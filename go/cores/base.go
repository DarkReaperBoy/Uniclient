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
	Bio         string `json:"bio,omitempty"`
	AvatarURL   string `json:"avatar_url,omitempty"`
	AvatarB64   string `json:"avatar_b64,omitempty"` // base64-encoded thumbnail
	IsBot       bool   `json:"is_bot"`
	IsOnline    bool   `json:"is_online"`
	IsContact   bool   `json:"is_contact"`
	IsBlocked   bool   `json:"is_blocked"`
	LastSeen      *time.Time `json:"last_seen,omitempty"`
	LastSeenKind  string     `json:"last_seen_kind,omitempty"`
	IsVerified    bool       `json:"is_verified,omitempty"`
	IsPremium     bool       `json:"is_premium,omitempty"`
	IsScam        bool       `json:"is_scam,omitempty"`
	IsFake        bool       `json:"is_fake,omitempty"`
	EmojiStatusID string     `json:"emoji_status_id,omitempty"`
	BotMenuText   string     `json:"bot_menu_text,omitempty"`
	Role          string     `json:"role,omitempty"`
	Platform      string     `json:"platform"`
	StoryCount    int        `json:"story_count,omitempty"`
	HasUnreadStory bool      `json:"has_unread_story,omitempty"`
	BirthdayDay   int        `json:"birthday_day,omitempty"`
	BirthdayMonth int        `json:"birthday_month,omitempty"`
	BirthdayYear  int        `json:"birthday_year,omitempty"`
	PersonalChannelID      string `json:"personal_channel_id,omitempty"`
	PersonalChannelName    string `json:"personal_channel_name,omitempty"`
	VoiceMessagesForbidden bool   `json:"voice_messages_forbidden,omitempty"`
	ContactRequirePremium  bool   `json:"contact_require_premium,omitempty"`
	HasPersonalPhoto       bool   `json:"has_personal_photo,omitempty"`
	BannedRights           map[string]bool `json:"banned_rights,omitempty"`
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
	IsScam              bool   `json:"is_scam,omitempty"`
	IsFake              bool   `json:"is_fake,omitempty"`
	SlowmodeSeconds     int    `json:"slowmode_seconds,omitempty"`
	SlowmodeNextSendDate int64 `json:"slowmode_next_send_date,omitempty"`
	StarsToSend         int    `json:"stars_to_send,omitempty"`
	TtlPeriod           int    `json:"ttl_period,omitempty"`
	LinkedChatId        string `json:"linked_chat_id,omitempty"`
	EmojiStatusID       string `json:"emoji_status_id,omitempty"`
	StoryCount          int    `json:"story_count,omitempty"`
	HasUnreadStory      bool   `json:"has_unread_story,omitempty"`
	IsForum             bool   `json:"is_forum,omitempty"`
	WriteRestrictionType int   `json:"write_restriction_type,omitempty"`
	WriteRestrictionText string `json:"write_restriction_text,omitempty"`
	NotJoined           bool   `json:"not_joined,omitempty"`
	JoinRequest         bool   `json:"join_request,omitempty"`
	CanPost             bool   `json:"can_post,omitempty"`
	IsAdmin             bool   `json:"is_admin,omitempty"`
	NoForwards          bool   `json:"no_forwards,omitempty"`
	AccessHash          int64  `json:"-"`
	Platform            string `json:"platform"`
}

