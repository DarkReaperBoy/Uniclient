package tests

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/sha512"
	"encoding/base64"
	"encoding/binary"
	"fmt"
	"math/big"
	"net"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	"filippo.io/edwards25519"

	. "uniclient/cores"
	"uniclient/utils"
)

var tsScriptedInitMAC = [8]byte{'T', 'S', '3', 'I', 'N', 'I', 'T', '1'}

const (
	tsScriptedPktInit      = 0x08
	tsScriptedPktAck       = 0x06
	tsScriptedPktPing      = 0x04
	tsScriptedPktPong      = 0x05
	tsScriptedPktCommandLo = 0x03
	tsScriptedFlagUnenc    = 0x80
)

const tsScriptedLevel = uint32(8)

type tsScriptedConfig struct {
	ServerName     string
	ClientID       int
	ChannelLines   []string
	OmitServerName bool
	FloodCommands  int
}

type tsScriptedGen struct {
	init bool
	last uint16
	gen  uint32
}

type tsCmdPkt struct {
	pID   uint16
	flags byte
}

type tsScriptedServer struct {
	conn *net.UDPConn
	addr string

	p256     *ecdsa.PrivateKey
	omegaB64 string

	rootScalar *edwards25519.Scalar

	beta     [54]byte
	alpha    [10]byte
	sharedIV [64]byte

	random0  [4]byte
	random1  [16]byte
	init3X   [64]byte
	init3N   [64]byte
	init3Rnd [100]byte

	clientOmegaX *big.Int
	clientOmegaY *big.Int

	wireMu   sync.Mutex
	client   *net.UDPAddr
	cryptoOn bool
	cmdPID   uint16
	ackPID   uint16
	recvGen  [9]tsScriptedGen

	mu             sync.Mutex
	cfg            tsScriptedConfig
	respond        func(string) []string
	received       chan string
	clientinitLine string
	init2EchoValid bool
	init4EchoValid bool
	init4YValid    bool
	ekProofValid   bool
	ackedCount     int

	voiceCount int
	lastVoice  []byte
	pongCount  int
	cmdPkts    []tsCmdPkt

	fragActive     bool
	fragBuf        []byte
	fragCompressed bool

	wg sync.WaitGroup
}

func startTSScriptedServer(tb testing.TB, cfg tsScriptedConfig) *tsScriptedServer {
	tb.Helper()
	conn, err := net.ListenUDP("udp", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1), Port: 0})
	if err != nil {
		tb.Fatalf("listen udp: %v", err)
	}
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		conn.Close()
		tb.Fatalf("gen p256: %v", err)
	}
	seed := make([]byte, 32)
	if _, err := rand.Read(seed); err != nil {
		conn.Close()
		tb.Fatalf("read seed: %v", err)
	}
	rootScalar, err := new(edwards25519.Scalar).SetBytesWithClamping(seed)
	if err != nil {
		conn.Close()
		tb.Fatalf("root scalar: %v", err)
	}
	if cfg.ServerName == "" && !cfg.OmitServerName {
		cfg.ServerName = "Scripted HQ"
	}
	if cfg.ClientID == 0 {
		cfg.ClientID = 1
	}
	s := &tsScriptedServer{
		conn:       conn,
		addr:       conn.LocalAddr().String(),
		p256:       key,
		rootScalar: rootScalar,
		cfg:        cfg,
		received:   make(chan string, 64),
		omegaB64:   tsScriptedOmega(key.PublicKey.X, key.PublicKey.Y),
	}
	rand.Read(s.beta[:])
	s.wg.Add(1)
	go s.loop()
	tb.Cleanup(s.Close)
	return s
}

func (s *tsScriptedServer) Addr() string { return s.addr }

func (s *tsScriptedServer) Close() {
	s.conn.Close()
	s.wg.Wait()
}

func (s *tsScriptedServer) SetResponder(fn func(string) []string) {
	s.mu.Lock()
	s.respond = fn
	s.mu.Unlock()
}

type tsScriptedQueue struct {
	mu   sync.Mutex
	next [][]string
}

func (q *tsScriptedQueue) add(lines ...string) {
	q.mu.Lock()
	q.next = append(q.next, lines)
	q.mu.Unlock()
}

func (q *tsScriptedQueue) take() []string {
	q.mu.Lock()
	defer q.mu.Unlock()
	if len(q.next) == 0 {
		return nil
	}
	group := q.next[0]
	q.next = q.next[1:]
	return group
}

