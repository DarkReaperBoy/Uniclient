package utils

import (
	"testing"
)

func TestVP8EncodeKeyframe(t *testing.T) {
	tests := []struct {
		name   string
		width  int
		height int
	}{
		{"16x16", 16, 16},
		{"320x240", 320, 240},
		{"640x480", 640, 480},
		{"1280x720", 1280, 720},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			enc, err := NewVP8Enc(tc.width, tc.height, 500000)
			if err != nil {
				t.Fatalf("NewVP8Enc: %v", err)
			}

			yuv := make([]byte, tc.width*tc.height*3/2)
			frame, err := enc.Encode(yuv, tc.width, tc.height)
			if err != nil {
				t.Fatalf("Encode: %v", err)
			}

			if len(frame) < 10 {
				t.Fatalf("frame too short: %d bytes", len(frame))
			}

			// Verify frame tag
			if frame[0]&1 != 0 {
				t.Error("frame_type bit should be 0 (keyframe)")
			}
			if (frame[0]>>4)&1 != 1 {
				t.Error("show_frame bit should be 1")
			}

			// Verify start code
			if frame[3] != 0x9D || frame[4] != 0x01 || frame[5] != 0x2A {
				t.Errorf("bad start code: %02X %02X %02X", frame[3], frame[4], frame[5])
			}

			// Verify width/height from uncompressed header
			w := int(frame[6]) | int(frame[7])<<8
			w &= 0x3FFF // mask out scale bits
			h := int(frame[8]) | int(frame[9])<<8
			h &= 0x3FFF
			if w != tc.width {
				t.Errorf("width: got %d, want %d", w, tc.width)
			}
			if h != tc.height {
				t.Errorf("height: got %d, want %d", h, tc.height)
			}

			// Verify first_part_size makes sense
			firstPartSize := int(frame[0]>>5) | int(frame[1])<<3 | int(frame[2])<<11
			expectedMinTokenPart := 10 + firstPartSize
			if expectedMinTokenPart > len(frame) {
				t.Errorf("first_part_size %d exceeds frame length %d", firstPartSize, len(frame))
			}

			t.Logf("frame size: %d bytes, first_part: %d bytes", len(frame), firstPartSize)

			// Multiple encodes should produce identical output
			frame2, _ := enc.Encode(yuv, tc.width, tc.height)
			if len(frame) != len(frame2) {
				t.Errorf("non-deterministic: %d vs %d bytes", len(frame), len(frame2))
			}
		})
	}
}

func TestVP8EncDifferentSizes(t *testing.T) {
	// Odd sizes that aren't macroblock-aligned
	for _, sz := range [][2]int{{17, 17}, {100, 75}, {319, 239}} {
		enc, err := NewVP8Enc(sz[0], sz[1], 0)
		if err != nil {
			t.Fatalf("NewVP8Enc(%d,%d): %v", sz[0], sz[1], err)
		}
		yuv := make([]byte, sz[0]*sz[1]*3/2)
		frame, err := enc.Encode(yuv, sz[0], sz[1])
		if err != nil {
			t.Fatalf("Encode(%d,%d): %v", sz[0], sz[1], err)
		}
		if len(frame) < 10 {
			t.Fatalf("frame too short for %dx%d: %d bytes", sz[0], sz[1], len(frame))
		}
		t.Logf("%dx%d → %d bytes", sz[0], sz[1], len(frame))
	}
}

func BenchmarkVP8Encode320x240(b *testing.B) {
	enc, _ := NewVP8Enc(320, 240, 0)
	yuv := make([]byte, 320*240*3/2)
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		enc.Encode(yuv, 320, 240)
	}
}
