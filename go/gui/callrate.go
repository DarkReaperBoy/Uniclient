package gui

import (
	"image"
	"image/color"
	"strings"
	"time"

	"gioui.org/layout"
	"gioui.org/op/clip"
	"gioui.org/op/paint"
	"gioui.org/unit"
	"gioui.org/widget/material"

	"uniclient/cores"
)

const minRateCallDur = 10 * time.Second

type rateCallState struct {
	accountID string
	callID    string
	peerName  string
	stars     int
	comment   string
}

func (s *rateCallState) valid() bool {
	return s != nil && s.stars >= 1 && s.stars <= 5
}

func (s *rateCallState) setStars(n int) {
	if n < 1 || n > 5 {
		return
	}
	s.stars = n
}

func (s *rateCallState) canSend() bool {
	return s.valid()
}

func (s *rateCallState) payloadComment() string {
	return strings.TrimSpace(s.comment)
}

func callRateable(c *callUI, now time.Time) bool {
	if c == nil || c.state != string(cores.CallStateEnded) {
		return false
	}
	if c.startedAt.IsZero() {
		return false
	}
	var end time.Time
	if c.endedAt.IsZero() {
		end = now
	} else {
		end = c.endedAt
	}
	return end.Sub(c.startedAt) >= minRateCallDur
}

func (a *App) openRateCall(c *callUI) {
	if c == nil {
		return
	}
	a.mu.Lock()
	a.rateDlg = &rateCallState{
		accountID: c.accountID,
		callID:    c.callID,
		peerName:  c.peerName,
	}
	a.mu.Unlock()
	a.invalidate()
}

func (a *App) closeRateCall() {
	a.mu.Lock()
	a.rateDlg = nil
	a.mu.Unlock()
	a.invalidate()
}

func (a *App) sendRateCall() {
	a.mu.Lock()
	st := a.rateDlg
	if st == nil || !st.canSend() {
		a.mu.Unlock()
		return
	}
	acc, callID, stars, comment := st.accountID, st.callID, st.stars, st.payloadComment()
	a.rateDlg = nil
	a.mu.Unlock()
	a.invalidate()
	go func() {
		if err := a.eng.SendCallRating(acc, callID, stars, comment); err != nil {
			a.setToast("Rate call: " + err.Error())
			return
		}
		a.setToast("Thanks for the feedback")
	}()
}

func (a *App) layoutRateCallDialog(gtx layout.Context, f frame) layout.Dimensions {
	st := f.rateDlg
	growClickables(&a.wid.rateStars, 5)
	for i := 1; i <= 5; i++ {
		if a.wid.rateStars[i-1].Clicked(gtx) {
			a.mu.Lock()
			st.setStars(i)
			a.mu.Unlock()
			a.invalidate()
		}
	}
	if a.wid.rateSendBtn.Clicked(gtx) {
		a.sendRateCall()
	}
	if a.wid.rateSkipBtn.Clicked(gtx) {
		a.closeRateCall()
	}

	paint.FillShape(gtx.Ops, color.NRGBA{R: 0, G: 0, B: 0, A: 0x66},
		clip.Rect{Max: image.Pt(gtx.Constraints.Max.X, gtx.Constraints.Max.Y)}.Op())

	return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		cardW := gtx.Dp(unit.Dp(360))
		if cardW > gtx.Constraints.Max.X {
			cardW = gtx.Constraints.Max.X
		}
		gtx.Constraints.Max.X = cardW
		return roundedFill(gtx, a.ui.p.Surface, unit.Dp(16), func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(18)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.H3("Rate this call")
						return lbl.Layout(gtx)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(2)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Dim(unit.Sp(13), "How was the call quality with "+st.peerName+"?")
							lbl.MaxLines = 2
							return lbl.Layout(gtx)
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(14), Bottom: unit.Dp(14)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
									flexForEach(5, func(gtx layout.Context, i int) layout.Dimensions {
										n := i + 1
										return layout.Inset{Right: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
											return a.wid.rateStars[i].Layout(gtx, func(gtx layout.Context) layout.Dimensions {
												gtx.Constraints.Max.X = gtx.Dp(unit.Dp(34))
												gtx.Constraints.Max.Y = gtx.Dp(unit.Dp(34))
												col := a.ui.p.TextFaint
												if st.stars >= n {
													col = a.ui.p.Accent
												}
												return iconToggleStar.Layout(gtx, col)
											})
										})
									})...)
							})
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						ed := a.ui.Editor(&a.wid.rateCommentEd, "Add a comment (optional)")
						ed.Editor.SingleLine = false
						st.comment = a.wid.rateCommentEd.Text()
						return ed.Layout(gtx)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(14)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
								layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
									btn := material.Button(a.ui.Theme, &a.wid.rateSkipBtn, "Skip")
									btn.Background = a.ui.p.SurfaceHi
									btn.Color = a.ui.p.Text
									btn.CornerRadius = 12
									return btn.Layout(gtx)
								}),
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									return layout.Inset{Left: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
										btn := material.Button(a.ui.Theme, &a.wid.rateSendBtn, "Send")
										btn.Background = a.ui.p.Accent
										btn.Color = a.ui.p.Background
										btn.CornerRadius = 12
										if !st.canSend() {
											btn.Background = a.ui.p.SurfaceHi
											btn.Color = a.ui.p.TextDim
										}
										return btn.Layout(gtx)
									})
								}),
							)
						})
					}),
				)
			})
		})
	})
}
