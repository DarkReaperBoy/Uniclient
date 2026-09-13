package gui

import (
	"image"
	"image/color"

	"gioui.org/layout"
	"gioui.org/op/clip"
	"gioui.org/op/paint"
	"gioui.org/unit"

	"uniclient/engine"
)

// Send-as identity picker (slice 178, parity row "Send-as channel (in
// groups)"): chats where the account can post as more than one identity
// (self + channels it admins) show a "Sending as <name>" row above the
// composer; tapping it opens the identity picker; picking one persists
// through engine.SaveDefaultSendAs (messages.saveDefaultSendAs — the
// server applies the identity to subsequent sends). One identity or
// none → the row hides entirely (§1.10 honest gating).

// chatInfoFor looks the chat's info up (nil when not in the list).
func (a *App) chatInfoFor(k chatKey) *engine.ChatInfo {
	a.mu.Lock()
	defer a.mu.Unlock()
	for i := range a.chats {
		if a.chats[i].AccountID == k.AccountID && a.chats[i].ChatID == k.ChatID {
			c := a.chats[i]
			return &c
		}
	}
	return nil
}

// sendAsRowVisible: the row shows only with a real choice.
func sendAsRowVisible(peers []engine.SendAsPeerInfo) bool {
	return len(peers) > 1
}

// sendAsCurrent resolves the active identity: the saved one when still
// offered, else the first non-channel (self).
func sendAsCurrent(peers []engine.SendAsPeerInfo, saved string) string {
	if saved != "" {
		for _, p := range peers {
			if p.PeerID == saved {
				return p.PeerID
			}
		}
	}
	for _, p := range peers {
		if !p.IsChannel {
			return p.PeerID
		}
	}
	if len(peers) > 0 {
		return peers[0].PeerID
	}
	return ""
}

// sendAsName: the identity's display name.
func sendAsName(peers []engine.SendAsPeerInfo, peerID string) (string, bool) {
	for _, p := range peers {
		if p.PeerID == peerID {
			if p.DisplayName != "" {
				return p.DisplayName, true
			}
			return "Channel", true
		}
	}
	return "", false
}

// ensureSendAs loads the offered identities for the open chat (once per
// chat open; hidden entirely on error or single-identity results).
func (a *App) ensureSendAs(f frame) {
	k := f.selected
	if k == nil {
		return
	}
	a.mu.Lock()
	cur := a.sendAsFor
	a.mu.Unlock()
	if cur != nil && *cur == *k {
		return
	}
	chat := a.chatInfoFor(*k)
	if chat == nil || (chat.Type != engine.ChatTypeGroupVal && chat.Type != engine.ChatTypeChanVal) {
		return
	}
	acc, chatID := k.AccountID, k.ChatID
	a.mu.Lock()
	kk := *k
	a.sendAsFor = &kk
	a.sendAs = nil
	a.mu.Unlock()
	go func() {
		peers, err := a.eng.GetSendAs(acc, chatID)
		a.mu.Lock()
		if a.sendAsFor == nil || *a.sendAsFor != (chatKey{AccountID: acc, ChatID: chatID}) {
			a.mu.Unlock()
			return
		}
		if err == nil && len(peers) > 0 {
			a.sendAs = peers
		} else {
			a.sendAs = nil
		}
		a.mu.Unlock()
		if err == nil {
			a.invalidate()
		}
	}()
}

// openSendAsPicker shows the identity dialog for the open chat.
func (a *App) openSendAsPicker() {
	a.mu.Lock()
	k := a.selected
	if k == nil {
		a.mu.Unlock()
		return
	}
	a.sendAsDlg = true
	a.mu.Unlock()
	a.invalidate()
}

// closeSendAsPicker dismisses it.
func (a *App) closeSendAsPicker() {
	a.mu.Lock()
	if !a.sendAsDlg {
		a.mu.Unlock()
		return
	}
	a.sendAsDlg = false
	a.mu.Unlock()
	a.invalidate()
}

// pickSendAs persists the chosen identity (messages.saveDefaultSendAs —
// the server routes subsequent sends through it).
func (a *App) pickSendAs(peerID string) {
	a.mu.Lock()
	k := a.selected
	a.sendAsDlg = false
	a.sendAsCur = peerID
	a.mu.Unlock()
	a.invalidate()
	if k == nil {
		return
	}
	acc, chatID := k.AccountID, k.ChatID
	go func() {
		if err := a.eng.SaveDefaultSendAs(acc, chatID, peerID); err != nil {
			a.setToast("Send-as: " + err.Error())
			return
		}
	}()
}

