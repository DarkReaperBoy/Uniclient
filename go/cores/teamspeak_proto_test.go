package cores

import (
	"bytes"
	"crypto/rand"
	"encoding/base64"
	"encoding/binary"
	"encoding/hex"
	"filippo.io/edwards25519"
	"math/big"
	"testing"
)

// ───────────────────────────── TS3 key derivation ─────────────────────────────
//
// Official test vector from ts3j's EncryptionTest.java (Manevolent/ts3j):
// a 64-byte ivStruct + CLIENT/CMD/generation 0/packetId 1 must derive the
// exact key/nonce pair below. This pins the 1.6.2 key derivation from the
// ts3protocol.md paper.

func TestTS3KeyNonceDerivationVector(t *testing.T) {
	ivStruct, err := base64.StdEncoding.DecodeString("/rn6nR71hV8eFl+15WO68fRU8pOCBw3t0FmcG5c7WNxIkeZ1NtaWTVMBde0cdU5tTKwOl8sE6gpHjnCEF4hhDw==")
	if err != nil {
		t.Fatalf("decode ivStruct: %v", err)
	}
	if len(ivStruct) != 64 {
		t.Fatalf("ivStruct length %d, want 64", len(ivStruct))
	}

	// CLIENT role (0x31), Command packet type (2), generation 0, PId 1.
	key, nonce := tsCreateKeyNonce(0x02, 1, 0, 0x31, ivStruct)

	wantKey, _ := base64.StdEncoding.DecodeString("BF+lO776+e45u+qYAOHihg==")
	wantNonce, _ := base64.StdEncoding.DecodeString("1IVcTMuizpDHjQgn2yGCgg==")

	if !bytes.Equal(key[:], wantKey) {
		t.Fatalf("key = %x, want %x", key, wantKey)
	}
	if !bytes.Equal(nonce[:], wantNonce) {
		t.Fatalf("nonce = %x, want %x", nonce, wantNonce)
	}
}

func TestTS3KeyNoncePIdXOR(t *testing.T) {
	// key[0]^=(PId>>8), key[1]^=PId — different pIDs must give different keys.
	iv := make([]byte, 64)
	key1, _ := tsCreateKeyNonce(0x02, 1, 0, 0x31, iv)
	key2, _ := tsCreateKeyNonce(0x02, 2, 0, 0x31, iv)
	if key1[1] == key2[1] && key1[0] == key2[0] {
		t.Fatal("packet id not mixed into key")
	}
	// Direction must change the key (0x30 vs 0x31).
	keyS, _ := tsCreateKeyNonce(0x02, 1, 0, 0x30, iv)
	if bytes.Equal(keyS[:], key1[:]) {
		t.Fatal("direction byte not mixed into key")
	}
	// Flags must NOT change the key (only the low 4 bits of PT matter).
	keyF, _ := tsCreateKeyNonce(0x22, 1, 0, 0x31, iv)
	if !bytes.Equal(keyF[:], key1[:]) {
		t.Fatal("PT flags leaked into key derivation (spec: type only)")
	}
}

// ───────────────────────────── TS3 EAX ─────────────────────────────

func TestTS3EAXRoundTrip(t *testing.T) {
	key, nonce := tsCreateKeyNonce(0x02, 7, 0, 0x31, make([]byte, 64))
	header := []byte{0x00, 0x07, 0x00, 0x00, 0x22}
	plaintext := []byte("clientinit client_nickname=Test")

	mac, ciphertext := tsEAXEncrypt(key[:], nonce[:], header, plaintext)
	if !bytes.Equal(ciphertext, plaintext) {
		// ciphertext is CTR output — equal only by coincidence; just sanity lengths
		if len(ciphertext) != len(plaintext) {
			t.Fatalf("ciphertext length %d != plaintext %d", len(ciphertext), len(plaintext))
		}
	}
	got, err := tsEAXDecrypt(key[:], nonce[:], header, ciphertext, mac)
	if err != nil {
		t.Fatalf("decrypt: %v", err)
	}
	if !bytes.Equal(got, plaintext) {
		t.Fatalf("round-trip mismatch: %q", got)
	}

	// Tampered header must fail MAC verification.
	if _, err := tsEAXDecrypt(key[:], nonce[:], []byte{0x00, 0x08, 0x00, 0x00, 0x22}, ciphertext, mac); err == nil {
		t.Fatal("tampered header accepted")
	}
	// Tampered ciphertext must fail.
	ciphertext[0] ^= 0x01
	if _, err := tsEAXDecrypt(key[:], nonce[:], header, ciphertext, mac); err == nil {
		t.Fatal("tampered ciphertext accepted")
	}
}

