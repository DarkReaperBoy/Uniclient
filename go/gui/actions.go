package gui

import (
	"strings"

	"uniclient/engine"
)

type msgActions struct {
	Reply     bool
	Edit      bool
	Copy      bool
	Forward   bool
	Delete    bool
	Pin       bool
	React     bool
	Translate bool
	Filter    bool
	Retry     bool
}

func actionsFor(m *engine.CachedMessage, caps []string) msgActions {
	if m == nil || m.IsService {
		return msgActions{}
	}
	hasCap := func(want string) bool {
		for _, c := range caps {
			if c == want {
				return true
			}
		}
		return false
	}
	pending := m.IsOutgoing && (m.Status == engine.MsgStatusSending || m.Status == engine.MsgStatusFailed)
	return msgActions{
		Reply:     !pending,
		Edit:      m.IsOutgoing && !pending,
		Copy:      strings.TrimSpace(m.ContentText) != "",
		Forward:   !m.NoForwards && !pending,
		Delete:    true,
		Pin:       !pending,
		React:     hasCap("REACTIONS") && !pending,
		Translate: strings.TrimSpace(m.ContentText) != "",
		Filter:    strings.TrimSpace(m.ContentText) != "",
		Retry:     m.IsOutgoing && m.Status == engine.MsgStatusFailed,
	}
}

type composerMode struct {
	reply *engine.CachedMessage
	edit  *engine.CachedMessage
}

func (c *composerMode) startReply(m *engine.CachedMessage) {
	if m == nil {
		return
	}
	c.reply, c.edit = m, nil
}

func (c *composerMode) startEdit(m *engine.CachedMessage) {
	if m == nil {
		return
	}
	c.edit, c.reply = m, nil
}

func (c *composerMode) cancel() {
	c.reply, c.edit = nil, nil
}

func (c *composerMode) active() bool { return c.reply != nil || c.edit != nil }

func (c *composerMode) header() (title, preview string) {
	if c.edit != nil {
		return "Edit message", quotePreview(c.edit.ContentText, 64)
	}
	if c.reply != nil {
		title = "Reply to " + c.reply.SenderName
		if c.reply.SenderName == "" {
			title = "Reply"
		}
		return title, quotePreview(c.reply.ContentText, 64)
	}
	return "", ""
}

func (c *composerMode) replyTarget() string {
	if c.reply != nil {
		return c.reply.MsgID
	}
	return ""
}

func (c *composerMode) editTarget() *engine.CachedMessage { return c.edit }

func quotePreview(s string, max int) string {
	s = strings.TrimSpace(s)
	if i := strings.IndexByte(s, '\n'); i >= 0 {
		s = s[:i]
	}
	r := []rune(s)
	if len(r) <= max {
		return s
	}
	return string(r[:max]) + "…"
}
