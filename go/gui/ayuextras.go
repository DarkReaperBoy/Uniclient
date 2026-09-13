package gui

import (
	"image"
	"image/color"
	"sync"
	"sync/atomic"
	"time"
	"unicode"

	"gioui.org/layout"
	"gioui.org/op/clip"
	"gioui.org/op/paint"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/engine"
)

// Ayu behavior extras (slice 173, primary source ayu_settings.h +
// settings_general.cpp + ayu_helpers.cpp):
//   - showMessageSeconds — message timestamps render HH:MM:SS
//     (formatMessageTime semantics; chat-list rows stay minute-level).
//   - filterZalgo — strip zalgo runs (3+ combining marks keep the first
//     two) and bidi override controls from rendered message text and
//     sender names (kZalgoPattern 1:1). Render-time only: cached data is
//     never modified.
//   - showChannel/Group/PrivateReactions — per-chat-type reaction-strip
//     visibility (default OFF in our config = AyuGram toggle ON flips
//     them; the AyuGram defaults are true, so our nil = false means the
//     strips need the toggle or the config default flips to true).
//   - sticker/gif/voice Confirmation — a confirm card before the send
//     fires. Round-video notes have no send path in UniClient yet, so
//     that toggle stays unshipped (§1.10: no dead UI).

// ayuOn resolves an Ayu extra toggle (all default OFF — AyuGram ships
// these as opt-in).
func ayuOn(v *bool) bool { return v != nil && *v }

// ── message seconds ──────────────────────────────────────────────────────

// msgShowSeconds is the process-wide effective toggle (set from the config
// snapshot; fmtTime call sites for messages read it via msgTimeLabel).
var msgShowSeconds atomic.Bool

func setMsgShowSeconds(on bool) { msgShowSeconds.Store(on) }

// msgTimeLabel renders a MESSAGE timestamp: HH:MM, or HH:MM:SS when the
// Ayu showMessageSeconds toggle is on (AyuGram formatMessageTime).
// Chat-list rows and day dividers keep fmtTime (AyuGram separates the
// two formatters the same way).
func msgTimeLabel(ms int64) string {
	if ms == 0 {
		return ""
	}
	if msgShowSeconds.Load() {
		return time.UnixMilli(ms).Format("15:04:05")
	}
	return time.UnixMilli(ms).Format("15:04")
}

// ── zalgo / bidi filtering ───────────────────────────────────────────────

// isBidiControl matches the second branch of AyuGram's kZalgoPattern:
// directional embeddings/overrides and isolate marks that spoof text
// direction.
func isBidiControl(r rune) bool {
	switch {
	case r >= 0x202A && r <= 0x202E, // LRE..PDF overrides
		r >= 0x2066 && r <= 0x2069, // isolates
		r == 0x200E, r == 0x200F,   // LRM / RLM
		r == 0x061C: // ALM
		return true
	}
	return false
}

// stripZalgo removes zalgo runs and bidi controls from text (AyuGram
// ayu_helpers.cpp filterZalgo 1:1): runs of 3+ combining marks (Mn) keep
// their first two, everything past that drops; bidi controls drop whole.
// Clean text returns unchanged (fast path scans without allocating).
func stripZalgo(s string) string {
	dirty := false
	combos := 0
	for _, r := range s {
		if isBidiControl(r) {
			dirty = true
			break
		}
		if unicode.Is(unicode.Mn, r) {
			combos++
			if combos >= 3 {
				dirty = true
				break
			}
		} else {
			combos = 0
		}
	}
	if !dirty {
		return s
	}

	var b []rune
	run := 0
	for _, r := range s {
		if isBidiControl(r) {
			run = 0
			continue
		}
		if unicode.Is(unicode.Mn, r) {
			run++
			if run > 2 {
				continue // zalgo tail: keep first two marks only
			}
		} else {
			run = 0
		}
		b = append(b, r)
	}
	return string(b)
}

// ayuFilterText applies the toggle to rendered text (message bodies).
func ayuFilterText(s string, on bool) string {
	if !on || s == "" {
		return s
	}
	return stripZalgo(s)
}

// ── reaction-strip visibility ────────────────────────────────────────────

