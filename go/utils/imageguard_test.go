package utils

import (
	"bytes"
	"encoding/binary"
	"hash/crc32"
	"image"
	"image/color"
	"image/png"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// F-74 (slice 311): image decoders allocate w×h×4 from the FILE
// HEADER before reading a single pixel — a hostile 800-byte PNG/JPEG
// declaring 65535×65535 asks for ~17 GB and OOMs the client. Byte
// caps (downloadCeiling, inlineThumbCap) do not help: the bomb is in
// the DIMENSIONS. Guard = DecodeConfig first (header only, no alloc),
// budget check, then Decode.
//
// Seam-RED (WORKLOG 311): undefined: DecodeImageGuarded.

// bombPNG returns a valid small PNG with patched IHDR dimensions
// (width=height=20000 = 400 MP) and a CORRECT CRC — the header is
// what the guard must reject before any decode/alloc happens.
func bombPNG(t *testing.T, dim uint32) []byte {
	t.Helper()
	var buf bytes.Buffer
	img := image.NewRGBA(image.Rect(0, 0, 8, 8))
	img.Set(0, 0, color.RGBA{R: 255, A: 255})
	if err := png.Encode(&buf, img); err != nil {
		t.Fatalf("encode: %v", err)
	}
	b := buf.Bytes()
	// IHDR: sig(8) + len(4) + "IHDR"(4) + w(4) + h(4) + 5 bytes + crc(4)
	binary.BigEndian.PutUint32(b[16:20], dim)
	binary.BigEndian.PutUint32(b[20:24], dim)
	// PNG chunk CRC covers chunk TYPE + DATA (b[12:29]) — data alone
	// was rejected as "invalid checksum" (self-caught in slice 311).
	crc := crc32.ChecksumIEEE(b[12:29])
	binary.BigEndian.PutUint32(b[29:33], crc)
	return b
}

func TestDecodeImageGuardedRejectsDimensionBomb(t *testing.T) {
	data := bombPNG(t, 20000) // 400 MP > budget
	_, _, err := DecodeImageGuarded(bytes.NewReader(data), 40_000_000)
	if err == nil {
		t.Fatal("dimension bomb accepted — a real decoder would allocate 1.6 GB")
	}
	if !strings.Contains(err.Error(), "image dimensions exceed") {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestDecodeImageGuardedAcceptsSmallImage(t *testing.T) {
	var buf bytes.Buffer
	if err := png.Encode(&buf, image.NewRGBA(image.Rect(0, 0, 32, 24))); err != nil {
		t.Fatalf("encode: %v", err)
	}
	img, format, err := DecodeImageGuarded(bytes.NewReader(buf.Bytes()), 40_000_000)
	if err != nil {
		t.Fatalf("small image rejected: %v", err)
	}
	if format != "png" {
		t.Fatalf("format = %q, want png", format)
	}
	if img.Bounds().Dx() != 32 || img.Bounds().Dy() != 24 {
		t.Fatalf("bounds = %v", img.Bounds())
	}
}

func TestImageWithinBudget(t *testing.T) {
	if !ImageWithinBudget(3840, 2160, 40_000_000) {
		t.Error("4K image rejected")
	}
	if ImageWithinBudget(65535, 65535, 40_000_000) {
		t.Error("4.3 Gpx accepted")
	}
	if ImageWithinBudget(0, 100, 40_000_000) {
		t.Error("zero width accepted")
	}
}

// TestDimensionBombWiringGone: source-scan pin — every GUI/QR decode
// site must go through DecodeImageGuarded; a bare image.Decode on
// wire/cache bytes re-opens the allocation bomb (comments skipped,
// slice-284 lesson).
func TestDimensionBombWiringGone(t *testing.T) {
	for _, dir := range []string{"../gui", "../qrscan"} {
		entries, err := os.ReadDir(dir)
		if err != nil {
			t.Fatalf("read %s: %v", dir, err)
		}
		for _, e := range entries {
			name := e.Name()
			if e.IsDir() || !strings.HasSuffix(name, ".go") || strings.HasSuffix(name, "_test.go") {
				continue
			}
			src, err := os.ReadFile(filepath.Join(dir, name))
			if err != nil {
				t.Fatalf("read %s/%s: %v", dir, name, err)
			}
			for _, line := range strings.Split(string(src), "\n") {
				trimmed := strings.TrimSpace(line)
				if strings.HasPrefix(trimmed, "//") {
					continue
				}
				if strings.Contains(line, "image.Decode(") && !strings.Contains(line, "DecodeConfig") {
					t.Errorf("%s/%s still decodes unguarded: %s", dir, name, trimmed)
				}
			}
		}
	}
}
