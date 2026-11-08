package tests

import (
	"testing"

	"uniclient/ui/history"
	"uniclient/ui/tokens"
)

func TestSendButtonSizes(t *testing.T) {
	widths := map[history.SendButtonType]int{
		history.SendTypeSend:     44,
		history.SendTypeSchedule: 44,
		history.SendTypeSlowmode: 44,
		history.SendTypeSave:     44,
		history.SendTypeCancel:   44,
		history.SendTypeRecord:   44,
		history.SendTypeRound:    44,
		history.SendTypeStop:     44,
	}
	for ty, want := range widths {
		if got := history.SendButtonWidth(ty); got != want {
			t.Fatalf("SendButtonWidth(%d) = %d, want %d — inner.width historySendSize 44 (updateSize 676-683)", ty, got, want)
		}
	}
	if got := history.SendButtonWidth(history.SendTypeEditPrice); got != 0 {
		t.Fatalf("EditPrice width = %d, want 0 — updateSize: EditPrice resizes to (0, inner.height)", got)
	}
	if got := history.SendButtonHeight(); got != 46 {
		t.Fatalf("SendButtonHeight() = %d, want 46 — inner.height historySendSizeH (updateSize)", got)
	}
}

func TestSendButtonRipple(t *testing.T) {
	want := history.Geometry{Left: 2, Top: 3, Width: 40, Height: 40}
	for _, ty := range []history.SendButtonType{
		history.SendTypeSend, history.SendTypeSchedule, history.SendTypeSlowmode,
		history.SendTypeSave, history.SendTypeCancel, history.SendTypeRecord,
		history.SendTypeRound, history.SendTypeStop,
	} {
		if got := history.SendButtonRipple(ty); got != want {
			t.Fatalf("SendButtonRipple(%d) = %+v, want %+v — ((44 - rippleAreaSize 40)/2, rippleAreaPosition.y 3) (send_button.cpp 234-237, 279-282)", ty, got, want)
		}
	}
}

func TestSendButtonStopRect(t *testing.T) {
	if got := history.SendButtonStopRect(44, 46); got != (history.Geometry{Left: 15, Top: 16, Width: 14, Height: 14}) {
		t.Fatalf("stop rect = %+v, want {15 16 14 14} — stopSize 14x14 centered, radius 3 (paintStop 296-308)", got)
	}
	if got := history.SendButtonStopRect(40, 40); got != (history.Geometry{Left: 13, Top: 13, Width: 14, Height: 14}) {
		t.Fatalf("stop rect odd = %+v, want {13 13 14 14} — C++ int division truncates", got)
	}
}

func TestSlowmodeDelayText(t *testing.T) {
	cases := []struct {
		seconds int
		want    string
	}{
		{0, ""},
		{5, "0:05"},
		{59, "0:59"},
		{60, "1:00"},
		{65, "1:05"},
		{600, "10:00"},
		{3599, "59:59"},
		{3600, "60:00"},
	}
	for _, c := range cases {
		if got := history.SlowmodeDelayText(c.seconds); got != c.want {
			t.Fatalf("SlowmodeDelayText(%d) = %q, want %q — minutes = s/60, seconds%%60 padded to 2 with '0'; 0 -> empty (setState 91-97)", c.seconds, got, c.want)
		}
	}
}

func TestSlowmodeTextRect(t *testing.T) {
	if got := history.SlowmodeTextRect(44, 46); got != (history.Geometry{Left: 0, Top: 0, Width: 34, Height: 46}) {
		t.Fatalf("slowmode text rect = %+v, want {0 0 34 46} — rect().marginsRemoved(historySlowmodeCounterMargins 0,0,10,0) (paintSlowmode 331-338)", got)
	}
}

func TestSendButtonTokens(t *testing.T) {
	if tokens.HistorySendIconPositionX != 10 || tokens.HistorySendIconPositionY != 11 {
		t.Fatalf("send icon position drifted: (%d, %d), want (10, 11) — historySend sendIconPosition (chat_helpers.style 1498)", tokens.HistorySendIconPositionX, tokens.HistorySendIconPositionY)
	}
	if tokens.HistoryScheduleIconPositionX != 7 || tokens.HistoryScheduleIconPositionY != 8 {
		t.Fatalf("schedule icon position drifted: (%d, %d), want (7, 8) — historyScheduleIconPosition (chat_helpers.style 1407)", tokens.HistoryScheduleIconPositionX, tokens.HistoryScheduleIconPositionY)
	}
	if tokens.HistoryStopSizeW != 14 || tokens.HistoryStopSizeH != 14 || tokens.HistoryStopRadius != 3 {
		t.Fatalf("stop tokens drifted: %dx%d r%d, want 14x14 r3 — historySend stopSize/stopRadius (chat_helpers.style 1506-1507)", tokens.HistoryStopSizeW, tokens.HistoryStopSizeH, tokens.HistoryStopRadius)
	}
	if tokens.HistoryRecordSizeW != 26 || tokens.HistoryRecordSizeH != 26 {
		t.Fatalf("record size drifted: %dx%d, want 26x26 — historySend recordSize (chat_helpers.style 1505)", tokens.HistoryRecordSizeW, tokens.HistoryRecordSizeH)
	}
	if tokens.SendStateChangeDurationMs != 120 {
		t.Fatalf("state change duration drifted: %d, want 120 — universalDuration (lib_ui basic.style 135)", tokens.SendStateChangeDurationMs)
	}
	if tokens.HistorySlowmodeCounterRight != 10 {
		t.Fatalf("slowmode right margin drifted: %d, want 10 — historySlowmodeCounterMargins (chat_helpers.style 1013)", tokens.HistorySlowmodeCounterRight)
	}
}
