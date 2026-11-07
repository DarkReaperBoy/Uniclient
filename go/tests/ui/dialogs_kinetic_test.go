package tests

import (
	"testing"

	"uniclient/ui/dialogs"
	. "uniclient/ui/tokens"
)

func TestTouchSpeedSampleManualBlend(t *testing.T) {
	s := dialogs.TouchSpeedSample(dialogs.TouchSpeed{Y: 800}, 0, 3, 10, false)
	if s != (dialogs.TouchSpeed{Y: 425}) {
		t.Fatalf("blend 1 = %+v, want {0 425}", s)
	}
	s = dialogs.TouchSpeedSample(s, 0, -4, 8, false)
	if s != (dialogs.TouchSpeed{Y: -269}) {
		t.Fatalf("blend 2 = %+v, want {0 -269} (106 - 375)", s)
	}
}

func TestTouchSpeedSampleInitialRaw(t *testing.T) {
	s := dialogs.TouchSpeedSample(dialogs.TouchSpeed{}, 0, 30, 10, false)
	if s != (dialogs.TouchSpeed{Y: 3000}) {
		t.Fatalf("initial = %+v, want {0 3000} (raw, no flick clamp)", s)
	}
	s = dialogs.TouchSpeedSample(s, 0, 30, 10, false)
	if s != (dialogs.TouchSpeed{Y: TouchMaxScrollFlick}) {
		t.Fatalf("post-initial = %+v, want {0 %d} (blend clamps)", s, TouchMaxScrollFlick)
	}
}

func TestTouchSpeedSampleIntegerMultiplier(t *testing.T) {
	s := dialogs.TouchSpeedSample(dialogs.TouchSpeed{}, 0, 4, 7, false)
	if s != (dialogs.TouchSpeed{Y: 568}) {
		t.Fatalf("mul quirk = %+v, want {0 568} (4*142, 1000/7 trunc)", s)
	}
}

func TestTouchSpeedSampleAccuracy(t *testing.T) {
	s := dialogs.TouchSpeedSample(dialogs.TouchSpeed{Y: 500}, 0, 2, 1000, false)
	if s != (dialogs.TouchSpeed{Y: 125}) {
		t.Fatalf("below accuracy = %+v, want {0 125} (new speed zeroed)", s)
	}
	s = dialogs.TouchSpeedSample(dialogs.TouchSpeed{}, 3, 0, 100, false)
	if s != (dialogs.TouchSpeed{X: 30}) {
		t.Fatalf("x axis kept = %+v, want {30 0}", s)
	}
}

func TestTouchSpeedSampleAutoBlend(t *testing.T) {
	s := dialogs.TouchSpeedSample(dialogs.TouchSpeed{Y: -3000}, 0, -8, 10, true)
	if s != (dialogs.TouchSpeed{Y: -3200}) {
		t.Fatalf("accelerate = %+v, want {0 -3200} (-3000 + -800/4)", s)
	}
	s = dialogs.TouchSpeedSample(dialogs.TouchSpeed{Y: 500}, 0, -8, 10, true)
	if s != (dialogs.TouchSpeed{Y: 300}) {
		t.Fatalf("opposite y, zero x = %+v, want {0 300} (compat passes, blend)", s)
	}
	s = dialogs.TouchSpeedSample(dialogs.TouchSpeed{X: -5, Y: 500}, 6, -3, 10, true)
	if s != (dialogs.TouchSpeed{}) {
		t.Fatalf("x straddle = %+v, want {0 0} (direction mismatch zeroes)", s)
	}
}

