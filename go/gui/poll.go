package gui

import (
	"bytes"
	"encoding/json"
	"image"
	"image/color"
	"sort"
	"strings"

	"gioui.org/f32"
	"gioui.org/font"
	"gioui.org/io/event"
	"gioui.org/io/key"
	"gioui.org/layout"
	"gioui.org/op"
	"gioui.org/op/clip"
	"gioui.org/op/paint"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/engine"
)

// Polls (AyuGram parity §4 "Attach menu: Poll" + poll results): the attach
// menu gains a Poll entry that opens a creation dialog (question, options,
// anonymous/multiple/quiz toggles) wired to engine CreatePollEx; received
// polls render as an interactive bubble — question, tappable options, vote
// bars with percentages once voted, quiz correct/wrong reveal + solution
// line, and a vote-count footer. Telegram vote semantics (slice 124):
// single polls vote once and tap-own-choice retracts; multiple polls
// toggle options with the full set on the wire (VotePollMulti); quizzes
// lock after the answer; the creator can Stop poll from the context menu.
// Optimistic overlays mirror server truth (UpdateMessagePoll merges
// counts into the cache).

// ── model ──────────────────────────────────────────────────────────────────

// pollOption is one answer row of a poll.
type pollOption struct {
	Text    string
	Voters  int
	Chosen  bool // voted by me (server data)
	Correct bool // quiz: this is the right answer
}

// pollData is the parsed poll carried by a message Extra (content_raw).
type pollData struct {
	Question    string
	Options     []pollOption
	TotalVoters int
	Multiple    bool
	Quiz        bool
	Closed      bool
	Public      bool
	Solution    string // quiz explanation, shown after voting
}

// rawEnvelope decodes just the Extra map of a marshaled cores.Message.
type rawEnvelope struct {
	Extra map[string]interface{} `json:"extra"`
}

// extraNum pulls a JSON number out of a decoded interface{} value.
func extraNum(v interface{}) (float64, bool) {
	f, ok := v.(float64)
	return f, ok
}

// strVal coerces a decoded JSON value to string ("" when absent).
func strVal(v interface{}) string {
	s, _ := v.(string)
	return s
}

// parsePollMessage extracts poll data from a cached message's raw JSON
// (cores.Message.Extra["poll_*"], written by the telegram core's
// MessageMediaPoll conversion). nil when the message is not a usable poll.
func parsePollMessage(m *engine.CachedMessage) *pollData {
	if m == nil || len(m.ContentRaw) == 0 {
		return nil
	}
	// Cheap pre-check before the full unmarshal (runs per row per frame).
	if !bytes.Contains(m.ContentRaw, []byte(`"poll_question"`)) {
		return nil
	}
	var env rawEnvelope
	if err := json.Unmarshal(m.ContentRaw, &env); err != nil {
		return nil
	}
	if env.Extra == nil {
		return nil
	}
	q, _ := env.Extra["poll_question"].(string)
	if strings.TrimSpace(q) == "" {
		return nil
	}
	d := &pollData{Question: q}
	d.Quiz, _ = env.Extra["poll_quiz"].(bool)
	d.Multiple, _ = env.Extra["poll_multiple"].(bool)
	d.Closed, _ = env.Extra["poll_closed"].(bool)
	d.Public, _ = env.Extra["poll_public"].(bool)
	d.Solution = strVal(env.Extra["poll_solution"])
	if tv, ok := extraNum(env.Extra["poll_total_voters"]); ok {
		d.TotalVoters = int(tv)
	}
	if rawOpts, ok := env.Extra["poll_options"].([]interface{}); ok {
		for _, ro := range rawOpts {
			om, ok := ro.(map[string]interface{})
			if !ok {
				continue
			}
			opt := pollOption{Text: strVal(om["text"])}
			if v, ok := extraNum(om["voters"]); ok {
				opt.Voters = int(v)
			}
			opt.Chosen, _ = om["chosen"].(bool)
			opt.Correct, _ = om["correct"].(bool)
			d.Options = append(d.Options, opt)
		}
	}
	if len(d.Options) < 2 {
		return nil
	}
	return d
}

