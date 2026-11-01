package gui

import (
	"slices"
	"testing"
)

func TestWebPickerHidesSocketOnlyBackends(t *testing.T) {
	web := pickerPlatformsFor("js")
	if len(web) == 0 {
		t.Fatal("js picker is empty — the web build must offer the fetch/WebSocket backends")
	}
	for _, p := range web {
		if !webConnectable[p.ID] {
			t.Errorf("js picker offers %q — it dials raw TCP, which no browser can do (§1.10)", p.ID)
		}
	}
	for _, id := range []string{"github", "matrix", "bale"} {
		if !slices.ContainsFunc(web, func(p platformMeta) bool { return p.ID == id }) {
			t.Errorf("js picker is missing %q (fetch/WebSocket backend, must be offered)", id)
		}
	}

	native := pickerPlatformsFor("linux")
	if len(native) != len(platforms) {
		t.Fatalf("native picker shows %d of %d backends — the filter must be js-only", len(native), len(platforms))
	}
	windows := pickerPlatformsFor("windows")
	if len(windows) != len(platforms) {
		t.Fatalf("windows picker shows %d of %d backends — the filter must be js-only", len(windows), len(platforms))
	}
}
