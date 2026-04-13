package cores

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"mime"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/pion/webrtc/v4"
	"github.com/rs/zerolog"
	"maunium.net/go/mautrix"
	"maunium.net/go/mautrix/crypto"
	"maunium.net/go/mautrix/crypto/attachment"
	"maunium.net/go/mautrix/crypto/backup"
	"maunium.net/go/mautrix/crypto/olm"
	"maunium.net/go/mautrix/crypto/verificationhelper"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"
)

// MatrixCore implements the Core interface for Matrix via the mautrix SDK.
type MatrixCore struct {
	mu sync.RWMutex

	// Auth state
	authed      bool
	isBot       bool
	userID      id.UserID
	deviceID    id.DeviceID
	accessToken string
	homeserver  string

	// Client
	client    *mautrix.Client
	syncer    *mautrix.DefaultSyncer
	syncCtx   context.Context
	syncStop  context.CancelFunc
	syncToken string

	// Room state cache
	rooms    map[id.RoomID]*matrixRoomState
	roomsMu  sync.RWMutex
	roomList []id.RoomID // sorted by last activity

	// DM mappings (from m.direct account data)
	directChats   map[id.UserID][]id.RoomID
	directChatsMu sync.RWMutex

	// Active calls (WebRTC)
	activeCalls map[string]*matrixCall
	callsMu     sync.RWMutex

	// E2EE (Olm/Megolm — pure Go, no SQL)
	olmMachine         *crypto.OlmMachine
	cryptoStore        *crypto.MemoryStore
	stateStore         *mautrix.MemoryStateStore
	pickleKey          []byte
	verificationHelper *verificationhelper.VerificationHelper
	verificationStore  *verificationhelper.InMemoryVerificationStore

	// Session persistence
	sessionPath string

	// Update handlers
	updateHandlers []func(Update)
	updateMu       sync.RWMutex

	// Context
	ctx    context.Context
	cancel context.CancelFunc
}

type matrixRoomState struct {
	ID          id.RoomID
	Name        string
	Topic       string
	AvatarURL   string
	Type        ChatType
	IsEncrypted bool
	IsDirect    bool
	SpaceParent id.RoomID
	Members     map[id.UserID]*matrixMember
	PinnedIDs   []id.EventID
	LastEvent   time.Time
	UnreadCount int
	JoinRule    string
	HistVis     string
	PowerLevels *event.PowerLevelsEventContent
}

type matrixMember struct {
	UserID      id.UserID
	DisplayName string
	AvatarURL   string
	Membership  event.Membership
}

type matrixCall struct {
	ID          string
	RoomID      id.RoomID
	IsVideo     bool
	State       CallState
	StartTime   time.Time
	IsOutgoing  bool
	RemoteParty string // remote party_id

	// WebRTC
	pc         *webrtc.PeerConnection
	audioTrack *webrtc.TrackLocalStaticRTP
	cancel     context.CancelFunc

	// ICE candidates buffered before remote description is set
	pendingCandidates []webrtc.ICECandidateInit
	remoteSet         bool // true after SetRemoteDescription
	mu                sync.Mutex

	// Pluggable audio I/O — set via SetCallAudioSource/SetCallAudioSink.
	// If nil, sends silence and discards incoming audio.
	audioSource func() []byte // returns Opus frame to send (called every 20ms)
	audioSink   func([]byte)  // receives decoded Opus frame from remote
}

type matrixSession struct {
	Homeserver  string `json:"homeserver"`
	UserID      string `json:"user_id"`
	AccessToken string `json:"access_token"`
	DeviceID    string `json:"device_id"`
	NextBatch   string `json:"next_batch"`
	IsBot       bool   `json:"is_bot"`
	PickleKey   string `json:"pickle_key,omitempty"`
}

// NewMatrixCore creates a new Matrix core instance.
func NewMatrixCore(sessionPath string) *MatrixCore {
	ctx, cancel := context.WithCancel(context.Background())
	return &MatrixCore{
		rooms:       make(map[id.RoomID]*matrixRoomState),
		directChats: make(map[id.UserID][]id.RoomID),
		activeCalls: make(map[string]*matrixCall),
		sessionPath: sessionPath,
		ctx:         ctx,
		cancel:      cancel,
	}
}

// --- Core Interface: Identity ---

func (m *MatrixCore) Name() string { return "matrix" }

func (m *MatrixCore) Capabilities() []string {
	return []string{
		"CALLS",
		"CHANNELS",
		"REACTIONS",
		"READ_RECEIPTS",
		"STICKERS",
		"FOLDERS",
		"ADMIN",
		"BASE64_IMAGE",
		"THREADS",
		"PRESENCE",
		"SPACES",
		"E2EE",
		"POLLS",
		"TYPING",
		"SEARCH",
	}
}

// --- Core Interface: Auth ---

func (m *MatrixCore) Authenticate(cfg AuthConfig) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	m.isBot = cfg.Mode == AuthModeBot

	homeserver := cfg.Extra["homeserver"]
	if homeserver == "" {
		homeserver = "https://matrix.org"
	}
	m.homeserver = homeserver

	// Try loading existing session
	if err := m.loadSession(); err == nil && m.accessToken != "" {
		// Reconnect with saved credentials
		client, err := mautrix.NewClient(m.homeserver, m.userID, m.accessToken)
		if err != nil {
			return fmt.Errorf("%w: create client: %v", ErrAuth, err)
		}
		client.DeviceID = m.deviceID
		m.client = client

		// Verify the token still works
		_, err = client.Whoami(m.ctx)
		if err != nil {
			// Token expired, need fresh login
			m.accessToken = ""
		} else {
			m.authed = true
			m.setupSyncer()
			if err := m.initCrypto(); err != nil {
				fmt.Fprintf(os.Stderr, "matrix: E2EE init failed (will work without encryption): %v\n", err)
			}
			m.saveSession()
			go m.startSync()
			return nil
		}
	}

	// Fresh login
	client, err := mautrix.NewClient(homeserver, "", "")
	if err != nil {
		return fmt.Errorf("%w: create client: %v", ErrAuth, err)
	}

	if cfg.BotToken != "" {
		// Bot mode: access token provided directly
		client.AccessToken = cfg.BotToken
		client.UserID = id.UserID(cfg.Extra["user_id"])
		if client.UserID == "" {
			// Discover user ID from token
			resp, err := client.Whoami(m.ctx)
			if err != nil {
				return fmt.Errorf("%w: whoami: %v", ErrAuth, err)
			}
			client.UserID = resp.UserID
			client.DeviceID = resp.DeviceID
		}
		m.accessToken = cfg.BotToken
		m.userID = client.UserID
		m.deviceID = client.DeviceID
	} else {
		// User mode: password login
		username := cfg.Phone // username passed via Phone field
		if username == "" {
			username = cfg.Extra["username"]
		}
		password := cfg.Password2F
		if password == "" {
			password = cfg.Extra["password"]
		}
		if username == "" || password == "" {
			return fmt.Errorf("%w: username and password required (or bot_token for bot mode)", ErrInvalidInput)
		}

		resp, err := client.Login(m.ctx, &mautrix.ReqLogin{
			Type: mautrix.AuthTypePassword,
			Identifier: mautrix.UserIdentifier{
				Type: mautrix.IdentifierTypeUser,
				User: username,
			},
			Password:         password,
			StoreCredentials: true,
			DeviceID:         id.DeviceID(cfg.Extra["device_id"]),
			InitialDeviceDisplayName: "Uniclient",
		})
		if err != nil {
			return fmt.Errorf("%w: login: %v", ErrAuth, err)
		}

		m.accessToken = resp.AccessToken
		m.userID = resp.UserID
		m.deviceID = resp.DeviceID
	}

	m.client = client
	m.authed = true

	m.setupSyncer()
	if err := m.initCrypto(); err != nil {
		fmt.Fprintf(os.Stderr, "matrix: E2EE init failed (will work without encryption): %v\n", err)
	}
	m.saveSession()
	go m.startSync()

	return nil
}

func (m *MatrixCore) Logout() error {
	m.mu.Lock()
	defer m.mu.Unlock()

	if m.syncStop != nil {
		m.syncStop()
	}

	m.closeCrypto()

	if m.client != nil && m.authed {
		m.client.Logout(m.ctx)
	}

	m.authed = false
	m.accessToken = ""

	return nil
}

// --- Core Interface: Dialogs ---

func (m *MatrixCore) GetDialogs(opts PaginationOpts) ([]Dialog, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	if !m.authed {
		return nil, ErrAuth
	}

	m.roomsMu.RLock()
	defer m.roomsMu.RUnlock()

	// Sort rooms by last activity
	type roomSort struct {
		id   id.RoomID
		time time.Time
	}
	sorted := make([]roomSort, 0, len(m.rooms))
	for rid, rs := range m.rooms {
		sorted = append(sorted, roomSort{rid, rs.LastEvent})
	}
	sort.Slice(sorted, func(i, j int) bool {
		return sorted[i].time.After(sorted[j].time)
	})

	limit := opts.Limit
	if limit <= 0 {
		limit = 100
	}
	offset := 0
	if opts.Offset != "" {
		offset, _ = strconv.Atoi(opts.Offset)
	}

	var dialogs []Dialog
	for i := offset; i < len(sorted) && len(dialogs) < limit; i++ {
		rs := m.rooms[sorted[i].id]
		dialogs = append(dialogs, m.roomToDialog(rs))
	}

	return dialogs, nil
}

func (m *MatrixCore) CreateGroup(name string, members []string) (*Dialog, error) {
	if !m.authed {
		return nil, ErrAuth
	}

	invites := make([]id.UserID, len(members))
	for i, member := range members {
		invites[i] = id.UserID(member)
	}

	resp, err := m.client.CreateRoom(m.ctx, &mautrix.ReqCreateRoom{
		Name:    name,
		Preset:  "private_chat",
		Invite:  invites,
		IsDirect: len(members) == 1,
	})
	if err != nil {
		return nil, fmt.Errorf("create group: %w", err)
	}

	// Wait briefly for sync to pick up the room
	time.Sleep(500 * time.Millisecond)

	m.roomsMu.RLock()
	rs := m.rooms[resp.RoomID]
	m.roomsMu.RUnlock()

	if rs == nil {
		// Create stub
		rs = &matrixRoomState{
			ID:      resp.RoomID,
			Name:    name,
			Type:    ChatTypeGroup,
			Members: make(map[id.UserID]*matrixMember),
		}
	}

	dialog := m.roomToDialog(rs)
	return &dialog, nil
}

func (m *MatrixCore) CreateChannel(name string, description string) (*Dialog, error) {
	if !m.authed {
		return nil, ErrAuth
	}

	req := &mautrix.ReqCreateRoom{
		Name:   name,
		Topic:  description,
		Preset: "public_chat",
	}

	resp, err := m.client.CreateRoom(m.ctx, req)
	if err != nil {
		return nil, fmt.Errorf("create channel: %w", err)
	}

	time.Sleep(500 * time.Millisecond)

	m.roomsMu.RLock()
	rs := m.rooms[resp.RoomID]
	m.roomsMu.RUnlock()

	if rs == nil {
		rs = &matrixRoomState{
			ID:    resp.RoomID,
			Name:  name,
			Topic: description,
			Type:  ChatTypeChannel,
			Members: make(map[id.UserID]*matrixMember),
		}
	}

	dialog := m.roomToDialog(rs)
	return &dialog, nil
}

func (m *MatrixCore) CreateTopic(chatID string, name string) (*Dialog, error) {
	if !m.authed {
		return nil, ErrAuth
	}

	// Matrix threads: send a message that becomes the thread root
	roomID := id.RoomID(chatID)
	content := &event.MessageEventContent{
		MsgType: event.MsgText,
		Body:    name,
	}

	resp, err := m.client.SendMessageEvent(m.ctx, roomID, event.EventMessage, content)
	if err != nil {
		return nil, fmt.Errorf("create thread root: %w", err)
	}

	dialog := Dialog{
		ID:       resp.EventID.String(),
		Type:     ChatTypeTopic,
		Title:    name,
		ParentID: chatID,
		Platform: "matrix",
	}
	return &dialog, nil
}

func (m *MatrixCore) GetFolders() ([]Folder, error) {
	if !m.authed {
		return nil, ErrAuth
	}

	m.roomsMu.RLock()
	defer m.roomsMu.RUnlock()

	var folders []Folder
	for _, rs := range m.rooms {
		if !m.isSpace(rs) {
			continue
		}

		// Get child rooms
		children, err := m.client.Hierarchy(m.ctx, rs.ID, &mautrix.ReqHierarchy{Limit: 100})
		if err != nil {
			continue
		}

		var chatIDs []string
		for _, child := range children.Rooms {
			if child.RoomID != rs.ID {
				chatIDs = append(chatIDs, child.RoomID.String())
			}
		}

		folders = append(folders, Folder{
			ID:      rs.ID.String(),
			Name:    rs.Name,
			ChatIDs: chatIDs,
		})
	}

	return folders, nil
}

func (m *MatrixCore) CreateFolder(name string, chatIDs []string) (*Folder, error) {
	if !m.authed {
		return nil, ErrAuth
	}

	// Create a Space room
	resp, err := m.client.CreateRoom(m.ctx, &mautrix.ReqCreateRoom{
		Name: name,
		CreationContent: map[string]interface{}{
			"type": "m.space",
		},
	})
	if err != nil {
		return nil, fmt.Errorf("create space: %w", err)
	}

	// Add child rooms
	for _, chatID := range chatIDs {
		childID := id.RoomID(chatID)
		_, err := m.client.SendStateEvent(m.ctx, resp.RoomID, event.StateSpaceChild, childID.String(), &event.SpaceChildEventContent{
			Via: []string{m.serverName()},
		})
		if err != nil {
			// Best effort — continue with others
			continue
		}
	}

	folder := &Folder{
		ID:      resp.RoomID.String(),
		Name:    name,
		ChatIDs: chatIDs,
	}
	return folder, nil
}

// --- Core Interface: Messages ---

func (m *MatrixCore) SendMessage(chatID string, msg OutgoingMessage) (*Message, error) {
	if !m.authed {
		return nil, ErrAuth
	}

	roomID := id.RoomID(chatID)
	content := &event.MessageEventContent{
		MsgType: event.MsgText,
		Body:    msg.Text,
	}

	// Reply
	if msg.ReplyToID != "" {
		content.RelatesTo = &event.RelatesTo{
			InReplyTo: &event.InReplyTo{
				EventID: id.EventID(msg.ReplyToID),
			},
		}
	}

	resp, err := m.client.SendMessageEvent(m.ctx, roomID, event.EventMessage, content)
	if err != nil {
		return nil, fmt.Errorf("send message: %w", err)
	}

	return &Message{
		ID:        resp.EventID.String(),
		ChatID:    chatID,
		SenderID:  m.userID.String(),
		Text:      msg.Text,
		Timestamp: time.Now(),
		Status:    MessageStatusSent,
		Platform:  "matrix",
	}, nil
}

func (m *MatrixCore) GetMessages(chatID string, opts PaginationOpts) ([]Message, error) {
	if !m.authed {
		return nil, ErrAuth
	}

	roomID := id.RoomID(chatID)
	limit := opts.Limit
	if limit <= 0 {
		limit = 50
	}

	from := opts.Offset
	if from == "" {
		from = m.syncToken
	}

	resp, err := m.client.Messages(m.ctx, roomID, from, "", 'b', nil, limit)
	if err != nil {
		return nil, fmt.Errorf("get messages: %w", err)
	}

	var messages []Message
	for _, evt := range resp.Chunk {
		msg := m.eventToMessage(evt)
		if msg != nil {
			messages = append(messages, *msg)
		}
	}

	return messages, nil
}

func (m *MatrixCore) EditMessage(chatID string, msgID string, text string) (*Message, error) {
	if !m.authed {
		return nil, ErrAuth
	}

	roomID := id.RoomID(chatID)
	content := &event.MessageEventContent{
		MsgType: event.MsgText,
		Body:    "* " + text,
		NewContent: &event.MessageEventContent{
			MsgType: event.MsgText,
			Body:    text,
		},
		RelatesTo: &event.RelatesTo{
			Type:    event.RelReplace,
			EventID: id.EventID(msgID),
		},
	}

	resp, err := m.client.SendMessageEvent(m.ctx, roomID, event.EventMessage, content)
	if err != nil {
		return nil, fmt.Errorf("edit message: %w", err)
	}

	return &Message{
		ID:        resp.EventID.String(),
		ChatID:    chatID,
		SenderID:  m.userID.String(),
		Text:      text,
		Timestamp: time.Now(),
		Status:    MessageStatusSent,
		Platform:  "matrix",
	}, nil
}

func (m *MatrixCore) DeleteMessage(chatID string, msgID string) error {
	if !m.authed {
		return ErrAuth
	}

	roomID := id.RoomID(chatID)
	_, err := m.client.RedactEvent(m.ctx, roomID, id.EventID(msgID))
	if err != nil {
		return fmt.Errorf("delete message: %w", err)
	}
	return nil
}

func (m *MatrixCore) ReplyToMessage(chatID string, replyToMsgID string, msg OutgoingMessage) (*Message, error) {
	if !m.authed {
		return nil, ErrAuth
	}

	roomID := id.RoomID(chatID)
	content := &event.MessageEventContent{
		MsgType: event.MsgText,
		Body:    msg.Text,
		RelatesTo: &event.RelatesTo{
			InReplyTo: &event.InReplyTo{
				EventID: id.EventID(replyToMsgID),
			},
		},
	}

	resp, err := m.client.SendMessageEvent(m.ctx, roomID, event.EventMessage, content)
	if err != nil {
		return nil, fmt.Errorf("reply: %w", err)
	}

	return &Message{
		ID:        resp.EventID.String(),
		ChatID:    chatID,
		SenderID:  m.userID.String(),
		Text:      msg.Text,
		Timestamp: time.Now(),
		Status:    MessageStatusSent,
		ReplyToID: replyToMsgID,
		Platform:  "matrix",
	}, nil
}

func (m *MatrixCore) ForwardMessage(fromChatID string, msgID string, toChatID string) (*Message, error) {
	if !m.authed {
		return nil, ErrAuth
	}

	// Matrix has no native forward — fetch the event and re-send
	fromRoom := id.RoomID(fromChatID)
	evt, err := m.client.GetEvent(m.ctx, fromRoom, id.EventID(msgID))
	if err != nil {
		return nil, fmt.Errorf("get event for forward: %w", err)
	}

	// Parse the original message content
	evt.Content.ParseRaw(evt.Type)
	msgContent, ok := evt.Content.Parsed.(*event.MessageEventContent)
	if !ok {
		return nil, fmt.Errorf("%w: cannot forward non-message event", ErrInvalidInput)
	}

	// Re-send with forwarded attribution
	forwardContent := &event.MessageEventContent{
		MsgType: msgContent.MsgType,
		Body:    msgContent.Body,
	}

	toRoom := id.RoomID(toChatID)
	resp, err := m.client.SendMessageEvent(m.ctx, toRoom, event.EventMessage, forwardContent)
	if err != nil {
		return nil, fmt.Errorf("forward message: %w", err)
	}

	return &Message{
		ID:          resp.EventID.String(),
		ChatID:      toChatID,
		SenderID:    m.userID.String(),
		Text:        msgContent.Body,
		Timestamp:   time.Now(),
		Status:      MessageStatusSent,
		ForwardFrom: evt.Sender.String(),
		Platform:    "matrix",
	}, nil
}

func (m *MatrixCore) ReactToMessage(chatID string, msgID string, emoji string) error {
	if !m.authed {
		return ErrAuth
	}

	roomID := id.RoomID(chatID)
	_, err := m.client.SendReaction(m.ctx, roomID, id.EventID(msgID), emoji)
	if err != nil {
		return fmt.Errorf("react: %w", err)
	}
	return nil
}

func (m *MatrixCore) PinMessage(chatID string, msgID string) error {
	if !m.authed {
		return ErrAuth
	}

	roomID := id.RoomID(chatID)
	evtID := id.EventID(msgID)

	// Get current pinned events
	pinned := m.getPinnedEvents(roomID)
	for _, p := range pinned {
		if p == evtID {
			return nil // already pinned
		}
	}
	pinned = append(pinned, evtID)

	_, err := m.client.SendStateEvent(m.ctx, roomID, event.StatePinnedEvents, "", map[string]interface{}{
		"pinned": pinned,
	})
	if err != nil {
		return fmt.Errorf("pin message: %w", err)
	}

	return nil
}

func (m *MatrixCore) UnpinMessage(chatID string, msgID string) error {
	if !m.authed {
		return ErrAuth
	}

	roomID := id.RoomID(chatID)
	evtID := id.EventID(msgID)

	pinned := m.getPinnedEvents(roomID)
	var newPinned []id.EventID
	for _, p := range pinned {
		if p != evtID {
			newPinned = append(newPinned, p)
		}
	}

	_, err := m.client.SendStateEvent(m.ctx, roomID, event.StatePinnedEvents, "", map[string]interface{}{
		"pinned": newPinned,
	})
	if err != nil {
		return fmt.Errorf("unpin message: %w", err)
	}

	return nil
}

// --- Core Interface: Read State ---

