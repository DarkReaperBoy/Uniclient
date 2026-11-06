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
