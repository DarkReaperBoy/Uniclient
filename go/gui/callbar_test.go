package gui

import (
	"testing"

	"uniclient/engine"
)

// Group-call live bar in the chat view (AyuGram parity slice 70): a bar
// under the chat header while the chat has an active group call, fed by
// engine.GetGroupCall. Pure derivations locked here.

func TestCallBarSubtitle(t *testing.T) {
	c := engine.ChatInfo{Title: "chat"}
	if s := callBarSubtitle(c, nil); s != "group call · live" {
		t.Fatalf("no call info: %q", s)
	}
	gc := &engine.GroupCallInfo{ParticipantsCount: 5}
	if s := callBarSubtitle(c, gc); s != "group call · 5 participants" {
		t.Fatalf("five participants: %q", s)
	}
	gc.ParticipantsCount = 1
	if s := callBarSubtitle(c, gc); s != "group call · 1 participant" {
		t.Fatalf("singular: %q", s)
	}
	gc.IsRtmp = true
	if s := callBarSubtitle(c, gc); s != "group call · 1 participant · live stream" {
		t.Fatalf("rtmp: %q", s)
	}
}

func TestCallBarPollNeeded(t *testing.T) {
	// The bar polls GetGroupCall while its chat is open and has a call;
	// chats without a call never start a poll loop.
	c := engine.ChatInfo{ChatID: "1"}
	if callBarPollNeeded(c) {
		t.Fatal("chat without an active call must not poll")
	}
	c.HasActiveCall = true
	if !callBarPollNeeded(c) {
		t.Fatal("chat with an active call must poll")
	}
}

func TestCallBarJoinedToast(t *testing.T) {
	if s := callJoinedLabel("Group Chat"); s != "Joined the group call in Group Chat" {
		t.Fatalf("toast: %q", s)
	}
}
