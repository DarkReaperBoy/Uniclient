package utils

import (
	"testing"
)

// ---------------------------------------------------------------------------
// PlainTextSummary
// ---------------------------------------------------------------------------

func TestPlainTextSummary_Bold(t *testing.T) {
	got := PlainTextSummary("**hello**", 100)
	if got != "hello" {
		t.Errorf("bold: got %q, want %q", got, "hello")
	}
}

func TestPlainTextSummary_Italic(t *testing.T) {
	tests := []struct {
		in, want string
	}{
		{"*italic*", "italic"},
		{"_italic_", "italic"},
	}
	for _, tt := range tests {
		got := PlainTextSummary(tt.in, 100)
		if got != tt.want {
			t.Errorf("italic %q: got %q, want %q", tt.in, got, tt.want)
		}
	}
}

func TestPlainTextSummary_Strikethrough(t *testing.T) {
	got := PlainTextSummary("~~removed~~", 100)
	if got != "removed" {
		t.Errorf("strikethrough: got %q, want %q", got, "removed")
	}
}

func TestPlainTextSummary_InlineCode(t *testing.T) {
	got := PlainTextSummary("`code here`", 100)
	if got != "code here" {
		t.Errorf("inline code: got %q, want %q", got, "code here")
	}
}

func TestPlainTextSummary_Links(t *testing.T) {
	got := PlainTextSummary("[click here](https://example.com)", 100)
	if got != "click here" {
		t.Errorf("link: got %q, want %q", got, "click here")
	}
}

func TestPlainTextSummary_CodeBlock(t *testing.T) {
	input := "```go\nfmt.Println(\"hi\")\n```"
	got := PlainTextSummary(input, 200)
	want := "fmt.Println(\"hi\")"
	if got != want {
		t.Errorf("code block: got %q, want %q", got, want)
	}
}

func TestPlainTextSummary_Headings(t *testing.T) {
	tests := []struct {
		in, want string
	}{
		{"# Title", "Title"},
		{"## Subtitle", "Subtitle"},
		{"### Deep heading", "Deep heading"},
	}
	for _, tt := range tests {
		got := PlainTextSummary(tt.in, 100)
		if got != tt.want {
			t.Errorf("heading %q: got %q, want %q", tt.in, got, tt.want)
		}
	}
}

func TestPlainTextSummary_Truncation(t *testing.T) {
	got := PlainTextSummary("Hello world, this is a long message", 5)
	want := "Hello..."
	if got != want {
		t.Errorf("truncation: got %q, want %q", got, want)
	}
}

func TestPlainTextSummary_Empty(t *testing.T) {
	got := PlainTextSummary("", 100)
	if got != "" {
		t.Errorf("empty: got %q, want %q", got, "")
	}
}

func TestPlainTextSummary_PlainRoundTrip(t *testing.T) {
	plain := "Just some normal text without formatting"
	got := PlainTextSummary(plain, 200)
	if got != plain {
		t.Errorf("round-trip: got %q, want %q", got, plain)
	}
}

func TestPlainTextSummary_Mixed(t *testing.T) {
	input := "**bold** and *italic* with [a link](http://x.com)"
	got := PlainTextSummary(input, 200)
	want := "bold and italic with a link"
	if got != want {
		t.Errorf("mixed: got %q, want %q", got, want)
	}
}

// ---------------------------------------------------------------------------
// ContainsMarkdown
// ---------------------------------------------------------------------------

func TestContainsMarkdown_True(t *testing.T) {
	cases := []string{
		"**bold**",
		"*italic*",
		"`code`",
		"~~strike~~",
		"[link](url)",
		"```code```",
		"# heading",
	}
	for _, c := range cases {
		if !ContainsMarkdown(c) {
			t.Errorf("expected true for %q", c)
		}
	}
}

func TestContainsMarkdown_False(t *testing.T) {
	cases := []string{
		"plain text",
		"hello world",
		"no formatting here",
	}
	for _, c := range cases {
		if ContainsMarkdown(c) {
			t.Errorf("expected false for %q", c)
		}
	}
}

// ---------------------------------------------------------------------------
// EscapeMarkdown
// ---------------------------------------------------------------------------

func TestEscapeMarkdown(t *testing.T) {
	tests := []struct {
		in, want string
	}{
		{"**bold**", `\*\*bold\*\*`},
		{"`code`", "\\`code\\`"},
		{"~~strike~~", `\~\~strike\~\~`},
		{"[text](url)", `\[text\]\(url\)`},
		{"# heading", `\# heading`},
	}
	for _, tt := range tests {
		got := EscapeMarkdown(tt.in)
		if got != tt.want {
			t.Errorf("escape %q: got %q, want %q", tt.in, got, tt.want)
		}
	}
}
