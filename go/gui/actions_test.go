package gui

import (
	"testing"

	"uniclient/engine"
)

// actionsFor gates every context-menu entry on real message state and real
// backend capabilities (AyuGram parity: the menu never shows a dead action).
func TestActionsFor(t *testing.T) {
	telegramCaps := []string{"TEXT", "REACTIONS", "ADMIN", "CALLS"}
	noReactCaps := []string{"TEXT"}

	base := func() engine.CachedMessage {
		return engine.CachedMessage{
			MsgID:       "10",
			ChatID:      "c",
			ContentText: "hello",
		}
	}

	t.Run("plain incoming message", func(t *testing.T) {
		m := base()
		a := actionsFor(&m, telegramCaps)
		if !a.Reply || !a.Copy || !a.Forward || !a.Delete || !a.React {
			t.Errorf("incoming message should allow reply/copy/forward/delete/react, got %+v", a)
		}
		if a.Edit {
			t.Errorf("incoming message must not be editable")
		}
	})

	t.Run("own outgoing message", func(t *testing.T) {
		m := base()
		m.IsOutgoing = true
		a := actionsFor(&m, telegramCaps)
		if !a.Edit {
			t.Errorf("own outgoing message must be editable")
		}
	})

	t.Run("service message has no actions", func(t *testing.T) {
		m := base()
		m.IsService = true
		a := actionsFor(&m, telegramCaps)
		if a.Reply || a.Edit || a.Delete || a.React || a.Forward || a.Pin {
			t.Errorf("service message must have no message actions, got %+v", a)
		}
	})

	t.Run("noForwards hides forward", func(t *testing.T) {
		m := base()
		m.NoForwards = true
		a := actionsFor(&m, telegramCaps)
		if a.Forward {
			t.Errorf("NoForwards message must not offer forward")
		}
	})

	t.Run("reactions gated by capability", func(t *testing.T) {
		m := base()
		if actionsFor(&m, noReactCaps).React {
			t.Errorf("backend without REACTIONS capability must not offer react")
		}
		if !actionsFor(&m, telegramCaps).React {
			t.Errorf("backend with REACTIONS capability should offer react")
		}
	})

	t.Run("pending messages only deletable", func(t *testing.T) {
		m := base()
		m.IsOutgoing = true
		m.Status = engine.MsgStatusSending
		a := actionsFor(&m, telegramCaps)
		if a.Edit || a.Reply || a.Forward || a.Pin || a.React {
			t.Errorf("pending (unconfirmed) message should only allow delete, got %+v", a)
		}
		if !a.Delete {
			t.Errorf("pending message must allow delete")
		}
	})
}

// composerMode mirrors AyuGram's reply/edit header bar above the input field.
func TestComposerMode(t *testing.T) {
	var c composerMode

	if c.active() {
		t.Fatalf("zero composerMode must be inactive")
	}
	if title, _ := c.header(); title != "" {
		t.Fatalf("inactive mode must have no header, got %q", title)
	}

	msg := &engine.CachedMessage{MsgID: "42", SenderName: "Alice", ContentText: "hi there"}
	c.startReply(msg)
	if !c.active() || c.replyTarget() != "42" || c.editTarget() != nil {
		t.Fatalf("reply mode broken: %+v", c)
	}
	title, preview := c.header()
	if title != "Reply to Alice" {
		t.Errorf("reply header title = %q, want %q", title, "Reply to Alice")
	}
	if preview != "hi there" {
		t.Errorf("reply header preview = %q, want %q", preview, "hi there")
	}

	// Switching to edit replaces reply (AyuGram: one mode at a time).
	editMsg := &engine.CachedMessage{MsgID: "43", ContentText: "old text"}
	c.startEdit(editMsg)
	if c.replyTarget() != "" || c.editTarget() == nil || c.editTarget().MsgID != "43" {
		t.Fatalf("edit mode broken: %+v", c)
	}
	title, _ = c.header()
	if title != "Edit message" {
		t.Errorf("edit header title = %q, want %q", title, "Edit message")
	}

	c.cancel()
	if c.active() || c.replyTarget() != "" || c.editTarget() != nil {
		t.Fatalf("cancel must clear the mode: %+v", c)
	}

	// startReply then cancel then startEdit with prefill text.
	c.startReply(msg)
	c.cancel()
	c.startEdit(editMsg)
	if c.editTarget() == nil || c.editTarget().ContentText != "old text" {
		t.Fatalf("edit prefill source broken")
	}
}

// quotePreview truncates long quoted previews the way AyuGram's reply bar does.
func TestQuotePreview(t *testing.T) {
	cases := []struct {
		in, want string
	}{
		{"", ""},
		{"short", "short"},
		// previews keep the first line only (AyuGram one-liner quotes)
		{"line one\nline two", "line one"},
	}
	for _, c := range cases {
		if got := quotePreview(c.in, 40); got != c.want {
			t.Errorf("quotePreview(%q) = %q, want %q", c.in, got, c.want)
		}
	}
	long := "0123456789012345678901234567890123456789012345"
	if got := quotePreview(long, 40); got != "0123456789012345678901234567890123456789…" {
		t.Errorf("quotePreview truncation failed: %q", got)
	}
}
