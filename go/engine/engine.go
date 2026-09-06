package engine

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"log"
	"net"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	"golang.org/x/net/proxy"

	"uniclient/cores"
	"uniclient/utils"
)

// ConnState represents the connection state of an account.
type ConnState int

const (
	ConnDisconnected ConnState = iota
	ConnConnecting
	ConnConnected
	ConnUnstable
)

// Account holds the live state for a connected platform account.
type Account struct {
	ID          string
	Platform    string
	DisplayName string
	Phone       string
	Username    string
	Core        cores.Core
	ConnState   ConnState
	SortOrder   int
	IsVerified  bool
	IsPremium   bool

	// reconnect state
	reconnect  reconnectState
	lastEvent  time.Time
	cancelFunc context.CancelFunc // cancels this account's goroutines
}

// Engine is the orchestration layer between cores and the host UI.
type Engine struct {
	mu     sync.RWMutex
	db     *sql.DB
	vault  *utils.Vault
	config *utils.AppConfig

	accounts   map[string]*Account // accountID → live account
	accountsMu sync.RWMutex

	eventCB func([]byte) // push serialized events to the host

	configDir   string
	cacheDir    string
	downloadDir string
	mediaDir    string
	maxCache    int64 // bytes, 0 = unlimited

	activeChat struct {
		mu        sync.Mutex
		accountID string
		chatID    string
	}

	media   *MediaManager
	avatars *avatarState

	lockFile     *os.File // single-instance lock file (held open with flock)
	shuttingDown bool
	wg           sync.WaitGroup // tracks background goroutines

	// Anti-recall settings (§52): controlled from the host via SetAntiRecallSettings.
	antiRecallMu        sync.RWMutex
	saveDeletedMessages bool
	saveMessagesHistory bool
	saveForBots         bool

	exportMu sync.RWMutex
	exports  map[string]*exportState

	// Export-ready suggestion scheduling (AyuGram Session::suggestStartExport):
	// per-account timer that fires when a delayed takeout becomes available,
	// emitting EventExportSuggest so the host shows the "Data export ready" box.
	exportSuggestMu     sync.Mutex
	exportSuggestTimers map[string]*time.Timer

	// Proxy settings: controlled from the host via SetProxy.
	proxyMu       sync.RWMutex
	proxyMode     int // 0=disabled, 1=system, 2=custom
	proxyHost     string
	proxyPort     int
	proxyType     string // socks5, http, mtproto
	proxyUser     string
	proxyPass     string
	proxySecret   string
	proxyIPv6     bool
	proxyForCalls bool
	// Proxy rotation (AyuGram SettingsProxy.proxyRotationEnabled/Timeout):
	// rotate through the proxy list every proxyRotationTimeout seconds.
	proxyRotationEnabled bool
	proxyRotationTimeout int

	// Auto-download settings: per-source limits controlled from the host via SetAutoDownload.
	autoDownloadMu       sync.RWMutex
	autoDownloadSettings map[string]map[string]interface{}

	// Per-account ghost overrides (AyuGram per-session ghost resolution,
	// ayu_settings.cpp:437 ghost(uint64 userId)). When an account has an entry
	// here, its ghost flags take precedence over the global config; otherwise
	// the global config applies. Populated from the host when the user picks
	// "individual settings for each account".
	ghostMu        sync.RWMutex
	ghostOverrides map[string]GhostFlags

	// Power saving flags bitmap from host UI.
	powerSavingFlags int
	// powerSavingForceAll mirrors AyuGram PowerSaving::ForceAll (auto power
	// saving): when true, every power-saving flag is treated as enabled.
	powerSavingForceAll bool

	// Local storage limits from host UI.
	localStorageTotalMB  int
	localStorageMediaMB  int
	localStorageTimeDays int

	experimentalFlagsMu sync.RWMutex
	experimentalFlags   map[string]bool
}

// Init initializes the engine: opens vault+DB, loads accounts, starts connections.
// configDir: path to config directory (contains vault, config.json)
// cacheDir: path to cache directory (contains cache.db, media/)
// downloadDir: path to user downloads directory
// vaultPassword: password for the encrypted vault (empty string = no vault encryption)
func Init(configDir, cacheDir, downloadDir, vaultPassword string) (*Engine, error) {
	e := &Engine{
		accounts:            make(map[string]*Account),
		configDir:           configDir,
		cacheDir:            cacheDir,
		downloadDir:         downloadDir,
		mediaDir:            filepath.Join(cacheDir, "media"),
		maxCache:            1 << 30, // 1GB default
		avatars:             newAvatarState(),
		saveDeletedMessages: true,
		saveMessagesHistory: true,
		saveForBots:         false,
	}

	// Ensure directories exist.
	for _, d := range []string{configDir, cacheDir, downloadDir, e.mediaDir} {
		if err := os.MkdirAll(d, 0o755); err != nil {
			return nil, fmt.Errorf("create dir %s: %w", d, err)
		}
	}

	// Single-instance lock — prevent two copies from running simultaneously.
	lockPath := filepath.Join(configDir, "uniclient.lock")
	lf, err := acquireLock(lockPath)
	if err != nil {
		return nil, err
	}
	e.lockFile = lf

	// Open or create vault (stores credentials, config, and sessions).
	vaultPath := filepath.Join(configDir, "uniclient.vault")
	if _, err := os.Stat(vaultPath); os.IsNotExist(err) {
		e.vault, err = utils.CreateVault(vaultPath, vaultPassword)
		if err != nil {
			return nil, fmt.Errorf("create vault: %w", err)
		}
	} else {
		e.vault, err = utils.OpenVault(vaultPath, vaultPassword)
		if err != nil {
			return nil, fmt.Errorf("open vault: %w", err)
		}
	}

	// Migrate old uniconfig file into vault if present.
	uniConfigPath := filepath.Join(configDir, "uniconfig")
	if _, statErr := os.Stat(uniConfigPath); statErr == nil {
		_ = e.vault.MigrateUniConfig(uniConfigPath)
	}

	// Migrate old config.json if present.
	oldCfgPath := filepath.Join(configDir, "config.json")
	if _, statErr := os.Stat(oldCfgPath); statErr == nil {
		if cfg, cfgErr := utils.LoadConfig(oldCfgPath); cfgErr == nil {
			_ = e.vault.SetConfig(cfg)
		}
		os.Remove(oldCfgPath)
	}

	cfg := e.vault.Config()
	utils.MergeDefaults(cfg)
	e.config = cfg

	if cfg.MaxCacheSize > 0 {
		e.maxCache = cfg.MaxCacheSize
	}

	// Open SQLite database.
	e.db, err = OpenDB(cacheDir)
	if err != nil {
		e.vault.Close()
		return nil, fmt.Errorf("open db: %w", err)
	}

	// Migrate old DB+vault account data into unified vault entries.
	e.migrateAccountsToVault()

	// Load accounts from vault (source of truth), sync DB cache.
	if err := e.loadAccounts(); err != nil {
		e.db.Close()
		e.vault.Close()
		return nil, fmt.Errorf("load accounts: %w", err)
	}

	// Resume pending operations from crash.
	e.resumePending()

	// Start media download manager.
	e.media = newMediaManager(e)
	e.media.Start(context.Background())

	return e, nil
}

// Vault returns the vault (stores credentials, config, sessions).
func (e *Engine) Vault() *utils.Vault {
	return e.vault
}

func (e *Engine) MediaDir() string {
	return e.mediaDir
}

// SetEventCallback sets the function called when async events are pushed to the host.
// The callback receives serialized event bytes.
func (e *Engine) SetEventCallback(cb func([]byte)) {
	e.mu.Lock()
	defer e.mu.Unlock()
	e.eventCB = cb
}

// pushEvent sends an event to the host side. Safe to call from any goroutine.
func (e *Engine) pushEvent(data []byte) {
	e.mu.RLock()
	cb := e.eventCB
	e.mu.RUnlock()
	if cb != nil {
		cb(data)
	}
}

// SetAntiRecallSettings updates the anti-recall settings (§52).
func (e *Engine) SetAntiRecallSettings(saveDeleted, saveHistory, saveForBots bool) {
	e.antiRecallMu.Lock()
	defer e.antiRecallMu.Unlock()
	e.saveDeletedMessages = saveDeleted
	e.saveMessagesHistory = saveHistory
	e.saveForBots = saveForBots
}

// proxyConfigurable is implemented by cores that can dial through a proxy.
type proxyConfigurable interface {
	SetProxyConfig(cores.ProxyConfig)
}

// SetProxy updates the engine proxy settings and pushes them to every live core
// so the change takes effect on the next (re)connect. Mirrors AyuGram's
// Application::setCurrentProxy (core/application.cpp:836), which installs the
// proxy into MTProto and reconnects sessions.
func (e *Engine) SetProxy(mode int, host string, port int, proxyType, user, pass, secret string, ipv6, forCalls, rotationEnabled bool, rotationTimeout int) {
	// Normalize the proxy type to the lowercase tokens the dialer expects
	// ("socks5"/"http"/"mtproto"). the host sends the uppercase display label
	// ("SOCKS5"/"HTTP"/"MTPROTO"), but ProxyConfig.active()/resolver()/dialFunc()
	// (cores/proxy.go) compare case-sensitively against lowercase. Without this
	// active() returns false for every real proxy, no resolver is installed, and
	// every connection silently dials direct.
	proxyType = strings.ToLower(strings.TrimSpace(proxyType))
	e.proxyMu.Lock()
	e.proxyMode = mode
	e.proxyHost = host
	e.proxyPort = port
	e.proxyType = proxyType
	e.proxyUser = user
	e.proxyPass = pass
	e.proxySecret = secret
	e.proxyIPv6 = ipv6
	e.proxyForCalls = forCalls
	e.proxyRotationEnabled = rotationEnabled
	e.proxyRotationTimeout = rotationTimeout
	e.proxyMu.Unlock()
	log.Printf("[engine] SetProxy: mode=%d type=%s host=%s:%d ipv6=%v forCalls=%v rotation=%v/%ds",
		mode, proxyType, host, port, ipv6, forCalls, rotationEnabled, rotationTimeout)
	e.applyProxyToAllCores()
}

// currentProxyConfig builds the cores.ProxyConfig from the engine's stored proxy
// settings. Only mode 2 (custom) installs a proxy; 0 (disabled) and 1 (system)
// fall back to the default direct dialer.
func (e *Engine) currentProxyConfig() cores.ProxyConfig {
	e.proxyMu.RLock()
	defer e.proxyMu.RUnlock()
	return cores.ProxyConfig{
		Enabled:  e.proxyMode == 2,
		Type:     e.proxyType,
		Host:     e.proxyHost,
		Port:     e.proxyPort,
		Username: e.proxyUser,
		Password: e.proxyPass,
		Secret:   e.proxySecret,
		IPv6:     e.proxyIPv6,
	}
}

