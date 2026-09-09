package gui

import (
	"testing"
)

// About page (slice 82): version + shortcut list.

func TestShortcutRows(t *testing.T) {
	rows := shortcutRows()
	if len(rows) < 5 {
		t.Fatalf("shortcutRows = %d entries, want >= 5", len(rows))
	}
	// Every row: non-empty key + description.
	for _, r := range rows {
		if r.key == "" || r.desc == "" {
			t.Errorf("malformed row %+v", r)
		}
	}
	// The core shortcuts from gui/shortcuts.go must be listed.
	want := map[string]bool{"Esc": false, "Ctrl+F": false}
	for _, r := range rows {
		if _, ok := want[r.key]; ok {
			want[r.key] = true
		}
	}
	for k, seen := range want {
		if !seen {
			t.Errorf("shortcut %q missing from the About list", k)
		}
	}
}

func TestAppVersionFormat(t *testing.T) {
	// Must look like a semver-ish dev or release string.
	if len(appVersion) < 3 || appVersion[0] < '0' || appVersion[0] > '9' {
		t.Errorf("appVersion = %q, expected numeric version", appVersion)
	}
}

// Bubble corners (slice 82): radius mapping + config mapping.

func TestBubbleRadiusFor(t *testing.T) {
	if got := bubbleRadiusFor(true); got != 12 {
		t.Errorf("rounded = %d, want 12", got)
	}
	if got := bubbleRadiusFor(false); got != 2 {
		t.Errorf("square = %d, want 2", got)
	}
}

func TestConfigFieldChangesBubbleCorners(t *testing.T) {
	c := configFieldChanges("bubble_corners", false)
	if c == nil || c.BubbleCorners == nil || *c.BubbleCorners {
		t.Fatalf("configFieldChanges(bubble_corners) = %+v, want pointer to false", c)
	}
}
