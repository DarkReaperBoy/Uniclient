package cores

import (
	"bytes"
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha1"
	"crypto/sha256"
	"crypto/sha512"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"math"
	"math/big"
	"net"
	"os"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"filippo.io/edwards25519"
)

// ──────────────────────────── constants ────────────────────────────

const (
	tsVoicePort      = "9987"
	tsMaxMsgBuffer   = 500
	tsPingInterval   = 30 * time.Second
	tsReadTimeout    = 5 * time.Second
	tsDialTimeout    = 10 * time.Second
	tsRetransmitBase = 500 * time.Millisecond
	tsMaxRetransmit  = 30 * time.Second
	tsMaxPayloadC2S  = 487 // 500 - 13 byte header
	tsMaxPayloadS2C  = 489 // 500 - 11 byte header
	tsHeaderC2S      = 13
	tsHeaderS2C      = 11
	tsVersionTS      = 1466672534 // 3.0.19.3 build timestamp
	tsEpochOffset    = 1356998400
)

// Packet types
const (
	tsPktVoice        = 0x00
	tsPktVoiceWhisper = 0x01
	tsPktCommand      = 0x02
	tsPktCommandLow   = 0x03
	tsPktPing         = 0x04
	tsPktPong         = 0x05
	tsPktAck          = 0x06
	tsPktAckLow       = 0x07
	tsPktInit         = 0x08
)

// Flags
const (
	tsFlagUnencrypted = 0x80
	tsFlagCompressed  = 0x40
	tsFlagNewprotocol = 0x20
	tsFlagFragmented  = 0x10
)

// Init MAC ("TS3INIT1")
var tsInitMAC = [8]byte{0x54, 0x53, 0x33, 0x49, 0x4E, 0x49, 0x54, 0x31}

// FAKE_KEY and FAKE_NONCE for the first encrypted command exchange
var tsFakeKey = [16]byte{0x63, 0x3A, 0x5C, 0x77, 0x69, 0x6E, 0x64, 0x6F, 0x77, 0x73, 0x5C, 0x73, 0x79, 0x73, 0x74, 0x65}
var tsFakeNonce = [16]byte{0x6D, 0x5C, 0x66, 0x69, 0x72, 0x65, 0x77, 0x61, 0x6C, 0x6C, 0x33, 0x32, 0x2E, 0x63, 0x70, 0x6C}

// ROOT_KEY for Ed25519 license chain
var tsRootKey = [32]byte{
	0xcd, 0x0d, 0xe2, 0xae, 0xd4, 0x63, 0x45, 0x50,
	0x9a, 0x7e, 0x3c, 0xfd, 0x8f, 0x68, 0xb3, 0xdc,
	0x75, 0x55, 0xb2, 0x9d, 0xcc, 0xec, 0x73, 0xcd,
	0x18, 0x75, 0x0f, 0x99, 0x38, 0x12, 0x40, 0x8a,
}

// Version string and platform for clientinit
const tsVersionStr = "3.?.? [Build: 5680278000]"
const tsPlatform = "Linux"
const tsVersionSign = "Hjd+N58Gv3ENhoKmGYy2bNRBsNNgm5kpiaQWxOj5HN2DXttG6REjymSwJtpJ8muC2gSwRuZi0R+8Laan5ts5CQ=="

// ──────────────────────────── QuickLZ Level 1 ────────────────────────────
// Pure Go decompressor for QuickLZ Level 1 as used by TS3.

func tsQuickLZDecompress(src []byte) ([]byte, error) {
	if len(src) < 3 {
		return nil, fmt.Errorf("quicklz: input too short (%d bytes)", len(src))
	}

	flags := src[0]
	var compressedSize, decompressedSize uint32
	var headerLen int

	if flags&0x02 != 0 {
		// Long header (9 bytes)
		if len(src) < 9 {
			return nil, fmt.Errorf("quicklz: long header but only %d bytes", len(src))
		}
		headerLen = 9
		compressedSize = binary.LittleEndian.Uint32(src[1:5])
		decompressedSize = binary.LittleEndian.Uint32(src[5:9])
	} else {
		// Short header (3 bytes)
		headerLen = 3
		compressedSize = uint32(src[1])
		decompressedSize = uint32(src[2])
	}

	if compressedSize > uint32(len(src)) {
		return nil, fmt.Errorf("quicklz: compressed size %d > input %d", compressedSize, len(src))
	}
	if decompressedSize > 1024*1024*10 {
		return nil, fmt.Errorf("quicklz: decompressed size too large: %d", decompressedSize)
	}

	// Not compressed — stored raw
	if flags&0x01 == 0 {
		out := make([]byte, decompressedSize)
		copy(out, src[headerLen:])
		return out, nil
	}

	// Decompress
	in := src[headerLen:compressedSize]
	out := make([]byte, 0, decompressedSize)
	var hashtable [4096]uint32
	inPos := 0

	control := uint32(1) // forces immediate read

	nextHashed := 0

	for uint32(len(out)) < decompressedSize {
		if control == 1 {
			if inPos+4 > len(in) {
				break
			}
			control = binary.LittleEndian.Uint32(in[inPos:])
			inPos += 4
		}

		if control&1 != 0 {
			// Back-reference
			control >>= 1
			if inPos+2 > len(in) {
				break
			}
			b0 := in[inPos]
			b1 := in[inPos+1]
			inPos += 2

			matchlen := uint32(b0 & 0x0F)
			hash := uint32(b0>>4) | uint32(b1)<<4

			if matchlen == 0 {
				if inPos >= len(in) {
					break
				}
				matchlen = uint32(in[inPos])
				inPos++
			} else {
				matchlen += 2
			}

			offset := hashtable[hash]

			// Copy matchlen bytes (byte-by-byte for overlapping)
			for i := uint32(0); i < matchlen; i++ {
				if int(offset+i) < len(out) {
					out = append(out, out[offset+i])
				}
			}

			// Update hashtable
			end := len(out) + 1 - int(matchlen)
			if end < 0 {
				end = 0
			}
			for i := nextHashed; i < end && i+2 < len(out); i++ {
				v := uint32(out[i]) | uint32(out[i+1])<<8 | uint32(out[i+2])<<16
				h := ((v >> 12) ^ v) & 0xFFF
				hashtable[h] = uint32(i)
			}
			nextHashed = len(out)

		} else if uint32(len(out)) >= decompressedSize-10 || (decompressedSize < 10 && uint32(len(out)) >= 0) {
			// Near end — emit remaining literals
			for uint32(len(out)) < decompressedSize {
				if control == 1 {
					if inPos+4 > len(in) {
						break
					}
					control = binary.LittleEndian.Uint32(in[inPos:])
					inPos += 4
				}
				control >>= 1
				if inPos >= len(in) {
					break
				}
				out = append(out, in[inPos])
				inPos++
			}
			break
		} else {
			// Literal byte
			control >>= 1
			if inPos >= len(in) {
				break
			}
			out = append(out, in[inPos])
			inPos++

			// Update hashtable
			end := len(out) - 2
			if end < 0 {
				end = 0
			}
			for i := nextHashed; i < end && i+2 < len(out); i++ {
				v := uint32(out[i]) | uint32(out[i+1])<<8 | uint32(out[i+2])<<16
				h := ((v >> 12) ^ v) & 0xFFF
				hashtable[h] = uint32(i)
			}
			if end > nextHashed {
				nextHashed = end
			}
		}
	}

	return out, nil
}

// ──────────────────────────── AES-128-EAX ────────────────────────────
// EAX mode with 8-byte (truncated) tag as used by TS3.

// tsOMAC1 computes OMAC1 (CMAC) using AES-128. Returns full 16-byte tag.
func tsOMAC1(key, data []byte) []byte {
	block, _ := aes.NewCipher(key)
	bs := block.BlockSize()

	// Generate subkeys
	var zero [16]byte
	l := make([]byte, bs)
	block.Encrypt(l, zero[:])

	k1 := tsDbl(l)
	k2 := tsDbl(k1)

	// Process data
	n := len(data)
	var flag bool
	if n == 0 {
		flag = false
		n = bs
	} else {
		flag = (n % bs) == 0
	}

	if flag {
		// Complete last block
		tmp := make([]byte, n)
		copy(tmp, data)
		for i := 0; i < bs; i++ {
			tmp[n-bs+i] ^= k1[i]
		}
		data = tmp
	} else {
		// Pad last block
		padded := make([]byte, ((n/bs)+1)*bs)
		copy(padded, data)
		padded[n] = 0x80
		for i := 0; i < bs; i++ {
			padded[len(padded)-bs+i] ^= k2[i]
		}
		data = padded
		n = len(padded)
	}

	// CBC-MAC
	mac := make([]byte, bs)
	for i := 0; i < n; i += bs {
		for j := 0; j < bs; j++ {
			mac[j] ^= data[i+j]
		}
		block.Encrypt(mac, mac)
	}
	return mac
}

// tsDbl doubles a value in GF(2^128) with the AES polynomial.
func tsDbl(b []byte) []byte {
	r := make([]byte, len(b))
	carry := b[0] >> 7
	for i := 0; i < len(b)-1; i++ {
		r[i] = (b[i] << 1) | (b[i+1] >> 7)
	}
	r[len(b)-1] = b[len(b)-1] << 1
	if carry == 1 {
		r[len(b)-1] ^= 0x87
	}
	return r
}

// tsEAXEncrypt encrypts with EAX mode (AES-128) and returns 8-byte truncated tag + ciphertext.
func tsEAXEncrypt(key, nonce, header, plaintext []byte) (mac [8]byte, ciphertext []byte) {
	block, _ := aes.NewCipher(key)

	// N = OMAC(0 || nonce)
	nonceInput := make([]byte, 16+len(nonce))
	// first 16 bytes are tag 0x00...00 (already zero)
	copy(nonceInput[16:], nonce)
	n := tsOMAC1(key, nonceInput)

	// H = OMAC(1 || header)
	headerInput := make([]byte, 16+len(header))
	headerInput[15] = 0x01
	copy(headerInput[16:], header)
	h := tsOMAC1(key, headerInput)

	// CTR encrypt using N as IV
	ciphertext = make([]byte, len(plaintext))
	stream := cipher.NewCTR(block, n)
	stream.XORKeyStream(ciphertext, plaintext)

	// C = OMAC(2 || ciphertext)
	cInput := make([]byte, 16+len(ciphertext))
	cInput[15] = 0x02
	copy(cInput[16:], ciphertext)
	c := tsOMAC1(key, cInput)

	// Tag = N ^ H ^ C (truncated to 8 bytes)
	for i := 0; i < 8; i++ {
		mac[i] = n[i] ^ h[i] ^ c[i]
	}
	return
}

// tsEAXDecrypt decrypts with EAX mode (AES-128), verifying the 8-byte truncated tag.
func tsEAXDecrypt(key, nonce, header, ciphertext []byte, macIn [8]byte) ([]byte, error) {
	block, _ := aes.NewCipher(key)

	// N = OMAC(0 || nonce)
	nonceInput := make([]byte, 16+len(nonce))
	copy(nonceInput[16:], nonce)
	n := tsOMAC1(key, nonceInput)

	// H = OMAC(1 || header)
	headerInput := make([]byte, 16+len(header))
	headerInput[15] = 0x01
	copy(headerInput[16:], header)
	h := tsOMAC1(key, headerInput)

	// C = OMAC(2 || ciphertext)
	cInput := make([]byte, 16+len(ciphertext))
	cInput[15] = 0x02
	copy(cInput[16:], ciphertext)
	c := tsOMAC1(key, cInput)

	// Verify tag
	for i := 0; i < 8; i++ {
		if macIn[i] != n[i]^h[i]^c[i] {
			return nil, fmt.Errorf("EAX: MAC mismatch")
		}
	}

	// CTR decrypt
	plaintext := make([]byte, len(ciphertext))
	stream := cipher.NewCTR(block, n)
	stream.XORKeyStream(plaintext, ciphertext)
	return plaintext, nil
}

// ──────────────────────────── Per-packet key derivation ────────────────────────────

// tsCreateKeyNonce derives the per-packet AES key and nonce from SharedIV.
// direction: 0x30 = S2C, 0x31 = C2S
func tsCreateKeyNonce(pType byte, pID uint16, genID uint32, direction byte, sharedIV []byte) (key [16]byte, nonce [16]byte) {
	var temp []byte
	if len(sharedIV) == 20 {
		temp = make([]byte, 26)
	} else {
		temp = make([]byte, 70)
	}
	temp[0] = direction
	temp[1] = pType & 0x0f
	binary.BigEndian.PutUint32(temp[2:6], genID)
	copy(temp[6:], sharedIV)

	h := sha256.Sum256(temp)
	copy(key[:], h[:16])
	copy(nonce[:], h[16:])

	key[0] ^= byte(pID >> 8)
	key[1] ^= byte(pID & 0xff)
	return
}

// ──────────────────────────── P-256 Identity (LibTomCrypt ASN.1) ────────────────────────────

// tsP256Identity holds the client's ECDSA P-256 identity keypair.
type tsP256Identity struct {
	key       *ecdsa.PrivateKey
	keyOffset uint64 // hashcash offset
}

func tsNewIdentity() (*tsP256Identity, error) {
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return nil, err
	}
	id := &tsP256Identity{key: key}
	// Compute hashcash offset for level 8 (server minimum)
	omega := id.tsOmega()
	id.keyOffset = tsHashCash(omega, 8)
	return id, nil
}

// tsOmega encodes the public key in LibTomCrypt ASN.1-DER format (for omega parameter).
// Format: SEQUENCE { BIT STRING (1 bit, value 0), INTEGER 32, INTEGER X, INTEGER Y }
func (id *tsP256Identity) tsOmega() string {
	pub := id.key.PublicKey
	xBytes := pub.X.Bytes()
	yBytes := pub.Y.Bytes()

	// Pad to 32 bytes
	for len(xBytes) < 32 {
		xBytes = append([]byte{0}, xBytes...)
	}
	for len(yBytes) < 32 {
		yBytes = append([]byte{0}, yBytes...)
	}

	// Build ASN.1 DER manually
	// BIT STRING: tag 0x03, length 2, unused_bits=7, data=0x00 (1 bit value 0, rest padding)
	bitString := []byte{0x03, 0x02, 0x07, 0x00}

	// INTEGER 32: tag 0x02, length 1, value 32
	int32 := []byte{0x02, 0x01, 0x20}

	// INTEGER X
	intX := tsASN1Integer(xBytes)
	// INTEGER Y
	intY := tsASN1Integer(yBytes)

	// SEQUENCE
	inner := make([]byte, 0, len(bitString)+len(int32)+len(intX)+len(intY))
	inner = append(inner, bitString...)
	inner = append(inner, int32...)
	inner = append(inner, intX...)
	inner = append(inner, intY...)

	seq := []byte{0x30}
	seq = append(seq, tsASN1Length(len(inner))...)
	seq = append(seq, inner...)

	return base64.StdEncoding.EncodeToString(seq)
}

// tsASN1Integer encodes a big-endian unsigned integer as ASN.1 INTEGER.
func tsASN1Integer(b []byte) []byte {
	// Strip leading zeros but keep at least one byte
	for len(b) > 1 && b[0] == 0 {
		b = b[1:]
	}
	// If high bit set, prepend 0x00
	if len(b) > 0 && b[0]&0x80 != 0 {
		b = append([]byte{0x00}, b...)
	}
	result := []byte{0x02}
	result = append(result, tsASN1Length(len(b))...)
	result = append(result, b...)
	return result
}

// tsASN1Length encodes an ASN.1 length.
func tsASN1Length(n int) []byte {
	if n < 0x80 {
		return []byte{byte(n)}
	}
	if n < 0x100 {
		return []byte{0x81, byte(n)}
	}
	return []byte{0x82, byte(n >> 8), byte(n)}
}

// tsUID computes the TeamSpeak UID: base64(sha1(omega_base64_string))
func (id *tsP256Identity) tsUID() string {
	omega := id.tsOmega()
	h := sha1.Sum([]byte(omega))
	return base64.StdEncoding.EncodeToString(h[:])
}

// tsSign signs data with ECDSA P-256 (SHA-256), returns DER-encoded signature.
func (id *tsP256Identity) tsSign(data []byte) ([]byte, error) {
	hash := sha256.Sum256(data)
	r, s, err := ecdsa.Sign(rand.Reader, id.key, hash[:])
	if err != nil {
		return nil, err
	}
	// DER encode
	rBytes := r.Bytes()
	sBytes := s.Bytes()
	rDer := tsASN1Integer(rBytes)
	sDer := tsASN1Integer(sBytes)
	seq := []byte{0x30}
	inner := append(rDer, sDer...)
	seq = append(seq, tsASN1Length(len(inner))...)
	seq = append(seq, inner...)
	return seq, nil
}

// tsVerifyP256 verifies a DER-encoded ECDSA signature against a P-256 public key.
func tsVerifyP256(pubX, pubY *big.Int, data, sig []byte) bool {
	pub := &ecdsa.PublicKey{Curve: elliptic.P256(), X: pubX, Y: pubY}
	hash := sha256.Sum256(data)
	return ecdsa.VerifyASN1(pub, hash[:], sig)
}

// tsParseOmega parses a LibTomCrypt ASN.1-DER encoded P-256 public key.
// Returns X, Y coordinates.
func tsParseOmega(b64 string) (*big.Int, *big.Int, error) {
	data, err := base64.StdEncoding.DecodeString(b64)
	if err != nil {
		return nil, nil, err
	}
	// Parse: SEQUENCE { BIT STRING, INTEGER(32), INTEGER(X), INTEGER(Y) }
	if len(data) < 2 || data[0] != 0x30 {
		return nil, nil, fmt.Errorf("not a SEQUENCE")
	}
	inner, err := tsASN1ReadLength(data[1:])
	if err != nil {
		return nil, nil, err
	}
	offset := len(data) - len(inner)
	_ = offset

	// Skip BIT STRING
	if len(inner) < 2 || inner[0] != 0x03 {
		return nil, nil, fmt.Errorf("expected BIT STRING")
	}
	bsLen, rest, err := tsASN1ParseLength(inner[1:])
	if err != nil {
		return nil, nil, err
	}
	rest = rest[bsLen:]

	// Skip INTEGER 32
	if len(rest) < 2 || rest[0] != 0x02 {
		return nil, nil, fmt.Errorf("expected INTEGER (keysize)")
	}
	ksLen, rest2, err := tsASN1ParseLength(rest[1:])
	if err != nil {
		return nil, nil, err
	}
	rest = rest2[ksLen:]

	// Read INTEGER X
	if len(rest) < 2 || rest[0] != 0x02 {
		return nil, nil, fmt.Errorf("expected INTEGER (X)")
	}
	xLen, xData, err := tsASN1ParseLength(rest[1:])
	if err != nil {
		return nil, nil, err
	}
	x := new(big.Int).SetBytes(xData[:xLen])
	rest = xData[xLen:]

	// Read INTEGER Y
	if len(rest) < 2 || rest[0] != 0x02 {
		return nil, nil, fmt.Errorf("expected INTEGER (Y)")
	}
	yLen, yData, err := tsASN1ParseLength(rest[1:])
	if err != nil {
		return nil, nil, err
	}
	y := new(big.Int).SetBytes(yData[:yLen])
	_ = yLen
	_ = yData

	return x, y, nil
}

func tsASN1ReadLength(data []byte) ([]byte, error) {
	n, rest, err := tsASN1ParseLength(data)
	if err != nil {
		return nil, err
	}
	if len(rest) < n {
		return nil, fmt.Errorf("ASN1 truncated")
	}
	return rest[:n], nil
}

func tsASN1ParseLength(data []byte) (int, []byte, error) {
	if len(data) == 0 {
		return 0, nil, fmt.Errorf("ASN1 empty")
	}
	if data[0] < 0x80 {
		return int(data[0]), data[1:], nil
	}
	nBytes := int(data[0] & 0x7f)
	if nBytes+1 > len(data) {
		return 0, nil, fmt.Errorf("ASN1 length truncated")
	}
	n := 0
	for i := 0; i < nBytes; i++ {
		n = (n << 8) | int(data[1+i])
	}
	return n, data[1+nBytes:], nil
}

// ──────────────────────────── Ed25519 License Chain ────────────────────────────

