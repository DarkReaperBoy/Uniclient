package cores

import (
	"bufio"
	"bytes"
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha1"
	"crypto/sha256"
	"crypto/tls"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"encoding/xml"
	"errors"
	"fmt"
	"hash"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"sort"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"
	"unicode/utf16"
	"unicode/utf8"

	"uniclient/utils"
)

const xmppPlatform = "xmpp"

const (
	xmppDefaultPort    = "5222"
	xmppDirectTLSPort  = "5223"
	xmppMsgBufSize     = 500
	xmppPingInterval   = 60 * time.Second
	xmppSendDelay      = 100 * time.Millisecond
	XMPPIQTimeout      = 30 * time.Second
	xmppReconnectDelay = 5 * time.Second
)

const (
	nsStream     = "http://etherx.jabber.org/streams"
	nsClient     = "jabber:client"
	nsTLS        = "urn:ietf:params:xml:ns:xmpp-tls"
	nsSASL       = "urn:ietf:params:xml:ns:xmpp-sasl"
	NsBind       = "urn:ietf:params:xml:ns:xmpp-bind"
	nsSession    = "urn:ietf:params:xml:ns:xmpp-session"
	nsRoster     = "jabber:iq:roster"
	nsDiscoInfo  = "http://jabber.org/protocol/disco#info"
	nsDiscoItem  = "http://jabber.org/protocol/disco#items"
	nsMUC        = "http://jabber.org/protocol/muc"
	nsMUCUser    = "http://jabber.org/protocol/muc#user"
	nsMUCAdmin   = "http://jabber.org/protocol/muc#admin"
	nsMUCOwner   = "http://jabber.org/protocol/muc#owner"
	nsDirectMUC  = "jabber:x:conference"
	nsChatState  = "http://jabber.org/protocol/chatstates"
	nsReceipts   = "urn:xmpp:receipts"
	nsCorrect    = "urn:xmpp:message-correct:0"
	nsCarbons    = "urn:xmpp:carbons:2"
	nsForward    = "urn:xmpp:forward:0"
	nsMAM        = "urn:xmpp:mam:2"
	nsRSM        = "http://jabber.org/protocol/rsm"
	nsBlocking   = "urn:xmpp:blocking"
	nsBookmarks  = "storage:bookmarks"
	nsBmk2       = "urn:xmpp:bookmarks:1"
	nsPubSub     = "http://jabber.org/protocol/pubsub"
	nsPubEvent   = "http://jabber.org/protocol/pubsub#event"
	nsPubOwner   = "http://jabber.org/protocol/pubsub#owner"
	nsUpload     = "urn:xmpp:http:upload:0"
	nsOOB        = "jabber:x:oob"
	nsVCard      = "vcard-temp"
	nsPing       = "urn:xmpp:ping"
	nsVersion    = "jabber:iq:version"
	nsLast       = "jabber:iq:last"
	nsTime       = "urn:xmpp:time"
	nsSM         = "urn:xmpp:sm:3"
	nsCSI        = "urn:xmpp:csi:0"
	nsCaps       = "http://jabber.org/protocol/caps"
	nsReply      = "urn:xmpp:reply:0"
	nsReactions  = "urn:xmpp:reactions:0"
	nsMarkers    = "urn:xmpp:chat-markers:0"
	nsHints      = "urn:xmpp:hints"
	nsRegister   = "jabber:iq:register"
	nsXData      = "jabber:x:data"
	nsDelay      = "urn:xmpp:delay"
	nsJingle     = "urn:xmpp:jingle:1"
	nsJingleRTP  = "urn:xmpp:jingle:apps:rtp:1"
	nsJingleICE  = "urn:xmpp:jingle:transports:ice-udp:1"
	nsExtSvc     = "urn:xmpp:extdisco:2"
	nsMood       = "http://jabber.org/protocol/mood"
	nsActivity   = "http://jabber.org/protocol/activity"
	nsTune       = "http://jabber.org/protocol/tune"
	nsGeoLoc     = "http://jabber.org/protocol/geoloc"
	nsAvatarData = "urn:xmpp:avatar:data"
	nsAvatarMeta = "urn:xmpp:avatar:metadata"
	nsPrivate    = "jabber:iq:private"
)

type xmppFeatures struct {
	StartTLS   *xmppTLSFeature `xml:"urn:ietf:params:xml:ns:xmpp-tls starttls"`
	Mechanisms *xmppSASLMechs  `xml:"urn:ietf:params:xml:ns:xmpp-sasl mechanisms"`
	Bind       *xml.Name       `xml:"urn:ietf:params:xml:ns:xmpp-bind bind"`
	Session    *xml.Name       `xml:"urn:ietf:params:xml:ns:xmpp-session session"`
	SM         *xml.Name       `xml:"urn:xmpp:sm:3 sm"`
	CSI        *xml.Name       `xml:"urn:xmpp:csi:0 csi"`
	RosterVer  *xml.Name       `xml:"urn:xmpp:features:rosterver ver"`
	IBR        *xml.Name       `xml:"http://jabber.org/features/iq-register register"`
	InnerXML   string          `xml:",innerxml"`
}

type xmppTLSFeature struct {
	Required *xml.Name `xml:"required"`
}

type xmppSASLMechs struct {
	Mechanism []string `xml:"mechanism"`
}

type XMPPIQ struct {
	XMLName xml.Name         `xml:"iq"`
	Type    string           `xml:"type,attr"`
	ID      string           `xml:"id,attr,omitempty"`
	To      string           `xml:"to,attr,omitempty"`
	From    string           `xml:"from,attr,omitempty"`
	Lang    string           `xml:"xml:lang,attr,omitempty"`
	Inner   string           `xml:",innerxml"`
	Error   *XMPPStanzaError `xml:"error"`
}

type xmppMessage struct {
	XMLName xml.Name `xml:"message"`
	Type    string   `xml:"type,attr,omitempty"`
	ID      string   `xml:"id,attr,omitempty"`
	To      string   `xml:"to,attr,omitempty"`
	From    string   `xml:"from,attr,omitempty"`
	Lang    string   `xml:"xml:lang,attr,omitempty"`
	Inner   string   `xml:",innerxml"`
}

type xmppPresence struct {
	XMLName xml.Name `xml:"presence"`
	Type    string   `xml:"type,attr,omitempty"`
	ID      string   `xml:"id,attr,omitempty"`
	To      string   `xml:"to,attr,omitempty"`
	From    string   `xml:"from,attr,omitempty"`
	Lang    string   `xml:"xml:lang,attr,omitempty"`
	Inner   string   `xml:",innerxml"`
}

type XMPPStanzaError struct {
	Type  string `xml:"type,attr,omitempty"`
	Code  string `xml:"code,attr,omitempty"`
	Text  string `xml:"text,omitempty"`
	Inner string `xml:",innerxml"`
}

type xmppParsedMessage struct {
	Body           string
	Subject        string
	Thread         string
	OOB            string
	Delay          *time.Time
	DelayFrom      string
	ReceiptRequest bool
	ReceiptFor     string
	ChatState      string
	ReplaceID      string
	DisplayedID    string
	ReceivedID     string
	ReplyTo        string
	ReplyID        string
	ReactionsID    string
	Reactions      []string
	MUCInviteFrom  string
	MUCInviteRoom  string
	CarbonType     string
	CarbonMsg      *xmppParsedMessage
	MAMID          string
	MAMQueryID     string
	MAMMsg         *xmppParsedMessage
	ForwardedFrom  string
}

type XmppRosterItem struct {
	JID          string   `xml:"jid,attr"`
	Name         string   `xml:"name,attr,omitempty"`
	Subscription string   `xml:"subscription,attr,omitempty"`
	Groups       []string `xml:"group"`
	Ask          string   `xml:"ask,attr,omitempty"`
}

type xmppSession struct {
	JID            string         `json:"jid"`
	Server         string         `json:"server"`
	Resource       string         `json:"resource"`
	MUCService     string         `json:"muc_service,omitempty"`
	UploadService  string         `json:"upload_service,omitempty"`
	UploadMaxSize  int64          `json:"upload_max_size,omitempty"`
	JoinedRooms    []string       `json:"joined_rooms,omitempty"`
	Bookmarks      []xmppBookmark `json:"bookmarks,omitempty"`
	Blocked        []string       `json:"blocked,omitempty"`
	RosterVer      string         `json:"roster_ver,omitempty"`
	SMEnabled      bool           `json:"sm_enabled,omitempty"`
	SMResumeID     string         `json:"sm_resume_id,omitempty"`
	CarbonsEnabled bool           `json:"carbons_enabled,omitempty"`
}

type xmppBookmark struct {
	JID      string `json:"jid"`
	Name     string `json:"name,omitempty"`
	Nick     string `json:"nick,omitempty"`
	AutoJoin bool   `json:"autojoin,omitempty"`
}

type xmppRoom struct {
	JID       string
	Name      string
	Nick      string
	Subject   string
	SubjectBy string
	Occupants map[string]*xmppOccupant
	Joined    bool
	Config    map[string]string
}

type xmppOccupant struct {
	Nick        string
	RealJID     string
	Role        string
	Affiliation string
	Show        string
	Status      string
}

type xmppPendingIQ struct {
	ch      chan *XMPPIQ
	timeout *time.Timer
}

type XMPPCore struct {
	mu     sync.RWMutex
	authed bool

	conn    net.Conn
	tlsConn *tls.Conn
	reader  *bufio.Reader
	encoder *xml.Encoder
	decoder *xml.Decoder
	writeMu sync.Mutex

	jid          string
	bareJID      string
	domain       string
	server       string
	resource     string
	password     string
	tlsMode      string
	saslMech     string
	wantRegister bool

	features      xmppFeatures
	serverFeats   []string
	mucService    string
	uploadService string
	uploadMaxSize int64

	roster    map[string]*XmppRosterItem
	rosterMu  sync.RWMutex
	rosterVer string

	rooms   map[string]*xmppRoom
	roomsMu sync.RWMutex

	messages   map[string][]*Message
	messagesMu sync.RWMutex
	msgCounter int64

	pinned   map[string]map[string]bool
	pinnedMu sync.RWMutex

	readState   map[string]*ReadState
	readStateMu sync.RWMutex

	blocked   map[string]bool
	blockedMu sync.RWMutex

	pendingIQ   map[string]*xmppPendingIQ
	pendingIQMu sync.Mutex
	iqCounter   atomic.Int64

	smEnabled  bool
	smResumeID string
	smInH      atomic.Int64
	smOutH     atomic.Int64
	smOutQueue []*bytes.Buffer
	smOutMu    sync.Mutex

	carbonsEnabled bool

	bookmarks   []xmppBookmark
	bookmarksMu sync.RWMutex

	vcardCache   map[string]map[string]string
	vcardCacheMu sync.RWMutex

	capsElement     string
	capsElementOnce sync.Once

	updateHandlers []func(Update)
	updateMu       sync.RWMutex

	streamMaxBytes    int
	streamIdleSeconds int

	session *utils.SessionStore
	ctx     context.Context
	cancel  context.CancelFunc
	wg      sync.WaitGroup
}

var _ Core = (*XMPPCore)(nil)

func NewXMPPCore(session *utils.SessionStore) *XMPPCore {
	ctx, cancel := context.WithCancel(context.Background())
	return &XMPPCore{
		roster:     make(map[string]*XmppRosterItem),
		rooms:      make(map[string]*xmppRoom),
		messages:   make(map[string][]*Message),
		pinned:     make(map[string]map[string]bool),
		readState:  make(map[string]*ReadState),
		blocked:    make(map[string]bool),
		pendingIQ:  make(map[string]*xmppPendingIQ),
		vcardCache: make(map[string]map[string]string),
		session:    session,
		ctx:        ctx,
		cancel:     cancel,
	}
}

func (c *XMPPCore) Name() string { return xmppPlatform }

func (c *XMPPCore) Capabilities() []string {
	return []string{
		CapText, CapChannels, CapCalls, CapReactions, CapReadReceipts,
		CapTyping, CapBlocking, CapSearch, CapPresence, CapE2EE,
		CapFileTransfer,
	}
}

func (c *XMPPCore) Authenticate(cfg AuthConfig) error {
	c.mu.Lock()
	if c.authed {
		c.mu.Unlock()
		return errors.New("already authenticated")
	}
	c.mu.Unlock()

	server := cfg.Extra["server"]
	if server == "" {
		parts := strings.SplitN(cfg.Extra["jid"], "@", 2)
		if len(parts) < 2 && cfg.Phone != "" {
			parts = strings.SplitN(cfg.Phone, "@", 2)
		}
		if len(parts) < 2 {
			return fmt.Errorf("%w: server or jid@domain required in Extra", ErrInvalidInput)
		}
		server = parts[1] + ":" + xmppDefaultPort
	}
	if !strings.Contains(server, ":") {
		server += ":" + xmppDefaultPort
	}

	jidLocal := cfg.Extra["jid"]
	if jidLocal == "" {
		jidLocal = cfg.Phone
	}
	if jidLocal == "" {
		return fmt.Errorf("%w: jid required (in Extra[\"jid\"] or Phone field)", ErrInvalidInput)
	}

	password := cfg.Extra["password"]
	if password == "" {
		password = cfg.BotToken
	}
	if password == "" {
		password = cfg.Password2F
	}
	if password == "" {
		return fmt.Errorf("%w: password required", ErrInvalidInput)
	}

	c.mu.Lock()
	c.server = server
	c.password = password
	c.resource = cfg.Extra["resource"]
	if c.resource == "" {
		c.resource = "uniclient"
	}
	c.tlsMode = cfg.Extra["tls"]
	if c.tlsMode == "" {
		c.tlsMode = "starttls"
	}
	c.saslMech = cfg.Extra["mechanism"]
	c.wantRegister = cfg.Extra["register"] == "true" || cfg.Extra["register"] == "1"
	if svc := cfg.Extra["muc_service"]; svc != "" {
		c.mucService = svc
	}
	if svc := cfg.Extra["upload_service"]; svc != "" {
		c.uploadService = svc
	}

	if at := strings.Index(jidLocal, "@"); at > 0 {
		c.bareJID = jidLocal
		c.domain = jidLocal[at+1:]
	} else {
		host, _, _ := net.SplitHostPort(server)
		c.domain = host
		c.bareJID = jidLocal + "@" + c.domain
	}
	c.mu.Unlock()

	c.loadSession()

	if err := c.connectAndAuth(); err != nil {
		c.mu.Lock()
		if c.conn != nil {
			c.conn.Close()
			c.conn = nil
			c.tlsConn = nil
			c.reader = nil
			c.decoder = nil
		}
		c.mu.Unlock()
		return fmt.Errorf("%w: %v", ErrAuth, err)
	}

	c.mu.Lock()
	c.authed = true
	c.mu.Unlock()

	c.wg.Add(1)
	go c.readLoop()
	c.wg.Add(1)
	go c.pingLoop()

	c.postAuthSetup()

	return nil
}

func (c *XMPPCore) postAuthSetup() {
	c.requestRoster()

	c.EnableCarbons()

	if c.features.SM != nil {
		c.EnableStreamManagement()
	}

	go c.discoverServices()

	c.SendPresenceAvailable("", "")

	go c.autoJoinBookmarks()
}

func (c *XMPPCore) Logout() error {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return ErrAuth
	}
	c.mu.RUnlock()

	c.SendPresenceUnavailable("Logged out")

	c.writeMu.Lock()
	if c.encoder != nil {
		c.encoder.Flush()
		c.conn.Write([]byte("</stream:stream>"))
	}
	c.writeMu.Unlock()

	c.saveSession()
	c.cancel()

	c.mu.Lock()
	c.authed = false
	if c.conn != nil {
		c.conn.Close()
	}
	c.mu.Unlock()

	return nil
}

func (c *XMPPCore) connectAndAuth() error {
	var conn net.Conn
	var err error

	c.mu.RLock()
	server := c.server
	tlsMode := c.tlsMode
	domain := c.domain
	c.mu.RUnlock()

	dialer := &net.Dialer{Timeout: 15 * time.Second}
	conn, err = dialer.DialContext(c.ctx, "tcp", server)
	if err != nil {
		return fmt.Errorf("tcp connect: %w", err)
	}

	if tlsMode == "direct" {
		tlsConf := &tls.Config{ServerName: domain}
		tlsConn := tls.Client(conn, tlsConf)
		if err := tlsConn.HandshakeContext(c.ctx); err != nil {
			conn.Close()
			return fmt.Errorf("tls handshake: %w", err)
		}
		conn = tlsConn
		c.mu.Lock()
		c.tlsConn = tlsConn
		c.mu.Unlock()
	}

	c.mu.Lock()
	c.conn = conn
	c.reader = bufio.NewReaderSize(conn, 8192)
	c.encoder = xml.NewEncoder(conn)
	c.mu.Unlock()

	if err := c.sendStreamHeader(); err != nil {
		return err
	}

	if err := c.readStreamStart(); err != nil {
		return err
	}

	if tlsMode == "starttls" && c.features.StartTLS != nil {
		if err := c.startTLS(); err != nil {
			return err
		}
	}

	c.mu.RLock()
	wantReg := c.wantRegister
	c.mu.RUnlock()
	if wantReg {
		if err := c.registerPreAuth(); err != nil {
			return err
		}
		c.mu.Lock()
		c.wantRegister = false
		c.mu.Unlock()
	}

	if err := c.authenticate(); err != nil {
		return err
	}

	if err := c.bindResource(); err != nil {
		return err
	}

	if c.features.Session != nil {
		c.establishSession()
	}

	return nil
}

func (c *XMPPCore) sendStreamHeader() error {
	c.mu.RLock()
	domain := c.domain
	c.mu.RUnlock()

	var b strings.Builder
	b.Grow(200)
	b.WriteString("<?xml version='1.0'?><stream:stream to='")
	b.WriteString(xmlEscape(domain))
	b.WriteString("' xmlns='")
	b.WriteString(nsClient)
	b.WriteString("' xmlns:stream='")
	b.WriteString(nsStream)
	b.WriteString("' version='1.0'>")

	c.writeMu.Lock()
	_, err := c.conn.Write([]byte(b.String()))
	c.writeMu.Unlock()
	return err
}

func (c *XMPPCore) readStreamStart() error {
	c.mu.RLock()
	reader := c.reader
	c.mu.RUnlock()

	c.conn.SetReadDeadline(time.Now().Add(15 * time.Second))
	defer c.conn.SetReadDeadline(time.Time{})

	var buf bytes.Buffer
	buf.Grow(2048)
	endTag1 := []byte("</stream:features>")
	endTag2 := []byte("</features>")
	for {
		b, err := reader.ReadByte()
		if err != nil {
			return fmt.Errorf("read stream: %w", err)
		}
		buf.WriteByte(b)
		if buf.Len() > streamHeadMax {
			return fmt.Errorf("stream header exceeds %d bytes", streamHeadMax)
		}

		if b != '>' {
			continue
		}

		data := buf.Bytes()
		if bytes.Contains(data, endTag1) || bytes.Contains(data, endTag2) {
			c.mu.Lock()
			c.decoder = xml.NewDecoder(reader)
			c.mu.Unlock()
			return c.ParseStreamFeatures(buf.String())
		}
	}
}

func (c *XMPPCore) ParseStreamFeatures(data string) error {
	var featXML string
	if idx := strings.Index(data, "<stream:features>"); idx >= 0 {
		end := strings.Index(data, "</stream:features>")
		if end > idx {
			featXML = data[idx+len("<stream:features>") : end]
		}
	} else if idx := strings.Index(data, "<features>"); idx >= 0 {
		end := strings.Index(data, "</features>")
		if end > idx {
			featXML = data[idx+len("<features>") : end]
		}
	}

	if featXML == "" {
		return errors.New("no features found in stream")
	}

	var feats xmppFeatures

	if strings.Contains(featXML, nsTLS) {
		feats.StartTLS = &xmppTLSFeature{}
		if strings.Contains(featXML, "<required") {
			feats.StartTLS.Required = &xml.Name{}
		}
	}

	if strings.Contains(featXML, nsSASL) {
		feats.Mechanisms = &xmppSASLMechs{}
		remaining := featXML
		for {
			mStart := strings.Index(remaining, "<mechanism>")
			if mStart < 0 {
				break
			}
			mEnd := strings.Index(remaining[mStart:], "</mechanism>")
			if mEnd < 0 {
				break
			}
			mech := remaining[mStart+len("<mechanism>") : mStart+mEnd]
			feats.Mechanisms.Mechanism = append(feats.Mechanisms.Mechanism, mech)
			remaining = remaining[mStart+mEnd+len("</mechanism>"):]
		}
	}

	if strings.Contains(featXML, NsBind) {
		feats.Bind = &xml.Name{}
	}

	if strings.Contains(featXML, nsSession) {
		feats.Session = &xml.Name{}
	}

	if strings.Contains(featXML, nsSM) {
		feats.SM = &xml.Name{}
	}

	if strings.Contains(featXML, nsCSI) {
		feats.CSI = &xml.Name{}
	}

	if strings.Contains(featXML, "rosterver") {
		feats.RosterVer = &xml.Name{}
	}

	if strings.Contains(featXML, "jabber.org/features/iq-register") {
		feats.IBR = &xml.Name{}
	}

	feats.InnerXML = featXML

	c.mu.Lock()
	c.features = feats
	c.mu.Unlock()

	c.decoder = xml.NewDecoder(c.conn)

	return nil
}

func (c *XMPPCore) startTLS() error {
	c.writeMu.Lock()
	c.conn.Write([]byte("<starttls xmlns='" + nsTLS + "'/>"))
	c.writeMu.Unlock()

	c.conn.SetReadDeadline(time.Now().Add(10 * time.Second))
	var buf bytes.Buffer
	for {
		b, err := c.reader.ReadByte()
		if err != nil {
			return fmt.Errorf("starttls read: %w", err)
		}
		buf.WriteByte(b)
		if buf.Len() > starttlsMax {
			return fmt.Errorf("starttls element exceeds %d bytes", starttlsMax)
		}
		data := buf.String()
		if strings.Contains(data, "/>") || strings.Contains(data, "</proceed>") || strings.Contains(data, "</failure>") {
			if strings.Contains(data, "failure") {
				return errors.New("starttls: server refused")
			}
			break
		}
	}
	c.conn.SetReadDeadline(time.Time{})

	c.mu.RLock()
	domain := c.domain
	c.mu.RUnlock()

	tlsConf := &tls.Config{ServerName: domain}
	tlsConn := tls.Client(c.conn, tlsConf)
	if err := tlsConn.HandshakeContext(c.ctx); err != nil {
		return fmt.Errorf("tls handshake: %w", err)
	}

	c.mu.Lock()
	c.conn = tlsConn
	c.tlsConn = tlsConn
	c.reader = bufio.NewReaderSize(tlsConn, 8192)
	c.encoder = xml.NewEncoder(tlsConn)
	c.mu.Unlock()

	if err := c.sendStreamHeader(); err != nil {
		return err
	}
	return c.readStreamStart()
}

func (c *XMPPCore) authenticate() error {
	c.mu.RLock()
	mechs := c.features.Mechanisms
	preferred := c.saslMech
	c.mu.RUnlock()

	if mechs == nil || len(mechs.Mechanism) == 0 {
		return errors.New("no SASL mechanisms offered")
	}

	available := make(map[string]bool)
	for _, m := range mechs.Mechanism {
		available[m] = true
	}

	var mech string
	if preferred != "" {
		mech = strings.ToUpper(strings.ReplaceAll(preferred, "-", "-"))
		if !available[mech] {
			return fmt.Errorf("requested mechanism %s not available (have: %v)", mech, mechs.Mechanism)
		}
	} else {
		switch {
		case available["SCRAM-SHA-256"]:
			mech = "SCRAM-SHA-256"
		case available["SCRAM-SHA-1"]:
			mech = "SCRAM-SHA-1"
		case available["PLAIN"]:
			mech = "PLAIN"
		default:
			return fmt.Errorf("no supported SASL mechanism (have: %v)", mechs.Mechanism)
		}
	}

	switch mech {
	case "PLAIN":
		return c.authSASLPlain()
	case "SCRAM-SHA-1":
		return c.authSASLScram(sha1.New, "SCRAM-SHA-1")
	case "SCRAM-SHA-256":
		return c.authSASLScram(sha256.New, "SCRAM-SHA-256")
	default:
		return fmt.Errorf("unsupported mechanism: %s", mech)
	}
}

func (c *XMPPCore) authSASLPlain() error {
	c.mu.RLock()
	bareJID := c.bareJID
	password := c.password
	c.mu.RUnlock()

	local := bareJID
	if at := strings.Index(bareJID, "@"); at > 0 {
		local = bareJID[:at]
	}

	payload := base64.StdEncoding.EncodeToString([]byte("\x00" + local + "\x00" + password))

	c.writeMu.Lock()
	c.conn.Write([]byte("<auth xmlns='" + nsSASL + "' mechanism='PLAIN'>" + payload + "</auth>"))
	c.writeMu.Unlock()

	return c.readSASLResult()
}

const (
	SaslElementMax = 16 << 10
	streamHeadMax  = 64 << 10
	iqResponseMax  = 8 << 20
	starttlsMax    = 4 << 10
	scramIterMin   = 1
	scramIterMax   = 1_000_000
	scramSaltMax   = 1024
)

func ParseScramServerFirst(serverFirst, clientNonce string) (serverNonce string, salt []byte, iterations int, err error) {
	params := parseSCRAMParams(serverFirst)
	serverNonce = params["r"]
	if !strings.HasPrefix(serverNonce, clientNonce) {
		return "", nil, 0, errors.New("scram: server nonce doesn't start with client nonce")
	}
	salt, err = base64.StdEncoding.DecodeString(params["s"])
	if err != nil {
		return "", nil, 0, fmt.Errorf("scram: bad salt: %w", err)
	}
	if len(salt) > scramSaltMax {
		return "", nil, 0, fmt.Errorf("scram: salt too large (%d bytes, max %d)", len(salt), scramSaltMax)
	}
	iterations, err = strconv.Atoi(params["i"])
	if err != nil {
		return "", nil, 0, fmt.Errorf("scram: bad iterations: %w", err)
	}
	if iterations < scramIterMin || iterations > scramIterMax {
		return "", nil, 0, fmt.Errorf("scram: iterations out of range (%d)", iterations)
	}
	return serverNonce, salt, iterations, nil
}

func (c *XMPPCore) authSASLScram(hashFunc func() hash.Hash, mechName string) error {
	c.mu.RLock()
	bareJID := c.bareJID
	password := c.password
	c.mu.RUnlock()

	local := bareJID
	if at := strings.Index(bareJID, "@"); at > 0 {
		local = bareJID[:at]
	}

	nonceBytes := make([]byte, 24)
	rand.Read(nonceBytes)
	clientNonce := base64.StdEncoding.EncodeToString(nonceBytes)

	clientFirstBare := fmt.Sprintf("n=%s,r=%s", scramEscapeUsername(local), clientNonce)
	clientFirst := "n,," + clientFirstBare

	payload := base64.StdEncoding.EncodeToString([]byte(clientFirst))
	c.writeMu.Lock()
	c.conn.Write([]byte("<auth xmlns='" + nsSASL + "' mechanism='" + mechName + "'>" + payload + "</auth>"))
	c.writeMu.Unlock()

	challenge, err := c.readSASLChallenge()
	if err != nil {
		return err
	}

	serverFirst := string(challenge)
	serverNonce, salt, iterations, err := ParseScramServerFirst(serverFirst, clientNonce)
	if err != nil {
		return err
	}

	saltedPassword := xmppPBKDF2([]byte(password), salt, iterations, hashFunc().Size(), hashFunc)

	clientKey := hmacHash(hashFunc, saltedPassword, []byte("Client Key"))
	storedKey := hashBytes(hashFunc, clientKey)

	clientFinalNoProof := fmt.Sprintf("c=biws,r=%s", serverNonce)
	authMessage := clientFirstBare + "," + serverFirst + "," + clientFinalNoProof

	clientSig := hmacHash(hashFunc, storedKey, []byte(authMessage))
	clientProof := xorBytes(clientKey, clientSig)

	serverKey := hmacHash(hashFunc, saltedPassword, []byte("Server Key"))
	serverSig := hmacHash(hashFunc, serverKey, []byte(authMessage))

	clientFinal := clientFinalNoProof + ",p=" + base64.StdEncoding.EncodeToString(clientProof)

	respPayload := base64.StdEncoding.EncodeToString([]byte(clientFinal))
	c.writeMu.Lock()
	c.conn.Write([]byte("<response xmlns='" + nsSASL + "'>" + respPayload + "</response>"))
	c.writeMu.Unlock()

	successData, err := c.readSASLSuccess()
	if err != nil {
		return err
	}

	if successData != "" {
		decoded, _ := base64.StdEncoding.DecodeString(successData)
		sParams := parseSCRAMParams(string(decoded))
		if v, ok := sParams["v"]; ok {
			expectedSig := base64.StdEncoding.EncodeToString(serverSig)
			if v != expectedSig {
				return errors.New("scram: server signature mismatch")
			}
		}
	}

	if err := c.sendStreamHeader(); err != nil {
		return err
	}
	return c.readStreamStart()
}

func (c *XMPPCore) ReadSASLElement() (elemName, content string, err error) {
	c.conn.SetReadDeadline(time.Now().Add(15 * time.Second))
	defer c.conn.SetReadDeadline(time.Time{})

	var buf bytes.Buffer
	buf.Grow(512)
	for {
		b, readErr := c.reader.ReadByte()
		if readErr != nil {
			return "", "", fmt.Errorf("sasl read: %w", readErr)
		}
		buf.WriteByte(b)
		if buf.Len() > SaslElementMax {
			return "", "", fmt.Errorf("sasl element exceeds %d bytes", SaslElementMax)
		}
		if b != '>' {
			continue
		}
		if name, content, ok := SaslElementMatch(buf.String()); ok {
			return name, content, nil
		}
	}
}

func SaslElementMatch(data string) (name, content string, ok bool) {
	tags := [3]string{"challenge", "success", "failure"}
	if strings.HasSuffix(data, "/>") {
		if lt := strings.LastIndex(data, "<"); lt >= 0 {
			inner := data[lt+1 : len(data)-2]
			tag := inner
			if sp := strings.IndexAny(inner, " \t\r\n"); sp >= 0 {
				tag = inner[:sp]
			}
			for _, t := range tags {
				if tag == t {
					return t, "", true
				}
			}
		}
	}
	for _, t := range tags {
		closeTag := "</" + t + ">"
		if !strings.Contains(data, closeTag) {
			continue
		}
		startIdx := strings.Index(data, "<"+t)
		if startIdx < 0 {
			continue
		}
		rest := data[startIdx+1+len(t):]
		gt := strings.IndexByte(rest, '>')
		if gt < 0 {
			continue
		}
		rest = rest[gt+1:]
		endIdx := strings.Index(rest, closeTag)
		if endIdx < 0 {
			continue
		}
		return t, rest[:endIdx], true
	}
	return "", "", false
}

func (c *XMPPCore) readSASLChallenge() ([]byte, error) {
	name, content, err := c.ReadSASLElement()
	if err != nil {
		return nil, err
	}
	if name == "failure" {
		return nil, fmt.Errorf("%w: sasl failure: %s", ErrAuth, content)
	}
	if name != "challenge" {
		return nil, fmt.Errorf("expected challenge, got %s", name)
	}
	decoded, err := base64.StdEncoding.DecodeString(strings.TrimSpace(content))
	if err != nil {
		return nil, fmt.Errorf("decode challenge: %w", err)
	}
	return decoded, nil
}

func (c *XMPPCore) readSASLSuccess() (string, error) {
	name, content, err := c.ReadSASLElement()
	if err != nil {
		return "", err
	}
	if name == "failure" {
		return "", fmt.Errorf("%w: sasl failure: %s", ErrAuth, content)
	}
	if name != "success" {
		return "", fmt.Errorf("expected success, got %s", name)
	}
	return strings.TrimSpace(content), nil
}

