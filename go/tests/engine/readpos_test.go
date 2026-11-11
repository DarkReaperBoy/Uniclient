package tests

import (
	"encoding/json"
	"fmt"
	"strings"
	"testing"
	"time"

	"uniclient/cores"
	. "uniclient/engine"
	"uniclient/ui/app"
	"uniclient/ui/appport"
)

func readPosDialog(chatID string, readInbox int, msgTs int64) cores.Dialog {
	return cores.Dialog{
		ID:             chatID,
		Type:           cores.ChatTypeGroup,
		Title:          "Dev Crew",
		LastMessage:    &cores.Message{ID: "m9", ChatID: chatID, SenderID: "u1", SenderName: "bob", Text: "release notes", Timestamp: time.UnixMilli(msgTs), Status: cores.MessageStatusSent},
		UnreadCount:    2,
		ReadInboxMaxID: readInbox,
	}
}

type readPosPayload struct {
	Chat struct {
		ChatID         string `json:"chat_id"`
		UnreadCount    int    `json:"unread_count"`
		ReadInboxMaxID int    `json:"read_inbox_max_id"`
	} `json:"chat"`
}

func TestDialogReadPositionFlowsThroughSnapshotAndLists(t *testing.T) {
	e := newTestEngine(t)
	msgTs := time.Date(2026, time.November, 30, 14, 2, 0, 0, time.Local).UnixMilli()
	raw := findEvent(t, e, EventChatSnapshot, func() {
		if err := e.SyncChats("a1", []cores.Dialog{readPosDialog("c1", 40, msgTs)}); err != nil {
			t.Fatal(err)
		}
	})
	if !strings.Contains(string(raw), `"read_inbox_max_id":40`) {
		t.Fatalf("chat_snapshot must carry read_inbox_max_id: %s", raw)
	}
	unified, err := e.GetUnifiedChatList(50, 0)
	if err != nil || len(unified) != 1 {
		t.Fatalf("unified = (%d, %v), want the single chat", len(unified), err)
	}
	if unified[0].ReadInboxMaxID != 40 {
		t.Fatalf("unified read position = %d, want 40", unified[0].ReadInboxMaxID)
	}
	perAccount, err := e.GetChatList("a1", false, 50, 0)
	if err != nil || len(perAccount) != 1 || perAccount[0].ReadInboxMaxID != 40 {
		t.Fatalf("per-account list read position wrong: %+v %v", perAccount, err)
	}
	found, err := e.SearchChats("Dev", 20)
	if err != nil || len(found) != 1 || found[0].ReadInboxMaxID != 40 {
		t.Fatalf("search list read position wrong: %+v %v", found, err)
	}
}

func TestReadStateAdvancesReadPositionMonotonically(t *testing.T) {
	e := newTestEngine(t)
	msgTs := time.Date(2026, time.November, 30, 14, 2, 0, 0, time.Local).UnixMilli()
	if err := e.SyncChats("a1", []cores.Dialog{readPosDialog("c1", 40, msgTs)}); err != nil {
		t.Fatal(err)
	}
	raw := findEvent(t, e, EventChatUpdated, func() {
		e.HandleUpdate("a1", cores.Update{
			Type:      cores.UpdateReadState,
			ChatID:    "c1",
			ReadState: &cores.ReadState{MyLastRead: "55"},
		})
	})
	var env snapshotEnvelope
	if err := json.Unmarshal(raw, &env); err != nil {
		t.Fatalf("chat_updated envelope: %v", err)
	}
	var d readPosPayload
	if err := json.Unmarshal(env.Data, &d); err != nil {
		t.Fatalf("chat_updated payload: %v", err)
	}
	if d.Chat.ReadInboxMaxID != 55 {
		t.Fatalf("chat_updated read position = %d, want 55", d.Chat.ReadInboxMaxID)
	}
	if d.Chat.UnreadCount != 0 {
		t.Fatalf("read-state update must clear the counter, got %d", d.Chat.UnreadCount)
	}
	if err := e.SyncChats("a1", []cores.Dialog{readPosDialog("c1", 30, msgTs)}); err != nil {
		t.Fatal(err)
	}
	chats, err := e.GetChatList("a1", false, 50, 0)
	if err != nil || len(chats) != 1 || chats[0].ReadInboxMaxID != 55 {
		t.Fatalf("a stale dialog list must never regress the read position: %+v %v", chats, err)
	}
	e.HandleUpdate("a1", cores.Update{
		Type:      cores.UpdateReadState,
		ChatID:    "c1",
		ReadState: &cores.ReadState{MyLastRead: "12"},
	})
	chats, err = e.GetChatList("a1", false, 50, 0)
	if err != nil || len(chats) != 1 || chats[0].ReadInboxMaxID != 55 {
		t.Fatalf("read positions must never regress: %+v %v", chats, err)
	}
}

