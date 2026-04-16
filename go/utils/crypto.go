package utils

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"errors"
	"fmt"
	"io"
)

const (
	NonceSize         = 12        // 96-bit nonce for AES-GCM
	KeySize           = 32        // 256-bit key
	Argon2Memory      = 64 * 1024 // 64 MB
	Argon2Iterations  = 3
	Argon2Parallelism = 4
)

var (
	ErrDecryptFailed  = errors.New("decryption failed")
	ErrInvalidPayload = errors.New("invalid encrypted payload")
)

// Encrypt encrypts plaintext with AES-256-GCM. Returns nonce + ciphertext + tag.
func Encrypt(key, plaintext []byte) ([]byte, error) {
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, fmt.Errorf("create cipher: %w", err)
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, fmt.Errorf("create gcm: %w", err)
	}
	nonce := make([]byte, NonceSize)
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return nil, fmt.Errorf("generate nonce: %w", err)
	}
	ciphertext := gcm.Seal(nonce, nonce, plaintext, nil)
	return ciphertext, nil
}

// Decrypt decrypts AES-256-GCM ciphertext (nonce prepended).
func Decrypt(key, ciphertext []byte) ([]byte, error) {
	if len(ciphertext) < NonceSize {
		return nil, ErrInvalidPayload
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, fmt.Errorf("create cipher: %w", err)
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, fmt.Errorf("create gcm: %w", err)
	}
	nonce := ciphertext[:NonceSize]
	plaintext, err := gcm.Open(nil, nonce, ciphertext[NonceSize:], nil)
	if err != nil {
		return nil, ErrDecryptFailed
	}
	return plaintext, nil
}
