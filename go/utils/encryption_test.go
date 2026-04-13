package utils

import (
	"bytes"
	"crypto/rand"
	"encoding/base64"
	"strings"
	"testing"
)

func TestGenerateX25519KeyPair(t *testing.T) {
	kp, err := GenerateX25519KeyPair()
	if err != nil {
		t.Fatal(err)
	}
	// Public key should not be all zeros
	var zero [32]byte
	if kp.PublicKey == zero {
		t.Fatal("public key is all zeros")
	}
	if kp.PrivateKey == zero {
		t.Fatal("private key is all zeros")
	}
	// Two keypairs should be different
	kp2, _ := GenerateX25519KeyPair()
	if kp.PublicKey == kp2.PublicKey {
		t.Fatal("two keypairs have the same public key")
	}
}

func TestECDH_SharedSecret(t *testing.T) {
	alice, _ := GenerateX25519KeyPair()
	bob, _ := GenerateX25519KeyPair()

	sharedA, err := ECDH(alice.PrivateKey, bob.PublicKey)
	if err != nil {
		t.Fatal(err)
	}
	sharedB, err := ECDH(bob.PrivateKey, alice.PublicKey)
	if err != nil {
		t.Fatal(err)
	}

	if !bytes.Equal(sharedA, sharedB) {
		t.Fatal("ECDH shared secrets don't match")
	}
}

func TestDeriveSessionKey(t *testing.T) {
	secret := make([]byte, 32)
	rand.Read(secret)

	key1, err := DeriveSessionKey(secret, "userA", "userB", "conv123")
	if err != nil {
		t.Fatal(err)
	}
	if len(key1) != KeySize {
		t.Fatalf("expected key size %d, got %d", KeySize, len(key1))
	}

	// Same inputs, reversed user order → same key (deterministic)
	key2, _ := DeriveSessionKey(secret, "userB", "userA", "conv123")
	if !bytes.Equal(key1, key2) {
		t.Fatal("reversed user IDs should produce the same key")
	}

	// Different conversation → different key
	key3, _ := DeriveSessionKey(secret, "userA", "userB", "conv456")
	if bytes.Equal(key1, key3) {
		t.Fatal("different conversations should produce different keys")
	}
}

func TestEncryptDecrypt_RoundTrip(t *testing.T) {
	key, _ := GenerateAES256Key()

	tests := []struct {
		name      string
		plaintext []byte
	}{
		{"empty", []byte{}},
		{"short", []byte("hello world")},
		{"medium", bytes.Repeat([]byte("a"), 10000)},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ciphertext, err := Encrypt(key, tt.plaintext)
			if err != nil {
				t.Fatal(err)
			}
			decrypted, err := Decrypt(key, ciphertext)
			if err != nil {
				t.Fatal(err)
			}
			if !bytes.Equal(decrypted, tt.plaintext) {
				t.Fatal("decrypted data doesn't match original")
			}
		})
	}
}

func TestEncrypt_UniqueNonce(t *testing.T) {
	key, _ := GenerateAES256Key()
	plaintext := []byte("same message")

	ct1, _ := Encrypt(key, plaintext)
	ct2, _ := Encrypt(key, plaintext)

	// Two encryptions of the same plaintext should produce different ciphertext (different nonce)
	if bytes.Equal(ct1, ct2) {
		t.Fatal("two encryptions produced identical ciphertext — nonce reuse!")
	}
}

func TestDecrypt_WrongKey(t *testing.T) {
	key1, _ := GenerateAES256Key()
	key2, _ := GenerateAES256Key()

	ciphertext, _ := Encrypt(key1, []byte("secret"))
	_, err := Decrypt(key2, ciphertext)
	if err == nil {
		t.Fatal("expected error decrypting with wrong key")
	}
	if err != ErrDecryptFailed {
		t.Fatalf("expected ErrDecryptFailed, got: %v", err)
	}
}

func TestDecrypt_CorruptCiphertext(t *testing.T) {
	key, _ := GenerateAES256Key()
	ciphertext, _ := Encrypt(key, []byte("hello"))

	// Corrupt a byte
	ciphertext[len(ciphertext)-1] ^= 0xFF
	_, err := Decrypt(key, ciphertext)
	if err == nil {
		t.Fatal("expected error on corrupt ciphertext")
	}
}

func TestDecrypt_TooShort(t *testing.T) {
	key, _ := GenerateAES256Key()
	_, err := Decrypt(key, []byte("short"))
	if err != ErrInvalidPayload {
		t.Fatalf("expected ErrInvalidPayload, got: %v", err)
	}
}

