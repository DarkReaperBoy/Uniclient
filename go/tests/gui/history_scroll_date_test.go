package tests

import (
	"testing"

	. "uniclient/ui/app"
	"uniclient/ui/history"
	"uniclient/ui/tokens"
)

func scrollDateItems() []history.Item {
	return []history.Item{
		{Kind: history.ItemMessage, Text: "a", DateText: "Jan 1", TimeText: "10:00"},
		{Kind: history.ItemMessage, Text: "b", DateText: "Jan 1", TimeText: "10:01"},
		{Kind: history.ItemMessage, Text: "c", DateText: "Jan 1", TimeText: "10:02"},
		{Kind: history.ItemMessage, Text: "d", DateText: "Jan 2", TimeText: "11:00"},
		{Kind: history.ItemMessage, Text: "e", DateText: "Jan 2", TimeText: "11:01"},
		{Kind: history.ItemMessage, Text: "f", DateText: "Jan 3", TimeText: "12:00"},
	}
}

func scrollDateModel(t *testing.T) Model {
	t.Helper()
	m, _ := Update(InitialModel(), Resized{Width: 800, Height: 120})
	m, _ = Update(m, ChatLoaded{Items: scrollDateItems()})
	m, _ = Update(m, ChatMeasured{Heights: uniformHeights(6, 50)})
	return m
}

func TestScrollDateTokens(t *testing.T) {
	if tokens.ScrollDateHideMs != 800 {
		t.Fatalf("hide timeout drifted: %d (want 800 — kScrollDateHideTimeout)",
			tokens.ScrollDateHideMs)
	}
	if tokens.ScrollDateHideOnDayCrossingMs != 3000 {
		t.Fatalf("day-crossing hide drifted: %d (want 3000 — kScrollDateHideOnDayCrossingTimeout)",
			tokens.ScrollDateHideOnDayCrossingMs)
	}
	if tokens.HistoryDateFadeMs != 200 {
		t.Fatalf("fade duration drifted: %d (want 200 — historyDateFadeDuration)",
			tokens.HistoryDateFadeMs)
	}
}

func TestScrollDateAnchor(t *testing.T) {
	l := history.List{Items: scrollDateItems(), Heights: uniformHeights(6, 50)}
	if row, off := l.ScrollDateAnchor(history.Viewport{Top: 130, Height: 120}); row != 2 || off != 30 {
		t.Fatalf("anchor = (%d, %d), want (2, 30)", row, off)
	}
	if row, _ := l.ScrollDateAnchor(history.Viewport{Top: 0, Height: 120}); row != 0 {
		t.Fatalf("anchor at 0 = %d, want 0", row)
	}
	if row, off := l.ScrollDateAnchor(history.Viewport{Top: 400, Height: 120}); row != 5 || off != 150 {
		t.Fatalf("anchor past end = (%d, %d), want (5, 150)", row, off)
	}
	sponsored := scrollDateItems()
	sponsored[2].Sponsored = true
	l2 := history.List{Items: sponsored, Heights: uniformHeights(6, 50)}
	if row, _ := l2.ScrollDateAnchor(history.Viewport{Top: 130, Height: 120}); row != 3 {
		t.Fatalf("sponsored anchor = %d, want 3 (skip sponsored downward)", row)
	}
	empty := history.List{}
	if row, _ := empty.ScrollDateAnchor(history.Viewport{Top: 0, Height: 120}); row != -1 {
		t.Fatalf("empty anchor = %d, want -1", row)
	}
}