func (c *XMPPCore) readSASLResult() error {
	name, content, err := c.ReadSASLElement()
	if err != nil {
		return err
	}
	if name == "failure" {
		return fmt.Errorf("%w: %s", ErrAuth, content)
	}
	if name != "success" {
		return fmt.Errorf("expected success, got %s", name)
	}
	if err := c.sendStreamHeader(); err != nil {
		return err
	}
	return c.readStreamStart()
}

func (c *XMPPCore) readRawIQResponse() (string, error) {
	c.conn.SetReadDeadline(time.Now().Add(15 * time.Second))
	defer c.conn.SetReadDeadline(time.Time{})

	var buf bytes.Buffer
	buf.Grow(1024)
	endTag := []byte("</iq>")
	for {
		b, err := c.reader.ReadByte()
		if err != nil {
			return "", fmt.Errorf("read iq: %w", err)
		}
		buf.WriteByte(b)
		if buf.Len() > iqResponseMax {
			return "", fmt.Errorf("iq response exceeds %d bytes", iqResponseMax)
		}
		if b != '>' {
			continue
		}
		if bytes.Contains(buf.Bytes(), endTag) {
			return buf.String(), nil
		}
		data := buf.String()
		if i := strings.Index(data, "<iq"); i >= 0 && strings.HasSuffix(data, "/>") {
			rest := data[i:]
			if gt := strings.IndexByte(rest, '>'); gt == len(rest)-1 {
				return data, nil
			}
		}
	}
}

func (c *XMPPCore) bindResource() error {
	c.mu.RLock()
	resource := c.resource
	c.mu.RUnlock()

	id := c.nextIQID()
	stanza := fmt.Sprintf(
		`<iq type='set' id='%s'><bind xmlns='%s'><resource>%s</resource></bind></iq>`,
		id, NsBind, xmlEscape(resource),
	)
	if err := c.sendRawStanza(stanza); err != nil {
		return fmt.Errorf("bind send: %w", err)
	}

	resp, err := c.readRawIQResponse()
	if err != nil {
		return fmt.Errorf("bind: %w", err)
	}

	if strings.Contains(resp, "type='error'") || strings.Contains(resp, `type="error"`) {
		return fmt.Errorf("bind error: %s", resp)
	}

	jid := ExtractXMLContent(resp, "jid")
	if jid != "" {
		c.mu.Lock()
		c.jid = jid
		if at := strings.Index(jid, "@"); at > 0 {
			if sl := strings.Index(jid, "/"); sl > 0 {
				c.bareJID = jid[:sl]
				c.resource = jid[sl+1:]
			} else {
				c.bareJID = jid
			}
		}
		c.mu.Unlock()
	}

	return nil
}

func (c *XMPPCore) establishSession() {
	id := c.nextIQID()
	stanza := fmt.Sprintf(`<iq type='set' id='%s'><session xmlns='%s'/></iq>`, id, nsSession)
	c.sendRawStanza(stanza)
	c.readRawIQResponse()
}

func (c *XMPPCore) readLoop() {
	defer c.wg.Done()
	for {
		select {
		case <-c.ctx.Done():
			return
		default:
		}

		tok, err := c.decoder.Token()
		if err != nil {
			if c.ctx.Err() != nil {
				return
			}
			if c.attemptReconnect() {
				continue
			}
			return
		}

		se, ok := tok.(xml.StartElement)
		if !ok {
			continue
		}

		switch se.Name.Local {
		case "message":
			var msg xmppMessage
			if err := c.decoder.DecodeElement(&msg, &se); err != nil {
				continue
			}
			go c.handleMessage(msg)

		case "presence":
			var pres xmppPresence
			if err := c.decoder.DecodeElement(&pres, &se); err != nil {
				continue
			}
			go c.handlePresence(pres)

		case "iq":
			var iq XMPPIQ
			if err := c.decoder.DecodeElement(&iq, &se); err != nil {
				continue
			}
			go c.handleIQ(iq)

		case "r":
			c.decoder.Skip()
			c.SendAck()

		case "a":
			var a struct {
				H int64 `xml:"h,attr"`
			}
			c.decoder.DecodeElement(&a, &se)
			c.handleAck(a.H)

		case "resumed":
			c.decoder.Skip()

		case "features":
			var feats xmppFeatures
			c.decoder.DecodeElement(&feats, &se)
			c.mu.Lock()
			c.features = feats
			c.mu.Unlock()

		default:
			c.decoder.Skip()
		}
	}
}

func (c *XMPPCore) attemptReconnect() bool {
	c.fireUpdate(Update{Type: UpdateConnectivity, ConnState: "disconnected"})

	c.mu.Lock()
	if c.conn != nil {
		c.conn.Close()
	}
	c.authed = false
	c.mu.Unlock()

	err := utils.Retry(c.ctx, 10, xmppReconnectDelay, 60*time.Second, nil, func() error {
		return c.connectAndAuth()
	})
	if err != nil {
		c.fireUpdate(Update{Type: UpdateConnectivity, ConnState: "disconnected"})
		return false
	}

	c.mu.Lock()
	c.authed = true
	c.mu.Unlock()

	c.postAuthSetup()

	c.fireUpdate(Update{Type: UpdateConnectivity, ConnState: "connected"})

	return true
}

func (c *XMPPCore) handleMessage(msg xmppMessage) {
	parsed := c.parseMessageInner(msg.Inner)

	from := msg.From
	fromBare := bareJID(from)
	chatID := fromBare

	if parsed.CarbonType != "" && parsed.CarbonMsg != nil {
		parsed = parsed.CarbonMsg
		if parsed.CarbonType == "sent" {
			chatID = bareJID(msg.To)
		}
	}

	if parsed.MAMID != "" && parsed.MAMMsg != nil {
		return
	}

	if parsed.ChatState != "" && parsed.Body == "" {
		if parsed.ChatState == "composing" {
			senderID := fromBare
			if msg.Type == "groupchat" {
				senderID = resourceFromJID(from)
			}
			c.fireUpdate(Update{
				Type:     UpdateTyping,
				ChatID:   chatID,
				UserID:   senderID,
				Platform: xmppPlatform,
			})
		}
		return
	}

	if parsed.ReceiptFor != "" {
		return
	}

	if parsed.DisplayedID != "" {
		c.readStateMu.Lock()
		if _, ok := c.readState[chatID]; !ok {
			c.readState[chatID] = &ReadState{PeerLastRead: make(map[string]string)}
		}
		c.readState[chatID].PeerLastRead[fromBare] = parsed.DisplayedID
		c.readStateMu.Unlock()
		c.fireUpdate(Update{
			Type:   UpdateReadState,
			ChatID: chatID,
			ReadState: &ReadState{
				PeerLastRead: map[string]string{fromBare: parsed.DisplayedID},
			},
			Platform: xmppPlatform,
		})
		return
	}

	if parsed.ReactionsID != "" && len(parsed.Reactions) > 0 {
		c.messagesMu.Lock()
		if msgs, ok := c.messages[chatID]; ok {
			for _, m := range msgs {
				if m.ID == parsed.ReactionsID {
					for _, emoji := range parsed.Reactions {
						found := false
						for i := range m.Reactions {
							if m.Reactions[i].Emoji == emoji {
								m.Reactions[i].Count++
								found = true
								break
							}
						}
						if !found {
							m.Reactions = append(m.Reactions, Reaction{Emoji: emoji, Count: 1})
						}
					}
					break
				}
			}
		}
		c.messagesMu.Unlock()
		return
	}

	if parsed.MUCInviteRoom != "" {
		m := &Message{
			ID:         msg.ID,
			ChatID:     chatID,
			SenderID:   fromBare,
			SenderName: fromBare,
			Text:       fmt.Sprintf("[MUC invitation to %s from %s]", parsed.MUCInviteRoom, parsed.MUCInviteFrom),
			Timestamp:  time.Now(),
			Status:     MessageStatusDelivered,
			IsOutgoing: false,
			Platform:   xmppPlatform,
		}
		c.bufferMessage(chatID, m)
		c.fireUpdate(Update{
			Type:     UpdateNewMessage,
			ChatID:   chatID,
			Message:  m,
			Platform: xmppPlatform,
		})
		return
	}

	if parsed.Body == "" && parsed.Subject == "" {
		return
	}

	if parsed.ReplaceID != "" {
		c.messagesMu.Lock()
		if msgs, ok := c.messages[chatID]; ok {
			for _, m := range msgs {
				if m.ID == parsed.ReplaceID {
					m.Text, m.Entities = ApplyStyling(parsed.Body)
					now := time.Now()
					m.EditedAt = &now
					c.messagesMu.Unlock()
					c.fireUpdate(Update{
						Type:     UpdateEditMessage,
						ChatID:   chatID,
						Message:  m,
						Platform: xmppPlatform,
					})
					return
				}
			}
		}
		c.messagesMu.Unlock()
	}

	if parsed.Subject != "" && msg.Type == "groupchat" {
		c.roomsMu.Lock()
		if room, ok := c.rooms[chatID]; ok {
			room.Subject = parsed.Subject
			room.SubjectBy = resourceFromJID(from)
		}
		c.roomsMu.Unlock()
		if parsed.Body == "" {
			return
		}
	}

	styledText, styledEntities := ApplyStyling(parsed.Body)
	ts := time.Now()
	if parsed.Delay != nil {
		ts = *parsed.Delay
	}

	senderID := fromBare
	senderName := fromBare
	if msg.Type == "groupchat" {
		nick := resourceFromJID(from)
		senderID = nick
		senderName = nick
	}

	msgID := msg.ID
	if msgID == "" {
		msgID = "xmpp_" + strconv.FormatInt(atomic.AddInt64(&c.msgCounter, 1), 10)
	}

	isOutgoing := false
	if msg.Type == "groupchat" {
		c.roomsMu.RLock()
		if room, ok := c.rooms[chatID]; ok {
			isOutgoing = room.Nick != "" && senderID == room.Nick
		}
		c.roomsMu.RUnlock()
	} else {
		isOutgoing = senderID == c.bareJID
	}

	m := &Message{
		ID:         msgID,
		ChatID:     chatID,
		SenderID:   senderID,
		SenderName: senderName,
		Text:       styledText,
		Entities:   styledEntities,
		Timestamp:  ts,
		Status:     MessageStatusDelivered,
		IsOutgoing: isOutgoing,
		Platform:   xmppPlatform,
	}

	if parsed.ReplyID != "" {
		m.ReplyToID = parsed.ReplyID
	}
	if parsed.OOB != "" {
		m.Attachments = []FileRef{{URL: parsed.OOB, Name: parsed.OOB}}
	}

	c.bufferMessage(chatID, m)

	if parsed.ReceiptRequest && msg.ID != "" {
		c.SendReceipt(from, msg.ID)
	}

	c.fireUpdate(Update{
		Type:     UpdateNewMessage,
		ChatID:   chatID,
		Message:  m,
		Platform: xmppPlatform,
	})
}

func (c *XMPPCore) handlePresence(pres xmppPresence) {
	from := pres.From
	fromBare := bareJID(from)

	if c.isRoom(fromBare) {
		c.handleMUCPresence(pres)
		return
	}

	switch pres.Type {
	case "subscribe":
		c.rosterMu.RLock()
		_, inRoster := c.roster[fromBare]
		c.rosterMu.RUnlock()
		if inRoster {
			c.SendPresenceSubscribed(fromBare)
		}
		c.fireUpdate(Update{
			Type:   UpdateNewMessage,
			ChatID: fromBare,
			Message: &Message{
				ID:         fmt.Sprintf("sub_%d", time.Now().UnixNano()),
				ChatID:     fromBare,
				SenderID:   fromBare,
				Text:       "[Subscription request]",
				Timestamp:  time.Now(),
				Status:     MessageStatusDelivered,
				IsOutgoing: false,
				Platform:   xmppPlatform,
			},
			Platform: xmppPlatform,
		})

	case "subscribed":

	case "unsubscribe", "unsubscribed":

	case "unavailable":
		isOnline := false
		c.fireUpdate(Update{
			Type:     UpdateUserStatus,
			UserID:   fromBare,
			IsOnline: &isOnline,
			Platform: xmppPlatform,
		})

	case "", "available":
		isOnline := true
		c.fireUpdate(Update{
			Type:     UpdateUserStatus,
			UserID:   fromBare,
			IsOnline: &isOnline,
			Platform: xmppPlatform,
		})

	case "error":
	}
}

func (c *XMPPCore) handleMUCPresence(pres xmppPresence) {
	roomJID := bareJID(pres.From)
	nick := resourceFromJID(pres.From)

	c.roomsMu.Lock()
	room, ok := c.rooms[roomJID]
	if !ok {
		room = &xmppRoom{
			JID:       roomJID,
			Occupants: make(map[string]*xmppOccupant),
		}
		c.rooms[roomJID] = room
	}

	if pres.Type == "unavailable" {
		delete(room.Occupants, nick)
		c.roomsMu.Unlock()
		c.fireUpdate(Update{
			Type:     UpdateGroupMembers,
			ChatID:   roomJID,
			UserID:   nick,
			Platform: xmppPlatform,
		})
		return
	}

	occ := &xmppOccupant{Nick: nick}
	if strings.Contains(pres.Inner, nsMUCUser) {
		occ.Role, occ.Affiliation, occ.RealJID = parseMUCUserItem(pres.Inner)
	}
	occ.Show, occ.Status = parsePresenceShowStatus(pres.Inner)

	room.Occupants[nick] = occ

	if strings.Contains(pres.Inner, `code='110'`) || strings.Contains(pres.Inner, `code="110"`) {
		room.Joined = true
		room.Nick = nick
	}

	c.roomsMu.Unlock()

	c.fireUpdate(Update{
		Type:     UpdateGroupMembers,
		ChatID:   roomJID,
		UserID:   nick,
		Platform: xmppPlatform,
	})
}

func (c *XMPPCore) handleIQ(iq XMPPIQ) {
	if iq.Type == "result" || iq.Type == "error" {
		c.pendingIQMu.Lock()
		if pending, ok := c.pendingIQ[iq.ID]; ok {
			delete(c.pendingIQ, iq.ID)
			c.pendingIQMu.Unlock()
			pending.timeout.Stop()
			pending.ch <- &iq
			return
		}
		c.pendingIQMu.Unlock()
		return
	}

	if iq.Type == "get" {
		escapedID := xmlEscape(iq.ID)
		escapedFrom := xmlEscape(iq.From)
		inner := iq.Inner

		if strings.Contains(inner, nsPing) {
			c.sendRawStanza("<iq type='result' id='" + escapedID + "' to='" + escapedFrom + "'/>")
			return
		}
		if strings.Contains(inner, nsVersion) {
			c.sendRawStanza("<iq type='result' id='" + escapedID + "' to='" + escapedFrom + "'><query xmlns='" + nsVersion + "'><name>Uniclient</name><version>1.0</version><os>Go</os></query></iq>")
			return
		}
		if strings.Contains(inner, nsDiscoInfo) {
			c.respondDiscoInfo(iq)
			return
		}
		if strings.Contains(inner, nsTime) {
			now := time.Now()
			c.sendRawStanza("<iq type='result' id='" + escapedID + "' to='" + escapedFrom + "'><time xmlns='" + nsTime + "'><tzo>" + now.Format("-07:00") + "</tzo><utc>" + now.UTC().Format("2006-01-02T15:04:05Z") + "</utc></time></iq>")
			return
		}
		if strings.Contains(inner, nsLast) {
			c.sendRawStanza("<iq type='result' id='" + escapedID + "' to='" + escapedFrom + "'><query xmlns='" + nsLast + "' seconds='0'/></iq>")
			return
		}
		c.sendRawStanza("<iq type='error' id='" + escapedID + "' to='" + escapedFrom + "'><error type='cancel'><service-unavailable xmlns='urn:ietf:params:xml:ns:xmpp-stanzas'/></error></iq>")
		return
	}

	if iq.Type == "set" {
		inner := iq.Inner
		if strings.Contains(inner, nsRoster) {
			c.handleRosterPush(iq)
			return
		}
		if strings.Contains(inner, nsBlocking) {
			c.handleBlocklistPush(iq)
			return
		}
		if strings.Contains(inner, nsJingle) {
			c.handleJingleAction(iq)
			return
		}
		c.sendRawStanza("<iq type='error' id='" + xmlEscape(iq.ID) + "' to='" + xmlEscape(iq.From) + "'><error type='cancel'><feature-not-implemented xmlns='urn:ietf:params:xml:ns:xmpp-stanzas'/></error></iq>")
	}
}

func XmppParseRoster(inner string) (items []XmppRosterItem, ver string, err error) {
	type rosterQuery struct {
		Items []XmppRosterItem `xml:"jabber:iq:roster query>item"`
		Ver   string           `xml:"jabber:iq:roster query>ver"`
	}
	var q rosterQuery
	if err := xml.Unmarshal([]byte("<r>"+inner+"</r>"), &q); err != nil {
		return nil, "", err
	}
	return q.Items, q.Ver, nil
}

func (c *XMPPCore) handleRosterPush(iq XMPPIQ) {
	c.sendRawStanza("<iq type='result' id='" + xmlEscape(iq.ID) + "'/>")

	items, ver, err := XmppParseRoster(iq.Inner)
	if err != nil {
		log.Printf("xmpp: roster push parse failed: %v", err)
		return
	}

	c.rosterMu.Lock()
	for _, item := range items {
		if item.Subscription == "remove" {
			delete(c.roster, item.JID)
		} else {
			c.roster[item.JID] = &item
		}
	}
	if ver != "" {
		c.rosterVer = ver
	}
	c.rosterMu.Unlock()
}

func (c *XMPPCore) handleBlocklistPush(iq XMPPIQ) {
	c.sendRawStanza("<iq type='result' id='" + xmlEscape(iq.ID) + "'/>")

	c.blockedMu.Lock()
	defer c.blockedMu.Unlock()

	if strings.Contains(iq.Inner, "<block") {
		jids := parseJIDsFromInner(iq.Inner, "item")
		for _, jid := range jids {
			c.blocked[jid] = true
		}
	}
	if strings.Contains(iq.Inner, "<unblock") {
		jids := parseJIDsFromInner(iq.Inner, "item")
		for _, jid := range jids {
			delete(c.blocked, jid)
		}
	}
}

func (c *XMPPCore) handleJingleAction(iq XMPPIQ) {
	c.sendRawStanza(fmt.Sprintf(`<iq type='result' id='%s' to='%s'/>`,
		xmlEscape(iq.ID), xmlEscape(iq.From)))
}

func (c *XMPPCore) nextIQID() string {
	return "iq_" + strconv.FormatInt(c.iqCounter.Add(1), 10)
}

func (c *XMPPCore) sendIQSync(typ, to, inner string) (*XMPPIQ, error) {
	id := c.nextIQID()
	ch := make(chan *XMPPIQ, 1)
	timer := time.NewTimer(XMPPIQTimeout)

	c.pendingIQMu.Lock()
	c.pendingIQ[id] = &xmppPendingIQ{ch: ch, timeout: timer}
	c.pendingIQMu.Unlock()

	var b strings.Builder
	b.Grow(64 + len(typ) + len(id) + len(to) + len(inner))
	b.WriteString("<iq type='")
	b.WriteString(typ)
	b.WriteString("' id='")
	b.WriteString(id)
	b.WriteByte('\'')
	if to != "" {
		b.WriteString(" to='")
		b.WriteString(xmlEscape(to))
		b.WriteByte('\'')
	}
	b.WriteByte('>')
	b.WriteString(inner)
	b.WriteString("</iq>")
	stanza := b.String()
	if err := c.sendRawStanza(stanza); err != nil {
		c.pendingIQMu.Lock()
		delete(c.pendingIQ, id)
		c.pendingIQMu.Unlock()
		timer.Stop()
		return nil, err
	}

	select {
	case resp := <-ch:
		if resp.Error != nil {
			errMsg := resp.Error.Type
			if resp.Error.Text != "" {
				errMsg = resp.Error.Text
			}
			return resp, fmt.Errorf("iq error: %s", errMsg)
		}
		return resp, nil
	case <-timer.C:
		c.pendingIQMu.Lock()
		delete(c.pendingIQ, id)
		c.pendingIQMu.Unlock()
		return nil, errors.New("iq timeout")
	case <-c.ctx.Done():
		return nil, c.ctx.Err()
	}
}

func (c *XMPPCore) sendRawStanza(stanza string) error {
	stanzaBytes := []byte(stanza)
	c.writeMu.Lock()
	defer c.writeMu.Unlock()
	if c.conn == nil {
		return errors.New("not connected")
	}

	_, err := c.conn.Write(stanzaBytes)

	if c.smEnabled {
		c.smOutH.Add(1)
		buf := bytes.NewBuffer(make([]byte, 0, len(stanzaBytes)))
		buf.Write(stanzaBytes)
		c.smOutMu.Lock()
		c.smOutQueue = append(c.smOutQueue, buf)
		c.smOutMu.Unlock()
	}

	return err
}

func (c *XMPPCore) pingLoop() {
	defer c.wg.Done()
	ticker := time.NewTicker(xmppPingInterval)
	defer ticker.Stop()
	for {
		select {
		case <-c.ctx.Done():
			return
		case <-ticker.C:
			c.SendPing("")
		}
	}
}

func (c *XMPPCore) GetDialogs(opts PaginationOpts) ([]Dialog, error) {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return nil, ErrAuth
	}
	c.mu.RUnlock()

	c.rosterMu.RLock()
	defer c.rosterMu.RUnlock()

	dialogs := []Dialog{}

	for _, item := range c.roster {
		if item.Subscription == "remove" {
			continue
		}
		d := Dialog{
			ID:       item.JID,
			Type:     ChatTypeDM,
			Title:    item.Name,
			Platform: xmppPlatform,
		}
		if d.Title == "" {
			d.Title = item.JID
		}
		c.messagesMu.RLock()
		if msgs, ok := c.messages[item.JID]; ok && len(msgs) > 0 {
			d.LastMessage = msgs[len(msgs)-1]
		}
		c.messagesMu.RUnlock()
		dialogs = append(dialogs, d)
	}

	c.roomsMu.RLock()
	for _, room := range c.rooms {
		if !room.Joined {
			continue
		}
		d := Dialog{
			ID:          room.JID,
			Type:        ChatTypeGroup,
			Title:       room.Name,
			MemberCount: len(room.Occupants),
			Platform:    xmppPlatform,
		}
		if d.Title == "" {
			d.Title = room.JID
		}
		c.messagesMu.RLock()
		if msgs, ok := c.messages[room.JID]; ok && len(msgs) > 0 {
			d.LastMessage = msgs[len(msgs)-1]
		}
		c.messagesMu.RUnlock()
		dialogs = append(dialogs, d)
	}
	c.roomsMu.RUnlock()

	offset := 0
	if opts.Offset != "" {
		offset, _ = strconv.Atoi(opts.Offset)
	}
	if offset > 0 {
		if offset >= len(dialogs) {
			return []Dialog{}, nil
		}
		dialogs = dialogs[offset:]
	}

	if opts.Limit > 0 && len(dialogs) > opts.Limit {
		dialogs = dialogs[:opts.Limit]
	}

	return dialogs, nil
}

func (c *XMPPCore) CreateGroup(name string, members []string) (*Dialog, error) {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return nil, ErrAuth
	}
	mucSvc := c.mucService
	c.mu.RUnlock()

	if mucSvc == "" {
		return nil, fmt.Errorf("%w: MUC service not discovered", ErrNotSupported)
	}

	roomJID := strings.ReplaceAll(strings.ToLower(name), " ", "-") + "@" + mucSvc

	if err := c.JoinMUC(roomJID, ""); err != nil {
		return nil, err
	}

	c.ConfigureMUC(roomJID, map[string]string{
		"muc#roomconfig_persistentroom": "1",
		"muc#roomconfig_roomname":       name,
	})

	for _, m := range members {
		c.SendMUCInvitation(roomJID, m, "")
	}

	d := &Dialog{
		ID:       roomJID,
		Type:     ChatTypeGroup,
		Title:    name,
		Platform: xmppPlatform,
	}
	return d, nil
}

func (c *XMPPCore) CreateChannel(name string, description string) (*Dialog, error) {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return nil, ErrAuth
	}
	c.mu.RUnlock()

	d, err := c.CreateGroup(name, nil)
	if err != nil {
		return nil, err
	}
	if description != "" {
		c.EditChatDescription(d.ID, description)
	}
	d.Type = ChatTypeChannel
	return d, nil
}

func (c *XMPPCore) CreateTopic(chatID string, name string) (*Dialog, error) {
	return nil, fmt.Errorf("%w: xmpp does not support forum topics", ErrNotSupported)
}

func (c *XMPPCore) GetFolders() ([]Folder, error) {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return nil, ErrAuth
	}
	c.mu.RUnlock()

	c.bookmarksMu.RLock()
	empty := len(c.bookmarks) == 0
	c.bookmarksMu.RUnlock()

	if empty {
		c.loadBookmarks()
	}

	c.bookmarksMu.RLock()
	defer c.bookmarksMu.RUnlock()

	var chatIDs []string
	for _, bm := range c.bookmarks {
		chatIDs = append(chatIDs, bm.JID)
	}

	return []Folder{{
		ID:      "bookmarks",
		Name:    "Bookmarks",
		ChatIDs: chatIDs,
	}}, nil
}

func (c *XMPPCore) CreateFolder(name string, chatIDs []string) (*Folder, error) {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return nil, ErrAuth
	}
	c.mu.RUnlock()

	for _, id := range chatIDs {
		c.SetBookmark(id, name, "", true)
	}
	return &Folder{
		ID:      "bookmarks",
		Name:    name,
		ChatIDs: chatIDs,
	}, nil
}

func (c *XMPPCore) SendMessage(chatID string, msg OutgoingMessage) (*Message, error) {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return nil, ErrAuth
	}
	c.mu.RUnlock()

	msgType := "chat"
	if c.isRoom(chatID) {
		msgType = "groupchat"
	}

	id := c.nextMsgID()

	escapedText := xmlEscape(msg.Text)
	escapedChatID := xmlEscape(chatID)

	var b strings.Builder
	b.Grow(128 + len(escapedText) + len(escapedChatID))
	b.WriteString("<message type='")
	b.WriteString(msgType)
	b.WriteString("' to='")
	b.WriteString(escapedChatID)
	b.WriteString("' id='")
	b.WriteString(id)
	b.WriteString("'><body>")
	b.WriteString(escapedText)
	b.WriteString("</body><request xmlns='")
	b.WriteString(nsReceipts)
	b.WriteString("'/><active xmlns='")
	b.WriteString(nsChatState)
	b.WriteString("'/>")
	if msg.ReplyToID != "" {
		b.WriteString("<reply xmlns='")
		b.WriteString(nsReply)
		b.WriteString("' id='")
		b.WriteString(xmlEscape(msg.ReplyToID))
		b.WriteString("'/>")
	}
	b.WriteString("<store xmlns='")
	b.WriteString(nsHints)
	b.WriteString("'/></message>")
	stanza := b.String()

	if err := c.sendRawStanza(stanza); err != nil {
		return nil, err
	}

	m := &Message{
		ID:         id,
		ChatID:     chatID,
		SenderID:   c.bareJID,
		SenderName: c.bareJID,
		Text:       msg.Text,
		Timestamp:  time.Now(),
		Status:     MessageStatusSent,
		ReplyToID:  msg.ReplyToID,
		IsOutgoing: true,
		Platform:   xmppPlatform,
	}

	if msgType != "groupchat" {
		c.bufferMessage(chatID, m)
	}

	return m, nil
}

func (c *XMPPCore) GetMessages(chatID string, opts PaginationOpts) ([]Message, error) {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return nil, ErrAuth
	}
	c.mu.RUnlock()

	if opts.Offset != "" || opts.Limit > 0 {
		msgs, err := c.QueryMAM(chatID, opts.Limit, opts.Offset)
		if err == nil && len(msgs) > 0 {
			return msgs, nil
		}
	}

	c.messagesMu.RLock()
	defer c.messagesMu.RUnlock()

	msgs, ok := c.messages[chatID]
	if !ok {
		return []Message{}, nil
	}

	result := make([]Message, len(msgs))
	for i, m := range msgs {
		result[i] = *m
	}
	return result, nil
}

func (c *XMPPCore) EditMessage(chatID string, msgID string, text string) (*Message, error) {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return nil, ErrAuth
	}
	c.mu.RUnlock()

	msgType := "chat"
	if c.isRoom(chatID) {
		msgType = "groupchat"
	}
	id := c.nextMsgID()
	err := c.sendRawStanza(fmt.Sprintf(
		`<message type='%s' to='%s' id='%s'><body>%s</body><replace xmlns='%s' id='%s'/></message>`,
		msgType, xmlEscape(chatID), id, xmlEscape(text), nsCorrect, xmlEscape(msgID),
	))
	if err != nil {
		return nil, err
	}

	c.messagesMu.Lock()
	if msgs, ok := c.messages[chatID]; ok {
		for _, m := range msgs {
			if m.ID == msgID {
				m.Text = text
				now := time.Now()
				m.EditedAt = &now
				c.messagesMu.Unlock()
				return m, nil
			}
		}
	}
	c.messagesMu.Unlock()

	return &Message{
		ID:         id,
		ChatID:     chatID,
		SenderID:   c.bareJID,
		Text:       text,
		Timestamp:  time.Now(),
		Status:     MessageStatusSent,
		IsOutgoing: true,
		Platform:   xmppPlatform,
	}, nil
}

func (c *XMPPCore) DeleteMessage(chatID string, msgID string) error {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return ErrAuth
	}
	c.mu.RUnlock()

	c.messagesMu.Lock()
	if msgs, ok := c.messages[chatID]; ok {
		for i, m := range msgs {
			if m.ID == msgID {
				c.messages[chatID] = append(msgs[:i], msgs[i+1:]...)
				break
			}
		}
	}
	c.messagesMu.Unlock()
	return nil
}

func (c *XMPPCore) ReplyToMessage(chatID string, replyToMsgID string, msg OutgoingMessage) (*Message, error) {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return nil, ErrAuth
	}
	c.mu.RUnlock()
	msg.ReplyToID = replyToMsgID
	return c.SendMessage(chatID, msg)
}

func (c *XMPPCore) ForwardMessage(fromChatID string, msgID string, toChatID string) (*Message, error) {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return nil, ErrAuth
	}
	c.mu.RUnlock()

	c.messagesMu.RLock()
	var original *Message
	if msgs, ok := c.messages[fromChatID]; ok {
		for _, m := range msgs {
			if m.ID == msgID {
				original = m
				break
			}
		}
	}
	c.messagesMu.RUnlock()

	if original == nil {
		return nil, ErrNotFound
	}

	fwdMsg := OutgoingMessage{
		Text: fmt.Sprintf("[Forwarded from %s]\n%s", original.SenderName, original.Text),
	}
	return c.SendMessage(toChatID, fwdMsg)
}

func (c *XMPPCore) ReactToMessage(chatID string, msgID string, emoji string) error {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return ErrAuth
	}
	c.mu.RUnlock()
	return c.SendReaction(chatID, msgID, []string{emoji})
}

func (c *XMPPCore) PinMessage(chatID string, msgID string) error {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return ErrAuth
	}
	c.mu.RUnlock()

	c.pinnedMu.Lock()
	defer c.pinnedMu.Unlock()
	if _, ok := c.pinned[chatID]; !ok {
		c.pinned[chatID] = make(map[string]bool)
	}
	c.pinned[chatID][msgID] = true
	c.saveSession()
	return nil
}

func (c *XMPPCore) UnpinMessage(chatID string, msgID string) error {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return ErrAuth
	}
	c.mu.RUnlock()

	c.pinnedMu.Lock()
	defer c.pinnedMu.Unlock()
	if pins, ok := c.pinned[chatID]; ok {
		delete(pins, msgID)
	}
	c.saveSession()
	return nil
}

func (c *XMPPCore) MarkAsRead(chatID string, upToMsgID string) error {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return ErrAuth
	}
	c.mu.RUnlock()

	c.readStateMu.Lock()
	if _, ok := c.readState[chatID]; !ok {
		c.readState[chatID] = &ReadState{PeerLastRead: make(map[string]string)}
	}
	c.readState[chatID].MyLastRead = upToMsgID
	c.readStateMu.Unlock()

	c.SendDisplayedMarker(chatID, upToMsgID)
	return nil
}

