package utils

func VaultExists(path string) bool {
	return vaultPathExists(path)
}
