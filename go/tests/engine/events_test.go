package tests

import (
	"encoding/json"
	"sync"
	"testing"

	. "uniclient/engine"
)

type fanRecorder struct {
	mu   sync.Mutex
	seen []string
}

func (r *fanRecorder) record(b []byte) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.seen = append(r.seen, string(b))
}

func (r *fanRecorder) count() int {
	r.mu.Lock()
	defer r.mu.Unlock()
	return len(r.seen)
}

func (r *fanRecorder) first() string {
	r.mu.Lock()
	defer r.mu.Unlock()
	if len(r.seen) == 0 {
		return ""
	}
	return r.seen[0]
}

func replayIsAccountList(t *testing.T, raw string) {
	t.Helper()
	var env struct {
		Type string          `json:"type"`
		Data json.RawMessage `json:"data"`
	}
	if err := json.Unmarshal([]byte(raw), &env); err != nil {
		t.Fatalf("replay is not JSON: %v", err)
	}
	if env.Type != EventAccountList {
		t.Fatalf("replay type = %q, want %q", env.Type, EventAccountList)
	}
	if string(env.Data) != "[]" {
		t.Fatalf("zero-value engine replay data = %s, want []", env.Data)
	}
}

func TestEventSubscriberFanOut(t *testing.T) {
	e := &Engine{}
	a, b := &fanRecorder{}, &fanRecorder{}

	subA := e.Subscribe(a.record)
	subB := e.Subscribe(b.record)

	e.PushEvent([]byte("e1"))
	e.PushEvent([]byte("e2"))

	if a.count() != 3 || b.count() != 3 {
		t.Fatalf("fan-out: a=%d b=%d events, want 3/3 (1 replay + 2 pushed)", a.count(), b.count())
	}
	replayIsAccountList(t, a.first())

	subB.Unsubscribe()
	e.PushEvent([]byte("e3"))

	if a.count() != 4 {
		t.Fatalf("a=%d after third event, want 4", a.count())
	}
	if b.count() != 3 {
		t.Fatalf("unsubscribed b=%d, want 3 (no delivery after unsubscribe)", b.count())
	}

	subB.Unsubscribe()
	e.PushEvent([]byte("e4"))
	if a.count() != 5 || b.count() != 3 {
		t.Fatalf("after double unsubscribe: a=%d b=%d, want 5/3", a.count(), b.count())
	}
	subA.Unsubscribe()
}

func TestEventSubscriberSetCallbackCompat(t *testing.T) {
	e := &Engine{}
	a, b, c := &fanRecorder{}, &fanRecorder{}, &fanRecorder{}

	e.Subscribe(a.record)
	e.Subscribe(b.record)
	if a.count() != 1 || b.count() != 1 {
		t.Fatalf("subscribe replay missing: a=%d b=%d, want 1/1", a.count(), b.count())
	}
	e.SetEventCallback(c.record)
	if c.count() != 1 {
		t.Fatalf("SetEventCallback replay missing: c=%d, want 1", c.count())
	}
	replayIsAccountList(t, c.first())

	e.PushEvent([]byte("x"))

	if a.count() != 1 || b.count() != 1 {
		t.Fatalf("SetEventCallback must clear prior subscribers, got a=%d b=%d", a.count(), b.count())
	}
	if c.count() != 2 {
		t.Fatalf("c=%d, want 2 (replay + x)", c.count())
	}
}

func TestEventSubscriberNoopSafety(t *testing.T) {
	e := &Engine{}
	e.PushEvent([]byte("nobody home"))
	if s := e.Subscribe(nil); s != nil {
		t.Fatalf("Subscribe(nil) must return nil, got %v", s)
	}
	var nilSub *EventSubscription
	nilSub.Unsubscribe()
}

func TestSubscribeReplayIsFirstAndFresh(t *testing.T) {
	e := &Engine{}
	a := &fanRecorder{}
	sub := e.Subscribe(a.record)
	defer sub.Unsubscribe()
	if a.count() != 1 {
		t.Fatalf("fresh subscribe delivered %d events, want exactly the replay", a.count())
	}
	replayIsAccountList(t, a.first())
	e.PushEvent([]byte("after"))
	if a.count() != 2 {
		t.Fatalf("post-replay push lost: a=%d, want 2", a.count())
	}
}

func TestSetEventCallbackNilClearsWithoutReplay(t *testing.T) {
	e := &Engine{}
	a := &fanRecorder{}
	e.SetEventCallback(a.record)
	if a.count() != 1 {
		t.Fatalf("SetEventCallback replay missing: a=%d, want 1", a.count())
	}
	e.SetEventCallback(nil)
	e.PushEvent([]byte("x"))
	if a.count() != 1 {
		t.Fatalf("nil SetEventCallback must clear without delivering: a=%d, want 1", a.count())
	}
}
