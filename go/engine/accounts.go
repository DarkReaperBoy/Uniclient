package engine

import (
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"sync"
	"time"

	"uniclient/cores"
)

// AccountInfo is the data returned to the UI for display.
type AccountInfo struct {
	ID          string `json:"id"`
	Platform    string `json:"platform"`
	DisplayName string `json:"display_name"`
	AvatarPath  string `json:"avatar_path"`
	SortOrder   int    `json:"sort_order"`
	ConnState   int    `json:"conn_state"`
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

// loadAccounts reads accounts from the DB into the in-memory map.
// Cores are NOT started here — call connectAccount() separately.
func (e *Engine) loadAccounts() error {
	rows, err := e.db.Query(
		`SELECT id, platform, display_name, avatar_path, sort_order
		 FROM accounts ORDER BY sort_order`)
	if err != nil {
		return fmt.Errorf("query accounts: %w", err)
	}
	defer rows.Close()

	for rows.Next() {
		var id, platform string
		var displayName, avatarPath sql.NullString
		var sortOrder int
		if err := rows.Scan(&id, &platform, &displayName, &avatarPath, &sortOrder); err != nil {
			return fmt.Errorf("scan account: %w", err)
		}
		e.accounts[id] = &Account{
			ID:          id,
			Platform:    platform,
			DisplayName: displayName.String,
			ConnState:   ConnDisconnected,
			SortOrder:   sortOrder,
		}
	}
	return rows.Err()
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
			SortOrder:   acc.SortOrder,
			ConnState:   int(acc.ConnState),
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

	vaultKey := "cred_" + id

	_, err := e.db.Exec(
		`INSERT INTO accounts (id, platform, vault_key, sort_order, created_at)
		 VALUES (?, ?, ?, ?, ?)`,
		id, platform, vaultKey, maxOrder, now)
	if err != nil {
		return "", fmt.Errorf("insert account: %w", err)
	}

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

	// Delete credentials from vault.
	vaultKey := "cred_" + accountID
	e.vault.Delete("accounts", vaultKey)
	e.vault.Save()

	// Delete all cached data (cascades via foreign key for chats).
	tx, err := e.db.Begin()
	if err != nil {
		return fmt.Errorf("begin delete tx: %w", err)
	}
	// Messages and media don't have FK cascade, delete explicitly.
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

	e.accountsMu.Lock()
	for i, id := range order {
		if acc, ok := e.accounts[id]; ok {
			acc.SortOrder = i
		}
	}
	e.accountsMu.Unlock()
	return nil
}

// SaveCredentials stores platform auth credentials in the vault.
func (e *Engine) SaveCredentials(accountID string, creds cores.AuthConfig) error {
	vaultKey := "cred_" + accountID
	if err := e.vault.Put("accounts", vaultKey, creds); err != nil {
		return fmt.Errorf("vault put: %w", err)
	}
	return e.vault.Save()
}

// LoadCredentials retrieves stored auth credentials from the vault.
func (e *Engine) LoadCredentials(accountID string) (*cores.AuthConfig, error) {
	vaultKey := "cred_" + accountID
	var creds cores.AuthConfig
	if err := e.vault.Get("accounts", vaultKey, &creds); err != nil {
		return nil, err
	}
	return &creds, nil
}

// UpdateAccountDisplay updates the display name and avatar for an account.
func (e *Engine) UpdateAccountDisplay(accountID, displayName, avatarPath string) error {
	_, err := e.db.Exec(
		`UPDATE accounts SET display_name = ?, avatar_path = ? WHERE id = ?`,
		displayName, avatarPath, accountID)
	if err != nil {
		return err
	}

	e.accountsMu.Lock()
	if acc, ok := e.accounts[accountID]; ok {
		acc.DisplayName = displayName
	}
	e.accountsMu.Unlock()
	return nil
}

// getAccount returns a live account by ID (thread-safe).
func (e *Engine) getAccount(accountID string) (*Account, bool) {
	e.accountsMu.RLock()
	defer e.accountsMu.RUnlock()
	acc, ok := e.accounts[accountID]
	return acc, ok
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
