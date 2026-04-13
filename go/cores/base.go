// Package cores defines the Core interface and shared models used by all messaging platform backends.
// Every core (Telegram, Bale, Rubika, etc.) implements the Core interface.
// No core may import from another core. All cores return these shared types.
package cores

import (
	"errors"
	"io"
	"time"
)

// --- Errors ---

var (
	ErrAuth           = errors.New("authentication failed")
	ErrNetwork        = errors.New("network error")
	ErrNotFound       = errors.New("not found")
	ErrNotSupported   = errors.New("not supported by this platform")
	ErrRateLimit      = errors.New("rate limited")
	ErrPermission     = errors.New("permission denied")
	ErrAlreadyExists  = errors.New("already exists")
	ErrInvalidInput   = errors.New("invalid input")
	ErrSessionExpired = errors.New("session expired")
)

// --- Enums ---

type ChatType string

const (
	ChatTypeDM      ChatType = "dm"
	ChatTypeGroup   ChatType = "group"
	ChatTypeChannel ChatType = "channel"
	ChatTypeTopic   ChatType = "topic"
)

type MessageStatus string

const (
	MessageStatusSending   MessageStatus = "sending"
	MessageStatusSent      MessageStatus = "sent"
	MessageStatusDelivered MessageStatus = "delivered"
	MessageStatusRead      MessageStatus = "read"
	MessageStatusFailed    MessageStatus = "failed"
)

type UpdateType string

const (
	UpdateNewMessage     UpdateType = "new_message"
	UpdateEditMessage    UpdateType = "edit_message"
	UpdateDeleteMessage  UpdateType = "delete_message"
	UpdateReadState      UpdateType = "read_state"
	UpdateUserStatus     UpdateType = "user_status"
	UpdateTyping         UpdateType = "typing"
	UpdateCallState      UpdateType = "call_state"
	UpdateGroupMembers   UpdateType = "group_members"
	UpdateVerification   UpdateType = "verification"
)

type CallState string

const (
	CallStateRinging    CallState = "ringing"
	CallStateConnecting CallState = "connecting"
	CallStateActive     CallState = "active"
	CallStateEnded      CallState = "ended"
)

type AuthMode string

const (
	AuthModeBot  AuthMode = "bot"
	AuthModeUser AuthMode = "user"
)

// --- Capability constants ---
// Return these from Capabilities() so the frontend can query supported features.

const (
	CapText         = "TEXT"
	CapChannels     = "CHANNELS"
	CapTopics       = "TOPICS"
	CapThreads      = "THREADS"
	CapCalls        = "CALLS"
	CapGroupCalls   = "GROUP_CALLS"
	CapReactions    = "REACTIONS"
	CapReadReceipts = "READ_RECEIPTS"
	CapTyping       = "TYPING"
	CapPolls        = "POLLS"
	CapStickers     = "STICKERS"
	CapFolders      = "FOLDERS"
	CapAdmin        = "ADMIN"
	CapSessions     = "SESSIONS"
	CapSearch       = "SEARCH"
	CapE2EE         = "E2EE"
	CapPresence     = "PRESENCE"
	CapBase64Image  = "BASE64_IMAGE"
	CapVoice        = "VOICE"
	CapBlocking     = "BLOCKING"
	CapLocation     = "LOCATION"
	CapScheduled    = "SCHEDULED"
	CapSpaces       = "SPACES"
	CapFileTransfer = "FILE_TRANSFER"
)

// --- Models ---

type AuthConfig struct {
	Mode       AuthMode          `json:"mode"`
	BotToken   string            `json:"bot_token,omitempty"`
	Phone      string            `json:"phone,omitempty"`
	OTP        string            `json:"otp,omitempty"`
	Password2F string            `json:"password_2f,omitempty"` // 2FA password
	Extra      map[string]string `json:"extra,omitempty"`       // platform-specific (e.g., api_id, api_hash, server)
}

type PaginationOpts struct {
	Limit  int    `json:"limit"`
	Offset string `json:"offset,omitempty"` // opaque cursor, platform-specific
}

type User struct {
	ID          string `json:"id"`
	Username    string `json:"username,omitempty"`
	DisplayName string `json:"display_name"`
	Phone       string `json:"phone,omitempty"`
	AvatarURL   string `json:"avatar_url,omitempty"`
	AvatarB64   string `json:"avatar_b64,omitempty"` // base64-encoded thumbnail
	IsBot       bool   `json:"is_bot"`
	IsOnline    bool   `json:"is_online"`
	LastSeen    *time.Time `json:"last_seen,omitempty"`
	Platform    string `json:"platform"`
}

