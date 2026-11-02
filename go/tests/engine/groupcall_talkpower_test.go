package tests

import (
	"testing"
	. "uniclient/engine"

	"uniclient/cores"
)

type tpFakeCore struct{ cores.StubCore }

func (tpFakeCore) GetGroupCall(string) (*cores.CallSession, error) {
	return &cores.CallSession{
		ID:    "ch:7",
		State: cores.CallStateActive,
		Meta: map[string]string{
			"title":              "Room",
			"participants_count": "2",
			"talk_power":         "blocked",
		},
	}, nil
}

func TestGroupCallInfoMapsTalkPowerBlocked(t *testing.T) {
	e := &Engine{}
	if err := e.AttachAccount("a1", "teamspeak", tpFakeCore{}); err != nil {
		t.Fatal(err)
	}

	info, err := e.GetGroupCall("a1", "ch:7")
	if err != nil {
		t.Fatalf("GetGroupCall: %v", err)
	}
	if info == nil {
		t.Fatal("nil info")
	}
	if !info.TalkPowerBlocked {
		t.Errorf("TalkPowerBlocked = false — Meta[talk_power]=blocked was not mapped (B-26); info=%+v", info)
	}
	if info.Title != "Room" || info.ParticipantsCount != 2 {
		t.Errorf("existing Meta mapping regressed: %+v", info)
	}
}