func TestDeriveKeyFromPassword(t *testing.T) {
	key1 := DeriveKeyFromPassword("mypassword", "alice", "bob", "conv1")
	if len(key1) != Argon2KeyLen {
		t.Fatalf("expected key len %d, got %d", Argon2KeyLen, len(key1))
	}

	// Same password, same params → same key
	key2 := DeriveKeyFromPassword("mypassword", "bob", "alice", "conv1")
	if !bytes.Equal(key1, key2) {
		t.Fatal("same password with reversed users should produce same key")
	}

	// Different password → different key
	key3 := DeriveKeyFromPassword("wrongpassword", "alice", "bob", "conv1")
	if bytes.Equal(key1, key3) {
		t.Fatal("different passwords should produce different keys")
	}
}

func TestArgon2id_ManualPassword_RoundTrip(t *testing.T) {
	password := "super-secret-passphrase"
	key := DeriveKeyFromPassword(password, "user1", "user2", "chat42")

	plaintext := "this is a secret message encrypted with manual password"
	ciphertext, err := Encrypt(key, []byte(plaintext))
	if err != nil {
		t.Fatal(err)
	}

	// Derive key again from same password
	key2 := DeriveKeyFromPassword(password, "user1", "user2", "chat42")
	decrypted, err := Decrypt(key2, ciphertext)
	if err != nil {
		t.Fatal(err)
	}
	if string(decrypted) != plaintext {
		t.Fatal("manual password round-trip failed")
	}
}

func TestEncryptMessage_DecryptMessage_RoundTrip(t *testing.T) {
	key, _ := GenerateAES256Key()
	original := "Hello, this is an encrypted message! 🔐"

	encrypted, err := EncryptMessage(key, original)
	if err != nil {
		t.Fatal(err)
	}

	if !strings.HasPrefix(encrypted, EncryptedPrefix) {
		t.Fatal("encrypted message should start with @@")
	}

	decrypted, isEncrypted, err := DecryptMessage(key, encrypted)
	if err != nil {
		t.Fatal(err)
	}
	if !isEncrypted {
		t.Fatal("should detect as encrypted")
	}
	if decrypted != original {
		t.Fatalf("expected %q, got %q", original, decrypted)
	}
}

func TestDecryptMessage_Plaintext(t *testing.T) {
	key, _ := GenerateAES256Key()
	plain := "just a normal message"

	result, isEncrypted, err := DecryptMessage(key, plain)
	if err != nil {
		t.Fatal(err)
	}
	if isEncrypted {
		t.Fatal("should not detect as encrypted")
	}
	if result != plain {
		t.Fatal("plaintext should pass through unchanged")
	}
}

func TestDecryptMessage_WrongKey(t *testing.T) {
	key1, _ := GenerateAES256Key()
	key2, _ := GenerateAES256Key()

	encrypted, _ := EncryptMessage(key1, "secret stuff")
	_, isEncrypted, err := DecryptMessage(key2, encrypted)
	if err == nil {
		t.Fatal("expected error with wrong key")
	}
	if !isEncrypted {
		t.Fatal("should still detect as encrypted even on failure")
	}
}

func TestIsEncryptedMessage(t *testing.T) {
	tests := []struct {
		msg      string
		expected bool
	}{
		{"@@" + base64.StdEncoding.EncodeToString([]byte("data")), true},
		{"@@abc", true},
		{"hello", false},
		{"@single", false},
		{"", false},
	}
	for _, tt := range tests {
		if got := IsEncryptedMessage(tt.msg); got != tt.expected {
			t.Errorf("IsEncryptedMessage(%q) = %v, want %v", tt.msg, got, tt.expected)
		}
	}
}

func TestHandshake_FormatParse(t *testing.T) {
	kp, _ := GenerateX25519KeyPair()
	msg := FormatHandshake("user123", kp.PublicKey)

	if !IsHandshakeMessage(msg) {
		t.Fatal("should be detected as handshake")
	}
	if IsEncryptedMessage(msg) {
		t.Fatal("handshake should not be detected as encrypted")
	}

	parsed, err := ParseHandshake(msg)
	if err != nil {
		t.Fatal(err)
	}
	if parsed.SenderID != "user123" {
		t.Fatalf("expected sender user123, got %s", parsed.SenderID)
	}

	pubBytes, _ := base64.StdEncoding.DecodeString(parsed.PublicKey)
	if !bytes.Equal(pubBytes, kp.PublicKey[:]) {
		t.Fatal("public key mismatch")
	}
}

