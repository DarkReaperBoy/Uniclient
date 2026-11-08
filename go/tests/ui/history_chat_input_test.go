package tests

import (
	"testing"

	. "uniclient/ui/dialogs"
	"uniclient/ui/history"
)

func chatList(heights ...int) history.List {
	items := make([]history.Item, len(heights))
	for i := range items {
		items[i] = history.Item{Kind: history.ItemMessage, Text: "m"}
	}
	return history.List{Items: items, Heights: heights}
}

func TestHistoryRowAt(t *testing.T) {
	l := chatList(50, 30, 20)
	cases := []struct {
		y    int
		want int
	}{
		{-1, -1},
		{0, 0},
		{49, 0},
		{50, 1},
		{79, 1},
		{80, 2},
		{99, 2},
		{100, -1},
		{1000, -1},
	}
	for _, c := range cases {
		if got := l.RowAt(c.y); got != c.want {
			t.Fatalf("RowAt(%d) = %d, want %d", c.y, got, c.want)
		}
	}
	empty := history.List{}
	if got := empty.RowAt(0); got != -1 {
		t.Fatalf("empty RowAt(0) = %d, want -1", got)
	}
}

func TestHistoryConsumeScrollAction(t *testing.T) {
	l := chatList(50, 50)
	if l.ConsumeScrollAction(0, -40, true, 10) {
		t.Fatal("classic vertical delta must not consume")
	}
	if l.ConsumeScrollAction(2, -40, true, 10) {
		t.Fatal("classic vertical-dominant delta must not consume")
	}
	if l.ConsumeScrollAction(-40, 0, true, 10) {
		t.Fatal("text item must not consume horizontal scroll")
	}
	if l.ConsumeScrollAction(-40, 0, true, 999) {
		t.Fatal("no item under y must not consume")
	}
	if l.ConsumeScrollAction(-40, 2, false, 10) {
		t.Fatal("phased horizontal delta over text must not consume")
	}
}

func TestHistoryChatBottomRequest(t *testing.T) {
	cases := []struct {
		top, delta, max int
		want            bool
	}{
		{80, 30, 80, true},
		{80, 1, 80, true},
		{50, 30, 80, false},
		{50, 29, 80, false},
		{80, -30, 80, false},
		{0, 0, 0, false},
		{0, 5, 0, true},
		{90, 5, 80, true},
	}
	for _, c := range cases {
		if got := history.ChatBottomRequest(c.top, c.delta, c.max); got != c.want {
			t.Fatalf("ChatBottomRequest(%d,%d,%d) = %v, want %v",
				c.top, c.delta, c.max, got, c.want)
		}
	}
}

func TestFlingDeltaRoundsHalfAwayFromZero(t *testing.T) {
	cases := []struct {
		speed        TouchSpeed
		elapsed      int
		wantX, wantY int
	}{
		{TouchSpeed{X: 0, Y: -2000}, 15, 0, -30},
		{TouchSpeed{X: 0, Y: -1985}, 15, 0, -30},
		{TouchSpeed{X: 0, Y: 1970}, 15, 0, 30},
		{TouchSpeed{X: 999, Y: 0}, 1, 1, 0},
		{TouchSpeed{X: -499, Y: 0}, 1, 0, 0},
		{TouchSpeed{X: -500, Y: 0}, 1, -1, 0},
		{TouchSpeed{X: 0, Y: 2500}, 40, 0, 100},
	}
	for _, c := range cases {
		gotX, gotY := FlingDelta(c.speed, c.elapsed)
		if gotX != c.wantX || gotY != c.wantY {
			t.Fatalf("FlingDelta(%v,%d) = (%d,%d), want (%d,%d)",
				c.speed, c.elapsed, gotX, gotY, c.wantX, c.wantY)
		}
	}
}

func TestTouchSpeedSampleAccelerationUsesManualBlend(t *testing.T) {
	prev := TouchSpeed{X: 0, Y: -1985}
	got := TouchSpeedSample(prev, 0, -10, 10, false)
	if got.Y != -1246 {
		t.Fatalf("manual blend during acceleration = %d, want -1246 (-1985/4 - 1000*3/4)", got.Y)
	}
	got = TouchSpeedSample(prev, 0, -10, 10, true)
	if got.Y != -1985+-250 {
		t.Fatalf("auto blend = %d, want -2235", got.Y)
	}
}
