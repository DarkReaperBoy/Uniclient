package gui

import (
	"time"

	"gioui.org/layout"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/engine"
)

var (
	voiceList  widget.List
	voiceCalls widget.List
)

func init() {
	voiceList.Axis = layout.Vertical
	voiceCalls.Axis = layout.Vertical
}

func (a *App) layoutVoice(gtx layout.Context, f frame) layout.Dimensions {
	if f.joinedGC != nil {
		return a.layoutGroupCallScreen(gtx, f)
	}
	active := chatsWithCalls(f)

	return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(14), Left: unit.Dp(18), Bottom: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return a.ui.H2("Voice").Layout(gtx)
			})
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Left: unit.Dp(18), Right: unit.Dp(18), Bottom: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				lbl := a.ui.Dim(unit.Sp(13), "Active group calls, voice rooms, and your recent calls across connected accounts.")
				return lbl.Layout(gtx)
			})
		}),
		layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
			if len(active) == 0 && !a.hasRecentCalls(f) {
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
			return list.Layout(gtx, 1, func(gtx layout.Context, _ int) layout.Dimensions {
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
					activeCallsSection(gtx, a, f, active),
					recentCallsSection(gtx, a, f),
				)
			})
		}),
	)
}

func activeCallsSection(gtx layout.Context, a *App, f frame, active []engine.ChatInfo) layout.FlexChild {
	return layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		var children []layout.FlexChild
		for _, c := range active {
			c := c
			children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return a.voiceRow(gtx, f, c)
			}))
		}
		if len(children) == 0 {
			return layout.Dimensions{}
		}
		return layout.Inset{Left: unit.Dp(12), Right: unit.Dp(12), Bottom: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
		})
	})
}

func recentCallsSection(gtx layout.Context, a *App, f frame) layout.FlexChild {
	return layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		if !f.callsLoaded {
			return layout.Inset{Left: unit.Dp(18), Top: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				lbl := a.ui.Dim(unit.Sp(13), "Loading recent calls…")
				lbl.Color = a.ui.p.TextFaint
				return lbl.Layout(gtx)
			})
		}
		var rows []layout.FlexChild
		n := 0
		for _, acc := range f.accounts {
			entries := f.callsList[acc.ID]
			if len(entries) == 0 {
				continue
			}
			acc := acc
			rows = append(rows, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return a.subHeader(gtx, accountName(acc)+" ("+platformTitle(acc.Platform)+")")
			}))
			for _, e := range entries {
				e := e
				n++
				rows = append(rows, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return a.callRow(gtx, f, acc.ID, e)
				}))
			}
		}
		if n == 0 {
			return layout.Inset{Left: unit.Dp(18), Top: unit.Dp(6), Bottom: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				lbl := a.ui.Dim(unit.Sp(13), "No recent calls")
				lbl.Color = a.ui.p.TextFaint
				return lbl.Layout(gtx)
			})
		}
		return layout.Inset{Left: unit.Dp(12), Right: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Vertical}.Layout(gtx, rows...)
		})
	})
}

func (a *App) hasRecentCalls(f frame) bool {
	for _, entries := range f.callsList {
		if len(entries) > 0 {
			return true
		}
	}
	return false
}

func callLabel(e engine.CallHistoryEntry) string {
	switch {
	case e.IsMissed && e.IsOutgoing:
		return "Missed outgoing" + videoSuffix(e) + " call"
	case e.IsMissed:
		return "Missed" + videoSuffix(e) + " call"
	case e.IsOutgoing:
		return "Outgoing" + videoSuffix(e) + " call"
	default:
		return "Incoming" + videoSuffix(e) + " call"
	}
}

func videoSuffix(e engine.CallHistoryEntry) string {
	if e.IsVideo {
		return " video"
	}
	return ""
}

func callStamp(ts int64, now time.Time) string {
	if ts <= 0 {
		return ""
	}
	t := time.Unix(ts, 0)
	if t.Format("2006-01-02") == now.Format("2006-01-02") {
		return t.Format("15:04")
	}
	return t.Format("2 Jan · 15:04")
}

func callSub(e engine.CallHistoryEntry, now time.Time) string {
	sub := callLabel(e)
	if !e.IsMissed && e.Duration > 0 {
		sub += " · " + fmtDur(e.Duration)
	}
	if stamp := callStamp(e.Timestamp, now); stamp != "" {
		sub += " · " + stamp
	}
	return sub
}

func (a *App) callRow(gtx layout.Context, f frame, accountID string, e engine.CallHistoryEntry) layout.Dimensions {
	if a.callRowBtn(e).Clicked(gtx) {
		if chat, ok := findChatByPeer(f, accountID, e.PeerID); ok {
			a.openChat(chatKey{AccountID: accountID, ChatID: e.PeerID}, chat.Title)
		} else {
			a.setToast("Call peer not in your chat list")
		}
	}
	name := e.PeerName
	if name == "" {
		name = "Unknown"
	}
	return layout.Inset{Bottom: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		bl := material.ButtonLayout(a.ui.Theme, a.callRowBtn(e))
		bl.Background = a.ui.p.Surface
		bl.CornerRadius = 12
		return bl.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(12)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Right: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return a.ui.Avatar(gtx, name, unit.Dp(42), dotNone)
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Right: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							gtx.Constraints.Max.X = gtx.Dp(unit.Dp(20))
							gtx.Constraints.Max.Y = gtx.Dp(unit.Dp(20))
							c := a.ui.p.TextDim
							if e.IsMissed {
								c = a.ui.p.Error
							}
							if e.IsVideo {
								return iconAVVideocam.Layout(gtx, c)
							}
							return iconCommunicationCall.Layout(gtx, c)
						})
					}),
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Label(unit.Sp(15), name)
								return lbl.Layout(gtx)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Dim(unit.Sp(12), callSub(e, f.now))
								if e.IsMissed {
									lbl.Color = a.ui.p.Error
								} else {
									lbl.Color = a.ui.p.TextDim
								}
								return lbl.Layout(gtx)
							}),
						)
					}),
				)
			})
		})
	})
}

func findChatByPeer(f frame, accountID, peerID string) (engine.ChatInfo, bool) {
	for _, c := range f.chats {
		if c.AccountID == accountID && c.ChatID == peerID {
			return c, true
		}
	}
	return engine.ChatInfo{}, false
}

func (a *App) callRowBtn(e engine.CallHistoryEntry) *widget.Clickable {
	key := e.PeerID + "/" + e.MsgID
	if btn, ok := a.wid.callBtnPool[key]; ok {
		return btn
	}
	btn := new(widget.Clickable)
	a.wid.callBtnPool[key] = btn
	if len(a.wid.callBtnPool) > 512 {
		a.wid.callBtnPool = map[string]*widget.Clickable{key: btn}
	}
	return btn
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

func (a *App) voiceRow(gtx layout.Context, f frame, c engine.ChatInfo) layout.Dimensions {
	if btn := a.gcRowJoinBtnFor(c.ChatID); btn.Clicked(gtx) {
		a.joinGroupCallFromVoice(c)
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
						btn := a.ui.PrimaryButton(a.gcRowJoinBtnFor(c.ChatID), "JOIN")
						return btn.Layout(gtx)
					}),
				)
			})
		})
	})
}
