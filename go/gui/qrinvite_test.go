package gui

import (
	"errors"
	"os"
	"path/filepath"
	"testing"

	"uniclient/qrscan"
)

// qrFixture reads a fixture rendered by a FOREIGN encoder during slice
// 227's research (see research/qr_decoder.md); the shared testdata lives
// with the decoder package that pins its sha256s.
func qrFixture(t *testing.T, name string) []byte {
	t.Helper()
	b, err := os.ReadFile(filepath.Join("..", "qrscan", "testdata", name))
	if err != nil {
		t.Fatalf("read fixture %s: %v", name, err)
	}
	return b
}

// TestInviteHashFromQRImage: every QR shape the flow accepts or refuses.
// Positive rows must yield the exact invite hash the confirm card will
// check with the server; negative rows must fail with the right sentinel
// so the toast names the real problem (§1.10).
func TestInviteHashFromQRImage(t *testing.T) {
	cases := []struct {
		file     string
		wantHash string
		wantErr  error
	}{
		{"invite_piglig.png", "QrSc4nBenchH4sh", nil},
		{"invite_netstar.png", "AAAAAEhJT0luZml0ZQ", nil},
		{"invite_snykk_utf8.png", "ключ🔑hash", nil},
		{"invite_piglig_rot90.png", "QrSc4nBenchH4sh", nil},
		{"invite_netstar_jpeg40.png", "AAAAAEhJT0luZml0ZQ", nil},
		// decodes fine, but the payload is not an invite: a foreign
		// site, and a public t.me username (which the server search
		// resolves — an invite hash it is not).
		{"notinvite_piglig.png", "", ErrNotInvite},
		{"publiclink_netstar.png", "", ErrNotInvite},
		// an image with no symbol at all
		{"no_qr.png", "", qrscan.ErrNoQR},
	}
	for _, tc := range cases {
		got, err := inviteHashFromQRImage(qrFixture(t, tc.file))
		if tc.wantErr != nil {
			if !errors.Is(err, tc.wantErr) {
				t.Errorf("%s: err = %v, want %v", tc.file, err, tc.wantErr)
			}
			if got != "" {
				t.Errorf("%s: hash = %q with error, want empty", tc.file, got)
			}
			continue
		}
		if err != nil {
			t.Errorf("%s: unexpected error: %v", tc.file, err)
			continue
		}
		if got != tc.wantHash {
			t.Errorf("%s: hash = %q, want %q", tc.file, got, tc.wantHash)
		}
	}
}

// TestInviteHashFromQRImageNotImage keeps the two failure classes apart:
// non-image bytes must report ErrNotImage, never ErrNoQR.
func TestInviteHashFromQRImageNotImage(t *testing.T) {
	_, err := inviteHashFromQRImage([]byte("not an image at all"))
	if !errors.Is(err, qrscan.ErrNotImage) {
		t.Errorf("err = %v, want ErrNotImage", err)
	}
	if errors.Is(err, qrscan.ErrNoQR) {
		t.Errorf("err = %v must not claim no-QR for non-image bytes", err)
	}
}

// TestQRScanErrorText pins the toast copy for each failure class — the
// point of keeping the sentinels distinct is that the user is told which
// of the three real problems they hit.
func TestQRScanErrorText(t *testing.T) {
	cases := []struct {
		err  error
		want string
	}{
		{qrscan.ErrNotImage, "That file is not an image"},
		{qrscan.ErrNoQR, "No QR code found in that image"},
		{ErrNotInvite, "QR code is not an invite link"},
		{errors.New("disk exploded"), "Scan failed: disk exploded"},
	}
	for _, tc := range cases {
		if got := qrScanErrorText(tc.err); got != tc.want {
			t.Errorf("qrScanErrorText(%v) = %q, want %q", tc.err, got, tc.want)
		}
	}
}
