package gui

import (
	"gioui.org/layout"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/engine"
)

// Voice mode widgets.
var (
	voiceList widget.List
)

func init() {
	voiceList.Axis = layout.Vertical
}

// layoutVoice: the second GUI mode — voice-chat backends surface here.
// Until voice cores land (AGENTS.md §7), it lists chats with active calls
// and a clear "coming" state — never a dead end.
func (a *App) layoutVoice(gtx layout.Context, f frame) layout.Dimensions {
	active := chatsWithCalls(f)

	return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(14), Left: unit.Dp(18), Bottom: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return a.ui.H2("Voice").Layout(gtx)
			})
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Left: unit.Dp(18), Right: unit.Dp(18), Bottom: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				lbl := a.ui.Dim(unit.Sp(13), "Group calls and voice rooms across your accounts. Voice backends (Mumble, TeamSpeak) are being rebuilt — see AGENTS.md.")
				return lbl.Layout(gtx)
			})
		}),
		layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
			if len(active) == 0 {
				return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.Flex{Axis: layout.Vertical, Alignment: layout.Middle}.Layout(gtx,
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							return layout.Inset{Bottom: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								gtx.Constraints.Max.X = gtx.Dp(unit.Dp(64))
								gtx.Constraints.Max.Y = gtx.Dp(unit.Dp(64))
								return iconHardwareHeadset.Layout(gtx, a.ui.p.TextFaint)
							})
						}),
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Dim(unit.Sp(14), "No active voice chats right now")
							lbl.Color = a.ui.p.TextFaint
							return lbl.Layout(gtx)
						}),
					)
				})
			}
			list := material.List(a.ui.Theme, &voiceList)
			return list.Layout(gtx, len(active), func(gtx layout.Context, i int) layout.Dimensions {
				return a.voiceRow(gtx, f, active[i])
			})
		}),
	)
}

func chatsWithCalls(f frame) []engine.ChatInfo {
	var out []engine.ChatInfo
	for _, c := range f.chats {
		if c.HasActiveCall {
			out = append(out, c)
		}
	}
	return out
}

// voiceRow: one active-call row with a Join button.
func (a *App) voiceRow(gtx layout.Context, f frame, c engine.ChatInfo) layout.Dimensions {
	for len(voiceJoinBtns) < len(f.chats) {
		voiceJoinBtns = append(voiceJoinBtns, widget.Clickable{})
	}
	idx := voiceIndex(f, c)
	if voiceJoinBtns[idx].Clicked(gtx) {
		a.setToast("Voice: joining is not wired yet — backends under rebuild")
	}

	return layout.Inset{Left: unit.Dp(12), Right: unit.Dp(12), Bottom: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return roundedFill(gtx, a.ui.p.Surface, 12, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(12)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Right: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return a.ui.Avatar(gtx, c.Title, unit.Dp(42), dotNone)
						})
					}),
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Label(unit.Sp(15), c.Title)
								return lbl.Layout(gtx)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Dim(unit.Sp(12), "voice chat in progress · "+platformTitle(platformOf(f, c.AccountID)))
								lbl.Color = a.ui.p.Online
								return lbl.Layout(gtx)
							}),
						)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						btn := a.ui.PrimaryButton(&voiceJoinBtns[idx], "Join")
						btn.CornerRadius = 14
						btn.Inset.Top, btn.Inset.Bottom = 8, 8
						return btn.Layout(gtx)
					}),
				)
			})
		})
	})
}

var voiceJoinBtns []widget.Clickable

func voiceIndex(f frame, c engine.ChatInfo) int {
	for i := range f.chats {
		if f.chats[i].AccountID == c.AccountID && f.chats[i].ChatID == c.ChatID {
			return i
		}
	}
	return 0
}
