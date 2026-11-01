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

type pollOption struct {
	Text    string
	Voters  int
	Chosen  bool
	Correct bool
}

type pollData struct {
	Question    string
	Options     []pollOption
	TotalVoters int
	Multiple    bool
	Quiz        bool
	Closed      bool
	Public      bool
	Solution    string
}

type rawEnvelope struct {
	Extra map[string]interface{} `json:"extra"`
}

func extraNum(v interface{}) (float64, bool) {
	f, ok := v.(float64)
	return f, ok
}

func strVal(v interface{}) string {
	s, _ := v.(string)
	return s
}

func parsePollMessage(m *engine.CachedMessage) *pollData {
	if m == nil || len(m.ContentRaw) == 0 {
		return nil
	}
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

func applyPollOverlay(d *pollData, votes map[int]bool) {
	if d == nil || votes == nil {
		return
	}
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

func pollVoteKey(m *engine.CachedMessage) string {
	return m.AccountID + "|" + m.ChatID + "|" + m.MsgID
}

func pollIsBody(m *engine.CachedMessage) bool {
	if m == nil || len(m.ContentRaw) == 0 {
		return false
	}
	if !bytes.Contains(m.ContentRaw, []byte(`"poll_question"`)) {
		return false
	}
	return parsePollMessage(m) != nil
}

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
				return "none"
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
		return "none"
	}
}

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
			a.setPollOverlay(k, map[int]bool{})
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

func pollEffectiveClosed(d *pollData, stopped bool) bool {
	if d == nil {
		return false
	}
	return d.Closed || stopped
}

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

func stopPollMenuGate(m *engine.CachedMessage) bool {
	if m == nil || !m.IsOutgoing || !pollIsBody(m) {
		return false
	}
	d := parsePollMessage(m)
	return d != nil && !d.Closed
}

func (a *App) pollVotesFor(key string) map[int]bool {
	a.mu.Lock()
	defer a.mu.Unlock()
	src, ok := a.pollVotes[key]
	if !ok {
		return nil
	}
	out := make(map[int]bool, len(src))
	for i, v := range src {
		out[i] = v
	}
	return out
}

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

func (a *App) pollStoppedFor(key string) bool {
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.pollStopped[key]
}

func (a *App) pollOptClickable(key string) *widget.Clickable {
	if c, ok := a.wid.pollClicks[key]; ok {
		return c
	}
	if len(a.wid.pollClicks) > 512 {
		a.wid.pollClicks = make(map[string]*widget.Clickable)
	}
	c := new(widget.Clickable)
	a.wid.pollClicks[key] = c
	return c
}

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