func (c *XMPPCore) GetReadState(chatID string) (*ReadState, error) {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return nil, ErrAuth
	}
	c.mu.RUnlock()

	c.readStateMu.RLock()
	defer c.readStateMu.RUnlock()
	if rs, ok := c.readState[chatID]; ok {
		return rs, nil
	}
	return &ReadState{PeerLastRead: make(map[string]string)}, nil
}

func (c *XMPPCore) UploadFile(chatID string, file FileUpload, progress func(sent, total int64)) (*Message, error) {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return nil, ErrAuth
	}
	uploadSvc := c.uploadService
	c.mu.RUnlock()

	if uploadSvc == "" {
		return nil, fmt.Errorf("%w: HTTP upload service not discovered", ErrNotSupported)
	}

	putURL, getURL, err := c.RequestHTTPUploadSlot(file.Name, file.Size, file.MimeType)
	if err != nil {
		return nil, err
	}

	data, err := io.ReadAll(file.Reader)
	if err != nil {
		return nil, fmt.Errorf("read file: %w", err)
	}

	if err := c.UploadFileHTTP(putURL, data, file.MimeType, progress); err != nil {
		return nil, err
	}

	return c.SendFileURL(chatID, getURL, file.Name)
}

func (c *XMPPCore) DownloadFile(fileRef FileRef, dest string, progress func(recv, total int64)) error {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return ErrAuth
	}
	c.mu.RUnlock()

	if fileRef.URL == "" {
		return fmt.Errorf("%w: no URL in file ref", ErrInvalidInput)
	}

	return c.DownloadFileHTTP(fileRef.URL, dest, progress)
}

func (c *XMPPCore) SendImageBase64(chatID string, b64 string, caption string) (*Message, error) {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return nil, ErrAuth
	}
	uploadSvc := c.uploadService
	c.mu.RUnlock()

	data, err := base64.StdEncoding.DecodeString(b64)
	if err != nil {
		return nil, fmt.Errorf("decode base64: %w", err)
	}

	if uploadSvc == "" {
		msg := OutgoingMessage{Text: caption}
		return c.SendMessage(chatID, msg)
	}

	putURL, getURL, err := c.RequestHTTPUploadSlot("image.png", int64(len(data)), "image/png")
	if err != nil {
		msg := OutgoingMessage{Text: caption}
		return c.SendMessage(chatID, msg)
	}

	c.UploadFileHTTP(putURL, data, "image/png", nil)
	return c.SendFileURL(chatID, getURL, caption)
}

func (c *XMPPCore) StartCall(chatID string, video bool) (*CallSession, error) {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return nil, ErrAuth
	}
	c.mu.RUnlock()
	return c.InitiateJingle(chatID, video)
}

func (c *XMPPCore) JoinGroupCall(chatID string) (*CallSession, error) {
	return nil, fmt.Errorf("%w: xmpp group calls (Muji/XEP-0272) not widely supported", ErrNotSupported)
}

func (c *XMPPCore) EndCall(callID string) error {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return ErrAuth
	}
	c.mu.RUnlock()
	return c.TerminateJingle(callID, "success")
}

func (c *XMPPCore) SetCallMuted(callID string, muted bool) error {
	return fmt.Errorf("%w: xmpp does not support call muting", ErrNotSupported)
}

func (c *XMPPCore) ToggleCamera(_ string, _ bool) error {
	return fmt.Errorf("%w: xmpp does not support camera toggle", ErrNotSupported)
}

func (c *XMPPCore) GetProfile(userID string) (*User, error) {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return nil, ErrAuth
	}
	c.mu.RUnlock()

	if userID == "" {
		userID = c.bareJID
	}

	vcard, err := c.GetVCard(userID)
	if err != nil {
		c.rosterMu.RLock()
		item, ok := c.roster[userID]
		c.rosterMu.RUnlock()
		if ok {
			return &User{
				ID:          item.JID,
				DisplayName: item.Name,
				Platform:    xmppPlatform,
			}, nil
		}
		return &User{
			ID:          userID,
			DisplayName: userID,
			Platform:    xmppPlatform,
		}, nil
	}

	u := &User{
		ID:          userID,
		DisplayName: vcard["FN"],
		Username:    vcard["NICKNAME"],
		Platform:    xmppPlatform,
	}
	if u.DisplayName == "" {
		u.DisplayName = vcard["NICKNAME"]
	}
	if u.DisplayName == "" {
		c.rosterMu.RLock()
		if item, ok := c.roster[userID]; ok {
			u.DisplayName = item.Name
		}
		c.rosterMu.RUnlock()
	}
	if u.DisplayName == "" {
		u.DisplayName = userID
	}

	return u, nil
}

func (c *XMPPCore) OnUpdate(handler func(Update)) {
	c.updateMu.Lock()
	c.updateHandlers = append(c.updateHandlers, handler)
	c.updateMu.Unlock()
}

func (c *XMPPCore) Close() error {
	c.saveSession()
	c.cancel()
	c.mu.Lock()
	c.authed = false
	var connErr error
	if c.conn != nil {
		c.writeMu.Lock()
		c.conn.Write([]byte("</stream:stream>"))
		c.writeMu.Unlock()
		connErr = c.conn.Close()
	}
	c.mu.Unlock()
	c.wg.Wait()
	return connErr
}

func (c *XMPPCore) GetChatInfo(chatID string) (*Dialog, error) {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return nil, ErrAuth
	}
	c.mu.RUnlock()

	if c.isRoom(chatID) {
		info, err := c.GetMUCInfo(chatID)
		if err != nil {
			c.roomsMu.RLock()
			room, ok := c.rooms[chatID]
			c.roomsMu.RUnlock()
			if ok {
				return &Dialog{
					ID:          room.JID,
					Type:        ChatTypeGroup,
					Title:       room.Name,
					MemberCount: len(room.Occupants),
					Platform:    xmppPlatform,
				}, nil
			}
		}
		return info, err
	}

	c.rosterMu.RLock()
	item, ok := c.roster[chatID]
	c.rosterMu.RUnlock()

	d := &Dialog{
		ID:       chatID,
		Type:     ChatTypeDM,
		Title:    chatID,
		Platform: xmppPlatform,
	}
	if ok && item.Name != "" {
		d.Title = item.Name
	}
	return d, nil
}

func (c *XMPPCore) EditChatTitle(chatID string, title string) error {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return ErrAuth
	}
	c.mu.RUnlock()

	if c.isRoom(chatID) {
		return c.SetMUCSubject(chatID, title)
	}
	return fmt.Errorf("%w: xmpp does not support editing DM titles", ErrNotSupported)
}

func (c *XMPPCore) EditChatDescription(chatID string, description string) error {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return ErrAuth
	}
	c.mu.RUnlock()

	if c.isRoom(chatID) {
		return c.ConfigureMUC(chatID, map[string]string{
			"muc#roomconfig_roomdesc": description,
		})
	}
	return fmt.Errorf("%w: xmpp does not support editing DM descriptions", ErrNotSupported)
}

func (c *XMPPCore) LeaveChat(chatID string) error {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return ErrAuth
	}
	c.mu.RUnlock()

	if c.isRoom(chatID) {
		return c.LeaveMUC(chatID)
	}
	return c.RemoveRosterItem(chatID)
}

func (c *XMPPCore) GetInviteLink(chatID string) (string, error) {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return "", ErrAuth
	}
	c.mu.RUnlock()

	return "xmpp:" + chatID + "?join", nil
}

func (c *XMPPCore) AddMembers(chatID string, userIDs []string) error {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return ErrAuth
	}
	c.mu.RUnlock()

	if !c.isRoom(chatID) {
		return fmt.Errorf("%w: xmpp only supports adding members to MUC rooms", ErrNotSupported)
	}
	for _, uid := range userIDs {
		c.SendMUCInvitation(chatID, uid, "")
	}
	return nil
}

func (c *XMPPCore) RemoveMember(chatID string, userID string) error {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return ErrAuth
	}
	c.mu.RUnlock()

	if !c.isRoom(chatID) {
		return fmt.Errorf("%w: xmpp only supports removing members from MUC rooms", ErrNotSupported)
	}
	return c.KickFromMUC(chatID, userID, "")
}

func (c *XMPPCore) BanMember(chatID string, userID string) error {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return ErrAuth
	}
	c.mu.RUnlock()

	if !c.isRoom(chatID) {
		return fmt.Errorf("%w: xmpp only supports banning in MUC rooms", ErrNotSupported)
	}
	return c.BanFromMUC(chatID, userID, "")
}

func (c *XMPPCore) UnbanMember(chatID string, userID string) error {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return ErrAuth
	}
	c.mu.RUnlock()

	if !c.isRoom(chatID) {
		return fmt.Errorf("%w: xmpp only supports unbanning in MUC rooms", ErrNotSupported)
	}
	return c.UnbanFromMUC(chatID, userID)
}

func (c *XMPPCore) GetMembers(chatID string, opts PaginationOpts) ([]User, error) {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return nil, ErrAuth
	}
	c.mu.RUnlock()

	if c.isRoom(chatID) {
		return c.GetMUCOccupants(chatID)
	}
	return []User{
		{ID: c.bareJID, DisplayName: c.bareJID, Platform: xmppPlatform},
		{ID: chatID, DisplayName: chatID, Platform: xmppPlatform},
	}, nil
}

func (c *XMPPCore) SetAdmin(chatID string, userID string, admin bool) error {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return ErrAuth
	}
	c.mu.RUnlock()

	if !c.isRoom(chatID) {
		return fmt.Errorf("%w: xmpp only supports admin management in MUC rooms", ErrNotSupported)
	}
	aff := "admin"
	if !admin {
		aff = "member"
	}
	return c.SetMUCAffiliation(chatID, userID, aff)
}

func (c *XMPPCore) GetContacts() ([]User, error) {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return nil, ErrAuth
	}
	c.mu.RUnlock()

	c.rosterMu.RLock()
	defer c.rosterMu.RUnlock()

	users := []User{}
	for _, item := range c.roster {
		if item.Subscription == "remove" {
			continue
		}
		name := item.Name
		if name == "" {
			name = item.JID
		}
		users = append(users, User{
			ID:          item.JID,
			DisplayName: name,
			Platform:    xmppPlatform,
		})
	}
	return users, nil
}

func (c *XMPPCore) AddContact(phone string, firstName string, lastName string) error {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return ErrAuth
	}
	c.mu.RUnlock()

	jid := phone
	name := firstName
	if lastName != "" {
		name += " " + lastName
	}
	return c.AddRosterItem(jid, name, nil)
}

func (c *XMPPCore) DeleteContact(userID string) error {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return ErrAuth
	}
	c.mu.RUnlock()
	return c.RemoveRosterItem(userID)
}

func (c *XMPPCore) BlockUser(userID string) error {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return ErrAuth
	}
	c.mu.RUnlock()
	return c.BlockJID(userID)
}

func (c *XMPPCore) UnblockUser(userID string) error {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return ErrAuth
	}
	c.mu.RUnlock()
	return c.UnblockJID(userID)
}

func (c *XMPPCore) GetBlockedUsers() ([]User, error) {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return nil, ErrAuth
	}
	c.mu.RUnlock()

	jids, err := c.GetBlocklist()
	if err != nil {
		return nil, err
	}
	users := []User{}
	for _, jid := range jids {
		users = append(users, User{
			ID:          jid,
			DisplayName: jid,
			Platform:    xmppPlatform,
		})
	}
	return users, nil
}

func (c *XMPPCore) SearchMessages(chatID string, query string, opts PaginationOpts) ([]Message, error) {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return nil, ErrAuth
	}
	c.mu.RUnlock()

	c.messagesMu.RLock()
	defer c.messagesMu.RUnlock()

	results := []Message{}
	q := strings.ToLower(query)

	if chatID != "" {
		if msgs, ok := c.messages[chatID]; ok {
			for _, m := range msgs {
				if strings.Contains(strings.ToLower(m.Text), q) {
					results = append(results, *m)
				}
			}
		}
	} else {
		for _, msgs := range c.messages {
			for _, m := range msgs {
				if strings.Contains(strings.ToLower(m.Text), q) {
					results = append(results, *m)
				}
			}
		}
	}

	return results, nil
}

func (c *XMPPCore) SearchGlobal(query string, opts PaginationOpts) ([]Dialog, error) {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return nil, ErrAuth
	}
	c.mu.RUnlock()

	q := strings.ToLower(query)
	results := []Dialog{}

	c.rosterMu.RLock()
	for _, item := range c.roster {
		name := item.Name
		if name == "" {
			name = item.JID
		}
		if strings.Contains(strings.ToLower(name), q) || strings.Contains(strings.ToLower(item.JID), q) {
			results = append(results, Dialog{
				ID:       item.JID,
				Type:     ChatTypeDM,
				Title:    name,
				Platform: xmppPlatform,
			})
		}
	}
	c.rosterMu.RUnlock()

	c.roomsMu.RLock()
	for _, room := range c.rooms {
		name := room.Name
		if name == "" {
			name = room.JID
		}
		if strings.Contains(strings.ToLower(name), q) || strings.Contains(strings.ToLower(room.JID), q) {
			results = append(results, Dialog{
				ID:       room.JID,
				Type:     ChatTypeGroup,
				Title:    name,
				Platform: xmppPlatform,
			})
		}
	}
	c.roomsMu.RUnlock()

	return results, nil
}

func (c *XMPPCore) SendTyping(chatID string) error {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return ErrAuth
	}
	c.mu.RUnlock()
	return c.SendChatStateComposing(chatID)
}

func (c *XMPPCore) CreatePoll(chatID string, question string, options []string) (*Message, error) {
	return nil, fmt.Errorf("%w: xmpp does not support polls", ErrNotSupported)
}

func (c *XMPPCore) VotePoll(chatID string, msgID string, optionIndex int) error {
	return fmt.Errorf("%w: xmpp does not support polls", ErrNotSupported)
}

func (c *XMPPCore) SendSticker(chatID string, stickerID string) (*Message, error) {
	return nil, fmt.Errorf("%w: xmpp does not support stickers", ErrNotSupported)
}

func (c *XMPPCore) GetSessions() ([]Session, error) {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return nil, ErrAuth
	}
	c.mu.RUnlock()

	return []Session{{
		ID:         c.jid,
		Device:     "uniclient",
		Platform:   xmppPlatform,
		LastActive: time.Now(),
		IsCurrent:  true,
	}}, nil
}

func (c *XMPPCore) TerminateSession(sessionID string) error {
	return fmt.Errorf("%w: xmpp does not support session termination", ErrNotSupported)
}

func (c *XMPPCore) SendPresenceAvailable(show, status string) error {
	var b strings.Builder
	b.Grow(128)
	b.WriteString("<presence>")
	if show != "" {
		b.WriteString("<show>")
		b.WriteString(xmlEscape(show))
		b.WriteString("</show>")
	}
	if status != "" {
		b.WriteString("<status>")
		b.WriteString(xmlEscape(status))
		b.WriteString("</status>")
	}
	b.WriteString(c.buildCapsElement())
	b.WriteString("</presence>")
	return c.sendRawStanza(b.String())
}

func (c *XMPPCore) SendPresenceUnavailable(status string) error {
	if status == "" {
		return c.sendRawStanza("<presence type='unavailable'/>")
	}
	return c.sendRawStanza("<presence type='unavailable'><status>" + xmlEscape(status) + "</status></presence>")
}

func (c *XMPPCore) SetPresencePriority(priority int) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<presence><priority>%d</priority>%s</presence>`, priority, c.buildCapsElement(),
	))
}

func (c *XMPPCore) SendPresenceSubscribe(jid string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<presence type='subscribe' to='%s'/>`, xmlEscape(jid),
	))
}

func (c *XMPPCore) SendPresenceSubscribed(jid string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<presence type='subscribed' to='%s'/>`, xmlEscape(jid),
	))
}

func (c *XMPPCore) SendPresenceUnsubscribe(jid string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<presence type='unsubscribe' to='%s'/>`, xmlEscape(jid),
	))
}

func (c *XMPPCore) SendPresenceUnsubscribed(jid string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<presence type='unsubscribed' to='%s'/>`, xmlEscape(jid),
	))
}

func (c *XMPPCore) SendDirectedPresence(jid, show, status string) error {
	var inner string
	if show != "" {
		inner += fmt.Sprintf(`<show>%s</show>`, xmlEscape(show))
	}
	if status != "" {
		inner += fmt.Sprintf(`<status>%s</status>`, xmlEscape(status))
	}
	return c.sendRawStanza(fmt.Sprintf(
		`<presence to='%s'>%s</presence>`, xmlEscape(jid), inner,
	))
}

func (c *XMPPCore) ProbePresence(jid string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<presence type='probe' to='%s'/>`, xmlEscape(jid),
	))
}

func (c *XMPPCore) requestRoster() {
	var verAttr string
	if c.rosterVer != "" {
		verAttr = fmt.Sprintf(` ver='%s'`, xmlEscape(c.rosterVer))
	}
	inner := fmt.Sprintf(`<query xmlns='%s'%s/>`, nsRoster, verAttr)
	resp, err := c.sendIQSync("get", "", inner)
	if err != nil {
		return
	}

	items, ver, err := XmppParseRoster(resp.Inner)
	if err != nil {
		log.Printf("xmpp: roster fetch parse failed: %v", err)
		return
	}

	c.rosterMu.Lock()
	for _, item := range items {
		itemCopy := item
		c.roster[item.JID] = &itemCopy
	}
	if ver != "" {
		c.rosterVer = ver
	}
	c.rosterMu.Unlock()
}

func (c *XMPPCore) GetRoster() ([]XmppRosterItem, error) {
	c.rosterMu.RLock()
	defer c.rosterMu.RUnlock()

	var items []XmppRosterItem
	for _, item := range c.roster {
		items = append(items, *item)
	}
	return items, nil
}

func (c *XMPPCore) AddRosterItem(jid, name string, groups []string) error {
	var inner strings.Builder
	inner.WriteString(fmt.Sprintf(`<query xmlns='%s'><item jid='%s'`, nsRoster, xmlEscape(jid)))
	if name != "" {
		inner.WriteString(fmt.Sprintf(` name='%s'`, xmlEscape(name)))
	}
	inner.WriteString(`>`)
	for _, g := range groups {
		inner.WriteString(fmt.Sprintf(`<group>%s</group>`, xmlEscape(g)))
	}
	inner.WriteString(`</item></query>`)

	_, err := c.sendIQSync("set", "", inner.String())
	if err != nil {
		return err
	}

	c.SendPresenceSubscribe(jid)
	return nil
}

func (c *XMPPCore) RemoveRosterItem(jid string) error {
	inner := fmt.Sprintf(`<query xmlns='%s'><item jid='%s' subscription='remove'/></query>`, nsRoster, xmlEscape(jid))
	_, err := c.sendIQSync("set", "", inner)
	return err
}

func (c *XMPPCore) SetRosterItemName(jid, name string) error {
	return c.AddRosterItem(jid, name, nil)
}

func (c *XMPPCore) SetRosterItemGroups(jid string, groups []string) error {
	c.rosterMu.RLock()
	item, ok := c.roster[jid]
	name := ""
	if ok {
		name = item.Name
	}
	c.rosterMu.RUnlock()
	return c.AddRosterItem(jid, name, groups)
}

func (c *XMPPCore) sendChatState(chatID, state string) error {
	msgType := "chat"
	if c.isRoom(chatID) {
		msgType = "groupchat"
	}
	var b strings.Builder
	b.Grow(80 + len(chatID) + len(state))
	b.WriteString("<message type='")
	b.WriteString(msgType)
	b.WriteString("' to='")
	b.WriteString(xmlEscape(chatID))
	b.WriteString("'><")
	b.WriteString(state)
	b.WriteString(" xmlns='")
	b.WriteString(nsChatState)
	b.WriteString("'/></message>")
	return c.sendRawStanza(b.String())
}

func (c *XMPPCore) SendChatStateActive(chatID string) error {
	return c.sendChatState(chatID, "active")
}

func (c *XMPPCore) SendChatStateComposing(chatID string) error {
	return c.sendChatState(chatID, "composing")
}

func (c *XMPPCore) SendChatStatePaused(chatID string) error {
	return c.sendChatState(chatID, "paused")
}

func (c *XMPPCore) SendChatStateInactive(chatID string) error {
	return c.sendChatState(chatID, "inactive")
}

func (c *XMPPCore) SendChatStateGone(chatID string) error {
	return c.sendChatState(chatID, "gone")
}

func (c *XMPPCore) SendGroupchatMessage(to, body string) error {
	id := c.nextMsgID()
	return c.sendRawStanza(fmt.Sprintf(
		`<message type='groupchat' to='%s' id='%s'><body>%s</body></message>`,
		xmlEscape(to), id, xmlEscape(body),
	))
}

func (c *XMPPCore) SendHeadlineMessage(to, body, subject string) error {
	id := c.nextMsgID()
	var subjectXML string
	if subject != "" {
		subjectXML = fmt.Sprintf(`<subject>%s</subject>`, xmlEscape(subject))
	}
	return c.sendRawStanza(fmt.Sprintf(
		`<message type='headline' to='%s' id='%s'>%s<body>%s</body></message>`,
		xmlEscape(to), id, subjectXML, xmlEscape(body),
	))
}

func (c *XMPPCore) SendNormalMessage(to, body string) error {
	id := c.nextMsgID()
	return c.sendRawStanza(fmt.Sprintf(
		`<message type='normal' to='%s' id='%s'><body>%s</body></message>`,
		xmlEscape(to), id, xmlEscape(body),
	))
}

func (c *XMPPCore) RequestReceipt(to, msgID string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<message to='%s' id='%s'><request xmlns='%s'/></message>`,
		xmlEscape(to), xmlEscape(msgID), nsReceipts,
	))
}

func (c *XMPPCore) SendReceipt(to, msgID string) error {
	id := c.nextMsgID()
	return c.sendRawStanza("<message to='" + xmlEscape(to) + "' id='" + id + "'><received xmlns='" + nsReceipts + "' id='" + xmlEscape(msgID) + "'/></message>")
}

func (c *XMPPCore) EnableCarbons() error {
	inner := fmt.Sprintf(`<enable xmlns='%s'/>`, nsCarbons)
	_, err := c.sendIQSync("set", "", inner)
	if err == nil {
		c.mu.Lock()
		c.carbonsEnabled = true
		c.mu.Unlock()
	}
	return err
}

func (c *XMPPCore) DisableCarbons() error {
	inner := fmt.Sprintf(`<disable xmlns='%s'/>`, nsCarbons)
	_, err := c.sendIQSync("set", "", inner)
	if err == nil {
		c.mu.Lock()
		c.carbonsEnabled = false
		c.mu.Unlock()
	}
	return err
}

func (c *XMPPCore) SendDisplayedMarker(to, msgID string) error {
	id := c.nextMsgID()
	return c.sendRawStanza("<message to='" + xmlEscape(to) + "' id='" + id + "'><displayed xmlns='" + nsMarkers + "' id='" + xmlEscape(msgID) + "'/></message>")
}

func (c *XMPPCore) SendReceivedMarker(to, msgID string) error {
	id := c.nextMsgID()
	return c.sendRawStanza(fmt.Sprintf(
		`<message to='%s' id='%s'><received xmlns='%s' id='%s'/></message>`,
		xmlEscape(to), id, nsMarkers, xmlEscape(msgID),
	))
}

func (c *XMPPCore) SendOOBURL(chatID, url, desc string) error {
	id := c.nextMsgID()
	msgType := "chat"
	if c.isRoom(chatID) {
		msgType = "groupchat"
	}
	var bodyXML string
	if desc != "" {
		bodyXML = fmt.Sprintf(`<body>%s</body>`, xmlEscape(desc))
	}
	return c.sendRawStanza(fmt.Sprintf(
		`<message type='%s' to='%s' id='%s'>%s<x xmlns='%s'><url>%s</url></x></message>`,
		msgType, xmlEscape(chatID), id, bodyXML, nsOOB, xmlEscape(url),
	))
}

func (c *XMPPCore) SetMessageHint(chatID, msgID, hint string) error {
	return fmt.Errorf("%w: xmpp message hints can only be set at send time", ErrNotSupported)
}

func (c *XMPPCore) SendReaction(chatID, msgID string, emojis []string) error {
	id := c.nextMsgID()
	msgType := "chat"
	if c.isRoom(chatID) {
		msgType = "groupchat"
	}

	var reactions strings.Builder
	for _, e := range emojis {
		reactions.WriteString(fmt.Sprintf(`<reaction>%s</reaction>`, xmlEscape(e)))
	}

	return c.sendRawStanza(fmt.Sprintf(
		`<message type='%s' to='%s' id='%s'><reactions xmlns='%s' id='%s'>%s</reactions><store xmlns='%s'/></message>`,
		msgType, xmlEscape(chatID), id, nsReactions, xmlEscape(msgID), reactions.String(), nsHints,
	))
}

func (c *XMPPCore) JoinMUC(roomJID, nick string) error {
	if nick == "" {
		c.mu.RLock()
		nick = c.bareJID
		if at := strings.Index(nick, "@"); at > 0 {
			nick = nick[:at]
		}
		c.mu.RUnlock()
	}

	fullJID := roomJID + "/" + nick

	err := c.sendRawStanza(fmt.Sprintf(
		`<presence to='%s'><x xmlns='%s'><history maxstanzas='50'/></x>%s</presence>`,
		xmlEscape(fullJID), nsMUC, c.buildCapsElement(),
	))
	if err != nil {
		return err
	}

	c.roomsMu.Lock()
	if _, ok := c.rooms[roomJID]; !ok {
		c.rooms[roomJID] = &xmppRoom{
			JID:       roomJID,
			Nick:      nick,
			Occupants: make(map[string]*xmppOccupant),
		}
	} else {
		c.rooms[roomJID].Nick = nick
	}
	c.roomsMu.Unlock()

	return nil
}

func (c *XMPPCore) LeaveMUC(roomJID string) error {
	c.roomsMu.RLock()
	room, ok := c.rooms[roomJID]
	nick := ""
	if ok {
		nick = room.Nick
	}
	c.roomsMu.RUnlock()

	if nick == "" {
		nick = c.bareJID
		if at := strings.Index(nick, "@"); at > 0 {
			nick = nick[:at]
		}
	}

	err := c.sendRawStanza(fmt.Sprintf(
		`<presence to='%s/%s' type='unavailable'/>`, xmlEscape(roomJID), xmlEscape(nick),
	))

	c.roomsMu.Lock()
	if room, ok := c.rooms[roomJID]; ok {
		room.Joined = false
	}
	c.roomsMu.Unlock()

	return err
}

func (c *XMPPCore) SetMUCNick(roomJID, nick string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<presence to='%s/%s'/>`, xmlEscape(roomJID), xmlEscape(nick),
	))
}

func (c *XMPPCore) GetMUCOccupants(roomJID string) ([]User, error) {
	c.roomsMu.RLock()
	room, ok := c.rooms[roomJID]
	c.roomsMu.RUnlock()
	if !ok {
		return nil, ErrNotFound
	}

	c.roomsMu.RLock()
	defer c.roomsMu.RUnlock()

	var users []User
	for nick, occ := range room.Occupants {
		u := User{
			ID:          nick,
			DisplayName: nick,
			Platform:    xmppPlatform,
		}
		if occ.RealJID != "" {
			u.ID = occ.RealJID
		}
		users = append(users, u)
	}

	sort.Slice(users, func(i, j int) bool {
		return users[i].DisplayName < users[j].DisplayName
	})

	return users, nil
}

func (c *XMPPCore) GetMUCInfo(roomJID string) (*Dialog, error) {
	resp, err := c.DiscoInfo(roomJID)
	if err != nil {
		return nil, err
	}

	d := &Dialog{
		ID:       roomJID,
		Type:     ChatTypeGroup,
		Title:    roomJID,
		Platform: xmppPlatform,
	}

	if name := ExtractXMLAttr(resp.Inner, "identity", "name"); name != "" {
		d.Title = name
	}

	c.roomsMu.RLock()
	if room, ok := c.rooms[roomJID]; ok {
		d.MemberCount = len(room.Occupants)
		if room.Name != "" {
			d.Title = room.Name
		}
	}
	c.roomsMu.RUnlock()

	return d, nil
}