// applyProxyToCore pushes the current proxy config to a single core (if it
// supports proxying). Called right after a core is created so a saved proxy is
// installed before the first connect.
func (e *Engine) applyProxyToCore(core cores.Core) {
	if core == nil {
		return
	}
	if pc, ok := core.(proxyConfigurable); ok {
		pc.SetProxyConfig(e.currentProxyConfig())
	}
}

// applyProxyToAllCores pushes the current proxy config to every live core.
func (e *Engine) applyProxyToAllCores() {
	cfg := e.currentProxyConfig()
	e.accountsMu.RLock()
	cs := make([]cores.Core, 0, len(e.accounts))
	for _, acc := range e.accounts {
		if acc.Core != nil {
			cs = append(cs, acc.Core)
		}
	}
	e.accountsMu.RUnlock()
	for _, c := range cs {
		if pc, ok := c.(proxyConfigurable); ok {
			pc.SetProxyConfig(cfg)
		}
	}
}

// SetAutoDownloadSettings stores per-source auto-download limits.
func (e *Engine) SetAutoDownloadSettings(source string, settings map[string]interface{}) {
	e.autoDownloadMu.Lock()
	if e.autoDownloadSettings == nil {
		e.autoDownloadSettings = make(map[string]map[string]interface{})
	}
	e.autoDownloadSettings[source] = settings
	e.autoDownloadMu.Unlock()
	log.Printf("[engine] SetAutoDownload: source=%s settings=%v", source, settings)
}

// ShouldAutoDownload reports whether a freshly-received attachment of the given
// media type and size should be auto-downloaded for the given source
// ("private"/"group"/"channel"), per the limits stored via
// SetAutoDownloadSettings. Mirrors AyuGram's Data::AutoDownload per-source /
// per-type bytesLimit gating (boxes/auto_download_box.cpp): a type only
// auto-downloads when its toggle is on and the file is within the size limit.
// When a source has no stored settings the AyuGram-faithful defaults apply
// (photos/videos/GIFs/round videos on, files off; 10 MB / 50 MB limits) so the
// feature works out of the box, matching the host getAutoDownloadForSource
// defaults.
func (e *Engine) ShouldAutoDownload(source string, mediaType int, fileSize int64) bool {
	e.autoDownloadMu.RLock()
	settings := e.autoDownloadSettings[source]
	e.autoDownloadMu.RUnlock()

	photos, files, videos, gifs, videoMsgs := true, false, true, true, true
	var downloadLimit int64 = 10 * 1024 * 1024
	var autoPlayLimit int64 = 50 * 1024 * 1024

	if settings != nil {
		boolOf := func(k string, def bool) bool {
			if v, ok := settings[k].(bool); ok {
				return v
			}
			return def
		}
		limitOf := func(k string, def int64) int64 {
			switch v := settings[k].(type) {
			case float64:
				return int64(v)
			case int:
				return int64(v)
			case int64:
				return v
			}
			return def
		}
		photos = boolOf("photos", photos)
		files = boolOf("files", files)
		videos = boolOf("videos", videos)
		gifs = boolOf("gifs", gifs)
		videoMsgs = boolOf("videoMessages", videoMsgs)
		downloadLimit = limitOf("downloadLimit", downloadLimit)
		autoPlayLimit = limitOf("autoPlayLimit", autoPlayLimit)
	}

	within := func(limit int64) bool { return limit <= 0 || fileSize <= limit }

	switch mediaType {
	case MediaImage:
		return photos && within(downloadLimit)
	case MediaFile, MediaAudio:
		return files && within(downloadLimit)
	case MediaVideo:
		return videos && within(autoPlayLimit)
	case MediaGIF:
		return gifs && within(autoPlayLimit)
	case MediaVideoNote:
		return videoMsgs && within(autoPlayLimit)
	default:
		return false
	}
}

// SetPasscode stores the full passcode config in the vault.
func (e *Engine) SetPasscode(data map[string]interface{}) error {
	if err := e.vault.Put("passcode", "config", data); err != nil {
		return err
	}
	return e.vault.Save()
}

// GetPasscodeConfig reads the passcode config from the vault.
func (e *Engine) GetPasscodeConfig() (map[string]interface{}, error) {
	var data map[string]interface{}
	if err := e.vault.Get("passcode", "config", &data); err != nil {
		if errors.Is(err, utils.ErrBucketNotFound) || errors.Is(err, utils.ErrKeyNotFound) {
			return nil, nil
		}
		return nil, err
	}
	return data, nil
}

// ClearPasscode removes the passcode config from the vault.
func (e *Engine) ClearPasscode() error {
	_ = e.vault.Delete("passcode", "config")
	return e.vault.Save()
}

// UpdatePasscodeConfig merges fields into the existing passcode config.
func (e *Engine) UpdatePasscodeConfig(updates map[string]interface{}) error {
	data, err := e.GetPasscodeConfig()
	if err != nil {
		return err
	}
	if data == nil {
		return fmt.Errorf("no passcode set")
	}
	for k, v := range updates {
		data[k] = v
	}
	if err := e.vault.Put("passcode", "config", data); err != nil {
		return err
	}
	return e.vault.Save()
}

// SetPowerSaving stores the power-saving flags bitmap and the force-all flag
// (auto power saving) from the host UI. forceAll maps to the host
// PowerSaving::SetForceAll: when set, every flag is treated as enabled.
func (e *Engine) SetPowerSaving(flags int, forceAll bool) {
	e.powerSavingFlags = flags
	e.powerSavingForceAll = forceAll
	log.Printf("[engine] SetPowerSaving: flags=0x%X forceAll=%v", flags, forceAll)
}

func (e *Engine) SetExperimentalFlag(id string, value bool) {
	e.experimentalFlagsMu.Lock()
	if e.experimentalFlags == nil {
		e.experimentalFlags = make(map[string]bool)
	}
	if value {
		e.experimentalFlags[id] = true
	} else {
		delete(e.experimentalFlags, id)
	}
	e.experimentalFlagsMu.Unlock()
	log.Printf("[engine] SetExperimentalFlag: %s=%v", id, value)
}

// SetLocalStorageLimits stores cache eviction limits from the host UI.
func (e *Engine) SetLocalStorageLimits(totalMB, mediaMB, timeDays int) {
	e.localStorageTotalMB = totalMB
	e.localStorageMediaMB = mediaMB
	e.localStorageTimeDays = timeDays
	if totalMB > 0 {
		e.maxCache = int64(totalMB) * 1024 * 1024
	}
	log.Printf("[engine] SetLocalStorageLimits: total=%dMB media=%dMB time=%ddays", totalMB, mediaMB, timeDays)
}

// CheckProxy tests proxy connectivity by connecting to a Telegram DC through it.
// Returns ping time in milliseconds on success.
func (e *Engine) CheckProxy(host string, port int, proxyType, user, pass, secret string) (int64, error) {
	addr := net.JoinHostPort(host, strconv.Itoa(port))
	start := time.Now()

	var conn net.Conn
	var err error

	// Lowercase to match the protocol cases below — the host may pass an uppercase
	// display label, which would otherwise fall through to the default (a bare
	// TCP dial that wrongly reports any reachable host as a working proxy).
	switch strings.ToLower(strings.TrimSpace(proxyType)) {
	case "socks5":
		dialer, dErr := proxy.SOCKS5("tcp", addr, nil, proxy.Direct)
		if dErr != nil {
			return 0, dErr
		}
		conn, err = dialer.Dial("tcp", "149.154.167.50:443")
	case "http":
		conn, err = net.DialTimeout("tcp", addr, 5*time.Second)
		if err != nil {
			return 0, err
		}
		connectReq := fmt.Sprintf("CONNECT 149.154.167.50:443 HTTP/1.1\r\nHost: 149.154.167.50:443\r\n\r\n")
		if _, wErr := conn.Write([]byte(connectReq)); wErr != nil {
			conn.Close()
			return 0, wErr
		}
		buf := make([]byte, 1024)
		conn.SetReadDeadline(time.Now().Add(5 * time.Second))
		n, rErr := conn.Read(buf)
		if rErr != nil {
			conn.Close()
			return 0, rErr
		}
		resp := string(buf[:n])
		if !strings.Contains(resp, "200") {
			conn.Close()
			return 0, fmt.Errorf("HTTP proxy returned: %s", strings.TrimSpace(strings.SplitN(resp, "\r\n", 2)[0]))
		}
	case "mtproto":
		conn, err = net.DialTimeout("tcp", addr, 5*time.Second)
	default:
		conn, err = net.DialTimeout("tcp", addr, 5*time.Second)
	}

	if err != nil {
		return 0, err
	}
	conn.Close()

	pingMs := time.Since(start).Milliseconds()
	return pingMs, nil
}

// SetActiveChat tells the engine which chat the user is looking at.
// Notifications for this chat are suppressed.
func (e *Engine) SetActiveChat(accountID, chatID string) {
	e.activeChat.mu.Lock()
	e.activeChat.accountID = accountID
	e.activeChat.chatID = chatID
	e.activeChat.mu.Unlock()
}

// ClearActiveChat clears the active chat (user navigated away).
func (e *Engine) ClearActiveChat() {
	e.activeChat.mu.Lock()
	e.activeChat.accountID = ""
	e.activeChat.chatID = ""
	e.activeChat.mu.Unlock()
}

// isActiveChat returns true if the given chat is the one the user is currently viewing.
func (e *Engine) isActiveChat(accountID, chatID string) bool {
	e.activeChat.mu.Lock()
	defer e.activeChat.mu.Unlock()
	return e.activeChat.accountID == accountID && e.activeChat.chatID == chatID
}

// GetConfig returns the current app config.
func (e *Engine) GetConfig() *utils.AppConfig {
	e.mu.RLock()
	defer e.mu.RUnlock()
	return e.config
}

// UpdateConfig merges changes into the current config and saves to disk.
func (e *Engine) UpdateConfig(changes *utils.AppConfig) error {
	e.mu.Lock()
	defer e.mu.Unlock()

	if changes.Theme != "" {
		e.config.Theme = changes.Theme
	}
	if changes.Language != "" {
		e.config.Language = changes.Language
	}
	if changes.AccentColor != "" {
		e.config.AccentColor = changes.AccentColor
	}
	if changes.MaxCacheSize > 0 {
		e.config.MaxCacheSize = changes.MaxCacheSize
		e.maxCache = changes.MaxCacheSize
	}

	return e.vault.SetConfig(e.config)
}

// ConfigChanges holds partial config updates from the bridge layer.
// Zero values are treated as "no change" (except MaxCacheSize where 0 means unlimited).
type ConfigChanges struct {
	Theme        string
	AccentColor  string
	FontScale    float64
	Language     string
	MaxCacheSize int64
	DownloadDir  string
	// Use pointers for booleans so zero-value (false) is distinguishable from "not set".
	SendReadReceipts       *bool
	SendTyping             *bool
	SendUploadProgress     *bool
	SendReadStories        *bool
	SendOnlinePackets      *bool
	SendOfflineAfterOnline *bool
	MarkReadAfterAction    *bool
	UseScheduledMessages   *bool
	SendWithoutSound       *bool
	NotifyDMs              *bool
	NotifyGroups           *bool
	NotifyMentionsOnly     *bool
}

