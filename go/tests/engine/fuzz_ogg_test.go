package tests

import (
	"bytes"
	"testing"
	. "uniclient/engine"
)

func FuzzOggPacketReader(f *testing.F) {
	f.Add([]byte{})
	f.Add([]byte("OggS"))
	f.Add(append([]byte("OggS"), make([]byte, 23)...))
	f.Add(BuildOggPage([][]byte{[]byte("pkt")}, 960, 1, 0, true))
	f.Add(BuildOggPage([][]byte{bytes.Repeat([]byte{0xA5}, 300), []byte("tail")}, 1920, 7, 1, true))
	f.Fuzz(func(t *testing.T, data []byte) {
		rd := NewOggPacketReader(bytes.NewReader(data))
		var first error
		for first == nil {
			_, first = rd.Next()
		}
		if _, again := rd.Next(); again != first {
			t.Fatalf("reader error not sticky: %v then %v", first, again)
		}
	})
}