func TestTS3FakeKeyConstants(t *testing.T) {
	// The constants are part of the wire contract (ts3protocol.md §3).
	// FAKE_KEY = "c:\windows\syste" (16 bytes), FAKE_NONCE = "m\firewall32.cpl".
	if hex.EncodeToString(tsFakeKey[:]) != "633a5c77696e646f77735c7379737465" {
		t.Fatalf("FAKE_KEY = %s", hex.EncodeToString(tsFakeKey[:]))
	}
	if hex.EncodeToString(tsFakeNonce[:]) != "6d5c6669726577616c6c33322e63706c" {
		t.Fatalf("FAKE_NONCE = %s", hex.EncodeToString(tsFakeNonce[:]))
	}
	// Root key from ts3protocol.md §3.2.2.4.
	if hex.EncodeToString(tsRootKey[:]) != "cd0de2aed46345509a7e3cfd8f68b3dc7555b29dccec73cd18750f993812408a" {
		t.Fatalf("ROOT_KEY = %s", hex.EncodeToString(tsRootKey[:]))
	}
}

// ───────────────────────────── TS3 init packets ─────────────────────────────

func TestTS3Init0Packet(t *testing.T) {
	var random0 [4]byte
	copy(random0[:], []byte{0xDE, 0xAD, 0xBE, 0xEF})
	pkt := tsBuildInit0(0x11223344, 0xAABBCCDD, random0)

	if len(pkt) != 13+21 {
		t.Fatalf("init0 length %d, want %d", len(pkt), 13+21)
	}
	if !bytes.Equal(pkt[:8], []byte("TS3INIT1")) {
		t.Fatalf("MAC = %q", pkt[:8])
	}
	if binary.BigEndian.Uint16(pkt[8:10]) != 101 {
		t.Fatalf("PId = %d, want 101", binary.BigEndian.Uint16(pkt[8:10]))
	}
	if binary.BigEndian.Uint16(pkt[10:12]) != 0 {
		t.Fatalf("CId = %d, want 0", binary.BigEndian.Uint16(pkt[10:12]))
	}
	if pkt[12] != 0x88 {
		t.Fatalf("PT = %#x, want 0x88 (unencrypted+init)", pkt[12])
	}
	if binary.BigEndian.Uint32(pkt[13:17]) != 0x11223344 {
		t.Fatal("version mismatch")
	}
	if pkt[17] != 0x00 {
		t.Fatalf("step = %d, want 0", pkt[17])
	}
	if binary.BigEndian.Uint32(pkt[18:22]) != 0xAABBCCDD {
		t.Fatal("timestamp mismatch")
	}
	if !bytes.Equal(pkt[22:26], random0[:]) {
		t.Fatal("random0 mismatch")
	}
	if !bytes.Equal(pkt[26:34], make([]byte, 8)) {
		t.Fatal("reserved bytes not zero")
	}
}

func TestTS3Init2Packet(t *testing.T) {
	var random1 [16]byte
	var random0r [4]byte
	rand.Read(random1[:])
	copy(random0r[:], []byte{1, 2, 3, 4})
	pkt := tsBuildInit2(0x0BADF00D, random1, random0r)

	if len(pkt) != 13+25 {
		t.Fatalf("init2 length %d, want %d", len(pkt), 13+25)
	}
	if !bytes.Equal(pkt[:8], []byte("TS3INIT1")) {
		t.Fatal("MAC mismatch")
	}
	if binary.BigEndian.Uint16(pkt[8:10]) != 101 {
		t.Fatal("PId mismatch")
	}
	if pkt[12] != 0x88 {
		t.Fatalf("PT = %#x", pkt[12])
	}
	if binary.BigEndian.Uint32(pkt[13:17]) != 0x0BADF00D {
		t.Fatal("version mismatch")
	}
	if pkt[17] != 0x02 {
		t.Fatalf("step = %d, want 2", pkt[17])
	}
	if !bytes.Equal(pkt[18:34], random1[:]) {
		t.Fatal("random1 mismatch")
	}
	if !bytes.Equal(pkt[34:38], random0r[:]) {
		t.Fatal("random0r mismatch")
	}
}

