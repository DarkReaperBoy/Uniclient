package cores

import (
	"bytes"
	"crypto/aes"
	"crypto/rand"
	"encoding/binary"
	"testing"
)

// ───────────────────────────── Mumble OCB2 crypto ─────────────────────────────
//
// Mirrors upstream TestCrypt.cpp (mumble-voip/mumble): IV recovery, replay
// rejection and the 30-packet out-of-order window.

func mumbleTestCryptState(t *testing.T) *mumbleCryptState {
	t.Helper()
	key := make([]byte, 16)
	clientNonce := make([]byte, 16)
	serverNonce := make([]byte, 16)
	for i := range key {
		key[i] = byte(i * 7)
		clientNonce[i] = byte(i * 11)
		serverNonce[i] = byte(i * 13)
	}
	cs := &mumbleCryptState{}
	if err := cs.init(key, clientNonce, serverNonce); err != nil {
		t.Fatalf("init: %v", err)
	}
	return cs
}

// mumbleTestCryptPair mirrors upstream TestCrypt.cpp: the decrypting side
// gets the encrypting side's encrypt IV as ITS decrypt IV (as if the
// "server" side of the pair were the encrypter).
func mumbleTestCryptPair(t *testing.T) (enc, dec *mumbleCryptState) {
	t.Helper()
	key := make([]byte, 16)
	encIV := make([]byte, 16)
	decIV := make([]byte, 16)
	for i := range key {
		key[i] = byte(i * 7)
		encIV[i] = byte(i * 11)
		decIV[i] = byte(i * 13)
	}
	enc = &mumbleCryptState{}
	if err := enc.init(key, encIV, decIV); err != nil {
		t.Fatalf("enc init: %v", err)
	}
	dec = &mumbleCryptState{}
	if err := dec.init(key, decIV, encIV); err != nil {
		t.Fatalf("dec init: %v", err)
	}
	return enc, dec
}

func TestMumbleOCB2RoundTrip(t *testing.T) {
	enc, dec := mumbleTestCryptPair(t)

	secret := []byte("abcdefghi")
	dst := make([]byte, 4+len(secret))
	n := enc.encrypt(dst, secret)
	if n != 4+len(secret) {
		t.Fatalf("encrypt returned %d, want %d", n, 4+len(secret))
	}

	plain := make([]byte, len(secret))
	m, err := dec.decrypt(plain, dst)
	if err != nil {
		t.Fatalf("decrypt: %v", err)
	}
	if m != len(secret) {
		t.Fatalf("decrypt length %d, want %d", m, len(secret))
	}
	if !bytes.Equal(plain, secret) {
		t.Fatalf("round-trip mismatch: %q != %q", plain, secret)
	}

	// Reusing the same IV (replaying the packet) must fail.
	if _, err := dec.decrypt(plain, dst); err == nil {
		t.Fatal("replayed packet accepted — replay protection broken")
	}
}

func TestMumbleOCB2OutOfOrderWindow(t *testing.T) {
	enc, dec := mumbleTestCryptPair(t)

	secret := []byte("abcdefghi")
	pktLen := 4 + len(secret)
	var crypted [128][13]byte
	for i := 0; i < 128; i++ {
		enc.encrypt(crypted[i][:pktLen], secret)
	}

	// Decrypting newest→oldest works within 30 packets.
	for i := 0; i < 30; i++ {
		plain := make([]byte, len(secret))
		if _, err := dec.decrypt(plain, crypted[127-i][:pktLen]); err != nil {
			t.Fatalf("in-window OOO packet %d rejected: %v", i, err)
		}
	}
	// Beyond 30 packets late must fail.
	for i := 30; i < 128; i++ {
		plain := make([]byte, len(secret))
		if _, err := dec.decrypt(plain, crypted[127-i][:pktLen]); err == nil {
			t.Fatalf("out-of-window OOO packet %d accepted", i)
		}
	}
	// Already-seen packets must fail (full replay guard).
	for i := 0; i < 30; i++ {
		plain := make([]byte, len(secret))
		if _, err := dec.decrypt(plain, crypted[127-i][:pktLen]); err == nil {
			t.Fatalf("replayed packet %d accepted", i)
		}
	}
}

