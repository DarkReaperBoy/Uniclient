package utils

import (
	"crypto/rand"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"sync"

	"golang.org/x/crypto/argon2"
)

// Vault is an encrypted key-value store backed by a single file.
// All data is held in memory while open, encrypted at rest using AES-256-GCM
// with a master key derived from the user's password via Argon2id.
type Vault struct {
	mu       sync.RWMutex
	path     string
	masterKey []byte
	data     map[string]map[string]json.RawMessage // bucket → key → value
	dirty    bool
}

const (
	vaultSaltSize = 32
	vaultVersion  = 1
)

// vaultFile is the on-disk format.
type vaultFile struct {
	Version    int    `json:"version"`
	Salt       []byte `json:"salt"`
	Ciphertext []byte `json:"ciphertext"` // AES-256-GCM encrypted JSON of data
}

var (
	ErrVaultLocked    = errors.New("vault is locked")
	ErrVaultWrongPass = errors.New("wrong vault password")
	ErrBucketNotFound = errors.New("bucket not found")
	ErrKeyNotFound    = errors.New("key not found in bucket")
)

// CreateVault creates a new vault file at path, encrypted with password.
func CreateVault(path, password string) (*Vault, error) {
	v := &Vault{
		path: path,
		data: make(map[string]map[string]json.RawMessage),
	}
	salt := make([]byte, vaultSaltSize)
	if _, err := io.ReadFull(rand.Reader, salt); err != nil {
		return nil, err
	}
	v.masterKey = deriveVaultKey(password, salt)

	// Write initial empty vault
	if err := v.flush(salt); err != nil {
		return nil, err
	}
	return v, nil
}

// OpenVault opens an existing vault file with the given password.
func OpenVault(path, password string) (*Vault, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read vault: %w", err)
	}
	var vf vaultFile
	if err := json.Unmarshal(raw, &vf); err != nil {
		return nil, fmt.Errorf("parse vault: %w", err)
	}
	if vf.Version != vaultVersion {
		return nil, fmt.Errorf("unsupported vault version: %d", vf.Version)
	}

	masterKey := deriveVaultKey(password, vf.Salt)
	plaintext, err := Decrypt(masterKey, vf.Ciphertext)
	if err != nil {
		return nil, ErrVaultWrongPass
	}

	data := make(map[string]map[string]json.RawMessage)
	if err := json.Unmarshal(plaintext, &data); err != nil {
		return nil, fmt.Errorf("decode vault data: %w", err)
	}

	return &Vault{
		path:      path,
		masterKey: masterKey,
		data:      data,
	}, nil
}

// Put stores a value in the vault under bucket/key.
func (v *Vault) Put(bucket, key string, value any) error {
	v.mu.Lock()
	defer v.mu.Unlock()

	raw, err := json.Marshal(value)
	if err != nil {
		return fmt.Errorf("marshal value: %w", err)
	}
	if v.data[bucket] == nil {
		v.data[bucket] = make(map[string]json.RawMessage)
	}
	v.data[bucket][key] = raw
	v.dirty = true
	return nil
}

// Get retrieves a value from the vault. dest must be a pointer.
func (v *Vault) Get(bucket, key string, dest any) error {
	v.mu.RLock()
	defer v.mu.RUnlock()

	b, ok := v.data[bucket]
	if !ok {
		return ErrBucketNotFound
	}
	raw, ok := b[key]
	if !ok {
		return ErrKeyNotFound
	}
	return json.Unmarshal(raw, dest)
}

// Delete removes a key from a bucket.
func (v *Vault) Delete(bucket, key string) error {
	v.mu.Lock()
	defer v.mu.Unlock()

	b, ok := v.data[bucket]
	if !ok {
		return ErrBucketNotFound
	}
	delete(b, key)
	if len(b) == 0 {
		delete(v.data, bucket)
	}
	v.dirty = true
	return nil
}

// ListBuckets returns all bucket names.
func (v *Vault) ListBuckets() []string {
	v.mu.RLock()
	defer v.mu.RUnlock()

	buckets := make([]string, 0, len(v.data))
	for k := range v.data {
		buckets = append(buckets, k)
	}
	return buckets
}

// ListKeys returns all keys in a bucket.
func (v *Vault) ListKeys(bucket string) ([]string, error) {
	v.mu.RLock()
	defer v.mu.RUnlock()

	b, ok := v.data[bucket]
	if !ok {
		return nil, ErrBucketNotFound
	}
	keys := make([]string, 0, len(b))
	for k := range b {
		keys = append(keys, k)
	}
	return keys, nil
}

// Save encrypts and writes the vault to disk.
func (v *Vault) Save() error {
	v.mu.Lock()
	defer v.mu.Unlock()

	if !v.dirty {
		return nil
	}

	return v.flushWithExistingKey()
}

func (v *Vault) flushWithExistingKey() error {
	// Read existing salt from file
	raw, err := os.ReadFile(v.path)
	if err != nil {
		// New file — generate salt
		salt := make([]byte, vaultSaltSize)
		if _, err := io.ReadFull(rand.Reader, salt); err != nil {
			return fmt.Errorf("generate salt: %w", err)
		}
		return v.flush(salt)
	}
	var vf vaultFile
	if err := json.Unmarshal(raw, &vf); err != nil {
		salt := make([]byte, vaultSaltSize)
		if _, err := io.ReadFull(rand.Reader, salt); err != nil {
			return fmt.Errorf("generate salt: %w", err)
		}
		return v.flush(salt)
	}
	return v.flush(vf.Salt)
}

func (v *Vault) flush(salt []byte) error {
	plaintext, err := json.Marshal(v.data)
	if err != nil {
		return fmt.Errorf("marshal data: %w", err)
	}
	ciphertext, err := Encrypt(v.masterKey, plaintext)
	if err != nil {
		return fmt.Errorf("encrypt vault: %w", err)
	}
	vf := vaultFile{
		Version:    vaultVersion,
		Salt:       salt,
		Ciphertext: ciphertext,
	}
	raw, err := json.Marshal(vf)
	if err != nil {
		return fmt.Errorf("marshal vault file: %w", err)
	}
	if err := os.WriteFile(v.path, raw, 0600); err != nil {
		return fmt.Errorf("write vault: %w", err)
	}
	v.dirty = false
	return nil
}

// Close saves and closes the vault.
func (v *Vault) Close() error {
	return v.Save()
}

// Export copies the vault file to a destination path (still encrypted).
func (v *Vault) Export(destPath string) error {
	if err := v.Save(); err != nil {
		return err
	}
	src, err := os.ReadFile(v.path)
	if err != nil {
		return err
	}
	return os.WriteFile(destPath, src, 0600)
}

// ImportVault imports a vault file, decrypting with the given password.
func ImportVault(srcPath, destPath, password string) (*Vault, error) {
	// First, verify we can open the source with the given password
	v, err := OpenVault(srcPath, password)
	if err != nil {
		return nil, fmt.Errorf("import: %w", err)
	}
	v.path = destPath
	v.dirty = true
	if err := v.Save(); err != nil {
		return nil, err
	}
	return v, nil
}

func deriveVaultKey(password string, salt []byte) []byte {
	return argon2.IDKey([]byte(password), salt, Argon2Iterations, Argon2Memory, Argon2Parallelism, KeySize)
}
