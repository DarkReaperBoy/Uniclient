package utils

import (
	"os"
	"path/filepath"
	"runtime"
	"strings"
)

// OverrideConfigDir, if non-empty, is used instead of the OS default config directory.
var OverrideConfigDir string

// OverrideCacheDir, if non-empty, is used instead of the OS default cache directory.
var OverrideCacheDir string

// AppConfigDir returns the platform-correct configuration directory for uniclient.
// The directory is created if it does not already exist.
func AppConfigDir() (string, error) {
	var base string
	if OverrideConfigDir != "" {
		base = OverrideConfigDir
	} else {
		d, err := os.UserConfigDir()
		if err != nil {
			return "", err
		}
		base = d
	}
	dir := filepath.Join(base, "uniclient")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", err
	}
	return dir, nil
}

// AppCacheDir returns the platform-correct cache directory for uniclient.
// The directory is created if it does not already exist.
func AppCacheDir() (string, error) {
	var base string
	if OverrideCacheDir != "" {
		base = OverrideCacheDir
	} else {
		d, err := os.UserCacheDir()
		if err != nil {
			return "", err
		}
		base = d
	}
	dir := filepath.Join(base, "uniclient")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", err
	}
	return dir, nil
}

// AppDownloadDir returns the download directory for uniclient.
// On Linux it respects $XDG_DOWNLOAD_DIR, falling back to ~/Downloads/uniclient.
// On other platforms it uses <home>/Downloads/uniclient.
// The directory is created if it does not already exist.
func AppDownloadDir() (string, error) {
	var base string

	if runtime.GOOS == "linux" {
		xdg := os.Getenv("XDG_DOWNLOAD_DIR")
		if xdg != "" {
			// XDG_DOWNLOAD_DIR may contain $HOME references
			xdg = strings.ReplaceAll(xdg, "$HOME", os.Getenv("HOME"))
			base = xdg
		}
	}

	if base == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return "", err
		}
		base = filepath.Join(home, "Downloads")
	}

	dir := filepath.Join(base, "uniclient")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", err
	}
	return dir, nil
}

// VaultPath returns the path to the uniclient vault file inside the config directory.
func VaultPath() (string, error) {
	cfgDir, err := AppConfigDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(cfgDir, "uniclient.vault"), nil
}
