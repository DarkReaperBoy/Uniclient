package tests

import (
	"reflect"
	"testing"

	"uniclient/ui/history"
	"uniclient/ui/tokens"
)

func TestServiceMsgRadii(t *testing.T) {
	if tokens.ServiceMsgRadius != 10 {
		t.Errorf("ServiceMsgRadius = %d, want 10", tokens.ServiceMsgRadius)
	}
	if tokens.ServiceMsgInvertedRadius != 3 {
		t.Errorf("ServiceMsgInvertedRadius = %d, want 3", tokens.ServiceMsgInvertedRadius)
	}
	if tokens.ServiceMsgInvertedShrink != 2 {
		t.Errorf("ServiceMsgInvertedShrink = %d, want 2", tokens.ServiceMsgInvertedShrink)
	}
}

func TestCountServiceLineWidths(t *testing.T) {
	cases := []struct {
		name string
		in   []int
		add  int
		want []int
	}{
		{"steady growth", []int{100, 140}, 0, []int{100, 140}},
		{"near equal bump", []int{100, 110}, 0, []int{110, 110}},
		{"trailing near equal", []int{100, 110, 90}, 0, []int{110, 110, 110}},
		{"rewalk jump", []int{100, 90, 110}, 0, []int{110, 110, 110}},
		{"last line add", []int{140, 100}, 9, []int{140, 109}},
		{"no add when last is widest", []int{100, 140}, 9, []int{100, 140}},
		{"no add after equalize", []int{100, 90, 110}, 9, []int{110, 110, 110}},
		{"negative clamp", []int{-5, 50}, 0, []int{0, 50}},
		{"empty", nil, 0, nil},
		{"single", []int{80}, 0, []int{80}},
		{"single no add", []int{80}, 9, []int{80}},
	}
	for _, c := range cases {
		if got := history.CountServiceLineWidths(c.in, c.add); !reflect.DeepEqual(got, c.want) {
			t.Errorf("%s: CountServiceLineWidths(%v, %d) = %v, want %v", c.name, c.in, c.add, got, c.want)
		}
	}
}

func TestServiceLastLineWidthAdd(t *testing.T) {
	cases := []struct {
		name    string
		in      []int
		badgeW  int
		wantAdd int
	}{
		{"applied", []int{140, 100}, 30, 9},
		{"last not narrower", []int{100, 140}, 30, 0},
		{"below badge width", []int{140, 100}, 120, 0},
		{"negative middle line", []int{140, -3, 100}, 30, 0},
		{"equal lines", []int{100, 100}, 30, 0},
		{"single", []int{50}, 30, 0},
		{"empty", nil, 30, 0},
	}
	for _, c := range cases {
		if got := history.ServiceLastLineWidthAdd(c.in, c.badgeW); got != c.wantAdd {
			t.Errorf("%s: ServiceLastLineWidthAdd(%v, %d) = %d, want %d", c.name, c.in, c.badgeW, got, c.wantAdd)
		}
	}
}

func TestServiceComplexBubblePartsSingle(t *testing.T) {
	parts := history.ServiceComplexBubbleParts(10, 300, []int{80})
	want := []history.ServiceBubblePart{
		{Left: 108, Top: 10, Width: 104, Height: 20, TopSide: history.ServiceSideRounded, BottomSide: history.ServiceSideRounded, Shrink: false},
	}
	if !reflect.DeepEqual(parts, want) {
		t.Errorf("single line parts = %+v, want %+v", parts, want)
	}
}

func TestServiceComplexBubblePartsWidening(t *testing.T) {
	parts := history.ServiceComplexBubbleParts(10, 300, []int{80, 140})
	want := []history.ServiceBubblePart{
		{Left: 110, Top: 10, Width: 100, Height: 13, TopSide: history.ServiceSideRounded, BottomSide: history.ServiceSideInverted, Shrink: true},
		{Left: 78, Top: 23, Width: 164, Height: 20, TopSide: history.ServiceSideRounded, BottomSide: history.ServiceSideRounded, Shrink: false},
	}
	if !reflect.DeepEqual(parts, want) {
		t.Errorf("widening parts = %+v, want %+v", parts, want)
	}
}

func TestServiceComplexBubblePartsNarrowing(t *testing.T) {
	parts := history.ServiceComplexBubbleParts(10, 300, []int{140, 80})
	want := []history.ServiceBubblePart{
		{Left: 78, Top: 10, Width: 164, Height: 20, TopSide: history.ServiceSideRounded, BottomSide: history.ServiceSideRounded, Shrink: false},
		{Left: 110, Top: 30, Width: 100, Height: 13, TopSide: history.ServiceSideInverted, BottomSide: history.ServiceSideRounded, Shrink: true},
	}
	if !reflect.DeepEqual(parts, want) {
		t.Errorf("narrowing parts = %+v, want %+v", parts, want)
	}
}

