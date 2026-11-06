package tests

import (
	"testing"

	. "uniclient/ui/tokens"
)

func TestMenuIconBoxesSane(t *testing.T) {
	if MenuIconSize != 24 {
		t.Fatalf("menu icon size drifted: %d (want 24)", MenuIconSize)
	}
	if MenuIconPosY+MenuIconSize != MenuWithIconsPadTop+FontBase+MenuWithIconsPadBottom {
		t.Fatalf("icon not flush with row: icon bottom %d+%d != row %d+%d+%d",
			MenuIconPosY, MenuIconSize,
			MenuWithIconsPadTop, FontBase, MenuWithIconsPadBottom)
	}
	if MenuWithIconsPadLeft < MenuIconPosX+MenuIconSize+10 {
		t.Fatalf("text starts inside icon box: pad %d, icon ends %d",
			MenuWithIconsPadLeft, MenuIconPosX+MenuIconSize)
	}
	if MenuWithIconsPadRight != MenuItemPadRight {
		t.Fatalf("menu right rhythm broken: with-icons %d, default %d",
			MenuWithIconsPadRight, MenuItemPadRight)
	}
	if MenuIconPosX <= 0 || MenuIconPosY < 0 {
		t.Fatalf("icon origin invalid: %d,%d", MenuIconPosX, MenuIconPosY)
	}
}

func TestWindowChromeSane(t *testing.T) {
	if WindowTitleHeight != 24 {
		t.Fatalf("title height drifted: %d (want 24)", WindowTitleHeight)
	}
	if WindowTitleButtonWidth != 36 {
		t.Fatalf("title button width drifted: %d (want 36)", WindowTitleButtonWidth)
	}
	if WindowTitleButtonWidth <= WindowTitleHeight {
		t.Fatalf("title button %d not wider than bar %d",
			WindowTitleButtonWidth, WindowTitleHeight)
	}
	if FontWindowTitle != 12 || FontWindowTitle >= FontBase {
		t.Fatalf("title font drifted: %d (want 12 below base %d)",
			FontWindowTitle, FontBase)
	}
}

func TestTopBarSane(t *testing.T) {
	if TopBarHeight != 54 {
		t.Fatalf("top bar height drifted: %d (want 54)", TopBarHeight)
	}
	if TopBarTitleLeft != 24 || TopBarTitleTop != 17 || TopBarTitleMaxHeight != 20 {
		t.Fatalf("top bar title geometry drifted: %d/%d/%d (want 24/17/20)",
			TopBarTitleLeft, TopBarTitleTop, TopBarTitleMaxHeight)
	}
	if TopBarTitleTop+TopBarTitleMaxHeight > TopBarHeight {
		t.Fatalf("title %d+%d overflows bar %d",
			TopBarTitleTop, TopBarTitleMaxHeight, TopBarHeight)
	}
	if FontTopBarTitle != 14 || FontTopBarTitle <= FontBase || FontTopBarTitle >= FontBoxTitle {
		t.Fatalf("top bar title font drifted: %d (want 14 between %d and %d)",
			FontTopBarTitle, FontBase, FontBoxTitle)
	}
	if !(TopBarButtonWidth < TopBarMenuButtonWidth && TopBarMenuButtonWidth < TopBarBackButtonWidth) {
		t.Fatalf("top bar button widths out of order: %d/%d/%d",
			TopBarButtonWidth, TopBarMenuButtonWidth, TopBarBackButtonWidth)
	}
	if TopBarIconSize != 32 || TopBarIconSize > TopBarButtonWidth {
		t.Fatalf("top bar icon size %d exceeds button width %d",
			TopBarIconSize, TopBarButtonWidth)
	}
	if TopBarRippleSize != 40 || TopBarRippleSize > TopBarButtonWidth {
		t.Fatalf("top bar ripple %d exceeds button width %d",
			TopBarRippleSize, TopBarButtonWidth)
	}
	if VerticalCenterOffset(TopBarHeight, TopBarRippleSize) != 7 {
		t.Fatalf("ripple not centered: offset %d (want 7)",
			VerticalCenterOffset(TopBarHeight, TopBarRippleSize))
	}
	if VerticalCenterOffset(TopBarButtonWidth, TopBarIconSize) != 4 ||
		VerticalCenterOffset(TopBarHeight, TopBarIconSize) != 11 {
		t.Fatalf("top bar icon not centered: %d/%d (want 4/11)",
			VerticalCenterOffset(TopBarButtonWidth, TopBarIconSize),
			VerticalCenterOffset(TopBarHeight, TopBarIconSize))
	}
	if DialogsMenuButtonSize != 40 {
		t.Fatalf("dialogs menu button drifted: %d (want 40)", DialogsMenuButtonSize)
	}
	if DialogsMenuButtonSize != TopBarButtonWidth {
		t.Fatalf("dialogs menu button %d != top bar button %d",
			DialogsMenuButtonSize, TopBarButtonWidth)
	}
	if VerticalCenterOffset(DialogsMenuButtonSize, TopBarIconSize) != 4 {
		t.Fatalf("dialogs menu icon not centered: %d (want 4)",
			VerticalCenterOffset(DialogsMenuButtonSize, TopBarIconSize))
	}
	if !(DialogsSearchFromWidth < DialogsCalendarWidth && DialogsCalendarWidth < DialogsMenuButtonSize) {
		t.Fatalf("dialogs button widths out of order: %d/%d/%d",
			DialogsSearchFromWidth, DialogsCalendarWidth, DialogsMenuButtonSize)
	}
	if DialogsCalendarHeight != 35 {
		t.Fatalf("dialogs calendar height drifted: %d (want 35)", DialogsCalendarHeight)
	}
}

