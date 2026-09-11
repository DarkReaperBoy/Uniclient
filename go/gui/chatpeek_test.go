package gui

// chatpeek_test.go — slice 145 (tests-first): the pure halves of the
// hover chat-preview popup — message-line assembly and anchor clamping.

import (
	"testing"
	"time"

	"uniclient/engine"
)

// TestPeekMsgLine: one message becomes one preview line — "You" prefix
// for outgoing, sender name for incoming, media-only messages get the
// typed label, service messages are skipped upstream.
func TestPeekMsgLine(t *testing.T) {
	cases := []struct {
		m          engine.CachedMessage
		wantSender string
		wantText   string
	}{
		{engine.CachedMessage{ContentText: "hello there"}, "", "hello there"},
		{engine.CachedMessage{IsOutgoing: true, ContentText: "sent"}, "You", "sent"},
		{engine.CachedMessage{SenderName: "Alice", ContentText: "hi"}, "Alice", "hi"},
		{engine.CachedMessage{MediaType: 2}, "", engine.MediaPreviewLabel(2)},
		{engine.CachedMessage{SenderName: "Bob", IsOutgoing: false, MediaType: 3}, "Bob", engine.MediaPreviewLabel(3)},
	}
	for _, c := range cases {
		s, txt := peekMsgLine(c.m)
		if s != c.wantSender || txt != c.wantText {
			t.Errorf("peekMsgLine(%+v) = (%q,%q), want (%q,%q)", c.m, s, txt, c.wantSender, c.wantText)
		}
	}
}

// TestPeekLines: newest-first messages flip to display order (oldest at
// the top), service messages drop, the list clamps to max.
func TestPeekLines(t *testing.T) {
	msgs := []engine.CachedMessage{
		{MsgID: "3", SenderName: "Alice", ContentText: "third"},
		{MsgID: "2", IsService: true, ContentText: "joined the group"},
		{MsgID: "1", SenderName: "Alice", ContentText: "first"},
	}
	lines := peekLines(msgs, 3)
	if len(lines) != 2 {
		t.Fatalf("lines = %d, want 2 (service dropped)", len(lines))
	}
	if lines[0].sender != "Alice" || lines[0].text != "first" {
		t.Fatalf("line 0 = %+v, want first (display order)", lines[0])
	}
	if lines[1].text != "third" {
		t.Fatalf("line 1 = %+v", lines[1])
	}

	// Clamp: more messages than max → last N in display order.
	many := []engine.CachedMessage{
		{MsgID: "5", ContentText: "5"},
		{MsgID: "4", ContentText: "4"},
		{MsgID: "3", ContentText: "3"},
		{MsgID: "2", ContentText: "2"},
		{MsgID: "1", ContentText: "1"},
	}
	lines = peekLines(many, 3)
	if len(lines) != 3 {
		t.Fatalf("clamped = %d, want 3", len(lines))
	}
	if lines[0].text != "3" || lines[2].text != "5" {
		t.Fatalf("clamped order wrong: %+v", lines)
	}

	if got := peekLines(nil, 3); len(got) != 0 {
		t.Fatalf("nil = %d, want 0", len(got))
	}
}

// TestPeekLineClamp: long texts clamp to one line.
func TestPeekLineClamp(t *testing.T) {
	long := make([]byte, 300)
	for i := range long {
		long[i] = 'x'
	}
	_, txt := peekMsgLine(engine.CachedMessage{ContentText: string(long)})
	if len([]rune(txt)) > peekMaxRunes+1 { // +1 for the ellipsis
		t.Fatalf("clamped text len = %d, want ≤ %d", len([]rune(txt)), peekMaxRunes+1)
	}
}

// TestPeekAnchorY: the popup clamps inside the window height.
func TestPeekAnchorY(t *testing.T) {
	cases := []struct {
		mouseY, peekH, winH, want int
	}{
		{100, 120, 800, 76},  // centered-ish on the mouse, clamped by top
		{790, 120, 800, 680}, // bottom clamp
		{-5, 120, 800, 0},    // negative clamps to 0
		{400, 120, 800, 376}, // normal: mouse - 10% of height... see impl
	}
	for _, c := range cases {
		if got := peekAnchorY(c.mouseY, c.peekH, c.winH); got != c.want {
			t.Errorf("peekAnchorY(%d,%d,%d) = %d, want %d", c.mouseY, c.peekH, c.winH, got, c.want)
		}
	}
}

// TestPeekDelayBounds: the hover delay is in the tdesktop ballpark
// (400-900ms — fast enough to feel instant, slow enough not to flicker).
func TestPeekDelayBounds(t *testing.T) {
	if peekHoverDelay < 400*time.Millisecond || peekHoverDelay > 900*time.Millisecond {
		t.Fatalf("peekHoverDelay = %v, want 400-900ms", peekHoverDelay)
	}
}
