// IRC core — pure Go IRC client implementing the Core interface.
// Protocol: RFC 1459/2812 + IRCv3 + CTCP + DCC + IRC services.
// 302 methods (55 Core + 247 IRC-specific).
// No external dependencies — stdlib only (net, crypto/tls, bufio).
//
// Chat IDs:
//   "#channel"  → channel
//   "nick"      → DM (private message)
//
// AuthConfig.Extra keys:
//   "server"          — host:port (e.g. "irc.libera.chat:6697")
//   "nick"            — desired nickname
//   "username"        — IRC username (defaults to nick)
//   "realname"        — real name field (defaults to nick)
//   "password"        — NickServ/SASL password (optional)
//   "server_password" — connection password (PASS command, optional)
//   "tls"             — "true"/"false" (default: auto-detect from port)
//   "sasl"            — "true" to force SASL PLAIN auth
//   "channels"        — comma-separated auto-join list
//
// Coverage: RFC 2812 commands, IRCv3 ratified + drafts (CAP, SASL, TAGMSG,
// CHATHISTORY, MARKREAD, REDACT, REGISTER, RENAME, MONITOR, WATCH),
// CTCP (VERSION/PING/TIME/ACTION/CLIENTINFO/FINGER/USERINFO/SOURCE/DCC),
// DCC (SEND/CHAT/RESUME/ACCEPT), NickServ (20), ChanServ (39),
// MemoServ (10), HostServ (4), BotServ (6), SILENCE, WHOX, STATUSMSG,
// CPRIVMSG/CNOTICE, LINKS/TRACE/MAP/RULES/HELP, SERVLIST/SQUERY, WEBIRC.
package cores

