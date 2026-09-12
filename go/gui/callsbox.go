package gui

import (
	"image"
	"image/color"
	"strconv"
	"time"

	"gioui.org/io/event"
	"gioui.org/io/key"
	"gioui.org/io/pointer"
	"gioui.org/layout"
	"gioui.org/op"
	"gioui.org/op/clip"
	"gioui.org/op/paint"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"golang.org/x/exp/shiny/materialdesign/icons"

	"uniclient/engine"
)

// The Calls box (AyuGram parity slice 154): tdesktop's calls_box_controller
// 1:1 — a per-account "Calls" page opened from the drawer, listing the call
// history from messages.search(inputMessagesFilterPhoneCalls) as rows
// grouped by peer × calendar day × direction (in / out / missed), with the
// redial action, show-in-chat jump, per-group delete, and the Clear-all flow
// (messages.deletePhoneCallHistory + revoke). Chats with an active group
// call render in a subsection above the history. Pure tdesktop behavior:
// no search field, tdesktop's box has none; the drawer entry and the box
// copy match its strings ("Calls", "Today at …", "3 calls, last …",
// "No calls here yet").

// Direction arrows (tdesktop callArrowIn/Out/Missed → Material icons).
var (
	iconCallMade     = mustIcon(icons.CommunicationCallMade)
	iconCallReceived = mustIcon(icons.CommunicationCallReceived)
	iconCallMissed   = mustIcon(icons.CommunicationCallMissed)
)

// callDir is the row's direction class (tdesktop BoxController::Row::Type).
type callDir int

const (
	callDirIn  callDir = iota // received
	callDirOut                // made
	callDirMissed
)

// callDirOf maps an entry to its direction class: outgoing beats missed
// (tdesktop ComputeType: item->out() first, then Busy/Missed reasons).
func callDirOf(e engine.CallHistoryEntry) callDir {
	if e.IsOutgoing {
		return callDirOut
	}
	if e.IsMissed {
		return callDirMissed
	}
	return callDirIn
}

// callBoxRow is one grouped row: every call between the same peer on the
// same calendar day with the same direction collapses into it (tdesktop
// Row::canAddItem), showing "N calls, last …" when the group is plural.
type callBoxRow struct {
	PeerID     string
	PeerName   string
	AvatarPath string
	Dir        callDir
	Video      bool // redial icon from the latest entry
	Last       engine.CallHistoryEntry
	MsgIDs     []string
	Count      int
}

// groupCallEntries groups call-history entries (newest→oldest, the
// messages.search order) into rows. Entries on different days, with
// different directions, or from different peers never merge; rows are
// ordered newest-first by message ID.
func groupCallEntries(entries []engine.CallHistoryEntry) []callBoxRow {
	if len(entries) == 0 {
		return nil
	}
	type key struct {
		peer string
		day  string
		dir  callDir
	}
	order := make([]key, 0, len(entries))
	groups := make(map[key]*callBoxRow, len(entries))
	for _, e := range entries {
		k := key{peer: e.PeerID, day: time.Unix(e.Timestamp, 0).Format("2006-01-02"), dir: callDirOf(e)}
		if g, ok := groups[k]; ok {
			g.MsgIDs = append(g.MsgIDs, e.MsgID)
			g.Count++
			continue
		}
		g := &callBoxRow{
			PeerID:     e.PeerID,
			PeerName:   e.PeerName,
			AvatarPath: e.AvatarPath,
			Dir:        k.dir,
			Video:      e.IsVideo,
			Last:       e,
			MsgIDs:     []string{e.MsgID},
			Count:      1,
		}
		groups[k] = g
		order = append(order, k)
	}
	rows := make([]callBoxRow, 0, len(order))
	for _, k := range order {
		rows = append(rows, *groups[k])
	}
	// Newest-first by numeric message ID (tdesktop sorts rows by maxItemId).
	sortCallBoxRows(rows)
	return rows
}

// sortCallBoxRows orders rows newest-first by the group's newest message ID.
func sortCallBoxRows(rows []callBoxRow) {
	for i := 1; i < len(rows); i++ {
		for j := i; j > 0; j-- {
			if callBoxRowID(rows[j]) <= callBoxRowID(rows[j-1]) {
				break
			}
			rows[j], rows[j-1] = rows[j-1], rows[j]
		}
	}
}

func callBoxRowID(r callBoxRow) int {
	id, _ := strconv.Atoi(r.Last.MsgID)
	return id
}

