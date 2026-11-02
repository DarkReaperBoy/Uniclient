package tests

import (
	"testing"
	"time"
	. "uniclient/engine"

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

	e.CacheMessage("a1", "c1", &cores.Message{ID: "m1", ChatID: "c1", Text: "hi", Timestamp: time.Now()})
	if got := getEmoticon(); got != "" {
		t.Fatalf("plain message set theme %q", got)
	}

	svc := &cores.Message{
		ID: "m2", ChatID: "c1", IsService: true, Text: "changed the chat theme",
		Timestamp: time.Now().Add(time.Second),
		Extra:     map[string]interface{}{"chat_theme_emoticon": "🎨"},
	}
	e.CacheMessage("a1", "c1", svc)
	if got := getEmoticon(); got != "🎨" {
		t.Fatalf("emoticon = %q, want 🎨", got)
	}

	svc2 := &cores.Message{
		ID: "m3", ChatID: "c1", IsService: true, Text: "changed the chat theme",
		Timestamp: time.Now().Add(2 * time.Second),
		Extra:     map[string]interface{}{"chat_theme_emoticon": ""},
	}
	e.CacheMessage("a1", "c1", svc2)
	if got := getEmoticon(); got != "" {
		t.Fatalf("reset emoticon = %q, want empty", got)
	}

	svc3 := &cores.Message{
		ID: "m4", ChatID: "c1", IsService: true, Text: "theme",
		Timestamp: time.Now().Add(3 * time.Second),
		Extra:     map[string]interface{}{"chat_theme_emoticon": "🎉"},
	}
	e.CacheMessage("a1", "c1", svc3)
	chats, err := e.GetChatList("a1", false, 10, 0)
	if err != nil || len(chats) == 0 {
		t.Fatalf("chat list: %v (%d)", err, len(chats))
	}
	if chats[0].ThemeEmoticon != "🎉" {
		t.Fatalf("ChatInfo.ThemeEmoticon = %q, want 🎉", chats[0].ThemeEmoticon)
	}

	e.CacheMessage("a1", "c1", &cores.Message{
		ID: "m5", ChatID: "c1", IsService: true, Text: "theme", Timestamp: time.Now().Add(4 * time.Second),
		Extra: map[string]interface{}{"chat_theme_emoticon": 42},
	})
	if got := getEmoticon(); got != "🎉" {
		t.Fatalf("non-string extra clobbered theme: %q", got)
	}
}

func TestEnsureChatExistsSeedsTheme(t *testing.T) {
	e := newTestEngine(t)
	svc := &cores.Message{
		ID: "m1", ChatID: "c9", IsService: true, Text: "theme", SenderName: "X",
		Timestamp: time.Now(),
		Extra:     map[string]interface{}{"chat_theme_emoticon": "❤️"},
	}
	e.CacheMessage("a1", "c9", svc)
	e.EnsureChatExists("a1", "c9", svc)
	var em string
	if err := e.db.QueryRow(
		`SELECT theme_emoticon FROM chats WHERE account_id = ? AND chat_id = ?`, "a1", "c9").Scan(&em); err != nil {
		t.Fatal(err)
	}
	if em != "❤️" {
		t.Fatalf("seed emoticon = %q, want ❤️ (ensureChatExists must seed it)", em)
	}
}
