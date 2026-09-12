package gui

// Sponsored messages (Telegram channels + bots, slice 163): the GUI over
// the engine's sponsored surface — the ad block below the last post of
// broadcast channels, the top bar above bot-chat messages (tdesktop
// history_view_top_controls FillSponsoredMessageBar), view/click
// reporting, the iterative ad-report flow, and the about-ads box.
//
// tdesktop behavior mirrored here:
//   - the whole ad is a click target → URL opens in the browser
//     (deep-linkable t.me URLs route in-app) + messages.clickSponsoredMessage
//   - messages.viewSponsoredMessage fires once per 5-minute cache window
//     when the ad actually lays out
//   - "Report ad" walks the choose-option chain; "About ads" opens the
//     promote.telegram.org box
//   - Recommended ads carry a badge; the sponsor photo renders as the
//     avatar bubble; media ads render the poster (video with a play glyph)

import (
	"image"
	"log"
	"strings"

	"gioui.org/io/event"
	"gioui.org/io/key"
	"gioui.org/layout"
	"gioui.org/op/clip"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/cores"
	"uniclient/engine"
)

// sponsoredDlgState: the open sponsored dialog — either the iterative
// ad-report chain (randomID set) or the about-ads box (about=true).
type sponsoredDlgState struct {
	about    bool
	randomID string
	account  string
	chat     string
	title    string
	options  []cores.SponsoredReportOption
	busy     bool
}

var (
	sponsoredAdClicks   []widget.Clickable // per-ad card clicks
	sponsoredBarClick   widget.Clickable   // bot-bar whole-bar click
	sponsoredReportBtn  widget.Clickable   // row "Report" link
	sponsoredAboutBtn   widget.Clickable   // row "About" link
	sponsoredDlgCancel  widget.Clickable
	sponsoredDlgPromote widget.Clickable
	sponsoredOptBtns    []widget.Clickable
	sponsoredDlgKeyTag  = new(struct{})
)

// appendSponsoredRows appends the sponsored block rows (caption + one row
// per ad) after the message rows of a broadcast channel — the wire
// contract's "below all other posts" placement. Bots don't get rows (the
// top bar renders their ad instead); forums/topic views don't either.
func appendSponsoredRows(rows []chatRow, chat *engine.ChatInfo, forumTopic string, sponsored []cores.SponsoredMessageInfo) []chatRow {
	if chat == nil || chat.Type != engine.ChatTypeChanVal || forumTopic != "" || len(sponsored) == 0 {
		return rows
	}
	rows = append(rows, chatRow{msgIdx: -1, spHead: true})
	for i := range sponsored {
		rows = append(rows, chatRow{msgIdx: -1, spIdx: i + 1})
	}
	return rows
}

// sponsoredEligible: sponsored messages surface in broadcast channels
// (below the last post) and bot chats (top bar) — the wire contract's
// two placements.
func sponsoredEligible(chat *engine.ChatInfo) bool {
	if chat == nil {
		return false
	}
	return chat.Type == engine.ChatTypeChanVal || chat.IsBot
}

// loadSponsored fetches the open chat's sponsored block (engine caches
// 5 minutes per chat) and resets the view-report ledger for the visit.
func (a *App) loadSponsored(k chatKey) {
	go func() {
		var chat *engine.ChatInfo
		a.mu.Lock()
		for i := range a.chats {
			if a.chats[i].AccountID == k.AccountID && a.chats[i].ChatID == k.ChatID {
				c := a.chats[i]
				chat = &c
				break
			}
		}
		a.mu.Unlock()
		if !sponsoredEligible(chat) {
			return
		}
		items, _, err := a.eng.GetSponsoredMessages(k.AccountID, k.ChatID)
		if err != nil {
			if !strings.Contains(err.Error(), "does not support") {
				log.Printf("gui: sponsored: %v", err)
			}
			items = nil
		}
		a.mu.Lock()
		if cur := a.selected; cur != nil && *cur == k {
			a.sponsored = items
			a.sponsoredFor = k.AccountID + "|" + k.ChatID
			a.sponsoredViewed = make(map[string]bool, len(items))
		}
		a.mu.Unlock()
		a.invalidate()
	}()
}

// sponsoredViewOnce reports the ad as viewed at most once per loaded
// window (the engine dedups per cache window too).
func (a *App) sponsoredViewOnce(randomID string) bool {
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.sponsoredViewed == nil {
		a.sponsoredViewed = map[string]bool{}
	}
	if a.sponsoredViewed[randomID] {
		return false
	}
	a.sponsoredViewed[randomID] = true
	return true
}

