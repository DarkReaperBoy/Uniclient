// VP8 keyframe encoder — pure Go, zero CGo (RFC 6386).
//
// Encodes actual DC coefficients from YUV420P input. Each 4x4 luma block
// gets its average Y value encoded via the Y2 (WHT) block; chroma blocks
// get their average U/V values encoded directly. AC coefficients are zero
// (no detail within 4x4 blocks), producing a blocky but correct image.
//
// This is sufficient for real-time call video — libwebrtc decodes it,
// VideoRenderer fires, and the remote sees actual content. Production callers
// should inject platform VP8 encoders via SetVideoEncoderFactory.

package utils

import (
	"encoding/binary"
	"fmt"
	"math/bits"
	"sync"
)

// ---------------------------------------------------------------------------
// VP8 bool encoder (RFC 6386 §7)
// ---------------------------------------------------------------------------

type vp8BoolEnc struct {
	buf   []byte
	low   uint32
	rng   uint32
	count int
}

func newVP8BoolEnc() *vp8BoolEnc {
	return &vp8BoolEnc{rng: 255, count: -24}
}

func (e *vp8BoolEnc) putBool(bit bool, prob uint8) {
	split := 1 + ((e.rng - 1) * uint32(prob) >> 8)
	if bit {
		e.low += split
		e.rng -= split
	} else {
		e.rng = split
	}
	shift := uint(bits.LeadingZeros8(uint8(e.rng)))
	e.rng <<= shift
	e.count += int(shift)
	if e.count >= 0 {
		offset := int(shift) - e.count
		if offset > 0 && (e.low<<uint(offset-1))&0x80000000 != 0 {
			for i := len(e.buf) - 1; i >= 0; i-- {
				if e.buf[i] == 0xFF {
					e.buf[i] = 0
				} else {
					e.buf[i]++
					break
				}
			}
		}
		e.buf = append(e.buf, byte(e.low>>uint(24-offset)))
		e.low <<= uint(offset)
		shift = uint(e.count)
		e.low &= 0xFFFFFF
		e.count -= 8
	}
	e.low <<= shift
}

func (e *vp8BoolEnc) putLit(v uint32, n int) {
	for i := n - 1; i >= 0; i-- {
		e.putBool(v&(1<<uint(i)) != 0, 128)
	}
}

func (e *vp8BoolEnc) flush() []byte {
	for i := 0; i < 32; i++ {
		e.putBool(false, 128)
	}
	// Emit any remaining accumulated bits
	if e.count&7 != 0 {
		s := uint(8 - (e.count & 7))
		e.low <<= s
		e.count += int(s)
		for e.count >= 0 {
			e.buf = append(e.buf, byte(e.low>>24))
			e.low <<= 8
			e.low &= 0xFFFFFFFF
			e.count -= 8
		}
	}
	// Pad with zero bytes — the Go VP8 decoder (golang.org/x/image/vp8) sets
	// unexpectedEOF if ANY readBit call tries to load a byte from an exhausted
	// buffer, even when there are still valid bits in the 16-bit accumulator.
	// After the last real token, the decoder may make many more readBit calls
	// (for the remaining sub-blocks), each of which can trigger a byte load
	// after range renormalization consumes accumulated bits. Empirically, the
	// read-ahead can reach 48+ bytes past the logical content for 1440p+
	// content. 64 bytes of padding covers all practical resolutions.
	for i := 0; i < 64; i++ {
		e.buf = append(e.buf, 0)
	}
	return e.buf
}

// ---------------------------------------------------------------------------
// VP8 coefficient update probabilities (RFC 6386 §13.4, from libvpx)
// [BLOCK_TYPES=4][COEF_BANDS=8][PREV_COEF_CONTEXTS=3][ENTROPY_NODES=11]
// ---------------------------------------------------------------------------

