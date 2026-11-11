package cores

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"time"
)

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
	ErrTruncated      = errors.New("truncated download")
	ErrFileTooLarge   = errors.New("exceeds download ceiling")
)

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
	UpdateNewMessage       UpdateType = "new_message"
	UpdateEditMessage      UpdateType = "edit_message"
	UpdateDeleteMessage    UpdateType = "delete_message"
	UpdateReadState        UpdateType = "read_state"
	UpdateUserStatus       UpdateType = "user_status"
	UpdateTyping           UpdateType = "typing"
	UpdateCallState        UpdateType = "call_state"
	UpdateGroupCallMessage UpdateType = "group_call_message"
	UpdateGroupMembers     UpdateType = "group_members"
	UpdateVerification     UpdateType = "verification"
	UpdateConnectivity     UpdateType = "connectivity"
	UpdateNotifySettings   UpdateType = "notify_settings"
	UpdateLoginCode        UpdateType = "login_code"
	UpdateReactions        UpdateType = "reactions"
	UpdatePollResults      UpdateType = "poll_results"
	UpdateTranscription    UpdateType = "transcription"
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

const (
	CapText          = "TEXT"
	CapChannels      = "CHANNELS"
	CapTopics        = "TOPICS"
	CapThreads       = "THREADS"
	CapCalls         = "CALLS"
	CapGroupCalls    = "GROUP_CALLS"
	CapReactions     = "REACTIONS"
	CapReadReceipts  = "READ_RECEIPTS"
	CapTyping        = "TYPING"
	CapPolls         = "POLLS"
	CapStickers      = "STICKERS"
	CapFolders       = "FOLDERS"
	CapAdmin         = "ADMIN"
	CapSessions      = "SESSIONS"
	CapSearch        = "SEARCH"
	CapE2EE          = "E2EE"
	CapPresence      = "PRESENCE"
	CapBase64Image   = "BASE64_IMAGE"
	CapVoice         = "VOICE"
	CapVoiceRooms    = "VOICE_ROOMS"
	CapBlocking      = "BLOCKING"
	CapLocation      = "LOCATION"
	CapScheduled     = "SCHEDULED"
	CapSpaces        = "SPACES"
	CapFileTransfer  = "FILE_TRANSFER"
	CapCloudPassword = "CLOUD_PASSWORD"
)

type AuthConfig struct {
	Mode       AuthMode          `json:"mode"`
	BotToken   string            `json:"bot_token,omitempty"`
	Phone      string            `json:"phone,omitempty"`
	OTP        string            `json:"otp,omitempty"`
	Password2F string            `json:"password_2f,omitempty"`
	Extra      map[string]string `json:"extra,omitempty"`
}

type PaginationOpts struct {
	Limit  int    `json:"limit"`
	Offset string `json:"offset,omitempty"`
}

