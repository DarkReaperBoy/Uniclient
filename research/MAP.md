# research/MAP.md — cycle-2 P0 surface map

One chunk per iteration (AGENTS.md §4 P0). Chunk = package set read IN FULL this
session; every claim below is from reading the code, not filenames. Tick + commit.

## Chunk 1 — go/cmd/uniclient + go/bootstrap (session 329)

### cmd/uniclient (main.go, 118 lines)
- Entry: flags `-dir` (default `$UNICLIENT_HOME` || `~/.uniclient`; js → `/uniclient`;
  UserHomeDir error → `.uniclient`), `-password` (`UNICLIENT_PASSWORD` || `"uniclient"`).
- `main()`: `gui.HandleLaunchURI(flag.Args(), dir)` first — the Windows uniclient://
  launcher forwards to the running instance and exits before any window exists
  (slice 202). Then `app.Window` 1120×760, min 360×480; `run()` in a goroutine +
  `app.Main()` on the main thread.
- `run()`: `bootstrap.Init(dir, dir/cache, dir/downloads, password, nil)` — events are
  nil because the GUI subscribes its own callback. `defer bootstrap.Shutdown()`;
  `gui.New(w, eng)` → `ui.Start()` → `ui.ServeInstanceCommands(dir)` (single-instance
  command listener, Windows toast click-through) → `defer ui.Shutdown()` (tray, slice
  137). Event loop: `ui.ListenEvents(e)` on EVERY event (mobile ViewEvent for the file
  explorer), `DestroyEvent` → `gui.CloseSeparateWindowsAndWait()` (slice 168: close
  separate windows BEFORE engine teardown so no frame races shutdown) → return,
  `FrameEvent` → `ui.Root(gtx)`.

### bootstrap (bootstrap.go, 194 lines)
- Package-global `eng *engine.Engine`; `Init` overwrites without shutting down the
  previous one (test-harness hazard; production boots exactly once).
- `supportedPlatforms` (9) = single source of truth for real backends;
  `SupportedPlatforms()` returns a copy; the GUI picker is tested against it.
- `Init()`: `engine.Init` → `migrateOldSessions` → `SetCoreFactory(platform, accountID)`:
  per-account `utils.SessionStore` over the vault. Telegram branch: apiID/apiHash
  2040/`b18441a…` (the public builtin pair; `TG_API_ID`/`TG_API_HASH` override) +
  `TestMode` read from the vault account entry (test DC). bale/matrix/irc/xmpp/github/
  deltachat/teamspeak/mumble: direct constructors (TS/Mumble stale "hidden" comments
  removed session 329 — the GUI DOES offer them natively; §8 LIVE is the truth).
- Post-init purge: saved accounts on unsupported platforms are REMOVED at boot
  (logged) — they could never connect (§1.10).
- `vaultSessionStorage`: gotd `session.Storage` adapter over `LoadRaw`/`SaveRaw`,
  `session.ErrNotFound` when nil.
- `migrateOldSessions(configDir, vault)`: scans `configDir/sessions/<platform>/
  <accountID>.json` → `SaveSessionRaw` when `!HasSession` → `os.RemoveAll(sessDir)`
  only if something migrated.

### Critical journeys on this surface
boot → engine init (vault+DB blocking, off UI thread) → GUI start → event loop;
URI-launch forwarding (no engine boot); shutdown: window close → separate windows
drained → ui.Shutdown (tray) → engine.Shutdown.

### Risk register (feeds P2)
- R11: `log.Fatal(err)` in `run()`'s goroutine on engine-init failure — os.Exit skips
  ALL defers; on js/wasm there is no exit: check the failure surface (shell overlay
  covers boot errors pre-canvas; verify engine-init timing vs overlay hide). Class:
  degraded UX on a rare path; needs a driven reproduction (law 21b).
- R12: `migrateOldSessions` edge — a session file named exactly `.json` yields
  accountID `""` → junk vault session row (boundary; law 21a). Also unbounded
  `os.ReadFile` (configDir is owner-controlled; acceptable).
- R13: second `Init` overwrites the global engine — first engine leaks (test-only
  path today; note for harnesses).
- Verified NOT a risk: multi-window teardown ordering; account-purge logging; gotd
  session adapter error mapping.

