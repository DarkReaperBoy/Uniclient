//go:build !js

package cores

import (
	"bufio"
	"context"
	"crypto/tls"
	"encoding/base64"
	"fmt"
	"net"
	"sort"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"uniclient/utils"
)

const ircPlatform = "irc"

const (
	ircMaxMsgLen    = 512
	ircMsgBufSize   = 500
	ircPingInterval = 90 * time.Second
	ircPongTimeout  = 30 * time.Second
	ircReconnDelay  = 5 * time.Second
	ircSendDelay    = 500 * time.Millisecond
)

type ircMsg struct {
	Tags    map[string]string
	Prefix  string
	Command string
	Params  []string
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

func ParseIRCMsg(line string) *ircMsg {
	m := &ircMsg{}

	if len(line) > 0 && line[0] == '@' {
		sp := strings.IndexByte(line, ' ')
		if sp < 0 {
			return nil
		}
		tagStr := line[1:sp]
		line = strings.TrimLeft(line[sp+1:], " ")
		m.Tags = make(map[string]string, 4)
		for {
			semi := strings.IndexByte(tagStr, ';')
			var tag string
			if semi < 0 {
				tag = tagStr
			} else {
				tag = tagStr[:semi]
			}
			if eq := strings.IndexByte(tag, '='); eq >= 0 {
				m.Tags[tag[:eq]] = tag[eq+1:]
			} else if tag != "" {
				m.Tags[tag] = ""
			}
			if semi < 0 {
				break
			}
			tagStr = tagStr[semi+1:]
		}
	}

	if len(line) > 0 && line[0] == ':' {
		sp := strings.IndexByte(line, ' ')
		if sp < 0 {
			return nil
		}
		m.Prefix = line[1:sp]
		line = strings.TrimLeft(line[sp+1:], " ")
	}

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

type ircChannel struct {
	Name    string
	Topic   string
	TopicBy string
	TopicAt time.Time
	Members map[string]string
	Modes   string
	Created time.Time
	URL     string
	Key     string
}

type IRCServerInfo struct {
	Network     string
	ServerName  string
	ServerVer   string
	UserModes   string
	ChanModes   string
	CaseMapping string
	ChanTypes   string
	Prefix      string
	MaxNickLen  int
	MaxChanLen  int
	MaxTopicLen int
	MaxTargets  int
	MaxModes    int
	MaxChannels int
	Raw         map[string]string
}

type IRCListEntry struct {
	Channel string
	Users   int
	Topic   string
}

type IRCWhoEntry struct {
	Channel  string
	User     string
	Host     string
	Server   string
	Nick     string
	Flags    string
	Hopcount int
	Realname string
}

type IRCWhowasEntry struct {
	Nick     string
	User     string
	Host     string
	Realname string
}

type IRCBanEntry struct {
	Mask  string
	SetBy string
	SetAt time.Time
}

type IRCUserhostEntry struct {
	Nick     string
	IsOper   bool
	IsAway   bool
	Hostname string
}

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

type IRCCore struct {
	mu     sync.RWMutex
	authed bool

	conn    net.Conn
	writer  *bufio.Writer
	writeMu sync.Mutex

	nick           string
	username       string
	realname       string
	server         string
	password       string
	serverPassword string
	useTLS         bool
	useSASL        bool

	channels   map[string]*ircChannel
	channelsMu sync.RWMutex

	dmPartners   map[string]bool
	dmPartnersMu sync.RWMutex

	messages   map[string][]*Message
	messagesMu sync.RWMutex
	msgCounter atomic.Int64

	pinned   map[string]map[string]bool
	pinnedMu sync.RWMutex

	readState   map[string]*ReadState
	readStateMu sync.RWMutex

	blocked   map[string]bool
	blockedMu sync.RWMutex

	whoisCache   map[string]*User
	whoisCacheMu sync.RWMutex
	whoisWait    map[string]chan struct{}
	whoisWaitMu  sync.Mutex

	updateHandlers []func(Update)
	updateMu       sync.RWMutex

	session *utils.SessionStore
	ctx     context.Context
	cancel  context.CancelFunc
	wg      sync.WaitGroup

	registered chan struct{}
	saslDone   chan struct{}
	capDone    chan struct{}

	banReason string

	lastSend   time.Time
	lastSendMu sync.Mutex

	autoJoin []string

	serverInfo   IRCServerInfo
	serverInfoMu sync.RWMutex

	motd   []string
	motdMu sync.RWMutex

	awayMsg string
	awayMu  sync.RWMutex

	enabledCaps   map[string]bool
	enabledCapsMu sync.RWMutex

	listResult []IRCListEntry
	listDone   chan struct{}
	listMu     sync.Mutex

	whoResult []IRCWhoEntry
	whoDone   chan struct{}
	whoMu     sync.Mutex

	whowasResult []IRCWhowasEntry
	whowasDone   chan struct{}
	whowasMu     sync.Mutex

	banResult []IRCBanEntry
	banDone   chan struct{}
	banMu     sync.Mutex

	userhostResult []IRCUserhostEntry
	userhostDone   chan struct{}
	userhostMu     sync.Mutex

	isonResult []string
	isonDone   chan struct{}
	isonMu     sync.Mutex

	monitored   map[string]bool
	monitoredMu sync.RWMutex

	dccOffers   []IRCDCCOffer
	dccOffersMu sync.RWMutex

	reconnectEnabled bool
	reconnectCount   int
	reconnecting     bool

	stsPolicies         map[string]int
	wsURL               string
	extbanPrefix        string
	inviteNotifyHandler func(inviter, channel, target string)
	networkIcon         string
	saslUser            string
	saslPass            string
	saslMech            string
}

var _ Core = (*IRCCore)(nil)

func NewIRCCore(session *utils.SessionStore) *IRCCore {
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
		session:     session,
		ctx:         ctx,
		cancel:      cancel,
	}
}

func (c *IRCCore) Name() string { return ircPlatform }

func (c *IRCCore) Capabilities() []string {
	return []string{CapText, CapChannels, CapAdmin, CapSearch, CapBlocking, CapTyping}
}

func (c *IRCCore) Authenticate(cfg AuthConfig) error {
	c.mu.Lock()
	if c.authed {
		c.mu.Unlock()
		return nil
	}

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

	if err := c.connect(); err != nil {
		return fmt.Errorf("%w: %v", ErrAuth, err)
	}

	c.mu.Lock()
	c.authed = true
	c.reconnectEnabled = true
	if c.reconnectCount <= 0 {
		c.reconnectCount = 10
	}
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
	c.banReason = ""

	c.wg.Add(1)
	go c.readLoop()

	if c.useSASL {
		c.sendRaw("CAP LS 302")
	}
	if c.serverPassword != "" {
		c.sendRaw("PASS " + c.serverPassword)
	}
	c.sendRaw("NICK " + c.nick)
	c.sendRaw("USER " + c.username + " 0 * :" + c.realname)

	select {
	case <-c.registered:
		c.mu.RLock()
		ban := c.banReason
		c.mu.RUnlock()
		if ban != "" {
			conn.Close()
			return fmt.Errorf("%w: banned by server: %s", ErrAuth, ban)
		}
	case <-time.After(30 * time.Second):
		conn.Close()
		return fmt.Errorf("irc: registration timeout: %w", ErrTimeout)
	case <-c.ctx.Done():
		conn.Close()
		return c.ctx.Err()
	}

	if c.password != "" && !c.useSASL {
		c.sendRaw("PRIVMSG NickServ :IDENTIFY " + c.password)
		time.Sleep(2 * time.Second)
	}

	for _, ch := range c.autoJoin {
		if ch != "" {
			c.sendRaw("JOIN " + ch)
		}
	}

	c.wg.Add(1)
	go c.pingLoop()

	return nil
}

func (c *IRCCore) Logout() error {
	c.mu.Lock()
	defer c.mu.Unlock()
	if !c.authed {
		return nil
	}
	c.reconnectEnabled = false
	c.sendRaw("QUIT :Goodbye")
	c.authed = false
	c.cancel()
	if c.conn != nil {
		c.conn.Close()
	}
	return nil
}

func (c *IRCCore) sendRawErr(line string) error {
	c.writeMu.Lock()
	defer c.writeMu.Unlock()

	if c.writer == nil {
		return fmt.Errorf("%w: IRC connection lost", ErrDisconnected)
	}

	c.lastSendMu.Lock()
	since := time.Since(c.lastSend)
	if since < ircSendDelay {
		time.Sleep(ircSendDelay - since)
	}
	c.lastSend = time.Now()
	c.lastSendMu.Unlock()

	if len(line) > ircMaxMsgLen-2 {
		line = line[:ircMaxMsgLen-2]
	}

	if _, err := c.writer.WriteString(line); err != nil {
		return fmt.Errorf("%w: %v", ErrDisconnected, err)
	}
	if _, err := c.writer.WriteString("\r\n"); err != nil {
		return fmt.Errorf("%w: %v", ErrDisconnected, err)
	}
	if err := c.writer.Flush(); err != nil {
		return fmt.Errorf("%w: %v", ErrDisconnected, err)
	}
	return nil
}

func (c *IRCCore) sendRaw(line string) {
	c.writeMu.Lock()
	defer c.writeMu.Unlock()

	if c.writer == nil {
		return
	}

	c.lastSendMu.Lock()
	since := time.Since(c.lastSend)
	if since < ircSendDelay {
		time.Sleep(ircSendDelay - since)
	}
	c.lastSend = time.Now()
	c.lastSendMu.Unlock()

	if len(line) > ircMaxMsgLen-2 {
		line = line[:ircMaxMsgLen-2]
	}

	c.writer.WriteString(line)
	c.writer.WriteString("\r\n")
	c.writer.Flush()
}

func (c *IRCCore) readLoop() {
	defer c.wg.Done()
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

		msg := ParseIRCMsg(line)
		if msg == nil {
			continue
		}

		c.handleMessage(msg)
	}

	select {
	case <-c.ctx.Done():
		return
	default:
	}

	offline := false
	c.fireUpdate(Update{
		Type:     UpdateConnectivity,
		IsOnline: &offline,
		Platform: ircPlatform,
	})

	c.mu.RLock()
	shouldReconnect := c.reconnectEnabled
	maxRetries := c.reconnectCount
	c.mu.RUnlock()

	if !shouldReconnect {
		return
	}
	if maxRetries <= 0 {
		maxRetries = 10
	}

	go c.reconnectLoop(maxRetries)
}

func (c *IRCCore) reconnectLoop(maxRetries int) {
	c.mu.Lock()
	if c.reconnecting {
		c.mu.Unlock()
		return
	}
	c.reconnecting = true
	c.mu.Unlock()

	defer func() {
		c.mu.Lock()
		c.reconnecting = false
		c.mu.Unlock()
	}()

	delay := 3 * time.Second
	const maxDelay = 60 * time.Second

	for attempt := 1; attempt <= maxRetries; attempt++ {
		select {
		case <-c.ctx.Done():
			return
		case <-time.After(delay):
		}

		c.mu.Lock()
		if c.conn != nil {
			c.conn.Close()
			c.conn = nil
		}
		c.writer = nil
		c.mu.Unlock()

		c.channelsMu.RLock()
		var rejoinChannels []string
		for _, ch := range c.channels {
			rejoinChannels = append(rejoinChannels, ch.Name)
		}
		c.channelsMu.RUnlock()

		var conn net.Conn
		var err error
		dialer := &net.Dialer{Timeout: 15 * time.Second}

		c.mu.RLock()
		server := c.server
		useTLS := c.useTLS
		c.mu.RUnlock()

		if useTLS {
			host, _, _ := net.SplitHostPort(server)
			conn, err = tls.DialWithDialer(dialer, "tcp", server, &tls.Config{
				ServerName: host,
			})
		} else {
			conn, err = dialer.DialContext(c.ctx, "tcp", server)
		}

		if err != nil {
			delay *= 2
			if delay > maxDelay {
				delay = maxDelay
			}
			continue
		}

		c.mu.Lock()
		c.conn = conn
		c.writer = bufio.NewWriter(conn)
		c.registered = make(chan struct{})
		c.saslDone = make(chan struct{})
		c.capDone = make(chan struct{})
		c.banReason = ""
		nick := c.nick
		username := c.username
		realname := c.realname
		password := c.password
		serverPassword := c.serverPassword
		useSASL := c.useSASL
		c.mu.Unlock()

		c.wg.Add(1)
		go c.readLoop()

		if useSASL {
			c.sendRaw("CAP LS 302")
		}
		if serverPassword != "" {
			c.sendRaw("PASS " + serverPassword)
		}
		c.sendRaw("NICK " + nick)
		c.sendRaw("USER " + username + " 0 * :" + realname)

		select {
		case <-c.registered:
			c.mu.RLock()
			banned := c.banReason != ""
			c.mu.RUnlock()
			if banned {
				return
			}
		case <-time.After(30 * time.Second):
			c.mu.Lock()
			if c.conn != nil {
				c.conn.Close()
				c.conn = nil
			}
			c.mu.Unlock()
			delay *= 2
			if delay > maxDelay {
				delay = maxDelay
			}
			continue
		case <-c.ctx.Done():
			return
		}

		if password != "" && !useSASL {
			c.sendRaw("PRIVMSG NickServ :IDENTIFY " + password)
			time.Sleep(2 * time.Second)
		}

		for _, ch := range rejoinChannels {
			if ch != "" {
				c.sendRaw("JOIN " + ch)
			}
		}

		c.wg.Add(1)
		go c.pingLoop()

		online := true
		c.fireUpdate(Update{
			Type:     UpdateConnectivity,
			IsOnline: &online,
			Platform: ircPlatform,
		})

		return
	}

}

