package tests

import (
	"fmt"
	"testing"
	"time"

	. "uniclient/ui/app"
	"uniclient/ui/dialogs"
	"uniclient/ui/dialogs/render"
	"uniclient/ui/history"
	chatrender "uniclient/ui/history/render"
	"uniclient/ui/material"
	"uniclient/ui/tokens"
)

type fakeChatPort struct {
	msgs    []WireMessage
	ok      bool
	account string
	chat    string
	limit   int
}

func (p *fakeChatPort) Messages(accountID, chatID string, limit int) ([]WireMessage, bool) {
	p.account, p.chat, p.limit = accountID, chatID, limit
	return p.msgs, p.ok
}

func (p *fakeChatPort) Send(accountID, chatID, text string) bool {
	return true
}

func feedsModel(t *testing.T, w, h int) Model {
	t.Helper()
	m := bridgeModel(t, w, h)
	return applyEngineEvent(t, m, accountListWire)
}

func chatSnapshotWire(accountID string, chats string, nowMs int64) string {
	return fmt.Sprintf(`{"type":"chat_snapshot","account_id":%q,"timestamp_ms":%d,"data":{"chats":[%s]}}`,
		accountID, nowMs, chats)
}

func localMs(year int, mon time.Month, day, hour, min int) int64 {
	return time.Date(year, mon, day, hour, min, 0, 0, time.Local).UnixMilli()
}

func snapshotChats(nowMs int64, chatID, title, text string, chatType int, sender string, outgoing bool, status int, unread int, pinned bool) string {
	return fmt.Sprintf(`{"account_id":"tele_02","chat_id":%q,"type":%d,"title":%q,`+
		`"last_msg_text":%q,"last_msg_time":%d,"last_msg_sender":%q,"last_msg_is_outgoing":%t,`+
		`"last_msg_status":%d,"unread_count":%d,"is_muted":false,"is_pinned":%t,"is_bot":false,"is_forum":false}`,
		chatID, chatType, title, text, nowMs-60000, sender, outgoing, status, unread, pinned)
}

const snapshotGroupWireTmpl = `{"account_id":"tele_02","chat_id":"-400","type":2,"title":"Dev Crew",` +
	`"last_msg_text":"release notes","last_msg_time":%d,"last_msg_sender":"bob",` +
	`"last_msg_is_outgoing":false,"last_msg_status":2,"unread_count":5,` +
	`"unread_mention_count":1,"unread_reaction_count":1,"unread_mark":true,` +
	`"is_muted":true,"is_pinned":true,"is_bot":false,"is_forum":true}`

const snapshotNoMessageWire = `{"account_id":"tele_02","chat_id":"10","type":1,"title":"Fresh",` +
	`"unread_count":0,"is_muted":false,"is_pinned":false,"is_bot":false,"is_forum":false}`

func TestChatSnapshotProjectsDialogRows(t *testing.T) {
	nowMs := localMs(2026, time.November, 30, 15, 0)
	group := fmt.Sprintf(snapshotGroupWireTmpl, localMs(2026, time.November, 30, 14, 2))
	dm := snapshotChats(nowMs, "77", "Alice", "hi there", 1, "", false, 0, 0, false)
	m := applyEngineEvent(t, feedsModel(t, 1440, 900), chatSnapshotWire("tele_02", group+","+dm+","+snapshotNoMessageWire, nowMs))
	if len(m.Dialogs.Rows) != 3 {
		t.Fatalf("rows = %d, want 3", len(m.Dialogs.Rows))
	}
	first, second, third := m.Dialogs.Rows[0], m.Dialogs.Rows[1], m.Dialogs.Rows[2]
	if first.Name != "Dev Crew" || first.Preview != "bob: release notes" || first.Unread != 5 {
		t.Fatalf("group row mapped wrong: %+v", first)
	}
	if first.ChatType != dialogs.ChatForum || !first.UnreadMark || !first.Mention || !first.Reaction || !first.Pinned || !first.UnreadMuted {
		t.Fatalf("group row flags wrong: type=%d mark=%v mention=%v reaction=%v pinned=%v muted=%v",
			first.ChatType, first.UnreadMark, first.Mention, first.Reaction, first.Pinned, first.UnreadMuted)
	}
	if first.Date != "14:02" {
		t.Fatalf("group row date = %q, want 14:02", first.Date)
	}
	if first.Account != "tele_02" || first.ChatID != "-400" || !first.Group {
		t.Fatalf("group row identity: %+v", first)
	}
	if second.Name != "Alice" || second.Preview != "hi there" || second.ChatType != dialogs.ChatPlain {
		t.Fatalf("dm row mapped wrong: %+v", second)
	}
	if second.Account != "tele_02" || second.ChatID != "77" || second.Group {
		t.Fatalf("dm row identity: %+v", second)
	}
	if second.Date != "14:59" {
		t.Fatalf("dm row date = %q, want 14:59", second.Date)
	}
	if third.Name != "Fresh" || third.Date != "" || third.Preview != "" {
		t.Fatalf("message-less row must stay dateless and previewless: %+v", third)
	}
}

func TestChatSnapshotOutgoingReadSendState(t *testing.T) {
	nowMs := localMs(2026, time.November, 30, 15, 0)
	outgoing := snapshotChats(nowMs, "55", "Work", "sent", 1, "me", true, 4, 2, false)
	m := applyEngineEvent(t, feedsModel(t, 1440, 900), chatSnapshotWire("tele_02", outgoing, nowMs))
	row := m.Dialogs.Rows[0]
	if row.SendState != dialogs.SendReceived {
		t.Fatalf("outgoing read row SendState = %d, want %d", row.SendState, dialogs.SendReceived)
	}
	if row.Preview != "sent" {
		t.Fatalf("dm outgoing preview = %q, want plain text", row.Preview)
	}
}

