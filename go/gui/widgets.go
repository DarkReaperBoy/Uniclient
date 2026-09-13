package gui

import (
	"gioui.org/layout"
	"gioui.org/widget"
)

// widgets is the per-window interactive widget state for the chat surface
// (slice 168: multi-window chats — every window owns its widgets; nothing
// interactive is shared between windows).
//
// Grouped by the surface that owns them; the group comments name the file
// the state previously lived in.
type widgets struct {

	// addmember.go
	addMemAddBtn   widget.Clickable
	addMemCloseBtn widget.Clickable
	addMemList     widget.List
	addMemRowBtns  []widget.Clickable
	addMemSearchEd widget.Editor

	// attach.go
	attachBtn      widget.Clickable
	attachMenuBtns []widget.Clickable

	// botcmds.go
	botCmdBtn   widget.Clickable
	botCmdBtns  []widget.Clickable
	botCmdClose widget.Clickable
	botCmdList  widget.List

	// callbar.go
	callJoinBtn widget.Clickable

	// callui.go
	callAcceptBtn  widget.Clickable
	callCamBtn     widget.Clickable
	callCloseBtn   widget.Clickable
	callDeclineBtn widget.Clickable
	callEndBtn     widget.Clickable
	callMuteBtn    widget.Clickable

	// chat.go
	chatBackBtn widget.Clickable
	chatSendBtn widget.Clickable
	composer    widget.Editor
	joinBarBtn  widget.Clickable
	linkPrevBtn widget.Clickable
	msgList     widget.List
	silentBtn   widget.Clickable

	// chatmenu.go
	chatMenuBtns []widget.Clickable

	// adminlog.go
	adminPanelBack  widget.Clickable
	adminSearchBtn  widget.Clickable
	adminMoreBtn    widget.Clickable
	adminSearchEd   widget.Editor
	adminPanelList  widget.List
	adminFilterList widget.List
	adminFilterBtns []widget.Clickable

	// instantview.go
	ivBackBtn    widget.Clickable
	ivOpenBtn    widget.Clickable
	ivSlidePrev  widget.Clickable
	ivSlideNext  widget.Clickable
	ivList       widget.List
	ivClickables map[string]*widget.Clickable

	// chatsearch.go
	inSearchCloseBtn widget.Clickable
	inSearchEd       widget.Editor
	inSearchFromBtn  widget.Clickable
	inSearchFromList widget.List
	inSearchFromRows []widget.Clickable
	inSearchList     widget.List
	inSearchNextBtn  widget.Clickable
	inSearchPrevBtn  widget.Clickable
	inSearchRows     []widget.Clickable

	// chatsettings.go
	reactWithBtns []widget.Clickable

	// chattheme.go
	chatThemeChipBtns     []widget.Clickable
	chatThemeDlgCancelBtn widget.Clickable
	chatThemeResetBtn     widget.Clickable

	// chrome.go
	pinnedBarBtn   widget.Clickable
	pinnedCycleBtn widget.Clickable

	// cloudthemes.go
	cloudThemeDlgCancelBtn  widget.Clickable
	cloudThemeDlgInstallBtn widget.Clickable
	cloudThemeRowBtns       []widget.Clickable

	// delbrowse.go
	deletedDlgClear widget.Clickable
	deletedDlgClose widget.Clickable
	deletedDlgMore  widget.Clickable

	// deldlg.go
	delDlgCancel widget.Clickable
	delDlgChk    widget.Bool
	delDlgDelete widget.Clickable

	// drafts.go
	composerSchedBtn   widget.Clickable
	schedDateEd        widget.Editor
	schedDlgCancel     widget.Clickable
	schedDlgSend       widget.Clickable
	schedDlgSilent     widget.Bool
	schedDlgWhenOnline widget.Clickable
	schedTimeEd        widget.Editor

	// edithistory.go
	editHistClose widget.Clickable
	editHistMore  widget.Clickable

	// emoji.go
	emojiBackspace widget.Clickable
	emojiBtn       widget.Clickable
	emojiCellBtns  []widget.Clickable
	emojiList      widget.List
	emojiSearchEd  widget.Editor
	emojiTabBtns   []widget.Clickable
	emojiTabsList  widget.List

	// emojicomplete.go
	emojiAcBtns []widget.Clickable
	emojiAcList widget.List

	// headermenu.go
	headerCxlBtn       widget.Clickable
	headerMenuBtns     []widget.Clickable
	headerMoreBtn      widget.Clickable
	headerOkBtn        widget.Clickable
	headerSearchBtn    widget.Clickable
	headerVideoCallBtn widget.Clickable
	headerVoiceCallBtn widget.Clickable

	// inlinebots.go
	inlineGridBtns []widget.Clickable
	inlineList     widget.List
	inlineMoreBtn  widget.Clickable
	inlinePMBtn    widget.Clickable
	inlineRowBtns  []widget.Clickable

	// location.go
	attachDlgCloseBtn widget.Clickable
	attachDlgContacts widget.List
	attachDlgLiveBtn  widget.Clickable
	attachDlgRowBtns  []widget.Clickable
	attachDlgSendBtn  widget.Clickable
	attachLatEditor   widget.Editor
	attachLonEditor   widget.Editor
	liveDurationBtns  []widget.Clickable

	// lock.go
	lockPadBtns []widget.Clickable

	// mediaview.go
	filmClicks      []widget.Clickable
	filmList        widget.List
	viewerCloseBtn  widget.Clickable
	viewerDelBtn    widget.Clickable
	viewerDelNoBtn  widget.Clickable
	viewerDelYesBtn widget.Clickable
	viewerFolderBtn widget.Clickable
	viewerNextBtn   widget.Clickable
	viewerPlayBtn   widget.Clickable
	viewerPrevBtn   widget.Clickable
	viewerSaveBtn   widget.Clickable
	viewerShareBtn  widget.Clickable

	// membermenu.go
	memberMenuBtns []widget.Clickable

	// menu.go
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

	// msgdetail.go
	detailCloseBtn widget.Clickable
	detailCopyBtn  widget.Clickable
	detailList     widget.List
	detailRowBtns  []widget.Clickable

	// mutedlg.go
	muteClockBtn     widget.Clickable
	muteDlgCancelBtn widget.Clickable
	muteDlgCustomBtn widget.Clickable
	muteDlgCustomEd  widget.Editor
	muteDlgCustomGo  widget.Clickable
	muteDlgRowBtns   []widget.Clickable
	muteDlgUnmuteBtn widget.Clickable
	// Notify exceptions (slice 174): sound + previews switches.
	muteDlgSound    widget.Bool
	muteDlgPreviews widget.Bool

	// nextunread.go
	nextUnreadBtn widget.Clickable

	// poll.go
	pollAddOptBtn   widget.Clickable
	pollAnonSw      widget.Bool
	pollCorrectBtns []widget.Clickable
	pollDelOptBtns  []widget.Clickable
	pollDlgCancel   widget.Clickable
	pollDlgCreate   widget.Clickable
	pollMultiSw     widget.Bool
	pollQEd         widget.Editor
	pollQuizSw      widget.Bool

	// profile.go
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

	// reactors.go
	reactorsClose   widget.Clickable
	reactorsMoreBtn widget.Clickable
	reactorsTabs    []widget.Clickable

	// report.go
	reportCancelBtn widget.Clickable
	reportCommentEd widget.Editor
	reportOptBtns   []widget.Clickable
	reportSendBtn   widget.Clickable

	// schedpanel.go
	schedPanelBack  widget.Clickable
	schedPanelList  widget.List
	schedRowDelete  []widget.Clickable
	schedRowResched []widget.Clickable
	schedRowSend    []widget.Clickable

	// seenby.go
	seenDlgClose widget.Clickable

	// select.go
	fwdComment    widget.Editor
	selBarCopyBtn widget.Clickable
	selBarDelBtn  widget.Clickable
	selBarFwdBtn  widget.Clickable
	selBarRptBtn  widget.Clickable
	selBarXBtn    widget.Clickable

	// sharedtabs.go
	sharedRowClicks []widget.Clickable

	// similar.go
	similarCardBtns    []widget.Clickable
	similarExpandBtn   widget.Clickable // slice 169: collapsed-bar expander
	similarCollapseBtn widget.Clickable // slice 169: expanded-block collapser

	// sponsored.go
	sponsoredAboutBtn   widget.Clickable
	sponsoredAdClicks   []widget.Clickable
	sponsoredBarClick   widget.Clickable
	sponsoredDlgCancel  widget.Clickable
	sponsoredDlgPromote widget.Clickable
	sponsoredOptBtns    []widget.Clickable
	sponsoredReportBtn  widget.Clickable

	// stickers.go
	gifCellBtns      []widget.Clickable
	gifGridList      widget.List
	stickerCellBtns  []widget.Clickable
	stickerGridList  widget.List
	stickerModeBtns  []widget.Clickable
	stickerPackBtns  []widget.Clickable
	stickerPacksList widget.List

	// stickerset.go
	stickerSetCellBtns   []widget.Clickable
	stickerSetCloseBtn   widget.Clickable
	stickerSetGrid       widget.List
	stickerSetInstallBtn widget.Clickable

	// stories.go
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

	// topictabs.go
	topicTabBtns []widget.Clickable
	topicTabList widget.List

	// topics.go
	forumActBtns   []widget.Clickable
	forumBackBtn   widget.Clickable
	forumCancelBtn widget.Clickable
	forumCreateBtn widget.Clickable
	forumIconChips []widget.Clickable
	forumMenuBtn   widget.Clickable
	forumNewBtn    widget.Clickable
	forumTitleEd   widget.Editor
	forumTopicBtns []widget.Clickable

	// translatebar.go
	transBarLangBtn widget.Clickable
	transBarOffBtn  widget.Clickable
	transLangBtns   []widget.Clickable

	// keyed clickable maps (per message id — per-window copies)
	albumCellClicks            map[string]*widget.Clickable
	callBtnPool                map[string]*widget.Clickable
	commonGroupBtns            map[string]*widget.Clickable
	gcRowJoinMap               map[string]*widget.Clickable
	liveStopBtns               map[string]*widget.Clickable
	mediaClicks                map[string]*widget.Clickable
	mediaPlayClickables        map[string]*widget.Clickable
	memberRowBtns              map[string]*widget.Clickable
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

// init applies the one-time widget setup (migrated from the old
// package init()s) and materializes the keyed clickable maps.
func (w *widgets) init() {
	w.albumCellClicks = make(map[string]*widget.Clickable)
	w.callBtnPool = make(map[string]*widget.Clickable)
	w.commonGroupBtns = make(map[string]*widget.Clickable)
	w.gcRowJoinMap = make(map[string]*widget.Clickable)
	w.liveStopBtns = make(map[string]*widget.Clickable)
	w.mediaClicks = make(map[string]*widget.Clickable)
	w.mediaPlayClickables = make(map[string]*widget.Clickable)
	w.memberRowBtns = make(map[string]*widget.Clickable)
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
	w.msgList.ScrollToEnd = true // stick to bottom, AyuGram-style
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
