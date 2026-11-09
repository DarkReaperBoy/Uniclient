package tests

import (
	"math"
	"testing"

	. "uniclient/ui/text"
)

func mono(advance, height int) Metrics {
	return Metrics{
		Height:  height,
		Advance: func(rune) int { return advance },
	}
}

func wideEllipsis(advance, ellipsis, height int) Metrics {
	return Metrics{
		Height: height,
		Advance: func(r rune) int {
			if r == '…' {
				return ellipsis
			}
			return advance
		},
	}
}

func TestLineHeight(t *testing.T) {
	cases := []struct {
		fontHeight, styleLineHeight, want int
	}{
		{16, 0, 16},
		{16, -1, 16},
		{16, 18, 18},
		{16, 12, 16},
		{20, 20, 20},
	}
	for _, c := range cases {
		if got := LineHeight(c.fontHeight, c.styleLineHeight); got != c.want {
			t.Fatalf("LineHeight(%d, %d) = %d, want %d", c.fontHeight, c.styleLineHeight, got, c.want)
		}
	}
}

func TestLineAscent(t *testing.T) {
	cases := []struct {
		m     Metrics
		lineH int
		want  float64
	}{
		{mono(8, 16), 0, 12.8},
		{mono(8, 16), 12, 12.8},
		{Metrics{Height: 16, Leading: 3}, 0, 9.8},
		{Metrics{Height: 16, Leading: 2}, 0, 10.8},
		{mono(8, 16), 20, 16},
		{mono(8, 20), 0, 16},
		{mono(8, 10), 20, 16},
		{Metrics{Height: 16, Leading: 100}, 0, 0},
		{Metrics{Height: 16, Leading: -5}, 0, 12.8},
	}
	for _, c := range cases {
		got := LineAscent(c.m, c.lineH)
		if math.Abs(got-c.want) > 1e-9 {
			t.Fatalf("LineAscent(h=%d lead=%d lh=%d) = %v, want %v", c.m.Height, c.m.Leading, c.lineH, got, c.want)
		}
	}
}

func TestElide(t *testing.T) {
	cases := []struct {
		text  string
		width int
		m     Metrics
		want  string
	}{
		{"abc", 30, mono(8, 16), "abc"},
		{"abcd", 30, mono(8, 16), "ab…"},
		{"abc", 20, mono(8, 16), "a…"},
		{"abc", 10, mono(8, 16), "…"},
		{"abc", 5, mono(8, 16), "…"},
		{"Hi", 16, mono(8, 16), "Hi"},
		{"", 20, mono(8, 16), ""},
		{"abcd", 25, wideEllipsis(10, 12, 16), "a…"},
	}
	for _, c := range cases {
		got := string(Elide([]rune(c.text), c.width, c.m))
		if got != c.want {
			t.Fatalf("Elide(%q, %d) = %q, want %q", c.text, c.width, got, c.want)
		}
	}
}

