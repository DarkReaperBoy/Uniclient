package utils

import (
        "os"
        "path/filepath"
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