var vp8CoefUpdateProbs = [4][8][3][11]uint8{
	{ // block type 0
		{{255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255},
			{255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255},
			{255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255}},
		{{176, 246, 255, 255, 255, 255, 255, 255, 255, 255, 255},
			{223, 241, 252, 255, 255, 255, 255, 255, 255, 255, 255},
			{249, 253, 253, 255, 255, 255, 255, 255, 255, 255, 255}},
		{{255, 244, 252, 255, 255, 255, 255, 255, 255, 255, 255},
			{234, 254, 254, 255, 255, 255, 255, 255, 255, 255, 255},
			{253, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255}},
		{{255, 246, 254, 255, 255, 255, 255, 255, 255, 255, 255},
			{239, 253, 254, 255, 255, 255, 255, 255, 255, 255, 255},
			{254, 255, 254, 255, 255, 255, 255, 255, 255, 255, 255}},
		{{255, 248, 254, 255, 255, 255, 255, 255, 255, 255, 255},
			{251, 255, 254, 255, 255, 255, 255, 255, 255, 255, 255},
			{255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255}},
		{{255, 253, 254, 255, 255, 255, 255, 255, 255, 255, 255},
			{251, 254, 254, 255, 255, 255, 255, 255, 255, 255, 255},
			{254, 255, 254, 255, 255, 255, 255, 255, 255, 255, 255}},
		{{255, 254, 253, 255, 254, 255, 255, 255, 255, 255, 255},
			{250, 255, 254, 255, 254, 255, 255, 255, 255, 255, 255},
			{254, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255}},
		{{255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255},
			{255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255},
			{255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255}},
	},
	{ // block type 1
		{{217, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255},
			{225, 252, 241, 253, 255, 255, 254, 255, 255, 255, 255},
			{234, 250, 241, 250, 253, 255, 253, 254, 255, 255, 255}},
		{{255, 254, 255, 255, 255, 255, 255, 255, 255, 255, 255},
			{223, 254, 254, 255, 255, 255, 255, 255, 255, 255, 255},
			{238, 253, 254, 254, 255, 255, 255, 255, 255, 255, 255}},
		{{255, 248, 254, 255, 255, 255, 255, 255, 255, 255, 255},
			{249, 254, 255, 255, 255, 255, 255, 255, 255, 255, 255},
			{255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255}},
		{{255, 253, 255, 255, 255, 255, 255, 255, 255, 255, 255},
			{247, 254, 255, 255, 255, 255, 255, 255, 255, 255, 255},
			{255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255}},
		{{255, 253, 254, 255, 255, 255, 255, 255, 255, 255, 255},
			{252, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255},
			{255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255}},
		{{255, 254, 254, 255, 255, 255, 255, 255, 255, 255, 255},
			{253, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255},
			{255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255}},
		{{255, 254, 253, 255, 255, 255, 255, 255, 255, 255, 255},
			{250, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255},
			{254, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255}},
		{{255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255},
			{255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255},
			{255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255}},
	},
	{ // block type 2
		{{186, 251, 250, 255, 255, 255, 255, 255, 255, 255, 255},
			{234, 251, 244, 254, 255, 255, 255, 255, 255, 255, 255},
			{251, 251, 243, 253, 254, 255, 254, 255, 255, 255, 255}},
		{{255, 253, 254, 255, 255, 255, 255, 255, 255, 255, 255},
			{236, 253, 254, 255, 255, 255, 255, 255, 255, 255, 255},
			{251, 253, 253, 254, 254, 255, 255, 255, 255, 255, 255}},
		{{255, 254, 254, 255, 255, 255, 255, 255, 255, 255, 255},
			{254, 254, 254, 255, 255, 255, 255, 255, 255, 255, 255},
			{255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255}},
		{{255, 254, 255, 255, 255, 255, 255, 255, 255, 255, 255},
			{254, 254, 255, 255, 255, 255, 255, 255, 255, 255, 255},
			{254, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255}},
		{{255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255},
			{254, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255},
			{255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255}},
		{{255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255},
			{255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255},
			{255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255}},
		{{255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255},
			{255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255},
			{255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255}},
		{{255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255},
			{255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255},
			{255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255}},
	},
	{ // block type 3
		{{248, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255},
			{250, 254, 252, 254, 255, 255, 255, 255, 255, 255, 255},
			{248, 254, 249, 253, 255, 255, 255, 255, 255, 255, 255}},
		{{255, 253, 253, 255, 255, 255, 255, 255, 255, 255, 255},
			{246, 253, 253, 255, 255, 255, 255, 255, 255, 255, 255},
			{252, 254, 251, 254, 254, 255, 255, 255, 255, 255, 255}},
		{{255, 254, 252, 255, 255, 255, 255, 255, 255, 255, 255},
			{248, 254, 253, 255, 255, 255, 255, 255, 255, 255, 255},
			{253, 255, 254, 254, 255, 255, 255, 255, 255, 255, 255}},
		{{255, 251, 254, 255, 255, 255, 255, 255, 255, 255, 255},
			{245, 251, 254, 255, 255, 255, 255, 255, 255, 255, 255},
			{253, 253, 254, 255, 255, 255, 255, 255, 255, 255, 255}},
		{{255, 251, 253, 255, 255, 255, 255, 255, 255, 255, 255},
			{252, 253, 254, 255, 255, 255, 255, 255, 255, 255, 255},
			{255, 254, 255, 255, 255, 255, 255, 255, 255, 255, 255}},
		{{255, 252, 255, 255, 255, 255, 255, 255, 255, 255, 255},
			{249, 255, 254, 255, 255, 255, 255, 255, 255, 255, 255},
			{255, 255, 254, 255, 255, 255, 255, 255, 255, 255, 255}},
		{{255, 255, 253, 255, 255, 255, 255, 255, 255, 255, 255},
			{250, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255},
			{255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255}},
		{{255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255},
			{254, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255},
			{255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255}},
	},
}

// ---------------------------------------------------------------------------
// VP8 keyframe Y/UV mode probabilities (RFC 6386 §11.2-11.3)
// ---------------------------------------------------------------------------

var kfYModeProb = [4]uint8{145, 156, 163, 128}
var kfUVModeProb = [3]uint8{142, 114, 183}

