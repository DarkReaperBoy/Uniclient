package cores

import "testing"

// TestDetectVoiceActivityRMS activates the exported VAD helper
// (deadcode: unreachable even with tests — voice activation was never
// wired, but the pure RMS gate is worth pinning before anyone wires
// it). Contract: empty → false, silence → false, above-threshold
// loudness → true, exact-boundary → false (strict >).
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
	// rms == threshold exactly: strict greater-than → false.
	edge := []int16{100, -100} // rms = 100
	if DetectVoiceActivity(edge, 100) {
		t.Error("rms == threshold must be false (strict >)")
	}
	// Single burst: RMS = sqrt(3000²/480) ≈ 136.9 (RMS, NOT the mean —
	// my first pin used mean-math and was wrong; the impl is right).
	// Below a 200 threshold a lone click must not open the gate.
	mixed := make([]int16, 480)
	mixed[0] = 3000
	if DetectVoiceActivity(mixed, 200) {
		t.Error("single burst (rms ≈ 136.9) must be false at threshold 200")
	}
}
