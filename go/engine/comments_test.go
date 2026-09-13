package engine

import (
	"testing"
	"time"

	"uniclient/cores"
)

// Channel-post comments (slice 195): cache round-trip (comments_count +
// thread_root columns), the thread filter, and the discussion-thread
// fetch path with a fake core.

func seedCommentPost(t *testing.T, e *Engine, chatType int, msgID string, comments int) {
	t.Helper()
	_, err := e.db.Exec(
		`INSERT INTO chats (account_id, chat_id, type, title, updated_at) VALUES ('a1', 'c1', ?, 'chan', ?)`,
		chatType, time.Now().UnixMilli())
	if err != nil {
		t.Fatal(err)
	}
	m := &cores.Message{ID: msgID, ChatID: "c1", Text: "post", CommentsCount: comments}
	e.cacheMessage("a1", "c1", m)
}

func TestCommentsCountRoundTrip(t *testing.T) {
	e := newTestEngine(t)
	seedCommentPost(t, e, ChatTypeChanVal, "m1", 12)

	msgs, err := e.GetMessages("a1", "c1", 0, 0, 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(msgs) != 1 || msgs[0].CommentsCount != 12 {
		t.Fatalf("round trip = %+v", msgs[0])
	}
}

func TestThreadRootRoundTripAndFilter(t *testing.T) {
	e := newTestEngine(t)
	// Discussion chat d1; thread rooted at r1 with two comments + the root.
	_, err := e.db.Exec(
		`INSERT INTO chats (account_id, chat_id, type, title, updated_at) VALUES ('a1', 'd1', ?, 'disc', ?)`,
		ChatTypeGroupVal, time.Now().UnixMilli())
	if err != nil {
		t.Fatal(err)
	}
	root := &cores.Message{ID: "r1", ChatID: "d1", Text: "forwarded post", ThreadRoot: "r1"}
	c1 := &cores.Message{ID: "k1", ChatID: "d1", Text: "first comment", ThreadRoot: "r1", Timestamp: time.Now().Add(time.Minute)}
	c2 := &cores.Message{ID: "k2", ChatID: "d1", Text: "second comment", ThreadRoot: "r1", Timestamp: time.Now().Add(2 * time.Minute)}
	other := &cores.Message{ID: "x1", ChatID: "d1", Text: "unrelated group message"}
	e.cacheMessage("a1", "d1", root)
	e.cacheMessage("a1", "d1", c1)
	e.cacheMessage("a1", "d1", c2)
	e.cacheMessage("a1", "d1", other)

	msgs, err := e.GetThreadMessages("a1", "d1", "r1", 0, 50)
	if err != nil {
		t.Fatal(err)
	}
	// Newest-first contract (same as GetMessages): k2, k1, r1 — and NOT x1.
	if len(msgs) != 3 {
		t.Fatalf("thread rows = %d, want 3 (root + 2 comments, no unrelated)", len(msgs))
	}
	if msgs[0].MsgID != "k2" || msgs[1].MsgID != "k1" || msgs[2].MsgID != "r1" {
		t.Fatalf("thread order = %v %v %v", msgs[0].MsgID, msgs[1].MsgID, msgs[2].MsgID)
	}
}

type fakeDiscussionCore struct {
	cores.StubCore
	msgs []cores.Message
	err  error
}

func (f *fakeDiscussionCore) GetDiscussionThread(chatID, msgID string) ([]cores.Message, error) {
	if f.err != nil {
		return nil, f.err
	}
	return f.msgs, nil
}

func TestGetDiscussionThreadCaches(t *testing.T) {
	e := newTestEngine(t)
	fc := &fakeDiscussionCore{msgs: []cores.Message{
		{ID: "r1", ChatID: "d1", Text: "root", ThreadRoot: "r1"},
		{ID: "k1", ChatID: "d1", Text: "comment", ThreadRoot: "r1"},
	}}
	e.accounts = map[string]*Account{"a1": {ID: "a1", Core: fc}}

	rows, err := e.GetDiscussionThread("a1", "c1", "m1")
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) != 2 {
		t.Fatalf("rows = %d, want 2", len(rows))
	}
	// Cached: a second read straight from the DB filter.
	msgs, err := e.GetThreadMessages("a1", "d1", "r1", 0, 50)
	if err != nil {
		t.Fatal(err)
	}
	if len(msgs) != 2 {
		t.Fatalf("cached thread rows = %d, want 2", len(msgs))
	}
	// Missing account → honest error.
	if _, err := e.GetDiscussionThread("nope", "c1", "m1"); err == nil {
		t.Error("missing account must error")
	}
	// Unsupported core → honest error.
	e.accounts = map[string]*Account{"a1": {ID: "a1", Core: &cores.StubCore{}}}
	if _, err := e.GetDiscussionThread("a1", "c1", "m1"); err == nil {
		t.Error("unsupported core must error")
	}
}
