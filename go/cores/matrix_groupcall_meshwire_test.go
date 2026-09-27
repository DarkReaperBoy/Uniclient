package cores

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/pion/webrtc/v4"
	"maunium.net/go/mautrix"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"uniclient/wrtc"
)

// B-6 → F-62, slice 297: conf-tagged transport over room events.
// Seam-RED (WORKLOG 297): undefined: reconcileGroupMesh.

type meshPut struct {
	Kind string // "state" or "send"
	Type string
	Body string
}

// newMeshHomeserver captures BOTH state and message event PUTs.
func newMeshHomeserver(t *testing.T) (*httptest.Server, *[]meshPut) {
	t.Helper()
	var puts []meshPut
	var mu sync.Mutex
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		p := r.URL.Path
		switch {
		case strings.Contains(p, "/state/") && r.Method == http.MethodPut:
			idx := strings.Index(p, "/state/")
			parts := strings.SplitN(p[idx+len("/state/"):], "/", 2)
			mu.Lock()
			puts = append(puts, meshPut{Kind: "state", Type: parts[0], Body: readBody(r)})
			mu.Unlock()
			writeEventID(w)
		case strings.Contains(p, "/send/") && r.Method == http.MethodPut:
			idx := strings.Index(p, "/send/")
			parts := strings.SplitN(p[idx+len("/send/"):], "/", 2)
			mu.Lock()
			puts = append(puts, meshPut{Kind: "send", Type: parts[0], Body: readBody(r)})
			mu.Unlock()
			writeEventID(w)
		default:
			w.WriteHeader(http.StatusNotFound)
			_, _ = io.WriteString(w, `{"errcode":"M_NOT_FOUND"}`)
		}
	}))
	t.Cleanup(srv.Close)
	return srv, &puts
}

func readBody(r *http.Request) string { b, _ := io.ReadAll(r.Body); return string(b) }
func writeEventID(w http.ResponseWriter) {
	w.Header().Set("Content-Type", "application/json")
	_, _ = io.WriteString(w, `{"event_id":"$ev"}`)
}

func newMeshTestCore(t *testing.T, srvURL string) *MatrixCore {
	t.Helper()
	client, err := mautrix.NewClient(srvURL, id.UserID("@alice:test"), "tok")
	if err != nil {
		t.Fatalf("NewClient: %v", err)
	}
	core := &MatrixCore{
		authed:     true,
		ctx:        context.Background(),
		deviceID:   "DEV1",
		userID:     id.UserID("@alice:test"),
		homeserver: srvURL,
		client:     client,
	}
	t.Cleanup(func() {
		core.groupMu.Lock()
		peers := core.groupPeers
		core.groupPeers = nil
		if core.groupRenew != nil {
			core.groupRenew()
		}
		core.groupMu.Unlock()
		for _, p := range peers {
			if p != nil && p.pc != nil {
				p.pc.Close()
			}
		}
	})
	return core
}

// makeOfferSDP builds a REAL offer (pion, no network needed).
func makeOfferSDP(t *testing.T, m *MatrixCore) string {
	t.Helper()
	pc, err := m.createPeerConnection()
	if err != nil {
		t.Fatalf("createPeerConnection: %v", err)
	}
	defer pc.Close()
	track, err := wrtcNewOpusTrack()
	if err != nil {
		t.Fatalf("track: %v", err)
	}
	if _, err := pc.AddTrack(track); err != nil {
		t.Fatalf("AddTrack: %v", err)
	}
	offer, err := pc.CreateOffer(nil)
	if err != nil {
		t.Fatalf("CreateOffer: %v", err)
	}
	return offer.SDP
}

// wrtcNewOpusTrack mirrors the production audio track setup.
func wrtcNewOpusTrack() (*wrtc.TrackLocalStaticRTP, error) {
	return wrtc.NewTrackLocalStaticRTP(
		webrtc.RTPCodecCapability{MimeType: webrtc.MimeTypeOpus, ClockRate: 48000, Channels: 2},
		"audio", "uniclient-audio",
	)
}

