//go:build js

package engine

import "os"

// No file locking in WASM — single instance is enforced by the browser tab.
func acquireLock(_ string) (*os.File, error) { return nil, nil }
func releaseLock(_ *os.File)                 {}
