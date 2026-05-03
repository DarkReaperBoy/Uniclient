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
	// Display
	Theme       string  `json:"theme"`
	AccentColor string  `json:"accent_color"`
	FontScale   float64 `json:"font_scale"`
	Language    string  `json:"language"`

	// Downloads
	DownloadDir  string `json:"download_dir"`
	MaxCacheSize int64  `json:"max_cache_size"` // bytes, 0 = unlimited, default 1GB

	// Network
	ProxyConfig  ProxyConfig       `json:"proxy_config"`
	DNSOverrides map[string]string `json:"dns_overrides"`
	DNSFallback  bool              `json:"dns_fallback"`

	// Privacy / Ghost Mode
	SendReadReceipts       bool `json:"send_read_receipts"`
	SendTyping             bool `json:"send_typing"`
	SendReadStories        bool `json:"send_read_stories"`
	SendOnlinePackets      bool `json:"send_online_packets"`
	SendOfflineAfterOnline bool `json:"send_offline_after_online"`
	MarkReadAfterAction    bool `json:"mark_read_after_action"`
	UseScheduledMessages   bool `json:"use_scheduled_messages"`
	SendWithoutSound       bool `json:"send_without_sound"`

	// Notifications
	NotifyDMs          bool `json:"notify_dms"`
	NotifyGroups       bool `json:"notify_groups"`
	NotifyMentionsOnly bool `json:"notify_mentions_only"`
}

// DefaultConfig returns an AppConfig populated with sensible defaults.
func DefaultConfig() AppConfig {
	return AppConfig{
		Theme:            "dark",
		AccentColor:      "#4f6ef7",
		FontScale:        1.0,
		Language:         "en",
		DownloadDir:      "",
		MaxCacheSize:     1 << 30, // 1GB
		ProxyConfig:      ProxyConfig{Type: "none", Host: "127.0.0.1", Port: "1080"},
		DNSOverrides:     make(map[string]string),
		DNSFallback:      true,
		SendReadReceipts:  true,
		SendTyping:        true,
		SendReadStories:   true,
		SendOnlinePackets: true,
		NotifyDMs:        true,
		NotifyGroups:     true,
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
