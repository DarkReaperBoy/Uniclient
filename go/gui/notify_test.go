package gui

import (
	"strings"
	"testing"

	"uniclient/engine"
	"uniclient/utils"
)

func allOn() cfgSnapshot {
	return cfgSnapshot{NotifyDMs: true, NotifyGroups: true, NotifyMentionsOnly: false}
}

func TestShouldNotifyChat(t *testing.T) {
	cfg := allOn()
	dm := engine.ChatInfo{Type: engine.ChatTypeDMVal, Title: "Alice"}
	grp := engine.ChatInfo{Type: engine.ChatTypeGroupVal, Title: "Dev"}
	chanl := engine.ChatInfo{Type: engine.ChatTypeChanVal, Title: "News"}

	if !shouldNotifyChat(cfg, dm, false) {
		t.Fatal("DM, config on, not open: should notify")
	}
	if shouldNotifyChat(cfg, dm, true) {
		t.Fatal("open chat: should not notify")
	}
	muted := dm
	muted.IsMuted = true
	if shouldNotifyChat(cfg, muted, false) {
		t.Fatal("muted chat: should not notify")
	}

	cfg2 := cfg
	cfg2.NotifyGroups = false
	if shouldNotifyChat(cfg2, grp, false) || shouldNotifyChat(cfg2, chanl, false) {
		t.Fatal("groups off: group/channel should not notify")
	}
	if !shouldNotifyChat(cfg2, dm, false) {
		t.Fatal("groups off: DMs still notify")
	}

	cfg3 := allOn()
	cfg3.NotifyDMs = false
	if shouldNotifyChat(cfg3, dm, false) {
		t.Fatal("DMs off: DM should not notify")
	}

	cfg4 := allOn()
	cfg4.NotifyMentionsOnly = true
	if shouldNotifyChat(cfg4, grp, false) {
		t.Fatal("mentions-only, no mentions: should not notify")
	}
	grpM := grp
	grpM.UnreadMentionCount = 2
	if !shouldNotifyChat(cfg4, grpM, false) {
		t.Fatal("mentions-only with unread mentions: should notify")
	}
	if !shouldNotifyChat(cfg4, dm, false) {
		t.Fatal("mentions-only still delivers DMs (Telegram semantics)")
	}
}

func TestNotifyBody(t *testing.T) {
	m := engine.CachedMessage{ContentText: "hello world"}
	if got := notifyBody(m); got != "hello world" {
		t.Errorf("body = %q", got)
	}
	m = engine.CachedMessage{ContentText: "line1\nline2\ttabbed"}
	if got := notifyBody(m); strings.ContainsAny(got, "\n\t") {
		t.Errorf("newlines must collapse: %q", got)
	}
	m = engine.CachedMessage{ContentText: "", MediaType: 2}
	if got := notifyBody(m); got == "" || got == "New message" {
		if engine.MediaPreviewLabel(2) != "" {
			t.Errorf("media-only should use the typed label: %q", got)
		}
	}
	m = engine.CachedMessage{}
	if got := notifyBody(m); got != "New message" {
		t.Errorf("empty = %q", got)
	}
	long := engine.CachedMessage{ContentText: string(make([]rune, 300))}
	if n := len([]rune(notifyBody(long))); n > 96+1 {
		t.Errorf("clamped = %d runes", n)
	}
}

func TestNotifyTitle(t *testing.T) {
	if got := notifyTitle(engine.ChatInfo{Title: "Dev"}, engine.CachedMessage{SenderName: "Bob"}); got != "Dev" {
		t.Errorf("title = %q", got)
	}
	if got := notifyTitle(engine.ChatInfo{}, engine.CachedMessage{SenderName: "Bob"}); got != "Bob" {
		t.Errorf("sender fallback = %q", got)
	}
	if got := notifyTitle(engine.ChatInfo{}, engine.CachedMessage{}); got != "Uniclient" {
		t.Errorf("final fallback = %q", got)
	}
}

func TestNotifyPreviewBody(t *testing.T) {
	m := engine.CachedMessage{ContentText: "meet me at the station"}
	if got := notifyPreviewBody(m, true); got != "meet me at the station" {
		t.Errorf("previews on = %q", got)
	}
	// Hidden previews never leak the text — or the media type.
	if got := notifyPreviewBody(m, false); got != "New message" {
		t.Errorf("previews off = %q", got)
	}
	media := engine.CachedMessage{MediaType: engine.MediaImage}
	if got := notifyPreviewBody(media, false); got != "New message" {
		t.Errorf("media previews off = %q", got)
	}
}

func TestNotifyPreviewsEnabledResolver(t *testing.T) {
	cfg := &utils.AppConfig{}
	if !cfg.NotifyPreviewsEnabled() {
		t.Error("nil pointer must default to true")
	}
	off := false
	cfg.NotifyPreviews = &off
	if cfg.NotifyPreviewsEnabled() {
		t.Error("false pointer must resolve false")
	}
	on := true
	cfg.NotifyPreviews = &on
	if !cfg.NotifyPreviewsEnabled() {
		t.Error("true pointer must resolve true")
	}
}