func TestChatSnapshotReplacesAccountRowsAndMergesAccounts(t *testing.T) {
	nowMs := localMs(2026, time.November, 30, 15, 0)
	teleFirst := snapshotChats(nowMs, "77", "Alice", "hi", 1, "", false, 0, 0, false)
	m := applyEngineEvent(t, feedsModel(t, 1440, 900), chatSnapshotWire("tele_02", teleFirst, nowMs))
	teleSecond := snapshotChats(nowMs, "88", "Bob", "yo", 1, "", false, 0, 0, false)
	m = applyEngineEvent(t, m, chatSnapshotWire("tele_02", teleSecond, nowMs))
	if len(m.Dialogs.Rows) != 1 || m.Dialogs.Rows[0].ChatID != "88" {
		t.Fatalf("second snapshot must replace the account's rows: %+v", m.Dialogs.Rows)
	}
	xm := fmt.Sprintf(`{"account_id":"xm_01","chat_id":"room1","type":2,"title":"Pals Room",`+
		`"last_msg_text":"hello","last_msg_time":%d,"last_msg_sender":"zed",`+
		`"last_msg_is_outgoing":false,"last_msg_status":2,"unread_count":0,`+
		`"is_muted":false,"is_pinned":false,"is_bot":false,"is_forum":false}`, nowMs-120000)
	m = applyEngineEvent(t, m, chatSnapshotWire("xm_01", xm, nowMs))
	if len(m.Dialogs.Rows) != 2 {
		t.Fatalf("merged rows = %d, want 2", len(m.Dialogs.Rows))
	}
	if m.Dialogs.Rows[0].Account != "xm_01" || m.Dialogs.Rows[1].Account != "tele_02" {
		t.Fatalf("merge order must follow account sort_order: %+v", m.Dialogs.Rows)
	}
	unknown := snapshotChats(nowMs, "99", "Ghost", "boo", 1, "", false, 0, 0, false)
	m = applyEngineEvent(t, m, chatSnapshotWire("ghost_09", unknown, nowMs))
	if len(m.Dialogs.Rows) != 2 {
		t.Fatalf("snapshot for unknown account must drop its rows, got %d", len(m.Dialogs.Rows))
	}
}

func TestChatSnapshotEmptyChatsClearsAccount(t *testing.T) {
	nowMs := localMs(2026, time.November, 30, 15, 0)
	row := snapshotChats(nowMs, "77", "Alice", "hi", 1, "", false, 0, 0, false)
	m := applyEngineEvent(t, feedsModel(t, 1440, 900), chatSnapshotWire("tele_02", row, nowMs))
	m = applyEngineEvent(t, m, chatSnapshotWire("tele_02", "", nowMs))
	if len(m.Dialogs.Rows) != 0 {
		t.Fatalf("empty snapshot must clear the account's rows, got %d", len(m.Dialogs.Rows))
	}
}

func TestChatSnapshotIgnoredCases(t *testing.T) {
	nowMs := localMs(2026, time.November, 30, 15, 0)
	base := applyEngineEvent(t, feedsModel(t, 1440, 900),
		chatSnapshotWire("tele_02", snapshotChats(nowMs, "77", "Alice", "hi", 1, "", false, 0, 0, false), nowMs))
	for name, wire := range map[string]string{
		"malformed":    "{not json",
		"bad-data":     `{"type":"chat_snapshot","account_id":"tele_02","timestamp_ms":1,"data":{"chats":"no"}}`,
		"chat-not-obj": `{"type":"chat_snapshot","account_id":"tele_02","timestamp_ms":1,"data":{"chats":[42]}}`,
		"unknown-type": `{"type":"chat_updated","account_id":"tele_02","timestamp_ms":1,"data":{}}`,
		"no-payload":   `{"type":"chat_snapshot","account_id":"tele_02","timestamp_ms":1}`,
	} {
		next := applyEngineEvent(t, base, wire)
		if len(next.Dialogs.Rows) != 1 || next.Dialogs.Rows[0].ChatID != "77" {
			t.Fatalf("%s mutated rows: %+v", name, next.Dialogs.Rows)
		}
	}
}

func TestChatSnapshotClampsSelection(t *testing.T) {
	nowMs := localMs(2026, time.November, 30, 15, 0)
	three := snapshotChats(nowMs, "77", "Alice", "a", 1, "", false, 0, 0, false) + "," +
		snapshotChats(nowMs, "88", "Bob", "b", 1, "", false, 0, 0, false) + "," +
		snapshotChats(nowMs, "99", "Cid", "c", 1, "", false, 0, 0, false)
	m := applyEngineEvent(t, feedsModel(t, 1440, 900), chatSnapshotWire("tele_02", three, nowMs))
	m, _ = Update(m, DialogRowPressed{Index: 2})
	m = applyEngineEvent(t, m, chatSnapshotWire("tele_02", snapshotChats(nowMs, "77", "Alice", "a", 1, "", false, 0, 0, false), nowMs))
	if m.Dialogs.Selected != -1 {
		t.Fatalf("selection clamp after snapshot: Selected = %d, want -1", m.Dialogs.Selected)
	}
}

func TestOpenChatJourney(t *testing.T) {
	nowMs := localMs(2026, time.November, 30, 15, 0)
	row := snapshotChats(nowMs, "77", "Alice", "hi", 1, "", false, 0, 0, false)
	port := &fakeChatPort{ok: true, msgs: []WireMessage{
		{ID: "m1", SenderID: "u1", SenderName: "Alice", Text: "hello", TimestampMs: localMs(2026, time.November, 30, 14, 0), Status: 2},
		{ID: "m2", SenderID: "u1", SenderName: "Alice", Text: "world", TimestampMs: localMs(2026, time.November, 30, 14, 5), Status: 4, Out: true},
	}}
	m := applyEngineEvent(t, feedsModel(t, 1440, 900).WithPort(port), chatSnapshotWire("tele_02", row, nowMs))
	next, cmd := Update(m, DialogsPressed{X: 20, Y: 10, Now: 2})
	if cmd == nil {
		t.Fatal("row press must produce an open cmd when selection changes")
	}
	if next.Open != (ChatRef{Account: "tele_02", ID: "77"}) || !next.OpenValid {
		t.Fatalf("open ref = %+v valid=%v", next.Open, next.OpenValid)
	}
	msg := cmd()
	loaded, ok := msg.(ChatLoaded)
	if !ok {
		t.Fatalf("open cmd produced %T, want ChatLoaded", msg)
	}
	if port.account != "tele_02" || port.chat != "77" || port.limit <= 0 {
		t.Fatalf("port called wrong: account=%q chat=%q limit=%d", port.account, port.chat, port.limit)
	}
	if len(loaded.Msgs) != 2 {
		t.Fatalf("loaded Msgs = %d, want 2", len(loaded.Msgs))
	}
	next, _ = Update(next, loaded)
	if len(next.Chat.Items) != 2 {
		t.Fatalf("items = %d, want 2", len(next.Chat.Items))
	}
	heights := []int{40, 60}
	next, _ = Update(next, ChatMeasured{Heights: heights})
	if next.Chat.MaxOffset(next.ChatScroll) != 0 {
		t.Fatalf("short history must not overflow, max offset = %d", next.Chat.MaxOffset(next.ChatScroll))
	}
	if next.ChatScroll.Top != 0 {
		t.Fatalf("fresh-open scroll Top = %d, want 0", next.ChatScroll.Top)
	}
}

