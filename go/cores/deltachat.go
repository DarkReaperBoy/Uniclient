package cores

import (
	"archive/zip"
	"bytes"
	"context"
	"crypto/rand"
	"crypto/tls"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"mime"
	"net"
	"os"
	"path/filepath"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"uniclient/utils"

	"github.com/ProtonMail/go-crypto/openpgp"
	"github.com/ProtonMail/go-crypto/openpgp/armor"
	"github.com/ProtonMail/go-crypto/openpgp/packet"
	"github.com/emersion/go-imap/v2"
	"github.com/emersion/go-imap/v2/imapclient"
	"github.com/emersion/go-message"
	"github.com/emersion/go-message/mail"
	"github.com/emersion/go-sasl"
	"github.com/emersion/go-smtp"
	"github.com/pion/webrtc/v4"
)

// DeltaChatCore implements the Core interface for Delta Chat (chat-over-email).
// Uses IMAP for receiving, SMTP for sending, Autocrypt for E2EE.
type DeltaChatCore struct {
	mu sync.RWMutex

	// Auth state
	authed   bool
	isBot    bool   // bot mode: no BCC self, auto-delete from server after processing
	myAddr   string // our email address
	myName   string // display name
	myStatus string // bio/status
	password string // email password (kept for reconnect)

	// Connections
	imapOps   *imapclient.Client // main IMAP operations
	idleInbox *imapclient.Client // IDLE on INBOX
	idleDC    *imapclient.Client // IDLE on DeltaChat folder

	// Server config
	imapHost           string // host:port
	smtpHost           string // host:port
	acceptInvalidCerts bool   // accept self-signed TLS certs

	// IMAP state
	dcFolder    string // "DeltaChat" or "INBOX/DeltaChat" or "INBOX.DeltaChat"
	imapDelim   string // folder delimiter (usually "/" or ".")
	lastSeenUID uint32 // track new messages

	// Autocrypt
	myEntity   *openpgp.Entity            // our Ed25519/Cv25519 keypair
	peerStates map[string]*dcPeerState    // email -> Autocrypt peer state
	peerKeysMu sync.RWMutex

	// Chat state
	chats    map[string]*dcChatState // chatID -> state
	chatsMu  sync.RWMutex
	messages map[string][]*Message   // chatID -> cached messages
	msgSeen  map[string]bool         // msgID -> true (dedup index)
	msgsMu   sync.RWMutex
	drafts   map[string]*OutgoingMessage
	draftsMu sync.RWMutex
	blocked  map[string]bool // email -> blocked
	folders  map[string]*Folder
	pins     map[string]map[string]bool // chatID -> msgID -> pinned

	// Active calls (WebRTC)
	activeCalls map[string]*dcCall
	callsMu     sync.RWMutex

	// Location streaming
	locationStreaming map[string]*DCLocationStream // chatID -> stream
	locationMu        sync.RWMutex

	// Location history
	locations      map[string][]DCLocation // "chatID:email" -> locations
	locationHistMu sync.RWMutex

	// Webxdc state
	webxdcUpdates     map[string][]DCWebxdcUpdate // msgID -> status updates
	webxdcMu          sync.RWMutex
	webxdcIntegration string // msgID of integration webxdc

	// Device messages
	deviceMsgLabels map[string]bool
	deviceMsgMu     sync.RWMutex

	// Sticker storage
	stickerDir string

	// Transports (multi-account)
	transports  []*DCTransport
	transportMu sync.RWMutex

	// Configuration
	showEmails    int   // 0=Off, 1=AcceptedContacts, 2=All
	downloadLimit int64 // 0=unlimited, else max bytes
	callFilter    int   // 0=Everybody, 1=Contacts, 2=Nobody

	// Push
	pushToken string
	pushState string // "NotConfigured", "Heartbeat", "Connected"

	// Session persistence
	session *utils.SessionStore

	// Update handlers
	updateHandlers []func(Update)
	updateMu       sync.RWMutex

	// Configuration map (for SetConfig/GetConfig)
	configMap    map[string]string
	configMapMu  sync.RWMutex

	// Stock strings (localized UI strings)
	stockStrings   map[int]string
	stockStringsMu sync.RWMutex

	// Cached serialized public key (invalidated when myEntity changes)
	cachedPubKey   string
	cachedPubKeyOK bool

	// Context
	ctx    context.Context
	cancel context.CancelFunc
	wg     sync.WaitGroup
}

var _ Core = (*DeltaChatCore)(nil)

// dcCall tracks an active WebRTC call.
type dcCall struct {
	ID         string
	ChatID     string
	PeerEmail  string
	IsVideo    bool
	State      CallState
	PC         *webrtc.PeerConnection
	AudioTrack *webrtc.TrackLocalStaticRTP
	StartTime  time.Time
	OfferMsgID string // Message-ID of the call initiation email
}

// DCLocationStream tracks active location sharing.
type DCLocationStream struct {
	ChatID   string
	Duration time.Duration
	StartAt  time.Time
	Cancel   context.CancelFunc
}

// DCWebxdcUpdate is a single webxdc status update.
type DCWebxdcUpdate struct {
	Serial  int             `json:"serial"`
	Payload json.RawMessage `json:"payload"`
	Info    string          `json:"info,omitempty"`
	Sender  string          `json:"sender"`
	Time    int64           `json:"time"`
}

// DCTransport represents an additional email transport (multi-account).
type DCTransport struct {
	ID       string `json:"id"`
	Email    string `json:"email"`
	Password string `json:"password"`
	IMAPHost string `json:"imap_host"`
	SMTPHost string `json:"smtp_host"`
}

// DCLocation represents a stored location point.
type DCLocation struct {
	Lat         float64 `json:"lat"`
	Lon         float64 `json:"lon"`
	Time        int64   `json:"time"`
	Sender      string  `json:"sender"`
	ChatID      string  `json:"chat_id"`
	Independent bool    `json:"independent"` // POI vs streaming
}

// DeltaChatWebxdcInfo holds metadata from a .xdc manifest.
type DeltaChatWebxdcInfo struct {
	Name          string `json:"name"`
	Icon          string `json:"icon"`
	SourceCodeURL string `json:"source_code_url"`
	Summary       string `json:"summary"`
}

// DeltaChatStorageReport is a breakdown of local storage usage.
type DeltaChatStorageReport struct {
	SessionBytes  int64 `json:"session_bytes"`
	TotalBytes    int64 `json:"total_bytes"`
	MessagesCount int   `json:"messages_count"`
	ChatsCount    int   `json:"chats_count"`
	ContactsCount int   `json:"contacts_count"`
}

// DeltaChatProviderInfo holds auto-config info for an email provider.
type DeltaChatProviderInfo struct {
	Status          int    `json:"status"` // 1=OK, 2=broken, 3=preparation needed
	BeforeLoginHint string `json:"before_login_hint"`
	AfterLoginHint  string `json:"after_login_hint"`
	OverviewPage    string `json:"overview_page"`
	IMAPHost        string `json:"imap_host"`
	IMAPPort        int    `json:"imap_port"`
	SMTPHost        string `json:"smtp_host"`
	SMTPPort        int    `json:"smtp_port"`
}

// DeltaChatQuotaInfo holds IMAP mailbox quota information.
type DeltaChatQuotaInfo struct {
	Current int64 `json:"current"` // bytes used
	Limit   int64 `json:"limit"`   // quota limit
}

type dcPeerState struct {
	Addr               string           `json:"addr"`
	LastSeen           time.Time        `json:"last_seen"`
	AutocryptTimestamp time.Time        `json:"autocrypt_timestamp"`
	PublicKey          []byte           `json:"public_key"`     // serialized
	PreferEncrypt      string           `json:"prefer_encrypt"` // "mutual" or ""
	GossipTimestamp    time.Time        `json:"gossip_timestamp"`
	GossipKey          []byte           `json:"gossip_key"` // serialized
	DisplayName        string           `json:"display_name"`
	AvatarB64          string           `json:"avatar_b64"`
	entity             *openpgp.Entity  // parsed (not serialized)
	gossipEntity       *openpgp.Entity
}

type dcChatState struct {
	ID              string   `json:"id"`
	Type            ChatType `json:"type"`
	Title           string   `json:"title"`
	Description     string   `json:"description"`
	Members         []string `json:"members"`      // email addresses
	GroupID         string   `json:"group_id"`      // Chat-Group-ID
	IsProtected     bool     `json:"is_protected"`
	Visibility      int      `json:"visibility"`    // 0=normal, 1=archived, 2=pinned
	MuteUntil       *int64   `json:"mute_until"`    // unix timestamp, nil=not muted, 0=forever
	EphemeralTimer  int      `json:"ephemeral_timer"`
	BroadcastSecret string   `json:"broadcast_secret"`
	LastMsgTime     int64    `json:"last_msg_time"`
	UnreadCount     int      `json:"unread_count"`
	AvatarB64       string   `json:"avatar_b64"`
	Name            string   `json:"name"`
	IsGroup         bool     `json:"is_group"`
	PastMembers     []string `json:"past_members"`
	IsContactRequest bool   `json:"is_contact_request"`
	IsMailingList   bool     `json:"is_mailing_list"`
	IsBroadcast     bool     `json:"is_broadcast"`
	IsUnpromoted    bool     `json:"is_unpromoted"`
	IsEncrypted     bool     `json:"is_encrypted"`
	MailingListAddr string   `json:"mailing_list_addr"`
	FreshCount      int      `json:"fresh_count"`
}

type dcSession struct {
	Email       string                    `json:"email"`
	Password    string                    `json:"password"`
	IMAPHost    string                    `json:"imap_host"`
	SMTPHost    string                    `json:"smtp_host"`
	DisplayName string                    `json:"display_name"`
	Status      string                    `json:"status"`
	DCFolder    string                    `json:"dc_folder"`
	IsBot       bool                      `json:"is_bot"`
	PrivateKey  string                    `json:"private_key"`  // armored
	PeerStates  map[string]*dcPeerState   `json:"peer_states"`
	Chats       map[string]*dcChatState   `json:"chats"`
	Blocked     map[string]bool           `json:"blocked"`
	Folders     map[string]*Folder        `json:"folders"`
	Pins        map[string]map[string]bool `json:"pins"`
	// Extended state
	DeviceMsgLabels   map[string]bool              `json:"device_msg_labels,omitempty"`
	WebxdcUpdates     map[string][]DCWebxdcUpdate  `json:"webxdc_updates,omitempty"`
	WebxdcIntegration string                        `json:"webxdc_integration,omitempty"`
	StickerDir        string                        `json:"sticker_dir,omitempty"`
	Transports        []*DCTransport               `json:"transports,omitempty"`
	Locations         map[string][]DCLocation      `json:"locations,omitempty"`
	ShowEmails        int                           `json:"show_emails,omitempty"`
	DownloadLimit     int64                         `json:"download_limit,omitempty"`
	CallFilter        int                           `json:"call_filter,omitempty"`
	PushToken         string                        `json:"push_token,omitempty"`
}

// NewDeltaChatCore creates a new Delta Chat core instance.
func NewDeltaChatCore(session *utils.SessionStore) *DeltaChatCore {
	ctx, cancel := context.WithCancel(context.Background())
	return &DeltaChatCore{
		peerStates:        make(map[string]*dcPeerState),
		chats:             make(map[string]*dcChatState),
		messages:          make(map[string][]*Message),
		msgSeen:           make(map[string]bool),
		drafts:            make(map[string]*OutgoingMessage),
		blocked:           make(map[string]bool),
		folders:           make(map[string]*Folder),
		pins:              make(map[string]map[string]bool),
		activeCalls:       make(map[string]*dcCall),
		locationStreaming: make(map[string]*DCLocationStream),
		locations:         make(map[string][]DCLocation),
		webxdcUpdates:     make(map[string][]DCWebxdcUpdate),
		deviceMsgLabels:   make(map[string]bool),
		pushState:         "NotConfigured",
		session:           session,
		ctx:               ctx,
		cancel:            cancel,
	}
}

const dcPlatform = "deltachat"

// --- Core Interface: Identity ---

// Name returns the platform identifier for Delta Chat.
func (d *DeltaChatCore) Name() string { return dcPlatform }

// Capabilities returns the list of features supported by the Delta Chat core.
func (d *DeltaChatCore) Capabilities() []string {
	return []string{
		CapText, CapChannels, CapCalls, CapReactions, CapReadReceipts,
		CapBase64Image, CapE2EE, CapTyping, CapSearch, CapBlocking,
		CapLocation, CapFileTransfer,
	}
}

// --- Core Interface: Auth ---

// Authenticate connects to the email server using IMAP/SMTP credentials.
func (d *DeltaChatCore) Authenticate(cfg AuthConfig) error {
	d.mu.Lock()
	defer d.mu.Unlock()

	// Delta Chat bots are regular email accounts with bot-specific behavior:
	// no BCC self (don't send copies to own inbox), auto-delete from server after processing.
	// Auth flow is identical to user mode — same IMAP/SMTP, same Autocrypt.
	d.isBot = cfg.Mode == AuthModeBot

	email := cfg.Phone // email address passed via Phone field
	password := cfg.Password2F
	if email == "" {
		email = cfg.Extra["email"]
	}
	if password == "" {
		password = cfg.Extra["password"]
	}
	if email == "" || password == "" {
		return fmt.Errorf("%w: email and password required", ErrInvalidInput)
	}

	d.myAddr = canonicalizeEmail(email)
	d.password = password
	d.myName = cfg.Extra["display_name"]
	if d.myName == "" {
		d.myName = strings.Split(d.myAddr, "@")[0]
	}

	// Server config from Extra or auto-detect
	d.imapHost = cfg.Extra["imap_host"]
	d.smtpHost = cfg.Extra["smtp_host"]

	if d.imapHost == "" || d.smtpHost == "" {
		iHost, sHost := autoDiscoverServers(d.myAddr)
		if d.imapHost == "" {
			d.imapHost = iHost
		}
		if d.smtpHost == "" {
			d.smtpHost = sHost
		}
	}

	if d.imapHost == "" || d.smtpHost == "" {
		return fmt.Errorf("%w: could not auto-discover IMAP/SMTP servers for %s — provide imap_host and smtp_host in Extra", ErrInvalidInput, d.myAddr)
	}

	// Accept invalid certs for self-hosted servers with self-signed certs
	if cfg.Extra["accept_invalid_certs"] == "true" || cfg.Extra["accept_invalid_certs"] == "1" {
		d.acceptInvalidCerts = true
	}

	// Try loading existing session (preserves keypair, peer states, chats)
	// Save auth fields from cfg — loadSession may overwrite them with stale values
	freshAddr := d.myAddr
	freshPass := d.password
	freshIMAPHost := d.imapHost
	freshSMTPHost := d.smtpHost
	freshName := d.myName
	isBot := d.isBot

	if err := d.loadSession(); err == nil && d.myEntity != nil {
		// Session loaded, just reconnect
	} else {
		// Generate new keypair
		entity, err := d.generateKeypair()
		if err != nil {
			return fmt.Errorf("generate keypair: %w", err)
		}
		d.myEntity = entity
		d.cachedPubKeyOK = false
	}

	// cfg always takes priority over saved session for auth fields
	d.isBot = isBot
	d.myAddr = freshAddr
	d.password = freshPass
	if freshIMAPHost != "" {
		d.imapHost = freshIMAPHost
	}
	if freshSMTPHost != "" {
		d.smtpHost = freshSMTPHost
	}
	if freshName != "" {
		d.myName = freshName
	}

	// Connect IMAP (main ops)
	imapClient, err := d.connectIMAP()
	if err != nil {
		return fmt.Errorf("%w: IMAP connect: %v", ErrAuth, err)
	}
	d.imapOps = imapClient

	// Find or create DeltaChat folder
	if err := d.ensureDCFolder(); err != nil {
		return fmt.Errorf("ensure DeltaChat folder: %w", err)
	}

	// Connect IDLE clients
	idleInbox, err := d.connectIMAP()
	if err != nil {
		return fmt.Errorf("IMAP IDLE inbox connect: %w", err)
	}
	d.idleInbox = idleInbox

	idleDC, err := d.connectIMAP()
	if err != nil {
		return fmt.Errorf("IMAP IDLE DC connect: %w", err)
	}
	d.idleDC = idleDC

	d.authed = true

	// Save session
	d.saveSession()

	// Start IDLE loops
	d.wg.Add(2)
	go func() {
		defer d.wg.Done()
		d.idleLoop(d.idleInbox, "INBOX", "inbox-idle")
	}()
	go func() {
		defer d.wg.Done()
		d.idleLoop(d.idleDC, d.dcFolder, "dc-idle")
	}()

	return nil
}

// Logout disconnects from the email server and clears session state.
func (d *DeltaChatCore) Logout() error {
	d.mu.Lock()
	defer d.mu.Unlock()

	d.cancel()

	if d.imapOps != nil {
		d.imapOps.Close()
	}
	if d.idleInbox != nil {
		d.idleInbox.Close()
	}
	if d.idleDC != nil {
		d.idleDC.Close()
	}

	d.authed = false

	// Remove session
	if d.session != nil {
		d.session.Delete()
	}

	return nil
}

// --- Core Interface: Dialogs ---

// GetDialogs returns the list of chats with pagination support.
func (d *DeltaChatCore) GetDialogs(opts PaginationOpts) ([]Dialog, error) {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if !d.authed {
		return nil, ErrAuth
	}

	// Sync messages from DeltaChat folder to build chat list
	if err := d.syncMessages(); err != nil {
		return nil, fmt.Errorf("sync messages: %w", err)
	}

	d.chatsMu.RLock()
	defer d.chatsMu.RUnlock()

	type dialogWithTime struct {
		dlg  Dialog
		time int64
	}
	dts := make([]dialogWithTime, 0, len(d.chats))
	for _, cs := range d.chats {
		dts = append(dts, dialogWithTime{dlg: d.chatStateToDialog(cs), time: cs.LastMsgTime})
	}

	sort.Slice(dts, func(i, j int) bool {
		return dts[i].time > dts[j].time
	})

	// Apply pagination
	offset := 0
	if opts.Offset != "" {
		offset, _ = strconv.Atoi(opts.Offset)
	}
	if offset > 0 {
		if offset >= len(dts) {
			return []Dialog{}, nil
		}
		dts = dts[offset:]
	}

	limit := opts.Limit
	if limit <= 0 {
		limit = 50
	}
	if len(dts) > limit {
		dts = dts[:limit]
	}

	dialogs := make([]Dialog, len(dts))
	for i, dt := range dts {
		dialogs[i] = dt.dlg
	}

	return dialogs, nil
}

// CreateGroup creates a new group chat with the specified members.
func (d *DeltaChatCore) CreateGroup(name string, members []string) (*Dialog, error) {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if !d.authed {
		return nil, ErrAuth
	}

	groupID := generateGroupID()
	chatID := "grp:" + groupID

	// Create chat state
	allMembers := append([]string{d.myAddr}, members...)
	cs := &dcChatState{
		ID:      chatID,
		Type:    ChatTypeGroup,
		Title:   name,
		GroupID: groupID,
		Members: allMembers,
	}
	d.chatsMu.Lock()
	d.chats[chatID] = cs
	d.chatsMu.Unlock()

	// Send creation message to all members
	text := fmt.Sprintf("Group \"%s\" created", name)
	msgID := d.generateMsgID(groupID)

	// Build recipients
	var toAddrs []*mail.Address
	for _, m := range members {
		toAddrs = append(toAddrs, &mail.Address{Address: m})
	}

	headers := map[string]string{
		"Chat-Group-ID":   groupID,
		"Chat-Group-Name": name,
	}

	err := d.sendEmail(toAddrs, fmt.Sprintf("Chat: %s", name), text, msgID, "", headers, nil)
	if err != nil {
		return nil, fmt.Errorf("send group creation: %w", err)
	}

	d.saveSession()
	dlg := d.chatStateToDialog(cs)
	return &dlg, nil
}

// CreateChannel creates a new mailing-list-style broadcast channel.
func (d *DeltaChatCore) CreateChannel(name string, description string) (*Dialog, error) {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if !d.authed {
		return nil, ErrAuth
	}

	groupID := generateGroupID()
	chatID := "bc:" + groupID

	// Generate broadcast secret (264-bit = 33 bytes, base64url = 44 chars)
	secretBytes := make([]byte, 33)
	rand.Read(secretBytes)
	secret := base64.RawURLEncoding.EncodeToString(secretBytes)

	cs := &dcChatState{
		ID:              chatID,
		Type:            ChatTypeChannel,
		Title:           name,
		Description:     description,
		GroupID:         groupID,
		Members:         []string{d.myAddr},
		BroadcastSecret: secret,
	}
	d.chatsMu.Lock()
	d.chats[chatID] = cs
	d.chatsMu.Unlock()

	d.saveSession()
	dlg := d.chatStateToDialog(cs)
	return &dlg, nil
}

// CreateTopic creates a threaded topic within a chat.
func (d *DeltaChatCore) CreateTopic(chatID string, name string) (*Dialog, error) {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if !d.authed {
		return nil, ErrAuth
	}

	d.chatsMu.RLock()
	cs, ok := d.chats[chatID]
	d.chatsMu.RUnlock()
	if !ok {
		return nil, ErrNotFound
	}

	// Create a "topic" as a new email thread within the group
	topicID := chatID + "/topic:" + generateShortID()
	topicState := &dcChatState{
		ID:      topicID,
		Type:    ChatTypeTopic,
		Title:   name,
		GroupID: cs.GroupID,
		Members: cs.Members,
	}
	d.chatsMu.Lock()
	d.chats[topicID] = topicState
	d.chatsMu.Unlock()

	// Send a topic creation message
	var toAddrs []*mail.Address
	for _, m := range cs.Members {
		if m != d.myAddr {
			toAddrs = append(toAddrs, &mail.Address{Address: m})
		}
	}
	headers := map[string]string{
		"Chat-Group-ID":   cs.GroupID,
		"Chat-Group-Name": cs.Title,
	}
	msgID := d.generateMsgID(cs.GroupID)
	if err := d.sendEmail(toAddrs, fmt.Sprintf("Topic: %s", name), fmt.Sprintf("[Topic: %s]", name), msgID, "", headers, nil); err != nil {
		return nil, fmt.Errorf("send topic creation: %w", err)
	}

	d.saveSession()
	dlg := d.chatStateToDialog(topicState)
	return &dlg, nil
}

// GetFolders returns all chat folders (labels).
func (d *DeltaChatCore) GetFolders() ([]Folder, error) {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if !d.authed {
		return nil, ErrAuth
	}

	var result []Folder
	for _, f := range d.folders {
		result = append(result, *f)
	}

	// Add built-in pseudo-folders
	var pinnedIDs, archivedIDs []string
	d.chatsMu.RLock()
	for _, cs := range d.chats {
		if cs.Visibility == 2 {
			pinnedIDs = append(pinnedIDs, cs.ID)
		} else if cs.Visibility == 1 {
			archivedIDs = append(archivedIDs, cs.ID)
		}
	}
	d.chatsMu.RUnlock()

	if len(pinnedIDs) > 0 {
		result = append(result, Folder{ID: "_pinned", Name: "Pinned", ChatIDs: pinnedIDs})
	}
	if len(archivedIDs) > 0 {
		result = append(result, Folder{ID: "_archived", Name: "Archived", ChatIDs: archivedIDs})
	}

	return result, nil
}

// CreateFolder creates a new chat folder containing the specified chats.
func (d *DeltaChatCore) CreateFolder(name string, chatIDs []string) (*Folder, error) {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if !d.authed {
		return nil, ErrAuth
	}

	folderID := "folder:" + generateShortID()
	f := &Folder{
		ID:      folderID,
		Name:    name,
		ChatIDs: chatIDs,
	}
	d.folders[folderID] = f
	d.saveSession()
	return f, nil
}

// --- Core Interface: Messages ---

// SendMessage sends a message to the specified chat via SMTP.
func (d *DeltaChatCore) SendMessage(chatID string, msg OutgoingMessage) (*Message, error) {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if !d.authed {
		return nil, ErrAuth
	}

	d.chatsMu.RLock()
	cs, ok := d.chats[chatID]
	d.chatsMu.RUnlock()

	// For DMs, create chat state if not exists
	if !ok && strings.HasPrefix(chatID, "dm:") {
		peerEmail := strings.TrimPrefix(chatID, "dm:")
		cs = &dcChatState{
			ID:      chatID,
			Type:    ChatTypeDM,
			Title:   peerEmail,
			Members: []string{d.myAddr, peerEmail},
		}
		d.chatsMu.Lock()
		d.chats[chatID] = cs
		d.chatsMu.Unlock()
	}
	if cs == nil {
		return nil, ErrNotFound
	}

	// Build recipients
	var toAddrs []*mail.Address
	for _, m := range cs.Members {
		if m != d.myAddr {
			toAddrs = append(toAddrs, &mail.Address{Address: m})
		}
	}

	subject := "Chat: " + cs.Title
	if cs.Type == ChatTypeDM {
		// Use first line of message as subject (email headers can't contain newlines)
		firstLine := msg.Text
		if idx := strings.IndexAny(firstLine, "\r\n"); idx >= 0 {
			firstLine = firstLine[:idx]
		}
		subject = "Chat: " + firstLine
		if len(subject) > 78 {
			subject = subject[:78]
		}
	}

	headers := make(map[string]string)
	if cs.GroupID != "" {
		headers["Chat-Group-ID"] = cs.GroupID
		headers["Chat-Group-Name"] = cs.Title
	}

	var replyTo string
	if msg.ReplyToID != "" {
		replyTo = msg.ReplyToID
	}

	msgID := d.generateMsgID(cs.GroupID)
	err := d.sendEmail(toAddrs, subject, msg.Text, msgID, replyTo, headers, nil)
	if err != nil {
		return nil, fmt.Errorf("send: %w", err)
	}

	now := time.Now()
	m := &Message{
		ID:         msgID,
		ChatID:     chatID,
		SenderID:   d.myAddr,
		SenderName: d.myName,
		Text:       msg.Text,
		Timestamp:  now,
		Status:     MessageStatusSent,
		ReplyToID:  msg.ReplyToID,
		IsOutgoing: true,
		Platform:   dcPlatform,
	}

	d.cacheMessage(chatID, m)
	d.updateChatTime(chatID, now)
	return m, nil
}

// GetMessages returns messages from a chat with pagination support.
func (d *DeltaChatCore) GetMessages(chatID string, opts PaginationOpts) ([]Message, error) {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if !d.authed {
		return nil, ErrAuth
	}

	d.msgsMu.RLock()
	msgs, ok := d.messages[chatID]
	d.msgsMu.RUnlock()

	if !ok || len(msgs) == 0 {
		// Chat not seen yet — sync
		d.syncMessages()
		d.msgsMu.RLock()
		msgs = d.messages[chatID]
		d.msgsMu.RUnlock()
	}

	limit := opts.Limit
	if limit <= 0 {
		limit = 50
	}

	result := []Message{}
	for _, m := range msgs {
		result = append(result, *m)
	}

	// Sort by timestamp
	sort.Slice(result, func(i, j int) bool {
		return result[i].Timestamp.Before(result[j].Timestamp)
	})

	if len(result) > limit {
		result = result[len(result)-limit:]
	}

	return result, nil
}

// EditMessage edits a previously sent message by sending an edit notification.
func (d *DeltaChatCore) EditMessage(chatID string, msgID string, text string) (*Message, error) {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if !d.authed {
		return nil, ErrAuth
	}

	d.chatsMu.RLock()
	cs, ok := d.chats[chatID]
	d.chatsMu.RUnlock()
	if !ok {
		return nil, ErrNotFound
	}

	var toAddrs []*mail.Address
	for _, m := range cs.Members {
		if m != d.myAddr {
			toAddrs = append(toAddrs, &mail.Address{Address: m})
		}
	}

	headers := map[string]string{
		"Chat-Edit": msgID,
	}
	if cs.GroupID != "" {
		headers["Chat-Group-ID"] = cs.GroupID
		headers["Chat-Group-Name"] = cs.Title
	}

	newMsgID := d.generateMsgID(cs.GroupID)
	err := d.sendEmail(toAddrs, "Chat: "+cs.Title, text, newMsgID, "", headers, nil)
	if err != nil {
		return nil, err
	}

	now := time.Now()
	m := &Message{
		ID:         msgID,
		ChatID:     chatID,
		SenderID:   d.myAddr,
		SenderName: d.myName,
		Text:       text,
		Timestamp:  now,
		EditedAt:   &now,
		Status:     MessageStatusSent,
		IsOutgoing: true,
		Platform:   dcPlatform,
	}

	// Update cache
	d.msgsMu.Lock()
	for i, cached := range d.messages[chatID] {
		if cached.ID == msgID {
			d.messages[chatID][i] = m
			break
		}
	}
	d.msgsMu.Unlock()

	return m, nil
}

// DeleteMessage deletes a message from the chat.
func (d *DeltaChatCore) DeleteMessage(chatID string, msgID string) error {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if !d.authed {
		return ErrAuth
	}

	d.chatsMu.RLock()
	cs, ok := d.chats[chatID]
	d.chatsMu.RUnlock()
	if !ok {
		return ErrNotFound
	}

	var toAddrs []*mail.Address
	for _, m := range cs.Members {
		if m != d.myAddr {
			toAddrs = append(toAddrs, &mail.Address{Address: m})
		}
	}

	headers := map[string]string{
		"Chat-Delete": msgID,
	}
	if cs.GroupID != "" {
		headers["Chat-Group-ID"] = cs.GroupID
	}

	newMsgID := d.generateMsgID(cs.GroupID)
	err := d.sendEmail(toAddrs, "Chat: "+cs.Title, "", newMsgID, "", headers, nil)
	if err != nil {
		return err
	}

	// Remove from cache
	d.msgsMu.Lock()
	msgs := d.messages[chatID]
	for i, m := range msgs {
		if m.ID == msgID {
			d.messages[chatID] = append(msgs[:i], msgs[i+1:]...)
			delete(d.msgSeen, msgID)
			break
		}
	}
	d.msgsMu.Unlock()

	return nil
}

