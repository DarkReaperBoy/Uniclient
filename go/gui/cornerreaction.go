package gui

// Corner reaction button (slice 159, tdesktop cornerReaction 1:1): a small
// pill at the top-right corner of a hovered message bubble showing the
// account's default (favorite) reaction emoji — tapping toggles that
// reaction on the message (tdesktop toggleFavoriteReaction: add when
// absent, remove when already own). Mirrors tdesktop:
//
//   - setting: cornerReaction, default ON, Messages section of Chat
//     settings (lng_settings_chat_corner_reaction "Reaction button in the
//     corner").
//   - the button renders for incoming AND own messages (tdesktop
//     canReact), never in selection mode or for service rows.
//   - the favorite reaction: tdesktop favoriteId() — server-side default
//     from help.getConfig reactions_default (fallback 👍), persisted per
//     account through messages.setDefaultReaction. Picked in Settings →
//     Chat → Quick actions ("React with").
//   - toggling sends the full new own-reaction list (tdesktop
//     toggleReaction semantics): favorite removed from / appended to the
//     current own reactions; an empty list removes them all.
//
// The pill rides the same pane hover routing as the corner reply button
// (slice 157) and anchors NE beside it (tdesktop stacks the reply and
// reaction buttons in the corner).

import (
	"sync"

	"gioui.org/layout"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/cores"
	"uniclient/engine"
)

// effectiveCornerReaction resolves the config (nil = tdesktop default ON).
func effectiveCornerReaction(v *bool) bool {
	return v == nil || *v
}

// favoriteReactionOrDefault is the 👍 fallback for an unset favorite
// (tdesktop ConfigDefaultReactionEmoji). Pure — locked by tests.
func favoriteReactionOrDefault(v string) string {
	if v == "" {
		return "👍"
	}
	return v
}

// cornerReactGate decides whether the pill renders for a message (pure,
// tested): setting on + not selection mode + real, non-service message.
// Unlike the reply pill, own messages qualify (tdesktop canReact).
func cornerReactGate(cornerOn, selOn bool, m engine.CachedMessage) bool {
	if !cornerOn || selOn || m.IsService || m.MsgID == "" {
		return false
	}
	return true
}

// ownHasReaction reports whether the own reaction list already contains
// the emoji. Pure — locked by tests.
func ownHasReaction(reactions []cores.Reaction, emoji string) bool {
	for _, r := range reactions {
		if r.ByMe && r.Emoji == emoji {
			return true
		}
	}
	return false
}

// toggleOwnReactionEmojis computes the new full own-reaction list for a
// favorite toggle (tdesktop toggleReaction semantics — pure, tested):
// favorite removed when present, appended when absent; an empty result
// removes all own reactions server-side.
func toggleOwnReactionEmojis(reactions []cores.Reaction, fav string) []string {
	own := make([]string, 0, len(reactions)+1)
	hasFav := false
	for _, r := range reactions {
		if r.ByMe {
			if r.Emoji == fav {
				hasFav = true
				continue
			}
			own = append(own, r.Emoji)
		}
	}
	if !hasFav {
		own = append(own, fav)
	}
	return own
}

// ── favorite-reaction cache (per account) ────────────────────────────────

var (
	favMu        sync.Mutex
	favReactions = map[string]string{} // accountID → favorite emoji
)

// setFavoriteReaction records the account's favorite emoji.
func setFavoriteReaction(accountID, emoji string) {
	favMu.Lock()
	favReactions[accountID] = emoji
	favMu.Unlock()
}

// favoriteReactionFor reads the account's cached favorite ("" = unset).
func favoriteReactionFor(accountID string) string {
	favMu.Lock()
	defer favMu.Unlock()
	return favReactions[accountID]
}

// loadFavoriteReaction fetches the account's server-side default reaction
// (help.getConfig reactions_default) into the cache. Async.
func (a *App) loadFavoriteReaction(accountID string) {
	if accountID == "" || favoriteReactionFor(accountID) != "" {
		return
	}
	go func() {
		emoji, err := a.eng.GetDefaultReaction(accountID)
		if err != nil || emoji == "" {
			return // keep the 👍 fallback until the server answers
		}
		setFavoriteReaction(accountID, emoji)
		a.invalidate()
	}()
}

