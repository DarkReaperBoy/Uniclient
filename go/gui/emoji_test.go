package gui

import (
	"testing"

	"gioui.org/layout"
)

// Emoji picker pure helpers (gui/emoji.go, §4 a.wid.composer helpers).

func TestEmojiRowCount(t *testing.T) {
	cases := []struct {
		n, cols, want int
	}{
		{0, 8, 0},
		{1, 8, 1},
		{8, 8, 1},
		{9, 8, 2},
		{80, 8, 10},
		{5, 0, 0}, // degenerate cols
		{10, 3, 4},
	}
	for _, c := range cases {
		if got := emojiRowCount(c.n, c.cols); got != c.want {
			t.Errorf("emojiRowCount(%d,%d) = %d, want %d", c.n, c.cols, got, c.want)
		}
	}
}

func TestEmojiCategorySafe(t *testing.T) {
	if got := emojiCategorySafe(-1); got.label != emojiCategories[0].label {
		t.Errorf("negative index should fall back to first category, got %q", got.label)
	}
	if got := emojiCategorySafe(len(emojiCategories)); got.label != emojiCategories[0].label {
		t.Errorf("overflow index should fall back to first category, got %q", got.label)
	}
	if got := emojiCategorySafe(1); got.label != emojiCategories[1].label {
		t.Errorf("index 1 = %q, want %q", got.label, emojiCategories[1].label)
	}
}

func TestEmojiDatasetSanity(t *testing.T) {
	if len(emojiCategories) < 8 {
		t.Fatalf("only %d categories, want a real set", len(emojiCategories))
	}
	seen := map[string]bool{}
	for _, cat := range emojiCategories {
		if cat.label == "" || cat.icon == "" {
			t.Fatalf("category with empty label/icon: %+v", cat)
		}
		if len(cat.emojis) < 12 {
			t.Fatalf("category %q too small: %d emojis", cat.label, len(cat.emojis))
		}
		for _, e := range cat.emojis {
			if e == "" {
				t.Fatalf("category %q contains an empty emoji string", cat.label)
			}
			if seen[e] {
				t.Fatalf("duplicate emoji %q across categories", e)
			}
			seen[e] = true
		}
	}
}

func TestCellsForRow(t *testing.T) {
	emojis := []string{"a", "b", "c", "d", "e"}
	// Rigid children are lazy (invoked at Layout time), so verify the shape:
	// every row is padded to exactly `cols` children.
	kids := cellsForRow(emojis, 2, 8, func(gtx layout.Context, idx int, e string) layout.Dimensions {
		return layout.Dimensions{}
	})
	if len(kids) != 8 {
		t.Errorf("cellsForRow returns %d children, want 8 (padded)", len(kids))
	}
	// Full-row start still yields cols children, none lazy-invoked here.
	kids = cellsForRow(emojis, 0, 8, func(gtx layout.Context, idx int, e string) layout.Dimensions {
		return layout.Dimensions{}
	})
	if len(kids) != 8 {
		t.Errorf("full row returns %d children, want 8", len(kids))
	}
	// Empty set yields cols spacer children.
	kids = cellsForRow(nil, 0, 8, func(gtx layout.Context, idx int, e string) layout.Dimensions {
		return layout.Dimensions{}
	})
	if len(kids) != 8 {
		t.Errorf("empty set returns %d children, want 8", len(kids))
	}
}
