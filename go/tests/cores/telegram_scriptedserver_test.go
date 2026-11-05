package tests

import (
	"context"
	"crypto/rand"
	"crypto/rsa"
	"net"
	"os"
	"sync"
	"testing"
	"time"

	. "uniclient/cores"

	"github.com/gotd/td/crypto"
	"github.com/gotd/td/exchange"
	"github.com/gotd/td/session"
	"github.com/gotd/td/telegram"
	"github.com/gotd/td/tg"
	"github.com/gotd/td/tgerr"
	"github.com/gotd/td/tgtest"
	"github.com/gotd/td/transport"
)

const (
	tgScriptedPhone = "+1555010042"
	tgScriptedCode  = "42442"
	tgScriptedDC    = 2
)

func tgScriptedSelf() *tg.User {
	return &tg.User{
		ID:         10,
		AccessHash: 10,
		Username:   "scripted_self",
		FirstName:  "Scripted",
		LastName:   "Self",
	}
}

type tgStuckCall struct {
	want    uint32
	gotType uint32
	entered chan struct{}
	release chan struct{}
}

type tgScriptedServer struct {
	srv  *tgtest.Server
	key  exchange.PrivateKey
	addr string
	cfg  tg.Config

	storage *session.StorageMemory

	mu            sync.Mutex
	authorized    map[[8]byte]struct{}
	stuck         *tgStuckCall
	watchers      map[uint32]chan struct{}
	counts        map[uint32]int
	uploadErr     *tgerr.Error
	uploadPayload []byte
	uploadSeen    []*tg.UploadGetFileRequest
}

func newTGScriptedServer(t *testing.T) *tgScriptedServer {
	t.Helper()
	rsaKey, err := rsa.GenerateKey(rand.Reader, crypto.RSAKeyBits)
	if err != nil {
		t.Fatalf("scripted server rsa key: %v", err)
	}
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("scripted server listen: %v", err)
	}
	tcpAddr := l.Addr().(*net.TCPAddr)

	s := &tgScriptedServer{
		key:  exchange.PrivateKey{RSA: rsaKey},
		addr: tcpAddr.String(),
		cfg: tg.Config{
			ThisDC: tgScriptedDC,
			DCOptions: []tg.DCOption{{
				ID:        tgScriptedDC,
				Static:    true,
				IPAddress: tcpAddr.IP.String(),
				Port:      tcpAddr.Port,
			}},
		},
		storage:    &session.StorageMemory{},
		authorized: map[[8]byte]struct{}{},
		watchers:   map[uint32]chan struct{}{},
		counts:     map[uint32]int{},
	}

	d := tgtest.NewDispatcher()
	d.Fallback(tgtest.HandlerFunc(s.onMessage))

	s.srv = tgtest.NewServer(s.key, tgtest.UnpackInvoke(d), tgtest.ServerOptions{
		DC: tgScriptedDC + 10000,
	})

	srvCtx, srvCancel := context.WithCancel(context.Background())
	t.Cleanup(func() {
		srvCancel()
		_ = l.Close()
	})
	go func() { _ = s.srv.Serve(srvCtx, transport.Listen(&tgWarmListener{Listener: l, dead: srvCtx.Done()})) }()
	return s
}

type tgWarmConn struct {
	net.Conn
	head []byte
}

func (c *tgWarmConn) Read(p []byte) (int, error) {
	if len(c.head) > 0 {
		n := copy(p, c.head)
		c.head = c.head[n:]
		return n, nil
	}
	return c.Conn.Read(p)
}

type tgWarmListener struct {
	net.Listener
	dead <-chan struct{}
}

func (l *tgWarmListener) Accept() (net.Conn, error) {
	for {
		conn, err := l.Listener.Accept()
		if err != nil {
			return nil, err
		}
		head := make([]byte, 1)
		for {
			if err := conn.SetReadDeadline(time.Now().Add(100 * time.Millisecond)); err != nil {
				_ = conn.Close()
				break
			}
			n, rerr := conn.Read(head)
			if n > 0 {
				_ = conn.SetReadDeadline(time.Time{})
				return &tgWarmConn{Conn: conn, head: head[:n]}, nil
			}
			select {
			case <-l.dead:
				_ = conn.Close()
				return nil, net.ErrClosed
			default:
			}
			if os.IsTimeout(rerr) {
				continue
			}
			_ = conn.Close()
			break
		}
	}
}