// callBoxStatus renders the row's secondary line, tdesktop phrases:
// "Today at 15:04" / "Yesterday at 15:04" / "21 Aug at 15:04", and
// "3 calls, last today at 15:04" for merged groups.
func callBoxStatus(r callBoxRow, now time.Time) string {
	if r.Last.Timestamp <= 0 {
		return ""
	}
	t := time.Unix(r.Last.Timestamp, 0)
	var when string
	switch day := t.Format("2006-01-02"); {
	case day == now.Format("2006-01-02"):
		when = "Today at " + t.Format("15:04")
	case day == now.AddDate(0, 0, -1).Format("2006-01-02"):
		when = "Yesterday at " + t.Format("15:04")
	default:
		when = t.Format("2 Jan") + " at " + t.Format("15:04")
	}
	if r.Count > 1 {
		lower := when
		if len(lower) > 0 && lower[0] >= 'A' && lower[0] <= 'Z' {
			lower = string(lower[0]|0x20) + lower[1:] // "3 calls, last today at …"
		}
		return strconv.Itoa(r.Count) + " calls, last " + lower
	}
	return when
}

// callsBoxNextOffset returns the pagination offset for the next page: the
// oldest message ID across all loaded rows (messages.search offset_id is
// exclusive — strictly older results).
func callsBoxNextOffset(rows []callBoxRow) int {
	min := 0
	for _, r := range rows {
		for _, id := range r.MsgIDs {
			if n, err := strconv.Atoi(id); err == nil && (min == 0 || n < min) {
				min = n
			}
		}
	}
	return min
}

// callsBoxMenuItems derives the header ⋮ menu rows (pure, tested): call
// settings always; "Clear all" only with something to clear (tdesktop adds
// it only when the list is non-empty, attention-styled).
func callsBoxMenuItems(rowCount int) []string {
	items := []string{"Call settings"}
	if rowCount > 0 {
		items = append(items, "Clear all")
	}
	return items
}

// ── widgets ──────────────────────────────────────────────────────────────

var (
	callsBoxList     widget.List
	callsBoxBackBtn  widget.Clickable
	callsBoxMenuBtn  widget.Clickable
	callsBoxMenuRow  []widget.Clickable // header ⋮ menu rows
	callsBoxRowBtns  []widget.Clickable // history rows
	callsBoxRedial   []widget.Clickable // redial actions
	callsBoxGcRow    []widget.Clickable // group-call rows
	callsBoxGcJoin   []widget.Clickable // group-call join actions
	callsCtxMenuRow  []widget.Clickable // row context menu rows
	callsClearOK     widget.Clickable
	callsClearCancel widget.Clickable
	callsClearRevoke widget.Bool // "Also delete for everyone"
	callsDelOK       widget.Clickable
	callsDelCancel   widget.Clickable
	callsDelRevoke   widget.Bool
)

func init() {
	callsBoxList.Axis = layout.Vertical
}

// callsBoxKeyTag consumes Escape while the page is open (self-handled,
// per escTarget's contract).
var callsBoxKeyTag = new(struct{})

// callsBoxPaneTag receives pointer presses across the calls box so
// right-clicks open the row context menu anchored at the cursor (the
// chatPaneTag pattern), and any press outside an open menu dismisses it.
var callsBoxPaneTag = new(struct{})

// callsBoxMenuTarget is the open header ⋮ menu (anchor position).
type callsBoxMenuTarget struct{ pos image.Point }

// callsRowMenuTarget is the open row context menu (row index + anchor).
type callsRowMenuTarget struct {
	row int
	pos image.Point
}

// ── state transitions ────────────────────────────────────────────────────

// openCallsBox opens the Calls page for an account and loads the first
// page (tdesktop kFirstPageCount = 20).
func (a *App) openCallsBox(accountID string) {
	a.mu.Lock()
	a.callsBoxOpen = true
	a.callsBoxFor = accountID
	a.callsBoxRows = nil
	a.callsBoxBusy = true
	a.callsBoxDone = false
	a.callsBoxLoad = true
	a.callsBoxMenu = nil
	a.callsRowMenu = nil
	a.callsClearDlg = false
	a.callsDelDlg = -1
	a.mu.Unlock()
	a.invalidate()
	a.loadCallsBoxPage(accountID, 0, 20)
}

// closeCallsBox dismisses the page and its sub-surfaces.
func (a *App) closeCallsBox() {
	a.mu.Lock()
	a.callsBoxOpen = false
	a.callsBoxMenu = nil
	a.callsRowMenu = nil
	a.callsClearDlg = false
	a.callsDelDlg = -1
	a.mu.Unlock()
	a.invalidate()
}

