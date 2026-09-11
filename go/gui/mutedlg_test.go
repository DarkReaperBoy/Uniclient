package gui

// mutedlg_test.go — slice 134 tests-first: the mute-duration picker
// (tdesktop's "Mute for" presets: 1 hour / 8 hours / 2 days / forever,
// plus an Unmute row). Pure helpers: the preset table and the dialog's
// surface gate.

import (
	"testing"
)

func TestMutePresets(t *testing.T) {
	// tdesktop's exact preset list.
	if len(mutePresets) != 4 {
		t.Fatalf("mutePresets = %d entries, want 4", len(mutePresets))
	}
	want := []struct {
		label string
		secs  int
	}{
		{"1 hour", 3600},
		{"8 hours", 8 * 3600},
		{"2 days", 2 * 86400},
		{"Until turned back on", 0},
	}
	for i, w := range want {
		if mutePresets[i].label != w.label || mutePresets[i].secs != w.secs {
			t.Errorf("preset[%d] = %+v, want %+v", i, mutePresets[i], w)
		}
	}
}

func TestMutePresetAction(t *testing.T) {
	// Timed presets mute for their duration; forever keeps the plain
	// muted flag (secs 0 means "no timed expiry" in the engine wire).
	for _, c := range []struct {
		secs      int
		wantMuted bool
		wantDur   int32
	}{
		{3600, true, 3600},
		{8 * 3600, true, 8 * 3600},
		{2 * 86400, true, 2 * 86400},
		{0, true, 0},
	} {
		m, d := mutePresetAction(c.secs)
		if m != c.wantMuted || d != c.wantDur {
			t.Errorf("mutePresetAction(%d) = (%v, %d), want (%v, %d)",
				c.secs, m, d, c.wantMuted, c.wantDur)
		}
	}
}

func TestContentPaneDialogSurfaceMute(t *testing.T) {
	f := frame{muteDlg: &muteDlgState{accountID: "a", chatID: "c"}}
	if got := contentDialogSurface(f); got != "mute" {
		t.Errorf("mute dialog surface = %q, want mute", got)
	}
	// The passcode lock outranks the mute picker (security gate).
	f = frame{muteDlg: &muteDlgState{accountID: "a"}, lockDlg: &lockDlgState{}}
	if got := contentDialogSurface(f); got != "lock" {
		t.Errorf("mute + lock: = %q, want lock (security gate wins)", got)
	}
}