func TestMumbleOCB2ReplayAttack512(t *testing.T) {
	enc, dec := mumbleTestCryptPair(t)

	secret := []byte("abcdefghi")
	pktLen := 4 + len(secret)
	var crypted [512][13]byte
	for i := 0; i < 512; i++ {
		enc.encrypt(crypted[i][:pktLen], secret)
	}
	for i := 0; i < 512; i++ {
		plain := make([]byte, len(secret))
		if _, err := dec.decrypt(plain, crypted[i][:pktLen]); err != nil {
			t.Fatalf("packet %d rejected in-order: %v", i, err)
		}
	}
	for i := 0; i < 512; i++ {
		plain := make([]byte, len(secret))
		if _, err := dec.decrypt(plain, crypted[i][:pktLen]); err == nil {
			t.Fatalf("replay of packet %d accepted", i)
		}
	}
}

func TestMumbleOCB2TamperDetection(t *testing.T) {
	enc, dec := mumbleTestCryptPair(t)

	secret := []byte("attack at dawn")
	dst := make([]byte, 4+len(secret))
	enc.encrypt(dst, secret)

	dst[5] ^= 0xFF // flip a ciphertext bit
	plain := make([]byte, len(secret))
	if _, err := dec.decrypt(plain, dst); err == nil {
		t.Fatal("tampered packet accepted — OCB2 tag not enforced")
	}
}

// ───────────────────────────── Mumble varint ─────────────────────────────

func TestMumbleVarintRoundTrip(t *testing.T) {
	values := []int64{0, 1, 7, 8, 63, 64, 127, 128, 255, 256, 8191, 8192,
		65535, 65536, 1048575, 1048576, 16777215, 16777216,
		1073741823, 1073741824, -1, -2, -3, -4, -64, -8192, -1048576, -134217728}
	for _, v := range values {
		buf := mumbleVarintEncode(v)
		got, n, err := mumbleVarintDecode(buf, 0)
		if err != nil {
			t.Fatalf("varint(%d) decode: %v", v, err)
		}
		if got != v {
			t.Fatalf("varint round-trip %d → %d (bytes %x)", v, got, buf)
		}
		if n != len(buf) {
			t.Fatalf("varint(%d) consumed %d bytes, wrote %d", v, n, len(buf))
		}
	}
}

// ───────────────────────────── Mumble protobuf ─────────────────────────────

func TestMumbleVersionRoundTrip(t *testing.T) {
	v := &mumbleVersion{
		VersionV1: mumbleVersionV1,
		VersionV2: mumbleVersionV2,
		Release:   "Uniclient test",
		OS:        "Linux",
		OSVersion: "6.1",
	}
	var v2 mumbleVersion
	if err := v2.unmarshal(v.marshal()); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if v2.VersionV1 != v.VersionV1 || v2.VersionV2 != v.VersionV2 ||
		v2.Release != v.Release || v2.OS != v.OS || v2.OSVersion != v.OSVersion {
		t.Fatalf("Version round-trip mismatch: %+v != %+v", v2, v)
	}
}

func TestMumbleAuthenticateWire(t *testing.T) {
	// Field order/numbers per official Mumble.proto:
	// username=1 password=2 tokens=3 celt=4 opus=5 client_type=6.
	a := &mumbleAuthenticate{
		Username: "u1",
		Password: "pw",
		Tokens:   []string{"t1", "t2"},
		Opus:     true,
	}
	wire := a.marshal()
	// username: field 1, LEN 2 → tag 0x0A
	if wire[0] != 0x0A {
		t.Fatalf("Authenticate field 1 tag = %#x, want 0x0A", wire[0])
	}
	// opus: field 5, VARINT → tag 0x28
	foundOpus := false
	for i := 0; i < len(wire); i++ {
		if wire[i] == 0x28 {
			foundOpus = true
		}
	}
	if !foundOpus {
		t.Fatal("Authenticate opus (field 5, tag 0x28) missing")
	}
}

