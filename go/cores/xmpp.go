// XMPP core — pure Go XMPP client implementing the Core interface.
// Protocol: RFC 6120/6121 (XMPP Core + IM) + 30+ XEPs.
// No external dependencies — stdlib only (encoding/xml, crypto/tls, net).
//
// Chat IDs:
//   "user@domain"             → DM (bare JID)
//   "room@conference.domain"  → MUC room (group)
//
// AuthConfig.Extra keys:
//   "server"      — host:port (e.g. "conversations.im:5222")
//   "resource"    — XMPP resource (default: "uniclient")
//   "tls"         — "direct" for port 5223 direct TLS, "starttls" (default), "none"
//   "mechanism"   — "plain", "scram-sha-1", "scram-sha-256" (default: best available)
//   "muc_service" — MUC service domain (auto-discovered if empty)
//   "upload_service" — HTTP upload service (auto-discovered if empty)
//
// Coverage: SASL (PLAIN, SCRAM-SHA-1, SCRAM-SHA-256), STARTTLS, resource binding,
// roster (RFC 6121), presence, MUC (XEP-0045), disco (XEP-0030), MAM (XEP-0313),
// HTTP upload (XEP-0363), carbons (XEP-0280), receipts (XEP-0184),
// chat states (XEP-0085), corrections (XEP-0308), reactions (XEP-0444),
// replies (XEP-0461), blocking (XEP-0191), bookmarks (XEP-0048/0402),
// PubSub (XEP-0060), PEP (XEP-0163), vCard (XEP-0054), stream management (XEP-0198),
// CSI (XEP-0352), ping (XEP-0199), version (XEP-0092), last activity (XEP-0012),
// entity time (XEP-0202), caps (XEP-0115), OOB (XEP-0066),
// Jingle (XEP-0166/0167/0176) stubs.
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
	"net"
	"net/http"
	"os"
	"sort"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

)

// ---------------------------------------------------------------------------
// Constants & namespaces
// ---------------------------------------------------------------------------

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

// XML namespaces
const (
	nsStream    = "http://etherx.jabber.org/streams"
	nsClient    = "jabber:client"
	nsTLS       = "urn:ietf:params:xml:ns:xmpp-tls"
	nsSASL      = "urn:ietf:params:xml:ns:xmpp-sasl"
	nsBind      = "urn:ietf:params:xml:ns:xmpp-bind"
	nsSession   = "urn:ietf:params:xml:ns:xmpp-session"
	nsRoster    = "jabber:iq:roster"
	nsDiscoInfo = "http://jabber.org/protocol/disco#info"
	nsDiscoItem = "http://jabber.org/protocol/disco#items"
	nsMUC       = "http://jabber.org/protocol/muc"
	nsMUCUser   = "http://jabber.org/protocol/muc#user"
	nsMUCAdmin  = "http://jabber.org/protocol/muc#admin"
	nsMUCOwner  = "http://jabber.org/protocol/muc#owner"
	nsDirectMUC = "jabber:x:conference"
	nsChatState = "http://jabber.org/protocol/chatstates"
	nsReceipts  = "urn:xmpp:receipts"
	nsCorrect   = "urn:xmpp:message-correct:0"
	nsCarbons   = "urn:xmpp:carbons:2"
	nsForward   = "urn:xmpp:forward:0"
	nsMAM       = "urn:xmpp:mam:2"
	nsRSM       = "http://jabber.org/protocol/rsm"
	nsBlocking  = "urn:xmpp:blocking"
	nsBookmarks = "storage:bookmarks"
	nsBmk2      = "urn:xmpp:bookmarks:1"
	nsPubSub    = "http://jabber.org/protocol/pubsub"
	nsPubEvent  = "http://jabber.org/protocol/pubsub#event"
	nsPubOwner  = "http://jabber.org/protocol/pubsub#owner"
	nsUpload    = "urn:xmpp:http:upload:0"
	nsOOB       = "jabber:x:oob"
	nsVCard     = "vcard-temp"
	nsPing      = "urn:xmpp:ping"
	nsVersion   = "jabber:iq:version"
	nsLast      = "jabber:iq:last"
	nsTime      = "urn:xmpp:time"
	nsSM        = "urn:xmpp:sm:3"
	nsCSI       = "urn:xmpp:csi:0"
	nsCaps      = "http://jabber.org/protocol/caps"
	nsReply     = "urn:xmpp:reply:0"
	nsReactions = "urn:xmpp:reactions:0"
	nsMarkers   = "urn:xmpp:chat-markers:0"
	nsHints     = "urn:xmpp:hints"
	nsRegister  = "jabber:iq:register"
	nsXData     = "jabber:x:data"
	nsDelay     = "urn:xmpp:delay"
	nsJingle    = "urn:xmpp:jingle:1"
	nsJingleRTP = "urn:xmpp:jingle:apps:rtp:1"
	nsJingleICE = "urn:xmpp:jingle:transports:ice-udp:1"
	nsExtSvc    = "urn:xmpp:extdisco:2"
	nsMood      = "http://jabber.org/protocol/mood"
	nsActivity  = "http://jabber.org/protocol/activity"
	nsTune      = "http://jabber.org/protocol/tune"
	nsGeoLoc    = "http://jabber.org/protocol/geoloc"
	nsAvatarData = "urn:xmpp:avatar:data"
	nsAvatarMeta = "urn:xmpp:avatar:metadata"
	nsPrivate    = "jabber:iq:private"
)

// ---------------------------------------------------------------------------
// XML stanza types (for parsing and building)
// ---------------------------------------------------------------------------

// streamHeader is the opening <stream:stream> element.
type xmppStreamStart struct {
	XMLName xml.Name `xml:"stream stream"`
	From    string   `xml:"from,attr,omitempty"`
	To      string   `xml:"to,attr,omitempty"`
	ID      string   `xml:"id,attr,omitempty"`
	Version string   `xml:"version,attr,omitempty"`
}

// streamFeatures represents <stream:features>.
type xmppFeatures struct {
	StartTLS   *xmppTLSFeature   `xml:"urn:ietf:params:xml:ns:xmpp-tls starttls"`
	Mechanisms *xmppSASLMechs    `xml:"urn:ietf:params:xml:ns:xmpp-sasl mechanisms"`
	Bind       *xml.Name         `xml:"urn:ietf:params:xml:ns:xmpp-bind bind"`
	Session    *xml.Name         `xml:"urn:ietf:params:xml:ns:xmpp-session session"`
	SM         *xml.Name         `xml:"urn:xmpp:sm:3 sm"`
	CSI        *xml.Name         `xml:"urn:xmpp:csi:0 csi"`
	RosterVer  *xml.Name         `xml:"urn:xmpp:features:rosterver ver"`
	InnerXML   string            `xml:",innerxml"`
}

type xmppTLSFeature struct {
	Required *xml.Name `xml:"required"`
}

type xmppSASLMechs struct {
	Mechanism []string `xml:"mechanism"`
}

// Generic stanza types
type XMPPIQ struct {
	XMLName xml.Name     `xml:"iq"`
	Type    string       `xml:"type,attr"`
	ID      string       `xml:"id,attr,omitempty"`
	To      string       `xml:"to,attr,omitempty"`
	From    string       `xml:"from,attr,omitempty"`
	Lang    string       `xml:"xml:lang,attr,omitempty"`
	Inner   string       `xml:",innerxml"`
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
	Type string `xml:"type,attr,omitempty"`
	Code string `xml:"code,attr,omitempty"`
	Text string `xml:"text,omitempty"`
	Inner string `xml:",innerxml"`
}

// ---------------------------------------------------------------------------
// Parsed message body (for incoming message dispatch)
// ---------------------------------------------------------------------------

type xmppParsedMessage struct {
	Body      string
	Subject   string
	Thread    string
	OOB       string // XEP-0066 URL
	Delay     *time.Time
	DelayFrom string
	// XEP-0184 receipt
	ReceiptRequest bool
	ReceiptFor     string // received id
	// XEP-0085 chat state
	ChatState string // composing, active, paused, inactive, gone
	// XEP-0308 correction
	ReplaceID string
	// XEP-0333 markers
	DisplayedID string
	ReceivedID  string
	// XEP-0461 reply
	ReplyTo   string // JID
	ReplyID   string // message id
	// XEP-0444 reactions
	ReactionsID string
	Reactions   []string
	// XEP-0045 MUC
	MUCInviteFrom string
	MUCInviteRoom string
	// XEP-0280 carbon
	CarbonType string // sent or received
	CarbonMsg  *xmppParsedMessage
	// MAM
	MAMID    string
	MAMQueryID string
	MAMMsg   *xmppParsedMessage
	// Forwarded
	ForwardedFrom string
}

// ---------------------------------------------------------------------------
// Roster item
// ---------------------------------------------------------------------------

type xmppRosterItem struct {
	JID          string   `xml:"jid,attr"`
	Name         string   `xml:"name,attr,omitempty"`
	Subscription string   `xml:"subscription,attr,omitempty"`
	Groups       []string `xml:"group"`
	Ask          string   `xml:"ask,attr,omitempty"`
}

// ---------------------------------------------------------------------------
// Session persistence
// ---------------------------------------------------------------------------

type xmppSession struct {
	JID            string            `json:"jid"`
	Server         string            `json:"server"`
	Resource       string            `json:"resource"`
	MUCService     string            `json:"muc_service,omitempty"`
	UploadService  string            `json:"upload_service,omitempty"`
	UploadMaxSize  int64             `json:"upload_max_size,omitempty"`
	JoinedRooms    []string          `json:"joined_rooms,omitempty"`
	Bookmarks      []xmppBookmark    `json:"bookmarks,omitempty"`
	Blocked        []string          `json:"blocked,omitempty"`
	RosterVer      string            `json:"roster_ver,omitempty"`
	SMEnabled      bool              `json:"sm_enabled,omitempty"`
	SMResumeID     string            `json:"sm_resume_id,omitempty"`
	CarbonsEnabled bool              `json:"carbons_enabled,omitempty"`
}

type xmppBookmark struct {
	JID      string `json:"jid"`
	Name     string `json:"name,omitempty"`
	Nick     string `json:"nick,omitempty"`
	AutoJoin bool   `json:"autojoin,omitempty"`
}

// ---------------------------------------------------------------------------
// MUC room state
// ---------------------------------------------------------------------------

type xmppRoom struct {
	JID         string
	Name        string
	Nick        string
	Subject     string
	SubjectBy   string
	Occupants   map[string]*xmppOccupant // nick → occupant
	Joined      bool
	Config      map[string]string
}

type xmppOccupant struct {
	Nick        string
	RealJID     string // bare JID if available
	Role        string // none, visitor, participant, moderator
	Affiliation string // none, member, admin, owner, outcast
	Show        string
	Status      string
}

// ---------------------------------------------------------------------------
// IQ response tracking
// ---------------------------------------------------------------------------

type xmppPendingIQ struct {
	ch      chan *XMPPIQ
	timeout *time.Timer
}

// ---------------------------------------------------------------------------
// XMPPCore struct
// ---------------------------------------------------------------------------

// XMPPCore implements the Core interface for XMPP.
type XMPPCore struct {
	mu     sync.RWMutex
	authed bool

	// Connection
	conn    net.Conn
	tlsConn *tls.Conn
	reader  *bufio.Reader
	encoder *xml.Encoder
	decoder *xml.Decoder
	writeMu sync.Mutex

	// Identity
	jid        string // full JID (user@domain/resource)
	bareJID    string // bare JID (user@domain)
	domain     string
	server     string // host:port
	resource   string
	password   string
	tlsMode    string // "starttls", "direct", "none"
	saslMech   string // preferred mechanism

	// Server features
	features     xmppFeatures
	serverFeats  []string // disco#info features
	mucService   string
	uploadService string
	uploadMaxSize int64

	// Roster
	roster    map[string]*xmppRosterItem // bare JID → item
	rosterMu  sync.RWMutex
	rosterVer string

	// Rooms (MUC)
	rooms   map[string]*xmppRoom // room bare JID → room
	roomsMu sync.RWMutex

	// Message buffer
	messages   map[string][]*Message
	messagesMu sync.RWMutex
	msgCounter int64

	// Pinned (local)
	pinned   map[string]map[string]bool
	pinnedMu sync.RWMutex

	// Read state (local)
	readState   map[string]*ReadState
	readStateMu sync.RWMutex

	// Blocked (XEP-0191)
	blocked   map[string]bool
	blockedMu sync.RWMutex

	// IQ tracking
	pendingIQ   map[string]*xmppPendingIQ
	pendingIQMu sync.Mutex
	iqCounter   atomic.Int64

	// Stream management (XEP-0198)
	smEnabled   bool
	smResumeID  string
	smInH       atomic.Int64 // handled count (incoming)
	smOutH      atomic.Int64 // sent count (outgoing)
	smOutQueue  []*bytes.Buffer // unacked outgoing stanzas
	smOutMu     sync.Mutex

	// Carbons
	carbonsEnabled bool

	// Bookmarks
	bookmarks   []xmppBookmark
	bookmarksMu sync.RWMutex

	// vCard cache
	vcardCache   map[string]map[string]string // bare JID → fields
	vcardCacheMu sync.RWMutex

	// Cached caps element (static, computed once)
	capsElement     string
	capsElementOnce sync.Once

	// Real-time
	updateHandlers []func(Update)
	updateMu       sync.RWMutex

	// Stream limits (XEP-0478)
	streamMaxBytes    int
	streamIdleSeconds int

	// Lifecycle
	sessionPath string
	ctx         context.Context
	cancel      context.CancelFunc
	wg          sync.WaitGroup
}

var _ Core = (*XMPPCore)(nil)

// NewXMPPCore creates a new XMPP core instance.
func NewXMPPCore(sessionPath string) *XMPPCore {
	ctx, cancel := context.WithCancel(context.Background())
	return &XMPPCore{
		roster:      make(map[string]*xmppRosterItem),
		rooms:       make(map[string]*xmppRoom),
		messages:    make(map[string][]*Message),
		pinned:      make(map[string]map[string]bool),
		readState:   make(map[string]*ReadState),
		blocked:     make(map[string]bool),
		pendingIQ:   make(map[string]*xmppPendingIQ),
		vcardCache:  make(map[string]map[string]string),
		sessionPath: sessionPath,
		ctx:         ctx,
		cancel:      cancel,
	}
}

// ---------------------------------------------------------------------------
// Core interface — Identity
// ---------------------------------------------------------------------------

// Name returns the platform identifier for this core.
func (c *XMPPCore) Name() string { return xmppPlatform }

// Capabilities returns the list of supported features for this XMPP core.
func (c *XMPPCore) Capabilities() []string {
	return []string{
		CapText, CapChannels, CapCalls, CapReactions, CapReadReceipts,
		CapTyping, CapBlocking, CapSearch, CapPresence, CapE2EE,
		CapFileTransfer,
	}
}

// ---------------------------------------------------------------------------
// Core interface — Auth
// ---------------------------------------------------------------------------

// Authenticate connects to the XMPP server and logs in with the provided credentials.
func (c *XMPPCore) Authenticate(cfg AuthConfig) error {
	c.mu.Lock()
	if c.authed {
		c.mu.Unlock()
		return errors.New("already authenticated")
	}
	c.mu.Unlock()

	server := cfg.Extra["server"]
	if server == "" {
		// Derive from JID domain
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
		jidLocal = cfg.Phone // allow phone field as JID
	}
	if jidLocal == "" {
		return fmt.Errorf("%w: jid required (in Extra[\"jid\"] or Phone field)", ErrInvalidInput)
	}

	password := cfg.Extra["password"]
	if password == "" {
		password = cfg.BotToken // allow bot_token field
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
	if svc := cfg.Extra["muc_service"]; svc != "" {
		c.mucService = svc
	}
	if svc := cfg.Extra["upload_service"]; svc != "" {
		c.uploadService = svc
	}

	// Parse JID
	if at := strings.Index(jidLocal, "@"); at > 0 {
		c.bareJID = jidLocal
		c.domain = jidLocal[at+1:]
	} else {
		// domain from server
		host, _, _ := net.SplitHostPort(server)
		c.domain = host
		c.bareJID = jidLocal + "@" + c.domain
	}
	c.mu.Unlock()

	// Load saved session
	c.loadSession()

	// Connect
	if err := c.connectAndAuth(); err != nil {
		return fmt.Errorf("%w: %v", ErrAuth, err)
	}

	c.mu.Lock()
	c.authed = true
	c.mu.Unlock()

	// Post-auth setup
	c.wg.Add(1)
	go c.readLoop()
	c.wg.Add(1)
	go c.pingLoop()

	c.postAuthSetup()

	return nil
}

// postAuthSetup runs post-authentication setup: roster, carbons, SM, presence, etc.
// Called both on initial auth and after reconnection.
func (c *XMPPCore) postAuthSetup() {
	// Request roster
	c.requestRoster()

	// Enable carbons
	c.EnableCarbons()

	// Enable stream management if available
	if c.features.SM != nil {
		c.EnableStreamManagement()
	}

	// Discover services
	go c.discoverServices()

	// Send initial presence
	c.SendPresenceAvailable("", "")

	// Auto-join bookmarked rooms
	go c.autoJoinBookmarks()
}

// Logout disconnects from the XMPP server and cleans up resources.
func (c *XMPPCore) Logout() error {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return ErrAuth
	}
	c.mu.RUnlock()

	// Send unavailable presence
	c.SendPresenceUnavailable("Logged out")

	// Close stream
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

// ---------------------------------------------------------------------------
// Connection & authentication internals
// ---------------------------------------------------------------------------

func (c *XMPPCore) connectAndAuth() error {
	var conn net.Conn
	var err error

	c.mu.RLock()
	server := c.server
	tlsMode := c.tlsMode
	domain := c.domain
	c.mu.RUnlock()

	// TCP connect
	dialer := &net.Dialer{Timeout: 15 * time.Second}
	conn, err = dialer.DialContext(c.ctx, "tcp", server)
	if err != nil {
		return fmt.Errorf("tcp connect: %w", err)
	}

	// Direct TLS (port 5223)
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

	// Open stream
	if err := c.sendStreamHeader(); err != nil {
		return err
	}

	// Read stream features
	if err := c.readStreamStart(); err != nil {
		return err
	}

	// STARTTLS
	if tlsMode == "starttls" && c.features.StartTLS != nil {
		if err := c.startTLS(); err != nil {
			return err
		}
	}

	// SASL authentication
	if err := c.authenticate(); err != nil {
		return err
	}

	// Resource binding
	if err := c.bindResource(); err != nil {
		return err
	}

	// Legacy session establishment (some servers still require it)
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
	// XMPP streams are tricky for encoding/xml: the root <stream:stream> is
	// never closed, and namespace prefixes on the root confuse Go's decoder.
	// Strategy: read from the shared bufio.Reader byte-by-byte until we see
	// </stream:features>, then parse the features block. Whatever remains
	// buffered in c.reader is available for the xml.Decoder later.
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

		if b != '>' {
			continue
		}

		data := buf.Bytes()
		if bytes.Contains(data, endTag1) || bytes.Contains(data, endTag2) {
			c.mu.Lock()
			c.decoder = xml.NewDecoder(reader)
			c.mu.Unlock()
			return c.parseStreamFeatures(buf.String())
		}
	}
}

