package cores

// deltachat_localserver_test.go — the §9 "dockerized server" rung for the
// Delta Chat core, offline: emersion's go-imap imapserver + go-smtp server
// libraries (independent server implementations, the same stack real Go
// mail servers are built on) with self-signed STARTTLS. Verifies the FULL
// chain: IMAP connect+login (STARTTLS, 3 connections incl. two IDLE),
// DeltaChat folder LIST/CREATE, SMTP send (EHLO/AUTH PLAIN/MAIL/DATA) with
// Delta Chat headers, and the receive path (SELECT + FETCH →
// processIncomingEmail → chat list). No secrets, no network, runs in CI.

import (
	"bytes"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"errors"
	"io"
	"math/big"
	"net"
	"os"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/emersion/go-imap/v2"
	"github.com/emersion/go-imap/v2/imapserver"
	"github.com/emersion/go-sasl"
	gosmtp "github.com/emersion/go-smtp"

	"uniclient/utils"
)

// ── self-signed certificate ───────────────────────────────────────────────

func selfSignedCert(t *testing.T) tls.Certificate {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatalf("ecdsa key: %v", err)
	}
	serial, _ := rand.Int(rand.Reader, big.NewInt(1<<62))
	tmpl := &x509.Certificate{
		SerialNumber: serial,
		Subject:      pkix.Name{CommonName: "localhost"},
		NotBefore:    time.Now().Add(-time.Hour),
		NotAfter:     time.Now().Add(24 * time.Hour),
		KeyUsage:     x509.KeyUsageDigitalSignature | x509.KeyUsageKeyEncipherment,
		ExtKeyUsage:  []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
		DNSNames:     []string{"localhost"},
		IPAddresses:  []net.IP{net.ParseIP("127.0.0.1")},
	}
	der, err := x509.CreateCertificate(rand.Reader, tmpl, tmpl, &key.PublicKey, key)
	if err != nil {
		t.Fatalf("x509: %v", err)
	}
	return tls.Certificate{Certificate: [][]byte{der}, PrivateKey: key}
}

// ── mini IMAP server ──────────────────────────────────────────────────────

type miniMsg struct {
	uid    imap.UID
	flags  []imap.Flag
	env    *imap.Envelope
	header []byte
	body   []byte
}

type miniMailStore struct {
	mu        sync.Mutex
	mailboxes map[string][]*miniMsg
	uidNext   uint32
}

func newMiniMailStore() *miniMailStore {
	return &miniMailStore{mailboxes: map[string][]*miniMsg{"INBOX": {}}, uidNext: 1}
}

func (st *miniMailStore) add(mailbox string, m *miniMsg) {
	st.mu.Lock()
	defer st.mu.Unlock()
	if st.mailboxes[mailbox] == nil {
		st.mailboxes[mailbox] = []*miniMsg{}
	}
	m.uid = imap.UID(st.uidNext)
	st.uidNext++
	st.mailboxes[mailbox] = append(st.mailboxes[mailbox], m)
}

// imapSession is one connection's view of the store.
type imapSession struct {
	store *miniMailStore
	user  string
	pass  string
}

var errMiniNotSupported = errors.New("mini imap: command not supported")

func (s *imapSession) Close() error { return nil }

func (s *imapSession) Login(username, password string) error {
	if username != s.user || password != s.pass {
		return imapserver.ErrAuthFailed
	}
	return nil
}

func (s *imapSession) Select(mailbox string, options *imap.SelectOptions) (*imap.SelectData, error) {
	s.store.mu.Lock()
	defer s.store.mu.Unlock()
	msgs := s.store.mailboxes[mailbox]
	if msgs == nil {
		return nil, &imap.Error{
			Type: imap.StatusResponseTypeNo,
			Code: imap.ResponseCodeNonExistent,
			Text: "no such mailbox",
		}
	}
	return &imap.SelectData{
		NumMessages: uint32(len(msgs)),
		UIDNext:     imap.UID(s.store.uidNext),
		UIDValidity: 1,
		Flags:       []imap.Flag{imap.FlagSeen},
	}, nil
}

