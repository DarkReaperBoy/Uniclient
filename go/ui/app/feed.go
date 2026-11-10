package app

import (
	"encoding/json"
	"sort"
	"strconv"
	"time"

	"uniclient/ui/dialogs"
	"uniclient/ui/history"
)

const (
	engineEventChatSnapshot = "chat_snapshot"
	engineEventChatUpdated  = "chat_updated"
	engineEventMsgReceived  = "msg_received"

	chatKindDM      = 1
	chatKindGroup   = 2
	chatKindChannel = 3
	chatKindTopic   = 4

	msgWireStatusSending   = 1
	msgWireStatusSent      = 2
	msgWireStatusDelivered = 3
	msgWireStatusRead      = 4

	attachWindowMs   = 900000
	chatHistoryLimit = 50
)

type ChatRef struct {
	Account string
	ID      string
}

type WireMessage struct {
	ID          string
	SenderID    string
	SenderName  string
	Text        string
	TimestampMs int64
	Status      int
	Out         bool
	Service     bool
}

type ChatPort interface {
	Messages(accountID, chatID string, limit int) ([]WireMessage, bool)
}

func (m Model) WithPort(p ChatPort) Model {
	m.port = p
	return m
}

type snapshotChat struct {
	ChatID              string `json:"chat_id"`
	Type                int    `json:"type"`
	Title               string `json:"title"`
	LastMsgText         string `json:"last_msg_text"`
	LastMsgTime         int64  `json:"last_msg_time"`
	LastMsgSender       string `json:"last_msg_sender"`
	LastMsgIsOutgoing   bool   `json:"last_msg_is_outgoing"`
	LastMsgStatus       int    `json:"last_msg_status"`
	UnreadCount         int    `json:"unread_count"`
	IsMuted             bool   `json:"is_muted"`
	IsPinned            bool   `json:"is_pinned"`
	IsBot               bool   `json:"is_bot"`
	IsForum             bool   `json:"is_forum"`
	UnreadMark          bool   `json:"unread_mark"`
	UnreadMentionCount  int    `json:"unread_mention_count"`
	UnreadReactionCount int    `json:"unread_reaction_count"`
}

type snapshotData struct {
	Chats []snapshotChat `json:"chats"`
}

type chatUpdatedData struct {
	Chat snapshotChat `json:"chat"`
}

type receivedMessage struct {
	MsgID       string `json:"msg_id"`
	SenderID    string `json:"sender_id"`
	SenderName  string `json:"sender_name"`
	ContentText string `json:"content_text"`
	Timestamp   int64  `json:"timestamp"`
	Status      int    `json:"status"`
	IsOutgoing  bool   `json:"is_outgoing"`
	IsService   bool   `json:"is_service"`
}

type msgReceivedData struct {
	ChatID  string          `json:"chat_id"`
	Message receivedMessage `json:"message"`
}

func (m Model) knowsAccount(id string) bool {
	for _, acc := range m.Accounts {
		if acc.ID == id {
			return true
		}
	}
	return false
}

func (m Model) applyChatSnapshot(env engineEnvelope) (Model, Cmd) {
	var d snapshotData
	if json.Unmarshal(env.Data, &d) != nil {
		return m, nil
	}
	if !m.knowsAccount(env.AccountID) {
		return m, nil
	}
	now := time.UnixMilli(env.TimestampMs)
	rows := make([]dialogs.Entry, 0, len(d.Chats))
	for _, c := range d.Chats {
		rows = append(rows, snapshotRow(c, env.AccountID, now))
	}
	sortDialogRows(rows)
	m.accountRows = storeAccountRows(m.accountRows, env.AccountID, rows)
	m.reprojectDialogRows()
	return m, nil
}

func (m Model) applyChatUpdated(env engineEnvelope) (Model, Cmd) {
	var d chatUpdatedData
	if json.Unmarshal(env.Data, &d) != nil || d.Chat.ChatID == "" {
		return m, nil
	}
	rows, known := m.accountRows[env.AccountID]
	if !known {
		return m, nil
	}
	fresh := make([]dialogs.Entry, len(rows))
	copy(fresh, rows)
	entry := snapshotRow(d.Chat, env.AccountID, time.UnixMilli(env.TimestampMs))
	at := len(fresh)
	for i := range fresh {
		if fresh[i].ChatID == d.Chat.ChatID {
			at = i
			break
		}
	}
	if at < len(fresh) {
		fresh[at] = entry
	} else {
		fresh = append(fresh, entry)
	}
	sortDialogRows(fresh)
	m.accountRows = storeAccountRows(m.accountRows, env.AccountID, fresh)
	m.reprojectDialogRows()
	return m, nil
}

