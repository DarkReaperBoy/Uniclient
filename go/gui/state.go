package gui

import (
	"encoding/json"
	"image"
	"image/color"
	"log"
	"sync"
	"time"

	"gioui.org/app"
	"gioui.org/f32"
	"gioui.org/io/event"
	"gioui.org/op"
	"gioui.org/widget"

	"gioui.org/x/explorer"

	"strconv"
	"uniclient/audio"
	"uniclient/cores"
	"uniclient/engine"
	"uniclient/utils"
)

type App struct {
	win *app.Window
	ui  *UI
	eng *engine.Engine

	loopLogMu   sync.Mutex
	loopLogLast time.Time

	inlineKbdBtns     [][]widget.Clickable
	replyKbdBtns      [][]widget.Clickable
	musicMenuBtn      widget.Clickable
	schedDlgPresets   [3]widget.Clickable
	shadowDlgClose    widget.Clickable
	shadowDlgUnban    []widget.Clickable
	replyKbdSingleUse bool
	replyKbdUsedFor   string
	msgFrameLastOwn   string
	fwdSel            map[string]bool

	wid widgets

	separate *chatKey

	pendingDeselect *chatKey
	pendingLock     *bool

	sepSub    *engine.EventSubscription
	lockUnsub func()

	mu sync.Mutex

	accounts []engine.AccountInfo
	chats    []engine.ChatInfo
	messages []engine.CachedMessage
	msgFor   *chatKey

	selected *chatKey
	folder   int
	search   string

	searchMsgs   []engine.SearchResult
	searchPosts  []engine.SearchResult
	searchGlobal []engine.ChatInfo
	searchFor    string

	mode       int
	auth       *engine.AuthState
	authAcct   string
	showPicker bool
	acctFilter string

	archiveView bool

	mediaTickerOn bool

	voiceRec         voiceRecState
	voiceRecTickerOn bool

	transcriptOpen map[string]bool
	transcribeCap  map[string]bool

	savedCap    map[string]bool
	savedChatID map[string]string

	forumTopic  string
	forumTopics []cores.ForumTopic
	forumLoaded bool
	forumFor    string
	forumIcons  []cores.ForumTopicIconInfo
	forumDlg    *forumDlgState

	groupCall    *engine.GroupCallInfo
	callPollFor  *chatKey
	viewsPollFor *chatKey

	call *callUI

	hdrCaps    []string
	hdrCapsFor string

	joinedGC     *joinedCall
	joinedGCInfo *engine.GroupCallInfo

	devPickers map[string]*devPickerState

	storyView    *storyViewerState
	storyViewGen int

	slowTickPending bool

	botCmds       []engine.BotCommandInfo
	botCmdsFor    *chatKey
	botCmdsLoaded bool
	botCmdsOn     bool

	sponsored       []cores.SponsoredMessageInfo
	sponsoredFor    string
	sponsoredViewed map[string]bool
	sponsoredDlg    *sponsoredDlgState

	similar         []engine.SimilarChannelInfo
	similarFor      string
	similarExpanded map[string]bool

	inlineRes       *cores.InlineBotResults
	inlineForKey    string
	inlineForOffset string
	inlineBusy      bool
	inlineLastAsk   time.Time
	inlineBotIDs    map[string]string

	topPeers       []engine.ChatInfo
	topPeersFor    string
	topPeersLoaded bool
	toast          string
	toastAt        time.Time
	connecting     map[string]bool
	sending        bool
	loadingMsgs    bool
	loadedOlder    int

	cMode        composerMode
	menu         *menuTarget
	fwd          []engine.CachedMessage
	menuCaps     []string
	menuCapsFor  string
	availEmojis  []string
	availFor     string
	loadingOlder bool
	olderDone    bool

	selOn bool
	sel   map[string]bool

	downloads  map[string]dlState
	autoDl     map[string]bool
	openOnDone map[string]bool
	saveOnDone map[string]bool
	playOnDone map[string]bool

	settingsOpen bool
	settingsSect int
	cfg          cfgSnapshot

	tray              *trayController
	accentNow         color.NRGBA
	lock              *lockState
	lockDlg           *lockDlgState
	twofaDlg          *twofaDlgState
	twofaStates       map[string]cores.CloudPasswordState
	soundPicker       *soundPickerState
	notifyAccts       map[string]notifyAcctState
	notifyLoaded      bool
	blockedUsers      map[string][]cores.User
	sessionsList      map[string][]cores.Session
	privacyLoaded     bool
	privacyScopes     map[string]map[string]string
	privacyDlg        *privacyDlgState
	autoDlRules       map[string]map[string]interface{}
	autoDlOn          bool
	autoDlDlg         *autodlDlgState
	callsList         map[string][]engine.CallHistoryEntry
	callsLoaded       bool
	themeDlg          *chatThemeDlgState
	wallpaperDlg      *wallpaperDlgState
	chatThemes        []cores.ChatThemeInfo
	chatThemesFor     string
	chatThemesOn      bool
	cloudThemes       []cores.CloudThemeInfo
	cloudThemesFor    string
	cloudThemeAcct    string
	profileEdit       *profileEditState
	stickerMgr        *stickerMgrState
	folderMgr         *folderMgrState
	premiumPage       *premiumPageState
	starsPage         *starsPageState
	businessPage      *businessPageState
	langCode          string
	langStrings       map[string]string
	langStringsLoaded bool
	langs             []engine.LanguageInfo
	langsLoaded       bool
	langsFor          string
	langsErr          string
	langApplying      bool
	cloudThemesOn     bool
	cloudDlg          *cloudThemeDlgState
	cacheTotal        int64
	cacheTags         [6]int64
	cacheLoaded       bool
	takeoutAccts      []string
	ghostSel          string
	ghostFlags        map[string]engine.GhostFlags
	ghostLoaded       bool
	panelOpen         bool
	panelChat         chatKey
	panelLoaded       bool
	panelMuted        bool
	profile           *engine.CachedUser
	members           []engine.MemberInfo
	mediaCounts       []engine.SharedMediaCountItem
	panelBotCmds      []engine.BotCommandInfo
	panelMusic        []engine.MusicTrack
	musicDlg          *musicDlgState
	musicRowMenu      *musicRowMenuState
	musicAttachDlg    *musicAttachDlgState
	giftDlg           *giftDlgState
	giftHideOn        bool
	giveawayDlg       *giveawayDlgState
	panelTab          string
	panelTabItems     map[string][]engine.SharedMediaItem
	panelTabLoaded    map[string]bool
	panelTabPending   map[string]bool
	panelLinks        []engine.SharedLinkItem
	panelLinksLoaded  bool

	expl           *explorer.Explorer
	attachMenuOpen bool
	attachLiveOn   bool
	attachLiveSel  int

	emojiOpen bool
	emojiTab  int

	unreadAtOpen   int
	unreadSepMsgID string
	pinned         []engine.CachedMessage
	pinnedIdx      int
	pinnedLoaded   bool

	folders          []engine.FolderInfo
	foldersFor       string
	foldersSupported bool
	folderDlg        *folderDlgState
	folderInvites    *folderInvitesState
	attachDlg        *attachDlgState
	addMemDlg        *addMemDlgState
	searchTab        int
	ttlDlg           *ttlDlgState
	muteDlg          *muteDlgState
	emojiMode        int
	stickerPacks     []cores.StickerPackSummary
	stickerPackIdx   int
	recentStickers   []cores.StickerInfo
	savedGifs        []cores.GifInfo
	panelMediaFor    string
	stickersLoaded   bool
	gifsLoaded       bool

	chatMenu *chatMenuTarget

	folderMenu *folderMenuTarget

	headerMenu *headerMenuTarget

	drawerOpen    bool
	contactsOpen  bool
	contactsFor   string
	contacts      []engine.ContactInfo
	contactsLoad  bool
	addDlgOpen    bool
	addDlgBusy    bool
	newDlg        *newChatDlg
	newDlgErr     string
	pendingOpen   *chatKey
	pendingTitle  string
	pendingJump   *jumpReq
	pendingTopic  *string
	pendingThread *threadOpenReq

	uiGen int

	callsBoxOpen         bool
	callsBoxFor          string
	callsBoxRows         []callBoxRow
	callsBoxBusy         bool
	callsBoxDone         bool
	callsBoxLoad         bool
	callsBoxGen          int
	callsBoxMenu         *callsBoxMenuTarget
	callsRowMenu         *callsRowMenuTarget
	callsClearDlg        bool
	callsDelDlg          int
	callsRowBounds       []image.Rectangle
	savedListRowBounds   []image.Rectangle
	savedSublistMenuRect image.Rectangle
	callsBoxMenuRect     image.Rectangle
	callsRowMenuRect     image.Rectangle

	inSearch          bool
	inSearchQ         string
	inChatHits        []engine.SearchResult
	inChatFor         string
	inChatIdx         int
	inChatBusy        bool
	inSearchFrom      string
	inSearchFromName  string
	inSearchFromPanel bool

	delDlg    *delDlgState
	reportDlg *reportDlgState

	clearDlg *clearDlgState

	restrictDlg *restrictDlgState

	signupPhotoPath string
	signupPhotoTemp []string
	signupPhotoB64  string

	threadScope      *threadScopeState
	savedListOpen    bool
	savedLists       []cores.SavedSublistInfo
	savedListsLoaded bool
	savedListsErr    string
	savedScope       *savedScopeState
	savedTags        []cores.SavedReactionTagInfo
	savedTagsLoaded  bool
	savedSublistMenu *savedSublistMenuTarget
	savedDelDlg      *savedDelDlgState

	schedDlg *schedDlgState

	pollDlg     *pollDlgState
	pollDlgGen  int
	pollVotes   map[string]map[int]bool
	pollStopped map[string]bool

	translations    map[string]string
	transChatOn     map[string]bool
	transTarget     string
	transAsked      map[string]bool
	transPickerOpen bool
	seenInline      map[string]*seenInlineState

	reactors *reactorsState

	ayuFilterDlg       *ayuFilterDlgState
	ayuFilterCount     int
	ayuFilterCountOn   bool
	ayuFilterCountBusy bool

	shadowDlg *shadowDlgState

	editHistDlg   *editHistState
	msgDetailDlg  *msgDetailState
	memberMenu    *memberMenuState
	commonChats   []cores.Dialog
	commonLoaded  bool
	stickerSetDlg *stickerSetDlgState

	deletedDlg *deletedDlgState

	seenDlg *seenDlgState

	exportDlg        *exportDlgState
	exportOptsSynced bool

	folderImportDlg *folderImportState

	emojiKws         []engine.EmojiKeywordEntry
	emojiKwsLoaded   bool
	emojiKwsFetching bool

	customThumbs         map[int64]cores.CustomEmojiThumb
	customThumbsFetching map[string]bool
	emojiArtFetching     map[string]bool
	customThumbWant      []int64
	customThumbWantAcc   string

	silentNext bool

	inviteDlg *inviteDlgState

	schedPanel bool
	schedMsgs  []engine.CachedMessage
	schedLoad  bool

	paidDlg *paidConfirmState

	rateDlg *rateCallState

	sendAs    []engine.SendAsPeerInfo
	sendAsFor *chatKey
	sendAsCur string
	sendAsDlg bool

	statsPanel bool

	boostPanel    bool
	boostStatus   map[string]interface{}
	boosters      []map[string]interface{}
	boostNext     string
	boostTotal    int
	boostGifts    bool
	boostLoad     bool
	boostErr      string
	statsData     *cores.ChannelStats
	statsLoad     bool
	statsErr      string
	statsEarnTab  bool
	statsEarn     *cores.StarsRevenueResult
	statsEarnLoad bool
	statsEarnErr  string
	statsWdBusy   bool

	adminPanel     bool
	adminEvents    []cores.AdminLogEvent
	adminLoad      bool
	adminLoadedAll bool
	adminFor       *chatKey
	adminFilters   map[string]bool
	adminErr       string

	viewer *viewerState

	pip *pipState

	vpW, vpH int

	iv *ivState

	typing map[string]time.Time

	hdrPresence *engine.CachedUser

	loginCode   string
	loginCodeAt time.Time

	pendingCopy string
	notifyAt    map[string]time.Time

	hoverChatKey string
	hoverSince   time.Time
	hoverPos     image.Point
	hoverFrame   bool
	chatPeek     *chatPeekState
	sidebarW     int

	spoilerRevealed map[string]bool

	rowBounds              map[int]image.Rectangle
	menuRect               image.Rectangle
	attachMenuRect         image.Rectangle
	emojiRect              image.Rectangle
	chatRowBounds          map[int]image.Rectangle
	sbVisible              []engine.ChatInfo
	sbAboveList            int
	chatMenuRect           image.Rectangle
	sbTabBounds            []image.Rectangle
	folderMenuRect         image.Rectangle
	headerMenuRect         image.Rectangle
	listTop                int
	headerH                int
	mvZoom                 float32
	mvPan                  f32.Point
	mvLastPressAt          time.Time
	mvLastPressPos         f32.Point
	mvBoxW, mvBoxH         int
	mvScaledW, mvScaledH   float32
	rubberOn               bool
	rubberStart, rubberCur image.Point
}