func seededMeshCore(t *testing.T, srvURL string) *MatrixCore {
	t.Helper()
	core := newMeshTestCore(t, srvURL)
	core.groupConfID = "conf_x"
	core.groupRoomID = "!room:test"
	core.groupSession = "sess1"
	core.groupMembers = map[id.UserID]matrixCallMemberContent{
		"@bob:test": {Calls: []matrixCallMemberCall{{
			CallID: "conf_x",
			Devices: []matrixCallDevice{{
				DeviceID: "BOB1", SessionID: "bs",
				ExpiresTS: time.Now().UnixMilli() + 60_000,
			}},
		}}},
	}
	return core
}

// TestGroupReconcileSendsConfTaggedOffer: the offer side must emit a
// conf_id-tagged m.call.invite carrying a real SDP offer, and register
// the peer — the mesh's "who connects" decision on the wire.
func TestGroupReconcileSendsConfTaggedOffer(t *testing.T) {
	srv, puts := newMeshHomeserver(t)
	core := seededMeshCore(t, srv.URL)

	if err := core.reconcileGroupMesh(); err != nil {
		t.Fatalf("reconcile: %v", err)
	}

	core.groupMu.Lock()
	peer := core.groupPeers[groupPeerKey("@bob:test", "BOB1")]
	core.groupMu.Unlock()
	if peer == nil || peer.pc == nil {
		t.Fatal("peer not registered after reconcile")
	}

	var invite *meshPut
	for i := range *puts {
		if (*puts)[i].Kind == "send" && (*puts)[i].Type == event.CallInvite.Type {
			invite = &(*puts)[i]
		}
	}
	if invite == nil {
		t.Fatalf("no conf-tagged invite sent; puts=%+v", *puts)
	}
	var body struct {
		ConfID string `json:"conf_id"`
		CallID string `json:"call_id"`
		Party  string `json:"party_id"`
		Offer  struct {
			Type string `json:"type"`
			SDP  string `json:"sdp"`
		} `json:"offer"`
	}
	if err := json.Unmarshal([]byte(invite.Body), &body); err != nil {
		t.Fatalf("invite body %q: %v", invite.Body, err)
	}
	if body.ConfID != "conf_x" {
		t.Fatalf("conf_id = %q, want conf_x", body.ConfID)
	}
	if body.Party != "DEV1" {
		t.Fatalf("party_id = %q, want DEV1", body.Party)
	}
	if body.Offer.Type != "offer" || !strings.HasPrefix(body.Offer.SDP, "v=0") {
		t.Fatalf("offer = %+v, want real SDP", body.Offer)
	}
}

// TestGroupIncomingInviteRoutesToMesh: a conf-tagged invite from our
// conf must register the peer (and answer asynchronously); it must NOT
// leak into the 1:1 activeCalls table.
func TestGroupIncomingInviteRoutesToMesh(t *testing.T) {
	srv, puts := newMeshHomeserver(t)
	core := seededMeshCore(t, srv.URL)
	sdp := makeOfferSDP(t, core)

	raw := `{"call_id":"conf_x","version":"1","party_id":"BOB1","conf_id":"conf_x",` +
		`"offer":{"type":"offer","sdp":` + strconv.Quote(sdp) + `}}`
	evt := &event.Event{
		Type:    event.CallInvite,
		RoomID:  id.RoomID("!room:test"),
		Sender:  id.UserID("@bob:test"),
		Content: event.Content{VeryRaw: json.RawMessage(raw)},
	}

	core.handleCallInvite(evt)

	core.groupMu.Lock()
	peer := core.groupPeers[groupPeerKey("@bob:test", "BOB1")]
	core.groupMu.Unlock()
	if peer == nil {
		t.Fatalf("group invite not routed to mesh; peers=%+v", core.groupPeers)
	}
	core.callsMu.RLock()
	_, in1x1 := core.activeCalls["conf_x"]
	core.callsMu.RUnlock()
	if in1x1 {
		t.Fatal("group invite leaked into the 1:1 activeCalls table")
	}

	// The answer (auto-accept) must go out conf-tagged.
	deadline := time.Now().Add(8 * time.Second)
	for time.Now().Before(deadline) {
		for i := range *puts {
			p := (*puts)[i]
			if p.Kind == "send" && p.Type == event.CallAnswer.Type && strings.Contains(p.Body, `"conf_id":"conf_x"`) {
				return // GREEN
			}
		}
		time.Sleep(50 * time.Millisecond)
	}
	t.Fatalf("no conf-tagged answer observed; puts=%+v", *puts)
}