func (c *XMPPCore) SetMUCSubject(roomJID, subject string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<message type='groupchat' to='%s'><subject>%s</subject></message>`,
		xmlEscape(roomJID), xmlEscape(subject),
	))
}

func (c *XMPPCore) SendMUCInvitation(roomJID, userJID, reason string) error {
	var reasonAttr string
	if reason != "" {
		reasonAttr = fmt.Sprintf(` reason='%s'`, xmlEscape(reason))
	}
	return c.sendRawStanza(fmt.Sprintf(
		`<message to='%s'><x xmlns='%s' jid='%s'%s/></message>`,
		xmlEscape(userJID), nsDirectMUC, xmlEscape(roomJID), reasonAttr,
	))
}

func (c *XMPPCore) SendMUCMediatedInvite(roomJID, userJID, reason string) error {
	var reasonXML string
	if reason != "" {
		reasonXML = fmt.Sprintf(`<reason>%s</reason>`, xmlEscape(reason))
	}
	return c.sendRawStanza(fmt.Sprintf(
		`<message to='%s'><x xmlns='%s'><invite to='%s'>%s</invite></x></message>`,
		xmlEscape(roomJID), nsMUCUser, xmlEscape(userJID), reasonXML,
	))
}

func (c *XMPPCore) DeclineMUCInvitation(roomJID, inviterJID, reason string) error {
	var reasonXML string
	if reason != "" {
		reasonXML = fmt.Sprintf(`<reason>%s</reason>`, xmlEscape(reason))
	}
	return c.sendRawStanza(fmt.Sprintf(
		`<message to='%s'><x xmlns='%s'><decline to='%s'>%s</decline></x></message>`,
		xmlEscape(roomJID), nsMUCUser, xmlEscape(inviterJID), reasonXML,
	))
}

func (c *XMPPCore) SetMUCRole(roomJID, nick, role string) error {
	inner := fmt.Sprintf(
		`<query xmlns='%s'><item nick='%s' role='%s'/></query>`,
		nsMUCAdmin, xmlEscape(nick), xmlEscape(role),
	)
	_, err := c.sendIQSync("set", roomJID, inner)
	return err
}

func (c *XMPPCore) SetMUCAffiliation(roomJID, userJID, affiliation string) error {
	inner := fmt.Sprintf(
		`<query xmlns='%s'><item jid='%s' affiliation='%s'/></query>`,
		nsMUCAdmin, xmlEscape(userJID), xmlEscape(affiliation),
	)
	_, err := c.sendIQSync("set", roomJID, inner)
	return err
}

func (c *XMPPCore) KickFromMUC(roomJID, nick, reason string) error {
	var reasonXML string
	if reason != "" {
		reasonXML = fmt.Sprintf(`<reason>%s</reason>`, xmlEscape(reason))
	}
	inner := fmt.Sprintf(
		`<query xmlns='%s'><item nick='%s' role='none'>%s</item></query>`,
		nsMUCAdmin, xmlEscape(nick), reasonXML,
	)
	_, err := c.sendIQSync("set", roomJID, inner)
	return err
}

func (c *XMPPCore) BanFromMUC(roomJID, userJID, reason string) error {
	var reasonXML string
	if reason != "" {
		reasonXML = fmt.Sprintf(`<reason>%s</reason>`, xmlEscape(reason))
	}
	inner := fmt.Sprintf(
		`<query xmlns='%s'><item jid='%s' affiliation='outcast'>%s</item></query>`,
		nsMUCAdmin, xmlEscape(userJID), reasonXML,
	)
	_, err := c.sendIQSync("set", roomJID, inner)
	return err
}

func (c *XMPPCore) UnbanFromMUC(roomJID, userJID string) error {
	return c.SetMUCAffiliation(roomJID, userJID, "none")
}

func (c *XMPPCore) GrantVoice(roomJID, nick string) error {
	return c.SetMUCRole(roomJID, nick, "participant")
}

func (c *XMPPCore) RevokeVoice(roomJID, nick string) error {
	return c.SetMUCRole(roomJID, nick, "visitor")
}

func (c *XMPPCore) GetMUCConfig(roomJID string) (map[string]string, error) {
	inner := fmt.Sprintf(`<query xmlns='%s'/>`, nsMUCOwner)
	resp, err := c.sendIQSync("get", roomJID, inner)
	if err != nil {
		return nil, err
	}

	return parseXDataForm(resp.Inner), nil
}

func (c *XMPPCore) ConfigureMUC(roomJID string, config map[string]string) error {
	var fields strings.Builder
	fields.WriteString(fmt.Sprintf(`<query xmlns='%s'><x xmlns='%s' type='submit'>`, nsMUCOwner, nsXData))
	fields.WriteString(fmt.Sprintf(`<field var='FORM_TYPE' type='hidden'><value>%s</value></field>`, nsMUCOwner))
	for k, v := range config {
		fields.WriteString(fmt.Sprintf(`<field var='%s'><value>%s</value></field>`, xmlEscape(k), xmlEscape(v)))
	}
	fields.WriteString(`</x></query>`)

	_, err := c.sendIQSync("set", roomJID, fields.String())
	return err
}

func (c *XMPPCore) DestroyMUC(roomJID, reason string) error {
	var reasonXML string
	if reason != "" {
		reasonXML = fmt.Sprintf(`<reason>%s</reason>`, xmlEscape(reason))
	}
	inner := fmt.Sprintf(
		`<query xmlns='%s'><destroy>%s</destroy></query>`,
		nsMUCOwner, reasonXML,
	)
	_, err := c.sendIQSync("set", roomJID, inner)

	c.roomsMu.Lock()
	delete(c.rooms, roomJID)
	c.roomsMu.Unlock()

	return err
}

func (c *XMPPCore) CreateInstantMUC(roomJID, nick string) error {
	if err := c.JoinMUC(roomJID, nick); err != nil {
		return err
	}
	inner := fmt.Sprintf(`<query xmlns='%s'><x xmlns='%s' type='submit'/></query>`, nsMUCOwner, nsXData)
	_, err := c.sendIQSync("set", roomJID, inner)
	return err
}

func (c *XMPPCore) RequestMUCHistory(roomJID string, maxStanzas int) error {
	c.roomsMu.RLock()
	room, ok := c.rooms[roomJID]
	nick := ""
	if ok {
		nick = room.Nick
	}
	c.roomsMu.RUnlock()

	return c.sendRawStanza(fmt.Sprintf(
		`<presence to='%s/%s'><x xmlns='%s'><history maxstanzas='%d'/></x></presence>`,
		xmlEscape(roomJID), xmlEscape(nick), nsMUC, maxStanzas,
	))
}

func (c *XMPPCore) MUCSelfPing(roomJID string) error {
	nick := ""
	c.roomsMu.RLock()
	if room, ok := c.rooms[roomJID]; ok {
		nick = room.Nick
	}
	c.roomsMu.RUnlock()

	if nick == "" {
		return errors.New("not in room")
	}

	inner := fmt.Sprintf(`<ping xmlns='%s'/>`, nsPing)
	_, err := c.sendIQSync("get", roomJID+"/"+nick, inner)
	return err
}

func (c *XMPPCore) DiscoInfo(target string) (*XMPPIQ, error) {
	if target == "" {
		target = c.domain
	}
	inner := fmt.Sprintf(`<query xmlns='%s'/>`, nsDiscoInfo)
	return c.sendIQSync("get", target, inner)
}

func (c *XMPPCore) DiscoItems(target string) (*XMPPIQ, error) {
	if target == "" {
		target = c.domain
	}
	inner := fmt.Sprintf(`<query xmlns='%s'/>`, nsDiscoItem)
	return c.sendIQSync("get", target, inner)
}

func (c *XMPPCore) QueryFeatures(target string) ([]string, error) {
	resp, err := c.DiscoInfo(target)
	if err != nil {
		return nil, err
	}
	return parseDiscoFeatures(resp.Inner), nil
}

func (c *XMPPCore) QueryIdentity(target string) (category, typ, name string, err error) {
	resp, err := c.DiscoInfo(target)
	if err != nil {
		return "", "", "", err
	}
	category = ExtractXMLAttr(resp.Inner, "identity", "category")
	typ = ExtractXMLAttr(resp.Inner, "identity", "type")
	name = ExtractXMLAttr(resp.Inner, "identity", "name")
	return
}

func (c *XMPPCore) DiscoverMUCService() (string, error) {
	resp, err := c.DiscoItems("")
	if err != nil {
		return "", err
	}

	items := parseDiscoItems(resp.Inner)
	for _, item := range items {
		infoResp, err := c.DiscoInfo(item)
		if err != nil {
			continue
		}
		if strings.Contains(infoResp.Inner, `category='conference'`) || strings.Contains(infoResp.Inner, `category="conference"`) {
			return item, nil
		}
	}
	return "", errors.New("no MUC service found")
}

func (c *XMPPCore) DiscoverHTTPUploadService() (string, int64, error) {
	resp, err := c.DiscoItems("")
	if err != nil {
		return "", 0, err
	}

	items := parseDiscoItems(resp.Inner)
	for _, item := range items {
		infoResp, err := c.DiscoInfo(item)
		if err != nil {
			continue
		}
		if strings.Contains(infoResp.Inner, nsUpload) {
			maxSize := parseUploadMaxSize(infoResp.Inner)
			return item, maxSize, nil
		}
	}
	return "", 0, errors.New("no HTTP upload service found")
}

func (c *XMPPCore) DiscoverExternalServices() ([]map[string]string, error) {
	inner := fmt.Sprintf(`<services xmlns='%s'/>`, nsExtSvc)
	resp, err := c.sendIQSync("get", c.domain, inner)
	if err != nil {
		return nil, err
	}

	return parseExternalServices(resp.Inner), nil
}

var xmppDiscoInfoBody string

func init() {
	features := []string{
		nsDiscoInfo, nsDiscoItem, nsCaps, nsChatState,
		nsReceipts, nsCorrect, nsReactions, nsReply,
		nsMarkers, nsPing, nsVersion, nsTime, nsLast,
		nsCarbons, nsBlocking,
	}
	var b strings.Builder
	b.WriteString("<query xmlns='")
	b.WriteString(nsDiscoInfo)
	b.WriteString("'><identity category='client' type='pc' name='Uniclient'/>")
	for _, f := range features {
		b.WriteString("<feature var='")
		b.WriteString(f)
		b.WriteString("'/>")
	}
	b.WriteString("</query>")
	xmppDiscoInfoBody = b.String()
}

func (c *XMPPCore) respondDiscoInfo(iq XMPPIQ) {
	var b strings.Builder
	b.Grow(64 + len(iq.ID) + len(iq.From) + len(xmppDiscoInfoBody))
	b.WriteString("<iq type='result' id='")
	b.WriteString(xmlEscape(iq.ID))
	b.WriteString("' to='")
	b.WriteString(xmlEscape(iq.From))
	b.WriteString("'>")
	b.WriteString(xmppDiscoInfoBody)
	b.WriteString("</iq>")
	c.sendRawStanza(b.String())
}

func (c *XMPPCore) discoverServices() {
	if c.mucService == "" {
		if svc, err := c.DiscoverMUCService(); err == nil {
			c.mu.Lock()
			c.mucService = svc
			c.mu.Unlock()
		}
	}

	if c.uploadService == "" {
		if svc, maxSize, err := c.DiscoverHTTPUploadService(); err == nil {
			c.mu.Lock()
			c.uploadService = svc
			c.uploadMaxSize = maxSize
			c.mu.Unlock()
		}
	}

	if feats, err := c.QueryFeatures(""); err == nil {
		c.mu.Lock()
		c.serverFeats = feats
		c.mu.Unlock()
	}
}

func (c *XMPPCore) RequestHTTPUploadSlot(filename string, size int64, contentType string) (putURL, getURL string, err error) {
	c.mu.RLock()
	uploadSvc := c.uploadService
	c.mu.RUnlock()

	if uploadSvc == "" {
		return "", "", fmt.Errorf("%w: no upload service", ErrNotSupported)
	}

	inner := fmt.Sprintf(
		`<request xmlns='%s' filename='%s' size='%d' content-type='%s'/>`,
		nsUpload, xmlEscape(filename), size, xmlEscape(contentType),
	)

	resp, err := c.sendIQSync("get", uploadSvc, inner)
	if err != nil {
		return "", "", err
	}

	putURL = ExtractXMLAttr(resp.Inner, "put", "url")
	getURL = ExtractXMLAttr(resp.Inner, "get", "url")

	if putURL == "" || getURL == "" {
		return "", "", errors.New("upload slot missing URLs")
	}

	return putURL, getURL, nil
}

func (c *XMPPCore) UploadFileHTTP(putURL string, data []byte, contentType string, progress func(sent, total int64)) error {
	req, err := http.NewRequestWithContext(c.ctx, "PUT", putURL, bytes.NewReader(data))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", contentType)
	req.ContentLength = int64(len(data))

	resp, err := TransferHTTPClient.Do(req)
	if err != nil {
		return fmt.Errorf("upload: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 300 {
		return fmt.Errorf("upload failed: HTTP %d", resp.StatusCode)
	}

	if progress != nil {
		progress(int64(len(data)), int64(len(data)))
	}
	return nil
}

func (c *XMPPCore) DownloadFileHTTP(url, dest string, progress func(recv, total int64)) error {
	req, err := http.NewRequestWithContext(c.ctx, "GET", url, nil)
	if err != nil {
		return err
	}

	resp, err := TransferHTTPClient.Do(req)
	if err != nil {
		return fmt.Errorf("download: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 300 {
		return fmt.Errorf("download failed: HTTP %d", resp.StatusCode)
	}

	f, err := os.Create(dest)
	if err != nil {
		return err
	}
	ok := false
	defer func() {
		if ok {
			f.Close()
			return
		}
		f.Close()
		os.Remove(dest)
	}()

	total := resp.ContentLength
	var received int64
	buf := make([]byte, 32*1024)
	for {
		n, readErr := resp.Body.Read(buf)
		if n > 0 {
			if received+int64(n) > DownloadCeiling {
				return fmt.Errorf("%w: more than %d bytes", ErrFileTooLarge, DownloadCeiling)
			}
			if _, writeErr := f.Write(buf[:n]); writeErr != nil {
				return writeErr
			}
			received += int64(n)
			if progress != nil {
				progress(received, total)
			}
		}
		if readErr != nil {
			if readErr == io.EOF {
				break
			}
			return readErr
		}
	}

	ok = true
	return nil
}

func (c *XMPPCore) SendFileURL(chatID, url, caption string) (*Message, error) {
	id := c.nextMsgID()
	msgType := "chat"
	if c.isRoom(chatID) {
		msgType = "groupchat"
	}

	body := url
	if caption != "" {
		body = caption
	}

	stanza := fmt.Sprintf(
		`<message type='%s' to='%s' id='%s'><body>%s</body><x xmlns='%s'><url>%s</url></x></message>`,
		msgType, xmlEscape(chatID), id, xmlEscape(body), nsOOB, xmlEscape(url),
	)

	if err := c.sendRawStanza(stanza); err != nil {
		return nil, err
	}

	m := &Message{
		ID:          id,
		ChatID:      chatID,
		SenderID:    c.bareJID,
		Text:        body,
		Timestamp:   time.Now(),
		Status:      MessageStatusSent,
		IsOutgoing:  true,
		Attachments: []FileRef{{URL: url, Name: caption}},
		Platform:    xmppPlatform,
	}
	c.bufferMessage(chatID, m)
	return m, nil
}

func (c *XMPPCore) CreatePubSubNode(service, node string) error {
	if service == "" {
		service = c.domain
	}
	inner := fmt.Sprintf(`<pubsub xmlns='%s'><create node='%s'/></pubsub>`, nsPubSub, xmlEscape(node))
	_, err := c.sendIQSync("set", service, inner)
	return err
}

func (c *XMPPCore) DeletePubSubNode(service, node string) error {
	if service == "" {
		service = c.domain
	}
	inner := fmt.Sprintf(`<pubsub xmlns='%s'><delete node='%s'/></pubsub>`, nsPubOwner, xmlEscape(node))
	_, err := c.sendIQSync("set", service, inner)
	return err
}

func (c *XMPPCore) PublishPubSubItem(service, node, itemID, payload string) error {
	if service == "" {
		service = c.bareJID
	}
	inner := fmt.Sprintf(
		`<pubsub xmlns='%s'><publish node='%s'><item id='%s'>%s</item></publish></pubsub>`,
		nsPubSub, xmlEscape(node), xmlEscape(itemID), payload,
	)
	_, err := c.sendIQSync("set", service, inner)
	return err
}

func (c *XMPPCore) RetractPubSubItem(service, node, itemID string) error {
	if service == "" {
		service = c.bareJID
	}
	inner := fmt.Sprintf(
		`<pubsub xmlns='%s'><retract node='%s'><item id='%s'/></retract></pubsub>`,
		nsPubSub, xmlEscape(node), xmlEscape(itemID),
	)
	_, err := c.sendIQSync("set", service, inner)
	return err
}

func (c *XMPPCore) SubscribePubSub(service, node string) error {
	if service == "" {
		service = c.domain
	}
	inner := fmt.Sprintf(
		`<pubsub xmlns='%s'><subscribe node='%s' jid='%s'/></pubsub>`,
		nsPubSub, xmlEscape(node), xmlEscape(c.bareJID),
	)
	_, err := c.sendIQSync("set", service, inner)
	return err
}

func (c *XMPPCore) UnsubscribePubSub(service, node string) error {
	if service == "" {
		service = c.domain
	}
	inner := fmt.Sprintf(
		`<pubsub xmlns='%s'><unsubscribe node='%s' jid='%s'/></pubsub>`,
		nsPubSub, xmlEscape(node), xmlEscape(c.bareJID),
	)
	_, err := c.sendIQSync("set", service, inner)
	return err
}

func (c *XMPPCore) GetPubSubItems(service, node string) (*XMPPIQ, error) {
	if service == "" {
		service = c.domain
	}
	inner := fmt.Sprintf(`<pubsub xmlns='%s'><items node='%s'/></pubsub>`, nsPubSub, xmlEscape(node))
	return c.sendIQSync("get", service, inner)
}

func (c *XMPPCore) GetPubSubSubscriptions(service string) (*XMPPIQ, error) {
	if service == "" {
		service = c.domain
	}
	inner := fmt.Sprintf(`<pubsub xmlns='%s'><subscriptions/></pubsub>`, nsPubSub)
	return c.sendIQSync("get", service, inner)
}

func (c *XMPPCore) ConfigurePubSubNode(service, node string, config map[string]string) error {
	if service == "" {
		service = c.domain
	}
	var fields strings.Builder
	fields.WriteString(fmt.Sprintf(`<pubsub xmlns='%s'><configure node='%s'><x xmlns='%s' type='submit'>`, nsPubOwner, xmlEscape(node), nsXData))
	for k, v := range config {
		fields.WriteString(fmt.Sprintf(`<field var='%s'><value>%s</value></field>`, xmlEscape(k), xmlEscape(v)))
	}
	fields.WriteString(`</x></configure></pubsub>`)
	_, err := c.sendIQSync("set", service, fields.String())
	return err
}

func (c *XMPPCore) SetUserMood(mood, text string) error {
	var textXML string
	if text != "" {
		textXML = fmt.Sprintf(`<text>%s</text>`, xmlEscape(text))
	}
	payload := fmt.Sprintf(`<mood xmlns='%s'><%s/>%s</mood>`, nsMood, xmlEscape(mood), textXML)
	return c.PublishPubSubItem("", nsMood, "current", payload)
}

func (c *XMPPCore) SetUserActivity(activity, specific, text string) error {
	var specificXML, textXML string
	if specific != "" {
		specificXML = fmt.Sprintf(`<%s/>`, xmlEscape(specific))
	}
	if text != "" {
		textXML = fmt.Sprintf(`<text>%s</text>`, xmlEscape(text))
	}
	payload := fmt.Sprintf(`<activity xmlns='%s'><%s>%s</%s>%s</activity>`,
		nsActivity, xmlEscape(activity), specificXML, xmlEscape(activity), textXML)
	return c.PublishPubSubItem("", nsActivity, "current", payload)
}

func (c *XMPPCore) SetUserTune(artist, title, source string, length int) error {
	var inner strings.Builder
	inner.WriteString(fmt.Sprintf(`<tune xmlns='%s'>`, nsTune))
	if artist != "" {
		inner.WriteString(fmt.Sprintf(`<artist>%s</artist>`, xmlEscape(artist)))
	}
	if title != "" {
		inner.WriteString(fmt.Sprintf(`<title>%s</title>`, xmlEscape(title)))
	}
	if source != "" {
		inner.WriteString(fmt.Sprintf(`<source>%s</source>`, xmlEscape(source)))
	}
	if length > 0 {
		inner.WriteString(fmt.Sprintf(`<length>%d</length>`, length))
	}
	inner.WriteString(`</tune>`)
	return c.PublishPubSubItem("", nsTune, "current", inner.String())
}

func (c *XMPPCore) SetUserLocation(lat, lon float64, description string) error {
	var inner strings.Builder
	inner.WriteString(fmt.Sprintf(`<geoloc xmlns='%s'>`, nsGeoLoc))
	inner.WriteString(fmt.Sprintf(`<lat>%f</lat>`, lat))
	inner.WriteString(fmt.Sprintf(`<lon>%f</lon>`, lon))
	if description != "" {
		inner.WriteString(fmt.Sprintf(`<description>%s</description>`, xmlEscape(description)))
	}
	inner.WriteString(`</geoloc>`)
	return c.PublishPubSubItem("", nsGeoLoc, "current", inner.String())
}

func (c *XMPPCore) SetAvatarPEP(imageData []byte, mimeType string) error {
	b64 := base64.StdEncoding.EncodeToString(imageData)
	h := sha1.Sum(imageData)
	hashStr := fmt.Sprintf("%x", h)

	dataPayload := fmt.Sprintf(`<data xmlns='%s'>%s</data>`, nsAvatarData, b64)
	if err := c.PublishPubSubItem("", nsAvatarData, hashStr, dataPayload); err != nil {
		return err
	}

	metaPayload := fmt.Sprintf(
		`<metadata xmlns='%s'><info id='%s' type='%s' bytes='%d'/></metadata>`,
		nsAvatarMeta, hashStr, xmlEscape(mimeType), len(imageData),
	)
	return c.PublishPubSubItem("", nsAvatarMeta, hashStr, metaPayload)
}

func (c *XMPPCore) GetAvatarPEP(jid string) ([]byte, error) {
	resp, err := c.GetPubSubItems(jid, nsAvatarData)
	if err != nil {
		return nil, err
	}

	data := ExtractXMLContent(resp.Inner, "data")
	if data == "" {
		return nil, ErrNotFound
	}
	return base64.StdEncoding.DecodeString(strings.TrimSpace(data))
}

func (c *XMPPCore) GetVCard(jid string) (map[string]string, error) {
	c.vcardCacheMu.RLock()
	if cached, ok := c.vcardCache[jid]; ok {
		c.vcardCacheMu.RUnlock()
		return cached, nil
	}
	c.vcardCacheMu.RUnlock()

	inner := fmt.Sprintf(`<vCard xmlns='%s'/>`, nsVCard)
	resp, err := c.sendIQSync("get", jid, inner)
	if err != nil {
		return nil, err
	}

	fields := parseVCard(resp.Inner)

	c.vcardCacheMu.Lock()
	c.vcardCache[jid] = fields
	c.vcardCacheMu.Unlock()

	return fields, nil
}

func (c *XMPPCore) SetVCard(fields map[string]string) error {
	var inner strings.Builder
	inner.WriteString(fmt.Sprintf(`<vCard xmlns='%s'>`, nsVCard))
	if fn, ok := fields["FN"]; ok {
		inner.WriteString(fmt.Sprintf(`<FN>%s</FN>`, xmlEscape(fn)))
	}
	if nick, ok := fields["NICKNAME"]; ok {
		inner.WriteString(fmt.Sprintf(`<NICKNAME>%s</NICKNAME>`, xmlEscape(nick)))
	}
	if email, ok := fields["EMAIL"]; ok {
		inner.WriteString(fmt.Sprintf(`<EMAIL><USERID>%s</USERID></EMAIL>`, xmlEscape(email)))
	}
	if url, ok := fields["URL"]; ok {
		inner.WriteString(fmt.Sprintf(`<URL>%s</URL>`, xmlEscape(url)))
	}
	if desc, ok := fields["DESC"]; ok {
		inner.WriteString(fmt.Sprintf(`<DESC>%s</DESC>`, xmlEscape(desc)))
	}
	inner.WriteString(`</vCard>`)

	_, err := c.sendIQSync("set", "", inner.String())
	return err
}

func (c *XMPPCore) GetVCardField(jid, field string) (string, error) {
	vcard, err := c.GetVCard(jid)
	if err != nil {
		return "", err
	}
	return vcard[field], nil
}

func (c *XMPPCore) SetAvatarVCard(imageData []byte, mimeType string) error {
	b64 := base64.StdEncoding.EncodeToString(imageData)
	fields := map[string]string{
		"PHOTO_TYPE":   mimeType,
		"PHOTO_BINVAL": b64,
	}

	var inner strings.Builder
	inner.WriteString(fmt.Sprintf(`<vCard xmlns='%s'>`, nsVCard))
	inner.WriteString(fmt.Sprintf(`<PHOTO><TYPE>%s</TYPE><BINVAL>%s</BINVAL></PHOTO>`, xmlEscape(mimeType), b64))
	inner.WriteString(`</vCard>`)

	_, err := c.sendIQSync("set", "", inner.String())
	if err != nil {
		return err
	}

	c.vcardCacheMu.Lock()
	if _, ok := c.vcardCache[c.bareJID]; !ok {
		c.vcardCache[c.bareJID] = make(map[string]string)
	}
	for k, v := range fields {
		c.vcardCache[c.bareJID][k] = v
	}
	c.vcardCacheMu.Unlock()

	return nil
}

func (c *XMPPCore) BlockJID(jid string) error {
	inner := fmt.Sprintf(`<block xmlns='%s'><item jid='%s'/></block>`, nsBlocking, xmlEscape(jid))
	_, err := c.sendIQSync("set", "", inner)
	if err == nil {
		c.blockedMu.Lock()
		c.blocked[jid] = true
		c.blockedMu.Unlock()
	}
	return err
}

func (c *XMPPCore) UnblockJID(jid string) error {
	inner := fmt.Sprintf(`<unblock xmlns='%s'><item jid='%s'/></unblock>`, nsBlocking, xmlEscape(jid))
	_, err := c.sendIQSync("set", "", inner)
	if err == nil {
		c.blockedMu.Lock()
		delete(c.blocked, jid)
		c.blockedMu.Unlock()
	}
	return err
}

func (c *XMPPCore) GetBlocklist() ([]string, error) {
	inner := fmt.Sprintf(`<blocklist xmlns='%s'/>`, nsBlocking)
	resp, err := c.sendIQSync("get", "", inner)
	if err != nil {
		c.blockedMu.RLock()
		defer c.blockedMu.RUnlock()
		var jids []string
		for jid := range c.blocked {
			jids = append(jids, jid)
		}
		return jids, nil
	}

	jids := parseJIDsFromInner(resp.Inner, "item")

	c.blockedMu.Lock()
	c.blocked = make(map[string]bool)
	for _, jid := range jids {
		c.blocked[jid] = true
	}
	c.blockedMu.Unlock()

	return jids, nil
}

func (c *XMPPCore) loadBookmarks() {
	resp, err := c.GetPubSubItems(c.bareJID, nsBmk2)
	if err == nil {
		bms := parseBookmarks2(resp.Inner)
		if len(bms) > 0 {
			c.bookmarksMu.Lock()
			c.bookmarks = bms
			c.bookmarksMu.Unlock()
			return
		}
	}

	inner := fmt.Sprintf(`<query xmlns='%s'><storage xmlns='%s'/></query>`, nsPrivate, nsBookmarks)
	resp2, err := c.sendIQSync("get", "", inner)
	if err != nil {
		return
	}

	bms := parseBookmarks(resp2.Inner)
	c.bookmarksMu.Lock()
	c.bookmarks = bms
	c.bookmarksMu.Unlock()
}

func (c *XMPPCore) GetBookmarks() ([]xmppBookmark, error) {
	c.bookmarksMu.RLock()
	if len(c.bookmarks) == 0 {
		c.bookmarksMu.RUnlock()
		c.loadBookmarks()
		c.bookmarksMu.RLock()
	}
	defer c.bookmarksMu.RUnlock()

	result := make([]xmppBookmark, len(c.bookmarks))
	copy(result, c.bookmarks)
	return result, nil
}

func (c *XMPPCore) SetBookmark(jid, name, nick string, autoJoin bool) error {
	c.bookmarksMu.Lock()
	found := false
	for i := range c.bookmarks {
		if c.bookmarks[i].JID == jid {
			c.bookmarks[i].Name = name
			c.bookmarks[i].Nick = nick
			c.bookmarks[i].AutoJoin = autoJoin
			found = true
			break
		}
	}
	if !found {
		c.bookmarks = append(c.bookmarks, xmppBookmark{
			JID:      jid,
			Name:     name,
			Nick:     nick,
			AutoJoin: autoJoin,
		})
	}
	bms := make([]xmppBookmark, len(c.bookmarks))
	copy(bms, c.bookmarks)
	c.bookmarksMu.Unlock()

	return c.saveBookmarks(bms)
}

func (c *XMPPCore) RemoveBookmark(jid string) error {
	c.bookmarksMu.Lock()
	for i := range c.bookmarks {
		if c.bookmarks[i].JID == jid {
			c.bookmarks = append(c.bookmarks[:i], c.bookmarks[i+1:]...)
			break
		}
	}
	bms := make([]xmppBookmark, len(c.bookmarks))
	copy(bms, c.bookmarks)
	c.bookmarksMu.Unlock()

	return c.saveBookmarks(bms)
}

func (c *XMPPCore) SetBookmarkAutoJoin(jid string, autoJoin bool) error {
	c.bookmarksMu.Lock()
	for i := range c.bookmarks {
		if c.bookmarks[i].JID == jid {
			c.bookmarks[i].AutoJoin = autoJoin
			break
		}
	}
	bms := make([]xmppBookmark, len(c.bookmarks))
	copy(bms, c.bookmarks)
	c.bookmarksMu.Unlock()

	return c.saveBookmarks(bms)
}

func (c *XMPPCore) saveBookmarks(bms []xmppBookmark) error {
	var inner strings.Builder
	inner.WriteString(fmt.Sprintf(`<query xmlns='%s'><storage xmlns='%s'>`, nsPrivate, nsBookmarks))
	for _, bm := range bms {
		autoJoin := "false"
		if bm.AutoJoin {
			autoJoin = "true"
		}
		inner.WriteString(fmt.Sprintf(`<conference jid='%s' autojoin='%s'`,
			xmlEscape(bm.JID), autoJoin))
		if bm.Name != "" {
			inner.WriteString(fmt.Sprintf(` name='%s'`, xmlEscape(bm.Name)))
		}
		inner.WriteString(`>`)
		if bm.Nick != "" {
			inner.WriteString(fmt.Sprintf(`<nick>%s</nick>`, xmlEscape(bm.Nick)))
		}
		inner.WriteString(`</conference>`)
	}
	inner.WriteString(`</storage></query>`)

	_, err := c.sendIQSync("set", "", inner.String())
	return err
}

func (c *XMPPCore) autoJoinBookmarks() {
	c.loadBookmarks()

	c.bookmarksMu.RLock()
	for _, bm := range c.bookmarks {
		if bm.AutoJoin {
			nick := bm.Nick
			c.JoinMUC(bm.JID, nick)
			time.Sleep(200 * time.Millisecond)
		}
	}
	c.bookmarksMu.RUnlock()
}

func (c *XMPPCore) QueryMAM(jid string, limit int, after string) ([]Message, error) {
	if limit <= 0 {
		limit = 50
	}

	var formFields strings.Builder
	formFields.WriteString(fmt.Sprintf(`<x xmlns='%s' type='submit'>`, nsXData))
	formFields.WriteString(fmt.Sprintf(`<field var='FORM_TYPE' type='hidden'><value>%s</value></field>`, nsMAM))
	if jid != "" {
		formFields.WriteString(fmt.Sprintf(`<field var='with'><value>%s</value></field>`, xmlEscape(jid)))
	}
	formFields.WriteString(`</x>`)

	var rsm string
	rsm = fmt.Sprintf(`<set xmlns='%s'><max>%d</max>`, nsRSM, limit)
	if after != "" {
		rsm += fmt.Sprintf(`<after>%s</after>`, xmlEscape(after))
	}
	rsm += `</set>`

	inner := fmt.Sprintf(`<query xmlns='%s'>%s%s</query>`, nsMAM, formFields.String(), rsm)
	_, err := c.sendIQSync("set", "", inner)
	if err != nil {
		return nil, err
	}

	c.messagesMu.RLock()
	defer c.messagesMu.RUnlock()

	if msgs, ok := c.messages[jid]; ok {
		result := make([]Message, len(msgs))
		for i, m := range msgs {
			result[i] = *m
		}
		return result, nil
	}

	return nil, nil
}

func (c *XMPPCore) QueryMAMByJID(jid string, limit int) ([]Message, error) {
	return c.QueryMAM(jid, limit, "")
}

func (c *XMPPCore) QueryMAMByDateRange(jid string, start, end time.Time, limit int) ([]Message, error) {
	if limit <= 0 {
		limit = 50
	}

	var formFields strings.Builder
	formFields.WriteString(fmt.Sprintf(`<x xmlns='%s' type='submit'>`, nsXData))
	formFields.WriteString(fmt.Sprintf(`<field var='FORM_TYPE' type='hidden'><value>%s</value></field>`, nsMAM))
	if jid != "" {
		formFields.WriteString(fmt.Sprintf(`<field var='with'><value>%s</value></field>`, xmlEscape(jid)))
	}
	if !start.IsZero() {
		formFields.WriteString(fmt.Sprintf(`<field var='start'><value>%s</value></field>`, start.UTC().Format("2006-01-02T15:04:05Z")))
	}
	if !end.IsZero() {
		formFields.WriteString(fmt.Sprintf(`<field var='end'><value>%s</value></field>`, end.UTC().Format("2006-01-02T15:04:05Z")))
	}
	formFields.WriteString(`</x>`)

	rsm := fmt.Sprintf(`<set xmlns='%s'><max>%d</max></set>`, nsRSM, limit)

	inner := fmt.Sprintf(`<query xmlns='%s'>%s%s</query>`, nsMAM, formFields.String(), rsm)
	_, err := c.sendIQSync("set", "", inner)
	if err != nil {
		return nil, err
	}

	c.messagesMu.RLock()
	defer c.messagesMu.RUnlock()
	if msgs, ok := c.messages[jid]; ok {
		result := make([]Message, len(msgs))
		for i, m := range msgs {
			result[i] = *m
		}
		return result, nil
	}
	return nil, nil
}

func (c *XMPPCore) QueryMAMPage(jid string, limit int, after string) ([]Message, error) {
	return c.QueryMAM(jid, limit, after)
}

func BuildIBRStanza(id, username, password string) string {
	return fmt.Sprintf(
		`<iq type='set' id='%s'><query xmlns='%s'><username>%s</username><password>%s</password></query></iq>`,
		xmlEscape(id), nsRegister, xmlEscape(username), xmlEscape(password),
	)
}

type IbrFormField struct {
	Var      string
	Type     string
	Value    string
	Required bool
}

func BuildIBRGetStanza(id string) string {
	return fmt.Sprintf(`<iq type='get' id='%s'><query xmlns='%s'/></iq>`, xmlEscape(id), nsRegister)
}

func ParseIBRForm(raw string) (fields []IbrFormField, ok bool) {
	xStart := -1
	for _, marker := range []string{"<x xmlns='jabber:x:data'", `<x xmlns="jabber:x:data"`} {
		if i := strings.Index(raw, marker); i >= 0 && (xStart < 0 || i < xStart) {
			xStart = i
		}
	}
	if xStart < 0 || !strings.Contains(raw, "type='form'") && !strings.Contains(raw, `type="form"`) {
		return nil, false
	}
	rest := raw[xStart:]
	if e := strings.Index(rest, "</x>"); e >= 0 {
		rest = rest[:e]
	}
	for {
		f := strings.Index(rest, "<field")
		if f < 0 {
			break
		}
		rest = rest[f:]
		end := strings.Index(rest, "</field>")
		selfClose := strings.Index(rest, "/>")
		if end < 0 && selfClose < 0 {
			break
		}
		var body string
		if end >= 0 && (selfClose < 0 || end < selfClose) {
			body = rest[:end]
			rest = rest[end+len("</field>"):]
		} else {
			body = rest[:selfClose]
			rest = rest[selfClose+2:]
		}
		fld := IbrFormField{}
		if v := ExtractXMLAttr(body, "field", "var"); v != "" {
			fld.Var = v
		}
		if v := ExtractXMLAttr(body, "field", "type"); v != "" {
			fld.Type = v
		}
		if strings.Contains(body, "<required") {
			fld.Required = true
		}
		if val := ExtractXMLContent(body, "value"); val != "" {
			fld.Value = xmlUnescape(val)
		}
		if fld.Var != "" {
			fields = append(fields, fld)
		}
	}
	return fields, len(fields) > 0
}

func BuildIBRDataFormSubmit(id string, fields []IbrFormField, username, password string) string {
	var b strings.Builder
	b.WriteString(fmt.Sprintf(`<iq type='set' id='%s'><query xmlns='%s'><x xmlns='jabber:x:data' type='submit'>`, xmlEscape(id), nsRegister))
	for _, f := range fields {
		switch f.Var {
		case "username":
			b.WriteString(fmt.Sprintf("<field var='username'><value>%s</value></field>", xmlEscape(username)))
		case "password":
			b.WriteString(fmt.Sprintf("<field var='password'><value>%s</value></field>", xmlEscape(password)))
		default:
			if f.Type == "hidden" && f.Value != "" {
				b.WriteString(fmt.Sprintf("<field var='%s' type='hidden'><value>%s</value></field>", xmlEscape(f.Var), xmlEscape(f.Value)))
			}
		}
	}
	b.WriteString(`</x></query></iq>`)
	return b.String()
}

func ParseIBRResponse(raw string) error {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return errors.New("ibr: empty response")
	}
	if !strings.Contains(raw, "type='result'") && !strings.Contains(raw, `type="result"`) {
		cond := "unknown"
		for _, c := range []string{
			"conflict", "not-allowed", "forbidden", "not-acceptable",
			"registration-required", "service-unavailable", "bad-request",
			"policy-violation", "not-authorized", "jid-malformed",
		} {
			if strings.Contains(raw, "<"+c) {
				cond = c
				break
			}
		}
		text := ""
		if s := strings.Index(raw, "<text"); s >= 0 {
			if a := strings.Index(raw[s:], ">"); a >= 0 {
				rest := raw[s+a+1:]
				if e := strings.Index(rest, "</text>"); e >= 0 {
					text = strings.TrimSpace(xmlUnescape(rest[:e]))
				}
			}
		}
		if text != "" {
			return fmt.Errorf("ibr: %s: %s", cond, text)
		}
		return fmt.Errorf("ibr: server rejected registration (%s): %.200s", cond, raw)
	}
	if !strings.Contains(raw, nsRegister) {
		return fmt.Errorf("ibr: unexpected result payload: %.200s", raw)
	}
	if u := ExtractXMLContent(raw, "url"); u != "" && !strings.Contains(raw, "<username>") {
		return fmt.Errorf("ibr: server requires web registration at %s (out-of-band)", xmlUnescape(u))
	}
	return nil
}

func (c *XMPPCore) registerPreAuth() error {
	c.mu.RLock()
	local := c.bareJID
	advertised := c.features.IBR != nil
	c.mu.RUnlock()
	if at := strings.Index(local, "@"); at > 0 {
		local = local[:at]
	}
	_ = advertised

	if err := c.sendRawStanza(BuildIBRGetStanza(c.nextIQID())); err != nil {
		return fmt.Errorf("ibr get send: %w", err)
	}
	formResp, err := c.readRawIQResponse()
	if err != nil {
		return fmt.Errorf("ibr get: %w", err)
	}
	if strings.Contains(formResp, "type='error'") || strings.Contains(formResp, `type="error"`) {
		return ParseIBRResponse(formResp)
	}

	var stanza string
	if fields, hasForm := ParseIBRForm(formResp); hasForm {
		stanza = BuildIBRDataFormSubmit(c.nextIQID(), fields, local, c.password)
	} else {
		stanza = BuildIBRStanza(c.nextIQID(), local, c.password)
	}
	if err := c.sendRawStanza(stanza); err != nil {
		return fmt.Errorf("ibr send: %w", err)
	}
	resp, err := c.readRawIQResponse()
	if err != nil {
		return fmt.Errorf("ibr: %w", err)
	}
	return ParseIBRResponse(resp)
}

func (c *XMPPCore) RegisterAccount(server, username, password string) error {
	inner := fmt.Sprintf(
		`<query xmlns='%s'><username>%s</username><password>%s</password></query>`,
		nsRegister, xmlEscape(username), xmlEscape(password),
	)
	_, err := c.sendIQSync("set", server, inner)
	return err
}

func (c *XMPPCore) ChangePassword(newPassword string) error {
	local := c.bareJID
	if at := strings.Index(local, "@"); at > 0 {
		local = local[:at]
	}
	inner := fmt.Sprintf(
		`<query xmlns='%s'><username>%s</username><password>%s</password></query>`,
		nsRegister, xmlEscape(local), xmlEscape(newPassword),
	)
	_, err := c.sendIQSync("set", "", inner)
	if err == nil {
		c.mu.Lock()
		c.password = newPassword
		c.mu.Unlock()
	}
	return err
}

func (c *XMPPCore) UnregisterAccount() error {
	inner := fmt.Sprintf(`<query xmlns='%s'><remove/></query>`, nsRegister)
	_, err := c.sendIQSync("set", "", inner)
	return err
}

func (c *XMPPCore) EnableStreamManagement() error {
	err := c.sendRawStanza(fmt.Sprintf(`<enable xmlns='%s' resume='true'/>`, nsSM))
	if err != nil {
		return err
	}

	c.mu.Lock()
	c.smEnabled = true
	c.mu.Unlock()
	return nil
}

func (c *XMPPCore) RequestAck() error {
	return c.sendRawStanza(fmt.Sprintf(`<r xmlns='%s'/>`, nsSM))
}

func (c *XMPPCore) SendAck() error {
	h := c.smInH.Load()
	c.writeMu.Lock()
	defer c.writeMu.Unlock()
	_, err := c.conn.Write([]byte("<a xmlns='" + nsSM + "' h='" + strconv.FormatInt(h, 10) + "'/>"))
	return err
}

func (c *XMPPCore) ResumeStream(prevID string, h int64) error {
	return c.sendRawStanza(fmt.Sprintf(`<resume xmlns='%s' previd='%s' h='%d'/>`, nsSM, xmlEscape(prevID), h))
}

func (c *XMPPCore) handleAck(h int64) {
	c.smOutMu.Lock()
	defer c.smOutMu.Unlock()

	acked := int(h - c.smOutH.Load() + int64(len(c.smOutQueue)))
	if acked > 0 && acked <= len(c.smOutQueue) {
		c.smOutQueue = c.smOutQueue[acked:]
	}
}

func (c *XMPPCore) SendPing(to string) error {
	if to == "" {
		to = c.domain
	}
	inner := fmt.Sprintf(`<ping xmlns='%s'/>`, nsPing)
	_, err := c.sendIQSync("get", to, inner)
	return err
}

func (c *XMPPCore) GetSoftwareVersion(jid string) (name, version, os string, err error) {
	inner := fmt.Sprintf(`<query xmlns='%s'/>`, nsVersion)
	resp, err := c.sendIQSync("get", jid, inner)
	if err != nil {
		return "", "", "", err
	}

	name = ExtractXMLContent(resp.Inner, "name")
	version = ExtractXMLContent(resp.Inner, "version")
	os = ExtractXMLContent(resp.Inner, "os")
	return
}

func (c *XMPPCore) GetLastActivity(jid string) (int64, error) {
	inner := fmt.Sprintf(`<query xmlns='%s'/>`, nsLast)
	resp, err := c.sendIQSync("get", jid, inner)
	if err != nil {
		return 0, err
	}

	secsStr := ExtractXMLAttr(resp.Inner, "query", "seconds")
	secs, _ := strconv.ParseInt(secsStr, 10, 64)
	return secs, nil
}

func (c *XMPPCore) GetEntityTime(jid string) (utc, tzo string, err error) {
	inner := fmt.Sprintf(`<time xmlns='%s'/>`, nsTime)
	resp, err := c.sendIQSync("get", jid, inner)
	if err != nil {
		return "", "", err
	}

	utc = ExtractXMLContent(resp.Inner, "utc")
	tzo = ExtractXMLContent(resp.Inner, "tzo")
	return
}

func (c *XMPPCore) SetClientStateActive() error {
	return c.sendRawStanza(fmt.Sprintf(`<active xmlns='%s'/>`, nsCSI))
}

func (c *XMPPCore) SetClientStateInactive() error {
	return c.sendRawStanza(fmt.Sprintf(`<inactive xmlns='%s'/>`, nsCSI))
}

func (c *XMPPCore) GetEntityCapabilities(jid string) (string, error) {
	resp, err := c.DiscoInfo(jid)
	if err != nil {
		return "", err
	}
	return resp.Inner, nil
}

func (c *XMPPCore) InitiateJingle(to string, video bool) (*CallSession, error) {
	sid := fmt.Sprintf("jingle_%d", time.Now().UnixNano())
	media := "audio"
	if video {
		media = "video"
	}

	inner := fmt.Sprintf(
		`<jingle xmlns='%s' action='session-initiate' sid='%s' initiator='%s'>`+
			`<content creator='initiator' name='%s'>`+
			`<description xmlns='%s' media='%s'>`+
			`<payload-type id='111' name='opus' clockrate='48000' channels='2'/>`+
			`</description>`+
			`<transport xmlns='%s'/>`+
			`</content></jingle>`,
		nsJingle, xmlEscape(sid), xmlEscape(c.jid),
		media, nsJingleRTP, media, nsJingleICE,
	)

	_, err := c.sendIQSync("set", to, inner)
	if err != nil {
		return nil, err
	}

	return &CallSession{
		ID:      sid,
		ChatID:  bareJID(to),
		IsVideo: video,
		State:   CallStateRinging,
		Participants: []CallParticipant{
			{UserID: c.bareJID, DisplayName: c.bareJID},
			{UserID: bareJID(to), DisplayName: bareJID(to)},
		},
	}, nil
}

func (c *XMPPCore) AcceptJingle(to, sid string) error {
	inner := fmt.Sprintf(
		`<jingle xmlns='%s' action='session-accept' sid='%s' responder='%s'>`+
			`<content creator='initiator' name='audio'>`+
			`<description xmlns='%s' media='audio'>`+
			`<payload-type id='111' name='opus' clockrate='48000' channels='2'/>`+
			`</description>`+
			`<transport xmlns='%s'/>`+
			`</content></jingle>`,
		nsJingle, xmlEscape(sid), xmlEscape(c.jid), nsJingleRTP, nsJingleICE,
	)
	_, err := c.sendIQSync("set", to, inner)
	return err
}

func (c *XMPPCore) RejectJingle(to, sid string) error {
	return c.TerminateJingle(sid, "decline")
}

func (c *XMPPCore) TerminateJingle(sid, reason string) error {
	if reason == "" {
		reason = "success"
	}
	inner := fmt.Sprintf(
		`<jingle xmlns='%s' action='session-terminate' sid='%s'><reason><%s/></reason></jingle>`,
		nsJingle, xmlEscape(sid), xmlEscape(reason),
	)
	return c.sendRawStanza(fmt.Sprintf(`<iq type='set' id='%s'>%s</iq>`, c.nextIQID(), inner))
}

func (c *XMPPCore) SendJingleTransportInfo(to, sid, candidate string) error {
	inner := fmt.Sprintf(
		`<jingle xmlns='%s' action='transport-info' sid='%s'>`+
			`<content creator='initiator' name='audio'>`+
			`<transport xmlns='%s'>%s</transport>`+
			`</content></jingle>`,
		nsJingle, xmlEscape(sid), nsJingleICE, candidate,
	)
	_, err := c.sendIQSync("set", to, inner)
	return err
}

func (c *XMPPCore) GetTURNCredentials() ([]map[string]string, error) {
	return c.DiscoverExternalServices()
}

func (c *XMPPCore) parseMessageInner(inner string) *xmppParsedMessage {
	p := &xmppParsedMessage{}

	p.Body = ExtractXMLContent(inner, "body")
	p.Subject = ExtractXMLContent(inner, "subject")
	p.Thread = ExtractXMLContent(inner, "thread")

	if strings.Contains(inner, nsDelay) {
		stamp := ExtractXMLAttr(inner, "delay", "stamp")
		if stamp != "" {
			if t, err := time.Parse("2006-01-02T15:04:05Z", stamp); err == nil {
				p.Delay = &t
			} else if t, err := time.Parse("2006-01-02T15:04:05.000Z", stamp); err == nil {
				p.Delay = &t
			}
		}
		p.DelayFrom = ExtractXMLAttr(inner, "delay", "from")
	}

	if strings.Contains(inner, nsOOB) {
		p.OOB = ExtractXMLContent(inner, "url")
	}

	if strings.Contains(inner, nsReceipts) {
		if strings.Contains(inner, "<request") {
			p.ReceiptRequest = true
		}
		if strings.Contains(inner, "<received") {
			p.ReceiptFor = ExtractXMLAttr(inner, "received", "id")
		}
	}

	if strings.Contains(inner, nsChatState) {
		for _, state := range []string{"composing", "active", "paused", "inactive", "gone"} {
			if strings.Contains(inner, "<"+state) {
				p.ChatState = state
				break
			}
		}
	}

	if strings.Contains(inner, nsCorrect) {
		p.ReplaceID = ExtractXMLAttr(inner, "replace", "id")
	}

	if strings.Contains(inner, nsMarkers) {
		p.DisplayedID = ExtractXMLAttr(inner, "displayed", "id")
		p.ReceivedID = ExtractXMLAttr(inner, "received", "id")
	}

	if strings.Contains(inner, nsReply) {
		p.ReplyTo = ExtractXMLAttr(inner, "reply", "to")
		p.ReplyID = ExtractXMLAttr(inner, "reply", "id")
	}

	if strings.Contains(inner, nsReactions) {
		p.ReactionsID = ExtractXMLAttr(inner, "reactions", "id")
		p.Reactions = extractXMLContents(inner, "reaction")
	}

	if strings.Contains(inner, nsDirectMUC) {
		p.MUCInviteRoom = ExtractXMLAttr(inner, "x", "jid")
		p.MUCInviteFrom = "direct"
	} else if strings.Contains(inner, nsMUCUser) && strings.Contains(inner, "<invite") {
		p.MUCInviteRoom = ExtractXMLAttr(inner, "invite", "from")
		p.MUCInviteFrom = "mediated"
	}

	if strings.Contains(inner, nsCarbons) {
		if strings.Contains(inner, "<sent") {
			p.CarbonType = "sent"
		} else if strings.Contains(inner, "<received") {
			p.CarbonType = "received"
		}
		if strings.Contains(inner, nsForward) {
			fwdInner := extractXMLBlock(inner, "message")
			if fwdInner != "" {
				p.CarbonMsg = c.parseMessageInner(fwdInner)
			}
		}
	}

	if strings.Contains(inner, nsMAM) {
		p.MAMID = ExtractXMLAttr(inner, "result", "id")
		p.MAMQueryID = ExtractXMLAttr(inner, "result", "queryid")
		if strings.Contains(inner, nsForward) {
			fwdInner := extractXMLBlock(inner, "message")
			if fwdInner != "" {
				p.MAMMsg = c.parseMessageInner(fwdInner)
			}
		}
	}

	return p
}

func (c *XMPPCore) saveSession() {
	sess := xmppSession{
		JID:            c.jid,
		Server:         c.server,
		Resource:       c.resource,
		MUCService:     c.mucService,
		UploadService:  c.uploadService,
		UploadMaxSize:  c.uploadMaxSize,
		RosterVer:      c.rosterVer,
		SMEnabled:      c.smEnabled,
		SMResumeID:     c.smResumeID,
		CarbonsEnabled: c.carbonsEnabled,
	}

	c.roomsMu.RLock()
	for jid, room := range c.rooms {
		if room.Joined {
			sess.JoinedRooms = append(sess.JoinedRooms, jid)
		}
	}
	c.roomsMu.RUnlock()

	c.bookmarksMu.RLock()
	sess.Bookmarks = c.bookmarks
	c.bookmarksMu.RUnlock()

	c.blockedMu.RLock()
	for jid := range c.blocked {
		sess.Blocked = append(sess.Blocked, jid)
	}
	c.blockedMu.RUnlock()

	if c.session != nil {
		c.session.Save(sess)
	}
}

func (c *XMPPCore) loadSession() {
	if c.session == nil {
		return
	}
	var sess xmppSession
	if c.session.Load(&sess) != nil {
		return
	}

	c.mu.Lock()
	if sess.MUCService != "" && c.mucService == "" {
		c.mucService = sess.MUCService
	}
	if sess.UploadService != "" && c.uploadService == "" {
		c.uploadService = sess.UploadService
		c.uploadMaxSize = sess.UploadMaxSize
	}
	c.rosterVer = sess.RosterVer
	c.smResumeID = sess.SMResumeID
	c.mu.Unlock()

	c.bookmarksMu.Lock()
	c.bookmarks = sess.Bookmarks
	c.bookmarksMu.Unlock()

	c.blockedMu.Lock()
	for _, jid := range sess.Blocked {
		c.blocked[jid] = true
	}
	c.blockedMu.Unlock()
}

func (c *XMPPCore) bufferMessage(chatID string, m *Message) {
	c.messagesMu.Lock()
	defer c.messagesMu.Unlock()
	c.messages[chatID] = append(c.messages[chatID], m)
	if len(c.messages[chatID]) > xmppMsgBufSize {
		c.messages[chatID] = c.messages[chatID][1:]
	}
}

func (c *XMPPCore) nextMsgID() string {
	return "msg_" + strconv.FormatInt(atomic.AddInt64(&c.msgCounter, 1), 10)
}

func (c *XMPPCore) fireUpdate(u Update) {
	c.updateMu.RLock()
	if len(c.updateHandlers) == 0 {
		c.updateMu.RUnlock()
		return
	}
	handlers := make([]func(Update), len(c.updateHandlers))
	copy(handlers, c.updateHandlers)
	c.updateMu.RUnlock()

	for _, h := range handlers {
		h(u)
	}
}

func bareJID(jid string) string {
	if sl := strings.Index(jid, "/"); sl > 0 {
		return jid[:sl]
	}
	return jid
}

func resourceFromJID(jid string) string {
	if sl := strings.Index(jid, "/"); sl >= 0 && sl < len(jid)-1 {
		return jid[sl+1:]
	}
	return ""
}

func (c *XMPPCore) isRoom(jid string) bool {
	c.roomsMu.RLock()
	_, ok := c.rooms[jid]
	c.roomsMu.RUnlock()
	if ok {
		return true
	}

	c.mu.RLock()
	mucSvc := c.mucService
	c.mu.RUnlock()

	if mucSvc != "" {
		if at := strings.IndexByte(jid, '@'); at >= 0 && jid[at+1:] == mucSvc {
			return true
		}
	}

	return false
}

func xmlEscape(s string) string {
	if !strings.ContainsAny(s, `<>&'"`) {
		return s
	}
	var b strings.Builder
	b.Grow(len(s) + 10)
	xml.EscapeText(&b, []byte(s))
	return b.String()
}