func TestFlingDelta(t *testing.T) {
	if dx, dy := dialogs.FlingDelta(dialogs.TouchSpeed{Y: -1000}, 15); dx != 0 || dy != -15 {
		t.Fatalf("fling delta = (%d,%d), want (0,-15)", dx, dy)
	}
	if dx, dy := dialogs.FlingDelta(dialogs.TouchSpeed{Y: 7}, 15); dx != 0 || dy != 0 {
		t.Fatalf("small fling = (%d,%d), want (0,0) (105/1000 trunc)", dx, dy)
	}
	if dx, dy := dialogs.FlingDelta(dialogs.TouchSpeed{X: 1000, Y: -1000}, 15); dx != 15 || dy != -15 {
		t.Fatalf("both axes = (%d,%d), want (15,-15)", dx, dy)
	}
	if _, dy := dialogs.FlingDelta(dialogs.TouchSpeed{Y: -7}, 15); dy != 0 {
		t.Fatalf("negative trunc = %d, want 0", dy)
	}
}

func TestTouchDeaccelerate(t *testing.T) {
	if s := dialogs.TouchDeaccelerate(dialogs.TouchSpeed{Y: -1000}, 15); s != (dialogs.TouchSpeed{Y: -985}) {
		t.Fatalf("deaccel = %+v, want {0 -985}", s)
	}
	if s := dialogs.TouchDeaccelerate(dialogs.TouchSpeed{Y: 7}, 15); s != (dialogs.TouchSpeed{}) {
		t.Fatalf("deaccel to zero = %+v, want {0 0}", s)
	}
	if s := dialogs.TouchDeaccelerate(dialogs.TouchSpeed{X: 12, Y: -20}, 15); s != (dialogs.TouchSpeed{Y: -5}) {
		t.Fatalf("deaccel both = %+v, want {0 -5}", s)
	}
}

func TestWillScrollToWiden(t *testing.T) {
	cases := []struct {
		from, target, max, want int
	}{
		{350, -100, 692, 0},
		{350, 1000, 692, 692},
		{0, -50, 692, 0},
		{692, 800, 692, 692},
		{-50, -80, 692, -50},
		{-50, 300, 692, 300},
		{-50, 800, 692, 692},
		{700, 800, 692, 700},
		{700, -30, 692, 0},
	}
	for i, c := range cases {
		if got := dialogs.WillScrollTo(c.from, c.target, c.max); got != c.want {
			t.Fatalf("case %d: willScrollTo(%d,%d,%d) = %d, want %d", i, c.from, c.target, c.max, got, c.want)
		}
	}
}

func TestOverscrollBand(t *testing.T) {
	from := map[int]int{60: 3, -60: -3, 10: 1, 9: 0, 30: 2, 29: 1, -50: -3, 0: 0}
	for acc, want := range from {
		if got := dialogs.OverscrollFromAccumulated(acc); got != want {
			t.Fatalf("fromAccumulated(%d) = %d, want %d", acc, got, want)
		}
	}
	to := map[int]int{1: 20, -2: -40, 3: 60, -3: -60}
	for stretch, want := range to {
		if got := dialogs.OverscrollToAccumulated(stretch); got != want {
			t.Fatalf("toAccumulated(%d) = %d, want %d", stretch, got, want)
		}
	}
	if got := dialogs.OverscrollToAccumulated(dialogs.OverscrollFromAccumulated(37)); got != 40 {
		t.Fatalf("roundtrip 37 = %d, want 40", got)
	}
}

func TestTrackVelocity(t *testing.T) {
	var o dialogs.Overscroll
	o.TrackVelocity(dialogs.PhaseUpdate, -100, 1010, 1010)
	if o.Velocity != 0 || o.VelocityTime != 1010 {
		t.Fatalf("first update = %v/%d, want 0/1010 (no baseline)", o.Velocity, o.VelocityTime)
	}
	o.TrackVelocity(dialogs.PhaseUpdate, -100, 1020, 1020)
	if o.Velocity != -MaxTrackedVelocity || o.VelocityTime != 1020 {
		t.Fatalf("second update = %v/%d, want -6000/1020", o.Velocity, o.VelocityTime)
	}
	o.TrackVelocity(dialogs.PhaseMomentum, 50, 2000, 2000)
	if o.Velocity != -MaxTrackedVelocity || o.VelocityTime != 1020 {
		t.Fatalf("momentum gap = %v/%d, want -6000/1020 (kept)", o.Velocity, o.VelocityTime)
	}
	o.TrackVelocity(dialogs.PhaseBegin, 0, 3000, 3000)
	if o.Velocity != 0 || o.VelocityTime != 0 || o.LastEventTime != 3000 {
		t.Fatalf("begin reset = %v/%d/%d, want 0/0/3000", o.Velocity, o.VelocityTime, o.LastEventTime)
	}
	o.TrackVelocity(dialogs.PhaseUpdate, -100, 3200, 3200)
	if o.Velocity != 0 || o.VelocityTime != 3200 {
		t.Fatalf("stale update = %v/%d, want 0/3200 (elapsed 200 zeroes)", o.Velocity, o.VelocityTime)
	}
}