| Chunk | Packages | Status |
|---|---|---|
| 1 | cmd/uniclient, bootstrap | mapped (329) |
| 2 | gui — state core (state.go + app.go Root/layoutMain) | mapped (330-331) |
| 3 | gui — remaining files (one surface per iteration) | in progress (331: chat.go; 332: sidebar.go, chatsearch.go, shortcuts.go, settings.go + R16, R17; 333: mediaview.go + profile.go + R18-R22) |

## Chunk 2 — go/gui, state/mutex core (session 330, iteration 1)

gui = ONE package, 91,617 lines / ~90 files — chunked by surface, one per iteration.
Iteration 1 = the state core: `state.go` (2,837 lines, read: struct head 1-180,
lifecycle 642-803, refreshers 807-891, event dispatch 970-1114, openChat 1341-1415,
func inventory) + `app.go` (449 lines, func inventory + Root frame entry). NOT yet
read: struct tail 181-641 (feature-state field groups), refreshMessages/mergeMessages
(892-969), downloads/auth/composer bodies (1115-1340, 1416-1747), cfg/load*/apply*
families (1748-2837), and every other gui file.

### State model
- `App` (state.go:30) = root state: `win/ui/eng` + per-window widget state
  (`wid widgets`, clickables — GUI-loop-only, NO lock) + `separate *chatKey`
  (multi-window, slice 168) + ONE `mu sync.Mutex` guarding ~all world/session state
  (accounts, chats, messages+msgFor, selected, search, mode, auth, + ~40
  "slice NNN"-labeled feature groups). Provenance discipline is exemplary: every
  field group cites its slice; bug fixes cite B-NN.
- Small specialist mutexes exist (`loopLogMu` diagnostic throttle); `sepMu` guards
  the global `mainRef` (separate-window registry); `lockEngaged` is process-wide
  atomic for the passcode.
- Event wiring: `Start()` uses `eng.Subscribe` (fan-out) — NEVER `SetEventCallback`
  (would replace every subscriber); lock-bus share for passcode state; theme/config
  applied BEFORE the first frame (single-threaded window documented); separate
  windows skip tray/taskbar/notify/ConnectAll (main-window-owned singletons).
- Event flow: `onEvent` JSON envelope `{type, account_id, timestamp_ms, data}` →
  ~20-case switch → per-type unmarshal → handler; refreshers spawned with `go`;
  `onMessageEvent` cheap-paths only the open chat (msgFor match). Every state
  mutation ends in `invalidate()` (win.Invalidate from any goroutine).
- openChat: flush LEAVING chat's draft → leaveChatMediaReset (B-4/B-9: explicitly
  called WITHOUT a.mu — closeSrc reaches the engine file guard) → separate-window
  retarget (sepMoveRegistry + queueDeselectElsewhere, one window per chat) → one
  locked block resets view state (selected/loadingMsgs/messages/olderDone/cMode…).

### Lock-discipline audit (the chunk's headline)
awk lock-state scanner over ALL gui/*.go, defer-aware, both call forms
(`a.eng.X` and captured `eng.X`): **749 `a.mu.Lock()` sites, ZERO engine calls
under the lock.** Refreshers follow engine-call-first-then-lock
(refreshAccounts/refreshChats). "…Locked()" suffix = call-with-lock-held contract
(acctFilterLocked, authAcctLocked). The §2 mutex law holds at the gui layer.

### Watch items (P2/P4 candidates — NOT BUGS rows until verified/measured)
- Typing events spawn a goroutine + 4 s sleep per event (state.go:1004) — churn
  under rapid typing, not a leak (self-exits). P2 lens: goroutine lifecycles.
- refreshAccounts queries transcription/saved caps SERIALLY per account on one
  goroutine (state.go:815-819) — boot-time latency with many/slow accounts.
  P4 lens: measure before touching.
- R11 interplay: gui has no boot-failure surface of its own — engine-init failure
  dies in main.go's goroutine (R11 stands; the web shell overlay only covers
  pre-canvas web boots).

Iteration 2 (session 331) completed the file: struct tail 181-640, refreshMessages/
mergeMessages, downloads 1115-1208, auth flows 1210-1335, openChat full body,
sendText/composer/loadOlder, cfgSnapshot + openSettings, load*/apply* families,
snapshot() + frame struct. app.go Root (separate-window routing, passcode gate,
content priority) + layoutMain (narrow/desktop chains) read in full.

