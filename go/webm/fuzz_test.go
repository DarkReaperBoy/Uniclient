package webm

// tests-first for BUGS.md B-17 — hostile-input fuzzing for the EBML
// parser (the repo had ZERO fuzz targets).
//
// Contract under fuzz: Parse must never panic, and it must never
// return (nil, nil) — an error or a real document, never fabricated
// structure (§1.10).

import "testing"

func FuzzParse(f *testing.F) {
	valid := append(render(ebmlHeader()), render(minimalDoc(1_000_000, []el{
		simpleBlock(1, 0, flagKey, []byte{0x42, 0x00}),
	}))...)
	f.Add(valid)
	f.Add([]byte{})
	f.Add([]byte{0x1A, 0x45, 0xDF, 0xA3})
	f.Add([]byte{0x1A, 0x45, 0xDF, 0xA3, 0x80})
	f.Add([]byte{0x1A, 0x45, 0xDF, 0xA3, 0x81, 0x01})
	f.Add([]byte("webm"))
	f.Add([]byte{0x18, 0x53, 0x80, 0x67, 0x01, 0xFF, 0xFF, 0xFF})
	f.Add([]byte{0x1F, 0x43, 0xB6, 0x75})
	f.Fuzz(func(t *testing.T, data []byte) {
		doc, err := Parse(data)
		if err == nil && doc == nil {
			t.Fatal("Parse returned no document and no error — fabricated outcome (§1.10)")
		}
	})
}
