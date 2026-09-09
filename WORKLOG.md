# WORKLOG — Uniclient

Every agent session appends one entry at the bottom. Format:
`## <date> — <session title>`, then what was done, decided, and left over.
The most recent entry is the current state of the project.

---

## 2026-09-07 — Restore the build, make wasm real, prove the FFI works

Session goal (owner): "build up the project, fix/continue, work until it is
fully done, push to GitHub. The research files could be outdated or plain
hallucination so do your own research."

### What I found

- Repo state at session start: the Flutter frontend had been stripped
  (61945478), go.mod/go.sum and build scripts deleted (498f5d9e), leaving
  ~529k lines of Go (373k generated proto) that could not build at all.
  AGENTS.md (fa32b30b) described a *future* project ("Code: none yet") whose
  plan did not match the code that was actually present.
- Executed my own dependency research against the module proxy (per owner's
  instruction to distrust the research files): gotd/td v0.161.0, mautrix
  v0.30.0, pion v4 current line, protobuf v1.36.12, modernc sqlite v1.58.0.
  The research files' version claims turned out accurate (Go 1.27.1 is
  current stable per go.dev).

### What I did

1. **Restored the build.** Recreated go.mod via `go mod tidy` (module
   `uniclient`, Go 1.27); fixed two API-skew compile errors:
   pion/ice/v4 v4.4.2 moved stun/v3→v4 (same URI API), and gotd v0.152+
   replaced `SetChangeTone` with `InputAiComposeToneDefault{Tone}`.
   Discovered the **goolm requirement**: mautrix's default Olm is cgo;
   `-tags goolm` selects the pure-Go implementation. Build + vet green,
   including `CGO_ENABLED=0` (pure-Go claim verified, not assumed).
2. **Made the js/wasm target buildable** (it never had been — the old
   build script had it hard-failing as "NOT CURRENTLY BUILDABLE"). Added
   `go/wrtc` compat package: type/func aliases to pion/webrtc on native
   (zero-cost, single code path), compile-only stubs on js/wasm for the
   native-only media surface. Split bale/rubika websocket dials and the
   telegram DTLS/transceiver debug chains into `_js.go`/`_native.go`
   files following the repo's existing bale_calls_js.go pattern.
3. **Found and fixed a real architecture bug in the wasm bridge**: a
   synchronous JS→Go `bridgeCall` deadlocks ("all goroutines are asleep")
   as soon as the engine does blocking fs work (vault/config), because
   syscall/fs_js callbacks cannot fire while the JS stack is stuck inside
   the call. `bridgeCall` now returns a Promise and dispatches on its own
   goroutine. This is a wire-contract change: web hosts must `await`.
4. **Test suite** (none existed): utils crypto/vault (round-trips, wrong
   key, tamper, persistence, export/import), IRC parser (RFC2812+IRCv3
   tags/prefix/trailing, standard replies), Bale pbEncode/pbDecode wire
   contract (varints→int64, nested+`__raw_N` ambiguity, repeated fields,
   deterministic field order, the real handshake frame), and the bridge
   FFI round-trip driving Init/ListAccounts/AddAccount/RemoveAccount/
   Shutdown exactly as a host does, plus error paths. All green.
   The suite caught one real bug: `categorizeError` bucketed FLOOD_WAIT
   as `auth` (bogus re-login prompt); rate limiting now categorizes first.
5. **FFI smoke suites against the real artifacts** (not just compilation):
   `scripts/smoke/smoke_c.c` drives the c-shared .so through
   BridgeCallWithLen/BridgeFree — full lifecycle PASSED.
   `scripts/smoke/smoke_wasm.mjs` (+run_wasm.mjs) drives the .wasm under
   Node with the Node fs globals — same lifecycle PASSED, including vault
   persistence through Node's filesystem.
6. **Tooling**: Makefile (build/test/vet/lint/c-shared/wasm/cli/smoke),
   `scripts/build.sh` (linux/windows/darwin/android/web/cli targets),
   `.github/workflows/ci.yml` (native gate, race detector, platform matrix
   windows/darwin/linux × amd64/arm64 all CGO_ENABLED=0, wasm build +
   artifact upload, both smoke suites), README.md with the FFI contracts,
   and `go/cmd/cli` — a headless host binary for driving the engine from a
   terminal (verified live: add/list/status round-trip).

### Decisions

- Keep the bridge/cores architecture as-is (it is the actual code that
  exists); AGENTS.md's "internal/-first Gio rewrite" remains a future plan,
  not something to attempt in one session.
- `wrtc` shim instead of splitting call transports out of the 37k-line
  telegram.go: aliases preserve the single native code path (zero risk to
  native behavior) while making wasm compile; stubs return ErrUnsupported
  at runtime (media degrades, signaling works) — the repo's own established
  pattern from bale.
- bridgeCall on wasm is async (Promise) — unavoidable given single-threaded
  wasm + blocking fs; no frontend existed to break.
- CI runs `-race` on utils/cores/bridge only: gotd's tg package under -race
  exceeds small-runner RAM (verified locally on 4GB).

### Leftovers / next session

- Frontend: none exists. The AGENTS.md P0/P1 (Gio shell, loopback backend)
  or a web host on the wasm module are the natural next steps; the engine
  side of both contracts is now verified working.