// sponsoredClick opens the ad's URL (in-app for deep links, browser
// otherwise) and reports the click server-side. media=true when the
// media block was the click target.
func (a *App) sponsoredClick(ad cores.SponsoredMessageInfo, acc, chat string, media bool) {
	a.openLinkExternal(ad.URL)
	go func() {
		if err := a.eng.ClickSponsoredMessage(acc, ad.RandomID, media, false); err != nil {
			log.Printf("gui: sponsored click report: %v", err)
		}
	}()
}

// openSponsoredReport starts the iterative ad-report chain (option ""
// requests the reason list).
func (a *App) openSponsoredReport(ad cores.SponsoredMessageInfo, acc, chat string) {
	a.mu.Lock()
	a.sponsoredDlg = &sponsoredDlgState{randomID: ad.RandomID, account: acc}
	a.mu.Unlock()
	a.invalidate()
	go a.sponsoredReportStep("")
}

// openSponsoredAbout opens the about-ads box (promote.telegram.org).
func (a *App) openSponsoredAbout() {
	a.mu.Lock()
	a.sponsoredDlg = &sponsoredDlgState{about: true}
	a.mu.Unlock()
	a.invalidate()
}

// closeSponsoredDialog dismisses the report/about dialog (blocked while
// a report request is in flight).
func (a *App) closeSponsoredDialog() {
	a.mu.Lock()
	if a.sponsoredDlg == nil || a.sponsoredDlg.busy {
		a.mu.Unlock()
		return
	}
	a.sponsoredDlg = nil
	a.mu.Unlock()
	a.invalidate()
}

// sponsoredReportStep walks one step of the report chain.
func (a *App) sponsoredReportStep(option string) {
	a.mu.Lock()
	d := a.sponsoredDlg
	if d == nil || d.busy {
		a.mu.Unlock()
		return
	}
	d.busy = true
	randomID, acc := d.randomID, d.account
	a.mu.Unlock()

	go func() {
		title, opts, err := a.eng.ReportSponsoredMessage(acc, randomID, option)
		a.mu.Lock()
		d = a.sponsoredDlg
		if d == nil {
			a.mu.Unlock()
			return
		}
		d.busy = false
		if err != nil {
			a.sponsoredDlg = nil
			msg := err.Error()
			a.mu.Unlock()
			a.setToast("Report failed: " + msg)
			return
		}
		if title == "" && len(opts) == 0 {
			a.sponsoredDlg = nil
			a.mu.Unlock()
			a.setToast("Thanks. The ad was reported.")
			return
		}
		d.title, d.options = title, opts
		a.mu.Unlock()
		a.invalidate()
	}()
}

// ── channel placement: rows below the last post ───────────────────────────

// sponsoredHeaderRow: the "Sponsored" caption + the About link that
// opens the about-ads box (tdesktop's section caption).
func (a *App) sponsoredHeaderRow(gtx layout.Context, f frame) layout.Dimensions {
	if sponsoredAboutBtn.Clicked(gtx) {
		a.openSponsoredAbout()
	}
	return layout.Inset{Top: unit.Dp(16), Bottom: unit.Dp(4), Left: unit.Dp(12), Right: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				lbl := a.ui.Dim(unit.Sp(12), "Sponsored")
				lbl.Color = a.ui.p.TextFaint
				return lbl.Layout(gtx)
			}),
			layout.Flexed(1, func(gtx layout.Context) layout.Dimensions { return layout.Dimensions{} }),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				btn := a.ui.TextButton(&sponsoredAboutBtn, "About ads")
				return btn.Layout(gtx)
			}),
		)
	})
}

