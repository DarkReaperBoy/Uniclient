package gui

import (
	"image"
	"strings"

	"gioui.org/io/event"
	"gioui.org/io/key"
	"gioui.org/layout"
	"gioui.org/op/clip"
	"gioui.org/unit"
	"gioui.org/widget"
)

// Invite-link join (AyuGram parity, matrix #278): pasting a t.me invite
// link (or +hash) into the search field surfaces a join row; the confirm
// card shows the preview title from engine.CheckChatInvite, then joins
// via engine.ImportChatInvite.

// inviteDlgState: open confirm card (nil when closed).
type inviteDlgState struct {
	hash    string
	title   string // "" while checking
	checked bool
	busy    bool
}

var (
	inviteJoinBtn   widget.Clickable
	inviteCancelBtn widget.Clickable
	inviteKeyTag    = new(struct{})
)

// extractInviteHash (pure, testable): pulls the invite hash out of a
// query; ok=false when it isn't an invite link. Accepts full URLs
// (https://t.me/+hash, t.me/joinchat/hash), +hash, and joinchat/hash.
func extractInviteHash(q string) (string, bool) {
	q = strings.TrimSpace(q)
	if q == "" {
		return "", false
	}
	low := strings.ToLower(q)
	// Strip URL prefixes (same byte length in q and low).
	for _, pre := range []string{"https://", "http://", "www."} {
		if strings.HasPrefix(low, pre) {
			low = low[len(pre):]
			q = q[len(pre):]
		}
	}
	strip := func(n int) {
		low = low[n:]
		q = q[n:]
	}
	// Bare "+hash".
	if strings.HasPrefix(low, "+") {
		strip(1)
		if h := q; h != "" && !strings.Contains(h, "/") && len(h) >= 5 {
			return h, true
		}
		return "", false
	}
	if strings.HasPrefix(low, "joinchat/") {
		strip(len("joinchat/"))
		if h := q; h != "" && !strings.Contains(h, "/") && len(h) >= 5 {
			return h, true
		}
		return "", false
	}
	// Domain form: t.me-style hosts with +hash or joinchat/hash paths.
	domains := []string{"t.me/", "telegram.me/", "telegram.dog/"}
	matched := false
	for _, d := range domains {
		if strings.HasPrefix(low, d) {
			strip(len(d))
			matched = true
			break
		}
	}
	if !matched {
		return "", false
	}
	if strings.HasPrefix(low, "+") {
		strip(1)
	} else if strings.HasPrefix(low, "joinchat/") {
		strip(len("joinchat/"))
	} else {
		// Plain t.me/username — a public link, not an invite (the global
		// server search resolves those instead).
		return "", false
	}
	h := strings.TrimSpace(q)
	if h == "" || strings.Contains(h, "/") || len(h) < 5 {
		return "", false
	}
	return h, true
}

// inviteScopeAccount picks the account to join with: the scoped one, else
// the first connected.
func inviteScopeAccount(f frame) string {
	if f.acctFilter != "" {
		return f.acctFilter
	}
	if c := currentAccount(f); c.ID != "" {
		return c.ID
	}
	if len(f.accounts) > 0 {
		return f.accounts[0].ID
	}
	return ""
}

// openInviteJoin starts the check + confirm flow for a hash.
func (a *App) openInviteJoin(hash string) {
	acc := inviteScopeAccount(a.snapshotForInvite())
	a.mu.Lock()
	a.inviteDlg = &inviteDlgState{hash: hash}
	a.mu.Unlock()
	a.invalidate()
	if acc == "" {
		a.setToast("Connect an account first")
		a.mu.Lock()
		a.inviteDlg = nil
		a.mu.Unlock()
		return
	}
	go func() {
		title, err := a.eng.CheckChatInvite(acc, hash)
		a.mu.Lock()
		if a.inviteDlg == nil || a.inviteDlg.hash != hash {
			a.mu.Unlock()
			return
		}
		if err != nil {
			a.inviteDlg.checked = true
			a.inviteDlg.title = "Invite link"
			a.mu.Unlock()
			a.setToast("Preview unavailable: " + err.Error())
			return
		}
		a.inviteDlg.checked = true
		a.inviteDlg.title = title
		a.mu.Unlock()
		a.invalidate()
	}()
}

// snapshotForInvite: a lightweight frame for scope resolution.
func (a *App) snapshotForInvite() frame {
	return a.snapshot()
}

// closeInviteDialog dismisses the confirm card.
func (a *App) closeInviteDialog() {
	a.mu.Lock()
	if a.inviteDlg == nil || a.inviteDlg.busy {
		a.mu.Unlock()
		return
	}
	a.inviteDlg = nil
	a.mu.Unlock()
	a.invalidate()
}

// submitInviteJoin joins via ImportChatInvite (async) and refreshes.
func (a *App) submitInviteJoin() {
	a.mu.Lock()
	if a.inviteDlg == nil || a.inviteDlg.busy {
		a.mu.Unlock()
		return
	}
	hash := a.inviteDlg.hash
	a.inviteDlg.busy = true
	a.mu.Unlock()
	acc := inviteScopeAccount(a.snapshotForInvite())
	go func() {
		if err := a.eng.ImportChatInvite(acc, hash); err != nil {
			a.mu.Lock()
			if a.inviteDlg != nil {
				a.inviteDlg.busy = false
			}
			a.mu.Unlock()
			a.setToast("Join failed: " + err.Error())
			return
		}
		a.mu.Lock()
		a.inviteDlg = nil
		a.mu.Unlock()
		a.setToast("Joined via invite link")
		a.refreshChats()
		a.refreshFolders(a.acctFilterLocked())
	}()
}

// layoutInviteDialog renders the centered confirm card over the sidebar.
func (a *App) layoutInviteDialog(gtx layout.Context, f frame) layout.Dimensions {
	d := f.inviteDlg
	{
		stack := clip.Rect{Max: image.Pt(gtx.Constraints.Max.X, gtx.Constraints.Max.Y)}.Push(gtx.Ops)
		event.Op(gtx.Ops, inviteKeyTag)
		stack.Pop()
	}
	for {
		ev, ok := gtx.Source.Event(key.Filter{Name: key.NameEscape})
		if !ok {
			break
		}
		if ke, is := ev.(key.Event); is && ke.State == key.Press {
			a.closeInviteDialog()
		}
	}
	if inviteCancelBtn.Clicked(gtx) {
		a.closeInviteDialog()
	}
	if inviteJoinBtn.Clicked(gtx) {
		a.submitInviteJoin()
	}

	paintScrimRect(gtx)

	title := "Checking invite…"
	if d.checked {
		if d.title != "" {
			title = d.title
		} else {
			title = "Invite link"
		}
	}
	joinLabel := "Join"
	if d.busy {
		joinLabel = "Joining…"
	}

	return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		gtx.Constraints.Max.X = gtx.Dp(unit.Dp(320))
		return roundedFill(gtx, a.ui.p.Surface, 12, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(16)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.H3(title)
						lbl.MaxLines = 1
						return lbl.Layout(gtx)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Dim(unit.Sp(13), "You are joining this chat via an invite link.")
							return lbl.Layout(gtx)
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(14)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
								layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
									btn := a.ui.TextButton(&inviteCancelBtn, "Cancel")
									if d.busy {
										btn.Color = a.ui.p.TextFaint
									}
									return btn.Layout(gtx)
								}),
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									btn := a.ui.PrimaryButton(&inviteJoinBtn, joinLabel)
									return btn.Layout(gtx)
								}),
							)
						})
					}),
				)
			})
		})
	})
}
