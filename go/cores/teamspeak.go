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
	"errors"
	"fmt"
	"io"
	"log"
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

	"uniclient/utils"
)

const (
	tsVoicePort      = "9987"
	tsMaxMsgBuffer   = 500
	tsPingInterval   = 30 * time.Second
	tsReadTimeout    = 5 * time.Second
	tsDialTimeout    = 10 * time.Second
	tsRetransmitBase = 500 * time.Millisecond
	tsMaxRetransmit  = 30 * time.Second
	TsMaxPayloadC2S  = 487
	tsMaxPayloadS2C  = 489
	tsHeaderC2S      = 13
	tsHeaderS2C      = 11
	tsVersionTS      = 1466672534
	tsEpochOffset    = 1356998400
	TsInitVersion    = 1566914096
)

const (
	TsPktVoice        = 0x00
	tsPktVoiceWhisper = 0x01
	TsPktCommand      = 0x02
	tsPktCommandLow   = 0x03
	tsPktPing         = 0x04
	tsPktPong         = 0x05
	tsPktAck          = 0x06
	tsPktAckLow       = 0x07
	tsPktInit         = 0x08
)

const (
	tsFlagUnencrypted = 0x80
	TsFlagCompressed  = 0x40
	TsFlagNewprotocol = 0x20
	TsFlagFragmented  = 0x10
)

var tsInitMAC = [8]byte{0x54, 0x53, 0x33, 0x49, 0x4E, 0x49, 0x54, 0x31}

var TsFakeKey = [16]byte{0x63, 0x3A, 0x5C, 0x77, 0x69, 0x6E, 0x64, 0x6F, 0x77, 0x73, 0x5C, 0x73, 0x79, 0x73, 0x74, 0x65}
var TsFakeNonce = [16]byte{0x6D, 0x5C, 0x66, 0x69, 0x72, 0x65, 0x77, 0x61, 0x6C, 0x6C, 0x33, 0x32, 0x2E, 0x63, 0x70, 0x6C}

var TsRootKey = [32]byte{
	0xcd, 0x0d, 0xe2, 0xae, 0xd4, 0x63, 0x45, 0x50,
	0x9a, 0x7e, 0x3c, 0xfd, 0x8f, 0x68, 0xb3, 0xdc,
	0x75, 0x55, 0xb2, 0x9d, 0xcc, 0xec, 0x73, 0xcd,
	0x18, 0x75, 0x0f, 0x99, 0x38, 0x12, 0x40, 0x8a,
}

const tsVersionStr = "3.?.? [Build: 5680278000]"
const tsPlatform = "Linux"
const ts3Platform = "teamspeak"
const tsVersionSign = "Hjd+N58Gv3ENhoKmGYy2bNRBsNNgm5kpiaQWxOj5HN2DXttG6REjymSwJtpJ8muC2gSwRuZi0R+8Laan5ts5CQ=="