type User struct {
	ID                     string          `json:"id"`
	Username               string          `json:"username,omitempty"`
	DisplayName            string          `json:"display_name"`
	Phone                  string          `json:"phone,omitempty"`
	Bio                    string          `json:"bio,omitempty"`
	AvatarURL              string          `json:"avatar_url,omitempty"`
	AvatarB64              string          `json:"avatar_b64,omitempty"`
	IsBot                  bool            `json:"is_bot"`
	IsOnline               bool            `json:"is_online"`
	IsContact              bool            `json:"is_contact"`
	IsBlocked              bool            `json:"is_blocked"`
	LastSeen               *time.Time      `json:"last_seen,omitempty"`
	LastSeenKind           string          `json:"last_seen_kind,omitempty"`
	IsVerified             bool            `json:"is_verified,omitempty"`
	IsPremium              bool            `json:"is_premium,omitempty"`
	IsScam                 bool            `json:"is_scam,omitempty"`
	IsFake                 bool            `json:"is_fake,omitempty"`
	EmojiStatusID          string          `json:"emoji_status_id,omitempty"`
	BotMenuText            string          `json:"bot_menu_text,omitempty"`
	BotDescription         string          `json:"bot_description,omitempty"`
	BotPrivacyURL          string          `json:"bot_privacy_url,omitempty"`
	Role                   string          `json:"role,omitempty"`
	Platform               string          `json:"platform"`
	StoryCount             int             `json:"story_count,omitempty"`
	HasUnreadStory         bool            `json:"has_unread_story,omitempty"`
	BirthdayDay            int             `json:"birthday_day,omitempty"`
	BirthdayMonth          int             `json:"birthday_month,omitempty"`
	BirthdayYear           int             `json:"birthday_year,omitempty"`
	PersonalChannelID      string          `json:"personal_channel_id,omitempty"`
	PersonalChannelName    string          `json:"personal_channel_name,omitempty"`
	PersonalChannelCount   int             `json:"personal_channel_count,omitempty"`
	VoiceMessagesForbidden bool            `json:"voice_messages_forbidden,omitempty"`
	ContactRequirePremium  bool            `json:"contact_require_premium,omitempty"`
	IsMutualContact        bool            `json:"is_mutual_contact,omitempty"`
	HasPersonalPhoto       bool            `json:"has_personal_photo,omitempty"`
	PersonalPhotoId        string          `json:"personal_photo_id,omitempty"`
	FallbackPhotoId        string          `json:"fallback_photo_id,omitempty"`
	UserpicPhotoId         string          `json:"userpic_photo_id,omitempty"`
	VideoStartPosition     int             `json:"video_start_position,omitempty"`
	Note                   string          `json:"note,omitempty"`
	NoteEntities           string          `json:"note_entities,omitempty"`
	BusinessHours          string          `json:"business_hours,omitempty"`
	BannedRights           map[string]bool `json:"banned_rights,omitempty"`
	AdminRights            map[string]bool `json:"admin_rights,omitempty"`
	Rank                   string          `json:"rank,omitempty"`
	BannedUntil            int             `json:"banned_until,omitempty"`
	BannedBy               string          `json:"banned_by,omitempty"`
	BannedByName           string          `json:"banned_by_name,omitempty"`
	BannedDate             int             `json:"banned_date,omitempty"`
	StarsPerMessage        int64           `json:"stars_per_message,omitempty"`
	NeedContactsException  bool            `json:"need_contacts_exception,omitempty"`
}

type Dialog struct {
	ID                   string   `json:"id"`
	Type                 ChatType `json:"type"`
	Title                string   `json:"title"`
	AvatarURL            string   `json:"avatar_url,omitempty"`
	AvatarB64            string   `json:"avatar_b64,omitempty"`
	LastMessage          *Message `json:"last_message,omitempty"`
	UnreadCount          int      `json:"unread_count"`
	ReadInboxMaxID       int      `json:"read_inbox_max_id,omitempty"`
	ReadOutboxMaxID      int      `json:"read_outbox_max_id,omitempty"`
	IsMuted              bool     `json:"is_muted"`
	IsPinned             bool     `json:"is_pinned"`
	IsArchived           bool     `json:"is_archived"`
	MemberCount          int      `json:"member_count,omitempty"`
	ParentID             string   `json:"parent_id,omitempty"`
	UnreadMark           bool     `json:"unread_mark,omitempty"`
	UnreadMentionCount   int      `json:"unread_mention_count,omitempty"`
	UnreadReactionCount  int      `json:"unread_reaction_count,omitempty"`
	IsVerified           bool     `json:"is_verified,omitempty"`
	IsScam               bool     `json:"is_scam,omitempty"`
	IsFake               bool     `json:"is_fake,omitempty"`
	SlowmodeSeconds      int      `json:"slowmode_seconds,omitempty"`
	SlowmodeNextSendDate int64    `json:"slowmode_next_send_date,omitempty"`
	StarsToSend          int      `json:"stars_to_send,omitempty"`
	TtlPeriod            int      `json:"ttl_period,omitempty"`
	LinkedChatId         string   `json:"linked_chat_id,omitempty"`
	EmojiStatusID        string   `json:"emoji_status_id,omitempty"`
	StoryCount           int      `json:"story_count,omitempty"`
	HasUnreadStory       bool     `json:"has_unread_story,omitempty"`
	IsForum              bool     `json:"is_forum,omitempty"`
	WriteRestrictionType int      `json:"write_restriction_type,omitempty"`
	WriteRestrictionText string   `json:"write_restriction_text,omitempty"`
	NotJoined            bool     `json:"not_joined,omitempty"`
	JoinRequest          bool     `json:"join_request,omitempty"`
	CanPost              bool     `json:"can_post,omitempty"`
	IsAdmin              bool     `json:"is_admin,omitempty"`
	IsCreator            bool     `json:"is_creator,omitempty"`
	NoForwards           bool     `json:"no_forwards,omitempty"`
	Username             string   `json:"username,omitempty"`
	HasActiveCall        bool     `json:"has_active_call,omitempty"`
	AccessHash           int64    `json:"-"`
	Platform             string   `json:"platform"`
}

