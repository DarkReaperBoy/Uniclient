package dialogs

import (
	"strings"
	"unicode"
	"unicode/utf8"

	"golang.org/x/text/unicode/norm"
)

const searchWordSplitSet = "@-+()[]{}<>,.:!_;\"'"

func isASCII(s string) bool {
	for i := 0; i < len(s); i++ {
		if s[i] >= utf8.RuneSelf {
			return false
		}
	}
	return true
}

func foldAccents(s string) string {
	if isASCII(s) {
		return s
	}
	var b strings.Builder
	b.Grow(len(s))
	for _, r := range norm.NFD.String(s) {
		if unicode.Is(unicode.Mn, r) {
			continue
		}
		b.WriteRune(r)
	}
	return norm.NFC.String(b.String())
}

func searchSplitRune(r rune) bool {
	if r == 0 || unicode.IsSpace(r) {
		return true
	}
	return strings.ContainsRune(searchWordSplitSet, r)
}

func SearchWords(query string) []string {
	folded := foldAccents(strings.ToLower(strings.TrimSpace(query)))
	return strings.FieldsFunc(folded, searchSplitRune)
}

func dedupWords(words []string) []string {
	seen := make(map[string]struct{}, len(words))
	out := words[:0]
	for _, w := range words {
		if _, dup := seen[w]; dup {
			continue
		}
		seen[w] = struct{}{}
		out = append(out, w)
	}
	return out
}

func NameWords(name, username string) []string {
	parts := make([]string, 0, 3)
	parts = append(parts, foldAccents(name))
	if username != "" {
		parts = append(parts, foldAccents(username))
	}
	return dedupWords(SearchWords(strings.Join(parts, " ")))
}

func MatchesNameWords(index, words []string) bool {
	if len(words) == 0 {
		return true
	}
	for _, w := range words {
		found := false
		for _, nw := range index {
			if strings.HasPrefix(nw, w) {
				found = true
				break
			}
		}
		if !found {
			return false
		}
	}
	return true
}
