package tests

import (
	"testing"
	. "uniclient/cores"
)

func TestDetectVoiceActivityRMS(t *testing.T) {
	if DetectVoiceActivity(nil, 50) {
		t.Error("empty frame must not register as voice")
	}
	silence := make([]int16, 480)
	if DetectVoiceActivity(silence, 50) {
		t.Error("digital silence must not register as voice")
	}
	loud := make([]int16, 480)
	for i := range loud {
		loud[i] = 1000
	}
	if !DetectVoiceActivity(loud, 50) {
		t.Error("loud frame (rms 1000) must register as voice")
	}
	edge := []int16{100, -100}
	if DetectVoiceActivity(edge, 100) {
		t.Error("rms == threshold must be false (strict >)")
	}
	mixed := make([]int16, 480)
	mixed[0] = 3000
	if DetectVoiceActivity(mixed, 200) {
		t.Error("single burst (rms ≈ 136.9) must be false at threshold 200")
	}
}
