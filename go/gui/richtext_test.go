package gui

import (
	"testing"

	"uniclient/cores"
)

// Rich-text parsing (AyuGram parity slice 32).

func segText(segs []richSegment) string {
	out := ""
	for _, s := range segs {
		out += s.text
	}
	return out
}

func segAt(segs []richSegment, text string) map[string]richStyle {
	out := map[string]richStyle{}
	for _, s := range segs {
		out[s.text] = s.style
	}
	return out
}

func TestParseRichSegmentsRoundTrip(t *testing.T) {
	text := "bold and normal"
	ents := []cores.TextEntity{{Type: "bold", Offset: 0, Length: 4}} // "bold"
	segs := parseRichSegments(text, ents)
	if got := segText(segs); got != text {
		t.Fatalf("round-trip text = %q, want %q", got, text)
	}
	by := segAt(segs, text)
	if !by["bold"].bold {
		t.Errorf("bold segment not bold: %+v", by["bold"])
	}
	if by["and"].bold {
		t.Errorf("normal segment marked bold")
	}
}

func TestParseRichSegmentsUTF16(t *testing.T) {
	// "👍bold" — emoji is 2 UTF-16 units; entity covers "bold" at offset 2.
	text := "👍bold"
	ents := []cores.TextEntity{{Type: "italic", Offset: 2, Length: 4}}
	segs := parseRichSegments(text, ents)
	by := segAt(segs, text)
	if !by["bold"].italic {
		t.Errorf("italic not applied after emoji: %+v", by["bold"])
	}
	if by["👍"].italic {
		t.Errorf("emoji segment wrongly italic")
	}
}

func TestParseRichSegmentsOverlap(t *testing.T) {
	text := "abcdef"
	ents := []cores.TextEntity{
		{Type: "bold", Offset: 0, Length: 4},   // abcd
		{Type: "italic", Offset: 2, Length: 4}, // cdef
	}
	segs := parseRichSegments(text, ents)
	by := segAt(segs, text)
	if !by["ab"].bold || by["ab"].italic {
		t.Errorf("ab = %+v", by["ab"])
	}
	if !by["cd"].bold || !by["cd"].italic {
		t.Errorf("cd should be bold+italic: %+v", by["cd"])
	}
	if !by["ef"].italic || by["ef"].bold {
		t.Errorf("ef = %+v", by["ef"])
	}
}

func TestParseRichSegmentsBounds(t *testing.T) {
	// Out-of-range entities clamp instead of slicing panics.
	text := "hi"
	ents := []cores.TextEntity{
		{Type: "spoiler", Offset: -5, Length: 100},
		{Type: "code", Offset: 1, Length: 99},
	}
	segs := parseRichSegments(text, ents)
	if got := segText(segs); got != text {
		t.Fatalf("clamped round-trip = %q", got)
	}
}

func TestApplyEntityStyles(t *testing.T) {
	st := richStyle{}
	applyEntity(&st, cores.TextEntity{Type: "spoiler", Offset: 0, Length: 1})
	applyEntity(&st, cores.TextEntity{Type: "text_url", Offset: 0, Length: 1, URL: "https://x"})
	applyEntity(&st, cores.TextEntity{Type: "pre", Offset: 0, Length: 1})
	if !st.spoiler || !st.mono || st.link != "https://x" || !st.underline {
		t.Errorf("merged style = %+v", st)
	}
}

func TestSplitTokens(t *testing.T) {
	toks := splitTokens(richSegment{text: "a  b c", style: richStyle{bold: true}})
	if len(toks) != 5 {
		t.Fatalf("tokens = %d (%v), want 5", len(toks), toks)
	}
	if toks[0].text != "a" || !toks[0].style.bold || toks[0].space {
		t.Errorf("tok0 = %+v", toks[0])
	}
	if toks[1].text != "  " || !toks[1].space {
		t.Errorf("tok1 = %+v", toks[1])
	}
	if toks[4].text != "c" {
		t.Errorf("tok4 = %+v", toks[4])
	}
}

func TestSpoilerHas(t *testing.T) {
	if spoilerHas(nil) {
		t.Error("nil entities have spoiler")
	}
	if spoilerHas([]cores.TextEntity{{Type: "bold"}}) {
		t.Error("bold counted as spoiler")
	}
	if !spoilerHas([]cores.TextEntity{{Type: "italic"}, {Type: "spoiler"}}) {
		t.Error("spoiler not detected")
	}
}

func TestUtf16Conversion(t *testing.T) {
	s := "a👍b" // 1 + 2 + 1 units
	if utf16Len(s) != 4 {
		t.Errorf("utf16Len = %d, want 4", utf16Len(s))
	}
	if richIndex(s, 3) != len("a👍") {
		t.Errorf("richIndex(3) = %d, want %d", richIndex(s, 3), len("a👍"))
	}
}

func TestApplyEntityLinkKind(t *testing.T) {
	// slice 92: hashtags carry their entity kind so taps can dispatch
	// to the tag search instead of the browser.
	var st richStyle
	applyEntity(&st, cores.TextEntity{Type: "hashtag", Offset: 0, Length: 5})
	if st.link != "auto" || st.linkKind != "hashtag" {
		t.Errorf("hashtag style = %+v, want auto/hashtag", st)
	}
	st = richStyle{}
	applyEntity(&st, cores.TextEntity{Type: "url", Offset: 0, Length: 5})
	if st.link != "auto" || st.linkKind != "url" {
		t.Errorf("url style = %+v, want auto/url", st)
	}
	st = richStyle{}
	applyEntity(&st, cores.TextEntity{Type: "text_url", URL: "https://x.example", Offset: 0, Length: 5})
	if st.link != "https://x.example" || st.linkKind != "text_url" {
		t.Errorf("text_url style = %+v", st)
	}
}

func TestIsHashtagQuery(t *testing.T) {
	cases := []struct {
		q    string
		want bool
	}{
		{"", false},
		{"#", false},
		{"#n", true},
		{"#news", true},
		{"news", false},
		{"a #news", false}, // tag mode is a leading-# query only
	}
	for _, tc := range cases {
		if got := isHashtagQuery(tc.q); got != tc.want {
			t.Errorf("isHashtagQuery(%q) = %v, want %v", tc.q, got, tc.want)
		}
	}
}