func TestOpenChatJourneyJumpsToBottomOnTallHistory(t *testing.T) {
	nowMs := localMs(2026, time.November, 30, 15, 0)
	row := snapshotChats(nowMs, "77", "Alice", "hi", 1, "", false, 0, 0, false)
	msgs := make([]WireMessage, 30)
	for i := range msgs {
		msgs[i] = WireMessage{ID: fmt.Sprintf("m%d", i), SenderID: "u1", SenderName: "Alice",
			Text: "msg", TimestampMs: nowMs - int64(30-i)*60000, Status: 2}
	}
	port := &fakeChatPort{ok: true, msgs: msgs}
	m := applyEngineEvent(t, feedsModel(t, 1440, 900).WithPort(port), chatSnapshotWire("tele_02", row, nowMs))
	next, cmd := Update(m, DialogsPressed{X: 20, Y: 10, Now: 1})
	if cmd == nil {
		t.Fatal("press must produce cmd")
	}
	next, _ = Update(next, cmd())
	heights := make([]int, len(msgs))
	for i := range heights {
		heights[i] = 100
	}
	next, _ = Update(next, ChatMeasured{Heights: heights})
	want := next.Chat.MaxOffset(next.ChatScroll)
	if want <= 0 {
		t.Fatalf("tall history must overflow viewport, max offset = %d", want)
	}
	if next.ChatScroll.Top != want {
		t.Fatalf("fresh open Top = %d, want %d (bottom)", next.ChatScroll.Top, want)
	}
}

func TestOpenChatNilPortSafe(t *testing.T) {
	nowMs := localMs(2026, time.November, 30, 15, 0)
	row := snapshotChats(nowMs, "77", "Alice", "hi", 1, "", false, 0, 0, false)
	m := applyEngineEvent(t, feedsModel(t, 1440, 900), chatSnapshotWire("tele_02", row, nowMs))
	next, cmd := Update(m, DialogsPressed{X: 20, Y: 10, Now: 1})
	if next.Dialogs.Selected != 0 {
		t.Fatalf("selection = %d, want 0", next.Dialogs.Selected)
	}
	if next.OpenValid {
		t.Fatal("open ref must stay invalid without a port")
	}
	if cmd != nil {
		t.Fatal("no port -> no cmd")
	}
}

func TestPressSameRowAgainNoReload(t *testing.T) {
	nowMs := localMs(2026, time.November, 30, 15, 0)
	row := snapshotChats(nowMs, "77", "Alice", "hi", 1, "", false, 0, 0, false)
	port := &fakeChatPort{ok: true}
	m := applyEngineEvent(t, feedsModel(t, 1440, 900).WithPort(port), chatSnapshotWire("tele_02", row, nowMs))
	m, _ = Update(m, DialogsPressed{X: 20, Y: 10, Now: 1})
	_, cmd := Update(m, DialogsPressed{X: 20, Y: 10, Now: 2})
	if cmd != nil {
		t.Fatal("pressing the already-selected row must not reload")
	}
}

func TestFeedItemsProjection(t *testing.T) {
	now := time.UnixMilli(localMs(2026, time.November, 30, 15, 0))
	base := localMs(2026, time.November, 30, 14, 0)
	msgs := []WireMessage{
		{ID: "m1", SenderID: "u1", SenderName: "Alice", Text: "one", TimestampMs: base, Status: 2},
		{ID: "m2", SenderID: "u1", SenderName: "Alice", Text: "two", TimestampMs: base + 899000, Status: 1, Out: true},
		{ID: "m3", SenderID: "u2", SenderName: "Bob", Text: "three", TimestampMs: base + 900000, Status: 2},
		{ID: "m4", SenderID: "u2", SenderName: "Bob", Text: "four", TimestampMs: base + 1800000, Status: 2},
		{ID: "m5", SenderID: "u2", SenderName: "Bob", Text: "Bob joined the group", TimestampMs: base + 1801000, Service: true, Status: 2},
		{ID: "m6", SenderID: "u2", SenderName: "Bob", Text: "six", TimestampMs: base + 1802000, Status: 2},
		{ID: "m7", SenderID: "u2", SenderName: "Bob", Text: "seven", TimestampMs: localMs(2026, time.December, 1, 9, 30), Status: 2},
	}
	items := FeedItems(msgs, now, true)
	if len(items) != 7 {
		t.Fatalf("items = %d, want 7", len(items))
	}
	if items[0].DateText == "" || items[0].AttachedTop {
		t.Fatalf("first item: divider=%q attached=%v", items[0].DateText, items[0].AttachedTop)
	}
	if !items[0].AttachedBottom {
		t.Fatal("items[0] must attach to items[1] (same sender, 899s)")
	}
	if !items[1].AttachedTop || items[1].AttachedBottom {
		t.Fatalf("items[1] attachment wrong: top=%v bottom=%v (top must attach to [0], bottom broken by sender change)",
			items[1].AttachedTop, items[1].AttachedBottom)
	}
	if items[2].AttachedTop || items[2].AttachedBottom {
		t.Fatalf("items[2] attachment wrong: sender changed vs [1]")
	}
	if items[3].AttachedTop || items[3].AttachedBottom {
		t.Fatalf("items[3] must not attach: 900s exactly breaks the chain: top=%v bottom=%v",
			items[3].AttachedTop, items[3].AttachedBottom)
	}
	if items[4].Kind != history.ItemService || items[4].AttachedTop || items[4].AttachedBottom {
		t.Fatalf("service item: kind=%v top=%v bottom=%v", items[4].Kind, items[4].AttachedTop, items[4].AttachedBottom)
	}
	if items[3].AttachedBottom {
		t.Fatal("service message must break the chain after items[3]")
	}
	if items[5].AttachedTop || items[5].AttachedBottom {
		t.Fatalf("items[5] must not attach across the service message: top=%v bottom=%v",
			items[5].AttachedTop, items[5].AttachedBottom)
	}
	if items[6].AttachedTop || items[6].DateText == "" {
		t.Fatalf("day change must break attachment and carry a divider: top=%v divider=%q",
			items[6].AttachedTop, items[6].DateText)
	}
	if items[6].TimeText != "09:30" {
		t.Fatalf("time text = %q, want 09:30", items[6].TimeText)
	}
	if !items[1].Out || !items[1].Sending {
		t.Fatal("items[1] must map Out and Sending (status 1)")
	}
	if items[2].FromName != "Bob" {
		t.Fatalf("group incoming FromName = %q, want Bob", items[2].FromName)
	}
	if items[1].FromName != "" {
		t.Fatalf("outgoing group FromName must stay empty, got %q", items[1].FromName)
	}
	dmItems := FeedItems(msgs[:2], now, false)
	if dmItems[0].FromName != "" {
		t.Fatalf("dm FromName must stay empty, got %q", dmItems[0].FromName)
	}
}