type Dialog struct {
	ID            string     `json:"id"`
	Type          ChatType   `json:"type"`
	Title         string     `json:"title"`
	AvatarURL     string     `json:"avatar_url,omitempty"`
	AvatarB64     string     `json:"avatar_b64,omitempty"`
	LastMessage   *Message   `json:"last_message,omitempty"`
	UnreadCount   int        `json:"unread_count"`
	IsMuted       bool       `json:"is_muted"`
	IsPinned      bool       `json:"is_pinned"`
	IsArchived    bool       `json:"is_archived"`
	MemberCount   int        `json:"member_count,omitempty"`
	ParentID      string     `json:"parent_id,omitempty"` // for topics: the parent group ID
	Platform      string     `json:"platform"`
}

type Message struct {
	ID            string        `json:"id"`
	ChatID        string        `json:"chat_id"`
	SenderID      string        `json:"sender_id"`
	SenderName    string        `json:"sender_name"`
	Text          string        `json:"text"`
	Timestamp     time.Time     `json:"timestamp"`
	EditedAt      *time.Time    `json:"edited_at,omitempty"`
	Status        MessageStatus `json:"status"`
	ReplyToID     string        `json:"reply_to_id,omitempty"`
	ReplyPreview  string        `json:"reply_preview,omitempty"` // first line of the replied-to message
	ForwardFrom   string        `json:"forward_from,omitempty"`
	IsEncrypted   bool          `json:"is_encrypted"`
	DecryptFailed bool          `json:"decrypt_failed"`
	Attachments   []FileRef     `json:"attachments,omitempty"`
	Reactions     []Reaction    `json:"reactions,omitempty"`
	IsPinned      bool                   `json:"is_pinned"`
	Platform      string                 `json:"platform"`
	Extra         map[string]interface{} `json:"extra,omitempty"` // platform-specific metadata
}

type OutgoingMessage struct {
	Text        string                 `json:"text"`
	ReplyToID   string                 `json:"reply_to_id,omitempty"`
	Attachments []FileRef              `json:"attachments,omitempty"`
	Extra       map[string]interface{} `json:"extra,omitempty"` // platform-specific metadata
}

type FileRef struct {
	ID       string `json:"id,omitempty"`  // platform file ID (for downloads)
	Name     string `json:"name"`
	MimeType string `json:"mime_type"`
	Size     int64  `json:"size"`
	URL      string `json:"url,omitempty"`       // download URL if available
	ThumbB64 string `json:"thumb_b64,omitempty"` // base64 thumbnail
	Extra    string `json:"extra,omitempty"`     // platform-specific metadata (e.g. Matrix encrypted file info JSON)
}

type FileUpload struct {
	Name     string    `json:"name"`
	MimeType string    `json:"mime_type"`
	Size     int64     `json:"size"`
	Reader   io.Reader `json:"-"` // the file data stream
}

type Reaction struct {
	Emoji string `json:"emoji"`
	Count int    `json:"count"`
	ByMe  bool   `json:"by_me"`
}

type ReadState struct {
	MyLastRead   string            `json:"my_last_read"`
	PeerLastRead map[string]string `json:"peer_last_read"` // userID → message ID
}

type CallSession struct {
	ID           string            `json:"id"`
	ChatID       string            `json:"chat_id"`
	IsVideo      bool              `json:"is_video"`
	IsGroup      bool              `json:"is_group"`
	Participants []CallParticipant `json:"participants"`
	State        CallState         `json:"state"`
	Meta         map[string]string `json:"meta,omitempty"` // platform-specific transport info (e.g. livekit_url, livekit_token, room)
}

type CallParticipant struct {
	UserID      string `json:"user_id"`
	DisplayName string `json:"display_name"`
	IsMuted     bool   `json:"is_muted"`
	IsSpeaking  bool   `json:"is_speaking"`
	HasVideo    bool   `json:"has_video"`
}

type Folder struct {
	ID      string   `json:"id"`
	Name    string   `json:"name"`
	ChatIDs []string `json:"chat_ids"`
}

type Session struct {
	ID         string    `json:"id"`
	Device     string    `json:"device"`
	Platform   string    `json:"platform"`
	AppName    string    `json:"app_name,omitempty"`
	AppVersion string    `json:"app_version,omitempty"`
	IP         string    `json:"ip,omitempty"`
	Location   string    `json:"location,omitempty"`
	LastActive time.Time `json:"last_active"`
	IsCurrent  bool      `json:"is_current"`
}

type Update struct {
	Type         UpdateType        `json:"type"`
	ChatID       string            `json:"chat_id,omitempty"`
	Message      *Message          `json:"message,omitempty"`
	MessageID    string            `json:"message_id,omitempty"`
	UserID       string            `json:"user_id,omitempty"`
	ReadState    *ReadState        `json:"read_state,omitempty"`
	Call         *CallSession      `json:"call,omitempty"`
	IsOnline     *bool             `json:"is_online,omitempty"`
	Verification *VerificationInfo `json:"verification,omitempty"`
	Platform     string            `json:"platform"`
}

