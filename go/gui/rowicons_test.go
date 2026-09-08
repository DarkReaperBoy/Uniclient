package gui

import (
	"testing"

	"uniclient/engine"
)

// Sidebar row meta + service pill (AyuGram parity slice 29).

func TestRowBadgeKind(t *testing.T) {
	cases := []struct {
		c    engine.ChatInfo
		want string
	}{
		{engine.ChatInfo{}, rowBadgeNone},
		{engine.ChatInfo{UnreadCount: 5}, rowBadgeCount},
		{engine.ChatInfo{UnreadMark: true}, rowBadgeMark},
		{engine.ChatInfo{UnreadMark: true, UnreadCount: 2}, rowBadgeCount},
		{engine.ChatInfo{UnreadCount: 0, UnreadMark: false}, rowBadgeNone},
	}
	for i, tc := range cases {
		if got := rowBadgeKindFor(tc.c); got != tc.want {
			t.Errorf("case %d: rowBadgeKindFor = %q, want %q", i, got, tc.want)
		}
	}
}

func TestServicePillText(t *testing.T) {
	if got := servicePillText(engine.CachedMessage{ContentText: "Alice joined the group"}); got != "Alice joined the group" {
		t.Errorf("pill text = %q", got)
	}
	if got := servicePillText(engine.CachedMessage{}); got != "(service message)" {
		t.Errorf("empty pill text = %q", got)
	}
}

func TestRowIconsRenderable(t *testing.T) {
	// The custom IconVG pin glyph must decode (regression: hand-encoded bytes).
	if iconCustomPin == nil {
		t.Fatal("pin icon is nil")
	}
	if iconAVVolumeOff == nil {
		t.Fatal("volume-off icon is nil")
	}
}
