package tests

import (
	"testing"

	"uniclient/ui/history"
	"uniclient/ui/tokens"
)

func TestComposeBarsDateLaw(t *testing.T) {
	items := []history.Item{
		{Kind: history.ItemMessage, Text: "a", DateText: "5 November"},
		{Kind: history.ItemMessage, Text: "b"},
		{Kind: history.ItemMessage, Text: "c", DateText: "6 November"},
		{Kind: history.ItemService, Text: "carol joined"},
		{Kind: history.ItemMessage, Text: "d", DateText: "7 November", UnreadBar: "Unread messages"},
	}
	bars := history.ComposeBars(items)
	wantDate := []int{32, 0, 32, 0, 32}
	wantUnread := []int{0, 0, 0, 0, 35}
	for i := range items {
		if bars[i].Date != wantDate[i] {
			t.Errorf("bars[%d].Date = %d, want %d", i, bars[i].Date, wantDate[i])
		}
		if bars[i].Unread != wantUnread[i] {
			t.Errorf("bars[%d].Unread = %d, want %d", i, bars[i].Unread, wantUnread[i])
		}
	}
}

func TestComposeBarsPrevDisplayedWalk(t *testing.T) {
	items := []history.Item{
		{Kind: history.ItemMessage, Text: "a", DateText: "5 November"},
		{Kind: history.ItemMessage, Text: "b", Hidden: true, DateText: "6 November"},
		{Kind: history.ItemMessage, Text: "c", Empty: true},
		{Kind: history.ItemMessage, Text: "d", DateText: "5 November"},
		{Kind: history.ItemMessage, Text: "e", DateText: "7 November"},
	}
	bars := history.ComposeBars(items)
	want := []int{32, 0, 0, 0, 32}
	for i := range items {
		if bars[i].Date != want[i] {
			t.Errorf("bars[%d].Date = %d, want %d", i, bars[i].Date, want[i])
		}
	}
}

func TestComposeBarsItemGates(t *testing.T) {
	items := []history.Item{
		{Kind: history.ItemMessage, Text: "a", DateText: "1 January"},
		{Kind: history.ItemMessage, Text: "b", DateText: "1 January", Sponsored: true},
		{Kind: history.ItemMessage, Text: "c", DateText: "1 January"},
		{Kind: history.ItemMessage, Text: "d", DateText: "1 January", HideDisplayDate: true},
		{Kind: history.ItemMessage, Text: "e", DateText: "1 January", Empty: true},
		{Kind: history.ItemMessage, Text: "f", DateText: "1 January", Hidden: true},
		{Kind: history.ItemMessage, Text: "g", DateText: "1 January"},
	}
	bars := history.ComposeBars(items)
	want := []int{32, 0, 0, 0, 0, 0, 32}
	for i := range items {
		if bars[i].Date != want[i] {
			t.Errorf("bars[%d].Date = %d, want %d", i, bars[i].Date, want[i])
		}
	}
}

func TestComposeBarsPrevHideDisplayDate(t *testing.T) {
	items := []history.Item{
		{Kind: history.ItemMessage, Text: "a", DateText: "1 January", HideDisplayDate: true},
		{Kind: history.ItemMessage, Text: "b", DateText: "1 January"},
	}
	bars := history.ComposeBars(items)
	if bars[0].Date != 0 {
		t.Errorf("own hide gate: bars[0].Date = %d, want 0", bars[0].Date)
	}
	if bars[1].Date != 32 {
		t.Errorf("prev hide gate: bars[1].Date = %d, want 32", bars[1].Date)
	}
}

func TestComposeBarsLegacyItems(t *testing.T) {
	items := []history.Item{
		{Kind: history.ItemMessage, Text: "a"},
		{Kind: history.ItemMessage, Text: "b"},
	}
	bars := history.ComposeBars(items)
	if bars[0].Date != 0 || bars[1].Date != 0 {
		t.Fatalf("legacy bars = %+v, want zero dates", bars)
	}
	if bars[0].Unread != 0 || bars[1].Unread != 0 {
		t.Fatalf("legacy bars = %+v, want zero unread", bars)
	}
}

func TestComposeBarsEmpty(t *testing.T) {
	if bars := history.ComposeBars(nil); len(bars) != 0 {
		t.Fatalf("nil items bars len = %d, want 0", len(bars))
	}
}

func TestUnreadBarMetrics(t *testing.T) {
	if got := history.UnreadBarHeight(); got != 35 {
		t.Errorf("UnreadBarHeight() = %d, want 35", got)
	}
	if got := history.UnreadBarMarginTop(); got != 4 {
		t.Errorf("UnreadBarMarginTop() = %d, want 4", got)
	}
	if got := history.UnreadBarWidth(80); got != 104 {
		t.Errorf("UnreadBarWidth(80) = %d, want 104", got)
	}
	if got := history.DateBadgeHeight(tokens.FontMsgService); got != 32 {
		t.Errorf("DateBadgeHeight(13) = %d, want 32", got)
	}
}

