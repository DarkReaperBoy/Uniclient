package cores

type GeoWebFileQuery struct {
	Lat        float64
	Long       float64
	AccessHash int64
	W          int
	H          int
	Zoom       int
	Scale      int
}

type LangPackInfo struct {
	LangCode   string `json:"lang_code"`
	Name       string `json:"name"`
	NativeName string `json:"native_name"`
	Official   bool   `json:"official"`
	Rtl        bool   `json:"rtl"`
	Beta       bool   `json:"beta"`
}

type JoinAsPeerInfo struct {
	ID        string `json:"id"`
	Title     string `json:"title"`
	Subtitle  string `json:"subtitle"`
	IsSelf    bool   `json:"is_self"`
	IsChannel bool   `json:"is_channel"`
}

type AdminLogEvent struct {
	ID         int64                  `json:"id"`
	Date       int                    `json:"date"`
	UserID     int64                  `json:"user_id"`
	UserName   string                 `json:"user_name"`
	Action     string                 `json:"action"`
	Detail     string                 `json:"detail"`
	OldValue   string                 `json:"old_value,omitempty"`
	NewValue   string                 `json:"new_value,omitempty"`
	MessageID  int                    `json:"message_id,omitempty"`
	MsgText    string                 `json:"msg_text,omitempty"`
	ActionData map[string]interface{} `json:"action_data,omitempty"`
}

type ChatPermissionFlags struct {
	SlowmodeSeconds       int      `json:"slowmode_seconds"`
	JoinToSend            bool     `json:"join_to_send"`
	NoForwards            bool     `json:"no_forwards"`
	JoinRequest           bool     `json:"join_request"`
	IsForum               bool     `json:"is_forum"`
	Antispam              bool     `json:"antispam"`
	Signatures            bool     `json:"signatures"`
	SignatureProfiles     bool     `json:"signature_profiles"`
	PreHistoryHidden      bool     `json:"pre_history_hidden"`
	NoTranslations        bool     `json:"no_translations"`
	HasUsername           bool     `json:"has_username"`
	LinkedChatID          string   `json:"linked_chat_id"`
	PendingRequestsCount  int      `json:"pending_requests_count"`
	BoostLevel            int      `json:"boost_level"`
	IsMegagroup           bool     `json:"is_megagroup"`
	IsBroadcast           bool     `json:"is_broadcast"`
	IsGigagroup           bool     `json:"is_gigagroup"`
	AmCreator             bool     `json:"am_creator"`
	HasAdminRights        bool     `json:"has_admin_rights"`
	CanViewStats          bool     `json:"can_view_stats"`
	AdminCanChangeInfo    bool     `json:"admin_can_change_info"`
	CanAddAdmins          bool     `json:"can_add_admins"`
	CanBanUsers           bool     `json:"can_ban_users"`
	CanInviteUsers        bool     `json:"can_invite_users"`
	CanViewParticipants   bool     `json:"can_view_participants"`
	ParticipantsHidden    bool     `json:"participants_hidden"`
	CanSetStickers        bool     `json:"can_set_stickers"`
	AutoTranslateMinLevel int      `json:"auto_translate_min_level"`
	MigratedFromChatID    string   `json:"migrated_from_chat_id"`
	DirectMessagesEnabled bool     `json:"direct_messages_enabled"`
	DirectMessagesStars   int64    `json:"direct_messages_stars"`
	StarRefJoinAllowed    bool     `json:"starref_join_allowed"`
	AdminCanPost          bool     `json:"admin_can_post"`
	ReactionsUniqMax      int      `json:"reactions_uniq_max"`
	ReactionsMaxCount     int      `json:"reactions_max_count"`
	PaidReactionsEnabled  bool     `json:"paid_reactions_enabled"`
	ForumTabs             bool     `json:"forum_tabs"`
	HasLocation           bool     `json:"has_location"`
	ReactionsMode         string   `json:"reactions_mode"`
	ReactionsAllowed      []string `json:"reactions_allowed"`
	AntispamGroupSizeMin  int      `json:"antispam_group_size_min"`
	MemberCount           int      `json:"member_count"`
}

type DefaultBannedRights struct {
	SendPlain        bool  `json:"send_plain"`
	SendPhotos       bool  `json:"send_photos"`
	SendVideos       bool  `json:"send_videos"`
	SendRoundvideos  bool  `json:"send_roundvideos"`
	SendAudios       bool  `json:"send_audios"`
	SendVoices       bool  `json:"send_voices"`
	SendDocs         bool  `json:"send_docs"`
	SendStickers     bool  `json:"send_stickers"`
	EmbedLinks       bool  `json:"embed_links"`
	SendPolls        bool  `json:"send_polls"`
	InviteUsers      bool  `json:"invite_users"`
	ManageTopics     bool  `json:"manage_topics"`
	PinMessages      bool  `json:"pin_messages"`
	EditRank         bool  `json:"edit_rank"`
	ChangeInfo       bool  `json:"change_info"`
	SlowmodeSeconds  int   `json:"slowmode_seconds"`
	BoostsUnrestrict int   `json:"boosts_unrestrict"`
	ChargeStars      int64 `json:"charge_stars"`
}

type ParticipantExtra struct {
	CustomRank   string
	PromotedBy   int64
	PromotedDate int
	IsSelf       bool
	IsCreator    bool
	CanEditAdmin bool
	CanRestrict  bool
	BannedRights *DefaultBannedRights
	BannedUntil  int
}

