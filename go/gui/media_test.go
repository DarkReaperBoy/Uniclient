package gui

import (
	"testing"

	"uniclient/engine"
)

// Media-bubble pure helpers (AyuGram parity slice 2: media bubbles +
// download progress). Tests lock the formatting / math before the widgets.

func TestFmtBytes(t *testing.T) {
	cases := []struct {
		n    int64
		want string
	}{
		{0, "0 B"},
		{-5, "0 B"},
		{1, "1 B"},
		{512, "512 B"},
		{1024, "1 KB"},
		{1536, "1.5 KB"},
		{90 * 1024, "90 KB"},
		{2 * 1024 * 1024, "2 MB"},
		{int64(2.4 * 1024 * 1024), "2.4 MB"},
		{3 * 1024 * 1024 * 1024, "3 GB"},
	}
	for _, c := range cases {
		if got := fmtBytes(c.n); got != c.want {
			t.Errorf("fmtBytes(%d) = %q, want %q", c.n, got, c.want)
		}
	}
}

func TestFmtDur(t *testing.T) {
	cases := []struct {
		sec  int
		want string
	}{
		{0, "0:00"},
		{-3, "0:00"},
		{5, "0:05"},
		{65, "1:05"},
		{3599, "59:59"},
		{3661, "1:01:01"},
	}
	for _, c := range cases {
		if got := fmtDur(c.sec); got != c.want {
			t.Errorf("fmtDur(%d) = %q, want %q", c.sec, got, c.want)
		}
	}
}

func TestFitDims(t *testing.T) {
	cases := []struct {
		w0, h0, maxW, maxH int
		wantW, wantH       int
	}{
		// landscape shrink into square box
		{800, 600, 300, 300, 300, 225},
		// portrait shrink
		{600, 1200, 300, 300, 150, 300},
		// square upscale to fill
		{60, 60, 260, 320, 260, 260},
		// degenerate: falls back to box
		{0, 0, 300, 200, 300, 200},
		// very wide strip: height floors at 1
		{10000, 10, 300, 300, 300, 1},
	}
	for _, c := range cases {
		gotW, gotH := fitDims(c.w0, c.h0, c.maxW, c.maxH)
		if gotW != c.wantW || gotH != c.wantH {
			t.Errorf("fitDims(%d,%d,%d,%d) = %d,%d want %d,%d",
				c.w0, c.h0, c.maxW, c.maxH, gotW, gotH, c.wantW, c.wantH)
		}
	}
}

func TestDlFraction(t *testing.T) {
	cases := []struct {
		recv, total int64
		want        float32
	}{
		{0, 100, 0},
		{50, 0, 0},
		{-1, 100, 0},
		{50, 100, 0.5},
		{100, 100, 1},
		{150, 100, 1},
	}
	for _, c := range cases {
		if got := dlFraction(c.recv, c.total); got != c.want {
			t.Errorf("dlFraction(%d,%d) = %v, want %v", c.recv, c.total, got, c.want)
		}
	}
}

func TestMediaBlockGating(t *testing.T) {
	// The bubble type switch must never fall through to an empty widget:
	// every engine media type renders one of the known blocks.
	for mt := range mediaBlockKinds() {
		if kind := mediaBlockKind(mt); kind == "" {
			t.Errorf("mediaBlockKind(%d) empty", mt)
		}
	}
}

// mediaBlockKinds returns every media type the GUI knows how to bubble.
func mediaBlockKinds() map[int]string {
	return map[int]string{
		engine.MediaImage:     "photo",
		engine.MediaVideo:     "video",
		engine.MediaVideoNote: "video",
		engine.MediaVoice:     "voice",
		engine.MediaAudio:     "audio",
		engine.MediaGIF:       "photo",
		engine.MediaSticker:   "file",
		engine.MediaFile:      "file",
		engine.MediaPoll:      "file",
		engine.MediaLocation:  "file",
		engine.MediaContact:   "file",
		engine.MediaInvoice:   "file",
	}
}