func (s *tsScriptedServer) Push(line string) {
	s.sendCommand([]byte(line))
}

func (s *tsScriptedServer) PushAtGen(gen uint32, line string) {
	s.sendCommandGen(gen, []byte(line))
}

func (s *tsScriptedServer) PushAtPID(pID uint16, line string) {
	s.sendCmdPkt(pID, byte(TsPktCommand)|TsFlagNewprotocol, []byte(line))
}

func (s *tsScriptedServer) NextPID() uint16 {
	s.wireMu.Lock()
	defer s.wireMu.Unlock()
	return s.cmdPID
}

func (s *tsScriptedServer) PushPing(pingID uint16) {
	pkt := make([]byte, 11)
	binary.BigEndian.PutUint16(pkt[8:10], pingID)
	pkt[10] = tsScriptedPktPing | tsScriptedFlagUnenc
	s.sendRaw(pkt)
}

func (s *tsScriptedServer) ClientInitLine() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.clientinitLine
}

func (s *tsScriptedServer) Init2EchoValid() bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.init2EchoValid
}

func (s *tsScriptedServer) Init4YValid() bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.init4YValid
}

func (s *tsScriptedServer) EKProofValid() bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.ekProofValid
}

func (s *tsScriptedServer) AckedCount() int {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.ackedCount
}

func (s *tsScriptedServer) SharedIV() [64]byte {
	s.wireMu.Lock()
	defer s.wireMu.Unlock()
	return s.sharedIV
}

func (s *tsScriptedServer) VoiceCount() int {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.voiceCount
}

func (s *tsScriptedServer) LastVoicePayload() []byte {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := make([]byte, len(s.lastVoice))
	copy(out, s.lastVoice)
	return out
}

func (s *tsScriptedServer) PongCount() int {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.pongCount
}

func (s *tsScriptedServer) CmdPackets() []tsCmdPkt {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := make([]tsCmdPkt, len(s.cmdPkts))
	copy(out, s.cmdPkts)
	return out
}

func (s *tsScriptedServer) ResetCmdPackets() {
	s.mu.Lock()
	s.cmdPkts = nil
	s.mu.Unlock()
}

func (s *tsScriptedServer) WaitCommand(t *testing.T, prefix string) string {
	t.Helper()
	deadline := time.After(2 * time.Second)
	for {
		select {
		case line := <-s.received:
			if strings.HasPrefix(line, prefix) {
				return line
			}
		case <-deadline:
			t.Fatalf("scripted server never received a command starting with %q", prefix)
		}
	}
}

func (s *tsScriptedServer) loop() {
	defer s.wg.Done()
	buf := make([]byte, 4096)
	for {
		n, from, err := s.conn.ReadFromUDP(buf)
		if err != nil {
			return
		}
		pkt := make([]byte, n)
		copy(pkt, buf[:n])
		s.wireMu.Lock()
		s.client = from
		s.wireMu.Unlock()
		s.handle(pkt)
	}
}

func (s *tsScriptedServer) handle(raw []byte) {
	if len(raw) < 13 {
		return
	}
	var mac [8]byte
	copy(mac[:], raw[:8])
	pID := binary.BigEndian.Uint16(raw[8:10])
	pType := raw[12]
	data := raw[13:]
	flags := pType & 0xf0
	typ := pType & 0x0f
	switch typ {
	case TsPktVoice:
		s.handleC2SVoice(pID, mac, raw, data)
	case tsScriptedPktInit:
		if len(data) < 5 {
			return
		}
		switch data[4] {
		case 0x00:
			s.handleInit0(data)
		case 0x02:
			s.handleInit2(data)
		case 0x04:
			s.handleInit4(data)
		}
	case TsPktCommand, tsScriptedPktCommandLo:
		s.handleC2SCommand(typ, pID, flags, mac, raw, data)
	case tsScriptedPktAck:
		s.handleC2SAck(pID, mac, raw, data)
	case tsScriptedPktPong:
		s.mu.Lock()
		s.pongCount++
		s.mu.Unlock()
	case tsScriptedPktPing:
	}
}

func (s *tsScriptedServer) handleInit0(data []byte) {
	copy(s.random0[:], data[9:13])
	rand.Read(s.random1[:])
	out := make([]byte, 21)
	out[0] = 0x01
	copy(out[1:17], s.random1[:])
	copy(out[17:21], s.random0[:])
	s.sendInit(out)
}

