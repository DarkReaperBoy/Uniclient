// Package gui is the Uniclient native UI: a Material-Design,
// AyuGram-inspired chat client built on Gio. It talks to the engine
// in-process (no bridge, no serialization) and renders chat + voice modes,
// chat folders, adaptive layout, and per-backend login flows.
package gui

import (
	"hash/fnv"
	"image"
	"image/color"
	"strings"
	"time"

	_ "embed"

	"gioui.org/layout"
	"gioui.org/op"
	"gioui.org/op/clip"
	"gioui.org/op/paint"
	"gioui.org/text"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/engine"
	"uniclient/utils"
)

// AyuGram-ish dark palette (Telegram dark + accent).
type palette struct {
	Background   color.NRGBA // app background
	Surface      color.NRGBA // cards, sidebar
	SurfaceHi    color.NRGBA // hover / active surface
	BubbleIn     color.NRGBA // incoming message bubble
	BubbleOut    color.NRGBA // outgoing message bubble
	BubbleOutDim color.NRGBA // outgoing bubble (dimmer variant)
	Accent       color.NRGBA // primary accent (links, send, tabs)
	AccentDim    color.NRGBA
	Text         color.NRGBA
	TextDim      color.NRGBA // secondary text
	TextFaint    color.NRGBA // hints, timestamps
	Online       color.NRGBA
	Connecting   color.NRGBA
	Error        color.NRGBA
	UnreadBadge  color.NRGBA
	Divider      color.NRGBA
}

var dark = palette{
	Background:   rgb(0x17212B),
	Surface:      rgb(0x1C2733),
	SurfaceHi:    rgb(0x232E3C),
	BubbleIn:     rgb(0x2B5278), // telegram inbound
	BubbleOut:    rgb(0x2B5278),
	BubbleOutDim: rgb(0x22405C),
	Accent:       rgb(0x64B5F6), // material blue 300
	AccentDim:    rgb(0x3E6F9E),
	Text:         rgb(0xE9EDF0),
	TextDim:      rgb(0x9AA6B1),
	TextFaint:    rgb(0x6E7B87),
	Online:       rgb(0x4CAF50),
	Connecting:   rgb(0xFFC107),
	Error:        rgb(0xEF5350),
	UnreadBadge:  rgb(0x64B5F6),
	Divider:      rgb(0x273241),
}

// light is the Telegram-light-flavored palette (settings → Appearance).
var light = palette{
	Background:   rgb(0xF2F4F7),
	Surface:      rgb(0xFFFFFF),
	SurfaceHi:    rgb(0xE9EDF2),
	BubbleIn:     rgb(0xE3EFFA),
	BubbleOut:    rgb(0xB9E2A0),
	BubbleOutDim: rgb(0xCDEBC0),
	Accent:       rgb(0x2E7CD6),
	AccentDim:    rgb(0xA7C9EC),
	Text:         rgb(0x1A2B3C),
	TextDim:      rgb(0x5B6B7A),
	TextFaint:    rgb(0x93A2B0),
	Online:       rgb(0x31A34A),
	Connecting:   rgb(0xE6A700),
	Error:        rgb(0xC43C3C),
	UnreadBadge:  rgb(0x2E7CD6),
	Divider:      rgb(0xE3E7EB),
}

// applyTheme swaps the active palette (config Theme: "dark" | "light").
// Called from the frame loop (button clicks) and once at boot before the
// first frame — both on the GUI thread, so no locking needed.
func (u *UI) applyTheme(name string) {
	if name == "light" {
		u.p = light
	} else {
		u.p = dark
	}
	// The theme switch overwrote the palette; re-tint with the stored accent.
	if u.accentHex != "" {
		u.applyAccent(u.accentHex)
	}
}

// bubbleRadiusFor maps the corners toggle to the bubble corner radius in
// dp (AyuGram "Corners": rounded vs square). Pure.
func bubbleRadiusFor(round bool) int {
	if round {
		return 12
	}
	return 2
}

// applyBubbleCorners sets the corner style (AyuGram appearance, slice 82).
func (u *UI) applyBubbleCorners(round bool) {
	u.bubbleCornersOn = round
}

// bubbleRadius is the active message-bubble corner radius in dp.
func (u *UI) bubbleRadius() int {
	return u.bubbleRadiusDp
}

// applyLayoutTweaks sets the slice-93 slider values (already clamped by
// the engine helpers at the config boundary).
func (u *UI) applyLayoutTweaks(radiusDp int, wideMult float64) {
	u.bubbleRadiusDp = utils.ClampBubbleRadius(radiusDp)
	u.wideMult = utils.ClampWideMultiplier(wideMult)
}

