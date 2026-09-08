package gui

import (
	"testing"
	"time"

	"uniclient/engine"
)

func TestSchedRowText(t *testing.T) {
	m := engine.CachedMessage{ContentText: "hello there"}
	if got := schedRowText(m); got != "hello there" {
		t.Errorf("text = %q", got)
	}
	m = engine.CachedMessage{ContentText: "", MediaType: 3} // 3 = voice-ish; label from engine
	if got := schedRowText(m); got == "(no text)" && engine.MediaPreviewLabel(3) != "" {
		t.Errorf("media fallback should use MediaPreviewLabel")
	}
	m = engine.CachedMessage{}
	if got := schedRowText(m); got != "(no text)" {
		t.Errorf("empty = %q", got)
	}
	m = engine.CachedMessage{ContentText: string(make([]rune, 200))}
	got := schedRowText(m)
	if n := len([]rune(got)); n > 72+1 {
		t.Errorf("clamped = %d runes", n)
	}
}

func TestSchedRowWhen(t *testing.T) {
	if got := schedRowWhen(engine.CachedMessage{}); got != "unscheduled" {
		t.Errorf("no date = %q", got)
	}
	w := time.Unix(1780000000, 0)
	got := schedRowWhen(engine.CachedMessage{ScheduleDate: 1780000000})
	if got != w.Format("Mon 2 Jan · 15:04") {
		t.Errorf("when = %q, want %q", got, w.Format("Mon 2 Jan · 15:04"))
	}
}

func TestSchedReschedRouting(t *testing.T) {
	// The resched pointer is what routes the dialog to RescheduleMessage.
	m := engine.CachedMessage{AccountID: "a", ChatID: "c", MsgID: "5", ScheduleDate: 1780000000}
	d := &schedDlgState{resched: &m}
	if d.resched == nil || d.resched.MsgID != "5" {
		t.Fatal("resched not retained")
	}
	d2 := &schedDlgState{}
	if d2.resched != nil {
		t.Fatal("plain schedule dialog should have nil resched")
	}
}
