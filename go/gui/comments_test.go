package gui

import (
	"testing"

	"uniclient/engine"
)

func TestCommentsLabel(t *testing.T) {
	if got := commentsCountLabel(1); got != "1 comment" {
		t.Errorf("singular = %q, want 1 comment", got)
	}
	if got := commentsCountLabel(5); got != "5 comments" {
		t.Errorf("plural = %q, want 5 comments", got)
	}
	if got := commentsCountLabel(1500); got != "1.5K comments" {
		t.Errorf("compact = %q, want 1.5K comments", got)
	}
}

func TestCommentsRowVisible(t *testing.T) {
	if !commentsRowVisible(engine.ChatInfo{Type: engine.ChatTypeChanVal}, 3) {
		t.Error("channel post with comments must show the row")
	}
	if commentsRowVisible(engine.ChatInfo{Type: engine.ChatTypeChanVal}, 0) {
		t.Error("zero comments must hide the row")
	}
	if commentsRowVisible(engine.ChatInfo{Type: engine.ChatTypeGroupVal}, 3) {
		t.Error("group must not show the comment row")
	}
	if commentsRowVisible(engine.ChatInfo{Type: engine.ChatTypeDMVal}, 3) {
		t.Error("DM must not show the comment row")
	}
}

func TestThreadBarTitle(t *testing.T) {
	if got := threadBarTitle(""); got != "Comments" {
		t.Errorf("default title = %q, want Comments", got)
	}
	if got := threadBarTitle("Big news!"); got != "Comments · Big news!" {
		t.Errorf("titled = %q", got)
	}
}

func TestThreadDeepJumpWindow(t *testing.T) {
	mk := func(id string, ts int64) engine.CachedMessage {
		return engine.CachedMessage{MsgID: id, Timestamp: ts}
	}
	newest := []engine.CachedMessage{mk("c1", 10), mk("c2", 20), mk("c3", 30)}
	older := []engine.CachedMessage{mk("target", 25), mk("o2", 15), mk("o1", 5)}

	win, jump := threadDeepJumpWindow(newest, older, "target")
	if win == nil {
		t.Fatal("window = nil, want assembled window")
	}
	wantIDs := []string{"o1", "o2", "target", "c3"}
	if len(win) != len(wantIDs) {
		t.Fatalf("window len = %d, want %d (%v)", len(win), len(wantIDs), win)
	}
	for i, id := range wantIDs {
		if win[i].MsgID != id {
			t.Errorf("win[%d] = %s, want %s", i, win[i].MsgID, id)
		}
	}
	if jump != 2 {
		t.Errorf("jump = %d, want 2 (the target row)", jump)
	}

	win, jump = threadDeepJumpWindow(newest, nil, "c2")
	if len(win) != 3 || win[1].MsgID != "c2" || jump != 1 {
		t.Fatalf("in-page target: win=%v jump=%d, want newest page and index 1", win, jump)
	}

	win, jump = threadDeepJumpWindow(newest, older, "nope")
	if win != nil || jump != -1 {
		t.Fatalf("missing target: win=%v jump=%d, want nil/-1", win, jump)
	}
}

func TestOpenCommentThreadDeepSchedules(t *testing.T) {
	a := &App{}
	a.openPermalinkTarget("acc1", "-100123", "My Channel", "55", "", "77")

	a.mu.Lock()
	defer a.mu.Unlock()
	if a.pendingOpen == nil || a.pendingOpen.AccountID != "acc1" || a.pendingOpen.ChatID != "-100123" {
		t.Fatalf("pendingOpen = %+v, want acc1/-100123", a.pendingOpen)
	}
	if a.pendingTitle != "My Channel" {
		t.Fatalf("pendingTitle = %q, want My Channel", a.pendingTitle)
	}
	if a.pendingThread == nil {
		t.Fatal("comment link did not schedule pendingThread")
	}
	if a.pendingThread.postID != "55" || a.pendingThread.commentID != "77" {
		t.Fatalf("pendingThread = %+v, want post 55 / comment 77", a.pendingThread)
	}
	if a.pendingJump != nil {
		t.Fatalf("pendingJump = %+v, want none for comment links", a.pendingJump)
	}
	if a.pendingTopic != nil {
		t.Fatalf("pendingTopic = %v, want none for comment links", a.pendingTopic)
	}
}