func TestScrollDateAt(t *testing.T) {
	l := history.List{Items: scrollDateItems(), Heights: uniformHeights(6, 50)}
	bars := history.ComposeBars(l.Items)

	d := l.ScrollDateAt(history.Viewport{Top: 0, Height: 120}, bars)
	if d.Row != 0 || d.Top != 10 || !d.InPlace {
		t.Fatalf("top 0 = %+v, want {0 10 true}", d)
	}
	d = l.ScrollDateAt(history.Viewport{Top: 5, Height: 120}, bars)
	if d.Row != 0 || d.Top != 15 || !d.InPlace {
		t.Fatalf("top 5 = %+v, want {0 15 true} (pushed but still in place)", d)
	}
	d = l.ScrollDateAt(history.Viewport{Top: 25, Height: 120}, bars)
	if d.Row != 0 || d.Top != 35 || d.InPlace {
		t.Fatalf("top 25 = %+v, want {0 35 false} (past the in-place window)", d)
	}
	d = l.ScrollDateAt(history.Viewport{Top: 60, Height: 120}, bars)
	if d.Row != 0 || d.Top != 70 || d.InPlace {
		t.Fatalf("top 60 = %+v, want {0 70 false} (mid-pack anchor floats its pack date)", d)
	}
	d = l.ScrollDateAt(history.Viewport{Top: 120, Height: 120}, bars)
	if d.Row != 0 || d.Top != 128 || d.InPlace {
		t.Fatalf("top 120 = %+v, want {0 128 false} (clamped to pack bottom - date height)", d)
	}
	d = l.ScrollDateAt(history.Viewport{Top: 130, Height: 120}, bars)
	if d.Row != 0 || d.Top != 128 || d.InPlace {
		t.Fatalf("top 130 = %+v, want {0 128 false} (pack-A hand-off clamp zone)", d)
	}
	d = l.ScrollDateAt(history.Viewport{Top: 175, Height: 120}, bars)
	if d.Row != 3 || d.Top != 185 || d.InPlace {
		t.Fatalf("top 175 = %+v, want {3 185 false} (pack-start anchor floats)", d)
	}
	d = l.ScrollDateAt(history.Viewport{Top: 200, Height: 120}, bars)
	if d.Row != 3 || d.Top != 210 || d.InPlace {
		t.Fatalf("top 200 = %+v, want {3 210 false} (second row of pack B)", d)
	}
	d = l.ScrollDateAt(history.Viewport{Top: 235, Height: 120}, bars)
	if d.Row != 3 || d.Top != 228 || d.InPlace {
		t.Fatalf("top 235 = %+v, want {3 228 false} (pack-B hand-off clamp)", d)
	}
	d = l.ScrollDateAt(history.Viewport{Top: 260, Height: 120}, bars)
	if d.Row != 5 || d.Top != 270 || !d.InPlace {
		t.Fatalf("top 260 = %+v, want {5 270 true} (pack C pushed but in place)", d)
	}
	withEmpty := scrollDateItems()
	withEmpty = append([]history.Item{{Kind: history.ItemMessage, Empty: true}}, withEmpty...)
	l3 := history.List{Items: withEmpty, Heights: uniformHeights(7, 50)}
	d = l3.ScrollDateAt(history.Viewport{Top: 0, Height: 120}, history.ComposeBars(withEmpty))
	if d.Row != -1 {
		t.Fatalf("empty-row anchor = %+v, want Row -1 (empties carry no date)", d)
	}
	none := history.List{}.ScrollDateAt(history.Viewport{Top: 0, Height: 120}, nil)
	if none.Row != -1 {
		t.Fatalf("empty list = %+v, want Row -1", none)
	}
}