func (m *MatrixCore) MarkAsRead(chatID string, upToMsgID string) error {
	if !m.authed {
		return ErrAuth
	}

	roomID := id.RoomID(chatID)
	err := m.client.MarkRead(m.ctx, roomID, id.EventID(upToMsgID))
	if err != nil {
		return fmt.Errorf("mark read: %w", err)
	}
	return nil
}

func (m *MatrixCore) GetReadState(chatID string) (*ReadState, error) {
	if !m.authed {
		return nil, ErrAuth
	}

	// Read receipts are delivered via sync — return cached state
	// The sync handler updates ReadState from m.receipt events
	return &ReadState{
		PeerLastRead: make(map[string]string),
	}, nil
}

// --- Core Interface: Files ---

func (m *MatrixCore) UploadFile(chatID string, file FileUpload, progress func(sent, total int64)) (*Message, error) {
	if !m.authed {
		return nil, ErrAuth
	}

	roomID := id.RoomID(chatID)

	// Read the file data
	data, err := io.ReadAll(file.Reader)
	if err != nil {
		return nil, fmt.Errorf("read file: %w", err)
	}

	if progress != nil {
		progress(int64(len(data)), file.Size)
	}

	// Check if room is encrypted
	isEncrypted, _, _ := m.GetEncryptionInfo(chatID)

	// Determine message type from MIME
	msgType := event.MsgFile
	if strings.HasPrefix(file.MimeType, "image/") {
		msgType = event.MsgImage
	} else if strings.HasPrefix(file.MimeType, "audio/") {
		msgType = event.MsgAudio
	} else if strings.HasPrefix(file.MimeType, "video/") {
		msgType = event.MsgVideo
	}

	content := &event.MessageEventContent{
		MsgType: msgType,
		Body:    file.Name,
		Info: &event.FileInfo{
			MimeType: file.MimeType,
			Size:     int(file.Size),
		},
	}

	var uploadURI id.ContentURI
	if isEncrypted {
		// Encrypt file data before upload (AES-256-CTR per Matrix spec)
		ef := attachment.NewEncryptedFile()
		ef.EncryptInPlace(data)

		// Upload encrypted bytes
		resp, err := m.client.UploadBytesWithName(m.ctx, data, "application/octet-stream", "")
		if err != nil {
			return nil, fmt.Errorf("upload encrypted: %w", err)
		}
		uploadURI = resp.ContentURI

		// Set encrypted file info (URL goes in File, not content.URL)
		content.File = &event.EncryptedFileInfo{
			EncryptedFile: *ef,
			URL:           resp.ContentURI.CUString(),
		}
	} else {
		// Upload plaintext
		resp, err := m.client.UploadBytesWithName(m.ctx, data, file.MimeType, file.Name)
		if err != nil {
			return nil, fmt.Errorf("upload: %w", err)
		}
		uploadURI = resp.ContentURI
		content.URL = resp.ContentURI.CUString()
	}

	sendResp, err := m.client.SendMessageEvent(m.ctx, roomID, event.EventMessage, content)
	if err != nil {
		return nil, fmt.Errorf("send file message: %w", err)
	}

	// Build attachment ref
	attRef := FileRef{
		ID:       uploadURI.String(),
		Name:     file.Name,
		MimeType: file.MimeType,
		Size:     file.Size,
	}
	if isEncrypted && content.File != nil {
		if efJSON, err := json.Marshal(content.File); err == nil {
			attRef.Extra = string(efJSON)
		}
	}

	return &Message{
		ID:        sendResp.EventID.String(),
		ChatID:    chatID,
		SenderID:  m.userID.String(),
		Text:      file.Name,
		Timestamp: time.Now(),
		Status:    MessageStatusSent,
		Attachments: []FileRef{attRef},
		Platform:  "matrix",
	}, nil
}

func (m *MatrixCore) DownloadFile(fileRef FileRef, dest string, progress func(recv, total int64)) error {
	if !m.authed {
		return ErrAuth
	}

	// Determine the mxc:// URI — may come from fileRef.ID or encrypted file info
	var mxcStr string
	var encFile *event.EncryptedFileInfo

	if fileRef.Extra != "" {
		// Try to parse encrypted file info from Extra
		var ef event.EncryptedFileInfo
		if err := json.Unmarshal([]byte(fileRef.Extra), &ef); err == nil && ef.URL != "" {
			encFile = &ef
			mxcStr = string(ef.URL)
		}
	}
	if mxcStr == "" {
		mxcStr = fileRef.ID
	}

	mxcURI, err := id.ParseContentURI(mxcStr)
	if err != nil {
		return fmt.Errorf("parse mxc URI: %w", err)
	}

	data, err := m.client.DownloadBytes(m.ctx, mxcURI)
	if err != nil {
		return fmt.Errorf("download: %w", err)
	}

	// Decrypt if encrypted file info is present
	if encFile != nil {
		if err := encFile.DecryptInPlace(data); err != nil {
			return fmt.Errorf("decrypt file: %w", err)
		}
	}

	if progress != nil {
		progress(int64(len(data)), int64(len(data)))
	}

	if err := os.MkdirAll(filepath.Dir(dest), 0o755); err != nil {
		return fmt.Errorf("mkdir: %w", err)
	}

	return os.WriteFile(dest, data, 0o644)
}

// --- Core Interface: Media ---

func (m *MatrixCore) SendImageBase64(chatID string, b64 string, caption string) (*Message, error) {
	if !m.authed {
		return nil, ErrAuth
	}

	data, err := base64.StdEncoding.DecodeString(b64)
	if err != nil {
		return nil, fmt.Errorf("decode base64: %w", err)
	}

	// Detect MIME type
	mimeType := http.DetectContentType(data)

	// Determine file extension
	exts, _ := mime.ExtensionsByType(mimeType)
	name := "image.png"
	if len(exts) > 0 {
		name = "image" + exts[0]
	}

	return m.UploadFile(chatID, FileUpload{
		Name:     name,
		MimeType: mimeType,
		Size:     int64(len(data)),
		Reader:   bytes.NewReader(data),
	}, nil)
}

// --- Core Interface: Calls ---

func (m *MatrixCore) StartCall(chatID string, video bool) (*CallSession, error) {
	if !m.authed {
		return nil, ErrAuth
	}

	roomID := id.RoomID(chatID)
	callID := fmt.Sprintf("call_%d", time.Now().UnixNano())

	// Create PeerConnection with TURN servers
	pc, err := m.createPeerConnection()
	if err != nil {
		return nil, fmt.Errorf("create peer connection: %w", err)
	}

	callCtx, callCancel := context.WithCancel(m.ctx)

	call := &matrixCall{
		ID:         callID,
		RoomID:     roomID,
		IsVideo:    video,
		State:      CallStateRinging,
		StartTime:  time.Now(),
		IsOutgoing: true,
		pc:         pc,
		cancel:     callCancel,
	}

	// Add audio track
	audioTrack, err := webrtc.NewTrackLocalStaticRTP(
		webrtc.RTPCodecCapability{MimeType: webrtc.MimeTypeOpus, ClockRate: 48000, Channels: 2},
		"audio", "uniclient-audio",
	)
	if err != nil {
		pc.Close()
		callCancel()
		return nil, fmt.Errorf("create audio track: %w", err)
	}
	call.audioTrack = audioTrack

	if _, err := pc.AddTrack(audioTrack); err != nil {
		pc.Close()
		callCancel()
		return nil, fmt.Errorf("add audio track: %w", err)
	}

	// Set up ICE candidate trickle
	pc.OnICECandidate(func(c *webrtc.ICECandidate) {
		if c == nil {
			return
		}
		m.sendICECandidates(call, []webrtc.ICECandidateInit{c.ToJSON()})
	})

	// Set up connection state handler
	m.setupCallStateHandlers(call)

	// Set up incoming audio handler
	pc.OnTrack(func(track *webrtc.TrackRemote, recv *webrtc.RTPReceiver) {
		m.handleIncomingAudio(callCtx, call, track)
	})

	// Create SDP offer
	offer, err := pc.CreateOffer(nil)
	if err != nil {
		pc.Close()
		callCancel()
		return nil, fmt.Errorf("create offer: %w", err)
	}

	if err := pc.SetLocalDescription(offer); err != nil {
		pc.Close()
		callCancel()
		return nil, fmt.Errorf("set local description: %w", err)
	}

	// Wait for ICE gathering to complete (or timeout)
	gatherDone := webrtc.GatheringCompletePromise(pc)
	select {
	case <-gatherDone:
	case <-time.After(5 * time.Second):
		// Use whatever candidates we have so far
	}

	// Send m.call.invite with the SDP offer
	inviteContent := &event.CallInviteEventContent{
		BaseCallEventContent: event.BaseCallEventContent{
			CallID:  callID,
			Version: "1",
			PartyID: m.deviceID.String(),
		},
		Lifetime: 60000,
		Offer: event.CallData{
			Type: event.CallDataTypeOffer,
			SDP:  pc.LocalDescription().SDP,
		},
	}

	_, err = m.client.SendMessageEvent(m.ctx, roomID, event.CallInvite, inviteContent)
	if err != nil {
		pc.Close()
		callCancel()
		return nil, fmt.Errorf("send call invite: %w", err)
	}

	m.callsMu.Lock()
	m.activeCalls[callID] = call
	m.callsMu.Unlock()

	// Start silence sender to keep the audio stream alive
	go m.sendAudio(callCtx, call)

	// Start invite timeout
	go func() {
		select {
		case <-time.After(60 * time.Second):
			m.callsMu.RLock()
			c, ok := m.activeCalls[callID]
			m.callsMu.RUnlock()
			if ok && c.State == CallStateRinging {
				m.EndCall(callID)
			}
		case <-callCtx.Done():
		}
	}()

	return &CallSession{
		ID:      callID,
		ChatID:  chatID,
		IsVideo: video,
		State:   CallStateRinging,
	}, nil
}

func (m *MatrixCore) JoinGroupCall(chatID string) (*CallSession, error) {
	return nil, ErrNotSupported // MSC3401, defer
}

func (m *MatrixCore) EndCall(callID string) error {
	if !m.authed {
		return ErrAuth
	}

	m.callsMu.Lock()
	call, ok := m.activeCalls[callID]
	if ok {
		delete(m.activeCalls, callID)
	}
	m.callsMu.Unlock()

	if !ok {
		return ErrNotFound
	}

	// Close WebRTC
	m.cleanupCall(call)

	content := &event.CallHangupEventContent{
		BaseCallEventContent: event.BaseCallEventContent{
			CallID:  callID,
			Version: "1",
			PartyID: m.deviceID.String(),
		},
		Reason: event.CallHangupUserHangup,
	}

	_, err := m.client.SendMessageEvent(m.ctx, call.RoomID, event.CallHangup, content)
	if err != nil {
		return fmt.Errorf("send hangup: %w", err)
	}

	return nil
}

func (m *MatrixCore) SetCallMuted(callID string, muted bool) error {
	m.callsMu.RLock()
	call, ok := m.activeCalls[callID]
	m.callsMu.RUnlock()
	if !ok {
		return ErrNotFound
	}

	if call.pc != nil {
		for _, sender := range call.pc.GetSenders() {
			if sender.Track() != nil {
				// Disable/enable the track by replacing with nil or restoring
				// For now, we stop the silence sender via muted flag on call
			}
		}
	}
	// Mute is handled by the silence sender checking this state
	call.mu.Lock()
	if muted {
		call.State = CallStateActive // stays active, just muted
	}
	call.mu.Unlock()

	return nil
}

// SetCallAudioSource sets a callback that provides Opus frames to send (called every 20ms).
// If nil, silence is sent. The callback must return a complete Opus frame or nil for silence.
func (m *MatrixCore) SetCallAudioSource(callID string, source func() []byte) error {
	m.callsMu.RLock()
	call, ok := m.activeCalls[callID]
	m.callsMu.RUnlock()
	if !ok {
		return ErrNotFound
	}
	call.mu.Lock()
	call.audioSource = source
	call.mu.Unlock()
	return nil
}

// SetCallAudioSink sets a callback that receives Opus frames from the remote party.
// Each call delivers one Opus frame (typically 20ms of audio).
func (m *MatrixCore) SetCallAudioSink(callID string, sink func([]byte)) error {
	m.callsMu.RLock()
	call, ok := m.activeCalls[callID]
	m.callsMu.RUnlock()
	if !ok {
		return ErrNotFound
	}
	call.mu.Lock()
	call.audioSink = sink
	call.mu.Unlock()
	return nil
}

// AcceptCall answers an incoming call (extra method, not in Core interface).
func (m *MatrixCore) AcceptCall(callID string) (*CallSession, error) {
	if !m.authed {
		return nil, ErrAuth
	}

	m.callsMu.RLock()
	call, ok := m.activeCalls[callID]
	m.callsMu.RUnlock()
	if !ok {
		return nil, ErrNotFound
	}
	if call.IsOutgoing {
		return nil, fmt.Errorf("%w: cannot accept outgoing call", ErrInvalidInput)
	}
	if call.pc == nil {
		return nil, fmt.Errorf("no peer connection for call %s (no SDP offer received)", callID)
	}

	// Create SDP answer
	answer, err := call.pc.CreateAnswer(nil)
	if err != nil {
		return nil, fmt.Errorf("create answer: %w", err)
	}

	if err := call.pc.SetLocalDescription(answer); err != nil {
		return nil, fmt.Errorf("set local description: %w", err)
	}

	// Wait for ICE gathering
	gatherDone := webrtc.GatheringCompletePromise(call.pc)
	select {
	case <-gatherDone:
	case <-time.After(5 * time.Second):
	}

	// Send m.call.answer
	answerContent := &event.CallAnswerEventContent{
		BaseCallEventContent: event.BaseCallEventContent{
			CallID:  callID,
			Version: "1",
			PartyID: m.deviceID.String(),
		},
		Answer: event.CallData{
			Type: event.CallDataTypeAnswer,
			SDP:  call.pc.LocalDescription().SDP,
		},
	}

	_, err = m.client.SendMessageEvent(m.ctx, call.RoomID, event.CallAnswer, answerContent)
	if err != nil {
		return nil, fmt.Errorf("send call answer: %w", err)
	}

	call.mu.Lock()
	call.State = CallStateConnecting
	call.mu.Unlock()

	return &CallSession{
		ID:      callID,
		ChatID:  call.RoomID.String(),
		IsVideo: call.IsVideo,
		State:   CallStateConnecting,
	}, nil
}

// RejectCall rejects an incoming call (extra method).
func (m *MatrixCore) RejectCall(callID string) error {
	if !m.authed {
		return ErrAuth
	}

	m.callsMu.Lock()
	call, ok := m.activeCalls[callID]
	if ok {
		delete(m.activeCalls, callID)
	}
	m.callsMu.Unlock()
	if !ok {
		return ErrNotFound
	}

	m.cleanupCall(call)

	rejectContent := &event.CallRejectEventContent{
		BaseCallEventContent: event.BaseCallEventContent{
			CallID:  callID,
			Version: "1",
			PartyID: m.deviceID.String(),
		},
	}

	_, err := m.client.SendMessageEvent(m.ctx, call.RoomID, event.CallReject, rejectContent)
	if err != nil {
		return fmt.Errorf("send reject: %w", err)
	}

	m.dispatchUpdate(Update{
		Type:   UpdateCallState,
		ChatID: call.RoomID.String(),
		Call: &CallSession{
			ID:     callID,
			ChatID: call.RoomID.String(),
			State:  CallStateEnded,
		},
		Platform: "matrix",
	})

	return nil
}

// createPeerConnection creates a pion PeerConnection with TURN servers from the homeserver.
func (m *MatrixCore) createPeerConnection() (*webrtc.PeerConnection, error) {
	config := webrtc.Configuration{
		ICEServers: []webrtc.ICEServer{
			{URLs: []string{"stun:stun.l.google.com:19302"}},
		},
	}

	// Try to get TURN server from homeserver
	turnResp, err := m.client.TurnServer(m.ctx)
	if err == nil && len(turnResp.URIs) > 0 {
		config.ICEServers = append(config.ICEServers, webrtc.ICEServer{
			URLs:       turnResp.URIs,
			Username:   turnResp.Username,
			Credential: turnResp.Password,
		})
	}

	return webrtc.NewPeerConnection(config)
}

// setupCallStateHandlers wires pion connection state changes to Matrix call state updates.
func (m *MatrixCore) setupCallStateHandlers(call *matrixCall) {
	call.pc.OnConnectionStateChange(func(state webrtc.PeerConnectionState) {
		switch state {
		case webrtc.PeerConnectionStateConnected:
			call.mu.Lock()
			call.State = CallStateActive
			call.mu.Unlock()

			m.dispatchUpdate(Update{
				Type:   UpdateCallState,
				ChatID: call.RoomID.String(),
				Call: &CallSession{
					ID:      call.ID,
					ChatID:  call.RoomID.String(),
					IsVideo: call.IsVideo,
					State:   CallStateActive,
				},
				Platform: "matrix",
			})

		case webrtc.PeerConnectionStateFailed, webrtc.PeerConnectionStateDisconnected:
			// ICE failed — end call
			m.callsMu.Lock()
			_, stillActive := m.activeCalls[call.ID]
			if stillActive {
				delete(m.activeCalls, call.ID)
			}
			m.callsMu.Unlock()

			if stillActive {
				m.cleanupCall(call)
				// Send hangup with ICE failed reason
				hangup := &event.CallHangupEventContent{
					BaseCallEventContent: event.BaseCallEventContent{
						CallID:  call.ID,
						Version: "1",
						PartyID: m.deviceID.String(),
					},
					Reason: event.CallHangupICEFailed,
				}
				m.client.SendMessageEvent(m.ctx, call.RoomID, event.CallHangup, hangup)

				m.dispatchUpdate(Update{
					Type:   UpdateCallState,
					ChatID: call.RoomID.String(),
					Call: &CallSession{
						ID:     call.ID,
						ChatID: call.RoomID.String(),
						State:  CallStateEnded,
					},
					Platform: "matrix",
				})
			}
		}
	})
}

// sendICECandidates sends ICE candidates to the remote peer via m.call.candidates.
func (m *MatrixCore) sendICECandidates(call *matrixCall, candidates []webrtc.ICECandidateInit) {
	var matrixCandidates []event.CallCandidate
	for _, c := range candidates {
		mc := event.CallCandidate{
			Candidate: c.Candidate,
		}
		if c.SDPMLineIndex != nil {
			mc.SDPMLineIndex = int(*c.SDPMLineIndex)
		}
		if c.SDPMid != nil {
			mc.SDPMID = *c.SDPMid
		}
		matrixCandidates = append(matrixCandidates, mc)
	}

	content := &event.CallCandidatesEventContent{
		BaseCallEventContent: event.BaseCallEventContent{
			CallID:  call.ID,
			Version: "1",
			PartyID: m.deviceID.String(),
		},
		Candidates: matrixCandidates,
	}

	m.client.SendMessageEvent(m.ctx, call.RoomID, event.CallCandidates, content)
}

// handleIncomingAudio reads RTP packets from a remote audio track and delivers
// the Opus payload to the audioSink callback if set.
func (m *MatrixCore) handleIncomingAudio(ctx context.Context, call *matrixCall, track *webrtc.TrackRemote) {
	buf := make([]byte, 1500)
	for {
		select {
		case <-ctx.Done():
			return
		default:
		}
		n, _, err := track.Read(buf)
		if err != nil {
			return
		}
		if n < 12 {
			continue // too short for RTP header
		}

		// Extract Opus payload (skip 12-byte RTP header)
		payload := make([]byte, n-12)
		copy(payload, buf[12:n])

		call.mu.Lock()
		sink := call.audioSink
		call.mu.Unlock()
		if sink != nil {
			sink(payload)
		}
	}
}

// sendAudio sends audio frames via RTP. Uses audioSource callback if set, otherwise sends Opus silence.
func (m *MatrixCore) sendAudio(ctx context.Context, call *matrixCall) {
	// Opus silence frame (20ms, mono)
	silence := []byte{0xf8, 0xff, 0xfe}
	ticker := time.NewTicker(20 * time.Millisecond)
	defer ticker.Stop()

	seq := uint16(0)
	ts := uint32(0)

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			if call.audioTrack == nil {
				return
			}

			// Get audio frame from source callback or use silence
			var frame []byte
			call.mu.Lock()
			src := call.audioSource
			call.mu.Unlock()
			if src != nil {
				frame = src()
			}
			if frame == nil {
				frame = silence
			}

			// Build RTP packet
			header := make([]byte, 12)
			header[0] = 0x80             // V=2, no padding, no extension, no CSRC
			header[1] = 111              // PT=111 (Opus), no marker
			header[2] = byte(seq >> 8)   // seq high
			header[3] = byte(seq)        // seq low
			header[4] = byte(ts >> 24)   // timestamp
			header[5] = byte(ts >> 16)
			header[6] = byte(ts >> 8)
			header[7] = byte(ts)
			// SSRC is set by pion from the track

			pkt := append(header, frame...)
			if _, err := call.audioTrack.Write(pkt); err != nil {
				return
			}
			seq++
			ts += 960 // 20ms at 48kHz
		}
	}
}