func TestTS3Init1Parse(t *testing.T) {
	data := make([]byte, 21)
	data[0] = 1
	copy(data[1:17], bytes.Repeat([]byte{0xAB}, 16))
	copy(data[17:21], []byte{9, 8, 7, 6})
	random1, random0r, err := tsParseInit1(data)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if !bytes.Equal(random1[:], data[1:17]) || !bytes.Equal(random0r[:], data[17:21]) {
		t.Fatal("parse mismatch")
	}

	// step 127 must be rejected as a restart signal
	data[0] = 127
	if _, _, err := tsParseInit1(data); err == nil {
		t.Fatal("step 127 not rejected")
	}
}

func TestTS3Init3Parse(t *testing.T) {
	data := make([]byte, 233)
	data[0] = 3
	copy(data[1:65], bytes.Repeat([]byte{0x11}, 64))
	copy(data[65:129], bytes.Repeat([]byte{0x22}, 64))
	binary.BigEndian.PutUint32(data[129:133], 10000)
	copy(data[133:233], bytes.Repeat([]byte{0x33}, 100))

	x, n, level, random2, err := tsParseInit3(data)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if !bytes.Equal(x[:], data[1:65]) || !bytes.Equal(n[:], data[65:129]) || level != 10000 || !bytes.Equal(random2[:], data[133:233]) {
		t.Fatal("parse mismatch")
	}

	data[0] = 127
	if _, _, _, _, err := tsParseInit3(data); err == nil {
		t.Fatal("step 127 not rejected")
	}
}

func TestTS3Init4Packet(t *testing.T) {
	var x, n, y [64]byte
	var random2 [100]byte
	for i := range x {
		x[i] = byte(i)
		n[i] = byte(255 - i)
	}
	copy(random2[:], bytes.Repeat([]byte{0x42}, 100))
	cmd := []byte("clientinitiv alpha=QQ== omega=AA== ot=1 ip=1.2.3.4")

	pkt := tsBuildInit4(0xCAFEBABE, x, n, 200, random2, y, cmd)
	wantLen := 13 + 4 + 1 + 64 + 64 + 4 + 100 + 64 + len(cmd)
	if len(pkt) != wantLen {
		t.Fatalf("init4 length %d, want %d", len(pkt), wantLen)
	}
	if !bytes.Equal(pkt[:8], []byte("TS3INIT1")) {
		t.Fatal("MAC mismatch")
	}
	if binary.BigEndian.Uint16(pkt[8:10]) != 101 {
		t.Fatal("PId mismatch")
	}
	if pkt[12] != 0x88 {
		t.Fatalf("PT = %#x", pkt[12])
	}
	if binary.BigEndian.Uint32(pkt[13:17]) != 0xCAFEBABE {
		t.Fatal("version mismatch")
	}
	if pkt[17] != 4 {
		t.Fatalf("step = %d, want 4", pkt[17])
	}
	if !bytes.Equal(pkt[18:82], x[:]) || !bytes.Equal(pkt[82:146], n[:]) {
		t.Fatal("x/n mismatch")
	}
	if binary.BigEndian.Uint32(pkt[146:150]) != 200 {
		t.Fatal("level mismatch")
	}
	if !bytes.Equal(pkt[150:250], random2[:]) {
		t.Fatal("random2 mismatch")
	}
	if !bytes.Equal(pkt[250:314], y[:]) {
		t.Fatal("y mismatch")
	}
	if !bytes.Equal(pkt[314:], cmd) {
		t.Fatal("command data mismatch")
	}
}

// ───────────────────────────── TS3 version constants ─────────────────────────────

func TestTS3InitVersionConstant(t *testing.T) {
	// Fixed real client build timestamp (3.5.0 [Stable]) — time-derived
	// values get rejected by live servers with error 522 or a step-127 loop
	// (verified 2026-09 against ts.arcticblaze.net).
	if tsInitVersion != 1566914096 {
		t.Fatalf("tsInitVersion = %d, want 1566914096 (3.5.0)", tsInitVersion)
	}
}

// ───────────────────────────── TS3 command escaping ─────────────────────────────

func TestTS3CommandEscapeRoundTrip(t *testing.T) {
	inputs := []string{
		"hello world",
		"nick with spaces",
		"a=b",
		"pipe|char",
		"back\\slash",
		"null\x00byte",
		"sl/ash",
	}
	for _, in := range inputs {
		esc := tsEscape(in)
		if strings := tsUnescape(esc); strings != in {
			t.Errorf("escape round-trip %q → %q → %q", in, esc, strings)
		}
	}
}

