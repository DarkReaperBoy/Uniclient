package engine

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"golang.org/x/net/proxy"

	"uniclient/audio"
	"uniclient/cores"
	"uniclient/utils"
)

type ConnState int

const (
	ConnDisconnected ConnState = iota
	ConnConnecting
	ConnConnected
	ConnUnstable
)

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

	reconnect  reconnectState
	lastEvent  time.Time
	cancelFunc context.CancelFunc
}

type Engine struct {
	mu     sync.RWMutex
	db     *sql.DB
	vault  *utils.Vault
	config *utils.AppConfig

	accounts   map[string]*Account
	accountsMu sync.RWMutex

	authFlows   map[string]*AuthFlow
	authFlowsMu sync.Mutex

	eventCBs map[int]func([]byte)
	cbSeq    int

	configDir   string
	cacheDir    string
	downloadDir string
	mediaDir    string
	maxCache    int64

	activeChat struct {
		mu        sync.Mutex
		accountID string
		chatID    string
	}

	media   *MediaManager
	avatars *avatarState

	guardMu sync.Mutex
	guards  map[string]*mediaGuard

	muteSweepLast atomic.Int64

	dicePacks map[string]*dicePackCache

	favReactMu sync.Mutex
	favReact   map[string]string

	ownMusicMu   sync.Mutex
	ownMusicIDs  map[string]map[string]bool
	ownMusicHash map[string]int64

	mediaMu     sync.Mutex
	MediaPlayer *MediaPlayer

	recMu         sync.Mutex
	VoiceRecorder *VoiceRecorder

	voiceMu      sync.Mutex
	voiceRun     *voiceRunner
	audioSession *audio.Session

	lockFile     *os.File
	shuttingDown bool
	wg           sync.WaitGroup
	ctx          context.Context
	ctxCancel    context.CancelFunc

	antiRecallMu        sync.RWMutex
	saveDeletedMessages bool
	saveMessagesHistory bool
	saveForBots         bool

	exportMu sync.RWMutex
	exports  map[string]*exportState

	exportSuggestMu     sync.Mutex
	exportSuggestTimers map[string]*time.Timer

	proxyMu              sync.RWMutex
	proxyMode            int
	proxyHost            string
	proxyPort            int
	proxyType            string
	proxyUser            string
	proxyPass            string
	proxySecret          string
	proxyIPv6            bool
	proxyForCalls        bool
	proxyRotationEnabled bool
	proxyRotationTimeout int

	autoDownloadMu       sync.RWMutex
	autoDownloadSettings map[string]map[string]interface{}

	ghostMu        sync.RWMutex
	ghostOverrides map[string]GhostFlags

	powerSavingFlags    int
	powerSavingForceAll bool

	localStorageTotalMB  int
	localStorageMediaMB  int
	localStorageTimeDays int

	experimentalFlagsMu sync.RWMutex
	experimentalFlags   map[string]bool
}

func New(db *sql.DB, vault *utils.Vault, config *utils.AppConfig) *Engine {
	e := &Engine{
		accounts:            make(map[string]*Account),
		authFlows:           make(map[string]*AuthFlow),
		db:                  db,
		vault:               vault,
		config:              config,
		maxCache:            1 << 30,
		avatars:             newAvatarState(),
		saveDeletedMessages: true,
		saveMessagesHistory: true,
	}
	e.ctx, e.ctxCancel = context.WithCancel(context.Background())
	if config == nil {
		return e
	}
	if config.MaxCacheSize > 0 {
		e.maxCache = config.MaxCacheSize
	}
	if config.AyuSaveDeleted != nil {
		e.saveDeletedMessages = *config.AyuSaveDeleted
	}
	if config.AyuSaveHistory != nil {
		e.saveMessagesHistory = *config.AyuSaveHistory
	}
	if config.AyuSaveForBots != nil {
		e.saveForBots = *config.AyuSaveForBots
	}
	if pc := config.ProxyConfig; pc.Host != "" || pc.Mode > 0 {
		e.proxyMode = pc.Mode
		e.proxyHost = pc.Host
		e.proxyType = strings.ToLower(pc.Type)
		e.proxyUser = pc.Username
		e.proxyPass = pc.Password
		if p, err := strconv.Atoi(strings.TrimSpace(pc.Port)); err == nil {
			e.proxyPort = p
		}
	}
	if config.DownloadDir != "" {
		e.downloadDir = config.DownloadDir
	}
	return e
}

