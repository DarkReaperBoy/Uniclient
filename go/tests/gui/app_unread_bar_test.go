package tests

import (
	"fmt"
	"strings"
	"testing"
	"time"

	. "uniclient/ui/app"
)

const unreadRowWireTmpl = `{"account_id":"tele_02","chat_id":"77","type":1,"title":"Alice",` +
	`"last_msg_text":"hi","last_msg_time":%d,"unread_count":2,` +
	`"read_inbox_max_id":4,"is_muted":false,"is_pinned":false,"is_bot":false,"is_forum":false}`

func unreadRowWire(nowMs int64, readInbox int) string {
	row := fmt.Sprintf(unreadRowWireTmpl, nowMs-60000)
	if readInbox != 4 {
		row = strings.Replace(row, `"read_inbox_max_id":4`, fmt.Sprintf(`"read_inbox_max_id":%d`, readInbox), 1)
	}
	return row
}

func unreadBarMsgs(nowMs int64) []WireMessage {
	base := nowMs - 240000
	return []WireMessage{
		{ID: "3", SenderID: "u1", SenderName: "Alice", Text: "read one", TimestampMs: base, Status: 2},
		{ID: "4", SenderID: "u1", SenderName: "Alice", Text: "read two", TimestampMs: base + 60000, Status: 2},
		{ID: "5", SenderID: "u1", SenderName: "Alice", Text: "unread one", TimestampMs: base + 120000, Status: 2},
		{ID: "6", SenderID: "u1", SenderName: "Alice", Text: "unread two", TimestampMs: base + 180000, Status: 2},
	}
}

func openUnreadChat(t *testing.T, rowWire string, msgs []WireMessage) Model {
	t.Helper()
	nowMs := localMs(2026, time.November, 30, 15, 0)
	port := &fakeChatPort{ok: true, msgs: msgs}
	m := applyEngineEvent(t, feedsModel(t, 1440, 900).WithPort(port), chatSnapshotWire("tele_02", rowWire, nowMs))
	m, cmd := Update(m, DialogsPressed{X: 20, Y: 10, Now: 1})
	if cmd == nil {
		t.Fatal("row press must produce an open cmd")
	}
	loaded, ok := cmd().(ChatLoaded)
	if !ok {
		t.Fatalf("open cmd produced %T, want ChatLoaded", cmd())
	}
	m, _ = Update(m, loaded)
	return m
}

func chatUpdatedReadWire(nowMs int64, readInbox int) string {
	return fmt.Sprintf(`{"type":"chat_updated","account_id":"tele_02","timestamp_ms":%d,`+
		`"data":{"chat":%s}}`, nowMs, unreadRowWire(nowMs, readInbox))
}

func msgReceivedWire(nowMs int64, id, text string) string {
	return fmt.Sprintf(`{"type":"msg_received","account_id":"tele_02","timestamp_ms":%d,`+
		`"data":{"chat_id":"77","message":{"msg_id":%q,"sender_id":"u1",`+
		`"sender_name":"Alice","content_text":%q,`+
		`"timestamp":%d,"status":2,"is_outgoing":false,"is_service":false}}}`,
		nowMs, id, text, nowMs-1000)
}

func TestUnreadBarRidesFirstUnreadMessage(t *testing.T) {
	nowMs := localMs(2026, time.November, 30, 15, 0)
	m := openUnreadChat(t, unreadRowWire(nowMs, 4), unreadBarMsgs(nowMs))
	items := m.Chat.Items
	if len(items) != 4 {
		t.Fatalf("items = %d, want 4", len(items))
	}
	if items[0].UnreadBar != "" || items[1].UnreadBar != "" {
		t.Fatalf("read messages must carry no bar: %+v %+v", items[0], items[1])
	}
	if items[2].UnreadBar != "Unread messages" {
		t.Fatalf("first unread message must carry the bar, got %q", items[2].UnreadBar)
	}
	if items[3].UnreadBar != "" {
		t.Fatalf("only the first unread carries the bar: %+v", items[3])
	}
	m, _ = Update(m, ChatMeasured{Heights: uniformHeights(4, 50)})
	pane := View(m).Chat
	barAt := -1
	for i, it := range pane.Rows {
		if it.UnreadBar != "" {
			barAt = i
		}
	}
	if barAt != 2 {
		t.Fatalf("pane must project the bar onto the first unread row, barAt = %d", barAt)
	}
}

func TestUnreadBarAbsentWhenFullyRead(t *testing.T) {
	nowMs := localMs(2026, time.November, 30, 15, 0)
	m := openUnreadChat(t, unreadRowWire(nowMs, 6), unreadBarMsgs(nowMs))
	for i, it := range m.Chat.Items {
		if it.UnreadBar != "" {
			t.Fatalf("fully read chat must show no bar, item %d: %q", i, it.UnreadBar)
		}
	}
}

func TestUnreadBarAbsentWhenReadPositionUnknown(t *testing.T) {
	nowMs := localMs(2026, time.November, 30, 15, 0)
	m := openUnreadChat(t, unreadRowWire(nowMs, 0), unreadBarMsgs(nowMs))
	for i, it := range m.Chat.Items {
		if it.UnreadBar != "" {
			t.Fatalf("unknown read position must show no bar, item %d: %q", i, it.UnreadBar)
		}
	}
}

