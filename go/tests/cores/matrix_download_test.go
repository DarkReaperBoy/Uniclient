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

	"maunium.net/go/mautrix"
	"maunium.net/go/mautrix/id"
)

func TestDownloadFileCapsHostileBody(t *testing.T) {
	old := MatrixMediaMaxBytes
	MatrixMediaMaxBytes = 1024
	defer func() { MatrixMediaMaxBytes = old }()

	hs := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/octet-stream")
		_, _ = w.Write(make([]byte, 4096))
	}))
	defer hs.Close()

	client, err := mautrix.NewClient(hs.URL, id.UserID("@u:test"), "tok")
	if err != nil {
		t.Fatalf("NewClient: %v", err)
	}
	m := ForTestNewMatrixCore(true, nil, client, context.Background(), id.DeviceID(""), "", id.UserID(""))

	dest := filepath.Join(t.TempDir(), "media.bin")
	err = m.DownloadFile(FileRef{ID: "mxc://test/abc"}, dest, nil)
	if err == nil || !strings.Contains(err.Error(), "exceeds size limit") {
		t.Fatalf("oversized body: err = %v, want size-limit error", err)
	}
	if _, statErr := os.Stat(dest); statErr == nil {
		t.Fatal("dest was written despite the rejected download")
	}
}

func TestDownloadFileSmallBodyPasses(t *testing.T) {
	payload := []byte("small media payload")
	hs := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write(payload)
	}))
	defer hs.Close()

	client, err := mautrix.NewClient(hs.URL, id.UserID("@u:test"), "tok")
	if err != nil {
		t.Fatalf("NewClient: %v", err)
	}
	m := ForTestNewMatrixCore(true, nil, client, context.Background(), id.DeviceID(""), "", id.UserID(""))

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
