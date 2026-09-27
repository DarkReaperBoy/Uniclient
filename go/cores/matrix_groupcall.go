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
	"encoding/json"
	"sort"
	"time"

	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"
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

// MSC3401 event types. Built explicitly with Class: event.StateEventType —
// event.NewEventType guesses Message class for org.matrix.* names.
var (
	matrixCallMemberStateType = event.Type{Type: matrixCallMemberEventType, Class: event.StateEventType}
	matrixCallStateType       = event.Type{Type: matrixCallEventType, Class: event.StateEventType}
)

// matrixNewSessionID mints the per-app-load session id MSC3401 requires.
func matrixNewSessionID() string {
	var b [8]byte
	if _, err := rand.Read(b[:]); err != nil {
		return "gs-" + time.Now().UTC().Format("20060102150405.000000000")
	}
	return "gs-" + hex.EncodeToString(b[:])
}

// publishGroupMembership writes our own m.call.member state event
// (state_key = our MXID, spec-mandated) with a fresh lease.
func (m *MatrixCore) publishGroupMembership(roomID id.RoomID, conf, sess string, now int64) error {
	content := matrixCallMemberContent{
		Calls: []matrixCallMemberCall{{
			CallID: conf,
			Foci:   []string{}, // full-mesh: no focus
			Devices: []matrixCallDevice{{
				DeviceID:  m.deviceID.String(),
				SessionID: sess,
				ExpiresTS: now + matrixDeviceTTLMillis,
				Feeds: []matrixCallFeed{{
					Purpose:  matrixFeedUserMedia,
					StreamID: "ms-" + sess,
					TrackID:  "mt-" + sess,
					Settings: map[string]interface{}{"m.maxbr": 48000},
				}},
			}},
		}},
	}
	_, err := m.client.SendStateEvent(m.ctx, roomID, matrixCallMemberStateType, m.userID.String(), content)
	return err
}

// handleGroupMemberEvent stores a participant's membership (the mesh
// diff consumes it next slice); expired devices are filtered at READ
// time via liveDevices, per spec.
func (m *MatrixCore) handleGroupMemberEvent(evt *event.Event) {
	if evt.StateKey == nil {
		return
	}
	var content matrixCallMemberContent
	if err := json.Unmarshal(evt.Content.VeryRaw, &content); err != nil {
		return
	}
	uid := id.UserID(*evt.StateKey)
	m.groupMu.Lock()
	if m.groupMembers == nil {
		m.groupMembers = make(map[id.UserID]matrixCallMemberContent)
	}
	m.groupMembers[uid] = content
	m.groupMu.Unlock()
}

// ─── mesh decision layer (slice 296) ────────────────────────────────────────
// Pure: which peers get a peer-connection and who offers. The SDP
// fan-out (next slice) consumes these; no socket is touched here.

// groupPeer is one mesh endpoint (device).
type groupPeer struct {
	key    string // "mxid|device"
	UserID id.UserID
	Device string
}

// groupPeerKey is the canonical mesh key for a device.
func groupPeerKey(userID, deviceID string) string {
	return userID + "|" + deviceID
}

// groupShouldOffer: lexicographic tie-break — exactly one side of any
// pair offers, so SDP glare is impossible across the N×(N−1) mesh. A
// device never offers to itself (own == peer → false).
func groupShouldOffer(own, peer string) bool {
	return own < peer
}

// groupPeersToConnect: every LIVE device except our own, sorted by
// key for a deterministic diff. Expiry filtering happens here per
// MSC3401 ("expired devices are ignored") with an injected now.
func groupPeersToConnect(ownUserID id.UserID, ownDevice string, members map[id.UserID]matrixCallMemberContent, now int64) []groupPeer {
	var out []groupPeer
	for uid, content := range members {
		for _, call := range content.Calls {
			for _, d := range call.liveDevices(now) {
				if uid == ownUserID && d.DeviceID == ownDevice {
					continue
				}
				out = append(out, groupPeer{
					key:    groupPeerKey(string(uid), d.DeviceID),
					UserID: uid,
					Device: d.DeviceID,
				})
			}
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].key < out[j].key })
	return out
}

// confIDFromRaw reads the conf_id discriminator (group m.call.* vs the
// 1:1 stack) from raw event content; absent or wrong-typed → "".
func confIDFromRaw(raw map[string]interface{}) string {
	if raw == nil {
		return ""
	}
	if s, ok := raw["conf_id"].(string); ok {
		return s
	}
	return ""
}

// withConfID merges conf_id into marshaled m.call.* content without
// losing any field — the group transport rides the same event names as
// the 1:1 stack, distinguished only by this key.
func withConfID(content interface{}, conf string) (map[string]interface{}, error) {
	raw, err := json.Marshal(content)
	if err != nil {
		return nil, err
	}
	var m map[string]interface{}
	if err := json.Unmarshal(raw, &m); err != nil {
		return nil, err
	}
	m["conf_id"] = conf
	return m, nil
}