func New(win *app.Window, eng *engine.Engine) *App {
	a := &App{
		win:             win,
		ui:              NewUI(),
		eng:             eng,
		expl:            explorer.NewExplorer(win),
		typing:          make(map[string]time.Time),
		connecting:      make(map[string]bool),
		rowBounds:       make(map[int]image.Rectangle),
		sbTabBounds:     make([]image.Rectangle, 0, 8),
		downloads:       make(map[string]dlState),
		autoDl:          make(map[string]bool),
		openOnDone:      make(map[string]bool),
		pollVotes:       make(map[string]map[int]bool),
		translations:    make(map[string]string),
		transChatOn:     make(map[string]bool),
		transTarget:     "en",
		transAsked:      make(map[string]bool),
		seenInline:      make(map[string]*seenInlineState),
		similarExpanded: make(map[string]bool),
	}
	a.wid.init()
	return a
}

func (a *App) Start() {
	eng := a.eng
	a.sepSub = eng.Subscribe(func(data []byte) { a.onEvent(data) })
	a.lockUnsub = lockBroadcastShare(a.onLockBroadcast)
	if !a.isSeparate() {
		sepMu.Lock()
		mainRef = a
		sepMu.Unlock()
	}
	if cfg := eng.GetConfig(); cfg != nil {
		a.ui.applyTheme(cfg.Theme)
		a.ui.applyAccent(cfg.AccentColor)
		a.ui.applyFontScale(cfg.FontScale)
		if cfg.FontPath != "" || cfg.MonoFontPath != "" {
			_ = a.ui.applyUserFonts(cfg.FontPath, cfg.MonoFontPath)
		}
		a.psLoad()
		a.ui.applyBubbleCorners(cfg.BubbleCorners == nil || *cfg.BubbleCorners)
		a.ui.applyLayoutTweaks(utils.EffectiveBubbleRadius(*cfg), utils.EffectiveWideMultiplier(*cfg))
		a.ui.applyAvatarCorners(utils.EffectiveAvatarCorners(*cfg))
		a.langCode = cfg.Language
		a.transTarget = normalizeTransTarget(cfg.TranslateTarget)
	}
	if data, err := eng.GetPasscodeConfig(); err != nil {
		a.setToast("Passcode: " + err.Error())
	} else if st := lockFromConfig(data); st != nil {
		if !a.isSeparate() {
			lockEngaged.Store(true)
			st.lastActive = time.Now()
			a.lock = st
		} else if lockEngaged.Load() {
			st.lastActive = time.Now()
			a.lock = st
		}
	}
	if a.isSeparate() {
		go a.refreshAccounts()
		go a.refreshChats()
		return
	}
	go a.refreshAccounts()
	go a.refreshChats()
	go eng.ConnectAllAccounts()
}

func (a *App) Shutdown() {
	if a.lockUnsub != nil {
		a.lockUnsub()
	}
	stopInstanceServer()
	if a.isSeparate() {
		return
	}
	a.stopTray()
	stopTaskbar()
	stopAppIcon()
}

func (a *App) ListenEvents(evt event.Event) {
	if a.expl != nil {
		a.expl.ListenEvents(evt)
	}
	audio.SetAndroidViewEvent(evt)
	if ev, ok := evt.(app.ViewEvent); ok && !a.isSeparate() {
		taskbarSetWindow(ev)
		a.mu.Lock()
		set := effectiveAppIconSet(a.cfg)
		accent := a.accentNow
		a.mu.Unlock()
		appiconSetWindow(ev, set, accent)
	}
}

func (a *App) invalidate() {
	if a.win != nil {
		a.win.Invalidate()
	}
}

func (a *App) setToast(msg string) {
	a.mu.Lock()
	a.toast = msg
	a.toastAt = time.Now()
	a.mu.Unlock()
	a.invalidate()
}

func (a *App) copyTextSoon(txt string) {
	if txt == "" {
		return
	}
	a.mu.Lock()
	a.pendingCopy = txt
	a.mu.Unlock()
	shown := txt
	if len(shown) > 48 {
		shown = shown[:48] + "…"
	}
	a.setToast("Copied: " + shown)
}

func (a *App) refreshAccounts() {
	accs := a.eng.ListAccounts()
	caps := make(map[string]bool, len(accs))
	savedCap := make(map[string]bool, len(accs))
	savedChat := make(map[string]string, len(accs))
	for _, acc := range accs {
		caps[acc.ID] = a.eng.TranscriptionSupported(acc.ID)
		savedCap[acc.ID] = a.eng.SavedMessagesSupported(acc.ID)
		savedChat[acc.ID] = a.eng.SavedMessagesChatID(acc.ID)
	}
	a.mu.Lock()
	a.accounts = accs
	a.transcribeCap = caps
	a.savedCap = savedCap
	a.savedChatID = savedChat
	a.mu.Unlock()
	go func() {
		for _, acc := range accs {
			if a.eng.ProfileMusicSupported(acc.ID) {
				a.eng.RefreshOwnProfileMusic(acc.ID)
			}
		}
	}()
	a.ensureLangStrings()
	a.updateTray()
	a.invalidate()
}

func (a *App) ensureLangStrings() {
	a.mu.Lock()
	code := a.langCode
	loaded := a.langStringsLoaded
	acc := ""
	for _, cand := range a.accounts {
		if cand.Platform == "telegram" || cand.Platform == "Telegram" {
			acc = cand.ID
			break
		}
	}
	if acc == "" && len(a.accounts) > 0 {
		acc = a.accounts[0].ID
	}
	a.mu.Unlock()
	if loaded || code == "" || code == "en" || acc == "" {
		return
	}
	a.mu.Lock()
	a.langStringsLoaded = true
	a.mu.Unlock()
	go func() {
		if m, err := a.eng.GetLangStrings(acc, code, langKeysForSettings()); err == nil {
			a.mu.Lock()
			a.langStrings = m
			a.mu.Unlock()
			a.invalidate()
		}
	}()
}

func (a *App) refreshChats() {
	chats, err := a.eng.GetUnifiedChatList(200, 0)
	if err != nil {
		log.Printf("gui: chat list: %v", err)
	}
	a.mu.Lock()
	a.chats = chats
	a.mu.Unlock()
	a.syncCallPoll()
	a.updateTray()
	a.invalidate()
}