// applyPollOverlay folds this session's optimistic votes into the parsed
// poll: an option voted locally that the server has not counted yet gets
// its Chosen flag and a +1 on the counters. Pure — unit-tested.
func applyPollOverlay(d *pollData, votes map[int]bool) {
	if d == nil || votes == nil {
		return
	}
	// The overlay is the user's FULL current vote set (supersedes the
	// server's Chosen snapshot): additions gain a voter, retractions
	// drop one, counts never go negative.
	added, removed := 0, 0
	for i := range d.Options {
		was, now := d.Options[i].Chosen, votes[i]
		switch {
		case now && !was:
			d.Options[i].Chosen = true
			d.Options[i].Voters++
			added++
		case !now && was:
			d.Options[i].Chosen = false
			if d.Options[i].Voters > 0 {
				d.Options[i].Voters--
			}
			removed++
		}
	}
	d.TotalVoters += added - removed
	if d.TotalVoters < 0 {
		d.TotalVoters = 0
	}
}

// pollPercent is the vote share of an option (0 when nobody voted). Pure.
func pollPercent(voters, total int) int {
	if total <= 0 || voters <= 0 {
		return 0
	}
	p := voters * 100 / total
	if p > 100 {
		p = 100
	}
	return p
}

// pollSubtitle is the small label under the question (Telegram wording).
// Pure — unit-tested.
func pollSubtitle(d *pollData) string {
	if d == nil {
		return ""
	}
	if d.Quiz {
		return "Quiz"
	}
	if d.Public {
		return "Public poll"
	}
	return "Anonymous poll"
}

// pollFooterLabel: "N votes" / "No votes yet" (+ closed mark). Pure.
func pollFooterLabel(d *pollData) string {
	if d == nil || d.TotalVoters <= 0 {
		if d != nil && d.Closed {
			return "No votes · closed"
		}
		return "No votes yet"
	}
	s := "1 vote"
	if d.TotalVoters != 1 {
		s = itoa(d.TotalVoters) + " votes"
	}
	if d.Closed {
		s += " · closed"
	}
	return s
}

// pollVoteKey identifies one poll message for the optimistic-vote overlay.
func pollVoteKey(m *engine.CachedMessage) string {
	return m.AccountID + "|" + m.ChatID + "|" + m.MsgID
}

// pollIsBody reports whether the message's text body duplicates the poll
// question (the telegram core prefixes it with the 📊 glyph) — the poll
// block already renders the question, so the bubble body is suppressed.
func pollIsBody(m *engine.CachedMessage) bool {
	if m == nil || len(m.ContentRaw) == 0 {
		return false
	}
	if !bytes.Contains(m.ContentRaw, []byte(`"poll_question"`)) {
		return false
	}
	return parsePollMessage(m) != nil
}

// ── voting ─────────────────────────────────────────────────────────────────

// pollTapAction decides what a tap on option idx does (Telegram
// semantics, pure — unit-tested):
//
//	"vote"    single poll, first vote
//	"retract" single poll, tapping own choice takes it back (non-quiz)
//	"toggle"  multiple poll: flip idx within the vote set
//	"none"    closed / quiz-locked / switching options / invalid
func pollTapAction(d *pollData, overlay map[int]bool, idx int) string {
	if d == nil || idx < 0 || idx >= len(d.Options) || d.Closed {
		return "none"
	}
	chosen := func(i int) bool { return d.Options[i].Chosen }
	if overlay != nil {
		chosen = func(i int) bool { return overlay[i] }
	}
	if d.Multiple {
		return "toggle"
	}
	if d.Quiz {
		for i := range d.Options {
			if chosen(i) {
				return "none" // quizzes lock after the first answer
			}
		}
		return "vote"
	}
	mine := -1
	for i := range d.Options {
		if chosen(i) {
			mine = i
			break
		}
	}
	switch {
	case mine < 0:
		return "vote"
	case mine == idx:
		return "retract"
	default:
		return "none" // single polls cannot switch to another option
	}
}