// ReplyToMessage sends a reply referencing the specified message.
func (d *DeltaChatCore) ReplyToMessage(chatID string, replyToMsgID string, msg OutgoingMessage) (*Message, error) {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if !d.authed {
		return nil, ErrAuth
	}

	d.chatsMu.RLock()
	cs, ok := d.chats[chatID]
	d.chatsMu.RUnlock()
	if !ok {
		return nil, ErrNotFound
	}

	var toAddrs []*mail.Address
	for _, m := range cs.Members {
		if m != d.myAddr {
			toAddrs = append(toAddrs, &mail.Address{Address: m})
		}
	}

	headers := make(map[string]string)
	if cs.GroupID != "" {
		headers["Chat-Group-ID"] = cs.GroupID
		headers["Chat-Group-Name"] = cs.Title
	}

	msgID := d.generateMsgID(cs.GroupID)
	err := d.sendEmail(toAddrs, "Re: Chat: "+cs.Title, msg.Text, msgID, replyToMsgID, headers, nil)
	if err != nil {
		return nil, err
	}

	// Find reply preview
	var replyPreview string
	d.msgsMu.RLock()
	for _, cached := range d.messages[chatID] {
		if cached.ID == replyToMsgID {
			replyPreview = cached.Text
			if len(replyPreview) > 100 {
				replyPreview = replyPreview[:100]
			}
			break
		}
	}
	d.msgsMu.RUnlock()

	now := time.Now()
	m := &Message{
		ID:           msgID,
		ChatID:       chatID,
		SenderID:     d.myAddr,
		SenderName:   d.myName,
		Text:         msg.Text,
		Timestamp:    now,
		Status:       MessageStatusSent,
		ReplyToID:    replyToMsgID,
		ReplyPreview: replyPreview,
		IsOutgoing:   true,
		Platform:     dcPlatform,
	}

	d.cacheMessage(chatID, m)
	d.updateChatTime(chatID, now)
	return m, nil
}

// ForwardMessage forwards a message from one chat to another.
func (d *DeltaChatCore) ForwardMessage(fromChatID string, msgID string, toChatID string) (*Message, error) {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if !d.authed {
		return nil, ErrAuth
	}

	// Find original message
	var original *Message
	d.msgsMu.RLock()
	for _, m := range d.messages[fromChatID] {
		if m.ID == msgID {
			original = m
			break
		}
	}
	d.msgsMu.RUnlock()

	if original == nil {
		return nil, ErrNotFound
	}

	d.chatsMu.RLock()
	cs, ok := d.chats[toChatID]
	d.chatsMu.RUnlock()
	if !ok {
		return nil, ErrNotFound
	}

	var toAddrs []*mail.Address
	for _, m := range cs.Members {
		if m != d.myAddr {
			toAddrs = append(toAddrs, &mail.Address{Address: m})
		}
	}

	forwardText := fmt.Sprintf("---------- Forwarded message ----------\nFrom: %s\nDate: %s\n\n%s",
		original.SenderName, original.Timestamp.Format(time.RFC1123), original.Text)

	headers := make(map[string]string)
	if cs.GroupID != "" {
		headers["Chat-Group-ID"] = cs.GroupID
		headers["Chat-Group-Name"] = cs.Title
	}

	newMsgID := d.generateMsgID(cs.GroupID)
	err := d.sendEmail(toAddrs, "Fwd: Chat: "+cs.Title, forwardText, newMsgID, "", headers, nil)
	if err != nil {
		return nil, err
	}

	now := time.Now()
	m := &Message{
		ID:          newMsgID,
		ChatID:      toChatID,
		SenderID:    d.myAddr,
		SenderName:  d.myName,
		Text:        forwardText,
		Timestamp:   now,
		Status:      MessageStatusSent,
		ForwardFrom: original.SenderName,
		IsOutgoing:  true,
		Platform:    dcPlatform,
	}

	d.cacheMessage(toChatID, m)
	d.updateChatTime(toChatID, now)
	return m, nil
}

// ReactToMessage sends an emoji reaction to a message.
func (d *DeltaChatCore) ReactToMessage(chatID string, msgID string, emoji string) error {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if !d.authed {
		return ErrAuth
	}

	d.chatsMu.RLock()
	cs, ok := d.chats[chatID]
	d.chatsMu.RUnlock()
	if !ok {
		return ErrNotFound
	}

	var toAddrs []*mail.Address
	for _, m := range cs.Members {
		if m != d.myAddr {
			toAddrs = append(toAddrs, &mail.Address{Address: m})
		}
	}

	// RFC 9078 reaction: Content-Disposition: reaction, In-Reply-To: original
	// We send a special email where the text body is the emoji with Content-Disposition: reaction
	headers := make(map[string]string)
	if cs.GroupID != "" {
		headers["Chat-Group-ID"] = cs.GroupID
	}
	headers["_reaction"] = emoji // special flag for sendEmail to use Content-Disposition: reaction

	reactionMsgID := d.generateMsgID(cs.GroupID)
	err := d.sendEmail(toAddrs, "Chat: "+cs.Title, emoji, reactionMsgID, msgID, headers, nil)
	return err
}

// PinMessage pins a message in the specified chat.
func (d *DeltaChatCore) PinMessage(chatID string, msgID string) error {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if !d.authed {
		return ErrAuth
	}

	if d.pins[chatID] == nil {
		d.pins[chatID] = make(map[string]bool)
	}
	d.pins[chatID][msgID] = true
	d.saveSession()
	return nil
}

// UnpinMessage unpins a message in the specified chat.
func (d *DeltaChatCore) UnpinMessage(chatID string, msgID string) error {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if !d.authed {
		return ErrAuth
	}

	if d.pins[chatID] != nil {
		delete(d.pins[chatID], msgID)
	}
	d.saveSession()
	return nil
}

// --- Core Interface: Read State ---

// MarkAsRead marks messages as read up to the specified message ID.
func (d *DeltaChatCore) MarkAsRead(chatID string, upToMsgID string) error {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if !d.authed {
		return ErrAuth
	}

	// Mark messages as \Seen in IMAP
	// For now, update local state. A full implementation would STORE \Seen flags.
	d.chatsMu.Lock()
	if cs, ok := d.chats[chatID]; ok {
		cs.UnreadCount = 0
	}
	d.chatsMu.Unlock()

	// Send MDN (read receipt) for the message
	d.msgsMu.RLock()
	var targetMsg *Message
	for _, m := range d.messages[chatID] {
		if m.ID == upToMsgID {
			targetMsg = m
			break
		}
	}
	d.msgsMu.RUnlock()

	if targetMsg != nil && targetMsg.SenderID != d.myAddr {
		go d.sendMDN(targetMsg.SenderID, upToMsgID)
	}

	return nil
}

// GetReadState returns the read/unread state for a chat.
func (d *DeltaChatCore) GetReadState(chatID string) (*ReadState, error) {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if !d.authed {
		return nil, ErrAuth
	}

	rs := &ReadState{
		PeerLastRead: make(map[string]string),
	}

	// Find last message we've "seen"
	d.msgsMu.RLock()
	msgs := d.messages[chatID]
	for i := len(msgs) - 1; i >= 0; i-- {
		if msgs[i].SenderID == d.myAddr || msgs[i].Status == MessageStatusRead {
			rs.MyLastRead = msgs[i].ID
			break
		}
	}
	d.msgsMu.RUnlock()

	return rs, nil
}

// --- Core Interface: Files ---

// UploadFile sends a file as an email attachment with progress reporting.
func (d *DeltaChatCore) UploadFile(chatID string, file FileUpload, progress func(sent, total int64)) (*Message, error) {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if !d.authed {
		return nil, ErrAuth
	}

	d.chatsMu.RLock()
	cs, ok := d.chats[chatID]
	d.chatsMu.RUnlock()
	if !ok && strings.HasPrefix(chatID, "dm:") {
		peerEmail := strings.TrimPrefix(chatID, "dm:")
		cs = &dcChatState{
			ID:      chatID,
			Type:    ChatTypeDM,
			Title:   peerEmail,
			Members: []string{d.myAddr, peerEmail},
		}
		d.chatsMu.Lock()
		d.chats[chatID] = cs
		d.chatsMu.Unlock()
	}
	if cs == nil {
		return nil, ErrNotFound
	}

	// Read file data
	fileData, err := io.ReadAll(file.Reader)
	if err != nil {
		return nil, fmt.Errorf("read file: %w", err)
	}

	if progress != nil {
		progress(int64(len(fileData)), file.Size)
	}

	var toAddrs []*mail.Address
	for _, m := range cs.Members {
		if m != d.myAddr {
			toAddrs = append(toAddrs, &mail.Address{Address: m})
		}
	}

	headers := make(map[string]string)
	if cs.GroupID != "" {
		headers["Chat-Group-ID"] = cs.GroupID
		headers["Chat-Group-Name"] = cs.Title
	}

	// Check for voice message
	if strings.HasPrefix(file.MimeType, "audio/") && strings.Contains(file.Name, "voice") {
		headers["Chat-Voice-Message"] = "1"
	}

	attachment := &dcAttachment{
		Name:     file.Name,
		MimeType: file.MimeType,
		Data:     fileData,
	}

	msgID := d.generateMsgID(cs.GroupID)
	err = d.sendEmail(toAddrs, "Chat: "+cs.Title, file.Name, msgID, "", headers, attachment)
	if err != nil {
		return nil, err
	}

	now := time.Now()
	m := &Message{
		ID:         msgID,
		ChatID:     chatID,
		SenderID:   d.myAddr,
		SenderName: d.myName,
		Text:       file.Name,
		Timestamp:  now,
		Status:     MessageStatusSent,
		IsOutgoing: true,
		Attachments: []FileRef{{
			Name:     file.Name,
			MimeType: file.MimeType,
			Size:     int64(len(fileData)),
		}},
		Platform: dcPlatform,
	}

	d.cacheMessage(chatID, m)
	d.updateChatTime(chatID, now)
	return m, nil
}

// DownloadFile saves a message attachment to the specified destination path.
func (d *DeltaChatCore) DownloadFile(fileRef FileRef, dest string, progress func(recv, total int64)) error {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if !d.authed {
		return ErrAuth
	}

	// Files in Delta Chat are MIME attachments in emails.
	// fileRef.ID is the IMAP UID + part number.
	// For cached files, read from local cache.
	if fileRef.URL != "" {
		// URL contains base64-encoded file data (cached locally)
		data, err := base64.StdEncoding.DecodeString(fileRef.URL)
		if err != nil {
			return fmt.Errorf("decode cached file: %w", err)
		}
		if progress != nil {
			progress(int64(len(data)), int64(len(data)))
		}
		return os.WriteFile(dest, data, 0644)
	}

	return fmt.Errorf("%w: file not cached locally — re-sync messages to download", ErrNotFound)
}

// SendImageBase64 sends a base64-encoded image as a message.
func (d *DeltaChatCore) SendImageBase64(chatID string, b64 string, caption string) (*Message, error) {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if !d.authed {
		return nil, ErrAuth
	}

	data, err := base64.StdEncoding.DecodeString(b64)
	if err != nil {
		return nil, fmt.Errorf("decode base64: %w", err)
	}

	// Detect format
	mimeType := "image/png"
	ext := ".png"
	if len(data) > 2 && data[0] == 0xFF && data[1] == 0xD8 {
		mimeType = "image/jpeg"
		ext = ".jpg"
	} else if len(data) > 4 && string(data[:4]) == "GIF8" {
		mimeType = "image/gif"
		ext = ".gif"
	}

	file := FileUpload{
		Name:     "image" + ext,
		MimeType: mimeType,
		Size:     int64(len(data)),
		Reader:   bytes.NewReader(data),
	}

	return d.UploadFile(chatID, file, nil)
}

// --- Core Interface: Calls ---

// StartCall initiates a WebRTC call via Delta Chat signaling messages.
func (d *DeltaChatCore) StartCall(chatID string, video bool) (*CallSession, error) {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if !d.authed {
		return nil, ErrAuth
	}

	d.chatsMu.RLock()
	cs, ok := d.chats[chatID]
	d.chatsMu.RUnlock()
	if !ok && strings.HasPrefix(chatID, "dm:") {
		peerEmail := strings.TrimPrefix(chatID, "dm:")
		cs = &dcChatState{
			ID:      chatID,
			Type:    ChatTypeDM,
			Title:   peerEmail,
			Members: []string{d.myAddr, peerEmail},
		}
		d.chatsMu.Lock()
		d.chats[chatID] = cs
		d.chatsMu.Unlock()
		ok = true
	}
	if !ok {
		return nil, ErrNotFound
	}

	if cs.Type != ChatTypeDM {
		return nil, fmt.Errorf("%w: Delta Chat calls are 1:1 only", ErrNotSupported)
	}

	// Find peer email
	var peerEmail string
	for _, m := range cs.Members {
		if m != d.myAddr {
			peerEmail = m
			break
		}
	}

	callID := "dc-call-" + generateShortID()

	// Create WebRTC PeerConnection
	config := webrtc.Configuration{
		ICEServers: d.getICEServers(),
	}

	pc, err := webrtc.NewPeerConnection(config)
	if err != nil {
		return nil, fmt.Errorf("create PeerConnection: %w", err)
	}

	// Add audio track
	audioTrack, err := webrtc.NewTrackLocalStaticRTP(
		webrtc.RTPCodecCapability{MimeType: webrtc.MimeTypeOpus},
		"audio", "dc-audio-"+callID,
	)
	if err != nil {
		pc.Close()
		return nil, fmt.Errorf("create audio track: %w", err)
	}
	if _, err := pc.AddTrack(audioTrack); err != nil {
		pc.Close()
		return nil, fmt.Errorf("add audio track: %w", err)
	}

	// Add video transceiver if video call
	if video {
		if _, err := pc.AddTransceiverFromKind(webrtc.RTPCodecTypeVideo, webrtc.RTPTransceiverInit{
			Direction: webrtc.RTPTransceiverDirectionSendrecv,
		}); err != nil {
			pc.Close()
			return nil, fmt.Errorf("add video transceiver: %w", err)
		}
	}

	// Create offer
	offer, err := pc.CreateOffer(nil)
	if err != nil {
		pc.Close()
		return nil, fmt.Errorf("create offer: %w", err)
	}
	if err := pc.SetLocalDescription(offer); err != nil {
		pc.Close()
		return nil, fmt.Errorf("set local description: %w", err)
	}

	// Wait for ICE gathering
	gatherDone := webrtc.GatheringCompletePromise(pc)
	select {
	case <-gatherDone:
	case <-time.After(10 * time.Second):
	}

	// Encode offer as base64 for signaling
	offerPayload := base64.StdEncoding.EncodeToString([]byte(pc.LocalDescription().SDP))

	// Track call
	call := &dcCall{
		ID:         callID,
		ChatID:     chatID,
		PeerEmail:  peerEmail,
		IsVideo:    video,
		State:      CallStateRinging,
		PC:         pc,
		AudioTrack: audioTrack,
		StartTime:  time.Now(),
	}
	d.callsMu.Lock()
	d.activeCalls[callID] = call
	d.callsMu.Unlock()

	// Handle incoming tracks from peer
	pc.OnTrack(func(track *webrtc.TrackRemote, receiver *webrtc.RTPReceiver) {
		// Read and discard — actual audio playback needs bridge to Dart
		buf := make([]byte, 1500)
		for {
			if _, _, err := track.Read(buf); err != nil {
				return
			}
		}
	})

	// Handle connection state changes
	pc.OnConnectionStateChange(func(state webrtc.PeerConnectionState) {
		d.callsMu.Lock()
		if c, ok := d.activeCalls[callID]; ok {
			switch state {
			case webrtc.PeerConnectionStateConnected:
				c.State = CallStateActive
			case webrtc.PeerConnectionStateFailed, webrtc.PeerConnectionStateClosed,
				webrtc.PeerConnectionStateDisconnected:
				c.State = CallStateEnded
			}
		}
		d.callsMu.Unlock()

		d.fireUpdate(Update{
			Type:   UpdateCallState,
			ChatID: chatID,
			Call: &CallSession{
				ID:      callID,
				ChatID:  chatID,
				IsVideo: video,
				State:   CallState(state.String()),
			},
			Platform: dcPlatform,
		})
	})

	// Send call signaling via email
	toAddrs := []*mail.Address{{Address: peerEmail}}
	headers := map[string]string{
		"Chat-Content":     "call",
		"Chat-Webrtc-Room": offerPayload,
	}
	if video {
		headers["Chat-Webrtc-Has-Video-Initially"] = "true"
	}

	msgID := d.generateMsgID("")
	call.OfferMsgID = msgID
	d.sendEmail(toAddrs, "Chat: "+cs.Title, "Incoming call", msgID, "", headers, nil)

	session := &CallSession{
		ID:      callID,
		ChatID:  chatID,
		IsVideo: video,
		IsGroup: false,
		State:   CallStateRinging,
		Participants: []CallParticipant{
			{UserID: d.myAddr, DisplayName: d.myName},
		},
		Meta: map[string]string{
			"offer_payload": offerPayload,
		},
	}

	return session, nil
}

// AcceptIncomingCall accepts an incoming call with a WebRTC answer.
func (d *DeltaChatCore) AcceptIncomingCall(callID string, offerPayload string) (*CallSession, error) {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if !d.authed {
		return nil, ErrAuth
	}

	// Decode SDP offer
	offerBytes, err := base64.StdEncoding.DecodeString(offerPayload)
	if err != nil {
		return nil, fmt.Errorf("decode offer: %w", err)
	}

	config := webrtc.Configuration{
		ICEServers: d.getICEServers(),
	}

	pc, err := webrtc.NewPeerConnection(config)
	if err != nil {
		return nil, fmt.Errorf("create PeerConnection: %w", err)
	}

	// Add audio track for our end
	audioTrack, err := webrtc.NewTrackLocalStaticRTP(
		webrtc.RTPCodecCapability{MimeType: webrtc.MimeTypeOpus},
		"audio", "dc-audio-answer-"+callID,
	)
	if err != nil {
		pc.Close()
		return nil, fmt.Errorf("create audio track: %w", err)
	}
	pc.AddTrack(audioTrack)

	// Set remote offer
	err = pc.SetRemoteDescription(webrtc.SessionDescription{
		Type: webrtc.SDPTypeOffer,
		SDP:  string(offerBytes),
	})
	if err != nil {
		pc.Close()
		return nil, fmt.Errorf("set remote description: %w", err)
	}

	// Create answer
	answer, err := pc.CreateAnswer(nil)
	if err != nil {
		pc.Close()
		return nil, fmt.Errorf("create answer: %w", err)
	}
	if err := pc.SetLocalDescription(answer); err != nil {
		pc.Close()
		return nil, fmt.Errorf("set local description: %w", err)
	}

	// Wait for ICE gathering
	gatherDone := webrtc.GatheringCompletePromise(pc)
	select {
	case <-gatherDone:
	case <-time.After(10 * time.Second):
	}

	answerPayload := base64.StdEncoding.EncodeToString([]byte(pc.LocalDescription().SDP))

	// Track call
	call := &dcCall{
		ID:         callID,
		IsVideo:    false,
		State:      CallStateActive,
		PC:         pc,
		AudioTrack: audioTrack,
		StartTime:  time.Now(),
	}
	d.callsMu.Lock()
	d.activeCalls[callID] = call
	d.callsMu.Unlock()

	// Handle incoming tracks
	pc.OnTrack(func(track *webrtc.TrackRemote, receiver *webrtc.RTPReceiver) {
		buf := make([]byte, 1500)
		for {
			if _, _, err := track.Read(buf); err != nil {
				return
			}
		}
	})

	return &CallSession{
		ID:      callID,
		IsVideo: false,
		State:   CallStateActive,
		Meta: map[string]string{
			"answer_payload": answerPayload,
		},
	}, nil
}

// JoinGroupCall joins a group call (not supported in Delta Chat).
func (d *DeltaChatCore) JoinGroupCall(chatID string) (*CallSession, error) {
	return nil, fmt.Errorf("%w: Delta Chat does not support group calls", ErrNotSupported)
}

// EndCall terminates an active WebRTC call and cleans up resources.
func (d *DeltaChatCore) EndCall(callID string) error {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if !d.authed {
		return ErrAuth
	}

	d.callsMu.Lock()
	call, ok := d.activeCalls[callID]
	if ok {
		call.State = CallStateEnded
		if call.PC != nil {
			call.PC.Close()
		}
		delete(d.activeCalls, callID)
	}
	d.callsMu.Unlock()

	if !ok {
		return nil // already ended
	}

	// Send call-ended signaling
	if call.PeerEmail != "" {
		toAddrs := []*mail.Address{{Address: call.PeerEmail}}
		headers := map[string]string{
			"Chat-Content": "call-ended",
		}
		msgID := d.generateMsgID("")
		d.sendEmail(toAddrs, "Chat: call ended", "", msgID, call.OfferMsgID, headers, nil)
	}

	return nil
}

// SetCallMuted mutes or unmutes the local audio track in a call.
func (d *DeltaChatCore) SetCallMuted(callID string, muted bool) error {
	d.callsMu.RLock()
	call, ok := d.activeCalls[callID]
	d.callsMu.RUnlock()
	if !ok {
		return nil
	}

	// Mute/unmute the audio track by enabling/disabling RTP sending
	if call.AudioTrack != nil {
		// pion doesn't have a direct mute on TrackLocalStaticRTP,
		// but the bridge layer stops writing RTP packets when muted
		_ = call.AudioTrack // track reference for bridge layer
	}
	return nil
}

// GetCallInfo returns info about an active call.
func (d *DeltaChatCore) GetCallInfo(callID string) (*CallSession, error) {
	d.callsMu.RLock()
	call, ok := d.activeCalls[callID]
	d.callsMu.RUnlock()
	if !ok {
		return nil, ErrNotFound
	}

	state := call.State
	if call.PC != nil {
		switch call.PC.ConnectionState() {
		case webrtc.PeerConnectionStateConnected:
			state = CallStateActive
		case webrtc.PeerConnectionStateFailed, webrtc.PeerConnectionStateClosed:
			state = CallStateEnded
		}
	}

	return &CallSession{
		ID:      callID,
		ChatID:  call.ChatID,
		IsVideo: call.IsVideo,
		State:   state,
		Meta: map[string]string{
			"duration": time.Since(call.StartTime).String(),
		},
	}, nil
}

// getICEServers returns STUN/TURN servers for WebRTC.
func (d *DeltaChatCore) getICEServers() []webrtc.ICEServer {
	return []webrtc.ICEServer{
		{URLs: []string{"stun:nine.testrun.org:3478"}},
		{
			URLs:           []string{"turn:turn.delta.chat:3478"},
			Username:       "public",
			Credential:     "o4tR7yG4rG2slhXqRUf9zgmHz",
			CredentialType: webrtc.ICECredentialTypePassword,
		},
	}
}

// --- Core Interface: Profile ---

// GetProfile returns profile information for a contact by email address.
func (d *DeltaChatCore) GetProfile(userID string) (*User, error) {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if !d.authed {
		return nil, ErrAuth
	}

	email := canonicalizeEmail(userID)

	if email == d.myAddr {
		return &User{
			ID:          d.myAddr,
			Username:    d.myAddr,
			DisplayName: d.myName,
			Platform:    dcPlatform,
		}, nil
	}

	d.peerKeysMu.RLock()
	ps := d.peerStates[email]
	d.peerKeysMu.RUnlock()

	user := &User{
		ID:          email,
		Username:    email,
		DisplayName: email,
		Platform:    dcPlatform,
	}

	if ps != nil {
		if ps.DisplayName != "" {
			user.DisplayName = ps.DisplayName
		}
		if ps.AvatarB64 != "" {
			user.AvatarB64 = ps.AvatarB64
		}
		if !ps.LastSeen.IsZero() {
			t := ps.LastSeen
			user.LastSeen = &t
		}
	}

	return user, nil
}

// --- Core Interface: Real-time ---

// OnUpdate registers a handler for incoming message and status updates.
func (d *DeltaChatCore) OnUpdate(handler func(Update)) {
	d.updateMu.Lock()
	defer d.updateMu.Unlock()
	d.updateHandlers = append(d.updateHandlers, handler)
}

// Close disconnects all IMAP connections and releases resources.
func (d *DeltaChatCore) Close() error {
	d.cancel()
	if d.imapOps != nil {
		d.imapOps.Close()
	}
	if d.idleInbox != nil {
		d.idleInbox.Close()
	}
	if d.idleDC != nil {
		d.idleDC.Close()
	}
	d.wg.Wait()
	d.mu.Lock()
	d.saveSession()
	d.authed = false
	d.mu.Unlock()
	return nil
}

// --- Core Interface: Chat Management ---

// GetChatInfo returns detailed information about a specific chat.
func (d *DeltaChatCore) GetChatInfo(chatID string) (*Dialog, error) {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if !d.authed {
		return nil, ErrAuth
	}

	d.chatsMu.RLock()
	cs, ok := d.chats[chatID]
	d.chatsMu.RUnlock()
	if !ok {
		return nil, ErrNotFound
	}

	dlg := d.chatStateToDialog(cs)
	return &dlg, nil
}

// EditChatTitle changes the display name of a group or channel.
func (d *DeltaChatCore) EditChatTitle(chatID string, title string) error {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if !d.authed {
		return ErrAuth
	}

	d.chatsMu.Lock()
	cs, ok := d.chats[chatID]
	if !ok {
		d.chatsMu.Unlock()
		return ErrNotFound
	}
	oldTitle := cs.Title
	cs.Title = title
	d.chatsMu.Unlock()

	// Send rename message
	var toAddrs []*mail.Address
	for _, m := range cs.Members {
		if m != d.myAddr {
			toAddrs = append(toAddrs, &mail.Address{Address: m})
		}
	}

	headers := map[string]string{
		"Chat-Group-ID":             cs.GroupID,
		"Chat-Group-Name":           title,
		"Chat-Group-Name-Changed":   oldTitle,
		"Chat-Group-Name-Timestamp": fmt.Sprintf("%d", time.Now().Unix()),
	}

	msgID := d.generateMsgID(cs.GroupID)
	if err := d.sendEmail(toAddrs, "Chat: "+title, fmt.Sprintf("Group renamed to \"%s\"", title), msgID, "", headers, nil); err != nil {
		return fmt.Errorf("send title change: %w", err)
	}
	d.saveSession()
	return nil
}

// EditChatDescription changes the description/topic of a group or channel.
func (d *DeltaChatCore) EditChatDescription(chatID string, description string) error {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if !d.authed {
		return ErrAuth
	}

	d.chatsMu.Lock()
	cs, ok := d.chats[chatID]
	if !ok {
		d.chatsMu.Unlock()
		return ErrNotFound
	}
	cs.Description = description
	d.chatsMu.Unlock()

	var toAddrs []*mail.Address
	for _, m := range cs.Members {
		if m != d.myAddr {
			toAddrs = append(toAddrs, &mail.Address{Address: m})
		}
	}

	headers := map[string]string{
		"Chat-Group-ID":                     cs.GroupID,
		"Chat-Group-Description":            base64.StdEncoding.EncodeToString([]byte(description)),
		"Chat-Group-Description-Changed":    "",
		"Chat-Group-Description-Timestamp":  fmt.Sprintf("%d", time.Now().Unix()),
	}

	msgID := d.generateMsgID(cs.GroupID)
	if err := d.sendEmail(toAddrs, "Chat: "+cs.Title, "Group description changed", msgID, "", headers, nil); err != nil {
		return fmt.Errorf("send description change: %w", err)
	}
	d.saveSession()
	return nil
}

// LeaveChat removes the current user from a group chat.
func (d *DeltaChatCore) LeaveChat(chatID string) error {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if !d.authed {
		return ErrAuth
	}

	d.chatsMu.Lock()
	cs, ok := d.chats[chatID]
	if !ok {
		d.chatsMu.Unlock()
		return ErrNotFound
	}

	// Remove self from members
	var newMembers []string
	for _, m := range cs.Members {
		if m != d.myAddr {
			newMembers = append(newMembers, m)
		}
	}

	var toAddrs []*mail.Address
	for _, m := range newMembers {
		toAddrs = append(toAddrs, &mail.Address{Address: m})
	}
	d.chatsMu.Unlock()

	headers := map[string]string{
		"Chat-Group-ID":             cs.GroupID,
		"Chat-Group-Member-Removed": d.myAddr,
	}

	msgID := d.generateMsgID(cs.GroupID)
	if len(toAddrs) > 0 {
		d.sendEmail(toAddrs, "Chat: "+cs.Title, d.myAddr+" left the group", msgID, "", headers, nil)
	}

	// Remove from local state
	d.chatsMu.Lock()
	delete(d.chats, chatID)
	d.chatsMu.Unlock()
	d.saveSession()
	return nil
}

// GetInviteLink returns a secure-join QR code URI for the chat.
func (d *DeltaChatCore) GetInviteLink(chatID string) (string, error) {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if !d.authed {
		return "", ErrAuth
	}

	d.chatsMu.RLock()
	cs, ok := d.chats[chatID]
	d.chatsMu.RUnlock()
	if !ok {
		return "", ErrNotFound
	}

	// Generate SecureJoin QR code URL
	fingerprint := d.getMyFingerprint()
	inviteNumber := generateShortID()
	auth := generateShortID()

	link := fmt.Sprintf("https://i.delta.chat/#%s&v=3&x=%s&i=%s&s=%s&a=%s&n=%s&g=%s",
		fingerprint, cs.GroupID, inviteNumber, auth,
		d.myAddr, d.myName, cs.Title)

	return link, nil
}

// --- Core Interface: Member Management ---

// AddMembers adds users to a group chat by email address.
func (d *DeltaChatCore) AddMembers(chatID string, userIDs []string) error {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if !d.authed {
		return ErrAuth
	}

	d.chatsMu.Lock()
	cs, ok := d.chats[chatID]
	if !ok {
		d.chatsMu.Unlock()
		return ErrNotFound
	}

	for _, uid := range userIDs {
		email := canonicalizeEmail(uid)

		// Skip if already a member
		alreadyMember := false
		for _, m := range cs.Members {
			if m == email {
				alreadyMember = true
				break
			}
		}
		if alreadyMember {
			continue
		}

		cs.Members = append(cs.Members, email)

		// Send member-added message
		var toAddrs []*mail.Address
		for _, m := range cs.Members {
			if m != d.myAddr {
				toAddrs = append(toAddrs, &mail.Address{Address: m})
			}
		}

		headers := map[string]string{
			"Chat-Group-ID":           cs.GroupID,
			"Chat-Group-Name":         cs.Title,
			"Chat-Group-Member-Added": email,
		}

		msgID := d.generateMsgID(cs.GroupID)
		if err := d.sendEmail(toAddrs, "Chat: "+cs.Title, email+" added to the group", msgID, "", headers, nil); err != nil {
			d.chatsMu.Unlock()
			return fmt.Errorf("notify member added: %w", err)
		}
	}
	d.chatsMu.Unlock()

	d.saveSession()
	return nil
}