func (c *IRCCore) handleMessage(msg *ircMsg) {
	switch msg.Command {
	case "001":
		if len(msg.Params) > 0 {
			c.mu.Lock()
			c.nick = msg.Params[0]
			c.mu.Unlock()
		}
		select {
		case <-c.registered:
		default:
			close(c.registered)
		}

	case "433":
		c.mu.Lock()
		c.nick = c.nick + "_"
		c.mu.Unlock()
		c.sendRaw("NICK " + c.nick)

	case "465":
		c.mu.Lock()
		c.banReason = msg.Trailing()
		c.mu.Unlock()
		select {
		case <-c.registered:
		default:
			close(c.registered)
		}
		c.mu.RLock()
		if c.conn != nil {
			c.conn.Close()
			c.conn = nil
		}
		c.mu.RUnlock()

	case "CAP":
		c.handleCAP(msg)
	case "AUTHENTICATE":
		c.handleAuthenticate(msg)
	case "903":
		c.sendRaw("CAP END")
	case "904", "905":
		c.sendRaw("CAP END")

	case "PING":
		c.sendRaw("PONG :" + msg.Trailing())

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

	case "353":
		c.handleNamesReply(msg)
	case "366":

	case "TOPIC":
		c.handleTopicChange(msg)
	case "332":
		c.handleTopicReply(msg)
	case "333":
		c.handleTopicWhoTime(msg)

	case "324":
		c.handleChannelMode(msg)
	case "329":
		c.handleCreationTime(msg)

	case "311":
		c.handleWhoisUser(msg)
	case "312":
		c.handleWhoisServer(msg)
	case "313":
		c.handleWhoisOper(msg)
	case "317":
		c.handleWhoisIdle(msg)
	case "318":
		c.handleWhoisEnd(msg)
	case "319":
		c.handleWhoisChannels(msg)
	case "330":
		c.handleWhoisAccount(msg)

	case "314":
		c.handleWhowasUser(msg)
	case "369":
		c.handleWhowasEnd(msg)

	case "352":
		c.handleWhoReply(msg)
	case "315":
		c.handleWhoEnd(msg)

	case "322":
		c.handleListEntry(msg)
	case "323":
		c.handleListEnd(msg)

	case "367":
		c.handleBanListEntry(msg)
	case "368":
		c.handleBanListEnd(msg)

	case "348":
		c.handleBanListEntry(msg)
	case "349":
		c.handleBanListEnd(msg)

	case "346":
		c.handleBanListEntry(msg)
	case "347":
		c.handleBanListEnd(msg)

	case "364":
	case "365":

	case "271":
	case "272":

	case "600":
		c.handleWatchEvent(msg, true)
	case "601":
		c.handleWatchEvent(msg, false)
	case "602":
	case "604":
		c.handleWatchEvent(msg, true)
	case "605":
		c.handleWatchEvent(msg, false)

	case "375":
		c.motdMu.Lock()
		c.motd = nil
		c.motdMu.Unlock()
	case "372":
		c.motdMu.Lock()
		c.motd = append(c.motd, msg.Trailing())
		c.motdMu.Unlock()
	case "376":

	case "004":
		c.handleMyInfo(msg)
	case "005":
		c.handleISupport(msg)

	case "302":
		c.handleUserhostReply(msg)

	case "303":
		c.handleIsonReply(msg)

	case "301":
		c.handleAwayReply(msg)
	case "305":
		c.awayMu.Lock()
		c.awayMsg = ""
		c.awayMu.Unlock()
	case "306":
	case "AWAY":
		c.handleAwayNotify(msg)

	case "221":

	case "381":

	case "401":
		c.handleErrorNumeric(msg)
	case "402":
		c.handleErrorNumeric(msg)
	case "403":
		c.handleErrorNumeric(msg)
	case "404":
		c.handleErrorNumeric(msg)
	case "405":
		c.handleErrorNumeric(msg)
	case "432":
		c.handleErrorNumeric(msg)
	case "442":
		c.handleErrorNumeric(msg)
	case "443":
		c.handleErrorNumeric(msg)
	case "461":
		c.handleErrorNumeric(msg)
	case "462":
		c.handleErrorNumeric(msg)
	case "471":
		c.handleErrorNumeric(msg)
	case "473":
		c.handleErrorNumeric(msg)
	case "474":
		c.handleErrorNumeric(msg)
	case "475":
		c.handleErrorNumeric(msg)
	case "481":
		c.handleErrorNumeric(msg)
	case "482":
		c.handleErrorNumeric(msg)

	case "730":
		c.handleMonitorOnline(msg)
	case "731":
		c.handleMonitorOffline(msg)
	case "732":
	case "733":
	case "734":

	case "ACCOUNT":
		c.handleAccountNotify(msg)
	case "CHGHOST":
	case "SETNAME":
	case "INVITE":
		c.handleInvite(msg)
	case "TAGMSG":
		c.handleTagMsg(msg)

	case "PRIVMSG":
		c.HandlePrivmsg(msg)
	case "NOTICE":
		c.HandleNotice(msg)

	case "MODE":
		c.handleMode(msg)

	case "328":
		c.handleChannelURL(msg)

	case "251", "252", "253", "254", "255", "265", "266":

	case "ERROR":
		c.handleServerError(msg)
	}
}

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
	case "NEW":
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
	case "DEL":
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
		payload := "\x00" + c.username + "\x00" + c.password
		encoded := base64.StdEncoding.EncodeToString([]byte(payload))
		c.sendRaw("AUTHENTICATE " + encoded)
	}
}

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

	c.mu.RLock()
	myNick := c.nick
	c.mu.RUnlock()
	if strings.EqualFold(nick, myNick) {
		c.sendRaw("TOPIC " + channel)
		c.sendRaw("MODE " + channel)
	}

	c.fireUpdate(Update{
		Type:     UpdateGroupMembers,
		ChatID:   channel,
		UserID:   nick,
		Platform: ircPlatform,
	})
}

func (c *IRCCore) handlePart(msg *ircMsg) {
	channel := ""
	if len(msg.Params) > 0 {
		channel = msg.Params[0]
	}
	nick := msg.Nick()
	chanLower := strings.ToLower(channel)

	c.mu.RLock()
	myNick := c.nick
	c.mu.RUnlock()

	c.channelsMu.Lock()
	if ch, ok := c.channels[chanLower]; ok {
		delete(ch.Members, nick)
	}
	if strings.EqualFold(nick, myNick) {
		delete(c.channels, chanLower)
	}
	c.channelsMu.Unlock()

	c.fireUpdate(Update{
		Type:     UpdateGroupMembers,
		ChatID:   channel,
		UserID:   nick,
		Platform: ircPlatform,
	})
}

func (c *IRCCore) handleKick(msg *ircMsg) {
	if len(msg.Params) < 2 {
		return
	}
	channel := msg.Params[0]
	kicked := msg.Params[1]
	chanLower := strings.ToLower(channel)

	c.mu.RLock()
	myNick := c.nick
	c.mu.RUnlock()

	c.channelsMu.Lock()
	if ch, ok := c.channels[chanLower]; ok {
		delete(ch.Members, kicked)
	}
	if strings.EqualFold(kicked, myNick) {
		delete(c.channels, chanLower)
	}
	c.channelsMu.Unlock()

	c.fireUpdate(Update{
		Type:     UpdateGroupMembers,
		ChatID:   channel,
		UserID:   kicked,
		Platform: ircPlatform,
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

	c.mu.Lock()
	if strings.EqualFold(oldNick, c.nick) {
		c.nick = newNick
	}
	c.mu.Unlock()

	c.channelsMu.Lock()
	for _, ch := range c.channels {
		if mode, ok := ch.Members[oldNick]; ok {
			delete(ch.Members, oldNick)
			ch.Members[newNick] = mode
		}
	}
	c.channelsMu.Unlock()

	oldNickLower := strings.ToLower(oldNick)
	c.dmPartnersMu.Lock()
	if c.dmPartners[oldNickLower] {
		delete(c.dmPartners, oldNickLower)
		c.dmPartners[strings.ToLower(newNick)] = true
	}
	c.dmPartnersMu.Unlock()
}

func (c *IRCCore) handleNamesReply(msg *ircMsg) {
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
		if name == "" {
			continue
		}
		mode := ""
		switch name[0] {
		case '@', '+', '%', '~', '&':
			mode = name[:1]
			name = name[1:]
		}
		ch.Members[name] = mode
	}
	c.channelsMu.Unlock()
}

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

func (c *IRCCore) handleChannelMode(msg *ircMsg) {
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
	if len(msg.Params) < 3 {
		return
	}
	channel := msg.Params[1]
	chanLower := strings.ToLower(channel)

	c.channelsMu.Lock()
	if ch, ok := c.channels[chanLower]; ok {
		if ts, err := strconv.ParseInt(msg.Params[2], 10, 64); err == nil && ts > 0 {
			ch.Created = time.Unix(ts, 0)
		}
	}
	c.channelsMu.Unlock()
}

func (c *IRCCore) handleMode(msg *ircMsg) {
	if len(msg.Params) < 2 {
		return
	}
	target := msg.Params[0]
	if !strings.HasPrefix(target, "#") && !strings.HasPrefix(target, "&") {
		return
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
		case 'o', 'v', 'h', 'q', 'a':
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
		case 'b', 'e', 'I':
			if paramIdx < len(modeParams) {
				paramIdx++
			}
		case 'k', 'l', 'j', 'f':
			if adding && paramIdx < len(modeParams) {
				paramIdx++
			}
		}
	}
	c.channelsMu.Unlock()

	c.fireUpdate(Update{
		Type:     UpdateGroupMembers,
		ChatID:   target,
		Platform: ircPlatform,
	})
}

