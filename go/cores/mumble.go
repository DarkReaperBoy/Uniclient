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
	"crypto/subtle"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/binary"
	"encoding/hex"
	"encoding/pem"
	"encoding/xml"
	"errors"
	"fmt"
	"io"
	"math"
	"math/big"
	"net"
	"net/http"
	"sort"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"uniclient/utils"
)

// ════════════════════════════════════════════════════════════════════════════════
// Constants
// ════════════════════════════════════════════════════════════════════════════════

const (
	mumbleDefaultPort    = 64738
	mumbleMaxMsgBuffer   = 500
	mumblePingInterval   = 15 * time.Second
	mumbleReadTimeout    = 5 * time.Second
	mumbleDialTimeout    = 10 * time.Second
	mumbleMaxUDPSize     = 1024
	mumbleMaxPayload     = 1020 // 1024 - 4 byte crypto header
	mumbleCryptoOverhead = 4    // 1 byte IV + 3 byte tag
	mumbleLateWindow     = 30   // packets we consider "late" vs "lost"

	// Version: 1.5.517 in v2 format
	mumbleVersionMajor = 1
	mumbleVersionMinor = 5
	mumbleVersionPatch = 517
	mumbleVersionV1    = (mumbleVersionMajor << 16) | (mumbleVersionMinor << 8) | (mumbleVersionPatch & 0xFF)
	mumbleVersionV2    = (uint64(mumbleVersionMajor) << 48) | (uint64(mumbleVersionMinor) << 32) | (uint64(mumbleVersionPatch) << 16)
	mumbleRelease      = "Uniclient 1.5.517"
	mumbleOS           = "Linux"
	mumblePlatform     = "mumble"
)

// TCP message type IDs (Mumble.proto)
const (
	mumbleMsgVersion              = 0
	mumbleMsgUDPTunnel            = 1
	mumbleMsgAuthenticate         = 2
	mumbleMsgPing                 = 3
	mumbleMsgReject               = 4
	mumbleMsgServerSync           = 5
	mumbleMsgChannelRemove        = 6
	mumbleMsgChannelState         = 7
	mumbleMsgUserRemove           = 8
	mumbleMsgUserState            = 9
	mumbleMsgBanList              = 10
	mumbleMsgTextMessage          = 11
	mumbleMsgPermissionDenied     = 12
	mumbleMsgACL                  = 13
	mumbleMsgQueryUsers           = 14
	mumbleMsgCryptSetup           = 15
	mumbleMsgContextActionModify  = 16
	mumbleMsgContextAction        = 17
	mumbleMsgUserList             = 18
	mumbleMsgVoiceTarget          = 19
	mumbleMsgPermissionQuery      = 20
	mumbleMsgCodecVersion         = 21
	mumbleMsgUserStats            = 22
	mumbleMsgRequestBlob          = 23
	mumbleMsgServerConfig         = 24
	mumbleMsgSuggestConfig        = 25
	mumbleMsgPluginDataTransmission = 26
)

// Permission bits
const (
	mumblePermWrite            = 0x00001
	mumblePermTraverse         = 0x00002
	mumblePermEnter            = 0x00004
	mumblePermSpeak            = 0x00008
	mumblePermMuteDeafen       = 0x00010
	mumblePermMove             = 0x00020
	mumblePermMakeChannel      = 0x00040
	mumblePermLinkChannel      = 0x00080
	mumblePermWhisper          = 0x00100
	mumblePermTextMessage      = 0x00200
	mumblePermMakeTempChannel  = 0x00400
	mumblePermListen           = 0x00800
	mumblePermKick             = 0x10000
	mumblePermBan              = 0x20000
	mumblePermRegister         = 0x40000
	mumblePermSelfRegister     = 0x80000
	mumblePermResetUserContent = 0x100000
)

// Reject types
const (
	mumbleRejectNone             = 0
	mumbleRejectWrongVersion     = 1
	mumbleRejectInvalidUsername  = 2
	mumbleRejectWrongUserPW      = 3
	mumbleRejectWrongServerPW    = 4
	mumbleRejectUsernameInUse    = 5
	mumbleRejectServerFull       = 6
	mumbleRejectNoCertificate    = 7
	mumbleRejectAuthenticatorFail = 8
	mumbleRejectNoNewConnections = 9
)

// UDP audio types (legacy format)
const (
	mumbleUDPCELTAlpha = 0
	mumbleUDPPing      = 1
	mumbleUDPSpeex     = 2
	mumbleUDPCELTBeta  = 3
	mumbleUDPOpus      = 4
)

// Voice target constants
const (
	mumbleTargetNormal   = 0
	mumbleTargetLoopback = 31
)

// Audio context (server→client, protobuf only)
const (
	mumbleContextNormal   = 0
	mumbleContextShout    = 1
	mumbleContextWhisper  = 2
	mumbleContextListener = 3
)

// ════════════════════════════════════════════════════════════════════════════════
// Protobuf Wire Format Helpers
// ════════════════════════════════════════════════════════════════════════════════
//
// Mumble uses proto2 syntax. We hand-encode/decode to stay in one file.
// Protobuf wire types: 0=varint, 1=64-bit, 2=length-delimited, 5=32-bit

type pbEncoder struct {
	buf bytes.Buffer
}

var pbEncoderPool = sync.Pool{
	New: func() interface{} {
		return &pbEncoder{}
	},
}

func getPBEncoder() *pbEncoder {
	e := pbEncoderPool.Get().(*pbEncoder)
	e.buf.Reset()
	return e
}

func putPBEncoder(e *pbEncoder) {
	pbEncoderPool.Put(e)
}

func (e *pbEncoder) writeVarint(v uint64) {
	for v >= 0x80 {
		e.buf.WriteByte(byte(v) | 0x80)
		v >>= 7
	}
	e.buf.WriteByte(byte(v))
}

func (e *pbEncoder) writeTag(field int, wireType int) {
	e.writeVarint(uint64(field<<3 | wireType))
}

func (e *pbEncoder) writeUint32(field int, v uint32) {
	if v == 0 {
		return
	}
	e.writeTag(field, 0)
	e.writeVarint(uint64(v))
}

func (e *pbEncoder) writeUint32Always(field int, v uint32) {
	e.writeTag(field, 0)
	e.writeVarint(uint64(v))
}

func (e *pbEncoder) writeUint64(field int, v uint64) {
	if v == 0 {
		return
	}
	e.writeTag(field, 0)
	e.writeVarint(v)
}

func (e *pbEncoder) writeInt32(field int, v int32) {
	if v == 0 {
		return
	}
	e.writeTag(field, 0)
	if v >= 0 {
		e.writeVarint(uint64(v))
	} else {
		e.writeVarint(uint64(uint32(v)))
	}
}

func (e *pbEncoder) writeBool(field int, v bool) {
	if !v {
		return
	}
	e.writeTag(field, 0)
	e.buf.WriteByte(1)
}

func (e *pbEncoder) writeBoolAlways(field int, v bool) {
	e.writeTag(field, 0)
	if v {
		e.buf.WriteByte(1)
	} else {
		e.buf.WriteByte(0)
	}
}

func (e *pbEncoder) writeString(field int, v string) {
	if v == "" {
		return
	}
	e.writeTag(field, 2)
	e.writeVarint(uint64(len(v)))
	e.buf.WriteString(v)
}

func (e *pbEncoder) writeBytes(field int, v []byte) {
	if len(v) == 0 {
		return
	}
	e.writeTag(field, 2)
	e.writeVarint(uint64(len(v)))
	e.buf.Write(v)
}

func (e *pbEncoder) writeFloat(field int, v float32) {
	if v == 0 {
		return
	}
	e.writeTag(field, 5)
	var buf [4]byte
	binary.LittleEndian.PutUint32(buf[:], math.Float32bits(v))
	e.buf.Write(buf[:])
}

func (e *pbEncoder) writeFloatAlways(field int, v float32) {
	e.writeTag(field, 5)
	var buf [4]byte
	binary.LittleEndian.PutUint32(buf[:], math.Float32bits(v))
	e.buf.Write(buf[:])
}

func (e *pbEncoder) writeRepeatedUint32(field int, vs []uint32) {
	for _, v := range vs {
		e.writeTag(field, 0)
		e.writeVarint(uint64(v))
	}
}

func (e *pbEncoder) writeRepeatedInt32(field int, vs []int32) {
	for _, v := range vs {
		e.writeTag(field, 0)
		if v >= 0 {
			e.writeVarint(uint64(v))
		} else {
			e.writeVarint(uint64(uint32(v)))
		}
	}
}

func (e *pbEncoder) writeRepeatedString(field int, vs []string) {
	for _, v := range vs {
		e.writeTag(field, 2)
		e.writeVarint(uint64(len(v)))
		e.buf.WriteString(v)
	}
}

func (e *pbEncoder) writeRepeatedBytes(field int, vs [][]byte) {
	for _, v := range vs {
		e.writeTag(field, 2)
		e.writeVarint(uint64(len(v)))
		e.buf.Write(v)
	}
}

func (e *pbEncoder) writeRepeatedFloat(field int, vs []float32) {
	for _, v := range vs {
		e.writeTag(field, 5)
		var buf [4]byte
		binary.LittleEndian.PutUint32(buf[:], math.Float32bits(v))
		e.buf.Write(buf[:])
	}
}

func (e *pbEncoder) writePackedUint32(field int, vs []uint32) {
	if len(vs) == 0 {
		return
	}
	inner := getPBEncoder()
	for _, v := range vs {
		inner.writeVarint(uint64(v))
	}
	e.writeTag(field, 2)
	e.writeVarint(uint64(inner.buf.Len()))
	e.buf.Write(inner.buf.Bytes())
	putPBEncoder(inner)
}

func (e *pbEncoder) writeSubmessage(field int, sub *pbEncoder) {
	n := sub.buf.Len()
	if n == 0 {
		return
	}
	e.writeTag(field, 2)
	e.writeVarint(uint64(n))
	e.buf.Write(sub.buf.Bytes())
}

func (e *pbEncoder) bytes() []byte {
	return e.buf.Bytes()
}

// Protobuf decoder
type pbDecoder struct {
	data []byte
	pos  int
}

func newPBDecoder(data []byte) *pbDecoder {
	return &pbDecoder{data: data}
}

func (d *pbDecoder) remaining() int { return len(d.data) - d.pos }

func (d *pbDecoder) readVarint() (uint64, error) {
	var v uint64
	var shift uint
	for i := 0; i < 10; i++ {
		if d.pos >= len(d.data) {
			return 0, io.ErrUnexpectedEOF
		}
		b := d.data[d.pos]
		d.pos++
		v |= uint64(b&0x7F) << shift
		if b < 0x80 {
			return v, nil
		}
		shift += 7
	}
	return 0, errors.New("pbDecoder: varint overflow")
}

func (d *pbDecoder) readTag() (int, int, error) {
	v, err := d.readVarint()
	if err != nil {
		return 0, 0, err
	}
	return int(v >> 3), int(v & 0x7), nil
}

func (d *pbDecoder) readFixed32() (uint32, error) {
	if d.pos+4 > len(d.data) {
		return 0, io.ErrUnexpectedEOF
	}
	v := binary.LittleEndian.Uint32(d.data[d.pos:])
	d.pos += 4
	return v, nil
}

func (d *pbDecoder) readFixed64() (uint64, error) {
	if d.pos+8 > len(d.data) {
		return 0, io.ErrUnexpectedEOF
	}
	v := binary.LittleEndian.Uint64(d.data[d.pos:])
	d.pos += 8
	return v, nil
}

func (d *pbDecoder) readBytes() ([]byte, error) {
	ln, err := d.readVarint()
	if err != nil {
		return nil, err
	}
	if d.pos+int(ln) > len(d.data) {
		return nil, io.ErrUnexpectedEOF
	}
	v := make([]byte, ln)
	copy(v, d.data[d.pos:d.pos+int(ln)])
	d.pos += int(ln)
	return v, nil
}

func (d *pbDecoder) readString() (string, error) {
	ln, err := d.readVarint()
	if err != nil {
		return "", err
	}
	n := int(ln)
	if d.pos+n > len(d.data) {
		return "", io.ErrUnexpectedEOF
	}
	s := string(d.data[d.pos : d.pos+n])
	d.pos += n
	return s, nil
}

func (d *pbDecoder) skipField(wireType int) error {
	switch wireType {
	case 0: // varint
		_, err := d.readVarint()
		return err
	case 1: // 64-bit
		if d.pos+8 > len(d.data) {
			return io.ErrUnexpectedEOF
		}
		d.pos += 8
		return nil
	case 2: // length-delimited
		_, err := d.readBytes()
		return err
	case 5: // 32-bit
		if d.pos+4 > len(d.data) {
			return io.ErrUnexpectedEOF
		}
		d.pos += 4
		return nil
	default:
		return fmt.Errorf("pbDecoder: unknown wire type %d", wireType)
	}
}

// ════════════════════════════════════════════════════════════════════════════════
// Mumble Varint (PacketDataStream format — NOT standard protobuf varint)
// ════════════════════════════════════════════════════════════════════════════════

func mumbleVarintEncode(v int64) []byte {
	var buf [10]byte
	n := mumbleVarintEncodeTo(buf[:], v)
	out := make([]byte, n)
	copy(out, buf[:n])
	return out
}

func mumbleVarintEncodeTo(buf []byte, v int64) int {
	if v < 0 {
		if v >= -4 {
			buf[0] = byte(0xFC | (^v & 0x03))
			return 1
		}
		buf[0] = 0xF8
		n := mumbleVarintEncodeTo(buf[1:], -v)
		return 1 + n
	}
	uv := uint64(v)
	switch {
	case uv < 0x80:
		buf[0] = byte(uv)
		return 1
	case uv < 0x4000:
		buf[0] = byte(0x80 | (uv >> 8))
		buf[1] = byte(uv)
		return 2
	case uv < 0x200000:
		buf[0] = byte(0xC0 | (uv >> 16))
		buf[1] = byte(uv >> 8)
		buf[2] = byte(uv)
		return 3
	case uv < 0x10000000:
		buf[0] = byte(0xE0 | (uv >> 24))
		buf[1] = byte(uv >> 16)
		buf[2] = byte(uv >> 8)
		buf[3] = byte(uv)
		return 4
	case uv <= 0xFFFFFFFF:
		buf[0] = 0xF0
		buf[1] = byte(uv >> 24)
		buf[2] = byte(uv >> 16)
		buf[3] = byte(uv >> 8)
		buf[4] = byte(uv)
		return 5
	default:
		buf[0] = 0xF4
		buf[1] = byte(uv >> 56)
		buf[2] = byte(uv >> 48)
		buf[3] = byte(uv >> 40)
		buf[4] = byte(uv >> 32)
		buf[5] = byte(uv >> 24)
		buf[6] = byte(uv >> 16)
		buf[7] = byte(uv >> 8)
		buf[8] = byte(uv)
		return 9
	}
}

func mumbleVarintDecode(data []byte, pos int) (int64, int, error) {
	if pos >= len(data) {
		return 0, pos, io.ErrUnexpectedEOF
	}
	b := data[pos]
	switch {
	case b&0x80 == 0: // 0xxxxxxx — 7-bit positive
		return int64(b & 0x7F), pos + 1, nil
	case b&0xC0 == 0x80: // 10xxxxxx — 14-bit
		if pos+1 >= len(data) {
			return 0, pos, io.ErrUnexpectedEOF
		}
		return int64(uint16(b&0x3F)<<8 | uint16(data[pos+1])), pos + 2, nil
	case b&0xE0 == 0xC0: // 110xxxxx — 21-bit
		if pos+2 >= len(data) {
			return 0, pos, io.ErrUnexpectedEOF
		}
		return int64(uint32(b&0x1F)<<16 | uint32(data[pos+1])<<8 | uint32(data[pos+2])), pos + 3, nil
	case b&0xF0 == 0xE0: // 1110xxxx — 28-bit
		if pos+3 >= len(data) {
			return 0, pos, io.ErrUnexpectedEOF
		}
		return int64(uint32(b&0x0F)<<24 | uint32(data[pos+1])<<16 | uint32(data[pos+2])<<8 | uint32(data[pos+3])), pos + 4, nil
	case b&0xFC == 0xF0: // 111100xx — 32-bit
		if pos+4 >= len(data) {
			return 0, pos, io.ErrUnexpectedEOF
		}
		return int64(uint32(data[pos+1])<<24 | uint32(data[pos+2])<<16 | uint32(data[pos+3])<<8 | uint32(data[pos+4])), pos + 5, nil
	case b&0xFC == 0xF4: // 111101xx — 64-bit
		if pos+8 >= len(data) {
			return 0, pos, io.ErrUnexpectedEOF
		}
		return int64(binary.BigEndian.Uint64(data[pos+1:])), pos + 9, nil
	case b&0xFC == 0xF8: // 111110xx — negative varint
		v, newPos, err := mumbleVarintDecode(data, pos+1)
		if err != nil {
			return 0, pos, err
		}
		return -v, newPos, nil
	case b&0xFC == 0xFC: // 111111xx — -1 to -4
		return int64(^(b & 0x03)), pos + 1, nil
	default:
		return 0, pos, fmt.Errorf("mumbleVarintDecode: invalid prefix 0x%02x", b)
	}
}

// ════════════════════════════════════════════════════════════════════════════════
// OCB2-AES128 Encryption
// ════════════════════════════════════════════════════════════════════════════════
// Reference: grumble/pkg/cryptstate/ocb2/ocb2.go

const (
	ocb2BlockSize = 16
	ocb2TagSize   = 16
	ocb2NonceSize = 16
)

func ocb2XOR(dst, a, b []byte) {
	for i := 0; i < ocb2BlockSize; i++ {
		dst[i] = a[i] ^ b[i]
	}
}

func ocb2Times2(block []byte) {
	carry := (block[0] >> 7) & 0x1
	for i := 0; i < ocb2BlockSize-1; i++ {
		block[i] = (block[i] << 1) | ((block[i+1] >> 7) & 0x1)
	}
	block[ocb2BlockSize-1] = (block[ocb2BlockSize-1] << 1) ^ (carry * 135)
}

func ocb2Times3(block []byte) {
	carry := (block[0] >> 7) & 0x1
	for i := 0; i < ocb2BlockSize-1; i++ {
		block[i] ^= (block[i] << 1) | ((block[i+1] >> 7) & 0x1)
	}
	block[ocb2BlockSize-1] ^= ((block[ocb2BlockSize-1] << 1) ^ (carry * 135))
}

func ocb2Encrypt(ciph cipher.Block, dst, src, nonce, tag []byte) {
	var checksum, delta, tmp, pad [ocb2BlockSize]byte

	ciph.Encrypt(delta[:], nonce)

	remain := len(src)
	off := 0
	for remain > ocb2BlockSize {
		ocb2Times2(delta[:])
		ocb2XOR(tmp[:], delta[:], src[off:off+ocb2BlockSize])
		ciph.Encrypt(tmp[:], tmp[:])
		ocb2XOR(dst[off:off+ocb2BlockSize], delta[:], tmp[:])
		ocb2XOR(checksum[:], checksum[:], src[off:off+ocb2BlockSize])
		remain -= ocb2BlockSize
		off += ocb2BlockSize
	}

	ocb2Times2(delta[:])
	tmp = [ocb2BlockSize]byte{}
	num := remain * 8
	tmp[ocb2BlockSize-2] = byte(uint32(num) >> 8)
	tmp[ocb2BlockSize-1] = byte(num)
	ocb2XOR(tmp[:], tmp[:], delta[:])
	ciph.Encrypt(pad[:], tmp[:])
	tmp = [ocb2BlockSize]byte{}
	copy(tmp[:remain], src[off:off+remain])
	copy(tmp[remain:], pad[remain:])
	ocb2XOR(checksum[:], checksum[:], tmp[:])
	ocb2XOR(tmp[:], pad[:], tmp[:])
	copy(dst[off:off+remain], tmp[:remain])

	ocb2Times3(delta[:])
	ocb2XOR(tmp[:], delta[:], checksum[:])
	ciph.Encrypt(tag[:ocb2TagSize], tmp[:])
}

func ocb2Decrypt(ciph cipher.Block, plain, encrypted, nonce, tag []byte) bool {
	var checksum, delta, tmp, pad [ocb2BlockSize]byte

	ciph.Encrypt(delta[:], nonce)

	remain := len(encrypted)
	off := 0
	for remain > ocb2BlockSize {
		ocb2Times2(delta[:])
		ocb2XOR(tmp[:], delta[:], encrypted[off:off+ocb2BlockSize])
		ciph.Decrypt(tmp[:], tmp[:])
		ocb2XOR(plain[off:off+ocb2BlockSize], delta[:], tmp[:])
		ocb2XOR(checksum[:], checksum[:], plain[off:off+ocb2BlockSize])
		off += ocb2BlockSize
		remain -= ocb2BlockSize
	}

	ocb2Times2(delta[:])
	tmp = [ocb2BlockSize]byte{}
	num := remain * 8
	tmp[ocb2BlockSize-2] = byte(uint32(num) >> 8)
	tmp[ocb2BlockSize-1] = byte(num)
	ocb2XOR(tmp[:], tmp[:], delta[:])
	ciph.Encrypt(pad[:], tmp[:])
	clear(tmp[:])
	copy(tmp[:remain], encrypted[off:off+remain])
	ocb2XOR(tmp[:], tmp[:], pad[:])
	ocb2XOR(checksum[:], checksum[:], tmp[:])
	copy(plain[off:off+remain], tmp[:remain])

	ocb2Times3(delta[:])
	ocb2XOR(tmp[:], delta[:], checksum[:])
	var calcTag [ocb2TagSize]byte
	ciph.Encrypt(calcTag[:], tmp[:])

	return subtle.ConstantTimeCompare(calcTag[:len(tag)], tag) == 1
}

// CryptState manages OCB2-AES128 encryption state for the UDP channel
type mumbleCryptState struct {
	key           [16]byte
	encryptIV     [16]byte
	decryptIV     [16]byte
	cipher        cipher.Block
	decryptHist   [256]byte
	good          uint32
	late          uint32
	lost          uint32
	resync        uint32
	mu            sync.Mutex
}

func (cs *mumbleCryptState) init(key, clientNonce, serverNonce []byte) error {
	if len(key) != 16 || len(clientNonce) != 16 || len(serverNonce) != 16 {
		return errors.New("mumbleCryptState: invalid key/nonce length")
	}
	copy(cs.key[:], key)
	copy(cs.encryptIV[:], clientNonce) // we encrypt with client nonce
	copy(cs.decryptIV[:], serverNonce) // we decrypt with server nonce
	var err error
	cs.cipher, err = aes.NewCipher(cs.key[:])
	return err
}

func (cs *mumbleCryptState) incrementIV(iv []byte) {
	for i := 0; i < len(iv); i++ {
		iv[i]++
		if iv[i] != 0 {
			break
		}
	}
}

func (cs *mumbleCryptState) encrypt(dst, src []byte) int {
	cs.mu.Lock()
	defer cs.mu.Unlock()

	cs.incrementIV(cs.encryptIV[:])

	var tag [ocb2TagSize]byte
	ocb2Encrypt(cs.cipher, dst[4:4+len(src)], src, cs.encryptIV[:], tag[:])

	dst[0] = cs.encryptIV[0]
	dst[1] = tag[0]
	dst[2] = tag[1]
	dst[3] = tag[2]
	return 4 + len(src)
}

func (cs *mumbleCryptState) decrypt(dst, src []byte) (int, error) {
	if len(src) < 4 {
		return 0, errors.New("mumbleCryptState: packet too short")
	}

	cs.mu.Lock()
	defer cs.mu.Unlock()

	ivByte := src[0]
	tagCheck := src[1:4]
	ciphertext := src[4:]
	plainLen := len(ciphertext)

	// Reconstruct full IV from single byte
	var iv [16]byte
	copy(iv[:], cs.decryptIV[:])

	diff := int(ivByte) - int(cs.decryptIV[0])
	if diff < 0 {
		diff += 256
	}

	if diff == 1 {
		// In order — most common case
		iv[0] = ivByte
	} else if diff > 128 {
		// Late packet (negative diff, wrapped around)
		// Temporarily adjust IV
		copy(iv[:], cs.decryptIV[:])
		iv[0] = ivByte
		// Decrement byte 1 to go back
		if ivByte > cs.decryptIV[0] {
			// Late by (256 - diff) packets, IV byte[1] was one less
			for i := 1; i < 16; i++ {
				iv[i]--
				if iv[i] != 0xFF {
					break
				}
			}
		}
	} else if diff > 1 {
		// Lost packets — gap
		lostCount := diff - 1
		cs.lost += uint32(lostCount)
		iv[0] = ivByte
		// Advance the higher IV bytes for the gap
		for i := 0; i < lostCount; i++ {
			cs.incrementIV(cs.decryptIV[:])
		}
		// Now decryptIV should be one behind
		cs.incrementIV(cs.decryptIV[:])
		copy(iv[:], cs.decryptIV[:])
	} else {
		// diff == 0, duplicate
		return 0, errors.New("mumbleCryptState: duplicate packet")
	}

	var tag [ocb2TagSize]byte
	tag[0] = tagCheck[0]
	tag[1] = tagCheck[1]
	tag[2] = tagCheck[2]
	ok := ocb2Decrypt(cs.cipher, dst[:plainLen], ciphertext, iv[:], tag[:3])
	if !ok {
		return 0, errors.New("mumbleCryptState: decrypt failed")
	}

	if diff >= 1 && diff <= 128 {
		copy(cs.decryptIV[:], iv[:])
		cs.good++
	} else {
		cs.late++
	}

	return plainLen, nil
}

// ════════════════════════════════════════════════════════════════════════════════
// Protobuf Message Structs
// ════════════════════════════════════════════════════════════════════════════════

type mumbleVersion struct {
	VersionV1 uint32
	VersionV2 uint64
	Release   string
	OS        string
	OSVersion string
}

func (m *mumbleVersion) marshal() []byte {
	var e pbEncoder
	e.writeUint32(1, m.VersionV1)
	e.writeUint64(5, m.VersionV2)
	e.writeString(2, m.Release)
	e.writeString(3, m.OS)
	e.writeString(4, m.OSVersion)
	return e.bytes()
}

func (m *mumbleVersion) unmarshal(data []byte) error {
	d := newPBDecoder(data)
	for d.remaining() > 0 {
		field, wt, err := d.readTag()
		if err != nil {
			return err
		}
		switch field {
		case 1:
			v, err := d.readVarint()
			if err != nil { return err }
			m.VersionV1 = uint32(v)
		case 5:
			v, err := d.readVarint()
			if err != nil { return err }
			m.VersionV2 = v
		case 2:
			s, err := d.readString()
			if err != nil { return err }
			m.Release = s
		case 3:
			s, err := d.readString()
			if err != nil { return err }
			m.OS = s
		case 4:
			s, err := d.readString()
			if err != nil { return err }
			m.OSVersion = s
		default:
			if err := d.skipField(wt); err != nil { return err }
		}
	}
	return nil
}

type mumbleAuthenticate struct {
	Username     string
	Password     string
	Tokens       []string
	CELTVersions []int32
	Opus         bool
	ClientType   int32
}

func (m *mumbleAuthenticate) marshal() []byte {
	var e pbEncoder
	e.writeString(1, m.Username)
	e.writeString(2, m.Password)
	e.writeRepeatedString(3, m.Tokens)
	e.writeRepeatedInt32(4, m.CELTVersions)
	e.writeBool(5, m.Opus)
	e.writeInt32(6, m.ClientType)
	return e.bytes()
}

type mumblePingMsg struct {
	Timestamp  uint64
	Good       uint32
	Late       uint32
	Lost       uint32
	Resync     uint32
	UDPPackets uint32
	TCPPackets uint32
	UDPPingAvg float32
	UDPPingVar float32
	TCPPingAvg float32
	TCPPingVar float32
}

func (m *mumblePingMsg) marshal() []byte {
	e := getPBEncoder()
	e.writeUint64(1, m.Timestamp)
	e.writeUint32(2, m.Good)
	e.writeUint32(3, m.Late)
	e.writeUint32(4, m.Lost)
	e.writeUint32(5, m.Resync)
	e.writeUint32(6, m.UDPPackets)
	e.writeUint32(7, m.TCPPackets)
	e.writeFloat(8, m.UDPPingAvg)
	e.writeFloat(9, m.UDPPingVar)
	e.writeFloat(10, m.TCPPingAvg)
	e.writeFloat(11, m.TCPPingVar)
	out := make([]byte, e.buf.Len())
	copy(out, e.bytes())
	putPBEncoder(e)
	return out
}

func (m *mumblePingMsg) unmarshal(data []byte) error {
	d := newPBDecoder(data)
	for d.remaining() > 0 {
		field, wt, err := d.readTag()
		if err != nil { return err }
		switch field {
		case 1:
			v, err := d.readVarint(); if err != nil { return err }
			m.Timestamp = v
		case 2:
			v, err := d.readVarint(); if err != nil { return err }
			m.Good = uint32(v)
		case 3:
			v, err := d.readVarint(); if err != nil { return err }
			m.Late = uint32(v)
		case 4:
			v, err := d.readVarint(); if err != nil { return err }
			m.Lost = uint32(v)
		case 5:
			v, err := d.readVarint(); if err != nil { return err }
			m.Resync = uint32(v)
		case 6:
			v, err := d.readVarint(); if err != nil { return err }
			m.UDPPackets = uint32(v)
		case 7:
			v, err := d.readVarint(); if err != nil { return err }
			m.TCPPackets = uint32(v)
		case 8:
			v, err := d.readFixed32(); if err != nil { return err }
			m.UDPPingAvg = math.Float32frombits(v)
		case 9:
			v, err := d.readFixed32(); if err != nil { return err }
			m.UDPPingVar = math.Float32frombits(v)
		case 10:
			v, err := d.readFixed32(); if err != nil { return err }
			m.TCPPingAvg = math.Float32frombits(v)
		case 11:
			v, err := d.readFixed32(); if err != nil { return err }
			m.TCPPingVar = math.Float32frombits(v)
		default:
			if err := d.skipField(wt); err != nil { return err }
		}
	}
	return nil
}

type mumbleReject struct {
	Type   uint32
	Reason string
}

func (m *mumbleReject) unmarshal(data []byte) error {
	d := newPBDecoder(data)
	for d.remaining() > 0 {
		field, wt, err := d.readTag()
		if err != nil { return err }
		switch field {
		case 1:
			v, err := d.readVarint(); if err != nil { return err }
			m.Type = uint32(v)
		case 2:
			s, err := d.readString(); if err != nil { return err }
			m.Reason = s
		default:
			if err := d.skipField(wt); err != nil { return err }
		}
	}
	return nil
}

type mumbleServerSync struct {
	Session      uint32
	MaxBandwidth uint32
	WelcomeText  string
	Permissions  uint64
}

func (m *mumbleServerSync) unmarshal(data []byte) error {
	d := newPBDecoder(data)
	for d.remaining() > 0 {
		field, wt, err := d.readTag()
		if err != nil { return err }
		switch field {
		case 1:
			v, err := d.readVarint(); if err != nil { return err }
			m.Session = uint32(v)
		case 2:
			v, err := d.readVarint(); if err != nil { return err }
			m.MaxBandwidth = uint32(v)
		case 3:
			s, err := d.readString(); if err != nil { return err }
			m.WelcomeText = s
		case 4:
			v, err := d.readVarint(); if err != nil { return err }
			m.Permissions = v
		default:
			if err := d.skipField(wt); err != nil { return err }
		}
	}
	return nil
}

type mumbleChannelStateMsg struct {
	ChannelID         uint32
	Parent            uint32
	Name              string
	Links             []uint32
	Description       string
	LinksAdd          []uint32
	LinksRemove       []uint32
	Temporary         bool
	Position          int32
	DescriptionHash   []byte
	MaxUsers          uint32
	IsEnterRestricted bool
	CanEnter          bool

	HasParent    bool // track if parent was set (0 is valid — root)
	HasChannelID bool
}

