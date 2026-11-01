package tests

import (
	"context"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	. "uniclient/cores"
)

func TestBoundedCopyWithinLimit(t *testing.T) {
	old := DownloadCeiling
	DownloadCeiling = 1024
	defer func() { DownloadCeiling = old }()

	dst := t.TempDir() + "/f"
	f, err := os.Create(dst)
	if err != nil {
		t.Fatalf("create: %v", err)
	}
	defer f.Close()
	n, err := BoundedCopy(f, strings.NewReader(strings.Repeat("x", 512)), DownloadCeiling)
	if err != nil {
		t.Fatalf("under-limit copy failed: %v", err)
	}
	if n != 512 {
		t.Fatalf("copied %d, want 512", n)
	}
}

func TestBoundedCopyStopsAtLimit(t *testing.T) {
	old := DownloadCeiling
	DownloadCeiling = 1024
	defer func() { DownloadCeiling = old }()

	dst := t.TempDir() + "/f"
	f, err := os.Create(dst)
	if err != nil {
		t.Fatalf("create: %v", err)
	}
	defer f.Close()
	_, err = BoundedCopy(f, strings.NewReader(strings.Repeat("x", 4<<20)), DownloadCeiling)
	if err == nil {
		t.Fatal("oversized stream accepted — disk would fill")
	}
	if !strings.Contains(err.Error(), "exceeds download ceiling") {
		t.Fatalf("unexpected error: %v", err)
	}
	fi, _ := os.Stat(dst)
	if fi.Size() > DownloadCeiling+1 {
		t.Fatalf("wrote %d bytes past the %d ceiling", fi.Size(), DownloadCeiling)
	}
}

func TestXMPPDownloadHTTPCapsBody(t *testing.T) {
	old := DownloadCeiling
	DownloadCeiling = 1024
	defer func() { DownloadCeiling = old }()

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
	c := ForTestNewXMPPCore(nil, context.Background(), nil)
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

func TestGitHubDownloadCapsBody(t *testing.T) {
	old := DownloadCeiling
	DownloadCeiling = 1024
	defer func() { DownloadCeiling = old }()

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		for i := 0; i < 100; i++ {
			if _, err := w.Write(make([]byte, 64<<10)); err != nil {
				return
			}
		}
	}))
	defer srv.Close()

	dest := filepath.Join(t.TempDir(), "dl.bin")
	g := ForTestNewGitHubCore(true, srv.Client(), context.Background(), "t")
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

func TestRawUnboundedDownloadsGone(t *testing.T) {
	banned := []string{
		"written, err := io.Copy(f, resp.Body)",
		"_, err = io.Copy(outFile, reader)",
	}
	for file, raw := range map[string]string{
		"../../cores/github.go": banned[0],
		"../../cores/bale.go":   banned[1],
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
	src, err := os.ReadFile("../../cores/xmpp.go")
	if err != nil {
		t.Fatalf("read xmpp.go: %v", err)
	}
	if !strings.Contains(string(src), "ErrFileTooLarge") {
		t.Error("xmpp.go DownloadFileHTTP lost its ceiling check")
	}
}
