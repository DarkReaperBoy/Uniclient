package gui

// Sticker pack info/add (AyuGram parity slice 108): sticker messages gain
// a context-menu "View sticker pack" — a dialog over the engine's sticker
// set info (title, count, animated/video flags, installed state, sticker
// thumbnail grid) with an Install button dispatching engine.InstallStickerSet.
// Set keys parse from the message's cached MediaExtra (pure, locked here).

import (
	"testing"

	"uniclient/cores"
	"uniclient/engine"
)

func TestStickerSetKeys(t *testing.T) {
	// By short name.
	m := engine.CachedMessage{MediaType: engine.MediaSticker, MediaExtra: `{"sticker_set_short_name":"CoolPack"}`}
	sn, id, hash, ok := stickerSetKeys(m)
	if !ok || sn != "CoolPack" || id != 0 || hash != 0 {
		t.Fatalf("short name keys: %q %d %d %v", sn, id, hash, ok)
	}
	// By set ID + access hash.
	m.MediaExtra = `{"sticker_set_id":123,"sticker_set_access_hash":456}`
	sn, id, hash, ok = stickerSetKeys(m)
	if !ok || sn != "" || id != 123 || hash != 456 {
		t.Fatalf("id keys: %q %d %d %v", sn, id, hash, ok)
	}
	// Non-sticker or missing keys → no dialog offer.
	m.MediaExtra = `{}`
	if _, _, _, ok := stickerSetKeys(m); ok {
		t.Fatal("missing keys must not open the pack dialog")
	}
	m2 := engine.CachedMessage{MediaType: engine.MediaImage, MediaExtra: `{"sticker_set_short_name":"x"}`}
	if _, _, _, ok := stickerSetKeys(m2); ok {
		t.Fatal("non-sticker messages must not offer the pack dialog")
	}
	// Garbage JSON is not a crash.
	m3 := engine.CachedMessage{MediaType: engine.MediaSticker, MediaExtra: "not json"}
	if _, _, _, ok := stickerSetKeys(m3); ok {
		t.Fatal("garbage extra must not open the dialog")
	}
}

func TestStickerPackMenuGate(t *testing.T) {
	st := engine.CachedMessage{MediaType: engine.MediaSticker, MediaExtra: `{"sticker_set_short_name":"p"}`}
	if !stickerPackMenuGate(st) {
		t.Fatal("sticker message with set keys gets the menu item")
	}
	nokeys := engine.CachedMessage{MediaType: engine.MediaSticker}
	if stickerPackMenuGate(nokeys) {
		t.Fatal("sticker without set keys: no menu item (honest)")
	}
	photo := engine.CachedMessage{MediaType: engine.MediaImage, MediaExtra: `{"sticker_set_short_name":"p"}`}
	if stickerPackMenuGate(photo) {
		t.Fatal("photo messages never get the pack item")
	}
}

func TestStickerPackSummaryLabel(t *testing.T) {
	s := &cores.StickerSetResult{Title: "Pack", Count: 12}
	if l := stickerPackSummaryLabel(s); l != "12 stickers" {
		t.Fatalf("label = %q", l)
	}
	s.Count = 1
	if l := stickerPackSummaryLabel(s); l != "1 sticker" {
		t.Fatalf("singular = %q", l)
	}
	s.Count = 0
	if l := stickerPackSummaryLabel(s); l != "no stickers" {
		t.Fatalf("zero = %q", l)
	}
}

func TestStickerPackKindLabel(t *testing.T) {
	s := &cores.StickerSetResult{}
	if l := stickerPackKindLabel(s); l != "static" {
		t.Fatalf("default = %q", l)
	}
	s.Animated = true
	if l := stickerPackKindLabel(s); l != "animated" {
		t.Fatalf("animated = %q", l)
	}
	s.Video = true
	if l := stickerPackKindLabel(s); l != "video" {
		t.Fatalf("video wins = %q", l)
	}
	s.Animated, s.Video = false, false
	s.Emojis = true
	if l := stickerPackKindLabel(s); l != "custom emoji" {
		t.Fatalf("emoji = %q", l)
	}
}
