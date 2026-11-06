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

func TestHistoryBubblesSane(t *testing.T) {
	if MsgPaddingLeft != MsgPaddingRight || MsgPaddingLeft <= 0 || MsgPaddingTop <= 0 {
		t.Fatalf("bubble padding asymmetric or non-positive: %d/%d/%d/%d",
			MsgPaddingLeft, MsgPaddingTop, MsgPaddingRight, MsgPaddingBottom)
	}
	if MsgMarginRight <= MsgMarginLeft {
		t.Fatalf("right margin %d must exceed left %d (date+ticks reserve)",
			MsgMarginRight, MsgMarginLeft)
	}
	if MsgMarginTopAttached >= MsgMarginTop {
		t.Fatalf("attached top margin %d must be tighter than %d",
			MsgMarginTopAttached, MsgMarginTop)
	}
	if MsgPhotoSkip < MsgPhotoSize {
		t.Fatalf("photo skip %d smaller than photo %d", MsgPhotoSkip, MsgPhotoSize)
	}
	if BubbleWideMaxWidth != MsgMaxWidth+2*MsgPhotoSkip+2*MsgMarginLeft {
		t.Fatalf("wide bubble width %d != formula", BubbleWideMaxWidth)
	}
	if BubbleWideMaxWidth != 542 || MsgMaxWidth != 430 {
		t.Fatalf("measured bubble widths drifted: max %d (want 430), wide %d (want 542)",
			MsgMaxWidth, BubbleWideMaxWidth)
	}
}

func TestBubbleRadiusSane(t *testing.T) {
	if BubbleRadiusSmall >= BubbleRadiusLarge {
		t.Fatalf("radius order inverted: small %d, large %d",
			BubbleRadiusSmall, BubbleRadiusLarge)
	}
	if MsgFileThumbRadiusSmall >= MsgFileThumbRadiusLarge {
		t.Fatalf("thumb radius order inverted: %d, %d",
			MsgFileThumbRadiusSmall, MsgFileThumbRadiusLarge)
	}
	if BubbleRadiusSliderMax != BubbleRadiusLarge || AyuMessageBubbleRadiusDefault != BubbleRadiusSliderMax {
		t.Fatalf("ayu default %d must sit at slider max %d == large %d",
			AyuMessageBubbleRadiusDefault, BubbleRadiusSliderMax, BubbleRadiusLarge)
	}
	if BubbleRadiusSmall != 6 || BubbleRadiusLarge != 16 {
		t.Fatalf("measured radii drifted: small %d (want 6), large %d (want 16)",
			BubbleRadiusSmall, BubbleRadiusLarge)
	}
}

func TestServiceMessagesSane(t *testing.T) {
	if MsgServiceMarginBottom >= MsgServiceMarginTop {
		t.Fatalf("service margin bottom %d must be tighter than top %d",
			MsgServiceMarginBottom, MsgServiceMarginTop)
	}
	if MsgServicePadLeft != MsgServicePadRight || MsgServicePadLeft <= 0 {
		t.Fatalf("service padding asymmetric or non-positive: %d/%d",
			MsgServicePadLeft, MsgServicePadRight)
	}
	if HistoryUnreadBarHeight <= 0 || HistoryUnreadBarMargin <= 0 || HistoryPaddingBottom <= 0 {
		t.Fatalf("history list metrics non-positive: bar %d, margin %d, bottom %d",
			HistoryUnreadBarHeight, HistoryUnreadBarMargin, HistoryPaddingBottom)
	}
}

func TestComposerSane(t *testing.T) {
	if !(ComposeFieldHeightMin < ComposeFieldHeightMax && ComposeFieldHeightMax < ComposeFieldRichMax) {
		t.Fatalf("field growth chain broken: %d/%d/%d",
			ComposeFieldHeightMin, ComposeFieldHeightMax, ComposeFieldRichMax)
	}
	if HistorySendSizeW != HistoryAttachSizeW || HistorySendSizeH != HistoryAttachSizeH {
		t.Fatalf("send %dx%d and attach %dx%d differ",
			HistorySendSizeW, HistorySendSizeH, HistoryAttachSizeW, HistoryAttachSizeH)
	}
	if ComposePadLeft != ComposePadRight {
		t.Fatalf("composer padding asymmetric: %d/%d", ComposePadLeft, ComposePadRight)
	}
	if ComposePadLeft != HistorySendRight {
		t.Fatalf("composer horizontal rhythm broken: pad %d, sendRight %d",
			ComposePadLeft, HistorySendRight)
	}
	if ComposerRestHeight != ComposePadTop+ComposeFieldHeightMin+ComposePadBottom {
		t.Fatalf("composer rest height %d != formula", ComposerRestHeight)
	}
	if ComposerRestHeight != 54 || ComposeFieldHeightMin != 36 || HistorySendSizeH != 46 {
		t.Fatalf("measured composer metrics drifted: rest %d (want 54), field %d (want 36), sendH %d (want 46)",
			ComposerRestHeight, ComposeFieldHeightMin, HistorySendSizeH)
	}
}