type ForumTopic struct {
	ID              string `json:"id"`
	Title           string `json:"title"`
	ColorID         int    `json:"color_id"`
	IconEmojiID     int64  `json:"icon_emoji_id"`
	CreatorID       string `json:"creator_id"`
	CreationDate    int64  `json:"creation_date"`
	IsClosed        bool   `json:"is_closed"`
	IsHidden        bool   `json:"is_hidden"`
	IsMy            bool   `json:"is_my"`
	IsPinned        bool   `json:"is_pinned"`
	UnreadCount     int    `json:"unread_count"`
	UnreadMentions  int    `json:"unread_mentions"`
	UnreadReactions int    `json:"unread_reactions"`
	TopMessageID    string `json:"top_message_id"`
	ReadInboxMaxID  int    `json:"read_inbox_max_id"`
	ReadOutboxMaxID int    `json:"read_outbox_max_id"`
	ParentID        string `json:"parent_id"`
	CanEdit         bool   `json:"can_edit"`
	CanDelete       bool   `json:"can_delete"`
	CanToggleClosed bool   `json:"can_toggle_closed"`
	CanTogglePinned bool   `json:"can_toggle_pinned"`
	LastMsgText     string `json:"last_msg_text"`
	LastMsgDate     int64  `json:"last_msg_date"`
}

func (ft *ForumTopic) IsGeneral() bool { return ft.ID == "1" }

type TextEntity struct {
	Type          string `json:"type"`
	Offset        int    `json:"offset"`
	Length        int    `json:"length"`
	URL           string `json:"url,omitempty"`
	Language      string `json:"language,omitempty"`
	DocumentID    int64  `json:"document_id,omitempty"`
	Date          int    `json:"date,omitempty"`
	DateRelative  bool   `json:"relative,omitempty"`
	DateShortTime bool   `json:"short_time,omitempty"`
	DateLongTime  bool   `json:"long_time,omitempty"`
	DateShortDate bool   `json:"short_date,omitempty"`
	DateLongDate  bool   `json:"long_date,omitempty"`
	DateDayOfWeek bool   `json:"day_of_week,omitempty"`
}

