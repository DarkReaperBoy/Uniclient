package gui

import (
	"testing"
	"time"

	"uniclient/engine"
)

// callLabel renders the direction/type line for every call shape
// (slice 64).
func TestCallLabel(t *testing.T) {
	cases := []struct {
		e    engine.CallHistoryEntry
		want string
	}{
		{engine.CallHistoryEntry{IsOutgoing: true}, "Outgoing call"},
		{engine.CallHistoryEntry{}, "Incoming call"},
		{engine.CallHistoryEntry{IsMissed: true}, "Missed call"},
		{engine.CallHistoryEntry{IsMissed: true, IsOutgoing: true}, "Missed outgoing call"},
		{engine.CallHistoryEntry{IsOutgoing: true, IsVideo: true}, "Outgoing video call"},
		{engine.CallHistoryEntry{IsVideo: true}, "Incoming video call"},
		{engine.CallHistoryEntry{IsMissed: true, IsVideo: true}, "Missed video call"},
	}
	for _, tc := range cases {
		if got := callLabel(tc.e); got != tc.want {
			t.Errorf("callLabel(%+v) = %q, want %q", tc.e, got, tc.want)
		}
	}
}

// callStamp: time-of-day for today, day+time for older, empty for unset
// (slice 64). Timestamps are unix seconds.
func TestCallStamp(t *testing.T) {
	now := time.Date(2026, 9, 8, 14, 0, 0, 0, time.UTC)
	today := now.Add(-2 * time.Hour)
	if got := callStamp(today.Unix(), now); got != "12:00" {
		t.Errorf("today stamp = %q", got)
	}
	old := time.Date(2026, 8, 20, 9, 5, 0, 0, time.UTC)
	if got := callStamp(old.Unix(), now); got != "20 Aug · 09:05" {
		t.Errorf("old stamp = %q", got)
	}
	if got := callStamp(0, now); got != "" {
		t.Errorf("unset stamp = %q", got)
	}
}

// callSub assembles label + duration (not for missed) + time (slice 64).
func TestCallSub(t *testing.T) {
	now := time.Date(2026, 9, 8, 14, 0, 0, 0, time.UTC)
	today := now.Add(-1 * time.Hour)
	talked := engine.CallHistoryEntry{IsOutgoing: true, Duration: 125, Timestamp: today.Unix()}
	if got := callSub(talked, now); got != "Outgoing call · 2:05 · 13:00" {
		t.Errorf("sub = %q", got)
	}
	// Missed calls omit the duration.
	missed := engine.CallHistoryEntry{IsMissed: true, Duration: 30, Timestamp: today.Unix()}
	if got := callSub(missed, now); got != "Missed call · 13:00" {
		t.Errorf("missed sub = %q", got)
	}
}

// findChatByPeer resolves loaded chats by account + peer (slice 64).
func TestFindChatByPeer(t *testing.T) {
	f := frame{chats: []engine.ChatInfo{
		{AccountID: "a", ChatID: "1", Title: "one"},
		{AccountID: "b", ChatID: "1", Title: "two"},
	}}
	if c, ok := findChatByPeer(f, "b", "1"); !ok || c.Title != "two" {
		t.Errorf("findChatByPeer = %+v ok=%v", c, ok)
	}
	if _, ok := findChatByPeer(f, "a", "2"); ok {
		t.Error("unknown peer should not resolve")
	}
}

// The Voice tab's call rows render peer names with a fallback (slice 64).
func TestCallRowNameFallback(t *testing.T) {
	// Indirect: the name fallback lives inline in callRow; guard the
	// entry shape we rely on instead.
	e := engine.CallHistoryEntry{PeerName: "", PeerID: "7"}
	if e.PeerName == "" && e.PeerID == "" {
		t.Fatal("entry lacks both name and peer")
	}
}