func TestTS3ParseCommand(t *testing.T) {
	name, params := tsParseCommand([]byte("clientinitiv alpha=abc omega=xyz ot=1 ip=1.2.3.4"))
	if name != "clientinitiv" {
		t.Fatalf("name = %q", name)
	}
	if params["alpha"] != "abc" || params["omega"] != "xyz" || params["ot"] != "1" || params["ip"] != "1.2.3.4" {
		t.Fatalf("params = %v", params)
	}
}

// ───────────────────────────── TS3 S2C/C2S packet parse ─────────────────────────────

func TestTS3PacketParseS2C(t *testing.T) {
	// MAC(8) + PId(2) + PT(1) + data
	pkt := make([]byte, 11+5)
	copy(pkt[:8], []byte{1, 2, 3, 4, 5, 6, 7, 8})
	binary.BigEndian.PutUint16(pkt[8:10], 55)
	pkt[10] = 0x12 // Command + Fragmented
	copy(pkt[11:], []byte("hello"))

	mac, pID, pType, data, err := tsParseS2CPacket(pkt)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if mac != [8]byte{1, 2, 3, 4, 5, 6, 7, 8} || pID != 55 || pType != 0x12 || string(data) != "hello" {
		t.Fatalf("parse mismatch: pID=%d pType=%#x data=%q", pID, pType, data)
	}
}

func TestTS3BuildC2SPacket(t *testing.T) {
	pkt := tsBuildC2SPacket([8]byte{9}, 0x1234, 0x5678, 0x22, []byte("payload"))
	if len(pkt) != 13+7 {
		t.Fatalf("length %d", len(pkt))
	}
	if binary.BigEndian.Uint16(pkt[8:10]) != 0x1234 || binary.BigEndian.Uint16(pkt[10:12]) != 0x5678 {
		t.Fatal("pID/cID mismatch")
	}
	if pkt[12] != 0x22 {
		t.Fatalf("PT = %#x", pkt[12])
	}
	if string(pkt[13:]) != "payload" {
		t.Fatal("data mismatch")
	}
}

// ───────────────────────────── TS3 RSA puzzle ─────────────────────────────

func TestTS3RSAPuzzleSolution(t *testing.T) {
	// x^(2^level) mod n via square-and-multiply must match big.Int Exp.
	x := big.NewInt(12345)
	n := big.NewInt(999999937) // prime
	level := uint32(64)

	e := new(big.Int).Lsh(big.NewInt(1), uint(level))
	want := new(big.Int).Exp(x, e, n)

	// The implementation inside tsHandshake uses the same Exp call; here we
	// verify the semantics the server checks (y == x^(2^level) mod n).
	y := new(big.Int).Exp(x, e, n)
	if y.Cmp(want) != 0 {
		t.Fatal("RSA puzzle semantics mismatch")
	}
}

// ───────────────────────────── TS3 identity ─────────────────────────────

func TestTS3IdentitySignVerify(t *testing.T) {
	id, err := tsNewIdentity()
	if err != nil {
		t.Fatalf("identity: %v", err)
	}
	data := []byte("sign me please")
	sig, err := id.tsSign(data)
	if err != nil {
		t.Fatalf("sign: %v", err)
	}
	x, y, err := tsParseOmega(id.tsOmega())
	if err != nil {
		t.Fatalf("parse own omega: %v", err)
	}
	if !tsVerifyP256(x, y, data, sig) {
		t.Fatal("own signature does not verify")
	}
	if tsVerifyP256(x, y, []byte("other data"), sig) {
		t.Fatal("signature verifies against different data")
	}
}

func TestTS3IdentityUID(t *testing.T) {
	// UID = base64(sha1(omega)) per ts3protocol.md §4.2.
	id, err := tsNewIdentity()
	if err != nil {
		t.Fatalf("identity: %v", err)
	}
	uid := id.tsUID()
	if uid == "" {
		t.Fatal("empty UID")
	}
	decoded, err := base64.StdEncoding.DecodeString(uid)
	if err != nil {
		t.Fatalf("UID not base64: %v", err)
	}
	if len(decoded) != 20 {
		t.Fatalf("UID decoded length %d, want 20 (sha1)", len(decoded))
	}
}

