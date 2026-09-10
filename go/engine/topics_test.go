package engine

import (
	"testing"
)

// Forum topic scoping (slice 118): messages cached with topic_id must filter
// cleanly, hidden/shadow-banned rows stay excluded, and the empty topic id
// falls back to the plain chat page.

func seedTopicMessage(t *testing.T, e *Engine, msgID, topicID string, ts int64) {
	t.Helper()
	_, err := e.db.Exec(
		`INSERT OR REPLACE INTO messages
		 (account_id, chat_id, msg_id, sender_id, sender_name, content_text, timestamp, status, is_outgoing, has_media, topic_id)
		 VALUES (?, ?, ?, 'u1', 'Alice', ?, ?, 1, 0, 0, ?)`,
		"tg", "10", msgID, "m-"+msgID, ts, topicID)
	if err != nil {
		t.Fatal(err)
	}
}

func TestGetTopicMessagesFiltersByTopic(t *testing.T) {
	e := newTestEngine(t)
	seedTopicMessage(t, e, "1", "100", 1700000100)
	seedTopicMessage(t, e, "2", "100", 1700000200)
	seedTopicMessage(t, e, "3", "200", 1700000300)
	seedTopicMessage(t, e, "4", "", 1700000400) // no topic (root-ish)

	msgs, err := e.GetTopicMessages("tg", "10", "100", 0, 50)
	if err != nil {
		t.Fatal(err)
	}
	if len(msgs) != 2 {
		t.Fatalf("topic 100 rows = %d, want 2", len(msgs))
	}
	if msgs[0].MsgID != "2" || msgs[1].MsgID != "1" {
		t.Errorf("order = [%s %s], want newest first [2 1]", msgs[0].MsgID, msgs[1].MsgID)
	}

	msgs, err = e.GetTopicMessages("tg", "10", "200", 0, 50)
	if err != nil {
		t.Fatal(err)
	}
	if len(msgs) != 1 || msgs[0].MsgID != "3" {
		t.Fatalf("topic 200 rows = %+v", msgs)
	}

	// beforeMs paging: only older rows return.
	msgs, err = e.GetTopicMessages("tg", "10", "100", 1700000150, 50)
	if err != nil {
		t.Fatal(err)
	}
	if len(msgs) != 1 || msgs[0].MsgID != "1" {
		t.Fatalf("paged rows = %+v", msgs)
	}

	// Empty topic id = the whole chat page.
	msgs, err = e.GetTopicMessages("tg", "10", "", 0, 50)
	if err != nil {
		t.Fatal(err)
	}
	if len(msgs) != 4 {
		t.Fatalf("unscoped rows = %d, want 4", len(msgs))
	}
}

func TestGetTopicMessagesHiddenExcluded(t *testing.T) {
	e := newTestEngine(t)
	seedTopicMessage(t, e, "1", "100", 1700000100)
	seedTopicMessage(t, e, "2", "100", 1700000200)
	if err := e.HideMessage("tg", "10", "2", true); err != nil {
		t.Fatal(err)
	}
	msgs, err := e.GetTopicMessages("tg", "10", "100", 0, 50)
	if err != nil {
		t.Fatal(err)
	}
	if len(msgs) != 1 || msgs[0].MsgID != "1" {
		t.Fatalf("rows after hide = %+v", msgs)
	}
}
