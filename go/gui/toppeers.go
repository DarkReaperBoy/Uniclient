package gui

import (
	"gioui.org/layout"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/engine"
)

// Top peers strip (AyuGram parity slice 72): the row of pictured top
// contacts Telegram shows above the chat list while the search field is
// focused and empty. Data: engine.GetTopPeers (server-side ranking),
// scoped to the current account — with a unified multi-account list the
// scope must be unambiguous (account filter set or exactly one account),
// otherwise the strip stays hidden. Tapping a peer opens their chat.

var (
	topPeerBtns   []widget.Clickable
	topPeersStrip widget.List
)

func init() {
	topPeersStrip.Axis = layout.Horizontal
}

// topPeersScope resolves the account the strip renders for. ok=false
// hides the strip (no unambiguous scope).
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

// topPeersRows drops rows without chat backing (empty id/title).
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

// loadTopPeers fetches the strip data for an account scope (async, guarded
// against scope changes and duplicate loads).
func (a *App) loadTopPeers(scope string) {
	a.mu.Lock()
	a.topPeersFor = scope // marks the load in flight
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

// layoutTopPeers renders the strip while the search field is focused and
// empty (the same state as the recent-searches dropdown).
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

// materialButtonLayoutStrip: one avatar + name cell.
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
