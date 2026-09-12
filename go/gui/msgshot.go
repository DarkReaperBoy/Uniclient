package gui

// msgshot.go — slice 151: AyuGram's message shot — render a message
// (forward header, reply quote, photo thumb, entity-styled text,
// timestamp) into a shareable PNG, composed offscreen with the pure-Go
// Go fonts (golang.org/x/image/font/gofont faces + manual rounded-rect
// drawing — no window, no GPU, cross-platform). Saved through the
// explorer's CreateFile save picker.

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"errors"
	"image"
	"image/color"
	"image/draw"
	"image/png"
	"sort"
	"strings"
	"time"
	"unicode/utf16"

	xdraw "golang.org/x/image/draw"
	"golang.org/x/image/font"
	xgofontbold "golang.org/x/image/font/gofont/gobold"
	xgofontbolditalic "golang.org/x/image/font/gofont/gobolditalic"
	xgofontitalic "golang.org/x/image/font/gofont/goitalic"
	xgofontmono "golang.org/x/image/font/gofont/gomono"
	xgofontmonobold "golang.org/x/image/font/gofont/gomonobold"
	xgofontregular "golang.org/x/image/font/gofont/goregular"
	"golang.org/x/image/font/opentype"
	xfont "golang.org/x/image/math/fixed"

	"uniclient/cores"
	"uniclient/engine"
)

// ── pure model ───────────────────────────────────────────────────────────

// shotRun is one styled text run of the message body.
type shotRun struct {
	text               string
	bold, italic       bool
	strike, mono, link bool
	spoiler            bool
	url                string
}

// styled reports whether the run needs a non-default face/color.
func (r shotRun) styled() bool {
	return r.bold || r.italic || r.strike || r.mono || r.link || r.spoiler
}

// shotRunsFromEntities splits the message text into styled runs using
// the entity list (offsets in UTF-16 code units, the Telegram
// convention). Overlapping entities combine flags. Pure — unit-tested.
func shotRunsFromEntities(text string, entities []cores.TextEntity) []shotRun {
	if strings.TrimSpace(text) == "" {
		return nil
	}
	if len(entities) == 0 {
		return []shotRun{{text: text}}
	}
	runes := []rune(text)
	// rune index → utf16 unit offset
	units := make([]int, len(runes)+1)
	for i, r := range runes {
		units[i+1] = units[i] + utf16.RuneLen(r)
	}
	// binary search: first rune index whose unit offset >= u
	runeAtUnit := func(u int) int {
		lo, hi := 0, len(units)
		for lo < hi {
			mid := (lo + hi) / 2
			if units[mid] < u {
				lo = mid + 1
			} else {
				hi = mid
			}
		}
		return lo
	}

	type span struct {
		lo, hi int // rune indexes (inclusive lo, exclusive hi)
		shotRun
	}
	var spans []span
	for _, e := range entities {
		lo := runeAtUnit(e.Offset)
		hi := runeAtUnit(e.Offset + e.Length)
		if hi > len(runes) {
			hi = len(runes)
		}
		if lo >= hi {
			continue
		}
		s := span{lo: lo, hi: hi}
		switch e.Type {
		case "bold":
			s.bold = true
		case "italic":
			s.italic = true
		case "strike":
			s.strike = true
		case "code", "pre":
			s.mono = true
		case "spoiler":
			s.spoiler = true
		case "text_url", "url", "mention", "hashtag", "email", "phone", "bot_command", "cashtag":
			s.link = true
			s.url = e.URL
		default:
			continue // underline/blockquote/custom_emoji render plain (honest scope)
		}
		spans = append(spans, s)
	}
	if len(spans) == 0 {
		return []shotRun{{text: text}}
	}

	// boundary sweep: walk rune positions, recomputing flags from the
	// active span set at every span start/end
	type boundary struct {
		pos  int
		span *span
		add  bool
	}
	var bs []boundary
	for i := range spans {
		bs = append(bs,
			boundary{spans[i].lo, &spans[i], true},
			boundary{spans[i].hi, &spans[i], false})
	}
	sort.SliceStable(bs, func(i, j int) bool {
		if bs[i].pos != bs[j].pos {
			return bs[i].pos < bs[j].pos
		}
		return !bs[i].add // removes before adds at the same position
	})

	var out []shotRun
	active := map[*span]bool{}
	flags := shotRun{}
	start := 0
	flush := func(end int) {
		if end > start {
			r := flags
			r.text = string(runes[start:end])
			out = append(out, r)
		}
	}
	for _, b := range bs {
		if b.pos > start {
			flush(b.pos)
			start = b.pos
		}
		if b.add {
			active[b.span] = true
		} else {
			delete(active, b.span)
		}
		flags = shotRun{}
		for s := range active {
			flags.bold = flags.bold || s.bold
			flags.italic = flags.italic || s.italic
			flags.strike = flags.strike || s.strike
			flags.mono = flags.mono || s.mono
			flags.link = flags.link || s.link
			flags.spoiler = flags.spoiler || s.spoiler
			if s.url != "" {
				flags.url = s.url
			}
		}
	}
	flush(len(runes))
	return out
}