func (s *tsScriptedServer) handleInit2(data []byte) {
	if len(data) < 25 {
		return
	}
	var r1 [16]byte
	var r0r [4]byte
	copy(r1[:], data[5:21])
	copy(r0r[:], data[21:25])
	s.mu.Lock()
	s.init2EchoValid = r1 == s.random1 && r0r == s.random0
	s.mu.Unlock()
	rand.Read(s.init3X[:])
	rand.Read(s.init3N[:])
	s.init3N[63] |= 0x01
	s.init3N[0] |= 0x80
	rand.Read(s.init3Rnd[:])
	out := make([]byte, 233)
	out[0] = 0x03
	copy(out[1:65], s.init3X[:])
	copy(out[65:129], s.init3N[:])
	binary.BigEndian.PutUint32(out[129:133], tsScriptedLevel)
	copy(out[133:233], s.init3Rnd[:])
	s.sendInit(out)
}

func (s *tsScriptedServer) handleInit4(data []byte) {
	if len(data) < 301 {
		return
	}
	var x, n, y [64]byte
	var r2 [100]byte
	copy(x[:], data[5:69])
	copy(n[:], data[69:133])
	level := binary.BigEndian.Uint32(data[133:137])
	copy(r2[:], data[137:237])
	copy(y[:], data[237:301])
	echoOK := x == s.init3X && n == s.init3N && r2 == s.init3Rnd && level == tsScriptedLevel
	eBig := new(big.Int).Lsh(big.NewInt(1), uint(level))
	yWant := new(big.Int).Exp(new(big.Int).SetBytes(x[:]), eBig, new(big.Int).SetBytes(n[:]))
	s.mu.Lock()
	s.init4EchoValid = echoOK
	s.init4YValid = echoOK && yWant.Cmp(new(big.Int).SetBytes(y[:])) == 0
	s.mu.Unlock()
	if len(data) > 301 {
		s.handleClientInitIV(data[301:])
	}
	s.sendInitivExpand2()
}

func (s *tsScriptedServer) handleClientInitIV(cmd []byte) {
	name, params := TsParseCommand(cmd)
	if name != "clientinitiv" {
		return
	}
	alpha, err := base64.StdEncoding.DecodeString(params["alpha"])
	if err != nil || len(alpha) != 10 {
		return
	}
	copy(s.alpha[:], alpha)
	s.clientOmegaX, s.clientOmegaY, _ = TsParseOmega(params["omega"])
}

func (s *tsScriptedServer) sendInitivExpand2() {
	license := []byte{0x01}
	licHash := sha256.Sum256(license)
	proof, err := ecdsa.SignASN1(rand.Reader, s.p256, licHash[:])
	if err != nil {
		return
	}
	root := new(edwards25519.Point).ScalarBaseMult(s.rootScalar).Bytes()
	line := "initivexpand2 l=" + TsEscape(base64.StdEncoding.EncodeToString(license)) +
		" beta=" + TsEscape(base64.StdEncoding.EncodeToString(s.beta[:])) +
		" omega=" + TsEscape(s.omegaB64) +
		" proof=" + TsEscape(base64.StdEncoding.EncodeToString(proof)) +
		" ot=1 root=" + TsEscape(base64.StdEncoding.EncodeToString(root))
	s.sendFakeCommand([]byte(line))
}

func (s *tsScriptedServer) handleClientek(pID uint16, mac [8]byte, raw, data []byte) {
	meta := raw[8:13]
	plain, err := TsEAXDecrypt(TsFakeKey[:], TsFakeNonce[:], meta, data, mac)
	if err != nil {
		return
	}
	name, params := TsParseCommand(plain)
	if name != "clientek" {
		return
	}
	ekBytes, err := base64.StdEncoding.DecodeString(params["ek"])
	if err != nil || len(ekBytes) != 32 {
		return
	}
	proof, err := base64.StdEncoding.DecodeString(params["proof"])
	if err != nil {
		return
	}
	ekPub, err := new(edwards25519.Point).SetBytes(ekBytes)
	if err != nil {
		return
	}
	proofData := make([]byte, 32+54)
	copy(proofData[:32], ekBytes)
	copy(proofData[32:], s.beta[:])
	proofOK := s.clientOmegaX != nil && TsVerifyP256(s.clientOmegaX, s.clientOmegaY, proofData, proof)
	shared := new(edwards25519.Point).ScalarMult(s.rootScalar, ekPub)
	iv := sha512.Sum512(shared.Bytes())
	for i := 0; i < 10; i++ {
		iv[i] ^= s.alpha[i]
	}
	for i := 0; i < 54; i++ {
		iv[i+10] ^= s.beta[i]
	}
	s.wireMu.Lock()
	copy(s.sharedIV[:], iv[:])
	s.cryptoOn = true
	s.wireMu.Unlock()
	s.mu.Lock()
	s.ekProofValid = proofOK
	s.mu.Unlock()
}

