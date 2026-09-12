package gui

import (
	"testing"

	"uniclient/engine"
)

// TestTransLangName: code → display name resolution with fallbacks.
func TestTransLangName(t *testing.T) {
	if got := transLangName("en"); got != "English" {
		t.Fatalf("en = %q", got)
	}
	if got := transLangName("fa"); got != "Persian" {
		t.Fatalf("fa = %q", got)
	}
	if got := transLangName("xx"); got != "xx" {
		t.Fatalf("xx = %q, want passthrough", got)
	}
	if got := transLangName(""); got != "English" {
		t.Fatalf("empty = %q, want English", got)
	}
}

// TestNormalizeTransTarget: clamping to the curated list.
func TestNormalizeTransTarget(t *testing.T) {
	cases := []struct{ in, want string }{
		{"", "en"},
		{"en", "en"},
		{"de", "de"},
		{"EN", "en"}, // unknown (case-sensitive) → default
		{"xx", "en"},
		{"english", "en"},
	}
	for _, c := range cases {
		if got := normalizeTransTarget(c.in); got != c.want {
			t.Fatalf("normalize(%q) = %q want %q", c.in, got, c.want)
		}
	}
}

// TestTransLangsUnique: no duplicate codes in the picker list.
func TestTransLangsUnique(t *testing.T) {
	seen := map[string]bool{}
	for _, l := range transLangs {
		if l.code == "" || l.name == "" {
			t.Fatalf("empty entry: %+v", l)
		}
		if seen[l.code] {
			t.Fatalf("duplicate code %q", l.code)
		}
		seen[l.code] = true
	}
}

// TestTransChatKey: stable per-chat key.
func TestTransChatKey(t *testing.T) {
	if got := transChatKey("acc1", "chat1"); got != "acc1|chat1" {
		t.Fatalf("key = %q", got)
	}
	if transChatKey("a", "b") == transChatKey("b", "a") {
		t.Fatalf("keys collide")
	}
}

// TestHeaderMenuTranslateEntry: the ⋮ menu carries the state-aware
// translate rows (slice 150).
func TestHeaderMenuTranslateEntry(t *testing.T) {
	dm := engine.ChatInfo{Type: engine.ChatTypeDMVal}
	off := headerMenuItems(dm, false, false, false)
	if !containsAction(off, "transon") {
		t.Fatalf("off-state menu lacks Translate to…: %+v", off)
	}
	if containsAction(off, "transoff") {
		t.Fatalf("off-state menu shows Hide translations")
	}
	on := headerMenuItems(dm, false, false, true)
	if !containsAction(on, "transoff") {
		t.Fatalf("on-state menu lacks Hide translations: %+v", on)
	}
	if containsAction(on, "transon") {
		t.Fatalf("on-state menu shows Translate to…")
	}
}