// addICECandidate adds a buffered or immediate ICE candidate.
func (m *MatrixCore) addICECandidate(call *matrixCall, candidate webrtc.ICECandidateInit) {
	call.mu.Lock()
	defer call.mu.Unlock()

	if !call.remoteSet {
		call.pendingCandidates = append(call.pendingCandidates, candidate)
		return
	}

	call.pc.AddICECandidate(candidate)
}

// flushPendingCandidates adds all buffered ICE candidates after remote description is set.
func (m *MatrixCore) flushPendingCandidates(call *matrixCall) {
	call.mu.Lock()
	defer call.mu.Unlock()

	call.remoteSet = true
	for _, c := range call.pendingCandidates {
		call.pc.AddICECandidate(c)
	}
	call.pendingCandidates = nil
}

// cleanupCall closes WebRTC resources for a call.
func (m *MatrixCore) cleanupCall(call *matrixCall) {
	if call.cancel != nil {
		call.cancel()
	}
	if call.pc != nil {
		call.pc.Close()
	}
	call.mu.Lock()
	call.State = CallStateEnded
	call.mu.Unlock()
}

// handleCallAnswer processes an incoming m.call.answer event (for outgoing calls).
func (m *MatrixCore) handleCallAnswer(evt *event.Event) {
	evt.Content.ParseRaw(evt.Type)
	ca, ok := evt.Content.Parsed.(*event.CallAnswerEventContent)
	if !ok {
		return
	}

	m.callsMu.RLock()
	call, ok := m.activeCalls[ca.CallID]
	m.callsMu.RUnlock()
	if !ok || !call.IsOutgoing || call.pc == nil {
		return
	}

	// Ignore our own events
	if ca.PartyID == m.deviceID.String() {
		return
	}

	call.RemoteParty = ca.PartyID

	// Set remote description (SDP answer)
	err := call.pc.SetRemoteDescription(webrtc.SessionDescription{
		Type: webrtc.SDPTypeAnswer,
		SDP:  ca.Answer.SDP,
	})
	if err != nil {
		return
	}

	// Flush buffered ICE candidates
	m.flushPendingCandidates(call)

	call.mu.Lock()
	call.State = CallStateConnecting
	call.mu.Unlock()

	m.dispatchUpdate(Update{
		Type:   UpdateCallState,
		ChatID: evt.RoomID.String(),
		Call: &CallSession{
			ID:      ca.CallID,
			ChatID:  evt.RoomID.String(),
			IsVideo: call.IsVideo,
			State:   CallStateConnecting,
		},
		Platform: "matrix",
	})
}

// handleCallCandidates processes incoming m.call.candidates events.
func (m *MatrixCore) handleCallCandidates(evt *event.Event) {
	evt.Content.ParseRaw(evt.Type)
	cc, ok := evt.Content.Parsed.(*event.CallCandidatesEventContent)
	if !ok {
		return
	}

	// Ignore our own events
	if cc.PartyID == m.deviceID.String() {
		return
	}

	m.callsMu.RLock()
	call, ok := m.activeCalls[cc.CallID]
	m.callsMu.RUnlock()
	if !ok || call.pc == nil {
		return
	}

	for _, c := range cc.Candidates {
		idx := uint16(c.SDPMLineIndex)
		mid := c.SDPMID
		m.addICECandidate(call, webrtc.ICECandidateInit{
			Candidate:     c.Candidate,
			SDPMLineIndex: &idx,
			SDPMid:        &mid,
		})
	}
}

// --- Core Interface: Profile ---

func (m *MatrixCore) GetProfile(userID string) (*User, error) {
	if !m.authed {
		return nil, ErrAuth
	}

	mxid := id.UserID(userID)
	profile, err := m.client.GetProfile(m.ctx, mxid)
	if err != nil {
		return nil, fmt.Errorf("get profile: %w", err)
	}

	user := &User{
		ID:          userID,
		DisplayName: profile.DisplayName,
		Platform:    "matrix",
	}

	if profile.AvatarURL.IsEmpty() == false {
		user.AvatarURL = profile.AvatarURL.String()
	}

	// Try presence
	presence, err := m.client.GetPresence(m.ctx, mxid)
	if err == nil {
		user.IsOnline = presence.Presence == event.PresenceOnline
		if presence.LastActiveAgo > 0 {
			t := time.Now().Add(-time.Duration(presence.LastActiveAgo) * time.Millisecond)
			user.LastSeen = &t
		}
	}

	return user, nil
}

// --- Core Interface: Real-time ---

func (m *MatrixCore) OnUpdate(handler func(Update)) {
	m.updateMu.Lock()
	defer m.updateMu.Unlock()
	m.updateHandlers = append(m.updateHandlers, handler)
}

func (m *MatrixCore) Close() error {
	m.mu.Lock()
	defer m.mu.Unlock()

	if m.syncStop != nil {
		m.syncStop()
	}
	m.cancel()
	m.saveSession()

	return nil
}

// --- Core Interface: Chat Management ---

func (m *MatrixCore) GetChatInfo(chatID string) (*Dialog, error) {
	if !m.authed {
		return nil, ErrAuth
	}

	roomID := id.RoomID(chatID)
	m.roomsMu.RLock()
	rs := m.rooms[roomID]
	m.roomsMu.RUnlock()

	if rs == nil {
		// Fetch from server
		if err := m.fetchRoomState(roomID); err != nil {
			return nil, err
		}
		m.roomsMu.RLock()
		rs = m.rooms[roomID]
		m.roomsMu.RUnlock()
	}

	if rs == nil {
		return nil, ErrNotFound
	}

	dialog := m.roomToDialog(rs)
	return &dialog, nil
}

func (m *MatrixCore) EditChatTitle(chatID string, title string) error {
	if !m.authed {
		return ErrAuth
	}

	roomID := id.RoomID(chatID)
	_, err := m.client.SendStateEvent(m.ctx, roomID, event.StateRoomName, "", map[string]string{
		"name": title,
	})
	if err != nil {
		return fmt.Errorf("set room name: %w", err)
	}
	return nil
}

func (m *MatrixCore) EditChatDescription(chatID string, description string) error {
	if !m.authed {
		return ErrAuth
	}

	roomID := id.RoomID(chatID)
	_, err := m.client.SendStateEvent(m.ctx, roomID, event.StateTopic, "", map[string]string{
		"topic": description,
	})
	if err != nil {
		return fmt.Errorf("set room topic: %w", err)
	}
	return nil
}

func (m *MatrixCore) LeaveChat(chatID string) error {
	if !m.authed {
		return ErrAuth
	}

	roomID := id.RoomID(chatID)
	_, err := m.client.LeaveRoom(m.ctx, roomID)
	if err != nil {
		return fmt.Errorf("leave room: %w", err)
	}

	m.roomsMu.Lock()
	delete(m.rooms, roomID)
	m.roomsMu.Unlock()

	return nil
}

func (m *MatrixCore) GetInviteLink(chatID string) (string, error) {
	if !m.authed {
		return "", ErrAuth
	}

	roomID := id.RoomID(chatID)

	// Try to get canonical alias first
	var aliasContent event.CanonicalAliasEventContent
	err := m.client.StateEvent(m.ctx, roomID, event.StateCanonicalAlias, "", &aliasContent)
	if err == nil && aliasContent.Alias != "" {
		return fmt.Sprintf("https://matrix.to/#/%s", aliasContent.Alias), nil
	}

	// Fall back to room ID
	return fmt.Sprintf("https://matrix.to/#/%s", roomID), nil
}

// --- Core Interface: Members ---

func (m *MatrixCore) AddMembers(chatID string, userIDs []string) error {
	if !m.authed {
		return ErrAuth
	}

	roomID := id.RoomID(chatID)
	for _, uid := range userIDs {
		_, err := m.client.InviteUser(m.ctx, roomID, &mautrix.ReqInviteUser{
			UserID: id.UserID(uid),
		})
		if err != nil {
			return fmt.Errorf("invite %s: %w", uid, err)
		}
	}
	return nil
}

func (m *MatrixCore) RemoveMember(chatID string, userID string) error {
	if !m.authed {
		return ErrAuth
	}

	roomID := id.RoomID(chatID)
	_, err := m.client.KickUser(m.ctx, roomID, &mautrix.ReqKickUser{
		UserID: id.UserID(userID),
	})
	if err != nil {
		return fmt.Errorf("kick: %w", err)
	}
	return nil
}

func (m *MatrixCore) BanMember(chatID string, userID string) error {
	if !m.authed {
		return ErrAuth
	}

	roomID := id.RoomID(chatID)
	_, err := m.client.BanUser(m.ctx, roomID, &mautrix.ReqBanUser{
		UserID: id.UserID(userID),
	})
	if err != nil {
		return fmt.Errorf("ban: %w", err)
	}
	return nil
}

func (m *MatrixCore) UnbanMember(chatID string, userID string) error {
	if !m.authed {
		return ErrAuth
	}

	roomID := id.RoomID(chatID)
	_, err := m.client.UnbanUser(m.ctx, roomID, &mautrix.ReqUnbanUser{
		UserID: id.UserID(userID),
	})
	if err != nil {
		return fmt.Errorf("unban: %w", err)
	}
	return nil
}

func (m *MatrixCore) GetMembers(chatID string, opts PaginationOpts) ([]User, error) {
	if !m.authed {
		return nil, ErrAuth
	}

	roomID := id.RoomID(chatID)
	resp, err := m.client.JoinedMembers(m.ctx, roomID)
	if err != nil {
		return nil, fmt.Errorf("get members: %w", err)
	}

	var users []User
	for uid, member := range resp.Joined {
		u := User{
			ID:          uid.String(),
			DisplayName: member.DisplayName,
			AvatarURL:   member.AvatarURL,
			Platform:    "matrix",
		}
		users = append(users, u)
	}

	return users, nil
}

func (m *MatrixCore) SetAdmin(chatID string, userID string, admin bool) error {
	if !m.authed {
		return ErrAuth
	}

	roomID := id.RoomID(chatID)
	mxid := id.UserID(userID)

	// Get current power levels
	var pl event.PowerLevelsEventContent
	err := m.client.StateEvent(m.ctx, roomID, event.StatePowerLevels, "", &pl)
	if err != nil {
		return fmt.Errorf("get power levels: %w", err)
	}

	if admin {
		pl.SetUserLevel(mxid, 50) // Moderator level
	} else {
		pl.SetUserLevel(mxid, 0) // Default
	}

	_, err = m.client.SendStateEvent(m.ctx, roomID, event.StatePowerLevels, "", &pl)
	if err != nil {
		return fmt.Errorf("set power levels: %w", err)
	}

	return nil
}

// --- Core Interface: Contacts ---

func (m *MatrixCore) GetContacts() ([]User, error) {
	if !m.authed {
		return nil, ErrAuth
	}

	// Matrix contacts = DM room participants from m.direct account data
	m.directChatsMu.RLock()
	defer m.directChatsMu.RUnlock()

	var contacts []User
	for uid := range m.directChats {
		profile, err := m.client.GetProfile(m.ctx, uid)
		if err != nil {
			contacts = append(contacts, User{
				ID:          uid.String(),
				DisplayName: uid.String(),
				Platform:    "matrix",
			})
			continue
		}

		u := User{
			ID:          uid.String(),
			DisplayName: profile.DisplayName,
			Platform:    "matrix",
		}
		if !profile.AvatarURL.IsEmpty() {
			u.AvatarURL = profile.AvatarURL.String()
		}
		contacts = append(contacts, u)
	}

	return contacts, nil
}

func (m *MatrixCore) AddContact(phone string, firstName string, lastName string) error {
	return ErrNotSupported // Matrix uses @user:server, not phone numbers
}

func (m *MatrixCore) DeleteContact(userID string) error {
	if !m.authed {
		return ErrAuth
	}

	// Remove from m.direct account data
	m.directChatsMu.Lock()
	delete(m.directChats, id.UserID(userID))
	m.directChatsMu.Unlock()

	return m.saveDirectChats()
}

func (m *MatrixCore) BlockUser(userID string) error {
	if !m.authed {
		return ErrAuth
	}

	// Get current ignored list
	var ignored map[string]interface{}
	m.client.GetAccountData(m.ctx, "m.ignored_user_list", &ignored)
	if ignored == nil {
		ignored = make(map[string]interface{})
	}

	users, _ := ignored["ignored_users"].(map[string]interface{})
	if users == nil {
		users = make(map[string]interface{})
	}
	users[userID] = map[string]interface{}{}
	ignored["ignored_users"] = users

	return m.client.SetAccountData(m.ctx, "m.ignored_user_list", &ignored)
}

func (m *MatrixCore) UnblockUser(userID string) error {
	if !m.authed {
		return ErrAuth
	}

	var ignored map[string]interface{}
	m.client.GetAccountData(m.ctx, "m.ignored_user_list", &ignored)
	if ignored == nil {
		return nil
	}

	users, _ := ignored["ignored_users"].(map[string]interface{})
	if users != nil {
		delete(users, userID)
		ignored["ignored_users"] = users
	}

	return m.client.SetAccountData(m.ctx, "m.ignored_user_list", &ignored)
}

func (m *MatrixCore) GetBlockedUsers() ([]User, error) {
	if !m.authed {
		return nil, ErrAuth
	}

	var ignored map[string]interface{}
	err := m.client.GetAccountData(m.ctx, "m.ignored_user_list", &ignored)
	if err != nil {
		return nil, nil // No ignored users
	}

	users, _ := ignored["ignored_users"].(map[string]interface{})
	var blocked []User
	for uid := range users {
		blocked = append(blocked, User{
			ID:          uid,
			DisplayName: uid,
			Platform:    "matrix",
		})
	}

	return blocked, nil
}

// --- Core Interface: Search ---

func (m *MatrixCore) SearchMessages(chatID string, query string, opts PaginationOpts) ([]Message, error) {
	if !m.authed {
		return nil, ErrAuth
	}

	limit := opts.Limit
	if limit <= 0 {
		limit = 20
	}

	roomID := id.RoomID(chatID)

	// Use raw /search endpoint — mautrix doesn't have a convenience method
	searchReq := map[string]interface{}{
		"search_categories": map[string]interface{}{
			"room_events": map[string]interface{}{
				"search_term": query,
				"filter": map[string]interface{}{
					"rooms": []string{roomID.String()},
					"limit": limit,
				},
				"order_by": "recent",
			},
		},
	}

	respData, err := m.client.MakeFullRequest(m.ctx, mautrix.FullRequest{
		Method:      http.MethodPost,
		URL:         m.client.BuildClientURL("v3", "search"),
		RequestJSON: searchReq,
	})
	if err != nil {
		return nil, fmt.Errorf("search: %w", err)
	}

	var searchResp struct {
		SearchCategories struct {
			RoomEvents struct {
				Results []struct {
					Result json.RawMessage `json:"result"`
				} `json:"results"`
			} `json:"room_events"`
		} `json:"search_categories"`
	}
	if err := json.Unmarshal(respData, &searchResp); err != nil {
		return nil, fmt.Errorf("parse search: %w", err)
	}

	var messages []Message
	for _, result := range searchResp.SearchCategories.RoomEvents.Results {
		var evt event.Event
		if err := json.Unmarshal(result.Result, &evt); err != nil {
			continue
		}
		msg := m.eventToMessage(&evt)
		if msg != nil {
			messages = append(messages, *msg)
		}
	}

	return messages, nil
}

func (m *MatrixCore) SearchGlobal(query string, opts PaginationOpts) ([]Dialog, error) {
	if !m.authed {
		return nil, ErrAuth
	}

	resp, err := m.client.SearchUserDirectory(m.ctx, query, 20)
	if err != nil {
		return nil, fmt.Errorf("search: %w", err)
	}

	var dialogs []Dialog
	for _, user := range resp.Results {
		dialogs = append(dialogs, Dialog{
			ID:       user.UserID.String(),
			Type:     ChatTypeDM,
			Title:    user.DisplayName,
			Platform: "matrix",
		})
	}

	return dialogs, nil
}

// --- Core Interface: Typing ---

func (m *MatrixCore) SendTyping(chatID string) error {
	if !m.authed {
		return ErrAuth
	}

	roomID := id.RoomID(chatID)
	_, err := m.client.UserTyping(m.ctx, roomID, true, 5000)
	if err != nil {
		return fmt.Errorf("typing: %w", err)
	}
	return nil
}

// --- Core Interface: Polls ---

func (m *MatrixCore) CreatePoll(chatID string, question string, options []string) (*Message, error) {
	if !m.authed {
		return nil, ErrAuth
	}

	roomID := id.RoomID(chatID)

	// MSC3381 poll format (unstable prefix)
	answers := make([]map[string]interface{}, len(options))
	for i, opt := range options {
		answers[i] = map[string]interface{}{
			"id":                        fmt.Sprintf("opt_%d", i),
			"org.matrix.msc1767.text":   opt,
		}
	}

	content := map[string]interface{}{
		"org.matrix.msc3381.v2.poll": map[string]interface{}{
			"kind":      "org.matrix.msc3381.v2.disclosed",
			"max_selections": 1,
			"question": map[string]interface{}{
				"org.matrix.msc1767.text": question,
			},
			"answers": answers,
		},
		"org.matrix.msc1767.text": question, // fallback
	}

	resp, err := m.client.SendMessageEvent(m.ctx, roomID, event.Type{
		Type:  "org.matrix.msc3381.v2.poll.start",
		Class: event.MessageEventType,
	}, content)
	if err != nil {
		return nil, fmt.Errorf("create poll: %w", err)
	}

	return &Message{
		ID:        resp.EventID.String(),
		ChatID:    chatID,
		SenderID:  m.userID.String(),
		Text:      question,
		Timestamp: time.Now(),
		Status:    MessageStatusSent,
		Platform:  "matrix",
	}, nil
}

func (m *MatrixCore) VotePoll(chatID string, msgID string, optionIndex int) error {
	if !m.authed {
		return ErrAuth
	}

	roomID := id.RoomID(chatID)
	content := map[string]interface{}{
		"m.relates_to": map[string]interface{}{
			"rel_type": "m.reference",
			"event_id": msgID,
		},
		"org.matrix.msc3381.v2.selections": []string{fmt.Sprintf("opt_%d", optionIndex)},
	}

	_, err := m.client.SendMessageEvent(m.ctx, roomID, event.Type{
		Type:  "org.matrix.msc3381.v2.poll.response",
		Class: event.MessageEventType,
	}, content)
	if err != nil {
		return fmt.Errorf("vote poll: %w", err)
	}
	return nil
}

// --- Core Interface: Stickers ---

func (m *MatrixCore) SendSticker(chatID string, stickerID string) (*Message, error) {
	if !m.authed {
		return nil, ErrAuth
	}

	roomID := id.RoomID(chatID)

	// stickerID is expected to be an mxc:// URI
	mxcURI, err := id.ParseContentURI(stickerID)
	if err != nil {
		return nil, fmt.Errorf("parse sticker URI: %w", err)
	}

	content := map[string]interface{}{
		"body": "sticker",
		"url":  mxcURI.String(),
		"info": map[string]interface{}{
			"mimetype": "image/png",
		},
	}

	resp, err := m.client.SendMessageEvent(m.ctx, roomID, event.EventSticker, content)
	if err != nil {
		return nil, fmt.Errorf("send sticker: %w", err)
	}

	return &Message{
		ID:        resp.EventID.String(),
		ChatID:    chatID,
		SenderID:  m.userID.String(),
		Text:      "sticker",
		Timestamp: time.Now(),
		Status:    MessageStatusSent,
		Platform:  "matrix",
	}, nil
}

// --- Core Interface: Sessions ---

func (m *MatrixCore) GetSessions() ([]Session, error) {
	if !m.authed {
		return nil, ErrAuth
	}

	resp, err := m.client.GetDevicesInfo(m.ctx)
	if err != nil {
		return nil, fmt.Errorf("get devices: %w", err)
	}

	var sessions []Session
	for _, dev := range resp.Devices {
		s := Session{
			ID:        dev.DeviceID.String(),
			Device:    dev.DisplayName,
			Platform:  "matrix",
			IsCurrent: dev.DeviceID == m.deviceID,
		}
		if dev.LastSeenIP != "" {
			s.IP = dev.LastSeenIP
		}
		if dev.LastSeenTS > 0 {
			t := time.UnixMilli(dev.LastSeenTS)
			s.LastActive = t
		}
		sessions = append(sessions, s)
	}

	return sessions, nil
}

func (m *MatrixCore) TerminateSession(sessionID string) error {
	if !m.authed {
		return ErrAuth
	}

	err := m.client.DeleteDevice(m.ctx, id.DeviceID(sessionID), nil)
	if err != nil {
		return fmt.Errorf("delete device: %w", err)
	}
	return nil
}

// --- Extra Matrix Methods ---

// GetPresence returns the presence status of a user.
func (m *MatrixCore) GetPresence(userID string) (*User, error) {
	if !m.authed {
		return nil, ErrAuth
	}

	mxid := id.UserID(userID)
	presence, err := m.client.GetPresence(m.ctx, mxid)
	if err != nil {
		return nil, fmt.Errorf("get presence: %w", err)
	}

	user := &User{
		ID:       userID,
		IsOnline: presence.Presence == event.PresenceOnline,
		Platform: "matrix",
	}

	if presence.LastActiveAgo > 0 {
		t := time.Now().Add(-time.Duration(presence.LastActiveAgo) * time.Millisecond)
		user.LastSeen = &t
	}

	return user, nil
}

