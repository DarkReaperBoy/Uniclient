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
	ErrDisconnected   = errors.New("disconnected")
	ErrTimeout        = errors.New("operation timed out")
)

// --- Enums ---

// ChatType represents the kind of chat (DM, group, channel, or topic).
type ChatType string

const (
	ChatTypeDM      ChatType = "dm"
	ChatTypeGroup   ChatType = "group"
	ChatTypeChannel ChatType = "channel"
	ChatTypeTopic   ChatType = "topic"
)

// MessageStatus represents the delivery state of a message.
type MessageStatus string

const (
	MessageStatusSending   MessageStatus = "sending"
	MessageStatusSent      MessageStatus = "sent"
	MessageStatusDelivered MessageStatus = "delivered"
	MessageStatusRead      MessageStatus = "read"
	MessageStatusFailed    MessageStatus = "failed"
)

// UpdateType represents the kind of real-time event received from the platform.
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
	UpdateConnectivity   UpdateType = "connectivity"
)

// CallState represents the current phase of a voice or video call.
type CallState string

const (
	CallStateRinging    CallState = "ringing"
	CallStateConnecting CallState = "connecting"
	CallStateActive     CallState = "active"
	CallStateEnded      CallState = "ended"
)

// AuthMode represents the authentication method (bot token or user login).
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

// AuthConfig holds the credentials and settings needed to authenticate with a platform.
type AuthConfig struct {
	Mode       AuthMode          `json:"mode"`
	BotToken   string            `json:"bot_token,omitempty"`
	Phone      string            `json:"phone,omitempty"`
	OTP        string            `json:"otp,omitempty"`
	Password2F string            `json:"password_2f,omitempty"` // 2FA password
	Extra      map[string]string `json:"extra,omitempty"`       // platform-specific (e.g., api_id, api_hash, server)
}

// PaginationOpts controls result pagination with a limit and an opaque cursor.
type PaginationOpts struct {
	Limit  int    `json:"limit"`
	Offset string `json:"offset,omitempty"` // opaque cursor, platform-specific
}

// User represents a platform user or bot with profile information.
type User struct {
	ID          string `json:"id"`
	Username    string `json:"username,omitempty"`
	DisplayName string `json:"display_name"`
	Phone       string `json:"phone,omitempty"`
	AvatarURL   string `json:"avatar_url,omitempty"`
	AvatarB64   string `json:"avatar_b64,omitempty"` // base64-encoded thumbnail
	IsBot       bool   `json:"is_bot"`
	IsOnline    bool   `json:"is_online"`
	IsContact   bool   `json:"is_contact"`
	IsBlocked   bool   `json:"is_blocked"`
	LastSeen    *time.Time `json:"last_seen,omitempty"`
	IsVerified  bool   `json:"is_verified,omitempty"`
	IsPremium   bool   `json:"is_premium,omitempty"`
	Platform    string `json:"platform"`
}

// Dialog represents a conversation (DM, group, channel, or topic) in the chat list.
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
	UnreadMark          bool `json:"unread_mark,omitempty"`
	UnreadMentionCount  int  `json:"unread_mention_count,omitempty"`
	UnreadReactionCount int  `json:"unread_reaction_count,omitempty"`
	IsVerified          bool `json:"is_verified,omitempty"`
	IsScam        bool       `json:"is_scam,omitempty"`
	IsFake        bool       `json:"is_fake,omitempty"`
	Platform      string     `json:"platform"`
}

// Message represents a single message with its content, metadata, and attachments.
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
	IsOutgoing    bool                   `json:"is_outgoing"`
	Platform      string                 `json:"platform"`
	Extra         map[string]interface{} `json:"extra,omitempty"` // platform-specific metadata
}

// OutgoingMessage holds the content for a message being sent.
type OutgoingMessage struct {
	Text        string                 `json:"text"`
	ReplyToID   string                 `json:"reply_to_id,omitempty"`
	Attachments []FileRef              `json:"attachments,omitempty"`
	Extra       map[string]interface{} `json:"extra,omitempty"` // platform-specific metadata
}

