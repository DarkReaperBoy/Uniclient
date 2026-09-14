package gui

// musicattach_test.go — slice 210 tests: the music attach box's pure
// helpers — query filtering (title/performer/file name), the collapsed
// preview window + Show All, the selection-aware Send label, and the
// send order (playlist order preserved, deduped by docID).

import (
	"testing"

	"uniclient/engine"
)

func maTracks() []engine.MusicTrack {
	return []engine.MusicTrack{
		{DocID: "7001", Title: "Nightcall", Performer: "Kavinsky", Duration: 257},
		{DocID: "7002", Title: "Rampage", Performer: "Aphex Twin", Duration: 200},
		{DocID: "7003", FileName: "untagged_song.mp3", Duration: 61},
		{DocID: "7004", Title: "Midnight Drive", Performer: "Kavinsky"},
		{DocID: "7005", Title: "Fifth"},
		{DocID: "7006", Title: "Sixth"},
		{DocID: "7007", Title: "Seventh"},
	}
}

func TestMusicAttachFilter(t *testing.T) {
	all := maTracks()

	if got := musicAttachFilter(all, ""); len(got) != len(all) {
		t.Errorf("empty query must keep all: %d", len(got))
	}
	if got := musicAttachFilter(all, "kavinsky"); len(got) != 2 || got[0].DocID != "7001" {
		t.Errorf("performer match = %+v", got)
	}
	if got := musicAttachFilter(all, "UNTAMED"); len(got) != 1 || got[0].DocID != "7003" {
		t.Errorf("file-name fallback (case-insensitive) = %+v", got)
	}
	if got := musicAttachFilter(all, "zzz"); len(got) != 0 {
		t.Errorf("no-match query kept rows: %d", len(got))
	}
	if got := musicAttachFilter(nil, "x"); len(got) != 0 {
		t.Errorf("nil input must stay nil-safe")
	}
}

func TestMusicAttachVisible(t *testing.T) {
	all := maTracks()
	if got := musicAttachVisible(all, false); len(got) != musicAttachPreviewRows {
		t.Errorf("collapsed preview = %d rows, want %d", len(got), musicAttachPreviewRows)
	}
	if got := musicAttachVisible(all, true); len(got) != len(all) {
		t.Errorf("show-all = %d rows, want %d", len(got), len(all))
	}
	// Shorter lists never pad or clip.
	short := all[:2]
	if got := musicAttachVisible(short, false); len(got) != 2 {
		t.Errorf("short list collapsed = %d", len(got))
	}
}

func TestMusicAttachSelectionLabel(t *testing.T) {
	if got := musicAttachSendLabel(0); got != "Send" {
		t.Errorf("empty selection label = %q", got)
	}
	if got := musicAttachSendLabel(3); got != "Send 3" {
		t.Errorf("label(3) = %q", got)
	}
}

func TestMusicAttachSendOrder(t *testing.T) {
	all := maTracks()
	sel := map[string]bool{"7004": true, "7001": true, "7001": true}
	got := musicAttachSendOrder(all, sel)
	if len(got) != 2 || got[0].DocID != "7001" || got[1].DocID != "7004" {
		t.Fatalf("send order = %+v (want playlist order 7001,7004)", got)
	}
	// Selection for tracks no longer in the list is ignored (stale docIDs).
	sel["ghost"] = true
	if got := musicAttachSendOrder(all, sel); len(got) != 2 {
		t.Errorf("ghost selection leaked: %+v", got)
	}
	if got := musicAttachSendOrder(all, nil); len(got) != 0 {
		t.Errorf("empty selection must send nothing")
	}
}