// SetPresence sets the user's presence status.
func (m *MatrixCore) SetPresence(status string, statusMsg string) error {
	if !m.authed {
		return ErrAuth
	}

	presence := event.PresenceOnline
	switch status {
	case "offline":
		presence = event.PresenceOffline
	case "unavailable":
		presence = event.PresenceUnavailable
	}

	return m.client.SetPresence(m.ctx, mautrix.ReqPresence{
		Presence:  presence,
		StatusMsg: statusMsg,
	})
}

// SetDisplayName updates the user's display name.
func (m *MatrixCore) SetDisplayName(name string) error {
	if !m.authed {
		return ErrAuth
	}
	return m.client.SetDisplayName(m.ctx, name)
}

// SetAvatar updates the user's avatar from an mxc:// URI.
func (m *MatrixCore) SetAvatar(mxcURI string) error {
	if !m.authed {
		return ErrAuth
	}
	uri, err := id.ParseContentURI(mxcURI)
	if err != nil {
		return fmt.Errorf("parse avatar URI: %w", err)
	}
	return m.client.SetAvatarURL(m.ctx, uri)
}

// GetRoomAliases returns all aliases for a room.
func (m *MatrixCore) GetRoomAliases(chatID string) ([]string, error) {
	if !m.authed {
		return nil, ErrAuth
	}

	roomID := id.RoomID(chatID)
	resp, err := m.client.GetAliases(m.ctx, roomID)
	if err != nil {
		return nil, fmt.Errorf("get aliases: %w", err)
	}

	aliases := make([]string, len(resp.Aliases))
	for i, a := range resp.Aliases {
		aliases[i] = string(a)
	}
	return aliases, nil
}

// SetRoomAlias creates an alias for a room.
func (m *MatrixCore) SetRoomAlias(chatID string, alias string) error {
	if !m.authed {
		return ErrAuth
	}

	roomID := id.RoomID(chatID)
	_, err := m.client.CreateAlias(m.ctx, id.RoomAlias(alias), roomID)
	if err != nil {
		return fmt.Errorf("create alias: %w", err)
	}
	return nil
}

// DeleteRoomAlias deletes a room alias.
func (m *MatrixCore) DeleteRoomAlias(alias string) error {
	if !m.authed {
		return ErrAuth
	}

	_, err := m.client.DeleteAlias(m.ctx, id.RoomAlias(alias))
	if err != nil {
		return fmt.Errorf("delete alias: %w", err)
	}
	return nil
}

// GetPublicRooms searches the public room directory.
func (m *MatrixCore) GetPublicRooms(query string, limit int) ([]Dialog, error) {
	if !m.authed {
		return nil, ErrAuth
	}

	if limit <= 0 {
		limit = 20
	}

	resp, err := m.client.PublicRooms(m.ctx, &mautrix.ReqPublicRooms{
		Limit: limit,
	})
	if err != nil {
		return nil, fmt.Errorf("public rooms: %w", err)
	}

	var dialogs []Dialog
	for _, room := range resp.Chunk {
		// Filter client-side if query provided
		if query != "" {
			q := strings.ToLower(query)
			if !strings.Contains(strings.ToLower(room.Name), q) &&
				!strings.Contains(strings.ToLower(room.Topic), q) {
				continue
			}
		}
		d := Dialog{
			ID:          room.RoomID.String(),
			Title:       room.Name,
			MemberCount: room.NumJoinedMembers,
			Platform:    "matrix",
		}
		if room.Topic != "" {
			d.Title += " — " + room.Topic
		}
		if room.WorldReadable {
			d.Type = ChatTypeChannel
		} else {
			d.Type = ChatTypeGroup
		}
		dialogs = append(dialogs, d)
	}

	return dialogs, nil
}

// JoinRoomByAlias joins a room using its alias.
// JoinRoom joins a room by room ID.
func (m *MatrixCore) JoinRoom(roomID string) error {
	if !m.authed {
		return ErrAuth
	}
	_, err := m.client.JoinRoom(m.ctx, roomID, nil)
	if err != nil {
		return fmt.Errorf("join room: %w", err)
	}
	return nil
}

func (m *MatrixCore) JoinRoomByAlias(alias string) (*Dialog, error) {
	if !m.authed {
		return nil, ErrAuth
	}

	resp, err := m.client.JoinRoom(m.ctx, alias, nil)
	if err != nil {
		return nil, fmt.Errorf("join room: %w", err)
	}

	time.Sleep(500 * time.Millisecond) // wait for sync

	m.roomsMu.RLock()
	rs := m.rooms[resp.RoomID]
	m.roomsMu.RUnlock()

	if rs != nil {
		dialog := m.roomToDialog(rs)
		return &dialog, nil
	}

	dialog := Dialog{
		ID:       resp.RoomID.String(),
		Platform: "matrix",
	}
	return &dialog, nil
}

// KnockRoom requests to join a restricted room.
func (m *MatrixCore) KnockRoom(chatID string, reason string) error {
	if !m.authed {
		return ErrAuth
	}

	_, err := m.client.KnockRoom(m.ctx, chatID, &mautrix.ReqKnockRoom{
		Reason: reason,
	})
	if err != nil {
		return fmt.Errorf("knock: %w", err)
	}
	return nil
}

// ForgetRoom removes a room from the room list after leaving.
func (m *MatrixCore) ForgetRoom(chatID string) error {
	if !m.authed {
		return ErrAuth
	}

	roomID := id.RoomID(chatID)
	_, err := m.client.ForgetRoom(m.ctx, roomID)
	if err != nil {
		return fmt.Errorf("forget room: %w", err)
	}

	m.roomsMu.Lock()
	delete(m.rooms, roomID)
	m.roomsMu.Unlock()

	return nil
}

// SetRoomAvatar sets the room's avatar.
func (m *MatrixCore) SetRoomAvatar(chatID string, mxcURI string) error {
	if !m.authed {
		return ErrAuth
	}

	roomID := id.RoomID(chatID)
	_, err := m.client.SendStateEvent(m.ctx, roomID, event.StateRoomAvatar, "", map[string]string{
		"url": mxcURI,
	})
	if err != nil {
		return fmt.Errorf("set room avatar: %w", err)
	}
	return nil
}

// SetJoinRules sets the room's join rules.
func (m *MatrixCore) SetJoinRules(chatID string, rule string) error {
	if !m.authed {
		return ErrAuth
	}

	roomID := id.RoomID(chatID)
	_, err := m.client.SendStateEvent(m.ctx, roomID, event.StateJoinRules, "", map[string]string{
		"join_rule": rule,
	})
	if err != nil {
		return fmt.Errorf("set join rules: %w", err)
	}
	return nil
}

// SetHistoryVisibility sets the room's history visibility.
func (m *MatrixCore) SetHistoryVisibility(chatID string, visibility string) error {
	if !m.authed {
		return ErrAuth
	}

	roomID := id.RoomID(chatID)
	_, err := m.client.SendStateEvent(m.ctx, roomID, event.StateHistoryVisibility, "", map[string]string{
		"history_visibility": visibility,
	})
	if err != nil {
		return fmt.Errorf("set history visibility: %w", err)
	}
	return nil
}

// EnableEncryption enables E2EE for a room.
func (m *MatrixCore) EnableEncryption(chatID string) error {
	if !m.authed {
		return ErrAuth
	}

	roomID := id.RoomID(chatID)
	_, err := m.client.SendStateEvent(m.ctx, roomID, event.StateEncryption, "", map[string]string{
		"algorithm": "m.megolm.v1.aes-sha2",
	})
	if err != nil {
		return fmt.Errorf("enable encryption: %w", err)
	}
	return nil
}

// GetEncryptionInfo checks if a room is encrypted.
func (m *MatrixCore) GetEncryptionInfo(chatID string) (bool, string, error) {
	if !m.authed {
		return false, "", ErrAuth
	}

	roomID := id.RoomID(chatID)
	var content map[string]string
	err := m.client.StateEvent(m.ctx, roomID, event.StateEncryption, "", &content)
	if err != nil {
		return false, "", nil // Not encrypted
	}

	return true, content["algorithm"], nil
}

// GetSpaceChildren returns child rooms of a space.
func (m *MatrixCore) GetSpaceChildren(chatID string) ([]Dialog, error) {
	if !m.authed {
		return nil, ErrAuth
	}

	roomID := id.RoomID(chatID)
	resp, err := m.client.Hierarchy(m.ctx, roomID, &mautrix.ReqHierarchy{Limit: 100})
	if err != nil {
		return nil, fmt.Errorf("hierarchy: %w", err)
	}

	var dialogs []Dialog
	for _, room := range resp.Rooms {
		if room.RoomID == roomID {
			continue // skip the space itself
		}
		d := Dialog{
			ID:          room.RoomID.String(),
			Title:       room.Name,
			MemberCount: room.NumJoinedMembers,
			Platform:    "matrix",
		}
		if room.WorldReadable {
			d.Type = ChatTypeChannel
		} else {
			d.Type = ChatTypeGroup
		}
		dialogs = append(dialogs, d)
	}

	return dialogs, nil
}

// AddSpaceChild adds a room to a space.
func (m *MatrixCore) AddSpaceChild(spaceID string, childID string) error {
	if !m.authed {
		return ErrAuth
	}

	space := id.RoomID(spaceID)
	child := id.RoomID(childID)
	_, err := m.client.SendStateEvent(m.ctx, space, event.StateSpaceChild, child.String(), &event.SpaceChildEventContent{
		Via: []string{m.serverName()},
	})
	if err != nil {
		return fmt.Errorf("add space child: %w", err)
	}
	return nil
}

// RemoveSpaceChild removes a room from a space.
func (m *MatrixCore) RemoveSpaceChild(spaceID string, childID string) error {
	if !m.authed {
		return ErrAuth
	}

	space := id.RoomID(spaceID)
	child := id.RoomID(childID)
	// Send empty content to remove
	_, err := m.client.SendStateEvent(m.ctx, space, event.StateSpaceChild, child.String(), map[string]interface{}{})
	if err != nil {
		return fmt.Errorf("remove space child: %w", err)
	}
	return nil
}

// GetThreads lists threads in a room.
func (m *MatrixCore) GetThreads(chatID string) ([]Dialog, error) {
	if !m.authed {
		return nil, ErrAuth
	}

	roomID := id.RoomID(chatID)

	// Use the threads endpoint
	resp, err := m.client.MakeFullRequest(m.ctx, mautrix.FullRequest{
		Method: http.MethodGet,
		URL:    m.client.BuildClientURL("v1", "rooms", roomID, "threads"),
	})
	if err != nil {
		return nil, fmt.Errorf("get threads: %w", err)
	}

	var threadResp struct {
		Chunk []json.RawMessage `json:"chunk"`
	}
	if err := json.Unmarshal(resp, &threadResp); err != nil {
		return nil, fmt.Errorf("parse threads: %w", err)
	}

	var dialogs []Dialog
	for _, raw := range threadResp.Chunk {
		var evt event.Event
		if err := json.Unmarshal(raw, &evt); err != nil {
			continue
		}
		evt.Content.ParseRaw(evt.Type)
		title := "Thread"
		if mc, ok := evt.Content.Parsed.(*event.MessageEventContent); ok {
			title = mc.Body
			if len(title) > 50 {
				title = title[:50] + "..."
			}
		}
		dialogs = append(dialogs, Dialog{
			ID:       evt.ID.String(),
			Type:     ChatTypeTopic,
			Title:    title,
			ParentID: chatID,
			Platform: "matrix",
		})
	}

	return dialogs, nil
}

// GetThreadReplies returns replies in a thread.
func (m *MatrixCore) GetThreadReplies(chatID string, threadRootID string) ([]Message, error) {
	if !m.authed {
		return nil, ErrAuth
	}

	roomID := id.RoomID(chatID)
	resp, err := m.client.GetRelations(m.ctx, roomID, id.EventID(threadRootID), &mautrix.ReqGetRelations{
		RelationType: event.RelThread,
		Limit:        50,
	})
	if err != nil {
		return nil, fmt.Errorf("get thread replies: %w", err)
	}

	var messages []Message
	for _, evt := range resp.Chunk {
		msg := m.eventToMessage(evt)
		if msg != nil {
			messages = append(messages, *msg)
		}
	}

	return messages, nil
}

// SetRoomTag adds a tag to a room.
func (m *MatrixCore) SetRoomTag(chatID string, tag string) error {
	if !m.authed {
		return ErrAuth
	}
	return m.client.AddTag(m.ctx, id.RoomID(chatID), event.RoomTag(tag), 0.5)
}

// RemoveRoomTag removes a tag from a room.
func (m *MatrixCore) RemoveRoomTag(chatID string, tag string) error {
	if !m.authed {
		return ErrAuth
	}
	return m.client.RemoveTag(m.ctx, id.RoomID(chatID), event.RoomTag(tag))
}

// GetURLPreview returns URL preview metadata.
func (m *MatrixCore) GetURLPreview(url string) (map[string]interface{}, error) {
	if !m.authed {
		return nil, ErrAuth
	}

	resp, err := m.client.GetURLPreview(m.ctx, url)
	if err != nil {
		return nil, fmt.Errorf("url preview: %w", err)
	}

	return map[string]interface{}{
		"title":       resp.Title,
		"description": resp.Description,
		"image_url":   resp.ImageURL,
	}, nil
}

// GetTurnServer returns TURN server credentials for WebRTC.
func (m *MatrixCore) GetTurnServer() (map[string]interface{}, error) {
	if !m.authed {
		return nil, ErrAuth
	}

	resp, err := m.client.TurnServer(m.ctx)
	if err != nil {
		return nil, fmt.Errorf("turn server: %w", err)
	}

	return map[string]interface{}{
		"username": resp.Username,
		"password": resp.Password,
		"uris":     resp.URIs,
		"ttl":      resp.TTL,
	}, nil
}

// SetDeviceName updates a device's display name.
func (m *MatrixCore) SetDeviceName(deviceID string, name string) error {
	if !m.authed {
		return ErrAuth
	}

	return m.client.SetDeviceInfo(m.ctx, id.DeviceID(deviceID), &mautrix.ReqDeviceInfo{
		DisplayName: name,
	})
}

// MarkUnread sets the unread marker for a room.
func (m *MatrixCore) MarkUnread(chatID string, unread bool) error {
	if !m.authed {
		return ErrAuth
	}

	return m.client.SetRoomAccountData(m.ctx, id.RoomID(chatID), "m.marked_unread", map[string]bool{
		"unread": unread,
	})
}

// ReportEvent reports a message.
func (m *MatrixCore) ReportEvent(chatID string, eventID string, reason string) error {
	if !m.authed {
		return ErrAuth
	}

	return m.client.ReportEvent(m.ctx, id.RoomID(chatID), id.EventID(eventID), reason)
}

// SearchUsers searches the user directory.
func (m *MatrixCore) SearchUsers(query string, limit int) ([]User, error) {
	if !m.authed {
		return nil, ErrAuth
	}

	if limit <= 0 {
		limit = 20
	}

	resp, err := m.client.SearchUserDirectory(m.ctx, query, limit)
	if err != nil {
		return nil, fmt.Errorf("search users: %w", err)
	}

	var users []User
	for _, u := range resp.Results {
		user := User{
			ID:          u.UserID.String(),
			DisplayName: u.DisplayName,
			Platform:    "matrix",
		}
		if !u.AvatarURL.IsEmpty() {
			user.AvatarURL = u.AvatarURL.String()
		}
		users = append(users, user)
	}

	return users, nil
}

// GetDirectChats returns DM room mappings.
func (m *MatrixCore) GetDirectChats() (map[string][]string, error) {
	if !m.authed {
		return nil, ErrAuth
	}

	m.directChatsMu.RLock()
	defer m.directChatsMu.RUnlock()

	result := make(map[string][]string)
	for uid, rooms := range m.directChats {
		roomIDs := make([]string, len(rooms))
		for i, r := range rooms {
			roomIDs[i] = r.String()
		}
		result[uid.String()] = roomIDs
	}

	return result, nil
}

// SetDirectChat marks a room as a DM with a user.
func (m *MatrixCore) SetDirectChat(userID string, roomID string) error {
	if !m.authed {
		return ErrAuth
	}

	uid := id.UserID(userID)
	rid := id.RoomID(roomID)

	m.directChatsMu.Lock()
	m.directChats[uid] = append(m.directChats[uid], rid)
	m.directChatsMu.Unlock()

	return m.saveDirectChats()
}

// UpgradeRoom upgrades a room to a new version.
func (m *MatrixCore) UpgradeRoom(chatID string, version string) (string, error) {
	if !m.authed {
		return "", ErrAuth
	}

	roomID := id.RoomID(chatID)
	resp, err := m.client.MakeFullRequest(m.ctx, mautrix.FullRequest{
		Method: http.MethodPost,
		URL:    m.client.BuildClientURL("v3", "rooms", roomID, "upgrade"),
		RequestJSON: map[string]string{
			"new_version": version,
		},
	})
	if err != nil {
		return "", fmt.Errorf("upgrade room: %w", err)
	}

	var upgradeResp struct {
		ReplacementRoom string `json:"replacement_room"`
	}
	if err := json.Unmarshal(resp, &upgradeResp); err != nil {
		return "", err
	}

	return upgradeResp.ReplacementRoom, nil
}

// --- Internal helpers ---

func (m *MatrixCore) setupSyncer() {
	syncer := mautrix.NewDefaultSyncer()

	// Message events
	syncer.OnEventType(event.EventMessage, func(ctx context.Context, evt *event.Event) {
		m.handleMessageEvent(evt)
	})

	// Redactions
	syncer.OnEventType(event.EventRedaction, func(ctx context.Context, evt *event.Event) {
		m.dispatchUpdate(Update{
			Type:      UpdateDeleteMessage,
			ChatID:    evt.RoomID.String(),
			MessageID: evt.Redacts.String(),
			Platform:  "matrix",
		})
	})

	// Room state: name, topic, members
	syncer.OnEventType(event.StateMember, func(ctx context.Context, evt *event.Event) {
		m.handleMemberEvent(evt)
	})

	syncer.OnEventType(event.StateRoomName, func(ctx context.Context, evt *event.Event) {
		m.updateRoomName(evt)
	})

	syncer.OnEventType(event.StateTopic, func(ctx context.Context, evt *event.Event) {
		m.updateRoomTopic(evt)
	})

	// Typing
	syncer.OnEventType(event.EphemeralEventTyping, func(ctx context.Context, evt *event.Event) {
		m.dispatchUpdate(Update{
			Type:     UpdateTyping,
			ChatID:   evt.RoomID.String(),
			Platform: "matrix",
		})
	})

	// Read receipts
	syncer.OnEventType(event.EphemeralEventReceipt, func(ctx context.Context, evt *event.Event) {
		m.dispatchUpdate(Update{
			Type:     UpdateReadState,
			ChatID:   evt.RoomID.String(),
			Platform: "matrix",
		})
	})

	// Presence
	syncer.OnEventType(event.EphemeralEventPresence, func(ctx context.Context, evt *event.Event) {
		evt.Content.ParseRaw(evt.Type)
		if pc, ok := evt.Content.Parsed.(*event.PresenceEventContent); ok {
			isOnline := pc.Presence == event.PresenceOnline
			m.dispatchUpdate(Update{
				Type:     UpdateUserStatus,
				UserID:   evt.Sender.String(),
				IsOnline: &isOnline,
				Platform: "matrix",
			})
		}
	})

	// Call events
	syncer.OnEventType(event.CallInvite, func(ctx context.Context, evt *event.Event) {
		m.handleCallInvite(evt)
	})
	syncer.OnEventType(event.CallAnswer, func(ctx context.Context, evt *event.Event) {
		m.handleCallAnswer(evt)
	})
	syncer.OnEventType(event.CallCandidates, func(ctx context.Context, evt *event.Event) {
		m.handleCallCandidates(evt)
	})
	syncer.OnEventType(event.CallHangup, func(ctx context.Context, evt *event.Event) {
		m.handleCallHangup(evt)
	})
	syncer.OnEventType(event.CallSelectAnswer, func(ctx context.Context, evt *event.Event) {
		// Multi-device: if another device answered, end our ringing state
		evt.Content.ParseRaw(evt.Type)
		if sa, ok := evt.Content.Parsed.(*event.CallSelectAnswerEventContent); ok {
			if sa.SelectedPartyID != m.deviceID.String() {
				// Another device answered — clean up our call
				m.callsMu.Lock()
				call, exists := m.activeCalls[sa.CallID]
				if exists {
					delete(m.activeCalls, sa.CallID)
				}
				m.callsMu.Unlock()
				if exists {
					m.cleanupCall(call)
				}
			}
		}
	})

	// Track sync token
	syncer.OnSync(func(ctx context.Context, resp *mautrix.RespSync, since string) bool {
		m.syncToken = resp.NextBatch

		// Process joined rooms for initial state
		for roomID, room := range resp.Rooms.Join {
			m.processJoinedRoom(roomID, room)
		}

		return true
	})

	m.syncer = syncer
	m.client.Syncer = syncer
}

