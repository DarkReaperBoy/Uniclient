package gui

import (
	"log"
	"strings"
	"time"

	"gioui.org/io/system"

	"uniclient/engine"
)

const notifyThrottle = 5 * time.Second

var notifyDefaultActions = []string{"default", "Open chat"}

func notifyIconURI(chat engine.ChatInfo) string {
	if chat.AvatarPath == "" {
		return ""
	}
	return "file://" + chat.AvatarPath
}

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
	default:
		return cfg.NotifyDMs
	}
}

func notifyBody(m engine.CachedMessage) string {
	txt := strings.TrimSpace(m.ContentText)
	if txt == "" && m.MediaType != 0 {
		txt = engine.MediaPreviewLabel(m.MediaType)
	}
	if txt == "" {
		txt = "New message"
	}
	txt = strings.Join(strings.Fields(txt), " ")
	const max = 96
	r := []rune(txt)
	if len(r) > max {
		return strings.TrimSpace(string(r[:max])) + "…"
	}
	return txt
}

func notifyPreviewBody(m engine.CachedMessage, showText bool) string {
	if !showText {
		return "New message"
	}
	return notifyBody(m)
}

func notifyTitle(chat engine.ChatInfo, m engine.CachedMessage) string {
	if chat.Title != "" {
		return chat.Title
	}
	if m.SenderName != "" {
		return m.SenderName
	}
	return "Uniclient"
}

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
	if cfg.NotifyPreviews && m.Message.SenderName != "" && title != m.Message.SenderName {
		body = m.Message.SenderName + ": " + body
	}
	go func() {
		sound := notifySoundFor(cfg.NotifySound, "")
		if kind, err := a.eng.GetChatNotifySound(m.AccountID, m.ChatID); err == nil {
			sound = notifySoundFor(cfg.NotifySound, kind)
		}
		playNotifySound(sound)
	}()
	go func() {
		if err := notifyDesktop(title, body, key, notifyIconURI(chat),
			notifyDefaultActions, notifyOpenAction(a, chatKey{
				AccountID: m.AccountID, ChatID: m.ChatID,
			}, title)); err != nil {
			log.Printf("gui: notify: %v", err)
		}
	}()
}
