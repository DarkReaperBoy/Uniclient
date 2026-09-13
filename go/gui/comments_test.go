package gui

import (
	"testing"

	"uniclient/engine"
)

// Channel-post comments (slice 195): the comments chip's label/gating
// and the thread-bar title — pure.

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
	// Channel post with comments → visible.
	if !commentsRowVisible(engine.ChatInfo{Type: engine.ChatTypeChanVal}, 3) {
		t.Error("channel post with comments must show the row")
	}
	// Zero/absent comments → hidden (no dead chip).
	if commentsRowVisible(engine.ChatInfo{Type: engine.ChatTypeChanVal}, 0) {
		t.Error("zero comments must hide the row")
	}
	// Groups/DMs never show the comment chip (their replies render as
	// normal reply headers).
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
