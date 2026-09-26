package cores

import (
	"encoding/json"
	"strings"
	"testing"
)

// B-6 → (F-62): MSC3401 membership layer for full-mesh group calls.
// This file pins the PURE state machine first: content encode/parse,
// expiry filtering (spec: expired devices are ignored), renewal
// timing, and the full-mesh marker (empty foci). Transport and mesh
// wiring follow in later slices.
//
// Seam-RED (WORKLOG 294): undefined: buildGroupMemberContent.

func TestGroupMemberContentRoundTrip(t *testing.T) {
	in := matrixCallMemberContent{
		Calls: []matrixCallMemberCall{{
			CallID: "conf_abc",
			Foci:   nil, // empty foci = full-mesh (Tier 1)
			Devices: []matrixCallDevice{{
				DeviceID:  "DEV1",
				SessionID: "sess1",
				ExpiresTS: 1760000000000,
				Feeds: []matrixCallFeed{{
					Purpose:  "m.usermedia",
					StreamID: "stream1",
					TrackID:  "track1",
					Settings: map[string]interface{}{"m.maxbr": 48000},
				}},
			}},
		}},
	}
	raw, err := json.Marshal(in)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	var out matrixCallMemberContent
	if err := json.Unmarshal(raw, &out); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if len(out.Calls) != 1 || out.Calls[0].CallID != "conf_abc" {
		t.Fatalf("calls = %+v", out.Calls)
	}
	if len(out.Calls[0].Foci) != 0 {
		t.Fatalf("foci must stay empty for full-mesh: %v", out.Calls[0].Foci)
	}
	d := out.Calls[0].Devices[0]
	if d.DeviceID != "DEV1" || d.SessionID != "sess1" || d.ExpiresTS != 1760000000000 {
		t.Fatalf("device = %+v", d)
	}
	if len(d.Feeds) != 1 || d.Feeds[0].Purpose != "m.usermedia" || d.Feeds[0].StreamID != "stream1" {
		t.Fatalf("feeds = %+v", d.Feeds)
	}
}

// TestGroupMemberJSONShape: the wire keys must be MSC3401's literal
// dotted names, not our Go field names.
func TestGroupMemberJSONShape(t *testing.T) {
	raw, err := json.Marshal(matrixCallMemberContent{
		Calls: []matrixCallMemberCall{{
			CallID:  "c",
			Devices: []matrixCallDevice{{DeviceID: "D", SessionID: "S", ExpiresTS: 1}},
		}},
	})
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	s := string(raw)
	for _, want := range []string{`"m.calls"`, `"m.call_id"`, `"m.foci"`, `"m.devices"`, `"device_id"`, `"session_id"`, `"expires_ts"`} {
		if !strings.Contains(s, want) {
			t.Errorf("wire JSON missing %s: %s", want, s)
		}
	}
	if strings.Contains(s, `"CallID"`) || strings.Contains(s, `"DeviceID"`) {
		t.Errorf("Go field names leaked into wire format: %s", s)
	}
}

// TestLiveDevicesDropsExpired: expired devices must be ignored (MSC3401:
// expired devices are ignored), live ones kept. now is injected — no
// wall-clock dependence (F-9 rule).
func TestLiveDevicesDropsExpired(t *testing.T) {
	const now int64 = 1_760_000_000_000
	call := matrixCallMemberCall{
		CallID: "c",
		Devices: []matrixCallDevice{
			{DeviceID: "live", ExpiresTS: now + 1000},
			{DeviceID: "expired", ExpiresTS: now - 1},
			{DeviceID: "edge-alive", ExpiresTS: now + 1},
		},
	}
	got := call.liveDevices(now)
	if len(got) != 2 {
		t.Fatalf("live devices = %d, want 2 (%+v)", len(got), got)
	}
	if got[0].DeviceID != "live" || got[1].DeviceID != "edge-alive" {
		t.Fatalf("survivors = %+v", got)
	}
}

// TestNextRenewal: membership must be renewed at half the TTL so a
// dropped update never expires us mid-call.
func TestNextRenewal(t *testing.T) {
	const now int64 = 1_760_000_000_000
	got := matrixNextRenewalAt(now)
	if got <= now || got > now+matrixDeviceTTLMillis {
		t.Fatalf("renewal at %d, want within (%d, %d]", got, now, now+matrixDeviceTTLMillis)
	}
	if got-now != matrixDeviceTTLMillis/2 {
		t.Fatalf("renewal delta = %d, want half TTL %d", got-now, matrixDeviceTTLMillis/2)
	}
}

// TestNewConfIDUnique: conf ids must differ across calls.
func TestNewConfIDUnique(t *testing.T) {
	a, b := matrixNewConfID(), matrixNewConfID()
	if a == b || len(a) < 8 {
		t.Fatalf("conf ids: %q %q", a, b)
	}
	if a[:5] != "conf_" {
		t.Fatalf("conf id prefix: %q", a)
	}
}
