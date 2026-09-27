package cores

import (
	"encoding/json"
	"testing"

	"maunium.net/go/mautrix/event"
)

// B-6 → F-62 hardening: MSC3401 says a member event's state_key is the
// sender's OWN matrix ID ("thus ensuring other users cannot edit it") —
// but Matrix auth rules only special-case m.room.member. Once the event
// type is granted at PL 0 (slice 300's room-creation fix), any room
// member could publish a member event with SOMEONE ELSE's state_key and
// spoof their call membership. Receivers MUST check sender == state_key.
//
// RED (behavioral, WORKLOG 300): the spoofed event below is currently
// stored into groupMembers — `spoofed member event stored`.
func TestGroupMemberEventRequiresMatchingSender(t *testing.T) {
	core := &MatrixCore{}

	sk := "@victim:localhost"
	raw := json.RawMessage(`{"m.calls":[{"m.call_id":"conf_x","m.devices":[{"device_id":"D1","session_id":"s1","expires_ts":9999999999999}]}]}`)
	spoof := &event.Event{
		Type:     matrixCallMemberStateType,
		StateKey: &sk,
		Sender:   "@attacker:localhost",
		Content:  event.Content{VeryRaw: raw},
	}
	core.handleGroupMemberEvent(spoof)

	core.groupMu.Lock()
	n := len(core.groupMembers)
	core.groupMu.Unlock()
	if n != 0 {
		t.Fatalf("spoofed member event stored (sender != state_key): %d entries", n)
	}

	// The honest event (sender == state_key) must still be accepted.
	honest := &event.Event{
		Type:     matrixCallMemberStateType,
		StateKey: &sk,
		Sender:   "@victim:localhost",
		Content:  event.Content{VeryRaw: raw},
	}
	core.handleGroupMemberEvent(honest)

	core.groupMu.Lock()
	_, ok := core.groupMembers["@victim:localhost"]
	core.groupMu.Unlock()
	if !ok {
		t.Fatal("honest member event (sender == state_key) was dropped")
	}
}