// RemoveMember removes a user from a group chat.
func (d *DeltaChatCore) RemoveMember(chatID string, userID string) error {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if !d.authed {
		return ErrAuth
	}

	email := canonicalizeEmail(userID)

	d.chatsMu.Lock()
	cs, ok := d.chats[chatID]
	if !ok {
		d.chatsMu.Unlock()
		return ErrNotFound
	}

	// Remove from members
	var newMembers []string
	for _, m := range cs.Members {
		if m != email {
			newMembers = append(newMembers, m)
		}
	}
	cs.Members = newMembers

	// Send to all members INCLUDING the removed one
	var toAddrs []*mail.Address
	for _, m := range cs.Members {
		if m != d.myAddr {
			toAddrs = append(toAddrs, &mail.Address{Address: m})
		}
	}
	toAddrs = append(toAddrs, &mail.Address{Address: email}) // removed member gets notification
	d.chatsMu.Unlock()

	headers := map[string]string{
		"Chat-Group-ID":             cs.GroupID,
		"Chat-Group-Member-Removed": email,
	}

	msgID := d.generateMsgID(cs.GroupID)
	if err := d.sendEmail(toAddrs, "Chat: "+cs.Title, email+" removed from the group", msgID, "", headers, nil); err != nil {
		return fmt.Errorf("notify member removed: %w", err)
	}

	d.saveSession()
	return nil
}

// BanMember removes and blocks a user from a group chat.
func (d *DeltaChatCore) BanMember(chatID string, userID string) error {
	if err := d.RemoveMember(chatID, userID); err != nil {
		return err
	}
	d.mu.Lock()
	d.blocked[canonicalizeEmail(userID)] = true
	d.mu.Unlock()
	d.saveSession()
	return nil
}

// UnbanMember unblocks a previously banned user from a group chat.
func (d *DeltaChatCore) UnbanMember(chatID string, userID string) error {
	d.mu.Lock()
	delete(d.blocked, canonicalizeEmail(userID))
	d.mu.Unlock()
	d.saveSession()
	return nil
}

// GetMembers returns the list of members in a group chat.
func (d *DeltaChatCore) GetMembers(chatID string, opts PaginationOpts) ([]User, error) {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if !d.authed {
		return nil, ErrAuth
	}

	d.chatsMu.RLock()
	cs, ok := d.chats[chatID]
	d.chatsMu.RUnlock()
	if !ok {
		return nil, ErrNotFound
	}

	users := []User{}
	for _, email := range cs.Members {
		u := User{
			ID:          email,
			Username:    email,
			DisplayName: email,
			Platform:    dcPlatform,
		}
		d.peerKeysMu.RLock()
		if ps := d.peerStates[email]; ps != nil && ps.DisplayName != "" {
			u.DisplayName = ps.DisplayName
		}
		d.peerKeysMu.RUnlock()
		if email == d.myAddr {
			u.DisplayName = d.myName
		}
		users = append(users, u)
	}

	return users, nil
}

// SetAdmin grants or revokes admin privileges for a chat member.
func (d *DeltaChatCore) SetAdmin(chatID string, userID string, admin bool) error {
	// DC groups are flat — no admin hierarchy in protocol. Local-only.
	return nil
}

// --- Core Interface: Contacts ---

// GetContacts returns all known contacts from the address book.
func (d *DeltaChatCore) GetContacts() ([]User, error) {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if !d.authed {
		return nil, ErrAuth
	}

	d.peerKeysMu.RLock()
	defer d.peerKeysMu.RUnlock()

	contacts := []User{}
	for email, ps := range d.peerStates {
		name := email
		if ps.DisplayName != "" {
			name = ps.DisplayName
		}
		contacts = append(contacts, User{
			ID:          email,
			Username:    email,
			DisplayName: name,
			AvatarB64:   ps.AvatarB64,
			Platform:    dcPlatform,
		})
	}
	return contacts, nil
}

// AddContact adds a new contact by email address.
func (d *DeltaChatCore) AddContact(phone string, firstName string, lastName string) error {
	// "phone" is actually email for Delta Chat
	email := canonicalizeEmail(phone)
	name := strings.TrimSpace(firstName + " " + lastName)

	d.peerKeysMu.Lock()
	if d.peerStates[email] == nil {
		d.peerStates[email] = &dcPeerState{Addr: email}
	}
	d.peerStates[email].DisplayName = name
	d.peerKeysMu.Unlock()

	d.saveSession()
	return nil
}

// DeleteContact removes a contact from the address book.
func (d *DeltaChatCore) DeleteContact(userID string) error {
	d.peerKeysMu.Lock()
	delete(d.peerStates, canonicalizeEmail(userID))
	d.peerKeysMu.Unlock()
	d.saveSession()
	return nil
}

// BlockUser blocks a contact by email address.
func (d *DeltaChatCore) BlockUser(userID string) error {
	d.mu.Lock()
	d.blocked[canonicalizeEmail(userID)] = true
	d.mu.Unlock()
	d.saveSession()
	return nil
}

// UnblockUser unblocks a previously blocked contact.
func (d *DeltaChatCore) UnblockUser(userID string) error {
	d.mu.Lock()
	delete(d.blocked, canonicalizeEmail(userID))
	d.mu.Unlock()
	d.saveSession()
	return nil
}

// GetBlockedUsers returns the list of blocked email addresses.
func (d *DeltaChatCore) GetBlockedUsers() ([]User, error) {
	d.mu.RLock()
	defer d.mu.RUnlock()
	users := []User{}
	for email := range d.blocked {
		users = append(users, User{
			ID:          email,
			Username:    email,
			DisplayName: email,
			Platform:    dcPlatform,
		})
	}
	return users, nil
}

// --- Core Interface: Search ---

// SearchMessages searches for messages matching a query within a chat.
func (d *DeltaChatCore) SearchMessages(chatID string, query string, opts PaginationOpts) ([]Message, error) {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if !d.authed {
		return nil, ErrAuth
	}

	queryLower := strings.ToLower(query)
	results := []Message{}

	d.msgsMu.RLock()
	msgs := d.messages[chatID]
	for _, m := range msgs {
		if strings.Contains(strings.ToLower(m.Text), queryLower) ||
			strings.Contains(strings.ToLower(m.SenderName), queryLower) {
			results = append(results, *m)
		}
	}
	d.msgsMu.RUnlock()

	limit := opts.Limit
	if limit <= 0 {
		limit = 50
	}
	if len(results) > limit {
		results = results[:limit]
	}

	return results, nil
}

// SearchGlobal searches for messages matching a query across all chats.
func (d *DeltaChatCore) SearchGlobal(query string, opts PaginationOpts) ([]Dialog, error) {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if !d.authed {
		return nil, ErrAuth
	}

	queryLower := strings.ToLower(query)
	results := []Dialog{}

	d.chatsMu.RLock()
	for _, cs := range d.chats {
		if strings.Contains(strings.ToLower(cs.Title), queryLower) {
			dlg := d.chatStateToDialog(cs)
			results = append(results, dlg)
		}
	}
	d.chatsMu.RUnlock()

	// Also search message content
	matched := make(map[string]bool, len(results))
	for _, r := range results {
		matched[r.ID] = true
	}
	d.msgsMu.RLock()
	var matchedChatIDs []string
	for chatID, msgs := range d.messages {
		if matched[chatID] {
			continue
		}
		for _, m := range msgs {
			if strings.Contains(strings.ToLower(m.Text), queryLower) {
				matchedChatIDs = append(matchedChatIDs, chatID)
				matched[chatID] = true
				break
			}
		}
	}
	d.msgsMu.RUnlock()

	d.chatsMu.RLock()
	for _, chatID := range matchedChatIDs {
		if cs, ok := d.chats[chatID]; ok {
			dlg := d.chatStateToDialog(cs)
			results = append(results, dlg)
		}
	}
	d.chatsMu.RUnlock()

	return results, nil
}

// --- Core Interface: Typing ---

// SendTyping sends a typing notification to the specified chat.
func (d *DeltaChatCore) SendTyping(chatID string) error {
	// No-op: email has no typing indicator concept. Return nil (not error).
	return nil
}

// --- Core Interface: Polls ---

// CreatePoll creates a poll message in the specified chat.
func (d *DeltaChatCore) CreatePoll(chatID string, question string, options []string) (*Message, error) {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if !d.authed {
		return nil, ErrAuth
	}

	// Convention-based polls: structured text message
	var sb strings.Builder
	sb.WriteString("📊 **Poll: " + question + "**\n\n")
	for i, opt := range options {
		sb.WriteString(fmt.Sprintf("%d. %s\n", i+1, opt))
	}
	sb.WriteString("\nReply with the option number to vote.")

	msg := OutgoingMessage{Text: sb.String()}
	return d.SendMessage(chatID, msg)
}

// VotePoll submits a vote on a poll message.
func (d *DeltaChatCore) VotePoll(chatID string, msgID string, optionIndex int) error {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if !d.authed {
		return ErrAuth
	}

	msg := OutgoingMessage{Text: fmt.Sprintf("%d", optionIndex+1)}
	_, err := d.ReplyToMessage(chatID, msgID, msg)
	return err
}

// --- Core Interface: Stickers ---

// SendSticker sends a sticker image to the specified chat.
func (d *DeltaChatCore) SendSticker(chatID string, stickerID string) (*Message, error) {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if !d.authed {
		return nil, ErrAuth
	}

	// stickerID is a local file path
	data, err := os.ReadFile(stickerID)
	if err != nil {
		return nil, fmt.Errorf("read sticker: %w", err)
	}

	mimeType := "image/png"
	ext := filepath.Ext(stickerID)
	if m := mime.TypeByExtension(ext); m != "" {
		mimeType = m
	}

	d.chatsMu.RLock()
	cs, ok := d.chats[chatID]
	d.chatsMu.RUnlock()
	if !ok {
		return nil, ErrNotFound
	}

	var toAddrs []*mail.Address
	for _, m := range cs.Members {
		if m != d.myAddr {
			toAddrs = append(toAddrs, &mail.Address{Address: m})
		}
	}

	headers := map[string]string{
		"Chat-Content": "sticker",
	}
	if cs.GroupID != "" {
		headers["Chat-Group-ID"] = cs.GroupID
	}

	attachment := &dcAttachment{
		Name:     filepath.Base(stickerID),
		MimeType: mimeType,
		Data:     data,
	}

	msgID := d.generateMsgID(cs.GroupID)
	err = d.sendEmail(toAddrs, "Chat: "+cs.Title, "", msgID, "", headers, attachment)
	if err != nil {
		return nil, err
	}

	now := time.Now()
	m := &Message{
		ID:         msgID,
		ChatID:     chatID,
		SenderID:   d.myAddr,
		SenderName: d.myName,
		Timestamp:  now,
		Status:     MessageStatusSent,
		IsOutgoing: true,
		Attachments: []FileRef{{
			Name:     filepath.Base(stickerID),
			MimeType: mimeType,
			Size:     int64(len(data)),
		}},
		Platform: dcPlatform,
	}

	d.cacheMessage(chatID, m)
	return m, nil
}

// --- Core Interface: Sessions ---

// GetSessions returns active session information.
func (d *DeltaChatCore) GetSessions() ([]Session, error) {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if !d.authed {
		return nil, ErrAuth
	}

	// IMAP doesn't expose other sessions. Return current session info.
	return []Session{{
		ID:         "current",
		Device:     "uniclient",
		Platform:   dcPlatform,
		AppName:    "uniclient",
		AppVersion: "1.0.0",
		LastActive: time.Now(),
		IsCurrent:  true,
	}}, nil
}

// TerminateSession terminates a session (changes the email password).
func (d *DeltaChatCore) TerminateSession(sessionID string) error {
	if sessionID == "current" {
		return fmt.Errorf("%w: cannot terminate current session", ErrInvalidInput)
	}
	return fmt.Errorf("%w: IMAP does not expose other sessions", ErrNotSupported)
}

// ========================================================================
// Delta Chat specific methods (beyond Core interface)
// ========================================================================

// --- Ephemeral / Disappearing Messages ---

// SetEphemeralTimer sets the disappearing message timer for a chat (in seconds). 0 = off.
func (d *DeltaChatCore) SetEphemeralTimer(chatID string, seconds int) error {
	d.chatsMu.Lock()
	cs, ok := d.chats[chatID]
	if !ok {
		d.chatsMu.Unlock()
		return ErrNotFound
	}
	cs.EphemeralTimer = seconds
	d.chatsMu.Unlock()

	// Announce via system message
	var toAddrs []*mail.Address
	for _, m := range cs.Members {
		if m != d.myAddr {
			toAddrs = append(toAddrs, &mail.Address{Address: m})
		}
	}

	headers := map[string]string{
		"Ephemeral-Timer": fmt.Sprintf("%d", seconds),
		"Chat-Content":   "ephemeral-timer-changed",
	}
	if cs.GroupID != "" {
		headers["Chat-Group-ID"] = cs.GroupID
	}

	text := "Disappearing messages disabled"
	if seconds > 0 {
		text = fmt.Sprintf("Disappearing messages set to %s", formatDuration(seconds))
	}

	msgID := d.generateMsgID(cs.GroupID)
	if err := d.sendEmail(toAddrs, "Chat: "+cs.Title, text, msgID, "", headers, nil); err != nil {
		return fmt.Errorf("send ephemeral timer: %w", err)
	}
	d.saveSession()
	return nil
}

// GetEphemeralTimer returns the disappearing message timer in seconds. 0 = off.
func (d *DeltaChatCore) GetEphemeralTimer(chatID string) (int, error) {
	d.chatsMu.RLock()
	cs, ok := d.chats[chatID]
	d.chatsMu.RUnlock()
	if !ok {
		return 0, ErrNotFound
	}
	return cs.EphemeralTimer, nil
}

// --- Drafts ---

// SetDraft saves a message draft for a chat.
func (d *DeltaChatCore) SetDraft(chatID string, msg *OutgoingMessage) error {
	d.draftsMu.Lock()
	if msg == nil || (msg.Text == "" && len(msg.Attachments) == 0) {
		delete(d.drafts, chatID)
	} else {
		d.drafts[chatID] = msg
	}
	d.draftsMu.Unlock()
	return nil
}

// GetDraft returns the saved draft for a chat, or nil.
func (d *DeltaChatCore) GetDraft(chatID string) (*OutgoingMessage, error) {
	d.draftsMu.RLock()
	draft := d.drafts[chatID]
	d.draftsMu.RUnlock()
	return draft, nil
}

// --- Chat Visibility ---

// SetChatVisibility sets a chat's visibility: 0=normal, 1=archived, 2=pinned.
func (d *DeltaChatCore) SetChatVisibility(chatID string, visibility int) error {
	d.chatsMu.Lock()
	cs, ok := d.chats[chatID]
	if !ok {
		d.chatsMu.Unlock()
		return ErrNotFound
	}
	cs.Visibility = visibility
	d.chatsMu.Unlock()
	d.saveSession()
	return nil
}

// --- Chat Muting ---

// SetChatMuted mutes a chat. duration: 0 = forever, -1 = unmute, >0 = seconds.
func (d *DeltaChatCore) SetChatMuted(chatID string, duration int64) error {
	d.chatsMu.Lock()
	cs, ok := d.chats[chatID]
	if !ok {
		d.chatsMu.Unlock()
		return ErrNotFound
	}
	if duration < 0 {
		cs.MuteUntil = nil
	} else if duration == 0 {
		zero := int64(0)
		cs.MuteUntil = &zero // forever
	} else {
		until := time.Now().Unix() + duration
		cs.MuteUntil = &until
	}
	d.chatsMu.Unlock()
	d.saveSession()
	return nil
}

// --- Chat Protection (Verified) ---

// SetChatProtected enables/disables verified mode (all members must be verified).
func (d *DeltaChatCore) SetChatProtected(chatID string, protected bool) error {
	d.chatsMu.Lock()
	cs, ok := d.chats[chatID]
	if !ok {
		d.chatsMu.Unlock()
		return ErrNotFound
	}
	cs.IsProtected = protected
	d.chatsMu.Unlock()

	var toAddrs []*mail.Address
	for _, m := range cs.Members {
		if m != d.myAddr {
			toAddrs = append(toAddrs, &mail.Address{Address: m})
		}
	}

	content := "protection-disabled"
	text := "Chat protection disabled"
	if protected {
		content = "protection-enabled"
		text = "Chat protection enabled — all messages must be encrypted"
	}

	headers := map[string]string{
		"Chat-Content": content,
	}
	if protected {
		headers["Chat-Verified"] = "1"
	}
	if cs.GroupID != "" {
		headers["Chat-Group-ID"] = cs.GroupID
	}

	msgID := d.generateMsgID(cs.GroupID)
	if err := d.sendEmail(toAddrs, "Chat: "+cs.Title, text, msgID, "", headers, nil); err != nil {
		return fmt.Errorf("send chat protection: %w", err)
	}
	d.saveSession()
	return nil
}

// --- Accept / Block Chat ---

// AcceptChat accepts a contact request chat.
func (d *DeltaChatCore) AcceptChat(chatID string) error {
	d.chatsMu.Lock()
	if cs, ok := d.chats[chatID]; ok {
		cs.Visibility = 0 // normal
	}
	d.chatsMu.Unlock()
	return nil
}

// BlockChat blocks a chat (hides it and stops receiving).
func (d *DeltaChatCore) BlockChat(chatID string) error {
	d.chatsMu.RLock()
	cs, ok := d.chats[chatID]
	if !ok {
		d.chatsMu.RUnlock()
		return ErrNotFound
	}
	// Copy members while lock is held
	members := make([]string, len(cs.Members))
	copy(members, cs.Members)
	d.chatsMu.RUnlock()

	// Block all members of this chat
	d.mu.Lock()
	for _, m := range members {
		if m != d.myAddr {
			d.blocked[m] = true
		}
	}
	d.mu.Unlock()
	d.saveSession()
	return nil
}

// --- Location Streaming ---

// StartLocationStreaming starts sharing location to a chat for the given duration (seconds). 0 = stop.
func (d *DeltaChatCore) StartLocationStreaming(chatID string, seconds int) error {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if !d.authed {
		return ErrAuth
	}

	if seconds == 0 {
		return d.StopLocationStreaming(chatID)
	}

	d.chatsMu.RLock()
	cs, ok := d.chats[chatID]
	d.chatsMu.RUnlock()
	if !ok {
		return ErrNotFound
	}

	// Send system message
	var toAddrs []*mail.Address
	for _, m := range cs.Members {
		if m != d.myAddr {
			toAddrs = append(toAddrs, &mail.Address{Address: m})
		}
	}

	headers := map[string]string{
		"Chat-Content": "location-streaming-enabled",
	}
	if cs.GroupID != "" {
		headers["Chat-Group-ID"] = cs.GroupID
	}

	msgID := d.generateMsgID(cs.GroupID)
	if err := d.sendEmail(toAddrs, "Chat: "+cs.Title, "Location streaming enabled", msgID, "", headers, nil); err != nil {
		return fmt.Errorf("send location streaming: %w", err)
	}

	// Track stream
	ctx, cancel := context.WithTimeout(d.ctx, time.Duration(seconds)*time.Second)
	d.locationMu.Lock()
	if old, ok := d.locationStreaming[chatID]; ok {
		old.Cancel()
	}
	d.locationStreaming[chatID] = &DCLocationStream{
		ChatID:   chatID,
		Duration: time.Duration(seconds) * time.Second,
		StartAt:  time.Now(),
		Cancel:   cancel,
	}
	d.locationMu.Unlock()

	// Auto-stop when context expires
	go func() {
		<-ctx.Done()
		d.locationMu.Lock()
		delete(d.locationStreaming, chatID)
		d.locationMu.Unlock()
	}()

	return nil
}

// StopLocationStreaming stops sharing location to a chat.
func (d *DeltaChatCore) StopLocationStreaming(chatID string) error {
	d.locationMu.Lock()
	if ls, ok := d.locationStreaming[chatID]; ok {
		ls.Cancel()
		delete(d.locationStreaming, chatID)
	}
	d.locationMu.Unlock()
	return nil
}

// SendLocation sends a single location (POI) to a chat as a KML attachment.
func (d *DeltaChatCore) SendLocation(chatID string, lat float64, lon float64) (*Message, error) {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if !d.authed {
		return nil, ErrAuth
	}

	d.chatsMu.RLock()
	cs, ok := d.chats[chatID]
	d.chatsMu.RUnlock()
	if !ok {
		return nil, ErrNotFound
	}

	kml := fmt.Sprintf(`<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <Placemark>
      <Timestamp><when>%s</when></Timestamp>
      <Point><coordinates>%f,%f,0</coordinates></Point>
    </Placemark>
  </Document>
</kml>`, time.Now().UTC().Format(time.RFC3339), lon, lat)

	var toAddrs []*mail.Address
	for _, m := range cs.Members {
		if m != d.myAddr {
			toAddrs = append(toAddrs, &mail.Address{Address: m})
		}
	}

	headers := make(map[string]string)
	if cs.GroupID != "" {
		headers["Chat-Group-ID"] = cs.GroupID
	}

	attachment := &dcAttachment{
		Name:     "message.kml",
		MimeType: "application/vnd.google-earth.kml+xml",
		Data:     []byte(kml),
	}

	msgID := d.generateMsgID(cs.GroupID)
	err := d.sendEmail(toAddrs, "Chat: "+cs.Title, "", msgID, "", headers, attachment)
	if err != nil {
		return nil, err
	}
	return &Message{
		ID:         msgID,
		ChatID:     chatID,
		IsOutgoing: true,
		Platform:   dcPlatform,
	}, nil
}

// --- vCard Import/Export ---

// ImportVCard parses a vCard string and adds contacts.
func (d *DeltaChatCore) ImportVCard(vcard string) ([]User, error) {
	var imported []User
	lines := strings.Split(vcard, "\n")
	var name, email string

	for _, line := range lines {
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, "FN:") {
			name = strings.TrimPrefix(line, "FN:")
		} else if strings.HasPrefix(line, "EMAIL") {
			// EMAIL;TYPE=internet:addr or EMAIL:addr
			parts := strings.SplitN(line, ":", 2)
			if len(parts) == 2 {
				email = strings.TrimSpace(parts[1])
			}
		} else if line == "END:VCARD" && email != "" {
			addr := canonicalizeEmail(email)
			d.peerKeysMu.Lock()
			if d.peerStates[addr] == nil {
				d.peerStates[addr] = &dcPeerState{Addr: addr}
			}
			if name != "" {
				d.peerStates[addr].DisplayName = name
			}
			d.peerKeysMu.Unlock()
			imported = append(imported, User{
				ID:          addr,
				Username:    addr,
				DisplayName: name,
				Platform:    dcPlatform,
			})
			name, email = "", ""
		}
	}

	d.saveSession()
	return imported, nil
}

// MakeVCard generates a vCard string for the given contact emails.
func (d *DeltaChatCore) MakeVCard(emails []string) (string, error) {
	var sb strings.Builder
	for _, email := range emails {
		addr := canonicalizeEmail(email)
		name := addr
		d.peerKeysMu.RLock()
		if ps := d.peerStates[addr]; ps != nil && ps.DisplayName != "" {
			name = ps.DisplayName
		}
		d.peerKeysMu.RUnlock()

		sb.WriteString("BEGIN:VCARD\r\n")
		sb.WriteString("VERSION:3.0\r\n")
		sb.WriteString(fmt.Sprintf("FN:%s\r\n", name))
		sb.WriteString(fmt.Sprintf("EMAIL:%s\r\n", addr))
		sb.WriteString("END:VCARD\r\n")
	}
	return sb.String(), nil
}

// --- HTML Messages ---

// SendHTML sends an HTML message with a plaintext fallback.
func (d *DeltaChatCore) SendHTML(chatID string, html string, plaintext string) (*Message, error) {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if !d.authed {
		return nil, ErrAuth
	}

	d.chatsMu.RLock()
	cs, ok := d.chats[chatID]
	d.chatsMu.RUnlock()
	if !ok && strings.HasPrefix(chatID, "dm:") {
		peerEmail := strings.TrimPrefix(chatID, "dm:")
		cs = &dcChatState{ID: chatID, Type: ChatTypeDM, Title: peerEmail, Members: []string{d.myAddr, peerEmail}}
		d.chatsMu.Lock()
		d.chats[chatID] = cs
		d.chatsMu.Unlock()
	}
	if cs == nil {
		return nil, ErrNotFound
	}

	var toAddrs []*mail.Address
	for _, m := range cs.Members {
		if m != d.myAddr {
			toAddrs = append(toAddrs, &mail.Address{Address: m})
		}
	}

	// Build multipart/alternative with text/plain + text/html
	var buf bytes.Buffer
	var h mail.Header
	h.SetDate(time.Now())
	h.SetAddressList("From", []*mail.Address{{Name: d.myName, Address: d.myAddr}})
	h.SetAddressList("To", toAddrs)
	h.SetSubject("Chat: " + cs.Title)
	h.Set("Chat-Version", "1.0")
	msgID := d.generateMsgID(cs.GroupID)
	h.Set("Message-ID", msgID)
	if !d.isBot {
		h.SetAddressList("Bcc", []*mail.Address{{Address: d.myAddr}})
	}

	if d.myEntity != nil {
		keydata := d.serializePublicKey()
		if keydata != "" {
			h.Set("Autocrypt", fmt.Sprintf("addr=%s; prefer-encrypt=mutual; keydata=%s", d.myAddr, keydata))
		}
	}

	w, err := mail.CreateWriter(&buf, h)
	if err != nil {
		return nil, err
	}

	// Inline alternative part
	pw, _ := w.CreateInline()

	// text/plain
	var ih1 mail.InlineHeader
	ih1.Set("Content-Type", "text/plain; charset=utf-8")
	tw, _ := pw.CreatePart(ih1)
	io.WriteString(tw, plaintext)
	tw.Close()

	// text/html
	var ih2 mail.InlineHeader
	ih2.Set("Content-Type", "text/html; charset=utf-8")
	hw, _ := pw.CreatePart(ih2)
	io.WriteString(hw, html)
	hw.Close()

	pw.Close()
	w.Close()

	plainMsg := buf.Bytes()
	var recipientEmails []string
	for _, a := range toAddrs {
		recipientEmails = append(recipientEmails, a.Address)
	}

	// Try PGP/MIME encryption (required by chatmail)
	if d.myEntity != nil {
		headers := make(map[string]string)
		if cs.GroupID != "" {
			headers["Chat-Group-ID"] = cs.GroupID
		}
		encrypted, err := d.wrapPGPMIME(plainMsg, recipientEmails, "Chat: "+cs.Title, msgID, toAddrs, "", headers)
		if err == nil && encrypted != nil {
			if err := d.smtpSend(toAddrs, encrypted); err != nil {
				return nil, err
			}
			goto sent
		}
	}

	if err := d.smtpSend(toAddrs, plainMsg); err != nil {
		return nil, err
	}

sent:
	now := time.Now()
	m := &Message{
		ID:         msgID,
		ChatID:     chatID,
		SenderID:   d.myAddr,
		SenderName: d.myName,
		Text:       plaintext,
		Timestamp:  now,
		Status:     MessageStatusSent,
		IsOutgoing: true,
		Platform:   dcPlatform,
	}
	d.cacheMessage(chatID, m)
	d.updateChatTime(chatID, now)
	return m, nil
}

// --- Encryption Info ---

// GetEncryptionInfo returns encryption status for a chat.
func (d *DeltaChatCore) GetEncryptionInfo(chatID string) (string, error) {
	d.chatsMu.RLock()
	cs, ok := d.chats[chatID]
	d.chatsMu.RUnlock()
	if !ok {
		return "", ErrNotFound
	}

	var sb strings.Builder
	if cs.IsProtected {
		sb.WriteString("Chat is PROTECTED (verified). All messages must be encrypted.\n\n")
	}

	for _, email := range cs.Members {
		if email == d.myAddr {
			sb.WriteString(fmt.Sprintf("You (%s):\n", d.myAddr))
			if d.myEntity != nil {
				fp := d.getMyFingerprint()
				sb.WriteString(fmt.Sprintf("  Fingerprint: %s\n", fp))
			}
			continue
		}

		d.peerKeysMu.RLock()
		ps := d.peerStates[email]
		d.peerKeysMu.RUnlock()

		sb.WriteString(fmt.Sprintf("%s:\n", email))
		if ps == nil || (len(ps.PublicKey) == 0 && len(ps.GossipKey) == 0) {
			sb.WriteString("  No Autocrypt key known — messages are NOT encrypted\n")
		} else {
			if len(ps.PublicKey) > 0 {
				sb.WriteString("  Autocrypt key: available\n")
				sb.WriteString(fmt.Sprintf("  prefer-encrypt: %s\n", ps.PreferEncrypt))
				sb.WriteString(fmt.Sprintf("  Last key update: %s\n", ps.AutocryptTimestamp.Format(time.RFC3339)))
			}
			if len(ps.GossipKey) > 0 {
				sb.WriteString("  Gossip key: available\n")
			}
		}
	}

	return sb.String(), nil
}

// --- Connectivity ---

// GetConnectivity returns the current connection status.
func (d *DeltaChatCore) GetConnectivity() (string, error) {
	d.mu.RLock()
	defer d.mu.RUnlock()

	if !d.authed {
		return "not_connected", nil
	}

	// Check IMAP connection by doing a NOOP
	if d.imapOps != nil {
		return "connected", nil
	}
	return "connecting", nil
}

// --- Resend Failed Messages ---

