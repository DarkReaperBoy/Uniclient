package vp9anim

import (
	"os"
	"path/filepath"
	"testing"
)

func FuzzParse(f *testing.F) {
	if entries, err := os.ReadDir("testdata"); err == nil {
		for _, e := range entries {
			if e.IsDir() {
				continue
			}
			if data, err := os.ReadFile(filepath.Join("testdata", e.Name())); err == nil && len(data) <= 64*1024 {
				f.Add(data)
			}
		}
	}
	f.Add([]byte{})
	f.Add([]byte{0x1A, 0x45, 0xDF, 0xA3})
	f.Add([]byte{0x18, 0x53, 0x80, 0x67})
	f.Add([]byte{0x42, 0x82, 0x77, 0x65, 0x62, 0x6D})
	f.Fuzz(func(t *testing.T, data []byte) {
		anim, err := Parse(data)
		if err == nil && anim == nil {
			t.Fatal("Parse returned no animation and no error — fabricated outcome (§1.10)")
		}
	})
}
