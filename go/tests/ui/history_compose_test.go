package tests

import (
	"testing"

	"uniclient/ui/history"
	"uniclient/ui/tokens"
)

func TestComposeBarHeight(t *testing.T) {
	cases := []struct {
		fieldHeight int
		want        int
	}{
		{36, 54},
		{46, 64},
		{72, 90},
		{28, 46},
	}
	for _, c := range cases {
		if got := history.ComposeBarHeight(c.fieldHeight); got != c.want {
			t.Fatalf("ComposeBarHeight(%d) = %d, want %d — fieldHeight + 2*historySendPadding (history_widget.cpp 8666: scroll loses fieldHeight + 2*9)", c.fieldHeight, got, c.want)
		}
	}
}

func TestComposeFieldMaxHeight(t *testing.T) {
	cases := []struct {
		paneHeight    int
		reservedAbove int
		replyShown    bool
		want          int
	}{
		{1000, 0, false, 224},
		{1000, 0, true, 224},
		{600, 0, true, 224},
		{300, 0, false, 224},
		{300, 49, false, 184},
		{250, 0, false, 183},
		{200, 0, false, 133},
		{200, 0, true, 84},
	}
	for _, c := range cases {
		if got := history.ComposeFieldMaxHeight(c.paneHeight, c.reservedAbove, c.replyShown); got != c.want {
			t.Fatalf("ComposeFieldMaxHeight(%d, %d, %v) = %d, want %d — min(224, pane - reserved - 18 - 49 - (49 if reply)) (computeMaxFieldHeight 9097-9115)", c.paneHeight, c.reservedAbove, c.replyShown, got, c.want)
		}
	}
}

func TestComposeFieldHeight(t *testing.T) {
	if got := history.ComposeFieldHeight(false, 50, 224); got != 28 {
		t.Fatalf("no-text-chat field height = %d, want 28 — historySendSize.height 46 - 2*historySendPadding 9 (fieldHeight 7402-7408)", got)
	}
	cases := []struct {
		contentHeight int
		maxHeight     int
		want          int
	}{
		{20, 224, 36},
		{36, 224, 36},
		{50, 224, 50},
		{72, 224, 72},
		{1000, 224, 224},
		{40, 30, 30},
		{20, 30, 30},
	}
	for _, c := range cases {
		if got := history.ComposeFieldHeight(true, c.contentHeight, c.maxHeight); got != c.want {
			t.Fatalf("ComposeFieldHeight(true, %d, %d) = %d, want %d — clamp(content, 36, max); max < 36 lowers the min (InputField setMaxHeight 2720-2725)", c.contentHeight, c.maxHeight, got, c.want)
		}
	}
}

func TestComposeBarGeometry(t *testing.T) {
	got := history.ComposeBarGeometry(720, 600, 46, history.ComposeButtons{Attach: true, Emoji: true})
	buttonsBottom := 600 - tokens.HistorySendSizeH
	if buttonsBottom != 554 {
		t.Fatalf("buttonsBottom sanity: %d, want 554", buttonsBottom)
	}
	if got.Attach != (history.Geometry{Left: 2, Top: 554, Width: 44, Height: 46}) {
		t.Fatalf("attach = %+v, want {2 554 44 46} — left run starts at historySendRight 2, buttonsBottom = paneH - historySendSizeH (moveFieldControls 7596-7612)", got.Attach)
	}
	if got.Field != (history.Geometry{Left: 46, Top: 545, Width: 586, Height: 46}) {
		t.Fatalf("field = %+v, want {46 545 586 46} — left = 2+44, top = paneH - fieldH - 9, width = W - 44 - 2 - 44 - 44 (moveFieldControls 7621 + updateFieldSize 7699-7703)", got.Field)
	}
	if got.Send != (history.Geometry{Left: 674, Top: 554, Width: 44, Height: 46}) {
		t.Fatalf("send = %+v, want {674 554 44 46} — moveToRight(historySendRight 2), buttonsBottom (moveFieldControls 7626)", got.Send)
	}
	if got.Emoji != (history.Geometry{Left: 630, Top: 554, Width: 44, Height: 46}) {
		t.Fatalf("emoji = %+v, want {630 554 44 46} — moveToRight(2 + send 44), buttonsBottom (moveFieldControls 7628-7630)", got.Emoji)
	}
	if got.Field.Left+got.Field.Width != got.Emoji.Left+2 {
		t.Fatalf("field right edge %d, want emoji left %d + 2 — updateFieldSize subtracts historySendRight once while both runs inset by 2: the reference's own 2px underlap (field bg paints under the toggle; both share historyComposeAreaBg)", got.Field.Left+got.Field.Width, got.Emoji.Left)
	}
}