// nextMultiVoteSet flips idx inside cur and returns the sorted full set
// (sendVote semantics: the whole set goes on the wire). Pure.
func nextMultiVoteSet(cur map[int]bool, idx int) []int {
	next := make(map[int]bool, len(cur)+1)
	for i, v := range cur {
		if v {
			next[i] = true
		}
	}
	if next[idx] {
		delete(next, idx)
	} else {
		next[idx] = true
	}
	out := make([]int, 0, len(next))
	for i := range next {
		out = append(out, i)
	}
	sort.Ints(out)
	return out
}

// tapPollOption handles a tap on poll option idx: first vote, retraction
// (non-quiz single polls) or set-toggle (multiple polls, full set on the
// wire via VotePollMulti). Optimistic overlay mirrors the server truth.
func (a *App) tapPollOption(m *engine.CachedMessage, d *pollData, idx int) {
	if m == nil || d == nil {
		return
	}
	k := pollVoteKey(m)
	overlay := a.pollVotesFor(k)
	switch pollTapAction(d, overlay, idx) {
	case "none":
		return
	case "vote":
		msg := *m
		go func() {
			if err := a.eng.VotePoll(msg.AccountID, msg.ChatID, msg.MsgID, idx); err != nil {
				a.setToast("Vote failed: " + err.Error())
				return
			}
			a.setPollOverlay(k, map[int]bool{idx: true})
		}()
	case "retract":
		msg := *m
		go func() {
			if err := a.eng.RetractPollVote(msg.AccountID, msg.ChatID, msg.MsgID); err != nil {
				a.setToast("Retract failed: " + err.Error())
				return
			}
			a.setPollOverlay(k, map[int]bool{}) // explicitly empty = retracted
		}()
	case "toggle":
		cur := overlay
		if cur == nil {
			cur = make(map[int]bool, len(d.Options))
			for i, o := range d.Options {
				if o.Chosen {
					cur[i] = true
				}
			}
		}
		next := nextMultiVoteSet(cur, idx)
		msg := *m
		go func() {
			if err := a.eng.VotePollMulti(msg.AccountID, msg.ChatID, msg.MsgID, next); err != nil {
				a.setToast("Vote failed: " + err.Error())
				return
			}
			set := make(map[int]bool, len(next))
			for _, i := range next {
				set[i] = true
			}
			a.setPollOverlay(k, set)
		}()
	}
}

// pollEffectiveClosed folds the optimistic stop overlay into the poll
// state (a server-confirmed stop stays locally closed until the poll
// update lands). Pure.
func pollEffectiveClosed(d *pollData, stopped bool) bool {
	if d == nil {
		return false
	}
	return d.Closed || stopped
}

// stopPollMessage closes an own open poll through the engine and pins the
// optimistic closed overlay.
func (a *App) stopPollMessage(m *engine.CachedMessage) {
	if m == nil {
		return
	}
	k := pollVoteKey(m)
	accountID, chatID, msgID := m.AccountID, m.ChatID, m.MsgID
	go func() {
		if err := a.eng.StopPoll(accountID, chatID, msgID); err != nil {
			a.setToast("Stop poll failed: " + err.Error())
			return
		}
		a.mu.Lock()
		if a.pollStopped == nil {
			a.pollStopped = make(map[string]bool)
		}
		a.pollStopped[k] = true
		a.mu.Unlock()
		a.invalidate()
		a.setToast("Poll stopped")
	}()
}

// stopPollMenuGate: the creator's own, still-open polls offer Stop poll.
func stopPollMenuGate(m *engine.CachedMessage) bool {
	if m == nil || !m.IsOutgoing || !pollIsBody(m) {
		return false
	}
	d := parsePollMessage(m)
	return d != nil && !d.Closed
}

