package tests

import (
	"context"
	"io"
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

	s := newGhScripted(t, func(w http.ResponseWriter, r *http.Request, _ []byte) {
		switch r.URL.Path {
		case "/user":
			w.Header().Set("Content-Type", "application/json")
			io.WriteString(w, `{"login":"octocat","id":5823,"type":"User"}`)
		case "/repos/octocat/octocat":
			w.Header().Set("Content-Type", "application/json")
			io.WriteString(w, `{"full_name":"octocat/octocat"}`)
		case "/notifications":
			w.Header().Set("Content-Type", "application/json")
			io.WriteString(w, `[]`)
		case "/dl":
			for i := 0; i < 100; i++ {
				if _, err := w.Write(make([]byte, 64<<10)); err != nil {
					return
				}
			}
		default:
			w.WriteHeader(404)
		}
	})
	g := s.authed(t, "ghp_dl")

	dest := filepath.Join(t.TempDir(), "dl.bin")
	err := g.DownloadFile(FileRef{URL: s.srv.URL + "/dl"}, dest, nil)
	if err == nil {
		t.Fatal("hostile endless stream accepted")
	}
	if !strings.Contains(err.Error(), "exceeds download ceiling") {
		t.Fatalf("unexpected error: %v", err)
	}
	if _, statErr := os.Stat(dest); statErr == nil {
		t.Fatal("partial file left behind after the rejected download")
	}

	var dl *ghServedReq
	reqs := s.served()
	for i := range reqs {
		if reqs[i].Path == "/dl" {
			dl = &reqs[i]
		}
	}
	if dl == nil {
		t.Fatal("download request never reached the server")
	}
	if dl.Auth != "Bearer ghp_dl" {
		t.Errorf("download Authorization = %q, want the authenticated token", dl.Auth)
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
