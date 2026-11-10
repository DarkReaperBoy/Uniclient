package tests

import (
	"strings"
	"testing"

	. "uniclient/ui/dialogs"
	. "uniclient/ui/tokens"
)

func TestSearchEmptyQueryPreviewCap(t *testing.T) {
	cases := []struct {
		in   string
		want string
	}{
		{"zz", "zz"},
		{strings.Repeat("a", 32), strings.Repeat("a", 32)},
		{strings.Repeat("a", 33), strings.Repeat("a", 32)},
		{strings.Repeat("a", 40), strings.Repeat("a", 32)},
	}
	for _, c := range cases {
		if got := SearchEmptyQueryPreview(c.in); got != c.want {
			t.Fatalf("SearchEmptyQueryPreview(%d chars) = %d chars, want %d", len(c.in), len(got), len(c.want))
		}
	}
}

func TestListSearchEmptyHeight(t *testing.T) {
	l := List{SearchEmptyShown: true}
	if got := l.Height(380); got != SearchEmptyHeightMin {
		t.Fatalf("search-empty height = %d, want %d", got, SearchEmptyHeightMin)
	}
	l.SearchEmptyShown = false
	if got := l.Height(380); got != 0 {
		t.Fatalf("bare empty list height = %d, want 0", got)
	}
}

func TestPaneCarriesSearchEmpty(t *testing.T) {
	l := List{SearchEmptyShown: true, SearchEmptyTitle: "No Results", SearchEmptyLine: "There were no results for \"zz\"."}
	p := l.Pane(Viewport{Top: 0, Height: 400}, 380)
	if !p.SearchEmptyShown || p.SearchEmptyTitle != "No Results" ||
		p.SearchEmptyLine != "There were no results for \"zz\"." {
		t.Fatalf("pane search-empty = (%v, %q, %q)", p.SearchEmptyShown, p.SearchEmptyTitle, p.SearchEmptyLine)
	}
}

func TestSearchEmptyTextTopLaw(t *testing.T) {
	want := (SearchEmptyHeightMin-SearchEmptyIconSize)/3 + SearchEmptyIconSize + SearchEmptyIconSkip
	if SearchEmptyTextTop != want {
		t.Fatalf("SearchEmptyTextTop = %d, want %d (the reference icon-slot law)", SearchEmptyTextTop, want)
	}
}
