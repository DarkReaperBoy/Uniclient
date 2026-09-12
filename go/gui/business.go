package gui

// Telegram Business settings page (tdesktop Settings → Telegram
// Business, slice 148): opening hours, location, greeting messages,
// away messages, quick replies and the profile intro — per Telegram
// account, all real RPCs through engine.{Get,Set}BusinessFeature and
// the quick-reply surface. Editors expand inline; nothing fakes
// capability (§1.10): rows show honest "Not set" states and the page
// only appears with Telegram-platform accounts.

import (
	"encoding/json"
	"fmt"
	"sort"
	"strconv"
	"strings"
	"time"

	"gioui.org/font"
	"gioui.org/layout"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/cores"
)

// ── pure model (unit-tested in business_test.go) ─────────────────────────

// bizIVL is one opening interval in minutes-of-day (0..1440; end may be
// 1440 = midnight close).
type bizIVL struct{ start, end int }

// bizWeek is the per-day opening-hours model (Mon..Sun).
type bizWeek [7][]bizIVL

var bizDayNames = [7]string{"Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"}

// bizWeekFromWire splits wire intervals (minute-of-week, cross-midnight
// friendly, end up to 8*24*60) into per-day intervals: a piece crossing
// midnight lands its tail on the following day (Sunday wraps to Monday).
func bizWeekFromWire(ivs []interface{}) bizWeek {
	var w bizWeek
	for _, raw := range ivs {
		iv, ok := raw.(map[string]interface{})
		if !ok {
			continue
		}
		s, e := mapInt(iv, "start"), mapInt(iv, "end")
		if s < 0 || e <= s {
			continue
		}
		for s < e {
			day := (s / 1440) % 7
			dayStart := s - (s % 1440)
			dayEnd := dayStart + 1440
			if dayEnd > e {
				dayEnd = e
			}
			w[day] = append(w[day], bizIVL{start: s - dayStart, end: dayEnd - dayStart})
			s = dayEnd
		}
	}
	for d := range w {
		w[d] = normalizeBizIVLs(w[d])
	}
	return w
}

// normalizeBizIVLs sorts, merges overlapping/adjacent intervals and
// drops empties within one day.
func normalizeBizIVLs(ivls []bizIVL) []bizIVL {
	if len(ivls) == 0 {
		return nil
	}
	sort.Slice(ivls, func(i, j int) bool { return ivls[i].start < ivls[j].start })
	out := []bizIVL{ivls[0]}
	for _, iv := range ivls[1:] {
		last := &out[len(out)-1]
		if iv.start <= last.end { // overlap or adjacent → merge
			if iv.end > last.end {
				last.end = iv.end
			}
			continue
		}
		out = append(out, iv)
	}
	return out
}

// toWire converts the per-day model back to sorted, merged wire
// intervals (minute-of-week; cross-midnight pieces stay split — the
// server accepts both shapes equivalently).
func (w bizWeek) toWire() []interface{} {
	type wireIVL struct{ start, end int }
	var flat []wireIVL
	for d, ivls := range w {
		for _, iv := range ivls {
			if iv.end <= iv.start {
				continue
			}
			flat = append(flat, wireIVL{start: d*1440 + iv.start, end: d*1440 + iv.end})
		}
	}
	sort.Slice(flat, func(i, j int) bool { return flat[i].start < flat[j].start })
	out := make([]interface{}, 0, len(flat))
	for _, iv := range flat {
		out = append(out, map[string]interface{}{"start": iv.start, "end": iv.end})
	}
	return out
}

// empty reports whether the week has no intervals at all.
func (w bizWeek) empty() bool {
	for _, ivls := range w {
		if len(ivls) > 0 {
			return false
		}
	}
	return true
}

// is247 reports the around-the-clock schedule (every day fully open,
// allowing the single 0..10080 wire form too).
func (w bizWeek) is247() bool {
	for _, ivls := range w {
		if len(ivls) != 1 || ivls[0].start != 0 || ivls[0].end != 1440 {
			return false
		}
	}
	return true
}

// set247 installs the around-the-clock schedule.
func (w *bizWeek) set247() {
	for d := range w {
		w[d] = []bizIVL{{start: 0, end: 1440}}
	}
}

// summary renders a human schedule ("Mon–Fri 09:00–17:00, Sat 10:00–14:00"
// style): days with identical intervals collapse into ranges.
func (w bizWeek) summary() string {
	if w.empty() {
		return ""
	}
	if w.is247() {
		return "24/7"
	}
	type span struct {
		days []int
		ivls string
	}
	var spans []span
	for d, ivls := range w {
		s := bizFormatDay(ivls)
		if len(spans) > 0 && spans[len(spans)-1].ivls == s && spans[len(spans)-1].days[len(spans[len(spans)-1].days)-1] == d-1 {
			spans[len(spans)-1].days = append(spans[len(spans)-1].days, d)
			continue
		}
		spans = append(spans, span{days: []int{d}, ivls: s})
	}
	var parts []string
	for _, sp := range spans {
		if sp.ivls == "" {
			continue // closed days stay implicit
		}
		var label string
		switch {
		case len(sp.days) == 1:
			label = bizDayShort(sp.days[0])
		case len(sp.days) == 7:
			label = "Daily"
		default:
			label = bizDayShort(sp.days[0]) + "–" + bizDayShort(sp.days[len(sp.days)-1])
		}
		parts = append(parts, label+" "+sp.ivls)
	}
	return strings.Join(parts, ", ")
}

// bizFormatDay renders one day's intervals ("09:00–17:00" or "" when
// closed).
func bizFormatDay(ivls []bizIVL) string {
	var parts []string
	for _, iv := range ivls {
		if iv.end <= iv.start {
			continue
		}
		parts = append(parts, bizFormatTime(iv.start)+"–"+bizFormatTime(iv.end))
	}
	return strings.Join(parts, ", ")
}

// bizFormatTime renders minutes-of-day as "09:30".
func bizFormatTime(m int) string {
	if m < 0 {
		m = 0
	}
	if m > 1440 {
		m = 1440
	}
	return fmt.Sprintf("%02d:%02d", m/60, m%60)
}

// bizParseTime leniently parses "9", "9:30", "09.30", "9 30" into
// minutes-of-day.
func bizParseTime(s string) (int, bool) {
	s = strings.TrimSpace(strings.ReplaceAll(s, ".", ":"))
	if s == "" {
		return 0, false
	}
	var h, m int
	var err1, err2 error
	switch parts := strings.FieldsFunc(s, func(r rune) bool { return r == ':' }); len(parts) {
	case 1:
		h, err1 = strconv.Atoi(parts[0])
	case 2:
		h, err1 = strconv.Atoi(parts[0])
		m, err2 = strconv.Atoi(parts[1])
	default:
		return 0, false
	}
	if err1 != nil || err2 != nil {
		return 0, false
	}
	if h < 0 || h > 24 || m < 0 || m >= 60 || (h == 24 && m != 0) {
		return 0, false
	}
	return h*60 + m, true
}

