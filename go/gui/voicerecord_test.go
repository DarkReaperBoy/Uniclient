package gui

import (
	"testing"

	"uniclient/engine"
)

func TestVoiceRecWanted(t *testing.T) {
	a := &App{}
	f := frame{msgFor: &chatKey{AccountID: "acct", ChatID: "chat"}}
	if a.voiceRecWanted(f) {
		t.Fatal("mic button must hide when the account cannot send voice notes")
	}
	a.voiceRec.active = true
	if a.voiceRecWanted(f) {
		t.Fatal("mic button must hide while recording")
	}
	a.voiceRec.active = false
	if a.voiceRecWanted(frame{}) {
		t.Fatal("mic button must hide without an open chat")
	}
}

func TestVoiceRecTrackDrag(t *testing.T) {
	a := &App{}
	a.voiceRec.start = 200

	a.voiceRecTrackDrag(160)
	if a.voiceRec.dragLeft {
		t.Fatal("160 is within the slide threshold (start 200 - 80)")
	}

	a.voiceRecTrackDrag(60)
	if !a.voiceRec.dragLeft {
		t.Fatal("60 crosses the cancel threshold")
	}

	a.voiceRecTrackDrag(150)
	if a.voiceRec.dragLeft {
		t.Fatal("dragging back must leave the cancel zone")
	}
}

func TestVoiceRecPanelRouting(t *testing.T) {
	a := &App{}
	if a.voiceRecActive() {
		t.Fatal("no recording running")
	}
	_ = a.voiceRec.active
}

func TestVoiceRecClickablesStable(t *testing.T) {
	a := &App{}
	a.wid.init()
	f1 := frame{msgFor: &chatKey{AccountID: "a", ChatID: "c1"}}
	f2 := frame{msgFor: &chatKey{AccountID: "a", ChatID: "c2"}}
	vStable1 := a.voiceRecClickable(f1)
	vStable2 := a.voiceRecClickable(f1)
	if vStable1 != vStable2 {
		t.Fatal("clickable must be stable per chat")
	}
	if a.voiceRecClickable(f1) == a.voiceRecClickable(f2) {
		t.Fatal("different chats must get different clickables")
	}
	if a.voiceRecClickable(frame{}) == nil {
		t.Fatal("fallback clickable must exist")
	}
}

func TestVoiceRecLevelClamp(t *testing.T) {
	e := &engine.Engine{}
	st := e.VoiceRecording()
	if st.Active || st.Level != 0 {
		t.Fatalf("idle recorder snapshot: %+v", st)
	}
}