func xmlUnescape(s string) string {
	if !strings.Contains(s, "&") {
		return s
	}
	r := strings.NewReplacer(
		"&lt;", "<", "&gt;", ">", "&quot;", `"`, "&apos;", "'", "&amp;", "&",
	)
	return r.Replace(s)
}

func ExtractXMLContent(xmlStr, elemName string) string {
	start := "<" + elemName
	end := "</" + elemName + ">"

	idx := strings.Index(xmlStr, start)
	if idx < 0 {
		return ""
	}

	rest := xmlStr[idx+len(start):]
	gt := strings.IndexByte(rest, '>')
	if gt < 0 {
		return ""
	}
	rest = rest[gt+1:]

	endIdx := strings.Index(rest, end)
	if endIdx < 0 {
		return rest
	}

	return rest[:endIdx]
}

func extractXMLContents(xmlStr, elemName string) []string {
	var results []string
	remaining := xmlStr
	for {
		content := ExtractXMLContent(remaining, elemName)
		if content == "" {
			break
		}
		results = append(results, content)
		endTag := "</" + elemName + ">"
		idx := strings.Index(remaining, endTag)
		if idx < 0 {
			break
		}
		remaining = remaining[idx+len(endTag):]
	}
	return results
}

func ExtractXMLAttr(xmlStr, elemName, attrName string) string {
	start := "<" + elemName
	idx := strings.Index(xmlStr, start)
	if idx < 0 {
		return ""
	}

	rest := xmlStr[idx:]
	gt := strings.IndexByte(rest, '>')
	if gt < 0 {
		return ""
	}
	tag := rest[:gt+1]

	for _, quote := range []string{"'", `"`} {
		pattern := attrName + "=" + quote
		aIdx := strings.Index(tag, pattern)
		if aIdx < 0 {
			continue
		}
		valueStart := aIdx + len(pattern)
		valueEnd := strings.Index(tag[valueStart:], quote)
		if valueEnd < 0 {
			continue
		}
		return tag[valueStart : valueStart+valueEnd]
	}

	return ""
}

func extractXMLBlock(xmlStr, elemName string) string {
	start := "<" + elemName
	idx := strings.Index(xmlStr, start)
	if idx < 0 {
		return ""
	}

	end := "</" + elemName + ">"
	endIdx := strings.Index(xmlStr[idx:], end)
	if endIdx < 0 {
		return ""
	}

	return xmlStr[idx : idx+endIdx+len(end)]
}

func parseJIDsFromInner(inner, elemName string) []string {
	var jids []string
	remaining := inner
	for {
		jid := ExtractXMLAttr(remaining, elemName, "jid")
		if jid == "" {
			break
		}
		jids = append(jids, jid)
		endTag := "/>"
		idx := strings.Index(remaining, jid)
		if idx < 0 {
			break
		}
		next := strings.Index(remaining[idx:], endTag)
		if next < 0 {
			next = strings.Index(remaining[idx:], ">")
			if next < 0 {
				break
			}
		}
		remaining = remaining[idx+next+len(endTag):]
	}
	return jids
}

func parsePresenceShowStatus(inner string) (show, status string) {
	show = ExtractXMLContent(inner, "show")
	status = ExtractXMLContent(inner, "status")
	return
}

func parseMUCUserItem(inner string) (role, affiliation, realJID string) {
	role = ExtractXMLAttr(inner, "item", "role")
	affiliation = ExtractXMLAttr(inner, "item", "affiliation")
	realJID = ExtractXMLAttr(inner, "item", "jid")
	return
}

func parseDiscoFeatures(inner string) []string {
	var features []string
	remaining := inner
	for {
		feat := ExtractXMLAttr(remaining, "feature", "var")
		if feat == "" {
			break
		}
		features = append(features, feat)
		idx := strings.Index(remaining, feat)
		if idx < 0 {
			break
		}
		remaining = remaining[idx+len(feat):]
	}
	return features
}

func parseDiscoItems(inner string) []string {
	var items []string
	remaining := inner
	for {
		jid := ExtractXMLAttr(remaining, "item", "jid")
		if jid == "" {
			break
		}
		items = append(items, jid)
		idx := strings.Index(remaining, jid)
		if idx < 0 {
			break
		}
		remaining = remaining[idx+len(jid):]
	}
	return items
}

func parseXDataForm(inner string) map[string]string {
	fields := make(map[string]string)
	remaining := inner
	for {
		varName := ExtractXMLAttr(remaining, "field", "var")
		if varName == "" {
			break
		}
		fieldStart := strings.Index(remaining, varName)
		if fieldStart < 0 {
			break
		}
		rest := remaining[fieldStart:]
		value := ExtractXMLContent(rest, "value")
		fields[varName] = value
		remaining = rest[len(varName):]
	}
	return fields
}

func parseUploadMaxSize(inner string) int64 {
	sizeStr := ExtractXMLContent(inner, "value")
	if sizeStr != "" {
		if size, err := strconv.ParseInt(sizeStr, 10, 64); err == nil {
			return size
		}
	}
	return 0
}

func parseVCard(inner string) map[string]string {
	fields := make(map[string]string)
	fields["FN"] = ExtractXMLContent(inner, "FN")
	fields["NICKNAME"] = ExtractXMLContent(inner, "NICKNAME")
	fields["URL"] = ExtractXMLContent(inner, "URL")
	fields["DESC"] = ExtractXMLContent(inner, "DESC")
	fields["EMAIL"] = ExtractXMLContent(inner, "USERID")
	fields["TEL"] = ExtractXMLContent(inner, "NUMBER")
	fields["PHOTO_TYPE"] = ExtractXMLContent(inner, "TYPE")
	fields["PHOTO_BINVAL"] = ExtractXMLContent(inner, "BINVAL")
	return fields
}

func parseBookmarks(inner string) []xmppBookmark {
	var bms []xmppBookmark
	remaining := inner
	for {
		jid := ExtractXMLAttr(remaining, "conference", "jid")
		if jid == "" {
			break
		}
		bm := xmppBookmark{
			JID:      jid,
			Name:     ExtractXMLAttr(remaining, "conference", "name"),
			AutoJoin: ExtractXMLAttr(remaining, "conference", "autojoin") == "true",
		}
		confIdx := strings.Index(remaining, jid)
		if confIdx >= 0 {
			rest := remaining[confIdx:]
			bm.Nick = ExtractXMLContent(rest, "nick")
		}
		bms = append(bms, bm)

		idx := strings.Index(remaining, jid)
		if idx < 0 {
			break
		}
		remaining = remaining[idx+len(jid):]
	}
	return bms
}

func parseBookmarks2(inner string) []xmppBookmark {
	return parseBookmarks(inner)
}

func parseExternalServices(inner string) []map[string]string {
	var services []map[string]string
	remaining := inner
	for {
		host := ExtractXMLAttr(remaining, "service", "host")
		if host == "" {
			break
		}
		svc := map[string]string{
			"host":      host,
			"port":      ExtractXMLAttr(remaining, "service", "port"),
			"type":      ExtractXMLAttr(remaining, "service", "type"),
			"transport": ExtractXMLAttr(remaining, "service", "transport"),
			"username":  ExtractXMLAttr(remaining, "service", "username"),
			"password":  ExtractXMLAttr(remaining, "service", "password"),
		}
		services = append(services, svc)

		idx := strings.Index(remaining, host)
		if idx < 0 {
			break
		}
		remaining = remaining[idx+len(host):]
	}
	return services
}

func xmppPBKDF2(password, salt []byte, iterations, keyLen int, h func() hash.Hash) []byte {
	hashSize := h().Size()
	numBlocks := (keyLen + hashSize - 1) / hashSize
	dk := make([]byte, 0, numBlocks*hashSize)
	for block := 1; block <= numBlocks; block++ {
		blk := []byte{byte(block >> 24), byte(block >> 16), byte(block >> 8), byte(block)}
		mac := hmac.New(h, password)
		mac.Write(salt)
		mac.Write(blk)
		u := mac.Sum(nil)
		result := make([]byte, len(u))
		copy(result, u)
		for i := 1; i < iterations; i++ {
			mac.Reset()
			mac.Write(u)
			u = mac.Sum(u[:0])
			for j := range result {
				result[j] ^= u[j]
			}
		}
		dk = append(dk, result...)
	}
	return dk[:keyLen]
}

func scramEscapeUsername(s string) string {
	s = strings.ReplaceAll(s, "=", "=3D")
	s = strings.ReplaceAll(s, ",", "=2C")
	return s
}

func parseSCRAMParams(s string) map[string]string {
	params := make(map[string]string)
	for _, part := range strings.Split(s, ",") {
		if eq := strings.IndexByte(part, '='); eq > 0 {
			params[part[:eq]] = part[eq+1:]
		}
	}
	return params
}

func hmacHash(hashFunc func() hash.Hash, key, data []byte) []byte {
	h := hmac.New(hashFunc, key)
	h.Write(data)
	return h.Sum(nil)
}

func hashBytes(hashFunc func() hash.Hash, data []byte) []byte {
	h := hashFunc()
	h.Write(data)
	return h.Sum(nil)
}

func xorBytes(a, b []byte) []byte {
	result := make([]byte, len(a))
	for i := range a {
		result[i] = a[i] ^ b[i]
	}
	return result
}

func (c *XMPPCore) buildCapsElement() string {
	c.capsElementOnce.Do(func() {
		features := []string{
			nsDiscoInfo, nsChatState, nsReceipts, nsCorrect,
			nsReactions, nsReply, nsMarkers, nsPing, nsVersion,
		}
		sort.Strings(features)

		h := sha1.New()
		h.Write([]byte("client/pc//Uniclient<"))
		for _, f := range features {
			h.Write([]byte(f))
			h.Write([]byte("<"))
		}
		ver := base64.StdEncoding.EncodeToString(h.Sum(nil))

		c.capsElement = "<c xmlns='" + nsCaps + "' hash='sha-1' node='https://github.com/DarkReaperBoy/uniclient' ver='" + ver + "'/>"
	})
	return c.capsElement
}

func (c *XMPPCore) ModerateMessage(roomJID, stanzaID, reason string) error {
	inner := fmt.Sprintf(
		`<apply-to xmlns='urn:xmpp:fasten:0' id='%s'>`+
			`<moderate xmlns='urn:xmpp:message-moderate:0'>`+
			`<retract xmlns='urn:xmpp:message-retract:0'/>`+
			`<reason>%s</reason></moderate></apply-to>`,
		xmlEscape(stanzaID), xmlEscape(reason))
	return c.sendRawStanza(fmt.Sprintf(
		`<iq type='set' to='%s' id='%s'>%s</iq>`,
		xmlEscape(roomJID), c.nextIQID(), inner))
}

func (c *XMPPCore) ProposeCall(toJID, sessionID string, descriptions string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<message to='%s' type='chat' id='%s'>`+
			`<propose xmlns='urn:xmpp:jingle-message:0' id='%s'>%s</propose></message>`,
		xmlEscape(toJID), c.nextIQID(), xmlEscape(sessionID), descriptions))
}

func (c *XMPPCore) AcceptProposal(toJID, sessionID string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<message to='%s' type='chat' id='%s'>`+
			`<accept xmlns='urn:xmpp:jingle-message:0' id='%s'/></message>`,
		xmlEscape(toJID), c.nextIQID(), xmlEscape(sessionID)))
}

func (c *XMPPCore) RejectProposal(toJID, sessionID string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<message to='%s' type='chat' id='%s'>`+
			`<reject xmlns='urn:xmpp:jingle-message:0' id='%s'/></message>`,
		xmlEscape(toJID), c.nextIQID(), xmlEscape(sessionID)))
}

func (c *XMPPCore) RetractProposal(toJID, sessionID string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<message to='%s' type='chat' id='%s'>`+
			`<retract xmlns='urn:xmpp:jingle-message:0' id='%s'/></message>`,
		xmlEscape(toJID), c.nextIQID(), xmlEscape(sessionID)))
}

func (c *XMPPCore) ProceedToJingle(toJID, sessionID string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<message to='%s' type='chat' id='%s'>`+
			`<proceed xmlns='urn:xmpp:jingle-message:0' id='%s'/></message>`,
		xmlEscape(toJID), c.nextIQID(), xmlEscape(sessionID)))
}

func (c *XMPPCore) JingleContentAdd(toJID, sessionID, contentXML string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<iq type='set' to='%s' id='%s'>`+
			`<jingle xmlns='%s' action='content-add' sid='%s'>%s</jingle></iq>`,
		xmlEscape(toJID), c.nextIQID(), nsJingle, xmlEscape(sessionID), contentXML))
}

