package gui

import (
	"testing"
	"time"

	"uniclient/engine"
)

// mkCall builds a CallHistoryEntry with the fields the calls box groups on.
func mkCall(msgID string, peer string, ts int64, out, missed, video bool) engine.CallHistoryEntry {
	return engine.CallHistoryEntry{
		MsgID:      msgID,
		PeerID:     peer,
		PeerName:   "User " + peer,
		Timestamp:  ts,
		IsOutgoing: out,
		IsMissed:   missed,
		IsVideo:    video,
	}
}

func TestGroupCallEntriesMergesSamePeerDayDir(t *testing.T) {
	// Three incoming calls from the same peer on the same day merge into
	// one row (tdesktop Row::canAddItem: same type + history + date).
	day := time.Date(2026, 9, 10, 0, 0, 0, 0, time.UTC)
	ts := func(h int64) int64 { return day.Add(time.Duration(h) * time.Hour).Unix() }
	entries := []engine.CallHistoryEntry{
		mkCall("30", "7", ts(15), false, false, false),
		mkCall("29", "7", ts(12), false, false, false),
		mkCall("28", "7", ts(9), false, false, false),
	}
	rows := groupCallEntries(entries)
	if len(rows) != 1 {
		t.Fatalf("rows = %d, want 1 (same peer+day+dir merges)", len(rows))
	}
	r := rows[0]
	if r.Count != 3 || len(r.MsgIDs) != 3 {
		t.Fatalf("count = %d, msgIDs = %d, want 3/3", r.Count, len(r.MsgIDs))
	}
	if r.Last.MsgID != "30" {
		t.Fatalf("last msg = %q, want 30 (newest of the group)", r.Last.MsgID)
	}
	if r.Dir != callDirIn {
		t.Fatalf("dir = %d, want callDirIn", r.Dir)
	}
}

func TestGroupCallEntriesSeparatesDirAndDay(t *testing.T) {
	day := time.Date(2026, 9, 10, 0, 0, 0, 0, time.UTC)
	next := day.AddDate(0, 0, 1)
	entries := []engine.CallHistoryEntry{
		mkCall("40", "7", next.Add(3*time.Hour).Unix(), false, false, false), // in, day 2
		mkCall("30", "7", day.Add(15*time.Hour).Unix(), false, false, false), // in, day 1
		mkCall("29", "7", day.Add(12*time.Hour).Unix(), true, false, false),  // out, day 1
		mkCall("28", "7", day.Add(9*time.Hour).Unix(), false, true, false),   // missed, day 1
		mkCall("27", "8", day.Add(9*time.Hour).Unix(), false, false, false),  // other peer
	}
	rows := groupCallEntries(entries)
	if len(rows) != 5 {
		t.Fatalf("rows = %d, want 5 (day, direction, and peer each split)", len(rows))
	}
	// Newest-first ordering by message id.
	if rows[0].Last.MsgID != "40" || rows[1].Last.MsgID != "30" || rows[4].Last.MsgID != "27" {
		t.Fatalf("order = %s,%s,...,%s, want 40,30,...,27 (newest first)",
			rows[0].Last.MsgID, rows[1].Last.MsgID, rows[4].Last.MsgID)
	}
	if rows[1].Dir != callDirIn || rows[2].Dir != callDirOut || rows[3].Dir != callDirMissed {
		t.Fatalf("dirs = %d,%d,%d, want in,out,missed", rows[1].Dir, rows[2].Dir, rows[3].Dir)
	}
}

func TestGroupCallEntriesEmpty(t *testing.T) {
	if rows := groupCallEntries(nil); len(rows) != 0 {
		t.Fatalf("rows = %d, want 0", len(rows))
	}
}

