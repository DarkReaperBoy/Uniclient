package cores

import (
	"bufio"
	"context"
	"crypto/ecdsa"
	"github.com/gotd/td/tg"
	"maunium.net/go/mautrix"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"
	"net"
	"net/http"
	"sync"
	"sync/atomic"
	"time"
	"uniclient/wrtc"
)

func (x *MatrixCore) ForTestActiveCalls() map[string]*MatrixCall {
	return x.activeCalls
}

func (x *MatrixCore) ForTestCallsMu() *sync.RWMutex {
	return &x.callsMu
}

func (x *TeamSpeakCore) ForTestChannels() map[int]TsChannelInfo {
	return x.channels
}

func (x *TeamSpeakCore) ForTestChannelsMu() *sync.RWMutex {
	return &x.channelsMu
}

func (x *TsConnection) ForTestClientID() *atomic.Uint32 {
	return &x.clientID
}

func (x *TeamSpeakCore) ForTestClientInfoMu() *sync.RWMutex {
	return &x.clientInfoMu
}

func (x *TsConnection) ForTestCmdCh() chan TsIncomingCmd {
	return x.cmdCh
}

func (x *MatrixCore) ForTestDeviceID() id.DeviceID {
	return x.deviceID
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

func (x *XMPPCore) ForTestFeatures() xmppFeatures {
	return x.features
}

func (x *MatrixCore) ForTestGroupConfID() string {
	return x.groupConfID
}

func (x *MatrixCore) ForTestGroupMembers() map[id.UserID]MatrixCallMemberContent {
	return x.groupMembers
}

func (x *MatrixCore) ForTestGroupMu() *sync.Mutex {
	return &x.groupMu
}

func (x *MatrixCore) ForTestGroupPeers() map[string]*MatrixCall {
	return x.groupPeers
}

func (x *MatrixCore) ForTestGroupRenew() context.CancelFunc {
	return x.groupRenew
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

func (x *TeamSpeakCore) ForTestMyChannelID() int {
	return x.myChannelID
}

func (x *TeamSpeakCore) ForTestMyClientID() int {
	return x.myClientID
}

func (x *TeamSpeakCore) ForTestMyTalkPower() int {
	return x.myTalkPower
}

func (x *MatrixCall) ForTestPc() *wrtc.PeerConnection {
	return x.pc
}

func (x *tgCall) ForTestPc() *wrtc.PeerConnection {
	return x.pc
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

func (x *MatrixCore) ForTestRooms() map[id.RoomID]*MatrixRoomState {
	return x.rooms
}

func (x *MatrixCore) ForTestRoomsMu() *sync.RWMutex {
	return &x.roomsMu
}

func (x *TsChannelInfo) ForTestTalkPower() int {
	return x.talkPower
}

func (x *TsChannelInfo) ForTestTalkPowerKnown() bool {
	return x.talkPowerKnown
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

func (x *TeamSpeakCore) ForTestSetChannels(v map[int]TsChannelInfo) {
	x.channels = v
}

func (x *TelegramCore) ForTestSetCtx(v context.Context) {
	x.ctx = v
}

func (x *MatrixCore) ForTestSetDeviceID(v id.DeviceID) {
	x.deviceID = v
}

func (x *MatrixCore) ForTestSetGroupConfID(v string) {
	x.groupConfID = v
}

func (x *MatrixCore) ForTestSetGroupMembers(v map[id.UserID]MatrixCallMemberContent) {
	x.groupMembers = v
}

func (x *MatrixCore) ForTestSetGroupPeers(v map[string]*MatrixCall) {
	x.groupPeers = v
}

func (x *MatrixCore) ForTestSetGroupRenew(v context.CancelFunc) {
	x.groupRenew = v
}

func (x *MatrixCore) ForTestSetGroupRoomID(v id.RoomID) {
	x.groupRoomID = v
}

func (x *MatrixCore) ForTestSetGroupSession(v string) {
	x.groupSession = v
}

func (x *TeamSpeakCore) ForTestSetMyClientID(v int) {
	x.myClientID = v
}

func (x *MatrixCore) ForTestSetRooms(v map[id.RoomID]*MatrixRoomState) {
	x.rooms = v
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

func (x *MatrixCore) ForTestHandleMemberEvent(evt *event.Event) {
	x.handleMemberEvent(evt)
}

func (x *MatrixCallMemberCall) ForTestLiveDevices(now int64) []MatrixCallDevice {
	return x.liveDevices(now)
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

func ForTestNewMatrixCall(GroupConf string, ID string, RoomID id.RoomID, State CallState, pc *wrtc.PeerConnection) *MatrixCall {
	return &MatrixCall{GroupConf: GroupConf, ID: ID, RoomID: RoomID, State: State, pc: pc}
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

func ForTestNewMatrixCore(authed bool, cancel context.CancelFunc, client *mautrix.Client, ctx context.Context, deviceID id.DeviceID, homeserver string, userID id.UserID) *MatrixCore {
	return &MatrixCore{authed: authed, cancel: cancel, client: client, ctx: ctx, deviceID: deviceID, homeserver: homeserver, userID: userID}
}

func ForTestNewTsWant(key string, name string, val string) *TsWant {
	return &TsWant{key: key, name: name, val: val}
}

func ForTestNewTeamSpeakCore(authed bool, channels map[int]TsChannelInfo, clientInfo map[int]TsClientInfo, ctx context.Context, myChannelID int, myClientID int, myTalkPower int, tsConn *TsConnection) *TeamSpeakCore {
	return &TeamSpeakCore{authed: authed, channels: channels, clientInfo: clientInfo, ctx: ctx, myChannelID: myChannelID, myClientID: myClientID, myTalkPower: myTalkPower, tsConn: tsConn}
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
