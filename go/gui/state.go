package gui

import (
	"encoding/json"
	"image"
	"log"
	"sync"
	"time"

	"gioui.org/app"
	"gioui.org/op"

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
	selected    *chatKey
	folder      int
	search      string
	mode        int               // 0 chat, 1 voice
	auth        *engine.AuthState // login flow in progress
	authAcct    string
	showPicker  bool
	acctFilter  string // "" = unified list, else filter to one account
	toast       string
	toastAt     time.Time
	connecting  map[string]bool // accountID -> busy
	sending     bool
	loadingMsgs bool
	loadedOlder int // how many pages loaded (scroll-up)

	// message-action state (AyuGram parity §1.11: reply/edit composer modes,
	// context menu, forward picker, reactions).
	cMode        composerMode          // reply/edit header above the composer
	menu         *menuTarget           // open message context menu (copy)
	fwd          *engine.CachedMessage // forward picker source (copy)
	menuCaps     []string              // capabilities cached for the menu's account
	menuCapsFor  string
	availEmojis  []string // available reactions for the menu's account
	availFor     string
	loadingOlder bool
	olderDone    bool // no more history pages for the open chat

	// transient
	typing map[string]time.Time // chatKey -> last typing seen

	// frame-loop-only layout bookkeeping (single GUI goroutine, no lock):
	// message-row bounds in chat-pane coordinates for right-click hit tests,
	// and the rendered context-menu rect for outside-press dismissal.
	rowBounds map[int]image.Rectangle
	menuRect  image.Rectangle
	listTop   int // top Y of the message list within the chat pane
	headerH   int // chat header height
}

func New(win *app.Window, eng *engine.Engine) *App {
	return &App{
		win:        win,
		ui:         NewUI(),
		eng:        eng,
		typing:     make(map[string]time.Time),
		connecting: make(map[string]bool),
		rowBounds:  make(map[int]image.Rectangle),
	}
}

// Start boots the app: initial data pull + event subscription + reconnect.
func (a *App) Start() {
	eng := a.eng
	eng.SetEventCallback(func(data []byte) { a.onEvent(data) })
	go a.refreshAccounts()
	go a.refreshChats()
	go eng.ConnectAllAccounts()
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
	}
}

func (a *App) onMessageEvent(typ, accountID string, data json.RawMessage) {
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

func (a *App) openChat(k chatKey, title string) {
	a.mu.Lock()
	a.selected = &k
	a.loadingMsgs = true
	a.messages = nil
	a.olderDone = false
	a.loadingOlder = false
	a.cMode = composerMode{}
	a.menu = nil
	a.fwd = nil
	a.mu.Unlock()
	a.rowBounds = make(map[int]image.Rectangle) // stale rows from the previous chat
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
		if _, err := a.eng.SendMessage(k.AccountID, k.ChatID, text, replyID, nil, false, 0, "", "", false, false, false, false); err != nil {
			a.setToast("Send failed: " + err.Error())
		}
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
	composer.Focus()
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
		showPicker:   a.showPicker,
		acctFilter:   a.acctFilter,
		accounts:     a.accounts,
		chats:        a.chats,
		messages:     a.messages,
		msgFor:       a.msgFor,
		selected:     a.selected,
		folder:       a.folder,
		search:       a.search,
		mode:         a.mode,
		auth:         a.auth,
		authAcct:     a.authAcct,
		toast:        a.toast,
		toastAt:      a.toastAt,
		connecting:   a.connecting,
		sending:      a.sending,
		loadingMsgs:  a.loadingMsgs,
		cMode:        a.cMode,
		menu:         a.menu,
		fwd:          a.fwd,
		menuCaps:     a.menuCaps,
		availEmojis:  a.availEmojis,
		loadingOlder: a.loadingOlder,
		now:          time.Now(),
	}
	return f
}

// frame is an immutable per-frame snapshot.
type frame struct {
	showPicker  bool
	acctFilter  string
	accounts    []engine.AccountInfo
	chats       []engine.ChatInfo
	messages    []engine.CachedMessage
	msgFor      *chatKey
	selected    *chatKey
	folder      int
	search      string
	mode        int
	auth        *engine.AuthState
	authAcct    string
	toast       string
	toastAt     time.Time
	connecting  map[string]bool
	sending     bool
	loadingMsgs bool
	// message-action surface
	cMode        composerMode
	menu         *menuTarget
	fwd          *engine.CachedMessage
	menuCaps     []string
	availEmojis  []string
	loadingOlder bool
	now          time.Time
}

var _ = op.InvalidateCmd{} // referenced in widgets that animate
