package bootstrap

import (
	"log"
	"os"
	"path/filepath"

	"uniclient/engine"
	"uniclient/utils"
)

var eng *engine.Engine

var productPlatforms = []string{
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
	return append([]string(nil), buildPlatforms()...)
}

func Init(configDir, cacheDir, downloadDir, vaultPassword string, onEvent func([]byte)) (*engine.Engine, error) {
	e, err := engine.Init(configDir, cacheDir, downloadDir, vaultPassword)
	if err != nil {
		return nil, err
	}
	eng = e

	vault := e.Vault()

	migrateOldSessions(configDir, vault)

	setCoreFactory(e, vault)

	supported := make(map[string]bool, len(productPlatforms))
	for _, p := range productPlatforms {
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
