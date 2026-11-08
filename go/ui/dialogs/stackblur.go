package dialogs

import "image"

func StackBlur(src *image.NRGBA, radius int) *image.NRGBA {
	w := src.Bounds().Dx()
	h := src.Bounds().Dy()
	if w <= radius || h <= radius || radius < 1 {
		return src
	}

	div := 2*radius + 1
	radiusP1 := radius + 1
	divsum := radiusP1 * radiusP1
	wm1 := w - 1
	hm1 := h - 1

	dv := make([]int, 256*divsum)
	for i := range dv {
		dv[i] = i / divsum
	}
	stack := make([]int, div*3)
	vmin := make([]int, max(w, h))
	rgb := make([]uint8, w*h*3)

	pix := func(x, y int) (int, int, int) {
		i := (y-src.Bounds().Min.Y)*src.Stride + (x-src.Bounds().Min.X)*4
		return int(src.Pix[i]), int(src.Pix[i+1]), int(src.Pix[i+2])
	}
	setPix := func(x, y int, r, g, b int) {
		i := (y-src.Bounds().Min.Y)*src.Stride + (x-src.Bounds().Min.X)*4
		src.Pix[i] = uint8(r)
		src.Pix[i+1] = uint8(g)
		src.Pix[i+2] = uint8(b)
	}

	for x := 0; x < w; x++ {
		vmin[x] = min(x+radiusP1, wm1)
	}
	for y := 0; y < h; y++ {
		var rinsum, ginsum, binsum int
		var routsum, goutsum, boutsum int
		var rsum, gsum, bsum int
		for i := -radius; i <= radius; i++ {
			x := clampInt(i, 0, wm1)
			r, g, b := pix(x, y)
			si := (i + radius) * 3
			stack[si], stack[si+1], stack[si+2] = r, g, b
			rbs := radiusP1 - absInt(i)
			rsum += r * rbs
			gsum += g * rbs
			bsum += b * rbs
			if i > 0 {
				rinsum += r
				ginsum += g
				binsum += b
			} else {
				routsum += r
				goutsum += g
				boutsum += b
			}
		}
		stackpointer := radius
		for x := 0; x < w; x++ {
			pos := (y*w + x) * 3
			rgb[pos] = uint8(dv[rsum])
			rgb[pos+1] = uint8(dv[gsum])
			rgb[pos+2] = uint8(dv[bsum])

			rsum -= routsum
			gsum -= goutsum
			bsum -= boutsum

			stackstart := (stackpointer - radius + div) % div
			si := stackstart * 3
			routsum -= stack[si]
			goutsum -= stack[si+1]
			boutsum -= stack[si+2]

			xr := vmin[x]
			r, g, b := pix(xr, y)
			stack[si], stack[si+1], stack[si+2] = r, g, b
			rinsum += r
			ginsum += g
			binsum += b

			rsum += rinsum
			gsum += ginsum
			bsum += binsum

			stackpointer = (stackpointer + 1) % div
			si = stackpointer * 3
			routsum += stack[si]
			goutsum += stack[si+1]
			boutsum += stack[si+2]
			rinsum -= stack[si]
			ginsum -= stack[si+1]
			binsum -= stack[si+2]
		}
	}

	for y := 0; y < h; y++ {
		vmin[y] = min(y+radiusP1, hm1) * w
	}
	for x := 0; x < w; x++ {
		var rinsum, ginsum, binsum int
		var routsum, goutsum, boutsum int
		var rsum, gsum, bsum int
		for i := -radius; i <= radius; i++ {
			y := clampInt(i, 0, hm1)
			pos := (y*w + x) * 3
			si := (i + radius) * 3
			stack[si] = int(rgb[pos])
			stack[si+1] = int(rgb[pos+1])
			stack[si+2] = int(rgb[pos+2])
			rbs := radiusP1 - absInt(i)
			rsum += stack[si] * rbs
			gsum += stack[si+1] * rbs
			bsum += stack[si+2] * rbs
			if i > 0 {
				rinsum += stack[si]
				ginsum += stack[si+1]
				binsum += stack[si+2]
			} else {
				routsum += stack[si]
				goutsum += stack[si+1]
				boutsum += stack[si+2]
			}
		}
		stackpointer := radius
		for y := 0; y < h; y++ {
			r, g, b := dv[rsum], dv[gsum], dv[bsum]
			setPix(x, y, r, g, b)

			rsum -= routsum
			gsum -= goutsum
			bsum -= boutsum

			stackstart := (stackpointer - radius + div) % div
			si := stackstart * 3
			routsum -= stack[si]
			goutsum -= stack[si+1]
			boutsum -= stack[si+2]

			pos := (vmin[y] + x) * 3
			stack[si] = int(rgb[pos])
			stack[si+1] = int(rgb[pos+1])
			stack[si+2] = int(rgb[pos+2])
			rinsum += stack[si]
			ginsum += stack[si+1]
			binsum += stack[si+2]

			rsum += rinsum
			gsum += ginsum
			bsum += binsum

			stackpointer = (stackpointer + 1) % div
			si = stackpointer * 3
			routsum += stack[si]
			goutsum += stack[si+1]
			boutsum += stack[si+2]
			rinsum -= stack[si]
			ginsum -= stack[si+1]
			binsum -= stack[si+2]
		}
	}
	return src
}
