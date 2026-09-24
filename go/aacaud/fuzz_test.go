package aacaud

// Hostile-input fuzzing for the MP4/AAC audio parser (slice 255):
// Parse must never panic on crafted bytes and must never return
// (nil, nil) — fail one clip, never kill the client (§1.10).

import (
	"bytes"
	"testing"
)

func FuzzParse(f *testing.F) {
	// Minimal ftyp box + a truncated moov attempt + plain garbage.
	f.Add([]byte{})
	f.Add([]byte{0, 0, 0, 16, 'f', 't', 'y', 'p', 'i', 's', 'o', 'm', 0, 0, 2, 0})
	f.Add([]byte{0, 0, 0, 8, 'm', 'o', 'o', 'v'})
	f.Add([]byte{0, 0, 0, 24, 'f', 't', 'y', 'p', 'M', 'P', '4', 'A', 0, 0, 0, 0, 'i', 's', 'o', 'm', 0, 0, 0, 0})
	f.Add([]byte("short"))
	f.Fuzz(func(t *testing.T, data []byte) {
		track, err := Parse(bytes.NewReader(data))
		if err == nil && track == nil {
			t.Fatal("Parse returned no track and no error — fabricated outcome (§1.10)")
		}
	})
}