// bizDayShort renders the 3-letter day name.
func bizDayShort(d int) string {
	if d < 0 || d > 6 {
		return "?"
	}
	return bizDayNames[d][:3]
}

// bizRecipients is the greeting/away recipient selection.
type bizRecipients struct {
	existing, newChats, contacts, nonContacts, exclude bool
}

// fromMap reads the wire-shaped flags.
func (r *bizRecipients) fromMap(m map[string]interface{}) {
	if len(m) == 0 {
		return
	}
	r.existing = mapBool(m, "existing_chats")
	r.newChats = mapBool(m, "new_chats")
	r.contacts = mapBool(m, "contacts")
	r.nonContacts = mapBool(m, "non_contacts")
	r.exclude = mapBool(m, "exclude_selected")
}

// toMap writes the wire-shaped flags.
func (r bizRecipients) toMap() map[string]interface{} {
	return map[string]interface{}{
		"existing_chats":   r.existing,
		"new_chats":        r.newChats,
		"contacts":         r.contacts,
		"non_contacts":     r.nonContacts,
		"exclude_selected": r.exclude,
	}
}

// mapBool/mapInt read leniently from the engine's JSON-decoded maps.
func mapBool(m map[string]interface{}, k string) bool {
	if v, ok := m[k].(bool); ok {
		return v
	}
	return false
}

func mapInt(m map[string]interface{}, k string) int {
	switch v := m[k].(type) {
	case int:
		return v
	case float64:
		return int(v)
	}
	return 0
}

func mapFloat(m map[string]interface{}, k string) (float64, bool) {
	if v, ok := m[k].(float64); ok {
		return v, true
	}
	return 0, false
}

func mapStr(m map[string]interface{}, k string) string {
	if v, ok := m[k].(string); ok {
		return v
	}
	return ""
}

// bizSubMap digs a nested map out of the read model.
func bizSubMap(info map[string]interface{}, key string) map[string]interface{} {
	if m, ok := info[key].(map[string]interface{}); ok {
		return m
	}
	return nil
}

// bizUtcLabel renders "UTC+03:00" from an offset in seconds.
func bizUtcLabel(off int) string {
	sign := "+"
	if off < 0 {
		sign, off = "-", -off
	}
	return fmt.Sprintf("UTC%s%02d:%02d", sign, off/3600, (off%3600)/60)
}

// ── page state ───────────────────────────────────────────────────────────

// businessPageState is the open Telegram Business sub-page.
type businessPageState struct {
	accountID string
	loading   bool
	loaded    bool
	err       string

	info      map[string]interface{}
	timezones []cores.TimezoneInfo
	tzLoaded  bool
	replies   []cores.QuickReplyInfo

	editor    string // "" | location | hours | greeting | away | intro | replies
	busy      bool   // an apply/remove/create RPC is in flight
	editorErr string

	hours  bizWeek // hours editor model
	tzPick string  // selected timezone id
	tzOpen bool    // timezone picker expanded

	recips    bizRecipients // greeting/away recipient model
	inactDays int           // 7 | 14 | 21 | 28
	awayMode  string        // always | outside_work_hours | custom
	awayFrom  string        // "YYYY-MM-DD"
	awayTo    string        // "YYYY-MM-DD"
	offline   bool          // away offline-only

	// quick-reply inline editors
	qrNewOpen  bool
	qrRenameID int // shortcut being renamed (0 = none)
}

var (
	bizOpenBtn     widget.Clickable // Settings → Main entry card
	bizBackBtn     widget.Clickable
	bizReloadBtn   widget.Clickable
	bizAcctBtns    []widget.Clickable
	bizEditorBtns  []widget.Clickable // section rows (tap to expand)
	bizApplyBtn    widget.Clickable
	bizRemoveBtn   widget.Clickable
	biz247Btn      widget.Clickable
	bizTzToggleBtn widget.Clickable
	bizTzRowBtns   []widget.Clickable
	bizAddIvlBtns  []widget.Clickable
	bizDelIvlBtns  []widget.Clickable
	bizDayChips    []widget.Clickable // quick day presets (weekday/all/none)
	bizInactChips  []widget.Clickable // 7/14/21/28
	bizAwayChips   []widget.Clickable // schedule modes
	bizRecChks     []widget.Bool      // recipient checkboxes
	bizOfflineChk  widget.Bool
	bizExcludeChk  widget.Bool

	bizMsgEd     widget.Editor // greeting/away message text
	bizAddrEd    widget.Editor // location address
	bizLatEd     widget.Editor
	bizLonEd     widget.Editor
	bizTitleEd   widget.Editor // intro title
	bizDescEd    widget.Editor // intro description
	bizTzSearch  widget.Editor
	bizQRNameEd  widget.Editor // quick-reply create/rename name
	bizQRTextEd  widget.Editor // quick-reply create text
	bizTimeEds   []*widget.Editor
	bizFromEd    widget.Editor // away custom range
	bizToEd      widget.Editor
	bizQRNewBtn  widget.Clickable
	bizQRCancel  widget.Clickable
	bizQRCreate  widget.Clickable
	bizQRRows    []widget.Clickable // shortcut rows
	bizQRRenBtns []widget.Clickable
	bizQRDelBtns []widget.Clickable
	bizQRUpdBtn  widget.Clickable // rename apply
	bizScroll    widget.List
)

func init() {
	bizMsgEd.SingleLine = false
	bizAddrEd.SingleLine = true
	bizLatEd.SingleLine = true
	bizLonEd.SingleLine = true
	bizTitleEd.SingleLine = true
	bizDescEd.SingleLine = false
	bizQRNameEd.SingleLine = true
	bizQRTextEd.SingleLine = false
	bizTzSearch.SingleLine = true
	bizFromEd.SingleLine = true
	bizToEd.SingleLine = true
}

// openBusinessPage starts the page for an account and loads its data.
func (a *App) openBusinessPage(accountID string) {
	a.mu.Lock()
	a.businessPage = &businessPageState{accountID: accountID, loading: true}
	a.profileEdit = nil // one sub-page at a time (settings shell)
	a.stickerMgr = nil
	a.folderMgr = nil
	a.premiumPage = nil
	a.starsPage = nil
	a.mu.Unlock()
	go a.loadBusinessPage(accountID)
	a.invalidate()
}

// closeBusinessPage dismisses the page.
func (a *App) closeBusinessPage() {
	a.mu.Lock()
	a.businessPage = nil
	a.mu.Unlock()
	a.invalidate()
}

// loadBusinessPage fetches the read model + timezone list in parallel.
func (a *App) loadBusinessPage(accountID string) {
	raw, errI := a.eng.GetBusinessInfo(accountID)
	var info map[string]interface{}
	if errI == nil && len(raw) > 0 {
		var decoded map[string]interface{}
		if err := json.Unmarshal(raw, &decoded); err == nil {
			info = decoded
		}
	}
	tzs, errT := a.eng.GetTimezones(accountID)
	replies, errR := a.eng.GetQuickReplies(accountID)
	a.mu.Lock()
	st := a.businessPage
	if st == nil || st.accountID != accountID {
		a.mu.Unlock()
		return
	}
	st.loading = false
	if errI != nil {
		st.err = errI.Error()
	} else {
		st.err = ""
		st.loaded = true
		st.info = info
	}
	if errT == nil && tzs != nil {
		st.timezones, st.tzLoaded = tzs, true
	}
	if errR == nil && replies != nil {
		st.replies = replies
	}
	a.mu.Unlock()
	a.invalidate()
}

