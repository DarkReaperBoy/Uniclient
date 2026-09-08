package gui

import (
	"log"
	"strings"
	"time"

	"uniclient/engine"
)

// Desktop notifications (AyuGram parity, matrix #279): new incoming
// messages raise a system banner when the chat is not open, honoring the
// global notify config (DMs / groups / mentions-only) and per-chat mute.
// Linux delivers through org.freedesktop.Notifications (DBus); other
// targets stub the transport until a native layer lands.

// notifyThrottle bounds banners per chat (bursty chats notify once).
const notifyThrottle = 5 * time.Second

// shouldNotifyChat (pure, testable): config + mute + open-chat gating.
func shouldNotifyChat(cfg cfgSnapshot, chat engine.ChatInfo, open bool) bool {
	if open || chat.IsMuted {
		return false
	}
	switch chat.Type {
	case engine.ChatTypeGroupVal, engine.ChatTypeChanVal:
		if cfg.NotifyMentionsOnly {
			return chat.UnreadMentionCount > 0
		}
		return cfg.NotifyGroups
	default: // DMs, topics and anything person-like
		return cfg.NotifyDMs
	}
}

// notifyBody (pure, testable): the banner body for a message — a clamped
// single-line text, or the typed media label for media-only messages.
func notifyBody(m engine.CachedMessage) string {
	txt := strings.TrimSpace(m.ContentText)
	if txt == "" && m.MediaType != 0 {
		txt = engine.MediaPreviewLabel(m.MediaType)
	}
	if txt == "" {
		txt = "New message"
	}
	txt = strings.Join(strings.Fields(txt), " ") // collapse newlines/tabs
	const max = 96
	r := []rune(txt)
	if len(r) > max {
		return strings.TrimSpace(string(r[:max])) + "…"
	}
	return txt
}

// notifyTitle (pure, testable): chat title or sender name.
func notifyTitle(chat engine.ChatInfo, m engine.CachedMessage) string {
	if chat.Title != "" {
		return chat.Title
	}
	if m.SenderName != "" {
		return m.SenderName
	}
	return "Uniclient"
}

// maybeNotify runs the gating + throttle for one received message and
// fires the (async) desktop banner. Called from the engine event pump.
func (a *App) maybeNotify(m engine.MsgReceivedEvent) {
	if m.Message.IsOutgoing || m.Message.IsService {
		return
	}
	key := m.AccountID + "/" + m.ChatID
	now := time.Now()

	a.mu.Lock()
	open := a.selected != nil && a.selected.AccountID == m.AccountID && a.selected.ChatID == m.ChatID
	var chat engine.ChatInfo
	for _, c := range a.chats {
		if c.AccountID == m.AccountID && c.ChatID == m.ChatID {
			chat = c
			break
		}
	}
	cfg := a.cfg
	if a.notifyAt == nil {
		a.notifyAt = make(map[string]time.Time)
	}
	if now.Sub(a.notifyAt[key]) < notifyThrottle {
		a.mu.Unlock()
		return
	}
	a.notifyAt[key] = now
	a.mu.Unlock()

	if !shouldNotifyChat(cfg, chat, open) {
		return
	}
	title := notifyTitle(chat, m.Message)
	body := notifyBody(m.Message)
	if m.Message.SenderName != "" && title != m.Message.SenderName {
		body = m.Message.SenderName + ": " + body
	}
	go func() {
		if err := notifyDesktop(title, body); err != nil {
			log.Printf("gui: notify: %v", err)
		}
	}()
}
