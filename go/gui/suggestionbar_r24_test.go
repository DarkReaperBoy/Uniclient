package gui

import (
	"sync"
	"testing"
	"time"
)

// TestSuggestionMapsAreGuarded pins R24: the suggestion-fetch goroutine
// (ensureSuggestionState) and the GUI loop share the package maps
// suggStates/suggFetching/suggDismissed — unguarded, the fetch goroutine's
// completion writes raced every frame's reads (concurrent map read and map
// write = fatal runtime panic, reachable at every boot with one slow
// fetch; frameMu does not help — the goroutine is not a frame). All access
// now goes through the suggMu-guarded helpers; this test hammers both
// sides through them. Deterministic-safe on the js leg; under -race (the
// CI race leg) it proves the guards hold.
func TestSuggestionMapsAreGuarded(t *testing.T) {
	const acc = "race-acc"
	var wg sync.WaitGroup
	// GUI-loop side: the bar's per-frame projection (state + dismissal
	// reads), the dismiss click's write, and the fetch flag's test-and-set.
	wg.Add(1)
	go func() {
		defer wg.Done()
		for i := 0; i < 2000; i++ {
			suggStateFor(acc)
			suggDismissedFor(acc)
			suggDismissedStore(acc, "k")
			suggFetchingStart(acc)
		}
	}()
	// Fetch-goroutine side: the completion publish + the fetch-flag release.
	wg.Add(1)
	go func() {
		defer wg.Done()
		for i := 0; i < 2000; i++ {
			suggStateStore(acc, &suggestionFetchState{fetched: time.Now()})
			suggFetchingDone(acc)
		}
	}()
	wg.Wait()
}
