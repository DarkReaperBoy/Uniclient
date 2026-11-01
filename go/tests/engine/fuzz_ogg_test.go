package tests

import (
	"bytes"
	"testing"
	. "uniclient/engine"
)

func FuzzReadOggPage(f *testing.F) {
	f.Add([]byte{})
	f.Add([]byte("OggS"))
	f.Add([]byte{0, 0, 0, 0})
	f.Add(append([]byte("OggS"), make([]byte, 23)...))
	f.Add(append([]byte("OggS\x00"), make([]byte, 27)...))
	f.Fuzz(func(t *testing.T, data []byte) {
		page, err := ReadOggPage(bytes.NewReader(data), nil)
		if err == nil && page.ForTestGranule() < 0 {
			t.Fatal("readOggPage fabricated a negative granule without error (§1.10)")
		}
	})
}