// loadCallsBoxPage fetches one page of call history at offsetID, groups it
// into rows, and appends (first page replaces). Entries are filtered to
// strictly-older-than-offset as a dedupe guard; a short or empty page marks
// the history exhausted.
func (a *App) loadCallsBoxPage(accountID string, offsetID, limit int) {
	go func() {
		entries, err := a.eng.GetCallHistory(accountID, offsetID, limit)
		a.mu.Lock()
		first := offsetID == 0
		if err != nil {
			a.callsBoxBusy = false
			a.callsBoxLoad = false
			a.mu.Unlock()
			a.setToast("Calls: " + err.Error())
			return
		}
		if offsetID > 0 {
			kept := entries[:0]
			for _, e := range entries {
				if id, convErr := strconv.Atoi(e.MsgID); convErr == nil && id < offsetID {
					kept = append(kept, e)
				}
			}
			entries = kept
		}
		if len(entries) < limit {
			a.callsBoxDone = true
		}
		if len(entries) > 0 {
			merged := append(a.callsBoxRows, groupCallEntries(entries)...)
			sortCallBoxRows(merged)
			a.callsBoxRows = merged
		} else if first {
			a.callsBoxRows = nil
		}
		a.callsBoxBusy = false
		a.callsBoxLoad = false
		a.mu.Unlock()
		a.invalidate()
	}()
}

// loadCallsBoxMore loads the next page (tdesktop kPerPageCount = 100) when
// the list scrolls to its end and more history may exist.
func (a *App) loadCallsBoxMore() {
	a.mu.Lock()
	if a.callsBoxBusy || a.callsBoxDone || !a.callsBoxOpen {
		a.mu.Unlock()
		return
	}
	offset := callsBoxNextOffset(a.callsBoxRows)
	accountID := a.callsBoxFor
	a.callsBoxBusy = true
	a.mu.Unlock()
	if offset <= 0 {
		// No ids loaded yet — nothing to paginate from.
		a.mu.Lock()
		a.callsBoxBusy = false
		a.mu.Unlock()
		return
	}
	a.loadCallsBoxPage(accountID, offset, 100)
}

// clearCallsBoxAll runs the Clear-all flow: deletePhoneCallHistory (revoke
// honored), then reload the first page (tdesktop ClearCallsBox).
func (a *App) clearCallsBoxAll(revoke bool) {
	a.mu.Lock()
	acc := a.callsBoxFor
	a.callsClearDlg = false
	a.callsRowMenu = nil
	a.callsBoxRows = nil
	a.callsBoxBusy = true
	a.callsBoxDone = false
	a.callsBoxLoad = true
	a.mu.Unlock()
	a.invalidate()
	go func() {
		if err := a.eng.ClearCallHistory(acc, revoke); err != nil {
			a.setToast("Clear call history: " + err.Error())
			return
		}
		a.setToast("Call history cleared")
	}()
	a.loadCallsBoxPage(acc, 0, 20)
}

// deleteCallsBoxGroup deletes one row's call messages (tdesktop row context
// menu → DeleteMessagesBox; revoke honored per checkbox), then drops the
// row locally.
func (a *App) deleteCallsBoxGroup(idx int, revoke bool) {
	a.mu.Lock()
	if idx < 0 || idx >= len(a.callsBoxRows) {
		a.mu.Unlock()
		return
	}
	row := a.callsBoxRows[idx]
	a.callsDelDlg = -1
	a.callsRowMenu = nil
	a.callsBoxRows = append(a.callsBoxRows[:idx], a.callsBoxRows[idx+1:]...)
	acc := a.callsBoxFor
	a.mu.Unlock()
	a.invalidate()
	go func() {
		ok := 0
		for _, id := range row.MsgIDs {
			if err := a.eng.DeleteMessage(acc, row.PeerID, id, revoke); err != nil {
				continue
			}
			ok++
		}
		if ok == 0 {
			a.setToast("Delete call entries failed")
			return
		}
	}()
}

// redialCallsBoxRow starts an outgoing 1:1 call to the row's peer (tdesktop
// right action; camera icon for video rows).
func (a *App) redialCallsBoxRow(idx int) {
	a.mu.Lock()
	if idx < 0 || idx >= len(a.callsBoxRows) {
		a.mu.Unlock()
		return
	}
	row := a.callsBoxRows[idx]
	acc := a.callsBoxFor
	a.mu.Unlock()
	peer := engine.ChatInfo{AccountID: acc, ChatID: row.PeerID, Title: row.PeerName}
	a.startDMCall(peer, row.Video)
}

// openCallsBoxPeer opens the row's chat and jumps to the latest call
// message (tdesktop rowClicked → showPeerHistory at maxItemId).
func (a *App) openCallsBoxPeer(idx int) {
	a.mu.Lock()
	if idx < 0 || idx >= len(a.callsBoxRows) {
		a.mu.Unlock()
		return
	}
	row := a.callsBoxRows[idx]
	acc := a.callsBoxFor
	chats := a.chats
	a.mu.Unlock()
	var chat engine.ChatInfo
	found := false
	for _, c := range chats {
		if c.AccountID == acc && c.ChatID == row.PeerID {
			chat, found = c, true
			break
		}
	}
	if !found {
		a.setToast("Call peer not in your chat list")
		return
	}
	a.closeCallsBox()
	a.openChat(chatKey{AccountID: acc, ChatID: row.PeerID}, chat.Title)
	a.jumpToMessageAt(row.Last.MsgID, row.Last.Timestamp)
}

