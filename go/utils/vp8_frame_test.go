package utils

import (
	"bytes"
	"fmt"
	"testing"

	"golang.org/x/image/vp8"
)

func TestVP8FrameStructure(t *testing.T) {
	w, h := 16, 16
	for _, y := range []int{128, 127, 120, 8, 0, 255} {
		t.Run(fmt.Sprintf("Y=%d", y), func(t *testing.T) {
			enc, _ := NewVP8Enc(w, h, 500000)
			yuv := make([]byte, w*h*3/2)
			for i := 0; i < w*h; i++ {
				yuv[i] = byte(y)
			}
			for i := w * h; i < len(yuv); i++ {
				yuv[i] = 128
			}

			frame, _ := enc.Encode(yuv, w, h)

			// Parse frame header manually
			tag := uint32(frame[0]) | uint32(frame[1])<<8 | uint32(frame[2])<<16
			keyframe := (tag & 1) == 0
			version := (tag >> 1) & 7
			showFrame := (tag>>4)&1 == 1
			firstPartLen := tag >> 5

			t.Logf("Y=%d: frame=%d bytes, kf=%v ver=%d show=%v firstPartLen=%d",
				y, len(frame), keyframe, version, showFrame, firstPartLen)
			t.Logf("  header: %x", frame[:10])
			t.Logf("  firstPart (%d bytes): %x", firstPartLen, frame[10:10+firstPartLen])
			tokenStart := 10 + firstPartLen
			t.Logf("  tokenPart (%d bytes): %x", len(frame)-int(tokenStart), frame[tokenStart:])

			// Compute what qY2 should be
			qpIdx := 10
			dcQ := int(vp8DCQLookup[qpIdx])
			y2DCQ := dcQ * 2
			if y2DCQ < 8 {
				y2DCQ = 8
			}
			resY := y - 128
			qY2 := 0
			if resY > 0 {
				qY2 = (resY*4 + y2DCQ/2) / y2DCQ
			} else if resY < 0 {
				qY2 = (resY*4 - y2DCQ/2) / y2DCQ
			}
			if qY2 > 127 {
				qY2 = 127
			} else if qY2 < -127 {
				qY2 = -127
			}
			hasCoeff := qY2 != 0
			t.Logf("  resY=%d qY2=%d hasCoeff=%v", resY, qY2, hasCoeff)

			// Try decode
			dec := vp8.NewDecoder()
			dec.Init(bytes.NewReader(frame), len(frame))
			fh, err := dec.DecodeFrameHeader()
			if err != nil {
				t.Fatalf("  header err: %v", err)
			}
			t.Logf("  decoded header: %dx%d", fh.Width, fh.Height)

			_, err = dec.DecodeFrame()
			if err != nil {
				t.Errorf("  FAIL: %v", err)
			} else {
				t.Logf("  PASS")
			}
		})
	}
}

// Test that first partition is identical between passing and failing cases
func TestVP8FirstPartConsistency(t *testing.T) {
	w, h := 16, 16

	// Generate frames for Y=128 (pass) and Y=8 (fail)
	for _, y := range []int{128, 8} {
		enc, _ := NewVP8Enc(w, h, 500000)
		yuv := make([]byte, w*h*3/2)
		for i := 0; i < w*h; i++ {
			yuv[i] = byte(y)
		}
		for i := w * h; i < len(yuv); i++ {
			yuv[i] = 128
		}

		frame, _ := enc.Encode(yuv, w, h)
		tag := uint32(frame[0]) | uint32(frame[1])<<8 | uint32(frame[2])<<16
		firstPartLen := tag >> 5

		t.Logf("Y=%d: firstPart(%d)=%x tokenPart(%d)=%x",
			y, firstPartLen, frame[10:10+firstPartLen],
			len(frame)-int(10+firstPartLen), frame[10+firstPartLen:])
	}
}
