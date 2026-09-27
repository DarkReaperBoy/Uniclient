package cores

import (
	"unicode/utf16"
	"unicode/utf8"
)

// Hostile-input fuzzing for the XMPP styling parsers (slice 306):
// applyStyling runs on EVERY incoming xmpp message (B-50/F-60) and
// byte-slices with indices derived from a marker scan — a panic here
// would kill the client on one hostile message (§1.10).

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

		// Invariant 1: applyStyling PRESERVES UTF-8 validity — valid
		// input never yields invalid output. (The oracle first asserted
		// validity unconditionally and failed on the fuzz-found input
		// "\xb7" — an invalid byte in, invalid byte out through the
		// pass-through path. XML bodies are valid UTF-8 by spec, so the
		// contract is preservation, not sanitization — oracle fixed in
		// slice 306, seed kept to pin the pass-through.)
		if utf8.ValidString(text) && !utf8.ValidString(cleaned) {
			t.Fatalf("applyStyling broke UTF-8: %q -> %q", text, cleaned)
		}

		// Invariant 2: entity bounds fit INSIDE the cleaned text
		// (measured in UTF-16 units — the GUI's coordinate space).
		text16 := len(utf16.Encode([]rune(cleaned)))
		for _, e := range ents {
			if e.Offset < 0 || e.Length <= 0 || e.Offset+e.Length > text16 {
				t.Fatalf("entity %+v escapes %q (%d utf16 units)", e, cleaned, text16)
			}
			if e.Type == "" {
				t.Fatalf("entity with empty type: %+v", e)
			}
		}

		// Invariant 3: determinism — same input, same output.
		cleaned2, ents2 := applyStyling(text)
		if cleaned2 != cleaned || len(ents2) != len(ents) {
			t.Fatalf("non-deterministic: %q/%d vs %q/%d", cleaned, len(ents), cleaned2, len(ents2))
		}
	})
}
