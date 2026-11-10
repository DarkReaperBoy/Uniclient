package tests

import (
	"encoding/json"
	"strings"
	"testing"
	"time"

	"uniclient/cores"
	. "uniclient/engine"
	"uniclient/ui/app"
	"uniclient/ui/appport"
)

type snapshotEnvelope struct {
	Type        string          `json:"type"`
	AccountID   string          `json:"account_id"`
	TimestampMs int64           `json:"timestamp_ms"`
	Data        json.RawMessage `json:"data"`
}

func findEvent(t *testing.T, e *dbEngine, eventType string, trigger func()) []byte {
	t.Helper()
	var captured []byte
	sub := e.Subscribe(func(data []byte) {
		if captured != nil {
			return
		}
		var env snapshotEnvelope
		if json.Unmarshal(data, &env) == nil && env.Type == eventType {
			captured = data
		}
	})
	defer sub.Unsubscribe()
	trigger()
	if captured == nil {
		t.Fatalf("no %s event captured", eventType)
	}
	return captured
}

func wireDialog(msgID, text string, msgTs int64) cores.Dialog {
	return cores.Dialog{
		ID:    "c1",
		Type:  cores.ChatTypeGroup,
		Title: "Dev Crew",
		LastMessage: &cores.Message{
			ID:         msgID,
			ChatID:     "c1",
			SenderID:   "u1",
			SenderName: "bob",
			Text:       text,
			Timestamp:  time.UnixMilli(msgTs),
			Status:     cores.MessageStatusSent,
		},
		UnreadCount:         5,
		IsMuted:             true,
		IsPinned:            true,
		UnreadMark:          true,
		UnreadMentionCount:  1,
		UnreadReactionCount: 1,
		IsForum:             true,
	}
}

func TestChatSnapshotWireFeedsDialogRows(t *testing.T) {
	e := newTestEngine(t)
	msgTs := time.Date(2026, time.November, 30, 14, 2, 0, 0, time.Local).UnixMilli()
	raw := findEvent(t, e, EventChatSnapshot, func() {
		if err := e.SyncChats("a1", []cores.Dialog{wireDialog("m1", "release notes", msgTs)}); err != nil {
			t.Fatal(err)
		}
	})
	var env snapshotEnvelope
	if err := json.Unmarshal(raw, &env); err != nil {
		t.Fatalf("snapshot envelope: %v", err)
	}
	if env.AccountID != "a1" {
		t.Fatalf("envelope account = %q, want a1", env.AccountID)
	}
	m := app.InitialModel()
	m.Accounts = []app.Account{{ID: "a1", SortOrder: 0}}
	next, _ := app.Update(m, app.EngineEventMsg{Data: raw})
	if len(next.Dialogs.Rows) != 1 {
		t.Fatalf("rows = %d, want 1", len(next.Dialogs.Rows))
	}
	row := next.Dialogs.Rows[0]
	if row.Account != "a1" || row.ChatID != "c1" || row.Name != "Dev Crew" || row.Group != true {
		t.Fatalf("row identity/mapping wrong: %+v", row)
	}
	if row.Preview != "bob: release notes" || row.Unread != 5 || row.Pinned != true || row.Mention != true {
		t.Fatalf("row content wrong: %+v", row)
	}
	if want := app.FormatDialogsDate(time.UnixMilli(msgTs), time.UnixMilli(env.TimestampMs)); row.Date != want {
		t.Fatalf("row date = %q, want %q (computed against the captured envelope ts)", row.Date, want)
	}
}

func TestGetMessagesPortFeedsItems(t *testing.T) {
	e := newTestEngine(t)
	seedMessage(t, e, "m1", 1000)
	seedMessage(t, e, "m2", 2000)
	seedMessage(t, e, "m3", 3000)
	port := appport.For(e.Engine)
	msgs, ok := port.Messages("a1", "c1", 50)
	if !ok {
		t.Fatal("port.Messages must succeed on the seeded chat")
	}
	if len(msgs) != 3 {
		t.Fatalf("port returned %d messages, want 3", len(msgs))
	}
	if msgs[0].ID != "m1" || msgs[0].Text != "m1" || msgs[0].TimestampMs != 1000 {
		t.Fatalf("port message mapping wrong: %+v", msgs[0])
	}
	if msgs[0].SenderID != "" || msgs[0].SenderName != "" || msgs[0].Out || msgs[0].Service {
		t.Fatalf("seeded message flags wrong: %+v", msgs[0])
	}
	if msgs[0].Status != 2 {
		t.Fatalf("seeded status = %d, want 2 (column default)", msgs[0].Status)
	}
	items := app.FeedItems(msgs, time.UnixMilli(4000), false)
	if len(items) != 3 || items[0].Text != "m1" || !items[0].AttachedBottom || !items[1].AttachedTop {
		t.Fatalf("items projection wrong: %+v", items)
	}
}

func TestMsgReceivedWireAppendsToOpenChat(t *testing.T) {
	e := newTestEngine(t)
	msgTs := time.Now().Add(-time.Minute).UnixMilli()
	raw := findEvent(t, e, EventMsgReceived, func() {
		e.HandleUpdate("a1", cores.Update{
			Type:   cores.UpdateNewMessage,
			ChatID: "c1",
			Message: &cores.Message{
				ID:         "live1",
				ChatID:     "c1",
				SenderID:   "u1",
				SenderName: "alice",
				Text:       "live wire",
				Timestamp:  time.UnixMilli(msgTs),
				Status:     cores.MessageStatusSent,
			},
		})
	})
	var env snapshotEnvelope
	if err := json.Unmarshal(raw, &env); err != nil {
		t.Fatalf("msg_received envelope: %v", err)
	}
	if env.AccountID != "a1" || !strings.Contains(string(env.Data), `"chat_id":"c1"`) {
		t.Fatalf("msg_received envelope wrong: %s", raw)
	}
	m := app.InitialModel()
	m.Open = app.ChatRef{Account: "a1", ID: "c1"}
	m.OpenValid = true
	next, _ := app.Update(m, app.EngineEventMsg{Data: raw})
	if len(next.Chat.Items) != 1 {
		t.Fatalf("live wire message must land in the open chat, items = %d", len(next.Chat.Items))
	}
	item := next.Chat.Items[0]
	if item.Text != "live wire" || item.Out {
		t.Fatalf("live item wrong: %+v", item)
	}
}

func TestGetMessagesPortEmptyChat(t *testing.T) {
	e := newTestEngine(t)
	port := appport.For(e.Engine)
	msgs, ok := port.Messages("a1", "never-seen", 50)
	if !ok || len(msgs) != 0 {
		t.Fatalf("empty chat must be ok with zero messages: ok=%v msgs=%d", ok, len(msgs))
	}
}
