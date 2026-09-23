package qrscan

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"image"
	"image/color"
	"os"
	"path/filepath"
	"testing"

	gozxing "github.com/makiuchi-d/gozxing"
	"github.com/makiuchi-d/gozxing/qrcode"
)

// Fixtures in testdata/ were rendered by THREE FOREIGN encoders during
// slice 227's research (piglig/go-qr, netstar-labs/qr, snykk/qr-generator)
// and committed with pinned SHA-256s — never by gozxing, which is the
// decoder under test. That keeps the test from grading its own homework;
// research/qr_decoder.md holds the cross-encoder bench that chose it.
var fixtures = []struct {
	file    string
	sha     string
	payload string
}{
	{"invite_piglig.png", "c2c9fe3d6a98442dbfb184cae38e060c39db510402974b004a3f3b7113b062e6", "https://t.me/+QrSc4nBenchH4sh"},
	{"invite_netstar.png", "534ff66c66eaf7d17f93b504ca84c15012a6bfe8be7818b5e3c028ae7f9db185", "https://t.me/joinchat/AAAAAEhJT0luZml0ZQ"},
	{"invite_snykk_utf8.png", "f1aea633f98718cdc428801c05629496e8d24a1c4d76f137b740f75dfd628b16", "https://t.me/+ключ🔑hash"},
	// same piglig symbol, rotated 90° (EXIF-style orientation) and a
	// netstar symbol round-tripped through JPEG q=40 (screenshot saved
	// as JPEG): the two real-world file shapes a user actually picks.
	{"invite_piglig_rot90.png", "1c21090efcb7deb2562003fcf8d02d63f07db1d488bebafdeb02fa34719918c5", "https://t.me/+QrSc4nBenchH4sh"},
	{"invite_netstar_jpeg40.png", "18519c76c1d6c2006002ad6e71fe1f42daf93286a757e086b44289424a769be6", "https://t.me/joinchat/AAAAAEhJT0luZml0ZQ"},
	{"notinvite_piglig.png", "ea156d0aaceafdaaa579d727acf89bb75e374132c926f5468b9d4313a216e756", "https://example.com/not-an-invite"},
	{"publiclink_netstar.png", "f8e5d85c60abea44794cfdd0679934e0374a2729d3387444df1f3638e659e808", "https://t.me/someuser"},
}

func readFixture(t *testing.T, file string) []byte {
	t.Helper()
	b, err := os.ReadFile(filepath.Join("testdata", file))
	if err != nil {
		t.Fatalf("read fixture %s: %v", file, err)
	}
	return b
}

// TestDecodeBytesFixtures pins each fixture's bytes (sha256) and demands
// the exact payload back — any drift in fixture or decoder fails loudly.
func TestDecodeBytesFixtures(t *testing.T) {
	for _, fx := range fixtures {
		b := readFixture(t, fx.file)
		sum := sha256.Sum256(b)
		if got := hex.EncodeToString(sum[:]); got != fx.sha {
			t.Errorf("%s: sha256 = %s, want %s", fx.file, got, fx.sha)
		}
		got, err := DecodeBytes(b)
		if err != nil {
			t.Errorf("%s: DecodeBytes: %v", fx.file, err)
			continue
		}
		if got != fx.payload {
			t.Errorf("%s: payload = %q, want %q", fx.file, got, fx.payload)
		}
	}
}

// TestDecodeBytesNoQR: a clean image with no symbol must map to ErrNoQR,
// not to a wrong payload and not to ErrNotImage.
func TestDecodeBytesNoQR(t *testing.T) {
	b := readFixture(t, "no_qr.png")
	sum := sha256.Sum256(b)
	if got, want := hex.EncodeToString(sum[:]), "35a6f747cf3c2a75353bfbf807fa80b3f53e993ea5911ff572011fbc63874154"; got != want {
		t.Fatalf("no_qr.png sha256 = %s, want %s", got, want)
	}
	_, err := DecodeBytes(b)
	if !errors.Is(err, ErrNoQR) {
		t.Errorf("no_qr.png: err = %v, want ErrNoQR", err)
	}
	if errors.Is(err, ErrNotImage) {
		t.Errorf("no_qr.png: %v must not report ErrNotImage (it is a valid image)", err)
	}
}

// TestDecodeBytesNotImage: non-image bytes must map to ErrNotImage so the
// GUI can say "not an image" instead of "no QR code" (real errors, §1.10).
func TestDecodeBytesNotImage(t *testing.T) {
	if _, err := DecodeBytes([]byte("definitely not an image")); !errors.Is(err, ErrNotImage) {
		t.Errorf("garbage: err = %v, want ErrNotImage", err)
	}
}

// TestDecodeFile exercises the path-based entry (the GUI reads picked
// files by path when the platform hands one over).
func TestDecodeFile(t *testing.T) {
	got, err := DecodeFile(filepath.Join("testdata", "invite_piglig.png"))
	if err != nil {
		t.Fatalf("DecodeFile: %v", err)
	}
	if want := "https://t.me/+QrSc4nBenchH4sh"; got != want {
		t.Errorf("DecodeFile = %q, want %q", got, want)
	}
	if _, err := DecodeFile(filepath.Join("testdata", "does-not-exist.png")); err == nil {
		t.Error("DecodeFile(missing): want error")
	}
}

// TestDecodeOwnWriterRoundTrip closes the loop the GUI will use if it
// ever renders a QR of its own: encode with the same library (gozxing's
// writer), decode back. The fixtures above stay foreign-encoded, so this
// wiring check cannot mask a decoder that only reads its own output.
func TestDecodeOwnWriterRoundTrip(t *testing.T) {
	const payload = "https://t.me/+OwnWriterRoundTrip"
	m, err := qrcode.NewQRCodeWriter().EncodeWithoutHint(payload, gozxing.BarcodeFormat_QR_CODE, 0, 0)
	if err != nil {
		t.Fatalf("encode: %v", err)
	}
	w, h := m.GetWidth(), m.GetHeight()
	if w <= 0 || h <= 0 {
		t.Fatalf("encode produced empty matrix %dx%d", w, h)
	}
	img := image.NewGray(image.Rect(0, 0, w, h))
	for y := 0; y < h; y++ {
		for x := 0; x < w; x++ {
			v := uint8(255)
			if m.Get(x, y) {
				v = 0
			}
			img.SetGray(x, y, color.Gray{Y: v})
		}
	}
	got, err := DecodeImage(img)
	if err != nil {
		t.Fatalf("DecodeImage: %v", err)
	}
	if got != payload {
		t.Errorf("round trip = %q, want %q", got, payload)
	}
}
