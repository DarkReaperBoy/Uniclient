//go:build js

package engine

import "os"

func acquireLock(_ string) (*os.File, error) { return nil, nil }
func releaseLock(_ *os.File)                 {}
