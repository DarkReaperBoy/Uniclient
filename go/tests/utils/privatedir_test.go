package tests

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	. "uniclient/utils"
)

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
	again, err := PrivateCacheDir("unit-test-sub")
	if err != nil || again != dir {
		t.Fatalf("not deterministic: %q vs %q (err %v)", dir, again, err)
	}
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

func TestNoPredictableTempJoinsLeft(t *testing.T) {
	for _, file := range []string{
		"../../engine/pending.go",
		"../../engine/voicerec.go",
		"../../cores/telegram.go",
		"../../cores/deltachat.go",
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
