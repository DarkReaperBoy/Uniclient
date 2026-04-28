package engine

import (
	"context"
	"database/sql"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
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

	media   *MediaManager
	avatars *avatarState

	lockFile     *os.File       // single-instance lock file (held open with flock)
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
		avatars:     newAvatarState(),
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
	// Use pointers for booleans so zero-value (false) is distinguishable from "not set".
	SendReadReceipts   *bool
	SendTyping         *bool
	NotifyDMs          *bool
	NotifyGroups       *bool
	NotifyMentionsOnly *bool
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
	if changes.SendReadReceipts != nil {
		e.config.SendReadReceipts = *changes.SendReadReceipts
	}
	if changes.SendTyping != nil {
		e.config.SendTyping = *changes.SendTyping
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

	// Emit chat_removed event so Dart updates the list.
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

// ClearHistory deletes the message history for a chat on the server and locally,
// but keeps the chat visible in the chat list.
func (e *Engine) ClearHistory(accountID, chatID string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}

	// Platform-specific history deletion.
	type historyDeleter interface {
		DeleteChatHistory(chatID string) error
	}
	if hd, ok := acc.Core.(historyDeleter); ok {
		if err := hd.DeleteChatHistory(chatID); err != nil {
			return err
		}
	}

	// Remove messages from local cache.
	e.db.Exec("DELETE FROM messages WHERE account_id = ? AND chat_id = ?", accountID, chatID)
	e.db.Exec("DELETE FROM media WHERE account_id = ? AND chat_id = ?", accountID, chatID)

	// Emit event so Dart can refresh the chat view.
	e.emitEvent(EventChatUpdated, accountID, map[string]string{
		"account_id": accountID,
		"chat_id":    chatID,
	})

	return nil
}

// DeleteChat deletes a chat entirely — clears history and removes the chat.
// For groups/channels this is equivalent to leave + delete. For DMs it clears
// history and removes the chat from the list.
func (e *Engine) DeleteChat(accountID, chatID string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}

	// Clear server-side history first.
	type historyDeleter interface {
		DeleteChatHistory(chatID string) error
	}
	if hd, ok := acc.Core.(historyDeleter); ok {
		_ = hd.DeleteChatHistory(chatID) // best-effort
	}

	// Remove from local cache.
	e.db.Exec("DELETE FROM messages WHERE account_id = ? AND chat_id = ?", accountID, chatID)
	e.db.Exec("DELETE FROM chats WHERE account_id = ? AND chat_id = ?", accountID, chatID)
	e.db.Exec("DELETE FROM media WHERE account_id = ? AND chat_id = ?", accountID, chatID)

	// Emit chat_removed event so Dart updates the list.
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

	// Re-sync so the chat list updates for the Dart side.
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
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account %q not found or not connected", accountID)
	}

	dialog, err := acc.Core.CreateGroup(name, members)
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

type ChatPermissionFlags struct {
	SlowmodeSeconds int  `json:"slowmode_seconds"`
	JoinToSend      bool `json:"join_to_send"`
	NoForwards      bool `json:"no_forwards"`
	JoinRequest     bool `json:"join_request"`
	IsForum         bool `json:"is_forum"`
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
		SlowmodeSeconds: cf.SlowmodeSeconds,
		JoinToSend:      cf.JoinToSend,
		NoForwards:      cf.NoForwards,
		JoinRequest:     cf.JoinRequest,
		IsForum:         cf.IsForum,
	}, nil
}

type DefaultBannedRights struct {
	SendPlain         bool `json:"send_plain"`
	SendPhotos        bool `json:"send_photos"`
	SendVideos        bool `json:"send_videos"`
	SendRoundvideos   bool `json:"send_roundvideos"`
	SendAudios        bool `json:"send_audios"`
	SendVoices        bool `json:"send_voices"`
	SendDocs          bool `json:"send_docs"`
	SendStickers      bool `json:"send_stickers"`
	EmbedLinks        bool `json:"embed_links"`
	SendPolls         bool `json:"send_polls"`
	InviteUsers       bool `json:"invite_users"`
	ManageTopics      bool `json:"manage_topics"`
	PinMessages       bool `json:"pin_messages"`
	EditRank          bool `json:"edit_rank"`
	ChangeInfo        bool `json:"change_info"`
	SlowmodeSeconds   int  `json:"slowmode_seconds"`
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
		SendPlain:       cr.SendPlain,
		SendPhotos:      cr.SendPhotos,
		SendVideos:      cr.SendVideos,
		SendRoundvideos: cr.SendRoundvideos,
		SendAudios:      cr.SendAudios,
		SendVoices:      cr.SendVoices,
		SendDocs:        cr.SendDocs,
		SendStickers:    cr.SendStickers,
		EmbedLinks:      cr.EmbedLinks,
		SendPolls:       cr.SendPolls,
		InviteUsers:     cr.InviteUsers,
		ManageTopics:    cr.ManageTopics,
		PinMessages:     cr.PinMessages,
		EditRank:        cr.EditRank,
		ChangeInfo:      cr.ChangeInfo,
		SlowmodeSeconds: cr.SlowmodeSeconds,
	}, nil
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
