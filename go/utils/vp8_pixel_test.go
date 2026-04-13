package utils

import (
	"bytes"
	"fmt"
	"math"
	"testing"

	"golang.org/x/image/vp8"
)

// TestVP8PixelAccuracy encodes known YUV patterns, decodes with Go's VP8 decoder
// (a separate RFC 6386 implementation), and verifies decoded pixel values match
// expected DC block averages within quantization tolerance.
//
// This is the strongest pure-Go proof that our encoder produces spec-compliant
// VP8 — if golang.org/x/image/vp8 decodes it correctly, libwebrtc/libvpx will too.
func TestVP8PixelAccuracy(t *testing.T) {
	tests := []struct {
		name string
		w, h int
		fill func(yuv []byte, w, h int) // fills Y, U, V planes
	}{
		{"solid_black", 320, 240, func(yuv []byte, w, h int) {
			// Y=0, U=128, V=128 → black
			for i := w * h; i < w*h+(w/2)*(h/2); i++ {
				yuv[i] = 128
			}
			for i := w*h + (w/2)*(h/2); i < len(yuv); i++ {
				yuv[i] = 128
			}
		}},
		{"solid_white", 320, 240, func(yuv []byte, w, h int) {
			for i := 0; i < w*h; i++ {
				yuv[i] = 255
			}
			for i := w * h; i < len(yuv); i++ {
				yuv[i] = 128
			}
		}},
		{"solid_green", 320, 240, func(yuv []byte, w, h int) {
			for i := 0; i < w*h; i++ {
				yuv[i] = 149
			}
			off := w * h
			for i := 0; i < (w/2)*(h/2); i++ {
				yuv[off+i] = 43
			}
			off += (w / 2) * (h / 2)
			for i := 0; i < (w/2)*(h/2); i++ {
				yuv[off+i] = 21
			}
		}},
		{"solid_red", 320, 240, func(yuv []byte, w, h int) {
			for i := 0; i < w*h; i++ {
				yuv[i] = 76
			}
			off := w * h
			for i := 0; i < (w/2)*(h/2); i++ {
				yuv[off+i] = 84
			}
			off += (w / 2) * (h / 2)
			for i := 0; i < (w/2)*(h/2); i++ {
				yuv[off+i] = 255
			}
		}},
		{"horizontal_gradient", 320, 240, func(yuv []byte, w, h int) {
			for y := 0; y < h; y++ {
				for x := 0; x < w; x++ {
					yuv[y*w+x] = byte(x * 255 / w)
				}
			}
			for i := w * h; i < len(yuv); i++ {
				yuv[i] = 128
			}
		}},
		{"vertical_gradient", 320, 240, func(yuv []byte, w, h int) {
			for y := 0; y < h; y++ {
				for x := 0; x < w; x++ {
					yuv[y*w+x] = byte(y * 255 / h)
				}
			}
			for i := w * h; i < len(yuv); i++ {
				yuv[i] = 128
			}
		}},
		{"checkerboard_16x16", 320, 240, func(yuv []byte, w, h int) {
			// 16x16 block checkerboard — each macroblock is uniform
			for y := 0; y < h; y++ {
				for x := 0; x < w; x++ {
					mbX, mbY := x/16, y/16
					if (mbX+mbY)%2 == 0 {
						yuv[y*w+x] = 200
					} else {
						yuv[y*w+x] = 50
					}
				}
			}
			for i := w * h; i < len(yuv); i++ {
				yuv[i] = 128
			}
		}},
		{"four_quadrants", 640, 480, func(yuv []byte, w, h int) {
			for y := 0; y < h; y++ {
				for x := 0; x < w; x++ {
					switch {
					case y < h/2 && x < w/2:
						yuv[y*w+x] = 30
					case y < h/2 && x >= w/2:
						yuv[y*w+x] = 100
					case y >= h/2 && x < w/2:
						yuv[y*w+x] = 180
					default:
						yuv[y*w+x] = 240
					}
				}
			}
			cw, ch := w/2, h/2
			off := w * h
			for cy := 0; cy < ch; cy++ {
				for cx := 0; cx < cw; cx++ {
					if cy < ch/2 {
						yuv[off+cy*cw+cx] = 60
					} else {
						yuv[off+cy*cw+cx] = 200
					}
				}
			}
			off += cw * ch
			for cy := 0; cy < ch; cy++ {
				for cx := 0; cx < cw; cx++ {
					if cx < cw/2 {
						yuv[off+cy*cw+cx] = 40
					} else {
						yuv[off+cy*cw+cx] = 220
					}
				}
			}
		}},
		{"small_16x16", 16, 16, func(yuv []byte, w, h int) {
			for i := 0; i < w*h; i++ {
				yuv[i] = 100
			}
			for i := w * h; i < len(yuv); i++ {
				yuv[i] = 128
			}
		}},
		{"720p", 1280, 720, func(yuv []byte, w, h int) {
			// Diagonal gradient
			for y := 0; y < h; y++ {
				for x := 0; x < w; x++ {
					yuv[y*w+x] = byte((x + y) * 255 / (w + h))
				}
			}
			for i := w * h; i < len(yuv); i++ {
				yuv[i] = 128
			}
		}},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			w, h := tc.w, tc.h
			yuv := make([]byte, w*h*3/2)
			tc.fill(yuv, w, h)

			enc, err := NewVP8Enc(w, h, 500000)
			if err != nil {
				t.Fatalf("NewVP8Enc: %v", err)
			}

			frame, err := enc.Encode(yuv, w, h)
			if err != nil {
				t.Fatalf("Encode: %v", err)
			}
			t.Logf("encoded: %d bytes", len(frame))

			// Decode with Go's VP8 decoder
			dec := vp8.NewDecoder()
			dec.Init(bytes.NewReader(frame), len(frame))
			fh, err := dec.DecodeFrameHeader()
			if err != nil {
				t.Fatalf("DecodeFrameHeader: %v", err)
			}
			if !fh.KeyFrame {
				t.Fatal("expected keyframe")
			}

			img, err := dec.DecodeFrame()
			if err != nil {
				t.Fatalf("DecodeFrame: %v", err)
			}

			// Verify dimensions
			ycbcr := img
			bounds := ycbcr.Bounds()
			if bounds.Dx() != w || bounds.Dy() != h {
				t.Fatalf("size mismatch: got %dx%d want %dx%d", bounds.Dx(), bounds.Dy(), w, h)
			}

			// Verify Y pixel values — compare 4x4 block averages
			// Our encoder encodes DC (block average), so decoded blocks should
			// match input block averages within quantization tolerance.
			mbW := (w + 15) / 16
			mbH := (h + 15) / 16
			maxYErr := 0.0
			totalYErr := 0.0
			nBlocks := 0

			for mbY := 0; mbY < mbH; mbY++ {
				for mbX := 0; mbX < mbW; mbX++ {
					for sbY := 0; sbY < 4; sbY++ {
						for sbX := 0; sbX < 4; sbX++ {
							// Compute expected 4x4 block average from input
							bx := mbX*16 + sbX*4
							by := mbY*16 + sbY*4
							sum := 0
							count := 0
							for dy := 0; dy < 4; dy++ {
								for dx := 0; dx < 4; dx++ {
									px, py := bx+dx, by+dy
									if px < w && py < h {
										sum += int(yuv[py*w+px])
										count++
									}
								}
							}
							if count == 0 {
								continue
							}
							expectedAvg := float64(sum) / float64(count)

							// Get decoded block average
							decSum := 0
							decCount := 0
							for dy := 0; dy < 4; dy++ {
								for dx := 0; dx < 4; dx++ {
									px, py := bx+dx, by+dy
									if px < bounds.Dx() && py < bounds.Dy() {
										decSum += int(ycbcr.Y[py*ycbcr.YStride+px])
										decCount++
									}
								}
							}
							if decCount == 0 {
								continue
							}
							decodedAvg := float64(decSum) / float64(decCount)

							err := math.Abs(expectedAvg - decodedAvg)
							if err > maxYErr {
								maxYErr = err
							}
							totalYErr += err
							nBlocks++
						}
					}
				}
			}

			avgYErr := totalYErr / float64(nBlocks)
			t.Logf("Y accuracy: %d blocks, avg_err=%.1f, max_err=%.1f", nBlocks, avgYErr, maxYErr)

			// VP8 quantization tolerance: QP=10 Y2_DC_Q=2*4=8, so each
			// coefficient can be off by up to half a quant step.
			// With WHT and prediction, max error per pixel ~20.
			// For typical content, average should be well under 10.
			if maxYErr > 30 {
				t.Errorf("Y max error too high: %.1f (expected <30)", maxYErr)
			}
			if avgYErr > 12 {
				t.Errorf("Y avg error too high: %.1f (expected <12)", avgYErr)
			}

			// Verify chroma — 8x8 block averages (chroma is subsampled 2x)
			cw, ch := w/2, h/2
			uOff := w * h
			vOff := uOff + cw*ch
			maxCErr := 0.0
			totalCErr := 0.0
			nCBlocks := 0

			cmbW := (cw + 7) / 8
			cmbH := (ch + 7) / 8

			for mbY := 0; mbY < cmbH; mbY++ {
				for mbX := 0; mbX < cmbW; mbX++ {
					for sbY := 0; sbY < 2; sbY++ {
						for sbX := 0; sbX < 2; sbX++ {
							bx := mbX*8 + sbX*4
							by := mbY*8 + sbY*4

							for plane := 0; plane < 2; plane++ {
								planeOff := uOff
								if plane == 1 {
									planeOff = vOff
								}

								sum := 0
								count := 0
								for dy := 0; dy < 4; dy++ {
									for dx := 0; dx < 4; dx++ {
										px, py := bx+dx, by+dy
										if px < cw && py < ch {
											sum += int(yuv[planeOff+py*cw+px])
											count++
										}
									}
								}
								if count == 0 {
									continue
								}
								expectedAvg := float64(sum) / float64(count)

								decSum := 0
								decCount := 0
								for dy := 0; dy < 4; dy++ {
									for dx := 0; dx < 4; dx++ {
										px, py := bx+dx, by+dy
										if px < bounds.Dx()/2 && py < bounds.Dy()/2 {
											var v byte
											if plane == 0 {
												v = ycbcr.Cb[py*ycbcr.CStride+px]
											} else {
												v = ycbcr.Cr[py*ycbcr.CStride+px]
											}
											decSum += int(v)
											decCount++
										}
									}
								}
								if decCount == 0 {
									continue
								}
								decodedAvg := float64(decSum) / float64(decCount)

								cerr := math.Abs(expectedAvg - decodedAvg)
								if cerr > maxCErr {
									maxCErr = cerr
								}
								totalCErr += cerr
								nCBlocks++
							}
						}
					}
				}
			}

			avgCErr := 0.0
			if nCBlocks > 0 {
				avgCErr = totalCErr / float64(nCBlocks)
			}
			t.Logf("Chroma accuracy: %d blocks, avg_err=%.1f, max_err=%.1f", nCBlocks, avgCErr, maxCErr)

			if maxCErr > 30 {
				t.Errorf("Chroma max error too high: %.1f (expected <30)", maxCErr)
			}
			if avgCErr > 12 {
				t.Errorf("Chroma avg error too high: %.1f (expected <12)", avgCErr)
			}
		})
	}
}