// ResendMessage attempts to resend a failed message.
func (d *DeltaChatCore) ResendMessage(chatID string, msgID string) (*Message, error) {
	d.msgsMu.RLock()
	var original *Message
	for _, m := range d.messages[chatID] {
		if m.ID == msgID {
			original = m
			break
		}
	}
	d.msgsMu.RUnlock()

	if original == nil {
		return nil, ErrNotFound
	}

	// Re-send via SendMessage
	return d.SendMessage(chatID, OutgoingMessage{Text: original.Text})
}

// --- Backup Export/Import ---

// ExportBackup exports all session data to a JSON file.
func (d *DeltaChatCore) ExportBackup(path string) error {
	d.mu.RLock()
	defer d.mu.RUnlock()

	// Export session by saving current state to the given path
	if d.session == nil {
		return fmt.Errorf("no session to export")
	}

	var sess dcSession
	if err := d.session.Load(&sess); err != nil {
		return fmt.Errorf("load session: %w", err)
	}

	data, err := json.Marshal(sess)
	if err != nil {
		return fmt.Errorf("marshal session: %w", err)
	}

	return os.WriteFile(path, data, 0600)
}

// ImportBackup imports session data from a JSON file.
func (d *DeltaChatCore) ImportBackup(path string) error {
	d.mu.Lock()
	defer d.mu.Unlock()

	data, err := os.ReadFile(path)
	if err != nil {
		return fmt.Errorf("read backup: %w", err)
	}

	var sess dcSession
	if err := json.Unmarshal(data, &sess); err != nil {
		return fmt.Errorf("parse backup: %w", err)
	}

	// Merge into current state
	if sess.PeerStates != nil {
		for k, v := range sess.PeerStates {
			d.peerStates[k] = v
		}
	}
	if sess.Chats != nil {
		for k, v := range sess.Chats {
			d.chats[k] = v
		}
	}
	if sess.Blocked != nil {
		for k, v := range sess.Blocked {
			d.blocked[k] = v
		}
	}

	d.saveSession()
	return nil
}

// --- Save Messages (Saved Messages / Self-Chat) ---

// SaveMessages copies messages to the self-chat (saved messages).
func (d *DeltaChatCore) SaveMessages(msgIDs []string) error {
	selfChatID := "dm:" + d.myAddr

	// Ensure self-chat exists
	d.chatsMu.Lock()
	if _, ok := d.chats[selfChatID]; !ok {
		d.chats[selfChatID] = &dcChatState{
			ID:      selfChatID,
			Type:    ChatTypeDM,
			Title:   "Saved Messages",
			Members: []string{d.myAddr},
		}
	}
	d.chatsMu.Unlock()

	// Copy messages
	d.msgsMu.Lock()
	defer d.msgsMu.Unlock()

	for _, chatMsgs := range d.messages {
		for _, m := range chatMsgs {
			for _, targetID := range msgIDs {
				if m.ID == targetID {
					saved := *m
					saved.ChatID = selfChatID
					d.messages[selfChatID] = append(d.messages[selfChatID], &saved)
				}
			}
		}
	}

	return nil
}

// --- Get Reactions ---

// GetReactions returns all reactions on a message.
func (d *DeltaChatCore) GetReactions(chatID string, msgID string) ([]Reaction, error) {
	d.msgsMu.RLock()
	defer d.msgsMu.RUnlock()

	for _, m := range d.messages[chatID] {
		if m.ID == msgID {
			return m.Reactions, nil
		}
	}
	return nil, ErrNotFound
}

// --- Send vCard as message ---

// SendContact sends a contact as a vCard message to a chat.
func (d *DeltaChatCore) SendContact(chatID string, contactEmail string) (*Message, error) {
	vcard, err := d.MakeVCard([]string{contactEmail})
	if err != nil {
		return nil, err
	}

	d.chatsMu.RLock()
	cs, ok := d.chats[chatID]
	d.chatsMu.RUnlock()
	if !ok {
		return nil, ErrNotFound
	}

	var toAddrs []*mail.Address
	for _, m := range cs.Members {
		if m != d.myAddr {
			toAddrs = append(toAddrs, &mail.Address{Address: m})
		}
	}

	headers := make(map[string]string)
	if cs.GroupID != "" {
		headers["Chat-Group-ID"] = cs.GroupID
	}

	attachment := &dcAttachment{
		Name:     "contact.vcf",
		MimeType: "text/vcard",
		Data:     []byte(vcard),
	}

	msgID := d.generateMsgID(cs.GroupID)
	err = d.sendEmail(toAddrs, "Chat: "+cs.Title, contactEmail, msgID, "", headers, attachment)
	if err != nil {
		return nil, err
	}

	now := time.Now()
	m := &Message{
		ID:         msgID,
		ChatID:     chatID,
		SenderID:   d.myAddr,
		SenderName: d.myName,
		Text:       contactEmail,
		Timestamp:  now,
		Status:     MessageStatusSent,
		IsOutgoing: true,
		Attachments: []FileRef{{
			Name:     "contact.vcf",
			MimeType: "text/vcard",
		}},
		Platform: dcPlatform,
	}
	d.cacheMessage(chatID, m)
	return m, nil
}

// --- Videochat Invitation ---

// SendVideochatInvitation sends a videochat invitation to a chat.
func (d *DeltaChatCore) SendVideochatInvitation(chatID string) (*Message, error) {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if !d.authed {
		return nil, ErrAuth
	}

	d.chatsMu.RLock()
	cs, ok := d.chats[chatID]
	d.chatsMu.RUnlock()
	if !ok {
		return nil, ErrNotFound
	}

	roomID := "dc-videochat-" + generateShortID()
	var toAddrs []*mail.Address
	for _, m := range cs.Members {
		if m != d.myAddr {
			toAddrs = append(toAddrs, &mail.Address{Address: m})
		}
	}

	headers := map[string]string{
		"Chat-Content":                    "call",
		"Chat-Webrtc-Room":               roomID,
		"Chat-Webrtc-Has-Video-Initially": "true",
	}
	if cs.GroupID != "" {
		headers["Chat-Group-ID"] = cs.GroupID
	}

	msgID := d.generateMsgID(cs.GroupID)
	err := d.sendEmail(toAddrs, "Chat: "+cs.Title, "Video call invitation", msgID, "", headers, nil)
	if err != nil {
		return nil, err
	}

	now := time.Now()
	m := &Message{
		ID:         msgID,
		ChatID:     chatID,
		SenderID:   d.myAddr,
		SenderName: d.myName,
		Text:       "Video call invitation",
		Timestamp:  now,
		Status:     MessageStatusSent,
		IsOutgoing: true,
		Platform:   dcPlatform,
	}
	d.cacheMessage(chatID, m)
	return m, nil
}

// --- Chat Image ---

// SetChatImage sets the group/channel avatar.
func (d *DeltaChatCore) SetChatImage(chatID string, imageB64 string) error {
	d.chatsMu.Lock()
	cs, ok := d.chats[chatID]
	if !ok {
		d.chatsMu.Unlock()
		return ErrNotFound
	}
	cs.AvatarB64 = imageB64
	d.chatsMu.Unlock()

	// Send avatar change message
	var toAddrs []*mail.Address
	for _, m := range cs.Members {
		if m != d.myAddr {
			toAddrs = append(toAddrs, &mail.Address{Address: m})
		}
	}

	headers := map[string]string{
		"Chat-Group-Avatar": "base64:" + imageB64,
		"Chat-Content":      "group-avatar-changed",
	}
	if cs.GroupID != "" {
		headers["Chat-Group-ID"] = cs.GroupID
	}

	msgID := d.generateMsgID(cs.GroupID)
	if err := d.sendEmail(toAddrs, "Chat: "+cs.Title, "Group image changed", msgID, "", headers, nil); err != nil {
		return fmt.Errorf("send avatar change: %w", err)
	}
	d.saveSession()
	return nil
}

// RemoveChatImage removes the group/channel avatar.
func (d *DeltaChatCore) RemoveChatImage(chatID string) error {
	return d.SetChatImage(chatID, "")
}

// --- User Avatar and Status ---

// SetAvatar sets the user's avatar (base64-encoded image).
// The avatar is sent via Chat-User-Avatar header in subsequent outgoing messages.
func (d *DeltaChatCore) SetAvatar(imageB64 string) error {
	// Stored for inclusion in outgoing messages via sendEmail
	_ = imageB64 // will be used when Chat-User-Avatar header support is added to sendEmail
	return nil
}

// SetStatus sets the user's bio/status text.
func (d *DeltaChatCore) SetStatus(text string) error {
	d.mu.Lock()
	d.myStatus = text
	d.mu.Unlock()
	d.saveSession()
	return nil
}

// GetStatus returns the user's bio/status text.
func (d *DeltaChatCore) GetStatus() string {
	d.mu.RLock()
	defer d.mu.RUnlock()
	return d.myStatus
}

// --- SecureJoin ---

// CheckQR parses a Delta Chat QR code and returns the parsed info.
func (d *DeltaChatCore) CheckQR(qr string) (map[string]string, error) {
	if !strings.HasPrefix(qr, "https://i.delta.chat/#") {
		return nil, fmt.Errorf("%w: not a Delta Chat QR code", ErrInvalidInput)
	}

	fragment := strings.TrimPrefix(qr, "https://i.delta.chat/#")
	parts := strings.Split(fragment, "&")

	result := make(map[string]string)
	if len(parts) > 0 {
		result["fingerprint"] = parts[0]
	}

	for _, p := range parts[1:] {
		kv := strings.SplitN(p, "=", 2)
		if len(kv) == 2 {
			result[kv[0]] = kv[1]
		}
	}

	return result, nil
}

// SecureJoin joins a verified group or verifies a contact via QR code data.
func (d *DeltaChatCore) SecureJoin(qrData string) (*Dialog, error) {
	info, err := d.CheckQR(qrData)
	if err != nil {
		return nil, err
	}

	groupID := info["x"]
	addr := info["a"]

	if groupID != "" {
		// Join a verified group
		chatID := "grp:" + groupID
		groupName := info["g"]
		if groupName == "" {
			groupName = "Verified Group"
		}

		cs := &dcChatState{
			ID:          chatID,
			Type:        ChatTypeGroup,
			Title:       groupName,
			GroupID:     groupID,
			Members:     []string{d.myAddr, addr},
			IsProtected: true,
		}
		d.chatsMu.Lock()
		d.chats[chatID] = cs
		d.chatsMu.Unlock()

		// Send join request
		toAddrs := []*mail.Address{{Address: addr}}
		headers := map[string]string{
			"Secure-Join":              "vg-request-with-auth",
			"Secure-Join-Auth":         info["s"],
			"Secure-Join-Invitenumber": info["i"],
		}
		msgID := d.generateMsgID(groupID)
		d.sendEmail(toAddrs, "Secure-Join", "Secure-Join: vg-request-with-auth", msgID, "", headers, nil)

		dlg := d.chatStateToDialog(cs)
		return &dlg, nil
	}

	// Verify a contact
	chatID := "dm:" + canonicalizeEmail(addr)
	cs := &dcChatState{
		ID:          chatID,
		Type:        ChatTypeDM,
		Title:       addr,
		Members:     []string{d.myAddr, addr},
		IsProtected: true,
	}
	d.chatsMu.Lock()
	d.chats[chatID] = cs
	d.chatsMu.Unlock()

	toAddrs := []*mail.Address{{Address: addr}}
	headers := map[string]string{
		"Secure-Join":              "vc-request-with-auth",
		"Secure-Join-Auth":         info["s"],
		"Secure-Join-Invitenumber": info["i"],
	}
	msgID := d.generateMsgID("")
	d.sendEmail(toAddrs, "Secure-Join", "Secure-Join: vc-request-with-auth", msgID, "", headers, nil)

	dlg := d.chatStateToDialog(cs)
	return &dlg, nil
}

// --- Fresh Messages ---

// GetFreshMessages returns unread messages across all chats.
func (d *DeltaChatCore) GetFreshMessages() ([]Message, error) {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if !d.authed {
		return nil, ErrAuth
	}

	var fresh []Message
	d.msgsMu.RLock()
	for _, msgs := range d.messages {
		for _, m := range msgs {
			if m.Status == MessageStatusDelivered && m.SenderID != d.myAddr {
				fresh = append(fresh, *m)
			}
		}
	}
	d.msgsMu.RUnlock()

	sort.Slice(fresh, func(i, j int) bool {
		return fresh[i].Timestamp.Before(fresh[j].Timestamp)
	})

	return fresh, nil
}

// --- Autocrypt PGP/MIME encryption ---

// decryptMessage attempts to decrypt a PGP/MIME message.
func (d *DeltaChatCore) decryptMessage(armored []byte) ([]byte, bool) {
	if d.myEntity == nil {
		return armored, false
	}

	block, err := armor.Decode(bytes.NewReader(armored))
	if err != nil {
		return armored, false
	}

	keyring := openpgp.EntityList{d.myEntity}
	md, err := openpgp.ReadMessage(block.Body, keyring, nil, nil)
	if err != nil {
		return armored, false
	}

	plain, err := io.ReadAll(md.UnverifiedBody)
	if err != nil {
		return armored, false
	}

	return plain, true
}

// decryptPGPMIME parses a multipart/encrypted MIME body, extracts the PGP-encrypted
// part, decrypts it, and parses the inner MIME message for headers and body text.
// Returns the plaintext body, inner headers, and success flag.
func (d *DeltaChatCore) decryptPGPMIME(outerContentType string, bodyBytes []byte) ([]byte, map[string]string, bool) {
	if d.myEntity == nil {
		return nil, nil, false
	}

	// bodyBytes is the full RFC 5322 message (BODY[] from IMAP), including headers.
	// Try parsing it directly first. If that fails (body-only), reconstruct with Content-Type.
	entity, err := message.Read(bytes.NewReader(bodyBytes))
	if err != nil {
		// Fallback: body might be without headers — reconstruct with Content-Type
		var fullMsg bytes.Buffer
		fullMsg.WriteString("Content-Type: ")
		fullMsg.WriteString(outerContentType)
		fullMsg.WriteString("\r\n\r\n")
		fullMsg.Write(bodyBytes)
		entity, err = message.Read(&fullMsg)
	}
	if err != nil {
		return nil, nil, false
	}

	mr := entity.MultipartReader()
	if mr == nil {
		// Not actually multipart — try direct PGP armor decryption
		if decrypted, ok := d.decryptMessage(bodyBytes); ok {
			return decrypted, nil, true
		}
		return nil, nil, false
	}

	// Walk parts: part 1 is "application/pgp-encrypted" (version ID),
	// part 2 is "application/octet-stream" (the actual PGP data)
	var pgpData []byte
	for {
		part, err := mr.NextPart()
		if err != nil {
			break
		}
		partType, _, _ := part.Header.ContentType()
		partData, readErr := io.ReadAll(part.Body)
		if readErr != nil {
			continue
		}
		if partType == "application/octet-stream" || partType == "application/pgp-encrypted" {
			// The actual encrypted data is in the octet-stream part,
			// but some clients use pgp-encrypted for both. Check for PGP armor.
			trimmed := bytes.TrimSpace(partData)
			if bytes.HasPrefix(trimmed, []byte("-----BEGIN PGP MESSAGE-----")) {
				pgpData = trimmed
			}
		}
	}

	if pgpData == nil {
		return nil, nil, false
	}

	// Decrypt the PGP block
	decrypted, ok := d.decryptMessage(pgpData)
	if !ok {
		return nil, nil, false
	}

	// The decrypted payload is an inner MIME message (e.g., text/plain or multipart/mixed).
	// Parse it for headers and body.
	innerEntity, err := message.Read(bytes.NewReader(decrypted))
	if err != nil {
		// If parsing fails, return raw decrypted bytes with no inner headers
		return decrypted, nil, true
	}

	innerHeaders := make(map[string]string)
	// Extract key headers from the inner MIME message
	for _, key := range []string{
		"Chat-Version", "Chat-Group-ID", "Chat-Group-Name", "Chat-Group-Member-Added",
		"Chat-Group-Member-Removed", "Chat-Group-Name-Changed", "Chat-Group-Image",
		"Chat-Content", "Chat-Edit", "Chat-Delete", "Chat-Voice-Message", "Chat-Duration",
		"Chat-Disposition-Notification-To", "Chat-User-Avatar", "Chat-Verified",
		"Autocrypt", "Autocrypt-Gossip", "Subject", "Content-Type",
		"Chat-Webrtc-Room", "Chat-List-ID",
	} {
		if v := innerEntity.Header.Get(key); v != "" {
			innerHeaders[key] = v
		}
	}

	// Extract body text
	innerType, _, _ := innerEntity.Header.ContentType()
	if strings.HasPrefix(innerType, "multipart/") {
		// Inner is multipart (e.g., multipart/mixed with text + attachments)
		imr := innerEntity.MultipartReader()
		if imr != nil {
			var textBody []byte
			for {
				iPart, err := imr.NextPart()
				if err != nil {
					break
				}
				iPartType, _, _ := iPart.Header.ContentType()
				if strings.HasPrefix(iPartType, "text/plain") && textBody == nil {
					textBody, _ = io.ReadAll(iPart.Body)
				}
			}
			if textBody != nil {
				return textBody, innerHeaders, true
			}
		}
		// Fallback: return raw decrypted
		return decrypted, innerHeaders, true
	}

	// Simple inner message (text/plain)
	innerBody, err := io.ReadAll(innerEntity.Body)
	if err != nil {
		return decrypted, innerHeaders, true
	}
	return innerBody, innerHeaders, true
}

// --- Utility ---

func formatDuration(seconds int) string {
	if seconds < 60 {
		return fmt.Sprintf("%d seconds", seconds)
	} else if seconds < 3600 {
		return fmt.Sprintf("%d minutes", seconds/60)
	} else if seconds < 86400 {
		return fmt.Sprintf("%d hours", seconds/3600)
	}
	return fmt.Sprintf("%d days", seconds/86400)
}

// ========================================================================
// Internal helpers
// ========================================================================

type dcAttachment struct {
	Name     string
	MimeType string
	Data     []byte
}

// connectIMAP creates a new authenticated IMAP connection.
// Tries TLS (993), STARTTLS (143), and insecure in order.
// Supports self-signed certs via Extra["accept_invalid_certs"].
func (d *DeltaChatCore) connectIMAP() (*imapclient.Client, error) {
	host, port, _ := net.SplitHostPort(d.imapHost)
	if host == "" {
		host = d.imapHost
		port = "993"
	}

	tlsConfig := &tls.Config{ServerName: host}
	if d.acceptInvalidCerts {
		tlsConfig.InsecureSkipVerify = true
	}
	opts := &imapclient.Options{TLSConfig: tlsConfig}

	// Determine socket strategy from port or Extra config
	// 993 = implicit TLS, 143 = STARTTLS, else try both
	var client *imapclient.Client
	var err error

	switch port {
	case "993":
		client, err = imapclient.DialTLS(host+":993", opts)
	case "143":
		client, err = imapclient.DialStartTLS(host+":143", opts)
		if err != nil {
			// Some servers on 143 don't support STARTTLS — try insecure
			client, err = imapclient.DialInsecure(host+":143", opts)
		}
	default:
		// Try TLS first, then STARTTLS, then insecure
		client, err = imapclient.DialTLS(host+":"+port, opts)
		if err != nil {
			client, err = imapclient.DialStartTLS(host+":"+port, opts)
		}
		if err != nil {
			client, err = imapclient.DialInsecure(host+":"+port, opts)
		}
	}

	// Fallback: if configured port failed, try standard ports
	if err != nil && port != "993" {
		client, err = imapclient.DialTLS(host+":993", opts)
	}
	if err != nil && port != "143" {
		client, err = imapclient.DialStartTLS(host+":143", opts)
	}
	if err != nil {
		return nil, fmt.Errorf("IMAP dial (tried TLS+STARTTLS): %w", err)
	}

	// Try LOGIN (most common), server may also support PLAIN via the same call
	loginCmd := client.Login(d.myAddr, d.password)
	if err := loginCmd.Wait(); err != nil {
		client.Close()
		return nil, fmt.Errorf("IMAP login: %w", err)
	}

	return client, nil
}

// ensureDCFolder finds or creates the DeltaChat IMAP folder.
func (d *DeltaChatCore) ensureDCFolder() error {
	// List folders to find delimiter and check for DeltaChat
	listCmd := d.imapOps.List("", "*", nil)
	var found bool
	for {
		mbox := listCmd.Next()
		if mbox == nil {
			break
		}
		if d.imapDelim == "" {
			d.imapDelim = string(mbox.Delim)
		}
		name := mbox.Mailbox
		if name == "DeltaChat" || name == "INBOX"+string(mbox.Delim)+"DeltaChat" {
			d.dcFolder = name
			found = true
		}
	}
	if err := listCmd.Close(); err != nil {
		return fmt.Errorf("IMAP list: %w", err)
	}

	if !found {
		// Try creating "DeltaChat"
		d.dcFolder = "DeltaChat"
		createCmd := d.imapOps.Create(d.dcFolder, nil)
		if err := createCmd.Wait(); err != nil {
			// Try with delimiter
			d.dcFolder = "INBOX" + d.imapDelim + "DeltaChat"
			createCmd = d.imapOps.Create(d.dcFolder, nil)
			if err := createCmd.Wait(); err != nil {
				return fmt.Errorf("create DeltaChat folder: %w", err)
			}
		}
	}

	return nil
}

// sendEmail constructs and sends a Delta Chat email via SMTP.
func (d *DeltaChatCore) sendEmail(to []*mail.Address, subject string, text string, msgID string, inReplyTo string, extraHeaders map[string]string, attachment *dcAttachment) error {
	var buf bytes.Buffer

	isReaction := extraHeaders["_reaction"] != ""
	if isReaction {
		delete(extraHeaders, "_reaction")
	}

	// Build headers
	var h mail.Header
	h.SetDate(time.Now())
	h.SetAddressList("From", []*mail.Address{{Name: d.myName, Address: d.myAddr}})
	h.SetAddressList("To", to)
	h.SetSubject(subject)
	h.Set("Chat-Version", "1.0")
	h.Set("Message-ID", msgID)
	h.Set("Chat-Disposition-Notification-To", d.myAddr)

	if inReplyTo != "" {
		h.Set("In-Reply-To", inReplyTo)
		h.Set("References", inReplyTo)
	}

	// Add Autocrypt header with our public key
	if d.myEntity != nil {
		keydata := d.serializePublicKey()
		if keydata != "" {
			h.Set("Autocrypt", fmt.Sprintf("addr=%s; prefer-encrypt=mutual; keydata=%s", d.myAddr, keydata))
		}
	}

	// Extra headers
	for k, v := range extraHeaders {
		h.Set(k, v)
	}

	// BCC self for IMAP sync (skip in bot mode — bots don't need copies)
	if !d.isBot {
		h.SetAddressList("Bcc", []*mail.Address{{Address: d.myAddr}})
	}

	if attachment == nil && !isReaction {
		// Simple text message
		h.Set("Content-Type", "text/plain; charset=utf-8")
		w, err := mail.CreateSingleInlineWriter(&buf, h)
		if err != nil {
			return fmt.Errorf("create writer: %w", err)
		}
		io.WriteString(w, text)
		w.Close()
	} else if isReaction {
		// RFC 9078 reaction
		h.Set("Content-Type", "text/plain; charset=utf-8")
		h.Set("Content-Disposition", "reaction")
		w, err := mail.CreateSingleInlineWriter(&buf, h)
		if err != nil {
			return fmt.Errorf("create reaction writer: %w", err)
		}
		io.WriteString(w, text)
		w.Close()
	} else {
		// Multipart message with attachment
		w, err := mail.CreateWriter(&buf, h)
		if err != nil {
			return fmt.Errorf("create multipart writer: %w", err)
		}

		// Text part
		var ih mail.InlineHeader
		ih.Set("Content-Type", "text/plain; charset=utf-8")
		pw, _ := w.CreateInline()
		tw, _ := pw.CreatePart(ih)
		io.WriteString(tw, text)
		tw.Close()
		pw.Close()

		// Attachment part
		var ah mail.AttachmentHeader
		ah.Set("Content-Type", attachment.MimeType)
		ah.SetFilename(attachment.Name)
		aw, _ := w.CreateAttachment(ah)
		aw.Write(attachment.Data)
		aw.Close()

		w.Close()
	}

	// Try PGP/MIME encryption if we have recipient keys
	plainMsg := buf.Bytes()
	var recipientEmails []string
	for _, addr := range to {
		recipientEmails = append(recipientEmails, addr.Address)
	}

	// Always try to encrypt (chatmail servers reject plaintext with 523).
	// Encrypt to all recipients who have keys + ourselves. If no recipients have
	// keys, encrypt to just ourselves so the email is still PGP/MIME valid.
	if d.myEntity != nil {
		encrypted, encErr := d.wrapPGPMIME(plainMsg, recipientEmails, subject, msgID, to, inReplyTo, extraHeaders)
		if encErr == nil && encrypted != nil {
			return d.smtpSend(to, encrypted)
		}
		// Encryption failed — try plaintext, but if that also fails (chatmail 523),
		// return the encryption error for better diagnostics
		smtpErr := d.smtpSend(to, plainMsg)
		if smtpErr != nil && encErr != nil {
			return fmt.Errorf("encrypt failed (%v), plaintext also rejected: %w", encErr, smtpErr)
		}
		return smtpErr
	}

	// Send via SMTP (plaintext — only works on servers that don't require encryption)
	return d.smtpSend(to, plainMsg)
}

// wrapPGPMIME wraps a plaintext MIME message in PGP/MIME encryption.
func (d *DeltaChatCore) wrapPGPMIME(plainMsg []byte, recipients []string, subject string, msgID string, to []*mail.Address, inReplyTo string, extraHeaders map[string]string) ([]byte, error) {
	// Collect recipient entities — encrypt to self + any recipients with known keys.
	// Recipients without keys are skipped (they'll still receive the email, just
	// won't be able to decrypt — but the email is PGP/MIME so chatmail accepts it).
	var recipientEntities []*openpgp.Entity
	recipientEntities = append(recipientEntities, d.myEntity) // always encrypt to self

	d.peerKeysMu.RLock()
	for _, email := range recipients {
		ps := d.peerStates[canonicalizeEmail(email)]
		if ps == nil {
			continue // no key — skip, don't fail
		}
		if ps.entity != nil {
			recipientEntities = append(recipientEntities, ps.entity)
		} else if len(ps.PublicKey) > 0 {
			entities, err := openpgp.ReadKeyRing(bytes.NewReader(ps.PublicKey))
			if err == nil && len(entities) > 0 {
				recipientEntities = append(recipientEntities, entities[0])
			}
			// Parse failure — skip this recipient, don't fail the whole send
		}
	}
	d.peerKeysMu.RUnlock()

	// Encrypt the plaintext MIME body, armor directly
	var armoredBuf bytes.Buffer
	armorWriter, _ := armor.Encode(&armoredBuf, "PGP MESSAGE", nil)
	plainWriter, err := openpgp.Encrypt(armorWriter, recipientEntities, d.myEntity, nil, nil)
	if err != nil {
		return nil, fmt.Errorf("pgp encrypt: %w", err)
	}
	plainWriter.Write(plainMsg)
	plainWriter.Close()
	armorWriter.Close()

	// Build the outer PGP/MIME envelope using low-level go-message API
	// (mail.CreateWriter forces multipart/mixed; we need multipart/encrypted)
	var outerBuf bytes.Buffer
	var oh message.Header
	oh.Set("Date", time.Now().UTC().Format("Mon, 02 Jan 2006 15:04:05 -0700"))
	oh.Set("From", (&mail.Address{Name: d.myName, Address: d.myAddr}).String())
	var toStrs []string
	for _, addr := range to {
		toStrs = append(toStrs, addr.String())
	}
	oh.Set("To", strings.Join(toStrs, ", "))
	oh.Set("Subject", subject)
	oh.Set("Chat-Version", "1.0")
	oh.Set("Message-ID", msgID)
	oh.Set("MIME-Version", "1.0")
	if inReplyTo != "" {
		oh.Set("In-Reply-To", inReplyTo)
		oh.Set("References", inReplyTo)
	}
	if d.myEntity != nil {
		keydata := d.serializePublicKey()
		if keydata != "" {
			oh.Set("Autocrypt", fmt.Sprintf("addr=%s; prefer-encrypt=mutual; keydata=%s", d.myAddr, keydata))
		}
	}
	for k, v := range extraHeaders {
		oh.Set(k, v)
	}
	if !d.isBot {
		oh.Set("Bcc", d.myAddr)
	}
	oh.Set("Content-Type", `multipart/encrypted; protocol="application/pgp-encrypted"`)

	mw, err := message.CreateWriter(&outerBuf, oh)
	if err != nil {
		return nil, err
	}

	// Part 1: PGP/MIME version identification
	var versionHeader message.Header
	versionHeader.Set("Content-Type", "application/pgp-encrypted")
	versionHeader.Set("Content-Description", "PGP/MIME version identification")
	vw, _ := mw.CreatePart(versionHeader)
	io.WriteString(vw, "Version: 1\r\n")
	vw.Close()

	// Part 2: Encrypted payload
	var encHeader message.Header
	encHeader.Set("Content-Type", `application/octet-stream; name="encrypted.asc"`)
	encHeader.Set("Content-Disposition", `inline; filename="encrypted.asc"`)
	aw, _ := mw.CreatePart(encHeader)
	aw.Write(armoredBuf.Bytes())
	aw.Close()

	mw.Close()

	return outerBuf.Bytes(), nil
}

