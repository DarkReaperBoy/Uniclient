package tests

import (
	"testing"

	. "uniclient/ui/history"
	. "uniclient/ui/icons"
)

func TestHistorySendStateSelection(t *testing.T) {
	cases := []struct {
		out, sending, unread bool
		hidden               bool
		want                 Icon
	}{
		{false, false, false, true, Icon{}},
		{false, true, true, true, Icon{}},
		{true, true, false, false, HistorySending},
		{true, true, true, false, HistorySending},
		{true, false, true, false, HistorySent},
		{true, false, false, false, HistoryReceived},
	}
	for _, c := range cases {
		got, ok := SendStateIcon(c.out, c.sending, c.unread)
		if c.hidden {
			if ok {
				t.Fatalf("SendStateIcon(%v,%v,%v) must hide, got cell %dx%d",
					c.out, c.sending, c.unread, got.Cell.W, got.Cell.H)
			}
			continue
		}
		if !ok {
			t.Fatalf("SendStateIcon(%v,%v,%v) must show cell %dx%d, got hidden",
				c.out, c.sending, c.unread, c.want.Cell.W, c.want.Cell.H)
		}
		if got.Cell != c.want.Cell {
			t.Fatalf("SendStateIcon(%v,%v,%v) = cell %+v, want %+v",
				c.out, c.sending, c.unread, got.Cell, c.want.Cell)
		}
		if got.Glyph.W != c.want.Glyph.W || got.Glyph.H != c.want.Glyph.H {
			t.Fatalf("SendStateIcon(%v,%v,%v) = glyph %dx%d, want %dx%d",
				c.out, c.sending, c.unread, got.Glyph.W, got.Glyph.H, c.want.Glyph.W, c.want.Glyph.H)
		}
	}
}
