package engine

import (
	"testing"
)

// effectiveAutoDownloadSettings fills the AyuGram-faithful defaults when
// nothing is stored (slice 63).
func TestEffectiveAutoDownloadSettingsDefaults(t *testing.T) {
	got := effectiveAutoDownloadSettings(nil)
	want := map[string]interface{}{
		"photos":        true,
		"files":         false,
		"videos":        true,
		"gifs":          true,
		"videoMessages": true,
		"downloadLimit": int64(10 * 1024 * 1024),
		"autoPlayLimit": int64(50 * 1024 * 1024),
	}
	for k, v := range want {
		if got[k] != v {
			t.Errorf("default %s = %v, want %v", k, got[k], v)
		}
	}
}

// Stored maps override defaults, tolerating the JSON-decoded (float64) and
// host-supplied (int/int64) number encodings (slice 63).
func TestEffectiveAutoDownloadSettingsMerge(t *testing.T) {
	got := effectiveAutoDownloadSettings(map[string]interface{}{
		"photos":        false,
		"files":         true,
		"videos":        false,
		"gifs":          false,
		"videoMessages": false,
		"downloadLimit": float64(1024),
		"autoPlayLimit": int(2048),
	})
	if v, _ := got["photos"].(bool); v {
		t.Error("photos should be off")
	}
	if v, _ := got["files"].(bool); !v {
		t.Error("files should be on")
	}
	if v, _ := got["videos"].(bool); v {
		t.Error("videos should be off")
	}
	if v, _ := got["gifs"].(bool); v {
		t.Error("gifs should be off")
	}
	if v, _ := got["videoMessages"].(bool); v {
		t.Error("video messages should be off")
	}
	if v, _ := got["downloadLimit"].(int64); v != 1024 {
		t.Errorf("downloadLimit = %d, want 1024", v)
	}
	if v, _ := got["autoPlayLimit"].(int64); v != 2048 {
		t.Errorf("autoPlayLimit = %d, want 2048", v)
	}
}

// int64-encoded limits (as stored by SetAutoDownloadSettings after a host
// round-trip) survive the merge untouched (slice 63).
func TestEffectiveAutoDownloadSettingsInt64(t *testing.T) {
	got := effectiveAutoDownloadSettings(map[string]interface{}{
		"downloadLimit": int64(0), // unlimited
		"autoPlayLimit": int64(500 * 1024 * 1024),
	})
	if v, _ := got["downloadLimit"].(int64); v != 0 {
		t.Errorf("downloadLimit = %d, want 0 (unlimited)", v)
	}
	if v, _ := got["autoPlayLimit"].(int64); v != 500*1024*1024 {
		t.Errorf("autoPlayLimit = %d", v)
	}
}

// GetAutoDownloadSettings returns effective settings for all three sources
// even with nothing stored (slice 63).
func TestGetAutoDownloadSettingsSources(t *testing.T) {
	e := &Engine{}
	got := e.GetAutoDownloadSettings()
	for _, source := range []string{"private", "group", "channel"} {
		if got[source] == nil {
			t.Fatalf("source %s missing", source)
		}
		if _, ok := got[source]["photos"].(bool); !ok {
			t.Errorf("source %s: photos not a bool", source)
		}
	}
}
