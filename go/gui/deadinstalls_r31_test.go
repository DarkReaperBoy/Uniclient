package gui

import (
	"testing"

	"uniclient/engine"
)

func TestApplyOpenChatMessagesGenGuard(t *testing.T) {
	k := chatKey{AccountID: "a", ChatID: "c"}
	mk := func(id string) []engine.CachedMessage { return []engine.CachedMessage{{MsgID: id}} }

	cur := &App{}
	cur.mu.Lock()
	cur.selected = &k
	cur.loadingMsgs = true
	cur.uiGen = 7
	gen := cur.uiGen
	cur.mu.Unlock()
	cur.applyOpenChatMessages(k, gen, mk("1"))
	if len(cur.messages) != 1 || cur.messages[0].MsgID != "1" || cur.msgFor == nil || *cur.msgFor != k || cur.loadingMsgs {
		t.Fatalf("current-gen install must land: msgs=%v msgFor=%v loading=%v", cur.messages, cur.msgFor, cur.loadingMsgs)
	}

	stale := &App{}
	stale.mu.Lock()
	stale.selected = &k
	stale.uiGen = 7
	stale.mu.Unlock()
	stale.applyOpenChatMessages(k, 6, mk("x"))
	if len(stale.messages) != 0 || stale.msgFor != nil {
		t.Fatalf("stale-gen install must be dropped: msgs=%v msgFor=%v", stale.messages, stale.msgFor)
	}

	moved := &App{}
	other := chatKey{AccountID: "a", ChatID: "other"}
	moved.mu.Lock()
	moved.selected = &other
	moved.uiGen = 7
	moved.mu.Unlock()
	moved.applyOpenChatMessages(k, 7, mk("x"))
	if len(moved.messages) != 0 || moved.msgFor != nil {
		t.Fatalf("install for a chat this window no longer shows must be dropped (R31)")
	}
}

func TestMergeMessagesGenGuard(t *testing.T) {
	k := chatKey{AccountID: "a", ChatID: "c"}
	fresh := []engine.CachedMessage{{MsgID: "f", Timestamp: 100}}

	ok := &App{}
	ok.mu.Lock()
	ok.selected = &k
	ok.msgFor = &k
	ok.uiGen = 3
	ok.mu.Unlock()
	ok.mergeMessages(&k, fresh, 3)
	if len(ok.messages) != 1 || ok.messages[0].MsgID != "f" || ok.msgFor == nil || *ok.msgFor != k {
		t.Fatalf("current-gen merge must land: %v", ok.messages)
	}

	stale := &App{}
	stale.mu.Lock()
	stale.selected = &k
	stale.msgFor = &k
	stale.messages = []engine.CachedMessage{{MsgID: "keep"}}
	stale.uiGen = 4
	stale.mu.Unlock()
	stale.mergeMessages(&k, fresh, 3)
	if len(stale.messages) != 1 || stale.messages[0].MsgID != "keep" {
		t.Fatalf("stale-gen merge must be dropped (R31): %v", stale.messages)
	}

	keep := &App{}
	keep.mu.Lock()
	keep.selected = &k
	keep.msgFor = &k
	keep.uiGen = 5
	keep.messages = []engine.CachedMessage{{MsgID: "old", Timestamp: 1}, {MsgID: "f", Timestamp: 100}}
	keep.mu.Unlock()
	keep.mergeMessages(&k, fresh, 5)
	if len(keep.messages) != 2 || keep.messages[0].MsgID != "old" || keep.messages[1].MsgID != "f" {
		t.Fatalf("merge must keep older pages: %v", keep.messages)
	}
}

func TestApplyForumTopicWindowGenGuard(t *testing.T) {
	k := chatKey{AccountID: "a", ChatID: "c"}
	msgs := []engine.CachedMessage{{MsgID: "t1"}}

	ok := &App{}
	ok.mu.Lock()
	ok.selected = &k
	ok.forumTopic = "T1"
	ok.loadingMsgs = true
	ok.uiGen = 5
	ok.mu.Unlock()
	ok.applyForumTopicWindow(k, "T1", 5, msgs)
	if len(ok.messages) != 1 || ok.loadingMsgs {
		t.Fatalf("current-gen topic window must land: %v loading=%v", ok.messages, ok.loadingMsgs)
	}

	stale := &App{}
	stale.mu.Lock()
	stale.selected = &k
	stale.forumTopic = "T1"
	stale.uiGen = 6
	stale.mu.Unlock()
	stale.applyForumTopicWindow(k, "T1", 5, msgs)
	if len(stale.messages) != 0 {
		t.Fatal("stale-gen topic window must be dropped (R31)")
	}

	switched := &App{}
	switched.mu.Lock()
	switched.selected = &k
	switched.forumTopic = "T2"
	switched.uiGen = 5
	switched.mu.Unlock()
	switched.applyForumTopicWindow(k, "T1", 5, msgs)
	if len(switched.messages) != 0 {
		t.Fatal("a window for a topic this window no longer shows must be dropped (R31)")
	}
}

func TestApplyOlderPageGenGuard(t *testing.T) {
	k := chatKey{AccountID: "a", ChatID: "c"}
	base := []engine.CachedMessage{{MsgID: "new", Timestamp: 100}}
	older := []engine.CachedMessage{{MsgID: "o1", Timestamp: 10}}

	ok := &App{}
	ok.mu.Lock()
	ok.selected = &k
	ok.msgFor = &k
	ok.messages = base
	ok.uiGen = 9
	ok.loadingOlder = true
	ok.mu.Unlock()
	ok.applyOlderPage(k, 9, older, nil)
	if len(ok.messages) != 2 || ok.messages[0].MsgID != "o1" || ok.loadingOlder {
		t.Fatalf("current-gen older page must prepend: %v", ok.messages)
	}

	stale := &App{}
	stale.mu.Lock()
	stale.selected = &k
	stale.msgFor = &k
	stale.messages = append([]engine.CachedMessage(nil), base...)
	stale.uiGen = 10
	stale.loadingOlder = true
	stale.mu.Unlock()
	stale.applyOlderPage(k, 9, older, nil)
	if len(stale.messages) != 1 || stale.messages[0].MsgID != "new" {
		t.Fatalf("stale-gen older page must be dropped (R31): %v", stale.messages)
	}
	if stale.loadingOlder {
		t.Fatal("the fetch's own loadingOlder flag clears even on a stale drop")
	}
}
