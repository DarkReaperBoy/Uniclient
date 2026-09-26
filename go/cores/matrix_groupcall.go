package cores

// MSC3401 group-call membership for B-6 (Tier 1 full-mesh).
//
// Scope of this file: the PURE membership state machine — the
// `org.matrix.msc3401.call.member` content shape (wire keys are the
// spec's literal dotted names), expiry filtering (spec: expired
// devices are ignored), renewal timing, and conf-id generation.
// Transport (m.call.* room events carrying conf_id — documented
// deviation from the spec's to-device transport, chosen because the
// entire 1:1 call stack already runs on room events) and the N×(N−1)
// mesh land in follow-up slices.
//
// Interop honesty: Element's modern default is MatrixRTC/Element
// Call, so Tier-1 full-mesh calls only reach other MSC3401 full-mesh
// clients (matrix-js-sdk's reference model). That limitation ships in
// the F-62 row, not hidden here.

import (
	"crypto/rand"
	"encoding/hex"
	"time"
)

const (
	// matrixCallMemberEventType is MSC3401's membership state event;
	// state_key is the member's own Matrix ID.
	matrixCallMemberEventType = "org.matrix.msc3401.call.member"
	// matrixCallEventType is the timeline placeholder for a running
	// call (MSC3401 §call state event).
	matrixCallEventType = "org.matrix.msc3401.call"

	// matrixDeviceTTLMillis: membership devices carry expires_ts in
	// POSIX milliseconds and must be renewed while connected; we
	// publish a 60 s lease and renew at half (matrixNextRenewalAt) so
	// one dropped state event never expires us mid-call.
	matrixDeviceTTLMillis int64 = 60_000

	// matrixFeedUserMedia is MSC3401's microphone feed purpose
	// (screenshare is "m.screenshare", not needed for Tier-1 audio).
	matrixFeedUserMedia = "m.usermedia"
)

// matrixCallFeed mirrors one media feed declaration of a device.
type matrixCallFeed struct {
	Purpose  string                 `json:"purpose"`
	StreamID string                 `json:"stream_id,omitempty"`
	TrackID  string                 `json:"track_id,omitempty"`
	Settings map[string]interface{} `json:"settings,omitempty"`
}

// matrixCallDevice is one joined device of a participant.
type matrixCallDevice struct {
	DeviceID  string           `json:"device_id"`
	SessionID string           `json:"session_id"`
	ExpiresTS int64            `json:"expires_ts"`
	Feeds     []matrixCallFeed `json:"feeds,omitempty"`
}

// matrixCallMemberCall is one call entry of a member's membership.
// Empty Foci = full-mesh (no SFU focus), the Tier-1 marker.
type matrixCallMemberCall struct {
	CallID  string             `json:"m.call_id"`
	Foci    []string           `json:"m.foci"`
	Devices []matrixCallDevice `json:"m.devices"`
}

// matrixCallMemberContent is the state event content
// (`m.calls` array, one item for our single-call model).
type matrixCallMemberContent struct {
	Calls []matrixCallMemberCall `json:"m.calls"`
}

// liveDevices returns the devices that have not expired at the
// INJECTED instant (no wall-clock dependence — F-9 rule).
func (c matrixCallMemberCall) liveDevices(now int64) []matrixCallDevice {
	var out []matrixCallDevice
	for _, d := range c.Devices {
		if d.ExpiresTS > now {
			out = append(out, d)
		}
	}
	return out
}

// matrixNextRenewalAt: renew at half the lease.
func matrixNextRenewalAt(now int64) int64 {
	return now + matrixDeviceTTLMillis/2
}

// matrixNewConfID mints a fresh group-call id.
func matrixNewConfID() string {
	var b [8]byte
	if _, err := rand.Read(b[:]); err != nil {
		// crypto/rand failing is unrecoverable in practice; fall back
		// to a time-shaped id so callers never see an empty conf id.
		return "conf_" + hex.EncodeToString([]byte(time.Now().UTC().Format("150405.000000000")))
	}
	return "conf_" + hex.EncodeToString(b[:])
}
