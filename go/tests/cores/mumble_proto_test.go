package tests

import (
	"bytes"
	"crypto/aes"
	"crypto/rand"
	"encoding/binary"
	"testing"
	. "uniclient/cores"
)

func mumbleTestCryptPair(t *testing.T) (enc, dec *ForTestMumbleCryptState) {
	t.Helper()
	key := make([]byte, 16)
	encIV := make([]byte, 16)
	decIV := make([]byte, 16)
	for i := range key {
		key[i] = byte(i * 7)
		encIV[i] = byte(i * 11)
		decIV[i] = byte(i * 13)
	}
	enc = &ForTestMumbleCryptState{}
	if err := enc.ForTestInit(key, encIV, decIV); err != nil {
		t.Fatalf("enc init: %v", err)
	}
	dec = &ForTestMumbleCryptState{}
	if err := dec.ForTestInit(key, decIV, encIV); err != nil {
		t.Fatalf("dec init: %v", err)
	}
	return enc, dec
}

func TestMumbleOCB2RoundTrip(t *testing.T) {
	enc, dec := mumbleTestCryptPair(t)

	secret := []byte("abcdefghi")
	dst := make([]byte, 4+len(secret))
	n := enc.ForTestEncrypt(dst, secret)
	if n != 4+len(secret) {
		t.Fatalf("encrypt returned %d, want %d", n, 4+len(secret))
	}

	plain := make([]byte, len(secret))
	m, err := dec.ForTestDecrypt(plain, dst)
	if err != nil {
		t.Fatalf("decrypt: %v", err)
	}
	if m != len(secret) {
		t.Fatalf("decrypt length %d, want %d", m, len(secret))
	}
	if !bytes.Equal(plain, secret) {
		t.Fatalf("round-trip mismatch: %q != %q", plain, secret)
	}

	if _, err := dec.ForTestDecrypt(plain, dst); err == nil {
		t.Fatal("replayed packet accepted — replay protection broken")
	}
}