func TestLayout(t *testing.T) {
	cases := []struct {
		text   string
		width  int
		lines  []string
		widths []int
		starts []int
	}{
		{"", 24, []string{""}, []int{0}, []int{0}},
		{"a", 24, []string{"a"}, []int{8}, []int{0}},
		{"aaa", 24, []string{"aaa"}, []int{24}, []int{0}},
		{"aa bb cc", 24, []string{"aa ", "bb ", "cc"}, []int{24, 24, 16}, []int{0, 3, 6}},
		{"aaaa", 24, []string{"aaa", "a"}, []int{24, 8}, []int{0, 3}},
		{"x aaaa", 24, []string{"x ", "aaa", "a"}, []int{16, 24, 8}, []int{0, 2, 5}},
		{"aa   bb", 24, []string{"aa   ", "bb"}, []int{40, 16}, []int{0, 5}},
		{" aa", 24, []string{" aa"}, []int{24}, []int{0}},
		{"   aa", 16, []string{"   ", "aa"}, []int{24, 16}, []int{0, 3}},
		{"a", 4, []string{"a"}, []int{8}, []int{0}},
		{"a\nb", 100, []string{"a", "b"}, []int{8, 8}, []int{0, 2}},
		{"a\n", 100, []string{"a", ""}, []int{8, 0}, []int{0, 2}},
		{"\n", 100, []string{"", ""}, []int{0, 0}, []int{0, 1}},
		{"a\n\nb", 100, []string{"a", "", "b"}, []int{8, 0, 8}, []int{0, 2, 3}},
		{"aa bb\ncc dd", 16, []string{"aa ", "bb", "cc ", "dd"}, []int{24, 16, 24, 16}, []int{0, 3, 6, 9}},
	}
	for _, c := range cases {
		doc := Layout(c.text, c.width, mono(8, 16))
		if len(doc.Lines) != len(c.lines) {
			t.Fatalf("Layout(%q, %d): %d lines, want %d: %v", c.text, c.width, len(doc.Lines), len(c.lines), doc.Lines)
		}
		for i, want := range c.lines {
			line := doc.Lines[i]
			if string(line.Runes) != want || line.Width != c.widths[i] || line.Start != c.starts[i] {
				t.Fatalf("Layout(%q, %d) line %d = {%q w%d s%d}, want {%q w%d s%d}",
					c.text, c.width, i, string(line.Runes), line.Width, line.Start, want, c.widths[i], c.starts[i])
			}
		}
		if got := string(doc.Text); got != c.text {
			t.Fatalf("Layout(%q).Text = %q", c.text, got)
		}
	}
}

func TestDocumentHeight(t *testing.T) {
	doc := Layout("aa bb cc", 24, mono(8, 16))
	if got := doc.Height(16); got != 48 {
		t.Fatalf("Height = %d, want 48", got)
	}
	empty := Layout("", 24, mono(8, 16))
	if got := empty.Height(16); got != 16 {
		t.Fatalf("empty Height = %d, want 16", got)
	}
}

func TestCursorAt(t *testing.T) {
	doc := Layout("aa bb cc", 24, mono(8, 16))
	cases := []struct {
		offset int
		line   int
		column int
		x      int
	}{
		{0, 0, 0, 0},
		{2, 0, 2, 16},
		{3, 1, 0, 0},
		{4, 1, 1, 8},
		{5, 1, 2, 16},
		{6, 2, 0, 0},
		{7, 2, 1, 8},
		{8, 2, 2, 16},
		{-3, 0, 0, 0},
		{99, 2, 2, 16},
	}
	for _, c := range cases {
		got := doc.CursorAt(c.offset)
		if got.Line != c.line || got.Column != c.column || got.X != c.x {
			t.Fatalf("CursorAt(%d) = {line %d col %d x %d}, want {line %d col %d x %d}",
				c.offset, got.Line, got.Column, got.X, c.line, c.column, c.x)
		}
	}

	nl := Layout("a\nb", 100, mono(8, 16))
	if got := nl.CursorAt(1); got.Line != 0 || got.Column != 1 || got.X != 8 {
		t.Fatalf("CursorAt(1) on newline = %+v, want {0 1 8}", got)
	}
	if got := nl.CursorAt(2); got.Line != 1 || got.Column != 0 || got.X != 0 {
		t.Fatalf("CursorAt(2) after newline = %+v, want {1 0 0}", got)
	}
}

func TestSelectionRange(t *testing.T) {
	sel := Selection{Anchor: 2, Position: 5}
	if from, to := sel.Range(); from != 2 || to != 5 {
		t.Fatalf("Range() = %d,%d want 2,5", from, to)
	}
	if sel.Empty() {
		t.Fatal("sel should not be empty")
	}
	rev := Selection{Anchor: 5, Position: 2}
	if from, to := rev.Range(); from != 2 || to != 5 {
		t.Fatalf("reversed Range() = %d,%d want 2,5", from, to)
	}
	same := Selection{Anchor: 3, Position: 3}
	if !same.Empty() {
		t.Fatal("equal anchor/position should be empty")
	}
}