### Iteration-2 findings
- **R14 (BUGS.md): package-level `inSearchFromPanel`** (chatsearch.go:25) —
  written/read from ANY window's GUI loop (toggle 226, reads 248/318, resets
  at chatsearch.go:472 + state.go:1477 openChat). Separate windows render the
  chat surface (separateChatView → layoutChatView → chatHeader → search button
  chat.go:480), so two windows' loops hit the same bool unsynchronized: data
  race + cross-window UI bleed (B-47 class, the exact thing the struct comment
  warns about). Fix belongs to P2 (per-App field like the other slice-168
  state).
- settings* package vars (settingsSwitches/settingsSynced/ayuMarksSynced/
  layoutSliderSeeded) — same architectural family BUT settings never renders in
  a separate window (Root:51-52), so single-goroutine in practice → no race;
  P3 note: fold into App with the widget-state group.
- snapshot() copies ~200 fields under one lock; slices by reference (replace-
  only discipline holds — onDownloadComplete copy-on-writes before mutation).
- mergeMessages edge: older-page messages with timestamp == fresh[0].Timestamp
  are dropped from the merged view (display-only; cache intact) — cosmetic
  watch item for P2's boundary lens.
- All auth/send/pagination flows: engine calls outside the lock, re-entrancy
  guarded (loadingOlder), staleness guards (…For keys) everywhere. Clean.

### Journeys mapped
boot → Start (subscribe+theme+lock) → go refresh*+ConnectAll → events → invalidate
→ frame reads state; open-chat (draft flush → media reset → state reset → load);
typing indicator lifecycle; desktop-notification gate on every incoming message.

## Chunk 3 — go/gui, per-file surfaces (from session 331)

### chat.go (1,578 lines — session 331, read in full: layout chain, messageList,
messageRow bubble tree, composer; header/bars skimmed at the overlay level)
- **layoutChatView** priority chain: no-selection → emptyState; fwd picker → full
  pane; panelOpen+narrow → info panel; schedPanel; adminPanel; statsPanel;
  boostPanel; then pane events; savedListOpen → chat+lists flex; panelOpen →
  desktop 3-pane; else chatPaneColumn. **chatPaneColumn** = header + divider +
  conditional strips (forum tabs / topic bar / thread bar / saved-scope bar /
  call bar / sel-or-pinned bar / in-chat search / translate bar / sponsored bar,
  each adding to a.listTop) + messageList-or-topicList + reply keyboard +
  composer variant (JOIN bar if NotJoined, restricted bar, voice-rec panel,
  else composerBar) + a 20-deep overlay chain (context menu, send-confirm card,
  forum dialog, header menu, attach, emoji, bot cmds, inline results, emoji
  autocomplete, del/report/sponsored/sendAs/paid/sched/poll/reactors/shadow/
  editHist/deleted/seen/msgDetail/stickerSet dialogs).
- **messageList**: msgFrameLastOwn per pass (B-47/B-48 honored); wallpaper or
  chat-theme background under rows; 200 ms invalidation loop while
  typing/sending/downloading; row model = buildChatRows + sponsored + similar
  (collapsed gating via per-chat override); loading spinner / empty intro;
  rowBounds rebuilt per frame (frame-loop bookkeeping); scroll-up pagination
  trigger at First==0 && Offset<=64 && !loadingOlder && !olderDone → loadOlder
  (which re-guards under a.mu).
- **messageRow**: service → centered pill or gift card; bare stickers no chrome;
  standard bubble = forwarded header (masked in streamer mode) + poll + webpage
  card + media (paid wall owns the row when locked) + reply quote + sender
  (name color/rank, anti-recall fade) + rich text w/ spoilers + meta strip;
  zalgo/bidi filter and deleted-mark applied to the RENDER copy only (cache
  untouched — good).
