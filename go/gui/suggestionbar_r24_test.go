package gui

import (
	"sync"
	"testing"
	"time"
)

func TestSuggestionMapsAreGuarded(t *testing.T) {
	const acc = "race-acc"
	var wg sync.WaitGroup
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
