package utils

import (
	"encoding/json"
	"os"
)

const (
	vaultBucketConfig   = "__config"
	vaultBucketSessions = "__sessions"
	vaultKeyApp         = "app"
)

// --- Vault extension methods for config + sessions ---

// Config returns the app config from the vault, or defaults if not set.
func (v *Vault) Config() *AppConfig {
	var cfg AppConfig
	if err := v.Get(vaultBucketConfig, vaultKeyApp, &cfg); err != nil {
		def := DefaultConfig()
		return &def
	}
	return &cfg
}

// SetConfig stores the app config in the vault and saves to disk.
func (v *Vault) SetConfig(cfg *AppConfig) error {
	if err := v.Put(vaultBucketConfig, vaultKeyApp, cfg); err != nil {
		return err
	}
	return v.Save()
}

// LoadSession unmarshals a session by account ID from the vault.
// Returns os.ErrNotExist if not found.
func (v *Vault) LoadSession(accountID string, dest any) error {
	err := v.Get(vaultBucketSessions, accountID, dest)
	if err == ErrBucketNotFound || err == ErrKeyNotFound {
		return os.ErrNotExist
	}
	return err
}

// SaveSession stores session data in the vault and saves to disk.
func (v *Vault) SaveSession(accountID string, data any) error {
	if err := v.Put(vaultBucketSessions, accountID, data); err != nil {
		return err
	}
	return v.Save()
}

// DeleteSession removes a session from the vault and saves.
func (v *Vault) DeleteSession(accountID string) error {
	_ = v.Delete(vaultBucketSessions, accountID)
	return v.Save()
}

// HasSession returns true if a session exists in the vault.
func (v *Vault) HasSession(accountID string) bool {
	v.mu.RLock()
	defer v.mu.RUnlock()
	b, ok := v.data[vaultBucketSessions]
	if !ok {
		return false
	}
	_, ok = b[accountID]
	return ok
}

// LoadSessionRaw returns raw JSON bytes for a session. Returns nil if not found.
func (v *Vault) LoadSessionRaw(accountID string) []byte {
	v.mu.RLock()
	defer v.mu.RUnlock()
	b, ok := v.data[vaultBucketSessions]
	if !ok {
		return nil
	}
	raw, ok := b[accountID]
	if !ok {
		return nil
	}
	return []byte(raw)
}

// SaveSessionRaw stores raw JSON bytes as a session and saves.
func (v *Vault) SaveSessionRaw(accountID string, raw []byte) error {
	v.mu.Lock()
	if v.data[vaultBucketSessions] == nil {
		v.data[vaultBucketSessions] = make(map[string]json.RawMessage)
	}
	v.data[vaultBucketSessions][accountID] = json.RawMessage(raw)
	v.dirty = true
	v.mu.Unlock()
	return v.Save()
}

// MigrateUniConfig imports data from an old uniconfig file into the vault.
// Imports config and all sessions, then deletes the uniconfig file.
func (v *Vault) MigrateUniConfig(uniConfigPath string) error {
	raw, err := os.ReadFile(uniConfigPath)
	if err != nil {
		return err
	}
	var data struct {
		Config   *AppConfig                 `json:"config"`
		Sessions map[string]json.RawMessage `json:"sessions"`
	}
	if err := json.Unmarshal(raw, &data); err != nil {
		return err
	}
	if data.Config != nil {
		_ = v.SetConfig(data.Config)
	}
	for id, sess := range data.Sessions {
		v.mu.Lock()
		if v.data[vaultBucketSessions] == nil {
			v.data[vaultBucketSessions] = make(map[string]json.RawMessage)
		}
		v.data[vaultBucketSessions][id] = sess
		v.dirty = true
		v.mu.Unlock()
	}
	if err := v.Save(); err != nil {
		return err
	}
	os.Remove(uniConfigPath)
	return nil
}

// --- SessionStore: per-account session accessor ---

// SessionStore is the interface cores use to load/save their session data.
type SessionStore struct {
	vault     *Vault
	accountID string
}

// NewSessionStore creates a SessionStore for a specific account.
func NewSessionStore(vault *Vault, accountID string) *SessionStore {
	return &SessionStore{vault: vault, accountID: accountID}
}

// AccountID returns the account ID this store is for.
func (s *SessionStore) AccountID() string { return s.accountID }

// Vault returns the underlying Vault.
func (s *SessionStore) Vault() *Vault { return s.vault }

// Load unmarshals the session into dest. Returns os.ErrNotExist if not found.
func (s *SessionStore) Load(dest any) error {
	return s.vault.LoadSession(s.accountID, dest)
}

// Save marshals data and stores it.
func (s *SessionStore) Save(data any) error {
	return s.vault.SaveSession(s.accountID, data)
}

// Delete removes the session.
func (s *SessionStore) Delete() error {
	return s.vault.DeleteSession(s.accountID)
}

// Has returns true if a session exists.
func (s *SessionStore) Has() bool {
	return s.vault.HasSession(s.accountID)
}

// LoadRaw returns raw JSON bytes.
func (s *SessionStore) LoadRaw() []byte {
	return s.vault.LoadSessionRaw(s.accountID)
}

// SaveRaw stores raw JSON bytes.
func (s *SessionStore) SaveRaw(raw []byte) error {
	return s.vault.SaveSessionRaw(s.accountID, raw)
}