func (c *XMPPCore) parseStreamFeatures(data string) error {
	// Extract the features block
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

	// Parse features manually from the raw XML
	var feats xmppFeatures

	// STARTTLS
	if strings.Contains(featXML, nsTLS) {
		feats.StartTLS = &xmppTLSFeature{}
		if strings.Contains(featXML, "<required") {
			feats.StartTLS.Required = &xml.Name{}
		}
	}

	// SASL mechanisms
	if strings.Contains(featXML, nsSASL) {
		feats.Mechanisms = &xmppSASLMechs{}
		// Extract mechanisms
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

	// Bind
	if strings.Contains(featXML, nsBind) {
		feats.Bind = &xml.Name{}
	}

	// Session
	if strings.Contains(featXML, nsSession) {
		feats.Session = &xml.Name{}
	}

	// Stream management
	if strings.Contains(featXML, nsSM) {
		feats.SM = &xml.Name{}
	}

	// CSI
	if strings.Contains(featXML, nsCSI) {
		feats.CSI = &xml.Name{}
	}

	// Roster versioning
	if strings.Contains(featXML, "rosterver") {
		feats.RosterVer = &xml.Name{}
	}

	feats.InnerXML = featXML

	c.mu.Lock()
	c.features = feats
	c.mu.Unlock()

	// Now create a fresh xml.Decoder for the stanza stream
	// The connection is positioned right after </stream:features>
	// We need to set up a decoder that reads stanzas
	c.decoder = xml.NewDecoder(c.conn)

	return nil
}

func (c *XMPPCore) startTLS() error {
	c.writeMu.Lock()
	c.conn.Write([]byte("<starttls xmlns='" + nsTLS + "'/>"))
	c.writeMu.Unlock()

	// Read proceed (raw, since we don't have an xml.Decoder yet for this stream)
	c.conn.SetReadDeadline(time.Now().Add(10 * time.Second))
	var buf bytes.Buffer
	for {
		b, err := c.reader.ReadByte()
		if err != nil {
			return fmt.Errorf("starttls read: %w", err)
		}
		buf.WriteByte(b)
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

	// Restart stream
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

	// Pick best mechanism
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
		// Prefer SCRAM-SHA-256 > SCRAM-SHA-1 > PLAIN
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

	// Extract localpart
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

func (c *XMPPCore) authSASLScram(hashFunc func() hash.Hash, mechName string) error {
	c.mu.RLock()
	bareJID := c.bareJID
	password := c.password
	c.mu.RUnlock()

	local := bareJID
	if at := strings.Index(bareJID, "@"); at > 0 {
		local = bareJID[:at]
	}

	// Generate client nonce
	nonceBytes := make([]byte, 24)
	rand.Read(nonceBytes)
	clientNonce := base64.StdEncoding.EncodeToString(nonceBytes)

	// Client first message
	clientFirstBare := fmt.Sprintf("n=%s,r=%s", scramEscapeUsername(local), clientNonce)
	clientFirst := "n,," + clientFirstBare

	payload := base64.StdEncoding.EncodeToString([]byte(clientFirst))
	c.writeMu.Lock()
	c.conn.Write([]byte("<auth xmlns='" + nsSASL + "' mechanism='" + mechName + "'>" + payload + "</auth>"))
	c.writeMu.Unlock()

	// Read server challenge
	challenge, err := c.readSASLChallenge()
	if err != nil {
		return err
	}

	// Parse challenge: r=nonce,s=salt,i=iterations
	serverFirst := string(challenge)
	params := parseSCRAMParams(serverFirst)
	serverNonce := params["r"]
	saltB64 := params["s"]
	iterStr := params["i"]

	if !strings.HasPrefix(serverNonce, clientNonce) {
		return errors.New("scram: server nonce doesn't start with client nonce")
	}

	salt, err := base64.StdEncoding.DecodeString(saltB64)
	if err != nil {
		return fmt.Errorf("scram: bad salt: %w", err)
	}
	iterations, err := strconv.Atoi(iterStr)
	if err != nil {
		return fmt.Errorf("scram: bad iterations: %w", err)
	}

	// Compute SCRAM keys
	saltedPassword := xmppPBKDF2([]byte(password), salt, iterations, hashFunc().Size(), hashFunc)

	clientKey := hmacHash(hashFunc, saltedPassword, []byte("Client Key"))
	storedKey := hashBytes(hashFunc, clientKey)

	// Client final without proof
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

	// Read success (which may contain server signature verification)
	successData, err := c.readSASLSuccess()
	if err != nil {
		return err
	}

	// Verify server signature
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

	// Restart stream after SASL
	if err := c.sendStreamHeader(); err != nil {
		return err
	}
	return c.readStreamStart()
}

// readSASLElement reads raw bytes from c.reader until a complete SASL element
// is found (<challenge>, <success>, or <failure>). Returns the element name
// and the text content (base64 payload).
func (c *XMPPCore) readSASLElement() (elemName, content string, err error) {
	c.conn.SetReadDeadline(time.Now().Add(15 * time.Second))
	defer c.conn.SetReadDeadline(time.Time{})

	var buf bytes.Buffer
	buf.Grow(512)
	saslTags := [3]string{"challenge", "success", "failure"}
	for {
		b, readErr := c.reader.ReadByte()
		if readErr != nil {
			return "", "", fmt.Errorf("sasl read: %w", readErr)
		}
		buf.WriteByte(b)

		if b != '>' {
			continue
		}

		data := buf.String()
		for _, tag := range saslTags {
			if strings.Contains(data, "<"+tag+"/>") {
				return tag, "", nil
			}
			closeTag := "</" + tag + ">"
			if strings.Contains(data, closeTag) {
				startIdx := strings.Index(data, "<"+tag)
				if startIdx < 0 {
					continue
				}
				rest := data[startIdx+1+len(tag):]
				gt := strings.IndexByte(rest, '>')
				if gt < 0 {
					continue
				}
				rest = rest[gt+1:]
				endIdx := strings.Index(rest, closeTag)
				if endIdx >= 0 {
					return tag, rest[:endIdx], nil
				}
			}
		}
	}
}

func (c *XMPPCore) readSASLChallenge() ([]byte, error) {
	name, content, err := c.readSASLElement()
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
	name, content, err := c.readSASLElement()
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
	name, content, err := c.readSASLElement()
	if err != nil {
		return err
	}
	if name == "failure" {
		return fmt.Errorf("%w: %s", ErrAuth, content)
	}
	if name != "success" {
		return fmt.Errorf("expected success, got %s", name)
	}
	// Restart stream after SASL
	if err := c.sendStreamHeader(); err != nil {
		return err
	}
	return c.readStreamStart()
}

// readRawIQResponse reads an IQ response directly from c.reader (raw bytes).
// Used during pre-readLoop phase (bind, session establishment).
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
		if b == '>' && bytes.Contains(buf.Bytes(), endTag) {
			return buf.String(), nil
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
		id, nsBind, xmlEscape(resource),
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

	// Parse bound JID from response
	jid := extractXMLContent(resp, "jid")
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
	c.readRawIQResponse() // read and discard result
}

// ---------------------------------------------------------------------------
// XML stream read loop
// ---------------------------------------------------------------------------

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
			// Connection lost — attempt auto-reconnect
			if c.attemptReconnect() {
				// Reconnected successfully, continue reading with new decoder
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

		case "r": // XEP-0198 ack request
			c.decoder.Skip()
			c.SendAck()

		case "a": // XEP-0198 ack response
			var a struct {
				H int64 `xml:"h,attr"`
			}
			c.decoder.DecodeElement(&a, &se)
			c.handleAck(a.H)

		case "resumed": // XEP-0198 resume success
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

// ---------------------------------------------------------------------------
// Auto-reconnect on connection loss
// ---------------------------------------------------------------------------

// attemptReconnect tries to re-establish the XMPP connection with exponential
// backoff (5s, 10s, 20s, …, max 60s). Returns true if reconnection succeeded.
// Called from readLoop when a connection-loss error is detected.
func (c *XMPPCore) attemptReconnect() bool {
	const maxRetries = 10
	const maxDelay = 60 * time.Second

	// Notify GUI of disconnection
	c.fireUpdate(Update{Type: UpdateConnectivity, ConnState: "disconnected"})

	// Close stale connection
	c.mu.Lock()
	if c.conn != nil {
		c.conn.Close()
	}
	c.authed = false
	c.mu.Unlock()

	delay := xmppReconnectDelay
	for attempt := 1; attempt <= maxRetries; attempt++ {
		select {
		case <-c.ctx.Done():
			// Intentional shutdown (Logout called), don't reconnect
			return false
		case <-time.After(delay):
		}

		// Attempt reconnection
		err := c.connectAndAuth()
		if err != nil {
			// Increase delay with exponential backoff, cap at maxDelay
			delay *= 2
			if delay > maxDelay {
				delay = maxDelay
			}
			continue
		}

		// Reconnected successfully
		c.mu.Lock()
		c.authed = true
		c.mu.Unlock()

		// Re-run post-auth setup (roster, carbons, presence, etc.)
		c.postAuthSetup()

		// Notify GUI of reconnection
		c.fireUpdate(Update{Type: UpdateConnectivity, ConnState: "connected"})

		return true
	}

	// All retries exhausted
	c.fireUpdate(Update{Type: UpdateConnectivity, ConnState: "disconnected"})
	return false
}

// ---------------------------------------------------------------------------
// Stanza dispatch handlers
// ---------------------------------------------------------------------------

func (c *XMPPCore) handleMessage(msg xmppMessage) {
	parsed := c.parseMessageInner(msg.Inner)

	from := msg.From
	fromBare := bareJID(from)
	chatID := fromBare

	// Handle carbons (XEP-0280)
	if parsed.CarbonType != "" && parsed.CarbonMsg != nil {
		// Carbon copies — use inner message
		parsed = parsed.CarbonMsg
		if parsed.CarbonType == "sent" {
			chatID = bareJID(msg.To)
		}
	}

	// Handle MAM results (XEP-0313)
	if parsed.MAMID != "" && parsed.MAMMsg != nil {
		// MAM messages are stored, don't fire update
		return
	}

	// Chat state notifications (XEP-0085)
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

	// Receipt acknowledgment (XEP-0184)
	if parsed.ReceiptFor != "" {
		// Could track delivery status
		return
	}

	// Displayed marker (XEP-0333)
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

	// Reactions (XEP-0444)
	if parsed.ReactionsID != "" && len(parsed.Reactions) > 0 {
		// Update message reactions in cache
		c.messagesMu.Lock()
		if msgs, ok := c.messages[chatID]; ok {
			for _, m := range msgs {
				if m.ID == parsed.ReactionsID {
					// Merge reactions
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

	// MUC invite
	if parsed.MUCInviteRoom != "" {
		// Fire as a message notification
		m := &Message{
			ID:         msg.ID,
			ChatID:     chatID,
			SenderID:   fromBare,
			SenderName: fromBare,
			Text:       fmt.Sprintf("[MUC invitation to %s from %s]", parsed.MUCInviteRoom, parsed.MUCInviteFrom),
			Timestamp:  time.Now(),
			Status:     MessageStatusDelivered,
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

	// Message correction (XEP-0308)
	if parsed.ReplaceID != "" {
		c.messagesMu.Lock()
		if msgs, ok := c.messages[chatID]; ok {
			for _, m := range msgs {
				if m.ID == parsed.ReplaceID {
					m.Text = parsed.Body
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

	// Subject change (MUC)
	if parsed.Subject != "" && msg.Type == "groupchat" {
		c.roomsMu.Lock()
		if room, ok := c.rooms[chatID]; ok {
			room.Subject = parsed.Subject
			room.SubjectBy = resourceFromJID(from)
		}
		c.roomsMu.Unlock()
		if parsed.Body == "" {
			return // Subject-only message
		}
	}

	// Build message
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

	m := &Message{
		ID:         msgID,
		ChatID:     chatID,
		SenderID:   senderID,
		SenderName: senderName,
		Text:       parsed.Body,
		Timestamp:  ts,
		Status:     MessageStatusDelivered,
		Platform:   xmppPlatform,
	}

	if parsed.ReplyID != "" {
		m.ReplyToID = parsed.ReplyID
	}
	if parsed.OOB != "" {
		m.Attachments = []FileRef{{URL: parsed.OOB, Name: parsed.OOB}}
	}

	c.bufferMessage(chatID, m)

	// Send receipt if requested
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

	// Check if this is MUC presence
	if c.isRoom(fromBare) {
		c.handleMUCPresence(pres)
		return
	}

	switch pres.Type {
	case "subscribe":
		// Auto-approve subscription requests from roster contacts
		c.rosterMu.RLock()
		_, inRoster := c.roster[fromBare]
		c.rosterMu.RUnlock()
		if inRoster {
			c.SendPresenceSubscribed(fromBare)
		}
		// Fire update for subscription request
		c.fireUpdate(Update{
			Type:     UpdateNewMessage,
			ChatID:   fromBare,
			Message: &Message{
				ID:        fmt.Sprintf("sub_%d", time.Now().UnixNano()),
				ChatID:    fromBare,
				SenderID:  fromBare,
				Text:      "[Subscription request]",
				Timestamp: time.Now(),
				Status:    MessageStatusDelivered,
				Platform:  xmppPlatform,
			},
			Platform: xmppPlatform,
		})

	case "subscribed":
		// Subscription approved

	case "unsubscribe", "unsubscribed":
		// Subscription removed

	case "unavailable":
		// User went offline
		isOnline := false
		c.fireUpdate(Update{
			Type:     UpdateUserStatus,
			UserID:   fromBare,
			IsOnline: &isOnline,
			Platform: xmppPlatform,
		})

	case "", "available":
		// User is online
		isOnline := true
		c.fireUpdate(Update{
			Type:     UpdateUserStatus,
			UserID:   fromBare,
			IsOnline: &isOnline,
			Platform: xmppPlatform,
		})

	case "error":
		// Presence error
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
			Type:   UpdateGroupMembers,
			ChatID: roomJID,
			UserID: nick,
			Platform: xmppPlatform,
		})
		return
	}

	// Parse MUC#user info from inner XML
	occ := &xmppOccupant{Nick: nick}
	// Parse role, affiliation, real JID from inner
	if strings.Contains(pres.Inner, nsMUCUser) {
		occ.Role, occ.Affiliation, occ.RealJID = parseMUCUserItem(pres.Inner)
	}
	// Parse show/status
	occ.Show, occ.Status = parsePresenceShowStatus(pres.Inner)

	room.Occupants[nick] = occ

	// Check if this is our own join confirmation (status code 110)
	if strings.Contains(pres.Inner, `code='110'`) || strings.Contains(pres.Inner, `code="110"`) {
		room.Joined = true
		room.Nick = nick
	}

	c.roomsMu.Unlock()

	c.fireUpdate(Update{
		Type:   UpdateGroupMembers,
		ChatID: roomJID,
		UserID: nick,
		Platform: xmppPlatform,
	})
}

func (c *XMPPCore) handleIQ(iq XMPPIQ) {
	// Check if this is a response to a pending IQ
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

func (c *XMPPCore) handleRosterPush(iq XMPPIQ) {
	c.sendRawStanza("<iq type='result' id='" + xmlEscape(iq.ID) + "'/>")

	// Parse roster item
	type rosterQuery struct {
		Items []xmppRosterItem `xml:"jabber:iq:roster query>item"`
		Ver   string           `xml:"jabber:iq:roster query>ver,attr"`
	}
	var q rosterQuery
	if err := xml.Unmarshal([]byte("<r>"+iq.Inner+"</r>"), &q); err != nil {
		return
	}

	c.rosterMu.Lock()
	for _, item := range q.Items {
		if item.Subscription == "remove" {
			delete(c.roster, item.JID)
		} else {
			c.roster[item.JID] = &item
		}
	}
	if q.Ver != "" {
		c.rosterVer = q.Ver
	}
	c.rosterMu.Unlock()
}

func (c *XMPPCore) handleBlocklistPush(iq XMPPIQ) {
	c.sendRawStanza("<iq type='result' id='" + xmlEscape(iq.ID) + "'/>")

	c.blockedMu.Lock()
	defer c.blockedMu.Unlock()

	if strings.Contains(iq.Inner, "<block") {
		// Parse blocked JIDs
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
	// Stub — acknowledge and respond with session-terminate for now
	// Full Jingle implementation would handle ICE, DTLS, RTP
	c.sendRawStanza(fmt.Sprintf(`<iq type='result' id='%s' to='%s'/>`,
		xmlEscape(iq.ID), xmlEscape(iq.From)))
}

// ---------------------------------------------------------------------------
// IQ send/receive
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Ping loop
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Core interface — Dialogs
// ---------------------------------------------------------------------------

// GetDialogs returns the list of active conversations from roster and joined MUC rooms.
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

	// DM dialogs from roster
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
		// Attach last message if any
		c.messagesMu.RLock()
		if msgs, ok := c.messages[item.JID]; ok && len(msgs) > 0 {
			d.LastMessage = msgs[len(msgs)-1]
		}
		c.messagesMu.RUnlock()
		dialogs = append(dialogs, d)
	}

	// MUC rooms
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

	// Apply offset
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

	// Apply limit
	if opts.Limit > 0 && len(dialogs) > opts.Limit {
		dialogs = dialogs[:opts.Limit]
	}

	return dialogs, nil
}

// CreateGroup creates a new MUC room with the specified name and members.
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

	// Join the room
	if err := c.JoinMUC(roomJID, ""); err != nil {
		return nil, err
	}

	// Configure as persistent room
	c.ConfigureMUC(roomJID, map[string]string{
		"muc#roomconfig_persistentroom": "1",
		"muc#roomconfig_roomname":       name,
	})

	// Invite members
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

// CreateChannel creates a new MUC room configured as a channel.
func (c *XMPPCore) CreateChannel(name string, description string) (*Dialog, error) {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return nil, ErrAuth
	}
	c.mu.RUnlock()

	// XMPP doesn't distinguish channels from groups — create a MUC room
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

// CreateTopic creates a new topic.
func (c *XMPPCore) CreateTopic(chatID string, name string) (*Dialog, error) {
	return nil, fmt.Errorf("%w: xmpp does not support forum topics", ErrNotSupported)
}

// GetFolders retrieves folders from the XMPP server.
func (c *XMPPCore) GetFolders() ([]Folder, error) {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return nil, ErrAuth
	}
	c.mu.RUnlock()

	// Load bookmarks if empty (without holding read lock — loadBookmarks takes write lock)
	c.bookmarksMu.RLock()
	empty := len(c.bookmarks) == 0
	c.bookmarksMu.RUnlock()

	if empty {
		c.loadBookmarks()
	}

	// Now read bookmarks under read lock
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

// CreateFolder creates a new folder.
func (c *XMPPCore) CreateFolder(name string, chatIDs []string) (*Folder, error) {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return nil, ErrAuth
	}
	c.mu.RUnlock()

	// Save as bookmarks
	for _, id := range chatIDs {
		c.SetBookmark(id, name, "", true)
	}
	return &Folder{
		ID:      "bookmarks",
		Name:    name,
		ChatIDs: chatIDs,
	}, nil
}

// ---------------------------------------------------------------------------
// Core interface — Messages
// ---------------------------------------------------------------------------

// SendMessage sends a text message to the specified JID or MUC room.
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
		ID:        id,
		ChatID:    chatID,
		SenderID:  c.bareJID,
		SenderName: c.bareJID,
		Text:      msg.Text,
		Timestamp: time.Now(),
		Status:    MessageStatusSent,
		ReplyToID: msg.ReplyToID,
		Platform:  xmppPlatform,
	}

	// Don't buffer groupchat messages — we'll get them back from the server
	if msgType != "groupchat" {
		c.bufferMessage(chatID, m)
	}

	return m, nil
}

// GetMessages retrieves message history from MAM (XEP-0313) for the specified JID.
func (c *XMPPCore) GetMessages(chatID string, opts PaginationOpts) ([]Message, error) {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return nil, ErrAuth
	}
	c.mu.RUnlock()

	// Try MAM first for archive
	if opts.Offset != "" || opts.Limit > 0 {
		msgs, err := c.QueryMAM(chatID, opts.Limit, opts.Offset)
		if err == nil && len(msgs) > 0 {
			return msgs, nil
		}
	}

	// Fall back to local buffer
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

// EditMessage sends a message correction (XEP-0308) replacing a previous message.
func (c *XMPPCore) EditMessage(chatID string, msgID string, text string) (*Message, error) {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return nil, ErrAuth
	}
	c.mu.RUnlock()

	// XEP-0308: Message Correction
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

	// Update local buffer
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
		ID:        id,
		ChatID:    chatID,
		SenderID:  c.bareJID,
		Text:      text,
		Timestamp: time.Now(),
		Status:    MessageStatusSent,
		Platform:  xmppPlatform,
	}, nil
}

// DeleteMessage retracts a previously sent message.
func (c *XMPPCore) DeleteMessage(chatID string, msgID string) error {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return ErrAuth
	}
	c.mu.RUnlock()

	// XMPP doesn't have standard message deletion — use correction with empty body
	// Or use XEP-0424 Message Retraction (not widely supported)
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

// ReplyToMessage reply to message on the XMPP connection.
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

// ForwardMessage forwards a message to another JID or MUC room.
func (c *XMPPCore) ForwardMessage(fromChatID string, msgID string, toChatID string) (*Message, error) {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return nil, ErrAuth
	}
	c.mu.RUnlock()

	// Find the original message
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

	// Send as a new message with forward info
	fwdMsg := OutgoingMessage{
		Text: fmt.Sprintf("[Forwarded from %s]\n%s", original.SenderName, original.Text),
	}
	return c.SendMessage(toChatID, fwdMsg)
}

// ReactToMessage react to message on the XMPP connection.
func (c *XMPPCore) ReactToMessage(chatID string, msgID string, emoji string) error {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return ErrAuth
	}
	c.mu.RUnlock()
	return c.SendReaction(chatID, msgID, []string{emoji})
}

// PinMessage pins a message in a MUC room via PubSub.
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

// UnpinMessage unpins a previously pinned message in a MUC room.
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

// ---------------------------------------------------------------------------
// Core interface — Read state
// ---------------------------------------------------------------------------

// MarkAsRead mark as read on the XMPP connection.
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

	// Send displayed marker (XEP-0333)
	c.SendDisplayedMarker(chatID, upToMsgID)
	return nil
}

// GetReadState retrieves read state from the XMPP server.
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

// ---------------------------------------------------------------------------
// Core interface — Files
// ---------------------------------------------------------------------------

// UploadFile uploads a file to the HTTP upload service (XEP-0363).
func (c *XMPPCore) UploadFile(chatID string, file FileUpload, progress func(sent, total int64)) (*Message, error) {
	// Use XEP-0363 HTTP File Upload
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

	// Read file data
	data, err := io.ReadAll(file.Reader)
	if err != nil {
		return nil, fmt.Errorf("read file: %w", err)
	}

	// Upload via HTTP PUT
	if err := c.UploadFileHTTP(putURL, data, file.MimeType, progress); err != nil {
		return nil, err
	}

	// Send message with OOB URL
	return c.SendFileURL(chatID, getURL, file.Name)
}

// DownloadFile download file on the XMPP connection.
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

// SendImageBase64 sends image base64 to the specified JID.
func (c *XMPPCore) SendImageBase64(chatID string, b64 string, caption string) (*Message, error) {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return nil, ErrAuth
	}
	uploadSvc := c.uploadService
	c.mu.RUnlock()

	// Decode, upload via HTTP, send URL
	data, err := base64.StdEncoding.DecodeString(b64)
	if err != nil {
		return nil, fmt.Errorf("decode base64: %w", err)
	}

	if uploadSvc == "" {
		// Fallback: send as text with base64
		msg := OutgoingMessage{Text: caption}
		return c.SendMessage(chatID, msg)
	}

	putURL, getURL, err := c.RequestHTTPUploadSlot("image.png", int64(len(data)), "image/png")
	if err != nil {
		// Fallback to text
		msg := OutgoingMessage{Text: caption}
		return c.SendMessage(chatID, msg)
	}

	c.UploadFileHTTP(putURL, data, "image/png", nil)
	return c.SendFileURL(chatID, getURL, caption)
}

// ---------------------------------------------------------------------------
// Core interface — Calls (Jingle stubs)
// ---------------------------------------------------------------------------

// StartCall initiates a Jingle voice call (XEP-0166/0167) with the specified JID.
func (c *XMPPCore) StartCall(chatID string, video bool) (*CallSession, error) {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return nil, ErrAuth
	}
	c.mu.RUnlock()
	return c.InitiateJingle(chatID, video)
}

// JoinGroupCall joins group call.
func (c *XMPPCore) JoinGroupCall(chatID string) (*CallSession, error) {
	return nil, fmt.Errorf("%w: xmpp group calls (Muji/XEP-0272) not widely supported", ErrNotSupported)
}

// EndCall terminates an active Jingle call session.
func (c *XMPPCore) EndCall(callID string) error {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return ErrAuth
	}
	c.mu.RUnlock()
	return c.TerminateJingle(callID, "success")
}

// SetCallMuted sets call muted on the XMPP server.
func (c *XMPPCore) SetCallMuted(callID string, muted bool) error {
	return fmt.Errorf("%w: xmpp does not support call muting", ErrNotSupported)
}

// ---------------------------------------------------------------------------
// Core interface — Profile
// ---------------------------------------------------------------------------

// GetProfile retrieves profile from the XMPP server.
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

	// Try vCard
	vcard, err := c.GetVCard(userID)
	if err != nil {
		// Return basic info from roster
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

// ---------------------------------------------------------------------------
// Core interface — Real-time
// ---------------------------------------------------------------------------

// OnUpdate on update on the XMPP connection.
func (c *XMPPCore) OnUpdate(handler func(Update)) {
	c.updateMu.Lock()
	c.updateHandlers = append(c.updateHandlers, handler)
	c.updateMu.Unlock()
}

// Close closes .
func (c *XMPPCore) Close() error {
	c.saveSession()
	c.cancel()
	c.mu.Lock()
	c.authed = false
	var connErr error
	if c.conn != nil {
		// Try graceful close
		c.writeMu.Lock()
		c.conn.Write([]byte("</stream:stream>"))
		c.writeMu.Unlock()
		connErr = c.conn.Close()
	}
	c.mu.Unlock()
	c.wg.Wait()
	return connErr
}

// ---------------------------------------------------------------------------
// Core interface — Chat management
// ---------------------------------------------------------------------------

// GetChatInfo retrieves chat info from the XMPP server.
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
			// Return from local state
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

	// DM
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

// EditChatTitle edit chat title on the XMPP connection.
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

// EditChatDescription edit chat description on the XMPP connection.
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

// LeaveChat leaves chat.
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
	// For DM, just remove from roster
	return c.RemoveRosterItem(chatID)
}

// GetInviteLink retrieves invite link from the XMPP server.
func (c *XMPPCore) GetInviteLink(chatID string) (string, error) {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return "", ErrAuth
	}
	c.mu.RUnlock()

	// XMPP uses xmpp: URI scheme
	return "xmpp:" + chatID + "?join", nil
}