// ForumTopic represents a forum topic within a supergroup.
type ForumTopic struct {
	ID              string `json:"id"`               // root message ID (General = "1")
	Title           string `json:"title"`
	ColorID         int    `json:"color_id"`          // predefined icon color (0x6FB9F0, 0xFFD67E, etc.)
	IconEmojiID     int64  `json:"icon_emoji_id"`     // custom emoji ID, 0 for default
	CreatorID       string `json:"creator_id"`
	CreationDate    int64  `json:"creation_date"`     // unix timestamp
	IsClosed        bool   `json:"is_closed"`
	IsHidden        bool   `json:"is_hidden"`         // only for General topic
	IsMy            bool   `json:"is_my"`             // created by current user
	IsPinned        bool   `json:"is_pinned"`
	UnreadCount     int    `json:"unread_count"`
	UnreadMentions  int    `json:"unread_mentions"`
	UnreadReactions int    `json:"unread_reactions"`
	TopMessageID    string `json:"top_message_id"`
	ReadInboxMaxID  int    `json:"read_inbox_max_id"`
	ReadOutboxMaxID int    `json:"read_outbox_max_id"`
	ParentID        string `json:"parent_id"`         // parent supergroup ID
	CanEdit         bool   `json:"can_edit"`
	CanDelete       bool   `json:"can_delete"`
	CanToggleClosed bool   `json:"can_toggle_closed"`
	CanTogglePinned bool   `json:"can_toggle_pinned"`
	LastMsgText     string `json:"last_msg_text"`
	LastMsgDate     int64  `json:"last_msg_date"`
}

// IsGeneral returns true if this is the General topic (ID "1").
func (ft *ForumTopic) IsGeneral() bool { return ft.ID == "1" }

// TextEntity represents a rich-text formatting entity (bold, italic, link, etc.)
// within a message's text. Offset and Length are in UTF-16 code units to match
// Telegram's convention; the Dart side works natively in UTF-16.
type TextEntity struct {
	Type       string `json:"type"`               // "bold","italic","underline","strike","code","pre","text_url","url","mention","hashtag","bot_command","email","phone","cashtag","spoiler","blockquote","custom_emoji","mention_name","bank_card"
	Offset     int    `json:"offset"`             // start position in UTF-16 code units
	Length     int    `json:"length"`             // length in UTF-16 code units
	URL        string `json:"url,omitempty"`      // for text_url
	Language   string `json:"language,omitempty"` // for pre (code block language)
	DocumentID int64  `json:"document_id,omitempty"` // for custom_emoji
}

// Message represents a single message with its content, metadata, and attachments.
type Message struct {
	ID            string        `json:"id"`
	ChatID        string        `json:"chat_id"`
	SenderID      string        `json:"sender_id"`
	SenderName    string        `json:"sender_name"`
	SenderRank    string        `json:"sender_rank,omitempty"` // admin/creator custom title (e.g. "admin", "owner", "Head Mod")
	SenderColorID int           `json:"sender_color_id"`       // name color palette index (0..63)
	Text          string        `json:"text"`
	Entities      []TextEntity  `json:"entities,omitempty"` // rich-text entities for Text
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
	IsService     bool                   `json:"is_service"`        // service/action message (e.g. "X joined the group")
	GroupedID     string                 `json:"grouped_id,omitempty"` // album group ID (messages with same ID form an album)
	Views         int                    `json:"views,omitempty"`    // view count (channel posts)
	Forwards      int                    `json:"forwards,omitempty"` // forward/share count (channel posts)
	NoForwards    bool                   `json:"no_forwards,omitempty"` // message-level forwarding restriction (AyuNoForwards flag)
	Platform      string                 `json:"platform"`
	Extra         map[string]interface{} `json:"extra,omitempty"` // platform-specific metadata
}

// OutgoingMessage holds the content for a message being sent.
type OutgoingMessage struct {
	Text        string                 `json:"text"`
	ReplyToID   string                 `json:"reply_to_id,omitempty"`
	Entities    []TextEntity           `json:"entities,omitempty"`
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
	Emoji      string `json:"emoji"`
	Count      int    `json:"count"`
	ByMe       bool   `json:"by_me"`
	DocumentID int64  `json:"document_id,omitempty"`
	PeerID     string `json:"peer_id,omitempty"`
	PeerName   string `json:"peer_name,omitempty"`
	Date       int    `json:"date,omitempty"`
}

// GifInfo holds data for a single saved GIF animation.
type GifInfo struct {
	ThumbB64 string `json:"thumb_b64"`
	Width    int    `json:"width"`
	Height   int    `json:"height"`
	MimeType string `json:"mime_type"`
	FileID   string `json:"file_id"`
}