func TestCheckboxSane(t *testing.T) {
	if CheckDiameter != 22 || CheckThickness != 2 {
		t.Fatalf("check geometry drifted: diameter %d (want 22), thickness %d (want 2)",
			CheckDiameter, CheckThickness)
	}
	if CheckDurationMs != 120 || CheckRipplePad != 8 {
		t.Fatalf("check timing drifted: duration %d (want 120), ripple pad %d (want 8)",
			CheckDurationMs, CheckRipplePad)
	}
	if CheckIconWidth != 14 || CheckIconHeight != 10 ||
		CheckIconPosX != 4 || CheckIconPosY != 7 {
		t.Fatalf("check mark box drifted: %dx%d at %d,%d (want 14x10 at 4,7)",
			CheckIconWidth, CheckIconHeight, CheckIconPosX, CheckIconPosY)
	}
	if CheckIconPosX+CheckIconWidth > CheckDiameter || CheckIconPosY+CheckIconHeight > CheckDiameter {
		t.Fatalf("check mark overflows circle: %d+%d / %d+%d vs %d",
			CheckIconPosX, CheckIconWidth, CheckIconPosY, CheckIconHeight, CheckDiameter)
	}
	if CheckboxMargin != 8 || CheckboxTextPosX != 10 || CheckboxTextPosY != 2 ||
		CheckboxCheckPosX != 8 || CheckboxCheckPosY != 8 {
		t.Fatalf("checkbox layout drifted: margin %d, text %d,%d, check %d,%d (want 8, 10,2, 8,8)",
			CheckboxMargin, CheckboxTextPosX, CheckboxTextPosY, CheckboxCheckPosX, CheckboxCheckPosY)
	}
	if CheckboxCheckPosX+CheckDiameter+CheckboxTextPosX != 40 {
		t.Fatalf("text skip law broken: %d+%d+%d != 40",
			CheckboxCheckPosX, CheckDiameter, CheckboxTextPosX)
	}
	if CheckboxMargin+CheckboxTextPosY != 10 {
		t.Fatalf("text top law broken: %d+%d != 10", CheckboxMargin, CheckboxTextPosY)
	}
	if CheckboxDisabledOpacity != 0.5 ||
		CheckboxDisabledOpacity <= 0 || CheckboxDisabledOpacity >= 1 {
		t.Fatalf("disabled opacity drifted: %v (want 0.5)", CheckboxDisabledOpacity)
	}
}

func TestRippleTimingsSane(t *testing.T) {
	if RippleShowDurationMs != 650 || RippleHideDurationMs != 200 {
		t.Fatalf("ripple timings drifted: show %d, hide %d (want 650/200)",
			RippleShowDurationMs, RippleHideDurationMs)
	}
	if RippleShowDurationMs <= RippleHideDurationMs || RippleHideDurationMs <= 0 {
		t.Fatalf("ripple order inverted: show %d, hide %d",
			RippleShowDurationMs, RippleHideDurationMs)
	}
	if RippleHideDurationMs < ToggleDurationMs {
		t.Fatalf("ripple hide %d shorter than toggle animation %d",
			RippleHideDurationMs, ToggleDurationMs)
	}
}

