package tests

import (
	"testing"

	"uniclient/ui/dialogs"
)

func paneFixture() dialogs.List {
	return dialogs.List{Selected: -1, Rows: []dialogs.Entry{
		{Name: "plain"},
		{Name: "tagged", Tagged: true},
		{Name: "forum", Forum: true},
		{Name: "taggedforum", Tagged: true, Forum: true},
	}}
}

func TestPaneVisibleWindow(t *testing.T) {
	l := paneFixture()
	const wide = 400
	p := l.Pane(dialogs.Viewport{Top: 0, Height: 100}, wide)
	if p.First != 0 || len(p.Rows) != 2 || len(p.RowYs) != 2 {
		t.Fatalf("pane at top: first %d, %d rows, %d ys — want 0, 2, 2 (row 2 top 134 >= till 100)",
			p.First, len(p.Rows), len(p.RowYs))
	}
	if p.RowYs[0] != 0 || p.RowYs[1] != 62 {
		t.Fatalf("pane row ys = %v, want [0 62] (absolute)", p.RowYs)
	}
	if p.Selected != -1 {
		t.Fatalf("pane selected = %d, want -1 passthrough", p.Selected)
	}
	if p.Thumb.Hidden || p.Thumb.Y != 3 || p.Thumb.H != 40 {
		t.Fatalf("pane thumb = (%d, %d, hidden %v), want (3, 40) — track 100, barWanted 30 lifted to min 40",
			p.Thumb.Y, p.Thumb.H, p.Thumb.Hidden)
	}
	p = l.Pane(dialogs.Viewport{Top: 134, Height: 100}, wide)
	if p.First != 2 || len(p.Rows) != 2 {
		t.Fatalf("pane at 134: first %d, %d rows — want 2, 2", p.First, len(p.Rows))
	}
	if p.RowYs[0] != 134 || p.RowYs[1] != 214 {
		t.Fatalf("pane row ys = %v, want [134 214]", p.RowYs)
	}
	l.Selected = 3
	p = l.Pane(dialogs.Viewport{Top: 134, Height: 100}, wide)
	if p.Selected != 3 {
		t.Fatalf("pane selected passthrough = %d, want 3", p.Selected)
	}
}

func TestPaneEmptyAndNarrow(t *testing.T) {
	empty := dialogs.List{}
	p := empty.Pane(dialogs.Viewport{Top: 0, Height: 100}, 400)
	if p.First != 0 || len(p.Rows) != 0 || len(p.RowYs) != 0 || !p.Thumb.Hidden {
		t.Fatalf("empty pane = first %d, %d rows, thumb %+v — want zeroed + hidden",
			p.First, len(p.Rows), p.Thumb)
	}
	narrow := paneFixture()
	p = narrow.Pane(dialogs.Viewport{Top: 62, Height: 124}, 100)
	if p.First != 1 || len(p.Rows) != 2 {
		t.Fatalf("narrow pane: first %d, %d rows — want 1, 2 (row 3 top 186 not < till 186)",
			p.First, len(p.Rows))
	}
	if p.RowYs[0] != 62 || p.RowYs[1] != 124 {
		t.Fatalf("narrow pane row ys = %v, want [62 124]", p.RowYs)
	}
	if p.View.Top != 62 || p.View.Height != 124 || p.Width != 100 {
		t.Fatalf("pane must echo viewport and width: %+v", p.View)
	}
}
