package engine

import (
	"testing"

	"uniclient/utils"
)

// Avatar Corners (AyuGram userpic styling, slice 215): the settings
// round-trip through the config bridge — slider value 0..23 (nil = 23 =
// circle, AyuGram kMaxAvatarCorners) and the Single Corner Radius toggle
// (nil = false, forums keep their native 30% rounding).

func TestAvatarCornersSettingsRoundTrip(t *testing.T) {
	e := newTestEngine(t)
	dir := t.TempDir()
	v, err := utils.CreateVault(dir+"/vault.db", "test")
	if err != nil {
		t.Fatal(err)
	}
	cfg := utils.DefaultConfig()
	e.vault = v
	e.config = &cfg

	// Defaults.
	if got := utils.EffectiveAvatarCorners(*e.GetConfig()); got != 23 {
		t.Fatalf("default corners = %d, want 23", got)
	}

	// Slider + toggle land in the config (clamped at the boundary).
	c12, single := 12, true
	if err := e.UpdateConfigFromBridge(&ConfigChanges{AyuAvatarCorners: &c12, AyuSingleCornerRadius: &single}); err != nil {
		t.Fatal(err)
	}
	if e.GetConfig().AyuAvatarCorners == nil || *e.GetConfig().AyuAvatarCorners != 12 {
		t.Fatalf("config AyuAvatarCorners = %v, want 12", e.GetConfig().AyuAvatarCorners)
	}
	if e.GetConfig().AyuSingleCornerRadius == nil || !*e.GetConfig().AyuSingleCornerRadius {
		t.Fatalf("config AyuSingleCornerRadius = %v, want true", e.GetConfig().AyuSingleCornerRadius)
	}

	// Out-of-range values clamp to the 0..23 domain.
	c99 := 99
	if err := e.UpdateConfigFromBridge(&ConfigChanges{AyuAvatarCorners: &c99}); err != nil {
		t.Fatal(err)
	}
	if got := *e.GetConfig().AyuAvatarCorners; got != 23 {
		t.Fatalf("clamped corners = %d, want 23", got)
	}
	cNeg := -5
	if err := e.UpdateConfigFromBridge(&ConfigChanges{AyuAvatarCorners: &cNeg}); err != nil {
		t.Fatal(err)
	}
	if got := *e.GetConfig().AyuAvatarCorners; got != 0 {
		t.Fatalf("clamped negative = %d, want 0", got)
	}

	// The toggle can be turned back off (pointer semantics).
	off := false
	if err := e.UpdateConfigFromBridge(&ConfigChanges{AyuSingleCornerRadius: &off}); err != nil {
		t.Fatal(err)
	}
	if e.GetConfig().AyuSingleCornerRadius == nil || *e.GetConfig().AyuSingleCornerRadius {
		t.Fatal("config AyuSingleCornerRadius not persisted as false")
	}
}
