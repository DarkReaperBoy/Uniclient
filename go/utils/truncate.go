package utils

import "unicode/utf8"

// Truncate cuts s to at most max RUNES without ever splitting a
// multi-byte character (BUGS B-28: the previous byte slices produced
// invalid UTF-8 — mojibake — whenever the cut landed mid-rune). No
// ellipsis is added; see TruncateEllipsis for the "..." variant.
func Truncate(s string, max int) string {
	if utf8.RuneCountInString(s) <= max {
		return s
	}
	count := 0
	for i := range s {
		if count == max {
			return s[:i]
		}
		count++
	}
	return s
}

// TruncateEllipsis is Truncate plus "..." — but only when a cut
// actually happened, so short strings pass through untouched.
func TruncateEllipsis(s string, max int) string {
	if utf8.RuneCountInString(s) <= max {
		return s
	}
	return Truncate(s, max) + "..."
}
