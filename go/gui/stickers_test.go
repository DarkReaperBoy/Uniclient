package gui

import (
	"testing"

	"uniclient/cores"
)

// Sticker pack tabs (slice 58): Recent leads when present, empty packs
// drop, and the selected index clamps into range.
func TestStickerTabs(t *testing.T) {
	packs := []cores.StickerPackSummary{
		{Title: "Empty", Stickers: nil},
		{Title: "Cats", Stickers: []cores.StickerInfo{{FileID: "a"}, {FileID: "b"}}},
		{Title: "Dogs", Stickers: []cores.StickerInfo{{FileID: "c"}}},
	}
	recent := []cores.StickerInfo{{FileID: "r1"}}

	tabs, sel := stickerTabs(packs, recent, 0)
	if len(tabs) != 3 {
		t.Fatalf("tabs = %d, want 3 (Recent + Cats + Dogs): %+v", len(tabs), tabs)
	}
	if tabs[0].title != "Recent" || len(tabs[0].stickers) != 1 {
		t.Fatalf("recent tab = %+v", tabs[0])
	}
	if tabs[1].title != "Cats" || sel != 0 {
		t.Fatalf("clamped sel = %d, tabs[1] = %+v", sel, tabs[1])
	}

	// out-of-range selection clamps to the last tab
	tabs, sel = stickerTabs(packs, recent, 99)
	if sel != len(tabs)-1 {
		t.Fatalf("overflow sel = %d, want %d", sel, len(tabs)-1)
	}
	tabs, sel = stickerTabs(packs, recent, -5)
	if sel != len(tabs)-1 {
		t.Fatalf("negative sel = %d, want %d", sel, len(tabs)-1)
	}

	// no recent: packs only
	tabs, sel = stickerTabs(packs, nil, 0)
	if len(tabs) != 2 || tabs[0].title != "Cats" {
		t.Fatalf("no-recent tabs = %+v", tabs)
	}

	// nothing at all: zero tabs, sel clamps to -1
	tabs, sel = stickerTabs(nil, nil, 3)
	if len(tabs) != 0 || sel != -1 {
		t.Fatalf("empty = %d tabs, sel %d", len(tabs), sel)
	}
}

func TestPanelModeConstants(t *testing.T) {
	if panelModeEmoji != 0 || panelModeStickers != 1 || panelModeGifs != 2 {
		t.Fatal("panel mode constants drifted")
	}
}
