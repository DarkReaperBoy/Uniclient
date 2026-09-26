//go:build !js

package utils

import (
	"os"
	"path/filepath"
)

// Vault persistence backend: a real encrypted file on native platforms.

func readVaultBytes(path string) ([]byte, error) {
	return os.ReadFile(path)
}

// writeVaultBytes replaces the vault file ATOMICALLY: bytes go to a
// sibling temp file, get fsynced, then are renamed over the destination
// (the file is created 0600, same as the old os.WriteFile). A plain
// os.WriteFile truncates the old vault BEFORE the new data lands, so
// disk-full or a crash mid-save destroyed the only copy of every
// account credential (slice-282 finding). Contract pinned by
// TestVaultWriteKeepsOldFileWhenWriteFails: a replacement that cannot
// complete must leave the previous bytes intact and no temp litter.
func writeVaultBytes(path string, data []byte) error {
	dir := filepath.Dir(path)
	tmp, err := os.CreateTemp(dir, ".vault-*.tmp")
	if err != nil {
		return err
	}
	tmpName := tmp.Name()
	_, werr := tmp.Write(data)
	serr := tmp.Sync()
	cerr := tmp.Close()
	if werr == nil {
		werr = serr
	}
	if werr == nil {
		werr = cerr
	}
	if werr == nil {
		werr = os.Rename(tmpName, path)
	}
	if werr != nil {
		os.Remove(tmpName)
		return werr
	}
	// Best-effort directory sync so the rename itself is durable; not
	// every filesystem supports fsync on a directory handle.
	if d, err := os.Open(dir); err == nil {
		_ = d.Sync()
		_ = d.Close()
	}
	return nil
}

// vaultPathExists reports whether a vault is stored at path.
func vaultPathExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}
