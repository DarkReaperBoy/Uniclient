package utils

import (
	"bytes"
	"fmt"
	"testing"

	"golang.org/x/image/vp8"
)

func TestVP8GradientSizes(t *testing.T) {
	sizes := [][2]int{{16, 16}, {32, 16}, {32, 32}, {64, 16}, {64, 64}, {160, 120}, {320, 240}}
	for _, sz := range sizes {
		w, h := sz[0], sz[1]
		t.Run(fmt.Sprintf("%dx%d", w, h), func(t *testing.T) {
			enc, _ := NewVP8Enc(w, h, 500000)
			yuv := make([]byte, w*h*3/2)
			for y := 0; y < h; y++ {
				for x := 0; x < w; x++ {
					yuv[y*w+x] = byte(x * 255 / w)
				}
			}
			off := w * h
			for i := off; i < len(yuv); i++ {
				yuv[i] = 128
			}

			frame, err := enc.Encode(yuv, w, h)
			if err != nil {
				t.Fatalf("Encode: %v", err)
			}

			dec := vp8.NewDecoder()
			dec.Init(bytes.NewReader(frame), len(frame))
			_, err = dec.DecodeFrameHeader()
			if err != nil {
				t.Fatalf("header: %v", err)
			}
			_, err = dec.DecodeFrame()
			if err != nil {
				t.Errorf("FAIL: %v", err)
			}
		})
	}
}

func TestVP8_PadTokenPartition(t *testing.T) {
	// Test if adding padding to the token partition fixes decode
	w, h := 128, 32
	enc, _ := NewVP8Enc(w, h, 500000)
	yuv := make([]byte, w*h*3/2)
	for y := 0; y < h; y++ {
		for x := 0; x < w; x++ {
			if y < 16 {
				yuv[y*w+x] = 100
			} else {
				yuv[y*w+x] = 114
			}
		}
	}
	for i := w * h; i < len(yuv); i++ {
		yuv[i] = 128
	}

	frame, _ := enc.Encode(yuv, w, h)
	tag := uint32(frame[0]) | uint32(frame[1])<<8 | uint32(frame[2])<<16
	fp := tag >> 5
	t.Logf("original: frame=%d fp=%d tp=%d token=%x", len(frame), fp, len(frame)-int(10+fp), frame[10+fp:])

	// Try with extra padding bytes
	for pad := 0; pad <= 8; pad++ {
		padded := make([]byte, len(frame)+pad)
		copy(padded, frame)
		dec := vp8.NewDecoder()
		dec.Init(bytes.NewReader(padded), len(padded))
		dec.DecodeFrameHeader()
		_, err := dec.DecodeFrame()
		if err != nil {
			t.Logf("pad=%d: FAIL", pad)
		} else {
			t.Logf("pad=%d: PASS", pad)
		}
	}
}

func TestVP8_SmallMultiNonSkip(t *testing.T) {
	// Find smallest frame with 2+ non-skip MBs that fails
	// Use two-row frame where top=Y1, bottom=Y2 to force both MBs non-skip
	for _, tc := range []struct {
		name     string
		w, h     int
		topY     byte
		bottomY  byte
	}{
		{"16x32_100_114", 16, 32, 100, 114},
		{"32x32_100_114", 32, 32, 100, 114},
		{"16x32_100_200", 16, 32, 100, 200},
		{"32x32_100_200", 32, 32, 100, 200},
		{"16x32_50_200", 16, 32, 50, 200},
		{"32x32_50_200", 32, 32, 50, 200},
		{"48x32_100_114", 48, 32, 100, 114},
		{"64x32_100_114", 64, 32, 100, 114},
		{"80x32_100_114", 80, 32, 100, 114},
		{"160x32_100_114", 160, 32, 100, 114},
		{"96x32_100_114", 96, 32, 100, 114},
		{"112x32_100_114", 112, 32, 100, 114},
		{"128x32_100_114", 128, 32, 100, 114},
		{"144x32_100_114", 144, 32, 100, 114},
	} {
		t.Run(tc.name, func(t *testing.T) {
			w, h := tc.w, tc.h
			enc, _ := NewVP8Enc(w, h, 500000)
			yuv := make([]byte, w*h*3/2)
			for y := 0; y < h; y++ {
				for x := 0; x < w; x++ {
					if y < 16 {
						yuv[y*w+x] = tc.topY
					} else {
						yuv[y*w+x] = tc.bottomY
					}
				}
			}
			for i := w * h; i < len(yuv); i++ {
				yuv[i] = 128
			}

			frame, _ := enc.Encode(yuv, w, h)
			tag := uint32(frame[0]) | uint32(frame[1])<<8 | uint32(frame[2])<<16
			fp := tag >> 5

			dec := vp8.NewDecoder()
			dec.Init(bytes.NewReader(frame), len(frame))
			dec.DecodeFrameHeader()
			_, err := dec.DecodeFrame()
			if err != nil {
				t.Errorf("FAIL: frame=%d fp=%d tp=%d", len(frame), fp, len(frame)-int(10+fp))
			}
		})
	}
}
