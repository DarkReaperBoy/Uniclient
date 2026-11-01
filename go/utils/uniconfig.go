package utils

import (
	"encoding/json"
	"errors"
	"os"
)

const (
	vaultBucketConfig   = "__config"
	vaultBucketSessions = "__sessions"
	vaultBucketAccounts = "__accounts"
	vaultKeyApp         = "app"
)

type VaultAccountEntry struct {
	Platform    string          `json:"platform"`
	DisplayName string          `json:"display_name,omitempty"`
	AvatarPath  string          `json:"avatar_path,omitempty"`
	SortOrder   int             `json:"sort_order"`
	CreatedAt   int64           `json:"created_at"`
	Credentials json.RawMessage `json:"credentials,omitempty"`
	TestMode    bool            `json:"test_mode,omitempty"`
}

func (v *Vault) Config() *AppConfig {
	var cfg AppConfig
	if err := v.Get(vaultBucketConfig, vaultKeyApp, &cfg); err != nil {
		def := DefaultConfig()
		return &def
	}
	return &cfg
}

func (v *Vault) SetConfig(cfg *AppConfig) error {
	if err := v.Put(vaultBucketConfig, vaultKeyApp, cfg); err != nil {
		return err
	}
	return v.Save()
}

func (v *Vault) LoadSession(accountID string, dest any) error {
	err := v.Get(vaultBucketSessions, accountID, dest)
	if errors.Is(err, ErrBucketNotFound) || errors.Is(err, ErrKeyNotFound) {
		return os.ErrNotExist
	}
	return err
}

func (v *Vault) SaveSession(accountID string, data any) error {
	if err := v.Put(vaultBucketSessions, accountID, data); err != nil {
		return err
	}
	return v.Save()
}

func (v *Vault) DeleteSession(accountID string) error {
	_ = v.Delete(vaultBucketSessions, accountID)
	return v.Save()
}

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

func (v *Vault) PutAccount(accountID string, entry VaultAccountEntry) error {
	if err := v.Put(vaultBucketAccounts, accountID, entry); err != nil {
		return err
	}
	return v.Save()
}

func (v *Vault) GetAccount(accountID string) (*VaultAccountEntry, error) {
	var entry VaultAccountEntry
	if err := v.Get(vaultBucketAccounts, accountID, &entry); err != nil {
		return nil, err
	}
	return &entry, nil
}

func (v *Vault) DeleteAccount(accountID string) error {
	_ = v.Delete(vaultBucketAccounts, accountID)
	return v.Save()
}

func (v *Vault) ListAccountEntries() map[string]VaultAccountEntry {
	keys, err := v.ListKeys(vaultBucketAccounts)
	if err != nil {
		return make(map[string]VaultAccountEntry)
	}
	result := make(map[string]VaultAccountEntry, len(keys))
	for _, k := range keys {
		var entry VaultAccountEntry
		if err := v.Get(vaultBucketAccounts, k, &entry); err == nil {
			result[k] = entry
		}
	}
	return result
}

func (v *Vault) HasAccountsBucket() bool {
	v.mu.RLock()
	defer v.mu.RUnlock()
	_, ok := v.data[vaultBucketAccounts]
	return ok
}

type SessionStore struct {
	vault     *Vault
	accountID string
}

func NewSessionStore(vault *Vault, accountID string) *SessionStore {
	return &SessionStore{vault: vault, accountID: accountID}
}

func (s *SessionStore) AccountID() string { return s.accountID }

func (s *SessionStore) Vault() *Vault { return s.vault }

func (s *SessionStore) Load(dest any) error {
	return s.vault.LoadSession(s.accountID, dest)
}

func (s *SessionStore) Save(data any) error {
	return s.vault.SaveSession(s.accountID, data)
}

func (s *SessionStore) Delete() error {
	return s.vault.DeleteSession(s.accountID)
}

func (s *SessionStore) Has() bool {
	return s.vault.HasSession(s.accountID)
}

func (s *SessionStore) LoadRaw() []byte {
	return s.vault.LoadSessionRaw(s.accountID)
}

func (s *SessionStore) SaveRaw(raw []byte) error {
	return s.vault.SaveSessionRaw(s.accountID, raw)
}
