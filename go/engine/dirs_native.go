//go:build !js

package engine

import "os"

// ensureDir creates d (and parents) on native platforms.
func ensureDir(d string) error {
	return os.MkdirAll(d, 0o755)
}