import (
	"bufio"
	"context"
	"crypto/tls"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net"
	"os"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const (
	ircMaxMsgLen    = 512 // RFC 2812 max line length (including CRLF)
	ircMsgBufSize   = 500 // max per-chat message buffer
	ircPingInterval = 90 * time.Second
	ircPongTimeout  = 30 * time.Second
	ircReconnDelay  = 5 * time.Second
	ircSendDelay    = 500 * time.Millisecond // flood protection
)

// ---------------------------------------------------------------------------
// IRC message parsing
// ---------------------------------------------------------------------------

type ircMsg struct {
	Tags    map[string]string // IRCv3 message tags
	Prefix  string            // nick!user@host or server name
	Command string            // PRIVMSG, JOIN, 001, etc.
	Params  []string          // parameters (last may include trailing)
}

func (m *ircMsg) Nick() string {
	if idx := strings.Index(m.Prefix, "!"); idx > 0 {
		return m.Prefix[:idx]
	}
	return m.Prefix
}

func (m *ircMsg) Trailing() string {
	if len(m.Params) > 0 {
		return m.Params[len(m.Params)-1]
	}
	return ""
}

func parseIRCMsg(line string) *ircMsg {
	m := &ircMsg{Tags: make(map[string]string)}

	// IRCv3 tags: @key=value;key2=value2
	if strings.HasPrefix(line, "@") {
		sp := strings.IndexByte(line, ' ')
		if sp < 0 {
			return nil
		}
		tagStr := line[1:sp]
		line = strings.TrimLeft(line[sp+1:], " ")
		for _, tag := range strings.Split(tagStr, ";") {
			if eq := strings.IndexByte(tag, '='); eq >= 0 {
				m.Tags[tag[:eq]] = tag[eq+1:]
			} else {
				m.Tags[tag] = ""
			}
		}
	}

	// Prefix: :nick!user@host
	if strings.HasPrefix(line, ":") {
		sp := strings.IndexByte(line, ' ')
		if sp < 0 {
			return nil
		}
		m.Prefix = line[1:sp]
		line = strings.TrimLeft(line[sp+1:], " ")
	}

	// Command + params
	if trailing := strings.Index(line, " :"); trailing >= 0 {
		front := line[:trailing]
		m.Params = strings.Fields(front)
		if len(m.Params) > 0 {
			m.Command = m.Params[0]
			m.Params = m.Params[1:]
		}
		m.Params = append(m.Params, line[trailing+2:])
	} else {
		m.Params = strings.Fields(line)
		if len(m.Params) > 0 {
			m.Command = m.Params[0]
			m.Params = m.Params[1:]
		}
	}

	return m
}

// ---------------------------------------------------------------------------
// Channel state
// ---------------------------------------------------------------------------

type ircChannel struct {
	Name    string
	Topic   string
	TopicBy string
	TopicAt time.Time
	Members map[string]string // nick → mode prefix ("@", "+", "")
	Modes   string
	Created time.Time
	URL     string // RPL_CHANNEL_URL (328)
	Key     string // channel key if set
}

// IRCServerInfo holds ISUPPORT (005) parameters and server metadata.
type IRCServerInfo struct {
	Network     string            // NETWORK=
	ServerName  string            // from 004
	ServerVer   string            // from 004
	UserModes   string            // from 004
	ChanModes   string            // from 004
	CaseMapping string            // CASEMAPPING=
	ChanTypes   string            // CHANTYPES=
	Prefix      string            // PREFIX=
	MaxNickLen  int               // NICKLEN=
	MaxChanLen  int               // CHANNELLEN=
	MaxTopicLen int               // TOPICLEN=
	MaxTargets  int               // TARGMAX=
	MaxModes    int               // MODES=
	MaxChannels int               // CHANLIMIT=
	Raw         map[string]string // all raw ISUPPORT key=value pairs
}

// IRCListEntry represents one entry from LIST response.
type IRCListEntry struct {
	Channel string
	Users   int
	Topic   string
}

// IRCWhoEntry represents one entry from WHO response.
type IRCWhoEntry struct {
	Channel  string
	User     string
	Host     string
	Server   string
	Nick     string
	Flags    string // H/G (here/gone), *, @, +
	Hopcount int
	Realname string
}

// IRCWhowasEntry represents one entry from WHOWAS response.
type IRCWhowasEntry struct {
	Nick     string
	User     string
	Host     string
	Realname string
}

// IRCBanEntry represents one entry from the ban list.
type IRCBanEntry struct {
	Mask   string
	SetBy  string
	SetAt  time.Time
}

// IRCUserhostEntry represents one USERHOST reply.
type IRCUserhostEntry struct {
	Nick     string
	IsOper   bool
	IsAway   bool
	Hostname string
}

// ---------------------------------------------------------------------------
// Session persistence
// ---------------------------------------------------------------------------

type ircSession struct {
	Server   string   `json:"server"`
	Nick     string   `json:"nick"`
	Username string   `json:"username"`
	Realname string   `json:"realname"`
	Password string   `json:"password"`
	UseTLS   bool     `json:"use_tls"`
	UseSASL  bool     `json:"use_sasl"`
	Channels []string `json:"channels"`
	Blocked  []string `json:"blocked"`
}

// ---------------------------------------------------------------------------
// IRCCore
// ---------------------------------------------------------------------------

type IRCCore struct {
	mu     sync.RWMutex
	authed bool

	// Connection
	conn    net.Conn
	writer  *bufio.Writer
	writeMu sync.Mutex

	// Identity
	nick           string
	username       string
	realname       string
	server         string
	password       string // NickServ/SASL password
	serverPassword string // PASS command (connection password)
	useTLS         bool
	useSASL        bool

	// State
	channels   map[string]*ircChannel // lowercase name → channel
	channelsMu sync.RWMutex

	dmPartners   map[string]bool // lowercase nicks we've DMed
	dmPartnersMu sync.RWMutex

	// Message buffer (per chat)
	messages   map[string][]*Message // chatID → ordered messages
	messagesMu sync.RWMutex
	msgCounter int64 // monotonic ID generator

	// Pinned messages (local only)
	pinned   map[string]map[string]bool
	pinnedMu sync.RWMutex

	// Read state (local only)
	readState   map[string]*ReadState
	readStateMu sync.RWMutex

	// Blocked users (local)
	blocked   map[string]bool
	blockedMu sync.RWMutex

	// WHOIS cache
	whoisCache   map[string]*User
	whoisCacheMu sync.RWMutex
	whoisWait    map[string]chan struct{} // pending WHOIS lookups
	whoisWaitMu  sync.Mutex

	// Real-time
	updateHandlers []func(Update)
	updateMu       sync.RWMutex

	// Lifecycle
	sessionPath string
	ctx         context.Context
	cancel      context.CancelFunc

	// Registration state (used during connect)
	registered chan struct{}
	saslDone   chan struct{}
	capDone    chan struct{}

	// Last send time (flood protection)
	lastSend   time.Time
	lastSendMu sync.Mutex

	// Auto-join channels from config
	autoJoin []string

	// Server info (ISUPPORT/005)
	serverInfo   IRCServerInfo
	serverInfoMu sync.RWMutex

	// MOTD
	motd   []string
	motdMu sync.RWMutex

	// Away state
	awayMsg   string
	awayMu    sync.RWMutex

	// IRCv3 enabled capabilities
	enabledCaps   map[string]bool
	enabledCapsMu sync.RWMutex

	// LIST accumulator (server-side channel listing)
	listResult   []IRCListEntry
	listDone     chan struct{}
	listMu       sync.Mutex

	// WHO accumulator
	whoResult   []IRCWhoEntry
	whoDone     chan struct{}
	whoMu       sync.Mutex

	// WHOWAS accumulator
	whowasResult []IRCWhowasEntry
	whowasDone   chan struct{}
	whowasMu     sync.Mutex

	// Ban list accumulator
	banResult   []IRCBanEntry
	banDone     chan struct{}
	banMu       sync.Mutex

	// USERHOST accumulator
	userhostResult []IRCUserhostEntry
	userhostDone   chan struct{}
	userhostMu     sync.Mutex

	// ISON accumulator
	isonResult []string
	isonDone   chan struct{}
	isonMu     sync.Mutex

	// MONITOR state
	monitored   map[string]bool // lowercase nicks being monitored
	monitoredMu sync.RWMutex

	// DCC offers
	dccOffers   []IRCDCCOffer
	dccOffersMu sync.RWMutex

	// Reconnection
	reconnectEnabled bool
	reconnectCount   int

	// Step 4 fields
	stsPolicies        map[string]int       // domain → TLS port
	wsURL              string               // WebSocket URL
	extbanPrefix       string               // EXTBAN prefix from ISUPPORT
	inviteNotifyHandler func(inviter, channel, target string)
	networkIcon        string               // ISUPPORT NETWORK_ICON
	saslUser           string               // SASL username for multi-step auth
	saslPass           string               // SASL password for multi-step auth
	saslMech           string               // SASL mechanism name
}

// NewIRCCore creates a new IRC core instance.
func NewIRCCore(sessionPath string) *IRCCore {
	ctx, cancel := context.WithCancel(context.Background())
	return &IRCCore{
		channels:    make(map[string]*ircChannel),
		dmPartners:  make(map[string]bool),
		messages:    make(map[string][]*Message),
		pinned:      make(map[string]map[string]bool),
		readState:   make(map[string]*ReadState),
		blocked:     make(map[string]bool),
		whoisCache:  make(map[string]*User),
		whoisWait:   make(map[string]chan struct{}),
		enabledCaps: make(map[string]bool),
		monitored:   make(map[string]bool),
		stsPolicies: make(map[string]int),
		serverInfo:  IRCServerInfo{Raw: make(map[string]string)},
		sessionPath: sessionPath,
		ctx:         ctx,
		cancel:      cancel,
	}
}

// ---------------------------------------------------------------------------
// Core interface — Identity
// ---------------------------------------------------------------------------

func (c *IRCCore) Name() string { return "irc" }

func (c *IRCCore) Capabilities() []string {
	return []string{
		"CHANNELS",
		"ADMIN",
		"SEARCH",
	}
}

// ---------------------------------------------------------------------------
// Core interface — Auth
// ---------------------------------------------------------------------------

func (c *IRCCore) Authenticate(cfg AuthConfig) error {
	c.mu.Lock()
	if c.authed {
		c.mu.Unlock()
		return nil
	}

	// Try loading existing session
	if err := c.loadSession(); err == nil && c.server != "" {
		c.applyConfig(cfg)
	} else {
		c.applyConfig(cfg)
	}

	if c.server == "" {
		c.mu.Unlock()
		return fmt.Errorf("%w: irc requires server address in Extra[\"server\"]", ErrAuth)
	}
	if c.nick == "" {
		c.mu.Unlock()
		return fmt.Errorf("%w: irc requires nickname in Extra[\"nick\"]", ErrAuth)
	}
	c.mu.Unlock()

	// Connect (must not hold c.mu — readLoop needs it for 001 handler)
	if err := c.connect(); err != nil {
		return fmt.Errorf("%w: %v", ErrAuth, err)
	}

	c.mu.Lock()
	c.authed = true
	c.mu.Unlock()
	c.saveSession()
	return nil
}

func (c *IRCCore) applyConfig(cfg AuthConfig) {
	if v := cfg.Extra["server"]; v != "" {
		c.server = v
	}
	if v := cfg.Extra["nick"]; v != "" {
		c.nick = v
	}
	if v := cfg.Extra["username"]; v != "" {
		c.username = v
	} else if c.username == "" {
		c.username = c.nick
	}
	if v := cfg.Extra["realname"]; v != "" {
		c.realname = v
	} else if c.realname == "" {
		c.realname = c.nick
	}
	if v := cfg.Extra["password"]; v != "" {
		c.password = v
	}
	if v := cfg.Extra["tls"]; v != "" {
		c.useTLS = v == "true"
	} else if c.server != "" && !c.useTLS {
		// Auto-detect TLS from port
		_, port, _ := net.SplitHostPort(c.server)
		c.useTLS = port == "6697" || port == "7000" || port == "7070"
	}
	if v := cfg.Extra["server_password"]; v != "" {
		c.serverPassword = v
	}
	if v := cfg.Extra["sasl"]; v == "true" {
		c.useSASL = true
	}
	if v := cfg.Extra["channels"]; v != "" {
		c.autoJoin = strings.Split(v, ",")
		for i := range c.autoJoin {
			c.autoJoin[i] = strings.TrimSpace(c.autoJoin[i])
		}
	}
}

func (c *IRCCore) connect() error {
	var conn net.Conn
	var err error

	dialer := &net.Dialer{Timeout: 15 * time.Second}

	if c.useTLS {
		host, _, _ := net.SplitHostPort(c.server)
		conn, err = tls.DialWithDialer(dialer, "tcp", c.server, &tls.Config{
			ServerName: host,
		})
	} else {
		conn, err = dialer.DialContext(c.ctx, "tcp", c.server)
	}
	if err != nil {
		return fmt.Errorf("connect to %s: %w", c.server, err)
	}

	c.conn = conn
	c.writer = bufio.NewWriter(conn)
	c.registered = make(chan struct{})
	c.saslDone = make(chan struct{})
	c.capDone = make(chan struct{})

	// Start read loop
	go c.readLoop()

	// IRC registration sequence
	if c.useSASL {
		c.sendRaw("CAP LS 302")
	}
	// Connection password (PASS command — distinct from NickServ password)
	if c.serverPassword != "" {
		c.sendRaw("PASS " + c.serverPassword)
	}
	c.sendRaw("NICK " + c.nick)
	c.sendRaw("USER " + c.username + " 0 * :" + c.realname)

	// Wait for registration (001 numeric) or timeout
	select {
	case <-c.registered:
	case <-time.After(30 * time.Second):
		conn.Close()
		return fmt.Errorf("registration timeout")
	case <-c.ctx.Done():
		conn.Close()
		return c.ctx.Err()
	}

	// NickServ auth (if password set and not using SASL)
	if c.password != "" && !c.useSASL {
		c.sendRaw("PRIVMSG NickServ :IDENTIFY " + c.password)
		time.Sleep(2 * time.Second) // wait for NickServ response
	}

	// Auto-join channels
	for _, ch := range c.autoJoin {
		if ch != "" {
			c.sendRaw("JOIN " + ch)
		}
	}

	// Start ping loop
	go c.pingLoop()

	return nil
}

func (c *IRCCore) Logout() error {
	c.mu.Lock()
	defer c.mu.Unlock()
	if !c.authed {
		return nil
	}
	c.sendRaw("QUIT :Goodbye")
	c.authed = false
	c.cancel()
	if c.conn != nil {
		c.conn.Close()
	}
	return nil
}

// ---------------------------------------------------------------------------
// Raw send with flood protection
// ---------------------------------------------------------------------------

func (c *IRCCore) sendRaw(line string) {
	c.writeMu.Lock()
	defer c.writeMu.Unlock()

	if c.writer == nil {
		return
	}

	// Flood protection
	c.lastSendMu.Lock()
	since := time.Since(c.lastSend)
	if since < ircSendDelay {
		time.Sleep(ircSendDelay - since)
	}
	c.lastSend = time.Now()
	c.lastSendMu.Unlock()

	// Truncate to IRC max (minus CRLF)
	if len(line) > ircMaxMsgLen-2 {
		line = line[:ircMaxMsgLen-2]
	}

	c.writer.WriteString(line + "\r\n")
	c.writer.Flush()
}

// ---------------------------------------------------------------------------
// Read loop — parses incoming IRC messages and dispatches
// ---------------------------------------------------------------------------

func (c *IRCCore) readLoop() {
	scanner := bufio.NewScanner(c.conn)
	scanner.Buffer(make([]byte, 0, 4096), 4096)

	for scanner.Scan() {
		select {
		case <-c.ctx.Done():
			return
		default:
		}

		line := scanner.Text()
		if line == "" {
			continue
		}

		msg := parseIRCMsg(line)
		if msg == nil {
			continue
		}

		c.handleMessage(msg)
	}
}

func (c *IRCCore) handleMessage(msg *ircMsg) {
	switch msg.Command {
	// --- Connection registration ---
	case "001": // RPL_WELCOME — registered
		if len(msg.Params) > 0 {
			c.mu.Lock()
			c.nick = msg.Params[0] // server may change our nick
			c.mu.Unlock()
		}
		select {
		case <-c.registered:
		default:
			close(c.registered)
		}

	case "433": // ERR_NICKNAMEINUSE
		c.mu.Lock()
		c.nick = c.nick + "_"
		c.mu.Unlock()
		c.sendRaw("NICK " + c.nick)

	// --- CAP / SASL ---
	case "CAP":
		c.handleCAP(msg)
	case "AUTHENTICATE":
		c.handleAuthenticate(msg)
	case "903": // RPL_SASLSUCCESS
		c.sendRaw("CAP END")
	case "904", "905": // ERR_SASLFAIL, ERR_SASLTOOLONG
		c.sendRaw("CAP END")

	// --- PING/PONG ---
	case "PING":
		c.sendRaw("PONG :" + msg.Trailing())

	// --- Channel tracking ---
	case "JOIN":
		c.handleJoin(msg)
	case "PART":
		c.handlePart(msg)
	case "KICK":
		c.handleKick(msg)
	case "QUIT":
		c.handleQuit(msg)
	case "NICK":
		c.handleNickChange(msg)

	// --- NAMES reply (353, 366) ---
	case "353": // RPL_NAMREPLY
		c.handleNamesReply(msg)
	case "366": // RPL_ENDOFNAMES
		// no-op, names already accumulated

	// --- TOPIC ---
	case "TOPIC":
		c.handleTopicChange(msg)
	case "332": // RPL_TOPIC
		c.handleTopicReply(msg)
	case "333": // RPL_TOPICWHOTIME
		c.handleTopicWhoTime(msg)

	// --- Channel info ---
	case "324": // RPL_CHANNELMODEIS
		c.handleChannelMode(msg)
	case "329": // RPL_CREATIONTIME
		c.handleCreationTime(msg)

	// --- WHOIS ---
	case "311": // RPL_WHOISUSER
		c.handleWhoisUser(msg)
	case "312": // RPL_WHOISSERVER
		c.handleWhoisServer(msg)
	case "313": // RPL_WHOISOPERATOR
		c.handleWhoisOper(msg)
	case "317": // RPL_WHOISIDLE
		c.handleWhoisIdle(msg)
	case "318": // RPL_ENDOFWHOIS
		c.handleWhoisEnd(msg)
	case "319": // RPL_WHOISCHANNELS
		c.handleWhoisChannels(msg)
	case "330": // RPL_WHOISACCOUNT (non-standard but widely used)
		c.handleWhoisAccount(msg)

	// --- WHOWAS ---
	case "314": // RPL_WHOWASUSER
		c.handleWhowasUser(msg)
	case "369": // RPL_ENDOFWHOWAS
		c.handleWhowasEnd(msg)

	// --- WHO ---
	case "352": // RPL_WHOREPLY
		c.handleWhoReply(msg)
	case "315": // RPL_ENDOFWHO
		c.handleWhoEnd(msg)

	// --- LIST ---
	case "322": // RPL_LIST
		c.handleListEntry(msg)
	case "323": // RPL_LISTEND
		c.handleListEnd(msg)

	// --- Ban list ---
	case "367": // RPL_BANLIST
		c.handleBanListEntry(msg)
	case "368": // RPL_ENDOFBANLIST
		c.handleBanListEnd(msg)

	// --- Ban exception list ---
	case "348": // RPL_EXCEPTLIST
		c.handleBanListEntry(msg) // same format as ban list
	case "349": // RPL_ENDOFEXCEPTLIST
		c.handleBanListEnd(msg)

	// --- Invite exception list ---
	case "346": // RPL_INVITELIST
		c.handleBanListEntry(msg) // same format
	case "347": // RPL_ENDOFINVITELIST
		c.handleBanListEnd(msg)

	// --- LINKS ---
	case "364": // RPL_LINKS
		// links response — informational
	case "365": // RPL_ENDOFLINKS
		// end of links

	// --- SILENCE ---
	case "271": // RPL_SILELIST
		// silence list entry
	case "272": // RPL_ENDOFSILELIST
		// end of silence list

	// --- WATCH ---
	case "600": // RPL_LOGON (watch)
		c.handleWatchEvent(msg, true)
	case "601": // RPL_LOGOFF (watch)
		c.handleWatchEvent(msg, false)
	case "602": // RPL_WATCHOFF
		// removed from watch list
	case "604": // RPL_NOWON (watch)
		c.handleWatchEvent(msg, true)
	case "605": // RPL_NOWOFF (watch)
		c.handleWatchEvent(msg, false)

	// --- MOTD ---
	case "375": // RPL_MOTDSTART
		c.motdMu.Lock()
		c.motd = nil
		c.motdMu.Unlock()
	case "372": // RPL_MOTD
		c.motdMu.Lock()
		c.motd = append(c.motd, msg.Trailing())
		c.motdMu.Unlock()
	case "376": // RPL_ENDOFMOTD
		// motd complete

	// --- ISUPPORT / server info ---
	case "004": // RPL_MYINFO
		c.handleMyInfo(msg)
	case "005": // RPL_ISUPPORT
		c.handleISupport(msg)

	// --- USERHOST ---
	case "302": // RPL_USERHOST
		c.handleUserhostReply(msg)

	// --- ISON ---
	case "303": // RPL_ISON
		c.handleIsonReply(msg)

	// --- AWAY ---
	case "301": // RPL_AWAY (someone we messaged/whois is away)
		c.handleAwayReply(msg)
	case "305": // RPL_UNAWAY
		c.awayMu.Lock()
		c.awayMsg = ""
		c.awayMu.Unlock()
	case "306": // RPL_NOWAWAY
		// we are now marked away
	case "AWAY": // IRCv3 away-notify
		c.handleAwayNotify(msg)

	// --- User mode ---
	case "221": // RPL_UMODEIS
		// user mode response, informational

	// --- OPER ---
	case "381": // RPL_YOUREOPER
		// successfully opered up

	// --- Errors ---
	case "401": // ERR_NOSUCHNICK
		c.handleErrorNumeric(msg)
	case "402": // ERR_NOSUCHSERVER
		c.handleErrorNumeric(msg)
	case "403": // ERR_NOSUCHCHANNEL
		c.handleErrorNumeric(msg)
	case "404": // ERR_CANNOTSENDTOCHAN
		c.handleErrorNumeric(msg)
	case "405": // ERR_TOOMANYCHANNELS
		c.handleErrorNumeric(msg)
	case "432": // ERR_ERRONEUSNICKNAME
		c.handleErrorNumeric(msg)
	case "442": // ERR_NOTONCHANNEL
		c.handleErrorNumeric(msg)
	case "443": // ERR_USERONCHANNEL
		c.handleErrorNumeric(msg)
	case "461": // ERR_NEEDMOREPARAMS
		c.handleErrorNumeric(msg)
	case "462": // ERR_ALREADYREGISTERED
		c.handleErrorNumeric(msg)
	case "471": // ERR_CHANNELISFULL
		c.handleErrorNumeric(msg)
	case "473": // ERR_INVITEONLYCHAN
		c.handleErrorNumeric(msg)
	case "474": // ERR_BANNEDFROMCHAN
		c.handleErrorNumeric(msg)
	case "475": // ERR_BADCHANKEY
		c.handleErrorNumeric(msg)
	case "481": // ERR_NOPRIVILEGES
		c.handleErrorNumeric(msg)
	case "482": // ERR_CHANOPRIVSNEEDED
		c.handleErrorNumeric(msg)

	// --- MONITOR (IRCv3) ---
	case "730": // RPL_MONONLINE
		c.handleMonitorOnline(msg)
	case "731": // RPL_MONOFFLINE
		c.handleMonitorOffline(msg)
	case "732": // RPL_MONLIST
		// informational
	case "733": // RPL_ENDOFMONLIST
		// informational
	case "734": // ERR_MONLISTFULL
		// monitor list full

	// --- IRCv3 commands ---
	case "ACCOUNT": // account-notify
		c.handleAccountNotify(msg)
	case "CHGHOST": // chghost
		// nick changed user@host — informational
	case "SETNAME": // setname
		// nick changed realname — informational
	case "INVITE": // invite-notify
		c.handleInvite(msg)
	case "TAGMSG": // message-tags only, no content
		c.handleTagMsg(msg)

	// --- Messages ---
	case "PRIVMSG":
		c.handlePrivmsg(msg)
	case "NOTICE":
		c.handleNotice(msg)

	// --- MODE ---
	case "MODE":
		c.handleMode(msg)

	// --- Channel URL ---
	case "328": // RPL_CHANNEL_URL
		c.handleChannelURL(msg)

	// --- LUSERS ---
	case "251", "252", "253", "254", "255", "265", "266":
		// lusers info — handled by serverInfo

	// --- ERROR ---
	case "ERROR":
		c.handleServerError(msg)
	}
}

// ---------------------------------------------------------------------------
// CAP/SASL handlers
// ---------------------------------------------------------------------------

// wantedCaps lists all IRCv3 capabilities we request if available.
var ircWantedCaps = []string{
	"sasl", "message-tags", "server-time", "account-notify",
	"away-notify", "extended-join", "multi-prefix", "echo-message",
	"chghost", "invite-notify", "cap-notify", "message-ids",
	"account-tag", "batch", "labeled-response", "setname",
	"monitor", "userhost-in-names", "draft/read-marker",
	"draft/chathistory", "draft/account-registration",
	"draft/channel-rename", "draft/message-redaction",
	"draft/multiline", "draft/pre-away", "draft/event-playback",
	"standard-replies",
}

func (c *IRCCore) handleCAP(msg *ircMsg) {
	if len(msg.Params) < 2 {
		return
	}
	subCmd := msg.Params[1]
	switch subCmd {
	case "LS":
		caps := msg.Trailing()
		var reqCaps []string
		for _, want := range ircWantedCaps {
			if want == "sasl" && !c.useSASL {
				continue
			}
			if strings.Contains(caps, want) {
				reqCaps = append(reqCaps, want)
			}
		}
		if len(reqCaps) > 0 {
			c.sendRaw("CAP REQ :" + strings.Join(reqCaps, " "))
		} else {
			c.sendRaw("CAP END")
		}
	case "ACK":
		acked := msg.Trailing()
		// Track enabled caps
		c.enabledCapsMu.Lock()
		for _, cap := range strings.Fields(acked) {
			c.enabledCaps[strings.TrimPrefix(cap, "-")] = !strings.HasPrefix(cap, "-")
		}
		c.enabledCapsMu.Unlock()

		if strings.Contains(acked, "sasl") && c.useSASL {
			c.sendRaw("AUTHENTICATE PLAIN")
		} else {
			c.sendRaw("CAP END")
		}
	case "NAK":
		c.sendRaw("CAP END")
	case "NEW": // cap-notify: server added new caps
		caps := msg.Trailing()
		var reqCaps []string
		for _, want := range ircWantedCaps {
			if want == "sasl" {
				continue
			}
			if strings.Contains(caps, want) {
				reqCaps = append(reqCaps, want)
			}
		}
		if len(reqCaps) > 0 {
			c.sendRaw("CAP REQ :" + strings.Join(reqCaps, " "))
		}
	case "DEL": // cap-notify: server removed caps
		removed := strings.Fields(msg.Trailing())
		c.enabledCapsMu.Lock()
		for _, cap := range removed {
			delete(c.enabledCaps, cap)
		}
		c.enabledCapsMu.Unlock()
	}
}

func (c *IRCCore) handleAuthenticate(msg *ircMsg) {
	if msg.Trailing() == "+" || (len(msg.Params) > 0 && msg.Params[0] == "+") {
		// Send SASL PLAIN: \0username\0password
		payload := fmt.Sprintf("\x00%s\x00%s", c.username, c.password)
		encoded := base64.StdEncoding.EncodeToString([]byte(payload))
		c.sendRaw("AUTHENTICATE " + encoded)
	}
}

// ---------------------------------------------------------------------------
// Channel event handlers
// ---------------------------------------------------------------------------

func (c *IRCCore) handleJoin(msg *ircMsg) {
	channel := msg.Trailing()
	if channel == "" && len(msg.Params) > 0 {
		channel = msg.Params[0]
	}
	nick := msg.Nick()
	chanLower := strings.ToLower(channel)

	c.channelsMu.Lock()
	ch, ok := c.channels[chanLower]
	if !ok {
		ch = &ircChannel{
			Name:    channel,
			Members: make(map[string]string),
		}
		c.channels[chanLower] = ch
	}
	ch.Members[nick] = ""
	c.channelsMu.Unlock()

	// If we joined, request topic & names
	c.mu.RLock()
	myNick := c.nick
	c.mu.RUnlock()
	if strings.EqualFold(nick, myNick) {
		c.sendRaw("TOPIC " + channel)
		c.sendRaw("MODE " + channel)
	}

	c.emitUpdate(Update{
		Type:     UpdateGroupMembers,
		ChatID:   channel,
		UserID:   nick,
		Platform: "irc",
	})
}

func (c *IRCCore) handlePart(msg *ircMsg) {
	channel := ""
	if len(msg.Params) > 0 {
		channel = msg.Params[0]
	}
	nick := msg.Nick()
	chanLower := strings.ToLower(channel)

	c.channelsMu.Lock()
	if ch, ok := c.channels[chanLower]; ok {
		delete(ch.Members, nick)
	}
	// If we parted, remove channel
	c.mu.RLock()
	myNick := c.nick
	c.mu.RUnlock()
	if strings.EqualFold(nick, myNick) {
		delete(c.channels, chanLower)
	}
	c.channelsMu.Unlock()

	c.emitUpdate(Update{
		Type:     UpdateGroupMembers,
		ChatID:   channel,
		UserID:   nick,
		Platform: "irc",
	})
}

func (c *IRCCore) handleKick(msg *ircMsg) {
	if len(msg.Params) < 2 {
		return
	}
	channel := msg.Params[0]
	kicked := msg.Params[1]
	chanLower := strings.ToLower(channel)

	c.channelsMu.Lock()
	if ch, ok := c.channels[chanLower]; ok {
		delete(ch.Members, kicked)
	}
	c.mu.RLock()
	myNick := c.nick
	c.mu.RUnlock()
	if strings.EqualFold(kicked, myNick) {
		delete(c.channels, chanLower)
	}
	c.channelsMu.Unlock()

	c.emitUpdate(Update{
		Type:     UpdateGroupMembers,
		ChatID:   channel,
		UserID:   kicked,
		Platform: "irc",
	})
}

func (c *IRCCore) handleQuit(msg *ircMsg) {
	nick := msg.Nick()
	c.channelsMu.Lock()
	for _, ch := range c.channels {
		delete(ch.Members, nick)
	}
	c.channelsMu.Unlock()
}

func (c *IRCCore) handleNickChange(msg *ircMsg) {
	oldNick := msg.Nick()
	newNick := msg.Trailing()
	if newNick == "" && len(msg.Params) > 0 {
		newNick = msg.Params[0]
	}

	// Update our own nick
	c.mu.Lock()
	if strings.EqualFold(oldNick, c.nick) {
		c.nick = newNick
	}
	c.mu.Unlock()

	// Update channel members
	c.channelsMu.Lock()
	for _, ch := range c.channels {
		if mode, ok := ch.Members[oldNick]; ok {
			delete(ch.Members, oldNick)
			ch.Members[newNick] = mode
		}
	}
	c.channelsMu.Unlock()

	// Update DM partner tracking
	c.dmPartnersMu.Lock()
	if c.dmPartners[strings.ToLower(oldNick)] {
		delete(c.dmPartners, strings.ToLower(oldNick))
		c.dmPartners[strings.ToLower(newNick)] = true
	}
	c.dmPartnersMu.Unlock()
}

// ---------------------------------------------------------------------------
// NAMES handling
// ---------------------------------------------------------------------------

func (c *IRCCore) handleNamesReply(msg *ircMsg) {
	// :server 353 mynick = #channel :@op +voice regular
	if len(msg.Params) < 3 {
		return
	}
	channel := msg.Params[2]
	names := msg.Trailing()
	chanLower := strings.ToLower(channel)

	c.channelsMu.Lock()
	ch, ok := c.channels[chanLower]
	if !ok {
		ch = &ircChannel{
			Name:    channel,
			Members: make(map[string]string),
		}
		c.channels[chanLower] = ch
	}
	for _, name := range strings.Fields(names) {
		mode := ""
		if strings.HasPrefix(name, "@") {
			mode = "@"
			name = name[1:]
		} else if strings.HasPrefix(name, "+") {
			mode = "+"
			name = name[1:]
		} else if strings.HasPrefix(name, "%") {
			mode = "%"
			name = name[1:]
		} else if strings.HasPrefix(name, "~") {
			mode = "~"
			name = name[1:]
		} else if strings.HasPrefix(name, "&") {
			mode = "&"
			name = name[1:]
		}
		ch.Members[name] = mode
	}
	c.channelsMu.Unlock()
}

// ---------------------------------------------------------------------------
// TOPIC handling
// ---------------------------------------------------------------------------

func (c *IRCCore) handleTopicChange(msg *ircMsg) {
	if len(msg.Params) < 1 {
		return
	}
	channel := msg.Params[0]
	topic := msg.Trailing()
	chanLower := strings.ToLower(channel)

	c.channelsMu.Lock()
	if ch, ok := c.channels[chanLower]; ok {
		ch.Topic = topic
		ch.TopicBy = msg.Nick()
		ch.TopicAt = time.Now()
	}
	c.channelsMu.Unlock()
}

func (c *IRCCore) handleTopicReply(msg *ircMsg) {
	// :server 332 mynick #channel :topic text
	if len(msg.Params) < 2 {
		return
	}
	channel := msg.Params[1]
	topic := msg.Trailing()
	chanLower := strings.ToLower(channel)

	c.channelsMu.Lock()
	if ch, ok := c.channels[chanLower]; ok {
		ch.Topic = topic
	}
	c.channelsMu.Unlock()
}

func (c *IRCCore) handleTopicWhoTime(msg *ircMsg) {
	// :server 333 mynick #channel setter timestamp
	if len(msg.Params) < 4 {
		return
	}
	channel := msg.Params[1]
	setter := msg.Params[2]
	chanLower := strings.ToLower(channel)

	c.channelsMu.Lock()
	if ch, ok := c.channels[chanLower]; ok {
		ch.TopicBy = setter
	}
	c.channelsMu.Unlock()
}

// ---------------------------------------------------------------------------
// Channel mode/creation
// ---------------------------------------------------------------------------

func (c *IRCCore) handleChannelMode(msg *ircMsg) {
	// :server 324 mynick #channel +modes
	if len(msg.Params) < 3 {
		return
	}
	channel := msg.Params[1]
	modes := msg.Params[2]
	chanLower := strings.ToLower(channel)

	c.channelsMu.Lock()
	if ch, ok := c.channels[chanLower]; ok {
		ch.Modes = modes
	}
	c.channelsMu.Unlock()
}

func (c *IRCCore) handleCreationTime(msg *ircMsg) {
	// :server 329 mynick #channel timestamp
	if len(msg.Params) < 3 {
		return
	}
	channel := msg.Params[1]
	chanLower := strings.ToLower(channel)

	c.channelsMu.Lock()
	if ch, ok := c.channels[chanLower]; ok {
		var ts int64
		fmt.Sscanf(msg.Params[2], "%d", &ts)
		if ts > 0 {
			ch.Created = time.Unix(ts, 0)
		}
	}
	c.channelsMu.Unlock()
}

// ---------------------------------------------------------------------------
// MODE changes (user modes in channel)
// ---------------------------------------------------------------------------

func (c *IRCCore) handleMode(msg *ircMsg) {
	if len(msg.Params) < 2 {
		return
	}
	target := msg.Params[0]
	if !strings.HasPrefix(target, "#") && !strings.HasPrefix(target, "&") {
		return // user mode, ignore
	}
	chanLower := strings.ToLower(target)
	modes := msg.Params[1]
	modeParams := msg.Params[2:]

	c.channelsMu.Lock()
	ch, ok := c.channels[chanLower]
	if !ok {
		c.channelsMu.Unlock()
		return
	}

	adding := true
	paramIdx := 0
	for _, modeChar := range modes {
		switch modeChar {
		case '+':
			adding = true
		case '-':
			adding = false
		case 'o', 'v', 'h', 'q', 'a': // ops, voice, halfop, owner, admin
			if paramIdx < len(modeParams) {
				nick := modeParams[paramIdx]
				paramIdx++
				if adding {
					prefix := ""
					switch modeChar {
					case 'o':
						prefix = "@"
					case 'v':
						prefix = "+"
					case 'h':
						prefix = "%"
					case 'q':
						prefix = "~"
					case 'a':
						prefix = "&"
					}
					ch.Members[nick] = prefix
				} else {
					ch.Members[nick] = ""
				}
			}
		case 'b', 'e', 'I': // ban, exempt, invite — take parameter
			if paramIdx < len(modeParams) {
				paramIdx++
			}
		case 'k', 'l', 'j', 'f': // key, limit, etc — take parameter on set
			if adding && paramIdx < len(modeParams) {
				paramIdx++
			}
		}
	}
	c.channelsMu.Unlock()

	c.emitUpdate(Update{
		Type:     UpdateGroupMembers,
		ChatID:   target,
		Platform: "irc",
	})
}

// ---------------------------------------------------------------------------
// WHOIS handling
// ---------------------------------------------------------------------------

func (c *IRCCore) handleWhoisUser(msg *ircMsg) {
	// :server 311 mynick target username host * :realname
	if len(msg.Params) < 4 {
		return
	}
	nick := msg.Params[1]
	username := msg.Params[2]
	host := msg.Params[3]
	realname := msg.Trailing()

	user := &User{
		ID:          nick,
		Username:    username + "@" + host,
		DisplayName: realname,
		Platform:    "irc",
	}

	c.whoisCacheMu.Lock()
	c.whoisCache[strings.ToLower(nick)] = user
	c.whoisCacheMu.Unlock()
}

func (c *IRCCore) handleWhoisEnd(msg *ircMsg) {
	if len(msg.Params) < 2 {
		return
	}
	nick := strings.ToLower(msg.Params[1])

	c.whoisWaitMu.Lock()
	if ch, ok := c.whoisWait[nick]; ok {
		close(ch)
		delete(c.whoisWait, nick)
	}
	c.whoisWaitMu.Unlock()
}

// ---------------------------------------------------------------------------
// Message handlers
// ---------------------------------------------------------------------------

func (c *IRCCore) handlePrivmsg(msg *ircMsg) {
	if len(msg.Params) < 1 {
		return
	}
	target := msg.Params[0]
	text := msg.Trailing()
	nick := msg.Nick()

	// Handle CTCP
	if strings.HasPrefix(text, "\x01") && strings.HasSuffix(text, "\x01") {
		c.handleCTCP(msg, nick, target, text[1:len(text)-1])
		return
	}

	// Blocked user check
	c.blockedMu.RLock()
	blocked := c.blocked[strings.ToLower(nick)]
	c.blockedMu.RUnlock()
	if blocked {
		return
	}

	// Determine chatID
	c.mu.RLock()
	myNick := c.nick
	c.mu.RUnlock()

	chatID := target
	if strings.EqualFold(target, myNick) {
		// DM — use sender's nick as chat ID
		chatID = nick
		c.dmPartnersMu.Lock()
		c.dmPartners[strings.ToLower(nick)] = true
		c.dmPartnersMu.Unlock()
	}

	// Parse timestamp from IRCv3 server-time tag
	ts := time.Now()
	if timeTag, ok := msg.Tags["time"]; ok {
		if parsed, err := time.Parse(time.RFC3339, timeTag); err == nil {
			ts = parsed
		}
	}

	// Create message
	c.msgCounter++
	m := &Message{
		ID:         fmt.Sprintf("%d", c.msgCounter),
		ChatID:     chatID,
		SenderID:   nick,
		SenderName: nick,
		Text:       text,
		Timestamp:  ts,
		Platform:   "irc",
	}

	// Check if message ID is in tags
	if msgID, ok := msg.Tags["msgid"]; ok {
		m.ID = msgID
	}

	// Buffer message
	c.bufferMessage(chatID, m)

	// Emit update
	c.emitUpdate(Update{
		Type:     UpdateNewMessage,
		ChatID:   chatID,
		Message:  m,
		Platform: "irc",
	})
}

func (c *IRCCore) handleNotice(msg *ircMsg) {
	if len(msg.Params) < 1 {
		return
	}
	target := msg.Params[0]
	text := msg.Trailing()
	nick := msg.Nick()

	c.mu.RLock()
	myNick := c.nick
	c.mu.RUnlock()

	chatID := target
	if strings.EqualFold(target, myNick) {
		chatID = nick
	}

	// Buffer as regular message with [NOTICE] prefix
	c.msgCounter++
	m := &Message{
		ID:         fmt.Sprintf("%d", c.msgCounter),
		ChatID:     chatID,
		SenderID:   nick,
		SenderName: nick,
		Text:       "[NOTICE] " + text,
		Timestamp:  time.Now(),
		Platform:   "irc",
	}
	c.bufferMessage(chatID, m)

	c.emitUpdate(Update{
		Type:     UpdateNewMessage,
		ChatID:   chatID,
		Message:  m,
		Platform: "irc",
	})
}

func (c *IRCCore) handleCTCP(msg *ircMsg, nick, target, ctcp string) {
	parts := strings.SplitN(ctcp, " ", 2)
	cmd := strings.ToUpper(parts[0])

	switch cmd {
	case "VERSION":
		c.sendRaw(fmt.Sprintf("NOTICE %s :\x01VERSION Uniclient IRC 1.0\x01", nick))
	case "PING":
		c.sendRaw(fmt.Sprintf("NOTICE %s :\x01%s\x01", nick, ctcp))
	case "TIME":
		c.sendRaw(fmt.Sprintf("NOTICE %s :\x01TIME %s\x01", nick, time.Now().Format(time.RFC1123)))
	case "CLIENTINFO":
		c.sendRaw(fmt.Sprintf("NOTICE %s :\x01CLIENTINFO ACTION PING VERSION TIME CLIENTINFO FINGER USERINFO SOURCE DCC\x01", nick))
	case "FINGER":
		c.mu.RLock()
		myNick := c.nick
		c.mu.RUnlock()
		c.sendRaw(fmt.Sprintf("NOTICE %s :\x01FINGER %s (Uniclient IRC)\x01", nick, myNick))
	case "USERINFO":
		c.mu.RLock()
		myNick := c.nick
		c.mu.RUnlock()
		c.sendRaw(fmt.Sprintf("NOTICE %s :\x01USERINFO %s\x01", nick, myNick))
	case "SOURCE":
		c.sendRaw(fmt.Sprintf("NOTICE %s :\x01SOURCE https://github.com/DarkReaperBoy/uniclient\x01", nick))
	case "ACTION":
		// Treat /me as a regular message with action formatting
		actionText := ""
		if len(parts) > 1 {
			actionText = parts[1]
		}

		c.mu.RLock()
		myNick := c.nick
		c.mu.RUnlock()

		chatID := target
		if strings.EqualFold(target, myNick) {
			chatID = nick
		}

		c.msgCounter++
		m := &Message{
			ID:         fmt.Sprintf("%d", c.msgCounter),
			ChatID:     chatID,
			SenderID:   nick,
			SenderName: nick,
			Text:       "* " + nick + " " + actionText,
			Timestamp:  time.Now(),
			Platform:   "irc",
		}
		c.bufferMessage(chatID, m)

		c.emitUpdate(Update{
			Type:     UpdateNewMessage,
			ChatID:   chatID,
			Message:  m,
			Platform: "irc",
		})

	case "DCC":
		// Parse DCC offers (SEND, CHAT, RESUME, ACCEPT) and emit as update
		if len(parts) < 2 {
			return
		}
		dccParts := strings.Fields(parts[1])
		if len(dccParts) < 2 {
			return
		}
		dccType := strings.ToUpper(dccParts[0])

		offer := IRCDCCOffer{
			Type: dccType,
			From: nick,
		}
		switch dccType {
		case "SEND":
			if len(dccParts) >= 4 {
				offer.Filename = dccParts[1]
				offer.IP = dccParts[2]
				offer.Port, _ = strconv.Atoi(dccParts[3])
				if len(dccParts) >= 5 {
					offer.Size, _ = strconv.ParseInt(dccParts[4], 10, 64)
				}
			}
		case "CHAT":
			if len(dccParts) >= 4 {
				offer.IP = dccParts[2]
				offer.Port, _ = strconv.Atoi(dccParts[3])
			}
		}

		c.dccOffersMu.Lock()
		c.dccOffers = append(c.dccOffers, offer)
		c.dccOffersMu.Unlock()

		// Emit as a message so the UI can handle it
		dccChatID := nick
		c.msgCounter++
		dccMsg := &Message{
			ID:         fmt.Sprintf("%d", c.msgCounter),
			ChatID:     dccChatID,
			SenderID:   nick,
			SenderName: nick,
			Text:       fmt.Sprintf("[DCC %s] %s", dccType, parts[1]),
			Timestamp:  time.Now(),
			Platform:   "irc",
		}
		c.bufferMessage(dccChatID, dccMsg)
		c.emitUpdate(Update{
			Type:     UpdateNewMessage,
			ChatID:   dccChatID,
			Message:  dccMsg,
			Platform: "irc",
		})
	}
}

// ---------------------------------------------------------------------------
// Ping loop
// ---------------------------------------------------------------------------

func (c *IRCCore) pingLoop() {
	ticker := time.NewTicker(ircPingInterval)
	defer ticker.Stop()

	for {
		select {
		case <-c.ctx.Done():
			return
		case <-ticker.C:
			c.sendRaw("PING :uniclient")
		}
	}
}

// ---------------------------------------------------------------------------
// Message buffer
// ---------------------------------------------------------------------------

func (c *IRCCore) bufferMessage(chatID string, msg *Message) {
	c.messagesMu.Lock()
	defer c.messagesMu.Unlock()

	buf := c.messages[chatID]
	buf = append(buf, msg)
	if len(buf) > ircMsgBufSize {
		buf = buf[len(buf)-ircMsgBufSize:]
	}
	c.messages[chatID] = buf
}

// ---------------------------------------------------------------------------
// Update emitter
// ---------------------------------------------------------------------------

func (c *IRCCore) emitUpdate(u Update) {
	c.updateMu.RLock()
	handlers := make([]func(Update), len(c.updateHandlers))
	copy(handlers, c.updateHandlers)
	c.updateMu.RUnlock()

	for _, h := range handlers {
		h(u)
	}
}

// ---------------------------------------------------------------------------
// Core interface — Dialogs
// ---------------------------------------------------------------------------

func (c *IRCCore) GetDialogs(opts PaginationOpts) ([]Dialog, error) {
	if !c.authed {
		return nil, ErrAuth
	}

	var dialogs []Dialog

	// Channels
	c.channelsMu.RLock()
	for _, ch := range c.channels {
		d := Dialog{
			ID:          ch.Name,
			Type:        ChatTypeGroup,
			Title:       ch.Name,
			MemberCount: len(ch.Members),
			Platform:    "irc",
		}
		// Last message
		c.messagesMu.RLock()
		if msgs, ok := c.messages[ch.Name]; ok && len(msgs) > 0 {
			last := msgs[len(msgs)-1]
			d.LastMessage = last
		}
		c.messagesMu.RUnlock()
		dialogs = append(dialogs, d)
	}
	c.channelsMu.RUnlock()

	// DM partners
	c.dmPartnersMu.RLock()
	for nick := range c.dmPartners {
		d := Dialog{
			ID:       nick,
			Type:     ChatTypeDM,
			Title:    nick,
			Platform: "irc",
		}
		c.messagesMu.RLock()
		if msgs, ok := c.messages[nick]; ok && len(msgs) > 0 {
			last := msgs[len(msgs)-1]
			d.LastMessage = last
		}
		c.messagesMu.RUnlock()
		dialogs = append(dialogs, d)
	}
	c.dmPartnersMu.RUnlock()

	// Apply pagination
	if opts.Limit > 0 && len(dialogs) > opts.Limit {
		dialogs = dialogs[:opts.Limit]
	}

	return dialogs, nil
}

func (c *IRCCore) CreateGroup(name string, members []string) (*Dialog, error) {
	if !c.authed {
		return nil, ErrAuth
	}
	// In IRC, creating a group = joining a channel
	if !strings.HasPrefix(name, "#") {
		name = "#" + name
	}
	c.sendRaw("JOIN " + name)
	time.Sleep(time.Second) // wait for JOIN response

	// Invite members
	for _, m := range members {
		c.sendRaw("INVITE " + m + " " + name)
	}

	return &Dialog{
		ID:       name,
		Type:     ChatTypeGroup,
		Title:    name,
		Platform: "irc",
	}, nil
}

func (c *IRCCore) CreateChannel(name string, description string) (*Dialog, error) {
	// IRC channels and groups are the same thing
	d, err := c.CreateGroup(name, nil)
	if err != nil {
		return nil, err
	}
	d.Type = ChatTypeChannel
	if description != "" {
		c.sendRaw("TOPIC " + d.ID + " :" + description)
	}
	return d, nil
}

func (c *IRCCore) CreateTopic(_ string, _ string) (*Dialog, error) {
	return nil, ErrNotSupported
}

func (c *IRCCore) GetFolders() ([]Folder, error) {
	return nil, ErrNotSupported
}

func (c *IRCCore) CreateFolder(_ string, _ []string) (*Folder, error) {
	return nil, ErrNotSupported
}

// ---------------------------------------------------------------------------
// Core interface — Messages
// ---------------------------------------------------------------------------

func (c *IRCCore) SendMessage(chatID string, msg OutgoingMessage) (*Message, error) {
	if !c.authed {
		return nil, ErrAuth
	}

	text := msg.Text
	if text == "" {
		return nil, fmt.Errorf("%w: empty message", ErrInvalidInput)
	}

	// Split long messages (IRC has ~512 byte line limit)
	// Overhead: "PRIVMSG target :" = 10 + len(target) + CRLF
	maxLen := 400 - len(chatID) // conservative limit
	if maxLen < 100 {
		maxLen = 100
	}

	lines := strings.Split(text, "\n")
	var lastMsg *Message
	for _, line := range lines {
		if line == "" {
			continue
		}
		// Further split if line too long
		for len(line) > 0 {
			chunk := line
			if len(chunk) > maxLen {
				chunk = line[:maxLen]
				line = line[maxLen:]
			} else {
				line = ""
			}
			c.sendRaw("PRIVMSG " + chatID + " :" + chunk)

			c.mu.RLock()
			myNick := c.nick
			c.mu.RUnlock()

			c.msgCounter++
			lastMsg = &Message{
				ID:         fmt.Sprintf("%d", c.msgCounter),
				ChatID:     chatID,
				SenderID:   myNick,
				SenderName: myNick,
				Text:       chunk,
				Timestamp:  time.Now(),
				Platform:   "irc",
			}
			c.bufferMessage(chatID, lastMsg)
		}
	}

	if lastMsg == nil {
		return nil, fmt.Errorf("%w: empty message after splitting", ErrInvalidInput)
	}

	// Track DM partner
	if !strings.HasPrefix(chatID, "#") && !strings.HasPrefix(chatID, "&") {
		c.dmPartnersMu.Lock()
		c.dmPartners[strings.ToLower(chatID)] = true
		c.dmPartnersMu.Unlock()
	}

	return lastMsg, nil
}

func (c *IRCCore) GetMessages(chatID string, opts PaginationOpts) ([]Message, error) {
	if !c.authed {
		return nil, ErrAuth
	}

	c.messagesMu.RLock()
	defer c.messagesMu.RUnlock()

	buf, ok := c.messages[chatID]
	if !ok {
		return []Message{}, nil
	}

	// Return copies
	result := make([]Message, 0, len(buf))
	for _, m := range buf {
		result = append(result, *m)
	}

	// Apply pagination (from newest)
	if opts.Limit > 0 && len(result) > opts.Limit {
		result = result[len(result)-opts.Limit:]
	}

	return result, nil
}

func (c *IRCCore) EditMessage(_ string, _ string, _ string) (*Message, error) {
	return nil, ErrNotSupported
}

func (c *IRCCore) DeleteMessage(_ string, _ string) error {
	return ErrNotSupported
}

func (c *IRCCore) ReplyToMessage(chatID string, replyToMsgID string, msg OutgoingMessage) (*Message, error) {
	if !c.authed {
		return nil, ErrAuth
	}

	text := msg.Text
	if replyToMsgID != "" {
		// Find original message and quote it
		c.messagesMu.RLock()
		for _, m := range c.messages[chatID] {
			if m.ID == replyToMsgID {
				firstLine := m.Text
				if idx := strings.Index(firstLine, "\n"); idx > 0 {
					firstLine = firstLine[:idx]
				}
				if len(firstLine) > 80 {
					firstLine = firstLine[:80] + "..."
				}
				text = fmt.Sprintf("<%s> %s — %s", m.SenderName, firstLine, msg.Text)
				break
			}
		}
		c.messagesMu.RUnlock()
	}

	return c.SendMessage(chatID, OutgoingMessage{Text: text})
}

func (c *IRCCore) ForwardMessage(fromChatID string, msgID string, toChatID string) (*Message, error) {
	if !c.authed {
		return nil, ErrAuth
	}

	// Find original message
	c.messagesMu.RLock()
	var original *Message
	for _, m := range c.messages[fromChatID] {
		if m.ID == msgID {
			original = m
			break
		}
	}
	c.messagesMu.RUnlock()

	if original == nil {
		return nil, ErrNotFound
	}

	text := fmt.Sprintf("[Fwd from %s] %s", original.SenderName, original.Text)
	return c.SendMessage(toChatID, OutgoingMessage{Text: text})
}

func (c *IRCCore) ReactToMessage(_ string, _ string, _ string) error {
	return ErrNotSupported
}

func (c *IRCCore) PinMessage(chatID string, msgID string) error {
	c.pinnedMu.Lock()
	if c.pinned[chatID] == nil {
		c.pinned[chatID] = make(map[string]bool)
	}
	c.pinned[chatID][msgID] = true
	c.pinnedMu.Unlock()
	c.saveSession()
	return nil
}

func (c *IRCCore) UnpinMessage(chatID string, msgID string) error {
	c.pinnedMu.Lock()
	if c.pinned[chatID] != nil {
		delete(c.pinned[chatID], msgID)
	}
	c.pinnedMu.Unlock()
	c.saveSession()
	return nil
}

// ---------------------------------------------------------------------------
// Core interface — Read State
// ---------------------------------------------------------------------------

func (c *IRCCore) MarkAsRead(chatID string, upToMsgID string) error {
	c.readStateMu.Lock()
	if c.readState[chatID] == nil {
		c.readState[chatID] = &ReadState{}
	}
	c.readState[chatID].MyLastRead = upToMsgID
	c.readStateMu.Unlock()
	return nil
}

func (c *IRCCore) GetReadState(chatID string) (*ReadState, error) {
	c.readStateMu.RLock()
	defer c.readStateMu.RUnlock()
	if rs, ok := c.readState[chatID]; ok {
		return rs, nil
	}
	return &ReadState{}, nil
}

// ---------------------------------------------------------------------------
// Core interface — Files (not supported)
// ---------------------------------------------------------------------------

func (c *IRCCore) UploadFile(_ string, _ FileUpload, _ func(int64, int64)) (*Message, error) {
	return nil, ErrNotSupported
}

func (c *IRCCore) DownloadFile(_ FileRef, _ string, _ func(int64, int64)) error {
	return ErrNotSupported
}

func (c *IRCCore) SendImageBase64(_ string, _ string, _ string) (*Message, error) {
	return nil, ErrNotSupported
}

// ---------------------------------------------------------------------------
// Core interface — Calls (not supported)
// ---------------------------------------------------------------------------

func (c *IRCCore) StartCall(_ string, _ bool) (*CallSession, error) {
	return nil, ErrNotSupported
}

func (c *IRCCore) JoinGroupCall(_ string) (*CallSession, error) {
	return nil, ErrNotSupported
}

func (c *IRCCore) EndCall(_ string) error {
	return ErrNotSupported
}

func (c *IRCCore) SetCallMuted(_ string, _ bool) error {
	return ErrNotSupported
}

// ---------------------------------------------------------------------------
// Core interface — Profile
// ---------------------------------------------------------------------------

func (c *IRCCore) GetProfile(userID string) (*User, error) {
	if !c.authed {
		return nil, ErrAuth
	}

	nickLower := strings.ToLower(userID)

	// Check cache first
	c.whoisCacheMu.RLock()
	if user, ok := c.whoisCache[nickLower]; ok {
		c.whoisCacheMu.RUnlock()
		return user, nil
	}
	c.whoisCacheMu.RUnlock()

	// Send WHOIS and wait for response
	waitCh := make(chan struct{})
	c.whoisWaitMu.Lock()
	c.whoisWait[nickLower] = waitCh
	c.whoisWaitMu.Unlock()

	c.sendRaw("WHOIS " + userID)

	select {
	case <-waitCh:
	case <-time.After(10 * time.Second):
		c.whoisWaitMu.Lock()
		delete(c.whoisWait, nickLower)
		c.whoisWaitMu.Unlock()
		return nil, fmt.Errorf("%w: WHOIS timeout for %s", ErrNetwork, userID)
	case <-c.ctx.Done():
		return nil, c.ctx.Err()
	}

	c.whoisCacheMu.RLock()
	user, ok := c.whoisCache[nickLower]
	c.whoisCacheMu.RUnlock()

	if !ok {
		return nil, fmt.Errorf("%w: user %s not found", ErrNotFound, userID)
	}
	return user, nil
}

// ---------------------------------------------------------------------------
// Core interface — Real-time
// ---------------------------------------------------------------------------

func (c *IRCCore) OnUpdate(handler func(Update)) {
	c.updateMu.Lock()
	c.updateHandlers = append(c.updateHandlers, handler)
	c.updateMu.Unlock()
}

func (c *IRCCore) Close() error {
	c.mu.Lock()
	defer c.mu.Unlock()

	if c.authed {
		c.sendRaw("QUIT :Goodbye")
	}
	c.cancel()
	if c.conn != nil {
		c.conn.Close()
	}
	c.authed = false
	return nil
}

// ---------------------------------------------------------------------------
// Core interface — Chat Info & Settings
// ---------------------------------------------------------------------------

func (c *IRCCore) GetChatInfo(chatID string) (*Dialog, error) {
	if !c.authed {
		return nil, ErrAuth
	}

	// DM
	if !strings.HasPrefix(chatID, "#") && !strings.HasPrefix(chatID, "&") {
		return &Dialog{
			ID:       chatID,
			Type:     ChatTypeDM,
			Title:    chatID,
			Platform: "irc",
		}, nil
	}

	// Channel
	chanLower := strings.ToLower(chatID)
	c.channelsMu.RLock()
	ch, ok := c.channels[chanLower]
	c.channelsMu.RUnlock()

	if !ok {
		return nil, fmt.Errorf("%w: not in channel %s", ErrNotFound, chatID)
	}

	return &Dialog{
		ID:          ch.Name,
		Type:        ChatTypeGroup,
		Title:       ch.Name,
		MemberCount: len(ch.Members),
		Platform:    "irc",
	}, nil
}

func (c *IRCCore) EditChatTitle(_ string, _ string) error {
	// IRC channel names are immutable
	return ErrNotSupported
}

func (c *IRCCore) EditChatDescription(chatID string, description string) error {
	if !c.authed {
		return ErrAuth
	}
	// Set channel topic
	c.sendRaw("TOPIC " + chatID + " :" + description)
	return nil
}

func (c *IRCCore) LeaveChat(chatID string) error {
	if !c.authed {
		return ErrAuth
	}
	if strings.HasPrefix(chatID, "#") || strings.HasPrefix(chatID, "&") {
		c.sendRaw("PART " + chatID)
	} else {
		// Remove DM partner from tracking
		c.dmPartnersMu.Lock()
		delete(c.dmPartners, strings.ToLower(chatID))
		c.dmPartnersMu.Unlock()
	}
	return nil
}

func (c *IRCCore) GetInviteLink(_ string) (string, error) {
	return "", ErrNotSupported
}

// ---------------------------------------------------------------------------
// Core interface — Member Management
// ---------------------------------------------------------------------------

func (c *IRCCore) AddMembers(chatID string, userIDs []string) error {
	if !c.authed {
		return ErrAuth
	}
	for _, uid := range userIDs {
		c.sendRaw("INVITE " + uid + " " + chatID)
	}
	return nil
}

func (c *IRCCore) RemoveMember(chatID string, userID string) error {
	if !c.authed {
		return ErrAuth
	}
	c.sendRaw("KICK " + chatID + " " + userID)
	return nil
}

func (c *IRCCore) BanMember(chatID string, userID string) error {
	if !c.authed {
		return ErrAuth
	}
	// Ban by nick — need to look up hostmask for proper ban
	// Simple ban: MODE #channel +b nick!*@*
	c.sendRaw("MODE " + chatID + " +b " + userID + "!*@*")
	c.sendRaw("KICK " + chatID + " " + userID + " :Banned")
	return nil
}

func (c *IRCCore) UnbanMember(chatID string, userID string) error {
	if !c.authed {
		return ErrAuth
	}
	c.sendRaw("MODE " + chatID + " -b " + userID + "!*@*")
	return nil
}

func (c *IRCCore) GetMembers(chatID string, opts PaginationOpts) ([]User, error) {
	if !c.authed {
		return nil, ErrAuth
	}

	chanLower := strings.ToLower(chatID)
	c.channelsMu.RLock()
	ch, ok := c.channels[chanLower]
	if !ok {
		c.channelsMu.RUnlock()
		return nil, fmt.Errorf("%w: not in channel %s", ErrNotFound, chatID)
	}

	var users []User
	for nick, mode := range ch.Members {
		displayName := nick
		if mode != "" {
			displayName = mode + nick
		}
		users = append(users, User{
			ID:          nick,
			Username:    nick,
			DisplayName: displayName,
			Platform:    "irc",
		})
	}
	c.channelsMu.RUnlock()

	// Sort by nick
	sort.Slice(users, func(i, j int) bool {
		return users[i].ID < users[j].ID
	})

	if opts.Limit > 0 && len(users) > opts.Limit {
		users = users[:opts.Limit]
	}

	return users, nil
}

func (c *IRCCore) SetAdmin(chatID string, userID string, admin bool) error {
	if !c.authed {
		return ErrAuth
	}
	if admin {
		c.sendRaw("MODE " + chatID + " +o " + userID)
	} else {
		c.sendRaw("MODE " + chatID + " -o " + userID)
	}
	return nil
}

// ---------------------------------------------------------------------------
// Core interface — Contacts (local tracking only)
// ---------------------------------------------------------------------------

func (c *IRCCore) GetContacts() ([]User, error) {
	return nil, ErrNotSupported
}

func (c *IRCCore) AddContact(_ string, _ string, _ string) error {
	return ErrNotSupported
}

func (c *IRCCore) DeleteContact(_ string) error {
	return ErrNotSupported
}

func (c *IRCCore) BlockUser(userID string) error {
	c.blockedMu.Lock()
	c.blocked[strings.ToLower(userID)] = true
	c.blockedMu.Unlock()
	c.saveSession()
	return nil
}

func (c *IRCCore) UnblockUser(userID string) error {
	c.blockedMu.Lock()
	delete(c.blocked, strings.ToLower(userID))
	c.blockedMu.Unlock()
	c.saveSession()
	return nil
}

func (c *IRCCore) GetBlockedUsers() ([]User, error) {
	c.blockedMu.RLock()
	defer c.blockedMu.RUnlock()

	var users []User
	for nick := range c.blocked {
		users = append(users, User{
			ID:       nick,
			Username: nick,
			Platform: "irc",
		})
	}
	return users, nil
}

// ---------------------------------------------------------------------------
// Core interface — Search
// ---------------------------------------------------------------------------

func (c *IRCCore) SearchMessages(chatID string, query string, opts PaginationOpts) ([]Message, error) {
	if !c.authed {
		return nil, ErrAuth
	}

	c.messagesMu.RLock()
	defer c.messagesMu.RUnlock()

	buf, ok := c.messages[chatID]
	if !ok {
		return []Message{}, nil
	}

	queryLower := strings.ToLower(query)
	var results []Message
	for _, m := range buf {
		if strings.Contains(strings.ToLower(m.Text), queryLower) ||
			strings.Contains(strings.ToLower(m.SenderName), queryLower) {
			results = append(results, *m)
		}
	}

	if opts.Limit > 0 && len(results) > opts.Limit {
		results = results[len(results)-opts.Limit:]
	}

	return results, nil
}

func (c *IRCCore) SearchGlobal(query string, opts PaginationOpts) ([]Dialog, error) {
	if !c.authed {
		return nil, ErrAuth
	}

	// Search local channels and DMs matching query
	queryLower := strings.ToLower(query)
	var results []Dialog

	c.channelsMu.RLock()
	for _, ch := range c.channels {
		if strings.Contains(strings.ToLower(ch.Name), queryLower) ||
			strings.Contains(strings.ToLower(ch.Topic), queryLower) {
			results = append(results, Dialog{
				ID:          ch.Name,
				Type:        ChatTypeGroup,
				Title:       ch.Name,
				MemberCount: len(ch.Members),
				Platform:    "irc",
			})
		}
	}
	c.channelsMu.RUnlock()

	c.dmPartnersMu.RLock()
	for nick := range c.dmPartners {
		if strings.Contains(nick, queryLower) {
			results = append(results, Dialog{
				ID:       nick,
				Type:     ChatTypeDM,
				Title:    nick,
				Platform: "irc",
			})
		}
	}
	c.dmPartnersMu.RUnlock()

	if opts.Limit > 0 && len(results) > opts.Limit {
		results = results[:opts.Limit]
	}

	return results, nil
}

// ---------------------------------------------------------------------------
// Core interface — Typing
// ---------------------------------------------------------------------------

func (c *IRCCore) SendTyping(_ string) error {
	// IRC has no native typing indicator
	// (IRCv3 draft/typing exists but very few servers support it)
	return nil
}

// ---------------------------------------------------------------------------
// Core interface — Polls (not supported)
// ---------------------------------------------------------------------------

func (c *IRCCore) CreatePoll(_ string, _ string, _ []string) (*Message, error) {
	return nil, ErrNotSupported
}

func (c *IRCCore) VotePoll(_ string, _ string, _ int) error {
	return ErrNotSupported
}

// ---------------------------------------------------------------------------
// Core interface — Stickers (not supported)
// ---------------------------------------------------------------------------

func (c *IRCCore) SendSticker(_ string, _ string) (*Message, error) {
	return nil, ErrNotSupported
}

// ---------------------------------------------------------------------------
// Core interface — Sessions (not supported)
// ---------------------------------------------------------------------------

func (c *IRCCore) GetSessions() ([]Session, error) {
	return nil, ErrNotSupported
}

func (c *IRCCore) TerminateSession(_ string) error {
	return ErrNotSupported
}

// ===========================================================================
// New numeric/command handlers
// ===========================================================================

func (c *IRCCore) handleMyInfo(msg *ircMsg) {
	// :server 004 mynick servername version usermodes chanmodes
	c.serverInfoMu.Lock()
	defer c.serverInfoMu.Unlock()
	if len(msg.Params) >= 3 {
		c.serverInfo.ServerName = msg.Params[1]
	}
	if len(msg.Params) >= 4 {
		c.serverInfo.ServerVer = msg.Params[2]
	}
	if len(msg.Params) >= 5 {
		c.serverInfo.UserModes = msg.Params[3]
	}
	if len(msg.Params) >= 6 {
		c.serverInfo.ChanModes = msg.Params[4]
	}
}

func (c *IRCCore) handleISupport(msg *ircMsg) {
	// :server 005 mynick KEY=VALUE KEY2=VALUE2 ... :are supported by this server
	c.serverInfoMu.Lock()
	defer c.serverInfoMu.Unlock()
	for _, param := range msg.Params[1:] {
		if strings.HasPrefix(param, ":") || param == "are" {
			break
		}
		key := param
		value := ""
		if eq := strings.IndexByte(param, '='); eq >= 0 {
			key = param[:eq]
			value = param[eq+1:]
		}
		c.serverInfo.Raw[key] = value
		switch key {
		case "NETWORK":
			c.serverInfo.Network = value
		case "CASEMAPPING":
			c.serverInfo.CaseMapping = value
		case "CHANTYPES":
			c.serverInfo.ChanTypes = value
		case "PREFIX":
			c.serverInfo.Prefix = value
		case "NICKLEN", "MAXNICKLEN":
			c.serverInfo.MaxNickLen, _ = strconv.Atoi(value)
		case "CHANNELLEN":
			c.serverInfo.MaxChanLen, _ = strconv.Atoi(value)
		case "TOPICLEN":
			c.serverInfo.MaxTopicLen, _ = strconv.Atoi(value)
		case "MODES":
			c.serverInfo.MaxModes, _ = strconv.Atoi(value)
		}
	}
}

func (c *IRCCore) handleWhoisServer(msg *ircMsg) {
	// :server 312 mynick target servername :serverinfo
	// Informational — WHOIS server info
}

func (c *IRCCore) handleWhoisOper(msg *ircMsg) {
	// :server 313 mynick target :is an IRC operator
	if len(msg.Params) < 2 {
		return
	}
	nick := strings.ToLower(msg.Params[1])
	c.whoisCacheMu.Lock()
	if user, ok := c.whoisCache[nick]; ok {
		_ = user // oper status noted
	}
	c.whoisCacheMu.Unlock()
}

func (c *IRCCore) handleWhoisIdle(msg *ircMsg) {
	// :server 317 mynick target seconds signon :seconds idle, signon time
	if len(msg.Params) < 3 {
		return
	}
	nick := strings.ToLower(msg.Params[1])
	idleSecs, _ := strconv.ParseInt(msg.Params[2], 10, 64)
	c.whoisCacheMu.Lock()
	if user, ok := c.whoisCache[nick]; ok {
		user.IsOnline = true
		t := time.Now().Add(-time.Duration(idleSecs) * time.Second)
		user.LastSeen = &t
	}
	c.whoisCacheMu.Unlock()
}

func (c *IRCCore) handleWhoisChannels(msg *ircMsg) {
	// :server 319 mynick target :#chan1 @#chan2 +#chan3
	// Informational — we already track via NAMES
}

func (c *IRCCore) handleWhoisAccount(msg *ircMsg) {
	// :server 330 mynick target account :is logged in as
	if len(msg.Params) < 3 {
		return
	}
	nick := strings.ToLower(msg.Params[1])
	account := msg.Params[2]
	c.whoisCacheMu.Lock()
	if user, ok := c.whoisCache[nick]; ok {
		if user.DisplayName == "" || user.DisplayName == nick {
			user.DisplayName = account
		}
	}
	c.whoisCacheMu.Unlock()
}

func (c *IRCCore) handleWhowasUser(msg *ircMsg) {
	if len(msg.Params) < 4 {
		return
	}
	c.whowasMu.Lock()
	c.whowasResult = append(c.whowasResult, IRCWhowasEntry{
		Nick:     msg.Params[1],
		User:     msg.Params[2],
		Host:     msg.Params[3],
		Realname: msg.Trailing(),
	})
	c.whowasMu.Unlock()
}

func (c *IRCCore) handleWhowasEnd(msg *ircMsg) {
	c.whowasMu.Lock()
	if c.whowasDone != nil {
		select {
		case <-c.whowasDone:
		default:
			close(c.whowasDone)
		}
	}
	c.whowasMu.Unlock()
}

func (c *IRCCore) handleWhoReply(msg *ircMsg) {
	if len(msg.Params) < 7 {
		return
	}
	trailing := msg.Trailing()
	hopcount := 0
	realname := trailing
	if sp := strings.IndexByte(trailing, ' '); sp >= 0 {
		hopcount, _ = strconv.Atoi(trailing[:sp])
		realname = trailing[sp+1:]
	}
	c.whoMu.Lock()
	c.whoResult = append(c.whoResult, IRCWhoEntry{
		Channel:  msg.Params[1],
		User:     msg.Params[2],
		Host:     msg.Params[3],
		Server:   msg.Params[4],
		Nick:     msg.Params[5],
		Flags:    msg.Params[6],
		Hopcount: hopcount,
		Realname: realname,
	})
	c.whoMu.Unlock()
}

func (c *IRCCore) handleWhoEnd(msg *ircMsg) {
	c.whoMu.Lock()
	if c.whoDone != nil {
		select {
		case <-c.whoDone:
		default:
			close(c.whoDone)
		}
	}
	c.whoMu.Unlock()
}

func (c *IRCCore) handleListEntry(msg *ircMsg) {
	if len(msg.Params) < 3 {
		return
	}
	users, _ := strconv.Atoi(msg.Params[2])
	c.listMu.Lock()
	c.listResult = append(c.listResult, IRCListEntry{
		Channel: msg.Params[1],
		Users:   users,
		Topic:   msg.Trailing(),
	})
	c.listMu.Unlock()
}

func (c *IRCCore) handleListEnd(msg *ircMsg) {
	c.listMu.Lock()
	if c.listDone != nil {
		select {
		case <-c.listDone:
		default:
			close(c.listDone)
		}
	}
	c.listMu.Unlock()
}

func (c *IRCCore) handleBanListEntry(msg *ircMsg) {
	if len(msg.Params) < 3 {
		return
	}
	entry := IRCBanEntry{Mask: msg.Params[2]}
	if len(msg.Params) >= 4 {
		entry.SetBy = msg.Params[3]
	}
	if len(msg.Params) >= 5 {
		ts, _ := strconv.ParseInt(msg.Params[4], 10, 64)
		if ts > 0 {
			entry.SetAt = time.Unix(ts, 0)
		}
	}
	c.banMu.Lock()
	c.banResult = append(c.banResult, entry)
	c.banMu.Unlock()
}

func (c *IRCCore) handleBanListEnd(msg *ircMsg) {
	c.banMu.Lock()
	if c.banDone != nil {
		select {
		case <-c.banDone:
		default:
			close(c.banDone)
		}
	}
	c.banMu.Unlock()
}

func (c *IRCCore) handleUserhostReply(msg *ircMsg) {
	reply := msg.Trailing()
	var entries []IRCUserhostEntry
	for _, part := range strings.Fields(reply) {
		eq := strings.IndexByte(part, '=')
		if eq < 0 {
			continue
		}
		nick := part[:eq]
		isOper := strings.HasSuffix(nick, "*")
		if isOper {
			nick = nick[:len(nick)-1]
		}
		rest := part[eq+1:]
		isAway := strings.HasPrefix(rest, "-")
		if strings.HasPrefix(rest, "+") || strings.HasPrefix(rest, "-") {
			rest = rest[1:]
		}
		entries = append(entries, IRCUserhostEntry{
			Nick:     nick,
			IsOper:   isOper,
			IsAway:   isAway,
			Hostname: rest,
		})
	}
	c.userhostMu.Lock()
	c.userhostResult = entries
	if c.userhostDone != nil {
		select {
		case <-c.userhostDone:
		default:
			close(c.userhostDone)
		}
	}
	c.userhostMu.Unlock()
}

func (c *IRCCore) handleIsonReply(msg *ircMsg) {
	nicks := strings.Fields(msg.Trailing())
	c.isonMu.Lock()
	c.isonResult = nicks
	if c.isonDone != nil {
		select {
		case <-c.isonDone:
		default:
			close(c.isonDone)
		}
	}
	c.isonMu.Unlock()
}

func (c *IRCCore) handleAwayReply(msg *ircMsg) {
	if len(msg.Params) < 2 {
		return
	}
	nick := strings.ToLower(msg.Params[1])
	c.whoisCacheMu.Lock()
	if user, ok := c.whoisCache[nick]; ok {
		user.IsOnline = true
	}
	c.whoisCacheMu.Unlock()
}

func (c *IRCCore) handleAwayNotify(msg *ircMsg) {
	nick := msg.Nick()
	awayMsg := msg.Trailing()
	notAway := awayMsg == ""
	c.emitUpdate(Update{
		Type:     UpdateUserStatus,
		UserID:   nick,
		IsOnline: &notAway,
		Platform: "irc",
	})
}

func (c *IRCCore) handleAccountNotify(msg *ircMsg) {
	nick := msg.Nick()
	account := ""
	if len(msg.Params) > 0 {
		account = msg.Params[0]
	}
	if account == "*" {
		account = ""
	}
	c.whoisCacheMu.Lock()
	if user, ok := c.whoisCache[strings.ToLower(nick)]; ok && account != "" {
		user.DisplayName = account
	}
	c.whoisCacheMu.Unlock()
}

func (c *IRCCore) handleInvite(msg *ircMsg) {
	if len(msg.Params) < 2 {
		return
	}
	channel := msg.Params[1]
	nick := msg.Nick()
	c.mu.RLock()
	myNick := c.nick
	c.mu.RUnlock()

	if strings.EqualFold(msg.Params[0], myNick) {
		c.emitUpdate(Update{
			Type:     UpdateNewMessage,
			ChatID:   channel,
			UserID:   nick,
			Platform: "irc",
			Message: &Message{
				ChatID:     channel,
				SenderID:   nick,
				SenderName: nick,
				Text:       fmt.Sprintf("%s invited you to %s", nick, channel),
				Timestamp:  time.Now(),
				Platform:   "irc",
			},
		})
	}
}

func (c *IRCCore) handleChannelURL(msg *ircMsg) {
	if len(msg.Params) < 2 {
		return
	}
	channel := msg.Params[1]
	chanLower := strings.ToLower(channel)
	c.channelsMu.Lock()
	if ch, ok := c.channels[chanLower]; ok {
		ch.URL = msg.Trailing()
	}
	c.channelsMu.Unlock()
}

func (c *IRCCore) handleMonitorOnline(msg *ircMsg) {
	nicks := strings.Split(msg.Trailing(), ",")
	for _, entry := range nicks {
		nick := entry
		if idx := strings.IndexByte(nick, '!'); idx > 0 {
			nick = nick[:idx]
		}
		online := true
		c.emitUpdate(Update{
			Type:     UpdateUserStatus,
			UserID:   nick,
			IsOnline: &online,
			Platform: "irc",
		})
	}
}

func (c *IRCCore) handleMonitorOffline(msg *ircMsg) {
	nicks := strings.Split(msg.Trailing(), ",")
	for _, nick := range nicks {
		offline := false
		c.emitUpdate(Update{
			Type:     UpdateUserStatus,
			UserID:   strings.TrimSpace(nick),
			IsOnline: &offline,
			Platform: "irc",
		})
	}
}

func (c *IRCCore) handleTagMsg(msg *ircMsg) {
	nick := msg.Nick()
	if nick == "" {
		return
	}

	// Check for typing indicator (+typing tag)
	if _, ok := msg.Tags["+typing"]; ok {
		target := ""
		if len(msg.Params) > 0 {
			target = msg.Params[0]
		}
		c.mu.RLock()
		myNick := c.nick
		c.mu.RUnlock()

		chatID := target
		if strings.EqualFold(target, myNick) {
			chatID = nick
		}

		c.emitUpdate(Update{
			Type:     UpdateTyping,
			ChatID:   chatID,
			UserID:   nick,
			Platform: "irc",
		})
	}

	// Check for reaction (+react tag)
	if reaction, ok := msg.Tags["+react"]; ok {
		target := ""
		if len(msg.Params) > 0 {
			target = msg.Params[0]
		}
		c.mu.RLock()
		myNick := c.nick
		c.mu.RUnlock()

		chatID := target
		if strings.EqualFold(target, myNick) {
			chatID = nick
		}

		replyTo := msg.Tags["+reply"]
		c.msgCounter++
		reactMsg := &Message{
			ID:         fmt.Sprintf("%d", c.msgCounter),
			ChatID:     chatID,
			SenderID:   nick,
			SenderName: nick,
			Text:       fmt.Sprintf("[React: %s to %s]", reaction, replyTo),
			Timestamp:  time.Now(),
			Platform:   "irc",
		}
		c.bufferMessage(chatID, reactMsg)
		c.emitUpdate(Update{
			Type:     UpdateNewMessage,
			ChatID:   chatID,
			Message:  reactMsg,
			Platform: "irc",
		})
	}
}

func (c *IRCCore) handleWatchEvent(msg *ircMsg, online bool) {
	if len(msg.Params) < 2 {
		return
	}
	nick := msg.Params[1]
	c.emitUpdate(Update{
		Type:     UpdateUserStatus,
		UserID:   nick,
		IsOnline: &online,
		Platform: "irc",
	})
}

func (c *IRCCore) handleErrorNumeric(msg *ircMsg) {
	text := msg.Trailing()
	if text == "" && len(msg.Params) > 1 {
		text = strings.Join(msg.Params[1:], " ")
	}
	c.msgCounter++
	m := &Message{
		ID:         fmt.Sprintf("%d", c.msgCounter),
		ChatID:     "*server*",
		SenderID:   msg.Prefix,
		SenderName: "Server",
		Text:       fmt.Sprintf("[%s] %s", msg.Command, text),
		Timestamp:  time.Now(),
		Platform:   "irc",
	}
	c.bufferMessage("*server*", m)
}

func (c *IRCCore) handleServerError(msg *ircMsg) {
	text := msg.Trailing()
	c.msgCounter++
	m := &Message{
		ID:         fmt.Sprintf("%d", c.msgCounter),
		ChatID:     "*server*",
		SenderID:   "server",
		SenderName: "Server",
		Text:       "[ERROR] " + text,
		Timestamp:  time.Now(),
		Platform:   "irc",
	}
	c.bufferMessage("*server*", m)
}

// ===========================================================================
// Exported IRC protocol methods (beyond Core interface)
// ===========================================================================

// --- Connection & Identity ---

// GetNick returns the current nickname.
func (c *IRCCore) GetNick() string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.nick
}

