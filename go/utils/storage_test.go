package utils

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestAppConfigDirOverride(t *testing.T) {
	tmp := t.TempDir()
	old := OverrideConfigDir
	OverrideConfigDir = tmp
	defer func() { OverrideConfigDir = old }()

	dir, err := AppConfigDir()
	if err != nil {
		t.Fatalf("AppConfigDir() error: %v", err)
	}
	expected := filepath.Join(tmp, "uniclient")
	if dir != expected {
		t.Errorf("got %q, want %q", dir, expected)
	}
	info, err := os.Stat(dir)
	if err != nil {
		t.Fatalf("directory not created: %v", err)
	}
	if !info.IsDir() {
		t.Fatalf("%q is not a directory", dir)
	}
}

func TestAppCacheDirOverride(t *testing.T) {
	tmp := t.TempDir()
	old := OverrideCacheDir
	OverrideCacheDir = tmp
	defer func() { OverrideCacheDir = old }()

	dir, err := AppCacheDir()
	if err != nil {
		t.Fatalf("AppCacheDir() error: %v", err)
	}
	expected := filepath.Join(tmp, "uniclient")
	if dir != expected {
		t.Errorf("got %q, want %q", dir, expected)
	}
	info, err := os.Stat(dir)
	if err != nil {
		t.Fatalf("directory not created: %v", err)
	}
	if !info.IsDir() {
		t.Fatalf("%q is not a directory", dir)
	}
}

func TestVaultPath(t *testing.T) {
	tmp := t.TempDir()
	old := OverrideConfigDir
	OverrideConfigDir = tmp
	defer func() { OverrideConfigDir = old }()

	vp, err := VaultPath()
	if err != nil {
		t.Fatalf("VaultPath() error: %v", err)
	}
	if !strings.HasSuffix(vp, "uniclient.vault") {
		t.Errorf("VaultPath() = %q, want suffix 'uniclient.vault'", vp)
	}
}

func TestAppDownloadDir(t *testing.T) {
	dir, err := AppDownloadDir()
	if err != nil {
		t.Fatalf("AppDownloadDir() error: %v", err)
	}
	if !strings.HasSuffix(dir, filepath.Join("uniclient")) {
		t.Errorf("AppDownloadDir() = %q, want path ending in 'uniclient'", dir)
	}
	info, err := os.Stat(dir)
	if err != nil {
		t.Fatalf("directory not created: %v", err)
	}
	if !info.IsDir() {
		t.Fatalf("%q is not a directory", dir)
	}
}
