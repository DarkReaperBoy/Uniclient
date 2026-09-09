package engine

import (
	"testing"

	"uniclient/utils"
)

// Local-read marking (AyuGram LRead drawer toggle, slice 75): the config
// flag gates the GUI's mark-on-open; round-trips through the same
// UpdateConfigFromBridge path as every other ghost flag.

func newLReadEngine(t *testing.T) *Engine {
	dir := t.TempDir()
	v, err := utils.CreateVault(dir+"/vault.db", "test")
	if err != nil {
		t.Fatal(err)
	}
	cfg := utils.DefaultConfig()
	return &Engine{vault: v, config: &cfg}
}

func TestLocalReadMarkDefaultOn(t *testing.T) {
	cfg := utils.DefaultConfig()
	if !cfg.LocalReadMark {
		t.Fatal("default config must mark chats read locally (LRead on)")
	}
}

func TestLocalReadMarkRoundTrip(t *testing.T) {
	e := newLReadEngine(t)
	off := false
	if err := e.UpdateConfigFromBridge(&ConfigChanges{LocalReadMark: &off}); err != nil {
		t.Fatal(err)
	}
	if e.GetConfig().LocalReadMark {
		t.Fatal("LRead off did not persist")
	}
	// The SendReadReceipts (SRead) flag stays independent.
	if e.GetConfig().SendReadReceipts != true {
		t.Fatal("SRead must be untouched by an LRead change")
	}
	on := true
	if err := e.UpdateConfigFromBridge(&ConfigChanges{LocalReadMark: &on, SendReadReceipts: &off}); err != nil {
		t.Fatal(err)
	}
	c := e.GetConfig()
	if !c.LocalReadMark || c.SendReadReceipts {
		t.Fatalf("round-trip: LRead=%v SRead=%v, want true/false", c.LocalReadMark, c.SendReadReceipts)
	}
}

func TestLocalReadMarkNilKeepsValue(t *testing.T) {
	e := newLReadEngine(t)
	off := false
	_ = e.UpdateConfigFromBridge(&ConfigChanges{LocalReadMark: &off})
	if err := e.UpdateConfigFromBridge(&ConfigChanges{}); err != nil {
		t.Fatal(err)
	}
	if e.GetConfig().LocalReadMark {
		t.Fatal("nil change must not reset LRead")
	}
}
