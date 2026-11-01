package gui

import (
	"gioui.org/layout"
	"gioui.org/widget"
)

type widgets struct {
	addMemAddBtn   widget.Clickable
	addMemCloseBtn widget.Clickable
	addMemList     widget.List
	addMemRowBtns  []widget.Clickable
	addMemSearchEd widget.Editor

	attachBtn      widget.Clickable
	attachMenuBtns []widget.Clickable

	botCmdBtn   widget.Clickable
	botCmdBtns  []widget.Clickable
	botCmdClose widget.Clickable
	botCmdList  widget.List

	callJoinBtn widget.Clickable

	callAcceptBtn  widget.Clickable
	callCamBtn     widget.Clickable
	callCloseBtn   widget.Clickable
	callDeclineBtn widget.Clickable
	callEndBtn     widget.Clickable
	callMuteBtn    widget.Clickable

	chatBackBtn widget.Clickable
	chatSendBtn widget.Clickable
	composer    widget.Editor
	joinBarBtn  widget.Clickable
	linkPrevBtn widget.Clickable
	msgList     widget.List
	silentBtn   widget.Clickable

	chatMenuBtns []widget.Clickable

	paidUnlockBtns map[string]*widget.Clickable
	paidConfirmBtn widget.Clickable
	paidCancelBtn  widget.Clickable

	rateStars     []widget.Clickable
	rateSendBtn   widget.Clickable
	rateSkipBtn   widget.Clickable
	rateCommentEd widget.Editor

	sendAsBtn      widget.Clickable
	sendAsCloseBtn widget.Clickable
	sendAsRowBtns  []widget.Clickable
	sendAsList     widget.List

	statsPanelBack   widget.Clickable
	statsTabOverview widget.Clickable
	statsTabEarn     widget.Clickable
	statsWithdrawBtn widget.Clickable
	statsWithdrawEd  widget.Editor

	boostPanelBack   widget.Clickable
	boostTabBoosters widget.Clickable
	boostTabGifts    widget.Clickable
	boostMoreBtn     widget.Clickable
	boostApplyBtn    widget.Clickable
	boostGiveawayBtn widget.Clickable
	boostLaunchCells []widget.Clickable
	statsPanelList   widget.List

	adminPanelBack  widget.Clickable
	adminSearchBtn  widget.Clickable
	adminMoreBtn    widget.Clickable
	adminSearchEd   widget.Editor
	adminPanelList  widget.List
	adminFilterList widget.List
	adminFilterBtns []widget.Clickable

	ivBackBtn    widget.Clickable
	ivOpenBtn    widget.Clickable
	ivSlidePrev  widget.Clickable
	ivSlideNext  widget.Clickable
	ivList       widget.List
	ivClickables map[string]*widget.Clickable

	inSearchCloseBtn widget.Clickable
	inSearchEd       widget.Editor
	inSearchFromBtn  widget.Clickable
	inSearchFromList widget.List
	inSearchFromRows []widget.Clickable
	inSearchList     widget.List
	inSearchNextBtn  widget.Clickable
	inSearchPrevBtn  widget.Clickable
	inSearchRows     []widget.Clickable

	reactWithBtns []widget.Clickable

	chatThemeChipBtns     []widget.Clickable
	chatThemeDlgCancelBtn widget.Clickable
	chatThemeResetBtn     widget.Clickable

	wallpaperPickBtn   widget.Clickable
	wallpaperCancelBtn widget.Clickable
	wallpaperSetBtn    widget.Clickable
	wallpaperBlurChk   widget.Bool
	wallpaperBothChk   widget.Bool

	pinnedBarBtn   widget.Clickable
	pinnedCycleBtn widget.Clickable

	cloudThemeDlgCancelBtn  widget.Clickable
	cloudThemeDlgInstallBtn widget.Clickable
	cloudThemeRowBtns       []widget.Clickable

	deletedDlgClear widget.Clickable
	deletedDlgClose widget.Clickable
	deletedDlgMore  widget.Clickable

	delDlgCancel widget.Clickable
	delDlgChk    widget.Bool
	delDlgDelete widget.Clickable

	clearDlgCancel widget.Clickable
	clearDlgChk    widget.Bool
	clearDlgClear  widget.Clickable

	restrictDlgCancel  widget.Clickable
	restrictDlgApply   widget.Clickable
	restrictDlgDurBtns []widget.Clickable
	restrictDlgSw      []widget.Bool

	composerSchedBtn   widget.Clickable
	schedDateEd        widget.Editor
	schedDlgCancel     widget.Clickable
	schedDlgSend       widget.Clickable
	schedDlgSilent     widget.Bool
	schedDlgWhenOnline widget.Clickable
	schedTimeEd        widget.Editor

	editHistClose widget.Clickable
	editHistMore  widget.Clickable

	emojiBackspace widget.Clickable
	emojiBtn       widget.Clickable
	emojiCellBtns  []widget.Clickable
	emojiList      widget.List
	emojiSearchEd  widget.Editor
	emojiTabBtns   []widget.Clickable
	emojiTabsList  widget.List

	emojiAcBtns []widget.Clickable
	emojiAcList widget.List

	headerCxlBtn       widget.Clickable
	headerMenuBtns     []widget.Clickable
	headerMoreBtn      widget.Clickable
	headerOkBtn        widget.Clickable
	headerSearchBtn    widget.Clickable
	headerVideoCallBtn widget.Clickable
	headerVoiceCallBtn widget.Clickable

	inlineGridBtns []widget.Clickable
	inlineList     widget.List
	inlineMoreBtn  widget.Clickable
	inlinePMBtn    widget.Clickable
	inlineRowBtns  []widget.Clickable

	attachDlgCloseBtn widget.Clickable
	attachDlgContacts widget.List
	attachDlgLiveBtn  widget.Clickable
	attachDlgRowBtns  []widget.Clickable
	attachDlgSendBtn  widget.Clickable
	attachLatEditor   widget.Editor
	attachLonEditor   widget.Editor
	liveDurationBtns  []widget.Clickable

	lockPadBtns []widget.Clickable

	filmClicks       []widget.Clickable
	filmList         widget.List
	viewerCloseBtn   widget.Clickable
	viewerDelBtn     widget.Clickable
	viewerDelNoBtn   widget.Clickable
	viewerDelYesBtn  widget.Clickable
	viewerFolderBtn  widget.Clickable
	viewerNextBtn    widget.Clickable
	viewerPlayBtn    widget.Clickable
	viewerVidPlayBtn widget.Clickable
	viewerPipBtn     widget.Clickable
	pipPlayBtn       widget.Clickable
	pipCloseBtn      widget.Clickable
	pipTag           *struct{}
	viewerPrevBtn    widget.Clickable
	viewerSaveBtn    widget.Clickable
	viewerShareBtn   widget.Clickable

	memberMenuBtns []widget.Clickable

	chipCancelBtn   widget.Clickable
	fwdCancelBtn    widget.Clickable
	fwdChatBtns     []widget.Clickable
	fwdHideAuthor   widget.Bool
	fwdHideCaptions widget.Bool
	fwdList         widget.List
	fwdSendBtn      widget.Clickable
	menuBtns        []widget.Clickable
	menuPickBtns    []widget.Clickable
	menuReactBtns   []widget.Clickable
	reactList       widget.List

	detailCloseBtn widget.Clickable
	detailList     widget.List
	detailRowBtns  []widget.Clickable

	muteClockBtn     widget.Clickable
	muteDlgCancelBtn widget.Clickable
	muteDlgCustomBtn widget.Clickable
	muteDlgCustomEd  widget.Editor
	muteDlgCustomGo  widget.Clickable
	muteDlgRowBtns   []widget.Clickable
	muteDlgUnmuteBtn widget.Clickable
	muteDlgSound     widget.Bool
	muteDlgPreviews  widget.Bool

	nextUnreadBtn widget.Clickable

	pollAddOptBtn   widget.Clickable
	pollAnonSw      widget.Bool
	pollCorrectBtns []widget.Clickable
	pollDelOptBtns  []widget.Clickable
	pollDlgCancel   widget.Clickable
	pollDlgCreate   widget.Clickable
	pollMultiSw     widget.Bool
	pollQEd         widget.Editor
	pollQuizSw      widget.Bool

	botPanelCmdBtns []widget.Clickable
	botPrivacyBtn   widget.Clickable
	memberSearchEd  widget.Editor
	panelAddBtn     widget.Clickable
	panelBlockBtn   widget.Clickable
	panelCloseBtn   widget.Clickable
	panelInfoBtn    widget.Clickable
	panelScroll     widget.List
	panelShareBtn   widget.Clickable
	photoGridClicks []widget.Clickable

	reactorsClose   widget.Clickable
	reactorsMoreBtn widget.Clickable
	reactorsTabs    []widget.Clickable

	reportCancelBtn widget.Clickable
	reportCommentEd widget.Editor
	reportOptBtns   []widget.Clickable
	reportSendBtn   widget.Clickable

	schedPanelBack  widget.Clickable
	schedPanelList  widget.List
	schedRowDelete  []widget.Clickable
	schedRowResched []widget.Clickable
	schedRowSend    []widget.Clickable

	seenDlgClose widget.Clickable

	fwdComment    widget.Editor
	selBarCopyBtn widget.Clickable
	selBarDelBtn  widget.Clickable
	selBarFwdBtn  widget.Clickable
	selBarRptBtn  widget.Clickable
	selBarXBtn    widget.Clickable

	sharedRowClicks []widget.Clickable

	similarCardBtns    []widget.Clickable
	similarExpandBtn   widget.Clickable
	similarCollapseBtn widget.Clickable

	sponsoredAboutBtn   widget.Clickable
	sponsoredAdClicks   []widget.Clickable
	sponsoredBarClick   widget.Clickable
	sponsoredDlgCancel  widget.Clickable
	sponsoredDlgPromote widget.Clickable
	sponsoredOptBtns    []widget.Clickable
	sponsoredReportBtn  widget.Clickable

	gifCellBtns      []widget.Clickable
	gifGridList      widget.List
	stickerCellBtns  []widget.Clickable
	stickerGridList  widget.List
	stickerModeBtns  []widget.Clickable
	stickerPackBtns  []widget.Clickable
	stickerPacksList widget.List

	stickerSetCellBtns   []widget.Clickable
	stickerSetCloseBtn   widget.Clickable
	stickerSetGrid       widget.List
	stickerSetInstallBtn widget.Clickable

	storyCloseBtn      widget.Clickable
	storyNextBtn       widget.Clickable
	storyPlayBtn       widget.Clickable
	storyPrevBtn       widget.Clickable
	storyReactBtn      widget.Clickable
	storyReactEmojiBtn []widget.Clickable
	storyReplyBtn      widget.Clickable
	storyReplyEd       widget.Editor
	storyReplySendBtn  widget.Clickable
	storyReplyXBtn     widget.Clickable
	storyShareBtn      widget.Clickable
	storyStripList     widget.List

	topicTabBtns []widget.Clickable
	topicTabList widget.List

	forumActBtns []widget.Clickable
	forumBackBtn widget.Clickable

	threadBackBtn   widget.Clickable
	commentChipBtns map[string]*widget.Clickable

	savedListBtn     widget.Clickable
	savedBackBtn     widget.Clickable
	savedListRowBtns []widget.Clickable
	savedTagRowBtns  []widget.Clickable

	savedSublistMenuRows []widget.Clickable
	savedDelOK           widget.Clickable
	savedDelCancel       widget.Clickable
	forumCancelBtn       widget.Clickable
	forumCreateBtn       widget.Clickable
	forumIconChips       []widget.Clickable
	forumMenuBtn         widget.Clickable
	forumNewBtn          widget.Clickable
	forumTitleEd         widget.Editor
	forumTopicBtns       []widget.Clickable

	transBarLangBtn widget.Clickable
	transBarOffBtn  widget.Clickable
	transLangBtns   []widget.Clickable

	albumCellClicks            map[string]*widget.Clickable
	callBtnPool                map[string]*widget.Clickable
	commonGroupBtns            map[string]*widget.Clickable
	gcRowJoinMap               map[string]*widget.Clickable
	liveStopBtns               map[string]*widget.Clickable
	mediaClicks                map[string]*widget.Clickable
	mediaPlayClickables        map[string]*widget.Clickable
	memberRowBtns              map[string]*widget.Clickable
	panelSwitches              map[string]*widget.Bool
	panelSynced                map[string]bool
	seekBarTags                map[string]*struct{}
	seekBarApplied             map[string]float64
	msgReactBtns               map[string]*widget.Clickable
	msgReplyBtns               map[string]*widget.Clickable
	panelRowClickables         map[string]*widget.Clickable
	pollClicks                 map[string]*widget.Clickable
	reactionClicks             map[string]*widget.Clickable
	replyQuoteClicks           map[string]*widget.Clickable
	sharedTabClicks            map[string]*widget.Clickable
	spoilerBtns                map[string]*widget.Clickable
	storyStripBtns             map[string]*widget.Clickable
	transcribeClickables       map[string]*widget.Clickable
	transcriptExpandClickables map[string]*widget.Clickable
	voiceRecClickables         map[string]*widget.Clickable
	webPageClickables          map[string]*widget.Clickable
}

