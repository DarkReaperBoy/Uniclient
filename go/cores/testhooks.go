package cores

import (
	"bufio"
	"context"
	"crypto/ecdsa"
	"github.com/gotd/td/tg"
	"maunium.net/go/mautrix/id"
	"net"
	"net/http"
	"sync"
	"sync/atomic"
	"time"
)

func (x *TsConnection) ForTestClientID() *atomic.Uint32 {
	return &x.clientID
}

func (x *TeamSpeakCore) ForTestClientInfoMu() *sync.RWMutex {
	return &x.clientInfoMu
}

func (x *TsConnection) ForTestCmdCh() chan TsIncomingCmd {
	return x.cmdCh
}

func (x *TsConnection) ForTestExecCh() chan TsIncomingCmd {
	return x.execCh
}

func (x *TsConnection) ForTestExecMu() *sync.Mutex {
	return &x.execMu
}

func (x *TsConnection) ForTestExecWait() bool {
	return x.execWait
}

func (x *tsP256Identity) ForTestKey() *ecdsa.PrivateKey {
	return x.key
}

func (x *TsWant) ForTestKey() string {
	return x.key
}

func (x *groupPeer) ForTestKey() string {
	return x.key
}

func (x *TelegramCore) ForTestMu() *sync.RWMutex {
	return &x.mu
}

func (x *TeamSpeakCore) ForTestMyClientID() int {
	return x.myClientID
}

func (x *TsConnection) ForTestPktState() *[9]tsPacketState {
	return &x.pktState
}

func (x *TsConnection) ForTestRecvQueue() *[2]map[uint16]*TsDecryptedPkt {
	return &x.recvQueue
}

func (x *TsConnection) ForTestRecvQueueMu() *sync.Mutex {
	return &x.recvQueueMu
}

func (x *TeamSpeakCore) ForTestTsConn() *TsConnection {
	return x.tsConn
}

func (x *TelegramCore) ForTestSetApi(v *tg.Client) {
	x.api = v
}

func (x *TeamSpeakCore) ForTestSetAuthed(v bool) {
	x.authed = v
}

func (x *TelegramCore) ForTestSetAuthed(v bool) {
	x.authed = v
}

func (x *TelegramCore) ForTestSetCtx(v context.Context) {
	x.ctx = v
}

func (x *TeamSpeakCore) ForTestSetMyClientID(v int) {
	x.myClientID = v
}

func (x *TeamSpeakCore) ForTestSetTsConn(v *TsConnection) {
	x.tsConn = v
}

func (x *MatrixCore) ForTestSetUserID(v id.UserID) {
	x.userID = v
}

func (x *GitHubCore) ForTestSetUsername(v string) {
	x.username = v
}

func (x *TsConnection) ForTestFireProof(name string, fields map[string]string) {
	x.fireProof(name, fields)
}

func (x *TsConnection) ForTestTakeProofs() bool {
	return x.takeProofs()
}

func (x *TsConnection) ForTestTsDecryptRecv(pktType byte, pID uint16, meta, data []byte, mac [8]byte) ([]byte, error) {
	return x.tsDecryptRecv(pktType, pID, meta, data, mac)
}

func (x *TsConnection) ForTestTsHandlePacket(raw []byte) {
	x.tsHandlePacket(raw)
}

func (x *tsP256Identity) ForTestTsOmega() string {
	return x.tsOmega()
}

func (x *TsConnection) ForTestTsProcessCommandQueue(cmdI int) {
	x.tsProcessCommandQueue(cmdI)
}

func (x *TsConnection) ForTestTsSendAck(pID uint16) error {
	return x.tsSendAck(pID)
}

func (x *TsConnection) ForTestTsSendCommand(cmdStr string) (uint16, error) {
	return x.tsSendCommand(cmdStr)
}

func (x *TsConnection) ForTestTsSendPong(pingID uint16) error {
	return x.tsSendPong(pingID)
}

func (x *tsP256Identity) ForTestTsSign(data []byte) ([]byte, error) {
	return x.tsSign(data)
}

func (x *TsConnection) ForTestTsTrackRecvPID(pktType byte, pID uint16) uint32 {
	return x.tsTrackRecvPID(pktType, pID)
}

func (x *tsP256Identity) ForTestTsUID() string {
	return x.tsUID()
}

func ForTestPbDecode(data []byte) map[string]interface{} {
	return pbDecode(data)
}

func ForTestPbEncode(fields map[string]interface{}) []byte {
	return pbEncode(fields)
}

func ForTestTruncate(s string, maxLen int) string {
	return truncate(s, maxLen)
}

func ForTestNewTsIncomingCmd(name string, params map[string]string, raw string) *TsIncomingCmd {
	return &TsIncomingCmd{name: name, params: params, raw: raw}
}

func ForTestNewXMPPCore(conn net.Conn, ctx context.Context, reader *bufio.Reader) *XMPPCore {
	return &XMPPCore{conn: conn, ctx: ctx, reader: reader}
}

func ForTestNewGitHubCore(authed bool, client *http.Client, ctx context.Context, token string) *GitHubCore {
	return &GitHubCore{authed: authed, client: client, ctx: ctx, token: token}
}

func ForTestNewTsConnection(addr *net.UDPAddr, cmdCh chan TsIncomingCmd, conn *net.UDPConn, cryptoOK bool, owner *TeamSpeakCore, pendingCmds map[uint16]*TsPendingCmd, proofs chan TsProof, recvQueue [2]map[uint16]*TsDecryptedPkt, sharedIV [64]byte) *TsConnection {
	return &TsConnection{addr: addr, cmdCh: cmdCh, conn: conn, cryptoOK: cryptoOK, owner: owner, pendingCmds: pendingCmds, proofs: proofs, recvQueue: recvQueue, sharedIV: sharedIV}
}

func ForTestNewTsWant(key string, name string, val string) *TsWant {
	return &TsWant{key: key, name: name, val: val}
}

func ForTestNewTeamSpeakCore(authed bool, channels map[int]TsChannelInfo, clientInfo map[int]TsClientInfo, ctx context.Context, myChannelID int, myClientID int, myTalkPower int, tsConn *TsConnection) *TeamSpeakCore {
	core := &TeamSpeakCore{authed: authed, channels: make(map[int]TsChannelInfo), clientInfo: make(map[int]TsClientInfo), msgBuffer: make(map[string][]Message), eventHandlers: make(map[string][]func(map[string]string)), ctx: ctx, myChannelID: myChannelID, myClientID: myClientID, myTalkPower: myTalkPower, tsConn: tsConn}
	if channels != nil {
		core.channels = channels
	}
	if clientInfo != nil {
		core.clientInfo = clientInfo
	}
	return core
}

func ForTestNewTsDecryptedPkt(flags byte, pID uint16, plaintext []byte) *TsDecryptedPkt {
	return &TsDecryptedPkt{flags: flags, pID: pID, plaintext: plaintext}
}

func ForTestNewTsChannelInfo(cid int, talkPower int, talkPowerKnown bool) *TsChannelInfo {
	return &TsChannelInfo{cid: cid, talkPower: talkPower, talkPowerKnown: talkPowerKnown}
}

func ForTestNewRpcGuard(next tg.Invoker, timeout time.Duration) *RpcGuard {
	return &RpcGuard{next: next, timeout: timeout}
}
