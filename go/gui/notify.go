package gui

import (
	"log"
	"strings"
	"time"

	"gioui.org/io/system"

	"uniclient/engine"
)

// Desktop notifications (AyuGram parity, matrix #279): new incoming
// messages raise a system banner when the chat is not open, honoring the
// global notify config (DMs / groups / mentions-only) and per-chat mute.
// Linux delivers through org.freedesktop.Notifications (DBus); other
// targets stub the transport until a native layer lands.

// notifyThrottle bounds banners per chat (bursty chats notify once).
const notifyThrottle = 5 * time.Second

// notifyDefaultActions: the freedesktop action pair for chat banners —
// the reserved "default" action is the whole-body click on every major
// server (GNOME, KDE), so one pair covers tdesktop's tap-to-open.
var notifyDefaultActions = []string{"default", "Open chat"}

// notifyIconURI (pure, testable): the banner's image hint — the chat
// avatar as a file URI when the engine has downloaded one, empty (server
// default) otherwise.
func notifyIconURI(chat engine.ChatInfo) string {
	if chat.AvatarPath == "" {
		return ""
	}
	return "file://" + chat.AvatarPath
}

// notifyOpenAction builds the banner-click handler: raise the window and
// schedule the chat open on the GUI loop (the pendingOpen hop — openChat
// touches the a.wid.composer editor and must never run from the dbus demux
// goroutine). Safe on a zero App (no window → no raise).
func notifyOpenAction(a *App, k chatKey, title string) func(string) {
	return func(string) {
		if w := a.win; w != nil {
			w.Perform(system.ActionRaise)
		}
		a.mu.Lock()
		a.pendingOpen = &k
		a.pendingTitle = title
		a.mu.Unlock()
		a.invalidate()
	}
}

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

// notifyPreviewBody (pure, testable): the banner body honoring the
// content-privacy toggle — "New message" when previews are hidden
// (AyuGram/Telegram behavior), the clamped text or media label otherwise.
func notifyPreviewBody(m engine.CachedMessage, showText bool) string {
	if !showText {
		return "New message"
	}
	return notifyBody(m)
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
	body := notifyPreviewBody(m.Message, cfg.NotifyPreviews)
	// The sender prefix is part of the preview — hide it too when off.
	if cfg.NotifyPreviews && m.Message.SenderName != "" && title != m.Message.SenderName {
		body = m.Message.SenderName + ": " + body
	}
	// Notification sound (slice 121): per-chat override wins over the
	// global config kind; the banner itself is independent of it.
	go func() {
		sound := notifySoundFor(cfg.NotifySound, "")
		if kind, err := a.eng.GetChatNotifySound(m.AccountID, m.ChatID); err == nil {
			sound = notifySoundFor(cfg.NotifySound, kind)
		}
		playNotifySound(sound)
	}()
	// The banner itself (slice 141): click-to-open through the freedesktop
	// default action, per-chat in-place replacement (banners never stack
	// for one chat), the peer avatar as the image hint.
	go func() {
		if err := notifyDesktop(title, body, key, notifyIconURI(chat),
			notifyDefaultActions, notifyOpenAction(a, chatKey{
				AccountID: m.AccountID, ChatID: m.ChatID,
			}, title)); err != nil {
			log.Printf("gui: notify: %v", err)
		}
	}()
}
