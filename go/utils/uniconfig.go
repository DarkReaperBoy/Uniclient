package utils

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sync"
)

// UniConfig is a single-file store for app config + all platform sessions.
// On disk it's a JSON file named "uniconfig" containing:
//
//	{
//	  "config": { ...AppConfig... },
//	  "sessions": {
//	    "tele_abc123": { ...session data... },
//	    "bale_def456": { ...session data... },
//	    ...
//	  }
//	}
type UniConfig struct {
	mu   sync.Mutex
	path string
	data uniConfigData
}

type uniConfigData struct {
	Config   *AppConfig                        `json:"config"`
	Sessions map[string]json.RawMessage        `json:"sessions"`
}

// OpenUniConfig opens or creates the unified config file at dir/uniconfig.
func OpenUniConfig(dir string) (*UniConfig, error) {
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return nil, err
	}
	path := filepath.Join(dir, "uniconfig")
	uc := &UniConfig{path: path}

	raw, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			cfg := DefaultConfig()
			uc.data = uniConfigData{
				Config:   &cfg,
				Sessions: make(map[string]json.RawMessage),
			}
			return uc, uc.flush()
		}
		return nil, err
	}

	if err := json.Unmarshal(raw, &uc.data); err != nil {
		return nil, err
	}
	if uc.data.Config == nil {
		cfg := DefaultConfig()
		uc.data.Config = &cfg
	}
	if uc.data.Sessions == nil {
		uc.data.Sessions = make(map[string]json.RawMessage)
	}
	return uc, nil
}

// Config returns the app config.
func (uc *UniConfig) Config() *AppConfig {
	uc.mu.Lock()
	defer uc.mu.Unlock()
	return uc.data.Config
}

// SetConfig replaces the app config and saves.
func (uc *UniConfig) SetConfig(cfg *AppConfig) error {
	uc.mu.Lock()
	defer uc.mu.Unlock()
	uc.data.Config = cfg
	return uc.flush()
}

// LoadSession unmarshals a session by account ID into dest.
// Returns os.ErrNotExist if not found.
func (uc *UniConfig) LoadSession(accountID string, dest any) error {
	uc.mu.Lock()
	defer uc.mu.Unlock()

	raw, ok := uc.data.Sessions[accountID]
	if !ok {
		return os.ErrNotExist
	}
	return json.Unmarshal(raw, dest)
}

// SaveSession marshals data and stores it under accountID, then flushes.
func (uc *UniConfig) SaveSession(accountID string, data any) error {
	uc.mu.Lock()
	defer uc.mu.Unlock()

	raw, err := json.Marshal(data)
	if err != nil {
		return err
	}
	uc.data.Sessions[accountID] = raw
	return uc.flush()
}

// DeleteSession removes a session by account ID and flushes.
func (uc *UniConfig) DeleteSession(accountID string) error {
	uc.mu.Lock()
	defer uc.mu.Unlock()

	delete(uc.data.Sessions, accountID)
	return uc.flush()
}

// HasSession returns true if a session exists for the given account ID.
func (uc *UniConfig) HasSession(accountID string) bool {
	uc.mu.Lock()
	defer uc.mu.Unlock()
	_, ok := uc.data.Sessions[accountID]
	return ok
}

// LoadSessionRaw returns the raw JSON bytes for an account's session.
// Returns nil if not found.
func (uc *UniConfig) LoadSessionRaw(accountID string) []byte {
	uc.mu.Lock()
	defer uc.mu.Unlock()
	raw, ok := uc.data.Sessions[accountID]
	if !ok {
		return nil
	}
	return []byte(raw)
}

// SaveSessionRaw stores raw JSON bytes as a session.
func (uc *UniConfig) SaveSessionRaw(accountID string, raw []byte) error {
	uc.mu.Lock()
	defer uc.mu.Unlock()
	uc.data.Sessions[accountID] = json.RawMessage(raw)
	return uc.flush()
}

// Path returns the file path.
func (uc *UniConfig) Path() string { return uc.path }

// Save forces a flush to disk.
func (uc *UniConfig) Save() error {
	uc.mu.Lock()
	defer uc.mu.Unlock()
	return uc.flush()
}

// flush writes atomically (tmp + rename).
func (uc *UniConfig) flush() error {
	buf, err := json.MarshalIndent(uc.data, "", "  ")
	if err != nil {
		return err
	}
	tmp := uc.path + ".tmp"
	if err := os.WriteFile(tmp, buf, 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, uc.path)
}

// MigrateOldConfig imports an old config.json into the unified file.
func (uc *UniConfig) MigrateOldConfig(configPath string) error {
	data, err := os.ReadFile(configPath)
	if err != nil {
		return err
	}
	var cfg AppConfig
	if err := json.Unmarshal(data, &cfg); err != nil {
		return err
	}
	uc.mu.Lock()
	uc.data.Config = &cfg
	err = uc.flush()
	uc.mu.Unlock()
	return err
}

// MigrateOldSession imports an old per-file session into the unified store.
func (uc *UniConfig) MigrateOldSession(accountID, sessionPath string) error {
	data, err := os.ReadFile(sessionPath)
	if err != nil {
		return err
	}
	// Validate it's JSON
	var raw json.RawMessage
	if err := json.Unmarshal(data, &raw); err != nil {
		return err
	}
	uc.mu.Lock()
	uc.data.Sessions[accountID] = raw
	err = uc.flush()
	uc.mu.Unlock()
	return err
}

// SessionStore is the interface cores use to load/save their session data
// from the unified config file.
type SessionStore struct {
	uc        *UniConfig
	accountID string
}

// NewSessionStore creates a SessionStore for a specific account.
func NewSessionStore(uc *UniConfig, accountID string) *SessionStore {
	return &SessionStore{uc: uc, accountID: accountID}
}

// AccountID returns the account ID this store is for.
func (s *SessionStore) AccountID() string { return s.accountID }

// UC returns the underlying UniConfig.
func (s *SessionStore) UC() *UniConfig { return s.uc }

// Load unmarshals the session into dest. Returns os.ErrNotExist if not found.
func (s *SessionStore) Load(dest any) error {
	return s.uc.LoadSession(s.accountID, dest)
}

// Save marshals data and stores it.
func (s *SessionStore) Save(data any) error {
	return s.uc.SaveSession(s.accountID, data)
}

// Delete removes the session.
func (s *SessionStore) Delete() error {
	return s.uc.DeleteSession(s.accountID)
}

// Has returns true if a session exists.
func (s *SessionStore) Has() bool {
	return s.uc.HasSession(s.accountID)
}

// LoadRaw returns raw JSON bytes.
func (s *SessionStore) LoadRaw() []byte {
	return s.uc.LoadSessionRaw(s.accountID)
}

// SaveRaw stores raw JSON bytes.
func (s *SessionStore) SaveRaw(raw []byte) error {
	return s.uc.SaveSessionRaw(s.accountID, raw)
}