// UpdateConfigFromBridge applies partial config changes from the bridge layer.
func (e *Engine) UpdateConfigFromBridge(changes *ConfigChanges) error {
	e.mu.Lock()
	defer e.mu.Unlock()

	if changes.Theme != "" {
		e.config.Theme = changes.Theme
	}
	if changes.AccentColor != "" {
		e.config.AccentColor = changes.AccentColor
	}
	if changes.FontScale != 0 {
		e.config.FontScale = changes.FontScale
	}
	if changes.Language != "" {
		e.config.Language = changes.Language
	}
	if changes.MaxCacheSize > 0 {
		e.config.MaxCacheSize = changes.MaxCacheSize
		e.maxCache = changes.MaxCacheSize
	}
	if changes.DownloadDir != "" {
		e.config.DownloadDir = changes.DownloadDir
	}
	if changes.SendReadReceipts != nil {
		e.config.SendReadReceipts = *changes.SendReadReceipts
	}
	if changes.SendTyping != nil {
		e.config.SendTyping = *changes.SendTyping
	}
	if changes.SendUploadProgress != nil {
		e.config.SendUploadProgress = *changes.SendUploadProgress
	}
	if changes.SendReadStories != nil {
		e.config.SendReadStories = *changes.SendReadStories
	}
	if changes.SendOnlinePackets != nil {
		e.config.SendOnlinePackets = *changes.SendOnlinePackets
	}
	if changes.SendOfflineAfterOnline != nil {
		e.config.SendOfflineAfterOnline = *changes.SendOfflineAfterOnline
	}
	if changes.MarkReadAfterAction != nil {
		e.config.MarkReadAfterAction = *changes.MarkReadAfterAction
	}
	if changes.UseScheduledMessages != nil {
		e.config.UseScheduledMessages = *changes.UseScheduledMessages
	}
	if changes.SendWithoutSound != nil {
		e.config.SendWithoutSound = *changes.SendWithoutSound
	}
	if changes.NotifyDMs != nil {
		e.config.NotifyDMs = *changes.NotifyDMs
	}
	if changes.NotifyGroups != nil {
		e.config.NotifyGroups = *changes.NotifyGroups
	}
	if changes.NotifyMentionsOnly != nil {
		e.config.NotifyMentionsOnly = *changes.NotifyMentionsOnly
	}

	return e.vault.SetConfig(e.config)
}

// GhostFlags holds the per-account ghost-mode toggles (AyuGram
// GhostModeAccountSettings). Mirrors the 8 ghost fields of the global config.
type GhostFlags struct {
	SendReadReceipts       bool
	SendUploadProgress     bool
	SendReadStories        bool
	SendOnlinePackets      bool
	SendOfflineAfterOnline bool
	MarkReadAfterAction    bool
	UseScheduledMessages   bool
	SendWithoutSound       bool
}

// SetAccountGhost stores a per-account ghost override. When set, GhostFor
// returns these flags for the account instead of the global config — so
// simultaneously-connected accounts each enforce their own ghost profile.
func (e *Engine) SetAccountGhost(accountID string, g GhostFlags) {
	e.ghostMu.Lock()
	defer e.ghostMu.Unlock()
	if e.ghostOverrides == nil {
		e.ghostOverrides = make(map[string]GhostFlags)
	}
	e.ghostOverrides[accountID] = g
}

// ClearAccountGhostOverrides removes every per-account ghost override, so the
// global config applies to all accounts again (global Ghost Mode).
func (e *Engine) ClearAccountGhostOverrides() {
	e.ghostMu.Lock()
	defer e.ghostMu.Unlock()
	e.ghostOverrides = nil
}

// GhostFor resolves the effective ghost flags for an account: the per-account
// override if one is registered, otherwise the global config's ghost flags.
// AyuGram resolves ghost per session/userId (ayu_settings.cpp:437).
func (e *Engine) GhostFor(accountID string) GhostFlags {
	e.ghostMu.RLock()
	g, ok := e.ghostOverrides[accountID]
	e.ghostMu.RUnlock()
	if ok {
		return g
	}
	cfg := e.GetConfig()
	return GhostFlags{
		SendReadReceipts:       cfg.SendReadReceipts,
		SendUploadProgress:     cfg.SendUploadProgress,
		SendReadStories:        cfg.SendReadStories,
		SendOnlinePackets:      cfg.SendOnlinePackets,
		SendOfflineAfterOnline: cfg.SendOfflineAfterOnline,
		MarkReadAfterAction:    cfg.MarkReadAfterAction,
		UseScheduledMessages:   cfg.UseScheduledMessages,
		SendWithoutSound:       cfg.SendWithoutSound,
	}
}

// Shutdown gracefully shuts down the engine: stops accepting operations,
// flushes pending writes, closes all cores, saves vault, closes DB.
func (e *Engine) Shutdown() error {
	e.mu.Lock()
	e.shuttingDown = true
	e.mu.Unlock()

	// Stop any pending export-ready suggestion timers.
	e.cancelAllExportSuggests()

	// Cancel all account goroutines.
	e.accountsMu.RLock()
	for _, acc := range e.accounts {
		if acc.cancelFunc != nil {
			acc.cancelFunc()
		}
	}
	e.accountsMu.RUnlock()

	// Wait for background goroutines (with timeout).
	done := make(chan struct{})
	go func() {
		e.wg.Wait()
		close(done)
	}()
	select {
	case <-done:
	case <-time.After(5 * time.Second):
	}

	// Save vault.
	if e.vault != nil {
		e.vault.Save()
	}

	// Close DB.
	if e.db != nil {
		e.db.Close()
	}

	// Release single-instance lock.
	if e.lockFile != nil {
		releaseLock(e.lockFile)
		e.lockFile = nil
	}

	return nil
}

// LeaveChat removes the current user from a chat/channel/room. For DMs this
// deletes the local chat history. After leaving, triggers a sync so the chat
// disappears from the list.
func (e *Engine) JoinChannel(accountID, chatID string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}

	type channelJoiner interface {
		JoinChannel(chatID string) error
	}
	j, ok := acc.Core.(channelJoiner)
	if !ok {
		return fmt.Errorf("platform does not support JoinChannel")
	}
	if err := j.JoinChannel(chatID); err != nil {
		return err
	}

	e.db.Exec("UPDATE chats SET not_joined = 0 WHERE account_id = ? AND chat_id = ?", accountID, chatID)

	e.emitEvent(EventChatUpdated, accountID, map[string]string{
		"account_id": accountID,
		"chat_id":    chatID,
	})

	return nil
}

func (e *Engine) LeaveChat(accountID, chatID string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}

	if err := acc.Core.LeaveChat(chatID); err != nil {
		return err
	}

	// Remove from local cache.
	e.db.Exec("DELETE FROM messages WHERE account_id = ? AND chat_id = ?", accountID, chatID)
	e.db.Exec("DELETE FROM chats WHERE account_id = ? AND chat_id = ?", accountID, chatID)
	e.db.Exec("DELETE FROM media WHERE account_id = ? AND chat_id = ?", accountID, chatID)

	// Emit chat_removed event so the host updates the list.
	e.emitEvent(EventChatRemoved, accountID, map[string]string{
		"account_id": accountID,
		"chat_id":    chatID,
	})

	return nil
}

func (e *Engine) EditChatTitle(accountID, chatID, title string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}
	if err := acc.Core.EditChatTitle(chatID, title); err != nil {
		return err
	}
	e.db.Exec("UPDATE chats SET title = ? WHERE account_id = ? AND chat_id = ?", title, accountID, chatID)
	go func() {
		ctx := context.Background()
		e.syncAccount(ctx, accountID)
	}()
	return nil
}

func (e *Engine) EditChatDescription(accountID, chatID, description string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}
	return acc.Core.EditChatDescription(chatID, description)
}

func (e *Engine) ToggleForum(accountID, chatID string, enabled bool) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}
	type forumToggler interface {
		ToggleForum(chatID string, enabled bool) error
	}
	ft, ok := acc.Core.(forumToggler)
	if !ok {
		return fmt.Errorf("core does not support forum toggle")
	}
	if err := ft.ToggleForum(chatID, enabled); err != nil {
		return err
	}
	go func() {
		ctx := context.Background()
		e.syncAccount(ctx, accountID)
	}()
	return nil
}

// ToggleForumTabs forwards both the enabled and tabs/list-layout choice from
// AyuGram's ToggleTopicsBox to the core (channels.toggleForum tabs flag).
func (e *Engine) ToggleForumTabs(accountID, chatID string, enabled, tabs bool) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}
	type forumTabsToggler interface {
		ToggleForumTabs(chatID string, enabled, tabs bool) error
	}
	ft, ok := acc.Core.(forumTabsToggler)
	if !ok {
		return fmt.Errorf("core does not support forum tabs toggle")
	}
	if err := ft.ToggleForumTabs(chatID, enabled, tabs); err != nil {
		return err
	}
	go func() {
		ctx := context.Background()
		e.syncAccount(ctx, accountID)
	}()
	return nil
}

func (e *Engine) SetForumViewAsMessages(accountID, chatID string, asMessages bool) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}
	type viewToggler interface {
		ToggleViewForumAsMessages(chatID string, enabled bool) error
	}
	vt, ok := acc.Core.(viewToggler)
	if !ok {
		return fmt.Errorf("core does not support forum view toggle")
	}
	return vt.ToggleViewForumAsMessages(chatID, asMessages)
}

// ClearHistory deletes the message history for a chat on the server and locally,
// but keeps the chat visible in the chat list.
func (e *Engine) ClearHistory(accountID, chatID string, revoke bool) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}

	// Platform-specific history deletion. Prefer the revoke-aware variant so
	// "Also delete for everyone" actually deletes server-side for both sides.
	type historyDeleterRevoke interface {
		DeleteChatHistoryWithRevoke(chatID string, revoke bool) error
	}
	type historyDeleter interface {
		DeleteChatHistory(chatID string) error
	}
	if hd, ok := acc.Core.(historyDeleterRevoke); ok {
		if err := hd.DeleteChatHistoryWithRevoke(chatID, revoke); err != nil {
			return err
		}
	} else if hd, ok := acc.Core.(historyDeleter); ok {
		if err := hd.DeleteChatHistory(chatID); err != nil {
			return err
		}
	}

	// Remove messages from local cache.
	e.db.Exec("DELETE FROM messages WHERE account_id = ? AND chat_id = ?", accountID, chatID)
	e.db.Exec("DELETE FROM media WHERE account_id = ? AND chat_id = ?", accountID, chatID)

	// Emit event so the host can refresh the chat view.
	e.emitEvent(EventChatUpdated, accountID, map[string]string{
		"account_id": accountID,
		"chat_id":    chatID,
	})

	return nil
}