// Default coefficient probabilities — must EXACTLY match the Go VP8 decoder's
// defaultTokenProb table (golang.org/x/image/vp8/token.go §13.5).
// [plane][band][ctx][node] where planes are: 0=Y1WithY2, 1=Y2, 2=UV, 3=Y1SansY2
var vp8DefaultCoefProbs = [4][8][3][11]uint8{
	{ // plane 0: Y1 with Y2 (planeY1WithY2)
		{{128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128},
			{128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128},
			{128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128}},
		{{253, 136, 254, 255, 228, 219, 128, 128, 128, 128, 128},
			{189, 129, 242, 255, 227, 213, 255, 219, 128, 128, 128},
			{106, 126, 227, 252, 214, 209, 255, 255, 128, 128, 128}},
		{{1, 98, 248, 255, 236, 226, 255, 255, 128, 128, 128},
			{181, 133, 238, 254, 221, 234, 255, 154, 128, 128, 128},
			{78, 134, 202, 247, 198, 180, 255, 219, 128, 128, 128}},
		{{1, 185, 249, 255, 243, 255, 128, 128, 128, 128, 128},
			{184, 150, 247, 255, 236, 224, 128, 128, 128, 128, 128},
			{77, 110, 216, 255, 236, 230, 128, 128, 128, 128, 128}},
		{{1, 101, 251, 255, 241, 255, 128, 128, 128, 128, 128},
			{170, 139, 241, 252, 236, 209, 255, 255, 128, 128, 128},
			{37, 116, 196, 243, 228, 255, 255, 255, 128, 128, 128}},
		{{1, 204, 254, 255, 245, 255, 128, 128, 128, 128, 128},
			{207, 160, 250, 255, 238, 128, 128, 128, 128, 128, 128},
			{102, 103, 231, 255, 211, 171, 128, 128, 128, 128, 128}},
		{{1, 152, 252, 255, 240, 255, 128, 128, 128, 128, 128},
			{177, 135, 243, 255, 234, 225, 128, 128, 128, 128, 128},
			{80, 129, 211, 255, 194, 224, 128, 128, 128, 128, 128}},
		{{1, 1, 255, 128, 128, 128, 128, 128, 128, 128, 128},
			{246, 1, 255, 128, 128, 128, 128, 128, 128, 128, 128},
			{255, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128}},
	},
	{ // plane 1: Y2 / WHT (planeY2)
		{{198, 35, 237, 223, 193, 187, 162, 160, 145, 155, 62},
			{131, 45, 198, 221, 172, 176, 220, 157, 252, 221, 1},
			{68, 47, 146, 208, 149, 167, 221, 162, 255, 223, 128}},
		{{1, 149, 241, 255, 221, 224, 255, 255, 128, 128, 128},
			{184, 141, 234, 253, 222, 220, 255, 199, 128, 128, 128},
			{81, 99, 181, 242, 176, 190, 249, 202, 255, 255, 128}},
		{{1, 129, 232, 253, 214, 197, 242, 196, 255, 255, 128},
			{99, 121, 210, 250, 201, 198, 255, 202, 128, 128, 128},
			{23, 91, 163, 242, 170, 187, 247, 210, 255, 255, 128}},
		{{1, 200, 246, 255, 234, 255, 128, 128, 128, 128, 128},
			{109, 178, 241, 255, 231, 245, 255, 255, 128, 128, 128},
			{44, 130, 201, 253, 205, 192, 255, 255, 128, 128, 128}},
		{{1, 132, 239, 251, 219, 209, 255, 165, 128, 128, 128},
			{94, 136, 225, 251, 218, 190, 255, 255, 128, 128, 128},
			{22, 100, 174, 245, 186, 161, 255, 199, 128, 128, 128}},
		{{1, 182, 249, 255, 232, 235, 128, 128, 128, 128, 128},
			{124, 143, 241, 255, 227, 234, 128, 128, 128, 128, 128},
			{35, 77, 181, 251, 193, 211, 255, 205, 128, 128, 128}},
		{{1, 157, 247, 255, 236, 231, 255, 255, 128, 128, 128},
			{121, 141, 235, 255, 225, 227, 255, 255, 128, 128, 128},
			{45, 99, 188, 251, 195, 217, 255, 224, 128, 128, 128}},
		{{1, 1, 251, 255, 213, 255, 128, 128, 128, 128, 128},
			{203, 1, 248, 255, 255, 128, 128, 128, 128, 128, 128},
			{137, 1, 177, 255, 224, 255, 128, 128, 128, 128, 128}},
	},
	{ // plane 2: UV (planeUV)
		{{253, 9, 248, 251, 207, 208, 255, 192, 128, 128, 128},
			{175, 13, 224, 243, 193, 185, 249, 198, 255, 255, 128},
			{73, 17, 171, 221, 161, 179, 236, 167, 255, 234, 128}},
		{{1, 95, 247, 253, 212, 183, 255, 255, 128, 128, 128},
			{239, 90, 244, 250, 211, 209, 255, 255, 128, 128, 128},
			{155, 77, 195, 248, 188, 195, 255, 255, 128, 128, 128}},
		{{1, 24, 239, 251, 218, 219, 255, 205, 128, 128, 128},
			{201, 51, 219, 255, 196, 186, 128, 128, 128, 128, 128},
			{69, 46, 190, 239, 201, 218, 255, 228, 128, 128, 128}},
		{{1, 191, 251, 255, 255, 128, 128, 128, 128, 128, 128},
			{223, 165, 249, 255, 213, 255, 128, 128, 128, 128, 128},
			{141, 124, 248, 255, 255, 128, 128, 128, 128, 128, 128}},
		{{1, 16, 248, 255, 255, 128, 128, 128, 128, 128, 128},
			{190, 36, 230, 255, 236, 255, 128, 128, 128, 128, 128},
			{149, 1, 255, 128, 128, 128, 128, 128, 128, 128, 128}},
		{{1, 226, 255, 128, 128, 128, 128, 128, 128, 128, 128},
			{247, 192, 255, 128, 128, 128, 128, 128, 128, 128, 128},
			{240, 128, 255, 128, 128, 128, 128, 128, 128, 128, 128}},
		{{1, 134, 252, 255, 255, 128, 128, 128, 128, 128, 128},
			{213, 62, 250, 255, 255, 128, 128, 128, 128, 128, 128},
			{55, 93, 255, 128, 128, 128, 128, 128, 128, 128, 128}},
		{{128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128},
			{128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128},
			{128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128}},
	},
	{ // plane 3: Y1 sans Y2 (planeY1SansY2)
		{{202, 24, 213, 235, 186, 191, 220, 160, 240, 175, 255},
			{126, 38, 182, 232, 169, 184, 228, 174, 255, 187, 128},
			{61, 46, 138, 219, 151, 178, 240, 170, 255, 216, 128}},
		{{1, 112, 230, 250, 199, 191, 247, 159, 255, 255, 128},
			{166, 109, 228, 252, 211, 215, 255, 174, 128, 128, 128},
			{39, 77, 162, 232, 172, 180, 245, 178, 255, 255, 128}},
		{{1, 52, 220, 246, 198, 199, 249, 220, 255, 255, 128},
			{124, 74, 191, 243, 183, 193, 250, 221, 255, 255, 128},
			{24, 71, 130, 219, 154, 170, 243, 182, 255, 255, 128}},
		{{1, 182, 225, 249, 219, 240, 255, 224, 128, 128, 128},
			{149, 150, 226, 252, 216, 205, 255, 171, 128, 128, 128},
			{28, 108, 170, 242, 183, 194, 254, 223, 255, 255, 128}},
		{{1, 81, 230, 252, 204, 203, 255, 192, 128, 128, 128},
			{123, 102, 209, 247, 188, 196, 255, 233, 128, 128, 128},
			{20, 95, 153, 243, 164, 173, 255, 203, 128, 128, 128}},
		{{1, 222, 248, 255, 216, 213, 128, 128, 128, 128, 128},
			{168, 175, 246, 252, 235, 205, 255, 255, 128, 128, 128},
			{47, 116, 215, 255, 211, 212, 255, 255, 128, 128, 128}},
		{{1, 121, 236, 253, 212, 214, 255, 255, 128, 128, 128},
			{141, 84, 213, 252, 201, 202, 255, 219, 128, 128, 128},
			{42, 80, 160, 240, 162, 185, 255, 205, 128, 128, 128}},
		{{1, 1, 255, 128, 128, 128, 128, 128, 128, 128, 128},
			{244, 1, 255, 128, 128, 128, 128, 128, 128, 128, 128},
			{238, 1, 255, 128, 128, 128, 128, 128, 128, 128, 128}},
	},
}

// VP8 DC quantizer table (RFC 6386 §14.1) — maps y_ac_qi to DC quantizer step
var vp8DCQLookup = [128]int16{
	4, 5, 6, 7, 8, 9, 10, 10, 11, 12, 13, 14, 15, 16, 17, 17,
	18, 19, 20, 20, 21, 21, 22, 22, 23, 23, 24, 25, 25, 26, 27, 28,
	29, 30, 31, 32, 33, 34, 35, 36, 37, 37, 38, 39, 40, 41, 42, 43,
	44, 45, 46, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58,
	59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74,
	75, 76, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89,
	91, 93, 95, 96, 98, 100, 101, 102, 104, 106, 108, 110, 112, 114, 116, 118,
	122, 124, 126, 128, 130, 132, 134, 136, 138, 140, 143, 145, 148, 151, 154, 157,
}

