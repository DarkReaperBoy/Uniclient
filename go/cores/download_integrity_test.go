package cores

import (
	"bytes"
	"errors"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// F-77/F-78 (slice 314): truncated downloads were accepted as complete
// and failed downloads left truncated partials at dest.
//
// F-77: the TeamSpeak file-transfer loop swallowed EVERY read error
// (`if readErr != nil { break }` then `return nil`) — a dropped
// connection mid-transfer produced a truncated file reported as a
// successful download; the server-declared size was parsed with the
// error IGNORED, so a missing/malformed size field looped zero times
// and "succeeded" with an EMPTY file. The TS3 FT protocol has no
// length framing of its own beyond that declared size — raw TCP, so
// net/http's Content-Length enforcement (which protects github/bale/
// xmpp) does not exist here.
//
// F-78: xmpp DownloadFileHTTP only removed the partial on the F-72
// ceiling path (write/read errors left it), matrix/deltachat
// DownloadFile left WriteFile mid-write partials, and the engine's
// executeDownload error branch never removed localPath.
//
// Seam-RED (WORKLOG 314): undefined: receiveTSFile / parseTSSize /
// ErrTruncated.

// --- F-77: TeamSpeak transfer integrity ---

func TestReceiveTSFileShortStreamFailsAndCleans(t *testing.T) {
	dest := filepath.Join(t.TempDir(), "f.bin")
	got, err := receiveTSFile(bytes.NewReader(bytes.Repeat([]byte{'x'}, 10)), dest, 100, nil)
	if !errors.Is(err, ErrTruncated) {
		t.Fatalf("short stream: err = %v, want ErrTruncated", err)
	}
	if got >= 100 {
		t.Fatalf("reported %d bytes of 100", got)
	}
	if _, serr := os.Stat(dest); serr == nil {
		t.Fatal("truncated file left behind after failed transfer")
	}
}

func TestReceiveTSFileExactStreamSucceeds(t *testing.T) {
	dest := filepath.Join(t.TempDir(), "f.bin")
	payload := bytes.Repeat([]byte{'y'}, 100)
	got, err := receiveTSFile(bytes.NewReader(payload), dest, 100, nil)
	if err != nil {
		t.Fatalf("exact stream: %v", err)
	}
	if got != 100 {
		t.Fatalf("wrote %d bytes, want 100", got)
	}
	data, rerr := os.ReadFile(dest)
	if rerr != nil || !bytes.Equal(data, payload) {
		t.Fatalf("dest = %v (%v), want exact payload", data, rerr)
	}
}

func TestReceiveTSFileZeroSizeMakesEmptyFile(t *testing.T) {
	dest := filepath.Join(t.TempDir(), "empty.bin")
	got, err := receiveTSFile(bytes.NewReader(nil), dest, 0, nil)
	if err != nil {
		t.Fatalf("legit empty file: %v", err)
	}
	if got != 0 {
		t.Fatalf("wrote %d bytes for a 0-byte file", got)
	}
	info, serr := os.Stat(dest)
	if serr != nil || info.Size() != 0 {
		t.Fatalf("empty file: stat=%v size=%v", serr, info)
	}
}

func TestReceiveTSFileNegativeSizeRejected(t *testing.T) {
	dest := filepath.Join(t.TempDir(), "f.bin")
	if _, err := receiveTSFile(bytes.NewReader(nil), dest, -1, nil); !errors.Is(err, ErrTruncated) {
		t.Fatalf("negative size: err = %v, want ErrTruncated", err)
	}
	if _, serr := os.Stat(dest); serr == nil {
		t.Fatal("file created for an invalid size")
	}
}

func TestParseTSSizeRejectsMalformed(t *testing.T) {
	if _, err := parseTSSize(""); !errors.Is(err, ErrTruncated) {
		t.Fatalf("empty size: err = %v, want ErrTruncated", err)
	}
	if _, err := parseTSSize("abc"); !errors.Is(err, ErrTruncated) {
		t.Fatalf("garbage size: err = %v, want ErrTruncated", err)
	}
	if _, err := parseTSSize("-5"); !errors.Is(err, ErrTruncated) {
		t.Fatalf("negative size: err = %v, want ErrTruncated", err)
	}
	if n, err := parseTSSize("0"); err != nil || n != 0 {
		t.Fatalf("size 0: got (%d, %v), want (0, nil)", n, err)
	}
	if n, err := parseTSSize("12345"); err != nil || n != 12345 {
		t.Fatalf("size 12345: got (%d, %v), want (12345, nil)", n, err)
	}
}

// --- F-78: failed downloads must not leave truncated partials ---

// TestFailedDownloadWritesCleanUpTheirPartial: source-scan pin — every
// DownloadFile error path that may have created dest must remove it
// (comments skipped; region = function body).
func TestFailedDownloadWritesCleanUpTheirPartial(t *testing.T) {
	regions := []struct{ file, fn, needle string }{
		{"matrix.go", "func (m *MatrixCore) DownloadFile(", "os.Remove(dest)"},
		{"deltachat.go", "func (d *DeltaChatCore) DownloadFile(", "os.Remove(dest)"},
		{"xmpp.go", "func (c *XMPPCore) DownloadFileHTTP(", "os.Remove(dest)"},
	}
	for _, r := range regions {
		src, err := os.ReadFile(r.file)
		if err != nil {
			t.Fatalf("read %s: %v", r.file, err)
		}
		text := string(src)
		start := strings.Index(text, r.fn)
		if start < 0 {
			t.Fatalf("%s: cannot find %s", r.file, r.fn)
		}
		end := strings.Index(text[start:], "\nfunc ")
		if end < 0 {
			t.Fatalf("%s: cannot find end of %s", r.file, r.fn)
		}
		body := text[start : start+end]
		clean := []string{}
		for _, line := range strings.Split(body, "\n") {
			trimmed := strings.TrimSpace(line)
			if strings.HasPrefix(trimmed, "//") {
				continue
			}
			clean = append(clean, trimmed)
		}
		joined := strings.Join(clean, "\n")
		if !strings.Contains(joined, r.needle) {
			t.Errorf("%s %s has no %q on its error paths — failed download leaves a truncated partial", r.file, r.fn, r.needle)
		}
	}
}

// --- F-77 upload half: exact-size send ---

type shortReader struct {
	data []byte
	pos  int
	err  error
}

func (r *shortReader) Read(p []byte) (int, error) {
	if r.pos >= len(r.data) {
		if r.err != nil {
			return 0, r.err
		}
		return 0, io.EOF
	}
	n := copy(p, r.data[r.pos:])
	r.pos += n
	return n, nil
}

type countingWriter struct{ n int }

func (w *countingWriter) Write(p []byte) (int, error) { w.n += len(p); return len(p), nil }

func TestSendTSFileShortSourceFails(t *testing.T) {
	w := &countingWriter{}
	got, err := sendTSFile(w, bytes.NewReader(bytes.Repeat([]byte{'z'}, 50)), 100, nil)
	if !errors.Is(err, ErrTruncated) {
		t.Fatalf("short source: err = %v, want ErrTruncated", err)
	}
	if got >= 100 {
		t.Fatalf("reported %d sent of 100", got)
	}
}

func TestSendTSFileExactSourceSucceeds(t *testing.T) {
	w := &countingWriter{}
	payload := bytes.Repeat([]byte{'z'}, 100)
	got, err := sendTSFile(w, bytes.NewReader(payload), 100, nil)
	if err != nil {
		t.Fatalf("exact source: %v", err)
	}
	if got != 100 || w.n != 100 {
		t.Fatalf("sent=%d written=%d, want 100/100", got, w.n)
	}
}

func TestSendTSFileOversizedSourceSendsExactlyDeclared(t *testing.T) {
	w := &countingWriter{}
	got, err := sendTSFile(w, bytes.NewReader(bytes.Repeat([]byte{'z'}, 200)), 100, nil)
	if err != nil {
		t.Fatalf("oversized source: %v", err)
	}
	if got != 100 || w.n != 100 {
		t.Fatalf("sent=%d written=%d, want exactly 100 (declared) — over-send breaks the protocol", got, w.n)
	}
}

func TestSendTSFileSizeZeroStreamsUntilEOF(t *testing.T) {
	w := &countingWriter{}
	got, err := sendTSFile(w, bytes.NewReader(bytes.Repeat([]byte{'z'}, 50)), 0, nil)
	if err != nil {
		t.Fatalf("legacy size-0 path: %v", err)
	}
	if got != 50 || w.n != 50 {
		t.Fatalf("sent=%d written=%d, want 50/50", got, w.n)
	}
}

func TestSendTSFileReadErrorFails(t *testing.T) {
	w := &countingWriter{}
	r := &shortReader{data: []byte("abc"), err: errors.New("disk exploded")}
	if _, err := sendTSFile(w, r, 100, nil); err == nil {
		t.Fatal("source read error swallowed — old loop reported a fake successful send")
	}
}
