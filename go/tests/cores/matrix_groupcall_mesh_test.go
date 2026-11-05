package tests

import (
	"encoding/json"
	"testing"
	. "uniclient/cores"

	"maunium.net/go/mautrix/id"
)

func TestGroupPeerKey(t *testing.T) {
	if got := GroupPeerKey("@a:t", "DEV"); got != "@a:t|DEV" {
		t.Fatalf("peer key = %q", got)
	}
}

func TestGroupShouldOfferNoGlare(t *testing.T) {
	pairs := [][2]string{
		{"@a:t|D1", "@b:t|D1"},
		{"@b:t|D1", "@a:t|D1"},
		{"@a:t|D1", "@a:t|D2"},
		{"@z:t|D1", "@a:t|D9"},
	}
	for _, p := range pairs {
		ab := GroupShouldOffer(p[0], p[1])
		ba := GroupShouldOffer(p[1], p[0])
		if ab == ba {
			t.Errorf("pair (%q, %q): both offered=%v — exactly one side must offer", p[0], p[1], ab)
		}
	}
	if GroupShouldOffer("@a:t|D1", "@a:t|D1") {
		t.Error("a device must not offer to itself")
	}
}

func TestGroupPeersToConnect(t *testing.T) {
	const now int64 = 1_760_000_000_000
	members := map[id.UserID]MatrixCallMemberContent{
		"@alice:test": {Calls: []MatrixCallMemberCall{{CallID: "c", Devices: []MatrixCallDevice{
			{DeviceID: "SELF", ExpiresTS: now + 10_000},
			{DeviceID: "ALICE2", ExpiresTS: now + 10_000},
		}}}},
		"@bob:test": {Calls: []MatrixCallMemberCall{{CallID: "c", Devices: []MatrixCallDevice{
			{DeviceID: "BOB1", ExpiresTS: now + 10_000},
			{DeviceID: "BOB-EXPIRED", ExpiresTS: now - 1},
		}}}},
		"@carol:test": {Calls: []MatrixCallMemberCall{{CallID: "c", Devices: []MatrixCallDevice{
			{DeviceID: "CAROL1", ExpiresTS: now - 1},
		}}}},
	}
	got := GroupPeersToConnect("@alice:test", "SELF", members, now)
	if len(got) != 2 {
		t.Fatalf("peers = %+v, want ALICE2 + BOB1", got)
	}
	if GroupPeerKey(string(got[0].UserID), got[0].Device) != GroupPeerKey("@alice:test", "ALICE2") || GroupPeerKey(string(got[1].UserID), got[1].Device) != GroupPeerKey("@bob:test", "BOB1") {
		t.Fatalf("order must be sorted by key: %+v", got)
	}
	for _, p := range got {
		if GroupPeerKey(string(p.UserID), p.Device) == GroupPeerKey("@alice:test", "SELF") {
			t.Fatal("own device must not be a peer")
		}
	}
}

func TestConfIDFromRaw(t *testing.T) {
	if ConfIDFromRaw(map[string]interface{}{"conf_id": "conf_x"}) != "conf_x" {
		t.Fatal("conf_id not read")
	}
	if ConfIDFromRaw(map[string]interface{}{"call_id": "x"}) != "" {
		t.Fatal("absent conf_id must be empty")
	}
	if ConfIDFromRaw(map[string]interface{}{"conf_id": 42}) != "" {
		t.Fatal("wrong type must be empty")
	}
	if ConfIDFromRaw(nil) != "" {
		t.Fatal("nil raw must be empty")
	}
}

func TestWithConfID(t *testing.T) {
	type invite struct {
		CallID string `json:"call_id"`
		Offer  string `json:"offer"`
	}
	out, err := WithConfID(invite{CallID: "c1", Offer: "v=0"}, "conf_z")
	if err != nil {
		t.Fatalf("WithConfID: %v", err)
	}
	if out["conf_id"] != "conf_z" || out["call_id"] != "c1" || out["offer"] != "v=0" {
		t.Fatalf("merged content = %#v", out)
	}
	raw, err := json.Marshal(out)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	if !json.Valid(raw) {
		t.Fatalf("invalid json: %s", raw)
	}
}
