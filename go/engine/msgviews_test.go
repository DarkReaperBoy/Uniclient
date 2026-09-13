package engine

// Channel-post views (slice 187): the cache round-trip (ingest → read)
// and the refresh pass (channel gate, batch RPC, cache update,
// non-channel / provider-less no-ops).

import (
	"testing"
	"time"

	"uniclient/cores"
)

type fakeViewsCore struct {
	cores.StubCore
	views    map[string]int
	forwards map[string]int
	calls    int
	err      error
}

func (f *fakeViewsCore) GetMessagesViewsBatch(chatID string, msgIDs []string) (views, forwards map[string]int, err error) {
	f.calls++
	return f.views, f.forwards, f.err
}

func seedChannelChat(t *testing.T, e *Engine, chatID string, chatType int) {
	t.Helper()
	_, err := e.db.Exec(
		`INSERT INTO chats (account_id, chat_id, type, title, updated_at) VALUES ('a1', ?, ?, 'chan', ?)`,
		chatID, chatType, time.Now().UnixMilli())
	if err != nil {
		t.Fatal(err)
	}
}

func TestCacheMessageViewsRoundTrip(t *testing.T) {
	e := newTestEngine(t)
	seedChannelChat(t, e, "c1", ChatTypeChanVal)

	msg := &cores.Message{
		ID:       "m1",
		ChatID:   "c1",
		Text:     "post",
		Views:    1234,
		Forwards: 7,
	}
	e.cacheMessage("a1", "c1", msg)

	msgs, err := e.GetMessages("a1", "c1", 0, 0, 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(msgs) != 1 || msgs[0].Views != 1234 || msgs[0].Forwards != 7 {
		t.Fatalf("round trip = %+v", msgs[0])
	}
}

func TestRefreshMessageViews(t *testing.T) {
	e := newTestEngine(t)
	seedChannelChat(t, e, "c1", ChatTypeChanVal)

	// Seed cached posts (no views yet).
	for i, id := range []string{"m1", "m2", "m3"} {
		m := &cores.Message{ID: id, ChatID: "c1", Text: "post " + id, Timestamp: time.Now().Add(-time.Duration(i) * time.Second)}
		e.cacheMessage("a1", "c1", m)
	}

	fc := &fakeViewsCore{
		views:    map[string]int{"m1": 100, "m2": 500, "m3": 0},
		forwards: map[string]int{"m1": 2, "m2": 0, "m3": 0},
	}
	e.accounts = map[string]*Account{"a1": {ID: "a1", Core: fc}}

	changed, err := e.RefreshMessageViews("a1", "c1")
	if err != nil {
		t.Fatal(err)
	}
	// m1 + m2 changed (m3: 0→0 stays).
	if changed != 2 {
		t.Fatalf("changed = %d, want 2", changed)
	}
	msgs, _ := e.GetMessages("a1", "c1", 0, 0, 10)
	byID := map[string]CachedMessage{}
	for _, m := range msgs {
		byID[m.MsgID] = m
	}
	if byID["m1"].Views != 100 || byID["m1"].Forwards != 2 {
		t.Fatalf("m1 = %+v", byID["m1"])
	}
	if byID["m2"].Views != 500 {
		t.Fatalf("m2 views = %d", byID["m2"].Views)
	}

	// Second pass with unchanged data: 0 changed, still one RPC.
	changed, err = e.RefreshMessageViews("a1", "c1")
	if err != nil {
		t.Fatal(err)
	}
	if changed != 0 {
		t.Fatalf("second pass changed = %d, want 0", changed)
	}

	// Non-channel chat: no-op, no RPC.
	seedChannelChat(t, e, "c2", ChatTypeDMVal)
	if _, err := e.RefreshMessageViews("a1", "c2"); err != nil {
		t.Fatal(err)
	}
	if fc.calls != 2 {
		t.Fatalf("RPC calls = %d, want 2 (non-channel must not call)", fc.calls)
	}

	// No account: quiet no-op.
	if n, err := e.RefreshMessageViews("nope", "c1"); err != nil || n != 0 {
		t.Fatalf("missing account = %d, %v", n, err)
	}
}
