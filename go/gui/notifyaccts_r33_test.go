package gui

import "testing"

func TestNotifyAcctSenderNameSurvives(t *testing.T) {
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

	st2 := notifyAcctState{senderName: true}
	st2.applyReactionsMap(map[string]interface{}{
		"reactions_enabled": true,
		"reactions_from":    "everyone",
	})
	if !st2.senderName {
		t.Fatal("silent show_sender_name must keep the true default")
	}

	st3 := notifyAcctState{}
	st3.applyReactionsMap(map[string]interface{}{"show_sender_name": true})
	if !st3.senderName {
		t.Fatal("show_sender_name=true must load as senderName=true")
	}

	st4 := notifyAcctState{senderName: true}
	st4.applyReactionsMap(map[string]interface{}{"show_sender_name": "no"})
	if !st4.senderName {
		t.Fatal("junk show_sender_name must leave the default untouched")
	}
}
