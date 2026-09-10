package gui

import (
	"strings"

	"uniclient/cores"
)

// Compose-side markdown (AyuGram parity slice 33).
//
// Telegram clients convert typed markdown to entity formatting when
// sending. Supported markers (Telegram Web/AyuGram set):
//
//	**bold**   __underline__   ||spoiler||   ~~strike~~
//	*bold*     _italic_        ~strike~      `code`
//	```pre block```
//
// Entities reference the cleaned text in UTF-16 code units — same as
// cores.TextEntity. Nesting works (bold inside italic etc.); offsets of
// inner entities are shifted to the outer text.

// mdRule maps a marker pair to an entity type.
type mdRule struct {
	marker string
	etype  string
}

var mdRules = []mdRule{
	{"```", "pre"},
	{"**", "bold"},
	{"__", "underline"},
	{"||", "spoiler"},
	{"~~", "strike"},
	{"*", "bold"},
	{"_", "italic"},
	{"~", "strike"},
	{"`", "code"},
}

// parseMarkdown converts marked-up text to clean text + entities.
func parseMarkdown(text string) (string, []cores.TextEntity) {
	var b strings.Builder
	var ents []cores.TextEntity
	i := 0
	for i < len(text) {
		matched := false
		for _, r := range mdRules {
			if !strings.HasPrefix(text[i:], r.marker) {
				continue
			}
			inner := i + len(r.marker)
			close := strings.Index(text[inner:], r.marker)
			if close <= 0 { // no closer, or empty content → literal
				continue
			}
			closeIdx := inner + close
			content := text[inner:closeIdx]

			offset := utf16Len(b.String())
			cleanInner, innerEnts := parseMarkdown(content)
			b.WriteString(cleanInner)
			length := utf16Len(cleanInner)
			if length > 0 {
				ents = append(ents, cores.TextEntity{Type: r.etype, Offset: offset, Length: length})
			}
			for _, e := range innerEnts {
				e.Offset += offset
				ents = append(ents, e)
			}
			i = closeIdx + len(r.marker)
			matched = true
			break
		}
		if matched {
			continue
		}
		b.WriteByte(text[i])
		i++
	}
	return b.String(), ents
}

// hasMarkdown reports whether the text contains any marker pair (cheap
// pre-check so plain sends skip the parse).
func hasMarkdown(text string) bool {
	for _, r := range mdRules {
		if strings.Count(text, r.marker) >= 2 {
			return true
		}
	}
	return false
}
