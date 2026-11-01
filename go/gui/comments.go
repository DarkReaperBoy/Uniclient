package gui

import (
	"strings"

	"gioui.org/layout"
	"gioui.org/unit"
	"gioui.org/widget"

	"uniclient/engine"
)

type threadScopeState struct {
	postKey        chatKey
	postID         string
	discussionChat string
	rootID         string
	title          string
}

func commentsCountLabel(n int) string {
	if n == 1 {
		return "1 comment"
	}
	return viewsCountLabel(n) + " comments"
}

func commentsRowVisible(chat engine.ChatInfo, comments int) bool {
	return chat.Type == engine.ChatTypeChanVal && comments > 0
}

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

func (a *App) openCommentThread(m engine.CachedMessage) {
	a.mu.Lock()
	k := a.selected
	a.threadScope = &threadScopeState{
		postKey: chatKey{AccountID: m.AccountID, ChatID: m.ChatID},
		postID:  m.MsgID,
		title:   m.ContentText,
	}
	a.messages = nil
	a.uiGen++
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
			a.threadScope.discussionChat = rows[0].ChatID
			a.threadScope.rootID = threadRootOfRows(rows)
		}
		a.mu.Unlock()
		a.invalidate()
		go func() { _ = a.eng.ReadDiscussion(m.AccountID, m.ChatID, m.MsgID) }()
	}()
}

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

type threadOpenReq struct {
	postID    string
	commentID string
}

func (a *App) openCommentThreadDeep(k chatKey, req threadOpenReq) {
	a.mu.Lock()
	a.threadScope = &threadScopeState{
		postKey: k,
		postID:  req.postID,
	}
	a.messages = nil
	a.uiGen++
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
			return
		}
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
		ts, err := a.eng.GetMessageTimestamp(k.AccountID, discussion, req.commentID)
		if err != nil || ts <= 0 {
			return
		}
		older, err := a.eng.GetThreadMessages(k.AccountID, discussion, rootID, ts+1, 26)
		if err != nil {
			return
		}
		win, jump := threadDeepJumpWindow(rows, older, req.commentID)
		if win == nil || jump < 0 {
			return
		}
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
	for i := range newest {
		if newest[i].Timestamp > ts {
			win = append(win, newest[i])
		}
	}
	return win, messageIndexOf(win, commentID)
}

func messageIndexOf(msgs []engine.CachedMessage, msgID string) int {
	for i := range msgs {
		if msgs[i].MsgID == msgID {
			return i
		}
	}
	return -1
}

func (a *App) closeCommentThread() {
	a.mu.Lock()
	k := a.selected
	a.threadScope = nil
	a.messages = nil
	a.uiGen++
	a.loadingMsgs = true
	a.mu.Unlock()
	a.invalidate()
	if k == nil {
		return
	}
	go a.refreshMessages()
}

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
