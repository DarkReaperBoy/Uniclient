package gui

import (
	"testing"
	"time"

	"uniclient/engine"
)

func TestStoryStripChats(t *testing.T) {
	chats := []engine.ChatInfo{
		{ChatID: "a", Title: "Seen", StoryCount: 3},
		{ChatID: "b", Title: "Unread", StoryCount: 1, HasUnreadStory: true},
		{ChatID: "c", Title: "None"},
		{ChatID: "d", Title: "Unread2", StoryCount: 5, HasUnreadStory: true},
		{ChatID: "e", Title: "Zero"},
	}
	got := storyStripChats(chats)
	if len(got) != 3 {
		t.Fatalf("strip len = %d, want 3 (only chats with stories)", len(got))
	}
	if got[0].ChatID != "b" || got[1].ChatID != "d" {
		t.Fatalf("unread-first order: %s, %s", got[0].ChatID, got[1].ChatID)
	}
	if got[2].ChatID != "a" {
		t.Fatalf("seen story chat must come after unread: %s", got[2].ChatID)
	}
	weird := []engine.ChatInfo{{ChatID: "x", HasUnreadStory: true}}
	if s := storyStripChats(weird); len(s) != 0 {
		t.Fatalf("zero-count chat must be hidden, got %d", len(s))
	}
}

func TestParseStories(t *testing.T) {
	in := `[
		{"id":1,"date":1700000000,"caption":"Hello","media_type":"photo","local_path":"/tmp/1.jpg","views":42},
		{"id":2,"date":1700000100,"caption":"","media_type":"video","local_path":"/tmp/2.mp4","views":7}
	]`
	items, err := parseStories(in)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if len(items) != 2 {
		t.Fatalf("items = %d", len(items))
	}
	if items[0].ID != 1 || items[0].Caption != "Hello" || items[0].Views != 42 {
		t.Fatalf("item0 = %+v", items[0])
	}
	if !isVideoStory(items[1]) || isVideoStory(items[0]) {
		t.Fatalf("video detection: photo=%v video=%v", isVideoStory(items[0]), isVideoStory(items[1]))
	}
	if _, err := parseStories("not json"); err == nil {
		t.Fatal("garbage must error")
	}
	if items, err := parseStories("[]"); err != nil || len(items) != 0 {
		t.Fatalf("empty: %v %d", err, len(items))
	}
}

func TestIsVideoStoryByType(t *testing.T) {
	if !isVideoStory(storyItem{MediaType: "video"}) {
		t.Fatal("media_type video must count")
	}
	if isVideoStory(storyItem{MediaType: "photo"}) {
		t.Fatal("photo must not count")
	}
	if !isVideoStory(storyItem{LocalPath: "/x/2.mp4"}) {
		t.Fatal("mp4 path must count as video")
	}
}

func TestStoryStep(t *testing.T) {
	if got := storyStep(0, -1, 3); got != 0 {
		t.Fatalf("prev at 0 = %d, want clamp 0", got)
	}
	if got := storyStep(1, -1, 3); got != 0 {
		t.Fatalf("prev = %d", got)
	}
	if got := storyStep(2, 1, 3); got != 2 {
		t.Fatalf("next at last = %d, want clamp 2 (caller closes)", got)
	}
	if got := storyStep(0, 1, 3); got != 1 {
		t.Fatalf("next = %d", got)
	}
}

func TestStoryMetaLine(t *testing.T) {
	now := time.Unix(1700000000, 0)
	s := storyItem{Views: 42, Date: now.Unix()}
	got := storyMetaLine(s, now)
	if got == "" {
		t.Fatal("meta line must not be empty")
	}
	if s2 := (storyItem{Date: now.Unix()}); storyMetaLine(s2, now) == "" {
		t.Fatal("date-only meta line must exist")
	}
}

func TestStoryRingUnread(t *testing.T) {
	c := engine.ChatInfo{StoryCount: 1}
	if storyRingUnread(c) {
		t.Fatal("no unread flag → seen ring")
	}
	c.HasUnreadStory = true
	if !storyRingUnread(c) {
		t.Fatal("unread flag → accent ring")
	}
}

func TestParseStoriesReactions(t *testing.T) {
	in := `[
		{"id":1,"date":1700000000,"caption":"Hi","media_type":"photo","views":42,"reactions":3,"sent_reaction":"🔥"}
	]`
	items, err := parseStories(in)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if len(items) != 1 {
		t.Fatalf("items = %d", len(items))
	}
	if items[0].Reactions != 3 {
		t.Errorf("reactions = %d, want 3", items[0].Reactions)
	}
	if items[0].SentReaction != "🔥" {
		t.Errorf("sent reaction = %q, want 🔥", items[0].SentReaction)
	}
}

func TestStoryHeartAction(t *testing.T) {
	if emoji, open := storyHeartAction(""); !open || emoji != "" {
		t.Errorf("unreacted tap = (%q,%v), want picker", emoji, open)
	}
	if emoji, open := storyHeartAction("🔥"); open || emoji != "" {
		t.Errorf("reacted tap = (%q,%v), want remove", emoji, open)
	}
}

func TestStoryReplyID(t *testing.T) {
	if got := storyReplyID(17); got != "story:17" {
		t.Errorf("reply id = %q, want story:17", got)
	}
}

func TestStoryOwnActionVisibility(t *testing.T) {
	f := frame{accounts: []engine.AccountInfo{
		{ID: "tg", SelfUserID: "42"},
	}}
	sv := &storyViewerState{accountID: "tg", chatID: "42"}
	if !storyViewerOwn(f, sv) {
		t.Error("own story not detected")
	}
	sv2 := &storyViewerState{accountID: "tg", chatID: "100"}
	if storyViewerOwn(f, sv2) {
		t.Error("peer's story misdetected as own")
	}
}