func TestMsgReceivedAppendsToOpenChat(t *testing.T) {
	nowMs := localMs(2026, time.November, 30, 15, 0)
	row := snapshotChats(nowMs, "77", "Alice", "hi", 1, "", false, 0, 0, false)
	m := applyEngineEvent(t, feedsModel(t, 1440, 900).WithPort(&fakeChatPort{ok: true}), chatSnapshotWire("tele_02", row, nowMs))
	m, cmd := Update(m, DialogsPressed{X: 20, Y: 10, Now: 1})
	if cmd == nil {
		t.Fatal("press must open the chat")
	}
	m, _ = Update(m, cmd())
	m = appendLive(t, m, nowMs, "m1", "hello", nowMs-600000)
	if len(m.Chat.Items) != 1 {
		t.Fatalf("open chat must receive the message, items = %d", len(m.Chat.Items))
	}
	m = appendLive(t, m, nowMs, "m2", "live one", nowMs)
	if len(m.Chat.Items) != 2 {
		t.Fatalf("second live message dropped, items = %d", len(m.Chat.Items))
	}
	if !m.Chat.Items[0].AttachedBottom || !m.Chat.Items[1].AttachedTop {
		t.Fatalf("live append must recompute attachment: %+v %+v", m.Chat.Items[0], m.Chat.Items[1])
	}
	other := `{"type":"msg_received","account_id":"tele_02","timestamp_ms":` + fmt.Sprint(nowMs) +
		`,"data":{"account_id":"tele_02","chat_id":"88","message":{"msg_id":"m9","chat_id":"88",` +
		`"account_id":"tele_02","sender_id":"u9","sender_name":"Zed","content_text":"not this chat",` +
		`"timestamp":` + fmt.Sprint(nowMs) + `,"status":2,"is_outgoing":false,"is_service":false}}}`
	m = applyEngineEvent(t, m, other)
	if len(m.Chat.Items) != 2 {
		t.Fatal("msg_received for a non-open chat must not touch items")
	}
}

func TestMsgReceivedKeepsBottomWhenAtBottom(t *testing.T) {
	nowMs := localMs(2026, time.November, 30, 15, 0)
	row := snapshotChats(nowMs, "77", "Alice", "hi", 1, "", false, 0, 0, false)
	m := applyEngineEvent(t, feedsModel(t, 1440, 900).WithPort(&fakeChatPort{ok: true}), chatSnapshotWire("tele_02", row, nowMs))
	next, cmd := Update(m, DialogsPressed{X: 20, Y: 10, Now: 1})
	if cmd == nil {
		t.Fatal("press must open the chat")
	}
	m, _ = Update(next, cmd())
	for i := range 8 {
		m = appendLive(t, m, nowMs, fmt.Sprintf("m%d", i), fmt.Sprintf("m%d", i), nowMs-int64(8-i)*60000)
	}
	heights := make([]int, 8)
	for i := range heights {
		heights[i] = 150
	}
	m, _ = Update(m, ChatMeasured{Heights: heights})
	bottom := m.Chat.MaxOffset(m.ChatScroll)
	if bottom <= 0 {
		t.Fatalf("test setup must overflow the viewport, max offset = %d", bottom)
	}
	m.ChatScroll.Top = bottom
	m = appendLive(t, m, nowMs, "m8", "m8", nowMs+60000)
	m, _ = Update(m, ChatMeasured{Heights: append(heights, 150)})
	if m.ChatScroll.Top != m.Chat.MaxOffset(m.ChatScroll) {
		t.Fatalf("at-bottom append must stay at bottom: top=%d want=%d",
			m.ChatScroll.Top, m.Chat.MaxOffset(m.ChatScroll))
	}
}

func appendLive(t *testing.T, m Model, nowMs int64, id, text string, ts int64) Model {
	t.Helper()
	return applyEngineEvent(t, m, `{"type":"msg_received","account_id":"tele_02","timestamp_ms":`+
		fmt.Sprint(nowMs)+`,"data":{"account_id":"tele_02","chat_id":"77","message":`+
		`{"msg_id":"`+id+`","chat_id":"77","account_id":"tele_02","sender_id":"u1",`+
		`"sender_name":"Alice","content_text":"`+text+`","timestamp":`+fmt.Sprint(ts)+
		`,"status":2,"is_outgoing":false,"is_service":false}}}`)
}