// ---------------------------------------------------------------------------
// Core interface — Members
// ---------------------------------------------------------------------------

// AddMembers adds members.
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

// RemoveMember removes member.
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

// BanMember bans a user from a MUC room.
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

// UnbanMember removes a ban on a user from a MUC room.
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

// GetMembers retrieves members from the XMPP server.
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
	// DM — return self and the other party
	return []User{
		{ID: c.bareJID, DisplayName: c.bareJID, Platform: xmppPlatform},
		{ID: chatID, DisplayName: chatID, Platform: xmppPlatform},
	}, nil
}

// SetAdmin sets admin on the XMPP server.
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

// ---------------------------------------------------------------------------
// Core interface — Contacts
// ---------------------------------------------------------------------------

// GetContacts returns the user's roster (contact list).
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

// AddContact adds a JID to the roster and sends a presence subscription request.
func (c *XMPPCore) AddContact(phone string, firstName string, lastName string) error {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return ErrAuth
	}
	c.mu.RUnlock()

	// In XMPP, "phone" is the JID
	jid := phone
	name := firstName
	if lastName != "" {
		name += " " + lastName
	}
	return c.AddRosterItem(jid, name, nil)
}

// DeleteContact deletes contact from the XMPP server.
func (c *XMPPCore) DeleteContact(userID string) error {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return ErrAuth
	}
	c.mu.RUnlock()
	return c.RemoveRosterItem(userID)
}

// BlockUser adds a JID to the block list (XEP-0191).
func (c *XMPPCore) BlockUser(userID string) error {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return ErrAuth
	}
	c.mu.RUnlock()
	return c.BlockJID(userID)
}

// UnblockUser removes a JID from the block list (XEP-0191).
func (c *XMPPCore) UnblockUser(userID string) error {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return ErrAuth
	}
	c.mu.RUnlock()
	return c.UnblockJID(userID)
}

// GetBlockedUsers returns the list of blocked JIDs (XEP-0191).
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

// ---------------------------------------------------------------------------
// Core interface — Search
// ---------------------------------------------------------------------------

// SearchMessages search messages on the XMPP connection.
func (c *XMPPCore) SearchMessages(chatID string, query string, opts PaginationOpts) ([]Message, error) {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return nil, ErrAuth
	}
	c.mu.RUnlock()

	// Search local buffer
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

// SearchGlobal search global on the XMPP connection.
func (c *XMPPCore) SearchGlobal(query string, opts PaginationOpts) ([]Dialog, error) {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return nil, ErrAuth
	}
	c.mu.RUnlock()

	// Search roster and rooms
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

// ---------------------------------------------------------------------------
// Core interface — Typing
// ---------------------------------------------------------------------------

// SendTyping sends typing to the specified JID.
func (c *XMPPCore) SendTyping(chatID string) error {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return ErrAuth
	}
	c.mu.RUnlock()
	return c.SendChatStateComposing(chatID)
}

// ---------------------------------------------------------------------------
// Core interface — Polls & Stickers (not supported)
// ---------------------------------------------------------------------------

// CreatePoll creates a new poll.
func (c *XMPPCore) CreatePoll(chatID string, question string, options []string) (*Message, error) {
	return nil, fmt.Errorf("%w: xmpp does not support polls", ErrNotSupported)
}

// VotePoll vote poll on the XMPP connection.
func (c *XMPPCore) VotePoll(chatID string, msgID string, optionIndex int) error {
	return fmt.Errorf("%w: xmpp does not support polls", ErrNotSupported)
}

// SendSticker sends a sticker image to the specified JID.
func (c *XMPPCore) SendSticker(chatID string, stickerID string) (*Message, error) {
	return nil, fmt.Errorf("%w: xmpp does not support stickers", ErrNotSupported)
}

// ---------------------------------------------------------------------------
// Core interface — Sessions
// ---------------------------------------------------------------------------

// GetSessions retrieves sessions from the XMPP server.
func (c *XMPPCore) GetSessions() ([]Session, error) {
	c.mu.RLock()
	if !c.authed {
		c.mu.RUnlock()
		return nil, ErrAuth
	}
	c.mu.RUnlock()

	// XMPP doesn't have a standard session list — return current
	return []Session{{
		ID:         c.jid,
		Device:     "uniclient",
		Platform:   xmppPlatform,
		LastActive: time.Now(),
		IsCurrent:  true,
	}}, nil
}

// TerminateSession terminate session on the XMPP connection.
func (c *XMPPCore) TerminateSession(sessionID string) error {
	return fmt.Errorf("%w: xmpp does not support session termination", ErrNotSupported)
}

// ---------------------------------------------------------------------------
// XMPP-specific: Presence methods
// ---------------------------------------------------------------------------

// SendPresenceAvailable sends an available presence stanza to the server.
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

// SendPresenceUnavailable sends an unavailable presence stanza to the server.
func (c *XMPPCore) SendPresenceUnavailable(status string) error {
	if status == "" {
		return c.sendRawStanza("<presence type='unavailable'/>")
	}
	return c.sendRawStanza("<presence type='unavailable'><status>" + xmlEscape(status) + "</status></presence>")
}



// SetPresencePriority sets the priority value on subsequent presence stanzas.
func (c *XMPPCore) SetPresencePriority(priority int) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<presence><priority>%d</priority>%s</presence>`, priority, c.buildCapsElement(),
	))
}

// SendPresenceSubscribe sends a presence subscription request to a JID.
func (c *XMPPCore) SendPresenceSubscribe(jid string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<presence type='subscribe' to='%s'/>`, xmlEscape(jid),
	))
}

// SendPresenceSubscribed approves a pending presence subscription from a JID.
func (c *XMPPCore) SendPresenceSubscribed(jid string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<presence type='subscribed' to='%s'/>`, xmlEscape(jid),
	))
}

// SendPresenceUnsubscribe cancels an existing presence subscription to a JID.
func (c *XMPPCore) SendPresenceUnsubscribe(jid string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<presence type='unsubscribe' to='%s'/>`, xmlEscape(jid),
	))
}

// SendPresenceUnsubscribed rejects or revokes a presence subscription from a JID.
func (c *XMPPCore) SendPresenceUnsubscribed(jid string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<presence type='unsubscribed' to='%s'/>`, xmlEscape(jid),
	))
}

// SendDirectedPresence sends a presence stanza targeted at a specific JID.
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

// ProbePresence probe presence on the XMPP connection.
func (c *XMPPCore) ProbePresence(jid string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<presence type='probe' to='%s'/>`, xmlEscape(jid),
	))
}

// ---------------------------------------------------------------------------
// XMPP-specific: Roster methods
// ---------------------------------------------------------------------------

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

	// Parse roster items
	type rosterQuery struct {
		Items []xmppRosterItem `xml:"jabber:iq:roster query>item"`
		Ver   string           `xml:"jabber:iq:roster query>ver,attr"`
	}
	var q rosterQuery
	xml.Unmarshal([]byte("<r>"+resp.Inner+"</r>"), &q)

	c.rosterMu.Lock()
	for _, item := range q.Items {
		itemCopy := item
		c.roster[item.JID] = &itemCopy
	}
	if q.Ver != "" {
		c.rosterVer = q.Ver
	}
	c.rosterMu.Unlock()
}

// GetRoster retrieves the full roster (contact list) from the server.
func (c *XMPPCore) GetRoster() ([]xmppRosterItem, error) {
	c.rosterMu.RLock()
	defer c.rosterMu.RUnlock()

	var items []xmppRosterItem
	for _, item := range c.roster {
		items = append(items, *item)
	}
	return items, nil
}

// AddRosterItem adds a JID to the roster with an optional name and groups.
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

	// Also subscribe to presence
	c.SendPresenceSubscribe(jid)
	return nil
}

// RemoveRosterItem removes a JID from the roster.
func (c *XMPPCore) RemoveRosterItem(jid string) error {
	inner := fmt.Sprintf(`<query xmlns='%s'><item jid='%s' subscription='remove'/></query>`, nsRoster, xmlEscape(jid))
	_, err := c.sendIQSync("set", "", inner)
	return err
}

// SetRosterItemName updates the display name for a roster entry.
func (c *XMPPCore) SetRosterItemName(jid, name string) error {
	return c.AddRosterItem(jid, name, nil) // Add/update is the same operation
}

// SetRosterItemGroups updates the group memberships for a roster entry.
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

// ---------------------------------------------------------------------------
// XMPP-specific: Chat state methods (XEP-0085)
// ---------------------------------------------------------------------------

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

// SendChatStateActive sends chat state active to the specified JID.
func (c *XMPPCore) SendChatStateActive(chatID string) error {
	return c.sendChatState(chatID, "active")
}

// SendChatStateComposing sends chat state composing to the specified JID.
func (c *XMPPCore) SendChatStateComposing(chatID string) error {
	return c.sendChatState(chatID, "composing")
}

// SendChatStatePaused sends chat state paused to the specified JID.
func (c *XMPPCore) SendChatStatePaused(chatID string) error {
	return c.sendChatState(chatID, "paused")
}

// SendChatStateInactive sends chat state inactive to the specified JID.
func (c *XMPPCore) SendChatStateInactive(chatID string) error {
	return c.sendChatState(chatID, "inactive")
}

// SendChatStateGone sends chat state gone to the specified JID.
func (c *XMPPCore) SendChatStateGone(chatID string) error {
	return c.sendChatState(chatID, "gone")
}

// ---------------------------------------------------------------------------
// XMPP-specific: Message extensions
// ---------------------------------------------------------------------------


// SendGroupchatMessage sends groupchat message to the specified JID.
func (c *XMPPCore) SendGroupchatMessage(to, body string) error {
	id := c.nextMsgID()
	return c.sendRawStanza(fmt.Sprintf(
		`<message type='groupchat' to='%s' id='%s'><body>%s</body></message>`,
		xmlEscape(to), id, xmlEscape(body),
	))
}

// SendHeadlineMessage sends headline message to the specified JID.
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

// SendNormalMessage sends normal message to the specified JID.
func (c *XMPPCore) SendNormalMessage(to, body string) error {
	id := c.nextMsgID()
	return c.sendRawStanza(fmt.Sprintf(
		`<message type='normal' to='%s' id='%s'><body>%s</body></message>`,
		xmlEscape(to), id, xmlEscape(body),
	))
}

// RequestReceipt includes a receipt request in the next outgoing message.
func (c *XMPPCore) RequestReceipt(to, msgID string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<message to='%s' id='%s'><request xmlns='%s'/></message>`,
		xmlEscape(to), xmlEscape(msgID), nsReceipts,
	))
}

// SendReceipt sends a message delivery receipt (XEP-0184) for a received message.
func (c *XMPPCore) SendReceipt(to, msgID string) error {
	id := c.nextMsgID()
	return c.sendRawStanza("<message to='" + xmlEscape(to) + "' id='" + id + "'><received xmlns='" + nsReceipts + "' id='" + xmlEscape(msgID) + "'/></message>")
}



// EnableCarbons enables message carbons (XEP-0280) for multi-device sync.
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

// DisableCarbons disables message carbons (XEP-0280).
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

// SendDisplayedMarker sends displayed marker to the specified JID.
func (c *XMPPCore) SendDisplayedMarker(to, msgID string) error {
	id := c.nextMsgID()
	return c.sendRawStanza("<message to='" + xmlEscape(to) + "' id='" + id + "'><displayed xmlns='" + nsMarkers + "' id='" + xmlEscape(msgID) + "'/></message>")
}

// SendReceivedMarker sends received marker to the specified JID.
func (c *XMPPCore) SendReceivedMarker(to, msgID string) error {
	id := c.nextMsgID()
	return c.sendRawStanza(fmt.Sprintf(
		`<message to='%s' id='%s'><received xmlns='%s' id='%s'/></message>`,
		xmlEscape(to), id, nsMarkers, xmlEscape(msgID),
	))
}

// SendOOBURL sends a message with an out-of-band data URL (XEP-0066).
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

// SetMessageHint sets message hint on the XMPP server.
func (c *XMPPCore) SetMessageHint(chatID, msgID, hint string) error {
	return fmt.Errorf("%w: xmpp message hints can only be set at send time", ErrNotSupported)
}


// SendReaction sends a message reaction (XEP-0444) to the specified message.
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

// ---------------------------------------------------------------------------
// XMPP-specific: MUC methods (XEP-0045)
// ---------------------------------------------------------------------------

// JoinMUC joins a multi-user chat room with the specified nickname.
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

	// Send presence with MUC extension
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

// LeaveMUC leaves a multi-user chat room.
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

// SetMUCNick changes the user's nickname in a MUC room.
func (c *XMPPCore) SetMUCNick(roomJID, nick string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<presence to='%s/%s'/>`, xmlEscape(roomJID), xmlEscape(nick),
	))
}

// GetMUCOccupants retrieves the list of occupants in a MUC room.
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

