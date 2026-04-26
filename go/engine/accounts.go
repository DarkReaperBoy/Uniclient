package engine

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
	"strings"
	"sync"
	"time"

	"uniclient/cores"
	"uniclient/utils"
)

// AccountInfo is the data returned to the UI for display.
type AccountInfo struct {
	ID          string `json:"id"`
	Platform    string `json:"platform"`
	DisplayName string `json:"display_name"`
	Phone       string `json:"phone,omitempty"`
	Username    string `json:"username,omitempty"`
	AvatarPath  string `json:"avatar_path"`
	SortOrder   int    `json:"sort_order"`
	ConnState   int    `json:"conn_state"`
	IsVerified  bool   `json:"is_verified"`
	IsPremium   bool   `json:"is_premium"`
}

// generateAccountID creates an ID like "tg_a1b2c3d4" (platform prefix + 8 random hex).
func generateAccountID(platform string) string {
	prefix := platform
	if len(prefix) > 4 {
		prefix = prefix[:4]
	}
	b := make([]byte, 4)
	rand.Read(b)
	return prefix + "_" + hex.EncodeToString(b)
}

// loadAccounts reads accounts from the vault (source of truth) into the
// in-memory map, and ensures DB cache rows exist for each.
func (e *Engine) loadAccounts() error {
	entries := e.vault.ListAccountEntries()

	for id, entry := range entries {
		e.accounts[id] = &Account{
			ID:          id,
			Platform:    entry.Platform,
			DisplayName: entry.DisplayName,
			ConnState:   ConnDisconnected,
			SortOrder:   entry.SortOrder,
		}

		// Ensure DB cache row exists.
		e.db.Exec(
			`INSERT OR IGNORE INTO accounts (id, platform, display_name, avatar_path, sort_order, created_at)
			 VALUES (?, ?, ?, ?, ?, ?)`,
			id, entry.Platform, entry.DisplayName, entry.AvatarPath, entry.SortOrder, entry.CreatedAt)
	}
	return nil
}

// migrateAccountsToVault migrates account data from the old DB+vault format
// into the unified __accounts vault bucket. Runs once on first startup after upgrade.
func (e *Engine) migrateAccountsToVault() {
	if e.vault.HasAccountsBucket() {
		return // already migrated
	}

	rows, err := e.db.Query(
		`SELECT id, platform, display_name, avatar_path, sort_order, created_at
		 FROM accounts ORDER BY sort_order`)
	if err != nil {
		return // no DB accounts = fresh install
	}
	defer rows.Close()

	migrated := 0
	for rows.Next() {
		var id, platform string
		var displayName, avatarPath interface{}
		var sortOrder int
		var createdAt int64
		if err := rows.Scan(&id, &platform, &displayName, &avatarPath, &sortOrder, &createdAt); err != nil {
			continue
		}

		entry := utils.VaultAccountEntry{
			Platform:  platform,
			SortOrder: sortOrder,
			CreatedAt: createdAt,
		}
		if dn, ok := displayName.(string); ok {
			entry.DisplayName = dn
		}
		if ap, ok := avatarPath.(string); ok {
			entry.AvatarPath = ap
		}

		// Pull old credentials from vault "accounts" bucket.
		var credRaw json.RawMessage
		if err := e.vault.Get("accounts", "cred_"+id, &credRaw); err == nil {
			entry.Credentials = credRaw
		}

		_ = e.vault.PutAccount(id, entry)
		migrated++
	}

	// Clean up old cred_* keys.
	if migrated > 0 {
		if keys, err := e.vault.ListKeys("accounts"); err == nil {
			for _, k := range keys {
				if strings.HasPrefix(k, "cred_") {
					_ = e.vault.Delete("accounts", k)
				}
			}
			_ = e.vault.Save()
		}
		log.Printf("[engine] migrated %d accounts from DB+vault to unified vault", migrated)
	}
}

