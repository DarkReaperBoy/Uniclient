// Package bootstrap wires the engine for in-process hosts: engine init,
// the core factory for every platform, and session migration. This is the
// seam where a host (the GUI app, a test harness) plugs into the engine.
package bootstrap

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strconv"

	"github.com/gotd/td/session"

	"uniclient/cores"
	"uniclient/engine"
	"uniclient/utils"
)

// Engine returns the engine started by Init. Nil before the first Init.
func Engine() *engine.Engine { return eng }

var eng *engine.Engine

// Init initializes the engine and registers the core factory for every
// supported platform. Events are delivered to onEvent as JSON EngineEvent
// envelopes (nil = keep the default no-op).
func Init(configDir, cacheDir, downloadDir, vaultPassword string, onEvent func([]byte)) (*engine.Engine, error) {
	e, err := engine.Init(configDir, cacheDir, downloadDir, vaultPassword)
	if err != nil {
		return nil, err
	}
	eng = e

	vault := e.Vault()

	// Migrate old per-file sessions into vault.
	migrateOldSessions(configDir, vault)

	// Register the core factory — each core gets a SessionStore backed by vault.
	engine.SetCoreFactory(func(platform, accountID string) (cores.Core, error) {
		store := utils.NewSessionStore(vault, accountID)
		switch platform {
		case "demo":
			return cores.NewDemoCore(), nil
		case "telegram":
			apiID := 2040
			apiHash := "b18441a1ff607e10a989891a5462e627"
			if v := os.Getenv("TG_API_ID"); v != "" {
				if id, err := strconv.Atoi(v); err == nil {
					apiID = id
				}
			}
			if v := os.Getenv("TG_API_HASH"); v != "" {
				apiHash = v
			}
			// Test-server accounts (AyuGram Environment::Test) connect to the
			// test datacenter. Flag is persisted in the vault entry at creation.
			testMode := false
			if entry, err := vault.GetAccount(accountID); err == nil && entry != nil {
				testMode = entry.TestMode
			}
			return cores.NewTelegramCore(cores.TelegramConfig{
				APIID:          apiID,
				APIHash:        apiHash,
				SessionStorage: &vaultSessionStorage{store: store},
				UseTestDC:      testMode,
			}), nil
		case "bale":
			return cores.NewBaleCore(store), nil
		case "matrix":
			return cores.NewMatrixCore(store), nil
		case "irc":
			return cores.NewIRCCore(store), nil
		case "xmpp":
			return cores.NewXMPPCore(store), nil
		case "github":
			return cores.NewGitHubCore(store), nil
		case "rubika":
			return cores.NewRubikaCore(store), nil
		case "deltachat":
			return cores.NewDeltaChatCore(store), nil
		case "teamspeak":
			// Stale core: hidden from the GUI until rewritten (AGENTS.md §7).
			return cores.NewTeamSpeakCore(store), nil
		case "mumble":
			// Stale core: hidden from the GUI until rewritten (AGENTS.md §7).
			c := &cores.MumbleCore{}
			c.Session = store
			return c, nil
		default:
			return nil, fmt.Errorf("unknown platform: %s", platform)
		}
	})

	if onEvent != nil {
		e.SetEventCallback(onEvent)
	}

	return e, nil
}

// Shutdown stops the engine.
func Shutdown() error {
	if eng == nil {
		return nil
	}
	return eng.Shutdown()
}

// vaultSessionStorage adapts utils.SessionStore to gotd's session.Storage.
type vaultSessionStorage struct {
	store *utils.SessionStore
}

func (s *vaultSessionStorage) LoadSession(_ context.Context) ([]byte, error) {
	raw := s.store.LoadRaw()
	if raw == nil {
		return nil, session.ErrNotFound
	}
	return raw, nil
}

func (s *vaultSessionStorage) StoreSession(_ context.Context, data []byte) error {
	return s.store.SaveRaw(data)
}

// migrateOldSessions imports old per-file sessions into the vault.
// Scans configDir/sessions/<platform>/<accountID>.json and imports each.
func migrateOldSessions(configDir string, vault *utils.Vault) {
	sessDir := filepath.Join(configDir, "sessions")
	platforms, err := os.ReadDir(sessDir)
	if err != nil {
		return // no old sessions
	}
	migrated := false
	for _, pdir := range platforms {
		if !pdir.IsDir() {
			continue
		}
		platDir := filepath.Join(sessDir, pdir.Name())
		files, err := os.ReadDir(platDir)
		if err != nil {
			continue
		}
		for _, f := range files {
			if f.IsDir() || filepath.Ext(f.Name()) != ".json" {
				continue
			}
			accountID := f.Name()[:len(f.Name())-5] // strip .json
			if vault.HasSession(accountID) {
				continue // already migrated
			}
			raw, err := os.ReadFile(filepath.Join(platDir, f.Name()))
			if err != nil {
				continue
			}
			_ = vault.SaveSessionRaw(accountID, raw)
			migrated = true
		}
	}
	if migrated {
		_ = os.RemoveAll(sessDir)
	}
}
