package tests

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
	. "uniclient/cores"

	"github.com/pion/webrtc/v4"
	"maunium.net/go/mautrix"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"uniclient/wrtc"
)

type meshPut struct {
	Kind string
	Type string
	Body string
}

type meshPuts struct {
	mu   sync.Mutex
	list []meshPut
}

func (p *meshPuts) append(x meshPut) {
	p.mu.Lock()
	p.list = append(p.list, x)
	p.mu.Unlock()
}

func (p *meshPuts) snapshot() []meshPut {
	p.mu.Lock()
	defer p.mu.Unlock()
	out := make([]meshPut, len(p.list))
	copy(out, p.list)
	return out
}

type meshServer struct {
	*httptest.Server
	puts      *meshPuts
	mu        sync.Mutex
	roomState string
	callConf  string
}

func (s *meshServer) setRoomState(state string) {
	s.mu.Lock()
	s.roomState = state
	s.mu.Unlock()
}

func (s *meshServer) setCallConf(conf string) {
	s.mu.Lock()
	s.callConf = conf
	s.mu.Unlock()
}

func newMeshHomeserver(t *testing.T) (*meshServer, *meshPuts) {
	t.Helper()
	puts := &meshPuts{}
	mesh := &meshServer{puts: puts}
	mesh.Server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		p := r.URL.Path
		switch {
		case strings.HasSuffix(p, "/state") && r.Method == http.MethodGet:
			mesh.mu.Lock()
			state := mesh.roomState
			mesh.mu.Unlock()
			w.Header().Set("Content-Type", "application/json")
			if state == "" {
				w.WriteHeader(http.StatusNotFound)
				_, _ = io.WriteString(w, `{"errcode":"M_NOT_FOUND"}`)
				return
			}
			_, _ = io.WriteString(w, state)
		case strings.Contains(p, "/state/") && r.Method == http.MethodGet:
			idx := strings.Index(p, "/state/")
			evType := strings.SplitN(p[idx+len("/state/"):], "/", 2)[0]
			mesh.mu.Lock()
			conf := mesh.callConf
			mesh.mu.Unlock()
			if evType == MatrixCallEventType && conf != "" {
				w.Header().Set("Content-Type", "application/json")
				_, _ = io.WriteString(w, `{"m.call_id":"`+conf+`"}`)
				return
			}
			w.WriteHeader(http.StatusNotFound)
			_, _ = io.WriteString(w, `{"errcode":"M_NOT_FOUND"}`)
		case strings.Contains(p, "/state/") && r.Method == http.MethodPut:
			idx := strings.Index(p, "/state/")
			parts := strings.SplitN(p[idx+len("/state/"):], "/", 2)
			puts.append(meshPut{Kind: "state", Type: parts[0], Body: readBody(r)})
			writeEventID(w)
		case strings.Contains(p, "/send/") && r.Method == http.MethodPut:
			idx := strings.Index(p, "/send/")
			parts := strings.SplitN(p[idx+len("/send/"):], "/", 2)
			puts.append(meshPut{Kind: "send", Type: parts[0], Body: readBody(r)})
			writeEventID(w)
		case strings.HasSuffix(p, "/leave") && r.Method == http.MethodPost:
			puts.append(meshPut{Kind: "leave", Type: "leave", Body: readBody(r)})
			w.Header().Set("Content-Type", "application/json")
			_, _ = io.WriteString(w, `{}`)
		case strings.HasSuffix(p, "/logout") && r.Method == http.MethodPost:
			puts.append(meshPut{Kind: "logout", Type: "logout", Body: readBody(r)})
			w.Header().Set("Content-Type", "application/json")
			_, _ = io.WriteString(w, `{}`)
		default:
			w.WriteHeader(http.StatusNotFound)
			_, _ = io.WriteString(w, `{"errcode":"M_NOT_FOUND"}`)
		}
	}))
	t.Cleanup(mesh.Close)
	return mesh, puts
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
	core := ForTestNewMatrixCore(true, func() {}, client, context.Background(), "DEV1", srvURL, id.UserID("@alice:test"))
	t.Cleanup(func() {
		core.ForTestGroupMu().Lock()
		peers := core.ForTestGroupPeers()
		core.ForTestSetGroupPeers(nil)
		if core.ForTestGroupRenew() != nil {
			core.ForTestGroupRenew()
		}
		core.ForTestGroupMu().Unlock()
		for _, p := range peers {
			if p != nil && p.ForTestPc() != nil {
				p.ForTestPc().Close()
			}
		}
	})
	return core
}