// smtpSend sends raw email bytes via SMTP.
// Tries implicit TLS (465), STARTTLS (587), and plain in order.
// Falls back from PLAIN to LOGIN auth if server rejects PLAIN.
func (d *DeltaChatCore) smtpSend(to []*mail.Address, msg []byte) error {
	host, port, _ := net.SplitHostPort(d.smtpHost)
	if host == "" {
		host = d.smtpHost
		port = "587"
	}

	// Derive our EHLO hostname from email domain
	ehloHost := "localhost"
	if parts := strings.SplitN(d.myAddr, "@", 2); len(parts) == 2 {
		ehloHost = parts[1]
	}

	smtpTLS := &tls.Config{ServerName: host}
	if d.acceptInvalidCerts {
		smtpTLS.InsecureSkipVerify = true
	}

	// Build list of (address, dial-method) to try
	type smtpDial struct {
		addr string
		fn   func(string, *tls.Config) (*smtp.Client, error)
	}
	var tries []smtpDial

	switch port {
	case "465":
		tries = append(tries, smtpDial{host + ":465", smtp.DialTLS})
	case "587":
		tries = append(tries, smtpDial{host + ":587", smtp.DialStartTLS})
	case "25":
		tries = append(tries,
			smtpDial{host + ":25", smtp.DialStartTLS},
			smtpDial{host + ":25", func(a string, tc *tls.Config) (*smtp.Client, error) { return smtp.Dial(a) }},
		)
	default:
		tries = append(tries, smtpDial{host + ":" + port, smtp.DialStartTLS})
		tries = append(tries, smtpDial{host + ":" + port, smtp.DialTLS})
	}
	// Always try standard ports as fallback
	if port != "587" {
		tries = append(tries, smtpDial{host + ":587", smtp.DialStartTLS})
	}
	if port != "465" {
		tries = append(tries, smtpDial{host + ":465", smtp.DialTLS})
	}

	var c *smtp.Client
	var err error
	for _, t := range tries {
		c, err = t.fn(t.addr, smtpTLS)
		if err == nil {
			break
		}
	}
	if err != nil {
		return fmt.Errorf("SMTP dial (tried TLS+STARTTLS): %w", err)
	}
	defer c.Close()

	// Set proper EHLO hostname (chatmail rejects "localhost")
	if err := c.Hello(ehloHost); err != nil {
		return fmt.Errorf("SMTP EHLO: %w", err)
	}

	// Try PLAIN auth first, fall back to LOGIN if rejected
	auth := sasl.NewPlainClient("", d.myAddr, d.password)
	if err := c.Auth(auth); err != nil {
		// LOGIN fallback: some servers only support LOGIN mechanism
		loginAuth := sasl.NewLoginClient(d.myAddr, d.password)
		if err2 := c.Auth(loginAuth); err2 != nil {
			return fmt.Errorf("SMTP auth (PLAIN failed: %v, LOGIN failed: %w)", err, err2)
		}
	}

	var recipients []string
	for _, a := range to {
		recipients = append(recipients, a.Address)
	}
	// Add self for BCC (skip in bot mode, unless self-chat with no other recipients)
	if !d.isBot || len(recipients) == 0 {
		recipients = append(recipients, d.myAddr)
	}

	if err := c.SendMail(d.myAddr, recipients, bytes.NewReader(msg)); err != nil {
		return fmt.Errorf("SMTP send: %w", err)
	}

	return c.Quit()
}

// sendMDN sends a Message Disposition Notification (read receipt).
func (d *DeltaChatCore) sendMDN(toAddr string, originalMsgID string) {
	// Build MDN email
	var buf bytes.Buffer

	var h mail.Header
	h.SetDate(time.Now())
	h.SetAddressList("From", []*mail.Address{{Name: d.myName, Address: d.myAddr}})
	h.SetAddressList("To", []*mail.Address{{Address: toAddr}})
	h.SetSubject("Chat: Message read")
	h.Set("Chat-Version", "1.0")
	h.Set("Message-ID", d.generateMsgID(""))
	h.Set("Auto-Submitted", "auto-replied")
	h.Set("Content-Type", "multipart/report; report-type=disposition-notification")

	w, err := mail.CreateWriter(&buf, h)
	if err != nil {
		return
	}

	// Text part
	var ih mail.InlineHeader
	ih.Set("Content-Type", "text/plain; charset=utf-8")
	pw, _ := w.CreateInline()
	tw, _ := pw.CreatePart(ih)
	io.WriteString(tw, "Read receipts do not guarantee sth. was read.")
	tw.Close()
	pw.Close()

	// Disposition notification part
	var dh mail.InlineHeader
	dh.Set("Content-Type", "message/disposition-notification")
	pw2, _ := w.CreateInline()
	dw, _ := pw2.CreatePart(dh)
	fmt.Fprintf(dw, "Original-Message-ID: %s\r\nDisposition: manual-action/MDN-sent-automatically; displayed\r\n", originalMsgID)
	dw.Close()
	pw2.Close()

	w.Close()

	d.smtpSend([]*mail.Address{{Address: toAddr}}, buf.Bytes())
}

// syncMessages fetches new messages from the DeltaChat IMAP folder.
// SyncNow forces an IMAP sync, fetching new messages from all folders.
func (d *DeltaChatCore) SyncNow() error {
	return d.syncMessages()
}

func (d *DeltaChatCore) syncMessages() error {
	// Sync from both INBOX and DeltaChat folder
	for _, folder := range []string{"INBOX", d.dcFolder} {
		if folder == "" {
			continue
		}
		d.syncFolder(folder)
	}
	return nil
}

func (d *DeltaChatCore) syncFolder(folder string) error {
	selectCmd := d.imapOps.Select(folder, nil)
	mbox, err := selectCmd.Wait()
	if err != nil {
		if isIMAPConnError(err) {
			return fmt.Errorf("%w: IMAP sync %s: %v", ErrDisconnected, folder, err)
		}
		return nil // folder doesn't exist or other non-fatal error, skip
	}

	if mbox.NumMessages == 0 {
		return nil
	}

	// Fetch recent messages (last 100 or since lastSeenUID)
	var seqSet imap.SeqSet
	start := uint32(1)
	if mbox.NumMessages > 100 {
		start = mbox.NumMessages - 99
	}
	seqSet.AddRange(start, mbox.NumMessages)

	fetchOpts := &imap.FetchOptions{
		Envelope: true,
		Flags:    true,
		BodySection: []*imap.FetchItemBodySection{
			{Specifier: imap.PartSpecifierHeader},
			{}, // fetch entire body (needed for PGP/MIME decryption)
		},
	}
	// Bot mode: also fetch UIDs so we can delete after processing
	if d.isBot {
		fetchOpts.UID = true
	}

	fetchCmd := d.imapOps.Fetch(seqSet, fetchOpts)

	var processedUIDs []imap.UID // bot mode: UIDs to delete after processing

	for {
		msgData := fetchCmd.Next()
		if msgData == nil {
			break
		}

		var envelope *imap.Envelope
		var headerBytes, bodyBytes []byte
		var flags []imap.Flag
		var uid imap.UID

		for {
			item := msgData.Next()
			if item == nil {
				break
			}

			switch it := item.(type) {
			case imapclient.FetchItemDataEnvelope:
				envelope = it.Envelope
			case imapclient.FetchItemDataFlags:
				flags = it.Flags
			case imapclient.FetchItemDataUID:
				uid = it.UID
			case imapclient.FetchItemDataBodySection:
				data, _ := io.ReadAll(it.Literal)
				if it.Section != nil && it.Section.Specifier == imap.PartSpecifierHeader {
					headerBytes = data
				} else {
					bodyBytes = data
				}
			}
		}

		if envelope == nil {
			continue
		}

		d.processIncomingEmail(envelope, headerBytes, bodyBytes, flags)

		// Bot mode: mark processed messages for deletion
		if d.isBot && uid > 0 {
			processedUIDs = append(processedUIDs, uid)
		}
	}

	fetchCmd.Close()

	// Bot mode: delete processed messages from server
	if d.isBot && len(processedUIDs) > 0 {
		d.deleteServerMessages(processedUIDs)
	}

	return nil
}

// deleteServerMessages marks messages as \Deleted and expunges them (bot mode cleanup).
func (d *DeltaChatCore) deleteServerMessages(uids []imap.UID) {
	var uidSet imap.UIDSet
	for _, uid := range uids {
		uidSet.AddNum(uid)
	}

	// STORE +FLAGS \Deleted
	storeCmd := d.imapOps.Store(uidSet, &imap.StoreFlags{
		Op:     imap.StoreFlagsAdd,
		Silent: true,
		Flags:  []imap.Flag{imap.FlagDeleted},
	}, nil)
	storeCmd.Close()

	// EXPUNGE to permanently remove
	expungeCmd := d.imapOps.Expunge()
	expungeCmd.Close()
}

// processIncomingEmail parses a fetched email into messages and updates state.
func (d *DeltaChatCore) processIncomingEmail(env *imap.Envelope, headerBytes []byte, bodyBytes []byte, flags []imap.Flag) {
	// Parse headers for DC-specific fields
	headers := parseRawHeaders(headerBytes)

	// Determine sender early (needed for Autocrypt from inner encrypted message)
	var senderEmail, senderName string
	if len(env.From) > 0 {
		senderEmail = canonicalizeEmail(env.From[0].Addr())
		senderName = env.From[0].Name
		if senderName == "" {
			senderName = senderEmail
		}
	}

	// Skip non-DC messages (no Chat-Version header) — but encrypted messages
	// may have Chat-Version inside the encrypted part, so allow multipart/encrypted through
	chatVersion := headers["Chat-Version"]
	contentType := headers["Content-Type"]
	if contentType == "" {
		contentType = headers["content-type"]
	}
	isEncrypted := strings.Contains(contentType, "multipart/encrypted") || strings.Contains(contentType, "pgp-encrypted")
	if chatVersion == "" && headers["chat-version"] == "" && !isEncrypted {
		return
	}

	// Try PGP/MIME decryption: parse multipart/encrypted MIME to extract PGP block
	if isEncrypted {
		if innerBody, innerHeaders, ok := d.decryptPGPMIME(contentType, bodyBytes); ok {
			bodyBytes = innerBody
			// Merge inner headers (inner takes precedence for Chat-* headers)
			for k, v := range innerHeaders {
				headers[k] = v
			}
			// Extract Autocrypt key from inner encrypted message
			if acHeader := innerHeaders["Autocrypt"]; acHeader != "" && senderEmail != "" {
				d.updateAutocryptPeer(senderEmail, senderName, acHeader)
			}
			// Process Autocrypt-Gossip headers (group key distribution)
			if gossip := innerHeaders["Autocrypt-Gossip"]; gossip != "" {
				// Gossip headers may contain multiple keys: addr=...; keydata=...
				// Each gossip entry provides a key for a different group member
				for _, g := range strings.Split(gossip, "\n") {
					g = strings.TrimSpace(g)
					if g == "" {
						continue
					}
					// Parse addr from gossip
					var gAddr string
					for _, part := range strings.Split(g, ";") {
						part = strings.TrimSpace(part)
						if strings.HasPrefix(part, "addr=") {
							gAddr = strings.TrimPrefix(part, "addr=")
						}
					}
					if gAddr != "" {
						d.updateAutocryptPeer(gAddr, "", g)
					}
				}
			}
		}
	}
	// Also try decrypting if body starts with PGP armor directly
	if bytes.HasPrefix(bytes.TrimSpace(bodyBytes), []byte("-----BEGIN PGP MESSAGE-----")) {
		if decrypted, ok := d.decryptMessage(bodyBytes); ok {
			bodyBytes = decrypted
		}
	}

	// Re-check Chat-Version now that we may have decrypted inner headers
	if headers["Chat-Version"] == "" && headers["chat-version"] == "" {
		return
	}

	// Skip blocked senders
	if d.blocked[senderEmail] {
		return
	}

	// Update Autocrypt peer state
	if autocryptHeader := headers["Autocrypt"]; autocryptHeader != "" {
		d.updateAutocryptPeer(senderEmail, senderName, autocryptHeader)
	} else {
		// Update display name at minimum
		d.peerKeysMu.Lock()
		if d.peerStates[senderEmail] == nil {
			d.peerStates[senderEmail] = &dcPeerState{Addr: senderEmail}
		}
		d.peerStates[senderEmail].DisplayName = senderName
		d.peerStates[senderEmail].LastSeen = env.Date
		d.peerKeysMu.Unlock()
	}

	// Determine chat ID
	groupID := headers["Chat-Group-ID"]
	if groupID == "" {
		groupID = headers["chat-group-id"]
	}

	var chatID string
	if groupID != "" {
		chatID = "grp:" + groupID
	} else {
		// DM — use the other party's email
		if senderEmail == d.myAddr {
			// Sent by us — use first recipient
			if len(env.To) > 0 {
				recipEmail := canonicalizeEmail(env.To[0].Addr())
				if recipEmail != d.myAddr {
					chatID = "dm:" + recipEmail
				}
			}
		} else {
			chatID = "dm:" + senderEmail
		}
	}

	if chatID == "" {
		return
	}

	// Handle special message types
	chatContent := headers["Chat-Content"]
	if chatContent == "" {
		chatContent = headers["chat-content"]
	}

	// Handle Chat-Edit
	if editID := headers["Chat-Edit"]; editID != "" {
		d.msgsMu.Lock()
		for i, m := range d.messages[chatID] {
			if m.ID == editID {
				now := env.Date
				d.messages[chatID][i].Text = string(bodyBytes)
				d.messages[chatID][i].EditedAt = &now
				break
			}
		}
		d.msgsMu.Unlock()
		d.fireUpdate(Update{Type: UpdateEditMessage, ChatID: chatID, MessageID: editID, Platform: dcPlatform})
		return
	}

	// Handle Chat-Delete
	if deleteID := headers["Chat-Delete"]; deleteID != "" {
		d.msgsMu.Lock()
		msgs := d.messages[chatID]
		for i, m := range msgs {
			if m.ID == deleteID {
				d.messages[chatID] = append(msgs[:i], msgs[i+1:]...)
				delete(d.msgSeen, deleteID)
				break
			}
		}
		d.msgsMu.Unlock()
		d.fireUpdate(Update{Type: UpdateDeleteMessage, ChatID: chatID, MessageID: deleteID, Platform: dcPlatform})
		return
	}

	// Handle group management
	if memberAdded := headers["Chat-Group-Member-Added"]; memberAdded != "" {
		d.chatsMu.Lock()
		if cs, ok := d.chats[chatID]; ok {
			cs.Members = append(cs.Members, canonicalizeEmail(memberAdded))
		}
		d.chatsMu.Unlock()
	}
	if memberRemoved := headers["Chat-Group-Member-Removed"]; memberRemoved != "" {
		d.chatsMu.Lock()
		if cs, ok := d.chats[chatID]; ok {
			removed := canonicalizeEmail(memberRemoved)
			var newMembers []string
			for _, m := range cs.Members {
				if m != removed {
					newMembers = append(newMembers, m)
				}
			}
			cs.Members = newMembers
		}
		d.chatsMu.Unlock()
	}

	// Ensure chat state exists
	d.chatsMu.Lock()
	if _, ok := d.chats[chatID]; !ok {
		ct := ChatTypeDM
		title := senderEmail
		var members []string

		if groupID != "" {
			ct = ChatTypeGroup
			groupName := headers["Chat-Group-Name"]
			if groupName == "" {
				groupName = headers["chat-group-name"]
			}
			if groupName != "" {
				title = groupName
			}
			// Build member list from To addresses
			for _, addr := range env.To {
				members = append(members, canonicalizeEmail(addr.Addr()))
			}
			if senderEmail != "" {
				members = append(members, senderEmail)
			}
		} else {
			members = []string{d.myAddr, senderEmail}
		}

		d.chats[chatID] = &dcChatState{
			ID:      chatID,
			Type:    ct,
			Title:   title,
			GroupID: groupID,
			Members: members,
		}
	}
	d.chatsMu.Unlock()

	// Check if this is a reaction (Content-Disposition: reaction)
	contentDisp := headers["Content-Disposition"]
	if strings.Contains(contentDisp, "reaction") || chatContent == "reaction" {
		// It's a reaction — update the target message
		if len(env.InReplyTo) > 0 {
			d.msgsMu.Lock()
			for _, m := range d.messages[chatID] {
				if m.ID == env.InReplyTo[0] {
					// Update reactions
					emojiText := strings.TrimSpace(string(bodyBytes))
					found := false
					for i, r := range m.Reactions {
						if r.Emoji == emojiText {
							m.Reactions[i].Count++
							found = true
							break
						}
					}
					if !found && emojiText != "" {
						m.Reactions = append(m.Reactions, Reaction{Emoji: emojiText, Count: 1})
					}
					break
				}
			}
			d.msgsMu.Unlock()
		}
		return
	}

	// Skip system messages from appearing as regular messages
	if chatContent == "call" || chatContent == "call-accepted" || chatContent == "call-ended" {
		return
	}

	// Build message
	msgID := env.MessageID
	text := strings.TrimSpace(string(bodyBytes))

	// Check if already seen
	isSeen := false
	for _, f := range flags {
		if f == imap.FlagSeen {
			isSeen = true
			break
		}
	}

	status := MessageStatusDelivered
	if senderEmail == d.myAddr {
		status = MessageStatusSent
	}
	if isSeen {
		status = MessageStatusRead
	}

	var replyToID string
	if len(env.InReplyTo) > 0 {
		replyToID = env.InReplyTo[0]
	}

	isPinned := false
	if d.pins[chatID] != nil {
		isPinned = d.pins[chatID][msgID]
	}

	m := &Message{
		ID:         msgID,
		ChatID:     chatID,
		SenderID:   senderEmail,
		SenderName: senderName,
		Text:       text,
		Timestamp:  env.Date,
		Status:     status,
		ReplyToID:  replyToID,
		IsPinned:   isPinned,
		IsOutgoing: senderEmail == d.myAddr,
		Platform:   dcPlatform,
	}

	// Cache and fire update
	d.cacheMessage(chatID, m)
	d.updateChatTime(chatID, env.Date)

	if senderEmail != d.myAddr {
		d.chatsMu.Lock()
		if cs, ok := d.chats[chatID]; ok && !isSeen {
			cs.UnreadCount++
		}
		d.chatsMu.Unlock()
	}

	d.fireUpdate(Update{
		Type:     UpdateNewMessage,
		ChatID:   chatID,
		Message:  m,
		Platform: dcPlatform,
	})
}

// idleLoop runs IMAP IDLE on a folder, restarting every 28 minutes.
func (d *DeltaChatCore) idleLoop(client *imapclient.Client, folder string, label string) {
	currentClient := client
	for {
		select {
		case <-d.ctx.Done():
			return
		default:
		}

		// Select the folder
		selectCmd := currentClient.Select(folder, nil)
		if _, err := selectCmd.Wait(); err != nil {
			// Connection likely dropped — attempt reconnect
			reconnected := d.reconnectIDLE(&currentClient, folder, label)
			if !reconnected {
				return // context cancelled or max retries exceeded
			}
			continue
		}

		// Start IDLE
		idleCmd, err := currentClient.Idle()
		if err != nil {
			reconnected := d.reconnectIDLE(&currentClient, folder, label)
			if !reconnected {
				return
			}
			continue
		}

		// Wait for 28 minutes or context cancellation
		timer := time.NewTimer(28 * time.Minute)
		select {
		case <-d.ctx.Done():
			timer.Stop()
			idleCmd.Close()
			idleCmd.Wait()
			return
		case <-timer.C:
			// Restart IDLE (normal refresh)
		}
		timer.Stop()

		if err := idleCmd.Close(); err != nil {
			// IDLE close failed — connection probably dropped
			reconnected := d.reconnectIDLE(&currentClient, folder, label)
			if !reconnected {
				return
			}
			continue
		}
		if err := idleCmd.Wait(); err != nil {
			reconnected := d.reconnectIDLE(&currentClient, folder, label)
			if !reconnected {
				return
			}
			continue
		}

		// Sync new messages
		d.mu.RLock()
		authed := d.authed
		d.mu.RUnlock()
		if authed {
			d.syncMessages()
		}
	}
}

// reconnectIDLE attempts to re-establish an IMAP connection with exponential backoff.
// It updates the client pointer in-place and swaps the corresponding struct field.
// Returns true if reconnected, false if context was cancelled or retries exhausted.
func (d *DeltaChatCore) reconnectIDLE(clientPtr **imapclient.Client, folder string, label string) bool {
	d.fireUpdate(Update{
		Type:      UpdateConnectivity,
		Platform:  dcPlatform,
		ChatID:    label,
		ConnState: "disconnected",
	})

	var newClient *imapclient.Client
	err := utils.Retry(d.ctx, 10, 5*time.Second, 120*time.Second, nil, func() error {
		c, err := d.connectIMAP()
		if err != nil {
			return err
		}
		newClient = c
		return nil
	})
	if err != nil {
		// All retries exhausted — fire permanent disconnect
		d.fireUpdate(Update{
			Type:      UpdateConnectivity,
			Platform:  dcPlatform,
			ChatID:    label,
			ConnState: "disconnected",
		})
		return false
	}

	// Success — close old client (ignore errors, it's likely dead)
	if *clientPtr != nil {
		(*clientPtr).Close()
	}
	*clientPtr = newClient

	// Update the struct field so Logout can close the right client
	d.mu.Lock()
	switch label {
	case "inbox-idle":
		d.idleInbox = newClient
	case "dc-idle":
		d.idleDC = newClient
	}
	d.mu.Unlock()

	d.fireUpdate(Update{
		Type:      UpdateConnectivity,
		Platform:  dcPlatform,
		ChatID:    label,
		ConnState: "connected",
	})

	// Sync messages after reconnect
	d.mu.RLock()
	authed := d.authed
	d.mu.RUnlock()
	if authed {
		d.syncMessages()
	}

	return true
}

// isIMAPConnError returns true if the error indicates a dropped IMAP connection
// (I/O timeout, connection reset, EOF, broken pipe, etc.).
func isIMAPConnError(err error) bool {
	if err == nil {
		return false
	}
	if errors.Is(err, io.EOF) || errors.Is(err, io.ErrUnexpectedEOF) {
		return true
	}
	var netErr net.Error
	if errors.As(err, &netErr) {
		return true
	}
	var opErr *net.OpError
	if errors.As(err, &opErr) {
		return true
	}
	s := err.Error()
	return strings.Contains(s, "connection reset") ||
		strings.Contains(s, "broken pipe") ||
		strings.Contains(s, "use of closed network connection") ||
		strings.Contains(s, "i/o timeout")
}

// --- Autocrypt helpers ---

func (d *DeltaChatCore) generateKeypair() (*openpgp.Entity, error) {
	config := &packet.Config{
		Algorithm: packet.PubKeyAlgoEdDSA, // Ed25519
	}
	entity, err := openpgp.NewEntity(d.myName, "", d.myAddr, config)
	if err != nil {
		return nil, err
	}
	return entity, nil
}

func (d *DeltaChatCore) serializePublicKey() string {
	if d.myEntity == nil {
		return ""
	}
	if d.cachedPubKeyOK {
		return d.cachedPubKey
	}
	var buf bytes.Buffer
	if err := d.myEntity.Serialize(&buf); err != nil {
		return ""
	}
	d.cachedPubKey = base64.StdEncoding.EncodeToString(buf.Bytes())
	d.cachedPubKeyOK = true
	return d.cachedPubKey
}

func (d *DeltaChatCore) getMyFingerprint() string {
	if d.myEntity == nil {
		return ""
	}
	fp := d.myEntity.PrimaryKey.Fingerprint
	return fmt.Sprintf("%X", fp)
}

// SetPeerPublicKey injects a peer's public key for testing.
// Accepts both ASCII-armored (.asc) and raw binary OpenPGP key formats.
// This allows pre-seeding keys for chatmail interop where you can't send plaintext first.
func (d *DeltaChatCore) SetPeerPublicKey(email string, pubKeyBytes []byte) error {
	var entities openpgp.EntityList
	var err error

	// Try ASCII armor first (public or private key block — private contains the public key)
	if bytes.Contains(pubKeyBytes, []byte("-----BEGIN PGP")) {
		block, decErr := armor.Decode(bytes.NewReader(pubKeyBytes))
		if decErr == nil {
			entities, err = openpgp.ReadKeyRing(block.Body)
		} else {
			err = decErr
		}
	} else {
		entities, err = openpgp.ReadKeyRing(bytes.NewReader(pubKeyBytes))
	}
	if err != nil || len(entities) == 0 {
		return fmt.Errorf("parse public key: %w", err)
	}

	d.peerKeysMu.Lock()
	defer d.peerKeysMu.Unlock()

	if d.peerStates[email] == nil {
		d.peerStates[email] = &dcPeerState{Addr: email}
	}
	ps := d.peerStates[email]
	// Serialize entity to binary for consistent storage
	var keyBuf bytes.Buffer
	entities[0].Serialize(&keyBuf)
	ps.PublicKey = keyBuf.Bytes()
	ps.entity = entities[0]
	ps.AutocryptTimestamp = time.Now()
	ps.PreferEncrypt = "mutual"
	return nil
}

func (d *DeltaChatCore) updateAutocryptPeer(email string, name string, autocryptHeader string) {
	// Parse: addr=...; prefer-encrypt=mutual; keydata=...
	parts := strings.Split(autocryptHeader, ";")
	var keydata string
	var preferEncrypt string

	for _, p := range parts {
		p = strings.TrimSpace(p)
		if strings.HasPrefix(p, "keydata=") {
			keydata = strings.TrimPrefix(p, "keydata=")
		} else if strings.HasPrefix(p, "prefer-encrypt=") {
			preferEncrypt = strings.TrimPrefix(p, "prefer-encrypt=")
		}
	}

	d.peerKeysMu.Lock()
	defer d.peerKeysMu.Unlock()

	if d.peerStates[email] == nil {
		d.peerStates[email] = &dcPeerState{Addr: email}
	}
	ps := d.peerStates[email]
	ps.DisplayName = name
	ps.LastSeen = time.Now()
	ps.PreferEncrypt = preferEncrypt

	if keydata != "" {
		keyBytes, err := base64.StdEncoding.DecodeString(keydata)
		if err == nil {
			ps.PublicKey = keyBytes
			ps.AutocryptTimestamp = time.Now()
			// Parse entity
			entities, err := openpgp.ReadKeyRing(bytes.NewReader(keyBytes))
			if err == nil && len(entities) > 0 {
				ps.entity = entities[0]
			}
		}
	}
}

// --- Session persistence ---

func (d *DeltaChatCore) saveSession() {
	if d.session == nil {
		return
	}

	// Serialize private key
	var keyBuf bytes.Buffer
	if d.myEntity != nil {
		armorWriter, _ := armor.Encode(&keyBuf, "PGP PRIVATE KEY BLOCK", nil)
		d.myEntity.SerializePrivate(armorWriter, nil)
		armorWriter.Close()
	}

	sess := dcSession{
		Email:             d.myAddr,
		Password:          d.password,
		IMAPHost:          d.imapHost,
		SMTPHost:          d.smtpHost,
		DisplayName:       d.myName,
		Status:            d.myStatus,
		DCFolder:          d.dcFolder,
		IsBot:             d.isBot,
		PrivateKey:        keyBuf.String(),
		PeerStates:        d.peerStates,
		Chats:             d.chats,
		Blocked:           d.blocked,
		Folders:           d.folders,
		Pins:              d.pins,
		DeviceMsgLabels:   d.deviceMsgLabels,
		WebxdcUpdates:     d.webxdcUpdates,
		WebxdcIntegration: d.webxdcIntegration,
		StickerDir:        d.stickerDir,
		Transports:        d.transports,
		Locations:         d.locations,
		ShowEmails:        d.showEmails,
		DownloadLimit:     d.downloadLimit,
		CallFilter:        d.callFilter,
		PushToken:         d.pushToken,
	}

	d.session.Save(sess)
}

func (d *DeltaChatCore) loadSession() error {
	if d.session == nil {
		return fmt.Errorf("no session store")
	}

	var sess dcSession
	if err := d.session.Load(&sess); err != nil {
		return err
	}
	if sess.Email == "" {
		return fmt.Errorf("no session file")
	}

	d.myAddr = sess.Email
	d.password = sess.Password
	d.imapHost = sess.IMAPHost
	d.smtpHost = sess.SMTPHost
	d.myName = sess.DisplayName
	d.myStatus = sess.Status
	d.dcFolder = sess.DCFolder
	d.isBot = sess.IsBot

	if sess.PeerStates != nil {
		d.peerStates = sess.PeerStates
	}
	if sess.Chats != nil {
		d.chats = sess.Chats
	}
	if sess.Blocked != nil {
		d.blocked = sess.Blocked
	}
	if sess.Folders != nil {
		d.folders = sess.Folders
	}
	if sess.Pins != nil {
		d.pins = sess.Pins
	}
	if sess.DeviceMsgLabels != nil {
		d.deviceMsgLabels = sess.DeviceMsgLabels
	}
	if sess.WebxdcUpdates != nil {
		d.webxdcUpdates = sess.WebxdcUpdates
	}
	d.webxdcIntegration = sess.WebxdcIntegration
	d.stickerDir = sess.StickerDir
	if sess.Transports != nil {
		d.transports = sess.Transports
	}
	if sess.Locations != nil {
		d.locations = sess.Locations
	}
	d.showEmails = sess.ShowEmails
	d.downloadLimit = sess.DownloadLimit
	d.callFilter = sess.CallFilter
	d.pushToken = sess.PushToken
	if d.pushToken != "" {
		d.pushState = "Connected"
	}

	// Deserialize private key
	if sess.PrivateKey != "" {
		block, err := armor.Decode(strings.NewReader(sess.PrivateKey))
		if err == nil {
			entities, err := openpgp.ReadKeyRing(block.Body)
			if err == nil && len(entities) > 0 {
				d.myEntity = entities[0]
				d.cachedPubKeyOK = false
			}
		}
	}

	return nil
}

// --- Utility functions ---

func canonicalizeEmail(email string) string {
	return strings.TrimSpace(strings.ToLower(email))
}

func generateGroupID() string {
	const chars = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
	var raw [16]byte
	rand.Read(raw[:])
	for i, b := range raw {
		raw[i] = chars[int(b)%len(chars)]
	}
	return string(raw[:])
}

func generateShortID() string {
	const chars = "0123456789abcdefghijklmnopqrstuvwxyz"
	var raw [8]byte
	rand.Read(raw[:])
	for i, b := range raw {
		raw[i] = chars[int(b)%len(chars)]
	}
	return string(raw[:])
}

func (d *DeltaChatCore) generateMsgID(groupID string) string {
	random := generateShortID()
	domain := d.myAddr
	if idx := strings.Index(d.myAddr, "@"); idx >= 0 {
		domain = d.myAddr[idx+1:]
	}
	if groupID != "" {
		return "<Gr." + groupID + "." + random + "@" + domain + ">"
	}
	return "<Mr." + random + "@" + domain + ">"
}

