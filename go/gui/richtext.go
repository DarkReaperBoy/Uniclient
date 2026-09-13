package gui

import (
	"encoding/json"
	"image"
	"image/color"
	"math"
	"sort"
	"strings"
	"unicode/utf16"

	"gioui.org/font"
	"gioui.org/io/event"
	"gioui.org/io/pointer"
	"gioui.org/layout"
	"gioui.org/op"
	"gioui.org/op/clip"
	"gioui.org/op/paint"
	"gioui.org/unit"
	"gioui.org/widget"

	"uniclient/cores"
	"uniclient/engine"
)

// Rich-text rendering (AyuGram parity slice 32).
//
// Telegram messages carry formatting entities (bold, italic, spoiler,
// code, links…). The engine round-trips them in CachedMessage.ContentRich
// (JSON []cores.TextEntity, UTF-16 offsets). This renderer walks entity
// boundaries, merges overlapping styles per segment, and flows styled
// words with wrapping — gio v0.10 has no multi-style paragraph API, so
// each word is recorded to a macro, measured, and placed manually.
//
// Spoilers start hidden (gray pill, glyphs in bubble color) and reveal on
// a click anywhere in the text block.

// a.wid.spoilerBtns are per-message clickables toggling spoiler reveal.

// linkTag marks one tappable link token; the press dispatches by kind:
// hashtags open the in-chat tag search (slice 92), everything else
// opens the platform browser / clipboard fallback.
type linkTag struct {
	msgID string
	url   string
	kind  string // entity type: "hashtag", "url", "mention", …
}

// linkTags caches per-message link tags (index-aligned to drawn tokens).
var linkTags = map[string][]*linkTag{}

// spoilerHas reports whether any entity is a spoiler.
func spoilerHas(entities []cores.TextEntity) bool {
	for _, e := range entities {
		if e.Type == "spoiler" {
			return true
		}
	}
	return false
}

// richStyle is the merged style of one segment (overlapping entities add up).
type richStyle struct {
	bold, italic, underline, strike, mono, spoiler, quote bool
	link                                                  string
	linkKind                                              string
	emojiDoc                                              int64 // custom-emoji document (slice 132)
}

// richSegment is a text slice with its merged style.
type richSegment struct {
	text  string
	style richStyle
}

// utf16Len counts UTF-16 code units in s.
func utf16Len(s string) int {
	n := 0
	for _, r := range s {
		n += utf16.RuneLen(r)
	}
	return n
}

// richIndex maps a UTF-16 code-unit offset to a byte index in s.
func richIndex(s string, u16 int) int {
	count := 0
	for i, r := range s {
		if count >= u16 {
			return i
		}
		count += utf16.RuneLen(r)
	}
	return len(s)
}

// applyEntity folds one entity into the style.
func applyEntity(st *richStyle, e cores.TextEntity) {
	switch e.Type {
	case "bold":
		st.bold = true
	case "italic":
		st.italic = true
	case "underline":
		st.underline = true
	case "strike":
		st.strike = true
	case "code", "pre":
		st.mono = true
	case "spoiler":
		st.spoiler = true
	case "blockquote":
		st.quote = true
	case "text_url":
		st.link = e.URL
		st.linkKind = "text_url"
		st.underline = true
	case "url", "mention", "hashtag", "bot_command", "email", "phone", "cashtag":
		st.link = "auto"
		st.linkKind = e.Type
		st.underline = true
	case "mention_name", "custom_emoji", "formatted_date":
		st.link = "auto"
		st.linkKind = e.Type
		if e.Type == "custom_emoji" && e.DocumentID != 0 {
			st.emojiDoc = e.DocumentID
		}
	}
}

// parseRichSegments splits text by entity boundaries and merges the styles
// covering each slice.
func parseRichSegments(text string, entities []cores.TextEntity) []richSegment {
	if text == "" || len(entities) == 0 {
		return nil
	}
	n := utf16Len(text)
	set := map[int]bool{0: true, n: true}
	for _, e := range entities {
		s, en := e.Offset, e.Offset+e.Length
		if s < 0 {
			s = 0
		}
		if s > n {
			s = n
		}
		if en < s {
			en = s
		}
		if en > n {
			en = n
		}
		set[s], set[en] = true, true
	}
	cuts := make([]int, 0, len(set))
	for k := range set {
		cuts = append(cuts, k)
	}
	sort.Ints(cuts)

	var out []richSegment
	for i := 0; i+1 < len(cuts); i++ {
		a, b := cuts[i], cuts[i+1]
		var seg richSegment
		seg.text = text[richIndex(text, a):richIndex(text, b)]
		for _, e := range entities {
			if e.Offset <= a && a < e.Offset+e.Length {
				applyEntity(&seg.style, e)
			}
		}
		if seg.text != "" {
			out = append(out, seg)
		}
	}
	return out
}