// shotLine is one wrapped display line.
type shotLine struct{ runs []shotRun }

// wrapShotLines greedily wraps runs into lines within maxW pixels
// (measure returns a run-text's width). Unbreakable words longer than
// the budget hard-split by rune. Pure — unit-tested.
func wrapShotLines(runs []shotRun, maxW int, measure func(r shotRun, text string) int) []shotLine {
	if maxW <= 0 {
		return nil
	}
	type word struct {
		run   shotRun
		text  string // the word itself (no spaces)
		space bool   // this token is a run of spaces
	}
	var words []word
	for _, r := range runs {
		rest := r.text
		for rest != "" {
			// leading spaces → one space token
			if rest[0] == ' ' {
				n := 0
				for n < len(rest) && rest[n] == ' ' {
					n++
				}
				words = append(words, word{run: r, text: rest[:n], space: true})
				rest = rest[n:]
				continue
			}
			// the word up to the next space
			w := strings.IndexByte(rest, ' ')
			if w < 0 {
				words = append(words, word{run: r, text: rest})
				rest = ""
			} else {
				words = append(words, word{run: r, text: rest[:w]})
				rest = rest[w:]
			}
		}
	}

	var lines []shotLine
	var cur shotLine
	curW := 0
	push := func(r shotRun) {
		cur.runs = append(cur.runs, r)
	}
	newline := func() {
		if len(cur.runs) > 0 {
			lines = append(lines, cur)
		}
		cur = shotLine{}
		curW = 0
	}
	for _, w := range words {
		w := w
		ww := measure(w.run, w.text)
		// spaces: drop them when they'd start a line; else append
		if w.space {
			if curW > 0 && curW+ww <= maxW {
				push(shotRun{ // spaces keep the style (font metrics equal anyway)
					text: w.text,
				})
				curW += ww
			}
			continue
		}
		if curW+ww <= maxW {
			// fits on the current line
			push(w.run.withText(w.text))
			curW += ww
			continue
		}
		// doesn't fit: break the line, retry
		newline()
		if ww <= maxW {
			push(w.run.withText(w.text))
			curW = ww
			continue
		}
		// hard-split the long word by runes
		remaining := w.text
		for remaining != "" {
			rr := []rune(remaining)
			take := 0
			for take < len(rr) {
				if measure(w.run, string(rr[:take+1])) > maxW {
					break
				}
				take++
			}
			if take == 0 {
				take = 1 // single rune wider than the budget — emit anyway
			}
			piece := string(rr[:take])
			remaining = string(rr[take:])
			newline()
			push(w.run.withText(piece))
			curW = measure(w.run, piece)
		}
	}
	newline()
	return lines
}

// withText clones the run with new text.
func (r shotRun) withText(text string) shotRun {
	r.text = text
	return r
}

// lineText joins a line's runs (for tests + the quote renderer).
func lineText(l shotLine) string {
	var b strings.Builder
	for _, r := range l.runs {
		b.WriteString(r.text)
	}
	return b.String()
}

// ── fonts ────────────────────────────────────────────────────────────────

