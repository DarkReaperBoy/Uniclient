package gui

import (
	"strings"

	"gioui.org/layout"
	"gioui.org/unit"
	"gioui.org/widget"

	"uniclient/engine"
)

// Channel-post comments (slice 195, tdesktop's comments view): the
// "N comments" chip on channel posts opens the comment thread — the
// discussion group's messages filtered by the reply-to-top root
// (messages.getDiscussionMessage + cached rows via engine
// GetDiscussionThread/GetThreadMessages), scoped like a forum topic:
// bar under the header (back → the channel), full composer redirected
// to the discussion chat with reply-to the thread root.

// threadScopeState: the open comment thread (nil = normal chat view).
type threadScopeState struct {
	postKey        chatKey // the CHANNEL chat the post belongs to
	postID         string  // the channel post's message id
	discussionChat string  // the linked discussion group's chat id
	rootID         string  // the thread root inside the discussion chat
	title          string  // the post's first line (bar subtitle)
}

// commentsCountLabel: "N comment(s)" with compact counts. Pure.
func commentsCountLabel(n int) string {
	if n == 1 {
		return "1 comment"
	}
	return viewsCountLabel(n) + " comments"
}

// commentsRowVisible: channel posts with a counted comment thread only.
// Groups/DMs never show the chip (their replies are reply headers). Pure.
func commentsRowVisible(chat engine.ChatInfo, comments int) bool {
	return chat.Type == engine.ChatTypeChanVal && comments > 0
}

// threadBarTitle: "Comments" or "Comments · <first line>". Pure.
func threadBarTitle(postText string) string {
	postText = strings.TrimSpace(postText)
	if postText == "" {
		return "Comments"
	}
	if len(postText) > 40 {
		postText = postText[:37] + "…"
	}
	return "Comments · " + postText
}

// openCommentThread opens the thread view for a channel post.
func (a *App) openCommentThread(m engine.CachedMessage) {
	a.mu.Lock()
	k := a.selected
	a.threadScope = &threadScopeState{
		postKey: chatKey{AccountID: m.AccountID, ChatID: m.ChatID},
		postID:  m.MsgID,
		title:   m.ContentText,
	}
	a.messages = nil
	a.loadingMsgs = true
	a.olderDone = false
	a.loadingOlder = false
	a.mu.Unlock()
	a.invalidate()
	if k == nil {
		return
	}
	go func() {
		rows, err := a.eng.GetDiscussionThread(m.AccountID, m.ChatID, m.MsgID)
		a.mu.Lock()
		if a.threadScope == nil || a.threadScope.postID != m.MsgID {
			a.mu.Unlock()
			return
		}
		a.loadingMsgs = false
		if err != nil {
			a.mu.Unlock()
			a.setToast("Comments: " + err.Error())
			return
		}
		for i, j := 0, len(rows)-1; i < j; i, j = i+1, j-1 {
			rows[i], rows[j] = rows[j], rows[i]
		}
		a.messages = rows
		if len(rows) > 0 {
			// The thread scope settles on the discussion chat + root.
			a.threadScope.discussionChat = rows[0].ChatID
			a.threadScope.rootID = threadRootOfRows(rows)
		}
		a.mu.Unlock()
		a.invalidate()
		// tdesktop marks the thread read on open.
		go func() { _ = a.eng.ReadDiscussion(m.AccountID, m.ChatID, m.MsgID) }()
	}()
}

// threadRootOfRows resolves the thread root from the loaded rows: the
// row whose root is itself, else the most common ThreadRoot. Pure.
func threadRootOfRows(rows []engine.CachedMessage) string {
	for _, r := range rows {
		if r.ThreadRoot == r.MsgID {
			return r.MsgID
		}
	}
	for _, r := range rows {
		if r.ThreadRoot != "" {
			return r.ThreadRoot
		}
	}
	return ""
}

// threadOpenReq (slice 196): a comment-thread deep link pending the chat
// open — the channel post's id plus the linked comment's id.
type threadOpenReq struct {
	postID    string
	commentID string
}