func chatUpdatedWire(accountID string, chat string, nowMs int64) string {
	return fmt.Sprintf(`{"type":"chat_updated","account_id":%q,"timestamp_ms":%d,"data":{"chat":%s}}`,
		accountID, nowMs, chat)
}

func TestChatUpdatedReplacesRowContent(t *testing.T) {
	nowMs := localMs(2026, time.November, 30, 15, 0)
	alice := snapshotChats(nowMs, "77", "Alice", "hi", 1, "", false, 0, 2, false)
	bob := snapshotChats(nowMs, "88", "Bob", "yo", 1, "", false, 0, 0, false)
	m := applyEngineEvent(t, feedsModel(t, 1440, 900), chatSnapshotWire("tele_02", alice+","+bob, nowMs))
	updated := fmt.Sprintf(`{"account_id":"tele_02","chat_id":"77","type":1,"title":"Alice Smith",`+
		`"last_msg_text":"new message","last_msg_time":%d,"last_msg_sender":"",`+
		`"last_msg_is_outgoing":false,"last_msg_status":2,"unread_count":0,`+
		`"unread_mention_count":1,"unread_mark":true,"is_muted":true,"is_pinned":false,`+
		`"is_bot":false,"is_forum":false}`, localMs(2026, time.November, 30, 14, 30))
	m = applyEngineEvent(t, m, chatUpdatedWire("tele_02", updated, nowMs))
	if len(m.Dialogs.Rows) != 2 {
		t.Fatalf("update must not change row count, rows = %d", len(m.Dialogs.Rows))
	}
	row := m.Dialogs.Rows[1]
	if row.Name != "Alice Smith" || row.Preview != "new message" || row.Unread != 0 ||
		!row.UnreadMark || !row.Mention || !row.UnreadMuted {
		t.Fatalf("updated row content wrong: %+v", row)
	}
	if row.Date != "14:30" {
		t.Fatalf("updated row date = %q, want 14:30", row.Date)
	}
	other := m.Dialogs.Rows[0]
	if other.Name != "Bob" || other.Preview != "yo" || other.Unread != 0 || other.UnreadMark {
		t.Fatalf("untouched row mutated: %+v", other)
	}
}

func TestChatUpdatedMovesRowByEngineListLaw(t *testing.T) {
	nowMs := localMs(2026, time.November, 30, 15, 0)
	older := fmt.Sprintf(`{"account_id":"tele_02","chat_id":"77","type":1,"title":"Alice",`+
		`"last_msg_text":"old","last_msg_time":%d,"last_msg_is_outgoing":false,`+
		`"last_msg_status":2,"unread_count":0,"is_muted":false,"is_pinned":false,`+
		`"is_bot":false,"is_forum":false}`, localMs(2026, time.November, 30, 14, 0))
	newest := fmt.Sprintf(`{"account_id":"tele_02","chat_id":"88","type":1,"title":"Bob",`+
		`"last_msg_text":"newest","last_msg_time":%d,"last_msg_is_outgoing":false,`+
		`"last_msg_status":2,"unread_count":0,"is_muted":false,"is_pinned":false,`+
		`"is_bot":false,"is_forum":false}`, localMs(2026, time.November, 30, 14, 59))
	m := applyEngineEvent(t, feedsModel(t, 1440, 900), chatSnapshotWire("tele_02", older+","+newest, nowMs))
	if m.Dialogs.Rows[0].ChatID != "88" {
		t.Fatalf("test setup: newest row must start on top, got %+v", m.Dialogs.Rows)
	}
	bumped := fmt.Sprintf(`{"account_id":"tele_02","chat_id":"77","type":1,"title":"Alice",`+
		`"last_msg_text":"just landed","last_msg_time":%d,"last_msg_is_outgoing":false,`+
		`"last_msg_status":2,"unread_count":1,"is_muted":false,"is_pinned":false,`+
		`"is_bot":false,"is_forum":false}`, nowMs-10000)
	m = applyEngineEvent(t, m, chatUpdatedWire("tele_02", bumped, nowMs))
	if m.Dialogs.Rows[0].ChatID != "77" || m.Dialogs.Rows[1].ChatID != "88" {
		t.Fatalf("fresher last message must move the row on top: %+v", m.Dialogs.Rows)
	}
	if m.Dialogs.Rows[0].Preview != "just landed" {
		t.Fatalf("moved row must carry the new preview: %+v", m.Dialogs.Rows[0])
	}
}

func TestChatUpdatedPinnedLaw(t *testing.T) {
	nowMs := localMs(2026, time.November, 30, 15, 0)
	pinned := fmt.Sprintf(`{"account_id":"tele_02","chat_id":"77","type":1,"title":"Pinned Old",`+
		`"last_msg_text":"old","last_msg_time":%d,"last_msg_is_outgoing":false,`+
		`"last_msg_status":2,"unread_count":0,"is_pinned":true,"is_bot":false,"is_forum":false}`,
		localMs(2026, time.November, 30, 10, 0))
	fresh := fmt.Sprintf(`{"account_id":"tele_02","chat_id":"88","type":1,"title":"Fresh",`+
		`"last_msg_text":"newest","last_msg_time":%d,"last_msg_is_outgoing":false,`+
		`"last_msg_status":2,"unread_count":0,"is_pinned":false,"is_bot":false,"is_forum":false}`,
		nowMs-5000)
	m := applyEngineEvent(t, feedsModel(t, 1440, 900), chatSnapshotWire("tele_02", pinned+","+fresh, nowMs))
	if m.Dialogs.Rows[0].ChatID != "77" {
		t.Fatalf("test setup: pinned row must start on top: %+v", m.Dialogs.Rows)
	}
	newestUnpinned := fmt.Sprintf(`{"account_id":"tele_02","chat_id":"88","type":1,"title":"Fresh",`+
		`"last_msg_text":"even newer","last_msg_time":%d,"last_msg_is_outgoing":false,`+
		`"last_msg_status":2,"unread_count":0,"is_pinned":false,"is_bot":false,"is_forum":false}`,
		nowMs-1000)
	m = applyEngineEvent(t, m, chatUpdatedWire("tele_02", newestUnpinned, nowMs))
	if m.Dialogs.Rows[0].ChatID != "77" || m.Dialogs.Rows[1].ChatID != "88" {
		t.Fatalf("pinned row must stay above a newer unpinned row: %+v", m.Dialogs.Rows)
	}
	nowPinned := fmt.Sprintf(`{"account_id":"tele_02","chat_id":"88","type":1,"title":"Fresh",`+
		`"last_msg_text":"even newer","last_msg_time":%d,"last_msg_is_outgoing":false,`+
		`"last_msg_status":2,"unread_count":0,"is_pinned":true,"is_bot":false,"is_forum":false}`,
		nowMs-1000)
	m = applyEngineEvent(t, m, chatUpdatedWire("tele_02", nowPinned, nowMs))
	if m.Dialogs.Rows[0].ChatID != "88" || m.Dialogs.Rows[1].ChatID != "77" {
		t.Fatalf("newly pinned newer row must rise above the older pinned: %+v", m.Dialogs.Rows)
	}
}

