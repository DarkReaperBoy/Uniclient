package gui

// powersave_test.go — slice 135 tests-first: power saving actually gates
// the GUI's chat animations (tdesktop's PowerSaving semantics: stickers /
// custom-emoji loops in chats render their first frame with no re-arm
// while the matching flag — or force-all — is on).

import (
	"testing"
)

func TestPowerSavingBlocks(t *testing.T) {
	const (
		stickersChat = 1 << 1 // tdesktop PowerSaving::kStickersChat
		emojiChat    = 1 << 3 // tdesktop PowerSaving::kEmojiChat
	)
	cases := []struct {
		flags    int
		forceAll bool
		stickers bool // want: stickers/dice animations blocked
		emoji    bool // want: inline custom-emoji animations blocked
	}{
		{0, false, false, false},
		{stickersChat, false, true, false},
		{emojiChat, false, false, true},
		{stickersChat | emojiChat, false, true, true},
		{0, true, true, true}, // force-all: every class treated as enabled
		{stickersChat, true, true, true},
	}
	for _, c := range cases {
		if got := powerSavingBlocks(c.flags, c.forceAll, psClassStickers); got != c.stickers {
			t.Errorf("powerSavingBlocks(%d, %v, stickers) = %v, want %v", c.flags, c.forceAll, got, c.stickers)
		}
		if got := powerSavingBlocks(c.flags, c.forceAll, psClassEmoji); got != c.emoji {
			t.Errorf("powerSavingBlocks(%d, %v, emoji) = %v, want %v", c.flags, c.forceAll, got, c.emoji)
		}
	}
}
