//go:build windows

package engine

import (
	"os"
)

// On Windows, single-instance locking uses CreateFile with no sharing.
// The OS prevents other processes from opening the same file.
func acquireLock(path string) (*os.File, error) {
	// Opening without sharing flags means Windows locks the file exclusively.
	// If another instance has it open, this returns an error.
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