func (s *tsScriptedServer) trackGen(typ byte, pID uint16) uint32 {
	st := &s.recvGen[typ&0x0f]
	if !st.init {
		st.init = true
		st.last = pID
		return st.gen
	}
	if pID == st.last {
		return st.gen
	}
	if pID > st.last {
		st.last = pID
	} else if st.last > 0xC000 && pID < 0x4000 {
		st.gen++
		st.last = pID
	}
	return st.gen
}

func (s *tsScriptedServer) decryptC2S(typ byte, pID uint16, gen uint32, meta, data []byte, mac [8]byte) ([]byte, error) {
	s.wireMu.Lock()
	iv := s.sharedIV
	s.wireMu.Unlock()
	key, nonce := TsCreateKeyNonce(typ, pID, gen, 0x31, iv[:])
	if plain, err := TsEAXDecrypt(key[:], nonce[:], meta, data, mac); err == nil {
		return plain, nil
	}
	alts := []uint32{gen + 1}
	if gen > 0 {
		alts = append(alts, gen-1)
	}
	for _, alt := range alts {
		key, nonce := TsCreateKeyNonce(typ, pID, alt, 0x31, iv[:])
		if plain, err := TsEAXDecrypt(key[:], nonce[:], meta, data, mac); err == nil {
			return plain, nil
		}
	}
	return nil, fmt.Errorf("scripted server: c2s decrypt failed for pID=%d gen=%d", pID, gen)
}

func (s *tsScriptedServer) handleC2SVoice(pID uint16, mac [8]byte, raw, data []byte) {
	meta := raw[8:13]
	s.wireMu.Lock()
	gen := s.trackGen(TsPktVoice, pID)
	s.wireMu.Unlock()
	plain, err := s.decryptC2S(TsPktVoice, pID, gen, meta, data, mac)
	if err != nil {
		return
	}
	s.mu.Lock()
	s.voiceCount++
	s.lastVoice = append(s.lastVoice[:0], plain...)
	s.mu.Unlock()
}

func (s *tsScriptedServer) handleC2SCommand(typ byte, pID uint16, flags byte, mac [8]byte, raw, data []byte) {
	meta := raw[8:13]
	s.wireMu.Lock()
	cryptoOn := s.cryptoOn
	gen := s.trackGen(typ, pID)
	s.wireMu.Unlock()
	if !cryptoOn {
		plain, err := TsEAXDecrypt(TsFakeKey[:], TsFakeNonce[:], meta, data, mac)
		if err != nil {
			return
		}
		if name, _ := TsParseCommand(plain); name == "clientek" {
			s.handleClientek(pID, mac, raw, data)
		}
		return
	}
	plain, err := s.decryptC2S(typ, pID, gen, meta, data, mac)
	if err != nil {
		return
	}
	s.sendAck(pID)
	s.mu.Lock()
	s.cmdPkts = append(s.cmdPkts, tsCmdPkt{pID: pID, flags: raw[12]})
	s.mu.Unlock()
	payload := plain
	compressed := flags&TsFlagCompressed != 0
	if flags&TsFlagFragmented != 0 {
		if !s.fragActive {
			s.fragActive = true
			s.fragBuf = append(s.fragBuf[:0], plain...)
			s.fragCompressed = compressed
			return
		}
		payload = append(s.fragBuf, plain...)
		s.fragActive = false
		s.fragBuf = nil
		compressed = s.fragCompressed
	} else if s.fragActive {
		s.fragBuf = append(s.fragBuf, plain...)
		return
	}
	if compressed {
		out, err := TsQuickLZDecompress(payload)
		if err != nil {
			return
		}
		payload = out
	}
	for _, line := range strings.Split(string(payload), "\n") {
		line = strings.TrimRight(line, "\x00\r\n")
		if line == "" {
			continue
		}
		s.dispatch(line)
	}
}

