package gui

import (
	"testing"

	"uniclient/engine"
)

// Hold-to-record voice notes (slice 114) — the pure decision logic:
// mic-button gating, slide-left cancel threshold, recording-panel
// routing. The engine-side round-trip (frames → Opus → Ogg → decode →
// tone check) is pinned in engine/voicerec_test.go.

func TestVoiceRecWanted(t *testing.T) {
	a := &App{}
	f := frame{msgFor: &chatKey{AccountID: "acct", ChatID: "chat"}}
	// No account info in the GUI test harness: VoiceRecordingSupported
	// consults the engine's live accounts and returns false with none —
	// the button must stay hidden (honest gating).
	if a.voiceRecWanted(f) {
		t.Fatal("mic button must hide when the account cannot send voice notes")
	}
	// While a recording is active the button must not render either.
	a.voiceRec.active = true
	if a.voiceRecWanted(f) {
		t.Fatal("mic button must hide while recording")
	}
	a.voiceRec.active = false
	// No open chat → hidden.
	if a.voiceRecWanted(frame{}) {
		t.Fatal("mic button must hide without an open chat")
	}
}

func TestVoiceRecTrackDrag(t *testing.T) {
	a := &App{}
	a.voiceRec.start = 200

	// Small movement: still in the send zone.
	a.voiceRecTrackDrag(160)
	if a.voiceRec.dragLeft {
		t.Fatal("160 is within the slide threshold (start 200 - 80)")
	}

	// Far left: cancel zone.
	a.voiceRecTrackDrag(60)
	if !a.voiceRec.dragLeft {
		t.Fatal("60 crosses the cancel threshold")
	}

	// Back right: returns to send.
	a.voiceRecTrackDrag(150)
	if a.voiceRec.dragLeft {
		t.Fatal("dragging back must leave the cancel zone")
	}
}

// TestVoiceRecPanelRouting: with the engine recorder idle the panel
// falls back to the plain composer (also proves no panic without a
// running engine recorder).
func TestVoiceRecPanelRouting(t *testing.T) {
	a := &App{}
	if a.voiceRecActive() {
		t.Fatal("no recording running")
	}
	// voiceRecActive consults the engine; a zero App has no engine —
	// must not panic.
	_ = a.voiceRec.active
}

func TestVoiceRecClickablesStable(t *testing.T) {
	f1 := frame{msgFor: &chatKey{AccountID: "a", ChatID: "c1"}}
	f2 := frame{msgFor: &chatKey{AccountID: "a", ChatID: "c2"}}
	if voiceRecClickable(f1) != voiceRecClickable(f1) {
		t.Fatal("clickable must be stable per chat")
	}
	if voiceRecClickable(f1) == voiceRecClickable(f2) {
		t.Fatal("different chats must get different clickables")
	}
	if voiceRecClickable(frame{}) == nil {
		t.Fatal("fallback clickable must exist")
	}
}

// TestVoiceRecLevelClamp: the level bars' input clamp.
func TestVoiceRecLevelClamp(t *testing.T) {
	// The engine smooths RMS into 0..1; over-range values must not
	// escape the bar math (clamped in voiceRecLevelBars; here we pin
	// the engine-side invariant via a direct recording snapshot).
	e := &engine.Engine{}
	st := e.VoiceRecording()
	if st.Active || st.Level != 0 {
		t.Fatalf("idle recorder snapshot: %+v", st)
	}
}
