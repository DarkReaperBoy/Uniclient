package cores

import (
	"unicode/utf16"
	"unicode/utf8"
)

import "testing"

func FuzzParseMessageStyling(f *testing.F) {
	f.Add("")
	f.Add("*bold* and _italic_ with `code` and ~strike~")
	f.Add("```pre block```")
	f.Add("*")
	f.Add("****")
	f.Add(string(make([]byte, 256)))
	f.Add("é *bold é* done")
	f.Add("😀_emoji italic_")
	f.Fuzz(func(t *testing.T, text string) {
		spans := ParseMessageStyling(text)
		for _, sp := range spans {
			if sp["style"] == "" || sp["text"] == "" {
				t.Fatalf("degenerate span: %#v", sp)
			}
		}
	})
}

func FuzzApplyStyling(f *testing.F) {
	f.Add("")
	f.Add("*bold* tail")
	f.Add("```pre``` ```second```")
	f.Add("*a **b** c*")
	f.Add("``````")
	f.Add("*_`~ all four ~`_*")
	f.Add("trailing * unmatched")
	f.Add("é *bold é* done")
	f.Add("😀 *hi 😀 there* ok")
	f.Add("\x00*\x01*")
	f.Fuzz(func(t *testing.T, text string) {
		cleaned, ents := applyStyling(text)

		if utf8.ValidString(text) && !utf8.ValidString(cleaned) {
			t.Fatalf("applyStyling broke UTF-8: %q -> %q", text, cleaned)
		}

		text16 := len(utf16.Encode([]rune(cleaned)))
		for _, e := range ents {
			if e.Offset < 0 || e.Length <= 0 || e.Offset+e.Length > text16 {
				t.Fatalf("entity %+v escapes %q (%d utf16 units)", e, cleaned, text16)
			}
			if e.Type == "" {
				t.Fatalf("entity with empty type: %+v", e)
			}
		}

		cleaned2, ents2 := applyStyling(text)
		if cleaned2 != cleaned || len(ents2) != len(ents) {
			t.Fatalf("non-deterministic: %q/%d vs %q/%d", cleaned, len(ents), cleaned2, len(ents2))
		}
	})
}