func (s *tsScriptedServer) handleC2SAck(pID uint16, mac [8]byte, raw, data []byte) {
	meta := raw[8:13]
	plain, err := TsEAXDecrypt(TsFakeKey[:], TsFakeNonce[:], meta, data, mac)
	if err != nil {
		s.wireMu.Lock()
		cryptoOn := s.cryptoOn
		gen := s.trackGen(tsScriptedPktAck, pID)
		s.wireMu.Unlock()
		if !cryptoOn {
			return
		}
		plain, err = s.decryptC2S(tsScriptedPktAck, pID, gen, meta, data, mac)
		if err != nil {
			return
		}
	}
	if len(plain) >= 2 {
		s.mu.Lock()
		s.ackedCount++
		s.mu.Unlock()
	}
}

func (s *tsScriptedServer) dispatch(line string) {
	select {
	case s.received <- line:
	default:
	}
	name, _ := TsParseCommand([]byte(line))
	if name == "clientinit" {
		s.mu.Lock()
		s.clientinitLine = line
		cfg := s.cfg
		s.mu.Unlock()
		s.sendInitserver(cfg)
		return
	}
	if strings.HasPrefix(name, "notify") {
		return
	}
	s.mu.Lock()
	respond := s.respond
	s.mu.Unlock()
	var lines []string
	if respond == nil {
		lines = []string{"error id=0 msg=ok"}
	} else {
		lines = respond(line)
	}
	for _, l := range lines {
		s.sendCommand([]byte(l))
	}
}

func (s *tsScriptedServer) sendInitserver(cfg tsScriptedConfig) {
	line := "initserver aclid=" + strconv.Itoa(cfg.ClientID)
	if !cfg.OmitServerName {
		line += " virtualserver_name=" + TsEscape(cfg.ServerName)
	}
	line += " virtualserver_platform=Linux virtualserver_version=3.13.7" +
		" virtualserver_maxclients=32 virtualserver_clientsonline=1 virtualserver_channelsonline=" + strconv.Itoa(len(cfg.ChannelLines))
	s.sendCommand([]byte(line))
	if len(cfg.ChannelLines) > 0 {
		s.sendCommand([]byte("channellist " + strings.Join(cfg.ChannelLines, "|")))
	}
	s.sendCommand([]byte("channellistfinished"))
	for i := 0; i < cfg.FloodCommands; i++ {
		s.sendCommand([]byte("error id=0 msg=ok"))
		if i%20 == 19 {
			time.Sleep(time.Millisecond)
		}
	}
}

func (s *tsScriptedServer) sendInit(data []byte) {
	pkt := make([]byte, 11+len(data))
	copy(pkt[:8], tsScriptedInitMAC[:])
	binary.BigEndian.PutUint16(pkt[8:10], 101)
	pkt[10] = tsScriptedPktInit | tsScriptedFlagUnenc
	copy(pkt[11:], data)
	s.sendRaw(pkt)
}

func (s *tsScriptedServer) sendFakeCommand(plain []byte) {
	s.wireMu.Lock()
	pID := s.cmdPID
	s.cmdPID++
	client := s.client
	s.wireMu.Unlock()
	if client == nil {
		return
	}
	flags := byte(TsPktCommand) | TsFlagNewprotocol
	header := []byte{byte(pID >> 8), byte(pID & 0xff), flags}
	mac, ct := TsEAXEncrypt(TsFakeKey[:], TsFakeNonce[:], header, plain)
	pkt := make([]byte, 11+len(ct))
	copy(pkt[:8], mac[:])
	binary.BigEndian.PutUint16(pkt[8:10], pID)
	pkt[10] = flags
	copy(pkt[11:], ct)
	s.conn.WriteToUDP(pkt, client)
}

func (s *tsScriptedServer) sendCommand(plain []byte) {
	s.sendCommandGen(0, plain)
}

