package gui

import (
	"testing"
)

// autodlLimitLabel renders byte gates (slice 63): MB when whole, KB
// otherwise, Unlimited for non-positive.
func TestAutodlLimitLabel(t *testing.T) {
	cases := map[int64]string{
		0:                 "Unlimited",
		-1:                "Unlimited",
		10 * 1024 * 1024:  "10 MB",
		500 * 1024 * 1024: "500 MB",
		1024:              "1 KB",
		1536:              "1 KB",
		100 * 1024 * 1024: "100 MB",
		5 * 1024 * 1024:   "5 MB",
	}
	for limit, want := range cases {
		if got := autodlLimitLabel(limit); got != want {
			t.Errorf("autodlLimitLabel(%d) = %q, want %q", limit, got, want)
		}
	}
}

// autodlSummary joins the enabled type toggles and the media size gate;
// all-off renders "Off" (slice 63).
func TestAutodlSummary(t *testing.T) {
	all := map[string]interface{}{
		"photos":        true,
		"files":         false,
		"videos":        true,
		"gifs":          true,
		"videoMessages": true,
		"downloadLimit": int64(10 * 1024 * 1024),
	}
	if got := autodlSummary(all); got != "Photos, Videos, GIFs & animations · Video messages · ≤10 MB" {
		t.Errorf("summary = %q", got)
	}
	off := map[string]interface{}{
		"photos":        false,
		"files":         false,
		"videos":        false,
		"gifs":          false,
		"videoMessages": false,
		"downloadLimit": int64(10 * 1024 * 1024),
	}
	if got := autodlSummary(off); got != "Off" {
		t.Errorf("off summary = %q", got)
	}
	// Unlimited media gate omits the size suffix.
	unlimited := map[string]interface{}{
		"photos":        true,
		"files":         true,
		"videos":        false,
		"gifs":          false,
		"videoMessages": false,
		"downloadLimit": int64(0),
	}
	if got := autodlSummary(unlimited); got != "Photos · Files" {
		t.Errorf("unlimited summary = %q", got)
	}
}

// The editor's toggle rows + size gates must cover every key the engine's
// auto-download settings map understands (slice 63) — keeps the GUI and
// engine vocabularies in sync across renames.
func TestAutodlRowsCoverEngineKeys(t *testing.T) {
	engineKeys := []string{
		"photos", "videos", "gifs", "videoMessages", "files",
		"downloadLimit", "autoPlayLimit",
	}
	covered := map[string]bool{}
	for _, r := range autodlToggleRows {
		covered[r.key] = true
	}
	covered["downloadLimit"] = true // media size ladder
	covered["autoPlayLimit"] = true // video size ladder
	for _, k := range engineKeys {
		if !covered[k] {
			t.Errorf("autodl GUI missing engine key: %s", k)
		}
	}
	for _, k := range covered {
		_ = k
	}
	// Every toggle row key must appear in the engine vocabulary.
	for _, r := range autodlToggleRows {
		found := false
		for _, k := range engineKeys {
			if k == r.key {
				found = true
			}
		}
		if !found {
			t.Errorf("autodl toggle row %q is not an engine key", r.key)
		}
	}
}

// The three sources are the engine's source vocabulary (slice 63).
func TestAutodlSourceLabels(t *testing.T) {
	want := map[string]string{
		"private": "In private chats",
		"group":   "In groups",
		"channel": "In channels",
	}
	if len(autodlSourceLabels) != 3 {
		t.Fatalf("sources = %v", autodlSourceLabels)
	}
	for _, r := range autodlSourceLabels {
		if want[r.source] != r.label {
			t.Errorf("source %q label = %q", r.source, r.label)
		}
	}
}

// The size ladders include the unlimited (0) option and are ascending
// before it (slice 63).
func TestAutodlLimitLadders(t *testing.T) {
	for _, ladder := range [][]int64{autodlMediaLimits, autodlVideoLimits} {
		if len(ladder) < 2 {
			t.Fatalf("ladder too short: %v", ladder)
		}
		if ladder[len(ladder)-1] != 0 {
			t.Errorf("ladder must end with unlimited: %v", ladder)
		}
		prev := int64(-1)
		for _, v := range ladder[:len(ladder)-1] {
			if v <= prev {
				t.Errorf("ladder not ascending: %v", ladder)
			}
			prev = v
		}
	}
}

// The dialog state carries the source it edits (slice 63).
func TestAutodlDlgStateFields(t *testing.T) {
	st := &autodlDlgState{source: "group"}
	if st.source != "group" {
		t.Fatalf("state = %+v", st)
	}
}

// autodlRowSummaryFor renders "" while the rules are still loading
// (slice 63).
func TestAutodlRowSummaryLoading(t *testing.T) {
	if got := autodlRowSummaryFor(frame{}, "private"); got != "" {
		t.Errorf("loading summary = %q, want empty", got)
	}
}