// wideMultiplier is the active bubble max-width factor (0.70..1.00).
func (u *UI) wideMultiplier() float64 {
	if u.wideMult <= 0 {
		return 0.75
	}
	return u.wideMult
}

// clampFontScale bounds the text scale to a sane, still-usable range.
func clampFontScale(v float64) float64 {
	if v < 0.8 {
		return 0.8
	}
	if v > 1.4 {
		return 1.4
	}
	return v
}

// applyFontScale sets the global text scale (1 = default).
func (u *UI) applyFontScale(v float64) {
	u.fontScale = clampFontScale(v)
}

// parseAccentHex decodes #RRGGBB into a color (A=255). False on malformed
// input. Pure — unit-tested.
func parseAccentHex(hex string) (color.NRGBA, bool) {
	hex = strings.TrimSpace(hex)
	if len(hex) != 7 || hex[0] != '#' {
		return color.NRGBA{}, false
	}
	var v [3]byte
	for i := 0; i < 3; i++ {
		hi, ok1 := hexDigit(hex[1+i*2])
		lo, ok2 := hexDigit(hex[2+i*2])
		if !ok1 || !ok2 {
			return color.NRGBA{}, false
		}
		v[i] = hi<<4 | lo
	}
	return color.NRGBA{A: 0xFF, R: v[0], G: v[1], B: v[2]}, true
}

func hexDigit(c byte) (byte, bool) {
	switch {
	case c >= '0' && c <= '9':
		return c - '0', true
	case c >= 'a' && c <= 'f':
		return c - 'a' + 10, true
	case c >= 'A' && c <= 'F':
		return c - 'A' + 10, true
	}
	return 0, false
}

// mixNRGBA linearly blends two colors (t=0 → a, t=1 → b).
func mixNRGBA(a, b color.NRGBA, t float32) color.NRGBA {
	f := func(x, y uint8) uint8 {
		v := float32(x)*(1-t) + float32(y)*t
		if v < 0 {
			v = 0
		}
		if v > 255 {
			v = 255
		}
		return uint8(v + 0.5)
	}
	return color.NRGBA{A: 0xFF, R: f(a.R, b.R), G: f(a.G, b.G), B: f(a.B, b.B)}
}

// applyAccent re-tints the palette's accent pair from #RRGGBB (the dim
// variant blends toward the theme background). No-op on malformed hex.
func (u *UI) applyAccent(hex string) {
	c, ok := parseAccentHex(hex)
	if !ok {
		return
	}
	u.p.Accent = c
	u.p.AccentDim = mixNRGBA(c, u.p.Background, 0.45)
	u.accentHex = hex
}

func rgb(c uint32) color.NRGBA {
	// NOTE: alpha is mandatory — NRGBA with A=0 is fully transparent.
	return color.NRGBA{A: 0xFF, R: uint8(c >> 16), G: uint8(c >> 8), B: uint8(c)}
}

// UI wraps the material theme with our palette and helpers.
type UI struct {
	*material.Theme
	p         palette
	fontScale float64 // global text scale (AyuGram appearance, slice 59)
	accentHex string  // applied accent (survives theme switches)
	// Round bubble corners (AyuGram appearance "Corners", slice 82):
	// true = 12dp rounded, false = 2dp near-square. Superseded by the
	// slice-93 radius slider (bubbleRadiusDp) but kept for legacy configs.
	bubbleCornersOn bool
	// Layout tweak sliders (AyuGram appearance, slice 93):
	// bubble radius in dp (0..18) and the bubble max-width factor of the
	// chat pane (0.70..1.00).
	bubbleRadiusDp int
	wideMult       float64
}

// notoEmoji is the monochrome Noto Emoji face (SIL OFL 1.1, see assets/OFL.txt).
// Registered as a shaper fallback so emoji in messages and reaction strips
// render instead of tofu (AyuGram parity: emoji everywhere).
//
//go:embed assets/notoemoji.ttf
var notoEmoji []byte

func NewUI() *UI {
	th := material.NewTheme()
	// gio v0.10.2 leaves the shaper empty — register the Go font collection
	// (embedded, works on every platform incl. Windows/WASM) and allow system
	// fonts as additional fallbacks.
	th.Shaper = text.NewShaper(text.WithCollection(baseFontCollection()))
	th.TextSize = unit.Sp(15)
	return &UI{Theme: th, p: dark}
}