// ChangeNick changes the client's nickname.
func (c *IRCCore) ChangeNick(newNick string) {
	c.sendRaw("NICK " + newNick)
}

// SetName changes the client's realname (IRCv3 SETNAME).
func (c *IRCCore) SetName(realname string) {
	c.sendRaw("SETNAME :" + realname)
}

// Away sets the away message. Empty string clears away status.
func (c *IRCCore) Away(message string) {
	c.awayMu.Lock()
	c.awayMsg = message
	c.awayMu.Unlock()
	if message == "" {
		c.sendRaw("AWAY")
	} else {
		c.sendRaw("AWAY :" + message)
	}
}

// GetAway returns the current away message (empty if not away).
func (c *IRCCore) GetAway() string {
	c.awayMu.RLock()
	defer c.awayMu.RUnlock()
	return c.awayMsg
}

// Oper authenticates as an IRC operator.
func (c *IRCCore) Oper(name, password string) {
	c.sendRaw("OPER " + name + " " + password)
}

// QuitMessage disconnects with a custom quit message.
func (c *IRCCore) QuitMessage(message string) {
	if message == "" {
		message = "Goodbye"
	}
	c.sendRaw("QUIT :" + message)
}

// SendRawCommand sends a raw IRC command.
func (c *IRCCore) SendRawCommand(line string) {
	c.sendRaw(line)
}