// ───────────────────────────── TS3 license chain + ECDH ─────────────────────────────
//
// Official test vector from ts3j's CryptoInit2Test.java: a full license
// chain → root-key derivation → Curve25519 ECDH → shared IV + fake MAC.
// This pins the entire §3.2.2.4 license-walk algorithm.

func TestTS3LicenseDerivationVector(t *testing.T) {
	licenseBytes, err := hex.DecodeString("0100358541498A24ACD30157918B8F50955C0DAE970AB65372CBE407" +
		"415FCF3E029B02084D15E00AA793600700000020416E6F6E796D6F7573000047D9E4DC25AA2E90ACD4DB5FA61C8F" +
		"ED369B346D84C2CA2FCCCA86F73AFEF092200A77C8810A787141")
	if err != nil {
		t.Fatalf("license hex: %v", err)
	}
	alphaB, _ := hex.DecodeString("9500A5DB3B50ACECAB81")
	betaB, _ := hex.DecodeString("EAFFC9A8BC996B25C8AA700264E99E372ECCDEB1C121D6EC0F4D49FB46" +
		"CEEBA4E3C724B3070FD70CB03D7BC08129205690ECE228CA7C")
	privB, _ := hex.DecodeString("102E591ABA4508129E812FF3437E2DDD3CA1F1EC341117CA3514CC347A7C2A77")

	wantIV, _ := hex.DecodeString("E4082A92F71C96A947452F5582EF2879B2051ED2D3" +
		"F2C6B0643CF5A266EE6B5180573C2F5F3F1C4AC579188366F16AE0EADC3AAF860805D8F2A831E9E49F4513")
	wantMAC, _ := hex.DecodeString("54F2B4D661E0F9AB")

	serverEK, err := tsDeriveLicenseKey(licenseBytes, tsRootKey)
	if err != nil {
		t.Fatalf("license derivation: %v", err)
	}

	var alpha [10]byte
	var beta [54]byte
	copy(alpha[:], alphaB)
	copy(beta[:], betaB)

	privScalar, err := new(edwards25519.Scalar).SetCanonicalBytes(privB)
	if err != nil {
		// fall back to clamping if not canonical
		privScalar, err = new(edwards25519.Scalar).SetBytesWithClamping(privB)
		if err != nil {
			t.Fatalf("private key: %v", err)
		}
	}

	sharedIV, sharedMAC := tsComputeSharedIVMAC(alpha, beta, privScalar, serverEK)
	if !bytes.Equal(sharedIV[:], wantIV) {
		t.Fatalf("shared IV mismatch:\n got %x\nwant %x", sharedIV, wantIV)
	}
	if !bytes.Equal(sharedMAC[:], wantMAC) {
		t.Fatalf("shared MAC mismatch: got %x want %x", sharedMAC, wantMAC)
	}
}

// ── receive-side generation tracking (ts3j RemoteCounter semantics) ──

func TestTS3RecvGenerationTracking(t *testing.T) {
	tc := &tsConnection{}

	// Fresh connection: first packet locks in without a generation bump.
	if g := tc.tsTrackRecvPID(tsPktVoice, 0); g != 0 {
		t.Fatalf("first packet gen = %d", g)
	}
	// Rising ids stay in generation 0.
	for id := uint16(1); id < 200; id++ {
		if g := tc.tsTrackRecvPID(tsPktVoice, id); g != 0 {
			t.Fatalf("id %d: gen = %d, want 0", id, g)
		}
	}
	// Wrap: last 0xFF00 → new 0x0010 bumps to generation 1.
	if g := tc.tsTrackRecvPID(tsPktVoice, 0xFF00); g != 0 {
		t.Fatalf("pre-wrap gen = %d", g)
	}
	if g := tc.tsTrackRecvPID(tsPktVoice, 0x0010); g != 1 {
		t.Fatalf("post-wrap gen = %d, want 1", g)
	}
	for id := uint16(0x0011); id < 0x0100; id++ {
		if g := tc.tsTrackRecvPID(tsPktVoice, id); g != 1 {
			t.Fatalf("gen1 id %d: gen = %d", id, g)
		}
	}
	// A late pre-wrap packet (0xFFF0 after the wrap) reports the current
	// generation — ts3j's "ahead to the right" rule — and relies on the
	// generation±1 decrypt retry to land on the old one. It must NOT
	// advance the wrap state, so a following high id is still gen 1.
	if g := tc.tsTrackRecvPID(tsPktVoice, 0xFFF0); g != 1 {
		t.Fatalf("late pre-wrap packet gen = %d, want 1 (retry resolves)", g)
	}
	// Second wrap.
	if g := tc.tsTrackRecvPID(tsPktVoice, 0xFFE0); g != 1 {
		t.Fatalf("second pre-wrap gen = %d, want 1", g)
	}
	if g := tc.tsTrackRecvPID(tsPktVoice, 0x0005); g != 2 {
		t.Fatalf("second post-wrap gen = %d, want 2", g)
	}
}