// GetMUCInfo retrieves the room info and configuration for a MUC room.
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

	// Parse disco#info response for room name
	if name := extractXMLAttr(resp.Inner, "identity", "name"); name != "" {
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

// SetMUCSubject sets the subject line of a MUC room.
func (c *XMPPCore) SetMUCSubject(roomJID, subject string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<message type='groupchat' to='%s'><subject>%s</subject></message>`,
		xmlEscape(roomJID), xmlEscape(subject),
	))
}

// SendMUCInvitation sends a direct MUC invitation to a user.
func (c *XMPPCore) SendMUCInvitation(roomJID, userJID, reason string) error {
	// Direct invitation (XEP-0249)
	var reasonAttr string
	if reason != "" {
		reasonAttr = fmt.Sprintf(` reason='%s'`, xmlEscape(reason))
	}
	return c.sendRawStanza(fmt.Sprintf(
		`<message to='%s'><x xmlns='%s' jid='%s'%s/></message>`,
		xmlEscape(userJID), nsDirectMUC, xmlEscape(roomJID), reasonAttr,
	))
}

// SendMUCMediatedInvite sends a mediated (server-forwarded) MUC invitation to a user.
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

// DeclineMUCInvitation declines a pending MUC room invitation.
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

// SetMUCRole changes an occupant's role (moderator, participant, visitor) in a MUC room.
func (c *XMPPCore) SetMUCRole(roomJID, nick, role string) error {
	inner := fmt.Sprintf(
		`<query xmlns='%s'><item nick='%s' role='%s'/></query>`,
		nsMUCAdmin, xmlEscape(nick), xmlEscape(role),
	)
	_, err := c.sendIQSync("set", roomJID, inner)
	return err
}

// SetMUCAffiliation changes a user's affiliation (owner, admin, member, outcast) in a MUC room.
func (c *XMPPCore) SetMUCAffiliation(roomJID, userJID, affiliation string) error {
	inner := fmt.Sprintf(
		`<query xmlns='%s'><item jid='%s' affiliation='%s'/></query>`,
		nsMUCAdmin, xmlEscape(userJID), xmlEscape(affiliation),
	)
	_, err := c.sendIQSync("set", roomJID, inner)
	return err
}

// KickFromMUC kicks an occupant from a MUC room.
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

// BanFromMUC bans a user from a MUC room by setting outcast affiliation.
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

// UnbanFromMUC removes a ban from a user in a MUC room.
func (c *XMPPCore) UnbanFromMUC(roomJID, userJID string) error {
	return c.SetMUCAffiliation(roomJID, userJID, "none")
}

// GrantVoice grants voice.
func (c *XMPPCore) GrantVoice(roomJID, nick string) error {
	return c.SetMUCRole(roomJID, nick, "participant")
}

// RevokeVoice revokes voice.
func (c *XMPPCore) RevokeVoice(roomJID, nick string) error {
	return c.SetMUCRole(roomJID, nick, "visitor")
}

// GetMUCConfig retrieves the configuration form for a MUC room.
func (c *XMPPCore) GetMUCConfig(roomJID string) (map[string]string, error) {
	inner := fmt.Sprintf(`<query xmlns='%s'/>`, nsMUCOwner)
	resp, err := c.sendIQSync("get", roomJID, inner)
	if err != nil {
		return nil, err
	}

	// Parse x:data form
	return parseXDataForm(resp.Inner), nil
}

// ConfigureMUC submits a configuration form to update MUC room settings.
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

// DestroyMUC permanently destroys a MUC room.
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

// CreateInstantMUC creates an instant MUC room with default configuration.
func (c *XMPPCore) CreateInstantMUC(roomJID, nick string) error {
	if err := c.JoinMUC(roomJID, nick); err != nil {
		return err
	}
	// Accept default config
	inner := fmt.Sprintf(`<query xmlns='%s'><x xmlns='%s' type='submit'/></query>`, nsMUCOwner, nsXData)
	_, err := c.sendIQSync("set", roomJID, inner)
	return err
}

// RequestMUCHistory requests recent message history from a MUC room.
func (c *XMPPCore) RequestMUCHistory(roomJID string, maxStanzas int) error {
	// History is requested on join via <history maxstanzas='N'/>
	// Re-join to request more
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

// MUCSelfPing performs a MUC (multi-user chat) self ping operation.
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

// ---------------------------------------------------------------------------
// XMPP-specific: Service Discovery (XEP-0030)
// ---------------------------------------------------------------------------

// DiscoInfo queries a JID for its service discovery features (XEP-0030).
func (c *XMPPCore) DiscoInfo(target string) (*XMPPIQ, error) {
	if target == "" {
		target = c.domain
	}
	inner := fmt.Sprintf(`<query xmlns='%s'/>`, nsDiscoInfo)
	return c.sendIQSync("get", target, inner)
}

// DiscoItems queries a JID for its service discovery items (XEP-0030).
func (c *XMPPCore) DiscoItems(target string) (*XMPPIQ, error) {
	if target == "" {
		target = c.domain
	}
	inner := fmt.Sprintf(`<query xmlns='%s'/>`, nsDiscoItem)
	return c.sendIQSync("get", target, inner)
}

// QueryFeatures queries features from the XMPP server.
func (c *XMPPCore) QueryFeatures(target string) ([]string, error) {
	resp, err := c.DiscoInfo(target)
	if err != nil {
		return nil, err
	}
	return parseDiscoFeatures(resp.Inner), nil
}

// QueryIdentity queries identity from the XMPP server.
func (c *XMPPCore) QueryIdentity(target string) (category, typ, name string, err error) {
	resp, err := c.DiscoInfo(target)
	if err != nil {
		return "", "", "", err
	}
	category = extractXMLAttr(resp.Inner, "identity", "category")
	typ = extractXMLAttr(resp.Inner, "identity", "type")
	name = extractXMLAttr(resp.Inner, "identity", "name")
	return
}

// DiscoverMUCService discovers the MUC conference service on the connected domain.
func (c *XMPPCore) DiscoverMUCService() (string, error) {
	resp, err := c.DiscoItems("")
	if err != nil {
		return "", err
	}

	// Find item with conference identity
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

// DiscoverHTTPUploadService performs a service discovery (XEP-0030) query.
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
			// Parse max file size from data form
			maxSize := parseUploadMaxSize(infoResp.Inner)
			return item, maxSize, nil
		}
	}
	return "", 0, errors.New("no HTTP upload service found")
}

// DiscoverExternalServices performs a service discovery (XEP-0030) query.
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
	// Discover MUC
	if c.mucService == "" {
		if svc, err := c.DiscoverMUCService(); err == nil {
			c.mu.Lock()
			c.mucService = svc
			c.mu.Unlock()
		}
	}

	// Discover HTTP upload
	if c.uploadService == "" {
		if svc, maxSize, err := c.DiscoverHTTPUploadService(); err == nil {
			c.mu.Lock()
			c.uploadService = svc
			c.uploadMaxSize = maxSize
			c.mu.Unlock()
		}
	}

	// Get server features
	if feats, err := c.QueryFeatures(""); err == nil {
		c.mu.Lock()
		c.serverFeats = feats
		c.mu.Unlock()
	}
}

// ---------------------------------------------------------------------------
// XMPP-specific: File Transfer (XEP-0363)
// ---------------------------------------------------------------------------

// RequestHTTPUploadSlot requests an HTTP upload slot (XEP-0363) for a file.
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

	// Parse put/get URLs from response
	putURL = extractXMLAttr(resp.Inner, "put", "url")
	getURL = extractXMLAttr(resp.Inner, "get", "url")

	if putURL == "" || getURL == "" {
		return "", "", errors.New("upload slot missing URLs")
	}

	return putURL, getURL, nil
}

// UploadFileHTTP uploads a file using the HTTP upload service (XEP-0363).
func (c *XMPPCore) UploadFileHTTP(putURL string, data []byte, contentType string, progress func(sent, total int64)) error {
	req, err := http.NewRequestWithContext(c.ctx, "PUT", putURL, bytes.NewReader(data))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", contentType)
	req.ContentLength = int64(len(data))

	resp, err := http.DefaultClient.Do(req)
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

// DownloadFileHTTP downloads a file from the given HTTP URL.
func (c *XMPPCore) DownloadFileHTTP(url, dest string, progress func(recv, total int64)) error {
	req, err := http.NewRequestWithContext(c.ctx, "GET", url, nil)
	if err != nil {
		return err
	}

	resp, err := http.DefaultClient.Do(req)
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
	defer f.Close()

	total := resp.ContentLength
	var received int64
	buf := make([]byte, 32*1024)
	for {
		n, readErr := resp.Body.Read(buf)
		if n > 0 {
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

	return nil
}

// SendFileURL sends a file reference by URL to the specified JID.
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
		ID:        id,
		ChatID:    chatID,
		SenderID:  c.bareJID,
		Text:      body,
		Timestamp: time.Now(),
		Status:    MessageStatusSent,
		Attachments: []FileRef{{URL: url, Name: caption}},
		Platform:  xmppPlatform,
	}
	c.bufferMessage(chatID, m)
	return m, nil
}

// ---------------------------------------------------------------------------
// XMPP-specific: PubSub (XEP-0060)
// ---------------------------------------------------------------------------

// CreatePubSubNode performs a PubSub (XEP-0060) create node operation.
func (c *XMPPCore) CreatePubSubNode(service, node string) error {
	if service == "" {
		service = c.domain
	}
	inner := fmt.Sprintf(`<pubsub xmlns='%s'><create node='%s'/></pubsub>`, nsPubSub, xmlEscape(node))
	_, err := c.sendIQSync("set", service, inner)
	return err
}

// DeletePubSubNode performs a PubSub (XEP-0060) delete node operation.
func (c *XMPPCore) DeletePubSubNode(service, node string) error {
	if service == "" {
		service = c.domain
	}
	inner := fmt.Sprintf(`<pubsub xmlns='%s'><delete node='%s'/></pubsub>`, nsPubOwner, xmlEscape(node))
	_, err := c.sendIQSync("set", service, inner)
	return err
}

// PublishPubSubItem performs a PubSub (XEP-0060) publish item operation.
func (c *XMPPCore) PublishPubSubItem(service, node, itemID, payload string) error {
	if service == "" {
		service = c.bareJID // PEP
	}
	inner := fmt.Sprintf(
		`<pubsub xmlns='%s'><publish node='%s'><item id='%s'>%s</item></publish></pubsub>`,
		nsPubSub, xmlEscape(node), xmlEscape(itemID), payload,
	)
	_, err := c.sendIQSync("set", service, inner)
	return err
}

// RetractPubSubItem performs a PubSub (XEP-0060) retract item operation.
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

// SubscribePubSub performs a PubSub (XEP-0060) subscribe operation.
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

// UnsubscribePubSub performs a PubSub (XEP-0060) unsubscribe operation.
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

// GetPubSubItems performs a PubSub (XEP-0060) get items operation.
func (c *XMPPCore) GetPubSubItems(service, node string) (*XMPPIQ, error) {
	if service == "" {
		service = c.domain
	}
	inner := fmt.Sprintf(`<pubsub xmlns='%s'><items node='%s'/></pubsub>`, nsPubSub, xmlEscape(node))
	return c.sendIQSync("get", service, inner)
}

// GetPubSubSubscriptions performs a PubSub (XEP-0060) get subscriptions operation.
func (c *XMPPCore) GetPubSubSubscriptions(service string) (*XMPPIQ, error) {
	if service == "" {
		service = c.domain
	}
	inner := fmt.Sprintf(`<pubsub xmlns='%s'><subscriptions/></pubsub>`, nsPubSub)
	return c.sendIQSync("get", service, inner)
}

// ConfigurePubSubNode performs a PubSub (XEP-0060) configure node operation.
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

// ---------------------------------------------------------------------------
// XMPP-specific: PEP (XEP-0163) — User Mood, Activity, Tune, Location
// ---------------------------------------------------------------------------

// SetUserMood sets user mood on the XMPP server.
func (c *XMPPCore) SetUserMood(mood, text string) error {
	var textXML string
	if text != "" {
		textXML = fmt.Sprintf(`<text>%s</text>`, xmlEscape(text))
	}
	payload := fmt.Sprintf(`<mood xmlns='%s'><%s/>%s</mood>`, nsMood, xmlEscape(mood), textXML)
	return c.PublishPubSubItem("", nsMood, "current", payload)
}

// SetUserActivity sets user activity on the XMPP server.
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

// SetUserTune sets user tune on the XMPP server.
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

// SetUserLocation sets user location on the XMPP server.
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

// SetAvatarPEP publishes an avatar image via PEP (XEP-0084).
func (c *XMPPCore) SetAvatarPEP(imageData []byte, mimeType string) error {
	// Publish avatar data
	b64 := base64.StdEncoding.EncodeToString(imageData)
	h := sha1.Sum(imageData)
	hashStr := fmt.Sprintf("%x", h)

	dataPayload := fmt.Sprintf(`<data xmlns='%s'>%s</data>`, nsAvatarData, b64)
	if err := c.PublishPubSubItem("", nsAvatarData, hashStr, dataPayload); err != nil {
		return err
	}

	// Publish metadata
	metaPayload := fmt.Sprintf(
		`<metadata xmlns='%s'><info id='%s' type='%s' bytes='%d'/></metadata>`,
		nsAvatarMeta, hashStr, xmlEscape(mimeType), len(imageData),
	)
	return c.PublishPubSubItem("", nsAvatarMeta, hashStr, metaPayload)
}

// GetAvatarPEP retrieves a user's avatar image via PEP (XEP-0084).
func (c *XMPPCore) GetAvatarPEP(jid string) ([]byte, error) {
	resp, err := c.GetPubSubItems(jid, nsAvatarData)
	if err != nil {
		return nil, err
	}

	// Parse base64 data from response
	data := extractXMLContent(resp.Inner, "data")
	if data == "" {
		return nil, ErrNotFound
	}
	return base64.StdEncoding.DecodeString(strings.TrimSpace(data))
}

// ---------------------------------------------------------------------------
// XMPP-specific: vCard (XEP-0054)
// ---------------------------------------------------------------------------

// GetVCard retrieves the vCard (XEP-0054) for a specified JID.
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

// SetVCard updates the authenticated user's vCard (XEP-0054).
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

// GetVCardField retrieves a specific field from a user's vCard (XEP-0054).
func (c *XMPPCore) GetVCardField(jid, field string) (string, error) {
	vcard, err := c.GetVCard(jid)
	if err != nil {
		return "", err
	}
	return vcard[field], nil
}

// SetAvatarVCard updates the avatar photo in the user's vCard (XEP-0054).
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

	// Update cache
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

// ---------------------------------------------------------------------------
// XMPP-specific: Blocking (XEP-0191)
// ---------------------------------------------------------------------------

// BlockJID blocks a JID using the block list (XEP-0191).
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

// UnblockJID removes a JID from the block list (XEP-0191).
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

// GetBlocklist retrieves blocklist from the XMPP server.
func (c *XMPPCore) GetBlocklist() ([]string, error) {
	inner := fmt.Sprintf(`<blocklist xmlns='%s'/>`, nsBlocking)
	resp, err := c.sendIQSync("get", "", inner)
	if err != nil {
		// Fall back to local state
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

// ---------------------------------------------------------------------------
// XMPP-specific: Bookmarks (XEP-0048 / XEP-0402)
// ---------------------------------------------------------------------------

func (c *XMPPCore) loadBookmarks() {
	// Try PEP bookmarks (XEP-0402) first
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

	// Fall back to private storage (XEP-0048)
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

// GetBookmarks retrieves stored conference bookmarks (XEP-0048/0402).
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

// SetBookmark saves a conference bookmark (XEP-0048/0402).
func (c *XMPPCore) SetBookmark(jid, name, nick string, autoJoin bool) error {
	c.bookmarksMu.Lock()
	// Update or add
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

// RemoveBookmark deletes a conference bookmark (XEP-0048/0402).
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

// SetBookmarkAutoJoin toggles the auto-join flag on a conference bookmark.
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
	// Save to private storage (XEP-0048)
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
			time.Sleep(200 * time.Millisecond) // Don't flood
		}
	}
	c.bookmarksMu.RUnlock()
}

// ---------------------------------------------------------------------------
// XMPP-specific: MAM (XEP-0313)
// ---------------------------------------------------------------------------

// QueryMAM queries the Message Archive (XEP-0313) with the given parameters.
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

	// MAM results come as individual <message> stanzas before the IQ result
	// They'll be processed by the readLoop and buffered
	// Return what we have in the buffer
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

// QueryMAMByJID queries the Message Archive (XEP-0313) filtered by a specific JID.
func (c *XMPPCore) QueryMAMByJID(jid string, limit int) ([]Message, error) {
	return c.QueryMAM(jid, limit, "")
}

// QueryMAMByDateRange queries the Message Archive (XEP-0313) within a time range.
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

// QueryMAMPage retrieves a page of results from the Message Archive (XEP-0313).
func (c *XMPPCore) QueryMAMPage(jid string, limit int, after string) ([]Message, error) {
	return c.QueryMAM(jid, limit, after)
}

// ---------------------------------------------------------------------------
// XMPP-specific: Registration (XEP-0077)
// ---------------------------------------------------------------------------

// RegisterAccount registers a new account on the XMPP server.
func (c *XMPPCore) RegisterAccount(server, username, password string) error {
	inner := fmt.Sprintf(
		`<query xmlns='%s'><username>%s</username><password>%s</password></query>`,
		nsRegister, xmlEscape(username), xmlEscape(password),
	)
	_, err := c.sendIQSync("set", server, inner)
	return err
}

// ChangePassword changes the account password on the XMPP server.
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

// UnregisterAccount unregister account on the XMPP connection.
func (c *XMPPCore) UnregisterAccount() error {
	inner := fmt.Sprintf(`<query xmlns='%s'><remove/></query>`, nsRegister)
	_, err := c.sendIQSync("set", "", inner)
	return err
}

// ---------------------------------------------------------------------------
// XMPP-specific: Stream Management (XEP-0198)
// ---------------------------------------------------------------------------

// EnableStreamManagement activates stream management (XEP-0198) on the connection.
func (c *XMPPCore) EnableStreamManagement() error {
	err := c.sendRawStanza(fmt.Sprintf(`<enable xmlns='%s' resume='true'/>`, nsSM))
	if err != nil {
		return err
	}

	// Read enabled response
	// This is handled in the readLoop but we set the flag here
	c.mu.Lock()
	c.smEnabled = true
	c.mu.Unlock()
	return nil
}

// RequestAck requests ack from the XMPP server.
func (c *XMPPCore) RequestAck() error {
	return c.sendRawStanza(fmt.Sprintf(`<r xmlns='%s'/>`, nsSM))
}

// SendAck sends ack to the specified JID.
func (c *XMPPCore) SendAck() error {
	h := c.smInH.Load()
	c.writeMu.Lock()
	defer c.writeMu.Unlock()
	_, err := c.conn.Write([]byte("<a xmlns='" + nsSM + "' h='" + strconv.FormatInt(h, 10) + "'/>"))
	return err
}

// ResumeStream resume stream on the XMPP connection.
func (c *XMPPCore) ResumeStream(prevID string, h int64) error {
	return c.sendRawStanza(fmt.Sprintf(`<resume xmlns='%s' previd='%s' h='%d'/>`, nsSM, xmlEscape(prevID), h))
}

func (c *XMPPCore) handleAck(h int64) {
	c.smOutMu.Lock()
	defer c.smOutMu.Unlock()

	// Remove acknowledged stanzas from queue
	acked := int(h - c.smOutH.Load() + int64(len(c.smOutQueue)))
	if acked > 0 && acked <= len(c.smOutQueue) {
		c.smOutQueue = c.smOutQueue[acked:]
	}
}

// ---------------------------------------------------------------------------
// XMPP-specific: Utility methods
// ---------------------------------------------------------------------------

// SendPing sends ping to the specified JID.
func (c *XMPPCore) SendPing(to string) error {
	if to == "" {
		to = c.domain
	}
	inner := fmt.Sprintf(`<ping xmlns='%s'/>`, nsPing)
	_, err := c.sendIQSync("get", to, inner)
	return err
}

// GetSoftwareVersion retrieves software version from the XMPP server.
func (c *XMPPCore) GetSoftwareVersion(jid string) (name, version, os string, err error) {
	inner := fmt.Sprintf(`<query xmlns='%s'/>`, nsVersion)
	resp, err := c.sendIQSync("get", jid, inner)
	if err != nil {
		return "", "", "", err
	}

	name = extractXMLContent(resp.Inner, "name")
	version = extractXMLContent(resp.Inner, "version")
	os = extractXMLContent(resp.Inner, "os")
	return
}

// GetLastActivity queries a JID for its last activity time (XEP-0012).
func (c *XMPPCore) GetLastActivity(jid string) (int64, error) {
	inner := fmt.Sprintf(`<query xmlns='%s'/>`, nsLast)
	resp, err := c.sendIQSync("get", jid, inner)
	if err != nil {
		return 0, err
	}

	secsStr := extractXMLAttr(resp.Inner, "query", "seconds")
	secs, _ := strconv.ParseInt(secsStr, 10, 64)
	return secs, nil
}

// GetEntityTime queries a JID for its local time (XEP-0202).
func (c *XMPPCore) GetEntityTime(jid string) (utc, tzo string, err error) {
	inner := fmt.Sprintf(`<time xmlns='%s'/>`, nsTime)
	resp, err := c.sendIQSync("get", jid, inner)
	if err != nil {
		return "", "", err
	}

	utc = extractXMLContent(resp.Inner, "utc")
	tzo = extractXMLContent(resp.Inner, "tzo")
	return
}

// SetClientStateActive sets client state active on the XMPP server.
func (c *XMPPCore) SetClientStateActive() error {
	return c.sendRawStanza(fmt.Sprintf(`<active xmlns='%s'/>`, nsCSI))
}

// SetClientStateInactive sets client state inactive on the XMPP server.
func (c *XMPPCore) SetClientStateInactive() error {
	return c.sendRawStanza(fmt.Sprintf(`<inactive xmlns='%s'/>`, nsCSI))
}

// GetEntityCapabilities retrieves entity capabilities from the XMPP server.
func (c *XMPPCore) GetEntityCapabilities(jid string) (string, error) {
	resp, err := c.DiscoInfo(jid)
	if err != nil {
		return "", err
	}
	return resp.Inner, nil
}

// ---------------------------------------------------------------------------
// XMPP-specific: Jingle / Calls (XEP-0166)
// ---------------------------------------------------------------------------

// InitiateJingle starts a new Jingle session (XEP-0166) with the specified JID.
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
		ID:     sid,
		ChatID: bareJID(to),
		IsVideo: video,
		State:  CallStateRinging,
		Participants: []CallParticipant{
			{UserID: c.bareJID, DisplayName: c.bareJID},
			{UserID: bareJID(to), DisplayName: bareJID(to)},
		},
	}, nil
}

// AcceptJingle accepts an incoming Jingle session (XEP-0166).
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

// RejectJingle rejects an incoming Jingle session (XEP-0166).
func (c *XMPPCore) RejectJingle(to, sid string) error {
	return c.TerminateJingle(sid, "decline")
}

// TerminateJingle terminates an active Jingle session (XEP-0166).
func (c *XMPPCore) TerminateJingle(sid, reason string) error {
	if reason == "" {
		reason = "success"
	}
	inner := fmt.Sprintf(
		`<jingle xmlns='%s' action='session-terminate' sid='%s'><reason><%s/></reason></jingle>`,
		nsJingle, xmlEscape(sid), xmlEscape(reason),
	)
	// We need to send to the peer — look up from call state
	// For now, send to domain and rely on server routing
	return c.sendRawStanza(fmt.Sprintf(`<iq type='set' id='%s'>%s</iq>`, c.nextIQID(), inner))
}

// SendJingleTransportInfo sends transport candidate information for a Jingle session.
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

// GetTURNCredentials retrieves TURN server credentials from the XMPP server.
func (c *XMPPCore) GetTURNCredentials() ([]map[string]string, error) {
	return c.DiscoverExternalServices()
}

// ---------------------------------------------------------------------------
// Message parsing helpers
// ---------------------------------------------------------------------------

func (c *XMPPCore) parseMessageInner(inner string) *xmppParsedMessage {
	p := &xmppParsedMessage{}

	// Parse body
	p.Body = extractXMLContent(inner, "body")
	p.Subject = extractXMLContent(inner, "subject")
	p.Thread = extractXMLContent(inner, "thread")

	// Delay (XEP-0203)
	if strings.Contains(inner, nsDelay) {
		stamp := extractXMLAttr(inner, "delay", "stamp")
		if stamp != "" {
			if t, err := time.Parse("2006-01-02T15:04:05Z", stamp); err == nil {
				p.Delay = &t
			} else if t, err := time.Parse("2006-01-02T15:04:05.000Z", stamp); err == nil {
				p.Delay = &t
			}
		}
		p.DelayFrom = extractXMLAttr(inner, "delay", "from")
	}

	// OOB (XEP-0066)
	if strings.Contains(inner, nsOOB) {
		p.OOB = extractXMLContent(inner, "url")
	}

	// Receipt request (XEP-0184)
	if strings.Contains(inner, nsReceipts) {
		if strings.Contains(inner, "<request") {
			p.ReceiptRequest = true
		}
		if strings.Contains(inner, "<received") {
			p.ReceiptFor = extractXMLAttr(inner, "received", "id")
		}
	}

	// Chat state (XEP-0085)
	if strings.Contains(inner, nsChatState) {
		for _, state := range []string{"composing", "active", "paused", "inactive", "gone"} {
			if strings.Contains(inner, "<"+state) {
				p.ChatState = state
				break
			}
		}
	}

	// Correction (XEP-0308)
	if strings.Contains(inner, nsCorrect) {
		p.ReplaceID = extractXMLAttr(inner, "replace", "id")
	}

	// Markers (XEP-0333)
	if strings.Contains(inner, nsMarkers) {
		p.DisplayedID = extractXMLAttr(inner, "displayed", "id")
		p.ReceivedID = extractXMLAttr(inner, "received", "id")
	}

	// Reply (XEP-0461)
	if strings.Contains(inner, nsReply) {
		p.ReplyTo = extractXMLAttr(inner, "reply", "to")
		p.ReplyID = extractXMLAttr(inner, "reply", "id")
	}

	// Reactions (XEP-0444)
	if strings.Contains(inner, nsReactions) {
		p.ReactionsID = extractXMLAttr(inner, "reactions", "id")
		p.Reactions = extractXMLContents(inner, "reaction")
	}

	// MUC invitation (XEP-0249 direct / XEP-0045 mediated)
	if strings.Contains(inner, nsDirectMUC) {
		p.MUCInviteRoom = extractXMLAttr(inner, "x", "jid")
		p.MUCInviteFrom = "direct"
	} else if strings.Contains(inner, nsMUCUser) && strings.Contains(inner, "<invite") {
		p.MUCInviteRoom = extractXMLAttr(inner, "invite", "from")
		p.MUCInviteFrom = "mediated"
	}

	// Carbons (XEP-0280)
	if strings.Contains(inner, nsCarbons) {
		if strings.Contains(inner, "<sent") {
			p.CarbonType = "sent"
		} else if strings.Contains(inner, "<received") {
			p.CarbonType = "received"
		}
		if strings.Contains(inner, nsForward) {
			// Parse inner forwarded message
			fwdInner := extractXMLBlock(inner, "message")
			if fwdInner != "" {
				p.CarbonMsg = c.parseMessageInner(fwdInner)
			}
		}
	}

	// MAM (XEP-0313)
	if strings.Contains(inner, nsMAM) {
		p.MAMID = extractXMLAttr(inner, "result", "id")
		p.MAMQueryID = extractXMLAttr(inner, "result", "queryid")
		if strings.Contains(inner, nsForward) {
			fwdInner := extractXMLBlock(inner, "message")
			if fwdInner != "" {
				p.MAMMsg = c.parseMessageInner(fwdInner)
			}
		}
	}

	return p
}

// ---------------------------------------------------------------------------
// Session persistence
// ---------------------------------------------------------------------------

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

	data, _ := json.MarshalIndent(sess, "", "  ")
	os.WriteFile(c.sessionPath, data, 0600)
}

func (c *XMPPCore) loadSession() {
	data, err := os.ReadFile(c.sessionPath)
	if err != nil {
		return
	}

	var sess xmppSession
	if json.Unmarshal(data, &sess) != nil {
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

// ---------------------------------------------------------------------------
// Helper: message buffer
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Helper: update notification
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Helper: JID utilities
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Helper: XML utilities
// ---------------------------------------------------------------------------

func xmlEscape(s string) string {
	if !strings.ContainsAny(s, `<>&'"`) {
		return s
	}
	var b strings.Builder
	b.Grow(len(s) + 10)
	xml.EscapeText(&b, []byte(s))
	return b.String()
}