// --- Channel Operations ---

// JoinKey joins a channel with a key (password).
func (c *IRCCore) JoinKey(channel, key string) {
	c.sendRaw("JOIN " + channel + " " + key)
}

// JoinMultiple joins multiple channels at once.
func (c *IRCCore) JoinMultiple(channels []string, keys []string) {
	chanStr := strings.Join(channels, ",")
	if len(keys) > 0 {
		c.sendRaw("JOIN " + chanStr + " " + strings.Join(keys, ","))
	} else {
		c.sendRaw("JOIN " + chanStr)
	}
}

// PartMessage leaves a channel with a reason.
func (c *IRCCore) PartMessage(channel, reason string) {
	if reason != "" {
		c.sendRaw("PART " + channel + " :" + reason)
	} else {
		c.sendRaw("PART " + channel)
	}
}

// PartMultiple leaves multiple channels at once.
func (c *IRCCore) PartMultiple(channels []string, reason string) {
	chanStr := strings.Join(channels, ",")
	if reason != "" {
		c.sendRaw("PART " + chanStr + " :" + reason)
	} else {
		c.sendRaw("PART " + chanStr)
	}
}

// GetChannelTopic returns the cached topic and who set it.
func (c *IRCCore) GetChannelTopic(channel string) (string, string, error) {
	chanLower := strings.ToLower(channel)
	c.channelsMu.RLock()
	ch, ok := c.channels[chanLower]
	c.channelsMu.RUnlock()
	if !ok {
		return "", "", fmt.Errorf("%w: not in channel %s", ErrNotFound, channel)
	}
	return ch.Topic, ch.TopicBy, nil
}

// SetMode sets modes on a channel or user.
func (c *IRCCore) SetMode(target, modes string, params ...string) {
	cmd := "MODE " + target + " " + modes
	if len(params) > 0 {
		cmd += " " + strings.Join(params, " ")
	}
	c.sendRaw(cmd)
}

// Knock requests an invitation to a channel.
func (c *IRCCore) Knock(channel string) {
	c.sendRaw("KNOCK " + channel)
}

// RequestNames explicitly requests the NAMES list for a channel.
func (c *IRCCore) RequestNames(channel string) {
	c.sendRaw("NAMES " + channel)
}

// LeaveAllChannels sends JOIN 0 (leaves all channels per RFC 2812).
func (c *IRCCore) LeaveAllChannels() {
	c.sendRaw("JOIN 0")
}

// --- Messaging ---

// SendNotice sends a NOTICE to a target.
func (c *IRCCore) SendNotice(target, text string) {
	c.sendRaw("NOTICE " + target + " :" + text)
}

// SendAction sends a CTCP ACTION (/me) to a target.
func (c *IRCCore) SendAction(target, text string) {
	c.sendRaw(fmt.Sprintf("PRIVMSG %s :\x01ACTION %s\x01", target, text))
	c.mu.RLock()
	myNick := c.nick
	c.mu.RUnlock()
	c.msgCounter++
	m := &Message{
		ID:         fmt.Sprintf("%d", c.msgCounter),
		ChatID:     target,
		SenderID:   myNick,
		SenderName: myNick,
		Text:       "* " + myNick + " " + text,
		Timestamp:  time.Now(),
		Platform:   "irc",
	}
	c.bufferMessage(target, m)
}

// SendCTCP sends a CTCP request to a target.
func (c *IRCCore) SendCTCP(target, command, params string) {
	if params != "" {
		c.sendRaw(fmt.Sprintf("PRIVMSG %s :\x01%s %s\x01", target, command, params))
	} else {
		c.sendRaw(fmt.Sprintf("PRIVMSG %s :\x01%s\x01", target, command))
	}
}

// SendCTCPReply sends a CTCP reply via NOTICE.
func (c *IRCCore) SendCTCPReply(target, command, params string) {
	if params != "" {
		c.sendRaw(fmt.Sprintf("NOTICE %s :\x01%s %s\x01", target, command, params))
	} else {
		c.sendRaw(fmt.Sprintf("NOTICE %s :\x01%s\x01", target, command))
	}
}

// Wallops sends a WALLOPS message (requires IRC operator).
func (c *IRCCore) Wallops(message string) {
	c.sendRaw("WALLOPS :" + message)
}

// --- User Queries ---

// Who sends a WHO query and returns results.
func (c *IRCCore) Who(mask string) ([]IRCWhoEntry, error) {
	c.whoMu.Lock()
	c.whoResult = nil
	c.whoDone = make(chan struct{})
	done := c.whoDone
	c.whoMu.Unlock()

	c.sendRaw("WHO " + mask)

	select {
	case <-done:
	case <-time.After(15 * time.Second):
		return nil, fmt.Errorf("%w: WHO timeout", ErrNetwork)
	case <-c.ctx.Done():
		return nil, c.ctx.Err()
	}

	c.whoMu.Lock()
	result := make([]IRCWhoEntry, len(c.whoResult))
	copy(result, c.whoResult)
	c.whoMu.Unlock()
	return result, nil
}

// RequestWhois sends a WHOIS request (result via GetProfile or WHOIS cache).
func (c *IRCCore) RequestWhois(nick string) {
	c.sendRaw("WHOIS " + nick)
}

// Whowas queries information about a disconnected user.
func (c *IRCCore) Whowas(nick string, count int) ([]IRCWhowasEntry, error) {
	c.whowasMu.Lock()
	c.whowasResult = nil
	c.whowasDone = make(chan struct{})
	done := c.whowasDone
	c.whowasMu.Unlock()

	if count > 0 {
		c.sendRaw(fmt.Sprintf("WHOWAS %s %d", nick, count))
	} else {
		c.sendRaw("WHOWAS " + nick)
	}

	select {
	case <-done:
	case <-time.After(10 * time.Second):
		return nil, fmt.Errorf("%w: WHOWAS timeout", ErrNetwork)
	case <-c.ctx.Done():
		return nil, c.ctx.Err()
	}

	c.whowasMu.Lock()
	result := make([]IRCWhowasEntry, len(c.whowasResult))
	copy(result, c.whowasResult)
	c.whowasMu.Unlock()
	return result, nil
}

// Userhost returns host information for given nicks.
func (c *IRCCore) Userhost(nicks ...string) ([]IRCUserhostEntry, error) {
	c.userhostMu.Lock()
	c.userhostResult = nil
	c.userhostDone = make(chan struct{})
	done := c.userhostDone
	c.userhostMu.Unlock()

	c.sendRaw("USERHOST " + strings.Join(nicks, " "))

	select {
	case <-done:
	case <-time.After(10 * time.Second):
		return nil, fmt.Errorf("%w: USERHOST timeout", ErrNetwork)
	case <-c.ctx.Done():
		return nil, c.ctx.Err()
	}

	c.userhostMu.Lock()
	result := make([]IRCUserhostEntry, len(c.userhostResult))
	copy(result, c.userhostResult)
	c.userhostMu.Unlock()
	return result, nil
}

