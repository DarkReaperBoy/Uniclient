package gui

import (
	"testing"

	"uniclient/cores"
	"uniclient/lottie"
	"uniclient/vp9anim"
)

func TestCustomWantDocs(t *testing.T) {
	list := []cores.Reaction{
		{Emoji: "👍", Count: 2},
		{Emoji: "", DocumentID: 7, Count: 1},
		{Emoji: "🔥", Count: 4},
		{Emoji: "", DocumentID: 99, Count: 3, ByMe: true},
	}
	got := customWantDocs(list)
	if len(got) != 2 || got[0] != 7 || got[1] != 99 {
		t.Errorf("customWantDocs = %v", got)
	}
	if customWantDocs(nil) != nil {
		t.Error("nil list = nil")
	}
	if got := customWantDocs([]cores.Reaction{{Emoji: "🙂"}}); got != nil {
		t.Errorf("no custom reactions = nil, got %v", got)
	}
}

func TestCustomReactionKey(t *testing.T) {
	if got := customReactionKey(42); got != "custom_42" {
		t.Errorf("key = %q", got)
	}
	if got := customReactionKey(-1); got != "custom_-1" {
		t.Errorf("negative doc = %q", got)
	}
	if got := customReactionKey(0); got != "custom_0" {
		t.Errorf("zero doc = %q", got)
	}
}

func TestReactionGlyphPath(t *testing.T) {
	anim := &emojiArt{kind: emojiArtLottie, anim: &lottie.Animation{}}
	if got := reactionGlyphPath(anim); got != reactionPathAnim {
		t.Fatalf("lottie art = %q", got)
	}
	raster := &emojiArt{kind: emojiArtRaster}
	if got := reactionGlyphPath(raster); got != reactionPathRaster {
		t.Fatalf("raster art = %q", got)
	}
	video := &emojiArt{kind: emojiArtVideo, player: &vp9anim.Player{}}
	if got := reactionGlyphPath(video); got != reactionPathAnim {
		t.Fatalf("video art = %q", got)
	}
	if got := reactionGlyphPath(&emojiArt{kind: emojiArtVideo, player: nil}); got != reactionPathThumb {
		t.Fatalf("unresolved video art = %q", got)
	}
	if got := reactionGlyphPath(&emojiArt{kind: emojiArtUnknown}); got != reactionPathThumb {
		t.Fatalf("unknown art = %q", got)
	}
	if got := reactionGlyphPath(&emojiArt{kind: emojiArtLottie, anim: nil}); got != reactionPathThumb {
		t.Fatalf("lottie without anim = %q", got)
	}
	if got := reactionGlyphPath(&emojiArt{kind: emojiArtUnsupported}); got != reactionPathThumb {
		t.Fatalf("unsupported art = %q", got)
	}
	if got := reactionGlyphPath(&emojiArt{failed: true}); got != reactionPathThumb {
		t.Fatalf("failed art = %q", got)
	}
	if got := reactionGlyphPath(nil); got != reactionPathThumb {
		t.Fatalf("nil art = %q", got)
	}
}

func TestReactionAnimSide(t *testing.T) {
	if got := reactionAnimSide(0); got <= 0 {
		t.Fatalf("side(0) = %d", got)
	}
	if got := reactionAnimSide(16); got != 20 {
		t.Fatalf("side(16) = %d, want 20", got)
	}
}