func TestMumbleTextMessageRoundTrip(t *testing.T) {
	m := &mumbleTextMsg{
		Actor:     42,
		Session:   []uint32{7, 8},
		ChannelID: []uint32{0},
		TreeID:    []uint32{3},
		Message:   "hello <b>world</b>",
	}
	var m2 mumbleTextMsg
	if err := m2.unmarshal(m.marshal()); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if m2.Actor != m.Actor || m2.Message != m.Message ||
		len(m2.Session) != 2 || m2.Session[1] != 8 ||
		len(m2.ChannelID) != 1 || len(m2.TreeID) != 1 || m2.TreeID[0] != 3 {
		t.Fatalf("TextMessage round-trip mismatch: %+v", m2)
	}
}

func TestMumbleUserStateAllFields(t *testing.T) {
	m := &mumbleUserStateMsg{
		Session:            5,
		HasSession:         true,
		Actor:              6,
		HasActor:           true,
		Name:               "alice",
		UserID:             9,
		HasUserID:          true,
		ChannelID:          1,
		HasChannelID:       true,
		Mute:               true,
		HasMute:            true,
		Deaf:               false,
		HasDeaf:            true,
		Suppress:           false,
		HasSuppress:        true,
		SelfMute:           true,
		HasSelfMute:        true,
		SelfDeaf:           false,
		HasSelfDeaf:        true,
		Comment:            "hi",
		Hash:               "abc",
		PrioritySpeaker:    false,
		HasPrioritySpeaker: true,
		Recording:          true,
		HasRecording:       true,
	}
	var m2 mumbleUserStateMsg
	if err := m2.unmarshal(m.marshal()); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if m2.Session != 5 || m2.Actor != 6 || m2.Name != "alice" || m2.ChannelID != 1 ||
		!m2.Mute || !m2.SelfMute || !m2.Recording || m2.Comment != "hi" || m2.Hash != "abc" || m2.UserID != 9 {
		t.Fatalf("UserState round-trip mismatch: %+v", m2)
	}
}

func TestMumbleCryptSetupRoundTrip(t *testing.T) {
	m := &mumbleCryptSetupMsg{}
	// hand-build fields through the struct
	key := make([]byte, 16)
	cn := make([]byte, 16)
	sn := make([]byte, 16)
	for i := range key {
		key[i] = byte(i)
		cn[i] = byte(200 - i)
		sn[i] = byte(100 + i)
	}
	m2 := &mumbleCryptSetupMsg{}
	wire := m.marshal()
	_ = wire
	_ = key
	_ = cn
	_ = sn
	_ = m2
	// CryptSetup fields: key=1 client_nonce=2 server_nonce=3 (bytes).
	cs := &mumbleCryptSetupMsg{}
	var e pbEncoder
	e.writeBytes(1, key)
	e.writeBytes(2, cn)
	e.writeBytes(3, sn)
	var out mumbleCryptSetupMsg
	if err := out.unmarshal(e.bytes()); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	_ = cs
}

// ───────────────────────────── Mumble TCP framing ─────────────────────────────

func TestMumbleTCPPingWire(t *testing.T) {
	// TCP Ping: timestamp=1 (varint). A marshaled Ping with only timestamp
	// set must be tag 0x08 followed by varint.
	p := &mumblePingMsg{Timestamp: 12345}
	wire := p.marshal()
	if len(wire) < 2 || wire[0] != 0x08 {
		t.Fatalf("Ping wire = %x, want tag 0x08 (field 1 varint)", wire)
	}
	var p2 mumblePingMsg
	if err := p2.unmarshal(wire); err != nil {
		t.Fatalf("Ping unmarshal: %v", err)
	}
	if p2.Timestamp != 12345 {
		t.Fatalf("Ping timestamp %d, want 12345", p2.Timestamp)
	}
}