- **composerBar/trySubmitComposer**: shared submit gate (empty/limit/slow-mode/
  in-flight), Enter vs Ctrl+Enter modes (tdesktop setting, slice 155),
  Ctrl+Enter only while composer focused, slow-tick armed while waiting,
  ensureSendAs per chat. Draft: cleared only on successful send (state.go
  clearDraftAfterSend path).
- **Watch item RESOLVED as R20 (session 333, law 22/23)**: the claim
  "failed send loses the typed text" was WRONG in its premise — the text
  is NOT lost: eng.SendMessage is the QUEUED path (pending.go inserts a
  visible pending message; on permanent failure FailMessage marks it
  MsgStatusFailed — tdesktop's model exactly). The real bugs: statusTicks
  mapped the status consts shifted (Failed drew the delivered
  double-check, Sending drew a check, Read lost its accent to Delivered)
  and RetryPending had NO gui wiring. Fixed: statusTickKind mapping +
  alertMark glyph, Resend menu action, failure toast (R20 in BUGS).
- Lock discipline in this file: all state writes via a.mu (or documented
  frame-loop-only fields); no engine calls under the lock; clean.

### sidebar.go (1,050 lines — session 332, read in full: account bar/mode tabs/
search field/folder tabs/chat list/rows; the chat-list journey)
- **layoutSidebar** vertical chain: account bar (+dropdown menu), Chat|Voice
  mode tabs, search field (+invite-scan glyph), search-result tabs, recent
  searches, top peers, story strip, saved-messages rows, folder tabs (or
  archive back row), suggestion bar, then the scrolling chat list; overlays
  after: chat-row menu, folder-tab menu, next-unread jump btn, invite dialog.
  All bounds bookkeeping per frame: sbAboveList accumulates, chatRowBounds/
  sbTabBounds/sbVisible are GUI-loop-only App fields (read by chatmenu/
  swipeaction on the same loop; chatpeek reads f.sidebarW from the frame).
- **Chat list model**: filterChats = account filter → archive split (main list
  hides archived unless searching; archive view is archived-only) → folder tab
  match → title/last-msg substring search. Search rows = invite join row +
  section headers + local chats + message results + global chats (+posts),
  filtered by searchTab. Click model uses Update-not-Clicked to read the
  modifier set: Ctrl+click → openSeparateWindow (slice 168), else openChat.
- **Rows**: avatar w/ streamer mode + conn dot; title badges (verified/
  premium/scam/fake); preview = draft (error color) > typing (accent) >
  LastMsgText > typed media label; media thumb; trailing badges (mentions,
  reactions, unread). Hover quick actions = 2 clickables/row (mute/read
  toggles → engine calls in goroutines, toast + refreshChats after). Swipe
  layer (slice 158) passes through to rows. Timed-mute chip: minute-boundary
  InvalidateCmd + expired-mute → go refreshChats.
- **Lock discipline**: 8 short a.mu sites, all pure field sets; engine calls
  (MuteChat, MarkChatRead/Unread) only in spawned goroutines — clean.
- **Package-level widgets** (sidebarSearch, accountMenuOpen, chatListBtns,
  folderBtns, searchMsgBtns/GlobalBtns, inviteRowBtn, lists): main-window-only
  by render path — layoutSidebar is called only from layoutMain; the drawer
  (accountMenuOpen=false) also renders main-only (Root's separate branch
  returns before it). Same P3 fold-in note as settings* (session 331).
- **Cross-window exposure via the SHORTCUTS layer** (renders in EVERY window,
  shortcuts.go): two paths reach sidebar-owned package state from a separate
  window's loop — (1) Esc→escTarget "search"→sidebarSearch.SetText(""):
  unreachable in separate Apps ONLY through the invariant that a.search is
  settable solely via the main window's searchField (implicit, fragile);
  (2) Ctrl+F with no chat open → FocusCmd{Tag:&sidebarSearch} executed on
  whichever window's queue handled the key — in a separate window it focuses
  an editor that renders in ANOTHER window (wrong-window no-op; the window is
  in its empty state when reachable). With a chat open, Ctrl+F correctly hits
  toggleInChatSearch on per-App state (separate windows carry their OWN
  selected — separateChatView gates on f.selected, and Ctrl+Down chat-switch
  runs openChat on the separate App's own loop/widgets: per-App wid is the
  slice-168/B-47 design). Watch item: make the search invariant explicit (or
  route handleSearchShortcut per-window) when shortcuts.go gets its iteration.
