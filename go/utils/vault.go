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

type Vault struct {
	mu        sync.RWMutex
	path      string
	masterKey []byte
	data      map[string]map[string]json.RawMessage
	dirty     bool
}

const (
	vaultSaltSize = 32
	vaultVersion  = 1
)

type vaultFile struct {
	Version    int    `json:"version"`
	Salt       []byte `json:"salt"`
	Ciphertext []byte `json:"ciphertext"`
}

var (
	ErrVaultLocked    = errors.New("vault is locked")
	ErrVaultWrongPass = errors.New("wrong vault password")
	ErrBucketNotFound = errors.New("bucket not found")
	ErrKeyNotFound    = errors.New("key not found in bucket")
)

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

	if err := v.flush(salt); err != nil {
		return nil, err
	}
	return v, nil
}

func OpenVault(path, password string) (*Vault, error) {
	raw, err := readVaultBytes(path)
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

func (v *Vault) ListBuckets() []string {
	v.mu.RLock()
	defer v.mu.RUnlock()

	buckets := make([]string, 0, len(v.data))
	for k := range v.data {
		buckets = append(buckets, k)
	}
	return buckets
}

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

func (v *Vault) Save() error {
	v.mu.Lock()
	defer v.mu.Unlock()

	if !v.dirty {
		return nil
	}

	return v.flushWithExistingKey()
}

func (v *Vault) flushWithExistingKey() error {
	raw, err := readVaultBytes(v.path)
	if err != nil {
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
	v.mergeForeignVaultData()
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
	if err := writeVaultBytes(v.path, raw); err != nil {
		return fmt.Errorf("write vault: %w", err)
	}
	v.dirty = false
	return nil
}

func (v *Vault) Close() error {
	return v.Save()
}

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

func ImportVault(srcPath, destPath, password string) (*Vault, error) {
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

func mergeVaultData(ours, foreign map[string]map[string]json.RawMessage) {
	for bucket, keys := range foreign {
		ob, ok := ours[bucket]
		if !ok {
			ob = make(map[string]json.RawMessage, len(keys))
			ours[bucket] = ob
		}
		for k, v := range keys {
			if _, exists := ob[k]; !exists {
				ob[k] = v
			}
		}
	}
}