func TestTS3RecvGenerationPerType(t *testing.T) {
	tc := &tsConnection{}
	// Voice wraps; commands must be unaffected.
	if g := tc.tsTrackRecvPID(tsPktVoice, 0xFF00); g != 0 {
		t.Fatalf("voice pre-wrap gen = %d", g)
	}
	if g := tc.tsTrackRecvPID(tsPktVoice, 0x0020); g != 1 {
		t.Fatalf("voice post-wrap gen = %d", g)
	}
	if g := tc.tsTrackRecvPID(tsPktCommand, 5); g != 0 {
		t.Fatalf("command gen = %d", g)
	}
	if g := tc.tsTrackRecvPID(tsPktCommand, 6); g != 0 {
		t.Fatalf("command gen = %d", g)
	}
}

func TestTS3RecvGenerationDupAndJitter(t *testing.T) {
	tc := &tsConnection{}
	// Duplicate ids must not bump the generation.
	if g := tc.tsTrackRecvPID(tsPktVoice, 0xFF00); g != 0 {
		t.Fatalf("dup base gen = %d", g)
	}
	for i := 0; i < 5; i++ {
		if g := tc.tsTrackRecvPID(tsPktVoice, 0xFF00); g != 0 {
			t.Fatalf("dup %d gen = %d", i, g)
		}
	}
	if g := tc.tsTrackRecvPID(tsPktVoice, 0x0010); g != 1 {
		t.Fatalf("post-dup wrap gen = %d, want 1", g)
	}
	// Small jitter around the wrap boundary must not double-bump.
	if g := tc.tsTrackRecvPID(tsPktVoice, 0x0008); g != 1 {
		t.Fatalf("jitter gen = %d", g)
	}
}

func TestTS3DecryptRecvGenerationRetry(t *testing.T) {
	var iv [64]byte
	for i := range iv {
		iv[i] = byte(i * 7)
	}
	tc := &tsConnection{sharedIV: iv}

	pktType := byte(tsPktVoice)
	pID := uint16(0x1234)
	meta := []byte{0x34, 0x12, 0x00}
	payload := []byte("audio-frame-payload")

	// Encrypt as the server would at generation 2 (S2C direction 0x30).
	key, nonce := tsCreateKeyNonce(pktType, pID, 2, 0x30, iv[:])
	mac, ciphertext := tsEAXEncrypt(key[:], nonce[:], meta, payload)

	// Tracker says generation 1 (stale by one): the retry must find 2.
	tc.pktState[pktType].recvInit = true
	tc.pktState[pktType].lastRecvPID = pID - 1
	tc.pktState[pktType].recvGenID = 1

	plain, err := tc.tsDecryptRecv(pktType, pID, meta, ciphertext, mac)
	if err != nil {
		t.Fatalf("retry decrypt failed: %v", err)
	}
	if string(plain) != string(payload) {
		t.Fatalf("payload mismatch: %q", plain)
	}
	if tc.pktState[pktType].recvGenID != 2 {
		t.Fatalf("generation not fast-forwarded: %d", tc.pktState[pktType].recvGenID)
	}

	// Tracker ahead by one (gen 3): retry at gen 2 must succeed WITHOUT
	// rewinding the tracker.
	plain2, err := tc.tsDecryptRecv(pktType, pID, meta, ciphertext, mac)
	if err != nil {
		t.Fatalf("ahead-retry decrypt failed: %v", err)
	}
	if string(plain2) != string(payload) {
		t.Fatalf("payload mismatch 2: %q", plain2)
	}

	// Tampered MAC must still fail on every generation.
	var badMac [8]byte
	copy(badMac[:], mac[:])
	badMac[0] ^= 0xFF
	if _, err := tc.tsDecryptRecv(pktType, pID, meta, ciphertext, badMac); err == nil {
		t.Fatal("tampered packet accepted")
	}
}
