package tests

import (
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
	mesh.Server = httptest.NewServer(mxAuthSurface(id.UserID("@alice:test"), id.DeviceID("DEV1"), http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
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
	})))
	t.Cleanup(mesh.Close)
	return mesh, puts
}

func readBody(r *http.Request) string { b, _ := io.ReadAll(r.Body); return string(b) }
func writeEventID(w http.ResponseWriter) {
	w.Header().Set("Content-Type", "application/json")
	_, _ = io.WriteString(w, `{"event_id":"$ev"}`)
}

type updateCapture struct {
	mu   sync.Mutex
	seen []Update
}

func newUpdateCapture(core *MatrixCore) *updateCapture {
	uc := &updateCapture{}
	core.OnUpdate(func(u Update) {
		uc.mu.Lock()
		uc.seen = append(uc.seen, u)
		uc.mu.Unlock()
	})
	return uc
}

func (uc *updateCapture) groupPeerEnded(user string) bool {
	uc.mu.Lock()
	defer uc.mu.Unlock()
	for _, u := range uc.seen {
		if u.Type != UpdateCallState || u.Call == nil || !u.Call.IsGroup {
			continue
		}
		if u.Call.State != CallStateEnded {
			continue
		}
		for _, p := range u.Call.Participants {
			if p.UserID == user {
				return true
			}
		}
	}
	return false
}

const meshRenewInterval = 120 * time.Millisecond

func shortenRenewal(t *testing.T) {
	t.Helper()
	old := MatrixRenewInterval
	MatrixRenewInterval = meshRenewInterval
	t.Cleanup(func() { MatrixRenewInterval = old })
}

func countMembershipPuts(puts *meshPuts) int {
	n := 0
	for _, p := range puts.snapshot() {
		if p.Kind == "state" && p.Type == MatrixCallMemberEventType {
			n++
		}
	}
	return n
}

func waitForRenewalTicks(t *testing.T, puts *meshPuts, want int) {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		if countMembershipPuts(puts) >= want {
			return
		}
		time.Sleep(20 * time.Millisecond)
	}
	t.Fatalf("renewal loop not publishing: %d membership PUTs, want >= %d", countMembershipPuts(puts), want)
}

func assertRenewalStopped(t *testing.T, puts *meshPuts, what string) {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		left := false
		for _, p := range puts.snapshot() {
			if p.Kind == "state" && p.Type == MatrixCallMemberEventType && strings.Contains(p.Body, `"m.calls":[]`) {
				left = true
			}
		}
		if left {
			break
		}
		time.Sleep(20 * time.Millisecond)
	}
	mark := countMembershipPuts(puts)
	if mark == 0 {
		t.Fatalf("%s: no membership PUTs observed at all", what)
	}
	time.Sleep(4 * meshRenewInterval)
	if after := countMembershipPuts(puts); after != mark {
		for _, p := range puts.snapshot()[mark:] {
			t.Errorf("%s: post-leave membership PUT: kind=%s type=%s body=%.200s", what, p.Kind, p.Type, p.Body)
		}
		t.Fatalf("%s: renewal kept publishing after teardown: %d -> %d", what, mark, after)
	}
}

func countConfInvites(puts *meshPuts, conf string) int {
	n := 0
	for _, p := range puts.snapshot() {
		if p.Kind == "send" && p.Type == event.CallInvite.Type && strings.Contains(p.Body, `"conf_id":"`+conf+`"`) {
			n++
		}
	}
	return n
}

func waitForCond(t *testing.T, cond func() bool, what string) {
	t.Helper()
	deadline := time.Now().Add(8 * time.Second)
	for time.Now().Before(deadline) {
		if cond() {
			return
		}
		time.Sleep(50 * time.Millisecond)
	}
	t.Fatal(what)
}

