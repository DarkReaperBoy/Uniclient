package tests

import (
	"testing"

	. "uniclient/ui/dialogs"
	"uniclient/ui/icons"
	. "uniclient/ui/tokens"
)

var pinnedIconSize = icons.DialogsPinned.Cell.W

func rowMetrics() Metrics {
	return Metrics{
		SemiboldHeight: 18,
		NormalDescent:  4,
		TextAscent:     13,
		TextHeight:     17,
		UnreadAscent:   12,
		UnreadHeight:   15,
		NameWidth:      100,
		DateWidth:      30,
		CounterWidth:   10,
		ChatTypeIconW:  0,
	}
}

func TestDialogsRowCoreGeometry(t *testing.T) {
	m := rowMetrics()
	l := Layout(Entry{Name: "Alice", Preview: "hi", Date: "12:30"}, 300, m)
	if l.Narrow {
		t.Fatalf("300dp wide row must not be narrow")
	}
	if l.Height != DialogsRowHeight {
		t.Fatalf("plain row height = %d, want %d", l.Height, DialogsRowHeight)
	}
	if l.Photo != (Rect{X: DialogsRowPadLeft, Y: DialogsRowPadTop, W: DialogsRowPhotoSize, H: DialogsRowPhotoSize}) {
		t.Fatalf("photo rect drifted: %+v", l.Photo)
	}
	namewidth := 300 - DialogsRowNameLeft - DialogsRowPadRight
	wantName := Rect{X: 68, Y: 10, W: namewidth - (m.DateWidth + DialogsDateSkip), H: m.SemiboldHeight}
	if l.Name != wantName {
		t.Fatalf("name rect = %+v, want %+v", l.Name, wantName)
	}
	if l.DateX != 300-DialogsRowPadRight-m.DateWidth {
		t.Fatalf("date x = %d, want %d", l.DateX, 300-DialogsRowPadRight-m.DateWidth)
	}
	if l.DateBaseline != DialogsRowNameTop+m.SemiboldHeight-m.NormalDescent {
		t.Fatalf("date baseline = %d, want %d", l.DateBaseline, DialogsRowNameTop+m.SemiboldHeight-m.NormalDescent)
	}
	wantPreview := Rect{X: 68, Y: DialogsRowTextTop, W: namewidth, H: m.TextHeight}
	if l.Preview != wantPreview {
		t.Fatalf("preview rect = %+v, want %+v", l.Preview, wantPreview)
	}
	if l.ChatTypeIcon.W != 0 || l.SendStateIcon.W != 0 || len(l.Badges) != 0 {
		t.Fatalf("empty row must carry no icons or badges: %+v", l)
	}
	if l.Online.W != 0 || l.TTL.W != 0 {
		t.Fatalf("offline row must carry no photo badges: %+v %+v", l.Online, l.TTL)
	}
}

func TestDialogsRowWithoutDate(t *testing.T) {
	m := rowMetrics()
	m.DateWidth = 0
	l := Layout(Entry{Name: "Alice"}, 300, m)
	namewidth := 300 - DialogsRowNameLeft - DialogsRowPadRight
	if l.Name.W != namewidth {
		t.Fatalf("name width without date = %d, want %d", l.Name.W, namewidth)
	}
	if l.DateX != 0 {
		t.Fatalf("no date must leave DateX zero: %d", l.DateX)
	}
}

func TestDialogsRowUnreadPill(t *testing.T) {
	m := rowMetrics()
	l := Layout(Entry{Name: "Alice", Date: "12:30", Unread: 5}, 300, m)
	if len(l.Badges) != 1 || l.Badges[0].Kind != BadgeCounter {
		t.Fatalf("unread row must paint one counter badge: %+v", l.Badges)
	}
	b := l.Badges[0]
	pillW := DialogsBadgeWidth(m.CounterWidth)
	top := DialogsRowTextTop + m.TextAscent - m.UnreadAscent - (DialogsUnreadHeight-m.UnreadHeight)/2
	want := Rect{X: 300 - DialogsRowPadRight - pillW, Y: top, W: pillW, H: DialogsUnreadHeight}
	if b.Cell != want {
		t.Fatalf("pill cell = %+v, want %+v", b.Cell, want)
	}
	if b.TextBaseline != top+(DialogsUnreadHeight-m.UnreadHeight)/2+m.UnreadAscent {
		t.Fatalf("pill text baseline = %d, want %d",
			b.TextBaseline, top+(DialogsUnreadHeight-m.UnreadHeight)/2+m.UnreadAscent)
	}
	namewidth := 300 - DialogsRowNameLeft - DialogsRowPadRight
	if l.Preview.W != namewidth-(pillW+DialogsUnreadPadding) {
		t.Fatalf("preview width = %d, want %d", l.Preview.W, namewidth-(pillW+DialogsUnreadPadding))
	}
}

