package utils

import (
	"regexp"
	"strings"
)

var (
	// Code blocks (``` ... ```) — must be processed before inline patterns.
	reCodeBlock = regexp.MustCompile("(?s)```[a-zA-Z]*\n?(.*?)```")

	// Inline code (` ... `).
	reInlineCode = regexp.MustCompile("`([^`]+)`")

	// Links: [text](url)
	reLink = regexp.MustCompile(`\[([^\]]+)\]\([^\)]+\)`)

	// Bold: **text** or __text__
	reBold = regexp.MustCompile(`\*\*(.+?)\*\*|__(.+?)__`)

	// Strikethrough: ~~text~~
	reStrikethrough = regexp.MustCompile(`~~(.+?)~~`)

	// Italic: *text* or _text_ (single marker, after bold is already removed).
	reItalicStar       = regexp.MustCompile(`\*(.+?)\*`)
	reItalicUnderscore = regexp.MustCompile(`_(.+?)_`)

	// Headings: lines starting with one or more #.
	reHeading = regexp.MustCompile(`(?m)^#{1,6}\s+`)

	// Blockquotes: lines starting with >.
	reBlockquote = regexp.MustCompile(`(?m)^>\s?`)

	// Unordered list markers: lines starting with - or * followed by a space.
	reUnorderedList = regexp.MustCompile(`(?m)^[\t ]*[-*]\s+`)

	// Ordered list markers: lines starting with digits followed by . and space.
	reOrderedList = regexp.MustCompile(`(?m)^[\t ]*\d+\.\s+`)

	// Markdown-detection heuristics.
	mdPatterns = []*regexp.Regexp{
		regexp.MustCompile(`\*\*.+?\*\*`),       // bold
		regexp.MustCompile(`__.+?__`),            // bold alt
		regexp.MustCompile(`(?:^|[^\\])\*.+?\*`), // italic
		regexp.MustCompile(`(?:^|[^\\])_.+?_`),   // italic alt
		regexp.MustCompile("`.+?`"),               // inline code
		regexp.MustCompile("```"),                 // code block fence
		regexp.MustCompile(`~~.+?~~`),             // strikethrough
		regexp.MustCompile(`\[.+?\]\(.+?\)`),      // link
		regexp.MustCompile(`(?m)^#{1,6}\s`),       // heading
	}

	// Characters that have special meaning in Markdown.
	mdSpecialChars = strings.NewReplacer(
		`\`, `\\`,
		"`", "\\`",
		"*", `\*`,
		"_", `\_`,
		"~", `\~`,
		"[", `\[`,
		"]", `\]`,
		"(", `\(`,
		")", `\)`,
		"#", `\#`,
		">", `\>`,
		"-", `\-`,
	)
)

// PlainTextSummary strips Markdown formatting from the input and returns a
// plain-text summary truncated to maxLen characters. If the result is longer
// than maxLen, it is truncated and "..." is appended.
func PlainTextSummary(markdown string, maxLen int) string {
	if markdown == "" {
		return ""
	}

	s := markdown

	// 1. Code blocks → keep content, remove fences.
	s = reCodeBlock.ReplaceAllString(s, "$1")

	// 2. Inline code → keep content, remove backticks.
	s = reInlineCode.ReplaceAllString(s, "$1")

	// 3. Links → keep link text.
	s = reLink.ReplaceAllString(s, "$1")

	// 4. Bold → keep content.
	s = reBold.ReplaceAllString(s, "$1$2")

	// 5. Strikethrough → keep content.
	s = reStrikethrough.ReplaceAllString(s, "$1")

	// 6. Italic → keep content.
	s = reItalicStar.ReplaceAllString(s, "$1")
	s = reItalicUnderscore.ReplaceAllString(s, "$1")

	// 7. Headings.
	s = reHeading.ReplaceAllString(s, "")

	// 8. Blockquotes.
	s = reBlockquote.ReplaceAllString(s, "")

	// 9. List markers.
	s = reUnorderedList.ReplaceAllString(s, "")
	s = reOrderedList.ReplaceAllString(s, "")

	// Collapse whitespace.
	s = strings.Join(strings.Fields(s), " ")
	s = strings.TrimSpace(s)

	if maxLen > 0 && len([]rune(s)) > maxLen {
		return string([]rune(s)[:maxLen]) + "..."
	}
	return s
}

// ContainsMarkdown returns true when the text appears to contain Markdown
// formatting that would render differently from plain text. This is a quick
// heuristic, not a full parser.
func ContainsMarkdown(text string) bool {
	for _, re := range mdPatterns {
		if re.MatchString(text) {
			return true
		}
	}
	return false
}

// EscapeMarkdown escapes Markdown special characters so they render as
// literal text in a Markdown context.
func EscapeMarkdown(text string) string {
	return mdSpecialChars.Replace(text)
}