func TestSelectionSpans(t *testing.T) {
	doc := Layout("aa bb cc", 24, mono(8, 16))
	cases := []struct {
		anchor, position int
		want             []Span
	}{
		{0, 8, []Span{{Line: 0, From: 0, To: 16}, {Line: 1, From: 0, To: 16}, {Line: 2, From: 0, To: 16}}},
		{0, 3, []Span{{Line: 0, From: 0, To: 16}}},
		{2, 5, []Span{{Line: 1, From: 0, To: 16}}},
		{0, 4, []Span{{Line: 0, From: 0, To: 16}, {Line: 1, From: 0, To: 8}}},
		{3, 3, nil},
		{-5, 99, []Span{{Line: 0, From: 0, To: 16}, {Line: 1, From: 0, To: 16}, {Line: 2, From: 0, To: 16}}},
	}
	for _, c := range cases {
		got := doc.SelectionSpans(Selection{Anchor: c.anchor, Position: c.position})
		if len(got) != len(c.want) {
			t.Fatalf("SelectionSpans(%d,%d) = %v, want %v", c.anchor, c.position, got, c.want)
		}
		for i, w := range c.want {
			if got[i] != w {
				t.Fatalf("SelectionSpans(%d,%d)[%d] = %+v, want %+v", c.anchor, c.position, i, got[i], w)
			}
		}
	}

	soft := Layout("aa   bb", 24, mono(8, 16))
	got := soft.SelectionSpans(Selection{Anchor: 0, Position: 7})
	want := []Span{{Line: 0, From: 0, To: 16}, {Line: 1, From: 0, To: 16}}
	if len(got) != 2 || got[0] != want[0] || got[1] != want[1] {
		t.Fatalf("soft-wrap trailing spaces must strip: %v", got)
	}

	hard := Layout("ab  \ncc", 100, mono(8, 16))
	got = hard.SelectionSpans(Selection{Anchor: 0, Position: 4})
	if len(got) != 1 || got[0] != (Span{Line: 0, From: 0, To: 32}) {
		t.Fatalf("hard-break trailing spaces must keep: %v", got)
	}
}

func TestMoveHorizontal(t *testing.T) {
	doc := Layout("abc", 100, mono(8, 16))
	if got := doc.MoveLeft(2, 2); got != 1 {
		t.Fatalf("MoveLeft(2) = %d, want 1", got)
	}
	if got := doc.MoveLeft(0, 0); got != 0 {
		t.Fatalf("MoveLeft(0) = %d, want 0", got)
	}
	if got := doc.MoveRight(1, 1); got != 2 {
		t.Fatalf("MoveRight(1) = %d, want 2", got)
	}
	if got := doc.MoveRight(3, 3); got != 3 {
		t.Fatalf("MoveRight(3) = %d, want 3", got)
	}
	if got := doc.MoveLeft(5, 2); got != 2 {
		t.Fatalf("MoveLeft with selection = %d, want 2 (min)", got)
	}
	if got := doc.MoveLeft(2, 5); got != 2 {
		t.Fatalf("MoveLeft with selection = %d, want 2 (min)", got)
	}
	if got := doc.MoveRight(2, 5); got != 5 {
		t.Fatalf("MoveRight with selection = %d, want 5 (max)", got)
	}
	if got := doc.MoveRight(5, 2); got != 5 {
		t.Fatalf("MoveRight with selection = %d, want 5 (max)", got)
	}
}

