package gui

import (
	"image"
	"log"
	"strings"
	"time"

	"gioui.org/layout"
	"gioui.org/op"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/cores"
)

func inlineBotQuery(text string) (bot, query string, ok bool) {
	if !strings.HasPrefix(text, "@") {
		return "", "", false
	}
	rest := text[1:]
	sp := strings.IndexByte(rest, ' ')
	if sp < 0 {
		return "", "", false
	}
	bot = rest[:sp]
	if !validBotUsername(bot) {
		return "", "", false
	}
	return bot, rest[sp+1:], true
}

func validBotUsername(u string) bool {
	if len(u) < 3 || len(u) > 32 {
		return false
	}
	for _, r := range u {
		switch {
		case r >= 'a' && r <= 'z', r >= 'A' && r <= 'Z', r >= '0' && r <= '9', r == '_':
		default:
			return false
		}
	}
	return true
}

func inlineFetchKey(account, bot, query string) string {
	return account + "|" + bot + "|" + query
}

func (a *App) inlineResultThumbWidget(gtx layout.Context, r cores.InlineBotResult, sizeDp unit.Dp) layout.Dimensions {
	src, url := inlineThumbSource(r)
	switch src {
	case thumbSrcB64:
		return a.mediaThumb(gtx, r.ThumbB64, sizeDp)
	case thumbSrcURL:
		return a.urlThumb(gtx, url, sizeDp)
	}
	return layout.Dimensions{}
}

func inlineResultSubtitle(r cores.InlineBotResult) string {
	return strings.TrimSpace(r.Description)
}

type inlinePanelModel struct {
	QueryID  int64
	Gallery  bool
	Results  []cores.InlineBotResult
	SwitchPM string
	NextOff  string
}

func newInlinePanelModel(res *cores.InlineBotResults) *inlinePanelModel {
	if res == nil || len(res.Results) == 0 {
		return nil
	}
	return &inlinePanelModel{
		QueryID:  res.QueryID,
		Gallery:  res.Gallery,
		Results:  res.Results,
		SwitchPM: strings.TrimSpace(res.SwitchPM),
		NextOff:  res.NextOffset,
	}
}

func inlineMoreAvailable(res *cores.InlineBotResults) bool {
	return res != nil && res.NextOffset != "" && len(res.Results) > 0
}

const inlineFetchThrottle = 400 * time.Millisecond

func (a *App) ensureInlineResults(gtx layout.Context, f frame) {
	bot, query, ok := inlineBotQuery(a.wid.composer.Text())
	if !ok || f.selected == nil {
		a.clearInlineResults()
		return
	}
	acc, chat := f.selected.AccountID, f.selected.ChatID
	key := inlineFetchKey(acc, bot, query)

	a.mu.Lock()
	busy := a.inlineBusy
	same := a.inlineForKey == key
	lastAsk := a.inlineLastAsk
	botID := a.inlineBotIDs[bot]
	a.mu.Unlock()
	if same || busy {
		return
	}
	if time.Since(lastAsk) < inlineFetchThrottle {
		gtx.Execute(op.InvalidateCmd{At: lastAsk.Add(inlineFetchThrottle + 20*time.Millisecond)})
		return
	}

	a.mu.Lock()
	a.inlineBusy = true
	a.inlineLastAsk = time.Now()
	a.inlineForKey = key
	a.inlineRes = nil
	a.mu.Unlock()

	go func() {
		defer func() {
			a.mu.Lock()
			a.inlineBusy = false
			a.mu.Unlock()
			a.invalidate()
		}()
		if botID == "" {
			id, err := a.eng.ResolveUsername(acc, bot)
			if err != nil {
				log.Printf("gui: inline bot resolve @%s: %v", bot, err)
				return
			}
			botID = id
			a.mu.Lock()
			if a.inlineBotIDs == nil {
				a.inlineBotIDs = make(map[string]string)
			}
			a.inlineBotIDs[bot] = botID
			a.mu.Unlock()
		}
		res, err := a.eng.GetInlineBotResultsFull(acc, botID, query, "", chat)
		a.mu.Lock()
		if a.inlineForKey != key {
			a.mu.Unlock()
			return
		}
		if err != nil {
			a.inlineRes = nil
			a.mu.Unlock()
			return
		}
		a.inlineRes = res
		a.inlineForOffset = res.NextOffset
		a.mu.Unlock()
		a.invalidate()
	}()
}