// VerificationInfo represents an interactive device verification event.
type VerificationInfo struct {
	TransactionID string   `json:"transaction_id"`
	State         string   `json:"state"` // "requested", "ready", "show_sas", "done", "cancelled"
	FromUser      string   `json:"from_user,omitempty"`
	FromDevice    string   `json:"from_device,omitempty"`
	Emojis        []string `json:"emojis,omitempty"`        // SAS emoji descriptions
	EmojiSymbols  []string `json:"emoji_symbols,omitempty"` // SAS emoji runes
	Decimals      []int    `json:"decimals,omitempty"`      // SAS decimal codes
	CancelCode    string   `json:"cancel_code,omitempty"`
	CancelReason  string   `json:"cancel_reason,omitempty"`
}

// --- Core Interface ---

// Core is the contract that every messaging platform must implement.
// The frontend programs against this interface exclusively.
type Core interface {
	// Identity
	Name() string
	Capabilities() []string

	// Auth
	Authenticate(cfg AuthConfig) error
	Logout() error

	// Dialogs
	GetDialogs(opts PaginationOpts) ([]Dialog, error)
	CreateGroup(name string, members []string) (*Dialog, error)
	CreateChannel(name string, description string) (*Dialog, error)
	CreateTopic(chatID string, name string) (*Dialog, error)
	GetFolders() ([]Folder, error)
	CreateFolder(name string, chatIDs []string) (*Folder, error)

	// Messages
	SendMessage(chatID string, msg OutgoingMessage) (*Message, error)
	GetMessages(chatID string, opts PaginationOpts) ([]Message, error)
	EditMessage(chatID string, msgID string, text string) (*Message, error)
	DeleteMessage(chatID string, msgID string) error
	ReplyToMessage(chatID string, replyToMsgID string, msg OutgoingMessage) (*Message, error)
	ForwardMessage(fromChatID string, msgID string, toChatID string) (*Message, error)
	ReactToMessage(chatID string, msgID string, emoji string) error
	PinMessage(chatID string, msgID string) error
	UnpinMessage(chatID string, msgID string) error

	// Read state
	MarkAsRead(chatID string, upToMsgID string) error
	GetReadState(chatID string) (*ReadState, error)

	// Files
	UploadFile(chatID string, file FileUpload, progress func(sent, total int64)) (*Message, error)
	DownloadFile(fileRef FileRef, dest string, progress func(recv, total int64)) error

	// Media
	SendImageBase64(chatID string, b64 string, caption string) (*Message, error)

	// Calls
	StartCall(chatID string, video bool) (*CallSession, error)
	JoinGroupCall(chatID string) (*CallSession, error)
	EndCall(callID string) error
	SetCallMuted(callID string, muted bool) error

	// Profile
	GetProfile(userID string) (*User, error)

	// Real-time
	OnUpdate(handler func(Update))
	Close() error

	// --- Unified chat management ---

	// Chat info & settings
	GetChatInfo(chatID string) (*Dialog, error)
	EditChatTitle(chatID string, title string) error
	EditChatDescription(chatID string, description string) error
	LeaveChat(chatID string) error
	GetInviteLink(chatID string) (string, error)

	// Member management
	AddMembers(chatID string, userIDs []string) error
	RemoveMember(chatID string, userID string) error
	BanMember(chatID string, userID string) error
	UnbanMember(chatID string, userID string) error
	GetMembers(chatID string, opts PaginationOpts) ([]User, error)
	SetAdmin(chatID string, userID string, admin bool) error

	// Contacts
	GetContacts() ([]User, error)
	AddContact(phone string, firstName string, lastName string) error
	DeleteContact(userID string) error
	BlockUser(userID string) error
	UnblockUser(userID string) error
	GetBlockedUsers() ([]User, error)

	// Search
	SearchMessages(chatID string, query string, opts PaginationOpts) ([]Message, error)
	SearchGlobal(query string, opts PaginationOpts) ([]Dialog, error)

	// Typing
	SendTyping(chatID string) error

	// Polls
	CreatePoll(chatID string, question string, options []string) (*Message, error)
	VotePoll(chatID string, msgID string, optionIndex int) error

	// Stickers
	SendSticker(chatID string, stickerID string) (*Message, error)

	// Sessions
	GetSessions() ([]Session, error)
	TerminateSession(sessionID string) error

	// Chat state
	MuteChat(chatID string, muted bool) error
	ArchiveChat(chatID string, archived bool) error
	MarkUnread(chatID string, unread bool) error
	UnpinAllMessages(chatID string) error

	// Calls (incoming)
	AcceptCall(callID string) (*CallSession, error)
	DeclineCall(callID string) error

	// Location
	SendLocation(chatID string, lat float64, lon float64) (*Message, error)
}
