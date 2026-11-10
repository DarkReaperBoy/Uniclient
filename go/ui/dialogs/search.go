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

func MatchesWords(name string, words []string) bool {
	if len(words) == 0 {
		return true
	}
	nameWords := SearchWords(name)
	for _, w := range words {
		found := false
		for _, nw := range nameWords {
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