type BotCommandEntry struct {
	Command     string `json:"command"`
	Description string `json:"description"`
	BotID       string `json:"bot_id"`
	BotName     string `json:"bot_name"`
	BotUsername string `json:"bot_username"`
	AvatarB64   string `json:"avatar_b64,omitempty"`
}

type InlineBotResults struct {
	QueryID       int64             `json:"query_id"`
	NextOffset    string            `json:"next_offset"`
	Gallery       bool              `json:"gallery"`
	Results       []InlineBotResult `json:"results"`
	SwitchPM      string            `json:"switch_pm,omitempty"`
	SwitchPMParam string            `json:"switch_pm_param,omitempty"`
}

type ForumTopicIconInfo struct {
	DocumentID int64  `json:"document_id"`
	Emoji      string `json:"emoji"`
}

type ChannelUsernameInfo struct {
	Username string `json:"username"`
	Active   bool   `json:"active"`
	Editable bool   `json:"editable"`
}

type PasskeyInfo struct {
	ID   string `json:"id"`
	Name string `json:"name"`
	Date int    `json:"date"`
}

type CloudPasswordState struct {
	HasPassword             bool   `json:"hasPassword"`
	HasRecovery             bool   `json:"hasRecovery"`
	Hint                    string `json:"hint"`
	EmailUnconfirmedPattern string `json:"emailUnconfirmedPattern"`
	PendingResetDate        int    `json:"pendingResetDate"`
	LoginEmailPattern       string `json:"loginEmailPattern"`
}

type PasswordResetResult struct {
	Done      bool `json:"done"`
	UntilDate int  `json:"untilDate"`
	RetryDate int  `json:"retryDate"`
}

type ChatNotifySettings struct {
	Muted        bool
	MuteUntil    int32
	SoundOn      bool
	ShowPreviews bool
}

type PeerColorEntry struct {
	ColorID         int   `json:"color_id"`
	DayColors       []int `json:"day_colors"`
	NightColors     []int `json:"night_colors"`
	Hidden          bool  `json:"hidden"`
	ChannelMinLevel int   `json:"channel_min_level"`
	GroupMinLevel   int   `json:"group_min_level"`
}

type CloudThemeInfo struct {
	ID          int64  `json:"id"`
	AccessHash  int64  `json:"access_hash"`
	Title       string `json:"title"`
	Slug        string `json:"slug"`
	IsCreator   bool   `json:"is_creator"`
	DocumentId  int64  `json:"document_id"`
	AccentColor int    `json:"accent_color"`
	BgColor     int    `json:"bg_color"`
	SentColor   int    `json:"sent_color"`
	RecvColor   int    `json:"recv_color"`
	IsDark      bool   `json:"is_dark"`
}

type ChatThemeInfo struct {
	Emoticon         string `json:"emoticon"`
	ID               int64  `json:"id"`
	IsDark           bool   `json:"is_dark"`
	AccentColor      int    `json:"accent_color"`
	MessageColors    []int  `json:"message_colors,omitempty"`
	BgColors         []int  `json:"bg_colors,omitempty"`
	PatternIntensity int    `json:"pattern_intensity,omitempty"`
}

type WallpaperInfo struct {
	ID         int64  `json:"id"`
	Slug       string `json:"slug"`
	Pattern    bool   `json:"pattern"`
	Dark       bool   `json:"dark"`
	Default    bool   `json:"default"`
	Creator    bool   `json:"creator,omitempty"`
	Colors     []int  `json:"colors,omitempty"`
	Rotation   int    `json:"rotation"`
	Blurred    bool   `json:"blurred"`
	Motion     bool   `json:"motion,omitempty"`
	Intensity  int    `json:"intensity,omitempty"`
	AccessHash int64  `json:"access_hash,omitempty"`
	ThumbB64   string `json:"thumb_b64,omitempty"`
	IsPhoto    bool   `json:"is_photo,omitempty"`
	DocID      int64  `json:"doc_id,omitempty"`
	DocHash    int64  `json:"doc_hash,omitempty"`
	DocRef     string `json:"doc_ref,omitempty"`
}

type CallHistoryEntry struct {
	MsgID      string `json:"msg_id"`
	PeerID     string `json:"peer_id"`
	PeerName   string `json:"peer_name"`
	AvatarPath string `json:"avatar_path,omitempty"`
	Timestamp  int64  `json:"timestamp"`
	Duration   int    `json:"duration"`
	IsOutgoing bool   `json:"is_outgoing"`
	IsMissed   bool   `json:"is_missed"`
	IsVideo    bool   `json:"is_video"`
}

type DiceSticker struct {
	Value    int
	FileID   string
	Extra    string
	ThumbB64 string
	Width    int
	Height   int
}

type DiceStickersResult struct {
	Emoji    string
	Stickers []DiceSticker
}

type ChannelStats struct {
	MinDate int `json:"min_date"`
	MaxDate int `json:"max_date"`

	Followers        StatsValue `json:"followers"`
	ViewsPerPost     StatsValue `json:"views_per_post"`
	SharesPerPost    StatsValue `json:"shares_per_post"`
	ReactionsPerPost StatsValue `json:"reactions_per_post"`
	ViewsPerStory    StatsValue `json:"views_per_story"`
	SharesPerStory   StatsValue `json:"shares_per_story"`
	NotifPercent     float64    `json:"notif_percent"`

	Graphs []StatsGraphData `json:"graphs"`
}