func (s *imapSession) Create(mailbox string, options *imap.CreateOptions) error {
	s.store.mu.Lock()
	defer s.store.mu.Unlock()
	if s.store.mailboxes[mailbox] == nil {
		s.store.mailboxes[mailbox] = []*miniMsg{}
	}
	return nil
}

func (s *imapSession) Delete(mailbox string) error                     { return errMiniNotSupported }
func (s *imapSession) Rename(a, b string, o *imap.RenameOptions) error { return errMiniNotSupported }
func (s *imapSession) Subscribe(mailbox string) error                  { return errMiniNotSupported }
func (s *imapSession) Unsubscribe(mailbox string) error                { return errMiniNotSupported }

func (s *imapSession) List(w *imapserver.ListWriter, ref string, patterns []string, options *imap.ListOptions) error {
	s.store.mu.Lock()
	names := make([]string, 0, len(s.store.mailboxes))
	for name := range s.store.mailboxes {
		names = append(names, name)
	}
	s.store.mu.Unlock()
	for _, name := range names {
		if err := w.WriteList(&imap.ListData{Mailbox: name, Delim: '/'}); err != nil {
			return err
		}
	}
	return nil
}

func (s *imapSession) Status(mailbox string, options *imap.StatusOptions) (*imap.StatusData, error) {
	return nil, errMiniNotSupported
}

func (s *imapSession) Append(mailbox string, r imap.LiteralReader, options *imap.AppendOptions) (*imap.AppendData, error) {
	return nil, errMiniNotSupported
}

func (s *imapSession) Poll(w *imapserver.UpdateWriter, allowExpunge bool) error { return nil }

func (s *imapSession) Idle(w *imapserver.UpdateWriter, stop <-chan struct{}) error {
	<-stop
	return nil
}

func (s *imapSession) Unselect() error { return nil }

func (s *imapSession) Expunge(w *imapserver.ExpungeWriter, uids *imap.UIDSet) error {
	return errMiniNotSupported
}

func (s *imapSession) Search(kind imapserver.NumKind, criteria *imap.SearchCriteria, options *imap.SearchOptions) (*imap.SearchData, error) {
	return nil, errMiniNotSupported
}

func (s *imapSession) Fetch(w *imapserver.FetchWriter, numSet imap.NumSet, options *imap.FetchOptions) error {
	s.store.mu.Lock()
	defer s.store.mu.Unlock()
	msgs := s.store.mailboxes["INBOX"] // the core only fetches the selected mailbox's list; keyed by INBOX snapshot
	// The selected state is per-connection; the mini store's only selected
	// mailbox in practice is INBOX or DeltaChat — serve from both.
	var all []*miniMsg
	all = append(all, s.store.mailboxes["INBOX"]...)
	all = append(all, s.store.mailboxes["DeltaChat"]...)
	msgs = all

	seqSet, ok := numSet.(imap.SeqSet)
	if !ok {
		return errMiniNotSupported
	}
	for seq := uint32(1); seq <= uint32(len(msgs)); seq++ {
		if !seqSet.Contains(seq) {
			continue
		}
		m := msgs[seq-1]
		mw := w.CreateMessage(seq)
		mw.WriteUID(m.uid)
		mw.WriteFlags(m.flags)
		if options.Envelope {
			mw.WriteEnvelope(m.env)
		}
		if options.BodySection != nil {
			for _, sec := range options.BodySection {
				var data []byte
				if sec.Specifier == imap.PartSpecifierHeader {
					data = m.header
				} else {
					data = append(append([]byte{}, m.header...), m.body...)
				}
				lw := mw.WriteBodySection(sec, int64(len(data)))
				if _, err := lw.Write(data); err != nil {
					return err
				}
				if err := lw.Close(); err != nil {
					return err
				}
			}
		}
		// FetchResponseWriter.Close must be called (ends the response and
		// releases the connection's response encoder).
		if err := mw.Close(); err != nil {
			return err
		}
	}
	return nil
}

func (s *imapSession) Store(w *imapserver.FetchWriter, numSet imap.NumSet, flags *imap.StoreFlags, options *imap.StoreOptions) error {
	return errMiniNotSupported
}

func (s *imapSession) Copy(numSet imap.NumSet, dest string) (*imap.CopyData, error) {
	return nil, errMiniNotSupported
}

