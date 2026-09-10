package gui

import (
	"testing"

	"uniclient/engine"
)

// Saved Messages (slice 116) — pure decision logic: which accounts get the
// sidebar shortcut, the bookmark-avatar predicate, and the forward-dialog
// candidate build. Engine-side creation/idempotency is pinned in
// engine/savedmessages_test.go.

func TestSavedRowAccounts(t *testing.T) {
	accs := []engine.AccountInfo{
		{ID: "tg", Platform: "telegram", DisplayName: "Alice"},
		{ID: "irc", Platform: "irc"},
		{ID: "tg2", Platform: "telegram", DisplayName: "Bob"},
	}
	caps := map[string]bool{"tg": true, "tg2": true}

	got := savedRowAccounts(accs, caps)
	if len(got) != 2 || got[0] != "tg" || got[1] != "tg2" {
		t.Fatalf("rows = %v, want [tg tg2]", got)
	}

	// No capability anywhere → no rows (honest gating, §1.10).
	if got := savedRowAccounts(accs, nil); len(got) != 0 {
		t.Fatalf("rows = %v, want none", got)
	}

	// Account list order is preserved.
	rev := savedRowAccounts([]engine.AccountInfo{{ID: "b"}, {ID: "a"}}, map[string]bool{"a": true, "b": true})
	if len(rev) != 2 || rev[0] != "b" || rev[1] != "a" {
		t.Fatalf("order not preserved: %v", rev)
	}
}

func TestIsSavedMessagesChat(t *testing.T) {
	saved := map[string]string{"tg": "42"}
	if !isSavedMessagesChat("tg", "42", saved) {
		t.Fatal("the self chat must be recognized")
	}
	if isSavedMessagesChat("tg", "43", saved) {
		t.Fatal("another chat must not be recognized")
	}
	if isSavedMessagesChat("irc", "42", saved) {
		t.Fatal("a chat id from another account must not match")
	}
	if isSavedMessagesChat("tg", "42", nil) {
		t.Fatal("no capability map → no match")
	}
}

func TestBuildForwardCandidates(t *testing.T) {
	src := engine.CachedMessage{AccountID: "tg", ChatID: "10"}
	chats := []engine.ChatInfo{
		{AccountID: "tg", ChatID: "10", Title: "Source"},
		{AccountID: "tg", ChatID: "20", Title: "Other"},
		{AccountID: "irc", ChatID: "30", Title: "Elsewhere"},
	}

	// Without a saved chat: same-account chats, source excluded.
	got := buildForwardCandidates(chats, src, "")
	if len(got) != 1 || got[0].ChatID != "20" {
		t.Fatalf("candidates = %v", got)
	}

	// With a saved chat: it is pinned FIRST, rest keep their order.
	got = buildForwardCandidates(chats, src, "42")
	if len(got) != 2 {
		t.Fatalf("candidates = %v, want 2", got)
	}
	if got[0].ChatID != "42" || got[0].Title != "Saved Messages" {
		t.Fatalf("pinned first = %+v", got[0])
	}
	if got[1].ChatID != "20" {
		t.Fatalf("second = %+v", got[1])
	}

	// The saved chat already in the list must not duplicate.
	withSaved := append([]engine.ChatInfo{{AccountID: "tg", ChatID: "42", Title: "Saved Messages"}}, chats...)
	got = buildForwardCandidates(withSaved, src, "42")
	if len(got) != 2 {
		t.Fatalf("duplicated saved chat: %v", got)
	}
}

func TestSavedRowSubtitle(t *testing.T) {
	accs := []engine.AccountInfo{
		{ID: "tg", DisplayName: "Alice"},
		{ID: "tg2", DisplayName: "Bob"},
	}
	if s := savedRowSubtitle("tg", accs, 2); s != "Alice" {
		t.Fatalf("multi-account subtitle = %q, want Alice", s)
	}
	if s := savedRowSubtitle("tg", accs, 1); s != "" {
		t.Fatalf("single-account subtitle = %q, want empty", s)
	}
	// Accounts without a display name fall back to the id.
	anon := []engine.AccountInfo{{ID: "x"}, {ID: "y"}}
	if s := savedRowSubtitle("x", anon, 2); s != "x" {
		t.Fatalf("anon subtitle = %q, want x", s)
	}
}
