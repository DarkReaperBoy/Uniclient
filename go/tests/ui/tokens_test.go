package tests

import (
	"testing"

	. "uniclient/ui/tokens"
)

func TestWindowGeometrySane(t *testing.T) {
	if WindowMinWidth <= 0 || WindowMinHeight <= 0 {
		t.Fatalf("min window non-positive: %dx%d", WindowMinWidth, WindowMinHeight)
	}
	if WindowMinWidth > WindowDefaultWidth || WindowMinHeight > WindowDefaultHeight {
		t.Fatalf("min %dx%d exceeds default %dx%d",
			WindowMinWidth, WindowMinHeight, WindowDefaultWidth, WindowDefaultHeight)
	}
	if WindowDefaultWidth > WindowBigDefaultWidth || WindowDefaultHeight > WindowBigDefaultHeight {
		t.Fatalf("default %dx%d exceeds big default %dx%d",
			WindowDefaultWidth, WindowDefaultHeight, WindowBigDefaultWidth, WindowBigDefaultHeight)
	}
}

func TestPanesSane(t *testing.T) {
	if ColumnMinWidthLeft <= 0 || ColumnMinWidthLeft >= ColumnMaxWidthLeft {
		t.Fatalf("left pane range invalid: [%d, %d]", ColumnMinWidthLeft, ColumnMaxWidthLeft)
	}
	if ColumnMinWidthMain <= 0 {
		t.Fatalf("main pane minimum non-positive: %d", ColumnMinWidthMain)
	}
	if ColumnMinWidthThird <= 0 || ColumnMinWidthThird >= ColumnMaxWidthThird {
		t.Fatalf("third pane range invalid: [%d, %d]", ColumnMinWidthThird, ColumnMaxWidthThird)
	}
	if AdaptiveChatWideWidth <= ColumnMinWidthMain {
		t.Fatalf("wide threshold %d must exceed main pane minimum %d",
			AdaptiveChatWideWidth, ColumnMinWidthMain)
	}
}

func TestDialogRowSane(t *testing.T) {
	if DialogsRowPadTop+DialogsRowPhotoSize+DialogsRowPadBottom != DialogsRowHeight {
		t.Fatalf("row height %d != paddings+photo %d+%d+%d",
			DialogsRowHeight, DialogsRowPadTop, DialogsRowPhotoSize, DialogsRowPadBottom)
	}
	if DialogsRowPadLeft+DialogsRowPhotoSize >= DialogsRowNameLeft {
		t.Fatalf("name x %d overlaps photo (pad %d + photo %d)",
			DialogsRowNameLeft, DialogsRowPadLeft, DialogsRowPhotoSize)
	}
	if DialogsRowNameTop >= DialogsRowTextTop || DialogsRowTextTop >= DialogsRowHeight {
		t.Fatalf("row text baselines out of order: name %d, text %d, height %d",
			DialogsRowNameTop, DialogsRowTextTop, DialogsRowHeight)
	}
	if DialogsSearchInHeight <= 0 {
		t.Fatalf("search block height non-positive: %d", DialogsSearchInHeight)
	}
}

func TestMainMenuGeometrySane(t *testing.T) {
	if MainMenuWidth <= 0 || MainMenuCoverHeight <= 0 {
		t.Fatalf("drawer frame non-positive: width %d, cover %d", MainMenuWidth, MainMenuCoverHeight)
	}
	if MainMenuUserpicSize > MainMenuCoverHeight {
		t.Fatalf("userpic %d taller than cover %d", MainMenuUserpicSize, MainMenuCoverHeight)
	}
	if !(MainMenuUserpicTop < MainMenuCoverNameTop &&
		MainMenuCoverNameTop < MainMenuCoverStatusTop &&
		MainMenuCoverStatusTop < MainMenuCoverHeight) {
		t.Fatalf("cover fields out of order: userpic %d, name %d, status %d, cover %d",
			MainMenuUserpicTop, MainMenuCoverNameTop, MainMenuCoverStatusTop, MainMenuCoverHeight)
	}
	if MainMenuButtonPadLeft <= MainMenuButtonIconLeft {
		t.Fatalf("button icon %d not inside left padding %d",
			MainMenuButtonIconLeft, MainMenuButtonPadLeft)
	}
	if MainMenuFooterHeightMin <= 0 || MainMenuSkip <= 0 {
		t.Fatalf("footer %d or skip %d non-positive", MainMenuFooterHeightMin, MainMenuSkip)
	}
}

