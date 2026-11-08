package tests

import (
	"testing"

	"gioui.org/layout"
	"gioui.org/op"
	"gioui.org/unit"

	"uniclient/ui/history"
	"uniclient/ui/history/render"
)

func renderContext() layout.Context {
	return layout.Context{
		Ops:    new(op.Ops),
		Metric: unit.Metric{PxPerDp: 1, PxPerSp: 1},
	}
}

func TestMeasureComposesEntryBars(t *testing.T) {
	p := render.NewChatPainter()
	gtx := renderContext()
	items := []history.Item{
		{Kind: history.ItemMessage, Text: "aa", TimeText: "10:00", DateText: "5 November"},
		{Kind: history.ItemMessage, Text: "bb", TimeText: "10:01"},
		{Kind: history.ItemMessage, Text: "cc", TimeText: "10:02", DateText: "6 November", UnreadBar: "Unread messages"},
	}
	h := p.Measure(gtx, items, 320)
	if len(h) != 3 {
		t.Fatalf("heights len = %d, want 3", len(h))
	}
	if h[0]-h[1] != 32 {
		t.Errorf("date badge delta = %d, want 32 (h0=%d h1=%d)", h[0]-h[1], h[0], h[1])
	}
	if h[2]-h[1] != 67 {
		t.Errorf("date+unread delta = %d, want 67 (h2=%d h1=%d)", h[2]-h[1], h[2], h[1])
	}
}