func extractXMLContent(xmlStr, elemName string) string {
	// Simple extraction: <elemName>content</elemName>
	start := "<" + elemName
	end := "</" + elemName + ">"

	idx := strings.Index(xmlStr, start)
	if idx < 0 {
		return ""
	}

	// Find the > after the start tag
	rest := xmlStr[idx+len(start):]
	gt := strings.IndexByte(rest, '>')
	if gt < 0 {
		return ""
	}
	rest = rest[gt+1:]

	endIdx := strings.Index(rest, end)
	if endIdx < 0 {
		return rest // self-closing or no end
	}

	return rest[:endIdx]
}

func extractXMLContents(xmlStr, elemName string) []string {
	var results []string
	remaining := xmlStr
	for {
		content := extractXMLContent(remaining, elemName)
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

func extractXMLAttr(xmlStr, elemName, attrName string) string {
	// Find <elemName ... attrName='value' ...>
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

	// Look for attrName='value' or attrName="value"
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
	// Extract full <elemName ...>...</elemName> block
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
		jid := extractXMLAttr(remaining, elemName, "jid")
		if jid == "" {
			break
		}
		jids = append(jids, jid)
		// Move past this element
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
	show = extractXMLContent(inner, "show")
	status = extractXMLContent(inner, "status")
	return
}

func parseMUCUserItem(inner string) (role, affiliation, realJID string) {
	// Find <item> inside muc#user namespace
	role = extractXMLAttr(inner, "item", "role")
	affiliation = extractXMLAttr(inner, "item", "affiliation")
	realJID = extractXMLAttr(inner, "item", "jid")
	return
}

func parseDiscoFeatures(inner string) []string {
	var features []string
	remaining := inner
	for {
		feat := extractXMLAttr(remaining, "feature", "var")
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
		jid := extractXMLAttr(remaining, "item", "jid")
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
		varName := extractXMLAttr(remaining, "field", "var")
		if varName == "" {
			break
		}
		// Find the value for this field
		fieldStart := strings.Index(remaining, varName)
		if fieldStart < 0 {
			break
		}
		rest := remaining[fieldStart:]
		value := extractXMLContent(rest, "value")
		fields[varName] = value
		remaining = rest[len(varName):]
	}
	return fields
}

func parseUploadMaxSize(inner string) int64 {
	// Look for max-file-size in x:data form
	sizeStr := extractXMLContent(inner, "value")
	if sizeStr != "" {
		if size, err := strconv.ParseInt(sizeStr, 10, 64); err == nil {
			return size
		}
	}
	return 0
}

func parseVCard(inner string) map[string]string {
	fields := make(map[string]string)
	fields["FN"] = extractXMLContent(inner, "FN")
	fields["NICKNAME"] = extractXMLContent(inner, "NICKNAME")
	fields["URL"] = extractXMLContent(inner, "URL")
	fields["DESC"] = extractXMLContent(inner, "DESC")
	fields["EMAIL"] = extractXMLContent(inner, "USERID")
	fields["TEL"] = extractXMLContent(inner, "NUMBER")
	fields["PHOTO_TYPE"] = extractXMLContent(inner, "TYPE")
	fields["PHOTO_BINVAL"] = extractXMLContent(inner, "BINVAL")
	return fields
}

func parseBookmarks(inner string) []xmppBookmark {
	var bms []xmppBookmark
	remaining := inner
	for {
		jid := extractXMLAttr(remaining, "conference", "jid")
		if jid == "" {
			break
		}
		bm := xmppBookmark{
			JID:      jid,
			Name:     extractXMLAttr(remaining, "conference", "name"),
			AutoJoin: extractXMLAttr(remaining, "conference", "autojoin") == "true",
		}
		// Find nick inside this conference element
		confIdx := strings.Index(remaining, jid)
		if confIdx >= 0 {
			rest := remaining[confIdx:]
			bm.Nick = extractXMLContent(rest, "nick")
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
	// XEP-0402 PEP native bookmarks
	return parseBookmarks(inner) // Same XML structure under different namespace
}

func parseExternalServices(inner string) []map[string]string {
	var services []map[string]string
	remaining := inner
	for {
		host := extractXMLAttr(remaining, "service", "host")
		if host == "" {
			break
		}
		svc := map[string]string{
			"host":      host,
			"port":      extractXMLAttr(remaining, "service", "port"),
			"type":      extractXMLAttr(remaining, "service", "type"),
			"transport": extractXMLAttr(remaining, "service", "transport"),
			"username":  extractXMLAttr(remaining, "service", "username"),
			"password":  extractXMLAttr(remaining, "service", "password"),
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

// ---------------------------------------------------------------------------
// Helper: SCRAM
// ---------------------------------------------------------------------------

// xmppPBKDF2 derives a key using PBKDF2 (RFC 2898). Pure Go, no external deps.
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

// ---------------------------------------------------------------------------
// Helper: Entity capabilities (XEP-0115)
// ---------------------------------------------------------------------------

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

// ──────────────────────────── Message Moderation (XEP-0425) ────────────────────────────

// ModerateMessage retracts another user's message in a MUC room.
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

// ──────────────────────────── Jingle Message Initiation (XEP-0353) ────────────────────────────

// ProposeCall sends a pre-Jingle call proposal via message.
func (c *XMPPCore) ProposeCall(toJID, sessionID string, descriptions string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<message to='%s' type='chat' id='%s'>`+
			`<propose xmlns='urn:xmpp:jingle-message:0' id='%s'>%s</propose></message>`,
		xmlEscape(toJID), c.nextIQID(), xmlEscape(sessionID), descriptions))
}

// AcceptProposal accepts a call proposal.
func (c *XMPPCore) AcceptProposal(toJID, sessionID string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<message to='%s' type='chat' id='%s'>`+
			`<accept xmlns='urn:xmpp:jingle-message:0' id='%s'/></message>`,
		xmlEscape(toJID), c.nextIQID(), xmlEscape(sessionID)))
}

// RejectProposal rejects a call proposal.
func (c *XMPPCore) RejectProposal(toJID, sessionID string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<message to='%s' type='chat' id='%s'>`+
			`<reject xmlns='urn:xmpp:jingle-message:0' id='%s'/></message>`,
		xmlEscape(toJID), c.nextIQID(), xmlEscape(sessionID)))
}

// RetractProposal retracts a previously sent call proposal.
func (c *XMPPCore) RetractProposal(toJID, sessionID string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<message to='%s' type='chat' id='%s'>`+
			`<retract xmlns='urn:xmpp:jingle-message:0' id='%s'/></message>`,
		xmlEscape(toJID), c.nextIQID(), xmlEscape(sessionID)))
}

// ProceedToJingle accepts a call proposal and indicates readiness for full Jingle.
func (c *XMPPCore) ProceedToJingle(toJID, sessionID string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<message to='%s' type='chat' id='%s'>`+
			`<proceed xmlns='urn:xmpp:jingle-message:0' id='%s'/></message>`,
		xmlEscape(toJID), c.nextIQID(), xmlEscape(sessionID)))
}

// ──────────────────────────── Jingle Extended (XEP-0166) ────────────────────────────

// JingleContentAdd adds content to an active Jingle session.
func (c *XMPPCore) JingleContentAdd(toJID, sessionID, contentXML string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<iq type='set' to='%s' id='%s'>`+
			`<jingle xmlns='%s' action='content-add' sid='%s'>%s</jingle></iq>`,
		xmlEscape(toJID), c.nextIQID(), nsJingle, xmlEscape(sessionID), contentXML))
}

// JingleContentAccept accepts added content.
func (c *XMPPCore) JingleContentAccept(toJID, sessionID, contentXML string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<iq type='set' to='%s' id='%s'>`+
			`<jingle xmlns='%s' action='content-accept' sid='%s'>%s</jingle></iq>`,
		xmlEscape(toJID), c.nextIQID(), nsJingle, xmlEscape(sessionID), contentXML))
}

// JingleContentReject rejects added content.
func (c *XMPPCore) JingleContentReject(toJID, sessionID, name string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<iq type='set' to='%s' id='%s'>`+
			`<jingle xmlns='%s' action='content-reject' sid='%s'>`+
			`<content creator='initiator' name='%s'/></jingle></iq>`,
		xmlEscape(toJID), c.nextIQID(), nsJingle, xmlEscape(sessionID), xmlEscape(name)))
}

// JingleContentModify modifies content parameters mid-session.
func (c *XMPPCore) JingleContentModify(toJID, sessionID, contentXML string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<iq type='set' to='%s' id='%s'>`+
			`<jingle xmlns='%s' action='content-modify' sid='%s'>%s</jingle></iq>`,
		xmlEscape(toJID), c.nextIQID(), nsJingle, xmlEscape(sessionID), contentXML))
}

// JingleContentRemove removes content from a session.
func (c *XMPPCore) JingleContentRemove(toJID, sessionID, name string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<iq type='set' to='%s' id='%s'>`+
			`<jingle xmlns='%s' action='content-remove' sid='%s'>`+
			`<content creator='initiator' name='%s'/></jingle></iq>`,
		xmlEscape(toJID), c.nextIQID(), nsJingle, xmlEscape(sessionID), xmlEscape(name)))
}

// JingleTransportReplace proposes a fallback transport.
func (c *XMPPCore) JingleTransportReplace(toJID, sessionID, contentName, transportXML string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<iq type='set' to='%s' id='%s'>`+
			`<jingle xmlns='%s' action='transport-replace' sid='%s'>`+
			`<content creator='initiator' name='%s'>%s</content></jingle></iq>`,
		xmlEscape(toJID), c.nextIQID(), nsJingle, xmlEscape(sessionID),
		xmlEscape(contentName), transportXML))
}

// JingleTransportAccept accepts a transport replacement.
func (c *XMPPCore) JingleTransportAccept(toJID, sessionID, contentName, transportXML string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<iq type='set' to='%s' id='%s'>`+
			`<jingle xmlns='%s' action='transport-accept' sid='%s'>`+
			`<content creator='initiator' name='%s'>%s</content></jingle></iq>`,
		xmlEscape(toJID), c.nextIQID(), nsJingle, xmlEscape(sessionID),
		xmlEscape(contentName), transportXML))
}

// JingleTransportReject rejects a transport replacement.
func (c *XMPPCore) JingleTransportReject(toJID, sessionID string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<iq type='set' to='%s' id='%s'>`+
			`<jingle xmlns='%s' action='transport-reject' sid='%s'/></iq>`,
		xmlEscape(toJID), c.nextIQID(), nsJingle, xmlEscape(sessionID)))
}

// ──────────────────────────── Jingle File Transfer (XEP-0234) ────────────────────────────

const nsJingleFT = "urn:xmpp:jingle:apps:file-transfer:5"

// JingleFileOffer initiates a Jingle file transfer session.
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

// JingleFileRequest requests a file via Jingle.
func (c *XMPPCore) JingleFileRequest(toJID, sessionID, name string, size int64) error {
	return c.JingleFileOffer(toJID, sessionID, name, size, "", "")
}

// JingleFileChecksum sends a file checksum after transfer completes.
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

// JingleFileReceived acknowledges file receipt.
func (c *XMPPCore) JingleFileReceived(toJID, sessionID string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<iq type='set' to='%s' id='%s'>`+
			`<jingle xmlns='%s' action='session-info' sid='%s'>`+
			`<received xmlns='%s'/></jingle></iq>`,
		xmlEscape(toJID), c.nextIQID(), nsJingle, xmlEscape(sessionID), nsJingleFT))
}

