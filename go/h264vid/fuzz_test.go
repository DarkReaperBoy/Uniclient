package h264vid

// Hostile-input fuzzing for the video-note/sticker decoder (extension of
// the webm fuzz contract, slice 255): Parse must never panic — a crafted
// media file must fail one clip, never kill the client (§1.10) — and it
// must never return (nil, nil).

import "testing"

func FuzzParse(f *testing.F) {
	f.Add([]byte{})
	f.Add([]byte{0x00, 0x00, 0x00, 0x18, 'f', 't', 'y', 'p'})
	f.Add([]byte{0x1A, 0x45, 0xDF, 0xA3})
	f.Add([]byte("not a video at all"))
	f.Fuzz(func(t *testing.T, data []byte) {
		video, err := Parse(data)
		if err == nil && video == nil {
			t.Fatal("Parse returned no video and no error — fabricated outcome (§1.10)")
		}
	})
}