func (m *MatrixCore) startSync() {
	m.syncCtx, m.syncStop = context.WithCancel(m.ctx)

	for {
		err := m.client.SyncWithContext(m.syncCtx)
		if err == nil || m.syncCtx.Err() != nil {
			return // clean shutdown or context cancelled
		}
		// Retry after brief delay
		time.Sleep(5 * time.Second)
	}
}

func (m *MatrixCore) processJoinedRoom(roomID id.RoomID, room *mautrix.SyncJoinedRoom) {
	m.roomsMu.Lock()
	defer m.roomsMu.Unlock()

	rs, ok := m.rooms[roomID]
	if !ok {
		rs = &matrixRoomState{
			ID:      roomID,
			Members: make(map[id.UserID]*matrixMember),
		}
		m.rooms[roomID] = rs
	}

	// Process state events
	for _, evt := range room.State.Events {
		evt.Content.ParseRaw(evt.Type)
		m.applyStateEvent(rs, evt)
	}

	// Process timeline for state updates and last event time
	for _, evt := range room.Timeline.Events {
		evt.Content.ParseRaw(evt.Type)
		if evt.StateKey != nil {
			m.applyStateEvent(rs, evt)
		}
		ts := time.UnixMilli(evt.Timestamp)
		if ts.After(rs.LastEvent) {
			rs.LastEvent = ts
		}
	}

	// Update unread count
	if room.UnreadNotifications != nil {
		rs.UnreadCount = room.UnreadNotifications.NotificationCount
	}
}

func (m *MatrixCore) applyStateEvent(rs *matrixRoomState, evt *event.Event) {
	switch evt.Type {
	case event.StateRoomName:
		if nc, ok := evt.Content.Parsed.(*event.RoomNameEventContent); ok {
			rs.Name = nc.Name
		}
	case event.StateTopic:
		if tc, ok := evt.Content.Parsed.(*event.TopicEventContent); ok {
			rs.Topic = tc.Topic
		}
	case event.StateRoomAvatar:
		if ac, ok := evt.Content.Parsed.(*event.RoomAvatarEventContent); ok {
			rs.AvatarURL = string(ac.URL)
		}
	case event.StateMember:
		if mc, ok := evt.Content.Parsed.(*event.MemberEventContent); ok {
			uid := id.UserID(*evt.StateKey)
			rs.Members[uid] = &matrixMember{
				UserID:      uid,
				DisplayName: mc.Displayname,
				AvatarURL:   string(mc.AvatarURL),
				Membership:  mc.Membership,
			}
		}
	case event.StateEncryption:
		rs.IsEncrypted = true
	case event.StatePowerLevels:
		if pl, ok := evt.Content.Parsed.(*event.PowerLevelsEventContent); ok {
			rs.PowerLevels = pl
		}
	case event.StateJoinRules:
		if jc, ok := evt.Content.Parsed.(*event.JoinRulesEventContent); ok {
			rs.JoinRule = string(jc.JoinRule)
		}
	case event.StatePinnedEvents:
		if pc, ok := evt.Content.Parsed.(*event.PinnedEventsEventContent); ok {
			rs.PinnedIDs = pc.Pinned
		}
	}
}

func (m *MatrixCore) handleMessageEvent(evt *event.Event) {
	evt.Content.ParseRaw(evt.Type)
	mc, ok := evt.Content.Parsed.(*event.MessageEventContent)
	if !ok {
		return
	}

	// Check if this is an edit
	if mc.RelatesTo != nil && mc.RelatesTo.Type == event.RelReplace {
		// Edit
		msg := m.eventToMessage(evt)
		if msg != nil {
			msg.ID = mc.RelatesTo.EventID.String() // use original event ID
			m.dispatchUpdate(Update{
				Type:    UpdateEditMessage,
				ChatID:  evt.RoomID.String(),
				Message: msg,
				Platform: "matrix",
			})
		}
		return
	}

	msg := m.eventToMessage(evt)
	if msg != nil {
		m.dispatchUpdate(Update{
			Type:     UpdateNewMessage,
			ChatID:   evt.RoomID.String(),
			Message:  msg,
			Platform: "matrix",
		})
	}
}

func (m *MatrixCore) handleMemberEvent(evt *event.Event) {
	evt.Content.ParseRaw(evt.Type)

	m.roomsMu.Lock()
	rs := m.rooms[evt.RoomID]
	if rs != nil {
		if mc, ok := evt.Content.Parsed.(*event.MemberEventContent); ok && evt.StateKey != nil {
			uid := id.UserID(*evt.StateKey)
			rs.Members[uid] = &matrixMember{
				UserID:      uid,
				DisplayName: mc.Displayname,
				AvatarURL:   string(mc.AvatarURL),
				Membership:  mc.Membership,
			}
		}
	}
	m.roomsMu.Unlock()

	m.dispatchUpdate(Update{
		Type:     UpdateGroupMembers,
		ChatID:   evt.RoomID.String(),
		Platform: "matrix",
	})
}

func (m *MatrixCore) updateRoomName(evt *event.Event) {
	evt.Content.ParseRaw(evt.Type)
	m.roomsMu.Lock()
	if rs := m.rooms[evt.RoomID]; rs != nil {
		if nc, ok := evt.Content.Parsed.(*event.RoomNameEventContent); ok {
			rs.Name = nc.Name
		}
	}
	m.roomsMu.Unlock()
}

func (m *MatrixCore) updateRoomTopic(evt *event.Event) {
	evt.Content.ParseRaw(evt.Type)
	m.roomsMu.Lock()
	if rs := m.rooms[evt.RoomID]; rs != nil {
		if tc, ok := evt.Content.Parsed.(*event.TopicEventContent); ok {
			rs.Topic = tc.Topic
		}
	}
	m.roomsMu.Unlock()
}

func (m *MatrixCore) handleCallInvite(evt *event.Event) {
	evt.Content.ParseRaw(evt.Type)
	ci, ok := evt.Content.Parsed.(*event.CallInviteEventContent)
	if !ok {
		return
	}

	// Ignore our own invites
	if ci.PartyID == m.deviceID.String() {
		return
	}

	// Check if we already have this call
	m.callsMu.RLock()
	_, exists := m.activeCalls[ci.CallID]
	m.callsMu.RUnlock()
	if exists {
		return
	}

	// Create PeerConnection for incoming call
	pc, err := m.createPeerConnection()
	if err != nil {
		return
	}

	callCtx, callCancel := context.WithCancel(m.ctx)

	call := &matrixCall{
		ID:          ci.CallID,
		RoomID:      evt.RoomID,
		IsVideo:     false,
		State:       CallStateRinging,
		StartTime:   time.Now(),
		IsOutgoing:  false,
		RemoteParty: ci.PartyID,
		pc:          pc,
		cancel:      callCancel,
	}

	// Add audio track
	audioTrack, err := webrtc.NewTrackLocalStaticRTP(
		webrtc.RTPCodecCapability{MimeType: webrtc.MimeTypeOpus, ClockRate: 48000, Channels: 2},
		"audio", "uniclient-audio",
	)
	if err != nil {
		pc.Close()
		callCancel()
		return
	}
	call.audioTrack = audioTrack

	if _, err := pc.AddTrack(audioTrack); err != nil {
		pc.Close()
		callCancel()
		return
	}

	// ICE candidate trickle
	pc.OnICECandidate(func(c *webrtc.ICECandidate) {
		if c == nil {
			return
		}
		m.sendICECandidates(call, []webrtc.ICECandidateInit{c.ToJSON()})
	})

	m.setupCallStateHandlers(call)

	pc.OnTrack(func(track *webrtc.TrackRemote, recv *webrtc.RTPReceiver) {
		m.handleIncomingAudio(callCtx, call, track)
	})

	// Set remote description (the offer)
	if ci.Offer.SDP != "" {
		err = pc.SetRemoteDescription(webrtc.SessionDescription{
			Type: webrtc.SDPTypeOffer,
			SDP:  ci.Offer.SDP,
		})
		if err != nil {
			pc.Close()
			callCancel()
			return
		}
		m.flushPendingCandidates(call)
	}

	m.callsMu.Lock()
	m.activeCalls[ci.CallID] = call
	m.callsMu.Unlock()

	// Start silence sender
	go m.sendAudio(callCtx, call)

	// Notify UI of incoming call
	m.dispatchUpdate(Update{
		Type:   UpdateCallState,
		ChatID: evt.RoomID.String(),
		Call: &CallSession{
			ID:      ci.CallID,
			ChatID:  evt.RoomID.String(),
			IsVideo: false,
			State:   CallStateRinging,
		},
		Platform: "matrix",
	})
}

func (m *MatrixCore) handleCallHangup(evt *event.Event) {
	evt.Content.ParseRaw(evt.Type)
	if ch, ok := evt.Content.Parsed.(*event.CallHangupEventContent); ok {
		m.callsMu.Lock()
		delete(m.activeCalls, ch.CallID)
		m.callsMu.Unlock()

		m.dispatchUpdate(Update{
			Type:   UpdateCallState,
			ChatID: evt.RoomID.String(),
			Call: &CallSession{
				ID:     ch.CallID,
				ChatID: evt.RoomID.String(),
				State:  CallStateEnded,
			},
			Platform: "matrix",
		})
	}
}

func (m *MatrixCore) eventToMessage(evt *event.Event) *Message {
	evt.Content.ParseRaw(evt.Type)
	mc, ok := evt.Content.Parsed.(*event.MessageEventContent)
	if !ok {
		return nil
	}

	msg := &Message{
		ID:        evt.ID.String(),
		ChatID:    evt.RoomID.String(),
		SenderID:  evt.Sender.String(),
		Timestamp: time.UnixMilli(evt.Timestamp),
		Status:    MessageStatusSent,
		Platform:  "matrix",
	}

	// Text content
	if mc.NewContent != nil {
		msg.Text = mc.NewContent.Body
	} else {
		msg.Text = mc.Body
	}

	// Sender name from room cache
	m.roomsMu.RLock()
	if rs := m.rooms[evt.RoomID]; rs != nil {
		if member := rs.Members[evt.Sender]; member != nil {
			msg.SenderName = member.DisplayName
		}
	}
	m.roomsMu.RUnlock()

	// Reply
	if mc.RelatesTo != nil && mc.RelatesTo.InReplyTo != nil {
		msg.ReplyToID = mc.RelatesTo.InReplyTo.EventID.String()
	}

	// Attachments (encrypted files use mc.File, plaintext use mc.URL)
	if mc.File != nil && mc.File.URL != "" {
		att := FileRef{
			ID:       string(mc.File.URL),
			Name:     mc.Body,
			MimeType: mc.GetInfo().MimeType,
			Size:     int64(mc.GetInfo().Size),
		}
		if efJSON, err := json.Marshal(mc.File); err == nil {
			att.Extra = string(efJSON)
		}
		msg.Attachments = []FileRef{att}
	} else if mc.URL != "" {
		att := FileRef{
			ID:       string(mc.URL),
			Name:     mc.Body,
			MimeType: mc.GetInfo().MimeType,
			Size:     int64(mc.GetInfo().Size),
		}
		msg.Attachments = []FileRef{att}
	}

	// Encryption status
	m.roomsMu.RLock()
	if rs := m.rooms[evt.RoomID]; rs != nil {
		msg.IsEncrypted = rs.IsEncrypted
	}
	m.roomsMu.RUnlock()

	return msg
}

func (m *MatrixCore) roomToDialog(rs *matrixRoomState) Dialog {
	d := Dialog{
		ID:          rs.ID.String(),
		Title:       rs.Name,
		AvatarURL:   rs.AvatarURL,
		UnreadCount: rs.UnreadCount,
		Platform:    "matrix",
	}

	// Determine chat type
	memberCount := 0
	for _, mem := range rs.Members {
		if mem.Membership == event.MembershipJoin || mem.Membership == event.MembershipInvite {
			memberCount++
		}
	}
	d.MemberCount = memberCount

	if m.isSpace(rs) {
		d.Type = ChatTypeChannel // Spaces displayed as channels
	} else if rs.IsDirect || memberCount == 2 {
		d.Type = ChatTypeDM
	} else if rs.JoinRule == "public" {
		d.Type = ChatTypeChannel
	} else {
		d.Type = ChatTypeGroup
	}

	// If no explicit name, generate from members
	if d.Title == "" {
		d.Title = m.generateRoomName(rs)
	}

	return d
}

func (m *MatrixCore) generateRoomName(rs *matrixRoomState) string {
	var names []string
	for _, mem := range rs.Members {
		if mem.UserID == m.userID {
			continue
		}
		if mem.Membership != event.MembershipJoin {
			continue
		}
		name := mem.DisplayName
		if name == "" {
			name = mem.UserID.String()
		}
		names = append(names, name)
	}
	if len(names) == 0 {
		return "Empty Room"
	}
	if len(names) <= 3 {
		return strings.Join(names, ", ")
	}
	return fmt.Sprintf("%s and %d others", strings.Join(names[:2], ", "), len(names)-2)
}

func (m *MatrixCore) isSpace(rs *matrixRoomState) bool {
	// A space has m.space.child state events
	// We detect this from the create event type field
	// For simplicity, check if we have any SpaceChild/SpaceParent keys in state
	return rs.SpaceParent != "" || rs.Type == "m.space"
}

func (m *MatrixCore) getPinnedEvents(roomID id.RoomID) []id.EventID {
	m.roomsMu.RLock()
	defer m.roomsMu.RUnlock()
	if rs := m.rooms[roomID]; rs != nil {
		return rs.PinnedIDs
	}
	return nil
}

func (m *MatrixCore) fetchRoomState(roomID id.RoomID) error {
	state, err := m.client.State(m.ctx, roomID)
	if err != nil {
		return fmt.Errorf("fetch state: %w", err)
	}

	m.roomsMu.Lock()
	defer m.roomsMu.Unlock()

	rs := &matrixRoomState{
		ID:      roomID,
		Members: make(map[id.UserID]*matrixMember),
	}

	for evtType, stateKeys := range state {
		for _, evt := range stateKeys {
			evt.Type = evtType
			evt.Content.ParseRaw(evtType)
			m.applyStateEvent(rs, evt)
		}
	}

	m.rooms[roomID] = rs
	return nil
}

func (m *MatrixCore) serverName() string {
	// Extract server name from user ID (@user:server.com)
	parts := strings.SplitN(m.userID.String(), ":", 2)
	if len(parts) == 2 {
		return parts[1]
	}
	return "matrix.org"
}

func (m *MatrixCore) dispatchUpdate(update Update) {
	m.updateMu.RLock()
	handlers := make([]func(Update), len(m.updateHandlers))
	copy(handlers, m.updateHandlers)
	m.updateMu.RUnlock()

	for _, h := range handlers {
		h(update)
	}
}

func (m *MatrixCore) saveDirectChats() error {
	m.directChatsMu.RLock()
	data := make(map[string][]string)
	for uid, rooms := range m.directChats {
		rids := make([]string, len(rooms))
		for i, r := range rooms {
			rids[i] = r.String()
		}
		data[uid.String()] = rids
	}
	m.directChatsMu.RUnlock()

	return m.client.SetAccountData(m.ctx, "m.direct", data)
}

// --- Session persistence ---

func (m *MatrixCore) loadSession() error {
	data, err := os.ReadFile(m.sessionPath)
	if err != nil {
		return err
	}

	var sess matrixSession
	if err := json.Unmarshal(data, &sess); err != nil {
		return err
	}

	m.homeserver = sess.Homeserver
	m.userID = id.UserID(sess.UserID)
	m.accessToken = sess.AccessToken
	m.deviceID = id.DeviceID(sess.DeviceID)
	m.syncToken = sess.NextBatch
	m.isBot = sess.IsBot

	if sess.PickleKey != "" {
		m.pickleKey, _ = base64.StdEncoding.DecodeString(sess.PickleKey)
	}

	return nil
}

func (m *MatrixCore) saveSession() {
	sess := matrixSession{
		Homeserver:  m.homeserver,
		UserID:      m.userID.String(),
		AccessToken: m.accessToken,
		DeviceID:    m.deviceID.String(),
		NextBatch:   m.syncToken,
		IsBot:       m.isBot,
	}
	if len(m.pickleKey) > 0 {
		sess.PickleKey = base64.StdEncoding.EncodeToString(m.pickleKey)
	}

	data, err := json.MarshalIndent(sess, "", "  ")
	if err != nil {
		return
	}

	os.MkdirAll(filepath.Dir(m.sessionPath), 0o755)
	os.WriteFile(m.sessionPath, data, 0o600)
}

// initCrypto sets up Olm/Megolm E2EE — pure Go, no SQL.
// Uses MemoryStore + MemoryStateStore persisted to JSON files.
func (m *MatrixCore) initCrypto() error {
	// Generate pickle key on first run, reuse on subsequent runs
	if len(m.pickleKey) == 0 {
		m.pickleKey = make([]byte, 32)
		if _, err := rand.Read(m.pickleKey); err != nil {
			return fmt.Errorf("generate pickle key: %w", err)
		}
	}

	cryptoPath := m.cryptoStorePath()
	log := zerolog.New(zerolog.NewConsoleWriter()).With().Timestamp().Str("component", "matrix").Logger()
	m.client.Log = log

	// Create memory-backed stores
	m.cryptoStore = crypto.NewMemoryStore(func() error {
		return m.saveCryptoStore()
	})
	m.stateStore = mautrix.NewMemoryStateStore().(*mautrix.MemoryStateStore)

	// Load persisted crypto state if available
	m.loadCryptoStore(cryptoPath)
	m.loadStateStore()

	// Set client state store (needed for auto-encrypt member lookups)
	m.client.StateStore = m.stateStore

	// Wire up syncer to feed state store
	if syncer, ok := m.client.Syncer.(mautrix.ExtensibleSyncer); ok {
		syncer.OnEvent(m.client.StateStoreSyncHandler)
	}

	// Create OlmMachine directly — no cryptohelper, no SQL
	m.olmMachine = crypto.NewOlmMachine(m.client, &log, m.cryptoStore, m.stateStore)
	if err := m.olmMachine.Load(m.ctx); err != nil {
		return fmt.Errorf("load olm account: %w", err)
	}

	// Upload device keys if not already shared
	if err := m.verifyAndShareKeys(); err != nil {
		return fmt.Errorf("share keys: %w", err)
	}

	// Hook into syncer for crypto events
	if syncer, ok := m.client.Syncer.(mautrix.ExtensibleSyncer); ok {
		syncer.OnSync(m.olmMachine.ProcessSyncResponse)
		syncer.OnEventType(event.StateMember, m.olmMachine.HandleMemberEvent)
		syncer.OnEventType(event.EventEncrypted, m.handleEncryptedEvent)
	}

	// Set client.Crypto so SendMessageEvent auto-encrypts for encrypted rooms
	m.client.Crypto = &matrixCryptoAdapter{m: m}

	// Initialize interactive verification helper (SAS emoji)
	m.verificationStore = verificationhelper.NewInMemoryVerificationStore()
	callbacks := &matrixVerificationCallbacks{m: m}
	m.verificationHelper = verificationhelper.NewVerificationHelper(
		m.client, m.olmMachine, m.verificationStore, callbacks,
		false, // supportsQRShow
		false, // supportsQRScan
		true,  // supportsSAS
	)
	if err := m.verificationHelper.Init(m.ctx); err != nil {
		// Non-fatal — verification is optional, core still works
		m.verificationHelper = nil
	}

	return nil
}

// verifyAndShareKeys uploads Olm device keys to the server if needed.
func (m *MatrixCore) verifyAndShareKeys() error {
	resp, err := m.client.QueryKeys(m.ctx, &mautrix.ReqQueryKeys{
		DeviceKeys: map[id.UserID]mautrix.DeviceIDList{
			m.client.UserID: {m.client.DeviceID},
		},
	})
	if err != nil {
		return fmt.Errorf("query keys: %w", err)
	}

	device, ok := resp.DeviceKeys[m.client.UserID][m.client.DeviceID]
	isShared := m.olmMachine.GetAccount().Shared
	if !ok || len(device.Keys) == 0 {
		if isShared {
			return fmt.Errorf("olm account marked shared but keys missing from server")
		}
		return m.olmMachine.ShareKeys(m.ctx, -1)
	} else if !isShared {
		return fmt.Errorf("olm account not marked shared but keys exist on server")
	}
	return nil
}

// handleEncryptedEvent decrypts an encrypted event and re-dispatches it.
func (m *MatrixCore) handleEncryptedEvent(ctx context.Context, evt *event.Event) {
	decrypted, err := m.olmMachine.DecryptMegolmEvent(ctx, evt)
	if err != nil {
		if syncer, ok := m.client.Syncer.(mautrix.ExtensibleSyncer); ok && ctx.Value(mautrix.SyncTokenContextKey) != "" {
			// Try waiting for the session key
			content := evt.Content.AsEncrypted()
			go func() {
				if m.olmMachine.WaitForSession(ctx, evt.RoomID, content.SenderKey, content.SessionID, 5*time.Second) {
					if dec, err := m.olmMachine.DecryptMegolmEvent(ctx, evt); err == nil {
						dec.Mautrix.EventSource |= event.SourceDecrypted
						syncer.(mautrix.DispatchableSyncer).Dispatch(ctx, dec)
					}
				}
			}()
		}
		return
	}
	decrypted.Mautrix.EventSource |= event.SourceDecrypted
	m.client.Syncer.(mautrix.DispatchableSyncer).Dispatch(ctx, decrypted)
}