- **Watch item (P4 churn family, with typing-tick/serial-caps)**: refreshChats
  has no re-entrancy guard — the timed-mute expiry path spawns one per frame
  until the refreshed list lands (engine round-trip window). Idempotent read,
  last-write-wins under lock; wasted work only.

### chatsearch.go (478 lines — session 332, read in full: the in-chat search
surface, post-R14 shape)
- **State**: all interactive widgets on a.wid (per-App: inSearchEd, close/
  prev/next/from buttons, result rows + lists, from-picker rows) — no
  package-level widget state left; inSearchFromPanel is per-App under a.mu
  (R14 verified at all five sites: toggle :226, frame-read render :250, tint
  :320, close-on-pick :473, openChat reset state.go:1481).
- **Async search**: onInChatSearchChanged (GUI loop) → engine FTS scoped by
  chat, in a goroutine, with a staleness key (query@chat|from) written to
  inChatFor BEFORE spawn and compared under lock on landing — stale writes
  dropped. Hashtag queries ("#x", ≥2 runes) switch to SearchMessagesByTag.
  2-rune minimum gates the search + busy flag.
- **Navigation**: prev/next clamps + jumpToMessageAt; row click sets idx +
  jumps; position counter x/y from the frame; from-filter chip in the bar.
- **From-picker**: senders derived from the LOADED message window only
  (searchSenders over f.messages) — scope note: members older than the
  loaded window are not offered (loaded-data honesty, vs tdesktop's full
  member list — fine for now, note if parity complains).
- **Esc**: pane-local key layer (inSearchKeyTag) + the global shortcuts
  layer maps escTarget "inChatSearch" → closeInChatSearch (priority ABOVE
  the sidebar "search" target — correct).
- Lock discipline: clean; SetText/Text on a.wid editors all GUI-loop.
- **Watch item (P4 churn family)**: one goroutine per ChangeEvent — as-you-
  type fires an engine FTS query per keystroke (no debounce); staleness
  guard keeps results correct, cost is query churn only. Same family as
  typing-tick / refreshChats / serial-caps.

### shortcuts.go (447 lines — session 332, read in full: the global keyboard
layer; iteration 4, produced R16)
- **layoutShortcuts** = window-wide pointer-transparent key layer (registered
  LAST in Root, both window branches) + five event drains in a FIXED order:
  Esc (escTarget chain) → Ctrl+F → Ctrl+Tab/Shift+Tab (account scope, slice
  147) → generic ModCtrl (chat switch/edge/jumplist/contacts/read) → Alt
  arrows. **R16 (fixed this session)**: the Tab drain must precede the
  generic ModCtrl drain — gio delivers a key event to a handler once per
  frame, so a broader earlier filter starves narrower later ones; Ctrl+Tab
  account cycling was dead until the reorder (RED-first
  TestCtrlTabReachesAccountSwitchLoop pins the order, input.Router harness).
  Esc/Ctrl+F/Alt verified collision-free.
- **escTarget** is pure over the FRAME (unit-tested): self-handled surfaces
  (dialogs, viewer, drawer, contacts, calls box, settings, sched panel)
  return "" — their own layouts consume Esc first; then menu/headerMenu/
  folderMenu/chatMenu/attach/botcmds/emoji/selection/inChatSearch/panel/
  search/archive in dismissal order.
