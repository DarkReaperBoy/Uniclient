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

func transcribeWanted(m *engine.CachedMessage, supported bool) bool {
	if m == nil || !supported {
		return false
	}
	if m.MediaType != engine.MediaVoice || m.IsService {
		return false
	}
	return m.TranscriptionText == "" && !m.TranscriptionPending
}

func transcriptMaxLines(pending, expanded bool) int {
	if pending {
		return 1
	}
	if expanded {
		return 0
	}
	return 3
}

func transcriptLabelText(m *engine.CachedMessage) string {
	if m == nil {
		return ""
	}
	if m.TranscriptionPending && m.TranscriptionText == "" {
		return "Transcribing…"
	}
	return m.TranscriptionText
}

const transcriptCollapseLen = 160

func transcriptKey(m *engine.CachedMessage) string {
	return m.AccountID + "|" + m.ChatID + "|" + m.MsgID
}

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

func (a *App) transcribeCapFor(k *chatKey) bool {
	if k == nil {
		return false
	}
	return a.transcribeCap[k.AccountID]
}

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