func TestMoveLineBounds(t *testing.T) {
	doc := Layout("aa bb cc", 24, mono(8, 16))
	cases := []struct {
		offset, want int
	}{
		{0, 2},
		{4, 5},
		{6, 8},
		{8, 8},
	}
	for _, c := range cases {
		if got := doc.MoveEndOfLine(c.offset); got != c.want {
			t.Fatalf("MoveEndOfLine(%d) = %d, want %d", c.offset, got, c.want)
		}
	}
	starts := []struct {
		offset, want int
	}{
		{0, 0},
		{4, 3},
		{7, 6},
		{8, 6},
	}
	for _, c := range starts {
		if got := doc.MoveStartOfLine(c.offset); got != c.want {
			t.Fatalf("MoveStartOfLine(%d) = %d, want %d", c.offset, got, c.want)
		}
	}

	hard := Layout("ab  \ncc", 100, mono(8, 16))
	if got := hard.MoveEndOfLine(0); got != 4 {
		t.Fatalf("hard MoveEndOfLine(0) = %d, want 4 (spaces kept)", got)
	}
	if got := hard.MoveStartOfLine(5); got != 5 {
		t.Fatalf("MoveStartOfLine(5) = %d, want 5", got)
	}
	if got := hard.MoveHome(); got != 0 {
		t.Fatalf("MoveHome = %d, want 0", got)
	}
	if got := hard.MoveEnd(); got != 7 {
		t.Fatalf("MoveEnd = %d, want 7", got)
	}
}

func TestMoveWords(t *testing.T) {
	doc := Layout("one two.three  four", 200, mono(8, 16))
	nexts := []struct{ from, want int }{
		{0, 4}, {1, 4}, {3, 4}, {4, 7}, {7, 8}, {8, 15}, {13, 15}, {15, 19}, {19, 19},
	}
	for _, c := range nexts {
		if got := doc.MoveWordRight(c.from); got != c.want {
			t.Fatalf("MoveWordRight(%d) = %d, want %d", c.from, got, c.want)
		}
	}
	prevs := []struct{ from, want int }{
		{0, 0}, {1, 0}, {3, 0}, {4, 0}, {7, 4}, {8, 7}, {9, 8}, {13, 8}, {15, 8}, {19, 15},
	}
	for _, c := range prevs {
		if got := doc.MoveWordLeft(c.from); got != c.want {
			t.Fatalf("MoveWordLeft(%d) = %d, want %d", c.from, got, c.want)
		}
	}

	nl := Layout("ab  \nxy zz", 200, mono(8, 16))
	nlNext := []struct{ from, want int }{
		{0, 4}, {2, 4}, {4, 5}, {5, 8}, {8, 10}, {10, 10},
	}
	for _, c := range nlNext {
		if got := nl.MoveWordRight(c.from); got != c.want {
			t.Fatalf("nl MoveWordRight(%d) = %d, want %d", c.from, got, c.want)
		}
	}
	nlPrev := []struct{ from, want int }{
		{0, 0}, {2, 0}, {4, 0}, {5, 4}, {6, 5}, {8, 5}, {10, 8},
	}
	for _, c := range nlPrev {
		if got := nl.MoveWordLeft(c.from); got != c.want {
			t.Fatalf("nl MoveWordLeft(%d) = %d, want %d", c.from, got, c.want)
		}
	}
}

func TestXToColumn(t *testing.T) {
	doc := Layout("aa bb cc", 24, mono(8, 16))
	cases := []struct {
		x, want int
	}{
		{0, 0}, {3, 0}, {4, 0}, {5, 1}, {8, 1}, {12, 1}, {16, 2}, {20, 2}, {24, 2}, {100, 2},
	}
	for _, c := range cases {
		if got := doc.XToColumn(1, c.x); got != c.want {
			t.Fatalf("XToColumn(1, %d) = %d, want %d", c.x, got, c.want)
		}
	}
}