// pollVotesFor returns a copy of the overlay votes for a message key.
func (a *App) pollVotesFor(key string) map[int]bool {
	a.mu.Lock()
	defer a.mu.Unlock()
	src, ok := a.pollVotes[key]
	if !ok {
		return nil // no overlay this session — server truth stands
	}
	out := make(map[int]bool, len(src))
	for i, v := range src {
		out[i] = v
	}
	return out
}

// setPollOverlay stores the user's full vote set for a poll (empty map =
// explicitly retracted) and repaints.
func (a *App) setPollOverlay(key string, votes map[int]bool) {
	a.mu.Lock()
	if a.pollVotes == nil {
		a.pollVotes = make(map[string]map[int]bool)
	}
	if votes == nil {
		votes = make(map[int]bool)
	}
	a.pollVotes[key] = votes
	a.mu.Unlock()
	a.invalidate()
}

// pollStoppedFor reports the optimistic stop overlay for a poll.
func (a *App) pollStoppedFor(key string) bool {
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.pollStopped[key]
}

// ── poll option clickables (stable per poll+option) ────────────────────────

var pollClicks = make(map[string]*widget.Clickable)

func pollOptClickable(key string) *widget.Clickable {
	if c, ok := pollClicks[key]; ok {
		return c
	}
	if len(pollClicks) > 512 {
		pollClicks = make(map[string]*widget.Clickable)
	}
	c := new(widget.Clickable)
	pollClicks[key] = c
	return c
}

// ── bubble rendering ───────────────────────────────────────────────────────

// pollBlock renders the poll inside a message bubble: question, subtitle,
// tappable option rows (vote bars once voted / closed), vote-count footer.
func (a *App) pollBlock(gtx layout.Context, m *engine.CachedMessage) layout.Dimensions {
	d := parsePollMessage(m)
	if d == nil {
		return layout.Dimensions{}
	}
	applyPollOverlay(d, a.pollVotesFor(pollVoteKey(m)))
	d.Closed = pollEffectiveClosed(d, a.pollStoppedFor(pollVoteKey(m)))

	voted := false
	for _, o := range d.Options {
		if o.Chosen {
			voted = true
			break
		}
	}
	showResults := voted || d.Closed

	children := make([]layout.FlexChild, 0, len(d.Options)+3)
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		lbl := a.ui.Label(unit.Sp(15), d.Question)
		lbl.Font.Weight = font.SemiBold
		return lbl.Layout(gtx)
	}))
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return layout.Inset{Top: unit.Dp(1)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			lbl := a.ui.Dim(unit.Sp(11), pollSubtitle(d))
			return lbl.Layout(gtx)
		})
	}))
	baseKey := pollVoteKey(m)
	for i := range d.Options {
		i := i
		opt := d.Options[i]
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return a.pollOptionRow(gtx, m, d, opt, i, baseKey, showResults, voted)
			})
		}))
	}
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return layout.Inset{Top: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			lbl := a.ui.Dim(unit.Sp(11), pollFooterLabel(d))
			return lbl.Layout(gtx)
		})
	}))
	// Quiz explanation (AyuGram: the solution line appears once voted).
	if d.Quiz && voted && d.Solution != "" {
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				lbl := a.ui.Dim(unit.Sp(12), d.Solution)
				lbl.Color = a.ui.p.TextDim
				lbl.MaxLines = 3
				return lbl.Layout(gtx)
			})
		}))
	}
	return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
}

