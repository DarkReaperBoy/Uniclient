package cores

import (
	"errors"
	"net/http"
	"os"
	"strings"
	"testing"
)

// F-75 (slice 313): API/metadata response bodies were read into memory
// with NO ceiling — 10 bare io.ReadAll(resp.Body) + 3 streaming
// json.NewDecoder(resp.Body) sites across xmpp/mumble/github/bale/
// matrix — and the discovery fetches used http.Get/http.Post/
// http.DefaultClient, which carry NO timeout at all (the slice-285
// timeout audit only counted http.Client{…} constructions — checker
// gap, self-caught slice 313). A hostile server streams gigabytes →
// OOM; a stalling server hangs the fetch forever.
//
// Seam-RED (WORKLOG 313): undefined: readBodyCapped / apiBodyCeiling /
// ErrBodyTooLarge / decodeJSONBody / apiHTTPClient / transferHTTPClient.

// endlessBody yields bytes forever. Safe: the capped reader stops at
// max+1 bytes, so the test never loops unbounded.
type endlessBody struct{}

func (e *endlessBody) Read(p []byte) (int, error) {
	for i := range p {
		p[i] = 'a'
	}
	return len(p), nil
}

func TestReadBodyCappedRejectsEndlessStream(t *testing.T) {
	old := apiBodyCeiling
	apiBodyCeiling = 1 << 10 // 1 KiB ceiling for this test
	defer func() { apiBodyCeiling = old }()

	body := &endlessBody{}

	data, err := readBodyCapped(body, apiBodyCeiling)
	if !errors.Is(err, ErrBodyTooLarge) {
		t.Fatalf("endless stream: err = %v, want ErrBodyTooLarge", err)
	}
	if data != nil {
		t.Fatalf("oversized read returned %d bytes, want nil", len(data))
	}
}

func TestReadBodyCappedWithinCeiling(t *testing.T) {
	payload := "hello ceiling"
	got, err := readBodyCapped(strings.NewReader(payload), 1024)
	if err != nil {
		t.Fatalf("within ceiling: %v", err)
	}
	if string(got) != payload {
		t.Fatalf("got %q, want %q", got, payload)
	}
	// exactly-at-ceiling passes (cap+1 sentinel semantics, F-53 pattern)
	got, err = readBodyCapped(strings.NewReader(payload), int64(len(payload)))
	if err != nil || string(got) != payload {
		t.Fatalf("exact ceiling: got %q err %v, want exact payload nil err", got, err)
	}
}

func TestDecodeJSONBodyCapsAndParses(t *testing.T) {
	old := apiBodyCeiling
	apiBodyCeiling = 64
	defer func() { apiBodyCeiling = old }()

	var ok map[string]interface{}
	if err := decodeJSONBody(strings.NewReader(`{"a":1}`), &ok); err != nil {
		t.Fatalf("small json: %v", err)
	}
	if ok["a"] != float64(1) {
		t.Fatalf("parsed %#v", ok)
	}

	body := &endlessBody{}
	var big map[string]interface{}
	err := decodeJSONBody(body, &big)
	if !errors.Is(err, ErrBodyTooLarge) {
		t.Fatalf("oversized json: err = %v, want ErrBodyTooLarge", err)
	}
}

// TestMetadataClientsCarryTimeouts: discovery/metadata fetches must not
// use the timeout-less DefaultClient (construction pins — no wall-clock
// waits, F-9).
func TestMetadataClientsCarryTimeouts(t *testing.T) {
	if apiHTTPClient.Timeout <= 0 {
		t.Error("apiHTTPClient has no Timeout — metadata fetch can hang forever")
	}
	tr, ok := transferHTTPClient.Transport.(*http.Transport)
	if !ok {
		t.Fatalf("transferHTTPClient.Transport is %T, want *http.Transport", transferHTTPClient.Transport)
	}
	if tr.ResponseHeaderTimeout <= 0 {
		t.Error("transferHTTPClient has no ResponseHeaderTimeout — a stalling upload/download target hangs the request forever")
	}
}

// TestBareBodyReadsAndUntimedFetchesGone: source-scan pin — no prod
// file reads a response body unbounded or fetches without a timeout
// client (comments skipped, slice-284 lesson; test files skipped).
func TestBareBodyReadsAndUntimedFetchesGone(t *testing.T) {
	banned := []string{
		"io.ReadAll(resp.Body)",
		"json.NewDecoder(resp.Body)",
		"http.Get(",
		"http.Post(",
		"http.DefaultClient",
		// IMAP literals + zip entries are server/file-controlled streams
		// too (hostile mail server / zip bomb → memory OOM, F-75).
		"io.ReadAll(it.Literal)",
		"io.ReadAll(bodySection.Literal)",
		"io.ReadAll(rc)",
	}
	dirs := []string{".", "../engine", "../gui", "../utils"}
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
