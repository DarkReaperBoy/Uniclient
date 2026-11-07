package dialogs

import (
	"math"

	"uniclient/ui/tokens"
)

type Phase int

const (
	PhaseNone Phase = iota
	PhaseBegin
	PhaseUpdate
	PhaseEnd
	PhaseMomentum
)

const (
	TouchScrollManual       = 0
	TouchScrollAuto         = 1
	TouchScrollAcceleration = 2
)

type TouchSpeed struct {
	X int
	Y int
}

func oppositeSigns(a, b int) bool {
	return (a < 0 && b > 0) || (a > 0 && b < 0)
}

func minInt(a, b int) int {
	if a < b {
		return a
	}
	return b
}

func TouchSpeedSample(prev TouchSpeed, diffX, diffY, elapsed int, auto bool) TouchSpeed {
	if elapsed == 0 {
		return prev
	}
	mul := 1000 / elapsed
	newX, newY := 0, 0
	if absInt(diffY*mul) > tokens.TouchFingerAccuracy {
		newY = diffY * mul
	}
	if absInt(diffX*mul) > tokens.TouchFingerAccuracy {
		newX = diffX * mul
	}
	if auto {
		oldX, oldY := prev.X, prev.Y
		if (oldY <= 0 && newY <= 0) || ((oldY >= 0 && newY >= 0) && (oldX <= 0 && newX <= 0)) || (oldX >= 0 && newX >= 0) {
			return TouchSpeed{
				X: clampInt(oldX+newX/4, -tokens.TouchMaxScrollAccelerated, tokens.TouchMaxScrollAccelerated),
				Y: clampInt(oldY+newY/4, -tokens.TouchMaxScrollAccelerated, tokens.TouchMaxScrollAccelerated),
			}
		}
		return TouchSpeed{}
	}
	if prev.X != 0 || prev.Y != 0 {
		return TouchSpeed{
			X: clampInt(prev.X/4+newX*3/4, -tokens.TouchMaxScrollFlick, tokens.TouchMaxScrollFlick),
			Y: clampInt(prev.Y/4+newY*3/4, -tokens.TouchMaxScrollFlick, tokens.TouchMaxScrollFlick),
		}
	}
	return TouchSpeed{X: newX, Y: newY}
}

func TouchDeaccelerate(s TouchSpeed, elapsed int) TouchSpeed {
	return TouchSpeed{X: deaccelAxis(s.X, elapsed), Y: deaccelAxis(s.Y, elapsed)}
}

func deaccelAxis(v, elapsed int) int {
	if v == 0 {
		return 0
	}
	if v > 0 {
		return maxInt(0, v-elapsed)
	}
	return -maxInt(0, -v-elapsed)
}

func FlingDelta(s TouchSpeed, elapsed int) (int, int) {
	return (s.X * elapsed / 1000), (s.Y * elapsed / 1000)
}

func OverscrollFromAccumulated(acc int) int {
	return qRound(float64(acc) / tokens.RubberBandStiffness)
}

func OverscrollToAccumulated(stretch int) int {
	return qRound(float64(stretch) * tokens.RubberBandStiffness)
}

func WillScrollTo(from, target, max int) int {
	lower := from
	if lower > 0 {
		lower = 0
	}
	upper := from
	if upper < max {
		upper = max
	}
	return clampInt(target, lower, upper)
}

type Overscroll struct {
	Stretch        int
	Accumulated    int
	Pending        int
	Returning      bool
	ReturnStart    int
	SpringSide     int
	SpringX0       float64
	SpringV0       float64
	SpringPeak     float64
	IgnoreMomentum int
	Velocity       float64
	VelocityTime   int
	LastEventTime  int
	LastMomentum   bool
}

func (o *Overscroll) Animating(now int) bool {
	return o.Returning && now-o.ReturnStart < tokens.RubberBandMaxReturnMs
}

func (o Overscroll) springSideOf(side int) bool {
	return side != 0
}

