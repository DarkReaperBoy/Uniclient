package tokens

const (
	WindowMinWidth         = 380
	WindowMinHeight        = 480
	WindowDefaultWidth     = 800
	WindowDefaultHeight    = 600
	WindowBigDefaultWidth  = 1024
	WindowBigDefaultHeight = 768

	ColumnMinWidthLeft    = 260
	ColumnMaxWidthLeft    = 540
	ColumnMinWidthMain    = 380
	ColumnMinWidthThird   = 292
	ColumnMaxWidthThird   = 392
	AdaptiveChatWideWidth = 880

	DialogsRowHeight      = 62
	DialogsRowPadLeft     = 10
	DialogsRowPadTop      = 8
	DialogsRowPadRight    = 10
	DialogsRowPadBottom   = 8
	DialogsRowPhotoSize   = 46
	DialogsRowNameLeft    = 68
	DialogsRowNameTop     = 10
	DialogsRowTextLeft    = 68
	DialogsRowTextTop     = 34
	DialogsSearchInHeight = 38

	MainMenuWidth                = 274
	MainMenuCoverHeight          = 134
	MainMenuUserpicSize          = 48
	MainMenuUserpicLeft          = 24
	MainMenuUserpicTop           = 20
	MainMenuCoverNameLeft        = 26
	MainMenuCoverNameTop         = 84
	MainMenuCoverStatusLeft      = 26
	MainMenuCoverStatusTop       = 103
	MainMenuSkip                 = 6
	MainMenuFooterHeightMin      = 80
	MainMenuFooterLeft           = 25
	MainMenuFooterTelegramBottom = 38
	MainMenuButtonPadLeft        = 61
	MainMenuButtonPadTop         = 11
	MainMenuButtonPadRight       = 20
	MainMenuButtonPadBottom      = 9
	MainMenuButtonIconLeft       = 21
	MainMenuButtonToggleSkip     = 19

	FontBase  = 13
	FontBox   = 14
	EmojiSize = 18

	LayoutOneColumnMaxWidth   = ColumnMinWidthLeft + ColumnMinWidthMain
	LayoutThreeColumnMinWidth = ColumnMinWidthLeft + ColumnMinWidthMain + ColumnMinWidthThird
	DialogsWidthRatioDefault  = 5.0 / 14.0
	ThirdColumnWidthDefault   = 0

	MsgPaddingLeft   = 11
	MsgPaddingTop    = 8
	MsgPaddingRight  = 11
	MsgPaddingBottom = 8

	MsgMarginLeft        = 16
	MsgMarginTop         = 6
	MsgMarginRight       = 56
	MsgMarginBottom      = 2
	MsgMarginTopAttached = 0

	MsgPhotoSize = 33
	MsgPhotoSkip = 40
	MsgMaxWidth  = 430

	BubbleRadiusSmall             = 6
	BubbleRadiusLarge             = 16
	BubbleRadiusSliderMax         = 16
	AyuMessageBubbleRadiusDefault = 16
	MsgFileThumbRadiusSmall       = 4
	MsgFileThumbRadiusLarge       = 12

	BubbleWideMaxWidth = MsgMaxWidth + 2*MsgPhotoSkip + 2*MsgMarginLeft

	MsgServicePadLeft   = 12
	MsgServicePadTop    = 3
	MsgServicePadRight  = 12
	MsgServicePadBottom = 4

	MsgServiceMarginLeft   = 10
	MsgServiceMarginTop    = 10
	MsgServiceMarginRight  = 10
	MsgServiceMarginBottom = 2

	FontMsgName    = 13
	FontMsgService = 13
	FontMsgDate    = 13

	HistoryPaddingBottom       = 8
	HistoryUnreadBarHeight     = 32
	HistoryUnreadBarMargin     = 3
	HistoryPhotoBubbleMinWidth = 200

	ComposeFieldHeightMin  = 36
	ComposeFieldHeightMax  = 72
	ComposeFieldRichMax    = 224
	ComposeFieldFadeHeight = 6
	ComposeAnimDurationMs  = 100

	HistorySendSizeW   = 44
	HistorySendSizeH   = 46
	HistorySendRight   = 2
	HistorySendPadding = 9
	HistoryAttachSizeW = 44
	HistoryAttachSizeH = 46

	ComposePadLeft   = 2
	ComposePadTop    = 9
	ComposePadRight  = 2
	ComposePadBottom = 9

	ComposerRestHeight = ComposePadTop + ComposeFieldHeightMin + ComposePadBottom

	BoxWidth            = 320
	BoxWideWidth        = 364
	BoxPadLeft          = 24
	BoxPadTop           = 14
	BoxPadRight         = 24
	BoxPadBottom        = 8
	BoxRadius           = 6
	BoxTitlePosX        = 24
	BoxTitlePosY        = 13
	BoxTitleHeight      = 48
	BoxTitleMaxHeight   = 24
	BoxTitleAddSkip     = 9
	FontBoxTitle        = 16
	BoxButtonHeight     = 34
	BoxButtonTextTop    = 7
	BoxButtonPadLeft    = 6
	BoxButtonPadTop     = 10
	BoxButtonPadRight   = 10
	BoxButtonPadBottom  = 10
	BoxRowPadLeft       = 24
	BoxRowPadRight      = 24
	BoxTopMargin        = 8
	BoxMaxListHeight    = 492
	BoxLittleSkip       = 10
	BoxMediumSkip       = 20
	BoxCheckboxTextPosX = 12

	MenuItemPadLeft    = 17
	MenuItemPadTop     = 8
	MenuItemPadRight   = 17
	MenuItemPadBottom  = 7
	MenuItemRightSkip  = 6
	MenuWidthMin       = 156
	MenuWidthMax       = 300
	MenuRadius         = 6
	MenuScrollPad      = 8
	MenuDurationMs     = 150
	MenuShowDurationMs = 200

	ToggleDiameter   = 14
	ToggleBorder     = 2
	ToggleShift      = -2
	ToggleDurationMs = 150

	SettingsRowHeightText  = 20
	SettingsRowPadLeft     = 22
	SettingsRowPadTop      = 10
	SettingsRowPadRight    = 22
	SettingsRowPadBottom   = 8
	SettingsRowToggleSkip  = 22
	SettingsChatRowPadLeft = 60
	SettingsChatPadTop     = 10
	SettingsChatPadRight   = 22
	SettingsChatPadBottom  = 10
	SettingsChatIconLeft   = 20
)

