package gui

import (
	"image/color"
	"strings"
	"testing"

	"uniclient/cores"
	"uniclient/engine"
)

// utf16 helpers under test: entity offsets are UTF-16 code units.

// TestShotRunsPlain: no entities → one plain run.
func TestShotRunsPlain(t *testing.T) {
	runs := shotRunsFromEntities("hello world", nil)
	if len(runs) != 1 || runs[0].text != "hello world" || runs[0].styled() {
		t.Fatalf("runs = %+v", runs)
	}
}

// TestShotRunsBold: a bold entity splits into plain+bold+plain.
func TestShotRunsBold(t *testing.T) {
	runs := shotRunsFromEntities("say **hi** now", []cores.TextEntity{
		{Type: "bold", Offset: 4, Length: 6}, // "**hi**"
	})
	if len(runs) != 3 {
		t.Fatalf("runs = %+v", runs)
	}
	if runs[0].text != "say " || runs[0].bold {
		t.Fatalf("run0 = %+v", runs[0])
	}
	if runs[1].text != "**hi**" || !runs[1].bold {
		t.Fatalf("run1 = %+v", runs[1])
	}
	if runs[2].text != " now" || runs[2].bold {
		t.Fatalf("run2 = %+v", runs[2])
	}
}

// TestShotRunsOverlapping: bold+italic combine onto one run.
func TestShotRunsOverlapping(t *testing.T) {
	runs := shotRunsFromEntities("xxBASICxx", []cores.TextEntity{
		{Type: "bold", Offset: 2, Length: 5},
		{Type: "italic", Offset: 3, Length: 3},
	})
	// segments: xx | B | AS | I | C | xx — the overlap region AS has both
	bold := 0
	both := 0
	for _, r := range runs {
		if r.bold {
			bold++
			if r.italic {
				both++
			}
		}
	}
	if bold != 3 {
		t.Fatalf("bold runs = %d (%+v)", bold, runs)
	}
	if both != 1 {
		t.Fatalf("overlap runs = %d (%+v)", both, runs)
	}
}

// TestShotRunsUTF16: entity offsets are UTF-16 code units — an emoji
// before the entity occupies 2 units in the offset space but 1 rune.
func TestShotRunsUTF16(t *testing.T) {
	// "😀ab" — 😀 is 2 UTF-16 units; bold "ab" starts at offset 2.
	runs := shotRunsFromEntities("😀ab", []cores.TextEntity{
		{Type: "bold", Offset: 2, Length: 2},
	})
	if len(runs) != 2 {
		t.Fatalf("runs = %+v", runs)
	}
	if runs[0].text != "😀" || runs[0].bold {
		t.Fatalf("run0 = %+v", runs[0])
	}
	if runs[1].text != "ab" || !runs[1].bold {
		t.Fatalf("run1 = %+v", runs[1])
	}
}

// TestShotRunsLink: text_url becomes a link run carrying the URL.
func TestShotRunsLink(t *testing.T) {
	runs := shotRunsFromEntities("go there", []cores.TextEntity{
		{Type: "text_url", Offset: 3, Length: 5, URL: "https://example.com"},
	})
	if len(runs) != 2 || !runs[1].link || runs[1].url != "https://example.com" {
		t.Fatalf("runs = %+v", runs)
	}
}

// TestWrapShotLines: greedy wrapping splits at word boundaries and
// honors the width budget.
func TestWrapShotLines(t *testing.T) {
	// fixed-width measurer: each rune = 10px
	measure := func(r shotRun, text string) int { return len([]rune(text)) * 10 }
	runs := []shotRun{{text: "aaa bbb ccc"}, {text: " ddd"}}
	lines := wrapShotLines(runs, 70, measure)
	var texts []string
	for _, l := range lines {
		var b strings.Builder
		for _, r := range l.runs {
			b.WriteString(r.text)
		}
		texts = append(texts, b.String())
	}
	if len(texts) < 2 {
		t.Fatalf("not wrapped: %q", texts)
	}
	for _, tx := range texts {
		if len([]rune(tx))*10 > 70 {
			t.Fatalf("line over budget: %q", tx)
		}
	}
	// the wrap space at the line break is consumed by the newline itself
	joined := strings.Join(texts, "\n")
	if joined != "aaa bbb\nccc ddd" {
		t.Fatalf("content changed: %q", joined)
	}
}