func sortDialogRows(rows []dialogs.Entry) {
	sort.SliceStable(rows, func(i, j int) bool {
		if rows[i].Pinned != rows[j].Pinned {
			return rows[i].Pinned
		}
		return rows[i].SortTime > rows[j].SortTime
	})
}

func storeAccountRows(current map[string][]dialogs.Entry, accountID string, rows []dialogs.Entry) map[string][]dialogs.Entry {
	fresh := make(map[string][]dialogs.Entry, len(current)+1)
	for id, r := range current {
		fresh[id] = r
	}
	fresh[accountID] = rows
	return fresh
}

func (m *Model) reprojectDialogRows() {
	rows := m.dialogFeed
	if len(m.accountRows) > 0 {
		rows = make([]dialogs.Entry, 0, len(m.accountRows))
		for _, acc := range m.Accounts {
			rows = append(rows, m.accountRows[acc.ID]...)
		}
	}
	m.setDialogRows(rows, false)
}

func (m *Model) selectDialogRow(idx int) {
	m.Dialogs.Selected = idx
	m.selectedAccount, m.selectedChat = "", ""
	if idx >= 0 && idx < len(m.Dialogs.Rows) {
		m.selectedAccount = m.Dialogs.Rows[idx].Account
		m.selectedChat = m.Dialogs.Rows[idx].ChatID
	}
}

func dialogRowsContain(rows []dialogs.Entry, account, chat string) bool {
	for _, r := range rows {
		if r.Account == account && r.ChatID == chat {
			return true
		}
	}
	return false
}

func (m *Model) setDialogRows(rows []dialogs.Entry, storeFeed bool) {
	prevIdx := m.Dialogs.Selected
	if storeFeed {
		m.dialogFeed = rows
	}
	words := dialogs.SearchWords(m.Search.Text)
	visible := rows
	if len(words) > 0 {
		visible = make([]dialogs.Entry, 0, len(rows))
		for _, r := range rows {
			if dialogs.MatchesWords(r.Name, words) {
				visible = append(visible, r)
			}
		}
	}
	m.Dialogs.Rows = visible
	m.Dialogs.Selected = -1
	if m.selectedAccount != "" || m.selectedChat != "" {
		for i, r := range visible {
			if r.Account == m.selectedAccount && r.ChatID == m.selectedChat {
				m.Dialogs.Selected = i
				break
			}
		}
		if m.Dialogs.Selected < 0 && !dialogRowsContain(rows, m.selectedAccount, m.selectedChat) {
			m.selectedAccount, m.selectedChat = "", ""
		}
	} else if len(words) == 0 && prevIdx >= 0 && prevIdx < len(visible) {
		m.Dialogs.Selected = prevIdx
		m.selectedAccount = visible[prevIdx].Account
		m.selectedChat = visible[prevIdx].ChatID
	}
	m.DialogsScroll.Top = m.clampDialogsScroll(m.DialogsScroll.Top)
	m.dialogsToUpCheck()
}

func snapshotRow(c snapshotChat, accountID string, now time.Time) dialogs.Entry {
	e := dialogs.Entry{
		Account:     accountID,
		ChatID:      c.ChatID,
		Name:        c.Title,
		Unread:      c.UnreadCount,
		UnreadMark:  c.UnreadMark,
		UnreadMuted: c.IsMuted,
		Mention:     c.UnreadMentionCount > 0,
		Reaction:    c.UnreadReactionCount > 0,
		Pinned:      c.IsPinned,
		SortTime:    c.LastMsgTime,
		Group:       c.Type == chatKindGroup || c.Type == chatKindTopic,
	}
	switch {
	case c.IsForum:
		e.ChatType = dialogs.ChatForum
	case c.Type == chatKindChannel:
		e.ChatType = dialogs.ChatChannel
	case c.Type == chatKindDM && c.IsBot:
		e.ChatType = dialogs.ChatBot
	default:
		e.ChatType = dialogs.ChatPlain
	}
	if c.LastMsgTime > 0 {
		e.Preview = snapshotPreview(c)
		e.Date = FormatDialogsDate(time.UnixMilli(c.LastMsgTime), now)
		e.SendState = snapshotSendState(c.LastMsgIsOutgoing, c.LastMsgStatus)
	}
	return e
}

func snapshotPreview(c snapshotChat) string {
	if c.LastMsgSender != "" && c.LastMsgText != "" &&
		(c.Type == chatKindGroup || c.Type == chatKindTopic) {
		return c.LastMsgSender + ": " + c.LastMsgText
	}
	return c.LastMsgText
}

func snapshotSendState(outgoing bool, status int) dialogs.SendState {
	if !outgoing {
		return dialogs.SendHidden
	}
	switch status {
	case msgWireStatusSending:
		return dialogs.SendSending
	case msgWireStatusSent, msgWireStatusDelivered:
		return dialogs.SendSent
	case msgWireStatusRead:
		return dialogs.SendReceived
	}
	return dialogs.SendHidden
}

