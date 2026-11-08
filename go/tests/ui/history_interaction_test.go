package tests

import (
	"reflect"
	"testing"

	"uniclient/ui/history"
)

func TestTimeRect(t *testing.T) {
	cases := []struct {
		name         string
		g            history.Geometry
		infoW, dateH int
		send         bool
		want         history.Geometry
	}{
		{
			name:  "plain",
			g:     history.Geometry{Left: 20, Top: 100, Width: 200, Height: 80},
			infoW: 30, dateH: 13,
			want: history.Geometry{Left: 181, Top: 164, Width: 30, Height: 13},
		},
		{
			name:  "sendState",
			g:     history.Geometry{Left: 20, Top: 100, Width: 200, Height: 80},
			infoW: 30, dateH: 13, send: true,
			want: history.Geometry{Left: 157, Top: 164, Width: 54, Height: 13},
		},
		{
			name:  "small bubble",
			g:     history.Geometry{Left: 0, Top: 0, Width: 120, Height: 40},
			infoW: 20, dateH: 12,
			want: history.Geometry{Left: 91, Top: 25, Width: 20, Height: 12},
		},
	}
	for _, c := range cases {
		if got := history.TimeRect(c.g, c.infoW, c.dateH, c.send); got != c.want {
			t.Fatalf("%s: TimeRect = %+v, want %+v", c.name, got, c.want)
		}
	}
}

func TestGeometryContains(t *testing.T) {
	g := history.Geometry{Left: 10, Top: 20, Width: 100, Height: 50}
	cases := []struct {
		x, y int
		want bool
	}{
		{10, 20, true},
		{109, 69, true},
		{110, 20, false},
		{10, 70, false},
		{9, 20, false},
		{10, 19, false},
	}
	for _, c := range cases {
		if got := g.Contains(c.x, c.y); got != c.want {
			t.Fatalf("Contains(%d,%d) = %v, want %v", c.x, c.y, got, c.want)
		}
	}
}

func TestHitBoxPointState(t *testing.T) {
	box := history.HitBox{
		Item: history.Geometry{Left: 20, Top: 100, Width: 200, Height: 80},
		Time: history.Geometry{Left: 181, Top: 164, Width: 30, Height: 13},
	}
	msg := history.Item{Kind: history.ItemMessage}
	cases := []struct {
		name string
		item history.Item
		x, y int
		want history.PointState
	}{
		{"inside bubble", msg, 20, 100, history.PointInside},
		{"inside far corner", msg, 219, 179, history.PointInside},
		{"right of bubble", msg, 220, 100, history.PointOutside},
		{"above bubble (row margin)", msg, 20, 99, history.PointOutside},
		{"hidden item", history.Item{Kind: history.ItemMessage, Hidden: true}, 100, 140, history.PointOutside},
	}
	for _, c := range cases {
		if got := box.PointStateOf(c.item, c.x, c.y); got != c.want {
			t.Fatalf("%s: PointStateOf = %v, want %v", c.name, got, c.want)
		}
	}
	degenerate := history.HitBox{Item: history.Geometry{Left: 20, Top: 100, Width: 0, Height: 80}}
	if got := degenerate.PointStateOf(msg, 20, 100); got != history.PointOutside {
		t.Fatalf("width < 1 = %v, want Outside", got)
	}
	svc := history.HitBox{Item: history.Geometry{Left: 12, Top: 65, Width: 776, Height: 50}}
	if got := svc.PointStateOf(history.Item{Kind: history.ItemService}, 100, 90); got != history.PointInside {
		t.Fatalf("service geometry contains = %v, want Inside", got)
	}
}

func TestHitBoxTimeHit(t *testing.T) {
	box := history.HitBox{
		Item: history.Geometry{Left: 20, Top: 100, Width: 200, Height: 80},
		Time: history.Geometry{Left: 181, Top: 164, Width: 30, Height: 13},
	}
	cases := []struct {
		x, y int
		want bool
	}{
		{181, 164, true},
		{210, 176, true},
		{211, 164, false},
		{181, 177, false},
	}
	for _, c := range cases {
		if got := box.TimeHit(c.x, c.y); got != c.want {
			t.Fatalf("TimeHit(%d,%d) = %v, want %v", c.x, c.y, got, c.want)
		}
	}
	empty := history.HitBox{}
	if empty.TimeHit(0, 0) {
		t.Fatal("zero time rect must not hit")
	}
}

func TestItemCanBeSelected(t *testing.T) {
	cases := []struct {
		item history.Item
		want bool
	}{
		{history.Item{Kind: history.ItemMessage}, true},
		{history.Item{Kind: history.ItemService}, false},
		{history.Item{Kind: history.ItemMessage, Empty: true}, false},
		{history.Item{Kind: history.ItemMessage, Hidden: true}, true},
	}
	for i, c := range cases {
		if got := c.item.CanBeSelected(); got != c.want {
			t.Fatalf("case %d: CanBeSelected = %v, want %v", i, got, c.want)
		}
	}
}