func TestBoxesSane(t *testing.T) {
	if BoxWidth >= BoxWideWidth || BoxWidth <= 0 {
		t.Fatalf("box widths inverted: %d/%d", BoxWidth, BoxWideWidth)
	}
	if BoxPadLeft != BoxTitlePosX {
		t.Fatalf("box left rhythm broken: pad %d, title x %d", BoxPadLeft, BoxTitlePosX)
	}
	if BoxPadLeft != BoxRowPadLeft {
		t.Fatalf("box row left drift: pad %d, row pad %d", BoxPadLeft, BoxRowPadLeft)
	}
	if !(BoxTitlePosY+BoxTitleMaxHeight <= BoxTitleHeight) {
		t.Fatalf("title %d+%d overflows title bar %d",
			BoxTitlePosY, BoxTitleMaxHeight, BoxTitleHeight)
	}
	if BoxButtonHeight != 34 || BoxWidth != 320 || BoxWideWidth != 364 {
		t.Fatalf("measured box metrics drifted: button %d (want 34), width %d (want 320), wide %d (want 364)",
			BoxButtonHeight, BoxWidth, BoxWideWidth)
	}
	if BoxMaxListHeight <= 0 || BoxLittleSkip <= 0 || BoxMediumSkip <= BoxLittleSkip {
		t.Fatalf("box skips broken: maxList %d, little %d, medium %d",
			BoxMaxListHeight, BoxLittleSkip, BoxMediumSkip)
	}
	if BoxRadius != 6 || FontBoxTitle != 16 {
		t.Fatalf("box radius %d (want 6) or title font %d (want 16)", BoxRadius, FontBoxTitle)
	}
}

func TestMenuSane(t *testing.T) {
	if MenuItemPadTop <= MenuItemPadBottom {
		t.Fatalf("menu padding inverted: top %d, bottom %d", MenuItemPadTop, MenuItemPadBottom)
	}
	if MenuWidthMin >= MenuWidthMax {
		t.Fatalf("menu widths inverted: %d/%d", MenuWidthMin, MenuWidthMax)
	}
	if MenuItemHeightFor(13) != 13+MenuItemPadTop+MenuItemPadBottom {
		t.Fatalf("menu row height formula broken")
	}
	if MenuItemHeightFor(FontBase) != 28 {
		t.Fatalf("measured menu row drifted: %d (want 28)", MenuItemHeightFor(FontBase))
	}
	if MenuRadius != 6 || MenuShowDurationMs != 200 || MenuDurationMs != 150 {
		t.Fatalf("menu chrome drifted: radius %d, show %d, anim %d",
			MenuRadius, MenuShowDurationMs, MenuDurationMs)
	}
}

func TestTogglesSane(t *testing.T) {
	if ToggleDiameter <= 0 || ToggleBorder <= 0 {
		t.Fatalf("toggle non-positive: diameter %d, border %d", ToggleDiameter, ToggleBorder)
	}
	if ToggleDurationMs <= 0 {
		t.Fatalf("toggle duration non-positive: %d", ToggleDurationMs)
	}
	if ToggleDiameter != 14 || ToggleBorder != 2 {
		t.Fatalf("measured toggle drifted: diameter %d (want 14), border %d (want 2)",
			ToggleDiameter, ToggleBorder)
	}
}

func TestSettingsRowsSane(t *testing.T) {
	if SettingsRowHeightText != 20 || SettingsRowPadTop != 10 || SettingsRowPadBottom != 8 {
		t.Fatalf("settings default row drifted: text %d, padTop %d, padBottom %d (want 20/10/8)",
			SettingsRowHeightText, SettingsRowPadTop, SettingsRowPadBottom)
	}
	if MainMenuRowHeight() != 13+MainMenuButtonPadTop+MainMenuButtonPadBottom {
		t.Fatalf("main-menu row formula broken (semibold 13 + 11 + 9 = 33)")
	}
	if MainMenuRowHeight() != 33 {
		t.Fatalf("measured main-menu row drifted: %d (want 33)", MainMenuRowHeight())
	}
}