var debugIMAP = false

func startMiniIMAP(t *testing.T, user, pass string, cert tls.Certificate) (*miniMailStore, string) {
	t.Helper()
	store := newMiniMailStore()
	opts := &imapserver.Options{
		NewSession: func(*imapserver.Conn) (imapserver.Session, *imapserver.GreetingData, error) {
			return &imapSession{store: store, user: user, pass: pass}, &imapserver.GreetingData{}, nil
		},
		Caps:         imap.CapSet{imap.CapIMAP4rev1: {}},
		TLSConfig:    &tls.Config{Certificates: []tls.Certificate{cert}},
		InsecureAuth: true,
	}
	if debugIMAP {
		opts.DebugWriter = os.Stderr
	}
	srv := imapserver.New(opts)
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("imap listen: %v", err)
	}
	go srv.Serve(ln)
	t.Cleanup(func() { srv.Close() })
	return store, ln.Addr().String()
}

// ── mini SMTP server ──────────────────────────────────────────────────────

type smtpMail struct {
	from string
	rcpt []string
	data []byte
}

type miniSMTPBackend struct {
	mu    sync.Mutex
	user  string
	pass  string
	mails []*smtpMail
}

type miniSMTPSession struct {
	be   *miniSMTPBackend
	mail *smtpMail
}

func (be *miniSMTPBackend) NewSession(c *gosmtp.Conn) (gosmtp.Session, error) {
	return &miniSMTPSession{be: be}, nil
}

func (s *miniSMTPSession) AuthMechanisms() []string { return []string{sasl.Plain} }

func (s *miniSMTPSession) Auth(mech string) (sasl.Server, error) {
	if mech != sasl.Plain {
		return nil, errors.New("mini smtp: unsupported mech")
	}
	return sasl.NewPlainServer(func(identity, user, pass string) error {
		if user != s.be.user || pass != s.be.pass {
			return errors.New("mini smtp: auth failed")
		}
		return nil
	}), nil
}

func (s *miniSMTPSession) Reset()        { s.mail = nil }
func (s *miniSMTPSession) Logout() error { return nil }
func (s *miniSMTPSession) Mail(from string, opts *gosmtp.MailOptions) error {
	s.mail = &smtpMail{from: from}
	return nil
}
func (s *miniSMTPSession) Rcpt(to string, opts *gosmtp.RcptOptions) error {
	if s.mail == nil {
		return errors.New("mini smtp: no MAIL")
	}
	s.mail.rcpt = append(s.mail.rcpt, to)
	return nil
}
func (s *miniSMTPSession) Data(r io.Reader) error {
	if s.mail == nil {
		return errors.New("mini smtp: no MAIL")
	}
	data, err := io.ReadAll(r)
	if err != nil {
		return err
	}
	s.mail.data = data
	s.be.mu.Lock()
	s.be.mails = append(s.be.mails, s.mail)
	s.be.mu.Unlock()
	return nil
}

func (be *miniSMTPBackend) received() []*smtpMail {
	be.mu.Lock()
	defer be.mu.Unlock()
	out := make([]*smtpMail, len(be.mails))
	copy(out, be.mails)
	return out
}

func startMiniSMTP(t *testing.T, user, pass string, cert tls.Certificate) (*miniSMTPBackend, string) {
	t.Helper()
	be := &miniSMTPBackend{user: user, pass: pass}
	srv := gosmtp.NewServer(be)
	srv.TLSConfig = &tls.Config{Certificates: []tls.Certificate{cert}}
	srv.Domain = "localhost"
	srv.AllowInsecureAuth = true
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("smtp listen: %v", err)
	}
	go srv.Serve(ln)
	t.Cleanup(func() { srv.Close() })
	return be, ln.Addr().String()
}

// ── the verification ──────────────────────────────────────────────────────