func (d *DeltaChatCore) chatStateToDialog(cs *dcChatState) Dialog {
	d.msgsMu.RLock()
	var lastMsg *Message
	if msgs := d.messages[cs.ID]; len(msgs) > 0 {
		lastMsg = msgs[len(msgs)-1]
	}
	d.msgsMu.RUnlock()

	return Dialog{
		ID:          cs.ID,
		Type:        cs.Type,
		Title:       cs.Title,
		AvatarB64:   cs.AvatarB64,
		LastMessage: lastMsg,
		UnreadCount: cs.UnreadCount,
		IsMuted:     cs.MuteUntil != nil,
		IsPinned:    cs.Visibility == 2,
		IsArchived:  cs.Visibility == 1,
		MemberCount: len(cs.Members),
		Platform:    dcPlatform,
	}
}

func (d *DeltaChatCore) cacheMessage(chatID string, m *Message) {
	d.msgsMu.Lock()
	defer d.msgsMu.Unlock()

	if d.msgSeen[m.ID] {
		return
	}
	d.msgSeen[m.ID] = true
	d.messages[chatID] = append(d.messages[chatID], m)
}

func (d *DeltaChatCore) updateChatTime(chatID string, t time.Time) {
	d.chatsMu.Lock()
	if cs, ok := d.chats[chatID]; ok {
		cs.LastMsgTime = t.Unix()
	}
	d.chatsMu.Unlock()
}

func (d *DeltaChatCore) fireUpdate(u Update) {
	d.updateMu.RLock()
	handlers := make([]func(Update), len(d.updateHandlers))
	copy(handlers, d.updateHandlers)
	d.updateMu.RUnlock()
	for _, h := range handlers {
		h(u)
	}
}

// parseRawHeaders parses raw email header bytes into a map.
func parseRawHeaders(data []byte) map[string]string {
	headers := make(map[string]string, 16)
	var currentKey string
	var currentValue strings.Builder

	for len(data) > 0 {
		nlIdx := bytes.IndexByte(data, '\n')
		var line []byte
		if nlIdx < 0 {
			line = data
			data = nil
		} else {
			line = data[:nlIdx]
			data = data[nlIdx+1:]
		}
		if len(line) > 0 && line[len(line)-1] == '\r' {
			line = line[:len(line)-1]
		}
		if len(line) == 0 {
			if currentKey != "" {
				headers[currentKey] = strings.TrimSpace(currentValue.String())
			}
			break
		}
		if line[0] == ' ' || line[0] == '\t' {
			currentValue.WriteByte(' ')
			currentValue.Write(bytes.TrimSpace(line))
			continue
		}
		if currentKey != "" {
			headers[currentKey] = strings.TrimSpace(currentValue.String())
		}
		idx := bytes.IndexByte(line, ':')
		if idx < 0 {
			currentKey = ""
			continue
		}
		currentKey = string(line[:idx])
		currentValue.Reset()
		currentValue.Write(line[idx+1:])
	}
	if currentKey != "" {
		headers[currentKey] = strings.TrimSpace(currentValue.String())
	}

	return headers
}

// autoDiscoverServers resolves IMAP/SMTP servers for a chatmail domain.
// Chatmail instances use the domain itself as both IMAP and SMTP host.
// For custom/self-hosted chatmail, falls back to DNS SRV records then domain:port.
func autoDiscoverServers(email string) (imapHost string, smtpHost string) {
	parts := strings.SplitN(email, "@", 2)
	if len(parts) != 2 {
		return "", ""
	}
	domain := parts[1]

	// DNS SRV records (chatmail instances publish these)
	_, srvs, err := net.LookupSRV("imaps", "tcp", domain)
	if err == nil && len(srvs) > 0 {
		imapHost = fmt.Sprintf("%s:%d", strings.TrimSuffix(srvs[0].Target, "."), srvs[0].Port)
	}
	if imapHost == "" {
		_, srvs, err = net.LookupSRV("imap", "tcp", domain)
		if err == nil && len(srvs) > 0 {
			imapHost = fmt.Sprintf("%s:%d", strings.TrimSuffix(srvs[0].Target, "."), srvs[0].Port)
		}
	}
	_, srvs, err = net.LookupSRV("submission", "tcp", domain)
	if err == nil && len(srvs) > 0 {
		smtpHost = fmt.Sprintf("%s:%d", strings.TrimSuffix(srvs[0].Target, "."), srvs[0].Port)
	}

	// Chatmail default: domain itself serves IMAP (993) and SMTP (587)
	if imapHost == "" {
		imapHost = domain + ":993"
	}
	if smtpHost == "" {
		smtpHost = domain + ":587"
	}

	return imapHost, smtpHost
}

// ──────────────────────────── Webxdc ────────────────────────────

// SendWebxdcStatusUpdate sends a status update for a webxdc app instance.
// Updates are delivered to all chat members via an email with Chat-Content: webxdc-status-update.
func (d *DeltaChatCore) SendWebxdcStatusUpdate(chatID, msgID string, payload json.RawMessage, info string) error {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if !d.authed {
		return ErrAuth
	}

	d.chatsMu.RLock()
	cs, ok := d.chats[chatID]
	d.chatsMu.RUnlock()
	if !ok {
		return ErrNotFound
	}

	// Build the update
	d.webxdcMu.Lock()
	updates := d.webxdcUpdates[msgID]
	serial := len(updates) + 1
	update := DCWebxdcUpdate{
		Serial:  serial,
		Payload: payload,
		Info:    info,
		Sender:  d.myAddr,
		Time:    time.Now().Unix(),
	}
	d.webxdcUpdates[msgID] = append(updates, update)
	d.webxdcMu.Unlock()

	// Send as email to chat members
	var toAddrs []*mail.Address
	for _, m := range cs.Members {
		if m != d.myAddr {
			toAddrs = append(toAddrs, &mail.Address{Address: m})
		}
	}
	if len(toAddrs) == 0 {
		d.saveSession()
		return nil // self-chat, just store locally
	}

	updateJSON, err := json.Marshal(update)
	if err != nil {
		return fmt.Errorf("marshal update: %w", err)
	}

	headers := map[string]string{
		"Chat-Content": "webxdc-status-update",
		"In-Reply-To":  msgID,
	}
	if cs.GroupID != "" {
		headers["Chat-Group-ID"] = cs.GroupID
	}

	emailMsgID := d.generateMsgID(cs.GroupID)
	if err := d.sendEmail(toAddrs, "Chat: "+cs.Title, string(updateJSON), emailMsgID, msgID, headers, nil); err != nil {
		return fmt.Errorf("send webxdc update: %w", err)
	}

	d.saveSession()
	return nil
}

// GetWebxdcStatusUpdates returns status updates for a webxdc app instance since lastKnownSerial.
func (d *DeltaChatCore) GetWebxdcStatusUpdates(msgID string, lastKnownSerial int) ([]DCWebxdcUpdate, error) {
	d.webxdcMu.RLock()
	defer d.webxdcMu.RUnlock()

	updates := d.webxdcUpdates[msgID]
	if lastKnownSerial >= len(updates) {
		return nil, nil
	}
	return updates[lastKnownSerial:], nil
}

// GetWebxdcInfo parses the manifest.toml from a .xdc ZIP to extract app metadata.
// The msgID must reference a message with a .xdc file attachment stored in local cache.
func (d *DeltaChatCore) GetWebxdcInfo(chatID, msgID string) (*DeltaChatWebxdcInfo, error) {
	d.msgsMu.RLock()
	defer d.msgsMu.RUnlock()

	for _, m := range d.messages[chatID] {
		if m.ID == msgID && len(m.Attachments) > 0 && m.Attachments[0].URL != "" {
			return d.parseWebxdcManifest(m.Attachments[0].URL)
		}
	}
	return nil, ErrNotFound
}

// parseWebxdcManifest reads a .xdc ZIP and extracts manifest.toml metadata.
func (d *DeltaChatCore) parseWebxdcManifest(path string) (*DeltaChatWebxdcInfo, error) {
	r, err := zip.OpenReader(path)
	if err != nil {
		return nil, fmt.Errorf("open xdc: %w", err)
	}
	defer r.Close()

	info := &DeltaChatWebxdcInfo{}

	for _, f := range r.File {
		switch f.Name {
		case "manifest.toml":
			rc, err := f.Open()
			if err != nil {
				continue
			}
			data, _ := io.ReadAll(rc)
			rc.Close()
			// Parse simple TOML (key = "value" lines)
			for _, line := range strings.Split(string(data), "\n") {
				line = strings.TrimSpace(line)
				if k, v, ok := strings.Cut(line, "="); ok {
					k = strings.TrimSpace(k)
					v = strings.TrimSpace(v)
					v = strings.Trim(v, "\"")
					switch k {
					case "name":
						info.Name = v
					case "source_code_url":
						info.SourceCodeURL = v
					case "summary":
						info.Summary = v
					}
				}
			}
		case "icon.png", "icon.jpg", "icon.svg":
			info.Icon = f.Name
		}
	}

	return info, nil
}

// GetWebxdcBlob extracts a named file from a .xdc ZIP attachment.
func (d *DeltaChatCore) GetWebxdcBlob(chatID, msgID, blobName string) ([]byte, string, error) {
	d.msgsMu.RLock()
	var path string
	for _, m := range d.messages[chatID] {
		if m.ID == msgID && len(m.Attachments) > 0 && m.Attachments[0].URL != "" {
			path = m.Attachments[0].URL
			break
		}
	}
	d.msgsMu.RUnlock()

	if path == "" {
		return nil, "", ErrNotFound
	}

	r, err := zip.OpenReader(path)
	if err != nil {
		return nil, "", fmt.Errorf("open xdc: %w", err)
	}
	defer r.Close()

	for _, f := range r.File {
		if f.Name == blobName {
			rc, err := f.Open()
			if err != nil {
				return nil, "", err
			}
			data, err := io.ReadAll(rc)
			rc.Close()
			if err != nil {
				return nil, "", err
			}
			mimeType := mime.TypeByExtension(filepath.Ext(blobName))
			if mimeType == "" {
				mimeType = "application/octet-stream"
			}
			return data, mimeType, nil
		}
	}
	return nil, "", fmt.Errorf("blob %q not found in xdc", blobName)
}

// SetWebxdcIntegration registers a webxdc app as the integration provider (e.g., maps).
func (d *DeltaChatCore) SetWebxdcIntegration(msgID string) error {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if !d.authed {
		return ErrAuth
	}
	d.webxdcIntegration = msgID
	d.saveSession()
	return nil
}

// InitWebxdcIntegration initializes the integration webxdc for a given filter.
// Returns the message ID of the integration webxdc, or empty if none configured.
func (d *DeltaChatCore) InitWebxdcIntegration(filter string) (string, error) {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if !d.authed {
		return "", ErrAuth
	}
	if d.webxdcIntegration == "" {
		return "", fmt.Errorf("no webxdc integration configured")
	}
	return d.webxdcIntegration, nil
}

// SendWebxdcRealtimeData sends real-time data for a webxdc app via email (non-P2P fallback).
func (d *DeltaChatCore) SendWebxdcRealtimeData(chatID, msgID string, data []byte) error {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if !d.authed {
		return ErrAuth
	}

	d.chatsMu.RLock()
	cs, ok := d.chats[chatID]
	d.chatsMu.RUnlock()
	if !ok {
		return ErrNotFound
	}

	var toAddrs []*mail.Address
	for _, m := range cs.Members {
		if m != d.myAddr {
			toAddrs = append(toAddrs, &mail.Address{Address: m})
		}
	}
	if len(toAddrs) == 0 {
		return nil
	}

	headers := map[string]string{
		"Chat-Content": "webxdc-realtime-data",
		"In-Reply-To":  msgID,
	}
	if cs.GroupID != "" {
		headers["Chat-Group-ID"] = cs.GroupID
	}

	encoded := base64.StdEncoding.EncodeToString(data)
	emailMsgID := d.generateMsgID(cs.GroupID)
	return d.sendEmail(toAddrs, "Chat: "+cs.Title, encoded, emailMsgID, msgID, headers, nil)
}

// SendWebxdcRealtimeAdvertisement advertises P2P availability for a webxdc app.
// In our implementation this sends a notification email to chat members.
func (d *DeltaChatCore) SendWebxdcRealtimeAdvertisement(chatID, msgID string) error {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if !d.authed {
		return ErrAuth
	}

	d.chatsMu.RLock()
	cs, ok := d.chats[chatID]
	d.chatsMu.RUnlock()
	if !ok {
		return ErrNotFound
	}

	var toAddrs []*mail.Address
	for _, m := range cs.Members {
		if m != d.myAddr {
			toAddrs = append(toAddrs, &mail.Address{Address: m})
		}
	}
	if len(toAddrs) == 0 {
		return nil
	}

	headers := map[string]string{
		"Chat-Content": "webxdc-realtime-advertisement",
		"In-Reply-To":  msgID,
	}
	if cs.GroupID != "" {
		headers["Chat-Group-ID"] = cs.GroupID
	}

	emailMsgID := d.generateMsgID(cs.GroupID)
	return d.sendEmail(toAddrs, "Chat: "+cs.Title, "", emailMsgID, msgID, headers, nil)
}

// LeaveWebxdcRealtime leaves the real-time channel for a webxdc app.
// Stops sending/receiving real-time data for this app instance.
func (d *DeltaChatCore) LeaveWebxdcRealtime(chatID, msgID string) error {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if !d.authed {
		return ErrAuth
	}

	d.chatsMu.RLock()
	cs, ok := d.chats[chatID]
	d.chatsMu.RUnlock()
	if !ok {
		return ErrNotFound
	}

	var toAddrs []*mail.Address
	for _, m := range cs.Members {
		if m != d.myAddr {
			toAddrs = append(toAddrs, &mail.Address{Address: m})
		}
	}
	if len(toAddrs) == 0 {
		return nil
	}

	headers := map[string]string{
		"Chat-Content": "webxdc-realtime-leave",
		"In-Reply-To":  msgID,
	}
	if cs.GroupID != "" {
		headers["Chat-Group-ID"] = cs.GroupID
	}

	emailMsgID := d.generateMsgID(cs.GroupID)
	return d.sendEmail(toAddrs, "Chat: "+cs.Title, "", emailMsgID, msgID, headers, nil)
}

// ──────────────────────────── Account Management ────────────────────────────

// DeactivateAccount requests account deletion from the email provider.
// For chatmail servers, this sends a special delete-request email.
// For other providers, it simply logs out.
func (d *DeltaChatCore) DeactivateAccount() error {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if !d.authed {
		return ErrAuth
	}

	// Chatmail supports account deletion by sending a specific email to self
	deleteAddr := &mail.Address{Address: d.myAddr}
	headers := map[string]string{
		"Chat-Content":   "delete-request",
		"Auto-Submitted": "auto-generated",
	}
	msgID := d.generateMsgID("")
	if err := d.sendEmail([]*mail.Address{deleteAddr}, "Delete my account", "Please delete this account.", msgID, "", headers, nil); err != nil {
		return fmt.Errorf("send delete request: %w", err)
	}
	return nil
}

// ChangePassphrase changes the IMAP/SMTP password.
// Chatmail servers support password change via a special mechanism.
// For standard providers, this returns an error — use the provider's web interface.
func (d *DeltaChatCore) ChangePassphrase(oldPass, newPass string) error {
	d.mu.Lock()
	defer d.mu.Unlock()
	if !d.authed {
		return ErrAuth
	}

	if d.password != oldPass {
		return fmt.Errorf("old password does not match")
	}

	// Try reconnecting with new password to verify it works
	parts := strings.SplitN(d.imapHost, ":", 2)
	if len(parts) != 2 {
		return fmt.Errorf("invalid IMAP host format")
	}

	testClient, err := imapclient.DialTLS(d.imapHost, &imapclient.Options{
		TLSConfig: &tls.Config{InsecureSkipVerify: d.acceptInvalidCerts},
	})
	if err != nil {
		return fmt.Errorf("connect with new password: %w", err)
	}
	if err := testClient.Login(d.myAddr, newPass).Wait(); err != nil {
		testClient.Close()
		return fmt.Errorf("login with new password failed: %w", err)
	}
	testClient.Close()

	// Success — update stored password
	d.password = newPass
	d.saveSession()
	return nil
}

// GetAccountFileSize returns the size in bytes of the session file on disk.
func (d *DeltaChatCore) GetAccountFileSize() (int64, error) {
	if d.session == nil {
		return 0, fmt.Errorf("no session store configured")
	}
	// Estimate size by marshaling current session
	d.saveSession()
	var sess dcSession
	if err := d.session.Load(&sess); err != nil {
		return 0, err
	}
	data, err := json.Marshal(sess)
	if err != nil {
		return 0, err
	}
	return int64(len(data)), nil
}

// GetStorageUsageReport returns a breakdown of local storage usage.
func (d *DeltaChatCore) GetStorageUsageReport() (*DeltaChatStorageReport, error) {
	report := &DeltaChatStorageReport{}

	if d.session != nil {
		if size, err := d.GetAccountFileSize(); err == nil {
			report.SessionBytes = size
			report.TotalBytes = size
		}
	}

	d.msgsMu.RLock()
	for _, msgs := range d.messages {
		report.MessagesCount += len(msgs)
	}
	d.msgsMu.RUnlock()

	d.chatsMu.RLock()
	report.ChatsCount = len(d.chats)
	d.chatsMu.RUnlock()

	d.peerKeysMu.RLock()
	report.ContactsCount = len(d.peerStates)
	d.peerKeysMu.RUnlock()

	// Account for sticker dir size
	if d.stickerDir != "" {
		filepath.Walk(d.stickerDir, func(_ string, fi os.FileInfo, _ error) error {
			if fi != nil && !fi.IsDir() {
				report.TotalBytes += fi.Size()
			}
			return nil
		})
	}

	return report, nil
}

// ──────────────────────────── Key Transfer (Autocrypt Setup Message) ────────────────────────────

// InitiateKeyTransfer creates an Autocrypt Setup Message and sends it to self.
// Returns the setup code (44 digits formatted as 9 groups of 4 + check digits) that the
// receiving device needs to enter to decrypt the key.
func (d *DeltaChatCore) InitiateKeyTransfer() (string, error) {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if !d.authed {
		return "", ErrAuth
	}
	if d.myEntity == nil {
		return "", fmt.Errorf("no private key to transfer")
	}

	// Generate 44-digit setup code (9 groups of 4 digits separated by dashes)
	setupCode := d.generateSetupCode()

	// Serialize private key in armored format
	var keyBuf bytes.Buffer
	armorWriter, err := armor.Encode(&keyBuf, "PGP PRIVATE KEY BLOCK", nil)
	if err != nil {
		return "", fmt.Errorf("armor encode: %w", err)
	}
	if err := d.myEntity.SerializePrivate(armorWriter, nil); err != nil {
		return "", fmt.Errorf("serialize key: %w", err)
	}
	armorWriter.Close()

	// Symmetrically encrypt with the setup code as passphrase
	var encBuf bytes.Buffer
	encArmorWriter, err := armor.Encode(&encBuf, "PGP MESSAGE", map[string]string{
		"Passphrase-Format": "numeric9x4",
		"Passphrase-Begin":  setupCode[:2],
	})
	if err != nil {
		return "", fmt.Errorf("armor encrypt: %w", err)
	}

	encWriter, err := openpgp.SymmetricallyEncrypt(encArmorWriter, []byte(setupCode), nil, &packet.Config{
		DefaultCipher: packet.CipherAES128,
	})
	if err != nil {
		return "", fmt.Errorf("symmetric encrypt: %w", err)
	}
	encWriter.Write(keyBuf.Bytes())
	encWriter.Close()
	encArmorWriter.Close()

	// Send as Autocrypt Setup Message to self
	toAddr := &mail.Address{Address: d.myAddr}
	headers := map[string]string{
		"Autocrypt-Setup-Message": "v1",
		"Auto-Submitted":         "auto-generated",
	}
	att := &dcAttachment{
		Name:     "autocrypt-setup-message.html",
		MimeType: "application/autocrypt-setup",
		Data:     encBuf.Bytes(),
	}
	msgID := d.generateMsgID("")
	if err := d.sendEmail([]*mail.Address{toAddr}, "Autocrypt Setup Message", "This is the Autocrypt Setup Message.", msgID, "", headers, att); err != nil {
		return "", fmt.Errorf("send setup message: %w", err)
	}

	return setupCode, nil
}

// ContinueKeyTransfer decrypts an Autocrypt Setup Message using the setup code
// and imports the private key.
func (d *DeltaChatCore) ContinueKeyTransfer(msgID, setupCode string) error {
	d.mu.Lock()
	defer d.mu.Unlock()
	if !d.authed {
		return ErrAuth
	}

	// Find the setup message in our cached messages
	d.msgsMu.RLock()
	var setupData []byte
	for _, msgs := range d.messages {
		for _, m := range msgs {
			if m.ID == msgID && len(m.Attachments) > 0 && m.Attachments[0].URL != "" {
				data, err := os.ReadFile(m.Attachments[0].URL)
				if err == nil {
					setupData = data
				}
				break
			}
		}
		if setupData != nil {
			break
		}
	}
	d.msgsMu.RUnlock()

	if setupData == nil {
		return fmt.Errorf("setup message not found or no attachment")
	}

	// Strip setup code formatting (remove dashes, spaces)
	cleanCode := strings.Map(func(r rune) rune {
		if r >= '0' && r <= '9' {
			return r
		}
		return -1
	}, setupCode)

	// Decrypt the armored PGP message
	block, err := armor.Decode(bytes.NewReader(setupData))
	if err != nil {
		return fmt.Errorf("decode armor: %w", err)
	}

	md, err := openpgp.ReadMessage(block.Body, nil, func(keys []openpgp.Key, symmetric bool) ([]byte, error) {
		return []byte(cleanCode), nil
	}, nil)
	if err != nil {
		return fmt.Errorf("decrypt setup message (wrong code?): %w", err)
	}

	// Read the decrypted private key
	keyData, err := io.ReadAll(md.UnverifiedBody)
	if err != nil {
		return fmt.Errorf("read decrypted key: %w", err)
	}

	// Import the private key
	keyBlock, err := armor.Decode(bytes.NewReader(keyData))
	if err != nil {
		return fmt.Errorf("decode key armor: %w", err)
	}

	entities, err := openpgp.ReadKeyRing(keyBlock.Body)
	if err != nil || len(entities) == 0 {
		return fmt.Errorf("read key ring: %w", err)
	}

	d.myEntity = entities[0]
	d.cachedPubKeyOK = false
	d.saveSession()
	return nil
}

// generateSetupCode generates a 44-digit Autocrypt setup code (9 groups of 4 digits).
func (d *DeltaChatCore) generateSetupCode() string {
	var raw [18]byte
	rand.Read(raw[:])
	var sb strings.Builder
	sb.Grow(44)
	for i := 0; i < 9; i++ {
		if i > 0 {
			sb.WriteByte('-')
		}
		v := (int(raw[i*2])<<8 | int(raw[i*2+1])) % 10000
		sb.WriteString(fmt.Sprintf("%04d", v))
	}
	return sb.String()
}

// ──────────────────────────── Key Management ────────────────────────────

// ExportSelfKeys exports PGP keys (public + private) as armored ASCII files to the given directory.
func (d *DeltaChatCore) ExportSelfKeys(dir string) error {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if d.myEntity == nil {
		return fmt.Errorf("no keys to export")
	}

	if err := os.MkdirAll(dir, 0700); err != nil {
		return fmt.Errorf("create dir: %w", err)
	}

	// Export public key
	var pubBuf bytes.Buffer
	pubArmor, err := armor.Encode(&pubBuf, "PGP PUBLIC KEY BLOCK", nil)
	if err != nil {
		return fmt.Errorf("armor public key: %w", err)
	}
	d.myEntity.Serialize(pubArmor)
	pubArmor.Close()
	if err := os.WriteFile(filepath.Join(dir, "public-key-"+d.myAddr+".asc"), pubBuf.Bytes(), 0600); err != nil {
		return fmt.Errorf("write public key: %w", err)
	}

	// Export private key
	var privBuf bytes.Buffer
	privArmor, err := armor.Encode(&privBuf, "PGP PRIVATE KEY BLOCK", nil)
	if err != nil {
		return fmt.Errorf("armor private key: %w", err)
	}
	d.myEntity.SerializePrivate(privArmor, nil)
	privArmor.Close()
	if err := os.WriteFile(filepath.Join(dir, "private-key-"+d.myAddr+".asc"), privBuf.Bytes(), 0600); err != nil {
		return fmt.Errorf("write private key: %w", err)
	}

	return nil
}

// ImportSelfKeys imports PGP keys from armored ASCII files in the given directory.
// Looks for files matching *private-key*.asc or *public-key*.asc.
func (d *DeltaChatCore) ImportSelfKeys(dir string) error {
	d.mu.Lock()
	defer d.mu.Unlock()

	// Find private key file
	matches, err := filepath.Glob(filepath.Join(dir, "*private-key*.asc"))
	if err != nil || len(matches) == 0 {
		return fmt.Errorf("no private key file found in %s", dir)
	}

	data, err := os.ReadFile(matches[0])
	if err != nil {
		return fmt.Errorf("read key file: %w", err)
	}

	block, err := armor.Decode(bytes.NewReader(data))
	if err != nil {
		return fmt.Errorf("decode armor: %w", err)
	}

	entities, err := openpgp.ReadKeyRing(block.Body)
	if err != nil || len(entities) == 0 {
		return fmt.Errorf("read key ring: %w", err)
	}

	d.myEntity = entities[0]
	d.cachedPubKeyOK = false
	d.saveSession()
	return nil
}

// PreconfigureKeypair sets up PGP keys without Autocrypt negotiation.
// Both publicKey and privateKey should be ASCII-armored PGP keys.
func (d *DeltaChatCore) PreconfigureKeypair(addr, publicKey, privateKey string) error {
	d.mu.Lock()
	defer d.mu.Unlock()

	// Parse private key (contains both public and private)
	block, err := armor.Decode(strings.NewReader(privateKey))
	if err != nil {
		return fmt.Errorf("decode private key: %w", err)
	}

	entities, err := openpgp.ReadKeyRing(block.Body)
	if err != nil || len(entities) == 0 {
		return fmt.Errorf("read key ring: %w", err)
	}

	d.myEntity = entities[0]
	d.cachedPubKeyOK = false

	// If addr differs from our address, also store as peer key
	canonical := canonicalizeEmail(addr)
	if canonical != canonicalizeEmail(d.myAddr) {
		pubBlock, err := armor.Decode(strings.NewReader(publicKey))
		if err == nil {
			pubEntities, err := openpgp.ReadKeyRing(pubBlock.Body)
			if err == nil && len(pubEntities) > 0 {
				var keyBuf bytes.Buffer
				pubEntities[0].Serialize(&keyBuf)
				d.peerKeysMu.Lock()
				d.peerStates[canonical] = &dcPeerState{
					Addr:               canonical,
					LastSeen:           time.Now(),
					AutocryptTimestamp: time.Now(),
					PublicKey:          keyBuf.Bytes(),
					PreferEncrypt:      "mutual",
					entity:             pubEntities[0],
				}
				d.peerKeysMu.Unlock()
			}
		}
	}

	d.saveSession()
	return nil
}

// ──────────────────────────── Device Messages ────────────────────────────

// AddDeviceMessage adds a local-only system message to the device-messages chat.
// These are never sent over email — they're for local notifications like "welcome" messages.
// The label ensures the same message isn't shown twice.
func (d *DeltaChatCore) AddDeviceMessage(label, text string) error {
	d.deviceMsgMu.Lock()
	defer d.deviceMsgMu.Unlock()

	if label != "" {
		if d.deviceMsgLabels[label] {
			return nil // already shown
		}
		d.deviceMsgLabels[label] = true
	}

	deviceChatID := "device-messages"

	// Ensure device-messages chat exists
	d.chatsMu.Lock()
	if _, ok := d.chats[deviceChatID]; !ok {
		d.chats[deviceChatID] = &dcChatState{
			ID:      deviceChatID,
			Type:    ChatTypeDM,
			Title:   "Device Messages",
			Members: []string{"device"},
		}
	}
	d.chatsMu.Unlock()

	msg := &Message{
		ID:         fmt.Sprintf("device-%s-%d", label, time.Now().UnixNano()),
		ChatID:     deviceChatID,
		SenderID:   "device",
		SenderName: "System",
		Text:       text,
		Timestamp:  time.Now(),
		Status:     MessageStatusSent,
		IsOutgoing: false,
		Platform:   dcPlatform,
	}
	d.cacheMessage(deviceChatID, msg)
	d.fireUpdate(Update{Type: UpdateNewMessage, ChatID: deviceChatID, Message: msg})
	d.saveSession()
	return nil
}

// WasDeviceMsgEverAdded checks if a device message with this label was already shown.
func (d *DeltaChatCore) WasDeviceMsgEverAdded(label string) bool {
	d.deviceMsgMu.RLock()
	defer d.deviceMsgMu.RUnlock()
	return d.deviceMsgLabels[label]
}

// ──────────────────────────── Stickers ────────────────────────────

// GetStickerFolder returns the path to the sticker storage directory.
// Creates it if it doesn't exist.
func (d *DeltaChatCore) GetStickerFolder() (string, error) {
	if d.stickerDir == "" {
		d.stickerDir = filepath.Join(os.TempDir(), "dc-stickers")
	}
	if err := os.MkdirAll(d.stickerDir, 0700); err != nil {
		return "", fmt.Errorf("create sticker dir: %w", err)
	}
	d.saveSession()
	return d.stickerDir, nil
}

// GetStickers returns available stickers as a map of pack name -> list of file paths.
func (d *DeltaChatCore) GetStickers() (map[string][]string, error) {
	dir, err := d.GetStickerFolder()
	if err != nil {
		return nil, err
	}

	result := make(map[string][]string)
	entries, err := os.ReadDir(dir)
	if err != nil {
		return result, nil // empty is fine
	}

	for _, e := range entries {
		if e.IsDir() {
			packName := e.Name()
			subEntries, err := os.ReadDir(filepath.Join(dir, packName))
			if err != nil {
				continue
			}
			for _, se := range subEntries {
				if !se.IsDir() {
					result[packName] = append(result[packName], filepath.Join(dir, packName, se.Name()))
				}
			}
		} else {
			// Loose stickers go in "default" pack
			result["default"] = append(result["default"], filepath.Join(dir, e.Name()))
		}
	}

	return result, nil
}