// DeleteChat deletes a chat entirely — clears history and removes the chat.
// For groups/channels this is equivalent to leave + delete. For DMs it clears
// history and removes the chat from the list.
func (e *Engine) DeleteChat(accountID, chatID string, revoke bool) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}

	// Clear server-side history first. Prefer the revoke-aware variant so a
	// "delete for everyone" conversation removal wipes both sides.
	type historyDeleterRevoke interface {
		DeleteChatHistoryWithRevoke(chatID string, revoke bool) error
	}
	type historyDeleter interface {
		DeleteChatHistory(chatID string) error
	}
	if hd, ok := acc.Core.(historyDeleterRevoke); ok {
		_ = hd.DeleteChatHistoryWithRevoke(chatID, revoke) // best-effort
	} else if hd, ok := acc.Core.(historyDeleter); ok {
		_ = hd.DeleteChatHistory(chatID) // best-effort
	}

	// Remove from local cache.
	e.db.Exec("DELETE FROM messages WHERE account_id = ? AND chat_id = ?", accountID, chatID)
	e.db.Exec("DELETE FROM chats WHERE account_id = ? AND chat_id = ?", accountID, chatID)
	e.db.Exec("DELETE FROM media WHERE account_id = ? AND chat_id = ?", accountID, chatID)

	// Emit chat_removed event so the host updates the list.
	e.emitEvent(EventChatRemoved, accountID, map[string]string{
		"account_id": accountID,
		"chat_id":    chatID,
	})

	return nil
}

// JoinChat joins a channel/room/group by name. For IRC this is a channel name
// like "#freenode", for Mumble it's a channel ID, etc. After joining, triggers
// a sync so the chat appears in the list.
func (e *Engine) JoinChat(accountID, channelName string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}

	// Platform-specific join. Use the core's exported methods directly.
	type joiner interface {
		JoinKey(channel, key string)
	}
	type roomJoiner interface {
		JoinRoom(roomID string) error
	}
	type channelMover interface {
		MoveToChannel(channelID uint32) error
	}

	switch j := acc.Core.(type) {
	case joiner:
		j.JoinKey(channelName, "")
	case roomJoiner:
		if err := j.JoinRoom(channelName); err != nil {
			return err
		}
	case channelMover:
		// Mumble — channelName is a numeric channel ID.
		id, err := strconv.ParseUint(channelName, 10, 32)
		if err != nil {
			return fmt.Errorf("invalid channel ID %q: %w", channelName, err)
		}
		if err := j.MoveToChannel(uint32(id)); err != nil {
			return err
		}
	default:
		return fmt.Errorf("platform %q does not support joining channels", acc.Platform)
	}

	// Re-sync chats so the new channel appears.
	go func() {
		ctx := context.Background()
		e.syncAccount(ctx, accountID)
	}()

	return nil
}

// CreateChannel creates a new broadcast channel with a name and description.
// Returns the created chat info after syncing it to the local cache.
func (e *Engine) CreateChannel(accountID, name, description string) (*ChatInfo, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account %q not found or not connected", accountID)
	}

	dialog, err := acc.Core.CreateChannel(name, description)
	if err != nil {
		return nil, err
	}

	// Upsert the new channel into the local cache.
	if err := e.UpsertChat(accountID, *dialog); err != nil {
		return nil, fmt.Errorf("failed to cache new channel: %w", err)
	}

	// Re-sync so the chat list updates for the host side.
	go func() {
		ctx := context.Background()
		e.syncAccount(ctx, accountID)
	}()

	// Return the created chat info.
	return &ChatInfo{
		AccountID:   accountID,
		ChatID:      dialog.ID,
		Type:        ChatTypeChanVal,
		Title:       dialog.Title,
		MemberCount: dialog.MemberCount,
	}, nil
}

func (e *Engine) CreateGroup(accountID, name string, members []string) (*ChatInfo, error) {
	return e.CreateGroupWithTTL(accountID, name, members, 0)
}

func (e *Engine) CreateGroupWithTTL(accountID, name string, members []string, ttlSeconds int) (*ChatInfo, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account %q not found or not connected", accountID)
	}

	type ttlCreator interface {
		CreateGroupWithTTL(name string, members []string, ttlSeconds int) (*cores.Dialog, error)
	}
	var dialog *cores.Dialog
	var err error
	if tc, ok := acc.Core.(ttlCreator); ok && ttlSeconds > 0 {
		dialog, err = tc.CreateGroupWithTTL(name, members, ttlSeconds)
	} else {
		dialog, err = acc.Core.CreateGroup(name, members)
	}
	if err != nil {
		return nil, err
	}

	if err := e.UpsertChat(accountID, *dialog); err != nil {
		return nil, fmt.Errorf("failed to cache new group: %w", err)
	}

	go func() {
		ctx := context.Background()
		e.syncAccount(ctx, accountID)
	}()

	return &ChatInfo{
		AccountID:   accountID,
		ChatID:      dialog.ID,
		Type:        ChatTypeGroupVal,
		Title:       dialog.Title,
		MemberCount: dialog.MemberCount,
	}, nil
}

func (e *Engine) CreateMegagroup(accountID, name, description string, forum bool, ttlPeriod int) (*ChatInfo, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account %q not found or not connected", accountID)
	}

	type fullCreator interface {
		RawCreateChannelFull(name, description string, broadcast, megagroup, forum bool, ttlPeriod int) (*cores.Dialog, error)
	}
	type rawCreator interface {
		RawCreateChannel(name, description string, broadcast, megagroup bool) (*cores.Dialog, error)
	}

	var dialog *cores.Dialog
	var err error
	if fc, ok := acc.Core.(fullCreator); ok {
		dialog, err = fc.RawCreateChannelFull(name, description, false, true, forum, ttlPeriod)
	} else if rc, ok := acc.Core.(rawCreator); ok {
		dialog, err = rc.RawCreateChannel(name, description, false, true)
	} else {
		dialog, err = acc.Core.CreateChannel(name, description)
	}
	if err != nil {
		return nil, err
	}

	if err := e.UpsertChat(accountID, *dialog); err != nil {
		return nil, fmt.Errorf("failed to cache new megagroup: %w", err)
	}

	go func() {
		ctx := context.Background()
		e.syncAccount(ctx, accountID)
	}()

	chatType := ChatTypeChanVal
	return &ChatInfo{
		AccountID:   accountID,
		ChatID:      dialog.ID,
		Type:        chatType,
		Title:       dialog.Title,
		MemberCount: dialog.MemberCount,
	}, nil
}

// AddMembers adds users to a group or channel.
func (e *Engine) AddMembers(accountID, chatID string, userIDs []string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}
	return acc.Core.AddMembers(chatID, userIDs)
}

// SendScheduledNow immediately sends previously scheduled messages.
// Only supported by cores that implement the scheduledSender interface
// (e.g. Telegram with CapScheduled capability).
func (e *Engine) SendScheduledNow(accountID, chatID string, msgIDs []string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}

	type scheduledSender interface {
		SendScheduledNow(chatID string, msgIDs []int) error
	}
	ss, ok := acc.Core.(scheduledSender)
	if !ok {
		return fmt.Errorf("core for account %q does not support scheduled messages", accountID)
	}

	// Convert string IDs to ints for the core method.
	intIDs := make([]int, 0, len(msgIDs))
	for _, id := range msgIDs {
		n, err := strconv.Atoi(id)
		if err != nil {
			return fmt.Errorf("invalid message ID %q: %w", id, err)
		}
		intIDs = append(intIDs, n)
	}

	return ss.SendScheduledNow(chatID, intIDs)
}

func (e *Engine) RescheduleMessage(accountID, chatID, msgID string, scheduleDate int64) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}

	type scheduledRescheduler interface {
		RescheduleMessage(chatID string, msgID int, scheduleDate int) error
	}
	sr, ok := acc.Core.(scheduledRescheduler)
	if !ok {
		return fmt.Errorf("core for account %q does not support rescheduling", accountID)
	}

	n, err := strconv.Atoi(msgID)
	if err != nil {
		return fmt.Errorf("invalid message ID %q: %w", msgID, err)
	}

	return sr.RescheduleMessage(chatID, n, int(scheduleDate))
}

func (e *Engine) GetScheduledCount(accountID, chatID string) (int, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return 0, nil
	}

	type scheduledGetter interface {
		GetScheduledMessages(chatID string) ([]cores.Message, error)
	}
	sg, ok := acc.Core.(scheduledGetter)
	if !ok {
		return 0, nil
	}

	msgs, err := sg.GetScheduledMessages(chatID)
	if err != nil {
		return 0, err
	}
	return len(msgs), nil
}

func (e *Engine) GetScheduledMessages(accountID, chatID string) ([]CachedMessage, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account %q not found or not connected", accountID)
	}

	type scheduledGetter interface {
		GetScheduledMessages(chatID string) ([]cores.Message, error)
	}
	sg, ok := acc.Core.(scheduledGetter)
	if !ok {
		return nil, nil
	}

	msgs, err := sg.GetScheduledMessages(chatID)
	if err != nil {
		return nil, err
	}

	result := make([]CachedMessage, len(msgs))
	for i, m := range msgs {
		hasMedia := len(m.Attachments) > 0
		result[i] = CachedMessage{
			AccountID:    accountID,
			ChatID:       chatID,
			MsgID:        m.ID,
			SenderID:     m.SenderID,
			SenderName:   m.SenderName,
			ContentText:  m.Text,
			Timestamp:    m.Timestamp.UnixMilli(),
			ScheduleDate: m.Timestamp.Unix(),
			IsOutgoing:   m.IsOutgoing,
			HasMedia:     hasMedia,
			PaidPostType: m.PaidPostType,
		}
		if m.Extra != nil {
			if v, ok := m.Extra["is_silent"].(bool); ok && v {
				result[i].IsSilent = true
			}
			if v, ok := m.Extra["schedule_repeat_period"].(int); ok {
				result[i].ScheduleRepeatPeriod = v
			}
		}
		if hasMedia {
			att := m.Attachments[0]
			result[i].MediaType = guessMediaType(att.MimeType, att.Name)
			result[i].MediaFileName = att.Name
			result[i].MediaMimeType = att.MimeType
			result[i].MediaFileSize = att.Size
			result[i].MediaThumbB64 = att.ThumbB64
			result[i].MediaWidth = att.Width
			result[i].MediaHeight = att.Height
			result[i].MediaDuration = att.Duration
		}
	}
	return result, nil
}

func (e *Engine) GetUnreadMentions(accountID, chatID string, limit int) ([]CachedMessage, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account %q not found or not connected", accountID)
	}
	type mentionsGetter interface {
		GetUnreadMentions(chatID string, limit int) ([]cores.Message, error)
	}
	mg, ok := acc.Core.(mentionsGetter)
	if !ok {
		return nil, nil
	}
	msgs, err := mg.GetUnreadMentions(chatID, limit)
	if err != nil {
		return nil, err
	}
	result := make([]CachedMessage, len(msgs))
	for i, m := range msgs {
		result[i] = CachedMessage{
			AccountID:   accountID,
			ChatID:      chatID,
			MsgID:       m.ID,
			SenderID:    m.SenderID,
			SenderName:  m.SenderName,
			ContentText: m.Text,
			Timestamp:   m.Timestamp.UnixMilli(),
			IsOutgoing:  m.IsOutgoing,
		}
	}
	return result, nil
}

