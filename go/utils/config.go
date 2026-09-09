package utils

import (
	"encoding/json"
	"errors"
	"os"
)

// ProxyConfig holds proxy connection settings. Mode: 0 = disabled,
// 1 = system, 2 = custom (the fields below apply in custom mode).
type ProxyConfig struct {
	Mode     int    `json:"mode,omitempty"`
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
	SendReadReceipts bool `json:"send_read_receipts"`
	// Local read marking (AyuGram LRead): mark chats read locally when
	// opened. SRead (SendReadReceipts) is independent — it controls whether
	// read receipts are SENT to the server.
	LocalReadMark          bool `json:"local_read_mark"`
	SendTyping             bool `json:"send_typing"`
	SendUploadProgress     bool `json:"send_upload_progress"`
	SendReadStories        bool `json:"send_read_stories"`
	SendOnlinePackets      bool `json:"send_online_packets"`
	SendOfflineAfterOnline bool `json:"send_offline_after_online"`
	MarkReadAfterAction    bool `json:"mark_read_after_action"`
	UseScheduledMessages   bool `json:"use_scheduled_messages"`
	SendWithoutSound       bool `json:"send_without_sound"`

	// Search
	RecentSearches []string `json:"recent_searches,omitempty"` // last 8 queries

	// Streamer mode (Ayu): blur names and photos in the UI for streams.
	StreamerMode bool `json:"streamer_mode"`

	// Ayu mark strings (settings_ayu): "" = the GUI defaults
	// ("— deleted", "edited ").
	AyuDeletedMark string `json:"ayu_deleted_mark,omitempty"`
	AyuEditedMark  string `json:"ayu_edited_mark,omitempty"`

	// Anti-recall saving (AyuGram Ayu preferences). Nil = engine defaults
	// (save deleted + history on, for bots off).
	AyuSaveDeleted *bool `json:"ayu_save_deleted,omitempty"`
	AyuSaveHistory *bool `json:"ayu_save_history,omitempty"`
	AyuSaveForBots *bool `json:"ayu_save_for_bots,omitempty"`

	// Bubble corner style (AyuGram appearance "Corners"). Nil = rounded.
	// Legacy boolean kept for older configs; superseded by BubbleRadius.
	BubbleCorners *bool `json:"bubble_corners,omitempty"`

	// Layout tweak sliders (AyuGram appearance, slice 93).
	// BubbleRadius: message-bubble corner radius, 0..18 dp; nil = derive
	// from the legacy BubbleCorners toggle (true 12 / false 2).
	// WideMultiplier: bubble max-width factor of the pane, 0.70..1.00;
	// nil = 0.75 (the previous fixed 3/4).
	BubbleRadius   *int     `json:"bubble_radius,omitempty"`
	WideMultiplier *float64 `json:"wide_multiplier,omitempty"`

	// Hide the "All chats" folder tab (AyuGram folder settings).
	HideAllChats bool `json:"hide_all_chats,omitempty"`

	// Drawer customization (Ayu "drawer" menu): ids of hidden rows.
	DrawerHiddenItems []string `json:"drawer_hidden_items,omitempty"`

	// Notifications
	NotifyDMs          bool `json:"notify_dms"`
	NotifyGroups       bool `json:"notify_groups"`
	NotifyMentionsOnly bool `json:"notify_mentions_only"`

	// Notification content privacy (AyuGram/Telegram "show previews"):
	// nil = default (show message text in banners).
	NotifyPreviews *bool `json:"notify_previews,omitempty"`

	// Call Devices
	CallOutputDevice string `json:"call_output_device,omitempty"`
	CallInputDevice  string `json:"call_input_device,omitempty"`
	CallCameraDevice string `json:"call_camera_device,omitempty"`
	// Separate call-only audio devices (AyuGram callPlaybackDeviceId/callCaptureDeviceId).
	// Empty means "use the same devices as the rest of the app" (the default).
	CallSeparateOutputDevice string `json:"call_separate_output_device,omitempty"`
	CallSeparateInputDevice  string `json:"call_separate_input_device,omitempty"`
	NoiseSuppression         bool   `json:"noise_suppression,omitempty"`
}

// DefaultConfig returns an AppConfig populated with sensible defaults.
func DefaultConfig() AppConfig {
	return AppConfig{
		Theme:              "dark",
		AccentColor:        "#4f6ef7",
		FontScale:          1.0,
		Language:           "en",
		DownloadDir:        "",
		MaxCacheSize:       1 << 30, // 1GB
		ProxyConfig:        ProxyConfig{Type: "none", Host: "127.0.0.1", Port: "1080"},
		DNSOverrides:       make(map[string]string),
		DNSFallback:        true,
		SendReadReceipts:   true,
		LocalReadMark:      true,
		SendTyping:         true,
		SendUploadProgress: true,
		SendReadStories:    true,
		SendOnlinePackets:  true,
		NotifyDMs:          true,
		NotifyGroups:       true,
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

// NotifyPreviewsEnabled resolves the preview pointer (nil = default true:
// message text shows in banners).
func (c *AppConfig) NotifyPreviewsEnabled() bool {
	return c.NotifyPreviews == nil || *c.NotifyPreviews
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

// ClampBubbleRadius bounds the bubble-corner slider (0..18 dp).
func ClampBubbleRadius(v int) int {
	if v < 0 {
		return 0
	}
	if v > 18 {
		return 18
	}
	return v
}

// ClampWideMultiplier bounds the bubble-width slider (0.70..1.00).
func ClampWideMultiplier(v float64) float64 {
	if v < 0.70 {
		return 0.70
	}
	if v > 1.00 {
		return 1.00
	}
	return v
}

// EffectiveBubbleRadius resolves the active bubble radius: the new
// slider value wins; older configs derive from the corners toggle. Pure.
func EffectiveBubbleRadius(cfg AppConfig) int {
	if cfg.BubbleRadius != nil {
		return ClampBubbleRadius(*cfg.BubbleRadius)
	}
	if cfg.BubbleCorners != nil && !*cfg.BubbleCorners {
		return 2
	}
	return 12
}

// EffectiveWideMultiplier resolves the active bubble-width factor. Pure.
func EffectiveWideMultiplier(cfg AppConfig) float64 {
	if cfg.WideMultiplier != nil {
		return ClampWideMultiplier(*cfg.WideMultiplier)
	}
	return 0.75
}
