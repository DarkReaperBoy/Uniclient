package utils

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// F-73 (slice 310): predictable-named files/dirs in the SHARED temp
// dir are plantable by any local account — pre-create
// /tmp/uniclient_resend and we write media into THEIR directory; plant
// a symlink at a predicted path (`iv_photo_%d.jpg`, `dc-backup.json`)
// and our os.Create/WriteFile truncates an attacker-chosen target
// (F-71 fixed traversal; this closes planting).
//
// Seam-RED (WORKLOG 310): undefined: PrivateCacheDir.

func TestPrivateCacheDirIsPrivateAndDeterministic(t *testing.T) {
	dir, err := PrivateCacheDir("unit-test-sub")
	if err != nil {
		t.Fatalf("PrivateCacheDir: %v", err)
	}
	if !filepath.IsAbs(dir) {
		t.Fatalf("not absolute: %q", dir)
	}
	fi, err := os.Stat(dir)
	if err != nil {
		t.Fatalf("dir not created: %v", err)
	}
	if perm := fi.Mode().Perm(); perm != 0o700 {
		t.Errorf("dir mode = %o, want 0700", perm)
	}
	// Deterministic per name: caches must survive across runs the way
	// the old /tmp paths did (Stat-reuse call sites depend on it).
	again, err := PrivateCacheDir("unit-test-sub")
	if err != nil || again != dir {
		t.Fatalf("not deterministic: %q vs %q (err %v)", dir, again, err)
	}
	// The whole point: NOT in the shared temp dir when a home cache
	// exists (a local attacker cannot pre-plant under our home).
	if base, cerr := os.UserCacheDir(); cerr == nil && base != "" {
		wantPrefix := filepath.Join(base, "uniclient") + string(os.PathSeparator)
		if !strings.HasPrefix(dir, wantPrefix) {
			t.Errorf("dir %q not under %q", dir, wantPrefix)
		}
		if strings.HasPrefix(dir, os.TempDir()+string(os.PathSeparator)) {
			t.Errorf("dir %q is in the SHARED temp dir — plantable", dir)
		}
	}
}

// TestNoPredictableTempJoinsLeft: source-scan pin — the four files
// that used to join os.TempDir() with FIXED names must be clean
// (comments skipped, slice-284 lesson). writeVoiceOgg's
// `dir = os.TempDir()` assignment is NOT a join: its files come from
// os.CreateTemp (random, O_EXCL) — safe.
func TestNoPredictableTempJoinsLeft(t *testing.T) {
	for _, file := range []string{
		"../engine/pending.go",
		"../engine/voicerec.go",
		"../cores/telegram.go",
		"../cores/deltachat.go",
	} {
		src, err := os.ReadFile(file)
		if err != nil {
			t.Fatalf("read %s: %v", file, err)
		}
		for _, line := range strings.Split(string(src), "\n") {
			trimmed := strings.TrimSpace(line)
			if strings.HasPrefix(trimmed, "//") {
				continue
			}
			if strings.Contains(line, "filepath.Join(os.TempDir(),") {
				t.Errorf("%s still joins the shared temp dir with a fixed name: %s", file, trimmed)
			}
		}
	}
}