func (e *Engine) GetUnreadPollVotes(accountID, chatID string, limit int) ([]CachedMessage, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account %q not found or not connected", accountID)
	}
	type pollVotesGetter interface {
		GetUnreadPollVotes(chatID string, limit int) ([]cores.Message, error)
	}
	pg, ok := acc.Core.(pollVotesGetter)
	if !ok {
		return nil, nil
	}
	msgs, err := pg.GetUnreadPollVotes(chatID, limit)
	if err != nil {
		return nil, err
	}
	result := make([]CachedMessage, len(msgs))
	for i, m := range msgs {
		result[i] = CachedMessage{
			AccountID:   accountID,
			ChatID:      chatID,
			MsgID:       m.ID,
			SenderID:    m.SenderID,
			SenderName:  m.SenderName,
			ContentText: m.Text,
			Timestamp:   m.Timestamp.UnixMilli(),
			IsOutgoing:  m.IsOutgoing,
		}
	}
	return result, nil
}

func (e *Engine) GetUnreadReactions(accountID, chatID string, limit int) ([]CachedMessage, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account %q not found or not connected", accountID)
	}
	type reactionsGetter interface {
		GetUnreadReactions(chatID string, limit int) ([]cores.Message, error)
	}
	rg, ok := acc.Core.(reactionsGetter)
	if !ok {
		return nil, nil
	}
	msgs, err := rg.GetUnreadReactions(chatID, limit)
	if err != nil {
		return nil, err
	}
	result := make([]CachedMessage, len(msgs))
	for i, m := range msgs {
		result[i] = CachedMessage{
			AccountID:   accountID,
			ChatID:      chatID,
			MsgID:       m.ID,
			SenderID:    m.SenderID,
			SenderName:  m.SenderName,
			ContentText: m.Text,
			Timestamp:   m.Timestamp.UnixMilli(),
			IsOutgoing:  m.IsOutgoing,
		}
	}
	return result, nil
}

func (e *Engine) GetMessageReactorsList(accountID, chatID string, msgID, limit int, offset, reactionFilter string) ([]cores.Reaction, string, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, "", fmt.Errorf("account %q not found or not connected", accountID)
	}
	type reactorsGetter interface {
		GetMessageReactionsList(chatID string, msgID int, limit int, offset string, reactionFilter string) ([]cores.Reaction, string, error)
	}
	rg, ok := acc.Core.(reactorsGetter)
	if !ok {
		return nil, "", nil
	}
	return rg.GetMessageReactionsList(chatID, msgID, limit, offset, reactionFilter)
}

func (e *Engine) GetOutboxReadDate(accountID, chatID, msgID string) (int, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return 0, fmt.Errorf("account %q not found or not connected", accountID)
	}
	type readDateGetter interface {
		GetOutboxReadDate(chatID, msgID string) (int, error)
	}
	rg, ok := acc.Core.(readDateGetter)
	if !ok {
		return 0, fmt.Errorf("GetOutboxReadDate not supported for this platform")
	}
	return rg.GetOutboxReadDate(chatID, msgID)
}

func (e *Engine) GetMessageReadParticipants(accountID, chatID, msgID string) ([]int64, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account %q not found or not connected", accountID)
	}
	type readParticipantsGetter interface {
		GetMessageReadParticipants(chatID, msgID string) ([]int64, error)
	}
	rp, ok := acc.Core.(readParticipantsGetter)
	if !ok {
		return nil, fmt.Errorf("GetMessageReadParticipants not supported for this platform")
	}
	return rp.GetMessageReadParticipants(chatID, msgID)
}

func (e *Engine) GetMessageReadParticipantsDetailed(accountID, chatID, msgID string) ([]map[string]interface{}, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account %q not found or not connected", accountID)
	}
	type detailedGetter interface {
		GetMessageReadParticipantsDetailedJSON(chatID, msgID string) ([]map[string]interface{}, error)
	}
	if dg, ok := acc.Core.(detailedGetter); ok {
		return dg.GetMessageReadParticipantsDetailedJSON(chatID, msgID)
	}
	return nil, fmt.Errorf("GetMessageReadParticipantsDetailed not supported for this platform")
}

func (e *Engine) GetInviteLink(accountID, chatID string) (string, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return "", fmt.Errorf("account %q not found or not connected", accountID)
	}
	return acc.Core.GetInviteLink(chatID)
}

func (e *Engine) CheckChannelUsername(accountID, chatID, username string) (bool, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return false, fmt.Errorf("account %q not found or not connected", accountID)
	}
	type checker interface {
		CheckChannelUsername(chatID, username string) (bool, error)
	}
	if c, ok := acc.Core.(checker); ok {
		return c.CheckChannelUsername(chatID, username)
	}
	return false, fmt.Errorf("platform does not support channel username check")
}

func (e *Engine) CheckAccountUsername(accountID, username string) (bool, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return false, fmt.Errorf("account %q not found or not connected", accountID)
	}
	type checker interface {
		AccountCheckUsername(username string) (bool, error)
	}
	if c, ok := acc.Core.(checker); ok {
		return c.AccountCheckUsername(username)
	}
	return false, fmt.Errorf("platform does not support account username check")
}

func (e *Engine) UpdateAccountUsername(accountID, username string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}
	type updater interface {
		UpdateUsername(username string) error
	}
	if u, ok := acc.Core.(updater); ok {
		return u.UpdateUsername(username)
	}
	return fmt.Errorf("platform does not support account username update")
}

func (e *Engine) GetAccountUsernames(accountID string) ([]cores.ChannelUsernameInfo, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account %q not found or not connected", accountID)
	}
	type getter interface {
		GetAccountUsernames() ([]cores.ChannelUsernameInfo, error)
	}
	if g, ok := acc.Core.(getter); ok {
		return g.GetAccountUsernames()
	}
	return nil, fmt.Errorf("platform does not support account usernames")
}

func (e *Engine) ToggleAccountUsername(accountID, username string, active bool) (bool, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return false, fmt.Errorf("account %q not found or not connected", accountID)
	}
	type toggler interface {
		ToggleAccountUsername(username string, active bool) (bool, error)
	}
	if t, ok := acc.Core.(toggler); ok {
		return t.ToggleAccountUsername(username, active)
	}
	return false, fmt.Errorf("platform does not support account username toggle")
}

func (e *Engine) ReorderAccountUsernames(accountID string, order []string) (bool, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return false, fmt.Errorf("account %q not found or not connected", accountID)
	}
	type reorderer interface {
		ReorderAccountUsernames(order []string) (bool, error)
	}
	if r, ok := acc.Core.(reorderer); ok {
		return r.ReorderAccountUsernames(order)
	}
	return false, fmt.Errorf("platform does not support account username reorder")
}

func (e *Engine) UpdateChannelUsername(accountID, chatID, username string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}
	type updater interface {
		UpdateChannelUsername(chatID, username string) error
	}
	if u, ok := acc.Core.(updater); ok {
		return u.UpdateChannelUsername(chatID, username)
	}
	return fmt.Errorf("platform does not support channel username update")
}

func (e *Engine) GetChatUsername(accountID, chatID string) (string, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return "", fmt.Errorf("account %q not found or not connected", accountID)
	}
	type usernameGetter interface {
		GetChatUsername(chatID string) (string, error)
	}
	if g, ok := acc.Core.(usernameGetter); ok {
		return g.GetChatUsername(chatID)
	}
	return "", fmt.Errorf("platform does not support chat username lookup")
}

type PublicLinkInfo struct {
	ChatID    string `json:"chat_id"`
	Title     string `json:"title"`
	Username  string `json:"username"`
	AvatarB64 string `json:"avatar_b64,omitempty"`
}

func (e *Engine) GetAdminedPublicChannels(accountID string) ([]PublicLinkInfo, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account %q not found or not connected", accountID)
	}
	type provider interface {
		GetAdminedPublicChannels() ([]cores.Dialog, error)
	}
	p, ok := acc.Core.(provider)
	if !ok {
		return nil, fmt.Errorf("platform does not support admined public channels")
	}
	dialogs, err := p.GetAdminedPublicChannels()
	if err != nil {
		return nil, err
	}
	result := make([]PublicLinkInfo, 0, len(dialogs))
	for _, d := range dialogs {
		result = append(result, PublicLinkInfo{
			ChatID:    d.ID,
			Title:     d.Title,
			Username:  d.LinkedChatId,
			AvatarB64: d.AvatarB64,
		})
	}
	return result, nil
}

func (e *Engine) GetAdminedPublicChannelsFiltered(accountID string, forPersonal bool) ([]PublicLinkInfo, error) {
	if !forPersonal {
		return e.GetAdminedPublicChannels(accountID)
	}
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account %q not found or not connected", accountID)
	}
	type provider interface {
		GetAdminedPublicChannelsForPersonal() ([]cores.Dialog, error)
	}
	p, ok := acc.Core.(provider)
	if !ok {
		return e.GetAdminedPublicChannels(accountID)
	}
	dialogs, err := p.GetAdminedPublicChannelsForPersonal()
	if err != nil {
		return nil, err
	}
	result := make([]PublicLinkInfo, 0, len(dialogs))
	for _, d := range dialogs {
		result = append(result, PublicLinkInfo{
			ChatID:    d.ID,
			Title:     d.Title,
			Username:  d.LinkedChatId,
			AvatarB64: d.AvatarB64,
		})
	}
	return result, nil
}

type ChatPermissionFlags struct {
	SlowmodeSeconds       int    `json:"slowmode_seconds"`
	JoinToSend            bool   `json:"join_to_send"`
	NoForwards            bool   `json:"no_forwards"`
	JoinRequest           bool   `json:"join_request"`
	IsForum               bool   `json:"is_forum"`
	Antispam              bool   `json:"antispam"`
	Signatures            bool   `json:"signatures"`
	SignatureProfiles     bool   `json:"signature_profiles"`
	PreHistoryHidden      bool   `json:"pre_history_hidden"`
	NoTranslations        bool   `json:"no_translations"`
	HasUsername           bool   `json:"has_username"`
	LinkedChatID          string `json:"linked_chat_id"`
	PendingRequestsCount  int    `json:"pending_requests_count"`
	BoostLevel            int    `json:"boost_level"`
	IsMegagroup           bool   `json:"is_megagroup"`
	IsBroadcast           bool   `json:"is_broadcast"`
	IsGigagroup           bool   `json:"is_gigagroup"`
	AmCreator             bool   `json:"am_creator"`
	HasAdminRights        bool   `json:"has_admin_rights"`
	AdminCanChangeInfo    bool   `json:"admin_can_change_info"`
	CanSetStickers        bool   `json:"can_set_stickers"`
	AutoTranslateMinLevel int    `json:"auto_translate_min_level"`
	MigratedFromChatID    string `json:"migrated_from_chat_id"`
	// Reactions state for the Edit-Peer "Reactions" manage-row count label
	// (edit_peer_info_box.cpp:1523-1534): mode is "all"/"some"/"none", the list
	// carries the allowed reactions when mode == "some", and paidEnabled gates
	// the "1" fallback.
	ReactionsMode        string   `json:"reactions_mode"`
	ReactionsAllowed     []string `json:"reactions_allowed"`
	PaidReactionsEnabled bool     `json:"paid_reactions_enabled"`
	// Aggressive anti-spam gating (menu_antispam_validator.cpp:86-90): the toggle
	// is locked while MemberCount < AntispamGroupSizeMin.
	AntispamGroupSizeMin int `json:"antispam_group_size_min"`
	MemberCount          int `json:"member_count"`
}

