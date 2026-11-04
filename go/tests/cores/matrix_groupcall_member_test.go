package tests

import (
	"encoding/json"
	"testing"
	. "uniclient/cores"

	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"
)

func groupCallHasParticipant(cs *CallSession, uid string) bool {
	for _, p := range cs.Participants {
		if p.UserID == uid {
			return true
		}
	}
	return false
}

func TestGroupMemberEventRequiresMatchingSender(t *testing.T) {
	srv, _ := newMeshHomeserver(t)
	core := seededMeshCore(t, srv)

	sk := "@victim:localhost"
	raw := json.RawMessage(`{"m.calls":[{"m.call_id":"conf_x","m.devices":[{"device_id":"D1","session_id":"s1","expires_ts":9999999999999}]}]}`)
	spoof := &event.Event{
		Type:     MatrixCallMemberStateType,
		RoomID:   id.RoomID("!room:test"),
		StateKey: &sk,
		Sender:   "@attacker:localhost",
		Content:  event.Content{VeryRaw: raw},
	}
	core.HandleGroupMemberEvent(spoof)

	cs, err := core.GetGroupCall("!room:test")
	if err != nil {
		t.Fatalf("GetGroupCall after spoofed event: %v", err)
	}
	if cs == nil {
		t.Fatal("setup: group call session gone before the honest event")
	}
	if groupCallHasParticipant(cs, "@victim:localhost") {
		t.Fatal("spoofed member event stored (sender != state_key)")
	}

	honest := &event.Event{
		Type:     MatrixCallMemberStateType,
		RoomID:   id.RoomID("!room:test"),
		StateKey: &sk,
		Sender:   "@victim:localhost",
		Content:  event.Content{VeryRaw: raw},
	}
	core.HandleGroupMemberEvent(honest)

	cs, err = core.GetGroupCall("!room:test")
	if err != nil {
		t.Fatalf("GetGroupCall after honest event: %v", err)
	}
	if cs == nil || !groupCallHasParticipant(cs, "@victim:localhost") {
		t.Fatalf("honest member event (sender == state_key) not projected into participants: cs=%+v", cs)
	}
}