// openCommentThreadDeep (slice 196): a comment deep link
// (t.me/<channel>/<post>?comment=<id>) opens the just-opened channel
// chat straight into the thread view and jumps onto the linked comment.
// Mirrors openCommentThread minus the in-hand post row: the thread fetch
// resolves the discussion chat + root, and the bar title falls back to
// the root row's text (the forwarded post copy). The comment jump
// targets the newest page first; an off-page comment resolves through
// the engine (GetMessageTimestamp caches the row) and loads a
// target-anchored window; a comment the engine cannot resolve leaves the
// newest page in place, no jump (honest). Loader goroutine — state under
// a.mu, mirroring the slice-189 topic jump.
func (a *App) openCommentThreadDeep(k chatKey, req threadOpenReq) {
	a.mu.Lock()
	a.threadScope = &threadScopeState{
		postKey: k,
		postID:  req.postID,
	}
	a.messages = nil
	a.loadingMsgs = true
	a.olderDone = false
	a.loadingOlder = false
	a.mu.Unlock()
	a.invalidate()
	go func() {
		rows, err := a.eng.GetDiscussionThread(k.AccountID, k.ChatID, req.postID)
		a.mu.Lock()
		if a.threadScope == nil || a.threadScope.postID != req.postID || a.selected == nil || *a.selected != k {
			a.mu.Unlock()
			return
		}
		a.loadingMsgs = false
		if err != nil {
			a.mu.Unlock()
			a.setToast("Comments: " + err.Error())
			return
		}
		for i, j := 0, len(rows)-1; i < j; i, j = i+1, j-1 {
			rows[i], rows[j] = rows[j], rows[i]
		}
		// rows is chronological (oldest first) now.
		if len(rows) > 0 {
			a.threadScope.discussionChat = rows[0].ChatID
			a.threadScope.rootID = threadRootOfRows(rows)
			if a.threadScope.title == "" {
				if root := threadRootRow(rows, a.threadScope.rootID); root != nil {
					a.threadScope.title = root.ContentText
				}
			}
		}
		a.messages = rows
		a.mu.Unlock()
		a.invalidate()
		go func() { _ = a.eng.ReadDiscussion(k.AccountID, k.ChatID, req.postID) }()

		if req.commentID == "" {
			return // thread open, no comment target
		}
		// The linked comment: newest page first...
		a.mu.Lock()
		row := rowIndexOf(rows, req.commentID, "")
		discussion := ""
		rootID := ""
		if a.threadScope != nil && a.threadScope.postID == req.postID {
			discussion = a.threadScope.discussionChat
			rootID = a.threadScope.rootID
		}
		if row >= 0 {
			a.wid.msgList.Position.First = row
			a.wid.msgList.Position.Offset = 0
			a.wid.msgList.Position.BeforeEnd = true
			a.mu.Unlock()
			a.invalidate()
			return
		}
		a.mu.Unlock()
		if discussion == "" || rootID == "" {
			return
		}
		// ...else resolve the comment's timestamp (engine caches the row on
		// the fetch) and load a target-anchored window.
		ts, err := a.eng.GetMessageTimestamp(k.AccountID, discussion, req.commentID)
		if err != nil || ts <= 0 {
			return // honest: the newest page stays, no jump
		}
		older, err := a.eng.GetThreadMessages(k.AccountID, discussion, rootID, ts+1, 26)
		if err != nil {
			return
		}
		win, jump := threadDeepJumpWindow(rows, older, req.commentID)
		if win == nil || jump < 0 {
			return
		}
		// Map the message index onto the render row (day dividers,
		// albums) — same conversion jumpToMessageAt performs.
		row = rowIndexOf(win, req.commentID, "")
		if row < 0 {
			return
		}
		a.mu.Lock()
		if a.threadScope == nil || a.threadScope.postID != req.postID || a.selected == nil || *a.selected != k {
			a.mu.Unlock()
			return
		}
		a.messages = win
		a.olderDone = false
		a.wid.msgList.Position.First = row
		a.wid.msgList.Position.Offset = 0
		a.wid.msgList.Position.BeforeEnd = true
		a.mu.Unlock()
		a.invalidate()
	}()
}

// threadRootRow finds the thread-root row (the forwarded post copy) in a
// thread window. Pure.
func threadRootRow(rows []engine.CachedMessage, rootID string) *engine.CachedMessage {
	if rootID == "" {
		return nil
	}
	for i := range rows {
		if rows[i].MsgID == rootID {
			return &rows[i]
		}
	}
	return nil
}

