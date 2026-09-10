package utils

// VaultExists reports whether a vault is persisted at path (file on native
// platforms, localStorage entry on the web build).
func VaultExists(path string) bool {
	return vaultPathExists(path)
}