func TestTypeScaleSane(t *testing.T) {
	if FontBase <= 0 {
		t.Fatalf("base font non-positive: %d", FontBase)
	}
	if FontBox <= FontBase {
		t.Fatalf("box font %d must exceed base %d", FontBox, FontBase)
	}
}

func TestLayoutDerivedFromPanes(t *testing.T) {
	if LayoutOneColumnMaxWidth != ColumnMinWidthLeft+ColumnMinWidthMain {
		t.Fatalf("one-column boundary %d != left+main %d+%d",
			LayoutOneColumnMaxWidth, ColumnMinWidthLeft, ColumnMinWidthMain)
	}
	if LayoutThreeColumnMinWidth != ColumnMinWidthLeft+ColumnMinWidthMain+ColumnMinWidthThird {
		t.Fatalf("three-column minimum %d != left+main+third %d+%d+%d",
			LayoutThreeColumnMinWidth, ColumnMinWidthLeft, ColumnMinWidthMain, ColumnMinWidthThird)
	}
	if LayoutOneColumnMaxWidth != 640 || LayoutThreeColumnMinWidth != 932 {
		t.Fatalf("measured boundaries drifted: one-col %d (want 640), three-col %d (want 932)",
			LayoutOneColumnMaxWidth, LayoutThreeColumnMinWidth)
	}
	if LayoutOneColumnMaxWidth >= LayoutThreeColumnMinWidth {
		t.Fatalf("boundaries inverted: %d >= %d", LayoutOneColumnMaxWidth, LayoutThreeColumnMinWidth)
	}
	if DialogsWidthRatioDefault <= 0 || DialogsWidthRatioDefault >= 1 {
		t.Fatalf("dialogs ratio out of range: %v", DialogsWidthRatioDefault)
	}
	if ThirdColumnWidthDefault >= ColumnMinWidthThird {
		t.Fatalf("third column default %d must clamp up to min %d when shown",
			ThirdColumnWidthDefault, ColumnMinWidthThird)
	}
}

func TestDefaultMainMenuTree(t *testing.T) {
	want := []string{
		"my_profile",
		"bots",
		"",
		"new_group",
		"new_channel",
		"contacts",
		"calls",
		"saved_messages",
		"sread",
		"settings",
		"night_mode",
		"ghost_mode",
	}
	if len(DefaultMainMenu) != len(want) {
		t.Fatalf("default menu has %d entries, want %d", len(DefaultMainMenu), len(want))
	}
	seen := map[string]bool{}
	for i, e := range DefaultMainMenu {
		if e.ID != want[i] {
			t.Fatalf("menu entry %d is %q, want %q", i, e.ID, want[i])
		}
		if e.Kind == MenuSeparator {
			if e.ID != "" {
				t.Fatalf("separator at %d carries id %q", i, e.ID)
			}
			if i == 0 || i == len(DefaultMainMenu)-1 {
				t.Fatalf("separator at edge position %d", i)
			}
			continue
		}
		if e.ID == "" {
			t.Fatalf("entry %d has empty id", i)
		}
		if e.Kind == MenuBotList {
			continue
		}
		if e.Icon == "" || e.Label == "" {
			t.Fatalf("entry %d incomplete: icon=%q label=%q", i, e.Icon, e.Label)
		}
		if seen[e.ID] {
			t.Fatalf("duplicate menu id %q", e.ID)
		}
		seen[e.ID] = true
	}
	toggles := 0
	for _, e := range DefaultMainMenu {
		if e.Kind == MenuToggle {
			toggles++
		}
	}
	if toggles != 3 {
		t.Fatalf("default menu has %d toggles, want 3 (sread, night_mode, ghost_mode)", toggles)
	}
	if DefaultMainMenu[1].Kind != MenuBotList {
		t.Fatalf("entry 1 must be the dynamic bot list, got kind %d", DefaultMainMenu[1].Kind)
	}
}