func TestUnreadBarSkipsOutgoingAndNonNumericIds(t *testing.T) {
	nowMs := localMs(2026, time.November, 30, 15, 0)
	base := nowMs - 240000
	msgs := []WireMessage{
		{ID: "3", SenderID: "u1", SenderName: "Alice", Text: "read one", TimestampMs: base, Status: 2},
		{ID: "7", SenderID: "u1", SenderName: "Alice", Text: "outgoing unread", TimestampMs: base + 60000, Status: 2, Out: true},
		{ID: "odd", SenderID: "u1", SenderName: "Alice", Text: "non numeric", TimestampMs: base + 120000, Status: 2},
		{ID: "9", SenderID: "u1", SenderName: "Alice", Text: "incoming unread", TimestampMs: base + 180000, Status: 2},
	}
	m := openUnreadChat(t, unreadRowWire(nowMs, 4), msgs)
	for i, it := range m.Chat.Items {
		if i == 3 {
			if it.UnreadBar != "Unread messages" {
				t.Fatalf("the first incoming numeric unread must carry the bar, item %d: %q", i, it.UnreadBar)
			}
			continue
		}
		if it.UnreadBar != "" {
			t.Fatalf("outgoing/non-numeric messages must carry no bar, item %d: %q", i, it.UnreadBar)
		}
	}
}

func TestReadAdvanceReplacesBar(t *testing.T) {
	nowMs := localMs(2026, time.November, 30, 15, 0)
	m := openUnreadChat(t, unreadRowWire(nowMs, 4), unreadBarMsgs(nowMs))
	m, _ = Update(m, ChatMeasured{Heights: uniformHeights(4, 50)})
	if m.Chat.Items[2].UnreadBar != "Unread messages" {
		t.Fatalf("pre-advance bar missing: %q", m.Chat.Items[2].UnreadBar)
	}
	m = applyEngineEvent(t, m, chatUpdatedReadWire(nowMs, 6))
	for i, it := range m.Chat.Items {
		if it.UnreadBar != "" {
			t.Fatalf("an advanced read position must drop the bar, item %d: %q", i, it.UnreadBar)
		}
	}
	if !m.ChatDirty || m.Chat.Heights != nil {
		t.Fatalf("the read advance must re-measure: dirty=%v heights=%v", m.ChatDirty, m.Chat.Heights)
	}
}

func TestReadAdvanceMovesBarDown(t *testing.T) {
	nowMs := localMs(2026, time.November, 30, 15, 0)
	m := openUnreadChat(t, unreadRowWire(nowMs, 4), unreadBarMsgs(nowMs))
	m = applyEngineEvent(t, m, chatUpdatedReadWire(nowMs, 5))
	if m.Chat.Items[2].UnreadBar != "" {
		t.Fatalf("message 5 is read now, bar must move: %q", m.Chat.Items[2].UnreadBar)
	}
	if m.Chat.Items[3].UnreadBar != "Unread messages" {
		t.Fatalf("message 6 is the first unread after the advance, got %q", m.Chat.Items[3].UnreadBar)
	}
}

func TestMsgReceivedKeepsBarOnFirstUnread(t *testing.T) {
	nowMs := localMs(2026, time.November, 30, 15, 0)
	m := openUnreadChat(t, unreadRowWire(nowMs, 4), unreadBarMsgs(nowMs))
	m, _ = Update(m, ChatMeasured{Heights: uniformHeights(4, 50)})
	m = applyEngineEvent(t, m, msgReceivedWire(nowMs, "7", "fresh below"))
	if len(m.Chat.Items) != 5 {
		t.Fatalf("items = %d, want 5", len(m.Chat.Items))
	}
	if m.Chat.Items[2].UnreadBar != "Unread messages" {
		t.Fatalf("a new message below must not steal the bar: %q", m.Chat.Items[2].UnreadBar)
	}
	if m.Chat.Items[4].UnreadBar != "" {
		t.Fatalf("the new message must not carry the bar: %q", m.Chat.Items[4].UnreadBar)
	}
}

func TestChatSwitchResetsReadPosition(t *testing.T) {
	nowMs := localMs(2026, time.November, 30, 15, 0)
	m := openUnreadChat(t, unreadRowWire(nowMs, 4), unreadBarMsgs(nowMs))
	m, _ = Update(m, ChatLoaded{Msgs: []WireMessage{
		{ID: "11", SenderID: "u1", SenderName: "Alice", Text: "other chat", TimestampMs: nowMs, Status: 2},
	}, Items: FeedItems([]WireMessage{
		{ID: "11", SenderID: "u1", SenderName: "Alice", Text: "other chat", TimestampMs: nowMs, Status: 2},
	}, 0, time.UnixMilli(nowMs), false), Now: int(nowMs)})
	if m.Chat.Items[0].UnreadBar != "" {
		t.Fatalf("a chat without a read position must show no bar: %q", m.Chat.Items[0].UnreadBar)
	}
}
