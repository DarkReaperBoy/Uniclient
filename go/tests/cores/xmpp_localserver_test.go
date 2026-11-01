package tests

import (
	"bufio"
	"encoding/base64"
	"fmt"
	"net"
	"strings"
	"sync"
	"testing"
	"time"
	. "uniclient/cores"

	"uniclient/utils"
)

type miniXMPPServer struct {
	ln   net.Listener
	user string
	pass string

	mu       sync.Mutex
	boundJID string
	inbox    chan string
	logFn    func(string)
}

func startMiniXMPPServer(t *testing.T, user, pass string) (*miniXMPPServer, string) {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	s := &miniXMPPServer{ln: ln, user: user, pass: pass, inbox: make(chan string, 8)}
	go s.acceptLoop()
	t.Cleanup(func() { ln.Close() })
	return s, ln.Addr().String()
}

func (s *miniXMPPServer) acceptLoop() {
	for {
		conn, err := s.ln.Accept()
		if err != nil {
			return
		}
		go s.handle(conn)
	}
}

type stanzaReader struct {
	r   *bufio.Reader
	c   net.Conn
	buf string
}

func (sr *stanzaReader) next() (string, error) {
	for {
		sr.buf = strings.TrimLeft(sr.buf, " \r\n\t")
		if strings.HasPrefix(sr.buf, "<?xml") {
			if e := strings.Index(sr.buf, "?>"); e >= 0 {
				sr.buf = sr.buf[e+2:]
				continue
			}
		}
		if !strings.HasPrefix(sr.buf, "<") {
			if sr.buf == "" {
				if err := sr.fill(); err != nil {
					return "", err
				}
				continue
			}
			sr.buf = ""
			continue
		}
		gt := strings.IndexByte(sr.buf, '>')
		if gt < 0 {
			if err := sr.fill(); err != nil {
				return "", err
			}
			continue
		}
		nameEnd := gt
		if sp := strings.IndexAny(sr.buf[:gt], " \t\r\n"); sp >= 0 {
			nameEnd = sp
		}
		name := sr.buf[1:nameEnd]
		selfClose := strings.HasSuffix(sr.buf[:gt+1], "/>")
		if name == "stream:stream" {
			sr.buf = sr.buf[gt+1:]
			return "<stream:stream>", nil
		}
		if selfClose {
			stanza := sr.buf[:gt+1]
			sr.buf = sr.buf[gt+1:]
			return stanza, nil
		}
		close := "</" + name + ">"
		if e := strings.Index(sr.buf, close); e >= 0 {
			stanza := sr.buf[:e+len(close)]
			sr.buf = sr.buf[e+len(close):]
			return stanza, nil
		}
		if err := sr.fill(); err != nil {
			return "", err
		}
	}
}

func (sr *stanzaReader) fill() error {
	if sr.c != nil {
		sr.c.SetReadDeadline(time.Now().Add(60 * time.Second))
	}
	var p [4096]byte
	n, err := sr.r.Read(p[:])
	if n > 0 {
		sr.buf += string(p[:n])
	}
	return err
}