// richToken is a word or space run with a style.
type richToken struct {
	text  string
	style richStyle
	space bool
}

// splitTokens splits a segment into alternating space/word tokens.
func splitTokens(seg richSegment) []richToken {
	var out []richToken
	rest := seg.text
	for rest != "" {
		sp := strings.IndexFunc(rest, func(r rune) bool { return r != ' ' })
		if sp < 0 {
			out = append(out, richToken{rest, seg.style, true})
			return out
		}
		if sp > 0 {
			out = append(out, richToken{rest[:sp], seg.style, true})
			rest = rest[sp:]
		}
		w := strings.IndexByte(rest, ' ')
		if w < 0 {
			out = append(out, richToken{rest, seg.style, false})
			return out
		}
		if w > 0 {
			out = append(out, richToken{rest[:w], seg.style, false})
			rest = rest[w:]
		}
	}
	return out
}

// tokenFont builds the font for a style.
func tokenFont(st richStyle) font.Font {
	f := font.Font{}
	if st.bold {
		f.Weight = font.Bold
	}
	if st.italic {
		f.Style = font.Italic
	}
	if st.mono {
		f.Typeface = "Go Mono"
	}
	return f
}

// richRect is one placed token.
type richRect struct {
	pos  image.Point
	size image.Point
	tok  richToken
	call op.CallOp
	lt   *linkTag  // non-nil for tappable link tokens
	art  *emojiArt // inline custom-emoji artwork (slice 132)
}

// richTextLabel renders the message body with entity formatting; plain
// label fallback when there are no entities. bg is the bubble color
// (hidden spoiler glyphs match it).
func (a *App) richTextLabel(gtx layout.Context, m engine.CachedMessage, size unit.Sp, base, bg color.NRGBA, clickable bool) layout.Dimensions {
	var entities []cores.TextEntity
	if len(m.ContentRich) > 0 {
		_ = json.Unmarshal(m.ContentRich, &entities)
	}
	a.ensureEmojiArt(&m, entities)
	segs := parseRichSegments(m.ContentText, entities)
	if len(segs) == 0 {
		lbl := a.ui.Label(size, m.ContentText)
		lbl.MaxLines = 30
		if base != (color.NRGBA{}) && base != a.ui.p.Text {
			lbl.Color = base
		}
		return lbl.Layout(gtx)
	}

	if clickable && spoilerHas(entities) {
		btn := a.wid.spoilerBtns[m.MsgID]
		if btn == nil {
			btn = new(widget.Clickable)
			a.wid.spoilerBtns[m.MsgID] = btn
		}
		if btn.Clicked(gtx) {
			if a.spoilerRevealed == nil {
				a.spoilerRevealed = map[string]bool{}
			}
			a.spoilerRevealed[m.MsgID] = !a.spoilerRevealed[m.MsgID]
		}
		return btn.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			// Spoiler click owns the press surface; links stay inert here.
			return a.flowRich(gtx, m, size, base, bg, segs, false)
		})
	}
	return a.flowRich(gtx, m, size, base, bg, segs, true)
}

