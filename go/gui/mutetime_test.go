package gui

import (
	"testing"
	"time"

	"uniclient/engine"
)

// TestMuteRemainingLabel: tdesktop-style compact remaining-time labels
// (single unit, floor, minimum 1 minute).
func TestMuteRemainingLabel(t *testing.T) {
	cases := []struct {
		remain time.Duration
		want   string
	}{
		{30 * time.Second, "1m"},
		{90 * time.Second, "1m"},
		{5 * time.Minute, "5m"},
		{59 * time.Minute, "59m"},
		{60 * time.Minute, "1h"},
		{90 * time.Minute, "1h"},
		{23 * time.Hour, "23h"},
		{24 * time.Hour, "1d"},
		{3*24*time.Hour + 5*time.Hour, "3d"},
		{-time.Minute, "1m"}, // expired reads as the honest floor
	}
	for _, c := range cases {
		if got := muteRemainingLabel(c.remain); got != c.want {
			t.Errorf("muteRemainingLabel(%v) = %q, want %q", c.remain, got, c.want)
		}
	}
}

// TestFormatMutedUntil: the profile row's "Muted until …" timestamp.
func TestFormatMutedUntil(t *testing.T) {
	now := time.Date(2026, 9, 11, 10, 0, 0, 0, time.Local)
	sameDay := now.Add(4 * time.Hour) // 14:00 today
	otherDay := now.AddDate(0, 0, 1)  // tomorrow
	otherYear := now.AddDate(1, 0, 0) // next year

	if got := formatMutedUntil(sameDay.Unix(), now.Unix()); got != sameDay.Format("15:04") {
		t.Errorf("same-day = %q, want %q", got, sameDay.Format("15:04"))
	}
	if got := formatMutedUntil(otherDay.Unix(), now.Unix()); got != otherDay.Format("Jan 2, 15:04") {
		t.Errorf("other-day = %q, want %q", got, otherDay.Format("Jan 2, 15:04"))
	}
	if got := formatMutedUntil(otherYear.Unix(), now.Unix()); got != otherYear.Format("Jan 2, 2006") {
		t.Errorf("other-year = %q, want %q", got, otherYear.Format("Jan 2, 2006"))
	}
}

// TestTrailingRowBadgesMuteTime: a timed mute adds a remaining-time badge
// ahead of mentions/reactions/count; forever mutes do not.
func TestTrailingRowBadgesMuteTime(t *testing.T) {
	timed := engine.ChatInfo{
		IsMuted:     true,
		MuteUntil:   time.Now().Add(time.Hour).Unix(),
		UnreadCount: 3,
	}
	kinds := trailingRowBadges(timed)
	if len(kinds) == 0 || kinds[0] != rowBadgeMuteTime {
		t.Fatalf("timed mute kinds = %v, want [muteTime ...]", kinds)
	}
	if len(kinds) != 2 || kinds[1] != rowBadgeCount {
		t.Fatalf("timed mute kinds = %v, want [muteTime count]", kinds)
	}

	forever := engine.ChatInfo{IsMuted: true, UnreadCount: 3}
	kinds = trailingRowBadges(forever)
	for _, k := range kinds {
		if k == rowBadgeMuteTime {
			t.Fatalf("forever mute must not show a time badge: %v", kinds)
		}
	}

	unmuted := engine.ChatInfo{UnreadCount: 3}
	kinds = trailingRowBadges(unmuted)
	for _, k := range kinds {
		if k == rowBadgeMuteTime {
			t.Fatalf("unmuted chat must not show a time badge: %v", kinds)
		}
	}
}

// TestMutedRowHasTimedMute: the sidebar tick-scheduling predicate.
func TestMutedRowHasTimedMute(t *testing.T) {
	if mutedRowHasTimedMute([]engine.ChatInfo{{IsMuted: true, MuteUntil: time.Now().Add(time.Hour).Unix()}}) != true {
		t.Fatal("timed-mute row should be detected")
	}
	if mutedRowHasTimedMute([]engine.ChatInfo{{IsMuted: true}}) {
		t.Fatal("forever mute should not be detected as timed")
	}
	if mutedRowHasTimedMute(nil) {
		t.Fatal("empty list should not be detected as timed")
	}
}