func TestScrollDateShowsOnScrollUp(t *testing.T) {
	m := scrollDateModel(t)
	if m.ChatDate.Shown {
		t.Fatal("initial measure must not show the date (empty last anchor)")
	}
	m, _ = Update(m, ChatScrolled{DeltaY: 180, Now: 1000})
	if !m.ChatDate.Shown {
		t.Fatal("downward scroll across a day boundary must show the date")
	}
	if !m.ChatDate.AfterDayCrossing || m.ChatDate.HideAt != 4000 {
		t.Fatalf("day crossing state = %+v, want AfterDayCrossing + hide at 4000", m.ChatDate)
	}
	m, _ = Update(m, ChatTick{Now: 1100})
	if m.ChatDate.Alpha != 0.5 {
		t.Fatalf("fade at 100ms = %v, want 0.5", m.ChatDate.Alpha)
	}
	m, _ = Update(m, ChatTick{Now: 1200})
	if m.ChatDate.Alpha != 1 {
		t.Fatalf("fade at 200ms = %v, want 1", m.ChatDate.Alpha)
	}
	m, _ = Update(m, ChatTick{Now: 4000})
	if m.ChatDate.Shown {
		t.Fatal("day-crossing hide deadline must hide")
	}
	m, _ = Update(m, ChatTick{Now: 4200})
	if m.ChatDate.Alpha != 0 {
		t.Fatalf("hide fade at 200ms = %v, want 0", m.ChatDate.Alpha)
	}
	m, _ = Update(m, ChatScrolled{DeltaY: -60, Now: 5000})
	if !m.ChatDate.Shown {
		t.Fatal("upward scroll onto a new anchor must show")
	}
	if m.ChatDate.HideAt != 5800 {
		t.Fatalf("hide deadline = %d, want 5800 (5000 + 800)", m.ChatDate.HideAt)
	}
	m, _ = Update(m, ChatTick{Now: 5200})
	if m.ChatDate.Alpha != 1 {
		t.Fatalf("re-show fade = %v, want 1 (already faded in)", m.ChatDate.Alpha)
	}
	m, _ = Update(m, ChatTick{Now: 5800})
	if m.ChatDate.Shown {
		t.Fatal("hide deadline must hide")
	}
	m, _ = Update(m, ChatTick{Now: 6000})
	if m.ChatDate.Alpha != 0 {
		t.Fatalf("hide fade = %v, want 0", m.ChatDate.Alpha)
	}
}

func TestScrollDateHidesOnDownwardSameDay(t *testing.T) {
	m := scrollDateModel(t)
	m, _ = Update(m, ChatScrolled{DeltaY: 180, Now: 1000})
	m, _ = Update(m, ChatTick{Now: 4200})
	m, _ = Update(m, ChatTick{Now: 4400})
	if m.ChatDate.Shown || m.ChatDate.Alpha != 0 {
		t.Fatalf("setup: shown=%v alpha=%v, want hidden and faded out", m.ChatDate.Shown, m.ChatDate.Alpha)
	}
	m, _ = Update(m, ChatScrolled{DeltaY: -60, Now: 5000})
	if !m.ChatDate.Shown {
		t.Fatal("setup: upward scroll must show")
	}
	m, _ = Update(m, ChatScrolled{DeltaY: 10, Now: 5200})
	if m.ChatDate.Shown {
		t.Fatal("downward scroll within the same day must hide immediately")
	}
	if m.ChatDate.HideAt != 0 {
		t.Fatalf("hide timer = %d, want 0 (canceled)", m.ChatDate.HideAt)
	}
}

func TestScrollDateClampedUpReArmsTimer(t *testing.T) {
	m := scrollDateModel(t)
	m, _ = Update(m, ChatScrolled{DeltaY: 180, Now: 1000})
	m, _ = Update(m, ChatTick{Now: 4200})
	m, _ = Update(m, ChatTick{Now: 4400})
	m, _ = Update(m, ChatScrolled{DeltaY: -60, Now: 5000})
	if !m.ChatDate.Shown || m.ChatDate.HideAt != 5800 {
		t.Fatalf("setup: shown=%v hideAt=%d, want true/5800", m.ChatDate.Shown, m.ChatDate.HideAt)
	}
	m, _ = Update(m, ChatScrolled{DeltaY: -200, Now: 5200})
	if m.ChatScroll.Top != 0 {
		t.Fatalf("setup: top = %d, want 0 (clamped)", m.ChatScroll.Top)
	}
	if m.ChatDate.HideAt != 6000 {
		t.Fatalf("clamped-up scroll onto a new anchor must re-arm the timer, got %d, want 6000",
			m.ChatDate.HideAt)
	}
}

