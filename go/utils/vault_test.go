package utils

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func newTestVault(t *testing.T) (*Vault, string) {
	t.Helper()
	path := filepath.Join(t.TempDir(), "test.vault")
	v, err := CreateVault(path, "hunter2")
	if err != nil {
		t.Fatalf("CreateVault: %v", err)
	}
	t.Cleanup(func() { v.Close() })
	return v, path
}

func TestVaultPutGetRoundTrip(t *testing.T) {
	v, _ := newTestVault(t)

	type account struct {
		Name  string
		Token string
		N     int
	}
	in := account{Name: "main", Token: "secret-token", N: 42}
	if err := v.Put("accounts", "main", in); err != nil {
		t.Fatalf("Put: %v", err)
	}
	var out account
	if err := v.Get("accounts", "main", &out); err != nil {
		t.Fatalf("Get: %v", err)
	}
	if out != in {
		t.Fatalf("round-trip mismatch: got %+v, want %+v", out, in)
	}
}

func TestVaultMissingKey(t *testing.T) {
	v, _ := newTestVault(t)
	var out string
	if err := v.Get("nope", "missing", &out); err == nil {
		t.Fatal("Get on missing key unexpectedly succeeded")
	}
}

// TestLoadSessionNotFoundMapsToErrNotExist pins LoadSession's
// documented contract ("Returns os.ErrNotExist if not found") on BOTH
// not-found branches: virgin vault = sessions bucket missing, saved
// vault = account key missing. Callers (matrix.go) distinguish
// "no session" from real failures with errors.Is(err, os.ErrNotExist),
// so this mapping must stay exact — slice-280 pin.
func TestLoadSessionNotFoundMapsToErrNotExist(t *testing.T) {
	v, _ := newTestVault(t)
	var dest any
	if err := v.LoadSession("acct-1", &dest); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("bucket-missing load: %v, want os.ErrNotExist", err)
	}
	if err := v.SaveSession("acct-1", []byte(`{"a":1}`)); err != nil {
		t.Fatalf("SaveSession: %v", err)
	}
	if err := v.LoadSession("acct-other", &dest); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("key-missing load: %v, want os.ErrNotExist", err)
	}
}

// TestVaultWriteKeepsOldFileWhenWriteFails: writeVaultBytes must be
// atomic — a replacement that cannot complete must leave the previous
// vault bytes intact. The old os.WriteFile implementation truncated the
// destination FIRST, so disk-full or a crash mid-save destroyed the
// only copy of every account credential (slice-282 finding; this test
// is RED against the truncating writer: the write "succeeds" and the
// original content is gone).
func TestVaultWriteKeepsOldFileWhenWriteFails(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "v.vault")
	if err := writeVaultBytes(path, []byte("v1-content")); err != nil {
		t.Fatalf("seed write: %v", err)
	}
	if err := os.Chmod(dir, 0o555); err != nil {
		t.Skipf("chmod dir: %v", err)
	}
	// Root (or CAP_DAC_OVERRIDE) ignores directory permissions; probe
	// before asserting on them.
	if probe, perr := os.CreateTemp(dir, "probe-*"); perr == nil {
		os.Remove(probe.Name())
		probe.Close()
		os.Chmod(dir, 0o755)
		t.Skip("directory permissions not enforced (running privileged)")
	}
	err := writeVaultBytes(path, []byte("v2-content"))
	os.Chmod(dir, 0o755) // restore for read + TempDir cleanup
	if err == nil {
		t.Fatal("expected the impossible write to report an error — the old os.WriteFile truncated and " +
			"'succeeded' silently, destroying the previous vault")
	}
	got, rerr := os.ReadFile(path)
	if rerr != nil {
		t.Fatalf("vault unreadable after failed write: %v", rerr)
	}
	if string(got) != "v1-content" {
		t.Fatalf("vault after failed write = %q, want the intact original %q", got, "v1-content")
	}
	entries, _ := os.ReadDir(dir)
	for _, e := range entries {
		if strings.HasSuffix(e.Name(), ".tmp") {
			t.Fatalf("temp litter left behind: %s", e.Name())
		}
	}
}

func TestVaultDelete(t *testing.T) {
	v, _ := newTestVault(t)
	if err := v.Put("kv", "k", "v"); err != nil {
		t.Fatal(err)
	}
	if err := v.Delete("kv", "k"); err != nil {
		t.Fatalf("Delete: %v", err)
	}
	var out string
	if err := v.Get("kv", "k", &out); err == nil {
		t.Fatal("Get after Delete unexpectedly succeeded")
	}
}

func TestVaultSaveAndReopen(t *testing.T) {
	v, path := newTestVault(t)
	_ = path
	if err := v.Put("cfg", "theme", "dark"); err != nil {
		t.Fatal(err)
	}
	if err := v.Save(); err != nil {
		t.Fatalf("Save: %v", err)
	}
	v.Close()

	v2, err := OpenVault(path, "hunter2")
	if err != nil {
		t.Fatalf("OpenVault: %v", err)
	}
	defer v2.Close()
	var theme string
	if err := v2.Get("cfg", "theme", &theme); err != nil {
		t.Fatalf("Get after reopen: %v", err)
	}
	if theme != "dark" {
		t.Fatalf("got theme %q, want %q", theme, "dark")
	}
}

func TestVaultReopenWrongPassword(t *testing.T) {
	v, path := newTestVault(t)
	if err := v.Put("cfg", "theme", "dark"); err != nil {
		t.Fatal(err)
	}
	if err := v.Save(); err != nil {
		t.Fatal(err)
	}
	v.Close()

	if _, err := OpenVault(path, "wrong-password"); err == nil {
		t.Fatal("OpenVault with wrong password unexpectedly succeeded")
	}
}

func TestVaultExportImport(t *testing.T) {
	v, _ := newTestVault(t)
	if err := v.Put("accounts", "a1", "token-123"); err != nil {
		t.Fatal(err)
	}
	if err := v.Save(); err != nil {
		t.Fatal(err)
	}

	dir := t.TempDir()
	exportPath := filepath.Join(dir, "export.vault")
	if err := v.Export(exportPath); err != nil {
		t.Fatalf("Export: %v", err)
	}
	if _, err := os.Stat(exportPath); err != nil {
		t.Fatalf("export file missing: %v", err)
	}

	// Import the export into a fresh path (password = source vault password;
	// the import re-saves the decrypted vault under the new path).
	importPath := filepath.Join(dir, "imported.vault")
	v2, err := ImportVault(exportPath, importPath, "hunter2")
	if err != nil {
		t.Fatalf("ImportVault: %v", err)
	}
	defer v2.Close()
	var tok string
	if err := v2.Get("accounts", "a1", &tok); err != nil {
		t.Fatalf("Get after import: %v", err)
	}
	if tok != "token-123" {
		t.Fatalf("got token %q, want %q", tok, "token-123")
	}
}