// threadDeepJumpWindow (slice 196): assembles the comment deep-link
// window around the linked comment. newest is the newest page
// (chronological); older is the target-anchored page (newest-first,
// target included). The window is reverse(older) plus the newest page's
// rows newer than the target, in chronological order; jump is the
// target's MESSAGE index (the caller maps it onto the render row via
// rowIndexOf, exactly like jumpToMessageAt). A target already in the
// newest page makes that page the window (older ignored); a target in
// neither slice returns (nil, -1) — the caller keeps the newest page
// (honest). Pure — locked by tests.
func threadDeepJumpWindow(newest, older []engine.CachedMessage, commentID string) ([]engine.CachedMessage, int) {
	if commentID == "" {
		return nil, -1
	}
	if idx := messageIndexOf(newest, commentID); idx >= 0 {
		return newest, idx
	}
	ts := int64(0)
	found := false
	for i := range older {
		if older[i].MsgID == commentID {
			ts = older[i].Timestamp
			found = true
			break
		}
	}
	if !found {
		return nil, -1
	}
	win := make([]engine.CachedMessage, 0, len(older)+len(newest))
	for i, j := 0, len(older)-1; i < j; i, j = i+1, j-1 {
		older[i], older[j] = older[j], older[i]
	}
	win = append(win, older...)
	for i := range newest { // chronological: the newer tail rides in order
		if newest[i].Timestamp > ts {
			win = append(win, newest[i])
		}
	}
	return win, messageIndexOf(win, commentID)
}

// messageIndexOf is the plain message-index lookup (no render rows).
// Pure.
func messageIndexOf(msgs []engine.CachedMessage, msgID string) int {
	for i := range msgs {
		if msgs[i].MsgID == msgID {
			return i
		}
	}
	return -1
}

// closeCommentThread returns to the channel view.
func (a *App) closeCommentThread() {
	a.mu.Lock()
	k := a.selected
	a.threadScope = nil
	a.messages = nil
	a.loadingMsgs = true
	a.mu.Unlock()
	a.invalidate()
	if k == nil {
		return
	}
	go a.refreshMessages()
}

// threadScopeFor returns the open thread scope when the selected chat is
// the thread's channel ("" discussion chat = still resolving).
func (a *App) threadScopeFor(k *chatKey) *threadScopeState {
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.threadScope == nil || k == nil || a.selected == nil {
		return nil
	}
	if a.threadScope.postKey.String() != k.String() {
		return nil
	}
	return a.threadScope
}

// layoutCommentsBar: the thread identity strip under the chat header.
func (a *App) layoutCommentsBar(gtx layout.Context, f frame) layout.Dimensions {
	if a.wid.threadBackBtn.Clicked(gtx) {
		a.closeCommentThread()
	}
	title := "Comments"
	if ts := f.threadScope; ts != nil {
		title = threadBarTitle(ts.title)
	}
	return layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(4), Left: unit.Dp(8), Right: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				btn := a.ui.IconButton(&a.wid.threadBackBtn, iconNavigationBack, "Back to channel")
				btn.Color = a.ui.p.TextDim
				return btn.Layout(gtx)
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Left: unit.Dp(4), Right: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return iconCommunicationChat.Layout(gtx, a.ui.p.TextDim)
				})
			}),
			layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
				lbl := a.ui.Label(unit.Sp(14), title)
				lbl.MaxLines = 1
				return lbl.Layout(gtx)
			}),
		)
	})
}

// commentsChip renders the tappable "N comments" pill for one post.
func (a *App) commentsChip(gtx layout.Context, f frame, m engine.CachedMessage) layout.Dimensions {
	chat := chatOf(f, m)
	if !commentsRowVisible(chat, m.CommentsCount) {
		return layout.Dimensions{}
	}
	key := m.AccountID + "/" + m.ChatID + "/" + m.MsgID
	btn := a.commentChipBtn(key)
	if btn.Clicked(gtx) {
		go a.openCommentThread(m)
		return layout.Dimensions{}
	}
	return layout.Inset{Right: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return iconCommunicationChat.Layout(gtx, a.ui.p.TextFaint)
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				lbl := a.ui.Dim(unit.Sp(10), commentsCountLabel(m.CommentsCount))
				return layout.Inset{Left: unit.Dp(2)}.Layout(gtx, lbl.Layout)
			}),
		)
	})
}

// commentChipBtn pools per-post chip clickables (comment-thread targets).
func (a *App) commentChipBtn(key string) *widget.Clickable {
	if btn, ok := a.wid.commentChipBtns[key]; ok {
		return btn
	}
	btn := new(widget.Clickable)
	a.wid.commentChipBtns[key] = btn
	if len(a.wid.commentChipBtns) > 512 {
		a.wid.commentChipBtns = map[string]*widget.Clickable{key: btn}
	}
	return btn
}
