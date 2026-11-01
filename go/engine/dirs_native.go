//go:build !js

package engine

import "os"

func ensureDir(d string) error {
	return os.MkdirAll(d, 0o755)
}
