package gui

import (
	"testing"

	"uniclient/cores"
	"uniclient/engine"
)

// Group-call live bar in the chat view (AyuGram parity slice 70): a bar
// under the chat header while the chat has an active group call, fed by
// engine.GetGroupCall. Pure derivations locked here.

func TestCallBarSubtitle(t *testing.T) {
	c := engine.ChatInfo{Title: "chat"}
	if s := callBarSubtitle(c, nil, false); s != "group call · live" {
		t.Fatalf("no call info: %q", s)
	}
	gc := &engine.GroupCallInfo{ParticipantsCount: 5}
	if s := callBarSubtitle(c, gc, false); s != "group call · 5 participants" {
		t.Fatalf("five participants: %q", s)
	}
	gc.ParticipantsCount = 1
	if s := callBarSubtitle(c, gc, false); s != "group call · 1 participant" {
		t.Fatalf("singular: %q", s)
	}
	gc.IsRtmp = true
	if s := callBarSubtitle(c, gc, false); s != "group call · 1 participant · live stream" {
		t.Fatalf("rtmp: %q", s)
	}
}

func TestCallBarSubtitleVoiceRoom(t *testing.T) {
	c := engine.ChatInfo{Title: "Room"}
	if s := callBarSubtitle(c, nil, true); s != "voice room · empty" {
		t.Fatalf("empty room: %q", s)
	}
	gc := &engine.GroupCallInfo{ParticipantsCount: 3}
	if s := callBarSubtitle(c, gc, true); s != "voice room · 3 participants" {
		t.Fatalf("three participants: %q", s)
	}
	gc.ParticipantsCount = 1
	if s := callBarSubtitle(c, gc, true); s != "voice room · 1 participant" {
		t.Fatalf("singular room: %q", s)
	}
	gc.ParticipantsCount = 0
	if s := callBarSubtitle(c, gc, true); s != "voice room · empty" {
		t.Fatalf("empty again: %q", s)
	}
}

func TestVoiceRoomChat(t *testing.T) {
	mumbleRoom := engine.ChatInfo{Type: engine.ChatTypeGroupVal}
	if !voiceRoomChat(mumbleRoom, []string{cores.CapVoiceRooms}) {
		t.Fatal("group chat on a VOICE_ROOMS account must be a voice room")
	}
	if voiceRoomChat(mumbleRoom, []string{cores.CapGroupCalls}) {
		t.Fatal("GROUP_CALLS alone is not a standing voice room")
	}
	dm := engine.ChatInfo{Type: engine.ChatTypeDMVal}
	if voiceRoomChat(dm, []string{cores.CapVoiceRooms}) {
		t.Fatal("DMs are never voice rooms")
	}
	if voiceRoomChat(mumbleRoom, nil) {
		t.Fatal("no caps, no voice room")
	}
}

func TestCallBarPollNeeded(t *testing.T) {
	// The bar polls GetGroupCall while its chat is open and has a call;
	// chats without a call never start a poll loop — except standing
	// voice rooms, whose occupancy changes as users join/leave.
	c := engine.ChatInfo{ChatID: "1"}
	if callBarPollNeeded(c, false) {
		t.Fatal("chat without an active call must not poll")
	}
	c.HasActiveCall = true
	if !callBarPollNeeded(c, false) {
		t.Fatal("chat with an active call must poll")
	}
	c.HasActiveCall = false
	if !callBarPollNeeded(c, true) {
		t.Fatal("voice rooms poll while open (occupancy is live)")
	}
}

func TestCallBarJoinedToast(t *testing.T) {
	if s := callJoinedLabel("Group Chat"); s != "Joined the group call in Group Chat" {
		t.Fatalf("toast: %q", s)
	}
}
