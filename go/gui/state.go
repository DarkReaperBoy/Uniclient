package gui

import (
	"encoding/json"
	"image"
	"log"
	"sync"
	"time"

	"gioui.org/app"
	"gioui.org/f32"
	"gioui.org/io/event"
	"gioui.org/op"
	"gioui.org/widget"

	"gioui.org/x/explorer"

	"uniclient/cores"
	"uniclient/engine"
)

// App is the root GUI state. Background goroutines mutate state under mu and
// call win.Invalidate() to schedule a redraw — the Gio event loop then reads
// state during the frame. All engine calls (network I/O) run on background
// goroutines, never in the frame loop.
type App struct {
	win *app.Window
	ui  *UI
	eng *engine.Engine

	mu sync.Mutex // guards everything below

	// world state
	accounts []engine.AccountInfo
	chats    []engine.ChatInfo // unified, newest first
	messages []engine.CachedMessage
	msgFor   *chatKey // which chat `messages` belongs to

	// session state
	selected *chatKey
	folder   int
	search   string

	// global search results (slice 16): message hits + server chat hits
	searchMsgs   []engine.SearchResult
	searchGlobal []engine.ChatInfo
	searchFor    string
	mode         int               // 0 chat, 1 voice
	auth         *engine.AuthState // login flow in progress
	authAcct     string
	showPicker   bool
	acctFilter   string // "" = unified list, else filter to one account
	toast        string
	toastAt      time.Time
	connecting   map[string]bool // accountID -> busy
	sending      bool
	loadingMsgs  bool
	loadedOlder  int // how many pages loaded (scroll-up)

	// message-action state (AyuGram parity §1.11: reply/edit composer modes,
	// context menu, forward picker, reactions).
	cMode        composerMode           // reply/edit header above the composer
	menu         *menuTarget            // open message context menu (copy)
	fwd          []engine.CachedMessage // forward picker sources (1 or batch)
	menuCaps     []string               // capabilities cached for the menu's account
	menuCapsFor  string
	availEmojis  []string // available reactions for the menu's account
	availFor     string
	loadingOlder bool
	olderDone    bool // no more history pages for the open chat

	// selection mode (AyuGram parity slice 14): marked message IDs.
	selOn bool
	sel   map[string]bool

	// media-bubble state (AyuGram parity slice 2): live download progress fed
	// by engine events, and the auto-download ledger for prefetches.
	downloads map[string]dlState // dlKey → progress
	autoDl    map[string]bool    // msgID → prefetch already issued

	// settings surface (AyuGram parity slice 3): open view + section, the
	// config snapshot for the toggles, and async-loaded page data.
	settingsOpen  bool
	settingsSect  int
	cfg           cfgSnapshot
	notifyAccts   map[string]notifyAcctState
	notifyLoaded  bool
	blockedUsers  map[string][]cores.User
	sessionsList  map[string][]cores.Session
	privacyLoaded bool
	cacheTotal    int64
	cacheTags     [6]int64
	cacheLoaded   bool
	ghostSel      string
	ghostFlags    map[string]engine.GhostFlags
	ghostLoaded   bool
	// right info panel (AyuGram parity slice 4): profile/members/media
	panelOpen   bool
	panelChat   chatKey
	panelLoaded bool
	panelMuted  bool
	profile     *engine.CachedUser
	members     []engine.MemberInfo
	mediaCounts []engine.SharedMediaCountItem
	panelRecent []engine.SharedMediaItem

	// attach flow (AyuGram parity slice 5): OS file picker + upload pipeline
	expl           *explorer.Explorer
	attachMenuOpen bool

	// emoji picker (AyuGram parity slice 10): panel open + active category
	emojiOpen bool
	emojiTab  int

	// chat chrome (AyuGram parity slice 11): unread boundary snapshot +
	// pinned messages for the open chat.
	unreadAtOpen   int
	unreadSepMsgID string // boundary message the separator anchors to
	pinned         []engine.CachedMessage
	pinnedIdx      int
	pinnedLoaded   bool

	// server folders (AyuGram parity slice 6): real dialog-filter tabs
	folders          []engine.FolderInfo
	foldersFor       string
	foldersSupported bool
	folderDlg        *folderDlgState

	// chat-row context menu (slice 8)
	chatMenu *chatMenuTarget

	// chat-header "..." menu (slice 15)
	headerMenu *headerMenuTarget

	// hamburger main menu (AyuGram parity slice 17): drawer, contacts
	// sheet, new group/channel dialog, and the pending-open hop that lets
	// goroutines schedule openChat on the GUI loop.
	drawerOpen   bool
	contactsOpen bool
	contactsFor  string
	contacts     []engine.ContactInfo
	contactsLoad bool
	addDlgOpen   bool
	addDlgBusy   bool
	newDlg       *newChatDlg
	newDlgErr    string
	pendingOpen  *chatKey
	pendingTitle string

	// in-chat search (AyuGram parity slice 18): scoped FTS + jump nav
	inSearch   bool
	inSearchQ  string
	inChatHits []engine.SearchResult
	inChatFor  string // "q@acct/chat" staleness guard
	inChatIdx  int
	inChatBusy bool

	// delete + report dialogs (AyuGram parity slice 19)
	delDlg    *delDlgState
	reportDlg *reportDlgState

	// drafts + scheduled send (AyuGram parity slice 20)
	schedDlg *schedDlgState

	// per-message silent sends (AyuGram 🔕, slice 23): sticky toggle
	silentNext bool

	// invite-link join (AyuGram parity slice 24)
	inviteDlg *inviteDlgState

	// scheduled-messages panel (AyuGram parity slice 21)
	schedPanel bool
	schedMsgs  []engine.CachedMessage
	schedLoad  bool

	// fullscreen media viewer (AyuGram parity slice 9, §12): shared under
	// mu; zoom/pan gesture state lives with the frame-loop bookkeeping.
	viewer *viewerState

	// transient
	typing   map[string]time.Time // chatKey -> last typing seen
	notifyAt map[string]time.Time // chatKey -> last banner (throttle, slice 22)

	// frame-loop-only layout bookkeeping (single GUI goroutine, no lock):
	// message-row bounds in chat-pane coordinates for right-click hit tests,
	// and the rendered context-menu rect for outside-press dismissal.
	rowBounds      map[int]image.Rectangle
	menuRect       image.Rectangle
	attachMenuRect image.Rectangle
	emojiRect      image.Rectangle
	// sidebar (chat-row menu) bookkeeping
	chatRowBounds  map[int]image.Rectangle
	sbVisible      []engine.ChatInfo
	sbAboveList    int
	chatMenuRect   image.Rectangle
	sbTabBounds    []image.Rectangle // folder-tab bounds (right-click → edit)
	headerMenuRect image.Rectangle
	listTop        int // top Y of the message list within the chat pane
	headerH        int // chat header height
	// media viewer gesture state (frame-loop only): zoom factor, pan
	// offset, double-click bookkeeping.
	mvZoom         float32
	mvPan          f32.Point
	mvLastPressAt  time.Time
	mvLastPressPos f32.Point
}

