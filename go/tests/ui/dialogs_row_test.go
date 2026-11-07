package tests

import (
	"testing"

	. "uniclient/ui/tokens"
)

func TestDialogsBadgeLaw(t *testing.T) {
	if FontDialogsUnread != 12 || DialogsUnreadHeight != 19 || DialogsUnreadPadding != 5 {
		t.Fatalf("badge chrome drifted: font %d, height %d, padding %d (want 12/19/5)",
			FontDialogsUnread, DialogsUnreadHeight, DialogsUnreadPadding)
	}
	cases := []struct {
		textWidth int
		want      int
	}{
		{0, 19}, {5, 19}, {9, 19}, {10, 20}, {42, 52},
	}
	for _, c := range cases {
		if got := DialogsBadgeWidth(c.textWidth); got != c.want {
			t.Fatalf("badge width for text %d = %d, want %d", c.textWidth, got, c.want)
		}
	}
	if DialogsBadgeRadius != 9 {
		t.Fatalf("badge radius drifted: %d (want 9)", DialogsBadgeRadius)
	}
	if DialogsBadgeRadius != DialogsUnreadHeight/2 {
		t.Fatalf("badge radius not derived from height: %d != %d/2",
			DialogsBadgeRadius, DialogsUnreadHeight)
	}
	if DialogsUnreadMarkDiameter != 8 {
		t.Fatalf("unread mark diameter drifted: %d (want 8)", DialogsUnreadMarkDiameter)
	}
	if off := (DialogsUnreadHeight - DialogsUnreadMarkDiameter) / 2; off != 5 {
		t.Fatalf("mark dot not centered in cell: offset %d (want 5)", off)
	}
}

func TestUnreadCounterFormat(t *testing.T) {
	cases := []struct {
		count   int
		mention bool
		narrow  bool
		want    string
	}{
		{0, false, false, ""},
		{0, true, true, ""},
		{1, false, false, "1"},
		{999, true, true, "999"},
		{1000, true, true, "99+"},
		{1000, false, true, "1000"},
		{999999, false, true, "999999"},
		{1000000, false, true, "99999+"},
		{1000000, true, false, "1000000"},
		{1500000, true, true, "99+"},
		{1500000, false, true, "99999+"},
	}
	for _, c := range cases {
		if got := FormatUnreadCounter(c.count, c.mention, c.narrow); got != c.want {
			t.Fatalf("FormatUnreadCounter(%d, %v, %v) = %q, want %q",
				c.count, c.mention, c.narrow, got, c.want)
		}
	}
}

func TestDialogsRowVariants(t *testing.T) {
	if DialogsRowTaggedHeight != 72 || DialogsRowTaggedTextTop != 30 || DialogsRowTaggedTagTop != 52 {
		t.Fatalf("tagged row drifted: %d/%d/%d (want 72/30/52)",
			DialogsRowTaggedHeight, DialogsRowTaggedTextTop, DialogsRowTaggedTagTop)
	}
	if DialogsRowForumHeight != 80 || DialogsRowForumTextTop != 32 ||
		DialogsRowForumTopicsSkip != 8 || DialogsRowForumTopicsSkipBig != 14 ||
		DialogsRowForumTopicsHeight != 21 {
		t.Fatalf("forum row drifted: %d/%d/%d/%d/%d (want 80/32/8/14/21)",
			DialogsRowForumHeight, DialogsRowForumTextTop, DialogsRowForumTopicsSkip,
			DialogsRowForumTopicsSkipBig, DialogsRowForumTopicsHeight)
	}
	if !(DialogsRowHeight < DialogsRowTaggedHeight && DialogsRowTaggedHeight < DialogsRowForumHeight) {
		t.Fatalf("row heights out of order: %d/%d/%d",
			DialogsRowHeight, DialogsRowTaggedHeight, DialogsRowForumHeight)
	}
	if DialogsRowTaggedTagTop <= DialogsRowTaggedTextTop {
		t.Fatalf("tag line must sit below text: %d <= %d",
			DialogsRowTaggedTagTop, DialogsRowTaggedTextTop)
	}
	if DialogsRowForumTopicsSkip >= DialogsRowForumTopicsSkipBig {
		t.Fatalf("forum skips inverted: %d >= %d",
			DialogsRowForumTopicsSkip, DialogsRowForumTopicsSkipBig)
	}
}