func (m *mumbleChannelStateMsg) marshal() []byte {
	var e pbEncoder
	if m.HasChannelID {
		e.writeUint32Always(1, m.ChannelID)
	}
	if m.HasParent {
		e.writeUint32Always(2, m.Parent)
	}
	e.writeString(3, m.Name)
	e.writeRepeatedUint32(4, m.Links)
	e.writeString(5, m.Description)
	e.writeRepeatedUint32(6, m.LinksAdd)
	e.writeRepeatedUint32(7, m.LinksRemove)
	e.writeBool(8, m.Temporary)
	e.writeInt32(9, m.Position)
	e.writeBytes(10, m.DescriptionHash)
	e.writeUint32(11, m.MaxUsers)
	return e.bytes()
}

func (m *mumbleChannelStateMsg) unmarshal(data []byte) error {
	d := newPBDecoder(data)
	for d.remaining() > 0 {
		field, wt, err := d.readTag()
		if err != nil { return err }
		switch field {
		case 1:
			v, err := d.readVarint(); if err != nil { return err }
			m.ChannelID = uint32(v); m.HasChannelID = true
		case 2:
			v, err := d.readVarint(); if err != nil { return err }
			m.Parent = uint32(v); m.HasParent = true
		case 3:
			s, err := d.readString(); if err != nil { return err }
			m.Name = s
		case 4:
			v, err := d.readVarint(); if err != nil { return err }
			m.Links = append(m.Links, uint32(v))
		case 5:
			s, err := d.readString(); if err != nil { return err }
			m.Description = s
		case 6:
			v, err := d.readVarint(); if err != nil { return err }
			m.LinksAdd = append(m.LinksAdd, uint32(v))
		case 7:
			v, err := d.readVarint(); if err != nil { return err }
			m.LinksRemove = append(m.LinksRemove, uint32(v))
		case 8:
			v, err := d.readVarint(); if err != nil { return err }
			m.Temporary = v != 0
		case 9:
			v, err := d.readVarint(); if err != nil { return err }
			m.Position = int32(v)
		case 10:
			b, err := d.readBytes(); if err != nil { return err }
			m.DescriptionHash = b
		case 11:
			v, err := d.readVarint(); if err != nil { return err }
			m.MaxUsers = uint32(v)
		case 12:
			v, err := d.readVarint(); if err != nil { return err }
			m.IsEnterRestricted = v != 0
		case 13:
			v, err := d.readVarint(); if err != nil { return err }
			m.CanEnter = v != 0
		default:
			if err := d.skipField(wt); err != nil { return err }
		}
	}
	return nil
}

type mumbleUserStateMsg struct {
	Session                uint32
	Actor                  uint32
	Name                   string
	UserID                 uint32
	ChannelID              uint32
	Mute                   bool
	Deaf                   bool
	Suppress               bool
	SelfMute               bool
	SelfDeaf               bool
	Texture                []byte
	PluginContext           []byte
	PluginIdentity         string
	Comment                string
	Hash                   string
	CommentHash            []byte
	TextureHash            []byte
	PrioritySpeaker        bool
	Recording              bool
	TemporaryAccessTokens  []string
	ListeningChannelAdd    []uint32
	ListeningChannelRemove []uint32
	// VolumeAdjustments stored as submessages
	ListeningVolumeAdj []mumbleVolumeAdj

	HasSession   bool
	HasActor     bool
	HasUserID    bool
	HasChannelID bool
	HasMute      bool
	HasDeaf      bool
	HasSuppress  bool
	HasSelfMute  bool
	HasSelfDeaf  bool
	HasPrioritySpeaker bool
	HasRecording bool
}

type mumbleVolumeAdj struct {
	ListeningChannel uint32
	VolumeAdjustment float32
}

func (m *mumbleUserStateMsg) marshal() []byte {
	var e pbEncoder
	if m.HasSession {
		e.writeUint32Always(1, m.Session)
	}
	if m.HasActor {
		e.writeUint32Always(2, m.Actor)
	}
	e.writeString(3, m.Name)
	if m.HasUserID {
		e.writeUint32Always(4, m.UserID)
	}
	if m.HasChannelID {
		e.writeUint32Always(5, m.ChannelID)
	}
	if m.HasMute {
		e.writeBoolAlways(6, m.Mute)
	}
	if m.HasDeaf {
		e.writeBoolAlways(7, m.Deaf)
	}
	if m.HasSuppress {
		e.writeBoolAlways(8, m.Suppress)
	}
	if m.HasSelfMute {
		e.writeBoolAlways(9, m.SelfMute)
	}
	if m.HasSelfDeaf {
		e.writeBoolAlways(10, m.SelfDeaf)
	}
	e.writeBytes(11, m.Texture)
	e.writeBytes(12, m.PluginContext)
	e.writeString(13, m.PluginIdentity)
	e.writeString(14, m.Comment)
	e.writeString(15, m.Hash)
	e.writeBytes(16, m.CommentHash)
	e.writeBytes(17, m.TextureHash)
	if m.HasPrioritySpeaker {
		e.writeBoolAlways(18, m.PrioritySpeaker)
	}
	if m.HasRecording {
		e.writeBoolAlways(19, m.Recording)
	}
	e.writeRepeatedString(20, m.TemporaryAccessTokens)
	e.writeRepeatedUint32(21, m.ListeningChannelAdd)
	e.writeRepeatedUint32(22, m.ListeningChannelRemove)
	for _, va := range m.ListeningVolumeAdj {
		var sub pbEncoder
		sub.writeUint32Always(1, va.ListeningChannel)
		sub.writeFloatAlways(2, va.VolumeAdjustment)
		e.writeSubmessage(23, &sub)
	}
	return e.bytes()
}

func (m *mumbleUserStateMsg) unmarshal(data []byte) error {
	d := newPBDecoder(data)
	for d.remaining() > 0 {
		field, wt, err := d.readTag()
		if err != nil { return err }
		switch field {
		case 1:
			v, err := d.readVarint(); if err != nil { return err }
			m.Session = uint32(v); m.HasSession = true
		case 2:
			v, err := d.readVarint(); if err != nil { return err }
			m.Actor = uint32(v); m.HasActor = true
		case 3:
			s, err := d.readString(); if err != nil { return err }
			m.Name = s
		case 4:
			v, err := d.readVarint(); if err != nil { return err }
			m.UserID = uint32(v); m.HasUserID = true
		case 5:
			v, err := d.readVarint(); if err != nil { return err }
			m.ChannelID = uint32(v); m.HasChannelID = true
		case 6:
			v, err := d.readVarint(); if err != nil { return err }
			m.Mute = v != 0; m.HasMute = true
		case 7:
			v, err := d.readVarint(); if err != nil { return err }
			m.Deaf = v != 0; m.HasDeaf = true
		case 8:
			v, err := d.readVarint(); if err != nil { return err }
			m.Suppress = v != 0; m.HasSuppress = true
		case 9:
			v, err := d.readVarint(); if err != nil { return err }
			m.SelfMute = v != 0; m.HasSelfMute = true
		case 10:
			v, err := d.readVarint(); if err != nil { return err }
			m.SelfDeaf = v != 0; m.HasSelfDeaf = true
		case 11:
			b, err := d.readBytes(); if err != nil { return err }
			m.Texture = b
		case 12:
			b, err := d.readBytes(); if err != nil { return err }
			m.PluginContext = b
		case 13:
			s, err := d.readString(); if err != nil { return err }
			m.PluginIdentity = s
		case 14:
			s, err := d.readString(); if err != nil { return err }
			m.Comment = s
		case 15:
			s, err := d.readString(); if err != nil { return err }
			m.Hash = s
		case 16:
			b, err := d.readBytes(); if err != nil { return err }
			m.CommentHash = b
		case 17:
			b, err := d.readBytes(); if err != nil { return err }
			m.TextureHash = b
		case 18:
			v, err := d.readVarint(); if err != nil { return err }
			m.PrioritySpeaker = v != 0; m.HasPrioritySpeaker = true
		case 19:
			v, err := d.readVarint(); if err != nil { return err }
			m.Recording = v != 0; m.HasRecording = true
		case 20:
			s, err := d.readString(); if err != nil { return err }
			m.TemporaryAccessTokens = append(m.TemporaryAccessTokens, s)
		case 21:
			v, err := d.readVarint(); if err != nil { return err }
			m.ListeningChannelAdd = append(m.ListeningChannelAdd, uint32(v))
		case 22:
			v, err := d.readVarint(); if err != nil { return err }
			m.ListeningChannelRemove = append(m.ListeningChannelRemove, uint32(v))
		case 23:
			b, err := d.readBytes(); if err != nil { return err }
			var va mumbleVolumeAdj
			sd := newPBDecoder(b)
			for sd.remaining() > 0 {
				sf, swt, serr := sd.readTag()
				if serr != nil { return serr }
				switch sf {
				case 1:
					sv, serr := sd.readVarint(); if serr != nil { return serr }
					va.ListeningChannel = uint32(sv)
				case 2:
					sv, serr := sd.readFixed32(); if serr != nil { return serr }
					va.VolumeAdjustment = math.Float32frombits(sv)
				default:
					if serr := sd.skipField(swt); serr != nil { return serr }
				}
			}
			m.ListeningVolumeAdj = append(m.ListeningVolumeAdj, va)
		default:
			if err := d.skipField(wt); err != nil { return err }
		}
	}
	return nil
}

type mumbleUserRemoveMsg struct {
	Session        uint32
	Actor          uint32
	Reason         string
	Ban            bool
	BanCertificate bool
	BanIP          bool
}

func (m *mumbleUserRemoveMsg) marshal() []byte {
	var e pbEncoder
	e.writeUint32Always(1, m.Session)
	e.writeUint32(2, m.Actor)
	e.writeString(3, m.Reason)
	e.writeBool(4, m.Ban)
	e.writeBool(5, m.BanCertificate)
	e.writeBool(6, m.BanIP)
	return e.bytes()
}

func (m *mumbleUserRemoveMsg) unmarshal(data []byte) error {
	d := newPBDecoder(data)
	for d.remaining() > 0 {
		field, wt, err := d.readTag()
		if err != nil { return err }
		switch field {
		case 1:
			v, err := d.readVarint(); if err != nil { return err }
			m.Session = uint32(v)
		case 2:
			v, err := d.readVarint(); if err != nil { return err }
			m.Actor = uint32(v)
		case 3:
			s, err := d.readString(); if err != nil { return err }
			m.Reason = s
		case 4:
			v, err := d.readVarint(); if err != nil { return err }
			m.Ban = v != 0
		case 5:
			v, err := d.readVarint(); if err != nil { return err }
			m.BanCertificate = v != 0
		case 6:
			v, err := d.readVarint(); if err != nil { return err }
			m.BanIP = v != 0
		default:
			if err := d.skipField(wt); err != nil { return err }
		}
	}
	return nil
}

type mumbleTextMsg struct {
	Actor     uint32
	Session   []uint32 // target user sessions
	ChannelID []uint32 // target channels
	TreeID    []uint32 // target trees
	Message   string
}

func (m *mumbleTextMsg) marshal() []byte {
	var e pbEncoder
	e.writeUint32(1, m.Actor)
	e.writeRepeatedUint32(2, m.Session)
	e.writeRepeatedUint32(3, m.ChannelID)
	e.writeRepeatedUint32(4, m.TreeID)
	e.writeString(5, m.Message)
	return e.bytes()
}

func (m *mumbleTextMsg) unmarshal(data []byte) error {
	d := newPBDecoder(data)
	for d.remaining() > 0 {
		field, wt, err := d.readTag()
		if err != nil { return err }
		switch field {
		case 1:
			v, err := d.readVarint(); if err != nil { return err }
			m.Actor = uint32(v)
		case 2:
			v, err := d.readVarint(); if err != nil { return err }
			m.Session = append(m.Session, uint32(v))
		case 3:
			v, err := d.readVarint(); if err != nil { return err }
			m.ChannelID = append(m.ChannelID, uint32(v))
		case 4:
			v, err := d.readVarint(); if err != nil { return err }
			m.TreeID = append(m.TreeID, uint32(v))
		case 5:
			s, err := d.readString(); if err != nil { return err }
			m.Message = s
		default:
			if err := d.skipField(wt); err != nil { return err }
		}
	}
	return nil
}

type mumbleChannelRemoveMsg struct {
	ChannelID uint32
}

func (m *mumbleChannelRemoveMsg) marshal() []byte {
	var e pbEncoder
	e.writeUint32Always(1, m.ChannelID)
	return e.bytes()
}

func (m *mumbleChannelRemoveMsg) unmarshal(data []byte) error {
	d := newPBDecoder(data)
	for d.remaining() > 0 {
		field, wt, err := d.readTag()
		if err != nil { return err }
		switch field {
		case 1:
			v, err := d.readVarint(); if err != nil { return err }
			m.ChannelID = uint32(v)
		default:
			if err := d.skipField(wt); err != nil { return err }
		}
	}
	return nil
}

type mumbleCryptSetupMsg struct {
	Key         []byte
	ClientNonce []byte
	ServerNonce []byte
}

func (m *mumbleCryptSetupMsg) marshal() []byte {
	var e pbEncoder
	e.writeBytes(1, m.Key)
	e.writeBytes(2, m.ClientNonce)
	e.writeBytes(3, m.ServerNonce)
	return e.bytes()
}

func (m *mumbleCryptSetupMsg) unmarshal(data []byte) error {
	d := newPBDecoder(data)
	for d.remaining() > 0 {
		field, wt, err := d.readTag()
		if err != nil { return err }
		switch field {
		case 1:
			b, err := d.readBytes(); if err != nil { return err }
			m.Key = b
		case 2:
			b, err := d.readBytes(); if err != nil { return err }
			m.ClientNonce = b
		case 3:
			b, err := d.readBytes(); if err != nil { return err }
			m.ServerNonce = b
		default:
			if err := d.skipField(wt); err != nil { return err }
		}
	}
	return nil
}

type mumbleCodecVersionMsg struct {
	Alpha       int32
	Beta        int32
	PreferAlpha bool
	Opus        bool
}

func (m *mumbleCodecVersionMsg) unmarshal(data []byte) error {
	d := newPBDecoder(data)
	for d.remaining() > 0 {
		field, wt, err := d.readTag()
		if err != nil { return err }
		switch field {
		case 1:
			v, err := d.readVarint(); if err != nil { return err }
			m.Alpha = int32(v)
		case 2:
			v, err := d.readVarint(); if err != nil { return err }
			m.Beta = int32(v)
		case 3:
			v, err := d.readVarint(); if err != nil { return err }
			m.PreferAlpha = v != 0
		case 4:
			v, err := d.readVarint(); if err != nil { return err }
			m.Opus = v != 0
		default:
			if err := d.skipField(wt); err != nil { return err }
		}
	}
	return nil
}

type MumbleServerConfig struct {
	MaxBandwidth       uint32
	WelcomeText        string
	AllowHTML          bool
	MessageLength      uint32
	ImageMessageLength uint32
	MaxUsers           uint32
	RecordingAllowed   bool
}

func (m *MumbleServerConfig) unmarshal(data []byte) error {
	d := newPBDecoder(data)
	for d.remaining() > 0 {
		field, wt, err := d.readTag()
		if err != nil { return err }
		switch field {
		case 1:
			v, err := d.readVarint(); if err != nil { return err }
			m.MaxBandwidth = uint32(v)
		case 2:
			s, err := d.readString(); if err != nil { return err }
			m.WelcomeText = s
		case 3:
			v, err := d.readVarint(); if err != nil { return err }
			m.AllowHTML = v != 0
		case 4:
			v, err := d.readVarint(); if err != nil { return err }
			m.MessageLength = uint32(v)
		case 5:
			v, err := d.readVarint(); if err != nil { return err }
			m.ImageMessageLength = uint32(v)
		case 6:
			v, err := d.readVarint(); if err != nil { return err }
			m.MaxUsers = uint32(v)
		case 7:
			v, err := d.readVarint(); if err != nil { return err }
			m.RecordingAllowed = v != 0
		default:
			if err := d.skipField(wt); err != nil { return err }
		}
	}
	return nil
}

type mumbleSuggestConfigMsg struct {
	VersionV1   uint32
	VersionV2   uint64
	Positional  bool
	PushToTalk  bool
}

func (m *mumbleSuggestConfigMsg) unmarshal(data []byte) error {
	d := newPBDecoder(data)
	for d.remaining() > 0 {
		field, wt, err := d.readTag()
		if err != nil { return err }
		switch field {
		case 1:
			v, err := d.readVarint(); if err != nil { return err }
			m.VersionV1 = uint32(v)
		case 4:
			v, err := d.readVarint(); if err != nil { return err }
			m.VersionV2 = v
		case 2:
			v, err := d.readVarint(); if err != nil { return err }
			m.Positional = v != 0
		case 3:
			v, err := d.readVarint(); if err != nil { return err }
			m.PushToTalk = v != 0
		default:
			if err := d.skipField(wt); err != nil { return err }
		}
	}
	return nil
}

type mumblePermissionDeniedMsg struct {
	Permission uint32
	ChannelID  uint32
	Session    uint32
	Reason     string
	Type       uint32
	Name       string
}

func (m *mumblePermissionDeniedMsg) unmarshal(data []byte) error {
	d := newPBDecoder(data)
	for d.remaining() > 0 {
		field, wt, err := d.readTag()
		if err != nil { return err }
		switch field {
		case 1:
			v, err := d.readVarint(); if err != nil { return err }
			m.Permission = uint32(v)
		case 2:
			v, err := d.readVarint(); if err != nil { return err }
			m.ChannelID = uint32(v)
		case 3:
			v, err := d.readVarint(); if err != nil { return err }
			m.Session = uint32(v)
		case 4:
			s, err := d.readString(); if err != nil { return err }
			m.Reason = s
		case 5:
			v, err := d.readVarint(); if err != nil { return err }
			m.Type = uint32(v)
		case 6:
			s, err := d.readString(); if err != nil { return err }
			m.Name = s
		default:
			if err := d.skipField(wt); err != nil { return err }
		}
	}
	return nil
}

type mumblePermissionQueryMsg struct {
	ChannelID   uint32
	Permissions uint32
	Flush       bool
}

func (m *mumblePermissionQueryMsg) marshal() []byte {
	var e pbEncoder
	e.writeUint32Always(1, m.ChannelID)
	e.writeUint32(2, m.Permissions)
	e.writeBool(3, m.Flush)
	return e.bytes()
}

func (m *mumblePermissionQueryMsg) unmarshal(data []byte) error {
	d := newPBDecoder(data)
	for d.remaining() > 0 {
		field, wt, err := d.readTag()
		if err != nil { return err }
		switch field {
		case 1:
			v, err := d.readVarint(); if err != nil { return err }
			m.ChannelID = uint32(v)
		case 2:
			v, err := d.readVarint(); if err != nil { return err }
			m.Permissions = uint32(v)
		case 3:
			v, err := d.readVarint(); if err != nil { return err }
			m.Flush = v != 0
		default:
			if err := d.skipField(wt); err != nil { return err }
		}
	}
	return nil
}

// ACL message
type MumbleACLMsg struct {
	ChannelID  uint32
	InheritACLs bool
	Groups     []MumbleACLGroup
	ACLs       []MumbleACLEntry
	Query      bool
}

type MumbleACLGroup struct {
	Name             string
	Inherited        bool
	Inherit          bool
	Inheritable      bool
	Add              []uint32
	Remove           []uint32
	InheritedMembers []uint32
}

type MumbleACLEntry struct {
	ApplyHere bool
	ApplySubs bool
	Inherited bool
	UserID    uint32
	Group     string
	Grant     uint32
	Deny      uint32
	HasUserID bool
}

func (m *MumbleACLMsg) marshal() []byte {
	var e pbEncoder
	e.writeUint32Always(1, m.ChannelID)
	if m.InheritACLs {
		e.writeBoolAlways(2, m.InheritACLs)
	}
	for _, g := range m.Groups {
		var sub pbEncoder
		sub.writeString(1, g.Name)
		sub.writeBoolAlways(2, g.Inherited)
		sub.writeBoolAlways(3, g.Inherit)
		sub.writeBoolAlways(4, g.Inheritable)
		sub.writeRepeatedUint32(5, g.Add)
		sub.writeRepeatedUint32(6, g.Remove)
		sub.writeRepeatedUint32(7, g.InheritedMembers)
		e.writeSubmessage(3, &sub)
	}
	for _, a := range m.ACLs {
		var sub pbEncoder
		sub.writeBoolAlways(1, a.ApplyHere)
		sub.writeBoolAlways(2, a.ApplySubs)
		sub.writeBoolAlways(3, a.Inherited)
		if a.HasUserID {
			sub.writeUint32Always(4, a.UserID)
		}
		sub.writeString(5, a.Group)
		sub.writeUint32(6, a.Grant)
		sub.writeUint32(7, a.Deny)
		e.writeSubmessage(4, &sub)
	}
	e.writeBool(5, m.Query)
	return e.bytes()
}

func (m *MumbleACLMsg) unmarshal(data []byte) error {
	d := newPBDecoder(data)
	for d.remaining() > 0 {
		field, wt, err := d.readTag()
		if err != nil { return err }
		switch field {
		case 1:
			v, err := d.readVarint(); if err != nil { return err }
			m.ChannelID = uint32(v)
		case 2:
			v, err := d.readVarint(); if err != nil { return err }
			m.InheritACLs = v != 0
		case 3:
			b, err := d.readBytes(); if err != nil { return err }
			var g MumbleACLGroup
			g.Inherited = true; g.Inherit = true; g.Inheritable = true // defaults
			sd := newPBDecoder(b)
			for sd.remaining() > 0 {
				sf, swt, serr := sd.readTag()
				if serr != nil { return serr }
				switch sf {
				case 1:
					s, e := sd.readString(); if e != nil { return e }
					g.Name = s
				case 2:
					v, e := sd.readVarint(); if e != nil { return e }
					g.Inherited = v != 0
				case 3:
					v, e := sd.readVarint(); if e != nil { return e }
					g.Inherit = v != 0
				case 4:
					v, e := sd.readVarint(); if e != nil { return e }
					g.Inheritable = v != 0
				case 5:
					v, e := sd.readVarint(); if e != nil { return e }
					g.Add = append(g.Add, uint32(v))
				case 6:
					v, e := sd.readVarint(); if e != nil { return e }
					g.Remove = append(g.Remove, uint32(v))
				case 7:
					v, e := sd.readVarint(); if e != nil { return e }
					g.InheritedMembers = append(g.InheritedMembers, uint32(v))
				default:
					if e := sd.skipField(swt); e != nil { return e }
				}
			}
			m.Groups = append(m.Groups, g)
		case 4:
			b, err := d.readBytes(); if err != nil { return err }
			var a MumbleACLEntry
			a.ApplyHere = true; a.ApplySubs = true; a.Inherited = true // defaults
			sd := newPBDecoder(b)
			for sd.remaining() > 0 {
				sf, swt, serr := sd.readTag()
				if serr != nil { return serr }
				switch sf {
				case 1:
					v, e := sd.readVarint(); if e != nil { return e }
					a.ApplyHere = v != 0
				case 2:
					v, e := sd.readVarint(); if e != nil { return e }
					a.ApplySubs = v != 0
				case 3:
					v, e := sd.readVarint(); if e != nil { return e }
					a.Inherited = v != 0
				case 4:
					v, e := sd.readVarint(); if e != nil { return e }
					a.UserID = uint32(v); a.HasUserID = true
				case 5:
					s, e := sd.readString(); if e != nil { return e }
					a.Group = s
				case 6:
					v, e := sd.readVarint(); if e != nil { return e }
					a.Grant = uint32(v)
				case 7:
					v, e := sd.readVarint(); if e != nil { return e }
					a.Deny = uint32(v)
				default:
					if e := sd.skipField(swt); e != nil { return e }
				}
			}
			m.ACLs = append(m.ACLs, a)
		case 5:
			v, err := d.readVarint(); if err != nil { return err }
			m.Query = v != 0
		default:
			if err := d.skipField(wt); err != nil { return err }
		}
	}
	return nil
}

type mumbleQueryUsersMsg struct {
	IDs   []uint32
	Names []string
}

func (m *mumbleQueryUsersMsg) marshal() []byte {
	var e pbEncoder
	e.writeRepeatedUint32(1, m.IDs)
	e.writeRepeatedString(2, m.Names)
	return e.bytes()
}

func (m *mumbleQueryUsersMsg) unmarshal(data []byte) error {
	d := newPBDecoder(data)
	for d.remaining() > 0 {
		field, wt, err := d.readTag()
		if err != nil { return err }
		switch field {
		case 1:
			v, err := d.readVarint(); if err != nil { return err }
			m.IDs = append(m.IDs, uint32(v))
		case 2:
			s, err := d.readString(); if err != nil { return err }
			m.Names = append(m.Names, s)
		default:
			if err := d.skipField(wt); err != nil { return err }
		}
	}
	return nil
}

// BanList message
type mumbleBanListMsg struct {
	Bans  []MumbleBanEntry
	Query bool
}

type MumbleBanEntry struct {
	Address  []byte
	Mask     uint32
	Name     string
	Hash     string
	Reason   string
	Start    string
	Duration uint32
}

func (m *mumbleBanListMsg) marshal() []byte {
	var e pbEncoder
	for _, b := range m.Bans {
		var sub pbEncoder
		sub.writeBytes(1, b.Address)
		sub.writeUint32Always(2, b.Mask)
		sub.writeString(3, b.Name)
		sub.writeString(4, b.Hash)
		sub.writeString(5, b.Reason)
		sub.writeString(6, b.Start)
		sub.writeUint32(7, b.Duration)
		e.writeSubmessage(1, &sub)
	}
	e.writeBool(2, m.Query)
	return e.bytes()
}

func (m *mumbleBanListMsg) unmarshal(data []byte) error {
	d := newPBDecoder(data)
	for d.remaining() > 0 {
		field, wt, err := d.readTag()
		if err != nil { return err }
		switch field {
		case 1:
			b, err := d.readBytes(); if err != nil { return err }
			var ban MumbleBanEntry
			sd := newPBDecoder(b)
			for sd.remaining() > 0 {
				sf, swt, serr := sd.readTag()
				if serr != nil { return serr }
				switch sf {
				case 1:
					v, e := sd.readBytes(); if e != nil { return e }
					ban.Address = v
				case 2:
					v, e := sd.readVarint(); if e != nil { return e }
					ban.Mask = uint32(v)
				case 3:
					s, e := sd.readString(); if e != nil { return e }
					ban.Name = s
				case 4:
					s, e := sd.readString(); if e != nil { return e }
					ban.Hash = s
				case 5:
					s, e := sd.readString(); if e != nil { return e }
					ban.Reason = s
				case 6:
					s, e := sd.readString(); if e != nil { return e }
					ban.Start = s
				case 7:
					v, e := sd.readVarint(); if e != nil { return e }
					ban.Duration = uint32(v)
				default:
					if e := sd.skipField(swt); e != nil { return e }
				}
			}
			m.Bans = append(m.Bans, ban)
		case 2:
			v, err := d.readVarint(); if err != nil { return err }
			m.Query = v != 0
		default:
			if err := d.skipField(wt); err != nil { return err }
		}
	}
	return nil
}

// UserList message
type mumbleUserListMsg struct {
	Users []mumbleUserListEntry
}

type mumbleUserListEntry struct {
	UserID      uint32
	Name        string
	LastSeen    string
	LastChannel uint32
}

func (m *mumbleUserListMsg) marshal() []byte {
	var e pbEncoder
	for _, u := range m.Users {
		var sub pbEncoder
		sub.writeUint32Always(1, u.UserID)
		sub.writeString(2, u.Name)
		sub.writeString(3, u.LastSeen)
		sub.writeUint32(4, u.LastChannel)
		e.writeSubmessage(1, &sub)
	}
	return e.bytes()
}

func (m *mumbleUserListMsg) unmarshal(data []byte) error {
	d := newPBDecoder(data)
	for d.remaining() > 0 {
		field, wt, err := d.readTag()
		if err != nil { return err }
		switch field {
		case 1:
			b, err := d.readBytes(); if err != nil { return err }
			var u mumbleUserListEntry
			sd := newPBDecoder(b)
			for sd.remaining() > 0 {
				sf, swt, serr := sd.readTag()
				if serr != nil { return serr }
				switch sf {
				case 1:
					v, e := sd.readVarint(); if e != nil { return e }
					u.UserID = uint32(v)
				case 2:
					s, e := sd.readString(); if e != nil { return e }
					u.Name = s
				case 3:
					s, e := sd.readString(); if e != nil { return e }
					u.LastSeen = s
				case 4:
					v, e := sd.readVarint(); if e != nil { return e }
					u.LastChannel = uint32(v)
				default:
					if e := sd.skipField(swt); e != nil { return e }
				}
			}
			m.Users = append(m.Users, u)
		default:
			if err := d.skipField(wt); err != nil { return err }
		}
	}
	return nil
}

// VoiceTarget message
type mumbleVoiceTargetMsg struct {
	ID      uint32
	Targets []MumbleVoiceTargetEntry
}

type MumbleVoiceTargetEntry struct {
	Sessions  []uint32
	ChannelID uint32
	Group     string
	Links     bool
	Children  bool
	HasChannel bool
}

func (m *mumbleVoiceTargetMsg) marshal() []byte {
	var e pbEncoder
	e.writeUint32(1, m.ID)
	for _, t := range m.Targets {
		var sub pbEncoder
		sub.writeRepeatedUint32(1, t.Sessions)
		if t.HasChannel {
			sub.writeUint32Always(2, t.ChannelID)
		}
		sub.writeString(3, t.Group)
		sub.writeBool(4, t.Links)
		sub.writeBool(5, t.Children)
		e.writeSubmessage(2, &sub)
	}
	return e.bytes()
}

// UserStats message
type mumbleUserStatsMsg struct {
	Session           uint32
	StatsOnly         bool
	Certificates      [][]byte
	FromClient        *mumblePacketStats
	FromServer        *mumblePacketStats
	UDPPackets        uint32
	TCPPackets        uint32
	UDPPingAvg        float32
	UDPPingVar        float32
	TCPPingAvg        float32
	TCPPingVar        float32
	Version           *mumbleVersion
	CELTVersions      []int32
	Address           []byte
	Bandwidth         uint32
	OnlineSecs        uint32
	IdleSecs          uint32
	StrongCertificate bool
	Opus              bool
}

type mumblePacketStats struct {
	Good   uint32
	Late   uint32
	Lost   uint32
	Resync uint32
}

func (m *mumbleUserStatsMsg) marshal() []byte {
	var e pbEncoder
	e.writeUint32Always(1, m.Session)
	e.writeBool(2, m.StatsOnly)
	return e.bytes()
}