func (e *Engine) GetChatPermissionFlags(accountID, chatID string) (*ChatPermissionFlags, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account %q not found or not connected", accountID)
	}
	type flagGetter interface {
		GetChatPermissionFlags(chatID string) (*cores.ChatPermissionFlags, error)
	}
	g, ok := acc.Core.(flagGetter)
	if !ok {
		return nil, fmt.Errorf("platform does not support chat permission flags")
	}
	cf, err := g.GetChatPermissionFlags(chatID)
	if err != nil {
		return nil, err
	}
	return &ChatPermissionFlags{
		SlowmodeSeconds:       cf.SlowmodeSeconds,
		JoinToSend:            cf.JoinToSend,
		NoForwards:            cf.NoForwards,
		JoinRequest:           cf.JoinRequest,
		IsForum:               cf.IsForum,
		Antispam:              cf.Antispam,
		Signatures:            cf.Signatures,
		SignatureProfiles:     cf.SignatureProfiles,
		PreHistoryHidden:      cf.PreHistoryHidden,
		NoTranslations:        cf.NoTranslations,
		HasUsername:           cf.HasUsername,
		LinkedChatID:          cf.LinkedChatID,
		PendingRequestsCount:  cf.PendingRequestsCount,
		BoostLevel:            cf.BoostLevel,
		IsMegagroup:           cf.IsMegagroup,
		IsBroadcast:           cf.IsBroadcast,
		IsGigagroup:           cf.IsGigagroup,
		AmCreator:             cf.AmCreator,
		HasAdminRights:        cf.HasAdminRights,
		AdminCanChangeInfo:    cf.AdminCanChangeInfo,
		CanSetStickers:        cf.CanSetStickers,
		AutoTranslateMinLevel: cf.AutoTranslateMinLevel,
		MigratedFromChatID:    cf.MigratedFromChatID,
		ReactionsMode:         cf.ReactionsMode,
		ReactionsAllowed:      cf.ReactionsAllowed,
		PaidReactionsEnabled:  cf.PaidReactionsEnabled,
		AntispamGroupSizeMin:  cf.AntispamGroupSizeMin,
		MemberCount:           cf.MemberCount,
	}, nil
}

// ToggleChannelAutoTranslation toggles admin channel-wide auto-translation.
func (e *Engine) ToggleChannelAutoTranslation(accountID, chatID string, enabled bool) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}
	type toggler interface {
		ToggleChannelAutoTranslation(chatID string, enabled bool) error
	}
	g, ok := acc.Core.(toggler)
	if !ok {
		return fmt.Errorf("platform does not support channel auto-translation")
	}
	return g.ToggleChannelAutoTranslation(chatID, enabled)
}

// GetBotManageInfo returns bot edit/manage gating info.
func (e *Engine) GetBotManageInfo(accountID, chatID string) (map[string]interface{}, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account %q not found or not connected", accountID)
	}
	type getter interface {
		GetBotManageInfo(chatID string) (map[string]interface{}, error)
	}
	g, ok := acc.Core.(getter)
	if !ok {
		return nil, fmt.Errorf("platform does not support bot manage info")
	}
	return g.GetBotManageInfo(chatID)
}

func (e *Engine) GetColorLevelRequirements(accountID string) (map[string]interface{}, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account %q not found or not connected", accountID)
	}
	type getter interface {
		GetColorLevelRequirements() (map[string]interface{}, error)
	}
	g, ok := acc.Core.(getter)
	if !ok {
		return nil, fmt.Errorf("platform does not support color level requirements")
	}
	return g.GetColorLevelRequirements()
}

func (e *Engine) GetBotVerifyState(accountID, botID, userID string) (bool, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return false, fmt.Errorf("account %q not found or not connected", accountID)
	}
	type getter interface {
		GetBotVerifyState(botID, userID string) (bool, error)
	}
	g, ok := acc.Core.(getter)
	if !ok {
		return false, fmt.Errorf("platform does not support bot verify state")
	}
	return g.GetBotVerifyState(botID, userID)
}

func (e *Engine) SetBotCustomVerification(accountID, botID, peerID string, enabled bool, customDescription string) (bool, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return false, fmt.Errorf("account %q not found or not connected", accountID)
	}
	type setter interface {
		SetBotCustomVerification(botID, peerID string, enabled bool, customDescription string) (bool, error)
	}
	g, ok := acc.Core.(setter)
	if !ok {
		return false, fmt.Errorf("platform does not support bot custom verification")
	}
	return g.SetBotCustomVerification(botID, peerID, enabled, customDescription)
}

func (e *Engine) GetInviteImportersList(accountID, chatID, link string, requested bool, limit int, offsetUserID int64, offsetDate int) (map[string]interface{}, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account %q not found or not connected", accountID)
	}
	type getter interface {
		GetInviteImportersList(chatID, link string, requested bool, limit int, offsetUserID int64, offsetDate int) (map[string]interface{}, error)
	}
	g, ok := acc.Core.(getter)
	if !ok {
		return nil, fmt.Errorf("platform does not support invite importers")
	}
	return g.GetInviteImportersList(chatID, link, requested, limit, offsetUserID, offsetDate)
}

func (e *Engine) GetSuggestedStarRefBots(accountID, chatID, offset string, limit int, orderByRevenue, orderByDate bool) (map[string]interface{}, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account %q not found or not connected", accountID)
	}
	type getter interface {
		GetSuggestedStarRefBots(chatID, offset string, limit int, orderByRevenue, orderByDate bool) (map[string]interface{}, error)
	}
	g, ok := acc.Core.(getter)
	if !ok {
		return nil, fmt.Errorf("platform does not support star-ref join")
	}
	return g.GetSuggestedStarRefBots(chatID, offset, limit, orderByRevenue, orderByDate)
}

func (e *Engine) GetConnectedStarRefBots(accountID, chatID string) ([]map[string]interface{}, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account %q not found or not connected", accountID)
	}
	type getter interface {
		GetConnectedStarRefBots(chatID string) ([]map[string]interface{}, error)
	}
	g, ok := acc.Core.(getter)
	if !ok {
		return nil, fmt.Errorf("platform does not support star-ref join")
	}
	return g.GetConnectedStarRefBots(chatID)
}

func (e *Engine) ConnectStarRefBot(accountID, chatID, botID string, revoked bool, link string) (map[string]interface{}, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account %q not found or not connected", accountID)
	}
	type getter interface {
		ConnectStarRefBot(chatID, botID string, revoked bool, link string) (map[string]interface{}, error)
	}
	g, ok := acc.Core.(getter)
	if !ok {
		return nil, fmt.Errorf("platform does not support star-ref join")
	}
	return g.ConnectStarRefBot(chatID, botID, revoked, link)
}

func (e *Engine) SetStarRefProgram(accountID, chatID string, commissionPermille, durationMonths int) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}
	type setter interface {
		SetStarRefProgram(chatID string, commissionPermille, durationMonths int) error
	}
	s, ok := acc.Core.(setter)
	if !ok {
		return fmt.Errorf("platform does not support star-ref program setup")
	}
	return s.SetStarRefProgram(chatID, commissionPermille, durationMonths)
}

type DefaultBannedRights struct {
	SendPlain        bool  `json:"send_plain"`
	SendPhotos       bool  `json:"send_photos"`
	SendVideos       bool  `json:"send_videos"`
	SendRoundvideos  bool  `json:"send_roundvideos"`
	SendAudios       bool  `json:"send_audios"`
	SendVoices       bool  `json:"send_voices"`
	SendDocs         bool  `json:"send_docs"`
	SendStickers     bool  `json:"send_stickers"`
	EmbedLinks       bool  `json:"embed_links"`
	SendPolls        bool  `json:"send_polls"`
	InviteUsers      bool  `json:"invite_users"`
	ManageTopics     bool  `json:"manage_topics"`
	PinMessages      bool  `json:"pin_messages"`
	EditRank         bool  `json:"edit_rank"`
	ChangeInfo       bool  `json:"change_info"`
	SlowmodeSeconds  int   `json:"slowmode_seconds"`
	BoostsUnrestrict int   `json:"boosts_unrestrict"`
	ChargeStars      int64 `json:"charge_stars"`
}

func (e *Engine) GetDefaultBannedRights(accountID, chatID string) (*DefaultBannedRights, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account %q not found or not connected", accountID)
	}
	type getter interface {
		GetDefaultBannedRights(chatID string) (*cores.DefaultBannedRights, error)
	}
	g, ok := acc.Core.(getter)
	if !ok {
		return nil, fmt.Errorf("platform does not support default banned rights")
	}
	cr, err := g.GetDefaultBannedRights(chatID)
	if err != nil {
		return nil, err
	}
	return &DefaultBannedRights{
		SendPlain:        cr.SendPlain,
		SendPhotos:       cr.SendPhotos,
		SendVideos:       cr.SendVideos,
		SendRoundvideos:  cr.SendRoundvideos,
		SendAudios:       cr.SendAudios,
		SendVoices:       cr.SendVoices,
		SendDocs:         cr.SendDocs,
		SendStickers:     cr.SendStickers,
		EmbedLinks:       cr.EmbedLinks,
		SendPolls:        cr.SendPolls,
		InviteUsers:      cr.InviteUsers,
		ManageTopics:     cr.ManageTopics,
		PinMessages:      cr.PinMessages,
		EditRank:         cr.EditRank,
		ChangeInfo:       cr.ChangeInfo,
		SlowmodeSeconds:  cr.SlowmodeSeconds,
		BoostsUnrestrict: cr.BoostsUnrestrict,
		ChargeStars:      cr.ChargeStars,
	}, nil
}

func (e *Engine) GetAdminLogEvents(accountID, chatID string, limit int, query string, maxID int64, filters map[string]bool, admins []string) ([]cores.AdminLogEvent, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account %q not found or not connected", accountID)
	}
	type provider interface {
		GetAdminLogEvents(chatID string, limit int, query string, maxID int64, filters map[string]bool, admins []string) ([]cores.AdminLogEvent, error)
	}
	p, ok := acc.Core.(provider)
	if !ok {
		return nil, fmt.Errorf("platform does not support admin log")
	}
	return p.GetAdminLogEvents(chatID, limit, query, maxID, filters, admins)
}

