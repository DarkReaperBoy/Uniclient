package cores

import (
	"context"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"maunium.net/go/mautrix"
	"maunium.net/go/mautrix/id"
)

// TestDownloadFileCapsHostileBody: DownloadFile used DownloadBytes,
// which streams the body with NO ceiling — mautrix's
// DefaultResponseSizeLimit never applies because DownloadWithParams
// sets DontReadResponse, so a hostile homeserver could stream an
// unbounded body and OOM the client (slice-283).
//
// RED evidence (two forms, both recorded in WORKLOG 283):
//   - seam-RED: with only this file present the build fails —
//     undefined: matrixMediaMaxBytes, ErrMediaTooLarge;
//   - behavioral RED: with the symbols added but DownloadBytes swapped
//     back in, this test reports the oversized body succeeding and
//     dest being written: `got nil, want size-limit error`.
func TestDownloadFileCapsHostileBody(t *testing.T) {
	// Tiny ceiling for the test; production value is 512 MiB (the same
	// DefaultResponseSizeLimit every other mautrix response gets).
	old := matrixMediaMaxBytes
	matrixMediaMaxBytes = 1024
	defer func() { matrixMediaMaxBytes = old }()

	hs := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/octet-stream")
		_, _ = w.Write(make([]byte, 4096)) // far beyond the ceiling
	}))
	defer hs.Close()

	client, err := mautrix.NewClient(hs.URL, id.UserID("@u:test"), "tok")
	if err != nil {
		t.Fatalf("NewClient: %v", err)
	}
	m := &MatrixCore{authed: true, client: client, ctx: context.Background()}

	dest := filepath.Join(t.TempDir(), "media.bin")
	err = m.DownloadFile(FileRef{ID: "mxc://test/abc"}, dest, nil)
	if err == nil || !strings.Contains(err.Error(), "exceeds size limit") {
		t.Fatalf("oversized body: err = %v, want size-limit error", err)
	}
	if _, statErr := os.Stat(dest); statErr == nil {
		t.Fatal("dest was written despite the rejected download")
	}
}

// TestDownloadFileSmallBodyPasses pins the happy path of the capped
// reader: a body under the ceiling must land byte-exact at dest.
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
	m := &MatrixCore{authed: true, client: client, ctx: context.Background()}

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