// shotFace returns a parsed Go-font face for the style (lazily cached;
// nil only on parse failure, which the callers tolerate by skipping).
func shotFace(bold, italic, mono bool) font.Face {
	var key [3]bool
	key[0], key[1], key[2] = bold, italic, mono
	if f, ok := shotFaceCache[key]; ok {
		return f
	}
	var data []byte
	switch {
	case mono && (bold || italic):
		data = xgofontmonobold.TTF
	case mono:
		data = xgofontmono.TTF
	case bold && italic:
		data = xgofontbolditalic.TTF
	case bold:
		data = xgofontbold.TTF
	case italic:
		data = xgofontitalic.TTF
	default:
		data = xgofontregular.TTF
	}
	face, err := parseShotFace(data, 16)
	if err != nil {
		face = nil
	}
	shotFaceCache[key] = face
	return face
}

// shotFaceSmall is the 13px variant for quotes/meta rows.
func shotFaceSmall() font.Face {
	if shotSmallFaceCache != nil {
		return shotSmallFaceCache
	}
	if face, err := parseShotFace(xgofontregular.TTF, 13); err == nil {
		shotSmallFaceCache = face
	}
	return shotSmallFaceCache
}

var (
	shotFaceCache      = map[[3]bool]font.Face{}
	shotSmallFaceCache font.Face
)

func parseShotFace(data []byte, size float64) (font.Face, error) {
	f, err := opentype.Parse(data)
	if err != nil {
		return nil, err
	}
	return opentype.NewFace(f, &opentype.FaceOptions{Size: size, DPI: 72})
}

// shotMeasure measures a run-text with its face (px).
func shotMeasure(r shotRun, text string) int {
	if f := shotFace(r.bold, r.italic, r.mono); f != nil {
		return font.MeasureString(f, text).Ceil()
	}
	return len([]rune(text)) * 8
}

// ── rendering ────────────────────────────────────────────────────────────

// shotPalette carries the render colors (caller passes the live theme).
type shotPalette struct {
	bubble    color.NRGBA
	bubbleOut color.NRGBA
	text      color.NRGBA
	dim       color.NRGBA
	accent    color.NRGBA
}

// shot layout geometry (px).
const (
	shotPad       = 18
	shotMaxWidth  = 440
	shotLineGap   = 4
	shotBodyPx    = 16
	shotQuotePx   = 13
	shotQuoteBarW = 3
	shotThumbMax  = 240
)

// errShotEmpty is the honest no-content refusal (§1.10).
var errShotEmpty = errors.New("message has no renderable content")