// applyFavoriteReaction persists a new favorite (messages.setDefaultReaction)
// and updates the cache. Async.
func (a *App) applyFavoriteReaction(accountID, emoji string) {
	setFavoriteReaction(accountID, emoji)
	go func() {
		if err := a.eng.SetDefaultReaction(accountID, emoji); err != nil {
			a.setToast("React with: " + err.Error())
			return
		}
	}()
}

// ── pill widgets ─────────────────────────────────────────────────────────

// a.wid.msgReactBtns pools the pill clickables keyed by chat/message.

func (a *App) msgReactBtn(key string) *widget.Clickable {
	if btn, ok := a.wid.msgReactBtns[key]; ok {
		return btn
	}
	btn := new(widget.Clickable)
	a.wid.msgReactBtns[key] = btn
	return btn
}

// layoutCornerReaction renders the favorite-reaction pill (or nothing) as
// an East-anchored overlay element. Sits LEFT of the reply pill when both
// render (tdesktop's corner button stack: reply then reaction).
func (a *App) layoutCornerReaction(gtx layout.Context, f frame, m *engine.CachedMessage) layout.Dimensions {
	if !cornerReactGate(f.cfg.CornerReaction, f.selOn, *m) {
		return layout.Dimensions{}
	}
	if m.MsgID != hoveredMsgID() {
		return layout.Dimensions{}
	}
	btn := a.msgReactBtn(m.AccountID + "/" + m.ChatID + "/" + m.MsgID)
	fav := favoriteReactionOrDefault(favoriteReactionFor(m.AccountID))
	own := ownHasReaction(m.Reactions, fav)
	if btn.Clicked(gtx) {
		emojis := toggleOwnReactionEmojis(m.Reactions, fav)
		acct, chat, msg := m.AccountID, m.ChatID, m.MsgID
		go func() {
			if err := a.eng.ReactToMessageList(acct, chat, msg, emojis); err != nil {
				a.setToast("React failed: " + err.Error())
			}
		}()
		return layout.Dimensions{}
	}
	return layout.UniformInset(unit.Dp(0)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		bl := material.ButtonLayout(a.ui.Theme, btn)
		bl.Background = a.ui.p.SurfaceHi
		bl.CornerRadius = 10
		return bl.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(4)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				lbl := a.ui.Label(unit.Sp(14), fav)
				if own {
					// Already reacted with the favorite: highlight it.
					lbl.Color = a.ui.p.Accent
				} else {
					lbl.Color = a.ui.p.Text
				}
				return lbl.Layout(gtx)
			})
		})
	})
}

// cornerButtonsOverlay wraps a message row in a NE-anchored stack carrying
// the corner pills: [favorite-reaction][Reply] for incoming rows, the
// reaction pill alone for own rows. The content renders first so inner
// interactive widgets keep their hit priority.
func (a *App) cornerButtonsOverlay(gtx layout.Context, f frame, m *engine.CachedMessage, canReply bool, content func(gtx layout.Context) layout.Dimensions) layout.Dimensions {
	return layout.Stack{Alignment: layout.NE}.Layout(gtx,
		layout.Stacked(func(gtx layout.Context) layout.Dimensions {
			return content(gtx)
		}),
		layout.Stacked(func(gtx layout.Context) layout.Dimensions {
			if !cornerReactGate(f.cfg.CornerReaction, f.selOn, *m) {
				return layout.Dimensions{}
			}
			return layout.Inset{Top: unit.Dp(2), Right: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
					// Reaction pill, then (incoming rows) the reply pill —
					// tdesktop's corner stack order.
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return a.layoutCornerReaction(gtx, f, m)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return a.layoutCornerReply(gtx, f, m, canReply)
					}),
				)
			})
		}),
	)
}