// TestWrapShotLinesLongWord: an unbreakable word longer than the budget
// hard-splits instead of overflowing.
func TestWrapShotLinesLongWord(t *testing.T) {
	measure := func(r shotRun, text string) int { return len([]rune(text)) * 10 }
	lines := wrapShotLines([]shotRun{{text: "aaaaaaaaaaaa"}}, 50, measure)
	var b strings.Builder
	for _, l := range lines {
		for _, r := range l.runs {
			b.WriteString(r.text)
		}
	}
	if b.String() != "aaaaaaaaaaaa" {
		t.Fatalf("content lost: %q", b.String())
	}
	if len(lines) < 3 {
		t.Fatalf("long word not hard-split: %d lines", len(lines))
	}
}

// TestShotFilename: sanitized default save names.
func TestShotFilename(t *testing.T) {
	if got := shotFilename("Alice Bob"); got != "shot-Alice-Bob.png" {
		t.Fatalf("name = %q", got)
	}
	if got := shotFilename(""); !strings.HasPrefix(got, "shot-message-") || !strings.HasSuffix(got, ".png") {
		t.Fatalf("fallback = %q", got)
	}
	if got := shotFilename("a/b\\c:d"); strings.ContainsAny(got, "/\\:") {
		t.Fatalf("unsafe chars kept: %q", got)
	}
}

// TestRenderMessageShot: a synthetic message renders to a non-trivial
// image with sane geometry (sender + styled body + timestamp), and
// encodes as PNG.
func TestRenderMessageShot(t *testing.T) {
	msg := engine.CachedMessage{
		SenderName:    "Alice",
		SenderColorID: 3,
		ContentText:   "The **quick** brown fox jumps over the lazy dog — twice, for a wrap check.",
		Timestamp:     1737000000,
		IsOutgoing:    false,
	}
	msg.ContentRich = []byte(`[{"type":"bold","offset":4,"length":6}]`)
	img, err := renderMessageShot(msg, shotPalette{bubble: color.NRGBA{R: 0x18, G: 0x2C, B: 0x3A, A: 0xFF}, text: color.NRGBA{R: 0xF0, G: 0xF4, B: 0xF8, A: 0xFF}})
	if err != nil {
		t.Fatalf("render: %v", err)
	}
	b := img.Bounds()
	if b.Dx() < 200 || b.Dy() < 60 {
		t.Fatalf("image too small: %dx%d", b.Dx(), b.Dy())
	}
	if raw, err := shotPNGBytes(img); err != nil || len(raw) == 0 {
		t.Fatalf("png encode: %v (%d bytes)", err, len(raw))
	}
}

// TestRenderMessageShotReplyAndForward: quote/forward blocks expand the
// layout without changing the body.
func TestRenderMessageShotReplyAndForward(t *testing.T) {
	base := engine.CachedMessage{
		SenderName:   "Bob",
		ContentText:  "hello",
		Timestamp:    1737000000,
		ReplyPreview: "Alice: previous message text",
		ForwardFrom:  "Channel X",
	}
	img, err := renderMessageShot(base, shotPalette{bubble: color.NRGBA{R: 0x18, G: 0x2C, B: 0x3A, A: 0xFF}, text: color.NRGBA{R: 0xFF, G: 0xFF, B: 0xFF, A: 0xFF}})
	if err != nil {
		t.Fatalf("render: %v", err)
	}
	if img.Bounds().Dy() < 120 {
		t.Fatalf("quote/forward not rendered: %dpx tall", img.Bounds().Dy())
	}
}