type Message struct {
	ID            string                 `json:"id"`
	ChatID        string                 `json:"chat_id"`
	SenderID      string                 `json:"sender_id"`
	SenderName    string                 `json:"sender_name"`
	SenderRank    string                 `json:"sender_rank,omitempty"`
	SenderColorID int                    `json:"sender_color_id"`
	Text          string                 `json:"text"`
	Entities      []TextEntity           `json:"entities,omitempty"`
	Timestamp     time.Time              `json:"timestamp"`
	EditedAt      *time.Time             `json:"edited_at,omitempty"`
	Status        MessageStatus          `json:"status"`
	ReplyToID     string                 `json:"reply_to_id,omitempty"`
	ReplyPreview  string                 `json:"reply_preview,omitempty"`
	ForwardFrom   string                 `json:"forward_from,omitempty"`
	ForwardFromID string                 `json:"forward_from_id,omitempty"`
	IsEncrypted   bool                   `json:"is_encrypted"`
	DecryptFailed bool                   `json:"decrypt_failed"`
	Attachments   []FileRef              `json:"attachments,omitempty"`
	Reactions     []Reaction             `json:"reactions,omitempty"`
	IsPinned      bool                   `json:"is_pinned"`
	IsOutgoing    bool                   `json:"is_outgoing"`
	IsService     bool                   `json:"is_service"`
	GroupedID     string                 `json:"grouped_id,omitempty"`
	Views         int                    `json:"views,omitempty"`
	Forwards      int                    `json:"forwards,omitempty"`
	CommentsCount int                    `json:"comments_count,omitempty"`
	ThreadRoot    string                 `json:"thread_root,omitempty"`
	SavedPeerID   string                 `json:"saved_peer_id,omitempty"`
	NoForwards    bool                   `json:"no_forwards,omitempty"`
	PaidPostType  int                    `json:"paid_post_type,omitempty"`
	Platform      string                 `json:"platform"`
	Extra         map[string]interface{} `json:"extra,omitempty"`
}

type OutgoingMessage struct {
	Text        string                 `json:"text"`
	ReplyToID   string                 `json:"reply_to_id,omitempty"`
	Entities    []TextEntity           `json:"entities,omitempty"`
	Attachments []FileRef              `json:"attachments,omitempty"`
	Extra       map[string]interface{} `json:"extra,omitempty"`
}

type FileRef struct {
	ID       string `json:"id,omitempty"`
	Name     string `json:"name"`
	MimeType string `json:"mime_type"`
	Size     int64  `json:"size"`
	URL      string `json:"url,omitempty"`
	ThumbB64 string `json:"thumb_b64,omitempty"`
	Extra    string `json:"extra,omitempty"`
	Width    int    `json:"width,omitempty"`
	Height   int    `json:"height,omitempty"`
	Duration int    `json:"duration,omitempty"`
	DC       int    `json:"dc,omitempty"`
}

type FileUpload struct {
	Name     string    `json:"name"`
	MimeType string    `json:"mime_type"`
	Size     int64     `json:"size"`
	Reader   io.Reader `json:"-"`
}

type Reaction struct {
	Emoji      string `json:"emoji"`
	Count      int    `json:"count"`
	ByMe       bool   `json:"by_me"`
	DocumentID int64  `json:"document_id,omitempty"`
	PeerID     string `json:"peer_id,omitempty"`
	PeerName   string `json:"peer_name,omitempty"`
	Date       int    `json:"date,omitempty"`
	AvatarB64  string `json:"avatar_b64,omitempty"`
}

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
	Type        int    `json:"type"`
	IsPinned    bool   `json:"is_pinned"`
	TopMessage  int    `json:"top_message"`
	LastMsgText string `json:"last_msg_text,omitempty"`
	LastMsgTime int64  `json:"last_msg_time,omitempty"`
	IsSelf      bool   `json:"is_self"`
	UnreadCount int    `json:"unread_count"`
}

type SavedReactionTagInfo struct {
	Emoji    string `json:"emoji,omitempty"`
	CustomID int64  `json:"custom_id,omitempty"`
	Title    string `json:"title,omitempty"`
	Count    int    `json:"count"`
}

type MusicTrackInfo struct {
	DocID      string `json:"doc_id"`
	AccessHash int64  `json:"access_hash,omitempty"`
	FileRefB64 string `json:"file_ref,omitempty"`
	Title      string `json:"title,omitempty"`
	Performer  string `json:"performer,omitempty"`
	Duration   int    `json:"duration,omitempty"`
	Size       int64  `json:"size,omitempty"`
	MimeType   string `json:"mime_type,omitempty"`
	FileName   string `json:"file_name,omitempty"`
}

