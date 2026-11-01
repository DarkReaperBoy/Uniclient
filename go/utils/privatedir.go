package utils

import (
	"os"
	"path/filepath"
)

func PrivateCacheDir(elem ...string) (string, error) {
	if base, err := os.UserCacheDir(); err == nil && base != "" {
		dir := filepath.Join(append([]string{base, "uniclient"}, elem...)...)
		if err := os.MkdirAll(dir, 0o700); err != nil {
			return "", err
		}
		return dir, nil
	}
	root, err := os.MkdirTemp("", "uniclient-*")
	if err != nil {
		return "", err
	}
	dir := filepath.Join(append([]string{root}, elem...)...)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return "", err
	}
	return dir, nil
}