func newMeshTestCore(t *testing.T, srvURL string) *MatrixCore {
	t.Helper()
	core := NewMatrixCore(nil)
	t.Cleanup(func() { _ = core.Close() })
	if err := core.Authenticate(AuthConfig{
		Mode:     AuthModeBot,
		BotToken: "tok",
		Extra:    map[string]string{"homeserver": srvURL},
	}); err != nil {
		t.Fatalf("authenticate: %v", err)
	}
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
	shortenRenewal(t)
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
	if !strings.Contains(body.Offer.SDP, "m=audio") || !strings.Contains(body.Offer.SDP, "a=fingerprint:") {
		t.Fatalf("offer SDP not pc-generated: %q", body.Offer.SDP)
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

	if _, err := core.AcceptCall("conf_x"); err == nil {
		t.Fatal("group invite leaked into the 1:1 call table: AcceptCall(conf_x) succeeded")
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
	srv, puts := newMeshHomeserver(t)
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

	before := len(puts.snapshot())
	core.HandleCallInvite(evt)

	for _, p := range puts.snapshot()[before:] {
		if p.Kind == "send" && (p.Type == event.CallInvite.Type || p.Type == event.CallAnswer.Type || p.Type == event.CallCandidates.Type) {
			t.Fatalf("foreign conf produced call traffic: %+v", p)
		}
	}

	raw = `{"call_id":"conf_x","version":"1","party_id":"BOB1","conf_id":"conf_x",` +
		`"offer":{"type":"offer","sdp":` + strconv.Quote(sdp) + `}}`
	evt = &event.Event{
		Type:    event.CallInvite,
		RoomID:  id.RoomID("!room:test"),
		Sender:  id.UserID("@bob:test"),
		Content: event.Content{VeryRaw: json.RawMessage(raw)},
	}
	core.HandleCallInvite(evt)

	waitForCond(t, func() bool {
		for _, p := range puts.snapshot() {
			if p.Kind == "send" && p.Type == event.CallAnswer.Type && strings.Contains(p.Body, `"conf_id":"conf_x"`) {
				return true
			}
		}
		return false
	}, "no conf-tagged answer after foreign-conf invite; foreign peer blocked the mesh")
}

func TestSendICECandidatesConfTagged(t *testing.T) {
	srv, puts := newMeshHomeserver(t)
	core := seededMeshCore(t, srv)

	if err := core.ReconcileGroupMesh(); err != nil {
		t.Fatalf("reconcile: %v", err)
	}

	waitForCond(t, func() bool {
		for _, p := range puts.snapshot() {
			if p.Kind == "send" && p.Type == event.CallCandidates.Type {
				return true
			}
		}
		return false
	}, "no candidates event sent by real ICE gathering; puts absent")
	for _, p := range puts.snapshot() {
		if p.Kind == "send" && p.Type == event.CallCandidates.Type {
			if !strings.Contains(p.Body, `"conf_id":"conf_x"`) {
				t.Fatalf("candidates not conf-tagged: %s", p.Body)
			}
			if !strings.Contains(p.Body, `"call_id":"conf_x"`) {
				t.Fatalf("candidates not call-tagged: %s", p.Body)
			}
		}
	}
}

func TestGroupReconcileRemovesDepartedPeers(t *testing.T) {
	srv, puts := newMeshHomeserver(t)
	core := seededMeshCore(t, srv)
	uc := newUpdateCapture(core)

	if err := core.ReconcileGroupMesh(); err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	waitForCond(t, func() bool { return countConfInvites(puts, "conf_x") == 1 },
		"setup: no conf-tagged invite sent for the live bob peer")

	fireGroupMemberEvent(t, core, "@bob:test", MatrixCallMemberContent{Calls: []MatrixCallMemberCall{{
		CallID:  "conf_x",
		Devices: []MatrixCallDevice{{DeviceID: "BOB1", ExpiresTS: time.Now().UnixMilli() - 1}},
	}}})

	if err := core.ReconcileGroupMesh(); err != nil {
		t.Fatalf("reconcile after expiry: %v", err)
	}
	if !uc.groupPeerEnded("@bob:test") {
		t.Fatal("departed peer not torn down (no per-peer Ended update)")
	}

	fireGroupMemberEvent(t, core, "@bob:test", MatrixCallMemberContent{Calls: []MatrixCallMemberCall{{
		CallID: "conf_x",
		Devices: []MatrixCallDevice{{DeviceID: "BOB1", SessionID: "bs2",
			ExpiresTS: time.Now().UnixMilli() + 60_000}},
	}}})

	if err := core.ReconcileGroupMesh(); err != nil {
		t.Fatalf("reconcile after re-add: %v", err)
	}
	waitForCond(t, func() bool { return countConfInvites(puts, "conf_x") == 2 },
		"re-added peer not re-invited — the departed peer was never dropped from the mesh")
}
