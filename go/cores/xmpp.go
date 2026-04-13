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
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha1"
	"crypto/sha256"
	"crypto/tls"
	"encoding/base64"
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

const (
	xmppDefaultPort    = "5222"
	xmppDirectTLSPort  = "5223"
	xmppMsgBufSize     = 500
	xmppPingInterval   = 60 * time.Second
	xmppSendDelay      = 100 * time.Millisecond
	xmppIQTimeout      = 30 * time.Second
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
type xmppIQ struct {
	XMLName xml.Name     `xml:"iq"`
	Type    string       `xml:"type,attr"`
	ID      string       `xml:"id,attr,omitempty"`
	To      string       `xml:"to,attr,omitempty"`
	From    string       `xml:"from,attr,omitempty"`
	Lang    string       `xml:"xml:lang,attr,omitempty"`
	Inner   string       `xml:",innerxml"`
	Error   *xmppStanzaError `xml:"error"`
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

type xmppStanzaError struct {
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
	ch      chan *xmppIQ
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

	// Real-time
	updateHandlers []func(Update)
	updateMu       sync.RWMutex

	// Lifecycle
	sessionPath string
	ctx         context.Context
	cancel      context.CancelFunc
}

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

func (c *XMPPCore) Name() string { return "xmpp" }

func (c *XMPPCore) Capabilities() []string {
	return []string{
		"messaging", "groups", "presence", "file_transfer",
		"reactions", "replies", "corrections", "read_receipts",
		"typing", "blocking", "search", "muc",
		"pubsub", "vcard", "bookmarks", "carbons",
		"stream_management", "service_discovery",
	}
}

// ---------------------------------------------------------------------------
// Core interface — Auth
// ---------------------------------------------------------------------------

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
	go c.readLoop()
	go c.pingLoop()

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

	return nil
}

func (c *XMPPCore) Logout() error {
	c.mu.RLock()
	authed := c.authed
	c.mu.RUnlock()
	if !authed {
		return nil
	}

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

	header := fmt.Sprintf(
		`<?xml version='1.0'?><stream:stream to='%s' xmlns='%s' xmlns:stream='%s' version='1.0'>`,
		xmlEscape(domain), nsClient, nsStream,
	)

	c.writeMu.Lock()
	_, err := c.conn.Write([]byte(header))
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
	for {
		b, err := reader.ReadByte()
		if err != nil {
			return fmt.Errorf("read stream: %w", err)
		}
		buf.WriteByte(b)
		data := buf.String()

		// Check if we have complete features
		if strings.Contains(data, "</stream:features>") {
			// Create the xml.Decoder from the same buffered reader
			// so it picks up any bytes read after features
			c.mu.Lock()
			c.decoder = xml.NewDecoder(reader)
			c.mu.Unlock()
			return c.parseStreamFeatures(data)
		}
		if strings.Contains(data, "</features>") {
			c.mu.Lock()
			c.decoder = xml.NewDecoder(reader)
			c.mu.Unlock()
			return c.parseStreamFeatures(data)
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
	// Send STARTTLS
	c.writeMu.Lock()
	c.conn.Write([]byte(fmt.Sprintf(`<starttls xmlns='%s'/>`, nsTLS)))
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

	// PLAIN: \0authcid\0password
	payload := base64.StdEncoding.EncodeToString([]byte("\x00" + local + "\x00" + password))

	c.writeMu.Lock()
	c.conn.Write([]byte(fmt.Sprintf(
		`<auth xmlns='%s' mechanism='PLAIN'>%s</auth>`, nsSASL, payload,
	)))
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
	c.conn.Write([]byte(fmt.Sprintf(
		`<auth xmlns='%s' mechanism='%s'>%s</auth>`, nsSASL, mechName, payload,
	)))
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

	// Send response
	respPayload := base64.StdEncoding.EncodeToString([]byte(clientFinal))
	c.writeMu.Lock()
	c.conn.Write([]byte(fmt.Sprintf(
		`<response xmlns='%s'>%s</response>`, nsSASL, respPayload,
	)))
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
	for {
		b, readErr := c.reader.ReadByte()
		if readErr != nil {
			return "", "", fmt.Errorf("sasl read: %w", readErr)
		}
		buf.WriteByte(b)
		data := buf.String()

		for _, tag := range []string{"challenge", "success", "failure"} {
			// Self-closing: <tag/>
			if strings.Contains(data, "<"+tag+"/>") {
				return tag, "", nil
			}
			// With content: <tag>...</tag> or <tag ...>...</tag>
			closeTag := "</" + tag + ">"
			if strings.Contains(data, closeTag) {
				// Extract content between > and </tag>
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
	for {
		b, err := c.reader.ReadByte()
		if err != nil {
			return "", fmt.Errorf("read iq: %w", err)
		}
		buf.WriteByte(b)
		data := buf.String()
		if strings.Contains(data, "</iq>") {
			return data, nil
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
			// Connection lost — could reconnect here
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
			var iq xmppIQ
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
			c.notifyUpdate(Update{
				Type:     UpdateTyping,
				ChatID:   chatID,
				UserID:   senderID,
				Platform: "xmpp",
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
		c.notifyUpdate(Update{
			Type:   UpdateReadState,
			ChatID: chatID,
			ReadState: &ReadState{
				PeerLastRead: map[string]string{fromBare: parsed.DisplayedID},
			},
			Platform: "xmpp",
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
			Platform:   "xmpp",
		}
		c.bufferMessage(chatID, m)
		c.notifyUpdate(Update{
			Type:     UpdateNewMessage,
			ChatID:   chatID,
			Message:  m,
			Platform: "xmpp",
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
					c.notifyUpdate(Update{
						Type:     UpdateEditMessage,
						ChatID:   chatID,
						Message:  m,
						Platform: "xmpp",
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
		msgID = fmt.Sprintf("xmpp_%d", atomic.AddInt64(&c.msgCounter, 1))
	}

	m := &Message{
		ID:         msgID,
		ChatID:     chatID,
		SenderID:   senderID,
		SenderName: senderName,
		Text:       parsed.Body,
		Timestamp:  ts,
		Status:     MessageStatusDelivered,
		Platform:   "xmpp",
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

	c.notifyUpdate(Update{
		Type:     UpdateNewMessage,
		ChatID:   chatID,
		Message:  m,
		Platform: "xmpp",
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
		c.notifyUpdate(Update{
			Type:     UpdateNewMessage,
			ChatID:   fromBare,
			Message: &Message{
				ID:        fmt.Sprintf("sub_%d", time.Now().UnixNano()),
				ChatID:    fromBare,
				SenderID:  fromBare,
				Text:      "[Subscription request]",
				Timestamp: time.Now(),
				Status:    MessageStatusDelivered,
				Platform:  "xmpp",
			},
			Platform: "xmpp",
		})

	case "subscribed":
		// Subscription approved

	case "unsubscribe", "unsubscribed":
		// Subscription removed

	case "unavailable":
		// User went offline
		isOnline := false
		c.notifyUpdate(Update{
			Type:     UpdateUserStatus,
			UserID:   fromBare,
			IsOnline: &isOnline,
			Platform: "xmpp",
		})

	case "", "available":
		// User is online
		isOnline := true
		c.notifyUpdate(Update{
			Type:     UpdateUserStatus,
			UserID:   fromBare,
			IsOnline: &isOnline,
			Platform: "xmpp",
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
		c.notifyUpdate(Update{
			Type:   UpdateGroupMembers,
			ChatID: roomJID,
			UserID: nick,
			Platform: "xmpp",
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

	c.notifyUpdate(Update{
		Type:   UpdateGroupMembers,
		ChatID: roomJID,
		UserID: nick,
		Platform: "xmpp",
	})
}

func (c *XMPPCore) handleIQ(iq xmppIQ) {
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

	// Handle incoming IQ requests
	if iq.Type == "get" {
		// Respond to common queries
		if strings.Contains(iq.Inner, nsPing) {
			// Respond to ping
			c.sendRawStanza(fmt.Sprintf(
				`<iq type='result' id='%s' to='%s'/>`, xmlEscape(iq.ID), xmlEscape(iq.From),
			))
			return
		}
		if strings.Contains(iq.Inner, nsVersion) {
			c.sendRawStanza(fmt.Sprintf(
				`<iq type='result' id='%s' to='%s'><query xmlns='%s'><name>Uniclient</name><version>1.0</version><os>Go</os></query></iq>`,
				xmlEscape(iq.ID), xmlEscape(iq.From), nsVersion,
			))
			return
		}
		if strings.Contains(iq.Inner, nsDiscoInfo) {
			c.respondDiscoInfo(iq)
			return
		}
		if strings.Contains(iq.Inner, nsTime) {
			now := time.Now()
			c.sendRawStanza(fmt.Sprintf(
				`<iq type='result' id='%s' to='%s'><time xmlns='%s'><tzo>%s</tzo><utc>%s</utc></time></iq>`,
				xmlEscape(iq.ID), xmlEscape(iq.From), nsTime,
				now.Format("-07:00"), now.UTC().Format("2006-01-02T15:04:05Z"),
			))
			return
		}
		if strings.Contains(iq.Inner, nsLast) {
			c.sendRawStanza(fmt.Sprintf(
				`<iq type='result' id='%s' to='%s'><query xmlns='%s' seconds='0'/></iq>`,
				xmlEscape(iq.ID), xmlEscape(iq.From), nsLast,
			))
			return
		}
		// Unknown — service-unavailable
		c.sendRawStanza(fmt.Sprintf(
			`<iq type='error' id='%s' to='%s'><error type='cancel'><service-unavailable xmlns='urn:ietf:params:xml:ns:xmpp-stanzas'/></error></iq>`,
			xmlEscape(iq.ID), xmlEscape(iq.From),
		))
		return
	}

	if iq.Type == "set" {
		// Roster push
		if strings.Contains(iq.Inner, nsRoster) {
			c.handleRosterPush(iq)
			return
		}
		// Blocklist push (XEP-0191)
		if strings.Contains(iq.Inner, nsBlocking) {
			c.handleBlocklistPush(iq)
			return
		}
		// Jingle
		if strings.Contains(iq.Inner, nsJingle) {
			c.handleJingleAction(iq)
			return
		}
		// Unknown set — feature-not-implemented
		c.sendRawStanza(fmt.Sprintf(
			`<iq type='error' id='%s' to='%s'><error type='cancel'><feature-not-implemented xmlns='urn:ietf:params:xml:ns:xmpp-stanzas'/></error></iq>`,
			xmlEscape(iq.ID), xmlEscape(iq.From),
		))
	}
}

func (c *XMPPCore) handleRosterPush(iq xmppIQ) {
	// Ack the push
	c.sendRawStanza(fmt.Sprintf(`<iq type='result' id='%s'/>`, xmlEscape(iq.ID)))

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

func (c *XMPPCore) handleBlocklistPush(iq xmppIQ) {
	c.sendRawStanza(fmt.Sprintf(`<iq type='result' id='%s'/>`, xmlEscape(iq.ID)))

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

func (c *XMPPCore) handleJingleAction(iq xmppIQ) {
	// Stub — acknowledge and respond with session-terminate for now
	// Full Jingle implementation would handle ICE, DTLS, RTP
	c.sendRawStanza(fmt.Sprintf(`<iq type='result' id='%s' to='%s'/>`,
		xmlEscape(iq.ID), xmlEscape(iq.From)))
}

// ---------------------------------------------------------------------------
// IQ send/receive
// ---------------------------------------------------------------------------

func (c *XMPPCore) nextIQID() string {
	return fmt.Sprintf("iq_%d", c.iqCounter.Add(1))
}

func (c *XMPPCore) sendIQSync(typ, to, inner string) (*xmppIQ, error) {
	id := c.nextIQID()
	ch := make(chan *xmppIQ, 1)
	timer := time.NewTimer(xmppIQTimeout)

	c.pendingIQMu.Lock()
	c.pendingIQ[id] = &xmppPendingIQ{ch: ch, timeout: timer}
	c.pendingIQMu.Unlock()

	var toAttr string
	if to != "" {
		toAttr = fmt.Sprintf(` to='%s'`, xmlEscape(to))
	}

	stanza := fmt.Sprintf(`<iq type='%s' id='%s'%s>%s</iq>`, typ, id, toAttr, inner)
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
	c.writeMu.Lock()
	defer c.writeMu.Unlock()
	if c.conn == nil {
		return errors.New("not connected")
	}

	_, err := c.conn.Write([]byte(stanza))

	// Stream management: track outgoing
	if c.smEnabled {
		c.smOutH.Add(1)
		c.smOutMu.Lock()
		c.smOutQueue = append(c.smOutQueue, bytes.NewBufferString(stanza))
		c.smOutMu.Unlock()
	}

	return err
}

// ---------------------------------------------------------------------------
// Ping loop
// ---------------------------------------------------------------------------

func (c *XMPPCore) pingLoop() {
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

func (c *XMPPCore) GetDialogs(opts PaginationOpts) ([]Dialog, error) {
	c.rosterMu.RLock()
	defer c.rosterMu.RUnlock()

	var dialogs []Dialog

	// DM dialogs from roster
	for _, item := range c.roster {
		if item.Subscription == "remove" {
			continue
		}
		d := Dialog{
			ID:       item.JID,
			Type:     ChatTypeDM,
			Title:    item.Name,
			Platform: "xmpp",
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
			Platform:    "xmpp",
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

	return dialogs, nil
}

func (c *XMPPCore) CreateGroup(name string, members []string) (*Dialog, error) {
	c.mu.RLock()
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
		Platform: "xmpp",
	}
	return d, nil
}

func (c *XMPPCore) CreateChannel(name string, description string) (*Dialog, error) {
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

func (c *XMPPCore) CreateTopic(chatID string, name string) (*Dialog, error) {
	return nil, ErrNotSupported
}

func (c *XMPPCore) GetFolders() ([]Folder, error) {
	// Return bookmarks as folders
	c.bookmarksMu.RLock()
	defer c.bookmarksMu.RUnlock()

	if len(c.bookmarks) == 0 {
		c.loadBookmarks()
	}

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

func (c *XMPPCore) SendMessage(chatID string, msg OutgoingMessage) (*Message, error) {
	msgType := "chat"
	if c.isRoom(chatID) {
		msgType = "groupchat"
	}

	id := c.nextMsgID()

	var inner strings.Builder
	inner.WriteString(fmt.Sprintf(`<body>%s</body>`, xmlEscape(msg.Text)))

	// Request receipt
	inner.WriteString(fmt.Sprintf(`<request xmlns='%s'/>`, nsReceipts))

	// Chat state: active
	inner.WriteString(fmt.Sprintf(`<active xmlns='%s'/>`, nsChatState))

	// Reply
	if msg.ReplyToID != "" {
		inner.WriteString(fmt.Sprintf(`<reply xmlns='%s' id='%s'/>`, nsReply, xmlEscape(msg.ReplyToID)))
	}

	// Store hint
	inner.WriteString(fmt.Sprintf(`<store xmlns='%s'/>`, nsHints))

	stanza := fmt.Sprintf(
		`<message type='%s' to='%s' id='%s'>%s</message>`,
		msgType, xmlEscape(chatID), xmlEscape(id), inner.String(),
	)

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
		Platform:  "xmpp",
	}

	// Don't buffer groupchat messages — we'll get them back from the server
	if msgType != "groupchat" {
		c.bufferMessage(chatID, m)
	}

	return m, nil
}

func (c *XMPPCore) GetMessages(chatID string, opts PaginationOpts) ([]Message, error) {
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
		return nil, nil
	}

	result := make([]Message, len(msgs))
	for i, m := range msgs {
		result[i] = *m
	}
	return result, nil
}

func (c *XMPPCore) EditMessage(chatID string, msgID string, text string) (*Message, error) {
	return c.CorrectMessage(chatID, msgID, text)
}

func (c *XMPPCore) DeleteMessage(chatID string, msgID string) error {
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

func (c *XMPPCore) ReplyToMessage(chatID string, replyToMsgID string, msg OutgoingMessage) (*Message, error) {
	msg.ReplyToID = replyToMsgID
	return c.SendMessage(chatID, msg)
}

func (c *XMPPCore) ForwardMessage(fromChatID string, msgID string, toChatID string) (*Message, error) {
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

func (c *XMPPCore) ReactToMessage(chatID string, msgID string, emoji string) error {
	return c.SendReaction(chatID, msgID, []string{emoji})
}

func (c *XMPPCore) PinMessage(chatID string, msgID string) error {
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

func (c *XMPPCore) MarkAsRead(chatID string, upToMsgID string) error {
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

func (c *XMPPCore) GetReadState(chatID string) (*ReadState, error) {
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

func (c *XMPPCore) UploadFile(chatID string, file FileUpload, progress func(sent, total int64)) (*Message, error) {
	// Use XEP-0363 HTTP File Upload
	c.mu.RLock()
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

func (c *XMPPCore) DownloadFile(fileRef FileRef, dest string, progress func(recv, total int64)) error {
	if fileRef.URL == "" {
		return fmt.Errorf("%w: no URL in file ref", ErrInvalidInput)
	}

	return c.DownloadFileHTTP(fileRef.URL, dest, progress)
}

func (c *XMPPCore) SendImageBase64(chatID string, b64 string, caption string) (*Message, error) {
	// Decode, upload via HTTP, send URL
	data, err := base64.StdEncoding.DecodeString(b64)
	if err != nil {
		return nil, fmt.Errorf("decode base64: %w", err)
	}

	c.mu.RLock()
	uploadSvc := c.uploadService
	c.mu.RUnlock()

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

func (c *XMPPCore) StartCall(chatID string, video bool) (*CallSession, error) {
	return c.InitiateJingle(chatID, video)
}

func (c *XMPPCore) JoinGroupCall(chatID string) (*CallSession, error) {
	return nil, ErrNotSupported // Muji (XEP-0272) not widely supported
}

func (c *XMPPCore) EndCall(callID string) error {
	return c.TerminateJingle(callID, "success")
}

func (c *XMPPCore) SetCallMuted(callID string, muted bool) error {
	// Would need to control local media track
	return ErrNotSupported
}

// ---------------------------------------------------------------------------
// Core interface — Profile
// ---------------------------------------------------------------------------

func (c *XMPPCore) GetProfile(userID string) (*User, error) {
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
				Platform:    "xmpp",
			}, nil
		}
		return &User{
			ID:          userID,
			DisplayName: userID,
			Platform:    "xmpp",
		}, nil
	}

	u := &User{
		ID:          userID,
		DisplayName: vcard["FN"],
		Username:    vcard["NICKNAME"],
		Platform:    "xmpp",
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

func (c *XMPPCore) OnUpdate(handler func(Update)) {
	c.updateMu.Lock()
	c.updateHandlers = append(c.updateHandlers, handler)
	c.updateMu.Unlock()
}

func (c *XMPPCore) Close() error {
	c.saveSession()
	c.cancel()
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.conn != nil {
		// Try graceful close
		c.writeMu.Lock()
		c.conn.Write([]byte("</stream:stream>"))
		c.writeMu.Unlock()
		return c.conn.Close()
	}
	return nil
}

// ---------------------------------------------------------------------------
// Core interface — Chat management
// ---------------------------------------------------------------------------

func (c *XMPPCore) GetChatInfo(chatID string) (*Dialog, error) {
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
					Platform:    "xmpp",
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
		Platform: "xmpp",
	}
	if ok && item.Name != "" {
		d.Title = item.Name
	}
	return d, nil
}

func (c *XMPPCore) EditChatTitle(chatID string, title string) error {
	if c.isRoom(chatID) {
		return c.SetMUCSubject(chatID, title)
	}
	return ErrNotSupported
}

func (c *XMPPCore) EditChatDescription(chatID string, description string) error {
	if c.isRoom(chatID) {
		return c.ConfigureMUC(chatID, map[string]string{
			"muc#roomconfig_roomdesc": description,
		})
	}
	return ErrNotSupported
}

func (c *XMPPCore) LeaveChat(chatID string) error {
	if c.isRoom(chatID) {
		return c.LeaveMUC(chatID)
	}
	// For DM, just remove from roster
	return c.RemoveRosterItem(chatID)
}

func (c *XMPPCore) GetInviteLink(chatID string) (string, error) {
	// XMPP uses xmpp: URI scheme
	return "xmpp:" + chatID + "?join", nil
}

// ---------------------------------------------------------------------------
// Core interface — Members
// ---------------------------------------------------------------------------

func (c *XMPPCore) AddMembers(chatID string, userIDs []string) error {
	if !c.isRoom(chatID) {
		return ErrNotSupported
	}
	for _, uid := range userIDs {
		c.SendMUCInvitation(chatID, uid, "")
	}
	return nil
}

func (c *XMPPCore) RemoveMember(chatID string, userID string) error {
	if !c.isRoom(chatID) {
		return ErrNotSupported
	}
	return c.KickFromMUC(chatID, userID, "")
}

func (c *XMPPCore) BanMember(chatID string, userID string) error {
	if !c.isRoom(chatID) {
		return ErrNotSupported
	}
	return c.BanFromMUC(chatID, userID, "")
}

func (c *XMPPCore) UnbanMember(chatID string, userID string) error {
	if !c.isRoom(chatID) {
		return ErrNotSupported
	}
	return c.UnbanFromMUC(chatID, userID)
}

func (c *XMPPCore) GetMembers(chatID string, opts PaginationOpts) ([]User, error) {
	if c.isRoom(chatID) {
		return c.GetMUCOccupants(chatID)
	}
	// DM — return self and the other party
	return []User{
		{ID: c.bareJID, DisplayName: c.bareJID, Platform: "xmpp"},
		{ID: chatID, DisplayName: chatID, Platform: "xmpp"},
	}, nil
}

func (c *XMPPCore) SetAdmin(chatID string, userID string, admin bool) error {
	if !c.isRoom(chatID) {
		return ErrNotSupported
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

func (c *XMPPCore) GetContacts() ([]User, error) {
	c.rosterMu.RLock()
	defer c.rosterMu.RUnlock()

	var users []User
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
			Platform:    "xmpp",
		})
	}
	return users, nil
}

func (c *XMPPCore) AddContact(phone string, firstName string, lastName string) error {
	// In XMPP, "phone" is the JID
	jid := phone
	name := firstName
	if lastName != "" {
		name += " " + lastName
	}
	return c.AddRosterItem(jid, name, nil)
}

func (c *XMPPCore) DeleteContact(userID string) error {
	return c.RemoveRosterItem(userID)
}

func (c *XMPPCore) BlockUser(userID string) error {
	return c.BlockJID(userID)
}

func (c *XMPPCore) UnblockUser(userID string) error {
	return c.UnblockJID(userID)
}

func (c *XMPPCore) GetBlockedUsers() ([]User, error) {
	jids, err := c.GetBlocklist()
	if err != nil {
		return nil, err
	}
	var users []User
	for _, jid := range jids {
		users = append(users, User{
			ID:          jid,
			DisplayName: jid,
			Platform:    "xmpp",
		})
	}
	return users, nil
}

// ---------------------------------------------------------------------------
// Core interface — Search
// ---------------------------------------------------------------------------

func (c *XMPPCore) SearchMessages(chatID string, query string, opts PaginationOpts) ([]Message, error) {
	// Search local buffer
	c.messagesMu.RLock()
	defer c.messagesMu.RUnlock()

	var results []Message
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
	// Search roster and rooms
	q := strings.ToLower(query)
	var results []Dialog

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
				Platform: "xmpp",
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
				Platform: "xmpp",
			})
		}
	}
	c.roomsMu.RUnlock()

	return results, nil
}

// ---------------------------------------------------------------------------
// Core interface — Typing
// ---------------------------------------------------------------------------

func (c *XMPPCore) SendTyping(chatID string) error {
	return c.SendChatStateComposing(chatID)
}

// ---------------------------------------------------------------------------
// Core interface — Polls & Stickers (not supported)
// ---------------------------------------------------------------------------

func (c *XMPPCore) CreatePoll(chatID string, question string, options []string) (*Message, error) {
	return nil, ErrNotSupported
}

func (c *XMPPCore) VotePoll(chatID string, msgID string, optionIndex int) error {
	return ErrNotSupported
}

func (c *XMPPCore) SendSticker(chatID string, stickerID string) (*Message, error) {
	return nil, ErrNotSupported
}

// ---------------------------------------------------------------------------
// Core interface — Sessions
// ---------------------------------------------------------------------------

func (c *XMPPCore) GetSessions() ([]Session, error) {
	// XMPP doesn't have a standard session list — return current
	return []Session{{
		ID:         c.jid,
		Device:     "uniclient",
		Platform:   "xmpp",
		LastActive: time.Now(),
		IsCurrent:  true,
	}}, nil
}

func (c *XMPPCore) TerminateSession(sessionID string) error {
	return ErrNotSupported
}

// ---------------------------------------------------------------------------
// XMPP-specific: Presence methods
// ---------------------------------------------------------------------------

func (c *XMPPCore) SendPresenceAvailable(show, status string) error {
	var inner string
	if show != "" {
		inner += fmt.Sprintf(`<show>%s</show>`, xmlEscape(show))
	}
	if status != "" {
		inner += fmt.Sprintf(`<status>%s</status>`, xmlEscape(status))
	}
	// Entity capabilities (XEP-0115)
	inner += c.buildCapsElement()

	return c.sendRawStanza(fmt.Sprintf(`<presence>%s</presence>`, inner))
}

func (c *XMPPCore) SendPresenceUnavailable(status string) error {
	var inner string
	if status != "" {
		inner = fmt.Sprintf(`<status>%s</status>`, xmlEscape(status))
	}
	return c.sendRawStanza(fmt.Sprintf(`<presence type='unavailable'>%s</presence>`, inner))
}

func (c *XMPPCore) SendPresenceAway(status string) error {
	return c.SendPresenceAvailable("away", status)
}

func (c *XMPPCore) SendPresenceDND(status string) error {
	return c.SendPresenceAvailable("dnd", status)
}

func (c *XMPPCore) SendPresenceXA(status string) error {
	return c.SendPresenceAvailable("xa", status)
}

func (c *XMPPCore) SendPresenceChat(status string) error {
	return c.SendPresenceAvailable("chat", status)
}

func (c *XMPPCore) SetPresenceStatus(status string) error {
	return c.SendPresenceAvailable("", status)
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

func (c *XMPPCore) GetRoster() ([]xmppRosterItem, error) {
	c.rosterMu.RLock()
	defer c.rosterMu.RUnlock()

	var items []xmppRosterItem
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

	// Also subscribe to presence
	c.SendPresenceSubscribe(jid)
	return nil
}

func (c *XMPPCore) RemoveRosterItem(jid string) error {
	inner := fmt.Sprintf(`<query xmlns='%s'><item jid='%s' subscription='remove'/></query>`, nsRoster, xmlEscape(jid))
	_, err := c.sendIQSync("set", "", inner)
	return err
}

func (c *XMPPCore) SetRosterItemName(jid, name string) error {
	return c.AddRosterItem(jid, name, nil) // Add/update is the same operation
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

// ---------------------------------------------------------------------------
// XMPP-specific: Chat state methods (XEP-0085)
// ---------------------------------------------------------------------------

func (c *XMPPCore) sendChatState(chatID, state string) error {
	msgType := "chat"
	if c.isRoom(chatID) {
		msgType = "groupchat"
	}
	return c.sendRawStanza(fmt.Sprintf(
		`<message type='%s' to='%s'><%s xmlns='%s'/></message>`,
		msgType, xmlEscape(chatID), state, nsChatState,
	))
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

// ---------------------------------------------------------------------------
// XMPP-specific: Message extensions
// ---------------------------------------------------------------------------

func (c *XMPPCore) SendChatMessage(to, body string) error {
	id := c.nextMsgID()
	return c.sendRawStanza(fmt.Sprintf(
		`<message type='chat' to='%s' id='%s'><body>%s</body></message>`,
		xmlEscape(to), id, xmlEscape(body),
	))
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
	return c.sendRawStanza(fmt.Sprintf(
		`<message to='%s' id='%s'><received xmlns='%s' id='%s'/></message>`,
		xmlEscape(to), id, nsReceipts, xmlEscape(msgID),
	))
}

func (c *XMPPCore) CorrectMessage(chatID, originalID, newText string) (*Message, error) {
	msgType := "chat"
	if c.isRoom(chatID) {
		msgType = "groupchat"
	}
	id := c.nextMsgID()
	err := c.sendRawStanza(fmt.Sprintf(
		`<message type='%s' to='%s' id='%s'><body>%s</body><replace xmlns='%s' id='%s'/></message>`,
		msgType, xmlEscape(chatID), id, xmlEscape(newText), nsCorrect, xmlEscape(originalID),
	))
	if err != nil {
		return nil, err
	}

	// Update local buffer
	c.messagesMu.Lock()
	if msgs, ok := c.messages[chatID]; ok {
		for _, m := range msgs {
			if m.ID == originalID {
				m.Text = newText
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
		Text:      newText,
		Timestamp: time.Now(),
		Status:    MessageStatusSent,
		Platform:  "xmpp",
	}, nil
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
	return c.sendRawStanza(fmt.Sprintf(
		`<message to='%s' id='%s'><displayed xmlns='%s' id='%s'/></message>`,
		xmlEscape(to), id, nsMarkers, xmlEscape(msgID),
	))
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
	// Hints are typically set per-message at send time, not retroactively
	return ErrNotSupported
}

func (c *XMPPCore) SendReply(chatID, replyToJID, replyToID, body string) (*Message, error) {
	return c.SendMessage(chatID, OutgoingMessage{
		Text:      body,
		ReplyToID: replyToID,
	})
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

// ---------------------------------------------------------------------------
// XMPP-specific: MUC methods (XEP-0045)
// ---------------------------------------------------------------------------

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
			Platform:    "xmpp",
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
		Platform: "xmpp",
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

func (c *XMPPCore) SetMUCSubject(roomJID, subject string) error {
	return c.sendRawStanza(fmt.Sprintf(
		`<message type='groupchat' to='%s'><subject>%s</subject></message>`,
		xmlEscape(roomJID), xmlEscape(subject),
	))
}

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

	// Parse x:data form
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
	// Accept default config
	inner := fmt.Sprintf(`<query xmlns='%s'><x xmlns='%s' type='submit'/></query>`, nsMUCOwner, nsXData)
	_, err := c.sendIQSync("set", roomJID, inner)
	return err
}

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

func (c *XMPPCore) DiscoInfo(target string) (*xmppIQ, error) {
	if target == "" {
		target = c.domain
	}
	inner := fmt.Sprintf(`<query xmlns='%s'/>`, nsDiscoInfo)
	return c.sendIQSync("get", target, inner)
}

func (c *XMPPCore) DiscoItems(target string) (*xmppIQ, error) {
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
	category = extractXMLAttr(resp.Inner, "identity", "category")
	typ = extractXMLAttr(resp.Inner, "identity", "type")
	name = extractXMLAttr(resp.Inner, "identity", "name")
	return
}

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

func (c *XMPPCore) DiscoverExternalServices() ([]map[string]string, error) {
	inner := fmt.Sprintf(`<services xmlns='%s'/>`, nsExtSvc)
	resp, err := c.sendIQSync("get", c.domain, inner)
	if err != nil {
		return nil, err
	}

	return parseExternalServices(resp.Inner), nil
}

func (c *XMPPCore) respondDiscoInfo(iq xmppIQ) {
	features := []string{
		nsDiscoInfo, nsDiscoItem, nsCaps, nsChatState,
		nsReceipts, nsCorrect, nsReactions, nsReply,
		nsMarkers, nsPing, nsVersion, nsTime, nsLast,
		nsCarbons, nsBlocking,
	}

	var featsXML strings.Builder
	featsXML.WriteString(fmt.Sprintf(`<query xmlns='%s'>`, nsDiscoInfo))
	featsXML.WriteString(`<identity category='client' type='pc' name='Uniclient'/>`)
	for _, f := range features {
		featsXML.WriteString(fmt.Sprintf(`<feature var='%s'/>`, f))
	}
	featsXML.WriteString(`</query>`)

	c.sendRawStanza(fmt.Sprintf(
		`<iq type='result' id='%s' to='%s'>%s</iq>`,
		xmlEscape(iq.ID), xmlEscape(iq.From), featsXML.String(),
	))
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
		Platform:  "xmpp",
	}
	c.bufferMessage(chatID, m)
	return m, nil
}

// ---------------------------------------------------------------------------
// XMPP-specific: PubSub (XEP-0060)
// ---------------------------------------------------------------------------

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
		service = c.bareJID // PEP
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

func (c *XMPPCore) GetPubSubItems(service, node string) (*xmppIQ, error) {
	if service == "" {
		service = c.domain
	}
	inner := fmt.Sprintf(`<pubsub xmlns='%s'><items node='%s'/></pubsub>`, nsPubSub, xmlEscape(node))
	return c.sendIQSync("get", service, inner)
}

func (c *XMPPCore) GetPubSubSubscriptions(service string) (*xmppIQ, error) {
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

// ---------------------------------------------------------------------------
// XMPP-specific: PEP (XEP-0163) — User Mood, Activity, Tune, Location
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// XMPP-specific: Registration (XEP-0077)
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// XMPP-specific: Stream Management (XEP-0198)
// ---------------------------------------------------------------------------

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

func (c *XMPPCore) RequestAck() error {
	return c.sendRawStanza(fmt.Sprintf(`<r xmlns='%s'/>`, nsSM))
}

func (c *XMPPCore) SendAck() error {
	h := c.smInH.Load()
	c.writeMu.Lock()
	defer c.writeMu.Unlock()
	_, err := c.conn.Write([]byte(fmt.Sprintf(`<a xmlns='%s' h='%d'/>`, nsSM, h)))
	return err
}

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

	name = extractXMLContent(resp.Inner, "name")
	version = extractXMLContent(resp.Inner, "version")
	os = extractXMLContent(resp.Inner, "os")
	return
}

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

// ---------------------------------------------------------------------------
// XMPP-specific: Jingle / Calls (XEP-0166)
// ---------------------------------------------------------------------------

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
	// We need to send to the peer — look up from call state
	// For now, send to domain and rely on server routing
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
	return fmt.Sprintf("msg_%d", atomic.AddInt64(&c.msgCounter, 1))
}

// ---------------------------------------------------------------------------
// Helper: update notification
// ---------------------------------------------------------------------------

func (c *XMPPCore) notifyUpdate(u Update) {
	c.updateMu.RLock()
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

	// Check if JID domain matches MUC service
	c.mu.RLock()
	mucSvc := c.mucService
	c.mu.RUnlock()

	if mucSvc != "" {
		parts := strings.SplitN(jid, "@", 2)
		if len(parts) == 2 && parts[1] == mucSvc {
			return true
		}
	}

	return false
}

// ---------------------------------------------------------------------------
// Helper: XML utilities
// ---------------------------------------------------------------------------

func xmlEscape(s string) string {
	var b strings.Builder
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
	numBlocks := (keyLen + h().Size() - 1) / h().Size()
	dk := make([]byte, 0, numBlocks*h().Size())
	for block := 1; block <= numBlocks; block++ {
		// U1 = PRF(password, salt || INT(block))
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
	// Simplified caps hash — in production you'd compute from actual disco#info
	features := []string{
		nsDiscoInfo, nsChatState, nsReceipts, nsCorrect,
		nsReactions, nsReply, nsMarkers, nsPing, nsVersion,
	}
	sort.Strings(features)

	h := sha1.New()
	h.Write([]byte("client/pc//Uniclient<"))
	for _, f := range features {
		h.Write([]byte(f + "<"))
	}
	ver := base64.StdEncoding.EncodeToString(h.Sum(nil))

	return fmt.Sprintf(`<c xmlns='%s' hash='sha-1' node='https://github.com/DarkReaperBoy/uniclient' ver='%s'/>`,
		nsCaps, ver)
}