// sponsoredAdRow renders one sponsored message as a message-like card:
// avatar (sponsor photo or title letter), title + Recommended badge,
// body text, media poster with a play glyph for video ads, and the
// action button — the whole card is the click target.
func (a *App) sponsoredAdRow(gtx layout.Context, f frame, idx1 int) layout.Dimensions {
	if idx1 < 1 || idx1 > len(f.sponsored) {
		return layout.Dimensions{}
	}
	ad := &f.sponsored[idx1-1]
	acc, chat := "", ""
	if f.selected != nil {
		acc, chat = f.selected.AccountID, f.selected.ChatID
	}

	growClickables(&sponsoredAdClicks, idx1)
	btn := &sponsoredAdClicks[idx1-1]
	if btn.Clicked(gtx) {
		a.sponsoredClick(*ad, acc, chat, false)
	}
	// View report: once per loaded window, when the row lays out.
	if a.sponsoredViewOnce(ad.RandomID) && acc != "" {
		go func() {
			if err := a.eng.MarkSponsoredViewed(acc, chat, ad.RandomID); err != nil {
				log.Printf("gui: sponsored view report: %v", err)
			}
		}()
	}

	return layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(4), Left: unit.Dp(12), Right: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		bl := material.ButtonLayout(a.ui.Theme, btn)
		bl.Background = a.ui.p.Surface
		bl.CornerRadius = 12
		return bl.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(10)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				body := func(gtx layout.Context) layout.Dimensions {
					return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Start}.Layout(gtx,
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							return layout.Inset{Right: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								return a.sponsoredAvatar(gtx, ad)
							})
						}),
						layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
							return a.sponsoredBody(gtx, f, ad)
						}),
					)
				}
				if ad.MediaThumbB64 == "" {
					return body(gtx)
				}
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return a.sponsoredPoster(gtx, ad)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(8)}.Layout(gtx, body)
					}),
				)
			})
		})
	})
}

// sponsoredAvatar: the sponsor's custom photo (stripped thumb) or the
// title letter bubble.
func (a *App) sponsoredAvatar(gtx layout.Context, ad *cores.SponsoredMessageInfo) layout.Dimensions {
	if ad.ThumbB64 != "" {
		key := "thumb:" + ad.ThumbB64
		if img := mediaImgs.get(key); img != nil {
			return avatarFromImage(gtx, a, img, unit.Dp(38), dotNone)
		}
		a.decodeThumbAsync(key, ad.ThumbB64)
	}
	return a.ui.Avatar(gtx, ad.Title, unit.Dp(38), dotNone)
}

// sponsoredBody: title row (+Recommended badge + sponsor info), the
// message text, and the action button.
func (a *App) sponsoredBody(gtx layout.Context, f frame, ad *cores.SponsoredMessageInfo) layout.Dimensions {
	return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					lbl := a.ui.Label(unit.Sp(14), ad.Title)
					lbl.Color = a.ui.p.Text
					return lbl.Layout(gtx)
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					if !ad.Recommended {
						return layout.Dimensions{}
					}
					return layout.Inset{Left: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						return roundedFill(gtx, a.ui.p.AccentDim, 8, func(gtx layout.Context) layout.Dimensions {
							return layout.Inset{Top: unit.Dp(2), Bottom: unit.Dp(2), Left: unit.Dp(6), Right: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Dim(unit.Sp(10), "Recommended")
								lbl.Color = a.ui.p.Accent
								return lbl.Layout(gtx)
							})
						})
					})
				}),
			)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			if ad.SponsorInfo != "" || ad.AdditionalInfo != "" {
				return layout.Inset{Top: unit.Dp(1)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					sub := ad.SponsorInfo
					if sub == "" {
						sub = ad.AdditionalInfo
					}
					lbl := a.ui.Dim(unit.Sp(11), sub)
					lbl.Color = a.ui.p.TextDim
					return lbl.Layout(gtx)
				})
			}
			return layout.Dimensions{}
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			if strings.TrimSpace(ad.Message) == "" {
				return layout.Dimensions{}
			}
			return layout.Inset{Top: unit.Dp(3)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				lbl := a.ui.Label(unit.Sp(14), ad.Message)
				lbl.Color = a.ui.p.Text
				return lbl.Layout(gtx)
			})
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			if ad.ButtonText == "" {
				return layout.Dimensions{}
			}
			return layout.Inset{Top: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return roundedFill(gtx, a.ui.p.AccentDim, 8, func(gtx layout.Context) layout.Dimensions {
					return layout.Inset{Top: unit.Dp(5), Bottom: unit.Dp(5), Left: unit.Dp(12), Right: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.Dim(unit.Sp(12), ad.ButtonText)
						lbl.Color = a.ui.p.Accent
						return lbl.Layout(gtx)
					})
				})
			})
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			if !ad.CanReport {
				return layout.Dimensions{}
			}
			if sponsoredReportBtn.Clicked(gtx) {
				acc, chat := "", ""
				if f.selected != nil {
					acc, chat = f.selected.AccountID, f.selected.ChatID
				}
				a.openSponsoredReport(*ad, acc, chat)
			}
			return layout.Inset{Top: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				btn := a.ui.TextButton(&sponsoredReportBtn, "Report ad")
				return btn.Layout(gtx)
			})
		}),
	)
}

