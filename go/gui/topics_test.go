package gui

import (
	"image/color"
	"testing"

	"uniclient/cores"
)

func mkTopic(id, topMsg string, pinned bool) cores.ForumTopic {
	return cores.ForumTopic{ID: id, Title: "T" + id, TopMessageID: topMsg, IsPinned: pinned}
}

func TestSortForumTopics(t *testing.T) {
	topics := []cores.ForumTopic{
		mkTopic("5", "50", false),
		mkTopic("2", "200", true),
		mkTopic("7", "90", true),
		mkTopic("3", "300", false),
		mkTopic("1", "10", false),
	}
	got := sortForumTopics(topics)
	if got[0].ID != "2" || got[1].ID != "7" {
		t.Fatalf("pinned server order = %s %s, want 2 7", got[0].ID, got[1].ID)
	}
	if got[2].ID != "3" || got[3].ID != "5" {
		t.Fatalf("activity order = %s %s", got[2].ID, got[3].ID)
	}
	if got[4].ID != "1" {
		t.Fatalf("General order = %s", got[4].ID)
	}
	if topics[0].ID != "5" {
		t.Fatal("input slice mutated")
	}

	all := sortForumTopics([]cores.ForumTopic{mkTopic("9", "5", true), mkTopic("8", "90", true)})
	if all[0].ID != "9" || all[1].ID != "8" {
		t.Fatalf("all-pinned order = %s %s, want server order 9 8", all[0].ID, all[1].ID)
	}
}

func TestTopicColor(t *testing.T) {
	accent := color.NRGBA{R: 1, G: 2, B: 3, A: 255}
	if got := topicColor(0x6FB9F0, accent); got.R != 0x6F || got.G != 0xB9 {
		t.Fatalf("blue = %+v", got)
	}
	if got := topicColor(0xFF93B2, accent); got.B != 0xB2 {
		t.Fatalf("pink = %+v", got)
	}
	if got := topicColor(0x123456, accent); got != accent {
		t.Fatalf("unknown id must fall back to accent: %+v", got)
	}
}

func TestTopicIsGeneral(t *testing.T) {
	if !topicIsGeneral("1") {
		t.Fatal("id 1 is General")
	}
	if topicIsGeneral("2") {
		t.Fatal("id 2 is not General")
	}
}

func TestTopicSubtitle(t *testing.T) {
	tp := cores.ForumTopic{IsMy: true, IsPinned: true}
	if got := topicSubtitle(tp); got != "Your topic · pinned" {
		t.Fatalf("subtitle = %q", got)
	}
	if got := topicSubtitle(cores.ForumTopic{}); got != "Topic" {
		t.Fatalf("plain subtitle = %q", got)
	}
}

func TestForumTopicMoveIDs(t *testing.T) {
	topics := []cores.ForumTopic{
		mkTopic("10", "1", true),
		mkTopic("11", "2", true),
		mkTopic("12", "3", true),
		mkTopic("13", "4", false),
	}
	if got := forumTopicMoveIDs(topics, "11", -1); len(got) != 3 ||
		got[0] != 11 || got[1] != 10 || got[2] != 12 {
		t.Errorf("move up = %v", got)
	}
	if got := forumTopicMoveIDs(topics, "11", 1); len(got) != 3 ||
		got[0] != 10 || got[1] != 12 || got[2] != 11 {
		t.Errorf("move down = %v", got)
	}
	if got := forumTopicMoveIDs(topics, "10", -1); got[0] != 10 || got[1] != 11 || got[2] != 12 {
		t.Errorf("edge move up = %v (want no-op)", got)
	}
	if got := forumTopicMoveIDs(topics, "12", 1); got[0] != 10 || got[1] != 11 || got[2] != 12 {
		t.Errorf("edge move down = %v (want no-op)", got)
	}
	if got := forumTopicMoveIDs(topics, "13", 1); got[0] != 10 || got[1] != 11 || got[2] != 12 {
		t.Errorf("unpinned move = %v (want no-op)", got)
	}
}

func TestForumTopicMenuCanMove(t *testing.T) {
	topics := []cores.ForumTopic{
		mkTopic("10", "1", true),
		mkTopic("11", "2", true),
	}
	if up, down := forumTopicMenuCanMove(topics, "10"); up || !down {
		t.Errorf("first pinned: canMove = %v %v, want false true", up, down)
	}
	if up, down := forumTopicMenuCanMove(topics, "11"); !up || down {
		t.Errorf("last pinned: canMove = %v %v, want true false", up, down)
	}
	one := []cores.ForumTopic{mkTopic("10", "1", true)}
	if up, down := forumTopicMenuCanMove(one, "10"); up || down {
		t.Errorf("single pinned: canMove = %v %v, want none", up, down)
	}
	if up, down := forumTopicMenuCanMove(topics, "99"); up || down {
		t.Errorf("missing topic: canMove = %v %v, want none", up, down)
	}
}
