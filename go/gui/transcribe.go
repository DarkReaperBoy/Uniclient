package gui

import (
	"image"
	"image/color"
	"log"

	"gioui.org/layout"
	"gioui.org/op/clip"
	"gioui.org/op/paint"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/engine"
)

// Voice-note transcription (slice 115, Telegram messages.transcribeAudio):
// the "A→A" glyph on voice bubbles (Telegram's transcribe affordance) for
// accounts whose core implements the engine's VoiceTranscriber. The result
// renders as a text block under the waveform — "Transcribing…" while the
// server works (updateTranscribedAudio pushes the final text later),
// collapsed to 3 lines with a tap-to-expand, like AyuGram's expandable
// transcription. Everything is engine-backed (§1.10): no capability, no
// button; no text, no block.

// transcribeWanted decides whether the transcribe glyph renders for one
// voice message. Pure — unit-tested.
func transcribeWanted(m *engine.CachedMessage, supported bool) bool {
	if m == nil || !supported {
		return false
	}
	if m.MediaType != engine.MediaVoice || m.IsService {
		return false
	}
	// Already transcribed (or in flight): the text block takes over.
	return m.TranscriptionText == "" && !m.TranscriptionPending
}

// transcriptMaxLines: pending → single hint line; final → 3 collapsed,
// unlimited when expanded. Pure — unit-tested.
func transcriptMaxLines(pending, expanded bool) int {
	if pending {
		return 1
	}
	if expanded {
		return 0 // no limit
	}
	return 3
}

// transcriptLabelText returns the block's text. Pure — unit-tested.
func transcriptLabelText(m *engine.CachedMessage) string {
	if m == nil {
		return ""
	}
	if m.TranscriptionPending && m.TranscriptionText == "" {
		return "Transcribing…"
	}
	return m.TranscriptionText
}

// transcriptCollapseLen: texts longer than this can clip at 3 lines and get
// the expand chip (Telegram shows the full block; we collapse generously).
const transcriptCollapseLen = 160

// transcriptKey identifies one message's transcription widgets.
func transcriptKey(m *engine.CachedMessage) string {
	return m.AccountID + "|" + m.ChatID + "|" + m.MsgID
}

// a.wid.transcribeClickables pools the glyph buttons per message.

func (a *App) transcribeClickable(key string) *widget.Clickable {
	if c, ok := a.wid.transcribeClickables[key]; ok {
		return c
	}
	if len(a.wid.transcribeClickables) > 512 {
		a.wid.transcribeClickables = make(map[string]*widget.Clickable)
	}
	c := new(widget.Clickable)
	a.wid.transcribeClickables[key] = c
	return c
}

// a.wid.transcriptExpandClickables pools the expand/collapse chips per message.

func (a *App) transcriptExpandClickable(key string) *widget.Clickable {
	if c, ok := a.wid.transcriptExpandClickables[key]; ok {
		return c
	}
	if len(a.wid.transcriptExpandClickables) > 512 {
		a.wid.transcriptExpandClickables = make(map[string]*widget.Clickable)
	}
	c := new(widget.Clickable)
	a.wid.transcriptExpandClickables[key] = c
	return c
}

// transcribeVoiceNote runs the engine transcription for one message.
// The cached row (pending or final) lands via refreshMessages; the final
// text for pending results arrives as EventMsgTranscribed.
func (a *App) transcribeVoiceNote(m *engine.CachedMessage) {
	if m == nil {
		return
	}
	go func() {
		_, _, err := a.eng.TranscribeVoiceNote(m.AccountID, m.ChatID, m.MsgID)
		if err != nil {
			log.Printf("gui: transcribe: %v", err)
			a.setToast("Transcription failed: " + err.Error())
		}
		a.refreshMessages()
	}()
}

// transcribeCapFor reports whether the open chat's account can transcribe
// (from the refreshAccounts capability cache; false for closed chats).
// Callers hold a.mu (snapshot) — plain map read, no extra lock.
func (a *App) transcribeCapFor(k *chatKey) bool {
	if k == nil {
		return false
	}
	return a.transcribeCap[k.AccountID]
}

// drawTranscribeGlyph draws the "A→A" badge (Telegram's transcribe icon,
// re-drawn with Material shapes — never copied assets).
func drawTranscribeGlyph(gtx layout.Context, u *UI, accent color.NRGBA, text color.NRGBA) layout.Dimensions {
	w := gtx.Dp(unit.Dp(34))
	h := gtx.Dp(unit.Dp(26))
	r := gtx.Dp(unit.Dp(13))
	shape := clip.UniformRRect(image.Rect(0, 0, w, h), r).Push(gtx.Ops)
	paint.Fill(gtx.Ops, accent)
	shape.Pop()
	lbl := u.Label(unit.Sp(11), "A→A")
	lbl.Color = text
	return layout.Inset{Left: unit.Dp(6), Right: unit.Dp(6), Top: unit.Dp(3), Bottom: unit.Dp(3)}.Layout(gtx, lbl.Layout)
}

// transcriptBlock renders the transcription text block under a voice
// bubble's waveform: pending hint, or the text (collapsed + expand chip).
func (a *App) transcriptBlock(gtx layout.Context, m *engine.CachedMessage) layout.Dimensions {
	text := transcriptLabelText(m)
	if text == "" {
		return layout.Dimensions{}
	}
	key := transcriptKey(m)
	a.mu.Lock()
	expanded := a.transcriptOpen[key]
	a.mu.Unlock()

	return layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(2)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				lbl := a.ui.Label(unit.Sp(13), text)
				lbl.MaxLines = transcriptMaxLines(m.TranscriptionPending, expanded)
				if m.TranscriptionPending && m.TranscriptionText == "" {
					lbl.Color = a.ui.p.TextDim
				}
				return lbl.Layout(gtx)
			}),
			// Expand / collapse chip (only when the text is long enough to clip).
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				if m.TranscriptionPending || len([]rune(m.TranscriptionText)) <= transcriptCollapseLen {
					return layout.Dimensions{}
				}
				clk := a.transcriptExpandClickable(key)
				if clk.Clicked(gtx) {
					a.mu.Lock()
					if a.transcriptOpen == nil {
						a.transcriptOpen = make(map[string]bool)
					}
					a.transcriptOpen[key] = !a.transcriptOpen[key]
					a.mu.Unlock()
					a.invalidate()
				}
				label := "More"
				if expanded {
					label = "Less"
				}
				btn := material.Button(a.ui.Theme, clk, label)
				btn.Background = a.ui.p.Surface
				btn.Color = a.ui.p.Accent
				btn.TextSize = unit.Sp(11)
				btn.CornerRadius = 10
				btn.Inset = layout.Inset{Top: unit.Dp(2), Bottom: unit.Dp(2), Left: unit.Dp(8), Right: unit.Dp(8)}
				return layout.Inset{Top: unit.Dp(2)}.Layout(gtx, btn.Layout)
			}),
		)
	})
}