func New(win *app.Window, eng *engine.Engine) *App {
	return &App{
		win:         win,
		ui:          NewUI(),
		eng:         eng,
		expl:        explorer.NewExplorer(win),
		typing:      make(map[string]time.Time),
		connecting:  make(map[string]bool),
		rowBounds:   make(map[int]image.Rectangle),
		sbTabBounds: make([]image.Rectangle, 0, 8),
		downloads:   make(map[string]dlState),
		autoDl:      make(map[string]bool),
	}
}

// Start boots the app: initial data pull + event subscription + reconnect.
func (a *App) Start() {
	eng := a.eng
	// Apply the persisted theme before the first frame renders (the frame
	// loop has not started yet — single-threaded at this point).
	if cfg := eng.GetConfig(); cfg != nil {
		a.ui.applyTheme(cfg.Theme)
	}
	eng.SetEventCallback(func(data []byte) { a.onEvent(data) })
	go a.refreshAccounts()
	go a.refreshChats()
	go eng.ConnectAllAccounts()
}

// ListenEvents forwards window events to the file explorer (it must see
// every event — e.g. ViewEvent on mobile — to wire OS dialogs).
func (a *App) ListenEvents(evt event.Event) {
	if a.expl != nil {
		a.expl.ListenEvents(evt)
	}
}

// invalidate schedules a redraw (safe from any goroutine).
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

// ── background refreshers ────────────────────────────────────────────────

func (a *App) refreshAccounts() {
	accs := a.eng.ListAccounts()
	a.mu.Lock()
	a.accounts = accs
	a.mu.Unlock()
	a.invalidate()
}

