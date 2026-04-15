package utils

import (
	"encoding/json"
	"os"
	"path/filepath"
)

// SaveSession marshals data as indented JSON and writes to path atomically.
// It creates parent directories if they don't exist.
func SaveSession(path string, data interface{}) error {
	buf, err := json.MarshalIndent(data, "", "  ")
	if err != nil {
		return err
	}
	if dir := filepath.Dir(path); dir != "." {
		if err := os.MkdirAll(dir, 0700); err != nil {
			return err
		}
	}
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, buf, 0600); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

// LoadSession reads a JSON session file into dest.
// Returns nil if the file doesn't exist.
func LoadSession(path string, dest interface{}) error {
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return err
	}
	return json.Unmarshal(data, dest)
}
