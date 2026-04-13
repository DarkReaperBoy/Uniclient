package utils

import (
	"bytes"
	"crypto/rand"
	"encoding/base64"
	"path/filepath"
	"testing"
)

// Integration test: full encryption pipeline
// compose → split → compress → encrypt → send → receive → decrypt → decompress → reassemble → verify
func TestIntegrationFullEncryptionPipeline(t *testing.T) {
	// 1. Compose: generate a realistic multi-part message (50KB random text)
	original := make([]byte, 50*1024)
	rand.Read(original)

	// 2. Split into chunks (simulate Bale's 19.5MB limit, but use smaller for speed)
	chunkSize := int64(20 * 1024) // 20KB chunks
	parts, err := SplitFile(bytes.NewReader(original), chunkSize)
	if err != nil {
		t.Fatalf("split: %v", err)
	}
	if len(parts) != 3 {
		t.Fatalf("expected 3 parts, got %d", len(parts))
	}

	// 3. Compress each part
	compressed := make([][]byte, len(parts))
	for i, p := range parts {
		compressed[i], err = Compress(p)
		if err != nil {
			t.Fatalf("compress part %d: %v", i, err)
		}
	}

	// 4. Encrypt each part (ECDH key exchange first)
	alice, _ := GenerateX25519KeyPair()
	bob, _ := GenerateX25519KeyPair()
	sharedA, _ := ECDH(alice.PrivateKey, bob.PublicKey)
	sessionKey, _ := DeriveSessionKey(sharedA, "alice", "bob", "conv-integration")

	encrypted := make([][]byte, len(compressed))
	for i, c := range compressed {
		encrypted[i], err = Encrypt(sessionKey, c)
		if err != nil {
			t.Fatalf("encrypt part %d: %v", i, err)
		}
	}

	// 5. "Send" — simulate by encoding to base64 (as would go over the wire)
	wire := make([]string, len(encrypted))
	for i, e := range encrypted {
		wire[i] = base64.StdEncoding.EncodeToString(e)
	}

	// 6. "Receive" — decode from base64
	received := make([][]byte, len(wire))
	for i, w := range wire {
		received[i], err = base64.StdEncoding.DecodeString(w)
		if err != nil {
			t.Fatalf("decode part %d: %v", i, err)
		}
	}

	// 7. Decrypt (Bob's side — derive same session key)
	sharedB, _ := ECDH(bob.PrivateKey, alice.PublicKey)
	sessionKeyB, _ := DeriveSessionKey(sharedB, "alice", "bob", "conv-integration")
	if !bytes.Equal(sessionKey, sessionKeyB) {
		t.Fatal("session keys don't match between alice and bob")
	}

	decrypted := make([][]byte, len(received))
	for i, r := range received {
		decrypted[i], err = Decrypt(sessionKeyB, r)
		if err != nil {
			t.Fatalf("decrypt part %d: %v", i, err)
		}
	}

	// 8. Decompress
	decompressed := make([][]byte, len(decrypted))
	for i, d := range decrypted {
		decompressed[i], err = Decompress(d)
		if err != nil {
			t.Fatalf("decompress part %d: %v", i, err)
		}
	}

	// 9. Reassemble
	reassembled := ReassembleFile(decompressed)

	// 10. Verify byte-identical
	if !bytes.Equal(reassembled, original) {
		t.Fatalf("reassembled data does not match original (got %d bytes, want %d)", len(reassembled), len(original))
	}
	t.Logf("PASS: %d bytes → %d parts → compress → encrypt → wire → decrypt → decompress → reassemble → byte-identical", len(original), len(parts))
}

// Integration test: full encrypted file pipeline
// file → compress → encrypt → split → send → receive → reassemble → decrypt → decompress → verify byte-identical
func TestIntegrationFullEncryptedFilePipeline(t *testing.T) {
	// Simulate a 100KB file
	fileData := make([]byte, 100*1024)
	rand.Read(fileData)

	// 1. Compress the whole file
	compressed, err := Compress(fileData)
	if err != nil {
		t.Fatalf("compress: %v", err)
	}

	// 2. Encrypt the compressed file
	key, _ := GenerateAES256Key()
	encrypted, err := Encrypt(key, compressed)
	if err != nil {
		t.Fatalf("encrypt: %v", err)
	}

	// 3. Split into chunks for upload
	chunkSize := int64(30 * 1024) // 30KB chunks
	parts, err := SplitFile(bytes.NewReader(encrypted), chunkSize)
	if err != nil {
		t.Fatalf("split: %v", err)
	}
	t.Logf("file %d bytes → compressed %d bytes → encrypted %d bytes → %d parts", len(fileData), len(compressed), len(encrypted), len(parts))

	// 4. "Send" + "Receive" (identity — simulate network transfer)
	received := make([][]byte, len(parts))
	copy(received, parts)

	// 5. Reassemble
	reassembled := ReassembleFile(received)
	if !bytes.Equal(reassembled, encrypted) {
		t.Fatal("reassembled encrypted data doesn't match")
	}

	// 6. Decrypt
	decrypted, err := Decrypt(key, reassembled)
	if err != nil {
		t.Fatalf("decrypt: %v", err)
	}

	// 7. Decompress
	decompressed, err := Decompress(decrypted)
	if err != nil {
		t.Fatalf("decompress: %v", err)
	}

	// 8. Verify byte-identical
	if !bytes.Equal(decompressed, fileData) {
		t.Fatalf("file mismatch: got %d bytes, want %d", len(decompressed), len(fileData))
	}
	t.Logf("PASS: file pipeline byte-identical (%d bytes)", len(fileData))
}