func (a *App) refreshMessages() {
	a.mu.Lock()
	key := a.msgFor
	selected := a.selected
	gen := a.uiGen
	a.mu.Unlock()
	k := key
	if k == nil {
		k = selected
	}
	if k == nil {
		return
	}
	var msgs []engine.CachedMessage
	var err error
	if ts := a.threadScopeFor(k); ts != nil && ts.discussionChat != "" {
		msgs, err = a.eng.GetThreadMessages(k.AccountID, ts.discussionChat, ts.rootID, 0, 100)
	} else if ss := a.savedScopeFor(k); ss != nil && ss.tag != "" {
		msgs, err = a.eng.SearchSavedMessagesByReaction(k.AccountID, k.ChatID, "", []string{ss.tag}, 0, 100)
	} else if ss := a.savedScopeFor(k); ss != nil {
		msgs, err = a.eng.GetSavedSublistMessages(k.AccountID, k.ChatID, ss.peerID, 0, 100)
	} else if topic := a.topicScopeFor(k); topic != "" {
		msgs, err = a.eng.GetTopicMessages(k.AccountID, k.ChatID, topic, 0, 100)
	} else {
		msgs, err = a.eng.GetMessages(k.AccountID, k.ChatID, 0, 0, 100)
	}
	if err != nil {
		log.Printf("gui: messages: %v", err)
	}
	for i, j := 0, len(msgs)-1; i < j; i, j = i+1, j-1 {
		msgs[i], msgs[j] = msgs[j], msgs[i]
	}
	a.mergeMessages(k, msgs, gen)
}

func (a *App) topicScopeFor(k *chatKey) string {
	a.mu.Lock()
	defer a.mu.Unlock()
	if k == nil || a.forumTopic == "" || a.selected == nil {
		return ""
	}
	if a.selected.String() != k.String() {
		return ""
	}
	return a.forumTopic
}

func (a *App) mergeMessages(k *chatKey, fresh []engine.CachedMessage, gen int) {
	a.mu.Lock()
	if a.uiGen != gen || a.selected == nil || *a.selected != *k {
		a.mu.Unlock()
		a.invalidate()
		return
	}
	merged := fresh
	if len(a.messages) > 0 && len(fresh) > 0 && a.messages[0].Timestamp < fresh[0].Timestamp {
		cutoff := fresh[0].Timestamp
		seen := make(map[string]bool, len(fresh))
		for _, m := range fresh {
			seen[m.MsgID] = true
		}
		keep := make([]engine.CachedMessage, 0, len(a.messages))
		for _, m := range a.messages {
			if m.Timestamp < cutoff && !seen[m.MsgID] {
				keep = append(keep, m)
			}
		}
		merged = make([]engine.CachedMessage, 0, len(keep)+len(fresh))
		merged = append(merged, keep...)
		merged = append(merged, fresh...)
	}
	a.messages = merged
	a.msgFor = &chatKey{k.AccountID, k.ChatID}
	a.loadingMsgs = false
	a.mu.Unlock()
	a.invalidate()
}

func (a *App) onEvent(data []byte) {
	var env struct {
		Type      string          `json:"type"`
		AccountID string          `json:"account_id"`
		Timestamp int64           `json:"timestamp_ms"`
		Data      json.RawMessage `json:"data"`
	}
	if err := json.Unmarshal(data, &env); err != nil {
		return
	}

	switch env.Type {
	case engine.EventAccountList, engine.EventConnState, engine.EventAuthState:
		go a.refreshAccounts()
		go a.refreshFolders(a.acctFilterLocked())
	case engine.EventChatSnapshot, engine.EventChatUpdated, engine.EventChatRemoved:
		go a.refreshChats()
	case engine.EventMsgReceived, engine.EventMsgEdited, engine.EventMsgDeleted, engine.EventMsgStatus:
		a.onMessageEvent(env.Type, env.AccountID, env.Data)
		go a.refreshChats()
	case engine.EventMsgTranscribed:
		var t engine.MsgTranscribedEvent
		if json.Unmarshal(env.Data, &t) == nil {
			a.onMessageEvent(env.Type, env.AccountID, env.Data)
		}
	case engine.EventTyping:
		var t engine.TypingEvent
		if json.Unmarshal(env.Data, &t) == nil {
			a.mu.Lock()
			a.typing[chatKey{env.AccountID, t.ChatID}.String()] = time.Now()
			a.mu.Unlock()
			a.invalidate()
			go func() {
				time.Sleep(4 * time.Second)
				a.mu.Lock()
				delete(a.typing, chatKey{env.AccountID, t.ChatID}.String())
				a.mu.Unlock()
				a.invalidate()
			}()
		}
	case engine.EventUserStatus:
		var s engine.UserStatusEvent
		if json.Unmarshal(env.Data, &s) == nil {
			a.onUserStatus(env.AccountID, s)
		}
	case engine.EventLoginCode:
		var m map[string]string
		if json.Unmarshal(env.Data, &m) == nil && m["code"] != "" {
			a.mu.Lock()
			a.loginCode = m["code"]
			a.loginCodeAt = time.Now()
			a.mu.Unlock()
			a.invalidate()
		}
		go a.refreshAuth()
	case engine.EventProfileMusicChanged:
		var pm engine.ProfileMusicEvent
		if json.Unmarshal(env.Data, &pm) == nil {
			a.onProfileMusicChanged(env.AccountID, pm.PeerID)
		}
	case engine.EventDownloadProgress:
		var d engine.DownloadProgressEvent
		if json.Unmarshal(env.Data, &d) == nil {
			a.onDownloadProgress(d)
		}
	case engine.EventDownloadComplete:
		var d engine.DownloadCompleteEvent
		if json.Unmarshal(env.Data, &d) == nil {
			a.onDownloadComplete(d)
		}
	case engine.EventDownloadFailed:
		var d engine.DownloadFailedEvent
		if json.Unmarshal(env.Data, &d) == nil {
			a.onDownloadFailed(d)
		}
	case engine.EventExportProgress:
		var ev engine.ExportProgressEvent
		if json.Unmarshal(env.Data, &ev) == nil {
			a.onExportProgress(ev, env.AccountID)
		}
	case engine.EventExportError:
		var ev engine.ExportErrorEvent
		if json.Unmarshal(env.Data, &ev) == nil {
			a.onExportError(ev, env.AccountID)
		}
	case engine.EventExportComplete:
		var ev engine.ExportCompleteEvent
		if json.Unmarshal(env.Data, &ev) == nil {
			a.onExportComplete(ev, env.AccountID)
			a.setToast("Export complete")
		}
	case engine.EventIncomingCall:
		var c cores.CallSession
		if json.Unmarshal(env.Data, &c) == nil {
			a.onIncomingCallEvent(env.AccountID, &c)
		}
	case engine.EventCallState:
		var c cores.CallSession
		if json.Unmarshal(env.Data, &c) == nil {
			a.onCallStateEvent(env.AccountID, &c)
		}
	case engine.EventGroupCallState:
		go a.refreshChats()
	}
}

func (a *App) onMessageEvent(typ, accountID string, data json.RawMessage) {
	if typ == engine.EventMsgReceived {
		var ev engine.MsgReceivedEvent
		if json.Unmarshal(data, &ev) == nil && ev.AccountID == accountID {
			a.maybeNotify(ev)
		}
	}
	if typ == engine.EventMsgStatus {
		var ev engine.MsgStatusEvent
		if json.Unmarshal(data, &ev) == nil && ev.Status == engine.MsgStatusFailed {
			a.setToast("Send failed — Resend from the message menu")
		}
	}

	a.mu.Lock()
	k := a.msgFor
	open := k != nil
	a.mu.Unlock()
	if !open {
		return
	}
	if typ == engine.EventMsgReceived {
		var m engine.MsgReceivedEvent
		if json.Unmarshal(data, &m) == nil && m.AccountID == k.AccountID && m.ChatID == k.ChatID {
			go a.refreshMessages()
		}
		return
	}
	go a.refreshMessages()
}

func (a *App) onDownloadProgress(d engine.DownloadProgressEvent) {
	a.mu.Lock()
	if a.downloads == nil {
		a.downloads = make(map[string]dlState)
	}
	a.downloads[dlKey(d.AccountID, d.ChatID, d.MsgID, d.Seq)] = dlState{
		recv: d.BytesRecv, total: d.BytesTotal, state: engine.DownloadInProgress,
	}
	a.mu.Unlock()
	a.invalidate()
}

func (a *App) onDownloadComplete(d engine.DownloadCompleteEvent) {
	a.mu.Lock()
	if a.downloads == nil {
		a.downloads = make(map[string]dlState)
	}
	a.downloads[dlKey(d.AccountID, d.ChatID, d.MsgID, d.Seq)] = dlState{recv: 1, total: 1, state: engine.DownloadComplete}
	wantOpen := a.consumeOpenOnDoneLocked(d.AccountID, d.ChatID, d.MsgID, d.Seq)
	wantInline := a.consumePlayOnDoneLocked(d.AccountID, d.ChatID, d.MsgID, d.Seq)
	wantSave := a.consumeSaveOnDoneLocked(d.AccountID, d.ChatID, d.MsgID, d.Seq)
	if k := a.msgFor; k != nil && k.AccountID == d.AccountID && k.ChatID == d.ChatID {
		for i := range a.messages {
			if a.messages[i].MsgID == d.MsgID {
				msgs := make([]engine.CachedMessage, len(a.messages))
				copy(msgs, a.messages)
				msgs[i].MediaDownloadState = engine.DownloadComplete
				msgs[i].MediaLocalPath = d.LocalPath
				a.messages = msgs
				break
			}
		}
	}
	if v := a.viewer; v != nil && v.accountID == d.AccountID && v.chatID == d.ChatID {
		for i := range v.items {
			if v.items[i].MsgID == d.MsgID {
				items := make([]engine.SharedMediaItem, len(v.items))
				copy(items, v.items)
				items[i].LocalPath = d.LocalPath
				v.items = items
				break
			}
		}
	}
	a.mu.Unlock()
	if wantSave {
		a.saveMediaToDownloads(d.AccountID, d.ChatID, d.MsgID, d.Seq)
		return
	}
	if wantInline {
		a.startVideoNoteInline(d.AccountID, d.ChatID, d.MsgID, d.LocalPath)
		return
	}
	if wantOpen {
		a.openMedia(d.LocalPath, true)
		return
	}
	st, have := h264Players.peek(d.MsgID)
	if joinAt, ok := streamJoinAt(st, have, d.LocalPath, h264Players.elapsed(d.MsgID)); ok {
		a.videoAudioPlayAt(d.AccountID, d.ChatID, d.MsgID, d.LocalPath, joinAt)
	}
	if isDisplayableImage(d.LocalPath) {
		a.decodeFileAsync(d.LocalPath)
	}
	a.invalidate()
}