func TestApplyInputDragOverscrollTop(t *testing.T) {
	var o dialogs.Overscroll
	from := o.ApplyInput(0, 692, -30, dialogs.PhaseUpdate, true, 1000, 1000)
	if from != -3 || o.Stretch != -3 || o.Accumulated != -60 {
		t.Fatalf("drag 1 = from %d stretch %d acc %d, want -3/-3/-60", from, o.Stretch, o.Accumulated)
	}
	from = o.ApplyInput(from, 692, -30, dialogs.PhaseUpdate, true, 1015, 1015)
	if from != -6 || o.Stretch != -6 || o.Accumulated != -120 {
		t.Fatalf("drag 2 = from %d stretch %d acc %d, want -6/-6/-120", from, o.Stretch, o.Accumulated)
	}
	if o.Velocity != -2000 {
		t.Fatalf("tracked velocity = %v, want -2000 (-30*1000/15)", o.Velocity)
	}
}

func TestApplyInputMinimumPending(t *testing.T) {
	var o dialogs.Overscroll
	from := o.ApplyInput(0, 692, -4, dialogs.PhaseUpdate, true, 1000, 1000)
	if from != 0 || o.Stretch != 0 || o.Pending != -8 {
		t.Fatalf("pending below min = from %d stretch %d pending %d, want 0/0/-8", from, o.Stretch, o.Pending)
	}
	from = o.ApplyInput(from, 692, -4, dialogs.PhaseUpdate, true, 1010, 1010)
	if from != -1 || o.Stretch != -1 || o.Pending != 0 {
		t.Fatalf("pending crosses min = from %d stretch %d pending %d, want -1/-1/0", from, o.Stretch, o.Pending)
	}
}

func TestApplyInputReconcile(t *testing.T) {
	var o dialogs.Overscroll
	from := o.ApplyInput(0, 692, -30, dialogs.PhaseUpdate, true, 1000, 1000)
	from = o.ApplyInput(from, 692, 30, dialogs.PhaseUpdate, true, 1015, 1015)
	if from != 27 || o.Stretch != 0 || o.Accumulated != 0 {
		t.Fatalf("full unwind = from %d stretch %d acc %d, want 27/0/0 (3 stretch + 24 scroll)", from, o.Stretch, o.Accumulated)
	}
}

func TestApplyInputPartialUnwind(t *testing.T) {
	var o dialogs.Overscroll
	from := o.ApplyInput(0, 692, -30, dialogs.PhaseUpdate, true, 1000, 1000)
	from = o.ApplyInput(from, 692, 2, dialogs.PhaseUpdate, true, 1015, 1015)
	if from != -1 || o.Stretch != -1 || o.Accumulated != -20 {
		t.Fatalf("partial unwind = from %d stretch %d acc %d, want -1/-1/-20", from, o.Stretch, o.Accumulated)
	}
}

