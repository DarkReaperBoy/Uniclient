package cores

import (
	"strings"
	"testing"
	"unicode/utf16"
)

// B-50 → F-60: ParseMessageStyling existed with zero callers — XMPP
// messages rendered with literal *bold* markers. applyStyling is the
// wiring layer: it converts the parser's byte spans into the GUI's
// UTF-16 TextEntity format AND strips the marker characters so the
// rendered text is clean (Telegram-style: text without markers,
// entities over it).
//
// Seam-RED (WORKLOG 292): undefined: applyStyling.
// Wiring RED: source-scan needs both call sites (initial receive +
// XEP-0308 correction) in handleMessage.

func TestApplyStylingBasicSpans(t *testing.T) {
	cases := []struct {
		name     string
		in       string
		wantText string
		wantEnts []TextEntity // compared as exact set (sorted by offset)
	}{
		{"plain passthrough", "hello world", "hello world", nil},
		{"bold", "x *bold* y", "x bold y", []TextEntity{{Type: "bold", Offset: 2, Length: 4}}},
		{"italic", "_it_ done", "it done", []TextEntity{{Type: "italic", Offset: 0, Length: 2}}},
		{"strike", "keep ~gone~ here", "keep gone here", []TextEntity{{Type: "strike", Offset: 5, Length: 4}}},
		{"code span", "run `rm` now", "run rm now", []TextEntity{{Type: "code", Offset: 4, Length: 2}}},
		{"utf16 offsets", "😀 *b*", "😀 b", []TextEntity{{Type: "bold", Offset: 3, Length: 1}}},
		{"pre block", "```pre```", "pre", []TextEntity{{Type: "pre", Offset: 0, Length: 3}}},
		{"unmatched marker", "a * b", "a * b", nil},
		{"two styles sorted", "`c` and *b*", "c and b", []TextEntity{
			{Type: "code", Offset: 0, Length: 1},
			{Type: "bold", Offset: 6, Length: 1},
		}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			gotText, gotEnts := applyStyling(tc.in)
			if gotText != tc.wantText {
				t.Errorf("text = %q, want %q", gotText, tc.wantText)
			}
			if len(gotEnts) != len(tc.wantEnts) {
				t.Fatalf("entities = %+v, want %+v", gotEnts, tc.wantEnts)
			}
			for i, e := range gotEnts {
				w := tc.wantEnts[i]
				if e.Type != w.Type || e.Offset != w.Offset || e.Length != w.Length {
					t.Errorf("entity[%d] = %+v, want %+v", i, e, w)
				}
			}
			// Invariant: every entity lies inside the cleaned text,
			// measured in UTF-16 code units.
			text16 := len(utf16.Encode([]rune(gotText)))
			for _, e := range gotEnts {
				if e.Offset < 0 || e.Length <= 0 || e.Offset+e.Length > text16 {
					t.Errorf("entity %+v escapes text %q (%d utf16 units)", e, gotText, text16)
				}
			}
		})
	}
}

// TestApplyStylingPreservesInnerStyledMultiByte: emoji INSIDE styled
// text must keep both the entity and its UTF-16 length.
func TestApplyStylingPreservesInnerStyledMultiByte(t *testing.T) {
	gotText, gotEnts := applyStyling("say *hi 😀 there* ok")
	if gotText != "say hi 😀 there ok" {
		t.Fatalf("text = %q", gotText)
	}
	if len(gotEnts) != 1 || gotEnts[0].Type != "bold" {
		t.Fatalf("entities = %+v", gotEnts)
	}
	// "say " = 4 utf16, inner "hi 😀 there" = 2+1(space)+2(😀)+1+5 = 11
	if gotEnts[0].Offset != 4 || gotEnts[0].Length != 11 {
		t.Fatalf("bold offset/len = %d/%d, want 4/11", gotEnts[0].Offset, gotEnts[0].Length)
	}
}

// TestIncomingMessageWiring: source-scan pin — handleMessage must run
// applyStyling on BOTH the initial receive and the XEP-0308
// correction path (headless render → scan precedent B-51).
func TestIncomingMessageWiring(t *testing.T) {
	src, err := readFileLines("xmpp.go")
	if err != nil {
		t.Fatalf("read source: %v", err)
	}
	joined := strings.Join(src, "\n")
	if c := strings.Count(joined, "applyStyling(parsed.Body)"); c < 2 {
		t.Fatalf("applyStyling(parsed.Body) wired %d times, want ≥2 (receive + correction)", c)
	}
}