// pollOptionRow renders one answer: a plain radio row before voting; after
// voting (or once closed) a Telegram-style bar with the vote share, the
// chosen answer highlighted, and quiz correct/wrong marks revealed.
func (a *App) pollOptionRow(gtx layout.Context, m *engine.CachedMessage, d *pollData, opt pollOption, idx int, baseKey string, showResults, voted bool) layout.Dimensions {
	btn := pollOptClickable(baseKey + "|" + itoa(idx))
	if !d.Closed && btn.Clicked(gtx) {
		a.tapPollOption(m, d, idx) // vote / retract / toggle, locks inside
	}

	if !showResults {
		// Pre-vote: radio circle + option text, full-row clickable.
		return roundedFill(gtx, a.ui.p.SurfaceHi, 8, func(gtx layout.Context) layout.Dimensions {
			return material.ButtonLayout(a.ui.Theme, btn).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Top: unit.Dp(6), Bottom: unit.Dp(6), Left: unit.Dp(8), Right: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							return pollRadioOutline(gtx, a.ui.p.TextFaint)
						}),
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							return layout.Inset{Left: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Label(unit.Sp(14), opt.Text)
								lbl.MaxLines = 2
								return lbl.Layout(gtx)
							})
						}),
					)
				})
			})
		})
	}

	// Results: share bar under the text, quiz marks, voter count.
	share := pollPercent(opt.Voters, d.TotalVoters)
	barCol := a.ui.p.AccentDim
	if opt.Chosen {
		barCol = a.ui.p.Accent
	}
	quizReveal := d.Quiz && voted

	row := roundedFill(gtx, a.ui.p.SurfaceHi, 8, func(gtx layout.Context) layout.Dimensions {
		// Record the content first, then paint the bar underneath it.
		macro := op.Record(gtx.Ops)
		dims := material.ButtonLayout(a.ui.Theme, btn).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(6), Bottom: unit.Dp(6), Left: unit.Dp(8), Right: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return pollRadioFilled(gtx, a, opt.Chosen, d.Quiz && voted && opt.Correct)
					}),
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Left: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Label(unit.Sp(14), opt.Text)
							lbl.MaxLines = 2
							return lbl.Layout(gtx)
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if quizReveal && (opt.Correct || opt.Chosen) {
							return pollQuizMark(gtx, a, opt.Correct)
						}
						return layout.Dimensions{}
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if quizReveal {
							return layout.Dimensions{}
						}
						return layout.Inset{Left: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Dim(unit.Sp(11), itoa(opt.Voters))
							return lbl.Layout(gtx)
						})
					}),
				)
			})
		})
		call := macro.Stop()

		if share > 0 && dims.Size.X > 0 {
			barW := dims.Size.X * share / 100
			if barW > dims.Size.X {
				barW = dims.Size.X
			}
			r := gtx.Dp(unit.Dp(8))
			paint.FillShape(gtx.Ops, barCol, clip.RRect{
				Rect: image.Rect(0, 0, barW, dims.Size.Y),
				NE:   r, NW: r, SE: 0, SW: 0,
			}.Op(gtx.Ops))
		}
		call.Add(gtx.Ops)
		return dims
	})
	return row
}

// pollRadioOutline draws the pre-vote answer circle.
func pollRadioOutline(gtx layout.Context, col color.NRGBA) layout.Dimensions {
	sz := gtx.Dp(unit.Dp(18))
	var p clip.Path
	p.Begin(gtx.Ops)
	m := float32(gtx.Dp(unit.Dp(1)))
	p.MoveTo(f32.Pt(m, m))
	p.LineTo(f32.Pt(float32(sz)-m, m))
	p.LineTo(f32.Pt(float32(sz)-m, float32(sz)-m))
	p.LineTo(f32.Pt(m, float32(sz)-m))
	p.Close()
	stroke := clip.Stroke{Path: p.End(), Width: float32(gtx.Dp(unit.Dp(1.5)))}
	stack := stroke.Op().Push(gtx.Ops)
	paint.Fill(gtx.Ops, col)
	stack.Pop()
	return layout.Dimensions{Size: image.Pt(sz, sz)}
}

// pollRadioFilled draws a filled answer circle (chosen / quiz-correct),
// with a white check inside.
func pollRadioFilled(gtx layout.Context, a *App, chosen, correct bool) layout.Dimensions {
	sz := gtx.Dp(unit.Dp(18))
	col := a.ui.p.Accent
	if correct {
		col = a.ui.p.Online
	} else if !chosen {
		return pollRadioOutline(gtx, a.ui.p.TextFaint)
	}
	paint.FillShape(gtx.Ops, col, clip.Ellipse{Min: image.Pt(0, 0), Max: image.Pt(sz, sz)}.Op(gtx.Ops))
	return check(gtx, color.NRGBA{R: 255, G: 255, B: 255, A: 255}, sz, 0)
}