func TestDialogsRowUnreadMarkDot(t *testing.T) {
	m := rowMetrics()
	l := Layout(Entry{Name: "Alice", Date: "12:30", UnreadMark: true}, 300, m)
	if len(l.Badges) != 1 || l.Badges[0].Kind != BadgeMark {
		t.Fatalf("mark row must paint one dot badge: %+v", l.Badges)
	}
	b := l.Badges[0]
	top := DialogsRowTextTop + m.TextAscent - m.UnreadAscent - (DialogsUnreadHeight-m.UnreadHeight)/2
	if b.Cell != (Rect{X: 300 - DialogsRowPadRight - DialogsUnreadHeight, Y: top, W: DialogsUnreadHeight, H: DialogsUnreadHeight}) {
		t.Fatalf("dot cell = %+v", b.Cell)
	}
	off := (DialogsUnreadHeight - DialogsUnreadMarkDiameter) / 2
	if b.Dot != (Rect{X: b.Cell.X + off, Y: top + off, W: DialogsUnreadMarkDiameter, H: DialogsUnreadMarkDiameter}) {
		t.Fatalf("dot rect = %+v", b.Dot)
	}
	namewidth := 300 - DialogsRowNameLeft - DialogsRowPadRight
	if l.Preview.W != namewidth-(DialogsUnreadHeight+DialogsUnreadPadding) {
		t.Fatalf("preview width = %d, want %d", l.Preview.W, namewidth-(DialogsUnreadHeight+DialogsUnreadPadding))
	}
}

func TestDialogsRowPinnedAndMention(t *testing.T) {
	m := rowMetrics()
	l := Layout(Entry{Name: "Alice", Date: "12:30", Pinned: true}, 300, m)
	if len(l.Badges) != 1 || l.Badges[0].Kind != BadgePinned {
		t.Fatalf("pinned quiet row must paint the pinned icon: %+v", l.Badges)
	}
	pinned := l.Badges[0]
	if pinned.Cell != (Rect{X: 300 - DialogsRowPadRight - pinnedIconSize, Y: DialogsRowTextTop, W: pinnedIconSize, H: pinnedIconSize}) {
		t.Fatalf("pinned icon rect = %+v (top must be textTop, right-aligned to the canvas)", pinned.Cell)
	}
	namewidth := 300 - DialogsRowNameLeft - DialogsRowPadRight
	if l.Preview.W != namewidth-(pinnedIconSize+DialogsUnreadPadding) {
		t.Fatalf("preview width = %d, want %d", l.Preview.W, namewidth-(pinnedIconSize+DialogsUnreadPadding))
	}

	l = Layout(Entry{Name: "Alice", Date: "12:30", Unread: 5, Mention: true}, 300, m)
	if len(l.Badges) != 2 || l.Badges[0].Kind != BadgeCounter || l.Badges[1].Kind != BadgeMention {
		t.Fatalf("unread+mention must stack counter then mention: %+v", l.Badges)
	}
	top := DialogsRowTextTop + m.TextAscent - m.UnreadAscent - (DialogsUnreadHeight-m.UnreadHeight)/2
	pillW := DialogsBadgeWidth(m.CounterWidth)
	wantMention := Rect{X: 300 - DialogsRowPadRight - pillW - DialogsUnreadPadding - DialogsIconSize, Y: top, W: DialogsIconSize, H: DialogsIconSize}
	if l.Badges[1].Cell != wantMention {
		t.Fatalf("mention icon rect = %+v, want %+v", l.Badges[1].Cell, wantMention)
	}
	if l.Preview.W != namewidth-(pillW+DialogsUnreadPadding)-(DialogsIconSize+DialogsUnreadPadding) {
		t.Fatalf("preview width = %d", l.Preview.W)
	}
}