// VP8 AC quantizer table (RFC 6386 §14.1) — maps y_ac_qi to AC quantizer step
var vp8ACQLookup = [128]int16{
	4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19,
	20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35,
	36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51,
	52, 53, 54, 55, 56, 57, 58, 60, 62, 64, 66, 68, 70, 72, 74, 76,
	78, 80, 82, 84, 86, 88, 90, 92, 94, 96, 98, 100, 102, 104, 106, 108,
	110, 112, 114, 116, 119, 122, 125, 128, 131, 134, 137, 140, 143, 146, 149, 152,
	155, 158, 161, 164, 167, 170, 173, 177, 181, 185, 189, 193, 197, 201, 205, 209,
	213, 217, 221, 225, 229, 234, 239, 245, 249, 254, 259, 264, 269, 274, 279, 284,
}

// VP8 zigzag scan order for 4x4 blocks (RFC 6386 §13.3)
// Maps scan position → flat index (row*4+col)
var vp8Zigzag = [16]int{
	0, 1, 4, 8, 5, 2, 3, 6, 9, 12, 13, 10, 7, 11, 14, 15,
}

// VP8 band assignment per scan position (RFC 6386 Table 13-1)
// VP8 coefficient band map — must match the decoder's bands table exactly.
// Maps scan position (0-16) → probability band index (0-7).
var vp8BandMap = [17]int{
	0, 1, 2, 3, 6, 4, 5, 6, 6, 6, 6, 6, 6, 6, 6, 7, 0,
}

// ---------------------------------------------------------------------------
// Walsh-Hadamard Transform (RFC 6386 §14.4)
// ---------------------------------------------------------------------------

// forwardWHT4x4 computes the forward 4x4 Walsh-Hadamard Transform.
// Input: 16 sub-block DC residuals in row-major order [row*4+col].
// Output: 16 WHT coefficients in row-major order (index 0 = DC).
// Matches libvpx's vp8_short_walsh4x4_c exactly.
// forwardWHT4x4 computes the forward 4x4 Walsh-Hadamard Transform.
// Matches libvpx's vp8_short_walsh4x4_c: rows first with <<2 scaling,
// columns second with >>1 rounding. Uses d-c (not c-d) for the 4th
// output to match the standard Hadamard matrix (H*H = 4I).
func forwardWHT4x4(in [16]int) [16]int {
	var tmp [16]int
	// Pass 1: rows with <<2 scaling
	for i := 0; i < 4; i++ {
		a := (in[i*4+0] + in[i*4+3]) << 2
		b := (in[i*4+1] + in[i*4+2]) << 2
		c := (in[i*4+1] - in[i*4+2]) << 2
		d := (in[i*4+0] - in[i*4+3]) << 2
		r := 0
		if a != 0 {
			r = 1
		}
		tmp[i*4+0] = a + b + r
		tmp[i*4+1] = c + d
		tmp[i*4+2] = a - b
		tmp[i*4+3] = d - c
	}
	// Pass 2: columns with >>1 rounding (toward zero)
	var out [16]int
	for j := 0; j < 4; j++ {
		a := tmp[0*4+j] + tmp[3*4+j]
		b := tmp[1*4+j] + tmp[2*4+j]
		c := tmp[1*4+j] - tmp[2*4+j]
		d := tmp[0*4+j] - tmp[3*4+j]
		a2 := a + b
		b2 := c + d
		c2 := a - b
		d2 := d - c
		out[0*4+j] = whtRoundHalf(a2)
		out[1*4+j] = whtRoundHalf(b2)
		out[2*4+j] = whtRoundHalf(c2)
		out[3*4+j] = whtRoundHalf(d2)
	}
	return out
}

// inverseWHT4x4 computes the inverse 4x4 Walsh-Hadamard Transform.
// Matches libvpx's vp8_short_inv_walsh4x4_c: rows first (no scaling),
// columns second with (x+3)>>3. Uses d-c for the 4th output.
func inverseWHT4x4(in [16]int) [16]int {
	var tmp [16]int
	// Pass 1: rows (no scaling)
	for i := 0; i < 4; i++ {
		a := in[i*4+0] + in[i*4+3]
		b := in[i*4+1] + in[i*4+2]
		c := in[i*4+1] - in[i*4+2]
		d := in[i*4+0] - in[i*4+3]
		tmp[i*4+0] = a + b
		tmp[i*4+1] = c + d
		tmp[i*4+2] = a - b
		tmp[i*4+3] = d - c
	}
	// Pass 2: columns with (x+3)>>3
	var out [16]int
	for j := 0; j < 4; j++ {
		a := tmp[0*4+j] + tmp[3*4+j]
		b := tmp[1*4+j] + tmp[2*4+j]
		c := tmp[1*4+j] - tmp[2*4+j]
		d := tmp[0*4+j] - tmp[3*4+j]
		out[0*4+j] = (a + b + 3) >> 3
		out[1*4+j] = (c + d + 3) >> 3
		out[2*4+j] = (a - b + 3) >> 3
		out[3*4+j] = (d - c + 3) >> 3
	}
	return out
}

// whtRoundHalf rounds v/2 toward zero (matches libvpx's (v + (v>0)) >> 1).
func whtRoundHalf(v int) int {
	if v > 0 {
		return (v + 1) >> 1
	}
	return v >> 1
}

// ---------------------------------------------------------------------------
// VP8Enc — pure Go VP8 DC-coefficient encoder
// ---------------------------------------------------------------------------

type VP8Enc struct {
	width  int
	height int
	mu     sync.Mutex
}

func NewVP8Enc(width, height, bitrate int) (*VP8Enc, error) {
	if width <= 0 || height <= 0 {
		return nil, fmt.Errorf("vp8enc: invalid dimensions %dx%d", width, height)
	}
	return &VP8Enc{width: width, height: height}, nil
}

