package gui

import (
	"strings"
	"testing"

	"uniclient/engine"
)

// TestSeenInlineGate: only the last own outgoing DM message carries the
// inline receipt.
func TestSeenInlineGate(t *testing.T) {
	own := engine.CachedMessage{IsOutgoing: true, MsgID: "m1"}
	other := engine.CachedMessage{IsOutgoing: false, MsgID: "m2"}
	service := engine.CachedMessage{IsOutgoing: true, IsService: true, MsgID: "m3"}

	if !seenInlineGate(own, engine.ChatTypeDMVal, true) {
		t.Fatalf("own last DM message should gate")
	}
	if seenInlineGate(own, engine.ChatTypeDMVal, false) {
		t.Fatalf("non-last message should not gate")
	}
	if seenInlineGate(other, engine.ChatTypeDMVal, true) {
		t.Fatalf("incoming message should not gate")
	}
	if seenInlineGate(service, engine.ChatTypeDMVal, true) {
		t.Fatalf("service message should not gate")
	}
	if seenInlineGate(own, engine.ChatTypeGroupVal, true) {
		t.Fatalf("group chat should not gate (dialog-only)")
	}
	if seenInlineGate(own, engine.ChatTypeChanVal, true) {
		t.Fatalf("channel should not gate")
	}
}

// TestSeenInlineLabel: the "Seen" caption.
func TestSeenInlineLabel(t *testing.T) {
	if got := seenInlineLabel(0, false); got != "Seen" {
		t.Fatalf("no date = %q", got)
	}
	if got := seenInlineLabel(1737000000, true); !strings.HasPrefix(got, "Seen ") || len(got) < 8 {
		t.Fatalf("dated = %q", got)
	}
	if got := seenInlineLabel(0, true); got != "Seen" {
		t.Fatalf("zero date = %q", got)
	}
}

// TestLastOwnMsgID: the last own non-service message in the slice.
func TestLastOwnMsgID(t *testing.T) {
	msgs := []engine.CachedMessage{
		{MsgID: "a", IsOutgoing: true},
		{MsgID: "b", IsOutgoing: false},
		{MsgID: "c", IsOutgoing: false},
	}
	if got := lastOwnMsgID(msgs); got != "a" {
		t.Fatalf("last own = %q", got)
	}
	msgs = append(msgs, engine.CachedMessage{MsgID: "d", IsOutgoing: true})
	if got := lastOwnMsgID(msgs); got != "d" {
		t.Fatalf("last own = %q", got)
	}
	msgs = append(msgs, engine.CachedMessage{MsgID: "e", IsOutgoing: true, IsService: true})
	if got := lastOwnMsgID(msgs); got != "d" {
		t.Fatalf("service message skipped: %q", got)
	}
	if got := lastOwnMsgID(nil); got != "" {
		t.Fatalf("empty = %q", got)
	}
}
