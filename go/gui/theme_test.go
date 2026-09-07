package gui

import (
	"testing"

	"uniclient/bootstrap"
)

// TestPlatformsAreRealBackends: every backend the picker offers must be a
// real, factory-supported platform. No fake/demo entries — AGENTS.md §1.10
// bans placeholders from the GUI.
func TestPlatformsAreRealBackends(t *testing.T) {
	supported := make(map[string]bool)
	for _, p := range bootstrap.SupportedPlatforms() {
		supported[p] = true
	}

	seen := make(map[string]bool)
	for _, p := range platforms {
		if p.ID == "" || p.Title == "" || p.Desc == "" {
			t.Errorf("platform %q has empty metadata fields", p.ID)
		}
		if seen[p.ID] {
			t.Errorf("duplicate platform %q in picker", p.ID)
		}
		seen[p.ID] = true
		if !supported[p.ID] {
			t.Errorf("picker offers %q but bootstrap cannot construct it", p.ID)
		}
	}

	for _, banned := range []string{"demo", "fake", "stub"} {
		if seen[banned] {
			t.Errorf("placeholder platform %q is offered in the GUI — banned (AGENTS.md §1.10)", banned)
		}
	}
}
