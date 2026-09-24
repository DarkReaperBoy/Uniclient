package lottie

// Hostile-input fuzzing for sticker animation parsers (slice 255):
// Telegram stickers are attacker-supplied content — ParseAnimationJSON
// and ParseTgs must never panic and never return (nil, nil) (§1.10).

import (
	"bytes"
	"compress/gzip"
	"testing"
)

func FuzzParseAnimationJSON(f *testing.F) {
	f.Add([]byte{})
	f.Add([]byte(`{}`))
	f.Add([]byte(`{"v":"5.7.4","fr":30,"ip":0,"op":60,"w":100,"h":100,"layers":[]}`))
	f.Add([]byte(`{"layers":[{"ty":4,"ks":{"p":{"k":[50,50]}}}]}`))
	f.Add([]byte("null"))
	f.Add([]byte("[1,2,3]"))
	f.Fuzz(func(t *testing.T, data []byte) {
		anim, err := ParseAnimationJSON(data)
		if err == nil && anim == nil {
			t.Fatal("ParseAnimationJSON returned no animation and no error — fabricated outcome (§1.10)")
		}
	})
}

func FuzzParseTgs(f *testing.F) {
	// Seed with a real gzip'd bodymovin document plus garbage.
	var buf bytes.Buffer
	zw := gzip.NewWriter(&buf)
	_, _ = zw.Write([]byte(`{"v":"5.7.4","fr":30,"ip":0,"op":60,"w":100,"h":100,"layers":[]}`))
	_ = zw.Close()
	f.Add(buf.Bytes())
	f.Add([]byte{})
	f.Add([]byte{0x1F, 0x8B, 0x08})
	f.Fuzz(func(t *testing.T, data []byte) {
		anim, err := ParseTgs(data)
		if err == nil && anim == nil {
			t.Fatal("ParseTgs returned no animation and no error — fabricated outcome (§1.10)")
		}
	})
}