// reloadBusinessPage re-pulls after a mutation or manual reload.
func (a *App) reloadBusinessPage() {
	a.mu.Lock()
	acc := ""
	if st := a.businessPage; st != nil {
		acc = st.accountID
		st.loading = true
		st.editorErr = ""
	}
	a.mu.Unlock()
	if acc != "" {
		go a.loadBusinessPage(acc)
	}
}

// bizEditorData assembles the feature map from the open editor's
// widget state; called on Apply (reads editors under the UI lock).
func (a *App) bizEditorData(st *businessPageState) (map[string]interface{}, error) {
	switch st.editor {
	case "location":
		data := map[string]interface{}{}
		addr := strings.TrimSpace(bizAddrEd.Text())
		if addr != "" {
			data["address"] = addr
		}
		if lat, ok := parseBizFloat(bizLatEd.Text()); ok {
			data["lat"] = lat
		}
		if lon, ok := parseBizFloat(bizLonEd.Text()); ok {
			data["lon"] = lon
		}
		return data, nil
	case "hours":
		w, err := bizWeekFromEditors()
		if err != nil {
			return nil, err
		}
		if w.empty() {
			return map[string]interface{}{}, nil
		}
		return map[string]interface{}{
			"timezone_id": st.tzPick,
			"weekly_open": w.toWire(),
		}, nil
	case "greeting", "away":
		data := st.recips.toMap()
		data["message"] = bizMsgEd.Text()
		data["shortcut_name"] = st.editor
		if g := bizSubMap(st.info, st.editor); g != nil {
			data["shortcut_id"] = mapInt(g, "shortcut_id")
		}
		if st.editor == "greeting" {
			data["no_activity_days"] = st.inactDays
		} else {
			data["offline_only"] = st.offline
			data["schedule"] = st.awayMode
			if st.awayMode == "custom" {
				s, okS := parseBizDate(bizFromEd.Text())
				e, okE := parseBizDate(bizToEd.Text())
				if !okS || !okE || e <= s {
					return nil, fmt.Errorf("enter a valid custom date range")
				}
				data["start_date"] = s
				data["end_date"] = e
			}
		}
		return data, nil
	case "intro":
		data := map[string]interface{}{
			"title":       strings.TrimSpace(bizTitleEd.Text()),
			"description": strings.TrimSpace(bizDescEd.Text()),
		}
		return data, nil
	}
	return nil, fmt.Errorf("no editor open")
}

func parseBizFloat(s string) (float64, bool) {
	var f float64
	if _, err := fmt.Sscanf(strings.TrimSpace(s), "%g", &f); err != nil {
		return 0, false
	}
	return f, true
}

// parseBizDate parses "YYYY-MM-DD" into unix seconds (UTC).
func parseBizDate(s string) (int64, bool) {
	s = strings.TrimSpace(s)
	t, err := time.Parse("2006-01-02", s)
	if err != nil {
		return 0, false
	}
	return t.Unix(), true
}

// bizApplyClicked runs on the UI goroutine: captures the open editor's
// widget state into the feature map, then dispatches the RPC.
func (a *App) bizApplyClicked(st *businessPageState) {
	if st == nil || st.busy {
		return
	}
	data, err := a.bizEditorData(st)
	acc, feature := st.accountID, st.editor
	a.mu.Lock()
	st.busy = true
	st.editorErr = ""
	a.mu.Unlock()
	a.invalidate()
	go func() {
		if err == nil {
			err = a.eng.SetBusinessFeature(acc, feature, data)
		}
		a.mu.Lock()
		if s := a.businessPage; s != nil {
			s.busy = false
			if err != nil {
				s.editorErr = err.Error()
			} else {
				s.editor = ""
			}
		}
		a.mu.Unlock()
		if err == nil {
			a.setToast("Saved")
		}
		a.reloadBusinessPage()
	}()
}

// removeBusinessFeature clears the open editor's feature.
func (a *App) removeBusinessFeature() {
	a.mu.Lock()
	st := a.businessPage
	if st == nil || st.busy {
		a.mu.Unlock()
		return
	}
	acc, feature := st.accountID, st.editor
	st.busy = true
	st.editorErr = ""
	a.mu.Unlock()
	a.invalidate()

	err := a.eng.SetBusinessFeature(acc, feature, map[string]interface{}{})
	a.mu.Lock()
	if st = a.businessPage; st != nil {
		st.busy = false
		if err != nil {
			st.editorErr = err.Error()
		} else {
			st.editor = ""
		}
	}
	a.mu.Unlock()
	if err == nil {
		a.setToast("Removed")
	}
	a.reloadBusinessPage()
}

// bizCreateQuickReply creates a shortcut; name/text are captured on the
// UI goroutine by the caller.
func (a *App) bizCreateQuickReply(name, text string) {
	a.mu.Lock()
	st := a.businessPage
	if st == nil || st.busy {
		a.mu.Unlock()
		return
	}
	acc := st.accountID
	st.busy = true
	st.editorErr = ""
	a.mu.Unlock()
	a.invalidate()

	_, err := a.eng.CreateQuickReply(acc, name, text)
	a.mu.Lock()
	if st = a.businessPage; st != nil {
		st.busy = false
		if err != nil {
			st.editorErr = err.Error()
		} else {
			st.qrNewOpen = false
		}
	}
	a.mu.Unlock()
	if err == nil {
		a.setToast("Shortcut created")
	}
	a.reloadBusinessPage()
}

// bizRenameQuickReply applies the inline rename; the name is captured on
// the UI goroutine by the caller.
func (a *App) bizRenameQuickReply(id int, name string) {
	a.mu.Lock()
	st := a.businessPage
	if st == nil || st.busy {
		a.mu.Unlock()
		return
	}
	acc := st.accountID
	st.busy = true
	st.editorErr = ""
	a.mu.Unlock()
	a.invalidate()

	err := a.eng.RenameQuickReply(acc, id, name)
	a.mu.Lock()
	if st = a.businessPage; st != nil {
		st.busy = false
		if err != nil {
			st.editorErr = err.Error()
		} else {
			st.qrRenameID = 0
		}
	}
	a.mu.Unlock()
	if err == nil {
		a.setToast("Shortcut renamed")
	}
	a.reloadBusinessPage()
}

