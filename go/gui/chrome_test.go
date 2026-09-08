package gui

import (
	"testing"

	"uniclient/engine"
)

// Chat-chrome pure helpers (gui/chrome.go).

func mkMsg(id string, ts int64) engine.CachedMessage {
	return engine.CachedMessage{MsgID: id, Timestamp: ts}
}

func TestUnreadSepIndex(t *testing.T) {
	cases := []struct {
		n, unread, want int
	}{
		{0, 0, -1},
		{10, 0, -1},
		{0, 3, -1},
		{10, 3, 7},
		{10, 10, 0},
		{10, 25, 0}, // more unread than messages → top
		{1, 1, 0},
	}
	for _, c := range cases {
		if got := unreadSepIndex(c.n, c.unread); got != c.want {
			t.Errorf("unreadSepIndex(%d,%d) = %d, want %d", c.n, c.unread, got, c.want)
		}
	}
}

func TestBuildChatRows(t *testing.T) {
	// Midnight-based so day boundaries are exact.
	day := func(h int) int64 { return 1_699_920_000_000 + int64(h)*3_600_000 }
	msgs := []engine.CachedMessage{
		mkMsg("a", day(0)),
		mkMsg("b", day(1)),
		mkMsg("c", day(25)), // next day
		mkMsg("d", day(26)),
	}

	t.Run("dividers only", func(t *testing.T) {
		rows := buildChatRows(msgs, "")
		if len(rows) != 6 { // 4 messages + 2 day dividers
			t.Fatalf("rows = %d, want 6", len(rows))
		}
		days := 0
		for _, r := range rows {
			if r.day != "" {
				days++
			}
			if r.unread {
				t.Fatal("no separator expected")
			}
		}
		if days != 2 {
			t.Fatalf("day dividers = %d, want 2", days)
		}
	})

	t.Run("separator anchored before its message", func(t *testing.T) {
		// Anchor on d: same day as c, so no day divider sits between the
		// separator and d — adjacency is exact.
		rows := buildChatRows(msgs, "d")
		var sepAt, dAt = -1, -1
		for i, r := range rows {
			if r.unread {
				sepAt = i
			}
			if r.msgIdx >= 0 && msgs[r.msgIdx].MsgID == "d" {
				dAt = i
			}
		}
		if sepAt != dAt-1 {
			t.Fatalf("separator at %d, message d at %d — want separator directly before", sepAt, dAt)
		}
	})

	t.Run("anchor absent = no separator", func(t *testing.T) {
		rows := buildChatRows(msgs, "zzz")
		for _, r := range rows {
			if r.unread {
				t.Fatal("separator should not render when the anchor is not in the window")
			}
		}
	})

	t.Run("empty messages", func(t *testing.T) {
		if rows := buildChatRows(nil, "a"); len(rows) != 0 {
			t.Fatalf("rows = %d, want 0", len(rows))
		}
	})
}

func TestRowIndexOf(t *testing.T) {
	day := func(h int) int64 { return int64(1_700_000_000_000 + h*3_600_000) }
	msgs := []engine.CachedMessage{mkMsg("a", day(0)), mkMsg("b", day(1)), mkMsg("c", day(25))}

	t.Run("with separator consistent with buildChatRows", func(t *testing.T) {
		rows := buildChatRows(msgs, "b")
		want := -1
		for i, r := range rows {
			if r.msgIdx >= 0 && msgs[r.msgIdx].MsgID == "c" {
				want = i
			}
		}
		if got := rowIndexOf(msgs, "c", "b"); got != want {
			t.Errorf("rowIndexOf(c) = %d, want %d (must match buildChatRows)", got, want)
		}
	})

	t.Run("missing id", func(t *testing.T) {
		if got := rowIndexOf(msgs, "zz", ""); got != -1 {
			t.Errorf("rowIndexOf(zz) = %d, want -1", got)
		}
	})

	t.Run("first message row", func(t *testing.T) {
		if got := rowIndexOf(msgs, "a", ""); got != 1 { // row 0 is the day divider
			t.Errorf("rowIndexOf(a) = %d, want 1", got)
		}
	})
}

func TestPinnedPreview(t *testing.T) {
	m := &engine.CachedMessage{ContentText: "hello world"}
	if got := pinnedPreview(m); got != "hello world" {
		t.Errorf("text preview = %q", got)
	}
	m = &engine.CachedMessage{HasMedia: true, MediaType: engine.MediaImage}
	if got := pinnedPreview(m); got != "Photo" {
		t.Errorf("media preview = %q, want Photo", got)
	}
	m = &engine.CachedMessage{}
	if got := pinnedPreview(m); got != "" {
		t.Errorf("empty preview = %q", got)
	}
}

func TestPinnedTitle(t *testing.T) {
	if got := pinnedTitle(1); got != "Pinned message" {
		t.Errorf("pinnedTitle(1) = %q", got)
	}
	if got := pinnedTitle(3); got != "Pinned messages (3)" {
		t.Errorf("pinnedTitle(3) = %q", got)
	}
}
