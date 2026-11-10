//go:build js

package bootstrap

import (
	"fmt"

	"uniclient/cores"
	"uniclient/engine"
	"uniclient/utils"
)

var webPlatforms = []string{"github", "matrix", "bale"}

func buildPlatforms() []string {
	return webPlatforms
}

func setCoreFactory(e *engine.Engine, vault *utils.Vault) {
	engine.SetCoreFactory(func(platform, accountID string) (cores.Core, error) {
		store := utils.NewSessionStore(vault, accountID)
		switch platform {
		case "github":
			return cores.NewGitHubCore(store), nil
		case "matrix":
			return cores.NewMatrixCore(store), nil
		case "bale":
			return cores.NewBaleCore(store), nil
		default:
			return nil, fmt.Errorf("platform %q cannot connect from a browser", platform)
		}
	})
}
