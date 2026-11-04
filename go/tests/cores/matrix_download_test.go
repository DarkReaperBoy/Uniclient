package tests

import (
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	. "uniclient/cores"

	"maunium.net/go/mautrix/id"
)

func TestDownloadFileCapsHostileBody(t *testing.T) {
	old := MatrixMediaMaxBytes
	MatrixMediaMaxBytes = 1024
	defer func() { MatrixMediaMaxBytes = old }()

	hs := httptest.NewServer(mxAuthSurface(id.UserID("@u:test"), id.DeviceID(""), http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/octet-stream")
		_, _ = w.Write(make([]byte, 4096))
	})))
	t.Cleanup(hs.Close)

	m := NewMatrixCore(nil)
	t.Cleanup(func() { _ = m.Close() })
	if err := m.Authenticate(AuthConfig{
		Mode:     AuthModeBot,
		BotToken: "tok",
		Extra:    map[string]string{"homeserver": hs.URL},
	}); err != nil {
		t.Fatalf("authenticate: %v", err)
	}

	dest := filepath.Join(t.TempDir(), "media.bin")
	err := m.DownloadFile(FileRef{ID: "mxc://test/abc"}, dest, nil)
	if err == nil || !strings.Contains(err.Error(), "exceeds size limit") {
		t.Fatalf("oversized body: err = %v, want size-limit error", err)
	}
	if _, statErr := os.Stat(dest); statErr == nil {
		t.Fatal("dest was written despite the rejected download")
	}
}

func TestDownloadFileSmallBodyPasses(t *testing.T) {
	payload := []byte("small media payload")
	hs := httptest.NewServer(mxAuthSurface(id.UserID("@u:test"), id.DeviceID(""), http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write(payload)
	})))
	t.Cleanup(hs.Close)

	m := NewMatrixCore(nil)
	t.Cleanup(func() { _ = m.Close() })
	if err := m.Authenticate(AuthConfig{
		Mode:     AuthModeBot,
		BotToken: "tok",
		Extra:    map[string]string{"homeserver": hs.URL},
	}); err != nil {
		t.Fatalf("authenticate: %v", err)
	}

	dest := filepath.Join(t.TempDir(), "media.bin")
	if err := m.DownloadFile(FileRef{ID: "mxc://test/abc"}, dest, nil); err != nil {
		t.Fatalf("DownloadFile: %v", err)
	}
	got, err := os.ReadFile(dest)
	if err != nil {
		t.Fatalf("read dest: %v", err)
	}
	if string(got) != string(payload) {
		t.Fatalf("dest = %q, want %q", got, payload)
	}
}