type StickerInfo struct {
	Emoji     string `json:"emoji"`
	ThumbB64  string `json:"thumb_b64"`
	Width     int    `json:"width"`
	Height    int    `json:"height"`
	MimeType  string `json:"mime_type"`
	FileID    string `json:"file_id"`
	IsFaved   bool   `json:"is_faved,omitempty"`
	IsPremium bool   `json:"is_premium,omitempty"`
}

type CustomEmojiThumb struct {
	DocumentID int64  `json:"document_id"`
	ThumbB64   string `json:"thumb_b64"`
	PathB64    string `json:"path_b64,omitempty"`
}

type CustomEmojiFile struct {
	DocumentID    int64  `json:"document_id"`
	MimeType      string `json:"mime_type"`
	FileData      []byte `json:"file_data"`
	UsesTextColor bool   `json:"uses_text_color"`
}

type BotCallbackResult struct {
	Message   string `json:"message"`
	URL       string `json:"url"`
	ShowAlert bool   `json:"show_alert"`
}

type StickerSetResult struct {
	Title      string        `json:"title"`
	ShortName  string        `json:"short_name"`
	Count      int           `json:"count"`
	Installed  bool          `json:"installed"`
	Archived   bool          `json:"archived"`
	Animated   bool          `json:"animated"`
	Video      bool          `json:"video"`
	Masks      bool          `json:"masks"`
	Emojis     bool          `json:"emojis"`
	Stickers   []StickerInfo `json:"stickers"`
	IsCreator  bool          `json:"is_creator,omitempty"`
	IsPremium  bool          `json:"is_premium,omitempty"`
	SetID      int64         `json:"set_id,omitempty"`
	AccessHash int64         `json:"access_hash,omitempty"`
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
	Archived   bool          `json:"archived"`
	Masks      bool          `json:"masks,omitempty"`
	Emojis     bool          `json:"emojis,omitempty"`
	Official   bool          `json:"official,omitempty"`
	ThumbB64   string        `json:"thumb_b64"`
	Stickers   []StickerInfo `json:"stickers"`
	Installed  bool          `json:"installed"`
}

type AttachMenuBotInfo struct {
	BotID     int64  `json:"bot_id"`
	ShortName string `json:"short_name"`
	Inactive  bool   `json:"inactive"`
	Username  string `json:"username"`
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
	Author        string `json:"author"`
	EmbedURL      string `json:"embed_url"`
	HasPhoto      bool   `json:"has_photo"`
	HasDocument   bool   `json:"has_document"`
	HasUniqueGift bool   `json:"has_unique_gift"`
	HasIV         bool   `json:"has_iv"`
}

type ReadState struct {
	MyLastRead   string            `json:"my_last_read"`
	PeerLastRead map[string]string `json:"peer_last_read"`
}

type CallSession struct {
	ID           string            `json:"id"`
	ChatID       string            `json:"chat_id"`
	IsVideo      bool              `json:"is_video"`
	IsGroup      bool              `json:"is_group"`
	Participants []CallParticipant `json:"participants"`
	State        CallState         `json:"state"`
	Meta         map[string]string `json:"meta,omitempty"`
}

type CallParticipant struct {
	UserID             string  `json:"user_id"`
	DisplayName        string  `json:"display_name"`
	IsMuted            bool    `json:"is_muted"`
	IsSpeaking         bool    `json:"is_speaking"`
	HasVideo           bool    `json:"has_video"`
	CanSelfUnmute      bool    `json:"can_self_unmute"`
	RaisedHandRating   int64   `json:"raised_hand_rating,omitempty"`
	Volume             int     `json:"volume,omitempty"`
	AudioLevel         float64 `json:"audio_level,omitempty"`
	MutedByMe          bool    `json:"muted_by_me,omitempty"`
	Sounding           bool    `json:"sounding,omitempty"`
	AdditionalSounding bool    `json:"additional_sounding,omitempty"`
	AdditionalSpeaking bool    `json:"additional_speaking,omitempty"`
	SSRC               int32   `json:"ssrc,omitempty"`
	LastActive         int64   `json:"last_active,omitempty"`
	Date               int64   `json:"date,omitempty"`
	State              string  `json:"state,omitempty"`
}