func TestChatUpdatedInsertsNewChatRow(t *testing.T) {
	nowMs := localMs(2026, time.November, 30, 15, 0)
	alice := snapshotChats(nowMs, "77", "Alice", "hi", 1, "", false, 0, 0, false)
	m := applyEngineEvent(t, feedsModel(t, 1440, 900), chatSnapshotWire("tele_02", alice, nowMs))
	stranger := fmt.Sprintf(`{"account_id":"tele_02","chat_id":"55","type":1,"title":"Stranger",`+
		`"last_msg_text":"hello there","last_msg_time":%d,"last_msg_is_outgoing":false,`+
		`"last_msg_status":2,"unread_count":1,"is_muted":false,"is_pinned":false,`+
		`"is_bot":false,"is_forum":false}`, nowMs-30000)
	m = applyEngineEvent(t, m, chatUpdatedWire("tele_02", stranger, nowMs))
	if len(m.Dialogs.Rows) != 2 {
		t.Fatalf("update for an unseen chat must insert a row, rows = %d", len(m.Dialogs.Rows))
	}
	if m.Dialogs.Rows[0].ChatID != "55" || m.Dialogs.Rows[0].Name != "Stranger" ||
		m.Dialogs.Rows[0].Unread != 1 || m.Dialogs.Rows[1].ChatID != "77" {
		t.Fatalf("inserted row must sort by last message time: %+v", m.Dialogs.Rows)
	}
}

func TestChatUpdatedDroppedWithoutSnapshot(t *testing.T) {
	nowMs := localMs(2026, time.November, 30, 15, 0)
	m := feedsModel(t, 1440, 900)
	stranger := snapshotChats(nowMs, "55", "Stranger", "hi", 1, "", false, 0, 0, false)
	m = applyEngineEvent(t, m, chatUpdatedWire("tele_02", stranger, nowMs))
	if len(m.Dialogs.Rows) != 0 {
		t.Fatalf("update before any snapshot must not fabricate rows: %+v", m.Dialogs.Rows)
	}
}

func TestChatUpdatedDroppedShapes(t *testing.T) {
	nowMs := localMs(2026, time.November, 30, 15, 0)
	alice := snapshotChats(nowMs, "77", "Alice", "hi", 1, "", false, 0, 0, false)
	base := applyEngineEvent(t, feedsModel(t, 1440, 900), chatSnapshotWire("tele_02", alice, nowMs))
	for name, wire := range map[string]string{
		"empty-data":  `{"type":"chat_updated","account_id":"tele_02","timestamp_ms":1,"data":{}}`,
		"chat-null":   `{"type":"chat_updated","account_id":"tele_02","timestamp_ms":1,"data":{"chat":null}}`,
		"legacy-keys": `{"type":"chat_updated","account_id":"tele_02","timestamp_ms":1,"data":{"account_id":"tele_02","chat_id":"77"}}`,
		"bad-data":    `{"type":"chat_updated","account_id":"tele_02","timestamp_ms":1,"data":{"chat":"no"}}`,
		"no-payload":  `{"type":"chat_updated","account_id":"tele_02","timestamp_ms":1}`,
		"no-chat-id":  `{"type":"chat_updated","account_id":"tele_02","timestamp_ms":1,"data":{"chat":{"title":"No ID","unread_count":9}}}`,
		"unknown-acc": chatUpdatedWire("ghost_09", snapshotChats(nowMs, "77", "Alice", "hi", 1, "", false, 0, 0, false), nowMs),
	} {
		next := applyEngineEvent(t, base, wire)
		if len(next.Dialogs.Rows) != 1 || next.Dialogs.Rows[0].ChatID != "77" ||
			next.Dialogs.Rows[0].Unread != 0 {
			t.Fatalf("%s mutated rows: %+v", name, next.Dialogs.Rows)
		}
	}
}

func TestChatUpdatedSelectionFollowsMovedRow(t *testing.T) {
	nowMs := localMs(2026, time.November, 30, 15, 0)
	older := fmt.Sprintf(`{"account_id":"tele_02","chat_id":"77","type":1,"title":"Alice",`+
		`"last_msg_text":"old","last_msg_time":%d,"last_msg_is_outgoing":false,`+
		`"last_msg_status":2,"unread_count":0,"is_muted":false,"is_pinned":false,`+
		`"is_bot":false,"is_forum":false}`, localMs(2026, time.November, 30, 14, 0))
	newer := fmt.Sprintf(`{"account_id":"tele_02","chat_id":"88","type":1,"title":"Bob",`+
		`"last_msg_text":"newest","last_msg_time":%d,"last_msg_is_outgoing":false,`+
		`"last_msg_status":2,"unread_count":0,"is_muted":false,"is_pinned":false,`+
		`"is_bot":false,"is_forum":false}`, localMs(2026, time.November, 30, 14, 59))
	m := applyEngineEvent(t, feedsModel(t, 1440, 900), chatSnapshotWire("tele_02", older+","+newer, nowMs))
	m, _ = Update(m, DialogRowPressed{Index: 1})
	if m.Dialogs.Selected != 1 || m.Dialogs.Rows[1].ChatID != "77" {
		t.Fatalf("test setup: selection wrong: idx=%d chat=%q", m.Dialogs.Selected, m.Dialogs.Rows[m.Dialogs.Selected].ChatID)
	}
	bumped := fmt.Sprintf(`{"account_id":"tele_02","chat_id":"77","type":1,"title":"Alice",`+
		`"last_msg_text":"bumped","last_msg_time":%d,"last_msg_is_outgoing":false,`+
		`"last_msg_status":2,"unread_count":0,"is_muted":false,"is_pinned":false,`+
		`"is_bot":false,"is_forum":false}`, nowMs-10000)
	m = applyEngineEvent(t, m, chatUpdatedWire("tele_02", bumped, nowMs))
	if m.Dialogs.Selected != 0 || m.Dialogs.Rows[0].ChatID != "77" {
		t.Fatalf("selection must follow the moved row: idx=%d chat=%q", m.Dialogs.Selected,
			m.Dialogs.Rows[max(m.Dialogs.Selected, 0)].ChatID)
	}
}