// ListAccounts returns info about all accounts, sorted by sort_order.
func (e *Engine) ListAccounts() []AccountInfo {
	e.accountsMu.RLock()
	defer e.accountsMu.RUnlock()

	list := make([]AccountInfo, 0, len(e.accounts))
	for _, acc := range e.accounts {
		list = append(list, AccountInfo{
			ID:          acc.ID,
			Platform:    acc.Platform,
			DisplayName: acc.DisplayName,
			Phone:       acc.Phone,
			Username:    acc.Username,
			SortOrder:   acc.SortOrder,
			ConnState:   int(acc.ConnState),
			IsVerified:  acc.IsVerified,
			IsPremium:   acc.IsPremium,
		})
	}

	// Sort by sort_order.
	for i := 1; i < len(list); i++ {
		for j := i; j > 0 && list[j].SortOrder < list[j-1].SortOrder; j-- {
			list[j], list[j-1] = list[j-1], list[j]
		}
	}
	return list
}

// AddAccount creates a new account entry for the given platform.
// Returns the generated account ID. The account is NOT connected yet —
// call StartAuth() to begin the authentication flow.
func (e *Engine) AddAccount(platform string) (string, error) {
	id := generateAccountID(platform)
	now := time.Now().UnixMilli()

	// Get next sort_order.
	e.accountsMu.RLock()
	maxOrder := 0
	for _, acc := range e.accounts {
		if acc.SortOrder >= maxOrder {
			maxOrder = acc.SortOrder + 1
		}
	}
	e.accountsMu.RUnlock()

	// Write to vault (source of truth).
	entry := utils.VaultAccountEntry{
		Platform:  platform,
		SortOrder: maxOrder,
		CreatedAt: now,
	}
	if err := e.vault.PutAccount(id, entry); err != nil {
		return "", fmt.Errorf("vault put account: %w", err)
	}

	// Insert DB cache row.
	e.db.Exec(
		`INSERT OR IGNORE INTO accounts (id, platform, sort_order, created_at)
		 VALUES (?, ?, ?, ?)`,
		id, platform, maxOrder, now)

	acc := &Account{
		ID:        id,
		Platform:  platform,
		ConnState: ConnDisconnected,
		SortOrder: maxOrder,
	}

	e.accountsMu.Lock()
	e.accounts[id] = acc
	e.accountsMu.Unlock()

	return id, nil
}

// RemoveAccount disconnects and deletes an account, including all its cached data.
func (e *Engine) RemoveAccount(accountID string) error {
	e.accountsMu.Lock()
	acc, ok := e.accounts[accountID]
	if !ok {
		e.accountsMu.Unlock()
		return fmt.Errorf("account %q not found", accountID)
	}
	delete(e.accounts, accountID)
	e.accountsMu.Unlock()

	// Disconnect core.
	if acc.Core != nil {
		if acc.cancelFunc != nil {
			acc.cancelFunc()
		}
		acc.Core.Close()
	}

	// Delete from vault: account entry (includes credentials) + session.
	e.vault.DeleteAccount(accountID)
	e.vault.DeleteSession(accountID)

	// Delete all cached data from DB.
	tx, err := e.db.Begin()
	if err != nil {
		return fmt.Errorf("begin delete tx: %w", err)
	}
	tx.Exec("DELETE FROM messages WHERE account_id = ?", accountID)
	tx.Exec("DELETE FROM media WHERE account_id = ?", accountID)
	tx.Exec("DELETE FROM users WHERE account_id = ?", accountID)
	tx.Exec("DELETE FROM pending WHERE account_id = ?", accountID)
	tx.Exec("DELETE FROM chats WHERE account_id = ?", accountID)
	tx.Exec("DELETE FROM accounts WHERE id = ?", accountID)
	if err := tx.Commit(); err != nil {
		return fmt.Errorf("commit delete: %w", err)
	}

	return nil
}

// ReorderAccounts sets the sort order based on the provided list of account IDs.
func (e *Engine) ReorderAccounts(order []string) error {
	// Update vault (source of truth).
	for i, id := range order {
		entry, err := e.vault.GetAccount(id)
		if err != nil {
			continue
		}
		entry.SortOrder = i
		_ = e.vault.PutAccount(id, *entry)
	}

	// Update DB cache.
	tx, err := e.db.Begin()
	if err != nil {
		return err
	}
	for i, id := range order {
		tx.Exec("UPDATE accounts SET sort_order = ? WHERE id = ?", i, id)
	}
	if err := tx.Commit(); err != nil {
		return err
	}

	// Update in-memory.
	e.accountsMu.Lock()
	for i, id := range order {
		if acc, ok := e.accounts[id]; ok {
			acc.SortOrder = i
		}
	}
	e.accountsMu.Unlock()
	return nil
}

