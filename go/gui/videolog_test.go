package gui

import (
	"testing"
	"time"
)

func TestLoopLogAllowed(t *testing.T) {
	var last time.Time
	base := time.Date(2026, 9, 25, 12, 0, 0, 0, time.UTC)
	gap := 10 * time.Second

	if !loopLogAllowed(&last, base, gap) {
		t.Error("first emission must be allowed (zero last)")
	}
	if loopLogAllowed(&last, base.Add(gap-1), gap) {
		t.Error("inside the gap must be suppressed")
	}
	if last != base {
		t.Errorf("suppressed checks must not move the timestamp, last = %v", last)
	}
	if !loopLogAllowed(&last, base.Add(gap), gap) {
		t.Error("at the gap boundary must be allowed")
	}
	if loopLogAllowed(&last, base.Add(gap+time.Nanosecond), gap) {
		t.Error("immediately after an allowed emission must be suppressed again")
	}
}