func (a *App) onDownloadFailed(d engine.DownloadFailedEvent) {
	a.mu.Lock()
	if a.downloads == nil {
		a.downloads = make(map[string]dlState)
	}
	a.downloads[dlKey(d.AccountID, d.ChatID, d.MsgID, d.Seq)] = dlState{state: engine.DownloadFailed}
	a.mu.Unlock()
	a.invalidate()
}

func (a *App) refreshAuth() {
	st := engine.CurrentAuthState(a.authAcctLocked())
	if st == nil {
		return
	}
	a.mu.Lock()
	a.auth = st
	a.mu.Unlock()
	a.invalidate()
}

func (a *App) authAcctLocked() string {
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.authAcct
}

func (a *App) addAccount(platform string) {
	a.mu.Lock()
	a.connecting[platform] = true
	a.mu.Unlock()
	a.invalidate()
	go func() {
		id, err := a.eng.AddAccount(platform, false)
		if err != nil {
			a.setToast("Add account: " + err.Error())
			return
		}
		a.mu.Lock()
		a.authAcct = id
		a.mu.Unlock()
		go a.startAuth(id)
	}()
}

func (a *App) startAuth(id string) {
	st, err := a.eng.StartAuth(id)
	if err != nil {
		a.setToast("Login: " + err.Error())
		a.refreshAccounts()
		return
	}
	a.mu.Lock()
	a.auth = st
	a.authAcct = id
	if st != nil && st.State == engine.AuthStateReady {
		a.auth = nil
	}
	a.mu.Unlock()
	a.invalidate()
}

func (a *App) submitAuth(input string) {
	id := a.authAcctLocked()
	a.mu.Lock()
	st := a.auth
	a.mu.Unlock()
	if st == nil || id == "" {
		return
	}
	a.setBusy(id, true)
	go func() {
		defer a.setBusy(id, false)
		st, err := a.eng.SubmitAuthInput(id, input)
		if err != nil {
			a.setToast("Login: " + err.Error())
		}
		a.mu.Lock()
		a.auth = st
		a.mu.Unlock()
		a.invalidate()
		if st != nil && st.State == engine.AuthStateReady {
			a.signupConsumePhoto(id)
			go func() {
				_ = a.eng.ConnectAccount(id)
			}()
		}
	}()
}

func (a *App) authBack() {
	id := a.authAcctLocked()
	if st, ok := a.eng.GoBackAuth(id); ok {
		a.mu.Lock()
		a.auth = st
		a.mu.Unlock()
		a.invalidate()
	}
}

func (a *App) authCancel() {
	id := a.authAcctLocked()
	a.signupResetPhoto()
	a.eng.CancelAuth(id)
	a.mu.Lock()
	a.auth = nil
	a.mu.Unlock()
	go a.refreshAccounts()
}

func (a *App) setBusy(id string, busy bool) {
	a.mu.Lock()
	if a.connecting == nil {
		a.connecting = make(map[string]bool)
	}
	a.connecting[id] = busy
	a.mu.Unlock()
	a.invalidate()
}

func (a *App) removeAccount(id string) {
	go func() {
		if err := a.eng.RemoveAccount(id); err != nil {
			a.setToast("Remove: " + err.Error())
		}
		a.refreshAccounts()
		a.refreshChats()
	}()
}

type jumpReq struct {
	msgID string
	ts    int64
}

func (a *App) consumePendingOpen() {
	a.mu.Lock()
	k := a.pendingOpen
	title := a.pendingTitle
	a.pendingOpen = nil
	a.pendingTitle = ""
	a.mu.Unlock()
	if k == nil {
		return
	}
	a.openChat(*k, title)
}

func (a *App) leaveChatMediaReset() {
	for _, id := range h264Players.resetAll() {
		a.videoAudioPause(id)
	}
}

func (a *App) openChat(k chatKey, title string) {
	a.hideChatPeek()

	a.mu.Lock()
	prev := a.selected
	var next engine.ChatInfo
	for _, c := range a.chats {
		if c.AccountID == k.AccountID && c.ChatID == k.ChatID {
			next = c
			break
		}
	}
	a.mu.Unlock()
	if a.isSeparate() {
		oldK := chatKey{}
		if prev != nil {
			oldK = *prev
		}
		a.sepMoveRegistry(oldK, k)
		a.win.Option(app.Title(separateWindowTitle(title)))
		a.queueDeselectElsewhere(k)
	}
	if prev != nil && (prev.AccountID != k.AccountID || prev.ChatID != k.ChatID) {
		a.flushDraft(*prev)
		a.leaveChatMediaReset()
	}

	a.mu.Lock()
	a.selected = &k
	a.loadingMsgs = true
	a.messages = nil
	a.uiGen++
	openGen := a.uiGen
	a.olderDone = false
	a.loadingOlder = false
	a.cMode = composerMode{}
	a.menu = nil
	a.fwd = nil
	a.forumTopic = ""
	a.threadScope = nil
	a.savedScope = nil
	a.savedListOpen = false
	a.forumDlg = nil
	a.hdrPresence = nil
	a.selOn = false
	a.sel = nil
	a.autoDl = make(map[string]bool)
	a.downloads = make(map[string]dlState)
	a.panelOpen = false
	a.attachMenuOpen = false
	a.emojiOpen = false
	a.chatMenu = nil
	a.folderMenu = nil
	a.attachDlg = nil
	a.addMemDlg = nil
	a.ttlDlg = nil
	a.privacyDlg = nil
	a.twofaDlg = nil
	a.soundPicker = nil
	a.autoDlDlg = nil
	a.themeDlg = nil
	a.cloudDlg = nil
	a.headerMenu = nil
	a.profile = nil
	a.members = nil
	a.mediaCounts = nil
	a.panelTab = ""
	a.panelTabItems = nil
	a.panelTabLoaded = nil
	a.panelTabPending = nil
	a.panelLinks = nil
	a.panelLinksLoaded = false
	a.pinned = nil
	a.pinnedIdx = 0
	a.pinnedLoaded = false
	a.unreadSepMsgID = ""
	a.viewer = nil
	a.iv = nil
	a.statsPanel = false
	a.statsEarnTab = false
	a.statsEarn = nil
	a.statsEarnLoad = false
	a.statsEarnErr = ""
	a.statsWdBusy = false
	a.boostPanel = false
	a.statsData = nil
	a.adminPanel = false
	a.adminEvents = nil
	a.sendAs = nil
	a.sendAsFor = nil
	a.sendAsCur = ""
	a.sendAsDlg = false
	a.inSearch = false
	a.inSearchQ = ""
	a.inChatHits = nil
	a.inChatIdx = 0
	a.inChatBusy = false
	a.inSearchFrom = ""
	a.inSearchFromName = ""
	a.inSearchFromPanel = false
	a.transPickerOpen = false
	a.delDlg = nil
	a.reportDlg = nil
	a.clearDlg = nil
	a.restrictDlg = nil
	a.schedDlg = nil
	a.groupCall = nil
	a.callPollFor = nil
	a.viewsPollFor = nil
	a.botCmds = nil
	a.botCmdsFor = nil
	a.botCmdsLoaded = false
	a.botCmdsOn = false
	a.sponsored = nil
	a.sponsoredFor = ""
	a.sponsoredViewed = nil
	a.sponsoredDlg = nil
	a.similar = nil
	a.similarFor = ""
	a.replyKbdUsedFor = ""
	a.inlineRes = nil
	a.inlineForKey = ""
	a.inlineForOffset = ""
	a.inlineBusy = false

	if next.DraftText != "" {
		a.wid.composer.SetText(next.DraftText)
	} else {
		a.wid.composer.SetText("")
	}
	a.unreadAtOpen = 0
	for _, c := range a.chats {
		if c.AccountID == k.AccountID && c.ChatID == k.ChatID {
			a.unreadAtOpen = c.UnreadCount
			break
		}
	}
	a.mu.Unlock()
	a.rowBounds = make(map[int]image.Rectangle)
	a.spoilerRevealed = nil
	a.loadPinned(k)
	if next.Type == engine.ChatTypeDMVal && next.ChatID != "" {
		go a.loadHdrPresence(k)
	}
	a.syncCallPoll()
	a.syncViewsRefresh()
	if next.ThemeEmoticon != "" {
		a.ensureChatThemeList(next.AccountID)
	}
	a.loadBotCmds(k)
	a.loadSponsored(k)
	a.loadSimilar(k)
	a.loadHdrCaps(k)
	if next.IsForum {
		go a.loadForumTopics(k)
	}
	a.invalidate()
	go func() {
		msgs, err := a.eng.GetMessages(k.AccountID, k.ChatID, 0, 0, 100)
		if err != nil {
			log.Printf("gui: messages: %v", err)
		}
		for i, j := 0, len(msgs)-1; i < j; i, j = i+1, j-1 {
			msgs[i], msgs[j] = msgs[j], msgs[i]
		}
		a.applyOpenChatMessages(k, openGen, msgs)
		go func() {
			a.mu.Lock()
			localRead := a.cfg.LocalReadMark
			a.mu.Unlock()
			if localRead {
				_ = a.eng.MarkChatRead(k.AccountID, k.ChatID, "")
			}
			a.refreshChats()
		}()
		a.invalidate()
	}()
}