// bizDeleteQuickReply removes a shortcut (slice 139's engine surface).
func (a *App) bizDeleteQuickReply(id int) {
	a.mu.Lock()
	st := a.businessPage
	if st == nil || st.busy {
		a.mu.Unlock()
		return
	}
	acc := st.accountID
	st.busy = true
	st.editorErr = ""
	a.mu.Unlock()
	a.invalidate()

	err := a.eng.DeleteQuickReplyShortcut(acc, id)
	a.mu.Lock()
	if st = a.businessPage; st != nil {
		st.busy = false
		if err != nil {
			st.editorErr = err.Error()
		}
	}
	a.mu.Unlock()
	if err == nil {
		a.setToast("Shortcut deleted")
	}
	a.reloadBusinessPage()
}

// ── editor pool sync ─────────────────────────────────────────────────────

// bizEditorSlots counts the editor pairs the model needs (a closed day
// still renders one empty pair so it can be filled in).
func bizEditorSlots(w bizWeek) int {
	n := 0
	for _, ivls := range w {
		if len(ivls) == 0 {
			n += 2
		} else {
			n += 2 * len(ivls)
		}
	}
	return n
}

// bizSlotDay maps each time-editor index to its owning day; rebuilt by
// syncBizTimeEditors alongside the pool.
var bizSlotDay []int

// syncBizTimeEditors rebuilds the time-editor pool from the model
// (structure changes only — add/remove/24-7/reset/open).
func syncBizTimeEditors(w bizWeek) {
	n := bizEditorSlots(w)
	for len(bizTimeEds) < n {
		bizTimeEds = append(bizTimeEds, &widget.Editor{SingleLine: true})
	}
	bizTimeEds = bizTimeEds[:n]
	bizSlotDay = bizSlotDay[:0]
	i := 0
	for d, ivls := range w {
		if len(ivls) == 0 {
			bizTimeEds[i].SetText("")
			bizTimeEds[i+1].SetText("")
			bizSlotDay = append(bizSlotDay, d, d)
			i += 2
			continue
		}
		for _, iv := range ivls {
			bizTimeEds[i].SetText(bizFormatTime(iv.start))
			bizTimeEds[i+1].SetText(bizFormatTime(iv.end))
			bizSlotDay = append(bizSlotDay, d, d)
			i += 2
		}
	}
}

// bizWeekFromEditors parses the editor pool back into a week model
// (slot ownership comes from bizSlotDay — the pool layout is immutable
// between structural syncs).
func bizWeekFromEditors() (bizWeek, error) {
	var w bizWeek
	for i := 0; i+1 < len(bizTimeEds); i += 2 {
		d := -1
		if i/2 < len(bizSlotDay) {
			d = bizSlotDay[i]
		}
		if d < 0 || d > 6 {
			continue
		}
		sTxt, eTxt := bizTimeEds[i].Text(), bizTimeEds[i+1].Text()
		if strings.TrimSpace(sTxt) == "" && strings.TrimSpace(eTxt) == "" {
			continue // closed slot
		}
		s, okS := bizParseTime(sTxt)
		e, okE := bizParseTime(eTxt)
		if !okS || !okE {
			return w, fmt.Errorf("%s: invalid time (use 9:00 style)", bizDayNames[d])
		}
		if e <= s {
			return w, fmt.Errorf("%s: end must be after start", bizDayNames[d])
		}
		w[d] = append(w[d], bizIVL{start: s, end: e})
	}
	for d := range w {
		w[d] = normalizeBizIVLs(w[d])
	}
	return w, nil
}

// ── layout ───────────────────────────────────────────────────────────────

// layoutBusinessPage renders the Telegram Business sub-page.
func (a *App) layoutBusinessPage(gtx layout.Context, f frame) layout.Dimensions {
	st := f.businessPage
	if st == nil {
		return layout.Dimensions{}
	}
	if bizBackBtn.Clicked(gtx) {
		a.closeBusinessPage()
	}
	if bizReloadBtn.Clicked(gtx) {
		a.reloadBusinessPage()
	}
	if bizApplyBtn.Clicked(gtx) {
		a.bizApplyClicked(st)
	}
	if bizRemoveBtn.Clicked(gtx) {
		go a.removeBusinessFeature()
	}

	var children []layout.FlexChild
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return layout.Inset{Bottom: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					btn := a.ui.IconButton(&bizBackBtn, iconNavigationBack, "Back")
					return btn.Layout(gtx)
				}),
				layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
					lbl := a.ui.Label(unit.Sp(17), "Telegram Business")
					lbl.Font.Weight = font.SemiBold
					return lbl.Layout(gtx)
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					btn := a.ui.IconButton(&bizReloadBtn, iconActionSchedule, "Reload")
					return btn.Layout(gtx)
				}),
			)
		})
	}))

	// account switcher chips (multiple accounts only)
	if len(f.accounts) > 1 {
		growClickables(&bizAcctBtns, len(f.accounts))
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Bottom: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal}.Layout(gtx, a.bizAcctChips(gtx, f, st)...)
			})
		}))
	}

	if st.loading && !st.loaded {
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.loadingNote(gtx)
		}))
		return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
	}
	if st.err != "" {
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			lbl := a.ui.Dim(unit.Sp(13), st.err)
			return lbl.Layout(gtx)
		}))
		return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
	}

	// premium note: business features are Premium-gated server-side.
	if v, _ := st.info["premium"].(bool); !v {
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Bottom: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				lbl := a.ui.Dim(unit.Sp(12), "Business features require Telegram Premium; the page stays read-only until then.")
				return lbl.Layout(gtx)
			})
		}))
	}

	// section rows
	type section struct {
		key, title, sub string
		icon            *widget.Icon
	}
	secs := []section{
		{"location", "Location", bizLocationSub(st.info), iconMapsPlace},
		{"hours", "Opening hours", bizHoursSub(st.info), iconActionSchedule},
		{"greeting", "Greeting messages", bizGreetingSub(st.info), iconCommunicationChat},
		{"away", "Away messages", bizAwaySub(st.info), iconNavArrowDown},
		{"replies", "Quick replies", bizRepliesSub(st.replies), iconActionDone},
		{"intro", "Intro", bizIntroSub(st.info), iconActionInfo},
	}
	growClickables(&bizEditorBtns, len(secs))
	for i, sec := range secs {
		i, sec := i, sec
		if bizEditorBtns[i].Clicked(gtx) {
			a.bizToggleEditor(sec.key)
		}
		active := st.editor == sec.key
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				bl := material.ButtonLayout(a.ui.Theme, &bizEditorBtns[i])
				bl.Background = a.ui.p.Surface
				if active {
					bl.Background = a.ui.p.AccentDim
				}
				bl.CornerRadius = 10
				return bl.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.UniformInset(unit.Dp(10)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								return layout.Inset{Right: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
									return sec.icon.Layout(gtx, a.ui.p.Accent)
								})
							}),
							layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
								return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
									layout.Rigid(func(gtx layout.Context) layout.Dimensions {
										lbl := a.ui.Label(unit.Sp(14), sec.title)
										return lbl.Layout(gtx)
									}),
									layout.Rigid(func(gtx layout.Context) layout.Dimensions {
										if sec.sub == "" {
											return layout.Dimensions{}
										}
										lbl := a.ui.Dim(unit.Sp(11), sec.sub)
										return lbl.Layout(gtx)
									}),
								)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								return iconNavChevronRight.Layout(gtx, a.ui.p.TextDim)
							}),
						)
					})
				})
			})
		}))
		// the expanded editor body
		if active {
			children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return a.bizEditorBody(gtx, f, st, sec.key)
			}))
		}
	}

	// editor error + busy row
	if st.editorErr != "" {
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			lbl := a.ui.Dim(unit.Sp(12), st.editorErr)
			return lbl.Layout(gtx)
		}))
	}

	return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
}

