package tests

import (
	"testing"
	. "uniclient/cores"

	"github.com/gotd/td/tg"
)

func TestReactionClassForKey(t *testing.T) {
	if r, ok := ReactionClassForKey("👍").(*tg.ReactionEmoji); !ok || r.Emoticon != "👍" {
		t.Errorf("plain emoji key should decode to ReactionEmoji, got %T", ReactionClassForKey("👍"))
	}
	if r, ok := ReactionClassForKey("custom_9").(*tg.ReactionCustomEmoji); !ok || r.DocumentID != 9 {
		t.Errorf("custom_9 should decode to ReactionCustomEmoji{9}, got %T", ReactionClassForKey("custom_9"))
	}
	if r, ok := ReactionClassForKey("custom_bogus").(*tg.ReactionEmoji); !ok || r.Emoticon != "custom_bogus" {
		t.Errorf("malformed custom key should fall back to emoji, got %T", ReactionClassForKey("custom_bogus"))
	}
}

func TestDecodeDefaultReactionKey(t *testing.T) {
	if got := DecodeDefaultReactionKey(nil); got != "" {
		t.Errorf("nil reaction class = %q, want \"\"", got)
	}
	if got := DecodeDefaultReactionKey(&tg.ReactionEmoji{Emoticon: "❤️"}); got != "❤️" {
		t.Errorf("emoji reaction = %q, want ❤️", got)
	}
	if got := DecodeDefaultReactionKey(&tg.ReactionCustomEmoji{DocumentID: 7}); got != "custom_7" {
		t.Errorf("custom reaction = %q, want custom_7", got)
	}
}
