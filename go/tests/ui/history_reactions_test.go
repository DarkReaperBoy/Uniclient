package tests

import (
	"testing"

	"uniclient/ui/history"
)

func TestReactionsShown(t *testing.T) {
	if (history.List{}).ReactionsShown() {
		t.Fatalf("empty list: shown, want hidden")
	}
	if l := downList(40); l.ReactionsShown() {
		t.Fatalf("no reactions: shown, want hidden")
	}
	items := downItems(40)
	items[7].UnreadReaction = true
	l := history.List{Items: items, Heights: downHeights(40)}
	if !l.ReactionsShown() {
		t.Fatalf("one reaction: hidden, want shown")
	}
	items[12].UnreadReaction = true
	two := history.List{Items: items, Heights: downHeights(40)}
	if !two.ReactionsShown() {
		t.Fatalf("two reactions: hidden, want shown")
	}
	if !two.MentionsShown() && items[12].UnreadMention {
		t.Fatalf("mention flag untouched by reaction flag, want independence")
	}
}

func TestReactionsJumpTop(t *testing.T) {
	if top := downList(40).ReactionsJumpTop(history.Viewport{Height: 120}); top != -1 {
		t.Fatalf("no reactions jump = %d, want -1 (no-op)", top)
	}
	items := downItems(40)
	items[7].UnreadReaction = true
	l := history.List{Items: items, Heights: downHeights(40)}
	if top := l.ReactionsJumpTop(history.Viewport{Top: 1880, Height: 120}); top != 350 {
		t.Fatalf("reaction jump = %d, want 350 (row 7 top — oldest unread reaction)", top)
	}
	late := downItems(40)
	late[39].UnreadReaction = true
	u := history.List{Items: late, Heights: downHeights(40)}
	if top := u.ReactionsJumpTop(history.Viewport{Top: 0, Height: 120}); top != 1880 {
		t.Fatalf("clamped reaction jump = %d, want 1880 (max)", top)
	}
}

func TestReactionsButtonGeometry(t *testing.T) {
	g := history.ReactionsButtonGeometry(800, 300, 1, 0, 0)
	if g.Left != 736 || g.Top != 228 || g.Width != 52 || g.Height != 62 {
		t.Fatalf("shown geometry over hidden stack = %+v, want {736 228 52 62}", g)
	}
	overDown := history.ReactionsButtonGeometry(800, 300, 1, 1, 0)
	if overDown.Left != 736 || overDown.Top != 162 {
		t.Fatalf("stacked over down = %+v, want left 736 top 162", overDown)
	}
	full := history.ReactionsButtonGeometry(800, 300, 1, 1, 1)
	if full.Left != 736 || full.Top != 96 {
		t.Fatalf("full stack = %+v, want left 736 top 96 (two 66px shifts above base 228)", full)
	}
	if full.Top+full.Height != 158 {
		t.Fatalf("full-stack bottom = %d, want 158 (4px skip above mentions top 162)",
			full.Top+full.Height)
	}
	hidden := history.ReactionsButtonGeometry(800, 300, 0, 1, 1)
	if hidden.Left != 800 {
		t.Fatalf("hidden geometry left = %d, want 800 (slid off the right edge)", hidden.Left)
	}
	mid := history.ReactionsButtonGeometry(800, 300, 0.5, 0.5, 0.5)
	if mid.Left != 768 {
		t.Fatalf("mid-slide left = %d, want 768", mid.Left)
	}
	if mid.Top != 162 {
		t.Fatalf("mid-stack top = %d, want 162 (base 228 minus two half-shifts of 33)", mid.Top)
	}
}

func TestReactionsButtonGeometryNeverOverlapsMentions(t *testing.T) {
	for _, downP := range []float32{0, 1} {
		for _, mentionsP := range []float32{0, 1} {
			r := history.ReactionsButtonGeometry(800, 300, 1, downP, mentionsP)
			m := history.MentionsButtonGeometry(800, 300, mentionsP, downP)
			if r.Left < m.Left+m.Width && m.Left < r.Left+r.Width &&
				r.Top < m.Top+m.Height && m.Top < r.Top+r.Height {
				t.Fatalf("settled downP %v mentionsP %v: reactions %+v intersects mentions %+v",
					downP, mentionsP, r, m)
			}
		}
	}
	full := history.ReactionsButtonGeometry(800, 300, 1, 1, 1)
	m := history.MentionsButtonGeometry(800, 300, 1, 1)
	if full.Top+full.Height != m.Top-4 {
		t.Fatalf("settled gap = %d, want 4 above mentions (updatePositions skip)",
			m.Top-(full.Top+full.Height))
	}
}

func TestReactionsButtonHit(t *testing.T) {
	if !history.ReactionsButtonHit(800, 300, 1, 0, 0, 750, 250) {
		t.Fatalf("inside shown box: miss, want hit")
	}
	if history.ReactionsButtonHit(800, 300, 1, 0, 0, 735, 250) {
		t.Fatalf("left of box: hit, want miss")
	}
	if history.ReactionsButtonHit(800, 300, 1, 0, 0, 750, 291) {
		t.Fatalf("below box: hit, want miss")
	}
	if history.ReactionsButtonHit(800, 300, 0, 1, 1, 750, 120) {
		t.Fatalf("hidden box (slid off right): hit, want miss")
	}
	if !history.ReactionsButtonHit(800, 300, 0.5, 0, 0, 780, 250) {
		t.Fatalf("mid-slide box: miss, want hit")
	}
	if !history.ReactionsButtonHit(800, 300, 1, 1, 1, 750, 120) {
		t.Fatalf("full-stack box: miss, want hit")
	}
}