// bizToggleEditor opens/closes a section editor (priming the widget
// state from the loaded read model on open).
func (a *App) bizToggleEditor(key string) {
	a.mu.Lock()
	st := a.businessPage
	if st == nil {
		a.mu.Unlock()
		return
	}
	if st.editor == key {
		st.editor = ""
		a.mu.Unlock()
		a.invalidate()
		return
	}
	st.editor = key
	st.editorErr = ""
	switch key {
	case "location":
		loc := bizSubMap(st.info, "location")
		bizAddrEd.SetText(mapStr(loc, "address"))
		lat, hasLat := mapFloat(loc, "lat")
		lon, hasLon := mapFloat(loc, "lon")
		if hasLat {
			bizLatEd.SetText(fmt.Sprintf("%g", lat))
		} else {
			bizLatEd.SetText("")
		}
		if hasLon {
			bizLonEd.SetText(fmt.Sprintf("%g", lon))
		} else {
			bizLonEd.SetText("")
		}
	case "hours":
		wh := bizSubMap(st.info, "work_hours")
		st.hours = bizWeekFromWire(mapSlice(wh, "weekly_open"))
		st.tzPick = mapStr(wh, "timezone_id")
		st.tzOpen = false
		syncBizTimeEditors(st.hours)
	case "greeting", "away":
		g := bizSubMap(st.info, key)
		st.recips.fromMap(g)
		bizMsgEd.SetText(mapStr(g, "message"))
		if key == "greeting" {
			st.inactDays = mapInt(g, "no_activity_days")
			if st.inactDays == 0 {
				st.inactDays = 7
			}
		} else {
			st.offline = mapBool(g, "offline_only")
			st.awayMode = mapStr(g, "schedule")
			if st.awayMode == "" {
				st.awayMode = "always"
			}
			if sd, ed := mapInt(g, "start_date"), mapInt(g, "end_date"); sd > 0 && ed > 0 {
				st.awayFrom = time.Unix(int64(sd), 0).UTC().Format("2006-01-02")
				st.awayTo = time.Unix(int64(ed), 0).UTC().Format("2006-01-02")
			}
			bizFromEd.SetText(st.awayFrom)
			bizToEd.SetText(st.awayTo)
			if st.awayMode == "custom" && st.awayFrom == "" {
				bizFromEd.SetText(time.Now().UTC().Format("2006-01-02"))
				bizToEd.SetText(time.Now().UTC().AddDate(0, 0, 7).Format("2006-01-02"))
			}
		}
	case "intro":
		in := bizSubMap(st.info, "intro")
		bizTitleEd.SetText(mapStr(in, "title"))
		bizDescEd.SetText(mapStr(in, "description"))
	case "replies":
		st.qrNewOpen = false
		st.qrRenameID = 0
	}
	a.mu.Unlock()
	a.invalidate()
}

// mapSlice digs the weekly_open slice out of the read model.
func mapSlice(m map[string]interface{}, k string) []interface{} {
	if m == nil {
		return nil
	}
	if v, ok := m[k].([]interface{}); ok {
		return v
	}
	return nil
}

// bizEditorBody renders the open editor's body.
func (a *App) bizEditorBody(gtx layout.Context, f frame, st *businessPageState, key string) layout.Dimensions {
	var children []layout.FlexChild
	switch key {
	case "location":
		children = append(children,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return a.bizFieldRow(gtx, &bizAddrEd, "Address (up to 96 chars)")
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						return a.bizFieldRow(gtx, &bizLatEd, "Latitude (optional)")
					}),
					layout.Rigid(layout.Spacer{Width: unit.Dp(8)}.Layout),
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						return a.bizFieldRow(gtx, &bizLonEd, "Longitude (optional)")
					}),
				)
			}),
		)
	case "hours":
		children = append(children, a.bizHoursEditor(gtx, st)...)
	case "greeting":
		children = append(children, a.bizMsgEditor(gtx, st, true)...)
	case "away":
		children = append(children, a.bizMsgEditor(gtx, st, false)...)
	case "intro":
		children = append(children,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return a.bizFieldRow(gtx, &bizTitleEd, "Title")
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return a.bizFieldRow(gtx, &bizDescEd, "Description")
			}),
		)
	case "replies":
		children = append(children, a.bizRepliesEditor(gtx, st)...)
	}
	// actions
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return layout.Inset{Top: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					if st.busy {
						return a.loadingNote(gtx)
					}
					btn := material.Button(a.ui.Theme, &bizApplyBtn, "Save")
					btn.Background = a.ui.p.Accent
					return btn.Layout(gtx)
				}),
				layout.Rigid(layout.Spacer{Width: unit.Dp(8)}.Layout),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					if key == "replies" {
						return layout.Dimensions{}
					}
					btn := material.Button(a.ui.Theme, &bizRemoveBtn, "Remove")
					btn.Background = a.ui.p.Error
					return btn.Layout(gtx)
				}),
			)
		})
	}))
	return layout.Inset{Left: unit.Dp(10), Bottom: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return roundedFill(gtx, a.ui.p.SurfaceHi, 10, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(10)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
			})
		})
	})
}

// bizFieldRow renders a labeled single editor line.
func (a *App) bizFieldRow(gtx layout.Context, ed *widget.Editor, hint string) layout.Dimensions {
	return layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		in := a.ui.Editor(ed, hint)
		return in.Layout(gtx)
	})
}