func (m *mumbleUserStatsMsg) unmarshal(data []byte) error {
	d := newPBDecoder(data)
	for d.remaining() > 0 {
		field, wt, err := d.readTag()
		if err != nil { return err }
		switch field {
		case 1:
			v, err := d.readVarint(); if err != nil { return err }
			m.Session = uint32(v)
		case 2:
			v, err := d.readVarint(); if err != nil { return err }
			m.StatsOnly = v != 0
		case 3:
			b, err := d.readBytes(); if err != nil { return err }
			m.Certificates = append(m.Certificates, b)
		case 4:
			b, err := d.readBytes(); if err != nil { return err }
			m.FromClient = &mumblePacketStats{}
			sd := newPBDecoder(b)
			for sd.remaining() > 0 {
				sf, swt, serr := sd.readTag()
				if serr != nil { return serr }
				switch sf {
				case 1: v, e := sd.readVarint(); if e != nil { return e }; m.FromClient.Good = uint32(v)
				case 2: v, e := sd.readVarint(); if e != nil { return e }; m.FromClient.Late = uint32(v)
				case 3: v, e := sd.readVarint(); if e != nil { return e }; m.FromClient.Lost = uint32(v)
				case 4: v, e := sd.readVarint(); if e != nil { return e }; m.FromClient.Resync = uint32(v)
				default: if e := sd.skipField(swt); e != nil { return e }
				}
			}
		case 5:
			b, err := d.readBytes(); if err != nil { return err }
			m.FromServer = &mumblePacketStats{}
			sd := newPBDecoder(b)
			for sd.remaining() > 0 {
				sf, swt, serr := sd.readTag()
				if serr != nil { return serr }
				switch sf {
				case 1: v, e := sd.readVarint(); if e != nil { return e }; m.FromServer.Good = uint32(v)
				case 2: v, e := sd.readVarint(); if e != nil { return e }; m.FromServer.Late = uint32(v)
				case 3: v, e := sd.readVarint(); if e != nil { return e }; m.FromServer.Lost = uint32(v)
				case 4: v, e := sd.readVarint(); if e != nil { return e }; m.FromServer.Resync = uint32(v)
				default: if e := sd.skipField(swt); e != nil { return e }
				}
			}
		case 6:
			v, err := d.readVarint(); if err != nil { return err }
			m.UDPPackets = uint32(v)
		case 7:
			v, err := d.readVarint(); if err != nil { return err }
			m.TCPPackets = uint32(v)
		case 8:
			v, err := d.readFixed32(); if err != nil { return err }
			m.UDPPingAvg = math.Float32frombits(v)
		case 9:
			v, err := d.readFixed32(); if err != nil { return err }
			m.UDPPingVar = math.Float32frombits(v)
		case 10:
			v, err := d.readFixed32(); if err != nil { return err }
			m.TCPPingAvg = math.Float32frombits(v)
		case 11:
			v, err := d.readFixed32(); if err != nil { return err }
			m.TCPPingVar = math.Float32frombits(v)
		case 12:
			b, err := d.readBytes(); if err != nil { return err }
			m.Version = &mumbleVersion{}
			if err := m.Version.unmarshal(b); err != nil { return err }
		case 13:
			v, err := d.readVarint(); if err != nil { return err }
			m.CELTVersions = append(m.CELTVersions, int32(v))
		case 14:
			b, err := d.readBytes(); if err != nil { return err }
			m.Address = b
		case 15:
			v, err := d.readVarint(); if err != nil { return err }
			m.Bandwidth = uint32(v)
		case 16:
			v, err := d.readVarint(); if err != nil { return err }
			m.OnlineSecs = uint32(v)
		case 17:
			v, err := d.readVarint(); if err != nil { return err }
			m.IdleSecs = uint32(v)
		case 18:
			v, err := d.readVarint(); if err != nil { return err }
			m.StrongCertificate = v != 0
		case 19:
			v, err := d.readVarint(); if err != nil { return err }
			m.Opus = v != 0
		default:
			if err := d.skipField(wt); err != nil { return err }
		}
	}
	return nil
}

type mumbleRequestBlobMsg struct {
	SessionTexture     []uint32
	SessionComment     []uint32
	ChannelDescription []uint32
}

func (m *mumbleRequestBlobMsg) marshal() []byte {
	var e pbEncoder
	e.writeRepeatedUint32(1, m.SessionTexture)
	e.writeRepeatedUint32(2, m.SessionComment)
	e.writeRepeatedUint32(3, m.ChannelDescription)
	return e.bytes()
}

type mumbleContextActionModifyMsg struct {
	Action    string
	Text      string
	Context   uint32
	Operation uint32
}

func (m *mumbleContextActionModifyMsg) unmarshal(data []byte) error {
	d := newPBDecoder(data)
	for d.remaining() > 0 {
		field, wt, err := d.readTag()
		if err != nil { return err }
		switch field {
		case 1:
			s, err := d.readString(); if err != nil { return err }
			m.Action = s
		case 2:
			s, err := d.readString(); if err != nil { return err }
			m.Text = s
		case 3:
			v, err := d.readVarint(); if err != nil { return err }
			m.Context = uint32(v)
		case 4:
			v, err := d.readVarint(); if err != nil { return err }
			m.Operation = uint32(v)
		default:
			if err := d.skipField(wt); err != nil { return err }
		}
	}
	return nil
}

type mumbleContextActionMsg struct {
	Session   uint32
	ChannelID uint32
	Action    string
}

func (m *mumbleContextActionMsg) marshal() []byte {
	var e pbEncoder
	e.writeUint32(1, m.Session)
	e.writeUint32(2, m.ChannelID)
	e.writeString(3, m.Action)
	return e.bytes()
}

type mumblePluginDataMsg struct {
	SenderSession    uint32
	ReceiverSessions []uint32
	Data             []byte
	DataID           string
}

func (m *mumblePluginDataMsg) marshal() []byte {
	var e pbEncoder
	e.writeUint32(1, m.SenderSession)
	e.writePackedUint32(2, m.ReceiverSessions)
	e.writeBytes(3, m.Data)
	e.writeString(4, m.DataID)
	return e.bytes()
}

func (m *mumblePluginDataMsg) unmarshal(data []byte) error {
	d := newPBDecoder(data)
	for d.remaining() > 0 {
		field, wt, err := d.readTag()
		if err != nil { return err }
		switch field {
		case 1:
			v, err := d.readVarint(); if err != nil { return err }
			m.SenderSession = uint32(v)
		case 2:
			if wt == 2 { // packed
				b, err := d.readBytes(); if err != nil { return err }
				sd := newPBDecoder(b)
				for sd.remaining() > 0 {
					v, err := sd.readVarint(); if err != nil { return err }
					m.ReceiverSessions = append(m.ReceiverSessions, uint32(v))
				}
			} else {
				v, err := d.readVarint(); if err != nil { return err }
				m.ReceiverSessions = append(m.ReceiverSessions, uint32(v))
			}
		case 3:
			b, err := d.readBytes(); if err != nil { return err }
			m.Data = b
		case 4:
			s, err := d.readString(); if err != nil { return err }
			m.DataID = s
		default:
			if err := d.skipField(wt); err != nil { return err }
		}
	}
	return nil
}

// ════════════════════════════════════════════════════════════════════════════════
// Internal data types
// ════════════════════════════════════════════════════════════════════════════════

type mumbleChannel struct {
	ID                uint32
	ParentID          uint32
	Name              string
	Description       string
	DescriptionHash   []byte
	Links             map[uint32]bool
	Temporary         bool
	Position          int32
	MaxUsers          uint32
	IsEnterRestricted bool
	CanEnter          bool
}

type mumbleUser struct {
	Session         uint32
	UserID          uint32
	Name            string
	ChannelID       uint32
	Mute            bool
	Deaf            bool
	Suppress        bool
	SelfMute        bool
	SelfDeaf        bool
	Comment         string
	CommentHash     []byte
	Hash            string // certificate hash
	Texture         []byte
	TextureHash     []byte
	PrioritySpeaker bool
	Recording       bool
}

type mumbleTextEntry struct {
	ID        string
	Sender    uint32
	SenderName string
	ChannelID uint32 // 0 for private messages
	IsPrivate bool
	Message   string
	Timestamp time.Time
}

type mumbleContextActionEntry struct {
	Action  string
	Text    string
	Context uint32 // bitmask: Server=1, Channel=2, User=4
}

// VoicePacket for the OnVoice callback
type MumbleVoicePacket struct {
	SenderSession uint32
	Codec         int // mumbleUDPOpus etc
	AudioData     []byte
	SequenceNum   int64
	Target        int // 0=normal, 1-30=whisper, 31=loopback
	IsTerminator  bool
	PositionX     float32
	PositionY     float32
	PositionZ     float32
}

// MumbleRejectEvent is fired when the server rejects the connection.
type MumbleRejectEvent struct {
	Type   uint32
	Reason string
}

// MumblePermissionDeniedEvent is fired when a permission is denied.
type MumblePermissionDeniedEvent struct {
	Permission uint32
	ChannelID  uint32
	Session    uint32
	Reason     string
	Type       uint32
	Name       string
}

// MumbleSuggestConfigEvent is fired when the server suggests configuration.
type MumbleSuggestConfigEvent struct {
	VersionV1  uint32
	VersionV2  uint64
	Positional bool
	PushToTalk bool
}

// MumbleContextActionEvent is fired when a context action is added/removed.
type MumbleContextActionEvent struct {
	Action    string
	Text      string
	Context   uint32 // bitmask: Server=1, Channel=2, User=4
	Operation uint32 // 0=Add, 1=Remove
}

// MumbleCodecVersionEvent is fired when the server negotiates codec versions.
type MumbleCodecVersionEvent struct {
	Alpha       int32
	Beta        int32
	PreferAlpha bool
	Opus        bool
}

// Session data for persistence
type mumbleSessionData struct {
	CertPEM string `json:"cert_pem"`
	KeyPEM  string `json:"key_pem"`
}

// ════════════════════════════════════════════════════════════════════════════════
// MumbleCore — main struct
// ════════════════════════════════════════════════════════════════════════════════

type MumbleCore struct {
	mu sync.RWMutex

	// connection
	tlsConn    *tls.Conn
	udpConn    net.Conn
	serverAddr string
	authed     bool
	isBot      bool

	// identity
	mySession   uint32
	myChannelID uint32
	certHash    string
	tlsCert     tls.Certificate
	Session *utils.SessionStore

	// server info
	serverVersion   mumbleVersion
	serverConfig    MumbleServerConfig
	maxBandwidth    uint32
	welcomeText     string
	rootPermissions uint64
	codecVersion    mumbleCodecVersionMsg
	useOpus         bool

	// crypto
	crypt mumbleCryptState
	cryptReady bool
	udpReady   bool

	// caches
	channels      map[uint32]*mumbleChannel
	users         map[uint32]*mumbleUser
	permissions   map[uint32]uint32 // channelID → permission bits
	contextActions map[string]mumbleContextActionEntry
	localMutes    map[uint32]bool
	banList       []MumbleBanEntry

	// text message buffer
	messages   []mumbleTextEntry
	msgCounter atomic.Int64

	// voice
	voiceHandler  func(MumbleVoicePacket)
	voiceSeqNum   atomic.Int64
	udpPktsSent   atomic.Uint32
	udpPktsRecv   atomic.Uint32
	tcpPktsSent      atomic.Uint32
	tcpPktsRecv      atomic.Uint32
	voiceTunnelRecv  atomic.Uint32

	// update handler
	updateHandlers []func(Update)

	// protocol event handlers
	rejectHandler        func(MumbleRejectEvent)
	permDeniedHandler    func(MumblePermissionDeniedEvent)
	suggestConfigHandler func(MumbleSuggestConfigEvent)
	contextActionHandler func(MumbleContextActionEvent)
	codecVersionHandler  func(MumbleCodecVersionEvent)

	// ping stats
	tcpPingAvg float32
	tcpPingVar float32
	udpPingAvg float32
	udpPingVar float32
	lastPingTS time.Time
	pingCount  int

	// lifecycle
	ctx    context.Context
	cancel context.CancelFunc
	wg     sync.WaitGroup

	// sync
	syncDone chan struct{} // closed when ServerSync received

	// Ice RPC admin connection (out-of-band, for server administration)
	ice               *mumbleIceClient
	iceContextHandler func(action string, session uint32, channelID int32)

	// Ice callbacks (Step 4)
	metaCallbackHandler      func(serverID int, started bool)
	iceCBUserConnected       func(state map[string]string)
	iceCBUserDisconnected    func(state map[string]string)
	iceCBUserStateChanged    func(state map[string]string)
	iceCBUserTextMessage     func(state map[string]string)
	iceCBChannelCreated      func(state map[string]string)
	iceCBChannelRemoved      func(state map[string]string)
	iceCBChannelStateChanged func(state map[string]string)
	iceCBMetaStarted         func(serverID int)
	iceCBMetaStopped         func(serverID int)

	// Custom authenticator (Step 4)
	authenticator *MumbleAuthenticator

	// UserStats callback (Step 4)
	userStatsHandler func(session uint32, stats map[string]interface{})

	// Auto-reconnect (Step 4)
	autoReconnect  bool
	reconnectDelay time.Duration

	// Audio config (Step 4)
	audioBitrate     int
	audioFrameSize   int
	audioStreamHandler func(session uint32, pcm []int16, codec string)
}

// ════════════════════════════════════════════════════════════════════════════════
// Certificate management
// ════════════════════════════════════════════════════════════════════════════════

func mumbleGenerateCert() (tls.Certificate, error) {
	priv, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return tls.Certificate{}, err
	}

	serial, _ := rand.Int(rand.Reader, new(big.Int).Lsh(big.NewInt(1), 128))
	template := &x509.Certificate{
		SerialNumber: serial,
		Subject:      pkix.Name{CommonName: "Uniclient Mumble"},
		NotBefore:    time.Now().Add(-24 * time.Hour),
		NotAfter:     time.Now().Add(10 * 365 * 24 * time.Hour),
		KeyUsage:     x509.KeyUsageDigitalSignature | x509.KeyUsageKeyEncipherment,
	}

	certDER, err := x509.CreateCertificate(rand.Reader, template, template, &priv.PublicKey, priv)
	if err != nil {
		return tls.Certificate{}, err
	}

	certPEM := pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: certDER})
	keyDER, err := x509.MarshalECPrivateKey(priv)
	if err != nil {
		return tls.Certificate{}, err
	}
	keyPEM := pem.EncodeToMemory(&pem.Block{Type: "EC PRIVATE KEY", Bytes: keyDER})

	return tls.X509KeyPair(certPEM, keyPEM)
}

func mumbleCertHash(cert tls.Certificate) string {
	if len(cert.Certificate) == 0 {
		return ""
	}
	h := sha1.Sum(cert.Certificate[0])
	return hex.EncodeToString(h[:])
}

func (c *MumbleCore) loadSession() error {
	if c.Session == nil {
		return fmt.Errorf("no session store")
	}
	var sess mumbleSessionData
	if err := c.Session.Load(&sess); err != nil {
		return err
	}
	if sess.CertPEM == "" || sess.KeyPEM == "" {
		return fmt.Errorf("no session file")
	}
	cert, err := tls.X509KeyPair([]byte(sess.CertPEM), []byte(sess.KeyPEM))
	if err != nil {
		return err
	}
	c.tlsCert = cert
	c.certHash = mumbleCertHash(cert)
	return nil
}

func (c *MumbleCore) saveSession() error {
	if len(c.tlsCert.Certificate) == 0 {
		return nil
	}
	certPEM := pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: c.tlsCert.Certificate[0]})
	ecKey, ok := c.tlsCert.PrivateKey.(*ecdsa.PrivateKey)
	if !ok {
		return fmt.Errorf("unexpected private key type: %T", c.tlsCert.PrivateKey)
	}
	keyBytes, err := x509.MarshalECPrivateKey(ecKey)
	if err != nil {
		return err
	}
	keyPEM := pem.EncodeToMemory(&pem.Block{Type: "EC PRIVATE KEY", Bytes: keyBytes})
	sess := mumbleSessionData{
		CertPEM: string(certPEM),
		KeyPEM:  string(keyPEM),
	}
	if c.Session == nil {
		return nil
	}
	return c.Session.Save(sess)
}

// ════════════════════════════════════════════════════════════════════════════════
// TCP Transport
// ════════════════════════════════════════════════════════════════════════════════

func (c *MumbleCore) tcpSend(msgType uint16, payload []byte) error {
	c.mu.Lock()
	conn := c.tlsConn
	c.mu.Unlock()
	if conn == nil {
		return ErrNetwork
	}

	msg := make([]byte, 6+len(payload))
	binary.BigEndian.PutUint16(msg[:2], msgType)
	binary.BigEndian.PutUint32(msg[2:6], uint32(len(payload)))
	copy(msg[6:], payload)
	_, err := conn.Write(msg)
	if err == nil {
		c.tcpPktsSent.Add(1)
	}
	return err
}

func (c *MumbleCore) tcpRecv() (uint16, []byte, error) {
	conn := c.tlsConn
	if conn == nil {
		return 0, nil, ErrNetwork
	}

	var header [6]byte
	if _, err := io.ReadFull(conn, header[:]); err != nil {
		return 0, nil, err
	}

	msgType := binary.BigEndian.Uint16(header[:2])
	msgLen := binary.BigEndian.Uint32(header[2:6])

	if msgLen > 8*1024*1024 {
		return 0, nil, fmt.Errorf("mumble: message too large: %d bytes", msgLen)
	}

	payload := make([]byte, msgLen)
	if _, err := io.ReadFull(conn, payload); err != nil {
		return 0, nil, err
	}
	c.tcpPktsRecv.Add(1)
	return msgType, payload, nil
}

// ════════════════════════════════════════════════════════════════════════════════
// UDP Transport
// ════════════════════════════════════════════════════════════════════════════════

func (c *MumbleCore) udpSend(data []byte) error {
	if !c.cryptReady {
		// Fall back to TCP tunnel
		return c.tcpSend(mumbleMsgUDPTunnel, data)
	}

	c.mu.RLock()
	conn := c.udpConn
	ready := c.udpReady
	c.mu.RUnlock()

	if conn == nil || !ready {
		// UDP not confirmed working (NAT/firewall) — fall back to TCP tunnel
		return c.tcpSend(mumbleMsgUDPTunnel, data)
	}

	encrypted := make([]byte, mumbleCryptoOverhead+len(data))
	c.crypt.encrypt(encrypted, data)

	_, err := conn.Write(encrypted)
	if err == nil {
		c.udpPktsSent.Add(1)
	}
	return err
}

func (c *MumbleCore) udpRecvLoop() {
	defer c.wg.Done()

	buf := make([]byte, mumbleMaxUDPSize)
	plain := make([]byte, mumbleMaxUDPSize)
	for {
		select {
		case <-c.ctx.Done():
			return
		default:
		}

		c.mu.RLock()
		conn := c.udpConn
		c.mu.RUnlock()
		if conn == nil {
			return
		}

		conn.SetReadDeadline(time.Now().Add(mumbleReadTimeout))
		n, err := conn.Read(buf)
		if err != nil {
			if ne, ok := err.(net.Error); ok && ne.Timeout() {
				continue
			}
			select {
			case <-c.ctx.Done():
				return
			default:
				continue
			}
		}

		if n < mumbleCryptoOverhead {
			continue
		}

		pLen, err := c.crypt.decrypt(plain, buf[:n])
		if err != nil {
			continue
		}

		c.udpPktsRecv.Add(1)
		c.handleUDPPacket(plain[:pLen])
	}
}

func (c *MumbleCore) handleUDPPacket(data []byte) {
	if len(data) < 2 {
		return
	}

	// Mumble 1.5+ protobuf format: first byte is UDPMessageType
	// 0 = Audio, 1 = Ping
	// Legacy format: first byte has type in bits[7:5] (range 0x00-0x9F)
	//
	// We declared version 1.5.517, so the server sends protobuf format.
	// TCP UDPTunnel also uses the same format.
	msgType := data[0]
	switch msgType {
	case 0: // Audio
		c.handleProtobufUDPPacket(data[1:])
	case 1: // Ping
		c.handleProtobufUDPPing(data[1:])
	default:
		// Might be legacy format (from old servers or TCP tunnel)
		audioType := int(msgType >> 5)
		if audioType >= 0 && audioType <= 4 {
			c.handleLegacyUDPPacket(data)
		}
		// else unknown, silently drop
	}
}

func (c *MumbleCore) handleProtobufUDPPing(data []byte) {
	// Parse MumbleUDP.Ping protobuf
	d := newPBDecoder(data)
	for d.remaining() > 0 {
		field, wt, err := d.readTag()
		if err != nil {
			return
		}
		switch field {
		case 1: // timestamp
			_, err := d.readVarint()
			if err != nil {
				return
			}
		default:
			d.skipField(wt)
		}
	}
	if !c.udpReady {
		c.mu.Lock()
		c.udpReady = true
		c.mu.Unlock()
	}
}

func (c *MumbleCore) handleLegacyUDPPacket(data []byte) {
	if len(data) < 1 {
		return
	}

	header := data[0]
	audioType := int(header >> 5)
	target := int(header & 0x1F)

	if audioType == mumbleUDPPing {
		// UDP Ping response
		if len(data) > 1 {
			ts, _, _ := mumbleVarintDecode(data, 1)
			_ = ts // Could track for ping stats
		}
		if !c.udpReady {
			c.mu.Lock()
			c.udpReady = true
			c.mu.Unlock()
		}
		return
	}

	// Audio packet — from server has session ID
	pos := 1
	session, newPos, err := mumbleVarintDecode(data, pos)
	if err != nil {
		return
	}
	pos = newPos

	seq, newPos, err := mumbleVarintDecode(data, pos)
	if err != nil {
		return
	}
	pos = newPos

	pkt := MumbleVoicePacket{
		SenderSession: uint32(session),
		Codec:         audioType,
		SequenceNum:   seq,
		Target:        target,
	}

	if audioType == mumbleUDPOpus {
		if pos >= len(data) {
			return
		}
		opusHeader, newPos, err := mumbleVarintDecode(data, pos)
		if err != nil {
			return
		}
		pos = newPos
		opusLen := int(opusHeader & 0x1FFF)
		pkt.IsTerminator = (opusHeader & 0x2000) != 0
		if pos+opusLen > len(data) {
			opusLen = len(data) - pos
		}
		if opusLen > 0 {
			pkt.AudioData = append([]byte(nil), data[pos:pos+opusLen]...)
			pos += opusLen
		}
	} else {
		// CELT/Speex: multiple frames with continuation bit
		var audioData []byte
		for pos < len(data) {
			if pos >= len(data) {
				break
			}
			frameHeader := data[pos]
			pos++
			frameLen := int(frameHeader & 0x7F)
			if pos+frameLen > len(data) {
				break
			}
			audioData = append(audioData, data[pos:pos+frameLen]...)
			pos += frameLen
			if frameHeader&0x80 == 0 {
				break // last frame
			}
		}
		pkt.AudioData = audioData
		if len(audioData) == 0 {
			pkt.IsTerminator = true
		}
	}

	// Optional positional data (3x float32 LE)
	if pos+12 <= len(data) {
		pkt.PositionX = math.Float32frombits(binary.LittleEndian.Uint32(data[pos:]))
		pkt.PositionY = math.Float32frombits(binary.LittleEndian.Uint32(data[pos+4:]))
		pkt.PositionZ = math.Float32frombits(binary.LittleEndian.Uint32(data[pos+8:]))
	}

	if c.voiceHandler != nil {
		c.voiceHandler(pkt)
	}
}

func (c *MumbleCore) handleProtobufUDPPacket(data []byte) {
	// Protobuf UDP: decode as MumbleUDP.Audio
	d := newPBDecoder(data)
	var pkt MumbleVoicePacket
	pkt.Codec = mumbleUDPOpus // protobuf format is always Opus

	for d.remaining() > 0 {
		field, wt, err := d.readTag()
		if err != nil {
			return
		}
		switch field {
		case 1: // target (client→server)
			v, err := d.readVarint()
			if err != nil { return }
			pkt.Target = int(v)
		case 2: // context (server→client)
			v, err := d.readVarint()
			if err != nil { return }
			pkt.Target = int(v) // reuse Target field for context
		case 3: // sender_session
			v, err := d.readVarint()
			if err != nil { return }
			pkt.SenderSession = uint32(v)
		case 4: // frame_number
			v, err := d.readVarint()
			if err != nil { return }
			pkt.SequenceNum = int64(v)
		case 5: // opus_data
			b, err := d.readBytes()
			if err != nil { return }
			pkt.AudioData = b
		case 6: // positional_data (repeated float)
			if wt == 5 { // single float32
				v, err := d.readFixed32()
				if err != nil { return }
				f := math.Float32frombits(v)
				if pkt.PositionX == 0 {
					pkt.PositionX = f
				} else if pkt.PositionY == 0 {
					pkt.PositionY = f
				} else {
					pkt.PositionZ = f
				}
			} else if wt == 2 { // packed floats
				b, err := d.readBytes()
				if err != nil { return }
				if len(b) >= 4 {
					pkt.PositionX = math.Float32frombits(binary.LittleEndian.Uint32(b[0:4]))
				}
				if len(b) >= 8 {
					pkt.PositionY = math.Float32frombits(binary.LittleEndian.Uint32(b[4:8]))
				}
				if len(b) >= 12 {
					pkt.PositionZ = math.Float32frombits(binary.LittleEndian.Uint32(b[8:12]))
				}
			} else {
				d.skipField(wt)
			}
		case 7: // volume_adjustment (float)
			_, err := d.readFixed32()
			if err != nil { return }
			// We don't use volume_adjustment in the voice packet struct currently
		case 16: // is_terminator
			v, err := d.readVarint()
			if err != nil { return }
			pkt.IsTerminator = v != 0
		default:
			d.skipField(wt)
		}
	}

	if c.voiceHandler != nil {
		c.voiceHandler(pkt)
	}
}

// ════════════════════════════════════════════════════════════════════════════════
// Connection & Handshake
// ════════════════════════════════════════════════════════════════════════════════

func (c *MumbleCore) connect(addr string, username, password string, tokens []string, isBot bool) error {
	c.mu.Lock()
	c.serverAddr = addr
	c.isBot = isBot
	c.channels = make(map[uint32]*mumbleChannel)
	c.users = make(map[uint32]*mumbleUser)
	c.permissions = make(map[uint32]uint32)
	c.contextActions = make(map[string]mumbleContextActionEntry)
	c.localMutes = make(map[uint32]bool)
	c.messages = nil
	c.syncDone = make(chan struct{})
	c.ctx, c.cancel = context.WithCancel(context.Background())
	c.mu.Unlock()

	// Parse host:port
	host, port, err := net.SplitHostPort(addr)
	if err != nil {
		host = addr
		port = strconv.Itoa(mumbleDefaultPort)
	}
	hostPort := net.JoinHostPort(host, port)

	// TLS connect
	tlsCfg := &tls.Config{
		InsecureSkipVerify: true, // Mumble servers often use self-signed certs
		Certificates:       []tls.Certificate{c.tlsCert},
		NextProtos:         []string{"mumble"},
	}

	dialer := &net.Dialer{Timeout: mumbleDialTimeout}
	conn, err := tls.DialWithDialer(dialer, "tcp", hostPort, tlsCfg)
	if err != nil {
		return fmt.Errorf("mumble: TLS connect failed: %w", err)
	}

	c.mu.Lock()
	c.tlsConn = conn
	c.mu.Unlock()

	// Send Version
	ver := &mumbleVersion{
		VersionV1: mumbleVersionV1,
		VersionV2: mumbleVersionV2,
		Release:   mumbleRelease,
		OS:        mumbleOS,
		OSVersion: "",
	}
	if err := c.tcpSend(mumbleMsgVersion, ver.marshal()); err != nil {
		conn.Close()
		return err
	}

	// Send Authenticate
	clientType := int32(0)
	if isBot {
		clientType = 1
	}
	auth := &mumbleAuthenticate{
		Username:   username,
		Password:   password,
		Tokens:     tokens,
		Opus:       true,
		ClientType: clientType,
	}
	if err := c.tcpSend(mumbleMsgAuthenticate, auth.marshal()); err != nil {
		conn.Close()
		return err
	}

	// Start TCP receive loop
	c.wg.Add(1)
	go c.tcpRecvLoop()

	// Wait for ServerSync (with timeout)
	select {
	case <-c.syncDone:
		// Connected!
	case <-time.After(30 * time.Second):
		c.Close()
		return fmt.Errorf("%w: mumble: connection timed out waiting for ServerSync", ErrTimeout)
	case <-c.ctx.Done():
		return fmt.Errorf("mumble: connection cancelled")
	}

	// Setup UDP
	udpAddr := net.JoinHostPort(host, port)
	udpConn, err := net.Dial("udp", udpAddr)
	if err == nil {
		c.mu.Lock()
		c.udpConn = udpConn
		c.mu.Unlock()
		c.wg.Add(1)
		go c.udpRecvLoop()
	}
	// If UDP fails, we'll use TCP tunnel — no error

	// Start ping loop
	c.wg.Add(1)
	go c.pingLoop()

	// Send initial UDP ping to check connectivity
	c.sendUDPPing()

	c.mu.Lock()
	c.authed = true
	c.autoReconnect = true
	c.mu.Unlock()

	return nil
}

func (c *MumbleCore) tcpRecvLoop() {
	defer c.wg.Done()
	for {
		select {
		case <-c.ctx.Done():
			return
		default:
		}

		msgType, payload, err := c.tcpRecv()
		if err != nil {
			select {
			case <-c.ctx.Done():
				return
			default:
				// Connection lost — notify listeners
				c.fireUpdate(Update{Type: UpdateCallState, Platform: mumblePlatform, ChatID: "disconnected"})

				// Attempt auto-reconnect if enabled (in separate goroutine
				// because Reconnect calls Close which waits on wg)
				c.mu.RLock()
				shouldReconnect := c.autoReconnect
				c.mu.RUnlock()

				if shouldReconnect {
					go c.attemptAutoReconnect()
				}
				return
			}
		}

		c.handleTCPMessage(msgType, payload)
	}
}

// attemptAutoReconnect tries to reconnect with exponential backoff.
// Backoff: 3s, 6s, 12s, 24s, 48s, 60s (capped), up to 10 retries.
// Must be called in its own goroutine (not from tcpRecvLoop) because
// Reconnect -> Close -> wg.Wait would deadlock otherwise.
func (c *MumbleCore) attemptAutoReconnect() {
	const maxRetries = 10
	attempt := 0
	err := utils.Retry(c.ctx, maxRetries, 3*time.Second, 60*time.Second, nil, func() error {
		attempt++
		c.fireUpdate(Update{
			Type:     UpdateCallState,
			Platform: mumblePlatform,
			ChatID:   fmt.Sprintf("reconnecting:%d/%d", attempt, maxRetries),
		})
		return c.Reconnect()
	})

	if err == nil {
		c.fireUpdate(Update{
			Type:     UpdateCallState,
			Platform: mumblePlatform,
			ChatID:   "reconnected",
		})
		return
	}

	// All retries exhausted
	c.fireUpdate(Update{
		Type:     UpdateCallState,
		Platform: mumblePlatform,
		ChatID:   "reconnect_failed",
	})
}

