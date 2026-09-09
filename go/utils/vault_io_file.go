//go:build !js

package utils

import "os"

// Vault persistence backend: a real encrypted file on native platforms.

func readVaultBytes(path string) ([]byte, error) {
	return os.ReadFile(path)
}

func writeVaultBytes(path string, data []byte) error {
	return os.WriteFile(path, data, 0o600)
}

// vaultPathExists reports whether a vault is stored at path.
func vaultPathExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}