type MainMenuEntryKind int

const (
	MenuAction MainMenuEntryKind = iota
	MenuToggle
	MenuBotList
	MenuSeparator
)

type MainMenuEntry struct {
	Kind  MainMenuEntryKind
	ID    string
	Label string
	Icon  string
}

var DefaultMainMenu = []MainMenuEntry{
	{Kind: MenuAction, ID: "my_profile", Label: "My Profile", Icon: "menuIconProfile"},
	{Kind: MenuBotList, ID: "bots"},
	{Kind: MenuSeparator},
	{Kind: MenuAction, ID: "new_group", Label: "New Group", Icon: "menuIconGroups"},
	{Kind: MenuAction, ID: "new_channel", Label: "New Channel", Icon: "menuIconChannel"},
	{Kind: MenuAction, ID: "contacts", Label: "Contacts", Icon: "menuIconUserShow"},
	{Kind: MenuAction, ID: "calls", Label: "Calls", Icon: "menuIconPhone"},
	{Kind: MenuAction, ID: "saved_messages", Label: "Saved Messages", Icon: "menuIconSavedMessages"},
	{Kind: MenuToggle, ID: "sread", Label: "Read on Server", Icon: "ayuSReadMenuIcon"},
	{Kind: MenuAction, ID: "settings", Label: "Settings", Icon: "menuIconSettings"},
	{Kind: MenuToggle, ID: "night_mode", Label: "Night Mode", Icon: "menuIconNightMode"},
	{Kind: MenuToggle, ID: "ghost_mode", Label: "Ghost Mode", Icon: "ayuGhostIcon"},
}

func MenuItemHeightFor(fontPx int) int {
	return fontPx + MenuItemPadTop + MenuItemPadBottom
}

func MainMenuRowHeight() int {
	return FontBase + MainMenuButtonPadTop + MainMenuButtonPadBottom
}
