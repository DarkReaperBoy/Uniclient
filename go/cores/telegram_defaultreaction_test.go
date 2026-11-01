package cores

import (
	"testing"

	"github.com/gotd/td/tg"
)

func TestReactionClassForKey(t *testing.T) {
	if r, ok := reactionClassForKey("👍").(*tg.ReactionEmoji); !ok || r.Emoticon != "👍" {
		t.Errorf("plain emoji key should decode to ReactionEmoji, got %T", reactionClassForKey("👍"))
	}
	if r, ok := reactionClassForKey("custom_9").(*tg.ReactionCustomEmoji); !ok || r.DocumentID != 9 {
		t.Errorf("custom_9 should decode to ReactionCustomEmoji{9}, got %T", reactionClassForKey("custom_9"))
	}
	if r, ok := reactionClassForKey("custom_bogus").(*tg.ReactionEmoji); !ok || r.Emoticon != "custom_bogus" {
		t.Errorf("malformed custom key should fall back to emoji, got %T", reactionClassForKey("custom_bogus"))
	}
}

func TestDecodeDefaultReactionKey(t *testing.T) {
	if got := decodeDefaultReactionKey(nil); got != "" {
		t.Errorf("nil reaction class = %q, want \"\"", got)
	}
	if got := decodeDefaultReactionKey(&tg.ReactionEmoji{Emoticon: "❤️"}); got != "❤️" {
		t.Errorf("emoji reaction = %q, want ❤️", got)
	}
	if got := decodeDefaultReactionKey(&tg.ReactionCustomEmoji{DocumentID: 7}); got != "custom_7" {
		t.Errorf("custom reaction = %q, want custom_7", got)
	}
}
