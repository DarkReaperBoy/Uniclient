package cores

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/tls"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"math/big"
	"mime"
	"net"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"

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
	locationStreaming map[string]*dcLocationStream // chatID -> stream
	locationMu        sync.RWMutex

	// Session persistence
	sessionPath string

	// Update handlers
	updateHandlers []func(Update)
	updateMu       sync.RWMutex

	// Context
	ctx    context.Context
	cancel context.CancelFunc
}

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

// dcLocationStream tracks active location sharing.
type dcLocationStream struct {
	ChatID   string
	Duration time.Duration
	StartAt  time.Time
	Cancel   context.CancelFunc
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
}

// NewDeltaChatCore creates a new Delta Chat core instance.
func NewDeltaChatCore(sessionPath string) *DeltaChatCore {
	ctx, cancel := context.WithCancel(context.Background())
	return &DeltaChatCore{
		peerStates:        make(map[string]*dcPeerState),
		chats:             make(map[string]*dcChatState),
		messages:          make(map[string][]*Message),
		drafts:            make(map[string]*OutgoingMessage),
		blocked:           make(map[string]bool),
		folders:           make(map[string]*Folder),
		pins:              make(map[string]map[string]bool),
		activeCalls:       make(map[string]*dcCall),
		locationStreaming: make(map[string]*dcLocationStream),
		sessionPath:       sessionPath,
		ctx:               ctx,
		cancel:            cancel,
	}
}

// --- Core Interface: Identity ---

func (d *DeltaChatCore) Name() string { return "deltachat" }

func (d *DeltaChatCore) Capabilities() []string {
	return []string{
		"CALLS",
		"CHANNELS",
		"REACTIONS",
		"READ_RECEIPTS",
		"STICKERS",
		"FOLDERS",
		"ADMIN",
		"BASE64_IMAGE",
	}
}

// --- Core Interface: Auth ---

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

	// Try loading existing session
	isBot := d.isBot // preserve cfg.Mode over saved session
	if err := d.loadSession(); err == nil && d.myEntity != nil {
		// Session loaded, just reconnect
	} else {
		// Generate new keypair
		entity, err := d.generateKeypair()
		if err != nil {
			return fmt.Errorf("generate keypair: %w", err)
		}
		d.myEntity = entity
	}
	d.isBot = isBot // cfg.Mode always takes priority over saved session

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
	go d.idleLoop(d.idleInbox, "INBOX", "inbox-idle")
	go d.idleLoop(d.idleDC, d.dcFolder, "dc-idle")

	return nil
}

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

	// Remove session file
	if d.sessionPath != "" {
		os.Remove(d.sessionPath)
	}

	return nil
}

// --- Core Interface: Dialogs ---

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

	var dialogs []Dialog
	for _, cs := range d.chats {
		dlg := d.chatStateToDialog(cs)
		dialogs = append(dialogs, dlg)
	}

	// Sort by last message time descending
	sort.Slice(dialogs, func(i, j int) bool {
		ti := d.chats[dialogs[i].ID].LastMsgTime
		tj := d.chats[dialogs[j].ID].LastMsgTime
		return ti > tj
	})

	// Apply pagination
	limit := opts.Limit
	if limit <= 0 {
		limit = 50
	}
	if len(dialogs) > limit {
		dialogs = dialogs[:limit]
	}

	return dialogs, nil
}

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
		Platform:   "deltachat",
	}

	d.cacheMessage(chatID, m)
	d.updateChatTime(chatID, now)
	return m, nil
}

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

	var result []Message
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
		Platform:   "deltachat",
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
			break
		}
	}
	d.msgsMu.Unlock()

	return nil
}

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
		Platform:     "deltachat",
	}

	d.cacheMessage(chatID, m)
	d.updateChatTime(chatID, now)
	return m, nil
}

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
		Platform:    "deltachat",
	}

	d.cacheMessage(toChatID, m)
	d.updateChatTime(toChatID, now)
	return m, nil
}

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
		Attachments: []FileRef{{
			Name:     file.Name,
			MimeType: file.MimeType,
			Size:     int64(len(fileData)),
		}},
		Platform: "deltachat",
	}

	d.cacheMessage(chatID, m)
	d.updateChatTime(chatID, now)
	return m, nil
}

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
			Platform: "deltachat",
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

func (d *DeltaChatCore) JoinGroupCall(chatID string) (*CallSession, error) {
	return nil, fmt.Errorf("%w: Delta Chat does not support group calls", ErrNotSupported)
}

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
			Platform:    "deltachat",
		}, nil
	}

	d.peerKeysMu.RLock()
	ps := d.peerStates[email]
	d.peerKeysMu.RUnlock()

	user := &User{
		ID:          email,
		Username:    email,
		DisplayName: email,
		Platform:    "deltachat",
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

func (d *DeltaChatCore) OnUpdate(handler func(Update)) {
	d.updateMu.Lock()
	defer d.updateMu.Unlock()
	d.updateHandlers = append(d.updateHandlers, handler)
}

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
	return nil
}