func TestMoveVertical(t *testing.T) {
	doc := Layout("aa bb cc", 24, mono(8, 16))
	cases := []struct {
		offset, goalX   int
		hasGoal, up     bool
		wantOff, wantGx int
	}{
		{6, 0, false, true, 3, 0},
		{8, 16, true, true, 5, 16},
		{8, 12, true, true, 4, 12},
		{3, 0, false, true, 0, 0},
		{0, 16, true, true, 0, 16},
		{0, 0, false, true, 0, 0},
		{5, 0, false, false, 8, 16},
		{8, 4, true, false, 8, 4},
	}
	for _, c := range cases {
		off, gx := doc.MoveVertical(c.offset, c.goalX, c.hasGoal, c.up)
		if off != c.wantOff || gx != c.wantGx {
			t.Fatalf("MoveVertical(%d, %d, %v, %v) = (%d, %d), want (%d, %d)",
				c.offset, c.goalX, c.hasGoal, c.up, off, gx, c.wantOff, c.wantGx)
		}
	}

	deep := Layout("a\nbb\nccc", 100, mono(8, 16))
	off, gx := deep.MoveVertical(7, 0, false, true)
	if off != 4 || gx != 16 {
		t.Fatalf("deep up 1 = (%d, %d), want (4, 16)", off, gx)
	}
	off, gx = deep.MoveVertical(off, gx, true, true)
	if off != 1 || gx != 16 {
		t.Fatalf("deep up 2 = (%d, %d), want (1, 16)", off, gx)
	}

	empty := Layout("", 24, mono(8, 16))
	off, gx = empty.MoveVertical(0, 0, false, true)
	if off != 0 || gx != 0 {
		t.Fatalf("empty up = (%d, %d), want (0, 0)", off, gx)
	}
}

func TestInsertAt(t *testing.T) {
	doc := Layout("abcdef", 200, mono(8, 16))
	cases := []struct {
		offset, anchor int
		insert         string
		wantText       string
		wantCursor     int
	}{
		{3, 3, "xy", "abcxydef", 5},
		{2, 5, "Z", "abZf", 3},
		{5, 2, "Z", "abZf", 3},
		{0, 0, "hi", "hiabcdef", 2},
		{6, 6, "!", "abcdef!", 7},
		{2, 5, "", "abf", 2},
	}
	for _, c := range cases {
		text, cursor := doc.InsertAt(c.offset, c.anchor, c.insert)
		if text != c.wantText || cursor != c.wantCursor {
			t.Fatalf("InsertAt(%d,%d,%q) = (%q,%d), want (%q,%d)",
				c.offset, c.anchor, c.insert, text, cursor, c.wantText, c.wantCursor)
		}
	}
	empty := Layout("", 200, mono(8, 16))
	if text, cursor := empty.InsertAt(0, 0, "hi"); text != "hi" || cursor != 2 {
		t.Fatalf("empty InsertAt = (%q,%d)", text, cursor)
	}
}

func TestDeleteBackwardForward(t *testing.T) {
	doc := Layout("abcdef", 200, mono(8, 16))
	cases := []struct {
		name           string
		offset, anchor int
		wantText       string
		wantCursor     int
	}{
		{"back", 3, 3, "abdef", 2},
		{"back-at-0", 0, 0, "abcdef", 0},
		{"back-sel", 2, 5, "abf", 2},
		{"back-sel-rev", 5, 2, "abf", 2},
	}
	for _, c := range cases {
		text, cursor := doc.DeleteBackward(c.offset, c.anchor)
		if text != c.wantText || cursor != c.wantCursor {
			t.Fatalf("%s = (%q,%d), want (%q,%d)", c.name, text, cursor, c.wantText, c.wantCursor)
		}
	}
	fwd := []struct {
		name           string
		offset, anchor int
		wantText       string
		wantCursor     int
	}{
		{"fwd", 1, 1, "acdef", 1},
		{"fwd-at-end", 6, 6, "abcdef", 6},
		{"fwd-sel", 2, 5, "abf", 2},
	}
	for _, c := range fwd {
		text, cursor := doc.DeleteForward(c.offset, c.anchor)
		if text != c.wantText || cursor != c.wantCursor {
			t.Fatalf("%s = (%q,%d), want (%q,%d)", c.name, text, cursor, c.wantText, c.wantCursor)
		}
	}
	nl := Layout("ab\nxy", 200, mono(8, 16))
	if text, cursor := nl.DeleteBackward(3, 3); text != "abxy" || cursor != 2 {
		t.Fatalf("newline merge = (%q,%d), want (abxy,2)", text, cursor)
	}
}

