package cores

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
	MatrixCallMemberEventType = "org.matrix.msc3401.call.member"
	MatrixCallEventType       = "org.matrix.msc3401.call"

	MatrixDeviceTTLMillis int64 = 60_000

	MatrixFeedUserMedia = "m.usermedia"
)

type MatrixCallFeed struct {
	Purpose  string                 `json:"purpose"`
	StreamID string                 `json:"stream_id,omitempty"`
	TrackID  string                 `json:"track_id,omitempty"`
	Settings map[string]interface{} `json:"settings,omitempty"`
}

type MatrixCallDevice struct {
	DeviceID  string           `json:"device_id"`
	SessionID string           `json:"session_id"`
	ExpiresTS int64            `json:"expires_ts"`
	Feeds     []MatrixCallFeed `json:"feeds,omitempty"`
}

type MatrixCallMemberCall struct {
	CallID  string             `json:"m.call_id"`
	Foci    []string           `json:"m.foci"`
	Devices []MatrixCallDevice `json:"m.devices"`
}

type MatrixCallMemberContent struct {
	Calls []MatrixCallMemberCall `json:"m.calls"`
}

func (c MatrixCallMemberCall) LiveDevices(now int64) []MatrixCallDevice {
	var out []MatrixCallDevice
	for _, d := range c.Devices {
		if d.ExpiresTS > now {
			out = append(out, d)
		}
	}
	return out
}

func MatrixNextRenewalAt(now int64) int64 {
	return now + MatrixDeviceTTLMillis/2
}

func MatrixNewConfID() string {
	var b [8]byte
	if _, err := rand.Read(b[:]); err != nil {
		return "conf_" + hex.EncodeToString([]byte(time.Now().UTC().Format("150405.000000000")))
	}
	return "conf_" + hex.EncodeToString(b[:])
}

var (
	MatrixCallMemberStateType = event.Type{Type: MatrixCallMemberEventType, Class: event.StateEventType}
	matrixCallStateType       = event.Type{Type: MatrixCallEventType, Class: event.StateEventType}
)

func matrixNewSessionID() string {
	var b [8]byte
	if _, err := rand.Read(b[:]); err != nil {
		return "gs-" + time.Now().UTC().Format("20060102150405.000000000")
	}
	return "gs-" + hex.EncodeToString(b[:])
}

func (m *MatrixCore) publishGroupMembership(roomID id.RoomID, conf, sess string, now int64) error {
	content := MatrixCallMemberContent{
		Calls: []MatrixCallMemberCall{{
			CallID: conf,
			Foci:   []string{},
			Devices: []MatrixCallDevice{{
				DeviceID:  m.deviceID.String(),
				SessionID: sess,
				ExpiresTS: now + MatrixDeviceTTLMillis,
				Feeds: []MatrixCallFeed{{
					Purpose:  MatrixFeedUserMedia,
					StreamID: "ms-" + sess,
					TrackID:  "mt-" + sess,
					Settings: map[string]interface{}{"m.maxbr": 48000},
				}},
			}},
		}},
	}
	_, err := m.client.SendStateEvent(m.ctx, roomID, MatrixCallMemberStateType, m.userID.String(), content)
	return err
}

func (m *MatrixCore) HandleGroupMemberEvent(evt *event.Event) {
	if evt.StateKey == nil {
		return
	}
	if string(*evt.StateKey) != string(evt.Sender) {
		return
	}
	var content MatrixCallMemberContent
	if err := json.Unmarshal(evt.Content.VeryRaw, &content); err != nil {
		return
	}
	uid := id.UserID(*evt.StateKey)
	m.groupMu.Lock()
	if m.groupMembers == nil {
		m.groupMembers = make(map[id.UserID]MatrixCallMemberContent)
	}
	m.groupMembers[uid] = content
	m.groupMu.Unlock()
	_ = m.ReconcileGroupMesh()
}

type groupPeer struct {
	key    string
	UserID id.UserID
	Device string
}

func GroupPeerKey(userID, deviceID string) string {
	return userID + "|" + deviceID
}

func GroupShouldOffer(own, peer string) bool {
	return own < peer
}

func GroupPeersToConnect(ownUserID id.UserID, ownDevice string, members map[id.UserID]MatrixCallMemberContent, now int64) []groupPeer {
	var out []groupPeer
	for uid, content := range members {
		for _, call := range content.Calls {
			for _, d := range call.LiveDevices(now) {
				if uid == ownUserID && d.DeviceID == ownDevice {
					continue
				}
				out = append(out, groupPeer{
					key:    GroupPeerKey(string(uid), d.DeviceID),
					UserID: uid,
					Device: d.DeviceID,
				})
			}
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].key < out[j].key })
	return out
}