func (c *IRCCore) handleWhoisUser(msg *ircMsg) {
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
		Platform:    ircPlatform,
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

const ircServerChat = "server"

func isServerOrigin(msg *ircMsg, target string) bool {
	if msg.Prefix != "" && !strings.Contains(msg.Prefix, "!") {
		return true
	}
	switch target {
	case "", "*", "AUTH":
		return true
	}
	return false
}

func (c *IRCCore) HandlePrivmsg(msg *ircMsg) {
	if len(msg.Params) < 1 {
		return
	}
	target := msg.Params[0]
	text := StripFormatting(msg.Trailing())
	nick := msg.Nick()

	if isServerOrigin(msg, target) {
		c.handleServerNotice(nick, text)
		return
	}

	if strings.HasPrefix(text, "\x01") && strings.HasSuffix(text, "\x01") {
		c.handleCTCP(msg, nick, target, text[1:len(text)-1])
		return
	}

	c.blockedMu.RLock()
	blocked := c.blocked[strings.ToLower(nick)]
	c.blockedMu.RUnlock()
	if blocked {
		return
	}

	c.mu.RLock()
	myNick := c.nick
	c.mu.RUnlock()

	chatID := target
	if strings.EqualFold(target, myNick) {
		chatID = nick
		c.dmPartnersMu.Lock()
		c.dmPartners[strings.ToLower(nick)] = true
		c.dmPartnersMu.Unlock()
	}

	ts := time.Now()
	if timeTag, ok := msg.Tags["time"]; ok {
		if parsed, err := time.Parse(time.RFC3339, timeTag); err == nil {
			ts = parsed
		}
	}

	id := c.msgCounter.Add(1)
	m := &Message{
		ID:         strconv.FormatInt(id, 10),
		ChatID:     chatID,
		SenderID:   nick,
		SenderName: nick,
		Text:       text,
		Timestamp:  ts,
		Platform:   ircPlatform,
		Status:     MessageStatusDelivered,
		IsOutgoing: strings.EqualFold(nick, myNick),
	}

	if msgID, ok := msg.Tags["msgid"]; ok {
		m.ID = msgID
	}

	c.bufferMessage(chatID, m)

	c.fireUpdate(Update{
		Type:     UpdateNewMessage,
		ChatID:   chatID,
		Message:  m,
		Platform: ircPlatform,
	})
}

func (c *IRCCore) HandleNotice(msg *ircMsg) {
	if len(msg.Params) < 1 {
		return
	}
	target := msg.Params[0]
	text := StripFormatting(msg.Trailing())
	nick := msg.Nick()

	c.mu.RLock()
	myNick := c.nick
	c.mu.RUnlock()

	if isServerOrigin(msg, target) {
		c.handleServerNotice(nick, text)
		return
	}

	chatID := target
	if strings.EqualFold(target, myNick) {
		chatID = nick
	}

	id := c.msgCounter.Add(1)
	m := &Message{
		ID:         strconv.FormatInt(id, 10),
		ChatID:     chatID,
		SenderID:   nick,
		SenderName: nick,
		Text:       "[NOTICE] " + text,
		Timestamp:  time.Now(),
		Platform:   ircPlatform,
		Status:     MessageStatusDelivered,
		IsOutgoing: strings.EqualFold(nick, myNick),
	}
	c.bufferMessage(chatID, m)

	c.fireUpdate(Update{
		Type:     UpdateNewMessage,
		ChatID:   chatID,
		Message:  m,
		Platform: ircPlatform,
	})
}

func (c *IRCCore) handleServerNotice(serverName, text string) {
	if text == "" {
		return
	}
	if serverName == "" {
		serverName = "server"
	}
	id := c.msgCounter.Add(1)
	m := &Message{
		ID:         strconv.FormatInt(id, 10),
		ChatID:     ircServerChat,
		SenderID:   ircServerChat,
		SenderName: serverName,
		Text:       text,
		Timestamp:  time.Now(),
		Platform:   ircPlatform,
		Status:     MessageStatusDelivered,
		IsOutgoing: false,
		IsService:  true,
	}
	c.bufferMessage(ircServerChat, m)

	c.fireUpdate(Update{
		Type:     UpdateNewMessage,
		ChatID:   ircServerChat,
		Message:  m,
		Platform: ircPlatform,
	})
}

func (c *IRCCore) handleCTCP(msg *ircMsg, nick, target, ctcp string) {
	parts := strings.SplitN(ctcp, " ", 2)
	cmd := strings.ToUpper(parts[0])

	switch cmd {
	case "VERSION":
		c.sendRaw("NOTICE " + nick + " :\x01VERSION Uniclient IRC 1.0\x01")
	case "PING":
		c.sendRaw("NOTICE " + nick + " :\x01" + ctcp + "\x01")
	case "TIME":
		c.sendRaw("NOTICE " + nick + " :\x01TIME " + time.Now().Format(time.RFC1123) + "\x01")
	case "CLIENTINFO":
		c.sendRaw("NOTICE " + nick + " :\x01CLIENTINFO ACTION PING VERSION TIME CLIENTINFO FINGER USERINFO SOURCE DCC\x01")
	case "FINGER":
		c.mu.RLock()
		myNick := c.nick
		c.mu.RUnlock()
		c.sendRaw("NOTICE " + nick + " :\x01FINGER " + myNick + " (Uniclient IRC)\x01")
	case "USERINFO":
		c.mu.RLock()
		myNick := c.nick
		c.mu.RUnlock()
		c.sendRaw("NOTICE " + nick + " :\x01USERINFO " + myNick + "\x01")
	case "SOURCE":
		c.sendRaw("NOTICE " + nick + " :\x01SOURCE https://github.com/DarkReaperBoy/uniclient\x01")
	case "ACTION":
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

		id := c.msgCounter.Add(1)
		m := &Message{
			ID:         strconv.FormatInt(id, 10),
			ChatID:     chatID,
			SenderID:   nick,
			SenderName: nick,
			Text:       "* " + nick + " " + actionText,
			Timestamp:  time.Now(),
			Platform:   ircPlatform,
			Status:     MessageStatusDelivered,
			IsOutgoing: strings.EqualFold(nick, myNick),
		}
		c.bufferMessage(chatID, m)

		c.fireUpdate(Update{
			Type:     UpdateNewMessage,
			ChatID:   chatID,
			Message:  m,
			Platform: ircPlatform,
		})

	case "DCC":
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

		dccChatID := nick
		id := c.msgCounter.Add(1)
		dccMsg := &Message{
			ID:         strconv.FormatInt(id, 10),
			ChatID:     dccChatID,
			SenderID:   nick,
			SenderName: nick,
			Text:       "[DCC " + dccType + "] " + parts[1],
			Timestamp:  time.Now(),
			Platform:   ircPlatform,
			Status:     MessageStatusDelivered,
			IsOutgoing: false,
		}
		c.bufferMessage(dccChatID, dccMsg)
		c.fireUpdate(Update{
			Type:     UpdateNewMessage,
			ChatID:   dccChatID,
			Message:  dccMsg,
			Platform: ircPlatform,
		})
	}
}

func (c *IRCCore) pingLoop() {
	defer c.wg.Done()
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

func (c *IRCCore) fireUpdate(u Update) {
	c.updateMu.RLock()
	if len(c.updateHandlers) == 0 {
		c.updateMu.RUnlock()
		return
	}
	if len(c.updateHandlers) == 1 {
		h := c.updateHandlers[0]
		c.updateMu.RUnlock()
		h(u)
		return
	}
	handlers := make([]func(Update), len(c.updateHandlers))
	copy(handlers, c.updateHandlers)
	c.updateMu.RUnlock()

	for _, h := range handlers {
		h(u)
	}
}

func (c *IRCCore) GetDialogs(opts PaginationOpts) ([]Dialog, error) {
	if !c.authed {
		return nil, ErrAuth
	}

	var dialogs []Dialog

	c.messagesMu.RLock()
	if msgs, ok := c.messages[ircServerChat]; ok && len(msgs) > 0 {
		last := msgs[len(msgs)-1]
		dialogs = append(dialogs, Dialog{
			ID:          ircServerChat,
			Type:        ChatTypeChannel,
			Title:       "Server log",
			LastMessage: last,
			Platform:    ircPlatform,
		})
	}
	c.messagesMu.RUnlock()

	c.channelsMu.RLock()
	for _, ch := range c.channels {
		d := Dialog{
			ID:          ch.Name,
			Type:        ChatTypeGroup,
			Title:       ch.Name,
			MemberCount: len(ch.Members),
			Platform:    ircPlatform,
		}
		c.messagesMu.RLock()
		if msgs, ok := c.messages[ch.Name]; ok && len(msgs) > 0 {
			last := msgs[len(msgs)-1]
			d.LastMessage = last
		}
		c.messagesMu.RUnlock()
		dialogs = append(dialogs, d)
	}
	c.channelsMu.RUnlock()

	c.dmPartnersMu.RLock()
	for nick := range c.dmPartners {
		d := Dialog{
			ID:       nick,
			Type:     ChatTypeDM,
			Title:    nick,
			Platform: ircPlatform,
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

	if opts.Offset != "" {
		if off, err := strconv.Atoi(opts.Offset); err == nil && off > 0 {
			if off >= len(dialogs) {
				return []Dialog{}, nil
			}
			dialogs = dialogs[off:]
		}
	}
	if opts.Limit > 0 && len(dialogs) > opts.Limit {
		dialogs = dialogs[:opts.Limit]
	}

	if dialogs == nil {
		dialogs = []Dialog{}
	}
	return dialogs, nil
}

func (c *IRCCore) CreateGroup(name string, members []string) (*Dialog, error) {
	if !c.authed {
		return nil, ErrAuth
	}
	if !strings.HasPrefix(name, "#") {
		name = "#" + name
	}
	c.sendRaw("JOIN " + name)
	time.Sleep(time.Second)

	for _, m := range members {
		c.sendRaw("INVITE " + m + " " + name)
	}

	return &Dialog{
		ID:       name,
		Type:     ChatTypeGroup,
		Title:    name,
		Platform: ircPlatform,
	}, nil
}

func (c *IRCCore) CreateChannel(name string, description string) (*Dialog, error) {
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
	return nil, fmt.Errorf("%w: irc does not support forum topics", ErrNotSupported)
}

func (c *IRCCore) GetFolders() ([]Folder, error) {
	return nil, fmt.Errorf("%w: irc does not support folders", ErrNotSupported)
}

func (c *IRCCore) CreateFolder(_ string, _ []string) (*Folder, error) {
	return nil, fmt.Errorf("%w: irc does not support folders", ErrNotSupported)
}

func (c *IRCCore) SendMessage(chatID string, msg OutgoingMessage) (*Message, error) {
	if !c.authed {
		return nil, ErrAuth
	}

	text := msg.Text
	if text == "" {
		return nil, fmt.Errorf("%w: empty message", ErrInvalidInput)
	}

	maxLen := 400 - len(chatID)
	if maxLen < 100 {
		maxLen = 100
	}

	lines := strings.Split(text, "\n")
	var lastMsg *Message
	for _, line := range lines {
		if line == "" {
			continue
		}
		for len(line) > 0 {
			chunk := line
			if len(chunk) > maxLen {
				chunk = line[:maxLen]
				line = line[maxLen:]
			} else {
				line = ""
			}
			if err := c.sendRawErr("PRIVMSG " + chatID + " :" + chunk); err != nil {
				return nil, err
			}

			c.mu.RLock()
			myNick := c.nick
			c.mu.RUnlock()

			id := c.msgCounter.Add(1)
			lastMsg = &Message{
				ID:         strconv.FormatInt(id, 10),
				ChatID:     chatID,
				SenderID:   myNick,
				SenderName: myNick,
				Text:       chunk,
				Timestamp:  time.Now(),
				Platform:   ircPlatform,
				Status:     MessageStatusSent,
				IsOutgoing: true,
			}
			c.bufferMessage(chatID, lastMsg)
		}
	}

	if lastMsg == nil {
		return nil, fmt.Errorf("%w: empty message after splitting", ErrInvalidInput)
	}

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

	result := make([]Message, 0, len(buf))
	for _, m := range buf {
		result = append(result, *m)
	}

	if opts.Limit > 0 && len(result) > opts.Limit {
		result = result[len(result)-opts.Limit:]
	}

	return result, nil
}

func (c *IRCCore) EditMessage(_ string, _ string, _ string) (*Message, error) {
	return nil, fmt.Errorf("%w: irc does not support message editing", ErrNotSupported)
}

func (c *IRCCore) DeleteMessage(_ string, _ string) error {
	return fmt.Errorf("%w: irc does not support message deletion", ErrNotSupported)
}

func (c *IRCCore) ReplyToMessage(chatID string, replyToMsgID string, msg OutgoingMessage) (*Message, error) {
	if !c.authed {
		return nil, ErrAuth
	}

	text := msg.Text
	if replyToMsgID != "" {
		c.messagesMu.RLock()
		for _, m := range c.messages[chatID] {
			if m.ID == replyToMsgID {
				firstLine := m.Text
				if idx := strings.Index(firstLine, "\n"); idx > 0 {
					firstLine = firstLine[:idx]
				}
				if len(firstLine) > 80 {
					firstLine = utils.TruncateEllipsis(firstLine, 80)
				}
				text = "<" + m.SenderName + "> " + firstLine + " — " + msg.Text
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

	text := "[Fwd from " + original.SenderName + "] " + original.Text
	return c.SendMessage(toChatID, OutgoingMessage{Text: text})
}

func (c *IRCCore) ReactToMessage(_ string, _ string, _ string) error {
	return fmt.Errorf("%w: irc does not support reactions", ErrNotSupported)
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

func (c *IRCCore) MarkAsRead(chatID string, upToMsgID string) error {
	c.readStateMu.Lock()
	if c.readState[chatID] == nil {
		c.readState[chatID] = &ReadState{}
	}
	c.readState[chatID].MyLastRead = upToMsgID
	c.readStateMu.Unlock()
	c.MarkRead(chatID, upToMsgID)
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

func (c *IRCCore) UploadFile(_ string, _ FileUpload, _ func(int64, int64)) (*Message, error) {
	return nil, fmt.Errorf("%w: irc does not support file uploads", ErrNotSupported)
}

func (c *IRCCore) DownloadFile(_ FileRef, _ string, _ func(int64, int64)) error {
	return fmt.Errorf("%w: irc does not support file downloads", ErrNotSupported)
}

func (c *IRCCore) SendImageBase64(_ string, _ string, _ string) (*Message, error) {
	return nil, fmt.Errorf("%w: irc does not support base64 image sending", ErrNotSupported)
}

func (c *IRCCore) StartCall(_ string, _ bool) (*CallSession, error) {
	return nil, fmt.Errorf("%w: irc does not support calls", ErrNotSupported)
}

func (c *IRCCore) JoinGroupCall(_ string) (*CallSession, error) {
	return nil, fmt.Errorf("%w: irc does not support calls", ErrNotSupported)
}

func (c *IRCCore) EndCall(_ string) error {
	return fmt.Errorf("%w: irc does not support calls", ErrNotSupported)
}

func (c *IRCCore) SetCallMuted(_ string, _ bool) error {
	return fmt.Errorf("%w: irc does not support calls", ErrNotSupported)
}

func (c *IRCCore) ToggleCamera(_ string, _ bool) error {
	return fmt.Errorf("%w: irc does not support calls", ErrNotSupported)
}

func (c *IRCCore) GetProfile(userID string) (*User, error) {
	if !c.authed {
		return nil, ErrAuth
	}

	if userID == "" {
		userID = c.nick
	}

	nickLower := strings.ToLower(userID)

	c.whoisCacheMu.RLock()
	if user, ok := c.whoisCache[nickLower]; ok {
		c.whoisCacheMu.RUnlock()
		return user, nil
	}
	c.whoisCacheMu.RUnlock()

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

func (c *IRCCore) OnUpdate(handler func(Update)) {
	c.updateMu.Lock()
	c.updateHandlers = append(c.updateHandlers, handler)
	c.updateMu.Unlock()
}

func (c *IRCCore) Close() error {
	c.mu.Lock()
	if c.authed {
		c.saveSession()
		c.sendRaw("QUIT :Goodbye")
	}
	c.cancel()
	if c.conn != nil {
		c.conn.Close()
	}
	c.authed = false
	c.mu.Unlock()
	c.wg.Wait()
	return nil
}

func (c *IRCCore) GetChatInfo(chatID string) (*Dialog, error) {
	if !c.authed {
		return nil, ErrAuth
	}

	if !strings.HasPrefix(chatID, "#") && !strings.HasPrefix(chatID, "&") {
		return &Dialog{
			ID:       chatID,
			Type:     ChatTypeDM,
			Title:    chatID,
			Platform: ircPlatform,
		}, nil
	}

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
		Platform:    ircPlatform,
	}, nil
}

func (c *IRCCore) EditChatTitle(_ string, _ string) error {
	return fmt.Errorf("%w: irc channel names are immutable", ErrNotSupported)
}

func (c *IRCCore) EditChatDescription(chatID string, description string) error {
	if !c.authed {
		return ErrAuth
	}
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
		c.dmPartnersMu.Lock()
		delete(c.dmPartners, strings.ToLower(chatID))
		c.dmPartnersMu.Unlock()
	}
	return nil
}

func (c *IRCCore) GetInviteLink(_ string) (string, error) {
	return "", fmt.Errorf("%w: irc does not support invite links", ErrNotSupported)
}

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
			Platform:    ircPlatform,
		})
	}
	c.channelsMu.RUnlock()

	sort.Slice(users, func(i, j int) bool {
		return users[i].ID < users[j].ID
	})

	if opts.Limit > 0 && len(users) > opts.Limit {
		users = users[:opts.Limit]
	}

	if users == nil {
		users = []User{}
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

func (c *IRCCore) GetContacts() ([]User, error) {
	return nil, fmt.Errorf("%w: irc does not support contacts", ErrNotSupported)
}

func (c *IRCCore) AddContact(_ string, _ string, _ string) error {
	return fmt.Errorf("%w: irc does not support contacts", ErrNotSupported)
}

func (c *IRCCore) DeleteContact(_ string) error {
	return fmt.Errorf("%w: irc does not support contacts", ErrNotSupported)
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
			Platform: ircPlatform,
		})
	}
	if users == nil {
		users = []User{}
	}
	return users, nil
}

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

	if results == nil {
		results = []Message{}
	}
	return results, nil
}

func (c *IRCCore) SearchGlobal(query string, opts PaginationOpts) ([]Dialog, error) {
	if !c.authed {
		return nil, ErrAuth
	}

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
				Platform:    ircPlatform,
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
				Platform: ircPlatform,
			})
		}
	}
	c.dmPartnersMu.RUnlock()

	if opts.Limit > 0 && len(results) > opts.Limit {
		results = results[:opts.Limit]
	}

	if results == nil {
		results = []Dialog{}
	}
	return results, nil
}

