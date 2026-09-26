package cores

import (
	"bytes"
	"compress/gzip"
	"os"
	"strings"
	"testing"
)

// TestGzipDecompressCapsBomb: gzipDecompress read its output with a
// bare io.ReadAll, and BOTH callers are network-controlled (MTProto
// layer + V2Reference signaling sniff for the gzip magic) — a hostile
// gzip bomb expanded unbounded in RAM (slice-284, the decompression
// sibling of F-53).
//
// RED evidence (both forms recorded in WORKLOG 284):
//   - seam-RED: undefined: tgGzipMaxDecompressed (symbol absent);
//   - behavioral RED: with the var present and the old bare ReadAll
//     swapped back: `gzip bomb: err = <nil>, want size-exceeded error`.
func TestGzipDecompressCapsBomb(t *testing.T) {
	old := tgGzipMaxDecompressed
	tgGzipMaxDecompressed = 1024
	defer func() { tgGzipMaxDecompressed = old }()

	// Classic bomb: 1 MiB of zeros compresses to ~1 KiB.
	var buf bytes.Buffer
	zw := gzip.NewWriter(&buf)
	if _, err := zw.Write(make([]byte, 1<<20)); err != nil {
		t.Fatalf("write bomb: %v", err)
	}
	if err := zw.Close(); err != nil {
		t.Fatalf("close bomb: %v", err)
	}

	out, err := gzipDecompress(buf.Bytes())
	if err == nil || !strings.Contains(err.Error(), "exceeds") {
		t.Fatalf("gzip bomb: err = %v, want size-exceeded error (out len %d)", err, len(out))
	}
}

// TestGzipDecompressHappyPath pins normal signaling payloads: a small
// legitimate gzip must still round-trip byte-exact.
func TestGzipDecompressHappyPath(t *testing.T) {
	payload := []byte(`{"@type":"offer","sdp":"v=0 o=- 1 1 IN IP4 0.0.0.0"}`)
	var buf bytes.Buffer
	zw := gzip.NewWriter(&buf)
	if _, err := zw.Write(payload); err != nil {
		t.Fatalf("write: %v", err)
	}
	if err := zw.Close(); err != nil {
		t.Fatalf("close: %v", err)
	}
	got, err := gzipDecompress(buf.Bytes())
	if err != nil {
		t.Fatalf("gzipDecompress: %v", err)
	}
	if !bytes.Equal(got, payload) {
		t.Fatalf("round-trip mismatch: got %q want %q", got, payload)
	}
}

// TestBaleUploadDrainIsBounded: the upload response used to be drained
// with a bare io.ReadAll (unbounded read of a server-controlled body
// whose result was discarded — a pure OOM sink). Source-scan pin: the
// call site must use the bounded drain. Comment lines are skipped —
// the first version of this scan matched its own explanatory comment
// (slice-284, self-caught false positive).
func TestBaleUploadDrainIsBounded(t *testing.T) {
	src, err := os.ReadFile("bale.go")
	if err != nil {
		t.Fatalf("read source: %v", err)
	}
	var wired bool
	for _, line := range strings.Split(string(src), "\n") {
		if strings.HasPrefix(strings.TrimSpace(line), "//") {
			continue // prose, not code
		}
		if strings.Contains(line, "io.ReadAll(uploadResp.Body)") {
			t.Errorf("bale.go still drains the upload response with unbounded io.ReadAll: %s", strings.TrimSpace(line))
		}
		if strings.Contains(line, "drainBodyLimited(uploadResp.Body)") {
			wired = true
		}
	}
	if !wired {
		t.Error("bale.go must drain the upload response through drainBodyLimited")
	}
}

// TestDrainBodyLimitedStopsAtMax: a server streaming an endless body
// must have at most baleDrainMax bytes consumed from it.
func TestDrainBodyLimitedStopsAtMax(t *testing.T) {
	old := baleDrainMax
	baleDrainMax = 1024
	defer func() { baleDrainMax = old }()

	rc := &infiniteBody{}
	drainBodyLimited(rc)
	if int64(rc.consumed) > baleDrainMax {
		t.Fatalf("consumed %d bytes, want at most %d", rc.consumed, baleDrainMax)
	}
	if rc.consumed == 0 {
		t.Fatal("drain consumed nothing — helper not reading (vacuous)")
	}
}

// infiniteBody is a ReadCloser that yields zeros forever and counts
// what was taken.
type infiniteBody struct {
	consumed int
}

func (r *infiniteBody) Read(p []byte) (int, error) {
	for i := range p {
		p[i] = 0
	}
	r.consumed += len(p)
	return len(p), nil
}

func (r *infiniteBody) Close() error { return nil }