func makeOfferSDP(t *testing.T, m *MatrixCore) string {
	t.Helper()
	pc, err := m.CreatePeerConnection()
	if err != nil {
		t.Fatalf("CreatePeerConnection: %v", err)
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

func wrtcNewOpusTrack() (*wrtc.TrackLocalStaticRTP, error) {
	return wrtc.NewTrackLocalStaticRTP(
		webrtc.RTPCodecCapability{MimeType: webrtc.MimeTypeOpus, ClockRate: 48000, Channels: 2},
		"audio", "uniclient-audio",
	)
}

func fireGroupMemberEvent(t *testing.T, core *MatrixCore, uid string, content MatrixCallMemberContent) {
	t.Helper()
	raw, err := json.Marshal(content)
	if err != nil {
		t.Fatalf("marshal member content: %v", err)
	}
	sk := uid
	core.HandleGroupMemberEvent(&event.Event{
		Type:     MatrixCallMemberStateType,
		RoomID:   id.RoomID("!room:test"),
		Sender:   id.UserID(uid),
		StateKey: &sk,
		Content:  event.Content{VeryRaw: raw},
	})
}

func seededMeshCore(t *testing.T, srv *meshServer) *MatrixCore {
	t.Helper()
	core := newMeshTestCore(t, srv.URL)
	fireGroupMemberEvent(t, core, "@bob:test", MatrixCallMemberContent{Calls: []MatrixCallMemberCall{{
		CallID: "conf_x",
		Devices: []MatrixCallDevice{{
			DeviceID: "BOB1", SessionID: "bs",
			ExpiresTS: time.Now().UnixMilli() + 60_000,
		}},
	}}})
	srv.setCallConf("conf_x")
	sess, err := core.JoinGroupCall("!room:test")
	if err != nil {
		t.Fatalf("join group call: %v", err)
	}
	if sess.ID != "conf_x" {
		t.Fatalf("conf = %q, want conf_x (adopted from server call state)", sess.ID)
	}
	return core
}

func TestGroupReconcileSendsConfTaggedOffer(t *testing.T) {
	srv, puts := newMeshHomeserver(t)
	core := seededMeshCore(t, srv)

	if err := core.ReconcileGroupMesh(); err != nil {
		t.Fatalf("reconcile: %v", err)
	}

	core.ForTestGroupMu().Lock()
	peer := core.ForTestGroupPeers()[GroupPeerKey("@bob:test", "BOB1")]
	core.ForTestGroupMu().Unlock()
	if peer == nil || peer.ForTestPc() == nil {
		t.Fatal("peer not registered after reconcile")
	}

	var invite meshPut
	for _, p := range puts.snapshot() {
		if p.Kind == "send" && p.Type == event.CallInvite.Type {
			invite = p
		}
	}
	if invite.Body == "" {
		t.Fatalf("no conf-tagged invite sent; puts=%+v", puts.snapshot())
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

func TestGroupIncomingInviteRoutesToMesh(t *testing.T) {
	srv, puts := newMeshHomeserver(t)
	core := seededMeshCore(t, srv)
	sdp := makeOfferSDP(t, core)

	raw := `{"call_id":"conf_x","version":"1","party_id":"BOB1","conf_id":"conf_x",` +
		`"offer":{"type":"offer","sdp":` + strconv.Quote(sdp) + `}}`
	evt := &event.Event{
		Type:    event.CallInvite,
		RoomID:  id.RoomID("!room:test"),
		Sender:  id.UserID("@bob:test"),
		Content: event.Content{VeryRaw: json.RawMessage(raw)},
	}

	core.HandleCallInvite(evt)

	core.ForTestGroupMu().Lock()
	peer := core.ForTestGroupPeers()[GroupPeerKey("@bob:test", "BOB1")]
	core.ForTestGroupMu().Unlock()
	if peer == nil {
		t.Fatalf("group invite not routed to mesh; peers=%+v", core.ForTestGroupPeers())
	}
	core.ForTestCallsMu().RLock()
	_, in1x1 := core.ForTestActiveCalls()["conf_x"]
	core.ForTestCallsMu().RUnlock()
	if in1x1 {
		t.Fatal("group invite leaked into the 1:1 activeCalls table")
	}

	deadline := time.Now().Add(8 * time.Second)
	for time.Now().Before(deadline) {
		for _, p := range puts.snapshot() {
			p := p
			if p.Kind == "send" && p.Type == event.CallAnswer.Type && strings.Contains(p.Body, `"conf_id":"conf_x"`) {
				return
			}
		}
		time.Sleep(50 * time.Millisecond)
	}
	t.Fatalf("no conf-tagged answer observed; puts=%+v", puts.snapshot())
}

func TestGroupIncomingInviteWrongConfIgnored(t *testing.T) {
	srv, _ := newMeshHomeserver(t)
	core := seededMeshCore(t, srv)
	sdp := makeOfferSDP(t, core)

	raw := `{"call_id":"conf_other","version":"1","party_id":"BOB1","conf_id":"conf_other",` +
		`"offer":{"type":"offer","sdp":` + strconv.Quote(sdp) + `}}`
	evt := &event.Event{
		Type:    event.CallInvite,
		RoomID:  id.RoomID("!room:test"),
		Sender:  id.UserID("@bob:test"),
		Content: event.Content{VeryRaw: json.RawMessage(raw)},
	}

	core.HandleCallInvite(evt)

	core.ForTestGroupMu().Lock()
	n := len(core.ForTestGroupPeers())
	core.ForTestGroupMu().Unlock()
	if n != 0 {
		t.Fatalf("foreign conf accepted: %d peers", n)
	}
}

func TestSendICECandidatesConfTagged(t *testing.T) {
	srv, puts := newMeshHomeserver(t)
	core := seededMeshCore(t, srv)

	mid := "0"
	idx := uint16(0)
	if err := core.ReconcileGroupMesh(); err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	core.ForTestGroupMu().Lock()
	call := core.ForTestGroupPeers()[GroupPeerKey("@bob:test", "BOB1")]
	core.ForTestGroupMu().Unlock()
	if call == nil {
		t.Fatal("setup: bob peer not created by reconcile")
	}
	core.SendICECandidates(call, []webrtc.ICECandidateInit{{
		Candidate:     "candidate:1 1 UDP 2122252543 192.0.2.1 3478 typ host generation 0",
		SDPMid:        &mid,
		SDPMLineIndex: &idx,
	}})

	found := false
	for _, p := range puts.snapshot() {
		if p.Kind == "send" && p.Type == event.CallCandidates.Type {
			if !strings.Contains(p.Body, `"conf_id":"conf_x"`) {
				t.Fatalf("candidates not conf-tagged: %s", p.Body)
			}
			found = true
		}
	}
	if !found {
		t.Fatalf("no candidates event sent; puts=%+v (mid=%s)", puts.snapshot(), mid)
	}
}

func TestGroupReconcileRemovesDepartedPeers(t *testing.T) {
	srv, _ := newMeshHomeserver(t)
	core := seededMeshCore(t, srv)

	if err := core.ReconcileGroupMesh(); err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	core.ForTestGroupMu().Lock()
	live := len(core.ForTestGroupPeers())
	core.ForTestGroupMu().Unlock()
	if live != 1 {
		t.Fatalf("setup: want 1 live bob peer, got %d", live)
	}

	fireGroupMemberEvent(t, core, "@bob:test", MatrixCallMemberContent{Calls: []MatrixCallMemberCall{{
		CallID:  "conf_x",
		Devices: []MatrixCallDevice{{DeviceID: "BOB1", ExpiresTS: time.Now().UnixMilli() - 1}},
	}}})

	if err := core.ReconcileGroupMesh(); err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	core.ForTestGroupMu().Lock()
	n := len(core.ForTestGroupPeers())
	core.ForTestGroupMu().Unlock()
	if n != 0 {
		t.Fatalf("departed peer still registered: %d", n)
	}
}