// bizHoursEditor renders the opening-hours editor body pieces.
func (a *App) bizHoursEditor(gtx layout.Context, st *businessPageState) []layout.FlexChild {
	if biz247Btn.Clicked(gtx) {
		a.mu.Lock()
		st.hours.set247()
		a.mu.Unlock()
		syncBizTimeEditors(st.hours)
		a.invalidate()
	}
	if bizTzToggleBtn.Clicked(gtx) {
		a.mu.Lock()
		st.tzOpen = !st.tzOpen
		if st.tzOpen {
			bizTzSearch.SetText("")
		}
		a.mu.Unlock()
		a.invalidate()
	}
	growClickables(&bizAddIvlBtns, 7)
	growClickables(&bizDelIvlBtns, 7)
	growClickables(&bizDayChips, 3)

	var children []layout.FlexChild
	// quick presets + timezone row
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return layout.Inset{Bottom: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					btn := material.Button(a.ui.Theme, &biz247Btn, "24/7")
					btn.Background = a.ui.p.AccentDim
					btn.Color = a.ui.p.Text
					return btn.Layout(gtx)
				}),
				layout.Rigid(layout.Spacer{Width: unit.Dp(8)}.Layout),
				layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
					lbl := a.ui.Label(unit.Sp(13), "Timezone: "+bizTzLabel(st))
					return lbl.Layout(gtx)
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					btn := a.ui.TextButton(&bizTzToggleBtn, "Change")
					btn.Color = a.ui.p.Accent
					return btn.Layout(gtx)
				}),
			)
		})
	}))
	// timezone picker (expanded)
	if st.tzOpen {
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Bottom: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return roundedFill(gtx, a.ui.p.Surface, 10, func(gtx layout.Context) layout.Dimensions {
					return layout.UniformInset(unit.Dp(8)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						return a.bizTzPicker(gtx, st)
					})
				})
			})
		}))
	}
	// per-day rows
	i := 0
	for d := 0; d < 7; d++ {
		d := d
		ivls := st.hours[d]
		if bizAddIvlBtns[d].Clicked(gtx) {
			a.mu.Lock()
			st.hours[d] = append(st.hours[d], bizIVL{start: 9 * 60, end: 17 * 60})
			a.mu.Unlock()
			syncBizTimeEditors(st.hours)
			a.invalidate()
		}
		if bizDelIvlBtns[d].Clicked(gtx) && len(st.hours[d]) > 0 {
			a.mu.Lock()
			st.hours[d] = st.hours[d][:len(st.hours[d])-1]
			a.mu.Unlock()
			syncBizTimeEditors(st.hours)
			a.invalidate()
		}
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(3), Bottom: unit.Dp(3)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						gtx.Constraints.Min.X = gtx.Dp(unit.Dp(86))
						lbl := a.ui.Label(unit.Sp(13), bizDayNames[d])
						return lbl.Layout(gtx)
					}),
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						// render this day's editor pairs
						n := len(ivls)
						if n == 0 {
							return a.bizTimePair(gtx, i)
						}
						var rows []layout.FlexChild
						for k := 0; k < n; k++ {
							k := k
							rows = append(rows, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								return a.bizTimePair(gtx, i+k)
							}))
						}
						return layout.Flex{Axis: layout.Vertical}.Layout(gtx, rows...)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						btn := a.ui.IconButton(&bizAddIvlBtns[d], iconContentAdd, "Add interval")
						return btn.Layout(gtx)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if len(ivls) == 0 {
							return layout.Dimensions{}
						}
						btn := a.ui.IconButton(&bizDelIvlBtns[d], iconContentClear, "Remove interval")
						return btn.Layout(gtx)
					}),
				)
			})
		}))
		if len(ivls) == 0 {
			i += 2
		} else {
			i += 2 * len(ivls)
		}
	}
	return children
}

// bizTimePair renders one start/end editor pair from the pool.
func (a *App) bizTimePair(gtx layout.Context, idx int) layout.Dimensions {
	if idx+1 >= len(bizTimeEds) {
		return layout.Dimensions{}
	}
	return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
		layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
			for {
				ev, ok := bizTimeEds[idx].Update(gtx)
				if !ok {
					break
				}
				if _, is := ev.(widget.ChangeEvent); is {
					a.invalidate()
				}
			}
			in := a.ui.Editor(bizTimeEds[idx], "09:00")
			return in.Layout(gtx)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			lbl := a.ui.Dim(unit.Sp(12), "–")
			return layout.Inset{Left: unit.Dp(4), Right: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return lbl.Layout(gtx)
			})
		}),
		layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
			for {
				ev, ok := bizTimeEds[idx+1].Update(gtx)
				if !ok {
					break
				}
				if _, is := ev.(widget.ChangeEvent); is {
					a.invalidate()
				}
			}
			in := a.ui.Editor(bizTimeEds[idx+1], "17:00")
			return in.Layout(gtx)
		}),
	)
}

// bizTzLabel renders the picked timezone (or the honest fallback).
func bizTzLabel(st *businessPageState) string {
	if st.tzPick == "" {
		return "not set"
	}
	for _, tz := range st.timezones {
		if tz.ID == st.tzPick {
			return tz.Name + " (" + bizUtcLabel(tz.UtcOffset) + ")"
		}
	}
	return st.tzPick
}

// bizTzPicker renders the searchable timezone list.
func (a *App) bizTzPicker(gtx layout.Context, st *businessPageState) layout.Dimensions {
	for {
		ev, ok := bizTzSearch.Update(gtx)
		if !ok {
			break
		}
		if _, is := ev.(widget.ChangeEvent); is {
			a.invalidate()
		}
	}
	var rows []cores.TimezoneInfo
	q := strings.ToLower(bizTzSearch.Text())
	for _, tz := range st.timezones {
		if q == "" || strings.Contains(strings.ToLower(tz.Name), q) || strings.Contains(strings.ToLower(tz.ID), q) {
			rows = append(rows, tz)
		}
	}
	growClickables(&bizTzRowBtns, len(rows))
	children := []layout.FlexChild{
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Bottom: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return roundedFill(gtx, a.ui.p.SurfaceHi, 10, func(gtx layout.Context) layout.Dimensions {
					return layout.UniformInset(unit.Dp(6)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								return layout.Inset{Right: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
									return iconActionSearch.Layout(gtx, a.ui.p.TextDim)
								})
							}),
							layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
								ed := a.ui.Editor(&bizTzSearch, "Search timezones")
								return ed.Layout(gtx)
							}),
						)
					})
				})
			})
		}),
	}
	if len(rows) == 0 {
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.centeredStateLabel(gtx, "No timezones found")
		}))
	} else {
		list := material.List(a.ui.Theme, &bizScroll)
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			gtx.Constraints.Max.Y = gtx.Dp(unit.Dp(240))
			return list.Layout(gtx, len(rows), func(gtx layout.Context, i int) layout.Dimensions {
				tz := rows[i]
				if bizTzRowBtns[i].Clicked(gtx) {
					a.mu.Lock()
					st.tzPick = tz.ID
					st.tzOpen = false
					a.mu.Unlock()
					a.invalidate()
				}
				active := st.tzPick == tz.ID
				return layout.Inset{Top: unit.Dp(2), Bottom: unit.Dp(2)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					bl := material.ButtonLayout(a.ui.Theme, &bizTzRowBtns[i])
					bl.Background = a.ui.p.Surface
					if active {
						bl.Background = a.ui.p.AccentDim
					}
					bl.CornerRadius = 8
					return bl.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						return layout.UniformInset(unit.Dp(6)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
								layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
									return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
										layout.Rigid(func(gtx layout.Context) layout.Dimensions {
											lbl := a.ui.Label(unit.Sp(13), tz.Name)
											return lbl.Layout(gtx)
										}),
										layout.Rigid(func(gtx layout.Context) layout.Dimensions {
											lbl := a.ui.Dim(unit.Sp(10), tz.ID+" · "+bizUtcLabel(tz.UtcOffset))
											return lbl.Layout(gtx)
										}),
									)
								}),
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									if !active {
										return layout.Dimensions{}
									}
									return iconActionDone.Layout(gtx, a.ui.p.Accent)
								}),
							)
						})
					})
				})
			})
		}))
	}
	return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
}

