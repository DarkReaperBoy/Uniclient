package gui

import (
	"image"
	"testing"

	"uniclient/engine"
)

// Album pure helpers (gui/album.go + chrome.go grouping).

func albumMsg(id, group string, mt int) engine.CachedMessage {
	return engine.CachedMessage{
		MsgID:     id,
		GroupedID: group,
		HasMedia:  true,
		MediaType: mt,
		Timestamp: 1_700_000_000_000,
	}
}

func abs(n int) int {
	if n < 0 {
		return -n
	}
	return n
}

func TestAlbumCells(t *testing.T) {
	const W, H, gap = 300, 200, 3

	t.Run("n=1 single", func(t *testing.T) {
		cs := albumCells(1, W, H, gap)
		if len(cs) != 1 || cs[0] != image.Rect(0, 0, W, H) {
			t.Fatalf("n=1 = %v", cs)
		}
	})

	t.Run("n=2 columns", func(t *testing.T) {
		cs := albumCells(2, W, H, gap)
		if len(cs) != 2 {
			t.Fatalf("n=2 = %d cells", len(cs))
		}
		if abs(cs[0].Dx()-cs[1].Dx()) > 1 || cs[0].Dy() != H || cs[1].Dy() != H {
			t.Fatalf("n=2 = %v", cs)
		}
	})

	t.Run("n=3 tall+stacked", func(t *testing.T) {
		cs := albumCells(3, W, H, gap)
		if len(cs) != 3 {
			t.Fatalf("n=3 = %d cells", len(cs))
		}
		if cs[0].Dy() != H { // left tall
			t.Fatalf("left cell not tall: %v", cs[0])
		}
		if cs[1].Dy() != (H-gap)/2 || cs[2].Min.Y < cs[1].Max.Y {
			t.Fatalf("right cells not stacked: %v", cs[1:])
		}
	})

	t.Run("n=4 grid", func(t *testing.T) {
		cs := albumCells(4, W, H, gap)
		if len(cs) != 4 {
			t.Fatalf("n=4 = %d cells", len(cs))
		}
		halfW, halfH := (W-gap)/2, (H-gap)/2
		for i, c := range cs {
			// Right/bottom cells absorb integer rounding (up to 1px).
			if c.Dx() < halfW || c.Dx() > halfW+1 || c.Dy() < halfH || c.Dy() > halfH+1 {
				t.Fatalf("cell %d = %v, want ~half-size (%d×%d)", i, c, halfW, halfH)
			}
		}
	})

	t.Run("n>4 clamps to 4 cells", func(t *testing.T) {
		if cs := albumCells(9, W, H, gap); len(cs) != 4 {
			t.Fatalf("n=9 = %d cells, want 4", len(cs))
		}
	})

	t.Run("degenerate", func(t *testing.T) {
		if cs := albumCells(0, W, H, gap); cs != nil {
			t.Fatalf("n=0 = %v", cs)
		}
		if cs := albumCells(2, 0, H, gap); cs != nil {
			t.Fatalf("W=0 = %v", cs)
		}
	})
}

func TestAlbumOverCount(t *testing.T) {
	cases := map[int]int{0: 0, 1: 0, 4: 0, 5: 1, 9: 5}
	for n, want := range cases {
		if got := albumOverCount(n); got != want {
			t.Errorf("albumOverCount(%d) = %d, want %d", n, got, want)
		}
	}
}

func TestIsAlbumMedia(t *testing.T) {
	if !isAlbumMedia(&engine.CachedMessage{HasMedia: true, GroupedID: "g", MediaType: engine.MediaImage}) {
		t.Error("grouped image should be album media")
	}
	if isAlbumMedia(&engine.CachedMessage{HasMedia: true, GroupedID: "g", MediaType: engine.MediaVoice}) {
		t.Error("voice is never album media")
	}
	if isAlbumMedia(&engine.CachedMessage{HasMedia: true, GroupedID: "", MediaType: engine.MediaImage}) {
		t.Error("ungrouped media is not album media")
	}
	if isAlbumMedia(&engine.CachedMessage{HasMedia: false, GroupedID: "g", MediaType: engine.MediaImage}) {
		t.Error("no media = not album media")
	}
}

func TestBuildChatRowsAlbums(t *testing.T) {
	msgs := []engine.CachedMessage{
		albumMsg("a", "", engine.MediaImage), // lone photo
		albumMsg("p1", "g1", engine.MediaImage),
		albumMsg("p2", "g1", engine.MediaImage),
		albumMsg("p3", "g1", engine.MediaVideo),
		albumMsg("b", "", engine.MediaImage), // lone photo after the album
	}
	rows := buildChatRows(msgs, "")
	var albums int
	for _, r := range rows {
		if r.album != nil {
			albums++
			if len(r.album) != 3 {
				t.Fatalf("album group = %v, want 3 members", r.album)
			}
			if r.msgIdx != 1 {
				t.Fatalf("album msgIdx = %d, want 1", r.msgIdx)
			}
		}
	}
	if albums != 1 {
		t.Fatalf("albums = %d, want 1", albums)
	}
	if len(rows) != 4 { // 1 day divider (same ts) + a + album row + b
		t.Fatalf("rows = %d, want 4", len(rows))
	}

	// Jump: album members resolve to the album row.
	if got := rowIndexOf(msgs, "p3", ""); got != 2 {
		t.Errorf("rowIndexOf(p3) = %d, want 2 (album row)", got)
	}
	if got := rowIndexOf(msgs, "a", ""); got != 1 {
		t.Errorf("rowIndexOf(a) = %d, want 1", got)
	}
}

func TestAlbumCaption(t *testing.T) {
	msgs := []engine.CachedMessage{
		albumMsg("p1", "g", engine.MediaImage),
		{MsgID: "p2", GroupedID: "g", HasMedia: true, MediaType: engine.MediaImage, ContentText: "the caption"},
	}
	if got := albumCaption(msgs, []int{0, 1}); got != "the caption" {
		t.Errorf("albumCaption = %q", got)
	}
	if got := albumCaption(msgs, []int{0}); got != "" {
		t.Errorf("albumCaption no-text = %q", got)
	}
}