func ConfIDFromRaw(raw map[string]interface{}) string {
	if raw == nil {
		return ""
	}
	if s, ok := raw["conf_id"].(string); ok {
		return s
	}
	return ""
}

func WithConfID(content interface{}, conf string) (map[string]interface{}, error) {
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

func peekGroupConf(evt *event.Event) string {
	var raw map[string]interface{}
	if err := json.Unmarshal(evt.Content.VeryRaw, &raw); err != nil {
		return ""
	}
	return ConfIDFromRaw(raw)
}

func (m *MatrixCore) teardownGroupPeer(call *MatrixCall) {
	m.cleanupCall(call)
	m.fireUpdate(Update{
		Type:   UpdateCallState,
		ChatID: call.RoomID.String(),
		Call: &CallSession{
			ID:           call.ID,
			ChatID:       call.RoomID.String(),
			IsGroup:      true,
			State:        CallStateEnded,
			Participants: []CallParticipant{{UserID: call.GroupSender.String()}},
		},
		Platform: MxPlatform,
	})
}

func (m *MatrixCore) dropGroupPeer(key string) {
	m.groupMu.Lock()
	call := m.groupPeers[key]
	delete(m.groupPeers, key)
	m.groupMu.Unlock()
	if call != nil {
		m.teardownGroupPeer(call)
	}
}

func (m *MatrixCore) ReconcileGroupMesh() error {
	joinByRoom := make(map[id.RoomID]map[id.UserID]bool)
	m.roomsMu.RLock()
	for roomID, rs := range m.rooms {
		if rs == nil || len(rs.Members) == 0 {
			continue
		}
		mm := make(map[id.UserID]bool, len(rs.Members))
		for uid, mem := range rs.Members {
			mm[uid] = mem != nil && mem.Membership == event.MembershipJoin
		}
		joinByRoom[roomID] = mm
	}
	m.roomsMu.RUnlock()

	m.groupMu.Lock()
	conf, room := m.groupConfID, m.groupRoomID
	if conf == "" || room == "" {
		m.groupMu.Unlock()
		return nil
	}
	roomJoin := joinByRoom[room]
	filtered := make(map[id.UserID]MatrixCallMemberContent, len(m.groupMembers))
	for uid, content := range m.groupMembers {
		if joined, known := roomJoin[uid]; known && !joined {
			continue
		}
		var kept []MatrixCallMemberCall
		for _, c := range content.Calls {
			if c.CallID == conf {
				kept = append(kept, c)
			}
		}
		if len(kept) > 0 {
			filtered[uid] = MatrixCallMemberContent{Calls: kept}
		}
	}
	now := time.Now().UnixMilli()
	ownKey := GroupPeerKey(string(m.userID), m.deviceID.String())
	desired := GroupPeersToConnect(m.userID, m.deviceID.String(), filtered, now)
	desiredSet := make(map[string]bool, len(desired))
	for _, p := range desired {
		desiredSet[p.key] = true
	}
	var toClose []*MatrixCall
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
		if GroupShouldOffer(ownKey, p.key) {
			toOffer = append(toOffer, p)
		}
	}
	m.groupMu.Unlock()

	for _, c := range toClose {
		m.teardownGroupPeer(c)
	}
	var firstErr error
	for _, p := range toOffer {
		if err := m.sendGroupOffer(room, conf, p); err != nil && firstErr == nil {
			firstErr = err
		}
	}
	return firstErr
}

