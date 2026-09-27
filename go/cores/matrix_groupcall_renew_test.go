package cores

import (
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"maunium.net/go/mautrix"
	"maunium.net/go/mautrix/id"
)

// B-6 follow-up #5 (F-69, found+fixed same slice): the membership
// renewal goroutine swallowed EVERY publish error (`_ =`) — a server
// that persistently rejected renewals (permission drift, rate-limit
// storm, state-event rules changed) left us in a ZOMBIE call: local
// side keeps mic/speaker/mesh running and believes it is in the call,
// the remote side expires the lease and drops us, nothing ever
// re-derives reality. Renewal failure must eventually end the call.
//
// RED (behavioral, WORKLOG 305): with phase-A plumbing only, the
// zombie test times out — `conf still joined after 3+ failed renewals`.

// renewFlakyServer scripts membership-state PUT failures:
// failNext member-PUTs are rejected with 503, the rest succeed.
// GET m.call state always 404s (JoinGroupCall mints the conf locally).
type renewFlakyServer struct {
	mu         sync.Mutex
	failNext   int
	memberPuts int
	callPuts   int
}

func newRenewFlakyServer(t *testing.T) (*httptest.Server, *renewFlakyServer) {
	t.Helper()
	f := &renewFlakyServer{}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		p := r.URL.Path
		if r.Method == http.MethodGet && strings.Contains(p, matrixCallEventType) {
			w.WriteHeader(http.StatusNotFound)
			_, _ = io.WriteString(w, `{"errcode":"M_NOT_FOUND"}`)
			return
		}
		if r.Method == http.MethodPut && strings.Contains(p, "/state/") {
			f.mu.Lock()
			switch {
			case strings.Contains(p, matrixCallMemberEventType):
				f.memberPuts++
				if f.failNext > 0 {
					f.failNext--
					f.mu.Unlock()
					w.WriteHeader(http.StatusServiceUnavailable)
					_, _ = io.WriteString(w, `{"errcode":"M_UNKNOWN","error":"renewal rejected"}`)
					return
				}
			case strings.Contains(p, matrixCallEventType):
				f.callPuts++
			}
			f.mu.Unlock()
			w.Header().Set("Content-Type", "application/json")
			_, _ = io.WriteString(w, `{"event_id":"$ev"}`)
			return
		}
		w.WriteHeader(http.StatusNotFound)
		_, _ = io.WriteString(w, `{"errcode":"M_NOT_FOUND"}`)
	}))
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

// endedRecorder collects Ended updates from any goroutine (the
// renewal path fires them off the ticker goroutine).
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

// renewTestCore: an authed core whose renewal ticks run at 20 ms.
func renewTestCore(t *testing.T, srvURL string) (*MatrixCore, *endedRecorder) {
	t.Helper()
	old := matrixRenewInterval
	matrixRenewInterval = 20 * time.Millisecond
	t.Cleanup(func() { matrixRenewInterval = old })

	client, err := mautrix.NewClient(srvURL, id.UserID("@alice:localhost"), "tok")
	if err != nil {
		t.Fatalf("NewClient: %v", err)
	}
	core := &MatrixCore{
		authed:     true,
		ctx:        context.Background(),
		cancel:     func() {},
		deviceID:   "DEV1",
		userID:     id.UserID("@alice:localhost"),
		homeserver: srvURL,
		client:     client,
	}
	rec := &endedRecorder{}
	core.OnUpdate(func(u Update) {
		if u.Type == UpdateCallState && u.Call != nil && u.Call.IsGroup && u.Call.State == CallStateEnded {
			rec.add(u.Call.ID)
		}
	})
	t.Cleanup(func() {
		core.groupMu.Lock()
		if core.groupRenew != nil {
			core.groupRenew()
		}
		core.groupMu.Unlock()
	})
	return core, rec
}

func joinedConf(core *MatrixCore) string {
	core.groupMu.Lock()
	defer core.groupMu.Unlock()
	return core.groupConfID
}

// TestRenewalFailuresEndTheZombieCall: persistently rejected renewals
// must eventually END the call (teardown + Ended fired + renewal
// goroutine exits) instead of running forever.
func TestRenewalFailuresEndTheZombieCall(t *testing.T) {
	srv, flaky := newRenewFlakyServer(t)
	core, ended := renewTestCore(t, srv.URL)

	if _, err := core.JoinGroupCall("!room:test"); err != nil {
		t.Fatalf("JoinGroupCall: %v", err)
	}
	if joinedConf(core) == "" {
		t.Fatal("setup: conf not joined")
	}
	// Initial publish succeeded; from now on every renewal is rejected.
	flaky.setFailNext(1 << 30)

	// Phase A (behavior absent): this times out — conf stays joined,
	// i.e. the zombie runs forever. RED quote in WORKLOG 305.
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) && joinedConf(core) != "" {
		time.Sleep(10 * time.Millisecond)
	}
	if conf := joinedConf(core); conf != "" {
		t.Fatalf("conf still joined after 3+ failed renewals: %s (zombie call)", conf)
	}

	// Ended update fired (poll — the handler runs on the ticker
	// goroutine, so the append is synchronized via endedRecorder).
	deadline = time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) && len(ended.snapshot()) == 0 {
		time.Sleep(20 * time.Millisecond)
	}
	if ids := ended.snapshot(); len(ids) == 0 {
		t.Fatal("no Ended update after the zombie teardown")
	}

	// The renewal goroutine must EXIT: member-PUT count stops growing.
	before := flaky.puts()
	time.Sleep(150 * time.Millisecond) // ≥7 ticks if still running
	if after := flaky.puts(); after != before {
		t.Fatalf("renewal still publishing after teardown: %d -> %d", before, after)
	}
}

// TestRenewalTransientFailuresKeepCall: a short burst of rejections
// must NOT kill the call — the counter resets on the next success.
func TestRenewalTransientFailuresKeepCall(t *testing.T) {
	srv, flaky := newRenewFlakyServer(t)
	core, _ := renewTestCore(t, srv.URL)

	if _, err := core.JoinGroupCall("!room:test"); err != nil {
		t.Fatalf("JoinGroupCall: %v", err)
	}
	flaky.setFailNext(2) // two failed renewals, then recovery

	time.Sleep(300 * time.Millisecond) // ≥10 ticks at 20 ms: fail, fail, recover, …
	if conf := joinedConf(core); conf == "" {
		t.Fatal("two transient renewal failures tore the call down (counter must reset on success)")
	}
	if flaky.puts() < 3 {
		t.Fatalf("expected retries after recovery, got %d member PUTs", flaky.puts())
	}
}
