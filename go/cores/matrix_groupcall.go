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
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"sort"
	"strconv"
	"time"

	"github.com/pion/webrtc/v4"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"uniclient/wrtc"
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
	// MSC3401: the state_key is the member's OWN mxid — auth rules only
	// special-case m.room.member, so once the event type is granted at
	// PL 0 any room member could publish a member event under someone
	// ELSE's state_key. Receivers must check sender == state_key or call
	// membership is spoofable (RED: "spoofed member event stored",
	// slice 300).
	if string(*evt.StateKey) != string(evt.Sender) {
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
	// Membership changed → re-derive the mesh. Best-effort: the next
	// renewal tick reconciles again, so a failed pass self-heals.
	_ = m.reconcileGroupMesh()
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

// ─── mesh transport wiring (slice 297) ───────────────────────────────────────

// peekGroupConf extracts the conf_id discriminator (group m.call.*
// events carry it; the 1:1 stack never does) from the raw event body.
func peekGroupConf(evt *event.Event) string {
	var raw map[string]interface{}
	if err := json.Unmarshal(evt.Content.VeryRaw, &raw); err != nil {
		return ""
	}
	return confIDFromRaw(raw)
}

// dropGroupPeer removes and closes one mesh peer (key = "mxid|device").
func (m *MatrixCore) dropGroupPeer(key string) {
	m.groupMu.Lock()
	call := m.groupPeers[key]
	delete(m.groupPeers, key)
	m.groupMu.Unlock()
	if call != nil {
		m.cleanupCall(call)
	}
}

// reconcileGroupMesh diffs live membership against open peer
// connections: departed/expired devices are closed, missing peers on
// the SHOULD-OFFER side get an offer (the lexicographic rule makes
// exactly one side of every pair connect, so no glare). Membership is
// filtered to OUR conf first — a room may carry several calls.
func (m *MatrixCore) reconcileGroupMesh() error {
	m.groupMu.Lock()
	conf, room := m.groupConfID, m.groupRoomID
	if conf == "" || room == "" {
		m.groupMu.Unlock()
		return nil
	}
	filtered := make(map[id.UserID]matrixCallMemberContent, len(m.groupMembers))
	for uid, content := range m.groupMembers {
		var kept []matrixCallMemberCall
		for _, c := range content.Calls {
			if c.CallID == conf {
				kept = append(kept, c)
			}
		}
		if len(kept) > 0 {
			filtered[uid] = matrixCallMemberContent{Calls: kept}
		}
	}
	now := time.Now().UnixMilli()
	ownKey := groupPeerKey(string(m.userID), m.deviceID.String())
	desired := groupPeersToConnect(m.userID, m.deviceID.String(), filtered, now)
	desiredSet := make(map[string]bool, len(desired))
	for _, p := range desired {
		desiredSet[p.key] = true
	}
	var toClose []*matrixCall
	for key, call := range m.groupPeers {
		if !desiredSet[key] {
			delete(m.groupPeers, key)
			toClose = append(toClose, call)
		}
	}
	var toOffer []groupPeer
	for _, p := range desired {
		if _, open := m.groupPeers[p.key]; open {
			continue
		}
		if groupShouldOffer(ownKey, p.key) {
			toOffer = append(toOffer, p)
		}
	}
	m.groupMu.Unlock()

	for _, c := range toClose {
		m.cleanupCall(c)
	}
	var firstErr error
	for _, p := range toOffer {
		if err := m.sendGroupOffer(room, conf, p); err != nil && firstErr == nil {
			firstErr = err
		}
	}
	return firstErr
}

// sendGroupOffer creates the OFFER side of one mesh link: pion PC +
// opus track, conf-tagged m.call.invite with a real SDP, peer
// registered BEFORE the invite goes out so a fast answer cannot race
// the store.
func (m *MatrixCore) sendGroupOffer(room id.RoomID, conf string, peer groupPeer) error {
	pc, err := m.createPeerConnection()
	if err != nil {
		return fmt.Errorf("group offer pc: %w", err)
	}
	callCtx, callCancel := context.WithCancel(m.ctx)
	track, err := wrtc.NewTrackLocalStaticRTP(
		webrtc.RTPCodecCapability{MimeType: webrtc.MimeTypeOpus, ClockRate: 48000, Channels: 2},
		"audio", "uniclient-audio",
	)
	if err != nil {
		pc.Close()
		callCancel()
		return fmt.Errorf("group offer track: %w", err)
	}
	if _, err := pc.AddTrack(track); err != nil {
		pc.Close()
		callCancel()
		return fmt.Errorf("group offer add track: %w", err)
	}
	call := &matrixCall{
		ID: conf, RoomID: room, GroupConf: conf,
		RemoteParty: peer.Device, GroupSender: peer.UserID,
		State:     CallStateConnecting,
		StartTime: time.Now(), IsOutgoing: true,
		pc: pc, audioTrack: track, cancel: callCancel,
	}
	call.audioSink = func(b []byte) { m.emitGroupVoice(string(peer.UserID), b) }

	m.groupMu.Lock()
	if m.groupPeers == nil {
		m.groupPeers = make(map[string]*matrixCall)
	}
	if _, open := m.groupPeers[peer.key]; open {
		m.groupMu.Unlock()
		pc.Close()
		callCancel()
		return nil
	}
	m.groupPeers[peer.key] = call
	m.groupMu.Unlock()

	pc.OnICECandidate(func(c *webrtc.ICECandidate) {
		if c == nil {
			return
		}
		m.sendICECandidates(call, []webrtc.ICECandidateInit{c.ToJSON()})
	})
	pc.OnTrack(func(t *wrtc.TrackRemote, _ *webrtc.RTPReceiver) {
		m.handleIncomingAudio(callCtx, call, t)
	})

	offer, err := pc.CreateOffer(nil)
	if err != nil {
		m.dropGroupPeer(peer.key)
		return fmt.Errorf("group offer sdp: %w", err)
	}
	if err := pc.SetLocalDescription(offer); err != nil {
		m.dropGroupPeer(peer.key)
		return fmt.Errorf("group offer local: %w", err)
	}
	gatherDone := wrtc.GatheringCompletePromise(pc)
	select {
	case <-gatherDone:
	case <-time.After(5 * time.Second):
	}

	// Group frames are DRIVEN by SendVoiceFrame — the 1:1 silence loop
	// would interleave and drown them (slice-298 decision).
	invite := &event.CallInviteEventContent{
		BaseCallEventContent: event.BaseCallEventContent{
			CallID:  conf,
			Version: "1",
			PartyID: m.deviceID.String(),
		},
		Lifetime: int(matrixDeviceTTLMillis),
		Offer: event.CallData{
			Type: event.CallDataTypeOffer,
			SDP:  pc.LocalDescription().SDP,
		},
	}
	payload, err := withConfID(invite, conf)
	if err != nil {
		m.dropGroupPeer(peer.key)
		return fmt.Errorf("conf-tag invite: %w", err)
	}
	if _, err := m.client.SendMessageEvent(m.ctx, room, event.CallInvite, payload); err != nil {
		m.dropGroupPeer(peer.key)
		return fmt.Errorf("send group invite: %w", err)
	}
	return nil
}

// handleGroupCallInvite is the ANSWER side: auto-accept (group calls
// have no ringing UI), register the peer before answering so the
// reply path resolves, answer conf-tagged.
func (m *MatrixCore) handleGroupCallInvite(evt *event.Event, ci *event.CallInviteEventContent, conf string) {
	m.groupMu.Lock()
	if conf != m.groupConfID || m.groupConfID == "" {
		m.groupMu.Unlock()
		return // foreign conf or not joined
	}
	peerKey := groupPeerKey(string(evt.Sender), ci.PartyID)
	if _, exists := m.groupPeers[peerKey]; exists {
		m.groupMu.Unlock()
		return
	}
	if m.groupPeers == nil {
		m.groupPeers = make(map[string]*matrixCall)
	}
	m.groupMu.Unlock()

	pc, err := m.createPeerConnection()
	if err != nil {
		return
	}
	callCtx, callCancel := context.WithCancel(m.ctx)
	track, err := wrtc.NewTrackLocalStaticRTP(
		webrtc.RTPCodecCapability{MimeType: webrtc.MimeTypeOpus, ClockRate: 48000, Channels: 2},
		"audio", "uniclient-audio",
	)
	if err != nil {
		pc.Close()
		callCancel()
		return
	}
	if _, err := pc.AddTrack(track); err != nil {
		pc.Close()
		callCancel()
		return
	}
	call := &matrixCall{
		ID: conf, RoomID: evt.RoomID, GroupConf: conf,
		RemoteParty: ci.PartyID, GroupSender: evt.Sender,
		State:     CallStateConnecting,
		StartTime: time.Now(),
		pc:        pc, audioTrack: track, cancel: callCancel,
	}
	call.audioSink = func(b []byte) { m.emitGroupVoice(string(evt.Sender), b) }
	m.groupMu.Lock()
	m.groupPeers[peerKey] = call
	m.groupMu.Unlock()

	pc.OnICECandidate(func(c *webrtc.ICECandidate) {
		if c == nil {
			return
		}
		m.sendICECandidates(call, []webrtc.ICECandidateInit{c.ToJSON()})
	})
	pc.OnTrack(func(t *wrtc.TrackRemote, _ *webrtc.RTPReceiver) {
		m.handleIncomingAudio(callCtx, call, t)
	})

	if ci.Offer.SDP != "" {
		if err := pc.SetRemoteDescription(webrtc.SessionDescription{
			Type: webrtc.SDPTypeOffer,
			SDP:  ci.Offer.SDP,
		}); err != nil {
			m.dropGroupPeer(peerKey)
			return
		}
		m.flushPendingCandidates(call)
	}

	answer, err := pc.CreateAnswer(nil)
	if err != nil {
		m.dropGroupPeer(peerKey)
		return
	}
	if err := pc.SetLocalDescription(answer); err != nil {
		m.dropGroupPeer(peerKey)
		return
	}
	gatherDone := wrtc.GatheringCompletePromise(pc)
	select {
	case <-gatherDone:
	case <-time.After(5 * time.Second):
	}

	answerContent := &event.CallAnswerEventContent{
		BaseCallEventContent: event.BaseCallEventContent{
			CallID:  conf,
			Version: "1",
			PartyID: m.deviceID.String(),
		},
		Answer: event.CallData{
			Type: event.CallDataTypeAnswer,
			SDP:  pc.LocalDescription().SDP,
		},
	}
	payload, err := withConfID(answerContent, conf)
	if err == nil {
		if _, sendErr := m.client.SendMessageEvent(m.ctx, call.RoomID, event.CallAnswer, payload); sendErr != nil {
			m.dropGroupPeer(peerKey)
			return
		}
	}

	m.fireUpdate(Update{
		Type:   UpdateCallState,
		ChatID: call.RoomID.String(),
		Call: &CallSession{
			ID: conf, ChatID: call.RoomID.String(), IsGroup: true,
			State: CallStateConnecting,
		},
		Platform: mxPlatform,
	})
}

// ─── VoiceCore surface for the mesh (slice 298) ─────────────────────────────
// The engine's startVoiceRunner type-asserts cores.VoiceCore and drives
// the shared pipeline: mic frames in via SendVoiceFrame (fan-out to
// every mesh peer), remote Opus out via OnVoiceFrame (sender-tagged).

// OnVoiceFrame registers the receiver for remote group voice.
func (m *MatrixCore) OnVoiceFrame(handler func(sender string, opus []byte)) {
	m.groupMu.Lock()
	m.groupVoiceHandler = handler
	m.groupMu.Unlock()
}

// SetVoiceMuted toggles client-side self-mute for the group call
// (matrix has no server-side mute for our own feed — we simply stop
// writing to the mesh).
func (m *MatrixCore) SetVoiceMuted(muted bool) error {
	m.groupMu.Lock()
	m.groupVoiceMuted = muted
	m.groupMu.Unlock()
	return nil
}

// SendVoiceFrame writes one 20 ms Opus packet to EVERY live mesh peer.
func (m *MatrixCore) SendVoiceFrame(opus []byte) error {
	m.groupMu.Lock()
	muted := m.groupVoiceMuted
	peers := make([]*matrixCall, 0, len(m.groupPeers))
	for _, c := range m.groupPeers {
		peers = append(peers, c)
	}
	m.groupMu.Unlock()
	if muted || len(opus) == 0 {
		return nil
	}
	for _, c := range peers {
		m.writeGroupRTP(c, opus)
	}
	return nil
}

// writeGroupRTP packetizes one Opus frame with per-peer RTP counters
// (same header shape as the 1:1 sendAudio loop: PT 111, zero SSRC).
func (m *MatrixCore) writeGroupRTP(call *matrixCall, frame []byte) {
	if call == nil || call.audioTrack == nil {
		return
	}
	call.mu.Lock()
	call.gseq++
	call.gts += 960
	seq, ts := call.gseq, call.gts
	call.mu.Unlock()

	header := make([]byte, 12)
	header[0] = 0x80
	header[1] = 111
	header[2] = byte(seq >> 8)
	header[3] = byte(seq)
	header[4] = byte(ts >> 24)
	header[5] = byte(ts >> 16)
	header[6] = byte(ts >> 8)
	header[7] = byte(ts)
	pkt := make([]byte, 0, 12+len(frame))
	pkt = append(pkt, header...)
	pkt = append(pkt, frame...)
	_, _ = call.audioTrack.Write(pkt)
}

// emitGroupVoice hands one received Opus frame to the engine handler.
func (m *MatrixCore) emitGroupVoice(sender string, payload []byte) {
	m.groupMu.Lock()
	h := m.groupVoiceHandler
	m.groupMu.Unlock()
	if h != nil {
		h(sender, payload)
	}
}

// GetGroupCall is the engine's groupCaller contract: joined → an
// ACTIVE IsGroup session with live participants (one entry per user,
// expired devices filtered, conf-scoped); not joined or another room
// → (nil, nil) so the engine reports "no active call".
func (m *MatrixCore) GetGroupCall(chatID string) (*CallSession, error) {
	if !m.authed {
		return nil, ErrAuth
	}
	m.groupMu.Lock()
	defer m.groupMu.Unlock()
	if m.groupConfID == "" || string(m.groupRoomID) != chatID {
		return nil, nil
	}
	conf := m.groupConfID
	now := time.Now().UnixMilli()
	seen := make(map[id.UserID]bool)
	var participants []CallParticipant
	for uid, content := range m.groupMembers {
		if seen[uid] {
			continue
		}
		for _, call := range content.Calls {
			if call.CallID != conf {
				continue
			}
			if len(call.liveDevices(now)) == 0 {
				continue
			}
			seen[uid] = true
			participants = append(participants, CallParticipant{UserID: string(uid)})
			break
		}
	}
	return &CallSession{
		ID:           conf,
		ChatID:       chatID,
		IsGroup:      true,
		State:        CallStateActive,
		Participants: participants,
		Meta:         map[string]string{"participants_count": strconv.Itoa(len(participants))},
	}, nil
}