func Init(configDir, cacheDir, downloadDir, vaultPassword string) (*Engine, error) {
	mediaDir := filepath.Join(cacheDir, "media")
	for _, d := range []string{configDir, cacheDir, downloadDir, mediaDir} {
		if err := ensureDir(d); err != nil {
			return nil, fmt.Errorf("create dir %s: %w", d, err)
		}
	}

	lockPath := filepath.Join(configDir, "uniclient.lock")
	lf, err := acquireLock(lockPath)
	if err != nil {
		return nil, err
	}

	vaultPath := filepath.Join(configDir, "uniclient.vault")
	var vault *utils.Vault
	if !utils.VaultExists(vaultPath) {
		vault, err = utils.CreateVault(vaultPath, vaultPassword)
		if err != nil {
			return nil, fmt.Errorf("create vault: %w", err)
		}
	} else {
		vault, err = utils.OpenVault(vaultPath, vaultPassword)
		if err != nil {
			return nil, fmt.Errorf("open vault: %w", err)
		}
	}

	uniConfigPath := filepath.Join(configDir, "uniconfig")
	if _, statErr := os.Stat(uniConfigPath); statErr == nil {
		_ = vault.MigrateUniConfig(uniConfigPath)
	}

	oldCfgPath := filepath.Join(configDir, "config.json")
	if _, statErr := os.Stat(oldCfgPath); statErr == nil {
		if cfg, cfgErr := utils.LoadConfig(oldCfgPath); cfgErr == nil {
			_ = vault.SetConfig(cfg)
		}
		os.Remove(oldCfgPath)
	}

	cfg := vault.Config()
	utils.MergeDefaults(cfg)

	db, err := OpenDB(cacheDir)
	if err != nil {
		vault.Close()
		return nil, fmt.Errorf("open db: %w", err)
	}

	e := New(db, vault, cfg)
	e.configDir = configDir
	e.cacheDir = cacheDir
	e.mediaDir = mediaDir
	if e.downloadDir == "" {
		e.downloadDir = downloadDir
	}
	e.lockFile = lf

	e.migrateAccountsToVault()

	if err := e.loadAccounts(); err != nil {
		e.db.Close()
		e.vault.Close()
		return nil, fmt.Errorf("load accounts: %w", err)
	}

	e.resumePending()

	e.loadAutoDownloadSettings()

	if err := e.UseMediaDir(mediaDir); err != nil {
		e.db.Close()
		e.vault.Close()
		return nil, err
	}

	return e, nil
}

func (e *Engine) Vault() *utils.Vault {
	return e.vault
}

func (e *Engine) MediaDir() string {
	e.mu.RLock()
	defer e.mu.RUnlock()
	return e.mediaDir
}

func (e *Engine) UseMediaDir(dir string) error {
	if err := ensureDir(dir); err != nil {
		return fmt.Errorf("media dir: %w", err)
	}
	e.mu.Lock()
	old := e.media
	e.media = nil
	e.mu.Unlock()
	if old != nil {
		old.Stop()
	}
	e.mu.Lock()
	e.mediaDir = dir
	mm := NewMediaManager(e)
	e.media = mm
	e.mu.Unlock()
	mm.Start(e.ctx)
	return nil
}

func (e *Engine) SetEventCallback(cb func([]byte)) {
	e.mu.Lock()
	defer e.mu.Unlock()
	e.eventCBs = nil
	if cb != nil {
		e.cbSeq++
		e.eventCBs = map[int]func([]byte){e.cbSeq: cb}
	}
}

type EventSubscription struct {
	id int
	e  *Engine
}

func (e *Engine) Subscribe(cb func([]byte)) *EventSubscription {
	if cb == nil {
		return nil
	}
	e.mu.Lock()
	defer e.mu.Unlock()
	if e.eventCBs == nil {
		e.eventCBs = make(map[int]func([]byte))
	}
	e.cbSeq++
	e.eventCBs[e.cbSeq] = cb
	return &EventSubscription{id: e.cbSeq, e: e}
}

func (s *EventSubscription) Unsubscribe() {
	if s == nil || s.e == nil {
		return
	}
	s.e.mu.Lock()
	defer s.e.mu.Unlock()
	delete(s.e.eventCBs, s.id)
}

