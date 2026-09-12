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
	)
}

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
