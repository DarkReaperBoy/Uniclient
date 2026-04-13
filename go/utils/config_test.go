package utils

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

func TestSaveAndLoadConfigRoundTrip(t *testing.T) {
	tmp := t.TempDir()
	path := filepath.Join(tmp, "config.json")

	original := &AppConfig{
		Theme:       "light",
		Language:    "fr",
		DownloadDir: "/tmp/downloads",
		ProxyConfig: ProxyConfig{
			Type:     "socks5",
			Host:     "proxy.example.com",
			Port:     "9050",
			Username: "user",
			Password: "pass",
		},
		DNSOverrides: map[string]string{"example.com": "1.2.3.4"},
		DNSFallback:  true,
	}

	if err := SaveConfig(path, original); err != nil {
		t.Fatalf("SaveConfig() error: %v", err)
	}

	loaded, err := LoadConfig(path)
	if err != nil {
		t.Fatalf("LoadConfig() error: %v", err)
	}

	if !reflect.DeepEqual(original, loaded) {
		t.Errorf("round-trip mismatch:\n  got  %+v\n  want %+v", loaded, original)
	}
}

func TestLoadConfigNonExistent(t *testing.T) {
	cfg, err := LoadConfig("/tmp/does_not_exist_uniclient_test.json")
	if err != nil {
		t.Fatalf("LoadConfig() on non-existent path should not error, got: %v", err)
	}
	def := DefaultConfig()
	if !reflect.DeepEqual(*cfg, def) {
		t.Errorf("expected default config, got %+v", cfg)
	}
}

func TestLoadConfigInvalidJSON(t *testing.T) {
	tmp := t.TempDir()
	path := filepath.Join(tmp, "bad.json")
	if err := writeFile(path, []byte("{invalid json!!}")); err != nil {
		t.Fatal(err)
	}
	_, err := LoadConfig(path)
	if err == nil {
		t.Fatal("LoadConfig() should return error for invalid JSON")
	}
}

func TestMergeDefaultsFillsEmpty(t *testing.T) {
	cfg := &AppConfig{}
	MergeDefaults(cfg)
	if cfg.Theme != "dark" {
		t.Errorf("Theme = %q, want %q", cfg.Theme, "dark")
	}
	if cfg.Language != "en" {
		t.Errorf("Language = %q, want %q", cfg.Language, "en")
	}
}

func TestMergeDefaultsPreservesExisting(t *testing.T) {
	cfg := &AppConfig{Theme: "light"}
	MergeDefaults(cfg)
	if cfg.Theme != "light" {
		t.Errorf("Theme = %q, want %q (should not be overwritten)", cfg.Theme, "light")
	}
}

func TestDefaultConfigNonZero(t *testing.T) {
	cfg := DefaultConfig()
	if cfg.Theme == "" {
		t.Error("Theme should not be empty")
	}
	if cfg.Language == "" {
		t.Error("Language should not be empty")
	}
	if cfg.DNSOverrides == nil {
		t.Error("DNSOverrides should not be nil")
	}
	if !cfg.DNSFallback {
		t.Error("DNSFallback should be true")
	}
	if cfg.ProxyConfig.Type == "" {
		t.Error("ProxyConfig.Type should not be empty")
	}
	if cfg.ProxyConfig.Host == "" {
		t.Error("ProxyConfig.Host should not be empty")
	}
	if cfg.ProxyConfig.Port == "" {
		t.Error("ProxyConfig.Port should not be empty")
	}
}

func writeFile(path string, data []byte) error {
	return os.WriteFile(path, data, 0o644)
}
