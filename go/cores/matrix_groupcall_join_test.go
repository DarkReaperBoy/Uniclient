package cores

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"maunium.net/go/mautrix"
	"maunium.net/go/mautrix/id"
)

// B-6 → F-62: JoinGroupCall against a scripted mini-homeserver.
// Seam-RED (WORKLOG 295): the OLD body returned ErrNotSupported —
// behavioral RED: `JoinGroupCall returned <not supported>` instead of
// a real session.

type statePut struct {
	Type     string
	StateKey string
	Body     string
}

// newMiniHomeserver serves exactly what JoinGroupCall touches:
// GET  .../state/<type>/<key>        → existingCallState (or 404)
// PUT  .../state/<type>/<key>        → captured, {"event_id":"$ev"}
func newMiniHomeserver(t *testing.T, existingCallState string) (*httptest.Server, *[]statePut) {
	t.Helper()
	var puts []statePut
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		p := r.URL.Path
		const marker = "/state/"
		if idx := strings.Index(p, marker); idx >= 0 && strings.Contains(p, "/rooms/") {
			rest := p[idx+len(marker):] // "<type>/<key>" (key optional)
			parts := strings.SplitN(rest, "/", 2)
			evType := parts[0]
			stateKey := ""
			if len(parts) == 2 {
				stateKey = parts[1]
			}
			switch r.Method {
			case http.MethodGet:
				if evType == matrixCallEventType && existingCallState != "" {
					w.Header().Set("Content-Type", "application/json")
					_, _ = io.WriteString(w, existingCallState)
					return
				}
				w.WriteHeader(http.StatusNotFound)
				_, _ = io.WriteString(w, `{"errcode":"M_NOT_FOUND","error":"Not found"}`)
				return
			case http.MethodPut:
				body, _ := io.ReadAll(r.Body)
				puts = append(puts, statePut{Type: evType, StateKey: stateKey, Body: string(body)})
				w.Header().Set("Content-Type", "application/json")
				_, _ = io.WriteString(w, `{"event_id":"$ev"}`)
				return
			}
		}
		w.WriteHeader(http.StatusNotFound)
		_, _ = io.WriteString(w, `{"errcode":"M_NOT_FOUND"}`)
	}))
	t.Cleanup(srv.Close)
	return srv, &puts
}

func newGroupTestCore(t *testing.T, srvURL string) *MatrixCore {
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
		if core.groupRenew != nil {
			core.groupRenew()
		}
		core.groupMu.Unlock()
	})
	return core
}

func TestJoinGroupCallCreatesConfAndPublishesMembership(t *testing.T) {
	srv, puts := newMiniHomeserver(t, "")
	core := newGroupTestCore(t, srv.URL)

	before := time.Now().UnixMilli()
	sess, err := core.JoinGroupCall("!room:test")
	if err != nil {
		t.Fatalf("JoinGroupCall: %v", err)
	}
	if sess == nil || sess.ID == "" || !sess.IsGroup || sess.State != CallStateActive {
		t.Fatalf("session = %+v, want active group session with id", sess)
	}

	// Exactly: one m.call creation + one member publish.
	var confPut, memberPut *statePut
	for i := range *puts {
		switch (*puts)[i].Type {
		case matrixCallEventType:
			confPut = &(*puts)[i]
		case matrixCallMemberEventType:
			memberPut = &(*puts)[i]
		}
	}
	if confPut == nil {
		t.Fatal("m.call state event never created")
	}
	if memberPut == nil {
		t.Fatal("m.call.member state event never published")
	}
	if memberPut.StateKey != "@alice:test" {
		t.Fatalf("member state_key = %q, want own MXID (spec)", memberPut.StateKey)
	}

	var conf struct {
		CallID string `json:"m.call_id"`
	}
	if err := json.Unmarshal([]byte(confPut.Body), &conf); err != nil || !strings.HasPrefix(conf.CallID, "conf_") {
		t.Fatalf("m.call body %q (err=%v)", confPut.Body, err)
	}

	var member matrixCallMemberContent
	if err := json.Unmarshal([]byte(memberPut.Body), &member); err != nil {
		t.Fatalf("member body %q: %v", memberPut.Body, err)
	}
	if len(member.Calls) != 1 || member.Calls[0].CallID != conf.CallID {
		t.Fatalf("member calls = %+v, want the created conf %q", member.Calls, conf.CallID)
	}
	if len(member.Calls[0].Foci) != 0 {
		t.Fatalf("foci must be empty (full-mesh): %v", member.Calls[0].Foci)
	}
	devs := member.Calls[0].Devices
	if len(devs) != 1 || devs[0].DeviceID != "DEV1" || devs[0].SessionID == "" {
		t.Fatalf("devices = %+v", devs)
	}
	if devs[0].ExpiresTS <= before || devs[0].ExpiresTS > time.Now().UnixMilli()+matrixDeviceTTLMillis+1000 {
		t.Fatalf("expires_ts = %d, want a fresh %d ms lease", devs[0].ExpiresTS, matrixDeviceTTLMillis)
	}
	if len(devs[0].Feeds) != 1 || devs[0].Feeds[0].Purpose != matrixFeedUserMedia {
		t.Fatalf("feeds = %+v", devs[0].Feeds)
	}
	if sess.ID != conf.CallID {
		t.Fatalf("session id %q != conf %q", sess.ID, conf.CallID)
	}
}

func TestJoinGroupCallAdoptsExistingConf(t *testing.T) {
	srv, puts := newMiniHomeserver(t, `{"m.call_id":"conf_existing"}`)
	core := newGroupTestCore(t, srv.URL)

	sess, err := core.JoinGroupCall("!room:test")
	if err != nil {
		t.Fatalf("JoinGroupCall: %v", err)
	}
	if sess.ID != "conf_existing" {
		t.Fatalf("session id = %q, want adopted conf_existing", sess.ID)
	}
	for _, p := range *puts {
		if p.Type == matrixCallEventType {
			t.Fatalf("existing conf must NOT be recreated; m.call PUT: %s", p.Body)
		}
		if p.Type == matrixCallMemberEventType && !strings.Contains(p.Body, "conf_existing") {
			t.Fatalf("membership must carry the adopted conf: %s", p.Body)
		}
	}
}
