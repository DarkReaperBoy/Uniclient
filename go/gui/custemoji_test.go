package gui

import (
	"testing"

	"uniclient/cores"
)

// Custom-emoji reaction pills (slice 53): the pure helpers that decide
// which reactions get document-thumbnail pills and what wire key the
// engine receives for toggling them.
func TestCustomWantDocs(t *testing.T) {
	list := []cores.Reaction{
		{Emoji: "👍", Count: 2},
		{Emoji: "", DocumentID: 7, Count: 1},
		{Emoji: "🔥", Count: 4},
		{Emoji: "", DocumentID: 99, Count: 3, ByMe: true},
	}
	got := customWantDocs(list)
	if len(got) != 2 || got[0] != 7 || got[1] != 99 {
		t.Errorf("customWantDocs = %v", got)
	}
	if customWantDocs(nil) != nil {
		t.Error("nil list = nil")
	}
	if got := customWantDocs([]cores.Reaction{{Emoji: "🙂"}}); got != nil {
		t.Errorf("no custom reactions = nil, got %v", got)
	}
}

func TestCustomReactionKey(t *testing.T) {
	if got := customReactionKey(42); got != "custom_42" {
		t.Errorf("key = %q", got)
	}
	if got := customReactionKey(-1); got != "custom_-1" {
		t.Errorf("negative doc = %q", got)
	}
	if got := customReactionKey(0); got != "custom_0" {
		t.Errorf("zero doc = %q", got)
	}
}
