package tokens

import (
	"math"
	"strconv"
)

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

	DialogsFilterPadX         = 7
	DialogsFilterSkip         = 4
	DialogsFilterHeight       = 35
	DialogsFilterRadius       = 18
	DialogsFilterTextLeft     = 12
	DialogsFilterBorderActive = 2

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
	MsgMinWidth  = 160

	MsgDateSpace  = 12
	MsgDateDeltaX = 2
	MsgDateDeltaY = 5

	HistoryFastShareSize = 31

	MsgTailWidth  = 6
	MsgTailHeight = 10
	MsgShadow     = 2

	HistorySendStateSpace = 24
	HistorySendStateDX    = -17
	HistorySendStateDY    = -19

	UnlimitedBubbleWidth = 0x3FFFFFF

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

	AyuServiceTimeBadgeFontSize         = 11
	AyuServiceTimeBadgePadX             = 7
	AyuServiceTimeBadgePadY             = 2
	AyuServiceTimeBadgeGap              = 8
	AyuServiceTimeBadgeTrailingInset    = 3
	AyuServiceTimeBadgeLastLineWidthAdd = 9

	FontMsgName    = 13
	FontMsgService = 13
	FontMsgDate    = 13

	ServiceMsgRadius         = (MsgServicePadTop + FontMsgService + MsgServicePadBottom) / 2
	ServiceMsgInvertedRadius = FontMsgService - ServiceMsgRadius
	ServiceMsgInvertedShrink = (ServiceMsgInvertedRadius * 2) / 3

	HistoryPaddingBottom       = 8
	HistoryUnreadBarHeight     = 32
	HistoryUnreadBarMargin     = 3
	HistoryUnreadBarFontHeight = FontMsgService
	UnreadPillPadding          = 12
	LineWidth                  = 1
	HistoryPhotoBubbleMinWidth = 200

	ComposeFieldHeightMin  = 36
	ComposeFieldHeightMax  = 72
	ComposeFieldRichMax    = 224
	ComposeFieldFadeHeight = 6
	ComposeAnimDurationMs  = 100

	ComposeTextMarginLeft   = 0
	ComposeTextMarginTop    = 0
	ComposeTextMarginRight  = 0
	ComposeTextMarginBottom = 0

	ComposePlaceholderMarginLeft   = 2
	ComposePlaceholderMarginTop    = 0
	ComposePlaceholderMarginRight  = 2
	ComposePlaceholderMarginBottom = 0
	ComposePlaceholderShift        = -50
	ComposeCaretReserve            = 2
	ComposeCursorWidth             = 1
	ComposeFieldStyleLineHeight    = 0

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

	MenuIconSize           = 24
	MenuIconPosX           = 15
	MenuIconPosY           = 5
	MenuWithIconsPadLeft   = 54
	MenuWithIconsPadTop    = 8
	MenuWithIconsPadRight  = 17
	MenuWithIconsPadBottom = 8

	WindowTitleHeight      = 24
	WindowTitleButtonWidth = 36
	FontWindowTitle        = 12

	TopBarHeight          = 54
	TopBarButtonWidth     = 40
	TopBarMenuButtonWidth = 44
	TopBarBackButtonWidth = 52
	TopBarRippleSize      = 40
	TopBarIconSize        = 32
	TopBarTitleLeft       = 24
	TopBarTitleTop        = 17
	TopBarTitleMaxHeight  = 20
	FontTopBarTitle       = 14

	DialogsMenuButtonSize  = 40
	DialogsCalendarWidth   = 32
	DialogsCalendarHeight  = 35
	DialogsSearchFromWidth = 29

	CheckDiameter   = 22
	CheckThickness  = 2
	CheckDurationMs = 120
	CheckRipplePad  = 8

	CheckIconWidth  = 14
	CheckIconHeight = 10
	CheckIconPosX   = 4
	CheckIconPosY   = 7

	CheckboxMargin          = 8
	CheckboxTextPosX        = 10
	CheckboxTextPosY        = 2
	CheckboxCheckPosX       = 8
	CheckboxCheckPosY       = 8
	CheckboxDisabledOpacity = 0.5

	RippleShowDurationMs = 650
	RippleHideDurationMs = 200

	ScrollBarWidth                = 10
	ScrollBarRadius               = 2
	ScrollBarMinHeight            = 20
	ScrollBarDeltax               = 3
	ScrollBarDeltat               = 3
	ScrollBarDeltab               = 3
	ScrollBarThumbMin             = 40
	ScrollDurationMs              = 150
	ScrollHidingMs                = 1000
	ScrollDateHideMs              = 800
	ScrollDateHideOnDayCrossingMs = 3000
	HistoryDateFadeMs             = 200

	HistoryScrollBarWidth  = 12
	HistoryScrollBarRadius = 3
	HistoryScrollBarDeltax = 3
	HistoryScrollBarDeltat = 3
	HistoryScrollBarDeltab = 3

	HistoryToDownPositionX    = 12
	HistoryToDownPositionY    = 10
	HistoryToDownWidth        = 52
	HistoryToDownHeight       = 62
	HistoryToDownCircleSize   = 42
	HistoryToDownCircleX      = 5
	HistoryToDownCircleY      = 15
	HistoryToDownArrowWidth   = 19
	HistoryToDownArrowHeight  = 10
	HistoryToDownArrowStroke  = 3
	HistoryToDownArrowCenterX = 26
	HistoryToDownArrowCenterY = 38
	HistoryToDownShownAfter   = 480
	HistoryToDownDurationMs   = 150

	HistoryUnreadThingsSkip = 4
	HistoryReplyHeight      = 49

	HistoryAttachRippleX    = 2
	HistoryAttachRippleY    = 3
	HistoryAttachRippleSize = 40

	HistorySendIconPositionX     = 10
	HistorySendIconPositionY     = 11
	HistoryScheduleIconPositionX = 7
	HistoryScheduleIconPositionY = 8
	HistoryStopSizeW             = 14
	HistoryStopSizeH             = 14
	HistoryStopRadius            = 3
	HistoryRecordSizeW           = 26
	HistoryRecordSizeH           = 26
	HistorySlowmodeCounterRight  = 10
	SendStateChangeDurationMs    = 120

	DialogsToUpShownAfter   = HistoryToDownShownAfter / 2
	DialogsToUpTravel       = HistoryToDownHeight + 2
	DialogsToUpArrowCenterY = HistoryToDownArrowCenterY + 1

	PreloadScreens = 3

	HistoryPreloadIfLessThanScreens = 2

	WheelPixelToAngleDelta = 2
	WheelScrollLines       = 3
	WheelNotchAngleDelta   = 120
	TouchDragStartDistance = 10

	ScrollKeyStep     = WheelNotchAngleDelta / WheelScrollLines / WheelPixelToAngleDelta
	ScrollKeyPageStep = 10 * ScrollKeyStep

	MouseDoubleClickIntervalMs = 400
	CursorFlashTimeMs          = 1000
	SearchRequestDelayMs       = 900

	SearchedBarHeight  = 28
	SearchedBarPadX    = 14
	SearchedBarTextTop = 5
	FontSearchedBar    = FontBase

	SearchEmptyHeightMin = 220
	SearchEmptyIconSize  = 100
	SearchEmptyIconSkip  = 10
	SearchEmptyPadX      = 10
	SearchEmptyTextTop   = (SearchEmptyHeightMin-SearchEmptyIconSize)/3 + SearchEmptyIconSize + SearchEmptyIconSkip

	TouchFingerAccuracy            = 3
	TouchMaxScrollFlick            = 2500
	TouchMaxScrollAccelerated      = 4000
	TouchOverscrollMultiplier      = 2
	TouchFlingTickMs               = 15
	TouchAccelerationTimeoutMs     = 40
	MinimumOverscrollBeforeStretch = 10
	MaxTrackedVelocity             = 6000
	VelocityZeroingMs              = 100
	RubberBandStiffness            = 20.
	RubberBandAmplitude            = 0.31
	RubberBandPeriod               = 1.6
	RubberBandMaxReturnMs          = 1000

	ToastPadLeft   = 19
	ToastPadTop    = 13
	ToastPadRight  = 19
	ToastPadBottom = 12
	ToastMargin    = 13
	ToastMaxWidth  = 480
	ToastRadius    = 8
	ToastFadeInMs  = 200
	ToastFadeOutMs = 1000
	ToastSlideMs   = 160

	FontDialogsUnread         = 12
	DialogsUnreadHeight       = 19
	DialogsUnreadPadding      = 5
	DialogsUnreadMarkDiameter = 8
	DialogsBadgeRadius        = DialogsUnreadHeight / 2

	FontDialogsDate     = 13
	DialogsDateSkip     = 5
	DialogsChatTypeSkip = 3

	DialogsSendStateSkip = 20
	DialogsTextWidthMin  = 150
	DialogsIconSize      = 18

	DialogsOnlineBadgeSize       = 12
	DialogsOnlineBadgeStroke     = 3
	DialogsOnlineBadgeDurationMs = 150
	DialogsCallBadgeSize         = 16
	DialogsTTLBadgeSize          = 20

	DialogsRowTaggedHeight  = 72
	DialogsRowTaggedTextTop = 30
	DialogsRowTaggedTagTop  = 52

	DialogsRowTaggedForumHeight = 96
	DialogsRowTaggedForumTagTop = 77

	DialogsRowForumHeight        = 80
	DialogsRowForumTextTop       = 32
	DialogsRowForumTopicsSkip    = 8
	DialogsRowForumTopicsSkipBig = 14
	DialogsRowForumTopicsHeight  = 21

	DialogsWidthDurationMs         = 120
	DialogsRightButtonMinPaneWidth = ColumnMinWidthLeft
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

