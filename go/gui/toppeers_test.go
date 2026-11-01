package gui

import (
	"testing"

	"uniclient/engine"
)

func topPeersTestFrame() frame {
	return frame{
		accounts: []engine.AccountInfo{
			{ID: "a", Platform: "telegram", DisplayName: "A"},
			{ID: "b", Platform: "irc", DisplayName: "B"},
		},
	}
}

func TestTopPeersScopeUnsetWithMultipleAccounts(t *testing.T) {
	if _, ok := topPeersScope(topPeersTestFrame()); ok {
		t.Fatal("unfiltered multi-account list: no unambiguous scope, strip must not render")
	}
}

func TestTopPeersScopeAccountFilter(t *testing.T) {
	f := topPeersTestFrame()
	f.acctFilter = "b"
	acc, ok := topPeersScope(f)
	if !ok || acc != "b" {
		t.Fatalf("account filter picks its own top peers, got %q ok=%v", acc, ok)
	}
}

func TestTopPeersScopeSingleAccount(t *testing.T) {
	f := topPeersTestFrame()
	f.accounts = f.accounts[:1]
	acc, ok := topPeersScope(f)
	if !ok || acc != "a" {
		t.Fatalf("single account is its own scope, got %q ok=%v", acc, ok)
	}
}

func TestTopPeersScopeNoAccounts(t *testing.T) {
	if _, ok := topPeersScope(frame{}); ok {
		t.Fatal("no accounts: no scope")
	}
}

func TestTopPeersFilterUnread(t *testing.T) {
	peers := []engine.ChatInfo{
		{ChatID: "1", Title: "Alice"},
		{ChatID: "", Title: ""},
		{ChatID: "3", Title: "Carol"},
	}
	got := topPeersRows(peers)
	if len(got) != 2 || got[0].ChatID != "1" || got[1].ChatID != "3" {
		t.Fatalf("rows = %+v", got)
	}
}
