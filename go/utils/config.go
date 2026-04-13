package utils

import (
	"encoding/json"
	"errors"
	"os"
)

// ProxyConfig holds proxy connection settings.
type ProxyConfig struct {
	Type     string `json:"type"`
	Host     string `json:"host"`
	Port     string `json:"port"`
	Username string `json:"username"`
	Password string `json:"password"`
}

// AppConfig holds the application configuration.
type AppConfig struct {
	Theme        string            `json:"theme"`
	Language     string            `json:"language"`
	DownloadDir  string            `json:"download_dir"`
	ProxyConfig  ProxyConfig       `json:"proxy_config"`
	DNSOverrides map[string]string `json:"dns_overrides"`
	DNSFallback  bool              `json:"dns_fallback"`
}

// DefaultConfig returns an AppConfig populated with sensible defaults.
func DefaultConfig() AppConfig {
	return AppConfig{
		Theme:        "dark",
		Language:     "en",
		DownloadDir:  "",
		ProxyConfig:  ProxyConfig{Type: "none", Host: "127.0.0.1", Port: "1080"},
		DNSOverrides: make(map[string]string),
		DNSFallback:  true,
	}
}

// LoadConfig reads a JSON config file from path. If the file does not exist,
// it returns a pointer to DefaultConfig with no error. If the file contains
// invalid JSON, it returns an error.
func LoadConfig(path string) (*AppConfig, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			cfg := DefaultConfig()
			return &cfg, nil
		}
		return nil, err
	}

	var cfg AppConfig
	if err := json.Unmarshal(data, &cfg); err != nil {
		return nil, err
	}
	return &cfg, nil
}

// SaveConfig writes cfg to path as indented JSON.
func SaveConfig(path string, cfg *AppConfig) error {
	data, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, data, 0o644)
}

// MergeDefaults fills zero-valued fields in cfg with values from DefaultConfig.
func MergeDefaults(cfg *AppConfig) {
	defaults := DefaultConfig()
	if cfg.Theme == "" {
		cfg.Theme = defaults.Theme
	}
	if cfg.Language == "" {
		cfg.Language = defaults.Language
	}
	if cfg.DownloadDir == "" {
		cfg.DownloadDir = defaults.DownloadDir
	}
	if cfg.ProxyConfig.Type == "" {
		cfg.ProxyConfig.Type = defaults.ProxyConfig.Type
	}
	if cfg.ProxyConfig.Host == "" {
		cfg.ProxyConfig.Host = defaults.ProxyConfig.Host
	}
	if cfg.ProxyConfig.Port == "" {
		cfg.ProxyConfig.Port = defaults.ProxyConfig.Port
	}
	if cfg.DNSOverrides == nil {
		cfg.DNSOverrides = defaults.DNSOverrides
	}
	if !cfg.DNSFallback {
		cfg.DNSFallback = defaults.DNSFallback
	}
}