// Integration test: vault lifecycle
// create → store → close → reopen → verify → export → delete → import → verify
func TestIntegrationVaultLifecycle(t *testing.T) {
	dir := t.TempDir()
	vaultPath := filepath.Join(dir, "test.vault")
	password := "integration-test-password-2026"

	// 1. Create
	v, err := CreateVault(vaultPath, password)
	if err != nil {
		t.Fatalf("create vault: %v", err)
	}

	// 2. Store various data types
	v.Put("accounts", "telegram:12345", map[string]string{"session": "abc123", "dc": "2"})
	v.Put("accounts", "matrix:@user:matrix.org", map[string]string{"token": "syt_xxx"})
	v.Put("keys", "dm:alice:bob", []byte{0xDE, 0xAD, 0xBE, 0xEF})
	v.Put("settings", "theme", "dark")
	v.Put("settings", "language", "en")

	// 3. Close (flushes to disk)
	if err := v.Close(); err != nil {
		t.Fatalf("close vault: %v", err)
	}

	// 4. Reopen
	v2, err := OpenVault(vaultPath, password)
	if err != nil {
		t.Fatalf("reopen vault: %v", err)
	}

	// 5. Verify all data survived
	var tgAcct map[string]string
	if err := v2.Get("accounts", "telegram:12345", &tgAcct); err != nil {
		t.Fatalf("get telegram account: %v", err)
	}
	if tgAcct["session"] != "abc123" || tgAcct["dc"] != "2" {
		t.Fatalf("telegram account data mismatch: %v", tgAcct)
	}

	var mxAcct map[string]string
	v2.Get("accounts", "matrix:@user:matrix.org", &mxAcct)
	if mxAcct["token"] != "syt_xxx" {
		t.Fatalf("matrix account data mismatch: %v", mxAcct)
	}

	var keyData []byte
	v2.Get("keys", "dm:alice:bob", &keyData)
	if !bytes.Equal(keyData, []byte{0xDE, 0xAD, 0xBE, 0xEF}) {
		t.Fatalf("key data mismatch: %x", keyData)
	}

	buckets := v2.ListBuckets()
	if len(buckets) != 3 {
		t.Fatalf("expected 3 buckets, got %d: %v", len(buckets), buckets)
	}

	// 6. Export
	exportPath := filepath.Join(dir, "export.vault")
	if err := v2.Export(exportPath); err != nil {
		t.Fatalf("export: %v", err)
	}
	v2.Close()

	// 7. Delete original (simulate loss)
	// (we just don't use vaultPath anymore)

	// 8. Import from export
	importPath := filepath.Join(dir, "imported.vault")
	v3, err := ImportVault(exportPath, importPath, password)
	if err != nil {
		t.Fatalf("import: %v", err)
	}
	defer v3.Close()

	// 9. Verify imported data
	var theme string
	v3.Get("settings", "theme", &theme)
	if theme != "dark" {
		t.Fatalf("imported theme mismatch: %s", theme)
	}

	var importedKey []byte
	v3.Get("keys", "dm:alice:bob", &importedKey)
	if !bytes.Equal(importedKey, []byte{0xDE, 0xAD, 0xBE, 0xEF}) {
		t.Fatalf("imported key mismatch: %x", importedKey)
	}

	// Verify wrong password still fails on import
	_, err = ImportVault(exportPath, filepath.Join(dir, "bad.vault"), "wrongpassword")
	if err == nil {
		t.Fatal("expected error importing with wrong password")
	}

	t.Log("PASS: vault lifecycle — create → store → close → reopen → verify → export → import → verify")
}

// Integration test: file split round-trip at exact Bale 19.5MB boundary
func TestIntegrationFileSplitBale195MB(t *testing.T) {
	const baleLimit = 19*1024*1024 + 512*1024 // 19.5 MB

	tests := []struct {
		name  string
		size  int
		parts int
	}{
		{"exact_boundary", baleLimit, 1},
		{"one_byte_over", baleLimit + 1, 2},
		{"double", baleLimit * 2, 2},
		{"double_plus_one", baleLimit*2 + 1, 3},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			data := make([]byte, tt.size)
			rand.Read(data)

			parts, err := SplitFile(bytes.NewReader(data), int64(baleLimit))
			if err != nil {
				t.Fatalf("split: %v", err)
			}
			if len(parts) != tt.parts {
				t.Fatalf("expected %d parts, got %d", tt.parts, len(parts))
			}

			reassembled := ReassembleFile(parts)
			if !bytes.Equal(reassembled, data) {
				t.Fatal("reassembled data doesn't match original")
			}

			// Verify part names round-trip
			for i := range parts {
				name := PartName("bigfile.zip", i+1, len(parts))
				base, num, ok := ParsePartName(name)
				if !ok || base != "bigfile.zip" || num != i+1 {
					t.Fatalf("part name round-trip failed: %s → %s, %d, %v", name, base, num, ok)
				}
			}
		})
	}
	t.Log("PASS: file split at Bale 19.5MB boundary — all cases byte-identical")
}