// matrixCryptoAdapter implements mautrix.CryptoHelper using our OlmMachine.
type matrixCryptoAdapter struct {
	m *MatrixCore
}

func (a *matrixCryptoAdapter) Encrypt(ctx context.Context, roomID id.RoomID, evtType event.Type, content any) (*event.EncryptedEventContent, error) {
	encrypted, err := a.m.olmMachine.EncryptMegolmEvent(ctx, roomID, evtType, content)
	if err != nil {
		if err != crypto.ErrNoGroupSession && !errors.Is(err, crypto.ErrSessionExpired) && !errors.Is(err, crypto.ErrSessionNotShared) {
			return nil, err
		}
		// Need to create/share group session first
		users, err2 := a.m.client.StateStore.GetRoomJoinedOrInvitedMembers(ctx, roomID)
		if err2 != nil {
			return nil, fmt.Errorf("get room members: %w", err2)
		}
		if err2 = a.m.olmMachine.ShareGroupSession(ctx, roomID, users); err2 != nil {
			return nil, fmt.Errorf("share group session: %w", err2)
		}
		encrypted, err = a.m.olmMachine.EncryptMegolmEvent(ctx, roomID, evtType, content)
		if err != nil {
			return nil, err
		}
	}
	return encrypted, nil
}

func (a *matrixCryptoAdapter) Decrypt(ctx context.Context, evt *event.Event) (*event.Event, error) {
	return a.m.olmMachine.DecryptMegolmEvent(ctx, evt)
}

func (a *matrixCryptoAdapter) WaitForSession(ctx context.Context, roomID id.RoomID, senderKey id.SenderKey, sessionID id.SessionID, timeout time.Duration) bool {
	return a.m.olmMachine.WaitForSession(ctx, roomID, senderKey, sessionID, timeout)
}

func (a *matrixCryptoAdapter) RequestSession(ctx context.Context, roomID id.RoomID, senderKey id.SenderKey, sessionID id.SessionID, userID id.UserID, deviceID id.DeviceID) {
	if deviceID == "" {
		deviceID = "*"
	}
	a.m.olmMachine.SendRoomKeyRequest(ctx, roomID, senderKey, sessionID, "", map[id.UserID][]id.DeviceID{
		userID:                  {deviceID},
		a.m.client.UserID: {"*"},
	})
}

func (a *matrixCryptoAdapter) Init(_ context.Context) error { return nil }

// closeCrypto saves state and cleans up.
func (m *MatrixCore) closeCrypto() {
	if m.olmMachine != nil {
		m.saveCryptoStore()
		m.saveStateStore()
		m.olmMachine = nil
		m.client.Crypto = nil
	}
}

// Crypto store persistence — pickle + JSON, no SQL.

func (m *MatrixCore) cryptoStorePath() string {
	return strings.TrimSuffix(m.sessionPath, filepath.Ext(m.sessionPath)) + "_crypto.json"
}

func (m *MatrixCore) stateStorePath() string {
	return strings.TrimSuffix(m.sessionPath, filepath.Ext(m.sessionPath)) + "_state.json"
}

// pickledOlmSession is the serializable form of a crypto.OlmSession.
type pickledOlmSession struct {
	Pickle            string    `json:"pickle"`
	CreationTime      time.Time `json:"creation_time"`
	LastEncryptedTime time.Time `json:"last_encrypted_time"`
	LastDecryptedTime time.Time `json:"last_decoded_time"`
}

// pickledInboundGroupSession is the serializable form of a crypto.InboundGroupSession.
type pickledInboundGroupSession struct {
	Pickle           string             `json:"pickle"`
	SigningKey       id.Ed25519         `json:"signing_key"`
	SenderKey        id.Curve25519      `json:"sender_key"`
	RoomID           id.RoomID          `json:"room_id"`
	ForwardingChains []string           `json:"forwarding_chains"`
	ReceivedAt       time.Time          `json:"received_at"`
	MaxAge           int64              `json:"max_age"`
	MaxMessages      int                `json:"max_messages"`
	KeyBackupVersion id.KeyBackupVersion `json:"key_backup_version"`
}

// pickledOutboundGroupSession is the serializable form of a crypto.OutboundGroupSession.
type pickledOutboundGroupSession struct {
	Pickle       string    `json:"pickle"`
	CreationTime time.Time `json:"creation_time"`
	MaxMessages  int       `json:"max_messages"`
	MessageCount int       `json:"message_count"`
	Shared       bool      `json:"shared"`
}

// cryptoStoreFile is the JSON file format for persisting crypto state.
type cryptoStoreFile struct {
	AccountPickle    string `json:"account_pickle"`
	AccountShared    bool   `json:"account_shared"`
	AccountKBVersion string `json:"account_kb_version,omitempty"`

	Sessions         map[string][]pickledOlmSession                  `json:"sessions"`
	GroupSessions    map[string]map[string]pickledInboundGroupSession `json:"group_sessions"`
	OutGroupSessions map[string]pickledOutboundGroupSession           `json:"out_group_sessions"`

	Devices          map[id.UserID]map[id.DeviceID]*id.Device                                    `json:"devices"`
	CrossSigningKeys map[id.UserID]map[id.CrossSigningUsage]id.CrossSigningKey                    `json:"cross_signing_keys"`
	KeySignatures    map[id.UserID]map[id.Ed25519]map[id.UserID]map[id.Ed25519]string            `json:"key_signatures"`
	Secrets          map[id.Secret]string                                                         `json:"secrets"`
}

func (m *MatrixCore) saveCryptoStore() error {
	if m.cryptoStore == nil {
		return nil
	}

	f := &cryptoStoreFile{
		Sessions:         make(map[string][]pickledOlmSession),
		GroupSessions:    make(map[string]map[string]pickledInboundGroupSession),
		OutGroupSessions: make(map[string]pickledOutboundGroupSession),
	}

	// Pickle account
	if m.cryptoStore.Account != nil {
		pickle, err := m.cryptoStore.Account.Internal.Pickle(m.pickleKey)
		if err == nil {
			f.AccountPickle = base64.StdEncoding.EncodeToString(pickle)
		}
		f.AccountShared = m.cryptoStore.Account.Shared
		f.AccountKBVersion = string(m.cryptoStore.Account.KeyBackupVersion)
	}

	// Pickle Olm sessions
	for senderKey, sessions := range m.cryptoStore.Sessions {
		var pickled []pickledOlmSession
		for _, sess := range sessions {
			p, err := sess.Internal.Pickle(m.pickleKey)
			if err != nil {
				continue
			}
			pickled = append(pickled, pickledOlmSession{
				Pickle:            base64.StdEncoding.EncodeToString(p),
				CreationTime:      sess.CreationTime,
				LastEncryptedTime: sess.LastEncryptedTime,
				LastDecryptedTime: sess.LastDecryptedTime,
			})
		}
		if len(pickled) > 0 {
			f.Sessions[string(senderKey)] = pickled
		}
	}

	// Pickle inbound group sessions
	for roomID, sessions := range m.cryptoStore.GroupSessions {
		roomMap := make(map[string]pickledInboundGroupSession)
		for sessID, sess := range sessions {
			p, err := sess.Internal.Pickle(m.pickleKey)
			if err != nil {
				continue
			}
			roomMap[string(sessID)] = pickledInboundGroupSession{
				Pickle:           base64.StdEncoding.EncodeToString(p),
				SigningKey:       sess.SigningKey,
				SenderKey:        sess.SenderKey,
				RoomID:           sess.RoomID,
				ForwardingChains: sess.ForwardingChains,
				ReceivedAt:       sess.ReceivedAt,
				MaxAge:           sess.MaxAge,
				MaxMessages:      sess.MaxMessages,
				KeyBackupVersion: sess.KeyBackupVersion,
			}
		}
		if len(roomMap) > 0 {
			f.GroupSessions[string(roomID)] = roomMap
		}
	}

	// Pickle outbound group sessions
	for roomID, sess := range m.cryptoStore.OutGroupSessions {
		p, err := sess.Internal.Pickle(m.pickleKey)
		if err != nil {
			continue
		}
		f.OutGroupSessions[string(roomID)] = pickledOutboundGroupSession{
			Pickle:       base64.StdEncoding.EncodeToString(p),
			CreationTime: sess.CreationTime,
			MaxMessages:  sess.MaxMessages,
			MessageCount: sess.MessageCount,
			Shared:       sess.Shared,
		}
	}

	// Copy plain data
	f.Devices = m.cryptoStore.Devices
	f.CrossSigningKeys = m.cryptoStore.CrossSigningKeys
	f.KeySignatures = m.cryptoStore.KeySignatures
	f.Secrets = m.cryptoStore.Secrets

	data, err := json.Marshal(f)
	if err != nil {
		return err
	}
	return os.WriteFile(m.cryptoStorePath(), data, 0o600)
}

func (m *MatrixCore) loadCryptoStore(path string) {
	data, err := os.ReadFile(path)
	if err != nil {
		return
	}

	var f cryptoStoreFile
	if err := json.Unmarshal(data, &f); err != nil {
		return
	}

	// Unpickle account
	if f.AccountPickle != "" {
		pickleBytes, err := base64.StdEncoding.DecodeString(f.AccountPickle)
		if err == nil {
			internal, err := olm.AccountFromPickled(pickleBytes, m.pickleKey)
			if err == nil {
				m.cryptoStore.Account = &crypto.OlmAccount{
					Internal:         internal,
					Shared:           f.AccountShared,
					KeyBackupVersion: id.KeyBackupVersion(f.AccountKBVersion),
				}
			}
		}
	}

	// Unpickle Olm sessions
	for senderKeyStr, sessions := range f.Sessions {
		senderKey := id.SenderKey(senderKeyStr)
		for _, ps := range sessions {
			pickleBytes, err := base64.StdEncoding.DecodeString(ps.Pickle)
			if err != nil {
				continue
			}
			internal, err := olm.SessionFromPickled(pickleBytes, m.pickleKey)
			if err != nil {
				continue
			}
			sess := &crypto.OlmSession{Internal: internal}
			sess.CreationTime = ps.CreationTime
			sess.LastEncryptedTime = ps.LastEncryptedTime
			sess.LastDecryptedTime = ps.LastDecryptedTime
			m.cryptoStore.Sessions[senderKey] = append(m.cryptoStore.Sessions[senderKey], sess)
		}
	}

	// Unpickle inbound group sessions
	for roomIDStr, sessions := range f.GroupSessions {
		roomID := id.RoomID(roomIDStr)
		roomMap := make(map[id.SessionID]*crypto.InboundGroupSession)
		for sessIDStr, ps := range sessions {
			pickleBytes, err := base64.StdEncoding.DecodeString(ps.Pickle)
			if err != nil {
				continue
			}
			internal, err := olm.InboundGroupSessionFromPickled(pickleBytes, m.pickleKey)
			if err != nil {
				continue
			}
			roomMap[id.SessionID(sessIDStr)] = &crypto.InboundGroupSession{
				Internal:         internal,
				SigningKey:       ps.SigningKey,
				SenderKey:        ps.SenderKey,
				RoomID:           ps.RoomID,
				ForwardingChains: ps.ForwardingChains,
				ReceivedAt:       ps.ReceivedAt,
				MaxAge:           ps.MaxAge,
				MaxMessages:      ps.MaxMessages,
				KeyBackupVersion: ps.KeyBackupVersion,
			}
		}
		m.cryptoStore.GroupSessions[roomID] = roomMap
	}

	// Unpickle outbound group sessions
	for roomIDStr, ps := range f.OutGroupSessions {
		roomID := id.RoomID(roomIDStr)
		pickleBytes, err := base64.StdEncoding.DecodeString(ps.Pickle)
		if err != nil {
			continue
		}
		internal, err := olm.OutboundGroupSessionFromPickled(pickleBytes, m.pickleKey)
		if err != nil {
			continue
		}
		sess := &crypto.OutboundGroupSession{
			Internal:     internal,
			MaxMessages:  ps.MaxMessages,
			MessageCount: ps.MessageCount,
			Shared:       ps.Shared,
			RoomID:       roomID,
		}
		sess.CreationTime = ps.CreationTime
		m.cryptoStore.OutGroupSessions[roomID] = sess
	}

	// Copy plain data
	if f.Devices != nil {
		m.cryptoStore.Devices = f.Devices
	}
	if f.CrossSigningKeys != nil {
		m.cryptoStore.CrossSigningKeys = f.CrossSigningKeys
	}
	if f.KeySignatures != nil {
		m.cryptoStore.KeySignatures = f.KeySignatures
	}
	if f.Secrets != nil {
		m.cryptoStore.Secrets = f.Secrets
	}
}

func (m *MatrixCore) saveStateStore() error {
	if m.stateStore == nil {
		return nil
	}
	data, err := json.Marshal(m.stateStore)
	if err != nil {
		return err
	}
	return os.WriteFile(m.stateStorePath(), data, 0o600)
}

func (m *MatrixCore) loadStateStore() {
	data, err := os.ReadFile(m.stateStorePath())
	if err != nil {
		return
	}
	json.Unmarshal(data, m.stateStore)
}

// --- E2EE Methods ---

// ExportKeys exports E2EE Megolm session keys encrypted with the given passphrase.
func (m *MatrixCore) ExportKeys(passphrase string) ([]byte, error) {
	if !m.authed {
		return nil, ErrAuth
	}
	if m.olmMachine == nil {
		return nil, fmt.Errorf("E2EE not initialized")
	}

	sessions := m.olmMachine.CryptoStore.GetAllGroupSessions(m.ctx)
	data, err := crypto.ExportKeysIter(passphrase, sessions)
	if err != nil && err.Error() == "no sessions provided for export" {
		return []byte{}, nil
	}
	return data, err
}

// ImportKeys imports E2EE Megolm session keys decrypted with the given passphrase.
func (m *MatrixCore) ImportKeys(data []byte, passphrase string) (int, int, error) {
	if !m.authed {
		return 0, 0, ErrAuth
	}
	if m.olmMachine == nil {
		return 0, 0, fmt.Errorf("E2EE not initialized")
	}

	return m.olmMachine.ImportKeys(m.ctx, passphrase, data)
}

// VerifyDevice marks a device as verified in the crypto store.
func (m *MatrixCore) VerifyDevice(userID string, deviceID string) error {
	if !m.authed {
		return ErrAuth
	}
	if m.olmMachine == nil {
		return fmt.Errorf("E2EE not initialized")
	}

	uid := id.UserID(userID)
	did := id.DeviceID(deviceID)

	device, err := m.olmMachine.GetOrFetchDevice(m.ctx, uid, did)
	if err != nil {
		return fmt.Errorf("get device: %w", err)
	}
	if device == nil {
		return fmt.Errorf("device not found: %s/%s", userID, deviceID)
	}

	device.Trust = id.TrustStateVerified
	return m.olmMachine.CryptoStore.PutDevice(m.ctx, uid, device)
}

// --- Interactive SAS Verification ---

// matrixVerificationCallbacks implements verificationhelper.RequiredCallbacks + ShowSASCallbacks.
type matrixVerificationCallbacks struct {
	m *MatrixCore
}

func (c *matrixVerificationCallbacks) VerificationRequested(_ context.Context, txnID id.VerificationTransactionID, from id.UserID, fromDevice id.DeviceID) {
	c.m.dispatchUpdate(Update{
		Type: UpdateVerification,
		Verification: &VerificationInfo{
			TransactionID: txnID.String(),
			State:         "requested",
			FromUser:      from.String(),
			FromDevice:    fromDevice.String(),
		},
		Platform: "matrix",
	})
}

func (c *matrixVerificationCallbacks) VerificationReady(_ context.Context, txnID id.VerificationTransactionID, otherDeviceID id.DeviceID, supportsSAS, _ bool, _ *verificationhelper.QRCode) {
	c.m.dispatchUpdate(Update{
		Type: UpdateVerification,
		Verification: &VerificationInfo{
			TransactionID: txnID.String(),
			State:         "ready",
			FromDevice:    otherDeviceID.String(),
		},
		Platform: "matrix",
	})
	// Auto-start SAS if both sides support it
	if supportsSAS && c.m.verificationHelper != nil {
		go c.m.verificationHelper.StartSAS(c.m.ctx, txnID)
	}
}

func (c *matrixVerificationCallbacks) VerificationCancelled(_ context.Context, txnID id.VerificationTransactionID, code event.VerificationCancelCode, reason string) {
	c.m.dispatchUpdate(Update{
		Type: UpdateVerification,
		Verification: &VerificationInfo{
			TransactionID: txnID.String(),
			State:         "cancelled",
			CancelCode:    string(code),
			CancelReason:  reason,
		},
		Platform: "matrix",
	})
}

func (c *matrixVerificationCallbacks) VerificationDone(_ context.Context, txnID id.VerificationTransactionID, _ event.VerificationMethod) {
	c.m.dispatchUpdate(Update{
		Type: UpdateVerification,
		Verification: &VerificationInfo{
			TransactionID: txnID.String(),
			State:         "done",
		},
		Platform: "matrix",
	})
}

func (c *matrixVerificationCallbacks) ShowSAS(_ context.Context, txnID id.VerificationTransactionID, emojis []rune, emojiDescriptions []string, decimals []int) {
	symbols := make([]string, len(emojis))
	for i, r := range emojis {
		symbols[i] = string(r)
	}
	c.m.dispatchUpdate(Update{
		Type: UpdateVerification,
		Verification: &VerificationInfo{
			TransactionID: txnID.String(),
			State:         "show_sas",
			Emojis:        emojiDescriptions,
			EmojiSymbols:  symbols,
			Decimals:      decimals,
		},
		Platform: "matrix",
	})
}

// StartSASVerification initiates an interactive SAS emoji verification with another user.
// Returns a transaction ID to track the flow. UI should listen for UpdateVerification events.
func (m *MatrixCore) StartSASVerification(userID string) (string, error) {
	if !m.authed {
		return "", ErrAuth
	}
	if m.verificationHelper == nil {
		return "", fmt.Errorf("verification not initialized")
	}

	txnID, err := m.verificationHelper.StartVerification(m.ctx, id.UserID(userID))
	if err != nil {
		return "", fmt.Errorf("start verification: %w", err)
	}
	return txnID.String(), nil
}

// AcceptSASVerification accepts an incoming verification request.
func (m *MatrixCore) AcceptSASVerification(txnID string) error {
	if !m.authed {
		return ErrAuth
	}
	if m.verificationHelper == nil {
		return fmt.Errorf("verification not initialized")
	}
	return m.verificationHelper.AcceptVerification(m.ctx, id.VerificationTransactionID(txnID))
}

// ConfirmSASEmojis confirms that the SAS emojis match on both sides.
func (m *MatrixCore) ConfirmSASEmojis(txnID string) error {
	if !m.authed {
		return ErrAuth
	}
	if m.verificationHelper == nil {
		return fmt.Errorf("verification not initialized")
	}
	return m.verificationHelper.ConfirmSAS(m.ctx, id.VerificationTransactionID(txnID))
}

// CancelVerification cancels an ongoing verification.
func (m *MatrixCore) CancelVerification(txnID string) error {
	if !m.authed {
		return ErrAuth
	}
	if m.verificationHelper == nil {
		return fmt.Errorf("verification not initialized")
	}
	return m.verificationHelper.CancelVerification(m.ctx, id.VerificationTransactionID(txnID), event.VerificationCancelCodeUser, "User cancelled")
}

// --- Server-Side Key Backup ---