- The research/*.md protocol notes for bale/rubika remain UNTESTED against
  live servers (geo-restricted) — unchanged from before.
- Proto regeneration tooling (scripts/gen_proto.sh + gen_bridge) was
  deleted in 498f5d9e and is NOT restored; the generated code is committed
  and builds, but regenerating requires rewriting those tools.
- ADR-007 (XMPP E2EE) and the other open decisions in AGENTS.md §15 still
  stand.

### Addendum (same session, later)

Live protocol verification against REAL servers (go/tests/, build tag
`live`, env-gated, now committed):

- **GitHub core vs api.github.com** with a real PAT: Authenticate verified
  via /user ("authenticated as DarkReaperBoy (Fallen Reaper)"), GetDialogs
  round-trip, background pollLoop — PASS.
- **IRC core vs irc.oftc.net:6697**: full TLS registration (NICK/USER →
  001), MOTD (35 lines), clean Logout — PASS.
- **Found+fixed by live testing**: IRC 465 (ERR_YOUREBANNED) stalled
  registration to the 30s timeout with a generic error. Libera bans
  datacenter IPs ("Your bot is not permitted"); the core now fails within
  seconds carrying the server's actual ban text, and the reconnect loop
  stops retrying permanent bans. Verified live against Libera (fails in
  ~6s with the real reason).

## Session 3 — CI repair + the desktop app (go/cmd/web)

### CI fix
- The race-detector job was the only red one: `CGO_ENABLED=0 go test -race`
  fails instantly — the race runtime on linux/amd64 requires cgo. Fixed to
  `CGO_ENABLED=1` (+30-min timeout). Verified green on GitHub runners
  (gotd/td's own CI compiles the same tg package under -race on
  ubuntu-latest, which is why it fits the 16GB runner but not the 4GB dev box).

### The desktop app: `uniclient-web` (go/cmd/web)
- Single binary: engine + local HTTP/WS API + embedded web UI (vanilla
  HTML/CSS/JS, go:embed, no frontend toolchain). Binds 127.0.0.1 only.
- Wires the engine through the bridge exactly like the FFI hosts
  (bridge.InitEngine), then drives the rich Go API directly.
- API: accounts (add/remove/connect/disconnect), the full interactive
  per-platform auth state machine (start/input/back/cancel + live state),
  chats (unified + per-account), messages (cache reads with live fallback),
  send (optimistic pending flow), mark-read, join-channel, QR rendering
  (rsc.io/qr, server-side PNG), /ws event stream (JSON EngineEvents).
- UI: account rail with status dots, chat list with unread badges, message
  bubbles (grouping, day dividers, reply quotes, media chips, status ticks),
  auth modal driven by the state machine (incl. Telegram QR login),
  new-chat/join modal, toasts. Verified in a real headless browser
  (agent-browser + VLM screenshot review): layout clean, no console errors.
- Second launch detects the running instance and just opens the browser.

### Live end-to-end verification (this session)
- **GitHub auth via the web API with the user's PAT**: full flow
  input→token→ready ("Fallen Reaper"), auto-reconnect after restart
  (vault-persisted), send pipeline: comment to issue #2 → msg_received +
  msg_status events over WS → read-back from the cache = the real comment.
- **IRC (irc.libera.chat)**: auth flow server→nick→(optional NickServ)→
  connected; joined #libera (1428 members) through the web API.
- Both OFTC (fresh autokill — test-connection spam) and Libera (pre-existing
  datacenter bot ban, dated 8/31) now k-line this dev box's IP; IRC live
  verification remains from Session 2 + the pre-ban checks above.

### Bugs found & fixed
- `engine.JoinChat` re-synced dialogs IMMEDIATELY after sending JOIN — the
  server's JOIN echo/353/366 arrive ~1s later, so the sync cached a list
  without the new channel and never re-synced. Now waits 3s.
- Server-origin IRC NOTICEs (auth banners, k-lines, "NOTICE AUTH") created
  junk DM chats named after the server host. They now route into a single
  "Server log" pseudo-chat (also surfaced in GetDialogs) — k-line text stays
  visible without polluting the chat list.
- Web events initially hooked `bridge.SetEventCallback` (protobuf
  BridgeEvent bytes) instead of the engine's JSON envelopes — browsers now
  get pure JSON via `eng.SetEventCallback(hub.broadcast)`.

### Tooling
- `scripts/smoke/smoke_web.sh`: headless web-host smoke (health, static UI,
  QR PNG magic, GitHub auth flow incl. a REAL bogus-token network
  round-trip, WS connect, second-launch dedupe, clean SIGINT shutdown).
  PASSED locally; wired into CI as its own job.
- `.github/workflows/release.yml`: tag `v*` → 6-platform matrix build
  (linux/windows/darwin × amd64/arm64) of uniclient-web + uniclient-cli
  with launchers (Start Uniclient.bat / uniclient.sh) + README, sha256s,
  auto-created GitHub Release.

### Leftovers / next session
- Telegram login UI flow is built (phone/OTP/2FA/QR) but unverified against
  a real phone account (needs the user's SIM). GitHub + IRC verified live.
- Avatars render as colored initials; media is read-only chips (no inline
  images / downloads yet).
- Bale/Rubika remain untested (geo-restricted), unchanged.

## Session 4 — v0.4.0: the native-Gio pivot (everything the owner demanded)

Session trigger: owner's angry review — web-app desktop is "retarded", two
binaries, JS/CSS in repo, CI on every commit, no Android, no scroll, no
folders, dead buttons, no indicators, bloated AGENTS.md, macOS/iOS not
wanted, binaries too big, not marked pre-release.

### Docs (done FIRST, per explicit instruction)
- **AGENTS.md rewritten from scratch**: 82KB of over-verified bloat → ~200
  lines of enforced owner requirements, verified platform truth table, GUI
  spec (folders/scroll/indicators/responsive), core status table, release
  policy (tag-only, prerelease), and a resumable checklist.
- README.md rewritten for end users (pre-release banner, platforms, demo
  mode, build/NixOS instructions). research/*.md stamped with "read with
  suspicion" headers; Flutter/bridge references marked historical.

### Architecture pivot (the repo is now pure Go)
- DELETED: go/bridge (35K generated dispatch), go/proto + root proto/
  (~420K generated), go/cmd/web (browser desktop app, the JS/CSS source),
  go/cmd/bridge (c-shared lib), go/cmd/cli (second binary), ci.yml,
  scripts/smoke/*.mjs|*.c. GitHub language stats will show Go only.
- NEW go/bootstrap: engine.Init + core factory + session migration (extracted
  from the bridge; the GUI calls the engine in-process, no serialization).
- NEW go/gui: full Gio Material-Design client — theme (AyuGram dark
  palette), adaptive sidebar+chat panes (phone layout below ~680dp),
  folder tabs (All/Unread/People/Groups/Channels), scrolling chat list with
  scrollbars, message list (bubbles, day dividers, status ticks, grouping),
  composer (Enter=send), account bar with connection dots + account menu
  (switch/remove), backend picker grid, auth state machine UI (choose/
  input/OTP/2FA/QR + back/cancel), voice mode tab, toasts, loaders on all
  async ops.
- NEW go/cores/demo.go + stub.go: credential-free demo backend (6 chats,
  folders, echo bot, typing simulation, live bursts). Registered in the
  engine as a real platform — the GUI is fully evaluable with zero accounts.
- NEW go/cmd/uniclient: THE single binary (flag -demo for instant demo).

### Bugs found & fixed along the way
- gio v0.10.2's material.NewTheme leaves the Shaper empty → NO text
  rendered. Fixed: th.Shaper = text.NewShaper(WithCollection(gofont)).
- All my palette colors lacked alpha (NRGBA A=0 = invisible): the entire UI
  rendered as default-blue rectangles. Fixed in rgb().
- engine.StartAuth: credential-free platforms (demo) now finalize
  immediately (save creds + connect + sync), mirroring auto-completing flows.
- wlynxg/anet v0.0.5 //go:linkname net.zoneCache breaks Go 1.23+ android
  LINKING (pion→transport→anet pulled in by webrtc). Fixed via patched fork
  go/third_party/anet + replace directive. APK builds again.
- Verified MYSELF (owner: don't trust old research): CGO_ENABLED=0 on
  Linux is impossible with gio (X11 cgo, EGL/Vulkan cgo) — the old
  AGENTS.md was right about that; Windows + WASM pure-Go confirmed.

### Runtime verification (not just compile)
- Headless Xvfb + software-EGL: app boots, engine+demo connect, window
  renders. VLM screenshot review read the ACTUAL UI: account bar ("Demo
  User/connected/+"), Chats/Voice tabs, search, folder tabs, 6 chat rows
  with unread badges, live incoming message + "typing…" indicator while
  watching, chat view with bubbles/timestamps/day divider, composer.
  Click-to-open-chat verified via synthetic XTEST events.
- Bootstrap end-to-end test (committed): add→auth→connect→folders→send→
  echo→events→cache→persistence→restart-reconnect. Green.

### Release pipeline
- release.yml: tag/dispatch ONLY. Jobs: test (vet+gofmt+tests), linux
  amd64+arm64 (native arm64 runner), windows (pure Go), android arm64 APK
  (SDK+NDK+gogio), web wasm → gh-pages push (index.html+wasm_exec.js
  generated IN CI — main stays pure Go). All binaries -s -w + UPX
  (~45MB→~12MB). softprops release, prerelease: true.
- flake.yml: dispatch job that computes the nix vendorHash and commits it.
- flake.nix: app + dev shell for NixOS (first-class, owner's platform).
- Makefile: build/run/test/lint/wasm/apk/windows/compress/serve.
- scripts: build.sh (release builds), web.sh (local wasm serving).

### Built & verified locally
- linux/amd64 12.1MB (UPX), windows/amd64 12.1MB, wasm 57.9MB,
  android arm64 APK 17.5MB. Tests+vet+gofmt green.

### Leftovers / next session
- CI run of the full release pipeline (tag v0.4.0) — watch for surprises.
- flake vendorHash needs the one-shot flake.yml dispatch to pin.
- mumble/teamspeak rewrite (tests-first, docker-based) — hidden until then.
- Telegram 1:1 AyuGram features (real folder sync, ghost mode, QR verify).
- Voice mode wiring to wrtc; media downloads/inline images; XMPP E2EE ADR.

## 2026-09-08 — Session 5: the placeholder purge (demo deleted, honest voice, verify pipeline)

Owner's order: "ok now based on the agents.md, work on it." — executed per
the AGENTS.md §2 workflow (research → think → rate → plan → tests → code →
verify), starting from the topmost unchecked checklist items.

### Ratings (§2 step 3, recorded as required)
- Demo backend: **1/10** — shipped fabricated chats/users to the owner's
  GUI (§1.10 violation). Verdict: complete deletion, nothing salvaged.
- Voice tab: **5/10** — data was real (HasActiveCall) but the copy promised
  future work ("being rebuilt — see AGENTS.md") and Join was a dead stub
  button. Verdict: strip the promises and the dead button, keep honest
  rows + empty state.
- Engine auth machine: **7/10** — solid per-platform state machine; demo
  was special-cased in 3 places (initialAuthState, advanceAuth, the
  credential-free StartAuth shortcut). All excised; the shortcut was dead
  code once demo was gone.
- Old bootstrap test: **3/10** — depended on the banned fake platform and
  contained a no-op placeholder test. Both replaced.

### What changed
- DELETED: go/cores/demo.go (315 lines of fake world), the `-demo` flag,
  the welcome-screen "Try the demo" CTA, the Demo picker card, the
  bootstrap factory row, and all engine auth demo special-cases.
- bootstrap: `SupportedPlatforms()` is now the single source of truth for
  real backends; saved accounts with unsupported platforms are PURGED at
  boot (the owner's vaulted demo row vanishes instead of rotting as a dead
  error row).
- gui/voice: honest state only — "being rebuilt" copy and the dead Join
  button removed; rows are informational until real call UI lands on wrtc.
- Makefile: `make run` no longer passes -demo.
- NEW `.github/workflows/verify.yml`: dispatch-only manual verification
  runner (gofmt/vet/tests + windows/wasm cross-builds + Xvfb GUI smoke
  with screenshot artifacts). Born out of necessity: this 4GB sandbox
  OOM-kills gotd/td's tg compile (3.6GB RSS, every GC recipe tried), so
  CI's 16GB runners are the build path here. Documented in AGENTS.md §5.

### Tests (written FIRST, red against the pre-deletion code)
- TestStartAuthRejectsUnknownPlatforms — "demo" must be refused.
- TestUnsupportedAccountsPurgedAtBoot — stale demo rows removed at boot.
- TestFactoryConstructsEverySupportedPlatform — all 10 real backends build.
- gui TestPlatformsAreRealBackends — picker ⊆ factory, no placeholder IDs.
- cores TestStubCoreIsHonest — stub never fakes success.
- Engine e2e rewritten on a TEST-LOCAL fake core (never shipped) via the
  real saved-account boot path: SaveCredentials → ConnectAccount → sync →
  send → echo events → cache → restart → ConnectAllAccounts reconnect.

### Verification (real, not "it compiles")
- GitHub Actions (dispatch, main): runs 34151360457, 34152145890,
  34152662552 — test/vet/gofmt GREEN, windows+wasm GREEN, GUI smoke GREEN.
- VLM review of CI screenshots: welcome screen shows exactly ONE CTA
  ("Add an account"), NO demo mention; picker grid = 8 real cards
  (Telegram, IRC, Matrix, GitHub, XMPP, Delta Chat, Bale, Rubika), NO
  Demo card; clicking a card opens the REAL auth state machine (Delta
  Chat email form, Continue/Back/Cancel, account listed offline).
- Purge test proves the owner's existing demo account self-destructs on
  next launch.

### Leftovers / next session
- Telegram 1:1 AyuGram features (folder sync, ghost mode, QR verification).
- mumble/teamspeak rewrite (tests-first, dockerized servers).
- Live-verify or replace xmpp / bale / rubika / deltachat.
- Real call UI on wrtc (voice rows informational until then).

---

## 2026-09-08 — AyuGram 1:1 parity program, first slice: message actions

Session goal (owner): "1:1 ui, and same functionality. 1:1 uniclient's gui
source code against ayugram (modify agents.md first before anything to
include this). i want every aspect of it cloned and the functionality
doesn't exist on the cores then update em or something. i want all of the
backends use the same frontend and be like just diff accounts and such. i
EXACT telegram functionality, like 1:1 for telegram core-gui at the very
least and other cores may follow."

### What I did

0. **AGENTS.md first (owner's explicit order)** — §1.11 rewritten as the
   full mandate: UI *and* functionality 1:1, every aspect, source-level
   feature-by-feature walk of AyuGramDesktop; GUI is never trimmed to fit
   cores — cores grow to fit the GUI; one frontend for every backend (a
   backend is just an account); Telegram = mandatory exact 1:1, others
   follow. §7 got the parity doctrine + one-frontend rule. §11 checklist
   got the parity-program item. Pushed as 03e496b3.
1. **Research (§2 step 1)** — full AyuGramDesktop source-tree enumeration
   (shallow clone, dev @ db3b989) cross-referenced with our gui/engine/
   cores → `research/ayugram_parity.md`: 201 concrete rows, statuses
   PRESENT 12 / PARTIAL 16 / MISSING 48 / CORE-ONLY 125, priorities
   P0 36 / P1 57 / P2 62 / P3 43, plus a ranked top-20 gap list. The huge
   finding: 125 features already exist in engine/cores and the GUI never
   shows them — the program is mostly GUI surfacing, not protocol work.
2. **Rating (§2 step 3, required)** — GUI architecture 7/10 (snapshot/
   frame pattern, event pump, async engine dispatch: keep + extend);
   GUI surface coverage 2/10 vs AyuGram (extension, not replacement —
   the engine/telegram core rated 8/10, 1323 methods live); reactions
   persistence missing end-to-end (core had data, cache dropped it) →
   this session closes that seam.
3. **Best plan (§2 step 4)** — deliver the top P0 cluster as one coherent
   "message-action layer": context menu, reply/edit composer modes,
   reply-quote + forward headers in bubbles, reactions strip with
   persistence, scroll-up history pagination, forward picker. All
   engine methods already existed except reaction persistence.

### Shipped (message-action layer)

- `gui/menu.go` (NEW): right-click message context menu anchored at the
  cursor (pane-level `event.Op` + `pointer.Filter` hit-testing against
  per-frame row bounds; press-outside dismisses, never blocks the chat),
  quick-reaction row (server list + TG default fallback), action rows
  gated by `actionsFor` (real message flags + backend Capabilities), and
  the forward picker (layout-swap chat list, same account).
- `gui/actions.go` (NEW) + `gui/actions_test.go` (tests first): the
  action-gating model (reply/edit/copy/forward/delete/pin/react rules —
  service messages, pending sends, NoForwards, CapReactions) and the
  composerMode reply/edit state machine.
- `gui/chat.go`: bubbles now render forwarded-from header, reply quote
  block, and the reactions strip (own reaction highlighted, click
  toggles); composer grows the reply/edit chip (Ayu input-field header)
  and routes send through replyToID/EditMessage; scroll-up loads older
  history (loadOlder + merge that preserves loaded pages across
  refreshes — the previously dead `loadedOlder` path).
- `gui/state.go`: message-action state (modes, menu, forward, cached
  caps/reaction list, older-page bookkeeping) wired into snapshot/frame.
- `gui/theme.go`: embedded Noto Emoji (monochrome, SIL OFL 1.1, license
  in gui/assets/OFL.txt) registered as a shaper fallback — emoji in
  messages and reaction pills render instead of tofu on every platform.
- Engine + core reactions pipeline (the "cores grow to fit the GUI" case):
  migration v44 `messages.reactions_json`; every cache write/read carries
  reactions; NEW `cores.UpdateReactions` fired by the telegram core from
  `tg.UpdateMessageReactions` with the full counts; engine updates the
  cache row + emits EventMsgEdited; own reaction toggles update the cache
  optimistically after the pending react succeeds (tests-first:
  `engine/reactions_test.go` locks the toggle semantics). Telegram core
  compiles against gotd v0.161.0 APIs verified from source (MsgID int,
  MessageReactions struct, GetResults).

### Verification status

- gofmt clean (all files; the editor's space-indent roundtrip was
  normalized back to tabs — diff reviewed, only intended changes remain).
- Local go build of the full graph is impossible on this 4GB sandbox
  (gotd tg compile OOM-kills, same as last session) → CI verify.yml is
  the gate; dispatched after push (run number in the next entry).
- Local type-level risk was minimized by verifying every new gio v0.10.2
  and gotd v0.161.0 API against the actual dependency sources.

### Leftovers / next session (in priority order)

- CI verify run green for this slice (watch it, fix anything red).
- Media bubbles + download progress (top-20 gap #3) — engine pipeline
  already emits EventDownloadProgress.
- Settings screen (gap #4) + right info panel (gap #5).
- Attach menu + uploads + voice recording (gap #6).
- Server folder sync + folder CRUD (gap #9) — replace hardcoded tabs.
- Real image avatars (gap #10); ghost-mode drawer + preferences (gap #11).
- Custom-emoji reaction pills (need document fetch) and the full tabbed
  reaction/emoji picker; delete for-me-vs-all dialog; selection mode.
- Touch long-press to open the context menu on Android/narrow layout
  (right-click only, desktop, for now).

---

## 2026-09-08 — CI verification of the message-action slice

- First verify dispatch (run 34167190069 on 9adce071): vet caught 5 real
  compile errors in the new gui code — previewText redeclared (sidebar.go
  already had one; mine renamed to quotePreview), image.Rect used as a type
  (→ image.Rectangle), clipboard.WriteCmd is the stream API in gio v0.10.2
  (Type + io.NopCloser), ForwardMessage arity, and widget.Editor has no
  Focus method (→ key.FocusCmd from the menu action). All fixed against
  the actual dependency sources; 19f64362.
- Second verify dispatch (run 34167736025 on 19f64362): **all green** —
  Test & vet & gofmt ✓ (new tests gui/actions_test.go +
  engine/reactions_test.go pass), windows + wasm cross-builds ✓, Xvfb GUI
  smoke + screenshots ✓ (app boots with the emoji font + new layout).

## 2026-09-08 — AyuGram parity program, slice 2: media bubbles + downloads

Scope: research/ayugram_parity.md §5 media rows (top-20 gap #3) — the engine
media pipeline existed (queue, priorities, LRU eviction, events) but the GUI
rendered nothing for any media message.

- `gui/media.go` (new): per-type bubbles — photo (inline stripped-thumb JPEG
  → auto-download → full-file swap, aspect-fit rounded, linear filter),
  video + round video-note (thumb + centered play badge + m:ss pill, ellipse
  crop for notes), voice (play badge + duration/size), audio (title row),
  file (name/size + dims). Whole-bubble tap = download / cancel / reveal
  (AyuGram semantics). Live byte counter + thin progress bar under
  downloading bubbles, "tap to retry" on failure. Decoding is off-frame with
  a bounded image cache; frames only look up.
- `gui/state.go`: download event plumbing — EventDownloadProgress/Complete/
  Failed handlers, copy-on-write message patch on complete (MediaLocalPath),
  per-frame snapshot of the live download map, per-chat auto-download
  ledger (photos/GIFs prefetch like AyuGram defaults), progress animation
  invalidation in the message list.
- `engine`: EventDownloadFailed + DownloadFailedEvent (media.go now emits it
  on error); MediaPreviewLabel("Photo"/"Voice message"/…) used by reply
  quotes (populateReplyPreviews + cacheMessage now resolve the target's
  media kind when the text is empty) and by chat-list rows (gui sidebar
  previewText — parity row "Row: media preview labels").
- Tests first: gui/media_test.go (fmtBytes/fmtDur/fitDims/dlFraction/
  block-kind gating), engine/media_label_test.go (label mapping).

Known follow-ups (next slices): media viewer overlay (§12), voice/audio
playback, album grouping (GroupedID), stickers (webp decode), sidebar thumbs.

## 2026-09-08 — AyuGram parity program, slice 3: settings screen + theme

- Verified locally this time: the 4GB box CAN compile the full graph with
  GOMEMLIMIT=3000MiB GOGC=15 -p=1 (downloaded Go 1.27.0 toolchain; gotd
  compiles fine) — full `go vet ./...` (windows target) + `go test ./engine
  ./utils` run green locally before push, no more CI-blind commits.
- fix: slice-2 commit's state.go had hand-misaligned struct fields →
  `gofmt -w` normalized (the CI gofmt gate caught it — run 34192076823).
- `gui/settings.go` (new): the AyuGram settings shell — left rail of 7
  sections (Main / Notifications / Privacy & Security / Data & Storage /
  Appearance / Ayu / About) with content pages; gear entry added to the
  sidebar account bar; narrow layouts collapse the rail to a chip row.
  Every toggle/row is a real engine call: config booleans
  (UpdateConfigFromBridge), per-account contact-signup + calls-disabled
  toggles, blocked users + active sessions lists, real cache accounting with
  per-tag and total clears, ghost flags (9 global + per-account overrides
  with reset), theme.
- `gui/theme.go`: light palette + UI.applyTheme; the persisted theme applies
  at boot before the first frame.
- `gui/state.go`: settings state surface (open/section, cfg snapshot, async
  page loaders under mu, frame copies).
- Tests first: gui/settings_test.go (section list, cache-tag labels,
  ConfigChanges/GhostFlags field mapping, theme name).

## 2026-09-08 — AyuGram parity program, slice 4: right info panel

- `gui/profile.go` (new): the AyuGram third pane — desktop slides in a 320dp
  column beside the chat (ⓘ toggle in the chat header), narrow replaces the
  pane with a back header. Sections: per-chat notifications switch
  (engine.MuteChat), DM profile (GetUserProfile → username/phone/bio rows,
  block/unblock + add-to-contacts actions), group/channel member list
  (GetChatMembers, 200, role badges w/ owner/admin/restricted/banned colors,
  custom ranks), shared-media counts (GetSharedMediaCounts) + a recent-photos
  grid reusing the media thumbnail cache (GetSharedMedia "image").
- `gui/chat.go`: header ⓘ button, chat column extracted to chatPaneColumn,
  panel routing; `gui/state.go`: panel state + async loadPanel; tests:
  gui/profile_test.go (section gating, role badges, last-seen labels).
- Local gate before push: gofmt clean, full windows-target vet clean.

## 2026-09-08 — AyuGram parity program, slice 5: attach menu + uploads

- `gui/attach.go` (new): 📎 in the composer opens an attach popup (Photo or
  Video / File); file picking through the OS dialog via gioui.org/x/explorer
  (new dep, v0.10.2 — matches gio v0.10.2; works on Linux portal / Windows /
  macOS / Android SAF / browser). Desktop picks resolve to real paths,
  streamed picks spool to temp files (cleaned up after upload). Single file →
  engine.UploadFileEx; multiple → new engine.SendMediaAlbumFromPaths (album
  when the core supports cores.MediaAlbumSender, sequential fallback). The
  composer text at attach time becomes the caption; the composer clears.
- `gui/state.go`: explorer wiring (created once per window, ListenEvents
  forwarded from main.go's event loop), attach-menu state; `gui/chat.go`:
  composer attach button + popup overlay; `gui/menu.go`: outside-press
  dismissal.
- fix (from CI runs 34194751486/34195237803): gui itoa(0) returned "" —
  TestFmtDur caught it; fixed to return "0" (also correct for member counts).
- Verification upgrade: the full gui test suite now runs locally under
  node+wasm (go test -c GOOS=js + lib/wasm executor) — all 20+ gui tests
  green locally before push; windows vet + wasm build clean.

## 2026-09-08 — AyuGram parity program, slice 6: server folder tabs

- `gui/folders.go` (new): the tab row now renders the scoped account's REAL
  server folders (engine.GetFolders) with Telegram dialog-filter matching —
  explicit ChatIDs win, ExcludeChatIDs/Read/Muted/Archived rules apply, then
  Contacts/NonContacts/Groups/Channels/Bots flag matches; emoticons render
  in tab names. Smart fallback tabs (People/Groups/Channels) when unified or
  the core lacks folders (new engine.FoldersSupported). "+" tab opens a
  create-folder dialog (engine.CreateFolder; name-only first pass — the
  full folder editor with chat picker is a follow-up).
- `gui/sidebar.go`: layoutFolders + filterChats rewritten over the dynamic
  tab model; account switching reloads the scoped folders; folder index
  resets on scope change. Old hardcoded folderNames/folderMatches removed.
- Folder loads also refresh on account/conn events; folder state in
  state.go/frame with async refreshFolders.
- Tests: gui/folders_test.go (tab building/scoping, tab matching, folder
  rule precedence) — full gui + engine suites green locally (wasm runner),
  windows vet clean.

## 2026-09-08 — AyuGram parity program, slice 7: real image avatars

- `gui/avatar.go` (new): real userpics render everywhere — chat rows, chat
  header, account bar, settings account cards, info-panel header + member
  rows (b64 thumbs), voice rows. Sources: ChatInfo.AvatarPath (the engine
  avatar pipeline downloads jpgs on sync and emits chat updates) and
  MemberInfo.AvatarB64; decoding reuses the shared media image cache (async
  decode, frame-only lookup). Circle cover-crop via RGBA.SubImage center
  square + ellipse clip + affine scale; letter fallback stays for chats
  without photos / wasm (no local FS).
- Tests: gui/avatar_test.go (square-crop math). Full gui suite green locally
  (wasm runner); windows vet + gofmt clean.

## 2026-09-08 — AyuGram parity program, slice 8: chat-row context menu

- `gui/chatmenu.go` (new): right-click a chat row in the sidebar for the
  AyuGram chat menu — mute for 1 hour / 8 hours / forever / unmute, pin/unpin,
  mark read/unread, archive/unarchive, delete chat. Every row dispatches a
  real engine call (MuteChat with durations, PinChat, MarkChatRead/Unread,
  ArchiveChat, DeleteChat); errors surface as toasts, successes refresh via
  the engine's chat-update events.
- Hit-testing mirrors the chat pane: the sidebar registers a pane-wide press
  area (new sidebarPaneTag), per-frame chat-row bounds + visible-slice
  bookkeeping in the sidebar layout, cursor-anchored clamped menu, outside
  press dismisses.
- `gui/state.go`: chatMenu state (open target, rect, row bounds). Tests:
  gui/chatmenu_test.go (flag-driven item sets). Full suite green locally.

## 2026-09-08 — AyuGram parity program, slice 9: fullscreen media viewer

- `gui/mediaview.go` (new): the AyuGram mediaview overlay (§12) — near-black
  fullscreen scrim; top bar with chat title + date and save/share/delete;
  aspect-fit image (or video poster + play badge) with double-click zoom
  (1x↔2.5x anchored at the cursor) + drag pan with edge clamping; caption
  (sender + text) under the image; thumbnail filmstrip over the chat's real
  shared media (engine.GetSharedMedia) with the current item highlighted;
  live download progress bar fed by the engine media pipeline; Escape/arrows
  keyboard routing (composer focus cleared while viewing so keys reach the
  viewer); backdrop click closes. Share hands the message to the existing
  forward picker; Delete shows a confirm dialog and dispatches
  engine.DeleteMessage with revoke=outgoing; Save runs RequestDownload when
  the file is missing. Photos/GIFs/videos with a complete download now open
  the viewer on tap (media.go actMedia), and the info-panel recent-photos
  grid opens it at the tapped photo.
- Engine: GetSharedMedia now joins the message row's sender_name,
  content_text and is_outgoing into SharedMediaItem (viewer header, caption,
  delete-revoke decision).
- Tests: gui/mediaview_test.go (step clamp, zoom toggle, pan clamp/zoom
  math, item find/merge/synth, kind mapping). Full gui suite green locally
  under node+wasm; engine+utils native green; windows + wasm builds clean;
  gofmt + vet clean.

## 2026-09-08 — AyuGram parity program, slice 10: emoji picker + release fix

- `gui/emoji.go` (new): the 😊 composer button opens a category-tabbed emoji
  panel above the input (AyuGram composer helper). 9 categories (~450
  emoji), tab strip with active highlight, 8-column grid, taps insert at the
  caret via widget.Editor.Insert and keep the panel open for multi-insert,
  backspace key (Editor.Delete), outside-press dismissal, mutually exclusive
  with the attach popup. Emoji render through the Noto Emoji fallback face
  (no new deps). Sticker/GIF tabs + emoji search = follow-up (engine sticker
  set fetch / GetEmojiKeywords).
- `gui/chat.go`: 😊 button beside 📎 + panel overlay; `gui/state.go`:
  emojiOpen/emojiTab state + rect bookkeeping; `gui/menu.go`: dismissal.
- Fix: the owner's manual "Release" dispatch (34199258328) failed at
  "Create pre-release — GitHub Releases requires a tag" (dispatches run on a
  branch). release.yml now derives a `dev-<sha>` tag for branch dispatches;
  tag pushes are unchanged.
- Tests: gui/emoji_test.go (row math, category clamp, dataset sanity incl.
  duplicate scan, row padding). Full gui suite green under node+wasm;
  engine/utils green; gofmt + vet clean.

## 2026-09-08 — AyuGram parity program, slice 11: chat chrome

- `gui/chrome.go` (new): the AyuGram chat-view chrome — pinned-message bar
  under the header (pin glyph, "Pinned message(s)" title, preview line w/
  media labels, cycle chevron for multiples; tap jumps to the message);
  "Unread messages" separator (accent pill on a hairline, anchored to the
  boundary MESSAGE id captured at open — before the read receipt fires — so
  it survives window reloads and jumps, AyuGram behavior); "No messages
  here yet…" empty-chat intro; jumpToMessage (in-window → exact row scroll
  via the shared row model; out-of-window → engine GetMessages
  beforeMs/afterMs window reload + scroll).
- `gui/chat.go`: messageList row model extracted to the shared
  buildChatRows (dividers + separator + messages) so hit-testing, bounds
  and jumps stay consistent; pinned bar slot under the header (listTop
  accounts for it).
- `gui/state.go`: unreadAtOpen/unreadSepMsgID + pinned state; openChat
  captures the unread count pre-receipt, loads pins, closes the emoji panel
  and any open media viewer.
- Tests: gui/chrome_test.go (separator index math, row model w/ anchored
  separator, rowIndexOf consistency, pinned preview/title). Full suite
  green under node+wasm; windows + wasm builds clean.

## 2026-09-08 — AyuGram parity program, slice 12: media albums

- `gui/album.go` (new): consecutive messages sharing a GroupedID render as
  ONE bubble with Telegram's album grids — 1 full, 2 columns, 3
  tall+stacked, 4+ 2×2 with a "+N" overflow counter on the last cell. Cells
  cover-crop (new drawImageCover: aspect-fill + center-crop), videos carry
  a play glyph, in-progress downloads get a veil, and each cell taps
  straight into the media pipeline (download / cancel / open the fullscreen
  viewer). The album bubble carries the group's caption (the member with
  text), first-member reactions + meta + outgoing styling.
- `gui/chrome.go`: buildChatRows collapses same-GroupedID media into album
  rows (isAlbumMedia gate: image/GIF/video only); rowIndexOf resolves album
  members to their row so pinned-bar jumps land on albums.
- Tests: gui/album_test.go (grid geometry per pattern incl. rounding, overflow
  count, media gating, grouping + member jump, caption selection). Full gui
  suite green under node+wasm; engine green; windows + wasm builds clean.

## 2026-09-08 — AyuGram parity program, slice 13: full folder editor

- `gui/folders.go`: the folder dialog is now the full AyuGram filter editor —
  name, emoticon pick row, Contacts/Non-contacts/Groups/Channels/Bots +
  Exclude-muted/read/archived switches, and the account's chat picker where
  tapping cycles none → include (✓) → exclude (✕) → none. Create and Edit
  share the dialog: engine.CreateFolder / EditFolder with CreateFolderOpts
  (flags + exclude lists + emoticon; ordered chat IDs from the sidebar
  order); Delete (engine.DeleteFolder) when editing.
- Entry points: the "+" tab still creates; right-clicking a REAL server
  folder tab opens the editor prefilled from engine.FolderInfo (tab bounds
  recorded in layoutFolders; sidebar press routing checks tabs before chat
  rows).
- Tests: gui/folderdlg_test.go (picker cycle state machine, flag mapping,
  switch sync, edit prefill incl. name editor). Full suite green under
  node+wasm; windows + wasm builds clean.

## 2026-09-08 — AyuGram parity program, slice 14: message selection mode

- `gui/select.go` (new): AyuGram multi-select — "Select" in the message
  context menu starts the mode with that message marked; taps on rows (pane
  press hit-testing) and on media bubbles toggle check circles; a header
  action bar replaces the pinned bar ("N selected" + Forward / Copy /
  Delete / ✕, Escape cancels). Forward feeds the batch into the forward
  picker (a.fwd is now []CachedMessage) which dispatches
  engine.ForwardMessages; Delete runs engine.DeleteMessage per message with
  revoke=outgoing; Copy joins texts onto the clipboard.
- `gui/menu.go`: Select action; forward dialog handles 1..N sources with a
  count title. `gui/chat.go`: selection circle rows + bar routing.
  `gui/state.go`: selOn/sel state; openChat resets it.
- Tests: gui/select_test.go (toggle state machine, menu auto-close,
  selectedMessages windowing, batch forward build). Full suite green under
  node+wasm; windows + wasm builds clean; engine green.

## 2026-09-08 — AyuGram parity program, slice 15: chat-header "..." menu

- `gui/headermenu.go` (new): the AyuGram peer menu on a ⋮ button in the chat
  header — mute/unmute (MuteChat), View profile (opens the info panel),
  clear history (ClearHistory w/ confirm card), block/unblock for DMs
  (BlockUser/UnblockUser; state-aware label when the panel profile is
  loaded), leave for groups/channels (LeaveChat) and delete for DMs
  (DeleteChat), each destructive action behind a confirm card; leave/delete
  close the chat and refresh the list. Outside-press dismissal via the pane
  press routing; menu anchored under the ⋮, clamped.
- Tests: gui/headermenu_test.go (DM/group/channel item sets, mute label
  swap, blocked-state label, confirm copy). Full suite green under
  node+wasm; windows + wasm builds clean.

## 2026-09-08 — AyuGram parity program, slice 16: global search

- `gui/search.go` (new): while the sidebar search has ≥2 runes, the chat
  list grows a search row model — [Chats local matches] [Messages:
  cross-account FTS5 hits (engine.SearchMessages, 30)] [Global results:
  per-account server chats (engine.SearchGlobalChats, 8/account, scoped by
  the account filter)]. Message rows show chat/sender + snippet + time and
  open the chat, jumping to the message (jumpToMessageAt now takes a
  timestamp fallback so out-of-window search targets reload a window around
  themselves — same path the pinned bar uses). Global rows open through the
  engine's cache-then-core fallback. Stale async runs are dropped by query
  comparison; short queries clear synchronously.
- `gui/sidebar.go`: searchField ChangeEvents trigger onSearchChanged;
  layoutChatList renders the mixed row model (chat-row bounds stay keyed to
  visible chats for the context menu).
- Tests: gui/search_test.go (row model shape, global scope filter, short
  query clears). Full suite green under node+wasm; windows + wasm builds
  clean.

---
### 2026-09-08 (session 4) — slices 17–22 (message-actions follow-ups + shell surfaces)

- **16 fix (811a1c88)**: gofmt on gui/search_test.go; CI green (34220054302)
- **17 (a0268178)**: hamburger drawer (☰ in account bar) — account switch, contacts, calls→voice, night switch, ghost master + ⚙ prefs, new group/channel (CreateGroup/CreateChannel/CreateMegagroup + pending-open GUI-loop hop), settings; contacts screen (GetContacts, search, jump-to-DM, AddContact dialog); CI green
- **18 (f2661061)**: in-chat search — header 🔍, live scoped FTS, N/M counter, ▲▼ + click jump; CI green (34221720448)
- **19 (d7a1c6f8)**: delete dialog w/ for-all revoke (single + bulk), interactive report flow (choose_option → add_comment → reported), JOIN bar for not-joined channel previews; CI green (34222198035)
- **20 (00e51735)**: drafts (restore/flush/clear + red row preview) + scheduled send (⏰ dialog: presets + custom date/time → SendMessage scheduleDate; scheduled meta); CI green (34222830611)
- **21 (d9d53c24)**: scheduled manager (header ⋮ → panel w/ send-now/reschedule/delete; new engine.DeleteScheduledMessages) + unread-story rings on avatars; CI in flight
- **22 (0750ff39)**: desktop notifications — Linux DBus org.freedesktop.Notifications, config/mute/throttle gating, pure helpers tested; CI dispatched
- Toolchain notes: wasm test runner is `/tmp/go/lib/wasm/wasm_exec_node.js` (go_js_wasm_exec no longer node-runnable); gofmt fix flow: CI gofmt gate → local `gofmt -w` → gates → push

---
### 2026-09-08 (session 4, cont.) — slices 23–25

- **23 (fe98f0e1)**: forward options (hide sender/captions → dropAuthor/dropCaptions), drawer Saved messages → self chat, composer 🔕 sticky per-message silent → SendMessage silent; CI green (34223944370)
- **24 (87996f21)**: invite-link join (t.me/+hash & joinchat forms in search → CheckChatInvite preview → confirm → ImportChatInvite); chat rows render REAL userpics + unread-story rings + 34dp media thumbs (LastMsgThumbB64); fixed slice-21 snapshot bug (schedPanel/schedMsgs/schedLoad never copied → panel never rendered); CI in flight
- **25 (6cd60ba1)**: new-group member picker (async contacts + toggles → CreateGroup members), reply quotes clickable → jumpToMessageAt; CI dispatched

---
### 2026-09-08 (session 4, final) — slice 26 + all CI green

- **26 (1c9257a5)**: profile info-row copy (username/phone/bio → clipboard + toast), in-chat search from-user filter (👤 sender picker → SearchMessages senderID); CI 34225265665 GREEN
- Session 4 total: 10 slices (17–26) + slice-16 gofmt fix + slice-21 snapshot bugfix, every dispatch green

---
Task ID: parity-slices-27-32
Agent: main (Super Z)
Task: Continue the AyuGram 1:1 parity program endlessly (slices 27–32)

Work Log:
- Local toolchain restored (Go 1.27 at /home/z/go; -tags goolm + GOMEMLIMIT recipe for gotd) — all local gates green per slice: gofmt, windows vet, gui suite under node+wasm, engine/utils tests, windows+wasm builds
- Slice 27: add-to-folder from chat-row context menu (folder picker w/ emoticons, account-scoped via frame.foldersFor; engine AddChatToFolder) — CI 34239396476 GREEN
- Slice 28: peer header status (online/last-seen via GetUserProfile + EventUserStatus, exact-time formatting) + verified/premium/scam badges — CI 34240718430 GREEN (w/ 29)
- Slice 29: row pin (custom hand-encoded IconVG pushpin) + mute icons, unread-mark dot, service-message centered pills
- Slice 30: floating next-unread ⬇ button (circular wrap search, scrolls + opens)
- Slice 31: login-code relay banner + auto-fill (EventLoginCode, 10-min window)
- Slice 32: rich text rendering — entity parsing (UTF-16 offsets, overlap merge), styled word-flow layouter, spoiler hide/reveal; engine content_rich already round-trips entities
- Matrix rows updated: 42, 57, 60, 66, 69, 79, 80, 90, 94, 125

Stage Summary:
- 32 parity slices landed; CI green through slice 29; verify run dispatched for 30–32 (HEAD c521a438)
- Next candidates: compose-side markdown formatting, link opening, copy message link (engine t.me), Ayu local "hide message", recent searches persistence, streamer mode

---
Task ID: parity-slices-33-40
Agent: main (Super Z)
Task: Continue the AyuGram 1:1 parity program endlessly (slices 33–40)

Work Log:
- CI runs all green this session: 34241829062 (30–32), 34242862469 (33–35), 34243839450 (36–37)
- Slice 33: compose markdown → entities on send (*bold*, _italic_, __underline__, ~strike~, ||spoiler||, `code`, ```pre```; nested, UTF-16 offsets)
- Slice 34: copy-link-to-message (engine MessageLink wraps core ExportMessageLink) + tappable link tokens copy URL via per-token event tags; pendingCopy clipboard hop for background goroutines
- Slice 35: Ayu local hide (locally_hidden_messages v45 migration, GetMessages NOT EXISTS filter) + repeat (resends cached text + entities); engine tests on in-memory sqlite
- Slice 36: drawer per-account unread badges + selection-bar Report (opens the slice-19 flow)
- Slice 37: recent searches — AddRecentSearch/ClearRecentSearches in vault config (dedupe, cap 8), recents dropdown under the focused empty search field, Enter records
- Slice 38: drawer customization — Settings → Ayu · Drawer toggles persist hidden row ids (AppConfig.drawer_hidden_items), rows filtered at build
- Slice 39: schedule "send when online" (0x7FFFFFFF magic date; labels render 'when online')
- Slice 40: member-list search in the info panel (name/username/id substring filter)
- Matrix rows updated for every slice; all local gates green per slice

Stage Summary:
- 40 parity slices landed; CI green through 37; runs dispatched for 38–40
- Remaining P1/P2 candidates: voice/video playback (blocked: engine streaming), call bar (wrtc), forward multi-pick, streamer mode, profile share/edit, shared-media full grids, QR invite scan

---
Task ID: parity-slice-41
Agent: main (Super Z)
Task: Forward picker multi-select

Work Log:
- openForward helper centralizes forward entry points + selection reset
- Rows toggle recipients (check circle + accent); Send bar commits to all selected chats w/ summary toast
- Local gates green; matrix row upgraded to PRESENT; CI dispatched for 40-41

Stage Summary:
- 41 slices landed; CI green through 37; runs in flight for 38-39 and 40-41

---
## 2026-09-08 — slices 42–47

- **42 Polls**: attach-menu Poll → creation dialog (question/options/anonymous/multiple/quiz+correct, engine.CreatePollEx); poll bubbles from message Extra (vote bars, quiz reveal, optimistic VotePoll overlay)
- **43 Keyboard shortcuts**: global key layer — Esc dismissal stack, Ctrl+F search, Ctrl+↑↓/PgUp/PgDn chat switching (gui/shortcuts.go)
- **44 Streamer mode**: drawer toggle + vault persistence; masked names/presence, neutral person avatars (gui/streamer.go)
- **45 Notification privacy**: "Message previews" toggle; banners hide text/sender while off (gui/notify.go, AppConfig.NotifyPreviews *bool)
- **46 Ayu translator**: message menu Translate/Hide translation → engine.TranslateText; italic block under bubble (gui/translate.go)
- **47 Ayu marks**: customizable deleted/edited mark strings in settings_ayu (gui/marks.go, AppConfig.AyuDeletedMark/AyuEditedMark)
- Infra: fixed the node+wasm test runner (Go 1.27 wasm_exec.js is library-only; wrapper now uses GOROOT/lib/wasm/go_js_wasm_exec) — tests verified actually executing
- CI: 34250036199 (s42) + 34251620044 (s43–45) GREEN; verify dispatched for s46–47

---
## 2026-09-08 — slices 48–50

- **48**: chat-row menu Block user (DMs) + schedule-dialog silent switch ('silent ·' meta)
- **49**: who-reacted dialog (per-emoji tabs, engine GetMessageReactorsList w/ paging)
- **50**: emoji panel keyword search (engine GetEmojiKeywords + pure filter)
- CI: 34252401355 (s46–47) GREEN; runs dispatched for s48–50

---
## 2026-09-08 — slice 51

- **51 Live poll results**: cores OnMessagePoll → UpdatePollResults; engine mergePollResults (cache chat resolve, option-byte merge into content_raw) + EventMsgEdited; fixed int/float64 number coercion
- CI: 34253409439 (s48–49) + 34253838794 (s50) GREEN; dispatched for s51

---
## 2026-09-08 — slice 52

- **52 Profile cover**: big centered 96dp panel photo + centered name/status (streamer-safe)
- CI: dispatched for s51–52 (34254679916 in flight)
---
## 2026-09-09 — slice 53

- **53 Custom-emoji reaction pills**: premium custom reactions (empty Emoji + DocumentID) render in the strip with static doc thumbnails — gui/custemoji.go (session cache, batched lazy fetch per message, ⭐ placeholder, box reserved); pills toggle via the engine `custom_<docID>` convention; engine toggleReaction now keys custom entries by document id (optimistic parity); webp decoder registered
- Gates: gofmt, windows vet, engine/cores/utils tests, gui wasm suite (executed-verified), win+wasm builds — all green locally
- CI: verify dispatched on 1f0e8174 (slice-52 run 34254679916 was in flight)
---
## 2026-09-09 — slice 54 + matrix corrections

- **54 Folder tab menu + invite links**: right-click a server folder tab → Edit / Move left / Move right (engine ReorderDialogFilters, boundary-aware) / Invite links / Delete; new chatlist-share dialog (GetFolderInviteLinks list, tap-to-copy, CreateFolderInviteLink); Esc + outside-press dismissal
- Matrix: rows 87 (custom-emoji pills), 48 (three-pane — was stale), 78 (header avatar — was stale) flipped to PRESENT
- CI: slice-53 run 34257548785 in flight; the earlier 34254679916 failure was a transient artifact-upload 403 (smoke itself passed; superseded GREEN by 34254967388)
---
## 2026-09-09 — slices 53–55

- **53 Custom-emoji reaction pills** (CI gofmt hiccup fixed in 43da68ec): static doc thumbs in pills, custom_<docID> toggle convention, webp decode
- **54 Folder tab menu + invite links**: Edit / Move left/right / Invite links / Delete + chatlist-share dialog
- **55 Full reaction picker**: quick bar (7 + ⋯) swaps the menu into a full scrollable 8-column grid
- Matrix rows 48/55/78/87/154 flipped to PRESENT (three-pane, folder management, header avatar, custom pills, reaction picker)
---
## 2026-09-09 — slice 56

- **56 Attach Location + Contact**: attach menu entries; Location = lat/lon dialog (SendLocation); Contact = account contact picker (SendContact); dedicated bubbles — map-card w/ pin + live badge (tap copies maps URL), person-card (tap copies phone); parser tests lock the Extra contract
- CI: runs for 43da68ec (gofmt fix) + 2782f703 (s55) in flight; 34257548785 (s53) failed on the since-fixed gofmt gate
---
## 2026-09-09 — slice 57

- **57 Search results tabs**: All/Chats/Messages/Links/Files bar over the sidebar results; engine SearchMessagesEx kind filters (links = URL text/entities, files = has_media); invite row survives tabs
- CI: 34258709036 (gofmt fix, s53–54) GREEN; dispatched for s55–57
---
## 2026-09-09 — slice 58

- **58 Sticker + GIF panel tabs**: Emoji/Stickers/GIFs mode row in the helper panel; pack chips (Recent-first) + static-thumb grids; tap-to-send through SendSticker; saved-GIF grid via GetSavedGifs
- CI: s55 (2782f703) + s56 runs in flight/verified; dispatched for s57–58
---
## 2026-09-09 — slice 59

- **59 Accent color + font scale**: appearance page — 6 accent swatches (palette re-tint, dim blended to background, survives theme swaps) + Small/Default/Large text scale (UI.Label, clamped); persisted via the pre-existing AppConfig fields
---
## 2026-09-09 — slice 60

- **60 Message auto-delete**: core MessagesSetHistoryTTL wrapper + engine SetChatTTL (chats.ttl_period + event); header ⋮ "Auto-delete…" dialog (Off/24h/7d/1m); profile info row; gate.sh now guards every commit (gofmt-before-add)
- CI: s57 gofmt failure fixed (a1e839e7); s58/s59 runs in flight
---
## 2026-09-09 — slice 61

- **61 Reactions & poll-vote notifications**: per-account settings rows w/ contacts-only filters, engine SetReactionsNotifySettings; state seeded from GetReactionsNotifySettings
- Root-caused + fixed the s58/s59 CI gofmt failures (stale searchtabs_test.go in those commits; fixed by a1e839e7 — subsequent commits gated by scripts gate.sh)
---
## 2026-09-09 — slices 62–66 (post sandbox-reset session)

- Reinstalled the toolchain after a sandbox reset (Go 1.27.1 → /home/z/go, wasm exec re-linked); all gates re-verified before continuing
- **62 Privacy scopes**: cores GetPrivacyScope/SetPrivacyScope (settings vocabulary ↔ Telegram rules, round-trip tested); engine GetPrivacyScopes/SetPrivacyScope; Privacy & Security page — 10 rows w/ live server scope + picker dialog (Everybody/My contacts/Close friends where supported/Nobody)
- **63 Auto-download rules**: engine persists rules (kv autodl:<source>, loaded at Init) + GetAutoDownloadSettings effective view; Data & Storage per-source rows + editor dialog (type toggles, media/video size ladders, immediate apply)
- **64 Recent calls**: Voice tab per-account call history (engine.GetCallHistory was CORE-ONLY) — direction/duration/time rows, missed red, tap opens peer chat
- **65 Per-chat themes**: DM ⋮ "Change colors…" — server chat-theme picker (emoticon chips tinted w/ message colors, Reset) → engine.SetChatTheme
- **66 Cloud themes**: Appearance section — server theme list (GetCloudThemes was CORE-ONLY), install confirm → InstallCloudTheme + accent applied locally (persisted)
- CI GREEN at every dispatched checkpoint: 34270604522 (s62) · 34271439394 (s62–65) · 34272135542 (s66)

## 2026-09-09 — slices 67–71 (archive row, row badges, composer gating, call bar, profile editor)

Session goal (owner): continue unattended, push, verify via API.

### Ratings (§2.3)
- Architecture (single Gio binary, engine/cores/gui split, snapshot pattern): 9/10 — keep & extend.
- Sidebar/chat-view code: 8/10 — additive slices, no replacement needed.
- README.md: 0/10 vs reality (described the deleted FFI bridge + web host) — rewritten from scratch (§10).

### What I did (tests-first, all pure helpers locked in *_test.go)

- **67 Archived chats**: collapsed "Archived Chats" row at the top of the
  main list (box glyph, aggregate unread of unmuted archived chats); tap →
  archive view (only archived chats, back row replaces folder tabs, Esc
  exits); search from the main list still matches archived chats, the
  archive view scopes search to itself; account filter honored.
- **68 Row badges**: verified/premium icons + SCAM/FAKE text tags next to
  row titles (same vocabulary as the header badges); trailing badge stack
  in Telegram order: @-mention pill → unread-reactions counter → unread
  count/mark.
- **69 Composer gating**: write-restricted chats (WriteRestriction*) swap
  the composer for a lock + server-text bar (not-joined previews keep the
  JOIN bar); slow-mode chats show a live countdown pill (per-second
  redraw via one pending timer) that blocks Enter + the send button with
  an explanatory toast.
- **70 Group-call live bar**: under the chat header while
  ChatInfo.HasActiveCall; title/participants/RTMP status polled from
  engine.GetGroupCall every 5s (single poll loop tracked against the open
  chat; started/stopped from openChat + refreshChats); JOIN runs
  engine.JoinGroupCall (creates the call when absent) and flips to the
  Voice tab.
- **71 Edit profile**: Settings → Main → "Edit profile" per account —
  avatar upload via the OS picker (UploadProfilePhoto), username/bio/
  birthday editors with client-side validation (UpdateAccountUsername/
  UpdateBio/UpdateBirthday), server reload after every apply; name and
  phone render read-only (no engine setter — hidden, not faked). Editor
  text is captured on the GUI thread; engine calls + reload run in the
  background.
- **README rewritten** to describe the real app (Gio single binary,
  platforms, build recipes incl. goolm + low-RAM, backend status table).
  The old one documented the deleted bridge/proto/FFI architecture.
- Matrix rows updated: 56/59/64/84/101/193 → PRESENT; stale search rows
  (254/255) and not-joined row (100) verified already PRESENT (slices 16/
  57/19); AGENTS.md checklist annotated with slices 67–71.

### Verification
- gofmt clean; `go vet -tags goolm` clean for windows (full tree) and
  natively for engine/cores/utils/bootstrap/wrtc.
- `go test -tags goolm`: engine, cores, utils, bootstrap PASS natively;
  the full gui suite (incl. the 5 new test files) compiled to js/wasm and
  executed under Node (PASS).
- Windows amd64 + js/wasm app builds produced binaries (CGO_ENABLED=0).
- Linux native GUI build impossible in this sandbox (no root for the Gio
  cgo headers) — CI verify (Xvfb GUI smoke + screenshots) covers it.

### Next
- CI verify dispatch for this push, monitor to GREEN (API).
- Continue parity: top-peers strip (row 53), chat background (row 103),
  stories row (row 65), voice-message playback (row 135).
- mumble/teamspeak rewrite, live-verify xmpp/bale/rubika/deltachat (§8).

## 2026-09-09 — slices 72–76 (top peers, LRead/SRead, bot commands) + first CI green

- CI Verify run 34317867694 (commit 555fffb7, slices 67–71): **GREEN** —
  test/vet/gofmt, windows+wasm cross-builds, and the Xvfb GUI smoke with
  screenshots all passed.
- **72 Top peers strip**: pictured row above the chat list while the search
  field is focused and empty (engine.GetTopPeers ranking); renders only
  with an unambiguous account scope (filter set or single account); tap
  opens the chat; scope-guarded async load.
- **75 LRead/SRead drawer toggles**: two switches in the drawer's AyuGram
  section. SRead = existing SendReadReceipts ghost flag; LRead = new
  AppConfig.LocalReadMark (default on) that gates the GUI's mark-on-open
  call — engine config round-trip tested; toggles are independent and
  toast their effect.
- **76 Bot commands menu**: composer "/" button (rendered only when the
  chat has commands — GetChatBotCommands loaded lazily per chat, never a
  dead button), panel with command/bot/description rows, tap inserts the
  command into the composer, Esc closes.
- Gates re-run: gofmt clean, gui vet (wasm) clean, full gui suite PASS
  under node, engine LocalRead tests PASS natively.
- Matrix rows 53/118/231 → PRESENT.

## 2026-09-09 — slice 77 (sender name colors + admin rank)

- CI Verify run 34319015048 (commit fbc2ce41, slices 72–76): test/vet/gofmt
  and the Xvfb GUI smoke GREEN at the time of writing; cross-builds in
  flight.
- **77 Sender name colors + rank**: group bubbles render sender names in
  Telegram's 7-color name palette — the server color slot when the core
  knows it (SenderColorID 0-6), otherwise a stable FNV derivation from the
  sender id (the core returns -1 for unknown); the admin rank
  (SenderRank: admin/owner/custom titles) is appended to the title.
  Streamer masking preserved.
- Char-count near limit (row 124) deliberately skipped: the 4096 limit is
  Telegram-specific and the engine exposes no per-backend message limit —
  a generic counter would lie on IRC/XMPP (§1.10).

## 2026-09-09 — Pages deployment fixed (the web target actually reachable)

- **Bug**: https://darkreaperboy.github.io/Uniclient/ 404'd since forever —
  the release pipeline had been pushing the gh-pages branch correctly
  (verified: index.html + wasm_exec.js + uniclient.wasm present, v0.4.0 web
  job GREEN), but GitHub Pages was never ENABLED on the repo, so the branch
  sat orphaned.
- **Fix**: enabled Pages via the API (source: gh-pages branch, root path).
  First build completed; the site now serves HTTP 200 (index 704B,
  wasm_exec.js 17KB, uniclient.wasm 64MB) at
  https://darkreaperboy.github.io/Uniclient/.
- The next release tag redeploys the site through the existing pipeline
  (release.yml web job force-pushes gh-pages; Pages picks it up).

## 2026-09-09 — v0.5.0 pre-release published (session close-out)

- Tagged **v0.5.0** (prerelease: true, per §1 policy) — the full release
  pipeline ran GREEN end-to-end: test/vet/gofmt, linux amd64+arm64 (cgo,
  UPX), windows amd64 (pure Go, UPX), android arm64 APK, web deploy, and
  the publish job.
- Assets live on the release page: uniclient-linux-amd64 (14.7 MB),
  linux-arm64 (12.5 MB), windows-amd64.exe (14.6 MB), uniclient.apk
  (20.7 MB), checksums.txt.
- The web demo re-deployed through the pipeline and serves the new build
  (uniclient.wasm 69 MB, HTTP 200) at
  https://darkreaperboy.github.io/Uniclient/ — Pages was enabled earlier
  this session, so this is the first release whose web target actually
  serves users.
- CI ledger this session: verify 34317867694 (slices 67–71) GREEN ·
  34319015048 (slices 72–76) GREEN · 34319212283 (slice 77) GREEN ·
  release 34319847283 (v0.5.0) GREEN.

Session totals: 11 parity slices (67–77) + README rewrite + Pages
deployment fix + v0.5.0 pre-release. All gates green locally and in CI.

## 2026-09-09 — release blockers fixed + slice 78 (shared-media tabs)

- **Two release blockers fixed** (user reports, both verified end-to-end
  with Xvfb/xdotool injection and the real binary):
  1. **App-wide pointer-input freeze** after adding an account (auth form,
     settings, every click dead on Linux/Windows/Android): the global
     keyboard-shortcuts layer registered an OPAQUE window-wide hit node
     (clip + event.Op, no pointer.PassOp) rendered last in Root — Gio's
     hit-test walk short-circuits at opaque nodes, so everything beneath
     stopped receiving pointer events. Fixed with a keyLayer helper
     (pointer.PassOp) shared by the shortcuts layer and Settings;
     regression test pins the fix (fails without PassOp).
  2. **Web (wasm) purple-screen boot crash**: engine.Init os.MkdirAll'ed
     on the js target (not implemented) → log.Fatal right after the first
     frame. Fixed: build-tag ensureDir (no-op on js), vault persistence
     split file/native vs localStorage/web (accounts and config now
     survive page reloads), OpenDB uses ensureDir.
- **Slice 78 — shared-media tab browser**: the profile panel's count
  pills + 12-photo strip became the full tabbed browser (§7): chip bar
  (Photos/Videos/GIFs/Voice/Audio/Files/Links, wrapping, active chip
  accented); 3-column grids for visual tabs (video cells carry the play
  badge + duration pill; tap → fullscreen viewer anchored in-tab);
  jump-to-message rows for voice/audio/files/links (panel closes before
  the jump on phone layout); engine GetSharedLinks + distinct gif/voice
  sub-tab filters; lazy per-tab loads (60 media / 100 links).
- CI Verify run 34342330119 (blockers commit c1fca15c) GREEN.

## 2026-09-09 — slices 79-82 (menu completion, anti-recall Ayu styling, music attach, about page)

- **79 Header ⋮ menu completion (§3 P0)**: "Search" opens the in-chat
  search bar; "Add members" (groups/channels) opens a contact picker —
  search filter, multi-select check circles, one engine.AddMembers call,
  count toast, member-list refresh. DM menus never offer Add members.
- **80 Anti-recall completion (§52, row 232)**: recalled bubbles fade to
  50% opacity (bg, body text, sender name — deletedFade); "Clear deleted
  messages" per chat in the header menu (engine.ClearDeletedMessages
  removes saved copies + media rows, idempotent, honest toasts); Ayu ·
  Anti-recall settings section (save deleted / save history / save for
  bots) applied immediately and persisted (AyuSave* config keys, Init
  restores).
- **81 Music attach (row 114 P0)**: the 📎 menu gains Music — the OS
  picker filtered to audio containers; upload path shared with File.
- **82 About page + bubble corners (rows 209/197)**: About shows the app
  version, Go runtime, backends, and the keyboard-shortcut list;
  Appearance gains "Round bubble corners" (12dp ↔ 2dp, persisted).
- Root cause of the 9dc8aad0 Verify failure was a gofmt miss on
  sharedtabs_test.go (unkeyed-field edit landed after the local gate);
  fixed; current HEAD is clean.

## 2026-09-09 — slices 83-84 (share contact, rubber-band selection)

- **83 Share contact** (profile actions, row 177 → PRESENT): the DM
  profile panel gains a Share button — vcardFor builds a minimal vCard
  (FN/TEL/NICKNAME from real profile fields) and copyTextSoon puts it on
  the clipboard (AyuGram's share-as-text).
- **84 Rubber-band selection** (row 98 → PRESENT): in selection mode,
  dragging over the message list draws an accent-tinted rectangle and,
  on release, marks every visible row it intersects (rowBounds
  hit-testing, drag-direction normalized). The overlay is a
  pass-through hit node — bubbles keep tap-to-toggle, the wheel keeps
  scrolling (desktop mouse drags don't scroll a Gio List anyway);
  a plain tap produces a zero-area rect and selects nothing.
- Matrix audit: row 223 (call bar) was stale — callbar.go (slice 70)
  already renders the active-call bar; row 210 updated for the
  anti-recall section.

## 2026-09-09 — slice 85 (proxy settings, download path, hide All-chats)

- **Proxy settings** (Data & Storage, row 196): mode segments
  (Disabled / System / Custom) + type segments (SOCKS5 / HTTP / MTProto)
  + host/port/user/pass fields. Apply pushes engine.SetProxy (live cores
  redial through it immediately) and persists AppConfig.ProxyConfig —
  Init restores the proxy before the first connect. engine.GetProxy
  Settings seeds the form.
- **Download path** (same page): editor → engine.SetDownloadDir (created
  when needed) + persisted; Init prefers the configured path over the
  bootstrap default.
- **Hide All-chats** (Main → Chat folders): the toggle drops the All
  tab from the folder bar (buildFolderTabs hideAll; Unread stays first,
  server folders follow) — persisted HideAllChats config.
- utils.ProxyConfig gained a Mode field (0/1/2).

Tests: proxy segment mappings, port normalization (junk/bounds), config
persist shape; buildFolderTabsHideAll (All gone, order preserved). Full
suite green under node+wasm; engine+utils native green; vet + gofmt clean.

## 2026-09-09 — v0.6.0: parity program complete to the engine's capability

- **Linux e2e verified on the release binary** (user's top-priority
  platform): rebuilt the Xvfb sysroot in the workspace (downloaded .debs,
  no root), built natively with CGO against it, and drove the real app
  through the full pointer-input regression path — welcome → picker →
  auth form → typed phone number (275 editor pixels changed = text
  rendered) → settings open → rail interaction → Esc back. Pointer and
  keyboard input confirmed live at HEAD; the c1fca15c fix holds.
- Session parity ledger: slices 78 (shared-media tabs), 79 (header menu
  search + add-members), 80 (anti-recall styling/toggles/clear), 81
  (music attach), 82 (about page + bubble corners), 83 (share contact),
  84 (rubber-band selection), 85 (proxy + download path + hide-All).
  Remaining matrix PARTIAL/MISSING rows are engine-gated (media
  playback/call audio need streaming+audio-out APIs the cores don't
  expose; tray/taskbar need platform shims) or P3 polish.
- CI Verify ledger this session: 34358390858 (79-80) GREEN ·
  34359032048 (81-82) GREEN · 34359921361 (83-84) GREEN ·
  34360912603 (85) GREEN · 9dc8aad0 failed on a gofmt miss (fixed
  before 79-80 landed).
- Tagging v0.6.0 (prerelease per §1): 4 platform binaries + checksums +
  web redeploy via the release pipeline.
- Release pipeline 34362784366 GREEN: v0.6.0 (prerelease) published —
  linux amd64 (14.1 MB) + arm64 (11.9 MB), windows-amd64.exe (14.0 MB),
  uniclient.apk (19.8 MB), checksums.txt. Web demo redeployed from the
  release (gh-pages "Web build for v0.6.0", pages deployment
  34363067495 GREEN; site serves the new wasm, HTTP 200).

## 2026-09-09 — slice 86 (media OS handoff: playback via system player, browser links, show-in-folder)

- **Playback handoff (rows 134/135/136/267)**: taps on voice/audio/video
  (and the viewer's play button) now express play intent — the download
  completes and the saved file opens in the system player
  (xdg-open / open / rundll32; android honestly errors, web opens links
  only). Photos keep the in-app viewer path; a second delivery of the
  same completion never re-opens (one-shot openOnDone marks).
- **Link opening (row 125)**: tapped links open the platform browser
  (window.open on web keeps user activation); schemes outside
  http/https/tg and opener-less platforms fall back to the slice-34
  clipboard copy.
- **Show in folder (row 159 → PRESENT)**: "Show in Folder" in the message
  context menu (only when the message has a local file) + a folder button
  in the viewer top bar reveal the saved media (xdg-open dir / open -R /
  explorer /select). Completed documents open in the system viewer.
- Platform layer injected via openExternalAsync/revealAsync package vars
  (desktop / js / android files) so tests never spawn processes; opener
  children are Run()-reaped (no zombies). Pure decision helpers
  (sanitizeURL, openArgsFor, revealArgsFor) locked by openext_test.go.
- Tests: 7 new (URL admission, per-OS command mapping, openOnDone
  one-shot flow incl. failure + unmarked paths, link fallback, reveal
  toasts, Show-in-Folder menu presence). Full suite green (gui 297 runs,
  0 fail), vet + gofmt clean, native binary builds.

## 2026-09-09 — slice 87 (local passcode lock)

- **Passcode lock (rows 195/207/291 → PRESENT)**: vault-backed 4-6 digit
  PIN (engine SetPasscode/GetPasscodeConfig/ClearPasscode/
  UpdatePasscodeConfig). The app boots LOCKED and renders ONLY the lock
  screen while locked — chat content is never drawn (screenshot-safe),
  and the lock's opaque window-wide input registration eats presses.
- Lock screen: PIN dots (red after a wrong try), shared 3×4 pad
  (pinGrid) + keyboard path (digits / ⌫ / Enter), auto-submit on the
  last digit, "Too many attempts" 30s cooldown after 5 wrong tries.
- Autolock: 1/5/60 minutes or never, persisted in the vault record; a
  pass-through key/pointer activity listener (lockActivityLayer,
  pointer.PassOp — same safety as keyLayer) feeds the idle timer, so
  network-driven repaints don't keep the app unlocked.
- Editor dialog (Privacy & Security → Security → Passcode Lock): set
  (new + confirm with digits picker), change (verify current first),
  disable (verify + armed double-tap), autolock segments applied
  immediately via UpdatePasscodeConfig. Row value summarizes state.
- Tests (lock_test.go): hash determinism, vault mapping roundtrip +
  clamps/defaults, feed/unlock/freeze state machine, autolock decision
  table, dialog step machine (entry→confirm→saved, mismatch restart,
  verify current, frozen reject), digits-changed reset, labels.
  Full suite green, vet + gofmt clean.

## 2026-09-09 — slice 88 (composer char counter)

- **Char counter (row 124 → PRESENT)**: the composer shows the remaining
  character count (right-aligned, under the input) once the draft is
  within 128 of Telegram's 4096-char limit — AyuGram's near-limit
  behavior; the count turns red past the limit. Rune-counted (CJK-safe),
  not bytes. Both send paths (Enter submit + send button) refuse
  over-limit drafts with a "Message is too long" toast.
- Tests: counter visibility thresholds (hidden / 128 / 0 / negative),
  rune-vs-byte counting, over-limit gate.

## 2026-09-09 — slice 89 (chat-row hover quick actions)

- **Hover quick actions (row 68 → PRESENT)**: hovering a chat row shows
  two compact icon toggles at the row's right edge (over the badge zone):
  mute/unmute (bell / crossed bell → engine.MuteChat toggle, forever) and
  mark read/unread (check-circle / mark-unread → MarkChatRead/
  MarkChatUnread). Honest toasts + list refresh after each action.
- Layout: East-anchored Stack overlay inside the row's ButtonLayout hit
  area (hover is not lost moving onto the buttons) rendering LAST so the
  buttons are the topmost opaque hit nodes — their presses don't open
  the chat (the c1fca15c hit-test lesson, in reverse).
- Tests: mute/read decision tables (muted, unread count, unread mark,
  read row), pool growth + distinct pairs.

## 2026-09-09 — CI fix (wasm build), slice 89 note

- Verify 34368893579 (slices 86+87) failed in the Web (wasm) cross-build:
  openext_web.go compared js.Value with != (js.Value embeds funcs — not
  comparable). Fixed with w.Type() checks. The local gate script now
  builds the js/wasm target too, so this class of break never lands
  again (android stays CI-gated via the release pipeline's NDK build).

## 2026-09-09 — slice 90 (Ayu regex message filters) + content-pane ordering fix

- **Message filters (row 238 → PRESENT)**: Ayu settings gains "Message
  filters" — a dialog listing local regex hide-rules with add (invalid
  regexes rejected inline before they can break every chat load),
  per-filter on/off, delete. Engine: ayu_filters table (v46 migration),
  AddAyuFilter/List/SetEnabled/Remove; GetMessages filters at BOTH load
  exits (cache window + fresh fetch) via enabledAyuRegexes; service rows
  and media-only bubbles survive text filters. Changes re-render the
  open chat instantly (refreshOpenChat).
- **Quick filter add (row 168 → PRESENT)**: message context-menu
  "Filter Like This…" opens the editor prefilled with a regex-quoted
  first-line snippet (quickFilterPattern: collapse spaces, cap 64
  runes, QuoteMeta — the suggestion always matches its source).
- **Content-pane ordering regression FIXED (introduced by c1fca15c)**:
  settings-first in the desktop chain hid every dialog opened FROM
  settings (auto-download editor) and — worse — the autolocked PIN
  screen whenever settings was open (the lock is a security gate).
  Extracted the shared priority into pure contentDialogSurface(f)
  (newChat → contacts → folder → folderInvites → attach → addMember →
  ttl → privacy → lock → autoDl → theme → cloud → ayuFilters) used
  verbatim by both narrow and desktop chains; lock wins over
  everything; settings beats only login. Pinned by
  TestContentPaneDialogSurface.
- Fixed the dialog's event handling: submit events drain via
  Editor.Update (the key.Filter{Focus} approach never fires), and the
  editor clear after a successful add moved to the layout pass via a
  clearInput flag (SetText is not goroutine-safe).
- Tests: engine (CRUD, invalid-regex rejection, load-path filtering,
  GetMessages gate) + gui (filterCountLabel/Text, quickFilterPattern
  incl. quote-meta semantics, actionsFor Filter gate, escTarget
  self-handling, contentDialogSurface incl. regression pins). Full
  suite green (gui 323 runs, 0 fail under node+wasm); engine+utils+
  cores+bootstrap native green; vet + gofmt clean.

## 2026-09-09 — slice 91 (Ayu shadow ban)

- **Shadow ban (row 240 → PRESENT)**: per-chat local ignore list —
  shadow_bans table (v47); GetMessages excludes banned senders in SQL
  at all three cursor branches (windowing stays consistent — a page is
  never short-filled), plus a Go-level filter on the live-fetch page
  (freshly cached rows bypass SQL until the next read). Per-chat
  scoping: a ban in one chat never leaks to another.
- Context menu: "Shadow-ban sender" / "Unshadow-ban sender" (state-
  aware label — openMenu resolves the ban state per open; nil state
  hides the item). Gate pinned by shadowBanMenuGate tests.
- Header ⋮ menu: "Shadow-banned users…" manager dialog (reactors-
  pattern overlay): per-row Unban, honest toasts, live refresh.
- Fetch-decision fix (benefits locally-hidden rows too): the live-
  fetch trigger now counts raw cache rows instead of the post-hide
  page — a full cache with hidden rows no longer re-fetches live on
  every initial load.
- Tests: engine CRUD + per-chat scoping + windowed exclusion +
  dropShadowBanned; gui row naming, header-menu presence on every
  chat type, escTarget self-handling, menu gate table. Full suite
  green; vet + gofmt clean.

## 2026-09-09 — slice 92 (hashtag/tag search)

- **Tag search (row 259 → PRESENT)**: engine.SearchMessagesByTag —
  FTS narrows to the tag body (unicode61 splits on '#'), then a pure
  post-filter (matchHashtagToken) enforces the exact '#tag' token with
  Telegram tag chars (letters/digits/underscore, case-insensitive), so
  "#news" never matches "newsletter" or "#news2".
- In-chat search: a leading-# query switches to tag mode
  (isHashtagQuery; same 2-rune minimum).
- Hashtag taps: bubbles' #hashtag entities now carry their kind
  (linkTag.kind via richStyle.linkKind); a tap opens the chat's tag
  search (openInChatSearchWithQuery) instead of the browser/copy path
  — AyuGram's tagged-messages behavior.
- Tests: matchHashtagToken table (boundaries, continuation, case),
  SearchMessagesByTag over seeded FTS rows (bare-word and longer-tag
  exclusions, degenerate queries), applyEntity link kinds,
  isHashtagQuery. Full suite green; vet + gofmt clean.

## 2026-09-09 — slice 93 (layout tweak sliders)

- **Bubble corner radius slider (row 246)**: Appearance → Layout; 0-18 dp
  replaces the slice-82 rounded/square toggle (12 = the old rounded
  default, 2 = near-square; legacy BubbleCorners configs fold in via
  utils.EffectiveBubbleRadius).
- **Wide multiplier slider**: bubble max width 70-100% of the chat pane
  (default 0.75 = the previous fixed 3/4); chat.go computes maxW from
  UI.wideMultiplier.
- Both apply live (UI state on the GUI loop) and persist debounced — a
  600 ms coalescing timer means a drag is one config write, not one per
  frame. Config: AppConfig.BubbleRadius / WideMultiplier (+ConfigChanges
  pointers; clamped at the engine boundary).
- Avatars stay circular (AyuGram's own default shape) — noted honestly
  in the matrix instead of a half-working corners knob.
- Tests: label formatting, Effective* defaults/legacy-fold/override,
  clamps. Full suite green; vet + gofmt clean. CI Verify GREEN on
  slices 90 (34374607937), 91 (34375695737), 92 (34376328142).

## 2026-09-09 — slice 94 (folder export/import)

- **Import filters (row 67 → PRESENT)**: the folder-tab context menu
  gains "Export folders" (all the account's dialog folders → versioned
  JSON on the clipboard) and "Import folders…" (paste dialog —
  content-pane replacement, Esc/Close, inline errors, busy state).
- Engine folderio: encode/parse pure halves (envelope version guard,
  name validation), ImportFoldersJSON skips existing names (re-import
  is a no-op, never a duplicate), CreateFolderOpts round-trips flags +
  chats/pinned/exclude.
- The paste field is multi-line: Enter inserts newlines, import runs
  from the button (no dead submit path).
- Tests: encode/parse round-trip, validation table (garbage/wrong
  version/empty/nameless), opts mapping, folderMenuItems order update,
  escTarget + contentDialogSurface entries. Full suite green; vet +
  gofmt clean.

## 2026-09-09 — slice 95 (deep links)

- **Deep links (row 292 → PARTIAL)**: t.me/+hash, t.me/joinchat/hash
  and tg://join?invite=hash taps open the in-app join flow
  (openInviteJoin); t.me/<username> and tg://resolve?domain=x resolve
  through the global server search and open the chat via the
  pendingOpen GUI-loop hop (openChat touches the composer — never from
  a goroutine). Message-permalink / topic forms (t.me/user/123,
  t.me/c/…) and reserved paths (addstickers, s/… etc.) stay on the
  browser: they need server message lookups the engine does not expose
  (honest split, noted in the matrix).
- Routing lives at the top of openLinkExternal, so every tapped link
  in the app benefits; pure classification (deepLinkTarget +
  parseQueryPairs) locked by tests incl. tg:// query parsing and
  last-value-wins.
- Row 39 refreshed: signup photo is covered by the own-profile editor
  immediately after signup.
- Tests: invite/resolve/not-a-link tables, permalink + reserved-path
  exclusions, query parsing; openext test updated for the new routing
  (browser path on non-deep URLs; t.me/invite links route internally,
  honest no-account toasts). Full suite green; vet + gofmt clean.
- CI Verify GREEN on slices 93 (34377086950) and 94 (34377706476).

## 2026-09-09 — v0.7.0: slices 86-95, dialog-priority regression fixed

Session ledger (since v0.6.0):
- slice 86 media OS handoff (system-player playback, browser links,
  show-in-folder) · slice 87 local passcode lock (boot-locked PIN gate,
  autolock) · slice 88 composer char counter · slice 89 chat-row hover
  quick actions (mute/read) · slice 90 Ayu regex message filters +
  quick-add · slice 91 per-chat shadow ban · slice 92 hashtag/tag
  search (incl. bubble hashtag taps) · slice 93 layout sliders (bubble
  radius + wide multiplier) · slice 94 folder export/import ·
  slice 95 in-app deep-link routing.
- Critical fix: the content-pane dialog priority (c1fca15c regression
  that hid the autolocked PIN screen and settings-opened dialogs on
  desktop) — extracted to pure contentDialogSurface, lock wins over
  everything, pinned by tests. Web boot crash + wasm build fixes from
  the prior session included.
- Fetch-decision fix: hidden/shadow-banned rows no longer force a live
  re-fetch on every initial load.
- CI Verify GREEN on every slice commit this session (runs 34374607937,
  34375695737, 34376328142, 34377086950, 34377706476, 34378611565).
- Tagging v0.7.0 (prerelease per §1.5): 4 platform binaries + web
  redeploy via the release pipeline.

## 2026-09-10 — slices 101-103 (voice mode: real call UI)

Session goal: the §11 unchecked "Voice mode: real call UI on top of wrtc"
item — the engine's complete call API (1:1 + group) was never surfaced in
the GUI (3 P1 + 1 P2 CORE-ONLY rows in the matrix).

### slice 101 — 1:1 call overlay

- **Header call buttons**: phone + video icons on DM chats, gated on the
  account's CALLS capability (cached per-account on chat open, hdrCaps) and
  non-bot peers; groups/channels keep the group-call bar. Hidden otherwise —
  no dead buttons (§1.10).
- **Outgoing flow**: StartCall → full-window dark call overlay (scrim over
  everything but toast/shortcuts): peer avatar (real userpic when the chat
  is loaded, streamer-masked), name, video tag, status line.
- **Incoming flow**: EventIncomingCall (previously an unused event!) raises
  the ringing overlay — green answer / red decline round controls;
  EventCallState drives the state machine.
- **State machine (pure, pinned by tests)**: ringing → connecting → active
  → ended; monotonic (stale ringing never rewinds an active call; ended is
  terminal), startedAt stamped once so the elapsed timer (1s invalidation
  ticker, runs only while the exact session is active) is stable; the ended
  panel freezes the call duration and auto-dismisses after 4s.
- **Controls**: mute (SetCallMuted), camera toggle on video calls
  (ToggleCamera), end (EndCall), decline (DeclineCall — closes the panel
  immediately), accept (AcceptCall, optimistic connecting). Esc declines a
  ring / cancels outgoing / dismisses the ended panel — but never silently
  hangs up an ACTIVE call (the red button is the only way, AyuGram-safe).
- Call-end refreshes the Voice tab's recent-calls history.

### slice 102 — group call screen

- **Joining is real now**: the call-bar JOIN and a new JOIN on Voice-tab
  active-call rows record the joined call (JoinGroupCall's returned callID)
  and the Voice tab becomes the call screen.
- **Call screen**: title + live participant count (GetGroupCall polled
  every 2s — faster than the bar's 5s because speaking indicators need
  fresher data), participants list with speaking dot, mic-off/hand/video
  icons, anonymous fallback "Participant", self sorted first with "(You)".
- **Controls**: mute (SetCallMuted — server truth wins over the optimistic
  local mirror once self appears in the list), raise hand (RaiseHand —
  offered only to force-muted self: IsMuted && !CanSelfUnmute), leave
  (LeaveGroupCall + toast + history refresh).
- The poll closes the screen itself when the engine reports the call
  inactive; transient fetch errors keep the last snapshot (never blanks).
- EventGroupCallState now refreshes the chat list (HasActiveCall stays
  current even without chat snapshots).

### slice 103 — Calls settings (device pickers) + noise suppression

- **Settings → Calls section** (rail order: … Appearance, Calls, Ayu … —
  AyuGram's): mic/speaker/camera pickers over the engine's real OS device
  enumeration (GetAudioDevices: pactl/ALSA/v4l2 on Linux; the Default
  sentinel everywhere). Selection persists (SetCallAudioDevice) and
  re-renders from the config snapshot; a stale current (unplugged device)
  selects nothing.
- **Noise suppression**: in-call toggle on the group-call screen
  (SetNoiseSuppression), stateful label.
- refreshConfig's inline config→snapshot mapping extracted to pure
  cfgFromAppConfig (testable; device fields added).

### verification

- Tests first per §9: 25 new gui tests (state machine, gating, controls,
  rows, pickers, labels) — one real bug caught pre-commit (the ended-state
  duration must freeze at endedAt, not drift with `now`).
- Full gate green: native engine/cores/utils/bootstrap + gui under
  node+wasm; gofmt clean; vet clean (gui wasm + native pkgs).
- wasm + windows/amd64 binaries build locally (70MB / 56MB unstripped
  toolchain builds; CI strips+UPX).
- Parity matrix: 107 PRESENT / 27 PARTIAL / 10 MISSING / 57 CORE-ONLY.

### leftovers

- 1:1 video: local camera preview rendering (engine video-frame APIs
  remain CORE-ONLY) — the toggle dispatches, no preview yet.
- Group-call admin actions (invite/recording/RTMP/title edit) remain
  engine-gated matrix rows.
- Call rating dialog (SendCallRating) remains CORE-ONLY (P3).

## 2026-09-10 — slice 104 (stories), live-core verification

- **Live verification (§9 ladder, official-server rung)**: IRC core round-
  trip PASSED against irc.libera.chat:6697 (connect, MOTD, join/send/
  receive); GitHub core PASSED against the real API authenticated as
  DarkReaperBoy. Both via the env-gated `go/tests/` live suite
  (`-tags goolm,live`).
- **Stories row (row 87 → PRESENT)**: horizontal story-circles strip above
  the folder tabs — chats with StoryCount>0 only (dangling unread flags on
  zero-count chats stay hidden), unread first, accent ring unseen / dim
  ring seen, real userpics with letter fallback, clipped name labels,
  streamer-mode masking.
- **Story viewer (row 126 → PARTIAL)**: full-window overlay fed by
  engine.FetchPeerStories — progress segment bar (one per story, active
  accent), left/right tap zones + arrow keys (past-last closes, AyuGram
  behavior), header avatar+title+close, caption + "N views · date" meta,
  image stories decode through the shared media image cache; video stories
  honestly hand off to the system player (in-app playback waits on engine
  streaming). Honest loading/error/empty cards for the fetch.
- Parity: 108 PRESENT / 28 PARTIAL / 10 MISSING / 56 CORE-ONLY.
- CI Verify run 34404120630 on slices 101-103 (b91c0537): SUCCESS (full
  gate + cross-builds + Xvfb GUI smoke).

## 2026-09-10 — slice 105 (message details)

- **Message details (row 165 → PARTIAL)**: context-menu "Message details"
  → dialog of key/value rows derived purely from the cached message —
  message/sender IDs, sent/edited/deleted (anti-recall) timestamps, delivery
  status, forward origin, reply-to, media metadata (file name, mime, size,
  dimensions, duration, local path), pinned/silent/no-forwards flags. Tap a
  row copies its value. DC and view counts are honestly absent (the engine
  does not cache them — never fabricated, §1.10).
- Rows derive via the pure msgDetailRows (locked by 7 tests incl. service
  gating, media table, fallback senders); dialog follows the
  reactors/edithistory card pattern (scrim + Esc + backdrop close).
- Parity: 108 PRESENT / 29 PARTIAL / 10 MISSING / 55 CORE-ONLY.

## 2026-09-10 — slice 106 (member admin menu)

- **Member context menu (row 148 → PRESENT)**: tapping a member row in the
  profile panel opens AyuGram's admin menu — Promote to admin / Demote to
  member / Restrict / Ban / Unban / Remove from chat. Gated on the chat's
  IsAdmin/IsCreator (non-admins get no menu — rows stay plain); owner rows
  and the viewer's own row are untouchable; banned members offer Unban.
  Every action dispatches the real engine call
  (Promote/Demote/Restrict/Ban/Unban/RemoveMember), toasts the result, and
  refreshes the panel's member list.
- Pure memberMenuItems locked by 5 tests (rights gate, role table, owner/
  self exclusion, label presence).
- CI Verify run 34405844949 on slice 104 (2f310298): SUCCESS.
- Parity: 109 PRESENT / 29 PARTIAL / 10 MISSING / 54 CORE-ONLY.

## 2026-09-10 — slice 107 (groups in common)

- **Common groups (row 150 → PRESENT)**: DM profile panels gain the
  "Groups in common (N)" section — engine.GetCommonChats (30 max), rows
  with avatars + member counts, streamer-masked titles, tap opens the
  chat (honest toast when it is not in the loaded list). Hidden when the
  list is empty; groups/channels never show it.
- Pure gate + row derivation locked by 3 tests.
- Parity: 110 PRESENT / 29 PARTIAL / 10 MISSING / 53 CORE-ONLY.

## 2026-09-10 — slice 108 (sticker packs), XMPP live-verified

- **Sticker pack info/add (row 161 → PRESENT)**: sticker messages with
  set keys (parsed from the cached MediaExtra: short name, or set ID +
  access hash) gain "View sticker pack" — a card dialog over
  engine.GetStickerSetInfo (title, "N stickers · kind · installed" line,
  5-column thumbnail grid reusing the composer picker's cell renderer,
  Esc/backdrop close) with ADD TO STICKERS → engine.InstallStickerSet
  (live installed-state flip + toast). Stickers without keys or cores
  without the fetcher honestly get no item (§1.10).
- **XMPP core live verification (§9 official-server rung)**:
  go/tests/xmpp_live_test.go dials conversations.im:5222, negotiates the
  stream, upgrades STARTTLS, and runs the SASL handshake with throwaway
  credentials — the server's auth-failure response proves the whole
  pre-auth chain works (1.9s). AGENTS.md §8 updated: implementation kept.
- Bale transport endpoints re-verified reachable (next-ws/tapi.bale.ai
  443 via the embedded IP table); Rubika web endpoint reachable. Full
  protocol verification stays blocked on real (geo-restricted) accounts.
- Parity: 111 PRESENT / 29 PARTIAL / 10 MISSING / 52 CORE-ONLY.