func TestApplyInputFlingIntoEdge(t *testing.T) {
	var o dialogs.Overscroll
	from := o.ApplyInput(692, 692, 40, dialogs.PhaseMomentum, true, 5000, 5000)
	if from != 696 || o.Stretch != 4 || !o.Returning || o.SpringSide != 1 {
		t.Fatalf("edge hit = from %d stretch %d returning %v side %d, want 696/4/true/1", from, o.Stretch, o.Returning, o.SpringSide)
	}
	if o.SpringX0 != 4 || o.SpringV0 != 0 {
		t.Fatalf("spring seed = %v/%v, want 4/0", o.SpringX0, o.SpringV0)
	}
	from = o.ApplyInput(from, 692, 40, dialogs.PhaseMomentum, true, 5015, 5015)
	if from != 696 || o.Stretch != 4 {
		t.Fatalf("same-direction momentum = from %d stretch %d, want 696/4 (consumed by bounce)", from, o.Stretch)
	}
}

func TestSpringUpdateNoVelocity(t *testing.T) {
	var o dialogs.Overscroll
	o.Stretch = 4
	o.Accumulated = 80
	o.Return(5000)
	from := o.SpringUpdate(692+4, 692, 5015)
	if from != 692+3 || o.Stretch != 3 {
		t.Fatalf("spring 15ms = from %d stretch %d, want 695/3", from, o.Stretch)
	}
	from = o.SpringUpdate(from, 692, 5100)
	if from != 692+1 || o.Stretch != 1 {
		t.Fatalf("spring 100ms = from %d stretch %d, want 693/1", from, o.Stretch)
	}
	from = o.SpringUpdate(from, 692, 5200)
	if from != 692 || o.Stretch != 0 || o.Returning || o.Accumulated != 0 {
		t.Fatalf("spring 200ms = from %d stretch %d returning %v acc %d, want 692/0/false/0", from, o.Stretch, o.Returning, o.Accumulated)
	}
}

func TestSpringUpdateOvershoot(t *testing.T) {
	var o dialogs.Overscroll
	o.Stretch = -50
	o.Accumulated = -1000
	o.Velocity = -3000
	o.VelocityTime = 1990
	o.Return(2000)
	if o.SpringPeak < 0.0262 || o.SpringPeak > 0.0263 {
		t.Fatalf("peak time = %v, want ~0.02624", o.SpringPeak)
	}
	from := o.SpringUpdate(-50, 692, 2026)
	if from != -54 || o.Stretch != -54 {
		t.Fatalf("overshoot = from %d stretch %d, want -54/-54 (velocity pushes deeper)", from, o.Stretch)
	}
	from = o.SpringUpdate(from, 692, 2100)
	if from != -41 || o.Stretch != -41 {
		t.Fatalf("100ms = %d, want -41", from)
	}
	from = o.SpringUpdate(from, 692, 2200)
	if from != -19 || o.Stretch != -19 {
		t.Fatalf("200ms = %d, want -19", from)
	}
	from = o.SpringUpdate(from, 692, 2300)
	if from != -8 || o.Stretch != -8 {
		t.Fatalf("300ms = %d, want -8", from)
	}
	from = o.SpringUpdate(from, 692, 2400)
	if from != -3 || o.Stretch != -3 {
		t.Fatalf("400ms = %d, want -3", from)
	}
	from = o.SpringUpdate(from, 692, 2500)
	if from != -1 || o.Stretch != -1 {
		t.Fatalf("500ms = %d, want -1", from)
	}
	from = o.SpringUpdate(from, 692, 2600)
	if from != 0 || o.Stretch != 0 || o.Returning || o.Accumulated != 0 {
		t.Fatalf("600ms = from %d stretch %d returning %v acc %d, want 0/0/false/0 (finish)", from, o.Stretch, o.Returning, o.Accumulated)
	}
}

func TestSpringUpdateCrossFinish(t *testing.T) {
	var o dialogs.Overscroll
	o.Stretch = -50
	o.Accumulated = -1000
	o.Velocity = 2000
	o.VelocityTime = 1990
	o.Return(2000)
	if o.SpringPeak != 0 {
		t.Fatalf("peak = %v, want 0 (push opposes reference)", o.SpringPeak)
	}
	from := o.SpringUpdate(-50, 692, 2050)
	if from != -10 || o.Stretch != -10 {
		t.Fatalf("50ms = %d, want -10", from)
	}
	from = o.SpringUpdate(from, 692, 2100)
	if from != 0 || o.Stretch != 0 || o.Returning {
		t.Fatalf("100ms = from %d stretch %d returning %v, want 0/0/false (crossed)", from, o.Stretch, o.Returning)
	}
}

