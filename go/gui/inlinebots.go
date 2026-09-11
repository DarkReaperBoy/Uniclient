package gui

// inlinebots.go — slice 128: inline bot results (AyuGram/tdesktop parity row
// §4 119, CORE-ONLY until now). Typing "@bot query" in the composer queries
// the bot live (messages.getInlineBotResults via engine.GetInlineBotResults
// Full) and shows the results in a panel above the composer:
//
//   - gallery results (photos) as a square thumb grid (b64 stripped thumbs —
//     the core fills them for BotInlineMediaResult);
//   - article/other results as title+description rows; URL-only thumbs
//     (plain BotInlineResult) render text-only — this build has no HTTP
//     image fetcher, and a missing thumbnail is honest (§1.10);
//   - switch_pm becomes a row that opens the bot's chat;
//   - next_offset becomes a "More" row that appends the next page.
//
// Tapping a result sends it (engine.SendInlineBotResult) and clears the
// composer query — tdesktop behavior. The panel derives from the live
// composer text per frame (emoji-autocomplete pattern): it appears only
// while an "@bot " query is active and hides the moment the text changes
// shape; fetches are guarded by key + in-flight flag + 400ms throttle.

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

// ── query parsing (pure) ───────────────────────────────────────────────────

// inlineBotQuery parses an inline-bot query from the composer text:
// "@<bot> <query>" with the @token at the START of the message (tdesktop
// semantics) and terminated by a space (still-typed usernames never
// trigger). The query may be empty — bots return default results then.
func inlineBotQuery(text string) (bot, query string, ok bool) {
	if !strings.HasPrefix(text, "@") {
		return "", "", false
	}
	rest := text[1:]
	sp := strings.IndexByte(rest, ' ')
	if sp < 0 {
		return "", "", false // not terminated yet
	}
	bot = rest[:sp]
	if !validBotUsername(bot) {
		return "", "", false
	}
	return bot, rest[sp+1:], true
}

// validBotUsername checks the username shape: 3-32 chars, letters digits
// underscore (3 = the official short bots — @gif, @pic, @wiki — Telegram
// reserves those below the regular 5-char minimum).
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

// inlineFetchKey guards one live fetch (account + bot + query).
func inlineFetchKey(account, bot, query string) string {
	return account + "|" + bot + "|" + query
}

// inlineResultThumbWidget renders one result's thumbnail through the
// b64 route (stripped bytes, no network) or the URL route (engine HTTP
// fetcher, slice 130). Empty box when neither exists (honest §1.10).
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

// inlineResultSubtitle is the row's second line (description, trimmed).
func inlineResultSubtitle(r cores.InlineBotResult) string {
	return strings.TrimSpace(r.Description)
}

// inlinePanelModel is the shaped view of one inline-bot response.
type inlinePanelModel struct {
	QueryID  int64
	Gallery  bool
	Results  []cores.InlineBotResult
	SwitchPM string
	NextOff  string
}

// newInlinePanelModel shapes a response for rendering (nil when empty).
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

// inlineMoreAvailable reports whether the "More" row should render.
func inlineMoreAvailable(res *cores.InlineBotResults) bool {
	return res != nil && res.NextOffset != "" && len(res.Results) > 0
}

// ── fetch flow ─────────────────────────────────────────────────────────────

// inlineFetchThrottle bounds query refreshes while typing.
const inlineFetchThrottle = 400 * time.Millisecond