func TsQuickLZDecompress(src []byte) ([]byte, error) {
	if len(src) < 3 {
		return nil, fmt.Errorf("quicklz: input too short (%d bytes)", len(src))
	}

	flags := src[0]
	var compressedSize, decompressedSize uint32
	var headerLen int

	if flags&0x02 != 0 {
		if len(src) < 9 {
			return nil, fmt.Errorf("quicklz: long header but only %d bytes", len(src))
		}
		headerLen = 9
		compressedSize = binary.LittleEndian.Uint32(src[1:5])
		decompressedSize = binary.LittleEndian.Uint32(src[5:9])
	} else {
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

	if flags&0x01 == 0 {
		out := make([]byte, decompressedSize)
		copy(out, src[headerLen:])
		return out, nil
	}

	in := src[headerLen:compressedSize]
	out := make([]byte, 0, decompressedSize)
	var hashtable [4096]uint32
	inPos := 0

	control := uint32(1)

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

			for i := uint32(0); i < matchlen; i++ {
				if int(offset+i) < len(out) {
					out = append(out, out[offset+i])
				}
			}

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

		} else if uint32(len(out)) >= decompressedSize-10 || decompressedSize < 10 {
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
			control >>= 1
			if inPos >= len(in) {
				break
			}
			out = append(out, in[inPos])
			inPos++

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

func TsQuickLZCompress(src []byte) ([]byte, bool) {
	size := len(src)
	if size == 0 || uint64(size) > uint64(0xffffffff-400) {
		return nil, false
	}
	base := 9
	if size < 216 {
		base = 3
	}

	var table [4096]uint32
	var cache [4096]uint32

	out := make([]byte, base+size+size/7+64)

	le24 := func(p int) uint32 {
		return uint32(src[p]) | uint32(src[p+1])<<8 | uint32(src[p+2])<<16
	}
	writeLE := func(v uint32, at, n int) {
		for i := 0; i < n; i++ {
			out[at+i] = byte(v >> (8 * i))
		}
	}
	same7 := func(pos int) bool {
		b := src[pos-3]
		for i := 1; i <= 6; i++ {
			if src[pos-3+i] != b {
				return false
			}
		}
		return true
	}

	lastByte := size - 1
	lastMatchStart := lastByte - 6 - 4

	cwordPtr := base
	dstPos := base + 4
	cwordVal := uint32(1) << 31
	lits := 0
	pos := 0
	var fetch uint32
	if pos <= lastMatchStart {
		fetch = le24(pos)
	}
	giveUp := false

mainLoop:
	for pos <= lastMatchStart {
		if cwordVal&1 == 1 {
			if pos > size>>1 && dstPos-base > pos-(pos>>5) {
				giveUp = true
				break mainLoop
			}
			writeLE((cwordVal>>1)|(1<<31), cwordPtr, 4)
			cwordPtr = dstPos
			dstPos += 4
			cwordVal = 1 << 31
			fetch = le24(pos)
		}
		h := ((fetch >> 12) ^ fetch) & 4095
		cached := fetch ^ cache[h]
		cache[h] = fetch
		prev := table[h]
		table[h] = uint32(pos)
		if cached == 0 && prev != 0 &&
			(pos-int(prev) > 2 ||
				(pos == int(prev)+1 && lits >= 3 && pos > 3 && same7(pos))) {
			o := int(prev)
			cwordVal = cwordVal>>1 | 1<<31
			hsh := h << 4
			if src[o+3] != src[pos+3] {
				writeLE(1|hsh, dstPos, 2)
				dstPos += 2
				pos += 3
			} else {
				oldPos := pos
				pos += 4
				if src[o+(pos-oldPos)] == src[pos] {
					pos++
					if src[o+(pos-oldPos)] == src[pos] {
						q := lastByte - 4 - (pos - 5) + 1
						remaining := q
						if remaining > 255 {
							remaining = 255
						}
						for src[o+(pos-oldPos)] == src[pos] && (pos-oldPos) < remaining {
							pos++
						}
					}
				}
				matchlen := pos - oldPos
				if matchlen < 18 {
					writeLE(uint32(matchlen-2)|hsh, dstPos, 2)
					dstPos += 2
				} else {
					writeLE(uint32(matchlen)<<16|hsh, dstPos, 3)
					dstPos += 3
				}
			}
			fetch = le24(pos)
			lits = 0
		} else {
			lits++
			out[dstPos] = src[pos]
			pos++
			dstPos++
			cwordVal >>= 1
			fetch = le24(pos)
		}
	}

	if !giveUp {
		for pos <= lastByte {
			if cwordVal&1 == 1 {
				writeLE((cwordVal>>1)|(1<<31), cwordPtr, 4)
				cwordPtr = dstPos
				dstPos += 4
				cwordVal = 1 << 31
			}
			if pos <= lastByte-3 {
				f := le24(pos)
				hh := ((f >> 12) ^ f) & 4095
				table[hh] = uint32(pos)
				cache[hh] = f
			}
			out[dstPos] = src[pos]
			pos++
			dstPos++
			cwordVal >>= 1
		}
		for cwordVal&1 != 1 {
			cwordVal >>= 1
		}
		writeLE((cwordVal>>1)|(1<<31), cwordPtr, 4)
	}

	coreLen := dstPos - base
	if coreLen < 9 {
		coreLen = 9
	}
	compressed := byte(1)
	r := base + coreLen
	if giveUp {
		compressed = 0
		coreLen = 0
		copy(out[base:], src)
		r = size + base
	}
	fl := compressed | (1 << 2) | (1 << 6)
	if base == 3 {
		out[0] = fl
		out[1] = byte(r)
		out[2] = byte(size)
	} else {
		out[0] = fl | 0x02
		writeLE(uint32(r), 1, 4)
		writeLE(uint32(size), 5, 4)
	}
	return out[:r], true
}

func tsOMAC1(key, data []byte) []byte {
	block, _ := aes.NewCipher(key)
	bs := block.BlockSize()

	var zero [16]byte
	l := make([]byte, bs)
	block.Encrypt(l, zero[:])

	k1 := tsDbl(l)
	k2 := tsDbl(k1)

	n := len(data)
	var flag bool
	if n == 0 {
		flag = false
		n = bs
	} else {
		flag = (n % bs) == 0
	}

	if flag {
		tmp := make([]byte, n)
		copy(tmp, data)
		for i := 0; i < bs; i++ {
			tmp[n-bs+i] ^= k1[i]
		}
		data = tmp
	} else {
		padded := make([]byte, ((n/bs)+1)*bs)
		copy(padded, data)
		padded[n] = 0x80
		for i := 0; i < bs; i++ {
			padded[len(padded)-bs+i] ^= k2[i]
		}
		data = padded
		n = len(padded)
	}

	mac := make([]byte, bs)
	for i := 0; i < n; i += bs {
		for j := 0; j < bs; j++ {
			mac[j] ^= data[i+j]
		}
		block.Encrypt(mac, mac)
	}
	return mac
}

func tsDbl(b []byte) []byte {
	var r [16]byte
	carry := b[0] >> 7
	for i := 0; i < 15; i++ {
		r[i] = (b[i] << 1) | (b[i+1] >> 7)
	}
	r[15] = b[15] << 1
	if carry == 1 {
		r[15] ^= 0x87
	}
	return r[:]
}

func TsEAXEncrypt(key, nonce, header, plaintext []byte) (mac [8]byte, ciphertext []byte) {
	block, _ := aes.NewCipher(key)

	nonceInput := make([]byte, 16+len(nonce))
	copy(nonceInput[16:], nonce)
	n := tsOMAC1(key, nonceInput)

	headerInput := make([]byte, 16+len(header))
	headerInput[15] = 0x01
	copy(headerInput[16:], header)
	h := tsOMAC1(key, headerInput)

	ciphertext = make([]byte, len(plaintext))
	stream := cipher.NewCTR(block, n)
	stream.XORKeyStream(ciphertext, plaintext)

	cInput := make([]byte, 16+len(ciphertext))
	cInput[15] = 0x02
	copy(cInput[16:], ciphertext)
	c := tsOMAC1(key, cInput)

	for i := 0; i < 8; i++ {
		mac[i] = n[i] ^ h[i] ^ c[i]
	}
	return
}

func TsEAXDecrypt(key, nonce, header, ciphertext []byte, macIn [8]byte) ([]byte, error) {
	block, _ := aes.NewCipher(key)

	nonceInput := make([]byte, 16+len(nonce))
	copy(nonceInput[16:], nonce)
	n := tsOMAC1(key, nonceInput)

	headerInput := make([]byte, 16+len(header))
	headerInput[15] = 0x01
	copy(headerInput[16:], header)
	h := tsOMAC1(key, headerInput)

	cInput := make([]byte, 16+len(ciphertext))
	cInput[15] = 0x02
	copy(cInput[16:], ciphertext)
	c := tsOMAC1(key, cInput)

	for i := 0; i < 8; i++ {
		if macIn[i] != n[i]^h[i]^c[i] {
			return nil, fmt.Errorf("EAX: MAC mismatch")
		}
	}

	plaintext := make([]byte, len(ciphertext))
	stream := cipher.NewCTR(block, n)
	stream.XORKeyStream(plaintext, ciphertext)
	return plaintext, nil
}

func TsCreateKeyNonce(pType byte, pID uint16, genID uint32, direction byte, sharedIV []byte) (key [16]byte, nonce [16]byte) {
	var temp [70]byte
	temp[0] = direction
	temp[1] = pType & 0x0f
	binary.BigEndian.PutUint32(temp[2:6], genID)
	n := 6 + copy(temp[6:], sharedIV)

	h := sha256.Sum256(temp[:n])
	copy(key[:], h[:16])
	copy(nonce[:], h[16:])

	key[0] ^= byte(pID >> 8)
	key[1] ^= byte(pID & 0xff)
	return
}

type tsP256Identity struct {
	key       *ecdsa.PrivateKey
	keyOffset uint64
}

func TsNewIdentity() (*tsP256Identity, error) {
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return nil, err
	}
	id := &tsP256Identity{key: key}
	omega := id.tsOmega()
	id.keyOffset = tsHashCash(omega, 8)
	return id, nil
}

func (id *tsP256Identity) tsOmega() string {
	pub := id.key.PublicKey
	xBytes := pub.X.Bytes()
	yBytes := pub.Y.Bytes()

	for len(xBytes) < 32 {
		xBytes = append([]byte{0}, xBytes...)
	}
	for len(yBytes) < 32 {
		yBytes = append([]byte{0}, yBytes...)
	}

	bitString := []byte{0x03, 0x02, 0x07, 0x00}

	int32 := []byte{0x02, 0x01, 0x20}

	intX := tsASN1Integer(xBytes)
	intY := tsASN1Integer(yBytes)

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

func tsASN1Integer(b []byte) []byte {
	for len(b) > 1 && b[0] == 0 {
		b = b[1:]
	}
	if len(b) > 0 && b[0]&0x80 != 0 {
		b = append([]byte{0x00}, b...)
	}
	result := []byte{0x02}
	result = append(result, tsASN1Length(len(b))...)
	result = append(result, b...)
	return result
}

func tsASN1Length(n int) []byte {
	if n < 0x80 {
		return []byte{byte(n)}
	}
	if n < 0x100 {
		return []byte{0x81, byte(n)}
	}
	return []byte{0x82, byte(n >> 8), byte(n)}
}

func (id *tsP256Identity) tsUID() string {
	omega := id.tsOmega()
	h := sha1.Sum([]byte(omega))
	return base64.StdEncoding.EncodeToString(h[:])
}

func (id *tsP256Identity) tsSign(data []byte) ([]byte, error) {
	hash := sha256.Sum256(data)
	r, s, err := ecdsa.Sign(rand.Reader, id.key, hash[:])
	if err != nil {
		return nil, err
	}
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

func TsVerifyP256(pubX, pubY *big.Int, data, sig []byte) bool {
	pub := &ecdsa.PublicKey{Curve: elliptic.P256(), X: pubX, Y: pubY}
	hash := sha256.Sum256(data)
	return ecdsa.VerifyASN1(pub, hash[:], sig)
}

func TsParseOmega(b64 string) (*big.Int, *big.Int, error) {
	data, err := base64.StdEncoding.DecodeString(b64)
	if err != nil {
		return nil, nil, err
	}
	if len(data) < 2 || data[0] != 0x30 {
		return nil, nil, fmt.Errorf("not a SEQUENCE")
	}
	inner, err := tsASN1ReadLength(data[1:])
	if err != nil {
		return nil, nil, err
	}
	offset := len(data) - len(inner)
	_ = offset

	if len(inner) < 2 || inner[0] != 0x03 {
		return nil, nil, fmt.Errorf("expected BIT STRING")
	}
	bsLen, rest, err := tsASN1ParseLength(inner[1:])
	if err != nil {
		return nil, nil, err
	}
	rest = rest[bsLen:]

	if len(rest) < 2 || rest[0] != 0x02 {
		return nil, nil, fmt.Errorf("expected INTEGER (keysize)")
	}
	ksLen, rest2, err := tsASN1ParseLength(rest[1:])
	if err != nil {
		return nil, nil, err
	}
	rest = rest2[ksLen:]

	if len(rest) < 2 || rest[0] != 0x02 {
		return nil, nil, fmt.Errorf("expected INTEGER (X)")
	}
	xLen, xData, err := tsASN1ParseLength(rest[1:])
	if err != nil {
		return nil, nil, err
	}
	x := new(big.Int).SetBytes(xData[:xLen])
	rest = xData[xLen:]

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

func TsDeriveLicenseKey(licenseData []byte, rootKey [32]byte) (*edwards25519.Point, error) {
	parentPoint, err := new(edwards25519.Point).SetBytes(rootKey[:])
	if err != nil {
		return nil, fmt.Errorf("invalid root key: %w", err)
	}

	if len(licenseData) < 1 {
		return nil, fmt.Errorf("empty license data")
	}
	offset := 1
	for offset < len(licenseData) {
		if offset+42 > len(licenseData) {
			return nil, fmt.Errorf("license block too short at offset %d", offset)
		}

		blockData := licenseData[offset:]

		pubKeyBytes := blockData[1:33]
		blockType := blockData[33]

		contentStart := 42
		blockLen := contentStart
		switch blockType {
		case 0:
			blockLen = contentStart + 4
			for blockLen < len(blockData) && blockData[blockLen] != 0 {
				blockLen++
			}
			if blockLen < len(blockData) {
				blockLen++
			}
		case 2:
			blockLen = contentStart + 5
			for blockLen < len(blockData) && blockData[blockLen] != 0 {
				blockLen++
			}
			if blockLen < len(blockData) {
				blockLen++
			}
		case 1, 3:
			blockLen = contentStart
			for blockLen < len(blockData) && blockData[blockLen] != 0 {
				blockLen++
			}
			if blockLen < len(blockData) {
				blockLen++
			}
		case 32:
			blockLen = contentStart
		default:
			blockLen = contentStart
			for blockLen < len(blockData) && blockData[blockLen] != 0 {
				blockLen++
			}
			if blockLen < len(blockData) {
				blockLen++
			}
		}

		fullHash := sha512.Sum512(blockData[1:blockLen])
		var hashKeyBytes [32]byte
		copy(hashKeyBytes[:], fullHash[:32])
		hashKeyBytes[0] &= 248
		hashKeyBytes[31] &= 63
		hashKeyBytes[31] |= 64

		hashKeyScalar, err := new(edwards25519.Scalar).SetCanonicalBytes(hashKeyBytes[:])
		if err != nil {
			hashKeyScalar, err = new(edwards25519.Scalar).SetBytesWithClamping(fullHash[:32])
			if err != nil {
				return nil, fmt.Errorf("invalid hash key scalar: %w", err)
			}
		}

		blockPubPoint, err := new(edwards25519.Point).SetBytes(pubKeyBytes)
		if err != nil {
			return nil, fmt.Errorf("invalid block public key: %w", err)
		}

		scaledPub := new(edwards25519.Point).ScalarMult(hashKeyScalar, blockPubPoint)
		parentPoint = new(edwards25519.Point).Add(scaledPub, parentPoint)

		offset += blockLen
	}

	return parentPoint, nil
}

func TsComputeSharedIVMAC(alpha [10]byte, beta [54]byte, ekPriv *edwards25519.Scalar, serverEK *edwards25519.Point) ([64]byte, [8]byte) {
	sharedSecret := new(edwards25519.Point).ScalarMult(ekPriv, serverEK)
	secretBytes := sharedSecret.Bytes()

	var sharedIV [64]byte
	h := sha512.Sum512(secretBytes)
	copy(sharedIV[:], h[:])

	for i := 0; i < 10; i++ {
		sharedIV[i] ^= alpha[i]
	}
	for i := 0; i < 54; i++ {
		sharedIV[i+10] ^= beta[i]
	}

	var sharedMAC [8]byte
	macHash := sha1.Sum(sharedIV[:])
	copy(sharedMAC[:], macHash[:8])

	return sharedIV, sharedMAC
}

func tsHashCash(omega string, level byte) uint64 {
	base := []byte(omega)
	buf := make([]byte, len(base), len(base)+20)
	copy(buf, base)
	for offset := uint64(0); offset < ^uint64(0); offset++ {
		buf = buf[:len(base)]
		buf = strconv.AppendUint(buf, offset, 10)
		h := sha1.Sum(buf)
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

func TsEscape(s string) string {
	needsEscape := false
	for i := 0; i < len(s); i++ {
		switch s[i] {
		case '\\', '/', ' ', '|', '\a', '\b', '\f', '\n', '\r', '\t', '\v':
			needsEscape = true
		}
		if needsEscape {
			break
		}
	}
	if !needsEscape {
		return s
	}
	var buf strings.Builder
	buf.Grow(len(s) + len(s)/4)
	for i := 0; i < len(s); i++ {
		switch s[i] {
		case '\\':
			buf.WriteString(`\\`)
		case '/':
			buf.WriteString(`\/`)
		case ' ':
			buf.WriteString(`\s`)
		case '|':
			buf.WriteString(`\p`)
		case '\a':
			buf.WriteString(`\a`)
		case '\b':
			buf.WriteString(`\b`)
		case '\f':
			buf.WriteString(`\f`)
		case '\n':
			buf.WriteString(`\n`)
		case '\r':
			buf.WriteString(`\r`)
		case '\t':
			buf.WriteString(`\t`)
		case '\v':
			buf.WriteString(`\v`)
		default:
			buf.WriteByte(s[i])
		}
	}
	return buf.String()
}

func TsUnescape(s string) string {
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
	n := strings.Count(s, " ") + 1
	m := make(map[string]string, n)
	for len(s) > 0 {
		end := strings.IndexByte(s, ' ')
		var pair string
		if end < 0 {
			pair = s
			s = ""
		} else {
			pair = s[:end]
			s = s[end+1:]
			for len(s) > 0 && s[0] == ' ' {
				s = s[1:]
			}
		}
		if pair == "" {
			continue
		}
		idx := strings.IndexByte(pair, '=')
		if idx < 0 {
			m[pair] = ""
		} else {
			m[pair[:idx]] = TsUnescape(pair[idx+1:])
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

func TsParseCommand(data []byte) (string, map[string]string) {
	end := len(data)
	for end > 0 && data[end-1] == 0 {
		end--
	}
	data = data[:end]
	spaceIdx := bytes.IndexByte(data, ' ')
	if spaceIdx < 0 {
		return string(data), make(map[string]string)
	}
	return string(data[:spaceIdx]), tsParseKV(string(data[spaceIdx+1:]))
}

func TsBuildC2SPacket(mac [8]byte, pID, cID uint16, pType byte, data []byte) []byte {
	pkt := make([]byte, 13+len(data))
	copy(pkt[:8], mac[:])
	binary.BigEndian.PutUint16(pkt[8:10], pID)
	binary.BigEndian.PutUint16(pkt[10:12], cID)
	pkt[12] = pType
	copy(pkt[13:], data)
	return pkt
}

func TsParseS2CPacket(raw []byte) (mac [8]byte, pID uint16, pType byte, data []byte, err error) {
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

func TsBuildInit0(version uint32, timestamp uint32, random0 [4]byte) []byte {
	data := make([]byte, 21)
	binary.BigEndian.PutUint32(data[0:4], version)
	data[4] = 0x00
	binary.BigEndian.PutUint32(data[5:9], timestamp)
	copy(data[9:13], random0[:])
	return TsBuildC2SPacket(tsInitMAC, 101, 0, tsFlagUnencrypted|tsPktInit, data)
}

func TsBuildInit2(version uint32, random1 [16]byte, random0r [4]byte) []byte {
	data := make([]byte, 25)
	binary.BigEndian.PutUint32(data[0:4], version)
	data[4] = 0x02
	copy(data[5:21], random1[:])
	copy(data[21:25], random0r[:])
	return TsBuildC2SPacket(tsInitMAC, 101, 0, tsFlagUnencrypted|tsPktInit, data)
}

func TsBuildInit4(version uint32, x, n [64]byte, level uint32, random2 [100]byte, y [64]byte, commandData []byte) []byte {
	data := make([]byte, 301+len(commandData))
	binary.BigEndian.PutUint32(data[0:4], version)
	data[4] = 0x04
	copy(data[5:69], x[:])
	copy(data[69:133], n[:])
	binary.BigEndian.PutUint32(data[133:137], level)
	copy(data[137:237], random2[:])
	copy(data[237:301], y[:])
	if len(commandData) > 0 {
		copy(data[301:], commandData)
	}
	return TsBuildC2SPacket(tsInitMAC, 101, 0, tsFlagUnencrypted|tsPktInit, data[:301+len(commandData)])
}

func TsParseInit1(data []byte) (random1 [16]byte, random0r [4]byte, err error) {
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

func TsParseInit3(data []byte) (x, n [64]byte, level uint32, random2 [100]byte, err error) {
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

type tsPacketState struct {
	nextSendID  uint16
	nextRecvID  uint16
	sendGenID   uint32
	recvGenID   uint32
	recvInit    bool
	lastRecvPID uint16
}

type TsPendingCmd struct {
	pktID  uint16
	data   []byte
	sentAt time.Time
	acked  bool
}

type TsDecryptedPkt struct {
	pID       uint16
	flags     byte
	plaintext []byte
}

type TsConnection struct {
	conn     *net.UDPConn
	addr     *net.UDPAddr
	identity *tsP256Identity
	owner    *TeamSpeakCore

	pktState [9]tsPacketState

	genMu sync.Mutex

	sharedIV  [64]byte
	sharedMAC [8]byte
	cryptoOK  bool
	clientID  atomic.Uint32

	recvQueue    [2]map[uint16]*TsDecryptedPkt
	recvQueueMu  sync.Mutex
	gapLogged    [2]bool
	gapLoggedFor [2]uint16

	fragBuf   [2][]byte
	fragFlags [2]byte

	pendingCmds  map[uint16]*TsPendingCmd
	pendingCmdMu sync.Mutex

	cmdCh chan TsIncomingCmd

	proofs chan TsProof

	execCh   chan TsIncomingCmd
	execMu   sync.Mutex
	execWait bool
	execSeq  sync.Mutex

	mu sync.Mutex
}

type TsIncomingCmd struct {
	name   string
	params map[string]string
	raw    string
}

type TeamSpeakCore struct {
	mu sync.RWMutex

	tsConn *TsConnection

	authed   bool
	nickname string

	serverAddr string

	myClientID int
	myUID      string
	myName     string

	myChannelID int
	myTalkPower int

	micMuted bool

	defaultChannelID int

	defaultChannelMu sync.RWMutex

	serverNameMu sync.RWMutex
	serverName   string

	session *utils.SessionStore

	updateHandlers []func(Update)
	eventHandlers  map[string][]func(map[string]string)
	updateMu       sync.RWMutex

	msgBuffer  map[string][]Message
	msgBufMu   sync.RWMutex
	msgCounter atomic.Int64

	clientInfo   map[int]TsClientInfo
	clientInfoMu sync.RWMutex

	channels   map[int]TsChannelInfo
	channelsMu sync.RWMutex

	voiceHandler   func(VoicePacket)
	voiceHandlerMu sync.RWMutex

	speakingMu    sync.Mutex
	speakingUntil map[int]time.Time

	bwStats tsBandwidthStats

	listener3D       ts3DListener
	client3DPos      map[int][3]float32
	wave3DPos        map[int][3]float32
	distanceFactor3D float32
	rolloffScale3D   float32

	playbackDevice     string
	captureDevice      string
	captureActive      bool
	preprocessorConfig map[string]string
	playbackConfig     map[string]string
	clientVolume       map[int]float32
	customDevices      map[string]tsCustomDevice
	waveNextHandle     int
	recording          bool

	whisperChannels []int
	whisperClients  []int

	bookmarks []map[string]string

	autoReconnect bool
	authCfg       AuthConfig

	ctx    context.Context
	cancel context.CancelFunc
	wg     sync.WaitGroup
}

var _ Core = (*TeamSpeakCore)(nil)

type VoicePacket struct {
	SenderClientID int
	Codec          byte
	AudioData      []byte
	PacketCounter  uint16
	IsWhisper      bool
	ServerFlag     byte
	HasServerFlag  bool
}

type TsClientInfo struct {
	clid      int
	dbid      int
	uid       string
	nickname  string
	channelID int
	isQuery   bool
}

type TsChannelInfo struct {
	cid            int
	pid            int
	name           string
	topic          string
	totalClients   int
	order          int
	talkPower      int
	talkPowerKnown bool
}

type tsSession struct {
	ServerAddr string `json:"server_address"`
	Nickname   string `json:"nickname,omitempty"`
	IdentityD  string `json:"identity_d,omitempty"`
	IdentityX  string `json:"identity_x,omitempty"`
	IdentityY  string `json:"identity_y,omitempty"`
	KeyOffset  uint64 `json:"key_offset,omitempty"`
}

func NewTeamSpeakCore(session *utils.SessionStore) *TeamSpeakCore {
	ctx, cancel := context.WithCancel(context.Background())
	return &TeamSpeakCore{
		session:       session,
		msgBuffer:     make(map[string][]Message),
		clientInfo:    make(map[int]TsClientInfo),
		channels:      make(map[int]TsChannelInfo),
		eventHandlers: make(map[string][]func(map[string]string)),
		ctx:           ctx,
		cancel:        cancel,
	}
}

func (t *TeamSpeakCore) Name() string { return ts3Platform }

func (t *TeamSpeakCore) Capabilities() []string {
	return []string{CapText, CapChannels, CapVoice, CapGroupCalls, CapVoiceRooms, CapAdmin, CapSessions, CapTyping}
}

func (tc *TsConnection) tsNextPktID(pType byte) uint16 {
	idx := pType & 0x0f
	id := tc.pktState[idx].nextSendID
	tc.pktState[idx].nextSendID++
	if tc.pktState[idx].nextSendID == 0 {
		tc.pktState[idx].sendGenID++
	}
	return id
}

func (tc *TsConnection) tsTrackRecvPID(pktType byte, pID uint16) uint32 {
	tc.genMu.Lock()
	defer tc.genMu.Unlock()
	idx := pktType & 0x0f
	st := &tc.pktState[idx]
	if !st.recvInit {
		st.recvInit = true
		st.lastRecvPID = pID
		return st.recvGenID
	}
	if pID == st.lastRecvPID {
		return st.recvGenID
	}
	switch {
	case pID > st.lastRecvPID:
		st.lastRecvPID = pID
	case st.lastRecvPID > 0xC000 && pID < 0x4000:
		st.recvGenID++
		st.lastRecvPID = pID
	default:
	}
	return st.recvGenID
}

func (tc *TsConnection) tsDecryptRecv(pktType byte, pID uint16, meta, data []byte, mac [8]byte) ([]byte, error) {
	gen := tc.tsTrackRecvPID(pktType, pID)
	key := tsRecvKey(pktType, pID, gen, tc.sharedIV[:])
	nonce := tsRecvNonce(pktType, pID, gen, tc.sharedIV[:])
	plain, err := TsEAXDecrypt(key[:], nonce[:], meta, data, mac)
	if err == nil {
		return plain, nil
	}
	for _, alt := range [...]uint32{gen + 1, func() uint32 {
		if gen > 0 {
			return gen - 1
		}
		return 0
	}()} {
		if alt == gen {
			continue
		}
		key = tsRecvKey(pktType, pID, alt, tc.sharedIV[:])
		nonce = tsRecvNonce(pktType, pID, alt, tc.sharedIV[:])
		plain, err = TsEAXDecrypt(key[:], nonce[:], meta, data, mac)
		if err == nil {
			if alt > gen {
				tc.genMu.Lock()
				tc.pktState[pktType&0x0f].recvGenID = alt
				tc.pktState[pktType&0x0f].lastRecvPID = pID
				tc.genMu.Unlock()
			}
			return plain, nil
		}
	}
	return nil, err
}

func tsRecvKey(pktType byte, pID uint16, gen uint32, iv []byte) (key [16]byte) {
	k, _ := TsCreateKeyNonce(pktType, pID, gen, 0x30, iv)
	return k
}

func tsRecvNonce(pktType byte, pID uint16, gen uint32, iv []byte) (nonce [16]byte) {
	_, n := TsCreateKeyNonce(pktType, pID, gen, 0x30, iv)
	return n
}

var tsDebug = os.Getenv("UNICLIENT_TS3_DEBUG") != ""

func tsLogf(format string, args ...interface{}) {
	if tsDebug {
		fmt.Printf("[TS3] "+format+"\n", args...)
	}
}

func TsRedactCmd(cmd string) string {
	for pos := 0; ; {
		rel := strings.Index(cmd[pos:], "cpw=")
		if rel < 0 {
			return cmd
		}
		i := pos + rel
		j := i + 4
		for j < len(cmd) && cmd[j] != ' ' {
			j++
		}
		cmd = cmd[:i+4] + "<redacted>" + cmd[j:]
		pos = i + 4 + len("<redacted>")
	}
}

func (tc *TsConnection) tsSendRaw(pkt []byte) error {
	if tsDebug && len(pkt) >= 12 {
		pt := pkt[12]
		pID := binary.BigEndian.Uint16(pkt[8:10])
		cID := binary.BigEndian.Uint16(pkt[10:12])
		preview := pkt[13:]
		if len(preview) > 24 {
			preview = preview[:24]
		}
		tsLogf("TX type=0x%02x pID=%d cID=%d len=%d data=%x", pt, pID, cID, len(pkt)-13, preview)
	}
	_, err := tc.conn.WriteToUDP(pkt, tc.addr)
	return err
}

func (tc *TsConnection) tsSendCommand(cmdStr string) (uint16, error) {
	tc.mu.Lock()
	defer tc.mu.Unlock()

	cmdBytes := []byte(cmdStr)
	tsLogf("TX cmd: %s", TsRedactCmd(cmdStr))

	compressed := false
	if len(cmdBytes) > TsMaxPayloadC2S {
		if qz, ok := TsQuickLZCompress(cmdBytes); ok && len(qz) < len(cmdBytes) {
			cmdBytes = qz
			compressed = true
		}
	}

	if len(cmdBytes) <= TsMaxPayloadC2S {
		pID := tc.tsNextPktID(TsPktCommand)
		flags := byte(TsPktCommand) | TsFlagNewprotocol
		if compressed {
			flags |= TsFlagCompressed
		}
		var meta [5]byte
		binary.BigEndian.PutUint16(meta[0:2], pID)
		binary.BigEndian.PutUint16(meta[2:4], uint16(tc.clientID.Load()))
		meta[4] = flags

		var mac [8]byte
		var ciphertext []byte
		if tc.cryptoOK {
			key, nonce := TsCreateKeyNonce(TsPktCommand, pID, tc.pktState[TsPktCommand].sendGenID, 0x31, tc.sharedIV[:])
			mac, ciphertext = TsEAXEncrypt(key[:], nonce[:], meta[:], cmdBytes)
		} else {
			mac, ciphertext = TsEAXEncrypt(TsFakeKey[:], TsFakeNonce[:], meta[:], cmdBytes)
		}

		pkt := TsBuildC2SPacket(mac, pID, uint16(tc.clientID.Load()), flags, ciphertext)

		tc.pendingCmdMu.Lock()
		tc.pendingCmds[pID] = &TsPendingCmd{pktID: pID, data: pkt, sentAt: time.Now()}
		tc.pendingCmdMu.Unlock()

		if tc.owner != nil {
			tc.owner.bwStats.recordSent(TsPktCommand, len(pkt))
		}
		if err := tc.tsSendRaw(pkt); err != nil {
			return 0, err
		}
		return pID, nil
	}

	numChunks := (len(cmdBytes) + TsMaxPayloadC2S - 1) / TsMaxPayloadC2S
	chunks := make([][]byte, 0, numChunks)
	remaining := cmdBytes
	for len(remaining) > 0 {
		chunkSize := TsMaxPayloadC2S
		if chunkSize > len(remaining) {
			chunkSize = len(remaining)
		}
		chunks = append(chunks, remaining[:chunkSize])
		remaining = remaining[chunkSize:]
	}

	var firstPID uint16
	for i, chunk := range chunks {
		pID := tc.tsNextPktID(TsPktCommand)
		if i == 0 {
			firstPID = pID
		}

		flags := byte(TsPktCommand) | TsFlagNewprotocol
		if i == 0 || i == len(chunks)-1 {
			flags |= TsFlagFragmented
		}
		if i == 0 && compressed {
			flags |= TsFlagCompressed
		}

		var meta [5]byte
		binary.BigEndian.PutUint16(meta[0:2], pID)
		binary.BigEndian.PutUint16(meta[2:4], uint16(tc.clientID.Load()))
		meta[4] = flags

		var mac [8]byte
		var ciphertext []byte
		if tc.cryptoOK {
			key, nonce := TsCreateKeyNonce(TsPktCommand, pID, tc.pktState[TsPktCommand].sendGenID, 0x31, tc.sharedIV[:])
			mac, ciphertext = TsEAXEncrypt(key[:], nonce[:], meta[:], chunk)
		} else {
			mac, ciphertext = TsEAXEncrypt(TsFakeKey[:], TsFakeNonce[:], meta[:], chunk)
		}

		pkt := TsBuildC2SPacket(mac, pID, uint16(tc.clientID.Load()), flags, ciphertext)

		tc.pendingCmdMu.Lock()
		tc.pendingCmds[pID] = &TsPendingCmd{pktID: pID, data: pkt, sentAt: time.Now()}
		tc.pendingCmdMu.Unlock()

		if err := tc.tsSendRaw(pkt); err != nil {
			return 0, err
		}
	}
	return firstPID, nil
}

func (tc *TsConnection) tsSendAck(pID uint16) error {
	tc.mu.Lock()
	defer tc.mu.Unlock()

	var ackData [2]byte
	binary.BigEndian.PutUint16(ackData[:], pID)

	ackPID := tc.tsNextPktID(tsPktAck)
	flags := byte(tsPktAck)

	var meta [5]byte
	binary.BigEndian.PutUint16(meta[0:2], ackPID)
	binary.BigEndian.PutUint16(meta[2:4], uint16(tc.clientID.Load()))
	meta[4] = flags

	if tc.cryptoOK {
		key, nonce := TsCreateKeyNonce(tsPktAck, ackPID, tc.pktState[tsPktAck].sendGenID, 0x31, tc.sharedIV[:])
		mac, ciphertext := TsEAXEncrypt(key[:], nonce[:], meta[:], ackData[:])
		pkt := TsBuildC2SPacket(mac, ackPID, uint16(tc.clientID.Load()), flags, ciphertext)
		return tc.tsSendRaw(pkt)
	}

	mac, ciphertext := TsEAXEncrypt(TsFakeKey[:], TsFakeNonce[:], meta[:], ackData[:])
	pkt := TsBuildC2SPacket(mac, ackPID, uint16(tc.clientID.Load()), flags, ciphertext)
	return tc.tsSendRaw(pkt)
}

func (tc *TsConnection) tsSendPing() error {
	tc.mu.Lock()
	defer tc.mu.Unlock()

	pID := tc.tsNextPktID(tsPktPing)
	flags := byte(tsPktPing) | tsFlagUnencrypted
	pkt := TsBuildC2SPacket(tc.sharedMAC, pID, uint16(tc.clientID.Load()), flags, nil)
	return tc.tsSendRaw(pkt)
}

func (tc *TsConnection) tsSendPong(pingID uint16) error {
	tc.mu.Lock()
	defer tc.mu.Unlock()

	var pongData [2]byte
	binary.BigEndian.PutUint16(pongData[:], pingID)

	pID := tc.tsNextPktID(tsPktPong)
	flags := byte(tsPktPong) | tsFlagUnencrypted
	pkt := TsBuildC2SPacket(tc.sharedMAC, pID, uint16(tc.clientID.Load()), flags, pongData[:])
	return tc.tsSendRaw(pkt)
}

func (tc *TsConnection) tsReceiveLoop(ctx context.Context) {

	for {
		select {
		case <-ctx.Done():
			return
		default:
		}

		tc.conn.SetReadDeadline(time.Now().Add(tsReadTimeout))
		buf := make([]byte, 2048)
		n, _, err := tc.conn.ReadFromUDP(buf)
		if err != nil {
			if netErr, ok := err.(net.Error); ok && netErr.Timeout() {
				continue
			}
			if tc.owner != nil {
				tc.owner.tsHandleConnectionLost(fmt.Errorf("%w: %v", ErrDisconnected, err))
			}
			return
		}

		go tc.tsHandlePacket(buf[:n])
	}
}

func (tc *TsConnection) tsHandlePacket(raw []byte) {
	mac, pID, pType, data, err := TsParseS2CPacket(raw)
	if err != nil {
		tsLogf("RX parse error: %v", err)
		return
	}

	flags := pType & 0xf0
	packetType := pType & 0x0f

	preview := data
	if len(preview) > 24 {
		preview = preview[:24]
	}
	tsLogf("RX type=0x%02x pID=%d len=%d mac=%x data=%x", pType, pID, len(data), mac[:4], preview)

	if tc.owner != nil {
		tc.owner.bwStats.recordRecv(packetType, len(raw))
	}

	switch packetType {
	case TsPktCommand, tsPktCommandLow:
		var plaintext []byte
		meta := raw[8:11]

		if flags&tsFlagUnencrypted != 0 {
			plaintext = data
		} else if tc.cryptoOK {
			plaintext, err = tc.tsDecryptRecv(packetType, pID, meta, data, mac)
			if err != nil {
				tsLogf("RX cmd decrypt FAIL pID=%d type=0x%02x err=%v", pID, pType, err)
				return
			}
		} else {
			plaintext, err = TsEAXDecrypt(TsFakeKey[:], TsFakeNonce[:], meta, data, mac)
			if err != nil {
				tsLogf("RX cmd fake decrypt FAIL pID=%d err=%v", pID, err)
				return
			}
		}

		tc.tsSendAck(pID)

		cmdI := 0
		if packetType == tsPktCommandLow {
			cmdI = 1
		}
		tc.recvQueueMu.Lock()
		tc.recvQueue[cmdI][pID] = &TsDecryptedPkt{pID: pID, flags: byte(flags) | byte(packetType), plaintext: plaintext}
		tc.tsProcessCommandQueue(cmdI)
		tc.recvQueueMu.Unlock()

	case tsPktAck:
		if len(data) >= 2 {
			var ackPlain []byte
			meta := raw[8:11]

			if flags&tsFlagUnencrypted != 0 {
				ackPlain = data
			} else if pID <= 1 {
				ackPlain, err = TsEAXDecrypt(TsFakeKey[:], TsFakeNonce[:], meta, data, mac)
				if err != nil && tc.cryptoOK {
					ackPlain, err = tc.tsDecryptRecv(tsPktAck, pID, meta, data, mac)
				}
			} else if tc.cryptoOK {
				ackPlain, err = tc.tsDecryptRecv(tsPktAck, pID, meta, data, mac)
			} else {
				ackPlain, err = TsEAXDecrypt(TsFakeKey[:], TsFakeNonce[:], meta, data, mac)
			}
			if err != nil || len(ackPlain) < 2 {
				tsLogf("RX ack decrypt FAIL pID=%d err=%v", pID, err)
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
		tc.tsSendPong(pID)

	case tsPktPong:

	case tsPktInit:

	case TsPktVoice, tsPktVoiceWhisper:
		var plaintext []byte
		meta := raw[8:11]

		if flags&tsFlagUnencrypted != 0 {
			plaintext = data
		} else if tc.cryptoOK {
			key, nonce := TsCreateKeyNonce(packetType, pID, tc.pktState[packetType].recvGenID, 0x30, tc.sharedIV[:])
			plaintext, err = TsEAXDecrypt(key[:], nonce[:], meta, data, mac)
			if err != nil {
				tsLogf("VOICE decrypt fail pID=%d len=%d: %v", pID, len(data), err)
				return
			}
		} else {
			tsLogf("VOICE no crypto for voice pID=%d", pID)
			return
		}

		tc.owner.tsHandleVoicePacket(packetType, byte(flags), plaintext)
	}
}

func (tc *TsConnection) tsProcessCommandQueue(cmdI int) {
	pktType := TsPktCommand
	if cmdI == 1 {
		pktType = tsPktCommandLow
	}

	for {
		nextID := tc.pktState[pktType].nextRecvID
		pkt, ok := tc.recvQueue[cmdI][nextID]
		if !ok {
			if len(tc.recvQueue[cmdI]) > 0 {
				if !tc.gapLogged[cmdI] || tc.gapLoggedFor[cmdI] != nextID {
					keys := make([]uint16, 0, len(tc.recvQueue[cmdI]))
					for k := range tc.recvQueue[cmdI] {
						keys = append(keys, k)
					}
					log.Printf("ts: waiting for command packet %d; queued out-of-order: %v", nextID, keys)
					tc.gapLogged[cmdI] = true
					tc.gapLoggedFor[cmdI] = nextID
				}
			}
			return
		}
		delete(tc.recvQueue[cmdI], nextID)

		tc.pktState[pktType].nextRecvID++
		tc.gapLogged[cmdI] = false

		flags := pkt.flags & 0xf0
		plaintext := pkt.plaintext

		hasFR := flags&TsFlagFragmented != 0
		if hasFR && tc.fragBuf[cmdI] == nil {
			tc.fragBuf[cmdI] = make([]byte, 0, 4096)
			tc.fragFlags[cmdI] = flags
			tc.fragBuf[cmdI] = append(tc.fragBuf[cmdI], plaintext...)

			continue
		} else if tc.fragBuf[cmdI] != nil && !hasFR {
			tc.fragBuf[cmdI] = append(tc.fragBuf[cmdI], plaintext...)

			continue
		} else if tc.fragBuf[cmdI] != nil && hasFR {
			tc.fragBuf[cmdI] = append(tc.fragBuf[cmdI], plaintext...)
			assembled := tc.fragBuf[cmdI]
			firstFlags := tc.fragFlags[cmdI]
			tc.fragBuf[cmdI] = nil

			if firstFlags&TsFlagCompressed != 0 {
				decompressed, err := TsQuickLZDecompress(assembled)
				if err != nil {
					tsLogf("FRAG decompress FAIL: %v", err)
					continue
				}

				assembled = decompressed
			}

			plaintext = assembled
		} else {
			if flags&TsFlagCompressed != 0 {
				decompressed, err := TsQuickLZDecompress(plaintext)
				if err != nil {
					tsLogf("RX decompress FAIL pID=%d: %v", pkt.pID, err)
					continue
				}
				plaintext = decompressed
			}
		}

		lines := bytes.Split(plaintext, []byte("\n"))
		for _, line := range lines {
			line = bytes.TrimRight(line, "\x00\r\n")
			if len(line) == 0 {
				continue
			}
			name, params := TsParseCommand(line)
			tsLogf("RX cmd: %s", line)
			select {
			case tc.cmdCh <- TsIncomingCmd{name: name, params: params, raw: string(line)}:
			default:
				tsLogf("CMD cmdCh FULL, dropping: %s", name)
			}
		}
	}
}

func (tc *TsConnection) tsKeepaliveLoop(ctx context.Context) {
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

	tc := &TsConnection{
		conn:        conn,
		addr:        udpAddr,
		identity:    nil,
		owner:       t,
		pendingCmds: make(map[uint16]*TsPendingCmd),
		recvQueue:   [2]map[uint16]*TsDecryptedPkt{make(map[uint16]*TsDecryptedPkt), make(map[uint16]*TsDecryptedPkt)},
		cmdCh:       make(chan TsIncomingCmd, 64),
		proofs:      make(chan TsProof, 8),
	}

	for i := 0; i < 9; i++ {
		tc.pktState[i].nextSendID = 0
		tc.pktState[i].nextRecvID = 0
	}

	t.tsConn = tc
	return nil
}

func (t *TeamSpeakCore) tsHandshake(nickname string) error {
	return t.tsHandshakeRetry(nickname, 5)
}

func (t *TeamSpeakCore) tsHandshakeRetry(nickname string, restartsLeft int) error {
	tc := t.tsConn

	if tc.identity == nil {
		id, err := TsNewIdentity()
		if err != nil {
			return fmt.Errorf("identity gen failed: %w", err)
		}
		tc.identity = id
	}

	version := uint32(TsInitVersion)
	timestamp := uint32(time.Now().Unix())

	var random0 [4]byte
	rand.Read(random0[:])

	cancelRecv := func() {}

	var random1 [16]byte
	var random0r [4]byte

	for attempt := 0; attempt < 5; attempt++ {
		init0 := TsBuildInit0(version, timestamp, random0)
		if err := tc.tsSendRaw(init0); err != nil {
			cancelRecv()
			return fmt.Errorf("%w: init0 send: %v", ErrNetwork, err)
		}

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
		mac, _, pType, data, err := TsParseS2CPacket(rawPkt)
		if err != nil || pType&0x0f != tsPktInit {
			if attempt < 4 {
				continue
			}
			cancelRecv()
			return fmt.Errorf("%w: unexpected response to init0 (ptype=0x%02x, len=%d, mac=%x)", ErrNetwork, pType, n, mac)
		}

		if mac != tsInitMAC {
			if attempt < 4 {
				continue
			}
			cancelRecv()
			return fmt.Errorf("%w: init response has wrong MAC: %x", ErrNetwork, mac)
		}

		random1, random0r, err = TsParseInit1(data)
		if err != nil {
			if attempt < 4 {
				continue
			}
			cancelRecv()
			return fmt.Errorf("%w: init1 parse (data len=%d, data=%x): %v", ErrNetwork, len(data), data, err)
		}
		break
	}

	init2 := TsBuildInit2(version, random1, random0r)
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
				tc.tsSendRaw(init2)
				continue
			}
			cancelRecv()
			return fmt.Errorf("%w: no init3 response: %v", ErrNetwork, err)
		}

		_, _, pType, data, err := TsParseS2CPacket(buf[:nRead])
		if err != nil || pType&0x0f != tsPktInit {
			continue
		}

		x, n, level, random2, err = TsParseInit3(data)
		if err != nil {
			if strings.Contains(err.Error(), "step 127") {
				cancelRecv()
				if restartsLeft <= 1 {
					return fmt.Errorf("%w: server keeps requesting handshake restart (step 127)", ErrNetwork)
				}
				time.Sleep(1 * time.Second)
				return t.tsHandshakeRetry(nickname, restartsLeft-1)
			}
			if attempt < 4 {
				continue
			}
			cancelRecv()
			return fmt.Errorf("%w: init3 parse: %v", ErrNetwork, err)
		}
		break
	}

	xBig := new(big.Int).SetBytes(x[:])
	nBig := new(big.Int).SetBytes(n[:])
	eBig := new(big.Int).Lsh(big.NewInt(1), uint(level))
	yBig := new(big.Int).Exp(xBig, eBig, nBig)

	var yBytes [64]byte
	yRaw := yBig.Bytes()
	copy(yBytes[64-len(yRaw):], yRaw)

	var alpha [10]byte
	rand.Read(alpha[:])
	alphaB64 := base64.StdEncoding.EncodeToString(alpha[:])
	omega := tc.identity.tsOmega()

	ip := tc.addr.IP.String()
	clientinitiv := fmt.Sprintf("clientinitiv alpha=%s omega=%s ot=1 ip=%s",
		TsEscape(alphaB64), TsEscape(omega), TsEscape(ip))

	init4 := TsBuildInit4(version, x, n, level, random2, yBytes, []byte(clientinitiv))
	if err := tc.tsSendRaw(init4); err != nil {
		cancelRecv()
		return fmt.Errorf("%w: init4 send: %v", ErrNetwork, err)
	}

	var initivCmd TsIncomingCmd
	var fragBuf []byte
	var fragmenting bool
	maxCmdPID := uint16(0)
	for attempt := 0; attempt < 20; attempt++ {
		buf := make([]byte, 4096)
		tc.conn.SetReadDeadline(time.Now().Add(5 * time.Second))
		nRead, _, err := tc.conn.ReadFromUDP(buf)
		if err != nil {
			continue
		}

		mac, pID, pType, data, err := TsParseS2CPacket(buf[:nRead])
		if err != nil {
			continue
		}

		pktType := pType & 0x0f
		flags := pType & 0xf0
		if pktType == TsPktCommand {
			meta := buf[8:11]
			plaintext, err := TsEAXDecrypt(TsFakeKey[:], TsFakeNonce[:], meta, data, mac)
			if err != nil {
				continue
			}

			ackData := make([]byte, 2)
			binary.BigEndian.PutUint16(ackData, pID)
			ackPID := tc.tsNextPktID(tsPktAck)
			ackMeta := make([]byte, 5)
			binary.BigEndian.PutUint16(ackMeta[0:2], ackPID)
			binary.BigEndian.PutUint16(ackMeta[2:4], 0)
			ackMeta[4] = tsPktAck
			ackMAC, ackCipher := TsEAXEncrypt(TsFakeKey[:], TsFakeNonce[:], ackMeta, ackData)
			ackPkt := TsBuildC2SPacket(ackMAC, ackPID, 0, tsPktAck, ackCipher)
			tc.tsSendRaw(ackPkt)

			if pID > maxCmdPID {
				maxCmdPID = pID
			}

			isFragmented := flags&TsFlagFragmented != 0
			if isFragmented && !fragmenting {
				fragmenting = true
				fragBuf = append([]byte{}, plaintext...)
				continue
			} else if fragmenting && !isFragmented {
				fragBuf = append(fragBuf, plaintext...)
				continue
			} else if fragmenting && isFragmented {
				fragBuf = append(fragBuf, plaintext...)
				plaintext = fragBuf
				fragmenting = false
			}

			name, params := TsParseCommand(plaintext)
			initivCmd = TsIncomingCmd{name: name, params: params, raw: string(plaintext)}
			break
		} else if pktType == tsPktPing {
			_ = tc.tsSendPong(pID)
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

	lB64 := initivCmd.params["l"]
	betaB64 := initivCmd.params["beta"]
	serverOmega := initivCmd.params["omega"]
	proofB64 := initivCmd.params["proof"]

	if lB64 == "" || betaB64 == "" || serverOmega == "" || proofB64 == "" {
		cancelRecv()
		return fmt.Errorf("%w: initivexpand2 missing params", ErrNetwork)
	}

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

	serverX, serverY, err := TsParseOmega(serverOmega)
	if err != nil {
		cancelRecv()
		return fmt.Errorf("parse server omega: %w", err)
	}
	if !TsVerifyP256(serverX, serverY, licenseData, proofBytes) {
		cancelRecv()
		return fmt.Errorf("%w: license proof verification failed", ErrAuth)
	}

	rootKey := TsRootKey
	if rootB64 := initivCmd.params["root"]; rootB64 != "" {
		rootBytes, err := base64.StdEncoding.DecodeString(rootB64)
		if err == nil && len(rootBytes) == 32 {
			copy(rootKey[:], rootBytes)
		}
	}

	serverEK, err := TsDeriveLicenseKey(licenseData, rootKey)
	if err != nil {
		cancelRecv()
		return fmt.Errorf("license key derivation: %w", err)
	}

	var ekPrivBytes [32]byte
	rand.Read(ekPrivBytes[:])
	ekPrivScalar, err := new(edwards25519.Scalar).SetBytesWithClamping(ekPrivBytes[:])
	if err != nil {
		cancelRecv()
		return fmt.Errorf("ed25519 scalar: %w", err)
	}
	ekPub := new(edwards25519.Point).ScalarBaseMult(ekPrivScalar)

	var betaArr [54]byte
	copy(betaArr[:], betaBytes)
	sharedIV, sharedMAC := TsComputeSharedIVMAC(alpha, betaArr, ekPrivScalar, serverEK)
	tc.sharedIV = sharedIV
	tc.sharedMAC = sharedMAC
	tc.cryptoOK = true

	tc.pktState[TsPktCommand].nextSendID = 1

	ekPubB64 := base64.StdEncoding.EncodeToString(ekPub.Bytes())

	proofData := make([]byte, 32+54)
	copy(proofData[:32], ekPub.Bytes())
	copy(proofData[32:], betaBytes)
	ekProof, err := tc.identity.tsSign(proofData)
	if err != nil {
		return fmt.Errorf("ek proof sign: %w", err)
	}
	ekProofB64 := base64.StdEncoding.EncodeToString(ekProof)

	clientekStr := fmt.Sprintf("clientek ek=%s proof=%s", TsEscape(ekPubB64), TsEscape(ekProofB64))
	{
		cmdBytes := []byte(clientekStr)
		pID := tc.tsNextPktID(TsPktCommand)
		flags := byte(TsPktCommand) | TsFlagNewprotocol
		meta := make([]byte, 5)
		binary.BigEndian.PutUint16(meta[0:2], pID)
		binary.BigEndian.PutUint16(meta[2:4], uint16(tc.clientID.Load()))
		meta[4] = flags
		mac, ciphertext := TsEAXEncrypt(TsFakeKey[:], TsFakeNonce[:], meta, cmdBytes)
		pkt := TsBuildC2SPacket(mac, pID, uint16(tc.clientID.Load()), flags, ciphertext)
		if err := tc.tsSendRaw(pkt); err != nil {
			return fmt.Errorf("clientek send: %w", err)
		}
	}

	tc.pktState[TsPktCommand].nextRecvID = maxCmdPID + 1
	tc.pktState[tsPktAck].nextRecvID = 0

	t.wg.Add(2)
	go func() {
		defer t.wg.Done()
		tc.tsReceiveLoop(t.ctx)
	}()
	go func() {
		defer t.wg.Done()
		tc.tsKeepaliveLoop(t.ctx)
	}()

	hwid := "123456789abcdef0123456789abcdef0"
	keyOffset := fmt.Sprintf("%d", tc.identity.keyOffset)
	clientinitCmd := fmt.Sprintf(
		"clientinit client_nickname=%s client_version=%s client_platform=%s client_input_hardware=1 client_output_hardware=1 client_default_channel= client_default_channel_password= client_server_password= client_meta_data= client_version_sign=%s client_key_offset=%s client_nickname_phonetic= client_default_token= hwid=%s",
		TsEscape(nickname),
		TsEscape(tsVersionStr),
		TsEscape(tsPlatform),
		TsEscape(tsVersionSign),
		TsEscape(keyOffset),
		TsEscape(hwid),
	)

	_, err = tc.tsSendCommand(clientinitCmd)
	if err != nil {
		return fmt.Errorf("clientinit send: %w", err)
	}

	initDeadline := time.After(10 * time.Second)
	var gotInitServer bool
	for !gotInitServer {
		select {
		case cmd := <-tc.cmdCh:
			if cmd.name == "initserver" {
				if cidStr := cmd.params["aclid"]; cidStr != "" {
					cid, err := strconv.Atoi(cidStr)
					if err == nil {
						tc.clientID.Store(uint32(cid))
						t.clientInfoMu.Lock()
						t.myClientID = cid
						t.clientInfoMu.Unlock()
					}
				}
				t.clientInfoMu.Lock()
				t.myName = nickname
				t.clientInfoMu.Unlock()
				gotInitServer = true
			} else if cmd.name == "error" {
				errID, err := strconv.Atoi(cmd.params["id"])
				if err != nil {
					return fmt.Errorf("%w: invalid error id %q", ErrNetwork, cmd.params["id"])
				}
				if errID != 0 {
					return fmt.Errorf("%w: server error: %s (id=%d)", ErrAuth, cmd.params["msg"], errID)
				}
			} else {
				t.TsHandleServerCommand(cmd)
			}
		case <-initDeadline:
			return fmt.Errorf("%w: timeout waiting for initserver", ErrNetwork)
		case <-t.ctx.Done():
			return fmt.Errorf("%w: context cancelled", ErrNetwork)
		}
	}

	if tc.identity != nil {
		t.myUID = tc.identity.tsUID()
	}

	drainTimer := time.After(2 * time.Second)
drainLoop:
	for {
		select {
		case cmd := <-tc.cmdCh:
			if cmd.name == "error" {
			} else {
				t.TsHandleServerCommand(cmd)
			}
			if cmd.name == "channellistfinished" {
				drainTimer = time.After(500 * time.Millisecond)
			}
		case <-drainTimer:
			break drainLoop
		}
	}

	return nil
}

func (t *TeamSpeakCore) ServerName() string {
	t.serverNameMu.RLock()
	defer t.serverNameMu.RUnlock()
	return t.serverName
}

func (t *TeamSpeakCore) setServerName(name string) {
	if name == "" {
		return
	}
	t.serverNameMu.Lock()
	t.serverName = name
	t.serverNameMu.Unlock()
}

func (t *TeamSpeakCore) TsHandleServerCommand(cmd TsIncomingCmd) {
	switch cmd.name {
	case "initserver":
		if v := cmd.params["virtualserver_name"]; v != "" {
			t.setServerName(v)
		}
	case "notifytextmessage":
		t.tsHandleTextMessage(cmd.params)
	case "notifycliententerview":
		t.tsHandleClientEnter(cmd.params)
	case "notifyclientleftview":
		if tc := t.tsConn; tc != nil {
			tc.fireProof("notifyclientleftview", cmd.params)
		}
		t.tsHandleClientLeave(cmd.params)
	case "notifyclientmoved":
		if tc := t.tsConn; tc != nil {
			tc.fireProof("notifyclientmoved", cmd.params)
		}
		t.TsHandleClientMoved(cmd.params)
	case "channellist":
		rawData := cmd.raw
		if idx := strings.Index(rawData, " "); idx >= 0 {
			rawData = rawData[idx+1:]
		}
		entries := tsParseKVList(rawData)
		t.channelsMu.Lock()
		for _, e := range entries {
			cid, err := strconv.Atoi(e["cid"])
			if err != nil {
				continue
			}
			pid, _ := strconv.Atoi(e["pid"])
			tc, _ := strconv.Atoi(e["total_clients"])
			order, _ := strconv.Atoi(e["channel_order"])
			ch := TsChannelInfo{
				cid:          cid,
				pid:          pid,
				name:         e["channel_name"],
				topic:        e["channel_topic"],
				totalClients: tc,
				order:        order,
			}
			t.channels[cid] = ch
			if e["channel_flag_default"] == "1" {
				t.defaultChannelMu.Lock()
				t.defaultChannelID = cid
				t.defaultChannelMu.Unlock()
			}
		}
		t.channelsMu.Unlock()
	case "channellistfinished":
	case "notifychannelcreated":
		if tc := t.tsConn; tc != nil {
			tc.fireProof("notifychannelcreated", cmd.params)
		}
		cid, err := strconv.Atoi(cmd.params["cid"])
		if err != nil {
			return
		}
		pid, _ := strconv.Atoi(cmd.params["cpid"])
		order, _ := strconv.Atoi(cmd.params["channel_order"])
		t.channelsMu.Lock()
		t.channels[cid] = TsChannelInfo{
			cid:   cid,
			pid:   pid,
			name:  cmd.params["channel_name"],
			topic: cmd.params["channel_topic"],
			order: order,
		}
		t.channelsMu.Unlock()
		t.fireUpdate(Update{
			Type:     UpdateGroupMembers,
			Platform: ts3Platform,
		})
	case "notifychanneldeleted":
		cid, err := strconv.Atoi(cmd.params["cid"])
		if err != nil {
			return
		}
		t.channelsMu.Lock()
		delete(t.channels, cid)
		t.channelsMu.Unlock()
		t.fireUpdate(Update{
			Type:     UpdateGroupMembers,
			Platform: ts3Platform,
		})
	case "notifychanneledited", "notifychannelmoved":
		if tc := t.tsConn; tc != nil {
			tc.fireProof(cmd.name, cmd.params)
		}
		cid, err := strconv.Atoi(cmd.params["cid"])
		if err != nil {
			return
		}
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
		t.fireUpdate(Update{
			Type:     UpdateGroupMembers,
			Platform: ts3Platform,
		})
	case "notifyclientupdated":
		clid, err := strconv.Atoi(cmd.params["clid"])
		if err != nil {
			return
		}
		if tc := t.tsConn; tc != nil {
			tc.fireProof("notifyclientupdated", cmd.params)
		}
		t.clientInfoMu.Lock()
		if clid == t.myClientID {
			if v, perr := strconv.Atoi(cmd.params["client_talk_power"]); perr == nil {
				t.myTalkPower = v
			}
		}
		if info, ok := t.clientInfo[clid]; ok {
			if v := cmd.params["client_nickname"]; v != "" {
				info.nickname = v
			}
			t.clientInfo[clid] = info
		}
		t.clientInfoMu.Unlock()
	case "notifyclientpoke":
		invokerID, err := strconv.Atoi(cmd.params["invokerid"])
		if err != nil {
			return
		}
		msg := Message{
			ID:         t.tsNextMsgID(),
			ChatID:     fmt.Sprintf("dm:%d", invokerID),
			SenderID:   strconv.Itoa(invokerID),
			SenderName: cmd.params["invokername"],
			Text:       "[poke] " + cmd.params["msg"],
			Timestamp:  time.Now(),
			Status:     MessageStatusDelivered,
			IsOutgoing: false,
			Platform:   ts3Platform,
		}
		t.tsAddMessage(msg.ChatID, &msg)
		t.fireUpdate(Update{
			Type:     UpdateNewMessage,
			ChatID:   msg.ChatID,
			Message:  &msg,
			Platform: ts3Platform,
		})
	case "notifyconnectioninforequest":
		go t.SetConnectionInfo()
	case "notifychanneldescriptionchanged":
		t.fireUpdate(Update{
			Type:     UpdateGroupMembers,
			Platform: ts3Platform,
		})
	case "notifychannelpasswordchanged":
	case "notifychannelsubscribed":
		cid, err := strconv.Atoi(cmd.params["cid"])
		if err != nil {
			return
		}
		t.fireUpdate(Update{
			Type:     UpdateGroupMembers,
			ChatID:   fmt.Sprintf("ch:%d", cid),
			Platform: ts3Platform,
		})
	case "notifychannelunsubscribed":
		cid, err := strconv.Atoi(cmd.params["cid"])
		if err != nil {
			return
		}
		t.fireUpdate(Update{
			Type:     UpdateGroupMembers,
			ChatID:   fmt.Sprintf("ch:%d", cid),
			Platform: ts3Platform,
		})
	case "notifyserveredited", "notifyserverupdated":
		t.fireUpdate(Update{
			Type:     UpdateGroupMembers,
			Platform: ts3Platform,
		})
	case "notifyservergroupclientadded", "notifyservergroupclientdeleted":
		t.fireUpdate(Update{
			Type:     UpdateGroupMembers,
			Platform: ts3Platform,
		})
	case "notifytokenused":
	case "notifyclientchannelgroupchanged":
		t.fireUpdate(Update{
			Type:     UpdateGroupMembers,
			Platform: ts3Platform,
		})
	case "notifyclientneededpermissions":
	case "notifyclientchatcomposing":
		if tc := t.tsConn; tc != nil {
			tc.fireProof("notifyclientchatcomposing", cmd.params)
		}
		clid, err := strconv.Atoi(cmd.params["clid"])
		if err != nil {
			return
		}
		t.fireUpdate(Update{
			Type:     UpdateTyping,
			ChatID:   fmt.Sprintf("dm:%d", clid),
			UserID:   strconv.Itoa(clid),
			Platform: ts3Platform,
		})
	case "notifyclientchatclosed":
	case "notifyplugincommand":
		invokerID, err := strconv.Atoi(cmd.params["invokerid"])
		if err != nil {
			return
		}
		msg := Message{
			ID:         t.tsNextMsgID(),
			ChatID:     fmt.Sprintf("dm:%d", invokerID),
			SenderID:   strconv.Itoa(invokerID),
			SenderName: cmd.params["invokername"],
			Text:       "[plugin:" + cmd.params["name"] + "] " + cmd.params["data"],
			Timestamp:  time.Now(),
			Status:     MessageStatusDelivered,
			IsOutgoing: false,
			Platform:   ts3Platform,
		}
		t.tsAddMessage(msg.ChatID, &msg)
		t.fireUpdate(Update{
			Type:     UpdateNewMessage,
			ChatID:   msg.ChatID,
			Message:  &msg,
			Platform: ts3Platform,
		})
	}

	t.updateMu.RLock()
	handlers := t.eventHandlers[cmd.name]
	t.updateMu.RUnlock()
	for _, h := range handlers {
		h(cmd.params)
	}
}

func (t *TeamSpeakCore) tsCommandLoop() {
	tc := t.tsConn
	for {
		select {
		case <-t.ctx.Done():
			return
		case cmd := <-tc.cmdCh:
			tc.execMu.Lock()
			if tc.execWait {
				tc.execCh <- cmd
				tc.execMu.Unlock()
			} else {
				tc.execMu.Unlock()
				t.TsHandleServerCommand(cmd)
			}
		}
	}
}

var TsExecVoidTimeout = 5 * time.Second

type TsProof struct {
	name   string
	fields map[string]string
}

type TsWant struct {
	name string
	key  string
	val  string
}

func (tc *TsConnection) fireProof(name string, fields map[string]string) {
	select {
	case tc.proofs <- TsProof{name: name, fields: fields}:
	default:
	}
}

func (tc *TsConnection) takeProofs() bool {
	select {
	case <-tc.proofs:
		return true
	default:
		return false
	}
}

func (t *TeamSpeakCore) TsExecVerified(cmd string, verify func() (bool, error)) ([]map[string]string, error) {
	rows, err := t.TsExec(cmd)
	if err == nil {
		return rows, nil
	}
	ok, verr := verify()
	if verr == nil && ok {
		return rows, nil
	}
	return nil, err
}

func (t *TeamSpeakCore) ServerGroupContains(sgid, cldbid int, wantPresent bool) func() (bool, error) {
	return func() (bool, error) {
		rows, err := t.TsExec(fmt.Sprintf("servergroupclientlist sgid=%d", sgid))
		if err != nil {
			if errors.Is(err, ErrNotFound) {
				return !wantPresent, nil
			}
			return false, err
		}
		want := strconv.Itoa(cldbid)
		for _, r := range rows {
			if r["cldbid"] == want {
				return wantPresent, nil
			}
		}
		return !wantPresent, nil
	}
}

func (t *TeamSpeakCore) TsExec(cmd string) ([]map[string]string, error) {
	return t.TsExecProof(cmd, nil)
}

func (t *TeamSpeakCore) TsExecProof(cmd string, want *TsWant) ([]map[string]string, error) {
	tc := t.tsConn
	if tc == nil {
		return nil, ErrAuth
	}

	tc.execSeq.Lock()
	defer tc.execSeq.Unlock()

	tc.execMu.Lock()
	tc.execCh = make(chan TsIncomingCmd, 64)
	tc.execWait = true
	tc.execMu.Unlock()

	defer func() {
		tc.execMu.Lock()
		tc.execWait = false
		tc.execMu.Unlock()
	}()

	var proofs <-chan TsProof
	if want != nil {
		tc.takeProofs()
		proofs = tc.proofs
	}

	if _, err := tc.tsSendCommand(cmd); err != nil {
		return nil, err
	}
	deadline := time.After(TsExecVoidTimeout)
	var dataLines []string
	var dataTimeout <-chan time.Time
	for {
		select {
		case resp := <-tc.execCh:
			if resp.name == "error" {
				errID, parseErr := strconv.Atoi(resp.params["id"])
				if parseErr != nil {
					return nil, fmt.Errorf("invalid error id %q in server response", resp.params["id"])
				}
				if errID != 0 {
					return nil, tsMapError(&tsError{ID: errID, Msg: resp.params["msg"]})
				}
				var result []map[string]string
				for _, dl := range dataLines {
					result = append(result, tsParseKVList(dl)...)
				}
				return result, nil
			}
			if strings.HasPrefix(resp.name, "notify") {
				go t.TsHandleServerCommand(resp)
			} else {
				dataLines = append(dataLines, resp.raw)
				dataTimeout = time.After(500 * time.Millisecond)
			}
		case <-dataTimeout:
			var result []map[string]string
			for _, dl := range dataLines {
				result = append(result, tsParseKVList(dl)...)
			}
			return result, nil
		case p := <-proofs:
			if want != nil && p.name == want.name && p.fields[want.key] == want.val {
				var result []map[string]string
				for _, dl := range dataLines {
					result = append(result, tsParseKVList(dl)...)
				}
				result = append(result, p.fields)
				return result, nil
			}
		case <-deadline:
			if len(dataLines) == 0 {
				return nil, fmt.Errorf("%w: no response to command within %s (response lost)", ErrNetwork, TsExecVoidTimeout)
			}
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
	_, err := t.TsExec(cmd)
	return err
}

func (t *TeamSpeakCore) RawExec(cmd string) ([]map[string]string, error) {
	return t.TsExec(cmd)
}

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

func (t *TeamSpeakCore) tsHandleTextMessage(kv map[string]string) {
	targetMode, err := strconv.Atoi(kv["targetmode"])
	if err != nil {
		return
	}
	invokerID, err := strconv.Atoi(kv["invokerid"])
	if err != nil {
		return
	}

	t.clientInfoMu.RLock()
	isSelfEcho := invokerID == t.myClientID
	t.clientInfoMu.RUnlock()
	if isSelfEcho {
		if tc := t.tsConn; tc != nil {
			tc.fireProof("notifytextmessage", kv)
		}
		return
	}

	var chatID string
	switch targetMode {
	case 1:
		chatID = fmt.Sprintf("dm:%d", invokerID)
	case 2:
		t.clientInfoMu.RLock()
		chID := t.myChannelID
		t.clientInfoMu.RUnlock()
		chatID = fmt.Sprintf("ch:%d", chID)
	case 3:
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
		IsOutgoing: false,
		Platform:   ts3Platform,
	}
	t.tsAddMessage(chatID, &msg)

	t.fireUpdate(Update{
		Type:     UpdateNewMessage,
		ChatID:   chatID,
		Message:  &msg,
		Platform: ts3Platform,
	})
}

func (t *TeamSpeakCore) tsHandleClientEnter(kv map[string]string) {
	clid, err := strconv.Atoi(kv["clid"])
	if err != nil {
		return
	}
	cid, _ := strconv.Atoi(kv["ctid"])
	dbid, _ := strconv.Atoi(kv["client_database_id"])

	info := TsClientInfo{
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

	t.fireUpdate(Update{
		Type:     UpdateGroupMembers,
		ChatID:   fmt.Sprintf("ch:%d", cid),
		UserID:   strconv.Itoa(dbid),
		Platform: ts3Platform,
	})
}

func (t *TeamSpeakCore) tsHandleClientLeave(kv map[string]string) {
	clid, err := strconv.Atoi(kv["clid"])
	if err != nil {
		return
	}
	cid, _ := strconv.Atoi(kv["cfid"])

	t.clientInfoMu.Lock()
	delete(t.clientInfo, clid)
	t.clientInfoMu.Unlock()

	t.fireUpdate(Update{
		Type:     UpdateGroupMembers,
		ChatID:   fmt.Sprintf("ch:%d", cid),
		Platform: ts3Platform,
	})
}

func (t *TeamSpeakCore) TsHandleClientMoved(kv map[string]string) {
	clid, err := strconv.Atoi(kv["clid"])
	if err != nil {
		return
	}
	cid, _ := strconv.Atoi(kv["ctid"])

	t.clientInfoMu.Lock()
	if clid == t.myClientID {
		t.myChannelID = cid
	}
	if info, ok := t.clientInfo[clid]; ok {
		info.channelID = cid
		t.clientInfo[clid] = info
	}
	t.clientInfoMu.Unlock()

	t.fireUpdate(Update{
		Type:     UpdateGroupMembers,
		ChatID:   fmt.Sprintf("ch:%d", cid),
		Platform: ts3Platform,
	})
}

func (t *TeamSpeakCore) fireUpdate(u Update) {
	t.updateMu.RLock()
	handlers := make([]func(Update), len(t.updateHandlers))
	copy(handlers, t.updateHandlers)
	t.updateMu.RUnlock()
	for _, h := range handlers {
		h(u)
	}
}

func (t *TeamSpeakCore) tsHandleConnectionLost(connErr error) {
	t.mu.Lock()
	shouldReconnect := t.autoReconnect && t.authed
	t.mu.Unlock()

	t.fireUpdate(Update{
		Type:     UpdateUserStatus,
		Platform: ts3Platform,
		ChatID:   "connection",
		UserID:   "self",
		IsOnline: func() *bool { b := false; return &b }(),
	})

	if !shouldReconnect {
		return
	}

	go t.tsReconnectLoop()
}

func (t *TeamSpeakCore) tsReconnectLoop() {
	const maxRetries = 10
	const maxDelay = 60 * time.Second
	baseDelay := 3 * time.Second

	for attempt := 0; attempt < maxRetries; attempt++ {
		t.mu.RLock()
		shouldStop := !t.autoReconnect
		t.mu.RUnlock()
		if shouldStop {
			return
		}

		delay := time.Duration(float64(baseDelay) * math.Pow(2, float64(attempt)))
		if delay > maxDelay {
			delay = maxDelay
		}

		t.fireUpdate(Update{
			Type:      UpdateUserStatus,
			Platform:  ts3Platform,
			ChatID:    "connection",
			UserID:    "self",
			MessageID: fmt.Sprintf("reconnecting attempt %d/%d in %s", attempt+1, maxRetries, delay),
		})

		time.Sleep(delay)

		t.mu.RLock()
		shouldStop = !t.autoReconnect
		t.mu.RUnlock()
		if shouldStop {
			return
		}

		t.mu.Lock()
		t.cancel()
		t.mu.Unlock()
		t.wg.Wait()

		t.mu.Lock()
		if t.tsConn != nil {
			t.tsConn.conn.Close()
			t.tsConn = nil
		}
		t.authed = false
		addr := t.serverAddr
		nickname := t.nickname
		cfg := t.authCfg

		ctx, cancel := context.WithCancel(context.Background())
		t.ctx = ctx
		t.cancel = cancel
		t.mu.Unlock()

		if cfg.Extra == nil {
			cfg.Extra = make(map[string]string)
		}
		cfg.Extra["server_address"] = addr
		cfg.Extra["nickname"] = nickname

		err := t.Authenticate(cfg)
		if err == nil {
			t.fireUpdate(Update{
				Type:     UpdateUserStatus,
				Platform: ts3Platform,
				ChatID:   "connection",
				UserID:   "self",
				IsOnline: func() *bool { b := true; return &b }(),
			})
			return
		}

		log.Printf("ts: reconnect attempt %d/%d failed: %v", attempt+1, maxRetries, err)
	}

	t.fireUpdate(Update{
		Type:      UpdateUserStatus,
		Platform:  ts3Platform,
		ChatID:    "connection",
		UserID:    "self",
		MessageID: "reconnect failed after 10 attempts",
	})
}

func (t *TeamSpeakCore) tsNextMsgID() string {
	return "ts_" + strconv.FormatInt(t.msgCounter.Add(1), 10)
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
	if t.session == nil {
		return nil
	}
	return t.session.Save(sess)
}

func (t *TeamSpeakCore) tsLoadSession() (*tsSession, error) {
	if t.session == nil {
		return nil, fmt.Errorf("no session store")
	}
	var sess tsSession
	if err := t.session.Load(&sess); err != nil {
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
		id.keyOffset = tsHashCash(id.tsOmega(), 8)
	}
	t.tsConn.identity = id
	return nil
}

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

	if err := t.tsConnect(addr); err != nil {
		return err
	}

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

	if err := t.tsHandshake(nickname); err != nil {
		t.tsConn.conn.Close()
		t.tsConn = nil
		return err
	}

	t.authed = true
	t.autoReconnect = true
	t.authCfg = cfg

	t.wg.Add(1)
	go func() {
		defer t.wg.Done()
		t.tsCommandLoop()
	}()

	_ = t.tsSaveSession()

	return nil
}

func (t *TeamSpeakCore) Logout() error {
	t.mu.Lock()
	defer t.mu.Unlock()

	if !t.authed {
		return nil
	}

	t.autoReconnect = false

	if t.tsConn != nil {
		t.tsConn.tsSendCommand("clientdisconnect")
		time.Sleep(100 * time.Millisecond)
		t.tsConn.conn.Close()
		t.tsConn = nil
	}

	t.authed = false
	t.cancel()
	if t.session != nil {
		_ = t.session.Delete()
	}
	return nil
}

func (t *TeamSpeakCore) GetDialogs(opts PaginationOpts) ([]Dialog, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}

	t.channelsMu.RLock()
	defer t.channelsMu.RUnlock()

	dialogs := make([]Dialog, 0, len(t.channels)+1)
	serverTitle := "Server Chat"
	if n := t.ServerName(); n != "" {
		serverTitle = n
	}
	dialogs = append(dialogs, Dialog{
		ID:       "server",
		Type:     ChatTypeChannel,
		Title:    serverTitle,
		Platform: ts3Platform,
	})

	for _, ch := range t.channels {
		d := Dialog{
			ID:            fmt.Sprintf("ch:%d", ch.cid),
			Type:          ChatTypeChannel,
			Title:         ch.name,
			MemberCount:   ch.totalClients,
			Platform:      ts3Platform,
			HasActiveCall: ch.totalClients > 0,
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

	t.msgBufMu.RLock()
	for chatID, msgs := range t.msgBuffer {
		if strings.HasPrefix(chatID, "dm:") && len(msgs) > 0 {
			last := msgs[len(msgs)-1]
			dialogs = append(dialogs, Dialog{
				ID:          chatID,
				Type:        ChatTypeDM,
				Title:       last.SenderName,
				LastMessage: &last,
				Platform:    ts3Platform,
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
	t.clientInfoMu.RLock()
	selfClid := t.myClientID
	t.clientInfoMu.RUnlock()

	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}

	cmd := fmt.Sprintf("channelcreate channel_name=%s", TsEscape(name))
	if description != "" {
		cmd += fmt.Sprintf(" channel_description=%s", TsEscape(description))
	}
	cmd += " channel_flag_semi_permanent=1"

	rows, err := t.TsExecProof(cmd, &TsWant{name: "notifychannelcreated", key: "invokerid", val: strconv.Itoa(selfClid)})
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
		Platform: ts3Platform,
	}, nil
}

func (t *TeamSpeakCore) CreateTopic(_ string, _ string) (*Dialog, error) {
	return nil, fmt.Errorf("%w: teamspeak does not support forum topics", ErrNotSupported)
}

func (t *TeamSpeakCore) GetFolders() ([]Folder, error) {
	return nil, fmt.Errorf("%w: teamspeak does not support folders", ErrNotSupported)
}

func (t *TeamSpeakCore) CreateFolder(_ string, _ []string) (*Folder, error) {
	return nil, fmt.Errorf("%w: teamspeak does not support folders", ErrNotSupported)
}

func (t *TeamSpeakCore) SendMessage(chatID string, msg OutgoingMessage) (*Message, error) {
	t.clientInfoMu.RLock()
	senderID := strconv.Itoa(t.myClientID)
	senderName := t.myName
	t.clientInfoMu.RUnlock()

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
		cmd = fmt.Sprintf("sendtextmessage targetmode=2 target=%d msg=%s", id, TsEscape(msg.Text))
	case "dm":
		cmd = fmt.Sprintf("sendtextmessage targetmode=1 target=%d msg=%s", id, TsEscape(msg.Text))
	case "server":
		cmd = fmt.Sprintf("sendtextmessage targetmode=3 msg=%s", TsEscape(msg.Text))
	}

	if _, err := t.TsExecProof(cmd, &TsWant{name: "notifytextmessage", key: "invokerid", val: senderID}); err != nil {
		return nil, err
	}

	m := &Message{
		ID:         t.tsNextMsgID(),
		ChatID:     chatID,
		SenderID:   senderID,
		SenderName: senderName,
		Text:       msg.Text,
		Timestamp:  time.Now(),
		Status:     MessageStatusSent,
		IsOutgoing: true,
		Platform:   ts3Platform,
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
	return nil, fmt.Errorf("%w: teamspeak does not support message editing", ErrNotSupported)
}

func (t *TeamSpeakCore) DeleteMessage(_ string, _ string) error {
	return fmt.Errorf("%w: teamspeak does not support message deletion", ErrNotSupported)
}

func (t *TeamSpeakCore) ReplyToMessage(chatID string, _ string, msg OutgoingMessage) (*Message, error) {
	return t.SendMessage(chatID, msg)
}

func (t *TeamSpeakCore) ForwardMessage(_ string, _ string, _ string) (*Message, error) {
	return nil, fmt.Errorf("%w: teamspeak does not support message forwarding", ErrNotSupported)
}

func (t *TeamSpeakCore) ReactToMessage(_ string, _ string, _ string) error {
	return fmt.Errorf("%w: teamspeak does not support reactions", ErrNotSupported)
}

func (t *TeamSpeakCore) PinMessage(_ string, _ string) error {
	return fmt.Errorf("%w: teamspeak does not support message pinning", ErrNotSupported)
}

func (t *TeamSpeakCore) UnpinMessage(_ string, _ string) error {
	return fmt.Errorf("%w: teamspeak does not support message pinning", ErrNotSupported)
}

func (t *TeamSpeakCore) MarkAsRead(_ string, _ string) error {
	return fmt.Errorf("%w: teamspeak does not support read state", ErrNotSupported)
}

func (t *TeamSpeakCore) GetReadState(_ string) (*ReadState, error) {
	return nil, fmt.Errorf("%w: teamspeak does not support read state", ErrNotSupported)
}

func (t *TeamSpeakCore) UploadFile(chatID string, file FileUpload, progress func(sent, total int64)) (*Message, error) {
	t.clientInfoMu.RLock()
	senderID := strconv.Itoa(t.myClientID)
	senderName := t.myName
	t.clientInfoMu.RUnlock()

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
		TsEscape("/"+file.Name), id, file.Size)
	rows, err := t.TsExec(cmd)
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

	if _, serr := SendTSFile(ftConn, file.Reader, file.Size, progress); serr != nil {
		return nil, serr
	}

	m := &Message{
		ID:         t.tsNextMsgID(),
		ChatID:     chatID,
		SenderID:   senderID,
		SenderName: senderName,
		Text:       fmt.Sprintf("[File: %s]", file.Name),
		Timestamp:  time.Now(),
		Status:     MessageStatusSent,
		IsOutgoing: true,
		Platform:   ts3Platform,
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
		TsEscape(filePath), channelID)
	rows, err := t.TsExec(cmd)
	if err != nil {
		return err
	}
	if len(rows) == 0 {
		return fmt.Errorf("%w: empty download init response", ErrNetwork)
	}

	ftkey := rows[0]["ftkey"]
	ftPort := rows[0]["port"]
	fileSize, perr := ParseTSSize(rows[0]["size"])
	if perr != nil {
		return perr
	}
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

	if _, rerr := ReceiveTSFile(ftConn, dest, fileSize, progress); rerr != nil {
		return rerr
	}
	return nil
}

func ParseTSSize(s string) (int64, error) {
	n, err := strconv.ParseInt(s, 10, 64)
	if err != nil || n < 0 {
		return 0, fmt.Errorf("%w: bad transfer size %q", ErrTruncated, s)
	}
	return n, nil
}

func ReceiveTSFile(r io.Reader, dest string, fileSize int64, progress func(recv, total int64)) (int64, error) {
	if fileSize < 0 {
		return 0, fmt.Errorf("%w: invalid transfer size %d", ErrTruncated, fileSize)
	}
	f, err := os.Create(dest)
	if err != nil {
		return 0, err
	}
	ok := false
	defer func() {
		if ok {
			f.Close()
			return
		}
		f.Close()
		os.Remove(dest)
	}()

	var recv int64
	buf := make([]byte, 32*1024)
	for recv < fileSize {
		n, readErr := r.Read(buf)
		if n > 0 {
			if _, writeErr := f.Write(buf[:n]); writeErr != nil {
				return recv, writeErr
			}
			recv += int64(n)
			if progress != nil {
				progress(recv, fileSize)
			}
		}
		if readErr != nil {
			if recv >= fileSize {
				break
			}
			return recv, fmt.Errorf("%w: stream ended at %d of %d bytes (%v)", ErrTruncated, recv, fileSize, readErr)
		}
	}
	if recv != fileSize {
		return recv, fmt.Errorf("%w: got %d bytes, declared %d", ErrTruncated, recv, fileSize)
	}
	ok = true
	return recv, nil
}

func SendTSFile(w io.Writer, r io.Reader, size int64, progress func(sent, total int64)) (int64, error) {
	if size < 0 {
		return 0, fmt.Errorf("%w: invalid upload size %d", ErrTruncated, size)
	}
	var sent int64
	buf := make([]byte, 32*1024)
	for size <= 0 || sent < size {
		n, readErr := r.Read(buf)
		if n > 0 {
			if size > 0 && sent+int64(n) > size {
				n = int(size - sent)
			}
			if _, writeErr := w.Write(buf[:n]); writeErr != nil {
				return sent, fmt.Errorf("%w: upload write failed: %v", ErrNetwork, writeErr)
			}
			sent += int64(n)
			if progress != nil {
				progress(sent, size)
			}
		}
		if readErr != nil {
			if readErr != io.EOF {
				return sent, fmt.Errorf("source read failed at %d bytes: %w", sent, readErr)
			}
			if size > 0 && sent < size {
				return sent, fmt.Errorf("%w: source ended at %d of %d bytes", ErrTruncated, sent, size)
			}
			break
		}
	}
	if size > 0 && sent != size {
		return sent, fmt.Errorf("%w: sent %d bytes, declared %d", ErrTruncated, sent, size)
	}
	return sent, nil
}

func (t *TeamSpeakCore) SendImageBase64(_ string, _ string, _ string) (*Message, error) {
	return nil, fmt.Errorf("%w: teamspeak does not support base64 image sending", ErrNotSupported)
}

func (t *TeamSpeakCore) StartCall(_ string, _ bool) (*CallSession, error) {
	return nil, fmt.Errorf("%w: teamspeak does not support calls", ErrNotSupported)
}

func (t *TeamSpeakCore) EndCall(callID string) error {
	return t.LeaveGroupCall(callID)
}

func (t *TeamSpeakCore) ToggleCamera(_ string, _ bool) error {
	return fmt.Errorf("%w: teamspeak does not support calls", ErrNotSupported)
}

func (t *TeamSpeakCore) GetProfile(userID string) (*User, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}

	if userID == "" {
		rows, whoErr := t.TsExec("whoami")
		if whoErr == nil && len(rows) > 0 {
			nick := rows[0]["client_nickname"]
			return &User{
				ID:          rows[0]["client_id"],
				Username:    nick,
				DisplayName: nick,
			}, nil
		}
		return nil, fmt.Errorf("whoami failed: %w", whoErr)
	}

	clid, err := strconv.Atoi(userID)
	if err != nil {
		return nil, fmt.Errorf("%w: invalid user ID", ErrInvalidInput)
	}

	rows, err := t.TsExec(fmt.Sprintf("clientinfo clid=%d", clid))
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
		Platform:    ts3Platform,
	}

	if ts := row["client_lastconnected"]; ts != "" {
		if epoch, err := strconv.ParseInt(ts, 10, 64); err == nil {
			lastSeen := time.Unix(epoch, 0)
			user.LastSeen = &lastSeen
		}
	}

	return user, nil
}

func (t *TeamSpeakCore) OnUpdate(handler func(Update)) {
	t.updateMu.Lock()
	defer t.updateMu.Unlock()
	t.updateHandlers = append(t.updateHandlers, handler)
}

func (t *TeamSpeakCore) Close() error {
	t.mu.Lock()
	t.autoReconnect = false
	t.tsSaveSession()
	t.cancel()
	if t.tsConn != nil {
		t.tsConn.tsSendCommand("clientdisconnect")
		t.tsConn.conn.Close()
		t.tsConn = nil
	}
	t.authed = false
	t.mu.Unlock()
	t.wg.Wait()
	return nil
}

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
			Platform: ts3Platform,
		}, nil
	}

	if kind == "dm" {
		return &Dialog{
			ID:       chatID,
			Type:     ChatTypeDM,
			Title:    fmt.Sprintf("DM %d", id),
			Platform: ts3Platform,
		}, nil
	}

	rows, err := t.TsExec(fmt.Sprintf("channelinfo cid=%d", id))
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
		Platform: ts3Platform,
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
		return fmt.Errorf("%w: teamspeak only supports editing channel titles", ErrNotSupported)
	}
	_, err = t.TsExecProof(fmt.Sprintf("channeledit cid=%d channel_name=%s", id, TsEscape(title)),
		&TsWant{name: "notifychanneledited", key: "cid", val: strconv.Itoa(id)})
	return err
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
		return fmt.Errorf("%w: teamspeak only supports editing channel descriptions", ErrNotSupported)
	}
	_, err = t.TsExecProof(fmt.Sprintf("channeledit cid=%d channel_description=%s", id, TsEscape(description)),
		&TsWant{name: "notifychanneledited", key: "cid", val: strconv.Itoa(id)})
	return err
}

func (t *TeamSpeakCore) LeaveChat(_ string) error {
	return fmt.Errorf("%w: teamspeak does not support leaving chats", ErrNotSupported)
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
		return "", fmt.Errorf("%w: teamspeak only supports invite links for channels", ErrNotSupported)
	}

	cmd := fmt.Sprintf("privilegekeyadd tokentype=0 tokenid1=0 tokenid2=%d tokendescription=%s",
		id, TsEscape("UniClient invite"))
	rows, err := t.TsExec(cmd)
	if err != nil {
		return "", err
	}
	if len(rows) == 0 {
		return "", fmt.Errorf("%w: no token returned", ErrNetwork)
	}
	return rows[0]["token"], nil
}

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
		return fmt.Errorf("%w: teamspeak only supports adding members to channels", ErrNotSupported)
	}

	for _, uid := range userIDs {
		clid, err := strconv.Atoi(uid)
		if err != nil {
			continue
		}
		if _, moveErr := t.TsExecProof(fmt.Sprintf("clientmove clid=%d cid=%d", clid, id),
			&TsWant{name: "notifyclientmoved", key: "clid", val: strconv.Itoa(clid)}); moveErr != nil {
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
	_, err = t.TsExecProof(fmt.Sprintf("clientkick clid=%d reasonid=4 reasonmsg=%s",
		clid, TsEscape("Removed")),
		&TsWant{name: "notifyclientleftview", key: "clid", val: strconv.Itoa(clid)})
	return err
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
	_, err = t.TsExecProof(fmt.Sprintf("banclient clid=%d banreason=%s", clid, TsEscape("Banned")),
		&TsWant{name: "notifyclientleftview", key: "clid", val: strconv.Itoa(clid)})
	return err
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
	banIDStr := strconv.Itoa(banID)
	_, verr := t.TsExecVerified(fmt.Sprintf("bandel banid=%d", banID), func() (bool, error) {
		rows, berr := t.TsExec("banlist")
		if berr != nil {
			if errors.Is(berr, ErrNotFound) {
				return true, nil
			}
			return false, berr
		}
		for _, r := range rows {
			if r["banid"] == banIDStr {
				return false, nil
			}
		}
		return true, nil
	})
	return verr
}

func (t *TeamSpeakCore) GetMembers(chatID string, opts PaginationOpts) ([]User, error) {
	t.clientInfoMu.RLock()
	defer t.clientInfoMu.RUnlock()

	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}

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
			Platform:    ts3Platform,
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

	clid, err := strconv.Atoi(userID)
	if err != nil {
		return fmt.Errorf("%w: invalid user ID", ErrInvalidInput)
	}
	irows, ierr := t.TsExec(fmt.Sprintf("clientinfo clid=%d", clid))
	if ierr != nil {
		return fmt.Errorf("resolve client %d: %w", clid, ierr)
	}
	dbid := 0
	for _, r := range irows {
		if v, perr := strconv.Atoi(r["client_database_id"]); perr == nil && v > 0 {
			dbid = v
			break
		}
	}
	if dbid == 0 {
		return fmt.Errorf("%w: cannot resolve database id for client %d", ErrNotFound, clid)
	}

	rows, err := t.TsExec("servergrouplist")
	if err != nil {
		return err
	}

	adminSGID := 0
	for _, row := range rows {
		name := row["name"]
		if strings.EqualFold(name, "Server Admin") || strings.EqualFold(name, "Admin") {
			if v, err := strconv.Atoi(row["sgid"]); err == nil {
				adminSGID = v
			}
			break
		}
	}
	if adminSGID == 0 {
		return fmt.Errorf("%w: could not find admin server group", ErrNotFound)
	}

	if admin {
		_, verr := t.TsExecVerified(
			fmt.Sprintf("servergroupaddclient sgid=%d cldbid=%d", adminSGID, dbid),
			t.ServerGroupContains(adminSGID, dbid, true))
		return verr
	}
	_, verr := t.TsExecVerified(
		fmt.Sprintf("servergroupdelclient sgid=%d cldbid=%d", adminSGID, dbid),
		t.ServerGroupContains(adminSGID, dbid, false))
	return verr
}

func (t *TeamSpeakCore) GetContacts() ([]User, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}

	rows, err := t.TsExec("clientdblist")
	if err != nil {
		return nil, err
	}

	users := make([]User, 0, len(rows))
	for _, row := range rows {
		u := User{
			ID:          row["cldbid"],
			Username:    row["client_unique_identifier"],
			DisplayName: row["client_nickname"],
			Platform:    ts3Platform,
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
	return fmt.Errorf("%w: teamspeak does not support contacts", ErrNotSupported)
}

func (t *TeamSpeakCore) DeleteContact(_ string) error {
	return fmt.Errorf("%w: teamspeak does not support contacts", ErrNotSupported)
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

	rows, err := t.TsExec("banlist")
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
			Platform:    ts3Platform,
		}
		users = append(users, u)
	}
	return users, nil
}

func (t *TeamSpeakCore) SearchMessages(_ string, query string, opts PaginationOpts) ([]Message, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}

	t.msgBufMu.RLock()
	defer t.msgBufMu.RUnlock()

	queryLower := strings.ToLower(query)
	results := []Message{}
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

	rows, err := t.TsExec("channellist")
	if err != nil {
		return nil, err
	}

	queryLower := strings.ToLower(query)
	results := []Dialog{}
	for _, row := range rows {
		name := row["channel_name"]
		if strings.Contains(strings.ToLower(name), queryLower) {
			results = append(results, Dialog{
				ID:       fmt.Sprintf("ch:%s", row["cid"]),
				Type:     ChatTypeChannel,
				Title:    name,
				Platform: ts3Platform,
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

func (t *TeamSpeakCore) SendTyping(chatID string) error {
	t.clientInfoMu.RLock()
	selfClid := t.myClientID
	t.clientInfoMu.RUnlock()

	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	kind, id, err := tsParseChatID(chatID)
	if err != nil {
		return err
	}
	if kind != "dm" {
		return fmt.Errorf("%w: typing indicators only supported for DMs", ErrNotSupported)
	}
	_, err = t.TsExecProof(fmt.Sprintf("clientchatcomposing clid=%d", id),
		&TsWant{name: "notifyclientchatcomposing", key: "clid", val: strconv.Itoa(selfClid)})
	return err
}

func (t *TeamSpeakCore) CreatePoll(_ string, _ string, _ []string) (*Message, error) {
	return nil, fmt.Errorf("%w: teamspeak does not support polls", ErrNotSupported)
}

func (t *TeamSpeakCore) VotePoll(_ string, _ string, _ int) error {
	return fmt.Errorf("%w: teamspeak does not support polls", ErrNotSupported)
}

func (t *TeamSpeakCore) SendSticker(_ string, _ string) (*Message, error) {
	return nil, fmt.Errorf("%w: teamspeak does not support stickers", ErrNotSupported)
}

func (t *TeamSpeakCore) GetSessions() ([]Session, error) {
	t.clientInfoMu.RLock()
	selfClid := t.myClientID
	t.clientInfoMu.RUnlock()

	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}

	rows, err := t.TsExec("clientlist -uid -times -info")
	if err != nil {
		return nil, err
	}

	sessions := make([]Session, 0, len(rows))
	for _, row := range rows {
		clid, err := strconv.Atoi(row["clid"])
		if err != nil {
			continue
		}
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

		s.IsCurrent = clid == selfClid

		sessions = append(sessions, s)
	}
	return sessions, nil
}

func (t *TeamSpeakCore) TerminateSession(sessionID string) error {
	t.clientInfoMu.RLock()
	selfClid := t.myClientID
	t.clientInfoMu.RUnlock()

	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}

	clid, err := strconv.Atoi(sessionID)
	if err != nil {
		return fmt.Errorf("%w: invalid session ID", ErrInvalidInput)
	}

	if clid == selfClid {
		return fmt.Errorf("%w: cannot terminate own session", ErrInvalidInput)
	}

	return t.tsExecSimple(fmt.Sprintf("clientkick clid=%d reasonid=5 reasonmsg=%s",
		clid, TsEscape("Session terminated")))
}

func (t *TeamSpeakCore) tsClientUpdate(params string) error {
	t.clientInfoMu.RLock()
	selfClid := t.myClientID
	t.clientInfoMu.RUnlock()

	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	_, err := t.TsExecProof("clientupdate "+params,
		&TsWant{name: "notifyclientupdated", key: "clid", val: strconv.Itoa(selfClid)})
	return err
}

func (t *TeamSpeakCore) ClientUpdate(params map[string]string) error {
	var b strings.Builder
	first := true
	for k, v := range params {
		if !first {
			b.WriteByte(' ')
		}
		b.WriteString(k)
		b.WriteByte('=')
		b.WriteString(TsEscape(v))
		first = false
	}
	return t.tsClientUpdate(b.String())
}

func (t *TeamSpeakCore) SetNickname(nickname string) error {
	if err := t.tsClientUpdate(fmt.Sprintf("client_nickname=%s", TsEscape(nickname))); err != nil {
		return err
	}
	t.mu.Lock()
	t.nickname = nickname
	t.mu.Unlock()

	t.clientInfoMu.Lock()
	t.myName = nickname
	t.clientInfoMu.Unlock()
	return nil
}

func (t *TeamSpeakCore) SetInputMuted(muted bool) error {
	v := "0"
	if muted {
		v = "1"
	}
	t.mu.Lock()
	t.micMuted = muted
	t.mu.Unlock()
	return t.tsClientUpdate("client_input_muted=" + v)
}

func (t *TeamSpeakCore) noteSpeaking(clid int) {
	t.speakingMu.Lock()
	if t.speakingUntil == nil {
		t.speakingUntil = make(map[int]time.Time)
	}
	t.speakingUntil[clid] = time.Now().Add(400 * time.Millisecond)
	t.speakingMu.Unlock()
}

func (t *TeamSpeakCore) isSpeaking(clid int) bool {
	t.speakingMu.Lock()
	defer t.speakingMu.Unlock()
	until, ok := t.speakingUntil[clid]
	return ok && time.Now().Before(until)
}

func (t *TeamSpeakCore) SendVoiceFrame(opusData []byte) error {
	return t.SendVoice(tsCodecOpusVoice, opusData)
}

func (t *TeamSpeakCore) OnVoiceFrame(handler func(sender string, opus []byte)) {
	t.OnVoice(func(p VoicePacket) {
		if len(p.AudioData) == 0 {
			return
		}
		handler(strconv.Itoa(p.SenderClientID), p.AudioData)
	})
}

func (t *TeamSpeakCore) SetVoiceMuted(muted bool) error {
	return t.SetInputMuted(muted)
}

func tsParseChannelChatID(chatID string) (int, error) {
	if !strings.HasPrefix(chatID, "ch:") {
		return 0, ErrInvalidInput
	}
	cid, err := strconv.Atoi(strings.TrimPrefix(chatID, "ch:"))
	if err != nil {
		return 0, ErrInvalidInput
	}
	return cid, nil
}

func (t *TeamSpeakCore) JoinGroupCall(chatID string) (*CallSession, error) {
	t.mu.RLock()
	if !t.authed {
		t.mu.RUnlock()
		return nil, ErrAuth
	}
	t.mu.RUnlock()
	cid, err := tsParseChannelChatID(chatID)
	if err != nil {
		return nil, err
	}
	if err := t.JoinChannel(cid, ""); err != nil {
		var te *tsError
		if !errors.As(err, &te) || te.ID != 770 {
			return nil, err
		}
	}
	return &CallSession{
		ID:      chatID,
		ChatID:  chatID,
		IsGroup: true,
		State:   CallStateActive,
	}, nil
}

func (t *TeamSpeakCore) DefaultChannelID() int {
	t.defaultChannelMu.RLock()
	defer t.defaultChannelMu.RUnlock()
	return t.defaultChannelID
}

func (t *TeamSpeakCore) LeaveGroupCall(callID string) error {
	t.mu.RLock()
	if !t.authed {
		t.mu.RUnlock()
		return ErrAuth
	}
	t.mu.RUnlock()
	cid := t.DefaultChannelID()
	if cid < 0 {
		return nil
	}
	return t.JoinChannel(cid, "")
}

func (t *TeamSpeakCore) SetCallMuted(callID string, muted bool) error {
	t.mu.RLock()
	if !t.authed {
		t.mu.RUnlock()
		return ErrAuth
	}
	t.mu.RUnlock()
	return t.SetInputMuted(muted)
}

func (t *TeamSpeakCore) GetGroupCall(chatID string) (*CallSession, error) {
	t.mu.RLock()
	if !t.authed {
		t.mu.RUnlock()
		return nil, ErrAuth
	}
	t.mu.RUnlock()
	cid, err := tsParseChannelChatID(chatID)
	if err != nil {
		return nil, err
	}
	t.channelsMu.RLock()
	ch, hasCh := t.channels[cid]
	var title string
	if hasCh {
		title = ch.name
	}
	t.channelsMu.RUnlock()

	t.clientInfoMu.RLock()
	var participants []CallParticipant
	selfSeen := false
	for _, cl := range t.clientInfo {
		if cl.channelID != cid {
			continue
		}
		if cl.clid == t.myClientID {
			selfSeen = true
		}
		participants = append(participants, CallParticipant{
			UserID:      strconv.Itoa(cl.clid),
			DisplayName: cl.nickname,
			IsMuted:     cl.clid == t.myClientID && t.selfMuted(),
			IsSpeaking:  cl.clid != t.myClientID && t.isSpeaking(cl.clid),
		})
	}
	t.clientInfoMu.RUnlock()

	t.clientInfoMu.RLock()
	selfInThisRoom := !selfSeen && t.myChannelID == cid
	t.clientInfoMu.RUnlock()
	if selfInThisRoom {
		participants = append(participants, CallParticipant{
			UserID:      strconv.Itoa(t.myClientID),
			DisplayName: t.myName,
			IsMuted:     t.selfMuted(),
			IsSpeaking:  false,
		})
	}

	return &CallSession{
		ID:           chatID,
		ChatID:       chatID,
		IsGroup:      true,
		State:        CallStateActive,
		Participants: participants,
		Meta: map[string]string{
			"title":              title,
			"participants_count": strconv.Itoa(len(participants)),
			"talk_power":         t.talkPowerState(cid),
		},
	}, nil
}

func (t *TeamSpeakCore) selfMuted() bool {
	t.mu.RLock()
	defer t.mu.RUnlock()
	return t.micMuted
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
		cmd = fmt.Sprintf("client_away=1 client_away_message=%s", TsEscape(message))
	}
	return t.tsClientUpdate(cmd)
}

func (t *TeamSpeakCore) SetDescription(description string) error {
	return t.tsClientUpdate(fmt.Sprintf("client_description=%s", TsEscape(description)))
}

func (t *TeamSpeakCore) SetAvatar(md5Hex string) error {
	return t.tsClientUpdate(fmt.Sprintf("client_flag_avatar=%s", md5Hex))
}

func (t *TeamSpeakCore) RequestTalkPower(message string) error {
	return t.tsClientUpdate(fmt.Sprintf("client_talk_request=1 client_talk_request_msg=%s", TsEscape(message)))
}

func (t *TeamSpeakCore) CancelTalkPowerRequest() error {
	return t.tsClientUpdate("client_talk_request=0")
}

func (t *TeamSpeakCore) SetBadges(badges string) error {
	return t.tsClientUpdate(fmt.Sprintf("client_badges=%s", TsEscape(badges)))
}

func (t *TeamSpeakCore) SetMetaData(metadata string) error {
	return t.tsClientUpdate(fmt.Sprintf("client_meta_data=%s", TsEscape(metadata)))
}

func (t *TeamSpeakCore) SetPhoneticNickname(name string) error {
	return t.tsClientUpdate(fmt.Sprintf("client_nickname_phonetic=%s", TsEscape(name)))
}

func (t *TeamSpeakCore) CreateChannelFull(name string, opts map[string]string) (int, error) {
	t.clientInfoMu.RLock()
	selfClid := t.myClientID
	t.clientInfoMu.RUnlock()

	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return 0, ErrAuth
	}

	var b strings.Builder
	b.WriteString("channelcreate channel_name=")
	b.WriteString(TsEscape(name))
	for k, v := range opts {
		b.WriteByte(' ')
		b.WriteString(k)
		b.WriteByte('=')
		b.WriteString(TsEscape(v))
	}
	cmd := b.String()

	rows, err := t.TsExecProof(cmd, &TsWant{name: "notifychannelcreated", key: "invokerid", val: strconv.Itoa(selfClid)})
	if err != nil {
		return 0, err
	}
	if len(rows) > 0 {
		cid, err := strconv.Atoi(rows[0]["cid"])
		if err != nil {
			return 0, fmt.Errorf("invalid cid in response: %w", err)
		}
		return cid, nil
	}
	return 0, nil
}

func (t *TeamSpeakCore) EditChannel(cid int, props map[string]string) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	var b strings.Builder
	b.WriteString("channeledit cid=")
	b.WriteString(strconv.Itoa(cid))
	for k, v := range props {
		b.WriteByte(' ')
		b.WriteString(k)
		b.WriteByte('=')
		b.WriteString(TsEscape(v))
	}
	return t.tsExecSimple(b.String())
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
	return t.TsExec(fmt.Sprintf("channelfind pattern=%s", TsEscape(pattern)))
}

func (t *TeamSpeakCore) GetChannelDescription(cid int) (string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return "", ErrAuth
	}
	rows, err := t.TsExec(fmt.Sprintf("channelgetdescription cid=%d", cid))
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
	var b strings.Builder
	b.WriteString("channelsubscribe ")
	for i, cid := range cids {
		if i > 0 {
			b.WriteByte('|')
		}
		b.WriteString("cid=")
		b.WriteString(strconv.Itoa(cid))
	}
	return t.tsExecSimple(b.String())
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
	var b strings.Builder
	b.WriteString("channelunsubscribe ")
	for i, cid := range cids {
		if i > 0 {
			b.WriteByte('|')
		}
		b.WriteString("cid=")
		b.WriteString(strconv.Itoa(cid))
	}
	return t.tsExecSimple(b.String())
}

func (t *TeamSpeakCore) UnsubscribeAllChannels() error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple("channelunsubscribeall")
}

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
	return t.TsExec(fmt.Sprintf("channelpermlist cid=%d", cid))
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
	return t.TsExec(fmt.Sprintf("channelclientpermlist cid=%d cldbid=%d", cid, cldbid))
}

func (t *TeamSpeakCore) ServerGroupAdd(name string) (int, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return 0, ErrAuth
	}
	rows, err := t.TsExec(fmt.Sprintf("servergroupadd name=%s", TsEscape(name)))
	if err != nil {
		return 0, err
	}
	if len(rows) > 0 {
		sgid, err := strconv.Atoi(rows[0]["sgid"])
		if err != nil {
			return 0, fmt.Errorf("invalid sgid in response: %w", err)
		}
		return sgid, nil
	}
	return 0, nil
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
	return t.TsExec(fmt.Sprintf("servergroupclientlist sgid=%d", sgid))
}

func (t *TeamSpeakCore) ServerGroupPermList(sgid int) ([]map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	return t.TsExec(fmt.Sprintf("servergrouppermlist sgid=%d", sgid))
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
	rows, err := t.TsExec(fmt.Sprintf("servergroupcopy ssgid=%d tsgid=0 name=%s type=%d", sourceSGID, TsEscape(name), targetType))
	if err != nil {
		return 0, err
	}
	if len(rows) > 0 {
		sgid, err := strconv.Atoi(rows[0]["sgid"])
		if err != nil {
			return 0, fmt.Errorf("invalid sgid in response: %w", err)
		}
		return sgid, nil
	}
	return 0, nil
}

func (t *TeamSpeakCore) ServerGroupRename(sgid int, name string) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple(fmt.Sprintf("servergrouprename sgid=%d name=%s", sgid, TsEscape(name)))
}

func (t *TeamSpeakCore) ServerGroupsByClientID(cldbid int) ([]map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	return t.TsExec(fmt.Sprintf("servergroupsbyclientid cldbid=%d", cldbid))
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

func (t *TeamSpeakCore) ChannelGroupList() ([]map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	return t.TsExec("channelgrouplist")
}

func (t *TeamSpeakCore) ChannelGroupAdd(name string) (int, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return 0, ErrAuth
	}
	rows, err := t.TsExec(fmt.Sprintf("channelgroupadd name=%s", TsEscape(name)))
	if err != nil {
		return 0, err
	}
	if len(rows) > 0 {
		cgid, err := strconv.Atoi(rows[0]["cgid"])
		if err != nil {
			return 0, fmt.Errorf("invalid cgid in response: %w", err)
		}
		return cgid, nil
	}
	return 0, nil
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
	return t.TsExec(fmt.Sprintf("channelgroupclientlist cgid=%d cid=%d", cgid, cid))
}

func (t *TeamSpeakCore) ChannelGroupPermList(cgid int) ([]map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	return t.TsExec(fmt.Sprintf("channelgrouppermlist cgid=%d", cgid))
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
	rows, err := t.TsExec(fmt.Sprintf("channelgroupcopy scgid=%d tcgid=0 name=%s type=%d", sourceCGID, TsEscape(name), targetType))
	if err != nil {
		return 0, err
	}
	if len(rows) > 0 {
		cgid, err := strconv.Atoi(rows[0]["cgid"])
		if err != nil {
			return 0, fmt.Errorf("invalid cgid in response: %w", err)
		}
		return cgid, nil
	}
	return 0, nil
}

func (t *TeamSpeakCore) ChannelGroupRename(cgid int, name string) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple(fmt.Sprintf("channelgrouprename cgid=%d name=%s", cgid, TsEscape(name)))
}