type SavedSublistInfo struct {
	PeerID      string `json:"peer_id"`
	PeerName    string `json:"peer_name"`
	AvatarPath  string `json:"avatar_path,omitempty"`
	Type        int    `json:"type"` // 1=user, 2=group, 3=channel
	IsPinned    bool   `json:"is_pinned"`
	TopMessage  int    `json:"top_message"`
	LastMsgText string `json:"last_msg_text,omitempty"`
	LastMsgTime int64  `json:"last_msg_time,omitempty"`
	IsSelf      bool   `json:"is_self"`
	UnreadCount int    `json:"unread_count"`
}

type SavedReactionTagInfo struct {
	Emoji      string `json:"emoji,omitempty"`
	CustomID   int64  `json:"custom_id,omitempty"`
	Title      string `json:"title,omitempty"`
	Count      int    `json:"count"`
}

// StickerInfo holds data for a single sticker in a set.
type StickerInfo struct {
	Emoji    string `json:"emoji"`
	ThumbB64 string `json:"thumb_b64"`
	Width    int    `json:"width"`
	Height   int    `json:"height"`
	MimeType string `json:"mime_type"`
	FileID   string `json:"file_id"`
}

// CustomEmojiThumb holds a document ID, its base64 thumbnail, and optional SVG path.
type CustomEmojiThumb struct {
	DocumentID int64  `json:"document_id"`
	ThumbB64   string `json:"thumb_b64"`
	PathB64    string `json:"path_b64,omitempty"`
}

// CustomEmojiFile holds a document ID, its MIME type, and the full file data.
type CustomEmojiFile struct {
	DocumentID int64  `json:"document_id"`
	MimeType   string `json:"mime_type"`
	FileData   []byte `json:"file_data"`
}

type BotCallbackResult struct {
	Message   string `json:"message"`
	URL       string `json:"url"`
	ShowAlert bool   `json:"show_alert"`
}

// StickerSetResult holds the structured result of a sticker set lookup.
type StickerSetResult struct {
	Title     string        `json:"title"`
	ShortName string        `json:"short_name"`
	Count     int           `json:"count"`
	Installed bool          `json:"installed"`
	Archived  bool          `json:"archived"`
	Animated  bool          `json:"animated"`
	Video     bool          `json:"video"`
	Masks     bool          `json:"masks"`
	Emojis    bool          `json:"emojis"`
	Stickers  []StickerInfo `json:"stickers"`
}

type EmojiSetSummary struct {
	SetID      int64         `json:"set_id"`
	AccessHash int64         `json:"access_hash"`
	Title      string        `json:"title"`
	ShortName  string        `json:"short_name"`
	Count      int           `json:"count"`
	Installed  bool          `json:"installed"`
	Premium    bool          `json:"premium"`
	Stickers   []StickerInfo `json:"stickers"`
}

type StickerPackSummary struct {
	SetID      int64         `json:"set_id"`
	AccessHash int64         `json:"access_hash"`
	Title      string        `json:"title"`
	ShortName  string        `json:"short_name"`
	Count      int           `json:"count"`
	Animated   bool          `json:"animated"`
	Video      bool          `json:"video"`
	ThumbB64   string        `json:"thumb_b64"`
	Stickers   []StickerInfo `json:"stickers"`
	Installed  bool          `json:"installed"`
}

type AttachMenuBotInfo struct {
	BotID     int64  `json:"bot_id"`
	ShortName string `json:"short_name"`
	Inactive  bool   `json:"inactive"`
}

type ReportOption struct {
	Text   string `json:"text"`
	Option []byte `json:"option"`
}

type ReportResult struct {
	Type            string         `json:"type"`
	Title           string         `json:"title,omitempty"`
	Options         []ReportOption `json:"options,omitempty"`
	CommentOptional bool           `json:"comment_optional,omitempty"`
	CommentOption   []byte         `json:"comment_option,omitempty"`
}

type WebPagePreviewResult struct {
	URL           string `json:"url"`
	SiteName      string `json:"site_name"`
	Title         string `json:"title"`
	Description   string `json:"description"`
	ThumbB64      string `json:"thumb_b64"`
	Type          string `json:"type"`
	HasLargeMedia bool   `json:"has_large_media"`
	PendingTill   int64  `json:"pending_till"`
}

