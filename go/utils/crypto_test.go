package utils

import (
	"bytes"
	"crypto/rand"
	"testing"
)

func TestEncryptDecryptRoundTrip(t *testing.T) {
	key := make([]byte, KeySize)
	if _, err := rand.Read(key); err != nil {
		t.Fatal(err)
	}
	plaintexts := [][]byte{
		{},
		[]byte("a"),
		[]byte("hello, uniclient"),
		bytes.Repeat([]byte("x"), 64*1024), // 64 KiB
	}
	for _, pt := range plaintexts {
		ct, err := Encrypt(key, pt)
		if err != nil {
			t.Fatalf("Encrypt(len=%d): %v", len(pt), err)
		}
		got, err := Decrypt(key, ct)
		if err != nil {
			t.Fatalf("Decrypt(len=%d): %v", len(pt), err)
		}
		if !bytes.Equal(got, pt) {
			t.Fatalf("round-trip mismatch: got %d bytes, want %d", len(got), len(pt))
		}
	}
}

func TestEncryptNonDeterministic(t *testing.T) {
	key := make([]byte, KeySize)
	if _, err := rand.Read(key); err != nil {
		t.Fatal(err)
	}
	a, err := Encrypt(key, []byte("same plaintext"))
	if err != nil {
		t.Fatal(err)
	}
	b, err := Encrypt(key, []byte("same plaintext"))
	if err != nil {
		t.Fatal(err)
	}
	if bytes.Equal(a, b) {
		t.Fatal("nonce reuse detected: two encryptions of the same plaintext are identical")
	}
}

func TestDecryptWrongKey(t *testing.T) {
	key1 := make([]byte, KeySize)
	key2 := make([]byte, KeySize)
	if _, err := rand.Read(key1); err != nil {
		t.Fatal(err)
	}
	if _, err := rand.Read(key2); err != nil {
		t.Fatal(err)
	}
	ct, err := Encrypt(key1, []byte("secret"))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := Decrypt(key2, ct); err != ErrDecryptFailed {
		t.Fatalf("wrong key: got %v, want ErrDecryptFailed", err)
	}
}

func TestDecryptTampered(t *testing.T) {
	key := make([]byte, KeySize)
	if _, err := rand.Read(key); err != nil {
		t.Fatal(err)
	}
	ct, err := Encrypt(key, []byte("secret"))
	if err != nil {
		t.Fatal(err)
	}
	ct[len(ct)-1] ^= 0xFF // flip last tag byte
	if _, err := Decrypt(key, ct); err != ErrDecryptFailed {
		t.Fatalf("tampered tag: got %v, want ErrDecryptFailed", err)
	}
}

func TestDecryptShortPayload(t *testing.T) {
	key := make([]byte, KeySize)
	if _, err := rand.Read(key); err != nil {
		t.Fatal(err)
	}
	if _, err := Decrypt(key, []byte("short")); err != ErrInvalidPayload {
		t.Fatalf("short payload: got %v, want ErrInvalidPayload", err)
	}
}

func TestDeriveVaultKeyDeterministic(t *testing.T) {
	salt := make([]byte, 16)
	if _, err := rand.Read(salt); err != nil {
		t.Fatal(err)
	}
	a := deriveVaultKey("correct horse battery staple", salt)
	b := deriveVaultKey("correct horse battery staple", salt)
	if !bytes.Equal(a, b) {
		t.Fatal("key derivation is not deterministic for same password+salt")
	}
	c := deriveVaultKey("different password", salt)
	if bytes.Equal(a, c) {
		t.Fatal("different passwords derived the same key")
	}
	d := deriveVaultKey("correct horse battery staple", salt)
	salt[0] ^= 0xFF
	if bytes.Equal(d, deriveVaultKey("correct horse battery staple", salt)) {
		t.Fatal("mutated salt derived the same key as the original salt")
	}
}
