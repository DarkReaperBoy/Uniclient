package gui

// seeninline.go — slice 152: the inline read receipt (tdesktop DM
// behavior): the last own outgoing message in a DM carries a small
// "Seen 12:34" row with the reader's avatar under the bubble meta. The
// data rides the slice-98 engine surface (GetOutboxReadDate +
// GetMessageReadParticipantsDetailed); privacy errors render nothing
// (the Seen-by dialog keeps the honest sentence).

import (
	"strconv"
	"time"

	"gioui.org/layout"
	"gioui.org/unit"

	"uniclient/engine"
)

// seenInlineGate (pure): the receipt renders on the LAST own outgoing
// non-service message of a DM (channels broadcast, groups keep the
// dialog-only receipt — tdesktop shows the avatar stack in DMs).
func seenInlineGate(m engine.CachedMessage, chatType int, isLastOwn bool) bool {
	if !m.IsOutgoing || m.IsService || !isLastOwn {
		return false
	}
	return chatType == engine.ChatTypeDMVal
}

// seenInlineLabel (pure): "Seen HH:MM" (or plain "Seen" without a
// resolved date).
func seenInlineLabel(readDate int64, ok bool) string {
	if !ok || readDate <= 0 {
		return "Seen"
	}
	return "Seen " + time.Unix(readDate, 0).Format("15:04")
}

// seenInlineState is the per-chat cached receipt (one entry per chat;
// keyed account|chat).
type seenInlineState struct {
	msgID      string
	parts      []map[string]interface{}
	readDate   int64
	readDateOK bool
	privacy    string
	fetching   bool
	lastTouch  time.Time
}

// msgFrameLastOwn is the last own outgoing message id of the frame's
// message slice (set once per messageList layout pass).
var msgFrameLastOwn string

// lastOwnMsgID (pure): the last outgoing non-service message in the
// slice, "" when none.
func lastOwnMsgID(msgs []engine.CachedMessage) string {
	for i := len(msgs) - 1; i >= 0; i-- {
		if msgs[i].IsOutgoing && !msgs[i].IsService {
			return msgs[i].MsgID
		}
	}
	return ""
}

// ensureSeenInline lazily fetches (and caches) the read receipt for the
// chat's last own message; refetches when the message changes.
func (a *App) ensureSeenInline(m *engine.CachedMessage) {
	if m == nil {
		return
	}
	key := m.AccountID + "|" + m.ChatID
	a.mu.Lock()
	st := a.seenInline[key]
	if st == nil {
		st = &seenInlineState{}
		if a.seenInline == nil {
			a.seenInline = make(map[string]*seenInlineState)
		}
		a.seenInline[key] = st
	}
	if st.msgID == m.MsgID && (st.privacy != "" || st.fetching || st.readDateOK) {
		a.mu.Unlock()
		return
	}
	st.msgID = m.MsgID
	st.fetching = true
	st.privacy = ""
	st.readDateOK = false
	st.parts = nil
	acc, chat, msgID := m.AccountID, m.ChatID, m.MsgID
	a.mu.Unlock()

	go func() {
		parts, err := a.eng.GetMessageReadParticipantsDetailed(acc, chat, msgID)
		privacy := ""
		if err != nil {
			privacy = err.Error()
		}
		date, dateErr := a.eng.GetOutboxReadDate(acc, chat, msgID)
		a.mu.Lock()
		st2 := a.seenInline[key]
		if st2 == nil || st2.msgID != msgID {
			a.mu.Unlock()
			return
		}
		st2.fetching = false
		st2.privacy = privacy
		if err == nil {
			st2.parts = parts
		}
		if dateErr == nil {
			st2.readDate = int64(date)
			st2.readDateOK = true
		}
		a.mu.Unlock()
		a.invalidate()
	}()
}

// seenInlineFor returns the chat's cached receipt state (frame read).
func seenInlineFor(f frame, m *engine.CachedMessage) *seenInlineState {
	if m == nil {
		return nil
	}
	return f.seenInline[m.AccountID+"|"+m.ChatID]
}

// layoutSeenInline renders the receipt row under the bubble meta:
// tiny reader avatar(s) + "Seen …". Hidden for privacy errors and
// while unread (readDate unknown + no parts = not seen yet — nothing
// renders, same as tdesktop's pending state).
func (a *App) layoutSeenInline(gtx layout.Context, f frame, m *engine.CachedMessage) layout.Dimensions {
	st := seenInlineFor(f, m)
	if st == nil || st.msgID != m.MsgID {
		return layout.Dimensions{}
	}
	if st.privacy != "" && seenByPrivacyNote(st.privacy) != "" {
		return layout.Dimensions{} // privacy: the dialog explains, the inline row stays silent
	}
	if st.privacy != "" {
		return layout.Dimensions{} // other errors: silent too (the dialog surfaces them)
	}
	seen := st.readDateOK || len(st.parts) > 0
	if !seen {
		return layout.Dimensions{}
	}
	// readers: up to 3 avatars (DMs have one, the map stays general)
	var names []string
	for i, p := range st.parts {
		if i >= 3 {
			break
		}
		names = append(names, seenByRowName(p))
	}
	if len(names) == 0 && st.readDateOK {
		names = append(names, "") // date-only row, no avatar
	}
	return layout.Inset{Top: unit.Dp(2)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		row := layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}
		children := make([]layout.FlexChild, 0, len(names)+2)
		for _, n := range names {
			n := n
			children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Right: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return a.ui.Avatar(gtx, n, unit.Dp(14), dotNone)
				})
			}))
		}
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			lbl := a.ui.Dim(unit.Sp(10), seenInlineLabel(st.readDate, st.readDateOK))
			lbl.Color = a.ui.p.TextFaint
			return lbl.Layout(gtx)
		}))
		if len(st.parts) > 3 {
			extra := strconv.Itoa(len(st.parts) - 3)
			children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				lbl := a.ui.Dim(unit.Sp(10), "+"+extra)
				lbl.Color = a.ui.p.TextFaint
				return lbl.Layout(gtx)
			}))
		}
		return row.Layout(gtx, children...)
	})
}