// bizMsgEditor renders the greeting (or away) message editor body.
func (a *App) bizMsgEditor(gtx layout.Context, st *businessPageState, greeting bool) []layout.FlexChild {
	var children []layout.FlexChild
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		for {
			ev, ok := bizMsgEd.Update(gtx)
			if !ok {
				break
			}
			if _, is := ev.(widget.ChangeEvent); is {
				a.invalidate()
			}
		}
		hint := "Message text"
		if greeting {
			hint = "Greeting message sent to new private chats"
		} else {
			hint = "Away message sent while you cannot answer"
		}
		in := a.ui.Editor(&bizMsgEd, hint)
		return in.Layout(gtx)
	}))
	// recipients
	labels := []string{"New chats", "Existing chats", "Contacts", "Non-contacts"}
	growBools(&bizRecChks, 4)
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return layout.Inset{Top: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					lbl := a.ui.Label(unit.Sp(13), "Recipients")
					lbl.Font.Weight = font.SemiBold
					return lbl.Layout(gtx)
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					var rows []layout.FlexChild
					for i, label := range labels {
						i, label := i, label
						rows = append(rows, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							chk := material.CheckBox(a.ui.Theme, &bizRecChks[i], label)
							return chk.Layout(gtx)
						}))
					}
					rows = append(rows, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						chk := material.CheckBox(a.ui.Theme, &bizExcludeChk, "Except the selected")
						return chk.Layout(gtx)
					}))
					return layout.Flex{Axis: layout.Vertical}.Layout(gtx, rows...)
				}),
			)
		})
	}))
	if greeting {
		// inactivity picker
		growClickables(&bizInactChips, 4)
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.Label(unit.Sp(13), "Send to chats inactive for")
						lbl.Font.Weight = font.SemiBold
						return lbl.Layout(gtx)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Horizontal}.Layout(gtx, a.bizChipRow(gtx, st, []string{"7", "14", "21", "28"}, func(sel string) {
							if n, err := strconv.Atoi(sel); err == nil {
								st.inactDays = n
							}
						}, func(sel string) bool {
							return st.inactDays == mustAtoi(sel)
						}, &bizInactChips)...)
					}),
				)
			})
		}))
	} else {
		// schedule + offline toggle
		growClickables(&bizAwayChips, 3)
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.Label(unit.Sp(13), "Schedule")
						lbl.Font.Weight = font.SemiBold
						return lbl.Layout(gtx)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Horizontal}.Layout(gtx, a.bizChipRow(gtx, st, []string{"Always", "Outside opening hours", "Custom"}, func(sel string) {
							switch sel {
							case "Always":
								st.awayMode = "always"
							case "Outside opening hours":
								st.awayMode = "outside_work_hours"
							case "Custom":
								if st.awayMode != "custom" {
									st.awayMode = "custom"
									if bizFromEd.Text() == "" {
										bizFromEd.SetText(time.Now().UTC().Format("2006-01-02"))
										bizToEd.SetText(time.Now().UTC().AddDate(0, 0, 7).Format("2006-01-02"))
									}
								}
							}
						}, func(sel string) bool {
							switch sel {
							case "Always":
								return st.awayMode == "always" || st.awayMode == ""
							case "Outside opening hours":
								return st.awayMode == "outside_work_hours"
							default:
								return st.awayMode == "custom"
							}
						}, &bizAwayChips)...)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if st.awayMode != "custom" {
							return layout.Dimensions{}
						}
						return layout.Inset{Top: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
								layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
									return a.bizFieldRow(gtx, &bizFromEd, "From (YYYY-MM-DD)")
								}),
								layout.Rigid(layout.Spacer{Width: unit.Dp(8)}.Layout),
								layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
									return a.bizFieldRow(gtx, &bizToEd, "To (YYYY-MM-DD)")
								}),
							)
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						chk := material.CheckBox(a.ui.Theme, &bizOfflineChk, "Send only when offline")
						return chk.Layout(gtx)
					}),
				)
			})
		}))
	}
	return children
}

// mustAtoi is strconv.Atoi with a 0 default.
func mustAtoi(s string) int {
	n, _ := strconv.Atoi(s)
	return n
}

// growBools grows a checkbox pool.
func growBools(pool *[]widget.Bool, n int) {
	for len(*pool) < n {
		*pool = append(*pool, widget.Bool{})
	}
}

// bizChipRow renders a horizontal chip selector.
func (a *App) bizChipRow(gtx layout.Context, st *businessPageState, options []string,
	onPick func(sel string), active func(sel string) bool, pool *[]widget.Clickable) []layout.FlexChild {
	growClickables(pool, len(options))
	var children []layout.FlexChild
	for i, opt := range options {
		i, opt := i, opt
		if (*pool)[i].Clicked(gtx) {
			onPick(opt)
			a.invalidate()
		}
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Right: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				bl := material.ButtonLayout(a.ui.Theme, &(*pool)[i])
				bl.CornerRadius = 14
				if active(opt) {
					bl.Background = a.ui.p.Accent
				} else {
					bl.Background = a.ui.p.Surface
				}
				return bl.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.UniformInset(unit.Dp(6)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.Label(unit.Sp(12), opt)
						if active(opt) {
							lbl.Color = a.ui.p.Background
						}
						return lbl.Layout(gtx)
					})
				})
			})
		}))
	}
	return children
}