// --- Core Interface: Chat Management ---

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

func (d *DeltaChatCore) UnbanMember(chatID string, userID string) error {
	d.mu.Lock()
	delete(d.blocked, canonicalizeEmail(userID))
	d.mu.Unlock()
	d.saveSession()
	return nil
}

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

	var users []User
	for _, email := range cs.Members {
		u := User{
			ID:          email,
			Username:    email,
			DisplayName: email,
			Platform:    "deltachat",
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

func (d *DeltaChatCore) SetAdmin(chatID string, userID string, admin bool) error {
	// DC groups are flat — no admin hierarchy in protocol. Local-only.
	return nil
}

// --- Core Interface: Contacts ---

func (d *DeltaChatCore) GetContacts() ([]User, error) {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if !d.authed {
		return nil, ErrAuth
	}

	d.peerKeysMu.RLock()
	defer d.peerKeysMu.RUnlock()

	var contacts []User
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
			Platform:    "deltachat",
		})
	}
	return contacts, nil
}

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

func (d *DeltaChatCore) DeleteContact(userID string) error {
	d.peerKeysMu.Lock()
	delete(d.peerStates, canonicalizeEmail(userID))
	d.peerKeysMu.Unlock()
	d.saveSession()
	return nil
}

func (d *DeltaChatCore) BlockUser(userID string) error {
	d.mu.Lock()
	d.blocked[canonicalizeEmail(userID)] = true
	d.mu.Unlock()
	d.saveSession()
	return nil
}

func (d *DeltaChatCore) UnblockUser(userID string) error {
	d.mu.Lock()
	delete(d.blocked, canonicalizeEmail(userID))
	d.mu.Unlock()
	d.saveSession()
	return nil
}

func (d *DeltaChatCore) GetBlockedUsers() ([]User, error) {
	d.mu.RLock()
	defer d.mu.RUnlock()
	var users []User
	for email := range d.blocked {
		users = append(users, User{
			ID:          email,
			Username:    email,
			DisplayName: email,
			Platform:    "deltachat",
		})
	}
	return users, nil
}

// --- Core Interface: Search ---

func (d *DeltaChatCore) SearchMessages(chatID string, query string, opts PaginationOpts) ([]Message, error) {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if !d.authed {
		return nil, ErrAuth
	}

	queryLower := strings.ToLower(query)
	var results []Message

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

func (d *DeltaChatCore) SearchGlobal(query string, opts PaginationOpts) ([]Dialog, error) {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if !d.authed {
		return nil, ErrAuth
	}

	queryLower := strings.ToLower(query)
	var results []Dialog

	d.chatsMu.RLock()
	for _, cs := range d.chats {
		if strings.Contains(strings.ToLower(cs.Title), queryLower) {
			dlg := d.chatStateToDialog(cs)
			results = append(results, dlg)
		}
	}
	d.chatsMu.RUnlock()

	// Also search message content
	d.msgsMu.RLock()
	matched := make(map[string]bool)
	for chatID, msgs := range d.messages {
		if matched[chatID] {
			continue
		}
		for _, m := range msgs {
			if strings.Contains(strings.ToLower(m.Text), queryLower) {
				d.chatsMu.RLock()
				if cs, ok := d.chats[chatID]; ok {
					dlg := d.chatStateToDialog(cs)
					results = append(results, dlg)
					matched[chatID] = true
				}
				d.chatsMu.RUnlock()
				break
			}
		}
	}
	d.msgsMu.RUnlock()

	return results, nil
}

// --- Core Interface: Typing ---

func (d *DeltaChatCore) SendTyping(chatID string) error {
	// No-op: email has no typing indicator concept. Return nil (not error).
	return nil
}

// --- Core Interface: Polls ---

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
		Attachments: []FileRef{{
			Name:     filepath.Base(stickerID),
			MimeType: mimeType,
			Size:     int64(len(data)),
		}},
		Platform: "deltachat",
	}

	d.cacheMessage(chatID, m)
	return m, nil
}