func TestScrollDateChatLoadedResets(t *testing.T) {
	m := scrollDateModel(t)
	m, _ = Update(m, ChatScrolled{DeltaY: 180, Now: 1000})
	if !m.ChatDate.Shown {
		t.Fatal("setup: must be shown")
	}
	m, _ = Update(m, ChatLoaded{Items: scrollDateItems()})
	if m.ChatDate != (ChatDateState{}) {
		t.Fatalf("chat switch must reset the date state, got %+v", m.ChatDate)
	}
}

func TestScrollDatePrependKeepsAnchor(t *testing.T) {
	m := scrollDateModel(t)
	m, _ = Update(m, ChatScrolled{DeltaY: 180, Now: 1000})
	if m.ChatDate.LastRow != 3 {
		t.Fatalf("setup: anchor row = %d, want 3", m.ChatDate.LastRow)
	}
	older := []history.Item{
		{Kind: history.ItemMessage, Text: "z1", DateText: "Dec 31", TimeText: "09:00"},
		{Kind: history.ItemMessage, Text: "z2", DateText: "Dec 31", TimeText: "09:01"},
	}
	m, _ = Update(m, ChatPrepended{Items: older, MoreAbove: false})
	if m.ChatDate.LastRow != 5 {
		t.Fatalf("prepend must translate the anchor row, got %d, want 5", m.ChatDate.LastRow)
	}
	m, _ = Update(m, ChatMeasured{Heights: uniformHeights(8, 50)})
	if !m.ChatDate.Shown || m.ChatDate.HideAt != 4000 {
		t.Fatalf("prepend compensation must keep the day-crossing show (timer 4000), got shown=%v hideAt=%d",
			m.ChatDate.Shown, m.ChatDate.HideAt)
	}
	if m.ChatScroll.Top != 280 {
		t.Fatalf("compensated top = %d, want 280", m.ChatScroll.Top)
	}
	m, _ = Update(m, ChatTick{Now: 4000})
	if m.ChatDate.Shown {
		t.Fatal("the day-crossing timer must still hide after the prepend")
	}
}

func TestSceneCarriesScrollDate(t *testing.T) {
	m := scrollDateModel(t)
	m, _ = Update(m, ChatScrolled{DeltaY: 180, Now: 1000})
	m, _ = Update(m, ChatTick{Now: 4200})
	m, _ = Update(m, ChatScrolled{DeltaY: -120, Now: 5000})
	m, _ = Update(m, ChatTick{Now: 5100})
	scene := View(m)
	if scene.Chat.DateRow != 0 || scene.Chat.DateTop != 70 || scene.Chat.DateInPlace {
		t.Fatalf("pane date = row %d top %d inPlace %v, want 0/70/false",
			scene.Chat.DateRow, scene.Chat.DateTop, scene.Chat.DateInPlace)
	}
	if scene.Chat.DateText != "Jan 1" {
		t.Fatalf("pane date text = %q, want Jan 1", scene.Chat.DateText)
	}
	if scene.Chat.DateAlpha != 0.5 {
		t.Fatalf("pane date alpha = %v, want 0.5 (100ms into the 200ms fade)", scene.Chat.DateAlpha)
	}
	m, _ = Update(m, ChatTick{Now: 5200})
	scene = View(m)
	if scene.Chat.DateAlpha != 1 {
		t.Fatalf("pane date alpha = %v, want 1", scene.Chat.DateAlpha)
	}
}

func TestScrollDateActive(t *testing.T) {
	m := scrollDateModel(t)
	if m.ChatDateActive() {
		t.Fatal("idle date state must not tick")
	}
	m, _ = Update(m, ChatScrolled{DeltaY: 180, Now: 1000})
	if !m.ChatDateActive() {
		t.Fatal("shown date with a pending timer must tick")
	}
	m, _ = Update(m, ChatTick{Now: 1200})
	m, _ = Update(m, ChatTick{Now: 4200})
	m, _ = Update(m, ChatTick{Now: 4400})
	if m.ChatDateActive() {
		t.Fatal("hidden + faded-out date must not tick")
	}
}