// pollQuizMark draws the quiz ✓ (green) / ✗ (red) glyph at an option row.
func pollQuizMark(gtx layout.Context, a *App, correct bool) layout.Dimensions {
	sz := gtx.Dp(unit.Dp(16))
	col := a.ui.p.Error
	if correct {
		col = a.ui.p.Online
	}
	var p clip.Path
	p.Begin(gtx.Ops)
	if correct {
		p.MoveTo(f32.Pt(float32(sz)/4, float32(sz)*0.55))
		p.LineTo(f32.Pt(float32(sz)/2, float32(sz)*0.8))
		p.LineTo(f32.Pt(float32(sz)*0.85, float32(sz)*0.25))
	} else {
		p.MoveTo(f32.Pt(float32(sz)*0.25, float32(sz)*0.25))
		p.LineTo(f32.Pt(float32(sz)*0.75, float32(sz)*0.75))
		p.MoveTo(f32.Pt(float32(sz)*0.75, float32(sz)*0.25))
		p.LineTo(f32.Pt(float32(sz)*0.25, float32(sz)*0.75))
	}
	stroke := clip.Stroke{Path: p.End(), Width: float32(gtx.Dp(unit.Dp(1.8)))}
	stack := stroke.Op().Push(gtx.Ops)
	paint.Fill(gtx.Ops, col)
	stack.Pop()
	return layout.Dimensions{Size: image.Pt(sz, sz)}
}

// ── creation dialog ────────────────────────────────────────────────────────

// pollDlgState: open poll-creation dialog (nil when closed).
type pollDlgState struct {
	busy    bool
	correct int // quiz: chosen correct option index
}

var (
	pollDlgCancel   widget.Clickable
	pollDlgCreate   widget.Clickable
	pollQEd         widget.Editor
	pollOptEds      []widget.Editor
	pollAddOptBtn   widget.Clickable
	pollDelOptBtns  []widget.Clickable
	pollAnonSw      widget.Bool
	pollMultiSw     widget.Bool
	pollQuizSw      widget.Bool
	pollQuizWas     bool // previous-frame values for change detection
	pollMultiWas    bool
	pollCorrectBtns []widget.Clickable
	pollKeyTag      = new(struct{})
)

const pollMaxOptions = 10

// validatePollDraft (pure, testable): "" = valid, else the error message.
func validatePollDraft(question string, options []string) string {
	if strings.TrimSpace(question) == "" {
		return "Add a question"
	}
	n := 0
	for _, o := range options {
		if strings.TrimSpace(o) != "" {
			n++
		}
	}
	if n < 2 {
		return "Add at least 2 options"
	}
	return ""
}

// openPollDialog resets and shows the poll creation dialog.
func (a *App) openPollDialog() {
	a.mu.Lock()
	a.pollDlg = &pollDlgState{correct: 0}
	a.mu.Unlock()
	if len(pollOptEds) < 2 {
		pollOptEds = make([]widget.Editor, 2)
	}
	pollQEd.SetText("")
	for i := range pollOptEds {
		pollOptEds[i].SetText("")
	}
	pollAnonSw.Value = true
	pollMultiSw.Value = false
	pollQuizSw.Value = false
	pollQuizWas, pollMultiWas = false, false
	a.invalidate()
}

// closePollDialog hides the poll creation dialog.
func (a *App) closePollDialog() {
	a.mu.Lock()
	a.pollDlg = nil
	a.mu.Unlock()
	a.invalidate()
}