func (u *UI) Label(size unit.Sp, txt string) material.LabelStyle {
	if u.fontScale != 0 && u.fontScale != 1 {
		size = unit.Sp(float32(size) * float32(u.fontScale))
	}
	l := material.Label(u.Theme, size, txt)
	l.Color = u.p.Text
	return l
}

func (u *UI) Dim(size unit.Sp, txt string) material.LabelStyle {
	l := u.Label(size, txt)
	l.Color = u.p.TextDim
	return l
}

// H1/H2/H3 headers.
func (u *UI) H1(txt string) material.LabelStyle { return u.Label(unit.Sp(28), txt) }
func (u *UI) H2(txt string) material.LabelStyle { return u.Label(unit.Sp(20), txt) }
func (u *UI) H3(txt string) material.LabelStyle { return u.Label(unit.Sp(17), txt) }

// Primary button (accent).
func (u *UI) PrimaryButton(btn *widget.Clickable, txt string) material.ButtonStyle {
	b := material.Button(u.Theme, btn, txt)
	b.Background = u.p.Accent
	b.Color = rgb(0x0D1821)
	b.CornerRadius = 8
	b.TextSize = unit.Sp(15)
	return b
}

// Flat text button.
func (u *UI) TextButton(btn *widget.Clickable, txt string) material.ButtonStyle {
	b := material.Button(u.Theme, btn, txt)
	b.Background = color.NRGBA{}
	b.Color = u.p.Accent
	b.CornerRadius = 8
	return b
}

// Filled surface button (e.g. backend cards).
func (u *UI) SurfaceButton(btn *widget.Clickable, txt string) material.ButtonStyle {
	b := material.Button(u.Theme, btn, txt)
	b.Background = u.p.SurfaceHi
	b.Color = u.p.Text
	b.CornerRadius = 10
	return b
}

func (u *UI) IconButton(btn *widget.Clickable, icon *widget.Icon, desc string) material.IconButtonStyle {
	b := material.IconButton(u.Theme, btn, icon, desc)
	b.Background = color.NRGBA{} // transparent
	b.Color = u.p.TextDim
	b.Size = unit.Dp(24)
	return b
}

func (u *UI) Editor(ed *widget.Editor, hint string) material.EditorStyle {
	e := material.Editor(u.Theme, ed, hint)
	e.Color = u.p.Text
	e.HintColor = u.p.TextFaint
	e.TextSize = unit.Sp(15)
	return e
}

// Divider draws a 1dp horizontal line.
func (u *UI) Divider(gtx layout.Context) layout.Dimensions {
	return drawRect(gtx, u.p.Divider, gtx.Dp(unit.Dp(1)))
}

func drawRect(gtx layout.Context, c color.NRGBA, h int) layout.Dimensions {
	w := gtx.Constraints.Max.X
	defer clip.Rect{Min: image.Pt(0, 0), Max: image.Pt(w, h)}.Push(gtx.Ops).Pop()
	paint.Fill(gtx.Ops, c)
	return layout.Dimensions{Size: image.Pt(w, h)}
}

// avatarColors returns a stable background color for a name.
func avatarColor(name string) color.NRGBA {
	h := fnv.New32a()
	h.Write([]byte(name))
	n := h.Sum32() % 8
	cs := []color.NRGBA{
		rgb(0xE17076), rgb(0x6BC1B4), rgb(0x74B9FF), rgb(0xA29BFE),
		rgb(0xFDCB6E), rgb(0xE84393), rgb(0x00B894), rgb(0x8C7AE6),
	}
	return cs[n]
}

// initials derives a 1-2 letter avatar from a title.
func initials(title string) string {
	title = strings.TrimSpace(title)
	if title == "" {
		return "?"
	}
	words := strings.Fields(title)
	if len(words) == 1 {
		r := []rune(words[0])
		n := 2
		if len(r) < n {
			n = len(r)
		}
		return strings.ToUpper(string(r[:n]))
	}
	return strings.ToUpper(string([]rune{[]rune(words[0])[0], []rune(words[1])[0]}))
}