// ── layout ───────────────────────────────────────────────────────────────

// layoutCallsBox renders the whole Calls page: header (back, title, ⋮),
// group-calls subsection (when any chat of this account has an active
// call), the grouped history list with redial actions, and the confirm
// dialogs. Esc closes; right-click opens the row context menu.
func (a *App) layoutCallsBox(gtx layout.Context, f frame) layout.Dimensions {
	// Esc layer (self-handled, per escTarget's contract).
	{
		stack := clip.Rect{Max: gtx.Constraints.Max}.Push(gtx.Ops)
		event.Op(gtx.Ops, callsBoxKeyTag)
		stack.Pop()
	}
	for {
		ev, ok := gtx.Source.Event(key.Filter{Name: key.NameEscape})
		if !ok {
			break
		}
		if ke, is := ev.(key.Event); is && ke.State == key.Press {
			a.closeCallsBox()
			return layout.Dimensions{Size: gtx.Constraints.Max}
		}
	}

	// Header events.
	if callsBoxBackBtn.Clicked(gtx) {
		a.closeCallsBox()
	}
	if callsBoxMenuBtn.Clicked(gtx) {
		a.mu.Lock()
		if a.callsBoxMenu != nil {
			a.callsBoxMenu = nil
		} else {
			a.callsBoxMenu = &callsBoxMenuTarget{pos: image.Pt(gtx.Constraints.Max.X-gtx.Dp(unit.Dp(236)), gtx.Dp(unit.Dp(52)))}
		}
		a.callsRowMenu = nil
		a.mu.Unlock()
		a.invalidate()
	}
	items := callsBoxMenuItems(len(f.callsBoxRows))
	growClickables(&callsBoxMenuRow, len(items))
	for i, label := range items {
		i, label := i, label
		if callsBoxMenuRow[i].Clicked(gtx) {
			a.mu.Lock()
			a.callsBoxMenu = nil
			a.mu.Unlock()
			switch label {
			case "Call settings":
				a.closeCallsBox()
				a.openSettings(setSectionCalls)
			case "Clear all":
				a.mu.Lock()
				a.callsClearDlg = true
				a.mu.Unlock()
			}
			a.invalidate()
		}
	}

	// Row + redial events.
	growClickables(&callsBoxRowBtns, len(f.callsBoxRows))
	growClickables(&callsBoxRedial, len(f.callsBoxRows))
	for i := range f.callsBoxRows {
		i := i
		if callsBoxRowBtns[i].Clicked(gtx) {
			a.openCallsBoxPeer(i)
		}
		if callsBoxRedial[i].Clicked(gtx) {
			a.redialCallsBoxRow(i)
		}
	}

	// Group-call rows.
	gcs := callsBoxGroupCalls(f)
	growClickables(&callsBoxGcRow, len(gcs))
	growClickables(&callsBoxGcJoin, len(gcs))
	for i, c := range gcs {
		i, c := i, c
		if callsBoxGcRow[i].Clicked(gtx) {
			a.closeCallsBox()
			a.openChat(chatKey{AccountID: c.AccountID, ChatID: c.ChatID}, c.Title)
		}
		if callsBoxGcJoin[i].Clicked(gtx) {
			a.closeCallsBox()
			a.joinGroupCallFromVoice(c)
		}
	}

	// Context menu actions (tdesktop: Delete, Show in chat).
	growClickables(&callsCtxMenuRow, 2)
	for i, action := range []string{"Show in chat", "Delete"} {
		i, action := i, action
		if callsCtxMenuRow[i].Clicked(gtx) {
			a.mu.Lock()
			ctx := a.callsRowMenu
			a.callsRowMenu = nil
			a.mu.Unlock()
			if ctx == nil {
				continue
			}
			switch action {
			case "Show in chat":
				a.openCallsBoxPeer(ctx.row)
			case "Delete":
				a.mu.Lock()
				a.callsDelDlg = ctx.row
				a.mu.Unlock()
			}
			a.invalidate()
		}
	}

	// Pane press routing: right-click → row menu; outside-press dismisses.
	a.processCallsBoxEvents(gtx, f)

	// Scroll-to-end pagination (tdesktop loadMoreRows).
	if !callsBoxList.Position.BeforeEnd && !f.callsBoxBusy && !f.callsBoxDone && len(f.callsBoxRows) > 0 {
		a.loadCallsBoxMore()
	}

	// Clear-all confirm buttons.
	if callsClearOK.Clicked(gtx) {
		a.clearCallsBoxAll(callsClearRevoke.Value)
	}
	if callsClearCancel.Clicked(gtx) {
		a.mu.Lock()
		a.callsClearDlg = false
		a.mu.Unlock()
		a.invalidate()
	}

	// Delete-group confirm buttons.
	if callsDelOK.Clicked(gtx) {
		a.mu.Lock()
		idx := a.callsDelDlg
		a.mu.Unlock()
		a.deleteCallsBoxGroup(idx, callsDelRevoke.Value)
	}
	if callsDelCancel.Clicked(gtx) {
		a.mu.Lock()
		a.callsDelDlg = -1
		a.mu.Unlock()
		a.invalidate()
	}

	return layout.Stack{}.Layout(gtx,
		layout.Stacked(func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return a.callsBoxHeader(gtx, f)
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return a.ui.Divider(gtx)
				}),
				layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
					return a.callsBoxBody(gtx, f, gcs)
				}),
			)
		}),
		layout.Expanded(func(gtx layout.Context) layout.Dimensions {
			if f.callsBoxMenu != nil {
				return a.layoutCallsBoxMenu(gtx, f, items)
			}
			return layout.Dimensions{}
		}),
		layout.Expanded(func(gtx layout.Context) layout.Dimensions {
			if f.callsRowMenu != nil {
				return a.layoutCallsRowMenu(gtx, f)
			}
			return layout.Dimensions{}
		}),
		layout.Expanded(func(gtx layout.Context) layout.Dimensions {
			if f.callsClearDlg {
				return a.layoutCallsClearDialog(gtx, f)
			}
			return layout.Dimensions{}
		}),
		layout.Expanded(func(gtx layout.Context) layout.Dimensions {
			if f.callsDelDlg >= 0 {
				return a.layoutCallsDeleteDialog(gtx, f)
			}
			return layout.Dimensions{}
		}),
	)
}

