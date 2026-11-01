package bootstrap

import (
	"context"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strconv"

	"github.com/gotd/td/session"

	"uniclient/cores"
	"uniclient/engine"
	"uniclient/utils"
)

var eng *engine.Engine

var supportedPlatforms = []string{
	"telegram",
	"matrix",
	"irc",
	"xmpp",
	"github",
	"bale",
	"deltachat",
	"teamspeak",
	"mumble",
}

func SupportedPlatforms() []string {
	return append([]string(nil), supportedPlatforms...)
}

func Init(configDir, cacheDir, downloadDir, vaultPassword string, onEvent func([]byte)) (*engine.Engine, error) {
	e, err := engine.Init(configDir, cacheDir, downloadDir, vaultPassword)
	if err != nil {
		return nil, err
	}
	eng = e

	vault := e.Vault()

	migrateOldSessions(configDir, vault)

	engine.SetCoreFactory(func(platform, accountID string) (cores.Core, error) {
		store := utils.NewSessionStore(vault, accountID)
		switch platform {
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
		case "deltachat":
			return cores.NewDeltaChatCore(store), nil
		case "teamspeak":
			return cores.NewTeamSpeakCore(store), nil
		case "mumble":
			c := &cores.MumbleCore{}
			c.Session = store
			return c, nil
		default:
			return nil, fmt.Errorf("unknown platform: %s", platform)
		}
	})

	supported := make(map[string]bool, len(supportedPlatforms))
	for _, p := range supportedPlatforms {
		supported[p] = true
	}
	for _, acc := range e.ListAccounts() {
		if !supported[acc.Platform] {
			log.Printf("[bootstrap] removing account %s: platform %q is no longer supported", acc.ID, acc.Platform)
			if err := e.RemoveAccount(acc.ID); err != nil {
				log.Printf("[bootstrap] remove account %s: %v", acc.ID, err)
			}
		}
	}

	if onEvent != nil {
		e.SetEventCallback(onEvent)
	}

	return e, nil
}

func Shutdown() error {
	if eng == nil {
		return nil
	}
	return eng.Shutdown()
}

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

func migrateOldSessions(configDir string, vault *utils.Vault) {
	sessDir := filepath.Join(configDir, "sessions")
	platforms, err := os.ReadDir(sessDir)
	if err != nil {
		return
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
			accountID := f.Name()[:len(f.Name())-5]
			if vault.HasSession(accountID) {
				continue
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