func TestScrollbarSane(t *testing.T) {
	if ScrollBarWidth != 10 || ScrollBarRadius != 2 {
		t.Fatalf("scrollbar chrome drifted: width %d (want 10), radius %d (want 2)",
			ScrollBarWidth, ScrollBarRadius)
	}
	if ScrollBarRadius > ScrollBarWidth/2 {
		t.Fatalf("scrollbar radius %d exceeds half width %d",
			ScrollBarRadius, ScrollBarWidth)
	}
	if ScrollBarMinHeight != 20 || ScrollBarThumbMin != 40 {
		t.Fatalf("scrollbar heights drifted: min %d (want 20), thumb %d (want 40)",
			ScrollBarMinHeight, ScrollBarThumbMin)
	}
	if ScrollBarThumbMin < ScrollBarMinHeight || ScrollBarThumbMin < 2*ScrollBarMinHeight {
		t.Fatalf("thumb minimum %d under bar minimum %d", ScrollBarThumbMin, ScrollBarMinHeight)
	}
	if ScrollBarDeltax != 3 || ScrollBarDeltat != 3 || ScrollBarDeltab != 3 {
		t.Fatalf("scrollbar insets drifted: %d/%d/%d (want 3/3/3)",
			ScrollBarDeltax, ScrollBarDeltat, ScrollBarDeltab)
	}
	if ScrollDurationMs != 150 || ScrollHidingMs != 1000 {
		t.Fatalf("scrollbar timings drifted: duration %d (want 150), hiding %d (want 1000)",
			ScrollDurationMs, ScrollHidingMs)
	}
	if ScrollHidingMs <= ScrollDurationMs {
		t.Fatalf("hiding %d not longer than duration %d", ScrollHidingMs, ScrollDurationMs)
	}
}

func TestToastSane(t *testing.T) {
	if ToastPadLeft != 19 || ToastPadRight != 19 || ToastPadTop != 13 || ToastPadBottom != 12 {
		t.Fatalf("toast padding drifted: %d/%d/%d/%d (want 19/13/19/12)",
			ToastPadLeft, ToastPadTop, ToastPadRight, ToastPadBottom)
	}
	if ToastPadLeft != ToastPadRight || ToastPadTop <= ToastPadBottom || ToastPadBottom <= 0 {
		t.Fatalf("toast padding law broken: %d/%d/%d/%d",
			ToastPadLeft, ToastPadTop, ToastPadRight, ToastPadBottom)
	}
	if ToastMargin != 13 || ToastMargin <= 0 {
		t.Fatalf("toast margin drifted: %d (want 13)", ToastMargin)
	}
	if ToastMaxWidth != 480 || ToastMaxWidth < 2*(ToastMargin+ToastPadLeft) {
		t.Fatalf("toast width law broken: %d (want 480)", ToastMaxWidth)
	}
	if ToastRadius != 8 {
		t.Fatalf("toast radius drifted: %d (want 8)", ToastRadius)
	}
	if ToastFadeInMs != 200 || ToastFadeOutMs != 1000 || ToastSlideMs != 160 {
		t.Fatalf("toast timings drifted: in %d, out %d, slide %d (want 200/1000/160)",
			ToastFadeInMs, ToastFadeOutMs, ToastSlideMs)
	}
	if ToastFadeOutMs <= ToastFadeInMs || ToastFadeInMs <= 0 || ToastSlideMs <= 0 {
		t.Fatalf("toast timing order broken: %d/%d/%d",
			ToastFadeInMs, ToastFadeOutMs, ToastSlideMs)
	}
}

func TestVerticalCenterOffset(t *testing.T) {
	cases := []struct {
		container int
		content   int
		want      int
	}{
		{24, 24, 0},
		{TopBarButtonWidth, TopBarIconSize, 4},
		{TopBarHeight, TopBarIconSize, 11},
		{TopBarHeight, TopBarRippleSize, 7},
		{DialogsMenuButtonSize, TopBarIconSize, 4},
		{29, 24, 2},
		{40, 16, 12},
		{27, 24, 1},
		{25, 24, 0},
		{20, 25, -2},
		{0, 0, 0},
	}
	for _, c := range cases {
		if got := VerticalCenterOffset(c.container, c.content); got != c.want {
			t.Fatalf("VerticalCenterOffset(%d, %d) = %d, want %d",
				c.container, c.content, got, c.want)
		}
	}
	if VerticalCenterOffset(TopBarButtonWidth, TopBarIconSize)+
		TopBarIconSize+
		VerticalCenterOffset(TopBarButtonWidth, TopBarIconSize) != TopBarButtonWidth {
		t.Fatalf("centering does not partition the button: %d+%d+%d != %d",
			VerticalCenterOffset(TopBarButtonWidth, TopBarIconSize),
			TopBarIconSize,
			VerticalCenterOffset(TopBarButtonWidth, TopBarIconSize),
			TopBarButtonWidth)
	}
}