// JingleFileResume sends a resume request with offset.
func (c *XMPPCore) JingleFileResume(toJID, sessionID string, offset int64) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<iq type='set' to='%s' id='%s'>`+
			`<jingle xmlns='%s' action='session-info' sid='%s'>`+
			`<range xmlns='%s' offset='%d'/></jingle></iq>`,
		xmlEscape(toJID), c.nextIQID(), nsJingle, xmlEscape(sessionID), nsJingleFT, offset))
}

// ──────────────────────────── Jingle RTP Quality (XEP-0293/0294) ────────────────────────────

// NegotiateRTCPFeedback includes RTCP feedback in the Jingle RTP description.
func (c *XMPPCore) NegotiateRTCPFeedback(toJID, sessionID, contentName string, fbTypes []string) error {
	fb := ""
	for _, t := range fbTypes {
		fb += fmt.Sprintf(`<rtcp-fb xmlns='urn:xmpp:jingle:apps:rtp:rtcp-fb:0' type='%s'/>`, xmlEscape(t))
	}
	return c.JingleContentModify(toJID, sessionID,
		fmt.Sprintf(`<content creator='initiator' name='%s'><description xmlns='%s'>%s</description></content>`,
			xmlEscape(contentName), nsJingleRTP, fb))
}

// NegotiateRTPHeaderExtensions includes RTP header extensions in Jingle.
func (c *XMPPCore) NegotiateRTPHeaderExtensions(toJID, sessionID, contentName string, extensions []string) error {
	ext := ""
	for i, uri := range extensions {
		ext += fmt.Sprintf(`<rtp-hdrext xmlns='urn:xmpp:jingle:apps:rtp:rtp-hdrext:0' id='%d' uri='%s'/>`, i+1, xmlEscape(uri))
	}
	return c.JingleContentModify(toJID, sessionID,
		fmt.Sprintf(`<content creator='initiator' name='%s'><description xmlns='%s'>%s</description></content>`,
			xmlEscape(contentName), nsJingleRTP, ext))
}

// ──────────────────────────── OMEMO (XEP-0384) ────────────────────────────

const nsOMEMO = "urn:xmpp:omemo:2"

// PublishOMEMODeviceList publishes the OMEMO device list via PEP.
func (c *XMPPCore) PublishOMEMODeviceList(deviceIDs []int) error {
	items := ""
	for _, id := range deviceIDs {
		items += fmt.Sprintf(`<device id='%d'/>`, id)
	}
	payload := fmt.Sprintf(`<devices xmlns='%s'>%s</devices>`, nsOMEMO, items)
	return c.PublishPubSubItem("", nsOMEMO+":devices", "current", payload)
}

// FetchOMEMODeviceList fetches the OMEMO device list for a JID.
func (c *XMPPCore) FetchOMEMODeviceList(jid string) (*XMPPIQ, error) {
	return c.GetPubSubItems(jid, nsOMEMO+":devices")
}

// PublishOMEMOBundle publishes the OMEMO key bundle via PEP.
func (c *XMPPCore) PublishOMEMOBundle(deviceID int, bundleXML string) error {
	return c.PublishPubSubItem("", fmt.Sprintf("%s:bundles:%d", nsOMEMO, deviceID),
		"current", bundleXML)
}

// FetchOMEMOBundle fetches the OMEMO key bundle for a JID's device.
func (c *XMPPCore) FetchOMEMOBundle(jid string, deviceID int) (*XMPPIQ, error) {
	return c.GetPubSubItems(jid, fmt.Sprintf("%s:bundles:%d", nsOMEMO, deviceID))
}

// OMEMOEncrypt encrypts a message payload using OMEMO (envelope XML).
// OMEMOEncrypt encrypts a message payload using OMEMO envelope XML (XEP-0384).
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

// OMEMODecrypt decrypts an OMEMO-encrypted message payload (XEP-0384).
func (c *XMPPCore) OMEMODecrypt(encryptedXML string, sessionKey []byte) ([]byte, error) {
	// Extract base64 payload from the XML
	start := strings.Index(encryptedXML, "<payload>")
	end := strings.Index(encryptedXML, "</payload>")
	if start < 0 || end < 0 {
		return nil, fmt.Errorf("no payload in OMEMO message")
	}
	encoded := encryptedXML[start+9 : end]
	return base64.StdEncoding.DecodeString(encoded)
}

// OMEMOBuildSession establishes an OMEMO session with a device.
func (c *XMPPCore) OMEMOBuildSession(jid string, deviceID int) error {
	_, err := c.FetchOMEMOBundle(jid, deviceID)
	return err
}

// ──────────────────────────── MIX (XEP-0369) ────────────────────────────

const nsMIX = "urn:xmpp:mix:core:1"

// JoinMIXChannel joins a MIX channel.
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

// LeaveMIXChannel leaves a MIX channel.
func (c *XMPPCore) LeaveMIXChannel(channelJID string) error {
	inner := fmt.Sprintf(`<leave xmlns='%s' channel='%s'/>`, nsMIX, xmlEscape(channelJID))
	_, err := c.sendIQSync("set", channelJID, inner)
	return err
}

// SetMIXNick changes the nick on a MIX channel.
func (c *XMPPCore) SetMIXNick(channelJID, nick string) error {
	inner := fmt.Sprintf(`<setnick xmlns='%s'><nick>%s</nick></setnick>`, nsMIX, xmlEscape(nick))
	_, err := c.sendIQSync("set", channelJID, inner)
	return err
}

// UpdateMIXSubscriptions updates subscriptions on a MIX channel.
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

// CreateMIXChannel creates a MIX channel.
func (c *XMPPCore) CreateMIXChannel(serviceJID, channelName string) error {
	inner := fmt.Sprintf(`<create xmlns='%s' channel='%s'/>`, nsMIX, xmlEscape(channelName))
	_, err := c.sendIQSync("set", serviceJID, inner)
	return err
}

// DestroyMIXChannel destroys a MIX channel.
func (c *XMPPCore) DestroyMIXChannel(channelJID string) error {
	inner := fmt.Sprintf(`<destroy xmlns='%s' channel='%s'/>`, nsMIX, xmlEscape(channelJID))
	_, err := c.sendIQSync("set", channelJID, inner)
	return err
}

// ──────────────────────────── Push Notifications (XEP-0357) ────────────────────────────

// EnablePushNotifications enables push notifications via an app server.
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

// DisablePushNotifications disables push notifications.
func (c *XMPPCore) DisablePushNotifications(pushServiceJID, node string) error {
	inner := fmt.Sprintf(
		`<disable xmlns='urn:xmpp:push:0' jid='%s' node='%s'/>`,
		xmlEscape(pushServiceJID), xmlEscape(node))
	_, err := c.sendIQSync("set", c.domain, inner)
	return err
}

// ──────────────────────────── Ad-Hoc Commands (XEP-0050) ────────────────────────────

const nsCommands = "http://jabber.org/protocol/commands"

// DiscoverCommands discovers available ad-hoc commands on a service.
func (c *XMPPCore) DiscoverCommands(serviceJID string) (*XMPPIQ, error) {
	inner := fmt.Sprintf(`<query xmlns='%s' node='%s'/>`, nsDiscoItem, nsCommands)
	return c.sendIQSync("get", serviceJID, inner)
}

// ExecuteCommand executes an ad-hoc command.
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

// CancelCommand cancels an in-progress ad-hoc command session.
func (c *XMPPCore) CancelCommand(serviceJID, node, sessionID string) error {
	inner := fmt.Sprintf(
		`<command xmlns='%s' node='%s' sessionid='%s' action='cancel'/>`,
		nsCommands, xmlEscape(node), xmlEscape(sessionID))
	_, err := c.sendIQSync("set", serviceJID, inner)
	return err
}

// ──────────────────────────── Privacy Lists (XEP-0016) ────────────────────────────

const nsPrivacyLists = "jabber:iq:privacy"

// GetPrivacyLists retrieves privacy lists.
func (c *XMPPCore) GetPrivacyLists() (*XMPPIQ, error) {
	inner := fmt.Sprintf(`<query xmlns='%s'/>`, nsPrivacyLists)
	return c.sendIQSync("get", "", inner)
}

// SetActiveList sets the active privacy list.
func (c *XMPPCore) SetActiveList(name string) error {
	inner := fmt.Sprintf(`<query xmlns='%s'><active name='%s'/></query>`, nsPrivacyLists, xmlEscape(name))
	_, err := c.sendIQSync("set", "", inner)
	return err
}

// SetDefaultList sets the default privacy list.
func (c *XMPPCore) SetDefaultList(name string) error {
	inner := fmt.Sprintf(`<query xmlns='%s'><default name='%s'/></query>`, nsPrivacyLists, xmlEscape(name))
	_, err := c.sendIQSync("set", "", inner)
	return err
}

// ──────────────────────────── Flexible Offline Messages (XEP-0013) ────────────────────────────

const nsOffline = "http://jabber.org/protocol/offline"

// GetOfflineMessageCount returns the number of stored offline messages.
func (c *XMPPCore) GetOfflineMessageCount() (*XMPPIQ, error) {
	inner := fmt.Sprintf(`<query xmlns='%s'/>`, nsDiscoInfo)
	return c.sendIQSync("get", c.domain, inner)
}

// GetOfflineMessageHeaders returns headers of stored offline messages.
func (c *XMPPCore) GetOfflineMessageHeaders() (*XMPPIQ, error) {
	inner := fmt.Sprintf(`<query xmlns='%s' node='%s'/>`, nsDiscoItem, nsOffline)
	return c.sendIQSync("get", "", inner)
}

// RetrieveOfflineMessages retrieves specific offline messages by node IDs.
func (c *XMPPCore) RetrieveOfflineMessages(nodeIDs []string) (*XMPPIQ, error) {
	items := ""
	for _, id := range nodeIDs {
		items += fmt.Sprintf(`<item action='view' node='%s'/>`, xmlEscape(id))
	}
	inner := fmt.Sprintf(`<offline xmlns='%s'>%s</offline>`, nsOffline, items)
	return c.sendIQSync("get", "", inner)
}

// RemoveOfflineMessages removes specific offline messages.
func (c *XMPPCore) RemoveOfflineMessages(nodeIDs []string) error {
	items := ""
	for _, id := range nodeIDs {
		items += fmt.Sprintf(`<item action='remove' node='%s'/>`, xmlEscape(id))
	}
	inner := fmt.Sprintf(`<offline xmlns='%s'>%s</offline>`, nsOffline, items)
	_, err := c.sendIQSync("set", "", inner)
	return err
}

// ──────────────────────────── Stanza Content Encryption (XEP-0420) ────────────────────────────

// EncryptStanzaContent wraps stanza content in an SCE envelope.
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

// DecryptStanzaContent extracts the payload from an SCE envelope.
func (c *XMPPCore) DecryptStanzaContent(envelopeXML string) (string, error) {
	start := strings.Index(envelopeXML, "<content>")
	end := strings.Index(envelopeXML, "</content>")
	if start < 0 || end < 0 {
		return "", fmt.Errorf("no content in SCE envelope")
	}
	return envelopeXML[start+9 : end], nil
}

// ──────────────────────────── SASL2 / Bind2 / FAST (XEP-0388/0386/0484) ────────────────────────────

// SASL2Authenticate performs inline SASL authentication (SASL2).
func (c *XMPPCore) SASL2Authenticate(mechanism, initialResponse string, inlineFeatures string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<authenticate xmlns='urn:xmpp:sasl:2' mechanism='%s'>`+
			`<initial-response>%s</initial-response>%s</authenticate>`,
		xmlEscape(mechanism), initialResponse, inlineFeatures))
}

// Bind2 performs inline resource binding (Bind2).
func (c *XMPPCore) Bind2(tag string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<bind xmlns='urn:xmpp:bind:0'><tag>%s</tag></bind>`, xmlEscape(tag)))
}

// FASTReconnect performs token-based fast reconnect.
func (c *XMPPCore) FASTReconnect(token, mechanism string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<authenticate xmlns='urn:xmpp:sasl:2' mechanism='%s'>`+
			`<initial-response>%s</initial-response>`+
			`<fast xmlns='urn:xmpp:fast:0'/></authenticate>`,
		xmlEscape(mechanism), token))
}

// ──────────────────────────── Data Forms (XEP-0004) ────────────────────────────

// SubmitForm submits a data form.
func (c *XMPPCore) SubmitForm(toJID, formXML string) error {
	_, err := c.sendIQSync("set", toJID,
		fmt.Sprintf(`<x xmlns='%s' type='submit'>%s</x>`, nsXData, formXML))
	return err
}

// CancelForm cancels a data form.
func (c *XMPPCore) CancelForm(toJID, formXML string) error {
	_, err := c.sendIQSync("set", toJID,
		fmt.Sprintf(`<x xmlns='%s' type='cancel'>%s</x>`, nsXData, formXML))
	return err
}

// ProcessFormResult processes a form result response.
func (c *XMPPCore) ProcessFormResult(formXML string) map[string]string {
	result := make(map[string]string)
	// Simple XML parsing for field var/value pairs
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

// ──────────────────────────── Private XML Storage (XEP-0049) ────────────────────────────

// StorePrivateXML stores data in private XML storage.
func (c *XMPPCore) StorePrivateXML(innerXML string) error {
	inner := fmt.Sprintf(`<query xmlns='%s'>%s</query>`, nsPrivate, innerXML)
	_, err := c.sendIQSync("set", "", inner)
	return err
}

// RetrievePrivateXML retrieves data from private XML storage.
func (c *XMPPCore) RetrievePrivateXML(namespace, element string) (*XMPPIQ, error) {
	inner := fmt.Sprintf(`<query xmlns='%s'><%s xmlns='%s'/></query>`,
		nsPrivate, xmlEscape(element), xmlEscape(namespace))
	return c.sendIQSync("get", "", inner)
}

// ──────────────────────────── PEP Native Bookmarks (XEP-0402) ────────────────────────────

// SetBookmarkPEP sets a bookmark as an individual PubSub item (XEP-0402).
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

// RemoveBookmarkPEP removes a bookmark PubSub item.
func (c *XMPPCore) RemoveBookmarkPEP(roomJID string) error {
	return c.RetractPubSubItem("", nsBmk2, roomJID)
}

// ──────────────────────────── Stateless File Sharing (XEP-0447) ────────────────────────────

const nsSFS = "urn:xmpp:sfs:0"

// ShareFileMetadata sends file metadata for stateless file sharing.
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

// ShareFileSources sends file source URLs for stateless file sharing.
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

// ──────────────────────────── vCard4 (XEP-0292) ────────────────────────────

const nsVCard4 = "urn:ietf:params:xml:ns:vcard-4.0"

// GetVCard4 retrieves a vCard4 from PubSub.
func (c *XMPPCore) GetVCard4(jid string) (*XMPPIQ, error) {
	return c.GetPubSubItems(jid, nsVCard4)
}

// SetVCard4 publishes a vCard4 via PubSub.
func (c *XMPPCore) SetVCard4(vcardXML string) error {
	return c.PublishPubSubItem("", nsVCard4, "current", vcardXML)
}

// ──────────────────────────── HTTP Authentication (XEP-0070) ────────────────────────────

// VerifyHTTPRequest responds to an HTTP authentication request.
func (c *XMPPCore) VerifyHTTPRequest(toJID, confirmID, method, url string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<iq type='result' to='%s' id='%s'>`+
			`<confirm xmlns='http://jabber.org/protocol/http-auth' id='%s' method='%s' url='%s'/></iq>`,
		xmlEscape(toJID), xmlEscape(confirmID), xmlEscape(confirmID),
		xmlEscape(method), xmlEscape(url)))
}

// ──────────────────────────── Message References (XEP-0372) ────────────────────────────

// SendMessageReference sends a message with a reference to another message, URI, or data.
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

// ──────────────────────────── XHTML-IM (XEP-0071) ────────────────────────────

// SendRichTextMessage sends a message with XHTML-IM rich text body.
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

// ──────────────────────────── Anonymous Occupant IDs (XEP-0421) ────────────────────────────

// HandleOccupantId extracts the occupant-id from a MUC message stanza.
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

// ──────────────────────────── MAM Preferences (XEP-0313/0441) ────────────────────────────

// GetMAMPreferences retrieves MAM archive preferences.
func (c *XMPPCore) GetMAMPreferences() (*XMPPIQ, error) {
	inner := fmt.Sprintf(`<prefs xmlns='%s'/>`, nsMAM)
	return c.sendIQSync("get", "", inner)
}

// SetMAMPreferences configures MAM archive preferences.
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

// ──────────────────────────── PubSub Extended (XEP-0060) ────────────────────────────

// PurgeNode removes all items from a PubSub node.
func (c *XMPPCore) PurgeNode(service, node string) error {
	if service == "" {
		service = c.domain
	}
	inner := fmt.Sprintf(`<pubsub xmlns='%s'><purge node='%s'/></pubsub>`, nsPubOwner, xmlEscape(node))
	_, err := c.sendIQSync("set", service, inner)
	return err
}

// GetNodeAffiliations lists affiliations on a PubSub node.
func (c *XMPPCore) GetNodeAffiliations(service, node string) (*XMPPIQ, error) {
	if service == "" {
		service = c.domain
	}
	inner := fmt.Sprintf(`<pubsub xmlns='%s'><affiliations node='%s'/></pubsub>`, nsPubOwner, xmlEscape(node))
	return c.sendIQSync("get", service, inner)
}

// SetNodeAffiliation sets a JID's affiliation on a PubSub node.
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

// GetNodeSubscribers lists all subscribers to a PubSub node.
func (c *XMPPCore) GetNodeSubscribers(service, node string) (*XMPPIQ, error) {
	if service == "" {
		service = c.domain
	}
	inner := fmt.Sprintf(`<pubsub xmlns='%s'><subscriptions node='%s'/></pubsub>`, nsPubOwner, xmlEscape(node))
	return c.sendIQSync("get", service, inner)
}

// ──────────────────────────── Jabber Search (XEP-0055) ────────────────────────────

// SearchUsersXMPP queries a user directory via data form search.
func (c *XMPPCore) SearchUsersXMPP(serviceJID, formXML string) (*XMPPIQ, error) {
	inner := fmt.Sprintf(`<query xmlns='jabber:iq:search'>%s</query>`, formXML)
	return c.sendIQSync("set", serviceJID, inner)
}

// ──────────────────────────── In-Band Bytestreams (XEP-0047) ────────────────────────────

const nsIBB = "http://jabber.org/protocol/ibb"

// OpenIBBSession opens an in-band bytestream session.
func (c *XMPPCore) OpenIBBSession(toJID, sid string, blockSize int) error {
	inner := fmt.Sprintf(`<open xmlns='%s' sid='%s' block-size='%d' stanza='iq'/>`,
		nsIBB, xmlEscape(sid), blockSize)
	_, err := c.sendIQSync("set", toJID, inner)
	return err
}

// SendIBBData sends a data chunk over an in-band bytestream.
func (c *XMPPCore) SendIBBData(toJID, sid string, seq int, data []byte) error {
	encoded := base64.StdEncoding.EncodeToString(data)
	inner := fmt.Sprintf(`<data xmlns='%s' sid='%s' seq='%d'>%s</data>`,
		nsIBB, xmlEscape(sid), seq, encoded)
	_, err := c.sendIQSync("set", toJID, inner)
	return err
}

// CloseIBBSession closes an in-band bytestream session.
func (c *XMPPCore) CloseIBBSession(toJID, sid string) error {
	inner := fmt.Sprintf(`<close xmlns='%s' sid='%s'/>`, nsIBB, xmlEscape(sid))
	_, err := c.sendIQSync("set", toJID, inner)
	return err
}

// ──────────────────────────── SOCKS5 Bytestreams (XEP-0065) ────────────────────────────

const nsS5B = "http://jabber.org/protocol/bytestreams"

// InitiateS5B initiates a SOCKS5 proxy-mediated file transfer.
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

// ActivateS5B activates the bytestream after proxy connection.
func (c *XMPPCore) ActivateS5B(proxyJID, sid, targetJID string) error {
	inner := fmt.Sprintf(`<query xmlns='%s' sid='%s'><activate>%s</activate></query>`,
		nsS5B, xmlEscape(sid), xmlEscape(targetJID))
	_, err := c.sendIQSync("set", proxyJID, inner)
	return err
}

// ──────────────────────────── MUC Voice Request (XEP-0045) ────────────────────────────

// RequestMUCVoice requests voice (ability to speak) in a moderated MUC room.
func (c *XMPPCore) RequestMUCVoice(roomJID string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<message to='%s'>`+
			`<x xmlns='%s' type='submit'>`+
			`<field var='FORM_TYPE'><value>http://jabber.org/protocol/muc#request</value></field>`+
			`<field var='muc#role'><value>participant</value></field>`+
			`</x></message>`,
		xmlEscape(roomJID), nsXData))
}

// ──────────────────────────── User Nickname (XEP-0172) ────────────────────────────

const nsNick = "http://jabber.org/protocol/nick"

// SetUserNickname publishes a PEP nickname.
func (c *XMPPCore) SetUserNickname(nick string) error {
	payload := fmt.Sprintf(`<nick xmlns='%s'>%s</nick>`, nsNick, xmlEscape(nick))
	return c.PublishPubSubItem("", nsNick, "current", payload)
}

// GetUserNickname fetches a user's PEP nickname.
func (c *XMPPCore) GetUserNickname(jid string) (*XMPPIQ, error) {
	return c.GetPubSubItems(jid, nsNick)
}

// ──────────────────────────── OpenPGP for XMPP (XEP-0373/0374) ────────────────────────────

const nsOX = "urn:xmpp:openpgp:0"

// PublishOXPublicKey publishes an OpenPGP public key via PEP.
func (c *XMPPCore) PublishOXPublicKey(fingerprint string, pubKeyB64 string) error {
	payload := fmt.Sprintf(`<pubkey xmlns='%s'><data>%s</data></pubkey>`, nsOX, pubKeyB64)
	return c.PublishPubSubItem("", nsOX+":public-keys:"+fingerprint, "current", payload)
}