// TestGroupIncomingInviteWrongConfIgnored: another room's call must be
// dropped, not joined.
func TestGroupIncomingInviteWrongConfIgnored(t *testing.T) {
	srv, _ := newMeshHomeserver(t)
	core := seededMeshCore(t, srv.URL)
	sdp := makeOfferSDP(t, core)

	raw := `{"call_id":"conf_other","version":"1","party_id":"BOB1","conf_id":"conf_other",` +
		`"offer":{"type":"offer","sdp":` + strconv.Quote(sdp) + `}}`
	evt := &event.Event{
		Type:    event.CallInvite,
		RoomID:  id.RoomID("!room:test"),
		Sender:  id.UserID("@bob:test"),
		Content: event.Content{VeryRaw: json.RawMessage(raw)},
	}

	core.handleCallInvite(evt)

	core.groupMu.Lock()
	n := len(core.groupPeers)
	core.groupMu.Unlock()
	if n != 0 {
		t.Fatalf("foreign conf accepted: %d peers", n)
	}
}

// TestSendICECandidatesConfTagged: the 1:1 candidates sender must tag
// candidates when the call carries a conf.
func TestSendICECandidatesConfTagged(t *testing.T) {
	srv, puts := newMeshHomeserver(t)
	core := seededMeshCore(t, srv.URL)

	mid := "0"
	idx := uint16(0)
	call := &matrixCall{ID: "conf_x", RoomID: id.RoomID("!room:test"), GroupConf: "conf_x"}
	core.sendICECandidates(call, []webrtc.ICECandidateInit{{
		Candidate:     "candidate:1 1 UDP 2122252543 192.0.2.1 3478 typ host generation 0",
		SDPMid:        &mid,
		SDPMLineIndex: &idx,
	}})

	found := false
	for i := range *puts {
		p := (*puts)[i]
		if p.Kind == "send" && p.Type == event.CallCandidates.Type {
			if !strings.Contains(p.Body, `"conf_id":"conf_x"`) {
				t.Fatalf("candidates not conf-tagged: %s", p.Body)
			}
			found = true
		}
	}
	if !found {
		t.Fatalf("no candidates event sent; puts=%+v (mid=%s)", *puts, mid)
	}
}

// TestGroupReconcileRemovesDepartedPeers: when membership no longer
// lists a live device, its peer connection is closed and dropped.
func TestGroupReconcileRemovesDepartedPeers(t *testing.T) {
	srv, _ := newMeshHomeserver(t)
	core := seededMeshCore(t, srv.URL)

	// Register a peer as if it existed.
	pc, err := core.createPeerConnection()
	if err != nil {
		t.Fatalf("pc: %v", err)
	}
	key := groupPeerKey("@bob:test", "BOB1")
	core.groupMu.Lock()
	core.groupPeers = map[string]*matrixCall{key: {ID: "conf_x", RoomID: id.RoomID("!room:test"), pc: pc}}
	core.groupMu.Unlock()

	// Bob leaves (expired membership).
	core.groupMembers["@bob:test"] = matrixCallMemberContent{Calls: []matrixCallMemberCall{{
		CallID:  "conf_x",
		Devices: []matrixCallDevice{{DeviceID: "BOB1", ExpiresTS: time.Now().UnixMilli() - 1}},
	}}}

	if err := core.reconcileGroupMesh(); err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	core.groupMu.Lock()
	n := len(core.groupPeers)
	core.groupMu.Unlock()
	if n != 0 {
		t.Fatalf("departed peer still registered: %d", n)
	}
}