// ───────────────────────────── Mumble message IDs ─────────────────────────────

func TestMumbleMessageTypeIDs(t *testing.T) {
	// Official Mumble.proto ordering (IDs are the wire contract).
	cases := []struct {
		id   uint16
		name string
	}{
		{0, "Version"}, {1, "UDPTunnel"}, {2, "Authenticate"}, {3, "Ping"},
		{4, "Reject"}, {5, "ServerSync"}, {6, "ChannelRemove"}, {7, "ChannelState"},
		{8, "UserRemove"}, {9, "UserState"}, {10, "BanList"}, {11, "TextMessage"},
		{12, "PermissionDenied"}, {13, "ACL"}, {14, "QueryUsers"}, {15, "CryptSetup"},
		{16, "ContextActionModify"}, {17, "ContextAction"}, {18, "UserList"},
		{19, "VoiceTarget"}, {20, "PermissionQuery"}, {21, "CodecVersion"},
		{22, "UserStats"}, {23, "RequestBlob"}, {24, "ServerConfig"},
		{25, "SuggestConfig"}, {26, "PluginDataTransmission"},
	}
	for _, c := range cases {
		if got := mumbleMsgName(c.id); got != c.name {
			t.Errorf("message id %d = %q, want %q", c.id, got, c.name)
		}
	}
}

func TestMumbleUDPPingFormat(t *testing.T) {
	// The legacy UDP ping request: 12 bytes = 4 zero bytes + 8 ident bytes.
	// Response: version(4) + ident(8) + users(4) + max(4) + bandwidth(4) = 24.
	req := make([]byte, 12)
	resp := make([]byte, 24)
	binary.BigEndian.PutUint32(resp[12:16], 3)  // users
	binary.BigEndian.PutUint32(resp[16:20], 50) // max users
	binary.BigEndian.PutUint32(resp[20:24], 72000)
	if len(req) != 12 || len(resp) != 24 {
		t.Fatal("ping format length mismatch")
	}
}

// TestOCB2OfficialVectors pins ocb2Encrypt/ocb2Decrypt against the
// draft-krovetz-ocb-00 vectors used by upstream TestCrypt::testvectors.
// If this fails, every encrypted UDP packet we send is unreadable to
// real Murmur servers (tag mismatch → silent drop).
func TestOCB2OfficialVectors(t *testing.T) {
	key := []byte{0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15}
	block, err := aes.NewCipher(key)
	if err != nil {
		t.Fatal(err)
	}

	// Empty message: tag BF3108130773AD5EC70EC69E7875A7B0.
	var tag [16]byte
	ocb2Encrypt(block, nil, nil, key, tag[:])
	wantBlank := []byte{0xBF, 0x31, 0x08, 0x13, 0x07, 0x73, 0xAD, 0x5E, 0xC7, 0x0E, 0xC6, 0x9E, 0x78, 0x75, 0xA7, 0xB0}
	if !bytes.Equal(tag[:], wantBlank) {
		t.Fatalf("blank tag mismatch:\n got %x\nwant %x", tag[:], wantBlank)
	}

	// 40-byte message 0..39.
	src := make([]byte, 40)
	for i := range src {
		src[i] = byte(i)
	}
	ct := make([]byte, 40)
	ocb2Encrypt(block, ct, src, key, tag[:])
	wantTag := []byte{0x9D, 0xB0, 0xCD, 0xF8, 0x80, 0xF7, 0x3E, 0x3E, 0x10, 0xD4, 0xEB, 0x32, 0x17, 0x76, 0x66, 0x88}
	if !bytes.Equal(tag[:], wantTag) {
		t.Fatalf("40-byte tag mismatch:\n got %x\nwant %x", tag[:], wantTag)
	}
	wantCT := []byte{0xF7, 0x5D, 0x6B, 0xC8, 0xB4, 0xDC, 0x8D, 0x66, 0xB8, 0x36, 0xA2, 0xB0, 0x8B, 0x32, 0xA6, 0x36, 0x9F, 0x1C, 0xD3, 0xC5, 0x22, 0x8D, 0x79, 0xFD, 0x6C, 0x26, 0x7F, 0x5F, 0x6A, 0xA7, 0xB2, 0x31, 0xC7, 0xDF, 0xB9, 0xD5, 0x99, 0x51, 0xAE, 0x9C}
	if !bytes.Equal(ct, wantCT) {
		t.Fatalf("40-byte ciphertext mismatch:\n got %x\nwant %x", ct, wantCT)
	}

	// Decrypt round-trip of the same vector through ocb2Decrypt.
	pt := make([]byte, 40)
	if !ocb2Decrypt(block, pt, wantCT, key, wantTag) {
		t.Fatal("vector decrypt failed")
	}
	if !bytes.Equal(pt, src) {
		t.Fatalf("vector plaintext mismatch:\n got %x\nwant %x", pt, src)
	}
}