func (a *App) applyOpenChatMessages(k chatKey, gen int, msgs []engine.CachedMessage) {
	a.mu.Lock()
	if a.uiGen != gen || a.selected == nil || *a.selected != k {
		a.mu.Unlock()
		return
	}
	a.messages = msgs
	a.msgFor = &k
	a.loadingMsgs = false
	pj := a.pendingJump
	a.pendingJump = nil
	pt := a.pendingTopic
	a.pendingTopic = nil
	pth := a.pendingThread
	a.pendingThread = nil
	if a.unreadSepMsgID == "" && a.unreadAtOpen > 0 {
		if sepAt := unreadSepIndex(len(msgs), a.unreadAtOpen); sepAt >= 0 && sepAt < len(msgs) {
			a.unreadSepMsgID = msgs[sepAt].MsgID
		}
	}
	a.mu.Unlock()
	if pth != nil {
		a.openCommentThreadDeep(k, *pth)
	} else if pt != nil {
		a.jumpToTopicMessageAt(*pt, pj)
	} else if pj != nil {
		a.jumpToMessageAt(pj.msgID, pj.ts)
	}
}

func (a *App) sendText(text string) {
	a.mu.Lock()
	k := a.selected
	replyID := a.cMode.replyTarget()
	editMsg := ""
	if e := a.cMode.editTarget(); e != nil {
		editMsg = e.MsgID
	}
	silent := a.silentNext
	a.cMode.cancel()
	a.sending = true
	a.mu.Unlock()
	a.invalidate()
	go func() {
		defer func() {
			a.mu.Lock()
			a.sending = false
			a.mu.Unlock()
			a.invalidate()
		}()
		if k == nil || text == "" {
			return
		}
		if editMsg != "" {
			if err := a.eng.EditMessage(k.AccountID, k.ChatID, editMsg, text, ""); err != nil {
				a.setToast("Edit failed: " + err.Error())
			}
			return
		}
		sendText, sendEnts := text, []cores.TextEntity(nil)
		if hasMarkdown(text) {
			sendText, sendEnts = parseMarkdown(text)
		}
		if cfg := a.eng.GetConfig(); cfg != nil && cfg.AyuImproveLinkPreviews {
			sendText = improveLinkURLs(sendText)
		}
		sendChat, sendReply := k.ChatID, replyID
		if ts := a.threadScopeFor(k); ts != nil && ts.discussionChat != "" {
			sendChat = ts.discussionChat
			if sendReply == "" {
				sendReply = ts.rootID
			}
		}
		if _, err := a.eng.SendMessage(k.AccountID, sendChat, sendText, sendReply, sendEnts, silent, 0, a.topicScopeFor(k), "", false, false, false, false, a.linkPreviewOffFor(k)); err != nil {
			a.setToast("Send failed: " + err.Error())
			return
		}
		a.clearDraft(*k)
	}()
}

func (a *App) startReply(m *engine.CachedMessage) {
	a.mu.Lock()
	a.cMode.startReply(m)
	a.mu.Unlock()
	a.invalidate()
}

func (a *App) startEdit(m *engine.CachedMessage) {
	a.mu.Lock()
	a.cMode.startEdit(m)
	a.mu.Unlock()
	a.wid.composer.SetText(m.ContentText)
	a.invalidate()
}

func (a *App) cancelComposerMode() {
	a.mu.Lock()
	editing := a.cMode.editTarget() != nil
	a.cMode.cancel()
	a.mu.Unlock()
	if editing {
		a.wid.composer.SetText("")
	}
	a.invalidate()
}

func (a *App) loadOlder() {
	a.mu.Lock()
	if a.loadingOlder || a.olderDone || a.selected == nil || len(a.messages) == 0 {
		a.mu.Unlock()
		return
	}
	a.loadingOlder = true
	k := *a.selected
	oldest := a.messages[0].Timestamp
	oldestID := 0
	if v, err := strconv.ParseInt(a.messages[0].MsgID, 10, 64); err == nil {
		oldestID = int(v)
	}
	gen := a.uiGen
	a.mu.Unlock()
	go func() {
		var older []engine.CachedMessage
		var err error
		if ts := a.threadScopeFor(&k); ts != nil && ts.discussionChat != "" {
			older, err = a.eng.GetThreadMessages(k.AccountID, ts.discussionChat, ts.rootID, oldest, 50)
		} else if ss := a.savedScopeFor(&k); ss != nil && ss.tag != "" {
			older, err = a.eng.SearchSavedMessagesByReaction(k.AccountID, k.ChatID, "", []string{ss.tag}, oldestID, 50)
		} else if ss := a.savedScopeFor(&k); ss != nil {
			older, err = a.eng.GetSavedSublistMessages(k.AccountID, k.ChatID, ss.peerID, oldest, 50)
		} else if topic := a.topicScopeFor(&k); topic != "" {
			older, err = a.eng.GetTopicMessages(k.AccountID, k.ChatID, topic, oldest, 50)
		} else {
			older, err = a.eng.GetMessages(k.AccountID, k.ChatID, oldest, 0, 50)
		}
		a.applyOlderPage(k, gen, older, err)
	}()
}

func (a *App) applyOlderPage(k chatKey, gen int, older []engine.CachedMessage, err error) {
	a.mu.Lock()
	a.loadingOlder = false
	if a.uiGen != gen || a.selected == nil || *a.selected != k || a.msgFor == nil || *a.msgFor != k {
		a.mu.Unlock()
		a.invalidate()
		return
	}
	if err == nil {
		if len(older) == 0 {
			a.olderDone = true
		} else {
			merged := make([]engine.CachedMessage, 0, len(older)+len(a.messages))
			for i := len(older) - 1; i >= 0; i-- {
				merged = append(merged, older[i])
			}
			a.messages = append(merged, a.messages...)
			a.loadedOlder++
		}
	}
	a.mu.Unlock()
	a.invalidate()
}

type cfgSnapshot struct {
	Theme                  string
	Accent                 string
	FontScale              float64
	FontPath               string
	MonoFontPath           string
	SendReadReceipts       bool
	LocalReadMark          bool
	SendTyping             bool
	SendUploadProgress     bool
	SendReadStories        bool
	SendOnlinePackets      bool
	SendOfflineAfterOnline bool
	MarkReadAfterAction    bool
	UseScheduledMessages   bool
	SendWithoutSound       bool
	NotifyDMs              bool
	NotifyGroups           bool
	NotifyMentionsOnly     bool
	NotifyPreviews         bool
	NotifySound            string
	AyuDeletedMark         string
	AyuEditedMark          string
	AyuSaveDeleted         bool
	AyuSaveHistory         bool
	AyuSaveForBots         bool
	BubbleCorners          bool
	BubbleRadius           int
	WideMult               float64
	DownloadDir            string
	HideAllChats           bool
	RecentSearches         []string
	DrawerHidden           []string
	Streamer               bool
	SystemTray             bool
	ComposerSubmit         string
	SwipeAction            string
	CornerReply            bool
	CornerReaction         bool
	LocalPremium           map[string]bool
	AyuImproveLinkPreviews bool
	AyuMsgSeconds          bool
	AyuFilterZalgo         bool
	AyuReactChannels       bool
	AyuReactGroups         bool
	AyuReactPrivate        bool
	AyuConfirmSticker      bool
	AyuConfirmGif          bool
	AyuConfirmVoice        bool
	AyuHideSimilar         bool
	AyuCollapseSimilar     bool
	AyuAppIcon             string
	AyuAvatarCorners       int
	AyuSingleCornerRadius  bool

	CallInputDevice  string
	CallOutputDevice string
	CallCameraDevice string
}

type notifyAcctState struct {
	contact    bool
	calls      bool
	reactOn    bool
	reactFrom  string
	pollsOn    bool
	pollsFrom  string
	senderName bool
}

func (st *notifyAcctState) applyReactionsMap(rn map[string]interface{}) {
	st.reactOn, _ = rn["reactions_enabled"].(bool)
	st.reactFrom = reactionsFromValue(rn["reactions_from"])
	st.pollsOn, _ = rn["poll_votes_enabled"].(bool)
	st.pollsFrom = reactionsFromValue(rn["poll_votes_from"])
	if from, ok := rn["show_sender_name"].(bool); ok {
		st.senderName = from
	}
}

func reactionsFromValue(v interface{}) string {
	if s, ok := v.(string); ok && s == "contacts" {
		return "contacts"
	}
	return "everyone"
}

func (a *App) applyReactionsNotify(accountID string, st notifyAcctState) {
	go func() {
		if err := a.eng.SetReactionsNotifySettings(accountID, st.reactOn, st.reactFrom, st.pollsOn, st.pollsFrom, st.senderName); err != nil {
			a.setToast("Reactions notify: " + err.Error())
		}
	}()
}

func (a *App) openSettings(section int) {
	a.mu.Lock()
	a.settingsOpen = true
	a.settingsSect = section
	a.mu.Unlock()
	settingsSwitches = make(map[string]*widget.Bool)
	settingsSynced = make(map[string]bool)
	ayuMarksSynced = false
	layoutSliderSeeded = false
	go a.refreshConfig()
	go a.loadStorage()
	go a.loadAutoDl()
	go a.loadCloudThemes()
	go a.loadNotifyAccts()
	go a.loadPrivacy()
	go a.loadGhost()
	go a.loadCallDevices()
	a.invalidate()
}

