package gui

import (
	"image"
	"image/color"
	"time"

	"gioui.org/io/event"
	"gioui.org/io/pointer"
	"gioui.org/layout"
	"gioui.org/op"
	"gioui.org/op/clip"
	"gioui.org/op/paint"
	"gioui.org/unit"
	"gioui.org/widget"

	"uniclient/engine"
)

// Hold-to-record voice notes (slice 114). The mic button sits in the
// a.wid.composer (text empty + the account supports voice notes); press-and-
// hold captures through the engine recorder while the a.wid.composer row
// becomes the recording panel (red dot, elapsed, level bars, slide-to-
// cancel hint). Release sends (≥ 0.9 s), slide left (or a pointercancel)
// discards. Platforms without a microphone keep the button but the
// engine's start error surfaces as a toast (§1.10 — honest, no dead UI:
// the button only appears for cores that can send voice notes).

// voiceRecTag is the single gesture tag: registered over the mic button
// when idle and over the whole recording panel while capturing, so the
// pointer grab survives the layout swap.
var voiceRecTag = new(bool)

type voiceRecState struct {
	active   bool
	press    bool
	dragLeft bool
	start    float32 // press X (slide-left reference)
	chat     chatKey
}

// voiceRecActive reports whether a capture is in progress.
func (a *App) voiceRecActive() bool {
	if !a.voiceRec.active || a.eng == nil {
		return false
	}
	return a.eng.VoiceRecording().Active
}

// voiceRecWanted: the mic button renders when the a.wid.composer is empty,
// nothing is being recorded, and the chat's core can send voice notes.
func (a *App) voiceRecWanted(f frame) bool {
	if f.msgFor == nil || a.voiceRec.active || f.sending {
		return false
	}
	if a.eng == nil {
		return false
	}
	return a.eng.VoiceRecordingSupported(f.msgFor.AccountID)
}

// voiceRecPanel replaces the a.wid.composer while recording.
func (a *App) voiceRecPanel(gtx layout.Context, f frame, chat *engine.ChatInfo) layout.Dimensions {
	rec := a.eng.VoiceRecording()
	if !rec.Active {
		// The engine stopped (min-duration discard, error): back to the
		// a.wid.composer.
		a.voiceRec.active = false
		return a.composerBar(gtx, f, chat)
	}

	// Full-panel gesture surface for the ongoing hold.
	{
		area := clip.Rect{Max: gtx.Constraints.Min}.Push(gtx.Ops)
		event.Op(gtx.Ops, voiceRecTag)
		area.Pop()
	}
	for {
		ev, ok := gtx.Source.Event(voiceRecFilter())
		if !ok {
			break
		}
		e, is := ev.(pointer.Event)
		if !is {
			continue
		}
		switch e.Kind {
		case pointer.Drag:
			a.voiceRecTrackDrag(e.Position.X)
		case pointer.Release:
			a.voiceRecFinish(f, a.voiceRec.dragLeft)
		case pointer.Cancel:
			a.voiceRecFinish(f, true)
		}
	}

	return layout.Inset{Top: unit.Dp(8), Bottom: unit.Dp(8), Left: unit.Dp(12), Right: unit.Dp(12)}.Layout(gtx,
		func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return layout.Inset{Right: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						return drawRecDot(gtx, gtx.Dp(unit.Dp(14)), time.Now())
					})
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return a.voiceRecLevelBars(gtx, rec.Level)
				}),
				layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
					lbl := a.ui.Label(unit.Sp(14), fmtDur(int(rec.Seconds+0.5)))
					lbl.Color = a.ui.p.Error
					return layout.Inset{Left: unit.Dp(10)}.Layout(gtx, lbl.Layout)
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					hint := "release to send · slide ← to cancel"
					if a.voiceRec.dragLeft {
						hint = "release to cancel"
					}
					lbl := a.ui.Dim(unit.Sp(11), hint)
					return lbl.Layout(gtx)
				}),
			)
		})
}

// voiceRecTrackDrag updates the slide-left cancel zone.
func (a *App) voiceRecTrackDrag(x float32) {
	left := a.voiceRec.start - 80
	now := x < left
	if now != a.voiceRec.dragLeft {
		a.voiceRec.dragLeft = now
		a.invalidate()
	}
}

// voiceRecFinish stops the capture: cancel discards, otherwise the note
// is sent once it reached the minimum duration.
func (a *App) voiceRecFinish(f frame, cancel bool) {
	if !a.voiceRec.press {
		return
	}
	a.voiceRec.press = false
	a.voiceRec.active = false
	if cancel {
		a.eng.CancelVoiceRecording()
		a.setToast("Recording cancelled")
		a.invalidate()
		return
	}
	go func() {
		path, secs, err := a.eng.StopVoiceRecording()
		if err != nil {
			a.setToast("Recording failed: " + err.Error())
			return
		}
		if path == "" {
			a.setToast("Hold the mic button to record")
			return
		}
		k := f.msgFor
		if k == nil {
			k = &a.voiceRec.chat
		}
		if k == nil {
			return
		}
		// Ayu voiceConfirmation (slice 173): park the send behind the
		// confirm card when the toggle is on. The temp recording file
		// survives until the user decides.
		send := func() {
			if _, err := a.eng.SendVoiceNote(k.AccountID, k.ChatID, path, int(secs+0.5)); err != nil {
				a.setToast("Voice note failed: " + err.Error())
			}
		}
		a.maybeConfirmMedia("voice", f.cfg.AyuConfirmVoice, send)
	}()
	a.invalidate()
}

