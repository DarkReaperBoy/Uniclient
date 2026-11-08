package tests

import (
	"image"
	"image/color"
	"testing"

	. "uniclient/ui/dialogs"
	"uniclient/ui/history"
	"uniclient/ui/icons"
	. "uniclient/ui/tokens"
)

func TestChatTypeIconSelection(t *testing.T) {
	cases := []struct {
		kind ChatType
		want icons.Icon
	}{
		{ChatBot, icons.DialogsBot},
		{ChatChannel, icons.DialogsChannel},
		{ChatForum, icons.DialogsForum},
	}
	for _, c := range cases {
		got := ChatTypeIcon(c.kind)
		if got.Cell != c.want.Cell {
			t.Fatalf("ChatTypeIcon(%v) cell = %+v, want %+v", c.kind, got.Cell, c.want.Cell)
		}
		if len(got.Glyph.Paths) != len(c.want.Glyph.Paths) {
			t.Fatalf("ChatTypeIcon(%v) contours = %d, want %d", c.kind, len(got.Glyph.Paths), len(c.want.Glyph.Paths))
		}
	}
	plain := ChatTypeIcon(ChatPlain)
	if plain.Cell.W != 0 || plain.Cell.H != 0 || len(plain.Glyph.Paths) != 0 {
		t.Fatalf("plain chats must carry no chat-type icon: %+v", plain)
	}
}

func TestBadgeIconSelection(t *testing.T) {
	cases := []struct {
		kind BadgeKind
		want icons.Icon
	}{
		{BadgePinned, icons.DialogsPinned},
		{BadgeMention, icons.DialogsMention},
		{BadgeReaction, icons.DialogsReaction},
		{BadgePoll, icons.DialogsPoll},
	}
	for _, c := range cases {
		got := BadgeIcon(c.kind)
		if got.Cell != c.want.Cell {
			t.Fatalf("BadgeIcon(%v) cell = %+v, want %+v", c.kind, got.Cell, c.want.Cell)
		}
		if len(got.Glyph.Paths) != len(c.want.Glyph.Paths) {
			t.Fatalf("BadgeIcon(%v) contours = %d, want %d", c.kind, len(got.Glyph.Paths), len(c.want.Glyph.Paths))
		}
	}
}

func TestChatTypeIconCanvasWidths(t *testing.T) {
	for _, c := range []struct {
		kind ChatType
		want int
	}{
		{ChatBot, 17},
		{ChatChannel, 15},
		{ChatForum, 20},
	} {
		if w := ChatTypeIcon(c.kind).Cell.W; w != c.want {
			t.Fatalf("ChatTypeIcon(%v) width = %d, want %d", c.kind, w, c.want)
		}
	}
	if w := icons.DialogsPinned.Cell.W; w != 20 {
		t.Fatalf("pinned canvas width = %d, want 20 (right-aligned on it)", w)
	}
}

func TestPinnedBadgeRightAlignedToCanvas(t *testing.T) {
	m := Metrics{
		SemiboldHeight: 18, NormalDescent: 4, TextAscent: 13, TextHeight: 17,
		UnreadAscent: 12, UnreadHeight: 15, NameWidth: 100, DateWidth: 30, CounterWidth: 10,
	}
	pinnedW := icons.DialogsPinned.Cell.W
	l := Layout(Entry{Name: "Alice", Date: "12:30", Pinned: true}, 300, m)
	if len(l.Badges) != 1 || l.Badges[0].Kind != BadgePinned {
		t.Fatalf("pinned quiet row must paint the pinned icon: %+v", l.Badges)
	}
	want := Rect{X: 300 - DialogsRowPadRight - pinnedW, Y: DialogsRowTextTop, W: pinnedW, H: pinnedW}
	if l.Badges[0].Cell != want {
		t.Fatalf("pinned icon rect = %+v, want %+v (right-aligned to the %dpx canvas)", l.Badges[0].Cell, want, pinnedW)
	}
	namewidth := 300 - DialogsRowNameLeft - DialogsRowPadRight
	if l.Preview.W != namewidth-(pinnedW+DialogsUnreadPadding) {
		t.Fatalf("preview width = %d, want %d", l.Preview.W, namewidth-(pinnedW+DialogsUnreadPadding))
	}
}