func (o Overscroll) collapsing() bool {
	stretch := o.Stretch
	return stretch != 0 && oppositeSigns(stretch, o.Stretch)
}

func (o *Overscroll) TrackVelocity(phase Phase, delta, eventTime, now int) {
	if eventTime == 0 {
		eventTime = now
	}
	momentum := phase == PhaseMomentum
	if phase != PhaseUpdate && !momentum {
		if phase == PhaseBegin {
			o.Velocity = 0
			o.VelocityTime = 0
			o.LastEventTime = eventTime
			o.Pending = 0
		}
		o.LastMomentum = false
		return
	}
	elapsed := 0
	if o.LastEventTime != 0 {
		elapsed = eventTime - o.LastEventTime
	}
	if elapsed > 0 && elapsed < tokens.VelocityZeroingMs {
		limit := float64(tokens.MaxTrackedVelocity)
		v := float64(delta) * 1000 / float64(elapsed)
		if v > limit {
			v = limit
		} else if v < -limit {
			v = -limit
		}
		o.Velocity = v
		o.VelocityTime = now
	} else if !momentum || o.LastMomentum {
		o.Velocity = 0
		o.VelocityTime = now
	}
	o.LastEventTime = eventTime
	o.LastMomentum = momentum
}

func (o *Overscroll) applyOverscroll(stretch, from, max int) int {
	if o.Stretch == stretch {
		return from
	}
	o.Stretch = stretch
	if stretch > 0 {
		return max + stretch
	}
	if stretch < 0 {
		return stretch
	}
	return clampInt(from, 0, max)
}

func (o *Overscroll) checkReturnFinish(now int) {
	if !o.Returning {
		return
	}
	if !o.Animating(now) {
		o.Returning = false
		o.Accumulated = 0
	} else if o.Stretch == 0 {
		o.ReturnStart = 0
		o.Returning = false
		o.Accumulated = 0
		o.SpringSide = 0
	}
}

func (o Overscroll) computeAccumulatedParts(now int) int {
	progress := 0.0
	if o.Returning && o.Animating(now) {
		progress = float64(now-o.ReturnStart) / float64(tokens.RubberBandMaxReturnMs)
	}
	return qRound((1 - progress) * float64(o.Accumulated))
}

func (o *Overscroll) applyAccumulatedScroll(from, max, now int) int {
	o.checkReturnFinish(now)
	relative := o.computeAccumulatedParts(now)
	return o.applyOverscroll(OverscrollFromAccumulated(relative), from, max)
}

func (o *Overscroll) springStart(side, now int) {
	o.SpringSide = side
	o.SpringX0 = float64(o.Stretch)
	if o.VelocityTime != 0 && now-o.VelocityTime <= tokens.VelocityZeroingMs {
		o.SpringV0 = o.Velocity
	} else {
		o.SpringV0 = 0
	}
	reference := o.SpringX0
	if reference == 0 {
		reference = float64(side)
	}
	push := o.SpringV0 * tokens.RubberBandAmplitude
	decay := tokens.RubberBandStiffness / tokens.RubberBandPeriod
	o.SpringPeak = 0
	if push != 0 && (push > 0) == (reference > 0) {
		peak := 1/decay - o.SpringX0/push
		if peak > 0 {
			o.SpringPeak = peak
		}
	}
	o.ReturnStart = now
}

func (o *Overscroll) springFinish(from, max int) int {
	o.ReturnStart = 0
	o.Returning = false
	o.SpringSide = 0
	o.Accumulated = 0
	return o.applyOverscroll(0, from, max)
}

