package tests

import (
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"
	. "uniclient/cores"

	"maunium.net/go/mautrix/id"
)

type renewFlakyServer struct {
	mu         sync.Mutex
	failNext   int
	memberPuts int
	callPuts   int
}

func newRenewFlakyServer(t *testing.T) (*httptest.Server, *renewFlakyServer) {
	t.Helper()
	f := &renewFlakyServer{}
	srv := httptest.NewServer(mxAuthSurface(id.UserID("@alice:localhost"), id.DeviceID("DEV1"), http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		p := r.URL.Path
		if r.Method == http.MethodGet && strings.Contains(p, MatrixCallEventType) {
			w.WriteHeader(http.StatusNotFound)
			_, _ = io.WriteString(w, `{"errcode":"M_NOT_FOUND"}`)
			return
		}
		if r.Method == http.MethodPut && strings.Contains(p, "/state/") {
			f.mu.Lock()
			switch {
			case strings.Contains(p, MatrixCallMemberEventType):
				f.memberPuts++
				if f.failNext > 0 {
					f.failNext--
					f.mu.Unlock()
					w.WriteHeader(http.StatusServiceUnavailable)
					_, _ = io.WriteString(w, `{"errcode":"M_UNKNOWN","error":"renewal rejected"}`)
					return
				}
			case strings.Contains(p, MatrixCallEventType):
				f.callPuts++
			}
			f.mu.Unlock()
			w.Header().Set("Content-Type", "application/json")
			_, _ = io.WriteString(w, `{"event_id":"$ev"}`)
			return
		}
		w.WriteHeader(http.StatusNotFound)
		_, _ = io.WriteString(w, `{"errcode":"M_NOT_FOUND"}`)
	})))
	t.Cleanup(srv.Close)
	return srv, f
}

func (f *renewFlakyServer) setFailNext(n int) {
	f.mu.Lock()
	f.failNext = n
	f.mu.Unlock()
}

func (f *renewFlakyServer) puts() (member int) {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.memberPuts
}

type endedRecorder struct {
	mu  sync.Mutex
	ids []string
}

func (r *endedRecorder) add(id string) {
	r.mu.Lock()
	r.ids = append(r.ids, id)
	r.mu.Unlock()
}

func (r *endedRecorder) snapshot() []string {
	r.mu.Lock()
	defer r.mu.Unlock()
	out := make([]string, len(r.ids))
	copy(out, r.ids)
	return out
}

func renewTestCore(t *testing.T, srvURL string) (*MatrixCore, *endedRecorder) {
	t.Helper()
	old := MatrixRenewInterval
	MatrixRenewInterval = 20 * time.Millisecond
	t.Cleanup(func() { MatrixRenewInterval = old })

	core := NewMatrixCore(nil)
	t.Cleanup(func() { _ = core.Close() })
	if err := core.Authenticate(AuthConfig{
		Mode:     AuthModeBot,
		BotToken: "tok",
		Extra:    map[string]string{"homeserver": srvURL},
	}); err != nil {
		t.Fatalf("authenticate: %v", err)
	}
	rec := &endedRecorder{}
	core.OnUpdate(func(u Update) {
		if u.Type == UpdateCallState && u.Call != nil && u.Call.IsGroup && u.Call.State == CallStateEnded {
			rec.add(u.Call.ID)
		}
	})
	t.Cleanup(func() {
		core.ForTestGroupMu().Lock()
		if core.ForTestGroupRenew() != nil {
			core.ForTestGroupRenew()
		}
		core.ForTestGroupMu().Unlock()
	})
	return core, rec
}

func joinedConf(core *MatrixCore) string {
	cs, _ := core.GetGroupCall("!room:test")
	if cs == nil {
		return ""
	}
	return cs.ID
}

func TestRenewalFailuresEndTheZombieCall(t *testing.T) {
	srv, flaky := newRenewFlakyServer(t)
	core, ended := renewTestCore(t, srv.URL)

	if _, err := core.JoinGroupCall("!room:test"); err != nil {
		t.Fatalf("JoinGroupCall: %v", err)
	}
	if joinedConf(core) == "" {
		t.Fatal("setup: conf not joined")
	}
	flaky.setFailNext(1 << 30)

	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) && joinedConf(core) != "" {
		time.Sleep(10 * time.Millisecond)
	}
	if conf := joinedConf(core); conf != "" {
		t.Fatalf("conf still joined after 3+ failed renewals: %s (zombie call)", conf)
	}

	deadline = time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) && len(ended.snapshot()) == 0 {
		time.Sleep(20 * time.Millisecond)
	}
	if ids := ended.snapshot(); len(ids) == 0 {
		t.Fatal("no Ended update after the zombie teardown")
	}

	before := flaky.puts()
	time.Sleep(150 * time.Millisecond)
	if after := flaky.puts(); after != before {
		t.Fatalf("renewal still publishing after teardown: %d -> %d", before, after)
	}
}

func TestRenewalTransientFailuresKeepCall(t *testing.T) {
	srv, flaky := newRenewFlakyServer(t)
	core, _ := renewTestCore(t, srv.URL)

	if _, err := core.JoinGroupCall("!room:test"); err != nil {
		t.Fatalf("JoinGroupCall: %v", err)
	}
	flaky.setFailNext(2)

	time.Sleep(300 * time.Millisecond)
	if conf := joinedConf(core); conf == "" {
		t.Fatal("two transient renewal failures tore the call down (counter must reset on success)")
	}
	if flaky.puts() < 3 {
		t.Fatalf("expected retries after recovery, got %d member PUTs", flaky.puts())
	}
}