func TestFormatTTLTiny(t *testing.T) {
	cases := []struct {
		sec  int
		want string
	}{
		{0, "0h"},
		{3600, "1h"},
		{32400, "9h"},
		{32401, "0d"},
		{86400, "1d"},
		{518400, "6d"},
		{518401, "0w"},
		{604800, "1w"},
		{1814400, "3w"},
		{1814401, "0m"},
		{2678400, "1m"},
		{29462400, "11m"},
		{29462401, "1y"},
		{31536000, "1y"},
		{31622400, "1y"},
		{31622401, ""},
		{999999999, ""},
	}
	for _, c := range cases {
		if got := FormatTTLTiny(c.sec); got != c.want {
			t.Fatalf("FormatTTLTiny(%d) = %q, want %q", c.sec, got, c.want)
		}
	}
}

func TestTimerClamp(t *testing.T) {
	cases := []struct{ in, want string }{
		{"5h", "5h"},
		{"9h", "9h"},
		{"1y", "1y"},
		{"11m", "11"},
		{"", ""},
	}
	for _, c := range cases {
		if got := TimerClamp(c.in); got != c.want {
			t.Fatalf("TimerClamp(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}

func TestTTLTimerRect(t *testing.T) {
	got := TTLTimerRect(Rect{X: 26, Y: 26, W: 20, H: 20})
	want := Rect{X: 28, Y: 28, W: 16, H: 16}
	if got != want {
		t.Fatalf("TTLTimerRect = %+v, want %+v", got, want)
	}
}

func solidNRGBA(size int, c color.NRGBA) *image.NRGBA {
	img := image.NewNRGBA(image.Rect(0, 0, size, size))
	for y := 0; y < size; y++ {
		for x := 0; x < size; x++ {
			img.SetNRGBA(x, y, c)
		}
	}
	return img
}

func TestStackBlurConstants(t *testing.T) {
	src := solidNRGBA(46, color.NRGBA{R: 137, G: 137, B: 137, A: 255})
	out := StackBlur(src, 24)
	for y := 0; y < 46; y++ {
		for x := 0; x < 46; x++ {
			r, g, b, _ := out.At(x, y).RGBA()
			if uint8(r) != 137 || uint8(g) != 137 || uint8(b) != 137 {
				t.Fatalf("constant image must survive the blur: (%d,%d) = %d %d %d", x, y, uint8(r), uint8(g), uint8(b))
			}
		}
	}
	small := solidNRGBA(20, color.NRGBA{R: 5, G: 10, B: 200, A: 255})
	if out := StackBlur(small, 24); out != small {
		t.Fatal("radius >= dimension must return the source untouched")
	}
	if out := StackBlur(src, 0); out != src {
		t.Fatal("radius < 1 must return the source untouched")
	}
}

func TestTTLBackdropContrastLaw(t *testing.T) {
	badge := image.Rect(26, 26, 46, 46)
	cases := []struct {
		name string
		src  color.NRGBA
		want uint8
	}{
		{"white darkens to 204", color.NRGBA{R: 255, G: 255, B: 255, A: 255}, 204},
		{"black keeps contrast", color.NRGBA{R: 0, G: 0, B: 0, A: 255}, 0},
		{"gray118 stays (4.54:1)", color.NRGBA{R: 118, G: 118, B: 118, A: 255}, 118},
		{"gray128 darkens (3.95:1)", color.NRGBA{R: 128, G: 128, B: 128, A: 255}, 102},
	}
	for _, c := range cases {
		out := TTLBackdrop(solidNRGBA(46, c.src), badge)
		if got := out.Bounds(); got != badge {
			t.Fatalf("%s: backdrop bounds = %v, want %v", c.name, got, badge)
		}
		r, g, b, _ := out.At(35, 35).RGBA()
		if uint8(r) != c.want || uint8(g) != c.want || uint8(b) != c.want {
			t.Fatalf("%s: backdrop pixel = %d %d %d, want %d", c.name, uint8(r), uint8(g), uint8(b), c.want)
		}
	}
}

func TestHistoryInfoWidthReservesTicks(t *testing.T) {
	if history.InfoWidth(40, false) != 40 {
		t.Fatalf("plain info width = %d, want 40", history.InfoWidth(40, false))
	}
	if got := history.InfoWidth(40, true); got != 64 {
		t.Fatalf("out info width = %d, want 64 (40 + 24 ticks)", got)
	}
	if got := history.SkipBlockWidth(history.InfoWidth(40, true)); got != 74 {
		t.Fatalf("out skip width = %d, want 74 (12 + 64 - 2)", got)
	}
	if HistorySendStateSpace != 24 {
		t.Fatalf("ticks space token = %d, want 24", HistorySendStateSpace)
	}
}
