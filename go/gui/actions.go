package gui

import (
	"strings"

	"uniclient/engine"
)

// Message-action layer — mirrors AyuGramDesktop's context menu + reply/edit
// composer header (research/ayugram_parity.md §3/§4, top gaps 1/7/8).
//
// Everything here gates on real state: menu actions are derived from the
// message flags and the account's backend capabilities, so the GUI never
// offers an action that cannot really be dispatched (§1.10 — no dead UI).

// msgActions is the set of context-menu actions available for one message.
type msgActions struct {
	Reply     bool
	Edit      bool
	Copy      bool
	Forward   bool
	Delete    bool
	Pin       bool
	React     bool
	Translate bool
}

// actionsFor derives the AyuGram message context-menu action set.
//   - Reply: any real message (not service, not still-pending).
//   - Edit: own outgoing, non-service, confirmed (server echo'd it).
//   - Forward: hidden when the chat/sender forbids it (NoForwards).
//   - React: only when the backend has the REACTIONS capability.
//   - Translate: any message with text (Ayu translator; free-text path).
//   - Delete: always available for real messages (revoke = own message).
//   - Pin: available; the engine surfaces a per-chat error honestly.
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
	}
}

// composerMode is the reply/edit context above the input field. Exactly one
// of reply/edit is set at a time — AyuGram shows a header chip with the
// quoted message (reply) or the original text (edit) and a close button.
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

// header returns the chip title and quoted preview for the active mode.
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

// quotePreview truncates s to max runes, appending an ellipsis when cut.
// Reply previews keep at most one newline (AyuGram quotes are one-liners).
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
