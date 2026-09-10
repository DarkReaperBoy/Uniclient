package gui

import (
	"image/color"
	"testing"

	"uniclient/cores"
)

// Forum topics (slice 118) — pure decision logic: ordering, color mapping,
// subtitles, General handling. The engine-side topic scoping is pinned in
// engine/topics_test.go.

func mkTopic(id, topMsg string, pinned bool) cores.ForumTopic {
	return cores.ForumTopic{ID: id, Title: "T" + id, TopMessageID: topMsg, IsPinned: pinned}
}

func TestSortForumTopics(t *testing.T) {
	topics := []cores.ForumTopic{
		mkTopic("5", "50", false),
		mkTopic("2", "200", true),
		mkTopic("3", "300", false),
		mkTopic("1", "10", false), // General
	}
	got := sortForumTopics(topics)
	if got[0].ID != "2" {
		t.Fatalf("pinned must lead, got %s", got[0].ID)
	}
	// Unpinned by descending activity.
	if got[1].ID != "3" || got[2].ID != "5" {
		t.Fatalf("activity order = %s %s", got[1].ID, got[2].ID)
	}
	// General (id 1, lowest activity) last among equals.
	if got[3].ID != "1" {
		t.Fatalf("General order = %s", got[3].ID)
	}
	// Input untouched.
	if topics[0].ID != "5" {
		t.Fatal("input slice mutated")
	}

	// All pinned → pure activity order.
	all := sortForumTopics([]cores.ForumTopic{mkTopic("9", "5", true), mkTopic("8", "90", true)})
	if all[0].ID != "8" {
		t.Fatalf("all-pinned order = %s %s", all[0].ID, all[1].ID)
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