// flowRich measures each token via a macro, wraps at max width, then
// plays the macros back with decorations (code/ spoiler pills, underline,
// strike).
func (a *App) flowRich(gtx layout.Context, m engine.CachedMessage, size unit.Sp, base, bg color.NRGBA, segs []richSegment, linksEnabled bool) layout.Dimensions {
	revealed := a.spoilerRevealed[m.MsgID]
	var tokens []richToken
	for _, seg := range segs {
		tokens = append(tokens, splitTokens(seg)...)
	}
	fontPx := gtx.Dp(unit.Dp(float32(size)))
	artSide := emojiArtSide(fontPx)

	maxW := gtx.Constraints.Max.X
	x, y := 0, 0
	lineH, lineEnd := 0, 0

	measure := func(tok richToken) (image.Point, op.CallOp) {
		col := base
		st := tok.style
		if st.link != "" {
			col = a.ui.p.Accent
		}
		if st.quote {
			col = a.ui.p.TextDim
		}
		if st.spoiler && !revealed {
			col = bg // glyphs invisible until revealed
		}
		lbl := a.ui.Label(size, tok.text)
		lbl.Color = col
		lbl.Font = tokenFont(st)
		macro := op.Record(gtx.Ops)
		measGtx := gtx
		measGtx.Constraints = layout.Constraints{Max: image.Pt(math.MaxInt32, math.MaxInt32)}
		d := lbl.Layout(measGtx)
		call := macro.Stop()
		return d.Size, call
	}

	hasLinks := false
	if linksEnabled {
		for _, tok := range tokens {
			if tok.style.link != "" {
				hasLinks = true
				break
			}
		}
	}
	if hasLinks {
		delete(linkTags, m.MsgID) // rebuild this frame's tags
	}

	var rects []richRect
	for _, tok := range tokens {
		var art *emojiArt
		sz, call := measure(tok)
		if tok.style.emojiDoc != 0 && !tok.space && artSide > 0 {
			art = emojiArts.get(tok.style.emojiDoc)
			if art.kind == emojiArtLottie || art.kind == emojiArtRaster {
				// Inline artwork token: a side×side square replaces the
				// base-glyph text measure.
				sz = image.Pt(artSide, artSide)
				call = op.CallOp{}
			} else {
				art = nil // unknown/unsupported/failed: keep the glyph
			}
		}
		if tok.space {
			if x == 0 {
				continue // no leading spaces after wrap
			}
			if x+sz.X > maxW {
				x, y = 0, y+lineH
				lineH = 0
				continue
			}
		} else if x > 0 && x+sz.X > maxW {
			x, y = 0, y+lineH
			lineH = 0
		}
		if sz.Y > lineH {
			lineH = sz.Y
		}
		var lt *linkTag
		if hasLinks && tok.style.link != "" && !tok.space {
			url := tok.style.link
			if url == "auto" {
				url = tok.text
			}
			lt = &linkTag{msgID: m.MsgID, url: url, kind: tok.style.linkKind}
			linkTags[m.MsgID] = append(linkTags[m.MsgID], lt)
		}
		rects = append(rects, richRect{pos: image.Pt(x, y), size: sz, tok: tok, call: call, lt: lt, art: art})
		x += sz.X
		if x > lineEnd {
			lineEnd = x
		}
	}
	totalH := y + lineH
	if totalH <= 0 {
		totalH = gtx.Dp(unit.Dp(float32(size))) / 1
	}

	for _, r := range rects {
		st := r.tok.style
		// Background pill for code + hidden spoilers.
		if st.mono || (st.spoiler && !revealed) {
			fillCol := a.ui.p.SurfaceHi
			if st.spoiler && !revealed {
				fillCol = a.ui.p.TextFaint
			}
			rrect := clip.RRect{Rect: image.Rect(r.pos.X, r.pos.Y, r.pos.X+r.size.X+2, r.pos.Y+r.size.Y), NE: 4, NW: 4, SE: 4, SW: 4}
			paint.FillShape(gtx.Ops, fillCol, rrect.Op(gtx.Ops))
		}
		stack := op.Offset(r.pos).Push(gtx.Ops)
		var clipStack clip.Stack
		if r.lt != nil {
			clipStack = clip.Rect{Max: r.size}.Push(gtx.Ops)
			event.Op(gtx.Ops, r.lt)
		}
		if r.art != nil {
			// Inline custom-emoji artwork (animated lottie or static
			// raster) in the token box; base glyph stayed the fallback.
			if !drawEmojiArt(gtx, r.art, r.size.X) {
				r.call.Add(gtx.Ops)
			}
		} else {
			r.call.Add(gtx.Ops)
		}
		// Underline / strike lines (approximate baselines).
		if st.underline {
			ly := r.size.Y - gtx.Dp(unit.Dp(2))
			paint.FillShape(gtx.Ops, a.ui.p.Accent, clip.Rect{Min: image.Pt(0, ly), Max: image.Pt(r.size.X, ly+1)}.Op())
		}
		if st.strike {
			ly := r.size.Y * 2 / 5
			paint.FillShape(gtx.Ops, base, clip.Rect{Min: image.Pt(0, ly), Max: image.Pt(r.size.X, ly+1)}.Op())
		}
		if r.lt != nil {
			clipStack.Pop()
		}
		stack.Pop()
	}

	// Tappable links: a press on a token area opens the URL in the
	// platform browser (slice 86); platforms or schemes without an
	// opener fall back to the clipboard copy (slice 34 behavior).
	for _, lt := range linkTags[m.MsgID] {
		for {
			ev, ok := gtx.Source.Event(pointer.Filter{Target: lt, Kinds: pointer.Press})
			if !ok {
				break
			}
			if pe, is := ev.(pointer.Event); is && pe.Kind == pointer.Press && pe.Buttons == pointer.ButtonPrimary {
				if lt.kind == "hashtag" {
					a.openInChatSearchWithQuery(lt.url, chatKey{AccountID: m.AccountID, ChatID: m.ChatID})
				} else if m.AccountID != "" && ivKnownHost(lt.url) {
					// Slice 176: telegra.ph / graph.org links open the
					// in-app Instant View reader.
					a.openInstantView(m.AccountID, lt.url)
				} else {
					a.openLinkExternal(lt.url)
				}
			}
		}
	}

	return layout.Dimensions{Size: image.Pt(lineEnd, totalH)}
}