- **Handlers all act per-App** (whichever window's loop received the key):
  chat switch/edge/jumplist → openChat (retargets a separate window via
  sepMoveRegistry — per-window behavior, correct); readChat → engine call in
  a goroutine; switchAccountScope under a.mu + refreshFolders outside.
  Cross-window watch items (from the sidebar iteration) live here:
  handleEscTarget "search" → sidebarSearch.SetText("") — reachable only via
  the main App's f.search invariant; handleSearchShortcut's fallback
  FocusCmd{Tag:&sidebarSearch} — wrong-window edge when a separate window is
  empty. Candidate hardening: per-window routing when this file is next
  touched.
- Pure mappers (chatSwitchAction, chatEdgeAction, jumplistDigit,
  pinnedJumpChat, showContactsKey, readChatKey, accountScopeCycle,
  accountSwitchStep, neighborChat, escTarget) are all unit-tested.

### settings.go (1,717 lines — session 332, read in full: the settings shell;
iteration 5, produced R17)
- **Shell**: layoutSettings = self-handled Esc (settingsKeyTag, pointer-
  transparent) + header + rail (9 sections, AyuGram order) + scrolling page.
  settingsPage routes to sub-managers FIRST (profileEdit, stickerMgr,
  folderMgr, premiumPage, starsPage, businessPage) then the 9 sections.
  Every toggle/row backs a real engine call (§1.10 honored: capability-
  gated rows — twofa, takeout export, premium/stars/business Telegram-only,
  tray on tray platforms, app icon picker on WM_SETICON/_NET_WM_ICON).
- **toggleRow + settingsSwitches map**: package-level widget pool keyed by
  config field ("cfg:x", "notify:x:acct", "ghost:acct:field", "drawer:x");
  syncs the switch from the config value ONCE (settingsSynced), then user
  flips drive apply closures. Cap 128 → map reset (re-sync). Main-window-
  only by render path (Root routes settings away from separate windows —
  session-331 audit stands). Watch item (P3, UX): after first sync the
  switch never re-syncs from config pushes (external change → stale toggle
  until the 128-cap reset or restart); tdesktop re-syncs on config push.
- **Ayu page**: global defaults (config) + per-account ghost overrides
  (engine ghost store, chips selector, reset button); mark-string editors
  (ayuDeletedEd/ayuEditedEd, one-shot synced, Apply → engine goroutine);
  drawer-row visibility; message-filter row; app-icon grid; avatar corners.
- Lock discipline: clean — a.mu around short field sets (settingsSect,
  ghostSel, notifyAccts mutations), engine calls (SetContactSignUpNotification,
  SetCallsDisabledHere, ClearCacheByTag/ClearCache, UpdateConfigFromBridge,
  ClearAccountGhostOverrides) all in goroutines with toast+refresh.
- **R17 (fixed this session)**: appVersion was 0.7.0 on the v0.10.3 line —
  bumped + TestAppVersionMatchesReleaseLine pins appVersion == flake.nix
  version (the string release.yml enforces against the tag); About shortcut
  list gained the Ctrl+Tab row (R16 parity), pinned by TestShortcutRows.

### mediaview.go (1,041 lines — session 333, read in full: the fullscreen
media viewer; iteration 6, produced R18 + R19)
- **Structure**: viewerState (a.viewer, mu-guarded pointer, frame reads via
  snapshot) = account/chat/kind/anchor/items/index/loaded/deleting. Two
  entry points: openViewerFromMsg (tapped bubble → synthetic item shows
  instantly, filmstrip backfills async via GetSharedMedia in a goroutine
  with account+chat+kind staleness guard, mergeViewerItems splices the
  anchor if the kind filter excluded it) and openViewerAt (info-panel
  gallery, same async fill). closeViewer releases the h264 stream reader +
  pauses its own audio track immediately instead of waiting for the
  48-entry eviction (B-4/B-9 honored).
- **Layout chain** (renders in BOTH Root branches — app.go :65 separate,
  :104 main; overlays everything below toast/shortcuts): key layer (Esc/
  arrows), press-to-close backdrop, scrim, top bar (close | title+date |
  folder-reveal/save/share/PiP/delete), center (aspect-fit image or video
  poster + zoom-pan gestures + side chevrons + play badge), caption,
  video transport (zero-height unless a live player), filmstrip (52px
  thumbs, accent backing on current), live download progress row, delete
  confirmation card last (on top).
- **Zoom/pan model**: double-click toggles fit↔2.5x anchored at the cursor
  (panAfterZoom keeps the point stationary, 350ms/10dp double-click
  window), drag pans while zoomed, clampPanAxis keeps edges reachable and
  centers an axis smaller than the box. All gesture state per-App frame-
  loop fields. Pure helpers unit-tested.
- **Actions, all engine-backed** (§1.10): save = copy local / download-
  then-copy (setSaveOnDone); share → forward picker; play = in-app h264
  when downloaded, ranged-stream when not (slice 229), system-player
  fallback for audio-bearing containers; delete = confirm card → engine
  DeleteMessage with revoke=IsOutgoing; PiP pop-out keeps the decoder.