func (e *Engine) SetDefaultBannedRights(accountID, chatID string, rights *DefaultBannedRights) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}
	type setter interface {
		SetDefaultBannedRights(chatID string, rights *cores.DefaultBannedRights) error
	}
	s, ok := acc.Core.(setter)
	if !ok {
		return fmt.Errorf("platform does not support setting default banned rights")
	}
	return s.SetDefaultBannedRights(chatID, &cores.DefaultBannedRights{
		SendPlain:       rights.SendPlain,
		SendPhotos:      rights.SendPhotos,
		SendVideos:      rights.SendVideos,
		SendRoundvideos: rights.SendRoundvideos,
		SendAudios:      rights.SendAudios,
		SendVoices:      rights.SendVoices,
		SendDocs:        rights.SendDocs,
		SendStickers:    rights.SendStickers,
		EmbedLinks:      rights.EmbedLinks,
		SendPolls:       rights.SendPolls,
		InviteUsers:     rights.InviteUsers,
		ManageTopics:    rights.ManageTopics,
		PinMessages:     rights.PinMessages,
		EditRank:        rights.EditRank,
		ChangeInfo:      rights.ChangeInfo,
		SlowmodeSeconds: rights.SlowmodeSeconds,
	})
}

func (e *Engine) SetSlowMode(accountID, chatID string, seconds int) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}
	type setter interface {
		SetSlowMode(chatID string, seconds int) error
	}
	if s, ok := acc.Core.(setter); ok {
		return s.SetSlowMode(chatID, seconds)
	}
	return fmt.Errorf("platform does not support slow mode")
}

func (e *Engine) ToggleJoinToSend(accountID, chatID string, enabled bool) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}
	type toggler interface {
		ToggleJoinToSend(chatID string, enabled bool) error
	}
	if t, ok := acc.Core.(toggler); ok {
		return t.ToggleJoinToSend(chatID, enabled)
	}
	return fmt.Errorf("platform does not support join-to-send toggle")
}

func (e *Engine) ToggleNoForwards(accountID, chatID string, enabled bool) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}
	type toggler interface {
		ToggleNoForwards(chatID string, enabled bool) error
	}
	if t, ok := acc.Core.(toggler); ok {
		return t.ToggleNoForwards(chatID, enabled)
	}
	return fmt.Errorf("platform does not support no-forwards toggle")
}

func (e *Engine) ToggleJoinRequest(accountID, chatID string, enabled bool) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}
	type toggler interface {
		ToggleJoinRequest(chatID string, enabled bool) error
	}
	if t, ok := acc.Core.(toggler); ok {
		return t.ToggleJoinRequest(chatID, enabled)
	}
	return fmt.Errorf("platform does not support join-request toggle")
}

func (e *Engine) ToggleAntiSpam(accountID, chatID string, enabled bool) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}
	type toggler interface {
		ToggleAntiSpam(chatID string, enabled bool) error
	}
	if t, ok := acc.Core.(toggler); ok {
		return t.ToggleAntiSpam(chatID, enabled)
	}
	return fmt.Errorf("platform does not support anti-spam toggle")
}

func (e *Engine) TogglePreHistoryHidden(accountID, chatID string, hidden bool) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}
	type toggler interface {
		TogglePreHistoryHidden(chatID string, hidden bool) error
	}
	if t, ok := acc.Core.(toggler); ok {
		return t.TogglePreHistoryHidden(chatID, hidden)
	}
	return fmt.Errorf("platform does not support pre-history hidden toggle")
}

func (e *Engine) ToggleSignatures(accountID, chatID string, enabled bool, profilesEnabled ...bool) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}
	type toggler interface {
		ToggleSignatures(chatID string, enabled bool, profilesEnabled ...bool) error
	}
	if t, ok := acc.Core.(toggler); ok {
		return t.ToggleSignatures(chatID, enabled, profilesEnabled...)
	}
	return fmt.Errorf("platform does not support signatures toggle")
}

func (e *Engine) TogglePeerTranslations(accountID, chatID string, disabled bool) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}
	type toggler interface {
		TogglePeerTranslations(chatID string, disabled bool) error
	}
	if t, ok := acc.Core.(toggler); ok {
		return t.TogglePeerTranslations(chatID, disabled)
	}
	return fmt.Errorf("platform does not support peer translations toggle")
}

func (e *Engine) SetChatReactionsMode(accountID, chatID, mode string, emojis []string, maxCount int, paidEnabled bool) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}
	type reactor interface {
		SetChatReactionsMode(chatID string, mode string, emojis []string, maxCount int, paidEnabled bool) error
	}
	if r, ok := acc.Core.(reactor); ok {
		return r.SetChatReactionsMode(chatID, mode, emojis, maxCount, paidEnabled)
	}
	return fmt.Errorf("platform does not support reactions mode")
}

func (e *Engine) GetAvailableReactions(accountID string) ([]string, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account %q not found or not connected", accountID)
	}
	type reactionsGetter interface {
		GetAvailableReactionEmojis() ([]string, error)
	}
	rg, ok := acc.Core.(reactionsGetter)
	if !ok {
		return []string{"👍", "❤️", "🔥", "🥰", "👏", "😱", "😢", "🎉"}, nil
	}
	return rg.GetAvailableReactionEmojis()
}

func (e *Engine) SendBotRequestedPeer(accountID, chatID string, msgID, buttonID int, peerIDs []string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}
	type peerSender interface {
		SendBotRequestedPeer(chatID string, msgID int, buttonID int, peerIDs []string) error
	}
	ps, ok := acc.Core.(peerSender)
	if !ok {
		return fmt.Errorf("platform does not support SendBotRequestedPeer")
	}
	return ps.SendBotRequestedPeer(chatID, msgID, buttonID, peerIDs)
}

func (e *Engine) SendLocation(accountID, chatID string, lat, lon float64) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}
	type locationSender interface {
		SendLocation(chatID string, lat float64, lon float64) (*cores.Message, error)
	}
	ls, ok := acc.Core.(locationSender)
	if !ok {
		return fmt.Errorf("platform does not support SendLocation")
	}
	_, err := ls.SendLocation(chatID, lat, lon)
	return err
}

func (e *Engine) UpdateChannelColor(accountID, chatID string, colorIndex int, backgroundEmojiID int64) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}
	type colorUpdater interface {
		UpdateChannelColorEx(chatID string, colorIndex int, backgroundEmojiID int64) error
	}
	if cu, ok := acc.Core.(colorUpdater); ok {
		return cu.UpdateChannelColorEx(chatID, colorIndex, backgroundEmojiID)
	}
	return fmt.Errorf("platform does not support channel color update")
}

func (e *Engine) UpdateChannelEmojiStatus(accountID, chatID string, documentID int64) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}
	type emojiStatusUpdater interface {
		UpdateChannelEmojiStatus(chatID string, documentID int64) error
	}
	if su, ok := acc.Core.(emojiStatusUpdater); ok {
		return su.UpdateChannelEmojiStatus(chatID, documentID)
	}
	return fmt.Errorf("platform does not support channel emoji status update")
}

func (e *Engine) UpdatePaidMessagesPrice(accountID, chatID string, stars int64, broadcastEnabled bool) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}
	type priceUpdater interface {
		UpdatePaidMessagesPrice(chatID string, stars int64, broadcastEnabled bool) error
	}
	if pu, ok := acc.Core.(priceUpdater); ok {
		return pu.UpdatePaidMessagesPrice(chatID, stars, broadcastEnabled)
	}
	return fmt.Errorf("platform does not support paid messages price")
}

func (e *Engine) SetBoostsUnrestrict(accountID, chatID string, boosts int) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}
	type boostsUpdater interface {
		SetBoostsUnrestrict(chatID string, boosts int) error
	}
	if bu, ok := acc.Core.(boostsUpdater); ok {
		return bu.SetBoostsUnrestrict(chatID, boosts)
	}
	return fmt.Errorf("platform does not support boosts unrestrict")
}

func (e *Engine) GetBoosts(accountID, chatID string) (map[string]interface{}, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account %q not found or not connected", accountID)
	}
	type boostsGetter interface {
		GetBoostsJSON(chatID string) (map[string]interface{}, error)
	}
	if bg, ok := acc.Core.(boostsGetter); ok {
		return bg.GetBoostsJSON(chatID)
	}
	return nil, fmt.Errorf("platform does not support boosts")
}

func (e *Engine) GetBoostsList(accountID, chatID string, isGifts bool, offset string) (map[string]interface{}, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account %q not found or not connected", accountID)
	}
	type boostsLister interface {
		GetBoostsListJSON(chatID string, isGifts bool, offset string) (map[string]interface{}, error)
	}
	if bl, ok := acc.Core.(boostsLister); ok {
		return bl.GetBoostsListJSON(chatID, isGifts, offset)
	}
	return nil, fmt.Errorf("platform does not support boosts list")
}

func (e *Engine) GetGiftCodeOptions(accountID, chatID string) ([]map[string]interface{}, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account %q not found or not connected", accountID)
	}
	type giftCodeOptionsGetter interface {
		GetGiftCodeOptions(chatID string) ([]map[string]interface{}, error)
	}
	if g, ok := acc.Core.(giftCodeOptionsGetter); ok {
		return g.GetGiftCodeOptions(chatID)
	}
	return nil, fmt.Errorf("platform does not support gift code options")
}

func (e *Engine) LaunchPrepaidGiveaway(accountID, chatID string, giveawayID int64, params map[string]interface{}) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}
	type prepaidGiveawayLauncher interface {
		LaunchPrepaidGiveaway(chatID string, giveawayID int64, params map[string]interface{}) error
	}
	if l, ok := acc.Core.(prepaidGiveawayLauncher); ok {
		return l.LaunchPrepaidGiveaway(chatID, giveawayID, params)
	}
	return fmt.Errorf("platform does not support prepaid giveaways")
}

func (e *Engine) LaunchRandomGiveaway(accountID, chatID string, params map[string]interface{}) (map[string]interface{}, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account %q not found or not connected", accountID)
	}
	type randomGiveawayLauncher interface {
		LaunchRandomGiveaway(chatID string, params map[string]interface{}) (map[string]interface{}, error)
	}
	if l, ok := acc.Core.(randomGiveawayLauncher); ok {
		return l.LaunchRandomGiveaway(chatID, params)
	}
	return nil, fmt.Errorf("platform does not support random giveaways")
}

func (e *Engine) GetStarsGiveawayOptions(accountID string) ([]map[string]interface{}, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account %q not found or not connected", accountID)
	}
	type starsGiveawayOptionsGetter interface {
		GetStarsGiveawayOptions() ([]map[string]interface{}, error)
	}
	if g, ok := acc.Core.(starsGiveawayOptionsGetter); ok {
		return g.GetStarsGiveawayOptions()
	}
	return nil, fmt.Errorf("platform does not support stars giveaway options")
}

func (e *Engine) LaunchCreditsGiveaway(accountID, chatID string, params map[string]interface{}) (map[string]interface{}, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account %q not found or not connected", accountID)
	}
	type creditsGiveawayLauncher interface {
		LaunchCreditsGiveaway(chatID string, params map[string]interface{}) (map[string]interface{}, error)
	}
	if l, ok := acc.Core.(creditsGiveawayLauncher); ok {
		return l.LaunchCreditsGiveaway(chatID, params)
	}
	return nil, fmt.Errorf("platform does not support credits giveaways")
}