type Folder struct {
	ID              string   `json:"id"`
	Name            string   `json:"name"`
	ChatIDs         []string `json:"chat_ids"`
	ExcludeChatIDs  []string `json:"exclude_chat_ids,omitempty"`
	PinnedChatIDs   []string `json:"pinned_chat_ids,omitempty"`
	Contacts        bool     `json:"contacts,omitempty"`
	NonContacts     bool     `json:"non_contacts,omitempty"`
	Groups          bool     `json:"groups,omitempty"`
	Channels        bool     `json:"channels,omitempty"`
	Bots            bool     `json:"bots,omitempty"`
	ExcludeMuted    bool     `json:"exclude_muted,omitempty"`
	ExcludeRead     bool     `json:"exclude_read,omitempty"`
	ExcludeArchived bool     `json:"exclude_archived,omitempty"`
	IsChatList      bool     `json:"is_chat_list,omitempty"`
	Emoticon        string   `json:"emoticon,omitempty"`
}

type SuggestedFolder struct {
	Filter      Folder `json:"filter"`
	Description string `json:"description"`
}

type PromoSuggestion struct {
	Key         string `json:"key"`
	Title       string `json:"title"`
	Description string `json:"description"`
	URL         string `json:"url,omitempty"`
}

type PromoSuggestionsSnapshot struct {
	Pending []string         `json:"pending"`
	Custom  *PromoSuggestion `json:"custom,omitempty"`
}

type BirthdayContact struct {
	UserID   int64  `json:"user_id"`
	Name     string `json:"name"`
	Username string `json:"username,omitempty"`
}

type SelfSuggestionState struct {
	PhotoSet        bool `json:"photo_set"`
	BirthdaySet     bool `json:"birthday_set"`
	BirthdayIsToday bool `json:"birthday_is_today"`
}

type ChatlistInviteLink struct {
	URL       string   `json:"url"`
	Title     string   `json:"title"`
	PeerCount int      `json:"peer_count"`
	Slug      string   `json:"slug"`
	PeerIDs   []string `json:"peer_ids,omitempty"`
}

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

type Update struct {
	Type             UpdateType              `json:"type"`
	ChatID           string                  `json:"chat_id,omitempty"`
	Message          *Message                `json:"message,omitempty"`
	MessageID        string                  `json:"message_id,omitempty"`
	UserID           string                  `json:"user_id,omitempty"`
	ReadState        *ReadState              `json:"read_state,omitempty"`
	Call             *CallSession            `json:"call,omitempty"`
	IsOnline         *bool                   `json:"is_online,omitempty"`
	LastSeenKind     string                  `json:"last_seen_kind,omitempty"`
	LastSeen         *time.Time              `json:"last_seen,omitempty"`
	Verification     *VerificationInfo       `json:"verification,omitempty"`
	Action           string                  `json:"action,omitempty"`
	ConnState        string                  `json:"conn_state,omitempty"`
	NotifySettings   *NotifySettingsUpdate   `json:"notify_settings,omitempty"`
	GroupCallMessage *GroupCallMessageUpdate `json:"group_call_message,omitempty"`
	LoginCode        string                  `json:"login_code,omitempty"`
	Transcription    *TranscriptionUpdate    `json:"transcription,omitempty"`
	Platform         string                  `json:"platform"`
}

type TranscriptionUpdate struct {
	MessageID       string `json:"message_id"`
	TranscriptionID int64  `json:"transcription_id,omitempty"`
	Pending         bool   `json:"pending"`
	Text            string `json:"text,omitempty"`
}