func (a *App) ensureInlineMore(f frame) {
	bot, query, ok := inlineBotQuery(a.wid.composer.Text())
	if !ok || f.selected == nil {
		return
	}
	acc, chat := f.selected.AccountID, f.selected.ChatID
	key := inlineFetchKey(acc, bot, query)

	a.mu.Lock()
	busy := a.inlineBusy
	cur := a.inlineRes
	offset := a.inlineForOffset
	botID := a.inlineBotIDs[bot]
	a.mu.Unlock()
	if busy || cur == nil || offset == "" || botID == "" {
		return
	}

	a.mu.Lock()
	a.inlineBusy = true
	a.mu.Unlock()
	go func() {
		defer func() {
			a.mu.Lock()
			a.inlineBusy = false
			a.mu.Unlock()
			a.invalidate()
		}()
		res, err := a.eng.GetInlineBotResultsFull(acc, botID, query, offset, chat)
		a.mu.Lock()
		defer a.mu.Unlock()
		if err != nil || a.inlineForKey != key || a.inlineRes == nil {
			return
		}
		a.inlineRes.Results = append(a.inlineRes.Results, res.Results...)
		a.inlineForOffset = res.NextOffset
		a.invalidate()
	}()
}

func (a *App) clearInlineResults() {
	a.mu.Lock()
	if a.inlineRes != nil || a.inlineForKey != "" || a.inlineForOffset != "" {
		a.inlineRes = nil
		a.inlineForKey = ""
		a.inlineForOffset = ""
	}
	a.mu.Unlock()
}

func (a *App) sendInlineResult(f frame, m *inlinePanelModel, r cores.InlineBotResult) {
	if f.selected == nil || m == nil {
		return
	}
	acc, chat := f.selected.AccountID, f.selected.ChatID
	qid, rid := m.QueryID, r.ID
	go func() {
		if _, err := a.eng.SendInlineBotResult(acc, chat, qid, rid); err != nil {
			a.setToast("Send failed: " + err.Error())
			return
		}
	}()
	a.wid.composer.SetText("")
	a.clearInlineResults()
	a.invalidate()
}

func (a *App) layoutInlineResults(gtx layout.Context, f frame) layout.Dimensions {
	_, _, ok := inlineBotQuery(a.wid.composer.Text())
	if !ok {
		return layout.Dimensions{}
	}
	a.ensureInlineResults(gtx, f)

	a.mu.Lock()
	res := a.inlineRes
	a.mu.Unlock()
	m := newInlinePanelModel(res)
	if m == nil {
		return layout.Dimensions{}
	}

	growClickables(&a.wid.inlineRowBtns, len(m.Results)+boolToIntGUI(m.SwitchPM != "")+boolToIntGUI(inlineMoreAvailable(res)))
	growClickables(&a.wid.inlineGridBtns, len(m.Results))
	rowIdx := 0
	if m.SwitchPM != "" {
		if a.wid.inlinePMBtn.Clicked(gtx) {
			a.openBotChatByUsername(f, m.SwitchPM)
			return layout.Dimensions{}
		}
	}
	for i := range m.Results {
		r := m.Results[i]
		if m.Gallery {
			if a.wid.inlineGridBtns[i].Clicked(gtx) {
				a.sendInlineResult(f, m, r)
				return layout.Dimensions{}
			}
		} else {
			if a.wid.inlineRowBtns[rowIdx].Clicked(gtx) {
				a.sendInlineResult(f, m, r)
				return layout.Dimensions{}
			}
			rowIdx++
		}
	}
	if inlineMoreAvailable(res) && a.wid.inlineMoreBtn.Clicked(gtx) {
		a.ensureInlineMore(f)
		return layout.Dimensions{}
	}

	maxH := gtx.Dp(unit.Dp(280))
	if maxH > gtx.Constraints.Max.Y/2 {
		maxH = gtx.Constraints.Max.Y / 2
	}
	gtx.Constraints.Max.Y = maxH
	return layout.Inset{Left: unit.Dp(12), Right: unit.Dp(12), Bottom: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return roundedFill(gtx, a.ui.p.Surface, 12, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(6)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				list := material.List(a.ui.Theme, &a.wid.inlineList)
				if m.Gallery {
					return list.Layout(gtx, galleryRows(m), func(gtx layout.Context, row int) layout.Dimensions {
						return a.inlineGalleryRow(gtx, m, row)
					})
				}
				return list.Layout(gtx, 1, func(gtx layout.Context, _ int) layout.Dimensions {
					return a.inlineListRows(gtx, f, m, res)
				})
			})
		})
	})
}