func (e *Engine) GetGiveawayPeriodMax(accountID string) (int, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return 604800, fmt.Errorf("account %q not found or not connected", accountID)
	}
	type giveawayPeriodMaxGetter interface {
		GetGiveawayPeriodMax() (int, error)
	}
	if g, ok := acc.Core.(giveawayPeriodMaxGetter); ok {
		return g.GetGiveawayPeriodMax()
	}
	return 604800, nil
}

func (e *Engine) GetGiveawayConfig(accountID string) (map[string]int, error) {
	fallback := map[string]int{
		"boosts_per_premium": 4,
		"countries_max":      10,
		"add_peers_max":      10,
		"period_max":         604800,
	}
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fallback, fmt.Errorf("account %q not found or not connected", accountID)
	}
	type giveawayConfigGetter interface {
		GetGiveawayConfig() (map[string]int, error)
	}
	if g, ok := acc.Core.(giveawayConfigGetter); ok {
		return g.GetGiveawayConfig()
	}
	return fallback, nil
}

func (e *Engine) AwardPremiumGiveaway(accountID, chatID string, params map[string]interface{}) (map[string]interface{}, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account %q not found or not connected", accountID)
	}
	type premiumAwarder interface {
		AwardPremiumGiveaway(chatID string, params map[string]interface{}) (map[string]interface{}, error)
	}
	if a, ok := acc.Core.(premiumAwarder); ok {
		return a.AwardPremiumGiveaway(chatID, params)
	}
	return nil, fmt.Errorf("platform does not support premium giveaways")
}

func (e *Engine) GetFullChat(accountID, chatID string) (*cores.Dialog, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account %q not found or not connected", accountID)
	}
	type provider interface {
		GetFullChat(chatID string) (*cores.Dialog, error)
	}
	if p, ok := acc.Core.(provider); ok {
		return p.GetFullChat(chatID)
	}
	return nil, fmt.Errorf("platform does not support full chat info")
}

func (e *Engine) GetParticipantInfo(accountID, chatID, userID string) (*cores.User, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account %q not found or not connected", accountID)
	}
	type provider interface {
		GetParticipantInfo(chatID, userID string) (*cores.User, error)
	}
	if p, ok := acc.Core.(provider); ok {
		return p.GetParticipantInfo(chatID, userID)
	}
	return nil, fmt.Errorf("platform does not support participant info")
}

func (e *Engine) EditChannelPhoto(accountID, chatID string, photoData []byte, isVideo bool) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}
	if isVideo {
		type videoEditor interface {
			EditChannelVideoPhoto(chatID string, videoData []byte) error
		}
		if ed, ok := acc.Core.(videoEditor); ok {
			return ed.EditChannelVideoPhoto(chatID, photoData)
		}
		return fmt.Errorf("platform does not support video channel photos")
	}
	type editor interface {
		EditChannelPhoto(chatID string, photoData []byte) error
	}
	if ed, ok := acc.Core.(editor); ok {
		return ed.EditChannelPhoto(chatID, photoData)
	}
	return fmt.Errorf("platform does not support channel photo editing")
}

func (e *Engine) DeleteChannelPhoto(accountID, chatID string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}
	type editor interface {
		EditChannelPhoto(chatID string, photoData []byte) error
	}
	if ed, ok := acc.Core.(editor); ok {
		return ed.EditChannelPhoto(chatID, nil)
	}
	return fmt.Errorf("platform does not support channel photo deletion")
}

func (e *Engine) SuggestContactPhoto(accountID, userID string, photoData []byte) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}
	type suggestor interface {
		SuggestContactPhoto(userID string, photoData []byte) error
	}
	if s, ok := acc.Core.(suggestor); ok {
		return s.SuggestContactPhoto(userID, photoData)
	}
	return fmt.Errorf("platform does not support suggesting contact photos")
}

func (e *Engine) SuggestBirthday(accountID, userID string, day, month, year int) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}
	type suggestor interface {
		SuggestBirthday(userID string, day, month, year int) error
	}
	if s, ok := acc.Core.(suggestor); ok {
		return s.SuggestBirthday(userID, day, month, year)
	}
	return fmt.Errorf("platform does not support suggesting birthdays")
}

func (e *Engine) SetPersonalContactPhoto(accountID, userID string, photoData []byte) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}
	type setter interface {
		SetPersonalContactPhoto(userID string, photoData []byte) error
	}
	if s, ok := acc.Core.(setter); ok {
		return s.SetPersonalContactPhoto(userID, photoData)
	}
	return fmt.Errorf("platform does not support setting personal contact photos")
}

func (e *Engine) ClearPersonalContactPhoto(accountID, userID string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}
	type clearer interface {
		ClearPersonalContactPhoto(userID string) error
	}
	if c, ok := acc.Core.(clearer); ok {
		return c.ClearPersonalContactPhoto(userID)
	}
	return fmt.Errorf("platform does not support clearing personal contact photos")
}

func (e *Engine) SetPersonalChannel(accountID, channelUsername string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}
	type setter interface {
		SetPersonalChannel(channelUsername string) error
	}
	if s, ok := acc.Core.(setter); ok {
		return s.SetPersonalChannel(channelUsername)
	}
	return fmt.Errorf("platform does not support personal channel")
}

func (e *Engine) ClearPersonalChannel(accountID string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}
	type clearer interface {
		ClearPersonalChannel() error
	}
	if c, ok := acc.Core.(clearer); ok {
		return c.ClearPersonalChannel()
	}
	return fmt.Errorf("platform does not support personal channel")
}

func (e *Engine) SetGroupStickerSet(accountID, chatID, shortName string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}
	type setter interface {
		SetGroupStickerSet(chatID, shortName string) error
	}
	if s, ok := acc.Core.(setter); ok {
		return s.SetGroupStickerSet(chatID, shortName)
	}
	return fmt.Errorf("platform does not support group sticker set")
}

func (e *Engine) SetDiscussionGroup(accountID, broadcastID, groupID string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}
	type setter interface {
		SetDiscussionGroup(broadcastID, groupID string) error
	}
	if s, ok := acc.Core.(setter); ok {
		return s.SetDiscussionGroup(broadcastID, groupID)
	}
	return fmt.Errorf("platform does not support discussion group linking")
}

func (e *Engine) GetDiscussionGroups(accountID string) ([]map[string]interface{}, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account %q not found or not connected", accountID)
	}
	type provider interface {
		GetDiscussionGroups() ([]map[string]interface{}, error)
	}
	if p, ok := acc.Core.(provider); ok {
		return p.GetDiscussionGroups()
	}
	return nil, fmt.Errorf("platform does not support discussion groups")
}

func (e *Engine) GetExportedChatInvites(accountID, chatID string, revoked bool, adminID string, offsetDate int, offsetLink string) ([]map[string]interface{}, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account %q not found or not connected", accountID)
	}
	type provider interface {
		GetExportedChatInvites(chatID string, revoked bool, adminID string, offsetDate int, offsetLink string) ([]map[string]interface{}, error)
	}
	if p, ok := acc.Core.(provider); ok {
		return p.GetExportedChatInvites(chatID, revoked, adminID, offsetDate, offsetLink)
	}
	return nil, fmt.Errorf("platform does not support invite link listing")
}

func (e *Engine) CreateChatInviteLink(accountID, chatID, label string, expireDate, usageLimit int, requestApproval bool, subscriptionCredits int) (map[string]interface{}, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account %q not found or not connected", accountID)
	}
	type subscriptionCreator interface {
		CreateChatInviteLinkWithSubscription(chatID, label string, expireDate, usageLimit int, requestApproval bool, subscriptionCredits int) (map[string]interface{}, error)
	}
	if subscriptionCredits > 0 {
		if sc, ok := acc.Core.(subscriptionCreator); ok {
			return sc.CreateChatInviteLinkWithSubscription(chatID, label, expireDate, usageLimit, requestApproval, subscriptionCredits)
		}
	}
	type creator interface {
		CreateChatInviteLink(chatID, label string, expireDate, usageLimit int, requestApproval bool) (map[string]interface{}, error)
	}
	if c, ok := acc.Core.(creator); ok {
		return c.CreateChatInviteLink(chatID, label, expireDate, usageLimit, requestApproval)
	}
	return nil, fmt.Errorf("platform does not support invite link creation")
}

func (e *Engine) EditChatInviteLink(accountID, chatID, link, label string, expireDate, usageLimit int, requestApproval bool, subscriptionCredits int) (map[string]interface{}, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account %q not found or not connected", accountID)
	}
	type subscriptionEditor interface {
		EditChatInviteLinkWithSubscription(chatID, link, label string, expireDate, usageLimit int, requestApproval bool, subscriptionCredits int) (map[string]interface{}, error)
	}
	if subscriptionCredits > 0 {
		if se, ok := acc.Core.(subscriptionEditor); ok {
			return se.EditChatInviteLinkWithSubscription(chatID, link, label, expireDate, usageLimit, requestApproval, subscriptionCredits)
		}
	}
	type editor interface {
		EditChatInviteLink(chatID, link, label string, expireDate, usageLimit int, requestApproval bool) (map[string]interface{}, error)
	}
	if ed, ok := acc.Core.(editor); ok {
		return ed.EditChatInviteLink(chatID, link, label, expireDate, usageLimit, requestApproval)
	}
	return nil, fmt.Errorf("platform does not support invite link editing")
}

func (e *Engine) RevokeChatInviteLink(accountID, chatID, link string) (map[string]interface{}, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account %q not found or not connected", accountID)
	}
	type revoker interface {
		RevokeChatInviteLink(chatID, link string) (map[string]interface{}, error)
	}
	if r, ok := acc.Core.(revoker); ok {
		return r.RevokeChatInviteLink(chatID, link)
	}
	return nil, fmt.Errorf("platform does not support invite link revoking")
}

func (e *Engine) DeleteRevokedChatInviteLink(accountID, chatID, link string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}
	type deleter interface {
		DeleteRevokedChatInviteLink(chatID, link string) error
	}
	if d, ok := acc.Core.(deleter); ok {
		return d.DeleteRevokedChatInviteLink(chatID, link)
	}
	return fmt.Errorf("platform does not support invite link deletion")
}

func (e *Engine) DeleteAllRevokedChatInvites(accountID, chatID string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}
	type deleter interface {
		DeleteAllRevokedChatInvites(chatID string) error
	}
	if d, ok := acc.Core.(deleter); ok {
		return d.DeleteAllRevokedChatInvites(chatID)
	}
	return fmt.Errorf("platform does not support deleting all revoked invites")
}

func (e *Engine) GetAdminsWithInvites(accountID, chatID string) ([]map[string]interface{}, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account %q not found or not connected", accountID)
	}
	type provider interface {
		GetAdminsWithInvites(chatID string) ([]map[string]interface{}, error)
	}
	if p, ok := acc.Core.(provider); ok {
		return p.GetAdminsWithInvites(chatID)
	}
	return nil, fmt.Errorf("platform does not support admins with invites")
}
