package gui

import (
	"testing"

	"uniclient/cores"
)

// Compose markdown (AyuGram parity slice 33).

func TestParseMarkdownBasic(t *testing.T) {
	cases := []struct {
		in    string
		want  string
		etype string
	}{
		{"*bold*", "bold", "bold"},
		{"**bold**", "bold", "bold"},
		{"_italic_", "italic", "italic"},
		{"__underline__", "underline", "underline"},
		{"~strike~", "strike", "strike"},
		{"~~strike~~", "strike", "strike"},
		{"||spoiler||", "spoiler", "spoiler"},
		{"`code`", "code", "code"},
	}
	for _, c := range cases {
		got, ents := parseMarkdown(c.in)
		if got != c.want {
			t.Errorf("parseMarkdown(%q) text = %q, want %q", c.in, got, c.want)
			continue
		}
		if len(ents) != 1 || ents[0].Type != c.etype || ents[0].Offset != 0 || ents[0].Length != utf16Len(c.want) {
			t.Errorf("parseMarkdown(%q) ents = %+v", c.in, ents)
		}
	}
}

func TestParseMarkdownMixed(t *testing.T) {
	in := "plain *bold* plain _it_ tail"
	got, ents := parseMarkdown(in)
	want := "plain bold plain it tail"
	if got != want {
		t.Fatalf("text = %q, want %q", got, want)
	}
	if len(ents) != 2 {
		t.Fatalf("ents = %+v, want 2", ents)
	}
	// "bold" starts at rune index 6 → UTF-16 offset 6.
	if ents[0].Type != "bold" || ents[0].Offset != 6 || ents[0].Length != 4 {
		t.Errorf("bold ent = %+v", ents[0])
	}
	// "it" starts at 17.
	if ents[1].Type != "italic" || ents[1].Offset != 17 || ents[1].Length != 2 {
		t.Errorf("italic ent = %+v", ents[1])
	}
}

func TestParseMarkdownNested(t *testing.T) {
	in := "*bold _both_*"
	got, ents := parseMarkdown(in)
	if got != "bold both" {
		t.Fatalf("text = %q", got)
	}
	if len(ents) != 2 {
		t.Fatalf("ents = %+v, want 2 (bold + inner italic)", ents)
	}
	var bold, italic *cores.TextEntity
	for i := range ents {
		if ents[i].Type == "bold" {
			bold = &ents[i]
		}
		if ents[i].Type == "italic" {
			italic = &ents[i]
		}
	}
	if bold == nil || bold.Offset != 0 || bold.Length != 9 {
		t.Errorf("bold = %+v", bold)
	}
	if italic == nil || italic.Offset != 5 || italic.Length != 4 {
		t.Errorf("italic (shifted to outer) = %+v", italic)
	}
}

func TestParseMarkdownPre(t *testing.T) {
	in := "see ```line1\nline2``` end"
	got, ents := parseMarkdown(in)
	want := "see line1\nline2 end"
	if got != want {
		t.Fatalf("text = %q, want %q", got, want)
	}
	if len(ents) != 1 || ents[0].Type != "pre" || ents[0].Offset != 4 || ents[0].Length != utf16Len("line1\nline2") {
		t.Errorf("pre ent = %+v", ents)
	}
}

func TestParseMarkdownUnmatched(t *testing.T) {
	for _, in := range []string{"*no close", "a_b", "orphan `", "", "plain text"} {
		got, ents := parseMarkdown(in)
		if got != in {
			t.Errorf("parseMarkdown(%q) = %q, want unchanged", in, got)
		}
		if len(ents) != 0 {
			t.Errorf("parseMarkdown(%q) ents = %+v, want none", in, ents)
		}
	}
}

func TestHasMarkdown(t *testing.T) {
	if hasMarkdown("plain text") {
		t.Error("plain flagged")
	}
	if !hasMarkdown("*bold*") {
		t.Error("bold not flagged")
	}
	if !hasMarkdown("||sp||") {
		t.Error("spoiler not flagged")
	}
	if hasMarkdown("*one") {
		t.Error("unmatched flagged")
	}
}
