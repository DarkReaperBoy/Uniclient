package cores

import (
	"bytes"
	"encoding/base64"
	"testing"

	"github.com/ProtonMail/go-crypto/openpgp"
)

func TestParseRawHeadersNormalizesKeys(t *testing.T) {
	in := "Chat-Version: 1.2\r\n" +
		"CONTENT-DISPOSITION: attachment; filename=\"a b.png\"\r\n" +
		"autocrypt: v=1; k=KEY\r\n"
	h := parseRawHeaders([]byte(in))

	if v, ok := h["chat-version"]; !ok || v != "1.2" {
		t.Errorf("chat-version = %q present=%v — keys must be stored lowercase (B-29); map=%v", v, ok, h)
	}
	if _, ok := h["Chat-Version"]; ok {
		t.Errorf("original-case key survived: %v", h)
	}
	if v := h["content-disposition"]; v != `attachment; filename="a b.png"` {
		t.Errorf("content-disposition = %q", v)
	}
	if v := h["autocrypt"]; v != "v=1; k=KEY" {
		t.Errorf("autocrypt = %q", v)
	}
}

func TestParseRawHeadersValueSemantics(t *testing.T) {
	in := "Subject:   hello   world  \r\n" +
		"Chat-Content: \r\n" +
		"Chat-Group-Name: The \r\n" +
		"\tGroup Name\r\n" +
		"X-No-Collector\r\n" +
		"Chat-Edit: $edit-id:server\r\n"
	h := parseRawHeaders([]byte(in))

	if v := h["subject"]; v != "hello   world" {
		t.Errorf("subject = %q (want trimmed, inner spaces kept)", v)
	}
	if v, ok := h["chat-content"]; !ok || v != "" {
		t.Errorf("chat-content = %q present=%v (empty value must exist)", v, ok)
	}
	if v := h["chat-group-name"]; v != "The Group Name" {
		t.Errorf("folded continuation = %q, want %q", v, "The Group Name")
	}
	if v := h["chat-edit"]; v != "$edit-id:server" {
		t.Errorf("chat-edit lost after colon-less line: %q", v)
	}
}

func TestParseRawHeadersTrailingHeaderWithoutNewline(t *testing.T) {
	h := parseRawHeaders([]byte("First: 1\r\nSecond: 2"))
	if h["first"] != "1" || h["second"] != "2" {
		t.Errorf("h = %v", h)
	}
}

func TestParseRawHeadersEmptyInput(t *testing.T) {
	h := parseRawHeaders(nil)
	if len(h) != 0 {
		t.Errorf("empty input → %v", h)
	}
}

func TestAutocryptKeydataSurvivesHeaderFolding(t *testing.T) {
	ent, err := openpgp.NewEntity("Fold", "", "fold@example.org", nil)
	if err != nil {
		t.Fatalf("NewEntity: %v", err)
	}
	var keyBuf bytes.Buffer
	if err := ent.Serialize(&keyBuf); err != nil {
		t.Fatalf("Serialize: %v", err)
	}
	full := base64.StdEncoding.EncodeToString(keyBuf.Bytes())
	if len(full) < 200 {
		t.Fatalf("test key too short to fold: %d b64 chars", len(full))
	}

	var raw bytes.Buffer
	raw.WriteString("Autocrypt: addr=fold@example.org; prefer-encrypt=mutual; keydata=")
	rest := full
	first := true
	for len(rest) > 0 {
		if !first {
			raw.WriteString("\r\n\t")
		}
		n := 70
		if n > len(rest) {
			n = len(rest)
		}
		raw.WriteString(rest[:n])
		rest = rest[n:]
		first = false
	}
	raw.WriteString("\r\n\n")

	h := parseRawHeaders(raw.Bytes())
	got := h["autocrypt"]
	if got == "" {
		t.Fatal("autocrypt header lost by the parser")
	}

	d := NewDeltaChatCore(nil)
	d.updateAutocryptPeer("fold@example.org", "Fold", got)

	d.peerKeysMu.RLock()
	ps := d.peerStates["fold@example.org"]
	var stored []byte
	var hasEntity bool
	if ps != nil {
		stored = ps.PublicKey
		hasEntity = ps.entity != nil
	}
	d.peerKeysMu.RUnlock()

	if len(stored) == 0 {
		t.Fatalf("folded keydata never stored (B-31): decode failed silently — peer=%v header value %q…", ps, got[:min(80, len(got))])
	}
	if !bytes.Equal(stored, keyBuf.Bytes()) {
		t.Errorf("stored key does not equal the serialized key (%d vs %d bytes)", len(stored), keyBuf.Len())
	}
	if !hasEntity {
		t.Errorf("openpgp entity not parsed from the stored key")
	}
}

func FuzzParseRawHeaders(f *testing.F) {
	f.Add([]byte(""))
	f.Add([]byte("Subject: hi\r\nFrom: a@b\r\n\r\n"))
	f.Add([]byte("Chat-Group-Name: The \r\n\tGroup Name\r\n"))
	f.Add([]byte("X-No-Collector\r\nNext: v\r\n"))
	f.Add([]byte("Empty:\r\nBinary: \x00\xff\xfe\r\n"))
	f.Add([]byte{0x00, 0x0A, 0x0D, 0x3A})
	f.Add([]byte("K: " + string(make([]byte, 8192))))
	f.Fuzz(func(t *testing.T, data []byte) {
		_ = parseRawHeaders(data)
	})
}
