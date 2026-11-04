package tests

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
	. "uniclient/cores"

	"maunium.net/go/mautrix/id"
)

type statePut struct {
	Type     string
	StateKey string
	Body     string
}

func newMiniHomeserver(t *testing.T, existingCallState string) (*httptest.Server, *[]statePut) {
	t.Helper()
	var puts []statePut
	srv := httptest.NewServer(mxAuthSurface(id.UserID("@alice:test"), id.DeviceID("DEV1"), http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		p := r.URL.Path
		const marker = "/state/"
		if idx := strings.Index(p, marker); idx >= 0 && strings.Contains(p, "/rooms/") {
			rest := p[idx+len(marker):]
			parts := strings.SplitN(rest, "/", 2)
			evType := parts[0]
			stateKey := ""
			if len(parts) == 2 {
				stateKey = parts[1]
			}
			switch r.Method {
			case http.MethodGet:
				if evType == MatrixCallEventType && existingCallState != "" {
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
	})))
	t.Cleanup(srv.Close)
	return srv, &puts
}

func newGroupTestCore(t *testing.T, srvURL string) *MatrixCore {
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

	var confPut, memberPut *statePut
	for i := range *puts {
		switch (*puts)[i].Type {
		case MatrixCallEventType:
			confPut = &(*puts)[i]
		case MatrixCallMemberEventType:
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

	var member MatrixCallMemberContent
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
	if devs[0].ExpiresTS <= before || devs[0].ExpiresTS > time.Now().UnixMilli()+MatrixDeviceTTLMillis+1000 {
		t.Fatalf("expires_ts = %d, want a fresh %d ms lease", devs[0].ExpiresTS, MatrixDeviceTTLMillis)
	}
	if len(devs[0].Feeds) != 1 || devs[0].Feeds[0].Purpose != MatrixFeedUserMedia {
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
		if p.Type == MatrixCallEventType {
			t.Fatalf("existing conf must NOT be recreated; m.call PUT: %s", p.Body)
		}
		if p.Type == MatrixCallMemberEventType && !strings.Contains(p.Body, "conf_existing") {
			t.Fatalf("membership must carry the adopted conf: %s", p.Body)
		}
	}
}
