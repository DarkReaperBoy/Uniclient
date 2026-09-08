package gui

import (
	"testing"
	"time"

	"uniclient/engine"
)

func TestSchedulePresetWhen(t *testing.T) {
	now := time.Date(2026, 9, 8, 10, 0, 0, 0, time.UTC)
	if p, ok := schedulePresetWhen(1, now); !ok || p.Sub(now) != 2*time.Hour {
		t.Errorf("preset 1 = %v ok=%v, want +2h", p, ok)
	}
	p, ok := schedulePresetWhen(2, now)
	if !ok {
		t.Fatal("preset 2 should exist")
	}
	// 9:00 already passed today (now is 10:00) → tomorrow 9:00.
	if p.Sub(now) != 23*time.Hour {
		t.Errorf("preset 2 = %v, want +23h", p.Sub(now))
	}
	if _, ok := schedulePresetWhen(0, now); ok {
		t.Fatal("preset 0 (custom) has no preset time")
	}
}

func TestParseScheduleInput(t *testing.T) {
	secs, ok := parseScheduleInput("2026-09-09", "09:30")
	if !ok {
		t.Fatal("valid input should parse")
	}
	want := time.Date(2026, 9, 9, 9, 30, 0, 0, time.Local).Unix()
	if secs != want {
		t.Errorf("secs = %d, want %d", secs, want)
	}
	if _, ok := parseScheduleInput("09/09/2026", "09:30"); ok {
		t.Fatal("wrong date format should fail")
	}
	// Lenient single-digit hour is accepted (09:30).
	if secs, ok := parseScheduleInput("2026-09-09", "9:30"); !ok || secs != want {
		t.Fatalf("lenient time = %d ok=%v, want %d", secs, ok, want)
	}
	if _, ok := parseScheduleInput("", ""); ok {
		t.Fatal("empty input should fail")
	}
}

func TestDraftPreview(t *testing.T) {
	if got := draftPreview("hello"); got != "Draft: hello" {
		t.Errorf("draftPreview = %q", got)
	}
	long := string(make([]rune, 100))
	got := draftPreview(long)
	if len([]rune(got)) != 48+7 { // "Draft: " + 48 runes
		t.Errorf("clamped length = %d", len([]rune(got)))
	}
}

func TestScheduledMetaLabel(t *testing.T) {
	if got := scheduledMetaLabel(engine.CachedMessage{}); got != "" {
		t.Errorf("no schedule date: %q", got)
	}
	m := engine.CachedMessage{ScheduleDate: 1780000000}
	got := scheduledMetaLabel(m)
	if len(got) == 0 || got[:10] != "scheduled " {
		t.Fatalf("label = %q", got)
	}
}

func TestScheduledMetaLabelWhenOnline(t *testing.T) {
	m := engine.CachedMessage{ScheduleDate: 0x7FFFFFFF}
	if got := scheduledMetaLabel(m); got != "scheduled · when online" {
		t.Errorf("when-online label = %q", got)
	}
	m2 := engine.CachedMessage{ScheduleDate: 0}
	if got := scheduledMetaLabel(m2); got != "" {
		t.Errorf("no schedule label = %q", got)
	}
	m3 := engine.CachedMessage{ScheduleDate: 1759000000}
	if got := scheduledMetaLabel(m3); got != "scheduled "+time.Unix(1759000000, 0).Format("Mon 15:04") {
		t.Errorf("normal label = %q", got)
	}
}