// ensureInlineResults derives the composer's inline query and keeps the
// results fresh: resolve the bot username once (cached), fetch on key
// change with an in-flight guard + throttle, append on offset change.
// Throttled calls re-arm a frame at the throttle deadline so the final
// query still fetches when typing stops mid-window.
func (a *App) ensureInlineResults(gtx layout.Context, f frame) {
	bot, query, ok := inlineBotQuery(composer.Text())
	if !ok || f.selected == nil {
		a.clearInlineResults()
		return
	}
	acc, chat := f.selected.AccountID, f.selected.ChatID
	key := inlineFetchKey(acc, bot, query)

	a.mu.Lock()
	busy := a.inlineBusy
	same := a.inlineForKey == key // offset is "More" state, not a refetch trigger
	lastAsk := a.inlineLastAsk
	botID := a.inlineBotIDs[bot]
	a.mu.Unlock()
	if same || busy {
		return
	}
	if time.Since(lastAsk) < inlineFetchThrottle {
		// Re-arm: without a scheduled frame the last query would never
		// fetch when typing stops inside the throttle window.
		gtx.Execute(op.InvalidateCmd{At: lastAsk.Add(inlineFetchThrottle + 20*time.Millisecond)})
		return
	}

	a.mu.Lock()
	a.inlineBusy = true
	a.inlineLastAsk = time.Now()
	a.inlineForKey = key // claim: in-flight results land only if the key still matches
	a.inlineRes = nil    // previous query's results stop rendering while fetching
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
		if a.inlineForKey != key { // query moved on mid-flight: drop
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

// ensureInlineMore appends the next page when the "More" row is tapped.
func (a *App) ensureInlineMore(f frame) {
	bot, query, ok := inlineBotQuery(composer.Text())
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

// clearInlineResults resets the panel state (query stopped matching).
func (a *App) clearInlineResults() {
	a.mu.Lock()
	if a.inlineRes != nil || a.inlineForKey != "" || a.inlineForOffset != "" {
		a.inlineRes = nil
		a.inlineForKey = ""
		a.inlineForOffset = ""
	}
	a.mu.Unlock()
}

// sendInlineResult sends one tapped result and clears the composer query.
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
	composer.SetText("")
	a.clearInlineResults()
	a.invalidate()
}

// ── panel ──────────────────────────────────────────────────────────────────

var (
	inlineGridBtns []widget.Clickable
	inlineRowBtns  []widget.Clickable
	inlineMoreBtn  widget.Clickable
	inlinePMBtn    widget.Clickable
	inlineList     widget.List
)

func init() {
	inlineList.Axis = layout.Vertical
}

// layoutInlineResults renders the results panel above the composer. The
// panel derives from the live composer text: no query, no panel.
func (a *App) layoutInlineResults(gtx layout.Context, f frame) layout.Dimensions {
	_, _, ok := inlineBotQuery(composer.Text())
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

	// Interactions.
	growClickables(&inlineRowBtns, len(m.Results)+boolToIntGUI(m.SwitchPM != "")+boolToIntGUI(inlineMoreAvailable(res)))
	growClickables(&inlineGridBtns, len(m.Results))
	rowIdx := 0
	if m.SwitchPM != "" {
		if inlinePMBtn.Clicked(gtx) {
			a.openBotChatByUsername(f, m.SwitchPM)
			return layout.Dimensions{}
		}
	}
	for i := range m.Results {
		r := m.Results[i]
		if m.Gallery {
			if inlineGridBtns[i].Clicked(gtx) {
				a.sendInlineResult(f, m, r)
				return layout.Dimensions{}
			}
		} else {
			if inlineRowBtns[rowIdx].Clicked(gtx) {
				a.sendInlineResult(f, m, r)
				return layout.Dimensions{}
			}
			rowIdx++
		}
	}
	if inlineMoreAvailable(res) && inlineMoreBtn.Clicked(gtx) {
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
				list := material.List(a.ui.Theme, &inlineList)
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

// boolToIntGUI is the gui-local bool→int (engine has one; kept local to
// avoid an engine import cycle).
func boolToIntGUI(b bool) int {
	if b {
		return 1
	}
	return 0
}

// galleryRows counts grid rows (4 cells per row).
func galleryRows(m *inlinePanelModel) int {
	return (len(m.Results) + 3) / 4
}

// inlineGalleryRow lays out one 4-wide grid row of square thumb cells.
func (a *App) inlineGalleryRow(gtx layout.Context, m *inlinePanelModel, row int) layout.Dimensions {
	cells := make([]layout.FlexChild, 0, 4)
	for c := 0; c < 4; c++ {
		i := row*4 + c
		if i >= len(m.Results) {
			break
		}
		r := m.Results[i]
		cl := &inlineGridBtns[i]
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
					// Honest placeholder: an empty square keeps the grid shape.
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

// inlineListRows lays out the non-gallery rows: results, switch_pm, More.
func (a *App) inlineListRows(gtx layout.Context, f frame, m *inlinePanelModel, res *cores.InlineBotResults) layout.Dimensions {
	var children []layout.FlexChild
	rowIdx := 0
	for i := range m.Results {
		r := m.Results[i]
		cl := &inlineRowBtns[rowIdx]
		rowIdx++
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.inlineResultRow(gtx, cl, r)
		}))
	}
	if m.SwitchPM != "" {
		cl := &inlinePMBtn
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
				btn := material.Button(a.ui.Theme, &inlineMoreBtn, "More results")
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

// inlineResultRow is one article-style row: thumb (when b64) + title +
// description.
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

// openBotChatByUsername opens the bot's chat for a switch_pm row: global
// search by username, then openChat (async; honest toast on miss).
func (a *App) openBotChatByUsername(f frame, label string) {
	_ = label // switch-pm text is display-only here; navigation uses the bot username
	if f.selected == nil {
		return
	}
	acc := f.selected.AccountID
	// The label is the bot's switch-pm text; the bot username comes from
	// the composer query itself.
	bot, _, ok := inlineBotQuery(composer.Text())
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
