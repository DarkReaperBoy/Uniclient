//go:build js

package engine

// ensureDir is a no-op on js/wasm — there is no filesystem; the vault
// persists via localStorage (utils/vault_io_js.go) and the cache DB uses
// the in-memory null driver (db_driver_js.go).
func ensureDir(string) error { return nil }
