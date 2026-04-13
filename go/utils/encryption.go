// Package utils provides cross-cutting utilities for the uniclient messaging platform.
// encryption.go implements ECDH key exchange, AES-256-GCM encryption, Argon2id password
// derivation, and the @@ message prefix protocol.
package utils

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"strings"

	"golang.org/x/crypto/argon2"
	"golang.org/x/crypto/curve25519"
	"golang.org/x/crypto/hkdf"
)

const (
	EncryptedPrefix  = "@@"
	HandshakePrefix  = "##HANDSHAKE##"
	NonceSize        = 12 // 96-bit nonce for AES-GCM
	KeySize          = 32 // 256-bit key
	Argon2Memory     = 64 * 1024 // 64 MB
	Argon2Iterations = 3
	Argon2Parallelism = 4
	Argon2KeyLen     = 32
)

var (
	ErrDecryptFailed   = errors.New("decryption failed")
	ErrInvalidPayload  = errors.New("invalid encrypted payload")
	ErrHandshakePending = errors.New("key exchange handshake not complete")
)

// X25519KeyPair holds a Curve25519 keypair for ECDH.
type X25519KeyPair struct {
	PrivateKey [32]byte `json:"private_key"`
	PublicKey  [32]byte `json:"public_key"`
}

// HandshakeMessage is sent to exchange ephemeral public keys.
type HandshakeMessage struct {
	SenderID  string `json:"sender_id"`
	PublicKey string `json:"public_key"` // base64-encoded
}

// GenerateX25519KeyPair generates a new X25519 keypair.
func GenerateX25519KeyPair() (*X25519KeyPair, error) {
	var priv [32]byte
	if _, err := io.ReadFull(rand.Reader, priv[:]); err != nil {
		return nil, fmt.Errorf("generate keypair: %w", err)
	}
	pub, err := curve25519.X25519(priv[:], curve25519.Basepoint)
	if err != nil {
		return nil, fmt.Errorf("derive public key: %w", err)
	}
	var kp X25519KeyPair
	copy(kp.PrivateKey[:], priv[:])
	copy(kp.PublicKey[:], pub)
	return &kp, nil
}

// ECDH performs X25519 Diffie-Hellman key agreement.
func ECDH(privateKey [32]byte, peerPublicKey [32]byte) ([]byte, error) {
	shared, err := curve25519.X25519(privateKey[:], peerPublicKey[:])
	if err != nil {
		return nil, fmt.Errorf("ecdh: %w", err)
	}
	return shared, nil
}

// DeriveSessionKey derives a 256-bit AES-GCM key from a shared secret using HKDF-SHA256.
func DeriveSessionKey(sharedSecret []byte, userA, userB, conversationID string) ([]byte, error) {
	// Sort user IDs for deterministic salt regardless of who initiates
	if userA > userB {
		userA, userB = userB, userA
	}
	salt := sha256Sum([]byte(userA + ":" + userB + ":" + conversationID))
	info := []byte("uniclient-session-key-v1")

	hkdfReader := hkdf.New(sha256.New, sharedSecret, salt, info)
	key := make([]byte, KeySize)
	if _, err := io.ReadFull(hkdfReader, key); err != nil {
		return nil, fmt.Errorf("derive session key: %w", err)
	}
	return key, nil
}

// DeriveKeyFromPassword derives a 256-bit AES-GCM key from a password using Argon2id.
func DeriveKeyFromPassword(password string, userA, userB, conversationID string) []byte {
	if userA > userB {
		userA, userB = userB, userA
	}
	salt := sha256Sum([]byte(userA + ":" + userB + ":" + conversationID))
	return argon2.IDKey([]byte(password), salt, Argon2Iterations, Argon2Memory, Argon2Parallelism, Argon2KeyLen)
}

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

// EncryptMessage compresses, encrypts, and formats a message with the @@ prefix.
func EncryptMessage(key []byte, plaintext string) (string, error) {
	compressed, err := Compress([]byte(plaintext))
	if err != nil {
		return "", fmt.Errorf("compress: %w", err)
	}
	encrypted, err := Encrypt(key, compressed)
	if err != nil {
		return "", fmt.Errorf("encrypt: %w", err)
	}
	encoded := base64.StdEncoding.EncodeToString(encrypted)
	return EncryptedPrefix + encoded, nil
}

