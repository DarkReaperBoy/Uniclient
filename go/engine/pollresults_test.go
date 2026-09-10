package engine

import (
	"encoding/json"
	"testing"
)

// seedPollMessage caches a poll message (raw cores.Message JSON w/ Extra
// poll_* fields, as the telegram core's MessageMediaPoll conversion writes).
func seedPollMessage(t *testing.T, e *Engine, msgID string) {
	t.Helper()
	raw, err := json.Marshal(map[string]interface{}{
		"id":   msgID,
		"text": "📊 Lunch?",
		"extra": map[string]interface{}{
			"poll_question":     "Lunch?",
			"poll_total_voters": 2,
			"poll_options": []interface{}{
				map[string]interface{}{"text": "Pizza", "option": "AAAAAA==", "voters": 2, "chosen": true},
				map[string]interface{}{"text": "Sushi", "option": "AAAAAQ==", "voters": 0},
			},
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	_, err = e.db.Exec(
		`INSERT INTO messages (account_id, chat_id, msg_id, content_text, content_raw, timestamp)
		 VALUES ('a1', 'c1', ?, ?, ?, 1000)`, msgID, "📊 Lunch?", string(raw))
	if err != nil {
		t.Fatal(err)
	}
}

func readPollExtra(t *testing.T, e *Engine, msgID string) map[string]interface{} {
	t.Helper()
	var raw []byte
	err := e.db.QueryRow(
		`SELECT content_raw FROM messages WHERE account_id='a1' AND chat_id='c1' AND msg_id=?`,
		msgID).Scan(&raw)
	if err != nil {
		t.Fatal(err)
	}
	var doc struct {
		Extra map[string]interface{} `json:"extra"`
	}
	if err := json.Unmarshal(raw, &doc); err != nil {
		t.Fatal(err)
	}
	return doc.Extra
}

func TestMergePollResults(t *testing.T) {
	e := newTestEngine(t)
	seedPollMessage(t, e, "55")

	// Fresh counts: sushi won, pizza chosen flag dropped, quiz correct set,
	// total voters bumped, poll closed.
	e.mergePollResults("a1", "c1", "55", map[string]interface{}{
		"poll_total_voters": 7,
		"poll_closed":       true,
		"poll_results_merge": []interface{}{
			map[string]interface{}{"option": "AAAAAA==", "voters": 3, "chosen": false, "correct": false},
			map[string]interface{}{"option": "AAAAAQ==", "voters": 4, "chosen": false, "correct": true},
		},
	})

	extra := readPollExtra(t, e, "55")
	if tv, ok := extra["poll_total_voters"].(float64); !ok || int(tv) != 7 {
		t.Errorf("total voters = %v", extra["poll_total_voters"])
	}
	if closed, _ := extra["poll_closed"].(bool); !closed {
		t.Errorf("poll_closed not set")
	}
	opts, _ := extra["poll_options"].([]interface{})
	if len(opts) != 2 {
		t.Fatalf("options = %d", len(opts))
	}
	pizza, _ := opts[0].(map[string]interface{})
	if pizza["text"] != "Pizza" || int(pizza["voters"].(float64)) != 3 || pizza["chosen"] == true {
		t.Errorf("pizza = %v", pizza)
	}
	sushi, _ := opts[1].(map[string]interface{})
	if int(sushi["voters"].(float64)) != 4 || sushi["correct"] != true {
		t.Errorf("sushi = %v", sushi)
	}
	// Untouched fields survive.
	if q, _ := extra["poll_question"].(string); q != "Lunch?" {
		t.Errorf("question = %q", q)
	}
}

func TestMergePollResultsResolvesChatFromCache(t *testing.T) {
	e := newTestEngine(t)
	seedPollMessage(t, e, "56")

	// Empty chatID (older layer): the merge resolves the chat by message id.
	e.mergePollResults("a1", "", "56", map[string]interface{}{
		"poll_total_voters": 9,
	})
	extra := readPollExtra(t, e, "56")
	if tv, ok := extra["poll_total_voters"].(float64); !ok || int(tv) != 9 {
		t.Errorf("total voters after chat resolve = %v", extra["poll_total_voters"])
	}
}

func TestMergePollResultsUnknownMessageNoop(t *testing.T) {
	e := newTestEngine(t)
	seedPollMessage(t, e, "57")
	e.mergePollResults("a1", "c1", "404", map[string]interface{}{
		"poll_total_voters": 99,
	})
	extra := readPollExtra(t, e, "57")
	if tv, ok := extra["poll_total_voters"].(float64); !ok || int(tv) != 2 {
		t.Errorf("unrelated message must be untouched, got %v", extra["poll_total_voters"])
	}
	// Non-poll messages never match (chat resolve requires poll_question).
	seedMessage(t, e, "58", 2000)
	e.mergePollResults("a1", "", "58", map[string]interface{}{"poll_total_voters": 99})
}