func (t *TeamSpeakCore) SetClientChannelGroup(cgid, cid, cldbid int) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple(fmt.Sprintf("setclientchannelgroup cgid=%d cid=%d cldbid=%d", cgid, cid, cldbid))
}

func (t *TeamSpeakCore) ClientDBInfo(cldbid int) (map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	rows, err := t.TsExec(fmt.Sprintf("clientdbinfo cldbid=%d", cldbid))
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
	var b strings.Builder
	b.WriteString("clientdbedit cldbid=")
	b.WriteString(strconv.Itoa(cldbid))
	for k, v := range props {
		b.WriteByte(' ')
		b.WriteString(k)
		b.WriteByte('=')
		b.WriteString(TsEscape(v))
	}
	return t.tsExecSimple(b.String())
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
	cmd := fmt.Sprintf("clientdbfind pattern=%s", TsEscape(pattern))
	if isUID {
		cmd += " -uid"
	}
	return t.TsExec(cmd)
}

func (t *TeamSpeakCore) ClientFind(pattern string) ([]map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	return t.TsExec(fmt.Sprintf("clientfind pattern=%s", TsEscape(pattern)))
}

func (t *TeamSpeakCore) ClientGetDBIDFromUID(cluid string) (int, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return 0, ErrAuth
	}
	rows, err := t.TsExec(fmt.Sprintf("clientgetdbidfromuid cluid=%s", TsEscape(cluid)))
	if err != nil {
		return 0, err
	}
	if len(rows) == 0 {
		return 0, ErrNotFound
	}
	cldbid, err := strconv.Atoi(rows[0]["cldbid"])
	if err != nil {
		return 0, fmt.Errorf("invalid cldbid in response: %w", err)
	}
	return cldbid, nil
}