func (s *tgScriptedServer) onMessage(server *tgtest.Server, req *tgtest.Request) error {
	id, err := req.Buf.PeekID()
	if err != nil {
		return err
	}
	s.mu.Lock()
	s.counts[id]++
	if ch, ok := s.watchers[id]; ok {
		delete(s.watchers, id)
		close(ch)
	}
	stuck := s.stuck
	if stuck != nil {
		s.stuck = nil
		s.mu.Unlock()
		stuck.gotType = id
		close(stuck.entered)
		go func() {
			<-stuck.release
			_ = server.SendErr(req, tgerr.New(400, "TEST_RELEASED"))
		}()
		return nil
	}
	s.mu.Unlock()

	switch id {
	case tg.HelpGetConfigRequestTypeID:
		cfg := s.cfg
		return server.SendResult(req, &cfg)

	case tg.HelpGetCDNConfigRequestTypeID:
		return server.SendResult(req, &tg.CDNConfig{})

	case tg.UsersGetUsersRequestTypeID:
		if !s.keyAuthorized(req) {
			return tgerr.New(401, "AUTH_KEY_UNAUTHORIZED")
		}
		return server.SendVector(req, tgScriptedSelf())

	case tg.AuthSendCodeRequestTypeID:
		var r tg.AuthSendCodeRequest
		if err := r.Decode(req.Buf); err != nil {
			return err
		}
		if r.PhoneNumber != tgScriptedPhone {
			return tgerr.New(400, "PHONE_NUMBER_INVALID")
		}
		return server.SendResult(req, &tg.AuthSentCode{
			Type:          &tg.AuthSentCodeTypeApp{Length: 5},
			PhoneCodeHash: "scripted-hash",
			Timeout:       60,
		})

	case tg.AuthSignInRequestTypeID:
		var r tg.AuthSignInRequest
		if err := r.Decode(req.Buf); err != nil {
			return err
		}
		if r.PhoneCodeHash != "scripted-hash" || r.PhoneCode != tgScriptedCode {
			return tgerr.New(400, "PHONE_CODE_INVALID")
		}
		s.setKeyAuthorized(req, true)
		return server.SendResult(req, &tg.AuthAuthorization{User: tgScriptedSelf()})

	case tg.AuthLogOutRequestTypeID:
		s.setKeyAuthorized(req, false)
		return server.SendResult(req, &tg.AuthLoggedOut{})

	case tg.AuthExportAuthorizationRequestTypeID:
		return server.SendResult(req, &tg.AuthExportedAuthorization{
			ID:    tgScriptedSelf().ID,
			Bytes: []byte("scripted-export"),
		})

	case tg.AuthImportAuthorizationRequestTypeID:
		var r tg.AuthImportAuthorizationRequest
		if err := r.Decode(req.Buf); err != nil {
			return err
		}
		if r.ID != tgScriptedSelf().ID {
			return tgerr.New(400, "AUTH_BYTES_INVALID")
		}
		s.setKeyAuthorized(req, true)
		return server.SendResult(req, &tg.AuthAuthorization{User: tgScriptedSelf()})

	case tg.UploadGetFileRequestTypeID:
		var r tg.UploadGetFileRequest
		if err := r.Decode(req.Buf); err != nil {
			return err
		}
		s.mu.Lock()
		s.uploadSeen = append(s.uploadSeen, &r)
		payload, rpcErr := s.uploadPayload, s.uploadErr
		s.mu.Unlock()
		if rpcErr != nil {
			return rpcErr
		}
		return server.SendResult(req, &tg.UploadFile{
			Type:  &tg.StorageFilePartial{},
			Bytes: payload,
		})
	}
	return tgerr.New(400, "INPUT_METHOD_INVALID")
}

func (s *tgScriptedServer) keyAuthorized(req *tgtest.Request) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	_, ok := s.authorized[req.Session.AuthKey.ID]
	return ok
}

func (s *tgScriptedServer) setKeyAuthorized(req *tgtest.Request, v bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if v {
		s.authorized[req.Session.AuthKey.ID] = struct{}{}
	} else {
		delete(s.authorized, req.Session.AuthKey.ID)
	}
}

func (s *tgScriptedServer) stickNext(want uint32) *tgStuckCall {
	stuck := &tgStuckCall{
		want:    want,
		entered: make(chan struct{}),
		release: make(chan struct{}),
	}
	s.mu.Lock()
	s.stuck = stuck
	s.mu.Unlock()
	return stuck
}

func (s *tgScriptedServer) watchType(id uint32) <-chan struct{} {
	ch := make(chan struct{})
	s.mu.Lock()
	s.watchers[id] = ch
	s.mu.Unlock()
	return ch
}

func (s *tgScriptedServer) countOf(id uint32) int {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.counts[id]
}

func (s *tgScriptedServer) uploadRequests() []*tg.UploadGetFileRequest {
	s.mu.Lock()
	defer s.mu.Unlock()
	return append([]*tg.UploadGetFileRequest(nil), s.uploadSeen...)
}

func (s *tgScriptedServer) setUploadScript(rpcErr *tgerr.Error, payload []byte) {
	s.mu.Lock()
	s.uploadErr, s.uploadPayload = rpcErr, payload
	s.mu.Unlock()
}

func (s *tgScriptedServer) authedCore(t *testing.T) *TelegramCore {
	t.Helper()
	core := NewTelegramCore(TelegramConfig{
		APIID:          1,
		APIHash:        "scripted",
		UseTestDC:      true,
		SessionStorage: s.storage,
		DialFunc: func(ctx context.Context, network, addr string) (net.Conn, error) {
			var d net.Dialer
			return d.DialContext(ctx, network, s.addr)
		},
		PublicKeys: []telegram.PublicKey{s.srv.Key()},
	})
	if err := core.Authenticate(AuthConfig{
		Mode:  AuthModeUser,
		Phone: tgScriptedPhone,
		OTP:   tgScriptedCode,
	}); err != nil {
		t.Fatalf("scripted Authenticate journey: %v", err)
	}
	t.Cleanup(func() { _ = core.Close() })
	return core
}

func waitStuckEntered(t *testing.T, stuck *tgStuckCall, what string) {
	t.Helper()
	select {
	case <-stuck.entered:
	case <-time.After(10 * time.Second):
		t.Fatalf("%s: RPC never reached the scripted server within 10s", what)
	}
	if stuck.gotType != stuck.want {
		t.Fatalf("%s: stuck RPC type = %#x, want %#x", what, stuck.gotType, stuck.want)
	}
}

func waitWatched(t *testing.T, ch <-chan struct{}, what string) {
	t.Helper()
	select {
	case <-ch:
	case <-time.After(2 * time.Second):
		t.Fatalf("%s: not observed server-side within 2s — a reader/writer is pinned across an in-flight RPC (freeze class)", what)
	}
}
