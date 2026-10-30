//go:build js

package utils

import (
	"encoding/json"
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

// mergeForeignVaultData is the js/wasm side of the flush-time cross-instance
// merge: localStorage is shared by every tab of the origin while each tab's
// engine holds its own in-memory vault image. Re-read the persisted vault,
// decrypt it with this instance's key, and fold entries ours does not know
// about into the in-memory image before the flush writes it back — without
// this, a save from one tab erases every account/session another tab wrote
// since this one booted (risk R1, data-loss class). Key-level conflicts go
// to this instance (mergeVaultData). Any decode/decrypt failure leaves the
// in-memory image untouched — writing our own flush still proceeds.
//
// Callers hold v.mu (Vault.flush is only called from Save/CreateVault on the
// instance's own goroutine).
//
// Remaining known limitation, accepted and documented: two tabs flushing
// in the SAME few-millisecond window can interleave (read, read, write,
// write) and one side's new keys still vanish. Flushes are rare,
// user-action-driven events seconds apart; the merge closes the realistic
// window. A browser-side mutex (Web Locks) cannot be awaited synchronously
// from Go wasm, so the residual race is the honest cost of the platform.
func (v *Vault) mergeForeignVaultData() {
	raw, err := readVaultBytes(v.path)
	if err != nil {
		return
	}
	var vf vaultFile
	if json.Unmarshal(raw, &vf) != nil || vf.Version != vaultVersion {
		return
	}
	plain, err := Decrypt(v.masterKey, vf.Ciphertext)
	if err != nil {
		return
	}
	var foreign map[string]map[string]json.RawMessage
	if json.Unmarshal(plain, &foreign) != nil {
		return
	}
	mergeVaultData(v.data, foreign)
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