func (t *TeamSpeakCore) ClientGetIDs(cluid string) ([]map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	return t.TsExec(fmt.Sprintf("clientgetids cluid=%s", TsEscape(cluid)))
}

func (t *TeamSpeakCore) ClientGetNameFromUID(cluid string) (string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return "", ErrAuth
	}
	rows, err := t.TsExec(fmt.Sprintf("clientgetnamefromuid cluid=%s", TsEscape(cluid)))
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
	rows, err := t.TsExec(fmt.Sprintf("clientgetnamefromdbid cldbid=%d", cldbid))
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
	rows, err := t.TsExec(fmt.Sprintf("clientgetuidfromclid clid=%d", clid))
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
	var b strings.Builder
	b.WriteString("clientedit clid=")
	b.WriteString(strconv.Itoa(clid))
	for k, v := range props {
		b.WriteByte(' ')
		b.WriteString(k)
		b.WriteByte('=')
		b.WriteString(TsEscape(v))
	}
	return t.tsExecSimple(b.String())
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
	return t.TsExec(fmt.Sprintf("clientpermlist cldbid=%d", cldbid))
}

func (t *TeamSpeakCore) ClientPoke(clid int, message string) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple(fmt.Sprintf("clientpoke clid=%d msg=%s", clid, TsEscape(message)))
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
	t.clientInfoMu.RLock()
	selfClid := t.myClientID
	t.clientInfoMu.RUnlock()

	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	cmd := fmt.Sprintf("clientmove clid=%d cid=%d", selfClid, cid)
	if password != "" {
		cmd += fmt.Sprintf(" cpw=%s", TsEscape(password))
	}
	if _, err := t.TsExecProof(cmd, &TsWant{name: "notifyclientmoved", key: "clid", val: strconv.Itoa(selfClid)}); err != nil {
		return err
	}
	go t.TsRefreshChannelTalkPower(cid)
	return nil
}