func TestApplyInputEndStartsSpring(t *testing.T) {
	var o dialogs.Overscroll
	from := o.ApplyInput(0, 692, -30, dialogs.PhaseUpdate, true, 1000, 1000)
	o.Velocity = -600
	o.VelocityTime = 4990
	from = o.ApplyInput(from, 692, 0, dialogs.PhaseEnd, true, 5000, 5000)
	if from != -3 || !o.Returning || o.SpringSide != -1 || o.SpringX0 != -3 || o.SpringV0 != -600 {
		t.Fatalf("end event = from %d returning %v side %d x0 %v v0 %v, want -3/true/-1/-3/-600", from, o.Returning, o.SpringSide, o.SpringX0, o.SpringV0)
	}
	if o.IgnoreMomentum != -3 {
		t.Fatalf("ignore momentum = %d, want -3", o.IgnoreMomentum)
	}
	from = o.SpringUpdate(from, 692, 5050)
	if from != -7 || o.Stretch != -7 {
		t.Fatalf("50ms = %d, want -7", from)
	}
	from = o.SpringUpdate(from, 692, 5100)
	if from != -6 || o.Stretch != -6 {
		t.Fatalf("100ms = %d, want -6", from)
	}
	from = o.SpringUpdate(from, 692, 5200)
	if from != -3 || o.Stretch != -3 {
		t.Fatalf("200ms = %d, want -3", from)
	}
	from = o.SpringUpdate(from, 692, 5300)
	if from != -1 || o.Stretch != -1 {
		t.Fatalf("300ms = %d, want -1", from)
	}
	from = o.SpringUpdate(from, 692, 5500)
	if from != 0 || o.Stretch != 0 || o.Returning {
		t.Fatalf("500ms = %d stretch %d, want 0/0 (finish)", from, o.Stretch)
	}
}

func TestApplyInputBeginCancelsSpring(t *testing.T) {
	var o dialogs.Overscroll
	o.Stretch = -2
	o.Accumulated = -60
	o.Returning = true
	o.ReturnStart = 5000
	o.SpringSide = -1
	o.SpringX0 = -3
	o.IgnoreMomentum = -3
	from := o.ApplyInput(-2, 692, 0, dialogs.PhaseBegin, true, 6000, 6000)
	if from != -2 || o.Returning || o.SpringSide != 0 || o.Accumulated != -40 || o.Stretch != -2 {
		t.Fatalf("begin cancel = from %d returning %v side %d acc %d stretch %d, want -2/false/0/-40/-2", from, o.Returning, o.SpringSide, o.Accumulated, o.Stretch)
	}
	if o.Velocity != 0 || o.VelocityTime != 0 || o.Pending != 0 {
		t.Fatalf("begin resets = %v/%d/%d, want 0/0/0", o.Velocity, o.VelocityTime, o.Pending)
	}
}

func TestApplyInputOppositeMomentumCancelsSpring(t *testing.T) {
	var o dialogs.Overscroll
	o.Stretch = -2
	o.Accumulated = -60
	o.Returning = true
	o.ReturnStart = 5000
	o.SpringSide = -1
	o.SpringX0 = -3
	o.IgnoreMomentum = -3
	from := o.ApplyInput(-2, 692, 20, dialogs.PhaseMomentum, true, 5020, 5020)
	if from != 18 || o.Stretch != 0 || o.Returning {
		t.Fatalf("opposite momentum = from %d stretch %d returning %v, want 18/0/false (cancel + unwind + scroll)", from, o.Stretch, o.Returning)
	}
}
