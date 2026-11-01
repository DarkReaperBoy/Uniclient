package gui

import (
	"gioui.org/layout"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/engine"
)

var (
	topPeerBtns   []widget.Clickable
	topPeersStrip widget.List
)

func init() {
	topPeersStrip.Axis = layout.Horizontal
}

func topPeersScope(f frame) (string, bool) {
	if f.acctFilter != "" {
		return f.acctFilter, true
	}
	switch len(f.accounts) {
	case 1:
		return f.accounts[0].ID, true
	default:
		return "", false
	}
}

func topPeersRows(peers []engine.ChatInfo) []engine.ChatInfo {
	out := make([]engine.ChatInfo, 0, len(peers))
	for _, c := range peers {
		if c.ChatID == "" || c.Title == "" {
			continue
		}
		out = append(out, c)
	}
	return out
}

func (a *App) loadTopPeers(scope string) {
	a.mu.Lock()
	a.topPeersFor = scope
	a.mu.Unlock()
	go func() {
		peers, err := a.eng.GetTopPeers(scope, 12)
		if err != nil {
			peers = nil
		}
		peers = topPeersRows(peers)
		a.mu.Lock()
		if a.topPeersFor == scope {
			a.topPeers = peers
			a.topPeersLoaded = true
		}
		a.mu.Unlock()
		a.invalidate()
	}()
}

func (a *App) layoutTopPeers(gtx layout.Context, f frame) layout.Dimensions {
	if !gtx.Focused(&sidebarSearch) || sidebarSearch.Text() != "" {
		return layout.Dimensions{}
	}
	scope, ok := topPeersScope(f)
	if !ok {
		return layout.Dimensions{}
	}
	if !f.topPeersLoaded || f.topPeersFor != scope {
		a.loadTopPeers(scope)
		return layout.Dimensions{}
	}
	peers := topPeersRows(f.topPeers)
	if len(peers) == 0 {
		return layout.Dimensions{}
	}
	growClickables(&topPeerBtns, len(peers))
	for i := range peers {
		if topPeerBtns[i].Clicked(gtx) {
			c := peers[i]
			a.openChat(chatKey{c.AccountID, c.ChatID}, c.Title)
			break
		}
	}
	return layout.Inset{Left: unit.Dp(12), Right: unit.Dp(12), Top: unit.Dp(2), Bottom: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		gtx.Constraints.Max.Y = gtx.Dp(unit.Dp(68))
		return topPeersStrip.Layout(gtx, len(peers), func(gtx layout.Context, i int) layout.Dimensions {
			c := peers[i]
			return layout.UniformInset(unit.Dp(2)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return materialButtonLayoutStrip(a, &topPeerBtns[i], gtx, c)
			})
		})
	})
}

func materialButtonLayoutStrip(a *App, btn *widget.Clickable, gtx layout.Context, c engine.ChatInfo) layout.Dimensions {
	return material.ButtonLayout(a.ui.Theme, btn).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Axis: layout.Vertical, Alignment: layout.Middle}.Layout(gtx,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return a.ui.Avatar(gtx, c.Title, unit.Dp(40), dotNone)
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				lbl := a.ui.Dim(unit.Sp(11), c.Title)
				lbl.MaxLines = 1
				return lbl.Layout(gtx)
			}),
		)
	})
}
