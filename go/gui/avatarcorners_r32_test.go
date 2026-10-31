package gui

import (
	"sync"
	"testing"
)

// TestAvatarCornersCrossGoroutineIsAtomic pins R32: UI.avatarCorners was a
// plain int written by refreshConfig from persist-completion goroutines
// (openSettings' `go a.refreshConfig()`, applyDrawerHidden/applySystemTray/
// applyAccent/applyFontScale tails, and the corners slider's 600 ms debounce
// timer) while the GUI loop read it every frame via avatarRadiusPx in every
// window — an unsynchronized write-races-layout data race. It is now an
// atomic.Int32 (same class as msgShowSeconds). This test hammers both sides
// through the real methods: deterministic-safe without -race; under -race
// (the CI race leg) it proves the atomic holds. A bare-harness engine never
// reaches the line (GetConfig()==nil early-return) — which is exactly why
// the race survived every existing test.
func TestAvatarCornersCrossGoroutineIsAtomic(t *testing.T) {
	u := NewUI()
	if got := int(u.avatarCorners.Load()); got != 23 {
		t.Fatalf("NewUI circle default: want 23, got %d", got)
	}
	var wg sync.WaitGroup
	// Writer side: refreshConfig's tail shape — applyAvatarCorners from a
	// non-GUI goroutine (config re-apply after a persist).
	wg.Add(1)
	go func() {
		defer wg.Done()
		for i := 0; i < 2000; i++ {
			u.applyAvatarCorners(i % 24)
		}
	}()
	// Reader side: layout's per-frame projection (every avatar, every window).
	for i := 0; i < 2000; i++ {
		if r := u.avatarRadiusPx(40); r < 0 || r > 20 {
			t.Fatalf("radius out of range: %d", r)
		}
	}
	wg.Wait()
	// Visibility sanity after the writer joined: Store→Load is linearizable.
	u.applyAvatarCorners(0)
	if r := u.avatarRadiusPx(40); r != 0 {
		t.Fatalf("square corners: want radius 0, got %d", r)
	}
	u.applyAvatarCorners(99) // clamp high
	if r := u.avatarRadiusPx(40); r != 20 {
		t.Fatalf("clamped-to-circle radius: want 20 (=40/2), got %d", r)
	}
}
