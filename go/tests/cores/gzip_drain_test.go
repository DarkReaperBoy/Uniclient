package tests

import (
	"bytes"
	"compress/gzip"
	"os"
	"strings"
	"testing"
	. "uniclient/cores"
)

func TestGzipDecompressCapsBomb(t *testing.T) {
	old := TgGzipMaxDecompressed
	TgGzipMaxDecompressed = 1024
	defer func() { TgGzipMaxDecompressed = old }()

	var buf bytes.Buffer
	zw := gzip.NewWriter(&buf)
	if _, err := zw.Write(make([]byte, 1<<20)); err != nil {
		t.Fatalf("write bomb: %v", err)
	}
	if err := zw.Close(); err != nil {
		t.Fatalf("close bomb: %v", err)
	}

	out, err := GzipDecompress(buf.Bytes())
	if err == nil || !strings.Contains(err.Error(), "exceeds") {
		t.Fatalf("gzip bomb: err = %v, want size-exceeded error (out len %d)", err, len(out))
	}
}

func TestGzipDecompressHappyPath(t *testing.T) {
	payload := []byte(`{"@type":"offer","sdp":"v=0 o=- 1 1 IN IP4 0.0.0.0"}`)
	var buf bytes.Buffer
	zw := gzip.NewWriter(&buf)
	if _, err := zw.Write(payload); err != nil {
		t.Fatalf("write: %v", err)
	}
	if err := zw.Close(); err != nil {
		t.Fatalf("close: %v", err)
	}
	got, err := GzipDecompress(buf.Bytes())
	if err != nil {
		t.Fatalf("GzipDecompress: %v", err)
	}
	if !bytes.Equal(got, payload) {
		t.Fatalf("round-trip mismatch: got %q want %q", got, payload)
	}
}

func TestBaleUploadDrainIsBounded(t *testing.T) {
	src, err := os.ReadFile("../../cores/bale.go")
	if err != nil {
		t.Fatalf("read source: %v", err)
	}
	var wired bool
	for _, line := range strings.Split(string(src), "\n") {
		if strings.HasPrefix(strings.TrimSpace(line), "//") {
			continue
		}
		if strings.Contains(line, "io.ReadAll(uploadResp.Body)") {
			t.Errorf("bale.go still drains the upload response with unbounded io.ReadAll: %s", strings.TrimSpace(line))
		}
		if strings.Contains(line, "DrainBodyLimited(uploadResp.Body)") {
			wired = true
		}
	}
	if !wired {
		t.Error("bale.go must drain the upload response through DrainBodyLimited")
	}
}

func TestDrainBodyLimitedStopsAtMax(t *testing.T) {
	old := BaleDrainMax
	BaleDrainMax = 1024
	defer func() { BaleDrainMax = old }()

	rc := &infiniteBody{}
	DrainBodyLimited(rc)
	if int64(rc.consumed) > BaleDrainMax {
		t.Fatalf("consumed %d bytes, want at most %d", rc.consumed, BaleDrainMax)
	}
	if rc.consumed == 0 {
		t.Fatal("drain consumed nothing — helper not reading (vacuous)")
	}
}

type infiniteBody struct {
	consumed int
}

func (r *infiniteBody) Read(p []byte) (int, error) {
	for i := range p {
		p[i] = 0
	}
	r.consumed += len(p)
	return len(p), nil
}

func (r *infiniteBody) Close() error { return nil }