func TestDeleteWords(t *testing.T) {
	doc := Layout("one two.three", 200, mono(8, 16))
	if text, cursor := doc.DeleteWordBackward(8, 8); text != "one twothree" || cursor != 7 {
		t.Fatalf("DeleteWordBackward(8) = (%q,%d), want (one twothree,7)", text, cursor)
	}
	if text, cursor := doc.DeleteWordBackward(0, 0); text != "one two.three" || cursor != 0 {
		t.Fatalf("DeleteWordBackward(0) = (%q,%d)", text, cursor)
	}
	if text, cursor := doc.DeleteWordBackward(4, 9); text != "one hree" || cursor != 4 {
		t.Fatalf("DeleteWordBackward sel = (%q,%d), want (one hree,4)", text, cursor)
	}
	two := Layout("one two", 200, mono(8, 16))
	if text, cursor := two.DeleteWordForward(4, 4); text != "one " || cursor != 4 {
		t.Fatalf("DeleteWordForward(4) = (%q,%d), want (one ,4)", text, cursor)
	}
	if text, cursor := doc.DeleteWordForward(3, 3); text != "onetwo.three" || cursor != 3 {
		t.Fatalf("DeleteWordForward(3) = (%q,%d), want (onetwo.three,3)", text, cursor)
	}
	if text, cursor := doc.DeleteWordForward(13, 13); text != "one two.three" || cursor != 13 {
		t.Fatalf("DeleteWordForward(end) = (%q,%d)", text, cursor)
	}
}

func TestNilMetricsAdvanceIsZeroWidth(t *testing.T) {
	doc := Layout("hi there", 100, Metrics{})
	if len(doc.Lines) != 1 || doc.Lines[0].Width != 0 {
		t.Fatalf("nil-advance layout = %d lines, width %d, want 1/0", len(doc.Lines), doc.Lines[0].Width)
	}
	if h := doc.Height(5); h != 5 {
		t.Fatalf("nil-advance height = %d, want 5", h)
	}
	c := doc.CursorAt(2)
	if c.Line != 0 || c.Column != 2 || c.X != 0 {
		t.Fatalf("nil-advance cursor = %+v, want col 2 x 0", c)
	}
	if text, cursor := doc.InsertAt(2, 2, "x"); text != "hix there" || cursor != 3 {
		t.Fatalf("nil-advance insert = (%q,%d)", text, cursor)
	}
}

func TestMoveStartOfWord(t *testing.T) {
	doc := Layout("foo bar", 200, mono(8, 16))
	cases := []struct{ from, want int }{
		{0, 0}, {2, 0}, {3, 0}, {4, 4}, {5, 4}, {7, 4},
	}
	for _, c := range cases {
		if got := doc.MoveStartOfWord(c.from); got != c.want {
			t.Fatalf("MoveStartOfWord(%d) = %d, want %d", c.from, got, c.want)
		}
	}
	sep := Layout("foo, bar", 200, mono(8, 16))
	sepCases := []struct{ from, want int }{
		{3, 3}, {4, 3}, {5, 5}, {8, 5},
	}
	for _, c := range sepCases {
		if got := sep.MoveStartOfWord(c.from); got != c.want {
			t.Fatalf("sep MoveStartOfWord(%d) = %d, want %d", c.from, got, c.want)
		}
	}
	multi := Layout("aa\nbb", 200, mono(8, 16))
	multiCases := []struct{ from, want int }{
		{2, 0}, {3, 3}, {5, 3},
	}
	for _, c := range multiCases {
		if got := multi.MoveStartOfWord(c.from); got != c.want {
			t.Fatalf("multi MoveStartOfWord(%d) = %d, want %d", c.from, got, c.want)
		}
	}
	trail := Layout("foo ", 200, mono(8, 16))
	if got := trail.MoveStartOfWord(4); got != 4 {
		t.Fatalf("trailing-space MoveStartOfWord(4) = %d, want 4 (at word start, no move)", got)
	}
}