// submitPollDialog validates and sends the poll (engine CreatePollEx).
func (a *App) submitPollDialog() {
	a.mu.Lock()
	k := a.selected
	dlg := a.pollDlg
	if dlg == nil || dlg.busy || k == nil {
		a.mu.Unlock()
		return
	}
	dlg.busy = true
	correct := dlg.correct
	a.mu.Unlock()
	a.invalidate()

	q := strings.TrimSpace(pollQEd.Text())
	opts := make([]string, 0, len(pollOptEds))
	for i := range pollOptEds {
		if t := strings.TrimSpace(pollOptEds[i].Text()); t != "" {
			opts = append(opts, t)
		}
	}
	if err := validatePollDraft(q, opts); err != "" {
		a.setToast(err)
		a.mu.Lock()
		if a.pollDlg != nil {
			a.pollDlg.busy = false
		}
		a.mu.Unlock()
		return
	}

	acc, chat := k.AccountID, k.ChatID
	go func() {
		_, err := a.eng.CreatePollEx(acc, chat, q, opts, engine.PollOptions{
			Anonymous:      pollAnonSw.Value,
			MultipleChoice: pollMultiSw.Value,
			Quiz:           pollQuizSw.Value,
			CorrectOption:  correct,
		})
		a.mu.Lock()
		if a.pollDlg != nil {
			a.pollDlg.busy = false
		}
		a.mu.Unlock()
		if err != nil {
			a.setToast("Poll failed: " + err.Error())
			return
		}
		a.closePollDialog()
	}()
}

