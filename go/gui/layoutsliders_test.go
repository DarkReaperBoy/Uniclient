package gui

// Layout tweak sliders (slice 93, matrix row 246): label formatting,
// clamping/defaults through the engine config boundary, and the legacy
// corners-toggle fold-in.

import (
	"testing"

	"uniclient/utils"
)

func TestLayoutSliderLabels(t *testing.T) {
	if got := bubbleRadiusSliderLabel(12); got != "12 dp" {
		t.Errorf("radius label = %q", got)
	}
	if got := bubbleRadiusSliderLabel(0); got != "0 dp" {
		t.Errorf("radius label(0) = %q", got)
	}
	if got := wideSliderLabel(0.75); got != "75%" {
		t.Errorf("wide label = %q", got)
	}
	if got := wideSliderLabel(1.0); got != "100%" {
		t.Errorf("wide label(1.0) = %q", got)
	}
}

func TestEffectiveLayoutTweaks(t *testing.T) {
	// Defaults: no slider fields set → 12 dp / 0.75 (the pre-slider
	// look), regardless of the legacy toggle.
	def := utils.DefaultConfig()
	if got := utils.EffectiveBubbleRadius(def); got != 12 {
		t.Errorf("default radius = %d, want 12", got)
	}
	if got := utils.EffectiveWideMultiplier(def); got != 0.75 {
		t.Errorf("default wide = %v, want 0.75", got)
	}

	// Legacy fold: square toggle → 2 dp.
	sq := utils.DefaultConfig()
	square := false
	sq.BubbleCorners = &square
	if got := utils.EffectiveBubbleRadius(sq); got != 2 {
		t.Errorf("legacy square radius = %d, want 2", got)
	}

	// New slider wins over the legacy toggle.
	both := utils.DefaultConfig()
	r := 6
	both.BubbleRadius = &r
	both.BubbleCorners = &square
	if got := utils.EffectiveBubbleRadius(both); got != 6 {
		t.Errorf("slider radius = %d, want 6 (wins over toggle)", got)
	}

	// Clamps.
	if got := utils.ClampBubbleRadius(-3); got != 0 {
		t.Errorf("clamp radius low = %d", got)
	}
	if got := utils.ClampBubbleRadius(99); got != 18 {
		t.Errorf("clamp radius high = %d", got)
	}
	if got := utils.ClampWideMultiplier(0.5); got != 0.70 {
		t.Errorf("clamp wide low = %v", got)
	}
	if got := utils.ClampWideMultiplier(1.4); got != 1.00 {
		t.Errorf("clamp wide high = %v", got)
	}
}