type GroupCallMessageUpdate struct {
	CallID     string `json:"call_id"`
	ChatID     string `json:"chat_id,omitempty"`
	MessageID  string `json:"message_id,omitempty"`
	SenderID   string `json:"sender_id"`
	SenderName string `json:"sender_name,omitempty"`
	Text       string `json:"text"`
	Date       int64  `json:"date"`
	Outgoing   bool   `json:"outgoing"`
	FromAdmin  bool   `json:"from_admin,omitempty"`
	Encrypted  bool   `json:"encrypted,omitempty"`
}

type NotifySettingsUpdate struct {
	PeerType  string `json:"peer_type"`
	PeerID    int64  `json:"peer_id,omitempty"`
	Muted     bool   `json:"muted"`
	MuteUntil int32  `json:"mute_until,omitempty"`
}

type VerificationInfo struct {
	TransactionID string   `json:"transaction_id"`
	State         string   `json:"state"`
	FromUser      string   `json:"from_user,omitempty"`
	FromDevice    string   `json:"from_device,omitempty"`
	Emojis        []string `json:"emojis,omitempty"`
	EmojiSymbols  []string `json:"emoji_symbols,omitempty"`
	Decimals      []int    `json:"decimals,omitempty"`
	CancelCode    string   `json:"cancel_code,omitempty"`
	CancelReason  string   `json:"cancel_reason,omitempty"`
}

type Core interface {
	Name() string
	Capabilities() []string

	Authenticate(cfg AuthConfig) error
	Logout() error

	GetDialogs(opts PaginationOpts) ([]Dialog, error)
	CreateGroup(name string, members []string) (*Dialog, error)
	CreateChannel(name string, description string) (*Dialog, error)
	CreateTopic(chatID string, name string) (*Dialog, error)
	GetFolders() ([]Folder, error)
	CreateFolder(name string, chatIDs []string) (*Folder, error)

	SendMessage(chatID string, msg OutgoingMessage) (*Message, error)
	GetMessages(chatID string, opts PaginationOpts) ([]Message, error)
	EditMessage(chatID string, msgID string, text string) (*Message, error)
	DeleteMessage(chatID string, msgID string) error
	ReplyToMessage(chatID string, replyToMsgID string, msg OutgoingMessage) (*Message, error)
	ForwardMessage(fromChatID string, msgID string, toChatID string) (*Message, error)
	ReactToMessage(chatID string, msgID string, emoji string) error
	PinMessage(chatID string, msgID string) error
	UnpinMessage(chatID string, msgID string) error

	MarkAsRead(chatID string, upToMsgID string) error
	GetReadState(chatID string) (*ReadState, error)

	UploadFile(chatID string, file FileUpload, progress func(sent, total int64)) (*Message, error)
	DownloadFile(fileRef FileRef, dest string, progress func(recv, total int64)) error

	SendImageBase64(chatID string, b64 string, caption string) (*Message, error)

	StartCall(chatID string, video bool) (*CallSession, error)
	JoinGroupCall(chatID string) (*CallSession, error)
	EndCall(callID string) error
	SetCallMuted(callID string, muted bool) error
	ToggleCamera(callID string, enabled bool) error

	GetProfile(userID string) (*User, error)

	OnUpdate(handler func(Update))
	Close() error

	GetChatInfo(chatID string) (*Dialog, error)
	EditChatTitle(chatID string, title string) error
	EditChatDescription(chatID string, description string) error
	LeaveChat(chatID string) error
	GetInviteLink(chatID string) (string, error)

	AddMembers(chatID string, userIDs []string) error
	RemoveMember(chatID string, userID string) error
	BanMember(chatID string, userID string) error
	UnbanMember(chatID string, userID string) error
	GetMembers(chatID string, opts PaginationOpts) ([]User, error)
	SetAdmin(chatID string, userID string, admin bool) error

	GetContacts() ([]User, error)
	AddContact(phone string, firstName string, lastName string) error
	DeleteContact(userID string) error
	BlockUser(userID string) error
	UnblockUser(userID string) error
	GetBlockedUsers() ([]User, error)

	SearchMessages(chatID string, query string, opts PaginationOpts) ([]Message, error)
	SearchGlobal(query string, opts PaginationOpts) ([]Dialog, error)

	SendTyping(chatID string) error

	CreatePoll(chatID string, question string, options []string) (*Message, error)
	VotePoll(chatID string, msgID string, optionIndex int) error

	SendSticker(chatID string, stickerID string) (*Message, error)

	GetSessions() ([]Session, error)
	TerminateSession(sessionID string) error

	MuteChat(chatID string, muted bool) error
	ArchiveChat(chatID string, archived bool) error
	MarkUnread(chatID string, unread bool) error
	UnpinAllMessages(chatID string) error

	AcceptCall(callID string) (*CallSession, error)
	DeclineCall(callID string) error

	SendLocation(chatID string, lat float64, lon float64) (*Message, error)
}

