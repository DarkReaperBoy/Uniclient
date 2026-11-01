package engine

import (
	"testing"
)

func TestVoiceVADDecision(t *testing.T) {
	var v voiceVAD
	loud := frameWithRMS(0.10)
	quiet := frameWithRMS(0.0005)

	if !v.gate(loud) {
		t.Fatal("loud frame must send")
	}
	if !v.gate(loud) {
		t.Fatal("second loud frame must keep sending")
	}
	if !v.gate(quiet) {
		t.Fatal("silent frame right after speech must still send (hangover)")
	}
	sent := 1
	for i := 1; i < voiceHangoverFrames; i++ {
		if v.gate(quiet) {
			sent++
		}
	}
	if sent != voiceHangoverFrames {
		t.Fatalf("hangover sent %d frames, want %d", sent, voiceHangoverFrames)
	}
	if v.gate(quiet) {
		t.Fatal("frame after hangover must not send")
	}
	if !v.needTerminator() {
		t.Fatal("first silent frame after hangover must arm the terminator")
	}
	if v.gate(quiet) || v.needTerminator() {
		t.Fatal("prolonged silence must stay inert")
	}
	if !v.gate(loud) {
		t.Fatal("speech again must resume sending")
	}
	if v.needTerminator() {
		t.Fatal("no terminator while speech is live")
	}
	for i := 0; i < voiceHangoverFrames+1; i++ {
		v.gate(quiet)
	}
	if !v.needTerminator() {
		t.Fatal("second drop must re-arm the terminator")
	}
}

func TestVoiceVADColdStart(t *testing.T) {
	var v voiceVAD
	quiet := frameWithRMS(0.0005)
	for i := 0; i < 10; i++ {
		if v.gate(quiet) {
			t.Fatalf("silent frame %d sent", i)
		}
	}
	if v.needTerminator() {
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