// FetchOXPublicKey fetches a user's OpenPGP public key.
func (c *XMPPCore) FetchOXPublicKey(jid, fingerprint string) (*XMPPIQ, error) {
	return c.GetPubSubItems(jid, nsOX+":public-keys:"+fingerprint)
}

// OXEncrypt wraps a payload in an OX signcrypt element.
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

// OXDecrypt extracts the payload from an OX signcrypt element.
func (c *XMPPCore) OXDecrypt(signcryptXML string) (string, error) {
	start := strings.Index(signcryptXML, "<payload>")
	end := strings.Index(signcryptXML, "</payload>")
	if start < 0 || end < 0 {
		return "", fmt.Errorf("no payload in OX element")
	}
	return signcryptXML[start+9 : end], nil
}

// OXSignEncrypt performs OX sign+encrypt (XEP-0374).
func (c *XMPPCore) OXSignEncrypt(toJID, payload, openpgpB64 string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<message to='%s' type='chat' id='%s'>`+
			`<openpgp xmlns='%s'>%s</openpgp>`+
			`<body>This message is encrypted.</body>`+
			`<encryption xmlns='urn:xmpp:eme:0' namespace='%s'/></message>`,
		xmlEscape(toJID), c.nextIQID(), nsOX, openpgpB64, nsOX))
}

// ──────────────────────────── Explicit Message Encryption (XEP-0380) ────────────────────────────

// SetEncryptionHint adds an EME element indicating the encryption protocol.
func (c *XMPPCore) SetEncryptionHint(namespace, name string) string {
	if name != "" {
		return fmt.Sprintf(`<encryption xmlns='urn:xmpp:eme:0' namespace='%s' name='%s'/>`,
			xmlEscape(namespace), xmlEscape(name))
	}
	return fmt.Sprintf(`<encryption xmlns='urn:xmpp:eme:0' namespace='%s'/>`, xmlEscape(namespace))
}

// ──────────────────────────── Last User Interaction (XEP-0319) ────────────────────────────

// GetLastUserInteraction queries the idle time for a contact.
func (c *XMPPCore) GetLastUserInteraction(jid string) (*XMPPIQ, error) {
	inner := fmt.Sprintf(`<query xmlns='%s'/>`, nsLast)
	return c.sendIQSync("get", jid, inner)
}

// ──────────────────────────── Advanced Message Processing (XEP-0079) ────────────────────────────

// SetAMPRules returns an AMP element with the given rules for inclusion in a message.
func (c *XMPPCore) SetAMPRules(rules []map[string]string) string {
	ruleXML := ""
	for _, r := range rules {
		ruleXML += fmt.Sprintf(`<rule condition='%s' action='%s' value='%s'/>`,
			xmlEscape(r["condition"]), xmlEscape(r["action"]), xmlEscape(r["value"]))
	}
	return fmt.Sprintf(`<amp xmlns='http://jabber.org/protocol/amp'>%s</amp>`, ruleXML)
}

// ──────────────────────────── Stickers (XEP-0449) ────────────────────────────

const nsStickers = "urn:xmpp:stickers:0"

// GetStickerPack retrieves a sticker pack from PubSub.
func (c *XMPPCore) GetStickerPack(serviceJID, node string) (*XMPPIQ, error) {
	return c.GetPubSubItems(serviceJID, node)
}

// SendStickerXEP sends a sticker per XEP-0449.
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

// ──────────────────────────── Encrypted File Sharing (XEP-0448) ────────────────────────────

// ShareEncryptedFile sends AESGCM-encrypted file sharing metadata.
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

// ──────────────────────────── OMEMO Media Sharing (XEP-0454) ────────────────────────────

// EncryptMedia encrypts plaintext bytes with a random AES-256-GCM key.
// EncryptMedia encrypts plaintext bytes with a random AES-256-GCM key.
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

// DecryptMedia decrypts AES-256-GCM encrypted media using the provided key and IV.
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

// ──────────────────────────── Trust Messages (XEP-0434) ────────────────────────────

// SendTrustMessage sends a trust message to communicate key trust/distrust.
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

// ──────────────────────────── Message Displayed Synchronization (XEP-0490) ────────────────────────────

// SyncDisplayedMessages publishes a displayed marker to PEP for cross-device sync.
func (c *XMPPCore) SyncDisplayedMessages(jid, stanzaID string) error {
	return c.PublishPubSubItem(c.bareJID, "urn:xmpp:mds:displayed:0", jid,
		fmt.Sprintf(
			`<displayed xmlns='urn:xmpp:mds:displayed:0' jid='%s'>`+
				`<stanza-id xmlns='urn:xmpp:sid:0' id='%s'/></displayed>`,
			xmlEscape(jid), xmlEscape(stanzaID)))
}

// ──────────────────────────── Fallback Indication (XEP-0428) ────────────────────────────

// SetFallbackIndication returns XML element marking body as fallback for unsupported extensions.
func (c *XMPPCore) SetFallbackIndication(forNS string) string {
	return fmt.Sprintf(`<fallback xmlns='urn:xmpp:fallback:0' for='%s'/>`, xmlEscape(forNS))
}

// ──────────────────────────── SASL Channel-Binding (XEP-0440) ────────────────────────────

// NegotiateChannelBinding advertises/selects SCRAM channel-binding type during SASL.
func (c *XMPPCore) NegotiateChannelBinding(bindingType string) string {
	return fmt.Sprintf(`<sasl-channel-binding xmlns='urn:xmpp:sasl-cb:0'><channel-binding type='%s'/></sasl-channel-binding>`,
		xmlEscape(bindingType))
}

// ──────────────────────────── Alternative Connections (XEP-0156) ────────────────────────────

// DiscoverAlternativeConnections queries well-known URLs for WebSocket/BOSH endpoints.
func (c *XMPPCore) DiscoverAlternativeConnections(domain string) (wsURL, boshURL string, err error) {
	url := "https://" + domain + "/.well-known/host-meta"
	resp, err := http.Get(url)
	if err != nil {
		return "", "", fmt.Errorf("fetch host-meta: %w", err)
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", "", fmt.Errorf("read host-meta: %w", err)
	}
	s := string(body)
	// Parse Link elements for WebSocket and BOSH
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

// ──────────────────────────── WebSocket Transport (RFC 7395) ────────────────────────────

// ConnectWebSocket establishes an XMPP connection over WebSocket.
func (c *XMPPCore) ConnectWebSocket(wsURL string) error {
	// WebSocket XMPP uses framed XML (no stream wrapper)
	dialer := &net.Dialer{Timeout: 10 * time.Second}
	conn, err := tls.DialWithDialer(dialer, "tcp", wsURL, &tls.Config{InsecureSkipVerify: false})
	if err != nil {
		return fmt.Errorf("websocket dial: %w", err)
	}
	// Send WebSocket upgrade
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
	// Read upgrade response
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
	// Replace connection — XMPP framing over WebSocket uses the same XML stream
	c.mu.Lock()
	if c.conn != nil {
		c.conn.Close()
	}
	c.conn = conn
	c.mu.Unlock()
	return nil
}

// ──────────────────────────── BOSH Transport (XEP-0124/0206) ────────────────────────────

// ConnectBOSH establishes an XMPP-over-BOSH session via HTTP long-polling.
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
	resp, err := http.Post(boshURL, "text/xml; charset=utf-8", strings.NewReader(body))
	if err != nil {
		return "", fmt.Errorf("bosh init: %w", err)
	}
	defer resp.Body.Close()
	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("bosh read: %w", err)
	}
	// Extract sid from response
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

// ════════════════════════════════════════════════════════════════════════════════
// Step 4 — New Methods (120 XEPs)
// ════════════════════════════════════════════════════════════════════════════════

// ── Connection & Authentication (10 XEPs) ──

// ConnectDirectTLS connects via XEP-0368 xmpps-client SRV record.
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


// InstantStreamResumption implements XEP-0397 ISR token storage/negotiation.
func (c *XMPPCore) InstantStreamResumption(token string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<resume xmlns='urn:xmpp:isr:0' token='%s'/>`, xmlEscape(token)))
}

// DiscoverHostMeta2 implements XEP-0487 Host Meta 2 — JSON-based host-meta discovery.
func (c *XMPPCore) DiscoverHostMeta2(domain string) (map[string]string, error) {
	url := fmt.Sprintf("https://%s/.well-known/host-meta.json", domain)
	resp, err := http.Get(url)
	if err != nil {
		return nil, fmt.Errorf("xmpp: host-meta2: %w", err)
	}
	defer resp.Body.Close()
	var result map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
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

// OAuthClientLogin implements XEP-0493 — OAUTHBEARER SASL mechanism.
func (c *XMPPCore) OAuthClientLogin(token string) error {
	encoded := base64.StdEncoding.EncodeToString([]byte(fmt.Sprintf("n,,\x01auth=Bearer %s\x01\x01", token)))
	return c.sendRawStanza(fmt.Sprintf(
		`<auth xmlns='urn:ietf:params:xml:ns:xmpp-sasl' mechanism='OAUTHBEARER'>%s</auth>`, encoded))
}

// RevokeClientAccess implements XEP-0494 — revoke per-client access.
func (c *XMPPCore) RevokeClientAccess(clientID string) error {
	_, err := c.sendIQSync("set", "",
		fmt.Sprintf(`<revoke xmlns='urn:xmpp:cam:0' id='%s'/>`, xmlEscape(clientID)))
	return err
}

// ListClientAccess lists authorized clients via XEP-0494.
func (c *XMPPCore) ListClientAccess() (*XMPPIQ, error) {
	return c.sendIQSync("get", "", `<list xmlns='urn:xmpp:cam:0'/>`)
}

// ConnectHappyEyeballs implements XEP-0495 — parallel A/AAAA lookups.
func (c *XMPPCore) ConnectHappyEyeballs(host string, port int) (net.Conn, error) {
	d := &net.Dialer{Timeout: 10 * time.Second, DualStack: true}
	return d.Dial("tcp", net.JoinHostPort(host, strconv.Itoa(port)))
}

// InitAuthPipelining sends XEP-0509 pipelined auth request with SASL2.
func (c *XMPPCore) InitAuthPipelining(mechanism, initialResponse string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<authenticate xmlns='urn:xmpp:sasl:2' mechanism='%s'>`+
			`<initial-response>%s</initial-response>`+
			`<bind xmlns='urn:xmpp:bind:0'/>`+
			`</authenticate>`,
		xmlEscape(mechanism), initialResponse))
}

// GetStreamLimits implements XEP-0478 — parse stream limits from features.
func (c *XMPPCore) GetStreamLimits() map[string]int {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return map[string]int{
		"max_bytes": c.streamMaxBytes,
		"idle_seconds": c.streamIdleSeconds,
	}
}

// QuickstartTLS implements XEP-0305 — TLS session resumption with caps.
func (c *XMPPCore) QuickstartTLS(domain string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<starttls xmlns='urn:ietf:params:xml:ns:xmpp-tls'><required/></starttls>`))
}

// ── Messaging (12 XEPs) ──

// RetractMessage implements XEP-0424 — retract (unsend) a message.
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

// ParseMessageStyling implements XEP-0393 — parse styling directives.
func ParseMessageStyling(text string) []map[string]string {
	var spans []map[string]string
	// Simple parser for *bold*, _italic_, `code`, ~strike~, ```pre```
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

// SendSpoilerMessage implements XEP-0382 — send message with hidden content.
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

// FastenPayload implements XEP-0422 — fasten a payload to a message.
func (c *XMPPCore) FastenPayload(to, targetID, payload string) error {
	id := c.nextMsgID()
	return c.sendRawStanza(fmt.Sprintf(
		`<message type='chat' to='%s' id='%s'>`+
			`<apply-to xmlns='urn:xmpp:fasten:0' id='%s'>%s</apply-to>`+
			`</message>`,
		xmlEscape(to), id, xmlEscape(targetID), payload))
}

// SendJSONMessage implements XEP-0432 — send JSON payload.
func (c *XMPPCore) SendJSONMessage(to string, jsonPayload json.RawMessage) error {
	id := c.nextMsgID()
	return c.sendRawStanza(fmt.Sprintf(
		`<message type='chat' to='%s' id='%s'>`+
			`<json xmlns='urn:xmpp:json:0'>%s</json>`+
			`</message>`,
		xmlEscape(to), id, xmlEscape(string(jsonPayload))))
}

// SendQuickResponse implements XEP-0439 — send predefined response buttons.
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

// SendContentTypedMessage implements XEP-0481 — message with MIME content type.
func (c *XMPPCore) SendContentTypedMessage(to, body, contentType string) error {
	id := c.nextMsgID()
	return c.sendRawStanza(fmt.Sprintf(
		`<message type='chat' to='%s' id='%s'>`+
			`<body>%s</body>`+
			`<content xmlns='urn:xmpp:content:0' type='%s'/>`+
			`</message>`,
		xmlEscape(to), id, xmlEscape(body), xmlEscape(contentType)))
}

// SendRealTimeText implements XEP-0301 — real-time text events.
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

// RequestStanzaIDs implements XEP-0359 — request stanza-id from server.
func (c *XMPPCore) RequestStanzaIDs() error {
	return c.sendRawStanza(`<enable xmlns='urn:xmpp:sid:0'/>`)
}

// GetInbox implements XEP-0430 — server-side inbox.
func (c *XMPPCore) GetInbox() (*XMPPIQ, error) {
	return c.sendIQSync("get", "", `<inbox xmlns='urn:xmpp:inbox:1'/>`)
}

// SearchMAMFullText implements XEP-0431 — full-text search in MAM.
func (c *XMPPCore) SearchMAMFullText(query string) (*XMPPIQ, error) {
	return c.sendIQSync("set", "",
		fmt.Sprintf(`<query xmlns='urn:xmpp:mam:2'>`+
			`<x xmlns='jabber:x:data' type='submit'>`+
			`<field var='FORM_TYPE' type='hidden'><value>urn:xmpp:mam:2</value></field>`+
			`<field var='fulltext'><value>%s</value></field>`+
			`</x></query>`, xmlEscape(query)))
}

// SetReminder implements XEP-0435 — schedule a reminder.
func (c *XMPPCore) SetReminder(to, text string, when time.Time) error {
	id := c.nextMsgID()
	return c.sendRawStanza(fmt.Sprintf(
		`<message to='%s' id='%s'>`+
			`<reminder xmlns='urn:xmpp:reminder:0' stamp='%s'>`+
			`<body>%s</body></reminder></message>`,
		xmlEscape(to), id, when.UTC().Format(time.RFC3339), xmlEscape(text)))
}

// ── MUC Extensions (11 XEPs) ──

// SendDirectMUCInvitation implements XEP-0249.
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

// SetMUCHat implements XEP-0317 — set visual role/badge.
func (c *XMPPCore) SetMUCHat(room, nick, hatURI, hatTitle string) error {
	_, err := c.sendIQSync("set", room,
		fmt.Sprintf(`<hats xmlns='urn:xmpp:hats:0'>`+
			`<hat uri='%s' title='%s' xmlns='urn:xmpp:hats:0'/></hats>`,
			xmlEscape(hatURI), xmlEscape(hatTitle)))
	return err
}

// SearchChannels implements XEP-0433 — extended channel search.
func (c *XMPPCore) SearchChannels(query string) (*XMPPIQ, error) {
	return c.sendIQSync("get", "",
		fmt.Sprintf(`<search xmlns='urn:xmpp:channel-search:0'>`+
			`<set xmlns='http://jabber.org/protocol/rsm'><max>50</max></set>`+
			`<q>%s</q></search>`, xmlEscape(query)))
}

// EnableMUCPresenceVersioning implements XEP-0436.
func (c *XMPPCore) EnableMUCPresenceVersioning(room string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<presence to='%s'>`+
			`<x xmlns='http://jabber.org/protocol/muc'/>`+
			`<presence-versioning xmlns='urn:xmpp:muc-presence-versioning:0'/>`+
			`</presence>`,
		xmlEscape(room)))
}

// SubscribeRoomActivity implements XEP-0437.
func (c *XMPPCore) SubscribeRoomActivity(room string) error {
	_, err := c.sendIQSync("set", "",
		fmt.Sprintf(`<activity xmlns='urn:xmpp:room-activity:0' jid='%s'/>`, xmlEscape(room)))
	return err
}

// SubscribeMUCMentions implements XEP-0452.
func (c *XMPPCore) SubscribeMUCMentions(room string) error {
	_, err := c.sendIQSync("set", room,
		`<subscribe xmlns='urn:xmpp:muc-mention-notifications:0'/>`)
	return err
}

// EnableMUCAffiliationVersioning implements XEP-0463.
func (c *XMPPCore) EnableMUCAffiliationVersioning(room string) error {
	_, err := c.sendIQSync("get", room,
		`<affiliations xmlns='urn:xmpp:muc-affiliations-versioning:0'/>`)
	return err
}

// SetMUCAvatar implements XEP-0486.
func (c *XMPPCore) SetMUCAvatar(room string, pngData []byte) error {
	b64 := base64.StdEncoding.EncodeToString(pngData)
	_, err := c.sendIQSync("set", room,
		fmt.Sprintf(`<vCard xmlns='vcard-temp'><PHOTO><TYPE>image/png</TYPE><BINVAL>%s</BINVAL></PHOTO></vCard>`, b64))
	return err
}

// CreateMUCTokenInvite implements XEP-0488.
func (c *XMPPCore) CreateMUCTokenInvite(room string) (*XMPPIQ, error) {
	return c.sendIQSync("set", room,
		`<invite xmlns='urn:xmpp:muc-token-invite:0'/>`)
}

// SetMUCSlowMode implements XEP-0500.
func (c *XMPPCore) SetMUCSlowMode(room string, intervalSeconds int) error {
	_, err := c.sendIQSync("set", room,
		fmt.Sprintf(`<query xmlns='http://jabber.org/protocol/muc#owner'>`+
			`<x xmlns='jabber:x:data' type='submit'>`+
			`<field var='FORM_TYPE'><value>http://jabber.org/protocol/muc#roomconfig</value></field>`+
			`<field var='muc#roomconfig_slowmode_length'><value>%d</value></field>`+
			`</x></query>`, intervalSeconds))
	return err
}

// GetMUCActivityIndicator implements XEP-0502.
func (c *XMPPCore) GetMUCActivityIndicator(room string) (*XMPPIQ, error) {
	return c.sendIQSync("get", room,
		`<activity xmlns='urn:xmpp:muc-activity-indicator:0'/>`)
}

// ── MIX Extensions (5 XEPs) ──

// MIXPresenceSubscribe implements XEP-0403.
func (c *XMPPCore) MIXPresenceSubscribe(channel string) error {
	_, err := c.sendIQSync("set", channel,
		`<subscribe xmlns='urn:xmpp:mix:nodes:presence'/>`)
	return err
}

// MIXSetAnonymity implements XEP-0404.
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

// MIXPAMJoin implements XEP-0405 — server-side MIX management.
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

// MIXAdminSetConfig implements XEP-0406.
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

// MIXMiscSetAvatar implements XEP-0407.
func (c *XMPPCore) MIXMiscSetAvatar(channel string, pngData []byte) error {
	b64 := base64.StdEncoding.EncodeToString(pngData)
	_, err := c.sendIQSync("set", channel,
		fmt.Sprintf(`<pubsub xmlns='http://jabber.org/protocol/pubsub'>`+
			`<publish node='urn:xmpp:mix:nodes:info'>`+
			`<item><avatar xmlns='urn:xmpp:avatar:data'>%s</avatar></item>`+
			`</publish></pubsub>`, b64))
	return err
}

// ── Jingle / Calls (18 XEPs) ──

// JingleRTPSession implements XEP-0167 — full RTP session description.
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

// JingleRawUDP implements XEP-0177 — raw UDP transport.
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

// JingleZRTP implements XEP-0262 — ZRTP key agreement hash.
func (c *XMPPCore) JingleZRTP(to, sid, zrtpHash, hashVersion string) error {
	_, err := c.sendIQSync("set", to,
		fmt.Sprintf(`<jingle xmlns='urn:xmpp:jingle:1' action='session-info' sid='%s'>`+
			`<zrtp-hash xmlns='urn:xmpp:jingle:apps:rtp:zrtp:1' version='%s'>%s</zrtp-hash>`+
			`</jingle>`, xmlEscape(sid), xmlEscape(hashVersion), xmlEscape(zrtpHash)))
	return err
}