func (w *widgets) init() {
	w.albumCellClicks = make(map[string]*widget.Clickable)
	w.callBtnPool = make(map[string]*widget.Clickable)
	w.commonGroupBtns = make(map[string]*widget.Clickable)
	w.gcRowJoinMap = make(map[string]*widget.Clickable)
	w.liveStopBtns = make(map[string]*widget.Clickable)
	w.mediaClicks = make(map[string]*widget.Clickable)
	w.mediaPlayClickables = make(map[string]*widget.Clickable)
	w.paidUnlockBtns = make(map[string]*widget.Clickable)
	w.memberRowBtns = make(map[string]*widget.Clickable)
	w.panelSwitches = make(map[string]*widget.Bool)
	w.panelSynced = make(map[string]bool)
	w.commentChipBtns = make(map[string]*widget.Clickable)
	w.seekBarTags = make(map[string]*struct{})
	w.seekBarApplied = make(map[string]float64)
	w.msgReactBtns = make(map[string]*widget.Clickable)
	w.msgReplyBtns = make(map[string]*widget.Clickable)
	w.panelRowClickables = make(map[string]*widget.Clickable)
	w.pollClicks = make(map[string]*widget.Clickable)
	w.reactionClicks = make(map[string]*widget.Clickable)
	w.replyQuoteClicks = make(map[string]*widget.Clickable)
	w.sharedTabClicks = make(map[string]*widget.Clickable)
	w.spoilerBtns = make(map[string]*widget.Clickable)
	w.storyStripBtns = make(map[string]*widget.Clickable)
	w.transcribeClickables = make(map[string]*widget.Clickable)
	w.transcriptExpandClickables = make(map[string]*widget.Clickable)
	w.voiceRecClickables = make(map[string]*widget.Clickable)
	w.webPageClickables = make(map[string]*widget.Clickable)
	w.ivClickables = make(map[string]*widget.Clickable)
	w.addMemSearchEd.SingleLine = true
	w.addMemList.Axis = layout.Vertical
	w.botCmdList.Axis = layout.Vertical
	w.composer.SingleLine = false
	w.msgList.Axis = layout.Vertical
	w.msgList.ScrollToEnd = true
	w.ivList.Axis = layout.Vertical
	w.inSearchList.Axis = layout.Vertical
	w.emojiAcList.Axis = layout.Horizontal
	w.inlineList.Axis = layout.Vertical
	w.attachLatEditor.SingleLine = true
	w.attachLonEditor.SingleLine = true
	w.detailList.Axis = layout.Vertical
	w.muteDlgCustomEd.SingleLine = true
	w.panelScroll.Axis = layout.Vertical
	w.schedPanelList.Axis = layout.Vertical
	w.stickerSetGrid.Axis = layout.Vertical
	w.storyStripList.Axis = layout.Horizontal
	w.topicTabList.Axis = layout.Horizontal
}