// Ison checks if given nicks are online.
func (c *IRCCore) Ison(nicks ...string) ([]string, error) {
	c.isonMu.Lock()
	c.isonResult = nil
	c.isonDone = make(chan struct{})
	done := c.isonDone
	c.isonMu.Unlock()

	c.sendRaw("ISON " + strings.Join(nicks, " "))

	select {
	case <-done:
	case <-time.After(10 * time.Second):
		return nil, fmt.Errorf("%w: ISON timeout", ErrNetwork)
	case <-c.ctx.Done():
		return nil, c.ctx.Err()
	}

	c.isonMu.Lock()
	result := make([]string, len(c.isonResult))
	copy(result, c.isonResult)
	c.isonMu.Unlock()
	return result, nil
}

// --- Server Queries ---

// List queries the server for available channels.
func (c *IRCCore) List(filter string) ([]IRCListEntry, error) {
	c.listMu.Lock()
	c.listResult = nil
	c.listDone = make(chan struct{})
	done := c.listDone
	c.listMu.Unlock()

	if filter != "" {
		c.sendRaw("LIST " + filter)
	} else {
		c.sendRaw("LIST")
	}

	select {
	case <-done:
	case <-time.After(30 * time.Second):
		return nil, fmt.Errorf("%w: LIST timeout", ErrNetwork)
	case <-c.ctx.Done():
		return nil, c.ctx.Err()
	}

	c.listMu.Lock()
	result := make([]IRCListEntry, len(c.listResult))
	copy(result, c.listResult)
	c.listMu.Unlock()
	return result, nil
}

// RequestMOTD requests the server's Message of the Day.
func (c *IRCCore) RequestMOTD() {
	c.sendRaw("MOTD")
}

// GetMOTD returns the cached MOTD lines.
func (c *IRCCore) GetMOTD() []string {
	c.motdMu.RLock()
	defer c.motdMu.RUnlock()
	result := make([]string, len(c.motd))
	copy(result, c.motd)
	return result
}

// RequestVersion queries the server version.
func (c *IRCCore) RequestVersion() {
	c.sendRaw("VERSION")
}

// RequestTime queries the server time.
func (c *IRCCore) RequestTime() {
	c.sendRaw("TIME")
}

// RequestAdmin queries the server admin info.
func (c *IRCCore) RequestAdmin() {
	c.sendRaw("ADMIN")
}

// RequestInfo queries the server info.
func (c *IRCCore) RequestInfo() {
	c.sendRaw("INFO")
}

// RequestLusers queries the network user statistics.
func (c *IRCCore) RequestLusers() {
	c.sendRaw("LUSERS")
}

// RequestStats queries server statistics.
func (c *IRCCore) RequestStats(query string) {
	c.sendRaw("STATS " + query)
}

// GetServerInfo returns the cached ISUPPORT/server information.
func (c *IRCCore) GetServerInfo() IRCServerInfo {
	c.serverInfoMu.RLock()
	defer c.serverInfoMu.RUnlock()
	info := c.serverInfo
	raw := make(map[string]string, len(c.serverInfo.Raw))
	for k, v := range c.serverInfo.Raw {
		raw[k] = v
	}
	info.Raw = raw
	return info
}

// HasCapability checks if an IRCv3 capability is enabled.
func (c *IRCCore) HasCapability(cap string) bool {
	c.enabledCapsMu.RLock()
	defer c.enabledCapsMu.RUnlock()
	return c.enabledCaps[cap]
}

// --- Ban List ---

// GetBanList retrieves the ban list for a channel.
func (c *IRCCore) GetBanList(channel string) ([]IRCBanEntry, error) {
	c.banMu.Lock()
	c.banResult = nil
	c.banDone = make(chan struct{})
	done := c.banDone
	c.banMu.Unlock()

	c.sendRaw("MODE " + channel + " +b")

	select {
	case <-done:
	case <-time.After(10 * time.Second):
		return nil, fmt.Errorf("%w: ban list timeout", ErrNetwork)
	case <-c.ctx.Done():
		return nil, c.ctx.Err()
	}

	c.banMu.Lock()
	result := make([]IRCBanEntry, len(c.banResult))
	copy(result, c.banResult)
	c.banMu.Unlock()
	return result, nil
}

// --- MONITOR (IRCv3) ---

// MonitorAdd adds nicks to the monitor list.
func (c *IRCCore) MonitorAdd(nicks ...string) {
	c.sendRaw("MONITOR + " + strings.Join(nicks, ","))
	c.monitoredMu.Lock()
	for _, n := range nicks {
		c.monitored[strings.ToLower(n)] = true
	}
	c.monitoredMu.Unlock()
}

// MonitorRemove removes nicks from the monitor list.
func (c *IRCCore) MonitorRemove(nicks ...string) {
	c.sendRaw("MONITOR - " + strings.Join(nicks, ","))
	c.monitoredMu.Lock()
	for _, n := range nicks {
		delete(c.monitored, strings.ToLower(n))
	}
	c.monitoredMu.Unlock()
}

// MonitorClear clears the entire monitor list.
func (c *IRCCore) MonitorClear() {
	c.sendRaw("MONITOR C")
	c.monitoredMu.Lock()
	c.monitored = make(map[string]bool)
	c.monitoredMu.Unlock()
}

// MonitorList requests the current monitor list from the server.
func (c *IRCCore) MonitorList() {
	c.sendRaw("MONITOR L")
}

// MonitorStatus requests the online/offline status of monitored nicks.
func (c *IRCCore) MonitorStatus() {
	c.sendRaw("MONITOR S")
}

// GetMonitored returns the set of locally tracked monitored nicks.
func (c *IRCCore) GetMonitored() []string {
	c.monitoredMu.RLock()
	defer c.monitoredMu.RUnlock()
	result := make([]string, 0, len(c.monitored))
	for nick := range c.monitored {
		result = append(result, nick)
	}
	sort.Strings(result)
	return result
}

// --- NickServ ---

// NickServIdentify authenticates with NickServ.
func (c *IRCCore) NickServIdentify(password string) {
	c.sendRaw("PRIVMSG NickServ :IDENTIFY " + password)
}

// NickServRegister registers a nickname with NickServ.
func (c *IRCCore) NickServRegister(password, email string) {
	if email != "" {
		c.sendRaw("PRIVMSG NickServ :REGISTER " + password + " " + email)
	} else {
		c.sendRaw("PRIVMSG NickServ :REGISTER " + password)
	}
}

// NickServGhost kills a ghost session.
func (c *IRCCore) NickServGhost(nick, password string) {
	c.sendRaw("PRIVMSG NickServ :GHOST " + nick + " " + password)
}

// NickServRelease releases a held nickname.
func (c *IRCCore) NickServRelease(nick, password string) {
	c.sendRaw("PRIVMSG NickServ :RELEASE " + nick + " " + password)
}

// NickServInfo queries NickServ info for a nick.
func (c *IRCCore) NickServInfo(nick string) {
	c.sendRaw("PRIVMSG NickServ :INFO " + nick)
}

// NickServLogout logs out of NickServ.
func (c *IRCCore) NickServLogout() {
	c.sendRaw("PRIVMSG NickServ :LOGOUT")
}

// NickServSetPassword changes the NickServ password.
func (c *IRCCore) NickServSetPassword(newPassword string) {
	c.sendRaw("PRIVMSG NickServ :SET PASSWORD " + newPassword)
}

// --- ChanServ ---

// ChanServOp gives operator status via ChanServ.
func (c *IRCCore) ChanServOp(channel, nick string) {
	c.sendRaw("PRIVMSG ChanServ :OP " + channel + " " + nick)
}

// ChanServDeop removes operator status via ChanServ.
func (c *IRCCore) ChanServDeop(channel, nick string) {
	c.sendRaw("PRIVMSG ChanServ :DEOP " + channel + " " + nick)
}

// ChanServVoice gives voice status via ChanServ.
func (c *IRCCore) ChanServVoice(channel, nick string) {
	c.sendRaw("PRIVMSG ChanServ :VOICE " + channel + " " + nick)
}

// ChanServDevoice removes voice status via ChanServ.
func (c *IRCCore) ChanServDevoice(channel, nick string) {
	c.sendRaw("PRIVMSG ChanServ :DEVOICE " + channel + " " + nick)
}

// ChanServHalfop gives half-operator status via ChanServ.
func (c *IRCCore) ChanServHalfop(channel, nick string) {
	c.sendRaw("PRIVMSG ChanServ :HALFOP " + channel + " " + nick)
}

// ChanServDehalfop removes half-operator status via ChanServ.
func (c *IRCCore) ChanServDehalfop(channel, nick string) {
	c.sendRaw("PRIVMSG ChanServ :DEHALFOP " + channel + " " + nick)
}

// ChanServRegister registers a channel with ChanServ.
func (c *IRCCore) ChanServRegister(channel, password, description string) {
	c.sendRaw("PRIVMSG ChanServ :REGISTER " + channel + " " + password + " " + description)
}

// ChanServDrop drops a registered channel.
func (c *IRCCore) ChanServDrop(channel string) {
	c.sendRaw("PRIVMSG ChanServ :DROP " + channel)
}

// ChanServInvite requests ChanServ to invite you.
func (c *IRCCore) ChanServInvite(channel string) {
	c.sendRaw("PRIVMSG ChanServ :INVITE " + channel)
}

// ChanServAkick manages the auto-kick list.
func (c *IRCCore) ChanServAkick(channel, action, mask, reason string) {
	cmd := "PRIVMSG ChanServ :AKICK " + channel + " " + action + " " + mask
	if reason != "" {
		cmd += " " + reason
	}
	c.sendRaw(cmd)
}

// ChanServInfo queries ChanServ channel info.
func (c *IRCCore) ChanServInfo(channel string) {
	c.sendRaw("PRIVMSG ChanServ :INFO " + channel)
}

// --- MemoServ ---

// MemoServSend sends a memo to a user or channel.
func (c *IRCCore) MemoServSend(target, text string) {
	c.sendRaw("PRIVMSG MemoServ :SEND " + target + " " + text)
}

// MemoServRead reads memos.
func (c *IRCCore) MemoServRead(which string) {
	if which == "" {
		which = "NEW"
	}
	c.sendRaw("PRIVMSG MemoServ :READ " + which)
}

// MemoServList lists memos.
func (c *IRCCore) MemoServList() {
	c.sendRaw("PRIVMSG MemoServ :LIST")
}

// MemoServDelete deletes a memo.
func (c *IRCCore) MemoServDelete(which string) {
	c.sendRaw("PRIVMSG MemoServ :DEL " + which)
}

// --- Admin Operations ---

// SetVoice gives/removes voice (+v/-v) on a user in a channel.
func (c *IRCCore) SetVoice(channel, nick string, voice bool) {
	if voice {
		c.sendRaw("MODE " + channel + " +v " + nick)
	} else {
		c.sendRaw("MODE " + channel + " -v " + nick)
	}
}

// SetHalfop gives/removes halfop (+h/-h) on a user in a channel.
func (c *IRCCore) SetHalfop(channel, nick string, halfop bool) {
	if halfop {
		c.sendRaw("MODE " + channel + " +h " + nick)
	} else {
		c.sendRaw("MODE " + channel + " -h " + nick)
	}
}

// KickWithReason kicks a user with a reason message.
func (c *IRCCore) KickWithReason(channel, nick, reason string) {
	if reason != "" {
		c.sendRaw("KICK " + channel + " " + nick + " :" + reason)
	} else {
		c.sendRaw("KICK " + channel + " " + nick)
	}
}

// BanMask sets a ban by hostmask.
func (c *IRCCore) BanMask(channel, mask string) {
	c.sendRaw("MODE " + channel + " +b " + mask)
}

// UnbanMask removes a ban by hostmask.
func (c *IRCCore) UnbanMask(channel, mask string) {
	c.sendRaw("MODE " + channel + " -b " + mask)
}

// SetChannelKey sets or removes a channel key (password).
func (c *IRCCore) SetChannelKey(channel, key string) {
	if key != "" {
		c.sendRaw("MODE " + channel + " +k " + key)
	} else {
		c.sendRaw("MODE " + channel + " -k *")
	}
}

// SetChannelLimit sets or removes a user limit on a channel.
func (c *IRCCore) SetChannelLimit(channel string, limit int) {
	if limit > 0 {
		c.sendRaw(fmt.Sprintf("MODE %s +l %d", channel, limit))
	} else {
		c.sendRaw("MODE " + channel + " -l")
	}
}

// SetChannelModerated sets or clears moderated mode (+m/-m).
func (c *IRCCore) SetChannelModerated(channel string, moderated bool) {
	if moderated {
		c.sendRaw("MODE " + channel + " +m")
	} else {
		c.sendRaw("MODE " + channel + " -m")
	}
}

// SetChannelInviteOnly sets or clears invite-only mode (+i/-i).
func (c *IRCCore) SetChannelInviteOnly(channel string, inviteOnly bool) {
	if inviteOnly {
		c.sendRaw("MODE " + channel + " +i")
	} else {
		c.sendRaw("MODE " + channel + " -i")
	}
}

// SetChannelNoExternal sets or clears no-external-messages mode (+n/-n).
func (c *IRCCore) SetChannelNoExternal(channel string, noExternal bool) {
	if noExternal {
		c.sendRaw("MODE " + channel + " +n")
	} else {
		c.sendRaw("MODE " + channel + " -n")
	}
}

// SetChannelSecret sets or clears secret mode (+s/-s).
func (c *IRCCore) SetChannelSecret(channel string, secret bool) {
	if secret {
		c.sendRaw("MODE " + channel + " +s")
	} else {
		c.sendRaw("MODE " + channel + " -s")
	}
}

// SetChannelTopicLock sets or clears topic-lock mode (+t/-t).
func (c *IRCCore) SetChannelTopicLock(channel string, locked bool) {
	if locked {
		c.sendRaw("MODE " + channel + " +t")
	} else {
		c.sendRaw("MODE " + channel + " -t")
	}
}

// --- Ban exceptions & invite exceptions ---

// SetBanExcept sets or removes a ban exception (+e/-e).
func (c *IRCCore) SetBanExcept(channel, mask string, add bool) {
	if add {
		c.sendRaw("MODE " + channel + " +e " + mask)
	} else {
		c.sendRaw("MODE " + channel + " -e " + mask)
	}
}

// GetExceptList retrieves the ban exception list (+e) for a channel.
func (c *IRCCore) GetExceptList(channel string) ([]IRCBanEntry, error) {
	c.banMu.Lock()
	c.banResult = nil
	c.banDone = make(chan struct{})
	c.banMu.Unlock()

	c.sendRaw("MODE " + channel + " +e")

	select {
	case <-c.banDone:
	case <-time.After(15 * time.Second):
		return nil, fmt.Errorf("except list timeout")
	}

	c.banMu.Lock()
	result := make([]IRCBanEntry, len(c.banResult))
	copy(result, c.banResult)
	c.banMu.Unlock()
	return result, nil
}

// SetInviteExcept sets or removes an invite exception (+I/-I).
func (c *IRCCore) SetInviteExcept(channel, mask string, add bool) {
	if add {
		c.sendRaw("MODE " + channel + " +I " + mask)
	} else {
		c.sendRaw("MODE " + channel + " -I " + mask)
	}
}

// GetInviteExceptList retrieves the invite exception list (+I) for a channel.
func (c *IRCCore) GetInviteExceptList(channel string) ([]IRCBanEntry, error) {
	c.banMu.Lock()
	c.banResult = nil
	c.banDone = make(chan struct{})
	c.banMu.Unlock()

	c.sendRaw("MODE " + channel + " +I")

	select {
	case <-c.banDone:
	case <-time.After(15 * time.Second):
		return nil, fmt.Errorf("invite except list timeout")
	}

	c.banMu.Lock()
	result := make([]IRCBanEntry, len(c.banResult))
	copy(result, c.banResult)
	c.banMu.Unlock()
	return result, nil
}

// --- User modes ---

// SetUserMode sets or queries the user's own modes (+i, +w, etc.).
func (c *IRCCore) SetUserMode(modes string) {
	c.mu.RLock()
	nick := c.nick
	c.mu.RUnlock()
	c.sendRaw("MODE " + nick + " " + modes)
}

// GetUserMode queries the user's current modes.
func (c *IRCCore) GetUserMode() {
	c.mu.RLock()
	nick := c.nick
	c.mu.RUnlock()
	c.sendRaw("MODE " + nick)
}

// --- Server topology ---

// RequestLinks queries the server link structure.
func (c *IRCCore) RequestLinks(mask string) {
	if mask != "" {
		c.sendRaw("LINKS " + mask)
	} else {
		c.sendRaw("LINKS")
	}
}

// RequestTrace traces the route to a server or user.
func (c *IRCCore) RequestTrace(target string) {
	if target != "" {
		c.sendRaw("TRACE " + target)
	} else {
		c.sendRaw("TRACE")
	}
}

// RequestMap requests the server link map (non-RFC, widely supported).
func (c *IRCCore) RequestMap() {
	c.sendRaw("MAP")
}

// RequestHelp requests help from the server.
func (c *IRCCore) RequestHelp(topic string) {
	if topic != "" {
		c.sendRaw("HELP " + topic)
	} else {
		c.sendRaw("HELP")
	}
}

// RequestRules requests the server rules (non-RFC, widely supported).
func (c *IRCCore) RequestRules() {
	c.sendRaw("RULES")
}

// --- Service queries ---

// ServList queries the list of services connected to the network.
func (c *IRCCore) ServList(mask, svcType string) {
	cmd := "SERVLIST"
	if mask != "" {
		cmd += " " + mask
		if svcType != "" {
			cmd += " " + svcType
		}
	}
	c.sendRaw(cmd)
}

// SQuery sends a message to a network service.
func (c *IRCCore) SQuery(service, text string) {
	c.sendRaw("SQUERY " + service + " :" + text)
}

// --- DCC ---

// IRCDCCOffer represents an incoming DCC request.
type IRCDCCOffer struct {
	Type     string // "SEND", "CHAT"
	Filename string
	IP       string
	Port     int
	Size     int64
	From     string
}

// DCCSend sends a DCC SEND request to a user.
func (c *IRCCore) DCCSend(nick, filename string, port int, size int64) {
	c.sendRaw(fmt.Sprintf("PRIVMSG %s :\x01DCC SEND %s 0 %d %d\x01", nick, filename, port, size))
}

// DCCChat sends a DCC CHAT request to a user.
func (c *IRCCore) DCCChat(nick string, port int) {
	c.sendRaw(fmt.Sprintf("PRIVMSG %s :\x01DCC CHAT chat 0 %d\x01", nick, port))
}

// DCCResume sends a DCC RESUME request to continue an interrupted transfer.
func (c *IRCCore) DCCResume(nick, filename string, port int, position int64) {
	c.sendRaw(fmt.Sprintf("PRIVMSG %s :\x01DCC RESUME %s %d %d\x01", nick, filename, port, position))
}

// DCCAccept accepts a DCC RESUME request.
func (c *IRCCore) DCCAccept(nick, filename string, port int, position int64) {
	c.sendRaw(fmt.Sprintf("PRIVMSG %s :\x01DCC ACCEPT %s %d %d\x01", nick, filename, port, position))
}

// --- TAGMSG (IRCv3) ---

// SendTagMsg sends a TAGMSG (message-tags only, no text content).
// Used for typing indicators, reactions, etc.
func (c *IRCCore) SendTagMsg(target string, tags map[string]string) {
	tagStr := ""
	for k, v := range tags {
		if tagStr != "" {
			tagStr += ";"
		}
		if v != "" {
			tagStr += k + "=" + v
		} else {
			tagStr += k
		}
	}
	c.sendRaw("@" + tagStr + " TAGMSG " + target)
}

// SendTypingIndicator sends a typing indicator via TAGMSG (IRCv3 draft/typing).
func (c *IRCCore) SendTypingIndicator(target string, typing bool) {
	status := "active"
	if !typing {
		status = "done"
	}
	c.SendTagMsg(target, map[string]string{"+typing": status})
}

// --- CHATHISTORY (IRCv3 draft) ---

// ChatHistoryLatest requests the latest N messages for a target.
func (c *IRCCore) ChatHistoryLatest(target string, limit int) {
	c.sendRaw(fmt.Sprintf("CHATHISTORY LATEST %s * %d", target, limit))
}

// ChatHistoryBefore requests messages before a given msgid or timestamp.
func (c *IRCCore) ChatHistoryBefore(target, reference string, limit int) {
	c.sendRaw(fmt.Sprintf("CHATHISTORY BEFORE %s %s %d", target, reference, limit))
}

// ChatHistoryAfter requests messages after a given msgid or timestamp.
func (c *IRCCore) ChatHistoryAfter(target, reference string, limit int) {
	c.sendRaw(fmt.Sprintf("CHATHISTORY AFTER %s %s %d", target, reference, limit))
}

// ChatHistoryAround requests messages around a given msgid or timestamp.
func (c *IRCCore) ChatHistoryAround(target, reference string, limit int) {
	c.sendRaw(fmt.Sprintf("CHATHISTORY AROUND %s %s %d", target, reference, limit))
}

// ChatHistoryTargets requests a list of targets with recent messages.
func (c *IRCCore) ChatHistoryTargets(fromTime, toTime string, limit int) {
	c.sendRaw(fmt.Sprintf("CHATHISTORY TARGETS %s %s %d", fromTime, toTime, limit))
}

// --- MARKREAD (IRCv3 draft) ---

// MarkRead sets or queries the read marker for a target.
func (c *IRCCore) MarkRead(target, msgid string) {
	if msgid != "" {
		c.sendRaw("MARKREAD " + target + " " + msgid)
	} else {
		c.sendRaw("MARKREAD " + target)
	}
}

// --- REDACT (IRCv3 draft) ---

// Redact redacts/deletes a previously sent message by msgid.
func (c *IRCCore) Redact(target, msgid, reason string) {
	if reason != "" {
		c.sendRaw("REDACT " + target + " " + msgid + " :" + reason)
	} else {
		c.sendRaw("REDACT " + target + " " + msgid)
	}
}

// --- REGISTER/VERIFY (IRCv3 draft account-registration) ---

// Register initiates in-band account registration.
func (c *IRCCore) Register(account, email, password string) {
	if email != "" {
		c.sendRaw("REGISTER " + account + " " + email + " " + password)
	} else {
		c.sendRaw("REGISTER " + account + " * " + password)
	}
}

// Verify confirms account registration with a verification code.
func (c *IRCCore) Verify(account, code string) {
	c.sendRaw("VERIFY " + account + " " + code)
}

// --- WHOX (extended WHO) ---

// WhoX sends an extended WHO query with custom fields.
// Fields is a string of field characters (e.g. "nuhsra" for nick/user/host/server/realname/account).
func (c *IRCCore) WhoX(mask, fields string) {
	c.sendRaw("WHO " + mask + " %" + fields)
}

// --- SILENCE (server-side ignore) ---