func (c *XMPPCore) JingleContentAccept(toJID, sessionID, contentXML string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<iq type='set' to='%s' id='%s'>`+
			`<jingle xmlns='%s' action='content-accept' sid='%s'>%s</jingle></iq>`,
		xmlEscape(toJID), c.nextIQID(), nsJingle, xmlEscape(sessionID), contentXML))
}

func (c *XMPPCore) JingleContentReject(toJID, sessionID, name string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<iq type='set' to='%s' id='%s'>`+
			`<jingle xmlns='%s' action='content-reject' sid='%s'>`+
			`<content creator='initiator' name='%s'/></jingle></iq>`,
		xmlEscape(toJID), c.nextIQID(), nsJingle, xmlEscape(sessionID), xmlEscape(name)))
}

func (c *XMPPCore) JingleContentModify(toJID, sessionID, contentXML string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<iq type='set' to='%s' id='%s'>`+
			`<jingle xmlns='%s' action='content-modify' sid='%s'>%s</jingle></iq>`,
		xmlEscape(toJID), c.nextIQID(), nsJingle, xmlEscape(sessionID), contentXML))
}

func (c *XMPPCore) JingleContentRemove(toJID, sessionID, name string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<iq type='set' to='%s' id='%s'>`+
			`<jingle xmlns='%s' action='content-remove' sid='%s'>`+
			`<content creator='initiator' name='%s'/></jingle></iq>`,
		xmlEscape(toJID), c.nextIQID(), nsJingle, xmlEscape(sessionID), xmlEscape(name)))
}

func (c *XMPPCore) JingleTransportReplace(toJID, sessionID, contentName, transportXML string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<iq type='set' to='%s' id='%s'>`+
			`<jingle xmlns='%s' action='transport-replace' sid='%s'>`+
			`<content creator='initiator' name='%s'>%s</content></jingle></iq>`,
		xmlEscape(toJID), c.nextIQID(), nsJingle, xmlEscape(sessionID),
		xmlEscape(contentName), transportXML))
}

func (c *XMPPCore) JingleTransportAccept(toJID, sessionID, contentName, transportXML string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<iq type='set' to='%s' id='%s'>`+
			`<jingle xmlns='%s' action='transport-accept' sid='%s'>`+
			`<content creator='initiator' name='%s'>%s</content></jingle></iq>`,
		xmlEscape(toJID), c.nextIQID(), nsJingle, xmlEscape(sessionID),
		xmlEscape(contentName), transportXML))
}

func (c *XMPPCore) JingleTransportReject(toJID, sessionID string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<iq type='set' to='%s' id='%s'>`+
			`<jingle xmlns='%s' action='transport-reject' sid='%s'/></iq>`,
		xmlEscape(toJID), c.nextIQID(), nsJingle, xmlEscape(sessionID)))
}

const nsJingleFT = "urn:xmpp:jingle:apps:file-transfer:5"

func (c *XMPPCore) JingleFileOffer(toJID, sessionID, name string, size int64, hash, desc string) error {
	fileXML := fmt.Sprintf(
		`<file xmlns='%s'><name>%s</name><size>%d</size>`,
		nsJingleFT, xmlEscape(name), size)
	if hash != "" {
		fileXML += fmt.Sprintf(`<hash xmlns='urn:xmpp:hashes:2' algo='sha-256'>%s</hash>`, xmlEscape(hash))
	}
	if desc != "" {
		fileXML += fmt.Sprintf(`<desc>%s</desc>`, xmlEscape(desc))
	}
	fileXML += `</file>`

	return c.sendRawStanza(fmt.Sprintf(
		`<iq type='set' to='%s' id='%s'>`+
			`<jingle xmlns='%s' action='session-initiate' sid='%s' initiator='%s'>`+
			`<content creator='initiator' name='file'>`+
			`<description xmlns='%s'>%s</description>`+
			`<transport xmlns='%s'/>`+
			`</content></jingle></iq>`,
		xmlEscape(toJID), c.nextIQID(), nsJingle, xmlEscape(sessionID),
		xmlEscape(c.jid), nsJingleFT, fileXML, nsJingleICE))
}

func (c *XMPPCore) JingleFileRequest(toJID, sessionID, name string, size int64) error {
	return c.JingleFileOffer(toJID, sessionID, name, size, "", "")
}

func (c *XMPPCore) JingleFileChecksum(toJID, sessionID, algo, hash string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<iq type='set' to='%s' id='%s'>`+
			`<jingle xmlns='%s' action='session-info' sid='%s'>`+
			`<checksum xmlns='%s'><file>`+
			`<hash xmlns='urn:xmpp:hashes:2' algo='%s'>%s</hash>`+
			`</file></checksum></jingle></iq>`,
		xmlEscape(toJID), c.nextIQID(), nsJingle, xmlEscape(sessionID),
		nsJingleFT, xmlEscape(algo), xmlEscape(hash)))
}

func (c *XMPPCore) JingleFileReceived(toJID, sessionID string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<iq type='set' to='%s' id='%s'>`+
			`<jingle xmlns='%s' action='session-info' sid='%s'>`+
			`<received xmlns='%s'/></jingle></iq>`,
		xmlEscape(toJID), c.nextIQID(), nsJingle, xmlEscape(sessionID), nsJingleFT))
}

func (c *XMPPCore) JingleFileResume(toJID, sessionID string, offset int64) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<iq type='set' to='%s' id='%s'>`+
			`<jingle xmlns='%s' action='session-info' sid='%s'>`+
			`<range xmlns='%s' offset='%d'/></jingle></iq>`,
		xmlEscape(toJID), c.nextIQID(), nsJingle, xmlEscape(sessionID), nsJingleFT, offset))
}

func (c *XMPPCore) NegotiateRTCPFeedback(toJID, sessionID, contentName string, fbTypes []string) error {
	fb := ""
	for _, t := range fbTypes {
		fb += fmt.Sprintf(`<rtcp-fb xmlns='urn:xmpp:jingle:apps:rtp:rtcp-fb:0' type='%s'/>`, xmlEscape(t))
	}
	return c.JingleContentModify(toJID, sessionID,
		fmt.Sprintf(`<content creator='initiator' name='%s'><description xmlns='%s'>%s</description></content>`,
			xmlEscape(contentName), nsJingleRTP, fb))
}

func (c *XMPPCore) NegotiateRTPHeaderExtensions(toJID, sessionID, contentName string, extensions []string) error {
	ext := ""
	for i, uri := range extensions {
		ext += fmt.Sprintf(`<rtp-hdrext xmlns='urn:xmpp:jingle:apps:rtp:rtp-hdrext:0' id='%d' uri='%s'/>`, i+1, xmlEscape(uri))
	}
	return c.JingleContentModify(toJID, sessionID,
		fmt.Sprintf(`<content creator='initiator' name='%s'><description xmlns='%s'>%s</description></content>`,
			xmlEscape(contentName), nsJingleRTP, ext))
}

const nsOMEMO = "urn:xmpp:omemo:2"

func (c *XMPPCore) PublishOMEMODeviceList(deviceIDs []int) error {
	items := ""
	for _, id := range deviceIDs {
		items += fmt.Sprintf(`<device id='%d'/>`, id)
	}
	payload := fmt.Sprintf(`<devices xmlns='%s'>%s</devices>`, nsOMEMO, items)
	return c.PublishPubSubItem("", nsOMEMO+":devices", "current", payload)
}

func (c *XMPPCore) FetchOMEMODeviceList(jid string) (*XMPPIQ, error) {
	return c.GetPubSubItems(jid, nsOMEMO+":devices")
}

func (c *XMPPCore) PublishOMEMOBundle(deviceID int, bundleXML string) error {
	return c.PublishPubSubItem("", fmt.Sprintf("%s:bundles:%d", nsOMEMO, deviceID),
		"current", bundleXML)
}

func (c *XMPPCore) FetchOMEMOBundle(jid string, deviceID int) (*XMPPIQ, error) {
	return c.GetPubSubItems(jid, fmt.Sprintf("%s:bundles:%d", nsOMEMO, deviceID))
}

func (c *XMPPCore) OMEMOEncrypt(payload []byte, recipientKeys []map[string]string) (string, error) {
	encoded := base64.StdEncoding.EncodeToString(payload)
	keys := ""
	for _, k := range recipientKeys {
		keys += fmt.Sprintf(`<key rid='%s' prekey='%s'>%s</key>`,
			k["rid"], k["prekey"], k["data"])
	}
	return fmt.Sprintf(
		`<encrypted xmlns='%s'><header sid='%s'>%s<iv>%s</iv></header>`+
			`<payload>%s</payload></encrypted>`,
		nsOMEMO, c.bareJID, keys, "", encoded), nil
}

func (c *XMPPCore) OMEMODecrypt(encryptedXML string, sessionKey []byte) ([]byte, error) {
	start := strings.Index(encryptedXML, "<payload>")
	end := strings.Index(encryptedXML, "</payload>")
	if start < 0 || end < 0 {
		return nil, fmt.Errorf("no payload in OMEMO message")
	}
	encoded := encryptedXML[start+9 : end]
	return base64.StdEncoding.DecodeString(encoded)
}

func (c *XMPPCore) OMEMOBuildSession(jid string, deviceID int) error {
	_, err := c.FetchOMEMOBundle(jid, deviceID)
	return err
}

const nsMIX = "urn:xmpp:mix:core:1"

func (c *XMPPCore) JoinMIXChannel(channelJID, nick string, subscriptions []string) error {
	subs := ""
	for _, s := range subscriptions {
		subs += fmt.Sprintf(`<subscribe node='%s'/>`, xmlEscape(s))
	}
	inner := fmt.Sprintf(
		`<join xmlns='%s' channel='%s'><nick>%s</nick>%s</join>`,
		nsMIX, xmlEscape(channelJID), xmlEscape(nick), subs)
	_, err := c.sendIQSync("set", channelJID, inner)
	return err
}

func (c *XMPPCore) LeaveMIXChannel(channelJID string) error {
	inner := fmt.Sprintf(`<leave xmlns='%s' channel='%s'/>`, nsMIX, xmlEscape(channelJID))
	_, err := c.sendIQSync("set", channelJID, inner)
	return err
}

func (c *XMPPCore) SetMIXNick(channelJID, nick string) error {
	inner := fmt.Sprintf(`<setnick xmlns='%s'><nick>%s</nick></setnick>`, nsMIX, xmlEscape(nick))
	_, err := c.sendIQSync("set", channelJID, inner)
	return err
}

func (c *XMPPCore) UpdateMIXSubscriptions(channelJID string, subscribe, unsubscribe []string) error {
	subs := ""
	for _, s := range subscribe {
		subs += fmt.Sprintf(`<subscribe node='%s'/>`, xmlEscape(s))
	}
	for _, s := range unsubscribe {
		subs += fmt.Sprintf(`<unsubscribe node='%s'/>`, xmlEscape(s))
	}
	inner := fmt.Sprintf(`<update-subscription xmlns='%s'>%s</update-subscription>`, nsMIX, subs)
	_, err := c.sendIQSync("set", channelJID, inner)
	return err
}

func (c *XMPPCore) CreateMIXChannel(serviceJID, channelName string) error {
	inner := fmt.Sprintf(`<create xmlns='%s' channel='%s'/>`, nsMIX, xmlEscape(channelName))
	_, err := c.sendIQSync("set", serviceJID, inner)
	return err
}

func (c *XMPPCore) DestroyMIXChannel(channelJID string) error {
	inner := fmt.Sprintf(`<destroy xmlns='%s' channel='%s'/>`, nsMIX, xmlEscape(channelJID))
	_, err := c.sendIQSync("set", channelJID, inner)
	return err
}

func (c *XMPPCore) EnablePushNotifications(pushServiceJID, node string, publishOptions map[string]string) error {
	opts := ""
	if len(publishOptions) > 0 {
		fields := ""
		for k, v := range publishOptions {
			fields += fmt.Sprintf(`<field var='%s'><value>%s</value></field>`, xmlEscape(k), xmlEscape(v))
		}
		opts = fmt.Sprintf(`<publish-options><x xmlns='%s' type='submit'>%s</x></publish-options>`, nsXData, fields)
	}
	inner := fmt.Sprintf(
		`<enable xmlns='urn:xmpp:push:0' jid='%s' node='%s'>%s</enable>`,
		xmlEscape(pushServiceJID), xmlEscape(node), opts)
	_, err := c.sendIQSync("set", c.domain, inner)
	return err
}

func (c *XMPPCore) DisablePushNotifications(pushServiceJID, node string) error {
	inner := fmt.Sprintf(
		`<disable xmlns='urn:xmpp:push:0' jid='%s' node='%s'/>`,
		xmlEscape(pushServiceJID), xmlEscape(node))
	_, err := c.sendIQSync("set", c.domain, inner)
	return err
}

const nsCommands = "http://jabber.org/protocol/commands"

func (c *XMPPCore) DiscoverCommands(serviceJID string) (*XMPPIQ, error) {
	inner := fmt.Sprintf(`<query xmlns='%s' node='%s'/>`, nsDiscoItem, nsCommands)
	return c.sendIQSync("get", serviceJID, inner)
}

func (c *XMPPCore) ExecuteCommand(serviceJID, node, sessionID, action, formXML string) (*XMPPIQ, error) {
	attrs := fmt.Sprintf(` xmlns='%s' node='%s'`, nsCommands, xmlEscape(node))
	if sessionID != "" {
		attrs += fmt.Sprintf(` sessionid='%s'`, xmlEscape(sessionID))
	}
	if action != "" {
		attrs += fmt.Sprintf(` action='%s'`, xmlEscape(action))
	} else {
		attrs += ` action='execute'`
	}
	inner := fmt.Sprintf(`<command%s>%s</command>`, attrs, formXML)
	return c.sendIQSync("set", serviceJID, inner)
}

func (c *XMPPCore) CancelCommand(serviceJID, node, sessionID string) error {
	inner := fmt.Sprintf(
		`<command xmlns='%s' node='%s' sessionid='%s' action='cancel'/>`,
		nsCommands, xmlEscape(node), xmlEscape(sessionID))
	_, err := c.sendIQSync("set", serviceJID, inner)
	return err
}

const nsPrivacyLists = "jabber:iq:privacy"

func (c *XMPPCore) GetPrivacyLists() (*XMPPIQ, error) {
	inner := fmt.Sprintf(`<query xmlns='%s'/>`, nsPrivacyLists)
	return c.sendIQSync("get", "", inner)
}

func (c *XMPPCore) SetActiveList(name string) error {
	inner := fmt.Sprintf(`<query xmlns='%s'><active name='%s'/></query>`, nsPrivacyLists, xmlEscape(name))
	_, err := c.sendIQSync("set", "", inner)
	return err
}

func (c *XMPPCore) SetDefaultList(name string) error {
	inner := fmt.Sprintf(`<query xmlns='%s'><default name='%s'/></query>`, nsPrivacyLists, xmlEscape(name))
	_, err := c.sendIQSync("set", "", inner)
	return err
}

const nsOffline = "http://jabber.org/protocol/offline"

func (c *XMPPCore) GetOfflineMessageCount() (*XMPPIQ, error) {
	inner := fmt.Sprintf(`<query xmlns='%s'/>`, nsDiscoInfo)
	return c.sendIQSync("get", c.domain, inner)
}

func (c *XMPPCore) GetOfflineMessageHeaders() (*XMPPIQ, error) {
	inner := fmt.Sprintf(`<query xmlns='%s' node='%s'/>`, nsDiscoItem, nsOffline)
	return c.sendIQSync("get", "", inner)
}

func (c *XMPPCore) RetrieveOfflineMessages(nodeIDs []string) (*XMPPIQ, error) {
	items := ""
	for _, id := range nodeIDs {
		items += fmt.Sprintf(`<item action='view' node='%s'/>`, xmlEscape(id))
	}
	inner := fmt.Sprintf(`<offline xmlns='%s'>%s</offline>`, nsOffline, items)
	return c.sendIQSync("get", "", inner)
}

func (c *XMPPCore) RemoveOfflineMessages(nodeIDs []string) error {
	items := ""
	for _, id := range nodeIDs {
		items += fmt.Sprintf(`<item action='remove' node='%s'/>`, xmlEscape(id))
	}
	inner := fmt.Sprintf(`<offline xmlns='%s'>%s</offline>`, nsOffline, items)
	_, err := c.sendIQSync("set", "", inner)
	return err
}

func (c *XMPPCore) EncryptStanzaContent(payload, rpad string) string {
	return fmt.Sprintf(
		`<envelope xmlns='urn:xmpp:sce:1'>`+
			`<content>%s</content>`+
			`<rpad>%s</rpad>`+
			`<from jid='%s'/>`+
			`<time stamp='%s'/>`+
			`</envelope>`,
		payload, rpad, xmlEscape(c.bareJID),
		time.Now().UTC().Format("2006-01-02T15:04:05Z"))
}

func (c *XMPPCore) DecryptStanzaContent(envelopeXML string) (string, error) {
	start := strings.Index(envelopeXML, "<content>")
	end := strings.Index(envelopeXML, "</content>")
	if start < 0 || end < 0 {
		return "", fmt.Errorf("no content in SCE envelope")
	}
	return envelopeXML[start+9 : end], nil
}

func (c *XMPPCore) SASL2Authenticate(mechanism, initialResponse string, inlineFeatures string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<authenticate xmlns='urn:xmpp:sasl:2' mechanism='%s'>`+
			`<initial-response>%s</initial-response>%s</authenticate>`,
		xmlEscape(mechanism), initialResponse, inlineFeatures))
}

func (c *XMPPCore) Bind2(tag string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<bind xmlns='urn:xmpp:bind:0'><tag>%s</tag></bind>`, xmlEscape(tag)))
}

func (c *XMPPCore) FASTReconnect(token, mechanism string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<authenticate xmlns='urn:xmpp:sasl:2' mechanism='%s'>`+
			`<initial-response>%s</initial-response>`+
			`<fast xmlns='urn:xmpp:fast:0'/></authenticate>`,
		xmlEscape(mechanism), token))
}

func (c *XMPPCore) SubmitForm(toJID, formXML string) error {
	_, err := c.sendIQSync("set", toJID,
		fmt.Sprintf(`<x xmlns='%s' type='submit'>%s</x>`, nsXData, formXML))
	return err
}

func (c *XMPPCore) CancelForm(toJID, formXML string) error {
	_, err := c.sendIQSync("set", toJID,
		fmt.Sprintf(`<x xmlns='%s' type='cancel'>%s</x>`, nsXData, formXML))
	return err
}

func (c *XMPPCore) ProcessFormResult(formXML string) map[string]string {
	result := make(map[string]string)
	for _, field := range strings.Split(formXML, "<field ") {
		if !strings.Contains(field, "var=") {
			continue
		}
		varStart := strings.Index(field, "var='") + 5
		if varStart < 5 {
			continue
		}
		varEnd := strings.Index(field[varStart:], "'")
		if varEnd < 0 {
			continue
		}
		key := field[varStart : varStart+varEnd]
		valStart := strings.Index(field, "<value>")
		valEnd := strings.Index(field, "</value>")
		if valStart >= 0 && valEnd > valStart {
			result[key] = field[valStart+7 : valEnd]
		}
	}
	return result
}

func (c *XMPPCore) StorePrivateXML(innerXML string) error {
	inner := fmt.Sprintf(`<query xmlns='%s'>%s</query>`, nsPrivate, innerXML)
	_, err := c.sendIQSync("set", "", inner)
	return err
}

func (c *XMPPCore) RetrievePrivateXML(namespace, element string) (*XMPPIQ, error) {
	inner := fmt.Sprintf(`<query xmlns='%s'><%s xmlns='%s'/></query>`,
		nsPrivate, xmlEscape(element), xmlEscape(namespace))
	return c.sendIQSync("get", "", inner)
}

func (c *XMPPCore) SetBookmarkPEP(roomJID, name, nick string, autoJoin bool) error {
	aj := "false"
	if autoJoin {
		aj = "true"
	}
	payload := fmt.Sprintf(
		`<conference xmlns='%s' name='%s' autojoin='%s'><nick>%s</nick></conference>`,
		nsBmk2, xmlEscape(name), aj, xmlEscape(nick))
	return c.PublishPubSubItem("", nsBmk2, roomJID, payload)
}

func (c *XMPPCore) RemoveBookmarkPEP(roomJID string) error {
	return c.RetractPubSubItem("", nsBmk2, roomJID)
}

const nsSFS = "urn:xmpp:sfs:0"

func (c *XMPPCore) ShareFileMetadata(toJID, name, mediaType string, size int64, hash string) error {
	msgType := "chat"
	if c.isRoom(toJID) {
		msgType = "groupchat"
	}
	return c.sendRawStanza(fmt.Sprintf(
		`<message to='%s' type='%s' id='%s'>`+
			`<file-sharing xmlns='%s'><file><media-type>%s</media-type>`+
			`<name>%s</name><size>%d</size>`+
			`<hash xmlns='urn:xmpp:hashes:2' algo='sha-256'>%s</hash>`+
			`</file></file-sharing></message>`,
		xmlEscape(toJID), msgType, c.nextIQID(), nsSFS,
		xmlEscape(mediaType), xmlEscape(name), size, xmlEscape(hash)))
}

func (c *XMPPCore) ShareFileSources(toJID string, urls []string) error {
	msgType := "chat"
	if c.isRoom(toJID) {
		msgType = "groupchat"
	}
	sources := ""
	for _, u := range urls {
		sources += fmt.Sprintf(`<url-data xmlns='http://jabber.org/protocol/url-data' target='%s'/>`, xmlEscape(u))
	}
	return c.sendRawStanza(fmt.Sprintf(
		`<message to='%s' type='%s' id='%s'>`+
			`<sources xmlns='%s'>%s</sources></message>`,
		xmlEscape(toJID), msgType, c.nextIQID(), nsSFS, sources))
}

const nsVCard4 = "urn:ietf:params:xml:ns:vcard-4.0"

func (c *XMPPCore) GetVCard4(jid string) (*XMPPIQ, error) {
	return c.GetPubSubItems(jid, nsVCard4)
}

func (c *XMPPCore) SetVCard4(vcardXML string) error {
	return c.PublishPubSubItem("", nsVCard4, "current", vcardXML)
}

func (c *XMPPCore) VerifyHTTPRequest(toJID, confirmID, method, url string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<iq type='result' to='%s' id='%s'>`+
			`<confirm xmlns='http://jabber.org/protocol/http-auth' id='%s' method='%s' url='%s'/></iq>`,
		xmlEscape(toJID), xmlEscape(confirmID), xmlEscape(confirmID),
		xmlEscape(method), xmlEscape(url)))
}

func (c *XMPPCore) SendMessageReference(toJID, text, refType, refURI string) error {
	msgType := "chat"
	if c.isRoom(toJID) {
		msgType = "groupchat"
	}
	return c.sendRawStanza(fmt.Sprintf(
		`<message to='%s' type='%s' id='%s'>`+
			`<body>%s</body>`+
			`<reference xmlns='urn:xmpp:reference:0' type='%s' uri='%s'/></message>`,
		xmlEscape(toJID), msgType, c.nextIQID(),
		xmlEscape(text), xmlEscape(refType), xmlEscape(refURI)))
}

func (c *XMPPCore) SendRichTextMessage(toJID, plainText, xhtmlBody string) error {
	msgType := "chat"
	if c.isRoom(toJID) {
		msgType = "groupchat"
	}
	return c.sendRawStanza(fmt.Sprintf(
		`<message to='%s' type='%s' id='%s'>`+
			`<body>%s</body>`+
			`<html xmlns='http://jabber.org/protocol/xhtml-im'>`+
			`<body xmlns='http://www.w3.org/1999/xhtml'>%s</body></html></message>`,
		xmlEscape(toJID), msgType, c.nextIQID(),
		xmlEscape(plainText), xhtmlBody))
}

func (c *XMPPCore) HandleOccupantId(stanzaXML string) string {
	start := strings.Index(stanzaXML, `<occupant-id xmlns='urn:xmpp:occupant-id:0' id='`)
	if start < 0 {
		return ""
	}
	rest := stanzaXML[start+48:]
	end := strings.Index(rest, "'")
	if end < 0 {
		return ""
	}
	return rest[:end]
}

func (c *XMPPCore) GetMAMPreferences() (*XMPPIQ, error) {
	inner := fmt.Sprintf(`<prefs xmlns='%s'/>`, nsMAM)
	return c.sendIQSync("get", "", inner)
}

func (c *XMPPCore) SetMAMPreferences(defaultPolicy string, alwaysJIDs, neverJIDs []string) error {
	always := ""
	if len(alwaysJIDs) > 0 {
		for _, j := range alwaysJIDs {
			always += fmt.Sprintf(`<jid>%s</jid>`, xmlEscape(j))
		}
		always = "<always>" + always + "</always>"
	}
	never := ""
	if len(neverJIDs) > 0 {
		for _, j := range neverJIDs {
			never += fmt.Sprintf(`<jid>%s</jid>`, xmlEscape(j))
		}
		never = "<never>" + never + "</never>"
	}
	inner := fmt.Sprintf(`<prefs xmlns='%s' default='%s'>%s%s</prefs>`,
		nsMAM, xmlEscape(defaultPolicy), always, never)
	_, err := c.sendIQSync("set", "", inner)
	return err
}

func (c *XMPPCore) PurgeNode(service, node string) error {
	if service == "" {
		service = c.domain
	}
	inner := fmt.Sprintf(`<pubsub xmlns='%s'><purge node='%s'/></pubsub>`, nsPubOwner, xmlEscape(node))
	_, err := c.sendIQSync("set", service, inner)
	return err
}

func (c *XMPPCore) GetNodeAffiliations(service, node string) (*XMPPIQ, error) {
	if service == "" {
		service = c.domain
	}
	inner := fmt.Sprintf(`<pubsub xmlns='%s'><affiliations node='%s'/></pubsub>`, nsPubOwner, xmlEscape(node))
	return c.sendIQSync("get", service, inner)
}

func (c *XMPPCore) SetNodeAffiliation(service, node, jid, affiliation string) error {
	if service == "" {
		service = c.domain
	}
	inner := fmt.Sprintf(
		`<pubsub xmlns='%s'><affiliations node='%s'>`+
			`<affiliation jid='%s' affiliation='%s'/></affiliations></pubsub>`,
		nsPubOwner, xmlEscape(node), xmlEscape(jid), xmlEscape(affiliation))
	_, err := c.sendIQSync("set", service, inner)
	return err
}

func (c *XMPPCore) GetNodeSubscribers(service, node string) (*XMPPIQ, error) {
	if service == "" {
		service = c.domain
	}
	inner := fmt.Sprintf(`<pubsub xmlns='%s'><subscriptions node='%s'/></pubsub>`, nsPubOwner, xmlEscape(node))
	return c.sendIQSync("get", service, inner)
}

func (c *XMPPCore) SearchUsersXMPP(serviceJID, formXML string) (*XMPPIQ, error) {
	inner := fmt.Sprintf(`<query xmlns='jabber:iq:search'>%s</query>`, formXML)
	return c.sendIQSync("set", serviceJID, inner)
}

const nsIBB = "http://jabber.org/protocol/ibb"

func (c *XMPPCore) OpenIBBSession(toJID, sid string, blockSize int) error {
	inner := fmt.Sprintf(`<open xmlns='%s' sid='%s' block-size='%d' stanza='iq'/>`,
		nsIBB, xmlEscape(sid), blockSize)
	_, err := c.sendIQSync("set", toJID, inner)
	return err
}

func (c *XMPPCore) SendIBBData(toJID, sid string, seq int, data []byte) error {
	encoded := base64.StdEncoding.EncodeToString(data)
	inner := fmt.Sprintf(`<data xmlns='%s' sid='%s' seq='%d'>%s</data>`,
		nsIBB, xmlEscape(sid), seq, encoded)
	_, err := c.sendIQSync("set", toJID, inner)
	return err
}

func (c *XMPPCore) CloseIBBSession(toJID, sid string) error {
	inner := fmt.Sprintf(`<close xmlns='%s' sid='%s'/>`, nsIBB, xmlEscape(sid))
	_, err := c.sendIQSync("set", toJID, inner)
	return err
}

const nsS5B = "http://jabber.org/protocol/bytestreams"

func (c *XMPPCore) InitiateS5B(toJID, sid string, streamHosts []map[string]string) error {
	hosts := ""
	for _, h := range streamHosts {
		hosts += fmt.Sprintf(`<streamhost jid='%s' host='%s' port='%s'/>`,
			xmlEscape(h["jid"]), xmlEscape(h["host"]), xmlEscape(h["port"]))
	}
	inner := fmt.Sprintf(`<query xmlns='%s' sid='%s'>%s</query>`,
		nsS5B, xmlEscape(sid), hosts)
	_, err := c.sendIQSync("set", toJID, inner)
	return err
}

func (c *XMPPCore) ActivateS5B(proxyJID, sid, targetJID string) error {
	inner := fmt.Sprintf(`<query xmlns='%s' sid='%s'><activate>%s</activate></query>`,
		nsS5B, xmlEscape(sid), xmlEscape(targetJID))
	_, err := c.sendIQSync("set", proxyJID, inner)
	return err
}

func (c *XMPPCore) RequestMUCVoice(roomJID string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<message to='%s'>`+
			`<x xmlns='%s' type='submit'>`+
			`<field var='FORM_TYPE'><value>http://jabber.org/protocol/muc#request</value></field>`+
			`<field var='muc#role'><value>participant</value></field>`+
			`</x></message>`,
		xmlEscape(roomJID), nsXData))
}

const nsNick = "http://jabber.org/protocol/nick"

func (c *XMPPCore) SetUserNickname(nick string) error {
	payload := fmt.Sprintf(`<nick xmlns='%s'>%s</nick>`, nsNick, xmlEscape(nick))
	return c.PublishPubSubItem("", nsNick, "current", payload)
}

func (c *XMPPCore) GetUserNickname(jid string) (*XMPPIQ, error) {
	return c.GetPubSubItems(jid, nsNick)
}

const nsOX = "urn:xmpp:openpgp:0"

func (c *XMPPCore) PublishOXPublicKey(fingerprint string, pubKeyB64 string) error {
	payload := fmt.Sprintf(`<pubkey xmlns='%s'><data>%s</data></pubkey>`, nsOX, pubKeyB64)
	return c.PublishPubSubItem("", nsOX+":public-keys:"+fingerprint, "current", payload)
}

func (c *XMPPCore) FetchOXPublicKey(jid, fingerprint string) (*XMPPIQ, error) {
	return c.GetPubSubItems(jid, nsOX+":public-keys:"+fingerprint)
}

func (c *XMPPCore) OXEncrypt(payload string) string {
	return fmt.Sprintf(
		`<signcrypt xmlns='%s'>`+
			`<to jid='%s'/>`+
			`<time stamp='%s'/>`+
			`<rpad>%s</rpad>`+
			`<payload>%s</payload></signcrypt>`,
		nsOX, xmlEscape(c.bareJID),
		time.Now().UTC().Format("2006-01-02T15:04:05Z"),
		generateShortID(), payload)
}

func (c *XMPPCore) OXDecrypt(signcryptXML string) (string, error) {
	start := strings.Index(signcryptXML, "<payload>")
	end := strings.Index(signcryptXML, "</payload>")
	if start < 0 || end < 0 {
		return "", fmt.Errorf("no payload in OX element")
	}
	return signcryptXML[start+9 : end], nil
}

