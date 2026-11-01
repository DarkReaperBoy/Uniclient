//go:build windows

package engine

import (
	"os"
)

func acquireLock(path string) (*os.File, error) {
	f, err := os.OpenFile(path, os.O_CREATE|os.O_RDWR, 0o644)
	if err != nil {
		return nil, err
	}
	return f, nil
}

func releaseLock(f *os.File) {
	name := f.Name()
	f.Close()
	os.Remove(name)
}
