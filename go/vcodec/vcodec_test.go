package vcodec

import (
	"sync"
	"testing"
	"time"
)

func TestPoolStartsWithPermits(t *testing.T) {
	if got := Cap(); got != 4 {
		t.Errorf("Cap() = %d, want 4 (bounded budget)", got)
	}
	done := make(chan struct{})
	go func() {
		Acquire()
		Release()
		close(done)
	}()
	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatal("Acquire blocked on a pool that init should have filled")
	}
}

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
	if added := PrimeToCapacity(); added < 0 {
		t.Errorf("PrimeToCapacity returned %d", added)
	}
}

func TestProducersQueueInsteadOfDeadlock(t *testing.T) {
	primed := PrimeToCapacity()
	if primed < 0 || primed > Cap() {
		t.Fatalf("PrimeToCapacity = %d (cap %d)", primed, Cap())
	}

	const producers = 16
	var wg sync.WaitGroup
	done := make(chan struct{})
	for i := 0; i < producers; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for r := 0; r < 8; r++ {
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