func TestDialogsTopRightLaw(t *testing.T) {
	if FontDialogsDate != 13 {
		t.Fatalf("date font drifted: %d (want 13)", FontDialogsDate)
	}
	if FontDialogsDate != FontBase {
		t.Fatalf("date font not the base size: %d != %d", FontDialogsDate, FontBase)
	}
	if DialogsDateSkip != 5 || DialogsChatTypeSkip != 3 {
		t.Fatalf("top-right skips drifted: date %d, chat type %d (want 5/3)",
			DialogsDateSkip, DialogsChatTypeSkip)
	}
	if DialogsSendStateSkip != 20 {
		t.Fatalf("send-state skip drifted: %d (want 20)", DialogsSendStateSkip)
	}
	if DialogsTextWidthMin != 150 {
		t.Fatalf("text min width drifted: %d (want 150)", DialogsTextWidthMin)
	}
	if DialogsRowNameLeft+DialogsTextWidthMin+DialogsRowPadRight > ColumnMinWidthLeft {
		t.Fatalf("min text does not fit the min pane: %d+%d+%d > %d",
			DialogsRowNameLeft, DialogsTextWidthMin, DialogsRowPadRight, ColumnMinWidthLeft)
	}
	if DialogsIconSize != 18 || DialogsIconSize >= DialogsUnreadHeight {
		t.Fatalf("state icon size drifted: %d (want 18 under badge height)", DialogsIconSize)
	}
	if DialogsRightButtonMinPaneWidth != ColumnMinWidthLeft {
		t.Fatalf("right-button gate drifted: %d (want column min %d)",
			DialogsRightButtonMinPaneWidth, ColumnMinWidthLeft)
	}
}

func TestDialogsOnlineBadge(t *testing.T) {
	if DialogsOnlineBadgeSize != 12 || DialogsOnlineBadgeStroke != 3 || DialogsOnlineBadgeDurationMs != 150 {
		t.Fatalf("online badge drifted: %d/%d/%d (want 12/3/150)",
			DialogsOnlineBadgeSize, DialogsOnlineBadgeStroke, DialogsOnlineBadgeDurationMs)
	}
	if DialogsCallBadgeSize != 16 || DialogsTTLBadgeSize != 20 {
		t.Fatalf("call/TTL badge drifted: %d/%d (want 16/20)",
			DialogsCallBadgeSize, DialogsTTLBadgeSize)
	}
	if DialogsOnlineBadgeSize+2*DialogsOnlineBadgeStroke > DialogsRowPhotoSize {
		t.Fatalf("online badge overflows photo: %d > %d",
			DialogsOnlineBadgeSize+2*DialogsOnlineBadgeStroke, DialogsRowPhotoSize)
	}
	if x, y := DialogsOnlineBadgePos(DialogsRowPhotoSize, DialogsOnlineBadgeSize, DialogsOnlineBadgeStroke); x != 33 || y != 33 {
		t.Fatalf("online badge pos drifted: %d,%d (want 33,33)", x, y)
	}
	if x, y := DialogsOnlineBadgePos(DialogsRowPhotoSize, DialogsTTLBadgeSize, 0); x != 26 || y != 26 {
		t.Fatalf("TTL badge pos drifted: %d,%d (want 26,26)", x, y)
	}
	if x, _ := DialogsOnlineBadgePos(DialogsRowPhotoSize, DialogsTTLBadgeSize, 0); x+DialogsTTLBadgeSize != DialogsRowPhotoSize {
		t.Fatalf("TTL badge not flush with photo edge: %d+%d != %d",
			x, DialogsTTLBadgeSize, DialogsRowPhotoSize)
	}
}

func TestDialogsTimings(t *testing.T) {
	if DialogsWidthDurationMs != 120 {
		t.Fatalf("dialogs width duration drifted: %d (want 120)", DialogsWidthDurationMs)
	}
	if DialogsWidthDurationMs != CheckDurationMs {
		t.Fatalf("width duration not the universal duration: %d != %d",
			DialogsWidthDurationMs, CheckDurationMs)
	}
	if got := DialogsNarrowBadgeTop(); got != 35 {
		t.Fatalf("narrow badge top drifted: %d (want 35)", got)
	}
	if DialogsNarrowBadgeTop()+DialogsUnreadHeight != DialogsRowPadTop+DialogsRowPhotoSize {
		t.Fatalf("narrow badge not bottom-aligned with photo: %d+%d != %d+%d",
			DialogsNarrowBadgeTop(), DialogsUnreadHeight, DialogsRowPadTop, DialogsRowPhotoSize)
	}
}