func TestComposeBarGeometryVariants(t *testing.T) {
	sendWant := history.Geometry{Left: 674, Top: 554, Width: 44, Height: 46}
	noAttach := history.ComposeBarGeometry(720, 600, 46, history.ComposeButtons{Attach: false, Emoji: true})
	if noAttach.Attach != (history.Geometry{}) {
		t.Fatalf("hidden attach must be the zero rect, got %+v", noAttach.Attach)
	}
	if noAttach.Field.Left != 2 || noAttach.Field.Width != 630 {
		t.Fatalf("no-attach field = %+v, want left 2 width 630 — fieldWidth = W - 0 - 2 - 44 - 44 (updateFieldSize: attach term gated by the setting)", noAttach.Field)
	}
	noEmoji := history.ComposeBarGeometry(720, 600, 46, history.ComposeButtons{Attach: true, Emoji: false})
	if noEmoji.Emoji != (history.Geometry{}) {
		t.Fatalf("hidden emoji must be the zero rect, got %+v", noEmoji.Emoji)
	}
	if noEmoji.Field.Width != 630 {
		t.Fatalf("no-emoji field width = %d, want 630 — fieldWidth = W - 44 - 2 - 44 - 0 (updateFieldSize: emoji term gated by the setting)", noEmoji.Field.Width)
	}
	if noEmoji.Field.Left != 46 {
		t.Fatalf("no-emoji field left = %d, want 46", noEmoji.Field.Left)
	}
	if noEmoji.Send != sendWant {
		t.Fatalf("send must not move with emoji visibility, got %+v", noEmoji.Send)
	}
	none := history.ComposeBarGeometry(720, 600, 46, history.ComposeButtons{})
	if none.Field.Left != 2 || none.Field.Width != 674 {
		t.Fatalf("bare field = %+v, want left 2 width 674 — W - 2 - 44", none.Field)
	}
}

func TestComposeScrollHeight(t *testing.T) {
	cases := []struct {
		paneHeight  int
		fieldHeight int
		canSend     bool
		want        int
	}{
		{600, 46, true, 536},
		{600, 28, true, 554},
		{600, 72, true, 510},
		{600, 46, false, 600},
	}
	for _, c := range cases {
		if got := history.ComposeScrollHeight(c.paneHeight, c.fieldHeight, c.canSend); got != c.want {
			t.Fatalf("ComposeScrollHeight(%d, %d, %v) = %d, want %d — canSend: pane - (fieldHeight + 2*9); else the list keeps the pane (updateHistoryGeometry 8660-8666)", c.paneHeight, c.fieldHeight, c.canSend, got, c.want)
		}
	}
}

func TestComposeFieldWidth(t *testing.T) {
	cases := []struct {
		pane   int
		button history.ComposeButtons
		want   int
	}{
		{400, history.ComposeButtons{Attach: true, Emoji: true}, 266},
		{400, history.ComposeButtons{Attach: true, Emoji: false}, 310},
		{400, history.ComposeButtons{Attach: false, Emoji: true}, 310},
		{400, history.ComposeButtons{Attach: false, Emoji: false}, 354},
		{60, history.ComposeButtons{Attach: true, Emoji: true}, -74},
	}
	for _, c := range cases {
		if got := history.ComposeFieldWidth(c.pane, c.button); got != c.want {
			t.Fatalf("ComposeFieldWidth(%d, %+v) = %d, want %d", c.pane, c.button, got, c.want)
		}
	}
	geo := history.ComposeBarGeometry(400, 600, 36, history.ComposeButtons{Attach: true, Emoji: true})
	if geo.Field.Width != history.ComposeFieldWidth(400, history.ComposeButtons{Attach: true, Emoji: true}) {
		t.Fatalf("bar geometry field width %d disagrees with ComposeFieldWidth", geo.Field.Width)
	}
}