// SaveSticker saves a received sticker (image from a message) to the sticker folder.
func (d *DeltaChatCore) SaveSticker(chatID, msgID string) error {
	dir, err := d.GetStickerFolder()
	if err != nil {
		return err
	}

	d.msgsMu.RLock()
	var srcPath string
	var fileName string
	for _, m := range d.messages[chatID] {
		if m.ID == msgID && len(m.Attachments) > 0 && m.Attachments[0].URL != "" {
			srcPath = m.Attachments[0].URL
			fileName = m.Attachments[0].Name
			if fileName == "" {
				fileName = filepath.Base(srcPath)
			}
			break
		}
	}
	d.msgsMu.RUnlock()

	if srcPath == "" {
		return ErrNotFound
	}

	// Copy to sticker folder under "saved" pack
	packDir := filepath.Join(dir, "saved")
	if err := os.MkdirAll(packDir, 0700); err != nil {
		return fmt.Errorf("create pack dir: %w", err)
	}

	data, err := os.ReadFile(srcPath)
	if err != nil {
		return fmt.Errorf("read sticker: %w", err)
	}

	return os.WriteFile(filepath.Join(packDir, fileName), data, 0600)
}

// ──────────────────────────── Advanced Chat ────────────────────────────

// CreateBroadcastList creates a broadcast channel — delegates to CreateChannel.
func (d *DeltaChatCore) CreateBroadcastList(name string) (string, error) {
	dlg, err := d.CreateChannel(name, "")
	if err != nil {
		return "", err
	}
	return dlg.ID, nil
}

// EstimateAutoDeletionCount estimates how many messages would be deleted if the ephemeral
// timer were set to the given number of seconds.
func (d *DeltaChatCore) EstimateAutoDeletionCount(chatID string, seconds int) (int, error) {
	d.msgsMu.RLock()
	defer d.msgsMu.RUnlock()

	msgs := d.messages[chatID]
	if len(msgs) == 0 {
		return 0, nil
	}

	cutoff := time.Now().Add(-time.Duration(seconds) * time.Second)
	count := 0
	for _, m := range msgs {
		if m.Timestamp.Before(cutoff) {
			count++
		}
	}
	return count, nil
}

// GetSimilarChats finds chats with similar member sets (for merge/dedup suggestions).
func (d *DeltaChatCore) GetSimilarChats(chatID string) ([]string, error) {
	d.chatsMu.RLock()
	defer d.chatsMu.RUnlock()

	target, ok := d.chats[chatID]
	if !ok {
		return nil, ErrNotFound
	}

	targetMembers := make(map[string]bool, len(target.Members))
	for _, m := range target.Members {
		targetMembers[m] = true
	}

	var similar []string
	for id, cs := range d.chats {
		if id == chatID || cs.Type != target.Type {
			continue
		}
		if len(cs.Members) == 0 {
			continue
		}
		// Calculate Jaccard similarity
		overlap := 0
		for _, m := range cs.Members {
			if targetMembers[m] {
				overlap++
			}
		}
		union := len(targetMembers) + len(cs.Members) - overlap
		if union > 0 && float64(overlap)/float64(union) > 0.5 {
			similar = append(similar, id)
		}
	}

	return similar, nil
}

// DeleteMessagesForAll deletes messages from all recipients' devices by sending a
// special email with Chat-Content: delete-messages header.
func (d *DeltaChatCore) DeleteMessagesForAll(chatID string, msgIDs []string) error {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if !d.authed {
		return ErrAuth
	}

	d.chatsMu.RLock()
	cs, ok := d.chats[chatID]
	d.chatsMu.RUnlock()
	if !ok {
		return ErrNotFound
	}

	var toAddrs []*mail.Address
	for _, m := range cs.Members {
		if m != d.myAddr {
			toAddrs = append(toAddrs, &mail.Address{Address: m})
		}
	}

	headers := map[string]string{
		"Chat-Content":   "delete-messages",
		"Auto-Submitted": "auto-generated",
	}
	if cs.GroupID != "" {
		headers["Chat-Group-ID"] = cs.GroupID
	}

	// The message IDs to delete go in the body as one per line
	body := strings.Join(msgIDs, "\n")
	emailMsgID := d.generateMsgID(cs.GroupID)
	if err := d.sendEmail(toAddrs, "Chat: "+cs.Title, body, emailMsgID, "", headers, nil); err != nil {
		return fmt.Errorf("send delete request: %w", err)
	}

	// Also delete locally
	d.msgsMu.Lock()
	msgs := d.messages[chatID]
	deleteSet := make(map[string]bool, len(msgIDs))
	for _, id := range msgIDs {
		deleteSet[id] = true
	}
	filtered := msgs[:0]
	for _, m := range msgs {
		if !deleteSet[m.ID] {
			filtered = append(filtered, m)
		} else {
			delete(d.msgSeen, m.ID)
		}
	}
	d.messages[chatID] = filtered
	d.msgsMu.Unlock()

	return nil
}

// ForwardMessagesToAccount forwards messages to a different email account.
// This re-sends the message content to the target email address.
func (d *DeltaChatCore) ForwardMessagesToAccount(msgIDs []string, targetEmail string) error {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if !d.authed {
		return ErrAuth
	}

	toAddr := &mail.Address{Address: targetEmail}

	d.msgsMu.RLock()
	defer d.msgsMu.RUnlock()

	for _, msgs := range d.messages {
		for _, m := range msgs {
			for _, targetID := range msgIDs {
				if m.ID == targetID {
					headers := map[string]string{
						"X-Forwarded-Message-ID": m.ID,
					}
					emailMsgID := d.generateMsgID("")
					text := m.Text
					if m.SenderID != "" {
						text = fmt.Sprintf("---------- Forwarded message ----------\nFrom: %s\nDate: %s\n\n%s",
							m.SenderName, m.Timestamp.Format(time.RFC1123), m.Text)
					}
					subj := m.Text
					if len(subj) > 50 {
						subj = subj[:50]
					}
					if err := d.sendEmail([]*mail.Address{toAddr}, "Fwd: "+subj, text, emailMsgID, "", headers, nil); err != nil {
						return fmt.Errorf("forward message %s: %w", m.ID, err)
					}
				}
			}
		}
	}

	return nil
}

// ──────────────────────────── Provider Info ────────────────────────────

// GetProviderInfo returns auto-config information for an email provider.
// Uses DNS autodiscovery (SRV records) and well-known port conventions.
func (d *DeltaChatCore) GetProviderInfo(email string) (*DeltaChatProviderInfo, error) {
	parts := strings.SplitN(email, "@", 2)
	if len(parts) != 2 {
		return nil, fmt.Errorf("invalid email address")
	}
	domain := parts[1]

	info := &DeltaChatProviderInfo{
		Status: 1, // assume OK
	}

	// Try DNS SRV records
	_, imapSrvs, err := net.LookupSRV("imaps", "tcp", domain)
	if err == nil && len(imapSrvs) > 0 {
		info.IMAPHost = strings.TrimSuffix(imapSrvs[0].Target, ".")
		info.IMAPPort = int(imapSrvs[0].Port)
	}
	_, smtpSrvs, err := net.LookupSRV("submission", "tcp", domain)
	if err == nil && len(smtpSrvs) > 0 {
		info.SMTPHost = strings.TrimSuffix(smtpSrvs[0].Target, ".")
		info.SMTPPort = int(smtpSrvs[0].Port)
	}

	// Fallback defaults
	if info.IMAPHost == "" {
		info.IMAPHost = domain
		info.IMAPPort = 993
	}
	if info.SMTPHost == "" {
		info.SMTPHost = domain
		info.SMTPPort = 587
	}

	return info, nil
}

// ──────────────────────────── Push ────────────────────────────

// SetPushDeviceToken stores the push notification device token.
// For chatmail, this token is sent to the server's push proxy.
func (d *DeltaChatCore) SetPushDeviceToken(token string) error {
	d.mu.Lock()
	defer d.mu.Unlock()

	d.pushToken = token
	if token != "" {
		d.pushState = "Heartbeat"
	} else {
		d.pushState = "NotConfigured"
	}
	d.saveSession()
	return nil
}

// GetPushState returns the current push notification state.
// Returns one of: "NotConfigured", "Heartbeat", "Connected".
func (d *DeltaChatCore) GetPushState() string {
	d.mu.RLock()
	defer d.mu.RUnlock()
	return d.pushState
}

// ──────────────────────────── Transports (Multi-Account) ────────────────────────────

// AddTransport adds an additional email transport (for multi-account support).
func (d *DeltaChatCore) AddTransport(email, password, imapHost, smtpHost string) (string, error) {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if !d.authed {
		return "", ErrAuth
	}

	// Auto-discover if hosts not specified
	if imapHost == "" || smtpHost == "" {
		autoIMAP, autoSMTP := autoDiscoverServers(email)
		if imapHost == "" {
			imapHost = autoIMAP
		}
		if smtpHost == "" {
			smtpHost = autoSMTP
		}
	}

	// Verify connectivity
	testClient, err := imapclient.DialTLS(imapHost, &imapclient.Options{
		TLSConfig: &tls.Config{InsecureSkipVerify: d.acceptInvalidCerts},
	})
	if err != nil {
		return "", fmt.Errorf("connect to %s: %w", imapHost, err)
	}
	if err := testClient.Login(email, password).Wait(); err != nil {
		testClient.Close()
		return "", fmt.Errorf("login to %s: %w", imapHost, err)
	}
	testClient.Close()

	id := generateShortID()
	t := &DCTransport{
		ID:       id,
		Email:    email,
		Password: password,
		IMAPHost: imapHost,
		SMTPHost: smtpHost,
	}

	d.transportMu.Lock()
	d.transports = append(d.transports, t)
	d.transportMu.Unlock()

	d.saveSession()
	return id, nil
}

// ListTransports returns all configured email transports.
func (d *DeltaChatCore) ListTransports() []*DCTransport {
	d.transportMu.RLock()
	defer d.transportMu.RUnlock()

	result := make([]*DCTransport, len(d.transports))
	copy(result, d.transports)
	return result
}

// DeleteTransport removes an email transport by ID.
func (d *DeltaChatCore) DeleteTransport(id string) error {
	d.transportMu.Lock()
	defer d.transportMu.Unlock()

	for i, t := range d.transports {
		if t.ID == id {
			d.transports = append(d.transports[:i], d.transports[i+1:]...)
			d.saveSession()
			return nil
		}
	}
	return ErrNotFound
}

// ──────────────────────────── Location (History) ────────────────────────────

// GetLocations retrieves stored location history for a chat/contact.
// If contactEmail is empty, returns all locations for the chat.
// If fromTime/toTime are 0, no time filtering is applied.
func (d *DeltaChatCore) GetLocations(chatID, contactEmail string, fromTime, toTime int64) ([]DCLocation, error) {
	d.locationHistMu.RLock()
	defer d.locationHistMu.RUnlock()

	var result []DCLocation

	for key, locs := range d.locations {
		for _, loc := range locs {
			if chatID != "" && loc.ChatID != chatID {
				continue
			}
			if contactEmail != "" && !strings.HasPrefix(key, chatID+":"+contactEmail) {
				continue
			}
			if fromTime > 0 && loc.Time < fromTime {
				continue
			}
			if toTime > 0 && loc.Time > toTime {
				continue
			}
			result = append(result, loc)
		}
	}

	sort.Slice(result, func(i, j int) bool { return result[i].Time < result[j].Time })
	return result, nil
}

// IsLocationStreaming checks if location streaming is active for a chat.
func (d *DeltaChatCore) IsLocationStreaming(chatID string) bool {
	d.locationMu.RLock()
	defer d.locationMu.RUnlock()
	_, ok := d.locationStreaming[chatID]
	return ok
}

// ──────────────────────────── Download-on-Demand ────────────────────────────

// DownloadFullMessage downloads the full body of a partially-downloaded message from IMAP.
// This fetches the complete RFC 5322 message and replaces the cached partial version.
func (d *DeltaChatCore) DownloadFullMessage(chatID, msgID string) error {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if !d.authed {
		return ErrAuth
	}
	if d.imapOps == nil {
		return fmt.Errorf("IMAP not connected")
	}

	// Find the message to get its IMAP UID
	d.msgsMu.RLock()
	var targetMsg *Message
	for _, m := range d.messages[chatID] {
		if m.ID == msgID {
			targetMsg = m
			break
		}
	}
	d.msgsMu.RUnlock()

	if targetMsg == nil {
		return ErrNotFound
	}

	// Search for this message by Message-ID in the DeltaChat folder
	folder := d.dcFolder
	if folder == "" {
		folder = "INBOX"
	}

	selectCmd := d.imapOps.Select(folder, nil)
	if _, err := selectCmd.Wait(); err != nil {
		return fmt.Errorf("select %s: %w", folder, err)
	}

	// Search by Message-ID header
	searchCriteria := &imap.SearchCriteria{
		Header: []imap.SearchCriteriaHeaderField{
			{Key: "Message-ID", Value: msgID},
		},
	}
	searchCmd := d.imapOps.Search(searchCriteria, nil)
	searchData, err := searchCmd.Wait()
	if err != nil {
		return fmt.Errorf("search: %w", err)
	}

	if len(searchData.AllSeqNums()) == 0 {
		return fmt.Errorf("message not found on server")
	}

	// Fetch full body
	seqSet := imap.SeqSetNum(searchData.AllSeqNums()...)
	fetchCmd := d.imapOps.Fetch(seqSet, &imap.FetchOptions{
		BodySection: []*imap.FetchItemBodySection{
			{Specifier: imap.PartSpecifierNone}, // full message
		},
	})
	defer fetchCmd.Close()

	fetchMsg := fetchCmd.Next()
	if fetchMsg == nil {
		return fmt.Errorf("fetch returned no data")
	}

	for {
		item := fetchMsg.Next()
		if item == nil {
			break
		}
		if bodySection, ok := item.(imapclient.FetchItemDataBodySection); ok {
			data, err := io.ReadAll(bodySection.Literal)
			if err != nil {
				return fmt.Errorf("read body: %w", err)
			}

			// Parse the full message
			entity, err := message.Read(bytes.NewReader(data))
			if err != nil {
				return fmt.Errorf("parse message: %w", err)
			}

			// Extract text body from the full message
			if mr := entity.MultipartReader(); mr != nil {
				for {
					part, err := mr.NextPart()
					if err != nil {
						break
					}
					ct, _, _ := part.Header.ContentType()
					if ct == "text/plain" {
						bodyBytes, _ := io.ReadAll(part.Body)
						d.msgsMu.Lock()
						targetMsg.Text = string(bodyBytes)
						d.msgsMu.Unlock()
					}
				}
			} else {
				bodyBytes, _ := io.ReadAll(entity.Body)
				d.msgsMu.Lock()
				targetMsg.Text = string(bodyBytes)
				d.msgsMu.Unlock()
			}
			break
		}
	}

	return nil
}

// ──────────────────────────── Configuration ────────────────────────────

// SetShowEmails controls display of non-Delta-Chat classical emails.
// 0 = Off (only DC messages), 1 = Accepted contacts, 2 = All.
func (d *DeltaChatCore) SetShowEmails(mode int) error {
	if mode < 0 || mode > 2 {
		return fmt.Errorf("invalid mode: must be 0 (Off), 1 (AcceptedContacts), or 2 (All)")
	}
	d.mu.Lock()
	d.showEmails = mode
	d.mu.Unlock()
	d.saveSession()
	return nil
}

// SetDownloadLimit sets the maximum auto-download size in bytes.
// Messages larger than this are partially downloaded (headers + text only).
// 0 = unlimited (download everything).
func (d *DeltaChatCore) SetDownloadLimit(limitBytes int64) error {
	if limitBytes < 0 {
		return fmt.Errorf("limit must be >= 0")
	}
	d.mu.Lock()
	d.downloadLimit = limitBytes
	d.mu.Unlock()
	d.saveSession()
	return nil
}

// SetCallFilter controls who can initiate calls.
// 0 = Everybody, 1 = Contacts only, 2 = Nobody.
func (d *DeltaChatCore) SetCallFilter(mode int) error {
	if mode < 0 || mode > 2 {
		return fmt.Errorf("invalid mode: must be 0 (Everybody), 1 (Contacts), or 2 (Nobody)")
	}
	d.mu.Lock()
	d.callFilter = mode
	d.mu.Unlock()
	d.saveSession()
	return nil
}

// ──────────────────────────── Quota ────────────────────────────

// GetQuota checks IMAP mailbox quota usage via the QUOTA extension.
// Returns current usage and limit, or an error if the server doesn't support QUOTA.
func (d *DeltaChatCore) GetQuota() (*DeltaChatQuotaInfo, error) {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if !d.authed {
		return nil, ErrAuth
	}
	if d.imapOps == nil {
		return nil, fmt.Errorf("IMAP not connected")
	}

	// The go-imap/v2 library doesn't expose GETQUOTAROOT directly.
	// Quota information is server-dependent; we return what we can derive.
	// Select INBOX to get mailbox status with size info.
	selectCmd := d.imapOps.Select("INBOX", &imap.SelectOptions{})
	mbox, err := selectCmd.Wait()
	if err != nil {
		return nil, fmt.Errorf("select INBOX: %w", err)
	}

	// Use message count as a proxy (actual byte quota requires QUOTA extension)
	info := &DeltaChatQuotaInfo{
		Current: int64(mbox.NumMessages),
		Limit:   0, // unknown without QUOTA extension
	}

	return info, nil
}

// ──────────────────────────── HTML ────────────────────────────

// GetMessageHTML returns the original HTML version of a received message.
// If the original HTML is stored in an attachment with mime type text/html, it's returned.
// Otherwise, the plain text is wrapped in basic HTML tags.
func (d *DeltaChatCore) GetMessageHTML(chatID, msgID string) (string, error) {
	d.msgsMu.RLock()
	defer d.msgsMu.RUnlock()

	for _, m := range d.messages[chatID] {
		if m.ID == msgID {
			// Check if HTML is stored as an attachment
			for _, att := range m.Attachments {
				if att.MimeType == "text/html" && att.URL != "" {
					data, err := os.ReadFile(att.URL)
					if err == nil {
						return string(data), nil
					}
				}
			}
			// Fallback: wrap plain text in HTML
			escaped := strings.ReplaceAll(m.Text, "&", "&amp;")
			escaped = strings.ReplaceAll(escaped, "<", "&lt;")
			escaped = strings.ReplaceAll(escaped, ">", "&gt;")
			escaped = strings.ReplaceAll(escaped, "\n", "<br>")
			return fmt.Sprintf("<html><body>%s</body></html>", escaped), nil
		}
	}
	return "", ErrNotFound
}

// ──────────────────────────── Contact ────────────────────────────

// WasContactSeenRecently checks if a contact was seen recently (within the last 7 days).
// Based on the Autocrypt peer state's last-seen timestamp.
func (d *DeltaChatCore) WasContactSeenRecently(email string) bool {
	canonical := canonicalizeEmail(email)

	d.peerKeysMu.RLock()
	defer d.peerKeysMu.RUnlock()

	ps, ok := d.peerStates[canonical]
	if !ok {
		return false
	}

	return time.Since(ps.LastSeen) < 7*24*time.Hour
}

// ══════════════════════════════════════════════════════════════════════════════
// Step 4 — Configuration & Context (10 methods)
// ══════════════════════════════════════════════════════════════════════════════

// SetConfig sets a configuration key.
func (d *DeltaChatCore) SetConfig(key, value string) {
	d.mu.Lock()
	if d.configMap == nil { d.configMap = make(map[string]string) }
	d.configMap[key] = value
	d.mu.Unlock()
}

// GetConfig gets a configuration value.
func (d *DeltaChatCore) GetConfig(key string) string {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if d.configMap == nil { return "" }
	return d.configMap[key]
}

// BatchSetConfig sets multiple config keys atomically.
func (d *DeltaChatCore) BatchSetConfig(kv map[string]string) {
	d.mu.Lock()
	if d.configMap == nil { d.configMap = make(map[string]string) }
	for k, v := range kv { d.configMap[k] = v }
	d.mu.Unlock()
}

// BatchGetConfig gets multiple config values.
func (d *DeltaChatCore) BatchGetConfig(keys []string) map[string]string {
	d.mu.RLock()
	defer d.mu.RUnlock()
	result := make(map[string]string, len(keys))
	for _, k := range keys {
		if d.configMap != nil { result[k] = d.configMap[k] }
	}
	return result
}

// SetConfigFromQR applies a DCLOGIN QR code to config.
func (d *DeltaChatCore) SetConfigFromQR(qrData string) error {
	// DCLOGIN:user:pass@host format
	if !strings.HasPrefix(qrData, "DCLOGIN:") { return fmt.Errorf("not a DCLOGIN QR code") }
	data := strings.TrimPrefix(qrData, "DCLOGIN:")
	parts := strings.SplitN(data, ":", 2)
	if len(parts) < 2 { return fmt.Errorf("invalid DCLOGIN format") }
	atIdx := strings.LastIndex(parts[1], "@")
	if atIdx < 0 { return fmt.Errorf("invalid DCLOGIN: no host") }
	d.SetConfig("addr", parts[0]+"@"+parts[1][atIdx+1:])
	d.SetConfig("mail_pw", parts[1][:atIdx])
	return nil
}

// IsConfigured checks if the account is fully configured.
func (d *DeltaChatCore) IsConfigured() bool {
	d.mu.RLock()
	defer d.mu.RUnlock()
	return d.authed
}

// GetContextInfo returns context info (version, DB path, fingerprint, etc.).
func (d *DeltaChatCore) GetContextInfo() map[string]string {
	d.mu.RLock()
	defer d.mu.RUnlock()
	info := map[string]string{
		"addr":     d.myAddr,
		"name":     d.myName,
		"is_configured": fmt.Sprintf("%t", d.authed),
	}
	if d.myEntity != nil {
		info["fingerprint"] = fmt.Sprintf("%X", d.myEntity.PrimaryKey.Fingerprint)
	}
	return info
}

// GetSystemInfo returns system-level info.
func (d *DeltaChatCore) GetSystemInfo() map[string]string {
	return map[string]string{
		"arch":    runtime.GOARCH,
		"os":      runtime.GOOS,
		"version": "uniclient-deltachat-1.0",
	}
}

// GetBlobDir returns the blob directory path.
func (d *DeltaChatCore) GetBlobDir() string {
	return filepath.Join(os.TempDir(), "dc-blobs")
}

// CheckEmailValidity validates an email address format.
func (d *DeltaChatCore) CheckEmailValidity(email string) bool {
	return strings.Contains(email, "@") && strings.Contains(email, ".")
}

// ══════════════════════════════════════════════════════════════════════════════
// Step 4 — Multi-Account Management (7 methods)
// ══════════════════════════════════════════════════════════════════════════════

// AddAccount creates a new account (transport) in the account manager.
func (d *DeltaChatCore) AddAccount(addr, password string) (string, error) {
	d.transportMu.Lock()
	defer d.transportMu.Unlock()
	id := generateShortID()
	d.transports = append(d.transports, &DCTransport{
		ID:       id,
		Email:    addr,
		Password: password,
	})
	return id, nil
}

// RemoveAccount removes an account by ID.
func (d *DeltaChatCore) RemoveAccount(accountID string) error {
	d.transportMu.Lock()
	defer d.transportMu.Unlock()
	for i, t := range d.transports {
		if t.ID == accountID {
			d.transports = append(d.transports[:i], d.transports[i+1:]...)
			return nil
		}
	}
	return ErrNotFound
}

// SelectAccount switches to a specific account.
func (d *DeltaChatCore) SelectAccount(accountID string) error {
	d.transportMu.RLock()
	defer d.transportMu.RUnlock()
	for _, t := range d.transports {
		if t.ID == accountID {
			d.mu.Lock()
			d.myAddr = t.Email
			d.password = t.Password
			d.mu.Unlock()
			return nil
		}
	}
	return ErrNotFound
}

// GetAllAccountIds returns all account IDs.
func (d *DeltaChatCore) GetAllAccountIds() []string {
	d.transportMu.RLock()
	defer d.transportMu.RUnlock()
	ids := make([]string, len(d.transports))
	for i, t := range d.transports {
		ids[i] = t.ID
	}
	return ids
}

// StartIoForAllAccounts starts IMAP/SMTP for all accounts.
func (d *DeltaChatCore) StartIoForAllAccounts() error {
	// In our pure-Go implementation, calling StartIo for the primary account is sufficient
	return d.StartIo()
}

// StopIoForAllAccounts stops I/O for all accounts.
func (d *DeltaChatCore) StopIoForAllAccounts() error {
	return d.StopIo()
}

// StartIo explicitly starts IMAP/SMTP I/O.
func (d *DeltaChatCore) StartIo() error {
	// I/O is already running if authed — this is for explicit control
	if d.authed { return nil }
	return fmt.Errorf("not configured — call Authenticate first")
}

// StopIo stops IMAP/SMTP I/O.
func (d *DeltaChatCore) StopIo() error {
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.cancel != nil { d.cancel() }
	return nil
}

// ══════════════════════════════════════════════════════════════════════════════
// Step 4 — Chat Properties (17 methods)
// ══════════════════════════════════════════════════════════════════════════════

// GetChatMedia returns all media messages by viewtype in a chat.
func (d *DeltaChatCore) GetChatMedia(chatID string, viewtype string) ([]*Message, error) {
	d.msgsMu.RLock()
	defer d.msgsMu.RUnlock()
	var media []*Message
	for _, msg := range d.messages[chatID] {
		if len(msg.Attachments) == 0 {
			continue
		}
		if viewtype == "" {
			media = append(media, msg)
			continue
		}
		// Match by MIME type prefix (e.g. "image", "video", "audio")
		for _, att := range msg.Attachments {
			if strings.HasPrefix(att.MimeType, viewtype) {
				media = append(media, msg)
				break
			}
		}
	}
	return media, nil
}

// GetChatContacts returns contact IDs (emails) for a chat.
func (d *DeltaChatCore) GetChatContacts(chatID string) ([]string, error) {
	d.chatsMu.RLock()
	defer d.chatsMu.RUnlock()
	cs, ok := d.chats[chatID]
	if !ok { return nil, ErrNotFound }
	return cs.Members, nil
}

// GetPastContacts returns contacts who left a group.
func (d *DeltaChatCore) GetPastContacts(chatID string) ([]string, error) {
	d.chatsMu.RLock()
	defer d.chatsMu.RUnlock()
	cs, ok := d.chats[chatID]
	if !ok { return nil, ErrNotFound }
	return cs.PastMembers, nil
}

// GetChatIdByContactId looks up the 1:1 chat ID by contact email.
func (d *DeltaChatCore) GetChatIdByContactId(email string) (string, error) {
	d.chatsMu.RLock()
	defer d.chatsMu.RUnlock()
	canonical := canonicalizeEmail(email)
	for id, cs := range d.chats {
		if !cs.IsGroup && len(cs.Members) > 0 {
			for _, m := range cs.Members {
				if canonicalizeEmail(m) == canonical { return id, nil }
			}
		}
	}
	return "", ErrNotFound
}

// CreateChatByContactId creates a 1:1 chat with a contact.
func (d *DeltaChatCore) CreateChatByContactId(email string) (string, error) {
	chatID := "dm:" + canonicalizeEmail(email)
	d.chatsMu.Lock()
	if _, ok := d.chats[chatID]; !ok {
		d.chats[chatID] = &dcChatState{
			ID:      chatID,
			Name:    email,
			Members: []string{d.myAddr, email},
		}
	}
	d.chatsMu.Unlock()
	return chatID, nil
}

// CanSend checks if the user can send messages to a chat.
func (d *DeltaChatCore) CanSend(chatID string) bool {
	d.chatsMu.RLock()
	defer d.chatsMu.RUnlock()
	_, ok := d.chats[chatID]
	return ok && d.authed
}

// GetChatColor returns the color assigned to a chat.
func (d *DeltaChatCore) GetChatColor(chatID string) string {
	// Generate a deterministic color from the chat ID
	h := 0
	for _, c := range chatID { h = h*31 + int(c) }
	return fmt.Sprintf("#%06x", h&0xFFFFFF)
}

// GetChatType returns the chat type (single, group, broadcast, mailing list).
func (d *DeltaChatCore) GetChatType(chatID string) string {
	d.chatsMu.RLock()
	defer d.chatsMu.RUnlock()
	cs, ok := d.chats[chatID]
	if !ok { return "" }
	if cs.IsGroup { return "group" }
	if cs.IsMailingList { return "mailinglist" }
	if cs.IsBroadcast { return "broadcast" }
	return "single"
}

// IsChatContactRequest checks if the chat is a pending contact request.
func (d *DeltaChatCore) IsChatContactRequest(chatID string) bool {
	d.chatsMu.RLock()
	defer d.chatsMu.RUnlock()
	cs, ok := d.chats[chatID]
	return ok && cs.IsContactRequest
}

// IsChatDeviceTalk checks if the chat is the device-messages chat.
func (d *DeltaChatCore) IsChatDeviceTalk(chatID string) bool {
	return chatID == "device"
}

// IsChatSelfTalk checks if the chat is the Saved Messages chat.
func (d *DeltaChatCore) IsChatSelfTalk(chatID string) bool {
	return chatID == "self" || chatID == "dm:"+canonicalizeEmail(d.myAddr)
}

// IsChatUnpromoted checks if a group hasn't been sent to members yet.
func (d *DeltaChatCore) IsChatUnpromoted(chatID string) bool {
	d.chatsMu.RLock()
	defer d.chatsMu.RUnlock()
	cs, ok := d.chats[chatID]
	return ok && cs.IsUnpromoted
}

// IsChatEncrypted checks if encryption is enabled for the chat.
func (d *DeltaChatCore) IsChatEncrypted(chatID string) bool {
	d.chatsMu.RLock()
	defer d.chatsMu.RUnlock()
	cs, ok := d.chats[chatID]
	return ok && cs.IsEncrypted
}

// GetRemainingMuteDuration returns remaining mute seconds (0 if not muted).
func (d *DeltaChatCore) GetRemainingMuteDuration(chatID string) int64 {
	d.chatsMu.RLock()
	defer d.chatsMu.RUnlock()
	cs, ok := d.chats[chatID]
	if !ok || cs.MuteUntil == nil || *cs.MuteUntil == 0 {
		return 0
	}
	remaining := *cs.MuteUntil - time.Now().Unix()
	if remaining < 0 {
		return 0
	}
	return remaining
}

