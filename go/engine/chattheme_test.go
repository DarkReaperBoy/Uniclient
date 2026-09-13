package engine

// Chat-theme mirror (slice 188): the latest messageActionSetChatTheme
// service row flips chats.theme_emoticon; the key's presence (even an
// empty emoticon) is the reset. ChatInfo round-trips it.

import (
	"testing"
	"time"

	"uniclient/cores"
)

func TestChatThemeMirror(t *testing.T) {
	e := newTestEngine(t)
	seedChannelChat(t, e, "c1", ChatTypeDMVal)

	getEmoticon := func() string {
		var em string
		if err := e.db.QueryRow(
			`SELECT theme_emoticon FROM chats WHERE account_id = ? AND chat_id = ?`, "a1", "c1").Scan(&em); err != nil {
			t.Fatal(err)
		}
		return em
	}

	// Ordinary messages never touch the theme.
	e.cacheMessage("a1", "c1", &cores.Message{ID: "m1", ChatID: "c1", Text: "hi", Timestamp: time.Now()})
	if got := getEmoticon(); got != "" {
		t.Fatalf("plain message set theme %q", got)
	}

	// A theme-change service row mirrors its emoticon.
	svc := &cores.Message{
		ID: "m2", ChatID: "c1", IsService: true, Text: "changed the chat theme",
		Timestamp: time.Now().Add(time.Second),
		Extra:     map[string]interface{}{"chat_theme_emoticon": "🎨"},
	}
	e.cacheMessage("a1", "c1", svc)
	if got := getEmoticon(); got != "🎨" {
		t.Fatalf("emoticon = %q, want 🎨", got)
	}

	// A later reset (empty emoticon, key present) clears it.
	svc2 := &cores.Message{
		ID: "m3", ChatID: "c1", IsService: true, Text: "changed the chat theme",
		Timestamp: time.Now().Add(2 * time.Second),
		Extra:     map[string]interface{}{"chat_theme_emoticon": ""},
	}
	e.cacheMessage("a1", "c1", svc2)
	if got := getEmoticon(); got != "" {
		t.Fatalf("reset emoticon = %q, want empty", got)
	}

	// ChatInfo round-trips the emoticon.
	svc3 := &cores.Message{
		ID: "m4", ChatID: "c1", IsService: true, Text: "theme",
		Timestamp: time.Now().Add(3 * time.Second),
		Extra:     map[string]interface{}{"chat_theme_emoticon": "🎉"},
	}
	e.cacheMessage("a1", "c1", svc3)
	chats, err := e.GetChatList("a1", false, 10, 0)
	if err != nil || len(chats) == 0 {
		t.Fatalf("chat list: %v (%d)", err, len(chats))
	}
	if chats[0].ThemeEmoticon != "🎉" {
		t.Fatalf("ChatInfo.ThemeEmoticon = %q, want 🎉", chats[0].ThemeEmoticon)
	}

	// Non-string extra values are skipped, not fatal.
	e.cacheMessage("a1", "c1", &cores.Message{
		ID: "m5", ChatID: "c1", IsService: true, Text: "theme", Timestamp: time.Now().Add(4 * time.Second),
		Extra: map[string]interface{}{"chat_theme_emoticon": 42},
	})
	if got := getEmoticon(); got != "🎉" {
		t.Fatalf("non-string extra clobbered theme: %q", got)
	}
}

func TestEnsureChatExistsSeedsTheme(t *testing.T) {
	e := newTestEngine(t)
	// The chat's FIRST message is the theme change (new chat path — the
	// INSERT runs before cacheMessage's mirror, so the seed must apply).
	// Same message object through both calls — the events.go ingest order
	// (cacheMessage runs first, no chat row exists yet for its mirror).
	svc := &cores.Message{
		ID: "m1", ChatID: "c9", IsService: true, Text: "theme", SenderName: "X",
		Timestamp: time.Now(),
		Extra:     map[string]interface{}{"chat_theme_emoticon": "❤️"},
	}
	e.cacheMessage("a1", "c9", svc)
	e.ensureChatExists("a1", "c9", svc)
	var em string
	if err := e.db.QueryRow(
		`SELECT theme_emoticon FROM chats WHERE account_id = ? AND chat_id = ?`, "a1", "c9").Scan(&em); err != nil {
		t.Fatal(err)
	}
	if em != "❤️" {
		t.Fatalf("seed emoticon = %q, want ❤️ (ensureChatExists must seed it)", em)
	}
}