// callsBoxGroupCalls lists this account's chats with an active group call.
func callsBoxGroupCalls(f frame) []engine.ChatInfo {
	var out []engine.ChatInfo
	for _, c := range f.chats {
		if c.AccountID == f.callsBoxFor && c.HasActiveCall {
			out = append(out, c)
		}
	}
	return out
}

// processCallsBoxEvents registers the pane pointer interest and routes
// presses: secondary (right) click over a row opens its context menu; any
// press outside an open menu or dialog dismisses it.
func (a *App) processCallsBoxEvents(gtx layout.Context, f frame) {
	stack := clip.Rect{Max: gtx.Constraints.Max}.Push(gtx.Ops)
	event.Op(gtx.Ops, callsBoxPaneTag)
	stack.Pop()
	for {
		ev, ok := gtx.Source.Event(pointer.Filter{Target: callsBoxPaneTag, Kinds: pointer.Press})
		if !ok {
			break
		}
		if pe, is := ev.(pointer.Event); is && pe.Kind == pointer.Press {
			a.onCallsBoxPress(f, pe)
		}
	}
}

func (a *App) onCallsBoxPress(f frame, pe pointer.Event) {
	pos := image.Pt(int(pe.Position.X), int(pe.Position.Y))
	if f.callsBoxMenu != nil {
		if !pointInRect(pos, a.callsBoxMenuRect) {
			a.mu.Lock()
			a.callsBoxMenu = nil
			a.mu.Unlock()
			a.invalidate()
		}
		return // presses inside the menu belong to its own buttons
	}
	if f.callsRowMenu != nil {
		if !pointInRect(pos, a.callsRowMenuRect) {
			a.mu.Lock()
			a.callsRowMenu = nil
			a.mu.Unlock()
			a.invalidate()
		}
		return
	}
	if pe.Buttons != pointer.ButtonSecondary {
		return
	}
	idx := a.callsRowAt(pos)
	if idx < 0 || idx >= len(f.callsBoxRows) {
		return
	}
	a.mu.Lock()
	a.callsRowMenu = &callsRowMenuTarget{row: idx, pos: pos}
	a.mu.Unlock()
	a.invalidate()
}

// callsRowAt maps a pane-space point to a history row index using the
// bounds recorded by the previous frame's layout.
func (a *App) callsRowAt(pos image.Point) int {
	for idx, r := range a.callsRowBounds {
		if pointInRect(pos, r) {
			return idx
		}
	}
	return -1
}

