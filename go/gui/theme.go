package gui

import (
	"hash/fnv"
	"image"
	"image/color"
	"runtime"
	"strings"
	"sync/atomic"
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

type palette struct {
	Background   color.NRGBA
	Surface      color.NRGBA
	SurfaceHi    color.NRGBA
	BubbleIn     color.NRGBA
	BubbleOut    color.NRGBA
	BubbleOutDim color.NRGBA
	Accent       color.NRGBA
	AccentDim    color.NRGBA
	Text         color.NRGBA
	TextDim      color.NRGBA
	TextFaint    color.NRGBA
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
	BubbleIn:     rgb(0x2B5278),
	BubbleOut:    rgb(0x2B5278),
	BubbleOutDim: rgb(0x22405C),
	Accent:       rgb(0x64B5F6),
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

func (u *UI) applyTheme(name string) {
	if name == "light" {
		u.p = light
	} else {
		u.p = dark
	}
	if u.accentHex != "" {
		u.applyAccent(u.accentHex)
	}
}

func bubbleRadiusFor(round bool) int {
	if round {
		return 12
	}
	return 2
}

func (u *UI) applyBubbleCorners(round bool) {
	u.bubbleCornersOn = round
}

func (u *UI) bubbleRadius() int {
	return u.bubbleRadiusDp
}

func (u *UI) applyLayoutTweaks(radiusDp int, wideMult float64) {
	u.bubbleRadiusDp = utils.ClampBubbleRadius(radiusDp)
	u.wideMult = utils.ClampWideMultiplier(wideMult)
}

func (u *UI) wideMultiplier() float64 {
	if u.wideMult <= 0 {
		return 0.75
	}
	return u.wideMult
}

func (u *UI) applyAvatarCorners(corners int) {
	if corners < 0 {
		corners = 0
	}
	if corners > 23 {
		corners = 23
	}
	u.avatarCorners.Store(int32(corners))
}

func (u *UI) avatarRadiusPx(sizePx int) int {
	return avatarCornerRadiusPx(int(u.avatarCorners.Load()), sizePx)
}

func clampFontScale(v float64) float64 {
	if v < 0.8 {
		return 0.8
	}
	if v > 1.4 {
		return 1.4
	}
	return v
}

func (u *UI) applyFontScale(v float64) {
	u.fontScale = clampFontScale(v)
}

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
	return color.NRGBA{A: 0xFF, R: uint8(c >> 16), G: uint8(c >> 8), B: uint8(c)}
}

type UI struct {
	*material.Theme
	p               palette
	fontScale       float64
	accentHex       string
	bubbleCornersOn bool
	bubbleRadiusDp  int
	wideMult        float64
	avatarCorners   atomic.Int32
}

//go:embed assets/notoemoji.ttf
var notoEmoji []byte

func NewUI() *UI {
	th := material.NewTheme()
	th.Shaper = text.NewShaper(text.WithCollection(baseFontCollection()))
	th.TextSize = unit.Sp(15)
	u := &UI{Theme: th, p: dark}
	u.avatarCorners.Store(23)
	return u
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

func (u *UI) H1(txt string) material.LabelStyle { return u.Label(unit.Sp(28), txt) }
func (u *UI) H2(txt string) material.LabelStyle { return u.Label(unit.Sp(20), txt) }
func (u *UI) H3(txt string) material.LabelStyle { return u.Label(unit.Sp(17), txt) }

func (u *UI) PrimaryButton(btn *widget.Clickable, txt string) material.ButtonStyle {
	b := material.Button(u.Theme, btn, txt)
	b.Background = u.p.Accent
	b.Color = rgb(0x0D1821)
	b.CornerRadius = 8
	b.TextSize = unit.Sp(15)
	return b
}

func (u *UI) TextButton(btn *widget.Clickable, txt string) material.ButtonStyle {
	b := material.Button(u.Theme, btn, txt)
	b.Background = color.NRGBA{}
	b.Color = u.p.Accent
	b.CornerRadius = 8
	return b
}

func (u *UI) SurfaceButton(btn *widget.Clickable, txt string) material.ButtonStyle {
	b := material.Button(u.Theme, btn, txt)
	b.Background = u.p.SurfaceHi
	b.Color = u.p.Text
	b.CornerRadius = 10
	return b
}

func (u *UI) IconButton(btn *widget.Clickable, icon *widget.Icon, desc string) material.IconButtonStyle {
	b := material.IconButton(u.Theme, btn, icon, desc)
	b.Background = color.NRGBA{}
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

func (u *UI) Divider(gtx layout.Context) layout.Dimensions {
	return drawRect(gtx, u.p.Divider, gtx.Dp(unit.Dp(1)))
}

func drawRect(gtx layout.Context, c color.NRGBA, h int) layout.Dimensions {
	w := gtx.Constraints.Max.X
	defer clip.Rect{Min: image.Pt(0, 0), Max: image.Pt(w, h)}.Push(gtx.Ops).Pop()
	paint.Fill(gtx.Ops, c)
	return layout.Dimensions{Size: image.Pt(w, h)}
}

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

func (u *UI) Avatar(gtx layout.Context, name string, sizeDp unit.Dp, online connDot) layout.Dimensions {
	return u.AvatarShaped(gtx, name, sizeDp, online, u.avatarRadiusPx(gtx.Dp(sizeDp)))
}

func (u *UI) AvatarShaped(gtx layout.Context, name string, sizeDp unit.Dp, online connDot, radiusPx int) layout.Dimensions {
	size := gtx.Dp(sizeDp)
	bg := avatarColor(name)

	paint.FillShape(gtx.Ops, bg, avatarShapeClip(gtx.Ops, size, radiusPx))

	macro := op.Record(gtx.Ops)
	lgtx := gtx
	lgtx.Constraints = layout.Constraints{Max: image.Pt(size, size)}
	lbl := u.Label(unit.Sp(float32(sizeDp)*0.36), initials(name))
	lbl.Color = rgb(0xFFFFFF)
	dims := lbl.Layout(lgtx)
	call := macro.Stop()
	stack := op.Offset(image.Pt((size-dims.Size.X)/2, (size-dims.Size.Y)/2)).Push(gtx.Ops)
	call.Add(gtx.Ops)
	stack.Pop()

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

type platformMeta struct {
	ID, Title, Desc, Letter string
	Status                  string
}

var platforms = []platformMeta{
	{ID: "telegram", Title: "Telegram", Desc: "MTProto via gotd. Calls, folders, full parity work.", Letter: "T"},
	{ID: "irc", Title: "IRC", Desc: "IRCv3, SASL, verified against real servers.", Letter: "I"},
	{ID: "matrix", Title: "Matrix", Desc: "mautrix, E2EE via goolm (pure Go).", Letter: "M"},
	{ID: "github", Title: "GitHub", Desc: "Issues, PRs, notifications as chats.", Letter: "G"},
	{ID: "xmpp", Title: "XMPP", Desc: "Own XMPP client (SASL, IBR, jingle calls).", Letter: "X"},
	{ID: "mumble", Title: "Mumble", Desc: "VoIP: channels, text chat, OCB2 voice crypto. Live-verified.", Letter: "U"},
	{ID: "teamspeak", Title: "TeamSpeak 3", Desc: "TS3 client protocol: EAX-encrypted commands, voice. Live-verified.", Letter: "S"},
	{ID: "deltachat", Title: "Delta Chat", Desc: "Email-based chat (IMAP/SMTP).", Letter: "Δ"},
	{ID: "bale", Title: "Bale", Desc: "Iranian messenger (experimental).", Letter: "B"},
}

var webConnectable = map[string]bool{
	"github": true,
	"matrix": true,
	"bale":   true,
}

func pickerPlatformsFor(goos string) []platformMeta {
	if goos != "js" {
		return platforms
	}
	out := make([]platformMeta, 0, len(platforms))
	for _, p := range platforms {
		if webConnectable[p.ID] {
			out = append(out, p)
		}
	}
	return out
}

func pickerPlatforms() []platformMeta {
	return pickerPlatformsFor(runtime.GOOS)
}

func platformTitle(id string) string {
	for _, p := range platforms {
		if p.ID == id {
			return p.Title
		}
	}
	return id
}

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

func fmtTime(ms int64) string {
	if ms == 0 {
		return ""
	}
	return time.UnixMilli(ms).Format("15:04")
}

type chatKey struct {
	AccountID string
	ChatID    string
}

func (k chatKey) String() string { return k.AccountID + "/" + k.ChatID }
