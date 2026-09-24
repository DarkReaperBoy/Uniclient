package engine

// Hostile-input fuzzing for the Ogg page reader (slice 255): voice
// messages are downloaded bytes — readOggPage must never panic and
// never fabricate a page (§1.10).

import (
	"bytes"
	"testing"
)

func FuzzReadOggPage(f *testing.F) {
	f.Add([]byte{})
	f.Add([]byte("OggS"))
	f.Add([]byte{0, 0, 0, 0})
	f.Add(append([]byte("OggS"), make([]byte, 23)...)) // header only, no segment table
	f.Add(append([]byte("OggS\x00"), make([]byte, 27)...))
	f.Fuzz(func(t *testing.T, data []byte) {
		page, err := readOggPage(bytes.NewReader(data), nil)
		if err == nil && page.granule < 0 {
			t.Fatal("readOggPage fabricated a negative granule without error (§1.10)")
		}
	})
}