func (m Model) applyMsgReceived(env engineEnvelope) (Model, Cmd) {
	if !m.OpenValid || env.AccountID != m.Open.Account {
		return m, nil
	}
	var d msgReceivedData
	if json.Unmarshal(env.Data, &d) != nil || d.ChatID != m.Open.ID {
		return m, nil
	}
	wm := WireMessage{
		ID:          d.Message.MsgID,
		SenderID:    d.Message.SenderID,
		SenderName:  d.Message.SenderName,
		Text:        d.Message.ContentText,
		TimestampMs: d.Message.Timestamp,
		Status:      d.Message.Status,
		Out:         d.Message.IsOutgoing,
		Service:     d.Message.IsService,
	}
	atBottom := m.ChatScroll.Top >= m.Chat.MaxOffset(m.ChatScroll)
	fresh := make([]WireMessage, 0, len(m.chatMsgs)+1)
	fresh = append(fresh, m.chatMsgs...)
	fresh = append(fresh, wm)
	m.chatMsgs = fresh
	m.Chat.Items = FeedItems(fresh, time.UnixMilli(env.TimestampMs), m.openGroup)
	m.Chat.Heights = nil
	m.Chat.Hits = nil
	m.ChatDirty = true
	if atBottom {
		m.chatJumpBottom = true
	}
	return m, nil
}

func FeedItems(msgs []WireMessage, now time.Time, group bool) []history.Item {
	items := make([]history.Item, 0, len(msgs))
	prevTs := int64(0)
	prevSender := ""
	prevMessage := false
	for _, wm := range msgs {
		it := history.Item{Kind: history.ItemMessage, Text: wm.Text}
		if wm.Service {
			it.Kind = history.ItemService
		} else {
			it.Out = wm.Out
			it.Sending = wm.Status == msgWireStatusSending
			it.TimeText = time.UnixMilli(wm.TimestampMs).Format("15:04")
			if group && !wm.Out && wm.SenderName != "" {
				it.FromName = wm.SenderName
			}
		}
		divider := len(items) == 0 || !sameLocalDay(prevTs, wm.TimestampMs)
		if divider {
			it.DateText = DayDividerText(time.UnixMilli(wm.TimestampMs), now)
		} else if prevMessage && !wm.Service && prevSender == wm.SenderID &&
			absInt64(wm.TimestampMs-prevTs) < attachWindowMs {
			it.AttachedTop = true
			items[len(items)-1].AttachedBottom = true
		}
		items = append(items, it)
		prevTs = wm.TimestampMs
		prevSender = wm.SenderID
		prevMessage = !wm.Service
	}
	return items
}

var weekdayShort = [...]string{"Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"}

func FormatDialogsDate(t, now time.Time) string {
	if sameCalendarDay(t, now) || absDuration(now.Sub(t)) < dialogsRecentWindow {
		return t.Format("15:04")
	}
	if calendarDayDistance(t, now) < 7 {
		return weekdayShort[(int(t.Weekday())+6)%7]
	}
	return t.Format("1/2/06")
}

const dialogsRecentWindow = 20 * time.Hour

func DayDividerText(t, now time.Time) string {
	text := t.Month().String() + " " + strconv.Itoa(t.Day())
	if dividerShowsYear(t, now) {
		return text + ", " + strconv.Itoa(t.Year())
	}
	return text
}

func dividerShowsYear(t, now time.Time) bool {
	ty, ny := t.Year(), now.Year()
	if ty == ny {
		return false
	}
	tm, nm := int(t.Month()), int(now.Month())
	muchGreater := func(y, m, oy, om int) bool {
		return y == oy+1 && m+12 > om+3
	}
	if ty > ny+1 || ny > ty+1 {
		return true
	}
	return muchGreater(ty, tm, ny, nm) || muchGreater(ny, nm, ty, tm)
}

func sameCalendarDay(a, b time.Time) bool {
	return a.Year() == b.Year() && a.Month() == b.Month() && a.Day() == b.Day()
}

func sameLocalDay(aMs, bMs int64) bool {
	a, b := time.UnixMilli(aMs), time.UnixMilli(bMs)
	return sameCalendarDay(a, b)
}

func calendarDayDistance(a, b time.Time) int {
	na := time.Date(a.Year(), a.Month(), a.Day(), 0, 0, 0, 0, time.UTC).Unix() / 86400
	nb := time.Date(b.Year(), b.Month(), b.Day(), 0, 0, 0, 0, time.UTC).Unix() / 86400
	if na < nb {
		return int(nb - na)
	}
	return int(na - nb)
}

func absDuration(d time.Duration) time.Duration {
	if d < 0 {
		return -d
	}
	return d
}

func absInt64(v int64) int64 {
	if v < 0 {
		return -v
	}
	return v
}
