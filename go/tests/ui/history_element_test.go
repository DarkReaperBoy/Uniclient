package tests

import (
	"testing"

	"uniclient/ui/history"
)

func TestDateBadgeHeight(t *testing.T) {
	cases := []struct {
		fontH int
		want  int
	}{
		{18, 37},
		{20, 39},
	}
	for _, c := range cases {
		if got := history.DateBadgeHeight(c.fontH); got != c.want {
			t.Errorf("DateBadgeHeight(%d) = %d, want %d", c.fontH, got, c.want)
		}
	}
}

func TestSkipBlock(t *testing.T) {
	if got := history.SkipBlockWidth(45); got != 55 {
		t.Errorf("SkipBlockWidth(45) = %d, want 55", got)
	}
	if got := history.SkipBlockWidth(0); got != 10 {
		t.Errorf("SkipBlockWidth(0) = %d, want 10", got)
	}
	if got := history.SkipBlockHeight(18); got != 13 {
		t.Errorf("SkipBlockHeight(18) = %d, want 13", got)
	}
}

func TestBubbleTextWidth(t *testing.T) {
	cases := []struct {
		bubbleW int
		want    int
	}{
		{200, 178},
		{160, 138},
		{100, 138},
		{0, 138},
	}
	for _, c := range cases {
		if got := history.BubbleTextWidth(c.bubbleW); got != c.want {
			t.Errorf("BubbleTextWidth(%d) = %d, want %d", c.bubbleW, got, c.want)
		}
	}
}

func TestTextualMaxWidth(t *testing.T) {
	if got := history.TextualMaxWidth(true, 100); got != 122 {
		t.Errorf("TextualMaxWidth(true, 100) = %d, want 122", got)
	}
	if got := history.TextualMaxWidth(false, 100); got != 22 {
		t.Errorf("TextualMaxWidth(false, 100) = %d, want 22", got)
	}
}

func TestBubbleWidthLimit(t *testing.T) {
	if got := history.BubbleWidthLimit(false, 0); got != 430 {
		t.Errorf("BubbleWidthLimit(false, 0) = %d, want 430", got)
	}
	if got := history.BubbleWidthLimit(false, 500); got != 500 {
		t.Errorf("BubbleWidthLimit(false, 500) = %d, want 500", got)
	}
	if got := history.BubbleWidthLimit(true, 0); got != 0x3FFFFFF {
		t.Errorf("BubbleWidthLimit(true, 0) = %d, want 0x3FFFFFF", got)
	}
}

func TestServiceTimeBadgeMetrics(t *testing.T) {
	b := history.ServiceTimeBadgeMetrics(20, 15, 18)
	if b.Width != 34 || b.Height != 19 || b.AdditionalWidth != 33 || b.SkipWidth != 33 || b.SkipHeight != 19 {
		t.Errorf("ServiceTimeBadgeMetrics(20,15,18) = %+v, want {34 19 33 33 19}", b)
	}
	b = history.ServiceTimeBadgeMetrics(0, 15, 18)
	if b.Width != 0 || b.Height != 0 || b.AdditionalWidth != 0 || b.SkipWidth != 0 || b.SkipHeight != 0 {
		t.Errorf("ServiceTimeBadgeMetrics(0,15,18) = %+v, want zero", b)
	}
	b = history.ServiceTimeBadgeMetrics(5, 15, 18)
	if b.AdditionalWidth != 18 {
		t.Errorf("ServiceTimeBadgeMetrics(5,15,18).AdditionalWidth = %d, want 18", b.AdditionalWidth)
	}
}

