package tests

import (
	"encoding/json"
	"testing"
	. "uniclient/cores"

	"maunium.net/go/mautrix/event"
)

func TestGroupMemberEventRequiresMatchingSender(t *testing.T) {
	core := &MatrixCore{}

	sk := "@victim:localhost"
	raw := json.RawMessage(`{"m.calls":[{"m.call_id":"conf_x","m.devices":[{"device_id":"D1","session_id":"s1","expires_ts":9999999999999}]}]}`)
	spoof := &event.Event{
		Type:     MatrixCallMemberStateType,
		StateKey: &sk,
		Sender:   "@attacker:localhost",
		Content:  event.Content{VeryRaw: raw},
	}
	core.HandleGroupMemberEvent(spoof)

	core.ForTestGroupMu().Lock()
	n := len(core.ForTestGroupMembers())
	core.ForTestGroupMu().Unlock()
	if n != 0 {
		t.Fatalf("spoofed member event stored (sender != state_key): %d entries", n)
	}

	honest := &event.Event{
		Type:     MatrixCallMemberStateType,
		StateKey: &sk,
		Sender:   "@victim:localhost",
		Content:  event.Content{VeryRaw: raw},
	}
	core.HandleGroupMemberEvent(honest)

	core.ForTestGroupMu().Lock()
	_, ok := core.ForTestGroupMembers()["@victim:localhost"]
	core.ForTestGroupMu().Unlock()
	if !ok {
		t.Fatal("honest member event (sender == state_key) was dropped")
	}
}
