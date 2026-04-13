package utils

import (
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"testing"
)

func TestVault_CreateAndOpen(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "test.vault")

	v, err := CreateVault(path, "mypassword")
	if err != nil {
		t.Fatal(err)
	}

	v.Put("accounts", "telegram:123", map[string]string{"token": "abc"})
	v.Close()

	// Reopen
	v2, err := OpenVault(path, "mypassword")
	if err != nil {
		t.Fatal(err)
	}
	defer v2.Close()

	var result map[string]string
	if err := v2.Get("accounts", "telegram:123", &result); err != nil {
		t.Fatal(err)
	}
	if result["token"] != "abc" {
		t.Fatalf("expected token abc, got %s", result["token"])
	}
}

func TestVault_WrongPassword(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "test.vault")

	v, _ := CreateVault(path, "correct")
	v.Put("data", "key", "value")
	v.Close()

	_, err := OpenVault(path, "wrong")
	if err != ErrVaultWrongPass {
		t.Fatalf("expected ErrVaultWrongPass, got: %v", err)
	}
}

func TestVault_PutGetDelete(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "test.vault")

	v, _ := CreateVault(path, "pass")
	defer v.Close()

	// Put various types
	v.Put("config", "theme", "dark")
	v.Put("config", "language", "en")
	v.Put("keys", "dm:alice:bob", []byte{1, 2, 3})

	// Get string
	var theme string
	v.Get("config", "theme", &theme)
	if theme != "dark" {
		t.Fatalf("expected dark, got %s", theme)
	}

	// Get bytes
	var key []byte
	v.Get("keys", "dm:alice:bob", &key)
	if len(key) != 3 || key[0] != 1 {
		t.Fatalf("unexpected key: %v", key)
	}

	// Delete
	v.Delete("config", "theme")
	err := v.Get("config", "theme", &theme)
	if err != ErrKeyNotFound {
		t.Fatalf("expected ErrKeyNotFound after delete, got: %v", err)
	}

	// Bucket not found
	err = v.Get("nonexistent", "key", &theme)
	if err != ErrBucketNotFound {
		t.Fatalf("expected ErrBucketNotFound, got: %v", err)
	}
}

func TestVault_ListBucketsAndKeys(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "test.vault")

	v, _ := CreateVault(path, "pass")
	defer v.Close()

	v.Put("accounts", "tg:1", "data1")
	v.Put("accounts", "bale:2", "data2")
	v.Put("keys", "key1", "val1")

	buckets := v.ListBuckets()
	if len(buckets) != 2 {
		t.Fatalf("expected 2 buckets, got %d", len(buckets))
	}

	keys, _ := v.ListKeys("accounts")
	if len(keys) != 2 {
		t.Fatalf("expected 2 keys, got %d", len(keys))
	}
}

func TestVault_Persistence(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "test.vault")

	// Create and populate
	v, _ := CreateVault(path, "pw")
	v.Put("a", "1", "one")
	v.Put("b", "2", "two")
	v.Put("c", "3", "three")
	v.Close()

	// Reopen and verify all data
	v2, _ := OpenVault(path, "pw")
	defer v2.Close()

	var val string
	v2.Get("a", "1", &val)
	if val != "one" {
		t.Fatalf("expected one, got %s", val)
	}
	v2.Get("b", "2", &val)
	if val != "two" {
		t.Fatalf("expected two, got %s", val)
	}
	v2.Get("c", "3", &val)
	if val != "three" {
		t.Fatalf("expected three, got %s", val)
	}
}

func TestVault_ExportImport(t *testing.T) {
	dir := t.TempDir()
	srcPath := filepath.Join(dir, "src.vault")
	dstPath := filepath.Join(dir, "dst.vault")

	// Create source vault
	v, _ := CreateVault(srcPath, "exportpw")
	v.Put("data", "secret", "mysecret")
	v.Close()

	// Export
	v2, _ := OpenVault(srcPath, "exportpw")
	v2.Export(dstPath)
	v2.Close()

	// Import at new location
	v3, err := ImportVault(dstPath, filepath.Join(dir, "imported.vault"), "exportpw")
	if err != nil {
		t.Fatal(err)
	}
	defer v3.Close()

	var secret string
	v3.Get("data", "secret", &secret)
	if secret != "mysecret" {
		t.Fatalf("expected mysecret, got %s", secret)
	}
}

func TestVault_CorruptFile(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "corrupt.vault")

	os.WriteFile(path, []byte("not valid json"), 0600)
	_, err := OpenVault(path, "anything")
	if err == nil {
		t.Fatal("expected error on corrupt vault file")
	}
}

func TestVault_ConcurrentAccess(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "concurrent.vault")

	v, _ := CreateVault(path, "pw")
	defer v.Close()

	var wg sync.WaitGroup
	for i := 0; i < 100; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			key := fmt.Sprintf("key%d", i)
			v.Put("bucket", key, i)
			var val int
			v.Get("bucket", key, &val)
		}(i)
	}
	wg.Wait()

	// Verify at least some data is there
	keys, _ := v.ListKeys("bucket")
	if len(keys) != 100 {
		t.Fatalf("expected 100 keys, got %d", len(keys))
	}
}