// callsBoxHeader: back arrow, "Calls" title, ⋮ menu button.
func (a *App) callsBoxHeader(gtx layout.Context, f frame) layout.Dimensions {
	return insetAll(gtx, unit.Dp(6), unit.Dp(8), 4, unit.Dp(8), func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				btn := a.ui.IconButton(&callsBoxBackBtn, iconNavigationBack, "Back")
				return btn.Layout(gtx)
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Left: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return a.ui.H2("Calls").Layout(gtx)
				})
			}),
			layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
				return layout.Dimensions{Size: image.Pt(gtx.Constraints.Max.X, 1)}
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				btn := a.ui.IconButton(&callsBoxMenuBtn, iconNavMoreVert, "Calls menu")
				return btn.Layout(gtx)
			}),
		)
	})
}

// callsBoxBody: group-calls subsection (when live) + the history list
// (loading / empty / rows), scrollable with the standard scrollbar.
func (a *App) callsBoxBody(gtx layout.Context, f frame, gcs []engine.ChatInfo) layout.Dimensions {
	var children []layout.FlexChild
	if len(gcs) > 0 {
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.callsBoxGroupCallsSection(gtx, f, gcs)
		}))
	}
	children = append(children, layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
		if f.callsBoxLoad && len(f.callsBoxRows) == 0 {
			return layout.Inset{Top: unit.Dp(24)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					lbl := a.ui.Dim(unit.Sp(14), "Loading…")
					lbl.Color = a.ui.p.TextFaint
					return lbl.Layout(gtx)
				})
			})
		}
		if len(f.callsBoxRows) == 0 {
			return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Vertical, Alignment: layout.Middle}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Bottom: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							gtx.Constraints.Max.X = gtx.Dp(unit.Dp(56))
							gtx.Constraints.Max.Y = gtx.Dp(unit.Dp(56))
							return iconCommunicationCall.Layout(gtx, a.ui.p.TextFaint)
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.Dim(unit.Sp(14), "No calls here yet")
						lbl.Color = a.ui.p.TextFaint
						return lbl.Layout(gtx)
					}),
				)
			})
		}
		a.callsRowBounds = a.callsRowBounds[:0]
		return material.List(a.ui.Theme, &callsBoxList).Layout(gtx, len(f.callsBoxRows), func(gtx layout.Context, idx int) layout.Dimensions {
			dims := a.callBoxRowWidget(gtx, f, idx)
			a.callsRowBounds = append(a.callsRowBounds, image.Rectangle{Max: dims.Size})
			return dims
		})
	}))
	return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
}

// callsBoxGroupCallsSection: the "Group calls" subsection above the
// history (tdesktop slide-wrap; only when a chat of this account has an
// active call). Rows open the chat; the headset action joins.
func (a *App) callsBoxGroupCallsSection(gtx layout.Context, f frame, gcs []engine.ChatInfo) layout.Dimensions {
	return layout.Inset{Top: unit.Dp(8), Bottom: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return a.subHeader(gtx, "Group calls")
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Left: unit.Dp(12), Right: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.Flex{Axis: layout.Vertical}.Layout(gtx, flexForEach(len(gcs), func(gtx layout.Context, idx int) layout.Dimensions {
						c := gcs[idx]
						return layout.Inset{Bottom: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							bl := material.ButtonLayout(a.ui.Theme, &callsBoxGcRow[idx])
							bl.Background = a.ui.p.Surface
							bl.CornerRadius = 12
							return bl.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								return layout.UniformInset(unit.Dp(10)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
									return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
										layout.Rigid(func(gtx layout.Context) layout.Dimensions {
											return layout.Inset{Right: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
												return a.chatAvatar(gtx, c, unit.Dp(42), dotNone)
											})
										}),
										layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
											return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
												layout.Rigid(func(gtx layout.Context) layout.Dimensions {
													return a.ui.Label(unit.Sp(15), c.Title).Layout(gtx)
												}),
												layout.Rigid(func(gtx layout.Context) layout.Dimensions {
													lbl := a.ui.Dim(unit.Sp(12), "Voice chat · live")
													lbl.Color = a.ui.p.Error
													return lbl.Layout(gtx)
												}),
											)
										}),
										layout.Rigid(func(gtx layout.Context) layout.Dimensions {
											btn := a.ui.IconButton(&callsBoxGcJoin[idx], iconHardwareHeadset, "Join voice chat")
											btn.Color = a.ui.p.Accent
											return btn.Layout(gtx)
										}),
									)
								})
							})
						})
					})...)
				})
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return a.ui.Divider(gtx)
			}),
		)
	})
}