func (c *MumbleCore) handleTCPMessage(msgType uint16, payload []byte) {
	switch msgType {
	case mumbleMsgVersion:
		var msg mumbleVersion
		if err := msg.unmarshal(payload); err == nil {
			c.mu.Lock()
			c.serverVersion = msg
			c.mu.Unlock()
		}

	case mumbleMsgUDPTunnel:
		// Voice packet tunneled over TCP
		c.voiceTunnelRecv.Add(1)
		c.handleUDPPacket(payload)

	case mumbleMsgPing:
		var msg mumblePingMsg
		if err := msg.unmarshal(payload); err == nil {
			c.mu.Lock()
			// Update server-side ping stats if present
			if msg.TCPPingAvg > 0 {
				c.tcpPingAvg = msg.TCPPingAvg
			}
			c.mu.Unlock()
		}

	case mumbleMsgReject:
		var msg mumbleReject
		msg.unmarshal(payload)
		c.mu.RLock()
		h := c.rejectHandler
		c.mu.RUnlock()
		if h != nil {
			h(MumbleRejectEvent{Type: msg.Type, Reason: msg.Reason})
		}
		select {
		case <-c.syncDone:
		default:
			close(c.syncDone)
		}

	case mumbleMsgServerSync:
		var msg mumbleServerSync
		if err := msg.unmarshal(payload); err == nil {
			c.mu.Lock()
			c.mySession = msg.Session
			c.maxBandwidth = msg.MaxBandwidth
			c.welcomeText = msg.WelcomeText
			c.rootPermissions = msg.Permissions
			c.mu.Unlock()
			select {
			case <-c.syncDone:
			default:
				close(c.syncDone)
			}
		}

	case mumbleMsgChannelState:
		var msg mumbleChannelStateMsg
		if err := msg.unmarshal(payload); err == nil {
			c.handleChannelState(&msg)
		}

	case mumbleMsgChannelRemove:
		var msg mumbleChannelRemoveMsg
		if err := msg.unmarshal(payload); err == nil {
			c.mu.Lock()
			delete(c.channels, msg.ChannelID)
			c.mu.Unlock()
		}

	case mumbleMsgUserState:
		var msg mumbleUserStateMsg
		if err := msg.unmarshal(payload); err == nil {
			c.handleUserState(&msg)
		}

	case mumbleMsgUserRemove:
		var msg mumbleUserRemoveMsg
		if err := msg.unmarshal(payload); err == nil {
			c.handleUserRemove(&msg)
		}

	case mumbleMsgTextMessage:
		var msg mumbleTextMsg
		if err := msg.unmarshal(payload); err == nil {
			c.handleTextMessage(&msg)
		}

	case mumbleMsgCryptSetup:
		var msg mumbleCryptSetupMsg
		if err := msg.unmarshal(payload); err == nil {
			if len(msg.Key) == 16 && len(msg.ClientNonce) == 16 && len(msg.ServerNonce) == 16 {
				if err := c.crypt.init(msg.Key, msg.ClientNonce, msg.ServerNonce); err == nil {
					c.mu.Lock()
					c.cryptReady = true
					c.mu.Unlock()
				}
			} else if len(msg.ServerNonce) == 16 {
				// Nonce resync — update server nonce
				c.crypt.mu.Lock()
				copy(c.crypt.decryptIV[:], msg.ServerNonce)
				c.crypt.resync++
				c.crypt.mu.Unlock()
			}
		}

	case mumbleMsgCodecVersion:
		var msg mumbleCodecVersionMsg
		if err := msg.unmarshal(payload); err == nil {
			c.mu.Lock()
			c.codecVersion = msg
			c.useOpus = msg.Opus
			h := c.codecVersionHandler
			c.mu.Unlock()
			if h != nil {
				h(MumbleCodecVersionEvent{
					Alpha: msg.Alpha, Beta: msg.Beta,
					PreferAlpha: msg.PreferAlpha, Opus: msg.Opus,
				})
			}
		}

	case mumbleMsgServerConfig:
		var msg MumbleServerConfig
		if err := msg.unmarshal(payload); err == nil {
			c.mu.Lock()
			c.serverConfig = msg
			if msg.MaxBandwidth > 0 {
				c.maxBandwidth = msg.MaxBandwidth
			}
			c.mu.Unlock()
		}

	case mumbleMsgPermissionQuery:
		var msg mumblePermissionQueryMsg
		if err := msg.unmarshal(payload); err == nil {
			c.mu.Lock()
			if msg.Flush {
				c.permissions = make(map[uint32]uint32)
			}
			c.permissions[msg.ChannelID] = msg.Permissions
			c.mu.Unlock()
		}

	case mumbleMsgPermissionDenied:
		var msg mumblePermissionDeniedMsg
		msg.unmarshal(payload)
		c.mu.RLock()
		pdh := c.permDeniedHandler
		c.mu.RUnlock()
		if pdh != nil {
			pdh(MumblePermissionDeniedEvent{
				Permission: msg.Permission, ChannelID: msg.ChannelID,
				Session: msg.Session, Reason: msg.Reason,
				Type: msg.Type, Name: msg.Name,
			})
		}

	case mumbleMsgContextActionModify:
		var msg mumbleContextActionModifyMsg
		if err := msg.unmarshal(payload); err == nil {
			c.mu.Lock()
			if msg.Operation == 0 {
				c.contextActions[msg.Action] = mumbleContextActionEntry{
					Action: msg.Action, Text: msg.Text, Context: msg.Context,
				}
			} else {
				delete(c.contextActions, msg.Action)
			}
			cah := c.contextActionHandler
			c.mu.Unlock()
			if cah != nil {
				cah(MumbleContextActionEvent{
					Action: msg.Action, Text: msg.Text,
					Context: msg.Context, Operation: msg.Operation,
				})
			}
		}

	case mumbleMsgSuggestConfig:
		var msg mumbleSuggestConfigMsg
		msg.unmarshal(payload)
		c.mu.RLock()
		sch := c.suggestConfigHandler
		c.mu.RUnlock()
		if sch != nil {
			sch(MumbleSuggestConfigEvent{
				VersionV1: msg.VersionV1, VersionV2: msg.VersionV2,
				Positional: msg.Positional, PushToTalk: msg.PushToTalk,
			})
		}

	case mumbleMsgPluginDataTransmission:
		var msg mumblePluginDataMsg
		if err := msg.unmarshal(payload); err == nil {
			_ = msg // Could expose via callback
		}

	case mumbleMsgBanList:
		var msg mumbleBanListMsg
		if err := msg.unmarshal(payload); err == nil {
			c.mu.Lock()
			c.banList = msg.Bans
			c.mu.Unlock()
		}

	case mumbleMsgUserList:
		// Handled by the caller that requested it
		// Store for GetRegisteredUsers

	case mumbleMsgUserStats:
		// Handled by the caller that requested it

	case mumbleMsgQueryUsers:
		// Response — handled inline

	case mumbleMsgACL:
		// Response — handled inline
	}
}

func (c *MumbleCore) handleChannelState(msg *mumbleChannelStateMsg) {
	c.mu.Lock()
	defer c.mu.Unlock()

	ch, exists := c.channels[msg.ChannelID]
	if !exists {
		ch = &mumbleChannel{
			ID:    msg.ChannelID,
			Links: make(map[uint32]bool),
		}
		c.channels[msg.ChannelID] = ch
	}

	if msg.HasParent {
		ch.ParentID = msg.Parent
	}
	if msg.Name != "" {
		ch.Name = msg.Name
	}
	if msg.Description != "" {
		ch.Description = msg.Description
	}
	if len(msg.DescriptionHash) > 0 {
		ch.DescriptionHash = msg.DescriptionHash
	}
	if len(msg.Links) > 0 {
		ch.Links = make(map[uint32]bool)
		for _, l := range msg.Links {
			ch.Links[l] = true
		}
	}
	for _, l := range msg.LinksAdd {
		ch.Links[l] = true
	}
	for _, l := range msg.LinksRemove {
		delete(ch.Links, l)
	}
	ch.Temporary = msg.Temporary
	ch.Position = msg.Position
	ch.MaxUsers = msg.MaxUsers
	ch.IsEnterRestricted = msg.IsEnterRestricted
	ch.CanEnter = msg.CanEnter
}

func (c *MumbleCore) handleUserState(msg *mumbleUserStateMsg) {
	c.mu.Lock()
	defer c.mu.Unlock()

	if !msg.HasSession {
		return
	}

	u, exists := c.users[msg.Session]
	if !exists {
		u = &mumbleUser{Session: msg.Session}
		c.users[msg.Session] = u
	}

	if msg.Name != "" {
		u.Name = msg.Name
	}
	if msg.HasUserID {
		u.UserID = msg.UserID
	}
	if msg.HasChannelID {
		oldChannel := u.ChannelID
		u.ChannelID = msg.ChannelID
		// Track our own channel
		if msg.Session == c.mySession {
			c.myChannelID = msg.ChannelID
		}
		if exists && oldChannel != msg.ChannelID {
			c.fireUpdateLocked(Update{
				Type:     UpdateGroupMembers,
				ChatID:   strconv.FormatUint(uint64(msg.ChannelID), 10),
				Platform: mumblePlatform,
			})
		}
	}
	if msg.HasMute {
		u.Mute = msg.Mute
	}
	if msg.HasDeaf {
		u.Deaf = msg.Deaf
	}
	if msg.HasSuppress {
		u.Suppress = msg.Suppress
	}
	if msg.HasSelfMute {
		u.SelfMute = msg.SelfMute
	}
	if msg.HasSelfDeaf {
		u.SelfDeaf = msg.SelfDeaf
	}
	if msg.Comment != "" {
		u.Comment = msg.Comment
	}
	if len(msg.CommentHash) > 0 {
		u.CommentHash = msg.CommentHash
	}
	if msg.Hash != "" {
		u.Hash = msg.Hash
	}
	if len(msg.Texture) > 0 {
		u.Texture = msg.Texture
	}
	if len(msg.TextureHash) > 0 {
		u.TextureHash = msg.TextureHash
	}
	if msg.HasPrioritySpeaker {
		u.PrioritySpeaker = msg.PrioritySpeaker
	}
	if msg.HasRecording {
		u.Recording = msg.Recording
	}

	// Fire user status update
	if exists {
		isOnline := true
		c.fireUpdateLocked(Update{
			Type:     UpdateUserStatus,
			UserID:   strconv.FormatUint(uint64(msg.Session), 10),
			IsOnline: &isOnline,
			Platform: mumblePlatform,
		})
	}
}

func (c *MumbleCore) handleUserRemove(msg *mumbleUserRemoveMsg) {
	c.mu.Lock()
	u, exists := c.users[msg.Session]
	channelID := uint32(0)
	if exists {
		channelID = u.ChannelID
	}
	delete(c.users, msg.Session)
	delete(c.localMutes, msg.Session)
	c.mu.Unlock()

	if exists {
		c.fireUpdate(Update{
			Type:     UpdateGroupMembers,
			ChatID:   strconv.FormatUint(uint64(channelID), 10),
			UserID:   strconv.FormatUint(uint64(msg.Session), 10),
			Platform: mumblePlatform,
		})
	}
}

func (c *MumbleCore) handleTextMessage(msg *mumbleTextMsg) {
	c.mu.Lock()

	senderName := ""
	if u, ok := c.users[msg.Actor]; ok {
		senderName = u.Name
	}

	isPrivate := len(msg.Session) > 0 && len(msg.ChannelID) == 0 && len(msg.TreeID) == 0
	channelID := uint32(0)
	if len(msg.ChannelID) > 0 {
		channelID = msg.ChannelID[0]
	} else if len(msg.TreeID) > 0 {
		channelID = msg.TreeID[0]
	}

	id := c.msgCounter.Add(1)
	entry := mumbleTextEntry{
		ID:         strconv.FormatInt(id, 10),
		Sender:     msg.Actor,
		SenderName: senderName,
		ChannelID:  channelID,
		IsPrivate:  isPrivate,
		Message:    msg.Message,
		Timestamp:  time.Now(),
	}

	c.messages = append(c.messages, entry)
	if len(c.messages) > mumbleMaxMsgBuffer {
		c.messages = c.messages[1:]
	}
	c.mu.Unlock()

	// Determine chat ID
	chatID := strconv.FormatUint(uint64(channelID), 10)
	if isPrivate {
		chatID = "user:" + strconv.FormatUint(uint64(msg.Actor), 10)
	}

	coreMsg := &Message{
		ID:         entry.ID,
		ChatID:     chatID,
		SenderID:   strconv.FormatUint(uint64(msg.Actor), 10),
		SenderName: senderName,
		Text:       msg.Message,
		Timestamp:  entry.Timestamp,
		Status:     MessageStatusDelivered,
		IsOutgoing: msg.Actor == c.mySession,
		Platform:   mumblePlatform,
	}

	c.fireUpdate(Update{
		Type:     UpdateNewMessage,
		ChatID:   chatID,
		Message:  coreMsg,
		Platform: mumblePlatform,
	})
}

func (c *MumbleCore) fireUpdate(u Update) {
	c.mu.RLock()
	n := len(c.updateHandlers)
	if n == 0 {
		c.mu.RUnlock()
		return
	}
	if n == 1 {
		h := c.updateHandlers[0]
		c.mu.RUnlock()
		h(u)
		return
	}
	handlers := make([]func(Update), n)
	copy(handlers, c.updateHandlers)
	c.mu.RUnlock()
	for _, h := range handlers {
		h(u)
	}
}

func (c *MumbleCore) fireUpdateLocked(u Update) {
	n := len(c.updateHandlers)
	if n == 0 {
		return
	}
	if n == 1 {
		h := c.updateHandlers[0]
		go h(u)
		return
	}
	handlers := make([]func(Update), n)
	copy(handlers, c.updateHandlers)
	go func() {
		for _, h := range handlers {
			h(u)
		}
	}()
}

// ════════════════════════════════════════════════════════════════════════════════
// Ping
// ════════════════════════════════════════════════════════════════════════════════

func (c *MumbleCore) pingLoop() {
	defer c.wg.Done()
	ticker := time.NewTicker(mumblePingInterval)
	defer ticker.Stop()

	for {
		select {
		case <-c.ctx.Done():
			return
		case <-ticker.C:
			c.sendTCPPing()
			c.sendUDPPing()
		}
	}
}

func (c *MumbleCore) sendTCPPing() {
	now := uint64(time.Now().UnixMilli())
	msg := &mumblePingMsg{
		Timestamp:  now,
		Good:       c.crypt.good,
		Late:       c.crypt.late,
		Lost:       c.crypt.lost,
		Resync:     c.crypt.resync,
		UDPPackets: c.udpPktsRecv.Load(),
		TCPPackets: c.tcpPktsRecv.Load(),
	}
	c.tcpSend(mumbleMsgPing, msg.marshal())
}

func (c *MumbleCore) sendUDPPing() {
	ts := uint64(time.Now().UnixMilli())
	e := getPBEncoder()
	e.writeUint64(1, ts)
	e.writeBool(2, true)
	pb := e.bytes()
	data := make([]byte, 1+len(pb))
	data[0] = 1
	copy(data[1:], pb)
	putPBEncoder(e)
	c.udpSend(data)
}

// ════════════════════════════════════════════════════════════════════════════════
// Voice Send
// ════════════════════════════════════════════════════════════════════════════════

// serverSupportsProtobufUDP returns true if server version >= 1.5.0 (protobuf UDP format).
func (c *MumbleCore) serverSupportsProtobufUDP() bool {
	c.mu.RLock()
	v := c.serverVersion
	c.mu.RUnlock()
	// Check v2 format first (field 5)
	if v.VersionV2 > 0 {
		major := (v.VersionV2 >> 48) & 0xFFFF
		minor := (v.VersionV2 >> 32) & 0xFFFF
		return major > 1 || (major == 1 && minor >= 5)
	}
	// Fall back to v1 format (field 1): major.minor.patch packed as (major<<16)|(minor<<8)|patch
	if v.VersionV1 > 0 {
		major := (v.VersionV1 >> 16) & 0xFF
		minor := (v.VersionV1 >> 8) & 0xFF
		return major > 1 || (major == 1 && minor >= 5)
	}
	// Unknown — assume legacy for safety
	return false
}

// buildVoiceAuto builds a voice packet in the format the server expects.
func (c *MumbleCore) buildVoiceAuto(opusData []byte, target int, seq int64, terminator bool) []byte {
	if c.serverSupportsProtobufUDP() {
		return c.buildVoicePacket(opusData, target, seq, terminator)
	}
	return c.buildLegacyVoicePacket(opusData, target, seq, terminator)
}

// SendVoice sends an Opus audio frame. target: 0=normal, 1-30=whisper, 31=loopback.
// Auto-detects server version and uses protobuf (1.5+) or legacy format.
func (c *MumbleCore) SendVoice(opusData []byte, target int) error {
	seq := c.voiceSeqNum.Add(1) - 1
	return c.udpSend(c.buildVoiceAuto(opusData, target, seq, false))
}

// SendVoiceTCP sends voice via TCP tunnel (UDPTunnel message), bypassing UDP crypto.
func (c *MumbleCore) SendVoiceTCP(opusData []byte, target int) error {
	seq := c.voiceSeqNum.Add(1) - 1
	return c.tcpSend(mumbleMsgUDPTunnel, c.buildVoiceAuto(opusData, target, seq, false))
}

func (c *MumbleCore) buildVoicePacket(opusData []byte, target int, seq int64, terminator bool) []byte {
	e := getPBEncoder()
	e.writeUint32Always(1, uint32(target))
	e.writeUint64(4, uint64(seq))
	e.writeBytes(5, opusData)
	if terminator {
		e.writeBool(16, true)
	}
	pb := e.bytes()
	out := make([]byte, 1+len(pb))
	out[0] = 0
	copy(out[1:], pb)
	putPBEncoder(e)
	return out
}

func (c *MumbleCore) buildLegacyVoicePacket(opusData []byte, target int, seq int64, terminator bool) []byte {
	var tmp [20]byte
	tmp[0] = byte(mumbleUDPOpus<<5) | byte(target&0x1F)
	n := 1
	n += mumbleVarintEncodeTo(tmp[n:], seq)
	opusHeader := int64(len(opusData) & 0x1FFF)
	if terminator {
		opusHeader |= 0x2000
	}
	n += mumbleVarintEncodeTo(tmp[n:], opusHeader)
	out := make([]byte, n+len(opusData))
	copy(out, tmp[:n])
	copy(out[n:], opusData)
	return out
}

// SendVoiceTerminator sends an end-of-transmission marker.
func (c *MumbleCore) SendVoiceTerminator() error {
	seq := c.voiceSeqNum.Add(1) - 1
	return c.udpSend(c.buildVoiceAuto(nil, 0, seq, true))
}

// OnVoice registers a callback for incoming voice packets.
func (c *MumbleCore) OnVoice(handler func(MumbleVoicePacket)) {
	c.mu.Lock()
	c.voiceHandler = handler
	c.mu.Unlock()
}

// ════════════════════════════════════════════════════════════════════════════════
// Server Query (Unauthenticated UDP Ping)
// ════════════════════════════════════════════════════════════════════════════════

// ServerPing sends an unauthenticated UDP ping and returns server info.
func MumbleServerPing(addr string) (version [4]byte, users, maxUsers, bandwidth uint32, err error) {
	host, port, splitErr := net.SplitHostPort(addr)
	if splitErr != nil {
		host = addr
		port = strconv.Itoa(mumbleDefaultPort)
	}

	conn, err := net.DialTimeout("udp", net.JoinHostPort(host, port), 5*time.Second)
	if err != nil {
		return
	}
	defer conn.Close()

	// Send 12-byte request: 4 zero bytes + 8 ident bytes
	var req [12]byte
	rand.Read(req[4:]) // random ident
	conn.SetWriteDeadline(time.Now().Add(2 * time.Second))
	if _, err = conn.Write(req[:]); err != nil {
		return
	}

	// Read 24-byte response
	var resp [24]byte
	conn.SetReadDeadline(time.Now().Add(5 * time.Second))
	n, readErr := conn.Read(resp[:])
	if readErr != nil {
		err = readErr
		return
	}
	if n < 24 {
		err = fmt.Errorf("mumble: server ping response too short: %d bytes", n)
		return
	}

	copy(version[:], resp[0:4])
	users = binary.BigEndian.Uint32(resp[12:16])
	maxUsers = binary.BigEndian.Uint32(resp[16:20])
	bandwidth = binary.BigEndian.Uint32(resp[20:24])
	return
}

// ════════════════════════════════════════════════════════════════════════════════
// Core Interface Implementation
// ════════════════════════════════════════════════════════════════════════════════

// Name returns the platform name for Mumble.
func (c *MumbleCore) Name() string { return mumblePlatform }

// Capabilities returns the list of supported features for Mumble.
func (c *MumbleCore) Capabilities() []string {
	return []string{CapText, CapChannels, CapVoice, CapAdmin, CapBlocking, CapSearch}
}

// Authenticate connects to a Mumble server using the provided configuration.
func (c *MumbleCore) Authenticate(cfg AuthConfig) error {
	// Load or generate certificate
	if err := c.loadSession(); err != nil {
		// Generate new cert
		cert, err := mumbleGenerateCert()
		if err != nil {
			return fmt.Errorf("mumble: failed to generate certificate: %w", err)
		}
		c.tlsCert = cert
		c.certHash = mumbleCertHash(cert)
	}

	server := cfg.Extra["server"]
	if server == "" {
		return fmt.Errorf("mumble: server address required in Extra[\"server\"]")
	}

	username := cfg.Extra["username"]
	if username == "" && cfg.Phone != "" {
		username = cfg.Phone
	}
	if username == "" {
		return fmt.Errorf("%w: mumble: username required", ErrInvalidInput)
	}

	password := cfg.Extra["password"]
	if password == "" {
		password = cfg.Password2F // reuse 2FA field for server password
	}

	var tokens []string
	if t := cfg.Extra["tokens"]; t != "" {
		tokens = strings.Split(t, ",")
	}

	isBot := cfg.Mode == AuthModeBot

	if err := c.connect(server, username, password, tokens, isBot); err != nil {
		return err
	}

	// Save session
	c.saveSession()
	return nil
}

// Logout disconnects from the Mumble server.
func (c *MumbleCore) Logout() error {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return ErrAuth
	}
	c.mu.RUnlock()
	return c.Close()
}

// Close shuts down the connection and releases all resources.
func (c *MumbleCore) Close() error {
	c.mu.Lock()
	if c.Session != nil {
		c.saveSession()
	}
	if c.cancel != nil {
		c.cancel()
	}
	if c.tlsConn != nil {
		c.tlsConn.Close()
		c.tlsConn = nil
	}
	if c.udpConn != nil {
		c.udpConn.Close()
		c.udpConn = nil
	}
	c.authed = false
	c.cryptReady = false
	c.udpReady = false
	c.mu.Unlock()

	c.wg.Wait()
	return nil
}

// OnUpdate registers a callback for server state change events.
func (c *MumbleCore) OnUpdate(handler func(Update)) {
	c.mu.Lock()
	c.updateHandlers = append(c.updateHandlers, handler)
	c.mu.Unlock()
}

// ── Dialogs ──

// GetDialogs returns the list of channels as dialogs.
func (c *MumbleCore) GetDialogs(opts PaginationOpts) ([]Dialog, error) {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return nil, ErrAuth
	}
	defer c.mu.RUnlock()

	dialogs := []Dialog{}
	// Sort channels by position then ID
	type chSort struct {
		pos int32
		id  uint32
		ch  *mumbleChannel
	}
	var sorted []chSort
	for _, ch := range c.channels {
		sorted = append(sorted, chSort{ch.Position, ch.ID, ch})
	}
	sort.Slice(sorted, func(i, j int) bool {
		if sorted[i].pos != sorted[j].pos {
			return sorted[i].pos < sorted[j].pos
		}
		return sorted[i].id < sorted[j].id
	})

	for _, s := range sorted {
		ch := s.ch
		// Count members in this channel
		memberCount := 0
		for _, u := range c.users {
			if u.ChannelID == ch.ID {
				memberCount++
			}
		}

		dlg := Dialog{
			ID:          strconv.FormatUint(uint64(ch.ID), 10),
			Type:        ChatTypeGroup,
			Title:       ch.Name,
			MemberCount: memberCount,
			Platform:    mumblePlatform,
		}
		if ch.ParentID != ch.ID {
			dlg.ParentID = strconv.FormatUint(uint64(ch.ParentID), 10)
		}
		if ch.Temporary {
			dlg.Type = ChatTypeTopic
		}

		// Find last message for this channel
		for i := len(c.messages) - 1; i >= 0; i-- {
			if c.messages[i].ChannelID == ch.ID && !c.messages[i].IsPrivate {
				dlg.LastMessage = &Message{
					ID:         c.messages[i].ID,
					ChatID:     dlg.ID,
					SenderID:   strconv.FormatUint(uint64(c.messages[i].Sender), 10),
					SenderName: c.messages[i].SenderName,
					Text:       c.messages[i].Message,
					Timestamp:  c.messages[i].Timestamp,
					IsOutgoing: c.messages[i].Sender == c.mySession,
					Platform:   mumblePlatform,
				}
				break
			}
		}

		dialogs = append(dialogs, dlg)
	}

	// Apply pagination
	offset := 0
	if opts.Offset != "" {
		offset, _ = strconv.Atoi(opts.Offset)
	}
	limit := opts.Limit
	if limit <= 0 {
		limit = 100
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

// CreateGroup creates a new permanent channel under root.
func (c *MumbleCore) CreateGroup(name string, members []string) (*Dialog, error) {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return nil, ErrAuth
	}
	c.mu.RUnlock()
	return c.createChannel(name, 0, false)
}

// CreateChannel creates a new permanent channel with an optional description.
func (c *MumbleCore) CreateChannel(name string, description string) (*Dialog, error) {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return nil, ErrAuth
	}
	c.mu.RUnlock()
	dlg, err := c.createChannel(name, 0, false)
	if err != nil {
		return nil, err
	}
	if description != "" {
		c.EditChatDescription(dlg.ID, description)
	}
	return dlg, nil
}

// CreateTopic creates a temporary sub-channel under the given parent channel.
func (c *MumbleCore) CreateTopic(chatID string, name string) (*Dialog, error) {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return nil, ErrAuth
	}
	c.mu.RUnlock()
	parentID, _ := strconv.ParseUint(chatID, 10, 32)
	return c.createChannel(name, uint32(parentID), true)
}

func (c *MumbleCore) createChannel(name string, parentID uint32, temporary bool) (*Dialog, error) {
	// Snapshot current channel IDs before sending
	c.mu.RLock()
	before := make(map[uint32]bool, len(c.channels))
	for id := range c.channels {
		before[id] = true
	}
	c.mu.RUnlock()

	msg := &mumbleChannelStateMsg{
		Parent:    parentID,
		HasParent: true,
		Name:      name,
		Temporary: temporary,
	}
	if err := c.tcpSend(mumbleMsgChannelState, msg.marshal()); err != nil {
		return nil, err
	}

	// Wait for server to send back ChannelState with the new channel ID
	deadline := time.After(5 * time.Second)
	ticker := time.NewTicker(50 * time.Millisecond)
	defer ticker.Stop()
	for {
		select {
		case <-deadline:
			// Timeout — return without ID (best effort)
			return &Dialog{
				Type:     ChatTypeGroup,
				Title:    name,
				Platform: mumblePlatform,
			}, nil
		case <-ticker.C:
			c.mu.RLock()
			for id, ch := range c.channels {
				if !before[id] && ch.Name == name {
					c.mu.RUnlock()
					return &Dialog{
						ID:       strconv.FormatUint(uint64(id), 10),
						Type:     ChatTypeGroup,
						Title:    name,
						Platform: mumblePlatform,
					}, nil
				}
			}
			c.mu.RUnlock()
		}
	}
}

// GetFolders returns an error because Mumble does not support folders.
func (c *MumbleCore) GetFolders() ([]Folder, error) {
	return nil, fmt.Errorf("%w: mumble does not support folders", ErrNotSupported)
}
// CreateFolder returns an error because Mumble does not support folders.
func (c *MumbleCore) CreateFolder(name string, chatIDs []string) (*Folder, error) {
	return nil, fmt.Errorf("%w: mumble does not support folders", ErrNotSupported)
}

// ── Messages ──

// SendMessage sends a text message to a channel or user.
func (c *MumbleCore) SendMessage(chatID string, msg OutgoingMessage) (*Message, error) {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return nil, ErrAuth
	}
	c.mu.RUnlock()
	textMsg := &mumbleTextMsg{Message: msg.Text}

	if strings.HasPrefix(chatID, "user:") {
		// Private message
		sessionStr := strings.TrimPrefix(chatID, "user:")
		session, err := strconv.ParseUint(sessionStr, 10, 32)
		if err != nil {
			return nil, ErrInvalidInput
		}
		textMsg.Session = []uint32{uint32(session)}
	} else {
		channelID, err := strconv.ParseUint(chatID, 10, 32)
		if err != nil {
			return nil, ErrInvalidInput
		}
		textMsg.ChannelID = []uint32{uint32(channelID)}
	}

	if err := c.tcpSend(mumbleMsgTextMessage, textMsg.marshal()); err != nil {
		return nil, err
	}

	c.mu.Lock()
	id := c.msgCounter.Add(1)
	entry := mumbleTextEntry{
		ID:         strconv.FormatInt(id, 10),
		Sender:     c.mySession,
		SenderName: c.getUserNameLocked(c.mySession),
		ChannelID:  0,
		Message:    msg.Text,
		Timestamp:  time.Now(),
	}
	c.messages = append(c.messages, entry)
	if len(c.messages) > mumbleMaxMsgBuffer {
		c.messages = c.messages[1:]
	}
	c.mu.Unlock()

	return &Message{
		ID:         entry.ID,
		ChatID:     chatID,
		SenderID:   strconv.FormatUint(uint64(c.mySession), 10),
		SenderName: entry.SenderName,
		Text:       msg.Text,
		Timestamp:  entry.Timestamp,
		Status:     MessageStatusSent,
		IsOutgoing: true,
		Platform:   mumblePlatform,
	}, nil
}

// GetMessages returns cached messages for a channel or private conversation.
func (c *MumbleCore) GetMessages(chatID string, opts PaginationOpts) ([]Message, error) {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return nil, ErrAuth
	}
	defer c.mu.RUnlock()

	msgs := []Message{}
	isPrivate := strings.HasPrefix(chatID, "user:")

	for _, entry := range c.messages {
		match := false
		if isPrivate {
			sessionStr := strings.TrimPrefix(chatID, "user:")
			session, _ := strconv.ParseUint(sessionStr, 10, 32)
			if entry.IsPrivate && (entry.Sender == uint32(session) || entry.Sender == c.mySession) {
				match = true
			}
		} else {
			cid, _ := strconv.ParseUint(chatID, 10, 32)
			if !entry.IsPrivate && entry.ChannelID == uint32(cid) {
				match = true
			}
		}

		if match {
			msgs = append(msgs, Message{
				ID:         entry.ID,
				ChatID:     chatID,
				SenderID:   strconv.FormatUint(uint64(entry.Sender), 10),
				SenderName: entry.SenderName,
				Text:       entry.Message,
				Timestamp:  entry.Timestamp,
				Status:     MessageStatusDelivered,
				IsOutgoing: entry.Sender == c.mySession,
				Platform:   mumblePlatform,
			})
		}
	}

	// Apply pagination
	limit := opts.Limit
	if limit <= 0 {
		limit = 50
	}
	if len(msgs) > limit {
		msgs = msgs[len(msgs)-limit:]
	}
	return msgs, nil
}

// EditMessage returns an error because Mumble does not support message editing.
func (c *MumbleCore) EditMessage(chatID, msgID, text string) (*Message, error) {
	return nil, fmt.Errorf("%w: mumble does not support message editing", ErrNotSupported)
}
// DeleteMessage returns an error because Mumble does not support message deletion.
func (c *MumbleCore) DeleteMessage(chatID, msgID string) error {
	return fmt.Errorf("%w: mumble does not support message deletion", ErrNotSupported)
}

// ReplyToMessage sends a message since Mumble has no native reply concept.
func (c *MumbleCore) ReplyToMessage(chatID, replyToMsgID string, msg OutgoingMessage) (*Message, error) {
	// Auth check is in SendMessage
	return c.SendMessage(chatID, msg) // Mumble has no reply concept
}

// ForwardMessage returns an error because Mumble does not support message forwarding.
func (c *MumbleCore) ForwardMessage(fromChatID, msgID, toChatID string) (*Message, error) {
	return nil, fmt.Errorf("%w: mumble does not support message forwarding", ErrNotSupported)
}
// ReactToMessage returns an error because Mumble does not support reactions.
func (c *MumbleCore) ReactToMessage(chatID, msgID, emoji string) error {
	return fmt.Errorf("%w: mumble does not support reactions", ErrNotSupported)
}
// PinMessage returns an error because Mumble does not support message pinning.
func (c *MumbleCore) PinMessage(chatID, msgID string) error {
	return fmt.Errorf("%w: mumble does not support message pinning", ErrNotSupported)
}
// UnpinMessage returns an error because Mumble does not support message pinning.
func (c *MumbleCore) UnpinMessage(chatID, msgID string) error {
	return fmt.Errorf("%w: mumble does not support message pinning", ErrNotSupported)
}

// ── Read State ──

// MarkAsRead is a no-op since Mumble has no read receipts.
func (c *MumbleCore) MarkAsRead(chatID, upToMsgID string) error {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return ErrAuth
	}
	c.mu.RUnlock()
	return nil
}
// GetReadState returns an empty read state since Mumble has no read receipts.
func (c *MumbleCore) GetReadState(chatID string) (*ReadState, error) {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return nil, ErrAuth
	}
	c.mu.RUnlock()
	return &ReadState{}, nil
}