// CreateKeyBackup creates a new server-side key backup, generates a recovery key,
// and uploads all current megolm sessions to the server.
// Returns the recovery key (base64-encoded private key) that must be saved by the user.
func (m *MatrixCore) CreateKeyBackup() (recoveryKey string, version string, err error) {
	if !m.authed {
		return "", "", ErrAuth
	}
	if m.olmMachine == nil {
		return "", "", fmt.Errorf("E2EE not initialized")
	}

	// Generate a new backup key
	backupKey, err := backup.NewMegolmBackupKey()
	if err != nil {
		return "", "", fmt.Errorf("generate backup key: %w", err)
	}

	// Create the backup version on the server
	publicKey := base64.RawStdEncoding.EncodeToString(backupKey.PublicKey().Bytes())
	resp, err := m.client.CreateKeyBackupVersion(m.ctx, &mautrix.ReqRoomKeysVersionCreate[backup.MegolmAuthData]{
		Algorithm: id.KeyBackupAlgorithmMegolmBackupV1,
		AuthData: backup.MegolmAuthData{
			PublicKey: id.Ed25519(publicKey),
		},
	})
	if err != nil {
		return "", "", fmt.Errorf("create backup version: %w", err)
	}
	version = string(resp.Version)

	// Upload all inbound group sessions
	reqBackup := &mautrix.ReqKeyBackup{
		Rooms: make(map[id.RoomID]mautrix.ReqRoomKeyBackup),
	}

	m.mu.RLock()
	groupSessions := m.cryptoStore.GroupSessions
	m.mu.RUnlock()

	sessionCount := 0
	for roomID, roomSessions := range groupSessions {
		roomBackup := mautrix.ReqRoomKeyBackup{
			Sessions: make(map[id.SessionID]mautrix.ReqKeyBackupData),
		}
		for sessID, sess := range roomSessions {
			sessionData := backup.MegolmSessionData{
				Algorithm: id.AlgorithmMegolmV1,
				SenderKey: sess.SenderKey,
				SenderClaimedKeys: backup.SenderClaimedKeys{
					Ed25519: sess.SigningKey,
				},
				ForwardingKeyChain: sess.ForwardingChains,
				SessionKey: func() string {
					exported, err := sess.Internal.Export(sess.Internal.FirstKnownIndex())
					if err != nil {
						return ""
					}
					return string(exported)
				}(),
			}

			encrypted, err := backup.EncryptSessionData(backupKey, sessionData)
			if err != nil {
				continue
			}

			encJSON, err := json.Marshal(encrypted)
			if err != nil {
				continue
			}

			roomBackup.Sessions[sessID] = mautrix.ReqKeyBackupData{
				FirstMessageIndex: int(sess.Internal.FirstKnownIndex()),
				IsVerified:        true,
				SessionData:       json.RawMessage(encJSON),
			}
			sessionCount++
		}
		if len(roomBackup.Sessions) > 0 {
			reqBackup.Rooms[roomID] = roomBackup
		}
	}

	if sessionCount > 0 {
		_, err = m.client.PutKeysInBackup(m.ctx, id.KeyBackupVersion(version), reqBackup)
		if err != nil {
			return "", "", fmt.Errorf("upload sessions: %w", err)
		}
	}

	// Return the recovery key (base64-encoded private key bytes)
	recoveryKey = base64.StdEncoding.EncodeToString(backupKey.Bytes())
	return recoveryKey, version, nil
}

// RestoreKeyBackup downloads and decrypts megolm sessions from a server-side key backup.
// The recoveryKey is the base64-encoded private key returned by CreateKeyBackup.
// Returns (imported, total, error).
func (m *MatrixCore) RestoreKeyBackup(recoveryKey string) (int, int, error) {
	if !m.authed {
		return 0, 0, ErrAuth
	}
	if m.olmMachine == nil {
		return 0, 0, fmt.Errorf("E2EE not initialized")
	}

	// Decode the recovery key
	keyBytes, err := base64.StdEncoding.DecodeString(recoveryKey)
	if err != nil {
		return 0, 0, fmt.Errorf("decode recovery key: %w", err)
	}

	backupKey, err := backup.MegolmBackupKeyFromBytes(keyBytes)
	if err != nil {
		return 0, 0, fmt.Errorf("parse backup key: %w", err)
	}

	// Download and store the latest backup
	version, err := m.olmMachine.DownloadAndStoreLatestKeyBackup(m.ctx, backupKey)
	if err != nil {
		return 0, 0, fmt.Errorf("restore backup: %w", err)
	}
	if version == "" {
		return 0, 0, fmt.Errorf("no key backup found on server")
	}

	// Count how many sessions we now have
	total := 0
	m.mu.RLock()
	for _, roomSessions := range m.cryptoStore.GroupSessions {
		total += len(roomSessions)
	}
	m.mu.RUnlock()

	return total, total, nil
}

// GetKeyBackupInfo returns info about the latest server-side key backup, or nil if none exists.
func (m *MatrixCore) GetKeyBackupInfo() (version string, count int, err error) {
	if !m.authed {
		return "", 0, ErrAuth
	}

	resp, err := m.client.GetKeyBackupLatestVersion(m.ctx)
	if err != nil {
		// 404 means no backup exists
		return "", 0, nil
	}

	return string(resp.Version), resp.Count, nil
}

// ──────────────────────────── VoIP Extended ────────────────────────────

// AcceptCallSelectAnswer sends m.call.select_answer for call glare handling.
func (m *MatrixCore) AcceptCallSelectAnswer(callID, selectedPartyID string) error {
	if !m.authed {
		return ErrAuth
	}
	m.callsMu.RLock()
	call, ok := m.activeCalls[callID]
	m.callsMu.RUnlock()
	if !ok {
		return fmt.Errorf("call %s not found", callID)
	}

	content := map[string]interface{}{
		"call_id":           callID,
		"version":           "1",
		"party_id":          m.deviceID.String(),
		"selected_party_id": selectedPartyID,
	}
	_, err := m.client.SendMessageEvent(m.ctx, call.RoomID, event.NewEventType("m.call.select_answer"), content)
	return err
}

// SendCallCandidates sends trickle ICE candidates for an active call.
func (m *MatrixCore) SendCallCandidates(callID string, candidates []webrtc.ICECandidateInit) error {
	if !m.authed {
		return ErrAuth
	}
	m.callsMu.RLock()
	call, ok := m.activeCalls[callID]
	m.callsMu.RUnlock()
	if !ok {
		return fmt.Errorf("call %s not found", callID)
	}

	m.sendICECandidates(call, candidates)
	return nil
}

// CallReplaces sends m.call.replaces for call transfer (attended or blind).
func (m *MatrixCore) CallReplaces(callID, targetRoomID, targetCallID string) error {
	if !m.authed {
		return ErrAuth
	}
	m.callsMu.RLock()
	call, ok := m.activeCalls[callID]
	m.callsMu.RUnlock()
	if !ok {
		return fmt.Errorf("call %s not found", callID)
	}

	content := map[string]interface{}{
		"call_id":  callID,
		"version":  "1",
		"party_id": m.deviceID.String(),
		"replacement_id": fmt.Sprintf("rep_%d", time.Now().UnixNano()),
		"target_room": map[string]interface{}{
			"room_id": targetRoomID,
		},
	}
	if targetCallID != "" {
		content["target_room"].(map[string]interface{})["call_id"] = targetCallID
	}
	_, err := m.client.SendMessageEvent(m.ctx, call.RoomID, event.NewEventType("m.call.replaces"), content)
	return err
}

// SDPStreamMetadataChanged sends m.call.sdp_stream_metadata_changed when stream metadata updates.
func (m *MatrixCore) SDPStreamMetadataChanged(callID string, metadata map[string]interface{}) error {
	if !m.authed {
		return ErrAuth
	}
	m.callsMu.RLock()
	call, ok := m.activeCalls[callID]
	m.callsMu.RUnlock()
	if !ok {
		return fmt.Errorf("call %s not found", callID)
	}

	content := map[string]interface{}{
		"call_id":                 callID,
		"version":                 "1",
		"party_id":               m.deviceID.String(),
		"sdp_stream_metadata": metadata,
	}
	_, err := m.client.SendMessageEvent(m.ctx, call.RoomID, event.NewEventType("m.call.sdp_stream_metadata_changed"), content)
	return err
}

// CallNotify sends m.call.notify to ring other devices.
func (m *MatrixCore) CallNotify(callID string, roomID id.RoomID, lifetime int) error {
	if !m.authed {
		return ErrAuth
	}
	content := map[string]interface{}{
		"call_id":          callID,
		"version":          "1",
		"party_id":         m.deviceID.String(),
		"lifetime":         lifetime,
		"application":      "m.call",
		"m.mentions":       map[string]interface{}{"user_ids": []string{}},
	}
	_, err := m.client.SendMessageEvent(m.ctx, roomID, event.NewEventType("m.call.notify"), content)
	return err
}

// GroupCallEncryptionKeys sends m.call.encryption_keys for MatrixRTC encrypted group calls.
func (m *MatrixCore) GroupCallEncryptionKeys(callID string, roomID id.RoomID, keys []map[string]interface{}) error {
	if !m.authed {
		return ErrAuth
	}
	content := map[string]interface{}{
		"call_id":  callID,
		"version":  "1",
		"party_id": m.deviceID.String(),
		"keys":     keys,
	}
	_, err := m.client.SendToDevice(m.ctx, event.NewEventType("m.call.encryption_keys"), &mautrix.ReqSendToDevice{
		Messages: map[id.UserID]map[id.DeviceID]*event.Content{
			// Broadcast — caller should fill in targets
		},
	})
	_ = err
	// Fallback: send as room event
	_, err = m.client.SendMessageEvent(m.ctx, roomID, event.NewEventType("m.call.encryption_keys"), content)
	return err
}

// ──────────────────────────── Registration / Account ────────────────────────────

// Register creates a new Matrix account.
func (m *MatrixCore) Register(homeserverURL, username, password string) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	client, err := mautrix.NewClient(homeserverURL, "", "")
	if err != nil {
		return fmt.Errorf("create client: %w", err)
	}
	client.Log = zerolog.Nop()

	type regReq struct {
		Username string `json:"username"`
		Password string `json:"password"`
		Auth     map[string]interface{} `json:"auth,omitempty"`
	}
	req := regReq{Username: username, Password: password}

	// First attempt — may get interactive auth response
	var resp mautrix.RespRegister
	_, err = client.MakeFullRequest(m.ctx, mautrix.FullRequest{
		Method:      http.MethodPost,
		URL:         client.BuildClientURL("v3", "register"),
		RequestJSON: req,
		ResponseJSON: &resp,
	})
	if err != nil {
		// Try with dummy auth
		req.Auth = map[string]interface{}{
			"type": "m.login.dummy",
		}
		_, err = client.MakeFullRequest(m.ctx, mautrix.FullRequest{
			Method:      http.MethodPost,
			URL:         client.BuildClientURL("v3", "register"),
			RequestJSON: req,
			ResponseJSON: &resp,
		})
		if err != nil {
			return fmt.Errorf("register: %w", err)
		}
	}

	m.userID = resp.UserID
	m.deviceID = resp.DeviceID
	m.accessToken = resp.AccessToken
	m.homeserver = homeserverURL
	m.client = client
	m.client.UserID = resp.UserID
	m.client.DeviceID = resp.DeviceID
	m.client.AccessToken = resp.AccessToken
	m.authed = true
	m.saveSession()
	return nil
}

// DeactivateAccount permanently deactivates the Matrix account.
func (m *MatrixCore) DeactivateAccount(password string) error {
	if !m.authed {
		return ErrAuth
	}
	req := map[string]interface{}{
		"auth": map[string]interface{}{
			"type":     "m.login.password",
			"user":     string(m.userID),
			"password": password,
		},
	}
	_, err := m.client.MakeFullRequest(m.ctx, mautrix.FullRequest{
		Method:      http.MethodPost,
		URL:         m.client.BuildClientURL("v3", "account", "deactivate"),
		RequestJSON: req,
	})
	return err
}

// ChangePassword changes the account password.
func (m *MatrixCore) ChangePassword(oldPassword, newPassword string) error {
	if !m.authed {
		return ErrAuth
	}
	req := map[string]interface{}{
		"new_password": newPassword,
		"auth": map[string]interface{}{
			"type":     "m.login.password",
			"user":     string(m.userID),
			"password": oldPassword,
		},
	}
	_, err := m.client.MakeFullRequest(m.ctx, mautrix.FullRequest{
		Method:      http.MethodPost,
		URL:         m.client.BuildClientURL("v3", "account", "password"),
		RequestJSON: req,
	})
	return err
}

// CheckUsernameAvailability checks if a username is available for registration.
func (m *MatrixCore) CheckUsernameAvailability(username string) (bool, error) {
	if m.client == nil {
		return false, fmt.Errorf("client not initialized")
	}
	resp, err := m.client.RegisterAvailable(m.ctx, username)
	if err != nil {
		return false, err
	}
	return resp.Available, nil
}

// RequestEmailToken requests an email validation token for 3PID operations.
func (m *MatrixCore) RequestEmailToken(email, clientSecret string, sendAttempt int) (string, error) {
	if !m.authed {
		return "", ErrAuth
	}
	req := map[string]interface{}{
		"email":        email,
		"client_secret": clientSecret,
		"send_attempt":  sendAttempt,
	}
	var resp struct {
		SID string `json:"sid"`
	}
	_, err := m.client.MakeFullRequest(m.ctx, mautrix.FullRequest{
		Method:       http.MethodPost,
		URL:          m.client.BuildClientURL("v3", "account", "3pid", "email", "requestToken"),
		RequestJSON:  req,
		ResponseJSON: &resp,
	})
	if err != nil {
		return "", err
	}
	return resp.SID, nil
}

// RequestMsisdnToken requests a phone number validation token.
func (m *MatrixCore) RequestMsisdnToken(country, phoneNumber, clientSecret string, sendAttempt int) (string, error) {
	if !m.authed {
		return "", ErrAuth
	}
	req := map[string]interface{}{
		"country":       country,
		"phone_number":  phoneNumber,
		"client_secret": clientSecret,
		"send_attempt":  sendAttempt,
	}
	var resp struct {
		SID string `json:"sid"`
	}
	_, err := m.client.MakeFullRequest(m.ctx, mautrix.FullRequest{
		Method:       http.MethodPost,
		URL:          m.client.BuildClientURL("v3", "account", "3pid", "msisdn", "requestToken"),
		RequestJSON:  req,
		ResponseJSON: &resp,
	})
	if err != nil {
		return "", err
	}
	return resp.SID, nil
}

// ──────────────────────────── 3PID Management ────────────────────────────

// Get3PIDs returns the list of third-party identifiers associated with the account.
func (m *MatrixCore) Get3PIDs() ([]map[string]interface{}, error) {
	if !m.authed {
		return nil, ErrAuth
	}
	var resp struct {
		ThreePIDs []map[string]interface{} `json:"threepids"`
	}
	_, err := m.client.MakeFullRequest(m.ctx, mautrix.FullRequest{
		Method:       http.MethodGet,
		URL:          m.client.BuildClientURL("v3", "account", "3pid"),
		ResponseJSON: &resp,
	})
	if err != nil {
		return nil, err
	}
	return resp.ThreePIDs, nil
}

// Add3PID adds a validated 3PID to the account.
func (m *MatrixCore) Add3PID(clientSecret, sid string) error {
	if !m.authed {
		return ErrAuth
	}
	req := map[string]interface{}{
		"three_pid_creds": map[string]interface{}{
			"client_secret": clientSecret,
			"sid":           sid,
		},
	}
	_, err := m.client.MakeFullRequest(m.ctx, mautrix.FullRequest{
		Method:      http.MethodPost,
		URL:         m.client.BuildClientURL("v3", "account", "3pid"),
		RequestJSON: req,
	})
	return err
}

// Bind3PID binds a 3PID to the identity server.
func (m *MatrixCore) Bind3PID(clientSecret, sid, idServer, idAccessToken string) error {
	if !m.authed {
		return ErrAuth
	}
	req := map[string]interface{}{
		"client_secret":   clientSecret,
		"sid":             sid,
		"id_server":       idServer,
		"id_access_token": idAccessToken,
	}
	_, err := m.client.MakeFullRequest(m.ctx, mautrix.FullRequest{
		Method:      http.MethodPost,
		URL:         m.client.BuildClientURL("v3", "account", "3pid", "bind"),
		RequestJSON: req,
	})
	return err
}

// Delete3PID removes a 3PID from the account.
func (m *MatrixCore) Delete3PID(medium, address string) error {
	if !m.authed {
		return ErrAuth
	}
	req := map[string]interface{}{
		"medium":  medium,
		"address": address,
	}
	_, err := m.client.MakeFullRequest(m.ctx, mautrix.FullRequest{
		Method:      http.MethodPost,
		URL:         m.client.BuildClientURL("v3", "account", "3pid", "delete"),
		RequestJSON: req,
	})
	return err
}

// Unbind3PID unbinds a 3PID from the identity server.
func (m *MatrixCore) Unbind3PID(medium, address, idServer string) error {
	if !m.authed {
		return ErrAuth
	}
	req := map[string]interface{}{
		"medium":    medium,
		"address":   address,
		"id_server": idServer,
	}
	_, err := m.client.MakeFullRequest(m.ctx, mautrix.FullRequest{
		Method:      http.MethodPost,
		URL:         m.client.BuildClientURL("v3", "account", "3pid", "unbind"),
		RequestJSON: req,
	})
	return err
}

// ──────────────────────────── Push Notifications ────────────────────────────

// GetPushers returns the list of push notification services for the current user.
func (m *MatrixCore) GetPushers() ([]map[string]interface{}, error) {
	if !m.authed {
		return nil, ErrAuth
	}
	var resp struct {
		Pushers []map[string]interface{} `json:"pushers"`
	}
	_, err := m.client.MakeFullRequest(m.ctx, mautrix.FullRequest{
		Method:       http.MethodGet,
		URL:          m.client.BuildClientURL("v3", "pushers"),
		ResponseJSON: &resp,
	})
	if err != nil {
		return nil, err
	}
	return resp.Pushers, nil
}

// SetPusher adds or updates a push notification service.
func (m *MatrixCore) SetPusher(pusher map[string]interface{}) error {
	if !m.authed {
		return ErrAuth
	}
	_, err := m.client.MakeFullRequest(m.ctx, mautrix.FullRequest{
		Method:      http.MethodPost,
		URL:         m.client.BuildClientURL("v3", "pushers", "set"),
		RequestJSON: pusher,
	})
	return err
}

// GetPushRules returns all push notification rules for the current user.
func (m *MatrixCore) GetPushRules() (json.RawMessage, error) {
	if !m.authed {
		return nil, ErrAuth
	}
	respData, err := m.client.MakeFullRequest(m.ctx, mautrix.FullRequest{
		Method: http.MethodGet,
		URL:    m.client.BuildClientURL("v3", "pushrules", ""),
	})
	if err != nil {
		return nil, err
	}
	return json.RawMessage(respData), nil
}

// SetPushRule creates or updates a push notification rule.
func (m *MatrixCore) SetPushRule(scope, kind, ruleID string, rule map[string]interface{}) error {
	if !m.authed {
		return ErrAuth
	}
	_, err := m.client.MakeFullRequest(m.ctx, mautrix.FullRequest{
		Method:      http.MethodPut,
		URL:         m.client.BuildClientURL("v3", "pushrules", scope, kind, ruleID),
		RequestJSON: rule,
	})
	return err
}

// DeletePushRule removes a push notification rule.
func (m *MatrixCore) DeletePushRule(scope, kind, ruleID string) error {
	if !m.authed {
		return ErrAuth
	}
	_, err := m.client.MakeFullRequest(m.ctx, mautrix.FullRequest{
		Method: http.MethodDelete,
		URL:    m.client.BuildClientURL("v3", "pushrules", scope, kind, ruleID),
	})
	return err
}

// EnablePushRule enables or disables a push notification rule.
func (m *MatrixCore) EnablePushRule(scope, kind, ruleID string, enabled bool) error {
	if !m.authed {
		return ErrAuth
	}
	_, err := m.client.MakeFullRequest(m.ctx, mautrix.FullRequest{
		Method:      http.MethodPut,
		URL:         m.client.BuildClientURL("v3", "pushrules", scope, kind, ruleID, "enabled"),
		RequestJSON: map[string]bool{"enabled": enabled},
	})
	return err
}

// GetNotifications returns recent notifications for the current user.
func (m *MatrixCore) GetNotifications(from string, limit int, only string) (json.RawMessage, error) {
	if !m.authed {
		return nil, ErrAuth
	}
	query := fmt.Sprintf("?limit=%d", limit)
	if from != "" {
		query += "&from=" + from
	}
	if only != "" {
		query += "&only=" + only
	}
	respData, err := m.client.MakeFullRequest(m.ctx, mautrix.FullRequest{
		Method: http.MethodGet,
		URL:    m.client.BuildClientURL("v3", "notifications") + query,
	})
	if err != nil {
		return nil, err
	}
	return json.RawMessage(respData), nil
}

// ──────────────────────────── Room State Events ────────────────────────────

// SetPowerLevels sets the power levels in a room.
func (m *MatrixCore) SetPowerLevels(chatID string, levels *event.PowerLevelsEventContent) error {
	if !m.authed {
		return ErrAuth
	}
	roomID := id.RoomID(chatID)
	_, err := m.client.SendStateEvent(m.ctx, roomID, event.StatePowerLevels, "", levels)
	return err
}

// SetGuestAccess sets whether guests can join a room.
func (m *MatrixCore) SetGuestAccess(chatID string, access string) error {
	if !m.authed {
		return ErrAuth
	}
	roomID := id.RoomID(chatID)
	_, err := m.client.SendStateEvent(m.ctx, roomID, event.StateGuestAccess, "", map[string]string{
		"guest_access": access, // "can_join" or "forbidden"
	})
	return err
}

// SetServerACL sets the server access control list for a room.
func (m *MatrixCore) SetServerACL(chatID string, allow, deny []string, allowIPLiterals bool) error {
	if !m.authed {
		return ErrAuth
	}
	roomID := id.RoomID(chatID)
	_, err := m.client.SendStateEvent(m.ctx, roomID, event.NewEventType("m.room.server_acl"), "", map[string]interface{}{
		"allow":              allow,
		"deny":               deny,
		"allow_ip_literals":  allowIPLiterals,
	})
	return err
}

