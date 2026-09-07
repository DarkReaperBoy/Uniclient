package cores

import (
	"testing"
)

// The Bale core speaks a protobuf-ish wire format (pbEncode/pbDecode) where
// field numbers arrive as STRING keys ("1", "2", …) in maps. These tests pin
// the encoding contract used by wsConnect and every RPC helper:
//
//   - varint fields decode to int64
//   - length-delimited payloads are first parsed as nested messages; when the
//     payload parses, the value is a map and the raw bytes are kept under
//     "__raw_<field>" (wire type 2 is ambiguous between string and message)
//   - payloads that cannot parse as messages decode to string
//   - repeated fields accumulate into []interface{}

func TestPbEncodeDecodeVarints(t *testing.T) {
	// Values crossing single/multi-byte varint boundaries.
	for _, v := range []uint64{0, 1, 127, 128, 300, 16383, 16384, 1<<32 - 1, 1 << 32} {
		enc := pbEncode(map[string]interface{}{"1": int64(v)})
		dec := pbDecode(enc)
		got, ok := dec["1"].(int64)
		if !ok || got != int64(v) {
			t.Fatalf("varint %d: got %#v, want int64(%d)", v, dec["1"], v)
		}
	}
}

func TestPbEncodeDecodeBool(t *testing.T) {
	enc := pbEncode(map[string]interface{}{"2": true})
	dec := pbDecode(enc)
	got, ok := dec["2"].(int64)
	if !ok || got != 1 {
		t.Fatalf("bool true: got %#v, want int64(1)", dec["2"])
	}
}

func TestPbEncodeDecodeNested(t *testing.T) {
	enc := pbEncode(map[string]interface{}{
		"3": map[string]interface{}{
			"1": int64(1),
			"2": int64(2),
		},
	})
	dec := pbDecode(enc)
	nested, ok := dec["3"].(map[string]interface{})
	if !ok {
		t.Fatalf("nested field not decoded as map: %#v", dec["3"])
	}
	// Nested varints decode to int64.
	if nested["1"] != int64(1) || nested["2"] != int64(2) {
		t.Fatalf("nested values: %#v", nested)
	}
	// Raw bytes are preserved for ambiguous type-2 recovery.
	if raw, ok := dec["__raw_3"].([]byte); !ok || len(raw) == 0 {
		t.Fatalf("__raw_3 missing: %#v", dec["__raw_3"])
	}
}

func TestPbEncodeDecodeOpaqueBytes(t *testing.T) {
	// 0xDE has wire type 6 (invalid) — cannot parse as a nested message, so
	// the decoder must fall back to string.
	payload := []byte{0xDE, 0xAD, 0xBE, 0xEF}
	enc := pbEncode(map[string]interface{}{"4": payload})
	dec := pbDecode(enc)
	got, ok := dec["4"].(string)
	if !ok {
		t.Fatalf("opaque bytes not decoded as string fallback: %#v", dec["4"])
	}
	if got != string(payload) {
		t.Fatalf("fallback string mismatch: %q", got)
	}
}

func TestPbEncodeDecodePlainString(t *testing.T) {
	// A string whose bytes are not a valid protobuf message decodes to itself.
	s := "?? not protobuf ??"
	enc := pbEncode(map[string]interface{}{"5": s})
	dec := pbDecode(enc)
	if dec["5"] != s {
		t.Fatalf("string field: got %#v, want %q", dec["5"], s)
	}
}

func TestPbEncodeDecodeRepeatedVarint(t *testing.T) {
	enc := pbEncode(map[string]interface{}{"1": []interface{}{int64(7), int64(8), int64(9)}})
	dec := pbDecode(enc)
	got, ok := dec["1"].([]interface{})
	if !ok || len(got) != 3 {
		t.Fatalf("repeated varint: got %#v", dec["1"])
	}
	if got[0] != int64(7) || got[1] != int64(8) || got[2] != int64(9) {
		t.Fatalf("repeated values: %#v", got)
	}
}

func TestPbEncodeDecodeHandshake(t *testing.T) {
	// The actual wsConnect handshake frame:
	// ClientFrame{3: HandshakeRequest{1: mkprotoVersion, 2: apiVersion}}
	enc := pbEncode(map[string]interface{}{
		"3": map[string]interface{}{
			"1": int64(1),
			"2": int64(1),
		},
	})
	dec := pbDecode(enc)
	frame, ok := dec["3"].(map[string]interface{})
	if !ok {
		t.Fatalf("handshake frame: %#v", dec["3"])
	}
	if frame["1"] != int64(1) || frame["2"] != int64(1) {
		t.Fatalf("handshake fields: %#v", frame)
	}
}

func TestPbDecodeEmpty(t *testing.T) {
	dec := pbDecode(nil)
	if dec == nil || len(dec) != 0 {
		t.Fatalf("decode(nil) = %#v, want empty map", dec)
	}
}

func TestPbEncodeDeterministicFieldOrder(t *testing.T) {
	// Fields must be encoded in ascending field-number order regardless of
	// map iteration order (Go map order is randomized).
	one := pbEncode(map[string]interface{}{"1": int64(1), "5": int64(5), "9": int64(9)})
	other := pbEncode(map[string]interface{}{"9": int64(9), "1": int64(1), "5": int64(5)})
	if string(one) != string(other) {
		t.Fatalf("encoding is not deterministic:\n%x\n%x", one, other)
	}
}