func VerticalCenterOffset(containerHeight, contentHeight int) int {
	return (containerHeight - contentHeight) / 2
}

func MainMenuRowHeight() int {
	return FontBase + MainMenuButtonPadTop + MainMenuButtonPadBottom
}

func DialogsBadgeWidth(textWidth int) int {
	w := textWidth + 2*DialogsUnreadPadding
	if w < DialogsUnreadHeight {
		w = DialogsUnreadHeight
	}
	return w
}

func DialogsNarrowBadgeTop() int {
	return DialogsRowPadTop + DialogsRowPhotoSize - DialogsUnreadHeight
}

func FormatUnreadCounter(unread int, hasMentionOrReaction, narrow bool) string {
	if unread <= 0 {
		return ""
	}
	if !narrow {
		return strconv.Itoa(unread)
	}
	if hasMentionOrReaction && unread > 999 {
		return "99+"
	}
	if unread > 999999 {
		return "99999+"
	}
	return strconv.Itoa(unread)
}

func DialogsOnlineBadgePos(photoSize, badgeSize, stroke int) (int, int) {
	edge := float64(photoSize) * (1 - (1-math.Cos(math.Pi/4))/2)
	half := float64(badgeSize) / 2
	maxPos := float64(photoSize - badgeSize)
	if stroke > 0 {
		maxPos = float64(photoSize) - half - (half+float64(stroke)/2)/math.Sqrt2
	}
	pos := int(math.Round(math.Min(edge-half, maxPos)))
	return pos, pos
}