// Silence adds or removes an entry from the server-side ignore list.
// Use "+mask" to add, "-mask" to remove, empty to query.
func (c *IRCCore) Silence(mask string) {
	if mask != "" {
		c.sendRaw("SILENCE " + mask)
	} else {
		c.sendRaw("SILENCE")
	}
}

// --- WATCH (server-side friend list) ---

// WatchAdd adds nicks to the server-side watch list.
func (c *IRCCore) WatchAdd(nicks ...string) {
	for _, nick := range nicks {
		c.sendRaw("WATCH +" + nick)
	}
}

// WatchRemove removes nicks from the server-side watch list.
func (c *IRCCore) WatchRemove(nicks ...string) {
	for _, nick := range nicks {
		c.sendRaw("WATCH -" + nick)
	}
}

// WatchClear clears the watch list.
func (c *IRCCore) WatchClear() {
	c.sendRaw("WATCH C")
}

// WatchList lists the watch list.
func (c *IRCCore) WatchList() {
	c.sendRaw("WATCH L")
}

// WatchStatus requests the status of watched nicks.
func (c *IRCCore) WatchStatus() {
	c.sendRaw("WATCH S")
}

// --- Connection password ---

// SendPass sends a connection password (must be called before NICK/USER).
// For normal connections, this is handled automatically via AuthConfig Extra["password"].
// This method is exposed for manual/advanced use.
func (c *IRCCore) SendPass(password string) {
	c.sendRaw("PASS " + password)
}

// --- STATUSMSG ---

// SendStatusMsg sends a PRIVMSG to only users with a specific prefix in a channel.
// E.g. SendStatusMsg("@", "#channel", "ops only message") sends only to ops.
func (c *IRCCore) SendStatusMsg(prefix, channel, text string) {
	c.sendRaw("PRIVMSG " + prefix + channel + " :" + text)
}

// SendStatusNotice sends a NOTICE to only users with a specific prefix in a channel.
func (c *IRCCore) SendStatusNotice(prefix, channel, text string) {
	c.sendRaw("NOTICE " + prefix + channel + " :" + text)
}

// --- USERS command ---

// RequestUsers requests the list of users logged into the server host.
func (c *IRCCore) RequestUsers(target string) {
	if target != "" {
		c.sendRaw("USERS " + target)
	} else {
		c.sendRaw("USERS")
	}
}

// --- SUMMON command ---

// Summon invites a user on the server host to join IRC.
func (c *IRCCore) Summon(user, target, channel string) {
	cmd := "SUMMON " + user
	if target != "" {
		cmd += " " + target
	}
	if channel != "" {
		cmd += " " + channel
	}
	c.sendRaw(cmd)
}

// --- USERIP command (non-RFC) ---

// UserIP queries the IP address of up to 5 users.
func (c *IRCCore) UserIP(nicks ...string) {
	if len(nicks) > 5 {
		nicks = nicks[:5]
	}
	c.sendRaw("USERIP " + strings.Join(nicks, " "))
}

// --- CPRIVMSG / CNOTICE (channel bypass) ---

// CPrivmsg sends a PRIVMSG bypassing channel flood limits (for voiced/ops).
func (c *IRCCore) CPrivmsg(nick, channel, text string) {
	c.sendRaw("CPRIVMSG " + nick + " " + channel + " :" + text)
}

// CNotice sends a NOTICE bypassing channel flood limits (for voiced/ops).
func (c *IRCCore) CNotice(nick, channel, text string) {
	c.sendRaw("CNOTICE " + nick + " " + channel + " :" + text)
}

// --- Additional NickServ commands ---

// NickServGroup links the current nick to an existing account.
func (c *IRCCore) NickServGroup(target, password string) {
	if target != "" {
		c.sendRaw("PRIVMSG NickServ :GROUP " + target + " " + password)
	} else {
		c.sendRaw("PRIVMSG NickServ :GROUP")
	}
}

// NickServUngroup unlinks a nick from the account group.
func (c *IRCCore) NickServUngroup(nick string) {
	c.sendRaw("PRIVMSG NickServ :UNGROUP " + nick)
}

// NickServAccess manages the authorized address list.
func (c *IRCCore) NickServAccess(action, mask string) {
	c.sendRaw("PRIVMSG NickServ :ACCESS " + action + " " + mask)
}

// NickServAjoin manages auto-join channels.
func (c *IRCCore) NickServAjoin(action, channel string) {
	c.sendRaw("PRIVMSG NickServ :AJOIN " + action + " " + channel)
}

// NickServCert manages client certificate fingerprints.
func (c *IRCCore) NickServCert(action, fingerprint string) {
	cmd := "PRIVMSG NickServ :CERT " + action
	if fingerprint != "" {
		cmd += " " + fingerprint
	}
	c.sendRaw(cmd)
}

// NickServAlist lists channels where you have privileges.
func (c *IRCCore) NickServAlist() {
	c.sendRaw("PRIVMSG NickServ :ALIST")
}

// NickServAcc checks authentication level of a user (0=not registered, 1=registered not identified, 2=recognized, 3=identified).
func (c *IRCCore) NickServAcc(nick string) {
	c.sendRaw("PRIVMSG NickServ :ACC " + nick)
}

// NickServStatus checks owner status of a nickname.
func (c *IRCCore) NickServStatus(nick string) {
	c.sendRaw("PRIVMSG NickServ :STATUS " + nick)
}

// NickServDrop unregisters a nickname.
func (c *IRCCore) NickServDrop(nick string) {
	if nick != "" {
		c.sendRaw("PRIVMSG NickServ :DROP " + nick)
	} else {
		c.sendRaw("PRIVMSG NickServ :DROP")
	}
}

// NickServSet configures a nick option (PASSWORD, ENFORCE, URL, EMAIL, NOMEMO, etc.).
func (c *IRCCore) NickServSet(option, value string) {
	c.sendRaw("PRIVMSG NickServ :SET " + option + " " + value)
}

// NickServSendPass requests a password recovery email.
func (c *IRCCore) NickServSendPass(nick string) {
	c.sendRaw("PRIVMSG NickServ :SENDPASS " + nick)
}

// NickServRecover disconnects someone using your registered nick.
func (c *IRCCore) NickServRecover(nick, password string) {
	c.sendRaw("PRIVMSG NickServ :RECOVER " + nick + " " + password)
}

// NickServUpdate refreshes status and checks for memos.
func (c *IRCCore) NickServUpdate() {
	c.sendRaw("PRIVMSG NickServ :UPDATE")
}

// --- Additional ChanServ commands ---

// ChanServFlags manages user privilege flags.
func (c *IRCCore) ChanServFlags(channel, nick, flags string) {
	cmd := "PRIVMSG ChanServ :FLAGS " + channel
	if nick != "" {
		cmd += " " + nick
		if flags != "" {
			cmd += " " + flags
		}
	}
	c.sendRaw(cmd)
}

// ChanServAccess manages the channel access list.
func (c *IRCCore) ChanServAccess(channel, action, mask, level string) {
	cmd := "PRIVMSG ChanServ :ACCESS " + channel + " " + action
	if mask != "" {
		cmd += " " + mask
	}
	if level != "" {
		cmd += " " + level
	}
	c.sendRaw(cmd)
}

// ChanServAop manages the Auto-Op list.
func (c *IRCCore) ChanServAop(channel, action, nick string) {
	c.sendRaw("PRIVMSG ChanServ :AOP " + channel + " " + action + " " + nick)
}

// ChanServSop manages the Super-Op list.
func (c *IRCCore) ChanServSop(channel, action, nick string) {
	c.sendRaw("PRIVMSG ChanServ :SOP " + channel + " " + action + " " + nick)
}

// ChanServHop manages the Half-Op list.
func (c *IRCCore) ChanServHop(channel, action, nick string) {
	c.sendRaw("PRIVMSG ChanServ :HOP " + channel + " " + action + " " + nick)
}

// ChanServVop manages the Voice list.
func (c *IRCCore) ChanServVop(channel, action, nick string) {
	c.sendRaw("PRIVMSG ChanServ :VOP " + channel + " " + action + " " + nick)
}

// ChanServQop manages the channel owner list.
func (c *IRCCore) ChanServQop(channel, action, nick string) {
	c.sendRaw("PRIVMSG ChanServ :QOP " + channel + " " + action + " " + nick)
}

// ChanServBan bans a user via ChanServ.
func (c *IRCCore) ChanServBan(channel, nick string) {
	c.sendRaw("PRIVMSG ChanServ :BAN " + channel + " " + nick)
}

// ChanServUnban unbans a user via ChanServ.
func (c *IRCCore) ChanServUnban(channel, nick string) {
	c.sendRaw("PRIVMSG ChanServ :UNBAN " + channel + " " + nick)
}

// ChanServKick kicks a user via ChanServ.
func (c *IRCCore) ChanServKick(channel, nick, reason string) {
	cmd := "PRIVMSG ChanServ :KICK " + channel + " " + nick
	if reason != "" {
		cmd += " " + reason
	}
	c.sendRaw(cmd)
}

// ChanServTopic sets the channel topic via ChanServ (bypasses +t).
func (c *IRCCore) ChanServTopic(channel, topic string) {
	c.sendRaw("PRIVMSG ChanServ :TOPIC " + channel + " " + topic)
}

// ChanServUp updates your own channel status to match your access level.
func (c *IRCCore) ChanServUp(channel string) {
	c.sendRaw("PRIVMSG ChanServ :UP " + channel)
}

// ChanServDown removes your own channel privileges.
func (c *IRCCore) ChanServDown(channel string) {
	c.sendRaw("PRIVMSG ChanServ :DOWN " + channel)
}

// ChanServSet configures a channel option (KEEPTOPIC, TOPICLOCK, MLOCK, PRIVATE, RESTRICTED, SECURE, etc.).
func (c *IRCCore) ChanServSet(channel, option, value string) {
	c.sendRaw("PRIVMSG ChanServ :SET " + channel + " " + option + " " + value)
}

// ChanServClear clears a channel attribute (MODES, BANS, USERS, etc.).
func (c *IRCCore) ChanServClear(channel, what string) {
	c.sendRaw("PRIVMSG ChanServ :CLEAR " + channel + " " + what)
}

// ChanServEnforce applies channel modes and access lists immediately.
func (c *IRCCore) ChanServEnforce(channel string) {
	c.sendRaw("PRIVMSG ChanServ :ENFORCE " + channel)
}

// ChanServEntryMsg sets the message shown when users join a channel.
func (c *IRCCore) ChanServEntryMsg(channel, message string) {
	c.sendRaw("PRIVMSG ChanServ :ENTRYMSG " + channel + " " + message)
}

// ChanServSync synchronizes channel modes with the access list.
func (c *IRCCore) ChanServSync(channel string) {
	c.sendRaw("PRIVMSG ChanServ :SYNC " + channel)
}

// ChanServGetKey retrieves the channel key.
func (c *IRCCore) ChanServGetKey(channel string) {
	c.sendRaw("PRIVMSG ChanServ :GETKEY " + channel)
}

// ChanServStatus shows a user's access level in a channel.
func (c *IRCCore) ChanServStatus(channel, nick string) {
	c.sendRaw("PRIVMSG ChanServ :STATUS " + channel + " " + nick)
}

// ChanServList searches registered channels.
func (c *IRCCore) ChanServList(pattern string) {
	if pattern != "" {
		c.sendRaw("PRIVMSG ChanServ :LIST " + pattern)
	} else {
		c.sendRaw("PRIVMSG ChanServ :LIST")
	}
}

// ChanServClone duplicates settings from one channel to another.
func (c *IRCCore) ChanServClone(source, target string) {
	c.sendRaw("PRIVMSG ChanServ :CLONE " + source + " " + target)
}

// ChanServOwner gives channel owner status via ChanServ.
func (c *IRCCore) ChanServOwner(channel, nick string) {
	c.sendRaw("PRIVMSG ChanServ :OWNER " + channel + " " + nick)
}

// ChanServDeowner removes channel owner status via ChanServ.
func (c *IRCCore) ChanServDeowner(channel, nick string) {
	c.sendRaw("PRIVMSG ChanServ :DEOWNER " + channel + " " + nick)
}

// ChanServProtect gives channel protect/admin status via ChanServ.
func (c *IRCCore) ChanServProtect(channel, nick string) {
	c.sendRaw("PRIVMSG ChanServ :PROTECT " + channel + " " + nick)
}

// ChanServDeprotect removes channel protect/admin status via ChanServ.
func (c *IRCCore) ChanServDeprotect(channel, nick string) {
	c.sendRaw("PRIVMSG ChanServ :DEPROTECT " + channel + " " + nick)
}

// ChanServIdentify authenticates as channel founder.
func (c *IRCCore) ChanServIdentify(channel, password string) {
	c.sendRaw("PRIVMSG ChanServ :IDENTIFY " + channel + " " + password)
}

// ChanServMode sets channel modes via ChanServ.
func (c *IRCCore) ChanServMode(channel, modes string) {
	c.sendRaw("PRIVMSG ChanServ :MODE " + channel + " " + modes)
}

// --- Additional MemoServ commands ---

// MemoServRSend sends a memo with read receipt.
func (c *IRCCore) MemoServRSend(target, text string) {
	c.sendRaw("PRIVMSG MemoServ :RSEND " + target + " " + text)
}

// MemoServCancel cancels the most recent unread memo.
func (c *IRCCore) MemoServCancel(target string) {
	c.sendRaw("PRIVMSG MemoServ :CANCEL " + target)
}

// MemoServCheck checks if a memo was read.
func (c *IRCCore) MemoServCheck(target string) {
	c.sendRaw("PRIVMSG MemoServ :CHECK " + target)
}

// MemoServInfo displays memo account information.
func (c *IRCCore) MemoServInfo(target string) {
	if target != "" {
		c.sendRaw("PRIVMSG MemoServ :INFO " + target)
	} else {
		c.sendRaw("PRIVMSG MemoServ :INFO")
	}
}

// MemoServIgnore manages memo sender ignore list.
func (c *IRCCore) MemoServIgnore(action, nick string) {
	cmd := "PRIVMSG MemoServ :IGNORE"
	if action != "" {
		cmd += " " + action
	}
	if nick != "" {
		cmd += " " + nick
	}
	c.sendRaw(cmd)
}

// MemoServSet configures memo options (NOTIFY, LIMIT, etc.).
func (c *IRCCore) MemoServSet(option, value string) {
	c.sendRaw("PRIVMSG MemoServ :SET " + option + " " + value)
}

// --- HostServ ---

// HostServOn activates the assigned vhost.
func (c *IRCCore) HostServOn() {
	c.sendRaw("PRIVMSG HostServ :ON")
}

// HostServOff deactivates the current vhost.
func (c *IRCCore) HostServOff() {
	c.sendRaw("PRIVMSG HostServ :OFF")
}

// HostServRequest submits a custom vhost for approval.
func (c *IRCCore) HostServRequest(vhost string) {
	c.sendRaw("PRIVMSG HostServ :REQUEST " + vhost)
}

// HostServGroup syncs vhost across grouped nicks.
func (c *IRCCore) HostServGroup() {
	c.sendRaw("PRIVMSG HostServ :GROUP")
}

// --- BotServ ---

// BotServBotList lists available service bots.
func (c *IRCCore) BotServBotList() {
	c.sendRaw("PRIVMSG BotServ :BOTLIST")
}

// BotServAssign assigns a bot to a channel.
func (c *IRCCore) BotServAssign(channel, botNick string) {
	c.sendRaw("PRIVMSG BotServ :ASSIGN " + channel + " " + botNick)
}

// BotServUnassign removes a bot from a channel.
func (c *IRCCore) BotServUnassign(channel string) {
	c.sendRaw("PRIVMSG BotServ :UNASSIGN " + channel)
}

// BotServInfo views bot or channel bot details.
func (c *IRCCore) BotServInfo(target string) {
	c.sendRaw("PRIVMSG BotServ :INFO " + target)
}

// BotServSay makes a bot send a message to a channel.
func (c *IRCCore) BotServSay(channel, text string) {
	c.sendRaw("PRIVMSG BotServ :SAY " + channel + " " + text)
}

// BotServAct makes a bot send an action (/me) to a channel.
func (c *IRCCore) BotServAct(channel, text string) {
	c.sendRaw("PRIVMSG BotServ :ACT " + channel + " " + text)
}

// --- DCC offers ---

// GetDCCOffers returns pending DCC offers received from other users.
func (c *IRCCore) GetDCCOffers() []IRCDCCOffer {
	c.dccOffersMu.RLock()
	defer c.dccOffersMu.RUnlock()
	result := make([]IRCDCCOffer, len(c.dccOffers))
	copy(result, c.dccOffers)
	return result
}

// ClearDCCOffers clears all pending DCC offers.
func (c *IRCCore) ClearDCCOffers() {
	c.dccOffersMu.Lock()
	c.dccOffers = nil
	c.dccOffersMu.Unlock()
}

// --- CTCP CLIENTINFO ---

// GetCTCPClientInfo returns the list of CTCP commands this client supports.
func (c *IRCCore) GetCTCPClientInfo() string {
	return "ACTION VERSION PING TIME CLIENTINFO FINGER USERINFO SOURCE DCC"
}

// --- Invite list tracking ---

// RequestInviteList requests the invite exception list for a channel.
func (c *IRCCore) RequestInviteList(channel string) {
	c.sendRaw("MODE " + channel + " +I")
}

// --- Channel RENAME (IRCv3 draft) ---

// RenameChannel renames a channel (requires server support for channel-rename cap).
func (c *IRCCore) RenameChannel(oldName, newName, reason string) {
	if reason != "" {
		c.sendRaw("RENAME " + oldName + " " + newName + " :" + reason)
	} else {
		c.sendRaw("RENAME " + oldName + " " + newName)
	}
}

// --- KILL (oper) ---

// Kill disconnects a user from the network (requires oper privileges).
func (c *IRCCore) Kill(nick, reason string) {
	c.sendRaw("KILL " + nick + " :" + reason)
}

// --- Enabled capabilities query ---

// GetEnabledCaps returns the set of IRCv3 capabilities that are currently enabled.
func (c *IRCCore) GetEnabledCaps() []string {
	c.enabledCapsMu.RLock()
	defer c.enabledCapsMu.RUnlock()
	caps := make([]string, 0, len(c.enabledCaps))
	for cap := range c.enabledCaps {
		caps = append(caps, cap)
	}
	sort.Strings(caps)
	return caps
}

// RequestCAPList requests the list of currently enabled capabilities from the server.
func (c *IRCCore) RequestCAPList() {
	c.sendRaw("CAP LIST")
}

// RequestCAP requests additional capabilities after registration.
func (c *IRCCore) RequestCAP(caps ...string) {
	c.sendRaw("CAP REQ :" + strings.Join(caps, " "))
}

// --- WEBIRC ---

// WebIRC sends a WEBIRC command to report the real IP through a gateway.
// Must be sent before PASS/NICK/USER.
func (c *IRCCore) WebIRC(password, gateway, hostname, ip string) {
	c.sendRaw("WEBIRC " + password + " " + gateway + " " + hostname + " " + ip)
}

// ---------------------------------------------------------------------------
// Session persistence
// ---------------------------------------------------------------------------

func (c *IRCCore) loadSession() error {
	data, err := os.ReadFile(c.sessionPath)
	if err != nil {
		return err
	}
	var sess ircSession
	if err := json.Unmarshal(data, &sess); err != nil {
		return err
	}

	c.server = sess.Server
	c.nick = sess.Nick
	c.username = sess.Username
	c.realname = sess.Realname
	c.password = sess.Password
	c.useTLS = sess.UseTLS
	c.useSASL = sess.UseSASL
	c.autoJoin = sess.Channels

	c.blockedMu.Lock()
	for _, b := range sess.Blocked {
		c.blocked[strings.ToLower(b)] = true
	}
	c.blockedMu.Unlock()

	return nil
}

func (c *IRCCore) saveSession() {
	sess := ircSession{
		Server:   c.server,
		Nick:     c.nick,
		Username: c.username,
		Realname: c.realname,
		Password: c.password,
		UseTLS:   c.useTLS,
		UseSASL:  c.useSASL,
	}

	// Save joined channels
	c.channelsMu.RLock()
	for _, ch := range c.channels {
		sess.Channels = append(sess.Channels, ch.Name)
	}
	c.channelsMu.RUnlock()
	if len(sess.Channels) == 0 {
		sess.Channels = c.autoJoin
	}

	// Save blocked
	c.blockedMu.RLock()
	for nick := range c.blocked {
		sess.Blocked = append(sess.Blocked, nick)
	}
	c.blockedMu.RUnlock()

	data, err := json.MarshalIndent(sess, "", "  ")
	if err != nil {
		return
	}
	os.WriteFile(c.sessionPath, data, 0600)
}

// ──────────────────────────── RFC Commands (Oper) ────────────────────────────

// Connect requests the server to link to another server (oper only).
func (c *IRCCore) Connect(target string, port int, remote string) {
	if remote != "" {
		c.sendRaw(fmt.Sprintf("CONNECT %s %d %s", target, port, remote))
	} else {
		c.sendRaw(fmt.Sprintf("CONNECT %s %d", target, port))
	}
}

// Die requests the server to shut down (oper only).
func (c *IRCCore) Die() {
	c.sendRaw("DIE")
}

// Rehash requests the server to reload its configuration (oper only).
func (c *IRCCore) Rehash() {
	c.sendRaw("REHASH")
}

// Restart requests the server to restart (oper only).
func (c *IRCCore) Restart() {
	c.sendRaw("RESTART")
}

// Service registers a new service on the network.
func (c *IRCCore) Service(nick, distribution, serviceType, info string) {
	c.sendRaw(fmt.Sprintf("SERVICE %s * %s %s 0 :%s", nick, distribution, serviceType, info))
}

// Njoin sends an NJOIN message for server-to-server channel burst.
func (c *IRCCore) Njoin(channel string, members []string) {
	c.sendRaw(fmt.Sprintf("NJOIN %s :%s", channel, strings.Join(members, ",")))
}

// ──────────────────────────── IRCv3 Extensions ────────────────────────────

// Setname changes the realname without reconnecting (requires setname capability).
func (c *IRCCore) Setname(realname string) {
	c.sendRaw("SETNAME :" + realname)
}

// ChatHistoryBetween fetches messages between two timestamps or message IDs.
func (c *IRCCore) ChatHistoryBetween(target, startRef, endRef string, limit int) {
	c.sendRaw(fmt.Sprintf("CHATHISTORY BETWEEN %s %s %s %d", target, startRef, endRef, limit))
}

// BatchStart starts a batch processing context.
func (c *IRCCore) BatchStart(refTag, batchType string, params ...string) {
	cmd := fmt.Sprintf("BATCH +%s %s", refTag, batchType)
	if len(params) > 0 {
		cmd += " " + strings.Join(params, " ")
	}
	c.sendRaw(cmd)
}

// BatchEnd ends a batch processing context.
func (c *IRCCore) BatchEnd(refTag string) {
	c.sendRaw("BATCH -" + refTag)
}