func (e *Engine) PushEvent(data []byte) {
	e.mu.RLock()
	cbs := make([]func([]byte), 0, len(e.eventCBs))
	for _, cb := range e.eventCBs {
		cbs = append(cbs, cb)
	}
	e.mu.RUnlock()
	for _, cb := range cbs {
		if cb != nil {
			cb(data)
		}
	}
}

func (e *Engine) GetAntiRecallSettings() (saveDeleted, saveHistory, saveForBots bool) {
	e.antiRecallMu.RLock()
	defer e.antiRecallMu.RUnlock()
	return e.saveDeletedMessages, e.saveMessagesHistory, e.saveForBots
}

func (e *Engine) ClearDeletedMessages(accountID, chatID string) (int64, error) {
	if _, err := e.db.Exec(
		`DELETE FROM media WHERE account_id = ? AND chat_id = ? AND msg_id IN
                  (SELECT msg_id FROM messages WHERE account_id = ? AND chat_id = ? AND is_deleted = 1)`,
		accountID, chatID, accountID, chatID); err != nil {
		return 0, err
	}

	res, err := e.db.Exec(
		`DELETE FROM messages WHERE account_id = ? AND chat_id = ? AND is_deleted = 1`,
		accountID, chatID)
	if err != nil {
		return 0, err
	}
	return res.RowsAffected()
}

type proxyConfigurable interface {
	SetProxyConfig(cores.ProxyConfig)
}