// ── Files ──

// UploadFile returns an error because Mumble does not support file uploads.
func (c *MumbleCore) UploadFile(chatID string, file FileUpload, progress func(sent, total int64)) (*Message, error) {
	return nil, fmt.Errorf("%w: mumble does not support file uploads", ErrNotSupported)
}

// DownloadFile returns an error because Mumble does not support file downloads.
func (c *MumbleCore) DownloadFile(fileRef FileRef, dest string, progress func(recv, total int64)) error {
	return fmt.Errorf("%w: mumble does not support file downloads", ErrNotSupported)
}

// SendImageBase64 sends a base64-encoded image as an inline HTML message.
func (c *MumbleCore) SendImageBase64(chatID, b64, caption string) (*Message, error) {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return nil, ErrAuth
	}
	allowHTML := c.serverConfig.AllowHTML
	c.mu.RUnlock()

	if !allowHTML {
		return nil, fmt.Errorf("mumble: server does not allow HTML (required for inline images)")
	}

	html := fmt.Sprintf(`<img src="data:image/png;base64,%s" />`, b64)
	if caption != "" {
		html = caption + "<br/>" + html
	}
	return c.SendMessage(chatID, OutgoingMessage{Text: html})
}

// ── Calls ──

// StartCall joins a voice channel, which is the Mumble equivalent of starting a call.
func (c *MumbleCore) StartCall(chatID string, video bool) (*CallSession, error) {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return nil, ErrAuth
	}
	c.mu.RUnlock()
	// In Mumble, "calling" = moving to a voice channel
	channelID, err := strconv.ParseUint(chatID, 10, 32)
	if err != nil {
		return nil, ErrInvalidInput
	}

	if err := c.MoveToChannel(uint32(channelID)); err != nil {
		return nil, err
	}

	return &CallSession{
		ID:     chatID,
		ChatID: chatID,
		State:  CallStateActive,
	}, nil
}

// JoinGroupCall joins a voice channel by moving to it.
func (c *MumbleCore) JoinGroupCall(chatID string) (*CallSession, error) {
	return c.StartCall(chatID, false)
}

// EndCall leaves the current voice channel by moving to root.
func (c *MumbleCore) EndCall(callID string) error {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return ErrAuth
	}
	c.mu.RUnlock()
	// Move to root channel
	return c.MoveToChannel(0)
}

// SetCallMuted toggles self-mute for the current voice session.
func (c *MumbleCore) SetCallMuted(callID string, muted bool) error {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return ErrAuth
	}
	c.mu.RUnlock()
	return c.SelfMute(muted)
}

// ToggleCamera toggles the camera on/off for an active call.
func (c *MumbleCore) ToggleCamera(_ string, _ bool) error {
	return fmt.Errorf("%w: mumble does not support camera toggle", ErrNotSupported)
}

// ── Profile ──

// GetProfile returns user information for the given session ID.
func (c *MumbleCore) GetProfile(userID string) (*User, error) {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return nil, ErrAuth
	}

	// Empty string = self.
	var session uint64
	if userID == "" {
		session = uint64(c.mySession)
	} else {
		var err error
		session, err = strconv.ParseUint(userID, 10, 32)
		if err != nil {
			c.mu.RUnlock()
			return nil, ErrInvalidInput
		}
	}

	u, ok := c.users[uint32(session)]
	if !ok {
		c.mu.RUnlock()
		return nil, ErrNotFound
	}
	user := &User{
		ID:          userID,
		Username:    u.Name,
		DisplayName: u.Name,
		IsBot:       false,
		IsOnline:    true,
		Platform:    mumblePlatform,
	}
	c.mu.RUnlock()
	return user, nil
}

// ── Chat Management ──

// GetChatInfo returns channel details including member count.
func (c *MumbleCore) GetChatInfo(chatID string) (*Dialog, error) {
	channelID, err := strconv.ParseUint(chatID, 10, 32)
	if err != nil {
		return nil, ErrInvalidInput
	}

	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return nil, ErrAuth
	}
	ch, ok := c.channels[uint32(channelID)]
	if !ok {
		c.mu.RUnlock()
		return nil, ErrNotFound
	}

	memberCount := 0
	for _, u := range c.users {
		if u.ChannelID == uint32(channelID) {
			memberCount++
		}
	}
	c.mu.RUnlock()

	return &Dialog{
		ID:          chatID,
		Type:        ChatTypeGroup,
		Title:       ch.Name,
		MemberCount: memberCount,
		Platform:    mumblePlatform,
	}, nil
}

// EditChatTitle renames a channel.
func (c *MumbleCore) EditChatTitle(chatID, title string) error {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return ErrAuth
	}
	c.mu.RUnlock()
	channelID, err := strconv.ParseUint(chatID, 10, 32)
	if err != nil {
		return ErrInvalidInput
	}
	msg := &mumbleChannelStateMsg{
		ChannelID:    uint32(channelID),
		HasChannelID: true,
		Name:         title,
	}
	return c.tcpSend(mumbleMsgChannelState, msg.marshal())
}

// EditChatDescription updates the description of a channel.
func (c *MumbleCore) EditChatDescription(chatID, description string) error {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return ErrAuth
	}
	c.mu.RUnlock()
	channelID, err := strconv.ParseUint(chatID, 10, 32)
	if err != nil {
		return ErrInvalidInput
	}
	msg := &mumbleChannelStateMsg{
		ChannelID:    uint32(channelID),
		HasChannelID: true,
		Description:  description,
	}
	return c.tcpSend(mumbleMsgChannelState, msg.marshal())
}

// LeaveChat moves the user to the root channel.
func (c *MumbleCore) LeaveChat(chatID string) error {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return ErrAuth
	}
	c.mu.RUnlock()
	return c.MoveToChannel(0) // Move to root
}

// GetInviteLink returns an error because Mumble does not support invite links.
func (c *MumbleCore) GetInviteLink(chatID string) (string, error) {
	return "", fmt.Errorf("%w: mumble does not support invite links", ErrNotSupported)
}

// ── Members ──

// AddMembers moves users into the specified channel.
func (c *MumbleCore) AddMembers(chatID string, userIDs []string) error {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return ErrAuth
	}
	c.mu.RUnlock()
	channelID, err := strconv.ParseUint(chatID, 10, 32)
	if err != nil {
		return ErrInvalidInput
	}
	for _, uid := range userIDs {
		session, err := strconv.ParseUint(uid, 10, 32)
		if err != nil {
			continue
		}
		if err := c.MoveUser(uint32(session), uint32(channelID)); err != nil {
			return err
		}
	}
	return nil
}

// RemoveMember kicks a user from the server.
func (c *MumbleCore) RemoveMember(chatID, userID string) error {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return ErrAuth
	}
	c.mu.RUnlock()
	session, err := strconv.ParseUint(userID, 10, 32)
	if err != nil {
		return ErrInvalidInput
	}
	msg := &mumbleUserRemoveMsg{Session: uint32(session)}
	return c.tcpSend(mumbleMsgUserRemove, msg.marshal())
}

// BanMember bans a user by certificate and IP.
func (c *MumbleCore) BanMember(chatID, userID string) error {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return ErrAuth
	}
	c.mu.RUnlock()
	session, err := strconv.ParseUint(userID, 10, 32)
	if err != nil {
		return ErrInvalidInput
	}
	msg := &mumbleUserRemoveMsg{
		Session:        uint32(session),
		Ban:            true,
		BanCertificate: true,
		BanIP:          true,
	}
	return c.tcpSend(mumbleMsgUserRemove, msg.marshal())
}

// UnbanMember removes all ban entries matching the user's certificate hash.
func (c *MumbleCore) UnbanMember(chatID, userID string) error {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return ErrAuth
	}
	c.mu.RUnlock()
	// Need to manipulate ban list
	// First query ban list
	query := &mumbleBanListMsg{Query: true}
	if err := c.tcpSend(mumbleMsgBanList, query.marshal()); err != nil {
		return err
	}
	// Wait briefly for response
	time.Sleep(500 * time.Millisecond)

	c.mu.RLock()
	bans := make([]MumbleBanEntry, len(c.banList))
	copy(bans, c.banList)
	c.mu.RUnlock()

	// Filter out the user's bans (by hash)
	c.mu.RLock()
	targetHash := ""
	for _, u := range c.users {
		if strconv.FormatUint(uint64(u.Session), 10) == userID {
			targetHash = u.Hash
			break
		}
	}
	c.mu.RUnlock()

	if targetHash == "" {
		return ErrNotFound
	}

	var filtered []MumbleBanEntry
	for _, b := range bans {
		if b.Hash != targetHash {
			filtered = append(filtered, b)
		}
	}

	set := &mumbleBanListMsg{Bans: filtered, Query: false}
	return c.tcpSend(mumbleMsgBanList, set.marshal())
}

// GetMembers returns the users currently in a channel.
func (c *MumbleCore) GetMembers(chatID string, opts PaginationOpts) ([]User, error) {
	channelID, err := strconv.ParseUint(chatID, 10, 32)
	if err != nil {
		return nil, ErrInvalidInput
	}

	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return nil, ErrAuth
	}
	defer c.mu.RUnlock()

	users := []User{}
	for _, u := range c.users {
		if u.ChannelID == uint32(channelID) {
			users = append(users, User{
				ID:          strconv.FormatUint(uint64(u.Session), 10),
				Username:    u.Name,
				DisplayName: u.Name,
				IsOnline:    true,
				Platform:    mumblePlatform,
			})
		}
	}

	return users, nil
}

// SetAdmin returns an error because Mumble uses ACLs instead of admin roles.
func (c *MumbleCore) SetAdmin(chatID, userID string, admin bool) error {
	return fmt.Errorf("%w: mumble uses ACL system instead of admin roles", ErrNotSupported)
}

// ── Contacts ──

// GetContacts returns all users currently connected to the server.
func (c *MumbleCore) GetContacts() ([]User, error) {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return nil, ErrAuth
	}
	defer c.mu.RUnlock()

	users := []User{}
	for _, u := range c.users {
		users = append(users, User{
			ID:          strconv.FormatUint(uint64(u.Session), 10),
			Username:    u.Name,
			DisplayName: u.Name,
			IsOnline:    true,
			Platform:    mumblePlatform,
		})
	}
	return users, nil
}

// AddContact returns an error because Mumble does not support contacts.
func (c *MumbleCore) AddContact(phone, firstName, lastName string) error {
	return fmt.Errorf("%w: mumble does not support contacts", ErrNotSupported)
}
// DeleteContact returns an error because Mumble does not support contacts.
func (c *MumbleCore) DeleteContact(userID string) error {
	return fmt.Errorf("%w: mumble does not support contacts", ErrNotSupported)
}

// BlockUser locally mutes a user so their voice packets are ignored.
func (c *MumbleCore) BlockUser(userID string) error {
	session, err := strconv.ParseUint(userID, 10, 32)
	if err != nil {
		return ErrInvalidInput
	}
	c.mu.Lock()
	if !c.authed {
		c.mu.Unlock()
		return ErrAuth
	}
	c.localMutes[uint32(session)] = true
	c.mu.Unlock()
	return nil
}

// UnblockUser removes the local mute for a user.
func (c *MumbleCore) UnblockUser(userID string) error {
	session, err := strconv.ParseUint(userID, 10, 32)
	if err != nil {
		return ErrInvalidInput
	}
	c.mu.Lock()
	if !c.authed {
		c.mu.Unlock()
		return ErrAuth
	}
	delete(c.localMutes, uint32(session))
	c.mu.Unlock()
	return nil
}

// GetBlockedUsers returns the list of locally muted users.
func (c *MumbleCore) GetBlockedUsers() ([]User, error) {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return nil, ErrAuth
	}
	defer c.mu.RUnlock()

	users := []User{}
	for session := range c.localMutes {
		name := ""
		if u, ok := c.users[session]; ok {
			name = u.Name
		}
		users = append(users, User{
			ID:          strconv.FormatUint(uint64(session), 10),
			DisplayName: name,
			Platform:    mumblePlatform,
		})
	}
	return users, nil
}

// ── Search ──

// SearchMessages searches cached messages for text matching the query.
func (c *MumbleCore) SearchMessages(chatID, query string, opts PaginationOpts) ([]Message, error) {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return nil, ErrAuth
	}
	defer c.mu.RUnlock()

	queryLower := strings.ToLower(query)
	msgs := []Message{}
	for _, entry := range c.messages {
		if strings.Contains(strings.ToLower(entry.Message), queryLower) {
			msgs = append(msgs, Message{
				ID:         entry.ID,
				ChatID:     chatID,
				SenderID:   strconv.FormatUint(uint64(entry.Sender), 10),
				SenderName: entry.SenderName,
				Text:       entry.Message,
				Timestamp:  entry.Timestamp,
				IsOutgoing: entry.Sender == c.mySession,
				Platform:   mumblePlatform,
			})
		}
	}
	return msgs, nil
}

// SearchGlobal searches channel names matching the query.
func (c *MumbleCore) SearchGlobal(query string, opts PaginationOpts) ([]Dialog, error) {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return nil, ErrAuth
	}
	defer c.mu.RUnlock()

	queryLower := strings.ToLower(query)
	results := []Dialog{}
	for _, ch := range c.channels {
		if strings.Contains(strings.ToLower(ch.Name), queryLower) {
			results = append(results, Dialog{
				ID:       strconv.FormatUint(uint64(ch.ID), 10),
				Type:     ChatTypeGroup,
				Title:    ch.Name,
				Platform: mumblePlatform,
			})
		}
	}
	return results, nil
}

// ── Typing / Polls / Stickers ──

// SendTyping is a no-op since Mumble does not support typing indicators.
func (c *MumbleCore) SendTyping(chatID string) error {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return ErrAuth
	}
	c.mu.RUnlock()
	return nil // no-op
}
// CreatePoll returns an error because Mumble does not support polls.
func (c *MumbleCore) CreatePoll(chatID, question string, options []string) (*Message, error) {
	return nil, fmt.Errorf("%w: mumble does not support polls", ErrNotSupported)
}
// VotePoll returns an error because Mumble does not support polls.
func (c *MumbleCore) VotePoll(chatID, msgID string, optionIndex int) error {
	return fmt.Errorf("%w: mumble does not support polls", ErrNotSupported)
}
// SendSticker returns an error because Mumble does not support stickers.
func (c *MumbleCore) SendSticker(chatID, stickerID string) (*Message, error) {
	return nil, fmt.Errorf("%w: mumble does not support stickers", ErrNotSupported)
}

// ── Sessions ──

// GetSessions returns all connected user sessions on the server.
func (c *MumbleCore) GetSessions() ([]Session, error) {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return nil, ErrAuth
	}
	defer c.mu.RUnlock()

	var sessions []Session
	for _, u := range c.users {
		sessions = append(sessions, Session{
			ID:        strconv.FormatUint(uint64(u.Session), 10),
			Device:    u.Name,
			Platform:  mumblePlatform,
			IsCurrent: u.Session == c.mySession,
		})
	}
	return sessions, nil
}

// TerminateSession kicks a user from the server by session ID.
func (c *MumbleCore) TerminateSession(sessionID string) error {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return ErrAuth
	}
	c.mu.RUnlock()
	session, err := strconv.ParseUint(sessionID, 10, 32)
	if err != nil {
		return ErrInvalidInput
	}
	msg := &mumbleUserRemoveMsg{
		Session: uint32(session),
		Reason:  "Kicked",
	}
	return c.tcpSend(mumbleMsgUserRemove, msg.marshal())
}

// ════════════════════════════════════════════════════════════════════════════════
// Mumble-Specific Methods (beyond Core interface)
// ════════════════════════════════════════════════════════════════════════════════

func (c *MumbleCore) getUserNameLocked(session uint32) string {
	if u, ok := c.users[session]; ok {
		return u.Name
	}
	return ""
}

// MoveToChannel moves self to the specified channel.
func (c *MumbleCore) MoveToChannel(channelID uint32) error {
	c.mu.RLock()
	session := c.mySession
	c.mu.RUnlock()
	return c.MoveUser(session, channelID)
}

// MoveUser moves another user to a channel.
func (c *MumbleCore) MoveUser(session, channelID uint32) error {
	msg := &mumbleUserStateMsg{
		Session:      session,
		HasSession:   true,
		ChannelID:    channelID,
		HasChannelID: true,
	}
	return c.tcpSend(mumbleMsgUserState, msg.marshal())
}

// ServerMute admin-mutes a user.
func (c *MumbleCore) ServerMute(session uint32, muted bool) error {
	msg := &mumbleUserStateMsg{
		Session:    session,
		HasSession: true,
		Mute:       muted,
		HasMute:    true,
	}
	return c.tcpSend(mumbleMsgUserState, msg.marshal())
}

// ServerDeaf admin-deafens a user.
func (c *MumbleCore) ServerDeaf(session uint32, deafed bool) error {
	msg := &mumbleUserStateMsg{
		Session:    session,
		HasSession: true,
		Deaf:       deafed,
		HasDeaf:    true,
	}
	return c.tcpSend(mumbleMsgUserState, msg.marshal())
}

// SelfMute toggles self-mute.
func (c *MumbleCore) SelfMute(muted bool) error {
	c.mu.RLock()
	session := c.mySession
	c.mu.RUnlock()

	msg := &mumbleUserStateMsg{
		Session:     session,
		HasSession:  true,
		SelfMute:    muted,
		HasSelfMute: true,
	}
	return c.tcpSend(mumbleMsgUserState, msg.marshal())
}

// SelfDeaf toggles self-deafen.
func (c *MumbleCore) SelfDeaf(deafed bool) error {
	c.mu.RLock()
	session := c.mySession
	c.mu.RUnlock()

	msg := &mumbleUserStateMsg{
		Session:     session,
		HasSession:  true,
		SelfDeaf:    deafed,
		HasSelfDeaf: true,
	}
	return c.tcpSend(mumbleMsgUserState, msg.marshal())
}

// Suppress prevents a user from talking (different from mute).
func (c *MumbleCore) Suppress(session uint32, suppressed bool) error {
	msg := &mumbleUserStateMsg{
		Session:     session,
		HasSession:  true,
		Suppress:    suppressed,
		HasSuppress: true,
	}
	return c.tcpSend(mumbleMsgUserState, msg.marshal())
}

// SetComment sets own comment (HTML allowed).
func (c *MumbleCore) SetComment(comment string) error {
	c.mu.RLock()
	session := c.mySession
	c.mu.RUnlock()

	msg := &mumbleUserStateMsg{
		Session:    session,
		HasSession: true,
		Comment:    comment,
	}
	return c.tcpSend(mumbleMsgUserState, msg.marshal())
}

// SetTexture sets own avatar/texture.
func (c *MumbleCore) SetTexture(imageData []byte) error {
	c.mu.RLock()
	session := c.mySession
	c.mu.RUnlock()

	msg := &mumbleUserStateMsg{
		Session:    session,
		HasSession: true,
		Texture:    imageData,
	}
	return c.tcpSend(mumbleMsgUserState, msg.marshal())
}

// SetPrioritySpeaker sets priority speaker status for a user.
func (c *MumbleCore) SetPrioritySpeaker(session uint32, enabled bool) error {
	msg := &mumbleUserStateMsg{
		Session:            session,
		HasSession:         true,
		PrioritySpeaker:    enabled,
		HasPrioritySpeaker: true,
	}
	return c.tcpSend(mumbleMsgUserState, msg.marshal())
}

// SetRecording announces recording state.
func (c *MumbleCore) SetRecording(recording bool) error {
	c.mu.RLock()
	session := c.mySession
	c.mu.RUnlock()

	msg := &mumbleUserStateMsg{
		Session:      session,
		HasSession:   true,
		Recording:    recording,
		HasRecording: true,
	}
	return c.tcpSend(mumbleMsgUserState, msg.marshal())
}

// RegisterSelf registers own certificate with the server.
func (c *MumbleCore) RegisterSelf() error {
	c.mu.RLock()
	session := c.mySession
	c.mu.RUnlock()

	msg := &mumbleUserStateMsg{
		Session:    session,
		HasSession: true,
		UserID:     0,
		HasUserID:  true,
	}
	return c.tcpSend(mumbleMsgUserState, msg.marshal())
}

// RegisterUser registers another user by session.
func (c *MumbleCore) RegisterUser(session uint32) error {
	msg := &mumbleUserStateMsg{
		Session:    session,
		HasSession: true,
		UserID:     0,
		HasUserID:  true,
	}
	return c.tcpSend(mumbleMsgUserState, msg.marshal())
}

// GetRegisteredUsers queries the server's registered user list.
func (c *MumbleCore) GetRegisteredUsers() error {
	msg := &mumbleUserListMsg{}
	return c.tcpSend(mumbleMsgUserList, msg.marshal())
}

// UnregisterUser removes a registered user.
func (c *MumbleCore) UnregisterUser(userID uint32) error {
	msg := &mumbleUserListMsg{
		Users: []mumbleUserListEntry{{UserID: userID}},
	}
	return c.tcpSend(mumbleMsgUserList, msg.marshal())
}

// GetBanList queries the server's ban list.
func (c *MumbleCore) GetBanList() ([]MumbleBanEntry, error) {
	query := &mumbleBanListMsg{Query: true}
	if err := c.tcpSend(mumbleMsgBanList, query.marshal()); err != nil {
		return nil, err
	}
	time.Sleep(1000 * time.Millisecond)
	c.mu.RLock()
	bans := make([]MumbleBanEntry, len(c.banList))
	copy(bans, c.banList)
	c.mu.RUnlock()
	return bans, nil
}

// SetBanList replaces the server's ban list.
func (c *MumbleCore) SetBanList(bans []MumbleBanEntry) error {
	msg := &mumbleBanListMsg{Bans: bans, Query: false}
	return c.tcpSend(mumbleMsgBanList, msg.marshal())
}

// AddBan adds a ban entry.
func (c *MumbleCore) AddBan(address []byte, mask uint32, name, hash, reason string, duration uint32) error {
	// Query current, add, set
	current, err := c.GetBanList()
	if err != nil {
		return err
	}
	// Normalize address to 16-byte IPv4-mapped IPv6 — Mumble expects this format
	addr := net.IP(address).To16()
	if addr == nil {
		addr = address
	}
	current = append(current, MumbleBanEntry{
		Address:  addr,
		Mask:     mask,
		Name:     name,
		Hash:     hash,
		Reason:   reason,
		Start:    time.Now().UTC().Format(time.RFC3339),
		Duration: duration,
	})
	return c.SetBanList(current)
}

// GetACL queries ACLs for a channel.
func (c *MumbleCore) GetACL(channelID uint32) (*MumbleACLMsg, error) {
	msg := &MumbleACLMsg{ChannelID: channelID, Query: true}
	if err := c.tcpSend(mumbleMsgACL, msg.marshal()); err != nil {
		return nil, err
	}
	// Note: response comes async; caller should use OnUpdate or wait
	return nil, nil
}

// SetACL sets ACLs for a channel.
func (c *MumbleCore) SetACL(channelID uint32, groups []MumbleACLGroup, acls []MumbleACLEntry, inheritACLs bool) error {
	msg := &MumbleACLMsg{
		ChannelID:   channelID,
		InheritACLs: inheritACLs,
		Groups:      groups,
		ACLs:        acls,
		Query:       false,
	}
	return c.tcpSend(mumbleMsgACL, msg.marshal())
}

// GetPermissions queries permissions for a channel.
func (c *MumbleCore) GetPermissions(channelID uint32) (uint32, error) {
	msg := &mumblePermissionQueryMsg{ChannelID: channelID}
	if err := c.tcpSend(mumbleMsgPermissionQuery, msg.marshal()); err != nil {
		return 0, err
	}
	time.Sleep(200 * time.Millisecond)
	c.mu.RLock()
	perms := c.permissions[channelID]
	c.mu.RUnlock()
	return perms, nil
}

// QueryUsers resolves user IDs to names and vice versa.
func (c *MumbleCore) QueryUsers(ids []uint32, names []string) error {
	msg := &mumbleQueryUsersMsg{IDs: ids, Names: names}
	return c.tcpSend(mumbleMsgQueryUsers, msg.marshal())
}

// RequestBlob requests large blobs (textures, comments, descriptions).
func (c *MumbleCore) RequestBlob(textures, comments, descriptions []uint32) error {
	msg := &mumbleRequestBlobMsg{
		SessionTexture:     textures,
		SessionComment:     comments,
		ChannelDescription: descriptions,
	}
	return c.tcpSend(mumbleMsgRequestBlob, msg.marshal())
}

// GetUserStats requests detailed statistics for a user.
func (c *MumbleCore) GetUserStats(session uint32) error {
	msg := &mumbleUserStatsMsg{Session: session}
	return c.tcpSend(mumbleMsgUserStats, msg.marshal())
}

// SetAccessTokens updates the access tokens for this connection.
func (c *MumbleCore) SetAccessTokens(tokens []string) error {
	auth := &mumbleAuthenticate{Tokens: tokens}
	return c.tcpSend(mumbleMsgAuthenticate, auth.marshal())
}

// LinkChannels adds links between channels.
func (c *MumbleCore) LinkChannels(channelID uint32, linkIDs []uint32) error {
	msg := &mumbleChannelStateMsg{
		ChannelID:    channelID,
		HasChannelID: true,
		LinksAdd:     linkIDs,
	}
	return c.tcpSend(mumbleMsgChannelState, msg.marshal())
}

// UnlinkChannels removes links between channels.
func (c *MumbleCore) UnlinkChannels(channelID uint32, unlinkIDs []uint32) error {
	msg := &mumbleChannelStateMsg{
		ChannelID:    channelID,
		HasChannelID: true,
		LinksRemove:  unlinkIDs,
	}
	return c.tcpSend(mumbleMsgChannelState, msg.marshal())
}

// AddChannelListener starts listening to channels without being in them.
func (c *MumbleCore) AddChannelListener(channelIDs []uint32) error {
	c.mu.RLock()
	session := c.mySession
	c.mu.RUnlock()

	msg := &mumbleUserStateMsg{
		Session:             session,
		HasSession:          true,
		ListeningChannelAdd: channelIDs,
	}
	return c.tcpSend(mumbleMsgUserState, msg.marshal())
}

// RemoveChannelListener stops listening to channels.
func (c *MumbleCore) RemoveChannelListener(channelIDs []uint32) error {
	c.mu.RLock()
	session := c.mySession
	c.mu.RUnlock()

	msg := &mumbleUserStateMsg{
		Session:                session,
		HasSession:             true,
		ListeningChannelRemove: channelIDs,
	}
	return c.tcpSend(mumbleMsgUserState, msg.marshal())
}

// SetListenerVolume adjusts volume for a listened channel.
func (c *MumbleCore) SetListenerVolume(channelID uint32, volume float32) error {
	c.mu.RLock()
	session := c.mySession
	c.mu.RUnlock()

	msg := &mumbleUserStateMsg{
		Session:    session,
		HasSession: true,
		ListeningVolumeAdj: []mumbleVolumeAdj{
			{ListeningChannel: channelID, VolumeAdjustment: volume},
		},
	}
	return c.tcpSend(mumbleMsgUserState, msg.marshal())
}

// SendPluginData sends plugin data to specific receivers.
func (c *MumbleCore) SendPluginData(receivers []uint32, dataID string, data []byte) error {
	msg := &mumblePluginDataMsg{
		ReceiverSessions: receivers,
		DataID:           dataID,
		Data:             data,
	}
	return c.tcpSend(mumbleMsgPluginDataTransmission, msg.marshal())
}

// TriggerContextAction triggers a registered context action.
func (c *MumbleCore) TriggerContextAction(action string, session, channelID uint32) error {
	msg := &mumbleContextActionMsg{
		Session:   session,
		ChannelID: channelID,
		Action:    action,
	}
	return c.tcpSend(mumbleMsgContextAction, msg.marshal())
}

// SetVoiceTarget registers a whisper target.
func (c *MumbleCore) SetVoiceTarget(id uint32, targets []MumbleVoiceTargetEntry) error {
	msg := &mumbleVoiceTargetMsg{
		ID:      id,
		Targets: targets,
	}
	return c.tcpSend(mumbleMsgVoiceTarget, msg.marshal())
}

// GetServerConfig returns the cached server config.
func (c *MumbleCore) GetServerConfig() MumbleServerConfig {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.serverConfig
}

// CreateTemporaryChannel creates a temporary channel (auto-removed when empty).
func (c *MumbleCore) CreateTemporaryChannel(name string, parent uint32) error {
	msg := &mumbleChannelStateMsg{
		Parent:    parent,
		HasParent: true,
		Name:      name,
		Temporary: true,
	}
	return c.tcpSend(mumbleMsgChannelState, msg.marshal())
}

// DeleteChannel removes a channel.
func (c *MumbleCore) DeleteChannel(channelID uint32) error {
	msg := &mumbleChannelRemoveMsg{ChannelID: channelID}
	return c.tcpSend(mumbleMsgChannelRemove, msg.marshal())
}

// SetChannelMaxUsers sets the max users for a channel.
func (c *MumbleCore) SetChannelMaxUsers(channelID, maxUsers uint32) error {
	msg := &mumbleChannelStateMsg{
		ChannelID:    channelID,
		HasChannelID: true,
		MaxUsers:     maxUsers,
	}
	return c.tcpSend(mumbleMsgChannelState, msg.marshal())
}

// SetChannelPosition sets the sort position for a channel.
func (c *MumbleCore) SetChannelPosition(channelID uint32, position int32) error {
	msg := &mumbleChannelStateMsg{
		ChannelID:    channelID,
		HasChannelID: true,
		Position:     position,
	}
	return c.tcpSend(mumbleMsgChannelState, msg.marshal())
}

// MoveChannel moves a channel to a new parent.
func (c *MumbleCore) MoveChannel(channelID, newParent uint32) error {
	msg := &mumbleChannelStateMsg{
		ChannelID:    channelID,
		HasChannelID: true,
		Parent:       newParent,
		HasParent:    true,
	}
	return c.tcpSend(mumbleMsgChannelState, msg.marshal())
}

// SendTreeMessage sends a text message to a channel tree (recursively).
func (c *MumbleCore) SendTreeMessage(channelID uint32, message string) error {
	msg := &mumbleTextMsg{
		TreeID:  []uint32{channelID},
		Message: message,
	}
	return c.tcpSend(mumbleMsgTextMessage, msg.marshal())
}

// RequestNonceResync requests a nonce resynchronization.
func (c *MumbleCore) RequestNonceResync() error {
	msg := &mumbleCryptSetupMsg{} // empty = request resync
	return c.tcpSend(mumbleMsgCryptSetup, msg.marshal())
}

// ── Exported wrappers for testing ──

// MumbleCryptState is an exported wrapper for testing.
type MumbleCryptState struct{ mumbleCryptState }

func (s *MumbleCryptState) Init(key, clientNonce, serverNonce []byte) error {
	return s.mumbleCryptState.init(key, clientNonce, serverNonce)
}
func (s *MumbleCryptState) Encrypt(dst, src []byte) int {
	return s.mumbleCryptState.encrypt(dst, src)
}
func (s *MumbleCryptState) Decrypt(dst, src []byte) (int, error) {
	return s.mumbleCryptState.decrypt(dst, src)
}

// OCB2Encrypt is an exported wrapper for testing.
func OCB2Encrypt(ciph cipher.Block, dst, src, nonce, tag []byte) {
	ocb2Encrypt(ciph, dst, src, nonce, tag)
}

// OCB2Decrypt is an exported wrapper for testing.
func OCB2Decrypt(ciph cipher.Block, plain, encrypted, nonce, tag []byte) bool {
	return ocb2Decrypt(ciph, plain, encrypted, nonce, tag)
}

