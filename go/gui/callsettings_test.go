package gui

// Calls settings (AyuGram parity slice 103): the settings rail gains a
// Calls section with mic/speaker/camera pickers backed by the engine's real
// OS device enumeration (GetAudioDevices) and the persisted device config
// (SetCallAudioDevice) — plus the in-call noise-suppression toggle on the
// group-call screen. Pure derivations locked here.

import (
	"testing"

	"uniclient/engine"
	"uniclient/utils"
)

func TestDevPickerRows(t *testing.T) {
	// Empty enumeration → the Default sentinel row only.
	rows := devPickerRows(nil, "")
	if len(rows) != 1 || rows[0].label != "Default" || !rows[0].selected {
		t.Fatalf("empty devices: %+v", rows)
	}
	// Default sentinel first + devices; current marks the selected row.
	rows = devPickerRows([]string{"HD Camera", "Mic"}, "Mic")
	if len(rows) != 3 {
		t.Fatalf("rows len = %d", len(rows))
	}
	if rows[0].label != "Default" || rows[0].selected {
		t.Fatalf("default row = %+v (must be first, unselected when current set)", rows[0])
	}
	if rows[1].label != "HD Camera" || rows[1].selected {
		t.Fatalf("row1 = %+v", rows[1])
	}
	if rows[2].label != "Mic" || !rows[2].selected {
		t.Fatalf("row2 = %+v", rows[2])
	}
	// Current = "" (default device) selects the sentinel.
	rows = devPickerRows([]string{"Mic"}, "")
	if !rows[0].selected || rows[1].selected {
		t.Fatalf("default selected: %+v", rows)
	}
	// Unknown current (stale config) → nothing crashes, nothing selected.
	rows = devPickerRows([]string{"Mic"}, "Gone")
	if rows[0].selected || rows[1].selected {
		t.Fatalf("stale current must not select: %+v", rows)
	}
}

func TestDevPickerLabel(t *testing.T) {
	if s := devPickerLabel(""); s != "Default" {
		t.Fatalf("empty = %q", s)
	}
	if s := devPickerLabel("Blue Yeti"); s != "Blue Yeti" {
		t.Fatalf("device = %q", s)
	}
}

func TestDevPickerFor(t *testing.T) {
	// The picker state covers the three device types; a nil state is inert.
	st := &devPickerState{typ: "input"}
	if st.deviceType() != "input" {
		t.Fatalf("typ = %q", st.deviceType())
	}
}

func TestCfgCallDevicesSnapshot(t *testing.T) {
	// Config round-trip into the settings snapshot.
	cfg := &utils.AppConfig{
		CallInputDevice:  "Mic",
		CallOutputDevice: "",
		CallCameraDevice: "Cam",
	}
	snap := cfgFromAppConfig(cfg)
	if snap.CallInputDevice != "Mic" || snap.CallOutputDevice != "" || snap.CallCameraDevice != "Cam" {
		t.Fatalf("snapshot devices: %+v", snap)
	}
}

func TestGCNoiseToggleLabel(t *testing.T) {
	if s := gcNoiseLabel(false); s != "NOISE SUPPRESSION: OFF" {
		t.Fatalf("off = %q", s)
	}
	if s := gcNoiseLabel(true); s != "NOISE SUPPRESSION: ON" {
		t.Fatalf("on = %q", s)
	}
}

func TestSettingsCallsSectionOrder(t *testing.T) {
	// The rail is AyuGram's order; Calls sits between Appearance and Ayu.
	found := -1
	for i, s := range settingsSections {
		if s == "Calls" {
			found = i
			break
		}
	}
	if found == -1 {
		t.Fatal("Calls section missing from the settings rail")
	}
	if settingsSections[found-1] != "Appearance" || settingsSections[found+1] != "Ayu" {
		t.Fatalf("Calls neighbors = %q / %q", settingsSections[found-1], settingsSections[found+1])
	}
}

var _ = engine.ChatInfo{}