func (a *App) refreshChats() {
	chats, err := a.eng.GetUnifiedChatList(200, 0)
	if err != nil {
		log.Printf("gui: chat list: %v", err)
	}
	a.mu.Lock()
	a.chats = chats
	a.mu.Unlock()
	a.invalidate()
}

// refreshMessages reloads the open chat's messages (cache-first), preserving
// any older history pages the user already scrolled up to (merge instead of
// clobbering the window — AyuGram keeps the loaded history in place).
func (a *App) refreshMessages() {
	a.mu.Lock()
	key := a.msgFor
	selected := a.selected
	a.mu.Unlock()
	k := key
	if k == nil {
		k = selected
	}
	if k == nil {
		return
	}
	msgs, err := a.eng.GetMessages(k.AccountID, k.ChatID, 0, 0, 100)
	if err != nil {
		log.Printf("gui: messages: %v", err)
	}
	// oldest-first for display
	for i, j := 0, len(msgs)-1; i < j; i, j = i+1, j-1 {
		msgs[i], msgs[j] = msgs[j], msgs[i]
	}
	a.mergeMessages(k, msgs)
}

// mergeMessages installs a fresh newest window (oldest-first slice), keeping
// pre-loaded older pages that fall outside it.
func (a *App) mergeMessages(k *chatKey, fresh []engine.CachedMessage) {
	a.mu.Lock()
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

// ── event pump ───────────────────────────────────────────────────────────

// onEvent decodes engine JSON events and updates UI state. Runs on the
// engine's goroutine; state writes are under mu, redraw via invalidate.
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
	case engine.EventLoginCode:
		// auto-fill handled by the login view via auth state refresh
		go a.refreshAuth()
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
	}
}

func (a *App) onMessageEvent(typ, accountID string, data json.RawMessage) {
	// Desktop notifications (slice 22): gate + banner on every incoming
	// message, regardless of which chat (if any) is open.
	if typ == engine.EventMsgReceived {
		var ev engine.MsgReceivedEvent
		if json.Unmarshal(data, &ev) == nil && ev.AccountID == accountID {
			a.maybeNotify(ev)
		}
	}

	a.mu.Lock()
	k := a.msgFor
	open := k != nil
	a.mu.Unlock()
	if !open {
		return
	}
	// Cheap path: only the open chat reloads its messages.
	if typ == engine.EventMsgReceived {
		var m engine.MsgReceivedEvent
		if json.Unmarshal(data, &m) == nil && m.AccountID == k.AccountID && m.ChatID == k.ChatID {
			go a.refreshMessages()
		}
		return
	}
	go a.refreshMessages()
}

// onDownloadProgress records live byte counts for a media bubble.
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

// onDownloadComplete flips the bubble to its local file (copy-on-write so an
// in-flight frame keeps a consistent slice) and swaps the displayed image
// from thumbnail to the full photo.
func (a *App) onDownloadComplete(d engine.DownloadCompleteEvent) {
	a.mu.Lock()
	if a.downloads == nil {
		a.downloads = make(map[string]dlState)
	}
	a.downloads[dlKey(d.AccountID, d.ChatID, d.MsgID, d.Seq)] = dlState{recv: 1, total: 1, state: engine.DownloadComplete}
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
	// The open media viewer swaps the shown item onto its local file.
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
	if isDisplayableImage(d.LocalPath) {
		a.decodeFileAsync(d.LocalPath)
	}
	a.invalidate()
}

// onDownloadFailed flips the bubble back to "tap to retry".
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

// ── engine operations (all async, results land via events/refresh) ───────

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
		// finalizeAuth already connected and synced — drop the login view.
		a.auth = nil
	}
	a.mu.Unlock()
	a.invalidate()
	// engine.ConnectAccount is implied by auth completing for new accounts;
	// existing saved accounts reconnect at boot via ConnectAllAccounts.
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

// openSavedMessages opens the account's self chat (AyuGram "Saved
// messages"). Falls back to the first connected account's self chat.
func (a *App) openSavedMessages(f frame) {
	scope := a.acctFilterLocked()
	var found *engine.ChatInfo
	for i := range f.chats {
		c := f.chats[i]
		if c.IsSelf && (scope == "" || c.AccountID == scope) {
			cc := c
			found = &cc
			break
		}
	}
	if found == nil {
		for i := range f.chats {
			if f.chats[i].IsSelf {
				cc := f.chats[i]
				found = &cc
				break
			}
		}
	}
	if found == nil {
		a.setToast("No saved-messages chat yet — forward something to yourself first")
		return
	}
	a.openChat(chatKey{AccountID: found.AccountID, ChatID: found.ChatID}, found.Title)
}

