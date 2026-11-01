//go:build !js

package utils

import (
	"os"
	"path/filepath"
)

func readVaultBytes(path string) ([]byte, error) {
	return os.ReadFile(path)
}

func WriteVaultBytes(path string, data []byte) error {
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
	if d, err := os.Open(dir); err == nil {
		_ = d.Sync()
		_ = d.Close()
	}
	return nil
}

func vaultPathExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

func (v *Vault) mergeForeignVaultData() {}