func (e *Engine) SetProxy(mode int, host string, port int, proxyType, user, pass, secret string, ipv6, forCalls, rotationEnabled bool, rotationTimeout int) {
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

func (e *Engine) GetProxySettings() (mode int, host string, port int, ptype, user, pass string) {
	e.proxyMu.RLock()
	defer e.proxyMu.RUnlock()
	return e.proxyMode, e.proxyHost, e.proxyPort, e.proxyType, e.proxyUser, e.proxyPass
}

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

func (e *Engine) applyProxyToCore(core cores.Core) {
	if core == nil {
		return
	}
	if pc, ok := core.(proxyConfigurable); ok {
		pc.SetProxyConfig(e.currentProxyConfig())
	}
}

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

func (e *Engine) SetAutoDownloadSettings(source string, settings map[string]interface{}) {
	e.autoDownloadMu.Lock()
	if e.autoDownloadSettings == nil {
		e.autoDownloadSettings = make(map[string]map[string]interface{})
	}
	e.autoDownloadSettings[source] = settings
	e.autoDownloadMu.Unlock()
	log.Printf("[engine] SetAutoDownload: source=%s settings=%v", source, settings)

	if e.db != nil {
		if data, err := json.Marshal(settings); err == nil {
			_, err = e.db.Exec(
				`INSERT INTO kv (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = ?`,
				"autodl:"+source, string(data), string(data))
			if err != nil {
				log.Printf("[engine] persist autodl %s: %v", source, err)
			}
		}
	}
}

func (e *Engine) GetAutoDownloadSettings() map[string]map[string]interface{} {
	out := make(map[string]map[string]interface{}, 3)
	for _, source := range []string{"private", "group", "channel"} {
		e.autoDownloadMu.RLock()
		stored := e.autoDownloadSettings[source]
		e.autoDownloadMu.RUnlock()
		out[source] = EffectiveAutoDownloadSettings(stored)
	}
	return out
}

func EffectiveAutoDownloadSettings(stored map[string]interface{}) map[string]interface{} {
	photos, files, videos, gifs, videoMsgs := true, false, true, true, true
	downloadLimit := int64(10 * 1024 * 1024)
	autoPlayLimit := int64(50 * 1024 * 1024)
	if stored != nil {
		if v, ok := stored["photos"].(bool); ok {
			photos = v
		}
		if v, ok := stored["files"].(bool); ok {
			files = v
		}
		if v, ok := stored["videos"].(bool); ok {
			videos = v
		}
		if v, ok := stored["gifs"].(bool); ok {
			gifs = v
		}
		if v, ok := stored["videoMessages"].(bool); ok {
			videoMsgs = v
		}
		switch v := stored["downloadLimit"].(type) {
		case float64:
			downloadLimit = int64(v)
		case int:
			downloadLimit = int64(v)
		case int64:
			downloadLimit = v
		}
		switch v := stored["autoPlayLimit"].(type) {
		case float64:
			autoPlayLimit = int64(v)
		case int:
			autoPlayLimit = int64(v)
		case int64:
			autoPlayLimit = v
		}
	}
	return map[string]interface{}{
		"photos":        photos,
		"files":         files,
		"videos":        videos,
		"gifs":          gifs,
		"videoMessages": videoMsgs,
		"downloadLimit": downloadLimit,
		"autoPlayLimit": autoPlayLimit,
	}
}

func (e *Engine) loadAutoDownloadSettings() {
	if e.db == nil {
		return
	}
	rows, err := e.db.Query("SELECT key, value FROM kv WHERE key LIKE 'autodl:%'")
	if err != nil {
		return
	}
	defer rows.Close()
	loaded := make(map[string]map[string]interface{})
	for rows.Next() {
		var key, val string
		if err := rows.Scan(&key, &val); err != nil {
			continue
		}
		source := strings.TrimPrefix(key, "autodl:")
		var settings map[string]interface{}
		if err := json.Unmarshal([]byte(val), &settings); err != nil {
			continue
		}
		loaded[source] = settings
	}
	if len(loaded) == 0 {
		return
	}
	e.autoDownloadMu.Lock()
	if e.autoDownloadSettings == nil {
		e.autoDownloadSettings = make(map[string]map[string]interface{})
	}
	for source, settings := range loaded {
		e.autoDownloadSettings[source] = settings
	}
	e.autoDownloadMu.Unlock()
}

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

func (e *Engine) SetPasscode(data map[string]interface{}) error {
	if err := e.vault.Put("passcode", "config", data); err != nil {
		return err
	}
	return e.vault.Save()
}

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

func (e *Engine) ClearPasscode() error {
	_ = e.vault.Delete("passcode", "config")
	return e.vault.Save()
}

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

func (e *Engine) SetPowerSaving(flags int, forceAll bool) {
	e.mu.Lock()
	e.powerSavingFlags = flags
	e.powerSavingForceAll = forceAll
	if e.config != nil {
		e.config.PowerSavingFlags = flags
		e.config.PowerSavingForceAll = forceAll
		if e.vault != nil {
			_ = e.vault.SetConfig(e.config)
		}
	}
	e.mu.Unlock()
	log.Printf("[engine] SetPowerSaving: flags=0x%X forceAll=%v", flags, forceAll)
}

func (e *Engine) GetPowerSaving() (flags int, forceAll bool, ok bool) {
	e.mu.Lock()
	defer e.mu.Unlock()
	if e.config == nil {
		return 0, false, false
	}
	return e.config.PowerSavingFlags, e.config.PowerSavingForceAll, true
}

func (e *Engine) GetChannelStats(accountID, chatID string) (*cores.ChannelStats, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account %q not found or not connected", accountID)
	}
	type statsProvider interface {
		GetChannelStats(chatID string) (*cores.ChannelStats, error)
	}
	p, ok := acc.Core.(statsProvider)
	if !ok {
		return nil, fmt.Errorf("platform does not support channel statistics")
	}
	return p.GetChannelStats(chatID)
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

func (e *Engine) SetLocalStorageLimits(totalMB, mediaMB, timeDays int) {
	e.localStorageTotalMB = totalMB
	e.localStorageMediaMB = mediaMB
	e.localStorageTimeDays = timeDays
	if totalMB > 0 {
		e.maxCache = int64(totalMB) * 1024 * 1024
	}
	log.Printf("[engine] SetLocalStorageLimits: total=%dMB media=%dMB time=%ddays", totalMB, mediaMB, timeDays)
}

func (e *Engine) CheckProxy(host string, port int, proxyType, user, pass, secret string) (int64, error) {
	addr := net.JoinHostPort(host, strconv.Itoa(port))
	start := time.Now()

	var conn net.Conn
	var err error

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

func (e *Engine) SetActiveChat(accountID, chatID string) {
	e.activeChat.mu.Lock()
	e.activeChat.accountID = accountID
	e.activeChat.chatID = chatID
	e.activeChat.mu.Unlock()
}

func (e *Engine) ClearActiveChat() {
	e.activeChat.mu.Lock()
	e.activeChat.accountID = ""
	e.activeChat.chatID = ""
	e.activeChat.mu.Unlock()
}

func (e *Engine) isActiveChat(accountID, chatID string) bool {
	e.activeChat.mu.Lock()
	defer e.activeChat.mu.Unlock()
	return e.activeChat.accountID == accountID && e.activeChat.chatID == chatID
}

func (e *Engine) AddRecentSearch(query string) error {
	query = strings.TrimSpace(query)
	if query == "" {
		return nil
	}
	e.mu.Lock()
	defer e.mu.Unlock()
	kept := make([]string, 0, 9)
	for _, q := range e.config.RecentSearches {
		if !strings.EqualFold(q, query) {
			kept = append(kept, q)
		}
	}
	recent := append([]string{query}, kept...)
	if len(recent) > 8 {
		recent = recent[:8]
	}
	e.config.RecentSearches = recent
	return e.vault.SetConfig(e.config)
}

func (e *Engine) ClearRecentSearches() error {
	e.mu.Lock()
	defer e.mu.Unlock()
	e.config.RecentSearches = nil
	return e.vault.SetConfig(e.config)
}

func (e *Engine) GetConfig() *utils.AppConfig {
	e.mu.RLock()
	defer e.mu.RUnlock()
	return e.config
}

func (e *Engine) UpdateConfig(changes *utils.AppConfig) error {
	e.mu.Lock()
	defer e.mu.Unlock()

	if changes.Theme != "" {
		e.config.Theme = changes.Theme
	}
	if changes.Language != "" {
		e.config.Language = changes.Language
	}
	if changes.RecentSearches != nil {
		e.config.RecentSearches = changes.RecentSearches
	}
	if changes.DrawerHiddenItems != nil {
		e.config.DrawerHiddenItems = changes.DrawerHiddenItems
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

type ConfigChanges struct {
	Theme                      string
	AccentColor                string
	FontScale                  float64
	Language                   string
	MediaVolume                *float64
	TranslateTarget            string
	ComposerSubmit             *string
	SwipeAction                *string
	CornerReply                *bool
	CornerReaction             *bool
	AyuImproveLinkPreviews     *bool
	AyuMsgSeconds              *bool
	AyuFilterZalgo             *bool
	AyuReactChannels           *bool
	AyuReactGroups             *bool
	AyuReactPrivate            *bool
	AyuConfirmSticker          *bool
	AyuConfirmGif              *bool
	AyuConfirmVoice            *bool
	AyuHideSimilarChannels     *bool
	AyuCollapseSimilarChannels *bool
	AyuAppIcon                 *string
	AyuAvatarCorners           *int
	AyuSingleCornerRadius      *bool
	FontPath                   *string
	MonoFontPath               *string
	MaxCacheSize               int64
	DownloadDir                string
	SendReadReceipts           *bool
	LocalReadMark              *bool
	SendTyping                 *bool
	SendUploadProgress         *bool
	SendReadStories            *bool
	SendOnlinePackets          *bool
	SendOfflineAfterOnline     *bool
	MarkReadAfterAction        *bool
	UseScheduledMessages       *bool
	SendWithoutSound           *bool
	NotifyDMs                  *bool
	NotifyGroups               *bool
	NotifyMentionsOnly         *bool

	NotifyPreviews *bool

	NotifySound *string

	DrawerHiddenItems []string

	StreamerMode *bool

	SystemTray *bool

	AyuDeletedMark *string
	AyuEditedMark  *string

	AyuSaveDeleted *bool
	AyuSaveHistory *bool
	AyuSaveForBots *bool
	BubbleCorners  *bool

	BubbleRadius   *int
	WideMultiplier *float64

	ProxyConfig *utils.ProxyConfig

	HideAllChats *bool
}

func (e *Engine) UpdateConfigFromBridge(changes *ConfigChanges) error {
	if e.config == nil {
		return fmt.Errorf("config: engine has no config to update")
	}
	if changes.DownloadDir != "" {
		if err := ensureDir(changes.DownloadDir); err != nil {
			return fmt.Errorf("download dir: %w", err)
		}
	}
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
	if changes.FontPath != nil {
		e.config.FontPath = *changes.FontPath
	}
	if changes.MonoFontPath != nil {
		e.config.MonoFontPath = *changes.MonoFontPath
	}
	if changes.MediaVolume != nil {
		v := utils.ClampMediaVolume(*changes.MediaVolume)
		e.config.MediaVolume = &v
	}
	if changes.Language != "" {
		e.config.Language = changes.Language
	}
	if changes.TranslateTarget != "" {
		e.config.TranslateTarget = changes.TranslateTarget
	}
	if changes.ComposerSubmit != nil {
		e.config.ComposerSubmit = *changes.ComposerSubmit
	}
	if changes.SwipeAction != nil {
		e.config.SwipeAction = *changes.SwipeAction
	}
	if changes.CornerReaction != nil {
		e.config.CornerReaction = changes.CornerReaction
	}
	if changes.CornerReply != nil {
		e.config.CornerReply = changes.CornerReply
	}
	if changes.AyuImproveLinkPreviews != nil {
		e.config.AyuImproveLinkPreviews = *changes.AyuImproveLinkPreviews
	}
	applyAyuExtras(e.config, changes)
	if changes.AyuHideSimilarChannels != nil {
		e.config.AyuHideSimilarChannels = *changes.AyuHideSimilarChannels
	}
	if changes.AyuCollapseSimilarChannels != nil {
		e.config.AyuCollapseSimilarChannels = changes.AyuCollapseSimilarChannels
	}
	if changes.AyuAppIcon != nil {
		e.config.AyuAppIcon = *changes.AyuAppIcon
	}
	if changes.AyuAvatarCorners != nil {
		v := utils.ClampAvatarCorners(*changes.AyuAvatarCorners)
		e.config.AyuAvatarCorners = &v
	}
	if changes.AyuSingleCornerRadius != nil {
		e.config.AyuSingleCornerRadius = changes.AyuSingleCornerRadius
	}
	if changes.MaxCacheSize > 0 {
		e.config.MaxCacheSize = changes.MaxCacheSize
		e.maxCache = changes.MaxCacheSize
	}
	if changes.DownloadDir != "" {
		e.config.DownloadDir = changes.DownloadDir
		e.downloadDir = changes.DownloadDir
	}
	if changes.DrawerHiddenItems != nil {
		e.config.DrawerHiddenItems = changes.DrawerHiddenItems
	}
	if changes.StreamerMode != nil {
		e.config.StreamerMode = *changes.StreamerMode
	}
	if changes.SystemTray != nil {
		e.config.SystemTray = changes.SystemTray
	}
	if changes.NotifyPreviews != nil {
		e.config.NotifyPreviews = changes.NotifyPreviews
	}
	if changes.NotifySound != nil {
		e.config.NotifySound = *changes.NotifySound
	}
	if changes.AyuDeletedMark != nil {
		e.config.AyuDeletedMark = *changes.AyuDeletedMark
	}
	if changes.AyuEditedMark != nil {
		e.config.AyuEditedMark = *changes.AyuEditedMark
	}
	if changes.SendReadReceipts != nil {
		e.config.SendReadReceipts = *changes.SendReadReceipts
	}
	if changes.LocalReadMark != nil {
		e.config.LocalReadMark = *changes.LocalReadMark
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
	if changes.AyuSaveDeleted != nil {
		e.config.AyuSaveDeleted = changes.AyuSaveDeleted
		e.antiRecallMu.Lock()
		e.saveDeletedMessages = *changes.AyuSaveDeleted
		e.antiRecallMu.Unlock()
	}
	if changes.AyuSaveHistory != nil {
		e.config.AyuSaveHistory = changes.AyuSaveHistory
		e.antiRecallMu.Lock()
		e.saveMessagesHistory = *changes.AyuSaveHistory
		e.antiRecallMu.Unlock()
	}
	if changes.AyuSaveForBots != nil {
		e.config.AyuSaveForBots = changes.AyuSaveForBots
		e.antiRecallMu.Lock()
		e.saveForBots = *changes.AyuSaveForBots
		e.antiRecallMu.Unlock()
	}
	if changes.BubbleCorners != nil {
		e.config.BubbleCorners = changes.BubbleCorners
	}
	if changes.BubbleRadius != nil {
		v := utils.ClampBubbleRadius(*changes.BubbleRadius)
		e.config.BubbleRadius = &v
	}
	if changes.WideMultiplier != nil {
		v := utils.ClampWideMultiplier(*changes.WideMultiplier)
		e.config.WideMultiplier = &v
	}
	if changes.ProxyConfig != nil {
		e.config.ProxyConfig = *changes.ProxyConfig
	}
	if changes.HideAllChats != nil {
		e.config.HideAllChats = *changes.HideAllChats
	}

	return e.vault.SetConfig(e.config)
}

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

func (e *Engine) SetAccountGhost(accountID string, g GhostFlags) {
	e.ghostMu.Lock()
	defer e.ghostMu.Unlock()
	if e.ghostOverrides == nil {
		e.ghostOverrides = make(map[string]GhostFlags)
	}
	e.ghostOverrides[accountID] = g
}

func (e *Engine) ClearAccountGhostOverrides() {
	e.ghostMu.Lock()
	defer e.ghostMu.Unlock()
	e.ghostOverrides = nil
}

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

func (e *Engine) Shutdown() error {
	e.mu.Lock()
	e.shuttingDown = true
	e.mu.Unlock()

	e.stopVoiceRunner()
	if e.audioSession != nil {
		e.audioSession.Close()
		e.audioSession = nil
	}

	e.ctxCancel()

	if mm := e.mediaManager(); mm != nil {
		drained := make(chan struct{})
		go func() {
			mm.Stop()
			close(drained)
		}()
		select {
		case <-drained:
		case <-time.After(5 * time.Second):
		}
	}

	e.cancelAllExportSuggests()

	e.accountsMu.RLock()
	for _, acc := range e.accounts {
		if acc.cancelFunc != nil {
			acc.cancelFunc()
		}
	}
	e.accountsMu.RUnlock()

	done := make(chan struct{})
	go func() {
		e.wg.Wait()
		close(done)
	}()
	select {
	case <-done:
	case <-time.After(5 * time.Second):
	}

	if e.vault != nil {
		e.vault.Save()
	}

	if e.db != nil {
		e.db.Close()
	}

	if e.lockFile != nil {
		releaseLock(e.lockFile)
		e.lockFile = nil
	}

	return nil
}

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

	e.db.Exec("DELETE FROM messages WHERE account_id = ? AND chat_id = ?", accountID, chatID)
	e.db.Exec("DELETE FROM chats WHERE account_id = ? AND chat_id = ?", accountID, chatID)
	e.db.Exec("DELETE FROM media WHERE account_id = ? AND chat_id = ?", accountID, chatID)

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

func (e *Engine) ClearHistory(accountID, chatID string, revoke bool) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}

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

	e.db.Exec("DELETE FROM messages WHERE account_id = ? AND chat_id = ?", accountID, chatID)
	e.db.Exec("DELETE FROM media WHERE account_id = ? AND chat_id = ?", accountID, chatID)

	e.emitEvent(EventChatUpdated, accountID, map[string]string{
		"account_id": accountID,
		"chat_id":    chatID,
	})

	return nil
}

func (e *Engine) DeleteChat(accountID, chatID string, revoke bool) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}

	type historyDeleterRevoke interface {
		DeleteChatHistoryWithRevoke(chatID string, revoke bool) error
	}
	type historyDeleter interface {
		DeleteChatHistory(chatID string) error
	}
	if hd, ok := acc.Core.(historyDeleterRevoke); ok {
		_ = hd.DeleteChatHistoryWithRevoke(chatID, revoke)
	} else if hd, ok := acc.Core.(historyDeleter); ok {
		_ = hd.DeleteChatHistory(chatID)
	}

	e.db.Exec("DELETE FROM messages WHERE account_id = ? AND chat_id = ?", accountID, chatID)
	e.db.Exec("DELETE FROM chats WHERE account_id = ? AND chat_id = ?", accountID, chatID)
	e.db.Exec("DELETE FROM media WHERE account_id = ? AND chat_id = ?", accountID, chatID)

	e.emitEvent(EventChatRemoved, accountID, map[string]string{
		"account_id": accountID,
		"chat_id":    chatID,
	})

	return nil
}

func (e *Engine) JoinChat(accountID, channelName string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}

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

	go func() {
		time.Sleep(3 * time.Second)
		ctx := context.Background()
		e.syncAccount(ctx, accountID)
	}()

	return nil
}