// consumePendingOpen runs a background-scheduled openChat on the GUI loop
// (set by the new group/channel creation flow).
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

func (a *App) openChat(k chatKey, title string) {
	// Draft flush: persist whatever the composer holds for the chat we are
	// LEAVING, then restore the new chat's draft (slice 20). Runs on the
	// GUI goroutine, so touching the composer editor is safe.
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
	if prev != nil && (prev.AccountID != k.AccountID || prev.ChatID != k.ChatID) {
		a.flushDraft(*prev)
	}

	a.mu.Lock()
	a.selected = &k
	a.loadingMsgs = true
	a.messages = nil
	a.olderDone = false
	a.loadingOlder = false
	a.cMode = composerMode{}
	a.menu = nil
	a.fwd = nil
	a.selOn = false
	a.sel = nil
	a.autoDl = make(map[string]bool)
	a.downloads = make(map[string]dlState)
	a.panelOpen = false
	a.attachMenuOpen = false
	a.emojiOpen = false
	a.chatMenu = nil
	a.headerMenu = nil
	a.profile = nil
	a.members = nil
	a.mediaCounts = nil
	a.panelRecent = nil
	a.pinned = nil
	a.pinnedIdx = 0
	a.pinnedLoaded = false
	a.unreadSepMsgID = ""
	a.viewer = nil     // slice 9: close any open media viewer
	a.inSearch = false // slice 18: close in-chat search
	a.inSearchQ = ""
	a.inChatHits = nil
	a.inChatIdx = 0
	a.inChatBusy = false
	a.delDlg = nil // slice 19: close delete/report dialogs
	a.reportDlg = nil
	a.schedDlg = nil // slice 20: close the schedule dialog

	// Restore the incoming chat's draft into the composer (slice 20).
	if next.DraftText != "" {
		composer.SetText(next.DraftText)
	} else {
		composer.SetText("")
	}
	// Unread snapshot BEFORE the read receipt fires (openChat marks read
	// right after the first load) — the separator position for this visit.
	a.unreadAtOpen = 0
	for _, c := range a.chats {
		if c.AccountID == k.AccountID && c.ChatID == k.ChatID {
			a.unreadAtOpen = c.UnreadCount
			break
		}
	}
	a.mu.Unlock()
	a.rowBounds = make(map[int]image.Rectangle) // stale rows from the previous chat
	a.loadPinned(k)
	a.invalidate()
	go func() {
		msgs, err := a.eng.GetMessages(k.AccountID, k.ChatID, 0, 0, 100)
		if err != nil {
			log.Printf("gui: messages: %v", err)
		}
		for i, j := 0, len(msgs)-1; i < j; i, j = i+1, j-1 {
			msgs[i], msgs[j] = msgs[j], msgs[i]
		}
		a.mu.Lock()
		a.messages = msgs
		a.msgFor = &k
		a.loadingMsgs = false
		// Anchor the unread separator to the boundary message (only
		// on the first load of this visit, before the read receipt).
		if a.unreadSepMsgID == "" && a.unreadAtOpen > 0 {
			if sepAt := unreadSepIndex(len(msgs), a.unreadAtOpen); sepAt >= 0 && sepAt < len(msgs) {
				a.unreadSepMsgID = msgs[sepAt].MsgID
			}
		}
		a.mu.Unlock()
		go func() {
			_ = a.eng.MarkChatRead(k.AccountID, k.ChatID, "")
			a.refreshChats()
		}()
		a.invalidate()
	}()
}

// sendText routes the composer submit through the active reply/edit mode
// (AyuGram input field: reply header → SendMessage(replyToID), edit header
// → EditMessage). Runs the engine call on a background goroutine.
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
		if _, err := a.eng.SendMessage(k.AccountID, k.ChatID, text, replyID, nil, silent, 0, "", "", false, false, false, false); err != nil {
			a.setToast("Send failed: " + err.Error())
			return
		}
		a.clearDraft(*k) // slice 20: sent → the draft is consumed
	}()
}