func (c *IRCCore) SendTyping(chatID string) error {
	c.SendTypingIndicator(chatID, true)
	return nil
}

func (c *IRCCore) CreatePoll(_ string, _ string, _ []string) (*Message, error) {
	return nil, fmt.Errorf("%w: irc does not support polls", ErrNotSupported)
}

func (c *IRCCore) VotePoll(_ string, _ string, _ int) error {
	return fmt.Errorf("%w: irc does not support polls", ErrNotSupported)
}

func (c *IRCCore) SendSticker(_ string, _ string) (*Message, error) {
	return nil, fmt.Errorf("%w: irc does not support stickers", ErrNotSupported)
}

func (c *IRCCore) GetSessions() ([]Session, error) {
	return nil, fmt.Errorf("%w: irc does not support session management", ErrNotSupported)
}

func (c *IRCCore) TerminateSession(_ string) error {
	return fmt.Errorf("%w: irc does not support session management", ErrNotSupported)
}

func (c *IRCCore) handleMyInfo(msg *ircMsg) {
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
}

func (c *IRCCore) handleWhoisOper(msg *ircMsg) {
	if len(msg.Params) < 2 {
		return
	}
	nick := strings.ToLower(msg.Params[1])
	c.whoisCacheMu.Lock()
	if user, ok := c.whoisCache[nick]; ok {
		_ = user
	}
	c.whoisCacheMu.Unlock()
}

func (c *IRCCore) handleWhoisIdle(msg *ircMsg) {
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
}