// tsDeriveLicenseKey derives the server's ephemeral Ed25519 public key from the license chain.
// Algorithm per block: next_key = block_public_key * hash_key + parent_key
// hash_key = clamp(sha512(block_data[1:])[0:32]) as Ed25519 scalar
func tsDeriveLicenseKey(licenseData []byte, rootKey [32]byte) (*edwards25519.Point, error) {
	parentPoint, err := new(edwards25519.Point).SetBytes(rootKey[:])
	if err != nil {
		return nil, fmt.Errorf("invalid root key: %w", err)
	}

	if len(licenseData) < 1 {
		return nil, fmt.Errorf("empty license data")
	}
	// Skip version byte
	offset := 1
	for offset < len(licenseData) {
		if offset+42 > len(licenseData) {
			return nil, fmt.Errorf("license block too short at offset %d", offset)
		}

		blockData := licenseData[offset:]

		// key_type = blockData[0] (should be 0x00 for public key)
		// pub_key = blockData[1:33]
		// block_type = blockData[33]
		// not_valid_before = blockData[34:38]
		// not_valid_after = blockData[38:42]
		// content follows (variable length)

		pubKeyBytes := blockData[1:33]
		blockType := blockData[33]

		// Determine block length (need to find content end)
		contentStart := 42
		blockLen := contentStart
		switch blockType {
		case 0: // Intermediate: 4 bytes unknown + null-terminated string
			blockLen = contentStart + 4
			for blockLen < len(blockData) && blockData[blockLen] != 0 {
				blockLen++
			}
			if blockLen < len(blockData) {
				blockLen++ // skip null terminator
			}
		case 2: // Server: 1 byte license type + 4 bytes max clients + null-terminated string
			blockLen = contentStart + 5
			for blockLen < len(blockData) && blockData[blockLen] != 0 {
				blockLen++
			}
			if blockLen < len(blockData) {
				blockLen++ // skip null terminator
			}
		case 1, 3: // Website/Code: null-terminated string
			blockLen = contentStart
			for blockLen < len(blockData) && blockData[blockLen] != 0 {
				blockLen++
			}
			if blockLen < len(blockData) {
				blockLen++ // skip null terminator
			}
		case 32: // Ephemeral: no content
			blockLen = contentStart
		default:
			// Unknown block type, try to parse as null-terminated
			blockLen = contentStart
			for blockLen < len(blockData) && blockData[blockLen] != 0 {
				blockLen++
			}
			if blockLen < len(blockData) {
				blockLen++
			}
		}

		// Get hash_key: clamp(sha512(blockData[1:blockLen])[0:32])
		fullHash := sha512.Sum512(blockData[1:blockLen])
		var hashKeyBytes [32]byte
		copy(hashKeyBytes[:], fullHash[:32])
		// Clamp
		hashKeyBytes[0] &= 248
		hashKeyBytes[31] &= 63
		hashKeyBytes[31] |= 64

		hashKeyScalar, err := new(edwards25519.Scalar).SetCanonicalBytes(hashKeyBytes[:])
		if err != nil {
			// Try SetBytesWithClamping
			hashKeyScalar, err = new(edwards25519.Scalar).SetBytesWithClamping(fullHash[:32])
			if err != nil {
				return nil, fmt.Errorf("invalid hash key scalar: %w", err)
			}
		}

		// Get block public key point
		blockPubPoint, err := new(edwards25519.Point).SetBytes(pubKeyBytes)
		if err != nil {
			return nil, fmt.Errorf("invalid block public key: %w", err)
		}

		// next = block_pub * hash_key + parent
		scaledPub := new(edwards25519.Point).ScalarMult(hashKeyScalar, blockPubPoint)
		parentPoint = new(edwards25519.Point).Add(scaledPub, parentPoint)

		offset += blockLen
	}

	return parentPoint, nil
}

// ──────────────────────────── Shared IV/MAC computation ────────────────────────────

// tsComputeSharedIVMAC computes the shared IV and shared MAC for the new protocol (initivexpand2).
// alpha: 10 bytes, beta: 54 bytes
// shared_secret from Ed25519 ECDH
func tsComputeSharedIVMAC(alpha [10]byte, beta [54]byte, ekPriv *edwards25519.Scalar, serverEK *edwards25519.Point) ([64]byte, [8]byte) {
	// ECDH: shared_secret = ekPriv * serverEK
	sharedSecret := new(edwards25519.Point).ScalarMult(ekPriv, serverEK)
	secretBytes := sharedSecret.Bytes()

	// SharedIV = SHA-512(shared_secret)
	var sharedIV [64]byte
	h := sha512.Sum512(secretBytes)
	copy(sharedIV[:], h[:])

	// XOR alpha and beta
	for i := 0; i < 10; i++ {
		sharedIV[i] ^= alpha[i]
	}
	for i := 0; i < 54; i++ {
		sharedIV[i+10] ^= beta[i]
	}

	// SharedMAC = SHA-1(SharedIV)[0:8]
	var sharedMAC [8]byte
	macHash := sha1.Sum(sharedIV[:])
	copy(sharedMAC[:], macHash[:8])

	return sharedIV, sharedMAC
}

// ──────────────────────────── Hashcash ────────────────────────────

// tsHashCash computes the hashcash offset for identity proof-of-work.
// Returns offset such that leading zero bits of SHA1(omega + offset) >= level.
func tsHashCash(omega string, level byte) uint64 {
	for offset := uint64(0); offset < ^uint64(0); offset++ {
		data := fmt.Sprintf("%s%d", omega, offset)
		h := sha1.Sum([]byte(data))
		zeros := tsCountLeadingZeros(h[:])
		if zeros >= level {
			return offset
		}
	}
	return 0
}

func tsCountLeadingZeros(data []byte) byte {
	var count byte
	for _, b := range data {
		if b == 0 {
			count += 8
		} else {
			// Count trailing zeros of the byte (TS3 counts from LSB per byte in big-endian hash)
			for i := byte(0); i < 8; i++ {
				if b&(1<<i) != 0 {
					break
				}
				count++
			}
			break
		}
	}
	return count
}

// ──────────────────────────── TS3 Command Escape ────────────────────────────