func tsParseNeededTalkPower(rows []map[string]string) (power int, known bool) {
	for _, r := range rows {
		v, ok := r["channel_needed_talk_power"]
		if !ok {
			continue
		}
		n, err := strconv.Atoi(v)
		if err != nil {
			return 0, false
		}
		return n, true
	}
	return 0, false
}

func (t *TeamSpeakCore) TsRefreshChannelTalkPower(cid int) {
	rows, err := t.TsExec(fmt.Sprintf("channelinfo cid=%d", cid))
	if err != nil {
		return
	}
	power, known := tsParseNeededTalkPower(rows)
	if !known {
		return
	}
	t.channelsMu.Lock()
	ch := t.channels[cid]
	ch.cid = cid
	ch.talkPower = power
	ch.talkPowerKnown = true
	t.channels[cid] = ch
	t.channelsMu.Unlock()
}

func (t *TeamSpeakCore) talkPowerState(cid int) string {
	t.clientInfoMu.RLock()
	power := t.myTalkPower
	t.clientInfoMu.RUnlock()
	if power <= 0 {
		return "unknown"
	}
	t.channelsMu.RLock()
	ch := t.channels[cid]
	t.channelsMu.RUnlock()
	if !ch.talkPowerKnown {
		return "unknown"
	}
	if ch.talkPower > 0 && power < ch.talkPower {
		return "blocked"
	}
	return "ok"
}

