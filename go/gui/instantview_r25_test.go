package gui

import (
	"sync"
	"testing"
	"time"

	"uniclient/engine"
)

// TestIVPhotoClaimLifecycle pins R25's claim semantics: the package-level
// IV photo latch is an in-flight CLAIM, not a done-marker. The pre-fix
// ivDocDone map was set before the download ran and never cleared on any
// failure path, so one transient error (network blip, engine hiccup,
// unreadable temp file) latched the photo as "done" forever — thumbnail-
// only or a permanent blank box until restart. Claim → reject → release →
// claim-again is the whole contract.
func TestIVPhotoClaimLifecycle(t *testing.T) {
	key := ivPhotoKey(987654321)
	ivPhotoRelease(key) // clean slate even if a prior run leaked
	if !ivPhotoClaim(key) {
		t.Fatal("first claim must succeed")
	}
	if ivPhotoClaim(key) {
		t.Fatal("claim must be rejected while the download is in flight")
	}
	ivPhotoRelease(key)
	if !ivPhotoClaim(key) {
		t.Fatal("release must allow a fresh claim — a failed download must not latch forever (R25)")
	}
	ivPhotoRelease(key)
}

// TestIVPhotoClaimGuarded hammers the latch from both sides (the GUI loop
// claims during layout; the download goroutine releases). The map is
// package-level and written by both — without ivDocMu this is a fatal
// concurrent-map panic; the CI race leg proves the guard.
func TestIVPhotoClaimGuarded(t *testing.T) {
	const key = "ivphoto:987654322"
	var wg sync.WaitGroup
	wg.Add(2)
	go func() {
		defer wg.Done()
		for i := 0; i < 2000; i++ {
			if ivPhotoClaim(key) {
				ivPhotoRelease(key)
			}
		}
	}()
	go func() {
		defer wg.Done()
		for i := 0; i < 2000; i++ {
			ivPhotoRelease(key)
		}
	}()
	wg.Wait()
}

// TestIVPhotoRetryAfterFailure drives the REAL failure wiring end to end:
// a bare App with a zero Engine (getAccount misses → "account not found")
// so ivPhotoImage's spawned chain fails on its first step. The chain must
// release its claim when it fails — otherwise the photo is unfetchable for
// the rest of the session (R25: pre-fix, one transient failure = permanent
// thumbnail-only until restart).
func TestIVPhotoRetryAfterFailure(t *testing.T) {
	a := &App{eng: &engine.Engine{}}
	st := &ivState{accountID: "no-such-account", url: "https://telegra.ph/r25"}
	b := &ivBlock{Type: "photo", PhotoID: 987654321, Extra: "x", W: 100, H: 50}
	key := ivPhotoKey(b.PhotoID)
	ivPhotoRelease(key)

	if img := a.ivPhotoImage(st, b); img != nil {
		t.Fatalf("no image can be available yet, got %v", img)
	}
	deadline := time.Now().Add(10 * time.Second)
	for {
		if ivPhotoClaim(key) {
			ivPhotoRelease(key)
			break // the failed chain gave the claim back — a retry is possible
		}
		if time.Now().After(deadline) {
			t.Fatal("failed IV photo download never released its claim — one transient error latches the photo for the whole session (R25)")
		}
		time.Sleep(2 * time.Millisecond)
	}
}