// callBoxRowWidget renders one grouped history row: avatar, direction
// arrow (missed tinted red), name, tdesktop status line, and the redial
// action (phone; camera for video rows).
func (a *App) callBoxRowWidget(gtx layout.Context, f frame, idx int) layout.Dimensions {
	row := f.callsBoxRows[idx]
	name := row.PeerName
	if name == "" {
		name = "Unknown"
	}
	return layout.Inset{Left: unit.Dp(12), Right: unit.Dp(12), Bottom: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		bl := material.ButtonLayout(a.ui.Theme, &callsBoxRowBtns[idx])
		bl.Background = a.ui.p.Surface
		bl.CornerRadius = 12
		return bl.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(10)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Right: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							if img := a.avatarImage(row.AvatarPath, ""); img != nil {
								return avatarFromImage(gtx, a, img, unit.Dp(42), dotNone)
							}
							return a.ui.Avatar(gtx, name, unit.Dp(42), dotNone)
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Right: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							gtx.Constraints.Max.X = gtx.Dp(unit.Dp(20))
							gtx.Constraints.Max.Y = gtx.Dp(unit.Dp(20))
							c := a.ui.p.TextDim
							var ic *widget.Icon
							switch row.Dir {
							case callDirOut:
								ic = iconCallMade
							case callDirMissed:
								ic = iconCallMissed
								c = a.ui.p.Error
							default:
								ic = iconCallReceived
							}
							return ic.Layout(gtx, c)
						})
					}),
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								return a.ui.Label(unit.Sp(15), name).Layout(gtx)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Dim(unit.Sp(12), callBoxStatus(row, f.now))
								if row.Dir == callDirMissed {
									lbl.Color = a.ui.p.Error
								}
								return lbl.Layout(gtx)
							}),
						)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						ic := iconCommunicationCall
						if row.Video {
							ic = iconAVVideocam
						}
						btn := a.ui.IconButton(&callsBoxRedial[idx], ic, "Call back")
						btn.Color = a.ui.p.Accent
						return btn.Layout(gtx)
					}),
				)
			})
		})
	})
}

// layoutCallsBoxMenu renders the header ⋮ popup (Call settings / Clear all
// — the latter attention-red, only when rows exist).
func (a *App) layoutCallsBoxMenu(gtx layout.Context, f frame, items []string) layout.Dimensions {
	m := f.callsBoxMenu
	menuW := gtx.Dp(unit.Dp(220))
	rowH := gtx.Dp(unit.Dp(36))
	h := gtx.Dp(unit.Dp(8)) + len(items)*rowH + gtx.Dp(unit.Dp(8))
	pos := m.pos
	if pos.X+menuW > gtx.Constraints.Max.X {
		pos.X = gtx.Constraints.Max.X - menuW
	}
	if pos.Y+h > gtx.Constraints.Max.Y {
		pos.Y = gtx.Constraints.Max.Y - h
	}
	a.callsBoxMenuRect = image.Rect(pos.X, pos.Y, pos.X+menuW, pos.Y+h)

	var dims layout.Dimensions
	func() {
		defer op.Offset(pos).Push(gtx.Ops).Pop()
		gtx.Constraints = layout.Constraints{Max: image.Pt(menuW, h), Min: image.Pt(menuW, h)}
		dims = roundedFill(gtx, a.ui.p.Surface, 10, func(gtx layout.Context) layout.Dimensions {
			children := make([]layout.FlexChild, 0, len(items)+2)
			children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Top: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.Dimensions{Size: image.Pt(menuW, gtx.Dp(unit.Dp(4)))}
				})
			}))
			for i, label := range items {
				i, label := i, label
				children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					btn := &callsBoxMenuRow[i]
					gtx.Constraints.Min.Y = rowH
					return material.ButtonLayout(a.ui.Theme, btn).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						return layout.UniformInset(unit.Dp(9)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Label(unit.Sp(14), label)
							if label == "Clear all" {
								lbl.Color = a.ui.p.Error
							} else {
								lbl.Color = a.ui.p.Text
							}
							return lbl.Layout(gtx)
						})
					})
				}))
			}
			children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Top: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.Dimensions{Size: image.Pt(menuW, gtx.Dp(unit.Dp(4)))}
				})
			}))
			layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
			return layout.Dimensions{Size: image.Pt(menuW, h)}
		})
	}()
	return dims
}

