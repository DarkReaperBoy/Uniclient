package gui

import (
	"testing"

	"uniclient/cores"
	"uniclient/engine"
)

func TestReactorTabs(t *testing.T) {
	m := &engine.CachedMessage{Reactions: []cores.Reaction{
		{Emoji: "👍", Count: 3},
		{Emoji: "", Count: 1, DocumentID: 7}, // custom-emoji placeholder skipped
		{Emoji: "🔥", Count: 1},
	}}
	tabs := reactorTabs(m)
	if len(tabs) != 2 || tabs[0] != "👍" || tabs[1] != "🔥" {
		t.Errorf("tabs = %v", tabs)
	}
	if reactorTabs(&engine.CachedMessage{}) != nil {
		t.Error("no reactions = no tabs")
	}
}

func TestReactorRowName(t *testing.T) {
	if got := reactorRowName(cores.Reaction{PeerName: "Alice"}); got != "Alice" {
		t.Errorf("name = %q", got)
	}
	if got := reactorRowName(cores.Reaction{PeerID: "42"}); got != "user 42" {
		t.Errorf("id fallback = %q", got)
	}
	if got := reactorRowName(cores.Reaction{}); got != "someone" {
		t.Errorf("last fallback = %q", got)
	}
}
