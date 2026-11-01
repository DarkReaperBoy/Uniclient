package lottie

import (
	"bytes"
	"compress/gzip"
	"strings"
	"testing"
)

func TestParseTgsCapsBomb(t *testing.T) {
	old := tgsMaxDecompressed
	tgsMaxDecompressed = 1024
	defer func() { tgsMaxDecompressed = old }()

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