// layoutPollDialog renders the poll creation card over the chat pane.
func (a *App) layoutPollDialog(gtx layout.Context, f frame) layout.Dimensions {
	d := f.pollDlg
	{
		stack := clip.Rect{Max: image.Pt(gtx.Constraints.Max.X, gtx.Constraints.Max.Y)}.Push(gtx.Ops)
		event.Op(gtx.Ops, pollKeyTag)
		stack.Pop()
	}
	for {
		ev, ok := gtx.Source.Event(key.Filter{Name: key.NameEscape})
		if !ok {
			break
		}
		if ke, is := ev.(key.Event); is && ke.State == key.Press {
			a.closePollDialog()
		}
	}
	if pollDlgCancel.Clicked(gtx) {
		a.closePollDialog()
	}
	if pollDlgCreate.Clicked(gtx) {
		a.submitPollDialog()
	}
	if pollAddOptBtn.Clicked(gtx) && len(pollOptEds) < pollMaxOptions {
		pollOptEds = append(pollOptEds, widget.Editor{})
		a.invalidate()
	}
	growClickables(&pollDelOptBtns, len(pollOptEds))
	for i := range pollDelOptBtns {
		if pollDelOptBtns[i].Clicked(gtx) && len(pollOptEds) > 2 {
			pollOptEds = append(pollOptEds[:i], pollOptEds[i+1:]...)
			pollDelOptBtns = pollDelOptBtns[:len(pollOptEds)]
			a.mu.Lock()
			if a.pollDlg != nil && a.pollDlg.correct == i {
				a.pollDlg.correct = 0
			}
			a.mu.Unlock()
			a.invalidate()
		}
	}
	// Quiz and multiple answers are mutually exclusive (Telegram rule);
	// widget.Bool has no change event — track the previous values.
	if pollQuizSw.Value != pollQuizWas || pollMultiSw.Value != pollMultiWas {
		if pollQuizSw.Value && !pollQuizWas {
			pollMultiSw.Value = false
		}
		if pollMultiSw.Value && !pollMultiWas {
			pollQuizSw.Value = false
		}
		pollQuizWas, pollMultiWas = pollQuizSw.Value, pollMultiSw.Value
		a.invalidate()
	}

	paintScrimRect(gtx)

	label := "Create"
	if d.busy {
		label = "Sending…"
	}

	return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		gtx.Constraints.Max.X = gtx.Dp(unit.Dp(380))
		return roundedFill(gtx, a.ui.p.Surface, 12, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(16)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.H3("New poll")
						return lbl.Layout(gtx)
					}),
					// Question editor.
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return roundedFill(gtx, a.ui.p.SurfaceHi, 10, func(gtx layout.Context) layout.Dimensions {
								return layout.UniformInset(unit.Dp(6)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
									ed := a.ui.Editor(&pollQEd, "Question")
									return ed.Layout(gtx)
								})
							})
						})
					}),
					// Option editors + add/remove + quiz-correct marks.
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						growClickables(&pollCorrectBtns, len(pollOptEds))
						rows := make([]layout.FlexChild, 0, len(pollOptEds)+1)
						for i := range pollOptEds {
							i := i
							rows = append(rows, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								return layout.Inset{Top: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
									return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
										layout.Rigid(func(gtx layout.Context) layout.Dimensions {
											return layout.Inset{Right: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
												lbl := a.ui.Dim(unit.Sp(12), itoa(i+1)+".")
												return lbl.Layout(gtx)
											})
										}),
										layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
											return roundedFill(gtx, a.ui.p.SurfaceHi, 10, func(gtx layout.Context) layout.Dimensions {
												return layout.UniformInset(unit.Dp(6)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
													ed := a.ui.Editor(&pollOptEds[i], "Option")
													return ed.Layout(gtx)
												})
											})
										}),
										layout.Rigid(func(gtx layout.Context) layout.Dimensions {
											if len(pollOptEds) <= 2 {
												return layout.Dimensions{}
											}
											return layout.Inset{Left: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
												return a.ui.IconButton(&pollDelOptBtns[i], iconContentClear, "Remove option").Layout(gtx)
											})
										}),
										layout.Rigid(func(gtx layout.Context) layout.Dimensions {
											if !pollQuizSw.Value {
												return layout.Dimensions{}
											}
											return layout.Inset{Left: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
												if pollCorrectBtns[i].Clicked(gtx) {
													a.mu.Lock()
													if a.pollDlg != nil {
														a.pollDlg.correct = i
													}
													a.mu.Unlock()
													a.invalidate()
												}
												btn := a.ui.IconButton(&pollCorrectBtns[i], iconNavigationCheck, "Correct answer")
												if d.correct == i {
													btn.Color = a.ui.p.Online
												} else {
													btn.Color = a.ui.p.TextFaint
												}
												return btn.Layout(gtx)
											})
										}),
									)
								})
							}))
						}
						rows = append(rows, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							return layout.Inset{Top: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								if len(pollOptEds) >= pollMaxOptions {
									return layout.Dimensions{}
								}
								btn := a.ui.TextButton(&pollAddOptBtn, "Add option")
								btn.Color = a.ui.p.Accent
								return btn.Layout(gtx)
							})
						}))
						return layout.Flex{Axis: layout.Vertical}.Layout(gtx, rows...)
					}),
					// Toggles.
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									return a.pollSwitchRow(gtx, &pollAnonSw, "Anonymous poll")
								}),
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									return a.pollSwitchRow(gtx, &pollMultiSw, "Multiple answers")
								}),
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									return a.pollSwitchRow(gtx, &pollQuizSw, "Quiz mode")
								}),
							)
						})
					}),
					// Actions.
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
								layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
									btn := a.ui.TextButton(&pollDlgCancel, "Cancel")
									btn.Color = a.ui.p.TextDim
									return btn.Layout(gtx)
								}),
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									btn := a.ui.TextButton(&pollDlgCreate, label)
									btn.Color = a.ui.p.Accent
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

// pollSwitchRow renders a label + material switch for the poll dialog.
func (a *App) pollSwitchRow(gtx layout.Context, sw *widget.Bool, label string) layout.Dimensions {
	return layout.Inset{Top: unit.Dp(3), Bottom: unit.Dp(3)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
			layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
				lbl := a.ui.Label(unit.Sp(14), label)
				return lbl.Layout(gtx)
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				tg := material.Switch(a.ui.Theme, sw, "")
				tg.Color.Enabled = a.ui.p.Accent
				tg.Color.Disabled = a.ui.p.SurfaceHi
				tg.Color.Track = a.ui.p.SurfaceHi
				return tg.Layout(gtx)
			}),
		)
	})
}
