package gui

import (
	"testing"

	"uniclient/engine"
)

// Clear-history confirm dialog (slice 190, tdesktop "Clear history?" box):
// pure helpers — title/hint composition, revoke-offer gating, and the
// engine-clear wiring through the dialog's submit path. Layout is verified
// by compile + review (repo discipline).

func TestClearDialogTitleAndHint(t *testing.T) {
	if got := clearDialogTitle("News"); got != "Clear history?" {
		t.Errorf("clearDialogTitle = %q, want Clear history?", got)
	}
	if got := clearDialogTitle(""); got != "Clear history?" {
		t.Errorf("clearDialogTitle(empty) = %q, want Clear history?", got)
	}
	if got := clearDialogHint(true); got != "This can't be undone." {
		t.Errorf("revoke hint = %q", got)
	}
	if got := clearDialogHint(false); got != "This can't be undone. Messages stay on the other side." {
		t.Errorf("no-revoke hint = %q", got)
	}
}

func TestCanRevokeClearHistory(t *testing.T) {
	// Private chats: clearing with revoke wipes both sides (Telegram
	// deleteHistory semantics) — always offered.
	if !canRevokeClearHistory(engine.ChatInfo{Type: engine.ChatTypeDMVal}) {
		t.Fatal("DM: revoke should be offered")
	}
	// Self chat: same as DM.
	if !canRevokeClearHistory(engine.ChatInfo{Type: engine.ChatTypeDMVal, ChatID: "self"}) {
		t.Fatal("self chat: revoke should be offered")
	}
	// Groups/channels: only admins can clear for everyone.
	if canRevokeClearHistory(engine.ChatInfo{Type: engine.ChatTypeGroupVal}) {
		t.Fatal("plain member group: no revoke")
	}
	if !canRevokeClearHistory(engine.ChatInfo{Type: engine.ChatTypeGroupVal, IsAdmin: true}) {
		t.Fatal("admin group: revoke")
	}
	if !canRevokeClearHistory(engine.ChatInfo{Type: engine.ChatTypeChanVal, IsCreator: true}) {
		t.Fatal("creator channel: revoke")
	}
	// Saved-messages-style zero type falls back to no revoke.
	if canRevokeClearHistory(engine.ChatInfo{}) {
		t.Fatal("unknown zero chat: no revoke")
	}
}