func TestMessageMargins(t *testing.T) {
	top := []struct {
		name string
		ctx  history.MessageCtx
		want int
	}{
		{"plain", history.MessageCtx{}, 6},
		{"attached", history.MessageCtx{Attached: true}, 0},
		{"hidden", history.MessageCtx{Hidden: true}, 0},
		{"date", history.MessageCtx{Bars: history.Bars{Date: 37}}, 43},
		{"hidden keeps bars", history.MessageCtx{Hidden: true, Bars: history.Bars{Date: 37, Unread: 19}}, 56},
		{"service pre above", history.MessageCtx{ServicePre: history.ServicePre{Height: 24}}, 30},
		{"service pre below", history.MessageCtx{ServicePre: history.ServicePre{Below: true, Height: 24}}, 6},
		{"added", history.MessageCtx{Added: history.AddedMargins{Top: 5}}, 11},
		{"full", history.MessageCtx{Attached: true, Bars: history.Bars{Date: 37, Unread: 19, Thread: 32}, ServicePre: history.ServicePre{Height: 24}, Added: history.AddedMargins{Top: 5}}, 117},
	}
	for _, c := range top {
		if got := history.MessageMarginTop(c.ctx); got != c.want {
			t.Errorf("MessageMarginTop(%s) = %d, want %d", c.name, got, c.want)
		}
	}
	bottom := []struct {
		name string
		ctx  history.MessageCtx
		want int
	}{
		{"plain", history.MessageCtx{}, 2},
		{"hidden", history.MessageCtx{Hidden: true}, 0},
		{"service pre below", history.MessageCtx{ServicePre: history.ServicePre{Below: true, Height: 24}}, 26},
		{"service pre above", history.MessageCtx{ServicePre: history.ServicePre{Height: 24}}, 2},
		{"added", history.MessageCtx{Added: history.AddedMargins{Bottom: 7}}, 9},
	}
	for _, c := range bottom {
		if got := history.MessageMarginBottom(c.ctx); got != c.want {
			t.Errorf("MessageMarginBottom(%s) = %d, want %d", c.name, got, c.want)
		}
	}
}

func TestServiceMargins(t *testing.T) {
	top := []struct {
		name string
		ctx  history.ServiceCtx
		want int
	}{
		{"plain", history.ServiceCtx{}, 10},
		{"hidden", history.ServiceCtx{Hidden: true}, 0},
		{"hidden keeps bars", history.ServiceCtx{Hidden: true, Bars: history.Bars{Date: 37}}, 37},
		{"date and unread", history.ServiceCtx{Bars: history.Bars{Date: 37, Unread: 19}}, 66},
		{"service pre unconditional", history.ServiceCtx{ServicePreHeight: 24}, 34},
		{"service pre below still counts", history.ServiceCtx{ServicePreBelow: true, ServicePreHeight: 24}, 34},
		{"added", history.ServiceCtx{Added: history.AddedMargins{Top: 5}}, 15},
	}
	for _, c := range top {
		if got := history.ServiceMarginTop(c.ctx); got != c.want {
			t.Errorf("ServiceMarginTop(%s) = %d, want %d", c.name, got, c.want)
		}
	}
	bottom := []struct {
		name string
		ctx  history.ServiceCtx
		want int
	}{
		{"plain", history.ServiceCtx{}, 2},
		{"hidden still pays", history.ServiceCtx{Hidden: true}, 2},
		{"added", history.ServiceCtx{Added: history.AddedMargins{Bottom: 7}}, 9},
	}
	for _, c := range bottom {
		if got := history.ServiceMarginBottom(c.ctx); got != c.want {
			t.Errorf("ServiceMarginBottom(%s) = %d, want %d", c.name, got, c.want)
		}
	}
}

func TestMessageOptimalSize(t *testing.T) {
	cases := []struct {
		name        string
		t           history.Text
		ctx         history.MessageCtx
		nameWidth   int
		wantW       int
		wantH       int
		wantNonText int
	}{
		{"plain", history.Text{MaxWidth: 100, MinHeight: 20}, history.MessageCtx{VisibleText: true, Bubble: true}, 0, 122, 36, 0},
		{"from name wider", history.Text{MaxWidth: 100, MinHeight: 20}, history.MessageCtx{VisibleText: true, Bubble: true, FromName: true}, 200, 222, 36, 222},
		{"from name narrower", history.Text{MaxWidth: 100, MinHeight: 20}, history.MessageCtx{VisibleText: true, Bubble: true, FromName: true}, 50, 122, 36, 72},
		{"no text", history.Text{MaxWidth: 100, MinHeight: 20}, history.MessageCtx{Bubble: true}, 0, 22, 16, 0},
	}
	for _, c := range cases {
		opt, nonText := history.MessageOptimalSize(c.t, c.ctx, c.nameWidth)
		if opt.Width != c.wantW || opt.Height != c.wantH || nonText != c.wantNonText {
			t.Errorf("MessageOptimalSize(%s) = {%d %d} nonText %d, want {%d %d} nonText %d",
				c.name, opt.Width, opt.Height, nonText, c.wantW, c.wantH, c.wantNonText)
		}
	}
}