func (a *App) closeSettings() {
	a.mu.Lock()
	a.settingsOpen = false
	a.mu.Unlock()
	a.invalidate()
}

func (a *App) refreshConfig() {
	c := a.eng.GetConfig()
	if c == nil {
		return
	}
	snap := cfgFromAppConfig(c)
	a.mu.Lock()
	prevIcon := a.cfg.AyuAppIcon
	a.cfg = snap
	accent := a.accentNow
	a.mu.Unlock()
	setMsgShowSeconds(snap.AyuMsgSeconds)
	a.ui.applyAvatarCorners(snap.AyuAvatarCorners)
	a.updateTray()
	if prevIcon != snap.AyuAppIcon || snap.AyuAppIcon == "" || snap.AyuAppIcon == "default" {
		go applyAppIconRuntime(effectiveAppIconSet(snap), accent)
	}
	a.invalidate()
}

func antiRecallFromConfig(c *utils.AppConfig) (saveDeleted, saveHistory, saveForBots bool) {
	saveDeleted = c.AyuSaveDeleted == nil || *c.AyuSaveDeleted
	saveHistory = c.AyuSaveHistory == nil || *c.AyuSaveHistory
	saveForBots = c.AyuSaveForBots != nil && *c.AyuSaveForBots
	return
}

func (a *App) loadStorage() {
	total, err1 := a.eng.GetCacheSize()
	tags, err2 := a.eng.GetCacheSizesByTag("")
	takeout := a.eng.TakeoutAccounts()
	a.mu.Lock()
	if err1 == nil {
		a.cacheTotal = total
	}
	if err2 == nil {
		a.cacheTags = tags
	}
	a.takeoutAccts = takeout
	a.cacheLoaded = true
	a.mu.Unlock()
	a.invalidate()
}

func (a *App) loadCalls() {
	calls := make(map[string][]engine.CallHistoryEntry)
	for _, acc := range a.eng.ListAccounts() {
		if entries, err := a.eng.GetCallHistory(acc.ID, 0, 40); err == nil {
			calls[acc.ID] = entries
		}
	}
	a.mu.Lock()
	a.callsList, a.callsLoaded = calls, true
	a.mu.Unlock()
	a.invalidate()
}

func (a *App) loadNotifyAccts() {
	st := make(map[string]notifyAcctState)
	for _, acc := range a.eng.ListAccounts() {
		contact, err1 := a.eng.GetContactSignUpNotification(acc.ID)
		calls, err2 := a.eng.GetCallsDisabledHere(acc.ID)
		if err1 != nil || err2 != nil {
			continue
		}
		e := notifyAcctState{contact: contact, calls: calls, senderName: true}
		if rn, err := a.eng.GetReactionsNotifySettings(acc.ID); err == nil {
			e.applyReactionsMap(rn)
		}
		st[acc.ID] = e
	}
	a.mu.Lock()
	a.notifyAccts, a.notifyLoaded = st, true
	a.mu.Unlock()
	a.invalidate()
}

func (a *App) loadPrivacy() {
	blocked := make(map[string][]cores.User)
	sessions := make(map[string][]cores.Session)
	scopes := make(map[string]map[string]string)
	twofa := make(map[string]cores.CloudPasswordState)
	for _, acc := range a.eng.ListAccounts() {
		if bl, err := a.eng.GetBlockedUsers(acc.ID); err == nil {
			blocked[acc.ID] = bl
		}
		if ss, err := a.eng.GetSessions(acc.ID); err == nil {
			sessions[acc.ID] = ss
		}
		if sc, err := a.eng.GetPrivacyScopes(acc.ID); err == nil {
			scopes[acc.ID] = sc
		}
		if st, err := a.eng.GetCloudPasswordState(acc.ID); err == nil {
			twofa[acc.ID] = st
		}
	}
	a.mu.Lock()
	a.blockedUsers, a.sessionsList, a.privacyScopes, a.twofaStates = blocked, sessions, scopes, twofa
	a.privacyLoaded = true
	a.mu.Unlock()
	a.invalidate()
}

func (a *App) loadGhost() {
	g := make(map[string]engine.GhostFlags)
	for _, acc := range a.eng.ListAccounts() {
		g[acc.ID] = a.eng.GhostFor(acc.ID)
	}
	a.mu.Lock()
	a.ghostFlags, a.ghostLoaded = g, true
	a.mu.Unlock()
	a.invalidate()
}

func (a *App) applyDrawerHidden(id string, show bool) {
	go func() {
		c := a.eng.GetConfig()
		if c == nil {
			return
		}
		hidden := make([]string, 0, len(c.DrawerHiddenItems))
		for _, h := range c.DrawerHiddenItems {
			if h != id {
				hidden = append(hidden, h)
			}
		}
		if !show {
			hidden = append(hidden, id)
		}
		ch := engine.ConfigChanges{DrawerHiddenItems: hidden}
		if err := a.eng.UpdateConfigFromBridge(&ch); err != nil {
			a.setToast("Drawer settings: " + err.Error())
			return
		}
		a.refreshConfig()
	}()
}

func (a *App) applyConfigBool(field string, v bool) {
	go func() {
		c := configFieldChanges(field, v)
		if c == nil {
			return
		}
		if err := a.eng.UpdateConfigFromBridge(c); err != nil {
			a.setToast("Settings: " + err.Error())
		}
	}()
}

func (a *App) applySystemTray(v bool) {
	go func() {
		c := configFieldChanges("system_tray", v)
		if err := a.eng.UpdateConfigFromBridge(c); err != nil {
			a.setToast("Settings: " + err.Error())
			return
		}
		a.refreshConfig()
		if v {
			a.startTrayIfNeeded()
		} else {
			a.stopTray()
		}
	}()
}

func (a *App) applyTheme(light bool) {
	name := themeName(light)
	a.ui.applyTheme(name)
	go func() {
		c := engine.ConfigChanges{Theme: name}
		if err := a.eng.UpdateConfigFromBridge(&c); err != nil {
			a.setToast("Theme: " + err.Error())
		}
	}()
}

func (a *App) applyAccent(hex string) {
	a.ui.applyAccent(hex)
	go func() {
		c := engine.ConfigChanges{AccentColor: hex}
		if err := a.eng.UpdateConfigFromBridge(&c); err != nil {
			a.setToast("Accent: " + err.Error())
		}
		a.refreshConfig()
	}()
}

func (a *App) applyFontScale(v float64) {
	a.ui.applyFontScale(v)
	go func() {
		c := engine.ConfigChanges{FontScale: v}
		if err := a.eng.UpdateConfigFromBridge(&c); err != nil {
			a.setToast("Font scale: " + err.Error())
		}
		a.refreshConfig()
	}()
}

func (a *App) applyGhostFlag(accountID, field string, v bool) {
	a.mu.Lock()
	g := a.ghostFlags[accountID]
	a.mu.Unlock()
	if !ghostFlagSet(&g, field, v) {
		return
	}
	a.mu.Lock()
	if a.ghostFlags == nil {
		a.ghostFlags = make(map[string]engine.GhostFlags)
	}
	a.ghostFlags[accountID] = g
	a.mu.Unlock()
	go func() {
		a.eng.SetAccountGhost(accountID, g)
	}()
}

func (a *App) acctFilterLocked() string {
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.acctFilter
}

func (a *App) stillTyping(k chatKey) bool {
	a.mu.Lock()
	defer a.mu.Unlock()
	t, ok := a.typing[k.String()]
	return ok && time.Since(t) < 4*time.Second
}

func (a *App) loadHdrPresence(k chatKey) {
	p, err := a.eng.GetUserProfile(k.AccountID, k.ChatID)
	if err != nil || p == nil {
		return
	}
	a.mu.Lock()
	if a.selected != nil && a.selected.AccountID == k.AccountID && a.selected.ChatID == k.ChatID {
		a.hdrPresence = p
	}
	a.mu.Unlock()
	a.invalidate()
}

func (a *App) onUserStatus(accountID string, s engine.UserStatusEvent) {
	a.mu.Lock()
	if a.selected != nil && a.selected.AccountID == accountID && a.selected.ChatID == s.UserID {
		p := a.hdrPresence
		if p == nil {
			p = &engine.CachedUser{AccountID: accountID, UserID: s.UserID}
		}
		p.IsOnline = s.IsOnline
		p.LastSeenKind = s.LastSeenKind
		p.LastSeen = s.LastSeen
		a.hdrPresence = p
	}
	a.mu.Unlock()
	a.invalidate()
}

