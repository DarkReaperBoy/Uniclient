package gui

import (
	"testing"

	"uniclient/engine"
)

func TestSenderColorForPalette(t *testing.T) {
	seen := map[[4]uint8]bool{}
	for id := 0; id < 7; id++ {
		c := senderColorFor(id, "42")
		seen[[4]uint8{c.R, c.G, c.B, c.A}] = true
	}
	if len(seen) != 7 {
		t.Fatalf("7 color ids must produce 7 distinct colors, got %d", len(seen))
	}
}

func TestSenderColorForUnknownFallsBackStable(t *testing.T) {
	a := senderColorFor(-1, "111")
	b := senderColorFor(-1, "111")
	if a != b {
		t.Fatal("same sender must always get the same color")
	}
	c := senderColorFor(-1, "222")
	if a == c {
		t.Fatal("different senders should (usually) differ — palette spread")
	}
	seen := map[[4]uint8]bool{}
	for i := 0; i < 100; i++ {
		col := senderColorFor(-1, itoa(100+i))
		seen[[4]uint8{col.R, col.G, col.B, col.A}] = true
	}
	if len(seen) != 7 {
		t.Fatalf("fallback must cover all 7 colors over a 100-id window, got %d", len(seen))
	}
}

func TestSenderColorForZeroIsValid(t *testing.T) {
	if senderColorFor(0, "1") == (senderColorFor(1, "1")) {
		t.Fatal("ids 0 and 1 must differ")
	}
}

func TestSenderTitle(t *testing.T) {
	m := engine.CachedMessage{SenderName: "Alice"}
	if got := senderTitle(m); got != "Alice" {
		t.Fatalf("no rank: %q", got)
	}
	m.SenderRank = "admin"
	if got := senderTitle(m); got != "Alice (admin)" {
		t.Fatalf("rank: %q", got)
	}
	m.SenderRank = "owner"
	if got := senderTitle(m); got != "Alice (owner)" {
		t.Fatalf("custom rank: %q", got)
	}
}