func (t *TeamSpeakCore) BanAdd(ip, name, uid string, timeSeconds int, reason string) (int, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return 0, ErrAuth
	}
	var b strings.Builder
	b.WriteString("banadd")
	if ip != "" {
		b.WriteString(" ip=")
		b.WriteString(TsEscape(ip))
	}
	if name != "" {
		b.WriteString(" name=")
		b.WriteString(TsEscape(name))
	}
	if uid != "" {
		b.WriteString(" uid=")
		b.WriteString(TsEscape(uid))
	}
	if timeSeconds > 0 {
		b.WriteString(" time=")
		b.WriteString(strconv.Itoa(timeSeconds))
	}
	if reason != "" {
		b.WriteString(" banreason=")
		b.WriteString(TsEscape(reason))
	}
	rows, err := t.TsExec(b.String())
	if err != nil {
		return 0, err
	}
	if len(rows) > 0 {
		banID, err := strconv.Atoi(rows[0]["banid"])
		if err != nil {
			return 0, fmt.Errorf("invalid banid in response: %w", err)
		}
		return banID, nil
	}
	return 0, nil
}

func (t *TeamSpeakCore) BanDelAll() error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple("bandelall")
}

func (t *TeamSpeakCore) MessageAdd(cluid, subject, message string) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple(fmt.Sprintf("messageadd cluid=%s subject=%s message=%s",
		TsEscape(cluid), TsEscape(subject), TsEscape(message)))
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
	rows, err := t.TsExec(fmt.Sprintf("messageget msgid=%d", msgID))
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
	return t.TsExec("messagelist")
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

func (t *TeamSpeakCore) ComplainAdd(tcldbid int, message string) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple(fmt.Sprintf("complainadd tcldbid=%d message=%s", tcldbid, TsEscape(message)))
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
	return t.TsExec(fmt.Sprintf("complainlist tcldbid=%d", tcldbid))
}

func (t *TeamSpeakCore) PrivilegeKeyAdd(tokenType, tokenID1, tokenID2 int) (string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return "", ErrAuth
	}
	rows, err := t.TsExec(fmt.Sprintf("privilegekeyadd tokentype=%d tokenid1=%d tokenid2=%d", tokenType, tokenID1, tokenID2))
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
	return t.tsExecSimple(fmt.Sprintf("privilegekeydelete token=%s", TsEscape(token)))
}

func (t *TeamSpeakCore) PrivilegeKeyList() ([]map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	return t.TsExec("privilegekeylist")
}

func (t *TeamSpeakCore) PrivilegeKeyUse(token string) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple(fmt.Sprintf("privilegekeyuse token=%s", TsEscape(token)))
}

func (t *TeamSpeakCore) ServerInfo() (map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	rows, err := t.TsExec("serverinfo")
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
	var b strings.Builder
	b.WriteString("serveredit")
	for k, v := range props {
		b.WriteByte(' ')
		b.WriteString(k)
		b.WriteByte('=')
		b.WriteString(TsEscape(v))
	}
	return t.tsExecSimple(b.String())
}

func (t *TeamSpeakCore) ServerVersion() (map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	rows, err := t.TsExec("version")
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
	rows, err := t.TsExec("whoami")
	if err != nil {
		return nil, err
	}
	if len(rows) == 0 {
		return nil, ErrNotFound
	}
	info := rows[0]
	if info["client_unique_identifier"] == "" && t.myUID != "" {
		info["client_unique_identifier"] = t.myUID
	}
	return info, nil
}