func (e *VP8Enc) Encode(yuv420p []byte, width, height int) ([]byte, error) {
	e.mu.Lock()
	defer e.mu.Unlock()
	if width > 0 && height > 0 {
		e.width = width
		e.height = height
	}
	return encodeVP8KeyframeWithDC(e.width, e.height, yuv420p)
}

func (e *VP8Enc) ForceKeyframe() {}
func (e *VP8Enc) Close()         {}

// ---------------------------------------------------------------------------
// Token encoding helpers (RFC 6386 §13.2)
// ---------------------------------------------------------------------------

// VP8 coefficient token tree — matches the Go x/image/vp8 decoder's
// parseResiduals4 implementation (which follows libwebp's approach):
//
//  probs[0]: EOB(F) vs more(T)
//  probs[1]: ZERO(F) vs nonzero(T)
//  probs[2]: ONE(F) vs >1(T)
//  probs[3]: LOW{2,3,4}(F) vs HIGH{cat1-6}(T)
//    LOW: probs[4]: TWO(F) vs {THREE,FOUR}(T)
//         probs[5]: THREE(F) vs FOUR(T)
//    HIGH:
//      probs[6]: {cat1,cat2}(F) vs {cat3,cat4,cat5,cat6}(T)
//        Left:  probs[7]: cat1(F) vs cat2(T)
//        Right: 2-bit selector using probs[8] and probs[9+b1]:
//               b1@probs[8], b0@probs[9+b1]
//               cat = 2*b1+b0: 0=cat3, 1=cat4, 2=cat5, 3=cat6

// writeTokenValue writes the value tree for a non-zero coefficient (probs[2..] + sign).
// Does NOT write the p[0] (EOB) or p[1] (zero/nonzero) bits — caller handles those.
func writeTokenValue(be *vp8BoolEnc, probs [11]uint8, value int) {
	absVal := value
	if absVal < 0 {
		absVal = -absVal
	}

	if absVal == 1 {
		be.putBool(false, probs[2])
		be.putBool(value < 0, 128)
		return
	}
	be.putBool(true, probs[2])

	if absVal <= 4 {
		be.putBool(false, probs[3])
		if absVal == 2 {
			be.putBool(false, probs[4])
		} else {
			be.putBool(true, probs[4])
			be.putBool(absVal == 4, probs[5])
		}
		be.putBool(value < 0, 128)
		return
	}

	be.putBool(true, probs[3])

	if absVal <= 10 {
		be.putBool(false, probs[6])
		if absVal <= 6 {
			be.putBool(false, probs[7])
			be.putBool(absVal == 6, 159)
		} else {
			be.putBool(true, probs[7])
			off := absVal - 7
			be.putBool(off&2 != 0, 165)
			be.putBool(off&1 != 0, 145)
		}
		be.putBool(value < 0, 128)
		return
	}

	be.putBool(true, probs[6])

	if absVal <= 18 {
		be.putBool(false, probs[8])
		be.putBool(false, probs[9])
		off := absVal - 11
		be.putBool(off&4 != 0, 173)
		be.putBool(off&2 != 0, 148)
		be.putBool(off&1 != 0, 140)
	} else if absVal <= 34 {
		be.putBool(false, probs[8])
		be.putBool(true, probs[9])
		off := absVal - 19
		be.putBool(off&8 != 0, 176)
		be.putBool(off&4 != 0, 155)
		be.putBool(off&2 != 0, 140)
		be.putBool(off&1 != 0, 135)
	} else if absVal <= 66 {
		be.putBool(true, probs[8])
		be.putBool(false, probs[10])
		off := absVal - 35
		be.putBool(off&16 != 0, 180)
		be.putBool(off&8 != 0, 157)
		be.putBool(off&4 != 0, 141)
		be.putBool(off&2 != 0, 134)
		be.putBool(off&1 != 0, 130)
	} else {
		be.putBool(true, probs[8])
		be.putBool(true, probs[10])
		off := absVal - 67
		cat6Probs := [11]uint8{254, 254, 243, 230, 196, 177, 153, 140, 133, 130, 129}
		for i := 10; i >= 0; i-- {
			be.putBool(off&(1<<uint(i)) != 0, cat6Probs[10-i])
		}
	}
	be.putBool(value < 0, 128)
}

// ---------------------------------------------------------------------------
// Core keyframe encoding with proper WHT and per-sub-block coefficients
// ---------------------------------------------------------------------------

// encodeBlock encodes a coefficient block matching the decoder's exact bit protocol:
//   1. p[0] EOB check before first coefficient
//   2. For each position: p[1] zero/nonzero
//   3. After non-zero: value tree + sign, then p[0] EOB check at next band
// Returns true if any non-zero coefficient was encoded.
func encodeBlock(tp *vp8BoolEnc, plane int, startBand int, ctx int, coeffs [16]int) bool {
	lastNz := -1
	for pos := 15; pos >= 0; pos-- {
		if coeffs[vp8Zigzag[pos]] != 0 {
			lastNz = pos
			break
		}
	}

	startPos := 0
	if startBand > 0 {
		startPos = startBand
	}

	// All zero → EOB
	if lastNz < startPos {
		tp.putBool(false, vp8DefaultCoefProbs[plane][vp8BandMap[startPos]][ctx][0])
		return false
	}

	// NOT-EOB before first coefficient
	tp.putBool(true, vp8DefaultCoefProbs[plane][vp8BandMap[startPos]][ctx][0])

	curCtx := ctx
	for pos := startPos; pos <= lastNz; pos++ {
		band := vp8BandMap[pos]
		val := coeffs[vp8Zigzag[pos]]
		probs := vp8DefaultCoefProbs[plane][band][curCtx]

		if val == 0 {
			tp.putBool(false, probs[1]) // zero
			curCtx = 0
		} else {
			tp.putBool(true, probs[1]) // non-zero
			writeTokenValue(tp, probs, val)

			absVal := val
			if absVal < 0 {
				absVal = -absVal
			}
			if absVal == 1 {
				curCtx = 1
			} else {
				curCtx = 2
			}

			// EOB/not-EOB after non-zero at the NEXT band
			if pos < 15 {
				nextBand := vp8BandMap[pos+1]
				if pos < lastNz {
					tp.putBool(true, vp8DefaultCoefProbs[plane][nextBand][curCtx][0]) // NOT-EOB
				} else {
					tp.putBool(false, vp8DefaultCoefProbs[plane][nextBand][curCtx][0]) // EOB
				}
			}
			// pos==15: decoder checks n==16 and returns, no EOB bit needed
		}
	}

	return true
}