type StarGiftItem struct {
	ID          int64  `json:"id"`
	Stars       int64  `json:"stars"`
	Title       string `json:"title,omitempty"`
	Limited     bool   `json:"limited,omitempty"`
	SoldOut     bool   `json:"sold_out,omitempty"`
	Birthday    bool   `json:"birthday,omitempty"`
	Remaining   int    `json:"remaining,omitempty"`
	Total       int    `json:"total,omitempty"`
	ThumbB64    string `json:"thumb_b64,omitempty"`
}

type StarGiftsResult struct {
	Gifts []StarGiftItem `json:"gifts"`
}

type PinnedGiftItem struct {
	ID       int64  `json:"id"`
	ThumbB64 string `json:"thumb_b64,omitempty"`
}

type PinnedGiftsResult struct {
	Gifts []PinnedGiftItem `json:"gifts"`
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
	IsChatList      bool    `json:"is_chat_list,omitempty"`
	Emoticon        string  `json:"emoticon,omitempty"`
}

type SuggestedFolder struct {
	Filter      Folder `json:"filter"`
	Description string `json:"description"`
}

type ChatlistInviteLink struct {
	URL       string   `json:"url"`
	Title     string   `json:"title"`
	PeerCount int      `json:"peer_count"`
	Slug      string   `json:"slug"`
	PeerIDs   []string `json:"peer_ids,omitempty"`
}

// Session represents an active login session on a device.
type Session struct {
	ID              string    `json:"id"`
	Device          string    `json:"device"`
	Platform        string    `json:"platform"`
	System          string    `json:"system,omitempty"`
	AppName         string    `json:"app_name,omitempty"`
	AppVersion      string    `json:"app_version,omitempty"`
	IP              string    `json:"ip,omitempty"`
	Location        string    `json:"location,omitempty"`
	LastActive      time.Time `json:"last_active"`
	IsCurrent       bool      `json:"is_current"`
	PasswordPending bool      `json:"password_pending,omitempty"`
	ApiID           int       `json:"api_id,omitempty"`
	OfficialApp     bool      `json:"official_app,omitempty"`
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
	Action       string            `json:"action,omitempty"` // typing action: "typing", "record_video", "upload_photo", etc.
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
	// ToggleCamera enables or disables the camera in a call.
	ToggleCamera(callID string, enabled bool) error

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

type ForwardOptions struct {
	DropAuthor   bool
	DropCaptions bool
	Silent       bool
	ScheduleDate int64
}

type StoryPostOptions struct {
	Privacy            string
	DurationHours      int
	SaveToProfile      bool
	AllowSharing       bool
	SelectedContactIDs []string
	TrimStart          float64
	TrimEnd            float64
}

type ForwardWithOptionsSupporter interface {
	ForwardMessageWithOptions(fromChatID, msgID, toChatID string, opts ForwardOptions) (*Message, error)
}

// UploadOptions provides extra control over media uploads for the resend pipeline.
type UploadOptions struct {
	Caption         string
	CaptionEntities string
	Silent          bool
	ScheduleDate    int64
	IsVoice         bool
	IsVideoNote     bool
	Width           int
	Height          int
	Duration        int
	Spoiler         bool
	SendAsDocument  bool
	CaptionAbove    bool
	VideoCoverPath  string
}

// UploadWithOptionsSupporter allows uploading files with extra metadata.
type UploadWithOptionsSupporter interface {
	UploadFileWithOptions(chatID string, file FileUpload, opts UploadOptions, progress func(sent, total int64)) (*Message, error)
}

// AlbumItem represents one item in a media album for batch sending.
type AlbumItem struct {
	Upload  FileUpload
	Caption string
	IsPhoto bool
}

// MediaAlbumSender can send multiple media items as a single album message.
type MediaAlbumSender interface {
	SendMediaAlbum(chatID string, items []AlbumItem, silent bool, scheduleDate int64) ([]*Message, error)
}
