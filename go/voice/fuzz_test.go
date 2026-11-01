package voice

import "testing"

func FuzzDecodeFrame(f *testing.F) {
	f.Add([]byte{})
	f.Add([]byte{0x00})
	f.Add([]byte{0x7F, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF})
	f.Add(make([]byte, 40))
	f.Add(make([]byte, 1420))
	f.Fuzz(func(t *testing.T, data []byte) {
		dec := NewDecoder()
		samples, err := dec.Decode(data)
		if err == nil && samples == nil {
			t.Fatal("Decode returned no samples and no error — fabricated outcome (§1.10)")
		}
	})
}