func TestMoveEndOfWord(t *testing.T) {
	doc := Layout("foo bar", 200, mono(8, 16))
	cases := []struct{ from, want int }{
		{0, 3}, {2, 3}, {3, 3}, {4, 7}, {6, 7}, {7, 7},
	}
	for _, c := range cases {
		if got := doc.MoveEndOfWord(c.from); got != c.want {
			t.Fatalf("MoveEndOfWord(%d) = %d, want %d", c.from, got, c.want)
		}
	}
	sep := Layout("foo,bar", 200, mono(8, 16))
	sepCases := []struct{ from, want int }{
		{2, 3}, {3, 4}, {4, 7},
	}
	for _, c := range sepCases {
		if got := sep.MoveEndOfWord(c.from); got != c.want {
			t.Fatalf("sep MoveEndOfWord(%d) = %d, want %d", c.from, got, c.want)
		}
	}
	multi := Layout("aa\nbb", 200, mono(8, 16))
	multiCases := []struct{ from, want int }{
		{0, 2}, {2, 2}, {3, 5}, {5, 5},
	}
	for _, c := range multiCases {
		if got := multi.MoveEndOfWord(c.from); got != c.want {
			t.Fatalf("multi MoveEndOfWord(%d) = %d, want %d", c.from, got, c.want)
		}
	}
}

func TestMoveStartOfBlock(t *testing.T) {
	doc := Layout("aa\nbb\ncc", 200, mono(8, 16))
	cases := []struct{ from, want int }{
		{0, 0}, {1, 0}, {2, 0}, {3, 3}, {4, 3}, {5, 3}, {6, 6}, {7, 6}, {8, 6},
	}
	for _, c := range cases {
		if got := doc.MoveStartOfBlock(c.from); got != c.want {
			t.Fatalf("MoveStartOfBlock(%d) = %d, want %d", c.from, got, c.want)
		}
	}
	empty := Layout("a\n\nb", 200, mono(8, 16))
	if got := empty.MoveStartOfBlock(2); got != 2 {
		t.Fatalf("empty-line MoveStartOfBlock(2) = %d, want 2", got)
	}
	if got := empty.MoveStartOfBlock(3); got != 3 {
		t.Fatalf("after-empty MoveStartOfBlock(3) = %d, want 3", got)
	}
}

func TestMoveEndOfBlock(t *testing.T) {
	doc := Layout("aa\nbb\ncc", 200, mono(8, 16))
	cases := []struct{ from, want int }{
		{0, 2}, {1, 2}, {2, 2}, {3, 5}, {4, 5}, {5, 5}, {6, 8}, {7, 8}, {8, 8},
	}
	for _, c := range cases {
		if got := doc.MoveEndOfBlock(c.from); got != c.want {
			t.Fatalf("MoveEndOfBlock(%d) = %d, want %d", c.from, got, c.want)
		}
	}
	empty := Layout("a\n\nb", 200, mono(8, 16))
	if got := empty.MoveEndOfBlock(2); got != 2 {
		t.Fatalf("on-separator MoveEndOfBlock(2) = %d, want 2", got)
	}
	if got := empty.MoveEndOfBlock(0); got != 1 {
		t.Fatalf("first-block MoveEndOfBlock(0) = %d, want 1", got)
	}
}