func (s *miniXMPPServer) handle(conn net.Conn) {
	defer conn.Close()
	sr := &stanzaReader{r: bufio.NewReader(conn), c: conn}

	phase := 0
	for {
		stanza, err := sr.next()
		if err != nil {
			return
		}
		if s.logFn != nil {
			s.logFn("recv: " + stanza)
		}
		switch {
		case stanza == "<stream:stream>":
			if phase == 0 {
				conn.Write([]byte("<?xml version='1.0'?><stream:stream xmlns='jabber:client' xmlns:stream='http://etherx.jabber.org/streams' id='mini1' from='localhost' version='1.0'>" +
					"<stream:features><mechanisms xmlns='urn:ietf:params:xml:ns:xmpp-sasl'><mechanism>PLAIN</mechanism></mechanisms></stream:features>"))
			} else {
				conn.Write([]byte("<?xml version='1.0'?><stream:stream xmlns='jabber:client' xmlns:stream='http://etherx.jabber.org/streams' id='mini2' from='localhost' version='1.0'>" +
					"<stream:features><bind xmlns='urn:ietf:params:xml:ns:xmpp-bind'/><session xmlns='urn:ietf:params:xml:ns:xmpp-session'/></stream:features>"))
			}
		case strings.HasPrefix(stanza, "<auth"):
			user, pass, ok := decodeSASLPlain(stanza)
			if !ok || user != s.user || pass != s.pass {
				conn.Write([]byte("<failure xmlns='urn:ietf:params:xml:ns:xmpp-sasl'><not-authorized/></failure>"))
				return
			}
			conn.Write([]byte("<success xmlns='urn:ietf:params:xml:ns:xmpp-sasl'/>"))
			phase = 1
		case strings.HasPrefix(stanza, "<iq"):
			id := ExtractXMLAttr(stanza, "iq", "id")
			if strings.Contains(stanza, NsBind) {
				res := ExtractXMLContent(stanza, "resource")
				if res == "" {
					res = "mini"
				}
				jid := fmt.Sprintf("%s@localhost/%s", s.user, res)
				s.mu.Lock()
				s.boundJID = jid
				s.mu.Unlock()
				conn.Write([]byte(fmt.Sprintf("<iq id='%s' type='result'><bind xmlns='urn:ietf:params:xml:ns:xmpp-bind'><jid>%s</jid></bind></iq>", id, jid)))
				phase = 2
			} else if strings.Contains(stanza, "urn:ietf:params:xml:ns:xmpp-session") {
				conn.Write([]byte(fmt.Sprintf("<iq id='%s' type='result'/>", id)))
			} else {
				conn.Write([]byte(fmt.Sprintf("<iq id='%s' type='result'/>", id)))
			}
		case strings.HasPrefix(stanza, "<message"):
			s.mu.Lock()
			jid := s.boundJID
			s.mu.Unlock()
			if jid == "" {
				continue
			}
			body := ExtractXMLContent(stanza, "body")
			echo := fmt.Sprintf("<message from='%s@localhost' to='%s' type='chat' id='echo1'><body>%s</body></message>", s.user, jid, body)
			conn.Write([]byte(echo))
			select {
			case s.inbox <- body:
			default:
			}
		}
	}
}

func decodeSASLPlain(stanza string) (user, pass string, ok bool) {
	b64 := ExtractXMLContent(stanza, "auth")
	raw, err := base64.StdEncoding.DecodeString(b64)
	if err != nil {
		return "", "", false
	}
	parts := strings.SplitN(string(raw), "\x00", 3)
	if len(parts) != 3 {
		return "", "", false
	}
	return parts[1], parts[2], true
}

func TestXMPPFullChainLocalServer(t *testing.T) {
	srv, addr := startMiniXMPPServer(t, "alice", "wonderland")
	_ = srv

	store := utils.NewSessionStore(newTestVaultXMPP(t), "xmpp-mini")
	core := NewXMPPCore(store)
	defer core.Logout()

	recv := make(chan string, 8)
	core.OnUpdate(func(u Update) {
		if u.Type == UpdateNewMessage && u.Message != nil && u.Message.Text != "" {
			recv <- u.Message.Text
		}
	})

	cfg := AuthConfig{
		Extra: map[string]string{
			"server":   addr,
			"jid":      "alice@localhost",
			"password": "wonderland",
			"tls":      "none",
		},
	}
	if err := core.Authenticate(cfg); err != nil {
		t.Fatalf("Authenticate against mini server: %v", err)
	}

	bad := NewXMPPCore(utils.NewSessionStore(newTestVaultXMPP(t), "xmpp-mini-bad"))
	defer bad.Logout()
	badCfg := cfg
	badCfg.Extra = map[string]string{
		"server":   addr,
		"jid":      "alice@localhost",
		"password": "wrong-password",
		"tls":      "none",
	}
	if err := bad.Authenticate(badCfg); err == nil || !strings.Contains(strings.ToLower(err.Error()), "auth") {
		t.Fatalf("bad password must fail SASL auth, got: %v", err)
	}

	body := "mini server round-trip 42"
	if _, err := core.SendMessage("alice@localhost", OutgoingMessage{Text: body}); err != nil {
		t.Fatalf("SendMessage: %v", err)
	}
	select {
	case got := <-recv:
		if got != body {
			t.Fatalf("round-trip mismatch: got %q want %q", got, body)
		}
		t.Log("FULL CHAIN OK: SASL PLAIN auth + bind + session + message round-trip against the local server")
	case <-time.After(10 * time.Second):
		t.Fatal("echoed message not received within 10s")
	}
}

func newTestVaultXMPP(t *testing.T) *utils.Vault {
	t.Helper()
	dir := t.TempDir()
	v, err := utils.CreateVault(dir+"/test.vault", "mini-test")
	if err != nil {
		t.Fatalf("vault: %v", err)
	}
	t.Cleanup(func() { v.Close() })
	return v
}