func TestMessageGeometry(t *testing.T) {
	cases := []struct {
		name  string
		ctx   history.MessageCtx
		w     int
		h     int
		maxW  int
		nonTx int
		real  int
		mono  int
		want  history.Geometry
	}{
		{"in wide pane", history.MessageCtx{}, 600, 100, 122, 0, 100, 0, history.Geometry{Left: 16, Top: 6, Width: 122, Height: 92}},
		{"out wide pane", history.MessageCtx{Out: true}, 600, 100, 122, 0, 100, 0, history.Geometry{Left: 422, Top: 6, Width: 122, Height: 92}},
		{"narrow pane", history.MessageCtx{}, 150, 100, 322, 0, 300, 0, history.Geometry{Left: 16, Top: 6, Width: 78, Height: 92}},
		{"from photo", history.MessageCtx{FromPhoto: true}, 600, 100, 122, 0, 100, 0, history.Geometry{Left: 56, Top: 6, Width: 122, Height: 92}},
		{"from photo right action", history.MessageCtx{FromPhoto: true, RightActionW: 31}, 600, 100, 500, 0, 460, 0, history.Geometry{Left: 56, Top: 6, Width: 430, Height: 92}},
		{"centered normal", history.MessageCtx{Centered: true}, 600, 100, 122, 0, 100, 0, history.Geometry{Left: 239, Top: 6, Width: 122, Height: 92}},
		{"centered wide", history.MessageCtx{Centered: true, Mode: history.ModeWide}, 800, 100, 122, 0, 100, 0, history.Geometry{Left: 210, Top: 6, Width: 122, Height: 92}},
		{"out wide mode no align", history.MessageCtx{Out: true, Mode: history.ModeWide}, 800, 100, 122, 0, 100, 0, history.Geometry{Left: 16, Top: 6, Width: 122, Height: 92}},
		{"unlimited", history.MessageCtx{Unlimited: true}, 600, 100, 560, 0, 540, 0, history.Geometry{Left: 16, Top: 6, Width: 528, Height: 92}},
		{"right layout", history.MessageCtx{RightLayout: true}, 600, 100, 122, 0, 100, 0, history.Geometry{Left: 56, Top: 6, Width: 122, Height: 92}},
		{"right layout narrow", history.MessageCtx{RightLayout: true, Mode: history.ModeNarrow}, 600, 100, 122, 0, 100, 0, history.Geometry{Left: 16, Top: 6, Width: 122, Height: 92}},
		{"non text max shrinks", history.MessageCtx{}, 600, 100, 400, 350, 100, 0, history.Geometry{Left: 16, Top: 6, Width: 350, Height: 92}},
	}
	for _, c := range cases {
		got := history.MessageGeometry(c.w, c.h, c.maxW, c.nonTx, c.real, c.mono, c.ctx)
		if got != c.want {
			t.Errorf("MessageGeometry(%s) = %+v, want %+v", c.name, got, c.want)
		}
	}
}

func TestMessageHeight(t *testing.T) {
	oneLine := history.Text{MaxWidth: 100, MinHeight: 20, HeightFor: func(int) (int, int) { return 20, 100 }}
	wrapText := history.Text{MaxWidth: 300, MinHeight: 20, HeightFor: func(w int) (int, int) {
		switch {
		case w >= 300:
			return 20, 300
		case w >= 150:
			return 40, w
		default:
			return 60, 150
		}
	}}
	longText := history.Text{MaxWidth: 478, MinHeight: 20, HeightFor: func(w int) (int, int) {
		if w >= 478 {
			return 20, 478
		}
		return 40, w
	}}
	fonts := history.Fonts{NameHeight: 18, DateHeight: 18}
	cases := []struct {
		name  string
		ctx   history.MessageCtx
		w     int
		maxW  int
		minH  int
		nonTx int
		infoH int
		mono  int
		t     history.Text
		want  int
	}{
		{"single line at max", history.MessageCtx{VisibleText: true, Bubble: true}, 600, 122, 36, 0, 18, 0, oneLine, 44},
		{"wrapped", history.MessageCtx{VisibleText: true, Bubble: true}, 200, 322, 36, 0, 18, 0, wrapText, 84},
		{"min width floor", history.MessageCtx{VisibleText: true, Bubble: true}, 100, 322, 36, 0, 18, 0, wrapText, 84},
		{"unlimited fits", history.MessageCtx{VisibleText: true, Bubble: true, Unlimited: true}, 600, 500, 36, 0, 18, 0, longText, 44},
		{"unlimited narrow", history.MessageCtx{VisibleText: true, Bubble: true, Unlimited: true}, 460, 500, 36, 0, 18, 0, longText, 64},
		{"mono limit wide", history.MessageCtx{VisibleText: true, Bubble: true}, 600, 500, 36, 0, 18, 500, longText, 44},
		{"mono limit narrow", history.MessageCtx{VisibleText: true, Bubble: true}, 480, 500, 36, 0, 18, 500, longText, 64},
		{"name and info", history.MessageCtx{VisibleText: true, Bubble: true, FromName: true, NeedInfo: true}, 600, 122, 36, 0, 36, 0, oneLine, 80},
		{"from photo right action", history.MessageCtx{VisibleText: true, Bubble: true, FromPhoto: true, RightActionW: 31}, 600, 122, 36, 0, 18, 0, oneLine, 44},
		{"centered", history.MessageCtx{VisibleText: true, Bubble: true, Centered: true}, 600, 122, 36, 0, 18, 0, oneLine, 44},
		{"attached", history.MessageCtx{VisibleText: true, Bubble: true, Attached: true}, 600, 122, 36, 0, 18, 0, oneLine, 38},
		{"hidden", history.MessageCtx{Hidden: true}, 600, 122, 36, 0, 18, 0, oneLine, 0},
	}
	for _, c := range cases {
		got := history.MessageHeight(c.w, c.maxW, c.minH, c.nonTx, c.infoH, c.mono, c.t, c.ctx, fonts)
		if got != c.want {
			t.Errorf("MessageHeight(%s) = %d, want %d", c.name, got, c.want)
		}
	}
}