// bizRepliesEditor renders the quick-reply manager body.
func (a *App) bizRepliesEditor(gtx layout.Context, st *businessPageState) []layout.FlexChild {
	if bizQRNewBtn.Clicked(gtx) {
		a.mu.Lock()
		st.qrNewOpen = !st.qrNewOpen
		if st.qrNewOpen {
			bizQRNameEd.SetText("")
			bizQRTextEd.SetText("")
		}
		a.mu.Unlock()
		a.invalidate()
	}
	if bizQRCancel.Clicked(gtx) {
		a.mu.Lock()
		st.qrNewOpen = false
		a.mu.Unlock()
		a.invalidate()
	}
	if bizQRCreate.Clicked(gtx) {
		go a.bizCreateQuickReply(bizQRNameEd.Text(), bizQRTextEd.Text())
	}
	if bizQRUpdBtn.Clicked(gtx) {
		go a.bizRenameQuickReply(st.qrRenameID, bizQRNameEd.Text())
	}
	growClickables(&bizQRRows, len(st.replies))
	growClickables(&bizQRRenBtns, len(st.replies))
	growClickables(&bizQRDelBtns, len(st.replies))

	var children []layout.FlexChild
	// new-shortcut row
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return layout.Inset{Bottom: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			btn := material.Button(a.ui.Theme, &bizQRNewBtn, "New shortcut")
			btn.Background = a.ui.p.AccentDim
			btn.Color = a.ui.p.Text
			return btn.Layout(gtx)
		})
	}))
	if st.qrNewOpen {
		children = append(children,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return a.bizFieldRow(gtx, &bizQRNameEd, "Shortcut name (up to 12 chars)")
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return a.bizFieldRow(gtx, &bizQRTextEd, "Message text")
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							btn := material.Button(a.ui.Theme, &bizQRCreate, "Create")
							btn.Background = a.ui.p.Accent
							return btn.Layout(gtx)
						}),
						layout.Rigid(layout.Spacer{Width: unit.Dp(8)}.Layout),
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							btn := a.ui.TextButton(&bizQRCancel, "Cancel")
							btn.Color = a.ui.p.TextDim
							return btn.Layout(gtx)
						}),
					)
				})
			}),
		)
	}
	// shortcut rows
	if len(st.replies) == 0 && !st.qrNewOpen {
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.centeredStateLabel(gtx, "No quick reply shortcuts")
		}))
	}
	for i, q := range st.replies {
		i, q := i, q
		if bizQRRenBtns[i].Clicked(gtx) && st.qrRenameID != q.ID {
			a.mu.Lock()
			st.qrRenameID = q.ID
			bizQRNameEd.SetText(q.Name)
			a.mu.Unlock()
			a.invalidate()
		}
		if bizQRDelBtns[i].Clicked(gtx) {
			go a.bizDeleteQuickReply(q.ID)
		}
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(3), Bottom: unit.Dp(3)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return roundedFill(gtx, a.ui.p.Surface, 10, func(gtx layout.Context) layout.Dimensions {
					return layout.UniformInset(unit.Dp(8)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						if st.qrRenameID == q.ID {
							return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									return a.bizFieldRow(gtx, &bizQRNameEd, "New name")
								}),
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
										layout.Rigid(func(gtx layout.Context) layout.Dimensions {
											btn := material.Button(a.ui.Theme, &bizQRUpdBtn, "Rename")
											btn.Background = a.ui.p.Accent
											return btn.Layout(gtx)
										}),
										layout.Rigid(layout.Spacer{Width: unit.Dp(8)}.Layout),
										layout.Rigid(func(gtx layout.Context) layout.Dimensions {
											btn := a.ui.TextButton(&bizQRCancel, "Cancel")
											btn.Color = a.ui.p.TextDim
											return btn.Layout(gtx)
										}),
									)
								}),
							)
						}
						return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
							layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
								return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
									layout.Rigid(func(gtx layout.Context) layout.Dimensions {
										lbl := a.ui.Label(unit.Sp(14), "/"+q.Name)
										return lbl.Layout(gtx)
									}),
									layout.Rigid(func(gtx layout.Context) layout.Dimensions {
										sub := fmt.Sprintf("%d message", q.Count)
										if q.Count != 1 {
											sub += "s"
										}
										if q.TopMessage != "" {
											sub += " · " + q.TopMessage
										}
										lbl := a.ui.Dim(unit.Sp(11), sub)
										return lbl.Layout(gtx)
									}),
								)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								btn := a.ui.TextButton(&bizQRRenBtns[i], "Rename")
								btn.Color = a.ui.p.Accent
								btn.TextSize = unit.Sp(13)
								return btn.Layout(gtx)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								btn := a.ui.TextButton(&bizQRDelBtns[i], "Delete")
								btn.Color = a.ui.p.Error
								btn.TextSize = unit.Sp(13)
								return btn.Layout(gtx)
							}),
						)
					})
				})
			})
		}))
	}
	return children
}

// bizAcctChips renders the account switcher chips.
func (a *App) bizAcctChips(gtx layout.Context, f frame, st *businessPageState) []layout.FlexChild {
	var children []layout.FlexChild
	for i, acc := range f.accounts {
		i, acc := i, acc
		if bizAcctBtns[i].Clicked(gtx) {
			a.openBusinessPage(acc.ID)
		}
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			bg := a.ui.p.Surface
			txtCol := a.ui.p.TextDim
			if acc.ID == st.accountID {
				bg = a.ui.p.AccentDim
				txtCol = a.ui.p.Accent
			}
			return layout.Inset{Right: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				bl := material.ButtonLayout(a.ui.Theme, &bizAcctBtns[i])
				bl.Background = bg
				bl.CornerRadius = 14
				return bl.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.UniformInset(unit.Dp(6)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.Label(unit.Sp(12), accountName(acc))
						lbl.Color = txtCol
						return lbl.Layout(gtx)
					})
				})
			})
		}))
	}
	return children
}

// ── section subtitles (honest state summaries) ───────────────────────────

func bizLocationSub(info map[string]interface{}) string {
	loc := bizSubMap(info, "location")
	if loc == nil {
		return "Not set"
	}
	return mapStr(loc, "address")
}

func bizHoursSub(info map[string]interface{}) string {
	wh := bizSubMap(info, "work_hours")
	if wh == nil {
		return "Not set"
	}
	w := bizWeekFromWire(mapSlice(wh, "weekly_open"))
	sub := w.summary()
	if tz := mapStr(wh, "timezone_id"); tz != "" {
		sub += " · " + tz
	}
	return sub
}

func bizGreetingSub(info map[string]interface{}) string {
	g := bizSubMap(info, "greeting")
	if g == nil {
		return "Off"
	}
	msg := mapStr(g, "message")
	if msg == "" {
		return "On"
	}
	return msg
}

func bizAwaySub(info map[string]interface{}) string {
	aw := bizSubMap(info, "away")
	if aw == nil {
		return "Off"
	}
	msg := mapStr(aw, "message")
	switch mapStr(aw, "schedule") {
	case "outside_work_hours":
		msg += " · outside hours"
	case "custom":
		msg += " · custom"
	}
	return msg
}

func bizRepliesSub(replies []cores.QuickReplyInfo) string {
	if len(replies) == 0 {
		return "No shortcuts"
	}
	return fmt.Sprintf("%d shortcuts", len(replies))
}

func bizIntroSub(info map[string]interface{}) string {
	in := bizSubMap(info, "intro")
	if in == nil {
		return "Not set"
	}
	return mapStr(in, "title")
}

// ── Settings → Main entry card ───────────────────────────────────────────

// businessEntryRow renders the Settings → Main entry card.
func (a *App) businessEntryRow(gtx layout.Context, f frame) layout.Dimensions {
	if bizOpenBtn.Clicked(gtx) {
		a.openBusinessPage(mgrAccountID(f))
	}
	return layout.Inset{Top: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return roundedFill(gtx, a.ui.p.Surface, 10, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(10)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Right: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return iconActionOfflinePin.Layout(gtx, a.ui.p.Accent)
						})
					}),
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Label(unit.Sp(14), "Telegram Business")
								return lbl.Layout(gtx)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Dim(unit.Sp(11), "Hours, location, greeting, away messages, quick replies")
								return lbl.Layout(gtx)
							}),
						)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return iconNavChevronRight.Layout(gtx, a.ui.p.TextDim)
					}),
				)
			})
		})
	})
}