func TestCallBoxStatusPhrases(t *testing.T) {
	now := time.Date(2026, 9, 12, 18, 0, 0, 0, time.UTC)
	today := now.Add(-2 * time.Hour)
	yesterday := now.AddDate(0, 0, -1)
	older := time.Date(2026, 8, 21, 15, 4, 0, 0, time.UTC)

	single := callBoxRow{Last: engine.CallHistoryEntry{Timestamp: today.Unix()}}
	if got, want := callBoxStatus(single, now), "Today at 16:00"; got != want {
		t.Errorf("today: = %q, want %q", got, want)
	}
	single.Last.Timestamp = yesterday.Unix()
	if got, want := callBoxStatus(single, now), "Yesterday at 18:00"; got != want {
		t.Errorf("yesterday: = %q, want %q", got, want)
	}
	single.Last.Timestamp = older.Unix()
	if got, want := callBoxStatus(single, now), "21 Aug at 15:04"; got != want {
		t.Errorf("older: = %q, want %q", got, want)
	}

	grouped := callBoxRow{Count: 3, Last: engine.CallHistoryEntry{Timestamp: today.Unix()}}
	if got, want := callBoxStatus(grouped, now), "3 calls, last today at 16:00"; got != want {
		t.Errorf("grouped today: = %q, want %q", got, want)
	}
	grouped.Last.Timestamp = older.Unix()
	if got, want := callBoxStatus(grouped, now), "3 calls, last 21 Aug at 15:04"; got != want {
		t.Errorf("grouped older: = %q, want %q", got, want)
	}
}

func TestCallsBoxNextOffset(t *testing.T) {
	rows := []callBoxRow{
		{MsgIDs: []string{"120", "119"}},
		{MsgIDs: []string{"98"}},
		{MsgIDs: []string{"45", "44", "43"}},
	}
	if got := callsBoxNextOffset(rows); got != 43 {
		t.Fatalf("nextOffset = %d, want 43 (oldest id)", got)
	}
	if got := callsBoxNextOffset(nil); got != 0 {
		t.Fatalf("empty nextOffset = %d, want 0", got)
	}
}

func TestCallsBoxMenuItems(t *testing.T) {
	items := callsBoxMenuItems(0)
	if len(items) != 1 || items[0] != "Call settings" {
		t.Fatalf("empty rows: items = %v, want [Call settings]", items)
	}
	items = callsBoxMenuItems(5)
	if len(items) != 2 || items[0] != "Call settings" || items[1] != "Clear all" {
		t.Fatalf("rows: items = %v, want [Call settings Clear all]", items)
	}
}

func TestContentPaneDialogSurfaceCallsBox(t *testing.T) {
	// Solo wins.
	if got := contentDialogSurface(frame{callsBoxOpen: true}); got != "callsBox" {
		t.Fatalf("solo callsBox: = %q, want callsBox", got)
	}
	// A full-pane dialog (newChat) beats the page, same as contacts.
	if got := contentDialogSurface(frame{callsBoxOpen: true, newDlg: &newChatDlg{}}); got != "newChat" {
		t.Fatalf("newChat + callsBox: = %q, want newChat", got)
	}
	// The page beats the settings pane (drawer gear beneath it).
	if got := contentDialogSurface(frame{callsBoxOpen: true, settingsOpen: true}); got != "callsBox" {
		t.Fatalf("settings + callsBox: = %q, want callsBox", got)
	}
	// Same chain position as the contacts page (both are drawer pages):
	// contacts first, calls box next.
	if got := contentDialogSurface(frame{callsBoxOpen: true, contactsOpen: true}); got != "contacts" {
		t.Fatalf("contacts + callsBox: = %q, want contacts (page order)", got)
	}
}

func TestEscTargetCallsBoxSelfHandled(t *testing.T) {
	// The calls box consumes Esc in its own layout (like contacts).
	f := frame{callsBoxOpen: true, menu: &menuTarget{}}
	if got := escTarget(f); got != "" {
		t.Errorf("callsBox + menu: escTarget = %q, want empty (box consumes Esc)", got)
	}
}

func TestCallDirOf(t *testing.T) {
	if d := callDirOf(mkCall("1", "7", 1, true, false, false)); d != callDirOut {
		t.Errorf("outgoing: dir = %d, want out", d)
	}
	if d := callDirOf(mkCall("1", "7", 1, false, true, false)); d != callDirMissed {
		t.Errorf("missed incoming: dir = %d, want missed", d)
	}
	if d := callDirOf(mkCall("1", "7", 1, false, false, false)); d != callDirIn {
		t.Errorf("incoming: dir = %d, want in", d)
	}
}