// sponsoredPoster: the media attachment poster (photo, or video with a
// play glyph — in-app decode of video is constitution-blocked, so video
// renders as poster + play, like every other video surface).
func (a *App) sponsoredPoster(gtx layout.Context, ad *cores.SponsoredMessageInfo) layout.Dimensions {
	key := "thumb:" + ad.MediaThumbB64
	img := mediaImgs.get(key)
	play := gtx.Dp(unit.Dp(44))
	if img == nil {
		a.decodeThumbAsync(key, ad.MediaThumbB64)
		w, h := gtx.Dp(unit.Dp(280)), gtx.Dp(unit.Dp(120))
		return layout.Stack{Alignment: layout.Center}.Layout(gtx,
			layout.Stacked(func(gtx layout.Context) layout.Dimensions {
				return roundedFill(gtx, a.ui.p.Divider, 10, func(gtx layout.Context) layout.Dimensions {
					gtx.Constraints = layout.Constraints{Min: image.Pt(w, h), Max: image.Pt(w, h)}
					return layout.Dimensions{Size: image.Pt(w, h)}
				})
			}),
			layout.Stacked(func(gtx layout.Context) layout.Dimensions {
				if !ad.MediaIsVideo {
					return layout.Dimensions{}
				}
				return drawPlayBadge(gtx, play)
			}),
		)
	}
	w, h := gtx.Dp(unit.Dp(280)), gtx.Dp(unit.Dp(160))
	return layout.Stack{Alignment: layout.Center}.Layout(gtx,
		layout.Stacked(func(gtx layout.Context) layout.Dimensions {
			return drawImageScaled(gtx, img, w, h, 10)
		}),
		layout.Stacked(func(gtx layout.Context) layout.Dimensions {
			if !ad.MediaIsVideo {
				return layout.Dimensions{}
			}
			return drawPlayBadge(gtx, play)
		}),
	)
}

// ── bot placement: the top bar ────────────────────────────────────────────

// layoutSponsoredBar: the bot-chat sponsored bar (tdesktop
// FillSponsoredMessageBar): "Sponsored" badge + title + one-line message
// + the action button; the whole bar is the click target.
func (a *App) layoutSponsoredBar(gtx layout.Context, f frame) layout.Dimensions {
	if len(f.sponsored) == 0 {
		return layout.Dimensions{}
	}
	ad := &f.sponsored[0]
	acc, chat := "", ""
	if f.selected != nil {
		acc, chat = f.selected.AccountID, f.selected.ChatID
	}

	if sponsoredBarClick.Clicked(gtx) {
		a.sponsoredClick(*ad, acc, chat, false)
	}
	if a.sponsoredViewOnce(ad.RandomID) && acc != "" {
		go func() {
			if err := a.eng.MarkSponsoredViewed(acc, chat, ad.RandomID); err != nil {
				log.Printf("gui: sponsored view report: %v", err)
			}
		}()
	}

	return layout.Inset{Left: unit.Dp(12), Right: unit.Dp(12), Top: unit.Dp(6), Bottom: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		bl := material.ButtonLayout(a.ui.Theme, &sponsoredBarClick)
		bl.Background = a.ui.p.Surface
		bl.CornerRadius = 10
		return bl.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(8)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return roundedFill(gtx, a.ui.p.AccentDim, 8, func(gtx layout.Context) layout.Dimensions {
							return layout.Inset{Top: unit.Dp(2), Bottom: unit.Dp(2), Left: unit.Dp(8), Right: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Dim(unit.Sp(10), "Sponsored")
								lbl.Color = a.ui.p.Accent
								return lbl.Layout(gtx)
							})
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Left: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Label(unit.Sp(13), ad.Title)
							lbl.Color = a.ui.p.Text
							return lbl.Layout(gtx)
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if strings.TrimSpace(ad.Message) == "" {
							return layout.Dimensions{}
						}
						return layout.Inset{Left: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							gtx.Constraints.Max.X = gtx.Dp(unit.Dp(220))
							lbl := a.ui.Dim(unit.Sp(13), ad.Message)
							lbl.Color = a.ui.p.TextDim
							return lbl.Layout(gtx)
						})
					}),
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions { return layout.Dimensions{} }),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if ad.ButtonText == "" {
							return layout.Dimensions{}
						}
						return roundedFill(gtx, a.ui.p.AccentDim, 8, func(gtx layout.Context) layout.Dimensions {
							return layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(4), Left: unit.Dp(10), Right: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Dim(unit.Sp(11), ad.ButtonText)
								lbl.Color = a.ui.p.Accent
								return lbl.Layout(gtx)
							})
						})
					}),
				)
			})
		})
	})
}