// renderMessageShot composes the message into a PNG-ready image.
func renderMessageShot(m engine.CachedMessage, p shotPalette) (image.Image, error) {
	if strings.TrimSpace(m.ContentText) == "" && m.MediaThumbB64 == "" {
		return nil, errShotEmpty
	}
	var entities []cores.TextEntity
	if len(m.ContentRich) > 0 {
		_ = json.Unmarshal(m.ContentRich, &entities)
	}
	runs := shotRunsFromEntities(m.ContentText, entities)
	lines := wrapShotLines(runs, shotMaxWidth-2*shotPad, shotMeasure)

	// photo thumb (decoded, aspect-kept)
	var thumb image.Image
	if m.MediaThumbB64 != "" {
		if raw, err := base64.StdEncoding.DecodeString(m.MediaThumbB64); err == nil {
			thumb, _, _ = image.Decode(bytes.NewReader(raw))
		}
	}

	// vertical budget
	head := 0
	if m.ForwardFrom != "" {
		head += 20
	}
	quoteLines := wrapShotLines([]shotRun{{text: m.ReplyPreview}},
		shotMaxWidth-2*shotPad-12, shotDimMeasure)
	if m.ReplyPreview != "" {
		head += len(quoteLines)*(shotQuotePx+2) + 10
	}
	senderH := 0
	if m.SenderName != "" && !m.IsOutgoing {
		senderH = 21
		head += senderH
	}
	thumbW, thumbH := 0, 0
	if thumb != nil {
		b := thumb.Bounds()
		w := shotMaxWidth - 2*shotPad
		thumbW = w
		thumbH = b.Dy() * w / max(b.Dx(), 1)
		if thumbH > shotThumbMax {
			thumbH = shotThumbMax
			thumbW = b.Dx() * shotThumbMax / max(b.Dy(), 1)
		}
		head += thumbH + 8
	}
	bodyH := 0
	if len(lines) > 0 {
		bodyH = len(lines)*(shotBodyPx+shotLineGap) + shotPad
	}

	W := shotMaxWidth
	H := shotPad + head + bodyH + 16 + shotPad
	img := image.NewRGBA(image.Rect(0, 0, W, H))

	bubble := p.bubble
	if m.IsOutgoing {
		bubble = p.bubbleOut
	}
	drawRoundedRect(img, img.Bounds(), bubble, 14)

	y := shotPad
	if m.ForwardFrom != "" {
		drawShotText(img, shotPad, y+14, "Forwarded from "+m.ForwardFrom, p.dim, false, false, false, 16)
		y += 20
	}
	if m.ReplyPreview != "" {
		drawRoundedRect(img, image.Rect(shotPad, y+2, shotPad+shotQuoteBarW, y+len(quoteLines)*(shotQuotePx+2)+8), p.accent, 2)
		for _, ln := range quoteLines {
			drawShotText(img, shotPad+10, y+shotQuotePx, lineText(ln), p.dim, false, false, false, shotQuotePx)
			y += shotQuotePx + 2
		}
		y += 10
	}
	if senderH > 0 {
		drawShotText(img, shotPad, y+shotBodyPx, m.SenderName, senderColorFor(m.SenderColorID, m.SenderID), true, false, false, shotBodyPx)
		y += senderH
	}
	if thumb != nil {
		dst := image.Rect(shotPad, y, shotPad+thumbW, y+thumbH)
		xdraw.CatmullRom.Scale(img, dst, thumb, thumb.Bounds(), xdraw.Over, nil)
		y += thumbH + 8
	}
	for _, ln := range lines {
		x := shotPad
		for _, r := range ln.runs {
			f := shotFace(r.bold, r.italic, r.mono)
			if f == nil {
				continue
			}
			col := p.text
			if r.link {
				col = p.accent
			}
			d := &font.Drawer{Dst: img, Src: image.NewUniform(col), Face: f, Dot: xfont.P(x, y+shotBodyPx)}
			d.DrawString(r.text)
			w := font.MeasureString(f, r.text).Ceil()
			if r.strike {
				drawHLine(img, x, y+shotBodyPx-5, w, p.text)
			}
			if r.link {
				drawHLine(img, x, y+shotBodyPx+2, w, p.accent)
			}
			if r.spoiler {
				// conceal like tdesktop's static spoiler: cover the text
				drawRoundedRect(img, image.Rect(x, y+2, x+w, y+shotBodyPx+3), bubble, 2)
			}
			x += w
		}
		y += shotBodyPx + shotLineGap
	}
	// timestamp (bottom-right)
	ts := time.Unix(m.Timestamp, 0).Format("15:04")
	if m.EditedAt > 0 {
		ts = "edited " + ts
	}
	if f := shotFaceSmall(); f != nil {
		w := font.MeasureString(f, ts).Ceil()
		d := &font.Drawer{Dst: img, Src: image.NewUniform(p.dim), Face: f, Dot: xfont.P(W-shotPad-w, H-shotPad-2)}
		d.DrawString(ts)
	}
	return img, nil
}

// shotDimMeasure measures with the small quote face.
func shotDimMeasure(r shotRun, text string) int {
	if f := shotFaceSmall(); f != nil {
		return font.MeasureString(f, text).Ceil()
	}
	return len([]rune(text)) * 7
}

// drawShotText draws one text line at baseline y with a sized face.
func drawShotText(img *image.RGBA, x, y int, text string, col color.NRGBA, bold, italic, mono bool, size int) {
	var f font.Face
	if size == shotQuotePx {
		f = shotFaceSmall()
	} else {
		f = shotFace(bold, italic, mono)
	}
	if f == nil {
		return
	}
	d := &font.Drawer{Dst: img, Src: image.NewUniform(col), Face: f, Dot: xfont.P(x, y)}
	d.DrawString(text)
}

