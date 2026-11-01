package tests

import (
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

func TestEventSubscriberFanOut(t *testing.T) {
	e := &Engine{}
	a, b := &fanRecorder{}, &fanRecorder{}

	subA := e.Subscribe(a.record)
	subB := e.Subscribe(b.record)

	e.PushEvent([]byte("e1"))
	e.PushEvent([]byte("e2"))

	if a.count() != 2 || b.count() != 2 {
		t.Fatalf("fan-out: a=%d b=%d events, want 2/2", a.count(), b.count())
	}

	subB.Unsubscribe()
	e.PushEvent([]byte("e3"))

	if a.count() != 3 {
		t.Fatalf("a=%d after third event, want 3", a.count())
	}
	if b.count() != 2 {
		t.Fatalf("unsubscribed b=%d, want 2 (no delivery after unsubscribe)", b.count())
	}

	subB.Unsubscribe()
	e.PushEvent([]byte("e4"))
	if a.count() != 4 || b.count() != 2 {
		t.Fatalf("after double unsubscribe: a=%d b=%d, want 4/2", a.count(), b.count())
	}
	subA.Unsubscribe()
}

func TestEventSubscriberSetCallbackCompat(t *testing.T) {
	e := &Engine{}
	a, b, c := &fanRecorder{}, &fanRecorder{}, &fanRecorder{}

	e.Subscribe(a.record)
	e.Subscribe(b.record)
	e.SetEventCallback(c.record)

	e.PushEvent([]byte("x"))

	if a.count() != 0 || b.count() != 0 {
		t.Fatalf("SetEventCallback must clear prior subscribers, got a=%d b=%d", a.count(), b.count())
	}
	if c.count() != 1 {
		t.Fatalf("c=%d, want 1", c.count())
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