func (s *tsScriptedServer) sendCommandGen(gen uint32, plain []byte) {
	s.wireMu.Lock()
	cryptoOn := s.cryptoOn
	pID := s.cmdPID
	s.cmdPID++
	iv := s.sharedIV
	client := s.client
	s.wireMu.Unlock()
	if !cryptoOn || client == nil {
		return
	}
	flags := byte(TsPktCommand) | TsFlagNewprotocol
	header := []byte{byte(pID >> 8), byte(pID & 0xff), flags}
	key, nonce := TsCreateKeyNonce(TsPktCommand, pID, gen, 0x30, iv[:])
	mac, ct := TsEAXEncrypt(key[:], nonce[:], header, plain)
	pkt := make([]byte, 11+len(ct))
	copy(pkt[:8], mac[:])
	binary.BigEndian.PutUint16(pkt[8:10], pID)
	pkt[10] = flags
	copy(pkt[11:], ct)
	s.conn.WriteToUDP(pkt, client)
}

type tsS2CFrag struct {
	pID     uint16
	flags   byte
	payload []byte
}

func (s *tsScriptedServer) FragmentsAtPID(pID uint16, line string, chunkSize int, compressed bool) []tsS2CFrag {
	data := []byte(line)
	didCompress := false
	if compressed {
		if qz, ok := TsQuickLZCompress(data); ok && len(qz) < len(data) {
			data = qz
			didCompress = true
		}
	}
	var frags []tsS2CFrag
	for off := 0; off < len(data); off += chunkSize {
		end := off + chunkSize
		if end > len(data) {
			end = len(data)
		}
		frags = append(frags, tsS2CFrag{pID: pID, flags: byte(TsPktCommand) | TsFlagNewprotocol, payload: data[off:end]})
		pID++
	}
	if len(frags) == 1 {
		if didCompress {
			frags[0].flags |= TsFlagCompressed
		}
		return frags
	}
	for i := range frags {
		if i == 0 || i == len(frags)-1 {
			frags[i].flags |= TsFlagFragmented
		}
	}
	if didCompress {
		frags[0].flags |= TsFlagCompressed
	}
	return frags
}

func (s *tsScriptedServer) SendS2CFragment(f tsS2CFrag) {
	s.sendCmdPkt(f.pID, f.flags, f.payload)
}

func (s *tsScriptedServer) PushFragmentedAtPID(pID uint16, line string, chunkSize int, compressed bool) {
	for _, f := range s.FragmentsAtPID(pID, line, chunkSize, compressed) {
		s.SendS2CFragment(f)
	}
}

func (s *tsScriptedServer) sendAck(ackedPID uint16) {
	s.wireMu.Lock()
	cryptoOn := s.cryptoOn
	pID := s.ackPID
	s.ackPID++
	iv := s.sharedIV
	client := s.client
	s.wireMu.Unlock()
	if !cryptoOn || client == nil {
		return
	}
	var data [2]byte
	binary.BigEndian.PutUint16(data[:], ackedPID)
	header := []byte{byte(pID >> 8), byte(pID & 0xff), tsScriptedPktAck}
	key, nonce := TsCreateKeyNonce(tsScriptedPktAck, pID, 0, 0x30, iv[:])
	mac, ct := TsEAXEncrypt(key[:], nonce[:], header, data[:])
	pkt := make([]byte, 11+len(ct))
	copy(pkt[:8], mac[:])
	binary.BigEndian.PutUint16(pkt[8:10], pID)
	pkt[10] = tsScriptedPktAck
	copy(pkt[11:], ct)
	s.conn.WriteToUDP(pkt, client)
}

func (s *tsScriptedServer) sendCmdPkt(pID uint16, flags byte, plain []byte) {
	s.wireMu.Lock()
	cryptoOn := s.cryptoOn
	if pID >= s.cmdPID {
		s.cmdPID = pID + 1
	}
	iv := s.sharedIV
	client := s.client
	s.wireMu.Unlock()
	if !cryptoOn || client == nil {
		return
	}
	header := []byte{byte(pID >> 8), byte(pID & 0xff), flags}
	key, nonce := TsCreateKeyNonce(TsPktCommand, pID, 0, 0x30, iv[:])
	mac, ct := TsEAXEncrypt(key[:], nonce[:], header, plain)
	pkt := make([]byte, 11+len(ct))
	copy(pkt[:8], mac[:])
	binary.BigEndian.PutUint16(pkt[8:10], pID)
	pkt[10] = flags
	copy(pkt[11:], ct)
	s.conn.WriteToUDP(pkt, client)
}

