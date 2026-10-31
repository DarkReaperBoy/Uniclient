package gui

import "testing"

// TestNotifyAcctSenderNameSurvives pins R33: loadNotifyAccts read the
// engine's show_sender_name into a dead `if ... { _ = from }` block and
// applyReactionsNotify hardcoded showSenderName=true — so toggling ANY
// reactions/polls row re-persisted the account with the sender name forced
// back on, silently stomping a setting made in another client (official
// Telegram / tdesktop). The value now loads into notifyAcctState and rides
// the struct through every apply. The engine round-trip itself needs a live
// account (not reachable on the bare harness) — this pins the map→state
// coercion the fix lives in.
func TestNotifyAcctSenderNameSurvives(t *testing.T) {
	// Override present and false: must land in the struct.
	st := notifyAcctState{senderName: true}
	st.applyReactionsMap(map[string]interface{}{
		"reactions_enabled":  false,
		"reactions_from":     "contacts",
		"poll_votes_enabled": true,
		"poll_votes_from":    "everyone",
		"show_sender_name":   false,
	})
	if st.senderName {
		t.Fatal("show_sender_name=false must load as senderName=false")
	}
	if st.reactOn {
		t.Fatal("reactions_enabled=false must load as reactOn=false")
	}
	if st.reactFrom != "contacts" {
		t.Fatalf("reactions_from: want contacts, got %q", st.reactFrom)
	}
	if !st.pollsOn || st.pollsFrom != "everyone" {
		t.Fatalf("polls fields: want true/everyone, got %v/%q", st.pollsOn, st.pollsFrom)
	}

	// Map silent on show_sender_name (the engine only records overrides):
	// the struct default (true) survives — the old dead block also lost
	// nothing here, but the default must keep flowing to the apply side.
	st2 := notifyAcctState{senderName: true}
	st2.applyReactionsMap(map[string]interface{}{
		"reactions_enabled": true,
		"reactions_from":    "everyone",
	})
	if !st2.senderName {
		t.Fatal("silent show_sender_name must keep the true default")
	}

	// Explicit true records too (an override back to on).
	st3 := notifyAcctState{}
	st3.applyReactionsMap(map[string]interface{}{"show_sender_name": true})
	if !st3.senderName {
		t.Fatal("show_sender_name=true must load as senderName=true")
	}

	// Non-bool junk is ignored, not coerced.
	st4 := notifyAcctState{senderName: true}
	st4.applyReactionsMap(map[string]interface{}{"show_sender_name": "no"})
	if !st4.senderName {
		t.Fatal("junk show_sender_name must leave the default untouched")
	}
}