func (a *App) snapshot() frame {
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.ui != nil {
		a.accentNow = a.ui.p.Accent
	}
	f := frame{
		showPicker:        a.showPicker,
		acctFilter:        a.acctFilter,
		accounts:          a.accounts,
		chats:             a.chats,
		messages:          a.messages,
		msgFor:            a.msgFor,
		selected:          a.selected,
		hdrPresence:       a.hdrPresence,
		loginCode:         a.loginCode,
		loginCodeFresh:    loginCodeFresh(a.loginCode, a.loginCodeAt, time.Now()),
		folder:            a.folder,
		search:            a.search,
		searchMsgs:        a.searchMsgs,
		searchPosts:       a.searchPosts,
		searchGlobal:      a.searchGlobal,
		searchFor:         a.searchFor,
		archiveView:       a.archiveView,
		groupCall:         a.groupCall,
		call:              a.call,
		hdrCaps:           a.hdrCaps,
		joinedGC:          a.joinedGC,
		joinedGCInfo:      a.joinedGCInfo,
		devPickers:        a.devPickers,
		storyView:         a.storyView,
		botCmds:           a.botCmds,
		sponsored:         a.sponsored,
		sponsoredDlg:      a.sponsoredDlg,
		similar:           a.similar,
		botCmdsOn:         a.botCmdsOn,
		botCmdsLoaded:     a.botCmdsLoaded,
		transcribeCap:     a.transcribeCapFor(a.msgFor),
		savedMsgAccts:     savedRowAccounts(a.accounts, a.savedCap),
		savedMsgChats:     a.savedChatID,
		savedChatID:       a.savedChatID,
		forumTopic:        a.forumTopic,
		forumTopics:       a.forumTopics,
		forumLoaded:       a.forumLoaded,
		forumIcons:        a.forumIcons,
		forumDlg:          a.forumDlg,
		topPeers:          a.topPeers,
		topPeersFor:       a.topPeersFor,
		topPeersLoaded:    a.topPeersLoaded,
		mode:              a.mode,
		auth:              a.auth,
		authAcct:          a.authAcct,
		toast:             a.toast,
		toastAt:           a.toastAt,
		connecting:        a.connecting,
		sending:           a.sending,
		loadingMsgs:       a.loadingMsgs,
		cMode:             a.cMode,
		menu:              a.menu,
		fwd:               a.fwd,
		selOn:             a.selOn,
		sel:               a.sel,
		menuCaps:          a.menuCaps,
		availEmojis:       a.availEmojis,
		loadingOlder:      a.loadingOlder,
		now:               time.Now(),
		settingsOpen:      a.settingsOpen,
		settingsSect:      a.settingsSect,
		cfg:               a.cfg,
		lock:              a.lock,
		lockDlg:           a.lockDlg,
		twofaDlg:          a.twofaDlg,
		twofaStates:       a.twofaStates,
		soundPicker:       a.soundPicker,
		notifyAccts:       a.notifyAccts,
		notifyLoaded:      a.notifyLoaded,
		blockedUsers:      a.blockedUsers,
		sessionsList:      a.sessionsList,
		privacyLoaded:     a.privacyLoaded,
		privacyScopes:     a.privacyScopes,
		privacyDlg:        a.privacyDlg,
		autoDlRules:       a.autoDlRules,
		autoDlOn:          a.autoDlOn,
		autoDlDlg:         a.autoDlDlg,
		callsList:         a.callsList,
		callsLoaded:       a.callsLoaded,
		themeDlg:          a.themeDlg,
		wallpaperDlg:      a.wallpaperDlg,
		chatThemes:        a.chatThemes,
		chatThemesFor:     a.chatThemesFor,
		chatThemesOn:      a.chatThemesOn,
		cloudThemes:       a.cloudThemes,
		cloudThemesFor:    a.cloudThemesFor,
		cloudThemeAcct:    a.cloudThemeAcct,
		cloudThemesOn:     a.cloudThemesOn,
		profileEdit:       a.profileEdit,
		stickerMgr:        a.stickerMgr,
		chatPeek:          a.chatPeek,
		sidebarW:          a.sidebarW,
		hoverPos:          a.hoverPos,
		folderMgr:         a.folderMgr,
		premiumPage:       a.premiumPage,
		starsPage:         a.starsPage,
		businessPage:      a.businessPage,
		transChatOn:       a.transChatOn,
		transTarget:       a.transTarget,
		transPickerOpen:   a.transPickerOpen,
		seenInline:        a.seenInline,
		langCode:          a.langCode,
		langStrings:       a.langStrings,
		langs:             a.langs,
		langsLoaded:       a.langsLoaded,
		langsFor:          a.langsFor,
		langsErr:          a.langsErr,
		langApplying:      a.langApplying,
		cloudDlg:          a.cloudDlg,
		cacheTotal:        a.cacheTotal,
		cacheTags:         a.cacheTags,
		cacheLoaded:       a.cacheLoaded,
		takeoutAccts:      a.takeoutAccts,
		ghostSel:          a.ghostSel,
		ghostFlags:        a.ghostFlags,
		ghostLoaded:       a.ghostLoaded,
		panelOpen:         a.panelOpen,
		panelChat:         a.panelChat,
		panelLoaded:       a.panelLoaded,
		panelMuted:        a.panelMuted,
		profile:           a.profile,
		panelBotCmds:      a.panelBotCmds,
		panelMusic:        a.panelMusic,
		musicDlg:          a.musicDlg,
		musicRowMenu:      a.musicRowMenu,
		musicAttachDlg:    a.musicAttachDlg,
		giftDlg:           a.giftDlg,
		giftHideOn:        a.giftHideOn,
		giveawayDlg:       a.giveawayDlg,
		muteDlg:           a.muteDlg,
		members:           a.members,
		mediaCounts:       a.mediaCounts,
		panelTab:          a.panelTab,
		panelTabItems:     a.panelTabItems,
		panelTabLoaded:    a.panelTabLoaded,
		panelLinks:        a.panelLinks,
		panelLinksLoaded:  a.panelLinksLoaded,
		attachMenuOpen:    a.attachMenuOpen,
		emojiOpen:         a.emojiOpen,
		emojiTab:          a.emojiTab,
		unreadAtOpen:      a.unreadAtOpen,
		unreadSepMsgID:    a.unreadSepMsgID,
		pinned:            a.pinned,
		pinnedIdx:         a.pinnedIdx,
		pinnedLoaded:      a.pinnedLoaded,
		folders:           a.folders,
		foldersFor:        a.foldersFor,
		foldersSupported:  a.foldersSupported,
		folderDlg:         a.folderDlg,
		folderInvites:     a.folderInvites,
		attachDlg:         a.attachDlg,
		addMemDlg:         a.addMemDlg,
		searchTab:         a.searchTab,
		ttlDlg:            a.ttlDlg,
		emojiMode:         a.emojiMode,
		stickerPacks:      a.stickerPacks,
		stickerPackIdx:    a.stickerPackIdx,
		recentStickers:    a.recentStickers,
		savedGifs:         a.savedGifs,
		chatMenu:          a.chatMenu,
		folderMenu:        a.folderMenu,
		headerMenu:        a.headerMenu,
		viewer:            a.viewer,
		pip:               a.pip,
		iv:                a.iv,
		drawerOpen:        a.drawerOpen,
		contactsOpen:      a.contactsOpen,
		contactsFor:       a.contactsFor,
		contacts:          a.contacts,
		contactsLoad:      a.contactsLoad,
		addDlgOpen:        a.addDlgOpen,
		addDlgBusy:        a.addDlgBusy,
		newDlg:            a.newDlg,
		newDlgErr:         a.newDlgErr,
		callsBoxOpen:      a.callsBoxOpen,
		callsBoxFor:       a.callsBoxFor,
		callsBoxRows:      a.callsBoxRows,
		callsBoxBusy:      a.callsBoxBusy,
		callsBoxDone:      a.callsBoxDone,
		callsBoxLoad:      a.callsBoxLoad,
		callsBoxMenu:      a.callsBoxMenu,
		callsRowMenu:      a.callsRowMenu,
		callsClearDlg:     a.callsClearDlg,
		mediaConfirm:      mediaConfirmActive(),
		callsDelDlg:       a.callsDelDlg,
		inSearch:          a.inSearch,
		inSearchQ:         a.inSearchQ,
		inChatHits:        a.inChatHits,
		inChatIdx:         a.inChatIdx,
		inChatBusy:        a.inChatBusy,
		inSearchFrom:      a.inSearchFrom,
		inSearchFromName:  a.inSearchFromName,
		inSearchFromPanel: a.inSearchFromPanel,
		delDlg:            a.delDlg,
		reportDlg:         a.reportDlg,
		clearDlg:          a.clearDlg,
		restrictDlg:       a.restrictDlg,
		signupPhotoPath:   a.signupPhotoPath,
		signupPhotoB64:    a.signupPhotoB64,
		threadScope:       a.threadScope,
		savedListOpen:     a.savedListOpen,
		savedLists:        a.savedLists,
		savedListsLoaded:  a.savedListsLoaded,
		savedListsErr:     a.savedListsErr,
		savedScope:        a.savedScope,
		savedTags:         a.savedTags,
		savedTagsLoaded:   a.savedTagsLoaded,
		savedSublistMenu:  a.savedSublistMenu,
		savedDelDlg:       a.savedDelDlg,
		schedDlg:          a.schedDlg,
		pollDlg:           a.pollDlg,
		reactors:          a.reactors,
		ayuFilterDlg:      a.ayuFilterDlg,
		ayuFilterCount:    a.ayuFilterCount,
		ayuFilterCountOn:  a.ayuFilterCountOn,
		shadowDlg:         a.shadowDlg,
		editHistDlg:       a.editHistDlg,
		msgDetailDlg:      a.msgDetailDlg,
		memberMenu:        a.memberMenu,
		commonChats:       a.commonChats,
		commonLoaded:      a.commonLoaded,
		stickerSetDlg:     a.stickerSetDlg,
		deletedDlg:        a.deletedDlg,
		seenDlg:           a.seenDlg,
		exportDlg:         a.exportDlg,
		folderImportDlg:   a.folderImportDlg,
		schedPanel:        a.schedPanel,
		schedMsgs:         a.schedMsgs,
		schedLoad:         a.schedLoad,
		paidDlg:           a.paidDlg,
		rateDlg:           a.rateDlg,
		sendAs:            a.sendAs,
		sendAsFor:         a.sendAsFor,
		sendAsCur:         a.sendAsCur,
		sendAsDlg:         a.sendAsDlg,
		statsPanel:        a.statsPanel,
		boostPanel:        a.boostPanel,
		boostStatus:       a.boostStatus,
		boosters:          a.boosters,
		boostNext:         a.boostNext,
		boostTotal:        a.boostTotal,
		boostGifts:        a.boostGifts,
		boostLoad:         a.boostLoad,
		boostErr:          a.boostErr,
		statsData:         a.statsData,
		statsLoad:         a.statsLoad,
		statsErr:          a.statsErr,
		statsEarnTab:      a.statsEarnTab,
		statsEarn:         a.statsEarn,
		statsEarnLoad:     a.statsEarnLoad,
		statsEarnErr:      a.statsEarnErr,
		statsWdBusy:       a.statsWdBusy,
		adminPanel:        a.adminPanel,
		adminEvents:       a.adminEvents,
		adminLoad:         a.adminLoad,
		adminLoadedAll:    a.adminLoadedAll,
		adminFilters:      a.adminFilters,
		adminErr:          a.adminErr,
		inviteDlg:         a.inviteDlg,
		silentNext:        a.silentNext,
	}
	if len(a.downloads) > 0 {
		dls := make(map[string]dlState, len(a.downloads))
		for k, v := range a.downloads {
			dls[k] = v
		}
		f.downloads = dls
	}
	return f
}