// startReply enters reply mode for a message (copy retained).
func (a *App) startReply(m *engine.CachedMessage) {
	a.mu.Lock()
	a.cMode.startReply(m)
	a.mu.Unlock()
	a.invalidate()
}

// startEdit enters edit mode and prefills the composer with the original text.
func (a *App) startEdit(m *engine.CachedMessage) {
	a.mu.Lock()
	a.cMode.startEdit(m)
	a.mu.Unlock()
	composer.SetText(m.ContentText)
	// Focus is executed by the menu's Edit action via key.FocusCmd (gio
	// v0.10.2 editors take focus through commands, not methods).
	a.invalidate()
}

// cancelComposerMode clears the reply/edit header.
func (a *App) cancelComposerMode() {
	a.mu.Lock()
	editing := a.cMode.editTarget() != nil
	a.cMode.cancel()
	a.mu.Unlock()
	if editing {
		composer.SetText("")
	}
	a.invalidate()
}

// loadOlder fetches the next history page above the current window when the
// user scrolls to the top (AyuGram HistoryWidget::loadMessages).
func (a *App) loadOlder() {
	a.mu.Lock()
	if a.loadingOlder || a.olderDone || a.selected == nil || len(a.messages) == 0 {
		a.mu.Unlock()
		return
	}
	a.loadingOlder = true
	k := *a.selected
	oldest := a.messages[0].Timestamp
	a.mu.Unlock()
	go func() {
		older, err := a.eng.GetMessages(k.AccountID, k.ChatID, oldest, 0, 50)
		a.mu.Lock()
		a.loadingOlder = false
		if err == nil {
			if len(older) == 0 {
				a.olderDone = true
			} else {
				// older is newest-first; messages is oldest-first — prepend reversed.
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
	}()
}

// ── settings surface (AyuGram parity §8) ──────────────────────────────────

// cfgSnapshot is the frame-read copy of the engine app config.
type cfgSnapshot struct {
	Theme                  string
	SendReadReceipts       bool
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
}

// notifyAcctState carries per-account notification behavior for the page.
type notifyAcctState struct {
	contact bool // contact sign-up notifications
	calls   bool // calls disabled on this account
}

// openSettings switches the content pane to the settings view and kicks off
// the async data loads for its pages. Switch/toggle pools reset because the
// values they mirror are re-read fresh.
func (a *App) openSettings(section int) {
	a.mu.Lock()
	a.settingsOpen = true
	a.settingsSect = section
	a.mu.Unlock()
	settingsSwitches = make(map[string]*widget.Bool)
	settingsSynced = make(map[string]bool)
	go a.refreshConfig()
	go a.loadStorage()
	go a.loadNotifyAccts()
	go a.loadPrivacy()
	go a.loadGhost()
	a.invalidate()
}

// closeSettings returns to the chat/list layout.
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
	snap := cfgSnapshot{
		Theme:                  c.Theme,
		SendReadReceipts:       c.SendReadReceipts,
		SendTyping:             c.SendTyping,
		SendUploadProgress:     c.SendUploadProgress,
		SendReadStories:        c.SendReadStories,
		SendOnlinePackets:      c.SendOnlinePackets,
		SendOfflineAfterOnline: c.SendOfflineAfterOnline,
		MarkReadAfterAction:    c.MarkReadAfterAction,
		UseScheduledMessages:   c.UseScheduledMessages,
		SendWithoutSound:       c.SendWithoutSound,
		NotifyDMs:              c.NotifyDMs,
		NotifyGroups:           c.NotifyGroups,
		NotifyMentionsOnly:     c.NotifyMentionsOnly,
	}
	a.mu.Lock()
	a.cfg = snap
	a.mu.Unlock()
	a.invalidate()
}

// loadStorage reads the cache accounting for the Data & Storage page.
func (a *App) loadStorage() {
	total, err1 := a.eng.GetCacheSize()
	tags, err2 := a.eng.GetCacheSizesByTag("")
	a.mu.Lock()
	if err1 == nil {
		a.cacheTotal = total
	}
	if err2 == nil {
		a.cacheTags = tags
	}
	a.cacheLoaded = true
	a.mu.Unlock()
	a.invalidate()
}

// loadNotifyAccts reads per-account notification behavior.
func (a *App) loadNotifyAccts() {
	st := make(map[string]notifyAcctState)
	for _, acc := range a.eng.ListAccounts() {
		contact, err1 := a.eng.GetContactSignUpNotification(acc.ID)
		calls, err2 := a.eng.GetCallsDisabledHere(acc.ID)
		if err1 != nil || err2 != nil {
			continue
		}
		st[acc.ID] = notifyAcctState{contact: contact, calls: calls}
	}
	a.mu.Lock()
	a.notifyAccts, a.notifyLoaded = st, true
	a.mu.Unlock()
	a.invalidate()
}

// loadPrivacy reads blocked users + active sessions per account.
func (a *App) loadPrivacy() {
	blocked := make(map[string][]cores.User)
	sessions := make(map[string][]cores.Session)
	for _, acc := range a.eng.ListAccounts() {
		if bl, err := a.eng.GetBlockedUsers(acc.ID); err == nil {
			blocked[acc.ID] = bl
		}
		if ss, err := a.eng.GetSessions(acc.ID); err == nil {
			sessions[acc.ID] = ss
		}
	}
	a.mu.Lock()
	a.blockedUsers, a.sessionsList, a.privacyLoaded = blocked, sessions, true
	a.mu.Unlock()
	a.invalidate()
}

// loadGhost reads the effective ghost flags per account.
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

// applyConfigBool persists one config boolean via the bridge (async).
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

// applyTheme swaps the palette and persists the theme name (async).
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

// applyGhostFlag flips one flag of an account's ghost override (async).
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

// acctFilterLocked returns the current account scope.
func (a *App) acctFilterLocked() string {
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.acctFilter
}

// stillTyping reports an active typing indicator for a chat.

func (a *App) stillTyping(k chatKey) bool {
	a.mu.Lock()
	defer a.mu.Unlock()
	t, ok := a.typing[k.String()]
	return ok && time.Since(t) < 4*time.Second
}

// snapshot returns consistent copies for one frame. Message slices etc. are
// copied by reference — they are only ever replaced, never mutated in place.
func (a *App) snapshot() frame {
	a.mu.Lock()
	defer a.mu.Unlock()
	f := frame{
		showPicker:       a.showPicker,
		acctFilter:       a.acctFilter,
		accounts:         a.accounts,
		chats:            a.chats,
		messages:         a.messages,
		msgFor:           a.msgFor,
		selected:         a.selected,
		folder:           a.folder,
		search:           a.search,
		searchMsgs:       a.searchMsgs,
		searchGlobal:     a.searchGlobal,
		searchFor:        a.searchFor,
		mode:             a.mode,
		auth:             a.auth,
		authAcct:         a.authAcct,
		toast:            a.toast,
		toastAt:          a.toastAt,
		connecting:       a.connecting,
		sending:          a.sending,
		loadingMsgs:      a.loadingMsgs,
		cMode:            a.cMode,
		menu:             a.menu,
		fwd:              a.fwd,
		selOn:            a.selOn,
		sel:              a.sel,
		menuCaps:         a.menuCaps,
		availEmojis:      a.availEmojis,
		loadingOlder:     a.loadingOlder,
		now:              time.Now(),
		settingsOpen:     a.settingsOpen,
		settingsSect:     a.settingsSect,
		cfg:              a.cfg,
		notifyAccts:      a.notifyAccts,
		notifyLoaded:     a.notifyLoaded,
		blockedUsers:     a.blockedUsers,
		sessionsList:     a.sessionsList,
		privacyLoaded:    a.privacyLoaded,
		cacheTotal:       a.cacheTotal,
		cacheTags:        a.cacheTags,
		cacheLoaded:      a.cacheLoaded,
		ghostSel:         a.ghostSel,
		ghostFlags:       a.ghostFlags,
		ghostLoaded:      a.ghostLoaded,
		panelOpen:        a.panelOpen,
		panelChat:        a.panelChat,
		panelLoaded:      a.panelLoaded,
		panelMuted:       a.panelMuted,
		profile:          a.profile,
		members:          a.members,
		mediaCounts:      a.mediaCounts,
		panelRecent:      a.panelRecent,
		attachMenuOpen:   a.attachMenuOpen,
		emojiOpen:        a.emojiOpen,
		emojiTab:         a.emojiTab,
		unreadAtOpen:     a.unreadAtOpen,
		unreadSepMsgID:   a.unreadSepMsgID,
		pinned:           a.pinned,
		pinnedIdx:        a.pinnedIdx,
		pinnedLoaded:     a.pinnedLoaded,
		folders:          a.folders,
		foldersSupported: a.foldersSupported,
		folderDlg:        a.folderDlg,
		chatMenu:         a.chatMenu,
		headerMenu:       a.headerMenu,
		viewer:           a.viewer,
		drawerOpen:       a.drawerOpen,
		contactsOpen:     a.contactsOpen,
		contactsFor:      a.contactsFor,
		contacts:         a.contacts,
		contactsLoad:     a.contactsLoad,
		addDlgOpen:       a.addDlgOpen,
		addDlgBusy:       a.addDlgBusy,
		newDlg:           a.newDlg,
		newDlgErr:        a.newDlgErr,
		inSearch:         a.inSearch,
		inSearchQ:        a.inSearchQ,
		inChatHits:       a.inChatHits,
		inChatIdx:        a.inChatIdx,
		inChatBusy:       a.inChatBusy,
		delDlg:           a.delDlg,
		reportDlg:        a.reportDlg,
		schedDlg:         a.schedDlg,
		schedPanel:       a.schedPanel,
		schedMsgs:        a.schedMsgs,
		schedLoad:        a.schedLoad,
		inviteDlg:        a.inviteDlg,
		silentNext:       a.silentNext,
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

// frame is an immutable per-frame snapshot.
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
	searchGlobal []engine.ChatInfo
	searchFor    string
	mode         int
	auth         *engine.AuthState
	authAcct     string
	toast        string
	toastAt      time.Time
	connecting   map[string]bool
	sending      bool
	loadingMsgs  bool
	// message-action surface
	cMode        composerMode
	menu         *menuTarget
	fwd          []engine.CachedMessage
	menuCaps     []string
	availEmojis  []string
	loadingOlder bool
	now          time.Time

	// selection mode (slice 14)
	selOn bool
	sel   map[string]bool

	// media bubbles (slice 2)
	downloads map[string]dlState

	// settings surface (slice 3)
	settingsOpen  bool
	settingsSect  int
	cfg           cfgSnapshot
	notifyAccts   map[string]notifyAcctState
	notifyLoaded  bool
	blockedUsers  map[string][]cores.User
	sessionsList  map[string][]cores.Session
	privacyLoaded bool
	cacheTotal    int64
	cacheTags     [6]int64
	cacheLoaded   bool
	ghostSel      string
	ghostFlags    map[string]engine.GhostFlags
	ghostLoaded   bool
	// right info panel (slice 4)
	panelOpen   bool
	panelChat   chatKey
	panelLoaded bool
	panelMuted  bool
	profile     *engine.CachedUser
	members     []engine.MemberInfo
	mediaCounts []engine.SharedMediaCountItem
	panelRecent []engine.SharedMediaItem

	// attach flow (slice 5)
	attachMenuOpen bool

	// emoji picker (slice 10)
	emojiOpen bool
	emojiTab  int

	// chat chrome (slice 11): unread separator + pinned bar
	unreadAtOpen   int
	unreadSepMsgID string
	pinned         []engine.CachedMessage
	pinnedIdx      int
	pinnedLoaded   bool

	// server folders (slice 6)
	folders          []engine.FolderInfo
	foldersSupported bool
	folderDlg        *folderDlgState

	// chat-row context menu (slice 8)
	chatMenu *chatMenuTarget

	// chat-header "..." menu (slice 15)
	headerMenu *headerMenuTarget

	// hamburger main menu (slice 17)
	drawerOpen   bool
	contactsOpen bool
	contactsFor  string
	contacts     []engine.ContactInfo
	contactsLoad bool
	addDlgOpen   bool
	addDlgBusy   bool
	newDlg       *newChatDlg
	newDlgErr    string

	// in-chat search (slice 18)
	inSearch   bool
	inSearchQ  string
	inChatHits []engine.SearchResult
	inChatIdx  int
	inChatBusy bool

	// delete + report dialogs (slice 19)
	delDlg    *delDlgState
	reportDlg *reportDlgState

	// scheduled send (slice 20)
	schedDlg *schedDlgState

	// scheduled-messages panel (slice 21)
	schedPanel bool
	schedMsgs  []engine.CachedMessage
	schedLoad  bool

	// invite-link join + silent sends (slices 23/24)
	inviteDlg  *inviteDlgState
	silentNext bool

	// fullscreen media viewer (slice 9)
	viewer *viewerState
}

var _ = op.InvalidateCmd{} // referenced in widgets that animate
