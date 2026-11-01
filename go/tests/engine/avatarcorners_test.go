package tests

import (
	"testing"
	. "uniclient/engine"

	"uniclient/utils"
)

func TestAvatarCornersSettingsRoundTrip(t *testing.T) {
	e := newTestEngine(t)
	dir := t.TempDir()
	v, err := utils.CreateVault(dir+"/vault.db", "test")
	if err != nil {
		t.Fatal(err)
	}
	cfg := utils.DefaultConfig()
	e.ForTestSetVault(v)
	e.ForTestSetConfig(&cfg)

	if got := utils.EffectiveAvatarCorners(*e.GetConfig()); got != 23 {
		t.Fatalf("default corners = %d, want 23", got)
	}

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

	off := false
	if err := e.UpdateConfigFromBridge(&ConfigChanges{AyuSingleCornerRadius: &off}); err != nil {
		t.Fatal(err)
	}
	if e.GetConfig().AyuSingleCornerRadius == nil || *e.GetConfig().AyuSingleCornerRadius {
		t.Fatal("config AyuSingleCornerRadius not persisted as false")
	}
}