func TestPublicKeyFingerprint(t *testing.T) {
	kp, _ := GenerateX25519KeyPair()
	fp := PublicKeyFingerprint(kp.PublicKey)

	// Should be groups of 4 hex chars separated by spaces
	parts := strings.Split(fp, " ")
	if len(parts) != 16 { // SHA-256 = 64 hex chars / 4 = 16 groups
		t.Fatalf("expected 16 fingerprint groups, got %d", len(parts))
	}
	for _, p := range parts {
		if len(p) != 4 {
			t.Fatalf("expected 4-char group, got %q", p)
		}
	}
}

func TestECIES_WrapUnwrap_RoundTrip(t *testing.T) {
	recipient, _ := GenerateX25519KeyPair()
	groupKey, _ := GenerateAES256Key()

	ephPub, wrapped, err := WrapKeyECIES(recipient.PublicKey, groupKey)
	if err != nil {
		t.Fatal(err)
	}

	unwrapped, err := UnwrapKeyECIES(recipient.PrivateKey, recipient.PublicKey, ephPub, wrapped)
	if err != nil {
		t.Fatal(err)
	}

	if !bytes.Equal(unwrapped, groupKey) {
		t.Fatal("ECIES unwrapped key doesn't match original")
	}
}

func TestECIES_WrongRecipient(t *testing.T) {
	recipient, _ := GenerateX25519KeyPair()
	wrongRecipient, _ := GenerateX25519KeyPair()
	groupKey, _ := GenerateAES256Key()

	ephPub, wrapped, _ := WrapKeyECIES(recipient.PublicKey, groupKey)

	_, err := UnwrapKeyECIES(wrongRecipient.PrivateKey, wrongRecipient.PublicKey, ephPub, wrapped)
	if err == nil {
		t.Fatal("expected error unwrapping with wrong recipient key")
	}
}

func TestECDH_FullKeyExchange(t *testing.T) {
	// Simulate full DM encryption setup
	alice, _ := GenerateX25519KeyPair()
	bob, _ := GenerateX25519KeyPair()

	// Both derive shared secret
	sharedA, _ := ECDH(alice.PrivateKey, bob.PublicKey)
	sharedB, _ := ECDH(bob.PrivateKey, alice.PublicKey)

	// Both derive session key
	keyA, _ := DeriveSessionKey(sharedA, "alice", "bob", "dm-123")
	keyB, _ := DeriveSessionKey(sharedB, "alice", "bob", "dm-123")

	if !bytes.Equal(keyA, keyB) {
		t.Fatal("session keys don't match")
	}

	// Alice encrypts, Bob decrypts
	msg, _ := EncryptMessage(keyA, "Hello Bob!")
	decrypted, isEnc, err := DecryptMessage(keyB, msg)
	if err != nil {
		t.Fatal(err)
	}
	if !isEnc {
		t.Fatal("should be encrypted")
	}
	if decrypted != "Hello Bob!" {
		t.Fatalf("got %q", decrypted)
	}
}

func TestGroupKey_RekeyOnMemberRemoval(t *testing.T) {
	// Create group with alice, bob, charlie
	alice, _ := GenerateX25519KeyPair()
	bob, _ := GenerateX25519KeyPair()
	charlie, _ := GenerateX25519KeyPair()

	// Generate group key
	groupKey, _ := GenerateAES256Key()

	// Wrap for all members
	_, wrappedA, _ := WrapKeyECIES(alice.PublicKey, groupKey)
	_, wrappedB, _ := WrapKeyECIES(bob.PublicKey, groupKey)
	_, wrappedC, _ := WrapKeyECIES(charlie.PublicKey, groupKey)
	_ = wrappedA
	_ = wrappedB
	_ = wrappedC

	// Encrypt a message with old key
	oldMsg, _ := EncryptMessage(groupKey, "old group message")

	// Charlie is removed — generate new key
	newGroupKey, _ := GenerateAES256Key()

	// Encrypt new message
	newMsg, _ := EncryptMessage(newGroupKey, "new group message after rekey")

	// Charlie can still decrypt old messages
	_, _, err := DecryptMessage(groupKey, oldMsg)
	if err != nil {
		t.Fatal("charlie should decrypt old messages")
	}

	// Charlie cannot decrypt new messages
	_, _, err = DecryptMessage(groupKey, newMsg)
	if err == nil {
		t.Fatal("old key should NOT decrypt messages encrypted with new key")
	}
}
