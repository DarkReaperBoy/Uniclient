package gui

import (
	"testing"
)

func TestPowerSavingBlocks(t *testing.T) {
	const (
		stickersChat = 1 << 1
		emojiChat    = 1 << 3
	)
	cases := []struct {
		flags    int
		forceAll bool
		stickers bool
		emoji    bool
	}{
		{0, false, false, false},
		{stickersChat, false, true, false},
		{emojiChat, false, false, true},
		{stickersChat | emojiChat, false, true, true},
		{0, true, true, true},
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