func TestDateBadgeGeometry(t *testing.T) {
	g := history.DateBadgeGeometry(0, 320, history.ModeNormal, 100, 13)
	if g.Bubble != (history.Geometry{Left: 98, Top: 10, Width: 124, Height: 20}) {
		t.Errorf("normal bubble = %+v", g.Bubble)
	}
	if g.Text != (history.Geometry{Left: 110, Top: 13, Width: 100, Height: 13}) {
		t.Errorf("normal text = %+v", g.Text)
	}
	g = history.DateBadgeGeometry(40, 1200, history.ModeWide, 100, 13)
	if g.Bubble != (history.Geometry{Left: 209, Top: 50, Width: 124, Height: 20}) {
		t.Errorf("wide bubble = %+v", g.Bubble)
	}
	if g.Text != (history.Geometry{Left: 221, Top: 53, Width: 100, Height: 13}) {
		t.Errorf("wide text = %+v", g.Text)
	}
	g = history.DateBadgeGeometry(0, 200, history.ModeNormal, 181, 13)
	if g.Bubble != (history.Geometry{Left: -2, Top: 10, Width: 205, Height: 20}) {
		t.Errorf("overflow bubble = %+v", g.Bubble)
	}
	if g.Text != (history.Geometry{Left: 10, Top: 13, Width: 181, Height: 13}) {
		t.Errorf("overflow text = %+v", g.Text)
	}
}

func TestUnreadBarGeometry(t *testing.T) {
	g := history.UnreadBarGeometry(0, 320, history.ModeNormal, 80, 13)
	if g.Pill != (history.Geometry{Left: 108, Top: 4, Width: 104, Height: 31}) {
		t.Errorf("normal pill = %+v", g.Pill)
	}
	if g.Radius != 15.5 {
		t.Errorf("radius = %v, want 15.5", g.Radius)
	}
	if g.Text != (history.Geometry{Left: 120, Top: 13, Width: 80, Height: 13}) {
		t.Errorf("normal text = %+v", g.Text)
	}
	g = history.UnreadBarGeometry(32, 320, history.ModeNormal, 80, 13)
	if g.Pill != (history.Geometry{Left: 108, Top: 36, Width: 104, Height: 31}) {
		t.Errorf("stacked pill = %+v", g.Pill)
	}
	if g.Text != (history.Geometry{Left: 120, Top: 45, Width: 80, Height: 13}) {
		t.Errorf("stacked text = %+v", g.Text)
	}
	g = history.UnreadBarGeometry(0, 1200, history.ModeWide, 80, 13)
	if g.Pill != (history.Geometry{Left: 219, Top: 4, Width: 104, Height: 31}) {
		t.Errorf("wide pill = %+v", g.Pill)
	}
	if g.Text != (history.Geometry{Left: 231, Top: 13, Width: 80, Height: 13}) {
		t.Errorf("wide text = %+v", g.Text)
	}
	g = history.UnreadBarGeometry(0, 320, history.ModeNormal, 600, 13)
	if g.Pill != (history.Geometry{Left: -152, Top: 4, Width: 624, Height: 31}) {
		t.Errorf("overflow pill = %+v", g.Pill)
	}
	if g.Text != (history.Geometry{Left: -140, Top: 13, Width: 600, Height: 13}) {
		t.Errorf("overflow text = %+v", g.Text)
	}
}

func TestChatPaneBars(t *testing.T) {
	l := history.List{
		Items: []history.Item{
			{Kind: history.ItemMessage, Text: "a", DateText: "5 November"},
			{Kind: history.ItemMessage, Text: "b"},
			{Kind: history.ItemMessage, Text: "c", DateText: "6 November", UnreadBar: "Unread messages"},
			{Kind: history.ItemMessage, Text: "d"},
		},
		Heights: []int{70, 50, 60, 50},
	}
	pane := l.Pane(history.Viewport{Top: 70, Height: 60}, 320)
	if pane.First != 1 || pane.Count != 2 {
		t.Fatalf("pane rows = %d %d, want 1 2", pane.First, pane.Count)
	}
	if len(pane.Bars) != 2 {
		t.Fatalf("pane bars len = %d, want 2", len(pane.Bars))
	}
	if pane.Bars[0].Date != 0 || pane.Bars[0].Unread != 0 {
		t.Errorf("bars[0] = %+v, want zero", pane.Bars[0])
	}
	if pane.Bars[1].Date != 32 || pane.Bars[1].Unread != 35 {
		t.Errorf("bars[1] = %+v, want date 32 unread 35", pane.Bars[1])
	}
}
