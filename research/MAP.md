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
| 2 | gui (state/mutex core — iteration 1 of N) | in progress (330) |

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

### Journeys mapped
boot → Start (subscribe+theme+lock) → go refresh*+ConnectAll → events → invalidate
→ frame reads state; open-chat (draft flush → media reset → state reset → load);
typing indicator lifecycle; desktop-notification gate on every incoming message.