func (e *Engine) CreateChannel(accountID, name, description string) (*ChatInfo, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account %q not found or not connected", accountID)
	}

	dialog, err := acc.Core.CreateChannel(name, description)
	if err != nil {
		return nil, err
	}

	if err := e.UpsertChat(accountID, *dialog); err != nil {
		return nil, fmt.Errorf("failed to cache new channel: %w", err)
	}

	go func() {
		ctx := context.Background()
		e.syncAccount(ctx, accountID)
	}()

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

func (e *Engine) AddMembers(accountID, chatID string, userIDs []string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}
	return acc.Core.AddMembers(chatID, userIDs)
}

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

func (e *Engine) DeleteScheduledMessages(accountID, chatID string, msgIDs []string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}

	type scheduledDeleter interface {
		DeleteScheduledMessages(chatID string, msgIDs []int) error
	}
	sd, ok := acc.Core.(scheduledDeleter)
	if !ok {
		return fmt.Errorf("core for account %q does not support scheduled messages", accountID)
	}

	intIDs := make([]int, 0, len(msgIDs))
	for _, id := range msgIDs {
		n, err := strconv.Atoi(id)
		if err != nil {
			return fmt.Errorf("invalid message ID %q: %w", id, err)
		}
		intIDs = append(intIDs, n)
	}

	return sd.DeleteScheduledMessages(chatID, intIDs)
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
	SlowmodeSeconds       int      `json:"slowmode_seconds"`
	JoinToSend            bool     `json:"join_to_send"`
	NoForwards            bool     `json:"no_forwards"`
	JoinRequest           bool     `json:"join_request"`
	IsForum               bool     `json:"is_forum"`
	Antispam              bool     `json:"antispam"`
	Signatures            bool     `json:"signatures"`
	SignatureProfiles     bool     `json:"signature_profiles"`
	PreHistoryHidden      bool     `json:"pre_history_hidden"`
	NoTranslations        bool     `json:"no_translations"`
	HasUsername           bool     `json:"has_username"`
	LinkedChatID          string   `json:"linked_chat_id"`
	PendingRequestsCount  int      `json:"pending_requests_count"`
	BoostLevel            int      `json:"boost_level"`
	IsMegagroup           bool     `json:"is_megagroup"`
	IsBroadcast           bool     `json:"is_broadcast"`
	IsGigagroup           bool     `json:"is_gigagroup"`
	AmCreator             bool     `json:"am_creator"`
	HasAdminRights        bool     `json:"has_admin_rights"`
	AdminCanChangeInfo    bool     `json:"admin_can_change_info"`
	CanSetStickers        bool     `json:"can_set_stickers"`
	AutoTranslateMinLevel int      `json:"auto_translate_min_level"`
	MigratedFromChatID    string   `json:"migrated_from_chat_id"`
	ReactionsMode         string   `json:"reactions_mode"`
	ReactionsAllowed      []string `json:"reactions_allowed"`
	PaidReactionsEnabled  bool     `json:"paid_reactions_enabled"`
	AntispamGroupSizeMin  int      `json:"antispam_group_size_min"`
	MemberCount           int      `json:"member_count"`
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