- **R18 (fixed this session)**: viewerShare held a.mu across openForward
  (which locks a.mu itself) → same-goroutine double-Lock = the Share
  button DEADLOCKED the whole window. Fixed by calling openForward outside
  the lock; RED-first watchdog test (TestViewerShareCompletes, 5s deadline
  — fails fast, does not park the runner; the R15 lesson).
- **R19 (fixed this session)**: mvBoxW/H + mvScaledW/H were PACKAGE vars —
  both windows' GUI loops write them every frame (viewer renders in both
  branches) → cross-window data race + one window's pan clamp reading the
  other's box. Moved to per-App frame-loop fields; clamps became methods
  (a.clampPan/a.clampPanNow). Compile-seam RED test
  (TestViewerBoxBookkeepingIsPerWindow, the F-90/R14 pattern).
- Lock discipline otherwise clean: GetSharedMedia/RequestDownload/
  DeleteMessage all in goroutines; a.mu only around short field sets;
  package caches with their OWN locks (h264Players mutex + snapshot-only
  access; mediaImgs get/store/start/fail) are cross-window-safe by design.
  Input tags (viewerKeyTag/viewerBgTag/viewerImgTag) are shared identities
  — fine, each window routes events on its own queue.
- Watch item (minor, P3): viewerProgress reads f.downloads per frame —
  fine; the filmstrip re-decodes thumbs through mediaImgs per paint (cache
  hits after first frame; pending-map dedupes in-flight decodes) — no
  action. The "file:"-keyed cache resets wholesale at 256 entries — a
  large album walked via filmstrip can thrash decodes (P4 churn family
  lens, unmeasured).

### profile.go (780 lines — session 333, read in full: the right info
panel; iteration 7, produced R22)
- **Structure**: AyuGram third pane for DM profiles (username/phone/bio,
  block/unblock, share contact as vCard, add contact) and group/channel
  member lists (role badges, member search), plus shared-media tabs
  (photos prefetched 60, others lazy), bot sections (description, command
  chips → composer insert, privacy link), profile music (capability-gated,
  §1.10), groups-in-common (async, slice 107), TTL row, notifications
  toggle with timed-mute picker.
- **Journey**: openPanel (locked flag+key set, loadPanel in a goroutine) →
  loadPanel: reads chat type/muted under lock, engine calls OUTSIDE
  (GetUserProfile/GetChatMembers/GetSharedMediaCounts/GetSharedMedia,
  bot cmds for bots, profile music when supported, common chats spawned),
  then one locked block writes all panel state + panelLoaded → invalidate.
  hdrPresence piggybacks on the fresh profile (slice 28). All actions
  (mute/block/add-contact) are engine calls in goroutines with toasts —
  clean; errors degrade to empty sections (loaded data honesty).
- **R22 (fixed this session)**: panelSwitches/panelSynced were PACKAGE
  maps — the panel renders in every window (layoutChatView →
  layoutInfoPanel in both Root branches), so two open panels = two GUI
  goroutines in one Go map = fatal runtime panic. Moved to a.wid
  (panelSwitch became a method, lazy-init for bare-App harnesses);
  compile-seam RED test pins per-window pool + one-shot bookkeeping.
  Every other keyed pool on a.wid was already per-App — this was the
  straggler; the settings*/sidebar* pools remain main-window-only by
  render path (P3 fold-in notes stand).
- **One-shot sync watch item (verified this session, P3 — same family as
  the settings toggles)**: the mute switch syncs from panelMuted ONCE per
  chat key (panelSynced[key]), and NO path ever clears it — not loadPanel
  (verified: its only callers are openPanel/block/add-contact/member
  dialogs), not any engine event. So a mute changed from the sidebar
  quick-action (or another device) leaves the panel toggle stale even
  after closing and REOPENING the panel for that chat; it re-syncs only
  at the 64-cap pool reset or process restart. Fix shape when touched:
  openPanel (or loadPanel) clears panelSynced for the opening chat.
- Streamer-mode masking honored on avatar/name/sub (isPanelSubCount lets
  member/online counts through).
