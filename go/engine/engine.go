package engine

import (
	"context"
	"database/sql"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"

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
	ConnAuthRequired
)

// Account holds the live state for a connected platform account.
type Account struct {
	ID          string
	Platform    string
	DisplayName string
	Core        cores.Core
	ConnState   ConnState
	SortOrder   int

	// reconnect state
	reconnect  reconnectState
	lastEvent  time.Time
	cancelFunc context.CancelFunc // cancels this account's goroutines
}

// Engine is the orchestration layer between cores and the Flutter UI.
type Engine struct {
	mu       sync.RWMutex
	db       *sql.DB
	vault    *utils.Vault
	config   *utils.AppConfig

	accounts   map[string]*Account // accountID → live account
	accountsMu sync.RWMutex

	eventCB func([]byte) // push serialized events to Dart

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

	media *MediaManager

	shuttingDown bool
	wg           sync.WaitGroup // tracks background goroutines
}

// Init initializes the engine: opens vault+DB, loads accounts, starts connections.
// configDir: path to config directory (contains vault, config.json)
// cacheDir: path to cache directory (contains cache.db, media/)
// downloadDir: path to user downloads directory
// vaultPassword: password for the encrypted vault (empty string = no vault encryption)
func Init(configDir, cacheDir, downloadDir, vaultPassword string) (*Engine, error) {
	e := &Engine{
		accounts:    make(map[string]*Account),
		configDir:   configDir,
		cacheDir:    cacheDir,
		downloadDir: downloadDir,
		mediaDir:    filepath.Join(cacheDir, "media"),
		maxCache:    1 << 30, // 1GB default
	}

	// Ensure directories exist.
	for _, d := range []string{configDir, cacheDir, downloadDir, e.mediaDir} {
		if err := os.MkdirAll(d, 0o755); err != nil {
			return nil, fmt.Errorf("create dir %s: %w", d, err)
		}
	}

	// Load config.
	cfgPath := filepath.Join(configDir, "config.json")
	cfg, err := utils.LoadConfig(cfgPath)
	if err != nil {
		return nil, fmt.Errorf("load config: %w", err)
	}
	utils.MergeDefaults(cfg)
	e.config = cfg

	if cfg.MaxCacheSize > 0 {
		e.maxCache = cfg.MaxCacheSize
	}

	// Open or create vault.
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

	// Open SQLite database.
	e.db, err = OpenDB(cacheDir)
	if err != nil {
		e.vault.Close()
		return nil, fmt.Errorf("open db: %w", err)
	}

	// Load accounts from DB.
	if err := e.loadAccounts(); err != nil {
		e.db.Close()
		e.vault.Close()
		return nil, fmt.Errorf("load accounts: %w", err)
	}

	// Resume pending operations from crash.
	e.resumePending()

	return e, nil
}

// SetEventCallback sets the function called when async events are pushed to Dart.
// The callback receives serialized event bytes.
func (e *Engine) SetEventCallback(cb func([]byte)) {
	e.mu.Lock()
	defer e.mu.Unlock()
	e.eventCB = cb
}

// pushEvent sends an event to the Dart side. Safe to call from any goroutine.
func (e *Engine) pushEvent(data []byte) {
	e.mu.RLock()
	cb := e.eventCB
	e.mu.RUnlock()
	if cb != nil {
		cb(data)
	}
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

	cfgPath := filepath.Join(e.configDir, "config.json")
	return utils.SaveConfig(cfgPath, e.config)
}

// ConfigChanges holds partial config updates from the bridge layer.
// Zero values are treated as "no change" (except MaxCacheSize where 0 means unlimited).
type ConfigChanges struct {
	Theme        string
	AccentColor  string
	FontScale    float64
	Language     string
	MaxCacheSize int64
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

	cfgPath := filepath.Join(e.configDir, "config.json")
	return utils.SaveConfig(cfgPath, e.config)
}

// Shutdown gracefully shuts down the engine: stops accepting operations,
// flushes pending writes, closes all cores, saves vault, closes DB.
func (e *Engine) Shutdown() error {
	e.mu.Lock()
	e.shuttingDown = true
	e.mu.Unlock()

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

	return nil
}