func (t *TeamSpeakCore) GetConnectionInfo(clid int) (map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	rows, err := t.TsExec(fmt.Sprintf("getconnectioninfo clid=%d", clid))
	if err != nil {
		return nil, err
	}
	if len(rows) == 0 {
		return nil, ErrNotFound
	}
	return rows[0], nil
}

func (t *TeamSpeakCore) PermissionList() ([]map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	return t.TsExec("permissionlist")
}

func (t *TeamSpeakCore) PermFind(permID int) ([]map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	return t.TsExec(fmt.Sprintf("permfind permid=%d", permID))
}

func (t *TeamSpeakCore) PermGet(permID int) (map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	rows, err := t.TsExec(fmt.Sprintf("permget permid=%d", permID))
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
	return t.TsExec(fmt.Sprintf("permoverview cid=%d cldbid=%d", cid, cldbid))
}

func (t *TeamSpeakCore) PermIDGetByName(permsid string) (int, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return 0, ErrAuth
	}
	rows, err := t.TsExec(fmt.Sprintf("permidgetbyname permsid=%s", TsEscape(permsid)))
	if err != nil {
		return 0, err
	}
	if len(rows) == 0 {
		return 0, ErrNotFound
	}
	pid, err := strconv.Atoi(rows[0]["permid"])
	if err != nil {
		return 0, fmt.Errorf("invalid permid in response: %w", err)
	}
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

func (t *TeamSpeakCore) CustomInfo(cldbid int) ([]map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	return t.TsExec(fmt.Sprintf("custominfo cldbid=%d", cldbid))
}

func (t *TeamSpeakCore) CustomSearch(ident, pattern string) ([]map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	return t.TsExec(fmt.Sprintf("customsearch ident=%s pattern=%s", TsEscape(ident), TsEscape(pattern)))
}

func (t *TeamSpeakCore) CustomSet(cldbid int, ident, value string) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple(fmt.Sprintf("customset cldbid=%d ident=%s value=%s", cldbid, TsEscape(ident), TsEscape(value)))
}

func (t *TeamSpeakCore) CustomDelete(cldbid int, ident string) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple(fmt.Sprintf("customdelete cldbid=%d ident=%s", cldbid, TsEscape(ident)))
}

func (t *TeamSpeakCore) SendPluginCommand(name, data string, targetMode int) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple(fmt.Sprintf("plugincmd name=%s data=%s targetmode=%d",
		TsEscape(name), TsEscape(data), targetMode))
}

func (t *TeamSpeakCore) FTGetFileList(cid int, path, channelPassword string) ([]map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	return t.TsExec(fmt.Sprintf("ftgetfilelist cid=%d cpw=%s path=%s", cid, TsEscape(channelPassword), TsEscape(path)))
}

func (t *TeamSpeakCore) FTGetFileInfo(cid int, name, channelPassword string) (map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	rows, err := t.TsExec(fmt.Sprintf("ftgetfileinfo cid=%d cpw=%s name=%s", cid, TsEscape(channelPassword), TsEscape(name)))
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
	var b strings.Builder
	b.WriteString("ftdeletefile cid=")
	b.WriteString(strconv.Itoa(cid))
	b.WriteString(" cpw=")
	b.WriteString(TsEscape(channelPassword))
	b.WriteByte(' ')
	for i, n := range names {
		if i > 0 {
			b.WriteByte('|')
		}
		b.WriteString("name=")
		b.WriteString(TsEscape(n))
	}
	return t.tsExecSimple(b.String())
}

func (t *TeamSpeakCore) FTCreateDir(cid int, dirname, channelPassword string) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple(fmt.Sprintf("ftcreatedir cid=%d cpw=%s dirname=%s", cid, TsEscape(channelPassword), TsEscape(dirname)))
}

func (t *TeamSpeakCore) FTRenameFile(cid int, oldName, newName, channelPassword string, targetCID int, targetPassword string) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	cmd := fmt.Sprintf("ftrenamefile cid=%d cpw=%s oldname=%s newname=%s",
		cid, TsEscape(channelPassword), TsEscape(oldName), TsEscape(newName))
	if targetCID > 0 {
		cmd += fmt.Sprintf(" tcid=%d tcpw=%s", targetCID, TsEscape(targetPassword))
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
	return t.TsExec("ftlist")
}

func (t *TeamSpeakCore) ServerRequestConnectionInfo() (map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	rows, err := t.TsExec("serverrequestconnectioninfo")
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

const (
	tsCodecSpeexNB   = 0
	tsCodecSpeexWB   = 1
	tsCodecSpeexUWB  = 2
	tsCodecCeltMono  = 3
	tsCodecOpusVoice = 4
	tsCodecOpusMusic = 5
)

const (
	tsGroupWhisperTypeServerGroup      = 0
	tsGroupWhisperTypeChannelGroup     = 1
	tsGroupWhisperTypeChannelCommander = 2
	tsGroupWhisperTypeAllClients       = 3
)

const (
	tsGroupWhisperTargetAllChannels           = 0
	tsGroupWhisperTargetCurrentChannel        = 1
	tsGroupWhisperTargetParentChannel         = 2
	tsGroupWhisperTargetAllParentChannels     = 3
	tsGroupWhisperTargetChannelFamily         = 4
	tsGroupWhisperTargetCompleteChannelFamily = 5
	tsGroupWhisperTargetSubchannels           = 6
)

func (t *TeamSpeakCore) OnVoice(handler func(VoicePacket)) {
	t.voiceHandlerMu.Lock()
	defer t.voiceHandlerMu.Unlock()
	t.voiceHandler = handler
}

func (t *TeamSpeakCore) tsHandleVoicePacket(packetType byte, flags byte, plaintext []byte) {
	isWhisper := packetType == tsPktVoiceWhisper
	hasServerFlag := flags&TsFlagCompressed != 0

	if len(plaintext) < 5 {
		return
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
		return
	}

	audioData := make([]byte, audioEnd-audioStart)
	copy(audioData, plaintext[audioStart:audioEnd])

	t.noteSpeaking(clientID)

	t.voiceHandlerMu.RLock()
	handler := t.voiceHandler
	t.voiceHandlerMu.RUnlock()
	if handler == nil {
		return
	}

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
	pktFlags := pktType | flags

	if len(body) >= 2 {
		binary.BigEndian.PutUint16(body[0:2], pID)
	}

	var meta [5]byte
	binary.BigEndian.PutUint16(meta[0:2], pID)
	binary.BigEndian.PutUint16(meta[2:4], uint16(tc.clientID.Load()))
	meta[4] = pktFlags

	key, nonce := TsCreateKeyNonce(pktType, pID, tc.pktState[pktType].sendGenID, 0x31, tc.sharedIV[:])
	mac, ciphertext := TsEAXEncrypt(key[:], nonce[:], meta[:], body)

	pkt := TsBuildC2SPacket(mac, pID, uint16(tc.clientID.Load()), pktFlags, ciphertext)
	t.bwStats.recordSent(pktType, len(pkt))
	return tc.tsSendRaw(pkt)
}

func (t *TeamSpeakCore) SendVoice(codec byte, audioData []byte) error {
	t.clientInfoMu.RLock()
	curChannel := t.myChannelID
	t.clientInfoMu.RUnlock()
	talkBlocked := t.talkPowerState(curChannel) == "blocked"

	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}

	body := make([]byte, 3+len(audioData))
	body[2] = codec
	copy(body[3:], audioData)

	if talkBlocked {
		return fmt.Errorf("%w: insufficient talk power in this room — the server discards voice below the channel requirement", ErrPermission)
	}

	return t.tsSendVoicePacket(TsPktVoice, 0, body)
}

func (t *TeamSpeakCore) SendVoiceWhisper(codec byte, audioData []byte, channelIDs []uint64, clientIDs []uint16) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}

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

func (t *TeamSpeakCore) SendVoiceGroupWhisper(codec byte, audioData []byte, whisperType, whisperTarget byte, targetID uint64) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}

	body := make([]byte, 13+len(audioData))
	body[2] = codec
	body[3] = whisperType
	body[4] = whisperTarget
	binary.BigEndian.PutUint64(body[5:13], targetID)
	copy(body[13:], audioData)

	return t.tsSendVoicePacket(tsPktVoiceWhisper, TsFlagNewprotocol, body)
}

const tsBwWindowSize = 60

type tsBwCategory int

const (
	tsBwSpeech    tsBwCategory = 0
	tsBwKeepalive tsBwCategory = 1
	tsBwControl   tsBwCategory = 2
)

type tsBwSample struct {
	packets int64
	bytes   int64
}

type tsBandwidthStats struct {
	mu sync.Mutex

	sentRing [3][tsBwWindowSize]tsBwSample
	recvRing [3][tsBwWindowSize]tsBwSample

	totalSentPkts  [3]int64
	totalSentBytes [3]int64
	totalRecvPkts  [3]int64
	totalRecvBytes [3]int64

	lastSecond int64

	voiceExpected atomic.Int64
	voiceLost     atomic.Int64
}

func tsBwCategoryForPacket(pktType byte) tsBwCategory {
	switch pktType {
	case TsPktVoice, tsPktVoiceWhisper:
		return tsBwSpeech
	case tsPktPing, tsPktPong:
		return tsBwKeepalive
	default:
		return tsBwControl
	}
}

func (bw *tsBandwidthStats) advance(now int64) {
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

type TsBandwidthSnapshot struct {
	SentLastSecond  [3]int64
	RecvLastSecond  [3]int64
	SentLastMinute  [3]int64
	RecvLastMinute  [3]int64
	TotalSentPkts   [3]int64
	TotalSentBytes  [3]int64
	TotalRecvPkts   [3]int64
	TotalRecvBytes  [3]int64
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

	prevIdx := (now - 1) % tsBwWindowSize
	for c := 0; c < 3; c++ {
		snap.SentLastSecond[c] = bw.sentRing[c][prevIdx].bytes
		snap.RecvLastSecond[c] = bw.recvRing[c][prevIdx].bytes
	}

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

func (t *TeamSpeakCore) GetBandwidthStats() TsBandwidthSnapshot {
	return t.bwStats.snapshot()
}

func (t *TeamSpeakCore) ClientKick(clid, reasonID int, message string) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	cmd := fmt.Sprintf("clientkick clid=%d reasonid=%d", clid, reasonID)
	if message != "" {
		cmd += fmt.Sprintf(" reasonmsg=%s", TsEscape(message))
	}
	return t.tsExecSimple(cmd)
}

func (t *TeamSpeakCore) ClientMute(clid int) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple(fmt.Sprintf("clientmute clid=%d", clid))
}

func (t *TeamSpeakCore) ClientUnmute(clid int) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple(fmt.Sprintf("clientunmute clid=%d", clid))
}

func (t *TeamSpeakCore) ClientChatComposing(clid int) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple(fmt.Sprintf("clientchatcomposing clid=%d", clid))
}

func (t *TeamSpeakCore) ClientDBList(start, duration int) ([]map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	cmd := "clientdblist"
	if start > 0 {
		cmd += fmt.Sprintf(" start=%d", start)
	}
	if duration > 0 {
		cmd += fmt.Sprintf(" duration=%d", duration)
	}
	return t.TsExec(cmd)
}

func (t *TeamSpeakCore) ClientVariable(clid int, varNames ...string) (map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	cmd := fmt.Sprintf("clientvariable clid=%d", clid)
	for _, v := range varNames {
		cmd += " " + TsEscape(v)
	}
	rows, err := t.TsExec(cmd)
	if err != nil {
		return nil, err
	}
	if len(rows) > 0 {
		return rows[0], nil
	}
	return map[string]string{}, nil
}

func (t *TeamSpeakCore) BanClient(clid, timeSeconds int, reason string) (int, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return 0, ErrAuth
	}
	cmd := fmt.Sprintf("banclient clid=%d", clid)
	if timeSeconds > 0 {
		cmd += fmt.Sprintf(" time=%d", timeSeconds)
	}
	if reason != "" {
		cmd += fmt.Sprintf(" banreason=%s", TsEscape(reason))
	}
	rows, err := t.TsExec(cmd)
	if err != nil {
		return 0, err
	}
	if len(rows) > 0 {
		banID, err := strconv.Atoi(rows[0]["banid"])
		if err != nil {
			return 0, fmt.Errorf("invalid banid in response: %w", err)
		}
		return banID, nil
	}
	return 0, nil
}

func (t *TeamSpeakCore) BanDel(banID int) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple(fmt.Sprintf("bandel banid=%d", banID))
}

func (t *TeamSpeakCore) ServerList() ([]map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	return t.TsExec("serverlist")
}

func (t *TeamSpeakCore) ServerCreate(name string, props map[string]string) (map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	var b strings.Builder
	b.WriteString("servercreate virtualserver_name=")
	b.WriteString(TsEscape(name))
	for k, v := range props {
		b.WriteByte(' ')
		b.WriteString(TsEscape(k))
		b.WriteByte('=')
		b.WriteString(TsEscape(v))
	}
	rows, err := t.TsExec(b.String())
	if err != nil {
		return nil, err
	}
	if len(rows) > 0 {
		return rows[0], nil
	}
	return map[string]string{}, nil
}

func (t *TeamSpeakCore) ServerDelete(sid int) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple(fmt.Sprintf("serverdelete sid=%d", sid))
}

func (t *TeamSpeakCore) ServerStart(sid int) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple(fmt.Sprintf("serverstart sid=%d", sid))
}

func (t *TeamSpeakCore) ServerStop(sid int) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple(fmt.Sprintf("serverstop sid=%d", sid))
}

func (t *TeamSpeakCore) ServerSnapshotCreate() (string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return "", ErrAuth
	}
	rows, err := t.TsExec("serversnapshotcreate")
	if err != nil {
		return "", err
	}
	if len(rows) > 0 {
		if v, ok := rows[0]["data"]; ok {
			return v, nil
		}
		if v, ok := rows[0]["snapshot"]; ok {
			return v, nil
		}
	}
	return "", nil
}

func (t *TeamSpeakCore) ServerSnapshotDeploy(snapshot string) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple(fmt.Sprintf("serversnapshotdeploy %s", snapshot))
}

func (t *TeamSpeakCore) ServerTempPasswordAdd(password string, description string, duration int, targetCID int) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	cmd := fmt.Sprintf("servertemppasswordadd pw=%s desc=%s duration=%d tcid=%d",
		TsEscape(password), TsEscape(description), duration, targetCID)
	return t.tsExecSimple(cmd)
}

func (t *TeamSpeakCore) ServerTempPasswordDel(password string) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple(fmt.Sprintf("servertemppassworddel pw=%s", TsEscape(password)))
}

func (t *TeamSpeakCore) ServerTempPasswordList() ([]map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	return t.TsExec("servertemppasswordlist")
}

func (t *TeamSpeakCore) FTInitUpload(clientftfid, cid int, name string, cpw string, size int64, overwrite, resume bool) (map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	ow := 0
	if overwrite {
		ow = 1
	}
	res := 0
	if resume {
		res = 1
	}
	cmd := fmt.Sprintf("ftinitupload clientftfid=%d name=%s cid=%d cpw=%s size=%d overwrite=%d resume=%d",
		clientftfid, TsEscape(name), cid, TsEscape(cpw), size, ow, res)
	rows, err := t.TsExec(cmd)
	if err != nil {
		return nil, err
	}
	if len(rows) > 0 {
		return rows[0], nil
	}
	return map[string]string{}, nil
}

func (t *TeamSpeakCore) FTInitDownload(clientftfid, cid int, name string, cpw string, seekpos int64) (map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	cmd := fmt.Sprintf("ftinitdownload clientftfid=%d name=%s cid=%d cpw=%s seekpos=%d",
		clientftfid, TsEscape(name), cid, TsEscape(cpw), seekpos)
	rows, err := t.TsExec(cmd)
	if err != nil {
		return nil, err
	}
	if len(rows) > 0 {
		return rows[0], nil
	}
	return map[string]string{}, nil
}

func (t *TeamSpeakCore) LogView(lines, reverse, instance int, beginPos uint64) ([]map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	cmd := fmt.Sprintf("logview lines=%d reverse=%d instance=%d begin_pos=%d",
		lines, reverse, instance, beginPos)
	return t.TsExec(cmd)
}

func (t *TeamSpeakCore) LogAdd(logLevel int, logMsg string) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple(fmt.Sprintf("logadd loglevel=%d logmsg=%s", logLevel, TsEscape(logMsg)))
}

func (t *TeamSpeakCore) QueryLoginAdd(name string, cldbid int) (map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	cmd := fmt.Sprintf("queryloginadd client_login_name=%s", TsEscape(name))
	if cldbid > 0 {
		cmd += fmt.Sprintf(" cldbid=%d", cldbid)
	}
	rows, err := t.TsExec(cmd)
	if err != nil {
		return nil, err
	}
	if len(rows) > 0 {
		return rows[0], nil
	}
	return map[string]string{}, nil
}

func (t *TeamSpeakCore) QueryLoginDel(cldbid int) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple(fmt.Sprintf("querylogindel cldbid=%d", cldbid))
}

func (t *TeamSpeakCore) QueryLoginList() ([]map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	return t.TsExec("queryloginlist")
}

func (t *TeamSpeakCore) ApiKeyAdd(scope string, lifetime int, cldbid int) (map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	cmd := fmt.Sprintf("apikeyadd scope=%s", TsEscape(scope))
	if lifetime > 0 {
		cmd += fmt.Sprintf(" lifetime=%d", lifetime)
	}
	if cldbid > 0 {
		cmd += fmt.Sprintf(" cldbid=%d", cldbid)
	}
	rows, err := t.TsExec(cmd)
	if err != nil {
		return nil, err
	}
	if len(rows) > 0 {
		return rows[0], nil
	}
	return map[string]string{}, nil
}

func (t *TeamSpeakCore) ApiKeyDel(id int) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple(fmt.Sprintf("apikeydel id=%d", id))
}

func (t *TeamSpeakCore) ApiKeyList(cldbid int, start, duration int) ([]map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	cmd := "apikeylist"
	if cldbid > 0 {
		cmd += fmt.Sprintf(" cldbid=%d", cldbid)
	}
	if start > 0 {
		cmd += fmt.Sprintf(" start=%d", start)
	}
	if duration > 0 {
		cmd += fmt.Sprintf(" duration=%d", duration)
	}
	return t.TsExec(cmd)
}

func (t *TeamSpeakCore) ServerAddPerm(permID, permValue int, permNegated, permSkip bool) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	n := 0
	if permNegated {
		n = 1
	}
	s := 0
	if permSkip {
		s = 1
	}
	return t.tsExecSimple(fmt.Sprintf("serveraddperm permid=%d permvalue=%d permnegated=%d permskip=%d",
		permID, permValue, n, s))
}

func (t *TeamSpeakCore) ServerDelPerm(permID int) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple(fmt.Sprintf("serverdelperm permid=%d", permID))
}

func (t *TeamSpeakCore) ServerPermList() ([]map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	return t.TsExec("serverpermlist")
}

func (t *TeamSpeakCore) GlobalMessage(message string) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple(fmt.Sprintf("gm msg=%s", TsEscape(message)))
}

func (t *TeamSpeakCore) ServerGroupList() ([]map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	return t.TsExec("servergrouplist")
}

func (t *TeamSpeakCore) ServerGroupAddClient(sgid, cldbid int) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple(fmt.Sprintf("servergroupaddclient sgid=%d cldbid=%d", sgid, cldbid))
}

func (t *TeamSpeakCore) ServerGroupDelClient(sgid, cldbid int) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple(fmt.Sprintf("servergroupdelclient sgid=%d cldbid=%d", sgid, cldbid))
}

func (t *TeamSpeakCore) ChannelGroupsByClientID(cldbid int) ([]map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	return t.TsExec(fmt.Sprintf("channelgroupclientlist cldbid=%d", cldbid))
}

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

func (t *TeamSpeakCore) HostInfo() (map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	rows, err := t.TsExec("hostinfo")
	if err != nil {
		return nil, err
	}
	if len(rows) == 0 {
		return nil, ErrNotFound
	}
	return rows[0], nil
}

func (t *TeamSpeakCore) InstanceInfo() (map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	rows, err := t.TsExec("instanceinfo")
	if err != nil {
		return nil, err
	}
	if len(rows) == 0 {
		return nil, ErrNotFound
	}
	return rows[0], nil
}