// Starttls requests TLS upgrade on a plain connection.
func (c *IRCCore) Starttls() {
	c.sendRaw("STARTTLS")
}

// ──────────────────────────── DCC Extended ────────────────────────────

// DCCSecureSend sends a DCC SSEND (TLS file transfer) request.
func (c *IRCCore) DCCSecureSend(nick, filename string, port int, size int64) {
	c.sendRaw(fmt.Sprintf("PRIVMSG %s :\x01DCC SSEND %s 0 %d %d\x01", nick, filename, port, size))
}

// DCCSecureChat sends a DCC SCHAT (TLS chat) request.
func (c *IRCCore) DCCSecureChat(nick string, port int) {
	c.sendRaw(fmt.Sprintf("PRIVMSG %s :\x01DCC SCHAT chat 0 %d\x01", nick, port))
}

// XDCCSend requests a file from an XDCC bot.
func (c *IRCCore) XDCCSend(botNick string, packNum int) {
	c.sendRaw(fmt.Sprintf("PRIVMSG %s :XDCC SEND #%d", botNick, packNum))
}

// XDCCList requests the pack list from an XDCC bot.
func (c *IRCCore) XDCCList(botNick string) {
	c.sendRaw(fmt.Sprintf("PRIVMSG %s :XDCC LIST", botNick))
}

// XDCCBatch requests multiple packs from an XDCC bot.
func (c *IRCCore) XDCCBatch(botNick string, packNums []int) {
	packs := make([]string, len(packNums))
	for i, n := range packNums {
		packs[i] = fmt.Sprintf("#%d", n)
	}
	c.sendRaw(fmt.Sprintf("PRIVMSG %s :XDCC BATCH %s", botNick, strings.Join(packs, ",")))
}

// XDCCCancel cancels the current XDCC transfer.
func (c *IRCCore) XDCCCancel(botNick string) {
	c.sendRaw(fmt.Sprintf("PRIVMSG %s :XDCC CANCEL", botNick))
}

// XDCCRemove removes a pack (bot owner only).
func (c *IRCCore) XDCCRemove(botNick string, packNum int) {
	c.sendRaw(fmt.Sprintf("PRIVMSG %s :XDCC REMOVE #%d", botNick, packNum))
}

// XDCCInfo shows details about a specific pack.
func (c *IRCCore) XDCCInfo(botNick string, packNum int) {
	c.sendRaw(fmt.Sprintf("PRIVMSG %s :XDCC INFO #%d", botNick, packNum))
}

// XDCCSearch searches packs on an XDCC bot.
func (c *IRCCore) XDCCSearch(botNick, query string) {
	c.sendRaw(fmt.Sprintf("PRIVMSG %s :XDCC SEARCH %s", botNick, query))
}

// ──────────────────────────── CTCP Extended ────────────────────────────

// CTCPFinger sends a CTCP FINGER query.
func (c *IRCCore) CTCPFinger(target string) {
	c.SendCTCP(target, "FINGER", "")
}

// CTCPSource sends a CTCP SOURCE query.
func (c *IRCCore) CTCPSource(target string) {
	c.SendCTCP(target, "SOURCE", "")
}

// CTCPUserinfo sends a CTCP USERINFO query.
func (c *IRCCore) CTCPUserinfo(target string) {
	c.SendCTCP(target, "USERINFO", "")
}

// ──────────────────────────── NickServ Extended ────────────────────────────

// NickServRegain recovers and changes to a nick in one step.
func (c *IRCCore) NickServRegain(nick, password string) {
	c.sendRaw("PRIVMSG NickServ :REGAIN " + nick + " " + password)
}

// NickServGList lists nicks in the current nick group.
func (c *IRCCore) NickServGList() {
	c.sendRaw("PRIVMSG NickServ :GLIST")
}

// NickServConfirm completes email verification for registration.
func (c *IRCCore) NickServConfirm(code string) {
	c.sendRaw("PRIVMSG NickServ :CONFIRM " + code)
}

// NickServSuspend suspends a nick (oper only).
func (c *IRCCore) NickServSuspend(nick, reason string) {
	c.sendRaw("PRIVMSG NickServ :SUSPEND " + nick + " " + reason)
}

// NickServUnsuspend lifts a nick suspension (oper only).
func (c *IRCCore) NickServUnsuspend(nick string) {
	c.sendRaw("PRIVMSG NickServ :UNSUSPEND " + nick)
}

// NickServForbid forbids a nick from being registered (oper only).
func (c *IRCCore) NickServForbid(nick, reason string) {
	c.sendRaw("PRIVMSG NickServ :FORBID " + nick + " " + reason)
}

// NickServList searches registered nicks (oper only).
func (c *IRCCore) NickServList(pattern string) {
	c.sendRaw("PRIVMSG NickServ :LIST " + pattern)
}

// NickServSaSet admin-sets a nick option (oper only).
func (c *IRCCore) NickServSaSet(nick, option, value string) {
	c.sendRaw("PRIVMSG NickServ :SASET " + nick + " " + option + " " + value)
}

// ──────────────────────────── ChanServ Extended ────────────────────────────

// ChanServAppendTopic appends text to the channel topic.
func (c *IRCCore) ChanServAppendTopic(channel, text string) {
	c.sendRaw("PRIVMSG ChanServ :APPENDTOPIC " + channel + " " + text)
}

// ChanServLevels manages access level definitions for a channel.
func (c *IRCCore) ChanServLevels(channel, action, level, value string) {
	cmd := "PRIVMSG ChanServ :LEVELS " + channel + " " + action
	if level != "" {
		cmd += " " + level
	}
	if value != "" {
		cmd += " " + value
	}
	c.sendRaw(cmd)
}

// ChanServLog views the action log for a channel.
func (c *IRCCore) ChanServLog(channel string) {
	c.sendRaw("PRIVMSG ChanServ :LOG " + channel)
}

// ChanServCount counts access list entries for a channel.
func (c *IRCCore) ChanServCount(channel string) {
	c.sendRaw("PRIVMSG ChanServ :COUNT " + channel)
}

// ChanServSuspend suspends a channel (oper only).
func (c *IRCCore) ChanServSuspend(channel, reason string) {
	c.sendRaw("PRIVMSG ChanServ :SUSPEND " + channel + " " + reason)
}

// ChanServUnsuspend lifts a channel suspension (oper only).
func (c *IRCCore) ChanServUnsuspend(channel string) {
	c.sendRaw("PRIVMSG ChanServ :UNSUSPEND " + channel)
}

// ChanServForbid forbids a channel from being registered (oper only).
func (c *IRCCore) ChanServForbid(channel, reason string) {
	c.sendRaw("PRIVMSG ChanServ :FORBID " + channel + " " + reason)
}

// ──────────────────────────── MemoServ Extended ────────────────────────────

// MemoServSendGroup sends a memo to a nick group.
func (c *IRCCore) MemoServSendGroup(group, text string) {
	c.sendRaw("PRIVMSG MemoServ :SENDGROUP " + group + " " + text)
}

// MemoServSendOps sends a memo to channel operators.
func (c *IRCCore) MemoServSendOps(channel, text string) {
	c.sendRaw("PRIVMSG MemoServ :SENDOPS " + channel + " " + text)
}

// MemoServForward forwards a memo to another user.
func (c *IRCCore) MemoServForward(memoID, target string) {
	c.sendRaw("PRIVMSG MemoServ :FORWARD " + target + " " + memoID)
}

// MemoServStaff sends a memo to all staff (oper only).
func (c *IRCCore) MemoServStaff(text string) {
	c.sendRaw("PRIVMSG MemoServ :STAFF " + text)
}

// ──────────────────────────── HostServ Extended ────────────────────────────

// HostServList lists own vhosts.
func (c *IRCCore) HostServList() {
	c.sendRaw("PRIVMSG HostServ :LIST")
}

// HostServSet assigns a vhost to a nick (oper only).
func (c *IRCCore) HostServSet(nick, vhost string) {
	c.sendRaw("PRIVMSG HostServ :SET " + nick + " " + vhost)
}

// HostServSetAll assigns a vhost to a nick group (oper only).
func (c *IRCCore) HostServSetAll(nick, vhost string) {
	c.sendRaw("PRIVMSG HostServ :SETALL " + nick + " " + vhost)
}

// HostServDel removes a vhost from a nick (oper only).
func (c *IRCCore) HostServDel(nick string) {
	c.sendRaw("PRIVMSG HostServ :DEL " + nick)
}

// HostServDelAll removes a vhost from a nick group (oper only).
func (c *IRCCore) HostServDelAll(nick string) {
	c.sendRaw("PRIVMSG HostServ :DELALL " + nick)
}

// HostServActivate approves a pending vhost request (oper only).
func (c *IRCCore) HostServActivate(nick string) {
	c.sendRaw("PRIVMSG HostServ :ACTIVATE " + nick)
}

// HostServReject rejects a pending vhost request (oper only).
func (c *IRCCore) HostServReject(nick, reason string) {
	cmd := "PRIVMSG HostServ :REJECT " + nick
	if reason != "" {
		cmd += " " + reason
	}
	c.sendRaw(cmd)
}

// HostServWaiting lists pending vhost requests (oper only).
func (c *IRCCore) HostServWaiting() {
	c.sendRaw("PRIVMSG HostServ :WAITING")
}

// ──────────────────────────── BotServ Extended ────────────────────────────

// BotServBotAdd creates a bot (oper only).
func (c *IRCCore) BotServBotAdd(nick, ident, host, realname string) {
	c.sendRaw("PRIVMSG BotServ :BOT ADD " + nick + " " + ident + " " + host + " " + realname)
}

// BotServBotDel deletes a bot (oper only).
func (c *IRCCore) BotServBotDel(nick string) {
	c.sendRaw("PRIVMSG BotServ :BOT DEL " + nick)
}

// BotServBotChange modifies a bot's nick/ident/host (oper only).
func (c *IRCCore) BotServBotChange(oldNick, newNick, ident, host, realname string) {
	c.sendRaw("PRIVMSG BotServ :BOT CHANGE " + oldNick + " " + newNick + " " + ident + " " + host + " " + realname)
}

// BotServBadwords manages the bad word filter list.
func (c *IRCCore) BotServBadwords(channel, action, word string) {
	cmd := "PRIVMSG BotServ :BADWORDS " + channel + " " + action
	if word != "" {
		cmd += " " + word
	}
	c.sendRaw(cmd)
}

// BotServKickConfig configures auto-kick triggers for a channel bot.
func (c *IRCCore) BotServKickConfig(channel, option, value string) {
	c.sendRaw("PRIVMSG BotServ :KICK " + channel + " " + option + " " + value)
}

// BotServSet configures bot settings for a channel.
func (c *IRCCore) BotServSet(channel, option, value string) {
	c.sendRaw("PRIVMSG BotServ :SET " + channel + " " + option + " " + value)
}

// ──────────────────────────── OperServ (all oper only) ────────────────────────────

// OperServAkill manages network-wide K-lines.
func (c *IRCCore) OperServAkill(action, mask, reason string) {
	cmd := "PRIVMSG OperServ :AKILL " + action + " " + mask
	if reason != "" {
		cmd += " " + reason
	}
	c.sendRaw(cmd)
}

// OperServSqline manages nick/channel quarantines.
func (c *IRCCore) OperServSqline(action, mask, reason string) {
	cmd := "PRIVMSG OperServ :SQLINE " + action + " " + mask
	if reason != "" {
		cmd += " " + reason
	}
	c.sendRaw(cmd)
}

// OperServSnline manages realname bans.
func (c *IRCCore) OperServSnline(action, mask, reason string) {
	cmd := "PRIVMSG OperServ :SNLINE " + action + " " + mask
	if reason != "" {
		cmd += " " + reason
	}
	c.sendRaw(cmd)
}

// OperServSession views/manages session limits.
func (c *IRCCore) OperServSession(action, host string) {
	c.sendRaw("PRIVMSG OperServ :SESSION " + action + " " + host)
}

// OperServNoop disables O-lines on a server.
func (c *IRCCore) OperServNoop(server, action string) {
	c.sendRaw("PRIVMSG OperServ :NOOP " + server + " " + action)
}

// OperServJupe fakes/quarantines a server.
func (c *IRCCore) OperServJupe(server, reason string) {
	c.sendRaw("PRIVMSG OperServ :JUPE " + server + " " + reason)
}

// OperServGlobal sends a global notice to all users.
func (c *IRCCore) OperServGlobal(message string) {
	c.sendRaw("PRIVMSG OperServ :GLOBAL " + message)
}

// OperServDefcon sets the network defense level (1-5).
func (c *IRCCore) OperServDefcon(level int) {
	c.sendRaw(fmt.Sprintf("PRIVMSG OperServ :DEFCON %d", level))
}

// OperServStats shows services statistics.
func (c *IRCCore) OperServStats(what string) {
	if what == "" {
		c.sendRaw("PRIVMSG OperServ :STATS")
	} else {
		c.sendRaw("PRIVMSG OperServ :STATS " + what)
	}
}

// OperServReload reloads services configuration modules.
func (c *IRCCore) OperServReload(module string) {
	if module == "" {
		c.sendRaw("PRIVMSG OperServ :RELOAD")
	} else {
		c.sendRaw("PRIVMSG OperServ :RELOAD " + module)
	}
}

// OperServShutdown shuts down services.
func (c *IRCCore) OperServShutdown() {
	c.sendRaw("PRIVMSG OperServ :SHUTDOWN")
}

// OperServRestart restarts services.
func (c *IRCCore) OperServRestart() {
	c.sendRaw("PRIVMSG OperServ :RESTART")
}

// ──────────────────────────── Server Extensions (oper commands) ────────────────────────────

// SetHost sets own virtual host (oper only).
func (c *IRCCore) SetHost(vhost string) {
	c.sendRaw("SETHOST " + vhost)
}

// ChgHost changes another user's host (oper only).
func (c *IRCCore) ChgHost(nick, newHost string) {
	c.sendRaw("CHGHOST " + nick + " " + newHost)
}

// ChgIdent changes another user's ident (oper only).
func (c *IRCCore) ChgIdent(nick, newIdent string) {
	c.sendRaw("CHGIDENT " + nick + " " + newIdent)
}

// ChgName changes another user's realname (oper only).
func (c *IRCCore) ChgName(nick, newName string) {
	c.sendRaw("CHGNAME " + nick + " :" + newName)
}

// SaJoin forces a user to join a channel (oper only).
func (c *IRCCore) SaJoin(nick, channel string) {
	c.sendRaw("SAJOIN " + nick + " " + channel)
}

// SaPart forces a user to part a channel (oper only).
func (c *IRCCore) SaPart(nick, channel string) {
	c.sendRaw("SAPART " + nick + " " + channel)
}

// SaNick forces a user to change nick (oper only).
func (c *IRCCore) SaNick(oldNick, newNick string) {
	c.sendRaw("SANICK " + oldNick + " " + newNick)
}

// SaMode forces a mode change on a channel or user (oper only).
func (c *IRCCore) SaMode(target, modes string) {
	c.sendRaw("SAMODE " + target + " " + modes)
}

// Globops sends an oper-only global broadcast message.
func (c *IRCCore) Globops(message string) {
	c.sendRaw("GLOBOPS :" + message)
}

// Vhost sets own virtual host (user command, UnrealIRCd).
func (c *IRCCore) Vhost(username, password string) {
	c.sendRaw("VHOST " + username + " " + password)
}

// ──────────────────────────── IRCv3 Draft Extensions ────────────────────────────

// BounceListNetworks lists networks available via a bouncer.
func (c *IRCCore) BounceListNetworks() {
	c.sendRaw("BOUNCER LISTNETWORKS")
}

// BouncerBind binds the current connection to a bouncer network.
func (c *IRCCore) BouncerBind(networkID string) {
	c.sendRaw("BOUNCER BIND " + networkID)
}

// Resume attempts to resume a disconnected session (draft/resume).
func (c *IRCCore) Resume(token string, timestamp time.Time) {
	c.sendRaw(fmt.Sprintf("RESUME %s %s", token, timestamp.UTC().Format("2006-01-02T15:04:05.000Z")))
}

// WebPushRegister registers for web push notifications.
func (c *IRCCore) WebPushRegister(endpoint, vapidKey, p256dh, auth string) {
	c.sendRaw(fmt.Sprintf("WEBPUSH REGISTER %s %s %s %s", endpoint, vapidKey, p256dh, auth))
}

// WebPushUnregister unregisters from web push notifications.
func (c *IRCCore) WebPushUnregister(endpoint string) {
	c.sendRaw("WEBPUSH UNREGISTER " + endpoint)
}

// ──────────────────────────── IRCd-Specific Oper Commands ────────────────────────────

// GLine adds a network-wide IP ban (UnrealIRCd/InspIRCd).
func (c *IRCCore) GLine(mask, duration, reason string) {
	c.sendRaw("GLINE " + mask + " " + duration + " :" + reason)
}

// GZLine adds a network-wide IP ban without ident (UnrealIRCd).
func (c *IRCCore) GZLine(ip, duration, reason string) {
	c.sendRaw("GZLINE " + ip + " " + duration + " :" + reason)
}

// ZLine adds a server-local IP ban.
func (c *IRCCore) ZLine(ip, duration, reason string) {
	c.sendRaw("ZLINE " + ip + " " + duration + " :" + reason)
}

// Shun silences a user network-wide (UnrealIRCd).
func (c *IRCCore) Shun(mask, duration, reason string) {
	c.sendRaw("SHUN " + mask + " " + duration + " :" + reason)
}

// KLine adds a server-local ban.
func (c *IRCCore) KLine(mask, duration, reason string) {
	c.sendRaw("KLINE " + mask + " " + duration + " :" + reason)
}

// Check inspects user/channel details (InspIRCd oper).
func (c *IRCCore) Check(target string) {
	c.sendRaw("CHECK " + target)
}

// ──────────────────────────── GroupServ (Atheme) ────────────────────────────

// GroupServInfo shows info about a group.
func (c *IRCCore) GroupServInfo(group string) {
	c.sendRaw("PRIVMSG GroupServ :INFO " + group)
}

// GroupServJoin joins a group.
func (c *IRCCore) GroupServJoin(group string) {
	c.sendRaw("PRIVMSG GroupServ :JOIN " + group)
}

// GroupServLeave leaves a group.
func (c *IRCCore) GroupServLeave(group string) {
	c.sendRaw("PRIVMSG GroupServ :LEAVE " + group)
}

// GroupServFlags manages group flags.
func (c *IRCCore) GroupServFlags(group, target, flags string) {
	c.sendRaw("PRIVMSG GroupServ :FLAGS " + group + " " + target + " " + flags)
}

// ──────────────────────────── StatServ ────────────────────────────

// StatServInfo shows network statistics.
func (c *IRCCore) StatServInfo() {
	c.sendRaw("PRIVMSG StatServ :INFO")
}

// StatServAkill shows akill statistics.
func (c *IRCCore) StatServAkill() {
	c.sendRaw("PRIVMSG StatServ :AKILL")
}

// ════════════════════════════════════════════════════════════════════════════════
// Step 4 — New Methods (~130 methods)
// ════════════════════════════════════════════════════════════════════════════════

// ── IRCd Oper Commands — UnrealIRCd (~23) ──

func (c *IRCCore) Tempshun(nick, reason string) { c.sendRaw("TEMPSHUN " + nick + " :" + reason) }
func (c *IRCCore) SpamfilterAdd(target, action, tkltime, reason, regex string) {
	c.sendRaw(fmt.Sprintf("SPAMFILTER add %s %s %s %s :%s", target, action, tkltime, reason, regex))
}
func (c *IRCCore) SpamfilterDel(target, action, regex string) {
	c.sendRaw(fmt.Sprintf("SPAMFILTER del %s %s :%s", target, action, regex))
}
func (c *IRCCore) Rmtkl(tklType, pattern string) { c.sendRaw("RMTKL " + tklType + " " + pattern) }
func (c *IRCCore) Jumpserver(addr, port, reason string) {
	c.sendRaw("JUMPSERVER " + addr + " " + port + " :" + reason)
}
func (c *IRCCore) Tsctl(subcmd string) { c.sendRaw("TSCTL " + subcmd) }
func (c *IRCCore) Dccdeny(filePattern, reason string) {
	c.sendRaw("DCCDENY " + filePattern + " :" + reason)
}
func (c *IRCCore) Undccdeny(filePattern string) { c.sendRaw("UNDCCDENY " + filePattern) }
func (c *IRCCore) Dccallow(args string) { c.sendRaw("DCCALLOW " + args) }
func (c *IRCCore) Sdesc(desc string) { c.sendRaw("SDESC :" + desc) }
func (c *IRCCore) Mkpasswd(hashType, password string) {
	c.sendRaw("MKPASSWD " + hashType + " " + password)
}
func (c *IRCCore) Ircops() { c.sendRaw("IRCOPS") }
func (c *IRCCore) Cycle(channel string) { c.sendRaw("CYCLE " + channel) }
func (c *IRCCore) CloseConnections() { c.sendRaw("CLOSE") }
func (c *IRCCore) DnsInfo(args string) { c.sendRaw("DNS " + args) }
func (c *IRCCore) Eline(mask, duration, reason string) {
	if reason != "" {
		c.sendRaw("ELINE " + mask + " " + duration + " :" + reason)
	} else {
		c.sendRaw("ELINE " + mask)
	}
}
func (c *IRCCore) Addmotd(line string)  { c.sendRaw("ADDMOTD :" + line) }
func (c *IRCCore) Addomotd(line string) { c.sendRaw("ADDOMOTD :" + line) }
func (c *IRCCore) Botmotd()             { c.sendRaw("BOTMOTD") }
func (c *IRCCore) Opermotd()            { c.sendRaw("OPERMOTD") }
func (c *IRCCore) ShowCredits()         { c.sendRaw("CREDITS") }
func (c *IRCCore) ShowLicense()         { c.sendRaw("LICENSE") }
func (c *IRCCore) ShowStaff()           { c.sendRaw("STAFFLIST") }
func (c *IRCCore) ModuleManage(action, moduleName string) {
	switch action {
	case "list":
		c.sendRaw("MODULE LIST")
	case "load":
		c.sendRaw("MODULE LOAD " + moduleName)
	case "unload":
		c.sendRaw("MODULE UNLOAD " + moduleName)
	}
}

// ── IRCd Oper Commands — InspIRCd (~23) ──

