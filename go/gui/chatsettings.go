package gui

import (
	"net/url"
	"regexp"
	"strings"

	"gioui.org/layout"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/engine"
)

// Chat settings (AyuGram parity slice 155): the tdesktop "Messages"
// section of Chat settings — the composer submit mode (Enter vs
// Ctrl+Enter, tdesktop's send-submit-way radio) — plus AyuGram's
// "Improve link previews" (Ayu preferences → General): outgoing links of
// big platforms are rewritten to their preview-friendly mirrors (Ayu
// getBetterLinkPreview: fixupx/kktiktok/vxreddit/kkclip/phixiv) so
// Telegram renders richer embeds.

// composerSubmitSends reports whether plain Enter submits the composer
// (tdesktop default; "" and "enter" both mean Enter). "ctrl-enter" moves
// submission to Ctrl+Enter and makes Enter a newline.
func composerSubmitSends(mode string) bool {
	return mode != "ctrl-enter"
}

// composerSubmitLabel renders the setting's current value for the row
// subtitle.
func composerSubmitLabel(mode string) string {
	if mode == "ctrl-enter" {
		return "Ctrl+Enter"
	}
	return "Enter"
}

// improveLinkURLs rewrites http(s) URLs in an outgoing message when Ayu
// "Improve link previews" is on. Only the host swaps — path, query, and
// fragment survive (Ayu semantics). Non-matching hosts and plain text
// pass through untouched.
func improveLinkURLs(text string) string {
	if !strings.Contains(text, "http://") && !strings.Contains(text, "https://") {
		return text
	}
	return improveLinkTokenRe.ReplaceAllStringFunc(text, func(tok string) string {
		u, err := url.Parse(tok)
		if err != nil || u.Host == "" {
			return tok
		}
		host := improveLinkHost(u.Host)
		if host == "" {
			return tok
		}
		u.Host = host
		return u.String()
	})
}

// improveLinkTokenRe matches one whitespace-delimited http(s) token.
var improveLinkTokenRe = regexp.MustCompile(`(?i)\bhttps?://[^\s]+`)

// improveLinkHost maps a URL host to its preview-friendly mirror (Ayu
// getBetterLinkPreview, host branch). "" = no rewrite. Case-insensitive;
// subdomains only for tiktok (Ayu replaces the suffix — vm.tiktok.com →
// vm.kktiktok.com).
func improveLinkHost(host string) string {
	h := strings.ToLower(strings.TrimSpace(host))
	switch h {
	case "twitter.com", "www.twitter.com", "x.com", "www.x.com":
		return "fixupx.com"
	case "tiktok.com", "www.tiktok.com":
		return "kktiktok.com"
	case "reddit.com", "www.reddit.com":
		return "vxreddit.com"
	case "instagram.com", "www.instagram.com":
		return "kkclip.com"
	case "pixiv.net", "www.pixiv.net":
		return "phixiv.net"
	}
	if strings.HasSuffix(h, ".tiktok.com") {
		return strings.TrimSuffix(h, "tiktok.com") + "kktiktok.com"
	}
	return ""
}

// ── widgets ──────────────────────────────────────────────────────────────

var composerSubmitBtns [2]widget.Clickable // Enter | Ctrl+Enter

// swipeActionBtns: one chip per quick action (tdesktop radioenum group).
var swipeActionBtns [6]widget.Clickable

// swipeActionOptions mirrors tdesktop's QuickDialogAction radio (order
// per settings_chat.cpp: Mute, Pin, Read, Archive, Delete, Disabled).
var swipeActionOptions = []struct {
	value, label string
}{
	{"disabled", "Disabled"},
	{"mute", "Mute"},
	{"pin", "Pin"},
	{"read", "Read"},
	{"archive", "Archive"},
	{"delete", "Delete"},
}

// swipeActionOptionLabel finds the chip label for a stored value.
func swipeActionOptionLabel(v string) string {
	for _, o := range swipeActionOptions {
		if o.value == v {
			return o.label
		}
	}
	return "Disabled"
}