// DecryptMessage detects @@, decodes, decrypts, and decompresses a message.
// If the message doesn't start with @@, returns it as plaintext with isEncrypted=false.
func DecryptMessage(key []byte, message string) (plaintext string, isEncrypted bool, err error) {
	if !IsEncryptedMessage(message) {
		return message, false, nil
	}
	encoded := message[len(EncryptedPrefix):]
	ciphertext, err := base64.StdEncoding.DecodeString(encoded)
	if err != nil {
		return message, true, ErrDecryptFailed
	}
	compressed, err := Decrypt(key, ciphertext)
	if err != nil {
		return message, true, err
	}
	decompressed, err := Decompress(compressed)
	if err != nil {
		return string(compressed), true, fmt.Errorf("decompress: %w", err)
	}
	return string(decompressed), true, nil
}

// IsEncryptedMessage checks if a message has the @@ prefix.
func IsEncryptedMessage(message string) bool {
	return strings.HasPrefix(message, EncryptedPrefix)
}

// IsHandshakeMessage checks if a message is a key exchange handshake.
func IsHandshakeMessage(message string) bool {
	return strings.HasPrefix(message, HandshakePrefix)
}

// FormatHandshake creates a handshake message containing the sender's public key.
func FormatHandshake(senderID string, publicKey [32]byte) string {
	msg := HandshakeMessage{
		SenderID:  senderID,
		PublicKey: base64.StdEncoding.EncodeToString(publicKey[:]),
	}
	data, _ := json.Marshal(msg)
	return HandshakePrefix + string(data)
}

// ParseHandshake extracts the sender ID and public key from a handshake message.
func ParseHandshake(message string) (*HandshakeMessage, error) {
	if !IsHandshakeMessage(message) {
		return nil, errors.New("not a handshake message")
	}
	payload := message[len(HandshakePrefix):]
	var msg HandshakeMessage
	if err := json.Unmarshal([]byte(payload), &msg); err != nil {
		return nil, fmt.Errorf("parse handshake: %w", err)
	}
	return &msg, nil
}

// PublicKeyFingerprint returns the SHA-256 fingerprint of a public key,
// formatted as groups of 4 hex characters for readability.
func PublicKeyFingerprint(publicKey [32]byte) string {
	hash := sha256.Sum256(publicKey[:])
	hex := fmt.Sprintf("%x", hash)
	var parts []string
	for i := 0; i < len(hex); i += 4 {
		end := i + 4
		if end > len(hex) {
			end = len(hex)
		}
		parts = append(parts, hex[i:end])
	}
	return strings.Join(parts, " ")
}

// GenerateAES256Key generates a random 256-bit key.
func GenerateAES256Key() ([]byte, error) {
	key := make([]byte, KeySize)
	if _, err := io.ReadFull(rand.Reader, key); err != nil {
		return nil, err
	}
	return key, nil
}

// WrapKeyECIES wraps a key for a recipient using ECIES (ephemeral ECDH + AES-GCM).
// Returns the ephemeral public key + encrypted wrapped key.
func WrapKeyECIES(recipientPublicKey [32]byte, keyToWrap []byte) (ephemeralPub [32]byte, wrapped []byte, err error) {
	ephemeral, err := GenerateX25519KeyPair()
	if err != nil {
		return [32]byte{}, nil, err
	}
	shared, err := ECDH(ephemeral.PrivateKey, recipientPublicKey)
	if err != nil {
		return [32]byte{}, nil, err
	}
	// Derive wrapping key from shared secret
	salt := sha256Sum(append(ephemeral.PublicKey[:], recipientPublicKey[:]...))
	info := []byte("uniclient-ecies-wrap-v1")
	hkdfReader := hkdf.New(sha256.New, shared, salt, info)
	wrappingKey := make([]byte, KeySize)
	if _, err := io.ReadFull(hkdfReader, wrappingKey); err != nil {
		return [32]byte{}, nil, err
	}
	wrapped, err = Encrypt(wrappingKey, keyToWrap)
	if err != nil {
		return [32]byte{}, nil, err
	}
	return ephemeral.PublicKey, wrapped, nil
}

// UnwrapKeyECIES unwraps a key using the recipient's private key + sender's ephemeral public key.
func UnwrapKeyECIES(recipientPrivateKey [32]byte, recipientPublicKey [32]byte, ephemeralPub [32]byte, wrapped []byte) ([]byte, error) {
	shared, err := ECDH(recipientPrivateKey, ephemeralPub)
	if err != nil {
		return nil, err
	}
	salt := sha256Sum(append(ephemeralPub[:], recipientPublicKey[:]...))
	info := []byte("uniclient-ecies-wrap-v1")
	hkdfReader := hkdf.New(sha256.New, shared, salt, info)
	wrappingKey := make([]byte, KeySize)
	if _, err := io.ReadFull(hkdfReader, wrappingKey); err != nil {
		return nil, err
	}
	return Decrypt(wrappingKey, wrapped)
}

func sha256Sum(data []byte) []byte {
	h := sha256.Sum256(data)
	return h[:]
}
