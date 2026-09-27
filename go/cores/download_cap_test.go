package cores

import (
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// F-72 (slice 309): downloads from the network copied resp.Body to
// disk with NO ceiling — github/bale/xmpp/rubika all unbounded. A
// hostile server (or a lying Content-Length) streams forever → the
// disk fills (the F-52/F-53 family: memory DoS got a cap in slice 283,
// disk DoS did not).
//
// Seam-RED (WORKLOG 309): undefined: downloadCeiling / ErrFileTooLarge
// / boundedCopy.

func TestBoundedCopyWithinLimit(t *testing.T) {
	old := downloadCeiling
	downloadCeiling = 1024
	defer func() { downloadCeiling = old }()

	dst := t.TempDir() + "/f"
	f, err := os.Create(dst)
	if err != nil {
		t.Fatalf("create: %v", err)
	}
	defer f.Close()
	n, err := boundedCopy(f, strings.NewReader(strings.Repeat("x", 512)), downloadCeiling)
	if err != nil {
		t.Fatalf("under-limit copy failed: %v", err)
	}
	if n != 512 {
		t.Fatalf("copied %d, want 512", n)
	}
}

func TestBoundedCopyStopsAtLimit(t *testing.T) {
	old := downloadCeiling
	downloadCeiling = 1024
	defer func() { downloadCeiling = old }()

	dst := t.TempDir() + "/f"
	f, err := os.Create(dst)
	if err != nil {
		t.Fatalf("create: %v", err)
	}
	defer f.Close()
	// 4 MiB stream against a 1 KiB ceiling.
	_, err = boundedCopy(f, strings.NewReader(strings.Repeat("x", 4<<20)), downloadCeiling)
	if err == nil {
		t.Fatal("oversized stream accepted — disk would fill")
	}
	if !strings.Contains(err.Error(), "exceeds download ceiling") {
		t.Fatalf("unexpected error: %v", err)
	}
	fi, _ := os.Stat(dst)
	if fi.Size() > downloadCeiling+1 {
		t.Fatalf("wrote %d bytes past the %d ceiling", fi.Size(), downloadCeiling)
	}
}

// TestXMPPDownloadHTTPCapsBody: behavioral — a hostile HTTP endpoint
// streaming forever must not fill the disk.
func TestXMPPDownloadHTTPCapsBody(t *testing.T) {
	old := downloadCeiling
	downloadCeiling = 1024
	defer func() { downloadCeiling = old }()

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Length", "999999999")
		for i := 0; i < 100; i++ {
			if _, err := w.Write(make([]byte, 64<<10)); err != nil {
				return
			}
		}
	}))
	defer srv.Close()

	dest := filepath.Join(t.TempDir(), "dl.bin")
	c := &XMPPCore{ctx: context.Background()}
	err := c.DownloadFileHTTP(srv.URL, dest, nil)
	if err == nil {
		t.Fatal("hostile endless stream accepted")
	}
	if !strings.Contains(err.Error(), "exceeds download ceiling") {
		t.Fatalf("unexpected error: %v", err)
	}
	if _, statErr := os.Stat(dest); statErr == nil {
		t.Fatal("partial file left behind after the rejected download")
	}
}

// TestGitHubDownloadCapsBody: same contract on the GitHub core.
func TestGitHubDownloadCapsBody(t *testing.T) {
	old := downloadCeiling
	downloadCeiling = 1024
	defer func() { downloadCeiling = old }()

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		for i := 0; i < 100; i++ {
			if _, err := w.Write(make([]byte, 64<<10)); err != nil {
				return
			}
		}
	}))
	defer srv.Close()

	dest := filepath.Join(t.TempDir(), "dl.bin")
	g := &GitHubCore{
		authed: true,
		ctx:    context.Background(),
		client: srv.Client(),
		token:  "t",
	}
	err := g.DownloadFile(FileRef{URL: srv.URL}, dest, nil)
	if err == nil {
		t.Fatal("hostile endless stream accepted")
	}
	if !strings.Contains(err.Error(), "exceeds download ceiling") {
		t.Fatalf("unexpected error: %v", err)
	}
	if _, statErr := os.Stat(dest); statErr == nil {
		t.Fatal("partial file left behind after the rejected download")
	}
}

// TestRawUnboundedDownloadsGone: source-scan pin — no core copies a
// network body to disk without the ceiling (comments skipped, slice-284
// lesson).
func TestRawUnboundedDownloadsGone(t *testing.T) {
	banned := []string{
		"written, err := io.Copy(f, resp.Body)", // github
		"_, err = io.Copy(outFile, reader)",     // bale
	}
	for file, raw := range map[string]string{
		"github.go": banned[0],
		"bale.go":   banned[1],
	} {
		src, err := os.ReadFile(file)
		if err != nil {
			t.Fatalf("read %s: %v", file, err)
		}
		for _, line := range strings.Split(string(src), "\n") {
			trimmed := strings.TrimSpace(line)
			if strings.HasPrefix(trimmed, "//") {
				continue
			}
			if strings.Contains(line, raw) {
				t.Errorf("%s still copies an unbounded body: %s", file, trimmed)
			}
		}
	}
	// xmpp manual loop must carry the ceiling check (needle = the
	// sentinel reference — the message text lives in base.go's
	// ErrFileTooLarge, first scan used the wrong needle and false-failed
	// while the behavioral test passed; self-caught slice 309).
	src, err := os.ReadFile("xmpp.go")
	if err != nil {
		t.Fatalf("read xmpp.go: %v", err)
	}
	if !strings.Contains(string(src), "ErrFileTooLarge") {
		t.Error("xmpp.go DownloadFileHTTP lost its ceiling check")
	}
	// rubika must copy exactly the requested chunk (CopyN), not the body.
	src, err = os.ReadFile("rubika.go")
	if err != nil {
		t.Fatalf("read rubika.go: %v", err)
	}
	if !strings.Contains(string(src), "io.CopyN(") {
		t.Error("rubika.go must use io.CopyN for bounded chunks")
	}
	_ = io.EOF
}