func TestServiceComplexBubblePartsEqualLines(t *testing.T) {
	parts := history.ServiceComplexBubbleParts(10, 300, []int{100, 100, 100})
	want := []history.ServiceBubblePart{
		{Left: 98, Top: 10, Width: 124, Height: 16, TopSide: history.ServiceSideRounded, BottomSide: history.ServiceSidePlain, Shrink: false},
		{Left: 98, Top: 26, Width: 124, Height: 13, TopSide: history.ServiceSidePlain, BottomSide: history.ServiceSidePlain, Shrink: false},
		{Left: 98, Top: 39, Width: 124, Height: 17, TopSide: history.ServiceSidePlain, BottomSide: history.ServiceSideRounded, Shrink: false},
	}
	if !reflect.DeepEqual(parts, want) {
		t.Errorf("equal parts = %+v, want %+v", parts, want)
	}
}

func TestServiceComplexBubblePartsForceShrink(t *testing.T) {
	parts := history.ServiceComplexBubbleParts(10, 300, []int{140, 100, 100})
	want := []history.ServiceBubblePart{
		{Left: 78, Top: 10, Width: 164, Height: 20, TopSide: history.ServiceSideRounded, BottomSide: history.ServiceSideRounded, Shrink: false},
		{Left: 100, Top: 30, Width: 120, Height: 9, TopSide: history.ServiceSideInverted, BottomSide: history.ServiceSidePlain, Shrink: true},
		{Left: 100, Top: 39, Width: 120, Height: 17, TopSide: history.ServiceSidePlain, BottomSide: history.ServiceSideRounded, Shrink: true},
	}
	if !reflect.DeepEqual(parts, want) {
		t.Errorf("force shrink parts = %+v, want %+v", parts, want)
	}
}

func TestServiceComplexBubblePartsCenteringTruncatesTowardZero(t *testing.T) {
	parts := history.ServiceComplexBubbleParts(10, 300, []int{401})
	if len(parts) != 1 {
		t.Fatalf("parts len = %d, want 1", len(parts))
	}
	p := parts[0]
	if p.Left != -52 || p.Width != 425 {
		t.Errorf("overflow centering = (%d, %d), want (-52, 425)", p.Left, p.Width)
	}
}

func TestServiceComplexBubblePartsEmpty(t *testing.T) {
	if parts := history.ServiceComplexBubbleParts(10, 300, nil); len(parts) != 0 {
		t.Errorf("empty parts len = %d, want 0", len(parts))
	}
}

func TestServiceBubblePartBands(t *testing.T) {
	cases := []struct {
		name string
		part history.ServiceBubblePart
		want history.ServiceBands
	}{
		{
			"rounded rounded",
			history.ServiceBubblePart{Left: 78, Top: 10, Width: 164, Height: 20, TopSide: history.ServiceSideRounded, BottomSide: history.ServiceSideRounded},
			history.ServiceBands{
				TopBand:    history.Geometry{Left: 78, Top: 10, Width: 164, Height: 10},
				BottomBand: history.Geometry{Left: 78, Top: 20, Width: 164, Height: 10},
				Body:       history.Geometry{Left: 78, Top: 20, Width: 164, Height: 0},
			},
		},
		{
			"rounded inverted",
			history.ServiceBubblePart{Left: 110, Top: 10, Width: 100, Height: 13, TopSide: history.ServiceSideRounded, BottomSide: history.ServiceSideInverted},
			history.ServiceBands{
				TopBand: history.Geometry{Left: 110, Top: 10, Width: 100, Height: 10},
				Body:    history.Geometry{Left: 110, Top: 20, Width: 100, Height: 3},
			},
		},
		{
			"inverted rounded",
			history.ServiceBubblePart{Left: 110, Top: 30, Width: 100, Height: 13, TopSide: history.ServiceSideInverted, BottomSide: history.ServiceSideRounded},
			history.ServiceBands{
				BottomBand: history.Geometry{Left: 110, Top: 33, Width: 100, Height: 10},
				Body:       history.Geometry{Left: 110, Top: 30, Width: 100, Height: 3},
			},
		},
		{
			"inverted plain",
			history.ServiceBubblePart{Left: 100, Top: 30, Width: 120, Height: 9, TopSide: history.ServiceSideInverted, BottomSide: history.ServiceSidePlain},
			history.ServiceBands{
				Body: history.Geometry{Left: 100, Top: 30, Width: 120, Height: 9},
			},
		},
		{
			"rounded plain",
			history.ServiceBubblePart{Left: 98, Top: 10, Width: 124, Height: 16, TopSide: history.ServiceSideRounded, BottomSide: history.ServiceSidePlain},
			history.ServiceBands{
				TopBand: history.Geometry{Left: 98, Top: 10, Width: 124, Height: 10},
				Body:    history.Geometry{Left: 98, Top: 20, Width: 124, Height: 6},
			},
		},
		{
			"plain rounded",
			history.ServiceBubblePart{Left: 98, Top: 39, Width: 124, Height: 17, TopSide: history.ServiceSidePlain, BottomSide: history.ServiceSideRounded},
			history.ServiceBands{
				BottomBand: history.Geometry{Left: 98, Top: 46, Width: 124, Height: 10},
				Body:       history.Geometry{Left: 98, Top: 39, Width: 124, Height: 7},
			},
		},
	}
	for _, c := range cases {
		if got := c.part.Bands(); !reflect.DeepEqual(got, c.want) {
			t.Errorf("%s: Bands() = %+v, want %+v", c.name, got, c.want)
		}
	}
}
