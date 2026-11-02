package utils

import (
	"encoding/json"
	"errors"
	"os"
)

type ProxyConfig struct {
	Mode     int    `json:"mode,omitempty"`
	Type     string `json:"type"`
	Host     string `json:"host"`
	Port     string `json:"port"`
	Username string `json:"username"`
	Password string `json:"password"`
}

type AppConfig struct {
	Theme           string  `json:"theme"`
	AccentColor     string  `json:"accent_color"`
	FontScale       float64 `json:"font_scale"`
	Language        string  `json:"language"`
	TranslateTarget string  `json:"translate_target,omitempty"`
	FontPath        string  `json:"font_path,omitempty"`
	MonoFontPath    string  `json:"mono_font_path,omitempty"`

	MediaVolume *float64 `json:"media_volume,omitempty"`

	ComposerSubmit string `json:"composer_submit,omitempty"`
	SwipeAction    string `json:"swipe_action,omitempty"`

	CornerReply    *bool `json:"corner_reply,omitempty"`
	CornerReaction *bool `json:"corner_reaction,omitempty"`

	AyuImproveLinkPreviews bool  `json:"ayu_improve_link_previews,omitempty"`
	AyuMsgSeconds          *bool `json:"ayu_msg_seconds,omitempty"`
	AyuFilterZalgo         *bool `json:"ayu_filter_zalgo,omitempty"`
	AyuReactChannels       *bool `json:"ayu_react_channels,omitempty"`
	AyuReactGroups         *bool `json:"ayu_react_groups,omitempty"`
	AyuReactPrivate        *bool `json:"ayu_react_private,omitempty"`
	AyuConfirmSticker      *bool `json:"ayu_confirm_sticker,omitempty"`
	AyuConfirmGif          *bool `json:"ayu_confirm_gif,omitempty"`
	AyuConfirmVoice        *bool `json:"ayu_confirm_voice,omitempty"`

	AyuHideSimilarChannels     bool  `json:"ayu_hide_similar_channels,omitempty"`
	AyuCollapseSimilarChannels *bool `json:"ayu_collapse_similar_channels,omitempty"`

	AyuAppIcon            string `json:"ayu_app_icon,omitempty"`
	AyuAvatarCorners      *int   `json:"ayu_avatar_corners,omitempty"`
	AyuSingleCornerRadius *bool  `json:"ayu_single_corner_radius,omitempty"`
	PowerSavingFlags      int    `json:"power_saving_flags"`
	PowerSavingForceAll   bool   `json:"power_saving_force_all"`

	DownloadDir  string `json:"download_dir"`
	MaxCacheSize int64  `json:"max_cache_size"`

	ProxyConfig  ProxyConfig       `json:"proxy_config"`
	DNSOverrides map[string]string `json:"dns_overrides"`
	DNSFallback  bool              `json:"dns_fallback"`

	SendReadReceipts       bool `json:"send_read_receipts"`
	LocalReadMark          bool `json:"local_read_mark"`
	SendTyping             bool `json:"send_typing"`
	SendUploadProgress     bool `json:"send_upload_progress"`
	SendReadStories        bool `json:"send_read_stories"`
	SendOnlinePackets      bool `json:"send_online_packets"`
	SendOfflineAfterOnline bool `json:"send_offline_after_online"`
	MarkReadAfterAction    bool `json:"mark_read_after_action"`
	UseScheduledMessages   bool `json:"use_scheduled_messages"`
	SendWithoutSound       bool `json:"send_without_sound"`

	RecentSearches []string `json:"recent_searches,omitempty"`

	StreamerMode bool `json:"streamer_mode"`

	SystemTray *bool `json:"system_tray,omitempty"`

	AyuDeletedMark string `json:"ayu_deleted_mark,omitempty"`
	AyuEditedMark  string `json:"ayu_edited_mark,omitempty"`

	AyuSaveDeleted *bool `json:"ayu_save_deleted,omitempty"`
	AyuSaveHistory *bool `json:"ayu_save_history,omitempty"`
	AyuSaveForBots *bool `json:"ayu_save_for_bots,omitempty"`

	BubbleCorners *bool `json:"bubble_corners,omitempty"`

	BubbleRadius   *int     `json:"bubble_radius,omitempty"`
	WideMultiplier *float64 `json:"wide_multiplier,omitempty"`

	HideAllChats bool `json:"hide_all_chats,omitempty"`

	DrawerHiddenItems []string `json:"drawer_hidden_items,omitempty"`

	NotifyDMs          bool   `json:"notify_dms"`
	NotifyGroups       bool   `json:"notify_groups"`
	NotifyMentionsOnly bool   `json:"notify_mentions_only"`
	NotifySound        string `json:"notify_sound,omitempty"`

	NotifyPreviews *bool `json:"notify_previews,omitempty"`

	CallOutputDevice         string `json:"call_output_device,omitempty"`
	CallInputDevice          string `json:"call_input_device,omitempty"`
	CallCameraDevice         string `json:"call_camera_device,omitempty"`
	CallSeparateOutputDevice string `json:"call_separate_output_device,omitempty"`
	CallSeparateInputDevice  string `json:"call_separate_input_device,omitempty"`
	NoiseSuppression         bool   `json:"noise_suppression,omitempty"`
}

func DefaultConfig() AppConfig {
	return AppConfig{
		Theme:              "dark",
		AccentColor:        "#4f6ef7",
		FontScale:          1.0,
		Language:           "en",
		DownloadDir:        "",
		MaxCacheSize:       1 << 30,
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
		SwipeAction:        "disabled",
	}
}

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

func (c *AppConfig) NotifyPreviewsEnabled() bool {
	return c.NotifyPreviews == nil || *c.NotifyPreviews
}

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

func (c *AppConfig) MediaVolumeValue() float64 {
	if c == nil || c.MediaVolume == nil {
		return 1
	}
	return ClampMediaVolume(*c.MediaVolume)
}

func ClampMediaVolume(v float64) float64 {
	if v >= 0 && v <= 1 {
		return v
	}
	if v > 1 {
		return 1
	}
	return 0
}

func ClampBubbleRadius(v int) int {
	if v < 0 {
		return 0
	}
	if v > 18 {
		return 18
	}
	return v
}

func ClampAvatarCorners(v int) int {
	if v < 0 {
		return 0
	}
	if v > 23 {
		return 23
	}
	return v
}

func ClampWideMultiplier(v float64) float64 {
	if v < 0.70 {
		return 0.70
	}
	if v > 1.00 {
		return 1.00
	}
	return v
}

func EffectiveBubbleRadius(cfg AppConfig) int {
	if cfg.BubbleRadius != nil {
		return ClampBubbleRadius(*cfg.BubbleRadius)
	}
	if cfg.BubbleCorners != nil && !*cfg.BubbleCorners {
		return 2
	}
	return 12
}

func EffectiveAvatarCorners(cfg AppConfig) int {
	if cfg.AyuAvatarCorners != nil {
		return ClampAvatarCorners(*cfg.AyuAvatarCorners)
	}
	return 23
}

func EffectiveWideMultiplier(cfg AppConfig) float64 {
	if cfg.WideMultiplier != nil {
		return ClampWideMultiplier(*cfg.WideMultiplier)
	}
	return 0.75
}

func EffectiveSystemTray(cfg AppConfig) bool {
	return cfg.SystemTray == nil || *cfg.SystemTray
}

func EffectiveCollapseSimilar(cfg AppConfig) bool {
	return cfg.AyuCollapseSimilarChannels == nil || *cfg.AyuCollapseSimilarChannels
}