func (o *Overscroll) SpringUpdate(from, max, now int) int {
	progress := float64(now-o.ReturnStart) / float64(tokens.RubberBandMaxReturnMs)
	if progress < 0 {
		progress = 0
	} else if progress > 1 {
		progress = 1
	}
	time := progress * float64(tokens.RubberBandMaxReturnMs) / 1000
	decay := tokens.RubberBandStiffness / tokens.RubberBandPeriod
	value := (o.SpringX0 + o.SpringV0*tokens.RubberBandAmplitude*time) * math.Exp(-decay*time)
	rounded := qRound(value)
	reference := o.SpringX0
	if reference == 0 {
		reference = float64(o.SpringSide)
	}
	var crossed bool
	if value == 0 {
		crossed = o.SpringX0 != 0
	} else {
		crossed = (value > 0) != (reference > 0)
	}
	if !o.Returning || o.SpringSide == 0 || crossed || !o.Animating(now) ||
		(rounded == 0 && time >= o.SpringPeak) {
		return o.springFinish(from, max)
	}
	return o.applyOverscroll(rounded, from, max)
}

func (o *Overscroll) Return(now int) {
	o.Returning = true
	o.IgnoreMomentum = o.Stretch
	if o.Stretch == 0 {
		o.ReturnStart = 0
		o.Returning = false
		o.Accumulated = 0
		o.SpringSide = 0
		return
	}
	if o.Animating(now) {
		return
	}
	side := 1
	if o.Stretch < 0 {
		side = -1
	}
	o.springStart(side, now)
}

func (o *Overscroll) ReturnCancel() {
	if !o.Returning {
		return
	}
	o.ReturnStart = 0
	o.Returning = false
	o.SpringSide = 0
	o.Accumulated = OverscrollToAccumulated(o.Stretch)
}

func (o *Overscroll) ApplyInput(from, max, delta int, phase Phase, touch bool, now, eventTime int) int {
	o.TrackVelocity(phase, delta, eventTime, now)
	momentum := phase == PhaseMomentum || phase == PhaseEnd
	if o.IgnoreMomentum != 0 {
		if !momentum {
			o.IgnoreMomentum = 0
		} else if o.SpringSide != 0 {
			if !oppositeSigns(o.SpringSide, delta) {
				return from
			}
			o.IgnoreMomentum = 0
			o.ReturnCancel()
		} else if !o.Animating(now) && !oppositeSigns(o.IgnoreMomentum, delta) {
			return from
		}
	}
	if !momentum {
		o.ReturnCancel()
	}
	if delta != 0 && o.Stretch != 0 && !o.Animating(now) && o.springSideOf(o.Stretch) {
		if oppositeSigns(o.Stretch, delta) {
			var unwound int
			if o.Stretch < 0 {
				unwound = minInt(o.Stretch+delta, 0)
			} else {
				unwound = maxInt(o.Stretch+delta, 0)
			}
			delta -= unwound - o.Stretch
			o.Accumulated = OverscrollToAccumulated(unwound)
			from = o.applyOverscroll(unwound, from, max)
		}
	}
	if momentum {
		returning := o.Stretch != 0 && !o.Animating(now)
		if returning && phase == PhaseMomentum && o.collapsing() {
			returning = false
		}
		if returning {
			o.Return(now)
		}
	}
	if o.Stretch == 0 {
		normalTo := WillScrollTo(from, from+delta, max)
		delta -= normalTo - from
		from = normalTo
	}
	if delta == 0 {
		return from
	}
	if touch {
		delta *= tokens.TouchOverscrollMultiplier
	}
	if o.Accumulated == 0 && o.springSideOf(delta) {
		if oppositeSigns(o.Pending, delta) {
			o.Pending = 0
		}
		o.Pending += delta
		if absInt(o.Pending) < tokens.MinimumOverscrollBeforeStretch {
			return from
		}
		delta = o.Pending
		o.Pending = 0
	} else {
		o.Pending = 0
	}
	accumulated := o.Accumulated + delta
	if oppositeSigns(o.Accumulated, accumulated) {
		o.Accumulated = 0
	} else {
		o.Accumulated = accumulated
	}
	from = o.applyAccumulatedScroll(from, max, now)
	if momentum && !o.Animating(now) && o.Stretch != 0 && o.springSideOf(o.Stretch) && !o.collapsing() {
		o.Return(now)
	}
	return from
}