func (m *MatrixCore) sendGroupOffer(room id.RoomID, conf string, peer groupPeer) error {
	pc, err := m.CreatePeerConnection()
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
	call := &MatrixCall{
		ID: conf, RoomID: room, GroupConf: conf,
		RemoteParty: peer.Device, GroupSender: peer.UserID,
		State:     CallStateConnecting,
		StartTime: time.Now(), IsOutgoing: true,
		pc: pc, audioTrack: track, cancel: callCancel,
	}
	call.audioSink = func(b []byte) { m.emitGroupVoice(string(peer.UserID), b) }

	m.groupMu.Lock()
	if m.groupPeers == nil {
		m.groupPeers = make(map[string]*MatrixCall)
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
		m.SendICECandidates(call, []webrtc.ICECandidateInit{c.ToJSON()})
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

	invite := &event.CallInviteEventContent{
		BaseCallEventContent: event.BaseCallEventContent{
			CallID:  conf,
			Version: "1",
			PartyID: m.deviceID.String(),
		},
		Lifetime: int(MatrixDeviceTTLMillis),
		Offer: event.CallData{
			Type: event.CallDataTypeOffer,
			SDP:  pc.LocalDescription().SDP,
		},
	}
	payload, err := WithConfID(invite, conf)
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

func (m *MatrixCore) handleGroupCallInvite(evt *event.Event, ci *event.CallInviteEventContent, conf string) {
	m.groupMu.Lock()
	if conf != m.groupConfID || m.groupConfID == "" {
		m.groupMu.Unlock()
		return
	}
	peerKey := GroupPeerKey(string(evt.Sender), ci.PartyID)
	if _, exists := m.groupPeers[peerKey]; exists {
		m.groupMu.Unlock()
		return
	}
	if m.groupPeers == nil {
		m.groupPeers = make(map[string]*MatrixCall)
	}
	m.groupMu.Unlock()

	pc, err := m.CreatePeerConnection()
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
	call := &MatrixCall{
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
		m.SendICECandidates(call, []webrtc.ICECandidateInit{c.ToJSON()})
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
	payload, err := WithConfID(answerContent, conf)
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
		Platform: MxPlatform,
	})
}

func (m *MatrixCore) OnVoiceFrame(handler func(sender string, opus []byte)) {
	m.groupMu.Lock()
	m.groupVoiceHandler = handler
	m.groupMu.Unlock()
}

func (m *MatrixCore) SetVoiceMuted(muted bool) error {
	m.groupMu.Lock()
	m.groupVoiceMuted = muted
	m.groupMu.Unlock()
	return nil
}

func (m *MatrixCore) SendVoiceFrame(opus []byte) error {
	m.groupMu.Lock()
	muted := m.groupVoiceMuted
	peers := make([]*MatrixCall, 0, len(m.groupPeers))
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

func (m *MatrixCore) writeGroupRTP(call *MatrixCall, frame []byte) {
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

func (m *MatrixCore) emitGroupVoice(sender string, payload []byte) {
	m.groupMu.Lock()
	h := m.groupVoiceHandler
	m.groupMu.Unlock()
	if h != nil {
		h(sender, payload)
	}
}

func (m *MatrixCore) GetGroupCall(chatID string) (*CallSession, error) {
	if !m.authed {
		return nil, ErrAuth
	}
	joined := make(map[id.UserID]bool)
	m.roomsMu.RLock()
	if rs := m.rooms[id.RoomID(chatID)]; rs != nil {
		for uid, mem := range rs.Members {
			joined[uid] = mem != nil && mem.Membership == event.MembershipJoin
		}
	}
	m.roomsMu.RUnlock()

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
		if j, known := joined[uid]; known && !j {
			continue
		}
		for _, call := range content.Calls {
			if call.CallID != conf {
				continue
			}
			if len(call.LiveDevices(now)) == 0 {
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

func (m *MatrixCore) leaveGroupCallInternal() (id.RoomID, string, error) {
	m.groupMu.Lock()
	room, conf := m.groupRoomID, m.groupConfID
	renew := m.groupRenew
	var peers []*MatrixCall
	for _, c := range m.groupPeers {
		peers = append(peers, c)
	}
	m.groupRenew = nil
	m.groupConfID = ""
	m.groupRoomID = ""
	m.groupMembers = nil
	m.groupPeers = nil
	m.groupMu.Unlock()

	if conf == "" {
		return "", "", nil
	}
	if renew != nil {
		renew()
	}
	for _, c := range peers {
		if c != nil {
			m.teardownGroupPeer(c)
		}
	}

	var pubErr error
	if m.authed && m.client != nil {
		if _, err := m.client.SendStateEvent(m.ctx, room, MatrixCallMemberStateType, m.userID.String(),
			MatrixCallMemberContent{Calls: []MatrixCallMemberCall{}}); err != nil {
			pubErr = fmt.Errorf("publish leave membership: %w", err)
		}
	}

	m.fireUpdate(Update{
		Type:   UpdateCallState,
		ChatID: room.String(),
		Call: &CallSession{
			ID: conf, ChatID: room.String(), IsGroup: true,
			State: CallStateEnded,
		},
		Platform: MxPlatform,
	})
	return room, conf, pubErr
}

var MatrixRenewInterval = time.Duration(MatrixDeviceTTLMillis/2) * time.Millisecond

const matrixRenewMaxConsecutiveFails = 3

func (m *MatrixCore) runGroupRenewal(renewCtx context.Context, roomID id.RoomID, conf, sess string, interval time.Duration) {
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	fails := 0
	for {
		select {
		case <-renewCtx.Done():
			return
		case <-m.ctx.Done():
			return
		case <-ticker.C:
			if err := m.publishGroupMembership(roomID, conf, sess, time.Now().UnixMilli()); err != nil {
				fails++
				if fails >= matrixRenewMaxConsecutiveFails {
					if _, _, pubErr := m.leaveGroupCallInternal(); pubErr != nil {
						_ = pubErr
					}
					return
				}
			} else {
				fails = 0
			}
			_ = m.ReconcileGroupMesh()
		}
	}
}