// DebugBuildVoicePacket returns the raw bytes of a voice packet for debugging.
func (c *MumbleCore) DebugBuildVoicePacket(opusData []byte, target int, seq int64) []byte {
	return c.buildVoicePacket(opusData, target, seq, false)
}

// DebugBuildLegacyVoicePacket returns legacy-format voice packet bytes.
func (c *MumbleCore) DebugBuildLegacyVoicePacket(opusData []byte, target int, seq int64) []byte {
	return c.buildLegacyVoicePacket(opusData, target, seq, false)
}

// DebugVoiceTunnelCount returns count of TCP UDPTunnel messages received.
func (c *MumbleCore) DebugVoiceTunnelCount() uint32 {
	return c.voiceTunnelRecv.Load()
}

// DebugCodecVersion returns the negotiated codec version.
func (c *MumbleCore) DebugCodecVersion() (alpha, beta int32, preferAlpha, opus bool) {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.codecVersion.Alpha, c.codecVersion.Beta, c.codecVersion.PreferAlpha, c.codecVersion.Opus
}

// DebugUserFlags returns mute/deaf/suppress flags for a user session.
func (c *MumbleCore) DebugUserFlags(session uint32) string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	u, ok := c.users[session]
	if !ok {
		return fmt.Sprintf("session %d not found", session)
	}
	return fmt.Sprintf("name=%s ch=%d mute=%v deaf=%v suppress=%v selfMute=%v selfDeaf=%v",
		u.Name, u.ChannelID, u.Mute, u.Deaf, u.Suppress, u.SelfMute, u.SelfDeaf)
}

// DebugServerVersion returns server version info for debugging.
func (c *MumbleCore) DebugServerVersion() (v1 uint32, v2 uint64, release string, protobuf bool) {
	c.mu.RLock()
	v := c.serverVersion
	c.mu.RUnlock()
	return v.VersionV1, v.VersionV2, v.Release, c.serverSupportsProtobufUDP()
}

// DebugMySession returns this client's session ID.
func (c *MumbleCore) DebugMySession() uint32 {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.mySession
}

// DebugState returns internal state for debugging tests.
func (c *MumbleCore) DebugState() (cryptReady, udpReady bool, udpSent, udpRecv, tcpSent, tcpRecv uint32) {
	c.mu.RLock()
	cryptReady = c.cryptReady
	udpReady = c.udpReady
	c.mu.RUnlock()
	udpSent = c.udpPktsSent.Load()
	udpRecv = c.udpPktsRecv.Load()
	tcpSent = c.tcpPktsSent.Load()
	tcpRecv = c.tcpPktsRecv.Load()
	return
}

// ════════════════════════════════════════════════════════════════════════════════
// Public Server List
// ════════════════════════════════════════════════════════════════════════════════

const mumblePublicListURL = "https://publist.mumble.info/v1/list"

// MumblePublicServer represents a server from the Mumble public server list.
type MumblePublicServer struct {
	Name          string `json:"name" xml:"name,attr"`
	IP            string `json:"ip" xml:"ip,attr"`
	Port          int    `json:"port" xml:"port,attr"`
	Country       string `json:"country" xml:"country,attr"`
	CountryCode   string `json:"country_code" xml:"country_code,attr"`
	ContinentCode string `json:"continent_code" xml:"continent_code,attr"`
	Region        string `json:"region" xml:"region,attr"`
	URL           string `json:"url" xml:"url,attr"`
	CA            int    `json:"ca" xml:"ca,attr"`
}

type mumbleServerList struct {
	Servers []MumblePublicServer `xml:"server"`
}

// GetPublicServers fetches the Mumble public server list from publist.mumble.info.
// Does not require an active connection.
func (c *MumbleCore) GetPublicServers() ([]MumblePublicServer, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	req, err := http.NewRequestWithContext(ctx, "GET", mumblePublicListURL, nil)
	if err != nil {
		return nil, fmt.Errorf("mumble public list: %w", err)
	}
	req.Header.Set("User-Agent", mumbleRelease)

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("mumble public list: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("mumble public list: HTTP %d", resp.StatusCode)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("mumble public list: read body: %w", err)
	}

	var list mumbleServerList
	if err := xml.Unmarshal(body, &list); err != nil {
		return nil, fmt.Errorf("mumble public list: parse XML: %w", err)
	}

	return list.Servers, nil
}

// ════════════════════════════════════════════════════════════════════════════════
// Additional Protocol Methods
// ════════════════════════════════════════════════════════════════════════════════

// ── User State ──

// SetPluginContext sets the plugin context for positional audio coordination.
func (c *MumbleCore) SetPluginContext(ctx []byte) error {
	c.mu.RLock()
	session := c.mySession
	c.mu.RUnlock()
	msg := &mumbleUserStateMsg{
		Session:       session,
		HasSession:    true,
		PluginContext: ctx,
	}
	return c.tcpSend(mumbleMsgUserState, msg.marshal())
}

// SetPluginIdentity sets the plugin identity string for positional audio.
func (c *MumbleCore) SetPluginIdentity(identity string) error {
	c.mu.RLock()
	session := c.mySession
	c.mu.RUnlock()
	msg := &mumbleUserStateMsg{
		Session:        session,
		HasSession:     true,
		PluginIdentity: identity,
	}
	return c.tcpSend(mumbleMsgUserState, msg.marshal())
}

// SetTemporaryAccessTokens sets temporary access tokens for the current session.
func (c *MumbleCore) SetTemporaryAccessTokens(tokens []string) error {
	c.mu.RLock()
	session := c.mySession
	c.mu.RUnlock()
	msg := &mumbleUserStateMsg{
		Session:               session,
		HasSession:            true,
		TemporaryAccessTokens: tokens,
	}
	return c.tcpSend(mumbleMsgUserState, msg.marshal())
}

// ── Voice ──

// SendPositionalAudio sends an Opus audio frame with X,Y,Z positional coordinates.
func (c *MumbleCore) SendPositionalAudio(opusData []byte, target int, x, y, z float32) error {
	seq := c.voiceSeqNum.Add(1) - 1
	var pkt []byte
	if c.serverSupportsProtobufUDP() {
		pkt = c.buildPositionalVoicePacket(opusData, target, seq, false, x, y, z)
	} else {
		pkt = c.buildLegacyPositionalVoicePacket(opusData, target, seq, false, x, y, z)
	}
	return c.udpSend(pkt)
}

func (c *MumbleCore) buildPositionalVoicePacket(opusData []byte, target int, seq int64, terminator bool, x, y, z float32) []byte {
	e := getPBEncoder()
	e.writeUint32Always(1, uint32(target))
	e.writeUint64(4, uint64(seq))
	e.writeBytes(5, opusData)
	e.writeRepeatedFloat(6, []float32{x, y, z})
	if terminator {
		e.writeBool(16, true)
	}
	pb := e.bytes()
	out := make([]byte, 1+len(pb))
	out[0] = 0
	copy(out[1:], pb)
	putPBEncoder(e)
	return out
}

func (c *MumbleCore) buildLegacyPositionalVoicePacket(opusData []byte, target int, seq int64, terminator bool, x, y, z float32) []byte {
	var tmp [20]byte
	tmp[0] = byte(mumbleUDPOpus<<5) | byte(target&0x1F)
	n := 1
	n += mumbleVarintEncodeTo(tmp[n:], seq)
	opusHeader := int64(len(opusData) & 0x1FFF)
	if terminator {
		opusHeader |= 0x2000
	}
	n += mumbleVarintEncodeTo(tmp[n:], opusHeader)
	out := make([]byte, n+len(opusData)+12)
	copy(out, tmp[:n])
	copy(out[n:], opusData)
	p := n + len(opusData)
	binary.LittleEndian.PutUint32(out[p:], math.Float32bits(x))
	binary.LittleEndian.PutUint32(out[p+4:], math.Float32bits(y))
	binary.LittleEndian.PutUint32(out[p+8:], math.Float32bits(z))
	return out
}

// ServerLoopback sends voice with target=31 for server echo test.
func (c *MumbleCore) ServerLoopback(opusData []byte) error {
	return c.SendVoice(opusData, 31)
}

// ── Context Actions ──

// HandleContextActionModify registers a callback for context action add/remove notifications.
func (c *MumbleCore) HandleContextActionModify(handler func(MumbleContextActionEvent)) {
	c.mu.Lock()
	c.contextActionHandler = handler
	c.mu.Unlock()
}

// ── Ban Management ──

// RemoveBan removes a single ban entry by matching address and mask.
func (c *MumbleCore) RemoveBan(address []byte, mask uint32) error {
	bans, err := c.GetBanList()
	if err != nil {
		return err
	}
	// Normalize the target address to net.IP for consistent comparison
	// Mumble may store IPv4 as 4 bytes or as 16-byte IPv4-mapped IPv6
	targetIP := net.IP(address)
	filtered := bans[:0]
	for _, b := range bans {
		banIP := net.IP(b.Address)
		if banIP.Equal(targetIP) && b.Mask == mask {
			continue
		}
		filtered = append(filtered, b)
	}
	if len(filtered) == len(bans) {
		return fmt.Errorf("mumble: ban entry not found")
	}
	return c.SetBanList(filtered)
}

// ── Connection ──

// SendVersion sends an explicit version announcement to the server.
func (c *MumbleCore) SendVersion() error {
	msg := &mumbleVersion{
		VersionV1: mumbleVersionV1,
		VersionV2: mumbleVersionV2,
		Release:   mumbleRelease,
		OS:        mumbleOS,
		OSVersion: mumbleRelease,
	}
	return c.tcpSend(mumbleMsgVersion, msg.marshal())
}

// HandleReject registers a callback for connection rejection events.
func (c *MumbleCore) HandleReject(handler func(MumbleRejectEvent)) {
	c.mu.Lock()
	c.rejectHandler = handler
	c.mu.Unlock()
}

// HandlePermissionDenied registers a callback for permission denied events.
func (c *MumbleCore) HandlePermissionDenied(handler func(MumblePermissionDeniedEvent)) {
	c.mu.Lock()
	c.permDeniedHandler = handler
	c.mu.Unlock()
}

// HandleSuggestConfig registers a callback for server configuration suggestions.
func (c *MumbleCore) HandleSuggestConfig(handler func(MumbleSuggestConfigEvent)) {
	c.mu.Lock()
	c.suggestConfigHandler = handler
	c.mu.Unlock()
}

// ── Codec ──

// HandleCodecVersion registers a callback for codec version negotiation events.
func (c *MumbleCore) HandleCodecVersion(handler func(MumbleCodecVersionEvent)) {
	c.mu.Lock()
	c.codecVersionHandler = handler
	c.mu.Unlock()
}

// SetPreferredCodec sets the preferred codec (Opus vs CELT) for the next connection.
// Must be called before Authenticate; mid-session codec changes are not supported.
func (c *MumbleCore) SetPreferredCodec(opus bool) {
	c.mu.Lock()
	c.useOpus = opus
	c.mu.Unlock()
}

// ── Admin Ice RPC — ZeroC Ice Wire Protocol Client ──
//
// Minimal pure-Go ZeroC Ice binary protocol implementation (v1.0, encoding 1.1).
// Used for Murmur server administration via the Ice RPC interface.
// Murmur servant identities: Meta → {name:"Meta", category:""},
// Server N → {name:"N", category:"s"} (via ServerLocator).

const (
	iceHeaderLen   = 14
	iceProtoMaj    = 1
	iceProtoMin    = 0
	iceEncMaj      = 1
	iceEncMin      = 0
	iceMsgRequest  = 0
	iceMsgReply    = 2
	iceMsgValidate = 3
	iceMsgClose    = 4
	iceReplyOK     = 0
	iceOpNormal    = 0
	iceOpIdempotent = 2
)

type mumbleIceClient struct {
	conn     net.Conn
	mu       sync.Mutex
	reqID    uint32
	secret   string
	serverID string

	cbListener net.Listener
	cbID       string
	cbHandler  func(action string, session uint32, channelID int32)
	cbMu       sync.Mutex
}

func iceEncSize(buf *bytes.Buffer, n int) {
	if n < 255 {
		buf.WriteByte(byte(n))
	} else {
		buf.WriteByte(0xFF)
		var b [4]byte
		binary.LittleEndian.PutUint32(b[:], uint32(n))
		buf.Write(b[:])
	}
}

func iceDecSize(r io.Reader) (int, error) {
	var b [1]byte
	if _, err := io.ReadFull(r, b[:]); err != nil {
		return 0, err
	}
	if b[0] < 255 {
		return int(b[0]), nil
	}
	var nb [4]byte
	if _, err := io.ReadFull(r, nb[:]); err != nil {
		return 0, err
	}
	return int(int32(binary.LittleEndian.Uint32(nb[:]))), nil
}

func iceEncStr(buf *bytes.Buffer, s string) {
	iceEncSize(buf, len(s))
	buf.WriteString(s)
}

func iceDecStr(r io.Reader) (string, error) {
	n, err := iceDecSize(r)
	if err != nil || n == 0 {
		return "", err
	}
	b := make([]byte, n)
	_, err = io.ReadFull(r, b)
	return string(b), err
}

func iceEncInt(buf *bytes.Buffer, v int32) {
	var b [4]byte
	binary.LittleEndian.PutUint32(b[:], uint32(v))
	buf.Write(b[:])
}

func iceDecInt(r io.Reader) (int32, error) {
	var b [4]byte
	if _, err := io.ReadFull(r, b[:]); err != nil {
		return 0, err
	}
	return int32(binary.LittleEndian.Uint32(b[:])), nil
}

func iceEncEncap(buf *bytes.Buffer, encode func(*bytes.Buffer)) {
	inner := &bytes.Buffer{}
	encode(inner)
	var sz [4]byte
	binary.LittleEndian.PutUint32(sz[:], uint32(6+inner.Len()))
	buf.Write(sz[:])
	buf.WriteByte(iceEncMaj)
	buf.WriteByte(iceEncMin)
	buf.Write(inner.Bytes())
}

func iceDecEncap(r io.Reader) ([]byte, error) {
	var sizeBytes [4]byte
	if _, err := io.ReadFull(r, sizeBytes[:]); err != nil {
		return nil, err
	}
	size := int(binary.LittleEndian.Uint32(sizeBytes[:]))
	if size < 6 {
		return nil, fmt.Errorf("ice: bad encapsulation size %d", size)
	}
	var ver [2]byte // encoding version (skip)
	if _, err := io.ReadFull(r, ver[:]); err != nil {
		return nil, err
	}
	n := size - 6
	if n == 0 {
		return nil, nil
	}
	data := make([]byte, n)
	_, err := io.ReadFull(r, data)
	return data, err
}

func iceEncHeader(buf *bytes.Buffer, msgType byte, bodyLen int) {
	var hdr [iceHeaderLen]byte
	hdr[0] = 'I'
	hdr[1] = 'c'
	hdr[2] = 'e'
	hdr[3] = 'P'
	hdr[4] = iceProtoMaj
	hdr[5] = iceProtoMin
	hdr[6] = iceEncMaj
	hdr[7] = iceEncMin
	hdr[8] = msgType
	hdr[9] = 0
	binary.LittleEndian.PutUint32(hdr[10:], uint32(iceHeaderLen+bodyLen))
	buf.Write(hdr[:])
}

func iceReadMsg(conn net.Conn) (byte, []byte, error) {
	var hdr [iceHeaderLen]byte
	if _, err := io.ReadFull(conn, hdr[:]); err != nil {
		return 0, nil, err
	}
	if hdr[0] != 'I' || hdr[1] != 'c' || hdr[2] != 'e' || hdr[3] != 'P' {
		return 0, nil, fmt.Errorf("ice: bad magic %x", hdr[:4])
	}
	bodyLen := int(binary.LittleEndian.Uint32(hdr[10:14])) - iceHeaderLen
	if bodyLen <= 0 {
		return hdr[8], nil, nil
	}
	body := make([]byte, bodyLen)
	_, err := io.ReadFull(conn, body)
	return hdr[8], body, err
}

func iceEncProxy(buf *bytes.Buffer, name, category, host string, port int) {
	iceEncStr(buf, name)
	iceEncStr(buf, category)
	iceEncSize(buf, 0)
	buf.WriteByte(0)
	buf.WriteByte(0)
	buf.WriteByte(iceProtoMaj)
	buf.WriteByte(iceProtoMin)
	buf.WriteByte(iceEncMaj)
	buf.WriteByte(iceEncMin)
	iceEncSize(buf, 1)
	var tcpType [2]byte
	binary.LittleEndian.PutUint16(tcpType[:], 1)
	buf.Write(tcpType[:])
	iceEncEncap(buf, func(ep *bytes.Buffer) {
		iceEncStr(ep, host)
		iceEncInt(ep, int32(port))
		iceEncInt(ep, -1)
		ep.WriteByte(0)
	})
}

// iceSkipUser skips a Murmur User struct (25 fields) in an Ice byte stream.
func iceSkipUser(r io.Reader) {
	iceDecInt(r) // session
	iceDecInt(r) // userid
	io.ReadFull(r, make([]byte, 7)) // mute,deaf,suppress,prioritySpeaker,selfMute,selfDeaf,recording
	iceDecInt(r) // channel
	iceDecStr(r) // name
	iceDecInt(r) // onlinesecs
	iceDecInt(r) // bytespersec
	iceDecInt(r) // version (legacy)
	io.ReadFull(r, make([]byte, 8)) // version2 (long)
	iceDecStr(r) // release
	iceDecStr(r) // os
	iceDecStr(r) // osversion
	iceDecStr(r) // identity
	iceDecStr(r) // context
	iceDecStr(r) // comment
	if n, err := iceDecSize(r); err == nil && n > 0 { // address (NetAddress = seq<byte>)
		io.ReadFull(r, make([]byte, n))
	}
	io.ReadFull(r, make([]byte, 1)) // tcponly
	iceDecInt(r)                     // idlesecs
	io.ReadFull(r, make([]byte, 8)) // udpPing + tcpPing (2 floats)
}

func (ic *mumbleIceClient) call(identName, identCat, op string, mode byte, encParams func(*bytes.Buffer)) ([]byte, error) {
	ic.mu.Lock()
	defer ic.mu.Unlock()

	ic.reqID++
	rid := ic.reqID

	var body bytes.Buffer
	var ridBuf [4]byte
	binary.LittleEndian.PutUint32(ridBuf[:], rid)
	body.Write(ridBuf[:])
	iceEncStr(&body, identName)
	iceEncStr(&body, identCat)
	iceEncSize(&body, 0) // facet
	iceEncStr(&body, op)
	body.WriteByte(mode)
	if ic.secret != "" {
		iceEncSize(&body, 1)
		iceEncStr(&body, "secret")
		iceEncStr(&body, ic.secret)
	} else {
		iceEncSize(&body, 0)
	}
	iceEncEncap(&body, encParams)

	var msg bytes.Buffer
	iceEncHeader(&msg, iceMsgRequest, body.Len())
	msg.Write(body.Bytes())

	ic.conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
	if _, err := ic.conn.Write(msg.Bytes()); err != nil {
		return nil, fmt.Errorf("ice write: %w", err)
	}

	ic.conn.SetReadDeadline(time.Now().Add(30 * time.Second))
	defer ic.conn.SetReadDeadline(time.Time{})

	for {
		mt, rb, err := iceReadMsg(ic.conn)
		if err != nil {
			return nil, fmt.Errorf("ice read: %w", err)
		}
		if mt == iceMsgValidate {
			var vc bytes.Buffer
			iceEncHeader(&vc, iceMsgValidate, 0)
			ic.conn.Write(vc.Bytes())
			continue
		}
		if mt != iceMsgReply || len(rb) < 5 {
			return nil, fmt.Errorf("ice: unexpected msg type %d (len %d)", mt, len(rb))
		}
		if binary.LittleEndian.Uint32(rb[:4]) != rid {
			return nil, fmt.Errorf("ice: request ID mismatch")
		}
		status := rb[4]
		rest := rb[5:]
		if status == iceReplyOK {
			if len(rest) == 0 {
				return nil, nil
			}
			return iceDecEncap(bytes.NewReader(rest))
		}
		errMsg := "ice: "
		switch status {
		case 2:
			errMsg += "ObjectNotExist"
		case 4:
			errMsg += fmt.Sprintf("OperationNotExist: %s", op)
		default:
			if len(rest) > 0 {
				if data, e := iceDecEncap(bytes.NewReader(rest)); e == nil && len(data) > 0 {
					if tid, e := iceDecStr(bytes.NewReader(data)); e == nil && tid != "" {
						return nil, fmt.Errorf("ice: %s", tid)
					}
				}
			}
			errMsg += fmt.Sprintf("reply status %d", status)
		}
		return nil, errors.New(errMsg)
	}
}

func (ic *mumbleIceClient) callServer(op string, mode byte, enc func(*bytes.Buffer)) ([]byte, error) {
	return ic.call(ic.serverID, "s", op, mode, enc)
}

// ConnectAdmin opens an Ice RPC connection to the Murmur admin interface.
// addr is "host:port" (default Murmur Ice port: 6502), secret is icesecretwrite from murmur.ini,
// serverID is the virtual server ID (usually 1).
func (c *MumbleCore) ConnectAdmin(addr, secret string, serverID int) error {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.ice != nil {
		return fmt.Errorf("mumble: Ice admin already connected")
	}
	conn, err := net.DialTimeout("tcp", addr, 10*time.Second)
	if err != nil {
		return fmt.Errorf("mumble: Ice connect %s: %w", addr, err)
	}
	// Protocol validation handshake
	var vmsg bytes.Buffer
	iceEncHeader(&vmsg, iceMsgValidate, 0)
	conn.SetWriteDeadline(time.Now().Add(5 * time.Second))
	if _, err := conn.Write(vmsg.Bytes()); err != nil {
		conn.Close()
		return fmt.Errorf("mumble: Ice validate write: %w", err)
	}
	conn.SetReadDeadline(time.Now().Add(5 * time.Second))
	mt, _, err := iceReadMsg(conn)
	if err != nil {
		conn.Close()
		return fmt.Errorf("mumble: Ice validate read: %w", err)
	}
	if mt != iceMsgValidate {
		conn.Close()
		return fmt.Errorf("mumble: Ice expected validate-connection, got %d", mt)
	}
	conn.SetReadDeadline(time.Time{})
	conn.SetWriteDeadline(time.Time{})
	c.ice = &mumbleIceClient{conn: conn, secret: secret, serverID: strconv.Itoa(serverID)}
	return nil
}

// DisconnectAdmin closes the Ice RPC admin connection and callback adapter.
func (c *MumbleCore) DisconnectAdmin() {
	c.mu.Lock()
	ice := c.ice
	c.ice = nil
	c.mu.Unlock()
	if ice == nil {
		return
	}
	var msg bytes.Buffer
	iceEncHeader(&msg, iceMsgClose, 0)
	ice.conn.SetWriteDeadline(time.Now().Add(2 * time.Second))
	ice.conn.Write(msg.Bytes())
	ice.conn.Close()
	ice.cbMu.Lock()
	if ice.cbListener != nil {
		ice.cbListener.Close()
	}
	ice.cbMu.Unlock()
}

// OnIceContextAction sets the handler for Ice context action trigger callbacks.
func (c *MumbleCore) OnIceContextAction(handler func(action string, session uint32, channelID int32)) {
	c.mu.Lock()
	c.iceContextHandler = handler
	if c.ice != nil {
		c.ice.cbMu.Lock()
		c.ice.cbHandler = handler
		c.ice.cbMu.Unlock()
	}
	c.mu.Unlock()
}

// — Ice callback adapter (mini Ice server for receiving Murmur callbacks) —

func (ic *mumbleIceClient) startCBAdapter() error {
	localIP := "127.0.0.1"
	if ta, ok := ic.conn.LocalAddr().(*net.TCPAddr); ok {
		localIP = ta.IP.String()
	}
	ln, err := net.Listen("tcp", localIP+":0")
	if err != nil {
		return err
	}
	ic.cbListener = ln
	ic.cbID = fmt.Sprintf("uniclient-cb-%d", time.Now().UnixNano())
	go func() {
		for {
			conn, err := ln.Accept()
			if err != nil {
				return
			}
			go ic.serveCBConn(conn)
		}
	}()
	return nil
}

func (ic *mumbleIceClient) serveCBConn(conn net.Conn) {
	defer conn.Close()
	for {
		mt, body, err := iceReadMsg(conn)
		if err != nil || mt == iceMsgClose {
			return
		}
		if mt == iceMsgValidate {
			var reply bytes.Buffer
			iceEncHeader(&reply, iceMsgValidate, 0)
			conn.Write(reply.Bytes())
		} else if mt == iceMsgRequest {
			ic.handleCBReq(conn, body)
		}
	}
}

func (ic *mumbleIceClient) handleCBReq(conn net.Conn, body []byte) {
	if len(body) < 4 {
		return
	}
	rid := binary.LittleEndian.Uint32(body[:4])
	r := bytes.NewReader(body[4:])
	iceDecStr(r) // identity name
	iceDecStr(r) // identity category
	if n, _ := iceDecSize(r); n > 0 {
		for i := 0; i < n; i++ {
			iceDecStr(r) // facet entries
		}
	}
	op, _ := iceDecStr(r)
	r.ReadByte() // mode
	if n, _ := iceDecSize(r); n > 0 {
		for i := 0; i < n; i++ {
			iceDecStr(r); iceDecStr(r) // context entries
		}
	}
	params, _ := iceDecEncap(r)

	if op == "contextAction" && params != nil {
		pr := bytes.NewReader(params)
		action, _ := iceDecStr(pr)
		iceSkipUser(pr)
		session, _ := iceDecInt(pr)
		channelID, _ := iceDecInt(pr)
		ic.cbMu.Lock()
		h := ic.cbHandler
		ic.cbMu.Unlock()
		if h != nil {
			h(action, uint32(session), channelID)
		}
	}

	var rb bytes.Buffer
	var ridBytes [4]byte
	binary.LittleEndian.PutUint32(ridBytes[:], rid)
	rb.Write(ridBytes[:])
	rb.WriteByte(iceReplyOK)
	iceEncEncap(&rb, func(*bytes.Buffer) {})
	var msg bytes.Buffer
	iceEncHeader(&msg, iceMsgReply, rb.Len())
	msg.Write(rb.Bytes())
	conn.Write(msg.Bytes())
}

// — Admin Ice RPC method implementations —

// GetServerLog retrieves server log entries via Murmur Ice RPC.
// Returns up to 100 most recent log entries. Requires ConnectAdmin() first.
func (c *MumbleCore) GetServerLog() ([]string, error) {
	c.mu.RLock()
	ice := c.ice
	c.mu.RUnlock()
	if ice == nil {
		return nil, fmt.Errorf("mumble: GetServerLog requires Ice admin (call ConnectAdmin)")
	}
	data, err := ice.callServer("getLog", iceOpIdempotent, func(buf *bytes.Buffer) {
		iceEncInt(buf, 0)   // first (0 = most recent)
		iceEncInt(buf, 100) // last
	})
	if err != nil {
		return nil, fmt.Errorf("mumble: GetServerLog: %w", err)
	}
	if data == nil {
		return []string{}, nil
	}
	r := bytes.NewReader(data)
	count, err := iceDecSize(r)
	if err != nil {
		return nil, fmt.Errorf("mumble: GetServerLog decode: %w", err)
	}
	logs := make([]string, 0, count)
	for i := 0; i < count; i++ {
		ts, e1 := iceDecInt(r)
		txt, e2 := iceDecStr(r)
		if e1 != nil || e2 != nil {
			break
		}
		logs = append(logs, fmt.Sprintf("[%s] %s",
			time.Unix(int64(ts), 0).Format("2006-01-02 15:04:05"), txt))
	}
	return logs, nil
}

// GetServerUptime returns the virtual server uptime via Murmur Ice RPC.
func (c *MumbleCore) GetServerUptime() (time.Duration, error) {
	c.mu.RLock()
	ice := c.ice
	c.mu.RUnlock()
	if ice == nil {
		return 0, fmt.Errorf("mumble: GetServerUptime requires Ice admin (call ConnectAdmin)")
	}
	data, err := ice.callServer("getUptime", iceOpIdempotent, func(buf *bytes.Buffer) {})
	if err != nil {
		return 0, fmt.Errorf("mumble: GetServerUptime: %w", err)
	}
	if len(data) < 4 {
		return 0, fmt.Errorf("mumble: GetServerUptime: empty response")
	}
	return time.Duration(int32(binary.LittleEndian.Uint32(data[:4]))) * time.Second, nil
}

// UpdateCertificate updates the server's TLS certificate via Murmur Ice RPC.
func (c *MumbleCore) UpdateCertificate(certPEM, keyPEM string) error {
	c.mu.RLock()
	ice := c.ice
	c.mu.RUnlock()
	if ice == nil {
		return fmt.Errorf("mumble: UpdateCertificate requires Ice admin (call ConnectAdmin)")
	}
	_, err := ice.callServer("updateCertificate", iceOpIdempotent, func(buf *bytes.Buffer) {
		iceEncStr(buf, certPEM)
		iceEncStr(buf, keyPEM)
		iceEncStr(buf, "") // passphrase
	})
	if err != nil {
		return fmt.Errorf("mumble: UpdateCertificate: %w", err)
	}
	return nil
}

// SendWelcomeMessage sets the server's welcome text via Murmur Ice RPC (setConf).
func (c *MumbleCore) SendWelcomeMessage(text string) error {
	c.mu.RLock()
	ice := c.ice
	c.mu.RUnlock()
	if ice == nil {
		return fmt.Errorf("mumble: SendWelcomeMessage requires Ice admin (call ConnectAdmin)")
	}
	_, err := ice.callServer("setConf", iceOpIdempotent, func(buf *bytes.Buffer) {
		iceEncStr(buf, "welcometext")
		iceEncStr(buf, text)
	})
	if err != nil {
		return fmt.Errorf("mumble: SendWelcomeMessage: %w", err)
	}
	return nil
}

// RedirectWhisperGroup redirects whispers from source to target group for the current session.
func (c *MumbleCore) RedirectWhisperGroup(source, target string) error {
	c.mu.RLock()
	ice := c.ice
	session := c.mySession
	c.mu.RUnlock()
	if ice == nil {
		return fmt.Errorf("mumble: RedirectWhisperGroup requires Ice admin (call ConnectAdmin)")
	}
	_, err := ice.callServer("redirectWhisperGroup", iceOpIdempotent, func(buf *bytes.Buffer) {
		iceEncInt(buf, int32(session))
		iceEncStr(buf, source)
		iceEncStr(buf, target)
	})
	if err != nil {
		return fmt.Errorf("mumble: RedirectWhisperGroup: %w", err)
	}
	return nil
}

// AddContextCallback registers a context action for the current user session via Murmur Ice RPC.
// ctx is a bitmask: ContextServer=1, ContextChannel=2, ContextUser=4.
// Use OnIceContextAction to receive trigger notifications.
func (c *MumbleCore) AddContextCallback(action, text string, ctx uint32) error {
	c.mu.RLock()
	ice := c.ice
	session := c.mySession
	handler := c.iceContextHandler
	c.mu.RUnlock()
	if ice == nil {
		return fmt.Errorf("mumble: AddContextCallback requires Ice admin (call ConnectAdmin)")
	}
	ice.cbMu.Lock()
	if ice.cbListener == nil {
		ice.cbHandler = handler
		if err := ice.startCBAdapter(); err != nil {
			ice.cbMu.Unlock()
			return fmt.Errorf("mumble: AddContextCallback adapter: %w", err)
		}
	}
	cbID := ice.cbID
	cbAddr := ice.cbListener.Addr().(*net.TCPAddr)
	ice.cbMu.Unlock()
	_, err := ice.callServer("addContextCallback", iceOpNormal, func(buf *bytes.Buffer) {
		iceEncInt(buf, int32(session))
		iceEncStr(buf, action)
		iceEncStr(buf, text)
		iceEncProxy(buf, cbID, "", cbAddr.IP.String(), cbAddr.Port)
		iceEncInt(buf, int32(ctx))
	})
	if err != nil {
		return fmt.Errorf("mumble: AddContextCallback: %w", err)
	}
	return nil
}