// FileRef represents a reference to a file attachment with optional thumbnail.
type FileRef struct {
	ID       string `json:"id,omitempty"`  // platform file ID (for downloads)
	Name     string `json:"name"`
	MimeType string `json:"mime_type"`
	Size     int64  `json:"size"`
	URL      string `json:"url,omitempty"`       // download URL if available
	ThumbB64 string `json:"thumb_b64,omitempty"` // base64 thumbnail
	Extra    string `json:"extra,omitempty"`     // platform-specific metadata (e.g. Matrix encrypted file info JSON)
	Width    int    `json:"width,omitempty"`     // media width in pixels (images/videos)
	Height   int    `json:"height,omitempty"`    // media height in pixels (images/videos)
	Duration int    `json:"duration,omitempty"`  // duration in seconds (audio/video)
}

// FileUpload holds file metadata and a data stream for uploading.
type FileUpload struct {
	Name     string    `json:"name"`
	MimeType string    `json:"mime_type"`
	Size     int64     `json:"size"`
	Reader   io.Reader `json:"-"` // the file data stream
}

// Reaction represents an emoji reaction on a message with its count.
type Reaction struct {
	Emoji string `json:"emoji"`
	Count int    `json:"count"`
	ByMe  bool   `json:"by_me"`
}

// ReadState tracks the last-read message positions for the current user and peers.
type ReadState struct {
	MyLastRead   string            `json:"my_last_read"`
	PeerLastRead map[string]string `json:"peer_last_read"` // userID → message ID
}

// CallSession represents an active or pending voice/video call with its participants.
type CallSession struct {
	ID           string            `json:"id"`
	ChatID       string            `json:"chat_id"`
	IsVideo      bool              `json:"is_video"`
	IsGroup      bool              `json:"is_group"`
	Participants []CallParticipant `json:"participants"`
	State        CallState         `json:"state"`
	Meta         map[string]string `json:"meta,omitempty"` // platform-specific transport info (e.g. livekit_url, livekit_token, room)
}

// CallParticipant represents a user in a call with their audio/video state.
type CallParticipant struct {
	UserID      string `json:"user_id"`
	DisplayName string `json:"display_name"`
	IsMuted     bool   `json:"is_muted"`
	IsSpeaking  bool   `json:"is_speaking"`
	HasVideo    bool   `json:"has_video"`
}

// Folder represents a named collection of chats for organizing the dialog list.
// Filter flags (Contacts, Groups, etc.) define type-based inclusion rules;
// a chat matches the folder if it's in ChatIDs OR matches any active flag.
// ExcludeChatIDs are always excluded. PinnedChatIDs are shown first.
type Folder struct {
	ID             string   `json:"id"`
	Name           string   `json:"name"`
	ChatIDs        []string `json:"chat_ids"`
	ExcludeChatIDs []string `json:"exclude_chat_ids,omitempty"`
	PinnedChatIDs  []string `json:"pinned_chat_ids,omitempty"`
	Contacts       bool     `json:"contacts,omitempty"`
	NonContacts    bool     `json:"non_contacts,omitempty"`
	Groups         bool     `json:"groups,omitempty"`
	Channels       bool     `json:"channels,omitempty"`
	Bots           bool     `json:"bots,omitempty"`
	ExcludeMuted   bool     `json:"exclude_muted,omitempty"`
	ExcludeRead    bool     `json:"exclude_read,omitempty"`
	ExcludeArchived bool    `json:"exclude_archived,omitempty"`
}

// Session represents an active login session on a device.
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

