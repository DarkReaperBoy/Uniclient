package tests

import (
	"testing"

	"uniclient/ui/history"
	"uniclient/ui/tokens"
)

func downItems(n int) []history.Item {
	items := make([]history.Item, n)
	for i := range items {
		items[i] = history.Item{
			Kind:     history.ItemMessage,
			Text:     "m",
			TimeText: "10:00",
			DateText: "Jan 1",
		}
	}
	return items
}

func downHeights(n int) []int {
	hs := make([]int, n)
	for i := range hs {
		hs[i] = 50
	}
	return hs
}

func downList(n int) history.List {
	return history.List{Items: downItems(n), Heights: downHeights(n)}
}

func TestDownButtonTokens(t *testing.T) {
	if tokens.HistoryToDownPositionX != 12 || tokens.HistoryToDownPositionY != 10 {
		t.Fatalf("position drifted: (%d, %d), want (12, 10) — historyToDownPosition",
			tokens.HistoryToDownPositionX, tokens.HistoryToDownPositionY)
	}
	if tokens.HistoryToDownWidth != 52 || tokens.HistoryToDownHeight != 62 {
		t.Fatalf("box drifted: %dx%d, want 52x62 — historyToDown",
			tokens.HistoryToDownWidth, tokens.HistoryToDownHeight)
	}
	if tokens.HistoryToDownCircleSize != 42 || tokens.HistoryToDownCircleX != 5 || tokens.HistoryToDownCircleY != 15 {
		t.Fatalf("circle drifted: %d@(%d,%d), want 42@(5,15) — rippleAreaPosition/Size + history_down_shadow mask",
			tokens.HistoryToDownCircleSize, tokens.HistoryToDownCircleX, tokens.HistoryToDownCircleY)
	}
	if tokens.HistoryToDownArrowWidth != 19 || tokens.HistoryToDownArrowHeight != 10 {
		t.Fatalf("arrow drifted: %dx%d, want 19x10 — history_down_arrow@2x bbox",
			tokens.HistoryToDownArrowWidth, tokens.HistoryToDownArrowHeight)
	}
	if tokens.HistoryToDownArrowStroke != 3 {
		t.Fatalf("arrow stroke drifted: %d, want 3 — history_down_arrow@2x leg thickness",
			tokens.HistoryToDownArrowStroke)
	}
	if tokens.HistoryToDownArrowCenterX != 26 || tokens.HistoryToDownArrowCenterY != 38 {
		t.Fatalf("arrow center drifted: (%d, %d), want (26, 38) — arrow bbox in button coords",
			tokens.HistoryToDownArrowCenterX, tokens.HistoryToDownArrowCenterY)
	}
	if tokens.HistoryToDownShownAfter != 480 {
		t.Fatalf("shown-after drifted: %d, want 480 — historyToDownShownAfter",
			tokens.HistoryToDownShownAfter)
	}
	if tokens.HistoryToDownDurationMs != 150 {
		t.Fatalf("duration drifted: %d, want 150 — historyToDownDuration",
			tokens.HistoryToDownDurationMs)
	}
}

func TestDownShown(t *testing.T) {
	l := downList(40)
	max := l.MaxOffset(history.Viewport{Height: 120})
	if max != 1880 {
		t.Fatalf("max = %d, want 1880", max)
	}
	if l.DownShown(history.Viewport{Top: 1880, Height: 120}) {
		t.Fatalf("at bottom: shown, want hidden")
	}
	if l.DownShown(history.Viewport{Top: 1400, Height: 120}) {
		t.Fatalf("boundary 1400+480 == max: shown, want hidden (strict less)")
	}
	if !l.DownShown(history.Viewport{Top: 1399, Height: 120}) {
		t.Fatalf("boundary 1399+480 < max: hidden, want shown")
	}
	if !l.DownShown(history.Viewport{Top: 0, Height: 120}) {
		t.Fatalf("scrolled to top: hidden, want shown")
	}
	if (history.List{}).DownShown(history.Viewport{Top: 0, Height: 120}) {
		t.Fatalf("empty list: shown, want hidden")
	}
	unmeasured := history.List{Items: downItems(4)}
	if unmeasured.DownShown(history.Viewport{Top: 0, Height: 120}) {
		t.Fatalf("unmeasured list: shown, want hidden")
	}
}

func TestDownShownUnreadBelowFold(t *testing.T) {
	items := downItems(40)
	items[32].UnreadBar = "Unread messages"
	l := history.List{Items: items, Heights: downHeights(40)}
	if !l.DownShown(history.Viewport{Top: 1450, Height: 120}) {
		t.Fatalf("unread below fold (1600 >= 1570) within 480px of bottom: hidden, want shown")
	}
	if l.DownShown(history.Viewport{Top: 1500, Height: 120}) {
		t.Fatalf("unread visible (1600 < fold 1620): shown, want hidden")
	}
	if l.DownShown(history.Viewport{Top: 1880, Height: 120}) {
		t.Fatalf("unread above viewport at bottom: shown, want hidden")
	}
	early := downItems(40)
	early[5].UnreadBar = "Unread messages"
	le := history.List{Items: early, Heights: downHeights(40)}
	if le.DownShown(history.Viewport{Top: 1880, Height: 120}) {
		t.Fatalf("read-past unread at bottom: shown, want hidden")
	}
}

func TestDownJumpTop(t *testing.T) {
	l := downList(40)
	if top := l.DownJumpTop(history.Viewport{Top: 0, Height: 120}); top != 1880 {
		t.Fatalf("no unread jump = %d, want 1880 (bottom)", top)
	}
	items := downItems(40)
	items[35].UnreadBar = "Unread messages"
	u := history.List{Items: items, Heights: downHeights(40)}
	if top := u.DownJumpTop(history.Viewport{Top: 100, Height: 120}); top != 1750 {
		t.Fatalf("unread jump = %d, want 1750 (row 35 top)", top)
	}
	late := downItems(40)
	late[39].UnreadBar = "Unread messages"
	ul := history.List{Items: late, Heights: downHeights(40)}
	if top := ul.DownJumpTop(history.Viewport{Top: 1880, Height: 120}); top != 1880 {
		t.Fatalf("clamped unread jump = %d, want 1880 (max)", top)
	}
}

func TestDownButtonGeometry(t *testing.T) {
	g := history.DownButtonGeometry(800, 120, 1)
	if g.Left != 736 || g.Top != 48 || g.Width != 52 || g.Height != 62 {
		t.Fatalf("shown geometry = %+v, want {736 48 52 62}", g)
	}
	if g := history.DownButtonGeometry(800, 120, 0); g.Top != 120 {
		t.Fatalf("hidden geometry top = %d, want 120 (below pane)", g.Top)
	}
	if g := history.DownButtonGeometry(800, 120, 0.5); g.Top != 84 {
		t.Fatalf("mid geometry top = %d, want 84", g.Top)
	}
	if !history.DownButtonHit(800, 120, 1, 750, 80) {
		t.Fatalf("inside shown box: miss, want hit")
	}
	if history.DownButtonHit(800, 120, 1, 735, 80) {
		t.Fatalf("left of box: hit, want miss")
	}
	if history.DownButtonHit(800, 120, 1, 750, 111) {
		t.Fatalf("below box: hit, want miss")
	}
	if history.DownButtonHit(800, 120, 0, 750, 80) {
		t.Fatalf("hidden box: hit, want miss")
	}
	if !history.DownButtonHit(800, 120, 0.5, 750, 100) {
		t.Fatalf("mid-slide box: miss, want hit")
	}
}
