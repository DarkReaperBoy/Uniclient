package gui

// Sticker & emoji manager (slice 139): pure helpers — installed/archived
// split, reorder-order math, row subtitles, search filter + merge, and
// featured visibility. tdesktop Stickers-and-Emoji semantics.

import (
	"testing"

	"uniclient/cores"
)

func mgrPacks() []cores.StickerPackSummary {
	return []cores.StickerPackSummary{
		{SetID: 1, Title: "Cats", ShortName: "cats", Count: 12},
		{SetID: 2, Title: "Dogs", ShortName: "dogs", Count: 3, Animated: true},
		{SetID: 3, Title: "Old", ShortName: "old", Count: 7, Archived: true},
		{SetID: 4, Title: "Boxes", ShortName: "boxes", Count: 1, Video: true, Masks: true},
		{SetID: 5, Title: "Gone", ShortName: "gone", Archived: true},
	}
}

func TestStickerMgrSplit(t *testing.T) {
	installed, archived := stickerMgrSplit(mgrPacks())
	if len(installed) != 3 || len(archived) != 2 {
		t.Fatalf("split = %d/%d, want 3/2", len(installed), len(archived))
	}
	if installed[0].Title != "Cats" || archived[0].Title != "Old" {
		t.Fatalf("order not preserved: %+v / %+v", installed, archived)
	}
	if inst, arch := stickerMgrSplit(nil); len(inst) != 0 || len(arch) != 0 {
		t.Fatal("nil input split non-empty")
	}
}

func TestStickerMgrMoveOrder(t *testing.T) {
	ids := []int64{10, 20, 30, 40}

	// move up (toward 0)
	got := stickerMgrMoveOrder(ids, 2, -1)
	if got[0] != 10 || got[1] != 30 || got[2] != 20 || got[3] != 40 {
		t.Fatalf("move up = %v", got)
	}
	// move down
	got = stickerMgrMoveOrder(ids, 1, 1)
	if got[0] != 10 || got[1] != 30 || got[2] != 20 || got[3] != 40 {
		t.Fatalf("move down = %v", got)
	}
	// edges clamp
	got = stickerMgrMoveOrder(ids, 0, -1)
	if got[0] != 10 || got[1] != 20 {
		t.Fatalf("edge up = %v", got)
	}
	got = stickerMgrMoveOrder(ids, 3, 1)
	if got[3] != 40 {
		t.Fatalf("edge down = %v", got)
	}
	// invalid index / delta unchanged (new slice, same order)
	got = stickerMgrMoveOrder(ids, -1, 1)
	if len(got) != 4 || got[2] != 30 {
		t.Fatalf("invalid idx = %v", got)
	}
	got = stickerMgrMoveOrder(ids, 2, 0)
	if got[2] != 30 {
		t.Fatalf("zero delta = %v", got)
	}
	// input not mutated
	if ids[1] != 20 || ids[2] != 30 {
		t.Fatalf("input mutated: %v", ids)
	}
}

func TestStickerMgrRowSubtitle(t *testing.T) {
	cases := []struct {
		in   cores.StickerPackSummary
		want string
	}{
		{cores.StickerPackSummary{Count: 1}, "1 sticker"},
		{cores.StickerPackSummary{Count: 12}, "12 stickers"},
		{cores.StickerPackSummary{Count: 12, Animated: true}, "12 stickers · animated"},
		{cores.StickerPackSummary{Count: 12, Video: true}, "12 stickers · video"},
		{cores.StickerPackSummary{Count: 12, Masks: true}, "12 stickers · masks"},
		{cores.StickerPackSummary{Count: 12, Official: true}, "12 stickers · official"},
		{cores.StickerPackSummary{Count: 12, Animated: true, Official: true}, "12 stickers · animated · official"},
	}
	for _, c := range cases {
		if got := stickerMgrRowSubtitle(c.in); got != c.want {
			t.Errorf("subtitle(%+v) = %q, want %q", c.in, got, c.want)
		}
	}
}

func TestStickerMgrFilter(t *testing.T) {
	packs := mgrPacks()
	got := stickerMgrFilter(packs, "cat")
	if len(got) != 1 || got[0].Title != "Cats" {
		t.Fatalf("filter cats = %+v", got)
	}
	// short-name matches, case-insensitive
	got = stickerMgrFilter(packs, "DOGS")
	if len(got) != 1 || got[0].Title != "Dogs" {
		t.Fatalf("filter DOGS = %+v", got)
	}
	// empty query = everything
	if got := stickerMgrFilter(packs, ""); len(got) != len(packs) {
		t.Fatal("empty query filtered")
	}
	// whitespace-only query = everything
	if got := stickerMgrFilter(packs, "   "); len(got) != len(packs) {
		t.Fatal("blank query filtered")
	}
	if got := stickerMgrFilter(packs, "zzz"); len(got) != 0 {
		t.Fatalf("no-hit filter = %+v", got)
	}
}

func TestStickerMgrFeaturedVisible(t *testing.T) {
	featured := []cores.StickerPackSummary{
		{SetID: 1, Title: "Already-in"},   // installed
		{SetID: 3, Title: "Already-arch"}, // archived
		{SetID: 7, Title: "Fresh"},
	}
	got := stickerMgrFeaturedVisible(featured, mgrPacks())
	if len(got) != 1 || got[0].SetID != 7 {
		t.Fatalf("featured visible = %+v", got)
	}
}

func TestStickerMgrSearchMerge(t *testing.T) {
	results := []cores.StickerPackSummary{
		{SetID: 1, Title: "Known-installed"},
		{SetID: 3, Title: "Known-archived"},
		{SetID: 8, Title: "New-hit"},
	}
	got := stickerMgrSearchMerge(results, mgrPacks())
	if len(got) != 1 || got[0].SetID != 8 {
		t.Fatalf("merge = %+v, want only the unknown set", got)
	}
	// empty known: everything passes
	if got := stickerMgrSearchMerge(results, nil); len(got) != 3 {
		t.Fatalf("nil known = %+v", got)
	}
}

func TestStickerMgrEmojiSubtitle(t *testing.T) {
	cases := []struct {
		in   cores.EmojiSetSummary
		want string
	}{
		{cores.EmojiSetSummary{Count: 1}, "1 emoji"},
		{cores.EmojiSetSummary{Count: 40}, "40 emoji"},
		{cores.EmojiSetSummary{Count: 40, Premium: true}, "40 emoji · premium"},
	}
	for _, c := range cases {
		if got := stickerMgrEmojiSubtitle(c.in); got != c.want {
			t.Errorf("emoji subtitle(%+v) = %q, want %q", c.in, got, c.want)
		}
	}
}

func TestStickerMgrTabConstants(t *testing.T) {
	if stickerMgrTabStickers != 0 || stickerMgrTabEmoji != 1 {
		t.Fatal("manager tab constants drifted")
	}
}

// mgrSetOrder extracts the set-ID order for ReorderStickerSets.
func TestStickerMgrSetOrder(t *testing.T) {
	got := stickerMgrSetOrder(mgrPacks()[:3])
	if len(got) != 3 || got[0] != 1 || got[1] != 2 || got[2] != 3 {
		t.Fatalf("set order = %v", got)
	}
	if got := stickerMgrSetOrder(nil); len(got) != 0 {
		t.Fatal("nil order non-empty")
	}
}