func (c *IRCCore) handleWhoisAccount(msg *ircMsg) {
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
	c.fireUpdate(Update{
		Type:     UpdateUserStatus,
		UserID:   nick,
		IsOnline: &notAway,
		Platform: ircPlatform,
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
		c.fireUpdate(Update{
			Type:     UpdateNewMessage,
			ChatID:   channel,
			UserID:   nick,
			Platform: ircPlatform,
			Message: &Message{
				ChatID:     channel,
				SenderID:   nick,
				SenderName: nick,
				Text:       nick + " invited you to " + channel,
				Timestamp:  time.Now(),
				Platform:   ircPlatform,
				Status:     MessageStatusDelivered,
				IsOutgoing: false,
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
		c.fireUpdate(Update{
			Type:     UpdateUserStatus,
			UserID:   nick,
			IsOnline: &online,
			Platform: ircPlatform,
		})
	}
}

func (c *IRCCore) handleMonitorOffline(msg *ircMsg) {
	nicks := strings.Split(msg.Trailing(), ",")
	for _, nick := range nicks {
		offline := false
		c.fireUpdate(Update{
			Type:     UpdateUserStatus,
			UserID:   strings.TrimSpace(nick),
			IsOnline: &offline,
			Platform: ircPlatform,
		})
	}
}

func (c *IRCCore) handleTagMsg(msg *ircMsg) {
	nick := msg.Nick()
	if nick == "" {
		return
	}

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

		c.fireUpdate(Update{
			Type:     UpdateTyping,
			ChatID:   chatID,
			UserID:   nick,
			Platform: ircPlatform,
		})
	}

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
		id := c.msgCounter.Add(1)
		reactMsg := &Message{
			ID:         strconv.FormatInt(id, 10),
			ChatID:     chatID,
			SenderID:   nick,
			SenderName: nick,
			Text:       "[React: " + reaction + " to " + replyTo + "]",
			Timestamp:  time.Now(),
			Platform:   ircPlatform,
			Status:     MessageStatusDelivered,
			IsOutgoing: strings.EqualFold(nick, myNick),
		}
		c.bufferMessage(chatID, reactMsg)
		c.fireUpdate(Update{
			Type:     UpdateNewMessage,
			ChatID:   chatID,
			Message:  reactMsg,
			Platform: ircPlatform,
		})
	}
}

func (c *IRCCore) handleWatchEvent(msg *ircMsg, online bool) {
	if len(msg.Params) < 2 {
		return
	}
	nick := msg.Params[1]
	c.fireUpdate(Update{
		Type:     UpdateUserStatus,
		UserID:   nick,
		IsOnline: &online,
		Platform: ircPlatform,
	})
}

func (c *IRCCore) handleErrorNumeric(msg *ircMsg) {
	text := StripFormatting(msg.Trailing())
	if text == "" && len(msg.Params) > 1 {
		text = strings.Join(msg.Params[1:], " ")
	}
	id := c.msgCounter.Add(1)
	m := &Message{
		ID:         strconv.FormatInt(id, 10),
		ChatID:     "*server*",
		SenderID:   msg.Prefix,
		SenderName: "Server",
		Text:       "[" + msg.Command + "] " + text,
		Timestamp:  time.Now(),
		Platform:   ircPlatform,
		Status:     MessageStatusDelivered,
		IsOutgoing: false,
	}
	c.bufferMessage("*server*", m)
}

func (c *IRCCore) handleServerError(msg *ircMsg) {
	text := StripFormatting(msg.Trailing())
	id := c.msgCounter.Add(1)
	m := &Message{
		ID:         strconv.FormatInt(id, 10),
		ChatID:     "*server*",
		SenderID:   "server",
		SenderName: "Server",
		Text:       "[ERROR] " + text,
		Timestamp:  time.Now(),
		Platform:   ircPlatform,
		Status:     MessageStatusDelivered,
		IsOutgoing: false,
	}
	c.bufferMessage("*server*", m)
}

func (c *IRCCore) GetNick() string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.nick
}

func (c *IRCCore) ChangeNick(newNick string) {
	c.sendRaw("NICK " + newNick)
}

func (c *IRCCore) SetName(realname string) {
	c.sendRaw("SETNAME :" + realname)
}

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

func (c *IRCCore) GetAway() string {
	c.awayMu.RLock()
	defer c.awayMu.RUnlock()
	return c.awayMsg
}

func (c *IRCCore) Oper(name, password string) {
	c.sendRaw("OPER " + name + " " + password)
}

func (c *IRCCore) QuitMessage(message string) {
	if message == "" {
		message = "Goodbye"
	}
	c.sendRaw("QUIT :" + message)
}

func (c *IRCCore) SendRawCommand(line string) {
	c.sendRaw(line)
}

func (c *IRCCore) JoinKey(channel, key string) {
	c.sendRaw("JOIN " + channel + " " + key)
}

func (c *IRCCore) JoinMultiple(channels []string, keys []string) {
	chanStr := strings.Join(channels, ",")
	if len(keys) > 0 {
		c.sendRaw("JOIN " + chanStr + " " + strings.Join(keys, ","))
	} else {
		c.sendRaw("JOIN " + chanStr)
	}
}

func (c *IRCCore) PartMessage(channel, reason string) {
	if reason != "" {
		c.sendRaw("PART " + channel + " :" + reason)
	} else {
		c.sendRaw("PART " + channel)
	}
}

func (c *IRCCore) PartMultiple(channels []string, reason string) {
	chanStr := strings.Join(channels, ",")
	if reason != "" {
		c.sendRaw("PART " + chanStr + " :" + reason)
	} else {
		c.sendRaw("PART " + chanStr)
	}
}

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

func (c *IRCCore) SetMode(target, modes string, params ...string) {
	cmd := "MODE " + target + " " + modes
	if len(params) > 0 {
		cmd += " " + strings.Join(params, " ")
	}
	c.sendRaw(cmd)
}

func (c *IRCCore) Knock(channel string) {
	c.sendRaw("KNOCK " + channel)
}

func (c *IRCCore) RequestNames(channel string) {
	c.sendRaw("NAMES " + channel)
}

func (c *IRCCore) LeaveAllChannels() {
	c.sendRaw("JOIN 0")
}

func (c *IRCCore) SendNotice(target, text string) {
	c.sendRaw("NOTICE " + target + " :" + text)
}

func (c *IRCCore) SendAction(target, text string) {
	c.sendRaw("PRIVMSG " + target + " :\x01ACTION " + text + "\x01")
	c.mu.RLock()
	myNick := c.nick
	c.mu.RUnlock()
	id := c.msgCounter.Add(1)
	m := &Message{
		ID:         strconv.FormatInt(id, 10),
		ChatID:     target,
		SenderID:   myNick,
		SenderName: myNick,
		Text:       "* " + myNick + " " + text,
		Timestamp:  time.Now(),
		Platform:   ircPlatform,
		Status:     MessageStatusSent,
		IsOutgoing: true,
	}
	c.bufferMessage(target, m)
}

func (c *IRCCore) SendCTCP(target, command, params string) {
	if params != "" {
		c.sendRaw("PRIVMSG " + target + " :\x01" + command + " " + params + "\x01")
	} else {
		c.sendRaw("PRIVMSG " + target + " :\x01" + command + "\x01")
	}
}

func (c *IRCCore) SendCTCPReply(target, command, params string) {
	if params != "" {
		c.sendRaw("NOTICE " + target + " :\x01" + command + " " + params + "\x01")
	} else {
		c.sendRaw("NOTICE " + target + " :\x01" + command + "\x01")
	}
}

func (c *IRCCore) Wallops(message string) {
	c.sendRaw("WALLOPS :" + message)
}

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

func (c *IRCCore) RequestWhois(nick string) {
	c.sendRaw("WHOIS " + nick)
}

func (c *IRCCore) Whowas(nick string, count int) ([]IRCWhowasEntry, error) {
	c.whowasMu.Lock()
	c.whowasResult = nil
	c.whowasDone = make(chan struct{})
	done := c.whowasDone
	c.whowasMu.Unlock()

	if count > 0 {
		c.sendRaw("WHOWAS " + nick + " " + strconv.Itoa(count))
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

func (c *IRCCore) RequestMOTD() {
	c.sendRaw("MOTD")
}

func (c *IRCCore) GetMOTD() []string {
	c.motdMu.RLock()
	defer c.motdMu.RUnlock()
	result := make([]string, len(c.motd))
	copy(result, c.motd)
	return result
}

func (c *IRCCore) RequestVersion() {
	c.sendRaw("VERSION")
}

func (c *IRCCore) RequestTime() {
	c.sendRaw("TIME")
}

func (c *IRCCore) RequestAdmin() {
	c.sendRaw("ADMIN")
}

func (c *IRCCore) RequestInfo() {
	c.sendRaw("INFO")
}

func (c *IRCCore) RequestLusers() {
	c.sendRaw("LUSERS")
}

func (c *IRCCore) RequestStats(query string) {
	c.sendRaw("STATS " + query)
}

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

func (c *IRCCore) HasCapability(cap string) bool {
	c.enabledCapsMu.RLock()
	defer c.enabledCapsMu.RUnlock()
	return c.enabledCaps[cap]
}

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

func (c *IRCCore) MonitorAdd(nicks ...string) {
	c.sendRaw("MONITOR + " + strings.Join(nicks, ","))
	c.monitoredMu.Lock()
	for _, n := range nicks {
		c.monitored[strings.ToLower(n)] = true
	}
	c.monitoredMu.Unlock()
}

func (c *IRCCore) MonitorRemove(nicks ...string) {
	c.sendRaw("MONITOR - " + strings.Join(nicks, ","))
	c.monitoredMu.Lock()
	for _, n := range nicks {
		delete(c.monitored, strings.ToLower(n))
	}
	c.monitoredMu.Unlock()
}

func (c *IRCCore) MonitorClear() {
	c.sendRaw("MONITOR C")
	c.monitoredMu.Lock()
	c.monitored = make(map[string]bool)
	c.monitoredMu.Unlock()
}

func (c *IRCCore) MonitorList() {
	c.sendRaw("MONITOR L")
}

func (c *IRCCore) MonitorStatus() {
	c.sendRaw("MONITOR S")
}

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

func (c *IRCCore) NickServIdentify(password string) {
	c.sendRaw("PRIVMSG NickServ :IDENTIFY " + password)
}

func (c *IRCCore) NickServRegister(password, email string) {
	if email != "" {
		c.sendRaw("PRIVMSG NickServ :REGISTER " + password + " " + email)
	} else {
		c.sendRaw("PRIVMSG NickServ :REGISTER " + password)
	}
}

func (c *IRCCore) NickServGhost(nick, password string) {
	c.sendRaw("PRIVMSG NickServ :GHOST " + nick + " " + password)
}

func (c *IRCCore) NickServRelease(nick, password string) {
	c.sendRaw("PRIVMSG NickServ :RELEASE " + nick + " " + password)
}

func (c *IRCCore) NickServInfo(nick string) {
	c.sendRaw("PRIVMSG NickServ :INFO " + nick)
}

func (c *IRCCore) NickServLogout() {
	c.sendRaw("PRIVMSG NickServ :LOGOUT")
}

func (c *IRCCore) NickServSetPassword(newPassword string) {
	c.sendRaw("PRIVMSG NickServ :SET PASSWORD " + newPassword)
}

func (c *IRCCore) ChanServModeCmd(channel, nick, command string) {
	c.sendRaw("PRIVMSG ChanServ :" + strings.ToUpper(command) + " " + channel + " " + nick)
}

func (c *IRCCore) ChanServRegister(channel, password, description string) {
	c.sendRaw("PRIVMSG ChanServ :REGISTER " + channel + " " + password + " " + description)
}

func (c *IRCCore) ChanServDrop(channel string) {
	c.sendRaw("PRIVMSG ChanServ :DROP " + channel)
}

func (c *IRCCore) ChanServInvite(channel string) {
	c.sendRaw("PRIVMSG ChanServ :INVITE " + channel)
}

func (c *IRCCore) ChanServAkick(channel, action, mask, reason string) {
	cmd := "PRIVMSG ChanServ :AKICK " + channel + " " + action + " " + mask
	if reason != "" {
		cmd += " " + reason
	}
	c.sendRaw(cmd)
}

func (c *IRCCore) ChanServInfo(channel string) {
	c.sendRaw("PRIVMSG ChanServ :INFO " + channel)
}

func (c *IRCCore) MemoServSend(target, text string) {
	c.sendRaw("PRIVMSG MemoServ :SEND " + target + " " + text)
}

func (c *IRCCore) MemoServRead(which string) {
	if which == "" {
		which = "NEW"
	}
	c.sendRaw("PRIVMSG MemoServ :READ " + which)
}

func (c *IRCCore) MemoServList() {
	c.sendRaw("PRIVMSG MemoServ :LIST")
}

func (c *IRCCore) MemoServDelete(which string) {
	c.sendRaw("PRIVMSG MemoServ :DEL " + which)
}

func (c *IRCCore) SetVoice(channel, nick string, voice bool) {
	if voice {
		c.sendRaw("MODE " + channel + " +v " + nick)
	} else {
		c.sendRaw("MODE " + channel + " -v " + nick)
	}
}

func (c *IRCCore) SetHalfop(channel, nick string, halfop bool) {
	if halfop {
		c.sendRaw("MODE " + channel + " +h " + nick)
	} else {
		c.sendRaw("MODE " + channel + " -h " + nick)
	}
}

func (c *IRCCore) KickWithReason(channel, nick, reason string) {
	if reason != "" {
		c.sendRaw("KICK " + channel + " " + nick + " :" + reason)
	} else {
		c.sendRaw("KICK " + channel + " " + nick)
	}
}

func (c *IRCCore) BanMask(channel, mask string) {
	c.sendRaw("MODE " + channel + " +b " + mask)
}

func (c *IRCCore) UnbanMask(channel, mask string) {
	c.sendRaw("MODE " + channel + " -b " + mask)
}

func (c *IRCCore) SetChannelKey(channel, key string) {
	if key != "" {
		c.sendRaw("MODE " + channel + " +k " + key)
	} else {
		c.sendRaw("MODE " + channel + " -k *")
	}
}

func (c *IRCCore) SetChannelLimit(channel string, limit int) {
	if limit > 0 {
		c.sendRaw("MODE " + channel + " +l " + strconv.Itoa(limit))
	} else {
		c.sendRaw("MODE " + channel + " -l")
	}
}

func (c *IRCCore) SetChannelModerated(channel string, moderated bool) {
	if moderated {
		c.sendRaw("MODE " + channel + " +m")
	} else {
		c.sendRaw("MODE " + channel + " -m")
	}
}

func (c *IRCCore) SetChannelInviteOnly(channel string, inviteOnly bool) {
	if inviteOnly {
		c.sendRaw("MODE " + channel + " +i")
	} else {
		c.sendRaw("MODE " + channel + " -i")
	}
}

func (c *IRCCore) SetChannelNoExternal(channel string, noExternal bool) {
	if noExternal {
		c.sendRaw("MODE " + channel + " +n")
	} else {
		c.sendRaw("MODE " + channel + " -n")
	}
}

func (c *IRCCore) SetChannelSecret(channel string, secret bool) {
	if secret {
		c.sendRaw("MODE " + channel + " +s")
	} else {
		c.sendRaw("MODE " + channel + " -s")
	}
}

func (c *IRCCore) SetChannelTopicLock(channel string, locked bool) {
	if locked {
		c.sendRaw("MODE " + channel + " +t")
	} else {
		c.sendRaw("MODE " + channel + " -t")
	}
}

func (c *IRCCore) SetBanExcept(channel, mask string, add bool) {
	if add {
		c.sendRaw("MODE " + channel + " +e " + mask)
	} else {
		c.sendRaw("MODE " + channel + " -e " + mask)
	}
}

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

func (c *IRCCore) SetInviteExcept(channel, mask string, add bool) {
	if add {
		c.sendRaw("MODE " + channel + " +I " + mask)
	} else {
		c.sendRaw("MODE " + channel + " -I " + mask)
	}
}

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

func (c *IRCCore) SetUserMode(modes string) {
	c.mu.RLock()
	nick := c.nick
	c.mu.RUnlock()
	c.sendRaw("MODE " + nick + " " + modes)
}

func (c *IRCCore) GetUserMode() {
	c.mu.RLock()
	nick := c.nick
	c.mu.RUnlock()
	c.sendRaw("MODE " + nick)
}

func (c *IRCCore) RequestLinks(mask string) {
	if mask != "" {
		c.sendRaw("LINKS " + mask)
	} else {
		c.sendRaw("LINKS")
	}
}

func (c *IRCCore) RequestTrace(target string) {
	if target != "" {
		c.sendRaw("TRACE " + target)
	} else {
		c.sendRaw("TRACE")
	}
}

func (c *IRCCore) RequestMap() {
	c.sendRaw("MAP")
}

func (c *IRCCore) RequestHelp(topic string) {
	if topic != "" {
		c.sendRaw("HELP " + topic)
	} else {
		c.sendRaw("HELP")
	}
}

func (c *IRCCore) RequestRules() {
	c.sendRaw("RULES")
}

type IRCDCCOffer struct {
	Type     string
	Filename string
	IP       string
	Port     int
	Size     int64
	From     string
}

func (c *IRCCore) DCCSend(nick, filename string, port int, size int64) {
	c.sendRaw("PRIVMSG " + nick + " :\x01DCC SEND " + filename + " 0 " + strconv.Itoa(port) + " " + strconv.FormatInt(size, 10) + "\x01")
}

func (c *IRCCore) DCCChat(nick string, port int) {
	c.sendRaw("PRIVMSG " + nick + " :\x01DCC CHAT chat 0 " + strconv.Itoa(port) + "\x01")
}

func (c *IRCCore) DCCResume(nick, filename string, port int, position int64) {
	c.sendRaw("PRIVMSG " + nick + " :\x01DCC RESUME " + filename + " " + strconv.Itoa(port) + " " + strconv.FormatInt(position, 10) + "\x01")
}

func (c *IRCCore) DCCAccept(nick, filename string, port int, position int64) {
	c.sendRaw("PRIVMSG " + nick + " :\x01DCC ACCEPT " + filename + " " + strconv.Itoa(port) + " " + strconv.FormatInt(position, 10) + "\x01")
}

func (c *IRCCore) SendTagMsg(target string, tags map[string]string) {
	var b strings.Builder
	b.Grow(64)
	b.WriteByte('@')
	first := true
	for k, v := range tags {
		if !first {
			b.WriteByte(';')
		}
		first = false
		b.WriteString(k)
		if v != "" {
			b.WriteByte('=')
			b.WriteString(v)
		}
	}
	b.WriteString(" TAGMSG ")
	b.WriteString(target)
	c.sendRaw(b.String())
}

func (c *IRCCore) SendTypingIndicator(target string, typing bool) {
	status := "active"
	if !typing {
		status = "done"
	}
	c.SendTagMsg(target, map[string]string{"+typing": status})
}

func (c *IRCCore) ChatHistoryLatest(target string, limit int) {
	c.sendRaw("CHATHISTORY LATEST " + target + " * " + strconv.Itoa(limit))
}

func (c *IRCCore) ChatHistoryBefore(target, reference string, limit int) {
	c.sendRaw("CHATHISTORY BEFORE " + target + " " + reference + " " + strconv.Itoa(limit))
}

func (c *IRCCore) ChatHistoryAfter(target, reference string, limit int) {
	c.sendRaw("CHATHISTORY AFTER " + target + " " + reference + " " + strconv.Itoa(limit))
}

func (c *IRCCore) ChatHistoryAround(target, reference string, limit int) {
	c.sendRaw("CHATHISTORY AROUND " + target + " " + reference + " " + strconv.Itoa(limit))
}

func (c *IRCCore) ChatHistoryTargets(fromTime, toTime string, limit int) {
	c.sendRaw("CHATHISTORY TARGETS " + fromTime + " " + toTime + " " + strconv.Itoa(limit))
}

func (c *IRCCore) MarkRead(target, msgid string) {
	if msgid != "" {
		c.sendRaw("MARKREAD " + target + " " + msgid)
	} else {
		c.sendRaw("MARKREAD " + target)
	}
}

func (c *IRCCore) Redact(target, msgid, reason string) {
	if reason != "" {
		c.sendRaw("REDACT " + target + " " + msgid + " :" + reason)
	} else {
		c.sendRaw("REDACT " + target + " " + msgid)
	}
}

func (c *IRCCore) Register(account, email, password string) {
	if email != "" {
		c.sendRaw("REGISTER " + account + " " + email + " " + password)
	} else {
		c.sendRaw("REGISTER " + account + " * " + password)
	}
}

func (c *IRCCore) Verify(account, code string) {
	c.sendRaw("VERIFY " + account + " " + code)
}

func (c *IRCCore) WhoX(mask, fields string) {
	c.sendRaw("WHO " + mask + " %" + fields)
}

func (c *IRCCore) Silence(mask string) {
	if mask != "" {
		c.sendRaw("SILENCE " + mask)
	} else {
		c.sendRaw("SILENCE")
	}
}

func (c *IRCCore) WatchAdd(nicks ...string) {
	for _, nick := range nicks {
		c.sendRaw("WATCH +" + nick)
	}
}

func (c *IRCCore) WatchRemove(nicks ...string) {
	for _, nick := range nicks {
		c.sendRaw("WATCH -" + nick)
	}
}

func (c *IRCCore) WatchClear() {
	c.sendRaw("WATCH C")
}

func (c *IRCCore) WatchList() {
	c.sendRaw("WATCH L")
}

func (c *IRCCore) WatchStatus() {
	c.sendRaw("WATCH S")
}

func (c *IRCCore) SendPass(password string) {
	c.sendRaw("PASS " + password)
}

func (c *IRCCore) SendStatusMsg(prefix, channel, text string) {
	c.sendRaw("PRIVMSG " + prefix + channel + " :" + text)
}

func (c *IRCCore) SendStatusNotice(prefix, channel, text string) {
	c.sendRaw("NOTICE " + prefix + channel + " :" + text)
}

func (c *IRCCore) RequestUsers(target string) {
	if target != "" {
		c.sendRaw("USERS " + target)
	} else {
		c.sendRaw("USERS")
	}
}

func (c *IRCCore) UserIP(nicks ...string) {
	if len(nicks) > 5 {
		nicks = nicks[:5]
	}
	c.sendRaw("USERIP " + strings.Join(nicks, " "))
}

func (c *IRCCore) CPrivmsg(nick, channel, text string) {
	c.sendRaw("CPRIVMSG " + nick + " " + channel + " :" + text)
}

func (c *IRCCore) CNotice(nick, channel, text string) {
	c.sendRaw("CNOTICE " + nick + " " + channel + " :" + text)
}

func (c *IRCCore) NickServGroup(target, password string) {
	if target != "" {
		c.sendRaw("PRIVMSG NickServ :GROUP " + target + " " + password)
	} else {
		c.sendRaw("PRIVMSG NickServ :GROUP")
	}
}

func (c *IRCCore) NickServUngroup(nick string) {
	c.sendRaw("PRIVMSG NickServ :UNGROUP " + nick)
}

func (c *IRCCore) NickServAccess(action, mask string) {
	c.sendRaw("PRIVMSG NickServ :ACCESS " + action + " " + mask)
}

func (c *IRCCore) NickServAjoin(action, channel string) {
	c.sendRaw("PRIVMSG NickServ :AJOIN " + action + " " + channel)
}

func (c *IRCCore) NickServCert(action, fingerprint string) {
	cmd := "PRIVMSG NickServ :CERT " + action
	if fingerprint != "" {
		cmd += " " + fingerprint
	}
	c.sendRaw(cmd)
}

func (c *IRCCore) NickServAlist() {
	c.sendRaw("PRIVMSG NickServ :ALIST")
}

func (c *IRCCore) NickServAcc(nick string) {
	c.sendRaw("PRIVMSG NickServ :ACC " + nick)
}

func (c *IRCCore) NickServStatus(nick string) {
	c.sendRaw("PRIVMSG NickServ :STATUS " + nick)
}

func (c *IRCCore) NickServDrop(nick string) {
	if nick != "" {
		c.sendRaw("PRIVMSG NickServ :DROP " + nick)
	} else {
		c.sendRaw("PRIVMSG NickServ :DROP")
	}
}

func (c *IRCCore) NickServSet(option, value string) {
	c.sendRaw("PRIVMSG NickServ :SET " + option + " " + value)
}

func (c *IRCCore) NickServSendPass(nick string) {
	c.sendRaw("PRIVMSG NickServ :SENDPASS " + nick)
}

func (c *IRCCore) NickServRecover(nick, password string) {
	c.sendRaw("PRIVMSG NickServ :RECOVER " + nick + " " + password)
}

func (c *IRCCore) NickServUpdate() {
	c.sendRaw("PRIVMSG NickServ :UPDATE")
}

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

func (c *IRCCore) ChanServAop(channel, action, nick string) {
	c.sendRaw("PRIVMSG ChanServ :AOP " + channel + " " + action + " " + nick)
}

func (c *IRCCore) ChanServSop(channel, action, nick string) {
	c.sendRaw("PRIVMSG ChanServ :SOP " + channel + " " + action + " " + nick)
}

func (c *IRCCore) ChanServHop(channel, action, nick string) {
	c.sendRaw("PRIVMSG ChanServ :HOP " + channel + " " + action + " " + nick)
}

func (c *IRCCore) ChanServVop(channel, action, nick string) {
	c.sendRaw("PRIVMSG ChanServ :VOP " + channel + " " + action + " " + nick)
}

func (c *IRCCore) ChanServQop(channel, action, nick string) {
	c.sendRaw("PRIVMSG ChanServ :QOP " + channel + " " + action + " " + nick)
}

func (c *IRCCore) ChanServBan(channel, nick string) {
	c.sendRaw("PRIVMSG ChanServ :BAN " + channel + " " + nick)
}

func (c *IRCCore) ChanServUnban(channel, nick string) {
	c.sendRaw("PRIVMSG ChanServ :UNBAN " + channel + " " + nick)
}

func (c *IRCCore) ChanServKick(channel, nick, reason string) {
	cmd := "PRIVMSG ChanServ :KICK " + channel + " " + nick
	if reason != "" {
		cmd += " " + reason
	}
	c.sendRaw(cmd)
}

func (c *IRCCore) ChanServTopic(channel, topic string) {
	c.sendRaw("PRIVMSG ChanServ :TOPIC " + channel + " " + topic)
}

func (c *IRCCore) ChanServUp(channel string) {
	c.sendRaw("PRIVMSG ChanServ :UP " + channel)
}

func (c *IRCCore) ChanServDown(channel string) {
	c.sendRaw("PRIVMSG ChanServ :DOWN " + channel)
}

func (c *IRCCore) ChanServSet(channel, option, value string) {
	c.sendRaw("PRIVMSG ChanServ :SET " + channel + " " + option + " " + value)
}

func (c *IRCCore) ChanServClear(channel, what string) {
	c.sendRaw("PRIVMSG ChanServ :CLEAR " + channel + " " + what)
}

func (c *IRCCore) ChanServEnforce(channel string) {
	c.sendRaw("PRIVMSG ChanServ :ENFORCE " + channel)
}

func (c *IRCCore) ChanServEntryMsg(channel, message string) {
	c.sendRaw("PRIVMSG ChanServ :ENTRYMSG " + channel + " " + message)
}

func (c *IRCCore) ChanServSync(channel string) {
	c.sendRaw("PRIVMSG ChanServ :SYNC " + channel)
}

func (c *IRCCore) ChanServGetKey(channel string) {
	c.sendRaw("PRIVMSG ChanServ :GETKEY " + channel)
}

func (c *IRCCore) ChanServStatus(channel, nick string) {
	c.sendRaw("PRIVMSG ChanServ :STATUS " + channel + " " + nick)
}

func (c *IRCCore) ChanServList(pattern string) {
	if pattern != "" {
		c.sendRaw("PRIVMSG ChanServ :LIST " + pattern)
	} else {
		c.sendRaw("PRIVMSG ChanServ :LIST")
	}
}

func (c *IRCCore) ChanServClone(source, target string) {
	c.sendRaw("PRIVMSG ChanServ :CLONE " + source + " " + target)
}

func (c *IRCCore) ChanServIdentify(channel, password string) {
	c.sendRaw("PRIVMSG ChanServ :IDENTIFY " + channel + " " + password)
}

func (c *IRCCore) ChanServMode(channel, modes string) {
	c.sendRaw("PRIVMSG ChanServ :MODE " + channel + " " + modes)
}

func (c *IRCCore) MemoServRSend(target, text string) {
	c.sendRaw("PRIVMSG MemoServ :RSEND " + target + " " + text)
}

func (c *IRCCore) MemoServCancel(target string) {
	c.sendRaw("PRIVMSG MemoServ :CANCEL " + target)
}

func (c *IRCCore) MemoServCheck(target string) {
	c.sendRaw("PRIVMSG MemoServ :CHECK " + target)
}

func (c *IRCCore) MemoServInfo(target string) {
	if target != "" {
		c.sendRaw("PRIVMSG MemoServ :INFO " + target)
	} else {
		c.sendRaw("PRIVMSG MemoServ :INFO")
	}
}

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

func (c *IRCCore) MemoServSet(option, value string) {
	c.sendRaw("PRIVMSG MemoServ :SET " + option + " " + value)
}

func (c *IRCCore) HostServOn() {
	c.sendRaw("PRIVMSG HostServ :ON")
}

func (c *IRCCore) HostServOff() {
	c.sendRaw("PRIVMSG HostServ :OFF")
}

func (c *IRCCore) HostServRequest(vhost string) {
	c.sendRaw("PRIVMSG HostServ :REQUEST " + vhost)
}

func (c *IRCCore) HostServGroup() {
	c.sendRaw("PRIVMSG HostServ :GROUP")
}

func (c *IRCCore) BotServBotList() {
	c.sendRaw("PRIVMSG BotServ :BOTLIST")
}

func (c *IRCCore) BotServAssign(channel, botNick string) {
	c.sendRaw("PRIVMSG BotServ :ASSIGN " + channel + " " + botNick)
}

func (c *IRCCore) BotServUnassign(channel string) {
	c.sendRaw("PRIVMSG BotServ :UNASSIGN " + channel)
}

func (c *IRCCore) BotServInfo(target string) {
	c.sendRaw("PRIVMSG BotServ :INFO " + target)
}

func (c *IRCCore) BotServSay(channel, text string) {
	c.sendRaw("PRIVMSG BotServ :SAY " + channel + " " + text)
}

func (c *IRCCore) BotServAct(channel, text string) {
	c.sendRaw("PRIVMSG BotServ :ACT " + channel + " " + text)
}

func (c *IRCCore) GetDCCOffers() []IRCDCCOffer {
	c.dccOffersMu.RLock()
	defer c.dccOffersMu.RUnlock()
	result := make([]IRCDCCOffer, len(c.dccOffers))
	copy(result, c.dccOffers)
	return result
}

func (c *IRCCore) ClearDCCOffers() {
	c.dccOffersMu.Lock()
	c.dccOffers = nil
	c.dccOffersMu.Unlock()
}

func (c *IRCCore) GetCTCPClientInfo() string {
	return "ACTION VERSION PING TIME CLIENTINFO FINGER USERINFO SOURCE DCC"
}

func (c *IRCCore) RequestInviteList(channel string) {
	c.sendRaw("MODE " + channel + " +I")
}

func (c *IRCCore) RenameChannel(oldName, newName, reason string) {
	if reason != "" {
		c.sendRaw("RENAME " + oldName + " " + newName + " :" + reason)
	} else {
		c.sendRaw("RENAME " + oldName + " " + newName)
	}
}

func (c *IRCCore) Kill(nick, reason string) {
	c.sendRaw("KILL " + nick + " :" + reason)
}

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

func (c *IRCCore) RequestCAPList() {
	c.sendRaw("CAP LIST")
}

func (c *IRCCore) RequestCAP(caps ...string) {
	c.sendRaw("CAP REQ :" + strings.Join(caps, " "))
}

func (c *IRCCore) WebIRC(password, gateway, hostname, ip string) {
	c.sendRaw("WEBIRC " + password + " " + gateway + " " + hostname + " " + ip)
}

func (c *IRCCore) loadSession() error {
	if c.session == nil {
		return fmt.Errorf("no session store configured")
	}
	var sess ircSession
	if err := c.session.Load(&sess); err != nil {
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

	c.channelsMu.RLock()
	for _, ch := range c.channels {
		sess.Channels = append(sess.Channels, ch.Name)
	}
	c.channelsMu.RUnlock()
	if len(sess.Channels) == 0 {
		sess.Channels = c.autoJoin
	}

	c.blockedMu.RLock()
	for nick := range c.blocked {
		sess.Blocked = append(sess.Blocked, nick)
	}
	c.blockedMu.RUnlock()

	if c.session == nil {
		return
	}
	c.session.Save(sess)
}

func (c *IRCCore) Connect(target string, port int, remote string) {
	portStr := strconv.Itoa(port)
	if remote != "" {
		c.sendRaw("CONNECT " + target + " " + portStr + " " + remote)
	} else {
		c.sendRaw("CONNECT " + target + " " + portStr)
	}
}

func (c *IRCCore) Die() {
	c.sendRaw("DIE")
}

func (c *IRCCore) Rehash() {
	c.sendRaw("REHASH")
}

func (c *IRCCore) Restart() {
	c.sendRaw("RESTART")
}

func (c *IRCCore) ChatHistoryBetween(target, startRef, endRef string, limit int) {
	c.sendRaw("CHATHISTORY BETWEEN " + target + " " + startRef + " " + endRef + " " + strconv.Itoa(limit))
}

func (c *IRCCore) BatchStart(refTag, batchType string, params ...string) {
	cmd := "BATCH +" + refTag + " " + batchType
	if len(params) > 0 {
		cmd += " " + strings.Join(params, " ")
	}
	c.sendRaw(cmd)
}

func (c *IRCCore) BatchEnd(refTag string) {
	c.sendRaw("BATCH -" + refTag)
}

func (c *IRCCore) Starttls() {
	c.sendRaw("STARTTLS")
}

func (c *IRCCore) DCCSecureSend(nick, filename string, port int, size int64) {
	c.sendRaw("PRIVMSG " + nick + " :\x01DCC SSEND " + filename + " 0 " + strconv.Itoa(port) + " " + strconv.FormatInt(size, 10) + "\x01")
}

func (c *IRCCore) DCCSecureChat(nick string, port int) {
	c.sendRaw("PRIVMSG " + nick + " :\x01DCC SCHAT chat 0 " + strconv.Itoa(port) + "\x01")
}

func (c *IRCCore) XDCCSend(botNick string, packNum int) {
	c.sendRaw("PRIVMSG " + botNick + " :XDCC SEND #" + strconv.Itoa(packNum))
}

func (c *IRCCore) XDCCList(botNick string) {
	c.sendRaw("PRIVMSG " + botNick + " :XDCC LIST")
}

func (c *IRCCore) XDCCBatch(botNick string, packNums []int) {
	packs := make([]string, len(packNums))
	for i, n := range packNums {
		packs[i] = "#" + strconv.Itoa(n)
	}
	c.sendRaw("PRIVMSG " + botNick + " :XDCC BATCH " + strings.Join(packs, ","))
}

func (c *IRCCore) XDCCCancel(botNick string) {
	c.sendRaw("PRIVMSG " + botNick + " :XDCC CANCEL")
}

func (c *IRCCore) XDCCRemove(botNick string, packNum int) {
	c.sendRaw("PRIVMSG " + botNick + " :XDCC REMOVE #" + strconv.Itoa(packNum))
}

func (c *IRCCore) XDCCInfo(botNick string, packNum int) {
	c.sendRaw("PRIVMSG " + botNick + " :XDCC INFO #" + strconv.Itoa(packNum))
}

func (c *IRCCore) XDCCSearch(botNick, query string) {
	c.sendRaw("PRIVMSG " + botNick + " :XDCC SEARCH " + query)
}

func (c *IRCCore) CTCPFinger(target string) {
	c.SendCTCP(target, "FINGER", "")
}

func (c *IRCCore) CTCPSource(target string) {
	c.SendCTCP(target, "SOURCE", "")
}

func (c *IRCCore) CTCPUserinfo(target string) {
	c.SendCTCP(target, "USERINFO", "")
}

func (c *IRCCore) NickServRegain(nick, password string) {
	c.sendRaw("PRIVMSG NickServ :REGAIN " + nick + " " + password)
}

func (c *IRCCore) NickServGList() {
	c.sendRaw("PRIVMSG NickServ :GLIST")
}

func (c *IRCCore) NickServConfirm(code string) {
	c.sendRaw("PRIVMSG NickServ :CONFIRM " + code)
}

func (c *IRCCore) NickServSuspend(nick, reason string) {
	c.sendRaw("PRIVMSG NickServ :SUSPEND " + nick + " " + reason)
}

func (c *IRCCore) NickServUnsuspend(nick string) {
	c.sendRaw("PRIVMSG NickServ :UNSUSPEND " + nick)
}

func (c *IRCCore) NickServForbid(nick, reason string) {
	c.sendRaw("PRIVMSG NickServ :FORBID " + nick + " " + reason)
}

func (c *IRCCore) NickServList(pattern string) {
	c.sendRaw("PRIVMSG NickServ :LIST " + pattern)
}

func (c *IRCCore) NickServSaSet(nick, option, value string) {
	c.sendRaw("PRIVMSG NickServ :SASET " + nick + " " + option + " " + value)
}

func (c *IRCCore) ChanServAppendTopic(channel, text string) {
	c.sendRaw("PRIVMSG ChanServ :APPENDTOPIC " + channel + " " + text)
}

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

func (c *IRCCore) ChanServLog(channel string) {
	c.sendRaw("PRIVMSG ChanServ :LOG " + channel)
}

func (c *IRCCore) ChanServCount(channel string) {
	c.sendRaw("PRIVMSG ChanServ :COUNT " + channel)
}

func (c *IRCCore) ChanServSuspend(channel, reason string) {
	c.sendRaw("PRIVMSG ChanServ :SUSPEND " + channel + " " + reason)
}

func (c *IRCCore) ChanServUnsuspend(channel string) {
	c.sendRaw("PRIVMSG ChanServ :UNSUSPEND " + channel)
}

func (c *IRCCore) ChanServForbid(channel, reason string) {
	c.sendRaw("PRIVMSG ChanServ :FORBID " + channel + " " + reason)
}

func (c *IRCCore) MemoServSendGroup(group, text string) {
	c.sendRaw("PRIVMSG MemoServ :SENDGROUP " + group + " " + text)
}

func (c *IRCCore) MemoServSendOps(channel, text string) {
	c.sendRaw("PRIVMSG MemoServ :SENDOPS " + channel + " " + text)
}

func (c *IRCCore) MemoServForward(memoID, target string) {
	c.sendRaw("PRIVMSG MemoServ :FORWARD " + target + " " + memoID)
}

func (c *IRCCore) MemoServStaff(text string) {
	c.sendRaw("PRIVMSG MemoServ :STAFF " + text)
}

func (c *IRCCore) HostServList() {
	c.sendRaw("PRIVMSG HostServ :LIST")
}

func (c *IRCCore) HostServSet(nick, vhost string) {
	c.sendRaw("PRIVMSG HostServ :SET " + nick + " " + vhost)
}

func (c *IRCCore) HostServSetAll(nick, vhost string) {
	c.sendRaw("PRIVMSG HostServ :SETALL " + nick + " " + vhost)
}

func (c *IRCCore) HostServDel(nick string) {
	c.sendRaw("PRIVMSG HostServ :DEL " + nick)
}

func (c *IRCCore) HostServDelAll(nick string) {
	c.sendRaw("PRIVMSG HostServ :DELALL " + nick)
}

func (c *IRCCore) HostServActivate(nick string) {
	c.sendRaw("PRIVMSG HostServ :ACTIVATE " + nick)
}

func (c *IRCCore) HostServReject(nick, reason string) {
	cmd := "PRIVMSG HostServ :REJECT " + nick
	if reason != "" {
		cmd += " " + reason
	}
	c.sendRaw(cmd)
}

func (c *IRCCore) HostServWaiting() {
	c.sendRaw("PRIVMSG HostServ :WAITING")
}

func (c *IRCCore) BotServBotAdd(nick, ident, host, realname string) {
	c.sendRaw("PRIVMSG BotServ :BOT ADD " + nick + " " + ident + " " + host + " " + realname)
}

func (c *IRCCore) BotServBotDel(nick string) {
	c.sendRaw("PRIVMSG BotServ :BOT DEL " + nick)
}

func (c *IRCCore) BotServBotChange(oldNick, newNick, ident, host, realname string) {
	c.sendRaw("PRIVMSG BotServ :BOT CHANGE " + oldNick + " " + newNick + " " + ident + " " + host + " " + realname)
}

func (c *IRCCore) BotServBadwords(channel, action, word string) {
	cmd := "PRIVMSG BotServ :BADWORDS " + channel + " " + action
	if word != "" {
		cmd += " " + word
	}
	c.sendRaw(cmd)
}

func (c *IRCCore) BotServKickConfig(channel, option, value string) {
	c.sendRaw("PRIVMSG BotServ :KICK " + channel + " " + option + " " + value)
}

func (c *IRCCore) BotServSet(channel, option, value string) {
	c.sendRaw("PRIVMSG BotServ :SET " + channel + " " + option + " " + value)
}

func (c *IRCCore) OperServAkill(action, mask, reason string) {
	cmd := "PRIVMSG OperServ :AKILL " + action + " " + mask
	if reason != "" {
		cmd += " " + reason
	}
	c.sendRaw(cmd)
}

func (c *IRCCore) OperServSqline(action, mask, reason string) {
	cmd := "PRIVMSG OperServ :SQLINE " + action + " " + mask
	if reason != "" {
		cmd += " " + reason
	}
	c.sendRaw(cmd)
}

func (c *IRCCore) OperServSnline(action, mask, reason string) {
	cmd := "PRIVMSG OperServ :SNLINE " + action + " " + mask
	if reason != "" {
		cmd += " " + reason
	}
	c.sendRaw(cmd)
}

func (c *IRCCore) OperServSession(action, host string) {
	c.sendRaw("PRIVMSG OperServ :SESSION " + action + " " + host)
}

func (c *IRCCore) OperServNoop(server, action string) {
	c.sendRaw("PRIVMSG OperServ :NOOP " + server + " " + action)
}

func (c *IRCCore) OperServJupe(server, reason string) {
	c.sendRaw("PRIVMSG OperServ :JUPE " + server + " " + reason)
}

func (c *IRCCore) OperServGlobal(message string) {
	c.sendRaw("PRIVMSG OperServ :GLOBAL " + message)
}

func (c *IRCCore) OperServDefcon(level int) {
	c.sendRaw("PRIVMSG OperServ :DEFCON " + strconv.Itoa(level))
}

func (c *IRCCore) OperServStats(what string) {
	if what == "" {
		c.sendRaw("PRIVMSG OperServ :STATS")
	} else {
		c.sendRaw("PRIVMSG OperServ :STATS " + what)
	}
}

func (c *IRCCore) OperServReload(module string) {
	if module == "" {
		c.sendRaw("PRIVMSG OperServ :RELOAD")
	} else {
		c.sendRaw("PRIVMSG OperServ :RELOAD " + module)
	}
}

func (c *IRCCore) OperServShutdown() {
	c.sendRaw("PRIVMSG OperServ :SHUTDOWN")
}

func (c *IRCCore) OperServRestart() {
	c.sendRaw("PRIVMSG OperServ :RESTART")
}

func (c *IRCCore) SetHost(vhost string) {
	c.sendRaw("SETHOST " + vhost)
}

func (c *IRCCore) ChgHost(nick, newHost string) {
	c.sendRaw("CHGHOST " + nick + " " + newHost)
}

func (c *IRCCore) ChgIdent(nick, newIdent string) {
	c.sendRaw("CHGIDENT " + nick + " " + newIdent)
}

func (c *IRCCore) ChgName(nick, newName string) {
	c.sendRaw("CHGNAME " + nick + " :" + newName)
}

func (c *IRCCore) SaJoin(nick, channel string) {
	c.sendRaw("SAJOIN " + nick + " " + channel)
}

func (c *IRCCore) SaPart(nick, channel string) {
	c.sendRaw("SAPART " + nick + " " + channel)
}

func (c *IRCCore) SaNick(oldNick, newNick string) {
	c.sendRaw("SANICK " + oldNick + " " + newNick)
}

func (c *IRCCore) SaMode(target, modes string) {
	c.sendRaw("SAMODE " + target + " " + modes)
}

func (c *IRCCore) Globops(message string) {
	c.sendRaw("GLOBOPS :" + message)
}

func (c *IRCCore) Vhost(username, password string) {
	c.sendRaw("VHOST " + username + " " + password)
}

func (c *IRCCore) BounceListNetworks() {
	c.sendRaw("BOUNCER LISTNETWORKS")
}

func (c *IRCCore) BouncerBind(networkID string) {
	c.sendRaw("BOUNCER BIND " + networkID)
}

func (c *IRCCore) Resume(token string, timestamp time.Time) {
	c.sendRaw("RESUME " + token + " " + timestamp.UTC().Format("2006-01-02T15:04:05.000Z"))
}

func (c *IRCCore) WebPushRegister(endpoint, vapidKey, p256dh, auth string) {
	c.sendRaw("WEBPUSH REGISTER " + endpoint + " " + vapidKey + " " + p256dh + " " + auth)
}

func (c *IRCCore) WebPushUnregister(endpoint string) {
	c.sendRaw("WEBPUSH UNREGISTER " + endpoint)
}

func (c *IRCCore) GLine(mask, duration, reason string) {
	c.sendRaw("GLINE " + mask + " " + duration + " :" + reason)
}

func (c *IRCCore) GZLine(ip, duration, reason string) {
	c.sendRaw("GZLINE " + ip + " " + duration + " :" + reason)
}

func (c *IRCCore) ZLine(ip, duration, reason string) {
	c.sendRaw("ZLINE " + ip + " " + duration + " :" + reason)
}

func (c *IRCCore) Shun(mask, duration, reason string) {
	c.sendRaw("SHUN " + mask + " " + duration + " :" + reason)
}

func (c *IRCCore) KLine(mask, duration, reason string) {
	c.sendRaw("KLINE " + mask + " " + duration + " :" + reason)
}

func (c *IRCCore) Check(target string) {
	c.sendRaw("CHECK " + target)
}

func (c *IRCCore) GroupServInfo(group string) {
	c.sendRaw("PRIVMSG GroupServ :INFO " + group)
}

func (c *IRCCore) GroupServJoin(group string) {
	c.sendRaw("PRIVMSG GroupServ :JOIN " + group)
}

func (c *IRCCore) GroupServLeave(group string) {
	c.sendRaw("PRIVMSG GroupServ :LEAVE " + group)
}

func (c *IRCCore) GroupServFlags(group, target, flags string) {
	c.sendRaw("PRIVMSG GroupServ :FLAGS " + group + " " + target + " " + flags)
}

func (c *IRCCore) StatServInfo() {
	c.sendRaw("PRIVMSG StatServ :INFO")
}

func (c *IRCCore) StatServAkill() {
	c.sendRaw("PRIVMSG StatServ :AKILL")
}

func (c *IRCCore) Tempshun(nick, reason string) { c.sendRaw("TEMPSHUN " + nick + " :" + reason) }

func (c *IRCCore) SpamfilterAdd(target, action, tkltime, reason, regex string) {
	c.sendRaw("SPAMFILTER add " + target + " " + action + " " + tkltime + " " + reason + " :" + regex)
}

func (c *IRCCore) SpamfilterDel(target, action, regex string) {
	c.sendRaw("SPAMFILTER del " + target + " " + action + " :" + regex)
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

func (c *IRCCore) Addmotd(line string) { c.sendRaw("ADDMOTD :" + line) }

func (c *IRCCore) Addomotd(line string) { c.sendRaw("ADDOMOTD :" + line) }

func (c *IRCCore) Botmotd() { c.sendRaw("BOTMOTD") }

func (c *IRCCore) Opermotd() { c.sendRaw("OPERMOTD") }

func (c *IRCCore) ShowCredits() { c.sendRaw("CREDITS") }

func (c *IRCCore) ShowLicense() { c.sendRaw("LICENSE") }

func (c *IRCCore) ShowStaff() { c.sendRaw("STAFFLIST") }

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

func (c *IRCCore) ForcePart(nick, channel, reason string) {
	c.sendRaw("REMOVE " + channel + " " + nick + " :" + reason)
}

func (c *IRCCore) Uninvite(nick, channel string) { c.sendRaw("UNINVITE " + nick + " " + channel) }

func (c *IRCCore) Clearchan(channel, action string) {
	c.sendRaw("CLEARCHAN " + channel + " " + action)
}

func (c *IRCCore) Cban(channel, reason string) { c.sendRaw("CBAN " + channel + " :" + reason) }

func (c *IRCCore) CbanDel(channel string) { c.sendRaw("CBAN " + channel) }

func (c *IRCCore) Rline(regex, duration, reason string) {
	c.sendRaw("RLINE " + regex + " " + duration + " :" + reason)
}

func (c *IRCCore) RlineDel(regex string) { c.sendRaw("RLINE " + regex) }

func (c *IRCCore) Tline(mask string) { c.sendRaw("TLINE " + mask) }

func (c *IRCCore) Clones() { c.sendRaw("CLONES") }

func (c *IRCCore) Rconnect(serverMask, remoteTarget string) {
	c.sendRaw("RCONNECT " + serverMask + " " + remoteTarget)
}

func (c *IRCCore) Rsquit(serverMask, reason string) {
	c.sendRaw("RSQUIT " + serverMask + " :" + reason)
}

func (c *IRCCore) Nicklock(nick, newNick string) { c.sendRaw("NICKLOCK " + nick + " " + newNick) }

func (c *IRCCore) Nickunlock(nick string) { c.sendRaw("NICKUNLOCK " + nick) }

func (c *IRCCore) Setidle(seconds int) { c.sendRaw("SETIDLE " + strconv.Itoa(seconds)) }

func (c *IRCCore) Swhois(nick, line string) { c.sendRaw("SWHOIS " + nick + " :" + line) }

func (c *IRCCore) Ojoin(channel string) { c.sendRaw("OJOIN " + channel) }

func (c *IRCCore) Sakick(channel, nick, reason string) {
	c.sendRaw("SAKICK " + channel + " " + nick + " :" + reason)
}

func (c *IRCCore) Saquit(nick, reason string) { c.sendRaw("SAQUIT " + nick + " :" + reason) }

func (c *IRCCore) Satopic(channel, topic string) {
	c.sendRaw("SATOPIC " + channel + " :" + topic)
}

func (c *IRCCore) Rmode(mask, modes string) { c.sendRaw("RMODE " + mask + " " + modes) }

func (c *IRCCore) FilterAdd(pattern string) { c.sendRaw("FILTER " + pattern) }

func (c *IRCCore) FilterDel(pattern string) { c.sendRaw("FILTER -" + pattern) }

func (c *IRCCore) Alltime() { c.sendRaw("ALLTIME") }

func (c *IRCCore) Qline(nick, reason string) { c.sendRaw("QLINE " + nick + " :" + reason) }

func (c *IRCCore) QlineDel(nick string) { c.sendRaw("QLINE -" + nick) }

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
	c.sendRaw("@+draft/relaymsg=" + nick + " PRIVMSG " + channel + " :" + text)
}

func ParseStandardReply(line string) (severity, command, code, context, description string) {
	if strings.HasPrefix(line, ":") {
		if idx := strings.IndexByte(line, ' '); idx >= 0 {
			line = line[idx+1:]
		}
	}
	parts := strings.SplitN(line, " ", 4)
	if len(parts) >= 3 {
		severity = parts[0]
		command = parts[1]
		code = parts[2]
		if len(parts) >= 4 {
			rest := parts[3]
			if strings.HasPrefix(rest, ":") {
				description = rest[1:]
			} else if idx := strings.Index(rest, " :"); idx >= 0 {
				context = rest[:idx]
				description = rest[idx+2:]
			} else {
				context = rest
			}
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

func (c *IRCCore) ParseAccountExtban(account string) string {
	c.mu.RLock()
	prefix := c.extbanPrefix
	c.mu.RUnlock()
	if prefix == "" {
		prefix = "$a:"
	}
	return prefix + account
}

func (c *IRCCore) OnInviteNotify(handler func(inviter, channel, target string)) {
	c.mu.Lock()
	c.inviteNotifyHandler = handler
	c.mu.Unlock()
}

func (c *IRCCore) SendChannelContextTag(target, channelCtx, tags string) {
	c.sendRaw("@+draft/channel-context=" + channelCtx + ";" + tags + " TAGMSG " + target)
}

func (c *IRCCore) SendReactTag(target, msgID, emoji string) {
	c.sendRaw("@+draft/react=" + emoji + ";+draft/reply=" + msgID + " TAGMSG " + target)
}

func (c *IRCCore) SendClientBatch(batchID, batchType, target string, start bool) {
	if start {
		c.sendRaw("BATCH +" + batchID + " " + batchType + " " + target)
	} else {
		c.sendRaw("BATCH -" + batchID)
	}
}

func (c *IRCCore) SendMultiline(target string, lines []string) {
	batchID := "ml" + strconv.FormatInt(time.Now().UnixNano()%10000, 10)
	c.sendRaw("BATCH +" + batchID + " draft/multiline " + target)
	last := len(lines) - 1
	for i, line := range lines {
		if i < last {
			c.sendRaw("@batch=" + batchID + ";draft/multiline-concat PRIVMSG " + target + " :" + line)
		} else {
			c.sendRaw("@batch=" + batchID + " PRIVMSG " + target + " :" + line)
		}
	}
	c.sendRaw("BATCH -" + batchID)
}

func (c *IRCCore) RequestExtendedIsupport() { c.sendRaw("CAP REQ :draft/extended-isupport") }

func (c *IRCCore) GetNetworkIcon() string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.networkIcon
}

func (c *IRCCore) FilehostUpload(filename string) {
	c.sendRaw("FILEHOST UPLOAD " + filename)
}

func (c *IRCCore) SASLScramSHA256(username, password string) {
	c.sendRaw("AUTHENTICATE SCRAM-SHA-256")
	c.mu.Lock()
	c.saslUser = username
	c.saslPass = password
	c.saslMech = "SCRAM-SHA-256"
	c.mu.Unlock()
}

func (c *IRCCore) SASLExternal() {
	c.sendRaw("AUTHENTICATE EXTERNAL")
	c.sendRaw("AUTHENTICATE +")
}

func (c *IRCCore) SASLECDSAChallenge(accountName string) {
	c.sendRaw("AUTHENTICATE ECDSA-NIST256P-CHALLENGE")
	encoded := base64.StdEncoding.EncodeToString([]byte(accountName + "\x00" + accountName))
	c.sendRaw("AUTHENTICATE " + encoded)
}

func (c *IRCCore) DCCReverse(nick, filename string, size int64, token string) {
	c.sendRaw("PRIVMSG " + nick + " :\x01DCC SEND " + filename + " 0 0 " + strconv.FormatInt(size, 10) + " " + token + "\x01")
}

func (c *IRCCore) RDCC(nick string) {
	c.sendRaw("PRIVMSG " + nick + " :\x01RDCC\x01")
}

func (c *IRCCore) SetExtban(channel string, modeChar byte, extbanType, value string) {
	c.sendRaw("MODE " + channel + " +" + string(modeChar) + " " + extbanType + value)
}

func (c *IRCCore) SetChannelModeFlag(channel string, mode byte, on bool) {
	c.chanMode(channel, mode, on)
}

func (c *IRCCore) SetFloodProtection(channel string, params string) {
	c.sendRaw("MODE " + channel + " +f " + params)
}

func (c *IRCCore) SetChannelHistory(channel string, lines int, seconds int) {
	c.sendRaw("MODE " + channel + " +H " + strconv.Itoa(lines) + ":" + strconv.Itoa(seconds))
}

func (c *IRCCore) SetJoinThrottle(channel string, joins int, seconds int) {
	c.sendRaw("MODE " + channel + " +j " + strconv.Itoa(joins) + ":" + strconv.Itoa(seconds))
}

func (c *IRCCore) SetChannelRedirect(channel, target string) {
	c.sendRaw("MODE " + channel + " +L " + target)
}

func (c *IRCCore) chanMode(channel string, mode byte, on bool) {
	prefix := "+"
	if !on {
		prefix = "-"
	}
	c.sendRaw("MODE " + channel + " " + prefix + string(mode))
}

func (c *IRCCore) userMode(mode byte, on bool) {
	prefix := "+"
	if !on {
		prefix = "-"
	}
	c.sendRaw("MODE " + c.nick + " " + prefix + string(mode))
}

func (c *IRCCore) SetUserModeFlag(mode byte, on bool) { c.userMode(mode, on) }

func (c *IRCCore) Accept(args string) { c.sendRaw("ACCEPT " + args) }

func StripFormatting(text string) string {
	var result strings.Builder
	i := 0
	for i < len(text) {
		ch := text[i]
		switch ch {
		case 0x02, 0x1D, 0x1F, 0x1E, 0x11, 0x0F:
			i++
		case 0x03:
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
		case 0x04:
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

func (c *IRCCore) ConnectSOCKS(proxyAddr, targetAddr string) error {
	conn, err := net.DialTimeout("tcp", proxyAddr, 10*time.Second)
	if err != nil {
		return fmt.Errorf("irc: SOCKS connect %s: %w", proxyAddr, err)
	}
	conn.Write([]byte{0x05, 0x01, 0x00})
	buf := make([]byte, 2)
	conn.Read(buf)
	if buf[0] != 0x05 || buf[1] != 0x00 {
		conn.Close()
		return fmt.Errorf("irc: SOCKS handshake failed")
	}
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
	connectReq := "CONNECT " + targetAddr + " HTTP/1.1\r\nHost: " + targetAddr + "\r\n\r\n"
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

func (c *IRCCore) CTCPErrMsg(nick, query, message string) {
	c.sendRaw("NOTICE " + nick + " :\x01ERRMSG " + query + " :" + message + "\x01")
}

func (c *IRCCore) CTCPAvatar(nick, url string) {
	c.sendRaw("NOTICE " + nick + " :\x01AVATAR " + url + "\x01")
}

func (c *IRCCore) MuteChat(chatID string, muted bool) error {
	return fmt.Errorf("%w: %s does not support mute chat", ErrNotSupported, ircPlatform)
}

func (c *IRCCore) ArchiveChat(chatID string, archived bool) error {
	return fmt.Errorf("%w: %s does not support archive chat", ErrNotSupported, ircPlatform)
}

func (c *IRCCore) MarkUnread(chatID string, unread bool) error {
	return fmt.Errorf("%w: %s does not support mark unread", ErrNotSupported, ircPlatform)
}

func (c *IRCCore) UnpinAllMessages(chatID string) error {
	return fmt.Errorf("%w: %s does not support unpin all messages", ErrNotSupported, ircPlatform)
}

func (c *IRCCore) AcceptCall(callID string) (*CallSession, error) {
	return nil, fmt.Errorf("%w: %s does not support accept call", ErrNotSupported, ircPlatform)
}

func (c *IRCCore) DeclineCall(callID string) error {
	return fmt.Errorf("%w: %s does not support decline call", ErrNotSupported, ircPlatform)
}

func (c *IRCCore) SendLocation(chatID string, lat float64, lon float64) (*Message, error) {
	return nil, fmt.Errorf("%w: %s does not support send location", ErrNotSupported, ircPlatform)
}
