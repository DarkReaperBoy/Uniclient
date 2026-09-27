package cores

import (
	"encoding/json"
	"testing"

	"maunium.net/go/mautrix/id"
)

// B-6 → F-62, mesh decision layer (slice 296): everything that decides
// WHICH peers get a peer-connection and WHO offers, without touching a
// socket — the SDP fan-out (slice 297) consumes these.
//
// Seam-RED (WORKLOG 296): undefined: groupPeersToConnect.

func TestGroupPeerKey(t *testing.T) {
	if got := groupPeerKey("@a:t", "DEV"); got != "@a:t|DEV" {
		t.Fatalf("peer key = %q", got)
	}
}

// TestGroupShouldOfferNoGlare: for any pair EXACTLY one side offers
// (lexicographic tie-break) — the rule that makes glare impossible in
// the N×(N−1) mesh. A key never offers to itself.
func TestGroupShouldOfferNoGlare(t *testing.T) {
	pairs := [][2]string{
		{"@a:t|D1", "@b:t|D1"},
		{"@b:t|D1", "@a:t|D1"},
		{"@a:t|D1", "@a:t|D2"},
		{"@z:t|D1", "@a:t|D9"},
	}
	for _, p := range pairs {
		ab := groupShouldOffer(p[0], p[1])
		ba := groupShouldOffer(p[1], p[0])
		if ab == ba {
			t.Errorf("pair (%q, %q): both offered=%v — exactly one side must offer", p[0], p[1], ab)
		}
	}
	if groupShouldOffer("@a:t|D1", "@a:t|D1") {
		t.Error("a device must not offer to itself")
	}
}

// TestGroupPeersToConnect: live devices everywhere except OUR device;
// expired entries dropped; deterministic order (sorted by peer key).
func TestGroupPeersToConnect(t *testing.T) {
	const now int64 = 1_760_000_000_000
	members := map[id.UserID]matrixCallMemberContent{
		"@alice:test": {Calls: []matrixCallMemberCall{{CallID: "c", Devices: []matrixCallDevice{
			{DeviceID: "SELF", ExpiresTS: now + 10_000},   // ours → excluded
			{DeviceID: "ALICE2", ExpiresTS: now + 10_000}, // our OTHER device → included
		}}}},
		"@bob:test": {Calls: []matrixCallMemberCall{{CallID: "c", Devices: []matrixCallDevice{
			{DeviceID: "BOB1", ExpiresTS: now + 10_000},
			{DeviceID: "BOB-EXPIRED", ExpiresTS: now - 1},
		}}}},
		"@carol:test": {Calls: []matrixCallMemberCall{{CallID: "c", Devices: []matrixCallDevice{
			{DeviceID: "CAROL1", ExpiresTS: now - 1}, // expired → dropped
		}}}},
	}
	got := groupPeersToConnect("@alice:test", "SELF", members, now)
	if len(got) != 2 {
		t.Fatalf("peers = %+v, want ALICE2 + BOB1", got)
	}
	if got[0].key != groupPeerKey("@alice:test", "ALICE2") || got[1].key != groupPeerKey("@bob:test", "BOB1") {
		t.Fatalf("order must be sorted by key: %+v", got)
	}
	for _, p := range got {
		if p.key == groupPeerKey("@alice:test", "SELF") {
			t.Fatal("own device must not be a peer")
		}
	}
}

// TestConfIDFromRaw: the 1:1 vs group dispatch discriminator on raw
// event content.
func TestConfIDFromRaw(t *testing.T) {
	if confIDFromRaw(map[string]interface{}{"conf_id": "conf_x"}) != "conf_x" {
		t.Fatal("conf_id not read")
	}
	if confIDFromRaw(map[string]interface{}{"call_id": "x"}) != "" {
		t.Fatal("absent conf_id must be empty")
	}
	if confIDFromRaw(map[string]interface{}{"conf_id": 42}) != "" {
		t.Fatal("wrong type must be empty")
	}
	if confIDFromRaw(nil) != "" {
		t.Fatal("nil raw must be empty")
	}
}

// TestWithConfID: outgoing 1:1-shaped content gains conf_id without
// losing any field (the group transport rides the same m.call.* names).
func TestWithConfID(t *testing.T) {
	type invite struct {
		CallID string `json:"call_id"`
		Offer  string `json:"offer"`
	}
	out, err := withConfID(invite{CallID: "c1", Offer: "v=0"}, "conf_z")
	if err != nil {
		t.Fatalf("withConfID: %v", err)
	}
	if out["conf_id"] != "conf_z" || out["call_id"] != "c1" || out["offer"] != "v=0" {
		t.Fatalf("merged content = %#v", out)
	}
	// Round-trips through JSON like the real send path.
	raw, err := json.Marshal(out)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	if !json.Valid(raw) {
		t.Fatalf("invalid json: %s", raw)
	}
}
