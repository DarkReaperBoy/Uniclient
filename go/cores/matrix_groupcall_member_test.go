package cores

import (
	"encoding/json"
	"testing"

	"maunium.net/go/mautrix/event"
)

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
