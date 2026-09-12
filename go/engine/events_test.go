package engine

import (
	"sync"
	"testing"
)

// fanRecorder records deliveries to one subscriber.
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

// TestEventSubscriberFanOut pins the multi-window event contract (slice 168):
// every registered subscriber receives every pushed event, unsubscription
// stops delivery for that subscriber only.
func TestEventSubscriberFanOut(t *testing.T) {
	e := &Engine{}
	a, b := &fanRecorder{}, &fanRecorder{}

	subA := e.Subscribe(a.record)
	subB := e.Subscribe(b.record)

	e.pushEvent([]byte("e1"))
	e.pushEvent([]byte("e2"))

	if a.count() != 2 || b.count() != 2 {
		t.Fatalf("fan-out: a=%d b=%d events, want 2/2", a.count(), b.count())
	}

	subB.Unsubscribe()
	e.pushEvent([]byte("e3"))

	if a.count() != 3 {
		t.Fatalf("a=%d after third event, want 3", a.count())
	}
	if b.count() != 2 {
		t.Fatalf("unsubscribed b=%d, want 2 (no delivery after unsubscribe)", b.count())
	}

	// Idempotent unsubscribe.
	subB.Unsubscribe()
	e.pushEvent([]byte("e4"))
	if a.count() != 4 || b.count() != 2 {
		t.Fatalf("after double unsubscribe: a=%d b=%d, want 4/2", a.count(), b.count())
	}
	subA.Unsubscribe()
}

// TestEventSubscriberSetCallbackCompat pins the legacy single-callback
// contract: SetEventCallback replaces the whole subscriber list (it is the
// boot-time registration used before any window exists).
func TestEventSubscriberSetCallbackCompat(t *testing.T) {
	e := &Engine{}
	a, b, c := &fanRecorder{}, &fanRecorder{}, &fanRecorder{}

	e.Subscribe(a.record)
	e.Subscribe(b.record)
	e.SetEventCallback(c.record)

	e.pushEvent([]byte("x"))

	if a.count() != 0 || b.count() != 0 {
		t.Fatalf("SetEventCallback must clear prior subscribers, got a=%d b=%d", a.count(), b.count())
	}
	if c.count() != 1 {
		t.Fatalf("c=%d, want 1", c.count())
	}
}

// TestEventSubscriberNoopSafety pins that pushEvent with no subscribers and
// nil-callback registrations are safe no-ops.
func TestEventSubscriberNoopSafety(t *testing.T) {
	e := &Engine{}
	e.pushEvent([]byte("nobody home"))
	if s := e.Subscribe(nil); s != nil {
		t.Fatalf("Subscribe(nil) must return nil, got %v", s)
	}
	var nilSub *EventSubscription
	nilSub.Unsubscribe() // no-op, must not panic
}