func (e *Engine) SetChatReactionsMode(accountID, chatID, mode string, emojis []string, maxCount int) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}
	type reactor interface {
		SetChatReactionsMode(chatID string, mode string, emojis []string, maxCount int) error
	}
	if r, ok := acc.Core.(reactor); ok {
		return r.SetChatReactionsMode(chatID, mode, emojis, maxCount)
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

func (e *Engine) SendLiveLocation(accountID, chatID string, lat, lon float64, periodSec int) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}
	type liveLocationSender interface {
		SendLiveLocation(chatID string, lat float64, lon float64, period int) (*cores.Message, error)
	}
	ls, ok := acc.Core.(liveLocationSender)
	if !ok {
		return fmt.Errorf("platform does not support live locations")
	}
	_, err := ls.SendLiveLocation(chatID, lat, lon, periodSec)
	return err
}

func (e *Engine) StopLiveLocation(accountID, chatID, msgID string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}
	type liveLocationStopper interface {
		StopLiveLocation(chatID, msgID string) error
	}
	ls, ok := acc.Core.(liveLocationStopper)
	if !ok {
		return fmt.Errorf("platform does not support live locations")
	}
	return ls.StopLiveLocation(chatID, msgID)
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

func applyAyuExtras(c *utils.AppConfig, changes *ConfigChanges) {
	if changes.AyuMsgSeconds != nil {
		c.AyuMsgSeconds = changes.AyuMsgSeconds
	}
	if changes.AyuFilterZalgo != nil {
		c.AyuFilterZalgo = changes.AyuFilterZalgo
	}
	if changes.AyuReactChannels != nil {
		c.AyuReactChannels = changes.AyuReactChannels
	}
	if changes.AyuReactGroups != nil {
		c.AyuReactGroups = changes.AyuReactGroups
	}
	if changes.AyuReactPrivate != nil {
		c.AyuReactPrivate = changes.AyuReactPrivate
	}
	if changes.AyuConfirmSticker != nil {
		c.AyuConfirmSticker = changes.AyuConfirmSticker
	}
	if changes.AyuConfirmGif != nil {
		c.AyuConfirmGif = changes.AyuConfirmGif
	}
	if changes.AyuConfirmVoice != nil {
		c.AyuConfirmVoice = changes.AyuConfirmVoice
	}
}