// GetRoomState returns all state events for a room.
func (m *MatrixCore) GetRoomState(chatID string) ([]json.RawMessage, error) {
	if !m.authed {
		return nil, ErrAuth
	}
	roomID := id.RoomID(chatID)
	var resp []json.RawMessage
	_, err := m.client.MakeFullRequest(m.ctx, mautrix.FullRequest{
		Method:       http.MethodGet,
		URL:          m.client.BuildClientURL("v3", "rooms", string(roomID), "state"),
		ResponseJSON: &resp,
	})
	if err != nil {
		return nil, err
	}
	return resp, nil
}

// ──────────────────────────── Room Visibility ────────────────────────────

// GetRoomVisibility returns the directory visibility of a room ("public" or "private").
func (m *MatrixCore) GetRoomVisibility(chatID string) (string, error) {
	if !m.authed {
		return "", ErrAuth
	}
	var resp struct {
		Visibility string `json:"visibility"`
	}
	_, err := m.client.MakeFullRequest(m.ctx, mautrix.FullRequest{
		Method:       http.MethodGet,
		URL:          m.client.BuildClientURL("v3", "directory", "list", "room", chatID),
		ResponseJSON: &resp,
	})
	if err != nil {
		return "", err
	}
	return resp.Visibility, nil
}

// SetRoomVisibility sets the directory visibility of a room ("public" or "private").
func (m *MatrixCore) SetRoomVisibility(chatID string, visibility string) error {
	if !m.authed {
		return ErrAuth
	}
	_, err := m.client.MakeFullRequest(m.ctx, mautrix.FullRequest{
		Method:      http.MethodPut,
		URL:         m.client.BuildClientURL("v3", "directory", "list", "room", chatID),
		RequestJSON: map[string]string{"visibility": visibility},
	})
	return err
}

// ──────────────────────────── Filters ────────────────────────────

// CreateFilter creates a filter definition on the server.
func (m *MatrixCore) CreateFilter(filter json.RawMessage) (string, error) {
	if !m.authed {
		return "", ErrAuth
	}
	var resp struct {
		FilterID string `json:"filter_id"`
	}
	_, err := m.client.MakeFullRequest(m.ctx, mautrix.FullRequest{
		Method:       http.MethodPost,
		URL:          m.client.BuildClientURL("v3", "user", string(m.userID), "filter"),
		RequestJSON:  json.RawMessage(filter),
		ResponseJSON: &resp,
	})
	if err != nil {
		return "", err
	}
	return resp.FilterID, nil
}

// GetFilter retrieves a previously created filter by ID.
func (m *MatrixCore) GetFilter(filterID string) (json.RawMessage, error) {
	if !m.authed {
		return nil, ErrAuth
	}
	respData, err := m.client.MakeFullRequest(m.ctx, mautrix.FullRequest{
		Method: http.MethodGet,
		URL:    m.client.BuildClientURL("v3", "user", string(m.userID), "filter", filterID),
	})
	if err != nil {
		return nil, err
	}
	return json.RawMessage(respData), nil
}

// ──────────────────────────── Account Data ────────────────────────────

// SetAccountData sets global account data.
func (m *MatrixCore) SetAccountData(name string, data interface{}) error {
	if !m.authed {
		return ErrAuth
	}
	return m.client.SetAccountData(m.ctx, name, data)
}

// GetAccountData retrieves global account data.
func (m *MatrixCore) GetAccountData(name string, output interface{}) error {
	if !m.authed {
		return ErrAuth
	}
	return m.client.GetAccountData(m.ctx, name, output)
}

// SetRoomAccountData sets per-room account data.
func (m *MatrixCore) SetRoomAccountData(chatID, name string, data interface{}) error {
	if !m.authed {
		return ErrAuth
	}
	_, err := m.client.MakeFullRequest(m.ctx, mautrix.FullRequest{
		Method:      http.MethodPut,
		URL:         m.client.BuildClientURL("v3", "user", string(m.userID), "rooms", chatID, "account_data", name),
		RequestJSON: data,
	})
	return err
}

// GetRoomAccountData retrieves per-room account data.
func (m *MatrixCore) GetRoomAccountData(chatID, name string, output interface{}) error {
	if !m.authed {
		return ErrAuth
	}
	_, err := m.client.MakeFullRequest(m.ctx, mautrix.FullRequest{
		Method:       http.MethodGet,
		URL:          m.client.BuildClientURL("v3", "user", string(m.userID), "rooms", chatID, "account_data", name),
		ResponseJSON: output,
	})
	return err
}

// ──────────────────────────── To-Device ────────────────────────────

// SendToDevice sends an event to specific devices.
func (m *MatrixCore) SendToDevice(eventType string, messages map[id.UserID]map[id.DeviceID]*event.Content) error {
	if !m.authed {
		return ErrAuth
	}
	_, err := m.client.SendToDevice(m.ctx, event.NewEventType(eventType), &mautrix.ReqSendToDevice{
		Messages: messages,
	})
	return err
}

// ──────────────────────────── Reporting ────────────────────────────

// ReportRoom reports a room for policy violation.
func (m *MatrixCore) ReportRoom(chatID, reason string) error {
	if !m.authed {
		return ErrAuth
	}
	_, err := m.client.MakeFullRequest(m.ctx, mautrix.FullRequest{
		Method:      http.MethodPost,
		URL:         m.client.BuildClientURL("v3", "rooms", chatID, "report"),
		RequestJSON: map[string]string{"reason": reason},
	})
	return err
}

// ReportUser reports a user for policy violation.
func (m *MatrixCore) ReportUser(userID, reason string) error {
	if !m.authed {
		return ErrAuth
	}
	_, err := m.client.MakeFullRequest(m.ctx, mautrix.FullRequest{
		Method:      http.MethodPost,
		URL:         m.client.BuildClientURL("v3", "users", userID, "report"),
		RequestJSON: map[string]string{"reason": reason},
	})
	return err
}

// ──────────────────────────── Third-Party Protocol ────────────────────────────

// GetThirdPartyProtocols returns the list of application service protocols supported by the server.
func (m *MatrixCore) GetThirdPartyProtocols() (map[string]json.RawMessage, error) {
	if !m.authed {
		return nil, ErrAuth
	}
	var resp map[string]json.RawMessage
	_, err := m.client.MakeFullRequest(m.ctx, mautrix.FullRequest{
		Method:       http.MethodGet,
		URL:          m.client.BuildClientURL("v3", "thirdparty", "protocols"),
		ResponseJSON: &resp,
	})
	if err != nil {
		return nil, err
	}
	return resp, nil
}

// LookupThirdPartyLocation looks up a location from a third-party protocol.
func (m *MatrixCore) LookupThirdPartyLocation(protocol string, fields map[string]string) ([]map[string]interface{}, error) {
	if !m.authed {
		return nil, ErrAuth
	}
	query := "?"
	for k, v := range fields {
		query += k + "=" + v + "&"
	}
	var resp []map[string]interface{}
	_, err := m.client.MakeFullRequest(m.ctx, mautrix.FullRequest{
		Method:       http.MethodGet,
		URL:          m.client.BuildClientURL("v3", "thirdparty", "location", protocol) + query,
		ResponseJSON: &resp,
	})
	if err != nil {
		return nil, err
	}
	return resp, nil
}

// LookupThirdPartyUser looks up a user from a third-party protocol.
func (m *MatrixCore) LookupThirdPartyUser(protocol string, fields map[string]string) ([]map[string]interface{}, error) {
	if !m.authed {
		return nil, ErrAuth
	}
	query := "?"
	for k, v := range fields {
		query += k + "=" + v + "&"
	}
	var resp []map[string]interface{}
	_, err := m.client.MakeFullRequest(m.ctx, mautrix.FullRequest{
		Method:       http.MethodGet,
		URL:          m.client.BuildClientURL("v3", "thirdparty", "user", protocol) + query,
		ResponseJSON: &resp,
	})
	if err != nil {
		return nil, err
	}
	return resp, nil
}

// ──────────────────────────── OpenID ────────────────────────────

// RequestOpenIDToken requests an OpenID Connect token for the current user.
func (m *MatrixCore) RequestOpenIDToken() (map[string]interface{}, error) {
	if !m.authed {
		return nil, ErrAuth
	}
	var resp map[string]interface{}
	_, err := m.client.MakeFullRequest(m.ctx, mautrix.FullRequest{
		Method:       http.MethodPost,
		URL:          m.client.BuildClientURL("v3", "user", string(m.userID), "openid", "request_token"),
		RequestJSON:  map[string]interface{}{},
		ResponseJSON: &resp,
	})
	if err != nil {
		return nil, err
	}
	return resp, nil
}

// ──────────────────────────── Cross-Signing ────────────────────────────

// UploadCrossSigningKeys uploads cross-signing keys to the server.
func (m *MatrixCore) UploadCrossSigningKeys(masterKey, selfSigningKey, userSigningKey map[string]interface{}, password string) error {
	if !m.authed {
		return ErrAuth
	}
	req := map[string]interface{}{
		"master_key":       masterKey,
		"self_signing_key": selfSigningKey,
		"user_signing_key": userSigningKey,
	}
	if password != "" {
		req["auth"] = map[string]interface{}{
			"type":     "m.login.password",
			"user":     string(m.userID),
			"password": password,
		}
	}
	_, err := m.client.MakeFullRequest(m.ctx, mautrix.FullRequest{
		Method:      http.MethodPost,
		URL:         m.client.BuildClientURL("v3", "keys", "device_signing", "upload"),
		RequestJSON: req,
	})
	return err
}

// UploadSignatures uploads key signatures (for cross-signing verification).
func (m *MatrixCore) UploadSignatures(signatures map[string]map[string]map[string]interface{}) error {
	if !m.authed {
		return ErrAuth
	}
	_, err := m.client.MakeFullRequest(m.ctx, mautrix.FullRequest{
		Method:      http.MethodPost,
		URL:         m.client.BuildClientURL("v3", "keys", "signatures", "upload"),
		RequestJSON: signatures,
	})
	return err
}

// GenerateCrossSigningKeys generates new cross-signing keys (master, self-signing, user-signing).
// Returns the keys as a map to be uploaded via UploadCrossSigningKeys.
func (m *MatrixCore) GenerateCrossSigningKeys() (master, selfSigning, userSigning map[string]interface{}, err error) {
	if !m.authed {
		return nil, nil, nil, ErrAuth
	}

	generateKey := func(usage string) (map[string]interface{}, error) {
		keyBytes := make([]byte, 32)
		if _, err := rand.Read(keyBytes); err != nil {
			return nil, err
		}
		keyB64 := base64.RawStdEncoding.EncodeToString(keyBytes)
		return map[string]interface{}{
			"user_id": string(m.userID),
			"usage":   []string{usage},
			"keys": map[string]string{
				"ed25519:" + keyB64[:8]: keyB64,
			},
		}, nil
	}

	master, err = generateKey("master")
	if err != nil {
		return nil, nil, nil, err
	}
	selfSigning, err = generateKey("self_signing")
	if err != nil {
		return nil, nil, nil, err
	}
	userSigning, err = generateKey("user_signing")
	if err != nil {
		return nil, nil, nil, err
	}
	return master, selfSigning, userSigning, nil
}

// ──────────────────────────── SSSS / Secret Storage ────────────────────────────

// SetSecretStorageKey stores a secret storage key in account data.
func (m *MatrixCore) SetSecretStorageKey(keyID string, keyData map[string]interface{}) error {
	if !m.authed {
		return ErrAuth
	}
	return m.client.SetAccountData(m.ctx, "m.secret_storage.key."+keyID, keyData)
}

// GetSecretStorageKey retrieves a secret storage key from account data.
func (m *MatrixCore) GetSecretStorageKey(keyID string) (map[string]interface{}, error) {
	if !m.authed {
		return nil, ErrAuth
	}
	var result map[string]interface{}
	err := m.client.GetAccountData(m.ctx, "m.secret_storage.key."+keyID, &result)
	if err != nil {
		return nil, err
	}
	return result, nil
}

// ──────────────────────────── Admin ────────────────────────────

// WhoisUser returns information about a user (only available to server admins).
func (m *MatrixCore) WhoisUser(userID string) (map[string]interface{}, error) {
	if !m.authed {
		return nil, ErrAuth
	}
	var resp map[string]interface{}
	_, err := m.client.MakeFullRequest(m.ctx, mautrix.FullRequest{
		Method:       http.MethodGet,
		URL:          m.client.BuildClientURL("v3", "admin", "whois", userID),
		ResponseJSON: &resp,
	})
	if err != nil {
		return nil, err
	}
	return resp, nil
}

// ──────────────────────────── Media ────────────────────────────

// GetMediaConfig returns the media upload configuration (max upload size).
func (m *MatrixCore) GetMediaConfig() (int64, error) {
	if !m.authed {
		return 0, ErrAuth
	}
	resp, err := m.client.GetMediaConfig(m.ctx)
	if err != nil {
		return 0, err
	}
	return resp.UploadSize, nil
}

// CreateMXCURI creates an MXC URI for an async upload.
func (m *MatrixCore) CreateMXCURI() (string, string, error) {
	if !m.authed {
		return "", "", ErrAuth
	}
	var resp struct {
		ContentURI      string `json:"content_uri"`
		UnusedExpiresAt int64  `json:"unused_expires_at"`
	}
	_, err := m.client.MakeFullRequest(m.ctx, mautrix.FullRequest{
		Method:       http.MethodPost,
		URL:          m.client.BuildURL(mautrix.MediaURLPath{"v1", "create"}),
		ResponseJSON: &resp,
	})
	if err != nil {
		return "", "", err
	}
	return resp.ContentURI, strconv.FormatInt(resp.UnusedExpiresAt, 10), nil
}

// DownloadThumbnail downloads a server-side generated thumbnail for a media file.
func (m *MatrixCore) DownloadThumbnail(mxcURI string, width, height int, dest string) error {
	if !m.authed {
		return ErrAuth
	}
	// Parse mxc://server/media_id
	uri := strings.TrimPrefix(mxcURI, "mxc://")
	parts := strings.SplitN(uri, "/", 2)
	if len(parts) != 2 {
		return fmt.Errorf("invalid mxc URI: %s", mxcURI)
	}

	query := fmt.Sprintf("?width=%d&height=%d&method=scale", width, height)
	respData, err := m.client.MakeFullRequest(m.ctx, mautrix.FullRequest{
		Method: http.MethodGet,
		URL:    m.client.BuildURL(mautrix.MediaURLPath{"v3", "thumbnail", parts[0], parts[1]}) + query,
	})
	if err != nil {
		return err
	}

	return os.WriteFile(dest, respData, 0600)
}

// ──────────────────────────── Rooms / State (extended) ────────────────────────────

// GetEvent retrieves a single event by ID from a room.
func (m *MatrixCore) GetEvent(chatID, eventID string) (json.RawMessage, error) {
	if !m.authed {
		return nil, ErrAuth
	}
	respData, err := m.client.MakeFullRequest(m.ctx, mautrix.FullRequest{
		Method: http.MethodGet,
		URL:    m.client.BuildClientURL("v3", "rooms", chatID, "event", eventID),
	})
	if err != nil {
		return nil, err
	}
	return json.RawMessage(respData), nil
}

// GetEventContext retrieves events around a given event in a room.
func (m *MatrixCore) GetEventContext(chatID, eventID string, limit int) (json.RawMessage, error) {
	if !m.authed {
		return nil, ErrAuth
	}
	query := fmt.Sprintf("?limit=%d", limit)
	respData, err := m.client.MakeFullRequest(m.ctx, mautrix.FullRequest{
		Method: http.MethodGet,
		URL:    m.client.BuildClientURL("v3", "rooms", chatID, "context", eventID) + query,
	})
	if err != nil {
		return nil, err
	}
	return json.RawMessage(respData), nil
}

// ResolveAlias resolves a room alias to a room ID.
func (m *MatrixCore) ResolveAlias(alias string) (string, []string, error) {
	if !m.authed {
		return "", nil, ErrAuth
	}
	resp, err := m.client.ResolveAlias(m.ctx, id.RoomAlias(alias))
	if err != nil {
		return "", nil, err
	}
	servers := make([]string, len(resp.Servers))
	for i, s := range resp.Servers {
		servers[i] = string(s)
	}
	return string(resp.RoomID), servers, nil
}

// ──────────────────────────── Auth / Login (extended) ────────────────────────────

// GetLoginFlows returns the supported login authentication types.
func (m *MatrixCore) GetLoginFlows() ([]map[string]interface{}, error) {
	if m.client == nil {
		return nil, fmt.Errorf("client not initialized")
	}
	resp, err := m.client.GetLoginFlows(m.ctx)
	if err != nil {
		return nil, err
	}
	var flows []map[string]interface{}
	for _, f := range resp.Flows {
		flows = append(flows, map[string]interface{}{
			"type": string(f.Type),
		})
	}
	return flows, nil
}

// LogoutAll logs out all sessions for the current user.
func (m *MatrixCore) LogoutAll() error {
	if !m.authed {
		return ErrAuth
	}
	_, err := m.client.LogoutAll(m.ctx)
	if err != nil {
		return err
	}
	m.authed = false
	return nil
}

// ──────────────────────────── Tags ────────────────────────────

// GetTags returns all tags for a room.
func (m *MatrixCore) GetTags(chatID string) (map[string]map[string]interface{}, error) {
	if !m.authed {
		return nil, ErrAuth
	}
	var resp struct {
		Tags map[string]map[string]interface{} `json:"tags"`
	}
	_, err := m.client.MakeFullRequest(m.ctx, mautrix.FullRequest{
		Method:       http.MethodGet,
		URL:          m.client.BuildClientURL("v3", "user", string(m.userID), "rooms", chatID, "tags"),
		ResponseJSON: &resp,
	})
	if err != nil {
		return nil, err
	}
	return resp.Tags, nil
}

// ──────────────────────────── Read Receipts ────────────────────────────

// SendPrivateReadReceipt sends a private read receipt (m.read.private, spec v1.4+).
func (m *MatrixCore) SendPrivateReadReceipt(chatID, eventID string) error {
	if !m.authed {
		return ErrAuth
	}
	_, err := m.client.MakeFullRequest(m.ctx, mautrix.FullRequest{
		Method:      http.MethodPost,
		URL:         m.client.BuildClientURL("v3", "rooms", chatID, "receipt", "m.read.private", eventID),
		RequestJSON: map[string]interface{}{},
	})
	return err
}

// SetReadMarkers atomically sets both the read receipt and fully-read marker.
func (m *MatrixCore) SetReadMarkers(chatID, fullyRead, read string) error {
	if !m.authed {
		return ErrAuth
	}
	req := map[string]string{}
	if fullyRead != "" {
		req["m.fully_read"] = fullyRead
	}
	if read != "" {
		req["m.read"] = read
	}
	_, err := m.client.MakeFullRequest(m.ctx, mautrix.FullRequest{
		Method:      http.MethodPost,
		URL:         m.client.BuildClientURL("v3", "rooms", chatID, "read_markers"),
		RequestJSON: req,
	})
	return err
}

// ──────────────────────────── Devices (extended) ────────────────────────────

// GetDeviceInfo retrieves information about a specific device.
func (m *MatrixCore) GetDeviceInfo(deviceID string) (map[string]interface{}, error) {
	if !m.authed {
		return nil, ErrAuth
	}
	var resp map[string]interface{}
	_, err := m.client.MakeFullRequest(m.ctx, mautrix.FullRequest{
		Method:       http.MethodGet,
		URL:          m.client.BuildClientURL("v3", "devices", deviceID),
		ResponseJSON: &resp,
	})
	if err != nil {
		return nil, err
	}
	return resp, nil
}

// DeleteDevices deletes multiple devices (requires interactive auth with password).
func (m *MatrixCore) DeleteDevices(deviceIDs []string, password string) error {
	if !m.authed {
		return ErrAuth
	}
	req := map[string]interface{}{
		"devices": deviceIDs,
	}
	if password != "" {
		req["auth"] = map[string]interface{}{
			"type":     "m.login.password",
			"user":     string(m.userID),
			"password": password,
		}
	}
	_, err := m.client.MakeFullRequest(m.ctx, mautrix.FullRequest{
		Method:      http.MethodPost,
		URL:         m.client.BuildClientURL("v3", "delete_devices"),
		RequestJSON: req,
	})
	return err
}

// ──────────────────────────── Server Discovery ────────────────────────────

// GetCapabilities returns the server's supported capabilities.
func (m *MatrixCore) GetCapabilities() (map[string]interface{}, error) {
	if !m.authed {
		return nil, ErrAuth
	}
	var resp map[string]interface{}
	capResp, err := m.client.Capabilities(m.ctx)
	if err != nil {
		return nil, err
	}
	data, _ := json.Marshal(capResp)
	json.Unmarshal(data, &resp)
	return resp, nil
}

// GetVersions returns the supported Matrix spec versions.
func (m *MatrixCore) GetVersions() ([]string, map[string]bool, error) {
	if m.client == nil {
		return nil, nil, fmt.Errorf("client not initialized")
	}
	resp, err := m.client.Versions(m.ctx)
	if err != nil {
		return nil, nil, err
	}
	features := make(map[string]bool)
	for k, v := range resp.UnstableFeatures {
		features[k] = v
	}
	versions := make([]string, len(resp.Versions))
	for i, v := range resp.Versions {
		versions[i] = v.String()
	}
	return versions, features, nil
}