type frame struct {
	showPicker bool
	acctFilter string
	accounts   []engine.AccountInfo
	chats      []engine.ChatInfo
	messages   []engine.CachedMessage
	msgFor     *chatKey
	selected   *chatKey
	folder     int
	search     string

	searchMsgs   []engine.SearchResult
	searchPosts  []engine.SearchResult
	searchGlobal []engine.ChatInfo
	searchFor    string

	archiveView bool

	groupCall *engine.GroupCallInfo

	call    *callUI
	hdrCaps []string

	joinedGC     *joinedCall
	joinedGCInfo *engine.GroupCallInfo

	devPickers map[string]*devPickerState

	storyView *storyViewerState

	botCmds       []engine.BotCommandInfo
	botCmdsOn     bool
	botCmdsLoaded bool

	sponsored    []cores.SponsoredMessageInfo
	sponsoredDlg *sponsoredDlgState

	similar []engine.SimilarChannelInfo

	transcribeCap bool

	savedMsgAccts []string
	savedMsgChats map[string]string
	savedChatID   map[string]string

	forumTopic  string
	forumTopics []cores.ForumTopic
	forumLoaded bool
	forumIcons  []cores.ForumTopicIconInfo
	forumDlg    *forumDlgState

	topPeers       []engine.ChatInfo
	topPeersFor    string
	topPeersLoaded bool

	mode         int
	auth         *engine.AuthState
	authAcct     string
	toast        string
	toastAt      time.Time
	connecting   map[string]bool
	sending      bool
	loadingMsgs  bool
	cMode        composerMode
	menu         *menuTarget
	fwd          []engine.CachedMessage
	menuCaps     []string
	availEmojis  []string
	loadingOlder bool
	now          time.Time

	selOn bool
	sel   map[string]bool

	downloads map[string]dlState

	settingsOpen    bool
	settingsSect    int
	cfg             cfgSnapshot
	lock            *lockState
	lockDlg         *lockDlgState
	twofaDlg        *twofaDlgState
	twofaStates     map[string]cores.CloudPasswordState
	soundPicker     *soundPickerState
	notifyAccts     map[string]notifyAcctState
	notifyLoaded    bool
	blockedUsers    map[string][]cores.User
	sessionsList    map[string][]cores.Session
	privacyLoaded   bool
	privacyScopes   map[string]map[string]string
	privacyDlg      *privacyDlgState
	autoDlRules     map[string]map[string]interface{}
	autoDlOn        bool
	autoDlDlg       *autodlDlgState
	callsList       map[string][]engine.CallHistoryEntry
	callsLoaded     bool
	themeDlg        *chatThemeDlgState
	wallpaperDlg    *wallpaperDlgState
	chatThemes      []cores.ChatThemeInfo
	chatThemesFor   string
	chatThemesOn    bool
	cloudThemes     []cores.CloudThemeInfo
	cloudThemesFor  string
	cloudThemeAcct  string
	cloudThemesOn   bool
	cloudDlg        *cloudThemeDlgState
	profileEdit     *profileEditState
	stickerMgr      *stickerMgrState
	chatPeek        *chatPeekState
	sidebarW        int
	hoverPos        image.Point
	folderMgr       *folderMgrState
	premiumPage     *premiumPageState
	starsPage       *starsPageState
	businessPage    *businessPageState
	transChatOn     map[string]bool
	transTarget     string
	transPickerOpen bool
	seenInline      map[string]*seenInlineState
	langCode        string
	langStrings     map[string]string
	langs           []engine.LanguageInfo
	langsLoaded     bool
	langsFor        string
	langsErr        string
	langApplying    bool
	cacheTotal      int64
	cacheTags       [6]int64
	cacheLoaded     bool
	ghostSel        string
	ghostFlags      map[string]engine.GhostFlags
	ghostLoaded     bool
	panelOpen       bool
	panelChat       chatKey
	panelLoaded     bool
	panelMuted      bool
	profile         *engine.CachedUser
	panelBotCmds    []engine.BotCommandInfo
	panelMusic      []engine.MusicTrack
	musicDlg        *musicDlgState
	musicRowMenu    *musicRowMenuState
	musicAttachDlg  *musicAttachDlgState
	giftDlg         *giftDlgState
	giftHideOn      bool
	giveawayDlg     *giveawayDlgState

	hdrPresence *engine.CachedUser

	loginCode        string
	loginCodeFresh   bool
	members          []engine.MemberInfo
	mediaCounts      []engine.SharedMediaCountItem
	panelTab         string
	panelTabItems    map[string][]engine.SharedMediaItem
	panelTabLoaded   map[string]bool
	panelLinks       []engine.SharedLinkItem
	panelLinksLoaded bool

	attachMenuOpen bool

	emojiOpen bool
	emojiTab  int

	unreadAtOpen   int
	unreadSepMsgID string
	pinned         []engine.CachedMessage
	pinnedIdx      int
	pinnedLoaded   bool

	folders          []engine.FolderInfo
	foldersFor       string
	foldersSupported bool
	folderDlg        *folderDlgState
	folderInvites    *folderInvitesState
	attachDlg        *attachDlgState
	addMemDlg        *addMemDlgState
	searchTab        int
	ttlDlg           *ttlDlgState
	muteDlg          *muteDlgState
	emojiMode        int
	stickerPacks     []cores.StickerPackSummary
	stickerPackIdx   int
	recentStickers   []cores.StickerInfo
	savedGifs        []cores.GifInfo

	chatMenu *chatMenuTarget

	folderMenu *folderMenuTarget

	headerMenu *headerMenuTarget

	drawerOpen   bool
	contactsOpen bool
	contactsFor  string
	contacts     []engine.ContactInfo
	contactsLoad bool
	addDlgOpen   bool
	addDlgBusy   bool
	newDlg       *newChatDlg
	newDlgErr    string

	callsBoxOpen  bool
	callsBoxFor   string
	callsBoxRows  []callBoxRow
	callsBoxBusy  bool
	callsBoxDone  bool
	callsBoxLoad  bool
	callsBoxMenu  *callsBoxMenuTarget
	callsRowMenu  *callsRowMenuTarget
	callsClearDlg bool
	callsDelDlg   int
	mediaConfirm  bool

	inSearch          bool
	inSearchQ         string
	inChatHits        []engine.SearchResult
	inChatIdx         int
	inChatBusy        bool
	inSearchFrom      string
	inSearchFromName  string
	inSearchFromPanel bool

	delDlg    *delDlgState
	reportDlg *reportDlgState

	clearDlg *clearDlgState

	restrictDlg *restrictDlgState

	signupPhotoPath string
	signupPhotoB64  string

	threadScope      *threadScopeState
	savedListOpen    bool
	savedLists       []cores.SavedSublistInfo
	savedListsLoaded bool
	savedListsErr    string
	savedScope       *savedScopeState
	savedTags        []cores.SavedReactionTagInfo
	savedTagsLoaded  bool
	savedSublistMenu *savedSublistMenuTarget
	savedDelDlg      *savedDelDlgState

	schedDlg *schedDlgState

	pollDlg *pollDlgState

	ayuFilterDlg     *ayuFilterDlgState
	ayuFilterCount   int
	ayuFilterCountOn bool

	shadowDlg *shadowDlgState

	folderImportDlg *folderImportState

	editHistDlg   *editHistState
	msgDetailDlg  *msgDetailState
	memberMenu    *memberMenuState
	commonChats   []cores.Dialog
	commonLoaded  bool
	stickerSetDlg *stickerSetDlgState

	deletedDlg *deletedDlgState

	seenDlg *seenDlgState

	exportDlg    *exportDlgState
	takeoutAccts []string

	reactors *reactorsState

	schedPanel bool
	schedMsgs  []engine.CachedMessage
	schedLoad  bool

	paidDlg *paidConfirmState

	rateDlg *rateCallState

	sendAs    []engine.SendAsPeerInfo
	sendAsFor *chatKey
	sendAsCur string
	sendAsDlg bool

	statsPanel bool

	boostPanel  bool
	boostStatus map[string]interface{}
	boosters    []map[string]interface{}
	boostNext   string
	boostTotal  int
	boostGifts  bool
	boostLoad   bool
	boostErr    string

	statsData     *cores.ChannelStats
	statsEarnTab  bool
	statsEarn     *cores.StarsRevenueResult
	statsEarnLoad bool
	statsEarnErr  string
	statsWdBusy   bool
	statsLoad     bool
	statsErr      string

	adminPanel     bool
	adminEvents    []cores.AdminLogEvent
	adminLoad      bool
	adminLoadedAll bool
	adminFilters   map[string]bool
	adminErr       string

	inviteDlg  *inviteDlgState
	silentNext bool

	viewer *viewerState

	pip *pipState

	iv *ivState
}

var _ = op.InvalidateCmd{}