// layoutMessagesSection renders the tdesktop "Messages" section rows on
// the Appearance page: Send message with (Enter / Ctrl+Enter chips).
func (a *App) layoutMessagesSection(gtx layout.Context, f frame) layout.Dimensions {
	mode := f.cfg.ComposerSubmit
	for i, v := range []string{"", "ctrl-enter"} {
		v := v
		if composerSubmitBtns[i].Clicked(gtx) {
			go func() {
				c := engine.ConfigChanges{ComposerSubmit: &v}
				if err := a.eng.UpdateConfigFromBridge(&c); err != nil {
					a.setToast("Send with: " + err.Error())
					return
				}
				a.refreshConfig()
			}()
		}
	}
	return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.sectionTitle(gtx, "Messages")
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.settingRow(gtx, "Send message with", "Enter or Ctrl+Enter submits the composer; the other inserts a newline")
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(2), Bottom: unit.Dp(8), Left: unit.Dp(14), Right: unit.Dp(14)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return a.submitModeChip(gtx, &composerSubmitBtns[0], "Enter", mode != "ctrl-enter")
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Left: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return a.submitModeChip(gtx, &composerSubmitBtns[1], "Ctrl+Enter", mode == "ctrl-enter")
						})
					}),
				)
			})
		}),
		// Corner reply button (tdesktop cornerReply, default ON): the
		// fast-reply pill on hovered incoming bubbles.
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.toggleRow(gtx, "cfg:corner_reply", "Reply button in the corner", f.cfg.CornerReply, func(v bool) {
				a.applyConfigBool("corner_reply", v)
			})
		}),
		// Corner reaction button (tdesktop cornerReaction, default ON,
		// slice 159): the favorite-reaction pill on hovered bubbles.
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.toggleRow(gtx, "cfg:corner_reaction", "Reaction button in the corner", f.cfg.CornerReaction, func(v bool) {
				a.applyConfigBool("corner_reaction", v)
			})
		}),
		// Quick actions (tdesktop SetupChatListQuickAction, slice 158):
		// the swipe-able dialog-row action. Disabled is the tdesktop
		// default; each action is state-aware per row (Mute↔Unmute…).
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.sectionTitle(gtx, "Quick actions")
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.settingRow(gtx, "Swipe action", "Swipe a chat row right to "+strings.ToLower(swipeActionOptionLabel(f.cfg.SwipeAction))+" it; swipe left to go back")
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			cur := effectiveSwipeAction(f.cfg.SwipeAction)
			for i, o := range swipeActionOptions {
				o := o
				if swipeActionBtns[i].Clicked(gtx) {
					v := o.value
					go func() {
						c := engine.ConfigChanges{SwipeAction: &v}
						if err := a.eng.UpdateConfigFromBridge(&c); err != nil {
							a.setToast("Swipe action: " + err.Error())
							return
						}
						a.refreshConfig()
					}()
				}
			}
			return layout.Inset{Top: unit.Dp(2), Bottom: unit.Dp(8), Left: unit.Dp(14), Right: unit.Dp(14)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				flex := layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}
				var children []layout.FlexChild
				for i, o := range swipeActionOptions {
					o := o
					children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if len(children) > 0 {
							return layout.Inset{Left: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								return a.submitModeChip(gtx, &swipeActionBtns[i], o.label, cur == o.value)
							})
						}
						return a.submitModeChip(gtx, &swipeActionBtns[i], o.label, cur == o.value)
					}))
				}
				return flex.Layout(gtx, children...)
			})
		}),
		// React with (tdesktop favorite reaction, slice 159): the emoji the
		// corner pill toggles. Per Telegram account (server-side default
		// via help.getConfig reactions_default, saved through
		// messages.setDefaultReaction); 👍 is the fallback.
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.layoutReactWithRow(gtx, f)
		}),
	)
}

// layoutReactWithRow renders the per-account favorite-reaction picker.
func (a *App) layoutReactWithRow(gtx layout.Context, f frame) layout.Dimensions {
	var tgAccounts []engine.AccountInfo
	for _, acc := range f.accounts {
		if platformOf(f, acc.ID) == "telegram" {
			tgAccounts = append(tgAccounts, acc)
		}
	}
	if len(tgAccounts) == 0 {
		return layout.Dimensions{} // nothing reacts without a Telegram account
	}
	children := []layout.FlexChild{
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.settingRow(gtx, "React with", "The emoji the corner reaction button toggles (the account's default reaction)")
		}),
	}
	for _, acc := range tgAccounts {
		acc := acc
		a.loadFavoriteReaction(acc.ID)
		fav := favoriteReactionOrDefault(favoriteReactionFor(acc.ID))
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(2), Bottom: unit.Dp(8), Left: unit.Dp(14), Right: unit.Dp(14)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						who := accountName(acc)
						if len(tgAccounts) == 1 {
							who = "Default reaction"
						}
						lbl := a.ui.Dim(unit.Sp(11), who)
						lbl.Color = a.ui.p.TextFaint
						return lbl.Layout(gtx)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							choices := favoriteReactionChoices(a.availEmojis)
							return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle, Spacing: layout.Spacing(4)}.Layout(gtx, favoriteChipRow(a, gtx, acc.ID, fav, choices)...)
						})
					}),
				)
			})
		}))
	}
	return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
}

// favoriteChipRow builds the emoji chip widgets for one account.
func favoriteChipRow(a *App, gtx layout.Context, accountID, fav string, choices []string) []layout.FlexChild {
	growClickables(&reactWithBtns, len(choices))
	var out []layout.FlexChild
	for i, emoji := range choices {
		i, emoji := i, emoji
		out = append(out, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			btn := &reactWithBtns[i]
			if btn.Clicked(gtx) {
				a.applyFavoriteReaction(accountID, emoji)
			}
			b := material.Button(a.ui.Theme, btn, emoji)
			if fav == emoji {
				b.Background = a.ui.p.Accent
			} else {
				b.Background = a.ui.p.SurfaceHi
			}
			b.TextSize = unit.Sp(15)
			b.CornerRadius = 14
			b.Inset = layout.UniformInset(unit.Dp(5))
			return b.Layout(gtx)
		}))
	}
	return out
}

// favoriteReactionChoices merges the account's available reaction emojis
// with the fallback set (deduped, 👍 first).
func favoriteReactionChoices(avail []string) []string {
	seen := map[string]bool{}
	choices := []string{"👍"}
	seen["👍"] = true
	for _, e := range avail {
		if !seen[e] {
			seen[e] = true
			choices = append(choices, e)
		}
	}
	if len(choices) > 12 {
		choices = choices[:12]
	}
	return choices
}

// reactWithBtns pools the picker chips.
var reactWithBtns []widget.Clickable

// submitModeChip renders one segmented option chip (material clickable).
func (a *App) submitModeChip(gtx layout.Context, btn *widget.Clickable, label string, active bool) layout.Dimensions {
	bg := a.ui.p.SurfaceHi
	fg := a.ui.p.Text
	if active {
		bg = a.ui.p.Accent
		fg = rgb(0xFFFFFF)
	}
	bl := material.ButtonLayout(a.ui.Theme, btn)
	bl.Background = bg
	bl.CornerRadius = 14
	return bl.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.UniformInset(unit.Dp(7)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			lbl := a.ui.Label(unit.Sp(13), label)
			lbl.Color = fg
			return lbl.Layout(gtx)
		})
	})
}
