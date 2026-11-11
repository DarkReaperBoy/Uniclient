package tests

import (
	"testing"

	"uniclient/ui/history"
	. "uniclient/ui/tokens"
)

func TestCornerRippleTokens(t *testing.T) {
	if HistoryToDownRippleShowMs != 650 {
		t.Fatalf("ripple show duration = %d, want 650 (defaultRippleAnimation.showDuration, widgets.style)",
			HistoryToDownRippleShowMs)
	}
	if HistoryToDownRippleHideMs != 200 {
		t.Fatalf("ripple hide duration = %d, want 200 (defaultRippleAnimation.hideDuration, widgets.style)",
			HistoryToDownRippleHideMs)
	}
	if StateLayerHoverAlpha != 0.08 {
		t.Fatalf("hover state layer alpha = %v, want 0.08 (Material interaction states)",
			StateLayerHoverAlpha)
	}
	if StateLayerRippleAlpha != 0.12 {
		t.Fatalf("ripple state layer alpha = %v, want 0.12 (Material interaction states)",
			StateLayerRippleAlpha)
	}
}

func TestRippleMaxRadius(t *testing.T) {
	if r := history.RippleMaxRadius(0, 0); r != 59 {
		t.Fatalf("top-left origin max radius = %d, want 59 (42*sqrt2 rounded)", r)
	}
	if r := history.RippleMaxRadius(21, 21); r != 30 {
		t.Fatalf("center origin max radius = %d, want 30 (21*sqrt2 rounded)", r)
	}
	if r := history.RippleMaxRadius(-5, -15); r != 74 {
		t.Fatalf("origin outside the ripple area max radius = %d, want 74", r)
	}
	if r := history.RippleMaxRadius(9, 17); r != 41 {
		t.Fatalf("(9,17) origin max radius = %d, want 41", r)
	}
}

func TestRippleShowEaseOutQuint(t *testing.T) {
	st := history.RippleState{OriginX: 21, OriginY: 21, Started: 1000}
	v := history.RippleView(st, 1000)
	if v.Radius != 0 || v.Alpha != 1 || v.OriginX != 21 || v.OriginY != 21 {
		t.Fatalf("press instant: %+v, want radius 0 alpha 1 same origin", v)
	}
	v = history.RippleView(st, 1130)
	if v.Radius != 20 {
		t.Fatalf("radius at 130ms = %d, want 20 (easeOutQuint 0.67232 * 30)", v.Radius)
	}
	v = history.RippleView(st, 1325)
	if v.Radius != 29 {
		t.Fatalf("radius at half show = %d, want 29 (easeOutQuint 0.96875 * 30)", v.Radius)
	}
	v = history.RippleView(st, 1650)
	if v.Radius != 30 {
		t.Fatalf("radius past show end = %d, want 30", v.Radius)
	}
	if v.Alpha != 1 {
		t.Fatalf("alpha without release = %v, want 1", v.Alpha)
	}
}

func TestRippleFadeLinearAndRadiusGrows(t *testing.T) {
	st := history.RippleState{OriginX: 21, OriginY: 21, Started: 1000, Fading: true, FadeStarted: 1200}
	v := history.RippleView(st, 1200)
	if v.Alpha != 1 || v.Radius != 25 {
		t.Fatalf("fade start: alpha %v radius %d, want 1 and 25 (200ms shown)", v.Alpha, v.Radius)
	}
	v = history.RippleView(st, 1300)
	if v.Alpha != 0.5 {
		t.Fatalf("fade mid alpha = %v, want 0.5 (linear 200ms)", v.Alpha)
	}
	if v.Radius <= 25 {
		t.Fatalf("radius must keep growing through the fade, got %d", v.Radius)
	}
	v = history.RippleView(st, 1400)
	if v.Alpha != 0 {
		t.Fatalf("fade end alpha = %v, want 0", v.Alpha)
	}
	if v.Radius != 30 {
		t.Fatalf("radius at fade end = %d, want fully shown 30", v.Radius)
	}
}
