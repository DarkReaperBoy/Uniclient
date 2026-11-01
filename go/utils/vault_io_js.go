//go:build js

package utils

import (
	"encoding/json"
	"errors"
	"io/fs"
	"syscall/js"
)

func vaultStorageKey(path string) string {
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

func vaultPathExists(path string) bool {
	ls := js.Global().Get("localStorage")
	if !ls.Truthy() {
		return false
	}
	v := ls.Call("getItem", vaultStorageKey(path))
	return v.Type() == js.TypeString
}

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
