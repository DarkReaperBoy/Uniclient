package gui

import (
	"testing"

	"uniclient/engine"
)

// Sidebar row badges (AyuGram parity slice 68): title-adjacent
// verified/premium/scam/fake badges and the trailing @-mention / unread
// badge stack. Pure derivations locked here.

func TestRowTitleBadgesKinds(t *testing.T) {
	c := engine.ChatInfo{Title: "x"}
	if b := rowTitleBadges(c); len(b) != 0 {
		t.Fatalf("plain chat: no badges, got %v", kindsOf(b))
	}
	c.IsVerified = true
	b := rowTitleBadges(c)
	if len(b) != 1 || b[0].label != "verified" {
		t.Fatalf("verified: got %v", kindsOf(b))
	}
	c.IsPremium = true
	b = rowTitleBadges(c)
	if len(b) != 2 || b[0].label != "verified" || b[1].label != "premium" {
		t.Fatalf("verified+premium order: got %v", kindsOf(b))
	}
}

func TestRowTitleBadgesScamFakeExclusive(t *testing.T) {
	// Telegram renders one warning tag; scam wins when both flags are set.
	c := engine.ChatInfo{IsScam: true, IsFake: true}
	b := rowTitleBadges(c)
	if len(b) != 1 || b[0].label != "scam" {
		t.Fatalf("scam+fake: expected single scam tag, got %v", kindsOf(b))
	}
	c = engine.ChatInfo{IsFake: true}
	b = rowTitleBadges(c)
	if len(b) != 1 || b[0].label != "fake" {
		t.Fatalf("fake: got %v", kindsOf(b))
	}
}

func TestRowTitleBadgesIcons(t *testing.T) {
	// Verified and premium render as icons; scam/fake as text tags.
	c := engine.ChatInfo{IsVerified: true, IsPremium: true}
	for _, b := range rowTitleBadges(c) {
		if b.icon == nil {
			t.Errorf("kind %s must use an icon", b.label)
		}
	}
	c = engine.ChatInfo{IsScam: true}
	if b := rowTitleBadges(c); b[0].icon != nil {
		t.Errorf("scam must render as a text tag, not an icon")
	}
}

func kindsOf(b []hdrBadge) []string {
	out := make([]string, len(b))
	for i, x := range b {
		out[i] = x.label
	}
	return out
}

func TestTrailingRowBadges(t *testing.T) {
	c := engine.ChatInfo{}
	if b := trailingRowBadges(c); len(b) != 0 {
		t.Fatalf("plain chat: no trailing badges, got %v", b)
	}
	c.UnreadMentionCount = 2
	b := trailingRowBadges(c)
	if len(b) != 1 || b[0] != rowBadgeMention {
		t.Fatalf("mentions only: got %v", b)
	}
	c.UnreadCount = 7
	b = trailingRowBadges(c)
	if len(b) != 2 || b[0] != rowBadgeMention || b[1] != rowBadgeCount {
		t.Fatalf("mention must precede the unread count, got %v", b)
	}
	c.UnreadCount = 0
	c.UnreadMark = true
	b = trailingRowBadges(c)
	if len(b) != 2 || b[1] != rowBadgeMark {
		t.Fatalf("unread mark keeps its slot, got %v", b)
	}
}

func TestTrailingRowBadgesReactionCount(t *testing.T) {
	c := engine.ChatInfo{UnreadReactionCount: 3}
	b := trailingRowBadges(c)
	if len(b) != 1 || b[0] != rowBadgeReactions {
		t.Fatalf("reactions only: got %v", b)
	}
	c.UnreadCount = 1
	c.UnreadMentionCount = 1
	b = trailingRowBadges(c)
	if len(b) != 3 {
		t.Fatalf("mention+reactions+count expected, got %v", b)
	}
	if b[0] != rowBadgeMention || b[1] != rowBadgeReactions || b[2] != rowBadgeCount {
		t.Fatalf("order must be mention, reactions, count; got %v", b)
	}
}
