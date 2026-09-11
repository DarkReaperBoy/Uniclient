package cores

// Sticker manager (slice 139): pure mapping helpers for the lightweight
// set listing (getAllStickers + getArchivedStickers merge) and the
// archive-flag install request. Pinned against the gotd v0.161.0 schema
// (messages.installStickerSet carries the Archived flag — tdesktop
// archives without deleting; messages.getArchivedStickers returns
// StickerSetCovered rows).

import (
	"encoding/base64"
	"testing"

	"github.com/gotd/td/tg"
)

func coveredSet() *tg.StickerSet {
	s := &tg.StickerSet{
		ID:         42,
		AccessHash: 4242,
		Title:      "Cats",
		ShortName:  "cats",
		Count:      12,
		Archived:   true,
		Official:   true,
	}
	s.SetThumbs([]tg.PhotoSizeClass{&tg.PhotoStrippedSize{Bytes: []byte{1, 2, 3}}})
	return s
}

func TestStickerSetCoveredSummaryFields(t *testing.T) {
	sc := &tg.StickerSetCovered{Set: *coveredSet()}
	sum, ok := stickerSetCoveredSummary(sc)
	if !ok {
		t.Fatal("covered set not mapped")
	}
	if sum.SetID != 42 || sum.AccessHash != 4242 || sum.Title != "Cats" || sum.ShortName != "cats" {
		t.Fatalf("identity = %+v", sum)
	}
	if sum.Count != 12 || !sum.Archived || !sum.Official {
		t.Fatalf("flags = %+v", sum)
	}
	// ThumbB64 decodes to a reconstructed JPEG (SOI marker), never the raw
	// stripped bytes.
	raw, err := base64.StdEncoding.DecodeString(sum.ThumbB64)
	if err != nil {
		t.Fatalf("thumb not base64: %v", err)
	}
	if len(raw) < 3 || raw[0] != 0xFF || raw[1] != 0xD8 {
		t.Fatalf("thumb not a JPEG (len=%d)", len(raw))
	}
	if sum.Installed {
		t.Fatal("covered summary must not default to installed")
	}
}

func TestStickerSetCoveredSummaryVariants(t *testing.T) {
	set := coveredSet()
	multi := &tg.StickerSetMultiCovered{Set: *set, Covers: []tg.DocumentClass{}}
	if sum, ok := stickerSetCoveredSummary(multi); !ok || sum.SetID != 42 {
		t.Fatalf("multi-covered = %+v ok=%v", sum, ok)
	}
	full := &tg.StickerSetFullCovered{Set: *set}
	if sum, ok := stickerSetCoveredSummary(full); !ok || sum.SetID != 42 {
		t.Fatalf("full-covered = %+v ok=%v", sum, ok)
	}
	no := &tg.StickerSetNoCovered{Set: *set}
	if sum, ok := stickerSetCoveredSummary(no); !ok || sum.SetID != 42 {
		t.Fatalf("no-covered = %+v ok=%v", sum, ok)
	}
	if _, ok := stickerSetCoveredSummary(nil); ok {
		t.Fatal("nil mapped to a summary")
	}
}

func TestStickerSetCoveredSummaryCoverDocs(t *testing.T) {
	set := coveredSet()
	doc := &tg.Document{
		ID:         7,
		AccessHash: 77,
		MimeType:   "image/webp",
		Thumbs:     []tg.PhotoSizeClass{&tg.PhotoStrippedSize{Bytes: []byte{9}}},
		Attributes: []tg.DocumentAttributeClass{&tg.DocumentAttributeImageSize{W: 512, H: 512}},
	}
	sc := &tg.StickerSetCovered{Set: *set, Cover: doc}
	sum, ok := stickerSetCoveredSummary(sc)
	if !ok {
		t.Fatal("covered set not mapped")
	}
	if len(sum.Stickers) != 1 || sum.Stickers[0].FileID != "7" {
		t.Fatalf("cover stickers = %+v", sum.Stickers)
	}
	if sum.Stickers[0].Width != 512 || sum.Stickers[0].Height != 512 {
		t.Fatalf("cover dims = %+v", sum.Stickers[0])
	}
	if sum.Stickers[0].MimeType != "image/webp" {
		t.Fatalf("cover mime = %q", sum.Stickers[0].MimeType)
	}
}

// installed summary rows (from getAllStickers tg.StickerSet) feed the same
// shape with Archived/Masks/Emojis surfaced.
func TestInstalledSetSummaryFields(t *testing.T) {
	s := coveredSet()
	s.Archived = false
	s.Masks = true
	s.Emojis = false
	sum := installedSetSummary(s)
	if sum.Installed != true || sum.Archived || !sum.Masks || sum.Emojis {
		t.Fatalf("installed summary = %+v", sum)
	}
	if sum.SetID != 42 || sum.ThumbB64 == "" {
		t.Fatalf("identity = %+v", sum)
	}
}

// Merge: archived entries dedup against installed rows with the same set
// ID — the archived row wins (tdesktop lists them under Archived only).
func TestMergeArchivedStickerSets(t *testing.T) {
	installed := []StickerPackSummary{
		{SetID: 1, Title: "Kept"},
		{SetID: 2, Title: "Archived-dup"},
		{SetID: 3, Title: "Also-kept"},
	}
	archived := []StickerPackSummary{
		{SetID: 2, Title: "Archived-dup", Archived: true},
		{SetID: 9, Title: "Only-archived", Archived: true},
	}
	merged := mergeArchivedStickerSets(installed, archived)
	if len(merged) != 4 {
		t.Fatalf("merged = %d rows: %+v", len(merged), merged)
	}
	byID := map[int64]StickerPackSummary{}
	for _, m := range merged {
		byID[m.SetID] = m
	}
	if byID[2].Archived != true || byID[2].Title != "Archived-dup" {
		t.Fatalf("dup row = %+v (archived must win)", byID[2])
	}
	if byID[9].Archived != true {
		t.Fatalf("archived-only row = %+v", byID[9])
	}
	if byID[1].Archived || byID[3].Archived {
		t.Fatalf("installed rows re-flagged: %+v", byID)
	}
}

// installStickerSetRequest pins the archive semantics: archived=true keeps
// the set installed but hides it (tdesktop "Archive"), archived=false
// restores (unarchive).
func TestInstallStickerSetRequestArchiveFlag(t *testing.T) {
	req := stickerSetInstallRequest(42, 4242, true)
	in, ok := req.Stickerset.(*tg.InputStickerSetID)
	if !ok || in.ID != 42 || in.AccessHash != 4242 {
		t.Fatalf("input set = %+v", req.Stickerset)
	}
	if !req.Archived {
		t.Fatal("archive request did not set Archived")
	}
	req = stickerSetInstallRequest(42, 4242, false)
	if req.Archived {
		t.Fatal("unarchive request set Archived")
	}
}