func encodeVP8KeyframeWithDC(w, h int, yuv []byte) ([]byte, error) {
	mbW := (w + 15) / 16
	mbH := (h + 15) / 16
	expectedYUV := w * h * 3 / 2
	hasYUV := len(yuv) >= expectedYUV

	// QP index — use moderate value for reasonable quality
	qpIdx := 10
	dcQ := int(vp8DCQLookup[qpIdx])
	acQ := int(vp8ACQLookup[qpIdx])
	// Y2 quantizers (RFC 6386 §14.1)
	y2DCQ := dcQ * 2
	if y2DCQ < 8 {
		y2DCQ = 8
	}
	y2ACQ := acQ * 155 / 100
	if y2ACQ < 8 {
		y2ACQ = 8
	}

	// Compute per-macroblock per-sub-block averages
	type mbInfo struct {
		y4x4 [16]int // average Y for each 4x4 sub-block [row*4+col]
		u4x4 [4]int  // average U for each 4x4 chroma sub-block [row*2+col]
		v4x4 [4]int  // average V for each 4x4 chroma sub-block [row*2+col]
	}
	mbs := make([]mbInfo, mbW*mbH)

	for mbY := 0; mbY < mbH; mbY++ {
		for mbX := 0; mbX < mbW; mbX++ {
			mb := &mbs[mbY*mbW+mbX]
			if !hasYUV {
				for i := range mb.y4x4 {
					mb.y4x4[i] = 128
				}
				for i := range mb.u4x4 {
					mb.u4x4[i] = 128
					mb.v4x4[i] = 128
				}
				continue
			}

			// Per-4x4 Y sub-block averages
			for by := 0; by < 4; by++ {
				for bx := 0; bx < 4; bx++ {
					var sum int
					for py := 0; py < 4; py++ {
						for px := 0; px < 4; px++ {
							fy := mbY*16 + by*4 + py
							fx := mbX*16 + bx*4 + px
							if fy < h && fx < w {
								sum += int(yuv[fy*w+fx])
							} else {
								sum += 128
							}
						}
					}
					mb.y4x4[by*4+bx] = sum / 16
				}
			}

			// Per-4x4 U sub-block averages (2x2 grid of 4x4 blocks)
			uOff := w * h
			cW := w / 2
			cH := h / 2
			for by := 0; by < 2; by++ {
				for bx := 0; bx < 2; bx++ {
					var sum int
					for py := 0; py < 4; py++ {
						for px := 0; px < 4; px++ {
							fy := mbY*8 + by*4 + py
							fx := mbX*8 + bx*4 + px
							if fy < cH && fx < cW {
								sum += int(yuv[uOff+fy*cW+fx])
							} else {
								sum += 128
							}
						}
					}
					mb.u4x4[by*2+bx] = sum / 16
				}
			}

			// Per-4x4 V sub-block averages
			vOff := uOff + cW*cH
			for by := 0; by < 2; by++ {
				for bx := 0; bx < 2; bx++ {
					var sum int
					for py := 0; py < 4; py++ {
						for px := 0; px < 4; px++ {
							fy := mbY*8 + by*4 + py
							fx := mbX*8 + bx*4 + px
							if fy < cH && fx < cW {
								sum += int(yuv[vOff+fy*cW+fx])
							} else {
								sum += 128
							}
						}
					}
					mb.v4x4[by*2+bx] = sum / 16
				}
			}
		}
	}

	// --- Compute per-sub-block DC residuals, WHT, and quantized coefficients ---

	// Per-sub-block reconstructed Y values (16 per MB) for prediction chain
	reconYSub := make([][16]int, mbW*mbH) // [mbIdx][subBlock]
	// Per-sub-block reconstructed chroma
	reconUSub := make([][4]int, mbW*mbH)
	reconVSub := make([][4]int, mbW*mbH)
	// Quantized Y2 WHT coefficients (16 per MB)
	y2Coeffs := make([][16]int, mbW*mbH)
	// Quantized chroma DC coefficients (4 per MB per plane)
	uCoeffs := make([][4]int, mbW*mbH)
	vCoeffs := make([][4]int, mbW*mbH)
	// Whether MB has any non-zero coefficients
	mbHasCoeff := make([]bool, mbW*mbH)

	for mbY := 0; mbY < mbH; mbY++ {
		for mbX := 0; mbX < mbW; mbX++ {
			idx := mbY*mbW + mbX
			mb := &mbs[idx]
			hasLeft := mbX > 0
			hasAbove := mbY > 0

			// --- Y: 16×16 DC prediction → WHT → quantize ---
			// Match decoder's predFunc16DC exactly: one prediction for the whole 16×16 block.
			// Left border = 16 pixels (rightmost column of left MB) = 4 each from sub-blocks 3,7,11,15.
			// Above border = 16 pixels (bottom row of above MB) = 4 each from sub-blocks 12,13,14,15.
			var yPred int
			if hasLeft && hasAbove {
				leftIdx := idx - 1
				aboveIdx := idx - mbW
				leftSum := 4 * (reconYSub[leftIdx][3] + reconYSub[leftIdx][7] + reconYSub[leftIdx][11] + reconYSub[leftIdx][15])
				aboveSum := 4 * (reconYSub[aboveIdx][12] + reconYSub[aboveIdx][13] + reconYSub[aboveIdx][14] + reconYSub[aboveIdx][15])
				yPred = (leftSum + aboveSum + 16) / 32
			} else if hasLeft {
				leftIdx := idx - 1
				leftSum := 4 * (reconYSub[leftIdx][3] + reconYSub[leftIdx][7] + reconYSub[leftIdx][11] + reconYSub[leftIdx][15])
				yPred = (leftSum + 8) / 16
			} else if hasAbove {
				aboveIdx := idx - mbW
				aboveSum := 4 * (reconYSub[aboveIdx][12] + reconYSub[aboveIdx][13] + reconYSub[aboveIdx][14] + reconYSub[aboveIdx][15])
				yPred = (aboveSum + 8) / 16
			} else {
				yPred = 128
			}

			// Compute 16 DC residuals, pre-scaled by 2 for DCT/IDCT compensation.
			// The decoder applies inverse IDCT after inverse WHT: pixel = (DC+4)>>3.
			// This ×2 pre-scale ensures the WHT round-trip gives correct pixel values.
			var dcResiduals [16]int
			for i := 0; i < 16; i++ {
				dcResiduals[i] = (mb.y4x4[i] - yPred) * 2
			}

			// Forward WHT
			whtCoeffs := forwardWHT4x4(dcResiduals)

			// Quantize WHT coefficients
			var qY2 [16]int
			for i := 0; i < 16; i++ {
				q := y2DCQ
				if i > 0 {
					q = y2ACQ // AC coefficients use Y2 AC quantizer
				}
				if whtCoeffs[i] >= 0 {
					qY2[i] = (whtCoeffs[i] + q/2) / q
				} else {
					qY2[i] = -((-whtCoeffs[i] + q/2) / q)
				}
				if qY2[i] > 2047 {
					qY2[i] = 2047
				} else if qY2[i] < -2047 {
					qY2[i] = -2047
				}
			}
			y2Coeffs[idx] = qY2

			// Dequantize and inverse WHT for reconstruction
			var dqY2 [16]int
			for i := 0; i < 16; i++ {
				q := y2DCQ
				if i > 0 {
					q = y2ACQ
				}
				dqY2[i] = qY2[i] * q
			}
			reconDCs := inverseWHT4x4(dqY2)
			for i := 0; i < 16; i++ {
				// Apply IDCT DC scaling: decoder does (DC+4)>>3 for each pixel
				reconYSub[idx][i] = clamp255(yPred + (reconDCs[i]+4)>>3)
			}

			// --- Chroma: 8×8 block-level DC prediction and quantization ---
			// Match decoder's predFunc8DC exactly: one prediction for entire 8×8 chroma block.
			// Left border = 8 pixels (right column of left MB's 8×8 block):
			//   4 from sub-block 1 (top-right) + 4 from sub-block 3 (bottom-right).
			// Above border = 8 pixels (bottom row of above MB's 8×8 block):
			//   4 from sub-block 2 (bottom-left) + 4 from sub-block 3 (bottom-right).
			for plane := 0; plane < 2; plane++ {
				var src *[4]int
				var reconSub [][4]int
				var coeffDst [][4]int
				if plane == 0 {
					src = &mb.u4x4
					reconSub = reconUSub
					coeffDst = uCoeffs
				} else {
					src = &mb.v4x4
					reconSub = reconVSub
					coeffDst = vCoeffs
				}

				// Compute single block-level DC prediction
				var pred int
				if hasLeft && hasAbove {
					leftIdx := idx - 1
					aboveIdx := idx - mbW
					leftSum := 4*reconSub[leftIdx][1] + 4*reconSub[leftIdx][3]
					aboveSum := 4*reconSub[aboveIdx][2] + 4*reconSub[aboveIdx][3]
					pred = (leftSum + aboveSum + 8) / 16
				} else if hasLeft {
					leftIdx := idx - 1
					leftSum := 4*reconSub[leftIdx][1] + 4*reconSub[leftIdx][3]
					pred = (leftSum + 4) / 8
				} else if hasAbove {
					aboveIdx := idx - mbW
					aboveSum := 4*reconSub[aboveIdx][2] + 4*reconSub[aboveIdx][3]
					pred = (aboveSum + 4) / 8
				} else {
					pred = 128
				}

				// Encode all 4 sub-blocks against the single prediction
				for by := 0; by < 2; by++ {
					for bx := 0; bx < 2; bx++ {
						si := by*2 + bx
						actual := src[si]

						// Pre-scale by 8 for DCT/IDCT compensation.
						// The decoder applies inverse IDCT: pixel = (DC+4)>>3.
						res := (actual - pred) * 8
						var qC int
						if res >= 0 {
							qC = (res + dcQ/2) / dcQ
						} else {
							qC = -((-res + dcQ/2) / dcQ)
						}
						if qC > 2047 {
							qC = 2047
						} else if qC < -2047 {
							qC = -2047
						}
						coeffDst[idx][si] = qC
						reconSub[idx][si] = clamp255(pred + (qC*dcQ+4)>>3)
					}
				}
			}

			// Check if MB has any non-zero coefficients
			hasNz := false
			for i := 0; i < 16; i++ {
				if y2Coeffs[idx][i] != 0 {
					hasNz = true
					break
				}
			}
			if !hasNz {
				for i := 0; i < 4; i++ {
					if uCoeffs[idx][i] != 0 || vCoeffs[idx][i] != 0 {
						hasNz = true
						break
					}
				}
			}
			mbHasCoeff[idx] = hasNz
		}
	}

	// --- First partition: frame header + macroblock modes ---
	be := newVP8BoolEnc()

	// §9.2
	be.putBool(false, 128) // color_space=0
	be.putBool(false, 128) // clamping_type=0

	// §9.3: segmentation
	be.putBool(false, 128) // segmentation_enabled=0

	// §9.4: loop filter
	be.putBool(false, 128) // filter_type=0 (normal)
	be.putLit(1, 6)        // loop_filter_level=1
	be.putLit(0, 3)        // sharpness_level=0

	// §9.5: loop filter adjustments
	be.putBool(false, 128) // loop_filter_adj_enable=0

	// §9.5: partitions
	be.putLit(0, 2) // log2_nbr_of_dct_partitions=0 (1 partition)

	// §9.6: quantizer
	be.putLit(uint32(qpIdx), 7) // y_ac_qi
	be.putBool(false, 128)      // y_dc_delta_present=0
	be.putBool(false, 128)      // y2_dc_delta_present=0
	be.putBool(false, 128)      // y2_ac_delta_present=0
	be.putBool(false, 128)      // uv_dc_delta_present=0
	be.putBool(false, 128)      // uv_ac_delta_present=0

	// §9.7: refresh_entropy_probs=0
	be.putBool(false, 128)

	// §13.4: token probability updates — no updates
	for i := 0; i < 4; i++ {
		for j := 0; j < 8; j++ {
			for k := 0; k < 3; k++ {
				for l := 0; l < 11; l++ {
					be.putBool(false, vp8CoefUpdateProbs[i][j][k][l])
				}
			}
		}
	}

	// §9.11: mb_no_coeff_skip=1, prob_skip_false
	be.putBool(true, 128) // mb_no_coeff_skip=1
	be.putLit(128, 8)     // prob_skip_false=128

	// Per-macroblock: mode + skip flag
	for mbY := 0; mbY < mbH; mbY++ {
		for mbX := 0; mbX < mbW; mbX++ {
			idx := mbY*mbW + mbX

			// mb_skip_coeff
			if mbHasCoeff[idx] {
				be.putBool(false, 128) // has coefficients
			} else {
				be.putBool(true, 128) // skip
			}

			// y_mode = DC_PRED (kf_ymode_tree: !B_PRED → DC/V branch → DC)
			be.putBool(true, kfYModeProb[0])  // not B_PRED
			be.putBool(false, kfYModeProb[1]) // left: DC_PRED/V_PRED branch
			be.putBool(false, kfYModeProb[2]) // DC_PRED (not V_PRED)

			// uv_mode = DC_PRED
			be.putBool(false, kfUVModeProb[0])
		}
	}

	firstPart := be.flush()

	// --- Token partition ---
	leftNzY16 := uint8(0)
	aboveNzY16 := make([]uint8, mbW)
	leftNzUV := [4]uint8{}
	aboveNzUV := make([][4]uint8, mbW)

	tp := newVP8BoolEnc()

	for mbY := 0; mbY < mbH; mbY++ {
		leftNzY16 = 0
		leftNzUV = [4]uint8{}
		for mbX := 0; mbX < mbW; mbX++ {
			idx := mbY*mbW + mbX
			if !mbHasCoeff[idx] {
				leftNzY16 = 0
				aboveNzY16[mbX] = 0
				leftNzUV = [4]uint8{}
				aboveNzUV[mbX] = [4]uint8{}
				continue
			}

			// Y2 block (plane=1/planeY2, all 16 WHT coefficients)
			y2Ctx := int(leftNzY16 + aboveNzY16[mbX])
			if y2Ctx > 2 {
				y2Ctx = 2
			}
			y2HasNz := encodeBlock(tp, 1, 0, y2Ctx, y2Coeffs[idx])
			var y2Nz uint8
			if y2HasNz {
				y2Nz = 1
			}
			leftNzY16 = y2Nz
			aboveNzY16[mbX] = y2Nz

			// 16 Y sub-blocks (plane=0/planeY1WithY2, start at band 1)
			// All ACs are zero → each sub-block is just EOB at band 1
			for b := 0; b < 16; b++ {
				tp.putBool(false, vp8DefaultCoefProbs[0][1][0][0]) // EOB
			}

			// 4 U blocks (plane=2/planeUV, band 0)
			// Raster order: (0,0), (1,0), (0,1), (1,1)
			var uNz [4]uint8
			for bi := 0; bi < 4; bi++ {
				by := bi / 2
				bx := bi % 2

				// Compute context from left/above sub-block nz
				var leftNz, aboveNz uint8
				if bx > 0 {
					leftNz = uNz[bi-1]
				} else {
					leftNz = leftNzUV[by] // left MB's right column
				}
				if by > 0 {
					aboveNz = uNz[bi-2]
				} else {
					aboveNz = aboveNzUV[mbX][bx] // above MB's bottom row
				}
				ctx := int(leftNz + aboveNz)
				if ctx > 2 {
					ctx = 2
				}

				val := uCoeffs[idx][bi]
				if val != 0 {
					// NOT-EOB, non-zero, value+sign, then EOB
					tp.putBool(true, vp8DefaultCoefProbs[2][0][ctx][0])
					probs := vp8DefaultCoefProbs[2][0][ctx]
					tp.putBool(true, probs[1])
					writeTokenValue(tp, probs, val)
					nzCtx := 2
					if val == 1 || val == -1 {
						nzCtx = 1
					}
					tp.putBool(false, vp8DefaultCoefProbs[2][1][nzCtx][0]) // EOB
					uNz[bi] = 1
				} else {
					tp.putBool(false, vp8DefaultCoefProbs[2][0][ctx][0]) // EOB
				}
			}

			// 4 V blocks (plane=2/planeUV, band 0) — same pattern
			var vNz [4]uint8
			for bi := 0; bi < 4; bi++ {
				by := bi / 2
				bx := bi % 2

				var leftNz, aboveNz uint8
				if bx > 0 {
					leftNz = vNz[bi-1]
				} else {
					leftNz = leftNzUV[2+by] // left MB's right column (V)
				}
				if by > 0 {
					aboveNz = vNz[bi-2]
				} else {
					aboveNz = aboveNzUV[mbX][2+bx] // above MB's bottom row (V)
				}
				ctx := int(leftNz + aboveNz)
				if ctx > 2 {
					ctx = 2
				}

				val := vCoeffs[idx][bi]
				if val != 0 {
					tp.putBool(true, vp8DefaultCoefProbs[2][0][ctx][0])
					probs := vp8DefaultCoefProbs[2][0][ctx]
					tp.putBool(true, probs[1])
					writeTokenValue(tp, probs, val)
					nzCtx := 2
					if val == 1 || val == -1 {
						nzCtx = 1
					}
					tp.putBool(false, vp8DefaultCoefProbs[2][1][nzCtx][0])
					vNz[bi] = 1
				} else {
					tp.putBool(false, vp8DefaultCoefProbs[2][0][ctx][0])
				}
			}

			// Update neighbor context: right column for left, bottom row for above
			leftNzUV = [4]uint8{uNz[1], uNz[3], vNz[1], vNz[3]}
			aboveNzUV[mbX] = [4]uint8{uNz[2], uNz[3], vNz[2], vNz[3]}
		}
	}

	tokenPart := tp.flush()
	if len(tokenPart) == 0 {
		tokenPart = []byte{0x00}
	}

	// --- Assemble frame ---
	firstPartSize := len(firstPart)
	tag := uint32(0) | (0 << 1) | (1 << 4) | (uint32(firstPartSize) << 5)

	frame := make([]byte, 0, 10+firstPartSize+len(tokenPart))
	frame = append(frame, byte(tag), byte(tag>>8), byte(tag>>16))
	frame = append(frame, 0x9D, 0x01, 0x2A)

	wBytes := make([]byte, 2)
	binary.LittleEndian.PutUint16(wBytes, uint16(w))
	frame = append(frame, wBytes...)

	hBytes := make([]byte, 2)
	binary.LittleEndian.PutUint16(hBytes, uint16(h))
	frame = append(frame, hBytes...)

	frame = append(frame, firstPart...)
	frame = append(frame, tokenPart...)

	return frame, nil
}

func clamp255(v int) int {
	if v < 0 {
		return 0
	}
	if v > 255 {
		return 255
	}
	return v
}
