package gui

import (
	"strings"
	"testing"
)

func TestInChatSearchKey(t *testing.T) {
	k := chatKey{AccountID: "acc1", ChatID: "100"}
	if got := inChatSearchKey("hi", k); got != "hi@acc1/100" {
		t.Errorf("key = %q, want hi@acc1/100", got)
	}
	if got := inChatSearchKey("", k); got != "@acc1/100" {
		t.Errorf("empty q key = %q", got)
	}
}

func TestSearchSnippet(t *testing.T) {
	if got := searchSnippet(""); got != "(no text)" {
		t.Errorf("empty = %q, want (no text)", got)
	}
	short := "hello world"
	if got := searchSnippet(short); got != short {
		t.Errorf("short = %q, want unchanged", got)
	}
	long := strings.Repeat("x", 200)
	got := searchSnippet(long)
	if !strings.HasSuffix(got, "…") {
		t.Errorf("long snippet should end with ellipsis: %q…", got[:20])
	}
	// Rune-count clamp: 96 runes + ellipsis.
	if n := len([]rune(got)); n != 97 {
		t.Errorf("snippet runes = %d, want 97", n)
	}
	// Multi-byte runes must not be split mid-rune.
	multi := strings.Repeat("é", 300)
	got = searchSnippet(multi)
	for _, r := range got {
		if r == 0xFFFD {
			t.Fatal("replacement rune found: multi-byte text was split")
		}
	}
}
