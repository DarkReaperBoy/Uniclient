package tests

import (
	"testing"
	. "uniclient/cores"
)

func TestPbEncodeDecodeVarints(t *testing.T) {
	for _, v := range []uint64{0, 1, 127, 128, 300, 16383, 16384, 1<<32 - 1, 1 << 32} {
		enc := ForTestPbEncode(map[string]interface{}{"1": int64(v)})
		dec := ForTestPbDecode(enc)
		got, ok := dec["1"].(int64)
		if !ok || got != int64(v) {
			t.Fatalf("varint %d: got %#v, want int64(%d)", v, dec["1"], v)
		}
	}
}

func TestPbEncodeDecodeBool(t *testing.T) {
	enc := ForTestPbEncode(map[string]interface{}{"2": true})
	dec := ForTestPbDecode(enc)
	got, ok := dec["2"].(int64)
	if !ok || got != 1 {
		t.Fatalf("bool true: got %#v, want int64(1)", dec["2"])
	}
}

func TestPbEncodeDecodeNested(t *testing.T) {
	enc := ForTestPbEncode(map[string]interface{}{
		"3": map[string]interface{}{
			"1": int64(1),
			"2": int64(2),
		},
	})
	dec := ForTestPbDecode(enc)
	nested, ok := dec["3"].(map[string]interface{})
	if !ok {
		t.Fatalf("nested field not decoded as map: %#v", dec["3"])
	}
	if nested["1"] != int64(1) || nested["2"] != int64(2) {
		t.Fatalf("nested values: %#v", nested)
	}
	if raw, ok := dec["__raw_3"].([]byte); !ok || len(raw) == 0 {
		t.Fatalf("__raw_3 missing: %#v", dec["__raw_3"])
	}
}

func TestPbEncodeDecodeOpaqueBytes(t *testing.T) {
	payload := []byte{0xDE, 0xAD, 0xBE, 0xEF}
	enc := ForTestPbEncode(map[string]interface{}{"4": payload})
	dec := ForTestPbDecode(enc)
	got, ok := dec["4"].(string)
	if !ok {
		t.Fatalf("opaque bytes not decoded as string fallback: %#v", dec["4"])
	}
	if got != string(payload) {
		t.Fatalf("fallback string mismatch: %q", got)
	}
}

func TestPbEncodeDecodePlainString(t *testing.T) {
	s := "?? not protobuf ??"
	enc := ForTestPbEncode(map[string]interface{}{"5": s})
	dec := ForTestPbDecode(enc)
	if dec["5"] != s {
		t.Fatalf("string field: got %#v, want %q", dec["5"], s)
	}
}

func TestPbEncodeDecodeRepeatedVarint(t *testing.T) {
	enc := ForTestPbEncode(map[string]interface{}{"1": []interface{}{int64(7), int64(8), int64(9)}})
	dec := ForTestPbDecode(enc)
	got, ok := dec["1"].([]interface{})
	if !ok || len(got) != 3 {
		t.Fatalf("repeated varint: got %#v", dec["1"])
	}
	if got[0] != int64(7) || got[1] != int64(8) || got[2] != int64(9) {
		t.Fatalf("repeated values: %#v", got)
	}
}

func TestPbEncodeDecodeHandshake(t *testing.T) {
	enc := ForTestPbEncode(map[string]interface{}{
		"3": map[string]interface{}{
			"1": int64(1),
			"2": int64(1),
		},
	})
	dec := ForTestPbDecode(enc)
	frame, ok := dec["3"].(map[string]interface{})
	if !ok {
		t.Fatalf("handshake frame: %#v", dec["3"])
	}
	if frame["1"] != int64(1) || frame["2"] != int64(1) {
		t.Fatalf("handshake fields: %#v", frame)
	}
}

func TestPbDecodeEmpty(t *testing.T) {
	dec := ForTestPbDecode(nil)
	if dec == nil || len(dec) != 0 {
		t.Fatalf("decode(nil) = %#v, want empty map", dec)
	}
}

func TestPbEncodeDeterministicFieldOrder(t *testing.T) {
	one := ForTestPbEncode(map[string]interface{}{"1": int64(1), "5": int64(5), "9": int64(9)})
	other := ForTestPbEncode(map[string]interface{}{"9": int64(9), "1": int64(1), "5": int64(5)})
	if string(one) != string(other) {
		t.Fatalf("encoding is not deterministic:\n%x\n%x", one, other)
	}
}

func TestBaleExportedPbWrappers(t *testing.T) {
	enc := PbEncode(map[string]interface{}{"1": "hello", "2": int64(42)})
	m := PbDecode(enc)
	if PbGetString(m, "1") != "hello" {
		t.Errorf("PbGetString = %q, want hello", PbGetString(m, "1"))
	}
	if PbGetInt64(m, "2") != 42 {
		t.Errorf("PbGetInt64 = %d, want 42", PbGetInt64(m, "2"))
	}

	list := PbEncode(map[string]interface{}{"3": []interface{}{"a", "b"}})
	ml := PbDecode(list)
	if got := PbGetList(ml, "3"); len(got) != 2 {
		t.Errorf("PbGetList = %v, want 2 entries", got)
	}

	nested := PbEncode(map[string]interface{}{"7": map[string]interface{}{"9": "x"}})
	mn := PbDecode(nested)
	sub := PbGetMsg(mn, "7")
	if sub == nil || PbGetString(sub, "9") != "x" {
		t.Errorf("PbGetMsg round-trip = %v", sub)
	}

	if rid, dateMs, mid := ParseMsgIDFullExported("123:1700000000123:456"); rid != 123 || dateMs != 1700000000123 || mid != 456 {
		t.Errorf("ParseMsgIDFullExported = %d/%d/%d", rid, dateMs, mid)
	}
}