// Update represents a real-time event pushed from the platform to the client.
type Update struct {
	Type         UpdateType        `json:"type"`
	ChatID       string            `json:"chat_id,omitempty"`
	Message      *Message          `json:"message,omitempty"`
	MessageID    string            `json:"message_id,omitempty"`
	UserID       string            `json:"user_id,omitempty"`
	ReadState    *ReadState        `json:"read_state,omitempty"`
	Call         *CallSession      `json:"call,omitempty"`
	IsOnline     *bool             `json:"is_online,omitempty"`
	// LastSeenKind carries coarse last-seen visibility for user_status updates:
	// "online", "recently", "within_week", "within_month", "long_ago", "exact", "hidden".
	// When "exact", LastSeen holds the actual timestamp.
	LastSeenKind string            `json:"last_seen_kind,omitempty"`
	LastSeen     *time.Time        `json:"last_seen,omitempty"`
	Verification *VerificationInfo `json:"verification,omitempty"`
	ConnState    string            `json:"conn_state,omitempty"` // "connected", "disconnected", "reconnecting"
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
	// Name returns the platform identifier (e.g. "telegram", "bale").
	Name() string
	// Capabilities returns the list of feature capability strings this core supports.
	Capabilities() []string

	// Authenticate logs into the platform using the provided credentials.
	Authenticate(cfg AuthConfig) error
	// Logout terminates the current session and clears stored credentials.
	Logout() error

	// GetDialogs returns a paginated list of conversations.
	GetDialogs(opts PaginationOpts) ([]Dialog, error)
	// CreateGroup creates a new group chat with the given members.
	CreateGroup(name string, members []string) (*Dialog, error)
	// CreateChannel creates a new broadcast channel with a name and description.
	CreateChannel(name string, description string) (*Dialog, error)
	// CreateTopic creates a new topic thread inside a group or channel.
	CreateTopic(chatID string, name string) (*Dialog, error)
	// GetFolders returns all chat folders for the current user.
	GetFolders() ([]Folder, error)
	// CreateFolder creates a new chat folder containing the specified chats.
	CreateFolder(name string, chatIDs []string) (*Folder, error)

	// SendMessage sends a message to the specified chat.
	SendMessage(chatID string, msg OutgoingMessage) (*Message, error)
	// GetMessages returns a paginated list of messages from a chat.
	GetMessages(chatID string, opts PaginationOpts) ([]Message, error)
	// EditMessage modifies the text of an existing message.
	EditMessage(chatID string, msgID string, text string) (*Message, error)
	// DeleteMessage removes a message from a chat.
	DeleteMessage(chatID string, msgID string) error
	// ReplyToMessage sends a message as a reply to an existing message.
	ReplyToMessage(chatID string, replyToMsgID string, msg OutgoingMessage) (*Message, error)
	// ForwardMessage forwards a message from one chat to another.
	ForwardMessage(fromChatID string, msgID string, toChatID string) (*Message, error)
	// ReactToMessage adds or changes an emoji reaction on a message.
	ReactToMessage(chatID string, msgID string, emoji string) error
	// PinMessage pins a message in a chat.
	PinMessage(chatID string, msgID string) error
	// UnpinMessage unpins a previously pinned message.
	UnpinMessage(chatID string, msgID string) error

	// MarkAsRead marks all messages up to the given ID as read.
	MarkAsRead(chatID string, upToMsgID string) error
	// GetReadState returns the read-state positions for a chat.
	GetReadState(chatID string) (*ReadState, error)

	// UploadFile uploads a file to a chat, reporting progress via callback.
	UploadFile(chatID string, file FileUpload, progress func(sent, total int64)) (*Message, error)
	// DownloadFile downloads a file to the given destination path, reporting progress via callback.
	DownloadFile(fileRef FileRef, dest string, progress func(recv, total int64)) error

	// SendImageBase64 sends a base64-encoded image with an optional caption.
	SendImageBase64(chatID string, b64 string, caption string) (*Message, error)

	// StartCall initiates a voice or video call in the specified chat.
	StartCall(chatID string, video bool) (*CallSession, error)
	// JoinGroupCall joins an ongoing group call in the specified chat.
	JoinGroupCall(chatID string) (*CallSession, error)
	// EndCall terminates an active call.
	EndCall(callID string) error
	// SetCallMuted mutes or unmutes the local microphone in a call.
	SetCallMuted(callID string, muted bool) error

	// GetProfile returns the profile information for a user.
	GetProfile(userID string) (*User, error)

	// OnUpdate registers a handler that receives real-time platform events.
	OnUpdate(handler func(Update))
	// Close disconnects from the platform and releases all resources.
	Close() error

	// --- Unified chat management ---

	// GetChatInfo returns detailed information about a chat.
	GetChatInfo(chatID string) (*Dialog, error)
	// EditChatTitle changes the title of a group or channel.
	EditChatTitle(chatID string, title string) error
	// EditChatDescription changes the description of a group or channel.
	EditChatDescription(chatID string, description string) error
	// LeaveChat removes the current user from a chat.
	LeaveChat(chatID string) error
	// GetInviteLink returns or generates an invite link for a chat.
	GetInviteLink(chatID string) (string, error)

	// AddMembers adds users to a group or channel.
	AddMembers(chatID string, userIDs []string) error
	// RemoveMember removes a user from a group or channel.
	RemoveMember(chatID string, userID string) error
	// BanMember bans a user from a group or channel.
	BanMember(chatID string, userID string) error
	// UnbanMember lifts a ban on a user in a group or channel.
	UnbanMember(chatID string, userID string) error
	// GetMembers returns a paginated list of members in a chat.
	GetMembers(chatID string, opts PaginationOpts) ([]User, error)
	// SetAdmin grants or revokes admin privileges for a user in a chat.
	SetAdmin(chatID string, userID string, admin bool) error

	// GetContacts returns the current user's contact list.
	GetContacts() ([]User, error)
	// AddContact adds a new contact by phone number and name.
	AddContact(phone string, firstName string, lastName string) error
	// DeleteContact removes a user from the contact list.
	DeleteContact(userID string) error
	// BlockUser blocks a user, preventing them from sending messages.
	BlockUser(userID string) error
	// UnblockUser unblocks a previously blocked user.
	UnblockUser(userID string) error
	// GetBlockedUsers returns the list of blocked users.
	GetBlockedUsers() ([]User, error)

	// SearchMessages searches for messages matching a query within a chat.
	SearchMessages(chatID string, query string, opts PaginationOpts) ([]Message, error)
	// SearchGlobal searches for chats matching a query across all conversations.
	SearchGlobal(query string, opts PaginationOpts) ([]Dialog, error)

	// SendTyping sends a typing indicator to a chat.
	SendTyping(chatID string) error

	// CreatePoll creates a poll message with a question and answer options.
	CreatePoll(chatID string, question string, options []string) (*Message, error)
	// VotePoll casts a vote on a poll by selecting an option index.
	VotePoll(chatID string, msgID string, optionIndex int) error

	// SendSticker sends a sticker by its platform-specific ID.
	SendSticker(chatID string, stickerID string) (*Message, error)

	// GetSessions returns all active login sessions for the current user.
	GetSessions() ([]Session, error)
	// TerminateSession ends a specific login session by its ID.
	TerminateSession(sessionID string) error

	// MuteChat enables or disables notifications for a chat.
	MuteChat(chatID string, muted bool) error
	// ArchiveChat moves a chat into or out of the archive.
	ArchiveChat(chatID string, archived bool) error
	// MarkUnread marks or unmarks a chat as unread.
	MarkUnread(chatID string, unread bool) error
	// UnpinAllMessages unpins every pinned message in a chat.
	UnpinAllMessages(chatID string) error

	// AcceptCall accepts an incoming call and returns the call session.
	AcceptCall(callID string) (*CallSession, error)
	// DeclineCall rejects an incoming call.
	DeclineCall(callID string) error

	// SendLocation sends a geographic location as a message.
	SendLocation(chatID string, lat float64, lon float64) (*Message, error)
}