func TestDialogsRowPollAndOrder(t *testing.T) {
	m := rowMetrics()
	l := Layout(Entry{Name: "A", Date: "12:30", Unread: 2, Mention: true, Reaction: true, Poll: true}, 300, m)
	if len(l.Badges) != 3 {
		t.Fatalf("unread+mention+poll must paint three badges (reaction shares the mention slot): %+v", l.Badges)
	}
	if l.Badges[0].Kind != BadgeCounter || l.Badges[1].Kind != BadgeMention || l.Badges[2].Kind != BadgePoll {
		t.Fatalf("badge order must be counter, mention, poll: %+v", l.Badges)
	}

	l = Layout(Entry{Name: "A", Date: "12:30", Poll: true}, 300, m)
	if len(l.Badges) != 1 || l.Badges[0].Kind != BadgePoll {
		t.Fatalf("poll-only row must paint the poll badge: %+v", l.Badges)
	}
}

func TestDialogsRowNarrowMode(t *testing.T) {
	m := rowMetrics()
	narrowWidth := ColumnMinWidthLeft/2 - 1
	l := Layout(Entry{Name: "Alice", Preview: "hi", Date: "12:30", Unread: 5, Mention: true, Poll: true, Forum: true}, narrowWidth, m)
	if !l.Narrow {
		t.Fatalf("width %d must be narrow (< %d)", narrowWidth, ColumnMinWidthLeft/2)
	}
	if l.Height != DialogsRowHeight {
		t.Fatalf("narrow row height = %d, want %d (collapse to plain)", l.Height, DialogsRowHeight)
	}
	if l.Name.W != 0 || l.Preview.W != 0 || l.DateX != 0 {
		t.Fatalf("narrow row must drop name/preview/date: %+v", l)
	}
	if len(l.Badges) != 2 || l.Badges[0].Kind != BadgeCounter || l.Badges[1].Kind != BadgeMention {
		t.Fatalf("narrow stack is max two badges, poll gated out: %+v", l.Badges)
	}
	anchor := DialogsRowPadLeft + DialogsRowPhotoSize
	pillW := DialogsBadgeWidth(m.CounterWidth)
	if l.Badges[0].Cell != (Rect{X: anchor - pillW, Y: DialogsNarrowBadgeTop(), W: pillW, H: DialogsUnreadHeight}) {
		t.Fatalf("narrow pill = %+v", l.Badges[0].Cell)
	}
	if l.Badges[1].Cell != (Rect{X: anchor - pillW - DialogsUnreadPadding - DialogsUnreadHeight, Y: DialogsNarrowBadgeTop(), W: DialogsUnreadHeight, H: DialogsUnreadHeight}) {
		t.Fatalf("narrow mention must be a 19dp pill cell: %+v", l.Badges[1].Cell)
	}

	mark := Layout(Entry{Name: "A", UnreadMark: true}, narrowWidth, m)
	if len(mark.Badges) != 1 || mark.Badges[0].Kind != BadgeMark {
		t.Fatalf("narrow mark row: %+v", mark.Badges)
	}
	if mark.Badges[0].Cell.X != anchor-DialogsUnreadHeight {
		t.Fatalf("narrow dot cell = %+v", mark.Badges[0].Cell)
	}
}

func TestDialogsRowVariantsMatrix(t *testing.T) {
	m := rowMetrics()
	cases := []struct {
		name        string
		entry       Entry
		wantHeight  int
		wantTextTop int
		wantTagTop  int
	}{
		{"plain", Entry{Name: "A"}, DialogsRowHeight, DialogsRowTextTop, 0},
		{"tagged", Entry{Name: "A", Tagged: true}, DialogsRowTaggedHeight, DialogsRowTaggedTextTop, DialogsRowTaggedTagTop},
		{"forum", Entry{Name: "A", Forum: true}, DialogsRowForumHeight, DialogsRowForumTextTop, 0},
		{"taggedForum", Entry{Name: "A", Tagged: true, Forum: true}, DialogsRowTaggedForumHeight, DialogsRowForumTextTop, DialogsRowTaggedForumTagTop},
	}
	for _, c := range cases {
		l := Layout(c.entry, 300, m)
		if l.Height != c.wantHeight {
			t.Fatalf("%s height = %d, want %d", c.name, l.Height, c.wantHeight)
		}
		if l.Preview.Y != c.wantTextTop {
			t.Fatalf("%s text top = %d, want %d", c.name, l.Preview.Y, c.wantTextTop)
		}
		if l.TagTop != c.wantTagTop {
			t.Fatalf("%s tag top = %d, want %d", c.name, l.TagTop, c.wantTagTop)
		}
	}
	if DialogsRowTaggedForumHeight != 96 || DialogsRowTaggedForumTagTop != 77 {
		t.Fatalf("taggedForum tokens drifted: %d/%d (want 96/77)",
			DialogsRowTaggedForumHeight, DialogsRowTaggedForumTagTop)
	}
}

