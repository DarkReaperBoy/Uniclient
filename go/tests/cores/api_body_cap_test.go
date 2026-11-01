package tests

import (
	"errors"
	"net/http"
	"os"
	"strings"
	"testing"
	. "uniclient/cores"
)

type endlessBody struct{}

func (e *endlessBody) Read(p []byte) (int, error) {
	for i := range p {
		p[i] = 'a'
	}
	return len(p), nil
}

func TestReadBodyCappedRejectsEndlessStream(t *testing.T) {
	old := ApiBodyCeiling
	ApiBodyCeiling = 1 << 10
	defer func() { ApiBodyCeiling = old }()

	body := &endlessBody{}

	data, err := ReadBodyCapped(body, ApiBodyCeiling)
	if !errors.Is(err, ErrBodyTooLarge) {
		t.Fatalf("endless stream: err = %v, want ErrBodyTooLarge", err)
	}
	if data != nil {
		t.Fatalf("oversized read returned %d bytes, want nil", len(data))
	}
}

func TestReadBodyCappedWithinCeiling(t *testing.T) {
	payload := "hello ceiling"
	got, err := ReadBodyCapped(strings.NewReader(payload), 1024)
	if err != nil {
		t.Fatalf("within ceiling: %v", err)
	}
	if string(got) != payload {
		t.Fatalf("got %q, want %q", got, payload)
	}
	got, err = ReadBodyCapped(strings.NewReader(payload), int64(len(payload)))
	if err != nil || string(got) != payload {
		t.Fatalf("exact ceiling: got %q err %v, want exact payload nil err", got, err)
	}
}

func TestDecodeJSONBodyCapsAndParses(t *testing.T) {
	old := ApiBodyCeiling
	ApiBodyCeiling = 64
	defer func() { ApiBodyCeiling = old }()

	var ok map[string]interface{}
	if err := DecodeJSONBody(strings.NewReader(`{"a":1}`), &ok); err != nil {
		t.Fatalf("small json: %v", err)
	}
	if ok["a"] != float64(1) {
		t.Fatalf("parsed %#v", ok)
	}

	body := &endlessBody{}
	var big map[string]interface{}
	err := DecodeJSONBody(body, &big)
	if !errors.Is(err, ErrBodyTooLarge) {
		t.Fatalf("oversized json: err = %v, want ErrBodyTooLarge", err)
	}
}

func TestMetadataClientsCarryTimeouts(t *testing.T) {
	if ApiHTTPClient.Timeout <= 0 {
		t.Error("ApiHTTPClient has no Timeout — metadata fetch can hang forever")
	}
	tr, ok := TransferHTTPClient.Transport.(*http.Transport)
	if !ok {
		t.Fatalf("TransferHTTPClient.Transport is %T, want *http.Transport", TransferHTTPClient.Transport)
	}
	if tr.ResponseHeaderTimeout <= 0 {
		t.Error("TransferHTTPClient has no ResponseHeaderTimeout — a stalling upload/download target hangs the request forever")
	}
}

func TestBareBodyReadsAndUntimedFetchesGone(t *testing.T) {
	banned := []string{
		"io.ReadAll(resp.Body)",
		"json.NewDecoder(resp.Body)",
		"http.Get(",
		"http.Post(",
		"http.DefaultClient",
		"io.ReadAll(it.Literal)",
		"io.ReadAll(bodySection.Literal)",
		"io.ReadAll(rc)",
	}
	dirs := []string{"../../cores", "../../engine", "../../utils"}
	for _, dir := range dirs {
		entries, err := os.ReadDir(dir)
		if err != nil {
			t.Fatalf("read %s: %v", dir, err)
		}
		for _, e := range entries {
			name := e.Name()
			if e.IsDir() || !strings.HasSuffix(name, ".go") || strings.HasSuffix(name, "_test.go") {
				continue
			}
			src, err := os.ReadFile(dir + "/" + name)
			if err != nil {
				t.Fatalf("read %s/%s: %v", dir, name, err)
			}
			for _, line := range strings.Split(string(src), "\n") {
				trimmed := strings.TrimSpace(line)
				if strings.HasPrefix(trimmed, "//") {
					continue
				}
				for _, b := range banned {
					if strings.Contains(line, b) {
						t.Errorf("%s/%s: bare pattern %q: %s", dir, name, b, trimmed)
					}
				}
			}
		}
	}
}
