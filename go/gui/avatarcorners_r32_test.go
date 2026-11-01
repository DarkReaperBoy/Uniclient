package gui

import (
	"sync"
	"testing"
)

func TestAvatarCornersCrossGoroutineIsAtomic(t *testing.T) {
	u := NewUI()
	if got := int(u.avatarCorners.Load()); got != 23 {
		t.Fatalf("NewUI circle default: want 23, got %d", got)
	}
	var wg sync.WaitGroup
	wg.Add(1)
	go func() {
		defer wg.Done()
		for i := 0; i < 2000; i++ {
			u.applyAvatarCorners(i % 24)
		}
	}()
	for i := 0; i < 2000; i++ {
		if r := u.avatarRadiusPx(40); r < 0 || r > 20 {
			t.Fatalf("radius out of range: %d", r)
		}
	}
	wg.Wait()
	u.applyAvatarCorners(0)
	if r := u.avatarRadiusPx(40); r != 0 {
		t.Fatalf("square corners: want radius 0, got %d", r)
	}
	u.applyAvatarCorners(99)
	if r := u.avatarRadiusPx(40); r != 20 {
		t.Fatalf("clamped-to-circle radius: want 20 (=40/2), got %d", r)
	}
}