func (t *TeamSpeakCore) InstanceEdit(props map[string]string) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	var b strings.Builder
	b.WriteString("instanceedit")
	for k, v := range props {
		b.WriteByte(' ')
		b.WriteString(k)
		b.WriteByte('=')
		b.WriteString(TsEscape(v))
	}
	return t.tsExecSimple(b.String())
}

func (t *TeamSpeakCore) BindingList() ([]map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	return t.TsExec("bindinglist")
}

func (t *TeamSpeakCore) ServerProcessStop() error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple("serverprocessstop")
}

func (t *TeamSpeakCore) ServerIdGetByPort(port int) (int, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return 0, ErrAuth
	}
	rows, err := t.TsExec(fmt.Sprintf("serveridgetbyport virtualserver_port=%d", port))
	if err != nil {
		return 0, err
	}
	if len(rows) == 0 {
		return 0, ErrNotFound
	}
	sid, err := strconv.Atoi(rows[0]["server_id"])
	if err != nil {
		return 0, fmt.Errorf("invalid server_id in response: %w", err)
	}
	return sid, nil
}

func (t *TeamSpeakCore) VerifyServerPassword(password string) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple(fmt.Sprintf("verifyserverpassword virtualserver_password=%s", TsEscape(password)))
}

func (t *TeamSpeakCore) VerifyChannelPassword(cid int, password string) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple(fmt.Sprintf("verifychannelpassword cid=%d cpw=%s", cid, TsEscape(password)))
}

func (t *TeamSpeakCore) BanClientDBID(cldbid, timeSeconds int, reason string) (int, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return 0, ErrAuth
	}
	cmd := fmt.Sprintf("banclient cldbid=%d time=%d", cldbid, timeSeconds)
	if reason != "" {
		cmd += fmt.Sprintf(" banreason=%s", TsEscape(reason))
	}
	rows, err := t.TsExec(cmd)
	if err != nil {
		return 0, err
	}
	if len(rows) == 0 {
		return 0, nil
	}
	banID, err := strconv.Atoi(rows[0]["banid"])
	if err != nil {
		return 0, fmt.Errorf("invalid banid in response: %w", err)
	}
	return banID, nil
}

func (t *TeamSpeakCore) BanAddMyTSID(mytsid string, timeSeconds int, reason string) (int, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return 0, ErrAuth
	}
	cmd := fmt.Sprintf("banadd mytsid=%s time=%d", TsEscape(mytsid), timeSeconds)
	if reason != "" {
		cmd += fmt.Sprintf(" banreason=%s", TsEscape(reason))
	}
	rows, err := t.TsExec(cmd)
	if err != nil {
		return 0, err
	}
	if len(rows) == 0 {
		return 0, nil
	}
	banID, err := strconv.Atoi(rows[0]["banid"])
	if err != nil {
		return 0, fmt.Errorf("invalid banid in response: %w", err)
	}
	return banID, nil
}

func (t *TeamSpeakCore) BanListPaginated(start, duration int) ([]map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	return t.TsExec(fmt.Sprintf("banlist -start=%d -duration=%d", start, duration))
}

func (t *TeamSpeakCore) ClientAddServerGroup(cldbid int, sgids []int) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	var b strings.Builder
	b.WriteString("clientaddservergroup cldbid=")
	b.WriteString(strconv.Itoa(cldbid))
	b.WriteString(" sgid=")
	for i, sg := range sgids {
		if i > 0 {
			b.WriteByte(',')
		}
		b.WriteString(strconv.Itoa(sg))
	}
	return t.tsExecSimple(b.String())
}

func (t *TeamSpeakCore) ClientDelServerGroup(cldbid int, sgids []int) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	var b strings.Builder
	b.WriteString("clientdelservergroup cldbid=")
	b.WriteString(strconv.Itoa(cldbid))
	b.WriteString(" sgid=")
	for i, sg := range sgids {
		if i > 0 {
			b.WriteByte(',')
		}
		b.WriteString(strconv.Itoa(sg))
	}
	return t.tsExecSimple(b.String())
}

func (t *TeamSpeakCore) tsOnEvent(event string, handler func(map[string]string)) {
	t.updateMu.Lock()
	t.eventHandlers[event] = append(t.eventHandlers[event], handler)
	t.updateMu.Unlock()
}

func (t *TeamSpeakCore) HandleServerEdited(handler func(map[string]string)) {
	t.tsOnEvent("notifyserveredited", handler)
}

func (t *TeamSpeakCore) HandleServerUpdated(handler func(map[string]string)) {
	t.tsOnEvent("notifyserverupdated", handler)
}

func (t *TeamSpeakCore) HandleChannelEdited(handler func(map[string]string)) {
	t.tsOnEvent("notifychanneledited", handler)
}

func (t *TeamSpeakCore) HandleChannelCreated(handler func(map[string]string)) {
	t.tsOnEvent("notifychannelcreated", handler)
}

func (t *TeamSpeakCore) HandleChannelDeleted(handler func(map[string]string)) {
	t.tsOnEvent("notifychanneldeleted", handler)
}

func (t *TeamSpeakCore) HandleChannelMoved(handler func(map[string]string)) {
	t.tsOnEvent("notifychannelmoved", handler)
}

func (t *TeamSpeakCore) HandleChannelDescriptionChanged(handler func(map[string]string)) {
	t.tsOnEvent("notifychanneldescriptionchanged", handler)
}

func (t *TeamSpeakCore) HandleChannelPasswordChanged(handler func(map[string]string)) {
	t.tsOnEvent("notifychannelpasswordchanged", handler)
}

func (t *TeamSpeakCore) HandleClientUpdated(handler func(map[string]string)) {
	t.tsOnEvent("notifyclientupdated", handler)
}

func (t *TeamSpeakCore) HandleTokenUsed(handler func(map[string]string)) {
	t.tsOnEvent("notifytokenused", handler)
}

func (t *TeamSpeakCore) HandleTalkStatusChange(handler func(map[string]string)) {
	t.tsOnEvent("notifytalkstatuschange", handler)
}

func (t *TeamSpeakCore) HandleConnectStatusChange(handler func(map[string]string)) {
	t.tsOnEvent("notifyconnectstatuschange", handler)
}

func (t *TeamSpeakCore) HandleCurrentServerConnectionChanged(handler func(map[string]string)) {
	t.tsOnEvent("notifycurrentserverconnectionchanged", handler)
}

func (t *TeamSpeakCore) ClientListExtended(flags ...string) ([]map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	cmd := "clientlist"
	for _, f := range flags {
		cmd += " " + f
	}
	return t.TsExec(cmd)
}

func (t *TeamSpeakCore) ChannelListExtended(flags ...string) ([]map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	cmd := "channellist"
	for _, f := range flags {
		cmd += " " + f
	}
	return t.TsExec(cmd)
}

func (t *TeamSpeakCore) ServerListExtended(flags ...string) ([]map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	cmd := "serverlist"
	for _, f := range flags {
		cmd += " " + f
	}
	return t.TsExec(cmd)
}

func (t *TeamSpeakCore) Set3DListenerAttributes(position, forward, up [3]float32) {
	t.mu.Lock()
	t.listener3D = ts3DListener{position: position, forward: forward, up: up}
	t.mu.Unlock()
}

func (t *TeamSpeakCore) SetChannel3DAttributes(clid int, position [3]float32) {
	t.mu.Lock()
	if t.client3DPos == nil {
		t.client3DPos = make(map[int][3]float32)
	}
	t.client3DPos[clid] = position
	t.mu.Unlock()
}

func (t *TeamSpeakCore) Set3DWaveAttributes(waveHandle int, position [3]float32) {
	t.mu.Lock()
	if t.wave3DPos == nil {
		t.wave3DPos = make(map[int][3]float32)
	}
	t.wave3DPos[waveHandle] = position
	t.mu.Unlock()
}

func (t *TeamSpeakCore) System3DSettings(distanceFactor, rolloffScale float32) {
	t.mu.Lock()
	t.distanceFactor3D = distanceFactor
	t.rolloffScale3D = rolloffScale
	t.mu.Unlock()
}

func (t *TeamSpeakCore) GetPlaybackDeviceList() []map[string]string {
	return []map[string]string{{"id": "default", "name": "Default Output", "isDefault": "1"}}
}

func (t *TeamSpeakCore) GetCaptureDeviceList() []map[string]string {
	return []map[string]string{{"id": "default", "name": "Default Input", "isDefault": "1"}}
}

func (t *TeamSpeakCore) GetPlaybackModeList() []string { return []string{"default"} }

func (t *TeamSpeakCore) GetCaptureModeList() []string { return []string{"default"} }

func (t *TeamSpeakCore) OpenPlaybackDevice(mode, deviceID string) error {
	t.mu.Lock()
	t.playbackDevice = deviceID
	t.mu.Unlock()
	return nil
}

func (t *TeamSpeakCore) OpenCaptureDevice(mode, deviceID string) error {
	t.mu.Lock()
	t.captureDevice = deviceID
	t.mu.Unlock()
	return nil
}

func (t *TeamSpeakCore) ClosePlaybackDevice() error {
	t.mu.Lock()
	t.playbackDevice = ""
	t.mu.Unlock()
	return nil
}

func (t *TeamSpeakCore) CloseCaptureDevice() error {
	t.mu.Lock()
	t.captureDevice = ""
	t.mu.Unlock()
	return nil
}

func (t *TeamSpeakCore) ActivateCaptureDevice() error {
	t.mu.Lock()
	t.captureActive = true
	t.mu.Unlock()
	return nil
}

func (t *TeamSpeakCore) GetPreProcessorInfo(key string) string {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if v, ok := t.preprocessorConfig[key]; ok {
		return v
	}
	return ""
}

func (t *TeamSpeakCore) GetPreProcessorConfig(key string) string {
	return t.GetPreProcessorInfo(key)
}

func (t *TeamSpeakCore) SetPreProcessorConfig(key, value string) {
	t.mu.Lock()
	if t.preprocessorConfig == nil {
		t.preprocessorConfig = make(map[string]string)
	}
	t.preprocessorConfig[key] = value
	t.mu.Unlock()
}

func (t *TeamSpeakCore) GetPlaybackConfig(key string) string {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if v, ok := t.playbackConfig[key]; ok {
		return v
	}
	return ""
}

func (t *TeamSpeakCore) SetPlaybackConfig(key, value string) {
	t.mu.Lock()
	if t.playbackConfig == nil {
		t.playbackConfig = make(map[string]string)
	}
	t.playbackConfig[key] = value
	t.mu.Unlock()
}

func (t *TeamSpeakCore) SetClientVolumeModifier(clid int, modifier float32) {
	t.mu.Lock()
	if t.clientVolume == nil {
		t.clientVolume = make(map[int]float32)
	}
	t.clientVolume[clid] = modifier
	t.mu.Unlock()
}

func (t *TeamSpeakCore) PlayWaveFile(path string) error {
	t.mu.Lock()
	t.waveNextHandle++
	t.mu.Unlock()
	return nil
}

func (t *TeamSpeakCore) PlayWaveFileHandle(path string, loop bool) (int, error) {
	t.mu.Lock()
	t.waveNextHandle++
	handle := t.waveNextHandle
	t.mu.Unlock()
	return handle, nil
}

func (t *TeamSpeakCore) PauseWaveFileHandle(handle int, pause bool) error {
	return nil
}

func (t *TeamSpeakCore) CloseWaveFileHandle(handle int) error {
	return nil
}

func (t *TeamSpeakCore) RegisterCustomDevice(deviceID, deviceDisplayName string, capFrequency, capChannels, playFrequency, playChannels int) error {
	t.mu.Lock()
	if t.customDevices == nil {
		t.customDevices = make(map[string]tsCustomDevice)
	}
	t.customDevices[deviceID] = tsCustomDevice{
		name:          deviceDisplayName,
		capFrequency:  capFrequency,
		capChannels:   capChannels,
		playFrequency: playFrequency,
		playChannels:  playChannels,
	}
	t.mu.Unlock()
	return nil
}

func (t *TeamSpeakCore) UnregisterCustomDevice(deviceID string) error {
	t.mu.Lock()
	delete(t.customDevices, deviceID)
	t.mu.Unlock()
	return nil
}

func (t *TeamSpeakCore) ProcessCustomCaptureData(deviceID string, pcm []int16) error {
	return nil
}

func (t *TeamSpeakCore) AcquireCustomPlaybackData(deviceID string, samples int) ([]int16, error) {
	return make([]int16, samples), nil
}

func (t *TeamSpeakCore) StartVoiceRecording() error {
	t.mu.Lock()
	t.recording = true
	t.mu.Unlock()
	return nil
}

func (t *TeamSpeakCore) StopVoiceRecording() error {
	t.mu.Lock()
	t.recording = false
	t.mu.Unlock()
	return nil
}

func (t *TeamSpeakCore) SetWhisperList(targetChannelIDs []int, targetClientIDs []int) error {
	t.mu.Lock()
	t.whisperChannels = targetChannelIDs
	t.whisperClients = targetClientIDs
	t.mu.Unlock()
	return nil
}

func (t *TeamSpeakCore) IsWhispering() bool {
	t.mu.RLock()
	defer t.mu.RUnlock()
	return len(t.whisperChannels) > 0 || len(t.whisperClients) > 0
}

func (t *TeamSpeakCore) IsReceivingWhisper(clid int) bool {
	return false
}

func (t *TeamSpeakCore) SetIsTalker(clid int, isTalker bool) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	val := "0"
	if isTalker {
		val = "1"
	}
	return t.tsExecSimple(fmt.Sprintf("clientedit clid=%d client_is_talker=%s", clid, val))
}

func (t *TeamSpeakCore) RequestClientsMove(clids []int, cid int, password string) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	for _, clid := range clids {
		cmd := fmt.Sprintf("clientmove clid=%d cid=%d", clid, cid)
		if password != "" {
			cmd += fmt.Sprintf(" cpw=%s", TsEscape(password))
		}
		if _, err := t.TsExecProof(cmd, &TsWant{name: "notifyclientmoved", key: "clid", val: strconv.Itoa(clid)}); err != nil {
			return err
		}
	}
	return nil
}

func (t *TeamSpeakCore) RequestClientsKickFromChannel(clids []int, message string) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	for _, clid := range clids {
		if err := t.tsExecSimple(fmt.Sprintf("clientkick clid=%d reasonid=4 reasonmsg=%s", clid, TsEscape(message))); err != nil {
			return err
		}
	}
	return nil
}

func (t *TeamSpeakCore) RequestClientsKickFromServer(clids []int, message string) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	for _, clid := range clids {
		if err := t.tsExecSimple(fmt.Sprintf("clientkick clid=%d reasonid=5 reasonmsg=%s", clid, TsEscape(message))); err != nil {
			return err
		}
	}
	return nil
}

func (t *TeamSpeakCore) RequestMuteClientsTemporary(clids []int) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	for _, clid := range clids {
		if err := t.tsExecSimple(fmt.Sprintf("clientedit clid=%d client_output_muted=1", clid)); err != nil {
			return err
		}
	}
	return nil
}

func (t *TeamSpeakCore) RequestUnmuteClientsTemporary(clids []int) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	for _, clid := range clids {
		if err := t.tsExecSimple(fmt.Sprintf("clientedit clid=%d client_output_muted=0", clid)); err != nil {
			return err
		}
	}
	return nil
}

func (t *TeamSpeakCore) RequestClientEditDescription(clid int, description string) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple(fmt.Sprintf("clientedit clid=%d client_description=%s", clid, TsEscape(description)))
}

func (t *TeamSpeakCore) GetAvatar(clid int) ([]byte, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	uid, err := t.ClientGetUIDFromCLID(clid)
	if err != nil {
		return nil, err
	}
	avatarPath := "/avatar_" + uid
	rows, err := t.TsExec(fmt.Sprintf("ftinitdownload clientftfid=1 name=%s cid=0 cpw= seekpos=0", TsEscape(avatarPath)))
	if err != nil {
		return nil, err
	}
	if len(rows) == 0 {
		return nil, ErrNotFound
	}
	return nil, fmt.Errorf("avatar file transfer info: port=%s, ftkey=%s, size=%s", rows[0]["port"], rows[0]["ftkey"], rows[0]["size"])
}

func (t *TeamSpeakCore) ChannelInfoRequest(cid int) (map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	rows, err := t.TsExec(fmt.Sprintf("channelinfo cid=%d", cid))
	if err != nil {
		return nil, err
	}
	if len(rows) == 0 {
		return nil, ErrNotFound
	}
	return rows[0], nil
}

func (t *TeamSpeakCore) RequestInfoUpdate(infoType string, id int) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	switch infoType {
	case "server":
		_, err := t.TsExec("serverinfo")
		return err
	case "channel":
		_, err := t.TsExec(fmt.Sprintf("channelinfo cid=%d", id))
		return err
	case "client":
		_, err := t.TsExec(fmt.Sprintf("clientinfo clid=%d", id))
		return err
	}
	return fmt.Errorf("unknown info type: %s", infoType)
}

func (t *TeamSpeakCore) ServerSnapshotDeployKeepFiles(snapshot string) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple(fmt.Sprintf("serversnapshotdeploy -keepfiles %s", TsEscape(snapshot)))
}

func (t *TeamSpeakCore) ServerSnapshotPassword(password string) (string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return "", ErrAuth
	}
	rows, err := t.TsExec(fmt.Sprintf("serversnapshotcreate -password=%s", TsEscape(password)))
	if err != nil {
		return "", err
	}
	if len(rows) == 0 {
		return "", nil
	}
	return rows[0]["data"], nil
}

func (t *TeamSpeakCore) GetBookmarkList() []map[string]string {
	t.mu.RLock()
	defer t.mu.RUnlock()
	result := make([]map[string]string, len(t.bookmarks))
	copy(result, t.bookmarks)
	return result
}

func (t *TeamSpeakCore) CreateBookmark(name, address, nickname, password string, isDefault bool) {
	t.mu.Lock()
	t.bookmarks = append(t.bookmarks, map[string]string{
		"name":       name,
		"address":    address,
		"nickname":   nickname,
		"password":   password,
		"is_default": fmt.Sprintf("%t", isDefault),
	})
	t.mu.Unlock()
}

func (t *TeamSpeakCore) GetProfileList() []map[string]string {
	return []map[string]string{{"id": "default", "name": "Default Profile"}}
}

func (t *TeamSpeakCore) PermissionListNew() ([]map[string]string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return nil, ErrAuth
	}
	return t.TsExec("permissionlist -new")
}

func (t *TeamSpeakCore) PermCommandsPermSID(command string, permSID string, permValue int) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed {
		return ErrAuth
	}
	return t.tsExecSimple(fmt.Sprintf("%s -permsid permsid=%s permvalue=%d", command, TsEscape(permSID), permValue))
}

func (t *TeamSpeakCore) DecodeLegacyCodec(codecType int, data []byte) ([]int16, error) {
	return nil, fmt.Errorf("legacy codec type %d not supported (Speex/CELT require native decoders)", codecType)
}

func (t *TeamSpeakCore) MuteChat(chatID string, muted bool) error {
	return fmt.Errorf("%w: %s does not support mute chat", ErrNotSupported, ts3Platform)
}

func (t *TeamSpeakCore) ArchiveChat(chatID string, archived bool) error {
	return fmt.Errorf("%w: %s does not support archive chat", ErrNotSupported, ts3Platform)
}

func (t *TeamSpeakCore) MarkUnread(chatID string, unread bool) error {
	return fmt.Errorf("%w: %s does not support mark unread", ErrNotSupported, ts3Platform)
}

func (t *TeamSpeakCore) UnpinAllMessages(chatID string) error {
	return fmt.Errorf("%w: %s does not support unpin all messages", ErrNotSupported, ts3Platform)
}

func (t *TeamSpeakCore) AcceptCall(callID string) (*CallSession, error) {
	return nil, fmt.Errorf("%w: %s does not support accept call", ErrNotSupported, ts3Platform)
}

func (t *TeamSpeakCore) DeclineCall(callID string) error {
	return fmt.Errorf("%w: %s does not support decline call", ErrNotSupported, ts3Platform)
}

func (t *TeamSpeakCore) SendLocation(chatID string, lat float64, lon float64) (*Message, error) {
	return nil, fmt.Errorf("%w: %s does not support send location", ErrNotSupported, ts3Platform)
}

type ts3DListener struct {
	position [3]float32
	forward  [3]float32
	up       [3]float32
}

type tsCustomDevice struct {
	name          string
	capFrequency  int
	capChannels   int
	playFrequency int
	playChannels  int
}
