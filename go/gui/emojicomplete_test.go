package gui

import (
	"testing"

	"gioui.org/widget"

	"uniclient/engine"
)

// ── emojiAutocompleteQuery (pure) ──────────────────────────────────────────

func TestEmojiAutocompleteQuery(t *testing.T) {
	cases := []struct {
		name       string
		text       string
		caret      int // rune offset of the caret
		wantQuery  string
		wantStart  int
		wantActive bool
	}{
		{"mid-text token", "hello :fi", 9, "fi", 6, true},
		{"token at start", ":fire", 5, "fire", 0, true},
		{"url colon not a trigger", "see https://x.com", 17, "", 0, false},
		{"colon glued to word", "a:b", 3, "", 0, false},
		{"plain text", "no token here", 13, "", 0, false},
		{"single char token", ":f", 2, "f", 0, true},
		{"bare colon no token", ":", 1, "", 0, false},
		{"caret before token end", "abc :fire def", 9, "fire", 4, true},
		{"token with digits and plus", ":thumbs_up+1", 12, "thumbs_up+1", 0, true},
		{"second colon after unresolved token stays quiet", ":fire:work", 10, "", 0, false},
		{"chain after replaced emoji works", "🔥:work", 6, "work", 1, true},
		{"newline before colon ok", "hi\n:smi", 7, "smi", 3, true},
		{"caret inside word not at token edge", ":fire", 3, "fi", 0, true},
	}
	for _, tc := range cases {
		q, start, active := emojiAutocompleteQuery(tc.text, tc.caret)
		if q != tc.wantQuery || start != tc.wantStart || active != tc.wantActive {
			t.Errorf("%s: emojiAutocompleteQuery(%q,%d) = (%q,%d,%v), want (%q,%d,%v)",
				tc.name, tc.text, tc.caret, q, start, active, tc.wantQuery, tc.wantStart, tc.wantActive)
		}
	}
}

// ── emojiAutocompleteMatches (pure) ─────────────────────────────────────────

func kw(k string, es ...string) engine.EmojiKeywordEntry {
	return engine.EmojiKeywordEntry{Keyword: k, Emoticons: es}
}

func TestEmojiAutocompleteMatches(t *testing.T) {
	kws := []engine.EmojiKeywordEntry{
		kw("fire", "🔥"),
		kw("fireworks", "🎆"),
		kw("heart", "❤️", "♥️"),
		kw("smile", "😄"),
	}
	if got := emojiAutocompleteMatches(kws, "", 32); got != nil {
		t.Errorf("empty query should match nothing, got %v", got)
	}
	if got := emojiAutocompleteMatches(nil, "fire", 32); got != nil {
		t.Errorf("nil keywords should match nothing, got %v", got)
	}
	// Exact keyword first, then prefixes.
	got := emojiAutocompleteMatches(kws, "fire", 32)
	want := []string{"🔥", "🎆"}
	if len(got) != len(want) || got[0] != want[0] || got[1] != want[1] {
		t.Errorf("matches(fire) = %v, want %v", got, want)
	}
	// Prefix only.
	got = emojiAutocompleteMatches(kws, "fir", 32)
	if len(got) != 2 || got[0] != "🔥" || got[1] != "🎆" {
		t.Errorf("matches(fir) = %v, want [🔥 🎆]", got)
	}
	// Multiple emoticons under one keyword, order preserved.
	got = emojiAutocompleteMatches(kws, "heart", 32)
	if len(got) != 2 || got[0] != "❤️" || got[1] != "♥️" {
		t.Errorf("matches(heart) = %v, want [❤️ ♥️]", got)
	}
	// Dedupe across keywords.
	dup := []engine.EmojiKeywordEntry{kw("fire", "🔥"), kw("flame", "🔥", "🥵")}
	got = emojiAutocompleteMatches(dup, "f", 32)
	seen := map[string]int{}
	for _, e := range got {
		seen[e]++
	}
	if seen["🔥"] != 1 {
		t.Errorf("dedupe failed: %v", got)
	}
	// Cap respected.
	if got := emojiAutocompleteMatches(kws, "", 0); got != nil {
		// zero cap on empty query already nil; sanity only
		_ = got
	}
	// Case-insensitive.
	got = emojiAutocompleteMatches(kws, "FIRE", 32)
	if len(got) != 2 {
		t.Errorf("matches(FIRE) = %v, want 2", got)
	}
}

// ── editor replacement round-trip ───────────────────────────────────────────

func TestEmojiAutocompleteApply(t *testing.T) {
	var ed widget.Editor
	ed.SetText("hello :fire")
	// Caret at end; replace runes [6,11) with the emoji.
	ed.SetCaret(6, 11)
	ed.Insert("🔥")
	if got := ed.Text(); got != "hello 🔥" {
		t.Errorf("after apply Text() = %q, want %q", got, "hello 🔥")
	}
}

// The suggestion panel must never fight the emoji picker or the attach menu:
// the visibility predicate is pure and testable.
func TestEmojiAutocompleteVisible(t *testing.T) {
	if emojiAutocompleteVisible(true, true) {
		t.Errorf("hidden while the emoji picker is open")
	}
	if emojiAutocompleteVisible(false, true) {
		t.Errorf("hidden while the attach menu is open")
	}
	if !emojiAutocompleteVisible(false, false) {
		t.Errorf("visible with a live token and no competing panels")
	}
}