// drawRoundedRect fills r (rounded by rad) with col — scanline fill with
// per-pixel corner mask.
func drawRoundedRect(img *image.RGBA, r image.Rectangle, col color.NRGBA, rad int) {
	if rad <= 0 || r.Dx() < 2*rad || r.Dy() < 2*rad {
		draw.Draw(img, r, image.NewUniform(col), image.Point{}, draw.Src)
		return
	}
	cx0, cy0, cx1, cy1 := r.Min.X+rad, r.Min.Y+rad, r.Max.X-rad, r.Max.Y-rad
	radSq := rad * rad
	for y := r.Min.Y; y < r.Max.Y; y++ {
		for x := r.Min.X; x < r.Max.X; x++ {
			inside := true
			switch {
			case x < cx0 && y < cy0:
				inside = (cx0-x)*(cx0-x)+(cy0-y)*(cy0-y) <= radSq
			case x >= cx1 && y < cy0:
				inside = (x-cx1+1)*(x-cx1+1)+(cy0-y)*(cy0-y) <= radSq
			case x < cx0 && y >= cy1:
				inside = (cx0-x)*(cx0-x)+(y-cy1+1)*(y-cy1+1) <= radSq
			case x >= cx1 && y >= cy1:
				inside = (x-cx1+1)*(x-cx1+1)+(y-cy1+1)*(y-cy1+1) <= radSq
			}
			if inside {
				img.Set(x, y, col)
			}
		}
	}
}

// drawHLine draws a 1px horizontal line.
func drawHLine(img *image.RGBA, x, y, w int, col color.NRGBA) {
	for i := 0; i < w; i++ {
		if px := x + i; px >= 0 && px < img.Bounds().Dx() {
			img.Set(px, y, col)
		}
	}
}

// shotFilename builds the default save name from the chat title.
func shotFilename(title string) string {
	var b strings.Builder
	b.WriteString("shot-")
	for _, r := range strings.TrimSpace(title) {
		switch {
		case r >= 'a' && r <= 'z', r >= 'A' && r <= 'Z', r >= '0' && r <= '9', r == '-', r == '_':
			b.WriteRune(r)
		case r == ' ':
			b.WriteRune('-')
		}
		if b.Len() >= 40 {
			break
		}
	}
	name := b.String()
	if name == "shot-" {
		return "shot-message-" + time.Now().Format("20060102-150405") + ".png"
	}
	return name + ".png"
}

// shotPNGBytes encodes the image.
func shotPNGBytes(img image.Image) ([]byte, error) {
	var buf bytes.Buffer
	if err := png.Encode(&buf, img); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

// ── save flow ────────────────────────────────────────────────────────────

// saveMessageShot renders + saves the shot via the explorer save picker
// (CreateFile). Rendering happens off the UI goroutine; the explorer
// call rides the same pattern as the attach picker.
func (a *App) saveMessageShot(m engine.CachedMessage) {
	msg := m
	go func() {
		p := shotPalette{
			bubble:    a.ui.p.BubbleIn,
			bubbleOut: a.ui.p.AccentDim,
			text:      a.ui.p.Text,
			dim:       a.ui.p.TextDim,
			accent:    a.ui.p.Accent,
		}
		title := ""
		a.mu.Lock()
		for i := range a.chats {
			if a.chats[i].AccountID == msg.AccountID && a.chats[i].ChatID == msg.ChatID {
				title = a.chats[i].Title
				break
			}
		}
		a.mu.Unlock()
		img, err := renderMessageShot(msg, p)
		if err != nil {
			a.setToast("Message shot: " + err.Error())
			return
		}
		raw, err := shotPNGBytes(img)
		if err != nil {
			a.setToast("Message shot encode: " + err.Error())
			return
		}
		if a.expl == nil {
			a.setToast("Message shot: file picker unavailable")
			return
		}
		wc, err := a.expl.CreateFile(shotFilename(title))
		if err != nil {
			if err.Error() == "user declined" || strings.Contains(strings.ToLower(err.Error()), "declin") {
				return // silent on cancel — the picker's own honesty
			}
			a.setToast("Message shot: " + err.Error())
			return
		}
		if _, err := wc.Write(raw); err != nil {
			wc.Close()
			a.setToast("Message shot write: " + err.Error())
			return
		}
		if err := wc.Close(); err != nil {
			a.setToast("Message shot close: " + err.Error())
			return
		}
		a.setToast("Message shot saved")
	}()
}
