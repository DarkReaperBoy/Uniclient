package gui

import (
	"testing"
	"time"

	"uniclient/engine"
)

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

func TestCallStamp(t *testing.T) {
	now := time.Date(2026, 9, 8, 14, 0, 0, 0, time.Local)
	today := now.Add(-2 * time.Hour)
	if got := callStamp(today.Unix(), now); got != "12:00" {
		t.Errorf("today stamp = %q", got)
	}
	old := time.Date(2026, 8, 20, 9, 5, 0, 0, time.Local)
	if got := callStamp(old.Unix(), now); got != "20 Aug · 09:05" {
		t.Errorf("old stamp = %q", got)
	}
	if got := callStamp(0, now); got != "" {
		t.Errorf("unset stamp = %q", got)
	}
}

func TestCallSub(t *testing.T) {
	now := time.Date(2026, 9, 8, 14, 0, 0, 0, time.Local)
	today := now.Add(-1 * time.Hour)
	talked := engine.CallHistoryEntry{IsOutgoing: true, Duration: 125, Timestamp: today.Unix()}
	if got := callSub(talked, now); got != "Outgoing call · 2:05 · 13:00" {
		t.Errorf("sub = %q", got)
	}
	missed := engine.CallHistoryEntry{IsMissed: true, Duration: 30, Timestamp: today.Unix()}
	if got := callSub(missed, now); got != "Missed call · 13:00" {
		t.Errorf("missed sub = %q", got)
	}
}

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

func TestCallRowNameFallback(t *testing.T) {
	e := engine.CallHistoryEntry{PeerName: "", PeerID: "7"}
	if e.PeerName == "" && e.PeerID == "" {
		t.Fatal("entry lacks both name and peer")
	}
}