func (c *XMPPCore) OXSignEncrypt(toJID, payload, openpgpB64 string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<message to='%s' type='chat' id='%s'>`+
			`<openpgp xmlns='%s'>%s</openpgp>`+
			`<body>This message is encrypted.</body>`+
			`<encryption xmlns='urn:xmpp:eme:0' namespace='%s'/></message>`,
		xmlEscape(toJID), c.nextIQID(), nsOX, openpgpB64, nsOX))
}

func (c *XMPPCore) SetEncryptionHint(namespace, name string) string {
	if name != "" {
		return fmt.Sprintf(`<encryption xmlns='urn:xmpp:eme:0' namespace='%s' name='%s'/>`,
			xmlEscape(namespace), xmlEscape(name))
	}
	return fmt.Sprintf(`<encryption xmlns='urn:xmpp:eme:0' namespace='%s'/>`, xmlEscape(namespace))
}

func (c *XMPPCore) GetLastUserInteraction(jid string) (*XMPPIQ, error) {
	inner := fmt.Sprintf(`<query xmlns='%s'/>`, nsLast)
	return c.sendIQSync("get", jid, inner)
}

func (c *XMPPCore) SetAMPRules(rules []map[string]string) string {
	ruleXML := ""
	for _, r := range rules {
		ruleXML += fmt.Sprintf(`<rule condition='%s' action='%s' value='%s'/>`,
			xmlEscape(r["condition"]), xmlEscape(r["action"]), xmlEscape(r["value"]))
	}
	return fmt.Sprintf(`<amp xmlns='http://jabber.org/protocol/amp'>%s</amp>`, ruleXML)
}

const nsStickers = "urn:xmpp:stickers:0"

func (c *XMPPCore) GetStickerPack(serviceJID, node string) (*XMPPIQ, error) {
	return c.GetPubSubItems(serviceJID, node)
}

func (c *XMPPCore) SendStickerXEP(toJID, stickerPackNode, stickerHash, fallbackBody string) error {
	msgType := "chat"
	if c.isRoom(toJID) {
		msgType = "groupchat"
	}
	return c.sendRawStanza(fmt.Sprintf(
		`<message to='%s' type='%s' id='%s'>`+
			`<body>%s</body>`+
			`<sticker xmlns='%s' pack='%s' hash='%s'/></message>`,
		xmlEscape(toJID), msgType, c.nextIQID(),
		xmlEscape(fallbackBody), nsStickers, xmlEscape(stickerPackNode), xmlEscape(stickerHash)))
}

func (c *XMPPCore) ShareEncryptedFile(toJID, name, mediaType string, size int64, ivB64, keyB64, url string) error {
	msgType := "chat"
	if c.isRoom(toJID) {
		msgType = "groupchat"
	}
	return c.sendRawStanza(fmt.Sprintf(
		`<message to='%s' type='%s' id='%s'>`+
			`<file-sharing xmlns='%s'>`+
			`<file><media-type>%s</media-type><name>%s</name><size>%d</size></file>`+
			`<sources><url-data xmlns='http://jabber.org/protocol/url-data' target='%s'/></sources>`+
			`</file-sharing>`+
			`<encryption xmlns='urn:xmpp:eme:0' namespace='urn:xmpp:crypt:0'/></message>`,
		xmlEscape(toJID), msgType, c.nextIQID(), nsSFS,
		xmlEscape(mediaType), xmlEscape(name), size, xmlEscape(url)))
}

func (c *XMPPCore) EncryptMedia(plaintext []byte) ([]byte, string, string, error) {
	key := make([]byte, 32)
	if _, err := rand.Read(key); err != nil {
		return nil, "", "", fmt.Errorf("generate key: %w", err)
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, "", "", fmt.Errorf("aes cipher: %w", err)
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, "", "", fmt.Errorf("gcm: %w", err)
	}
	iv := make([]byte, gcm.NonceSize())
	if _, err := rand.Read(iv); err != nil {
		return nil, "", "", fmt.Errorf("generate iv: %w", err)
	}
	ct := gcm.Seal(nil, iv, plaintext, nil)
	return ct, base64.StdEncoding.EncodeToString(iv), base64.StdEncoding.EncodeToString(key), nil
}

func (c *XMPPCore) DecryptMedia(ciphertext []byte, ivB64, keyB64 string) ([]byte, error) {
	key, err := base64.StdEncoding.DecodeString(keyB64)
	if err != nil {
		return nil, fmt.Errorf("decode key: %w", err)
	}
	iv, err := base64.StdEncoding.DecodeString(ivB64)
	if err != nil {
		return nil, fmt.Errorf("decode iv: %w", err)
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, fmt.Errorf("aes cipher: %w", err)
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, fmt.Errorf("gcm: %w", err)
	}
	return gcm.Open(nil, iv, ciphertext, nil)
}

func (c *XMPPCore) SendTrustMessage(toJID, encryptionNS string, trustedKeys, distrustedKeys []string) error {
	trustXML := ""
	for _, k := range trustedKeys {
		trustXML += fmt.Sprintf("<key-owner jid='%s'><trust>%s</trust></key-owner>", xmlEscape(toJID), xmlEscape(k))
	}
	distrustXML := ""
	for _, k := range distrustedKeys {
		distrustXML += fmt.Sprintf("<key-owner jid='%s'><distrust>%s</distrust></key-owner>", xmlEscape(toJID), xmlEscape(k))
	}
	return c.sendRawStanza(fmt.Sprintf(
		`<message to='%s' type='chat' id='%s'>`+
			`<trust-message xmlns='urn:xmpp:tm:1' usage='urn:xmpp:atm:1' encryption='%s'>`+
			`%s%s</trust-message></message>`,
		xmlEscape(toJID), c.nextIQID(), xmlEscape(encryptionNS), trustXML, distrustXML))
}

func (c *XMPPCore) SyncDisplayedMessages(jid, stanzaID string) error {
	return c.PublishPubSubItem(c.bareJID, "urn:xmpp:mds:displayed:0", jid,
		fmt.Sprintf(
			`<displayed xmlns='urn:xmpp:mds:displayed:0' jid='%s'>`+
				`<stanza-id xmlns='urn:xmpp:sid:0' id='%s'/></displayed>`,
			xmlEscape(jid), xmlEscape(stanzaID)))
}

func (c *XMPPCore) SetFallbackIndication(forNS string) string {
	return fmt.Sprintf(`<fallback xmlns='urn:xmpp:fallback:0' for='%s'/>`, xmlEscape(forNS))
}

func (c *XMPPCore) NegotiateChannelBinding(bindingType string) string {
	return fmt.Sprintf(`<sasl-channel-binding xmlns='urn:xmpp:sasl-cb:0'><channel-binding type='%s'/></sasl-channel-binding>`,
		xmlEscape(bindingType))
}

func (c *XMPPCore) DiscoverAlternativeConnections(domain string) (wsURL, boshURL string, err error) {
	url := "https://" + domain + "/.well-known/host-meta"
	resp, err := ApiHTTPClient.Get(url)
	if err != nil {
		return "", "", fmt.Errorf("fetch host-meta: %w", err)
	}
	defer resp.Body.Close()
	body, err := ReadBodyCapped(resp.Body, ApiBodyCeiling)
	if err != nil {
		return "", "", fmt.Errorf("read host-meta: %w", err)
	}
	s := string(body)
	for _, line := range strings.Split(s, "\n") {
		if strings.Contains(line, "urn:xmpp:alt-connections:websocket") {
			if i := strings.Index(line, "href='"); i >= 0 {
				rest := line[i+6:]
				if j := strings.Index(rest, "'"); j >= 0 {
					wsURL = rest[:j]
				}
			} else if i := strings.Index(line, `href="`); i >= 0 {
				rest := line[i+6:]
				if j := strings.Index(rest, `"`); j >= 0 {
					wsURL = rest[:j]
				}
			}
		}
		if strings.Contains(line, "urn:xmpp:alt-connections:xbosh") {
			if i := strings.Index(line, "href='"); i >= 0 {
				rest := line[i+6:]
				if j := strings.Index(rest, "'"); j >= 0 {
					boshURL = rest[:j]
				}
			} else if i := strings.Index(line, `href="`); i >= 0 {
				rest := line[i+6:]
				if j := strings.Index(rest, `"`); j >= 0 {
					boshURL = rest[:j]
				}
			}
		}
	}
	return wsURL, boshURL, nil
}

func (c *XMPPCore) ConnectWebSocket(wsURL string) error {
	dialer := &net.Dialer{Timeout: 10 * time.Second}
	conn, err := tls.DialWithDialer(dialer, "tcp", wsURL, &tls.Config{InsecureSkipVerify: false})
	if err != nil {
		return fmt.Errorf("websocket dial: %w", err)
	}
	host := wsURL
	path := "/"
	if i := strings.Index(wsURL, "://"); i >= 0 {
		rest := wsURL[i+3:]
		if j := strings.Index(rest, "/"); j >= 0 {
			host = rest[:j]
			path = rest[j:]
		} else {
			host = rest
		}
	}
	keyBytes := make([]byte, 16)
	rand.Read(keyBytes)
	wsKey := base64.StdEncoding.EncodeToString(keyBytes)
	upgrade := fmt.Sprintf("GET %s HTTP/1.1\r\nHost: %s\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: %s\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Protocol: xmpp\r\n\r\n",
		path, host, wsKey)
	if _, err := conn.Write([]byte(upgrade)); err != nil {
		conn.Close()
		return fmt.Errorf("websocket upgrade write: %w", err)
	}
	buf := make([]byte, 4096)
	n, err := conn.Read(buf)
	if err != nil {
		conn.Close()
		return fmt.Errorf("websocket upgrade read: %w", err)
	}
	if !strings.Contains(string(buf[:n]), "101") {
		conn.Close()
		return fmt.Errorf("websocket upgrade failed: %s", string(buf[:n]))
	}
	c.mu.Lock()
	if c.conn != nil {
		c.conn.Close()
	}
	c.conn = conn
	c.mu.Unlock()
	return nil
}

func (c *XMPPCore) ConnectBOSH(boshURL, domain string) (string, error) {
	body := fmt.Sprintf(
		`<body xmlns='http://jabber.org/protocol/httpbind' `+
			`xmlns:xmpp='urn:xmpp:xbosh' `+
			`to='%s' `+
			`xml:lang='en' `+
			`xmpp:version='1.0' `+
			`wait='60' hold='1' `+
			`rid='%d' `+
			`content='text/xml; charset=utf-8'/>`,
		xmlEscape(domain), time.Now().UnixNano()%1000000)
	resp, err := ApiHTTPClient.Post(boshURL, "text/xml; charset=utf-8", strings.NewReader(body))
	if err != nil {
		return "", fmt.Errorf("bosh init: %w", err)
	}
	defer resp.Body.Close()
	respBody, err := ReadBodyCapped(resp.Body, ApiBodyCeiling)
	if err != nil {
		return "", fmt.Errorf("bosh read: %w", err)
	}
	s := string(respBody)
	sid := ""
	if i := strings.Index(s, "sid='"); i >= 0 {
		rest := s[i+5:]
		if j := strings.Index(rest, "'"); j >= 0 {
			sid = rest[:j]
		}
	}
	if sid == "" {
		return "", fmt.Errorf("bosh: no session id in response: %s", s)
	}
	return sid, nil
}

func (c *XMPPCore) ConnectDirectTLS(domain string) error {
	_, addrs, err := net.LookupSRV("xmpps-client", "tcp", domain)
	if err != nil || len(addrs) == 0 {
		return fmt.Errorf("xmpp: XEP-0368: no xmpps-client SRV for %s", domain)
	}
	addr := net.JoinHostPort(strings.TrimRight(addrs[0].Target, "."), strconv.Itoa(int(addrs[0].Port)))
	conn, err := tls.DialWithDialer(&net.Dialer{Timeout: 10 * time.Second}, "tcp", addr, &tls.Config{ServerName: domain})
	if err != nil {
		return fmt.Errorf("xmpp: direct TLS connect %s: %w", addr, err)
	}
	c.mu.Lock()
	c.conn = conn
	c.reader = bufio.NewReader(conn)
	c.mu.Unlock()
	return nil
}

func (c *XMPPCore) InstantStreamResumption(token string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<resume xmlns='urn:xmpp:isr:0' token='%s'/>`, xmlEscape(token)))
}

func (c *XMPPCore) DiscoverHostMeta2(domain string) (map[string]string, error) {
	url := fmt.Sprintf("https://%s/.well-known/host-meta.json", domain)
	resp, err := ApiHTTPClient.Get(url)
	if err != nil {
		return nil, fmt.Errorf("xmpp: host-meta2: %w", err)
	}
	defer resp.Body.Close()
	var result map[string]interface{}
	if err := DecodeJSONBody(resp.Body, &result); err != nil {
		return nil, fmt.Errorf("xmpp: host-meta2 parse: %w", err)
	}
	links := make(map[string]string)
	if linksArr, ok := result["links"].([]interface{}); ok {
		for _, l := range linksArr {
			if lm, ok := l.(map[string]interface{}); ok {
				rel, _ := lm["rel"].(string)
				href, _ := lm["href"].(string)
				if rel != "" {
					links[rel] = href
				}
			}
		}
	}
	return links, nil
}

func (c *XMPPCore) OAuthClientLogin(token string) error {
	encoded := base64.StdEncoding.EncodeToString([]byte(fmt.Sprintf("n,,\x01auth=Bearer %s\x01\x01", token)))
	return c.sendRawStanza(fmt.Sprintf(
		`<auth xmlns='urn:ietf:params:xml:ns:xmpp-sasl' mechanism='OAUTHBEARER'>%s</auth>`, encoded))
}

func (c *XMPPCore) RevokeClientAccess(clientID string) error {
	_, err := c.sendIQSync("set", "",
		fmt.Sprintf(`<revoke xmlns='urn:xmpp:cam:0' id='%s'/>`, xmlEscape(clientID)))
	return err
}

func (c *XMPPCore) ListClientAccess() (*XMPPIQ, error) {
	return c.sendIQSync("get", "", `<list xmlns='urn:xmpp:cam:0'/>`)
}

func (c *XMPPCore) ConnectHappyEyeballs(host string, port int) (net.Conn, error) {
	d := &net.Dialer{Timeout: 10 * time.Second, DualStack: true}
	return d.Dial("tcp", net.JoinHostPort(host, strconv.Itoa(port)))
}

func (c *XMPPCore) InitAuthPipelining(mechanism, initialResponse string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<authenticate xmlns='urn:xmpp:sasl:2' mechanism='%s'>`+
			`<initial-response>%s</initial-response>`+
			`<bind xmlns='urn:xmpp:bind:0'/>`+
			`</authenticate>`,
		xmlEscape(mechanism), initialResponse))
}

func (c *XMPPCore) GetStreamLimits() map[string]int {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return map[string]int{
		"max_bytes":    c.streamMaxBytes,
		"idle_seconds": c.streamIdleSeconds,
	}
}

func (c *XMPPCore) QuickstartTLS(domain string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<starttls xmlns='urn:ietf:params:xml:ns:xmpp-tls'><required/></starttls>`))
}

func (c *XMPPCore) RetractMessage(to, msgID string) error {
	id := c.nextMsgID()
	return c.sendRawStanza(fmt.Sprintf(
		`<message type='chat' to='%s' id='%s'>`+
			`<apply-to xmlns='urn:xmpp:fasten:0' id='%s'>`+
			`<retract xmlns='urn:xmpp:message-retract:1'/>`+
			`</apply-to>`+
			`<fallback xmlns='urn:xmpp:fallback:0'/>`+
			`<body>This person attempted to retract a previous message, but your client doesn&apos;t support it.</body>`+
			`<store xmlns='urn:xmpp:hints'/>`+
			`</message>`,
		xmlEscape(to), id, xmlEscape(msgID)))
}

func ParseMessageStyling(text string) []map[string]string {
	var spans []map[string]string
	markers := map[byte]string{'*': "strong", '_': "emphasis", '`': "code", '~': "strike"}
	for char, style := range markers {
		for i := 0; i < len(text)-1; i++ {
			if text[i] == char {
				end := strings.IndexByte(text[i+1:], char)
				if end > 0 {
					spans = append(spans, map[string]string{
						"style": style, "text": text[i+1 : i+1+end],
						"start": strconv.Itoa(i), "end": strconv.Itoa(i + 1 + end + 1),
					})
					i = i + 1 + end
				}
			}
		}
	}
	return spans
}

func ApplyStyling(text string) (string, []TextEntity) {
	spans := ParseMessageStyling(text)
	if len(spans) == 0 {
		return text, nil
	}
	strip := make(map[int]bool)
	type ent struct {
		style   string
		s, e    int
		openRun int
	}
	var ents []ent
	for _, sp := range spans {
		start, err1 := strconv.Atoi(sp["start"])
		end, err2 := strconv.Atoi(sp["end"])
		if err1 != nil || err2 != nil || end-1 <= start {
			continue
		}
		closing := end - 1
		if sp["text"] == "" || closing >= len(text) || text[start] != text[closing] {
			continue
		}
		marker := text[start]
		openL, openR := start, start+1
		for openL-1 >= 0 && text[openL-1] == marker {
			openL--
		}
		for openR < len(text) && text[openR] == marker && openR < closing {
			openR++
		}
		closeL, closeR := closing, closing+1
		for closeR < len(text) && text[closeR] == marker {
			closeR++
		}
		for closeL-1 >= openR && text[closeL-1] == marker {
			closeL--
		}
		for i := openL; i < openR; i++ {
			strip[i] = true
		}
		for i := closeL; i < closeR; i++ {
			strip[i] = true
		}
		style := sp["style"]
		if marker == '`' && openR-openL >= 3 {
			style = "pre"
		}
		ents = append(ents, ent{style: style, s: openR, e: closeL, openRun: openR - openL})
	}

	pos := make(map[int]int, len(text))
	var sb strings.Builder
	u := 0
	i := 0
	for i < len(text) {
		pos[i] = u
		if strip[i] {
			i++
			continue
		}
		r, sz := utf8.DecodeRuneInString(text[i:])
		sb.WriteString(text[i : i+sz])
		if r >= 0x10000 {
			u += 2
		} else {
			u++
		}
		i += sz
	}
	pos[len(text)] = u

	var out []TextEntity
	typeOf := map[string]string{"strong": "bold", "emphasis": "italic", "code": "code", "strike": "strike", "pre": "pre"}
	for _, e := range ents {
		typ, ok := typeOf[e.style]
		if !ok {
			continue
		}
		sOff, ok1 := pos[e.s]
		eOff, ok2 := pos[e.e]
		if !ok1 || !ok2 || eOff-sOff <= 0 {
			continue
		}
		out = append(out, TextEntity{Type: typ, Offset: sOff, Length: eOff - sOff})
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Offset < out[j].Offset })

	final := sb.String()
	text16 := len(utf16.Encode([]rune(final)))
	filtered := out[:0]
	for _, e := range out {
		if e.Offset >= text16 {
			continue
		}
		if e.Offset+e.Length > text16 {
			e.Length = text16 - e.Offset
		}
		filtered = append(filtered, e)
	}
	return final, filtered
}

func (c *XMPPCore) SendSpoilerMessage(to, body, hint string) error {
	id := c.nextMsgID()
	hintXML := ""
	if hint != "" {
		hintXML = xmlEscape(hint)
	}
	return c.sendRawStanza(fmt.Sprintf(
		`<message type='chat' to='%s' id='%s'>`+
			`<body>%s</body>`+
			`<spoiler xmlns='urn:xmpp:spoiler:0'>%s</spoiler>`+
			`</message>`,
		xmlEscape(to), id, xmlEscape(body), hintXML))
}

func (c *XMPPCore) FastenPayload(to, targetID, payload string) error {
	id := c.nextMsgID()
	return c.sendRawStanza(fmt.Sprintf(
		`<message type='chat' to='%s' id='%s'>`+
			`<apply-to xmlns='urn:xmpp:fasten:0' id='%s'>%s</apply-to>`+
			`</message>`,
		xmlEscape(to), id, xmlEscape(targetID), payload))
}

func (c *XMPPCore) SendJSONMessage(to string, jsonPayload json.RawMessage) error {
	id := c.nextMsgID()
	return c.sendRawStanza(fmt.Sprintf(
		`<message type='chat' to='%s' id='%s'>`+
			`<json xmlns='urn:xmpp:json:0'>%s</json>`+
			`</message>`,
		xmlEscape(to), id, xmlEscape(string(jsonPayload))))
}

func (c *XMPPCore) SendQuickResponse(to, body string, responses []string) error {
	id := c.nextMsgID()
	var responseXML string
	for i, r := range responses {
		responseXML += fmt.Sprintf(`<response xmlns='urn:xmpp:quick-response:0' value='%s' id='resp-%d' label='%s'/>`,
			xmlEscape(r), i, xmlEscape(r))
	}
	return c.sendRawStanza(fmt.Sprintf(
		`<message type='chat' to='%s' id='%s'>`+
			`<body>%s</body>%s</message>`,
		xmlEscape(to), id, xmlEscape(body), responseXML))
}

func (c *XMPPCore) SendContentTypedMessage(to, body, contentType string) error {
	id := c.nextMsgID()
	return c.sendRawStanza(fmt.Sprintf(
		`<message type='chat' to='%s' id='%s'>`+
			`<body>%s</body>`+
			`<content xmlns='urn:xmpp:content:0' type='%s'/>`+
			`</message>`,
		xmlEscape(to), id, xmlEscape(body), xmlEscape(contentType)))
}

func (c *XMPPCore) SendRealTimeText(to string, seq int, actions []map[string]string) error {
	id := c.nextMsgID()
	var actionXML string
	for _, a := range actions {
		if t, ok := a["insert"]; ok {
			actionXML += fmt.Sprintf(`<t>%s</t>`, xmlEscape(t))
		} else if _, ok := a["erase"]; ok {
			n, _ := strconv.Atoi(a["erase"])
			actionXML += fmt.Sprintf(`<e n='%d'/>`, n)
		} else if _, ok := a["wait"]; ok {
			ms, _ := strconv.Atoi(a["wait"])
			actionXML += fmt.Sprintf(`<w n='%d'/>`, ms)
		}
	}
	return c.sendRawStanza(fmt.Sprintf(
		`<message type='chat' to='%s' id='%s'>`+
			`<rtt xmlns='urn:xmpp:rtt:0' seq='%d' event='edit'>%s</rtt>`+
			`</message>`,
		xmlEscape(to), id, seq, actionXML))
}

func (c *XMPPCore) RequestStanzaIDs() error {
	return c.sendRawStanza(`<enable xmlns='urn:xmpp:sid:0'/>`)
}

func (c *XMPPCore) GetInbox() (*XMPPIQ, error) {
	return c.sendIQSync("get", "", `<inbox xmlns='urn:xmpp:inbox:1'/>`)
}

func (c *XMPPCore) SearchMAMFullText(query string) (*XMPPIQ, error) {
	return c.sendIQSync("set", "",
		fmt.Sprintf(`<query xmlns='urn:xmpp:mam:2'>`+
			`<x xmlns='jabber:x:data' type='submit'>`+
			`<field var='FORM_TYPE' type='hidden'><value>urn:xmpp:mam:2</value></field>`+
			`<field var='fulltext'><value>%s</value></field>`+
			`</x></query>`, xmlEscape(query)))
}

func (c *XMPPCore) SetReminder(to, text string, when time.Time) error {
	id := c.nextMsgID()
	return c.sendRawStanza(fmt.Sprintf(
		`<message to='%s' id='%s'>`+
			`<reminder xmlns='urn:xmpp:reminder:0' stamp='%s'>`+
			`<body>%s</body></reminder></message>`,
		xmlEscape(to), id, when.UTC().Format(time.RFC3339), xmlEscape(text)))
}

func (c *XMPPCore) SendDirectMUCInvitation(to, room, reason, password string) error {
	id := c.nextMsgID()
	pwdAttr := ""
	if password != "" {
		pwdAttr = fmt.Sprintf(` password='%s'`, xmlEscape(password))
	}
	return c.sendRawStanza(fmt.Sprintf(
		`<message to='%s' id='%s'>`+
			`<x xmlns='jabber:x:conference' jid='%s' reason='%s'%s/>`+
			`</message>`,
		xmlEscape(to), id, xmlEscape(room), xmlEscape(reason), pwdAttr))
}

func (c *XMPPCore) SetMUCHat(room, nick, hatURI, hatTitle string) error {
	_, err := c.sendIQSync("set", room,
		fmt.Sprintf(`<hats xmlns='urn:xmpp:hats:0'>`+
			`<hat uri='%s' title='%s' xmlns='urn:xmpp:hats:0'/></hats>`,
			xmlEscape(hatURI), xmlEscape(hatTitle)))
	return err
}

func (c *XMPPCore) SearchChannels(query string) (*XMPPIQ, error) {
	return c.sendIQSync("get", "",
		fmt.Sprintf(`<search xmlns='urn:xmpp:channel-search:0'>`+
			`<set xmlns='http://jabber.org/protocol/rsm'><max>50</max></set>`+
			`<q>%s</q></search>`, xmlEscape(query)))
}

func (c *XMPPCore) EnableMUCPresenceVersioning(room string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<presence to='%s'>`+
			`<x xmlns='http://jabber.org/protocol/muc'/>`+
			`<presence-versioning xmlns='urn:xmpp:muc-presence-versioning:0'/>`+
			`</presence>`,
		xmlEscape(room)))
}

func (c *XMPPCore) SubscribeRoomActivity(room string) error {
	_, err := c.sendIQSync("set", "",
		fmt.Sprintf(`<activity xmlns='urn:xmpp:room-activity:0' jid='%s'/>`, xmlEscape(room)))
	return err
}

func (c *XMPPCore) SubscribeMUCMentions(room string) error {
	_, err := c.sendIQSync("set", room,
		`<subscribe xmlns='urn:xmpp:muc-mention-notifications:0'/>`)
	return err
}

func (c *XMPPCore) EnableMUCAffiliationVersioning(room string) error {
	_, err := c.sendIQSync("get", room,
		`<affiliations xmlns='urn:xmpp:muc-affiliations-versioning:0'/>`)
	return err
}

func (c *XMPPCore) SetMUCAvatar(room string, pngData []byte) error {
	b64 := base64.StdEncoding.EncodeToString(pngData)
	_, err := c.sendIQSync("set", room,
		fmt.Sprintf(`<vCard xmlns='vcard-temp'><PHOTO><TYPE>image/png</TYPE><BINVAL>%s</BINVAL></PHOTO></vCard>`, b64))
	return err
}

func (c *XMPPCore) CreateMUCTokenInvite(room string) (*XMPPIQ, error) {
	return c.sendIQSync("set", room,
		`<invite xmlns='urn:xmpp:muc-token-invite:0'/>`)
}

func (c *XMPPCore) SetMUCSlowMode(room string, intervalSeconds int) error {
	_, err := c.sendIQSync("set", room,
		fmt.Sprintf(`<query xmlns='http://jabber.org/protocol/muc#owner'>`+
			`<x xmlns='jabber:x:data' type='submit'>`+
			`<field var='FORM_TYPE'><value>http://jabber.org/protocol/muc#roomconfig</value></field>`+
			`<field var='muc#roomconfig_slowmode_length'><value>%d</value></field>`+
			`</x></query>`, intervalSeconds))
	return err
}

func (c *XMPPCore) GetMUCActivityIndicator(room string) (*XMPPIQ, error) {
	return c.sendIQSync("get", room,
		`<activity xmlns='urn:xmpp:muc-activity-indicator:0'/>`)
}

func (c *XMPPCore) MIXPresenceSubscribe(channel string) error {
	_, err := c.sendIQSync("set", channel,
		`<subscribe xmlns='urn:xmpp:mix:nodes:presence'/>`)
	return err
}

func (c *XMPPCore) MIXSetAnonymity(channel string, anonymous bool) error {
	val := "false"
	if anonymous {
		val = "true"
	}
	_, err := c.sendIQSync("set", channel,
		fmt.Sprintf(`<config xmlns='urn:xmpp:mix:admin:0'>`+
			`<field var='urn:xmpp:mix:anon:0#anonymous'><value>%s</value></field></config>`, val))
	return err
}

func (c *XMPPCore) MIXPAMJoin(channel string) error {
	_, err := c.sendIQSync("set", "",
		fmt.Sprintf(`<client-join xmlns='urn:xmpp:mix:pam:2' channel='%s'>`+
			`<join xmlns='urn:xmpp:mix:core:1'>`+
			`<subscribe node='urn:xmpp:mix:nodes:messages'/>`+
			`<subscribe node='urn:xmpp:mix:nodes:participants'/>`+
			`<subscribe node='urn:xmpp:mix:nodes:info'/>`+
			`</join></client-join>`, xmlEscape(channel)))
	return err
}

func (c *XMPPCore) MIXAdminSetConfig(channel string, fields map[string]string) error {
	var fieldXML string
	for k, v := range fields {
		fieldXML += fmt.Sprintf(`<field var='%s'><value>%s</value></field>`,
			xmlEscape(k), xmlEscape(v))
	}
	_, err := c.sendIQSync("set", channel,
		fmt.Sprintf(`<config xmlns='urn:xmpp:mix:admin:0'>%s</config>`, fieldXML))
	return err
}

func (c *XMPPCore) MIXMiscSetAvatar(channel string, pngData []byte) error {
	b64 := base64.StdEncoding.EncodeToString(pngData)
	_, err := c.sendIQSync("set", channel,
		fmt.Sprintf(`<pubsub xmlns='http://jabber.org/protocol/pubsub'>`+
			`<publish node='urn:xmpp:mix:nodes:info'>`+
			`<item><avatar xmlns='urn:xmpp:avatar:data'>%s</avatar></item>`+
			`</publish></pubsub>`, b64))
	return err
}

func (c *XMPPCore) JingleRTPSession(to, sid, media string, payloadTypes []map[string]string) error {
	var ptXML string
	for _, pt := range payloadTypes {
		ptXML += fmt.Sprintf(`<payload-type xmlns='urn:xmpp:jingle:apps:rtp:1' id='%s' name='%s' clockrate='%s'/>`,
			pt["id"], pt["name"], pt["clockrate"])
	}
	_, err := c.sendIQSync("set", to,
		fmt.Sprintf(`<jingle xmlns='urn:xmpp:jingle:1' action='session-initiate' sid='%s'>`+
			`<content creator='initiator' name='%s'>`+
			`<description xmlns='urn:xmpp:jingle:apps:rtp:1' media='%s'>%s</description>`+
			`</content></jingle>`, xmlEscape(sid), xmlEscape(media), xmlEscape(media), ptXML))
	return err
}

func (c *XMPPCore) JingleRawUDP(to, sid, candidateIP string, candidatePort int) error {
	_, err := c.sendIQSync("set", to,
		fmt.Sprintf(`<jingle xmlns='urn:xmpp:jingle:1' action='transport-info' sid='%s'>`+
			`<content creator='initiator' name='audio'>`+
			`<transport xmlns='urn:xmpp:jingle:transports:raw-udp:1'>`+
			`<candidate ip='%s' port='%d' generation='0'/>`+
			`</transport></content></jingle>`,
			xmlEscape(sid), xmlEscape(candidateIP), candidatePort))
	return err
}

func (c *XMPPCore) JingleZRTP(to, sid, zrtpHash, hashVersion string) error {
	_, err := c.sendIQSync("set", to,
		fmt.Sprintf(`<jingle xmlns='urn:xmpp:jingle:1' action='session-info' sid='%s'>`+
			`<zrtp-hash xmlns='urn:xmpp:jingle:apps:rtp:zrtp:1' version='%s'>%s</zrtp-hash>`+
			`</jingle>`, xmlEscape(sid), xmlEscape(hashVersion), xmlEscape(zrtpHash)))
	return err
}

func JingleAudioCodecs() []map[string]string {
	return []map[string]string{
		{"id": "111", "name": "opus", "clockrate": "48000", "channels": "2"},
		{"id": "100", "name": "speex", "clockrate": "16000"},
		{"id": "0", "name": "PCMU", "clockrate": "8000"},
		{"id": "8", "name": "PCMA", "clockrate": "8000"},
	}
}