func boolToIntGUI(b bool) int {
	if b {
		return 1
	}
	return 0
}

func galleryRows(m *inlinePanelModel) int {
	return (len(m.Results) + 3) / 4
}

func (a *App) inlineGalleryRow(gtx layout.Context, m *inlinePanelModel, row int) layout.Dimensions {
	cells := make([]layout.FlexChild, 0, 4)
	for c := 0; c < 4; c++ {
		i := row*4 + c
		if i >= len(m.Results) {
			break
		}
		r := m.Results[i]
		cl := &a.wid.inlineGridBtns[i]
		cells = append(cells, layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(2)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				side := gtx.Constraints.Max.X
				if side > gtx.Dp(unit.Dp(96)) {
					side = gtx.Dp(unit.Dp(96))
				}
				gtx.Constraints.Max.X = side
				gtx.Constraints.Max.Y = side
				btn := material.ButtonLayout(a.ui.Theme, cl)
				btn.CornerRadius = 8
				return btn.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					d := a.inlineResultThumbWidget(gtx, r, unit.Dp(96))
					if d.Size == (image.Point{}) {
						d = layout.Dimensions{Size: image.Pt(side, side)}
					}
					return d
				})
			})
		}))
	}
	return layout.Flex{Axis: layout.Horizontal}.Layout(gtx, cells...)
}

func (a *App) inlineListRows(gtx layout.Context, f frame, m *inlinePanelModel, res *cores.InlineBotResults) layout.Dimensions {
	var children []layout.FlexChild
	rowIdx := 0
	for i := range m.Results {
		r := m.Results[i]
		cl := &a.wid.inlineRowBtns[rowIdx]
		rowIdx++
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.inlineResultRow(gtx, cl, r)
		}))
	}
	if m.SwitchPM != "" {
		cl := &a.wid.inlinePMBtn
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(2)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				btn := material.Button(a.ui.Theme, cl, m.SwitchPM)
				btn.CornerRadius = 8
				btn.Inset = layout.UniformInset(unit.Dp(8))
				btn.TextSize = unit.Sp(13)
				btn.Background = a.ui.p.AccentDim
				return btn.Layout(gtx)
			})
		}))
	}
	if inlineMoreAvailable(res) {
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(2)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				btn := material.Button(a.ui.Theme, &a.wid.inlineMoreBtn, "More results")
				btn.CornerRadius = 8
				btn.Inset = layout.UniformInset(unit.Dp(8))
				btn.TextSize = unit.Sp(13)
				btn.Background = a.ui.p.SurfaceHi
				btn.Color = a.ui.p.Accent
				return btn.Layout(gtx)
			})
		}))
	}
	return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
}

func (a *App) inlineResultRow(gtx layout.Context, cl *widget.Clickable, r cores.InlineBotResult) layout.Dimensions {
	return material.ButtonLayout(a.ui.Theme, cl).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.UniformInset(unit.Dp(6)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return a.inlineResultThumbWidget(gtx, r, unit.Dp(40))
				}),
				layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
					return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Label(unit.Sp(14), r.Title)
							return lbl.Layout(gtx)
						}),
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							if s := inlineResultSubtitle(r); s != "" {
								lbl := a.ui.Dim(unit.Sp(12), s)
								lbl.MaxLines = 1
								return lbl.Layout(gtx)
							}
							return layout.Dimensions{}
						}),
					)
				}),
			)
		})
	})
}

func (a *App) openBotChatByUsername(f frame, label string) {
	_ = label
	if f.selected == nil {
		return
	}
	acc := f.selected.AccountID
	bot, _, ok := inlineBotQuery(a.wid.composer.Text())
	if !ok {
		return
	}
	go func() {
		hits, err := a.eng.SearchGlobalChats(acc, bot, 3)
		if err != nil || len(hits) == 0 {
			a.setToast("Bot not found: @" + bot)
			return
		}
		c := hits[0]
		a.mu.Lock()
		a.pendingOpen = &chatKey{AccountID: c.AccountID, ChatID: c.ChatID}
		a.pendingTitle = c.Title
		a.mu.Unlock()
		a.invalidate()
	}()
}