func TestReadStateNonNumericKeepsPositionLaw(t *testing.T) {
	e := newTestEngine(t)
	msgTs := time.Date(2026, time.November, 30, 14, 2, 0, 0, time.Local).UnixMilli()
	if err := e.SyncChats("a1", []cores.Dialog{readPosDialog("c1", 40, msgTs)}); err != nil {
		t.Fatal(err)
	}
	raw := findEvent(t, e, EventChatUpdated, func() {
		e.HandleUpdate("a1", cores.Update{
			Type:      cores.UpdateReadState,
			ChatID:    "c1",
			ReadState: &cores.ReadState{MyLastRead: "m1"},
		})
	})
	var env snapshotEnvelope
	if err := json.Unmarshal(raw, &env); err != nil {
		t.Fatalf("chat_updated envelope: %v", err)
	}
	var d readPosPayload
	if err := json.Unmarshal(env.Data, &d); err != nil {
		t.Fatalf("chat_updated payload: %v", err)
	}
	if d.Chat.UnreadCount != 0 {
		t.Fatalf("a non-numeric read marker must still clear the counter, got %d", d.Chat.UnreadCount)
	}
	if d.Chat.ReadInboxMaxID != 40 {
		t.Fatalf("a non-numeric read marker must leave the position law untouched, got %d", d.Chat.ReadInboxMaxID)
	}
}

func TestUnreadBarWirePositionsFirstUnreadMessage(t *testing.T) {
	e := newTestEngine(t)
	seedMessage(t, e, "3", 1000)
	seedMessage(t, e, "4", 2000)
	seedMessage(t, e, "5", 3000)
	seedMessage(t, e, "6", 4000)
	msgTs := time.Date(2026, time.November, 30, 14, 2, 0, 0, time.Local).UnixMilli()
	if err := e.SyncChats("a1", []cores.Dialog{readPosDialog("c1", 4, msgTs)}); err != nil {
		t.Fatal(err)
	}
	port := appport.For(e.Engine)
	msgs, ok := port.Messages("a1", "c1", 50)
	if !ok || len(msgs) != 4 {
		t.Fatalf("port messages = (%d, %v), want 4", len(msgs), ok)
	}
	items := app.FeedItems(msgs, 4, time.UnixMilli(9000), false)
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
	fully := app.FeedItems(msgs, 6, time.UnixMilli(9000), false)
	for i, it := range fully {
		if it.UnreadBar != "" {
			t.Fatalf("fully read chat must show no bar, item %d: %q", i, it.UnreadBar)
		}
	}
	unknown := app.FeedItems(msgs, 0, time.UnixMilli(9000), false)
	for i, it := range unknown {
		if it.UnreadBar != "" {
			t.Fatalf("unknown read position must show no bar, item %d: %q", i, it.UnreadBar)
		}
	}
}

func TestUnreadBarWireSkipsOutgoingAndNonNumericIds(t *testing.T) {
	e := newTestEngine(t)
	seedMessage(t, e, "3", 1000)
	seedMessage(t, e, "7", 2000)
	seedMessage(t, e, "odd", 3000)
	seedMessage(t, e, "9", 4000)
	port := appport.For(e.Engine)
	msgs, ok := port.Messages("a1", "c1", 50)
	if !ok || len(msgs) != 4 {
		t.Fatalf("port messages = (%d, %v), want 4", len(msgs), ok)
	}
	msgs[1].Out = true
	items := app.FeedItems(msgs, 4, time.UnixMilli(9000), false)
	for i, it := range items {
		if i == 3 {
			if it.UnreadBar != "Unread messages" {
				t.Fatalf("the first incoming numeric unread message must carry the bar, item %d: %q", i, it.UnreadBar)
			}
			continue
		}
		if it.UnreadBar != "" {
			t.Fatalf("outgoing/non-numeric messages must carry no bar, item %d: %q", i, it.UnreadBar)
		}
	}
}

func TestOpenChatReadPositionRidesTheWire(t *testing.T) {
	e := newTestEngine(t)
	seedMessage(t, e, "5", 3000)
	seedMessage(t, e, "6", 4000)
	msgTs := time.Date(2026, time.November, 30, 14, 2, 0, 0, time.Local).UnixMilli()
	snapshotRaw := findEvent(t, e, EventChatSnapshot, func() {
		if err := e.SyncChats("a1", []cores.Dialog{readPosDialog("c1", 4, msgTs)}); err != nil {
			t.Fatal(err)
		}
	})
	advancedRaw := findEvent(t, e, EventChatUpdated, func() {
		e.HandleUpdate("a1", cores.Update{
			Type:      cores.UpdateReadState,
			ChatID:    "c1",
			ReadState: &cores.ReadState{MyLastRead: "6"},
		})
	})
	m := app.InitialModel()
	m.Accounts = []app.Account{{ID: "a1", SortOrder: 0}}
	next, _ := app.Update(m, app.EngineEventMsg{Data: snapshotRaw})
	if len(next.Dialogs.Rows) != 1 {
		t.Fatalf("snapshot rows = %d, want 1", len(next.Dialogs.Rows))
	}
	if next.Dialogs.Rows[0].ReadInbox != 4 {
		t.Fatalf("row read position = %d, want 4", next.Dialogs.Rows[0].ReadInbox)
	}
	next, _ = app.Update(next, app.EngineEventMsg{Data: advancedRaw})
	if next.Dialogs.Rows[0].ReadInbox != 6 {
		t.Fatalf("advanced row read position = %d, want 6", next.Dialogs.Rows[0].ReadInbox)
	}
	var advancedEnv snapshotEnvelope
	if err := json.Unmarshal(advancedRaw, &advancedEnv); err != nil {
		t.Fatalf("envelope: %v", err)
	}
	if !strings.Contains(string(advancedEnv.Data), fmt.Sprintf(`"chat_id":"c1"`)) {
		t.Fatalf("advanced payload must target the chat: %s", advancedEnv.Data)
	}
}