// SaveCredentials stores platform auth credentials in the vault account entry.
func (e *Engine) SaveCredentials(accountID string, creds cores.AuthConfig) error {
	entry, err := e.vault.GetAccount(accountID)
	if err != nil {
		return fmt.Errorf("get account for creds: %w", err)
	}
	raw, err := json.Marshal(creds)
	if err != nil {
		return fmt.Errorf("marshal credentials: %w", err)
	}
	entry.Credentials = raw
	return e.vault.PutAccount(accountID, *entry)
}

// LoadCredentials retrieves stored auth credentials from the vault account entry.
func (e *Engine) LoadCredentials(accountID string) (*cores.AuthConfig, error) {
	entry, err := e.vault.GetAccount(accountID)
	if err != nil {
		return nil, fmt.Errorf("get account: %w", err)
	}
	if entry.Credentials == nil {
		return nil, fmt.Errorf("no credentials for %s", accountID)
	}
	var creds cores.AuthConfig
	if err := json.Unmarshal(entry.Credentials, &creds); err != nil {
		return nil, fmt.Errorf("unmarshal credentials: %w", err)
	}
	return &creds, nil
}

// UpdateAccountDisplay updates the display name and avatar for an account.
func (e *Engine) UpdateAccountDisplay(accountID, displayName, avatarPath string) error {
	// Update vault (source of truth).
	entry, err := e.vault.GetAccount(accountID)
	if err != nil {
		return fmt.Errorf("get account: %w", err)
	}
	if displayName != "" {
		entry.DisplayName = displayName
	}
	if avatarPath != "" {
		entry.AvatarPath = avatarPath
	}
	if err := e.vault.PutAccount(accountID, *entry); err != nil {
		return fmt.Errorf("put account: %w", err)
	}

	// Update DB cache.
	e.db.Exec(
		`UPDATE accounts SET display_name = ?, avatar_path = ? WHERE id = ?`,
		entry.DisplayName, entry.AvatarPath, accountID)

	// Update in-memory.
	e.accountsMu.Lock()
	if acc, ok := e.accounts[accountID]; ok {
		acc.DisplayName = entry.DisplayName
	}
	e.accountsMu.Unlock()

	// Notify Dart so the sidebar user panel updates.
	e.emitAccountList()
	return nil
}

// getAccount returns a live account by ID (thread-safe).
func (e *Engine) getAccount(accountID string) (*Account, bool) {
	e.accountsMu.RLock()
	defer e.accountsMu.RUnlock()
	acc, ok := e.accounts[accountID]
	return acc, ok
}

func (e *Engine) GetAccountCore(accountID string) cores.Core {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil
	}
	return acc.Core
}

// setConnState updates an account's connection state.
func (e *Engine) setConnState(accountID string, state ConnState) {
	e.accountsMu.Lock()
	if acc, ok := e.accounts[accountID]; ok {
		acc.ConnState = state
	}
	e.accountsMu.Unlock()
}

// isDuplicateAccount checks if an account with the same platform+userID already exists.
func (e *Engine) isDuplicateAccount(platform, userID string) (string, bool) {
	e.accountsMu.RLock()
	defer e.accountsMu.RUnlock()
	for _, acc := range e.accounts {
		if acc.Platform == platform && acc.Core != nil {
			profile, err := acc.Core.GetProfile("")
			if err == nil && profile != nil && profile.ID == userID {
				return acc.ID, true
			}
		}
	}
	return "", false
}

// CoreFactory is a function that creates a new core instance for a platform.
// The engine needs this to instantiate cores on account connect.
type CoreFactory func(platform, accountID string) (cores.Core, error)

// coreFactory is set by the bridge/main code so the engine can create cores.
var (
	coreFactoryMu sync.Mutex
	coreFactory    CoreFactory
)

// SetCoreFactory registers the function used to create new core instances.
func SetCoreFactory(f CoreFactory) {
	coreFactoryMu.Lock()
	defer coreFactoryMu.Unlock()
	coreFactory = f
}

func getCoreFactory() CoreFactory {
	coreFactoryMu.Lock()
	defer coreFactoryMu.Unlock()
	return coreFactory
}

// marshalJSON marshals v to JSON bytes, ignoring errors.
func marshalJSON(v any) []byte {
	b, _ := json.Marshal(v)
	return b
}