func tsEscape(s string) string {
	s = strings.ReplaceAll(s, `\`, `\\`)
	s = strings.ReplaceAll(s, `/`, `\/`)
	s = strings.ReplaceAll(s, ` `, `\s`)
	s = strings.ReplaceAll(s, `|`, `\p`)
	s = strings.ReplaceAll(s, "\a", `\a`)
	s = strings.ReplaceAll(s, "\b", `\b`)
	s = strings.ReplaceAll(s, "\f", `\f`)
	s = strings.ReplaceAll(s, "\n", `\n`)
	s = strings.ReplaceAll(s, "\r", `\r`)
	s = strings.ReplaceAll(s, "\t", `\t`)
	s = strings.ReplaceAll(s, "\v", `\v`)
	return s
}

func tsUnescape(s string) string {
	var buf strings.Builder
	buf.Grow(len(s))
	for i := 0; i < len(s); i++ {
		if s[i] == '\\' && i+1 < len(s) {
			switch s[i+1] {
			case '\\':
				buf.WriteByte('\\')
			case '/':
				buf.WriteByte('/')
			case 's':
				buf.WriteByte(' ')
			case 'p':
				buf.WriteByte('|')
			case 'a':
				buf.WriteByte('\a')
			case 'b':
				buf.WriteByte('\b')
			case 'f':
				buf.WriteByte('\f')
			case 'n':
				buf.WriteByte('\n')
			case 'r':
				buf.WriteByte('\r')
			case 't':
				buf.WriteByte('\t')
			case 'v':
				buf.WriteByte('\v')
			default:
				buf.WriteByte('\\')
				buf.WriteByte(s[i+1])
			}
			i++
		} else {
			buf.WriteByte(s[i])
		}
	}
	return buf.String()
}

func tsParseKV(s string) map[string]string {
	m := make(map[string]string)
	for _, pair := range strings.Fields(s) {
		idx := strings.IndexByte(pair, '=')
		if idx < 0 {
			m[pair] = ""
		} else {
			m[pair[:idx]] = tsUnescape(pair[idx+1:])
		}
	}
	return m
}

func tsParseKVList(s string) []map[string]string {
	entries := strings.Split(s, "|")
	result := make([]map[string]string, 0, len(entries))
	for _, entry := range entries {
		entry = strings.TrimSpace(entry)
		if entry == "" {
			continue
		}
		result = append(result, tsParseKV(entry))
	}
	return result
}

// tsParseCommand parses "cmdname key=val key=val" into (name, params).
func tsParseCommand(data []byte) (string, map[string]string) {
	s := string(data)
	// Strip trailing null
	s = strings.TrimRight(s, "\x00")
	spaceIdx := strings.IndexByte(s, ' ')
	if spaceIdx < 0 {
		return s, make(map[string]string)
	}
	return s[:spaceIdx], tsParseKV(s[spaceIdx+1:])
}

// ──────────────────────────── Packet Building ────────────────────────────

// tsBuildC2SPacket creates a C2S packet.
// Header: MAC(8) + PId(2) + CId(2) + PT(1) = 13 bytes
func tsBuildC2SPacket(mac [8]byte, pID, cID uint16, pType byte, data []byte) []byte {
	pkt := make([]byte, 13+len(data))
	copy(pkt[:8], mac[:])
	binary.BigEndian.PutUint16(pkt[8:10], pID)
	binary.BigEndian.PutUint16(pkt[10:12], cID)
	pkt[12] = pType
	copy(pkt[13:], data)
	return pkt
}

// tsParseS2CPacket parses a S2C packet.
// Header: MAC(8) + PId(2) + PT(1) = 11 bytes
func tsParseS2CPacket(raw []byte) (mac [8]byte, pID uint16, pType byte, data []byte, err error) {
	if len(raw) < 11 {
		err = fmt.Errorf("packet too short: %d bytes", len(raw))
		return
	}
	copy(mac[:], raw[:8])
	pID = binary.BigEndian.Uint16(raw[8:10])
	pType = raw[10]
	data = raw[11:]
	return
}

// ──────────────────────────── Init Packets ────────────────────────────

func tsBuildInit0(version uint32, timestamp uint32, random0 [4]byte) []byte {
	data := make([]byte, 21)
	binary.BigEndian.PutUint32(data[0:4], version)
	data[4] = 0x00 // step 0
	binary.BigEndian.PutUint32(data[5:9], timestamp)
	copy(data[9:13], random0[:])
	// data[13:21] = zeros (reserved)
	return tsBuildC2SPacket(tsInitMAC, 101, 0, tsFlagUnencrypted|tsPktInit, data)
}

func tsBuildInit2(version uint32, random1 [16]byte, random0r [4]byte) []byte {
	data := make([]byte, 25)
	binary.BigEndian.PutUint32(data[0:4], version)
	data[4] = 0x02 // step 2
	copy(data[5:21], random1[:])
	copy(data[21:25], random0r[:])
	return tsBuildC2SPacket(tsInitMAC, 101, 0, tsFlagUnencrypted|tsPktInit, data)
}

func tsBuildInit4(version uint32, x, n [64]byte, level uint32, random2 [100]byte, y [64]byte, commandData []byte) []byte {
	data := make([]byte, 301+len(commandData))
	binary.BigEndian.PutUint32(data[0:4], version)
	data[4] = 0x04 // step 4
	copy(data[5:69], x[:])
	copy(data[69:133], n[:])
	binary.BigEndian.PutUint32(data[133:137], level)
	copy(data[137:237], random2[:])
	copy(data[237:301], y[:])
	if len(commandData) > 0 {
		copy(data[301:], commandData)
	}
	// Note: init4 can exceed 500 bytes (the clientinitiv command appended to it)
	return tsBuildC2SPacket(tsInitMAC, 101, 0, tsFlagUnencrypted|tsPktInit, data[:301+len(commandData)])
}

// tsParseInit1 parses an Init1 (step 1) S2C response.
func tsParseInit1(data []byte) (random1 [16]byte, random0r [4]byte, err error) {
	if len(data) < 21 {
		err = fmt.Errorf("init1 too short: %d", len(data))
		return
	}
	if data[0] != 0x01 {
		err = fmt.Errorf("not step 1: %d", data[0])
		return
	}
	copy(random1[:], data[1:17])
	copy(random0r[:], data[17:21])
	return
}

// tsParseInit3 parses an Init3 (step 3) S2C response.
func tsParseInit3(data []byte) (x, n [64]byte, level uint32, random2 [100]byte, err error) {
	if len(data) < 233 {
		err = fmt.Errorf("init3 too short: %d", len(data))
		return
	}
	step := data[0]
	if step == 127 {
		err = fmt.Errorf("server sent step 127: retry")
		return
	}
	if step != 0x03 {
		err = fmt.Errorf("not step 3: %d", step)
		return
	}
	copy(x[:], data[1:65])
	copy(n[:], data[65:129])
	level = binary.BigEndian.Uint32(data[129:133])
	copy(random2[:], data[133:233])
	return
}

// ──────────────────────────── TS3 Connection State ────────────────────────────

type tsPacketState struct {
	nextSendID  uint16
	nextRecvID  uint16
	sendGenID   uint32
	recvGenID   uint32
}

type tsPendingCmd struct {
	pktID  uint16
	data   []byte // full packet for retransmission
	sentAt time.Time
	acked  bool
}

// tsDecryptedPkt holds a decrypted command packet waiting for in-order processing.
type tsDecryptedPkt struct {
	pID       uint16
	flags     byte
	plaintext []byte
}

type tsConnection struct {
	conn     *net.UDPConn
	addr     *net.UDPAddr
	identity *tsP256Identity
	owner    *TeamSpeakCore // back-reference for voice callbacks

	// Per-type packet counters
	pktState [9]tsPacketState // indexed by packet type

	// Crypto state
	sharedIV  [64]byte
	sharedMAC [8]byte
	cryptoOK  bool
	clientID  uint16

	// Receive queue for out-of-order command packets (per command type)
	recvQueue    [2]map[uint16]*tsDecryptedPkt // [0]=Command, [1]=CommandLow
	recvQueueMu  sync.Mutex

	// Fragment assembly state (per command type)
	fragBuf   [2][]byte // accumulated fragment data
	fragFlags [2]byte   // flags from first fragment (has Compressed bit)

	// Pending commands awaiting ACK
	pendingCmds  map[uint16]*tsPendingCmd
	pendingCmdMu sync.Mutex

	// Incoming command channel
	cmdCh chan tsIncomingCmd

	// When set, tsExec is waiting for a response — tsCommandLoop defers to it
	execCh   chan tsIncomingCmd
	execMu   sync.Mutex
	execWait bool

	mu sync.Mutex
}

type tsIncomingCmd struct {
	name   string
	params map[string]string
	raw    string
}

// ──────────────────────────── TeamSpeakCore ────────────────────────────

type TeamSpeakCore struct {
	mu sync.RWMutex

	tsConn *tsConnection

	authed   bool
	isBot    bool
	nickname string

	// Server connection info
	serverAddr string

	// Self info (from initserver)
	myClientID int
	myDBID     int
	myUID      string
	myName     string

	// Current channel
	myChannelID int

	sessionPath string

	// Update handlers
	updateHandlers []func(Update)
	updateMu       sync.RWMutex

	// Message buffer
	msgBuffer  map[string][]Message
	msgBufMu   sync.RWMutex
	msgCounter atomic.Int64

	// Client cache: clid → info
	clientInfo   map[int]tsClientInfo
	clientInfoMu sync.RWMutex

	// Channel cache: cid → info
	channels   map[int]tsChannelInfo
	channelsMu sync.RWMutex

	// Voice state
	voiceHandler   func(VoicePacket)
	voiceHandlerMu sync.RWMutex

	// Bandwidth stats
	bwStats tsBandwidthStats

	// Context
	ctx    context.Context
	cancel context.CancelFunc
}

// VoicePacket represents incoming or outgoing voice audio data.
type VoicePacket struct {
	SenderClientID int    // S2C only: who sent this voice
	Codec          byte   // 0=SpeexNB, 1=SpeexWB, 2=SpeexUWB, 3=CeltMono, 4=OpusVoice, 5=OpusMusic
	AudioData      []byte // encoded audio frame
	PacketCounter  uint16
	IsWhisper      bool
	ServerFlag     byte // decoder session tracking (0 if not present)
	HasServerFlag  bool
}

type tsClientInfo struct {
	clid      int
	dbid      int
	uid       string
	nickname  string
	channelID int
	isQuery   bool
}

type tsChannelInfo struct {
	cid          int
	pid          int
	name         string
	topic        string
	totalClients int
	order        int
	flags        map[string]bool // e.g., "channel_flag_permanent"
}

type tsSession struct {
	ServerAddr string `json:"server_address"`
	Nickname   string `json:"nickname,omitempty"`
	// Identity key (P-256 private key, base64 encoded)
	IdentityD  string `json:"identity_d,omitempty"`
	IdentityX  string `json:"identity_x,omitempty"`
	IdentityY  string `json:"identity_y,omitempty"`
	KeyOffset  uint64 `json:"key_offset,omitempty"`
}

func NewTeamSpeakCore(sessionPath string) *TeamSpeakCore {
	ctx, cancel := context.WithCancel(context.Background())
	return &TeamSpeakCore{
		sessionPath: sessionPath,
		msgBuffer:   make(map[string][]Message),
		clientInfo:  make(map[int]tsClientInfo),
		channels:    make(map[int]tsChannelInfo),
		ctx:         ctx,
		cancel:      cancel,
	}
}

func (t *TeamSpeakCore) Name() string { return "teamspeak" }

func (t *TeamSpeakCore) Capabilities() []string {
	return []string{"CHANNELS", "ADMIN", "SESSIONS"}
}

// ──────────────────────────── UDP Transport ────────────────────────────

func (tc *tsConnection) tsNextPktID(pType byte) uint16 {
	idx := pType & 0x0f
	id := tc.pktState[idx].nextSendID
	tc.pktState[idx].nextSendID++
	if tc.pktState[idx].nextSendID == 0 {
		tc.pktState[idx].sendGenID++
	}
	return id
}

// tsSendRaw sends a raw UDP packet.
func (tc *tsConnection) tsSendRaw(pkt []byte) error {
	_, err := tc.conn.WriteToUDP(pkt, tc.addr)
	return err
}

// tsSendCommand sends an encrypted Command packet. Handles compression and fragmentation.
func (tc *tsConnection) tsSendCommand(cmdStr string) (uint16, error) {
	tc.mu.Lock()
	defer tc.mu.Unlock()

	cmdBytes := []byte(cmdStr)

	// Try compression if large
	compressed := false
	if len(cmdBytes) > tsMaxPayloadC2S {
		// TODO: QuickLZ compression. For now, skip compression.
		// Most commands fit in a single packet.
		_ = compressed
	}

	// Check if fragmentation needed
	if len(cmdBytes) <= tsMaxPayloadC2S {
		// Single packet
		pID := tc.tsNextPktID(tsPktCommand)
		flags := byte(tsPktCommand) | tsFlagNewprotocol
		meta := make([]byte, 5) // PId(2) + CId(2) + PT(1) for C2S
		binary.BigEndian.PutUint16(meta[0:2], pID)
		binary.BigEndian.PutUint16(meta[2:4], tc.clientID)
		meta[4] = flags

		var mac [8]byte
		var ciphertext []byte
		if tc.cryptoOK {
			key, nonce := tsCreateKeyNonce(tsPktCommand, pID, tc.pktState[tsPktCommand].sendGenID, 0x31, tc.sharedIV[:])
			mac, ciphertext = tsEAXEncrypt(key[:], nonce[:], meta, cmdBytes)
		} else {
			mac, ciphertext = tsEAXEncrypt(tsFakeKey[:], tsFakeNonce[:], meta, cmdBytes)
		}

		pkt := tsBuildC2SPacket(mac, pID, tc.clientID, flags, ciphertext)

		// Track for ACK
		tc.pendingCmdMu.Lock()
		tc.pendingCmds[pID] = &tsPendingCmd{pktID: pID, data: pkt, sentAt: time.Now()}
		tc.pendingCmdMu.Unlock()

		if tc.owner != nil {
			tc.owner.bwStats.recordSent(tsPktCommand, len(pkt))
		}
		if err := tc.tsSendRaw(pkt); err != nil {
			return 0, err
		}
		return pID, nil
	}

	// Fragmentation
	chunks := make([][]byte, 0)
	remaining := cmdBytes
	for len(remaining) > 0 {
		chunkSize := tsMaxPayloadC2S
		if chunkSize > len(remaining) {
			chunkSize = len(remaining)
		}
		chunks = append(chunks, remaining[:chunkSize])
		remaining = remaining[chunkSize:]
	}

	var firstPID uint16
	for i, chunk := range chunks {
		pID := tc.tsNextPktID(tsPktCommand)
		if i == 0 {
			firstPID = pID
		}

		flags := byte(tsPktCommand) | tsFlagNewprotocol
		if i == 0 || i == len(chunks)-1 {
			flags |= tsFlagFragmented
		}
		if i == 0 && compressed {
			flags |= tsFlagCompressed
		}

		meta := make([]byte, 5)
		binary.BigEndian.PutUint16(meta[0:2], pID)
		binary.BigEndian.PutUint16(meta[2:4], tc.clientID)
		meta[4] = flags

		var mac [8]byte
		var ciphertext []byte
		if tc.cryptoOK {
			key, nonce := tsCreateKeyNonce(tsPktCommand, pID, tc.pktState[tsPktCommand].sendGenID, 0x31, tc.sharedIV[:])
			mac, ciphertext = tsEAXEncrypt(key[:], nonce[:], meta, chunk)
		} else {
			mac, ciphertext = tsEAXEncrypt(tsFakeKey[:], tsFakeNonce[:], meta, chunk)
		}

		pkt := tsBuildC2SPacket(mac, pID, tc.clientID, flags, ciphertext)

		tc.pendingCmdMu.Lock()
		tc.pendingCmds[pID] = &tsPendingCmd{pktID: pID, data: pkt, sentAt: time.Now()}
		tc.pendingCmdMu.Unlock()

		if err := tc.tsSendRaw(pkt); err != nil {
			return 0, err
		}
	}
	return firstPID, nil
}

// tsSendAck sends an ACK for a received command packet.
func (tc *tsConnection) tsSendAck(pID uint16) error {
	tc.mu.Lock()
	defer tc.mu.Unlock()

	ackData := make([]byte, 2)
	binary.BigEndian.PutUint16(ackData, pID)

	ackPID := tc.tsNextPktID(tsPktAck)
	flags := byte(tsPktAck)

	meta := make([]byte, 5)
	binary.BigEndian.PutUint16(meta[0:2], ackPID)
	binary.BigEndian.PutUint16(meta[2:4], tc.clientID)
	meta[4] = flags

	if tc.cryptoOK {
		key, nonce := tsCreateKeyNonce(tsPktAck, ackPID, tc.pktState[tsPktAck].sendGenID, 0x31, tc.sharedIV[:])
		mac, ciphertext := tsEAXEncrypt(key[:], nonce[:], meta, ackData)
		pkt := tsBuildC2SPacket(mac, ackPID, tc.clientID, flags, ciphertext)
		return tc.tsSendRaw(pkt)
	}

	mac, ciphertext := tsEAXEncrypt(tsFakeKey[:], tsFakeNonce[:], meta, ackData)
	pkt := tsBuildC2SPacket(mac, ackPID, tc.clientID, flags, ciphertext)
	return tc.tsSendRaw(pkt)
}

// tsSendPing sends a ping packet.
func (tc *tsConnection) tsSendPing() error {
	tc.mu.Lock()
	defer tc.mu.Unlock()

	pID := tc.tsNextPktID(tsPktPing)
	flags := byte(tsPktPing) | tsFlagUnencrypted
	pkt := tsBuildC2SPacket(tc.sharedMAC, pID, tc.clientID, flags, nil)
	return tc.tsSendRaw(pkt)
}

// tsSendPong sends a pong in response to a ping.
func (tc *tsConnection) tsSendPong(pingID uint16) error {
	tc.mu.Lock()
	defer tc.mu.Unlock()

	pongData := make([]byte, 2)
	binary.BigEndian.PutUint16(pongData, pingID)

	pID := tc.tsNextPktID(tsPktPong)
	flags := byte(tsPktPong) | tsFlagUnencrypted
	pkt := tsBuildC2SPacket(tc.sharedMAC, pID, tc.clientID, flags, pongData)
	return tc.tsSendRaw(pkt)
}

// ──────────────────────────── Receive Loop ────────────────────────────

func (tc *tsConnection) tsReceiveLoop(ctx context.Context) {

	buf := make([]byte, 2048)
	for {
		select {
		case <-ctx.Done():
			return
		default:
		}

		tc.conn.SetReadDeadline(time.Now().Add(tsReadTimeout))
		n, _, err := tc.conn.ReadFromUDP(buf)
		if err != nil {
			if netErr, ok := err.(net.Error); ok && netErr.Timeout() {
				continue
			}
			return
		}

		raw := make([]byte, n)
		copy(raw, buf[:n])
		go tc.tsHandlePacket(raw)
	}
}

func (tc *tsConnection) tsHandlePacket(raw []byte) {
	mac, pID, pType, data, err := tsParseS2CPacket(raw)
	if err != nil {
		fmt.Printf("[TS3 RX] parse error: %v\n", err)
		return
	}


	flags := pType & 0xf0
	packetType := pType & 0x0f

	// Track received bandwidth
	if tc.owner != nil {
		tc.owner.bwStats.recordRecv(packetType, len(raw))
	}



	switch packetType {
	case tsPktCommand, tsPktCommandLow:
		// Decrypt
		var plaintext []byte
		meta := raw[8:11] // PId(2) + PT(1) for S2C

		if flags&tsFlagUnencrypted != 0 {
			plaintext = data
		} else if tc.cryptoOK {
			key, nonce := tsCreateKeyNonce(packetType, pID, tc.pktState[packetType].recvGenID, 0x30, tc.sharedIV[:])
			plaintext, err = tsEAXDecrypt(key[:], nonce[:], meta, data, mac)
			if err != nil {
				fmt.Printf("[TS3 RX] cmd decrypt FAIL pID=%d type=0x%02x err=%v\n", pID, pType, err)
				return
			}
		} else {
			plaintext, err = tsEAXDecrypt(tsFakeKey[:], tsFakeNonce[:], meta, data, mac)
			if err != nil {
				fmt.Printf("[TS3 RX] cmd fake decrypt FAIL pID=%d err=%v\n", pID, err)
				return
			}
		}

		// Send ACK immediately regardless of ordering
		tc.tsSendAck(pID)

		// Queue the decrypted packet for in-order processing
		cmdI := 0
		if packetType == tsPktCommandLow {
			cmdI = 1
		}
		tc.recvQueueMu.Lock()
		tc.recvQueue[cmdI][pID] = &tsDecryptedPkt{pID: pID, flags: byte(flags) | byte(packetType), plaintext: plaintext}
		tc.tsProcessCommandQueue(cmdI)
		tc.recvQueueMu.Unlock()

	case tsPktAck:
		// An ACK for one of our commands
		if len(data) >= 2 {
			var ackPlain []byte
			meta := raw[8:11]

			if flags&tsFlagUnencrypted != 0 {
				// Unencrypted ACK — data is plaintext
				ackPlain = data
			} else if pID <= 1 {
				// Early ACKs: try fake decrypt first, fallback to real
				ackPlain, err = tsEAXDecrypt(tsFakeKey[:], tsFakeNonce[:], meta, data, mac)
				if err != nil && tc.cryptoOK {
					key, nonce := tsCreateKeyNonce(tsPktAck, pID, tc.pktState[tsPktAck].recvGenID, 0x30, tc.sharedIV[:])
					ackPlain, err = tsEAXDecrypt(key[:], nonce[:], meta, data, mac)
				}
			} else if tc.cryptoOK {
				key, nonce := tsCreateKeyNonce(tsPktAck, pID, tc.pktState[tsPktAck].recvGenID, 0x30, tc.sharedIV[:])
				ackPlain, err = tsEAXDecrypt(key[:], nonce[:], meta, data, mac)
			} else {
				ackPlain, err = tsEAXDecrypt(tsFakeKey[:], tsFakeNonce[:], meta, data, mac)
			}
			if err != nil || len(ackPlain) < 2 {
				fmt.Printf("[TS3 RX] ack decrypt FAIL pID=%d err=%v\n", pID, err)
				return
			}
			ackedPID := binary.BigEndian.Uint16(ackPlain[:2])

			tc.pendingCmdMu.Lock()
			if cmd, ok := tc.pendingCmds[ackedPID]; ok {
				cmd.acked = true
				delete(tc.pendingCmds, ackedPID)
			}
			tc.pendingCmdMu.Unlock()
		}

	case tsPktPing:
		// Respond with pong
		tc.tsSendPong(pID)

	case tsPktPong:
		// Pong received (keepalive response), nothing to do

	case tsPktInit:
		// S2C init packets handled during handshake, not in the receive loop

	case tsPktVoice, tsPktVoiceWhisper:
		// Voice data — decrypt and dispatch
		var plaintext []byte
		meta := raw[8:11] // PId(2) + PT(1)

		if flags&tsFlagUnencrypted != 0 {
			plaintext = data
		} else if tc.cryptoOK {
			key, nonce := tsCreateKeyNonce(packetType, pID, tc.pktState[packetType].recvGenID, 0x30, tc.sharedIV[:])
			plaintext, err = tsEAXDecrypt(key[:], nonce[:], meta, data, mac)
			if err != nil {
				fmt.Printf("[TS3 VOICE] decrypt fail pID=%d len=%d: %v\n", pID, len(data), err)
				return
			}
		} else {
			fmt.Printf("[TS3 VOICE] no crypto for voice pID=%d\n", pID)
			return // can't decrypt voice without crypto
		}

		tc.owner.tsHandleVoicePacket(packetType, byte(flags), plaintext)
	}
}

// tsProcessCommandQueue processes command packets in order.
// Must be called with recvQueueMu held.
func (tc *tsConnection) tsProcessCommandQueue(cmdI int) {
	pktType := tsPktCommand
	if cmdI == 1 {
		pktType = tsPktCommandLow
	}

	for {
		nextID := tc.pktState[pktType].nextRecvID
		pkt, ok := tc.recvQueue[cmdI][nextID]
		if !ok {
			if len(tc.recvQueue[cmdI]) > 0 {
				keys := make([]uint16, 0, len(tc.recvQueue[cmdI]))
				for k := range tc.recvQueue[cmdI] {
					keys = append(keys, k)
				}
	
			}
			return // waiting for the next in-order packet
		}
		delete(tc.recvQueue[cmdI], nextID)

		// Advance expected packet ID
		tc.pktState[pktType].nextRecvID++

		flags := pkt.flags & 0xf0
		plaintext := pkt.plaintext

		// Fragmentation handling
		hasFR := flags&tsFlagFragmented != 0
		if hasFR && tc.fragBuf[cmdI] == nil {
			// First fragment: FR set, may have Compressed flag
			tc.fragBuf[cmdI] = make([]byte, 0, 4096)
			tc.fragFlags[cmdI] = flags
			tc.fragBuf[cmdI] = append(tc.fragBuf[cmdI], plaintext...)

			continue
		} else if tc.fragBuf[cmdI] != nil && !hasFR {
			// Middle fragment: no FR flag, append
			tc.fragBuf[cmdI] = append(tc.fragBuf[cmdI], plaintext...)

			continue
		} else if tc.fragBuf[cmdI] != nil && hasFR {
			// Last fragment: FR set again
			tc.fragBuf[cmdI] = append(tc.fragBuf[cmdI], plaintext...)
			assembled := tc.fragBuf[cmdI]
			firstFlags := tc.fragFlags[cmdI]
			tc.fragBuf[cmdI] = nil



			// Decompress if first fragment had Compressed flag
			if firstFlags&tsFlagCompressed != 0 {
				decompressed, err := tsQuickLZDecompress(assembled)
				if err != nil {
					fmt.Printf("[TS3 FRAG] decompress FAIL: %v\n", err)
					continue
				}
	
				assembled = decompressed
			}

			plaintext = assembled
		} else {
			// Non-fragmented packet: decompress if needed
			if flags&tsFlagCompressed != 0 {
				decompressed, err := tsQuickLZDecompress(plaintext)
				if err != nil {
					fmt.Printf("[TS3 RX] decompress FAIL pID=%d: %v\n", pkt.pID, err)
					continue
				}
				plaintext = decompressed
			}
		}

		// TS3 sends multiple commands per packet separated by \n\r (0x0A 0x0D).
		// Split on \n to handle both \n\r and bare \n.
		lines := bytes.Split(plaintext, []byte("\n"))
		for _, line := range lines {
			line = bytes.TrimRight(line, "\x00\r\n")
			if len(line) == 0 {
				continue
			}
			name, params := tsParseCommand(line)
			select {
			case tc.cmdCh <- tsIncomingCmd{name: name, params: params, raw: string(line)}:
			default:
				fmt.Printf("[TS3 CMD] cmdCh FULL, dropping: %s\n", name)
			}
		}
	}
}

// ──────────────────────────── Keepalive ────────────────────────────

func (tc *tsConnection) tsKeepaliveLoop(ctx context.Context) {
	ticker := time.NewTicker(tsPingInterval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			tc.tsSendPing()
		}
	}
}

// ──────────────────────────── Connection & Handshake ────────────────────────────

func (t *TeamSpeakCore) tsConnect(addr string) error {
	host, port, err := net.SplitHostPort(addr)
	if err != nil {
		host = addr
		port = tsVoicePort
	}

	udpAddr, err := net.ResolveUDPAddr("udp", net.JoinHostPort(host, port))
	if err != nil {
		return fmt.Errorf("%w: resolve failed: %v", ErrNetwork, err)
	}

	conn, err := net.ListenUDP("udp", nil)
	if err != nil {
		return fmt.Errorf("%w: listen failed: %v", ErrNetwork, err)
	}

	tc := &tsConnection{
		conn:        conn,
		addr:        udpAddr,
		identity:    nil,
		owner:       t,
		pendingCmds: make(map[uint16]*tsPendingCmd),
		recvQueue:   [2]map[uint16]*tsDecryptedPkt{make(map[uint16]*tsDecryptedPkt), make(map[uint16]*tsDecryptedPkt)},
		cmdCh:       make(chan tsIncomingCmd, 64),
	}

	// Initialize packet IDs to 0
	for i := 0; i < 9; i++ {
		tc.pktState[i].nextSendID = 0
		tc.pktState[i].nextRecvID = 0
	}

	t.tsConn = tc
	return nil
}

// tsHandshake performs the full TS3 init handshake (steps 0-4) + high-level handshake.
func (t *TeamSpeakCore) tsHandshake(nickname string) error {
	tc := t.tsConn

	// Generate or load identity
	if tc.identity == nil {
		id, err := tsNewIdentity()
		if err != nil {
			return fmt.Errorf("identity gen failed: %w", err)
		}
		tc.identity = id
	}

	// tsproto uses current time as "version" field (not the build timestamp)
	timestamp := uint32(time.Now().Unix())
	version := timestamp - tsEpochOffset

	var random0 [4]byte
	rand.Read(random0[:])

	// The handshake reads packets directly from the UDP connection for Init steps 0-4.
	// The receive loop is started later, after crypto is established, for command exchange.
	// cancelRecv is a no-op during init steps; set properly when receive loop starts.
	cancelRecv := func() {} // no-op initially

	// --- Init Step 0 → Step 1 ---
	var random1 [16]byte
	var random0r [4]byte

	for attempt := 0; attempt < 5; attempt++ {
		init0 := tsBuildInit0(version, timestamp, random0)
		if err := tc.tsSendRaw(init0); err != nil {
			cancelRecv()
			return fmt.Errorf("%w: init0 send: %v", ErrNetwork, err)
		}

		// Wait for Init1 response
		buf := make([]byte, 2048)
		tc.conn.SetReadDeadline(time.Now().Add(5 * time.Second))
		n, _, err := tc.conn.ReadFromUDP(buf)
		if err != nil {
			if attempt < 4 {
				continue
			}
			cancelRecv()
			return fmt.Errorf("%w: no init1 response: %v", ErrNetwork, err)
		}

		rawPkt := buf[:n]
		mac, _, pType, data, err := tsParseS2CPacket(rawPkt)
		if err != nil || pType&0x0f != tsPktInit {
			if attempt < 4 {
				continue
			}
			cancelRecv()
			return fmt.Errorf("%w: unexpected response to init0 (ptype=0x%02x, len=%d, mac=%x)", ErrNetwork, pType, n, mac)
		}

		// Check if this is the TS3INIT1 MAC
		if mac != tsInitMAC {
			if attempt < 4 {
				continue
			}
			cancelRecv()
			return fmt.Errorf("%w: init response has wrong MAC: %x", ErrNetwork, mac)
		}

		random1, random0r, err = tsParseInit1(data)
		if err != nil {
			if attempt < 4 {
				continue
			}
			cancelRecv()
			return fmt.Errorf("%w: init1 parse (data len=%d, data=%x): %v", ErrNetwork, len(data), data, err)
		}
		break
	}

	// --- Init Step 2 → Step 3 ---
	init2 := tsBuildInit2(version, random1, random0r)
	if err := tc.tsSendRaw(init2); err != nil {
		cancelRecv()
		return fmt.Errorf("%w: init2 send: %v", ErrNetwork, err)
	}

	var x, n [64]byte
	var level uint32
	var random2 [100]byte

	for attempt := 0; attempt < 5; attempt++ {
		buf := make([]byte, 2048)
		tc.conn.SetReadDeadline(time.Now().Add(5 * time.Second))
		nRead, _, err := tc.conn.ReadFromUDP(buf)
		if err != nil {
			if attempt < 4 {
				// Resend init2
				tc.tsSendRaw(init2)
				continue
			}
			cancelRecv()
			return fmt.Errorf("%w: no init3 response: %v", ErrNetwork, err)
		}

		_, _, pType, data, err := tsParseS2CPacket(buf[:nRead])
		if err != nil || pType&0x0f != tsPktInit {
			continue
		}

		x, n, level, random2, err = tsParseInit3(data)
		if err != nil {
			if strings.Contains(err.Error(), "step 127") {
				// Server says retry — start over
				cancelRecv()
				return t.tsHandshake(nickname)
			}
			if attempt < 4 {
				continue
			}
			cancelRecv()
			return fmt.Errorf("%w: init3 parse: %v", ErrNetwork, err)
		}
		break
	}

	// --- Solve RSA puzzle: y = x^(2^level) mod n ---
	xBig := new(big.Int).SetBytes(x[:])
	nBig := new(big.Int).SetBytes(n[:])
	eBig := new(big.Int).Lsh(big.NewInt(1), uint(level))
	yBig := new(big.Int).Exp(xBig, eBig, nBig)

	var yBytes [64]byte
	yRaw := yBig.Bytes()
	// Right-align (pad from left with zeros)
	copy(yBytes[64-len(yRaw):], yRaw)

	// --- Build clientinitiv command ---
	var alpha [10]byte
	rand.Read(alpha[:])
	alphaB64 := base64.StdEncoding.EncodeToString(alpha[:])
	omega := tc.identity.tsOmega()

	ip := tc.addr.IP.String()
	clientinitiv := fmt.Sprintf("clientinitiv alpha=%s omega=%s ot=1 ip=%s",
		tsEscape(alphaB64), tsEscape(omega), tsEscape(ip))

	// --- Init Step 4 ---
	init4 := tsBuildInit4(version, x, n, level, random2, yBytes, []byte(clientinitiv))
	if err := tc.tsSendRaw(init4); err != nil {
		cancelRecv()
		return fmt.Errorf("%w: init4 send: %v", ErrNetwork, err)
	}

	// --- Wait for initivexpand2 (encrypted with fake key, may be fragmented) ---
	var initivCmd tsIncomingCmd
	var fragBuf []byte // reassembly buffer for fragmented commands
	var fragmenting bool
	for attempt := 0; attempt < 20; attempt++ {
		buf := make([]byte, 4096)
		tc.conn.SetReadDeadline(time.Now().Add(5 * time.Second))
		nRead, _, err := tc.conn.ReadFromUDP(buf)
		if err != nil {
			continue
		}

		mac, pID, pType, data, err := tsParseS2CPacket(buf[:nRead])
		if err != nil {
			continue
		}

		pktType := pType & 0x0f
		flags := pType & 0xf0
		if pktType == tsPktCommand {
			// Decrypt with fake key
			meta := buf[8:11] // S2C: bytes after MAC = PId(2) + PT(1)
			plaintext, err := tsEAXDecrypt(tsFakeKey[:], tsFakeNonce[:], meta, data, mac)
			if err != nil {
				continue
			}

			// ACK it
			ackData := make([]byte, 2)
			binary.BigEndian.PutUint16(ackData, pID)
			ackMeta := make([]byte, 5)
			binary.BigEndian.PutUint16(ackMeta[0:2], 0)
			binary.BigEndian.PutUint16(ackMeta[2:4], 0)
			ackMeta[4] = tsPktAck
			ackMAC, ackCipher := tsEAXEncrypt(tsFakeKey[:], tsFakeNonce[:], ackMeta, ackData)
			ackPkt := tsBuildC2SPacket(ackMAC, 0, 0, tsPktAck, ackCipher)
			tc.tsSendRaw(ackPkt)

			// Handle fragmentation
			isFragmented := flags&tsFlagFragmented != 0
			if isFragmented && !fragmenting {
				// First fragment — start reassembly
				fragmenting = true
				fragBuf = append([]byte{}, plaintext...)
				continue
			} else if fragmenting && !isFragmented {
				// Middle fragment — append
				fragBuf = append(fragBuf, plaintext...)
				continue
			} else if fragmenting && isFragmented {
				// Last fragment — complete
				fragBuf = append(fragBuf, plaintext...)
				plaintext = fragBuf
				fragmenting = false
			}
			// else: single unfragmented packet

			name, params := tsParseCommand(plaintext)
			initivCmd = tsIncomingCmd{name: name, params: params, raw: string(plaintext)}
			break
		} else if pktType == tsPktInit {
			if len(data) > 0 && data[0] == 127 {
				cancelRecv()
				return fmt.Errorf("%w: server sent step 127 after init4", ErrNetwork)
			}
		}
	}

	if initivCmd.name == "" {
		cancelRecv()
		return fmt.Errorf("%w: no initivexpand2 received", ErrNetwork)
	}

	if initivCmd.name != "initivexpand2" {
		cancelRecv()
		return fmt.Errorf("%w: expected initivexpand2, got %s", ErrNetwork, initivCmd.name)
	}

	// --- Parse initivexpand2 ---
	lB64 := initivCmd.params["l"]
	betaB64 := initivCmd.params["beta"]
	serverOmega := initivCmd.params["omega"]
	proofB64 := initivCmd.params["proof"]

	if lB64 == "" || betaB64 == "" || serverOmega == "" || proofB64 == "" {
		cancelRecv()
		return fmt.Errorf("%w: initivexpand2 missing params", ErrNetwork)
	}

	// Verify ot=1
	if initivCmd.params["ot"] != "1" {
		cancelRecv()
		return fmt.Errorf("%w: server outdated (no ot=1)", ErrNetwork)
	}

	licenseData, err := base64.StdEncoding.DecodeString(lB64)
	if err != nil {
		cancelRecv()
		return fmt.Errorf("license decode: %w", err)
	}
	betaBytes, err := base64.StdEncoding.DecodeString(betaB64)
	if err != nil {
		cancelRecv()
		return fmt.Errorf("beta decode: %w", err)
	}
	proofBytes, err := base64.StdEncoding.DecodeString(proofB64)
	if err != nil {
		cancelRecv()
		return fmt.Errorf("proof decode: %w", err)
	}

	if len(betaBytes) != 54 {
		cancelRecv()
		return fmt.Errorf("invalid beta length: %d", len(betaBytes))
	}

	// Verify proof: ECDSA verify of license data with server's P-256 key
	serverX, serverY, err := tsParseOmega(serverOmega)
	if err != nil {
		cancelRecv()
		return fmt.Errorf("parse server omega: %w", err)
	}
	if !tsVerifyP256(serverX, serverY, licenseData, proofBytes) {
		cancelRecv()
		return fmt.Errorf("%w: license proof verification failed", ErrAuth)
	}

	// Check for root key override
	rootKey := tsRootKey
	if rootB64 := initivCmd.params["root"]; rootB64 != "" {
		rootBytes, err := base64.StdEncoding.DecodeString(rootB64)
		if err == nil && len(rootBytes) == 32 {
			copy(rootKey[:], rootBytes)
		}
	}

	// Derive server ephemeral key from license chain
	serverEK, err := tsDeriveLicenseKey(licenseData, rootKey)
	if err != nil {
		cancelRecv()
		return fmt.Errorf("license key derivation: %w", err)
	}

	// Create our own ephemeral Ed25519 key
	var ekPrivBytes [32]byte
	rand.Read(ekPrivBytes[:])
	ekPrivScalar, err := new(edwards25519.Scalar).SetBytesWithClamping(ekPrivBytes[:])
	if err != nil {
		cancelRecv()
		return fmt.Errorf("ed25519 scalar: %w", err)
	}
	ekPub := new(edwards25519.Point).ScalarBaseMult(ekPrivScalar)

	// Compute shared IV and MAC
	var betaArr [54]byte
	copy(betaArr[:], betaBytes)
	sharedIV, sharedMAC := tsComputeSharedIVMAC(alpha, betaArr, ekPrivScalar, serverEK)
	tc.sharedIV = sharedIV
	tc.sharedMAC = sharedMAC
	tc.cryptoOK = true

	// clientinitiv was sent as part of Init4 as command pID=0.
	// So outgoing command counter starts at 1.
	tc.pktState[tsPktCommand].nextSendID = 1

	// --- Send clientek (fake-encrypted, pID=1) ---
	ekPubB64 := base64.StdEncoding.EncodeToString(ekPub.Bytes())

	// Proof: ECDSA sign(ek_pub || beta)
	proofData := make([]byte, 32+54)
	copy(proofData[:32], ekPub.Bytes())
	copy(proofData[32:], betaBytes)
	ekProof, err := tc.identity.tsSign(proofData)
	if err != nil {
		return fmt.Errorf("ek proof sign: %w", err)
	}
	ekProofB64 := base64.StdEncoding.EncodeToString(ekProof)

	// clientek must be fake-encrypted (FAKE_KEY/FAKE_NONCE), same as initivexpand2.
	// tsproto: "We fake encrypt the first command packet of the server (id 0) and the
	// first command packet of the client (id 1, clientek)."
	clientekStr := fmt.Sprintf("clientek ek=%s proof=%s", tsEscape(ekPubB64), tsEscape(ekProofB64))
	{
		cmdBytes := []byte(clientekStr)
		pID := tc.tsNextPktID(tsPktCommand) // should be 1
		flags := byte(tsPktCommand) | tsFlagNewprotocol
		meta := make([]byte, 5)
		binary.BigEndian.PutUint16(meta[0:2], pID)
		binary.BigEndian.PutUint16(meta[2:4], tc.clientID)
		meta[4] = flags
		mac, ciphertext := tsEAXEncrypt(tsFakeKey[:], tsFakeNonce[:], meta, cmdBytes)
		pkt := tsBuildC2SPacket(mac, pID, tc.clientID, flags, ciphertext)
		if err := tc.tsSendRaw(pkt); err != nil {
			return fmt.Errorf("clientek send: %w", err)
		}
	}

	// ACK pID counter also starts at 1 (first ACK was for initivexpand2)
	tc.pktState[tsPktAck].nextSendID = 1
	// Incoming command counter: initivexpand2 was pID=0, initserver starts at pID=2
	// (the server seems to reserve pID=1 or skip it in practice)
	tc.pktState[tsPktCommand].nextRecvID = 2
	// Incoming ACK counter: ACK for clientek will be pID=0
	tc.pktState[tsPktAck].nextRecvID = 0

	// Now start the receive loop for encrypted command exchange
	go tc.tsReceiveLoop(t.ctx)
	go tc.tsKeepaliveLoop(t.ctx)

	// --- Send clientinit (encrypted with shared key, pID=2) ---
	hwid := "123456789abcdef0123456789abcdef0"
	keyOffset := fmt.Sprintf("%d", tc.identity.keyOffset)
	clientinitCmd := fmt.Sprintf(
		"clientinit client_nickname=%s client_version=%s client_platform=%s client_input_hardware=1 client_output_hardware=1 client_default_channel= client_default_channel_password= client_server_password= client_meta_data= client_version_sign=%s client_key_offset=%s client_nickname_phonetic= client_default_token= hwid=%s",
		tsEscape(nickname),
		tsEscape(tsVersionStr),
		tsEscape(tsPlatform),
		tsEscape(tsVersionSign),
		tsEscape(keyOffset),
		tsEscape(hwid),
	)

	_, err = tc.tsSendCommand(clientinitCmd)
	if err != nil {
		return fmt.Errorf("clientinit send: %w", err)
	}

	// Wait for initserver (and process other commands that arrive during setup)
	initDeadline := time.After(10 * time.Second)
	var gotInitServer bool
	for !gotInitServer {
		select {
		case cmd := <-tc.cmdCh:
			if cmd.name == "initserver" {
				if cidStr := cmd.params["aclid"]; cidStr != "" {
					cid, _ := strconv.Atoi(cidStr)
					tc.clientID = uint16(cid)
					t.myClientID = cid
				}
				t.myName = nickname
				gotInitServer = true
			} else if cmd.name == "error" {
				errID, _ := strconv.Atoi(cmd.params["id"])
				if errID != 0 {
					return fmt.Errorf("%w: server error: %s (id=%d)", ErrAuth, cmd.params["msg"], errID)
				}
			} else {
				t.tsHandleServerCommand(cmd)
			}
		case <-initDeadline:
			return fmt.Errorf("%w: timeout waiting for initserver", ErrNetwork)
		case <-t.ctx.Done():
			return fmt.Errorf("%w: context cancelled", ErrNetwork)
		}
	}

	// Drain remaining setup commands (channellist, etc.) for a short period
	drainTimer := time.After(2 * time.Second)
drainLoop:
	for {
		select {
		case cmd := <-tc.cmdCh:
			if cmd.name == "error" {
				// Ignore error id=0 (OK response)
			} else {
				t.tsHandleServerCommand(cmd)
			}
			if cmd.name == "channellistfinished" {
				// All channels received, wait a bit more for remaining setup
				drainTimer = time.After(500 * time.Millisecond)
			}
		case <-drainTimer:
			break drainLoop
		}
	}

	return nil
}

// ──────────────────────────── Server Command Handler ────────────────────────────

func (t *TeamSpeakCore) tsHandleServerCommand(cmd tsIncomingCmd) {
	switch cmd.name {
	case "initserver":
		if v := cmd.params["virtualserver_name"]; v != "" {
			// Store server name etc
		}
	case "notifytextmessage":
		t.tsHandleTextMessage(cmd.params)
	case "notifycliententerview":
		t.tsHandleClientEnter(cmd.params)
	case "notifyclientleftview":
		t.tsHandleClientLeave(cmd.params)
	case "notifyclientmoved":
		t.tsHandleClientMoved(cmd.params)
	case "channellist":
		// Parse channel entries from |-separated list in raw data
		rawData := cmd.raw
		if idx := strings.Index(rawData, " "); idx >= 0 {
			rawData = rawData[idx+1:]
		}
		entries := tsParseKVList(rawData)
		t.channelsMu.Lock()
		for _, e := range entries {
			cid, _ := strconv.Atoi(e["cid"])
			pid, _ := strconv.Atoi(e["pid"])
			tc, _ := strconv.Atoi(e["total_clients"])
			order, _ := strconv.Atoi(e["channel_order"])
			ch := tsChannelInfo{
				cid:          cid,
				pid:          pid,
				name:         e["channel_name"],
				topic:        e["channel_topic"],
				totalClients: tc,
				order:        order,
			}
			t.channels[cid] = ch
		}
		t.channelsMu.Unlock()
	case "channellistfinished":
		// Done receiving channel list
	case "notifychannelcreated":
		cid, _ := strconv.Atoi(cmd.params["cid"])
		pid, _ := strconv.Atoi(cmd.params["cpid"])
		order, _ := strconv.Atoi(cmd.params["channel_order"])
		t.channelsMu.Lock()
		t.channels[cid] = tsChannelInfo{
			cid:   cid,
			pid:   pid,
			name:  cmd.params["channel_name"],
			topic: cmd.params["channel_topic"],
			order: order,
		}
		t.channelsMu.Unlock()
		t.tsDispatchUpdate(Update{
			Type:     UpdateGroupMembers,
			Platform: "teamspeak",
		})
	case "notifychanneldeleted":
		cid, _ := strconv.Atoi(cmd.params["cid"])
		t.channelsMu.Lock()
		delete(t.channels, cid)
		t.channelsMu.Unlock()
		t.tsDispatchUpdate(Update{
			Type:     UpdateGroupMembers,
			Platform: "teamspeak",
		})
	case "notifychanneledited", "notifychannelmoved":
		cid, _ := strconv.Atoi(cmd.params["cid"])
		t.channelsMu.Lock()
		if ch, ok := t.channels[cid]; ok {
			if v := cmd.params["channel_name"]; v != "" {
				ch.name = v
			}
			if v := cmd.params["channel_topic"]; v != "" {
				ch.topic = v
			}
			if v := cmd.params["cpid"]; v != "" {
				ch.pid, _ = strconv.Atoi(v)
			}
			if v := cmd.params["channel_order"]; v != "" {
				ch.order, _ = strconv.Atoi(v)
			}
			t.channels[cid] = ch
		}
		t.channelsMu.Unlock()
		t.tsDispatchUpdate(Update{
			Type:     UpdateGroupMembers,
			Platform: "teamspeak",
		})
	case "notifyclientupdated":
		clid, _ := strconv.Atoi(cmd.params["clid"])
		t.clientInfoMu.Lock()
		if info, ok := t.clientInfo[clid]; ok {
			if v := cmd.params["client_nickname"]; v != "" {
				info.nickname = v
			}
			t.clientInfo[clid] = info
		}
		t.clientInfoMu.Unlock()
	case "notifyclientpoke":
		invokerID, _ := strconv.Atoi(cmd.params["invokerid"])
		msg := Message{
			ID:         t.tsNextMsgID(),
			ChatID:     fmt.Sprintf("dm:%d", invokerID),
			SenderID:   strconv.Itoa(invokerID),
			SenderName: cmd.params["invokername"],
			Text:       "[poke] " + cmd.params["msg"],
			Timestamp:  time.Now(),
			Status:     MessageStatusDelivered,
			Platform:   "teamspeak",
		}
		t.tsAddMessage(msg.ChatID, &msg)
		t.tsDispatchUpdate(Update{
			Type:     UpdateNewMessage,
			ChatID:   msg.ChatID,
			Message:  &msg,
			Platform: "teamspeak",
		})
	case "notifyconnectioninforequest":
		// Server requests connection stats — auto-respond
		go t.SetConnectionInfo()
	case "notifychanneldescriptionchanged":
		// Channel description changed — could fetch new desc if needed
		t.tsDispatchUpdate(Update{
			Type:     UpdateGroupMembers,
			Platform: "teamspeak",
		})
	case "notifychannelpasswordchanged":
		// Channel password changed
	case "notifychannelsubscribed":
		// We subscribed to a channel — receive events from it now
		cid, _ := strconv.Atoi(cmd.params["cid"])
		t.tsDispatchUpdate(Update{
			Type:     UpdateGroupMembers,
			ChatID:   fmt.Sprintf("ch:%d", cid),
			Platform: "teamspeak",
		})
	case "notifychannelunsubscribed":
		// We unsubscribed from a channel
		cid, _ := strconv.Atoi(cmd.params["cid"])
		t.tsDispatchUpdate(Update{
			Type:     UpdateGroupMembers,
			ChatID:   fmt.Sprintf("ch:%d", cid),
			Platform: "teamspeak",
		})
	case "notifyserveredited", "notifyserverupdated":
		t.tsDispatchUpdate(Update{
			Type:     UpdateGroupMembers,
			Platform: "teamspeak",
		})
	case "notifyservergroupclientadded", "notifyservergroupclientdeleted":
		t.tsDispatchUpdate(Update{
			Type:     UpdateGroupMembers,
			Platform: "teamspeak",
		})
	case "notifytokenused":
		// Privilege key was used — informational
	case "notifyclientchannelgroupchanged":
		t.tsDispatchUpdate(Update{
			Type:     UpdateGroupMembers,
			Platform: "teamspeak",
		})
	case "notifyclientneededpermissions":
		// Server tells us what permissions we need — informational
	case "notifyclientchatcomposing":
		clid, _ := strconv.Atoi(cmd.params["clid"])
		t.tsDispatchUpdate(Update{
			Type:     UpdateTyping,
			ChatID:   fmt.Sprintf("dm:%d", clid),
			UserID:   strconv.Itoa(clid),
			Platform: "teamspeak",
		})
	case "notifyclientchatclosed":
		// The other client closed the chat window — informational
	case "notifyplugincommand":
		// Plugin command from another client
		invokerID, _ := strconv.Atoi(cmd.params["invokerid"])
		msg := Message{
			ID:         t.tsNextMsgID(),
			ChatID:     fmt.Sprintf("dm:%d", invokerID),
			SenderID:   strconv.Itoa(invokerID),
			SenderName: cmd.params["invokername"],
			Text:       "[plugin:" + cmd.params["name"] + "] " + cmd.params["data"],
			Timestamp:  time.Now(),
			Status:     MessageStatusDelivered,
			Platform:   "teamspeak",
		}
		t.tsAddMessage(msg.ChatID, &msg)
		t.tsDispatchUpdate(Update{
			Type:     UpdateNewMessage,
			ChatID:   msg.ChatID,
			Message:  &msg,
			Platform: "teamspeak",
		})
	}
}

// tsCommandLoop is the main loop processing incoming server commands after handshake.
func (t *TeamSpeakCore) tsCommandLoop() {
	tc := t.tsConn
	for {
		select {
		case <-t.ctx.Done():
			return
		case cmd := <-tc.cmdCh:
			tc.execMu.Lock()
			if tc.execWait {
				// Forward to tsExec's channel
				tc.execCh <- cmd
				tc.execMu.Unlock()
			} else {
				tc.execMu.Unlock()
				t.tsHandleServerCommand(cmd)
			}
		}
	}
}

// ──────────────────────────── Command Execution (send + wait for response) ────────────────────────────

// tsExec sends a command and waits for the response (error line).
func (t *TeamSpeakCore) tsExec(cmd string) ([]map[string]string, error) {
	tc := t.tsConn
	if tc == nil {
		return nil, ErrAuth
	}

	// Set up exec channel to capture responses
	tc.execMu.Lock()
	tc.execCh = make(chan tsIncomingCmd, 64)
	tc.execWait = true
	tc.execMu.Unlock()

	defer func() {
		tc.execMu.Lock()
		tc.execWait = false
		tc.execMu.Unlock()
	}()

	if _, err := tc.tsSendCommand(cmd); err != nil {
		return nil, err
	}
	// Wait for response — collect data until error command.
	// Some servers omit "error id=0 msg=ok" after successful responses,
	// so use short timeouts:
	// - 500ms after receiving data (assume complete)
	// - 2s with no response at all (void command success)
	deadline := time.After(2 * time.Second)
	var dataLines []string
	var dataTimeout <-chan time.Time
	for {
		select {
		case resp := <-tc.execCh:
			if resp.name == "error" {
				errID, _ := strconv.Atoi(resp.params["id"])
				if errID != 0 {
					return nil, tsMapError(&tsError{ID: errID, Msg: resp.params["msg"]})
				}
				var result []map[string]string
				for _, dl := range dataLines {
					result = append(result, tsParseKVList(dl)...)
				}
				return result, nil
			}
			// Notification or data line
			if strings.HasPrefix(resp.name, "notify") {
				go t.tsHandleServerCommand(resp)
			} else {
				dataLines = append(dataLines, resp.raw)
				// Start short timeout — if no "error id=0" follows, assume success
				dataTimeout = time.After(500 * time.Millisecond)
			}
		case <-dataTimeout:
			// Got data but no error terminator — server omitted it, treat as success
			var result []map[string]string
			for _, dl := range dataLines {
				result = append(result, tsParseKVList(dl)...)
			}
			return result, nil
		case <-deadline:
			// No error received within timeout — treat as success
			// (server may omit "error id=0 msg=ok" for successful commands)
			var result []map[string]string
			for _, dl := range dataLines {
				result = append(result, tsParseKVList(dl)...)
			}
			return result, nil
		case <-t.ctx.Done():
			return nil, fmt.Errorf("%w: context cancelled", ErrNetwork)
		}
	}
}

func (t *TeamSpeakCore) tsExecSimple(cmd string) error {
	_, err := t.tsExec(cmd)
	return err
}

// RawExec sends a raw TS3 command and returns the parsed key-value response rows.
func (t *TeamSpeakCore) RawExec(cmd string) ([]map[string]string, error) {
	return t.tsExec(cmd)
}

// ──────────────────────────── TS3 Error ────────────────────────────

type tsError struct {
	ID  int
	Msg string
}

func (e *tsError) Error() string {
	return fmt.Sprintf("ts3 error %d: %s", e.ID, e.Msg)
}

func tsMapError(e *tsError) error {
	switch {
	case e.ID == 0:
		return nil
	case e.ID == 256:
		return fmt.Errorf("%w: %s", ErrNotSupported, e.Msg)
	case e.ID == 512 || e.ID == 2568:
		return fmt.Errorf("%w: %s", ErrPermission, e.Msg)
	case e.ID == 1024 || e.ID == 1281:
		return fmt.Errorf("%w: %s", ErrNotFound, e.Msg)
	case e.ID == 2050:
		return fmt.Errorf("%w: file too large", ErrInvalidInput)
	case e.ID == 3329:
		return fmt.Errorf("%w: %s", ErrAlreadyExists, e.Msg)
	case e.ID == 3331:
		return fmt.Errorf("%w: rate limited", ErrRateLimit)
	default:
		return e
	}
}

// ──────────────────────────── Notification Handlers ────────────────────────────

func (t *TeamSpeakCore) tsHandleTextMessage(kv map[string]string) {
	targetMode, _ := strconv.Atoi(kv["targetmode"])
	invokerID, _ := strconv.Atoi(kv["invokerid"])

	var chatID string
	switch targetMode {
	case 1: // Private message
		chatID = fmt.Sprintf("dm:%d", invokerID)
	case 2: // Channel message
		chatID = fmt.Sprintf("ch:%d", t.myChannelID)
	case 3: // Server message
		chatID = "server"
	default:
		return
	}

	msg := Message{
		ID:         t.tsNextMsgID(),
		ChatID:     chatID,
		SenderID:   strconv.Itoa(invokerID),
		SenderName: kv["invokername"],
		Text:       kv["msg"],
		Timestamp:  time.Now(),
		Status:     MessageStatusDelivered,
		Platform:   "teamspeak",
	}
	t.tsAddMessage(chatID, &msg)

	t.tsDispatchUpdate(Update{
		Type:     UpdateNewMessage,
		ChatID:   chatID,
		Message:  &msg,
		Platform: "teamspeak",
	})
}

func (t *TeamSpeakCore) tsHandleClientEnter(kv map[string]string) {
	cid, _ := strconv.Atoi(kv["ctid"])
	clid, _ := strconv.Atoi(kv["clid"])
	dbid, _ := strconv.Atoi(kv["client_database_id"])

	info := tsClientInfo{
		clid:      clid,
		dbid:      dbid,
		uid:       kv["client_unique_identifier"],
		nickname:  kv["client_nickname"],
		channelID: cid,
		isQuery:   kv["client_type"] == "1",
	}

	t.clientInfoMu.Lock()
	t.clientInfo[clid] = info
	t.clientInfoMu.Unlock()

	t.tsDispatchUpdate(Update{
		Type:     UpdateGroupMembers,
		ChatID:   fmt.Sprintf("ch:%d", cid),
		UserID:   strconv.Itoa(dbid),
		Platform: "teamspeak",
	})
}

func (t *TeamSpeakCore) tsHandleClientLeave(kv map[string]string) {
	cid, _ := strconv.Atoi(kv["cfid"])
	clid, _ := strconv.Atoi(kv["clid"])

	t.clientInfoMu.Lock()
	delete(t.clientInfo, clid)
	t.clientInfoMu.Unlock()

	t.tsDispatchUpdate(Update{
		Type:     UpdateGroupMembers,
		ChatID:   fmt.Sprintf("ch:%d", cid),
		Platform: "teamspeak",
	})
}

func (t *TeamSpeakCore) tsHandleClientMoved(kv map[string]string) {
	cid, _ := strconv.Atoi(kv["ctid"])
	clid, _ := strconv.Atoi(kv["clid"])

	if clid == t.myClientID {
		t.myChannelID = cid
	}

	t.clientInfoMu.Lock()
	if info, ok := t.clientInfo[clid]; ok {
		info.channelID = cid
		t.clientInfo[clid] = info
	}
	t.clientInfoMu.Unlock()

	t.tsDispatchUpdate(Update{
		Type:     UpdateGroupMembers,
		ChatID:   fmt.Sprintf("ch:%d", cid),
		Platform: "teamspeak",
	})
}

// ──────────────────────────── Helpers ────────────────────────────

func (t *TeamSpeakCore) tsDispatchUpdate(u Update) {
	t.updateMu.RLock()
	defer t.updateMu.RUnlock()
	for _, h := range t.updateHandlers {
		go h(u)
	}
}

func (t *TeamSpeakCore) tsNextMsgID() string {
	return fmt.Sprintf("ts_%d", t.msgCounter.Add(1))
}

func (t *TeamSpeakCore) tsAddMessage(chatID string, msg *Message) {
	t.msgBufMu.Lock()
	defer t.msgBufMu.Unlock()
	buf := t.msgBuffer[chatID]
	buf = append(buf, *msg)
	if len(buf) > tsMaxMsgBuffer {
		buf = buf[len(buf)-tsMaxMsgBuffer:]
	}
	t.msgBuffer[chatID] = buf
}

func tsParseChatID(chatID string) (string, int, error) {
	if chatID == "server" {
		return "server", 0, nil
	}
	parts := strings.SplitN(chatID, ":", 2)
	if len(parts) != 2 {
		return "", 0, fmt.Errorf("%w: invalid chat ID %q", ErrInvalidInput, chatID)
	}
	id, err := strconv.Atoi(parts[1])
	if err != nil {
		return "", 0, fmt.Errorf("%w: invalid chat ID %q", ErrInvalidInput, chatID)
	}
	switch parts[0] {
	case "ch", "dm":
		return parts[0], id, nil
	default:
		return "", 0, fmt.Errorf("%w: unknown chat type %q", ErrInvalidInput, parts[0])
	}
}

// tsResolveClientID finds the current transient client ID for a target.
func (t *TeamSpeakCore) tsResolveClientID(dbid int) (int, error) {
	t.clientInfoMu.RLock()
	for _, info := range t.clientInfo {
		if info.dbid == dbid {
			t.clientInfoMu.RUnlock()
			return info.clid, nil
		}
	}
	t.clientInfoMu.RUnlock()

	// Refresh from server
	rows, err := t.tsExec("clientlist")
	if err != nil {
		return 0, err
	}

	t.clientInfoMu.Lock()
	for _, row := range rows {
		clid, _ := strconv.Atoi(row["clid"])
		db, _ := strconv.Atoi(row["client_database_id"])
		cid, _ := strconv.Atoi(row["cid"])
		t.clientInfo[clid] = tsClientInfo{
			clid:      clid,
			dbid:      db,
			uid:       row["client_unique_identifier"],
			nickname:  row["client_nickname"],
			channelID: cid,
			isQuery:   row["client_type"] == "1",
		}
	}
	t.clientInfoMu.Unlock()

	t.clientInfoMu.RLock()
	defer t.clientInfoMu.RUnlock()
	for _, info := range t.clientInfo {
		if info.dbid == dbid {
			return info.clid, nil
		}
	}
	return 0, fmt.Errorf("%w: client with dbid %d not online", ErrNotFound, dbid)
}

// ──────────────────────────── Session Persistence ────────────────────────────

func (t *TeamSpeakCore) tsSaveSession() error {
	sess := tsSession{
		ServerAddr: t.serverAddr,
		Nickname:   t.myName,
	}
	if t.tsConn != nil && t.tsConn.identity != nil {
		key := t.tsConn.identity.key
		sess.IdentityD = base64.StdEncoding.EncodeToString(key.D.Bytes())
		sess.IdentityX = base64.StdEncoding.EncodeToString(key.PublicKey.X.Bytes())
		sess.IdentityY = base64.StdEncoding.EncodeToString(key.PublicKey.Y.Bytes())
		sess.KeyOffset = t.tsConn.identity.keyOffset
	}
	data, err := json.MarshalIndent(sess, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(t.sessionPath, data, 0600)
}

func (t *TeamSpeakCore) tsLoadSession() (*tsSession, error) {
	data, err := os.ReadFile(t.sessionPath)
	if err != nil {
		return nil, err
	}
	var sess tsSession
	if err := json.Unmarshal(data, &sess); err != nil {
		return nil, err
	}
	return &sess, nil
}

func (t *TeamSpeakCore) tsLoadIdentity(sess *tsSession) error {
	if sess.IdentityD == "" {
		return nil
	}
	dBytes, err := base64.StdEncoding.DecodeString(sess.IdentityD)
	if err != nil {
		return err
	}
	key := new(ecdsa.PrivateKey)
	key.Curve = elliptic.P256()
	key.D = new(big.Int).SetBytes(dBytes)
	key.PublicKey.Curve = elliptic.P256()
	key.PublicKey.X, key.PublicKey.Y = elliptic.P256().ScalarBaseMult(dBytes)

	id := &tsP256Identity{key: key, keyOffset: sess.KeyOffset}
	if id.keyOffset == 0 {
		// Recompute hashcash if not stored in session
		id.keyOffset = tsHashCash(id.tsOmega(), 8)
	}
	t.tsConn.identity = id
	return nil
}

// ──────────────────────────── Core Interface: Auth ────────────────────────────

func (t *TeamSpeakCore) Authenticate(cfg AuthConfig) error {
	t.mu.Lock()
	defer t.mu.Unlock()

	if t.authed {
		return fmt.Errorf("%w: already authenticated", ErrAlreadyExists)
	}

	addr := cfg.Extra["server_address"]
	if addr == "" {
		addr = "localhost:" + tsVoicePort
	}

	nickname := cfg.Extra["nickname"]
	if nickname == "" {
		nickname = "UniClient"
	}

	// Connect UDP
	if err := t.tsConnect(addr); err != nil {
		return err
	}

	// Try loading saved identity
	if sess, err := t.tsLoadSession(); err == nil {
		if addr == "localhost:"+tsVoicePort && sess.ServerAddr != "" {
			addr = sess.ServerAddr
		}
		if nickname == "UniClient" && sess.Nickname != "" {
			nickname = sess.Nickname
		}
		t.tsLoadIdentity(sess)
	}

	t.serverAddr = addr
	t.nickname = nickname

	// Perform handshake
	if err := t.tsHandshake(nickname); err != nil {
		t.tsConn.conn.Close()
		t.tsConn = nil
		return err
	}

	t.authed = true

	// Start command processing loop first (needed for tsExec routing)
	go t.tsCommandLoop()

	// Register for notifications
	_ = t.tsExecSimple("servernotifyregister event=server")
	_ = t.tsExecSimple("servernotifyregister event=channel id=0")
	_ = t.tsExecSimple("servernotifyregister event=textserver")
	_ = t.tsExecSimple("servernotifyregister event=textchannel")
	_ = t.tsExecSimple("servernotifyregister event=textprivate")

	// Save session (with identity)
	_ = t.tsSaveSession()

	return nil
}

func (t *TeamSpeakCore) Logout() error {
	t.mu.Lock()
	defer t.mu.Unlock()

	if !t.authed {
		return nil
	}

	// Send disconnect
	if t.tsConn != nil {
		t.tsConn.tsSendCommand("clientdisconnect")
		time.Sleep(100 * time.Millisecond)
		t.tsConn.conn.Close()
		t.tsConn = nil
	}

	t.authed = false
	t.cancel()
	_ = os.Remove(t.sessionPath)
	return nil
}

// ──────────────────────────── Core Interface: Dialogs ────────────────────────────

func (t *TeamSpeakCore) GetDialogs(opts PaginationOpts) ([]Dialog, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}

	// Use cached channel data from handshake
	t.channelsMu.RLock()
	defer t.channelsMu.RUnlock()

	dialogs := make([]Dialog, 0, len(t.channels)+1)
	dialogs = append(dialogs, Dialog{
		ID:       "server",
		Type:     ChatTypeChannel,
		Title:    "Server Chat",
		Platform: "teamspeak",
	})

	for _, ch := range t.channels {
		d := Dialog{
			ID:          fmt.Sprintf("ch:%d", ch.cid),
			Type:        ChatTypeChannel,
			Title:       ch.name,
			MemberCount: ch.totalClients,
			Platform:    "teamspeak",
		}
		if ch.pid > 0 {
			d.ParentID = fmt.Sprintf("ch:%d", ch.pid)
		}

		t.msgBufMu.RLock()
		if msgs := t.msgBuffer[d.ID]; len(msgs) > 0 {
			last := msgs[len(msgs)-1]
			d.LastMessage = &last
		}
		t.msgBufMu.RUnlock()

		dialogs = append(dialogs, d)
	}

	// Add DM dialogs from message buffer
	t.msgBufMu.RLock()
	for chatID, msgs := range t.msgBuffer {
		if strings.HasPrefix(chatID, "dm:") && len(msgs) > 0 {
			last := msgs[len(msgs)-1]
			dialogs = append(dialogs, Dialog{
				ID:          chatID,
				Type:        ChatTypeDM,
				Title:       last.SenderName,
				LastMessage: &last,
				Platform:    "teamspeak",
			})
		}
	}
	t.msgBufMu.RUnlock()

	limit := opts.Limit
	if limit <= 0 {
		limit = 100
	}
	offset := 0
	if opts.Offset != "" {
		offset, _ = strconv.Atoi(opts.Offset)
	}
	if offset >= len(dialogs) {
		return []Dialog{}, nil
	}
	end := offset + limit
	if end > len(dialogs) {
		end = len(dialogs)
	}
	return dialogs[offset:end], nil
}

func (t *TeamSpeakCore) CreateGroup(name string, members []string) (*Dialog, error) {
	return t.CreateChannel(name, "")
}

func (t *TeamSpeakCore) CreateChannel(name string, description string) (*Dialog, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}

	cmd := fmt.Sprintf("channelcreate channel_name=%s", tsEscape(name))
	if description != "" {
		cmd += fmt.Sprintf(" channel_description=%s", tsEscape(description))
	}
	cmd += " channel_flag_semi_permanent=1"

	rows, err := t.tsExec(cmd)
	if err != nil {
		return nil, err
	}

	cid := "0"
	if len(rows) > 0 {
		cid = rows[0]["cid"]
	}

	return &Dialog{
		ID:       fmt.Sprintf("ch:%s", cid),
		Type:     ChatTypeChannel,
		Title:    name,
		Platform: "teamspeak",
	}, nil
}

func (t *TeamSpeakCore) CreateTopic(_ string, _ string) (*Dialog, error) {
	return nil, ErrNotSupported
}

func (t *TeamSpeakCore) GetFolders() ([]Folder, error) {
	return nil, ErrNotSupported
}

func (t *TeamSpeakCore) CreateFolder(_ string, _ []string) (*Folder, error) {
	return nil, ErrNotSupported
}

// ──────────────────────────── Core Interface: Messages ────────────────────────────

func (t *TeamSpeakCore) SendMessage(chatID string, msg OutgoingMessage) (*Message, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}

	kind, id, err := tsParseChatID(chatID)
	if err != nil {
		return nil, err
	}

	var cmd string
	switch kind {
	case "ch":
		cmd = fmt.Sprintf("sendtextmessage targetmode=2 target=%d msg=%s", id, tsEscape(msg.Text))
	case "dm":
		cmd = fmt.Sprintf("sendtextmessage targetmode=1 target=%d msg=%s", id, tsEscape(msg.Text))
	case "server":
		cmd = fmt.Sprintf("sendtextmessage targetmode=3 msg=%s", tsEscape(msg.Text))
	}

	if err := t.tsExecSimple(cmd); err != nil {
		return nil, err
	}

	m := &Message{
		ID:         t.tsNextMsgID(),
		ChatID:     chatID,
		SenderID:   strconv.Itoa(t.myClientID),
		SenderName: t.myName,
		Text:       msg.Text,
		Timestamp:  time.Now(),
		Status:     MessageStatusSent,
		Platform:   "teamspeak",
	}
	t.tsAddMessage(chatID, m)
	return m, nil
}

func (t *TeamSpeakCore) GetMessages(chatID string, opts PaginationOpts) ([]Message, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}

	t.msgBufMu.RLock()
	defer t.msgBufMu.RUnlock()

	msgs := t.msgBuffer[chatID]
	if len(msgs) == 0 {
		return []Message{}, nil
	}

	limit := opts.Limit
	if limit <= 0 {
		limit = 50
	}
	offset := 0
	if opts.Offset != "" {
		offset, _ = strconv.Atoi(opts.Offset)
	}

	result := make([]Message, 0, limit)
	start := len(msgs) - 1 - offset
	for i := start; i >= 0 && len(result) < limit; i-- {
		result = append(result, msgs[i])
	}
	return result, nil
}

func (t *TeamSpeakCore) EditMessage(_ string, _ string, _ string) (*Message, error) {
	return nil, ErrNotSupported
}

func (t *TeamSpeakCore) DeleteMessage(_ string, _ string) error {
	return ErrNotSupported
}

func (t *TeamSpeakCore) ReplyToMessage(chatID string, _ string, msg OutgoingMessage) (*Message, error) {
	return t.SendMessage(chatID, msg)
}

func (t *TeamSpeakCore) ForwardMessage(_ string, _ string, _ string) (*Message, error) {
	return nil, ErrNotSupported
}

func (t *TeamSpeakCore) ReactToMessage(_ string, _ string, _ string) error {
	return ErrNotSupported
}

func (t *TeamSpeakCore) PinMessage(_ string, _ string) error {
	return ErrNotSupported
}

func (t *TeamSpeakCore) UnpinMessage(_ string, _ string) error {
	return ErrNotSupported
}

// ──────────────────────────── Core Interface: Read State ────────────────────────────

func (t *TeamSpeakCore) MarkAsRead(_ string, _ string) error {
	return ErrNotSupported
}

func (t *TeamSpeakCore) GetReadState(_ string) (*ReadState, error) {
	return nil, ErrNotSupported
}

// ──────────────────────────── Core Interface: Files ────────────────────────────

func (t *TeamSpeakCore) UploadFile(chatID string, file FileUpload, progress func(sent, total int64)) (*Message, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}

	kind, id, err := tsParseChatID(chatID)
	if err != nil {
		return nil, err
	}
	if kind != "ch" {
		return nil, fmt.Errorf("%w: file upload only supported in channels", ErrNotSupported)
	}

	cmd := fmt.Sprintf("ftinitupload clientftfid=1 name=%s cid=%d cpw= size=%d overwrite=1 resume=0",
		tsEscape("/"+file.Name), id, file.Size)
	rows, err := t.tsExec(cmd)
	if err != nil {
		return nil, err
	}
	if len(rows) == 0 {
		return nil, fmt.Errorf("%w: empty upload init response", ErrNetwork)
	}

	ftkey := rows[0]["ftkey"]
	ftPort := rows[0]["port"]
	if ftPort == "" {
		ftPort = "30033"
	}

	host, _, _ := net.SplitHostPort(t.serverAddr)
	if host == "" {
		host = t.serverAddr
	}
	ftAddr := net.JoinHostPort(host, ftPort)
	ftConn, err := net.DialTimeout("tcp", ftAddr, tsDialTimeout)
	if err != nil {
		return nil, fmt.Errorf("%w: file transfer connect: %v", ErrNetwork, err)
	}
	defer ftConn.Close()

	if _, err := ftConn.Write([]byte(ftkey)); err != nil {
		return nil, fmt.Errorf("%w: ftkey send: %v", ErrNetwork, err)
	}

	var sent int64
	buf := make([]byte, 32*1024)
	for {
		n, readErr := file.Reader.Read(buf)
		if n > 0 {
			if _, writeErr := ftConn.Write(buf[:n]); writeErr != nil {
				return nil, fmt.Errorf("%w: upload: %v", ErrNetwork, writeErr)
			}
			sent += int64(n)
			if progress != nil {
				progress(sent, file.Size)
			}
		}
		if readErr != nil {
			break
		}
	}

	m := &Message{
		ID:         t.tsNextMsgID(),
		ChatID:     chatID,
		SenderID:   strconv.Itoa(t.myClientID),
		SenderName: t.myName,
		Text:       fmt.Sprintf("[File: %s]", file.Name),
		Timestamp:  time.Now(),
		Status:     MessageStatusSent,
		Platform:   "teamspeak",
		Attachments: []FileRef{{
			Name:     file.Name,
			MimeType: file.MimeType,
			Size:     file.Size,
		}},
	}
	t.tsAddMessage(chatID, m)
	return m, nil
}

func (t *TeamSpeakCore) DownloadFile(fileRef FileRef, dest string, progress func(recv, total int64)) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}

	parts := strings.SplitN(fileRef.ID, ":", 3)
	if len(parts) != 3 || parts[0] != "cid" {
		return fmt.Errorf("%w: invalid file ref ID %q", ErrInvalidInput, fileRef.ID)
	}
	channelID := parts[1]
	filePath := parts[2]

	cmd := fmt.Sprintf("ftinitdownload clientftfid=1 name=%s cid=%s cpw= seekpos=0",
		tsEscape(filePath), channelID)
	rows, err := t.tsExec(cmd)
	if err != nil {
		return err
	}
	if len(rows) == 0 {
		return fmt.Errorf("%w: empty download init response", ErrNetwork)
	}

	ftkey := rows[0]["ftkey"]
	ftPort := rows[0]["port"]
	fileSize, _ := strconv.ParseInt(rows[0]["size"], 10, 64)
	if ftPort == "" {
		ftPort = "30033"
	}

	host, _, _ := net.SplitHostPort(t.serverAddr)
	if host == "" {
		host = t.serverAddr
	}
	ftAddr := net.JoinHostPort(host, ftPort)
	ftConn, err := net.DialTimeout("tcp", ftAddr, tsDialTimeout)
	if err != nil {
		return fmt.Errorf("%w: file transfer connect: %v", ErrNetwork, err)
	}
	defer ftConn.Close()

	if _, err := ftConn.Write([]byte(ftkey)); err != nil {
		return fmt.Errorf("%w: ftkey send: %v", ErrNetwork, err)
	}

	f, err := os.Create(dest)
	if err != nil {
		return err
	}
	defer f.Close()

	var recv int64
	buf := make([]byte, 32*1024)
	for recv < fileSize {
		n, readErr := ftConn.Read(buf)
		if n > 0 {
			if _, writeErr := f.Write(buf[:n]); writeErr != nil {
				return writeErr
			}
			recv += int64(n)
			if progress != nil {
				progress(recv, fileSize)
			}
		}
		if readErr != nil {
			break
		}
	}
	return nil
}

// ──────────────────────────── Core Interface: Media / Calls / Misc ────────────────────────────

func (t *TeamSpeakCore) SendImageBase64(_ string, _ string, _ string) (*Message, error) {
	return nil, ErrNotSupported
}

func (t *TeamSpeakCore) StartCall(_ string, _ bool) (*CallSession, error) {
	return nil, ErrNotSupported
}

func (t *TeamSpeakCore) JoinGroupCall(_ string) (*CallSession, error) {
	return nil, ErrNotSupported
}

func (t *TeamSpeakCore) EndCall(_ string) error {
	return ErrNotSupported
}

func (t *TeamSpeakCore) SetCallMuted(_ string, _ bool) error {
	return ErrNotSupported
}

// ──────────────────────────── Core Interface: Profile ────────────────────────────

func (t *TeamSpeakCore) GetProfile(userID string) (*User, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}

	clid, err := strconv.Atoi(userID)
	if err != nil {
		return nil, fmt.Errorf("%w: invalid user ID", ErrInvalidInput)
	}

	rows, err := t.tsExec(fmt.Sprintf("clientinfo clid=%d", clid))
	if err != nil {
		return nil, err
	}
	if len(rows) == 0 {
		return nil, ErrNotFound
	}

	row := rows[0]
	user := &User{
		ID:          userID,
		Username:    row["client_unique_identifier"],
		DisplayName: row["client_nickname"],
		IsBot:       row["client_type"] == "1",
		IsOnline:    true,
		Platform:    "teamspeak",
	}

	if ts := row["client_lastconnected"]; ts != "" {
		if epoch, err := strconv.ParseInt(ts, 10, 64); err == nil {
			lastSeen := time.Unix(epoch, 0)
			user.LastSeen = &lastSeen
		}
	}

	return user, nil
}

// ──────────────────────────── Core Interface: Real-time ────────────────────────────

func (t *TeamSpeakCore) OnUpdate(handler func(Update)) {
	t.updateMu.Lock()
	defer t.updateMu.Unlock()
	t.updateHandlers = append(t.updateHandlers, handler)
}

func (t *TeamSpeakCore) Close() error {
	t.mu.Lock()
	defer t.mu.Unlock()

	t.cancel()
	if t.tsConn != nil {
		t.tsConn.tsSendCommand("clientdisconnect")
		time.Sleep(100 * time.Millisecond)
		t.tsConn.conn.Close()
		t.tsConn = nil
	}
	t.authed = false
	return nil
}

// ──────────────────────────── Core Interface: Chat Management ────────────────────────────

func (t *TeamSpeakCore) GetChatInfo(chatID string) (*Dialog, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}

	kind, id, err := tsParseChatID(chatID)
	if err != nil {
		return nil, err
	}

	if kind == "server" {
		return &Dialog{
			ID:       "server",
			Type:     ChatTypeChannel,
			Title:    "Server Chat",
			Platform: "teamspeak",
		}, nil
	}

	if kind == "dm" {
		return &Dialog{
			ID:       chatID,
			Type:     ChatTypeDM,
			Title:    fmt.Sprintf("DM %d", id),
			Platform: "teamspeak",
		}, nil
	}

	rows, err := t.tsExec(fmt.Sprintf("channelinfo cid=%d", id))
	if err != nil {
		return nil, err
	}
	if len(rows) == 0 {
		return nil, ErrNotFound
	}

	row := rows[0]
	pid, _ := strconv.Atoi(row["pid"])

	d := &Dialog{
		ID:       chatID,
		Type:     ChatTypeChannel,
		Title:    row["channel_name"],
		Platform: "teamspeak",
	}
	if pid > 0 {
		d.ParentID = fmt.Sprintf("ch:%d", pid)
	}
	return d, nil
}

func (t *TeamSpeakCore) EditChatTitle(chatID string, title string) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}

	kind, id, err := tsParseChatID(chatID)
	if err != nil {
		return err
	}
	if kind != "ch" {
		return ErrNotSupported
	}
	return t.tsExecSimple(fmt.Sprintf("channeledit cid=%d channel_name=%s", id, tsEscape(title)))
}

func (t *TeamSpeakCore) EditChatDescription(chatID string, description string) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}

	kind, id, err := tsParseChatID(chatID)
	if err != nil {
		return err
	}
	if kind != "ch" {
		return ErrNotSupported
	}
	return t.tsExecSimple(fmt.Sprintf("channeledit cid=%d channel_description=%s", id, tsEscape(description)))
}

func (t *TeamSpeakCore) LeaveChat(_ string) error {
	return ErrNotSupported
}

func (t *TeamSpeakCore) GetInviteLink(chatID string) (string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return "", ErrAuth
	}

	kind, id, err := tsParseChatID(chatID)
	if err != nil {
		return "", err
	}
	if kind != "ch" {
		return "", ErrNotSupported
	}

	cmd := fmt.Sprintf("privilegekeyadd tokentype=0 tokenid1=0 tokenid2=%d tokendescription=%s",
		id, tsEscape("UniClient invite"))
	rows, err := t.tsExec(cmd)
	if err != nil {
		return "", err
	}
	if len(rows) == 0 {
		return "", fmt.Errorf("%w: no token returned", ErrNetwork)
	}
	return rows[0]["token"], nil
}

// ──────────────────────────── Core Interface: Members ────────────────────────────

func (t *TeamSpeakCore) AddMembers(chatID string, userIDs []string) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}

	kind, id, err := tsParseChatID(chatID)
	if err != nil {
		return err
	}
	if kind != "ch" {
		return ErrNotSupported
	}

	for _, uid := range userIDs {
		clid, err := strconv.Atoi(uid)
		if err != nil {
			continue
		}
		if moveErr := t.tsExecSimple(fmt.Sprintf("clientmove clid=%d cid=%d", clid, id)); moveErr != nil {
			return moveErr
		}
	}
	return nil
}

func (t *TeamSpeakCore) RemoveMember(_ string, userID string) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}

	clid, err := strconv.Atoi(userID)
	if err != nil {
		return fmt.Errorf("%w: invalid user ID", ErrInvalidInput)
	}
	return t.tsExecSimple(fmt.Sprintf("clientkick clid=%d reasonid=4 reasonmsg=%s",
		clid, tsEscape("Removed")))
}

func (t *TeamSpeakCore) BanMember(_ string, userID string) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}

	clid, err := strconv.Atoi(userID)
	if err != nil {
		return fmt.Errorf("%w: invalid user ID", ErrInvalidInput)
	}
	return t.tsExecSimple(fmt.Sprintf("banclient clid=%d banreason=%s", clid, tsEscape("Banned")))
}

func (t *TeamSpeakCore) UnbanMember(_ string, userID string) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}

	banID, err := strconv.Atoi(userID)
	if err != nil {
		return fmt.Errorf("%w: invalid ban ID", ErrInvalidInput)
	}
	return t.tsExecSimple(fmt.Sprintf("bandel banid=%d", banID))
}

func (t *TeamSpeakCore) GetMembers(chatID string, opts PaginationOpts) ([]User, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}

	// Use cached client data from notifycliententerview events
	t.clientInfoMu.RLock()
	defer t.clientInfoMu.RUnlock()

	kind, id, _ := tsParseChatID(chatID)

	users := make([]User, 0)
	for _, ci := range t.clientInfo {
		if kind == "ch" && ci.channelID != id {
			continue
		}

		u := User{
			ID:          fmt.Sprintf("%d", ci.clid),
			Username:    ci.uid,
			DisplayName: ci.nickname,
			IsBot:       ci.isQuery,
			IsOnline:    true,
			Platform:    "teamspeak",
		}
		users = append(users, u)
	}

	limit := opts.Limit
	if limit <= 0 {
		limit = 100
	}
	offset := 0
	if opts.Offset != "" {
		offset, _ = strconv.Atoi(opts.Offset)
	}
	if offset >= len(users) {
		return []User{}, nil
	}
	end := offset + limit
	if end > len(users) {
		end = len(users)
	}
	return users[offset:end], nil
}

func (t *TeamSpeakCore) SetAdmin(chatID string, userID string, admin bool) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}

	dbid, err := strconv.Atoi(userID)
	if err != nil {
		return fmt.Errorf("%w: invalid user ID", ErrInvalidInput)
	}

	rows, err := t.tsExec("servergrouplist")
	if err != nil {
		return err
	}

	adminSGID := 0
	for _, row := range rows {
		name := row["name"]
		if strings.EqualFold(name, "Server Admin") || strings.EqualFold(name, "Admin") {
			adminSGID, _ = strconv.Atoi(row["sgid"])
			break
		}
	}
	if adminSGID == 0 {
		return fmt.Errorf("%w: could not find admin server group", ErrNotFound)
	}

	if admin {
		return t.tsExecSimple(fmt.Sprintf("servergroupaddclient sgid=%d cldbid=%d", adminSGID, dbid))
	}
	return t.tsExecSimple(fmt.Sprintf("servergroupdelclient sgid=%d cldbid=%d", adminSGID, dbid))
}

// ──────────────────────────── Core Interface: Contacts ────────────────────────────

func (t *TeamSpeakCore) GetContacts() ([]User, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}

	rows, err := t.tsExec("clientdblist")
	if err != nil {
		return nil, err
	}

	users := make([]User, 0, len(rows))
	for _, row := range rows {
		u := User{
			ID:          row["cldbid"],
			Username:    row["client_unique_identifier"],
			DisplayName: row["client_nickname"],
			Platform:    "teamspeak",
		}
		if ts := row["client_lastconnected"]; ts != "" {
			if epoch, err := strconv.ParseInt(ts, 10, 64); err == nil {
				lastSeen := time.Unix(epoch, 0)
				u.LastSeen = &lastSeen
			}
		}
		users = append(users, u)
	}
	return users, nil
}

func (t *TeamSpeakCore) AddContact(_ string, _ string, _ string) error {
	return ErrNotSupported
}

func (t *TeamSpeakCore) DeleteContact(_ string) error {
	return ErrNotSupported
}

func (t *TeamSpeakCore) BlockUser(userID string) error {
	return t.BanMember("", userID)
}

func (t *TeamSpeakCore) UnblockUser(userID string) error {
	return t.UnbanMember("", userID)
}

func (t *TeamSpeakCore) GetBlockedUsers() ([]User, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}

	rows, err := t.tsExec("banlist")
	if err != nil {
		if strings.Contains(err.Error(), "1281") {
			return []User{}, nil
		}
		return nil, err
	}

	users := make([]User, 0, len(rows))
	for _, row := range rows {
		u := User{
			ID:          row["banid"],
			Username:    row["uid"],
			DisplayName: row["name"],
			Platform:    "teamspeak",
		}
		users = append(users, u)
	}
	return users, nil
}

// ──────────────────────────── Core Interface: Search ────────────────────────────

func (t *TeamSpeakCore) SearchMessages(_ string, query string, opts PaginationOpts) ([]Message, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}

	t.msgBufMu.RLock()
	defer t.msgBufMu.RUnlock()

	queryLower := strings.ToLower(query)
	var results []Message
	for _, msgs := range t.msgBuffer {
		for _, msg := range msgs {
			if strings.Contains(strings.ToLower(msg.Text), queryLower) {
				results = append(results, msg)
			}
		}
	}

	limit := opts.Limit
	if limit <= 0 {
		limit = 50
	}
	if len(results) > limit {
		results = results[:limit]
	}
	return results, nil
}

func (t *TeamSpeakCore) SearchGlobal(query string, opts PaginationOpts) ([]Dialog, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}

	rows, err := t.tsExec("channellist")
	if err != nil {
		return nil, err
	}

	queryLower := strings.ToLower(query)
	var results []Dialog
	for _, row := range rows {
		name := row["channel_name"]
		if strings.Contains(strings.ToLower(name), queryLower) {
			results = append(results, Dialog{
				ID:       fmt.Sprintf("ch:%s", row["cid"]),
				Type:     ChatTypeChannel,
				Title:    name,
				Platform: "teamspeak",
			})
		}
	}

	limit := opts.Limit
	if limit <= 0 {
		limit = 50
	}
	if len(results) > limit {
		results = results[:limit]
	}
	return results, nil
}

// ──────────────────────────── Core Interface: Remaining Stubs ────────────────────────────

func (t *TeamSpeakCore) SendTyping(_ string) error {
	return ErrNotSupported
}

func (t *TeamSpeakCore) CreatePoll(_ string, _ string, _ []string) (*Message, error) {
	return nil, ErrNotSupported
}

func (t *TeamSpeakCore) VotePoll(_ string, _ string, _ int) error {
	return ErrNotSupported
}

func (t *TeamSpeakCore) SendSticker(_ string, _ string) (*Message, error) {
	return nil, ErrNotSupported
}

func (t *TeamSpeakCore) GetSessions() ([]Session, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}

	rows, err := t.tsExec("clientlist -uid -times -info")
	if err != nil {
		return nil, err
	}

	sessions := make([]Session, 0, len(rows))
	for _, row := range rows {
		clid, _ := strconv.Atoi(row["clid"])
		clientType, _ := strconv.Atoi(row["client_type"])

		platform := "voice"
		if clientType == 1 {
			platform = "serverquery"
		}

		s := Session{
			ID:       row["clid"],
			Device:   row["client_platform"],
			Platform: platform,
			AppName:  row["client_version"],
			IP:       row["connection_client_ip"],
		}

		if ts := row["client_lastconnected"]; ts != "" {
			if epoch, err := strconv.ParseInt(ts, 10, 64); err == nil {
				s.LastActive = time.Unix(epoch, 0)
			}
		}

		if clid == t.myClientID {
			s.IsCurrent = true
		}

		sessions = append(sessions, s)
	}
	return sessions, nil
}

func (t *TeamSpeakCore) TerminateSession(sessionID string) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}

	clid, err := strconv.Atoi(sessionID)
	if err != nil {
		return fmt.Errorf("%w: invalid session ID", ErrInvalidInput)
	}

	if clid == t.myClientID {
		return fmt.Errorf("%w: cannot terminate own session", ErrInvalidInput)
	}

	return t.tsExecSimple(fmt.Sprintf("clientkick clid=%d reasonid=5 reasonmsg=%s",
		clid, tsEscape("Session terminated")))
}

// ──────────────────────────── Client Self-Update (clientupdate) ────────────────────────────

func (t *TeamSpeakCore) tsClientUpdate(params string) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple("clientupdate " + params)
}

// ClientUpdate sends a clientupdate command with the given key=value pairs.
func (t *TeamSpeakCore) ClientUpdate(params map[string]string) error {
	parts := make([]string, 0, len(params))
	for k, v := range params {
		parts = append(parts, k+"="+tsEscape(v))
	}
	return t.tsClientUpdate(strings.Join(parts, " "))
}

func (t *TeamSpeakCore) SetNickname(nickname string) error {
	if err := t.tsClientUpdate(fmt.Sprintf("client_nickname=%s", tsEscape(nickname))); err != nil {
		return err
	}
	t.mu.Lock()
	t.myName = nickname
	t.nickname = nickname
	t.mu.Unlock()
	return nil
}

func (t *TeamSpeakCore) SetInputMuted(muted bool) error {
	v := "0"
	if muted {
		v = "1"
	}
	return t.tsClientUpdate("client_input_muted=" + v)
}

func (t *TeamSpeakCore) SetOutputMuted(muted bool) error {
	v := "0"
	if muted {
		v = "1"
	}
	return t.tsClientUpdate("client_output_muted=" + v)
}

func (t *TeamSpeakCore) SetInputHardware(enabled bool) error {
	v := "0"
	if enabled {
		v = "1"
	}
	return t.tsClientUpdate("client_input_hardware=" + v)
}

func (t *TeamSpeakCore) SetOutputHardware(enabled bool) error {
	v := "0"
	if enabled {
		v = "1"
	}
	return t.tsClientUpdate("client_output_hardware=" + v)
}

func (t *TeamSpeakCore) SetChannelCommander(enabled bool) error {
	v := "0"
	if enabled {
		v = "1"
	}
	return t.tsClientUpdate("client_is_channel_commander=" + v)
}

func (t *TeamSpeakCore) SetRecording(enabled bool) error {
	v := "0"
	if enabled {
		v = "1"
	}
	return t.tsClientUpdate("client_is_recording=" + v)
}

func (t *TeamSpeakCore) SetAway(away bool, message string) error {
	cmd := fmt.Sprintf("client_away=%d", 0)
	if away {
		cmd = fmt.Sprintf("client_away=1 client_away_message=%s", tsEscape(message))
	}
	return t.tsClientUpdate(cmd)
}

func (t *TeamSpeakCore) SetDescription(description string) error {
	return t.tsClientUpdate(fmt.Sprintf("client_description=%s", tsEscape(description)))
}

func (t *TeamSpeakCore) SetAvatar(md5Hex string) error {
	return t.tsClientUpdate(fmt.Sprintf("client_flag_avatar=%s", md5Hex))
}

func (t *TeamSpeakCore) RequestTalkPower(message string) error {
	return t.tsClientUpdate(fmt.Sprintf("client_talk_request=1 client_talk_request_msg=%s", tsEscape(message)))
}

func (t *TeamSpeakCore) CancelTalkPowerRequest() error {
	return t.tsClientUpdate("client_talk_request=0")
}

func (t *TeamSpeakCore) SetBadges(badges string) error {
	return t.tsClientUpdate(fmt.Sprintf("client_badges=%s", tsEscape(badges)))
}

func (t *TeamSpeakCore) SetMetaData(metadata string) error {
	return t.tsClientUpdate(fmt.Sprintf("client_meta_data=%s", tsEscape(metadata)))
}

func (t *TeamSpeakCore) SetPhoneticNickname(name string) error {
	return t.tsClientUpdate(fmt.Sprintf("client_nickname_phonetic=%s", tsEscape(name)))
}

// ──────────────────────────── Channel Management ────────────────────────────

func (t *TeamSpeakCore) CreateChannelFull(name string, opts map[string]string) (int, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return 0, ErrAuth
	}

	cmd := fmt.Sprintf("channelcreate channel_name=%s", tsEscape(name))
	for k, v := range opts {
		cmd += fmt.Sprintf(" %s=%s", k, tsEscape(v))
	}

	rows, err := t.tsExec(cmd)
	if err != nil {
		return 0, err
	}
	cid := 0
	if len(rows) > 0 {
		cid, _ = strconv.Atoi(rows[0]["cid"])
	}
	return cid, nil
}

func (t *TeamSpeakCore) EditChannel(cid int, props map[string]string) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	cmd := fmt.Sprintf("channeledit cid=%d", cid)
	for k, v := range props {
		cmd += fmt.Sprintf(" %s=%s", k, tsEscape(v))
	}
	return t.tsExecSimple(cmd)
}

func (t *TeamSpeakCore) DeleteChannel(cid int, force bool) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	f := 0
	if force {
		f = 1
	}
	return t.tsExecSimple(fmt.Sprintf("channeldelete cid=%d force=%d", cid, f))
}

func (t *TeamSpeakCore) MoveChannel(cid, newParent, order int) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple(fmt.Sprintf("channelmove cid=%d cpid=%d order=%d", cid, newParent, order))
}

func (t *TeamSpeakCore) FindChannel(pattern string) ([]map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	return t.tsExec(fmt.Sprintf("channelfind pattern=%s", tsEscape(pattern)))
}

func (t *TeamSpeakCore) GetChannelDescription(cid int) (string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return "", ErrAuth
	}
	rows, err := t.tsExec(fmt.Sprintf("channelgetdescription cid=%d", cid))
	if err != nil {
		return "", err
	}
	if len(rows) > 0 {
		return rows[0]["channel_description"], nil
	}
	return "", nil
}

func (t *TeamSpeakCore) SubscribeChannel(cids ...int) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	parts := make([]string, len(cids))
	for i, cid := range cids {
		parts[i] = fmt.Sprintf("cid=%d", cid)
	}
	return t.tsExecSimple("channelsubscribe " + strings.Join(parts, "|"))
}

func (t *TeamSpeakCore) SubscribeAllChannels() error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple("channelsubscribeall")
}

func (t *TeamSpeakCore) UnsubscribeChannel(cids ...int) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	parts := make([]string, len(cids))
	for i, cid := range cids {
		parts[i] = fmt.Sprintf("cid=%d", cid)
	}
	return t.tsExecSimple("channelunsubscribe " + strings.Join(parts, "|"))
}

func (t *TeamSpeakCore) UnsubscribeAllChannels() error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple("channelunsubscribeall")
}

// ──────────────────────────── Channel Permissions ────────────────────────────

func (t *TeamSpeakCore) ChannelAddPerm(cid int, permID int, permValue int) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple(fmt.Sprintf("channeladdperm cid=%d permid=%d permvalue=%d", cid, permID, permValue))
}

func (t *TeamSpeakCore) ChannelDelPerm(cid int, permID int) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple(fmt.Sprintf("channeldelperm cid=%d permid=%d", cid, permID))
}

func (t *TeamSpeakCore) ChannelPermList(cid int) ([]map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	return t.tsExec(fmt.Sprintf("channelpermlist cid=%d", cid))
}

func (t *TeamSpeakCore) ChannelClientAddPerm(cid, cldbid, permID, permValue int) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple(fmt.Sprintf("channelclientaddperm cid=%d cldbid=%d permid=%d permvalue=%d", cid, cldbid, permID, permValue))
}

func (t *TeamSpeakCore) ChannelClientDelPerm(cid, cldbid, permID int) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple(fmt.Sprintf("channelclientdelperm cid=%d cldbid=%d permid=%d", cid, cldbid, permID))
}

func (t *TeamSpeakCore) ChannelClientPermList(cid, cldbid int) ([]map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	return t.tsExec(fmt.Sprintf("channelclientpermlist cid=%d cldbid=%d", cid, cldbid))
}

// ──────────────────────────── Server Group Commands ────────────────────────────

func (t *TeamSpeakCore) ServerGroupAdd(name string) (int, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return 0, ErrAuth
	}
	rows, err := t.tsExec(fmt.Sprintf("servergroupadd name=%s", tsEscape(name)))
	if err != nil {
		return 0, err
	}
	sgid := 0
	if len(rows) > 0 {
		sgid, _ = strconv.Atoi(rows[0]["sgid"])
	}
	return sgid, nil
}

func (t *TeamSpeakCore) ServerGroupDel(sgid int, force bool) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	f := 0
	if force {
		f = 1
	}
	return t.tsExecSimple(fmt.Sprintf("servergroupdel sgid=%d force=%d", sgid, f))
}

func (t *TeamSpeakCore) ServerGroupClientList(sgid int) ([]map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	return t.tsExec(fmt.Sprintf("servergroupclientlist sgid=%d", sgid))
}

func (t *TeamSpeakCore) ServerGroupPermList(sgid int) ([]map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	return t.tsExec(fmt.Sprintf("servergrouppermlist sgid=%d", sgid))
}

func (t *TeamSpeakCore) ServerGroupAddPerm(sgid, permID, permValue int) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple(fmt.Sprintf("servergroupaddperm sgid=%d permid=%d permvalue=%d permnegated=0 permskip=0", sgid, permID, permValue))
}

func (t *TeamSpeakCore) ServerGroupDelPerm(sgid, permID int) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple(fmt.Sprintf("servergroupdelperm sgid=%d permid=%d", sgid, permID))
}

func (t *TeamSpeakCore) ServerGroupCopy(sourceSGID int, name string, targetType int) (int, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return 0, ErrAuth
	}
	rows, err := t.tsExec(fmt.Sprintf("servergroupcopy ssgid=%d tsgid=0 name=%s type=%d", sourceSGID, tsEscape(name), targetType))
	if err != nil {
		return 0, err
	}
	sgid := 0
	if len(rows) > 0 {
		sgid, _ = strconv.Atoi(rows[0]["sgid"])
	}
	return sgid, nil
}

func (t *TeamSpeakCore) ServerGroupRename(sgid int, name string) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple(fmt.Sprintf("servergrouprename sgid=%d name=%s", sgid, tsEscape(name)))
}

func (t *TeamSpeakCore) ServerGroupsByClientID(cldbid int) ([]map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	return t.tsExec(fmt.Sprintf("servergroupsbyclientid cldbid=%d", cldbid))
}

func (t *TeamSpeakCore) ServerGroupAutoAddPerm(sgtype int, permID, permValue int, permNegated, permSkip bool) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	n, s := 0, 0
	if permNegated {
		n = 1
	}
	if permSkip {
		s = 1
	}
	return t.tsExecSimple(fmt.Sprintf("servergroupautoaddperm sgtype=%d permid=%d permvalue=%d permnegated=%d permskip=%d",
		sgtype, permID, permValue, n, s))
}

func (t *TeamSpeakCore) ServerGroupAutoDelPerm(sgtype int, permID int) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple(fmt.Sprintf("servergroupautodelperm sgtype=%d permid=%d", sgtype, permID))
}

// ──────────────────────────── Channel Group Commands ────────────────────────────

func (t *TeamSpeakCore) ChannelGroupList() ([]map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	return t.tsExec("channelgrouplist")
}

func (t *TeamSpeakCore) ChannelGroupAdd(name string) (int, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return 0, ErrAuth
	}
	rows, err := t.tsExec(fmt.Sprintf("channelgroupadd name=%s", tsEscape(name)))
	if err != nil {
		return 0, err
	}
	cgid := 0
	if len(rows) > 0 {
		cgid, _ = strconv.Atoi(rows[0]["cgid"])
	}
	return cgid, nil
}

func (t *TeamSpeakCore) ChannelGroupDel(cgid int, force bool) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	f := 0
	if force {
		f = 1
	}
	return t.tsExecSimple(fmt.Sprintf("channelgroupdel cgid=%d force=%d", cgid, f))
}

func (t *TeamSpeakCore) ChannelGroupClientList(cgid, cid int) ([]map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	return t.tsExec(fmt.Sprintf("channelgroupclientlist cgid=%d cid=%d", cgid, cid))
}

func (t *TeamSpeakCore) ChannelGroupPermList(cgid int) ([]map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	return t.tsExec(fmt.Sprintf("channelgrouppermlist cgid=%d", cgid))
}

func (t *TeamSpeakCore) ChannelGroupAddPerm(cgid, permID, permValue int) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple(fmt.Sprintf("channelgroupaddperm cgid=%d permid=%d permvalue=%d permnegated=0 permskip=0", cgid, permID, permValue))
}

func (t *TeamSpeakCore) ChannelGroupDelPerm(cgid, permID int) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple(fmt.Sprintf("channelgroupdelperm cgid=%d permid=%d", cgid, permID))
}

func (t *TeamSpeakCore) ChannelGroupCopy(sourceCGID int, name string, targetType int) (int, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return 0, ErrAuth
	}
	rows, err := t.tsExec(fmt.Sprintf("channelgroupcopy scgid=%d tcgid=0 name=%s type=%d", sourceCGID, tsEscape(name), targetType))
	if err != nil {
		return 0, err
	}
	cgid := 0
	if len(rows) > 0 {
		cgid, _ = strconv.Atoi(rows[0]["cgid"])
	}
	return cgid, nil
}

func (t *TeamSpeakCore) ChannelGroupRename(cgid int, name string) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple(fmt.Sprintf("channelgrouprename cgid=%d name=%s", cgid, tsEscape(name)))
}

func (t *TeamSpeakCore) SetClientChannelGroup(cgid, cid, cldbid int) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple(fmt.Sprintf("setclientchannelgroup cgid=%d cid=%d cldbid=%d", cgid, cid, cldbid))
}

// ──────────────────────────── Client Lookup Commands ────────────────────────────

func (t *TeamSpeakCore) ClientDBInfo(cldbid int) (map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	rows, err := t.tsExec(fmt.Sprintf("clientdbinfo cldbid=%d", cldbid))
	if err != nil {
		return nil, err
	}
	if len(rows) == 0 {
		return nil, ErrNotFound
	}
	return rows[0], nil
}

func (t *TeamSpeakCore) ClientDBEdit(cldbid int, props map[string]string) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	cmd := fmt.Sprintf("clientdbedit cldbid=%d", cldbid)
	for k, v := range props {
		cmd += fmt.Sprintf(" %s=%s", k, tsEscape(v))
	}
	return t.tsExecSimple(cmd)
}

func (t *TeamSpeakCore) ClientDBDelete(cldbid int) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple(fmt.Sprintf("clientdbdelete cldbid=%d", cldbid))
}

func (t *TeamSpeakCore) ClientDBFind(pattern string, isUID bool) ([]map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	cmd := fmt.Sprintf("clientdbfind pattern=%s", tsEscape(pattern))
	if isUID {
		cmd += " -uid"
	}
	return t.tsExec(cmd)
}

func (t *TeamSpeakCore) ClientFind(pattern string) ([]map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	return t.tsExec(fmt.Sprintf("clientfind pattern=%s", tsEscape(pattern)))
}

func (t *TeamSpeakCore) ClientGetDBIDFromUID(cluid string) (int, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return 0, ErrAuth
	}
	rows, err := t.tsExec(fmt.Sprintf("clientgetdbidfromuid cluid=%s", tsEscape(cluid)))
	if err != nil {
		return 0, err
	}
	if len(rows) == 0 {
		return 0, ErrNotFound
	}
	cldbid, _ := strconv.Atoi(rows[0]["cldbid"])
	return cldbid, nil
}

func (t *TeamSpeakCore) ClientGetIDs(cluid string) ([]map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	return t.tsExec(fmt.Sprintf("clientgetids cluid=%s", tsEscape(cluid)))
}

func (t *TeamSpeakCore) ClientGetNameFromUID(cluid string) (string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return "", ErrAuth
	}
	rows, err := t.tsExec(fmt.Sprintf("clientgetnamefromuid cluid=%s", tsEscape(cluid)))
	if err != nil {
		return "", err
	}
	if len(rows) == 0 {
		return "", ErrNotFound
	}
	return rows[0]["name"], nil
}

func (t *TeamSpeakCore) ClientGetNameFromDBID(cldbid int) (string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return "", ErrAuth
	}
	rows, err := t.tsExec(fmt.Sprintf("clientgetnamefromdbid cldbid=%d", cldbid))
	if err != nil {
		return "", err
	}
	if len(rows) == 0 {
		return "", ErrNotFound
	}
	return rows[0]["name"], nil
}

func (t *TeamSpeakCore) ClientGetUIDFromCLID(clid int) (string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return "", ErrAuth
	}
	rows, err := t.tsExec(fmt.Sprintf("clientgetuidfromclid clid=%d", clid))
	if err != nil {
		return "", err
	}
	if len(rows) == 0 {
		return "", ErrNotFound
	}
	return rows[0]["cluid"], nil
}

func (t *TeamSpeakCore) ClientEdit(clid int, props map[string]string) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	cmd := fmt.Sprintf("clientedit clid=%d", clid)
	for k, v := range props {
		cmd += fmt.Sprintf(" %s=%s", k, tsEscape(v))
	}
	return t.tsExecSimple(cmd)
}

func (t *TeamSpeakCore) ClientAddPerm(cldbid, permID, permValue int) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple(fmt.Sprintf("clientaddperm cldbid=%d permid=%d permvalue=%d permnegated=0 permskip=0", cldbid, permID, permValue))
}

func (t *TeamSpeakCore) ClientDelPerm(cldbid, permID int) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple(fmt.Sprintf("clientdelperm cldbid=%d permid=%d", cldbid, permID))
}

func (t *TeamSpeakCore) ClientPermList(cldbid int) ([]map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	return t.tsExec(fmt.Sprintf("clientpermlist cldbid=%d", cldbid))
}

func (t *TeamSpeakCore) ClientPoke(clid int, message string) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple(fmt.Sprintf("clientpoke clid=%d msg=%s", clid, tsEscape(message)))
}

func (t *TeamSpeakCore) ClientChatClosed(clid int) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple(fmt.Sprintf("clientchatclosed clid=%d", clid))
}

func (t *TeamSpeakCore) JoinChannel(cid int, password string) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	cmd := fmt.Sprintf("clientmove clid=%d cid=%d", t.myClientID, cid)
	if password != "" {
		cmd += fmt.Sprintf(" cpw=%s", tsEscape(password))
	}
	return t.tsExecSimple(cmd)
}

// ──────────────────────────── Ban Management (extended) ────────────────────────────

func (t *TeamSpeakCore) BanAdd(ip, name, uid string, timeSeconds int, reason string) (int, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return 0, ErrAuth
	}
	cmd := "banadd"
	if ip != "" {
		cmd += fmt.Sprintf(" ip=%s", tsEscape(ip))
	}
	if name != "" {
		cmd += fmt.Sprintf(" name=%s", tsEscape(name))
	}
	if uid != "" {
		cmd += fmt.Sprintf(" uid=%s", tsEscape(uid))
	}
	if timeSeconds > 0 {
		cmd += fmt.Sprintf(" time=%d", timeSeconds)
	}
	if reason != "" {
		cmd += fmt.Sprintf(" banreason=%s", tsEscape(reason))
	}
	rows, err := t.tsExec(cmd)
	if err != nil {
		return 0, err
	}
	banID := 0
	if len(rows) > 0 {
		banID, _ = strconv.Atoi(rows[0]["banid"])
	}
	return banID, nil
}

func (t *TeamSpeakCore) BanDelAll() error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple("bandelall")
}

// ──────────────────────────── Offline Messages ────────────────────────────

func (t *TeamSpeakCore) MessageAdd(cluid, subject, message string) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple(fmt.Sprintf("messageadd cluid=%s subject=%s message=%s",
		tsEscape(cluid), tsEscape(subject), tsEscape(message)))
}

func (t *TeamSpeakCore) MessageDel(msgID int) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple(fmt.Sprintf("messagedel msgid=%d", msgID))
}

func (t *TeamSpeakCore) MessageGet(msgID int) (map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	rows, err := t.tsExec(fmt.Sprintf("messageget msgid=%d", msgID))
	if err != nil {
		return nil, err
	}
	if len(rows) == 0 {
		return nil, ErrNotFound
	}
	return rows[0], nil
}

func (t *TeamSpeakCore) MessageList() ([]map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	return t.tsExec("messagelist")
}

func (t *TeamSpeakCore) MessageUpdateFlag(msgID int, read bool) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	flag := 0
	if read {
		flag = 1
	}
	return t.tsExecSimple(fmt.Sprintf("messageupdateflag msgid=%d flag=%d", msgID, flag))
}

// ──────────────────────────── Complaints ────────────────────────────

func (t *TeamSpeakCore) ComplainAdd(tcldbid int, message string) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple(fmt.Sprintf("complainadd tcldbid=%d message=%s", tcldbid, tsEscape(message)))
}

func (t *TeamSpeakCore) ComplainDel(tcldbid, fcldbid int) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple(fmt.Sprintf("complaindel tcldbid=%d fcldbid=%d", tcldbid, fcldbid))
}

func (t *TeamSpeakCore) ComplainDelAll(tcldbid int) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple(fmt.Sprintf("complaindelall tcldbid=%d", tcldbid))
}

func (t *TeamSpeakCore) ComplainList(tcldbid int) ([]map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	return t.tsExec(fmt.Sprintf("complainlist tcldbid=%d", tcldbid))
}

// ──────────────────────────── Privilege Keys (Tokens) ────────────────────────────

func (t *TeamSpeakCore) PrivilegeKeyAdd(tokenType, tokenID1, tokenID2 int) (string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return "", ErrAuth
	}
	rows, err := t.tsExec(fmt.Sprintf("privilegekeyadd tokentype=%d tokenid1=%d tokenid2=%d", tokenType, tokenID1, tokenID2))
	if err != nil {
		return "", err
	}
	if len(rows) > 0 {
		return rows[0]["token"], nil
	}
	return "", nil
}

func (t *TeamSpeakCore) PrivilegeKeyDelete(token string) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple(fmt.Sprintf("privilegekeydelete token=%s", tsEscape(token)))
}

func (t *TeamSpeakCore) PrivilegeKeyList() ([]map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	return t.tsExec("privilegekeylist")
}

func (t *TeamSpeakCore) PrivilegeKeyUse(token string) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple(fmt.Sprintf("privilegekeyuse token=%s", tsEscape(token)))
}

// ──────────────────────────── Server Info ────────────────────────────

func (t *TeamSpeakCore) ServerInfo() (map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	rows, err := t.tsExec("serverinfo")
	if err != nil {
		return nil, err
	}
	if len(rows) == 0 {
		return nil, ErrNotFound
	}
	return rows[0], nil
}

func (t *TeamSpeakCore) ServerEdit(props map[string]string) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	cmd := "serveredit"
	for k, v := range props {
		cmd += fmt.Sprintf(" %s=%s", k, tsEscape(v))
	}
	return t.tsExecSimple(cmd)
}

func (t *TeamSpeakCore) ServerVersion() (map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	rows, err := t.tsExec("version")
	if err != nil {
		return nil, err
	}
	if len(rows) == 0 {
		return nil, ErrNotFound
	}
	return rows[0], nil
}

func (t *TeamSpeakCore) WhoAmI() (map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	rows, err := t.tsExec("whoami")
	if err != nil {
		return nil, err
	}
	if len(rows) == 0 {
		return nil, ErrNotFound
	}
	return rows[0], nil
}

func (t *TeamSpeakCore) GetConnectionInfo(clid int) (map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	rows, err := t.tsExec(fmt.Sprintf("getconnectioninfo clid=%d", clid))
	if err != nil {
		return nil, err
	}
	if len(rows) == 0 {
		return nil, ErrNotFound
	}
	return rows[0], nil
}

// ──────────────────────────── Permission System ────────────────────────────

func (t *TeamSpeakCore) PermissionList() ([]map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	return t.tsExec("permissionlist")
}

func (t *TeamSpeakCore) PermFind(permID int) ([]map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	return t.tsExec(fmt.Sprintf("permfind permid=%d", permID))
}

func (t *TeamSpeakCore) PermGet(permID int) (map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	rows, err := t.tsExec(fmt.Sprintf("permget permid=%d", permID))
	if err != nil {
		return nil, err
	}
	if len(rows) == 0 {
		return nil, ErrNotFound
	}
	return rows[0], nil
}

func (t *TeamSpeakCore) PermOverview(cid, cldbid int) ([]map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	return t.tsExec(fmt.Sprintf("permoverview cid=%d cldbid=%d", cid, cldbid))
}

func (t *TeamSpeakCore) PermIDGetByName(permsid string) (int, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return 0, ErrAuth
	}
	rows, err := t.tsExec(fmt.Sprintf("permidgetbyname permsid=%s", tsEscape(permsid)))
	if err != nil {
		return 0, err
	}
	if len(rows) == 0 {
		return 0, ErrNotFound
	}
	pid, _ := strconv.Atoi(rows[0]["permid"])
	return pid, nil
}

func (t *TeamSpeakCore) PermReset() error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple("permreset")
}

// ──────────────────────────── Custom Properties ────────────────────────────

func (t *TeamSpeakCore) CustomInfo(cldbid int) ([]map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	return t.tsExec(fmt.Sprintf("custominfo cldbid=%d", cldbid))
}

func (t *TeamSpeakCore) CustomSearch(ident, pattern string) ([]map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	return t.tsExec(fmt.Sprintf("customsearch ident=%s pattern=%s", tsEscape(ident), tsEscape(pattern)))
}

func (t *TeamSpeakCore) CustomSet(cldbid int, ident, value string) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple(fmt.Sprintf("customset cldbid=%d ident=%s value=%s", cldbid, tsEscape(ident), tsEscape(value)))
}

func (t *TeamSpeakCore) CustomDelete(cldbid int, ident string) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple(fmt.Sprintf("customdelete cldbid=%d ident=%s", cldbid, tsEscape(ident)))
}

// ──────────────────────────── Plugin Commands ────────────────────────────

func (t *TeamSpeakCore) SendPluginCommand(name, data string, targetMode int) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple(fmt.Sprintf("plugincmd name=%s data=%s targetmode=%d",
		tsEscape(name), tsEscape(data), targetMode))
}

// ──────────────────────────── File Transfer Management ────────────────────────────

func (t *TeamSpeakCore) FTGetFileList(cid int, path, channelPassword string) ([]map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	return t.tsExec(fmt.Sprintf("ftgetfilelist cid=%d cpw=%s path=%s", cid, tsEscape(channelPassword), tsEscape(path)))
}

func (t *TeamSpeakCore) FTGetFileInfo(cid int, name, channelPassword string) (map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	rows, err := t.tsExec(fmt.Sprintf("ftgetfileinfo cid=%d cpw=%s name=%s", cid, tsEscape(channelPassword), tsEscape(name)))
	if err != nil {
		return nil, err
	}
	if len(rows) == 0 {
		return nil, ErrNotFound
	}
	return rows[0], nil
}

func (t *TeamSpeakCore) FTDeleteFile(cid int, names []string, channelPassword string) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	parts := make([]string, len(names))
	for i, n := range names {
		parts[i] = fmt.Sprintf("name=%s", tsEscape(n))
	}
	return t.tsExecSimple(fmt.Sprintf("ftdeletefile cid=%d cpw=%s %s", cid, tsEscape(channelPassword), strings.Join(parts, "|")))
}

func (t *TeamSpeakCore) FTCreateDir(cid int, dirname, channelPassword string) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple(fmt.Sprintf("ftcreatedir cid=%d cpw=%s dirname=%s", cid, tsEscape(channelPassword), tsEscape(dirname)))
}

func (t *TeamSpeakCore) FTRenameFile(cid int, oldName, newName, channelPassword string, targetCID int, targetPassword string) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	cmd := fmt.Sprintf("ftrenamefile cid=%d cpw=%s oldname=%s newname=%s",
		cid, tsEscape(channelPassword), tsEscape(oldName), tsEscape(newName))
	if targetCID > 0 {
		cmd += fmt.Sprintf(" tcid=%d tcpw=%s", targetCID, tsEscape(targetPassword))
	}
	return t.tsExecSimple(cmd)
}

func (t *TeamSpeakCore) FTStop(serverFTFID int, del bool) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	d := 0
	if del {
		d = 1
	}
	return t.tsExecSimple(fmt.Sprintf("ftstop serverftfid=%d delete=%d", serverFTFID, d))
}

func (t *TeamSpeakCore) FTList() ([]map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	return t.tsExec("ftlist")
}

// ──────────────────────────── Connection Stats ────────────────────────────

func (t *TeamSpeakCore) ServerRequestConnectionInfo() (map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	rows, err := t.tsExec("serverrequestconnectioninfo")
	if err != nil {
		return nil, err
	}
	if len(rows) == 0 {
		return nil, ErrNotFound
	}
	return rows[0], nil
}

func (t *TeamSpeakCore) SetConnectionInfo() error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	s := t.bwStats.snapshot()
	cmd := fmt.Sprintf("setconnectioninfo connection_ping=0.05 connection_ping_deviation=0.01 "+
		"connection_bandwidth_sent_last_second_speech=%d connection_bandwidth_sent_last_second_keepalive=%d "+
		"connection_bandwidth_sent_last_second_control=%d connection_bandwidth_sent_last_minute_speech=%d "+
		"connection_bandwidth_sent_last_minute_keepalive=%d connection_bandwidth_sent_last_minute_control=%d "+
		"connection_bandwidth_received_last_second_speech=%d connection_bandwidth_received_last_second_keepalive=%d "+
		"connection_bandwidth_received_last_second_control=%d connection_bandwidth_received_last_minute_speech=%d "+
		"connection_bandwidth_received_last_minute_keepalive=%d connection_bandwidth_received_last_minute_control=%d "+
		"connection_packets_sent_speech=%d connection_packets_sent_keepalive=%d connection_packets_sent_control=%d "+
		"connection_packets_received_speech=%d connection_packets_received_keepalive=%d connection_packets_received_control=%d "+
		"connection_bytes_sent_speech=%d connection_bytes_sent_keepalive=%d connection_bytes_sent_control=%d "+
		"connection_bytes_received_speech=%d connection_bytes_received_keepalive=%d connection_bytes_received_control=%d "+
		"connection_server2client_packetloss_speech=%.4f connection_server2client_packetloss_keepalive=0 "+
		"connection_server2client_packetloss_control=0 connection_server2client_packetloss_total=%.4f",
		s.SentLastSecond[0], s.SentLastSecond[1], s.SentLastSecond[2],
		s.SentLastMinute[0], s.SentLastMinute[1], s.SentLastMinute[2],
		s.RecvLastSecond[0], s.RecvLastSecond[1], s.RecvLastSecond[2],
		s.RecvLastMinute[0], s.RecvLastMinute[1], s.RecvLastMinute[2],
		s.TotalSentPkts[0], s.TotalSentPkts[1], s.TotalSentPkts[2],
		s.TotalRecvPkts[0], s.TotalRecvPkts[1], s.TotalRecvPkts[2],
		s.TotalSentBytes[0], s.TotalSentBytes[1], s.TotalSentBytes[2],
		s.TotalRecvBytes[0], s.TotalRecvBytes[1], s.TotalRecvBytes[2],
		s.VoicePacketLoss, s.VoicePacketLoss)
	return t.tsExecSimple(cmd)
}

// ──────────────────────────── Voice ────────────────────────────

// Codec type constants
const (
	tsCodecSpeexNB  = 0 // Speex Narrowband 8kHz mono
	tsCodecSpeexWB  = 1 // Speex Wideband 16kHz mono
	tsCodecSpeexUWB = 2 // Speex Ultra-wideband 32kHz mono
	tsCodecCeltMono = 3 // CELT Mono 48kHz
	tsCodecOpusVoice = 4 // Opus Voice 48kHz mono (default)
	tsCodecOpusMusic = 5 // Opus Music 48kHz stereo
)

// Group whisper types
const (
	tsGroupWhisperTypeServerGroup      = 0
	tsGroupWhisperTypeChannelGroup     = 1
	tsGroupWhisperTypeChannelCommander = 2
	tsGroupWhisperTypeAllClients       = 3
)

// Group whisper targets
const (
	tsGroupWhisperTargetAllChannels           = 0
	tsGroupWhisperTargetCurrentChannel        = 1
	tsGroupWhisperTargetParentChannel         = 2
	tsGroupWhisperTargetAllParentChannels     = 3
	tsGroupWhisperTargetChannelFamily         = 4
	tsGroupWhisperTargetCompleteChannelFamily = 5
	tsGroupWhisperTargetSubchannels           = 6
)

// OnVoice registers a callback for incoming voice packets.
func (t *TeamSpeakCore) OnVoice(handler func(VoicePacket)) {
	t.voiceHandlerMu.Lock()
	defer t.voiceHandlerMu.Unlock()
	t.voiceHandler = handler
}

// tsHandleVoicePacket parses and dispatches incoming voice data.
func (t *TeamSpeakCore) tsHandleVoicePacket(packetType byte, flags byte, plaintext []byte) {
	t.voiceHandlerMu.RLock()
	handler := t.voiceHandler
	t.voiceHandlerMu.RUnlock()
	if handler == nil {
		return // no voice handler registered
	}

	isWhisper := packetType == tsPktVoiceWhisper
	hasServerFlag := flags&tsFlagCompressed != 0

	// S2C voice body: VoicePacketCounter(2) + ClientID(2) + Codec(1) + AudioData(...)
	// If COMPRESSED flag, last byte is serverFlag0
	if len(plaintext) < 5 {
		return // too short for S2C voice
	}

	voiceCounter := binary.BigEndian.Uint16(plaintext[0:2])
	clientID := int(binary.BigEndian.Uint16(plaintext[2:4]))
	codec := plaintext[4]

	audioStart := 5
	audioEnd := len(plaintext)

	var serverFlag byte
	if hasServerFlag && audioEnd > audioStart {
		serverFlag = plaintext[audioEnd-1]
		audioEnd--
	}

	if audioEnd <= audioStart {
		return // no audio data
	}

	audioData := make([]byte, audioEnd-audioStart)
	copy(audioData, plaintext[audioStart:audioEnd])

	vp := VoicePacket{
		SenderClientID: clientID,
		Codec:          codec,
		AudioData:      audioData,
		PacketCounter:  voiceCounter,
		IsWhisper:      isWhisper,
		ServerFlag:     serverFlag,
		HasServerFlag:  hasServerFlag,
	}

	go handler(vp)
}

// tsSendVoicePacket sends an encrypted voice packet.
func (t *TeamSpeakCore) tsSendVoicePacket(pktType byte, flags byte, body []byte) error {
	tc := t.tsConn
	if tc == nil {
		return ErrAuth
	}
	if !tc.cryptoOK {
		return fmt.Errorf("%w: crypto not established", ErrNetwork)
	}

	tc.mu.Lock()
	defer tc.mu.Unlock()

	pID := tc.tsNextPktID(pktType)
	// Voice packets do NOT use Newprotocol flag (unlike commands)
	pktFlags := pktType | flags

	// Voice body counter = packet ID (per ts3j: voice counter is same as header pID)
	if len(body) >= 2 {
		binary.BigEndian.PutUint16(body[0:2], pID)
	}

	// Build meta for EAX: PId(2) + CId(2) + PT(1)
	meta := make([]byte, 5)
	binary.BigEndian.PutUint16(meta[0:2], pID)
	binary.BigEndian.PutUint16(meta[2:4], tc.clientID)
	meta[4] = pktFlags

	key, nonce := tsCreateKeyNonce(pktType, pID, tc.pktState[pktType].sendGenID, 0x31, tc.sharedIV[:])
	mac, ciphertext := tsEAXEncrypt(key[:], nonce[:], meta, body)

	pkt := tsBuildC2SPacket(mac, pID, tc.clientID, pktFlags, ciphertext)
	t.bwStats.recordSent(pktType, len(pkt))
	return tc.tsSendRaw(pkt)
	// Voice packets are NOT acknowledged — fire and forget
}

// SendVoice sends a normal voice packet to the current channel.
// audioData must be pre-encoded (Opus, CELT, etc.)
func (t *TeamSpeakCore) SendVoice(codec byte, audioData []byte) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}

	// Body: VoicePacketCounter(2) + Codec(1) + AudioData(...)
	// Voice counter = packet ID (filled in by tsSendVoicePacket after getting pID)
	body := make([]byte, 3+len(audioData))
	// body[0:2] = placeholder for counter (set by tsSendVoicePacket)
	body[2] = codec
	copy(body[3:], audioData)

	return t.tsSendVoicePacket(tsPktVoice, 0, body)
}

// SendVoiceWhisper sends a whisper voice packet to specific channels and/or clients.
func (t *TeamSpeakCore) SendVoiceWhisper(codec byte, audioData []byte, channelIDs []uint64, clientIDs []uint16) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}

	// Body: VoicePacketCounter(2) + Codec(1) + ChannelCount(1) + ClientCount(1) + ChannelIDs(8*N) + ClientIDs(2*M) + AudioData
	// Voice counter filled in by tsSendVoicePacket (= packet ID)
	headerLen := 5 + len(channelIDs)*8 + len(clientIDs)*2
	body := make([]byte, headerLen+len(audioData))
	body[2] = codec
	body[3] = byte(len(channelIDs))
	body[4] = byte(len(clientIDs))
	off := 5
	for _, cid := range channelIDs {
		binary.BigEndian.PutUint64(body[off:off+8], cid)
		off += 8
	}
	for _, clid := range clientIDs {
		binary.BigEndian.PutUint16(body[off:off+2], clid)
		off += 2
	}
	copy(body[off:], audioData)

	return t.tsSendVoicePacket(tsPktVoiceWhisper, 0, body)
}

// SendVoiceGroupWhisper sends a group whisper voice packet.
func (t *TeamSpeakCore) SendVoiceGroupWhisper(codec byte, audioData []byte, whisperType, whisperTarget byte, targetID uint64) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}

	// Body: VoicePacketCounter(2) + Codec(1) + GroupWhisperType(1) + GroupWhisperTarget(1) + TargetID(8) + AudioData
	// Voice counter filled in by tsSendVoicePacket (= packet ID)
	body := make([]byte, 13+len(audioData))
	body[2] = codec
	body[3] = whisperType
	body[4] = whisperTarget
	binary.BigEndian.PutUint64(body[5:13], targetID)
	copy(body[13:], audioData)

	// Group whisper uses Newprotocol flag on the whisper packet type
	return t.tsSendVoicePacket(tsPktVoiceWhisper, tsFlagNewprotocol, body)
}

// ──────────────────────────── Bandwidth Stats ────────────────────────────

const tsBwWindowSize = 60 // 60-second rolling window

// tsBwCategory is a packet category for bandwidth tracking.
type tsBwCategory int

const (
	tsBwSpeech    tsBwCategory = 0
	tsBwKeepalive tsBwCategory = 1
	tsBwControl   tsBwCategory = 2
)

// tsBwSample is a single-second stats sample.
type tsBwSample struct {
	packets int64
	bytes   int64
}

// tsBandwidthStats tracks per-category packet/byte counters with a 60-second rolling window.
type tsBandwidthStats struct {
	mu sync.Mutex

	// Rolling window: ring buffers indexed by (unix_second % 60)
	sentRing [3][tsBwWindowSize]tsBwSample // [category][second]
	recvRing [3][tsBwWindowSize]tsBwSample

	// Totals
	totalSentPkts  [3]int64
	totalSentBytes [3]int64
	totalRecvPkts  [3]int64
	totalRecvBytes [3]int64

	// Current second tracker
	lastSecond int64

	// Packet loss: S2C voice
	voiceExpected atomic.Int64
	voiceLost     atomic.Int64
}

// tsBwCategoryForPacket maps a packet type to a bandwidth category.
func tsBwCategoryForPacket(pktType byte) tsBwCategory {
	switch pktType {
	case tsPktVoice, tsPktVoiceWhisper:
		return tsBwSpeech
	case tsPktPing, tsPktPong:
		return tsBwKeepalive
	default:
		return tsBwControl
	}
}

func (bw *tsBandwidthStats) advance(now int64) {
	// Clear stale slots between lastSecond and now
	if bw.lastSecond == 0 {
		bw.lastSecond = now
		return
	}
	gap := now - bw.lastSecond
	if gap <= 0 {
		return
	}
	if gap > tsBwWindowSize {
		gap = tsBwWindowSize
	}
	for i := int64(1); i <= gap; i++ {
		idx := (bw.lastSecond + i) % tsBwWindowSize
		for c := 0; c < 3; c++ {
			bw.sentRing[c][idx] = tsBwSample{}
			bw.recvRing[c][idx] = tsBwSample{}
		}
	}
	bw.lastSecond = now
}

func (bw *tsBandwidthStats) recordSent(pktType byte, size int) {
	cat := tsBwCategoryForPacket(pktType)
	bw.mu.Lock()
	now := time.Now().Unix()
	bw.advance(now)
	idx := now % tsBwWindowSize
	bw.sentRing[cat][idx].packets++
	bw.sentRing[cat][idx].bytes += int64(size)
	bw.totalSentPkts[cat]++
	bw.totalSentBytes[cat] += int64(size)
	bw.mu.Unlock()
}

func (bw *tsBandwidthStats) recordRecv(pktType byte, size int) {
	cat := tsBwCategoryForPacket(pktType)
	bw.mu.Lock()
	now := time.Now().Unix()
	bw.advance(now)
	idx := now % tsBwWindowSize
	bw.recvRing[cat][idx].packets++
	bw.recvRing[cat][idx].bytes += int64(size)
	bw.totalRecvPkts[cat]++
	bw.totalRecvBytes[cat] += int64(size)
	bw.mu.Unlock()
}

// TsBandwidthSnapshot holds bandwidth statistics at a point in time.
type TsBandwidthSnapshot struct {
	// Per-category last-second bandwidth (bytes/sec)
	SentLastSecond  [3]int64 // [speech, keepalive, control]
	RecvLastSecond  [3]int64
	// Per-category last-minute bandwidth (bytes/sec average)
	SentLastMinute  [3]int64
	RecvLastMinute  [3]int64
	// Total packet/byte counts
	TotalSentPkts   [3]int64
	TotalSentBytes  [3]int64
	TotalRecvPkts   [3]int64
	TotalRecvBytes  [3]int64
	// Voice packet loss ratio (0.0-1.0)
	VoicePacketLoss float64
}

func (bw *tsBandwidthStats) snapshot() TsBandwidthSnapshot {
	bw.mu.Lock()
	now := time.Now().Unix()
	bw.advance(now)

	snap := TsBandwidthSnapshot{
		TotalSentPkts:  bw.totalSentPkts,
		TotalSentBytes: bw.totalSentBytes,
		TotalRecvPkts:  bw.totalRecvPkts,
		TotalRecvBytes: bw.totalRecvBytes,
	}

	// Last second = the previous completed second
	prevIdx := (now - 1) % tsBwWindowSize
	for c := 0; c < 3; c++ {
		snap.SentLastSecond[c] = bw.sentRing[c][prevIdx].bytes
		snap.RecvLastSecond[c] = bw.recvRing[c][prevIdx].bytes
	}

	// Last minute = average over 60 seconds
	for c := 0; c < 3; c++ {
		var sentTotal, recvTotal int64
		for i := int64(0); i < tsBwWindowSize; i++ {
			sentTotal += bw.sentRing[c][i].bytes
			recvTotal += bw.recvRing[c][i].bytes
		}
		snap.SentLastMinute[c] = sentTotal / tsBwWindowSize
		snap.RecvLastMinute[c] = recvTotal / tsBwWindowSize
	}

	bw.mu.Unlock()

	expected := bw.voiceExpected.Load()
	lost := bw.voiceLost.Load()
	if expected > 0 {
		snap.VoicePacketLoss = float64(lost) / float64(expected)
	}

	return snap
}

// GetBandwidthStats returns current bandwidth statistics.
func (t *TeamSpeakCore) GetBandwidthStats() TsBandwidthSnapshot {
	return t.bwStats.snapshot()
}

// ──────────────────────────── Voice Activity Detection ────────────────────────────

// DetectVoiceActivity checks if PCM audio samples contain voice (energy-based).
// pcm: int16 samples (mono). threshold: RMS threshold (300-500 typical for speech).
// Returns true if the RMS energy exceeds the threshold.
func DetectVoiceActivity(pcm []int16, threshold float64) bool {
	if len(pcm) == 0 {
		return false
	}
	var sumSq float64
	for _, s := range pcm {
		v := float64(s)
		sumSq += v * v
	}
	rms := math.Sqrt(sumSq / float64(len(pcm)))
	return rms > threshold
}