func TestDialogsRowPhotoBadges(t *testing.T) {
	m := rowMetrics()
	l := Layout(Entry{Name: "Alice", Online: true}, 300, m)
	ox, oy := DialogsOnlineBadgePos(DialogsRowPhotoSize, DialogsOnlineBadgeSize, DialogsOnlineBadgeStroke)
	want := Rect{X: DialogsRowPadLeft + ox, Y: DialogsRowPadTop + oy, W: DialogsOnlineBadgeSize, H: DialogsOnlineBadgeSize}
	if l.Online != want {
		t.Fatalf("online badge = %+v, want %+v", l.Online, want)
	}

	l = Layout(Entry{Name: "Alice", TTL: true}, 300, m)
	tx, ty := DialogsOnlineBadgePos(DialogsRowPhotoSize, DialogsTTLBadgeSize, 0)
	wantTTL := Rect{X: DialogsRowPadLeft + tx, Y: DialogsRowPadTop + ty, W: DialogsTTLBadgeSize, H: DialogsTTLBadgeSize}
	if l.TTL != wantTTL {
		t.Fatalf("ttl badge = %+v, want %+v", l.TTL, wantTTL)
	}

	l = Layout(Entry{Name: "Alice", Online: true, TTL: true}, 300, m)
	if l.Online.W == 0 || l.TTL.W == 0 {
		t.Fatalf("online and ttl badges are independent: %+v %+v", l.Online, l.TTL)
	}
}

func TestDialogsRowIcons(t *testing.T) {
	m := rowMetrics()
	m.ChatTypeIconW = 21
	l := Layout(Entry{Name: "Alice", Date: "12:30", ChatType: ChatBot}, 300, m)
	if l.ChatTypeIcon != (Rect{X: DialogsRowNameLeft, Y: DialogsRowNameTop, W: 21, H: DialogsIconSize}) {
		t.Fatalf("chat type icon rect = %+v", l.ChatTypeIcon)
	}
	namewidth := 300 - DialogsRowNameLeft - DialogsRowPadRight
	if l.Name.X != DialogsRowNameLeft+21+DialogsChatTypeSkip {
		t.Fatalf("name x after chat icon = %d", l.Name.X)
	}
	if l.Name.W != namewidth-21-DialogsChatTypeSkip-(m.DateWidth+DialogsDateSkip) {
		t.Fatalf("name width after chat icon = %d", l.Name.W)
	}

	m2 := rowMetrics()
	l = Layout(Entry{Name: "Alice", SendState: SendReceived}, 300, m2)
	if l.SendStateIcon != (Rect{X: DialogsRowNameLeft + l.Name.W, Y: DialogsRowNameTop, W: DialogsIconSize, H: DialogsIconSize}) {
		t.Fatalf("send state icon rect = %+v (must sit at the shrunk name right edge)", l.SendStateIcon)
	}
	if l.Name.W != 300-DialogsRowNameLeft-DialogsRowPadRight-DialogsSendStateSkip {
		t.Fatalf("name width with send state = %d", l.Name.W)
	}
}

func TestDialogsListHitTesting(t *testing.T) {
	list := List{Rows: []Entry{
		{Name: "a"},
		{Name: "b", Forum: true},
		{Name: "c", Tagged: true},
		{Name: "d", Tagged: true, Forum: true},
	}}
	if h := list.Height(300); h != 62+80+72+96 {
		t.Fatalf("list height = %d, want %d", h, 62+80+72+96)
	}
	if h := list.Height(ColumnMinWidthLeft/2 - 1); h != 4*62 {
		t.Fatalf("narrow list height = %d, want %d", h, 4*62)
	}
	cases := []struct {
		y    int
		want int
	}{
		{0, 0}, {61, 0}, {62, 1}, {141, 1}, {142, 2}, {213, 2}, {214, 3}, {309, 3}, {310, -1}, {-1, -1},
	}
	for _, c := range cases {
		if got := list.RowAt(c.y, 300); got != c.want {
			t.Fatalf("RowAt(%d) = %d, want %d", c.y, got, c.want)
		}
	}
}