type VoiceCore interface {
	SendVoiceFrame(opus []byte) error
	OnVoiceFrame(handler func(sender string, opus []byte))
	SetVoiceMuted(muted bool) error
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
	ExcludedContactIDs []string
	TrimStart          float64
	TrimEnd            float64
	OverlayData        []byte
}

type ForwardWithOptionsSupporter interface {
	ForwardMessageWithOptions(fromChatID, msgID, toChatID string, opts ForwardOptions) (*Message, error)
}

type RevokableMessageDeleter interface {
	DeleteMessageRevoke(chatID, msgID string, revoke bool) error
}

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
	SendLargePhotos bool
	SendAsSticker   bool
	ReplyToMsgID    string
	GroupID         string
	Price           int64
}

type UploadWithOptionsSupporter interface {
	UploadFileWithOptions(chatID string, file FileUpload, opts UploadOptions, progress func(sent, total int64)) (*Message, error)
}

type AlbumItem struct {
	Upload  FileUpload
	Caption string
	IsPhoto bool
}

type MediaAlbumSender interface {
	SendMediaAlbum(chatID string, items []AlbumItem, silent bool, scheduleDate int64) ([]*Message, error)
}

var DownloadCeiling int64 = 512 * 1024 * 1024

func BoundedCopy(dst io.Writer, src io.Reader, max int64) (int64, error) {
	n, err := io.Copy(dst, io.LimitReader(src, max+1))
	if n > max {
		return n, fmt.Errorf("%w: more than %d bytes", ErrFileTooLarge, max)
	}
	return n, err
}

var ApiBodyCeiling int64 = 64 << 20

var ErrBodyTooLarge = errors.New("response body exceeds ceiling")

func ReadBodyCapped(r io.Reader, max int64) ([]byte, error) {
	data, err := io.ReadAll(io.LimitReader(r, max+1))
	if err != nil {
		return nil, err
	}
	if int64(len(data)) > max {
		return nil, fmt.Errorf("%w: more than %d bytes", ErrBodyTooLarge, max)
	}
	return data, nil
}

func DecodeJSONBody(r io.Reader, v any) error {
	data, err := ReadBodyCapped(r, ApiBodyCeiling)
	if err != nil {
		return err
	}
	return json.Unmarshal(data, v)
}

var ApiHTTPClient = &http.Client{Timeout: 30 * time.Second}

var TransferHTTPClient = &http.Client{
	Transport: newTransferTransport(),
}

func newTransferTransport() http.RoundTripper {
	tr, ok := http.DefaultTransport.(*http.Transport)
	if !ok {
		return &http.Transport{Proxy: http.ProxyFromEnvironment}
	}
	clone := tr.Clone()
	clone.ResponseHeaderTimeout = 30 * time.Second
	return clone
}
