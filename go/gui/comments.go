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
