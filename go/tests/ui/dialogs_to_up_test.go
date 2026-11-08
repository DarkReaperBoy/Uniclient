package tests

import (
	"testing"

	"uniclient/ui/dialogs"
	"uniclient/ui/tokens"
)

func toUpRows(n int) []dialogs.Entry {
	rows := make([]dialogs.Entry, n)
	for i := range rows {
		rows[i] = dialogs.Entry{Name: "A", Date: "12:30"}
	}
	return rows
}

func toUpList(n int) dialogs.List {
	return dialogs.List{Rows: toUpRows(n)}
}

func TestToUpTokens(t *testing.T) {
	if tokens.DialogsToUpShownAfter != tokens.HistoryToDownShownAfter/2 {
		t.Fatalf("shown-after not derived: %d, want historyToDownShownAfter/2",
			tokens.DialogsToUpShownAfter)
	}
	if tokens.DialogsToUpShownAfter != 240 {
		t.Fatalf("shown-after drifted: %d, want 240", tokens.DialogsToUpShownAfter)
	}
	if tokens.DialogsToUpTravel != tokens.HistoryToDownHeight+2 {
		t.Fatalf("travel not derived: %d, want height + connectingMargin.top 2",
			tokens.DialogsToUpTravel)
	}
	if tokens.DialogsToUpTravel != 64 {
		t.Fatalf("travel drifted: %d, want 64", tokens.DialogsToUpTravel)
	}
	if tokens.DialogsToUpArrowCenterY != tokens.HistoryToDownArrowCenterY+1 {
		t.Fatalf("arrow center y not derived: %d, want flip_vertical + 1px",
			tokens.DialogsToUpArrowCenterY)
	}
	if tokens.DialogsToUpArrowCenterY != 39 {
		t.Fatalf("arrow center y drifted: %d, want 39", tokens.DialogsToUpArrowCenterY)
	}
	if tokens.DialogsRightButtonMinPaneWidth != 260 {
		t.Fatalf("min pane width drifted: %d, want 260 — columnMinimalWidthLeft",
			tokens.DialogsRightButtonMinPaneWidth)
	}
}

func TestToUpShown(t *testing.T) {
	l := toUpList(60)
	v := dialogs.Viewport{Height: 400}
	wide := 300
	max := l.MaxOffset(wide, v.Height)
	if max <= 300 {
		t.Fatalf("test data too short: max = %d, want > 300", max)
	}
	if l.ToUpShown(v, wide) {
		t.Fatalf("at top: shown, want hidden")
	}
	if !l.ToUpShown(dialogs.Viewport{Top: 241, Height: 400}, wide) {
		t.Fatalf("241 > 240 and below max: hidden, want shown")
	}
	if l.ToUpShown(dialogs.Viewport{Top: 240, Height: 400}, wide) {
		t.Fatalf("240 is not > 240: shown, want hidden")
	}
	if l.ToUpShown(dialogs.Viewport{Top: max, Height: 400}, wide) {
		t.Fatalf("at bottom (top == max): shown, want hidden")
	}
	if l.ToUpShown(dialogs.Viewport{Top: 300, Height: 400}, 259) {
		t.Fatalf("narrow pane: shown, want hidden")
	}
	if !l.ToUpShown(dialogs.Viewport{Top: 300, Height: 400}, 260) {
		t.Fatalf("pane == 260 is not < 260: hidden, want shown")
	}
}

func TestToUpGeometry(t *testing.T) {
	g := dialogs.ToUpGeometry(286, 400, 1)
	if g.X != 286-12-tokens.HistoryToDownWidth || g.Y != 400-tokens.DialogsToUpTravel {
		t.Fatalf("shown geometry = %+v, want x %d y %d",
			g, 286-12-tokens.HistoryToDownWidth, 400-tokens.DialogsToUpTravel)
	}
	if g.W != tokens.HistoryToDownWidth || g.H != tokens.HistoryToDownHeight {
		t.Fatalf("box drifted: %dx%d", g.W, g.H)
	}
	if g := dialogs.ToUpGeometry(286, 400, 0); g.Y != 400 {
		t.Fatalf("hidden y = %d, want 400 (below pane)", g.Y)
	}
	if g := dialogs.ToUpGeometry(286, 400, 0.5); g.Y != 400-tokens.DialogsToUpTravel/2 {
		t.Fatalf("mid y = %d, want %d", g.Y, 400-tokens.DialogsToUpTravel/2)
	}
	if !dialogs.ToUpHit(286, 400, 1, 250, 360) {
		t.Fatalf("inside shown box: miss, want hit")
	}
	if dialogs.ToUpHit(286, 400, 1, 250, 400) {
		t.Fatalf("below box: hit, want miss")
	}
	if dialogs.ToUpHit(286, 400, 0, 250, 360) {
		t.Fatalf("hidden box: hit, want miss")
	}
}
