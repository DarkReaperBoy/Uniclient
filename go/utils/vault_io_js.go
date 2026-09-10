//go:build js

package utils

import (
	"errors"
	"io/fs"
	"syscall/js"
)

// Vault persistence backend for the web build: browser localStorage keyed
// per vault path. There is no filesystem on js/wasm — the vault (accounts,
// credentials, config, the source of truth per engine/accounts.go) persists
// across page reloads here. The path argument is kept for API symmetry and
// hashed into the storage key so distinct vaults never collide.

func vaultStorageKey(path string) string {
	// One vault per origin in practice; keep a stable suffix.
	return "uniclient.vault"
}

func readVaultBytes(path string) ([]byte, error) {
	ls := js.Global().Get("localStorage")
	if !ls.Truthy() {
		return nil, fs.ErrNotExist
	}
	v := ls.Call("getItem", vaultStorageKey(path))
	if v.Type() != js.TypeString {
		return nil, fs.ErrNotExist
	}
	return []byte(v.String()), nil
}

func writeVaultBytes(path string, data []byte) error {
	ls := js.Global().Get("localStorage")
	if !ls.Truthy() {
		return errors.New("localStorage unavailable")
	}
	ls.Call("setItem", vaultStorageKey(path), string(data))
	return nil
}

// vaultPathExists reports whether a vault is stored at path.
func vaultPathExists(path string) bool {
	ls := js.Global().Get("localStorage")
	if !ls.Truthy() {
		return false
	}
	v := ls.Call("getItem", vaultStorageKey(path))
	return v.Type() == js.TypeString
}