func TestChatUpdatedReAppliesSearchFilter(t *testing.T) {
	nowMs := localMs(2026, time.November, 30, 15, 0)
	alice := snapshotChats(nowMs, "77", "Alice", "a", 1, "", false, 0, 0, false)
	bob := snapshotChats(nowMs, "88", "Bob", "b", 1, "", false, 0, 0, false)
	m := applyEngineEvent(t, feedsModel(t, 1440, 900), chatSnapshotWire("tele_02", alice+","+bob, nowMs))
	m, _ = Update(m, SearchTyped{Text: "bob"})
	if len(m.Dialogs.Rows) != 1 || m.Dialogs.Rows[0].ChatID != "88" {
		t.Fatalf("test setup: filter must hide Alice: %+v", m.Dialogs.Rows)
	}
	renamed := fmt.Sprintf(`{"account_id":"tele_02","chat_id":"77","type":1,"title":"Bob Smith",`+
		`"last_msg_text":"a","last_msg_time":%d,"last_msg_is_outgoing":false,`+
		`"last_msg_status":2,"unread_count":0,"is_muted":false,"is_pinned":false,`+
		`"is_bot":false,"is_forum":false}`, localMs(2026, time.November, 30, 14, 58))
	m = applyEngineEvent(t, m, chatUpdatedWire("tele_02", renamed, nowMs))
	if len(m.Dialogs.Rows) != 2 {
		t.Fatalf("rename must re-apply the filter, rows = %d", len(m.Dialogs.Rows))
	}
	if m.Dialogs.Rows[0].ChatID != "88" || m.Dialogs.Rows[1].ChatID != "77" ||
		m.Dialogs.Rows[1].Name != "Bob Smith" {
		t.Fatalf("filtered order wrong after rename: %+v", m.Dialogs.Rows)
	}
	m, _ = Update(m, SearchBackspace{})
	if len(m.Dialogs.Rows) != 2 || m.Dialogs.Rows[0].ChatID != "88" {
		t.Fatalf("clearing the filter must restore the full list: %+v", m.Dialogs.Rows)
	}
}

func TestChatUpdatedSnapshotEquivalence(t *testing.T) {
	nowMs := localMs(2026, time.November, 30, 15, 0)
	alice := snapshotChats(nowMs, "77", "Alice", "old", 1, "", false, 0, 0, false)
	m := applyEngineEvent(t, feedsModel(t, 1440, 900), chatSnapshotWire("tele_02", alice, nowMs))
	moved := fmt.Sprintf(`{"account_id":"tele_02","chat_id":"77","type":1,"title":"Alice",`+
		`"last_msg_text":"renamed msg","last_msg_time":%d,"last_msg_is_outgoing":false,`+
		`"last_msg_status":2,"unread_count":4,"is_muted":true,"is_pinned":false,`+
		`"is_bot":false,"is_forum":false}`, nowMs-10000)
	m = applyEngineEvent(t, m, chatUpdatedWire("tele_02", moved, nowMs))
	inserted := fmt.Sprintf(`{"account_id":"tele_02","chat_id":"55","type":1,"title":"Stranger",`+
		`"last_msg_text":"hello","last_msg_time":%d,"last_msg_is_outgoing":false,`+
		`"last_msg_status":2,"unread_count":1,"is_muted":false,"is_pinned":false,`+
		`"is_bot":false,"is_forum":false}`, localMs(2026, time.November, 30, 13, 0))
	m = applyEngineEvent(t, m, chatUpdatedWire("tele_02", inserted, nowMs))
	if len(m.Dialogs.Rows) != 2 {
		t.Fatalf("update chain must keep two rows: %+v", m.Dialogs.Rows)
	}
	aliceAfter := fmt.Sprintf(`{"account_id":"tele_02","chat_id":"77","type":1,"title":"Alice",`+
		`"last_msg_text":"renamed msg","last_msg_time":%d,"last_msg_is_outgoing":false,`+
		`"last_msg_status":2,"unread_count":4,"is_muted":true,"is_pinned":false,`+
		`"is_bot":false,"is_forum":false}`, nowMs-10000)
	refreshed := applyEngineEvent(t, feedsModel(t, 1440, 900),
		chatSnapshotWire("tele_02", aliceAfter+","+inserted, nowMs))
	for i := range m.Dialogs.Rows {
		live, fresh := m.Dialogs.Rows[i], refreshed.Dialogs.Rows[i]
		if live.Name != fresh.Name || live.Preview != fresh.Preview || live.Date != fresh.Date ||
			live.Unread != fresh.Unread || live.UnreadMuted != fresh.UnreadMuted ||
			live.ChatID != fresh.ChatID || live.Account != fresh.Account {
			t.Fatalf("row %d drifts from the snapshot equivalence: live=%+v fresh=%+v", i, live, fresh)
		}
	}
}