// ── dialogs ───────────────────────────────────────────────────────────────

// layoutSponsoredDialog renders the report chain or the about-ads card.
func (a *App) layoutSponsoredDialog(gtx layout.Context, f frame) layout.Dimensions {
	d := f.sponsoredDlg
	{
		stack := clip.Rect{Max: image.Pt(gtx.Constraints.Max.X, gtx.Constraints.Max.Y)}.Push(gtx.Ops)
		event.Op(gtx.Ops, sponsoredDlgKeyTag)
		stack.Pop()
	}
	for {
		ev, ok := gtx.Source.Event(key.Filter{Name: key.NameEscape})
		if !ok {
			break
		}
		if ke, is := ev.(key.Event); is && ke.State == key.Press {
			a.closeSponsoredDialog()
		}
	}
	if sponsoredDlgCancel.Clicked(gtx) {
		a.closeSponsoredDialog()
	}
	if sponsoredDlgPromote.Clicked(gtx) {
		a.openLinkExternal("https://promote.telegram.org")
	}

	growClickables(&sponsoredOptBtns, len(d.options))
	for i := range d.options {
		if sponsoredOptBtns[i].Clicked(gtx) {
			opt := d.options[i].Option
			go a.sponsoredReportStep(opt)
			break
		}
	}

	paintScrimRect(gtx)

	title := d.title
	if d.about {
		title = "About ads"
	}
	return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		gtx.Constraints.Max.X = gtx.Dp(unit.Dp(340))
		if gtx.Constraints.Max.Y > gtx.Dp(unit.Dp(400)) {
			gtx.Constraints.Max.Y = gtx.Dp(unit.Dp(400))
		}
		return roundedFill(gtx, a.ui.p.Surface, 12, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(16)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.H3(title)
						return lbl.Layout(gtx)
					}),
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						return a.sponsoredDialogBody(gtx, f, d)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							btn := a.ui.TextButton(&sponsoredDlgCancel, "Close")
							if d.busy {
								btn.Color = a.ui.p.TextFaint
							}
							return btn.Layout(gtx)
						})
					}),
				)
			})
		})
	})
}

func (a *App) sponsoredDialogBody(gtx layout.Context, f frame, d *sponsoredDlgState) layout.Dimensions {
	if d.about {
		return layout.Inset{Top: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					lbl := a.ui.Label(unit.Sp(13), "Sponsored messages are paid promotions shown in large public channels and bot chats. They keep Telegram free while respecting your data: no message content is analyzed to target them.")
					lbl.Color = a.ui.p.Text
					return lbl.Layout(gtx)
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return layout.Inset{Top: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						btn := a.ui.PrimaryButton(&sponsoredDlgPromote, "promote.telegram.org")
						return btn.Layout(gtx)
					})
				}),
			)
		})
	}
	if d.busy || len(d.options) == 0 {
		return layout.Inset{Top: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			lbl := a.ui.Dim(unit.Sp(13), "Asking Telegram for the reasons…")
			lbl.Color = a.ui.p.TextDim
			return lbl.Layout(gtx)
		})
	}
	return layout.Inset{Top: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		var children []layout.FlexChild
		if d.title != "" {
			children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				lbl := a.ui.Dim(unit.Sp(12), d.title)
				lbl.Color = a.ui.p.TextDim
				return lbl.Layout(gtx)
			}))
		}
		for i := range d.options {
			i := i
			children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Top: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return roundedFill(gtx, a.ui.p.Background, 8, func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(8), Bottom: unit.Dp(8), Left: unit.Dp(12), Right: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Label(unit.Sp(14), d.options[i].Text)
							lbl.Color = a.ui.p.Text
							return lbl.Layout(gtx)
						})
					})
				})
			}))
		}
		return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
	})
}
