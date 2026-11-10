package tests

import (
	"testing"

	. "uniclient/ui/dialogs"
	. "uniclient/ui/tokens"
)

func sectionList() List {
	return List{
		Rows:      []Entry{{Name: "Alice", ChatType: ChatPlain}},
		Global:    []Entry{{Name: "Bob", ChatType: ChatPlain}, {Name: "Carol", ChatType: ChatPlain}},
		GlobalBar: true,
	}
}

func TestListSectionHeights(t *testing.T) {
	l := sectionList()
	if got := l.Height(380); got != DialogsRowHeight+SearchedBarHeight+2*DialogsRowHeight {
		t.Fatalf("sectioned height = %d, want %d", got, DialogsRowHeight+SearchedBarHeight+2*DialogsRowHeight)
	}
	l.GlobalBar = false
	if got := l.Height(380); got != DialogsRowHeight {
		t.Fatalf("bare height = %d, want %d", got, DialogsRowHeight)
	}
	l.GlobalBar = true
	l.Global = nil
	if got := l.Height(380); got != DialogsRowHeight+SearchedBarHeight {
		t.Fatalf("bar-only height = %d, want %d (the loading bar occupies the slot)", got, DialogsRowHeight+SearchedBarHeight)
	}
}

func TestListSectionRowAt(t *testing.T) {
	l := sectionList()
	barTop := DialogsRowHeight
	globalTop := barTop + SearchedBarHeight
	cases := []struct {
		y    int
		want int
	}{
		{0, 0},
		{barTop - 1, 0},
		{barTop, -1},
		{globalTop, 1},
		{globalTop + DialogsRowHeight, 2},
		{globalTop + 2*DialogsRowHeight - 1, 2},
		{globalTop + 2*DialogsRowHeight, -1},
	}
	for _, c := range cases {
		if got := l.RowAt(c.y, 380); got != c.want {
			t.Fatalf("RowAt(%d) = %d, want %d", c.y, got, c.want)
		}
	}
}

func TestListEntryAtAndRowCount(t *testing.T) {
	l := sectionList()
	if l.RowCount() != 3 {
		t.Fatalf("RowCount = %d, want 3 (local + global stitched)", l.RowCount())
	}
	if l.EntryAt(0).Name != "Alice" || l.EntryAt(1).Name != "Bob" || l.EntryAt(2).Name != "Carol" {
		t.Fatalf("EntryAt stitch wrong: %q %q %q", l.EntryAt(0).Name, l.EntryAt(1).Name, l.EntryAt(2).Name)
	}
	if l.EntryAt(3).Name != "" {
		t.Fatalf("out-of-range EntryAt must be the zero entry")
	}
}

func TestPaneCarriesSectionGeometry(t *testing.T) {
	l := sectionList()
	l.BarText = "Global search results"
	p := l.Pane(Viewport{Top: 0, Height: 400}, 380)
	if !p.GlobalBar {
		t.Fatalf("pane must carry the section bar")
	}
	if p.GlobalBarY != DialogsRowHeight {
		t.Fatalf("pane bar Y = %d, want %d (right under the local rows)", p.GlobalBarY, DialogsRowHeight)
	}
	if p.BarText != "Global search results" {
		t.Fatalf("pane bar text = %q", p.BarText)
	}
	if len(p.Global) != 2 || p.Global[0].Name != "Bob" || p.Global[1].Name != "Carol" {
		t.Fatalf("pane global rows = %+v", p.Global)
	}
	if len(p.GlobalRowYs) != 2 || p.GlobalRowYs[0] != DialogsRowHeight+SearchedBarHeight ||
		p.GlobalRowYs[1] != DialogsRowHeight+SearchedBarHeight+DialogsRowHeight {
		t.Fatalf("pane global row Ys = %v", p.GlobalRowYs)
	}
}

func TestPaneSectionPartialVisibility(t *testing.T) {
	l := sectionList()
	p := l.Pane(Viewport{Top: DialogsRowHeight + SearchedBarHeight + DialogsRowHeight, Height: 200}, 380)
	if len(p.Global) != 1 || p.Global[0].Name != "Carol" {
		t.Fatalf("scrolled pane global rows = %+v, want only Carol", p.Global)
	}
	if len(p.GlobalRowYs) != 1 || p.GlobalRowYs[0] != DialogsRowHeight+SearchedBarHeight+DialogsRowHeight {
		t.Fatalf("scrolled pane global row Y = %v", p.GlobalRowYs)
	}
	if !p.GlobalBar {
		t.Fatalf("the bar flag rides the pane even when scrolled past it")
	}
}

func TestPaneNoSectionWithoutBar(t *testing.T) {
	l := sectionList()
	l.GlobalBar = false
	p := l.Pane(Viewport{Top: 0, Height: 400}, 380)
	if p.GlobalBar || p.Global != nil || p.GlobalRowYs != nil {
		t.Fatalf("no-bar list must project no section: %+v", p)
	}
}

func TestListSectionScrollbarCoversGlobalRows(t *testing.T) {
	l := sectionList()
	v := Viewport{Top: 0, Height: 100}
	if got := l.MaxOffset(380, 100); got != DialogsRowHeight+SearchedBarHeight+2*DialogsRowHeight-100 {
		t.Fatalf("MaxOffset = %d, want the sectioned content height minus the view", got)
	}
	thumb := l.ScrollbarThumb(v, 380, 100)
	if thumb.Hidden {
		t.Fatalf("the thumb must show over sectioned content")
	}
}