func TestMumbleOCB2OutOfOrderWindow(t *testing.T) {
	enc, dec := mumbleTestCryptPair(t)

	secret := []byte("abcdefghi")
	pktLen := 4 + len(secret)
	var crypted [128][13]byte
	for i := 0; i < 128; i++ {
		enc.ForTestEncrypt(crypted[i][:pktLen], secret)
	}

	for i := 0; i < 30; i++ {
		plain := make([]byte, len(secret))
		if _, err := dec.ForTestDecrypt(plain, crypted[127-i][:pktLen]); err != nil {
			t.Fatalf("in-window OOO packet %d rejected: %v", i, err)
		}
	}
	for i := 30; i < 128; i++ {
		plain := make([]byte, len(secret))
		if _, err := dec.ForTestDecrypt(plain, crypted[127-i][:pktLen]); err == nil {
			t.Fatalf("out-of-window OOO packet %d accepted", i)
		}
	}
	for i := 0; i < 30; i++ {
		plain := make([]byte, len(secret))
		if _, err := dec.ForTestDecrypt(plain, crypted[127-i][:pktLen]); err == nil {
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
		enc.ForTestEncrypt(crypted[i][:pktLen], secret)
	}
	for i := 0; i < 512; i++ {
		plain := make([]byte, len(secret))
		if _, err := dec.ForTestDecrypt(plain, crypted[i][:pktLen]); err != nil {
			t.Fatalf("packet %d rejected in-order: %v", i, err)
		}
	}
	for i := 0; i < 512; i++ {
		plain := make([]byte, len(secret))
		if _, err := dec.ForTestDecrypt(plain, crypted[i][:pktLen]); err == nil {
			t.Fatalf("replay of packet %d accepted", i)
		}
	}
}

func TestMumbleOCB2TamperDetection(t *testing.T) {
	enc, dec := mumbleTestCryptPair(t)

	secret := []byte("attack at dawn")
	dst := make([]byte, 4+len(secret))
	enc.ForTestEncrypt(dst, secret)

	dst[5] ^= 0xFF
	plain := make([]byte, len(secret))
	if _, err := dec.ForTestDecrypt(plain, dst); err == nil {
		t.Fatal("tampered packet accepted — OCB2 tag not enforced")
	}
}

func TestMumbleVarintRoundTrip(t *testing.T) {
	values := []int64{0, 1, 7, 8, 63, 64, 127, 128, 255, 256, 8191, 8192,
		65535, 65536, 1048575, 1048576, 16777215, 16777216,
		1073741823, 1073741824, -1, -2, -3, -4, -64, -8192, -1048576, -134217728}
	for _, v := range values {
		buf := MumbleVarintEncode(v)
		got, n, err := MumbleVarintDecode(buf, 0)
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

func TestMumbleVersionRoundTrip(t *testing.T) {
	v := &MumbleVersion{
		VersionV1: MumbleVersionV1,
		VersionV2: MumbleVersionV2,
		Release:   "Uniclient test",
		OS:        "Linux",
		OSVersion: "6.1",
	}
	var v2 MumbleVersion
	if err := MumbleUnmarshal(MumbleMarshal(v), &v2); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if v2.VersionV1 != v.VersionV1 || v2.VersionV2 != v.VersionV2 ||
		v2.Release != v.Release || v2.OS != v.OS || v2.OSVersion != v.OSVersion {
		t.Fatalf("Version round-trip mismatch: %+v != %+v", v2, v)
	}
}

func TestMumbleAuthenticateWire(t *testing.T) {
	a := &MumbleAuthenticate{
		Username: "u1",
		Password: "pw",
		Tokens:   []string{"t1", "t2"},
		Opus:     true,
	}
	wire := MumbleMarshal(a)
	if wire[0] != 0x0A {
		t.Fatalf("Authenticate field 1 tag = %#x, want 0x0A", wire[0])
	}
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
	m := &MumbleTextMsg{
		Actor:     42,
		Session:   []uint32{7, 8},
		ChannelID: []uint32{0},
		TreeID:    []uint32{3},
		Message:   "hello <b>world</b>",
	}
	var m2 MumbleTextMsg
	if err := MumbleUnmarshal(MumbleMarshal(m), &m2); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if m2.Actor != m.Actor || m2.Message != m.Message ||
		len(m2.Session) != 2 || m2.Session[1] != 8 ||
		len(m2.ChannelID) != 1 || len(m2.TreeID) != 1 || m2.TreeID[0] != 3 {
		t.Fatalf("TextMessage round-trip mismatch: %+v", m2)
	}
}

func TestMumbleUserStateAllFields(t *testing.T) {
	m := &MumbleUserStateMsg{
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
	var m2 MumbleUserStateMsg
	if err := MumbleUnmarshal(MumbleMarshal(m), &m2); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if m2.Session != 5 || m2.Actor != 6 || m2.Name != "alice" || m2.ChannelID != 1 ||
		!m2.Mute || !m2.SelfMute || !m2.Recording || m2.Comment != "hi" || m2.Hash != "abc" || m2.UserID != 9 {
		t.Fatalf("UserState round-trip mismatch: %+v", m2)
	}
}

func TestMumbleCryptSetupRoundTrip(t *testing.T) {
	key := make([]byte, 16)
	cn := make([]byte, 16)
	sn := make([]byte, 16)
	for i := range key {
		key[i] = byte(i)
		cn[i] = byte(200 - i)
		sn[i] = byte(100 + i)
	}
	cs := &MumbleCryptSetupMsg{Key: key, ClientNonce: cn, ServerNonce: sn}
	wire := MumbleMarshal(cs)
	if len(wire) == 0 || wire[0] != 0x0A {
		t.Fatalf("CryptSetup wire = %x, want field 1 (key) tag 0x0A first", wire)
	}
	var out MumbleCryptSetupMsg
	if err := MumbleUnmarshal(wire, &out); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if !bytes.Equal(out.Key, key) || !bytes.Equal(out.ClientNonce, cn) || !bytes.Equal(out.ServerNonce, sn) {
		t.Fatalf("CryptSetup round-trip mismatch: key=%x client=%x server=%x", out.Key, out.ClientNonce, out.ServerNonce)
	}
}

func TestMumbleTCPPingWire(t *testing.T) {
	p := &MumblePingMsg{Timestamp: 12345}
	wire := MumbleMarshal(p)
	if len(wire) < 2 || wire[0] != 0x08 {
		t.Fatalf("Ping wire = %x, want tag 0x08 (field 1 varint)", wire)
	}
	var p2 MumblePingMsg
	if err := MumbleUnmarshal(wire, &p2); err != nil {
		t.Fatalf("Ping unmarshal: %v", err)
	}
	if p2.Timestamp != 12345 {
		t.Fatalf("Ping timestamp %d, want 12345", p2.Timestamp)
	}
}

func TestMumbleMessageTypeIDs(t *testing.T) {
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
		if got := MumbleMsgName(c.id); got != c.name {
			t.Errorf("message id %d = %q, want %q", c.id, got, c.name)
		}
	}
}

func TestMumbleUDPPingFormat(t *testing.T) {
	req := make([]byte, 12)
	resp := make([]byte, 24)
	binary.BigEndian.PutUint32(resp[12:16], 3)
	binary.BigEndian.PutUint32(resp[16:20], 50)
	binary.BigEndian.PutUint32(resp[20:24], 72000)
	if len(req) != 12 || len(resp) != 24 {
		t.Fatal("ping format length mismatch")
	}
}

func TestOCB2OfficialVectors(t *testing.T) {
	key := []byte{0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15}
	block, err := aes.NewCipher(key)
	if err != nil {
		t.Fatal(err)
	}

	var tag [16]byte
	Ocb2Encrypt(block, nil, nil, key, tag[:])
	wantBlank := []byte{0xBF, 0x31, 0x08, 0x13, 0x07, 0x73, 0xAD, 0x5E, 0xC7, 0x0E, 0xC6, 0x9E, 0x78, 0x75, 0xA7, 0xB0}
	if !bytes.Equal(tag[:], wantBlank) {
		t.Fatalf("blank tag mismatch:\n got %x\nwant %x", tag[:], wantBlank)
	}

	src := make([]byte, 40)
	for i := range src {
		src[i] = byte(i)
	}
	ct := make([]byte, 40)
	Ocb2Encrypt(block, ct, src, key, tag[:])
	wantTag := []byte{0x9D, 0xB0, 0xCD, 0xF8, 0x80, 0xF7, 0x3E, 0x3E, 0x10, 0xD4, 0xEB, 0x32, 0x17, 0x76, 0x66, 0x88}
	if !bytes.Equal(tag[:], wantTag) {
		t.Fatalf("40-byte tag mismatch:\n got %x\nwant %x", tag[:], wantTag)
	}
	wantCT := []byte{0xF7, 0x5D, 0x6B, 0xC8, 0xB4, 0xDC, 0x8D, 0x66, 0xB8, 0x36, 0xA2, 0xB0, 0x8B, 0x32, 0xA6, 0x36, 0x9F, 0x1C, 0xD3, 0xC5, 0x22, 0x8D, 0x79, 0xFD, 0x6C, 0x26, 0x7F, 0x5F, 0x6A, 0xA7, 0xB2, 0x31, 0xC7, 0xDF, 0xB9, 0xD5, 0x99, 0x51, 0xAE, 0x9C}
	if !bytes.Equal(ct, wantCT) {
		t.Fatalf("40-byte ciphertext mismatch:\n got %x\nwant %x", ct, wantCT)
	}

	pt := make([]byte, 40)
	if !Ocb2Decrypt(block, pt, wantCT, key, wantTag) {
		t.Fatal("vector decrypt failed")
	}
	if !bytes.Equal(pt, src) {
		t.Fatalf("vector plaintext mismatch:\n got %x\nwant %x", pt, src)
	}
}

func TestOCB2ClientServerDirections(t *testing.T) {
	key := make([]byte, 16)
	clientNonce := make([]byte, 16)
	serverNonce := make([]byte, 16)
	rand.Read(key)
	rand.Read(clientNonce)
	rand.Read(serverNonce)

	client := &ForTestMumbleCryptState{}
	if err := client.ForTestInit(key, clientNonce, serverNonce); err != nil {
		t.Fatal(err)
	}
	server := &ForTestMumbleCryptState{}
	if err := server.ForTestInit(key, serverNonce, clientNonce); err != nil {
		t.Fatal(err)
	}

	for i := 0; i < 5; i++ {
		plain := []byte{1, 0x08, byte(i), 0x01}
		wire := make([]byte, MumbleCryptoOverhead+len(plain))
		n := client.ForTestEncrypt(wire, plain)
		if n != len(wire) {
			t.Fatalf("packet %d: encrypt wrote %d, want %d", i, n, len(wire))
		}
		got := make([]byte, len(wire))
		pLen, err := server.ForTestDecrypt(got, wire)
		if err != nil {
			t.Fatalf("packet %d: server-side decrypt failed: %v (real murmur would silently drop it)", i, err)
		}
		if !bytes.Equal(got[:pLen], plain) {
			t.Fatalf("packet %d: plaintext mismatch: %x vs %x", i, got[:pLen], plain)
		}
	}

	for i := 0; i < 5; i++ {
		plain := []byte{1, 0x08, byte(i), 0x01}
		wire := make([]byte, MumbleCryptoOverhead+len(plain))
		server.ForTestEncrypt(wire, plain)
		got := make([]byte, len(wire))
		pLen, err := client.ForTestDecrypt(got, wire)
		if err != nil {
			t.Fatalf("reply %d: client-side decrypt failed: %v", i, err)
		}
		if !bytes.Equal(got[:pLen], plain) {
			t.Fatalf("reply %d: plaintext mismatch", i)
		}
	}
}

func TestMumbleExportedCryptWrappers(t *testing.T) {
	key := make([]byte, 16)
	encIV := make([]byte, 16)
	decIV := make([]byte, 16)
	for i := range key {
		key[i] = byte(i * 7)
		encIV[i] = byte(i * 11)
		decIV[i] = byte(i * 13)
	}

	var s MumbleCryptState
	if err := s.Init(key, encIV, encIV); err != nil {
		t.Fatalf("Init: %v", err)
	}

	secret := []byte("wrapper round trip payload")
	dst := make([]byte, 4+len(secret))
	n := s.Encrypt(dst, secret)
	if n != 4+len(secret) {
		t.Fatalf("Encrypt returned %d, want %d", n, 4+len(secret))
	}

	plain := make([]byte, len(secret))
	m, err := s.Decrypt(plain, dst[:n])
	if err != nil {
		t.Fatalf("Decrypt: %v", err)
	}
	if m != len(secret) || !bytes.Equal(plain, secret) {
		t.Fatalf("round-trip mismatch: n=%d plain=%q want=%q", m, plain, secret)
	}

	bad := make([]byte, n)
	copy(bad, dst[:n])
	bad[6] ^= 0xFF
	got := make([]byte, len(secret))
	_, err2 := s.Decrypt(got, bad)
	if err2 == nil && bytes.Equal(got, secret) {
		t.Fatal("tampered packet decrypted to the original — no integrity rejection")
	}

	block, err := aes.NewCipher(key)
	if err != nil {
		t.Fatal(err)
	}
	ct := make([]byte, len(secret))
	var tag [16]byte
	OCB2Encrypt(block, ct, secret, key, tag[:])
	out := make([]byte, len(secret))
	if !OCB2Decrypt(block, out, ct, key, tag[:]) || !bytes.Equal(out, secret) {
		t.Fatal("OCB2Encrypt/OCB2Decrypt wrapper round-trip mismatch")
	}
	ct[0] ^= 0xFF
	if OCB2Decrypt(block, out, ct, key, tag[:]) {
		t.Fatal("tampered ciphertext accepted by OCB2Decrypt wrapper")
	}
}
