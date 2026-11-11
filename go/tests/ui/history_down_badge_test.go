package tests

import (
	"testing"

	"uniclient/ui/history"
	. "uniclient/ui/tokens"
)

func TestDownBadgeTokens(t *testing.T) {
	if HistoryToDownBadgeSize != 22 {
		t.Fatalf("down badge size drifted: %d, want 22 (jump_down_button.cpp historyToDownBadge*)",
			HistoryToDownBadgeSize)
	}
}

func TestDownBadgeGeometry(t *testing.T) {
	button := history.Geometry{Left: 100, Top: 500, Width: 52, Height: 62}
	g := history.DownBadgeGeometry(button, 12)
	if g.Width != HistoryToDownBadgeSize {
		t.Fatalf("narrow badge width = %d, want the 22dp minimum", g.Width)
	}
	if g.Height != HistoryToDownBadgeSize {
		t.Fatalf("badge height = %d, want 22", g.Height)
	}
	if g.Left != button.Left+(button.Width-HistoryToDownBadgeSize)/2 {
		t.Fatalf("badge must center on the button x, got %d", g.Left)
	}
	if g.Top != button.Top {
		t.Fatalf("badge top = %d, want the button top (top 0 of the button)", g.Top)
	}
	wide := history.DownBadgeGeometry(button, 40)
	if wide.Width != 40+2*HistoryToDownBadgePadding {
		t.Fatalf("wide badge width = %d, want text + symmetric padding", wide.Width)
	}
	if wide.Left != button.Left+(button.Width-wide.Width)/2 {
		t.Fatalf("wide badge must stay centered, got %d", wide.Left)
	}
}
