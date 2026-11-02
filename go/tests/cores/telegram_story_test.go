package tests

import (
	"testing"
	. "uniclient/cores"

	"github.com/gotd/td/tg"
)

func TestStoryReactionEmoticon(t *testing.T) {
	if got := StoryReactionEmoticon(&tg.ReactionEmoji{Emoticon: "🔥"}); got != "🔥" {
		t.Errorf("emoji reaction = %q, want 🔥", got)
	}
	if got := StoryReactionEmoticon(&tg.ReactionCustomEmoji{DocumentID: 5}); got != "" {
		t.Errorf("custom emoji reaction must map to empty (not representable), got %q", got)
	}
	if got := StoryReactionEmoticon(nil); got != "" {
		t.Errorf("nil reaction = %q, want empty", got)
	}
}
