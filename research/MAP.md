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