func (c *IRCCore) ForcePart(nick, channel, reason string) {
	c.sendRaw("REMOVE " + channel + " " + nick + " :" + reason)
}
func (c *IRCCore) Uninvite(nick, channel string) { c.sendRaw("UNINVITE " + nick + " " + channel) }
func (c *IRCCore) Clearchan(channel, action string) {
	c.sendRaw("CLEARCHAN " + channel + " " + action)
}
func (c *IRCCore) Cban(channel, reason string) { c.sendRaw("CBAN " + channel + " :" + reason) }
func (c *IRCCore) CbanDel(channel string)      { c.sendRaw("CBAN " + channel) }
func (c *IRCCore) Rline(regex, duration, reason string) {
	c.sendRaw("RLINE " + regex + " " + duration + " :" + reason)
}
func (c *IRCCore) RlineDel(regex string) { c.sendRaw("RLINE " + regex) }
func (c *IRCCore) Tline(mask string)     { c.sendRaw("TLINE " + mask) }
func (c *IRCCore) Clones()               { c.sendRaw("CLONES") }
func (c *IRCCore) Lockserv()             { c.sendRaw("LOCKSERV") }
func (c *IRCCore) Unlockserv()           { c.sendRaw("UNLOCKSERV") }
func (c *IRCCore) Rconnect(serverMask, remoteTarget string) {
	c.sendRaw("RCONNECT " + serverMask + " " + remoteTarget)
}
func (c *IRCCore) Rsquit(serverMask, reason string) {
	c.sendRaw("RSQUIT " + serverMask + " :" + reason)
}
func (c *IRCCore) Nicklock(nick, newNick string) { c.sendRaw("NICKLOCK " + nick + " " + newNick) }
func (c *IRCCore) Nickunlock(nick string)        { c.sendRaw("NICKUNLOCK " + nick) }
func (c *IRCCore) Setidle(seconds int)           { c.sendRaw(fmt.Sprintf("SETIDLE %d", seconds)) }
func (c *IRCCore) Swhois(nick, line string)      { c.sendRaw("SWHOIS " + nick + " :" + line) }
func (c *IRCCore) Ojoin(channel string)          { c.sendRaw("OJOIN " + channel) }
func (c *IRCCore) Sakick(channel, nick, reason string) {
	c.sendRaw("SAKICK " + channel + " " + nick + " :" + reason)
}
func (c *IRCCore) Saquit(nick, reason string) { c.sendRaw("SAQUIT " + nick + " :" + reason) }
func (c *IRCCore) Satopic(channel, topic string) {
	c.sendRaw("SATOPIC " + channel + " :" + topic)
}
func (c *IRCCore) Rmode(mask, modes string)    { c.sendRaw("RMODE " + mask + " " + modes) }
func (c *IRCCore) FilterAdd(pattern string)    { c.sendRaw("FILTER " + pattern) }
func (c *IRCCore) FilterDel(pattern string)    { c.sendRaw("FILTER -" + pattern) }
func (c *IRCCore) Alltime()                    { c.sendRaw("ALLTIME") }
func (c *IRCCore) Qline(nick, reason string)   { c.sendRaw("QLINE " + nick + " :" + reason) }
func (c *IRCCore) QlineDel(nick string)        { c.sendRaw("QLINE -" + nick) }

// ── IRCv3 Extensions (~19) ──

func (c *IRCCore) MetadataGet(target, key string) {
	c.sendRaw("METADATA " + target + " GET " + key)
}
func (c *IRCCore) MetadataSet(target, key, value string) {
	c.sendRaw("METADATA " + target + " SET " + key + " :" + value)
}
func (c *IRCCore) MetadataList(target string) { c.sendRaw("METADATA " + target + " LIST") }
func (c *IRCCore) MetadataSub(target, key string) {
	c.sendRaw("METADATA " + target + " SUB " + key)
}
func (c *IRCCore) MetadataUnsub(target, key string) {
	c.sendRaw("METADATA " + target + " UNSUB " + key)
}
func (c *IRCCore) Relaymsg(channel, nick, text string) {
	c.sendRaw(fmt.Sprintf("@+draft/relaymsg=%s PRIVMSG %s :%s", nick, channel, text))
}

// ParseStandardReply parses FAIL/WARN/NOTE structured responses from IRCv3.
func ParseStandardReply(line string) (severity, command, code, context, description string) {
	parts := strings.SplitN(line, " ", 5)
	if len(parts) >= 4 {
		severity = parts[0]
		command = parts[1]
		code = parts[2]
		if len(parts) >= 5 {
			context = parts[3]
			description = strings.TrimPrefix(parts[4], ":")
		} else {
			description = strings.TrimPrefix(parts[3], ":")
		}
	}
	return
}

func (c *IRCCore) STSAutoUpgrade(domain string, port int) error {
	c.mu.Lock()
	c.stsPolicies[domain] = port
	c.mu.Unlock()
	return nil
}

func (c *IRCCore) ConnectWebSocket(url string) error {
	// WebSocket IRC requires HTTP upgrade — store URL for use during connect
	c.mu.Lock()
	c.wsURL = url
	c.mu.Unlock()
	return fmt.Errorf("irc: WebSocket transport requires external ws library")
}

func (c *IRCCore) RequestNoImplicitNames() {
	c.sendRaw("CAP REQ :draft/no-implicit-names")
}
func (c *IRCCore) RequestExtendedMonitor() {
	c.sendRaw("CAP REQ :draft/extended-monitor")
}

// ParseAccountExtban returns an extban string for account-based matching.
func (c *IRCCore) ParseAccountExtban(account string) string {
	c.mu.RLock()
	prefix := c.extbanPrefix
	c.mu.RUnlock()
	if prefix == "" {
		prefix = "$a:"
	}
	return prefix + account
}

func (c *IRCCore) SetBotModeIRCv3() { c.sendRaw("MODE " + c.nick + " +B") }

func (c *IRCCore) OnInviteNotify(handler func(inviter, channel, target string)) {
	c.mu.Lock()
	c.inviteNotifyHandler = handler
	c.mu.Unlock()
}

// SendTagMsg sends a TAGMSG with a channel context tag.
func (c *IRCCore) SendChannelContextTag(target, channelCtx, tags string) {
	c.sendRaw(fmt.Sprintf("@+draft/channel-context=%s;%s TAGMSG %s", channelCtx, tags, target))
}

// SendReactTag sends a TAGMSG with a react tag.
func (c *IRCCore) SendReactTag(target, msgID, emoji string) {
	c.sendRaw(fmt.Sprintf("@+draft/react=%s;+draft/reply=%s TAGMSG %s",
		emoji, msgID, target))
}

// SendClientBatch starts/ends a client-to-server batch.
func (c *IRCCore) SendClientBatch(batchID, batchType, target string, start bool) {
	if start {
		c.sendRaw(fmt.Sprintf("BATCH +%s %s %s", batchID, batchType, target))
	} else {
		c.sendRaw("BATCH -" + batchID)
	}
}

// SendMultiline sends a multi-line message via batch (IRCv3 draft).
func (c *IRCCore) SendMultiline(target string, lines []string) {
	batchID := fmt.Sprintf("ml%d", time.Now().UnixNano()%10000)
	c.sendRaw(fmt.Sprintf("BATCH +%s draft/multiline %s", batchID, target))
	for i, line := range lines {
		if i < len(lines)-1 {
			c.sendRaw(fmt.Sprintf("@batch=%s;draft/multiline-concat PRIVMSG %s :%s", batchID, target, line))
		} else {
			c.sendRaw(fmt.Sprintf("@batch=%s PRIVMSG %s :%s", batchID, target, line))
		}
	}
	c.sendRaw("BATCH -" + batchID)
}

func (c *IRCCore) PreAway(msg string)       { c.sendRaw("AWAY :" + msg) }
func (c *IRCCore) RequestExtendedIsupport()  { c.sendRaw("CAP REQ :draft/extended-isupport") }
func (c *IRCCore) GetNetworkIcon() string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.networkIcon
}

func (c *IRCCore) FilehostUpload(filename string) {
	c.sendRaw("FILEHOST UPLOAD " + filename)
}

// ── SASL Mechanisms (3) ──

// SASLScramSHA256 starts SCRAM-SHA-256 auth.
func (c *IRCCore) SASLScramSHA256(username, password string) {
	c.sendRaw("AUTHENTICATE SCRAM-SHA-256")
	// The server will respond with a challenge; the actual SCRAM
	// exchange must happen in the message handler, but we store creds.
	c.mu.Lock()
	c.saslUser = username
	c.saslPass = password
	c.saslMech = "SCRAM-SHA-256"
	c.mu.Unlock()
}

// SASLExternal starts EXTERNAL auth (client certificate).
func (c *IRCCore) SASLExternal() {
	c.sendRaw("AUTHENTICATE EXTERNAL")
	c.sendRaw("AUTHENTICATE +")
}

// SASLECDSAChallenge starts ECDSA challenge-response auth.
func (c *IRCCore) SASLECDSAChallenge(accountName string) {
	c.sendRaw("AUTHENTICATE ECDSA-NIST256P-CHALLENGE")
	encoded := base64.StdEncoding.EncodeToString([]byte(accountName + "\x00" + accountName))
	c.sendRaw("AUTHENTICATE " + encoded)
}

// ── DCC Extensions (2) ──

// DCCReverse initiates passive/reverse DCC (port 0 for NAT traversal).
func (c *IRCCore) DCCReverse(nick, filename string, size int64, token string) {
	c.sendRaw(fmt.Sprintf("PRIVMSG %s :\x01DCC SEND %s 0 0 %d %s\x01",
		nick, filename, size, token))
}

// RDCC initiates an advanced DCC Server handshake.
func (c *IRCCore) RDCC(nick string) {
	c.sendRaw(fmt.Sprintf("PRIVMSG %s :\x01RDCC\x01", nick))
}

// ── Extended Bans — Helpers (18 types) ──

func (c *IRCCore) ExtbanTimed(channel, duration, banMask string) {
	c.sendRaw(fmt.Sprintf("MODE %s +b ~t:%s:%s", channel, duration, banMask))
}
func (c *IRCCore) ExtbanQuiet(channel, mask string) {
	c.sendRaw(fmt.Sprintf("MODE %s +b ~q:%s", channel, mask))
}
func (c *IRCCore) ExtbanNickchange(channel, mask string) {
	c.sendRaw(fmt.Sprintf("MODE %s +b ~n:%s", channel, mask))
}
func (c *IRCCore) ExtbanJoin(channel, mask string) {
	c.sendRaw(fmt.Sprintf("MODE %s +b ~j:%s", channel, mask))
}
func (c *IRCCore) ExtbanForward(channel, mask, target string) {
	c.sendRaw(fmt.Sprintf("MODE %s +b ~f:%s:%s", channel, target, mask))
}
func (c *IRCCore) ExtbanMsgbypass(channel, mask string) {
	c.sendRaw(fmt.Sprintf("MODE %s +e ~m:%s", channel, mask))
}
func (c *IRCCore) ExtbanFlood(channel, mask string) {
	c.sendRaw(fmt.Sprintf("MODE %s +e ~F:%s", channel, mask))
}
func (c *IRCCore) ExtbanAccount(channel, account string) {
	c.sendRaw(fmt.Sprintf("MODE %s +b ~a:%s", channel, account))
}
func (c *IRCCore) ExtbanASN(channel string, asn int) {
	c.sendRaw(fmt.Sprintf("MODE %s +b ~A:%d", channel, asn))
}
func (c *IRCCore) ExtbanChannel(channel, bannedChannel string) {
	c.sendRaw(fmt.Sprintf("MODE %s +b ~c:%s", channel, bannedChannel))
}
func (c *IRCCore) ExtbanCountry(channel, countryCode string) {
	c.sendRaw(fmt.Sprintf("MODE %s +b ~C:%s", channel, countryCode))
}
func (c *IRCCore) ExtbanSecurityGroup(channel, group string) {
	c.sendRaw(fmt.Sprintf("MODE %s +b ~G:%s", channel, group))
}
func (c *IRCCore) ExtbanOperclass(channel, operClass string) {
	c.sendRaw(fmt.Sprintf("MODE %s +b ~O:%s", channel, operClass))
}
func (c *IRCCore) ExtbanRealname(channel, realname string) {
	c.sendRaw(fmt.Sprintf("MODE %s +b ~r:%s", channel, realname))
}
func (c *IRCCore) ExtbanCertFP(channel, fingerprint string) {
	c.sendRaw(fmt.Sprintf("MODE %s +b ~S:%s", channel, fingerprint))
}
func (c *IRCCore) ExtbanInherit(channel, sourceChannel string) {
	c.sendRaw(fmt.Sprintf("MODE %s +b ~i:%s", channel, sourceChannel))
}
func (c *IRCCore) ExtbanText(channel, pattern string) {
	c.sendRaw(fmt.Sprintf("MODE %s +b ~T:block:%s", channel, pattern))
}
func (c *IRCCore) ExtbanPartmsg(channel, mask string) {
	c.sendRaw(fmt.Sprintf("MODE %s +b ~p:%s", channel, mask))
}

// ── Channel Modes — Typed Methods (~20) ──

func (c *IRCCore) SetNoColors(channel string, on bool)           { c.chanMode(channel, 'c', on) }
func (c *IRCCore) SetNoCTCP(channel string, on bool)             { c.chanMode(channel, 'C', on) }
func (c *IRCCore) SetDelayedJoins(channel string, on bool)       { c.chanMode(channel, 'D', on) }
func (c *IRCCore) SetFloodProtection(channel string, params string) {
	c.sendRaw(fmt.Sprintf("MODE %s +f %s", channel, params))
}
func (c *IRCCore) SetWordFilter(channel string, on bool)         { c.chanMode(channel, 'g', on) }
func (c *IRCCore) SetCensor(channel string, on bool)             { c.chanMode(channel, 'G', on) }
func (c *IRCCore) SetChannelHistory(channel string, lines int, seconds int) {
	c.sendRaw(fmt.Sprintf("MODE %s +H %d:%d", channel, lines, seconds))
}
func (c *IRCCore) SetJoinThrottle(channel string, joins int, seconds int) {
	c.sendRaw(fmt.Sprintf("MODE %s +j %d:%d", channel, joins, seconds))
}
func (c *IRCCore) SetNoKnock(channel string, on bool)            { c.chanMode(channel, 'K', on) }
func (c *IRCCore) SetChannelRedirect(channel, target string) {
	c.sendRaw(fmt.Sprintf("MODE %s +L %s", channel, target))
}
func (c *IRCCore) SetRequireRegistered(channel string, on bool)  { c.chanMode(channel, 'R', on) }
func (c *IRCCore) SetRequireRegisteredSpeak(channel string, on bool) { c.chanMode(channel, 'M', on) }
func (c *IRCCore) SetNoNickChange(channel string, on bool)       { c.chanMode(channel, 'N', on) }
func (c *IRCCore) SetOperOnly(channel string, on bool)           { c.chanMode(channel, 'O', on) }
func (c *IRCCore) SetPermanent(channel string, on bool)          { c.chanMode(channel, 'P', on) }
func (c *IRCCore) SetNoKicks(channel string, on bool)            { c.chanMode(channel, 'Q', on) }
func (c *IRCCore) SetStripColors(channel string, on bool)        { c.chanMode(channel, 'S', on) }
func (c *IRCCore) SetNoNotices(channel string, on bool)          { c.chanMode(channel, 'T', on) }
func (c *IRCCore) SetAuditorium(channel string, on bool)         { c.chanMode(channel, 'u', on) }
func (c *IRCCore) SetNoInvite(channel string, on bool)           { c.chanMode(channel, 'V', on) }
func (c *IRCCore) SetSSLOnly(channel string, on bool)            { c.chanMode(channel, 'z', on) }

func (c *IRCCore) chanMode(channel string, mode byte, on bool) {
	prefix := "+"
	if !on {
		prefix = "-"
	}
	c.sendRaw(fmt.Sprintf("MODE %s %s%c", channel, prefix, mode))
}

// ── User Modes — Typed Methods (~10) ──

func (c *IRCCore) userMode(mode byte, on bool) {
	prefix := "+"
	if !on {
		prefix = "-"
	}
	c.sendRaw(fmt.Sprintf("MODE %s %s%c", c.nick, prefix, mode))
}

func (c *IRCCore) SetBotMode(on bool)              { c.userMode('B', on) }
func (c *IRCCore) SetDeafMode(on bool)              { c.userMode('d', on) }
func (c *IRCCore) SetCallerID(on bool)              { c.userMode('g', on) }
func (c *IRCCore) SetHideOper(on bool)              { c.userMode('H', on) }
func (c *IRCCore) SetHideChannels(on bool)          { c.userMode('I', on) }
func (c *IRCCore) SetBlockUnregistered(on bool)     { c.userMode('R', on) }
func (c *IRCCore) SetBlockCTCP(on bool)             { c.userMode('T', on) }
func (c *IRCCore) SetWhoisNotify(on bool)           { c.userMode('W', on) }
func (c *IRCCore) SetRequireSSL(on bool)            { c.userMode('Z', on) }

// ── ACCEPT Command (1) ──

func (c *IRCCore) Accept(args string) { c.sendRaw("ACCEPT " + args) }

// ── IRC Formatting Helpers (4 groups) ──

const (
	ircFmtBold          = "\x02"
	ircFmtItalic        = "\x1D"
	ircFmtUnderline     = "\x1F"
	ircFmtStrikethrough = "\x1E"
	ircFmtMonospace     = "\x11"
	ircFmtColor         = "\x03"
	ircFmtHexColor      = "\x04"
	ircFmtReset         = "\x0F"
)

func FormatBold(text string)          string { return ircFmtBold + text + ircFmtBold }
func FormatItalic(text string)        string { return ircFmtItalic + text + ircFmtItalic }
func FormatUnderline(text string)     string { return ircFmtUnderline + text + ircFmtUnderline }
func FormatStrikethrough(text string) string { return ircFmtStrikethrough + text + ircFmtStrikethrough }
func FormatMonospace(text string)     string { return ircFmtMonospace + text + ircFmtMonospace }
func FormatColor(text string, fg, bg int) string {
	if bg >= 0 {
		return fmt.Sprintf("%s%02d,%02d%s%s", ircFmtColor, fg, bg, text, ircFmtColor)
	}
	return fmt.Sprintf("%s%02d%s%s", ircFmtColor, fg, text, ircFmtColor)
}
func FormatReset() string { return ircFmtReset }

func StripFormatting(text string) string {
	var result strings.Builder
	i := 0
	for i < len(text) {
		ch := text[i]
		switch ch {
		case 0x02, 0x1D, 0x1F, 0x1E, 0x11, 0x0F:
			i++
		case 0x03: // mIRC color
			i++
			for j := 0; j < 2 && i < len(text) && text[i] >= '0' && text[i] <= '9'; j++ {
				i++
			}
			if i < len(text) && text[i] == ',' {
				i++
				for j := 0; j < 2 && i < len(text) && text[i] >= '0' && text[i] <= '9'; j++ {
					i++
				}
			}
		case 0x04: // hex color
			i++
			for j := 0; j < 6 && i < len(text) && ((text[i] >= '0' && text[i] <= '9') ||
				(text[i] >= 'a' && text[i] <= 'f') || (text[i] >= 'A' && text[i] <= 'F')); j++ {
				i++
			}
		default:
			result.WriteByte(ch)
			i++
		}
	}
	return result.String()
}

// ParseColors returns color code positions in text.
func ParseColors(text string) []map[string]interface{} {
	var colors []map[string]interface{}
	for i := 0; i < len(text); i++ {
		if text[i] == 0x03 {
			pos := i
			i++
			fg := ""
			for j := 0; j < 2 && i < len(text) && text[i] >= '0' && text[i] <= '9'; j++ {
				fg += string(text[i])
				i++
			}
			bg := ""
			if i < len(text) && text[i] == ',' {
				i++
				for j := 0; j < 2 && i < len(text) && text[i] >= '0' && text[i] <= '9'; j++ {
					bg += string(text[i])
					i++
				}
			}
			colors = append(colors, map[string]interface{}{
				"pos": pos, "fg": fg, "bg": bg,
			})
			i-- // loop will increment
		}
	}
	return colors
}

func FormatHexColor(text, rrggbb string) string {
	return ircFmtHexColor + rrggbb + text + ircFmtHexColor
}

// ── Connection/Transport (5) ──

func (c *IRCCore) ConnectSOCKS(proxyAddr, targetAddr string) error {
	// SOCKS5 connect
	conn, err := net.DialTimeout("tcp", proxyAddr, 10*time.Second)
	if err != nil {
		return fmt.Errorf("irc: SOCKS connect %s: %w", proxyAddr, err)
	}
	// SOCKS5 handshake: version=5, 1 method, no auth
	conn.Write([]byte{0x05, 0x01, 0x00})
	buf := make([]byte, 2)
	conn.Read(buf)
	if buf[0] != 0x05 || buf[1] != 0x00 {
		conn.Close()
		return fmt.Errorf("irc: SOCKS handshake failed")
	}
	// Connect request
	host, portStr, _ := net.SplitHostPort(targetAddr)
	port, _ := strconv.Atoi(portStr)
	req := []byte{0x05, 0x01, 0x00, 0x03, byte(len(host))}
	req = append(req, []byte(host)...)
	req = append(req, byte(port>>8), byte(port&0xff))
	conn.Write(req)
	reply := make([]byte, 10)
	conn.Read(reply)
	if reply[1] != 0x00 {
		conn.Close()
		return fmt.Errorf("irc: SOCKS connect refused: %d", reply[1])
	}
	c.mu.Lock()
	c.conn = conn
	c.mu.Unlock()
	return nil
}

func (c *IRCCore) ConnectHTTPProxy(proxyAddr, targetAddr string) error {
	conn, err := net.DialTimeout("tcp", proxyAddr, 10*time.Second)
	if err != nil {
		return fmt.Errorf("irc: HTTP proxy connect %s: %w", proxyAddr, err)
	}
	connectReq := fmt.Sprintf("CONNECT %s HTTP/1.1\r\nHost: %s\r\n\r\n", targetAddr, targetAddr)
	conn.Write([]byte(connectReq))
	buf := make([]byte, 1024)
	n, _ := conn.Read(buf)
	resp := string(buf[:n])
	if !strings.Contains(resp, "200") {
		conn.Close()
		return fmt.Errorf("irc: HTTP CONNECT failed: %s", strings.TrimSpace(resp))
	}
	c.mu.Lock()
	c.conn = conn
	c.mu.Unlock()
	return nil
}

// ParsePROXYProtocol parses a HAProxy PROXY header line.
func ParsePROXYProtocol(line string) (proto, srcIP, dstIP string, srcPort, dstPort int) {
	parts := strings.Fields(line)
	if len(parts) >= 6 && parts[0] == "PROXY" {
		proto = parts[1]
		srcIP = parts[2]
		dstIP = parts[3]
		srcPort, _ = strconv.Atoi(parts[4])
		dstPort, _ = strconv.Atoi(parts[5])
	}
	return
}

func (c *IRCCore) STSRemember(domain string, port int, duration time.Duration) {
	c.mu.Lock()
	c.stsPolicies[domain] = port
	c.mu.Unlock()
}

// ── CTCP Types (2) ──

func (c *IRCCore) CTCPErrMsg(nick, query, message string) {
	c.sendRaw(fmt.Sprintf("NOTICE %s :\x01ERRMSG %s :%s\x01", nick, query, message))
}

func (c *IRCCore) CTCPAvatar(nick, url string) {
	c.sendRaw(fmt.Sprintf("NOTICE %s :\x01AVATAR %s\x01", nick, url))
}
