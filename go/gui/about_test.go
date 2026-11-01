package gui

import (
	"os"
	"path/filepath"
	"regexp"
	"runtime"
	"testing"
)

func TestShortcutRows(t *testing.T) {
	rows := shortcutRows()
	if len(rows) < 5 {
		t.Fatalf("shortcutRows = %d entries, want >= 5", len(rows))
	}
	for _, r := range rows {
		if r.key == "" || r.desc == "" {
			t.Errorf("malformed row %+v", r)
		}
	}
	want := map[string]bool{"Esc": false, "Ctrl+F": false, "Ctrl+Tab": false}
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
	if len(appVersion) < 3 || appVersion[0] < '0' || appVersion[0] > '9' {
		t.Errorf("appVersion = %q, expected numeric version", appVersion)
	}
}

func TestAppVersionMatchesReleaseLine(t *testing.T) {
	if runtime.GOOS == "js" {
		t.Skip("flake.nix is unreachable on js/wasm (no filesystem by design)")
	}
	data, err := os.ReadFile(filepath.Join("..", "flake.nix"))
	if err != nil {
		t.Skipf("flake.nix not readable from the test dir: %v", err)
	}
	m := regexp.MustCompile(`version = "([0-9]+\.[0-9]+\.[0-9]+)"`).FindSubmatch(data)
	if m == nil {
		t.Fatal(`no version = "x.y.z" line found in flake.nix — cannot check the About-page version`)
	}
	if string(m[1]) != appVersion {
		t.Fatalf("About-page appVersion = %q but the release line (flake.nix) is %q — bump appVersion in settings.go when cutting a release", appVersion, m[1])
	}
}

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
