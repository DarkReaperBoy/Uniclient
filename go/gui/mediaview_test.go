package gui

import (
	"testing"

	"uniclient/engine"
)

// Media viewer pure helpers (gui/mediaview.go, §12 parity).

func TestStepViewerIndex(t *testing.T) {
	cases := []struct {
		i, n, delta, want int
	}{
		{0, 5, 1, 1},   // step in
		{3, 5, 1, 4},   // to last
		{4, 5, 1, 4},   // clamp at newest
		{1, 5, -1, 0},  // to oldest
		{0, 5, -1, 0},  // clamp at oldest
		{0, 5, 99, 4},  // overshoot clamps
		{4, 5, -99, 0}, // undershoot clamps
		{0, 0, 1, 0},   // empty list
		{0, 1, 1, 0},   // single item stays
	}
	for _, c := range cases {
		if got := stepViewerIndex(c.i, c.n, c.delta); got != c.want {
			t.Errorf("stepViewerIndex(%d,%d,%d) = %d, want %d", c.i, c.n, c.delta, got, c.want)
		}
	}
}

func TestViewerZoomAfter(t *testing.T) {
	if z := viewerZoomAfter(1); z != 2.5 {
		t.Errorf("zoom 1 → %v, want 2.5", z)
	}
	if z := viewerZoomAfter(2.5); z != 1 {
		t.Errorf("zoom 2.5 → %v, want 1", z)
	}
	if z := viewerZoomAfter(1.3); z != 1 {
		t.Errorf("zoom 1.3 → %v, want 1", z)
	}
}

func TestClampPanAxis(t *testing.T) {
	// Image smaller than the box → snap to center.
	if p := clampPanAxis(30, 100, 200); p != 0 {
		t.Errorf("smaller side: %v, want 0", p)
	}
	// Zoomed larger: limited to (scaled-box)/2.
	if p := clampPanAxis(0, 400, 200); p != 0 {
		t.Errorf("center: %v, want 0", p)
	}
	if p := clampPanAxis(101, 400, 200); p != 100 {
		t.Errorf("over limit: %v, want 100", p)
	}
	if p := clampPanAxis(-101, 400, 200); p != -100 {
		t.Errorf("under limit: %v, want -100", p)
	}
}

func TestPanAfterZoom(t *testing.T) {
	// k=2, pan=0, click 10 right of center: pan' = 0*2 + (10-0)*(1-2) = -10
	// (the image grows right where the cursor sits, so its origin moves left).
	if p := panAfterZoom(0, 10, 0, 2); p != -10 {
		t.Errorf("panAfterZoom(0,10,0,2) = %v, want -10", p)
	}
	// Zoom back k=0.4 from pan=-10 with cursor at same spot: back to ~0.
	if p := panAfterZoom(-10, 10, 0, 0.4); p != -10*0.4+10*0.6 {
		t.Errorf("panAfterZoom(-10,10,0,0.4) = %v, want %v", p, -10*0.4+10*0.6)
	}
}

func TestFindViewerItem(t *testing.T) {
	items := []engine.SharedMediaItem{{MsgID: "a"}, {MsgID: "b"}}
	if i := findViewerItem(items, "b"); i != 1 {
		t.Errorf("find b = %d, want 1", i)
	}
	if i := findViewerItem(items, "zz"); i != -1 {
		t.Errorf("find zz = %d, want -1", i)
	}
	if i := findViewerItem(nil, "a"); i != -1 {
		t.Errorf("find in nil = %d, want -1", i)
	}
}

func TestMergeViewerItems(t *testing.T) {
	synth := &engine.SharedMediaItem{MsgID: "x", Text: "caption"}

	t.Run("anchor present", func(t *testing.T) {
		items := []engine.SharedMediaItem{{MsgID: "a"}, {MsgID: "x"}, {MsgID: "b"}}
		out, idx := mergeViewerItems(items, synth, "x")
		if idx != 1 || len(out) != 3 || out[0].MsgID != "a" {
			t.Fatalf("merge = idx %d len %d, want idx 1 len 3", idx, len(out))
		}
	})

	t.Run("anchor missing gets synth prepended", func(t *testing.T) {
		items := []engine.SharedMediaItem{{MsgID: "a"}, {MsgID: "b"}}
		out, idx := mergeViewerItems(items, synth, "x")
		if len(out) != 3 || out[0].MsgID != "x" || idx != 0 {
			t.Fatalf("merge = %v idx %d, want synth first at 0", out, idx)
		}
	})

	t.Run("empty list keeps synth", func(t *testing.T) {
		out, idx := mergeViewerItems(nil, synth, "x")
		if len(out) != 1 || out[0].MsgID != "x" || idx != 0 {
			t.Fatalf("merge = %v idx %d, want single synth", out, idx)
		}
	})

	t.Run("missing without synth", func(t *testing.T) {
		out, idx := mergeViewerItems([]engine.SharedMediaItem{{MsgID: "a"}}, nil, "zz")
		if len(out) != 1 || idx != 0 {
			t.Fatalf("merge = %v idx %d, want passthrough at 0", out, idx)
		}
	})
}

func TestSynthItemFromMsg(t *testing.T) {
	m := &engine.CachedMessage{
		AccountID: "acct", ChatID: "chat", MsgID: "m1",
		Timestamp: 1_700_000_000_000, MediaType: engine.MediaImage,
		MediaFileName: "f.jpg", MediaThumbB64: "AAA", MediaLocalPath: "/tmp/f.jpg",
		MediaWidth: 640, MediaHeight: 480, SenderName: "Alice", ContentText: "hi",
		IsOutgoing: true,
	}
	it := synthItemFromMsg(m)
	if it.MsgID != "m1" || it.MediaType != engine.MediaImage || it.ThumbB64 != "AAA" ||
		it.LocalPath != "/tmp/f.jpg" || it.Width != 640 || it.Height != 480 ||
		it.SenderName != "Alice" || it.Text != "hi" || !it.IsOutgoing || it.Timestamp != m.Timestamp {
		t.Fatalf("synthItemFromMsg = %+v", it)
	}
}

func TestViewerKindFor(t *testing.T) {
	cases := map[int]string{
		engine.MediaImage:     "image",
		engine.MediaGIF:       "image",
		engine.MediaSticker:   "image",
		engine.MediaVideo:     "video",
		engine.MediaVideoNote: "video",
		engine.MediaVoice:     "file",
		engine.MediaAudio:     "file",
		engine.MediaFile:      "file",
	}
	for mt, want := range cases {
		if got := viewerKindFor(mt); got != want {
			t.Errorf("viewerKindFor(%d) = %q, want %q", mt, got, want)
		}
	}
}

func TestFmtViewerDate(t *testing.T) {
	if s := fmtViewerDate(0); s != "" {
		t.Errorf("zero ts = %q, want empty", s)
	}
	if s := fmtViewerDate(1_700_000_000_000); s == "" || s == "—" {
		t.Errorf("valid ts = %q, want formatted", s)
	}
}

func TestViewerIsVideo(t *testing.T) {
	if !viewerIsVideo(engine.SharedMediaItem{MediaType: engine.MediaVideo}) {
		t.Error("video should be video")
	}
	if viewerIsVideo(engine.SharedMediaItem{MediaType: engine.MediaImage}) {
		t.Error("image should not be video")
	}
}