// TestVP8MultiFrame encodes a sequence of frames with changing content
// and verifies each decodes correctly. Simulates real video call usage.
func TestVP8MultiFrame(t *testing.T) {
	w, h := 320, 240
	enc, _ := NewVP8Enc(w, h, 500000)

	for i := 0; i < 30; i++ {
		yuv := make([]byte, w*h*3/2)
		// Moving vertical bar
		barX := (i * 10) % w
		for y := 0; y < h; y++ {
			for x := 0; x < w; x++ {
				dist := x - barX
				if dist < 0 {
					dist = -dist
				}
				if dist < 20 {
					yuv[y*w+x] = 220
				} else {
					yuv[y*w+x] = 40
				}
			}
		}
		for j := w * h; j < len(yuv); j++ {
			yuv[j] = 128
		}

		frame, err := enc.Encode(yuv, w, h)
		if err != nil {
			t.Fatalf("frame %d: Encode: %v", i, err)
		}

		dec := vp8.NewDecoder()
		dec.Init(bytes.NewReader(frame), len(frame))
		_, err = dec.DecodeFrameHeader()
		if err != nil {
			t.Fatalf("frame %d: header: %v", i, err)
		}
		img, err := dec.DecodeFrame()
		if err != nil {
			t.Fatalf("frame %d: DecodeFrame: %v", i, err)
		}

		ycbcr := img
		// Verify the bar is visible — center of bar should be bright
		centerY := ycbcr.Y[(h/2)*ycbcr.YStride+barX]
		if centerY < 150 {
			t.Errorf("frame %d: bar center Y=%d (expected >150)", i, centerY)
		}
	}
	t.Logf("30 sequential frames encoded+decoded, all with correct content")
}