// reactionsVisible gates the under-bubble reaction strip by chat type and
// the three Ayu toggles (showChannel/Group/PrivateReactions — AyuGram
// defaults all three ON; a nil config key means ON, only an explicit
// false hides).
func reactionsVisible(chat engine.ChatInfo, cfg cfgSnapshot) bool {
	switch chat.Type {
	case engine.ChatTypeChanVal:
		return cfg.AyuReactChannels
	case engine.ChatTypeGroupVal, engine.ChatTypeTopicVal:
		return cfg.AyuReactGroups
	default:
		return cfg.AyuReactPrivate
	}
	// (cfgSnapshot carries the EFFECTIVE values — nil folded to true in
	// cfgFromAppConfig.)
}

// ── send confirmations ───────────────────────────────────────────────────

// mediaConfirmState is one pending confirmed send.
type mediaConfirmState struct {
	kind      string // "sticker" | "gif" | "voice"
	send      func()
	ok        *widget.Clickable
	cancelBtn *widget.Clickable
}

var (
	mediaConfirmMu sync.Mutex
	mediaConfirm   *mediaConfirmState
)

// confirmKindTitle: the card headline per media kind (AyuGram
// lng-style phrasing).
func confirmKindTitle(kind string) string {
	switch kind {
	case "sticker":
		return "Send this sticker?"
	case "gif":
		return "Send this GIF?"
	case "voice":
		return "Send this voice message?"
	}
	return "Send this?"
}

// maybeConfirmMedia fires the send directly, or parks it behind the
// confirm card when the Ayu confirmation toggle is on.
func (a *App) maybeConfirmMedia(kind string, on bool, send func()) {
	if !on {
		send()
		return
	}
	mediaConfirmMu.Lock()
	mediaConfirm = &mediaConfirmState{
		kind:      kind,
		send:      send,
		ok:        new(widget.Clickable),
		cancelBtn: new(widget.Clickable),
	}
	mediaConfirmMu.Unlock()
	a.invalidate()
}

// mediaConfirmActive reports whether the card is open.
func mediaConfirmActive() bool {
	mediaConfirmMu.Lock()
	defer mediaConfirmMu.Unlock()
	return mediaConfirm != nil
}

// layoutMediaConfirm renders the centered confirm card + scrim over the
// chat pane (the callsConfirmCard pattern, checkbox-free).
func (a *App) layoutMediaConfirm(gtx layout.Context) layout.Dimensions {
	mediaConfirmMu.Lock()
	mc := mediaConfirm
	mediaConfirmMu.Unlock()
	if mc == nil {
		return layout.Dimensions{}
	}
	if mc.ok.Clicked(gtx) {
		mediaConfirmMu.Lock()
		mediaConfirm = nil
		mediaConfirmMu.Unlock()
		go mc.send()
		a.invalidate()
		return layout.Dimensions{}
	}
	if mc.cancelBtn.Clicked(gtx) {
		mediaConfirmMu.Lock()
		mediaConfirm = nil
		mediaConfirmMu.Unlock()
		a.invalidate()
		return layout.Dimensions{}
	}

	// Scrim behind the card.
	paint.FillShape(gtx.Ops, color.NRGBA{R: 0, G: 0, B: 0, A: 0x66},
		clip.Rect{Max: image.Pt(gtx.Constraints.Max.X, gtx.Constraints.Max.Y)}.Op())

	cardW := gtx.Dp(unit.Dp(340))
	if cardW > gtx.Constraints.Max.X {
		cardW = gtx.Constraints.Max.X
	}
	return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		gtx.Constraints.Max.X = cardW
		return roundedFill(gtx, a.ui.p.Surface, 14, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(18)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return a.ui.H3(confirmKindTitle(mc.kind)).Layout(gtx)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(6), Bottom: unit.Dp(14)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Dim(unit.Sp(13), "AyuGram send confirmation")
							return lbl.Layout(gtx)
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
							layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
								return layout.Dimensions{Size: image.Pt(gtx.Constraints.Max.X, 1)}
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								return layout.Inset{Right: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
									btn := material.Button(a.ui.Theme, mc.cancelBtn, "Cancel")
									btn.Background = a.ui.p.SurfaceHi
									btn.Color = a.ui.p.Text
									return btn.Layout(gtx)
								})
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								btn := material.Button(a.ui.Theme, mc.ok, "Send")
								btn.Background = a.ui.p.Accent
								return btn.Layout(gtx)
							}),
						)
					}),
				)
			})
		})
	})
}
