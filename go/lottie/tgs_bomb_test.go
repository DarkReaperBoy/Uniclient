package lottie

import (
	"bytes"
	"compress/gzip"
	"strings"
	"testing"
)

// TestParseTgsCapsBomb: ParseTgs read the inflated sticker with a bare
// io.ReadAll — the download layer bounds the compressed bytes, but a
// hostile .tgs can inflate far beyond that (gzip-bomb sibling of F-53,
// slice-284). Legit stickers inflate to a few MB; the cap is 32 MiB.
//
// RED evidence (WORKLOG 284): seam-RED `undefined: tgsMaxDecompressed`;
// behavioral RED with the var present and the bare io.ReadAll swapped
// back: `err = lottie: json: ..., want decompressed-size error` (the
// old path inflated the whole bomb, then failed JSON with a different
// error).
func TestParseTgsCapsBomb(t *testing.T) {
	old := tgsMaxDecompressed
	tgsMaxDecompressed = 1024
	defer func() { tgsMaxDecompressed = old }()

	// Bomb: 1 MiB of zeros (valid gzip, nowhere-near-JSON payload).
	var buf bytes.Buffer
	zw := gzip.NewWriter(&buf)
	if _, err := zw.Write(make([]byte, 1<<20)); err != nil {
		t.Fatalf("write bomb: %v", err)
	}
	if err := zw.Close(); err != nil {
		t.Fatalf("close bomb: %v", err)
	}

	_, err := ParseTgs(buf.Bytes())
	if err == nil || !strings.Contains(err.Error(), "exceeds") {
		t.Fatalf("tgs bomb: err = %v, want decompressed-size error", err)
	}
}