// Avatar renders a colored circle with initials, or a colored status dot.
func (u *UI) Avatar(gtx layout.Context, name string, sizeDp unit.Dp, online connDot) layout.Dimensions {
	size := gtx.Dp(sizeDp)
	bg := avatarColor(name)

	// Circle + initials.
	macro := op.Record(gtx.Ops)
	lbl := u.Label(unit.Sp(float32(sizeDp)*0.36), initials(name))
	lbl.Color = rgb(0xFFFFFF)
	dims := lbl.Layout(gtx)
	call := macro.Stop()
	stack := op.Offset(image.Pt((size-dims.Size.X)/2, (size-dims.Size.Y)/2)).Push(gtx.Ops)
	call.Add(gtx.Ops)
	stack.Pop()

	defer clip.Ellipse{Min: image.Pt(0, 0), Max: image.Pt(size, size)}.Push(gtx.Ops).Pop()
	paint.Fill(gtx.Ops, bg)

	if online != dotNone {
		d := size / 5
		cx, cy := size-d, size-d
		paint.FillShape(gtx.Ops, dark.Background,
			clip.Ellipse{Min: image.Pt(cx-d/6, cy-d/6), Max: image.Pt(cx+d+d/6, cy+d+d/6)}.Op(gtx.Ops))
		paint.FillShape(gtx.Ops, online.color(),
			clip.Ellipse{Min: image.Pt(cx, cy), Max: image.Pt(cx+d, cy+d)}.Op(gtx.Ops))
	}
	return layout.Dimensions{Size: image.Pt(size, size)}
}

// connDot is the per-account connection indicator.
type connDot int

const (
	dotNone connDot = iota
	dotOffline
	dotConnecting
	dotOnline
	dotError
)

func (c connDot) color() color.NRGBA {
	switch c {
	case dotOnline:
		return dark.Online
	case dotConnecting:
		return dark.Connecting
	case dotError:
		return dark.Error
	default:
		return dark.TextFaint
	}
}

func connDotFor(a engine.AccountInfo) connDot {
	switch a.ConnState {
	case int(engine.ConnConnected):
		return dotOnline
	case int(engine.ConnConnecting):
		return dotConnecting
	default:
		if a.DisplayName == "" && a.Username == "" {
			return dotOffline
		}
		return dotOffline
	}
}

// platformMeta describes backends shown in the GUI.
type platformMeta struct {
	ID, Title, Desc, Letter string
	Status                  string // "", "experimental", "hidden"
}

// platforms is the picker list (order = display order). Every entry must
// be a real, factory-supported backend (tested in theme_test.go against
// bootstrap.SupportedPlatforms). Mumble and TeamSpeak are live-verified
// against public servers (2026-09-10, research/mumble_protocol.md +
// research/teamspeak_protocol.md). No fake/demo entries — AGENTS.md §1.10.
var platforms = []platformMeta{
	{ID: "telegram", Title: "Telegram", Desc: "MTProto via gotd. Calls, folders, full parity work.", Letter: "T"},
	{ID: "irc", Title: "IRC", Desc: "IRCv3, SASL, verified against real servers.", Letter: "I"},
	{ID: "matrix", Title: "Matrix", Desc: "mautrix, E2EE via goolm (pure Go).", Letter: "M"},
	{ID: "github", Title: "GitHub", Desc: "Issues, PRs, notifications as chats.", Letter: "G"},
	{ID: "xmpp", Title: "XMPP", Desc: "mellium-based core.", Letter: "X"},
	{ID: "mumble", Title: "Mumble", Desc: "VoIP: channels, text chat, OCB2 voice crypto. Live-verified.", Letter: "U"},
	{ID: "teamspeak", Title: "TeamSpeak 3", Desc: "TS3 client protocol: EAX-encrypted commands, voice. Live-verified.", Letter: "S"},
	{ID: "deltachat", Title: "Delta Chat", Desc: "Email-based chat (IMAP/SMTP).", Letter: "Δ"},
	{ID: "bale", Title: "Bale", Desc: "Iranian messenger (experimental).", Letter: "B"},
	{ID: "rubika", Title: "Rubika", Desc: "Iranian messenger (experimental).", Letter: "R"},
}

func platformTitle(id string) string {
	for _, p := range platforms {
		if p.ID == id {
			return p.Title
		}
	}
	return id
}

// chatKind classifies a ChatInfo for folders.
func chatKind(c engine.ChatInfo) string {
	switch c.Type {
	case engine.ChatTypeDMVal:
		return "people"
	case engine.ChatTypeGroupVal, engine.ChatTypeTopicVal:
		return "groups"
	case engine.ChatTypeChanVal:
		return "channels"
	}
	return "people"
}

// fmtTime renders a message timestamp (HH:MM or date).
func fmtTime(ms int64) string {
	if ms == 0 {
		return ""
	}
	return time.UnixMilli(ms).Format("15:04")
}

// chatKey identifies an open chat.
type chatKey struct {
	AccountID string
	ChatID    string
}

func (k chatKey) String() string { return k.AccountID + "/" + k.ChatID }

// draftText returns the draft text for a chat (per-open-session).
func draftText(c engine.ChatInfo) string {
	return c.DraftText
}
