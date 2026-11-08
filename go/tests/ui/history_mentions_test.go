package tests

import (
	"testing"

	"uniclient/ui/history"
	"uniclient/ui/tokens"
)

func TestMentionsTokens(t *testing.T) {
	if tokens.HistoryUnreadThingsSkip != 4 {
		t.Fatalf("unread-things skip drifted: %d, want 4 — historyUnreadThingsSkip",
			tokens.HistoryUnreadThingsSkip)
	}
}

func TestMentionsShown(t *testing.T) {
	if (history.List{}).MentionsShown() {
		t.Fatalf("empty list: shown, want hidden")
	}
	if l := downList(40); l.MentionsShown() {
		t.Fatalf("no mentions: shown, want hidden")
	}
	items := downItems(40)
	items[12].UnreadMention = true
	one := history.List{Items: items, Heights: downHeights(40)}
	if !one.MentionsShown() {
		t.Fatalf("one mention: hidden, want shown")
	}
	items[39].UnreadMention = true
	two := history.List{Items: items, Heights: downHeights(40)}
	if !two.MentionsShown() {
		t.Fatalf("two mentions: hidden, want shown")
	}
	unmeasured := history.List{Items: items}
	if !unmeasured.MentionsShown() {
		t.Fatalf("unmeasured list with mentions: hidden, want shown — visibility is data-driven, not height-driven")
	}
}

func TestMentionsJumpTop(t *testing.T) {
	if top := downList(40).MentionsJumpTop(history.Viewport{Height: 120}); top != -1 {
		t.Fatalf("no mentions jump = %d, want -1 (no-op)", top)
	}
	items := downItems(40)
	items[12].UnreadMention = true
	l := history.List{Items: items, Heights: downHeights(40)}
	if top := l.MentionsJumpTop(history.Viewport{Top: 1880, Height: 120}); top != 600 {
		t.Fatalf("mention jump = %d, want 600 (row 12 top — oldest unread mention)", top)
	}
	late := downItems(40)
	late[39].UnreadMention = true
	u := history.List{Items: late, Heights: downHeights(40)}
	if top := u.MentionsJumpTop(history.Viewport{Top: 0, Height: 120}); top != 1880 {
		t.Fatalf("clamped mention jump = %d, want 1880 (max)", top)
	}
}

func TestMentionsButtonGeometry(t *testing.T) {
	g := history.MentionsButtonGeometry(800, 300, 1, 0)
	if g.Left != 736 || g.Top != 228 || g.Width != 52 || g.Height != 62 {
		t.Fatalf("shown geometry over hidden down = %+v, want {736 228 52 62}", g)
	}
	stacked := history.MentionsButtonGeometry(800, 300, 1, 1)
	if stacked.Left != 736 || stacked.Top != 162 {
		t.Fatalf("stacked geometry = %+v, want left 736 top 162 (down 62 + skip 4 above down top 228)",
			stacked)
	}
	if stacked.Top+stacked.Height != 224 {
		t.Fatalf("stacked bottom = %d, want 224 (4px skip above down top 228)",
			stacked.Top+stacked.Height)
	}
	hidden := history.MentionsButtonGeometry(800, 300, 0, 0)
	if hidden.Left != 800 {
		t.Fatalf("hidden geometry left = %d, want 800 (slid off the right edge)", hidden.Left)
	}
	mid := history.MentionsButtonGeometry(800, 300, 0.5, 0.5)
	if mid.Left != 768 {
		t.Fatalf("mid-slide left = %d, want 768 (half of the 64px travel)", mid.Left)
	}
	if mid.Top != 195 {
		t.Fatalf("mid-stack top = %d, want 195 (half of the 66px shift)", mid.Top)
	}
}

func TestMentionsButtonGeometryNeverOverlapsDown(t *testing.T) {
	for _, downP := range []float32{0, 0.25, 0.5, 0.75, 1} {
		m := history.MentionsButtonGeometry(800, 300, 1, downP)
		d := history.DownButtonGeometry(800, 300, downP)
		if m.Top+m.Height > d.Top {
			t.Fatalf("downP %v: mentions bottom %d overlaps down top %d",
				downP, m.Top+m.Height, d.Top)
		}
	}
}

func TestMentionsButtonHit(t *testing.T) {
	if !history.MentionsButtonHit(800, 300, 1, 0, 750, 250) {
		t.Fatalf("inside shown box: miss, want hit")
	}
	if history.MentionsButtonHit(800, 300, 1, 0, 735, 250) {
		t.Fatalf("left of box: hit, want miss")
	}
	if history.MentionsButtonHit(800, 300, 1, 0, 750, 291) {
		t.Fatalf("below box: hit, want miss")
	}
	if history.MentionsButtonHit(800, 300, 0, 0, 750, 250) {
		t.Fatalf("hidden box (slid off right): hit, want miss")
	}
	if !history.MentionsButtonHit(800, 300, 0.5, 0, 780, 250) {
		t.Fatalf("mid-slide box: miss, want hit")
	}
	if !history.MentionsButtonHit(800, 300, 1, 1, 750, 180) {
		t.Fatalf("stacked box: miss, want hit")
	}
}