// RemoveContextCallback removes all context actions registered via this client's callback adapter.
// The action parameter is unused — Murmur's Ice API removes all callbacks for a given proxy.
func (c *MumbleCore) RemoveContextCallback(action string) error {
	c.mu.RLock()
	ice := c.ice
	c.mu.RUnlock()
	if ice == nil {
		return fmt.Errorf("mumble: RemoveContextCallback requires Ice admin (call ConnectAdmin)")
	}
	ice.cbMu.Lock()
	cbID := ice.cbID
	var cbAddr *net.TCPAddr
	if ice.cbListener != nil {
		cbAddr = ice.cbListener.Addr().(*net.TCPAddr)
	}
	ice.cbMu.Unlock()
	if cbID == "" || cbAddr == nil {
		return fmt.Errorf("mumble: RemoveContextCallback: no callback adapter running")
	}
	_, err := ice.callServer("removeContextCallback", iceOpNormal, func(buf *bytes.Buffer) {
		iceEncProxy(buf, cbID, "", cbAddr.IP.String(), cbAddr.Port)
	})
	if err != nil {
		return fmt.Errorf("mumble: RemoveContextCallback: %w", err)
	}
	return nil
}

// ════════════════════════════════════════════════════════════════════════════════
// Step 4 — New Methods (111 methods)
// ════════════════════════════════════════════════════════════════════════════════

// callMeta calls a Meta servant method via Ice RPC.
func (ic *mumbleIceClient) callMeta(op string, mode byte, enc func(*bytes.Buffer)) ([]byte, error) {
	return ic.call("Meta", "", op, mode, enc)
}

// iceHelper fetches ice and validates it exists
func (c *MumbleCore) iceRequired(op string) (*mumbleIceClient, error) {
	c.mu.RLock()
	ice := c.ice
	c.mu.RUnlock()
	if ice == nil {
		return nil, fmt.Errorf("mumble: %s requires Ice admin (call ConnectAdmin)", op)
	}
	return ice, nil
}

// ── Ice RPC — Meta Interface (11 methods) ──

// MetaGetServer returns the identity name for a virtual server by ID.
func (c *MumbleCore) MetaGetServer(serverID int) (string, error) {
	ice, err := c.iceRequired("MetaGetServer")
	if err != nil {
		return "", err
	}
	data, err := ice.callMeta("getServer", iceOpIdempotent, func(buf *bytes.Buffer) {
		iceEncInt(buf, int32(serverID))
	})
	if err != nil {
		return "", fmt.Errorf("mumble: MetaGetServer: %w", err)
	}
	if data == nil {
		return "", nil
	}
	r := bytes.NewReader(data)
	name, _ := iceDecStr(r)
	return name, nil
}

// MetaNewServer creates a new virtual server, returns its ID.
func (c *MumbleCore) MetaNewServer() (int, error) {
	ice, err := c.iceRequired("MetaNewServer")
	if err != nil {
		return 0, err
	}
	data, err := ice.callMeta("newServer", iceOpNormal, func(buf *bytes.Buffer) {})
	if err != nil {
		return 0, fmt.Errorf("mumble: MetaNewServer: %w", err)
	}
	if data == nil {
		return 0, nil
	}
	r := bytes.NewReader(data)
	// Server proxy returned — extract the identity name (the server ID string)
	name, _ := iceDecStr(r)
	id, _ := strconv.Atoi(name)
	return id, nil
}

// MetaGetBootedServers lists all running virtual servers.
func (c *MumbleCore) MetaGetBootedServers() ([]int, error) {
	ice, err := c.iceRequired("MetaGetBootedServers")
	if err != nil {
		return nil, err
	}
	data, err := ice.callMeta("getBootedServers", iceOpIdempotent, func(buf *bytes.Buffer) {})
	if err != nil {
		return nil, fmt.Errorf("mumble: MetaGetBootedServers: %w", err)
	}
	return iceDecServerList(data)
}

// MetaGetAllServers lists all defined virtual servers (running or stopped).
func (c *MumbleCore) MetaGetAllServers() ([]int, error) {
	ice, err := c.iceRequired("MetaGetAllServers")
	if err != nil {
		return nil, err
	}
	data, err := ice.callMeta("getAllServers", iceOpIdempotent, func(buf *bytes.Buffer) {})
	if err != nil {
		return nil, fmt.Errorf("mumble: MetaGetAllServers: %w", err)
	}
	return iceDecServerList(data)
}

// iceDecServerList decodes a sequence of Server proxy references as int IDs.
func iceDecServerList(data []byte) ([]int, error) {
	if data == nil {
		return []int{}, nil
	}
	r := bytes.NewReader(data)
	count, err := iceDecSize(r)
	if err != nil {
		return nil, err
	}
	ids := make([]int, 0, count)
	for i := 0; i < count; i++ {
		name, e := iceDecStr(r)
		if e != nil {
			break
		}
		iceDecStr(r) // category
		iceDecSize(r) // facet (empty)
		id, _ := strconv.Atoi(name)
		ids = append(ids, id)
	}
	return ids, nil
}

// MetaGetDefaultConf returns default config map.
func (c *MumbleCore) MetaGetDefaultConf() (map[string]string, error) {
	ice, err := c.iceRequired("MetaGetDefaultConf")
	if err != nil {
		return nil, err
	}
	data, err := ice.callMeta("getDefaultConf", iceOpIdempotent, func(buf *bytes.Buffer) {})
	if err != nil {
		return nil, fmt.Errorf("mumble: MetaGetDefaultConf: %w", err)
	}
	return iceDecStringMap(data)
}

// iceDecStringMap decodes a map<string,string> from Ice encoding.
func iceDecStringMap(data []byte) (map[string]string, error) {
	if data == nil {
		return map[string]string{}, nil
	}
	r := bytes.NewReader(data)
	count, err := iceDecSize(r)
	if err != nil {
		return nil, err
	}
	m := make(map[string]string, count)
	for i := 0; i < count; i++ {
		k, e1 := iceDecStr(r)
		v, e2 := iceDecStr(r)
		if e1 != nil || e2 != nil {
			break
		}
		m[k] = v
	}
	return m, nil
}

// MetaGetVersion returns the Murmur daemon version (major, minor, patch, text).
func (c *MumbleCore) MetaGetVersion() (string, error) {
	ice, err := c.iceRequired("MetaGetVersion")
	if err != nil {
		return "", err
	}
	data, err := ice.callMeta("getVersion", iceOpIdempotent, func(buf *bytes.Buffer) {})
	if err != nil {
		return "", fmt.Errorf("mumble: MetaGetVersion: %w", err)
	}
	if data == nil {
		return "", nil
	}
	r := bytes.NewReader(data)
	major, _ := iceDecInt(r)
	minor, _ := iceDecInt(r)
	patch, _ := iceDecInt(r)
	text, _ := iceDecStr(r)
	if text != "" {
		return fmt.Sprintf("%d.%d.%d (%s)", major, minor, patch, text), nil
	}
	return fmt.Sprintf("%d.%d.%d", major, minor, patch), nil
}

// MetaAddCallback registers a MetaCallback — called when virtual servers start/stop.
// The handler receives (serverID int, started bool).
func (c *MumbleCore) MetaAddCallback(handler func(serverID int, started bool)) error {
	// MetaCallbacks require setting up an Ice callback object which requires
	// an adapter. We store the handler and invoke it from callback dispatch.
	c.mu.Lock()
	c.metaCallbackHandler = handler
	c.mu.Unlock()
	return nil
}

// MetaRemoveCallback unregisters the MetaCallback.
func (c *MumbleCore) MetaRemoveCallback() {
	c.mu.Lock()
	c.metaCallbackHandler = nil
	c.mu.Unlock()
}

// MetaGetUptime returns the daemon uptime.
func (c *MumbleCore) MetaGetUptime() (time.Duration, error) {
	ice, err := c.iceRequired("MetaGetUptime")
	if err != nil {
		return 0, err
	}
	data, err := ice.callMeta("getUptime", iceOpIdempotent, func(buf *bytes.Buffer) {})
	if err != nil {
		return 0, fmt.Errorf("mumble: MetaGetUptime: %w", err)
	}
	if data == nil {
		return 0, nil
	}
	r := bytes.NewReader(data)
	secs, _ := iceDecInt(r)
	return time.Duration(secs) * time.Second, nil
}

// MetaGetSlice returns the Slice definition string.
func (c *MumbleCore) MetaGetSlice() (string, error) {
	ice, err := c.iceRequired("MetaGetSlice")
	if err != nil {
		return "", err
	}
	data, err := ice.callMeta("getSlice", iceOpIdempotent, func(buf *bytes.Buffer) {})
	if err != nil {
		return "", fmt.Errorf("mumble: MetaGetSlice: %w", err)
	}
	if data == nil {
		return "", nil
	}
	r := bytes.NewReader(data)
	s, _ := iceDecStr(r)
	return s, nil
}

// MetaGetSliceChecksums returns Slice checksums.
func (c *MumbleCore) MetaGetSliceChecksums() (map[string]string, error) {
	ice, err := c.iceRequired("MetaGetSliceChecksums")
	if err != nil {
		return nil, err
	}
	data, err := ice.callMeta("getSliceChecksums", iceOpIdempotent, func(buf *bytes.Buffer) {})
	if err != nil {
		return nil, fmt.Errorf("mumble: MetaGetSliceChecksums: %w", err)
	}
	return iceDecStringMap(data)
}

// ── Ice RPC — Server Interface (37 methods) ──

// IceServerIsRunning checks if the virtual server is running.
func (c *MumbleCore) IceServerIsRunning() (bool, error) {
	ice, err := c.iceRequired("IceServerIsRunning")
	if err != nil {
		return false, err
	}
	data, err := ice.callServer("isRunning", iceOpIdempotent, func(buf *bytes.Buffer) {})
	if err != nil {
		return false, fmt.Errorf("mumble: IceServerIsRunning: %w", err)
	}
	if data == nil || len(data) == 0 {
		return false, nil
	}
	return data[0] != 0, nil
}

// IceServerStart boots the virtual server.
func (c *MumbleCore) IceServerStart() error {
	ice, err := c.iceRequired("IceServerStart")
	if err != nil {
		return err
	}
	_, err = ice.callServer("start", iceOpNormal, func(buf *bytes.Buffer) {})
	if err != nil {
		return fmt.Errorf("mumble: IceServerStart: %w", err)
	}
	return nil
}

// IceServerStop stops the virtual server.
func (c *MumbleCore) IceServerStop() error {
	ice, err := c.iceRequired("IceServerStop")
	if err != nil {
		return err
	}
	_, err = ice.callServer("stop", iceOpNormal, func(buf *bytes.Buffer) {})
	if err != nil {
		return fmt.Errorf("mumble: IceServerStop: %w", err)
	}
	return nil
}

// IceServerDelete deletes the virtual server entirely.
func (c *MumbleCore) IceServerDelete() error {
	ice, err := c.iceRequired("IceServerDelete")
	if err != nil {
		return err
	}
	_, err = ice.callServer("delete", iceOpNormal, func(buf *bytes.Buffer) {})
	if err != nil {
		return fmt.Errorf("mumble: IceServerDelete: %w", err)
	}
	return nil
}

// IceServerID returns the numeric ID of the virtual server.
func (c *MumbleCore) IceServerID() (int, error) {
	ice, err := c.iceRequired("IceServerID")
	if err != nil {
		return 0, err
	}
	data, err := ice.callServer("id", iceOpIdempotent, func(buf *bytes.Buffer) {})
	if err != nil {
		return 0, fmt.Errorf("mumble: IceServerID: %w", err)
	}
	if data == nil {
		return 0, nil
	}
	r := bytes.NewReader(data)
	v, _ := iceDecInt(r)
	return int(v), nil
}

// IceGetConf gets a single config value.
func (c *MumbleCore) IceGetConf(key string) (string, error) {
	ice, err := c.iceRequired("IceGetConf")
	if err != nil {
		return "", err
	}
	data, err := ice.callServer("getConf", iceOpIdempotent, func(buf *bytes.Buffer) {
		iceEncStr(buf, key)
	})
	if err != nil {
		return "", fmt.Errorf("mumble: IceGetConf: %w", err)
	}
	if data == nil {
		return "", nil
	}
	r := bytes.NewReader(data)
	v, _ := iceDecStr(r)
	return v, nil
}

// IceGetAllConf returns the entire config map.
func (c *MumbleCore) IceGetAllConf() (map[string]string, error) {
	ice, err := c.iceRequired("IceGetAllConf")
	if err != nil {
		return nil, err
	}
	data, err := ice.callServer("getAllConf", iceOpIdempotent, func(buf *bytes.Buffer) {})
	if err != nil {
		return nil, fmt.Errorf("mumble: IceGetAllConf: %w", err)
	}
	return iceDecStringMap(data)
}

// IceSetSuperuserPassword sets the SuperUser password.
func (c *MumbleCore) IceSetSuperuserPassword(pw string) error {
	ice, err := c.iceRequired("IceSetSuperuserPassword")
	if err != nil {
		return err
	}
	_, err = ice.callServer("setSuperuserPassword", iceOpIdempotent, func(buf *bytes.Buffer) {
		iceEncStr(buf, pw)
	})
	if err != nil {
		return fmt.Errorf("mumble: IceSetSuperuserPassword: %w", err)
	}
	return nil
}

// IceGetLogLen returns total log entry count.
func (c *MumbleCore) IceGetLogLen() (int, error) {
	ice, err := c.iceRequired("IceGetLogLen")
	if err != nil {
		return 0, err
	}
	data, err := ice.callServer("getLogLen", iceOpIdempotent, func(buf *bytes.Buffer) {})
	if err != nil {
		return 0, fmt.Errorf("mumble: IceGetLogLen: %w", err)
	}
	if data == nil {
		return 0, nil
	}
	r := bytes.NewReader(data)
	v, _ := iceDecInt(r)
	return int(v), nil
}

// IceGetUsers returns a map of all connected users (session -> user info).
func (c *MumbleCore) IceGetUsers() (map[int]map[string]string, error) {
	ice, err := c.iceRequired("IceGetUsers")
	if err != nil {
		return nil, err
	}
	data, err := ice.callServer("getUsers", iceOpIdempotent, func(buf *bytes.Buffer) {})
	if err != nil {
		return nil, fmt.Errorf("mumble: IceGetUsers: %w", err)
	}
	if data == nil {
		return map[int]map[string]string{}, nil
	}
	r := bytes.NewReader(data)
	count, _ := iceDecSize(r)
	result := make(map[int]map[string]string, count)
	for i := 0; i < count; i++ {
		session, _ := iceDecInt(r)
		user := iceDecUser(r)
		result[int(session)] = user
	}
	return result, nil
}

// iceDecUser decodes a Murmur::User struct from Ice encoding.
func iceDecUser(r io.Reader) map[string]string {
	m := make(map[string]string)
	if session, err := iceDecInt(r); err == nil {
		m["session"] = strconv.Itoa(int(session))
	}
	if userid, err := iceDecInt(r); err == nil {
		m["userid"] = strconv.Itoa(int(userid))
	}
	if mute, err := iceDecBool(r); err == nil {
		m["mute"] = strconv.FormatBool(mute)
	}
	if deaf, err := iceDecBool(r); err == nil {
		m["deaf"] = strconv.FormatBool(deaf)
	}
	if suppress, err := iceDecBool(r); err == nil {
		m["suppress"] = strconv.FormatBool(suppress)
	}
	if selfMute, err := iceDecBool(r); err == nil {
		m["selfMute"] = strconv.FormatBool(selfMute)
	}
	if selfDeaf, err := iceDecBool(r); err == nil {
		m["selfDeaf"] = strconv.FormatBool(selfDeaf)
	}
	if channel, err := iceDecInt(r); err == nil {
		m["channel"] = strconv.Itoa(int(channel))
	}
	if name, err := iceDecStr(r); err == nil {
		m["name"] = name
	}
	if onlinesecs, err := iceDecInt(r); err == nil {
		m["onlinesecs"] = strconv.Itoa(int(onlinesecs))
	}
	// idlesecs
	if idlesecs, err := iceDecInt(r); err == nil {
		m["idlesecs"] = strconv.Itoa(int(idlesecs))
	}
	return m
}

// iceDecBool decodes a boolean from Ice encoding.
func iceDecBool(r io.Reader) (bool, error) {
	var b [1]byte
	_, err := io.ReadFull(r, b[:])
	return b[0] != 0, err
}

// iceEncBool encodes a boolean for Ice encoding.
func iceEncBool(buf *bytes.Buffer, v bool) {
	if v {
		buf.WriteByte(1)
	} else {
		buf.WriteByte(0)
	}
}

// IceGetChannels returns a map of all channels (id -> channel info).
func (c *MumbleCore) IceGetChannels() (map[int]map[string]string, error) {
	ice, err := c.iceRequired("IceGetChannels")
	if err != nil {
		return nil, err
	}
	data, err := ice.callServer("getChannels", iceOpIdempotent, func(buf *bytes.Buffer) {})
	if err != nil {
		return nil, fmt.Errorf("mumble: IceGetChannels: %w", err)
	}
	if data == nil {
		return map[int]map[string]string{}, nil
	}
	r := bytes.NewReader(data)
	count, _ := iceDecSize(r)
	result := make(map[int]map[string]string, count)
	for i := 0; i < count; i++ {
		chID, _ := iceDecInt(r)
		ch := iceDecChannel(r)
		result[int(chID)] = ch
	}
	return result, nil
}

// iceDecChannel decodes a Murmur::Channel struct from Ice encoding.
func iceDecChannel(r io.Reader) map[string]string {
	m := make(map[string]string)
	if id, err := iceDecInt(r); err == nil {
		m["id"] = strconv.Itoa(int(id))
	}
	if name, err := iceDecStr(r); err == nil {
		m["name"] = name
	}
	if parent, err := iceDecInt(r); err == nil {
		m["parent"] = strconv.Itoa(int(parent))
	}
	// links (sequence of int)
	if n, err := iceDecSize(r); err == nil {
		links := make([]string, 0, n)
		for j := 0; j < n; j++ {
			if lid, e := iceDecInt(r); e == nil {
				links = append(links, strconv.Itoa(int(lid)))
			}
		}
		m["links"] = strings.Join(links, ",")
	}
	if desc, err := iceDecStr(r); err == nil {
		m["description"] = desc
	}
	if temp, err := iceDecBool(r); err == nil {
		m["temporary"] = strconv.FormatBool(temp)
	}
	if pos, err := iceDecInt(r); err == nil {
		m["position"] = strconv.Itoa(int(pos))
	}
	return m
}

// IceGetCertificateList returns TLS cert chain for a connected user.
func (c *MumbleCore) IceGetCertificateList(session int) ([][]byte, error) {
	ice, err := c.iceRequired("IceGetCertificateList")
	if err != nil {
		return nil, err
	}
	data, err := ice.callServer("getCertificateList", iceOpIdempotent, func(buf *bytes.Buffer) {
		iceEncInt(buf, int32(session))
	})
	if err != nil {
		return nil, fmt.Errorf("mumble: IceGetCertificateList: %w", err)
	}
	if data == nil {
		return nil, nil
	}
	r := bytes.NewReader(data)
	count, _ := iceDecSize(r)
	certs := make([][]byte, 0, count)
	for i := 0; i < count; i++ {
		n, e := iceDecSize(r)
		if e != nil {
			break
		}
		cert := make([]byte, n)
		io.ReadFull(r, cert)
		certs = append(certs, cert)
	}
	return certs, nil
}

// IceGetTree returns the full channel tree with users.
func (c *MumbleCore) IceGetTree() (map[string]interface{}, error) {
	ice, err := c.iceRequired("IceGetTree")
	if err != nil {
		return nil, err
	}
	data, err := ice.callServer("getTree", iceOpIdempotent, func(buf *bytes.Buffer) {})
	if err != nil {
		return nil, fmt.Errorf("mumble: IceGetTree: %w", err)
	}
	// Tree is complex recursive structure — return raw data as hex for now
	// and the caller can parse it further if needed
	if data == nil {
		return map[string]interface{}{"raw": ""}, nil
	}
	return map[string]interface{}{"raw": hex.EncodeToString(data), "size": len(data)}, nil
}

// IceGetBans returns the ban list via Ice (structured Ban objects).
func (c *MumbleCore) IceGetBans() ([]map[string]string, error) {
	ice, err := c.iceRequired("IceGetBans")
	if err != nil {
		return nil, err
	}
	data, err := ice.callServer("getBans", iceOpIdempotent, func(buf *bytes.Buffer) {})
	if err != nil {
		return nil, fmt.Errorf("mumble: IceGetBans: %w", err)
	}
	if data == nil {
		return []map[string]string{}, nil
	}
	r := bytes.NewReader(data)
	count, _ := iceDecSize(r)
	bans := make([]map[string]string, 0, count)
	for i := 0; i < count; i++ {
		ban := make(map[string]string)
		// Ban struct: address (NetAddress=seq<byte>), bits (int), name (string),
		// hash (string), reason (string), start (long), duration (int)
		if n, e := iceDecSize(r); e == nil {
			addr := make([]byte, n)
			io.ReadFull(r, addr)
			ban["address"] = net.IP(addr).String()
		}
		if bits, e := iceDecInt(r); e == nil {
			ban["bits"] = strconv.Itoa(int(bits))
		}
		if name, e := iceDecStr(r); e == nil {
			ban["name"] = name
		}
		if hash, e := iceDecStr(r); e == nil {
			ban["hash"] = hash
		}
		if reason, e := iceDecStr(r); e == nil {
			ban["reason"] = reason
		}
		var startBytes [8]byte
		if _, e := io.ReadFull(r, startBytes[:]); e == nil {
			start := int64(binary.LittleEndian.Uint64(startBytes[:]))
			ban["start"] = time.Unix(start, 0).Format(time.RFC3339)
		}
		if dur, e := iceDecInt(r); e == nil {
			ban["duration"] = strconv.Itoa(int(dur))
		}
		bans = append(bans, ban)
	}
	return bans, nil
}

// IceSetBans replaces the ban list via Ice.
func (c *MumbleCore) IceSetBans(bans []map[string]string) error {
	ice, err := c.iceRequired("IceSetBans")
	if err != nil {
		return err
	}
	_, err = ice.callServer("setBans", iceOpIdempotent, func(buf *bytes.Buffer) {
		iceEncSize(buf, len(bans))
		for _, ban := range bans {
			addr := net.ParseIP(ban["address"])
			if addr == nil {
				addr = net.IPv4zero
			}
			addr = addr.To4()
			if addr == nil {
				addr = net.ParseIP(ban["address"])
			}
			iceEncSize(buf, len(addr))
			buf.Write(addr)
			bits, _ := strconv.Atoi(ban["bits"])
			iceEncInt(buf, int32(bits))
			iceEncStr(buf, ban["name"])
			iceEncStr(buf, ban["hash"])
			iceEncStr(buf, ban["reason"])
			var startUnix int64
			if t, e := time.Parse(time.RFC3339, ban["start"]); e == nil {
				startUnix = t.Unix()
			}
			var startBytes [8]byte
			binary.LittleEndian.PutUint64(startBytes[:], uint64(startUnix))
			buf.Write(startBytes[:])
			dur, _ := strconv.Atoi(ban["duration"])
			iceEncInt(buf, int32(dur))
		}
	})
	if err != nil {
		return fmt.Errorf("mumble: IceSetBans: %w", err)
	}
	return nil
}

// IceKickUser kicks a user via Ice.
func (c *MumbleCore) IceKickUser(session int, reason string) error {
	ice, err := c.iceRequired("IceKickUser")
	if err != nil {
		return err
	}
	_, err = ice.callServer("kickUser", iceOpNormal, func(buf *bytes.Buffer) {
		iceEncInt(buf, int32(session))
		iceEncStr(buf, reason)
	})
	if err != nil {
		return fmt.Errorf("mumble: IceKickUser: %w", err)
	}
	return nil
}

// IceGetState returns the full User state struct via Ice.
func (c *MumbleCore) IceGetState(session int) (map[string]string, error) {
	ice, err := c.iceRequired("IceGetState")
	if err != nil {
		return nil, err
	}
	data, err := ice.callServer("getState", iceOpIdempotent, func(buf *bytes.Buffer) {
		iceEncInt(buf, int32(session))
	})
	if err != nil {
		return nil, fmt.Errorf("mumble: IceGetState: %w", err)
	}
	if data == nil {
		return nil, nil
	}
	return iceDecUser(bytes.NewReader(data)), nil
}

// IceSetState modifies user state via Ice.
func (c *MumbleCore) IceSetState(session int, fields map[string]string) error {
	ice, err := c.iceRequired("IceSetState")
	if err != nil {
		return err
	}
	_, err = ice.callServer("setState", iceOpIdempotent, func(buf *bytes.Buffer) {
		s := int32(session)
		iceEncInt(buf, s) // session
		uid, _ := strconv.Atoi(fields["userid"])
		iceEncInt(buf, int32(uid))
		iceEncBool(buf, fields["mute"] == "true")
		iceEncBool(buf, fields["deaf"] == "true")
		iceEncBool(buf, fields["suppress"] == "true")
		iceEncBool(buf, fields["selfMute"] == "true")
		iceEncBool(buf, fields["selfDeaf"] == "true")
		ch, _ := strconv.Atoi(fields["channel"])
		iceEncInt(buf, int32(ch))
		iceEncStr(buf, fields["name"])
		onlinesecs, _ := strconv.Atoi(fields["onlinesecs"])
		iceEncInt(buf, int32(onlinesecs))
		idlesecs, _ := strconv.Atoi(fields["idlesecs"])
		iceEncInt(buf, int32(idlesecs))
	})
	if err != nil {
		return fmt.Errorf("mumble: IceSetState: %w", err)
	}
	return nil
}

// IceSendMessage sends text to a specific user via Ice.
func (c *MumbleCore) IceSendMessage(session int, text string) error {
	ice, err := c.iceRequired("IceSendMessage")
	if err != nil {
		return err
	}
	_, err = ice.callServer("sendMessage", iceOpNormal, func(buf *bytes.Buffer) {
		iceEncInt(buf, int32(session))
		iceEncStr(buf, text)
	})
	if err != nil {
		return fmt.Errorf("mumble: IceSendMessage: %w", err)
	}
	return nil
}

// IceHasPermission checks if a user has a specific permission in a channel.
func (c *MumbleCore) IceHasPermission(session, channelID int, perm int) (bool, error) {
	ice, err := c.iceRequired("IceHasPermission")
	if err != nil {
		return false, err
	}
	data, err := ice.callServer("hasPermission", iceOpIdempotent, func(buf *bytes.Buffer) {
		iceEncInt(buf, int32(session))
		iceEncInt(buf, int32(channelID))
		iceEncInt(buf, int32(perm))
	})
	if err != nil {
		return false, fmt.Errorf("mumble: IceHasPermission: %w", err)
	}
	if data == nil || len(data) == 0 {
		return false, nil
	}
	return data[0] != 0, nil
}

// IceEffectivePermissions returns the effective permission bitmask.
func (c *MumbleCore) IceEffectivePermissions(session, channelID int) (int, error) {
	ice, err := c.iceRequired("IceEffectivePermissions")
	if err != nil {
		return 0, err
	}
	data, err := ice.callServer("effectivePermissions", iceOpIdempotent, func(buf *bytes.Buffer) {
		iceEncInt(buf, int32(session))
		iceEncInt(buf, int32(channelID))
	})
	if err != nil {
		return 0, fmt.Errorf("mumble: IceEffectivePermissions: %w", err)
	}
	if data == nil {
		return 0, nil
	}
	r := bytes.NewReader(data)
	v, _ := iceDecInt(r)
	return int(v), nil
}

// IceGetChannelState returns a Channel struct via Ice.
func (c *MumbleCore) IceGetChannelState(channelID int) (map[string]string, error) {
	ice, err := c.iceRequired("IceGetChannelState")
	if err != nil {
		return nil, err
	}
	data, err := ice.callServer("getChannelState", iceOpIdempotent, func(buf *bytes.Buffer) {
		iceEncInt(buf, int32(channelID))
	})
	if err != nil {
		return nil, fmt.Errorf("mumble: IceGetChannelState: %w", err)
	}
	if data == nil {
		return nil, nil
	}
	return iceDecChannel(bytes.NewReader(data)), nil
}

// IceSetChannelState modifies channel properties via Ice.
func (c *MumbleCore) IceSetChannelState(channelID int, fields map[string]string) error {
	ice, err := c.iceRequired("IceSetChannelState")
	if err != nil {
		return err
	}
	_, err = ice.callServer("setChannelState", iceOpIdempotent, func(buf *bytes.Buffer) {
		iceEncInt(buf, int32(channelID))
		iceEncStr(buf, fields["name"])
		parent, _ := strconv.Atoi(fields["parent"])
		iceEncInt(buf, int32(parent))
		iceEncSize(buf, 0) // links (empty)
		iceEncStr(buf, fields["description"])
		iceEncBool(buf, fields["temporary"] == "true")
		pos, _ := strconv.Atoi(fields["position"])
		iceEncInt(buf, int32(pos))
	})
	if err != nil {
		return fmt.Errorf("mumble: IceSetChannelState: %w", err)
	}
	return nil
}

// IceRemoveChannel removes a channel via Ice.
func (c *MumbleCore) IceRemoveChannel(channelID int) error {
	ice, err := c.iceRequired("IceRemoveChannel")
	if err != nil {
		return err
	}
	_, err = ice.callServer("removeChannel", iceOpNormal, func(buf *bytes.Buffer) {
		iceEncInt(buf, int32(channelID))
	})
	if err != nil {
		return fmt.Errorf("mumble: IceRemoveChannel: %w", err)
	}
	return nil
}

// IceAddChannel creates a channel via Ice, returns new channel ID.
func (c *MumbleCore) IceAddChannel(name string, parent int) (int, error) {
	ice, err := c.iceRequired("IceAddChannel")
	if err != nil {
		return 0, err
	}
	data, err := ice.callServer("addChannel", iceOpNormal, func(buf *bytes.Buffer) {
		iceEncStr(buf, name)
		iceEncInt(buf, int32(parent))
	})
	if err != nil {
		return 0, fmt.Errorf("mumble: IceAddChannel: %w", err)
	}
	if data == nil {
		return 0, nil
	}
	r := bytes.NewReader(data)
	v, _ := iceDecInt(r)
	return int(v), nil
}

// IceSendMessageChannel sends text to a channel via Ice.
func (c *MumbleCore) IceSendMessageChannel(channelID int, tree bool, text string) error {
	ice, err := c.iceRequired("IceSendMessageChannel")
	if err != nil {
		return err
	}
	_, err = ice.callServer("sendMessageChannel", iceOpNormal, func(buf *bytes.Buffer) {
		iceEncInt(buf, int32(channelID))
		iceEncBool(buf, tree)
		iceEncStr(buf, text)
	})
	if err != nil {
		return fmt.Errorf("mumble: IceSendMessageChannel: %w", err)
	}
	return nil
}

// IceGetACL returns ACL/groups for a channel via Ice.
func (c *MumbleCore) IceGetACL(channelID int) (map[string]interface{}, error) {
	ice, err := c.iceRequired("IceGetACL")
	if err != nil {
		return nil, err
	}
	data, err := ice.callServer("getACL", iceOpIdempotent, func(buf *bytes.Buffer) {
		iceEncInt(buf, int32(channelID))
	})
	if err != nil {
		return nil, fmt.Errorf("mumble: IceGetACL: %w", err)
	}
	if data == nil {
		return map[string]interface{}{}, nil
	}
	return map[string]interface{}{"raw": hex.EncodeToString(data), "size": len(data)}, nil
}

