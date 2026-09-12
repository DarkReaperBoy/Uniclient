package gui

import (
	"testing"

	"uniclient/cores"
)

func mkTabTopic(id, title string, unread int, closed, hidden bool) cores.ForumTopic {
	return cores.ForumTopic{ID: id, Title: title, UnreadCount: unread, IsClosed: closed, IsHidden: hidden, ColorID: 0x6FB9F0}
}

func TestTopicTabsForIncludesAllTopicsFirst(t *testing.T) {
	topics := []cores.ForumTopic{mkTabTopic("1", "General", 0, false, false), mkTabTopic("5", "News", 2, false, false)}
	tabs := topicTabsFor(topics, "5")
	if len(tabs) != 3 {
		t.Fatalf("tabs = %d, want 3 (All topics + 2)", len(tabs))
	}
	if tabs[0].topicID != "" || tabs[0].title != "All topics" {
		t.Fatalf("first tab = %+v, want the All-topics pseudo-tab", tabs[0])
	}
	if tabs[1].topicID != "1" || tabs[2].topicID != "5" {
		t.Fatalf("topic order = %s,%s, want 1,5 (cached pinned-first order kept)", tabs[1].topicID, tabs[2].topicID)
	}
}

func TestTopicTabsForActive(t *testing.T) {
	topics := []cores.ForumTopic{mkTabTopic("1", "General", 0, false, false), mkTabTopic("5", "News", 2, false, false)}
	tabs := topicTabsFor(topics, "5")
	if !tabs[2].active || tabs[0].active || tabs[1].active {
		t.Fatalf("active flags: %v %v %v, want only the 5 tab", tabs[0].active, tabs[1].active, tabs[2].active)
	}
	// "" (topic-list view) activates the All-topics tab.
	tabs = topicTabsFor(topics, "")
	if !tabs[0].active || tabs[2].active {
		t.Fatalf("list view: active = %v %v, want All-topics only", tabs[0].active, tabs[2].active)
	}
	// Unknown active id (stale) → no topic tab active, All-topics inert.
	tabs = topicTabsFor(topics, "999")
	for i, tab := range tabs {
		if tab.active && tab.topicID != "" {
			t.Fatalf("stale id must not activate topic tabs (tab %d)", i)
		}
	}
}

func TestTopicTabsForSkipsHidden(t *testing.T) {
	topics := []cores.ForumTopic{mkTabTopic("1", "General", 0, false, true), mkTabTopic("5", "News", 0, false, false)}
	tabs := topicTabsFor(topics, "")
	if len(tabs) != 2 {
		t.Fatalf("tabs = %d, want 2 (hidden General skipped)", len(tabs))
	}
	if tabs[1].topicID != "5" {
		t.Fatalf("visible tab = %s, want 5", tabs[1].topicID)
	}
}

func TestTopicTabsForCarriesState(t *testing.T) {
	topics := []cores.ForumTopic{mkTabTopic("7", "Locked", 120, true, false)}
	tabs := topicTabsFor(topics, "7")
	if !tabs[1].closed {
		t.Error("closed flag not carried")
	}
	if tabs[1].unread != 120 {
		t.Errorf("unread = %d, want 120", tabs[1].unread)
	}
	if tabs[1].colorID != 0x6FB9F0 {
		t.Errorf("colorID = %x, want 6FB9F0", tabs[1].colorID)
	}
}

func TestTopicTabBadgeText(t *testing.T) {
	if got := topicTabBadgeText(0); got != "" {
		t.Errorf("badge(0) = %q, want empty", got)
	}
	if got := topicTabBadgeText(7); got != "7" {
		t.Errorf("badge(7) = %q, want 7", got)
	}
	if got := topicTabBadgeText(99); got != "99" {
		t.Errorf("badge(99) = %q, want 99", got)
	}
	if got := topicTabBadgeText(100); got != "99+" {
		t.Errorf("badge(100) = %q, want 99+ (clamp)", got)
	}
}