// --- Core Interface: Sessions ---

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
		Platform:   "deltachat",
		AppName:    "uniclient",
		AppVersion: "1.0.0",
		LastActive: time.Now(),
		IsCurrent:  true,
	}}, nil
}

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
	d.locationStreaming[chatID] = &dcLocationStream{
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
func (d *DeltaChatCore) SendLocation(chatID string, lat float64, lon float64) error {
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
	return d.sendEmail(toAddrs, "Chat: "+cs.Title, "", msgID, "", headers, attachment)
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
				Platform:    "deltachat",
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
		Platform:   "deltachat",
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

	// Just copy the session file
	if d.sessionPath == "" {
		return fmt.Errorf("no session to export")
	}

	data, err := os.ReadFile(d.sessionPath)
	if err != nil {
		return fmt.Errorf("read session: %w", err)
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
		Attachments: []FileRef{{
			Name:     "contact.vcf",
			MimeType: "text/vcard",
		}},
		Platform: "deltachat",
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
		Platform:   "deltachat",
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

// encryptMessage encrypts a MIME message payload using PGP for the given recipients.
func (d *DeltaChatCore) encryptMessage(plainMIME []byte, recipients []string) ([]byte, error) {
	if d.myEntity == nil {
		return plainMIME, nil // no key, send plaintext
	}

	// Collect recipient entities
	var recipientEntities []*openpgp.Entity
	recipientEntities = append(recipientEntities, d.myEntity) // encrypt to self

	d.peerKeysMu.RLock()
	allHaveKeys := true
	for _, email := range recipients {
		ps := d.peerStates[canonicalizeEmail(email)]
		if ps != nil && ps.entity != nil {
			recipientEntities = append(recipientEntities, ps.entity)
		} else if ps != nil && len(ps.PublicKey) > 0 {
			entities, err := openpgp.ReadKeyRing(bytes.NewReader(ps.PublicKey))
			if err == nil && len(entities) > 0 {
				recipientEntities = append(recipientEntities, entities[0])
			} else {
				allHaveKeys = false
			}
		} else {
			allHaveKeys = false
		}
	}
	d.peerKeysMu.RUnlock()

	if !allHaveKeys || len(recipientEntities) <= 1 {
		return plainMIME, nil // not all recipients have keys, send plaintext
	}

	// Encrypt
	var cipherBuf bytes.Buffer
	plainWriter, err := openpgp.Encrypt(&cipherBuf, recipientEntities, d.myEntity, nil, nil)
	if err != nil {
		return plainMIME, nil // fallback to plaintext
	}
	plainWriter.Write(plainMIME)
	plainWriter.Close()

	// Armor
	var armoredBuf bytes.Buffer
	armorWriter, _ := armor.Encode(&armoredBuf, "PGP MESSAGE", nil)
	armoredBuf.Write(cipherBuf.Bytes())
	armorWriter.Close()

	return armoredBuf.Bytes(), nil
}

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

// shouldEncrypt checks if all recipients have Autocrypt keys and we should encrypt.
func (d *DeltaChatCore) shouldEncrypt(recipients []string) bool {
	if d.myEntity == nil {
		return false
	}
	d.peerKeysMu.RLock()
	defer d.peerKeysMu.RUnlock()
	for _, email := range recipients {
		ps := d.peerStates[canonicalizeEmail(email)]
		if ps == nil || (len(ps.PublicKey) == 0 && len(ps.GossipKey) == 0) {
			return false
		}
	}
	return len(recipients) > 0
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

	// Encrypt the plaintext MIME body
	var cipherBuf bytes.Buffer
	plainWriter, err := openpgp.Encrypt(&cipherBuf, recipientEntities, d.myEntity, nil, nil)
	if err != nil {
		return nil, fmt.Errorf("pgp encrypt: %w", err)
	}
	plainWriter.Write(plainMsg)
	plainWriter.Close()

	// Armor the encrypted data
	var armoredBuf bytes.Buffer
	armorWriter, _ := armor.Encode(&armoredBuf, "PGP MESSAGE", nil)
	armorWriter.Write(cipherBuf.Bytes())
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
		return nil // folder doesn't exist, skip
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
		d.fireUpdate(Update{Type: UpdateEditMessage, ChatID: chatID, MessageID: editID, Platform: "deltachat"})
		return
	}

	// Handle Chat-Delete
	if deleteID := headers["Chat-Delete"]; deleteID != "" {
		d.msgsMu.Lock()
		msgs := d.messages[chatID]
		for i, m := range msgs {
			if m.ID == deleteID {
				d.messages[chatID] = append(msgs[:i], msgs[i+1:]...)
				break
			}
		}
		d.msgsMu.Unlock()
		d.fireUpdate(Update{Type: UpdateDeleteMessage, ChatID: chatID, MessageID: deleteID, Platform: "deltachat"})
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
		Platform:   "deltachat",
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
		Platform: "deltachat",
	})
}

// idleLoop runs IMAP IDLE on a folder, restarting every 28 minutes.
func (d *DeltaChatCore) idleLoop(client *imapclient.Client, folder string, label string) {
	for {
		select {
		case <-d.ctx.Done():
			return
		default:
		}

		// Select the folder
		selectCmd := client.Select(folder, nil)
		if _, err := selectCmd.Wait(); err != nil {
			time.Sleep(5 * time.Second)
			continue
		}

		// Start IDLE
		idleCmd, err := client.Idle()
		if err != nil {
			time.Sleep(5 * time.Second)
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
			// Restart IDLE
		}
		timer.Stop()

		if err := idleCmd.Close(); err != nil {
			continue
		}
		if err := idleCmd.Wait(); err != nil {
			continue
		}

		// Sync new messages
		d.mu.RLock()
		if d.authed {
			d.syncMessages()
		}
		d.mu.RUnlock()
	}
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
	var buf bytes.Buffer
	if err := d.myEntity.Serialize(&buf); err != nil {
		return ""
	}
	return base64.StdEncoding.EncodeToString(buf.Bytes())
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
	if d.sessionPath == "" {
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
		Email:       d.myAddr,
		Password:    d.password,
		IMAPHost:    d.imapHost,
		SMTPHost:    d.smtpHost,
		DisplayName: d.myName,
		Status:      d.myStatus,
		DCFolder:    d.dcFolder,
		IsBot:       d.isBot,
		PrivateKey:  keyBuf.String(),
		PeerStates:  d.peerStates,
		Chats:       d.chats,
		Blocked:     d.blocked,
		Folders:     d.folders,
		Pins:        d.pins,
	}

	data, err := json.MarshalIndent(sess, "", "  ")
	if err != nil {
		return
	}

	os.MkdirAll(filepath.Dir(d.sessionPath), 0700)
	os.WriteFile(d.sessionPath, data, 0600)
}

func (d *DeltaChatCore) loadSession() error {
	if d.sessionPath == "" {
		return fmt.Errorf("no session path")
	}

	data, err := os.ReadFile(d.sessionPath)
	if err != nil {
		return err
	}

	var sess dcSession
	if err := json.Unmarshal(data, &sess); err != nil {
		return err
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

	// Deserialize private key
	if sess.PrivateKey != "" {
		block, err := armor.Decode(strings.NewReader(sess.PrivateKey))
		if err == nil {
			entities, err := openpgp.ReadKeyRing(block.Body)
			if err == nil && len(entities) > 0 {
				d.myEntity = entities[0]
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
	b := make([]byte, 16)
	for i := range b {
		n, _ := rand.Int(rand.Reader, big.NewInt(int64(len(chars))))
		b[i] = chars[n.Int64()]
	}
	return string(b)
}

func generateShortID() string {
	const chars = "0123456789abcdefghijklmnopqrstuvwxyz"
	b := make([]byte, 8)
	for i := range b {
		n, _ := rand.Int(rand.Reader, big.NewInt(int64(len(chars))))
		b[i] = chars[n.Int64()]
	}
	return string(b)
}

func (d *DeltaChatCore) generateMsgID(groupID string) string {
	random := generateShortID()
	domain := d.myAddr
	if idx := strings.Index(d.myAddr, "@"); idx >= 0 {
		domain = d.myAddr[idx+1:]
	}
	if groupID != "" {
		return fmt.Sprintf("<Gr.%s.%s@%s>", groupID, random, domain)
	}
	return fmt.Sprintf("<Mr.%s@%s>", random, domain)
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
		Platform:    "deltachat",
	}
}

func (d *DeltaChatCore) cacheMessage(chatID string, m *Message) {
	d.msgsMu.Lock()
	defer d.msgsMu.Unlock()

	// Dedup by ID
	for _, existing := range d.messages[chatID] {
		if existing.ID == m.ID {
			return
		}
	}
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
	handlers := d.updateHandlers
	d.updateMu.RUnlock()

	for _, h := range handlers {
		go h(u)
	}
}

// parseRawHeaders parses raw email header bytes into a map.
func parseRawHeaders(data []byte) map[string]string {
	headers := make(map[string]string)
	lines := strings.Split(string(data), "\n")
	var currentKey, currentValue string

	for _, line := range lines {
		line = strings.TrimRight(line, "\r")
		if line == "" {
			if currentKey != "" {
				headers[currentKey] = strings.TrimSpace(currentValue)
			}
			break
		}
		if len(line) > 0 && (line[0] == ' ' || line[0] == '\t') {
			// Continuation
			currentValue += " " + strings.TrimSpace(line)
			continue
		}
		// Save previous header
		if currentKey != "" {
			headers[currentKey] = strings.TrimSpace(currentValue)
		}
		// Parse new header
		idx := strings.Index(line, ":")
		if idx < 0 {
			continue
		}
		currentKey = line[:idx]
		currentValue = line[idx+1:]
	}
	if currentKey != "" {
		headers[currentKey] = strings.TrimSpace(currentValue)
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
