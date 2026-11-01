package gui

import (
	"sync"
	"testing"
	"time"

	"uniclient/engine"
)

func TestIVPhotoClaimLifecycle(t *testing.T) {
	key := ivPhotoKey(987654321)
	ivPhotoRelease(key)
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
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("failed IV photo download never released its claim — one transient error latches the photo for the whole session (R25)")
		}
		time.Sleep(2 * time.Millisecond)
	}
}
