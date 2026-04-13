package utils

import (
	"bytes"
	"testing"
	"golang.org/x/image/vp8"
)

func TestVP8DecodeOwnFrame(t *testing.T) {
	enc, err := NewVP8Enc(320, 240, 500000)
	if err != nil {
		t.Fatalf("NewVP8Enc: %v", err)
	}

	// Green YUV420P frame
	w, h := 320, 240
	yuv := make([]byte, w*h*3/2)
	for i := 0; i < w*h; i++ {
		yuv[i] = 149 // Y (green)
	}
	off := w * h
	for i := 0; i < (w/2)*(h/2); i++ {
		yuv[off+i] = 43 // U
	}
	off += (w / 2) * (h / 2)
	for i := 0; i < (w/2)*(h/2); i++ {
		yuv[off+i] = 21 // V
	}

	frame, err := enc.Encode(yuv, w, h)
	if err != nil {
		t.Fatalf("Encode: %v", err)
	}
	t.Logf("Encoded frame: %d bytes", len(frame))

	// Try to decode with Go's vp8 decoder
	dec := vp8.NewDecoder()
	dec.Init(bytes.NewReader(frame), len(frame))
	
	fh, err := dec.DecodeFrameHeader()
	if err != nil {
		t.Fatalf("DecodeFrameHeader: %v", err)
	}
	t.Logf("Frame header: %dx%d keyframe=%v", fh.Width, fh.Height, fh.KeyFrame)
	
	img, err := dec.DecodeFrame()
	if err != nil {
		t.Fatalf("DecodeFrame: %v", err)
	}
	bounds := img.Bounds()
	t.Logf("Decoded image: %dx%d", bounds.Dx(), bounds.Dy())

	// Test gradient frame too
	for y := 0; y < h; y++ {
		for x := 0; x < w; x++ {
			yuv[y*w+x] = byte(x * 255 / w)
		}
	}
	frame2, err := enc.Encode(yuv, w, h)
	if err != nil {
		t.Fatalf("Encode gradient: %v", err)
	}
	t.Logf("Gradient frame: %d bytes", len(frame2))
	
	dec2 := vp8.NewDecoder()
	dec2.Init(bytes.NewReader(frame2), len(frame2))
	fh2, err := dec2.DecodeFrameHeader()
	if err != nil {
		t.Fatalf("DecodeFrameHeader gradient: %v", err)
	}
	t.Logf("Gradient header: %dx%d keyframe=%v", fh2.Width, fh2.Height, fh2.KeyFrame)
	
	img2, err := dec2.DecodeFrame()
	if err != nil {
		t.Fatalf("DecodeFrame gradient: %v", err)
	}
	t.Logf("Gradient decoded: %dx%d", img2.Bounds().Dx(), img2.Bounds().Dy())
	
	// Verify nil/empty YUV
	frame3, _ := enc.Encode(nil, w, h)
	dec3 := vp8.NewDecoder()
	dec3.Init(bytes.NewReader(frame3), len(frame3))
	_, err = dec3.DecodeFrameHeader()
	if err != nil {
		t.Fatalf("DecodeFrameHeader nil: %v", err)
	}
	_, err = dec3.DecodeFrame()
	if err != nil {
		t.Fatalf("DecodeFrame nil: %v", err)
	}
	t.Log("Nil YUV frame decoded OK")
}