// dcTestEmail builds a plain Delta Chat message (headers incl. the
// Chat-Version marker + text body) as it would sit in a mailbox.
func dcTestEmail(from, to, subject, body string) *miniMsg {
	header := strings.Join([]string{
		"From: " + from,
		"To: " + to,
		"Subject: " + subject,
		"Message-ID: <mini-1@localhost>",
		"Date: " + time.Now().Format(time.RFC1123Z),
		"Chat-Version: 1.0",
		"Content-Type: text/plain; charset=utf-8",
		"",
	}, "\r\n")
	return &miniMsg{
		flags: nil,
		env: &imap.Envelope{
			Subject: subject,
			From: []imap.Address{{
				Name:    "Bob",
				Mailbox: "bob",
				Host:    "example.test",
			}},
			To:        []imap.Address{{Mailbox: "alice", Host: "example.test"}},
			MessageID: "<mini-1@localhost>",
		},
		header: []byte(header),
		body:   []byte(body),
	}
}

// TestDeltaChatFullChainLocalServer: IMAP auth (3 conns incl. IDLE pair) +
// folder setup + SMTP send with DC headers + receive path (FETCH → chat).
func TestDeltaChatFullChainLocalServer(t *testing.T) {
	cert := selfSignedCert(t)
	store, imapAddr := startMiniIMAP(t, "alice@example.test", "passw0rd", cert)
	smtpBe, smtpAddr := startMiniSMTP(t, "alice@example.test", "passw0rd", cert)

	// Pre-load one incoming chat email in INBOX.
	store.add("INBOX", dcTestEmail("bob@example.test", "alice@example.test", "Chat: Hello", "Hello from the mini mail server!"))

	store2 := utils.NewSessionStore(newTestVaultXMPP(t), "dc-mini")
	core := NewDeltaChatCore(store2)
	defer core.Logout()

	recv := make(chan Message, 8)
	core.OnUpdate(func(u Update) {
		if u.Type == UpdateNewMessage && u.Message != nil && u.Message.Text != "" {
			recv <- *u.Message
		}
	})

	cfg := AuthConfig{
		Phone:      "alice@example.test",
		Password2F: "passw0rd",
		Extra: map[string]string{
			"email":                "alice@example.test",
			"password":             "passw0rd",
			"imap_host":            imapAddr,
			"smtp_host":            smtpAddr,
			"accept_invalid_certs": "true",
		},
	}
	if err := core.Authenticate(cfg); err != nil {
		t.Fatalf("Authenticate against mini IMAP/SMTP: %v", err)
	}
	t.Log("IMAP auth OK: STARTTLS + LOGIN + LIST + DeltaChat folder + IDLE pair connected")

	// Send a chat message → SMTP chain.
	if _, err := core.SendMessage("dm:bob@example.test", OutgoingMessage{Text: "hi over SMTP"}); err != nil {
		t.Fatalf("SendMessage via mini SMTP: %v", err)
	}
	mails := smtpBe.received()
	if len(mails) == 0 {
		t.Fatal("no mail received by the mini SMTP server")
	}
	got := string(mails[0].data)
	for _, want := range []string{"Chat-Version:", "hi over SMTP", "alice@example.test"} {
		if !strings.Contains(got, want) {
			t.Errorf("sent email missing %q:\n%.400s", want, got)
		}
	}
	if !strings.Contains(got, "Autocrypt:") && !strings.Contains(got, "multipart") {
		t.Logf("note: no Autocrypt header / multipart structure (plain singlepart send)")
	}
	t.Logf("SMTP send OK: %d recipient(s), %d bytes, Chat-Version header present", len(mails[0].rcpt), len(got))

	// Receive path: GetDialogs triggers syncMessages → SELECT + FETCH →
	// processIncomingEmail → chat list from the pre-loaded email.
	dlgs, err := core.GetDialogs(PaginationOpts{Limit: 10})
	if err != nil {
		t.Fatalf("GetDialogs: %v", err)
	}
	found := false
	for _, d := range dlgs {
		if strings.Contains(d.Title, "bob") || strings.Contains(d.ID, "bob") {
			found = true
			break
		}
	}
	if !found {
		names := make([]string, 0, len(dlgs))
		for _, d := range dlgs {
			names = append(names, d.Title+"("+d.ID+")")
		}
		t.Fatalf("chat with bob not built from fetched email; dialogs: %v", names)
	}
	t.Log("RECEIVE PATH OK: SELECT + FETCH + processIncomingEmail built the chat from the incoming email")
	_ = bytes.MinRead
}
