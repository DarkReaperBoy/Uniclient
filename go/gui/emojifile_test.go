package gui

// emojifile_test.go — slice 132 tests-first: inline custom-emoji artwork.
// Pure helpers under test: the document-ID collector (from a message's
// entities), the mime classifier (lottie / raster / honest-unsupported),
// and the inline sizing rule (~1.35x the font box, tdesktop proportions).

import (
	"testing"

	"uniclient/cores"
)

func TestCustomEmojiDocIDs(t *testing.T) {
	ents := []cores.TextEntity{
		{Type: "bold", Offset: 0, Length: 2},
		{Type: "custom_emoji", Offset: 3, Length: 2, DocumentID: 111},
		{Type: "italic", Offset: 5, Length: 1},
		{Type: "custom_emoji", Offset: 6, Length: 2, DocumentID: 222},
		{Type: "custom_emoji", Offset: 8, Length: 2, DocumentID: 111}, // dupe
		{Type: "custom_emoji", Offset: 9, Length: 1, DocumentID: 0},   // degenerate
	}
	got := customEmojiDocIDs(ents)
	if len(got) != 2 || got[0] != 111 || got[1] != 222 {
		t.Fatalf("customEmojiDocIDs = %v, want [111 222]", got)
	}
	if customEmojiDocIDs(nil) != nil {
		t.Error("nil entities yielded ids")
	}
	if ids := customEmojiDocIDs([]cores.TextEntity{{Type: "spoiler"}}); ids != nil {
		t.Errorf("non-custom entities yielded %v", ids)
	}
}

func TestClassifyEmojiArt(t *testing.T) {
	cases := []struct {
		mime string
		want int
	}{
		{"application/x-tgsticker", emojiArtLottie},
		{"image/webp", emojiArtRaster},
		{"image/png", emojiArtRaster},
		{"image/jpeg", emojiArtRaster},
		{"video/webm", emojiArtUnsupported}, // no pure-Go webm decode (§1.1)
		{"video/mp4", emojiArtUnsupported},
		{"", emojiArtUnsupported},
		{"application/octet-stream", emojiArtUnsupported},
	}
	for _, c := range cases {
		if got := classifyEmojiArt(c.mime); got != c.want {
			t.Errorf("classifyEmojiArt(%q) = %d, want %d", c.mime, got, c.want)
		}
	}
}

func TestEmojiArtSide(t *testing.T) {
	cases := []struct {
		fontPx, want int
	}{
		{20, 27}, // 20 * 1.35 = 27
		{15, 20}, // 20.25 → 20
		{0, 0},
		{-4, 0},
	}
	for _, c := range cases {
		if got := emojiArtSide(c.fontPx); got != c.want {
			t.Errorf("emojiArtSide(%d) = %d, want %d", c.fontPx, got, c.want)
		}
	}
}
