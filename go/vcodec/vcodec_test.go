package vcodec

import (
	"sync"
	"testing"
	"time"
)

// The pool must start with at least one permit (otherwise every Acquire
// blocks forever) and never exceed its capacity.
func TestPoolStartsWithPermits(t *testing.T) {
	if got := Cap(); got != 4 {
		t.Errorf("Cap() = %d, want 4 (bounded budget)", got)
	}
	done := make(chan struct{})
	go func() {
		Acquire() // must not block: init deposited permits
		Release()
		close(done)
	}()
	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatal("Acquire blocked on a pool that init should have filled")
	}
}

// Acquire/Release round-trip: permits taken are returned, so the pool
// never leaks and later callers still make progress.
func TestAcquireReleaseRoundTrip(t *testing.T) {
	const workers = 12
	var wg sync.WaitGroup
	released := make(chan int, workers)
	for i := 0; i < workers; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			Acquire()
			released <- 1
			Release()
		}()
	}
	// Everything must finish without a permit leak.
	done := make(chan struct{})
	go func() { wg.Wait(); close(done) }()
	select {
	case <-done:
	case <-time.After(10 * time.Second):
		t.Fatal("workers did not finish — permit leak or inverted Acquire")
	}
	if n := len(released); n != workers {
		t.Errorf("only %d/%d workers got a permit", n, workers)
	}
	// The pool must be refilled to capacity now that everyone released.
	if added := PrimeToCapacity(); added < 0 {
		t.Errorf("PrimeToCapacity returned %d", added)
	}
}

// Regression pin (the slice-216 CI failure, now shared by both codecs):
// more concurrent producers than permits must QUEUE, never deadlock.
// The pool is primed to CAPACITY first — an inverted Acquire (a send
// instead of a receive) deadlocks instantly against a full buffer, which
// is the only way to catch it on a machine with spare capacity.
func TestProducersQueueInsteadOfDeadlock(t *testing.T) {
	primed := PrimeToCapacity()
	if primed < 0 || primed > Cap() {
		t.Fatalf("PrimeToCapacity = %d (cap %d)", primed, Cap())
	}

	const producers = 16 // 4× the permit count
	var wg sync.WaitGroup
	done := make(chan struct{})
	for i := 0; i < producers; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for r := 0; r < 8; r++ { // several round-trips each
				Acquire()
				Release()
			}
		}()
	}
	go func() { wg.Wait(); close(done) }()
	select {
	case <-done:
	case <-time.After(20 * time.Second):
		t.Fatal("a producer starved under semaphore pressure (deadlock regression)")
	}
}