// TestVP8HighRes tests encode/decode at resolutions typical for video calls.
func TestVP8HighRes(t *testing.T) {
	for _, sz := range [][2]int{{640, 480}, {1280, 720}, {1920, 1080}} {
		w, h := sz[0], sz[1]
		t.Run(fmt.Sprintf("%dx%d", w, h), func(t *testing.T) {
			enc, _ := NewVP8Enc(w, h, 500000)
			yuv := make([]byte, w*h*3/2)
			// Radial pattern from center
			cx, cy := w/2, h/2
			for y := 0; y < h; y++ {
				for x := 0; x < w; x++ {
					dx, dy := x-cx, y-cy
					dist := math.Sqrt(float64(dx*dx + dy*dy))
					yuv[y*w+x] = byte(int(dist) % 256)
				}
			}
			for i := w * h; i < len(yuv); i++ {
				yuv[i] = 128
			}

			frame, err := enc.Encode(yuv, w, h)
			if err != nil {
				t.Fatalf("Encode: %v", err)
			}
			t.Logf("encoded %dx%d: %d bytes (%.1f KB)", w, h, len(frame), float64(len(frame))/1024)

			dec := vp8.NewDecoder()
			dec.Init(bytes.NewReader(frame), len(frame))
			_, err = dec.DecodeFrameHeader()
			if err != nil {
				t.Fatalf("header: %v", err)
			}
			img, err := dec.DecodeFrame()
			if err != nil {
				t.Fatalf("DecodeFrame: %v", err)
			}
			bounds := img.Bounds()
			if bounds.Dx() != w || bounds.Dy() != h {
				t.Errorf("size: got %dx%d want %dx%d", bounds.Dx(), bounds.Dy(), w, h)
			}
			t.Logf("PASS — decoded %dx%d", w, h)
		})
	}
}
