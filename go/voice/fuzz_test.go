package voice

// Hostile-input fuzzing for the Opus voice-frame decoder (slice 255):
// remote voice packets are attacker-supplied — Decode must never panic
// and never fabricate samples without error (§1.10).

import "testing"

func FuzzDecodeFrame(f *testing.F) {
	f.Add([]byte{})
	f.Add([]byte{0x00})
	f.Add([]byte{0x7F, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF})
	f.Add(make([]byte, 40))   // plausible frame length, garbage payload
	f.Add(make([]byte, 1420)) // oversized frame
	f.Fuzz(func(t *testing.T, data []byte) {
		dec := NewDecoder() // fresh state per input: framing is per-stream
		samples, err := dec.Decode(data)
		if err == nil && samples == nil {
			t.Fatal("Decode returned no samples and no error — fabricated outcome (§1.10)")
		}
	})
}