// voiceRecMicButton renders the hold-to-record mic control and drives
// the press that starts the capture.
func (a *App) voiceRecMicButton(gtx layout.Context, f frame) layout.Dimensions {
	clk := a.voiceRecClickable(f)
	dims := clk.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		btn := a.ui.IconButton(clk, iconAVMic, "Record voice message")
		btn.Color = a.ui.p.TextDim
		return btn.Layout(gtx)
	})

	// The gesture area exactly covers the button; the same tag later
	// covers the recording panel, keeping the pointer grab alive.
	{
		area := clip.Rect{Max: dims.Size}.Push(gtx.Ops)
		event.Op(gtx.Ops, voiceRecTag)
		area.Pop()
	}
	for {
		ev, ok := gtx.Source.Event(voiceRecFilter())
		if !ok {
			break
		}
		e, is := ev.(pointer.Event)
		if !is {
			continue
		}
		switch e.Kind {
		case pointer.Press:
			if e.Buttons == pointer.ButtonPrimary {
				a.voiceRec.press = true
				a.voiceRec.dragLeft = false
				a.voiceRec.start = e.Position.X
				if f.msgFor != nil {
					a.voiceRec.chat = *f.msgFor
				}
				if err := a.eng.StartVoiceRecording(); err == nil {
					a.voiceRec.active = true
					a.startVoiceRecTicker()
				} else {
					a.voiceRec.press = false
					a.setToast("Microphone unavailable")
				}
				a.invalidate()
			}
		case pointer.Drag:
			if a.voiceRec.press {
				a.voiceRecTrackDrag(e.Position.X)
			}
		case pointer.Release:
			a.voiceRecFinish(f, a.voiceRec.dragLeft)
		case pointer.Cancel:
			a.voiceRecFinish(f, true)
		}
	}
	return dims
}

func voiceRecFilter() pointer.Filter {
	return pointer.Filter{Target: voiceRecTag, Kinds: pointer.Press | pointer.Drag | pointer.Release | pointer.Cancel}
}

// startVoiceRecTicker redraws 10×/s while recording (elapsed + level).
func (a *App) startVoiceRecTicker() {
	a.mu.Lock()
	if a.voiceRecTickerOn {
		a.mu.Unlock()
		return
	}
	a.voiceRecTickerOn = true
	a.mu.Unlock()
	go func() {
		t := time.NewTicker(100 * time.Millisecond)
		defer t.Stop()
		for range t.C {
			if !a.eng.VoiceRecording().Active {
				a.mu.Lock()
				a.voiceRecTickerOn = false
				a.mu.Unlock()
				return
			}
			a.invalidate()
		}
	}()
}

// voiceRecLevelBars draws the live input level as growing bars.
func (a *App) voiceRecLevelBars(gtx layout.Context, level float64) layout.Dimensions {
	w := gtx.Dp(unit.Dp(90))
	h := gtx.Dp(unit.Dp(22))
	const n = 12
	lvl := level
	if lvl > 1 {
		lvl = 1
	}
	for i := 0; i < n; i++ {
		frac := float32(i) / float32(n)
		var mag float32
		if frac <= float32(lvl) {
			mag = 0.4 + 0.6*float32(lvl)
		} else {
			mag = 0.15
		}
		bh := mag * float32(h)
		bw := float32(w) / float32(n)
		x := float32(i) * bw
		col := a.ui.p.Error
		if a.voiceRec.dragLeft {
			col = a.ui.p.TextDim
		}
		paint.FillShape(gtx.Ops, col, clip.Rect{
			Min: image.Pt(int(x), int((float32(h)-bh)/2)),
			Max: image.Pt(int(x)+max(int(bw*0.6), 1), int((float32(h)+bh)/2)),
		}.Op())
	}
	return layout.Dimensions{Size: image.Pt(w, h)}
}

// drawRecDot renders the pulsing red recording dot.
func drawRecDot(gtx layout.Context, d int, now time.Time) layout.Dimensions {
	if d <= 0 {
		return layout.Dimensions{}
	}
	// Pulse: 1 Hz between bright and dim.
	phase := now.Sub(now.Truncate(time.Second)).Seconds()
	alpha := byte(0xB0)
	if phase < 0.5 {
		alpha = 0xFF
	}
	circle := clip.Ellipse{Min: image.Pt(0, 0), Max: image.Pt(d, d)}.Push(gtx.Ops)
	paint.Fill(gtx.Ops, color.NRGBA{R: 0xE5, G: 0x39, B: 0x35, A: alpha})
	circle.Pop()
	gtx.Execute(op.InvalidateCmd{At: now.Add(500 * time.Millisecond)})
	return layout.Dimensions{Size: image.Pt(d, d)}
}

// a.wid.voiceRecClickables keeps one stable clickable per chat mic button.

func (a *App) voiceRecClickable(f frame) *widget.Clickable {
	key := "mic"
	if f.msgFor != nil {
		key = f.msgFor.String()
	}
	if c, ok := a.wid.voiceRecClickables[key]; ok {
		return c
	}
	if len(a.wid.voiceRecClickables) > 128 {
		a.wid.voiceRecClickables = make(map[string]*widget.Clickable)
	}
	c := new(widget.Clickable)
	a.wid.voiceRecClickables[key] = c
	return c
}
