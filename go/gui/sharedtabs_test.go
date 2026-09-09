package gui

import (
        "testing"

        "uniclient/engine"
)

// Shared-media tab browser (slice 78, AyuGram profile §7): the count pills
// became a tappable chip bar with lazy per-tab grids/lists.

func TestSharedTabsFor(t *testing.T) {
        // Empty chat: Photos (honest-empty) + Links (countless) only.
        tabs := sharedTabsFor(nil)
        if len(tabs) != 2 || tabs[0].key != "image" || tabs[1].key != "links" {
                t.Fatalf("empty counts → %+v, want [image links]", tabs)
        }

        // Full media set: Photos, Videos, GIFs, Voice, Audio, Files, Links.
        counts := []engine.SharedMediaCountItem{
                {MediaType: "photo", Count: 10}, {MediaType: "video", Count: 4},
                {MediaType: "videonote", Count: 2}, {MediaType: "gif", Count: 3},
                {MediaType: "voice", Count: 5}, {MediaType: "audio", Count: 1},
                {MediaType: "sticker", Count: 7}, {MediaType: "file", Count: 6},
        }
        tabs = sharedTabsFor(counts)
        if len(tabs) != 7 {
                t.Fatalf("full counts → %d tabs, want 7", len(tabs))
        }
        wantKeys := []string{"image", "video", "gif", "voice", "audio", "file", "links"}
        for i, k := range wantKeys {
                if tabs[i].key != k {
                        t.Errorf("tab[%d].key = %q, want %q", i, tabs[i].key, k)
                }
        }
        // Umbrella counts: photos = photo+gif+sticker, videos = video+videonote.
        if tabs[0].count != 20 {
                t.Errorf("photos count = %d, want 20 (10+3+7)", tabs[0].count)
        }
        if tabs[1].count != 6 {
                t.Errorf("videos count = %d, want 6 (4+2)", tabs[1].count)
        }
        if tabs[2].count != 3 {
                t.Errorf("gifs count = %d, want 3", tabs[2].count)
        }
        if tabs[6].count != -1 {
                t.Errorf("links count = %d, want -1 (unknown)", tabs[6].count)
        }

        // Zero-count kinds are hidden; Photos stays even at zero.
        tabs = sharedTabsFor([]engine.SharedMediaCountItem{{MediaType: "video", Count: 2}, {MediaType: "file", Count: 1}})
        if len(tabs) != 4 {
                t.Fatalf("video+file → %d tabs, want 4 (image,video,file,links)", len(tabs))
        }
        if tabs[0].key != "image" || tabs[0].count != 0 {
                t.Errorf("photos tab with zero images = %+v, want count 0", tabs[0])
        }
}

func TestWrapChipRows(t *testing.T) {
        tabs := []sharedTab{
                {"image", "Photos", 0}, {"video", "Videos", 0}, {"gif", "GIFs", 0},
                {"voice", "Voice", 0}, {"audio", "Audio", 0}, {"file", "Files", 0},
                {"links", "Links", -1},
        }
        // Wide bar: one row.
        rows := wrapChipRows(600, tabs)
        if len(rows) != 1 || len(rows[0]) != 7 {
                t.Fatalf("wide bar → %d rows, want 1 with 7 chips", len(rows))
        }
        // Narrow bar: every chip wraps alone (maxWidth fits one chip).
        rows = wrapChipRows(estChipWidthDp("Photos"), tabs)
        if len(rows) != 7 {
                t.Fatalf("one-chip-wide bar → %d rows, want 7", len(rows))
        }
        for i, r := range rows {
                if len(r) != 1 || r[0] != i {
                        t.Errorf("row %d = %v, want [%d]", i, r, i)
                }
        }
        // Mid width: leading chips pack, remainder wraps.
        rows = wrapChipRows(3*estChipWidthDp("Photos")+8, tabs)
        if len(rows) < 2 {
                t.Fatalf("3-wide bar → %d rows, want ≥2", len(rows))
        }
        var total int
        for _, r := range rows {
                total += len(r)
        }
        if total != 7 {
                t.Errorf("wrapped %d chips total, want 7", total)
        }
        // No tab list: no rows.
        if rows := wrapChipRows(300, nil); len(rows) != 0 {
                t.Errorf("nil tabs → %d rows, want 0", len(rows))
        }
}

func TestHostOfURL(t *testing.T) {
        cases := []struct{ in, want string }{
                {"https://example.com/a?b=1", "example.com"},
                {"http://plain.org", "plain.org"},
                {"tg://join?invite=abc", "join"},
                {"https://sub.dom.io/path/to/x", "sub.dom.io"},
                {"", ""},
        }
        for _, c := range cases {
                if got := hostOfURL(c.in); got != c.want {
                        t.Errorf("hostOfURL(%q) = %q, want %q", c.in, got, c.want)
                }
        }
}

func TestSharedRowTitleSub(t *testing.T) {
        if got := sharedRowTitle("voice", ""); got != "Voice message" {
                t.Errorf("voice title = %q, want Voice message", got)
        }
        if got := sharedRowTitle("audio", "song.mp3"); got != "song.mp3" {
                t.Errorf("audio title = %q, want song.mp3", got)
        }
        if got := sharedRowTitle("file", ""); got != "File" {
                t.Errorf("file title = %q, want File", got)
        }

        it := engine.SharedMediaItem{FileName: "v.mp4", FileSize: 2048, Duration: 65, Timestamp: 0}
        if sub := sharedRowSub("video", it); sub != "2 KB" {
                // video rows show size + date only (no duration in the sub line;
                // the duration pill is on the thumbnail).
                t.Errorf("video sub = %q, want 2 KB", sub)
        }
        it2 := engine.SharedMediaItem{FileName: "a.mp3", FileSize: 4096, Duration: 185, Timestamp: 1700000000000}
        sub := sharedRowSub("audio", it2)
        if sub != "3:05 · 4 KB · "+fmtTabDate(1700000000000) {
                t.Errorf("audio sub = %q", sub)
        }
        if got := fmtTabDate(0); got != "" {
                t.Errorf("fmtTabDate(0) = %q, want empty", got)
        }
}

func TestTabLabelFor(t *testing.T) {
        cases := []struct{ in, want string }{
                {"image", "photos"}, {"video", "videos"}, {"gif", "GIFs"},
                {"file", "file"}, {"", ""},
        }
        for _, c := range cases {
                if got := tabLabelFor(c.in); got != c.want {
                        t.Errorf("tabLabelFor(%q) = %q, want %q", c.in, got, c.want)
                }
        }
}