func TestServiceOptimalSize(t *testing.T) {
	opt := history.ServiceOptimalSize(history.Text{MaxWidth: 100, MinHeight: 18})
	if opt.Width != 124 || opt.Height != 18 {
		t.Errorf("ServiceOptimalSize = {%d %d}, want {124 18}", opt.Width, opt.Height)
	}
}

func TestServiceGeometry(t *testing.T) {
	cases := []struct {
		name string
		ctx  history.ServiceCtx
		w    int
		h    int
		want history.Geometry
	}{
		{"plain", history.ServiceCtx{}, 600, 50, history.Geometry{Left: 10, Top: 10, Width: 580, Height: 38}},
		{"wide", history.ServiceCtx{Mode: history.ModeWide}, 600, 50, history.Geometry{Left: 10, Top: 10, Width: 522, Height: 38}},
		{"date bar", history.ServiceCtx{Bars: history.Bars{Date: 37}}, 600, 50, history.Geometry{Left: 10, Top: 47, Width: 580, Height: 1}},
	}
	for _, c := range cases {
		got := history.ServiceGeometry(c.w, c.h, c.ctx)
		if got != c.want {
			t.Errorf("ServiceGeometry(%s) = %+v, want %+v", c.name, got, c.want)
		}
	}
}

func TestServiceHeight(t *testing.T) {
	svcText := history.Text{MaxWidth: 100, MinHeight: 18, HeightFor: func(w int) (int, int) {
		if w >= 500 {
			return 18, w
		}
		if w >= 50 {
			return 36, w
		}
		return 72, 40
	}}
	cases := []struct {
		name string
		ctx  history.ServiceCtx
		w    int
		maxW int
		minH int
		want int
	}{
		{"plain fits", history.ServiceCtx{HasText: true}, 600, 124, 18, 37},
		{"plain wraps", history.ServiceCtx{HasText: true}, 100, 124, 18, 55},
		{"floor", history.ServiceCtx{HasText: true}, 40, 124, 18, 91},
		{"empty text", history.ServiceCtx{}, 600, 124, 18, 0},
		{"empty text with date", history.ServiceCtx{Bars: history.Bars{Date: 37}}, 600, 124, 18, 37},
		{"hidden", history.ServiceCtx{Hidden: true}, 600, 124, 18, 0},
		{"hidden with date", history.ServiceCtx{Hidden: true, Bars: history.Bars{Date: 37}}, 600, 124, 18, 37},
		{"wide clamp wraps", history.ServiceCtx{HasText: true, Mode: history.ModeWide}, 600, 560, 18, 55},
	}
	for _, c := range cases {
		got := history.ServiceHeight(c.w, c.maxW, c.minH, svcText, c.ctx)
		if got != c.want {
			t.Errorf("ServiceHeight(%s) = %d, want %d", c.name, got, c.want)
		}
	}
}
