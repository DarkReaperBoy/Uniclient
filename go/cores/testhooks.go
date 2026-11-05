package cores

import (
	"bufio"
	"context"
	"crypto/ecdsa"
	"github.com/gotd/td/tg"
	"maunium.net/go/mautrix/id"
	"net"
	"net/http"
	"time"
)

func (x *tsP256Identity) ForTestKey() *ecdsa.PrivateKey {
	return x.key
}

func (x *TsWant) ForTestKey() string {
	return x.key
}

func (x *groupPeer) ForTestKey() string {
	return x.key
}

func (x *TeamSpeakCore) ForTestMyClientID() int {
	return x.myClientID
}

func (x *TsConnection) ForTestPktState() *[9]tsPacketState {
	return &x.pktState
}

func (x *TeamSpeakCore) ForTestTsConn() *TsConnection {
	return x.tsConn
}

func (x *MatrixCore) ForTestSetUserID(v id.UserID) {
	x.userID = v
}

func (x *GitHubCore) ForTestSetUsername(v string) {
	x.username = v
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

func ForTestNewRpcGuard(next tg.Invoker, timeout time.Duration) *RpcGuard {
	return &RpcGuard{next: next, timeout: timeout}
}