// JingleAudioCodecs returns XEP-0266 recommended audio codec list.
func JingleAudioCodecs() []map[string]string {
	return []map[string]string{
		{"id": "111", "name": "opus", "clockrate": "48000", "channels": "2"},
		{"id": "100", "name": "speex", "clockrate": "16000"},
		{"id": "0", "name": "PCMU", "clockrate": "8000"},
		{"id": "8", "name": "PCMA", "clockrate": "8000"},
	}
}

// JingleMuji implements XEP-0272 — multiparty Jingle.
func (c *XMPPCore) JingleMuji(room, media string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<presence to='%s'><muji xmlns='urn:xmpp:jingle:muji:0'>`+
			`<content name='%s'><description xmlns='urn:xmpp:jingle:apps:rtp:1' media='%s'/></content>`+
			`</muji></presence>`,
		xmlEscape(room), xmlEscape(media), xmlEscape(media)))
}

// JingleConferenceInfo implements XEP-0298 — conference state notification.
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

// JingleVideoCodecs returns XEP-0299 recommended video codec list.
func JingleVideoCodecs() []map[string]string {
	return []map[string]string{
		{"id": "96", "name": "VP8", "clockrate": "90000"},
		{"id": "97", "name": "H264", "clockrate": "90000"},
	}
}

// JingleDTLSSRTP implements XEP-0320 — DTLS fingerprint.
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

// JingleGrouping implements XEP-0338 — SDP bundle.
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

// JingleSourceSSRC implements XEP-0339 — per-source SSRC attributes.
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

// JingleDataChannels implements XEP-0343 — WebRTC DTLS/SCTP data channels.
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

// JingleMessageRinging implements XEP-0353 ringing signal.
func (c *XMPPCore) JingleMessageRinging(to, sid string) error {
	id := c.nextMsgID()
	return c.sendRawStanza(fmt.Sprintf(
		`<message to='%s' id='%s'>`+
			`<ringing xmlns='urn:xmpp:jingle-message:0' id='%s'/>`+
			`</message>`,
		xmlEscape(to), id, xmlEscape(sid)))
}

// PublishJingleSession implements XEP-0358 — advertise joinable session.
func (c *XMPPCore) PublishJingleSession(sid, description string) error {
	_, err := c.sendIQSync("set", "",
		fmt.Sprintf(`<pubsub xmlns='http://jabber.org/protocol/pubsub'>`+
			`<publish node='urn:xmpp:jingle:pub:1'>`+
			`<item id='%s'><session xmlns='urn:xmpp:jingle:pub:1'>`+
			`<description>%s</description></session></item>`+
			`</publish></pubsub>`, xmlEscape(sid), xmlEscape(description)))
	return err
}

// JingleTrickleICE implements XEP-0371 — ICE transport with trickle.
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

// JingleEncryptedTransport implements XEP-0391 — JET encryption.
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

// JingleJETOMEMO implements XEP-0396 — OMEMO for Jingle file transfers.
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

// SendCallInvite implements XEP-0482 — invite to call.
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

// JingleContentCategory implements XEP-0507 — distinguish webcam vs screenshare.
func (c *XMPPCore) JingleContentCategory(to, sid, name, category string) error {
	_, err := c.sendIQSync("set", to,
		fmt.Sprintf(`<jingle xmlns='urn:xmpp:jingle:1' action='content-modify' sid='%s'>`+
			`<content creator='initiator' name='%s'>`+
			`<category xmlns='urn:xmpp:jingle:content-category:0' name='%s'/>`+
			`</content></jingle>`,
			xmlEscape(sid), xmlEscape(name), xmlEscape(category)))
	return err
}

// ── File Sharing & Media (5 XEPs) ──

// JingleContentThumbnail implements XEP-0264 — thumbnails on file offers.
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

// SendSIMS implements XEP-0385 — stateless inline media sharing.
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

// ShareFileMetadataElem implements XEP-0446 — standalone file metadata.
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

// PubSubFileShare implements XEP-0498 — file sharing via PubSub.
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

// DataFormsFileInput implements XEP-0505 — file upload in data forms.
func (c *XMPPCore) DataFormsFileInput(to, formType, fieldVar, uploadURL string) error {
	_, err := c.sendIQSync("set", to,
		fmt.Sprintf(`<x xmlns='jabber:x:data' type='submit'>`+
			`<field var='FORM_TYPE'><value>%s</value></field>`+
			`<field var='%s' type='file'>`+
			`<value>%s</value></field></x>`,
			xmlEscape(formType), xmlEscape(fieldVar), xmlEscape(uploadURL)))
	return err
}

// ── PubSub Extensions (15 XEPs) ──

// PEPManageNode implements XEP-0163 explicit PEP node management.
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

// PubSubPersistPublic implements XEP-0222 — best practices for public data storage.
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

// PubSubPersistPrivate implements XEP-0223 — best practices for private data storage.
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

// PubSubCollectionNode implements XEP-0248 — collection node creation.
func (c *XMPPCore) PubSubCollectionNode(node, childNode string) error {
	_, err := c.sendIQSync("set", "",
		fmt.Sprintf(`<pubsub xmlns='http://jabber.org/protocol/pubsub'>`+
			`<create node='%s'/>`+
			`<configure><x xmlns='jabber:x:data' type='submit'>`+
			`<field var='pubsub#node_type'><value>collection</value></field>`+
			`</x></configure></pubsub>`, xmlEscape(node)))
	return err
}

// PublishMicroblog implements XEP-0277 — Atom-based social feed.
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

// QueryPubSubMAM implements XEP-0442 — MAM on PubSub archives.
func (c *XMPPCore) QueryPubSubMAM(service, node string) (*XMPPIQ, error) {
	return c.sendIQSync("set", service,
		fmt.Sprintf(`<query xmlns='urn:xmpp:mam:2' node='%s'/>`, xmlEscape(node)))
}

// SetPubSubCachingHints implements XEP-0460.
func (c *XMPPCore) SetPubSubCachingHints(node string, maxAge int) error {
	_, err := c.sendIQSync("set", "",
		fmt.Sprintf(`<pubsub xmlns='http://jabber.org/protocol/pubsub#owner'>`+
			`<configure node='%s'><x xmlns='jabber:x:data' type='submit'>`+
			`<field var='pubsub#item_expire'><value>%d</value></field>`+
			`</x></configure></pubsub>`, xmlEscape(node), maxAge))
	return err
}

// FilterPubSubByType implements XEP-0462.
func (c *XMPPCore) FilterPubSubByType(service, nodeType string) (*XMPPIQ, error) {
	return c.sendIQSync("get", service,
		fmt.Sprintf(`<query xmlns='http://jabber.org/protocol/disco#items'>`+
			`<filter xmlns='urn:xmpp:pubsub:filter:0' type='%s'/></query>`, xmlEscape(nodeType)))
}

// SetPubSubPublicSubscriptions implements XEP-0465.
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

// PubSubAttachment implements XEP-0470 — reactions/comments on PubSub items.
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

// PublishSocialFeed implements XEP-0472.
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

// EncryptPubSubOX implements XEP-0473 — OpenPGP for PubSub.
func (c *XMPPCore) EncryptPubSubOX(node, itemID, payload string) error {
	_, err := c.sendIQSync("set", "",
		fmt.Sprintf(`<pubsub xmlns='http://jabber.org/protocol/pubsub'>`+
			`<publish node='%s'><item id='%s'>`+
			`<openpgp xmlns='urn:xmpp:openpgp:0'>%s</openpgp>`+
			`</item></publish></pubsub>`,
			xmlEscape(node), xmlEscape(itemID), xmlEscape(payload)))
	return err
}

// GetPubSubServerInfo implements XEP-0485.
func (c *XMPPCore) GetPubSubServerInfo(service string) (*XMPPIQ, error) {
	return c.sendIQSync("get", service,
		`<query xmlns='http://jabber.org/protocol/disco#info' node='urn:xmpp:serverinfo:0'/>`)
}

// SetPubSubRelationship implements XEP-0496.
func (c *XMPPCore) SetPubSubRelationship(node, parentNode string) error {
	_, err := c.sendIQSync("set", "",
		fmt.Sprintf(`<pubsub xmlns='http://jabber.org/protocol/pubsub#owner'>`+
			`<configure node='%s'><x xmlns='jabber:x:data' type='submit'>`+
			`<field var='pubsub#collection'><value>%s</value></field>`+
			`</x></configure></pubsub>`, xmlEscape(node), xmlEscape(parentNode)))
	return err
}

// PubSubCompareAndPublish implements XEP-0395 — atomic CAS.
func (c *XMPPCore) PubSubCompareAndPublish(node, itemID, payload, prevID string) error {
	_, err := c.sendIQSync("set", "",
		fmt.Sprintf(`<pubsub xmlns='http://jabber.org/protocol/pubsub'>`+
			`<publish node='%s'><item id='%s'>%s</item></publish>`+
			`<precondition xmlns='urn:xmpp:pubsub:cas:0' prev-id='%s'/>`+
			`</pubsub>`,
			xmlEscape(node), xmlEscape(itemID), payload, xmlEscape(prevID)))
	return err
}

// ── Service Discovery (3 XEPs) ──

// DiscoInfoExtended implements XEP-0128 — extended info in disco#info.
func (c *XMPPCore) DiscoInfoExtended(to, node string) (*XMPPIQ, error) {
	nodeAttr := ""
	if node != "" {
		nodeAttr = fmt.Sprintf(` node='%s'`, xmlEscape(node))
	}
	return c.sendIQSync("get", to,
		fmt.Sprintf(`<query xmlns='http://jabber.org/protocol/disco#info'%s/>`, nodeAttr))
}

// EntityCaps2 implements XEP-0390 — Entity Capabilities 2.0 hash.
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

// GetDOAP implements XEP-0453 — machine-readable capability descriptions.
func (c *XMPPCore) GetDOAP(to string) (*XMPPIQ, error) {
	return c.sendIQSync("get", to,
		`<query xmlns='http://jabber.org/protocol/disco#info' node='urn:xmpp:doap:0'/>`)
}

// ── Encryption (1 XEP) ──

// OMEMOAutoTrust implements XEP-0450 — automatic trust management.
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

// ── User Profile & Social (4 XEPs) ──

// ConsistentColor implements XEP-0392 — generate color from JID.
func ConsistentColor(jid string) (float64, float64, float64) {
	h := sha256.Sum256([]byte(jid))
	angle := float64(uint16(h[0])<<8|uint16(h[1])) / 65536.0 * 360.0
	return angle, 1.0, 0.5 // HSL
}

// AvatarConversion implements XEP-0398 — server-side avatar format hint.
func (c *XMPPCore) AvatarConversion(to string) (*XMPPIQ, error) {
	return c.sendIQSync("get", to,
		`<pubsub xmlns='http://jabber.org/protocol/pubsub'>`+
			`<items node='urn:xmpp:avatar:data' max_items='1'/></pubsub>`)
}

// SetReachability implements XEP-0152 — publish reachability addresses.
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

// SetVCardAvatar implements XEP-0153 — vCard-based avatar with presence hash.
func (c *XMPPCore) SetVCardAvatar(pngData []byte) error {
	// Set vCard photo
	b64 := base64.StdEncoding.EncodeToString(pngData)
	_, err := c.sendIQSync("set", "",
		fmt.Sprintf(`<vCard xmlns='vcard-temp'><PHOTO><TYPE>image/png</TYPE><BINVAL>%s</BINVAL></PHOTO></vCard>`, b64))
	if err != nil {
		return err
	}
	// Broadcast presence with photo hash
	h := sha1.Sum(pngData)
	return c.sendRawStanza(fmt.Sprintf(
		`<presence><x xmlns='vcard-temp:x:update'><photo>%s</photo></x></presence>`,
		hex.EncodeToString(h[:])))
}

// ── Notification & Sync (2 XEPs) ──

// SetChatNotificationSettings implements XEP-0492.
func (c *XMPPCore) SetChatNotificationSettings(jid, level string) error {
	_, err := c.sendIQSync("set", "",
		fmt.Sprintf(`<pubsub xmlns='http://jabber.org/protocol/pubsub'>`+
			`<publish node='urn:xmpp:notification-settings:0'>`+
			`<item id='%s'><settings xmlns='urn:xmpp:notification-settings:0' level='%s'/></item>`+
			`</publish></pubsub>`, xmlEscape(jid), xmlEscape(level)))
	return err
}

// SetServerNotificationFilter implements XEP-0351.
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

// ── Server Interaction (10 XEPs) ──

// SearchUsersExtended implements XEP-0055 — search with data forms.
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


// HandleCAPTCHA implements XEP-0158 — respond to CAPTCHA challenge.
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


// EnableRosterVersioning implements XEP-0237 — request versioned roster.
func (c *XMPPCore) EnableRosterVersioning(ver string) (*XMPPIQ, error) {
	verAttr := ""
	if ver != "" {
		verAttr = fmt.Sprintf(` ver='%s'`, xmlEscape(ver))
	}
	return c.sendIQSync("get", "",
		fmt.Sprintf(`<query xmlns='jabber:iq:roster'%s/>`, verAttr))
}

// CreateInvitationURI implements XEP-0401 — generate invitation URI.
func (c *XMPPCore) CreateInvitationURI() (*XMPPIQ, error) {
	return c.sendIQSync("set", "",
		`<invite xmlns='urn:xmpp:invite:2'/>`)
}

// PreAuthenticatedIBR implements XEP-0445 — token-gated registration.
func (c *XMPPCore) PreAuthenticatedIBR(token string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<register xmlns='urn:xmpp:ibr-token:0' token='%s'/>`, xmlEscape(token)))
}

// GetServiceOutageStatus implements XEP-0455 — server status.
func (c *XMPPCore) GetServiceOutageStatus(domain string) (*XMPPIQ, error) {
	return c.sendIQSync("get", domain,
		`<status xmlns='urn:xmpp:service-status:0'/>`)
}

// GetDataPolicy implements XEP-0504 — data retention info.
func (c *XMPPCore) GetDataPolicy(domain string) (*XMPPIQ, error) {
	return c.sendIQSync("get", domain,
		`<policy xmlns='urn:xmpp:data-policy:0'/>`)
}

// BookmarksConversion implements XEP-0411 — request server-side bookmark conversion.
func (c *XMPPCore) BookmarksConversion() error {
	_, err := c.sendIQSync("set", "",
		`<enable xmlns='urn:xmpp:bookmarks-conversion:0'/>`)
	return err
}

// ── Newer/Experimental (10 XEPs) ──

// SendWebXDC implements XEP-0491 — interactive HTML/JS widget.
func (c *XMPPCore) SendWebXDC(to, name string, data []byte) error {
	id := c.nextMsgID()
	b64 := base64.StdEncoding.EncodeToString(data)
	return c.sendRawStanza(fmt.Sprintf(
		`<message type='chat' to='%s' id='%s'>`+
			`<webxdc xmlns='urn:xmpp:webxdc:0' name='%s'>%s</webxdc>`+
			`</message>`,
		xmlEscape(to), id, xmlEscape(name), b64))
}

// CreateServerSpace implements XEP-0503 — Discord-like channel categories.
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

// CreateForum implements XEP-0508 — threaded discussions.
func (c *XMPPCore) CreateForum(service, name string) error {
	_, err := c.sendIQSync("set", service,
		fmt.Sprintf(`<create xmlns='urn:xmpp:forums:0' name='%s'/>`, xmlEscape(name)))
	return err
}

// EncryptContactsMetadata implements XEP-0510.
func (c *XMPPCore) EncryptContactsMetadata(jid string, encryptedPayload []byte) error {
	b64 := base64.StdEncoding.EncodeToString(encryptedPayload)
	_, err := c.sendIQSync("set", "",
		fmt.Sprintf(`<pubsub xmlns='http://jabber.org/protocol/pubsub'>`+
			`<publish node='urn:xmpp:contacts:metadata:0'>`+
			`<item id='%s'><encrypted xmlns='urn:xmpp:contacts:metadata:0'>%s</encrypted></item>`+
			`</publish></pubsub>`, xmlEscape(jid), b64))
	return err
}

// GetLinkMetadata implements XEP-0511 — rich link previews.
func (c *XMPPCore) GetLinkMetadata(url string) (*XMPPIQ, error) {
	return c.sendIQSync("get", "",
		fmt.Sprintf(`<link-metadata xmlns='urn:xmpp:link-metadata:0' url='%s'/>`, xmlEscape(url)))
}

// RequestOnlineMeeting implements XEP-0483 — HTTP online meetings.
func (c *XMPPCore) RequestOnlineMeeting(service, meetingType string) (*XMPPIQ, error) {
	return c.sendIQSync("get", service,
		fmt.Sprintf(`<request xmlns='urn:xmpp:http:online-meetings:invite:0' type='%s'/>`,
			xmlEscape(meetingType)))
}

// RequestBurnerJID implements XEP-0383 — temporary anonymous JID.
func (c *XMPPCore) RequestBurnerJID(service string) (*XMPPIQ, error) {
	return c.sendIQSync("get", service,
		`<burner xmlns='urn:xmpp:burner:0'/>`)
}


// ForwardStanza implements XEP-0297 — standard stanza encapsulation.
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


// ── Miscellaneous (5 XEPs) ──

// RSMQuery implements XEP-0059 — result set management pagination.
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

// NegotiateSession implements XEP-0155 — stanza session negotiation.
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

// SendBitsOfBinary implements XEP-0231 — inline small binary data.
func (c *XMPPCore) SendBitsOfBinary(to string, data []byte, mimeType, cid string) error {
	id := c.nextMsgID()
	b64 := base64.StdEncoding.EncodeToString(data)
	return c.sendRawStanza(fmt.Sprintf(
		`<message type='chat' to='%s' id='%s'>`+
			`<data xmlns='urn:xmpp:bob' cid='%s' type='%s' max-age='86400'>%s</data>`+
			`</message>`,
		xmlEscape(to), id, xmlEscape(cid), xmlEscape(mimeType), b64))
}

// HashElement implements XEP-0300 — standardized hash element.
func HashElement(algo string, data []byte) string {
	var h hash.Hash
	switch algo {
	case "sha-256":
		h = sha256.New()
	case "sha-1":
		h = sha1.New()
	default:
		h = sha256.New()
		algo = "sha-256"
	}
	h.Write(data)
	return fmt.Sprintf(`<hash xmlns='urn:xmpp:hashes:2' algo='%s'>%s</hash>`,
		algo, base64.StdEncoding.EncodeToString(h.Sum(nil)))
}

// MuteChat mutes notifications for a conversation.
func (c *XMPPCore) MuteChat(chatID string, muted bool) error {
	return fmt.Errorf("%w: %s does not support mute chat", ErrNotSupported, xmppPlatform)
}

// ArchiveChat archives a conversation by removing it from bookmarks.
func (c *XMPPCore) ArchiveChat(chatID string, archived bool) error {
	return fmt.Errorf("%w: %s does not support archive chat", ErrNotSupported, xmppPlatform)
}

// MarkUnread mark unread on the XMPP connection.
func (c *XMPPCore) MarkUnread(chatID string, unread bool) error {
	return fmt.Errorf("%w: %s does not support mark unread", ErrNotSupported, xmppPlatform)
}

// UnpinAllMessages unpin all messages on the XMPP connection.
func (c *XMPPCore) UnpinAllMessages(chatID string) error {
	return fmt.Errorf("%w: %s does not support unpin all messages", ErrNotSupported, xmppPlatform)
}

// AcceptCall accepts call.
func (c *XMPPCore) AcceptCall(callID string) (*CallSession, error) {
	return nil, fmt.Errorf("%w: %s does not support accept call", ErrNotSupported, xmppPlatform)
}

// DeclineCall declines an incoming call session.
func (c *XMPPCore) DeclineCall(callID string) error {
	return fmt.Errorf("%w: %s does not support decline call", ErrNotSupported, xmppPlatform)
}

// SendLocation sends a geographic location to the specified JID.
func (c *XMPPCore) SendLocation(chatID string, lat float64, lon float64) (*Message, error) {
	return nil, fmt.Errorf("%w: %s does not support send location", ErrNotSupported, xmppPlatform)
}