// sendAsRow renders the "Sending as <name>" strip above the composer
// input (avatar + name + chevron). Hidden when there is no choice.
func (a *App) sendAsRow(gtx layout.Context, f frame) layout.Dimensions {
	if !sendAsRowVisible(f.sendAs) {
		return layout.Dimensions{}
	}
	cur := sendAsCurrent(f.sendAs, f.sendAsCur)
	name, _ := sendAsName(f.sendAs, cur)
	if a.wid.sendAsBtn.Clicked(gtx) {
		a.openSendAsPicker()
	}
	return layout.Inset{Bottom: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return a.wid.sendAsBtn.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return roundedFill(gtx, a.ui.p.SurfaceHi, unit.Dp(14), func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Top: unit.Dp(3), Bottom: unit.Dp(3), Left: unit.Dp(6), Right: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							return a.ui.Avatar(gtx, name, unit.Dp(20), dotNone)
						}),
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							return layout.Inset{Left: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Label(unit.Sp(12), "Sending as "+name)
								lbl.Color = a.ui.p.TextDim
								lbl.MaxLines = 1
								return lbl.Layout(gtx)
							})
						}),
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							return layout.Inset{Left: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								gtx.Constraints.Max.X = gtx.Dp(unit.Dp(16))
								gtx.Constraints.Max.Y = gtx.Dp(unit.Dp(16))
								return iconNavChevronRight.Layout(gtx, a.ui.p.TextDim)
							})
						}),
					)
				})
			})
		})
	})
}

// layoutSendAsDialog: the identity picker (modal list above the chat).
func (a *App) layoutSendAsDialog(gtx layout.Context, f frame) layout.Dimensions {
	peers := f.sendAs
	cur := sendAsCurrent(peers, f.sendAsCur)
	growClickables(&a.wid.sendAsRowBtns, len(peers))
	for i := range peers {
		if a.wid.sendAsRowBtns[i].Clicked(gtx) {
			a.pickSendAs(peers[i].PeerID)
		}
	}
	if a.wid.sendAsCloseBtn.Clicked(gtx) {
		a.closeSendAsPicker()
	}

	// Scrim.
	paint.FillShape(gtx.Ops, color.NRGBA{R: 0, G: 0, B: 0, A: 0x66},
		clip.Rect{Max: image.Pt(gtx.Constraints.Max.X, gtx.Constraints.Max.Y)}.Op())

	return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		gtx.Constraints.Max.X = gtx.Dp(unit.Dp(420))
		return roundedFill(gtx, a.ui.p.Surface, unit.Dp(16), func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return layout.Inset{Top: unit.Dp(14), Left: unit.Dp(16), Right: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
							layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.H3("Send messages as")
								return lbl.Layout(gtx)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								return a.ui.IconButton(&a.wid.sendAsCloseBtn, iconContentClear, "Close").Layout(gtx)
							}),
						)
					})
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return layout.Inset{Left: unit.Dp(16), Right: unit.Dp(16), Bottom: unit.Dp(6), Top: unit.Dp(2)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.Dim(unit.Sp(12), "Your messages in this chat will be sent as the chosen identity.")
						lbl.MaxLines = 2
						return lbl.Layout(gtx)
					})
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return layout.UniformInset(unit.Dp(8)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						return a.wid.sendAsList.Layout(gtx, len(peers), func(gtx layout.Context, i int) layout.Dimensions {
							p := peers[i]
							sel := p.PeerID == cur
							return layout.Inset{Bottom: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								return a.wid.sendAsRowBtns[i].Layout(gtx, func(gtx layout.Context) layout.Dimensions {
									bg := a.ui.p.SurfaceHi
									if sel {
										bg = blendSurface(a.ui.p.Accent, 0.18)
									}
									return roundedFill(gtx, bg, unit.Dp(12), func(gtx layout.Context) layout.Dimensions {
										return layout.UniformInset(unit.Dp(8)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
											return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
												layout.Rigid(func(gtx layout.Context) layout.Dimensions {
													name := p.DisplayName
													if name == "" {
														name = "Channel"
													}
													return a.ui.Avatar(gtx, name, unit.Dp(32), dotNone)
												}),
												layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
													return layout.Inset{Left: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
														name := p.DisplayName
														if name == "" {
															name = "Channel"
														}
														return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
															layout.Rigid(func(gtx layout.Context) layout.Dimensions {
																lbl := a.ui.Label(unit.Sp(14), name)
																lbl.MaxLines = 1
																return lbl.Layout(gtx)
															}),
															layout.Rigid(func(gtx layout.Context) layout.Dimensions {
																sub := "Personal account"
																if p.IsChannel {
																	sub = "Channel"
																}
																lbl := a.ui.Dim(unit.Sp(11), sub)
																lbl.MaxLines = 1
																return lbl.Layout(gtx)
															}),
														)
													})
												}),
												layout.Rigid(func(gtx layout.Context) layout.Dimensions {
													if !sel {
														return layout.Dimensions{}
													}
													gtx.Constraints.Max.X = gtx.Dp(unit.Dp(20))
													gtx.Constraints.Max.Y = gtx.Dp(unit.Dp(20))
													return iconNavigationCheck.Layout(gtx, a.ui.p.Accent)
												}),
											)
										})
									})
								})
							})
						})
					})
				}),
			)
		})
	})
}