func TestChatUpdatedMapsEventBadges(t *testing.T) {
	nowMs := localMs(2026, time.November, 30, 15, 0)
	group := fmt.Sprintf(snapshotGroupWireTmpl, localMs(2026, time.November, 30, 14, 2))
	m := applyEngineEvent(t, feedsModel(t, 1440, 900), chatSnapshotWire("tele_02", group, nowMs))
	row := m.Dialogs.Rows[0]
	if row.Unread != 5 || !row.UnreadMark || !row.Mention || !row.Reaction {
		t.Fatalf("test setup: badges missing: %+v", row)
	}
	read := fmt.Sprintf(`{"account_id":"tele_02","chat_id":"-400","type":2,"title":"Dev Crew",`+
		`"last_msg_text":"release notes","last_msg_time":%d,"last_msg_sender":"bob",`+
		`"last_msg_is_outgoing":false,"last_msg_status":2,"unread_count":0,`+
		`"unread_mention_count":0,"unread_reaction_count":0,"unread_mark":false,`+
		`"is_muted":true,"is_pinned":true,"is_bot":false,"is_forum":true}`,
		localMs(2026, time.November, 30, 14, 2))
	m = applyEngineEvent(t, m, chatUpdatedWire("tele_02", read, nowMs))
	row = m.Dialogs.Rows[0]
	if row.Unread != 0 || row.UnreadMark || row.Mention || row.Reaction {
		t.Fatalf("the event badge fields must replace the row's: %+v", row)
	}
	if row.Name != "Dev Crew" || row.Preview != "bob: release notes" || !row.Pinned ||
		row.ChatType != dialogs.ChatForum {
		t.Fatalf("non-badge content must survive the read update: %+v", row)
	}
}

func TestFormatDialogsDateLaw(t *testing.T) {
	loc := time.UTC
	cases := []struct {
		name string
		t    time.Time
		now  time.Time
		want string
	}{
		{"same day", time.Date(2026, 11, 30, 14, 2, 0, 0, loc), time.Date(2026, 11, 30, 15, 0, 0, 0, loc), "14:02"},
		{"yesterday within 20h", time.Date(2026, 11, 29, 23, 0, 0, 0, loc), time.Date(2026, 11, 30, 9, 0, 0, 0, loc), "23:00"},
		{"exactly 20h falls through", time.Date(2026, 11, 29, 13, 0, 0, 0, loc), time.Date(2026, 11, 30, 9, 0, 0, 0, loc), "Sun"},
		{"six days weekday", time.Date(2026, 11, 24, 12, 0, 0, 0, loc), time.Date(2026, 11, 30, 12, 0, 0, 0, loc), "Tue"},
		{"seven days numeric", time.Date(2026, 11, 23, 12, 0, 0, 0, loc), time.Date(2026, 11, 30, 12, 0, 0, 0, loc), "11/23/26"},
		{"older numeric", time.Date(2024, 3, 5, 12, 0, 0, 0, loc), time.Date(2026, 11, 30, 12, 0, 0, 0, loc), "3/5/24"},
	}
	for _, tc := range cases {
		if got := FormatDialogsDate(tc.t, tc.now); got != tc.want {
			t.Fatalf("%s: FormatDialogsDate = %q, want %q", tc.name, got, tc.want)
		}
	}
}

func TestDayDividerTextLaw(t *testing.T) {
	loc := time.UTC
	cases := []struct {
		name string
		t    time.Time
		now  time.Time
		want string
	}{
		{"same year", time.Date(2026, 11, 5, 12, 0, 0, 0, loc), time.Date(2026, 11, 30, 12, 0, 0, 0, loc), "November 5"},
		{"two years out", time.Date(2028, 11, 5, 12, 0, 0, 0, loc), time.Date(2026, 11, 30, 12, 0, 0, 0, loc), "November 5, 2028"},
		{"next year near month keeps no year", time.Date(2027, 1, 9, 12, 0, 0, 0, loc), time.Date(2026, 11, 30, 12, 0, 0, 0, loc), "January 9"},
		{"next year far month shows year", time.Date(2027, 3, 12, 12, 0, 0, 0, loc), time.Date(2026, 11, 30, 12, 0, 0, 0, loc), "March 12, 2027"},
		{"past year near month keeps no year", time.Date(2025, 11, 9, 12, 0, 0, 0, loc), time.Date(2026, 1, 30, 12, 0, 0, 0, loc), "November 9"},
		{"past year far month shows year", time.Date(2025, 8, 5, 12, 0, 0, 0, loc), time.Date(2026, 1, 30, 12, 0, 0, 0, loc), "August 5, 2025"},
	}
	for _, tc := range cases {
		if got := DayDividerText(tc.t, tc.now); got != tc.want {
			t.Fatalf("%s: DayDividerText = %q, want %q", tc.name, got, tc.want)
		}
	}
}

func TestFeedPaintSmoke(t *testing.T) {
	p := render.NewPainter()
	cp := chatrender.NewChatPainter()
	gtx := renderContext()
	sch := material.SchemeFor(material.Light)
	nowMs := localMs(2026, time.November, 30, 15, 0)
	chats := snapshotChats(nowMs, "77", "Alice", "hi there", 1, "", false, 0, 3, true) + "," + snapshotChats(nowMs, "88", "Bob", "yo", 2, "bob", false, 2, 0, false)
	m := applyEngineEvent(t, feedsModel(t, 1440, 900), chatSnapshotWire("tele_02", chats, nowMs))
	items := FeedItems([]WireMessage{
		{ID: "m1", SenderID: "u1", SenderName: "Alice", Text: "hello world", TimestampMs: nowMs - 60000, Status: 2},
		{ID: "m2", SenderID: "u1", SenderName: "Alice", Text: "grouped", TimestampMs: nowMs, Status: 2, Out: true},
	}, time.UnixMilli(nowMs), true)
	m, _ = Update(m, ChatLoaded{Items: items})
	scene := View(m)
	p.PaintPane(gtx, scene.Dialogs, sch)
	cp.PaintChatPane(gtx, scene.Chat, sch)
	if cols := m.Columns(); cols.Dialogs < m.Width {
		cp.PaintChatPane(gtx, scene.Chat, sch)
	}
}

func TestDialogsRowHeightCoversPress(t *testing.T) {
	if tokens.DialogsRowHeight <= 10 {
		t.Fatalf("press Y=10 assumes row height > 10, got %d", tokens.DialogsRowHeight)
	}
}

func (p *fakeChatPort) SearchGlobalChats(accountID, query string) ([]dialogs.Entry, bool) {
	return nil, false
}