// layoutCallsRowMenu renders the row context menu (Show in chat / Delete).
func (a *App) layoutCallsRowMenu(gtx layout.Context, f frame) layout.Dimensions {
	m := f.callsRowMenu
	actions := []string{"Show in chat", "Delete"}
	menuW := gtx.Dp(unit.Dp(200))
	rowH := gtx.Dp(unit.Dp(36))
	h := gtx.Dp(unit.Dp(8)) + len(actions)*rowH + gtx.Dp(unit.Dp(8))
	pos := m.pos
	if pos.X+menuW > gtx.Constraints.Max.X {
		pos.X = gtx.Constraints.Max.X - menuW
	}
	if pos.Y+h > gtx.Constraints.Max.Y {
		pos.Y = gtx.Constraints.Max.Y - h
	}
	a.callsRowMenuRect = image.Rect(pos.X, pos.Y, pos.X+menuW, pos.Y+h)

	var dims layout.Dimensions
	func() {
		defer op.Offset(pos).Push(gtx.Ops).Pop()
		gtx.Constraints = layout.Constraints{Max: image.Pt(menuW, h), Min: image.Pt(menuW, h)}
		dims = roundedFill(gtx, a.ui.p.Surface, 10, func(gtx layout.Context) layout.Dimensions {
			children := make([]layout.FlexChild, 0, len(actions)+2)
			children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Top: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.Dimensions{Size: image.Pt(menuW, gtx.Dp(unit.Dp(4)))}
				})
			}))
			for i, label := range actions {
				i, label := i, label
				children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					btn := &callsCtxMenuRow[i]
					gtx.Constraints.Min.Y = rowH
					return material.ButtonLayout(a.ui.Theme, btn).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						return layout.UniformInset(unit.Dp(9)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Label(unit.Sp(14), label)
							if label == "Delete" {
								lbl.Color = a.ui.p.Error
							} else {
								lbl.Color = a.ui.p.Text
							}
							return lbl.Layout(gtx)
						})
					})
				}))
			}
			children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Top: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.Dimensions{Size: image.Pt(menuW, gtx.Dp(unit.Dp(4)))}
				})
			}))
			layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
			return layout.Dimensions{Size: image.Pt(menuW, h)}
		})
	}()
	return dims
}

// layoutCallsClearDialog: Clear-all confirm (tdesktop ClearCallsBox): the
// "also delete for everyone" revoke checkbox rides the same RPC.
func (a *App) layoutCallsClearDialog(gtx layout.Context, f frame) layout.Dimensions {
	return a.callsConfirmCard(gtx, "Clear call history?",
		"Are you sure you want to clear your entire call history?",
		"Also delete for everyone", &callsClearRevoke, &callsClearOK, &callsClearCancel, "Clear")
}

// layoutCallsDeleteDialog: per-group delete confirm (tdesktop
// DeleteMessagesBox semantics, revoke checkbox honored per message).
func (a *App) layoutCallsDeleteDialog(gtx layout.Context, f frame) layout.Dimensions {
	return a.callsConfirmCard(gtx, "Delete calls?",
		"The selected call entries will be deleted for you"+deleteScopeSuffix(callsDelRevoke.Value)+".",
		"Also delete for everyone", &callsDelRevoke, &callsDelOK, &callsDelCancel, "Delete")
}

func deleteScopeSuffix(revoke bool) string {
	if revoke {
		return " and everyone"
	}
	return ""
}

// callsConfirmCard renders the shared centered confirm card + scrim.
func (a *App) callsConfirmCard(gtx layout.Context, title, body, checkLabel string, check *widget.Bool, ok, cancel *widget.Clickable, okLabel string) layout.Dimensions {
	// Scrim behind the card.
	paint.FillShape(gtx.Ops, color.NRGBA{R: 0, G: 0, B: 0, A: 0x66},
		clip.Rect{Max: image.Pt(gtx.Constraints.Max.X, gtx.Constraints.Max.Y)}.Op())

	cardW := gtx.Dp(unit.Dp(360))
	if cardW > gtx.Constraints.Max.X {
		cardW = gtx.Constraints.Max.X
	}
	return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		gtx.Constraints.Max.X = cardW
		return roundedFill(gtx, a.ui.p.Surface, 14, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(18)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return a.ui.H3(title).Layout(gtx)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(6), Bottom: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Dim(unit.Sp(13), body)
							return lbl.Layout(gtx)
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return material.CheckBox(a.ui.Theme, check, checkLabel).Layout(gtx)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(14)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
								layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
									return layout.Dimensions{Size: image.Pt(gtx.Constraints.Max.X, 1)}
								}),
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									return layout.Inset{Right: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
										btn := material.Button(a.ui.Theme, cancel, "Cancel")
										btn.Background = a.ui.p.SurfaceHi
										btn.Color = a.ui.p.Text
										return btn.Layout(gtx)
									})
								}),
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									btn := material.Button(a.ui.Theme, ok, okLabel)
									btn.Background = a.ui.p.Error
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

// flexForEach builds n rigid children with idx-sourced widgets.
func flexForEach(n int, w func(gtx layout.Context, idx int) layout.Dimensions) []layout.FlexChild {
	children := make([]layout.FlexChild, 0, n)
	for i := 0; i < n; i++ {
		i := i
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return w(gtx, i)
		}))
	}
	return children
}
