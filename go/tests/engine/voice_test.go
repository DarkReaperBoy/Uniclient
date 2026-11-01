package tests

import (
	"testing"
	. "uniclient/engine"
)

func TestVoiceVADDecision(t *testing.T) {
	var v VoiceVAD
	loud := frameWithRMS(0.10)
	quiet := frameWithRMS(0.0005)

	if !v.ForTestGate(loud) {
		t.Fatal("loud frame must send")
	}
	if !v.ForTestGate(loud) {
		t.Fatal("second loud frame must keep sending")
	}
	if !v.ForTestGate(quiet) {
		t.Fatal("silent frame right after speech must still send (hangover)")
	}
	sent := 1
	for i := 1; i < VoiceHangoverFrames; i++ {
		if v.ForTestGate(quiet) {
			sent++
		}
	}
	if sent != VoiceHangoverFrames {
		t.Fatalf("hangover sent %d frames, want %d", sent, VoiceHangoverFrames)
	}
	if v.ForTestGate(quiet) {
		t.Fatal("frame after hangover must not send")
	}
	if !v.ForTestNeedTerminator() {
		t.Fatal("first silent frame after hangover must arm the terminator")
	}
	if v.ForTestGate(quiet) || v.ForTestNeedTerminator() {
		t.Fatal("prolonged silence must stay inert")
	}
	if !v.ForTestGate(loud) {
		t.Fatal("speech again must resume sending")
	}
	if v.ForTestNeedTerminator() {
		t.Fatal("no terminator while speech is live")
	}
	for i := 0; i < VoiceHangoverFrames+1; i++ {
		v.ForTestGate(quiet)
	}
	if !v.ForTestNeedTerminator() {
		t.Fatal("second drop must re-arm the terminator")
	}
}

func TestVoiceVADColdStart(t *testing.T) {
	var v VoiceVAD
	quiet := frameWithRMS(0.0005)
	for i := 0; i < 10; i++ {
		if v.ForTestGate(quiet) {
			t.Fatalf("silent frame %d sent", i)
		}
	}
	if v.ForTestNeedTerminator() {
		t.Fatal("cold-start silence must not arm a terminator")
	}
}

func frameWithRMS(rms float64) []byte {
	const n = 960
	out := make([]byte, n*2)
	amp := rms * 32768 * 1.414
	for i := 0; i < n; i++ {
		var s int16
		if (i/11)%2 == 0 {
			s = int16(amp)
		} else {
			s = -int16(amp)
		}
		out[2*i] = byte(s)
		out[2*i+1] = byte(s >> 8)
	}
	return out
}
