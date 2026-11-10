//go:build !js

package bootstrap

import (
	"context"
	"fmt"
	"os"
	"strconv"

	"github.com/gotd/td/session"

	"uniclient/cores"
	"uniclient/engine"
	"uniclient/utils"
)

func buildPlatforms() []string {
	return productPlatforms
}

func setCoreFactory(e *engine.Engine, vault *utils.Vault) {
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
