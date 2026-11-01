package gui

import (
	"strings"

	"uniclient/cores"
)

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
			if close <= 0 {
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

func hasMarkdown(text string) bool {
	for _, r := range mdRules {
		if strings.Count(text, r.marker) >= 2 {
			return true
		}
	}
	return false
}