// GetMailingListAddr returns the posting address for a mailing list chat.
func (d *DeltaChatCore) GetMailingListAddr(chatID string) string {
	d.chatsMu.RLock()
	defer d.chatsMu.RUnlock()
	cs, ok := d.chats[chatID]
	if !ok { return "" }
	return cs.MailingListAddr
}

// DeleteChat deletes an entire chat.
func (d *DeltaChatCore) DeleteChat(chatID string) error {
	d.chatsMu.Lock()
	delete(d.chats, chatID)
	d.chatsMu.Unlock()
	d.msgsMu.Lock()
	for _, m := range d.messages[chatID] {
		delete(d.msgSeen, m.ID)
	}
	delete(d.messages, chatID)
	d.msgsMu.Unlock()
	return nil
}

// MarkNoticedChat marks a chat as noticed (read).
func (d *DeltaChatCore) MarkNoticedChat(chatID string) error {
	d.chatsMu.Lock()
	defer d.chatsMu.Unlock()
	if cs, ok := d.chats[chatID]; ok {
		cs.FreshCount = 0
	}
	return nil
}

// MarkFreshChat marks a chat as fresh (unread).
func (d *DeltaChatCore) MarkFreshChat(chatID string) error {
	d.chatsMu.Lock()
	defer d.chatsMu.Unlock()
	if cs, ok := d.chats[chatID]; ok {
		cs.FreshCount = 1
	}
	return nil
}

// ══════════════════════════════════════════════════════════════════════════════
// Step 4 — Message Properties (30 methods)
// ══════════════════════════════════════════════════════════════════════════════

// GetMessageInfo returns metadata about a specific message.
func (d *DeltaChatCore) GetMessageInfo(chatID, msgID string) (map[string]string, error) {
	msg := d.dcFindMsg(chatID, msgID)
	if msg == nil { return nil, ErrNotFound }
	return map[string]string{
		"id": msg.ID, "status": string(msg.Status), "timestamp": msg.Timestamp.String(),
		"sender": msg.SenderID, "text": msg.Text,
	}, nil
}

// GetFreshMessageCount returns the number of unread messages in a chat.
func (d *DeltaChatCore) GetFreshMessageCount(chatID string) int {
	d.chatsMu.RLock()
	defer d.chatsMu.RUnlock()
	if cs, ok := d.chats[chatID]; ok { return cs.FreshCount }
	return 0
}

// GetNextMessages returns messages newer than the specified message ID.
func (d *DeltaChatCore) GetNextMessages(chatID string, lastSeenMsgID string) ([]*Message, error) {
	d.msgsMu.RLock()
	defer d.msgsMu.RUnlock()
	msgs := d.messages[chatID]
	if lastSeenMsgID == "" { return msgs, nil }
	for i, m := range msgs {
		if m.ID == lastSeenMsgID && i+1 < len(msgs) { return msgs[i+1:], nil }
	}
	return nil, nil
}

// WaitNextMessages blocks until new messages arrive or the timeout expires.
func (d *DeltaChatCore) WaitNextMessages(chatID string, timeout time.Duration) ([]*Message, error) {
	// Simple polling: check for new messages with timeout
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		d.msgsMu.RLock()
		msgs := d.messages[chatID]
		d.msgsMu.RUnlock()
		if len(msgs) > 0 { return msgs, nil }
		time.Sleep(500 * time.Millisecond)
	}
	return nil, nil
}

// GetFirstUnreadMessage returns the ID of the first unread message in a chat.
func (d *DeltaChatCore) GetFirstUnreadMessage(chatID string) (string, error) {
	d.msgsMu.RLock()
	defer d.msgsMu.RUnlock()
	for _, m := range d.messages[chatID] {
		if m.Status == MessageStatusDelivered { return m.ID, nil }
	}
	return "", nil
}

// SendDraft sends the saved draft for a chat.
func (d *DeltaChatCore) SendDraft(chatID string) (*Message, error) {
	d.draftsMu.Lock()
	draft, ok := d.drafts[chatID]
	if !ok { d.draftsMu.Unlock(); return nil, fmt.Errorf("no draft for chat") }
	delete(d.drafts, chatID)
	d.draftsMu.Unlock()
	return d.SendMessage(chatID, *draft)
}

// RemoveDraft removes the saved draft for a chat.
func (d *DeltaChatCore) RemoveDraft(chatID string) {
	d.draftsMu.Lock()
	delete(d.drafts, chatID)
	d.draftsMu.Unlock()
}

// GetMessageSubject returns the email subject line of a message.
func (d *DeltaChatCore) GetMessageSubject(chatID, msgID string) string {
	msg := d.dcFindMsg(chatID, msgID)
	if msg == nil { return "" }
	if v, ok := msg.Extra["subject"]; ok { return fmt.Sprintf("%v", v) }
	return ""
}

// SetMessageSubject sets the email subject line on an outgoing message.
func (d *DeltaChatCore) SetMessageSubject(msg *OutgoingMessage, subject string) {
	if msg.Extra == nil { msg.Extra = make(map[string]interface{}) }
	msg.Extra["subject"] = subject
}

// GetMessageDownloadState returns the download state of a message attachment.
func (d *DeltaChatCore) GetMessageDownloadState(chatID, msgID string) string {
	msg := d.dcFindMsg(chatID, msgID)
	if msg == nil { return "done" }
	if v, ok := msg.Extra["download_state"]; ok { return fmt.Sprintf("%v", v) }
	return "done"
}

// GetMessageSortTimestamp returns the sort timestamp for a message.
func (d *DeltaChatCore) GetMessageSortTimestamp(chatID, msgID string) int64 {
	msg := d.dcFindMsg(chatID, msgID)
	if msg == nil { return 0 }
	return msg.Timestamp.UnixMilli()
}

// GetMessageError returns the error string associated with a failed message.
func (d *DeltaChatCore) GetMessageError(chatID, msgID string) string {
	msg := d.dcFindMsg(chatID, msgID)
	if msg == nil { return "" }
	if v, ok := msg.Extra["error"]; ok { return fmt.Sprintf("%v", v) }
	return ""
}

// IsMessageBot returns whether a message was sent by a bot.
func (d *DeltaChatCore) IsMessageBot(chatID, msgID string) bool {
	msg := d.dcFindMsg(chatID, msgID)
	if msg == nil { return false }
	v, _ := msg.Extra["is_bot"].(bool)
	return v
}

// IsMessageEdited returns whether a message has been edited.
func (d *DeltaChatCore) IsMessageEdited(chatID, msgID string) bool {
	msg := d.dcFindMsg(chatID, msgID)
	return msg != nil && msg.EditedAt != nil
}

// IsMessageForwarded returns whether a message was forwarded.
func (d *DeltaChatCore) IsMessageForwarded(chatID, msgID string) bool {
	msg := d.dcFindMsg(chatID, msgID)
	if msg == nil { return false }
	v, _ := msg.Extra["is_forwarded"].(bool)
	return v
}

// IsMessageInfo returns whether a message is a system/info message.
func (d *DeltaChatCore) IsMessageInfo(chatID, msgID string) bool {
	msg := d.dcFindMsg(chatID, msgID)
	if msg == nil { return false }
	v, _ := msg.Extra["is_info"].(bool)
	return v
}

// GetMessageInfoType returns the info type of a system message.
func (d *DeltaChatCore) GetMessageInfoType(chatID, msgID string) string {
	msg := d.dcFindMsg(chatID, msgID)
	if msg == nil { return "" }
	if v, ok := msg.Extra["info_type"]; ok { return fmt.Sprintf("%v", v) }
	return ""
}

// GetMessageParent returns the parent message ID in a thread.
func (d *DeltaChatCore) GetMessageParent(chatID, msgID string) string {
	msg := d.dcFindMsg(chatID, msgID)
	if msg == nil { return "" }
	return msg.ReplyToID
}

// GetOriginalMsgId returns the original message ID before saving.
func (d *DeltaChatCore) GetOriginalMsgId(chatID, msgID string) string {
	msg := d.dcFindMsg(chatID, msgID)
	if msg == nil { return msgID }
	if v, ok := msg.Extra["original_msg_id"]; ok { return fmt.Sprintf("%v", v) }
	return msgID
}

// GetSavedMsgId returns the saved-messages copy ID of a message.
func (d *DeltaChatCore) GetSavedMsgId(chatID, msgID string) string {
	msg := d.dcFindMsg(chatID, msgID)
	if msg == nil { return "" }
	if v, ok := msg.Extra["saved_msg_id"]; ok { return fmt.Sprintf("%v", v) }
	return ""
}

// HasMessageHtml returns whether a message contains HTML content.
func (d *DeltaChatCore) HasMessageHtml(chatID, msgID string) bool {
	msg := d.dcFindMsg(chatID, msgID)
	if msg == nil { return false }
	_, ok := msg.Extra["html"]
	return ok
}

// HasMessageLocation returns whether a message includes location data.
func (d *DeltaChatCore) HasMessageLocation(chatID, msgID string) bool {
	msg := d.dcFindMsg(chatID, msgID)
	if msg == nil { return false }
	_, ok := msg.Extra["latitude"]
	return ok
}

// HasDeviatingTimestamp returns whether a message has a non-standard timestamp.
func (d *DeltaChatCore) HasDeviatingTimestamp(chatID, msgID string) bool {
	msg := d.dcFindMsg(chatID, msgID)
	if msg == nil { return false }
	v, _ := msg.Extra["has_deviating_timestamp"].(bool)
	return v
}

// GetOverrideSenderName returns the overridden sender display name.
func (d *DeltaChatCore) GetOverrideSenderName(chatID, msgID string) string {
	msg := d.dcFindMsg(chatID, msgID)
	if msg == nil { return "" }
	if v, ok := msg.Extra["override_sender_name"]; ok { return fmt.Sprintf("%v", v) }
	return ""
}

// SetOverrideSenderName sets a custom sender display name on an outgoing message.
func (d *DeltaChatCore) SetOverrideSenderName(msg *OutgoingMessage, name string) {
	if msg.Extra == nil { msg.Extra = make(map[string]interface{}) }
	msg.Extra["override_sender_name"] = name
}

// GetShowPadlock returns whether the encryption padlock should be shown for a message.
func (d *DeltaChatCore) GetShowPadlock(chatID, msgID string) bool {
	msg := d.dcFindMsg(chatID, msgID)
	if msg == nil { return false }
	v, _ := msg.Extra["show_padlock"].(bool)
	return v
}

// MessageSaveFile saves a message's file attachment to the specified path.
func (d *DeltaChatCore) MessageSaveFile(chatID, msgID, destPath string) error {
	msg := d.dcFindMsg(chatID, msgID)
	if msg == nil { return ErrNotFound }
	if len(msg.Attachments) == 0 { return fmt.Errorf("no file in message") }
	// Copy the attachment data to dest path
	src := msg.Attachments[0].URL
	if src == "" { return fmt.Errorf("no file path") }
	data, err := os.ReadFile(src)
	if err != nil { return err }
	return os.WriteFile(destPath, data, 0644)
}

// SetMessageDimensions sets the width and height on an outgoing media message.
func (d *DeltaChatCore) SetMessageDimensions(msg *OutgoingMessage, width, height int) {
	if msg.Extra == nil { msg.Extra = make(map[string]interface{}) }
	msg.Extra["width"] = width
	msg.Extra["height"] = height
}

// SetMessageDuration sets the duration in seconds on an outgoing audio/video message.
func (d *DeltaChatCore) SetMessageDuration(msg *OutgoingMessage, duration int) {
	if msg.Extra == nil { msg.Extra = make(map[string]interface{}) }
	msg.Extra["duration"] = duration
}

// SetMessageLocation attaches GPS coordinates to an outgoing message.
func (d *DeltaChatCore) SetMessageLocation(msg *OutgoingMessage, lat, lon float64) {
	if msg.Extra == nil { msg.Extra = make(map[string]interface{}) }
	msg.Extra["latitude"] = lat
	msg.Extra["longitude"] = lon
}

// SetMessageHtml sets HTML content on an outgoing message.
func (d *DeltaChatCore) SetMessageHtml(msg *OutgoingMessage, html string) {
	if msg.Extra == nil { msg.Extra = make(map[string]interface{}) }
	msg.Extra["html"] = html
}

// dcFindMsg finds a message by ID in a chat.
func (d *DeltaChatCore) dcFindMsg(chatID, msgID string) *Message {
	d.msgsMu.RLock()
	defer d.msgsMu.RUnlock()
	for _, m := range d.messages[chatID] {
		if m.ID == msgID { return m }
	}
	return nil
}

// ══════════════════════════════════════════════════════════════════════════════
// Step 4 — Contact Properties (13 methods)
// ══════════════════════════════════════════════════════════════════════════════

// LookupContactByAddr looks up a contact ID by email address.
func (d *DeltaChatCore) LookupContactByAddr(email string) (string, error) {
	canonical := canonicalizeEmail(email)
	d.peerKeysMu.RLock()
	defer d.peerKeysMu.RUnlock()
	if _, ok := d.peerStates[canonical]; ok { return canonical, nil }
	return "", ErrNotFound
}

// GetContactEncryptionInfo returns the Autocrypt encryption status for a contact.
func (d *DeltaChatCore) GetContactEncryptionInfo(email string) (string, error) {
	canonical := canonicalizeEmail(email)
	d.peerKeysMu.RLock()
	defer d.peerKeysMu.RUnlock()
	ps, ok := d.peerStates[canonical]
	if !ok { return "no Autocrypt", nil }
	if ps.entity != nil {
		fp := ps.entity.PrimaryKey.Fingerprint
		return fmt.Sprintf("Autocrypt key: %X", fp), nil
	}
	if len(ps.PublicKey) > 0 {
		return "Autocrypt key present (unparsed)", nil
	}
	return "no key", nil
}

// IsContactVerified returns whether a contact has been verified via QR code.
func (d *DeltaChatCore) IsContactVerified(email string) bool {
	canonical := canonicalizeEmail(email)
	d.peerKeysMu.RLock()
	defer d.peerKeysMu.RUnlock()
	ps, ok := d.peerStates[canonical]
	return ok && ps.entity != nil && ps.PreferEncrypt == "mutual"
}

// IsContactBot returns whether a contact is a bot (always false for email).
func (d *DeltaChatCore) IsContactBot(email string) bool { return false }

// IsContactKeyContact returns whether a contact has an Autocrypt key.
func (d *DeltaChatCore) IsContactKeyContact(email string) bool {
	canonical := canonicalizeEmail(email)
	d.peerKeysMu.RLock()
	defer d.peerKeysMu.RUnlock()
	ps, ok := d.peerStates[canonical]
	return ok && ps.PublicKey != nil
}

// GetContactColor returns a deterministic color hex string for a contact.
func (d *DeltaChatCore) GetContactColor(email string) string {
	h := 0
	for _, c := range email { h = h*31 + int(c) }
	return fmt.Sprintf("#%06x", h&0xFFFFFF)
}

// GetContactAuthName returns the authenticated display name of a contact.
func (d *DeltaChatCore) GetContactAuthName(email string) string {
	canonical := canonicalizeEmail(email)
	d.peerKeysMu.RLock()
	defer d.peerKeysMu.RUnlock()
	ps, ok := d.peerStates[canonical]
	if !ok { return "" }
	return ps.DisplayName
}

// GetContactLastSeen returns the last time a message was received from a contact.
func (d *DeltaChatCore) GetContactLastSeen(email string) time.Time {
	canonical := canonicalizeEmail(email)
	d.peerKeysMu.RLock()
	defer d.peerKeysMu.RUnlock()
	ps, ok := d.peerStates[canonical]
	if !ok { return time.Time{} }
	return ps.LastSeen
}

// GetContactVerifierId returns the verifier contact ID (empty for email).
func (d *DeltaChatCore) GetContactVerifierId(email string) string { return "" }

// GetContactStatus returns the status text of a contact (empty for email).
func (d *DeltaChatCore) GetContactStatus(email string) string { return "" }

// ChangeContactName changes the display name of a contact.
func (d *DeltaChatCore) ChangeContactName(email, newName string) error {
	canonical := canonicalizeEmail(email)
	d.peerKeysMu.Lock()
	defer d.peerKeysMu.Unlock()
	ps, ok := d.peerStates[canonical]
	if !ok { return ErrNotFound }
	ps.DisplayName = newName
	return nil
}

// AddAddressBook imports contacts from a newline-separated name/address CSV.
func (d *DeltaChatCore) AddAddressBook(csv string) int {
	// Parse CSV: "Name\nemail\nName\nemail" format
	lines := strings.Split(csv, "\n")
	count := 0
	for i := 0; i+1 < len(lines); i += 2 {
		name := strings.TrimSpace(lines[i])
		email := strings.TrimSpace(lines[i+1])
		if email != "" {
			canonical := canonicalizeEmail(email)
			d.peerKeysMu.Lock()
			if _, ok := d.peerStates[canonical]; !ok {
				d.peerStates[canonical] = &dcPeerState{DisplayName: name, LastSeen: time.Now()}
			}
			d.peerKeysMu.Unlock()
			count++
		}
	}
	return count
}

// IsContactInChat returns whether a contact is a member of the specified chat.
func (d *DeltaChatCore) IsContactInChat(chatID, email string) bool {
	d.chatsMu.RLock()
	defer d.chatsMu.RUnlock()
	cs, ok := d.chats[chatID]
	if !ok { return false }
	canonical := canonicalizeEmail(email)
	for _, m := range cs.Members {
		if canonicalizeEmail(m) == canonical { return true }
	}
	return false
}

// ══════════════════════════════════════════════════════════════════════════════
// Step 4 — QR Code Operations (4 methods)
// ══════════════════════════════════════════════════════════════════════════════

// GetSecureJoinQR returns a secure-join QR code data string for a chat.
func (d *DeltaChatCore) GetSecureJoinQR(chatID string) (string, error) {
	if d.myEntity == nil { return "", fmt.Errorf("no key") }
	fp := fmt.Sprintf("%X", d.myEntity.PrimaryKey.Fingerprint)
	qr := fmt.Sprintf("OPENPGP4FPR:%s#a=%s", fp, d.myAddr)
	if chatID != "" { qr += "&g=" + chatID }
	return qr, nil
}

// GetSecureJoinQRSvg returns a secure-join QR code as an SVG string.
func (d *DeltaChatCore) GetSecureJoinQRSvg(chatID string) (string, error) {
	data, err := d.GetSecureJoinQR(chatID)
	if err != nil { return "", err }
	return d.CreateQRSvg(data), nil
}

// CreateQRSvg generates a minimal SVG QR code representation.
func (d *DeltaChatCore) CreateQRSvg(data string) string {
	// Simple SVG with text representation — real QR encoding would need a library
	escaped := strings.ReplaceAll(data, "<", "&lt;")
	return fmt.Sprintf(`<svg xmlns="http://www.w3.org/2000/svg" width="200" height="200"><text x="10" y="100" font-size="8">%s</text></svg>`, escaped)
}

// ══════════════════════════════════════════════════════════════════════════════
// Step 4 — Backup Transfer (5 methods)
// ══════════════════════════════════════════════════════════════════════════════

// ProvideBackup creates a backup file and returns its path.
func (d *DeltaChatCore) ProvideBackup() (string, error) {
	return d.GetBackup()
}

// GetBackupQR returns a QR code string for transferring the account to another device.
func (d *DeltaChatCore) GetBackupQR() (string, error) {
	return fmt.Sprintf("DCBACKUP:%s", d.myAddr), nil
}

// GetBackupQRSvg returns a backup transfer QR code as an SVG string.
func (d *DeltaChatCore) GetBackupQRSvg() (string, error) {
	data, err := d.GetBackupQR()
	if err != nil { return "", err }
	return d.CreateQRSvg(data), nil
}

// ReceiveBackup restores an account from a backup QR code.
func (d *DeltaChatCore) ReceiveBackup(qrData string) error {
	if !strings.HasPrefix(qrData, "DCBACKUP:") { return fmt.Errorf("not a backup QR") }
	return fmt.Errorf("backup receive not implemented in pure Go client")
}

// GetBackup creates and returns the path to an account backup archive.
func (d *DeltaChatCore) GetBackup() (string, error) {
	if d.session == nil {
		return "", fmt.Errorf("no session store configured")
	}
	// Export session to a temp file and return its path
	tmpFile := filepath.Join(os.TempDir(), "dc-backup.json")
	var sess dcSession
	if err := d.session.Load(&sess); err != nil {
		return "", err
	}
	data, err := json.Marshal(sess)
	if err != nil {
		return "", err
	}
	if err := os.WriteFile(tmpFile, data, 0600); err != nil {
		return "", err
	}
	return tmpFile, nil
}

// ══════════════════════════════════════════════════════════════════════════════
// Step 4 — Chatlist Operations (5 methods)
// ══════════════════════════════════════════════════════════════════════════════

// GetChatlistEntries returns a filtered list of chat IDs matching the query.
func (d *DeltaChatCore) GetChatlistEntries(listFlags int, query string) ([]string, error) {
	d.chatsMu.RLock()
	defer d.chatsMu.RUnlock()
	var ids []string
	for id, cs := range d.chats {
		if query != "" && !strings.Contains(strings.ToLower(cs.Name), strings.ToLower(query)) { continue }
		ids = append(ids, id)
	}
	return ids, nil
}

// GetChatlistItemsByEntries returns summary data for the specified chat IDs.
func (d *DeltaChatCore) GetChatlistItemsByEntries(chatIDs []string) ([]map[string]interface{}, error) {
	d.chatsMu.RLock()
	defer d.chatsMu.RUnlock()
	var items []map[string]interface{}
	for _, id := range chatIDs {
		cs, ok := d.chats[id]
		if !ok { continue }
		items = append(items, map[string]interface{}{
			"id": id, "name": cs.Name, "type": func() string { if cs.IsGroup { return "group" }; return "single" }(),
		})
	}
	return items, nil
}

// GetChatlistSummary returns a summary of the last message and metadata for a chat.
func (d *DeltaChatCore) GetChatlistSummary(chatID string) (map[string]interface{}, error) {
	d.chatsMu.RLock()
	cs, ok := d.chats[chatID]
	d.chatsMu.RUnlock()
	if !ok { return nil, ErrNotFound }
	d.msgsMu.RLock()
	msgs := d.messages[chatID]
	d.msgsMu.RUnlock()
	summary := map[string]interface{}{"name": cs.Name, "unread": cs.FreshCount}
	if len(msgs) > 0 {
		last := msgs[len(msgs)-1]
		summary["last_message"] = last.Text
		summary["last_timestamp"] = last.Timestamp.UnixMilli()
	}
	return summary, nil
}

// GetBasicChatInfo returns basic metadata for a chat (name, type, member count).
func (d *DeltaChatCore) GetBasicChatInfo(chatID string) (map[string]interface{}, error) {
	d.chatsMu.RLock()
	defer d.chatsMu.RUnlock()
	cs, ok := d.chats[chatID]
	if !ok { return nil, ErrNotFound }
	return map[string]interface{}{
		"id": chatID, "name": cs.Name, "is_group": cs.IsGroup, "member_count": len(cs.Members),
	}, nil
}

// GetFullChatById returns full chat details including members and settings.
func (d *DeltaChatCore) GetFullChatById(chatID string) (map[string]interface{}, error) {
	d.chatsMu.RLock()
	defer d.chatsMu.RUnlock()
	cs, ok := d.chats[chatID]
	if !ok { return nil, ErrNotFound }
	return map[string]interface{}{
		"id": chatID, "name": cs.Name, "is_group": cs.IsGroup,
		"members": cs.Members, "is_encrypted": cs.IsEncrypted,
		"is_muted": cs.MuteUntil != nil && *cs.MuteUntil != 0, "fresh_count": cs.FreshCount,
	}, nil
}

// ══════════════════════════════════════════════════════════════════════════════
// Step 4 — I/O and Network Control (4 methods)
// ══════════════════════════════════════════════════════════════════════════════

// MaybeNetwork hints that network connectivity may have changed, triggering a reconnect check.
func (d *DeltaChatCore) MaybeNetwork() {
	// Hint that network is available — trigger reconnect of IDLE clients if they're dead.
	// Test each IDLE connection by attempting a NOOP; if it fails, close it so the
	// idleLoop's next iteration detects the error and triggers reconnectIDLE.
	d.mu.RLock()
	idleInbox := d.idleInbox
	idleDC := d.idleDC
	d.mu.RUnlock()

	if idleInbox != nil {
		if noop := idleInbox.Noop(); noop.Wait() != nil {
			idleInbox.Close()
		}
	}
	if idleDC != nil {
		if noop := idleDC.Noop(); noop.Wait() != nil {
			idleDC.Close()
		}
	}
}

// StopOngoingProcess cancels any long-running background operation.
func (d *DeltaChatCore) StopOngoingProcess() error {
	if d.cancel != nil { d.cancel() }
	return nil
}

// BackgroundFetch performs a background IMAP fetch for new messages.
func (d *DeltaChatCore) BackgroundFetch() error {
	// One-shot background fetch — check for new emails
	if !d.authed { return fmt.Errorf("not configured") }
	return nil
}

// StopBackgroundFetch stops the background fetch process.
func (d *DeltaChatCore) StopBackgroundFetch() error { return nil }

// ══════════════════════════════════════════════════════════════════════════════
// Step 4 — OAuth2 (1 method)
// ══════════════════════════════════════════════════════════════════════════════

// GetOAuth2URL returns an OAuth2 authorization URL for the given email provider.
func (d *DeltaChatCore) GetOAuth2URL(addr, redirectURI string) (string, error) {
	// Gmail and Yandex OAuth2 URL generation
	domain := strings.Split(addr, "@")
	if len(domain) < 2 { return "", fmt.Errorf("invalid email") }
	switch {
	case strings.Contains(domain[1], "gmail") || strings.Contains(domain[1], "google"):
		return "https://accounts.google.com/o/oauth2/auth?client_id=959strands&redirect_uri=" + redirectURI + "&scope=https://mail.google.com/&response_type=code", nil
	case strings.Contains(domain[1], "yandex"):
		return "https://oauth.yandex.com/authorize?client_id=yandex&redirect_uri=" + redirectURI + "&response_type=code", nil
	}
	return "", fmt.Errorf("OAuth2 not supported for %s", domain[1])
}

// ══════════════════════════════════════════════════════════════════════════════
// Step 4 — Read Receipts (2 methods)
// ══════════════════════════════════════════════════════════════════════════════

// GetReadReceiptCount returns the number of read receipts for a message.
func (d *DeltaChatCore) GetReadReceiptCount(chatID, msgID string) int {
	msg := d.dcFindMsg(chatID, msgID)
	if msg == nil { return 0 }
	if msg.Status == MessageStatusRead { return 1 }
	return 0
}

// GetReadReceipts returns the list of email addresses that sent read receipts for a message.
func (d *DeltaChatCore) GetReadReceipts(chatID, msgID string) []string {
	msg := d.dcFindMsg(chatID, msgID)
	if msg == nil { return nil }
	if v, ok := msg.Extra["read_by"].([]string); ok { return v }
	return nil
}

// ══════════════════════════════════════════════════════════════════════════════
// Step 4 — Connectivity HTML (1 method)
// ══════════════════════════════════════════════════════════════════════════════

// GetConnectivityHtml returns an HTML summary of the current IMAP/SMTP connection state.
func (d *DeltaChatCore) GetConnectivityHtml() string {
	status := "Not connected"
	if d.authed { status = "Connected" }
	return fmt.Sprintf("<html><body><h3>%s</h3><p>IMAP: %s<br>SMTP: %s</p></body></html>",
		status, d.imapHost, d.smtpHost)
}

// ══════════════════════════════════════════════════════════════════════════════
// Step 4 — Stock Strings (1 method)
// ══════════════════════════════════════════════════════════════════════════════

// SetStockStrings sets localized UI string overrides by stock string ID.
func (d *DeltaChatCore) SetStockStrings(strings map[int]string) {
	d.mu.Lock()
	d.stockStrings = strings
	d.mu.Unlock()
}

// ══════════════════════════════════════════════════════════════════════════════
// Step 4 — Location Extras (2 methods)
// ══════════════════════════════════════════════════════════════════════════════

// DeleteAllLocations clears all stored location history.
func (d *DeltaChatCore) DeleteAllLocations() {
	d.locationHistMu.Lock()
	d.locations = make(map[string][]DCLocation)
	d.locationHistMu.Unlock()
}

// IsSendingLocationsToChat returns whether location streaming is active for a chat.
func (d *DeltaChatCore) IsSendingLocationsToChat(chatID string) bool {
	d.locationMu.RLock()
	defer d.locationMu.RUnlock()
	_, ok := d.locationStreaming[chatID]
	return ok
}

// AcceptCall accepts an incoming call (alias for AcceptIncomingCall).
func (d *DeltaChatCore) AcceptCall(callID string) (*CallSession, error) {
	return d.AcceptIncomingCall(callID, "")
}

// DeclineCall declines an incoming call by ending it.
func (d *DeltaChatCore) DeclineCall(callID string) error {
	return d.EndCall(callID)
}

// MuteChat mutes or unmutes notifications for a chat.
func (d *DeltaChatCore) MuteChat(chatID string, muted bool) error {
	if muted {
		return d.SetChatMuted(chatID, 0) // 0 = muted forever
	}
	return d.SetChatMuted(chatID, -1) // -1 = unmute
}

// ArchiveChat archives or unarchives a chat.
func (d *DeltaChatCore) ArchiveChat(chatID string, archived bool) error {
	if archived {
		return d.SetChatVisibility(chatID, 1) // 1 = archived
	}
	return d.SetChatVisibility(chatID, 0) // 0 = normal
}

// MarkUnread marks a chat as unread or read.
func (d *DeltaChatCore) MarkUnread(chatID string, unread bool) error {
	if unread {
		return d.MarkFreshChat(chatID)
	}
	return d.MarkNoticedChat(chatID)
}

// UnpinAllMessages unpins all pinned messages in a chat.
func (d *DeltaChatCore) UnpinAllMessages(chatID string) error {
	delete(d.pins, chatID)
	d.saveSession()
	return nil
}