// IceSetACL sets ACL/groups for a channel via Ice.
func (c *MumbleCore) IceSetACL(channelID int, aclData []byte, inherit bool) error {
	ice, err := c.iceRequired("IceSetACL")
	if err != nil {
		return err
	}
	_, err = ice.callServer("setACL", iceOpIdempotent, func(buf *bytes.Buffer) {
		iceEncInt(buf, int32(channelID))
		// ACL data is complex — pass raw encoded bytes
		buf.Write(aclData)
		iceEncBool(buf, inherit)
	})
	if err != nil {
		return fmt.Errorf("mumble: IceSetACL: %w", err)
	}
	return nil
}

// IceAddUserToGroup adds a user to an ACL group.
func (c *MumbleCore) IceAddUserToGroup(channelID, session int, group string) error {
	ice, err := c.iceRequired("IceAddUserToGroup")
	if err != nil {
		return err
	}
	_, err = ice.callServer("addUserToGroup", iceOpNormal, func(buf *bytes.Buffer) {
		iceEncInt(buf, int32(channelID))
		iceEncInt(buf, int32(session))
		iceEncStr(buf, group)
	})
	if err != nil {
		return fmt.Errorf("mumble: IceAddUserToGroup: %w", err)
	}
	return nil
}

// IceRemoveUserFromGroup removes a user from an ACL group.
func (c *MumbleCore) IceRemoveUserFromGroup(channelID, session int, group string) error {
	ice, err := c.iceRequired("IceRemoveUserFromGroup")
	if err != nil {
		return err
	}
	_, err = ice.callServer("removeUserFromGroup", iceOpNormal, func(buf *bytes.Buffer) {
		iceEncInt(buf, int32(channelID))
		iceEncInt(buf, int32(session))
		iceEncStr(buf, group)
	})
	if err != nil {
		return fmt.Errorf("mumble: IceRemoveUserFromGroup: %w", err)
	}
	return nil
}

// IceGetUserNames resolves user IDs to names.
func (c *MumbleCore) IceGetUserNames(ids []int) (map[int]string, error) {
	ice, err := c.iceRequired("IceGetUserNames")
	if err != nil {
		return nil, err
	}
	data, err := ice.callServer("getUserNames", iceOpIdempotent, func(buf *bytes.Buffer) {
		iceEncSize(buf, len(ids))
		for _, id := range ids {
			iceEncInt(buf, int32(id))
		}
	})
	if err != nil {
		return nil, fmt.Errorf("mumble: IceGetUserNames: %w", err)
	}
	if data == nil {
		return map[int]string{}, nil
	}
	r := bytes.NewReader(data)
	count, _ := iceDecSize(r)
	result := make(map[int]string, count)
	for i := 0; i < count; i++ {
		id, _ := iceDecInt(r)
		name, _ := iceDecStr(r)
		result[int(id)] = name
	}
	return result, nil
}

// IceGetUserIds resolves usernames to IDs.
func (c *MumbleCore) IceGetUserIds(names []string) (map[string]int, error) {
	ice, err := c.iceRequired("IceGetUserIds")
	if err != nil {
		return nil, err
	}
	data, err := ice.callServer("getUserIds", iceOpIdempotent, func(buf *bytes.Buffer) {
		iceEncSize(buf, len(names))
		for _, name := range names {
			iceEncStr(buf, name)
		}
	})
	if err != nil {
		return nil, fmt.Errorf("mumble: IceGetUserIds: %w", err)
	}
	if data == nil {
		return map[string]int{}, nil
	}
	r := bytes.NewReader(data)
	count, _ := iceDecSize(r)
	result := make(map[string]int, count)
	for i := 0; i < count; i++ {
		name, _ := iceDecStr(r)
		id, _ := iceDecInt(r)
		result[name] = int(id)
	}
	return result, nil
}

// IceRegisterUser registers a new user via Ice.
func (c *MumbleCore) IceRegisterUser(info map[int]string) (int, error) {
	ice, err := c.iceRequired("IceRegisterUser")
	if err != nil {
		return 0, err
	}
	data, err := ice.callServer("registerUser", iceOpNormal, func(buf *bytes.Buffer) {
		iceEncSize(buf, len(info))
		for k, v := range info {
			iceEncInt(buf, int32(k))
			iceEncStr(buf, v)
		}
	})
	if err != nil {
		return 0, fmt.Errorf("mumble: IceRegisterUser: %w", err)
	}
	if data == nil {
		return 0, nil
	}
	r := bytes.NewReader(data)
	v, _ := iceDecInt(r)
	return int(v), nil
}

// IceUnregisterUser unregisters a user via Ice.
func (c *MumbleCore) IceUnregisterUser(userID int) error {
	ice, err := c.iceRequired("IceUnregisterUser")
	if err != nil {
		return err
	}
	_, err = ice.callServer("unregisterUser", iceOpNormal, func(buf *bytes.Buffer) {
		iceEncInt(buf, int32(userID))
	})
	if err != nil {
		return fmt.Errorf("mumble: IceUnregisterUser: %w", err)
	}
	return nil
}

// IceUpdateRegistration updates registered user info.
func (c *MumbleCore) IceUpdateRegistration(userID int, info map[int]string) error {
	ice, err := c.iceRequired("IceUpdateRegistration")
	if err != nil {
		return err
	}
	_, err = ice.callServer("updateRegistration", iceOpNormal, func(buf *bytes.Buffer) {
		iceEncInt(buf, int32(userID))
		iceEncSize(buf, len(info))
		for k, v := range info {
			iceEncInt(buf, int32(k))
			iceEncStr(buf, v)
		}
	})
	if err != nil {
		return fmt.Errorf("mumble: IceUpdateRegistration: %w", err)
	}
	return nil
}

// IceGetRegistration gets registered user info.
func (c *MumbleCore) IceGetRegistration(userID int) (map[int]string, error) {
	ice, err := c.iceRequired("IceGetRegistration")
	if err != nil {
		return nil, err
	}
	data, err := ice.callServer("getRegistration", iceOpIdempotent, func(buf *bytes.Buffer) {
		iceEncInt(buf, int32(userID))
	})
	if err != nil {
		return nil, fmt.Errorf("mumble: IceGetRegistration: %w", err)
	}
	if data == nil {
		return map[int]string{}, nil
	}
	r := bytes.NewReader(data)
	count, _ := iceDecSize(r)
	result := make(map[int]string, count)
	for i := 0; i < count; i++ {
		k, _ := iceDecInt(r)
		v, _ := iceDecStr(r)
		result[int(k)] = v
	}
	return result, nil
}

// IceVerifyPassword verifies a user's password.
func (c *MumbleCore) IceVerifyPassword(name, pw string) (int, error) {
	ice, err := c.iceRequired("IceVerifyPassword")
	if err != nil {
		return -1, err
	}
	data, err := ice.callServer("verifyPassword", iceOpIdempotent, func(buf *bytes.Buffer) {
		iceEncStr(buf, name)
		iceEncStr(buf, pw)
	})
	if err != nil {
		return -1, fmt.Errorf("mumble: IceVerifyPassword: %w", err)
	}
	if data == nil {
		return -1, nil
	}
	r := bytes.NewReader(data)
	v, _ := iceDecInt(r)
	return int(v), nil // -1 = failed, >=0 = user ID
}

// IceGetTexture gets user avatar/texture via Ice.
func (c *MumbleCore) IceGetTexture(userID int) ([]byte, error) {
	ice, err := c.iceRequired("IceGetTexture")
	if err != nil {
		return nil, err
	}
	data, err := ice.callServer("getTexture", iceOpIdempotent, func(buf *bytes.Buffer) {
		iceEncInt(buf, int32(userID))
	})
	if err != nil {
		return nil, fmt.Errorf("mumble: IceGetTexture: %w", err)
	}
	if data == nil {
		return nil, nil
	}
	r := bytes.NewReader(data)
	n, _ := iceDecSize(r)
	tex := make([]byte, n)
	io.ReadFull(r, tex)
	return tex, nil
}

// IceSetTexture sets user avatar/texture via Ice.
func (c *MumbleCore) IceSetTexture(userID int, texture []byte) error {
	ice, err := c.iceRequired("IceSetTexture")
	if err != nil {
		return err
	}
	_, err = ice.callServer("setTexture", iceOpIdempotent, func(buf *bytes.Buffer) {
		iceEncInt(buf, int32(userID))
		iceEncSize(buf, len(texture))
		buf.Write(texture)
	})
	if err != nil {
		return fmt.Errorf("mumble: IceSetTexture: %w", err)
	}
	return nil
}

// IceStartListening makes a user listen to a channel via Ice.
func (c *MumbleCore) IceStartListening(session, channelID int) error {
	ice, err := c.iceRequired("IceStartListening")
	if err != nil {
		return err
	}
	_, err = ice.callServer("startListening", iceOpNormal, func(buf *bytes.Buffer) {
		iceEncInt(buf, int32(session))
		iceEncInt(buf, int32(channelID))
	})
	if err != nil {
		return fmt.Errorf("mumble: IceStartListening: %w", err)
	}
	return nil
}

// IceStopListening stops a user from listening to a channel via Ice.
func (c *MumbleCore) IceStopListening(session, channelID int) error {
	ice, err := c.iceRequired("IceStopListening")
	if err != nil {
		return err
	}
	_, err = ice.callServer("stopListening", iceOpNormal, func(buf *bytes.Buffer) {
		iceEncInt(buf, int32(session))
		iceEncInt(buf, int32(channelID))
	})
	if err != nil {
		return fmt.Errorf("mumble: IceStopListening: %w", err)
	}
	return nil
}

// IceIsListening checks if a user is listening to a channel via Ice.
func (c *MumbleCore) IceIsListening(session, channelID int) (bool, error) {
	ice, err := c.iceRequired("IceIsListening")
	if err != nil {
		return false, err
	}
	data, err := ice.callServer("isListening", iceOpIdempotent, func(buf *bytes.Buffer) {
		iceEncInt(buf, int32(session))
		iceEncInt(buf, int32(channelID))
	})
	if err != nil {
		return false, fmt.Errorf("mumble: IceIsListening: %w", err)
	}
	if data == nil || len(data) == 0 {
		return false, nil
	}
	return data[0] != 0, nil
}

// IceGetListeningChannels returns channels a user listens to via Ice.
func (c *MumbleCore) IceGetListeningChannels(session int) ([]int, error) {
	ice, err := c.iceRequired("IceGetListeningChannels")
	if err != nil {
		return nil, err
	}
	data, err := ice.callServer("getListeningChannels", iceOpIdempotent, func(buf *bytes.Buffer) {
		iceEncInt(buf, int32(session))
	})
	if err != nil {
		return nil, fmt.Errorf("mumble: IceGetListeningChannels: %w", err)
	}
	if data == nil {
		return []int{}, nil
	}
	r := bytes.NewReader(data)
	count, _ := iceDecSize(r)
	ids := make([]int, 0, count)
	for i := 0; i < count; i++ {
		id, _ := iceDecInt(r)
		ids = append(ids, int(id))
	}
	return ids, nil
}

// IceGetListeningUsers returns users listening to a channel via Ice.
func (c *MumbleCore) IceGetListeningUsers(channelID int) ([]int, error) {
	ice, err := c.iceRequired("IceGetListeningUsers")
	if err != nil {
		return nil, err
	}
	data, err := ice.callServer("getListeningUsers", iceOpIdempotent, func(buf *bytes.Buffer) {
		iceEncInt(buf, int32(channelID))
	})
	if err != nil {
		return nil, fmt.Errorf("mumble: IceGetListeningUsers: %w", err)
	}
	if data == nil {
		return []int{}, nil
	}
	r := bytes.NewReader(data)
	count, _ := iceDecSize(r)
	ids := make([]int, 0, count)
	for i := 0; i < count; i++ {
		id, _ := iceDecInt(r)
		ids = append(ids, int(id))
	}
	return ids, nil
}

// IceSendWelcomeMessage sends welcome message to specific user IDs via Ice.
func (c *MumbleCore) IceSendWelcomeMessage(userIDs []int) error {
	ice, err := c.iceRequired("IceSendWelcomeMessage")
	if err != nil {
		return err
	}
	_, err = ice.callServer("sendWelcomeMessage", iceOpNormal, func(buf *bytes.Buffer) {
		iceEncSize(buf, len(userIDs))
		for _, uid := range userIDs {
			iceEncInt(buf, int32(uid))
		}
	})
	if err != nil {
		return fmt.Errorf("mumble: IceSendWelcomeMessage: %w", err)
	}
	return nil
}

// ── Ice RPC — Callbacks (9 methods) ──

// IceServerCallbackUserConnected registers handler for user connect events.
func (c *MumbleCore) IceServerCallbackUserConnected(handler func(state map[string]string)) {
	c.mu.Lock()
	c.iceCBUserConnected = handler
	c.mu.Unlock()
}

// IceServerCallbackUserDisconnected registers handler for user disconnect events.
func (c *MumbleCore) IceServerCallbackUserDisconnected(handler func(state map[string]string)) {
	c.mu.Lock()
	c.iceCBUserDisconnected = handler
	c.mu.Unlock()
}

// IceServerCallbackUserStateChanged registers handler for user state change events.
func (c *MumbleCore) IceServerCallbackUserStateChanged(handler func(state map[string]string)) {
	c.mu.Lock()
	c.iceCBUserStateChanged = handler
	c.mu.Unlock()
}

// IceServerCallbackUserTextMessage registers handler for user text message events.
func (c *MumbleCore) IceServerCallbackUserTextMessage(handler func(state map[string]string)) {
	c.mu.Lock()
	c.iceCBUserTextMessage = handler
	c.mu.Unlock()
}

// IceServerCallbackChannelCreated registers handler for channel created events.
func (c *MumbleCore) IceServerCallbackChannelCreated(handler func(state map[string]string)) {
	c.mu.Lock()
	c.iceCBChannelCreated = handler
	c.mu.Unlock()
}

// IceServerCallbackChannelRemoved registers handler for channel removed events.
func (c *MumbleCore) IceServerCallbackChannelRemoved(handler func(state map[string]string)) {
	c.mu.Lock()
	c.iceCBChannelRemoved = handler
	c.mu.Unlock()
}

// IceServerCallbackChannelStateChanged registers handler for channel state change events.
func (c *MumbleCore) IceServerCallbackChannelStateChanged(handler func(state map[string]string)) {
	c.mu.Lock()
	c.iceCBChannelStateChanged = handler
	c.mu.Unlock()
}

// IceMetaCallbackStarted registers handler for virtual server started events.
func (c *MumbleCore) IceMetaCallbackStarted(handler func(serverID int)) {
	c.mu.Lock()
	c.iceCBMetaStarted = handler
	c.mu.Unlock()
}

// IceMetaCallbackStopped registers handler for virtual server stopped events.
func (c *MumbleCore) IceMetaCallbackStopped(handler func(serverID int)) {
	c.mu.Lock()
	c.iceCBMetaStopped = handler
	c.mu.Unlock()
}

// ── Ice RPC — Authenticator (10 methods) ──

// MumbleAuthenticator stores external authenticator callbacks.
type MumbleAuthenticator struct {
	Authenticate  func(name, pw, certHash string, certStrong bool) (userID int, groups []string, err error)
	GetInfo       func(userID int) (map[int]string, error)
	NameToId      func(name string) (int, error)
	IdToName      func(userID int) (string, error)
	IdToTexture   func(userID int) ([]byte, error)
	RegisterUser  func(info map[int]string) (int, error)
	UnregisterUser func(userID int) error
	SetInfo       func(userID int, info map[int]string) error
	SetTexture    func(userID int, texture []byte) error
}

// IceSetAuthenticator registers a custom authenticator for the server.
func (c *MumbleCore) IceSetAuthenticator(auth *MumbleAuthenticator) {
	c.mu.Lock()
	c.authenticator = auth
	c.mu.Unlock()
}

// AuthenticatorAuthenticate dispatches to the registered authenticator.
func (c *MumbleCore) AuthenticatorAuthenticate(name, pw, certHash string, certStrong bool) (int, []string, error) {
	c.mu.RLock()
	auth := c.authenticator
	c.mu.RUnlock()
	if auth == nil || auth.Authenticate == nil {
		return -1, nil, fmt.Errorf("mumble: no authenticator registered")
	}
	return auth.Authenticate(name, pw, certHash, certStrong)
}

// AuthenticatorGetInfo gets user info through the authenticator.
func (c *MumbleCore) AuthenticatorGetInfo(userID int) (map[int]string, error) {
	c.mu.RLock()
	auth := c.authenticator
	c.mu.RUnlock()
	if auth == nil || auth.GetInfo == nil {
		return nil, fmt.Errorf("mumble: no authenticator registered")
	}
	return auth.GetInfo(userID)
}

// AuthenticatorNameToId resolves username to user ID.
func (c *MumbleCore) AuthenticatorNameToId(name string) (int, error) {
	c.mu.RLock()
	auth := c.authenticator
	c.mu.RUnlock()
	if auth == nil || auth.NameToId == nil {
		return -1, fmt.Errorf("mumble: no authenticator registered")
	}
	return auth.NameToId(name)
}

// AuthenticatorIdToName resolves user ID to username.
func (c *MumbleCore) AuthenticatorIdToName(userID int) (string, error) {
	c.mu.RLock()
	auth := c.authenticator
	c.mu.RUnlock()
	if auth == nil || auth.IdToName == nil {
		return "", fmt.Errorf("mumble: no authenticator registered")
	}
	return auth.IdToName(userID)
}

// AuthenticatorIdToTexture gets user texture by ID.
func (c *MumbleCore) AuthenticatorIdToTexture(userID int) ([]byte, error) {
	c.mu.RLock()
	auth := c.authenticator
	c.mu.RUnlock()
	if auth == nil || auth.IdToTexture == nil {
		return nil, fmt.Errorf("mumble: no authenticator registered")
	}
	return auth.IdToTexture(userID)
}

// UpdatingAuthRegisterUser registers user via authenticator.
func (c *MumbleCore) UpdatingAuthRegisterUser(info map[int]string) (int, error) {
	c.mu.RLock()
	auth := c.authenticator
	c.mu.RUnlock()
	if auth == nil || auth.RegisterUser == nil {
		return -1, fmt.Errorf("mumble: no authenticator registered")
	}
	return auth.RegisterUser(info)
}

// UpdatingAuthUnregisterUser unregisters user via authenticator.
func (c *MumbleCore) UpdatingAuthUnregisterUser(userID int) error {
	c.mu.RLock()
	auth := c.authenticator
	c.mu.RUnlock()
	if auth == nil || auth.UnregisterUser == nil {
		return fmt.Errorf("mumble: no authenticator registered")
	}
	return auth.UnregisterUser(userID)
}

// UpdatingAuthSetInfo updates user info via authenticator.
func (c *MumbleCore) UpdatingAuthSetInfo(userID int, info map[int]string) error {
	c.mu.RLock()
	auth := c.authenticator
	c.mu.RUnlock()
	if auth == nil || auth.SetInfo == nil {
		return fmt.Errorf("mumble: no authenticator registered")
	}
	return auth.SetInfo(userID, info)
}

// UpdatingAuthSetTexture updates user texture via authenticator.
func (c *MumbleCore) UpdatingAuthSetTexture(userID int, texture []byte) error {
	c.mu.RLock()
	auth := c.authenticator
	c.mu.RUnlock()
	if auth == nil || auth.SetTexture == nil {
		return fmt.Errorf("mumble: no authenticator registered")
	}
	return auth.SetTexture(userID, texture)
}

// ── Client Protocol — Missing Features (15 methods) ──

// RenameChannel sends ChannelState with a new name.
func (c *MumbleCore) RenameChannel(channelID uint32, newName string) error {
	c.mu.RLock()
	conn := c.tlsConn
	c.mu.RUnlock()
	if conn == nil {
		return fmt.Errorf("mumble: not connected")
	}
	msg := &mumbleChannelStateMsg{ChannelID: channelID, HasChannelID: true, Name: newName}
	return c.tcpSend(mumbleMsgChannelState, msg.marshal())
}

// GetChannelDescription requests and returns a channel's description (auto-resolves blob hash).
func (c *MumbleCore) GetChannelDescription(channelID uint32) (string, error) {
	c.mu.RLock()
	ch, ok := c.channels[channelID]
	c.mu.RUnlock()
	if !ok {
		return "", ErrNotFound
	}
	if ch.Description != "" {
		return ch.Description, nil
	}
	// If we have a descriptionHash, request the blob
	if len(ch.DescriptionHash) > 0 {
		if err := c.RequestBlob(nil, nil, []uint32{channelID}); err != nil {
			return "", err
		}
		// Wait briefly for the response
		time.Sleep(500 * time.Millisecond)
		c.mu.RLock()
		desc := c.channels[channelID].Description
		c.mu.RUnlock()
		return desc, nil
	}
	return "", nil
}

// GetUserComment requests and returns a user's comment (auto-resolves blob hash).
func (c *MumbleCore) GetUserComment(session uint32) (string, error) {
	c.mu.RLock()
	user, ok := c.users[session]
	c.mu.RUnlock()
	if !ok {
		return "", ErrNotFound
	}
	if user.Comment != "" {
		return user.Comment, nil
	}
	if len(user.CommentHash) > 0 {
		if err := c.RequestBlob([]uint32{session}, nil, nil); err != nil {
			return "", err
		}
		time.Sleep(500 * time.Millisecond)
		c.mu.RLock()
		comment := c.users[session].Comment
		c.mu.RUnlock()
		return comment, nil
	}
	return "", nil
}

// GetUserTexture requests and returns a user's texture (auto-resolves blob hash).
func (c *MumbleCore) GetUserTexture(session uint32) ([]byte, error) {
	c.mu.RLock()
	user, ok := c.users[session]
	c.mu.RUnlock()
	if !ok {
		return nil, ErrNotFound
	}
	if len(user.Texture) > 0 {
		return user.Texture, nil
	}
	if len(user.TextureHash) > 0 {
		if err := c.RequestBlob(nil, []uint32{session}, nil); err != nil {
			return nil, err
		}
		time.Sleep(500 * time.Millisecond)
		c.mu.RLock()
		tex := c.users[session].Texture
		c.mu.RUnlock()
		return tex, nil
	}
	return nil, nil
}

// ParseMumbleURL parses a mumble:// URL into components.
func ParseMumbleURL(rawURL string) (host string, port int, channel string, username string, password string, err error) {
	rawURL = strings.TrimPrefix(rawURL, "mumble://")
	// Format: [user[:password]@]host[:port][/channel[/subchannel]]
	port = 64738 // default

	// Extract channel path
	slashIdx := strings.Index(rawURL, "/")
	hostPart := rawURL
	if slashIdx >= 0 {
		channel = rawURL[slashIdx+1:]
		channel = strings.TrimRight(channel, "/")
		hostPart = rawURL[:slashIdx]
	}

	// Extract user@
	atIdx := strings.LastIndex(hostPart, "@")
	if atIdx >= 0 {
		userPart := hostPart[:atIdx]
		hostPart = hostPart[atIdx+1:]
		if colonIdx := strings.Index(userPart, ":"); colonIdx >= 0 {
			username = userPart[:colonIdx]
			password = userPart[colonIdx+1:]
		} else {
			username = userPart
		}
	}

	// Parse host:port
	h, p, e := net.SplitHostPort(hostPart)
	if e != nil {
		host = hostPart
	} else {
		host = h
		fmt.Sscanf(p, "%d", &port)
	}
	return
}

// ConnectFromURL connects using a mumble:// URL.
func (c *MumbleCore) ConnectFromURL(mumbleURL string) error {
	host, port, _, username, password, err := ParseMumbleURL(mumbleURL)
	if err != nil {
		return fmt.Errorf("mumble: invalid URL: %w", err)
	}
	addr := net.JoinHostPort(host, strconv.Itoa(port))

	cfg := AuthConfig{
		Mode: AuthModeUser,
		Extra: map[string]string{
			"server":   addr,
			"username": username,
		},
	}
	if password != "" {
		cfg.Password2F = password
	}
	return c.Authenticate(cfg)
}

// HandleUserStats registers a callback for UserStats responses.
func (c *MumbleCore) HandleUserStats(handler func(session uint32, stats map[string]interface{})) {
	c.mu.Lock()
	c.userStatsHandler = handler
	c.mu.Unlock()
}

// LoadCertificate loads a TLS client certificate from PEM files.
func (c *MumbleCore) LoadCertificate(certFile, keyFile string) error {
	cert, err := tls.LoadX509KeyPair(certFile, keyFile)
	if err != nil {
		return fmt.Errorf("mumble: load certificate: %w", err)
	}
	c.mu.Lock()
	c.tlsCert = cert
	c.mu.Unlock()
	return nil
}

// GetCertificateHash returns the SHA1 hash of the client certificate.
func (c *MumbleCore) GetCertificateHash() string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.certHash
}

// GetServerCertificate returns the server's TLS certificate.
func (c *MumbleCore) GetServerCertificate() (*x509.Certificate, error) {
	c.mu.RLock()
	conn := c.tlsConn
	c.mu.RUnlock()
	if conn == nil {
		return nil, fmt.Errorf("mumble: not connected")
	}
	state := conn.ConnectionState()
	if len(state.PeerCertificates) == 0 {
		return nil, fmt.Errorf("mumble: no server certificate")
	}
	return state.PeerCertificates[0], nil
}

// FlushPermissions sends PermissionQuery with flush=true.
func (c *MumbleCore) FlushPermissions(channelID uint32) error {
	c.mu.RLock()
	conn := c.tlsConn
	c.mu.RUnlock()
	if conn == nil {
		return fmt.Errorf("mumble: not connected")
	}
	msg := &mumblePermissionQueryMsg{ChannelID: channelID, Flush: true}
	return c.tcpSend(mumbleMsgPermissionQuery, msg.marshal())
}

// GetCachedPermissions returns locally cached permissions without a round-trip.
func (c *MumbleCore) GetCachedPermissions(channelID uint32) uint32 {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.permissions[channelID]
}

// GetChannelTree builds a full channel tree as a structured object.
func (c *MumbleCore) GetChannelTree() map[string]interface{} {
	c.mu.RLock()
	defer c.mu.RUnlock()

	type treeNode struct {
		ID       uint32
		Name     string
		Children []treeNode
		Users    []string
	}

	var buildTree func(parentID uint32) []treeNode
	buildTree = func(parentID uint32) []treeNode {
		var children []treeNode
		for _, ch := range c.channels {
			if ch.ParentID == parentID && ch.ID != parentID {
				var users []string
				for _, u := range c.users {
					if u.ChannelID == ch.ID {
						users = append(users, u.Name)
					}
				}
				children = append(children, treeNode{
					ID:       ch.ID,
					Name:     ch.Name,
					Children: buildTree(ch.ID),
					Users:    users,
				})
			}
		}
		return children
	}

	root, ok := c.channels[0]
	if !ok {
		return map[string]interface{}{"error": "no root channel"}
	}
	var rootUsers []string
	for _, u := range c.users {
		if u.ChannelID == 0 {
			rootUsers = append(rootUsers, u.Name)
		}
	}

	return map[string]interface{}{
		"id":       root.ID,
		"name":     root.Name,
		"users":    rootUsers,
		"children": buildTree(0),
	}
}

// Reconnect reconnects with the same credentials.
func (c *MumbleCore) Reconnect() error {
	c.mu.RLock()
	addr := c.serverAddr
	c.mu.RUnlock()
	if addr == "" {
		return fmt.Errorf("mumble: no previous connection")
	}
	c.Close()
	// Re-authenticate with stored config
	return c.Authenticate(AuthConfig{
		Mode:  AuthModeUser,
		Extra: map[string]string{"server": addr},
	})
}

// SetAutoReconnect enables auto-reconnect on disconnection.
func (c *MumbleCore) SetAutoReconnect(enabled bool, delay time.Duration) {
	c.mu.Lock()
	c.autoReconnect = enabled
	c.reconnectDelay = delay
	c.mu.Unlock()
}

// ── Audio — Missing Features (4 methods) ──

// SetAudioBitrate configures the Opus encoder bitrate.
func (c *MumbleCore) SetAudioBitrate(bitrate int) {
	c.mu.Lock()
	c.audioBitrate = bitrate
	c.mu.Unlock()
}

// SetAudioFrameSize configures audio frame duration in ms (10, 20, 40, 60).
func (c *MumbleCore) SetAudioFrameSize(ms int) {
	c.mu.Lock()
	c.audioFrameSize = ms
	c.mu.Unlock()
}

// GetAudioStats returns local audio statistics.
func (c *MumbleCore) GetAudioStats() map[string]interface{} {
	return map[string]interface{}{
		"udp_packets_sent":     c.udpPktsSent.Load(),
		"udp_packets_received": c.udpPktsRecv.Load(),
		"tcp_packets_sent":     c.tcpPktsSent.Load(),
		"tcp_packets_received": c.tcpPktsRecv.Load(),
		"voice_tunnel_recv":    c.voiceTunnelRecv.Load(),
		"voice_seq_num":        c.voiceSeqNum.Load(),
		"tcp_ping_avg":         c.tcpPingAvg,
		"udp_ping_avg":         c.udpPingAvg,
	}
}

// OnAudioStream registers a per-user audio stream callback.
// The handler receives (session uint32, pcm []int16, codec string).
func (c *MumbleCore) OnAudioStream(handler func(session uint32, pcm []int16, codec string)) {
	c.mu.Lock()
	c.audioStreamHandler = handler
	c.mu.Unlock()
}

// ── DNS / Discovery ──

// MumbleResolveSRV performs DNS SRV record lookup for _mumble._tcp.<hostname>.
func MumbleResolveSRV(hostname string) (string, error) {
	_, addrs, err := net.LookupSRV("mumble", "tcp", hostname)
	if err != nil {
		return "", fmt.Errorf("mumble SRV lookup: %w", err)
	}
	if len(addrs) == 0 {
		return "", fmt.Errorf("mumble SRV lookup: no records found for %s", hostname)
	}
	target := strings.TrimRight(addrs[0].Target, ".")
	return net.JoinHostPort(target, strconv.Itoa(int(addrs[0].Port))), nil
}

// MuteChat returns an error because Mumble does not support muting chats.
func (c *MumbleCore) MuteChat(chatID string, muted bool) error {
	return fmt.Errorf("%w: %s does not support mute chat", ErrNotSupported, mumblePlatform)
}

// ArchiveChat returns an error because Mumble does not support archiving chats.
func (c *MumbleCore) ArchiveChat(chatID string, archived bool) error {
	return fmt.Errorf("%w: %s does not support archive chat", ErrNotSupported, mumblePlatform)
}

// MarkUnread returns an error because Mumble does not support marking chats as unread.
func (c *MumbleCore) MarkUnread(chatID string, unread bool) error {
	return fmt.Errorf("%w: %s does not support mark unread", ErrNotSupported, mumblePlatform)
}

// UnpinAllMessages returns an error because Mumble does not support message pinning.
func (c *MumbleCore) UnpinAllMessages(chatID string) error {
	return fmt.Errorf("%w: %s does not support unpin all messages", ErrNotSupported, mumblePlatform)
}

// AcceptCall returns an error because Mumble uses always-on voice channels instead of call invitations.
func (c *MumbleCore) AcceptCall(callID string) (*CallSession, error) {
	return nil, fmt.Errorf("%w: %s does not support accept call", ErrNotSupported, mumblePlatform)
}

// DeclineCall returns an error because Mumble uses always-on voice channels instead of call invitations.
func (c *MumbleCore) DeclineCall(callID string) error {
	return fmt.Errorf("%w: %s does not support decline call", ErrNotSupported, mumblePlatform)
}

// SendLocation returns an error because Mumble does not support location sharing.
func (c *MumbleCore) SendLocation(chatID string, lat float64, lon float64) (*Message, error) {
	return nil, fmt.Errorf("%w: %s does not support send location", ErrNotSupported, mumblePlatform)
}

// ════════════════════════════════════════════════════════════════════════════════
// Ensure MumbleCore implements Core interface
// ════════════════════════════════════════════════════════════════════════════════

var _ Core = (*MumbleCore)(nil)