func (a *App) pollOptionRow(gtx layout.Context, m *engine.CachedMessage, d *pollData, opt pollOption, idx int, baseKey string, showResults, voted bool) layout.Dimensions {
	btn := a.pollOptClickable(baseKey + "|" + itoa(idx))
	if !d.Closed && btn.Clicked(gtx) {
		a.tapPollOption(m, d, idx)
	}

	if !showResults {
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

	share := pollPercent(opt.Voters, d.TotalVoters)
	barCol := a.ui.p.AccentDim
	if opt.Chosen {
		barCol = a.ui.p.Accent
	}
	quizReveal := d.Quiz && voted

	row := roundedFill(gtx, a.ui.p.SurfaceHi, 8, func(gtx layout.Context) layout.Dimensions {
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

type pollDlgState struct {
	busy    bool
	correct int
}

var (
	pollOptEds   []widget.Editor
	pollQuizWas  bool
	pollMultiWas bool
	pollKeyTag   = new(struct{})
)

func (a *App) updatePollDlg(fn func(d *pollDlgState) bool) bool {
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.pollDlg == nil {
		return false
	}
	d := *a.pollDlg
	if !fn(&d) {
		return false
	}
	a.pollDlg = &d
	return true
}

const pollMaxOptions = 10

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

func (a *App) openPollDialog() {
	a.mu.Lock()
	a.pollDlg = &pollDlgState{correct: 0}
	a.pollDlgGen++
	a.mu.Unlock()
	if len(pollOptEds) < 2 {
		pollOptEds = make([]widget.Editor, 2)
	}
	a.wid.pollQEd.SetText("")
	for i := range pollOptEds {
		pollOptEds[i].SetText("")
	}
	a.wid.pollAnonSw.Value = true
	a.wid.pollMultiSw.Value = false
	a.wid.pollQuizSw.Value = false
	pollQuizWas, pollMultiWas = false, false
	a.invalidate()
}

func (a *App) closePollDialog() {
	a.mu.Lock()
	a.pollDlg = nil
	a.mu.Unlock()
	a.invalidate()
}

func (a *App) submitPollDialog() {
	a.mu.Lock()
	k := a.selected
	gen := a.pollDlgGen
	dlg := a.pollDlg
	a.mu.Unlock()
	if dlg == nil || k == nil {
		return
	}
	if !a.updatePollDlg(func(d *pollDlgState) bool {
		if d.busy {
			return false
		}
		d.busy = true
		return true
	}) {
		return
	}
	a.invalidate()

	q := strings.TrimSpace(a.wid.pollQEd.Text())
	opts := make([]string, 0, len(pollOptEds))
	for i := range pollOptEds {
		if t := strings.TrimSpace(pollOptEds[i].Text()); t != "" {
			opts = append(opts, t)
		}
	}
	if err := validatePollDraft(q, opts); err != "" {
		a.setToast(err)
		a.updatePollDlg(func(d *pollDlgState) bool { d.busy = false; return true })
		return
	}

	anon := a.wid.pollAnonSw.Value
	multi := a.wid.pollMultiSw.Value
	quiz := a.wid.pollQuizSw.Value
	correct := dlg.correct
	acc, chat := k.AccountID, k.ChatID
	go func() {
		_, err := a.eng.CreatePollEx(acc, chat, q, opts, engine.PollOptions{
			Anonymous:      anon,
			MultipleChoice: multi,
			Quiz:           quiz,
			CorrectOption:  correct,
		})
		a.pollSendDone(gen, err)
	}()
}

func (a *App) pollSendDone(gen int, err error) {
	a.mu.Lock()
	live := a.pollDlg != nil && a.pollDlgGen == gen
	a.mu.Unlock()
	if live {
		if err == nil {
			a.closePollDialog()
		} else {
			a.updatePollDlg(func(d *pollDlgState) bool { d.busy = false; return true })
		}
	}
	if err != nil {
		a.setToast("Poll failed: " + err.Error())
	}
}

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
	if a.wid.pollDlgCancel.Clicked(gtx) {
		a.closePollDialog()
	}
	if a.wid.pollDlgCreate.Clicked(gtx) {
		a.submitPollDialog()
	}
	if a.wid.pollAddOptBtn.Clicked(gtx) && len(pollOptEds) < pollMaxOptions {
		pollOptEds = append(pollOptEds, widget.Editor{})
		a.invalidate()
	}
	growClickables(&a.wid.pollDelOptBtns, len(pollOptEds))
	for i := range a.wid.pollDelOptBtns {
		if a.wid.pollDelOptBtns[i].Clicked(gtx) && len(pollOptEds) > 2 {
			pollOptEds = append(pollOptEds[:i], pollOptEds[i+1:]...)
			a.wid.pollDelOptBtns = a.wid.pollDelOptBtns[:len(pollOptEds)]
			a.updatePollDlg(func(d *pollDlgState) bool {
				if d.correct != i {
					return false
				}
				d.correct = 0
				return true
			})
			a.invalidate()
		}
	}
	if a.wid.pollQuizSw.Value != pollQuizWas || a.wid.pollMultiSw.Value != pollMultiWas {
		if a.wid.pollQuizSw.Value && !pollQuizWas {
			a.wid.pollMultiSw.Value = false
		}
		if a.wid.pollMultiSw.Value && !pollMultiWas {
			a.wid.pollQuizSw.Value = false
		}
		pollQuizWas, pollMultiWas = a.wid.pollQuizSw.Value, a.wid.pollMultiSw.Value
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
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return roundedFill(gtx, a.ui.p.SurfaceHi, 10, func(gtx layout.Context) layout.Dimensions {
								return layout.UniformInset(unit.Dp(6)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
									ed := a.ui.Editor(&a.wid.pollQEd, "Question")
									return ed.Layout(gtx)
								})
							})
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						growClickables(&a.wid.pollCorrectBtns, len(pollOptEds))
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
												return a.ui.IconButton(&a.wid.pollDelOptBtns[i], iconContentClear, "Remove option").Layout(gtx)
											})
										}),
										layout.Rigid(func(gtx layout.Context) layout.Dimensions {
											if !a.wid.pollQuizSw.Value {
												return layout.Dimensions{}
											}
											return layout.Inset{Left: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
												if a.wid.pollCorrectBtns[i].Clicked(gtx) {
													a.updatePollDlg(func(d *pollDlgState) bool { d.correct = i; return true })
													a.invalidate()
												}
												btn := a.ui.IconButton(&a.wid.pollCorrectBtns[i], iconNavigationCheck, "Correct answer")
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
								btn := a.ui.TextButton(&a.wid.pollAddOptBtn, "Add option")
								btn.Color = a.ui.p.Accent
								return btn.Layout(gtx)
							})
						}))
						return layout.Flex{Axis: layout.Vertical}.Layout(gtx, rows...)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									return a.pollSwitchRow(gtx, &a.wid.pollAnonSw, "Anonymous poll")
								}),
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									return a.pollSwitchRow(gtx, &a.wid.pollMultiSw, "Multiple answers")
								}),
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									return a.pollSwitchRow(gtx, &a.wid.pollQuizSw, "Quiz mode")
								}),
							)
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
								layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
									btn := a.ui.TextButton(&a.wid.pollDlgCancel, "Cancel")
									btn.Color = a.ui.p.TextDim
									return btn.Layout(gtx)
								}),
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									btn := a.ui.TextButton(&a.wid.pollDlgCreate, label)
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
