package tests

import (
	"math"
	"testing"

	"uniclient/ui/history"
	"uniclient/ui/text"
)

func fieldMono() text.Metrics {
	return text.Metrics{
		Height:  16,
		Advance: func(rune) int { return 8 },
	}
}

func TestComposeFieldWrapWidth(t *testing.T) {
	cases := []struct{ inner, want int }{
		{100, 98},
		{46, 44},
		{2, 0},
		{1, 0},
	}
	for _, c := range cases {
		if got := history.ComposeFieldWrapWidth(c.inner); got != c.want {
			t.Fatalf("ComposeFieldWrapWidth(%d) = %d, want %d", c.inner, got, c.want)
		}
	}
}

func TestComposeFieldDocument(t *testing.T) {
	doc := history.ComposeFieldDocument("aa bb cc", 26, fieldMono())
	if len(doc.Lines) != 3 {
		t.Fatalf("ComposeFieldDocument: %d lines, want 3", len(doc.Lines))
	}
	if s := doc.Lines[1].Start; s != 3 {
		t.Fatalf("line 2 start = %d, want 3", s)
	}
}

func TestComposeFieldContentHeight(t *testing.T) {
	cases := []struct {
		text  string
		inner int
		want  int
	}{
		{"", 26, 16},
		{"a", 26, 16},
		{"aa bb cc", 26, 48},
		{"aa bb cc", 1000, 16},
	}
	for _, c := range cases {
		if got := history.ComposeFieldContentHeight(c.text, c.inner, fieldMono()); got != c.want {
			t.Fatalf("ComposeFieldContentHeight(%q, %d) = %d, want %d", c.text, c.inner, got, c.want)
		}
	}
}

func TestComposePlaceholderShown(t *testing.T) {
	cases := []struct {
		textLen int
		want    bool
	}{
		{0, true},
		{1, false},
		{5, false},
	}
	for _, c := range cases {
		if got := history.ComposePlaceholderShown(c.textLen); got != c.want {
			t.Fatalf("ComposePlaceholderShown(%d) = %v, want %v", c.textLen, got, c.want)
		}
	}
}

func TestComposePlaceholderMaxWidth(t *testing.T) {
	cases := []struct{ field, want int }{
		{100, 96},
		{46, 42},
		{4, 0},
		{3, 0},
	}
	for _, c := range cases {
		if got := history.ComposePlaceholderMaxWidth(c.field); got != c.want {
			t.Fatalf("ComposePlaceholderMaxWidth(%d) = %d, want %d", c.field, got, c.want)
		}
	}
}

func TestComposePlaceholderText(t *testing.T) {
	cases := []struct {
		placeholder string
		field       int
		want        string
	}{
		{"Message", 30, "Me…"},
		{"Hi", 20, "Hi"},
		{"Message", 4, "…"},
	}
	for _, c := range cases {
		if got := history.ComposePlaceholderText(c.placeholder, c.field, fieldMono()); got != c.want {
			t.Fatalf("ComposePlaceholderText(%q, %d) = %q, want %q", c.placeholder, c.field, got, c.want)
		}
	}
}

func TestComposePlaceholderOrigin(t *testing.T) {
	cases := []struct {
		degree float64
		wantX  int
	}{
		{0, 2},
		{0.25, 15},
		{0.5, 27},
		{1, 52},
	}
	for _, c := range cases {
		if got := history.ComposePlaceholderX(c.degree); got != c.wantX {
			t.Fatalf("ComposePlaceholderX(%v) = %d, want %d", c.degree, got, c.wantX)
		}
	}

	baseline := history.ComposePlaceholderBaseline(fieldMono())
	if math.Abs(baseline-12.8) > 1e-9 {
		t.Fatalf("ComposePlaceholderBaseline = %v, want 12.8", baseline)
	}
	withLead := history.ComposePlaceholderBaseline(text.Metrics{
		Height:  16,
		Leading: 2,
		Advance: func(rune) int { return 8 },
	})
	if math.Abs(withLead-10.8) > 1e-9 {
		t.Fatalf("ComposePlaceholderBaseline with leading = %v, want 10.8", withLead)
	}
}

func TestComposePlaceholderOpacity(t *testing.T) {
	cases := []struct {
		degree float64
		want   float64
	}{
		{0, 1},
		{0.5, 0.5},
		{1, 0},
	}
	for _, c := range cases {
		if got := history.ComposePlaceholderOpacity(c.degree); math.Abs(got-c.want) > 1e-9 {
			t.Fatalf("ComposePlaceholderOpacity(%v) = %v, want %v", c.degree, got, c.want)
		}
	}
}

func TestComposeCursorRect(t *testing.T) {
	doc := history.ComposeFieldDocument("aa bb cc", 26, fieldMono())
	cases := []struct {
		offset int
		want   history.Geometry
	}{
		{0, history.Geometry{Left: 0, Top: 0, Width: 1, Height: 16}},
		{4, history.Geometry{Left: 8, Top: 16, Width: 1, Height: 16}},
		{8, history.Geometry{Left: 16, Top: 32, Width: 1, Height: 16}},
	}
	for _, c := range cases {
		if got := history.ComposeCursorRect(doc, c.offset, fieldMono()); got != c.want {
			t.Fatalf("ComposeCursorRect(%d) = %+v, want %+v", c.offset, got, c.want)
		}
	}
}

func TestComposeFieldScrollOffset(t *testing.T) {
	cases := []struct {
		current, content, view, cursorY, cursorH, want int
	}{
		{0, 16, 36, 0, 16, 0},
		{0, 80, 36, 48, 16, 28},
		{28, 80, 36, 48, 16, 28},
		{28, 80, 36, 16, 16, 16},
		{0, 80, 36, 60, 16, 40},
		{0, 80, 36, 70, 16, 44},
		{0, 80, 36, 8, 16, 0},
	}
	for _, c := range cases {
		if got := history.ComposeFieldScrollOffset(c.current, c.content, c.view, c.cursorY, c.cursorH); got != c.want {
			t.Fatalf("ScrollOffset(cur=%d content=%d view=%d y=%d h=%d) = %d, want %d",
				c.current, c.content, c.view, c.cursorY, c.cursorH, got, c.want)
		}
	}
}
