package dialogs

import "uniclient/ui/tokens"

func qRound(d float64) int {
	if d >= 0 {
		return int(d + 0.5)
	}
	return int(d - 0.5)
}

func absInt(v int) int {
	if v < 0 {
		return -v
	}
	return v
}

func maxInt(a, b int) int {
	if a > b {
		return a
	}
	return b
}

func wheelApply(unmultX, unmultY, areaW, areaH int, accelerate bool) int {
	px, py := unmultX, unmultY
	if accelerate {
		notch := float64(tokens.WheelNotchAngleDelta)
		px = int(float64(unmultX) * float64(maxInt(areaW, tokens.WheelNotchAngleDelta)) / notch)
		py = int(float64(unmultY) * float64(maxInt(areaH, tokens.WheelNotchAngleDelta)) / notch)
	}
	if absInt(px) >= absInt(py) {
		return 0
	}
	return -py
}

func WheelDelta(angleX, angleY, lines, areaW, areaH int, accelerate bool) int {
	scale := float64(lines) / float64(tokens.WheelPixelToAngleDelta*tokens.WheelScrollLines)
	return wheelApply(qRound(float64(angleX)*scale), qRound(float64(angleY)*scale), areaW, areaH, accelerate)
}

func ScrollPixels(pixelX, pixelY, areaW, areaH int, accelerate bool) int {
	return wheelApply(qRound(float64(pixelX)), qRound(float64(pixelY)), areaW, areaH, accelerate)
}

func BarOver(t Thumb, x, y int) bool {
	if t.Hidden {
		return false
	}
	thickness := tokens.ScrollBarWidth - 2*tokens.ScrollBarDeltax
	return x >= tokens.ScrollBarDeltax && x < tokens.ScrollBarDeltax+thickness &&
		y >= t.Y && y < t.Y+t.H
}

func (l List) BarTrackJump(v Viewport, width, trackH, y int) int {
	thumb := l.ScrollbarThumb(v, width, trackH)
	if thumb.Hidden {
		return v.Top
	}
	fullSkip := tokens.ScrollBarDeltat + tokens.ScrollBarDeltab
	available := trackH - fullSkip
	bar := thumb.H
	half := bar / 2
	middle := clampInt(y, tokens.ScrollBarDeltat+half, tokens.ScrollBarDeltat+available+half-bar)
	scrollable := l.MaxOffset(width, v.Height)
	return scrollable * (middle - half - tokens.ScrollBarDeltat) / (available - bar)
}

func (l List) BarDragScale(v Viewport, width, trackH, dy int) int {
	thumb := l.ScrollbarThumb(v, width, trackH)
	if thumb.Hidden {
		return dy
	}
	fullSkip := tokens.ScrollBarDeltat + tokens.ScrollBarDeltab
	available := trackH - fullSkip
	outsideBar := available - thumb.H
	scrollable := l.MaxOffset(width, v.Height)
	if outsideBar <= 0 || scrollable <= outsideBar {
		return dy
	}
	return dy * scrollable / outsideBar
}