func TestSelectionQueries(t *testing.T) {
	var nilSel history.Selection
	if nilSel.HasSelectedItems() || nilSel.InSelectionMode() {
		t.Fatal("nil selection must report no items / no selection mode")
	}
	if nilSel.ContainsRow(0) {
		t.Fatal("nil selection contains nothing")
	}
	empty := history.Selection{}
	if empty.HasSelectedItems() || empty.InSelectionMode() {
		t.Fatal("empty selection must report no items / no selection mode")
	}
	sel := history.Selection{1: true}
	if !sel.HasSelectedItems() || !sel.InSelectionMode() || !sel.ContainsRow(1) {
		t.Fatal("one selected item must report selection mode")
	}
}

func TestChangeSelection(t *testing.T) {
	msg := history.Item{Kind: history.ItemMessage}
	svc := history.Item{Kind: history.ItemService}
	empty := history.Item{Kind: history.ItemMessage, Empty: true}
	cases := []struct {
		name   string
		before history.Selection
		row    int
		item   history.Item
		action history.SelectAction
		want   history.Selection
	}{
		{"invert adds on nil", nil, 2, msg, history.SelectInvert, history.Selection{2: true}},
		{"invert removes the member", history.Selection{2: true}, 2, msg, history.SelectInvert, nil},
		{"invert keeps others", history.Selection{2: true}, 3, msg, history.SelectInvert, history.Selection{2: true, 3: true}},
		{"invert on service gated", nil, 0, svc, history.SelectInvert, nil},
		{"invert on empty gated", nil, 0, empty, history.SelectInvert, nil},
		{"add on nil", nil, 7, msg, history.SelectAdd, history.Selection{7: true}},
		{"add existing is a no-op", history.Selection{2: true}, 2, msg, history.SelectAdd, history.Selection{2: true}},
		{"add service gated", nil, 0, svc, history.SelectAdd, nil},
		{"add empty gated", nil, 0, empty, history.SelectAdd, nil},
		{"remove non-member is a no-op", history.Selection{1: true}, 5, msg, history.SelectRemove, history.Selection{1: true}},
		{"remove on nil", nil, 7, msg, history.SelectRemove, nil},
	}
	for _, c := range cases {
		got := history.ChangeSelection(c.before, c.row, c.item, c.action)
		if !reflect.DeepEqual(got, c.want) {
			t.Fatalf("%s: ChangeSelection = %v, want %v", c.name, got, c.want)
		}
	}
}

func TestChangeSelectionCap(t *testing.T) {
	msg := history.Item{Kind: history.ItemMessage}
	full := make(history.Selection, history.MaxSelectedItems)
	for i := 0; i < history.MaxSelectedItems; i++ {
		full[i] = true
	}
	got := history.ChangeSelection(full, history.MaxSelectedItems, msg, history.SelectAdd)
	if len(got) != history.MaxSelectedItems || got[history.MaxSelectedItems] {
		t.Fatalf("cap: got %d items, want %d without row %d",
			len(got), history.MaxSelectedItems, history.MaxSelectedItems)
	}
	got = history.ChangeSelection(full, history.MaxSelectedItems, msg, history.SelectInvert)
	if len(got) != history.MaxSelectedItems || got[history.MaxSelectedItems] {
		t.Fatalf("invert cap: got %d items, want %d without row %d",
			len(got), history.MaxSelectedItems, history.MaxSelectedItems)
	}
	got = history.ChangeSelection(full, 0, msg, history.SelectAdd)
	if len(got) != history.MaxSelectedItems || !got[0] {
		t.Fatal("member re-add must keep the member")
	}
	got = history.ChangeSelection(full, 0, msg, history.SelectRemove)
	if len(got) != history.MaxSelectedItems-1 {
		t.Fatalf("remove at cap = %d items, want %d", len(got), history.MaxSelectedItems-1)
	}
	got = history.ChangeSelection(got, 0, msg, history.SelectAdd)
	if len(got) != history.MaxSelectedItems || !got[0] {
		t.Fatal("refill after remove must re-add the row")
	}
}

func TestChangeSelectionDoesNotAlias(t *testing.T) {
	msg := history.Item{Kind: history.ItemMessage}
	before := history.Selection{1: true}
	after := history.ChangeSelection(before, 2, msg, history.SelectInvert)
	if len(before) != 1 || before[2] {
		t.Fatalf("ChangeSelection aliased the input: before = %v", before)
	}
	if !after[1] || !after[2] {
		t.Fatalf("after = %v, want rows 1 and 2", after)
	}
}