func (c *XMPPCore) JingleMuji(room, media string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<presence to='%s'><muji xmlns='urn:xmpp:jingle:muji:0'>`+
			`<content name='%s'><description xmlns='urn:xmpp:jingle:apps:rtp:1' media='%s'/></content>`+
			`</muji></presence>`,
		xmlEscape(room), xmlEscape(media), xmlEscape(media)))
}

func (c *XMPPCore) JingleConferenceInfo(to, sid string, users []string) error {
	var userXML string
	for _, u := range users {
		userXML += fmt.Sprintf(`<user entity='%s'/>`, xmlEscape(u))
	}
	_, err := c.sendIQSync("set", to,
		fmt.Sprintf(`<jingle xmlns='urn:xmpp:jingle:1' action='session-info' sid='%s'>`+
			`<conference-info xmlns='urn:xmpp:coin:1'><users>%s</users></conference-info>`+
			`</jingle>`, xmlEscape(sid), userXML))
	return err
}

func JingleVideoCodecs() []map[string]string {
	return []map[string]string{
		{"id": "96", "name": "VP8", "clockrate": "90000"},
		{"id": "97", "name": "H264", "clockrate": "90000"},
	}
}

func (c *XMPPCore) JingleDTLSSRTP(to, sid, fingerprint, setup string) error {
	_, err := c.sendIQSync("set", to,
		fmt.Sprintf(`<jingle xmlns='urn:xmpp:jingle:1' action='transport-info' sid='%s'>`+
			`<content creator='initiator' name='audio'>`+
			`<transport xmlns='urn:xmpp:jingle:transports:ice-udp:1'>`+
			`<fingerprint xmlns='urn:xmpp:jingle:apps:dtls:0' hash='sha-256' setup='%s'>%s</fingerprint>`+
			`</transport></content></jingle>`,
			xmlEscape(sid), xmlEscape(setup), xmlEscape(fingerprint)))
	return err
}

func (c *XMPPCore) JingleGrouping(to, sid string, contentNames []string) error {
	var contentsXML string
	for _, name := range contentNames {
		contentsXML += fmt.Sprintf(`<content name='%s'/>`, xmlEscape(name))
	}
	_, err := c.sendIQSync("set", to,
		fmt.Sprintf(`<jingle xmlns='urn:xmpp:jingle:1' action='session-initiate' sid='%s'>`+
			`<group xmlns='urn:xmpp:jingle:apps:grouping:0' semantics='BUNDLE'>%s</group>`+
			`</jingle>`, xmlEscape(sid), contentsXML))
	return err
}

func (c *XMPPCore) JingleSourceSSRC(to, sid string, ssrc uint32, params map[string]string) error {
	var paramXML string
	for k, v := range params {
		paramXML += fmt.Sprintf(`<parameter name='%s' value='%s'/>`, xmlEscape(k), xmlEscape(v))
	}
	_, err := c.sendIQSync("set", to,
		fmt.Sprintf(`<jingle xmlns='urn:xmpp:jingle:1' action='source-add' sid='%s'>`+
			`<content creator='initiator' name='audio'>`+
			`<description xmlns='urn:xmpp:jingle:apps:rtp:1'>`+
			`<source xmlns='urn:xmpp:jingle:apps:rtp:ssma:0' ssrc='%d'>%s</source>`+
			`</description></content></jingle>`,
			xmlEscape(sid), ssrc, paramXML))
	return err
}

func (c *XMPPCore) JingleDataChannels(to, sid string, port int) error {
	_, err := c.sendIQSync("set", to,
		fmt.Sprintf(`<jingle xmlns='urn:xmpp:jingle:1' action='session-initiate' sid='%s'>`+
			`<content creator='initiator' name='data'>`+
			`<description xmlns='urn:xmpp:jingle:transports:dtls-sctp:1'/>`+
			`<transport xmlns='urn:xmpp:jingle:transports:ice-udp:1'>`+
			`<sctpmap xmlns='urn:xmpp:jingle:transports:dtls-sctp:1' number='%d' protocol='webrtc-datachannel'/>`+
			`</transport></content></jingle>`,
			xmlEscape(sid), port))
	return err
}

func (c *XMPPCore) JingleMessageRinging(to, sid string) error {
	id := c.nextMsgID()
	return c.sendRawStanza(fmt.Sprintf(
		`<message to='%s' id='%s'>`+
			`<ringing xmlns='urn:xmpp:jingle-message:0' id='%s'/>`+
			`</message>`,
		xmlEscape(to), id, xmlEscape(sid)))
}

func (c *XMPPCore) PublishJingleSession(sid, description string) error {
	_, err := c.sendIQSync("set", "",
		fmt.Sprintf(`<pubsub xmlns='http://jabber.org/protocol/pubsub'>`+
			`<publish node='urn:xmpp:jingle:pub:1'>`+
			`<item id='%s'><session xmlns='urn:xmpp:jingle:pub:1'>`+
			`<description>%s</description></session></item>`+
			`</publish></pubsub>`, xmlEscape(sid), xmlEscape(description)))
	return err
}

func (c *XMPPCore) JingleTrickleICE(to, sid string, candidate map[string]string) error {
	_, err := c.sendIQSync("set", to,
		fmt.Sprintf(`<jingle xmlns='urn:xmpp:jingle:1' action='transport-info' sid='%s'>`+
			`<content creator='initiator' name='audio'>`+
			`<transport xmlns='urn:xmpp:jingle:transports:ice:0' ufrag='%s' pwd='%s'>`+
			`<candidate component='1' foundation='%s' generation='0' ip='%s' port='%s' priority='%s' protocol='%s' type='%s'/>`+
			`</transport></content></jingle>`,
			xmlEscape(sid), candidate["ufrag"], candidate["pwd"],
			candidate["foundation"], candidate["ip"], candidate["port"],
			candidate["priority"], candidate["protocol"], candidate["type"]))
	return err
}

func (c *XMPPCore) JingleEncryptedTransport(to, sid, cipher, keyB64 string) error {
	_, err := c.sendIQSync("set", to,
		fmt.Sprintf(`<jingle xmlns='urn:xmpp:jingle:1' action='session-initiate' sid='%s'>`+
			`<content creator='initiator' name='file'>`+
			`<security xmlns='urn:xmpp:jingle:jet:0' name='file' cipher='%s' type='urn:xmpp:omemo:0'>`+
			`<key>%s</key></security>`+
			`</content></jingle>`,
			xmlEscape(sid), xmlEscape(cipher), keyB64))
	return err
}

func (c *XMPPCore) JingleJETOMEMO(to, sid string, deviceID int, keyData []byte) error {
	b64 := base64.StdEncoding.EncodeToString(keyData)
	_, err := c.sendIQSync("set", to,
		fmt.Sprintf(`<jingle xmlns='urn:xmpp:jingle:1' action='session-initiate' sid='%s'>`+
			`<content creator='initiator' name='file'>`+
			`<security xmlns='urn:xmpp:jingle:jet:0' cipher='urn:xmpp:ciphers:aes-256-gcm-nopadding'>`+
			`<encrypted xmlns='urn:xmpp:omemo:2' device-id='%d'>`+
			`<payload>%s</payload></encrypted></security>`+
			`</content></jingle>`,
			xmlEscape(sid), deviceID, b64))
	return err
}

func (c *XMPPCore) SendCallInvite(to, sid string, audio, video bool) error {
	id := c.nextMsgID()
	var mediaXML string
	if audio {
		mediaXML += `<audio xmlns='urn:xmpp:call-invites:0'/>`
	}
	if video {
		mediaXML += `<video xmlns='urn:xmpp:call-invites:0'/>`
	}
	return c.sendRawStanza(fmt.Sprintf(
		`<message to='%s' id='%s'>`+
			`<invite xmlns='urn:xmpp:call-invites:0' id='%s'>%s</invite>`+
			`</message>`,
		xmlEscape(to), id, xmlEscape(sid), mediaXML))
}

func (c *XMPPCore) JingleContentCategory(to, sid, name, category string) error {
	_, err := c.sendIQSync("set", to,
		fmt.Sprintf(`<jingle xmlns='urn:xmpp:jingle:1' action='content-modify' sid='%s'>`+
			`<content creator='initiator' name='%s'>`+
			`<category xmlns='urn:xmpp:jingle:content-category:0' name='%s'/>`+
			`</content></jingle>`,
			xmlEscape(sid), xmlEscape(name), xmlEscape(category)))
	return err
}

func (c *XMPPCore) JingleContentThumbnail(to, sid, thumbnailURI, mimeType string, width, height int) error {
	_, err := c.sendIQSync("set", to,
		fmt.Sprintf(`<jingle xmlns='urn:xmpp:jingle:1' action='session-initiate' sid='%s'>`+
			`<content creator='initiator' name='file'>`+
			`<description xmlns='urn:xmpp:jingle:apps:file-transfer:5'>`+
			`<file><thumbnail xmlns='urn:xmpp:thumbs:1' uri='%s' media-type='%s' width='%d' height='%d'/>`+
			`</file></description></content></jingle>`,
			xmlEscape(sid), xmlEscape(thumbnailURI), xmlEscape(mimeType), width, height))
	return err
}

func (c *XMPPCore) SendSIMS(to, url, mimeType string, size int64, desc string) error {
	id := c.nextMsgID()
	return c.sendRawStanza(fmt.Sprintf(
		`<message type='chat' to='%s' id='%s'>`+
			`<reference xmlns='urn:xmpp:reference:0' type='data'>`+
			`<media-sharing xmlns='urn:xmpp:sims:1'>`+
			`<file xmlns='urn:xmpp:jingle:apps:file-transfer:5'>`+
			`<media-type>%s</media-type><size>%d</size><desc>%s</desc>`+
			`</file><sources><reference xmlns='urn:xmpp:reference:0' type='data' uri='%s'/></sources>`+
			`</media-sharing></reference></message>`,
		xmlEscape(to), id, xmlEscape(mimeType), size, xmlEscape(desc), xmlEscape(url)))
}

func (c *XMPPCore) ShareFileMetadataElem(to, name, mimeType string, size int64, hashAlgo, hashValue string) error {
	id := c.nextMsgID()
	return c.sendRawStanza(fmt.Sprintf(
		`<message type='chat' to='%s' id='%s'>`+
			`<file xmlns='urn:xmpp:file:metadata:0'>`+
			`<name>%s</name><media-type>%s</media-type><size>%d</size>`+
			`<hash xmlns='urn:xmpp:hashes:2' algo='%s'>%s</hash>`+
			`</file></message>`,
		xmlEscape(to), id, xmlEscape(name), xmlEscape(mimeType), size,
		xmlEscape(hashAlgo), xmlEscape(hashValue)))
}

func (c *XMPPCore) PubSubFileShare(node, itemID, name, url string) error {
	_, err := c.sendIQSync("set", "",
		fmt.Sprintf(`<pubsub xmlns='http://jabber.org/protocol/pubsub'>`+
			`<publish node='%s'><item id='%s'>`+
			`<file-sharing xmlns='urn:xmpp:file-sharing:0'>`+
			`<file xmlns='urn:xmpp:file:metadata:0'><name>%s</name></file>`+
			`<sources><url-data xmlns='http://jabber.org/protocol/url-data' target='%s'/></sources>`+
			`</file-sharing></item></publish></pubsub>`,
			xmlEscape(node), xmlEscape(itemID), xmlEscape(name), xmlEscape(url)))
	return err
}

func (c *XMPPCore) DataFormsFileInput(to, formType, fieldVar, uploadURL string) error {
	_, err := c.sendIQSync("set", to,
		fmt.Sprintf(`<x xmlns='jabber:x:data' type='submit'>`+
			`<field var='FORM_TYPE'><value>%s</value></field>`+
			`<field var='%s' type='file'>`+
			`<value>%s</value></field></x>`,
			xmlEscape(formType), xmlEscape(fieldVar), xmlEscape(uploadURL)))
	return err
}

func (c *XMPPCore) PEPManageNode(node string, config map[string]string) error {
	var fieldXML string
	for k, v := range config {
		fieldXML += fmt.Sprintf(`<field var='%s'><value>%s</value></field>`,
			xmlEscape(k), xmlEscape(v))
	}
	_, err := c.sendIQSync("set", "",
		fmt.Sprintf(`<pubsub xmlns='http://jabber.org/protocol/pubsub#owner'>`+
			`<configure node='%s'><x xmlns='jabber:x:data' type='submit'>%s</x></configure></pubsub>`,
			xmlEscape(node), fieldXML))
	return err
}

func (c *XMPPCore) PubSubPersistPublic(node, itemID, payload string) error {
	_, err := c.sendIQSync("set", "",
		fmt.Sprintf(`<pubsub xmlns='http://jabber.org/protocol/pubsub'>`+
			`<publish node='%s'><item id='%s'>%s</item></publish>`+
			`<publish-options><x xmlns='jabber:x:data' type='submit'>`+
			`<field var='FORM_TYPE' type='hidden'><value>http://jabber.org/protocol/pubsub#publish-options</value></field>`+
			`<field var='pubsub#persist_items'><value>true</value></field>`+
			`<field var='pubsub#access_model'><value>open</value></field>`+
			`</x></publish-options></pubsub>`,
			xmlEscape(node), xmlEscape(itemID), payload))
	return err
}

func (c *XMPPCore) PubSubPersistPrivate(node, itemID, payload string) error {
	_, err := c.sendIQSync("set", "",
		fmt.Sprintf(`<pubsub xmlns='http://jabber.org/protocol/pubsub'>`+
			`<publish node='%s'><item id='%s'>%s</item></publish>`+
			`<publish-options><x xmlns='jabber:x:data' type='submit'>`+
			`<field var='FORM_TYPE' type='hidden'><value>http://jabber.org/protocol/pubsub#publish-options</value></field>`+
			`<field var='pubsub#persist_items'><value>true</value></field>`+
			`<field var='pubsub#access_model'><value>whitelist</value></field>`+
			`</x></publish-options></pubsub>`,
			xmlEscape(node), xmlEscape(itemID), payload))
	return err
}

func (c *XMPPCore) PubSubCollectionNode(node, childNode string) error {
	_, err := c.sendIQSync("set", "",
		fmt.Sprintf(`<pubsub xmlns='http://jabber.org/protocol/pubsub'>`+
			`<create node='%s'/>`+
			`<configure><x xmlns='jabber:x:data' type='submit'>`+
			`<field var='pubsub#node_type'><value>collection</value></field>`+
			`</x></configure></pubsub>`, xmlEscape(node)))
	return err
}

func (c *XMPPCore) PublishMicroblog(content, author string) error {
	id := c.nextMsgID()
	_, err := c.sendIQSync("set", "",
		fmt.Sprintf(`<pubsub xmlns='http://jabber.org/protocol/pubsub'>`+
			`<publish node='urn:xmpp:microblog:0'>`+
			`<item id='%s'><entry xmlns='http://www.w3.org/2005/Atom'>`+
			`<content type='text'>%s</content>`+
			`<author><name>%s</name></author>`+
			`<published>%s</published>`+
			`</entry></item></publish></pubsub>`,
			id, xmlEscape(content), xmlEscape(author),
			time.Now().UTC().Format(time.RFC3339)))
	return err
}

func (c *XMPPCore) QueryPubSubMAM(service, node string) (*XMPPIQ, error) {
	return c.sendIQSync("set", service,
		fmt.Sprintf(`<query xmlns='urn:xmpp:mam:2' node='%s'/>`, xmlEscape(node)))
}

func (c *XMPPCore) SetPubSubCachingHints(node string, maxAge int) error {
	_, err := c.sendIQSync("set", "",
		fmt.Sprintf(`<pubsub xmlns='http://jabber.org/protocol/pubsub#owner'>`+
			`<configure node='%s'><x xmlns='jabber:x:data' type='submit'>`+
			`<field var='pubsub#item_expire'><value>%d</value></field>`+
			`</x></configure></pubsub>`, xmlEscape(node), maxAge))
	return err
}

func (c *XMPPCore) FilterPubSubByType(service, nodeType string) (*XMPPIQ, error) {
	return c.sendIQSync("get", service,
		fmt.Sprintf(`<query xmlns='http://jabber.org/protocol/disco#items'>`+
			`<filter xmlns='urn:xmpp:pubsub:filter:0' type='%s'/></query>`, xmlEscape(nodeType)))
}

func (c *XMPPCore) SetPubSubPublicSubscriptions(node string, public bool) error {
	val := "false"
	if public {
		val = "true"
	}
	_, err := c.sendIQSync("set", "",
		fmt.Sprintf(`<pubsub xmlns='http://jabber.org/protocol/pubsub#owner'>`+
			`<configure node='%s'><x xmlns='jabber:x:data' type='submit'>`+
			`<field var='pubsub#subscription_visibility'><value>%s</value></field>`+
			`</x></configure></pubsub>`, xmlEscape(node), val))
	return err
}

func (c *XMPPCore) PubSubAttachment(targetNode, targetItem, attachmentPayload string) error {
	id := c.nextMsgID()
	_, err := c.sendIQSync("set", "",
		fmt.Sprintf(`<pubsub xmlns='http://jabber.org/protocol/pubsub'>`+
			`<publish node='urn:xmpp:pubsub-attachments:1'>`+
			`<item id='%s'><attachments xmlns='urn:xmpp:pubsub-attachments:1'`+
			` for-node='%s' for-item='%s'>%s</attachments></item>`+
			`</publish></pubsub>`,
			id, xmlEscape(targetNode), xmlEscape(targetItem), attachmentPayload))
	return err
}

func (c *XMPPCore) PublishSocialFeed(content, contentType string) error {
	id := c.nextMsgID()
	_, err := c.sendIQSync("set", "",
		fmt.Sprintf(`<pubsub xmlns='http://jabber.org/protocol/pubsub'>`+
			`<publish node='urn:xmpp:social-feed:0'>`+
			`<item id='%s'><post xmlns='urn:xmpp:social-feed:0'>`+
			`<body type='%s'>%s</body></post></item>`+
			`</publish></pubsub>`, id, xmlEscape(contentType), xmlEscape(content)))
	return err
}

func (c *XMPPCore) EncryptPubSubOX(node, itemID, payload string) error {
	_, err := c.sendIQSync("set", "",
		fmt.Sprintf(`<pubsub xmlns='http://jabber.org/protocol/pubsub'>`+
			`<publish node='%s'><item id='%s'>`+
			`<openpgp xmlns='urn:xmpp:openpgp:0'>%s</openpgp>`+
			`</item></publish></pubsub>`,
			xmlEscape(node), xmlEscape(itemID), xmlEscape(payload)))
	return err
}

func (c *XMPPCore) GetPubSubServerInfo(service string) (*XMPPIQ, error) {
	return c.sendIQSync("get", service,
		`<query xmlns='http://jabber.org/protocol/disco#info' node='urn:xmpp:serverinfo:0'/>`)
}

func (c *XMPPCore) SetPubSubRelationship(node, parentNode string) error {
	_, err := c.sendIQSync("set", "",
		fmt.Sprintf(`<pubsub xmlns='http://jabber.org/protocol/pubsub#owner'>`+
			`<configure node='%s'><x xmlns='jabber:x:data' type='submit'>`+
			`<field var='pubsub#collection'><value>%s</value></field>`+
			`</x></configure></pubsub>`, xmlEscape(node), xmlEscape(parentNode)))
	return err
}

func (c *XMPPCore) PubSubCompareAndPublish(node, itemID, payload, prevID string) error {
	_, err := c.sendIQSync("set", "",
		fmt.Sprintf(`<pubsub xmlns='http://jabber.org/protocol/pubsub'>`+
			`<publish node='%s'><item id='%s'>%s</item></publish>`+
			`<precondition xmlns='urn:xmpp:pubsub:cas:0' prev-id='%s'/>`+
			`</pubsub>`,
			xmlEscape(node), xmlEscape(itemID), payload, xmlEscape(prevID)))
	return err
}

func (c *XMPPCore) DiscoInfoExtended(to, node string) (*XMPPIQ, error) {
	nodeAttr := ""
	if node != "" {
		nodeAttr = fmt.Sprintf(` node='%s'`, xmlEscape(node))
	}
	return c.sendIQSync("get", to,
		fmt.Sprintf(`<query xmlns='http://jabber.org/protocol/disco#info'%s/>`, nodeAttr))
}

func (c *XMPPCore) EntityCaps2(hashAlgo string, features []string) string {
	sort.Strings(features)
	data := strings.Join(features, "<")
	var h hash.Hash
	switch hashAlgo {
	case "sha-256":
		h = sha256.New()
	default:
		h = sha1.New()
	}
	h.Write([]byte(data))
	return base64.StdEncoding.EncodeToString(h.Sum(nil))
}

func (c *XMPPCore) GetDOAP(to string) (*XMPPIQ, error) {
	return c.sendIQSync("get", to,
		`<query xmlns='http://jabber.org/protocol/disco#info' node='urn:xmpp:doap:0'/>`)
}

func (c *XMPPCore) OMEMOAutoTrust(to string, deviceIDs []int) error {
	var devicesXML string
	for _, id := range deviceIDs {
		devicesXML += fmt.Sprintf(`<device id='%d'/>`, id)
	}
	id := c.nextMsgID()
	return c.sendRawStanza(fmt.Sprintf(
		`<message to='%s' id='%s'>`+
			`<trust-message xmlns='urn:xmpp:atm:1' usage='urn:xmpp:omemo:2' encryption='urn:xmpp:omemo:2'>`+
			`<key-owner jid='%s'>%s</key-owner>`+
			`</trust-message></message>`,
		xmlEscape(to), id, xmlEscape(to), devicesXML))
}

func (c *XMPPCore) AvatarConversion(to string) (*XMPPIQ, error) {
	return c.sendIQSync("get", to,
		`<pubsub xmlns='http://jabber.org/protocol/pubsub'>`+
			`<items node='urn:xmpp:avatar:data' max_items='1'/></pubsub>`)
}

func (c *XMPPCore) SetReachability(addresses []map[string]string) error {
	var addrXML string
	for _, a := range addresses {
		addrXML += fmt.Sprintf(`<addr uri='%s'><desc>%s</desc></addr>`,
			xmlEscape(a["uri"]), xmlEscape(a["desc"]))
	}
	_, err := c.sendIQSync("set", "",
		fmt.Sprintf(`<pubsub xmlns='http://jabber.org/protocol/pubsub'>`+
			`<publish node='urn:xmpp:reach:0'><item>`+
			`<reach xmlns='urn:xmpp:reach:0'>%s</reach></item></publish></pubsub>`, addrXML))
	return err
}

func (c *XMPPCore) SetVCardAvatar(pngData []byte) error {
	b64 := base64.StdEncoding.EncodeToString(pngData)
	_, err := c.sendIQSync("set", "",
		fmt.Sprintf(`<vCard xmlns='vcard-temp'><PHOTO><TYPE>image/png</TYPE><BINVAL>%s</BINVAL></PHOTO></vCard>`, b64))
	if err != nil {
		return err
	}
	h := sha1.Sum(pngData)
	return c.sendRawStanza(fmt.Sprintf(
		`<presence><x xmlns='vcard-temp:x:update'><photo>%s</photo></x></presence>`,
		hex.EncodeToString(h[:])))
}

func (c *XMPPCore) SetChatNotificationSettings(jid, level string) error {
	_, err := c.sendIQSync("set", "",
		fmt.Sprintf(`<pubsub xmlns='http://jabber.org/protocol/pubsub'>`+
			`<publish node='urn:xmpp:notification-settings:0'>`+
			`<item id='%s'><settings xmlns='urn:xmpp:notification-settings:0' level='%s'/></item>`+
			`</publish></pubsub>`, xmlEscape(jid), xmlEscape(level)))
	return err
}

func (c *XMPPCore) SetServerNotificationFilter(rules map[string]bool) error {
	var ruleXML string
	for eventType, enabled := range rules {
		if enabled {
			ruleXML += fmt.Sprintf(`<allow event='%s'/>`, xmlEscape(eventType))
		} else {
			ruleXML += fmt.Sprintf(`<deny event='%s'/>`, xmlEscape(eventType))
		}
	}
	_, err := c.sendIQSync("set", "",
		fmt.Sprintf(`<filter xmlns='urn:xmpp:notification-filter:0'>%s</filter>`, ruleXML))
	return err
}

func (c *XMPPCore) SearchUsersExtended(service string, fields map[string]string) (*XMPPIQ, error) {
	var fieldXML string
	for k, v := range fields {
		fieldXML += fmt.Sprintf(`<field var='%s'><value>%s</value></field>`,
			xmlEscape(k), xmlEscape(v))
	}
	return c.sendIQSync("set", service,
		fmt.Sprintf(`<query xmlns='jabber:iq:search'>`+
			`<x xmlns='jabber:x:data' type='submit'>%s</x></query>`, fieldXML))
}

func (c *XMPPCore) HandleCAPTCHA(to, challengeID, answer string) error {
	_, err := c.sendIQSync("set", to,
		fmt.Sprintf(`<captcha xmlns='urn:xmpp:captcha'>`+
			`<x xmlns='jabber:x:data' type='submit'>`+
			`<field var='FORM_TYPE' type='hidden'><value>urn:xmpp:captcha</value></field>`+
			`<field var='challenge'><value>%s</value></field>`+
			`<field var='ocr'><value>%s</value></field>`+
			`</x></captcha>`, xmlEscape(challengeID), xmlEscape(answer)))
	return err
}

func (c *XMPPCore) EnableRosterVersioning(ver string) (*XMPPIQ, error) {
	verAttr := ""
	if ver != "" {
		verAttr = fmt.Sprintf(` ver='%s'`, xmlEscape(ver))
	}
	return c.sendIQSync("get", "",
		fmt.Sprintf(`<query xmlns='jabber:iq:roster'%s/>`, verAttr))
}

func (c *XMPPCore) CreateInvitationURI() (*XMPPIQ, error) {
	return c.sendIQSync("set", "",
		`<invite xmlns='urn:xmpp:invite:2'/>`)
}

func (c *XMPPCore) PreAuthenticatedIBR(token string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<register xmlns='urn:xmpp:ibr-token:0' token='%s'/>`, xmlEscape(token)))
}

func (c *XMPPCore) GetServiceOutageStatus(domain string) (*XMPPIQ, error) {
	return c.sendIQSync("get", domain,
		`<status xmlns='urn:xmpp:service-status:0'/>`)
}

func (c *XMPPCore) GetDataPolicy(domain string) (*XMPPIQ, error) {
	return c.sendIQSync("get", domain,
		`<policy xmlns='urn:xmpp:data-policy:0'/>`)
}

func (c *XMPPCore) BookmarksConversion() error {
	_, err := c.sendIQSync("set", "",
		`<enable xmlns='urn:xmpp:bookmarks-conversion:0'/>`)
	return err
}

func (c *XMPPCore) SendWebXDC(to, name string, data []byte) error {
	id := c.nextMsgID()
	b64 := base64.StdEncoding.EncodeToString(data)
	return c.sendRawStanza(fmt.Sprintf(
		`<message type='chat' to='%s' id='%s'>`+
			`<webxdc xmlns='urn:xmpp:webxdc:0' name='%s'>%s</webxdc>`+
			`</message>`,
		xmlEscape(to), id, xmlEscape(name), b64))
}

func (c *XMPPCore) CreateServerSpace(name string, channels []string) error {
	var channelXML string
	for _, ch := range channels {
		channelXML += fmt.Sprintf(`<channel jid='%s'/>`, xmlEscape(ch))
	}
	_, err := c.sendIQSync("set", "",
		fmt.Sprintf(`<space xmlns='urn:xmpp:spaces:0' name='%s'>%s</space>`,
			xmlEscape(name), channelXML))
	return err
}

func (c *XMPPCore) CreateForum(service, name string) error {
	_, err := c.sendIQSync("set", service,
		fmt.Sprintf(`<create xmlns='urn:xmpp:forums:0' name='%s'/>`, xmlEscape(name)))
	return err
}

func (c *XMPPCore) EncryptContactsMetadata(jid string, encryptedPayload []byte) error {
	b64 := base64.StdEncoding.EncodeToString(encryptedPayload)
	_, err := c.sendIQSync("set", "",
		fmt.Sprintf(`<pubsub xmlns='http://jabber.org/protocol/pubsub'>`+
			`<publish node='urn:xmpp:contacts:metadata:0'>`+
			`<item id='%s'><encrypted xmlns='urn:xmpp:contacts:metadata:0'>%s</encrypted></item>`+
			`</publish></pubsub>`, xmlEscape(jid), b64))
	return err
}

func (c *XMPPCore) GetLinkMetadata(url string) (*XMPPIQ, error) {
	return c.sendIQSync("get", "",
		fmt.Sprintf(`<link-metadata xmlns='urn:xmpp:link-metadata:0' url='%s'/>`, xmlEscape(url)))
}

func (c *XMPPCore) RequestOnlineMeeting(service, meetingType string) (*XMPPIQ, error) {
	return c.sendIQSync("get", service,
		fmt.Sprintf(`<request xmlns='urn:xmpp:http:online-meetings:invite:0' type='%s'/>`,
			xmlEscape(meetingType)))
}

func (c *XMPPCore) RequestBurnerJID(service string) (*XMPPIQ, error) {
	return c.sendIQSync("get", service,
		`<burner xmlns='urn:xmpp:burner:0'/>`)
}

func (c *XMPPCore) ForwardStanza(to, originalFrom, originalStanza string) error {
	id := c.nextMsgID()
	return c.sendRawStanza(fmt.Sprintf(
		`<message to='%s' id='%s'>`+
			`<forwarded xmlns='urn:xmpp:forward:0'>`+
			`<delay xmlns='urn:xmpp:delay' from='%s' stamp='%s'/>`+
			`%s</forwarded></message>`,
		xmlEscape(to), id, xmlEscape(originalFrom),
		time.Now().UTC().Format("2006-01-02T15:04:05Z"), originalStanza))
}

func (c *XMPPCore) RSMQuery(to, queryNS string, max int, after string) (*XMPPIQ, error) {
	afterXML := ""
	if after != "" {
		afterXML = fmt.Sprintf(`<after>%s</after>`, xmlEscape(after))
	}
	return c.sendIQSync("get", to,
		fmt.Sprintf(`<query xmlns='%s'>`+
			`<set xmlns='http://jabber.org/protocol/rsm'><max>%d</max>%s</set></query>`,
			xmlEscape(queryNS), max, afterXML))
}

func (c *XMPPCore) NegotiateSession(to string, fields map[string]string) error {
	var fieldXML string
	for k, v := range fields {
		fieldXML += fmt.Sprintf(`<field var='%s'><value>%s</value></field>`,
			xmlEscape(k), xmlEscape(v))
	}
	id := c.nextMsgID()
	return c.sendRawStanza(fmt.Sprintf(
		`<message to='%s' id='%s'>`+
			`<feature xmlns='http://jabber.org/protocol/feature-neg'>`+
			`<x xmlns='jabber:x:data' type='form'>%s</x></feature></message>`,
		xmlEscape(to), id, fieldXML))
}

func (c *XMPPCore) SendBitsOfBinary(to string, data []byte, mimeType, cid string) error {
	id := c.nextMsgID()
	b64 := base64.StdEncoding.EncodeToString(data)
	return c.sendRawStanza(fmt.Sprintf(
		`<message type='chat' to='%s' id='%s'>`+
			`<data xmlns='urn:xmpp:bob' cid='%s' type='%s' max-age='86400'>%s</data>`+
			`</message>`,
		xmlEscape(to), id, xmlEscape(cid), xmlEscape(mimeType), b64))
}

func (c *XMPPCore) MuteChat(chatID string, muted bool) error {
	return fmt.Errorf("%w: %s does not support mute chat", ErrNotSupported, xmppPlatform)
}

func (c *XMPPCore) ArchiveChat(chatID string, archived bool) error {
	return fmt.Errorf("%w: %s does not support archive chat", ErrNotSupported, xmppPlatform)
}

func (c *XMPPCore) MarkUnread(chatID string, unread bool) error {
	return fmt.Errorf("%w: %s does not support mark unread", ErrNotSupported, xmppPlatform)
}

func (c *XMPPCore) UnpinAllMessages(chatID string) error {
	return fmt.Errorf("%w: %s does not support unpin all messages", ErrNotSupported, xmppPlatform)
}

func (c *XMPPCore) AcceptCall(callID string) (*CallSession, error) {
	return nil, fmt.Errorf("%w: %s does not support accept call", ErrNotSupported, xmppPlatform)
}

func (c *XMPPCore) DeclineCall(callID string) error {
	return fmt.Errorf("%w: %s does not support decline call", ErrNotSupported, xmppPlatform)
}

func (c *XMPPCore) SendLocation(chatID string, lat float64, lon float64) (*Message, error) {
	return nil, fmt.Errorf("%w: %s does not support send location", ErrNotSupported, xmppPlatform)
}