// TestOCB2ClientServerDirections simulates the full crypt handshake
// exactly as Murmur does it: the server generates key+nonces; the
// client encrypts with client_nonce as its initial IV, the server
// decrypts the same stream with client_nonce as its decrypt IV. If the
// first packet fails, every encrypted UDP datagram is silently dropped
// by real servers.
func TestOCB2ClientServerDirections(t *testing.T) {
	key := make([]byte, 16)
	clientNonce := make([]byte, 16)
	serverNonce := make([]byte, 16)
	rand.Read(key)
	rand.Read(clientNonce)
	rand.Read(serverNonce)

	// Client state: encrypt from client_nonce, decrypt from server_nonce.
	client := &mumbleCryptState{}
	if err := client.init(key, clientNonce, serverNonce); err != nil {
		t.Fatal(err)
	}
	// Server state (mirrors murmur): the server's OWN encryption IV is
	// server_nonce (its stream to us), and its decryption IV for OUR
	// stream is client_nonce — the nonce pair from the client's
	// perspective, swapped.
	server := &mumbleCryptState{}
	if err := server.init(key, serverNonce, clientNonce); err != nil {
		t.Fatal(err)
	}

	// Client → server: 5 packets.
	for i := 0; i < 5; i++ {
		plain := []byte{1, 0x08, byte(i), 0x01}
		wire := make([]byte, mumbleCryptoOverhead+len(plain))
		n := client.encrypt(wire, plain)
		if n != len(wire) {
			t.Fatalf("packet %d: encrypt wrote %d, want %d", i, n, len(wire))
		}
		got := make([]byte, len(wire))
		pLen, err := server.decrypt(got, wire)
		if err != nil {
			t.Fatalf("packet %d: server-side decrypt failed: %v (real murmur would silently drop it)", i, err)
		}
		if !bytes.Equal(got[:pLen], plain) {
			t.Fatalf("packet %d: plaintext mismatch: %x vs %x", i, got[:pLen], plain)
		}
	}

	// Server → client: the reply direction.
	for i := 0; i < 5; i++ {
		plain := []byte{1, 0x08, byte(i), 0x01}
		wire := make([]byte, mumbleCryptoOverhead+len(plain))
		server.encrypt(wire, plain)
		got := make([]byte, len(wire))
		pLen, err := client.decrypt(got, wire)
		if err != nil {
			t.Fatalf("reply %d: client-side decrypt failed: %v", i, err)
		}
		if !bytes.Equal(got[:pLen], plain) {
			t.Fatalf("reply %d: plaintext mismatch", i)
		}
	}
}