func (s *tsScriptedServer) sendRaw(pkt []byte) {
	s.wireMu.Lock()
	client := s.client
	s.wireMu.Unlock()
	if client == nil {
		return
	}
	s.conn.WriteToUDP(pkt, client)
}

func tsScriptedASN1Int(b []byte) []byte {
	for len(b) > 1 && b[0] == 0 {
		b = b[1:]
	}
	if len(b) > 0 && b[0]&0x80 != 0 {
		b = append([]byte{0}, b...)
	}
	out := []byte{0x02, byte(len(b))}
	return append(out, b...)
}

func tsScriptedOmega(x, y *big.Int) string {
	inner := append([]byte{0x03, 0x02, 0x07, 0x00}, []byte{0x02, 0x01, 0x20}...)
	inner = append(inner, tsScriptedASN1Int(x.Bytes())...)
	inner = append(inner, tsScriptedASN1Int(y.Bytes())...)
	seq := append([]byte{0x30, byte(len(inner))}, inner...)
	return base64.StdEncoding.EncodeToString(seq)
}

func newScriptedTSCore(tb testing.TB, cfg tsScriptedConfig) (*TeamSpeakCore, *tsScriptedServer) {
	tb.Helper()
	srv := startTSScriptedServer(tb, cfg)
	store := utils.NewSessionStore(newTestVaultSimple(tb, tb.TempDir()), "ts-scripted")
	core := NewTeamSpeakCore(store)
	tb.Cleanup(func() { _ = core.Logout() })
	if err := core.Authenticate(AuthConfig{Mode: AuthModeUser, Extra: map[string]string{
		"server_address": srv.Addr(),
		"nickname":       "alice",
	}}); err != nil {
		tb.Fatalf("Authenticate against the scripted TS server: %v", err)
	}
	return core, srv
}

func TestTeamSpeakScriptedServerAuthenticateJourney(t *testing.T) {
	old := TsExecVoidTimeout
	TsExecVoidTimeout = 2 * time.Second
	t.Cleanup(func() { TsExecVoidTimeout = old })

	core, srv := newScriptedTSCore(t, tsScriptedConfig{
		ServerName: "Scripted HQ",
		ClientID:   42,
		ChannelLines: []string{
			"cid=1 pid=0 channel_name=Default\\sChannel channel_topic= total_clients=1 channel_order=0 channel_flag_default=1",
			"cid=7 pid=1 channel_name=Lobby channel_topic=Guests total_clients=2 channel_order=1",
		},
	})
	srv.SetResponder(func(line string) []string {
		if strings.HasPrefix(line, "channelinfo") {
			return []string{"channel_id=7 channel_needed_talk_power=9999", "error id=0 msg=ok"}
		}
		return []string{"error id=0 msg=ok"}
	})

	if got := core.ServerName(); got != "Scripted HQ" {
		t.Errorf("ServerName = %q, want %q — initserver not ingested through the real wire", got, "Scripted HQ")
	}

	dialogs, err := core.GetDialogs(PaginationOpts{})
	if err != nil {
		t.Fatalf("GetDialogs: %v", err)
	}
	lobby := false
	for _, d := range dialogs {
		if d.ID == "ch:7" && d.Title == "Lobby" && d.MemberCount == 2 {
			lobby = true
		}
	}
	if !lobby {
		t.Errorf("ch:7 Lobby missing from dialogs after the real channellist journey: %+v", dialogs)
	}

	rows, err := core.TsExec("channelinfo cid=7")
	if err != nil {
		t.Fatalf("TsExec through the real wire: %v", err)
	}
	if len(rows) == 0 || rows[0]["channel_needed_talk_power"] != "9999" {
		t.Errorf("channelinfo rows = %v, want channel_needed_talk_power=9999 from the scripted responder", rows)
	}

	initLine := srv.ClientInitLine()
	if !strings.Contains(initLine, "client_nickname=alice") {
		t.Errorf("clientinit seen by the server = %q, want client_nickname=alice", initLine)
	}
	if !srv.Init2EchoValid() {
		t.Errorf("client init2 did not echo the server randoms")
	}
	if !srv.Init4YValid() {
		t.Errorf("client init4 y failed the server-side level modexp check")
	}
	if !srv.EKProofValid() {
		t.Errorf("client clientek proof failed server-side identity verification")
	}
	if srv.AckedCount() < 1 {
		t.Errorf("server saw no client acks of its command packets")
	}
}
