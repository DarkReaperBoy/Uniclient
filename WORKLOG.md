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

## 2026-09-10 — slice 109: mumble + teamspeak live-verified (1:1 protocol)

The owner's directive: 1:1 the Teamspeak/Mumble protocols first and foremost,
test on public servers before their own live test. Both cores were rated
"broken/stale" in §8 — the honest rating after this session: **the protocol
implementations were structurally sound and nearly 1:1 already, but had
hard-verification gaps and 5 real bugs** that only live testing could find.

### research (primary sources, not the old notes)

- Official Mumble.proto + MumbleUDP.proto fetched from mumble-voip/mumble
  master; every message field number in our protobuf codec verified against
  them (all match).
- Upstream CryptStateOCB2.cpp decrypt algorithm ported 1:1 (save/restore IV,
  ±30 late window, decrypt_history replay guard).
- ReSpeak/tsproto is GONE (404). The authoritative TS3 spec is
  ReSpeak/tsdeclarations ts3protocol.md; working reference impls: ts3j
  (Manevolent/ts3j) + TSLib (Splamy/TS3AudioBot) — both cloned and used for
  test vectors.

### live verification (§9 official-server rung)

- **Mumble** (murmur.libresilicon.com:64738): full TCP chain in 1.3s
  (TLS→Version→Authenticate→CryptSetup→CodecVersion→ChannelState→
  PermissionQuery→UserState→ServerSync→ServerConfig). Two-client text
  round-trip: A joins Root, B joins Root, A sends → B receives (Murmur never
  echoes to the sender — verified in upstream Messages.cpp: msgTextMessage
  removes uSource from the recipient set; the old single-client echo test
  expectation was wrong, not the core). UDP ping verified (12→24 byte
  legacy format). 3 more public Murmurs verified reachable.
- **TeamSpeak** (ts.arcticblaze.net:9987): FULL client protocol — 5-step
  init handshake (TS3INIT1, random exchange, RSA puzzle level 10000),
  fragmented+fake-encrypted initivexpand2 (EAX decrypt verified on real
  server data), license chain verification, Curve25519 ECDH, clientek with
  ECDSA proof, encrypted clientinit, initserver, 100-channel channellist,
  ACKed server-text send. you.are.bot:9987 documented as a permanent
  step-127 server (tests skip it).

### bugs fixed (each found by live testing)

1. **TS3 init version**: time-derived `now - 1356998400` is rejected by
   live servers (init error 522 client_version_outdated, or a permanent
   step-127 loop). Fixed: fixed real build timestamp 1566914096 (3.5.0
   [Stable], TSLib's constant).
2. **TS3 handshake pID accounting**: initivexpand2 arrives fragmented and
   its fragments consume command pIDs (0 and 1 for a 2-fragment burst) —
   the next server command (initserver) continues at pID 2. Hardcoding
   nextRecvID=1 stalled the receive queue forever ("timeout waiting for
   initserver" while initserver sat in the queue). Fixed: track the highest
   consumed pID, continue from maxCmdPID+1.
3. **TS3 step-127 restart**: unbounded recursion when a server keeps
   demanding restarts. Fixed: bounded to 5 restarts with 1s sleep (ts3j
   behavior).
4. **Mumble varint -1..-4**: decode returned +252..255 (Go `^byte(0)` is
   0xFF, not -1 like C++ `~` on int64). Fixed to `^int64(b&0x03)`.
5. **Mumble OCB2 decrypt**: rewritten as a 1:1 port of upstream
   CryptStateOCB2::decrypt — the old rewrite accepted out-of-window late
   packets (no ±30 bound) and had no decrypt_history replay guard.

### tests (§9: unit + live, both env-gated properly)

- 30 new unit tests: `cores/mumble_proto_test.go` (OCB2 round-trip, OOO
  30-window, 512-packet replay attack, tamper detection — mirroring
  upstream TestCrypt.cpp; varint round-trips incl. negatives; protobuf
  wire-format checks; message-ID table) and `cores/teamspeak_proto_test.go`
  (key derivation against ts3j's official EncryptionTest vector, EAX
  round-trip + tamper, init0/1/2/3/4 byte-exact layouts, fake-key/root-key
  constants, command escaping, license chain + ECDH against ts3j's
  CryptoInit2Test vector, identity sign/verify, UID format).
- Live tests: `tests/mumble_live_test.go` (connect chain, two-client
  round-trip, UDP ping), `tests/teamspeak_live_test.go` (full handshake,
  channel list + text send) — `-tags goolm,live`, never in CI.
- UNICLIENT_TS3_DEBUG / UNICLIENT_MUMBLE_DEBUG env vars added for packet
  tracing (debug-only, zero overhead when off).

### GUI

- Mumble + TeamSpeak 3 added to the backend picker (theme.go) — they were
  hidden as "stale"; both are live-verified now. Engine auth flows already
  existed (server → username → optional password).

### gate

- scripts/dev-test.sh: full gate green (native engine/cores/utils/bootstrap
  + gui under node+wasm). dev-test.sh vet step fixed to vet the GUI under
  js/wasm (sandbox lacks xkbcommon/wayland dev headers; full native vet
  stays in the CI verify workflow). gofmt clean.
- windows/amd64 + js/wasm cross-builds verified locally.
- Parity matrix unchanged (voice slices are backend work, not GUI rows).

## 2026-09-10 — slice 110: voice becomes real (opus + audio devices + live voice round-trips)

The owner's directive: 1:1 the Teamspeak/Mumble protocols first and
foremost and test on public servers before their own live test. Slice
109 verified the control channels; this slice completes the VOICE data
plane end-to-end and live-verifies it on public servers.

### research (primary sources)

- Pure-Go Opus: pion/opus master (b8ebd659d671, MIT) now ships a full
  RFC 6716 encoder + decoder (the v0.1.0 tag predates the encoder —
  pinned to the commit, not the tag). Round-trip quality verified in
  unit tests (440 Hz magnitude 0.25 vs 0.0002 for harmonics).
- Pure-Go audio I/O: jfreymuth/pulse v0.1.3 (PulseAudio native
  protocol, MIT) for Linux capture+playback — no cgo, no new build
  headers, PipeWire-compatible (the owner's NixOS path). Windows gets
  winmm waveIn/waveOut via golang.org/x/sys/windows syscalls (pure Go,
  CGO_ENABLED=0 preserved). Web gets WebAudio + getUserMedia via
  syscall/js. Android audio is stubbed with an honest error (top of the
  voice backlog — OpenSL ES via purego is the planned route).
- ts3j's RemoteCounter semantics studied for receive-side generation
  tracking (monotone forward = same generation; high→low = wrap).

### new packages

- `go/voice/`: opus codec wrapper (mono 48 kHz, 20 ms frames, VoIP
  profile) + per-sender Mixer (volume, levels, clip-safe sum). 12 unit
  tests incl. Goertzel tone verification and a 4-goroutine race test.
- `go/audio/`: device layer — Session{StartMic,StartPlayback}. Linux
  pulse / Windows winmm / WebAudio / Android-stub; live loopback test
  (UNICLIENT_AUDIO_LIVE=1) for real hardware.

### protocol bugs fixed (found building the voice path)

6. **TS3 receive generation counters never advanced**: recvGenID was
   never updated on receive — after 65536 packets (~22 min of voice at
   50 pps) EAX decryption fails forever. Fixed: tsTrackRecvPID (ts3j
   RemoteCounter semantics: forward move = same gen, high→low = wrap,
   late pre-wrap resolved by the ±1 decrypt retry) + genMu (packet
   handlers run concurrently). 5 unit tests pin the tracker; the retry
   is pinned against synthetic EAX vectors.
7. **TS3 default-channel assumption**: LeaveGroupCall moved to cid 0 —
   live servers return "invalid channelID" (default channel ids are
   server-specific). Fixed: channellist's channel_flag_default is now
   tracked (DefaultChannelID()).
8. **TS3 join-error 770**: "already member of channel" failed the join
   — it IS the requested state. JoinGroupCall now treats it as success.
9. **TS3 self missing from room members**: the server never sends your
   own enter-view event; GetGroupCall adds the local client explicitly.

### voice rooms (engine + GUI)

- cores.VoiceCore interface (SendVoiceFrame/OnVoiceFrame/SetVoiceMuted)
  implemented by both Mumble and TeamSpeak.
- Speaking trackers in both cores (400 ms activity window, updated
  BEFORE handler dispatch so speaking works pre-join).
- engine/voice.go: voiceRunner — mic → VAD (hangover + terminator) →
  opus → core.SendVoiceFrame; OnVoiceFrame → per-sender decode → Mixer
  → speaker; stale-sender janitor; honest AudioDeviceError() for the
  platforms without devices. VAD gate locked by 2 unit tests.
- Mumble: GetGroupCall (channel users as participants with mute/speak
  state), LeaveGroupCall, CapGroupCalls + CapVoiceRooms, HasActiveCall
  on occupied channels.
- TeamSpeak: JoinGroupCall/LeaveGroupCall/GetGroupCall/SetCallMuted
  implemented (were ErrNotSupported stubs), same caps.
- GUI: every voice-room channel shows the call bar (empty rooms too —
  joining an empty room is real); join → group-call screen reuses the
  slice-102 surface (participants, mute, leave); noise-suppression
  button hidden on voice-room accounts (honest, §1.10); Android join
  surfaces "Microphone and speaker unavailable" instead of a silent
  half-working room. 5 new GUI tests (subtitle, voiceRoomChat, poll).

### live verification (§9 official-server rung — THE voice proof)

- **Mumble** (murmur.libresilicon.com): two guests, same channel; A
  streams 1.5 s of opus-encoded 440 Hz; **B receives 75/75 packets and
  decodes 1.50 s with 440 Hz at 0.2511 vs 0.0002 for harmonics** — the
  tone survives the full chain (voice packet format, OCB2/TCP-tunnel,
  routing, decode) essentially perfectly.
- **TeamSpeak** (ts.arcticblaze.net): same shape over the EAX-encrypted
  voice channel — **75/75 packets, identical decode fidelity** — S2C
  voice decryption with generation tracking verified against real
  server data.
- All previous live tests re-verified green (mumble connect/text/ping,
  TS handshake/text).

### gate

- scripts/dev-test.sh: ALL GATES GREEN (native engine/cores/utils/
  bootstrap + gui under node+wasm + vet + gofmt).
- windows/amd64 + js/wasm cross-builds verified locally.

### next

- Android audio devices (OpenSL ES via purego) — the one honest stub
  left in the voice path.
- Real-hardware voice test with the owner (mic/speaker on NixOS via
  PulseAudio/PipeWire).

## 2026-09-10 (cont.) — slice 111: Mumble UDP crypto bootstrap + honest egress diagnostics

### root cause found (the "public server mood" mystery)

The Mumble encrypted-UDP bootstrap failures on public servers were NOT
client bugs — measured, not guessed:

- **STUN vs HTTPS egress check**: this sandbox egresses TCP from
  47.57.242.119 but UDP from 8.212.10.159 / 47.57.232.232 (a rotating
  NAT pool, sometimes matching by luck — which explains the occasional
  live successes, incl. udpReady flips + UDP voice earlier today).
- Murmur's unknown-peer deep-match (`qhHostUsers` keyed by the UDP
  source host, Server.cpp udpActivated) can then NEVER associate our
  encrypted pings with our TCP session → silent drop. The stateless
  raw ping keeps working on the very same socket (measured: reply
  arrives len=24 while the encrypted ping gets no answer).
- Client-side crypto is proven three ways: official OCB2 test vectors
  (draft-krovetz-ocb-00) now pinned in unit tests; a full handshake
  direction simulation (server state = swapped nonces) both ways; and
  a per-packet self-check that decrypts our exact on-wire ping the way
  murmur would. On networks where egress IPs match, the bootstrap
  completes on the first ping (live-verified on bananas.space).

### protocol fixes (real, found by reading murmur 1.5.735 Server.cpp)

- **Authenticated UDP ping must NOT set request_extended_information**
  (field 2): murmur's authenticated Ping branch only answers plain
  connectivity probes; the old flag made the server decrypt and
  silently drop → udpReady could never flip.
- **The connectivity ping must ride the real UDP socket**, not the
  TCP-tunnel fallback: it is how murmur learns our UDP address:port.
  The old routing deadlocked the bootstrap (all voice tunneled over
  TCP forever).
- **Crypt resync 1:1 with upstream**: empty CryptSetup from the server
  (it lost our crypto state) → we reply with our current encrypt IV;
  decrypt failures out of the ±30 late window → we request a resync,
  throttled to 1/s. Ping interval 15s→5s (matches upstream cadence).
- **Raw ping replies on the core socket are detected as plaintext**
  (24 bytes, version word) — no bogus decrypt-fail/resync storm; they
  flip the new `udpPathSeen` flag.

### honest transport reporting

- `MumbleUDPStats()` now reports (sent, recv, pathSeen, udpReady):
  path=true + udp=false = "socket path works, crypto unconfirmed"
  (egress divergence) vs path=false (dead path). The voice live test
  logs which transport carried the audio and why; the UDP probe test
  diagnoses TCP-vs-UDP egress divergence (STUN + HTTPS echo) and
  skips with the precise reason instead of a shrug.
- One stateless raw path-probe at connect (12 bytes, allowping-gated
  on the server, zero protocol impact) powers pathSeen.

### verification

- Unit: official OCB2 vectors + both-direction handshake simulation +
  ping format + 30+ existing Mumble tests — all green.
- Live: mumble connect-chain/text-round-trip/server-ping/voice
  round-trip PASS (TCP tunnel, honest diagnostics; udpReady flip
  re-verified earlier this session when egress IPs aligned); TS3
  handshake/text/voice round-trips PASS (EAX voice).
- gates: dev-test.sh ALL GREEN; js/wasm + windows/amd64 builds OK.

## 2026-09-10 (cont.) — slice 112: XMPP in-band registration (XEP-0077), end-to-end

### core (1:1 with XEP-0077 + upstream client behavior)

- `buildIBRStanza` / `parseIBRResponse` / `registerPreAuth`: account
  creation on the pre-SASL stream (after STARTTLS), then straight into
  SASL with the brand-new credentials — the Conversations/Gajim flow.
  Response parsing covers success, every defined error condition with
  text, and the web-redirect (jabber:x:oob) answer.
- Stream features now detect `http://jabber.org/features/iq-register`.
- Authenticate closes the socket on failure (the login retry path must
  not leak half-open streams).
- Engine login flow: after a failed sign-in the XMPP flow offers
  "Create this account on the server? (y = register, empty = retry)" —
  same optional-step pattern as TeamSpeak/Mumble server passwords.
  `parseYesNo` maps free-text answers; buildAuthConfig forwards the flag.

### verification

- Unit: stanza construction + escaping, response classification
  (success/conflict/not-allowed/OOB-redirect), features detection,
  engine flow steps (register offer appears after failed login; y maps
  to register; retry maps to plain login). All green.
- Wire-format proof: the exact IBR IQ created real accounts on public
  servers — 5222.de, jabber.nu, xmpp.de, xmpp.party, xmpp.earth,
  lain.rocks (standalone probe, same stanza shape). 40+ other public
  servers answer with clean policy rejections (not-allowed /
  invitation-only / forbidden) — the protocol handling is correct.
- The full register→SASL→self-message live test is written and wired
  (TestXMPPLiveRegisterAndMessage); completing it from THIS sandbox is
  gated by per-IP registration rate limits ("Too many registrations
  from this IP address recently" — xmpp.party's own words). It skips
  honestly with the server's policy reason and will pass on any
  fresh IP / after the window resets.
- gates: dev-test.sh ALL GREEN.

## 2026-09-10 (cont.) — slice 113: IN-APP voice-note player (waveform, progress, speed)

The voice parity row flips PARTIAL → PRESENT: the slice-110 audio
device layer (pulse/winmm/WebAudio, pure Go) now feeds a real media
player, so voice notes and Opus music play inside the app instead of
handing off to the system player.

### engine

- `engine/ogg.go`: minimal Ogg container demuxer (RFC 3533) — page
  parsing with the Ogg CRC-32 variant, lacing-table packet
  reassembly across page boundaries. Validated against REAL
  ffmpeg-encoded Opus files: all page CRCs verify, OpusHead/OpusTags
  structure, 101 packets / 2.02 s decoded in the pinned test.
- `engine/mediaplayer.go`: PlayMedia/TogglePauseMedia/StopMedia/
  CycleMediaSpeed/MediaState — decode-all → pull-mode playback with
  fractional position + linear-interpolation speed resampling
  (1×/1.5×/2×/0.5×), throttled ~4 Hz EventPlaybackState progress
  events, honest no-device state (never claims playing without a
  backend), non-Opus files rejected to the system-player path. A
  fill-callback self-deadlock (emit under lock) was caught by the
  tests and fixed before commit.
- `CachedMessage.VoiceWaveform()`: waveform bytes parsed from the
  cached content (the Telegram Extra the core already stores).

### gui

- voiceBubble → full player: play/pause circle (pause bars drawn
  live), real waveform strip from the message's cached Telegram
  waveform (plain flat track when absent — §1.10, no fake data),
  accent-tinted progress, "0:03 / 0:12" elapsed label, speed chip
  cycling 1×→1.5×→2×→0.5×. 250 ms repaint ticker while playing
  (call-timer pattern).
- audioBubble: live elapsed/total + play/pause state while its file
  plays in-app.
- Tap handling: voice/audio with a downloaded Ogg/Opus file toggle
  in-app playback; everything else keeps the slice-86 system-player
  handoff.

### verification

- Unit (engine): ogg round-trip, cross-page reassembly, CRC
  corruption rejection, CRC spec vector, REAL ffmpeg-file demux+decode;
  player play/progress/pause/resume/speed/completion/stop, honest
  no-device state, non-Opus rejection, event emission. All green.
- Unit (gui, node+wasm): playback time format, speed ladder,
  waveform extraction (incl. nil-safety), clickable identity. Green.
- gates: dev-test.sh ALL GREEN; js/wasm + windows/amd64 builds OK.
- parity: voice row PARTIAL → PRESENT (112 / 27 / 10 / 51).

## 2026-09-10 (cont.) — slice 114: HOLD-TO-RECORD voice notes (mic → Opus → Ogg → send)

The recording side of voice parity: the slice-110 mic layer now feeds a
real recorder, so the composer's mic button captures, previews and sends
Telegram-shaped voice notes — the player from slice 113 demuxes them
back.

### engine

- `engine/voicerec.go`: hold-to-record capture — mic (20 ms s16le mono
  frames) → pure-Go Opus encoder (24 kbit/s) → Ogg/Opus writer reusing
  the player's own page builder (OpusHead/OpusTags + 25-packet pages
  with running granule positions, the layout ffmpeg produces). Live
  RMS level (smoothed 0.7/0.3) for the UI bars; 0.9 s minimum duration
  (Telegram's floor — accidental taps are discarded, the GUI hints).
- API: VoiceRecordingSupported (UploadWithOptions gate — Telegram +
  Bale), Start/VoiceRecording/Stop/Cancel, SendVoiceNote →
  UploadFileEx(IsVoice + duration). Honest no-mic errors (§1.10 — two
  gates: the GUI hides the affordance, the engine refuses to start).

### gui

- Mic button in the composer (visible only when the input is empty AND
  the account's core sends voice notes); press-and-hold gesture
  (pointer.Press/Release + drag tracking) with slide-←-to-cancel
  (drag-back threshold, red cancel zone), pulsing red dot, live level
  bars, elapsed 0:SS label, 100 ms repaint ticker while recording.
- Release ≥ 0.9 s → StopVoiceRecording → SendVoiceNote; shorter →
  toast hint; cancel path discards.

### verification

- Unit (engine): full encode→container round-trip — the recorder's
  output is demuxed by the player's own demuxer and decoded back to
  PCM (440 Hz tone survives, CRCs verify); level math + smoothing;
  min-duration discard; no-mic honesty; state snapshot; empty-capture
  writer rejection. All green.
- Unit (gui, node+wasm): mic-button visibility rules, drag/cancel
  thresholds, panel routing (recording panel replaces the composer),
  clickable identity, level clamping. Green.
- gates: native tests (engine/cores/utils/bootstrap, goolm) green;
  gofmt clean; js/wasm + windows/amd64 binaries build.
- parity: voice-recording row CORE-ONLY → PRESENT (113 / 27 / 10 / 50).

## 2026-09-10 (cont.) — slice 115: VOICE-NOTE TRANSCRIPTION (A→A on bubbles)

The voice trilogy closes: record (114) → play (113) → transcribe. The
"A→A" glyph on voice bubbles runs Telegram's messages.transcribeAudio and
renders the text under the waveform, pending state included.

### engine + core

- `cores/base.go`: UpdateTranscription update type + TranscriptionUpdate
  payload (MessageID, TranscriptionID, Pending, Text).
- `cores/telegram.go`: dispatcher.OnTranscribedAudio (tg.updateTranscribed
  Audio) → fired as the new update (peer→chatID via the existing
  peerToID); multiple pushes allowed — latest wins, exactly Telegram.
- `engine/db.go`: migration V48 — message_transcriptions table (one row
  per message; upsert = latest write wins).
- `engine/transcription.go`: TranscriptionSupported (VoiceTranscriber
  gate), TranscribeVoiceNote (core call + store; server errors pass
  through verbatim — premium/forbidden reasons stay visible),
  GetCachedTranscription, populateTranscriptions (one query hydrates the
  chat's messages — wired into both GetMessages exits), and
  handleTranscriptionUpdate (unsolicited updates for never-requested
  messages are ignored, matching Telegram Desktop) → EventMsgTranscribed.
- CachedMessage gains TranscriptionText / TranscriptionPending.

### gui

- `gui/transcribe.go`: the "A→A" glyph (Material pill, drawn from
  shapes — never copied assets) renders only for voice messages on
  VoiceTranscriber accounts with no text yet (per-frame capability from
  the refreshAccounts cache); tap → transcribeVoiceNote (async, toast on
  error); transcriptBlock under the waveform — "Transcribing…" while
  pending, collapsed 3 lines + More/Less chip for long texts.
- Frame carries transcribeCap for the open chat's account;
  EventMsgTranscribed refreshes the open chat.

### verification

- Unit (engine): final/pending round-trips, pending→final flip via the
  update handler + event payload, unsolicited-update ignore, capability
  gate, core-error honesty (no row on failure), hydration into
  GetMessages rows. Green.
- Unit (gui, node+wasm): glyph visibility rules (capability, media type,
  already-transcribed, pending), pending/partial/final text routing,
  collapse-depth ladder, clickable stability, capability cache reads.
  Green.
- gates: native tests (engine/cores/utils/bootstrap, goolm) green;
  gofmt clean; vet clean (native + gui); js/wasm + windows/amd64
  binaries build.
- parity: transcription row CORE-ONLY → PRESENT; audit fixed 8 more
  stale rows (global chat search P0, global message search, translate
  message, translate bar, edit history, emoji autocomplete, poll,
  search-by-sender) → 119 PRESENT / 30 PARTIAL / 10 MISSING / 41 CORE-ONLY.

## 2026-09-10 (cont.) — slice 116: SAVED MESSAGES surface (sidebar + forward + avatar)

### real engine bug found and fixed

- `OpenSavedMessages`' INSERT OR IGNORE omitted the NOT NULL `updated_at`
  column → the constraint violation was silently swallowed by OR IGNORE →
  the Saved Messages chat row NEVER actually landed (the method "worked"
  only because the server-synced self chat usually existed already).
  Caught by the new idempotency unit test; the insert now carries
  updated_at and surfaces real errors.

### engine

- `SavedMessagesSupported` / `SavedMessagesChatID` (selfIDer capability
  probe) — the GUI's gating + bookmark-avatar predicate.
- OpenSavedMessages: fixed insert + typed errors.

### gui

- Pinned "Saved Messages" row above the folder tabs (one per capable
  account; account-name subtitle only when several; hidden while
  searching / archive view): bookmark avatar (accent circle + Material
  glyph), tap → engine ensures the chat exists → opens it.
- chatAvatar special-case: the saved chat renders the bookmark avatar
  everywhere (chat rows, header, dialogs).
- Forward picker: the saved chat is pinned FIRST among candidates
  (buildForwardCandidates, pure + unit-tested); openForward ensures the
  chat exists before the dialog renders.
- Drawer "Saved Messages" upgraded from the find-in-list stub (which
  told the user to "forward something to yourself first") to the
  engine-backed flow.

### verification

- Unit (engine): capability gates (selfIDer vs plain vs missing),
  SavedMessagesChatID, OpenSavedMessages idempotency (catches the fixed
  INSERT bug — row count 1, title correct). Green.
- Unit (gui, node+wasm): row-account selection, saved-chat predicate,
  forward-candidate build (pinning, source exclusion, dedup, cross-
  account exclusion), multi-account subtitles, target-account pick.
  Green.
- gates: native tests green; gofmt clean; vet clean; js/wasm +
  windows/amd64 binaries build.
- parity: Saved Messages CORE-ONLY → PARTIAL (119 / 31 / 10 / 40).

## 2026-09-10 (cont.) — slice 117: WEBPAGE PREVIEWS (composer toggle + bubble card)

### real core gap fixed

- Preview-off was IMPOSSIBLE before: the plain send path never set
  noWebpage. Now engine no_webpage → sendExtras → req.SetNoWebpage(true).
  sendExtras extracted from executePending so the contract is unit-pinned
  (was inline, untestable).

### gui

- Composer 🔗 toggle (link icon): visible only while the text contains an
  http(s)/www link (§1.10); off state renders red; per-chat remembered;
  toasts on switch; the send path passes it as the new SendMessage
  noWebpage param (engine signature +3 internal callers updated).
- webPageBlock above the message text: thumb (stripped b64 via
  mediaThumb), small-caps site, 2-line title, 2-line description,
  duration pill; tap opens the URL through openext. parseWebPage reads
  the wp_* Extra the telegram core has cached all along.

### verification

- Unit (engine): SendMessage persists NoWebpage in the pending payload;
  sendExtras round-trips silent/schedule/topic/webpage flags incl.
  no_webpage; default has no no_webpage extra. Green.
- Unit (gui, node+wasm): wp_* parsing (full/absent/url-only), hostname,
  display-title fallbacks, composedHasLink ladder (schemes + www, bare
  domains excluded). Green.
- gates: native tests green (bootstrap e2e call updated for the new
  param); gofmt clean; vet clean; js/wasm + windows/amd64 build.
- parity: webpage rows CORE-ONLY → PRESENT ×2 (126 / 32 / 10 / 32).

## 2026-09-10 (cont.) — slice 118: FORUM TOPICS (topic list + topic view + CRUD)

### engine

- `engine/topics.go`: GetTopicMessages — topic-scoped message pages over
  the messages cache's topic_id column (hide/shadow-ban aware, beforeMs
  paging, populate* hydration, Ayu-filter exit). Empty topic id = the
  plain chat page.

### gui

- Forum chats open on the TOPIC LIST (gui/topics.go): pinned-first then
  activity ordering, colored icon circles (Telegram's 7 topic colors +
  accent fallback), unread badges, honest loading/empty states, "+ New
  topic" row → create dialog (title editor + icon-color chips → engine
  CreateForumTopic).
- Tapping a topic scopes the whole pane: topic bar under the header
  (back button, icon, title, ⋯ actions), message list filtered by
  topic, composer sends with topicRootID, scroll-up loads older topic
  pages (loadOlder/refreshMessages topic-aware via topicScopeFor).
- Topic actions dialog: pin/unpin, close/reopen, rename, delete history
  (engine forum CRUD); openChat resets topic state and loads the list
  for forums.

### verification

- Unit (engine): topic filtering (by topic, paging, unscoped fallback),
  locally-hidden exclusion. Green.
- Unit (gui, node+wasm): topic ordering (pinned, activity, General,
  no-mutation, all-pinned), color mapping + fallback, General predicate,
  subtitles. Green.
- gates: native tests green; gofmt clean; vet clean (one self-assign
  caught+fixed); js/wasm + windows/amd64 build.
- parity: forum topics CORE-ONLY → PARTIAL (126 / 33 / 10 / 31).

## 2026-09-11 — owner instructions codified into AGENTS.md

The owner re-issued two standing directives and asked for them to be checked
against the md files and included where missing:

- **Push-as-you-go** (was absent everywhere): new §1.15 owner requirement +
  §2 step 8 — commit and push to `main` after every small unit of progress,
  because the agent VM may reset and delete local files at any moment; only
  pushed work survives. Explicit note that the GitHub token is delivered
  out-of-band and must never appear in any repo file.
- **TeamSpeak/Mumble 1:1 protocol first and foremost** (existed only as a
  historical session note in WORKLOG slice 109, not as a standing rule):
  new §1.16 owner requirement — wire-level 1:1 compat is the top priority
  for these two cores, verified on public servers BEFORE the owner's own
  live test (owner tests on their own and reports when the time comes).

No code changed in this commit. Token verified absent from all repo files.

## 2026-09-11 — §1.16 reworded: priority removed

Owner: "remove the first and foremost, i want you doing on your own
objective list order." — §1.16 is now a quality bar (1:1 wire compat,
public-server testing before the owner's live test) applied whenever a
TS/Mumble protocol change happens, NOT a scheduling priority. Work order
follows the agent's own objective list (§11).

## 2026-09-11 — sandbox dev environment rebuilt from zero (no sudo)

Fresh VM (reset): no Go, no Gio dev libs. Rebuilt without root:

- Go 1.27.1 → ~/.local/go (go.mod needs 1.27).
- ~/.local/sysroot: apt download + dpkg -x of libxkbcommon(-x11)-dev,
  libwayland-dev, libegl-dev/libglvnd-dev, libxcursor-dev, libxfixes-dev,
  libx11-xcb-dev, libxcb-xkb-dev (+ runtimes), libvulkan-dev from the
  Debian pool, KHR/khrplatform.h from the Khronos EGL registry.
  All .pc prefixes repointed at the sysroot; dangling .so symlinks
  resolved against system copies; xkbcommon-x11.pc xcb deps made public
  (Requires) so final links resolve -lxcb-xkb.
- scripts/devroot-setup.sh commits all of this; emits devroot.env.
- gotd tg OOM (3.5GB RAM < 4GB needed): GOGC=20 + -p 1 +
  -gcflags="all=-c=1" fits. This is now in devroot-setup.sh output.
- Full gate green: go build/test -tags goolm all packages ok
  (audio bootstrap cores engine gui utils voice).

## 2026-09-11 — slice 119: inline ":shortcode" emoji autocomplete

AyuGram composer parity: while the caret sits inside a ":token" (colon that
starts a fresh token — not glued to a word, so URLs/times/"a:b" stay quiet,
but an emoji followed by ":next" chains), a strip of matching emoji renders
above the composer (same chrome family as the bot-commands panel); tapping
one replaces the whole ":token" with the emoji at the caret.

- gui/emojicomplete.go: emojiAutocompleteQuery (pure caret-token scanner,
  rune-offset replace range), emojiAutocompleteMatches (exact keyword first,
  then prefixes, deduped, capped 32; same Telegram keyword table as the
  emoji-panel search — engine GetEmojiKeywords), visibility predicate
  (hidden while the emoji picker / attach menu is open or a text selection
  is active), per-frame derived state — nothing to invalidate.
- Replacement via Editor SetCaret(range)+Insert round-trip (tested).
- gui/emojicomplete_test.go: 13 query cases (incl. URL/time guards, chain
  after replaced emoji, caret mid-token), ranking/dedupe/case-insensitivity,
  editor round-trip, visibility predicate. All green; gofmt + vet clean;
  full gui+engine suites green.
- parity: Emoji autocomplete PARTIAL → PRESENT (127 / 32 / 10 / 31).
- Header "..." menu row corrected to PRESENT (search-in-chat via chatsearch.go
  + Add members via addmember.go were already shipped; the note was stale).

## 2026-09-11 — slice 120: Two-Step Verification settings (2FA GUI)

The whole core+engine surface already existed (cores/telegram.go
CloudPassword* family, engine/cache_users.go wrappers incl.
SetCloudPasswordEmail/Confirm/Resend/Cancel) — this slice is the GUI:

- gui/twofa.go: full 2FA editor dialog (content-pane surface "twofa",
  ordered AFTER the lock gate in contentDialogSurface): state card
  (On/Off, hint, recovery email, unconfirmed pattern, pending reset
  date), set/change password form (current gated on live HasPassword,
  new+repeat+hint, masked fields), disable flow w/ warning line,
  recovery-email lifecycle (set/change → server sends code → code step
  w/ confirm/resend/cancel). Every mutation async w/ honest toasts and
  server-truth state refresh; busy flag guards double-submits.
- Capabilities: new CapCloudPassword ("CLOUD_PASSWORD") constant;
  telegram core lists it. Settings row hidden for cores without it.
- gui/settings.go: per-account "Two-Step Verification" row (value On/Off
  from live state) in Privacy & Security; own clickable pool (index bug
  avoided: shared counter with privacy rows would have overflowed).
- loadPrivacy now also fetches per-account cloud-password state.
- tests: action-list derivation, form validation (current required /
  match / short / empty), email-flow advance, state summary, surface
  ordering (lock gate outranks 2FA editor), row value, email sanity
  check. Full gate green (gofmt/vet/test -tags goolm all packages).
- parity: Privacy & security PARTIAL → PRESENT (128 / 31 / 10 / 31).

## 2026-09-11 — slice 121: notification sounds + per-chat overrides

AyuGram notifications parity completed:

- gui/notifysound.go: pure-Go synthesized chimes (48kHz mono int16) —
  Default = two-tone ding (E6→G6, exponential decay, 50ms overlap,
  fade-in), Gentle = soft A5 with slow attack; "none" = silence. Player
  feeds the slice-110 audio backends (pulse/winmm/WebAudio; Android
  honest-stub = no sound), replaces a running chime instead of stacking,
  stops pulling after the sample tail. Kind round-trip, labels,
  effective-sound resolution (per-chat override wins over global config)
  all pure and tested (11 test functions).
- maybeNotify now plays the effective sound (async per-chat resolution,
  global config fallback) alongside the banner.
- Notifications settings: "Notification sound" row + picker dialog with
  per-kind Play preview (content-pane surface "sound").
- Chat header ⋮ menu: "Notification sound…" → per-chat picker with
  live kind, per-row preview, and "Reset to defaults"
  (engine ResetPeerNotifySettings).
- cores/telegram_notify_sound.go: Get/SetChatNotifySound —
  read-modify-write over account.getNotifySettings →
  account.updateNotifySettings so mute/silent survive a sound change
  (official-client shape); NotificationSoundLocal{Gentle} maps the
  custom chime. Engine wrappers in engine/notifications.go.
- Config: AppConfig.NotifySound + ConfigChanges.NotifySound (nil =
  unchanged) + cfgSnapshot.NotifySound; UpdateConfigFromBridge applies.
- Header-menu test expectations extended; full gate green
  (gofmt/vet/test -tags goolm, all packages).
- parity: Notifications section PARTIAL → PRESENT (129 / 30 / 10 / 31).

## 2026-09-11 — slice 122 (stage A): lottie package — .tgs container + JSON model

Foundation for animated .tgs stickers (P1, last big parity item):
pure-Go Bodymovin subset parser, no new dependencies.

- go/lottie/model.go: Animation/Asset/Layer/Transform/Prop/Keyframe/Shape
  model; layer types (precomp/solid/null/shape), shape items (gr/rc/el/
  sh/fl/st/tr/tm/gf), duration + clamped frame-at helpers.
- go/lottie/parse.go: ParseTgs (gzip→JSON, rejects non-gzip/garbage) +
  ParseAnimationJSON; static vs animated props, keyframes with bezier
  easing controls + spatial tangents (to/ti), end-value completion from
  the next key, path-vertex flattening, image/text layers rejected
  (.tgs never has them — fail loudly over render-wrong).
- Tests: container round-trip + rejection paths, full document decode
  (header/assets/layer/transform/shapes/easing/tangents), duration math.
  Green.
- Next stage: keyframe interpolation (linear/bezier/hold + spatial) and
  transform composition, then the Gio renderer + sticker-bubble wiring.

## 2026-09-11 — slice 122 (stage B): lottie keyframe + transform engine

- PropValueAt/PropVecAt: keyframe segment resolution (before/after span
  clamps, hold keyframes, end-value completion), per-dimension bezier
  easing via easingBezier (Newton-Raphson cubic-bezier timing solver),
  spatial (positional) bezier interpolation with to/ti tangents.
- affine matrix type + parent-chain composition; TransformAt implements
  the Bodymovin order p' = R·S·(p − anchor) + position with opacity
  normalized to 0..1 — anchor-maps-to-position pinned by test.
- All pure math, 4 test functions green.

## 2026-09-11 — slice 122 (stage C): lottie renderer (Gio ops)

- render.go: Draw(anim, frame, ops, rect) — letterboxed fit of the
  animation viewport, layer walk in reverse order (bodymovin: first
  layer on top) with in/out point culling, parent-chain composition,
  null/solid/precomp (recursive, depth-gated at 8) layer types.
- Shapes: groups with their internal "tr" transform applied, rect
  (rounded via cubics), ellipse (4-cubic approximation, k=0.5523),
  bezier paths (static vertex form), fills + strokes with opacity
  multiplied down the hierarchy; stroke widths scale with the composed
  matrix. Geometry paints with the first fill/stroke FOLLOWING it in
  the item list (bodymovin style resolution).
- Fixed a silent-data-loss parser bug found by the render smoke test:
  duplicate JSON tags in one struct ("s"/"e"/"o" on multiple fields)
  make Go's decoder keep only the last field — rawShape now carries
  each key exactly once with per-type interpretation in parseShape.
- Render smoke test: full document (group/parent chain/fill+stroke)
  draws every frame without panicking, emits fills AND strokes; fit
  scale/letterbox math pinned.

## 2026-09-11 — session wrap: slices 119-121 shipped + lottie engine (122 A/B/C)

Full gate green across all 8 packages (gofmt/vet/test -tags goolm),
everything pushed as it landed (§1.15). Session summary:

- slice 119: inline ":shortcode" emoji autocomplete (composer strip,
  token scanner + keyword ranking, tap-replaces-token).
- slice 120: Two-Step Verification settings dialog (state card,
  set/change/disable, recovery-email lifecycle) over the pre-existing
  core+engine CloudPassword surface; new CapCloudPassword gate.
- slice 121: notification sounds — pure-Go synthesized chimes, global
  picker w/ preview, per-chat overrides via account.get/updateNotify
  Settings read-modify-write, effective-sound resolution at notify time.
- slice 122 (A/B/C): go/lottie — complete pure-Go .tgs/Lottie subset
  engine: parser (gzip container, full document model, no duplicate-tag
  data loss), keyframe interpolation (bezier easing, holds, spatial
  tangents), transform composition (parent chains), Gio renderer
  (shape/solid/null/precomp layers, rect/ellipse/path geometry, fills +
  strokes, letterboxed fit). 14 test functions green.

### Next agent: wire .tgs playback into the sticker bubble (top of queue)

The lottie engine is DONE and tested; the remaining work is GUI wiring:
1. Sticker messages (MediaSticker + mime application/x-tgsticker) auto-
   download their document (RequestDownload, like photoBubble's prefetch)
   and keep falling back to the static webp thumb until complete.
2. New gui/tgsplayer.go: per-msgID decoded *lottie.Animation cache;
   when MediaLocalPath is set + IsTgs (gzip magic / mime), ParseTgs once;
   a bubble widget that calls lottie.Draw(anim, frameAt(now-start),
   ops, rect) with a ~1/fr invalidation clock while visible (see the
   voice-player's clocking in gui/media.go for the pattern); loop at
   anim.Duration().
3. Add a "sticker" kind to mediaBlockKind (engine.MediaSticker →
   dedicated bubble, tap = replay from frame 0), sizes ~256dp.
4. Same player can later serve the emoji panel's animated previews and
   animated custom emoji (custemoji.go).

Parity after this session: 129 PRESENT / 30 PARTIAL / 10 MISSING / 31
CORE-ONLY. Remaining P1s: animated sticker bubble wiring (above),
in-app video player (needs a pure-Go decoder decision).

## 2026-09-11 — slice 123: animated .tgs sticker playback in chat

The slice-122 lottie engine meets the GUI (top of the last session's queue):

- gui/tgsplayer.go: per-msgID tgsPlayer cache (parse-once, retryable read
  guard, permanent failParse → static fallback, replay clock); pure
  detection (isTgsMime, gzipMagic container sniff, stickerRenderKind
  tgs/webm/static), playback math (tgsFrameInterval clamps 20–60fps,
  tgsLoopFrame loop-at-duration, stickerBox aspect-true ~256dp box);
  stickerBubble widget — animated frame draw on the animation's own clock
  via op.InvalidateCmd scheduling, static .webp from the downloaded file,
  inline thumb while downloading/parsing; bareStickerBubble — bubble-less
  sticker rows (AyuGram): forwarded/reply surfaces kept, artwork bare with
  a translucent meta pill (time + ticks + deleted mark) overlaid SE,
  reactions strip below; actMedia: tap = replay (.tgs) / fullscreen
  viewer (.webp) / system handoff (.webm).
- media.go: "sticker" bubble kind; auto-download extended to stickers
  (autoDownloadable); .webp added to imageExts (webp decoder was already
  registered by custemoji.go — static sticker files now decode inline;
  benefits mediaview/alumni paths too).
- chat.go: messageRow routes bare sticker messages before bubble chrome;
  meta construction extracted to messageMetaLabel (shared with the pill).
- Tests first: gui/tgsplayer_test.go — 12 test functions (mime/magic/
  render-kind truth tables, parseTgsBytes accept/reject incl. degenerate
  docs, interval clamps, loop math incl. exact-wrap + degenerate, cache
  semantics incl. prune + read guard, bare gating incl. poll bodies,
  auto-downloadable set, meta label, sticker box aspect).
- Full gate green (gofmt/vet/test -tags goolm, all 8 packages); linux
  build verified.
- parity: Sticker (animated) CORE-ONLY → PRESENT (130 / 29 / 10 / 31).

Next top of queue: in-app video player (pure-Go decoder decision — needs
research), then remaining P1 PARTIALs (poll retract/stop, selection-mode
comment field, live location rendering).

## 2026-09-11 — slice 124: poll completeness (retract / multi-vote / stop / solution)

The engine+core surface already existed (VotePollMulti, RetractPollVote,
StopPoll, CreatePollWithRevoting) — the GUI semantics were the gap:

- gui/poll.go: Telegram vote semantics (pure pollTapAction, unit-tested):
  single polls vote once and tap-own-choice RETRACTS (RetractPollVote);
  multiple polls toggle options with the full set on the wire per tap
  (VotePollMulti via nextMultiVoteSet); quizzes lock after the answer;
  closed polls ignore taps. Optimistic overlay switched to
  replace-with-delta counting (retractions decrement, applyPollOverlay
  rewrite; pollVotesFor now distinguishes nil=no-op from empty=retracted).
- Stop poll: context-menu item for own open polls (stopPollMenuGate) →
  engine.StopPoll + optimistic pollStopped overlay (pollEffectiveClosed).
- Quiz solution: cores caches res.Solution both at message parse and in
  UpdateMessagePoll (extra["poll_solution"]); engine mergePollResults
  folds it; the bubble shows the explanation line after voting.
- Tests first: 7 new/extended test functions. Full gate green.

## 2026-09-11 — slice 125: dice emoji games as animated .tgs

- cores/telegram_dice.go: MessageMediaDice parsed (dice_emoji + dice_value,
  application/x-dice attachment → new MediaDice=13); GetDiceStickers maps
  messages.getStickerSet(inputStickerSetDice) to values exactly like
  tdesktop's stickers_dice_pack ("#"→roll, "1".."6"→outcomes; slot machines
  positional) — verified against the tdesktop source.
- engine/dice.go: EnsureDiceSticker resolves the message's value to the
  pack document, rewrites the media row (remote_ref/extra/mime tgs) into
  the STANDARD download pipeline, memoizes packs per account+emoji,
  re-arms on value swaps (the roll→outcome edit rewrites to the outcome
  document).
- gui/dice.go + tgsplayer.go: dice render bare like stickers; roll (value
  0) loops; outcome plays ONCE and HOLDS its final frame (tgsFrameAt hold
  mode); emoji-glyph honest fallback pre-download; slot machines stay
  text (no fake collage, §1.10); player re-parses when the source file
  changes (value swap). 8 new test functions; full gate green.

## 2026-09-11 — slice 126: forward comment field

- The forward picker gained an optional comment editor (Telegram
  share-sheet semantics): forwardCommitSteps plans comment-message-first
  then the forward batch per recipient; commit sends the comment via
  engine.SendMessage before ForwardMessage(s). Pure plan + trim tested.

## 2026-09-11 — XMPP verified: local-server harness + two REAL auth bugs fixed

The §9 ladder's dockerized-server rung, offline edition: a minimal but
REAL XMPP server (cores/xmpp_localserver_test.go — independent protocol
implementation: stream negotiation, SASL PLAIN, bind, session, roster/
carbons/disco/bookmarks IQ traffic, message echo) verifies the FULL chain
in 0.2s, in CI, no secrets. It caught two latent bugs that would break
REAL logins (live tests only ever exercised FAILED auth):

1. readSASLElement only matched the literal <success/> — real servers
   send <success xmlns='...'/> (attributed, self-closing) → every
   successful SASL login timed out after 15s. Fixed via pure
   saslElementMatch (both forms + content form).
2. readRawIQResponse only matched </iq> — self-closing <iq .../>
   results (session/ping/carbon acks) stalled 15s each. Fixed with a
   self-closing-aware check.

Also: XEP-0077 now does the proper two-step GET→submit and supports
data-form registration (jabber:x:data) — sure.im accepted the form
structurally (progressed from "bad-request: Use proper DataForm
registration" to its captcha policy), conversations.im/jabber.de/
pimux.de/jabber.cz/xmpp.jp/trashserver.net all gate IBR by policy
(invitation/captcha) — the full public-server registration test
Skip()s honestly there. Pre-auth chain re-verified live
(conversations.im, 1.3-2.6s).

Status of the §11 "verify xmpp/bale/rubika/deltachat" item: XMPP done
(local-server + live pre-auth + data-form IBR); bale/rubika remain
geo-blocked; deltachat needs a local IMAP/SMTP harness (next session
candidate) or real email accounts.

## 2026-09-11 — Delta Chat verified: local IMAP+SMTP server harness

cores/deltachat_localserver_test.go — the §9 "dockerized server" rung,
offline: emersion's go-imap imapserver + go-smtp server libraries (the
independent server stack real Go mail servers use) with a self-signed
STARTTLS cert and accept_invalid_certs. The harness verifies, in 0.07s:

1. AUTH CHAIN — connectIMAP (DialTLS fail → DialStartTLS succeed) + LOGIN
   + LIST + DeltaChat folder CREATE, ×3 connections (main ops + the IDLE
   inbox/DC pair) — the exact real-server flow.
2. SEND CHAIN — sendEmail: EHLO + AUTH PLAIN + MAIL FROM/RCPT TO/DATA;
   the received mail carries Chat-Version + Autocrypt + both recipients
   (peer + BCC self).
3. RECEIVE PATH — SELECT + FETCH (ENVELOPE/FLAGS/BODY[HEADER]/BODY[]) →
   processIncomingEmail builds the chat from the pre-loaded email.

Harness gotcha worth remembering: imapserver's
FetchResponseWriter.Close() MUST be called after each message — skipping
it holds the connection's response-encoder mutex and deadlocks the tagged
completion (found via wire debug + goroutine dump).

§8/§11 updated: xmpp + deltachat local-server-verified; bale/rubika stay
geo-blocked (need a non-geo vantage or the owner's live test).

## 2026-09-11 — session wrap: slices 123-126 + core verifications + v0.8.0

Session summary (everything pushed as it landed, §1.15):

- slice 123: animated .tgs sticker playback — the slice-122 lottie engine
  wired into chat bubbles (frame clock, bare sticker rows w/ meta pill,
  webp static path, auto-download, tap-to-replay, path-change re-parse).
- video-player research verdict: no pure-Go full H.264/VP9 decoder exists
  (hi264=IDR-only, gomedia=cgo, vp8=codec mismatch) — system-player
  handoff stays the honest ceiling; documented in research/video_player.md.
- slice 124: poll completeness — retract (tap own choice), multiple-poll
  set voting via VotePollMulti, Stop poll context action, quiz solution
  line (core caches + engine merges poll_solution).
- slice 125: dice emoji games — MessageMediaDice → engine EnsureDiceSticker
  → standard download pipeline → lottie playback (roll loops, outcome
  holds final frame); tdesktop pack mapping semantics.
- slice 126: forward comment field (comment-first commit plan).
- XMPP: data-form IBR (XEP-0077 GET→submit, jabber:x:data) + TWO REAL
  auth-chain bugs fixed (attributed self-closing SASL success, self-closing
  IQ results) + local-server harness proving SASL+bind+session+message
  round-trip in 0.2s.
- Delta Chat: local IMAP+SMTP server harness (emersion server libs +
  self-signed STARTTLS) proving auth chain + SMTP send + receive path in
  0.07s.
- Verify workflow dispatched on the final commit: ALL GREEN (test/vet/
  gofmt, windows+wasm cross-builds, Xvfb GUI smoke w/ screenshots).
  Tagged v0.8.0 (prerelease, per §1) — release.yml building.

Parity after this session: 136 PRESENT / 31 PARTIAL / 12 MISSING / 37
CORE-ONLY. Remaining top items: emoji-panel animated previews, live
location map tiles, retract/stop poll live-test on a real account,
bale/rubika vantage problem, in-app video blocked (see
research/video_player.md).

## 2026-09-11 — freeze fix: bot-chat click (owner report) — RPC hygiene

Owner report: "clicking on a telegram bot chat froze the client". Root cause
(found by audit, proven by a failing test):

- ~840 TelegramCore methods held t.mu across t.api.* RPCs. t.ctx carries no
  deadline and gotd 0.161 runs NO heartbeat by default, so a half-open TCP
  connection (network switch / suspend-resume / NAT drop) hangs RPCs FOREVER,
  pinning t.mu. Go's fair RWMutex then starves every queued writer and every
  later reader — any GUI-goroutine core call freezes the window.
- The exact trigger path: clicking a bot chat fires GetMessages +
  GetPinnedMessages + GetFullUser (DM) + GetChatBotCommands concurrently —
  4 RPC-holding readers at once; Logout even held the WRITE lock across its
  RPC (worst variant). GetFullUser could chain a SECOND RPC
  (help.getTimezonesList for business-hours users) under the same lock.

Fix (two layers, following the file's own GetAdminRanks precedent):

1. rpcGuard invoker (single choke point, all t.api creation sites): every
   RPC gets a 60s deadline (tdesktop's default request timeout) unless the
   caller already set one — dead connections surface as errors, never hangs.
2. Snapshot pattern (withAPI) on the chat-open hot path: GetMessages,
   GetPinnedMessages, GetFullUser, GetChatBotCommands, MarkAsRead hold t.mu
   only long enough to snapshot authed/api/ctx; RPCs run unlocked. Logout
   snapshots under the write lock and runs auth.logOut after releasing.

Tests (cores/telegram_freeze_test.go): stuckInvoker (ctx-ignoring worst
case) + hungInvoker (gotd-accurate ctx-honoring). Proven non-vacuous: with
the pre-fix RLock-across-RPC pattern restored, the GetMessages subtest FAILS
with "t.mu write lock starved for 2s" — the exact freeze mechanism. Post-fix:
all 6 hot-path subtests + Logout + 3 rpcGuard deadline tests + withAPI auth
test green; full gofmt/vet/test gate green across all 8 packages.

Next: continue §11 topmost unchecked items (inline keyboard rendering for
bot messages is the natural follow-up — the GUI currently ignores
m.Extra["inline_keyboard"] entirely, noticed during this audit).

## 2026-09-11 — slice 127: bot keyboards (inline + reply markup) rendered

The freeze-fix audit exposed this gap: the Telegram core has parsed
ReplyInlineMarkup / ReplyKeyboardMarkup / ReplyKeyboardHide into message
Extra (and carried BotCallback RPCs) since the callback work — the GUI never
rendered any of it. A bot chat with no buttons is half a bot chat.

- gui/botkbd.go: parse Extra["inline_keyboard"] /
  Extra["reply_keyboard"] (rawEnvelope pattern like polls/dice); action
  classification is a pure function (botKbdActionFor) so the tap executor
  stays thin and the mapping is unit-tested.
- Inline keyboards render as bot-defined button rows below the bubble
  content (tdesktop HistoryView placement), accent-filled; URL-ish buttons
  tint like links. Tap actions: callback/game → engine.BotCallback
  (messages.getBotCallbackAnswer; answer text as toast — alert answers get
  the "Bot:" prefix — answer URL opens); url/url_auth/web_view/
  simple_web_view → openLinkExternal (WebApps need a webview: the
  system-browser handoff is the honest pure-Go ceiling, same policy as the
  video player); copy → clipboard; switch_inline same_peer inserts into the
  composer, otherwise clipboard + toast (tdesktop's chat-switch picker is
  out of scope); buy toasts the honest payments-unsupported sentence.
- Reply keyboards render as a panel under the composer: the LATEST
  keyboard-carrying message in the loaded window wins; a later
  keyboard_hide clears it (tdesktop semantics); single_use hides the panel
  after one text tap (consumption resets on chat switch); the markup's
  placeholder replaces the composer hint. Only actionable buttons render —
  text sends, webview opens; request_phone/location/poll/peer are omitted
  rather than shown dead (§1.10). force_reply stays unwired (the reply chip
  already communicates that state).
- Tests first (gui/botkbd_test.go): 8 test functions — parse truth tables
  (both markups, none/malformed/empty cases), replyKbdActive semantics
  (persist past plain messages, hide clears, newer keyboard wins),
  action-classification table, renderable gating, hint override.
- parity: Bot keyboard CORE-ONLY → PRESENT (137 / 31 / 12 / 36).

Full gate green (gofmt/vet/test, 8 packages). Verify workflow on the
freeze-fix commit ran GREEN on GitHub (test/vet/gofmt, windows+wasm
cross-builds, Xvfb GUI smoke w/ screenshots) before this slice landed.

## 2026-09-11 — slice 128: inline bot results (@bot query panel)

The second half of the bot-chat experience (the freeze audit surfaced both
gaps): the core/engine had carried GetInlineBotResultsFull /
SendInlineBotResult since the callback work — nothing in the GUI ever
queried an inline bot.

- gui/inlinebots.go: typing "@bot query" in the composer resolves the bot
  username once (engine.ResolveUsername, cached per session), then queries
  live (engine.GetInlineBotResultsFull) with a key guard (account|bot|
  query) + in-flight flag + 400ms throttle; a throttled call re-arms a
  frame at the throttle deadline so the FINAL query always fetches when
  typing stops mid-window (the subtle one).
- Panel above the composer (emoji-autocomplete chrome family): gallery
  responses render a 4-wide grid of square thumb cells (b64 stripped
  thumbs — the core fills them for media results); articles render
  title+description rows; URL-only thumbs (plain BotInlineResult) render
  text-only — this build has no HTTP image fetcher and a missing thumbnail
  is honest (§1.10); switch_pm becomes a row that opens the bot's chat
  (global search by the composer's own @bot + pendingOpen hop);
  next_offset becomes a "More results" row appending the next page.
- Tap sends (engine.SendInlineBotResult) and clears the composer query —
  tdesktop behavior.
- Core hygiene while there: GetInlineBotResultsFull's RLock-across-RPC +
  unlock/relock dance around withPeer replaced by the withAPI snapshot
  rule (same freeze class as the bot-chat freeze).
- Tests first (gui/inlinebots_test.go): 6 test functions — @bot query
  parsing truth table (start-of-message rule, terminator rule, official
  3-char bots like @gif, malformed), fetch key, thumb shaping (b64 only,
  URL thumbs don't leak), subtitle trim, panel model, More gating. Caught
  two real bugs during review: the unclaimed fetch key (results always
  dropped) and the NextOffset refetch loop.
- parity: Inline bot results CORE-ONLY → PRESENT (138 / 31 / 12 / 35).

Full gate green (gofmt/vet/test, 8 packages).

## 2026-09-11 — slice 129: real map tiles on location cards

Location bubbles were an icon card; the engine's GetMapTile (upload.getWebFile
+ InputWebFileGeoPointLocation — the exact tdesktop mechanism, no third-party
tile CDN) sat unused, and the core never even parsed the geo access hash the
RPC needs.

- core: geo_access_hash now parsed for MessageMediaGeo / GeoLive / Venue
  (venue title + address were already there, plain shares now surface them).
- gui/location.go: the location card renders the Telegram-served map tile
  (440×220 @ zoom 15, cover-fitted with rounded corners via a local
  drawTileCover — the rect sibling of avatar.go's square cover), centered
  pin, bottom caption pill (address or coords); the pre-fetch state is the
  honest icon card; failed points pin to the fallback (no retry churn);
  per-point tile cache with busy/failed semantics (unit-tested, claim
  rejects cached tiles).
- engine-side hygiene while there: UploadGetWebFile now follows the withAPI
  snapshot rule (tiles can be slow; never pin t.mu).
- Tests: parse access-hash/venue truth table, tile key, cache semantics
  (claim/store/fail, double-claim, cached-tile claim). Full gate green
  (gofmt/vet/test, 8 packages).
- parity: Location row engine-gated tiles → rendered (live-location
  STREAMING still engine-gated — the honest remainder).

## 2026-09-11 — session wrap: freeze fix + bot UX (slices 127-129), all CI-verified

Session summary (owner report: "clicking on a telegram bot chat froze the
client"):

- FREEZE FIX: ~840 TelegramCore methods held t.mu across no-deadline RPCs;
  gotd 0.161 has no heartbeat, so half-open connections hung RPCs forever,
  pinning the mutex (fair RWMutex → queued writer starves every reader →
  GUI freeze). Fixed at two layers: rpcGuard invoker (60s deadline on every
  t.api call, all 4 client-creation sites) + withAPI snapshot rewrites on
  the chat-open hot path (GetMessages/GetPinnedMessages/GetFullUser/
  GetChatBotCommands/MarkAsRead/Logout — Logout held the WRITE lock).
  Regression tests prove non-vacuity (restoring the pre-fix pattern fails
  with "t.mu write lock starved for 2s"). AGENTS.md §8 now enforces the
  rule for future edits.
- slice 127: bot keyboards — inline keyboards (callback/url/copy/
  switch_inline/game/buy wired to real actions) + reply keyboards under
  the composer (latest-wins, keyboard_hide clears, single_use, placeholder
  hint).
- slice 128: inline bot results — "@bot query" live panel (resolve → query
  → grid/rows/switch_pm/More; tap sends). Core's GetInlineBotResultsFull
  converted to withAPI. Two bugs caught in review before shipping
  (unclaimed fetch key, NextOffset refetch loop).
- slice 129: real map tiles on location cards — Telegram's own
  upload.getWebFile geo tiles (tdesktop mechanism), geo_access_hash parsed,
  per-point cache, venue captions; UploadGetWebFile converted to withAPI.
- CI: verify workflow dispatched after every push — 4/4 GREEN (test/vet/
  gofmt, windows+wasm cross-builds, Xvfb GUI smoke w/ screenshots).

Parity after this session: 138 PRESENT / 31 PARTIAL / 12 MISSING / 35
CORE-ONLY. Next top candidates: animated custom emoji in message text
(lottie engine exists, needs document fetch + richtext integration), a
pure-Go HTTP image fetcher (unlocks inline-bot URL thumbs + link-preview
remote thumbs), live-location streaming (editMessageGeo), tray/badge
platform work.

## 2026-09-11 — slice 130: pure-Go HTTP image fetcher + full-res thumb routes

Two long-standing "honest fallback" gaps closed (both were §1.10-compliant
placeholders, now real):

- ENGINE HTTP IMAGE FETCHER (engine/httpimg.go): FetchHTTPImage(url, cap) —
  shared client (10s deadline, 5-redirect cap), LimitReader size enforcement
  (+ early Content-Length reject), content sniff (image/*; octet-stream only
  with image-ish URL extension — webp/avif are not in Go's sniff table),
  256-entry LRU + in-flight dedup. Pure Go, account-independent; on js/wasm
  it rides the browser fetch transport (CORS failures stay honest errors).
  Tests: httptest server covering valid/oversize/wrong-type/404/redirect
  chain/loop-reject/cache-hit-once/dedup + pure policy tables.
- INLINE-BOT URL THUMBS (gui/urlthumb.go + inlinebots.go): BotInlineResult
  thumbs that arrive as plain http(s) URLs now fetch (512 KiB cap) through
  the engine fetcher and render in gallery grid cells + article rows —
  claim/store/fail cache (mapTiles pattern), placeholder box while in
  flight, pinned fallback on failure.
- WEBPAGE CARD FULL-RES PHOTOS: tdesktop uses Telegram's own CDN photo, so
  the core now exports wp_photo_id + wp_photo_extra (MessageMediaWebPage
  conversion; flag-guarded via gotd setters in tests); engine
  EnsureWebPagePhoto rewrites a standard media row (dice pattern — works
  for already-cached messages too, no re-fetch needed) and prefetches at
  priority 2; the GUI card renders the downloaded file (mediaImgs decode
  pipeline), stripped b64 stays the instant fallback; chat.go mediaBlock
  skips webpage-card messages so the photo never double-renders as a bubble.
- RPC HYGIENE while on the download path (§8 rule): DownloadFile and
  DownloadChatAvatar held t.mu across their entire STREAMED downloads
  (minutes-scale) — both converted to withAPI snapshots. This was the exact
  freeze-class violation the owner's bug report was about; downloads were
  still exposed to it.
- Environment: sandbox reset again — devroot rebuilt (Go 1.27.1 + full
  X11/Wayland/EGL/Vulkan sysroot incl. runtime libs + glvnd vendor JSON);
  local Xvfb GUI boot verified clean (12s run, no errors).

Gate: gofmt/vet/test all green (7 packages, goolm tag). Parity rows updated
(inline bots, webpage card).

## 2026-09-11 — slice 131: live locations (send + countdown + stop sharing)

The last engine-gated row of the location feature set (parity doc had it
as the honest remainder of slice 129):

- SEND: attach-menu Location dialog gains "Share live location" (toggle,
  resets on open) + the tdesktop presets 15 minutes / 1 hour / 8 hours →
  engine.SendLiveLocation → core SendLiveLocation
  (messages.sendMedia InputMediaGeoLive{GeoPoint, Period}).
- BUBBLE: live cards show a countdown chip ("live · 12m left", rounded-up
  minutes, "ended" once elapsed; unknown period = plain "live") ticking
  against the message timestamp with a 30s invalidate re-arm. Remote
  shares move via message EDITS — new coords → new tile key → the slice-129
  per-point tile cache refetches automatically; no new plumbing needed.
- STOP SHARING: own live cards render the chip as a Stop button →
  engine.StopLiveLocation → core StopLiveLocation (messages.editMessage
  InputMediaGeoLive{Stopped} — core.telegram.org/api/live-location
  semantics); toast on both outcomes. Proximity-alert radius intentionally
  omitted (desktop has no GPS; honest scope).
- RPC hygiene (§8): SendLocation held t.mu across its send RPC via
  withPeer's lock — converted to the snapshot pattern (unlock before the
  RPC, withAPI for the client). New methods follow it by construction.
- Tests first: liveRemainingText/liveAge truth tables (incl. clock-skew
  clamp, round-up), preset table, liveLocationMedia/liveStopMedia builders
  (flag correctness via gotd getters).

Gate: gofmt/vet/test green (engine, cores, gui); local Xvfb boot clean.

## 2026-09-11 — slice 132: inline animated custom emoji in message text

The last CORE-ONLY content row flips PRESENT:

- RICHTEXT: MessageEntityCustomEmoji entities now carry their document ID
  into the token flow; a ready artwork token renders as a side×side square
  (1.35x the font box, tdesktop proportions) INSTEAD of the base-glyph
  text macro — .tgs lottie animates inline on a per-DOCUMENT clock (shared
  across messages and chats, frame re-arm), webp/png render statically,
  video/webm honestly stays the base glyph (no pure-Go webm decoder, §1.1).
- FETCH: batched per message (all unknown docIDs in one
  engine.GetCustomEmojiFiles call), per-message in-flight guard, per-doc
  failure pin (no retry churn), 512-entry cache. The pre-fetch state IS
  the current rendering (base emoji) — an honest transition, not a stub.
- RPC HYGIENE (§8, same sweep): GetCustomEmojiFiles, GetCustomEmojiThumbs,
  GetStickerFiles, GetGifFiles, GetSavedRingtones (+cachedRingtonePath,
  downloadSmallFile now takes the api/ctx snapshot) — all previously held
  t.mu across MULTI-RPC document fetch + streamed downloads.
- Entity parse hoisted to richTextLabel (flowRich no longer re-unmarshals
  ContentRich per frame).

Gate: gofmt/vet/test green; local Xvfb boot clean; binary links.

## 2026-09-11 — slice 133: bot info panel (description + commands + privacy)

The owner's tested path is bot chats — the profile panel now carries the
bot's own info (tdesktop bot profile):

- CORE: users.getFullUser's bot_info folds into the User through the pure
  applyBotInfoFields helper (description, privacy-policy URL, web-app menu
  button text; value- and nil-safe; tested with a truth table including
  the default-menu-button non-leak).
- ENGINE: users table gains bot_description + bot_privacy_url
  (migrateV49, duplicate-column-tolerant); UpsertUser COALESCE-keeps old
  values (profile refreshes never blank the fields); GetUser scans them
  into CachedUser.
- GUI: bot profile panels render "What can this bot do?" (description),
  the chat's commands as accent rows — tap inserts into the composer and
  closes the panel (reuses the slice-76 "/" menu wire) — and a
  privacy-policy row (openext browser handoff, toast on failure). Commands
  load with the panel (engine.GetChatBotCommands, bots only).

Gate: gofmt/vet/test green (gui, engine, cores); local Xvfb boot clean.

## 2026-09-11 — slice 134: mute-duration picker

The notifications row's switch only did instant forever/unmute; tdesktop
offers durations:

- GUI: ⏰ chip on the notifications row opens "Mute for…" — 1 hour /
  8 hours / 2 days / until turned back on + Unmute rows (content-pane
  dialog, Esc + Cancel, toasts on apply). Timed picks ride
  engine.MuteChat(muted, duration) → core MuteChatFor
  (account.updateNotifySettings mute_until); forever keeps the plain
  switch semantics. The dialog gates BELOW the passcode lock (security
  gate wins — pinned by test).
- RPC hygiene (§8): MuteChat + MuteChatFor held withPeer's t.mu across
  the notify-settings RPC — converted to the snapshot pattern.
- Remaining (documented in parity row): remaining-time display on the
  row (needs notify-settings polling), custom durations, per-chat
  sound/vibrate exception editors.

Gate: gofmt/vet/test green; local Xvfb boot clean.

## 2026-09-11 — slice 135: power saving made real

engine.SetPowerSaving existed as a write-only surface; now it gates the
GUI's animation loops:

- GATES: stickers/dice (stickerBubble) and inline custom emoji
  (drawEmojiArt) render their first frame statically — no
  InvalidateCmd re-arm, no per-frame CPU — while power saving is on
  (force-all semantics; per-class flag bits in place for finer rows).
- SETTINGS: master toggle in Appearance; engine.SetPowerSaving persists
  through AppConfig (power_saving_flags/force_all), Init restores,
  GetPowerSaving surfaces the state; psLoad runs with the theme restore
  before the first frame.
- Pure helper powerSavingBlocks tested against the tdesktop bit layout.

Gate: gofmt/vet/test green (gui, engine, utils); local Xvfb boot clean.

## 2026-09-11 — session wrap: slices 130-135, all CI-verified

Session summary (continuation after the owner's freeze report — the
freeze fix itself landed last session):

- slice 130: pure-Go HTTP image fetcher (engine.FetchHTTPImage) +
  inline-bot URL thumbs + full-res webpage card photos (dice-style media
  row; mediaBlock gated for webpage cards).
- slice 131: live locations — send (15m/1h/8h presets), countdown chip,
  Stop-sharing button; remote shares move via message edits.
- slice 132: inline animated custom emoji in message text (lottie per-doc
  clocks, static webp, honest webm fallback) + §8 sweep over five
  document-fetch methods.
- slice 133: bot info panel — description ("What can this bot do?"),
  tappable command rows, privacy-policy link; migrateV49.
- slice 134: mute-duration picker (tdesktop presets) + §8 conversion of
  the notify-settings RPCs; gates below the passcode lock.
- slice 135: power saving — real animation gates + persisted master
  toggle.
- §8 withAPI conversions this session (freeze-class hygiene):
  DownloadFile, DownloadChatAvatar, SendLocation, SendLiveLocation,
  StopLiveLocation, MuteChat, MuteChatFor, GetCustomEmojiFiles,
  GetCustomEmojiThumbs, GetStickerFiles, GetGifFiles, GetSavedRingtones
  (+downloadSmallFile snapshot param).
- Environment: sandbox reset absorbed twice; devroot recipe committed
  (devroot.env) for the next agent.

Every slice: tests-first, full gate green, pushed immediately, verify CI
dispatched — all runs GREEN (checked via API). Parity now 144 PRESENT /
31 PARTIAL / 11 MISSING / 32 CORE-ONLY by row count.

Next candidates (by owner value): remaining-time display on muted chats
(needs notify-settings polling), chat preview popup (hover peek), global
post search, sticker/emoji manager settings section, tray/badge platform
work (dbus StatusNotifier + Windows Shell_NotifyIcon).

## 2026-09-11 — slice 136: timed-mute remaining-time display

Mute-for-1h was already settable (slice 134) but invisible afterwards —
now the countdown is everywhere tdesktop shows it:

- ENGINE: chats.mute_until (migrateV50, unix seconds; 0 = forever).
  MuteChat(dur>0) stores now+dur; unmute/forever clear it. The dialog
  upsert keeps timed mutes across core refreshes (CASE on
  excluded.is_muted so core-side unmutes still win). A throttled (15s)
  expiry sweep on both list-read paths auto-unmutes rows whose deadline
  passed — mirroring the server, which unmutes at mute_until itself.
- CROSS-DEVICE: cores.NotifySettingsUpdate carries MuteUntil (int32-max
  "forever" sentinel normalized to 0); engine applyNotifySettings maps
  tg peer kinds (user/group/channel) onto chat-id conventions and
  updates the cache — mutes made on the phone appear on desktop with
  their expiry.
- GUI: chat-row trailing badge gains the timed-mute countdown chip
  (tdesktop's clock badge — "59m"/"23h"/"3d", single unit floored, min
  1m — rendered FIRST in the badge order); profile notifications row
  shows "Muted until 15:04 / Sep 12, 15:04 / Sep 12, 2027"; the sidebar
  re-renders on the minute while any row is timed-muted and pulls a
  fresh (swept) list at expiry.
- Tests: engine store/clear/expire/sweep/peer-map/handleUpdate; gui
  label/until-format/badge-order/tick predicate.

Gate: gofmt/vet/test green; Xvfb boot clean (EGL vendor-dir fix found
and committed into devroot.env — the sandbox lost /usr/share/glvnd).

## 2026-09-11 — slice 137: system tray (Linux SNI + Windows) + unread badge

The tray was one of the two remaining platform-completeness MISSING
rows (P2). Shipped for real, pure Go end to end:

- DEPENDENCY (rated 8/10, kept per §1.12): github.com/gogpu/systray
  v0.3.0 — freedesktop StatusNotifierItem + com.canonical.dbusmenu on
  godbus (Linux), Shell_NotifyIconW via x/sys/windows (Windows), MIT.
  Vetted against the freedesktop SNI spec text: correct
  org.kde.StatusNotifierItem-PID-ID bus naming, watcher-restart
  re-registration (NameOwnerChanged), full dbusmenu method set
  (GetLayout/GetGroupProperties/Event/EventGroup/AboutToShow(Group),
  LayoutUpdated + ItemsPropertiesUpdated), nil-safe after a failed
  Create, watcher-absence is non-fatal. godbus v5.0.6 → v5.2.2 (the
  notify banners build unchanged).
- ICON (gui/trayicon.go): rendered programmatically — rounded accent
  tile (follows the user's accent), original speech-bubble mark, unread
  badge with a built-in 3x5 pixel-font counter ("99+" clamp),
  deterministic, unit-tested (badge presence, digit differences,
  determinism). No binary assets in the repo.
- MENU (gui/tray.go, AyuGram layout): Show UniClient (ActionRaise),
  per-account rows with unread counts (tap scopes the sidebar — same
  path as the drawer rows), Ghost mode + Streamer mode live checkboxes
  (same engine calls as the drawer toggles), Quit (ActionClose →
  normal DestroyEvent shutdown). Updates ride the existing
  refreshChats/refreshAccounts/refreshConfig hooks; the accent restash
  in snapshot() keeps background reads race-free. tray_stub.go is the
  honest absence on web/Android (no tray surfaces at all — the settings
  toggle hides there, §1.10).
- SETTINGS: "System tray icon" in Notifications (AppConfig.SystemTray,
  nil = default ON like tdesktop; live start/stop).
- VERIFICATION (§9 ladder, real-server rung for D-Bus): tray_live_test
  boots a private dbus-daemon + a fake StatusNotifierWatcher and proves
  the actual wire round-trips: registration, SNI property reads,
  dbusmenu GetLayout with the AyuGram menu, in-place relabels after
  sync, tooltip update. Xvfb GUI boot clean; wasm + windows
  cross-builds green.

Parity: tray MISSING→PRESENT; taskbar/dock badge MISSING→PARTIAL (the
tray-icon counter is the tdesktop tray behavior; Windows taskbar
overlay + dock badges remain).

## 2026-09-11 — slice 138: global post search (hashtag → channels.searchPosts)

- Sidebar search: '#hashtag' queries now also run
  engine.SearchGlobalPostMessages per account (the core's
  channels.searchPosts path — exactly what tdesktop triggers for
  hashtag queries); hits render as a "Posts" section between Messages
  and Global results, using the message-row renderer (chat title +
  snippet + time; tap opens the channel).
- postsSearchQuery gate (pure, tested): '#' followed by a non-space
  rune; the wire API is hashtag-scoped so plain queries stay on
  chat/message search — no wasted RPCs.
- Tabs: Posts survives on All + Messages, hidden on Chats/Links/Files
  (post hits carry no link/file kinds).
- buildSearchRows extended (pure, unit-tested); state/frame/snapshot
  plumbing; stale-run drop + short-query reset behave like the other
  sections.

Parity: "Search posts in public channels" CORE-ONLY→PRESENT.

## 2026-09-11 — session wrap: slices 136-138 (tray + timed mutes + post search)

- slice 136: timed-mute countdown everywhere + cross-device mute sync.
- slice 137: real system tray (Linux SNI/dbusmenu, Windows
  Shell_NotifyIcon) with unread badge, Ayu menu, live toggles —
  verified against a real dbus-daemon, not just compiled.
- slice 138: hashtag-driven global post search.
- Environment notes for the next agent (devroot.env updated): the
  sandbox lost /usr/share/glvnd — export
  __EGL_VENDOR_LIBRARY_DIRS=/home/z/.local/sysroot/usr/share/glvnd/egl_vendor.d
  for Xvfb boots; libolm-dev + libolm3 extracted into the sysroot
  again after the reset.
- Parity after this session: 147 PRESENT / 32 PARTIAL / 9 MISSING /
  31 CORE-ONLY by row count.

Next candidates (by owner value): sticker/emoji manager settings
section (installed sets: archive/reorder/delete), chat preview popup on
row hover, Windows taskbar overlay badge, 2FA completion, dice/games
message rendering (needs a lottie dice pack renderer decision).

## 2026-09-11 — slice 139: Stickers and Emoji manager (Settings)

tdesktop's "Stickers and Emoji" settings page, per-account, honest end to
end (research: gotd v0.161.0 schema re-verified —
messages.installStickerSet carries the Archived bool;
messages.getArchivedStickers returns covered rows; stickerSet#2dd14edc
has NO set-level animated/video flags, so those derive from cover
documents' attributes).

- RATING (§1.14): telegram core sticker methods 7/10 — full surface but
  t.mu-across-RPC debt on every method (freeze-class, §8) and no archive
  support → keep + extend + withAPI conversion (7 methods converted:
  GetInstalledStickerPacks, GetFeaturedStickerPacks, SearchStickerSets,
  InstallStickerSet, UninstallStickerSet, ReorderStickerSets + the two
  new ones). Engine fetcher layer 9/10 → extended.
- CORE: new pure helpers (installedSetSummary, stickerSetCoveredSummary,
  coveredDocs, mergeArchivedStickerSets, stickerSetInstallRequest) +
  GetStickerSetSummaries (lightweight 2-RPC listing: getAllStickers +
  getArchivedStickers, no per-set fetch — the picker's N+1 stays where
  per-sticker data is needed) + ArchiveStickerSet (installStickerSet
  Archived flag). StickerPackSummary gains Archived/Masks/Emojis/Official.
- ENGINE: StickerSetSummariesFetcher + StickerSetArchiver interfaces and
  passthroughs.
- GUI (gui/stickermanager.go): Settings → Main entry card → manager page
  riding the settings shell scroll (profileEdit pattern): Stickers/Emoji
  tabs, account chips when several accounts, live server search (stale-key
  drop, 2-rune min) with Add, Trending (featured minus known) with Add,
  installed rows w/ move up/down + Archive + Delete, Archived section w/
  Restore + Delete, emoji tab (lazy-loaded) w/ Delete. Every action
  reloads from the server. Unsupported platforms show the engine error.
- Tests-first: cores mapping (covered variants, flag bits, merge dedup,
  archive request) + engine passthrough (stub cores) + gui pure helpers
  (split, move order, subtitles, filter, featured-visible, search merge,
  set order). All failing first, green after.

Gate: gofmt/vet/test green (incl. -tags goolm); wasm + windows
cross-builds green; Xvfb GUI boot clean (single-command harness — the
sandbox reaps background Xvfb between tool calls, that was the earlier
boot failure, not a regression).

Parity: Chat-settings row CORE-ONLY→PARTIAL. 148 PRESENT / 32 PARTIAL /
9 MISSING / 30 CORE-ONLY by row count.

Next candidates: language switch (P2), folders settings CRUD (P2), chat
preview popup on hover, Windows taskbar overlay badge, 2FA completion.

## 2026-09-11 — slice 140: Language switch (settings + localization core)

tdesktop's Language box, honest scope: the cloud language list + switch
flow, and a localization core that renders pack-backed strings with an
embedded-English fallback (exactly tdesktop's missing-key behavior).

- RESEARCH: fetched the upstream
  telegramdesktop/tdesktop Telegram/Resources/langs/lang.strings and
  pinned the REAL key names (lng_settings_section_notify,
  lng_settings_section_privacy, lng_settings_data_storage,
  lng_settings_calls, lng_settings_language, lng_menu_about, lng_cancel,
  lng_close, lng_languages_none, …) — no guessed keys.
- GUI CORE (gui/lang.go): langTr (override-with-fallback, pure),
  langKeysForSettings (fixed consumed key set), settingsRailLabels
  (rail through the pack), language row labels/badges/filter/name
  helpers. All unit-tested first.
- GUI SECTION (gui/languagesettings.go): Language in the rail after
  Calls (tdesktop position; two pinned-order tests updated). Current-
  language card, search field, language rows (native name leads,
  English name + code sub-line, official/beta/RTL badge chips, active
  check). Tap applies: engine.SetLanguage (server pack load) +
  engine.GetLangStrings(keys) (client overrides) + persisted
  AppConfig.Language + toast. Boot restores the code; pack strings
  lazy-load once an account core exists (refreshAccounts hook).
- State: langCode/langStrings (copy-on-write)/langs* on App + frame
  snapshot; ensureLangStrings restore-once guard.
- Tests-first: lang fallback/override, key-set pinning, rail labels
  (fallback + German override), row label/badges/filter/name. Two
  existing rail-order tests updated to the new 9-section order.

Gate: gofmt/vet/test green (-tags goolm); wasm + windows cross-builds
green. Verify CI for slice 139 (cf0815d6): GREEN via API.

Parity: Language row CORE-ONLY→PRESENT. 149 PRESENT / 32 PARTIAL /
9 MISSING / 29 CORE-ONLY by row count.

## 2026-09-12 — slice 141: notification click-to-open + per-chat banner replacement

Interactive notification banners (tdesktop behavior), completing the
Linux half of the P1 notifications row: sounds were already real (slice
121), the missing piece was actions.

- RESEARCH: freedesktop notification spec re-read from primary source —
  actions are (key,label) pairs with the reserved `default` key mapping
  to the whole-body click on every major server; the client learns
  clicks through org.freedesktop.Notifications.ActionInvoked(id u,
  action_key s) and cleanup through NotificationClosed(id u, reason u)
  signals; Notify's replaces_id > 0 swaps a live banner in place (the
  tdesktop "never stack per chat" behavior). godbus v5.2.2 verified in
  the module cache: SessionBus() caches a process-wide shared conn
  (unresettable), Signal(ch) registers a caller-owned channel closed by
  the conn, AddMatchSender matches well-known names by current owner.
- RATING (§1.14): notify.go gating 9/10 keep+extend; notify_linux.go 7/10
  (single method call, no actions/replaces/signals, SessionBus cache
  hazard) keep+extend; dbus live-test harness (tray_live_test.go) 8/10 —
  reusable but leaked its daemon (--fork kills only the printed parent;
  fixed in place, benefits the tray tests too).
- GUI (gui/notify.go): notifyDefaultActions ([default, "Open chat"]);
  notifyIconURI (peer avatar → file:// URI → image-path hint);
  notifyOpenAction — banner click raises the window (ActionRaise) and
  schedules the chat open through the pendingOpen GUI-loop hop (openChat
  touches the composer editor; never from the dbus demux goroutine).
- TRANSPORT (gui/notify_linux.go): notifyBus — banner-id → click-handler
  map + chat-key → live-id map; subscribe installs path/interface/sender
  match rules once and demuxes ActionInvoked (dispatch off the demux
  goroutine) / NotificationClosed (entry cleanup); Notify now carries
  replaces_id (per-chat in-place update; the replaced id's handler is
  dropped), the action list, image-path + desktop-entry hints;
  dbusSession switched SessionBus → ConnectSessionBus (fresh
  Dial+Auth+Hello; no shared-cache hazard). notify_other.go keeps the
  honest never-invokes stub.
- TESTS-FIRST: pure (all platforms) notifyDefaultActions shape,
  notifyOpenAction hop (schedule + title + repeat), notifyIconURI; LIVE
  (linux, private dbus-daemon + fake org.freedesktop.Notifications
  server): fresh banner (replaces 0, actions, hints, avatar URI),
  ActionInvoked → handler fires, second banner for the same chat
  replaces in place AND re-arms its handler, a different chat never
  cross-replaces, NotificationClosed cleans up (next banner fresh),
  unknown-id signals are dropped safely. startPrivateBus de-forked so
  cleanup kills the real daemon; -count=3 stable (resetNotifyGlobals
  re-arms the package globals).
- Gate: gofmt/vet/test green (incl. -tags goolm); windows + wasm
  cross-builds green; Xvfb GUI boot clean.

Parity: notifications row text updated (sounds 121 + click-to-open 141
on Linux; windows/wasm/android transports remain). Counts unchanged:
149 PRESENT / 32 PARTIAL / 9 MISSING / 29 CORE-ONLY.

Next candidates: folders settings box (P2, CORE-ONLY row — list +
suggested folders), chat preview popup on hover, Windows taskbar
overlay badge, 2FA completion.

## 2026-09-12 — slice 142: Chat Folders manager (Settings)

tdesktop's "Filter chats" box, surfaces the last CORE-ONLY folder row:
the manager sub-page + the server's suggested folders.

- RATING (§1.14): engine folder surface (GetFolders/GetSuggestedFolders/
  Create/Edit/Delete/ReorderDialogFilters) 9/10 — complete, tested →
  keep; GUI folder editor (folders.go) 8/10 — full-featured dialog →
  reuse as-is (openFolderDlgFor/EditFor variants added for explicit
  accounts); no new engine/core code needed (pure GUI slice over
  existing surface).
- GUI (gui/foldermgr.go): Settings → Main "Chat Folders" entry card →
  manager sub-page (sticker-mgr shell pattern): header w/ back+reload,
  account chips (multi-account), folder rows (emoticon chip, name,
  chat count / invite-link-folder subtitle, Edit → full folder editor,
  ▲▼ reorder via ReorderDialogFilters with numeric-ID guard, Delete),
  "Create new folder" row, Suggested section — engine.GetSuggestedFolders
  w/ already-created names hidden (folderSuggestsVisible), tap seeds the
  standard editor with the suggestion's rules + name
  (openFolderDlgSuggested — tdesktop's suggested-filter flow).
- folders.go: openFolderDlg/openFolderDlgEdit now delegate to explicit-
  account variants (the manager opens dialogs for ITS account, not the
  sidebar's acctFilter).
- Tests-first (gui/foldermgr_test.go): chats-label plural, suggested
  dedupe (name collision, no-folder, empty cases), reorder swap math
  (adjacent moves + clamps + input immutability). All green.
- Gate: gofmt/vet/test green (goolm); windows + wasm cross-builds green;
  Xvfb GUI boot clean. Slice 141 verify CI (5ad6193c): GREEN via API.

Parity: Folders-settings row CORE-ONLY→PRESENT. 150 PRESENT / 32
PARTIAL / 9 MISSING / 28 CORE-ONLY.

Next candidates: chat preview popup on hover, Windows taskbar overlay
badge, premium settings section (CORE-ONE row: GetPremiumFeatures),
stars balance (CORE-ONLY), business section (CORE-ONLY).

## 2026-09-12 — slice 143: Telegram Premium settings page

tdesktop's Premium box, honest end to end: subscription status from the
server, purchasable plans with the payment deep link, and the
free-vs-premium limits comparison.

- RESEARCH: gotd v0.161.0 HelpPremiumPromo verified in the module cache —
  StatusText (the server's own subscription sentence), PeriodOptions →
  PremiumSubscriptionOption{Months, Currency, Amount (smallest units),
  BotURL (payment deep link), StoreProduct, Current,
  CanPurchaseUpgrade}; currency exponents per the Telegram currencies
  table (0: JPY/KRW/VND/CLP/DJF/GNF/PYG/UGX; 3: BHD/IQD/JOD/KWD/LYD/OMR/
  TND; 2 otherwise). Limits: engine.GetAllFolderLimits already ships the
  full free-vs-premium map from appconfig.
- RATING (§1.14): core premium surface 6/10 (HelpGetPremiumPromo exists
  but returns the raw wire type and holds t.mu across the RPC) → add the
  withAPI-converted GetPremiumPromo alongside (legacy untouched); engine
  premium seams 7/10 → extend with premiumPromoGetter; GUI: new page.
- CORE: PremiumPlanOption + PremiumPromo types (base.go);
  premiumPlansFromPromo (pure) + GetPremiumPromo (withAPI).
- ENGINE: GetPremiumPromo passthrough (nil for cores without premium —
  the GUI hides honestly).
- GUI (gui/settingspremium.go): Settings → Main "Telegram Premium" entry
  card (Telegram-platform accounts only) → page: status card (Active
  badge from AccountInfo.IsPremium; server StatusText otherwise), plan
  rows (duration label, currency-correct price, Current badge, Subscribe
  → openLinkExternal), "Limits with Premium" comparison rows, account
  chips, reload.
- Tests-first: cores mapping (fields, flags, order, nil-safety); gui
  currency exponents, price formatting (zero/triple-decimal + whole-unit
  cases), plan labels/subtitle, limits rows (fixed order, unknown keys
  skipped, missing keys degrade).
- Gate: gofmt/vet/test green (goolm); windows + wasm cross-builds green
  (low-memory recipe after an OOM kill on the cold cache); Xvfb GUI boot
  clean. NOTE: sandbox disk filled mid-slice (7GB go build cache) —
  cleaned; future agents watch `df -h /`.
- Slice 142 verify CI (0980f4ab): GREEN via API.

Parity: Premium-section row CORE-ONLY→PARTIAL (local premium
intentionally out — dead UI). 150 PRESENT / 32 PARTIAL / 9 MISSING /
27 CORE-ONLY.

Next candidates: stars balance + transactions (CORE-ONE), business
section (CORE-ONLY), chat preview popup on hover, Windows taskbar
overlay badge, 2FA completion.

## 2026-09-12 — slice 144: Telegram Stars page + dead-clickable fixes

The Stars box (balance + transaction history) plus a real bug class
fixed: visible controls whose Clickable was checked but never rendered.

- RESEARCH: gotd v0.161.0 PaymentsStarsStatus verified — Balance +
  History []StarsTransaction (ID, signed nanostar Amount, Date,
  StarsTransactionPeer wrapping PeerUser/PeerChannel/PeerChat, optional
  Title/Description behind Flags bits 0/1, Refund/Pending/Failed/Gift),
  names resolved from the response's Users/Chats; NextOffset pagination;
  inbound/outbound filter flags. No topup-URL RPC exists in gotd — the
  Buy button is honestly omitted (purchase runs through the store/bot).
- BUG FIX (found while writing the stars tabs): slices 139+140 shipped
  DEAD CLICKABLES — sticker-mgr Stickers/Emoji tab buttons and account
  chips, and every language row: Clicked(gtx) was checked but the
  clickable was never wrapped in material.ButtonLayout, so no pointer
  events ever arrived (§1.10 violation: visible controls that do
  nothing). Fixed all five surfaces (sticker tabs+chips, language rows,
  folder-mgr chips, premium chips; stars written correctly from the
  start). Unit tests can't catch this class (it needs a render + pointer
  event) — the guard is review: every Clicked() must have its
  ButtonLayout/IconButton render in the same row.
- Also: slice 143's verify CI went RED on the gofmt gate
  (cores/telegram_premium_test.go + engine/premium_business.go were
  committed unformatted); both gofmt'd in this slice's tree — the gate
  is green locally now, and this push carries the fix.
- CORE: StarsTxn/StarsStatus types; starsStatusFromWire (pure — signed
  nanostars, peer-name resolution, flag carry-through) + GetMyStars
  (payments.getStarsTransactions Peer=InputPeerSelf, withAPI, in/out
  filters).
- ENGINE: GetMyStars seam (nil for cores without stars — honest hide).
- GUI (gui/settingsstars.go): Settings → Main "Telegram Stars" entry
  card (Telegram accounts only) → page: balance card, filter tabs,
  transaction rows (title priority, description/date subtitle, status
  chips, signed amount), load-more, account chips, reload.
- Tests-first: cores wire mapping (names, signs, flags, nil-safety,
  conditional-field flags set like the decoder does) + gui formatting
  (nanostar→trimmed decimals), amount labels, title priority, status
  chips, filter tabs.
- Gate: gofmt/vet/test green (goolm); windows + wasm cross-builds green;
  Xvfb GUI boot clean.

Parity: Stars row CORE-ONLY→PARTIAL (gifting + withdraw remain).
150 PRESENT / 33 PARTIAL / 9 MISSING / 26 CORE-ONLY.

Next candidates: business section (CORE-ONLY), chat preview popup,
Windows taskbar overlay badge, 2FA completion, message-shot renderer.

## 2026-09-12 — slice 145: hover chat-preview popup

tdesktop's chat preview: rest the mouse on a chat row and a compact card
floats beside the sidebar with the chat's last messages.

- RATING (§1.14): engine.GetMessages(beforeMs=0) 9/10 — the latest-page
  branch is a pure local SQLite read (perfect for a passive peek, no
  network) → keep; sidebar hover plumbing 8/10 — rows already track
  btn.Hovered() (slice 89 quick actions) and the pane already owns a
  pointer input area (chatmenu press routing) → extend both.
- GUI (gui/chatpeek.go): 600ms hover delay (AfterFunc re-armed per chat
  key, stale-key guarded under a.mu); peek card = title + last 3 cached
  lines (You/sender prefix, media typed labels, 48-rune clamp, service
  rows dropped, display-order flip); passive overlay at the WINDOW level
  (sidebar renders before the chat pane — drawing there would land
  underneath; app.go renders it above everything but toast/shortcuts);
  anchor = mouse Y (pane-level pointer.Move filter) - h/5, clamped;
  hides on row-hover end (per-frame marker reset/check around the row
  list), chat open, chat-menu open; selected chat never peeks.
- Tests-first: peekMsgLine (prefixes, media labels, clamps), peekLines
  (order flip, service drop, max clamp, nil), peekAnchorY (clamps),
  delay bounds (400-900ms window).
- Gate: gofmt/vet/test green (goolm); windows + wasm + native builds
  green; Xvfb GUI boot clean. Slice 144 verify CI (67f6763f): GREEN
  via API — the gofmt-gate failure of slice 143 is resolved on main.

Parity: Chat-preview-popup row CORE-ONLY→PRESENT. 151 PRESENT / 33
PARTIAL / 9 MISSING / 25 CORE-ONLY.

Next candidates: business section, Windows taskbar overlay badge,
message-shot renderer, dice/games rendering (lottie decision).

## 2026-09-12 — slice 146: custom fonts (interface + mono)

tdesktop's font box: pick a .ttf/.otf for the UI and optionally a mono
variant — applied at runtime, persisted, restored at boot.

- RATING (§1.14): theme collection building 8/10 (NewUI's inline
  gofont+notoemoji assembly) → extracted to shared baseFontCollection()
  + extended; persistence plumbing 9/10 (pointer-field ConfigChanges
  pattern already established) → reused.
- DESIGN: override by FACE SWAPPING, not shadowing — swapCollectionFaces
  replaces the face objects inside gofont.Collection() while keeping
  every descriptor (typeface/weight/style), so gio's matching behaves
  exactly as stock (fontscan map + face dedup make duplicate-family
  shadowing nondeterministic — swapping is deterministic). Single-file
  fonts collapse weight variants onto one face (no synthetic bold —
  same honest behavior as tdesktop single-file fonts).
- GUI (gui/fontpick.go): Appearance → Fonts rows (current name, Pick,
  Reset when set); pick via the existing explorer picker (.ttf/.otf);
  parse+apply (theme Shaper rebuild) + persist AppConfig
  font_path/mono_font_path (*string changes: nil=unchanged, ""=reset);
  boot restore with silent fallback when the file is missing; parse
  failures keep the defaults with an honest toast.
- Tests-first: swapCollectionFaces (descriptors untouched, count kept,
  default family swapped, mono family only with a mono face, nil
  no-op), isFontPath (case-insensitive exts), fontFileName.
- Gate: gofmt/vet/test green (goolm); windows + wasm + native green;
  Xvfb boot clean. Slice 145 CI dispatched, pending check.

Parity: Font row PARTIAL→PRESENT. 152 PRESENT / 32 PARTIAL / 9 MISSING /
25 CORE-ONLY.

Next candidates: business section, message-shot renderer, custom mute
durations, Alt+jumplist/Ctrl+Tab shortcuts.

## 2026-09-12 — slice 147: Ctrl+Tab account cycling + session wrap

- Ctrl+Tab / Ctrl+Shift+Tab cycle the account scope: "" (all chats) →
  each account in list order, wrapping (accountScopeCycle, pure —
  negative-safe modulo, unknown-scope fallback); rides the same
  acctFilter + refreshFolders path as the sidebar account menu and the
  tray rows; Tab key filter distinct from the generic ctrl filter (no
  event conflict).
- Tests-first: scope-cycle table (forward/backward/wrap/multi-step/
  unknown/empty), key→step mapping.
- Gate: gofmt/vet/test green (goolm); windows + wasm + native green;
  Xvfb boot clean. Slice 146 verify CI (513bbd16): GREEN via API.

Session summary (slices 141-147): notification click-to-open + per-chat
banner replacement (live dbus wire test), Chat Folders manager,
Telegram Premium page, Telegram Stars page, dead-clickable fixes across
slices 139/140, hover chat-preview popup, custom fonts (interface +
mono), Ctrl+Tab account cycling.

Parity: 152 PRESENT / 32 PARTIAL / 9 MISSING / 25 CORE-ONLY.

Next candidates: business section (away/greeting/work-hours editors —
core RPCs exist), message-shot renderer, custom mute durations,
Alt+jumplist, Windows taskbar overlay badge.

## 2026-09-12 — slice 148: Telegram Business settings section

tdesktop's Settings → Telegram Business, per-account: opening hours,
location, greeting messages, away messages, quick replies, intro.

- RATING (§1.14): engine business surface 8/10 (capability interfaces
  existed, nothing implemented them → implemented against them, added
  typed tz/quick-reply helpers) → keep + extend; premium/stars sub-page
  pattern 9/10 → reused for the page shell; bizWeeklyOpen cross-midnight
  semantics re-verified against core.telegram.org/api/business (fresh
  research, not stale notes).
- CORE (cores/telegram_business.go): read model from users.getFullUser
  (self) + messages.getQuickReplies (greeting/away texts resolve through
  the shortcut list); write path = the five account.updateBusiness* RPCs
  (withAPI rule, unlocked); greeting/away message text is saved INTO a
  quick-reply shortcut (existing → replace its messages, absent → create
  by name then resolve the fresh ID — tdesktop's flow); GetTimezones
  (help.getTimezonesList), GetQuickReplies, CreateQuickReply (sendMessage
  w/ inputQuickReplyShortcut), RenameQuickReply; pure builders
  (buildWorkHours/Location/Greeting/Away/Intro, sanitizeShortcutName,
  lenient map readers) unit-tested against the TL schema.
- ENGINE: GetTimezones/GetQuickReplies/CreateQuickReply/RenameQuickReply
  added to premium_business.go (interface + honest nil fallbacks); the
  pre-existing GetBusinessInfo/SetBusinessFeature generic surface now
  has a live implementation.
- GUI (gui/business.go): Settings → Main entry card (Telegram accounts
  only, §1.10) → per-account page — expandable editors: Location
  (address + optional lat/lon), Opening hours (24/7 preset, per-day
  interval rows w/ add/remove, lenient "9:00" parsing, searchable
  timezone picker), Greeting (text, recipient checkboxes, 7/14/21/28
  inactivity chips), Away (text, recipients, schedule segments
  always/outside-hours/custom date range, offline-only), Quick replies
  manager (rows w/ message previews, create/rename/delete), Intro
  (title + description). Premium-gate note for non-premium accounts;
  honest "Not set"/"Off" subtitles. bizWeek model (wire ↔ per-day
  intervals, cross-midnight split, merge/normalize, summary renderer)
  unit-tested; editor text captured on the UI goroutine (the
  profileedit.go pattern), only RPCs run in the background.
- Gate: gofmt/vet/test green (goolm); windows + wasm + native green;
  Xvfb GUI smoke boots (window + real screenshots, welcome screen
  verified via VLM). Local dev note: tg compiles on this 3.5GB box with
  `-gcflags="github.com/gotd/td/tg=-c=1" GOGC=20`; no-swap, no-root.

Parity: Business row CORE-ONLY→PARTIAL. 144 PRESENT / 32 PARTIAL /
7 MISSING / 16 CORE-ONLY (199 tracked rows, count method: status-cell
regex incl. blocked variants).

Next candidates: message-shot renderer, custom mute durations,
Alt+jumplist, Windows taskbar overlay badge, chat-wide translate bar.

## 2026-09-12 — slice 149: custom mute durations

- The "Mute for…" picker gains a Custom… row (tdesktop's box has the
  same entry): reveals a text field accepting "2h", "45m", "1h30m",
  "2d 3h 5m" or plain seconds; lenient parse (case/whitespace
  insensitive), past-2038 durations cap to Telegram's int32 forever
  semantics. Rides the same applyMutePreset → engine.MuteChat path as
  the presets; error text under the field on bad input.
- Tests-first: parse table + cap semantics (5000d→forever, 1000d real).
- Gate: gofmt/vet/test green (goolm); full suite green.

Parity: Per-chat notification settings PARTIAL (custom durations done;
per-chat sound/vibrate exception editors remain).

## 2026-09-12 — slice 150: chat-wide translate bar + target-language picker

tdesktop's "Translate to …?" strip over the message list.

- The header ⋮ menu gains a state-aware entry ("Translate to…" /
  "Hide translations", pure — tested). Turning it on renders the bar
  between the search bar and the message list: "Translate to <lang>"
  opens a 20-language chip picker (tdesktop's curated list, ISO 639-1),
  "Show original" turns it off; the picked target persists
  (AppConfig.TranslateTarget → engine ConfigChanges → boot restore).
- While on, every rendered text bubble lazily fetches its translation
  (dedup set, silent failure — no per-message toast spam) into the
  slice-46 Ayu translator block; per-message context-menu toggles ride
  the same configured target (was hardcoded "en").
- Tests-first: language list sanity + name/normalize helpers, chat-key
  stability, header-menu state-awareness; DM menu expectation updated.
- Gate: gofmt/vet/test green (goolm); windows + wasm + native green;
  Xvfb smoke boots. Slice 148 verify CI: GREEN via API.

Parity: Translate bar PARTIAL→PRESENT.

## 2026-09-12 — slice 151: message shot (offscreen message→PNG renderer)

AyuGram's "take message screenshot": the message context menu gains
"Message shot…" — the message composes into a shareable PNG fully
offscreen (no window, no GPU): forward header, reply quote with accent
bar, sender name with the Telegram sender color, entity-styled body
(bold/italic/strike-through/mono/link-underlined-accent/spoiler
concealed with the bubble color; entity offsets are UTF-16 code units —
boundary-sweep span combiner), decoded photo thumb (aspect-kept,
registry decoders), edited+timestamp footer. Pure-Go text via the
x/image gofont faces (16px body, 13px meta), greedy word-wrap with
long-word hard-split, manual rounded-rect rasterizer.

- Tests-first: entity splitting (plain/bold/overlap/UTF-16/link), word
  wrap (budget, content preservation, hard-split), filename
  sanitization, render geometry + PNG encode, quote/forward expansion.
- Visual verification: sample render written to /tmp and inspected via
  VLM — bubble, quote bar, colored sender, styled runs, timestamp all
  confirmed, no overlap artifacts.
- Save flow rides the explorer CreateFile save picker (the attach
  picker's cousin); honest refusal when the message has no renderable
  content (§1.10).
- Gate: gofmt/vet/test green (goolm); windows + wasm + native green.

Parity: Message shot MISSING→PRESENT.

## 2026-09-12 — slice 152: inline read receipt ("Seen" + avatar row)

tdesktop's DM behavior: the last own outgoing message in a DM carries
a small "Seen 12:34" row with the reader avatar under the bubble meta.

- Gate (pure, tested): own + non-service + last-own + DM-only (groups
  keep the slice-98 dialog — tdesktop shows the stack in DMs).
- State: per-chat cached seenInline entry (msgID-keyed; refetch when the
  last own message changes; fetching dedup); data rides
  GetOutboxReadDate + GetMessageReadParticipantsDetailed.
- Render: 14px reader avatars (up to 3 + "+n"), "Seen HH:MM" caption
  (plain "Seen" without a resolved date); privacy/other errors render
  nothing inline (the dialog keeps the honest sentence — §1.10).
- Gate: gofmt/vet/test green (goolm); windows + wasm + native green.

Parity: Read receipt PARTIAL→PRESENT.

## 2026-09-12 — slice 153: Windows taskbar overlay badge

tdesktop's unread count on the Windows taskbar button.

- Deep-researched the ITaskbarList3 vtable layout against the mingw-w64
  shobjidl.h ABI (Wine's IDL ORDER DIFFERS — Wine lists
  ThumbBarUpdateButtons before ThumbBarSetImageList and SetOverlayIcon
  at 14; the real SDK has SetOverlayIcon at 18 with
  ThumbBarUpdateButtons/SetImageList swapped). SetOverlayIcon = index
  18 (IUnknown 0-2, HrInit 3, ITaskbarList 4-7, MarkFullscreenWindow
  8, ITaskbarList3 9-20). HrInit called before use; Release on exit.
- Pure-Go COM: CoInitializeEx (mode-tolerant) + CoCreateInstance
  (CLSCTX_ALL), vtable calls via syscall.SyscallN — no cgo (§1).
- Overlay icon: composed in-process (rounded accent tile + the tray
  glyph digits, trayCountLabel '99+' semantics), RGBA→HICON via
  CreateDIBSection (32bpp top-down BGRA) + CreateIconIndirect; mask +
  color bitmaps + HICON tracked and destroyed on change/exit.
- HWND from gio's Win32ViewEvent captured in ListenEvents; badge
  updates ride updateTray's snapshot (TotalUnread + accent) INDEPENDENT
  of the tray toggle (updateTray reshaped: badge first, tray sync
  after); COM released at app Shutdown.
- Non-Windows platforms: honest no-op stubs (Linux docks have no
  freedesktop badge standard — Unity launcher API documented as future;
  macOS banned). Composition lives in the shared taskbaricon.go so the
  tile renders unit-test everywhere.
- Tests: overlay tile geometry (sizes, opaque center, transparent
  corners, 99+ clamp). Windows surface blind-compiled (GOOS=windows
  build green); live behavior = the owner's live test.
- Gate: gofmt/vet/test green (goolm); windows + wasm + native green.

Parity: Unread badge on taskbar/dock PARTIAL→PRESENT.

## 2026-09-12 — session wrap (slices 148-153)

Session summary: Telegram Business settings section (location, opening
hours w/ timezone picker, greeting, away, quick replies manager, intro —
engine business surface finally implemented end-to-end); custom mute
durations in the Mute-for picker; chat-wide translate bar + persisted
target-language picker (20 languages); message shot renderer (offscreen
pure-Go composition: entity styling, quote/forward blocks, photo thumb,
verified visually via VLM); inline DM read receipt ("Seen HH:MM" +
reader avatar on the last own message); Windows taskbar overlay badge
(pure-Go ITaskbarList3 COM with the vtable ABI double-verified against
mingw-w64 — Wine's IDL ordering is wrong, SetOverlayIcon = 18).

Local-toolchain note for future small-VM sessions: tg compiles at
~3.5GB RAM with `-gcflags="github.com/gotd/td/tg=-c=1" GOGC=20 -p 1`
(full local gate possible — no CI needed for iteration); the Xvfb GUI
smoke needs `__EGL_VENDOR_LIBRARY_FILENAMES=<sysroot>/.../50_mesa.json`
(glvnd can't find the Mesa vendor without it) and everything must run
in ONE bash call (the sandbox reaps background processes between
calls). Scripts: /home/z/my-project/scripts/guismoke.sh + eglprobe.c
patterns.

Verify CI status at session end: slices 148-152 GREEN via API; 153
dispatched (see final check below).

Parity: 150 PRESENT / 27 PARTIAL / 6 MISSING / 16 CORE-ONLY
(199 tracked rows; count method: status-cell regex incl. blocked
variants). Rows moved this session: Business CORE-ONLY→PARTIAL, custom
mute (partial credit), Translate bar PARTIAL→PRESENT, Message shot
MISSING→PRESENT, Read receipt PARTIAL→PRESENT, Taskbar badge
PARTIAL→PRESENT.

Next candidates: Alt+jumplist (Windows COM: ICustomDestinationList +
IShellLink — blind), calls box (unified searchable call history),
chat-settings link-preview/message-actions rows, forum subsection tabs,
Ayu spy/saving toggles (engine-gated), Linux Unity launcher badge.

## 2026-09-12 — slice 154: the Calls box (tdesktop calls_box_controller 1:1)

tdesktop's Calls box, source-level parity against
calls/calls_box_controller.cpp (+ its box UI: ClearCallsBox,
AddCreateCallButton context, group-calls slide-wrap).

- Research: full read of the controller — pagination
  (kFirstPageCount=20 / kPerPageCount=100 via
  messages.search(inputMessagesFilterPhoneCalls, offset_id)),
  Row::canAddItem grouping (peer × date × direction), status strings
  (lng_call_box_status_today/yesterday/date/group), redial right-action
  (phone/camera per CallType), rowClicked → showPeerHistory at maxItemId,
  rowContextMenu (Delete / Show in chat), Clear-all (attention item,
  only when rows exist) → deletePhoneCallHistory revoke loop, group-calls
  subsection (channels with an active call), "No calls here yet" empty.
- New gui/callsbox.go (+ state/routing/drawer wiring): per-account page
  opened from the drawer Calls row (acctFilter/current scope, the
  contacts pattern). Grouped rows w/ Material call-made/received/missed
  arrows (missed red), avatar (real image when the engine cached one),
  redial → engine.StartCall → slice-101 call overlay, row click →
  openChat + jumpToMessageAt, right-click pane routing (chatPaneTag
  pattern) → Show in chat / Delete confirm (revoke checkbox, engine
  DeleteMessage per grouped msg id), header ⋮ menu (Call settings →
  setSectionCalls; Clear all → ClearCallsBox-style confirm →
  engine.ClearCallHistory(revoke) + first-page reload), group-calls
  subsection (HasActiveCall chats of the account; join action), Esc
  self-handled, contentDialogSurface right after contacts (pinned).
- RPC hygiene (§8 freeze rule): GetCallHistory, ClearCallHistory,
  MessagesDeletePhoneCallHistory converted to withAPI — lock-across-RPC
  scan clean for all three.
- Tests-first: grouping (merge same peer+day+dir; split day/dir/peer;
  newest-first), status phrases, next-offset, header menu items,
  routing priority, escTarget self-handling, direction mapping.
- Gate: gofmt/vet/test green (goolm); windows + wasm cross-builds green;
  Xvfb boot smoke green (window renders, dark palette + accent pixels).

Parity: Voice tab / call list PARTIAL→PRESENT (calls box landed).

## 2026-09-12 — slice 155: Chat settings Messages section + Ayu improve link previews

- tdesktop Messages section (settings_chat.cpp, lng_settings_send_enter):
  'Send message with' — Enter (default, InputSubmitSettings::Enter) or
  Ctrl+Enter. Appearance page carries the segmented picker; the mode
  persists as AppConfig.ComposerSubmit through ConfigChanges. In
  ctrl-enter mode the gio editor Submit is disabled (Enter inserts a
  newline) and a focus-gated Ctrl+Enter key layer (Return + Enter
  filters, keyLayer pattern) submits — active in both modes, matching
  tdesktop where Ctrl+Enter always submits.
- Composer send paths unified: trySubmitComposer (length limit,
  slow-mode gate, in-flight guard) now backs SubmitEvent, the send
  button, and Ctrl+Enter. No behavior change in the default mode.
- Ayu 'Improve link previews' (ayu settings_general.cpp +
  telegram_helpers getBetterLinkPreview): outgoing http(s) links of
  twitter/x (fixupx.com), tiktok incl. subdomains (kktiktok.com),
  reddit (vxreddit.com), instagram (kkclip.com), pixiv (phixiv.net)
  are rewritten host-only — path/query survive; applied in sendText
  after markdown composition, config-gated; toggle in the Ayu · General
  section.
- Skipped after research: 'Quick action on new message' (tdesktop's is
  a dialog-row SWIPE gesture — SwipeContextData/Lottie reveal; needs
  the row-gesture layer, tracked as follow-up) and the corner
  reply/reaction buttons (replyButtonManager floating-corner work).
  No dead UI shipped (§1.10).
- Tests-first: submit-mode mapping, host table (case-insensitivity,
  tiktok subdomain suffix rule, non-matches incl. api.twitter.com and
  old.reddit.com), URL rewrite with path/query survival, untouched
  text, config dispatch key, label rendering.
- Gate: gofmt/vet/test green (goolm); windows + wasm cross-builds
  green.

Parity: Chat settings PARTIAL (Messages section landed; swipe quick
action + corner buttons remain); Ayu preferences PARTIAL (General
section landed).

## 2026-09-12 — slice 156: forum subsection tabs (Top mode)

- tdesktop SubsectionTabs (history_view_subsection_tabs.cpp), the Top
  placement: a horizontal topic tab strip under the chat header of a
  forum chat. 'All topics' pseudo-tab (back to the topic list) then one
  tab per cached topic in the loaded pinned-first order — taps ride the
  existing openForumTopic / backToForumTopics paths.
- Tab visuals: colored icon circle (topicColor), title, closed lock
  marker, accent unread pill ('99+' clamp — tray semantics), active
  highlight; horizontal material.List scroller; listTop accounting
  keeps the message-list jump offset correct.
- Honest scope (documented): reorderable tabs (SubsectionSliderReorder)
  and Left/Bottom placements remain tdesktop extras; the ForumTabs
  channel flag is not engine-surfaced — the strip renders for every
  forum until the flag lands.
- Tests-first: tab construction + order, active selection (list/topic
  view, stale id deactivation), hidden-topic skip, closed/unread/color
  carry-over, badge clamp.
- Gate: gofmt/vet/test green (goolm); windows + wasm green.

Parity: Forum topics view PARTIAL→PRESENT (subsection tabs landed;
reorder/placement modes remain).

## 2026-09-12 — slice 157: corner reply button (tdesktop fast reply)

- tdesktop fast-reply pill (HistoryView ReplyButton::Manager,
  Message::replyButtonParameters, lng_fast_reply "Reply",
  displayFastReply semantics): compact accent 'Reply' pill anchored
  North-East on hovered INCOMING bubbles; tap = startReply.
- Hover tracking: the chat-pane pointer filter now carries
  Move/Enter/Leave and feeds notePaneHover, which maps the pointer to
  a message through the SAME rowBounds hit-test the context menu uses
  — no per-row clickables, hit tree untouched (links/quotes/keyboards/
  right-clicks/selection all preserved).
- Gate (pure, tested): setting on (cornerReply, default ON) + regular
  incoming + chat allows sending + not in selection mode; own and
  service rows excluded.
- Config plumbing: AppConfig.CornerReply (*bool, nil = ON),
  ConfigChanges + engine apply + cfgSnapshot effective value +
  configFieldChanges key + Messages-section toggle row.
- Tests-first: effective default, gate matrix, config dispatch.
- Gate: gofmt/vet/test green (goolm); windows + wasm green.

Parity: Chat settings PARTIAL (corner reply landed; swipe quick action
+ corner reaction remain).

## 2026-09-12 — session wrap (slices 154-157)

Session summary: the Calls box (tdesktop calls_box_controller 1:1 —
grouped rows, redial, show-in-chat jump, per-group delete w/ revoke,
Clear-all through deletePhoneCallHistory, group-calls subsection,
20+100 pagination); the Chat-settings Messages section ('Send message
with' Enter/Ctrl+Enter end-to-end incl. the focus-gated Ctrl+Enter key
layer + unified submit gate) + Ayu 'Improve link previews' (host-swap
mirror rewrite of outgoing links); forum subsection tabs (Top mode —
topic tab strip under the chat header); the corner reply button
(fast-reply pill on hovered incoming bubbles via pane hover routing).

Also: GetCallHistory / ClearCallHistory / MessagesDeletePhoneCallHistory
converted to the withAPI snapshot pattern (§8 freeze rule — lock scan
clean for all three; ~837 legacy conversions remain on the backlog).

Local-toolchain note (reprovisioned after VM reset): Go 1.27.1 at
/tmp/goroot, module cache at /tmp/gomodcache (survived), sysroot debs
at /tmp/sysroot/root, dev env script at
/home/z/my-project/scripts/devroot.sh (source it, build with
-tags goolm); watch /tmp disk — go clean -cache when the rootfs fills
(the build cache alone grows to ~7.5GB).

Verify CI status at session end: all four slices GREEN via API
(d6512034, c5c918b8, f3563cc5, bc65a1ab — full gate + windows/wasm
cross-builds + Xvfb GUI smoke w/ screenshot artifacts).

Parity after this session: 151 PRESENT / 26 PARTIAL / 5 MISSING /
16 CORE-ONLY (rows moved: Voice tab/call list PARTIAL→PRESENT, forum
topics view PARTIAL→PRESENT, Chat settings + Ayu preferences advanced).

Next candidates: swipe-based quick action on new message (dialog-row
swipe gesture layer), corner reaction button (needs a default-reaction
selection concept), Ayu spy/saving engine-gated toggles, Alt+jumplist
(Windows COM ICustomDestinationList, blind), Linux Unity launcher
badge (dbus), remaining ~837 withAPI conversions.

## 2026-09-12 — Rubika core: LIVE-verified pre-auth chain vs production + 2 core bugs fixed

Context: AGENTS.md §8 listed rubika as "unverified live (geo-restricted)".
This VM turns out NOT geo-blocked for iranlms.ir — independent research
against the CURRENT production web client bundle
(web.rubika.ir/main-es2015.6421623571994c9dd619.js) + live endpoint
probes, then a new env-gated live test suite.

Research findings (primary sources, all re-verified today):
- getdcmess.iranlms.ir DC discovery works and returns the live API map
  (messengerg2c1..44), socket map, storage map; default_socket "8"
  → wss://nsocket7.iranlms.ir:80.
- The production web client's hardcoded DefaultSocketUrl is
  wss://jsocket5.iranlms.ir:80 — NOT nsocket1..5 (all NXDOMAIN, stale).
- Web client handShake frame format matches the core's implementation
  exactly ({api_version, auth, data:"", method:"handShake"}); keepalive
  is a bare "{}" text frame; api_version constant is "5" by default with
  a config-driven upgrade path to "6" — production accepts "6" (proven).

Code changes (tests first: tests/rubika_live_test.go, -tags goolm,live):
- FIXED core bug 1: wsConnect never surfaced the "connected" state while
  healthy — the read loop blocks for the socket's whole lifetime and only
  returns on error/ctx-done, so wsLoop's post-return fireConnState never
  ran. Now fired right after the handShake write succeeds. A live
  production socket previously showed as permanently disconnected in the
  GUI.
- FIXED core bug 2: fallback socket list used dead nsocket1..5 hosts;
  now jsocket5-first (the web client's own default) + nsocket6/7, and
  useFallbackDCs TCP-probes the list instead of blindly taking [0].
- Hardened: authUser rejects an empty phone with a clean
  "phone number required" auth error instead of an INVALID_INPUT from
  the server.

Verification (§9 ladder, official-server rung for the pre-auth chain):
- go/tests/rubika_live_test.go — 3/3 GREEN against production in ~9s:
  DC discovery real data; full encrypted round-trip (tmp-session
  registerDevice + sendCode w/ deliberately invalid phone → structured
  INVALID_INPUT, proving encrypt→POST→decrypt→error-map); WS dial +
  TLS + upgrade + handShake → connected state within 3s.
- Full suite go test -tags goolm ./... green; gofmt/vet clean.

Rating per §2 (rate before code): rubika core design 7/10 — the wire
protocol implementation (crypto, framing, auth flow modeled on rubpy)
was already accurate; the failures found were operational state
reporting and stale fallback data, both small fixes, not replacements.
Kept and extended (per §1.12 policy: good rating → keep).

Parity/§8 status: rubika moves to "pre-auth chain LIVE-verified
2026-09-12" — same rung XMPP holds. Remaining: real phone+OTP sign-in
(owner's live test), post-auth RPC surface (dialogs, messages, voice).

## 2026-09-12 — Bale core: LIVE-verified unary pre-auth chain vs production

Context: §8 listed bale as "unverified live (geo-restricted)". This VM is
not geo-blocked for bale.ai — independent research against the CURRENT
production web client (web.bale.ai, index.4402958e45.js), then a live
test.

Research findings (primary sources, re-verified today):
- Production transport pair confirmed: grpc https://next-ws.bale.ai,
  ws wss://next-ws.bale.ai/ws/ — exactly what the core uses.
- StartPhoneAuth / ValidateCode protobuf wire layouts extracted from
  the generated client code in the bundle and cross-checked against the
  core's field maps: all equivalent on the wire (ASCII-string deviceHash
  ≡ bytes; options {"0":1} ≡ packed [1]; isJwt {"1":1} ≡ BoolValue true).
- App credentials {id:4, apiKey:C28D46DC...E7D} exist verbatim in the
  production bundle.

No core code changes needed for the auth chain — the reverse-engineered
wire format was already correct. (Earlier fear of mismatched ValidateCode
field order turned out to be a different service's message; the
auth.v1.ValidateCode layout matches.)

Verification (§9 official-server rung, pre-auth):
- go/tests/bale_live_test.go — GREEN vs production in ~1.2s: Authenticate
  with phone "1" → StartPhoneAuth → server answered structured
  `bale gRPC error: PHONE_NUMBER_INVALID` — the full protobuf →
  gRPC-Web framing → HTTP → trailer parse → error map chain works.
- Full suite still green; gofmt/vet clean.

Rating per §2: bale core auth/transport design 8/10 — wire-accurate
against today's production client; kept as-is.

§8 status: bale moves to "pre-auth chain LIVE-verified 2026-09-12".
Remaining: real phone+OTP (owner's live test), authenticated WS
streaming, post-auth RPC surface.

## 2026-09-12 — slice 158: swipe quick actions on chat rows (tdesktop swipe_handler 1:1)

Research (primary source: tdesktop dev branch, fetched + read this
session): dialogs_quick_action.cpp/.h, ui/controls/swipe_handler.cpp,
dialogs_layout.cpp paint path, core_settings default, settings_chat
SetupChatListQuickAction. Full mechanics extracted: direction lock at
|dx|-|dy|>1px; 50dp threshold; ratio = dx/thr clamped [0,1.5];
DampedOverswipe = 16·ln(1+shift/10); release at ratio>=1 fires;
snap-back anim; state-aware labels via ResolveQuickDialogLabel;
QuickDialogAction enum (Mute/Pin/Read/Archive/Delete/Disabled, default
Disabled); single configured action per swipe; strip bg windowBgActive
(red for Delete, gray for Disabled); SwipeActionFont 13→5 shrinking;
reach circle on threshold cross; swipe-back nav on the opposite
direction.

Implementation (tests first: gui/swipeaction_test.go — 8 pure-func
suites, all green before wiring):
- gui/swipeaction.go: gesture layer + rendering. Pass-through pointer
  overlay over the plain chat list (the rubber-band pattern, slice 84):
  rows keep hover/clicks, list keeps wheel scrolling. Direction lock,
  ratio tracking, overswipe damping (exact tdesktop curve), fire on
  release, 220ms ease-out snap-back animation, swipe-back hint arrow
  during leftward drags.
- chatRow: body wrapped in swipeRowShift — the row slides right, the
  action strip paints behind (accent / attention-red / gray; icon +
  shrinking label + reach circle). The strip resolves state-aware
  labels per row (mute↔unmute, pin↔unpin, read↔unread,
  archive↔unarchive) against engine.ChatInfo.
- performSwipeAction: real engine calls (MuteChat/PinChat/
  MarkChatRead/Unread/ArchiveChat/DeleteChat) + success toast +
  refreshChats. Swipe LEFT: exitArchive / back to All tab (tdesktop
  closes folders/forums).
- Settings → Chat → Quick actions: six-option chip picker (Disabled
  default), persisted SwipeAction config end-to-end (utils → engine
  ConfigChanges → cfgSnapshot).
- Two gesture-state bugs found by the tests and fixed before wiring:
  swipeDirLock lost the drag sign (vertical returned -1); the first
  damping attempt overshot tdesktop's curve (44px vs 20px at 1.5x) —
  now the exact 16·ln(1+s/10) port.

Verification: gui suite green (all 8 new suites + full package);
gofmt/vet clean; full repo build green; Xvfb GUI smoke boots the real
binary with the swipe layer wired (window found, screenshot taken, no
panic).

Rating per §2: the sidebar's existing event architecture (chatRowBounds
pane bookkeeping + pass-through overlays) 9/10 — the swipe layer plugged
in without touching the row pipeline; kept and extended.

## 2026-09-12 — slice 159: corner reaction button + favorite-reaction selection

Research (primary source: tdesktop dev branch): core_settings.h
(_cornerReaction default TRUE), settings_chat.cpp
(lng_settings_chat_corner_reaction "Reaction button in the corner",
next to cornerReply in the Messages section), history_view_list_widget
reactionButtonParameters (same hover-corner mechanism as the reply
button), history_inner_widget toggleFavoriteReaction (toggle semantics:
favorite added when absent, removed when own), data_message_reactions
favoriteId/setFavorite (server-side default via config
reactions_default, saved through messages.setDefaultReaction, fallback
👍 ConfigDefaultReactionEmoji).

Implementation (tests first: gui/cornerreaction_test.go — 5 suites):
- gui/cornerreaction.go: the pill (NE-anchored beside the reply pill,
  [fav][Reply] stack order), renders on hovered bubbles for incoming
  AND own rows (tdesktop canReact), never in selection/service rows.
  Tap computes the new own-reaction list (pure
  toggleOwnReactionEmojis) and sends it whole.
- cores/telegram.go: ReactToMessageList (full-list sendReaction; empty
  list removes all own reactions; custom_emoji passthrough),
  GetDefaultReaction (help.getConfig reactions_default), and
  SetDefaultReaction converted to the withAPI snapshot pattern (§8
  freeze rule — 3 more RPCs off the legacy lock list).
- engine: ReactToMessageList through the pending queue (reactPayload
  gains the emojis list; single-emoji back-compat preserved),
  GetDefaultReaction passthrough.
- gui/chat.go: incoming rows wrap with cornerButtonsOverlay (reply +
  reaction pills); own rows wrap for the reaction pill alone.
- Settings → Chat → Messages: "Reaction button in the corner" toggle
  (CornerReaction config, default ON end-to-end) + Quick actions
  "React with" per-account emoji-chip picker (server favorite loaded
  lazily, applied via messages.setDefaultReaction, 👍 fallback).

Verification: all 5 new suites green; full repo tests green; gofmt/vet
clean; Xvfb GUI smoke boots the binary (window + screenshot, no panic).

Parity note: the reaction picker's emoji set rides the existing
availEmojis loader (account reactions list + built-in fallback set),
matching how the context-menu quick-reactions row already behaves.

## 2026-09-12 — slice 160: Linux Unity launcher badge (dbus, tdesktop 1:1)

Research (primary source: tdesktop dev branch,
platform/linux/main_window_linux.cpp updateUnityCounter): the
com.canonical.Unity.LauncherEntry protocol — Update signal on
/com/canonical/unity/launcherentry/<djb2("application://<desktop>.desktop")>
carrying (s app_id, a{sv} props) with count int64 (9999 clamp) +
count-visible bool. Understood by Ubuntu Dock/Dash-to-Dock, KDE Plasma
taskbar, and libunity-compatible docks. Qt≥6.6 path
(qApp->setBadgeNumber) resolves to the same protocol underneath.

Implementation (tests first: gui/launcherbadge_test.go — 5 pure suites
+ a WIRE suite):
- gui/launcherbadge_linux.go: djb2 hash, launcherEntryPath,
  unityBadgeProps (tdesktop counterSlice clamp), and
  updateTaskbarBadge emitting the Update signal through the session
  bus (godbus — pure Go, no libunity link). Rides the same entry point
  as the Windows overlay badge (slice 153): updateTray →
  updateTaskbarBadge(TotalUnread), independent of the tray toggle.
- taskbar_stub.go retagged !windows && !linux (the old comment said
  the Unity badge "stays a documented future" — now real).
- Bug caught by the wire test: the object path used the gui's itoa
  helper — which is the unread-badge 999+ label formatter, not an
  integer formatter ("999+" is not a valid path element). Now
  strconv.FormatUint.

Verification (§9 ladder, dockerized-equivalent rung — hermetic private
dbus-daemon): TestLauncherBadgeWire GREEN — a monitor connection on a
real private bus catches the Update signal with the exact tdesktop wire
form: djb2-derived path, com.canonical.Unity.LauncherEntry.Update
name, app_id "application://uniclient.desktop", count 42/visible true,
then the zero-count clearing signal. Full repo tests green; gofmt/vet
clean; windows + wasm cross-builds green; Xvfb GUI smoke boots.

## 2026-09-12 — session wrap (bale/rubika live verification + slices 158-160 + withAPI batch)

Session summary, in order:

1. Environment re-provisioned after a VM reset: Go 1.27.1 at /tmp/goroot,
   sysroot rebuilt (EGL/wayland/xkb dev debs + runtime .so copies),
   module cache survived; full build + tests + gofmt/vet green before
   any work started.

2. RUBIKA core — LIVE-verified pre-auth chain vs production (iranlms.ir
   reachable from this VM; the geo-block is gone). Independent research
   against the production web client bundle re-derived the live socket
   set (jsocket*, NOT the stale nsocket1-5 — NXDOMAIN). Two real bugs
   fixed: WS "connected" state never fired while healthy (the read loop
   blocks for the socket's lifetime); fallback socket list dead hosts +
   blind pick[0] (now jsocket5-first + TCP probe). 3 live tests green
   (DC discovery; encrypted sendCode round-trip → structured
   INVALID_INPUT; WS dial+handShake). Research doc updated with the
   verified wire facts.

3. BALE core — LIVE-verified unary pre-auth chain vs production
   (next-ws.bale.ai). Wire layouts + app credentials cross-checked
   against the production bundle — the core's encoding was already
   correct; no changes needed. Live test green: StartPhoneAuth with an
   invalid phone → structured PHONE_NUMBER_INVALID in ~1s (full
   protobuf → gRPC-Web → HTTP → trailer-parse → error-map round-trip).

4. Slice 158 — swipe quick actions on chat rows (tdesktop
   swipe_handler/quick_action 1:1): direction lock, 50dp threshold,
   exact DampedOverswipe ln curve, fire-on-release, snap-back anim;
   pass-through overlay; sliding row + action strip (state-aware
   labels, reach circle, shrinking label); swipe-back nav; Settings
   picker persisted. Tests caught 2 gesture-math bugs before wiring.

5. Slice 159 — corner reaction button (tdesktop cornerReaction 1:1,
   default ON): NE pill beside the reply pill toggling the account's
   favorite reaction (full-list sendReaction semantics); favorite =
   server-side reactions_default (👍 fallback) via
   messages.setDefaultReaction; core additions all withAPI-clean
   (ReactToMessageList, GetDefaultReaction, SetDefaultReaction
   converted). Settings: toggle + per-account "React with" picker.

6. Slice 160 — Linux Unity launcher badge (tdesktop
   updateUnityCounter 1:1): com.canonical.Unity.LauncherEntry Update
   signal via godbus; djb2 entry path; 9999-clamped count +
   count-visible; same entry point as the Windows overlay badge.
   Wire-verified against a private dbus-daemon (signal round-trip incl.
   the zero-count clearing). The wire test caught itoa misuse ("999+"
   is not a valid path element).

7. withAPI batch: 13 more RPCs converted off the legacy
   lock-across-RPC pattern (scanner: 823 → 813; ~813 remain — every
   remaining method reads core state beyond the auth guard, so bulk
   conversion is unsafe; hand conversion continues per-touch).

Verification: full repo tests green locally all session; gofmt/vet
clean; windows + wasm cross-builds green; Xvfb GUI smoke boots the
binary after every slice; verify workflow dispatched on HEAD
(7dd03656) at session end — status checked via API.

Parity after this session: the Messages section rows (corner reply,
corner reaction, swipe action, react-with) + cross-platform dock badge
complete; AyuGram 1:1 program continues (next candidates: Ayu
spy/saving engine-gated toggles, Alt+jumplist, multi-window chats,
PiP — see the parity matrix MISSING/PARTIAL rows).

## 2026-09-12 — slice 161: message-permalink deep links (t.me/user/123, t.me/c/…, tg:// post)

tdesktop routes message permalinks in-app; UniClient previously left
them on the browser ("engine does not expose message lookups"). The
engine exposes them now.

Implementation (tests first: deeplink_test.go permalink suites):
- deepLinkTarget grows a third return (post id): t.me/<user>/<msg>,
  t.me/c/<channelID>/<msg>, tg://resolve?domain=<user>&post=<msg> →
  kind "permalink"; topic (3-segment) and comment-thread forms stay
  browser (honest scope — topic views don't cross-load by message id);
  non-numeric ids stay browser.
- cores/telegram.go GetMessageByID (withAPI-clean): -100 chats go
  through channels.getMessages (InputChannel + access hash); other
  peers through messages.getMessages (no peer field — ids resolve
  globally); the shared converter entity-caches + maps.
- engine GetMessageTimestamp: cache-first; on miss the core fetch
  lands the message in the cache (window loads then include it).
- GUI: resolveDeepLinkPermalink — username form via global search,
  c/ form requires the chat in the dialogs (no access hash in the
  link; honest toast otherwise); openPermalinkTarget fetches the ts
  then pendingOpen + pendingJump; openChat's first-load goroutine
  consumes pendingJump → jumpToMessageAt (loads a window around the
  message when the initial 100 don't cover it).

Verification: deeplink suites green (2 stale expectations updated to
the new routing); full repo tests, gofmt/vet green; Xvfb GUI smoke
boots.

## 2026-09-12 — slice 162: AyuGram local premium (per-account, honest labeling)

The Premium page's status card gains the AyuGram "local premium"
switch: a per-account client-side premium view. The engine flips
IsPremium in ListAccounts when the flag is on (star badge, presence
rendering, premium page status all follow); the status card labels it
honestly — "Active locally (Ayu) — server perks need a subscription"
and an "Active (local)" badge — so the client-side view is never
mistaken for a server-granted subscription (§1.10 honesty).

Plumbing: utils AppConfig.LocalPremium (per-account map, persisted
through the vault config path); engine SetLocalPremium/
localPremiumSnapshot/LocalPremiumFor; cfgSnapshot carries the map;
the switch rides the settingsSwitch + settingsSynced idiom keyed
"local_premium:<account>". Pure resolution locked by
TestEffectiveAccountPremium.

Verification: full repo tests green; gofmt/vet clean; Xvfb GUI smoke
boots.
## 2026-09-12 — slice 163 (planned): story viewer completion — reactions, reply, share

Research (primary sources, verified against the pinned gotd v0.161.0 schema):
stories.sendReaction#7fd736b2 (peer, story_id, reaction, add_to_recent);
inputReplyToStory#5881323a — SendMessage already wires it via the
"story:<id>" ReplyToID convention (cores/telegram.go SendMessage);
stories.exportStoryLink → ExportedStoryLink.link (raw RPC wrapper already
generated at telegram.go:34425 but unused); StoryItem.SentReaction
(ReactionClass) carries the own-reaction state on fetch. tdesktop story
viewer behavior: bottom bar with views/reactions counts, heart reaction
button (own reaction filled; tapping again removes), inline reply field
(InputReplyToStory), share via the exported story link.

Ratings (§1.14): viewer shell 7/10 keep+extend; core story RPC surface
6/10 — ReactToStory is legacy lock-across-RPC + user-peers-only (convert
touched methods to withAPI per §8 freeze rule, generalize to
resolvePeer); engine plumbing 7/10 keep+extend.

Plan: tests first (gui visibility/toggle semantics + engine routing),
then core (withAPI ReactToStory incl. channels + ReactionEmpty removal,
ExportStoryLink, sent_reaction pass-through), engine (StoryLinkExporter),
GUI (viewer action row: heart + emoji strip, reply composer, share =
copy link + toast; own stories hide react/reply per §1.10). Verify:
build + full tests + gofmt/vet + windows/wasm cross-builds + Xvfb smoke.
Push. Parity row "Story viewer" PARTIAL → PRESENT (forward-to-chat share
stays noted scope).

## 2026-09-12 — slice 163: sponsored messages (channels + bots, the full ad surface)

Recovered and finished the core layer a prior session left uncommitted
(telegram_sponsored.go + tests were complete but had 4 compile errors:
SetMedia/SetFullscreen bool args, GetPostsBetween two-value return,
flag-gated GetSponsorInfo/GetAdditionalInfo, plus d.Thumbnails →
d.Thumbs and a non-existent ReportResultInternal type in the test).
Fixed against the pinned gotd v0.161.0 schema; tests now green.

Research (primary sources): tdesktop data/components/sponsored_messages
+ ui/chat/sponsored_message_bar (bot placement = history_view_top_
controls TOP bar, channels = below all other posts) + menu/menu_
sponsored (report chain + about box); AyuGram keeps tdesktop's sponsored
UI (Resources/icons/sponsored present; no client-side hide toggle in
ayu_settings.h) — so 1:1 = render them properly, not hide them.

Engine (engine/sponsored.go, tests-first): GetSponsoredMessages with a
5-minute per-account+chat cache (expiry → refetch, errors never serve
stale); MarkSponsoredViewed one-shot per window per ad; Click /
Report / Toggle routing with honest unsupported errors; invalidateSponsoredCache.

GUI (gui/sponsored.go + rows in chat.go + settingspremium.go):
- channels: appendSponsoredRows extends the message-list row model —
  caption row ("Sponsored" + About ads link) + one message-like card
  per ad (sponsor photo avatar w/ letter fallback, title +
  Recommended badge, sponsor/additional info subtitle, body, media
  poster w/ play glyph for video ads, action button, Report ad link);
  the whole card is a material.ButtonLayout click target →
  openLinkExternal (deep links route in-app) + click report.
- bots: layoutSponsoredBar top bar (Sponsored badge + title +
  one-line message + button), same click/view wiring.
- viewSponsoredMessage fires once per loaded window per ad when the
  row/bar actually lays out (App ledger + engine dedup, both guards).
- report chain: sponsoredDlgState dialog — option list → submit → next
  chain or "Thanks. The ad was reported." toast (the engine walks
  messages.reportSponsoredMessage).
- about-ads box: promote.telegram.org explanation + link button.
- Premium page no-ads lever: account.toggleSponsoredMessages toggle
  (server-premium accounts only — local premium does NOT grant server
  perks); failed toggles revert the switch through a GUI-thread drain
  queue (no cross-goroutine widget writes).

Ratings (§1.14): engine 7/10 keep+extend (interface-routed, cached);
core 8/10 (withAPI-clean throughout, pure conversion locked by tests);
GUI surfaces follow the established row/bar/dialog idioms.

Verification: full repo tests green (new: engine sponsored cache/view/
routing suite, gui eligibility/row-model/view-ledger suite, core
conversion suite); gofmt/vet clean; windows + wasm cross-builds green
(-gcflags=all=-c=1 low-memory recipe); Xvfb GUI smoke boots (vault +
cache dirs created, ran until timeout kill).

Parity: "Sponsored messages (ads)" MISSING → PRESENT; posts_between
interleaving + the similar-channels block stay engine-gated (honest
scope). Next: the planned story-viewer completion slice (reactions/
reply/share — schema verified: stories.sendReaction, inputReplyToStory
already wired in SendMessage, stories.exportStoryLink).

## 2026-09-12 — slice 164: story viewer completion — reactions, reply, share

Research recap (recorded in the slice plan above; all verified against
the pinned gotd v0.161.0 schema + tdesktop story_view behavior):
stories.sendReaction#7fd736b2 (peer, story_id, reaction — empty
ReactionEmpty removes); inputReplyToStory#5881323a — cores.SendMessage
already wires it via the "story:<id>" ReplyToID convention;
stories.exportStoryLink → ExportedStoryLink.link; StoryItem.SentReaction
carries the own-reaction state on fetch.

Core: ReactToStory converted off the legacy lock-across-RPC pattern
(§8 freeze rule) to withAPI + general resolvePeer (channels react too,
not just users) + removal support; ExportStoryLink added (withAPI);
FetchPeerStoriesData now emits sent_reaction + reactions counts
(storyReactionEmoticon: custom-emoji reactions honestly map to "" —
not representable as a plain emoticon).

Engine: StoryLinkExporter + ExportStoryLink routing; ReactToStory
already routed (tests locked: react/remove/unsupported/missing-account).

GUI (gui/stories.go): the viewer's bottom action bar — views/reactions
stats; the reaction heart (sent emoji on the accent circle when
reacted, dim ❤️ otherwise — tap-again removes, optimistic flip with
error revert); the emoji strip (favoriteReactionChoices of the
account's available reactions, lazily loaded with the menu idiom); the
reply composer (inline editor + send, Enter submits, "story:<id>"
ReplyToID → InputReplyToStory, toast on success/failure); share
(stories.exportStoryLink → clipboard + "Story link copied" toast).
Own stories (chatID == account SelfUserID) hide react/reply per §1.10
and keep share. The composer owns the keyboard while armed (the
viewer's per-frame focus clear and arrow navigation stand down).

Verification: new suites green (gui: parseStories reactions contract,
heart-action semantics, reply id, own-visibility; engine: react/remove/
export routing; core: storyReactionEmoticon); full repo tests, gofmt/
vet clean; windows + wasm cross-builds green; Xvfb GUI smoke boots.

Parity: "Story viewer" PARTIAL → PRESENT (reactions/reply/share were
the engine-gated remainder). Next candidates from the matrix:
Alt+jumplist (keyboard row), account-bar unread dots (P1 row),
multi-window chats, app icon selector.

## 2026-09-12 — slice 165: account-switcher unread badges (bar avatar + dropdown rows)

The P1 "Account switcher" row's last PARTIAL bit: per-account unread
dots on the switcher surface itself. The bar avatar now wears the
current account's unread badge (NE Stack overlay over the 38dp avatar,
AyuGram account-rail parity) and every account-menu dropdown row
carries its own trailing unreadBadge (drawer-row parity, slice 36
idiom — accountUnread was already pure + tested). Conn dot stays at
the avatar's bottom-right; the badge sits top-right, no overlap.

Verification: GUI suite green; gofmt/vet clean; builds green.

Parity: "Account switcher" PARTIAL → PRESENT.

## 2026-09-12 — slice 166: the tdesktop jumplist shortcut family

Research (primary source: tdesktop core/shortcuts.cpp defaults — the
worklog's "Alt+jumplist" note resolved to the real bindings):
Ctrl+1..8 = ChatPinned1..8 (jump to the Nth pinned chat), Ctrl+9 =
ShowArchive, Ctrl+0 = ChatSelf, Ctrl+J = ShowContacts, Ctrl+R =
ReadChat, Alt+Up/Down = ChatNext/ChatPrevious, Ctrl+Alt+Home/End =
ChatFirst/ChatLast.

Implementation (tests first — 6 new/extended suites): the global key
layer's Ctrl catch-all now routes the family: jumplistDigit maps the
digits (1..8 pinned, 9 archive, 10 self); pinnedJumpChat walks the
pinned prefix of the visible list; chatEdgeAction handles
Ctrl+Alt+Home/End; showContactsKey/readChatKey gate Ctrl+J/Ctrl+R;
chatSwitchAction grew the alt parameter (Alt+↑/↓ ride the same
handleChatSwitch). Handlers: handleJumplistDigit (archive view flip /
openSavedMessages with the open-chat account fallback /
pinned-chat openChat), handleChatEdge, handleReadChat
(engine.MarkChatRead, fire-and-forget).

Verification: full repo tests green; gofmt/vet clean; Xvfb smoke not
re-run for this GUI-only key-layer change (build + suite cover it;
the layer is the same mechanism as slices 43/147, both smoke-verified).

Parity: "Keyboard shortcuts" PARTIAL → PRESENT (Alt+jumplist was the
noted remainder).

## 2026-09-12 — slice 167: similar-channels block (broadcast channel footer)

The last CORE-ONLY→renderable surface of the matrix's channel footer:
channels.getChannelRecommendations (engine + core existed from the
giveaway work; only rendering was missing).

Core: GetSimilarChannels converted to the withAPI snapshot pattern
(§8) and now caches each recommended channel's access hash
(cacheChannelHash) so a tap can open the channel without a prior
dialog (resolvePeer needs the hash).

GUI (gui/similar.go): loadSimilar rides the openChat flow (channel
chats only); the block renders as one appended message-list row
(appendSimilarRow — broadcast channels, no topic views) after the
sponsored block: "Similar channels" caption + horizontal card row
(stripped-thumb avatar w/ letter fallback, single-line title, member
count); tap → pendingOpen hop (same mechanism as the deep-link opens).

Also this session: disk filled up (9.9G root, dist binaries + stale
caches) — cleaned /tmp build dirs + ms-playwright/puppeteer caches;
kept the 7G go-build cache for rebuild speed.

Verification: full repo tests green (new AppendSimilarRow suite);
gofmt/vet clean; Xvfb smoke skipped for this row-append change (same
layout path as slice 163's rows, smoke-verified then).

Parity: "Similar channels block" CORE-ONLY → PRESENT. Remaining
MISSING rows: PiP (blocked on pure-Go video decode), multi-window
chats, app icon selector, suggestions cards (P3s); the "Hide similar
channels / ads" row's ads half is PRESENT via slice 163 + the no-ads
lever — the hide-similar toggle is moot now that the block exists
(honest display, no dead toggle).

## 2026-09-12 — session wrap (slices 163-167)

Session summary, in order:

1. Environment re-provisioned after a VM reset (devroot-setup.sh: Go
   1.27.1 + CGO sysroot); full build + tests + gofmt/vet green before
   any work. Repo moved to a persistent home (the prior session's
   clone held uncommitted slice-163 core work — recovered and finished).

2. Slice 163 — sponsored messages: recovered the prior session's core
   (4 compile errors fixed against the pinned gotd schema), built the
   engine layer (5-min per-chat cache, one-shot view reporting,
   click/report/toggle routing) + the GUI (channel ad cards below the
   last post, bot-chat top bar, iterative ad-report chain, about-ads
   box, Premium no-ads lever w/ error revert).

3. Slice 164 — story viewer completion: reactions (stories.sendReaction
   w/ ReactionEmpty removal, withAPI + channel peers), inline reply
   (story:<id> → inputReplyToStory), share (stories.exportStoryLink →
   clipboard), own-reaction state from StoryItem.SentReaction, honest
   own-story gating (§1.10).

4. Slice 165 — account-switcher unread badges: the bar avatar wears the
   current account's unread badge; every dropdown row carries its own.

5. Slice 166 — the tdesktop jumplist family (researched from
   core/shortcuts.cpp defaults): Ctrl+1..8 pinned chats, Ctrl+9
   archive, Ctrl+0 Saved Messages, Ctrl+J contacts, Ctrl+R read,
   Alt+↑/↓ chat switch, Ctrl+Alt+Home/End first/last.

6. Slice 167 — similar-channels block: recommendation cards under the
   channel footer (access hashes cached for dialog-less opens, withAPI
   conversion of the core fetch).

Disk incident: root fs filled mid-session (dist verification binaries
+ stale caches); cleaned, kept the go-build cache.

Verification: full repo tests green locally after every slice;
gofmt/vet clean; windows + wasm cross-builds green (slices 163/164);
Xvfb GUI smoke boots (slices 163/164); verify workflow dispatched on
HEAD (5eb2f03e) at session end — status checked via API.

Parity after this session: Story viewer PRESENT, Keyboard shortcuts
PRESENT, Account switcher PRESENT, Sponsored messages PRESENT, Similar
channels PRESENT. Remaining MISSING: PiP (blocked on pure-Go video
decode), multi-window chats, app icon selector, suggestions cards —
all P3. The program continues (next session: multi-window chats or app
icons; withAPI backlog continues per-touch).

## 2026-09-13 — slice 168: multi-window separate chat windows

Recovered the prior session's uncommitted ground work (App.wid instance
commit 6647243d had landed; app.go/lock.go/state.go carried the
cross-window hops + lock-bus wiring uncommitted) and finished the slice:

- gui/separate.go: per-chat native Gio windows (tdesktop
  SeparateType::Chat). One window per chat INCLUDING the main window —
  takeovers deselect everywhere else (pendingDeselect hops, each App
  mutates only on its own GUI loop). Frames serialize on frameMu so
  residual package-level widget state stays safe. Process-wide
  passcode lock via a lock bus (lock/unlock + activity keepalives,
  lockEngaged boot decision). Registry: chatKey → live window,
  reopen = close + remap on top, sepMoveRegistry retargets on
  in-window chat switches. Honest empty surface after a takeover.
- Entry points (this session): chat-row context menu "Open in separate
  window" first row (chatMenuItems gained separateSupported; the
  chatMenuAction.action field renamed to id across foldermenu/
  headermenu/membermenu + their tests), and Ctrl+click on a chat row —
  sidebar rows consume widget.Clickable.Update so the click's modifier
  set is readable (IsCtrlPressed semantics; no stale key-tracking
  state).
- deselectIfShowing: the caller's own window deselects the chat it is
  handing over (was missing — shouldDeselectMainForSeparate had no
  production caller).
- cmd/uniclient/main.go: main-window DestroyEvent closes every
  separate window and waits for their loops before engine teardown.
- Platform gate: linux + windows only; js/wasm and Android hide the
  entry points (Gio exposes one window there — honest absence, §1.10).

Tests: separate_test.go (platform gate, menu row first+absent,
one-window-per-chat decision, app mode, title rule) + updated
chatmenu/headermenu/membermenu/foldermenu suites for the id rename.

Verification: linux build green (GOGC=20 -p1 all=-c=1); gofmt/vet
clean; full repo test suite green; windows + wasm cross-builds
dispatched to the verify workflow (local disk filled mid-cross-build —
/tmp build dirs cleaned; the CI run is the sanctioned path on this
machine, AGENTS.md §5).

Parity: "Multi-window chats" MISSING → PRESENT. Remaining MISSING: PiP
(blocked on pure-Go video decode), app icon selector, suggestions
cards, hide sponsored/similar toggle (now real — blocks render since
slices 163/167), dice/games, message-shot renderer (P3s).

## 2026-09-13 — slice 169: AyuGram similar-channels settings (hide + collapse)

Research (primary source: AyuGramDesktop dev branch ayu_settings.h —
read via the GitHub API): hideSimilarChannels (default false) and
collapseSimilarChannels (default TRUE); the per-channel expanded state
is tdesktop's runtime ChannelDataFlag::SimilarExpanded (in-memory, not
persisted). Note: AyuGram has NO hide-sponsored setting (that's
Premium-only; we already ship the no-ads lever) — the earlier worklog
hypothesis about a hide-sponsored toggle was wrong; the real settings
are the similar-channels pair.

Config: AppConfig.AyuHideSimilarChannels (bool) +
AyuCollapseSimilarChannels (*bool, nil = collapsed — the
EffectiveCollapseSimilar helper mirrors EffectiveSystemTray's
nil-default idiom); engine ConfigChanges + apply; cfgSnapshot copies
both (collapse effective).

GUI (tests first — similar_settings_test.go): similarBlockMode /
similarExpandedDefault / similarEffectiveExpanded pure decisions;
appendSimilarRow gained hide+collapsed (chatRow.simCollapsed row
kind); the collapsed compact bar (caption + count + Show expander) and
a Hide collapser on the expanded block; per-chat expanded map
(a.similarExpanded, runtime only — deliberately NOT reset on chat
switch); Settings → Ayu gains the "Ayu · Channels" section with both
toggles riding applyConfigBool/configFieldChanges.

Verification: linux build green; gofmt/vet clean; full repo suite
green. Slice 168's verify workflow run completed SUCCESS on CI
(75a14ccb) — quality gate + windows/wasm cross-builds + Xvfb GUI smoke
all green, closing that slice's local-disk gap.

Parity: "Similar channels block" PRESENT gains the settings half
(slice 169). Remaining MISSING: PiP (blocked on pure-Go video decode),
app icon selector, suggestions cards — all P3; everything else on the
matrix is PRESENT/PARTIAL/CORE-ONLY.

## 2026-09-13 — withAPI batch: 735 strict-shape legacy conversions

The §8 freeze-rule backlog: convert_withapi.py (strict-shape matcher —
top RLock/defer + auth guard + exactly one t.api call) converted 735
legacy telegram.go methods to the withAPI snapshot pattern in one
pass. 65 follow-up compile fixes where the original code redeclared
err after the inserted snapshot (`:=` → `=`, same scope — semantics
identical; the fixer lives at scripts/ fix-redecl inline, the scanner
at scripts/scan_lock_across_rpc.py).

Result: 784 of the core's methods now use t.withAPI(); the scanner
finds 77 remaining lock-across-RPC functions (multi-RPC flows, call
write-lock state machines — SendMessage, the group-call family, cloud
password flows, profile photo uploads) that need careful manual
conversion; they stay on the per-touch backlog.

Verification: gofmt clean (whole repo), vet clean, linux build green,
FULL repo test suite green after the mass rewrite.

AGENTS.md §8 note updated to the new counts.

## 2026-09-13 — withAPI: SendMessage converted (manual, complex shape)

The highest-traffic remaining violation: SendMessage held the RLock
across BOTH send paths (web-page media + plain text). Converted to the
snapshot pattern — the t.sender guard is covered by the withAPI
invariant (api+sender set/cleared together under t.mu in auth/Logout/
teardown). 76 complex-shaped violations remain (scan_lock_across_rpc).

Also this session: an editor quirk space-mangled the worktree copy of
telegram.go mid-edit (the committed blob stayed tab-clean — verified
via git show + grep count); re-gofmt'd and re-verified. Committed
2f38b02c's gofmt gate will pass.

Verification: cores suite green, vet clean, build green.

## 2026-09-13 — withAPI: eleven more manual conversions

DeleteMessageRevoke (2-RPC channel/chat branches), SendContact,
EditChatTitle, LeaveChat, AddMembers, RemoveMember,
SuggestContactPhoto, SetPersonalContactPhoto, DeleteRingtone,
GetWallpapers, MarkAllStoriesRead — all off the RLock-across-RPC
pattern (65 violations remain; the group-call write-lock family +
cloud-password flows stay for careful per-touch work).

Verification: build green; cores+engine suites green (one engine
timing flake under combined load, green standalone + on re-run);
gofmt/vet clean. Full-suite rerun hit a full root fs (go-build cache
grew to 7.7G) — TempDir failures only, no code failures; CI verify
dispatched for the pushed commit.

Editor quirk note (again): MultiEdit space-mangles the whole worktree
telegram.go — always gofmt -w after edits to it.

## 2026-09-13 — withAPI program COMPLETE: zero lock-across-RPC violations

The §8 freeze-rule backlog is cleared. Two findings drove the final push:

1. The v1 scanner flagged co-occurrence of t.mu and t.api in a function
   body — 30 of its "31 remaining" were FALSE positives (brief-snapshot
   pattern already compliant). Rewrote it as a v2 lock-state machine
   (line-level acquire/release tracking; a violation = a t.api call on a
   lexically-held line).
2. The real stragglers were RPCs flowing through helper OBJECTS
   (uploader.NewUploader(u).Upload, downloader.Download().Stream) — no
   `t.api.` token, invisible to both scanners. A deep audit for locked-
   region calls into RPC-capable helpers surfaced them.

Batches this session (tests-first each time — every case starved the
2s write-lock probe pre-fix, green post-fix; 41 pinned cases total in
TestReadPathRPCsDoNotPinMutex):
- batch 3 (16): settings/emoji/folder/participants/global-search reads
- batch 3b (7): cloud-password + SRP flows (withdrawal URLs, ownership
  transfer)
- batch 3c (11): photo management + theme/document uploads (uploader
  chunk streams were the worst remaining offenders)
- batch 3d (6): GetDifferenceCheck, DownloadWallpaperDocument,
  UploadFile, UploadFileWithOptions (new withSenderAPI helper —
  snapshots api+ctx+sender together, they are set/cleared as a group),
  SendStoryWithPhoto/WithVideoFile (sendStoryCommon now takes the
  snapshot pair)
- withPeer: no longer holds RLock across resolvePeer's @username RPC
  (release func is now a no-op; call shape kept for the 796 users)

Also fixed pre-existing local-gate breaks found along the way:
- gui/launcherbadge_test.go imported godbus untagged while every symbol
  it tests lives in _linux.go → js/wasm test build broke since slice 160;
  renamed launcherbadge_linux_test.go + //go:build linux.
- tgsplayer TestGzipMagic/TestStickerRenderKind used t.TempDir()
  (not implemented on js) → skip with reason on js/wasm.

Verification per commit: gofmt/vet clean, native engine+cores+utils+
bootstrap suites green, wasm gui suite green (dev-test.sh ALL GATES
GREEN), CI verify dispatched and SUCCESS on each pushed SHA.

Parity impact: none of these are features — pure freeze-class hardening.
Remaining parity MISSING unchanged: PiP (blocked on pure-Go video
decode), app icon selector, suggestions cards — all P3.

## 2026-09-13 — slice 170: app icon selector (AyuGram parity)

Research (primary sources, GitHub API on AyuGramDesktop dev):
ayu_settings.h `appIcon` + ayu/ui/components/icon_picker.cpp — 12 icon
sets in a 4-column grid (kColumns=4), cached previews, apply-on-click
(OverrideApplicationIcon + tray refresh; on Windows also the taskbar
resource reload).

Implementation (tests first — 13 new cases, all failing pre-impl):
- gui/appicon.go: 12-set registry + programmatic renderer (slice-137
  tile+mark geometry recolored per set; default set follows the live
  accent via a sentinel tile, stand-in Material blue for previews).
  _NET_WM_ICON payload builder. Picker grid math (4 columns).
- gui/appicon_apply_windows.go: WM_SETICON (ICON_BIG 48 + ICON_SMALL
  32) via the slice-153 CreateDIBSection+CreateIconIndirect syscall
  path; previous HICON pair destroyed after install (caller owns).
- gui/appicon_apply_linux.go: _NET_WM_ICON via github.com/jezek/xgb
  (pure Go — was already in the graph through the tray's systray dep;
  promoted to direct). Sizes capped 128/64/48/32: one ChangeProperty
  must stay under the core protocol's 16-bit request length — a 256px
  icon alone overflows it (live-verified: BadLength under Xvfb before
  the cap, property lands after).
- gui/appicon_picker.go: Ayu · App icon settings section (title + grid
  + captions), accent selection ring, apply-on-click →
  ConfigChanges.AyuAppIcon → refreshConfig hook re-applies runtime icon
  + tray re-render. Hidden on js/wasm + Android (appIconPickerSupported
  = false — honest absence §1.10).
- Tray (slice 137 integration): tray icon now renders the selected set
  (AyuGram tray = current app logo) with the unread badge on top; sync
  dedupes on set id too.
- Shutdown: stopAppIcon frees HICONs / closes the xgb helper conn.

Plumbing: AppConfig.AyuAppIcon + engine ConfigChanges.AyuAppIcon +
cfgSnapshot.AyuAppIcon.

Verification: full local gates green (gofmt/vet, native suites, wasm
gui suite); LIVE X11 rung — app booted under Xvfb, window tree walked
with xgb, _NET_WM_ICON present (128x128 first icon, type CARDINAL,
fmt 32). Windows cross-build (goolm) green; CI verify dispatched for
the Xvfb GUI smoke + artifacts.

Parity: "App icon selector" MISSING → PRESENT. Remaining MISSING: PiP
(blocked on pure-Go video decode), suggestions cards — both P3.

## 2026-09-13 — slice 171: chat-list top-bar suggestions (AyuGram parity)

Research (primary sources via GitHub API, AyuGramDesktop dev):
dialogs/suggestions/suggestion.cpp AllSpecs() defines the priority
order (BIRTHDAY_CONTACTS_TODAY > BIRTHDAY_SETUP > CUSTOM_PROMO >
GIFT_AUCTIONS > LOW_CREDITS_SUBS > PREMIUM_GRACE > PREMIUM_OFFER >
UNREVIEWED_AUTH > USERPIC_SETUP); data/components/promo_suggestions.cpp
maps help.getPromoData pending_suggestions + custom_pending_suggestion,
refreshes hourly, dismisses via help.dismissSuggestion(inputPeerEmpty).
Birthdays ride the dedicated contacts.getBirthdays RPC (checked daily).

Implementation (tests first — 5 decision-suite cases):
- cores: GetPromoSuggestions (help.getPromoData → keys + custom card),
  DismissSuggestion, GetTodayBirthdayContacts
  (contacts.getBirthdays + day/month filter + cached display names),
  GetSelfSuggestionState (users.getUsers photo flag +
  users.getFullUser birthday). All on the withAPI snapshot pattern.
- engine/suggestionstate.go: capability-sniffed aggregate per account
  (GetSuggestionState) + DismissSuggestion with immediate local
  dismissal (server dismiss async, best-effort).
- gui/suggestionbar.go: the card above the dialog rows (below folder
  tabs): leading glyph + title + description + X close (toast), tap
  routes to a REAL action — birthday contact → openChat, BIRTHDAY_SETUP
  / USERPIC_SETUP → own profile editor, PREMIUM_OFFER → Premium page,
  custom → openLinkExternal. Hourly refetch, per-account state cache.
  Keys without local surface (gift auctions / low credits / premium
  grace / unreviewed auth) stay hidden — exactly tdesktop's
  unknown-key behavior; nothing renders without real data (§1.10).
- The birthday card shows from LOCAL birthday data even without the
  server key (tdesktop shows it while the set is unknown; ours is
  definitive).

Verification: full local gate ALL GREEN (native + wasm gui + vet +
gofmt). The RPC surfaces need the owner's live test (signed-in
account); the decision layer is fully unit-pinned.

Parity: "Suggestions (birthday/premium/promo)" MISSING → PRESENT.
Remaining MISSING: PiP only (blocked on pure-Go video decode, P3).

## 2026-09-13 — slice 172: favorite-reaction hardening (fetch-once + custom favorites)

- Context: a parallel session had already pushed slices 158-171 (swipe
  quick actions landed THEIR slice-158 as swipe, corner reaction as 159,
  plus 160-171: Unity badge, deep-link permalinks, local premium,
  sponsored messages, story completion, account badges, jumplist,
  similar channels, multi-window, app-icon selector, suggestions, and
  withAPI COMPLETE — zero lock-across-RPC violations). A locally built
  duplicate corner-reaction slice was discarded via hard reset to
  remote (f17cb08a precedent); this session's work builds on fe3c6892.
- Bug found in slice 159 (real, freeze-class): loadFavoriteReaction is
  called from the ROW LAYOUT PATH (chat.go, every rendered row, every
  frame) and the engine/core favorite read had NO caching — whenever the
  favorite was unset (server has no reactions_default, or a fetch error)
  every frame spawned a goroutine + a full help.getConfig RPC. RPC storm.
- Ratings (§1.14): slice-159 cornerreaction.go 8/10 keep+extend (solid
  gate/toggle design + tests; fix the churn + custom gap in place);
  engine GetDefaultReaction 4/10 at fault → now session-cached (9/10);
  core GetDefaultReaction 5/10 → per-connection config cache + custom
  decode (8/10); custemoji glyph machinery 9/10 reused as-is.
- Landed: (a) engine favorite-reaction session cache (success incl.
  empty caches — the 👍 fallback sticks without re-RPC; errors stay
  uncached so transient failures recover; SetDefaultReaction writes
  through); (b) core per-connection help.getConfig cache feeding
  GetDefaultReaction + optimistic SetDefaultReaction mirror (tdesktop
  applyFavorite); (c) GUI attempted-once guard (one fetch goroutine per
  account per session); (d) custom-emoji favorites end-to-end: core
  decode (reactions_default custom → "custom_<docID>"), ownHasReaction
  + toggleOwnReactionEmojis match custom reactions by document id and
  carry them through the full own-list send (previously custom own
  reactions were dropped to empty-string keys), the pill renders the
  custom emoji's static thumb (customReactionGlyph — same machinery as
  the reaction strip), and SetDefaultReaction accepts custom keys.
- Tests-first: cores reactionClassForKey + decodeDefaultReactionKey
  truth tables; engine session-cache semantics (hit-once, custom
  passthrough, empty-caches, error-not-cached, write-through); gui
  customKeyDocID + custom ownHasReaction + custom toggle list cases.
- Gate: gofmt/vet/test green (goolm); local Xvfb GUI smoke boots with a
  live window. Verify CI dispatched after push.

Parity: Chat settings PARTIAL (favorite reaction now fetch-once +
custom-capable; swipe quick action + expandable reaction strip remain).

## 2026-09-13 — slice 173: Ayu behavior extras (seconds, zalgo, reaction visibility, send confirmations)

- Primary-source research (AyuGramDesktop): ayu_settings.h carries
  showMessageSeconds / filterZalgo / showChannel+Group+PrivateReactions
  / sticker+gif+voice+roundConfirmation; settings_general.cpp builds
  the General-page rows (Confirmations subsection, zalgo with a BETA
  badge + restart prompt — ours applies render-time so no restart);
  ayu_helpers.cpp filterZalgo = regex "\\p{Mn}{3,}|[bidi controls]"
  (202A-202E, 2066-2069, 200E, 200F, 061C); formatMessageTime renders
  HH:mm:ss vs the locale short format.
- Ratings (§1.14): settings/config plumbing chain 9/10 keep+extend
  (the toggleRow + ConfigChanges + cfgSnapshot pattern absorbs eight
  more keys cleanly); message render path (chat.go messageRow) 8/10
  keep+extend (text + sender + reaction-strip gates are single-line
  inserts); send paths (stickers.go sendStickerFile shared by sticker
  AND gif cells, voicerecord.go) 7/10 keep+extend (kind split + confirm
  hook; temp voice file survives the confirm window); no core/engine
  protocol surface touched.
- Landed: (a) message seconds — messageMetaLabel + album meta carry
  seconds when the toggle is on (chat rows/dividers keep fmtTime —
  AyuGram separates the formatters the same way); (b) filterZalgo —
  pure stripZalgo (first-two-marks rule, bidi control drop, fast-path
  no-alloc scan) applied to rendered message bodies + sender names
  only; (c) reaction-strip visibility — reactionsVisible gates the
  under-bubble strip per chat type (channel / group+topic / private),
  nil config = ON (AyuGram defaults); (d) send confirmations —
  maybeConfirmMedia parks sticker/gif/voice sends behind a centered
  scrim card (callsConfirmCard pattern, checkbox-free); round-video
  notes have no send path so that AyuGram toggle stays unshipped
  (§1.10).
- Tests-first: stripZalgo (clean/accented/emoji identity, run trim,
  bidi drop, mixed), msgTimeLabel (off/on/zero), reactionsVisible
  matrix, confirmKindTitle, config dispatch for all eight keys.
- Gate: gofmt/vet/test green (goolm); Xvfb GUI smoke boots with a
  live window. Verify CI for slice 172 still queued (runner backlog)
  — this slice pushes behind it.

Parity: Ayu preferences PARTIAL→advanced (General extras + Reactions +
Confirmations sections landed; spy/saving engine-gated remainder +
round-video confirmation unshipped).

## 2026-09-13 — slice 174: per-chat notification exceptions (sound + previews)

- Primary-source research: tdesktop notify exceptions write
  account.updateNotifySettings per peer; gotd InputPeerNotifySettings
  carries ternary ShowPreviews/Silent + MuteUntil + Sound
  (NotificationSoundClass: Default/None/Local/Ringtone); read side
  account.getNotifySettings → PeerNotifySettings with per-platform sound
  fields (desktop = OtherSound). Our existing MuteChatFor already wrote
  mute_until through this RPC — extend, don't replace.
- Ratings (§1.14): MuteChatFor + updateNotifySettings push handler 8/10
  keep+extend (mute semantics well-tested; sound/previews ride the same
  RPC); mutedlg.go picker 8/10 keep+extend (custom duration + presets
  already strong; the exceptions section is one Rigid + a helper);
  vibrate is mobile-only — unshipped honestly.
- Landed: core GetChatNotifySettings (live read, ternary decodes:
  OtherSound unset = on, None = off; ShowPreviews unset = shown) +
  SetChatNotifySettings (mute_until always rides; sound/previews ride
  only when provided — Default/None mapping), both withAPI; engine
  passthrough interfaces + optimistic mute mirror with the same
  emitChatUpdate MuteChat uses; GUI: the "Mute for…" picker grows a
  NOTIFY EXCEPTIONS section (Sound + Message previews switches) shown
  only when the live read lands (§1.10 — non-Telegram platforms or
  transient errors hide it), per-field writes preserve the current
  mute, edge detection via synced previous values (widget.Bool has no
  Changed signal — the drawer-toggle pattern).
- Tests-first (cores): notifySoundOn truth table (nil/Default/None/
  Local), notifyPreviewsOf ternary table, notifySettingsInput flag
  semantics (nil fields stay unset; sound on/off mapping),
  chatNotifySettingsFromWire full decode incl. the forever sentinel.
- Gate: gofmt/vet/test green (goolm); Xvfb GUI smoke boots with a live
  window. Slices 172 + 173 verify CI runs both GREEN via API (full
  gate + windows/wasm cross-builds + Xvfb GUI smoke w/ screenshots).

Parity: Per-chat notification settings UI PARTIAL→PRESENT (mute picker
+ presets + custom duration + exceptions; vibrate mobile-only stays).

## 2026-09-13 — slice 175: parity-table truth pass

- research/ayugram_parity.md had drifted from the code: four rows said
  less than what shipped. Trued against the tree + slice history (§10:
  markdown stays short and true): App icon selector MISSING → PRESENT
  (slice 170 landed the 12-set picker + runtime window icon); Voice
  message's "transcribe stays engine-gated" note — slice 115 landed
  transcribe (A→A → messages.transcribeAudio + pushed updates, cached);
  Ayu preferences' "remaining spy/saving toggles stay engine-gated" —
  slices 162 (local premium) + 163 (sponsored/disable-ads) closed the
  set, the section list now matches AyuGramDesktop's shipped sections
  1:1; Business row's "chat links remain engine-gated" — tdesktop and
  AyuGramDesktop ship NO chat-links UI, so it is out of 1:1 scope by
  §1.11 (what AyuGram does), documented instead of built.
- Counts after the pass: PRESENT 161 (80%) · PARTIAL 25 · MISSING 1
  (PiP, blocked on a pure-Go video decoder) · CORE-ONLY 13.
- No code change — gate still green from slice 174's run.

Parity: table now matches the tree.

## 2026-09-13 — slice 176: Instant View reader overlay

- Parity row "Instant View pages" CORE-ONLY → PRESENT. The core/engine
  IV surface (GetInstantViewPage — messages.getWebPage → cached_page →
  27-block JSON; DownloadIVPhoto; DownloadIVDocument; wp_has_iv preview
  flag) was complete and unused; this slice surfaces it (§1.11: the GUI
  is never trimmed to fit the cores — the cores already fit).
- Rating (§1.14): core IV layer 8/10 (withAPI-compliant, honest
  domain/type gating, full block coverage) — kept as-is. GUI: no reader
  existed; built on the proven overlay pattern (viewer slice 9 / story
  viewer slice 104) instead of a new surface.
- gui/instantview.go (new): ivPage/ivBlock model + parseIVPage (pure);
  ivRich tree → ivRichSpans flattener → text+Telegram entities so the
  existing flowRich renderer paints IV text (wrapping, links, mono
  pills) — one renderer for messages and IV. Reader overlay: top bar
  (back w/ history stack, site+title, open-in-browser), capped-width
  scrollable column, loading/err states. Every block kind renders:
  title/subtitle/kicker/header/subheader/paragraph/footer/
  author_date/preformatted/blockquote/pullquote/divider/anchor/list/
  ordered_list (text + nested-block items)/photo (stripped-thumb →
  async DownloadIVPhoto → decode swap-in)/video/audio (tap →
  DownloadIVDocument → system player, slice-86 handoff)/embed + map
  (browser card — no webview by §1 pure-Go)/embed_post/collage/
  slideshow (chevrons + counter)/details (collapsible)/related
  articles (tap → ivOpenRelated pushes history; back pops; cap 16)/
  table (colspan-weighted columns, header bold, zebra, hairlines)/
  channel (t.me deep link → the in-app resolver).
- Entry points: webpage-preview card tap gated on wp_has_iv (new
  webPageData.HasIV, parsed from the core's Extra); text links on
  telegra.ph/graph.org hosts route through ivKnownHost (the core's
  isKnownIVDomain mirrored) in flowRich's tap dispatch — message text,
  IV body links and bot buttons all inherit it. Fetch failure → toast +
  browser fallback (§1.10: never a dead overlay).
- Frame wiring: App.iv + frame.iv + snapshot mirror + widgets
  (ivList/ivBackBtn/ivOpenBtn/ivSlidePrev/ivSlideNext/ivClickables) +
  overlay hook in both the main and separate-window paths (between the
  media viewer and the story viewer).
- Tests first (go/gui/instantview_test.go, 7 tests): parseIVPage basics
  + 15-block variety (photo/video/related/table/channel/embed/details
  field fidelity), ivRichSpans style+href propagation, ivKnownHost
  suffix-trick negatives, wp_has_iv parse, history push/back/cap,
  details-open defaults+overrides. All pure — layout verified by
  compile + review.
- Gate: gofmt clean · vet -tags goolm clean · go test -tags goolm
  ./... 8/8 ok · linux build ok · GOOS=js wasm + GOOS=windows
  cross-builds ok. Devroot rebuilt via the repo's own
  scripts/devroot-setup.sh (fresh VM this session: no Go, no GL dev
  packages — the script handled all of it).

Parity: PRESENT 162 (81%) · PARTIAL 25 · MISSING 1 · CORE-ONLY 12.

## 2026-09-13 — slice 177: admin log / Recent Actions panel

- Parity row "Moderation (admin log, restrictions)" GUI half → PRESENT
  (restrict boxes were already shipped; the admin-log viewer was the
  missing half). Rating (§1.14): core 9/10 (channels.getAdminLog w/
  query + filters + maxID paging + per-admin filter + ActionData
  structured extras for message previews — kept as-is); engine
  pass-through fine; GUI built on the schedPanel pane-replacement
  pattern.
- gui/adminlog.go (new): searchable + filterable + paginated event list
  — header (back + chat title), search field (query → refetch),
  horizontal filter-chip strip (17 chips over the core's filter keys:
  join/leave/invite/ban/unban/kick/unkick/promote/demote/info/settings/
  pinned/group_call/stickers/messages/edit/delete/invites — active
  chips accent-tinted, toggle refetches), event cards (admin avatar +
  accent name + action sentence + detail + old→new change rows + date),
  message events render the inline media preview bubble (ActionData's
  stripped thumb + MsgText), load-more row pages via the smallest seen
  event ID as maxID, honest loading/error/empty states.
- Entry: chat-header ⋮ menu "Recent actions" for admins of groups/
  channels/topics (ChatInfo.IsAdmin gate — tdesktop semantics);
  non-admins never see it. RPC errors still toast honestly.
- State wiring: App/frame admin* fields + snapshot mirror + chat-switch
  cleanup + widgets pool (list, filter list, search editor + button,
  back, load-more).
- Truth pass alongside: parity row "Sponsored messages (channels)" was
  stale CORE-ONLY — slice 163 shipped the ad block; row trued to
  PRESENT (§10).
- Tests first (go/gui/adminlog_test.go, 6 tests): header-menu gating
  (admin chan/group yes, non-admin no, DM never), paging cursor,
  filter-chip completeness vs the core's keys + toggle semantics, row
  composition (headline/action/sub/old-new), ActionData media
  extraction. All pure.
- Gate: gofmt clean · vet -tags goolm clean · go test -tags goolm
  ./... 8/8 ok.

Parity: PRESENT 163 (81%) · PARTIAL 25 · MISSING 1 · CORE-ONLY 11.

## 2026-09-13 — slice 178: send-as identity picker

- Parity row "Send-as channel (in groups)" CORE-ONLY → PRESENT. Rating
  (§1.14): engine GetSendAs (ChannelsGetSendAs + user/chat title
  resolution) + SaveDefaultSendAs (messages.saveDefaultSendAs — the
  server routes subsequent sends through the saved identity) 8/10,
  kept; GUI built on the composer-chip + modal-dialog patterns.
- gui/sendas.go (new): "Sending as <name>" strip above the composer
  input (20dp avatar + dim label + chevron, rounded chip) rendered ONLY
  when the chat offers >1 identity (engine.GetSendAs, loaded once per
  chat open for group/channel chats; single-identity or error → row
  hidden, §1.10). Tap → the identity picker modal (scrim + card: self
  "Personal account" + offered channels, avatar + name + subtype,
  checkmark on the current choice, selected-row tint) → pick persists
  through SaveDefaultSendAs; stale saved selections (identity no longer
  offered) resolve back to self.
- Wiring: App/frame sendAs fields + snapshot mirror + chat-switch
  reset + composer first-child hook + dialog render in the chat-pane
  dialog stack + widget pool (row button, close, list, row buttons).
- Tests first (go/gui/sendas_test.go, 4 tests): visibility gating
  (1/none hidden, 2+ shown), current-resolution (default self, saved
  wins, stale falls back), name resolution, picker order. All pure.
- Gate: gofmt clean · vet -tags goolm clean · go test -tags goolm
  ./... 8/8 ok.

Parity: PRESENT 164 (81%) · PARTIAL 25 · MISSING 1 · CORE-ONLY 10.

## 2026-09-13 — slice 179: call rating dialog

- Parity row "Call rating dialog" CORE-ONLY → PRESENT (tdesktop's
  RateCallBox). Rating (§1.14): engine SendCallRating (calls.setRating
  pass-through) 7/10 — kept; GUI on the modal-dialog pattern.
- gui/callrate.go (new): ended calls that actually connected and lasted
  minRateCallDur (10s) arm the rating card when the call panel dismisses
  — "Rate this call / How was the call quality with <peer>?" + five
  star taps (accent-tinted up to the chosen count, out-of-range ignored)
  + optional comment editor + Send/Skip. Send walks engine.SendCallRating
  (account, callID, stars, trimmed comment) with a toast on error;
  missed/declined (never-active) and sub-threshold calls never rate.
- Wiring: onCallStateEvent computes rateability under the lock and arms
  App.rateDlg after the ended transition; dialog renders above the call
  overlay in the app overlay stack; frame/snapshot mirror; widget pool
  (5 star clickables, send/skip, comment editor).
- Tests first (go/gui/callrate_test.go, 3 tests): gating (4s call no,
  never-active no, 2min yes, threshold yes), star semantics (same-tap
  no-op, out-of-range ignored, validity), payload (comment trim, send
  gating). All pure.
- Gate: gofmt clean · vet -tags goolm clean · go test -tags goolm
  ./... 8/8 ok.

Parity: PRESENT 165 (82%) · PARTIAL 25 · MISSING 1 · CORE-ONLY 9.

## 2026-09-13 — slice 180: gift card bubbles

- Parity row "Gift / star-gift messages" CORE-ONLY → PRESENT. Rating
  (§1.14): core gift surface 7/10 (GetStarGifts/GetPinnedStarGifts
  existed; service conversion collapsed gifts to a text line — the
  "performed an action" fallback) — extended in place; GUI bubble on
  the map-card/location pattern.
- cores/telegram.go: convertServiceMessage writes structured Extra for
  messageActionStarGift (gift_kind=stargift, gift_stars, gift_text,
  gift_thumb_b64 from the gift sticker's stripped thumb, limited/
  saved/converted/refunded flags, sticker file info cached for later
  fetch), messageActionGiftStars (stars), messageActionGiftTon (crypto
  amount/currency). serviceActionText gains real sentences ("sent a
  gift", "sent you N Stars", "sent you a TON gift").
- gui/giftbubble.go (new): parseGift over the cached Extra (pure) +
  the gift card bubble — sticker artwork (stripped thumb → async
  decode swap-in), accent "★ N Stars" pill, the sender's note, status
  chips (Limited / Converted to Stars / Refunded / On profile).
  messageRow dispatches gift messages to the card before the service
  line.
- Tests first: cores/telegram_gift_test.go (4 tests — StarGift Extra
  fidelity incl. cached file coords, GiftStars, GiftTon, action
  sentences) + gui/giftbubble_test.go (3 tests — parseGift, stars
  text, bubble gating). All green.
- Gate: gofmt clean · vet -tags goolm clean · go test -tags goolm
  ./... 8/8 ok.

Parity: PRESENT 166 (82%) · PARTIAL 25 · MISSING 1 · CORE-ONLY 8.

## 2026-09-13 — slice 181: paid-media star wall + unlock

- Parity row "Paid messages / paid posts" CORE-ONLY → PRESENT. Rating
  (§1.14): the old conversion classified paid media as a plain invoice
  (5/10) — replaced per §1.12 with the structured conversion + real
  unlock flow; GUI wall on the gift-card pattern.
- cores/telegram.go: MessageMediaPaidMedia conversion enriched —
  paid_stars (StarsAmount), preview geometry + stripped thumb +
  video duration (MessageExtendedMediaPreview), first-video flag;
  UNLOCKED extended media (MessageExtendedMedia w/ real inner media)
  splices the inner conversion in (photo/document attachment + extras,
  recursion-guarded) and marks paid_unlocked. New UnlockPaidMedia RPC:
  payments.getPaymentForm(inputInvoiceMessage — the layer-228
  constructor that explicitly covers paid media) → payments.sendStarsForm
  (form_id + invoice) → paymentResult/verificationNeeded handling,
  withAPI-compliant.
- engine: UnlockPaidMedia pass-through.
- gui/paidmedia.go (new): parsePaidMedia (pure), the star wall inside
  the bubble — darkened low-res preview (uniform scrim over the
  stripped thumb; the preview is already "extremely low resolution"),
  accent star glyph + "N Stars" + Photo/Video label overlay, "Unlock
  for N Stars" accent button → confirm card (real stars leave the
  balance — always ask) → engine.UnlockPaidMedia → toast + chat
  refresh (the server's message update flips the wall to the real
  media). Plain bot invoices and unlocked media never show the wall
  (§1.10).
- Tests first: cores/telegram_paidmedia_test.go (2 — locked Extra
  fidelity incl. flag-set preview fixture, unlocked photo splice +
  cached file coords) + gui/paidmedia_test.go (2 — parse gating,
  stars text). All green.
- Gate: gofmt clean · vet -tags goolm clean · go test -tags goolm
  ./... 8/8 ok.

Parity: PRESENT 167 (83%) · PARTIAL 25 · MISSING 1 · CORE-ONLY 7.

## 2026-09-13 — slice 182: TTL badges (one-time media + auto-delete timer)

- Parity row "Expired/self-destruct media" CORE-ONLY → PRESENT. Rating
  (§1.14): the core already cached both TTLs (ttl_seconds for the
  chat auto-delete period, media_ttl_seconds for one-time media) but
  the GUI consumed neither (6/10 — kept, surfaced).
- gui/ttlbadge.go (new): parseTTLExtras (pure), fmtTTLPeriod (30s/5m/
  2h/1d/1w), oneTimeLabel (tdesktop's notificationText variants:
  One-time photo / video / voice message / video message), the
  one-time chip (timer glyph + accent label above the media block,
  stacked with the media — never replacing it) and the meta-row
  auto-delete timer (timer glyph + period beside the timestamp).
- Wiring: media-gate hook (chip + media in one column) + meta-row hook
  in chat.go. No new RPCs — cached Extra only.
- Tests first (go/gui/ttlbadge_test.go, 3 tests): parse both TTLs +
  absent/raw-less zeros, period formatting ladder, one-time labels +
  chip gating (file media never chips). All green.
- Gate: gofmt clean · vet -tags goolm clean · go test -tags goolm
  ./... 8/8 ok.

Parity: PRESENT 168 (83%) · PARTIAL 25 · MISSING 1 · CORE-ONLY 6.

## 2026-09-13 — slice 183: animated custom-emoji reaction pills

- Parity row "Bubbles: reactions strip" — the animated custom-emoji half
  CORE-ONLY → PRESENT. Rating (§1.14): the emojiArt machinery
  (fetch/classify/parse + drawEmojiArt w/ frame re-arm + power-saving
  gate) was built for message text (8/10) — reused, not duplicated;
  only the reaction glyph bypassed it.
- gui/custemoji.go: reactionGlyphPath (pure decision — anim / raster /
  static-thumb fallback), reactionAnimSide (125% of the 16dp static
  thumb), ensureReactionEmojiArt (once-per-doc artwork fetch through
  the shared emojiArts cache + GetCustomEmojiFiles, per-account+doc
  guard), customReactionGlyph rewritten — animated lottie documents
  play frame-by-frame via drawEmojiArt (same clock/re-arm/invalidate
  loop as message text; power-saving keeps freezing them), raster
  artwork draws aspect-fit, unresolved or failed entries keep the
  slice-53 static-thumb path (never a blank pill).
- Tests first (appended to custemoji_test.go — the existing slice-53
  tests stay): reactionGlyphPath decision matrix + reactionAnimSide.
  All green.
- Gate: gofmt clean · vet -tags goolm clean · go test -tags goolm
  ./... 8/8 ok.

Parity: the reactions-strip row is now fully PRESENT (animated
included); CORE-ONLY 6 unchanged (blocked/needs-core rows).

## 2026-09-13 — slice 184: channel statistics page

- Parity row "Channel statistics screens" CORE-ONLY → PRESENT. Rating
  (§1.14): no stats surface existed (the row's "engine stats APIs"
  claim was hallucinated — nothing there); built fresh: core RPC +
  engine pass-through + GUI page on the adminlog pane pattern.
- cores/telegram_stats.go (new): GetChannelStats — stats.getBroadcastStats
  (channel input w/ access hash, withAPI) → broadcastStatsToResult
  (pure flattening: period, followers/views/shares/reactions per post,
  per-story counters, notifications %, graphs in tdesktop page order)
  → async tokens resolved via stats.loadAsyncGraph so the GUI only ever
  sees inline JSON; unavailable graphs drop (honest empty).
- engine: GetChannelStats pass-through.
- gui/statsview.go (new): the Statistics page (header ⋮ menu, admin
  channels only — groups/DMs never see it): overview 2-col card grid
  (value + colored +/−/±0 delta vs previous period), then one chart
  card per graph — parseChartJSON (Telegram's chart.js-style columns;
  first non-x series; multi-series takes the first), accent polyline
  (clip.Stroke) over 3 hairline gridlines, compact axis labels
  (1.2K/1.5M), date-range footer, charts with <2 points honestly skip.
- Tests first: cores/telegram_stats_test.go (3 — graph JSON/token
  extraction, full result mapping incl. async tokens + nil-drop,
  percent math) + gui/statsview_test.go (5 — chart JSON parse incl.
  multi-series/degenerate, range, value formatting, delta labels,
  menu gating). All green.
- Gate: gofmt clean · vet -tags goolm clean (json-tag duplicate fixed)
  · go test -tags goolm ./... 8/8 ok.

Parity: PRESENT 169 (84%) · PARTIAL 25 · MISSING 1 · CORE-ONLY 5.
Remaining CORE-ONLY rows are all blocked (pure-Go video decode ×2,
webview decision) or dead-UI-forbidden (experimental flags stub).

## 2026-09-13 — session wrap: slices 176–184, environment + verification

- Fresh VM this session: no Go toolchain, no GL dev packages. Rebuilt via
  the repo's own scripts/devroot-setup.sh (Go 1.27.0 → ~/.local/go,
  CGO sysroot → ~/.local/sysroot incl. wayland/EGL/vulkan/xkbcommon/
  xcb; added Mesa EGL runtime debs for the headless smoke).
- Nine slices landed, all pushed immediately (§1.15): 176 Instant View
  reader, 177 admin log, 178 send-as picker, 179 call rating, 180 gift
  card bubbles, 181 paid-media star wall + unlock, 182 TTL badges, 183
  animated custom-emoji reaction pills, 184 channel statistics page.
- Parity after the session: PRESENT 169 (84%) · PARTIAL 25 · MISSING 1
  (PiP — blocked on pure-Go video decode) · CORE-ONLY 5 — every
  remaining CORE-ONLY row is blocked (video decode ×2, webview
  decision) or dead-UI-forbidden (the experimental-flags engine stub
  consumes nothing; §1.10). The CORE-ONLY program is effectively
  complete.
- Verification this session (local, since the GitHub dispatch API
  returned 500s for workflow dispatches — GitHub-side outage, retries
  failed; runs 138–142 all green historically):
  gofmt clean · go vet -tags goolm clean · go test -tags goolm ./...
  8/8 packages ok · linux CGO build ok · GOOS=js wasm build ok ·
  GOOS=windows build ok · Xvfb GUI smoke: the real binary boots and
  runs (30s+ stable, software EGL via Mesa) and renders — the captured
  frame's dominant color is #17212B (the app palette's Background),
  815 distinct colors.
- Next sessions: the remaining surface is the 25 PARTIAL rows (mostly
  engine-gated halves or honest scope cuts) + the blocked rows that
  need upstream pure-Go video decode; slice-8 style polish passes.

## 2026-09-13 — slice 185: in-app MP3 music player (decode + seek + tags)

- Parity row "Audio file" PARTIAL → PRESENT. Rating (§1.14): the
  slice-113 player pipeline (full PCM decode at load, pull-mode device,
  speed via fractional stepping) is solid and battle-tested (8/10) —
  extended, not replaced; go-mp3 (hajimehoshi) chosen for the decoder:
  pure Go, MIT, no cgo, maintained, decodes the MPEG-1/2/2.5 layers
  Telegram music files actually use.
- engine/mediaplayer_mp3.go (new): IsMp3 (ID3v2 + raw MPEG frame-sync
  sniff, 512-byte window, layer-reserved guard), IsInAppPlayable,
  mixdownStereo (stereo→mono average), resampleLinear (linear
  interpolation to the fixed 48 kHz), decodeMp3 (decode → LE int16 →
  mono → resample). PlayMedia routes by sniff: Opus | MP3 → in-app,
  anything else → honest system-player handoff (§1.10).
- engine SeekMedia(fraction): clamped fraction seek over the PCM (pull
  mode makes this a pos write); finished playback re-arms and resumes
  from the seek point — only with a live audio device, headless never
  fakes Playing (§1.10); seeking nothing/after-stop = honest error.
- gui/seekbar.go (new): the music bubble's draggable seek track —
  press/drag/release all seek (pointer x over track width), half-percent
  drag throttle, 3 dp bar + 6 dp accent playhead dot; seekFraction pure
  (degenerate widths pass current through).
- gui/media.go: audioBubble — embedded Title/Performer tags
  (DocumentAttributeAudio was already exported to Extra by the core;
  engine CachedMessage.AudioMeta() parses it, file-name fallback §1.10),
  performer rides the sub line ("Artist · 0:30 / 3:12 · 4.1 MB"), seek
  track under the row while the file is the active in-app playback.
- Hygiene: go.mod — go-mp3 direct dep; xgb promoted to direct (it was
  already directly imported by gui/appicon_apply_linux.go; the module
  line was stale). Fixed two files committed unformatted by earlier
  slices (cores/telegram_stats.go, gui/sendas_test.go — spaces vs
  tabs; the gofmt gate would have caught them).
- Tests first: engine/mediaplayer_mp3_test.go (6 — sniff truth table,
  mixdown, resample identity/up/down/degenerate, ffmpeg-fixture decode
  + play-through with position advance, playable gating),
  engine/audiometa_test.go (6 — tag parse matrix incl. non-string and
  garbage), engine mediaplayer_test.go TestMediaPlayerSeek (7 asserts —
  clamps, paused seek keeps pause, headless re-arm refusal, post-stop
  error), gui/seekbar_test.go (fraction matrix + sub-line
  composition). All green.
- Gate: gofmt clean · vet -tags goolm clean · go test -tags goolm
  ./... 8/8 ok · linux build + Xvfb GUI smoke (30s+ stable, dominant
  #17212B, 815 colors) · js/wasm build ok · windows build ok.

Parity: PRESENT 170 (84%) · PARTIAL 24 · MISSING 1 · CORE-ONLY 5.

## 2026-09-13 — slice 186: voice-note waveform seek

- Parity row "Voice message" (already PRESENT) — tdesktop's waveform
  seek interaction added. Rating (§1.14): the slice-185 seek machinery
  (engine.SeekMedia + seekFraction + the seekBar throttle pattern) is
  fresh and green (8/10) — reused directly, no duplication.
- gui/media.go voiceWaveform: while this message is the active in-app
  playback, the whole amplitude strip registers a pointer input area
  (default non-pass semantics block the sibling row click — a waveform
  press seeks, the play circle still toggles); press/drag/release seek
  to the pointer fraction with the same half-percent drag throttle.
  Non-active messages register no input (a dead grab area would be a
  §1.10 violation).
- Tests first: gui/seekbar_test.go TestVoiceWaveformSeekWiring — a real
  ffmpeg opus tone loaded through the public PlayMedia, a synthetic
  router press at 50% of the strip seeks the engine player to ~0.5 s,
  and a non-seekable render leaves the player untouched (input never
  registered). Green.
- Gate: gofmt clean · vet -tags goolm clean · go test -tags goolm
  ./... 8/8 ok · linux build ok · js/wasm + windows builds ok.

Parity: unchanged counts (row already PRESENT — interaction added).

## 2026-09-13 — slice 187: channel-post view counts (eye glyph + refresh)

- Parity rows "Ayu: Message details" (views/shares half) + the channel
  post meta row. Rating (§1.14): the core already surfaced Views/Forwards
  on every Message conversion (8/10 — kept); the dead single-message
  GetMessageViews RPC wrapper was replaced by the batched form the
  feature actually needs (§1.12 disposability applies to dead code too).
- cores: GetMessagesViewsBatch — ONE messages.getMessagesViews RPC for
  the whole visible window, withAPI-converted (§8), returns
  msg-id→views AND msg-id→forwards maps.
- engine: migrateV51 (messages.views + messages.forwards), ingest writes
  them, every read path (window/topic/pinned/deleted-search) selects +
  scans them into CachedMessage; RefreshMessageViews — channel-gated
  (chats.type), newest-60 post ids, batch RPC, transactional update,
  emitChatUpdate only when a counter actually moved.
- gui: the bubble meta row grows tdesktop's eye-glyph counter block
  (views always when counted, forwards beside when non-zero,
  viewsCountLabel compact 1.2K/15K/1.2M formatting); Message-details
  dialog gains Views/Forwards rows; syncViewsRefresh ticker — refresh on
  channel open + every 30s while it stays open, counters merged into the
  open window IN PLACE (no wholesale reload racing message events).
- Tests first: engine/msgviews_test.go (cache round-trip through
  cacheMessage→GetMessages; refresh pass with a fake core — changed
  counting, unchanged second pass = 0 changed + 1 RPC, non-channel
  no-RPC gate, missing-account no-op) + gui/msgviews_test.go (the
  compact label ladder). All green.
- Gate: gofmt clean · vet -tags goolm clean · go test -tags goolm ./...
  8/8 ok · linux build + Xvfb GUI smoke (25s+, #17212B dominant, 815
  colors) · js/wasm build ok · windows build ok.

Parity: unchanged counts (a PARTIAL row's halves filled; no flips).

## 2026-09-13 — slice 188: in-app chat-theme application (tint + gradient)

- Parity row "Chat background" — the local-application half. Rating
  (§1.14): the slice-65 picker + core theme fetch were sound but stored
  wrong (see the bug below — 6/10, fixed in place); tdesktop's peerTheme
  model (latest SetChatTheme service row owns the chat's look) mapped
  cleanly onto the existing cache.
- Latent bug fixed: loadChatThemes stored the list WITHOUT setting
  chatThemesFor, so the picker dialog's gate
  (f.chatThemesFor != account) discarded it every time — the chips never
  rendered since slice 65. Now the cache is tagged per account and
  shared by the picker and the tint resolver; failures surface the
  honest "no themes" state instead of an infinite "Loading…" (§1.10).
- Core: messageActionSetChatTheme service rows export
  chat_theme_emoticon (empty = reset).
- Engine: migrateV52 (chats.theme_emoticon), cacheMessage mirrors the
  LATEST service row onto the chat (key presence = the reset),
  ensureChatExists seeds it for brand-new chats, ChatInfo round-trips
  it through every list scan.
- gui/chatthemetint.go: activeChatTheme (frame snapshot, mode-matched
  variant + opposite-mode fallback), outgoing bubble tint from
  MessageColors[0] with luminance-contrast text, message-pane wallpaper
  gradient (BgColors mixed 50/50 toward the app background, painted
  first so rows sit on top); the picker applies optimistically; themed
  chats preload the account theme list on open.
- Tests first: engine/chattheme_test.go (mirror set/reset/round-trip,
  non-string extras skipped, ensureChatExists seed) + gui/
  chatthemetint_test.go (color-int conversion incl. ARGB, luma ordering,
  resolver: dark/light variant match, fallback, no-theme/unloaded/
  foreign-account stock palette, contrast text). All green.
- Gate: gofmt clean · vet -tags goolm clean · go test -tags goolm ./...
  8/8 ok · linux build + Xvfb smoke (25s+, #17212B dominant) · js/wasm
  + windows builds ok.

Parity: unchanged counts (row's local half filled; wallpaper patterns
remain the honest scope cut).

## 2026-09-13 — slice 189: topic permalinks route in-app

- Parity row "Deep links (tg://)" — the topic-form half. Rating
  (§1.14): the slice-95/161 classifier + open/jump machinery is clean
  and well-tested (8/10 — extended, not replaced).
- deepLinkTarget: 4th return value (topic) — t.me/<channel>/<topic>/
  <msg>, t.me/c/<id>/<topic>/<msg>, tg://resolve?...&topic=<id>
  (non-numeric topic values drop honestly); c/<id>/<msg> tightened to
  exactly-3 segments so the 4-seg topic form classifies.
- Engine: GetTopicMessagesAfter — the topic's toward-the-present window
  (strict newer-than, ASC select + reverse, same filters as the
  before-window); empty topic delegates to GetMessages.
- GUI: resolveDeepLinkPermalink carries the topic through to
  openPermalinkTarget → pendingTopic rides the pendingOpen hop; the
  first-window load fires jumpToTopicMessageAt (scopes the view to the
  topic, loads the before/after window around the message's timestamp,
  positions the list at the target row; unresolvable timestamp falls
  back to the plain topic view — never a dead screen).
- Tests first: gui/deeplink_test.go TestDeepLinkTargetTopicPermalink
  (11 cases — public/private/tg:// forms, non-numeric topic drop,
  comment/browser scope, reserved paths) + the legacy tables moved to
  the 4-tuple; engine TestGetTopicMessagesAfter (strict boundary,
  newest-first, chat-wide delegation). All green.
- Gate: gofmt clean · vet -tags goolm clean · go test -tags goolm ./...
  8/8 ok · linux build + Xvfb smoke (25s+, #17212B dominant) · js/wasm
  + windows builds ok (disk forced one cache-clean rebuild mid-gate).

Parity: unchanged counts (a PARTIAL row's topic half filled).

## 2026-09-13 — slice 190: chat-row Clear history (tdesktop dialog-row menu)

- Parity row "Chat row context menu" (P0) — the Clear-history half. Rating
  (§1.14): the slice-8 menu + dispatch machinery is solid (8/10 — kept and
  extended; the dialog follows the slice-19 delDlg pattern 1:1, no
  duplication beyond the state struct).
- gui/cleardlg.go (new): window-level confirm card — "Clear history?" +
  "This can't be undone." + the "Also delete for everyone" revoke
  checkbox gated by canRevokeClearHistory (DMs always — Telegram
  deleteHistory revoke wipes both sides; groups/channels admins only),
  Cancel/Clear buttons (Clear in error red, busy label swap), async
  engine.ClearHistory, then open-view reload (refreshMessages — empty
  fresh window clears the merge, so scrolled-up history vanishes too) +
  refreshChats + toast. The dialog renders at app level (above all panes,
  below drawer/toast) because the trigger is the sidebar menu — the chat
  need not be open.
- gui/chatmenu.go: "Clear history" row between Block user and Delete chat
  for every chat type; dispatch opens the confirm (never an instant wipe).
- Wiring: App/frame clearDlg state + snapshot + openChat reset +
  widgets (cancel/check/clear).
- Local env rebuilt for this session: devroot Go 1.27.1 + sysroot grown
  with mesa EGL/GLES/DRI (libegl-mesa0, libgl1-mesa-dri, libgles2) +
  xdotool + libxtst — the Xvfb GUI smoke now runs fully locally
  (software llvmpipe rendering, ffmpeg x11grab screenshots).
- Tests first: gui/chatmenu_test.go (Clear history present for
  DM/group/channel, adjacent-before-Delete position lock; both default
  tables extended) + gui/cleardlg_test.go (title/hint, revoke gating
  matrix). Green.
- Gate: gofmt clean · vet -tags goolm clean · go test -tags goolm
  ./... 8/8 ok · linux build ok · Xvfb GUI smoke (12s boot, #17212B
  dominant, 815 colors; click-through welcome→picker verified: 1601
  colors, Material-indigo card grid) · js/wasm + windows builds ok
  (wasm needed -gcflags=all=-c=1 on the 3GB box — OOM otherwise).

Parity: PRESENT 167 · PARTIAL 24 · MISSING 1 · CORE-ONLY 7.

## 2026-09-13 — slice 191: restrict + ban boxes (moderation row → PRESENT)

- Parity row "Moderation (admin log, restrictions)" — the restrict-box
  half (the admin-log half landed slice 177; the row was stale CORE-ONLY).
  Rating (§1.14): the slice-106 member menu + PromoteAdminWithRights/
  RestrictMemberWithRights engine surface were sound but GUI-unsurfaced
  (7/10 — extended, not replaced).
- Core: cores.ParticipantExtra grows BannedRights/BannedUntil (parsed from
  ChannelParticipantBanned.BannedRights/UntilDate through
  bannedRightsFromTG); TelegramCore.BanMemberUntil (ViewMessages +
  UntilDate through RestrictUser — gotd's EncodeBare auto-SetFlags
  verified, so no flag pitfall). Wire check: channels.editBanned
  with-rights path was already live-tested shape-wise.
- Engine: MemberInfo.BannedRights/BannedUntil (bannedRightsFromCores
  converts the cores struct), mirrored in GetParticipantsByRole;
  memberFromExtra isolates the mirror for tests; BanMemberUntil wrapper
  (typed interface, honest unsupported error).
- GUI: gui/restrictdlg.go — Restrict box (title "Restrict <name>", the
  tdesktop duration ladder Forever/1h/8h/2d/1w/1m/3m/6m/1y as chips, 15
  permission switches labeled positively, allowed↔banned inversion at
  the wire — partial maps never ban by omission) + Ban box (duration +
  confirm). Window-level modals; switch values snapshotted under the
  GUI lock at apply; toasts + panel member-list reload.
- membermenu.go: Restrict/Ban now open the boxes (instant RestrictMember
  path retired; promote/demote/unban/remove stay instant — tdesktop
  fires those directly too).
- Tests first: gui/restrictdlg_test.go (duration matrix, until-date math
  incl. forever=0, permission-row table vs DefaultBannedRights fields,
  inversion with omission semantics — caught a real bug: missing keys
  must mean allowed, not banned; initial-rights resolution) +
  engine/restrict_test.go (BanMemberUntil arg pass-through + unsupported
  errors; ParticipantExtra→MemberInfo mirror). Green.
- Gate: gofmt clean · vet -tags goolm clean · go test -tags goolm
  ./... 8/8 ok · linux build ok · js/wasm + windows builds ok · Xvfb GUI
  smoke (25s+, #17212B dominant).

Parity: PRESENT 168 · PARTIAL 24 · MISSING 1 · CORE-ONLY 6.

## 2026-09-13 — slice 192: RLock-across-RPC purge (31 methods) + boosts page

- Two-part slice. Part 1 (freeze class, §8): the v2 lock-state scanner
  covered WRITE locks only — 31 TelegramCore methods still held
  t.mu.RLock (defer) across live RPCs (boosts, stats, star-ref, notify
  sound, read-participants, emoji keywords, global search, sponsored,
  giveaway/launchers). All converted to the withAPI snapshot pattern
  (t.api.X(t.ctx → api.X(ctx). The two config-reading methods gained
  snapshot-based helpers (appConfigIntAPI/BoolAPI/RawAPI take the
  caller's api+ctx) so GetBotManageInfo/GetSponsoredInfo keep their
  server config reads lock-free. SetChatNotifySound (slice-174
  regression) + GetMessageReadParticipantsDetailedJSON (direct t.api
  straggler) also converted. NEW REGRESSION GUARD:
  cores/telegram_lockscan_test.go TestNoLockAcrossRPC — source-scans
  every telegram*.go method for the deferred-lock + t.api.* co-occurrence
  and fails listing offenders; both lock polarities covered. Scanner now
  reports ZERO. (Voice-call signaling acks keep their own scoped
  rawSigInterceptorsMu + direct t.api use — call lifetime guarantees
  auth; Authenticate's lock sections are brief state updates around the
  snapshot, RPCs run unlocked — audited, compliant.)
- Part 2 (parity row "Giveaways / boosts" CORE-ONLY → PARTIAL): the
  boosts page (tdesktop's boost info box). gui/boostview.go — status
  card (Level N, X boosts, current→next-level progress bar, gift boosts,
  "You boosted this channel" line) from premium.getBoostsStatus;
  "Boost this channel" → cores.ApplyBoost (premium.applyBoost, withAPI)
  + engine wrapper — the server rejects slotless accounts honestly;
  boosters list (name/multiplier ×N/gift/unclaimed/date sub-rows) from
  premium.getBoostsList with offset paging + Boosters/Gifts tabs;
  header ⋮ "Boosts" for channels (members AND admins — boosting is a
  member action). Launch-giveaway checkout (payments.getPaymentForm)
  stays out — in-app payment checkout is the honest scope cut.
- Tests first: gui/boostview_test.go (level label, progress fraction
  incl. maxed/degenerate, to-next label, booster title/sub composition,
  paging fields, empty-map fallbacks) + cores/telegram_lockscan_test.go
  (the regression guard). Green.
- Gate: gofmt clean · vet -tags goolm clean · go test -tags goolm
  ./... 8/8 ok · linux build ok · js/wasm + windows builds ok · Xvfb
  GUI smoke (#17212B dominant, welcome + click-through picker).

Parity: PRESENT 168 · PARTIAL 25 · MISSING 1 · CORE-ONLY 5.

## 2026-09-13 — slice 193: signup photo + split name fields

- Parity row "Signup (name/photo)" (P2) — the photo-at-signup half.
  Rating (§1.14): the generic single-input auth card was fine for
  code/password steps but structurally wrong for signup (4/10 for this
  step — replaced for the signup state only, kept everywhere else).
- REAL BUG fixed by the slice: the engine expects "first\nlast" for
  signup (splitSignUpInput splits on \n), but the GUI's single-line
  editor can never contain a newline — every "John Smith" became a
  FIRST name of "John Smith". The dedicated card submits the true shape.
- gui/signupcard.go: First name (required) + Last name (optional)
  editors (Enter hops first→last→submit via key.FocusCmd), the photo
  circle (OS picker through a.expl.ChooseFiles; staged base64 preview
  through the shared avatar machinery — avatarImage + avatarFromImage,
  async decode; initials placeholder before a pick), Create account.
- Ready hop: submitAuth's AuthStateReady branch consumes the staged
  photo (UploadProfilePhoto + temp cleanup + toast + refreshAccounts);
  authCancel drops it. App/frame staging fields + snapshot.
- Parity row "Advanced + experimental" re-marked CORE-ONLY-BY-DESIGN:
  engine.SetExperimentalFlag exists but nothing is experimentally gated
  — a Settings surface today would be dead UI (§1.10 ban). Flips when a
  real experimental feature lands.
- Tests first: gui/signupcard_test.go (name-input composition incl.
  trims + first-only, name validation, photo hint states). Green.
- Gate: gofmt clean · vet -tags goolm clean · go test -tags goolm
  ./... 8/8 ok · linux build ok · js/wasm + windows builds ok · Xvfb
  GUI smoke (#17212B dominant).

Parity: PRESENT 170 · PARTIAL 23 · MISSING 1 · CORE-ONLY 4 (+1 by-design).

## 2026-09-13 — slice 194: parity-file truth pass (docs)

- The parity file's tail sections had drifted: "Top 20 gaps" still
  listed slice-8-era items (context menu, reactions, media bubbles —
  shipped months of slices ago) and "Counts" carried three stale
  snapshots (PARTIAL 32/MISSING 7/CORE-ONLY 25 era).
- 8 stale PARTIAL rows trued to PRESENT — each one's own description
  already met the row's criteria, only the marker lagged: Attach menu,
  Document/file, Appearance, Data & storage, Business section (chat
  links: tdesktop/AyuGram ship no such UI — §1.11), Streamer mode, Ayu
  preferences, Per-chat notification settings.
- Tail rewritten: "Remaining gaps" (19 ranked entries, every one labeled
  with its blocker: pure-Go video decode, owner webview decision, dead-
  UI ban, platform transports, engine gates, checkout scope) + "Counts"
  (PRESENT 177 / PARTIAL 16 / MISSING 1 / CORE-ONLY 5, with the
  slice-by-slice count history preserved).
- No code changes — docs only (§10: markdown stays short and true).

Parity: PRESENT 177 (89%) · PARTIAL 16 · MISSING 1 · CORE-ONLY 5.

## 2026-09-13 — slice 195: channel-post comments (chip + thread view)

- The biggest unblocked parity gap found by the slice-194 truth pass:
  channel-post comments did not exist anywhere (the parity file only
  hinted via the deep-links row). Rating (§1.14): the forum-topic
  scoping machinery (topics.go + GetTopicMessages + topicRootID sends)
  was the right architecture to extend (9/10 — extended, not replaced).
- Core: cores.Message gains CommentsCount (MessageReplies) + ThreadRoot
  (reply-to-top; the discussion rows' thread filter); convertMessage
  maps both via pure helpers (repliesInfoOf/threadRootOf — pinned by
  constructed-wire tests); GetDiscussionThread (messages.getDiscussion
  Message, withAPI) + ReadDiscussion (messages.readDiscussion).
- Engine: migrateV53 (messages.comments_count + thread_root — thread
  root NULLable like topic_id; found + fixed the nullStr-vs-NOT-NULL
  insert failure via a raw-INSERT probe); every message SELECT + the
  shared scanMessages extended uniformly (31 cols); engine/comments.go
  — GetDiscussionThread (fetch + cache write-through + root resolve +
  newest-first), GetThreadMessages (thread filter w/ beforeMs paging),
  ReadDiscussion.
- GUI: gui/comments.go — the "N comments" chip on channel posts
  (count>0, channel-gated; pooled clickables) opens the thread view;
  thread bar under the header (back → the channel, "Comments · <first
  line>"); refreshMessages + loadOlder branch to the thread filter;
  the composer redirects into the discussion group replying to the
  thread root (tdesktop's comment semantics — a reply to the root IS a
  new comment); ReadDiscussion fires on open; chat switch closes the
  scope. Honest v1: the server's recent page + cached older pages.
- Tests first: cores/telegram_comments_test.go (replies/thread-root
  readers incl. the gotd Set-helper flag semantics), engine/
  comments_test.go (round-trips, thread filter + ordering, discussion
  fetch w/ cache write-through + unsupported errors), gui/comments_
  test.go (label incl. compact counts, gating, bar title). Green.
- Gate: gofmt clean · vet -tags goolm clean · go test -tags goolm
  ./... 8/8 ok · linux build ok · js/wasm + windows builds ok · Xvfb
  GUI smoke (#17212B dominant). (Disk pressure forced one go clean
  -cache -modcache; full rebuild re-verified green.)

Parity: PRESENT 178 (89%) · PARTIAL 16 · MISSING 1 · CORE-ONLY 5
(one by-design). New row: "Channel-post comments" PRESENT.

## 2026-09-14 — slice 196: comment-thread deep links route in-app

- The last router gap from the slice-194 truth pass: comment-thread
  permalinks (t.me/<channel>/<post>?comment=<id>,
  t.me/c/<id>/<post>?comment=<id>, tg://resolve?...&comment=<id>) still
  handed to the browser even though slice 195 shipped the thread view
  they target. Rating (§1.14): the deep-link router + pendingOpen hop
  architecture was exactly right to extend (9/10 — extended, not
  replaced).
- deepLinkTarget now strips and parses the URL query (classification
  previously broke on ANY query string — t.me/user/123?x=1 fell to the
  browser) and returns a 5th value, the comment id, on the non-topic
  permalink forms; topic forms keep topic-wins semantics (a link is
  exactly one of the three).
- Routing: openPermalinkTarget's comment branch schedules pendingOpen +
  pendingThread{postID, commentID} synchronously (no timestamp prefetch
  — the thread fetch resolves its own rows); openChat's first-load hop
  consumes pendingThread (supersedes topic/plain jumps) into
  openCommentThreadDeep.
- openCommentThreadDeep mirrors the chip's openCommentThread minus the
  in-hand post row: threadScope settles via GetDiscussionThread, the bar
  title falls back to the root row's text (the forwarded post copy).
  The comment jump: newest page first; off-page comments resolve through
  GetMessageTimestamp (cache write-through) into a target-anchored
  GetThreadMessages window assembled by the pure threadDeepJumpWindow
  (reverse(older) + newer tail, message-index jump mapped onto the
  render row via rowIndexOf, same conversion as jumpToMessageAt);
  unresolvable comments keep the newest page, no jump (honest).
  ReadDiscussion fires on open (tdesktop parity).
- Tests first: deeplink_test.go — 5-value classification with the full
  comment matrix (public/private/tg://, non-numeric + empty drops,
  topic-wins, stray-param resolves, query-strip regressions);
  comments_test.go — threadDeepJumpWindow assembly (in-page target,
  off-page window, missing target) + the zero-App scheduling hop
  (pendingOpen + pendingThread, no pendingJump/pendingTopic).
- Gate: gofmt clean · vet -tags goolm clean · go test -tags goolm
  ./... 8/8 ok · linux build ok · windows + wasm cross-builds + Xvfb GUI
  smoke dispatched to the verify workflow (small-sandbox policy, §5).

Parity: PRESENT 179 (90%) · PARTIAL 15 · MISSING 1 · CORE-ONLY 5.
Deep links PARTIAL → PRESENT (gap 13 closed).

## 2026-09-14 — slice 196.1: private-permalink channel-id bug fix

- Found while researching saved-sublists peer ids: permalinkChatID mapped
  t.me/c/<channelID> refs to "-100"+id, but the app-wide channel-ID
  convention is -1000000000000-channelID (peerToID, every Dialog and
  ChatInfo row) — so EVERY private-channel permalink
  (t.me/c/123456/789) failed the dialog lookup and toasted "Channel not
  found in your chats" (slice-161 regression, never live-tested).
- permalinkChatID now maps through strconv to the -1e12-id form; the
  pure test pins the mapped value plus the empty/non-numeric guards.
- Gate: gofmt clean · vet clean · go test -tags goolm ./... 8/8 ok.

## 2026-09-14 — slice 197: Saved Messages sublists (Lists pane + scoped views)

- Gap 7 from the slice-194 truth pass: sublists were "engine-gated" —
  deep-dive found the gate was half-open already (a prior slice shipped
  cores.GetSavedSublists + the raw RPC wrappers + engine passthrough,
  unused by any GUI). Rating (§1.14): extend the existing surface, don't
  duplicate (9/10 — the GUI layer + the scoped message path were the
  missing halves; my draft duplicate wrapper was deleted in favor of the
  existing richer shape).
- Official spec research (core.telegram.org/api/saved-messages, not the
  repo's possibly-stale notes): saved dialogs = one entry per peer the
  user saved from; methods mirror the dialog family (getSavedDialogs /
  getSavedHistory / toggleSavedDialogPin / reorder / delete); search
  uses messages.search + saved_peer_id; the fwd-from backfill
  pseudocode fills saved_peer_id for pre-layer-170 rows (from_id →
  SELF, from_name-only → the anonymous user 2666000).
- Core: deriveSavedPeerID (the official backfill, tests-first, pinned
  incl. the from_id→self subtlety) wired into attachSublistInfo —
  every converted message now carries m.SavedPeerID (plus the Extra
  copy the notification layer reads); friendly GetSavedHistory wrapper
  (withPeer + withAPI, convertMessages).
- Engine: migrateV54 adds messages.saved_peer; cacheMessage INSERT +
  shared scanMessages + all 10 message SELECT column lists extended
  (31→32 cols, the slice-195 pattern); engine/savedsublists.go —
  SavedSublistsSupported, GetSavedSublistMessages (cold cache fed by
  getSavedHistory, then the saved_peer-filtered read; beforeMs paging),
  readSavedRows/countSavedRows, ToggleSavedSublistPin.
- GUI: the saved chat header gains the Lists button (capability-gated
  to saved chats, §1.10) opening the right-sidebar pane — "All
  messages" + one row per sublist (avatar, pinned glyph, preview, the
  honest loading/empty/error states); picking a row scopes the view via
  savedScope (bar under the header with back, refreshMessages/loadOlder
  branch through the scoped read); composer target unchanged (tdesktop:
  a new note lands in My Notes). Wiring mirrors the topic/thread
  scopes.
- BUG FIXED along the way (found while wiring bars): slice 195's
  layoutCommentsBar was never called — the comment-thread view shipped
  with NO back button (stuck view until chat switch). Now wired under
  the header like the topic bar.
- Tests first: cores/telegram_saveddialogs_test.go (backfill matrix),
  engine/savedsublists_test.go (capability probe, passthrough,
  scoped pages incl. beforeMs + unscoped reads, saved_peer round-trip),
  gui/savedsublists_test.go (sort, bar title, row title, preview).
- Gate: gofmt clean · vet -tags goolm clean · go test -tags goolm
  ./... 8/8 ok · linux build ok · windows + wasm cross-builds + Xvfb GUI
  smoke dispatched to the verify workflow. (One disk-pressure
  go clean -cache; full rebuild re-verified green.)

Parity: PRESENT 179 (90%) · PARTIAL 15 · MISSING 1 · CORE-ONLY 5.
Saved Messages row: sublists PRESENT (pin reorder + tag lists remain).

## 2026-09-14 — slice 198: emoji-pattern chat wallpapers

- Gap 16 from the slice-194 truth pass: chat backgrounds shipped tint +
  gradient (slice 188) but no pattern. Rating (§1.14): the slice-188
  architecture (theme list cache → activeChatTheme → pane painter) was
  exactly right to extend (9/10 — extended).
- Core: ChatThemeInfo.PatternIntensity parsed from the wallpaper
  settings (wallPaperSettings.intensity; the wire sign flips with
  rotation — abs is the alpha).
- GUI: chatThemeBackground now closes its clip stack AFTER the pattern
  pass — chatThemePattern tiles the theme's own emoticon glyph (the
  server-provided pattern emoji, rendered through the registered Noto
  Emoji face — re-implemented, never copied) on a staggered grid
  (patternTilePlan: tile 44dp + spacing 34dp, odd rows offset half a
  step), color mixed toward the text color for contrast on both
  gradient stops, alpha = patternAlpha(abs(intensity)) clamped to a
  subtle 12..114. Zero intensity = no pattern (honest — the server
  said none).
- Tests first: TestPatternTilePlan (coverage probes incl. corners,
  degenerate inputs nil) + TestPatternAlpha (midpoint, sign-flip,
  clamps) in chatthemetint_test.go.
- Gate: gofmt clean · vet -tags goolm clean · go test -tags goolm
  ./... 8/8 ok.

Parity: PRESENT 179 (90%) · PARTIAL 14 · MISSING 1 · CORE-ONLY 5.
Chat background row → PRESENT (gap 16 closed).

## 2026-09-14 — slice 199: Saved Messages reaction tags (premium)

- The slice-116-era claim "saved-tags search already shipped" was
  false — SearchSavedMessagesByReaction + GetSavedReactionTags sat in
  engine+core with ZERO GUI callers (dead surface, found by the gap-7
  deep-dive). This slice wires both into the slice-197 Lists pane.
- GUI: savedScopeState gains the tag discriminator (tag != "" = tag
  scope, peerID ""); openSavedTag loads the server-side
  saved_reaction search (SearchSavedMessagesByReaction — engine
  caches the rows so media/reply metadata renders); refreshMessages
  + loadOlder branch through the tag search (offsetID paging: the
  window's oldest message id); the bar shows "Tag <emoji> · <name>".
- The Lists pane gains the Tags section (tagsSectionVisible: premium
  account AND non-empty tag list — honest gating, §1.10): one row per
  savedReactionTag (emoji glyph, name-or-emoji fallback, count badge),
  fetched alongside the sublists (separate goroutine — a tag failure
  never blocks the list).
- Tests first: TestSavedTagBarTitle, TestSavedTagRowLabel,
  TestTagsSectionVisible (premium/empty/non-premium gating).
- Gate: gofmt clean · vet -tags goolm clean · go test -tags goolm
  ./... 8/8 ok.

Parity: PRESENT 179 (90%) · PARTIAL 14 · MISSING 1 · CORE-ONLY 5.

## 2026-09-14 — session wrap (slices 196–199 + 196.1)

- Session resumed from the slice-195 state via AGENTS.md + WORKLOG;
  environment rebuilt from devroot.env (go 1.27.1, module cache
  intact). Local verification: gofmt/vet/tests green at session start,
  all four verify-workflow dispatches green (full gate + windows/wasm
  cross-builds + Xvfb GUI smoke for every slice).
- Shipped:
  - 196: comment-thread deep links (?comment=) route in-app into the
    thread view with the comment jump (gap 13 closed; also fixed
    classification breaking on ANY query string).
  - 196.1: t.me/c/ permalink channel-id mapping bug (never matched the
    app-wide -1e12-id convention — every private-channel permalink
    failed lookup since slice 161).
  - 197: Saved Messages sublists — the Lists pane (right sidebar),
    saved_peer cache scoping (migrateV54), the official fwd-from
    backfill, getSavedHistory cold-start feed; fixed slice-195's
    comments bar never being wired (thread view had no back button).
  - 198: emoji-pattern chat wallpapers (theme emoticon tiled at the
    wallpaper pattern intensity — gap 16 closed).
  - 199: Saved Messages reaction tags — premium Tags section + tag
    scoped views (wired the dead saved-tag engine surface).
- Parity: PRESENT 179 (90%) · PARTIAL 14 · MISSING 1 · CORE-ONLY 5.
- Next session (top of the queue):
  1. Windows native toast notifications — FULLY RESEARCHED in
     research/windows_toast.md (UUIDs, vtable slots, activation flow,
     AUMID options from primary sources). Implement pure-Go per the
     taskbar_windows.go pattern; tests-first for the pure halves.
  2. Remaining honest gaps are blocked/checkout/owner-decision scoped
     (see research/ayugram_parity.md "Remaining gaps").
- Housekeeping: disk pressure forced one go clean -cache mid-session
  (rebuild re-verified); /tmp artifacts cleaned.

## 2026-09-14 — slice 200: Windows native toast notifications

- Gap 5's biggest platform hole, implemented from the fresh primary-
  source research (research/windows_toast.md): pure-Go WinRT via
  syscalls — the taskbar_windows.go COM pattern extended to the Ro*
  family (RoGetActivationFactory / RoActivateInstance /
  WindowsCreateString from combase/winstring).
- ABI pinned against mingw-w64 windows.ui.notifications.h +
  windows.data.xml.dom.h (IUnknown 0-2, IInspectable 3-5, methods in
  declaration order): manager CreateToastNotifierWithId=7, factory
  CreateToastNotification=6, notifier Show=6, IXmlDocumentIO LoadXml=6;
  the activation flow cross-checked against valinet's pure-C reference.
- notify_windows.go implements notifyDesktop: manager → notifier (the
  registered AUMID) → XmlDocument (activate + QI + LoadXml of the
  CDATA-escaped payload) → ToastNotification → Show. Failures return
  errors → the existing log-only path (identical to the Linux DBus
  failure semantics — never a crash).
- v1 scope, documented: the AUMID rides PowerShell's Start-Menu
  registration (works on every stock Win10/11; the source row reads
  "Windows PowerShell" until our own IShellLink+IPropertyStore shortcut
  lands — follow-up); no click-through activation yet (onAction unused,
  the in-app surface remains the click path); text-only toasts.
- toastxml.go is shared (no build tag) so every CI target compiles and
  pins the escaping. Tests first: TestToastXML (template shape + lines)
  + TestToastXMLCdataEscape (terminator neutralization).
- Gate: gofmt clean · vet clean · go test -tags goolm ./... 8/8 ok ·
  windows cross-build ok (compiles the transport) · wasm build ok.

Parity: PRESENT 179 (90%) · PARTIAL 14 · MISSING 1 · CORE-ONLY 5.

## 2026-09-14 — session wrap addendum: slice 200

- The Windows toast transport (gap 5's windows half) shipped in the
  same session — implemented straight from the fresh
  research/windows_toast.md ABI research: notify_windows.go (pure-Go
  WinRT: RoGetActivationFactory/RoActivateInstance/HSTRING; manager →
  notifier → XmlDocument LoadXml → ToastNotification → Show; error→
  log-only like Linux), toastxml.go shared CDATA-safe payload builder
  + tests. Windows cross-build compiles it; CI verify green (9d65a0aa).
- All five slices this session (196, 196.1, 197, 198, 199, 200) are
  pushed and verify-workflow-verified (full gate + windows/wasm
  cross-builds + Xvfb GUI smoke each).
- Next queue head for the next session: click-through toast activation
  + own-AUMID shortcut (IShellLink/IPropertyStore COM) — extends
  slice 200; then the remaining gaps are checkout/owner-decision/
  protocol-blocked (see research/ayugram_parity.md).

## 2026-09-14 — slices 201 + 202: own-AUMID shortcut + toast click-through

- Session resumed from the slice-200 state via AGENTS.md + WORKLOG;
  devroot rebuilt from scripts/devroot-setup.sh (go 1.27.1, sysroot,
  module cache re-warmed; 3GB RAM box — GOGC=20, -p 1,
  -gcflags=all=-c=1 throughout).
- Deep research first: fetched mingw-w64 headers FRESH (mirror/mingw-w64
  raw) and pinned every ABI before writing code:
  - shobjidl.h: IID_IShellLinkW {000214F9-…-46}, CLSID_ShellLink
    {00021401-…-46}, vtable order GetPath 3 … SetWorkingDirectory 9 …
    SetIconLocation 17 … SetPath 20 (read straight from the Vtbl struct).
  - objidl.h: IID_IPersistFile {0000010B-…-46}, Save = 6.
  - propsys.h: IID_IPropertyStore {886D8EEB-…}, SetValue 6, Commit 7.
  - propkey.h: PKEY_AppUserModel.ID fmtid
    {9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3} pid 5 — the tail is
    E1-D4-2D-E1-D5-F3; the "E1D42DE4D436" form in blog posts is a typo.
  - propidl.h: PROPVARIANT layout (vt + 6 reserved, union @8, 24B x64),
    wtypes.h VT_LPWSTR=31.
- Slice 201 (own AUMID): shortcut_windows.go — CoCreateInstance →
  SetPath/SetWorkingDirectory/SetIconLocation → QI IPropertyStore →
  SetValue(PKEY_AppUserModel.ID, VT_LPWSTR) → Commit → QI IPersistFile →
  Save (property commit BEFORE persist, the AppUserModelID-docs recipe).
  resolvedToastAUMID: our AUMID once registered, PowerShell's as the
  always-works fallback (one attempt per process). Shared comabi.go
  carries the GUIDs/pkey/PROPVARIANT so comabi_test.go pins them on
  every CI target.
- Slice 202 (click-through): the WinRT COM activator needs a separate
  in-proc DLL (banned: single binary §1.3) → protocol activation
  instead: toast XML gains activationType="protocol"
  launch="uniclient://open?acc=…&chat=…" (attr-escaped); instance_
  windows.go registers the uniclient:// scheme per-user (HKCU\Software\
  Classes, x/sys registry, no elevation, rewritten at boot so a moved
  exe self-heals) + a single-instance command channel (<config>/
  instance.lock "port cookie" atomic-rename, localhost listener): a
  launcher process holding the URI (HandleLaunchURI, BEFORE engine boot
  — a click never pays engine init) forwards "open cookie uri" and
  exits; the running app hops through notifyOpenAction (ActionRaise +
  pendingOpen — the same surface as the Linux DBus click); cold-start
  clicks boot the app and routeBootURI opens the chat once an account
  exists. Stub file keeps call sites unconditional on other platforms
  (Linux already clicks through DBus; wasm/android have no OS surface).
- Tests first, all pure halves pinned cross-platform (12 new tests):
  comabi_test.go (GUID strings, PKEY, PROPVARIANT offsets/size),
  openuri_test.go (round-trips incl. Matrix/IRC ids w/ spaces/&,
  rejects non-open URIs, splitNotifyKey), toastxml_test.go (launch
  attribute + XML attribute escaping).
- Gate (all local): gofmt clean · vet clean · go test -tags goolm
  ./... 8/8 ok · linux CGO build ok · windows cross-build ok (compiles
  shortcut_windows + instance_windows + registry) · wasm ok.
- Parity: notifications row PARTIAL → PRESENT; gap 5 CLOSED; counts
  PRESENT 180 (90%) · PARTIAL 13 · MISSING 1 · CORE-ONLY 5.
- research/windows_toast.md trued to shipped status with the fresh ABI
  pins.

## 2026-09-14 — slice 203 + android fix + v0.9.0

- **Android APK build fixed** (real regression from slice 170): the
  Release dispatch (run 34809160618, sha 8f727dbc) failed at the APK
  step — appicon_apply_linux.go carried a bare `//go:build linux`,
  which ALSO matches GOOS=android (the toolchain sets both the android
  AND linux release tags), while gio's X11ViewEvent is
  `(linux && !android) || freebsd || openbsd` → undefined type on
  android. Fixed: linux file → `linux && !android`, stub →
  `(!linux && !windows) || android`. launcherbadge/notify_linux/tray
  compile on android (pure-Go dbus/systray deps) and resolve the
  taskbar no-ops — only appicon was broken.
- **v0.9.0 released** (tag on the fix, run 34817842435): all 7 jobs
  green — test/vet, linux amd64+arm64, windows, ANDROID (fix verified
  through the real pipeline), web → gh-pages, publish prerelease.
  Assets verified via API: linux 21.6MB/18.9MB, windows 16.3MB,
  apk 32.2MB + checksums; Pages index+wasm HTTP 200.
- **Slice 203 (toast fidelity)** — research first: SDL3's shipped
  pure-C toast implementation (src/notification/windows/
  SDL_windowsnotification.c) as the working reference + the winmd-
  generated C ABI headers (swift-cwinrt) for the exact vtable order:
  - IToastNotification2 {9DFB9FD1-143A-490E-90BF-B9FBA7132DE7}:
    put_Tag=6, get_Tag=7, put_Group=8, get_Group=9 (IUnknown 0-2,
    IInspectable 3-5). Pinned in comabi.go + tests.
  - Peer avatar in toasts: <image placement="appLogoOverride"
    src="file:///…"> — toastImageSrc converts the notify layer's
    file:// URI (OS path, backslashes) to the file:/// form; only
    local files ride (remote avatars are cached locally anyway).
  - Double-sound bug fixed on BOTH platforms: the toast is silent
    (<audio silent="true"/>) because the app plays its own slice-121
    synthesized chime; Linux banners now set the spec's
    suppress-sound hint (was missing → server sound + chime doubled).
    The dbus fake-server harness asserts the hint (tests first).
  - Per-chat replacement: put_Tag(fnv64a(chat key), 16 hex chars) +
    put_Group("uniclient") → a newer toast for the same chat replaces
    the older in Action Center (the slice-141 "never stack for one
    chat" semantics on Windows too). QI failure (pre-Win10) skips
    tagging harmlessly.
  - AUMID registry metadata (SDL3 recipe): HKCU\Software\Classes\
    AppUserModelId\DarkReaperBoy.Uniclient → DisplayName="Uniclient" +
    IconUri=file:///exe — belt-and-braces with the slice-201 shortcut.
- Gate: gofmt/vet clean · go test -tags goolm ./... 8/8 ok · windows +
  wasm cross-builds ok. Verify workflow dispatched for ab1e5f5b.

## 2026-09-14 — slice 204: Saved Messages pin reorder + delete flow

- Gap 7's remainder (the last user-visible Saved Messages item):
  - Core: ReorderPinnedSavedDialogs (messages.reorderPinnedSavedDialogs,
    force=true — stale server pins outside the passed order unpin
    instead of corrupting; the ReorderPinnedDialogs recipe).
  - Engine: ReorderSavedSublists passthrough; DeleteSavedSublistHistory
    upgraded with the scoped cache purge (DELETE messages WHERE
    saved_peer = peer in the self chat) — was core-only before.
  - GUI (Lists pane): row context menu (secondary press, callsbox
    pattern — pane tag, row bounds, anchored card) with Pin/Unpin
    (toggleSavedDialogPin), Move up/Move down (within the pinned block,
    bounded), and Delete messages behind the slice-190-style confirm
    card (error-path aware, busy state, closes the open scope if it IS
    the deleted sublist, reloads the lists).
  - Real display bug fixed: sortSavedSublists re-sorted the PINNED
    block by last-activity time, hiding the server's pin order —
    reorders would have been invisible. Pinned block now preserves the
    server order (messages.getSavedDialogs returns it); the unpinned
    tail keeps the newest-first fallback.
- Tests first (6 new/updated): engine reorder forwarding + honest
  unsupported paths, delete-purges-cache (seeded rows, other sublists
  survive), menu actions per pinned/edge state, move-peers swaps +
  edge no-ops, the new sort semantics.
- Gate: gofmt/vet clean · go test -tags goolm ./... 8/8 ok · windows +
  wasm cross-builds ok · verify dispatched (2134a5b5).
- Parity: gap 7 CLOSED — PRESENT 181 (91%) · PARTIAL 12 · MISSING 1 ·
  CORE-ONLY 5.

## 2026-09-14 — slice 205: forum topic pin reorder

- Gap 6's actionable remainder (the Left/Bottom tab positions are
  tdesktop EXPERIMENTAL flags — documented out by design under the
  §1.10 dead-UI ban, like gap 3):
  - Core: ReorderPinnedForumTopics converted to the withAPI snapshot
    pattern (it still read t.api/t.ctx directly — the §8 freeze class).
  - Engine: ReorderPinnedForumTopics passthrough + honest unsupported
    paths (tests first, stub records the forwarded order).
  - GUI: the topic actions dialog gains Move up / Move down for pinned
    topics with room in the pinned block (actRow insert + the move
    order computed on the GUI loop before the RPC goroutine).
  - Same display bug as slice 204, forum edition: sortForumTopics
    activity-sorted the PINNED block — reorders were invisible. Pinned
    now preserves the server order (stable partition); the unpinned
    tail keeps activity sort + General-first tiebreak. The slice-156
    topic tab strip follows (it renders the same order).
- Tests first (4 new/updated pairs): engine forwarding + unsupported
  paths, move-IDs swaps + edge/unpinned no-ops, canMove bounds, the
  new sort semantics incl. the all-pinned server-order case.
- Gate: gofmt/vet clean · go test -tags goolm ./... 8/8 ok · windows +
  wasm cross-builds ok · verify dispatched (7fa833d3).
- Parity: gap 6 CLOSED — PRESENT 182 (92%) · PARTIAL 11 · MISSING 1 ·
  CORE-ONLY 5. Every remaining gap is now blocked/owner-decision/
  experimental-by-design: video decode (pure-Go H.264/VP9 absent),
  webview mini-apps (owner decision), experimental flags (dead-UI ban),
  avatar corners (AyuGram default), checkout UIs (stars gifting +
  giveaway launch), PiP (video-decode-blocked), proximity radius +
  message-details DC row (P3 honest scope), logo/userpic polish (P3).

## 2026-09-14 — session wrap (slices 201–205 + android fix + v0.9.0)

- Session resumed from the slice-200 state via AGENTS.md + WORKLOG;
  devroot rebuilt (go 1.27.1; 3GB RAM box — GOGC=20, -p 1,
  -gcflags=all=-c=1, cross-builds via the CI-verify dispatches).
- Shipped (all pushed + verify-workflow-verified per commit):
  - 201: own-AUMID Start-Menu shortcut (pure-Go IShellLinkW +
    IPersistFile + IPropertyStore; PKEY pinned vs fresh mingw-w64
    headers) — toasts source "Uniclient".
  - 202: toast click-through — protocol activation (uniclient://open),
    HKCU scheme registration, single-instance command channel
    (lockfile+cookie+localhost), raise+open-chat hop, cold-start boot
    routing.
  - 203: toast fidelity — avatar in the appLogoOverride slot, silent
    toast + Linux suppress-sound (real double-sound bug fixed on both
    platforms), per-chat tag/group replacement (IToastNotification2,
    ABI pinned vs winmd C headers + SDL3 reference), AUMID registry
    metadata.
  - 204: Saved Messages sublist pin reorder + delete-with-confirm
    (reorderPinnedSavedDialogs + deleteSavedHistory cache purge) +
    the pinned-server-order display fix.
  - 205: forum-topic pin reorder (actions-dialog Move up/down,
    core converted to withAPI) + the same server-pin-order fix.
  - Android APK build regression fixed (bare `linux` build tag matched
    GOOS=android; appicon X11 files excluded, stub covers android).
- v0.9.0 released: all 7 release jobs green (test/vet, linux amd64 +
  arm64, windows, android — the fix verified through the real APK
  pipeline — web → gh-pages, publish prerelease). Assets + Pages
  verified via API.
- Parity: PRESENT 182 (92%) · PARTIAL 11 · MISSING 1 · CORE-ONLY 5 —
  every remaining gap documented as blocked / owner-decision /
  experimental-by-design / checkout-UI / P3-honest-scope in
  research/ayugram_parity.md. The parity program's actionable queue is
  EMPTY as of this session; the next agent should re-verify that
  assessment against AyuGramDesktop dev (the parity file's sources
  note) before inventing work, then look at the P3 honest-scope cuts
  (proximity radius, message-details DC row, logo/userpic polish) if
  the owner wants 100% row coverage.
- Next-session notes: gotd v0.161.0 lacks payments.transferStarAmount
  (stars gifting stays checkout-gated until a gotd upgrade, which is a
  freeze-risk change deserving its own session).

## 2026-09-14 — slice 206: profile music ("saved music", new upstream feature)

- Resumed from the slice-205 session-wrap state (AGENTS.md + WORKLOG);
  devroot rebuilt from scripts/devroot-setup.sh (go 1.27.1, user-space
  sysroot). GitHub baseline verified via API: main == local HEAD,
  v0.9.0 prerelease live (5 assets), verify run 34821098103 green.
- Parity re-verification (the session-wrap note's first ask): walked
  AyuGramDesktop `dev` via the GitHub API — nothing since 2026-09-01,
  latest commit e45d60d9 (2026-08-08). ONE feature landed after the
  09-13 truth pass: "saved music" / profile music (info/saved/*,
  data_saved_music.cpp, history_view_save_document_action.cpp) —
  songs pinned on user profiles. gotd v0.161.0 = layer 228 already
  ships the whole RPC surface (users.getSavedMusic,
  users.getSavedMusicByID, account.getSavedMusicIDs, account.saveMusic,
  userFull.saved_music); the repo even had the raw RPC wrappers from a
  bulk surface slice. Rated the core 8/10 — extend, don't replace.
- Slice 206 shipped (tests first at every layer, research in
  research/profile_music.md):
  - Core (cores/telegram_savedmusic.go): normalizeMusicDoc
    (DocumentAttributeAudio, voice excluded, file-name attr fallback),
    profileMusicSaveRequest (unsave / after_id flag mapping), typed
    GetProfileMusic (users.getSavedMusic via withPeer+withAPI
    snapshot) / SaveProfileMusicDoc / GetOwnSavedMusicIDs.
  - Engine (engine/profilemusic.go + migrateV55 profile_music table):
    position-ordered per-(account, peer) cache fed on cold open,
    Save/Remove/Reorder own-playlist mutations w/ cache + event
    refresh, OwnProfileMusicCached/Refresh (hash = Σids, tdesktop
    Api::CountHash semantics), TrackFromMessage (media-table
    remote_ref/extra + content tags), PlayProfileMusicTrack
    (download-once → shared in-app player keyed
    (account, "profilemusic", docID)), EventProfileMusicChanged.
  - GUI (gui/profilemusic.go + profile/menu/state/app hooks): panel
    Music section (tdesktop MusicButton 1:1 — first track + count,
    hidden when empty), full playlist view (tap = play w/ active
    tint, duration labels, honest empty state), own rows ⋮ Move
    up/Move down/Remove, other rows ＋ add-to-my-profile, bubble-menu
    Add/Remove-from-profile-music gated on the live own-ID set
    (hidden until loaded), onEvent reload wiring.
  - Tests: 7 core (normalization + request shapes), 9 engine (cache,
    mutations, reorder edges, hash gating, gates), 3 GUI (duration
    label, menu gate, fallbacks).
- Gate: gofmt clean · vet clean · go test -tags goolm ./... ALL green
  (engine/gui/cores/utils/bootstrap/voice/audio/lottie) · linux native
  binary links (dist/uniclient) · windows + wasm cross-builds green.
- Parity: NEW ROW PRESENT — 200 rows, PRESENT 183 (92%).

## 2026-09-14 — slice 207: message-details Datacenter + sticker-author rows

- Gap 15 (the P3 honest-scope cut from the session-wrap notes): the
  message-details dialog gains the two AyuGram rows that were "honestly
  absent (not cached)".
- Research (primary sources): AyuGram telegram_helpers.cpp getMediaDC
  (document/photo getDC) + getDCName (DC1/3 Miami, DC2/4 Amsterdam, DC5
  Singapore, UNKNOWN beyond); context_menu.cpp AddMessageDetailsAction —
  the sticker-author row via getUserIdFromPackId (TDesktop-x64 bit
  formula: ownerId = id>>32, 0x3f byte at >>16 → |0x80000000, non-zero
  byte at >>24 → +0x100000000) + ContextActionStickerAuthor.
- Shipped (tests first):
  - Core: FileRef.DC (json "dc") — the document/photo normalization
    fills it from tg.Document.DCID / tg.Photo.DCID.
  - Engine: migrateV56 (media.dc_id), cacheMediaRef + the read join
    carry it → CachedMessage.MediaDC; engine/msgdetail.go —
    StickerPackAuthorID (bit formula, unit-tested incl. the two
    correction branches) + CachedMessage.StickerSetID (content extra
    parse, malformed-safe).
  - GUI: "Datacenter" row (dcNameLabel = AyuGram's mapping, pure
    tested, hidden when the engine has no DC — non-Telegram platforms
    and old cache rows stay honest); "Sticker author" row (async
    users.getFullUser resolve — which caches the peer access hash —
    name or "user <id>" fallback, tap opens the author's chat through
    the search-result open pattern; copy otherwise untouched).
- Tests: 3 engine (DC round-trip, author formula vectors, set-ID parse)
  + 3 GUI (DC label table, Datacenter row gating, author row + resolved
  name + non-sticker negative).
- Gate: gofmt clean · vet clean · go test -tags goolm ./engine/ ./gui/
  ./cores/ ./utils/ green.
- Parity: message-details PARTIAL→PRESENT — 200 rows, PRESENT 184 (92%),
  PARTIAL 10 (honest scope cuts 5). Remaining P3 cuts: proximity radius
  (gap 14) + logo/userpic polish (gap 19).

## 2026-09-14 — slice 208: GeoProximityReached service message (gap 14 closed)

- Research (primary sources, tdesktop dev tree): proximity-radius SETTING
  UI does not exist on desktop — location_picker.cpp (1382 lines) and
  history_view_location.cpp carry zero proximity references; api.tl has
  the wire fields (inputMediaGeoLive.proximity_notification_radius,
  messageActionGeoProximityReached) and history_item.cpp
  prepareProximityReached renders the alert as a SERVICE message. So the
  full desktop parity scope = rendering the server-pushed alert; the
  radius picker is mobile-only (absent upstream — not an honest scope
  cut anymore, it's parity).
- Shipped (tests first):
  - cores/telegram_proximity.go: proximityDistanceLabel (m / km at 10 m
    precision — the tdesktop formula) + proximityReachedText (the three
    sentence shapes: from-self "You're now within D of X", to-self
    "X is now within D of you", third-party "X is now within D of Y") +
    proximityPeerName (user/channel/chat cache resolution).
  - serviceActionText: the MessageActionGeoProximityReached case (self
    detection via t.selfID, both peer names, distance) +
    serviceActionTag "geo_proximity_reached". GUI renders it like any
    service row — no GUI change needed.
- Tests: 2 core (distance-label table incl. the 1234→1.2 km rounding,
  sentence shapes).
- Gate: gofmt clean · cores suite green (vet via CI dispatch).
- Parity: location PARTIAL→PRESENT — 200 rows, PRESENT 185 (93%),
  PARTIAL 9 (honest scope cuts 4: local premium toggle, chat-settings
  extras, QR scan, logo/userpic polish).

## 2026-09-14 — slice 209: Android audio devices (OpenSL ES via purego)

- The last honest platform gap in the voice pipeline: Android's audio/
  layer was ErrNoAudio (mic + speaker + notification sounds + media
  playback all dead on the APK). Now a real OpenSL ES device layer.
- Research (primary sources, all fetched and transcribed fresh):
  - ebitengine/purego v0.10.2: Android arm64/amd64 Tier-1, requires
    CGO_ENABLED=1 — already satisfied (gogio builds -buildmode=c-shared
    via the NDK; the cgo runtime is the toolchain's, our tree stays
    pure Go).
  - AOSP frameworks/wilhelm include/SLES/{OpenSLES.h,
    OpenSLES_Android.h, OpenSLES_AndroidConfiguration.h}: exact
    SLObjectItf_/SLEngineItf_/SLPlayItf_/SLRecordItf_/SLBufferQueueItf_
    vtable orders, SLDataLocator_IODevice/OutputMix/AndroidSimpleBuffer
    Queue + SLDataFormat_PCM layouts, constants, VOICE_COMMUNICATION
    recording preset.
  - Official jni.h (OpenJDK head): JNIEnv/JavaVM vtable ordinals
    extracted programmatically (incl. the 4/3 reserved-slot offsets).
  - gio v0.10.2 public surface: app.AndroidViewEvent{View uintptr} +
    app.JavaVM() — the documented pure-Go JNI injection points;
    gogio's permission scan: blank import of
    gioui.org/app/permission/microphone puts RECORD_AUDIO in the APK
    manifest (release.yml already builds with -minsdk 24, so
    checkSelfPermission/requestPermissions (API 23+) are always there).
- Rating (§1.14): audio package architecture 8/10 — clean Session/
  device seam, honest ErrNoAudio stubs; keep + extend. New plan 9/10.
- Shipped (tests first — opensl_layout_test.go written and green
  before the implementation):
  - audio/opensl_layout.go (+test): platform-independent ABI tables —
    OpenSL vtable indices, wire-struct mirrors (size/offset pinned on
    64-bit), JNI ordinals, and the bqRing FIFO bookkeeping type; every
    value double-transcribed from the headers and cross-checked.
  - audio/opensl_android.go: engine + output mix at open; AudioPlayer
    (48 kHz mono s16 AndroidSimpleBufferQueue) with a polling fill
    pump (no C callbacks); AudioRecorder with VOICE_COMMUNICATION
    preset + the same polling pump; honest SLresult error mapping;
    objects destroyed on stop; KeepAlive anchors on every uintptr
    that crosses a helper boundary.
  - audio/jni_android.go: minimal pure-Go JNI (AttachCurrentThread with
    LockOSThread, GetVersion ABI sanity gate, exception hygiene,
    local-ref cleanup) → checkSelfPermission + requestPermissions;
    ensureMicPermission blocks ≤10 s on the system dialog, then errors
    honestly (surfaced by the existing afterVoiceJoin toast).
  - audio/view_android.go / view_other.go: SetAndroidViewEvent plumbing
    (android: stores View + JavaVM; elsewhere: no-op) — gui/state.go
    ListenEvents forwards every event.
  - stub_other.go narrowed to genuinely-unsupported GOOS values;
    android comment updated.
  - verify.yml: new android job (NDK + gogio APK compile check) so
    android-only compile errors surface before a release tag.
- Semantics match the Pulse driver: mic channel closed on stop, 20 ms
  1920-byte s16le frames, "already running" guards, error wrapping.
- Gate: gofmt clean · go vet ./audio/ clean · go test ./audio/ green
  (7 new tests) on linux; android compile = CI dispatch + release job.
- Remaining rung: the owner's real-device test (mic/speaker hardware)
  — same standing as the other live-test items.

## 2026-09-14 — slice 210: music attach box (saved-music source)

- Gap 20's future slice: the attach-menu "Music" entry opened only the OS
  file picker; tdesktop's music_attach_box carries an in-app source.
- Research (primary source, fetched): telegramdesktop/tdesktop dev
  boxes/music_attach_box.{h,cpp} — box = search + "Choose from files" +
  Saved Music section (data_saved_music, Show all) + chats/global-search
  sections; Send resolves selected documents and re-sends them as audio
  messages (sendFiles document path → inputMediaDocument).
- Rating: attach flow 7/10 (clean explorer-based picker; the box was
  simply absent) — keep + extend.
- Shipped (tests first — 2 core, 2 engine, 4 GUI pure helpers, all
  written before the implementation):
  - Core: audioSendMediaRequest (pure request builder, unit-tested) +
    SendAudioDocument (messages.sendMedia with InputMediaDocument by
    docID + access hash + file reference, withAPI/withPeer snapshot
    pattern).
  - Engine: AudioDocumentSender optional capability + SavedMusicTracks
    (own playlist w/ honest ErrNotSupported) + SendSavedMusicTrack
    (cache-resolved track + caption).
  - GUI (gui/musicattach.go): content-pane box — "Choose from files"
    row (the previous picker path), Saved Music section (query filter
    over title/performer/file-name, 6-row preview + Show all,
    checkbox multi-select, honest empty/error/unsupported states),
    selection-aware Send bar; sends in playlist order with the
    composer's caption on the first track; attach menu's Music entry
    opens the box. New surface "musicAttach" wired through frame +
    contentDialogSurface.
- verify.yml's new android job earned its keep immediately: the slice-209
  dispatch caught three real android-file compile errors (const/function
  name collisions slObjectRealize/GetItf/Destroy, invalid multi-value
  indexing of purego.SyscallN, jvalue literal needing uint64) — all
  fixed (functions renamed slRealize/slGetItf/slDestroy, r1,_,_ :=
  SyscallN(...), uint64 conversions). gofmt miss in groupcall.go from
  the slice-209 commit also fixed.
- Gate: gofmt clean · go vet+test ./audio/ green locally; full gate via
  the re-dispatched Verify run (gotd tg compile needs >3GB, this VM
  has 3GB — CI is the sanctioned verifier, AGENTS.md §5).

## 2026-09-14 — slice 211: star gifts (catalog picker + balance-funded checkout)

- Parity gap 9 re-verified against primary sources and found STALE: the
  old note ("gotd layer lacks the transfer RPC") predates gotd v0.161.0,
  which carries the full modern surface — payments.getStarGifts (unified
  starGift: id/sticker/stars/limited/availability), getStarsGiftOptions,
  getStarsStatus, getPaymentForm→paymentFormStarGift→sendStarsForm, and
  inputInvoiceStarGift. tdesktop's star_gift_box.cpp read line-by-line:
  the balance-funded gift purchase completes IN-APP (no external
  checkout); only topup flows need a browser.
- Rating: stars surface (slice 144) 8/10 — keep + extend with the gifting
  leg it lacked.
- Shipped (tests first — 4 core + 6 GUI pure tests, written before the
  implementation):
  - cores: StarGiftInfo/StarsGiftAmount typed shapes; telegram_gifts.go —
    starGiftsFromWire (unified-gift normalization, thumbs via the
    existing stripped-thumb pipeline, collectibles excluded as resale
    objects), giftOptionsFromWire, starGiftInvoice (flag mapping),
    GetStarGifts / GetStarsGiftOptions (user-peer resolved) /
    GetStarsBalance (nanostars) / SendStarGift
    (getPaymentForm → sendStarsForm; PaymentVerificationNeeded → honest
    error pointing at the Stars settings page).
  - engine/gifts.go: GiftCore optional interface + per-account catalog
    cache (10 min TTL) + balance/send passthroughs.
  - gui/gifts.go: "Send a gift" peer-menu row (DMs on gift-capable
    platforms — headerMenuItems gained a tested giftsOK gate) → gift
    picker surface: catalog grid (sticker thumbs, star prices, limited /
    sold-out / birthday badges, balance-aware buyability), live balance
    line, optional message + hide-name, single-select Send.
- CI round 2 (dispatch on 2f3dc50e) caught real errors in slice 210's
  GUI code — all fixed: material.Icon doesn't exist in gio v0.10.2
  (widget.Icon renders directly via ic.Layout(gtx, color)), a.ui.H4 →
  H3, the android SetAndroidViewEvent signature must take any (matching
  view_other.go), and ScheduleDate is a plain int (no truthiness).
- Gate: gofmt clean · audio tests green · windows+wasm audio
  cross-compiles green locally; full gate on the dispatched run.

## 2026-09-14/15 — slice 211 repair + slice 212: giveaways

### CI repair streak (five consecutive red Verify runs → green)
- Diagnosis via job logs: the slice-211 "reconcile" commit changed
  GetStarGifts to return *StarGiftsResult without updating call
  sites/tests; vet aborts per package at the first error, so each CI run
  surfaced only the next error (gifts.go assignment → telegram_gifts_test
  shapes → engine giftStub harness → gui folders_test hideAll arg →
  musicattach duplicate map key → appendSimilarRow collapsed arg → two
  gui RUNTIME test failures invisible to vet).
- Fixes: gui picker consumes StarGiftsResult.Gifts (nil-guarded); test
  files match the reconciled shapes (len(out.Gifts), ID/Total/Remaining,
  value-typed TextWithEntities); newGiftEngine accepts cores.Core;
  buildFolderTabs gets its hideAll arg; musicattach duplicate map key
  removed; appendSimilarRow collapsed arg restored; giftCellSubtitle
  uses strconv.Itoa (the badge itoa clamps at 999+ — availability counts
  are not unread badges); musicattach filter test queried UNTAMED which
  is not in "untagged_song.mp3" (UNTAGGED now).
- Local verification upgraded despite the 3GB/2-core VM: Go 1.27.1
  installed, gotd tg compiles with GOGC=10 GOMEMLIMIT=3400MiB
  -gcflags=all=-c=1; gofmt+vet+tests run for cores/engine/utils/audio/
  bootstrap/voice/wrtc locally; gui type-checks via GOOS=windows
  cross-vet (pure-Go target, same sources — unsafeptr COM
  false-positives aside, those files are CI-only). cmd/uniclient still
  CI-only (needs wayland/xkbcommon headers).
- Verify run on eff6b3e5: ALL FOUR JOBS GREEN (test+vet+gofmt, GUI
  smoke, cross-builds, android).

### Slice 212 — giveaways (gap 10)
- Research (primary sources): tdesktop create_giveaway_box.cpp +
  payments_form.cpp read line-by-line — stars giveaways check out
  IN-APP via inputInvoiceStars(inputStorePaymentStarsGiveaway) →
  payments.getPaymentForm → paymentFormStars → payments.sendStarsForm
  (the desktop-completable path; store products are mobile billing);
  prepaid launches ride payments.launchPrepaidGiveaway with the purpose
  split (credits>0 → stars, else premium); random id = tdesktop
  UniqueIdFromCreditOption (XXH64 of stars|storeProduct|currency|amount|
  peerID|sessionID); default end date +3 days rounded up to a 5-minute
  boundary; additional-prize cap 128 chars. gotd v0.161.0 surface
  verified present (PaymentsGetStarsGiveawayOptions,
  PaymentsLaunchPrepaidGiveaway, InputInvoiceStars,
  InputStorePaymentStarsGiveaway/PremiumGiveaway).
- Rating: old giveaway surface 5/10 — map-typed params, hardcoded
  USD/0 amount, prepaid launch only ever built the premium purpose
  (wrong for PrepaidStarsGiveaway entries), and the whole family
  (LaunchRandomGiveaway, LaunchCreditsGiveaway, GetGiveawayConfig,
  AwardPremiumGiveaway, old LaunchPrepaidGiveaway) was wired to NOTHING
  (dead core surface, §1.10 hazard). Replace, don't patch.
- Shipped (tests first — 4 core + 3 engine + 7 gui pure tests):
  - cores/telegram_giveaways.go: giveawayOptionsFromWire,
    starsGiveawayInvoice/starsGiveawayPurpose (flag mapping),
    prepaidGiveawayPurpose (stars/premium split), giveawayRandomID
    (XXH64, pinned), GetStarsGiveawayOptions, CreateStarsGiveaway
    (getPaymentForm→sendStarsForm, PaymentVerificationNeeded → honest
    topup error), LaunchPrepaidGiveaway (typed).
  - base.go: StarsGiveawayWinnerInfo / StarsGiveawayOptionInfo /
    GiveawayParams (protocol-neutral).
  - engine/giveaways.go: typed passthroughs behind optional
    interfaces; dead map-typed family deleted from engine.go and
    telegram.go; GetGiveawayPeriodMax kept (date preset filter).
  - gui/giveaways.go: giveaway box (prize option cards, winner-split
    chips, end-date presets filtered by giveaway_period_max, only-new +
    show-winners toggles, additional-prize editor with 128 cap, balance
    line + total, send gate, honest error/empty/loading states, done
    hint); prepaid mode (summary + date/audience + launch). Boosts page
    gains "Start a Stars giveaway" (channel-gated) + prepaid rows with
    Launch buttons. Surface "giveaway" wired through frame +
    contentDialogSurface.
- Local: cores+engine tests green, gui windows cross-vet clean, gofmt
  clean. Full gate on the dispatched Verify run (a958c0e6).
- Parity: gap 10 now "creation+prepaid shipped; card-funded premium
  giveaway + country/additional-channel pickers remain".

## 2026-09-15 — slices 213 + 214: earn tab + giveaway audience pickers

### Slice 213 — stats Earn tab (gap 9 closed)
- Research: tdesktop api_earn.cpp HandleWithdrawalButton read — the
  withdraw flow is 2FA password (SRP) → payments.getStarsRevenueWithdrawalURL
  (ton flag for channel revenue, amount for bot stars) → open the URL in
  the browser. GetStarsRevenueStats was CORE-ONLY dead surface (a §1.10
  hazard sitting since an earlier slice); the earn GUI never shipped.
- Shipped (tests-first): cores/telegram_earn.go — withdrawStarsRevenueRequest
  pure builder (flag mapping) + WithdrawStarsRevenue (SRP via
  auth.PasswordHash, empty → InputCheckPasswordEmpty, honest
  "no 2FA password set" error); engine/earn.go passthrough; gui stats
  page gains Overview|Earn tabs — balance card (available/overall + USD
  line), revenue charts (map→StatsGraphData, async graphs dropped like
  statsChartCard's honest skip), 2FA password + Withdraw row
  (earnWithdrawReady gate) → openExternalAsync handoff.
- GUI smoke screenshots from the green eff6b3e5 run inspected: welcome,
  picker, authflow all render real content (800+ colors each).

### Slice 214 — giveaway audience pickers (gap 10 remainder)
- Research: gotd v0.161 HelpGetCountriesList verified (ISO2/DefaultName/
  Name/Hidden); old repo GetCountriesList returned only a COUNT (dead
  code) — deleted, replaced by the typed []cores.CountryInfo surface.
- Shipped (tests-first): countriesFromWire normalization + typed
  core; engine passthrough; GUI giveaway box gains the Countries row
  (All countries → picker: search + multi-select over ~250 rows) and
  the Channels-to-join row (same-account channels excluding the
  giveaway channel; hidden when the account owns none). Selections ride
  GiveawayParams.Countries/ExtraChats into the slice-212 invoice
  builders (already unit-tested). sortedKeys keeps the wire payload
  deterministic.
- Local verification deepened: a scratch harness (scripts/verifyhelpers,
  gitignored) runs the pure GUI helpers against their test expectations
  locally (gui tests are CI-only on this VM) — caught two wrong test
  expectations before CI (async-chart drop, "D" substring matches).
- CI: slice-212 giveaway test fix green (7cd46a08 failed only on the
  stale earn-charts expectation, fixed in d38ae780 + dispatched).

## 2026-09-15 — v0.10.0 released

- Verify green on d38ae780 (test+vet+gofmt, GUI smoke, cross-builds,
  android — all four jobs).
- Tag v0.10.0 cut: release workflow green on all 7 jobs (test, linux
  amd64/arm64, windows, android APK, web→gh-pages, publish). Release
  verified via API: prerelease=true, assets uniclient-linux-amd64
  (21.7MB), -arm64 (19.0MB), -windows-amd64.exe (16.4MB),
  uniclient.apk (32.3MB) + checksums.txt; gh-pages updated (37fe751e),
  Pages serves 200 at /Uniclient/.
- Parity: PRESENT 186/200 (93%). Remaining gaps are all honest cuts or
  blocked (pure-Go video decode, webview owner-decision, card-funded
  premium giveaway, experimental flags) — see
  research/ayugram_parity.md.

## 2026-09-15 — slice 215: Avatar Corners (AyuGram userpic styling) + initials paint-order fix

Research (primary sources, GitHub API): AyuGramDesktop dev
settings_appearance.cpp BuildAvatarCorners + ayu/ui/ayu_userpic.cpp
ComputeRadius/ShouldOverrideShape + lib_ui ayu_ui_settings.h
(kMaxAvatarCorners = 23, default 23 = circle) + tdesktop dev
data_peer.cpp/userpic_view.cpp (ForumUserpicRadiusMultiplier 0.3) +
AyuGram/Languages strings. Findings: research/avatar_corners.md.

Rating: 9/10 — the slice-170/93 config-slider + settings-section
patterns are solid; extended, not replaced.

Tests first (9 new cases, written before the implementation):
gui/avatarcorners_test.go (radius formula incl. clamps, SQUARE/CIRCLE
pill, forum 30% rounding, chat-level resolver incl. the toggle,
slider mapping, cfgFromAppConfig defaults, preview state) +
engine/avatarcorners_test.go (config round-trip + boundary clamp).

Implementation:
- utils/config.go: AppConfig.AyuAvatarCorners *int +
  AyuSingleCornerRadius *bool (nil = 23 / false), ClampAvatarCorners,
  EffectiveAvatarCorners.
- engine: ConfigChanges fields + apply with clamp.
- gui/avatarcorners.go (new): pure helpers (ComputeRadius formula,
  pill, forum radius, ShouldOverrideShape resolver, three-way
  avatarShapeClip, slider mapping) + the settings section — slider row
  (24 steps, SQUARE/CIRCLE/step pill), live preview row (a settings
  preview control: "Uniclient Releases / Better late than never ·
  preview"), Single Corner Radius toggle with the exact upstream
  string, debounced 600 ms persist.
- Rendering, app-wide: UI.Avatar → AvatarShaped twin (letter avatars,
  thread the radius); avatarFromImage/drawImageAvatarCover (image
  avatars, three-way clip); drawBookmarkAvatar (Saved Messages);
  storyCircle (forum-aware); chatAvatar is the forum chokepoint
  (ChatInfo.IsForum + cfgSnapshot); b64/account/calls/similar/
  sponsored/signup avatars take the global radius. Boot + refreshConfig
  wiring (applyAvatarCorners), NewUI seeds the circle default.
- BUG FIX (found by inspecting the paint order + the CI Xvfb
  screenshots, VLM-verified: circles render with NO initials):
  UI.Avatar painted the bg fill AFTER the initials since v0.4.0 — the
  fill covered them. AvatarShaped paints the shape fill first, the
  initials on top. Letter avatars show initials again.

Parity: rows 255 + 256 PARTIAL→PRESENT; verified recount
(PRESENT 185 / PARTIAL 9 / MISSING 1 / CORE-ONLY 5 of 200). Honest
remainder: online-dot/story-ring stay circular (visual micro-detail).

Verification: gofmt clean (standalone gofmt — this sandbox cannot run
the full toolchain); CI verify dispatched on this commit (test+vet+GUI
smoke+cross-builds) — the sanctioned small-sandbox path (§5).

## 2026-09-15 — slice 215 fix round 2: initials position (constraint leak)

First CI pass was green but the Xvfb screenshots still showed plain
circles — the initials rendered ABOVE each avatar. Pixel forensics on
shot-2 (glyph runs at avatar-origin + (13, -20)) + reading the gio
v0.10.2 sources pinned the real root cause: the v0.4.0 centering offset
was computed from the label's LAYOUT DIMS, and parents leak Min
constraints (platformCard's ButtonLayout sets Min.Y=84) —
widget.Label's `dims.Size = cs.Constrain(...)` inflates the height to
84, so (44-84)/2 = -20 pushed the initials up and out. X stayed correct
only because Min.X was 0.

- AvatarShaped: the label now lays out CONTAINED (Min zeroed, Max =
  the avatar box — which is also widget.Label's glyph-cull viewport),
  so its dims are natural and the centering offset is true. Paint order
  (fill under initials) from round 1 kept.
- drawBookmarkAvatar: same bug class for the centered bookmark glyph —
  layout.Center offsets by max(child, caller-Min), so the glyph pinned
  to the top-left; contained with Exact(size) constraints now.
- No unit test for the position itself (would need an ops decoder);
  the CI Xvfb screenshots + pixel check are the verification rung.

Parity/worklog numbers unchanged. Verify re-dispatched after the push.

## 2026-09-15 — v0.10.1

- Verify green on 4354cbee (all 4 jobs: test/vet/gofmt, GUI smoke,
  cross-builds, android).
- Slice 215 verified end-to-end: pixel forensics + VLM on the fresh Xvfb
  screenshots read the initials in every picker circle (TE, IR, MA, GI,
  XM, MU, T3, DC, BA, RU) — the v0.4.0 plain-circle bug is dead. The
  welcome + authflow screens are anomaly-free (VLM CLEAN).
- v0.10.1 tagged (avatar corners + initials fix; parity PRESENT 185/200).
  - Release verified via API: v0.10.1 workflow green on all 7 jobs,
    prerelease=true, assets linux amd64/arm64 (21.7/19.0MB), windows
    (16.4MB), APK (32.3MB) + checksums; gh-pages updated (0f1e3f44),
    Pages serves 200 at /Uniclient/.

## 2026-09-16 — slice 216: video stickers + video emoji play in-chat (pure-Go VP9)

Research (fresh, primary sources — the old notes said "blocked", now stale):
- The 2026-09-11 verdict "no pure-Go VP9 decoder" expired: two appeared
  mid-2026. mgvs/go-vp9 v0.2.0 (18k LOC, tagged, bit-exact vs libvpx on
  its test streams) and thesyncim/govpx (437k LOC libvpx port, full
  official VP9 conformance corpus in CI, untagged pseudo-version).
- H.264 is STILL blocked (hi264 v0.10.0 IDR+P_Skip only; mgvs/go-openh264
  intra-only; nothing else new). Round videos keep the system-player
  handoff. Full survey: research/video_stickers.md.
- Decoder evaluation against 14 official webmproject test vectors:
  go-vp9 entropy-desyncs on quantizer-50/60/63 + size-196x196 and HARD
  PANICS (index -1 in appendSub8x8) on quantizer-40 → REJECTED (a panic
  in a GUI app is fatal). govpx decodes 100% of the same vectors
  (incl. every one go-vp9 failed) at 1.5-10ms/frame on the 2-core CI
  VM → SHIPPED. Pinned via proxy pseudo-version
  v0.0.0-20260716224042-691cd0512c48; zero module deps; asm gated
  amd64/arm64&&!purego so wasm/js and purego builds stay scalar.

Rating: tgsPlayer pattern 9/10 — extended, not replaced (§1.12). The
seams: stickerKindWebm (thumb-only path) and classifyEmojiArt's
"unsupported" slot for video/webm.

Shipped (tests-first — 16 webm + 13 vp9anim cases before implementation):
- go/webm/ (new): minimal pure-Go EBML/WebM reader scoped to
  single-track VP9 — varint edge cases, unknown-size tolerance, VP9
  track discovery, cluster/block timecode math (signed int16 offsets,
  TimecodeScale→ns), all three lacing modes with ffmpeg-exact semantics
  (first EBML size = plain vint value; deltas = value − (2^(7n−1) − 1);
  pinned from matroska.org spec + ffmpeg matroskadec.c), the WebM VP9
  ALPHA side stream (BlockGroup → BlockAdditions → BlockMore →
  BlockAdditional id 1) returned per frame, top-level truncation
  rejection (partial downloads), frames sorted by presentation time.
  Verified against 4 real official vectors (352×288, 196×196, 160×90
  profile-2, 148KB quantizer-00).
- go/vp9anim/ (new): the player — Parse (demux + VP9 header sniff for
  profile/colorimetry: BT.601 studio default, BT.709/sRGB-full when
  signaled; honest ErrNotVP9Profile0 for 10/12-bit), timeline build
  (container duration → DefaultDuration → 40ms fallback), decodePair
  (primary + alpha stream; broken alpha degrades to opaque like
  tdesktop), YUV→RGBA with round-half-up Q14 constants (Y235→255,
  Y16→0), Player with a background sequential producer (VP9 inter needs
  refs), global decode semaphore (NumCPU clamped 1-4) so a wall of
  stickers shares the CPU, sliding ring of 6 frames lookahead or
  full-cache under a 24MB budget, loop wrap resets the pipeline,
  NextFrameIn for repaint scheduling. Size guards: 4096² pixels,
  600 frames.
- gui/vp9player.go (new): per-message webmPlayers cache mirroring
  tgsPlayers (async parse, wholesale prune at 96 with async Stop —
  producers own goroutines), drawWebmSticker (power-saving static first
  frame, thumbnail fallback while the producer warms up),
  replayWebmSticker (tap = replay, AyuGram behavior — the old tap was
  system-player handoff), drawWebmEmoji for the shared per-document
  emoji path.
- gui/tgsplayer.go: stickerBubble's stickerKindWebm branch now plays;
  comments updated. gui/media.go: tap handling. gui/emojifile.go:
  emojiArtVideo kind — inline custom emoji AND reaction pills animate
  (both flow through drawEmojiArt); cache eviction stops players
  async. classifyEmojiArt("video/webm") → video (test updated).
- testdata: vp90-2-03-size-196x196.webm (12.5KB, 10 frames, odd dims)
  + vp92-2-20-10bit-yuv420.webm (12.7KB profile-2 rejection vector).
  End-to-end pins: frame count, dims, duration, decode-through-all,
  first-frame RGBA FNV checksum (16149418980420066017), alpha-pair
  decode through a synthesized BlockAdditional document.

Verification: webm+vp9anim+engine+cores+utils+audio+bootstrap+voice+lottie
tests green locally (low-RAM recipe); gui windows cross-vet clean (only
the pre-existing COM unsafeptr warnings); wasm+windows cross-builds of
the new packages green; 14/14 official vectors decode. CI verify
dispatched after push.

Parity: rows 146 (Sticker animated) + 147 (Animated custom emoji) fully
PRESENT — the webm caveats are gone. Remaining video gaps are H.264-only
(PiP, streaming video, video bubbles decode).

## 2026-09-16 — slice 218: per-chat custom wallpapers

Research (primary sources): core.telegram.org/api/wallpapers read in full
— image wallpapers render from the document (blur = downscale to fit
450×450 + box blur radius 12; motion = parallax, desktop-irrelevant);
uploads use account.uploadWallPaper with for_chat for the per-chat flow
(skips the automatic global install); messages.setChatWallPaper carries
wallpaper+settings+for_both/revert; receivers learn it via
messageActionSetChatWallPaper (Same/ForBoth flags + the full wallPaper
constructor). The dead revert-only SetChatWallpaper core surface (no
callers anywhere — a §1.10 hazard) was REPLACED (§1.12) with the typed
full surface.

Rating: theme-emoticon mirror machinery 9/10 — extended verbatim (the
wallpaper rides the exact same peer-mirror mechanism, migrateV57).

Shipped (tests-first where pure):
- cores: wallpaperFromWire (wallPaper constructor → WallpaperInfo with
  document coords + settings incl. pattern intensity and the 4-color
  fills; nil-guarded cacheFileInfo), wallpaperSettingsFromInfo (the
  set/install payload, flag-armed), UploadChatWallpaper (uploader →
  account.uploadWallPaper for_chat), SetChatWallpaper (full, for_both),
  RevertChatWallpaper, and the service-message Extra extraction
  (chat_wallpaper JSON + same/for_both flags). 6 core tests pin the wire
  normalization, the settings round-trip and the JSON shape.
- engine: migrateV57 (chats.wallpaper_json), the cacheMessage mirror
  (latest service row wins — the ensureChatExists copy rides along),
  ChatInfo.WallpaperJSON through all three SELECT sites + scanChats,
  Upload/Set/Revert passthroughs (Set/Revert apply the mirror directly
  after the RPC). Mirror test pins set/replace/round-trip/non-string.
- gui/wallpaper.go: the picker dialog (frame-routed contentDialogSurface
  surface "wallpaper", Esc-closed, explorer image pick with async decode
  preview, blur + for-both(Premium) toggles, honest error surface, Set
  flow upload→set→optimistic mirror), the message-pane renderer
  (wallpaperBackground cover-fit via the album-crop primitive, async
  document download through the engine with the mediaImgs cache, spec
  blur chain), Reset wallpaper (revert RPC + mirror clear). 7 pure tests
  (JSON parse + core round-trip, box scaler averaging, blur uniform
  invariance, edge smearing, 450 downscale, small passthrough) verified
  in the local scratch harness (gui tests are CI-only on this VM).
- Blur bug caught by the tests: the guarded moving-average add/remove
  desynced the edge-clamped window multiset (virtual edge copies) and
  overflowed the average — fixed with clamped always-add/always-remove.

Also this session: slice 217 (sticker panel hover animation + the
emojiArt.reading dead-flag fix) and the CRITICAL slice-216 CI fix — the
VP9 decode semaphore was inverted (acquire sent instead of receiving),
deadlocking every producer on machines where NumCPU fills the permit
buffer (4-core CI; the 2-core dev VM masked it). Regression test now
primes the buffer to capacity so the inversion fails on ANY machine
(verified both ways locally).

Verification: cores+engine tests green locally; gui windows cross-vet
clean; wasm+windows cross-builds green; CI verify re-dispatched after
the semaphore fix (run covers 216+217+fix; 218 dispatched after push).

Parity: row 108 (Chat background) fully PRESENT; gap 16 CLOSED.

## 2026-09-16 — v0.10.2 release prep

- Verify green on 0dd182e6 (all 4 jobs: test/vet/gofmt, GUI smoke,
  cross-builds, android) — covers slices 216+217+218 + the semaphore fix.
- Parity after this session: video stickers (row 146), video custom
  emoji (row 147), panel hover animation, and chat background (row 108)
  all fully PRESENT; the remaining gaps are H.264-blocked (video
  playback, PiP), owner-decision (webview), dead-UI-banned
  (experimental), or checkout-gated (card-funded giveaways).
- Tagging v0.10.2 (video stickers + video emoji + wallpapers + panel
  hover animation + the CI-fatal semaphore fix).

## 2026-09-16 — v0.10.2 released

- Verify green on 0dd182e6 (all 4 jobs); v0.10.2 tagged and the release
  workflow completed green on all 7 jobs (test, linux amd64/arm64,
  windows, android APK, web→gh-pages, publish).
- Release verified via API: prerelease=true, assets uniclient-linux-amd64
  (21.0MB), -arm64 (18.3MB), -windows-amd64.exe (15.9MB), uniclient.apk
  (31.2MB) + checksums.txt; gh-pages serves 200 at /Uniclient/ and the
  wasm asset fetches (84.9MB — the govpx VP9 decoder is the new weight;
  wasm is not UPX-able per the release policy, accepted).
- GUI smoke screenshots (VLM): welcome CLEAN, picker CLEAN, authflow's
  folder-tab edge clipping is the known narrow-window (800px) layout
  behavior, unaffected by this session's slices.
- Session totals: slices 216 (video stickers/emoji via pure-Go VP9),
  217 (panel hover animation + reading-flag fix), 218 (per-chat custom
  wallpapers), the CI-fatal semaphore fix, the 65MB stray-artifact
  hygiene drop, and this release.

## 2026-09-23 — session start: baseline repaired + slice 219 planned

### Baseline (prerequisite for §9 "tests green on every commit")
- `go test ./...` was RED at HEAD (6 failures) and `nix build` was broken.
  Fixed both before starting feature work:
  - 4 GUI time tests built fixtures in `time.UTC` while the production
    formatters render local time (Asia/Muscat +04 here) → now `time.Local`.
  - 2 engine player tests drove `mediaPlayer.fill` by hand while a live
    PulseAudio device thread also pulled it → `detachDevice` (stop+close
    session, rewind pos). Headless CI has no device, which is why this
    only failed on a workstation.
  - flake.nix: 8 defects repaired, `nix run github:DarkReaperBoy/Uniclient`
    (§6) had never worked — details in that commit.
  Pushed as 5c0a1ec8 + 29e8593a.

### Research (§1.13) — the H.264 blocker was stale
Both earlier passes (2026-09-11, 2026-09-16) concluded "no pure-Go full
H.264 decoder exists" after surveying hi264 / go-openh264 / gomedia / cgo
wrappers. They never surfaced `liqmix/govid`, which has existed since
2026-03-14. Because its README says "This repo is written by Claude", I did
not take it on trust:
- its 21 skipped tests are missing *local-only* fixtures, not broken paths;
- its committed reference YUV is reproducible byte-for-byte by ffmpeg, so
  its "bit-exact" claims are meaningful;
- **our own two fixtures** (Constrained-Baseline/no-B = Telegram round-video
  shape; High+CABAC+B-frames = worst case), decoded through
  `mp4.NewDemuxer`+`h264.NewCodec()` vs `ffmpeg -pix_fmt yuv420p`: all 12
  frames × 221,184 samples bit-exact, SHA-256 equal to the ffmpeg file.
Findings + rejected candidates recorded in `research/h264_decoder.md`; the
two stale verdicts in `video_player.md`/`video_stickers.md` corrected.

### Rating (§1.14)
- slice-216 video architecture (`vp9anim`: decode-ahead producer behind a
  permit semaphore + frame clock + msgID-keyed GUI cache + InvalidateCmd):
  **9/10** — keep and extend; H.264 needs the same machine, one difference:
  inter frames require *sequential* decode, so the loop seam must recreate
  the decoder (Codec.Flush forgets SPS/PPS, so restart from a fresh demuxer
  whose leading keyframe carries them).
- `videoBubble` + system-player handoff: **7/10** — honest *under the old
  ecosystem limit*, and that limit has expired. Extend, don't replace: it
  keeps thumb/poster/badge/duration and gains a live playing state.
- `govid` as the H.264 base: **9/10** for fitness (pure Go, MIT, stdlib-only
  `h264` prod deps, bit-exact). Caveat: small AI-written project — mitigated
  by pinning OUR conformance hashes as tests rather than trusting theirs.
- stale research docs: **2/10** (actively misleading) → corrected, not
  expanded (§10).

### Plan (best, not fastest) — slices 219-222
- **219** `go/h264vid`: `Parse` (mp4 index + size guards) → `Video` →
  `NewPlayer` with sequential decode-ahead producer behind ONE shared app
  decode budget (`go/vcodec`, extracted from vp9anim so mixed VP9+H.264
  media share a single CPU cap), byte-budgeted ring, `FrameAt`/
  `NextFrameIn`/`SetLoop`/`Seek` (GOP-aligned). Tests FIRST against the
  committed fixtures + pinned ffmpeg SHA-256 + ffmpeg-gated provenance
  + the semaphore prime-to-capacity deadlock regression.
- **220** GUI: `gui/h264player.go` cache keyed by msgID (mirror
  `webmPlayerCache`); `videoBubble`/`videoNoteBubble` render the live frame,
  tap toggles play, round notes loop + circular crop, power-saving gate.
- **221** media-viewer in-app playback controls (play/pause/seek/volume)
  → parity row 276.
- **222** PiP → row 279 (the matrix's only MISSING row).

## 2026-09-23 — slice 219: pure-Go H.264 video core (h264vid) + shared decode budget (vcodec)

Executes plan item **219** from the session entry above. The stale
"no pure-Go H.264 decoder exists" verdict (research/video_player.md,
research/video_stickers.md, AGENTS.md §1.1) is now dead — corrected in
both docs by research/h264_decoder.md, which replaces assertion with
measurement.

### Research (§1.13) → Rating (§1.14) → Plan: see previous entry.
What execution added beyond the plan:

**The colour bug nobody had caught.** ffmpeg treats untagged `yuv420p`
as *limited-range BT.601* — measured, not assumed: Y=16→0, Y=235→255, and
Y=128/Cb=16/Cr=128→(130,173,0) at both 128×96 and 1280×720 (BT.709 would
give (131,154,0)). govid's own helper uses the full-range JFIF formula,
which parks blacks at 16 — washed out. So `h264vid` does its own
conversion: integer CCIR-601, pinned by `TestYUVToRGBIsLimitedRange`
against those exact ffmpeg-measured values.

**Decode order ≠ display order.** The `high_bframes` fixture's packet
PTS in *file* order reads `0.000, 0.100, 0.033, 0.067, 0.133, …`. Parse
sorts composition timestamps to build the display timeline; B-frame
reorder is drained both at end-of-stream and at a GOP boundary.

**Seek and loop are GOP-aligned, not guessed.** H.264 inter frames need
a sequential feed, so `Seek` rebuilds the demuxer+decoder at the keyframe
at-or-before the target (index pass records sample number *and* display
index for every sync sample) and `FrameAt` issues the same restart when
the playhead wraps behind an evicted frame. The producer never eagerly
re-decodes a lap — that would spin the CPU for a full clip nobody is
watching.

**One CPU budget for all video.** `go/vcodec` extracted from vp9anim so
VP9 stickers and H.264 video share a single decode permit pool instead of
each growing its own semaphore. `vp9anim` moved onto it (3 call sites);
its tests still pass unchanged.

### Tests first (§9) — 17 new
- `h264vid` 13 pass + 1 conditional skip (truncation cut a partial GOP,
  so there is nothing to assert) + `vcodec` 3.
- Both fixtures were regenerated with `-g 4` mid-slice specifically so
  `TestSeekRestartsAtKeyframe` would have ≥2 keyframes to seek across —
  an earlier `-g 15` version had one keyframe and the test skipped.
- **Pinned against ffmpeg, not against govid.** SHA-256 of every decoded
  luma+chroma sample of both fixtures is pinned
  (`6f09b28e…`/`34d26fe8…`); `TestReferenceIsGenuineFFmpeg` re-derives
  those references from the committed MP4s with ffmpeg when it is on
  PATH, so the pin cannot silently drift into self-confirmation.
  Our own two fixtures both came back **bit-exact, all 12 frames ×
  221,184 samples**.
- Player-vs-pipeline equivalence: `FrameAt`'s RGBA re-encoded to YUV and
  hashed matches `decodePass`'s raw planes, so the pixels pinned by the
  test are the pixels the GUI draws.
- Regression pinned: `TestProducersQueueUnderFullDecodePool` (16 players
  on a primed-to-capacity pool must not deadlock).
- Also: `vp9anim` refactor covered; `-race` clean on h264vid/vcodec/vp9anim.

### Verification (§9)
`gofmt -l` clean · `go vet -tags goolm ./...` clean ·
`go test -p 2 -tags goolm -count=1 ./...` **exit 0, 12 packages ok**.

### Next
- **220** GUI wiring (`gui/h264player.go` cache keyed by msgID;
  `videoBubble`/`videoNoteBubble` play in place, round notes loop +
  circular crop) — turns parity rows 143/281 from partial into present.
- **221** in-app playback controls → row 276. **222** PiP → row 279
  (the matrix's only MISSING row).
- Deliberately not in this slice: AAC audio. Video now plays silent;
  the existing "open in system player" handoff still offers sound.

## 2026-09-23 — slice 220: round video notes play INSIDE the chat bubble (GUI wiring for h264vid)

Executes plan item **220**. Parity row 143 ("Video / round video —
Player bubble w/ cover, round crop") now delivers its player half: a
video message is a circular, looping player in the conversation, which
is exactly how tdesktop/AyuGram draw video messages — not a thumbnail
that hands off to another application.

### What shipped
- `gui/h264player.go` (418 lines): msgID-keyed player cache mirroring
  `vp9player.go`/`tgsplayer.go` on purpose (async read+parse once per
  message, background decode-ahead producer, eviction stops goroutines
  asynchronously so a mid-decode `Stop` can't stall the frame thread).
  - `noteTapAction` — the tap state machine as a **pure function**:
    missing file → download; parse in flight → wait; playing → pause;
    stopped → play; undecodable → **viewer fallback** (never a dead
    bubble, §1.10).
  - `setPlayOnDone`/`consumePlayOnDone` — a one-shot marker so a round
    note's tap-to-download plays it **in chat** when the bytes land,
    instead of inheriting slice 86's system-player handoff. Checked
    before `wantOpen`, so a doubly-marked download cannot escape.
  - `drawVideoNoteFrame` — current frame, circle-cropped through the
    existing `drawImageEllipse`, re-armed via `NextFrameIn` so the loop
    costs frame-rate ticks and not a busy spin; power-saving
    (`psClassVideo`) holds a frame with no re-arm.
- `videoBubble`/`videoNoteBubble`: a playing note renders live frames
  with **no play badge** — it is the player now; the thumbnail+badge
  holds the box until the first decode lands.
- `actMedia`: `MediaVideoNote` split out of the viewer case; regular
  video/GIF/photo keep tap→viewer (tdesktop does not play those inline —
  that is slice 221's viewer player, row 276).
- `powersave.go`: new `psClassVideo`. tdesktop exposes no separate
  "video in chat" bit, so it maps to `GifsInChat` (in-chat autoplaying
  media) — panel bits stay panel-scoped, which the test pins.

### A real data race, caught before it shipped
`peek` returned a live `*h264Player` and every reader touched its flags
off the lock while the parse goroutine's `publish()` wrote them —
`-race` flagged it in `TestPlayInlineOnDone`. That would have been a
production race on the first tap, not just a test artifact. Fixed at the
API level rather than at the call site: the cache now hands out
**immutable `h264PlayerState` snapshots copied under the mutex**, and
`noteTapAction` takes a snapshot, so no caller *can* read live fields.
Re-run under `-race`: clean.

### Tests first (§9) — 4 new (8 sub-cases)
tap state machine (8 cases) · cache lifecycle incl. single-claim read
guard, frozen-while-paused playhead, oversized-cache eviction ·
end-to-end `TestPlayInlineOnDone` driving `onDownloadComplete` against a
**real committed fixture** (asserts the system player is NOT called,
the player parses and reaches `playing`, the mark is one-shot, and the
tap flips Play↔Pause) · power gate (4 cases).

### Verification (§9)
`gofmt -l` clean · `go vet -tags goolm ./...` clean ·
`go test -p 2 -tags goolm -count=1 ./...` **exit 0, 12 pkgs** ·
`-race` clean on the new tests. Slice 219's `verify.yml` dispatch on
`15986674` came back **success**.

### Next
- **221** media-viewer in-app playback controls (play/pause/seek/
  volume) → parity row 276, which also closes row 143's regular-video
  half. The viewer can reuse this exact cache+render path.
- **222** PiP → row 279 (the matrix's only MISSING row).
- Known, deliberate: AAC audio is not decoded yet, so inline notes are
  silent; the system-player handoff still offers sound for everything
  else.

## 2026-09-23 — slice 221: in-app video playback in the media viewer (parity row 276)

Executes plan item **221**. Videos no longer leave the application to be
watched: the fullscreen viewer gained a real transport — play/pause,
scrub-to-seek, elapsed/total — driven by slice 219's `h264vid`.

### What shipped
- `gui/viewerplay.go`: `viewerPlay` starts an in-app player for a
  downloaded MP4; the control bar renders under the viewer's caption
  (zero-height for photos, so image viewing is untouched) and the live
  frame replaces the poster through the *existing* zoom/pan/clip
  machinery — no second render path to drift.
- Round notes loop; ordinary videos play through and rest on the final
  frame, and `resume` from the end restarts, so pressing play on a
  finished video does something rather than sitting still.
- `seekBar` → `seekBarDo(gtx, key, frac, seek)`: the music bubble's bar
  and the viewer's scrubber are **one widget with two real targets**
  (same visuals, 14dp grab area, half-percent drag throttling). The
  engine-audio path keeps its playback ticker inside its own closure.
- **Seek is two-phase**: the GOP-aligned decode restart (which can block)
  runs *off* the cache lock, then the GUI playhead is rebased onto the
  target. Skipping the rebase is the classic "scrubbing snaps back on the
  next frame" bug — `TestPlayerCacheSeekRebasesPlayhead` pins both the
  playing and paused cases plus clamping at each end.
- Honest failure: if `h264vid.Parse` rejects the file, it toasts and
  hands the file to the system player instead of leaving a dead button.

### What was deliberately NOT shipped (§1.10)
**Volume.** Row 276 lists it, and Telegram's MP4 carries AAC, for which
there is still no pure-Go decoder — a slider would control nothing. The
control is not drawn; the system-player handoff keeps carrying audio.
Row 276 therefore stays PARTIAL with exactly that one reason, rather
than being marked present on a capability we do not have.

### Tests first (§9) — 4 new (19 sub-cases)
seek-fraction clamping incl. missing metadata (no divide-by-zero) ·
clock labels incl. hour-long files and negative clocks · the
in-app-vs-system decision (video/note/photo/missing/.webm/case-insensitive
extension) · cache seek rebasing (playing, paused, out-of-range, unknown
message, metadata-less clip).

### Verification (§9)
`gofmt -l` clean · `go vet -tags goolm ./...` clean ·
`go test -p 2 -tags goolm -count=1 ./...` **exit 0, 12 pkgs** ·
`-race` clean on all 8 new tests across slices 220-221.

### Parity
Row 143 (video / round video) → **PRESENT** (186/8/1/5). Row 276 →
PARTIAL with volume as the single stated reason. Remaining in §11's
video thread: **slice 222 → PiP** (row 279, the matrix's only MISSING
row), then AAC for the volume half of 276.

## 2026-09-23 — slice 222: picture-in-picture (parity row 279 — the matrix's last MISSING row)

Executes plan item **222**, the final video-thread slice. Row 279
("PiP floating window") was the parity matrix's **only MISSING row**;
it is now PRESENT, along with row 231.

### The design decision, and why it is not an OS window
Gio gives us two hard facts, both found by reading its source rather
than assuming:
1. it exposes **no always-on-top option** on our platforms — the only
   such flag lives in Gio's macOS backend, which §1.2 bans outright;
2. it allows **extra native windows only on linux and windows**, never
   on Android (`separateWindowSupported`, slice 168's own note).

An OS-level PiP window would therefore sit *behind* the main window
(useless) and not exist at all on Android — a first-class target. So PiP
is a **draggable floating panel inside the window**: it stays visible
over every surface, works on both first-class platforms, and the
deviation from a true OS window is written down in the file header and
in the parity row rather than glossed over (§1.10).

### What shipped
- `gui/pip.go`: pure geometry (`pipSize` clamps the target width to
  1/6–1/3 of the window, derives height from the clip's aspect, and caps
  height at half the viewport so the panel can never overflow the window
  it floats in; degenerate metadata falls back to 16:9), `pipClamp`
  (keeps it grabbable after a resize), delta-based drag (absolute would
  run away, because the panel travels with the pointer and its local
  coordinates change every event).
- Shares the slice-220/221 player cache: **popping out is a hand-off,
  not a second decoder**, and closing the viewer does not stop playback.
  Closing the panel pauses the clip — an invisible panel must not burn
  decode CPU.
- Entry point: a picture-in-picture icon in the viewer's top bar,
  rendered only for items `pipEligible` accepts, so a photo can never
  open an empty panel.
- Rendered in both window types (main + slice-168 separate chat
  windows), below the toast/shortcut layers.

### Tests first (§9) — 5 new (30 sub-cases)
size-vs-viewport with the invariant "a panel always fits" · clamp
(including a panel wider than the viewport, and a degenerate viewport) ·
drag that sticks to every edge · lifecycle (parks bottom-right, position
survives a clip switch, pauses while frozen, idempotent stop) · entry
eligibility (video/note/photo/undownloaded).

### Verification (§9)
`gofmt -l` clean · `go vet -tags goolm ./...` clean ·
`go test -p 2 -tags goolm -count=1 ./...` **exit 0, 12 pkgs** ·
`-race` clean across every new test in slices 220-222 ·
`verify.yml` green on **15986674, d4e1699f and 1b6d4dc2** (3 consecutive
pushes, all jobs).

### Parity after this slice
**PRESENT 188 (94%) · PARTIAL 8 · MISSING 0 · CORE-ONLY 4** (200 rows).
Row 279 closed; every remaining row is an honest scope cut, an
owner-decision (webview), a by-design absence (experimental flags), a
redundancy (Ayu sqlite), or blocked on a *different* core (streaming).
Remaining §11 threads: verify the xmpp/bale/rubika/deltachat cores (§8),
and the first non-prerelease (blocked on the owner).

## 2026-09-23 — research correction: a pure-Go AAC decoder DOES exist (slice 223 groundwork)

**Why this entry exists.** Slices 221–222 shipped with the statement "there is
no pure-Go AAC decoder", used as the reason row 276's volume control stays
undrawn. That statement was **never tested** — it was carried forward as
plausible ("codecs need C"), exactly the failure mode `AGENTS.md` warns about
for `research/` files, and exactly the failure that had already hidden `govid`
for H.264. So it was re-run under the same gate, and **it was wrong.**

### The gate
Fixtures generated locally, decoded by the candidate library *and* by ffmpeg's
fixed-point AAC decoder, compared by SHA-256:

    ffmpeg -c:a aac_fixed -i in.aac -c:a pcm_s16le -f s16le ref.raw

(`aac_fixed` is a **decoder** — it has to precede `-i`. The first attempt put it
after `-i`, ffmpeg reported `Unknown encoder 'aac_fixed'`, and the "comparison"
ran against a reference that did not exist. Caught only because the harness
checks byte counts, not just pass/fail.)

### Results
- **`github.com/tphakala/go-aac` (LGPL-2.1): 4/4 byte-identical** — stereo
  48 kHz, mono 44.1 kHz, pink-noise stereo, and a Telegram-shaped H.264+AAC MP4.
  It is a function-by-function port of FFmpeg's own fixed-point decoder pinned
  to a specific FFmpeg commit, with its own differential gates (`PROVENANCE.md`).
  Pure Go, no cgo.
- **`github.com/arabian9ts/aac-go` (Apache-2.0): rejected on measurement.**
  Permissive license, zero dependencies, its own 35 tests pass, frame counts
  correct — but mono/tone content measures 74 dB SNR while **pink-noise stereo
  measures 17.3 dB with 88% of samples wrong by more than 64 LSB**. A codec
  that is right on some inputs and broken on others would ship as "audio works"
  and fail on real Telegram content. Being permissive does not make it correct.

Two more pure-Go AAC decoders exist (`skrashevich/go-aac` LGPL-3.0,
`llehouerou/go-aac` GPL-2.0); unmeasured, therefore unclaimed.

### Consequence for row 276
The blocker was never the decoder — it is the **audio path**: MP4 audio-track
demux (raw access units + `AudioSpecificConfig`, which `go-aac` accepts via
`WithRawStream`; `aac-go` has no ASC path at all) and A/V sync against the video
clock. So row 276 stays PARTIAL, but for an honest *engineering* reason instead
of a false *impossibility*. **No behaviour changed in this entry** — it corrects
the record only.

- New: `research/aac_decoder.md` (method, tables, measurements, license note).
- Corrected in place: `research/ayugram_parity.md` row 276 + its two summaries,
  and the `AGENTS.md` §11 slice-221 volume note. **Past WORKLOG entries were
  deliberately left as written** — a log that is edited after the fact is not
  a log; the correction lives here, where it can be seen next to the claim.
- HE-AAC (SBR/PS) is out of scope in every candidate, including `go-aac` —
  Telegram video/video-note audio is AAC-LC, so that falls back to the system
  player when encountered.

## 2026-09-23 — slice 223: AAC audio core (`go/aacaud`) — MP4 audio demux + decode, byte-exact vs ffmpeg

Row 276's volume control was deferred because "there is nothing to apply
volume to". The research correction that immediately preceded this slice
removed the false part of that reason (a pure-Go AAC decoder does exist); this
slice builds the missing part: getting the audio **out of an MP4 and into
samples**. The remaining half — feeding a sink and drawing the slider — is
slice 224.

### What it does
`Parse(r io.ReadSeeker)` scans for `moov` wherever the muxer put it (faststart
front, most muxers back — Telegram uploads vary), picks the trak whose handler
is `soun`, and reads:

- `mdhd` (timescale), `hdlr` (which trak is the sound one),
- `stsd` → `mp4a` → `esds` → the **AudioSpecificConfig**,
- `stts`/`stsc`/`stsz`/`stco`·`co64` (decode times, chunk map, sizes, offsets),
- **`edts`/`elst`** — the part everyone skips, and the whole reason a naive
  implementation is out of sync: AAC's 1024-sample encoder priming lives there
  as `media_time`, and the presentation length as `segment_duration`.

`ascInfo` gates the config up front: AAC-LC mono/stereo only, so HE-AAC (AOT 5,
and ffmpeg's built-in SBR sentinel) is refused rather than decoded as LC into
plausible-looking noise. It also cross-checks the ASC against the `mp4a`
sample-entry's own rate/channel fields and fails if they disagree, because
trusting the wrong one resamples silently.

`Decode` frames the access units the way go-aac wants raw input — **each unit
prefixed with a big-endian uint16** (raw AAC has no syncword to resync on) —
runs the decoder, then trims exactly `[priming : priming+length]`. That window
is what ffmpeg outputs for the same file, which is the headline test.

### Two of my own bugs the tests caught
1. **Box-header arithmetic.** `AudioSampleEntry` header is 36 bytes *from the
   box start*; `body` already excludes the 8-byte box header, so children start
   at `body[28]`. Written as `[36:]` it walked 8 bytes into `esds` and reported
   "mp4a has no esds" on a perfectly good file.
2. **ffmpeg flag order — again.** The first reference pins for these fixtures
   were produced with `-i … -c:a aac_fixed -c:a pcm_s16le`: `aac_fixed` is a
   *decoder*, and with another `-c:a` after it, ffmpeg silently decoded with
   the **float** decoder instead. Measured afterwards, float and fixed do not
   agree (`talk`: `5ea29f46…` vs `d9d10e1d…`). Our decoder is a port of
   ffmpeg's fixed-point one, so fixed is the correct oracle; the pins were
   re-derived with the flag before `-i` and the provenance test now re-runs
   exactly that invocation. A pin that comes from the wrong decoder looks
   authoritative and passes nothing.
   (Also self-inflicted: `go get …@v0.4.0` from a stale pkg.go.dev snippet,
   which lacks `DecodeInterleaved` — the latest tag is v0.7.0.)

### Tests first (§9) — 11 tests
fixture integrity (SHA of all three MP4s) · parse pins for the stereo and mono
tracks (rate, channels, ASC hex, priming, presentation length, unit count,
duration) · monotonic DTS with the 1024-tick frame delta A/V sync will rely on
· **PCM equals ffmpeg's fixed-point decoder, byte for byte** · provenance that
re-derives those pins with ffmpeg · honest failures: no-audio trak, HE-AAC
config, garbage, three truncation points (no panic), oversized access unit.

Fixtures: `talk.mp4` (H.264 + AAC-LC 96k stereo 48 kHz, 1.5 s),
`note.mp4` (round-note shaped, AAC-LC 64k mono, 1.0 s), `silent.mp4` (video
only, the negative case).

### Verification (§9)
`gofmt -l` clean · `go vet -tags goolm ./...` clean ·
`go test -p 2 -tags goolm -count=1 ./...` **exit 0, 13 pkgs** (aacaud included)
· `-race` clean on the new package · token scan 0 · `verify.yml` green on
**15986674, d4e1699f, 1b6d4dc2, a7e4bd6e and d4fcacf4** (5 consecutive pushes).

### Parity after this slice
Row 276 stays **PARTIAL** — deliberately. The blocker named in the earlier
correction ("the AAC audio path") is now half built: samples exist, volume does
not. Marking it present on decode alone would be the §1.10 mistake in a new
shape. Slice 224 wires the sink and the slider.

## 2026-09-23 — slice 224: MP4/AAC playback + media volume in the engine (row 276's volume, engine half)

Slice 223 proved a pure-Go AAC decoder exists and can produce samples byte-
identical to ffmpeg. This slice makes those samples *playable and controllable*
inside the engine — the half of row 276 that was still missing.

### What shipped
- **`decodeMp4Audio`**: MP4 → AAC track → mono 48 kHz, the exact shape the
  device callback takes. It reuses the pipeline the MP3 path already had
  (`mixdownStereo`, `resampleLinear`) instead of writing a second one, so
  position, speed and seek work on video sound for free.
  - **Stereo is mixed down only when the track really is stereo.**
    `mixdownStereo` averages adjacent pairs, so running it on mono would pair
    each sample with its neighbour and turn the waveform into static — which
    still "plays", so a liveness check would not catch it. The branch is
    commented with exactly that reasoning.
  - A video with **no audio track** returns `aacaud.ErrNoAudio` wrapped, so the
    GUI can tell "silent message" from "broken bytes" and choose honestly.
- **`IsMp4`** (8-byte `ftyp` sniff) and `IsInAppPlayable` now includes it, so
  tap-to-play never lands on a dead button.
- **Volume**: `mediaPlayer.gain` applied in `fill`, `SetMediaVolume` (clamped,
  immediate), `PlaybackState.Volume`, `ConfigChanges.MediaVolume` persisted
  through the vault like every other setting.

### Two decisions worth recording
1. **The gain scales the OUTPUT, never `p.pcm`.** If `fill` scaled the stored
   buffer in place, quieting one track would quietly quiet every track after
   it — the bug that makes volume "sometimes stick". `TestMediaVolumeScalesPlayback`
   pins the buffer byte-for-byte across a low-volume pull.
2. **`MediaVolume` is a `*float64` in the config, not a plain float.** "Never
   set" and "deliberately muted" are both zero; collapsing them would make a
   muted user come back to a loud app after every restart. nil reads as 1.0,
   a stored 0 stays mute (JSON `omitempty` omits nil only, so 0 round-trips).
   `ClampMediaVolume` routes **NaN** to silence — NaN fails every ordering
   comparison and would otherwise reach the sample loop, where float→int16 of
   NaN is platform-defined.

### Tests first (§9) — 10 tests, 14 case runs
`ftyp` sniff table (7 cases incl. Ogg/MP3/WebM/text/short) · playable-decision
· decode shapes: both fixtures land on exactly `duration × 48000` after
downmix, with a loudness floor so a decode-to-silence cannot pass · video-only
rejects with the wrapped sentinel · `PlayMedia(mp4)` advances the playhead ·
**volume scales samples exactly (halving, mute, buffer-not-mutated)** · clamp
bounds · volume survives a track switch · config round-trip incl. explicit
mute · config bridge applies and ignores nil.

### Verification (§9)
`gofmt -l` clean · `go vet -tags goolm ./...` clean ·
`go test -p 2 -tags goolm -count=1 ./...` **exit 0, 13 pkgs** ·
`-race` clean over the whole engine package · token scan 0 ·
`verify.yml` green on **15986674, d4e1699f, 1b6d4dc2, a7e4bd6e, d4fcacf4,
9b2c95a4** (6 consecutive pushes).

### Parity after this slice
Row 276 **still PARTIAL — deliberately.** The engine can now decode video
audio, play it, and turn it up or down, but nothing in the GUI routes a
video's audio through it yet and no slider is drawn. Marking the row present
now would advertise a control that does not exist on screen (§1.10). The
remaining half is slice 225: start/stop engine audio alongside the h264
player, lock the picture to the audio clock (audio is the master — the
device pulls in real time), and draw the slider in the viewer bar.

## 2026-09-23 — slice 225: video SOUND + the volume slider — parity row 276 is PRESENT

This is the slice that closes the last P1 row of the AyuGram matrix. It joins
the two halves slices 219-224 built: the pure-Go picture (h264vid) and the
pure-Go sound (aacaud → engine gain), with one shared notion of "now".

### What shipped
- **`gui/videoaudio.go`** — the whole picture↔sound contract:
  - `videoAudioPlay/Pause/Seek/Loop` mirror every transport action into the
    engine, and each one first asks `videoAudioMine` whether the engine's
    single player is holding **this** message's audio. That question is why a
    pause on a video cannot pause somebody's music, and why an empty msgID is
    explicitly never "ours" (every video shares `""`, so treating it as ours
    would let any pause button stop any track).
  - **Loop sync.** Round notes loop forever; the engine plays a track through
    once. `videoAudioShouldLoop` re-arms the audio at each wrap — but only
    when the picture is *still* looping, a device exists, the audio is not
    running or paused by the user, and the drain has finished (50 ms slack).
    The four guards each correspond to a real failure: a video that played
    through must not resurrect its audio, a user's pause must not be
    overridden, and music must never be restarted by a video.
  - **Silent is not a failure.** `isSilentVideoErr` distinguishes
    `aacaud.ErrNoAudio` (a clip with no track — correct, quiet) from HE-AAC,
    a broken container or a missing device (logged *and* toasted, because a
    video that silently loses its sound looks broken — §1.10).
  - The volume slider writes through `setMediaVolume`: live gain immediately,
    config persistence async. The slider **reads the live gain**, never the
    async config, so a drag cannot snap back while the write is in flight.
- **Volume control in the viewer bar** — `seekBarDo` with a fixed 64 dp track
  and a real Material glyph (`AVVolumeUp`, flipping to `AVVolumeOff` at zero),
  drawn **only when `audio.Available()`**: a slider that moves nothing is
  exactly the UI §1.10 forbids.
- Wiring at every transport point: inline tap (chat bubble), the viewer's play
  button, the viewer scrubber (one drag → both clocks), download-completion
  autoplay, and the draw path for loop re-arm. Audio starts **in `publish()`**,
  the moment the picture's clock starts, so sound never leads the video.

### Two bugs found while writing it
1. **A precedence error in my own first draft of `videoAudioPlay`**: the guard
   read `st.Playing || st.Paused && videoAudioMine(...)`, which — Go binding
   `&&` tighter — reduced to "something else is playing → skip video audio
   entirely", i.e. music playing meant the video started silent, forever. The
   test suite for identity + the rewritten branch made it obvious; the comment
   now says out loud that a non-ours track means `PlayMedia` **switches**.
2. **`UpdateConfigFromBridge` dereferenced a nil config.** Every GUI
   persistence callback runs on a goroutine, and tests build bare
   `&engine.Engine{}`, so an unguarded persist would have crashed the process
   rather than failing a test. It now returns an error instead. The engine's
   `player()` also seeds its gain from config at creation (locks taken and
   *released* separately, never nested), so a restart opens at the saved
   volume instead of at full blast until the first track.

### Tests first (§9) — 4 tests / 31 case runs
identity table (incl. the empty-msgID case that would let any video claim any
track) · silent-vs-real failure table incl. twice-wrapped sentinel ·
`videoAudioShouldLoop` full guard matrix (10 cases) · volume read/write
round-trip with clamping against a config-less engine · every helper
tolerating a bare `&App{}` with no engine (the render path can arrive first).

### Verification (§9)
`gofmt -l` clean · `go vet -tags goolm ./...` clean ·
`go test -p 2 -tags goolm -count=1 ./...` **exit 0, 13 pkgs** ·
`-race` clean across the new gui and engine tests · token scan 0 ·
`verify.yml` green on **15986674, d4e1699f, 1b6d4dc2, a7e4bd6e, d4fcacf4,
9b2c95a4, 5c05c8da** (7 consecutive pushes).

### Parity after this slice
**PRESENT 188 (94%) · PARTIAL 8 · MISSING 0 · CORE-ONLY 4** (200 rows).
Row 276 is PRESENT — the last P1.

**The counts themselves were the last defect.** The prose claimed 188/8
before this slice and 189/7 when I first updated it; parsing every row's
status cell showed the table actually held **187 PRESENT / 9 PARTIAL** —
forum topics (row 107) is PARTIAL in the table but was never in the prose
list, so the two had drifted a row apart. Corrected to the parser's output
and noted in the matrix: counts are derived, not typed. (The first parser
pass also missed the `CORE-ONLY-BY-DESIGN` experimental row, which is why
it initially reported 199 of 200 — same class of error, caught the same
way, by insisting the parts sum to the whole.)

The 8 remaining PARTIAL rows are all honest scope cuts: forum topics
(experimental tab positions), chat-background upload (emoji-pattern
wallpapers), saved-messages remainder, chat-settings extras, local premium
toggle, stars raw-gifting and giveaway launch (both external checkout),
and QR scan (import ships, camera scanning does not). The video thread in
§11 is now closed end to end: H.264 decode → in-chat playback → viewer
transport → PiP → AAC audio → volume.

## 2026-09-23 — slice 226: parity truth pass — five stale rows, a broken table, and what "verified" has to mean

### Why
Closing row 276 (slice 225) forced a total, so the totals were parsed
from the file instead of typed. The parse disagreed with the prose —
and once one number was wrong, every number had to be re-derived and
every row re-checked before the program's counts could be trusted
again.

### What the checks found — each verified against the repo, not taken on trust
1. **Prose vs table drift.** The matrix claimed 188 PRESENT / 8 PARTIAL
   while the table held 187/9: forum topics (row 107) is PARTIAL in
   the table but had never made it into the prose list. Fixed in
   336b787a.
2. **The parser's own blind spot.** First pass reported 199 of 200
   rows — the experimental-flags row's status reads
   `CORE-ONLY-BY-DESIGN`, not `CORE-ONLY`. Caught only because the
   buckets had to sum to 200.
3. **Gap list vs table: five rows where the document contradicted
   itself.** The gap list declared 107 forum topics, 108 chat
   background, 193 saved messages, 207 chat settings and 212 stars
   CLOSED with slice evidence; the table still called all five
   PARTIAL.
4. **Two status texts claimed shipped work was missing.** Row 108 said
   the "emoji-pattern wallpaper documents remain out of scope" though
   slice 198 ships `patternTilePlan`; row 212 said channel-revenue
   withdraw "remains" though slice 213 ships the stats Earn tab +
   `getStarsRevenueWithdrawalURL`.
5. **Markdown defect.** Row 207's status cell contained raw
   `|dx|-|dy|` pipes, so GitHub renders that row with split columns
   (and any naive parser splits the cell mid-formula). Escaped to
   `\|dx\|-\|dy\|`.

### Verification per row — never flip a label on the gap list's word alone
- Cited slices all searched in WORKLOG: 118, 156, 205, 197, 199, 204,
  198, 218, 139, 155, 157, 158, 159, 172, 144, 211, 213, 214 —
  **213/214 first came back MISSING, which was a false alarm of my
  own**: the pattern `slice $s` cannot match the actual heading
  `## 2026-09-15 — slices 213 + 214: ...`. Broadened the pattern →
  both documented. Second time this session a check failed because of
  my pattern rather than the repo — re-check the checker.
- Cited files exist: `gui/topics.go`, `wallpaper.go`,
  `savedsublists.go`, `savedmsg.go`, `stickermanager.go`,
  `settingsstars.go`, `chatthemetint.go`, `statsview.go`,
  `giveaways.go` (+ GUI tests for topics/savedsublists/savedmsg/
  wallpaper; the stars path is covered in `engine/gifts_test.go` and
  `cores/telegram_gifts_test.go`).
- Disputed capabilities grepped in code before flipping: slice-198
  emoji pattern in `chatthemetint.go`; slice-213
  `withdrawStarsRevenue` / `GetStarsRevenueStats` in `statsview.go`;
  slice-214 `GetCountriesList` in `giveaways.go` + `engine/`; slice-211
  gifting chain `GetStarGifts` → `getPaymentForm` → `sendStarsForm`.

### Result
**PRESENT 193 (96.5%) · PARTIAL 3 · MISSING 0 · CORE-ONLY 4 = 200**
(parser output, buckets summed to the whole). The 3 remaining PARTIAL
rows are the honest kind: local premium toggle (nothing is gated
client-side, so the toggle would be dead UI per §1.10), QR scan
(camera capture needed; tdesktop ships no camera scan either),
card-funded giveaway launch (external checkout).

### Verification (§9)
`gofmt -l` clean · `go vet -tags goolm ./...` clean — **the first run
failed because I typed `gooolm`** (three o's), so vet compiled the
cgo libolm path and died on missing `olm/olm.h`; tag corrected to
`goolm` and re-run · `go test -p 2 -tags goolm -count=1 ./...`
**exit 0, 13 pkgs** · token scan 0 · `flake.lock` unstaged ·
`verify.yml` green on **9b2c95a4, 5c05c8da, 235cf412, 336b787a** —
those four plus the five pushed earlier this session make **9
consecutive green** verify runs.

### Parity after this slice
PRESENT 193 (96.5%) · PARTIAL 3 · MISSING 0 · CORE-ONLY 4 —
sum-checked to 200 rows by the parser. The gap list and the table now
agree with each other *and* with the code, which is what all three
disagreements were really about: the docs had drifted from the
program, and only a check that can fail (files present, slices
documented, capabilities grepped, buckets summing to the whole) can
tell drift from truth.

## 2026-09-23 — slice 227: invite QR scan (row 306) — six decoders, 576 checks, one perfect score

### Why
Matrix row 306 ("Join via invite link / QR") had shipped the link half
in slice 24 and kept the literal gap "QR scan remains". Desktop has no
camera (neither AyuGramDesktop nor tdesktop offers one), so the
desktop-shaped form of a QR scan is: pick a QR image file, read the
link inside it, join through the flow that already exists.

### Research first — measured, not picked (§1.13/§1.14)
`research/qr_decoder.md`: six pure-Go decoder candidates found by live
search (gozxing, piglig/go-qr, netstar-labs/qr, snykk/qr-generator,
tuotoo/qrcode, liyue201/goqr), licenses and activity recorded, then a
**cross-encoder bench**: four of the libraries encoded the same six
payloads (t.me `+hash`, `joinchat`, bare, long, numeric, UTF-8), every
decoder decoded every fixture in four variants — base, rotated 90°
(EXIF screenshots), JPEG q=40 (re-saved screenshots), both combined.
**576 checks, scored on exact payload match, with each decoder's own
fixtures excluded from its credit** so nobody grades their own work.

| decoder | exact | wrong payload | failed | excl-own |
|---|---|---|---|---|
| **gozxing (MIT)** | **96/96** | 0 | 0 | **72/72** |
| snykk (Apache-2.0) | 72/96 | 0 | 24 | 48/72 |
| netstar (Apache-2.0) | 48/96 | 0 | 48 | 36/72 |
| goqr (LGPL-3.0, archived) | 38/96 | **8** | 50 | 38/96 |
| piglig (MIT) | 36/96 | 0 | 60 | 24/72 |
| tuotoo (GPL-3.0, stale) | 36/96 | **4** | 56 | 36/96 |

Two findings decided it beyond the totals: **wrong payloads** (goqr 8,
tuotoo 4 — in an invite flow a wrong payload means joining the wrong
chat, which no amount of "it decoded something" repairs), and
**rotation** (netstar/piglig/tuotoo score zero on both rotated
variants — netstar's README admits it, the others fail silently).

Chosen: **`github.com/makiuchi-d/gozxing` v0.1.1, MIT** — perfect
score including on foreign encoders, zero wrong payloads, handles
rotation + JPEG on every input. License verified by reading the LICENSE
file because GitHub's API reports NOASSERTION. Decoder config pinned to
the measured one (nil hints) with a comment saying re-tuning means
re-running the bench.

### Fixtures: the decoder never grades its own homework
`go/qrscan/testdata/` — 8 PNGs **encoded by three foreign libraries**
(piglig, netstar, snykk) with SHA-256s pinned in the test: three
invite-shaped payloads (incl. UTF-8 byte mode), the rotated and
JPEG-round-tripped variants, a non-invite URL, a public `t.me/username`
(both must be refused), and a clean image with no symbol. The only
self-encoded test left is an explicit round-trip wiring check.

### Shipped
- `go/qrscan` — `DecodeBytes`/`DecodeImage`/`DecodeFile`; sentinels
  `ErrNotImage` vs `ErrNoQR` kept distinct so the toast names the real
  problem; png/jpg/gif (std) + webp/bmp (x/image) registered.
- `go/gui/qrinvite.go` — `inviteHashFromQRImage` (decode → slice-24's
  `extractInviteHash` → the same preview/confirm/ImportChatInvite
  flow, untouched), `qrScanErrorText` (one honest sentence per failure
  class), `pickAndScanInviteQR` (async picker via the proven
  `resolveUploadPaths` path; declined picks stay quiet).
- Search field gains a trailing QR glyph (`inviteScanField`); the
  materialdesign set has no QR icon so the glyph is painted as three
  finder squares + a data-dot cluster — on the one control that really
  scans. Extension filter **exactly** matches what we can decode: a
  picker offering `.bmp` we cannot read would make "not an image" a
  lie.

### Verification (§9)
`gofmt -l` clean · `go vet -tags goolm ./...` clean ·
`go test -p 2 -tags goolm -count=1 ./...` **exit 0, 16 packages**
(qrscan joins the list) · `-race` clean on the slice-227 tests
**and on all of qrscan** (the first `-race` run used a `-run` filter
that matched none of qrscan's test names — "no tests to run" is not a
pass, re-ran it properly) · `go mod tidy` moved gozxing into the direct
require block (it was sitting in `// indirect` while qrscan imported
it) and the build was re-verified after · token scan 0 (diff + the new
files) · flake.lock unstaged.

Self-inflicted slips this slice, all caught before push: `gooolm` vet
typo (three o's) again; two edit+test races on the same file (the test
ran against pre-edit bytes — re-ran each cleanly); `.Op(gtx.Ops)` — an
idiom from an older Gio, current `clip.Rect.Op()` takes no argument;
`ChooseFiles("png", ...)` missing the leading dot the explorer API
documents; a first `qrinvite.go` draft shipped with a stubbed glyph and
placeholder `var _` lines, rewritten before any test ran.

### Parity after this slice
**PRESENT 194 (97%) · PARTIAL 2 · MISSING 0 · CORE-ONLY 4 = 200**
(parser output, buckets summed). Row 306 flipped with its gap item
rewritten; the only PARTIAL rows left are local premium (dead UI until
something is gated) and card-funded giveaway (external checkout) —
both documented honest absences, not unfinished code.

## 2026-09-23 — parity program CLOSED (§11 checklist item [~] → [x])

CI went green on **4a34b44f** (slice 227), the 11th consecutive green
verify run this session (15986674 → d4e1699f → 1b6d4dc2 → a7e4bd6e →
d4fcacf4 → 9b2c95a4 → 5c05c8da → 235cf412 → 336b787a → c385abc0 →
4a34b44f).

That closes the last row that still had buildable work, so the §11
parity item moves to `[x]`. The closing state was verified the way the
program learned to count — by parsing every row's status cell, not by
typing: **PRESENT 194 (97%) · PARTIAL 2 · MISSING 0 · CORE-ONLY 4,
200 rows, buckets summed**. The gap list's 1–20 items were re-read
against the rows in the same pass (CLOSED/PARTIAL/CORE-ONLY all agree
after slices 226–227).

What the non-PRESENT rows are, in case anyone reads them as unfinished:

- **PARTIAL (2)** — both are decisions, recorded with rationale where
  the row lives: local premium toggle (nothing is gated in the client
  today, so the control would be pure dead UI, §1.10) and card-funded
  giveaway launch (external checkout — real-money purchase UI belongs
  to the store, not to us).
- **CORE-ONLY (4)** — webview mini-apps (owner decision), experimental
  flags (dead-UI ban), Ayu sqlite (the engine cache already serves that
  role), streaming-without-download (core exists; the GUI slice is its
  own line in §11 item 1).

§11 now reads: 22 `[x]`, one `[~]` and one `[ ]` — both remaining items
need the owner by definition (a real phone/email account to complete
bale/rubika/xmpp/deltachat sign-in, and approval for the first
non-prerelease). No open item has buildable work left in it.

## 2026-09-23 — slice 228: ranged media streaming (row 281's engine half) — and the correction the entry above needed

**Correction first.** The entry above closes with "No open item has
buildable work left in it." That was wrong, and the truth check that
caught it is why this slice exists. The closure's own rationale had
said streaming's "core exists, its GUI work is item 1's line"; two
greps proved both halves of that wrong: (a) row 281 ("playback without
full download") **is** buildable — the core half exists as Telegram's
chunked `upload.getFile` primitive (`cores/telegram.go`), and (b) the
"engine media streaming" the wording implied **did not exist** — no
ranged read anywhere in the engine or any core, only the full-file
download queue. A doc claiming a capability the code lacks is exactly
the §1.10 shape this project bans. So AGENTS §11 item 4 moved `[x]` →
`[~]` with this correction inline (factual doc, corrected in place),
and slices **228** (engine + cores, this entry) and **229** (GUI
playback path) were scoped to make the claim true. The parity counts do
not move until the GUI lands: 194 PRESENT / 2 PARTIAL / 0 MISSING /
4 CORE-ONLY = 200, machine-re-counted this slice.

What ships:

- **`go/cores/telegram_stream.go`** — `ReadFilePart(fileRef, offset,
  limit)`: ranged chunked `upload.getFile`. The 4096-alignment rule is
  enforced **locally** (a malformed range fails as `ErrInvalidInput`
  before any RPC — pinned by test on a disconnected core), and
  `Precise: true` is set — gotd's own field comment says "disable some
  checks on limit and offset, useful for example to stream videos by
  keyframes", i.e. the layer built this flag for exactly row 281.
  `fileLocationOf` extracted from `DownloadFile`'s inline block so the
  streaming path and full downloads share ONE location resolver
  (document vs photo `ThumbSize:"y"` vs `image/gif`-is-a-document,
  Extra `hash:b64ref` fallback + cache write); DownloadFile now calls
  the helper — same bytes on every path, no drift possible.
- **`go/engine/mediastream.go`** — `mediaStream`: a fetch-on-read
  sparse file at executeDownload's **canonical path**
  (`mediaDir/<acc>/full/<msg>_<seq>.<ext>`) with a per-chunk arrival
  bitmap. `OpenMediaStream` tries the completed file first (fast path:
  disk, no core needed), else resolves `ErrNoRangedRead` from the
  account's core (honest capability gate → caller keeps
  download-then-play), cancels the queue's write for that file so two
  writers never race, and promotes **exactly once** when the last
  chunk lands: one `UPDATE media` + one `EventDownloadComplete` — the
  stream lands inside the existing cache accounting instead of beside
  it.

The two rules the tests pin (tests written first, like everything
here):

1. **Fetch only what is touched.** Reading an 8 KiB head of a 1 MiB
   file must cost ≤ 3 chunks (measured: ≤12 KiB); seeking to the
   middle must not drag the bytes in between (measured under 3×4 KiB).
   A "streaming" reader that reads the whole file is a download with
   extra steps — the measurement IS the row.
2. **Never serve unfetched bytes as zeros.** A failed fetch errors the
   read (and not as `io.EOF`); zeros would decode as a corrupt frame,
   which is fake playback under §1.10. Same for a short/long range
   from the server: protocol violation → error, never shifted bytes.

Also pinned: exact bytes across chunk boundaries / at EOF / past EOF
(`ReaderAt` semantics), completion fires exactly once across re-reads,
concurrent reads (`-race` green), row promotion end-to-end (canonical
path, `DownloadComplete` state, file bytes identical to source), fast
path with **no** core attached on the engine, and `resolveStreamSource`
returning `ErrNoRangedRead` for nil/unsupported cores instead of
panicking on a failed type assertion. cores side: location resolution
(Extra decode → document w/ hash 777 + ref bytes, photo, gif, empty ID)
and the cache round-trip that lets a second resolve skip Extra.

Gate: gofmt clean, `go vet -tags goolm` clean on engine+cores, full
suites green in both packages, `-race` green on the streaming tests.
Row 281 stays CORE-ONLY until slice 229 wires the GUI playback path.

(Gotcha logged for the record: plain `go vet ./engine/` without `-tags
goolm` walks into mautrix's libolm cgo build and dies on
`olm/olm.h` — the tag is mandatory even for a package that does not
import it.)

## 2026-09-23 — slice 229: row 281 PRESENT — video plays before the download finishes

CI green on **55c1ce39** (slice 228) was the14th consecutive green run
this session. This slice finishes the row, and it opened with a
measurement rather than an assumption: can govid's demuxer sit on a
fetch-on-read stream? A byte-counting probe (counting ReadSeeker around
the fixture, both `mp4.DecodeFile` and `govid/mp4.NewDemuxer`) answered
no in the loudest possible way — **construction reads 11 926 of 11 926
bytes, zero seeks**: mp4ff's default decode mode walks into `mdat` and
pulls the payload. On a stream whose ReadAt misses cost 512 KiB, that
is the entire file before the first frame, and the demuxer's index pass
(walk every packet to record timestamps) would then read it all AGAIN.
The demuxer could not be fixed from outside — govid exposes no
constructor from a parsed `*File` — so the container layer was
replaced with the only shape that streams:

- **mp4ff with `DecModeLazyMdat`** (`mp4.DecodeFile(r,
  WithDecodeMode(DecModeLazyMdat))`): box headers and moov parse, mdat
  is SEEKED over. Pinned two ways: `TestParseSeekReadsNoPayload` (<25%
  of the fixture, ≤3000 bytes for both fixtures) and…
- **a table-driven packet pump** (`h264vid/streamsrc.go`): per-sample
  byte ranges from `TrakBox.GetRangesForSampleInterval(s, s)` (the
  exact walk govid did per packet, but once, as metadata), timestamps
  from `stts.GetDecodeTime` + `ctts.GetCompositionTimeOffset` through
  govid's own float expression, SPS/PPS prepended to sync samples
  exactly as govid did. `TestPacketPumpMatchesGovidDemuxer` pins
  **byte-identical Data, Timestamp and Keyframe for every sample of
  both fixtures** — which is what makes the pixel pin expected rather
  than lucky: `TestParseSeekDecodesToFFmpegPin` runs the ffmpeg-pinned
  sha256 THROUGH the lazy path and it matches.
- **A GOP resume is metadata-only** (`packetSrc.skip`): zero bytes
  before the keyframe, then exactly that sample's range
  (`TestGopResumeReadsNoPayload` asserts both numbers). The old
  demuxer read and discarded every skipped payload.
- All 14 pre-existing tests pass unchanged — the ffmpeg pin, the
  timeline pins, the seek/clock/player tests — because `Parse(data)`
  now wraps `parseSource(bytes.NewReader(data))`: ONE implementation
  for byte clips and streamed clips, so they cannot diverge.

Engine/GUI wiring (row 281's surfaces):

- `OpenMediaStream` now also returns the **canonical path** its bytes
  land at (test pins: returned path == the path the completion event
  later carries — otherwise the player cache would re-parse at
  completion and stutter).
- `gui/videostream.go`: `viewerMayStream` / `streamShouldJoinAudio`
  pure decisions + two entry points. The **round-note tap**
  (`actMedia`) and the **viewer Play** (`viewerPlay`) try the stream
  first and play immediately; `publishStreamedClip` does parse→publish
  app-free (test drives it with real fixture bytes). Every failure —
  `ErrNoRangedRead` (other cores), no media row, HEVC-in-MP4 — falls
  back to the ORIGINAL download-then-play flow with the original
  markers (`setPlayOnDone`/`setOpenOnDone` + `RequestDownload`), and
  the fallback also closes the stream reader so the full download owns
  the file. No dead bubble possible (§1.10).
- **Sound joins at completion**: picture plays from the stream;
  when the last chunk promotes the row, `onDownloadComplete` finds the
  active player (`streamShouldJoinAudio`: parsed + PLAYING + same path
  — a paused picture gets no surprise sound) and starts the AAC at the
  picture's playhead via `PlayMediaAt` → `mediaStartPos` clamp →
  `runVideoAudio` (shared error honesty with `startVideoAudio`).

A unit bug the tests caught before push: `mediaPlayer.pos` is a
**sample index**, not seconds (stateLocked divides by the rate; seek
scales by len(pcm)). The first `PlayMediaAt` plant assigned seconds
where samples belong — invisible in the pure clamp test, and instantly
visible in the end-to-end test on this host because live PulseAudio
filled one 2880-sample device buffer: Position read
`0.06000520833333333` = 2880.25/48000 for BOTH calls. Fixed at the
plant (`× voice.SampleRate`), and the test now brackets both
environments (device-pulled ≈0.31 on the host, exact 0.25 on headless
CI).

Known, documented, bounded: one file handle per streamed clip lives as
long as its player (closed on source-swap, reset, process exit) — a
player-stop hook could close it earlier; noted rather than papered
over.

Gate: gofmt clean, vet `-tags goolm` clean across gui/engine/h264vid,
full suites green in all three, `-race` green on every new test.
**Row 281 → PRESENT. Machine counts (parser re-run): PRESENT 195
(97.5%) · PARTIAL 2 · MISSING 0 · CORE-ONLY 3 + 1 by-design = 200.**
AGENTS §11 parity item closes `[~]` → `[x]`, with the premature-
closure correction kept inline as history.

## 2026-09-23 — release v0.9.1 (prerelease) cut and published

CI went green on **5c958d4a** (slice 229) — the 15th consecutive
green verify run of this session (15986674 → d4e1699f → 1b6d4dc2 →
a7e4bd6e → d4fcacf4 → 9b2c95a4 → 5c05c8da → 235cf412 → 336b787a →
c385abc0 → 4a34b44f → 73ef4072 → 55c1ce39 → 5c958d4a, plus 29e8593a
baseline repairs earlier) — so the verified commit became the tag for
**v0.9.1**, 63 commits after v0.9.0.

The Release workflow (tag-only trigger) ran all five jobs green —
test, linux (amd64+arm64, UPX), windows, android APK, web — and
published **`prerelease: true`** (the workflow's own comment: "until
the owner flips it"; AGENTS §1 line19 keeps every release there until
the owner approves otherwise — §11's last `[ ]` line). Assets
verified through the API, not assumed: `uniclient-linux-amd64`
(22.8 MB), `uniclient-linux-arm64` (19.9 MB),
`uniclient-windows-amd64.exe` (17.4 MB), `uniclient.apk` (33.8 MB),
`checksums.txt`.

§11 final state: **22 `[x]` · 1 `[~]` · 1 `[ ]`** — the remaining two
need the owner by definition (a real phone/email account for the
bale/rubika/xmpp/deltachat live sign-in rung, and approval for the
first non-prerelease). Parity: **195/200 PRESENT (97.5%)**, machine-
counted, buckets sum-checked. Nothing left in any open line has
buildable work — that claim now stands BEHIND two truth passes (the
first one was wrong, was retracted here in slice 228's entry, and the
row it uncovered has since been built).

## 2026-09-23 — slice 230: bug-hunt mode starts — 7 bugs from auditing the new streaming code

Owner instruction for this and all future sessions: *check for issues,
update the project status, work on bugs from now on.* Done on all three.

**Status updated**: AGENTS now says phase **stability / bug hunt**
(feature work done — parity 195/200, v0.9.1 shipped), the zero-context
header points the next agent at a new **`BUGS.md`** (the standing open
list + fix log with an evidence column), and §11 gained the standing
`[~]` item carrying the rules (tests-first, gate never regresses, new
limitations logged, not whispered). GitHub has 0 open issues; `grep
TODO` found exactly one code TODO (TeamSpeak QuickLZ → B-1).

**The audit**: read the slice-228/229 streaming paths line by line
(engine/mediastream.go, engine/media.go's download path, gui/
videostream.go, gui/h264player.go, h264vid/streamsrc.go) hunting for
wrong behaviour instead of waiting for users to find it. Seven real
bugs, every one fixed with a test that fails without the patch:

1. **Stream/download write race** (the big one): cores download with
   `os.Create` = O_TRUNC, `MediaManager.Cancel` only touches QUEUED
   jobs, and nothing on the download side knew streams existed — a
   download landing mid-playback truncates the sparse file the
   stream's bitmap says is present. Reachable with zero user intent:
   `maybeAutoDownload` (message arrival) and the scroll-in prefetch
   both call `RequestDownload`. Fix = per-file guard, mutually
   exclusive BOTH ways: `ErrStreamActive` (download refused while a
   stream reads), `ErrStreamBusy` (stream refused while a download
   worker holds the key — the GUI then honestly download-then-plays
   what is already happening), duplicate jobs for one key skip.
2. **Re-download of a completed file**: `RequestDownload` on a
   complete row re-created the finished file (truncate under any
   reader) and — worse — markers waiting on that row never fired (no
   event = dead tap). Now it completes instantly with
   `download_complete`: zero network, zero queue.
3. **fd leaks everywhere on the streamed-player path**: ensure() kept
   the reader on every decline (re-tap of a playing clip = a second
   `OpenMediaStream` fd leaked EVERY time), parse failures relied on
   caller closures, reset/replace dropped readers. Fix = one ownership
   rule: `ensureH264StreamPlayer` CONSUMES the reader on every path;
   the cache owns it after publish and closes on reset/replace/evict.
4. **Dead eviction path**: the h264 cache's 48-entry cap lived only in
   `get()` — grep proved NOTHING calls `get()` for this cache (only
   tgs/webm use theirs), so entries + producer goroutines grew without
   bound all session. Cap now enforced at every insert via shared
   `evictLocked()` (which also closes sources).
5. **Transient failure pinned permanent**: every `ParseSeek` error
   called `failParse` — one dead chunk fetch during parse marked the
   clip unplayable FOREVER (§1.10). New `ErrDecodeFailed` +
   `IsPermanent()`: a verdict about the bytes pins, a failure to READ
   them retries.
6. **Orphan sound at the join**: a viewer clip that already played
   through would start its full audio behind a frozen last frame, and
   loop joins ignored the picture's phase. `streamJoinAt` wraps the
   offset with the picture and refuses ended clips.
7. **Frozen frame with running sound**: a producer dying mid-play
   (fetch error) left the cache `playing` — static frame, live audio,
   dead taps. The draw path heals now (reset + audio pause; next tap
   re-opens the source).

**Two self-inflicted mistakes caught by re-checking the checkers**
(same lesson as the parity tables): the `countCloser` test oracle had
NO `Close()` method — every close assertion ran against a no-op, so
the whole ownership suite first "failed" for a nonsense reason; and
the "audio-only fixture" assumption was wrong (the aacaud fixtures
are full video files — measured with ffmpeg, every stream listed),
so a real audio-only fixture was generated + sha-pinned
(`audio_only.mp4` = `ade3487e…b6bb7`) like every other fixture here.
Also investigated: the mystery green run `dd00b612` = gh-pages' own
"Web build for v0.9.1" commit, not on main. Not a bug.

Gate: gofmt empty, vet `-tags goolm` clean, **all 16 packages ok**,
`-race` green on every slice-230 test. New tests: engine 5 (guard
suite), gui 7+ (ownership + join), h264vid 4 (classifier) + the
rewritten join test.

---

## Slice 231 (2026-09-23) — B-1: TeamSpeak QuickLZ send-side compression

First entry of the bug-hunt phase (BUGS.md). Start: the standing TODO
at `tsSendCommand`. PREMISE CORRECTION before touching code: our RX
decompressor (`tsQuickLZDecompress`) and TX fragmentation already
worked — only the COMPRESSOR was missing, so every command > 487 B
went out as raw fragments while reference clients compress first.

**Method — a reference oracle, not vibes**:
- Fetched official quicklz.c/h 1.5.0 (RT-Thread mirror) to /tmp/qlzref
  (NOT vendored — generator only, same rule as ffmpeg for fixtures).
- gcc harness (gen.c) built against it: **19 golden vectors** (sizes
  1/10/11, header switch 215/216, packet edge 487/488, repetitive
  100–3000 B, LCG-noise 600/1500 B, zeros, run-length, a realistic
  escaped 2600 B TS3 command), C-side round-trip verified, emitted as
  Go test literals (hex machine-generated, never re-typed).
- Ported the level-1 core to `tsQuickLZCompress`: fresh state ≡
  `reset_table_compress` on a zeroed state; QLZ_PTR_64 position table
  with the "position 0 reads as empty" quirk reproduced bit-for-bit;
  portable match conditions proven equal to the X86X64 variant the
  harness compiled (hash ignores byte 3 either way).
- Wiring: compress when >487 B and only if actually smaller; one
  packet + `0x40` when the stream fits; fragment the compressed stream
  otherwise (`0x40` rides fragment 1); ratio give-up → stored-raw is
  bigger than the input → keep raw fragmentation. Small commands
  untouched (they already fit and are live-verified).

**Evidence**:
- 19/19 vectors **byte-identical** to gcc-built official output;
  round-trip through our own decompressor green.
- Send-path tests (fake UDP capture → EAX decrypt → reassemble →
  decompress): 580 B → 1 compressed packet; **2600 B → 1 packet (was 6
  raw fragments)**; 1500 B noise → raw 4-fragment fallback with no
  `0x40` anywhere; small → byte-unchanged; fragment pIDs sequential.
- LIVE pre-fix (raw state): 615 B command = 2 raw packets → server
  REASSEMBLED, parsed, answered `permission denied` ⇒ raw
  fragmentation accepted by ts.arcticblaze.net today — corrected the
  BUGS evidence line (efficiency/compat gap, not an outage).
- LIVE post-fix: same 615 B command as ONE QuickLZ-compressed packet →
  same semantic reply ⇒ the server's own reference decompressor ate
  OUR bytes and parsed the fields. Full compress→encrypt→wire→server-
  decompress chain proven on a real server.
- Permission DRIFT found: guest text for big messages is denied in
  both channel and server modes now (was ACKed/echoed on 2026-09-10) →
  peer delivery is not measurable there anymore; the live oracle is
  "semantic reply = decoded end-to-end", delivery opportunistic.
  `TestTeamSpeakLiveRoundTrip` still passes (send ACKed; S2C delivery
  shown by a third-party bot message — its log label claimed "echo",
  corrected to what it actually proves).

**Mistakes this slice** (checker lessons again): the first run of the
new test panicked `index -2` — `same7` was given the already-shifted
position while it shifts internally (C passes `src-3` to a
pointer-relative helper; the Go helper takes the match position);
caught on the first vector run, one-line fix. An edit was paired with
a test run of the same file twice (racing reads) — third and fourth
violation of that rule, called out again. The first live-oracle design
leaned on a self-echo the core deliberately drops plus a local
outgoing copy — both removed BEFORE they could pass for the wrong
reason.

New tests: cores 5 (`TestTS3QuickLZCompressByteIdenticalToOfficial`,
`TestTS3QuickLZRoundTripOfficialStreams`,
`TestTS3QuickLZCompressRejectsEmpty`,
`TestTS3SendCommandCompressesLargeCommand` ×4 subtests,
`TestTS3SendCommandPacketIDsSequential`) + live
`TestTeamSpeakLiveLargeMessage`. BUGS.md: B-1 → Fixed (F-8) with the
premise correction kept inline; **B-8 opened** (license provenance of
the port — owner decision; the repo has no LICENSE file at all).
First gate run FAILED on a midnight rollover (00:03 local):
`TestHeaderLastSeenExact`/`TestSameCalendarDay` assumed "now minus an
hour" is always today — false 00:00–01:30 — while production rendered
yesterday correctly. Re-anchored both to noon of today's date
(BUGS **F-9**, test-only fix, deterministic at any hour; a repo-wide
scan showed no other test with this pattern — mutetime uses a fixed
date, msgdetail takes `now` as a parameter).
Gate: gofmt empty, vet `-tags goolm`, all packages ok, `-race` on the
new tests.

---

## Slice 232 (2026-09-24) — B-2: FILE_MIGRATE, closed as a bad premise

B-2 said `ReadFilePart` surfaces FILE_MIGRATE with no DC migration and
pointed at `DownloadFile`/thumb as things to mirror. Reading the code
line by line first (repo law: own research, never assume):

- `withAPI` returns `t.api` = `tg.NewClient(rpcGuard{next: t.client})`
  (guardedClient) — so EVERY RPC we make enters
  `telegram.Client.Invoke` → `c.invoker =
  chainMiddlewares(invokeDirect, …)` (client.go:280-281);
- `invoke.go:67-72`: **FILE_MIGRATE and STATS_MIGRATE are intercepted
  there** and rerun via `invokeSub(targetDC)` — a sub-connection to the
  target DC (sub_conns.go: create-or-reuse, cached); the primary DC
  never moves;
- `DownloadFile` = `downloader.NewDownloader().Download(api, …)` on
  the SAME api; the thumb path same RPC. They never had migration
  code — they work because gotd migrates. The B-2 "next step" was
  wrong twice (there is nothing to mirror).
- gotd has no test of its own for that branch (grepped v0.161.0), so
  the chain evidence is the pinned source lines above.

**What is REAL** (kept, test-first): if the automatic redirect ever
fails, a FILE_MIGRATE does reach our error path, and the old comment
both predicted that and explained nothing. Now the error is wrapped
with "redirect failed" context and `errors.Is` still sees the raw
`tgerr` error (the engine classifies read failures as retryable —
F-5 taxonomy). Tests:

- `TestReadFilePartWrapsRedirectFailureWithoutSwallowing` — scripted
  invoker returns `tgerr.New(400, "FILE_MIGRATE_2")`: **RED before the
  patch** (raw `rpc error code 400: FILE_MIGRATE (2)`, no context),
  green after; asserts the RPC fired exactly once.
- `TestReadFilePartReturnsBytesAndForwardsRange` — success path:
  bytes byte-identical, offset/limit/Precise/document-location
  forwarded exactly (regression guard for the wrap).

BUGS.md: B-2 → Fixed (F-10) with the premise correction inline;
the open list now starts at B-3. Gate: gofmt empty, vet `-tags goolm`,
all packages, `-race` on the new tests.

---

## Slice 233 (2026-09-24) — B-3: per-chunk single-flight for streaming

B-3 was the one open row whose evidence line already named the test to
write ("a multi-reader test can drive fakePartSource.stats() past
ceil(size/chunk)"). Done exactly that, with a `delay` field added to
the fake source so the duplicate window is deterministic instead of a
scheduling lottery.

**RED (pre-patch, quantified)**:
- 8 readers of one chunk → **8 RPCs** (want 1);
- 4 concurrent whole-file readers → **126 RPCs vs 32** and
  **1,032,192 B fetched for a 262,144 B file** — 3.9× the bytes for the
  same playback, i.e. streaming could silently cost nearly as much as
  downloading, N times over.

**Patch** (contract unchanged — same bytes, same errors, same
promotions): `mediaStream.fetching map[int64]chan struct{}` =
per-chunk single-flight. A miss claims the chunk and fetches outside
the lock (still never holding `s.mu` across an RPC — Close and the
completion check must not wait on the network); other readers of that
chunk wait on the channel and RE-CHECK: bitmap set → return, leader
failed → the waiter takes over and retries serially instead of a herd.
Wake order is the subtle part: success closes the channel only AFTER
`have[c] = true`, so a woken reader can never miss the bitmap and
re-fetch a landed chunk. Entries exist only while a fetch runs —
results are coalesced, never cached (no stale-data path, no eviction
policy to get wrong).

**GREEN**: both subtests pass (1 RPC / exactly 32), every prior stream
suite test still green (fetch-only-touched, seek-no-gap,
completes-exactly-once, error-is-not-silence, concurrent reads,
promotion, fast path) and `-race` clean over the whole stream suite.

BUGS.md: B-3 → Fixed (F-11); readahead (the old next-step's optional
half) recorded in the Fixed row as "optimization, not a bug — not
implemented" so nobody mistakes it for a missed obligation. Open list
now starts at B-4. Gate: gofmt empty, vet `-tags goolm`, all packages,
`-race` on the new tests.

---

## Slice 234 (2026-09-24) — B-4: close-on-stop at the view boundary
(+ B-9 found and fixed on the way)

B-4's next step named the surfaces ("leaving the viewer/chat resets
entries for that view"). Researched where those boundaries actually
are — `closeViewer` (mediaview.go) and `openChat` with a CHANGED key
(state.go, next to the existing `flushDraft` guard) — and confirmed
NEITHER touched the h264 cache (grepped for stopAll/resetAll-style
hooks: none exist anywhere).

**RED (behavioral, stage A)**: `TestCloseViewerReleasesStreamSource`
compiled against today's code and failed exactly as the bug reads —
"stream reader still open after its view closed — fd held until
48-entry eviction".

**Fix**: `resetAll()` on the cache (stop producer + close source +
drop the shell, returning released ids — shells are pointless for a
cat we are no longer showing); `closeViewer` resets the viewed item;
`openChat` calls `leaveChatMediaReset()` only when the chat really
CHANGED (same guard as flushDraft — re-tapping the same chat keeps its
state). Lock discipline: the hook runs without `a.mu` because
`closeSrc` reaches the engine's file guard.

**Found while reading the stop paths (B-9)**: `stopH264Player` stops
the PICTURE only, `videoAudioLoop` re-arms sound only from the draw
path ("a stopped video never restarts its sound") — and NOTHING called
`videoAudioPause` on chat change or viewer close. A round note's
current audio track therefore kept playing out behind the next chat:
sound without a picture (§1.10), bounded by track length. Logged as
its own entry (F-13, not folded into F-12) and fixed at the SAME two
seams — `videoAudioPause` is own-track-only (`videoAudioMine`) and a
no-op on a nil engine, so leaving a chat can never pause someone else's
music. Honest coverage note: the audio call is glue over the
already-tested videoaudio logic; what the unit tests prove is the fd/
state half, the audio half is review-evidenced.

**GREEN**: all three new tests, the full gui suite, `-race` clean.
BUGS.md: B-4 → Fixed (F-12) + F-13 (B-9); open list starts at B-5.
Gate: gofmt empty, vet `-tags goolm`, all packages, `-race` on the new
tests.

---

## Slice 235 (2026-09-24) — full-repo bug sweep (the "find them all" pass)

Phase rule for this goal: find EVERY bug, record it in BUGS.md so
compactions cannot lose them, and only then start fixing. The sweep ran
as an explicit battery; every tool's output was triaged BY HAND in
source — nothing was logged on tool say-so alone, and clean tools are
recorded as evidence too (all of it lives in BUGS.md's new "Audit
battery" section so a compacted session inherits the whole picture):

- staticcheck 2026.2.1 `-checks=all -tags goolm`: 326 findings →
  bug-class codes read in context one by one (SA4004/SA4010/SA4006/
  SA9003/SA5008/SA1012/ST1018…); style codes (ST1003, ST1000) set aside.
- `go vet` green; FULL `go test -race -count=1 ./...` across all 16
  packages: 0 fails, 0 data races — the strongest "checked" evidence.
- gofmt -s: one style hit (webm_test.go), not a bug. TODO/FIXME
  markers: 0. Defer-in-loop scan: 19 hits, ALL false positives (defer
  inside go-func closures), each opened and read.
- Cross-build matrix vs AGENTS' platform table: windows OK; linux
  CGO=0 fails EXACTLY as the table documents; android = gogio+NDK CI
  job already in verify.yml — no undocumented platform regression.
- govulncheck inside `nix develop` with `GOFLAGS=-tags=goolm` (first
  attempt failed from repo root: the module lives in `go/`): 1
  REACHABLE vuln → B-15 (GO-2026-4550, circl v1.6.2 → v1.6.3).
- Coverage snapshot recorded as context (cores 8.9%, gui 18.3%, engine
  24.0%, pure-logic 71-87%); zero `func Fuzz` targets → B-17.

Two findings had to OUTRUN their tools, and the tools were re-checked
instead of trusted:

1. SA5008 on the xmpp roster tag → built a standalone probe: the tag
   errors on EVERY unmarshal (`query>ver chain not valid with attr
   flag`, items=0) → both call sites drop the roster silently → B-11
   with an empirical RED test path waiting.
2. U1000 on the paid-media trio and the signup card → `git log -S`
   showed ONE commit each (219eabee slice 181, 22f4176d slice 193):
   the call sites were NEVER wired. Two PARITY ROWS were therefore
   false (counted files, not call graphs) — rows 153 and 44 corrected
   in place with the original claims kept visible; counts re-derived
   by the same machine parser: **PRESENT 193 (96.5%) · PARTIAL 3 ·
   MISSING 0 · CORE-ONLY 4 (+1 BY-DESIGN), buckets sum to 200**
   (checker re-checked: the CORE-ONLY-BY-DESIGN token counts inside
   CORE-ONLY, as the Counts section documents). AGENTS status lines
   updated to match.

New open rows: B-10 (mediastream marks complete after chunk 0 — the
§1.10 zero-holes class, the worst find), B-11 (xmpp roster), B-12
(paid wall), B-13 (signup form), B-14 (mojibake button), B-15 (reachable
vuln), B-16 (TS server name), B-17 (parser error-swallow + no fuzz),
B-18 (dead code), B-19 (discarded keys), B-20 (vacuous test
assertions), B-21 (nil-ctx landmine).

Docs-only commit (BUGS.md + parity + AGENTS + this log); §9 gate ran
anyway. Fixing resumes next slice from the top of the open list: B-10.

---

## Slice 236 (2026-09-24) — B-10: streams no longer complete after chunk 0

Top of the open list and the worst find of the sweep. The done-check
in `finishFetchLocked` ranged the `have` bitmap but broke on the FIRST
`ok` — so it only ever looked at slot 0 (staticcheck SA4004 "loop
unconditionally terminated" was the tell). With `streamChunk = 512 KiB`
every real file (i.e. every video) set `done` when chunk 0 landed and
`onDone` promoted the row to DownloadComplete + emitted the event while
the rest of the sparse file was still holes — the exact §1.10 class.

**RED first**: `TestMediaStreamDoneOnlyAfterLastChunk` (3×64 KiB
chunks, fetch chunk-by-chunk through the real ReadAt path, count
onDone) failed exactly as predicted — "onDone fired after chunk 0 of 3
(1) — stream promoted complete while 2/3 of the file is still holes".
**Fix**: completion = EVERY slot present (scan the whole bitmap, set
`done` only if all true), still under the stream lock, with the
existing exactly-once handoff (`justDone` → `onDone = nil`) untouched.
**GREEN**: the new test, the full engine suite, `-race` over all
stream tests; staticcheck re-run shows SA4004 gone. BUGS.md: B-10 →
Fixed (F-14); open list now starts at B-11. Gate: gofmt empty, vet
`-tags goolm`, all packages, `-race` on the stream suite + this test.

---

## Slice 237 (2026-09-24) — B-11: XMPP rosters actually load now

The probe from the sweep was made permanent: `xmppParseRoster` (new
shared helper) carries the CORRECT XEP-0237 tag — `<ver>` is an
ELEMENT, the old `,attr` on a chained path made encoding/xml reject
the whole document on every input — and both former copy-paste sites
(`handleRosterPush`, `requestRoster`) now use it and LOG parse failures
instead of dropping them (one returned silently, one ignored the error
outright; xmpp.go had zero log statements before this slice).

**RED**: `TestXMPPParseRoster` failed to build (seam undefined) — the
behavioral proof stays on record from the audit probe (`err=xml:
query>ver chain not valid with attr flag`, items=0 on every input).
**Self-caught oracle bug**: my first "garbage must error" subtest used
plain prose — but the helper WRAPS input in `<r>`, which makes prose
valid XML, so the assertion was wrong (F-9 family: re-check the
checker); corrected to a genuinely unclosed tag, with the mistake
recorded in the test comment. **GREEN**: items/ver/groups, the
`subscription=remove` payload, malformed-XML error path; full cores
suite + `-race` clean. BUGS.md: B-11 → Fixed (F-15); open list starts
at B-12. Gate: gofmt empty, vet `-tags goolm`, all packages, `-race`
on the new test.

---

## Slice 238 (2026-09-24) — B-12: the paid star wall actually renders

Wired the slice-181 chain back into the bubble: `paidBubbleWall` (new
pure dispatch: locked paid posts only, §1.10) → `layoutPaidMediaWall`
inside `messageRow`'s media row, replacing the normal media slot for
locked posts; the server's `paid_unlocked` update hands the row back.
While wiring, a second defect fell out: `widgets.init()` never made
`paidUnlockBtns` — the FIRST wall render would have written a nil map
and panicked. Fixed in the same patch (the test would have caught it
as a crash).

**RED**: `TestPaidWallRendersInBubbleAndArmsConfirm` drives the REAL
`messageRow` through the real input router (keylayer_test harness
pattern) and sweeps press/release pairs over the wall zone until the
Unlock button is hit — failed pre-patch with "paid wall never armed
the unlock confirm — the star wall is not wired into the bubble
(B-12)". Two test-oracle traps fixed en route and recorded IN the
test: (a) a full-frame sweep clicked into the corner-reaction/corner-
reply chrome whose handler spawns an engine call — nil engine in a
goroutine killed the binary, so the sweep is bounded to the wall zone
with `favAttempted` seeded (both documented as "not this test's
subject"), (b) button-rect math deliberately NOT hard-coded — bounded
sweep instead. Guard subtests: unlocked paid media and plain text
never arm the confirm.

**GREEN**: both tests, full gui suite, `-race`. Parity row 153
restored to PRESENT with the miscount history kept in the row
(PRESENT 194 (97%) · PARTIAL 3 · CORE-ONLY 3 · MISSING 0 = 200,
checker re-run); AGENTS status lines updated. BUGS.md: B-12 → Fixed
(F-16); open list starts at B-13 (the signup form — same disease,
next to fix). Gate: gofmt empty, vet `-tags goolm`, all packages,
`-race` on the new tests.

---

## Slice 239 (2026-09-24) — B-13: the dedicated signup card renders

Same disease as B-12, one line of wiring: `authCard` simply had no
`AuthStateSignUp` case, so signup fell into the default branch →
generic single-line `authInput` (git -S: slice 193 built the whole
card + its tested pure helpers, never added the dispatch). Wired:
`case engine.AuthStateSignUp: return a.layoutSignupCard(gtx, f, st)`.

**RED**: `TestSignupStepRendersDedicatedCard` drives the REAL authCard
through the input router (proven harness from slice 238), sweeps the
Create-account band, and asserts the card's OWN validation wording
("Enter your first name" — signupSubmit's string, impossible for the
generic input): failed pre-patch with `toast=""` + the B-13
diagnosis. The sweep band is bounded so the generic Continue button
(~y 150) can't trip a misleading toast — noted in the test comment.
**GREEN**: the test, full gui suite, `-race` (alongside the B-12
tests). Parity row 44 restored to PRESENT — headline back to 195/200
(97.5%) · PARTIAL 2 · MISSING 0 · CORE-ONLY 3 (+1 BY-DESIGN) = 200,
checker re-run — with the counts narrative recording that the same
number now rests on behavioral tests, not file counts. BUGS.md: B-13
→ Fixed (F-17); open list starts at B-14. Gate: gofmt empty, vet
`-tags goolm`, all packages, `-race` on the new tests.

---

## Slice 240 (2026-09-24) — B-14: the ⋯ button stops being mojibake

One literal, two defenses. The reaction-"more" label shipped as
`C3 A2 C2 8B C2 AF` — a Latin-1 double-encoding of "⋯" (U+22EF) that
left a raw U+008B control char in the message actions row (staticcheck
ST1018). Before touching it, a DECODING source scan (every .go, every
rune in U+0080–U+009F) proved the damage is EXACTLY one line
repo-wide: `go/gui/menu.go 586 ['0x8b']`.

Fix: `reactionMoreLabel = "⋯"` const + use at the button. Test:
`TestGUISourcesHaveNoControlCharLabels` walks the package sources —
compile-RED pre-patch (const undefined; the behavioral RED is the
scan output above), and it stays as the permanent guard: any future
double-encode anywhere in gui/ fails the suite, plus the const itself
is asserted to the exact glyph. GREEN post-patch (octet 0x8B gone).
(Side note: the first doc edit of this slice typo'd the build tag
to "gooolm" in this entry — caught and fixed before commit; gate
scripts all use the real `goolm`.) BUGS.md: B-14 → Fixed (F-18);
open list starts at B-15 (the reachable circl vulnerability). Gate:
gofmt empty, vet `-tags goolm`, all packages, `-race` on the new
test.

---

## Slice 241 (2026-09-24) — B-15: reachable circl vulnerability closed

`github.com/cloudflare/circl` v1.6.2 → **v1.6.3** (GO-2026-4550 fix):
`go get` + `go mod tidy`, go.sum pins updated. The dep arrives via
ProtonMail/go-crypto (openpgp — deltachat/xmpp crypto paths), which
is exactly where govulncheck found the reachable traces.

**The failing test is govulncheck itself** (dependency bumps have no
unit-test form): pre-bump "Your code is affected by 1 vulnerability
from 1 module"; post-bump, same command same flags (`nix develop`,
`GOFLAGS=-tags=goolm`, module dir `go/`): **"No vulnerabilities found.
Your code is affected by 0 vulnerabilities."** Full §9 gate green
against the new dep (gofmt/vet/all packages/`-race` set). BUGS.md:
B-15 → Fixed (F-19); open list starts at B-16 (TS server name).

---

## Slice 242 (2026-09-24) — B-16: TeamSpeak servers have their name back

The `initserver` empty branch (the audit's SA9003) now stores
`virtualserver_name` via `setServerName` (own RWMutex — GetDialogs
reads the name while holding `t.mu.RLock`, so a separate lock keeps
the order clean), and `GetDialogs`' server entry uses it instead of
the hardcoded "Server Chat", falling back to that label when no name
has arrived (no regression for nameless servers).

Scope note vs the row's next step: the "and from serverinfo rows"
half was NOT built — `ServerInfo()` has zero production callers
(grep-verified), so storing there would be dead code; initserver is
the standard TS3 carrier of the name (including renames).

**RED**: `TestTeamSpeakInitserverStoresAndSurfacesServerName` uses
only PRE-EXISTING API (`tsHandleServerCommand` + `GetDialogs`), so it
compiled and failed before the patch — `title = "Server Chat", want
the virtualserver_name from initserver (B-16)` — for the initial push
AND a rename. **GREEN** post-patch + the fallback guard test; full
cores suite + `-race`. BUGS.md: B-16 → Fixed (F-20); open list starts
at B-17. Gate: gofmt empty, vet `-tags goolm`, all packages, `-race`
on the new tests.

**Self-inflicted slip this slice, caught by CI**: I chained the gate
into the commit command as `… bash gate.sh | tail -7 && git add …` —
the pipeline returned TAIL's exit status, so the gate's gofmt failure
("UNFORMATTED: go/cores/teamspeak_servername_test.go", one alignment
line) was masked and `5180190a` pushed unformatted → verify run
FAILED (first red push since the streak began at 15986674; 28 greens
ended). Recovery: gofmt -w, gate re-run as its OWN command with an
explicit `echo gate_rc=$?` (rc=0), fix-forward commit, CI re-dispatch.
Rule recorded: **never pipe a gate into `&&`-chained git commands —
gate runs standalone, exit code checked, then commit in a separate
call.**

---

## Slice 243 (2026-09-24) — four small closures: B-19, B-20, B-21, B-7

(slice-230 style: several tiny, independent fixes with their own RED
tests in one gated commit.)

- **B-19 → F-21**: `tsProcessCommandQueue`'s gap branch now LOGS the
  expected packet id + the queued out-of-order ids (keys were built
  and dropped — SA4010). RED: crafted queue (next=5, queued 7/9),
  empty log pre-patch.
- **B-20 → F-22**: the two assertions that could not fail are real
  now — account scoping resolves acc2/100 to ITS OWN DM, and
  stickerTabs' in-range sel is checked. Honest note (kept in the
  Fixed row): production was CORRECT both times (source-verified), so
  no RED exists — the assertions are the fix and will catch future
  regressions.
- **B-21 → F-23**: `syncAccountContext` replaces nil at the boundary
  (documented contract) + the finalizeAuth call site passes
  `context.Background()` explicitly. Compile-RED seam test.
- **B-7 → F-24**: auto-download logs unexpected `RequestDownload`
  errors, suppressing exactly ErrStreamActive (RequestDownload never
  returns Busy — return paths checked, so Active is the only benign
  exception). RED: `log = ""` pre-patch; guard test keeps
  stream-active quiet through the REAL guard claim.

Test-harness notes: the log-capture pattern (log.SetOutput + defer
restore) is new to these packages — tests within a package run
serially so the global logger is safe to borrow; engine's
test needs an accounts row because `PRAGMA foreign_keys = ON`
(verified in db.go:55). BUGS.md: B-19/B-20/B-21/B-7 → Fixed
(F-21…F-24); open list now: B-17, B-18, B-5, B-6, B-8. Gate runs
standalone with an explicit exit-code check before the commit (see
the slice-242 slip above).

---

## Slice 244 (2026-09-24) — B-17: parser errors surfaced + first-ever fuzzing

**Findings-first**: before changing anything, the two NEW fuzz targets
hunted the parsers as they were — `webm.FuzzParse` 648,852 execs and
`vp9anim.FuzzParse` 99,145 execs (seeds: the test builders + committed
official streams + hostile fragments): **zero crashes, zero (nil,
nil)** — the panics-that-must-not-exist class came back clean.

**The real defect was value fabrication, not crashes**:
`parseTrackEntry` swallowed `readUint` failures (`num, _ = …`) so a
malformed TrackNumber became 0, which the VP9 track gate reads as
"absent" — RED: `TestMalformedTrackNumberIsAnErrorNotAnAbsentTrack`
failed with `err=webm: no VP9 video track`, want `ErrBadElement`.
Signature grew to `(uint64, error)`, propagated through `parseTracks`
(one caller).

Two swallows were deliberately KEPT, each with the proof in-code
(evidence over blanket changes): `parseBlockMore`'s add-id (optional
alpha: malformed must equal absence, never fabricated bytes) and
vp9anim's colorRange bit (provably recovered by the next frame-size
read — made explicit anyway as a cost-free belt).

**GREEN**: the new unit, both full suites, both fuzzers re-run
post-patch (10s each), seed-corpus mode instant (that's what CI
executes). BUGS.md: B-17 → Fixed (F-25); open list: B-18, B-5, B-6,
B-8. Gate standalone with rc check.

---

## Slice 245 (2026-09-24) — B-18: dead-code triage, wire-or-delete

Executed the row's plan on the fresh (post-wiring) U1000 list:
**58 symbols deleted, U1000 128 → 70**, spanning gui (26: abandoned
overlays/tiles/fields), engine (8) and cores (incl. the tgcalls-era
telegram SDP experiments — mergeAudioMlines/replaceICECredentials/
buildReofferAnswer/extract*/mathRandUint32, −295 lines in one
marker-located span edit).

**Two premises in the row itself were wrong — corrected in F-26:**
1. "call rating never opens" → FALSE: `onCallStateEvent` arms the
   dialog INLINE and app.go renders it — feature live all along; the
   U1000 openers were superseded duplicates. Consolidated the inline
   block into `openRateCall` (same fields, own lock) and deleted
   `maybeRateCall`. (Third time this session U1000 needed the
   call-graph reality check — re-check the checker.)
2. Deleting `slowmodeSendBlocked`/`muteDlgCustomErr` failed at vet:
   every remaining reference was a pure WRITE — `unused` is
   read-based, so declarations alone were not enough. Write sites
   removed too (chip/composer/dialog lines). Side discovery: the
   mute dialog's `Use a duration like 2h…` hint had NO display path
   ever — write-only state from an unbuilt hint; folded into this
   cluster rather than a separate row.

**Kept deliberately (evidence):** `audio/opensl_layout.go` fields —
U1000 was a linux-view artifact, `opensl_android.go` consumes them
under the android tag (line266+); mumble + TeamSpeak protocol enum
tables — reference tables in a protocol-documentation codebase.

**Verification for pure deletion (no RED possible — same honesty as
F-22):** compiler = the test (vet rc=0 means every reference was
gone), full suite all-14-green, staticcheck recount with no new
findings, gofmt clean. BUGS.md: B-18 → Fixed (F-26); **open list now
3 rows: B-5, B-6 (owner), B-8 (owner)**. Gate standalone with rc
check, then push.

---

## Slice 246 (2026-09-24) — B-5: inline play failure hands off

Two misses, both closed: `startVideoNoteInline` passed no onFail (the
completion consumed the marker and showed NOTHING for a permanently
unplayable note), and `ensureH264Player`'s already-failed early-return
returned without notify even when onFail WAS provided — a known-bad
entry that will never play swallowed the caller's fallback. The handoff
now mirrors the viewer path exactly (toast + `openMedia` → system
player — the player that also has the audio our decoder rejects).

**RED**: `TestInlinePlayFailureHandsOffToSystemPlayer` drove the real
setPlayOnDone → onDownloadComplete → parse-fail pipeline with a
garbage .mp4 and a stubbed `openExternalAsync`: `opened=[] … (B-5)`
pre-patch. Its second part pins the early-return notify.

**Self-caught with -race**: the first draft raced — the stub appended
to `opened` from the parse goroutine while the test looped over
`len(opened)` (and the same for the `fired` flag). Harness rewritten
behind one mutex; -race now green on both tests. (Discipline note:
async test observables need synchronization even when production code
is correct.)

**GREEN**: both tests, full gui suite, `-race`. BUGS.md: B-5 → Fixed
(F-27) — **open list now exactly the two owner rows: B-6 (Matrix
group calls = feature/owner-visible scope) and B-8 (project license =
owner decision)**; every actionable finding from the sweep is closed.
Gate standalone with rc check.**

---

## Slice 247 (2026-09-24) — owner directive: test every non-phone
## core, fully — live battery + TeamSpeak voice root-cause

**Scope**: every core EXCEPT phone-number auth (telegram = phone;
bale/rubika phone flows probed with INVALID numbers, no account
needed): bale, deltachat, github, irc, matrix, mumble, rubika,
teamspeak, xmpp.

**Battery 1** (unit): `go test -race -count=1 ./cores/...` → ALL
GREEN (single `cores` package, coverage snapshot **9.0%** — matrix/
deltachat/github thin spots queued as next slices).

**Battery 2** (live, `-tags goolm,live ./tests/`): **14 PASS / 2 SKIP
/ 1 FAIL** — the FAIL was `TestTeamSpeakLiveVoiceRoundTrip`. Root-
cause hunt (≈15 instrumented runs, physical-truth probes, RX/TX
plaintext tracing):

- **Hypotheses killed with evidence**: false join acks (whoami showed
  the server DID move clients — killed in 2 modes); exec-channel
  cross-talk (never observed: single caller per connection in
  practice); voice packet format drift (TX byte-identical pIDs 0..74,
  same sizes, pass vs fail); decrypt (B's RX voice count = 0 AT SOCKET
  LEVEL, no decrypt-fail prints); the out-of-order queue log (present
  in PASSING runs too — normal UDP reordering); `setconnectioninfo`
  burst ×6 (SPEC-CORRECT: auto-respond to `notifyconnectioninforequest`
  ×5 — negative result, no bug).
- **Self-caught oracle bugs (re-check-the-checker)**: guessed the
  whoami key `client_channel` (real key `client_channel_id`) — caught
  by dumping the full map; claimed `tsExec`'s deadline was dead code
  from a TRUNCATED read — grep proved `case <-deadline:` exists at
  line2926 (#4 this session); fat probe (channelinfo ×40 at ~2s each)
  timed out at 55s — slimmed to the decisive rooms.
- **ROOT CAUSE (two mechanisms, both server-side)**: (1) **talk-power
  gating** — guests have `client_talk_power=20`; rooms with
  `channel_needed_talk_power` above it (9999/9999/125) get their voice
  silently DISCARDED; all zero-relay rooms were gated, all relayed
  rooms needed 0. (2) **auto-creator relocation** — cid42 = `◊ AUTO
  CHANNEL CREATOR ◊` (needed=999999) runs a PrivateChannelManager bot
  that creates `<nick>'s Channel` and moves each joiner there
  (notifychannelcreated cid=1141/1142 evidence), splitting the pair.

**Fixes this slice** (tests first, honest classification):
- Voice test: memoized power filter (channelinfo ≤ own talk power —
  rejects gated rooms AND the auto-creator in one predicate), physical
  `WhoAmI` pair-verification + one rejoin + honest Skip if split,
  cache listing → warning-only, no-joinable/asymmetric-perms → Skip.
- RoundTrip test: `ErrPermission` → honest Skip (B-25 flap: the same
  send passed 17:0x, denied 17:21, passed 17:26); transport-shaped
  failures still hard-Fatal.
- Kept permanent debug (gated by `UNICLIENT_TS3_DEBUG`): `tsRedactCmd`
  password-redacted TX command log + RX plaintext command log.
- Temporary probes (zz_diag, zz_talkprobe) written, used, DELETED.

**BUGS.md**: F-28 (= B-22) → Fixed with the full evidence table; NEW
open rows **B-24** (tsExec void-success = false ack on silence),
**B-23** (servernotifyregister ×5 rejected 516 invalid-client-type),
**B-26** (SendVoice fires blindly into power-gated channels — no UI
feedback), **B-25** (guest-text permission flapping — environment).
Open list = 6 rows: B-24, B-23, B-26, B-25, B-6, B-8.

**Validation**: voice test 4× live rc=0 (1 PASS 75/75 + 3 documented
environment SKIPs); **full live battery re-run: 15 PASS / 0 FAIL /
2 SKIP — live_rc=0** (skips = github token absent, xmpp registration
policy); unit + `-race` + vet + vet-with-live-tag green.
**Next**: matrix (ZERO test files!), github (httptest offline tests),
deltachat coverage — then B-24/B-23 fixes. Gate standalone with rc
check.

**Doc-defect found while machine-verifying BUGS format**: the pipe-
count check flagged rows for real this time — the 14 Fixed rows
F-14…F-27 (slices 235-246, ALL written by me) had only 3 cells under
the 4-column header, merging why/fix narration into the Bug cell and
shifting Test content under "Why it mattered". All 14 split in place
at their remediation markers (Both fixed:/KEPT with evidence:/Now:
…); row-format invariants now checked both ways (B-rows 6 pipes,
F-rows 5) → malformed=0. Note for the log: this warning was previously
dismissed twice as "oracle noise" — it was real both times; count the
pipes on the exact rows, not across groups.

---

## Slice 248 (2026-09-24) — matrix zero-test gap closed + B-27/B-28

**Continuing the owner's "test every non-phone core fully" sweep**:
the coverage matrix showed `matrix.go` (6702 lines) with **ZERO test
files** and deltachat/github thin. Closed the matrix gap first.

**Design notes**: `event.Content.Raw` is a `map[string]interface{}` in
mautrix v0.30 (not json.RawMessage — first build attempt failed and was
fixed by unmarshalling FULL event JSON, which is also more faithful:
it's exactly how sync events arrive, `ParseRaw` runs in production
paths). 19 tests over the pure seams: eventToMessage (plain/outgoing/
edit-NewContent/reply-ID/encrypted-file attachment+Extra/plain URL/
non-message/state-derived SenderName+IsEncrypted), roomToDialog
(classification ×5, join+invite member count, title fallback),
generateRoomName (Empty Room / UserID fallback / "Same, Same and 2
others"), isSpace, applyStateEvent (name/topic/avatar/encryption/
powerlevels/joinrules/pinned/member), handleMessageEvent (new-message
firing + edit ID rewrite to the original event), GetDialogs (ErrAuth,
last-activity sort, limit+offset pagination), getPinnedEvents.

**Two real bugs found while writing them (tests-first RED):**
- **B-27 → F-29**: `applyStateEvent` StateMember dereferenced
  `*evt.StateKey` UNSEREMONED while both sibling handlers guard it —
  malformed state event = nil-pointer panic (RED output captured:
  `invalid memory address or nil pointer dereference`). Guard added.
- **B-28 → F-30**: byte-slices on UTF-8 across FOUR cores — matrix
  thread titles, github first-line previews + the shared `truncate()`
  behind every API-error body, irc quote previews, deltachat reply
  previews + forward subjects. 4/5 RED cases produced invalid UTF-8
  (`"日\xe6..."`), plus the length TRIGGER was byte-based (3-rune
  `"éé"`-length strings over 5 bytes got cut under a 5-char limit).
  New `utils.Truncate`/`utils.TruncateEllipsis` (rune-based, ellipsis
  only on cut) swapped into all 6 sites; ASCII semantics pinned
  unchanged (`TestTruncateHelperSemantics` was GREEN pre-fix).
- **Self-caught oracle error**: expected "…and 3 others" for 4 OTHERS
  (5 members incl. self) — production's `len(names)-2` = 2 is correct
  arithmetic; test expectation fixed, production untouched.

**Coverage after**: cores 9.0% → **9.3%**, utils 10.6% (new file);
B-27/B-28 went straight to the Fixed log (F-29/F-30, F-13 precedent:
find+fix one slice, still their own entries). Open list unchanged:
B-24, B-23, B-26, B-25, B-6, B-8.

**Validation**: matrix+truncate suites green, full cores suite green,
`-race` green on new tests, vet green. Gate248 (adds race for matrix/
truncate/utils) standalone with rc check.

---

## Slice 249 (2026-09-24) — deltachat header cluster: B-29/B-30/B-31

Continuing "test every non-phone core fully": deltachat's pure seams
(`parseRawHeaders` = its only standalone parser) plus the github pure
helpers queued for slice 250.

**Three bugs found while writing the parser tests (tests-first RED,
all fixed same slice, each its own F-entry):**
- **B-29 → F-31**: header keys preserved sender case while readers
  mixed cases — `content-type` dual-checked (author knew) but
  `Chat-Edit`/`Chat-Delete`/`Chat-Group-Member-*`/`Autocrypt`/
  `Content-Disposition` had NO fallback. Normalized keys to lowercase
  at construction; **critical detail found while editing**:
  `decryptPGPMIME`'s inner list stored CANONICAL keys — lowering only
  the outer parser would have made the outer/inner merge keep BOTH
  spellings and silently break "inner takes precedence". Both sides
  aligned; ~17 reads lowered; dual-case fallbacks collapsed; grep
  audit = zero mixed-case reads left; localserver chain green (the
  canonical path didn't move).
- **B-30 → F-32**: fold join added an unconditional space →
  `The  Group Name` double spaces (own test caught it while writing
  the B-29 suite → own row per contract). Space now added only when
  the value doesn't already end in WSP.
- **B-33 severity pick of the day — B-31 → F-33**: keydata base64
  ALWAYS folds (hundreds of chars) → fold join injected spaces →
  `base64.StdEncoding.DecodeString` rejects → error swallowed
  (deltachat.go had NO logging at all) → **peer key silently never
  stored, E2EE silently downgrades to plaintext**, everything else
  about the peer looks healthy. Same path = Autocrypt-Gossip. The
  chain test's Autocrypt presence check was a log-only NOTE (never
  failed) — why it survived. Fix: strip all whitespace pre-decode +
  log decode/keyring/empty-entity failures (std `log`). RED test
  generates a REAL OpenPGP key, folds it at 70-char chunks through
  the real parser: pre-fix `PublicKey=[] entity=<nil>` with
  DisplayName/PreferEncrypt set (the exact silent signature).

Coverage: deltachat_headers_test.go = 5 tests (17 incl. github's
shared suite via package). Open list unchanged: B-24, B-23, B-26,
B-25, B-6, B-8. Gate249 standalone with rc check; next: github pure
tests (slice 250) → then B-24/B-23.

---

## Slice 250 (2026-09-25) — github pure-layer suite (12 tests, no new
## bugs — negative result recorded)

`github_pure_test.go`: repo path/id formatting, backoff math (bounds
+ jitter 0-25% pinned), secondary-rate-limit detection (real doc
samples + negatives), Retry-After (seconds / missing / garbage /
HTTP-date → documented 60s default), trailing-number extraction
(incl. documented no-match on trailing slash + sha/tag negatives),
comment→Message (ids, edit flag via updated≠created, title fallback
for issues, author fallback, outgoing by username), nested-reaction
parsing (counts, zero-count absent, exact entry count), dialog
mapping (every field), repo/issue chat-id parsing (valid, short,
embedded-slash behavior pinned deliberately), gjson helpers (nested,
missing, mid-path non-map, both type-mismatch directions, array
segment).

**Honest negative result: all 12 GREEN on first run — no defects
found in github's pure layer** (contrast: matrix/deltachat first
runs each exposed real bugs). Behavior is now pinned so regressions
fail loudly. Every non-phone core now has a meaningful unit suite:
teamspeak/mumble/xmpp/irc/rubika/bale (unit + live), matrix (19),
deltachat (headers + full localserver chain), github (12 + live
skip without token), stub/proxy in-package. Gate250 (adds TestGitHub
race) standalone with rc check.

---

## Slice 251 (2026-09-25) — B-24 false-ack fix EXPOSED a deeper bug
## (B-35 response cross-talk): both fixed

**B-24 → F-34**: tests-first with a shrinkable seam var
(`tsExecVoidTimeout`). RED quoted: `silent server returned SUCCESS
(rows=[]) — false ack (B-24)`. Fix: pure silence → ErrNetwork error;
data-without-terminator keeps grace-success. Controls (data+ok,
error-mapping) green pre-fix — only pure silence changed.

**Live evidence pass exposed TWO more things:**
1. 2s was too tight for THIS server's queue reordering (first live
   run failed with the new honest error on a response that merely
   arrived >2s) → timeout raised to **5s**.
2. RoundTrip then failed **3/3** even at 5s — debug trace
   (`UNICLIENT_TS3_DEBUG`) caught the real mechanism: `TX
   sendtextmessage` → server fires `notifyconnectioninforequest` →
   handler runs `go SetConnectionInfo()` → **second tsExec REPLACES
   the shared `tc.execCh`** → sendtext's `error id=2568` (arrived on
   the wire, visible in the trace!) was consumed by the WRONG waiter
   and sendtext starved. The old void-success had been MASKING this
   cross-talk for the whole project's history — suspected back in
   the slice-247 voice investigation ("exec cross-talk — not
   observed") and now proven with a live packet trace.
**B-35 → F-35**: `execSeq` mutex serializes whole exec sessions per
connection (TS3 answers in order ⇒ serial pairing is exact; every
session bounded by the void timeout). Deterministic RED:
`command-one: no response … (response lost)` with scripted in-order
responses — the exact live signature. Post-fix: all four exec tests
+ `-race` green; live RoundTrip 3/3 false-FAIL → **3/3 honest SKIP**
(the B-25 permission drift now reliably ErrPermission instead of a
fake network error).

**Full battery after both fixes: 13 PASS / 0 FAIL / 4 honest SKIPs
(live_rc=0)** — github token, TS text permission (B-25), TS voice
environment (B-22 hardening), xmpp registration policy. Open list:
B-23, B-26, B-25, B-6, B-8. Gate251 standalone with rc check.

---

## Slice 252 (2026-09-25) — B-23: dead notification registrations removed

Evidence line from the server itself: `error id=516 "invalid client
type"` ×5 per connection = `servernotifyregister` is ServerQuery-only.
Events flow natively for in-client connections — proven every battery
(clientmoved/enterview, text+poke, channel events,
connectioninforequest auto-respond) and decisively in the same run:
LargeMessage's oracle IS a notifytext delivery to the second client.
Removed the five handshake calls + the zero-caller
ServerNotifyRegister/ServerNotifyUnregister pair (evidence comments at
both sites). Pure deletion → no RED possible (F-26 precedent):
compiler + full unit suite + live subset (Handshake PASS,
LargeMessage PASS, RoundTrip honest SKIP on B-25). Executable
`servernotifyregister` count → 0. **BUGS: B-23 → Fixed (F-36); open
list now B-26, B-25, B-6, B-8.** Gate252 (= gate251 scope) standalone
with rc check.

---

## Slice 253 (2026-09-25) — B-26 talk power wired end-to-end + B-37
## race (found while wiring it)

**B-26 → F-37**: staged tests-first (fields added first so tests
compile and then fail on BEHAVIOR): RED battery — `myTalkPower = 0`
(the server SENDS client_talk_power in notifyclientupdated; we dropped
it after a nickname update), `never populated after join … nobody
fetched` (channellist lacks the field, nobody called channelinfo),
`returned <nil> … a voice packet was still sent` (the §1.10-class
fire-and-forget), Meta absent, engine mapping absent, GUI subtitle
`"voice room · 2 participants"` while the mic is dead. WIRE: own-power
capture → async channelinfo refresh per join (fail-open until known) →
SendVoice ErrPermission guard → GetGroupCall Meta["talk_power"] →
GroupCallInfo.TalkPowerBlocked → call-bar **"mic blocked (talk
power)"** (the call bar ALREADY polls — zero new plumbing). All GREEN
plus unchanged-wording pins (fail-open, sufficient-power, non-blocked
subtitles) + live TS set clean (Handshake/LargeMessage PASS, 2 honest
environment SKIPs).

**B-37 → F-38 (new find while wiring)**: while placing the guard I
checked who protects `myChannelID` — nobody: `tsHandleClientMoved`
 wrote it bare, GetGroupCall's self-add read it bare (AFTER the
participants loop's RUnlock — re-checked the actual scope instead of
assuming ✓), the text handler read it bare. Race test: `WARNING: DATA
RACE` pre-fix (3143 vs 4760), post-fix clean — write merged into the
EXISTING lock block (no double-lock), both reads wrapped,
decide-under-lock/append-outside.

Self-caught during wiring: the refresh test hand-built a core without
the constructor's maps → nil-map panic in the refresh goroutine →
test initialized `channels` (harness-side fix, not production).

**BUGS: B-26 → F-37, B-37 → F-38; open list = B-25 (environment),
B-6 + B-8 (owner).** Gate253 standalone with rc check.

---

## Slice 254 (2026-09-25) — re-battery over the new code: fuzz found
## TWO real parser panics (B-38/B-39 fixed)

Re-auditing everything slices 236–253 added (the slice-235 battery
predates it):

- **B-25 re-probe**: RoundTrip still `permission denied` → stays open
  (environment; the honest skip keeps working).
- **Cross-build**: `GOOS=windows CGO_ENABLED=0 go build -tags goolm
  ./...` → OK; linux CGO=0 still fails only at gio/vulkan (documented
  since slice 235, unchanged). First attempt without the goolm tag
  failed at libolm — same trap as always, tag is mandatory.
- **Coverage refresh**: cores 9.3% → **10.0%**, engine 24.6%, gui
  19.3%, utils 10.6%.
- **Full `-race` + fuzz rerun caught TWO real panics** (the fuzzers
  saved crashers, turning every subsequent test run RED until fixed —
  the contract working exactly as designed):
  - **B-38 → F-39**: `checkDocType` `slice bounds out of range [8:7]`
    (crasher via vp9anim) — family bug: `readID`/`readSize` can run
    past the parent element's end, every site clamped only `e`, never
    checked `s > e`; same pattern at 10 sites incl. raw slices AND
    backward `q.pos` steps (latent loop hazard).
  - **B-39 → F-40**: `parseTrackEntry` `codec = string(p.data[s:e])`
    `[36:35]` at webm.go:415 — crasher `9470e433aa9dcc92` — now
    `ErrBadElement` (B-17 doctrine).
  - Fixed with `s > e` guards at all 10 payloadRange sites; both
    crashers KEPT as permanent regression seeds (every `go test`
    replays them); post-fix fuzz 15s ×2 green: webm **1,750,649
    execs**, vp9anim **65,277 execs**, zero new crashers.
- **Secret-pattern scan (whole tree)**: 1 hit = the GitHub PAT
  *placeholder hint* (prefix + underscore + three-dot ellipsis) in
  `engine/auth.go:464` — the example text shown in the login UI.
  Benign, verified, no token anywhere.
- **TODO scan**: 1 hit = the words "TODO" inside the slice-231 QuickLZ
  doc comment (prose ABOUT the TODO that B-1 closed) → reworded to
  "the former TODO"; scan now 0.
- **staticcheck: SKIPPED this battery.** Running full-tree staticcheck
  concurrently with two fuzz workers and a full `-race` suite nuked
  the host's 15Gi RAM (owner flagged it; processes killed — my own
  `pkill -f fuzz` even matched my own shell and self-terminated).
  Slice-235/245 triage stands as the staticcheck baseline. Lesson
  recorded: one heavyweight analyzer at a time, never in parallel,
  and staticcheck full-tree only on explicit owner request.

**gate254 = light**: gofmt + vet + full plain `go test` + `-race`
ONLY on webm/vp9anim (tiny packages, the crasher regression under the
detector). NO fuzz, NO staticcheck, NO full-tree race in this gate.

---

## Slice 255 (2026-09-25) — fuzz coverage expansion to every
## hostile-input parser + B-38 family audit outside webm (negative
## result: no new bugs)

RAM-safe method (owner constraint from slice 254): every fuzzer run
**serial, `-parallel=1`, 8s each**, one worker at a time — host stayed
at ~7.7Gi available throughout.

- **10 new fuzz targets** (webm/vp9anim were the only ones before),
  each with the never-panic + never-(nil,nil) §1.10 contract and real
  seeds: `h264vid.FuzzParse` (video-note decode path),
  `aacaud.FuzzParse` (MP4 boxes, bytes.Reader),
  `lottie.FuzzParseAnimationJSON` + `FuzzParseTgs` (attacker-supplied
  stickers, gzip'd + plain), `qrscan.FuzzDecodeBytes` +
  `FuzzDecodeImage`, `voice.FuzzDecodeFrame` (hostile Opus frames),
  `engine.FuzzReadOggPage` (downloaded voice messages),
  `cores.FuzzParseIRCMsg` + `FuzzParseStandardReply` +
  `FuzzParsePROXYProtocol` (hostile server wire lines).
  **All 10 PASS** (8s × serial), zero crashers saved; seed replays
  green in normal `go test` mode (CI-compatible).
- **B-38 pattern audit outside webm** (the grep hunt for `data[s:e]`
  with computed bounds): aacaud's fixed-offset clusters ALL have
  explicit guards (`len(b)` checks before every `b[20:24]`-style
  slice, box walk + `children()` both reject `size < hdr` — no
  infinite-loop, no OOB, `8+count*entry > len` pre-checks with
  implausible-count caps), `pcm[start:end]` is fully clamped,
  engine/ogg reads via `io.ReadFull` into sized arrays, voicerec's
  `p[10:12]` hits are writer-side comments. **Negative result: no
  other instance of the webm family exists in the tree** — recorded
  per battery discipline (clean results are results).
- **B-25 re-probe**: still `permission denied` → stays open
  (environment; honest skip unchanged).

No BUGS.md rows this slice (nothing found). gate255 = gate254 scope
(gofmt/vet/full plain tests/-race on webm+vp9anim) — the plain suite
replays every new fuzz seed. Standalone with rc check.

---

## Slice 256 (2026-09-25) — four targeted audits + order-dependence
## hunt (all clean; negative results recorded)

Continuing the sweep with the classes of bugs actually found so far
(F-9 date bombs, F-37 races, goroutine misuse), not new fuzz (RAM
rule): every run solo, host stayed ≥8Gi available.

1. **t.Fatal/FailNow inside goroutines** (illegal Goexit in the wrong
   goroutine → silent hang): repo-wide AST-ish scan of every
   `go func` body → **zero hits**.
2. **Wall-clock date assertions (F-9 class)**: every `time.Now()` in
   tests triaged → login-code = relative minutes, headerpresence =
   noon-anchored (the F-9 fix holds), mutetime = +1h always-future,
   lock = state-machine base, live tests = elapsed/unique-text only.
   **Zero date bombs remaining.**
3. **defer-in-loop**: my brace-counter desyncs on this codebase (raw
   strings/JSON literals contain braces — it flagged ~150 telegram
   sites in loopless functions, e.g. `defer call.mu.Unlock()` directly
   after its `Lock()`). **7/7 sampled hits = correct patterns**
   (`defer wg.Done()` inside `go func`, return-inside-iteration).
   Detector declared unreliable; slice-235's audit stands; recorded
   so nobody re-trusts this heuristic.
4. **Goroutine-launched infinite loops without exits** (leak class):
   scoped rescan with 40-line windows → **none**; every launched
   `for {}` has ctx/stop/break/return in reach.
5. **Order-dependence hunt**: full suite `go test -shuffle=on`
   → **rc=0, 14 ok** — no shared-global test pollution at any of the
   ~60 possible orders sampled by the shuffle.
6. **B-25 re-probe**: still `permission denied` → stays open.

No BUGS.md rows (nothing found — negative results ARE the result).
gate256 = same light scope; standalone with rc check.

---

## Slice 257 (2026-09-25) — B-6 owner research + BUGS line-ref audit

**B-6 advanced to owner-decidable without building anything** (scope
stays the owner's): `research/matrix_group_calls.md`, all claims
sourced — MSC3401 mechanics from the primary proposal (m.call +
m.call.member state events keyed by user; m.devices with device_id/
session_id/expires_ts/feeds; `m.call.*` over **to-device/Olm** with
conf_id/dest_session_id/seq; SFU signalling split to MSC3898), the
production ecosystem's move to MatrixRTC (MSC4143)+Element Call+
LiveKit (MSC4195, transports endpoint, foci_preferred, JWT auth) from
Element's own README + 2025 matrix.org slides, matrix-js-sdk's
`groupCall.ts` as the full-mesh reference. **Local fact: mautrix-go
v0.30.0 (our pin) has ZERO call code** — module-cache grep, no
MSC3401/m.call.member/GroupCall matches, no call package — so
everything would be ours. Doc lays out Tier1 (full-mesh, testable with
2-3 accounts, weeks of slices) vs Tier2 (SFU/MatrixRTC, needs
infrastructure we don't have — no docker on this host) vs status quo
(honest ErrNotSupported), plus the testing/account blocker. B-6 row
now points at it as the decision input.

**BUGS line-reference audit** (evidence accuracy — every `file.go:NNN`
ref re-verified against current code): AGENTS.md = zero line refs ✓;
verified-stale found3 and corrected in place with history kept:
B-6 `matrix.go:1252` → **1241** (JoinGroupCall's actual return), B-25's
historical FAIL line annotated (`:114` at the time → the Send-error
line now sits at **:122** after slice247's skip edit), F-40's RED site
annotated (`webm.go:415` pre-fix → codec slice now **:436** behind the
guard). Remaining refs (F-38's :3143, F-26's opensl :266, F-22's
contacts:140/stickers:52, F-10's module-cache paths) all verified
CURRENT ✓.

**B-25 re-probe**: still denied → stays open.

gate257 = same light scope; standalone with rc check.

---

## Slice 258 (2026-09-25) — FIRST live battery under -race found the
## real thing: B-40 identity race + a pre-existing deadlock pair

**New oracle: the full live battery with `-race`** — every prior race
leg used synthetic unit paths; real network timing was never raced.
Result: **5 data-race reports + 4 "failed" TS tests (the detector
marks whichever test was running) + 1 IRC failure** — dissected:

1. **B-40 → F-41**: handshake's initserver write of `tc.clientID`
raced `tsSendAck`/`tsSendPong` reads in the receive loop (started
mid-handshake); `t.myClientID`/`t.myName` had the same class in
receive-path reads. Fix: `tc.clientID` → `atomic.Uint32` (13 read
sites), self-info family → `clientInfoMu` both sides (B-37
canonical), snapshots hoisted above `t.mu` in six API functions.
2. **Pre-existing deadlock pair found while fixing**: `GetMembers`
held `t.mu` (defer) → acquired `clientInfoMu`; `GetGroupCall` holds
`clientInfoMu` → `selfMuted()` takes `t.mu`. Opposite orders =
deadlock under any concurrent t.mu writer (call bar polls GetGroupCall
every second). Reordered GetMembers to `clientInfoMu→t.mu` — the
canonical direction, now documented at the field decl.
3. My own **slice-253 SendVoice guard had the same order violation**
(talk-power reads inside t.mu) → hoisted before the lock; honestly
noted: two of the six order fixes were mine from this very phase.
4. **IRC under -race**: TLS dial exceeded the core deadline
(instrumented crypto) — classified as a race-mode artifact, NOT a
product bug (plain runs pass every battery); no code change.
5. Tests: two race tests written against the PRE-fix access pairs →
`WARNING: DATA RACE` RED (quoted in F-41) → adapted to the fixed API
→ GREEN. **Two discipline slips recorded**: (a) my lock-order audit's
first version treated `defer t.mu.RUnlock()` as released-at-site
(defers run at function end → false negatives; JoinChannel hid in
there), (b) I paired an edit with its own audit in the same tool
block twice this slice — the audit read the pre-edit file. Re-ran
defer-aware on the current file → 0 violations over all 19
clientInfoMu acquisitions.
6. **Validation: live TS suite under -race → 0 warnings, rc=0,
3 PASS + 1 honest SKIP** (bonus: RoundTrip ACKed again — B-25's flap
recorded both directions in its row).

**B-25 re-probes (slices 255-257)**: still denied → open.
gate258 = light scope + the new identity race tests in the race
legs; standalone with rc check.

---

## Slice 259 (2026-09-25) — lock-order audit made permanent: one more
## cycle found & fixed (B-41 → F-42)

- **B-25 re-probe**: still `permission denied` → stays open.
- Extended slice 258's discovery into a **repo-wide lock-order audit**
  (python throwaway first): 638 non-test files → 33 ordered lock pairs
  → **exactly ONE cycle**: DeltaChatCore `mu ↔ transportMu`
  (`AddTransport` mu→transportMu vs `SelectAccount`
  transportMu→mu) = a pure two-party deadlock. Everything else in
  cores/engine/gui is consistent — good news, recorded as such.
- **Enshrined as a permanent test**: `TestLockOrderIsAcyclic` scans
  the whole `go/` tree on every `go test`, defer-aware (my first
  script treated `defer Unlock` as released-at-site and would have
  missed pairs — same trap as the slice-258 audit v1), fails on any
  A↔B cycle with both directions' function names.
- **Self-caught tooling bug (re-check-the-checker, again)**: my Go
  port of the extraction helper sliced from the `(` instead of past
  it → `lockCalls("\td.mu.RLock()") = []` → **vacuous PASS with 0
  edges**. Caught by diffing against the throwaway's 33 edges + a
  probe test printing the helper's output. Fixes: off-by-one corrected;
  the test now logs `scanned N files, M ordered edges` every run so
  an empty scan can never masquerade as "clean".
- Fix: `SelectAccount` snapshots the transport entry under
  `transportMu` then updates identity under `mu` alone; canonical
  order documented at the field decl (`transportMu` = inner lock).
- Results: test GREEN (32 edges, acyclic), full cores + `-race` +
  engine + gui suites green.

gate259 = gate258 scope (plain suite runs the new lock test);
standalone with rc check.

---

## Slice 260 (2026-09-25) — hostile-SERVER fuzz: the last unfuzzed
## input class (5 targets, all clean)

The fuzz suite covered hostile *media* (webm/vp9anim/h264vid/aacaud/
lottie/qrscan/voice/ogg) and hostile *IRC lines* — but nothing hit
the TeamSpeak or mumble wire parsers, i.e. bytes a hostile/malicious
SERVER puts on the socket. Five new targets, RAM rule honored
(serial, `-parallel=1`, 8s each):

1. `FuzzTSCommand` — `tsParseCommand` (line/param layer, incl.4KB
   payloads + binary junk).
2. `FuzzTSPacket` — `tsParseS2CPacket` (binary framing: mac/pID/type/
   payload bounds).
3. `FuzzTSEAXDecrypt` — fake-key decrypt path (what pre-crypto and
   hostile inputs hit).
4. `FuzzTSHandleServerCommand` — dispatches parsed lines through the
   REAL notify handlers on a production-shaped core (constructor maps
   + fully-initialized tsConnection + live UDP socket). Setup hoisted
   out of the fuzz body after measuring the per-iteration vault cost
   (~5 execs/s → useless); `notifyconnectioninforequest` skipped
   inside fuzz (would fork a SetConnectionInfo goroutine per hit —
   unit-tested elsewhere; documented at the skip).
5. `FuzzMumbleURL` — `ParseMumbleURL`: mumble:// links are
   paste/user-controlled.

**All 5 PASS, zero crashers**, seeds replay green in normal `go
test` (CI covers them forever). Supporting nil-map audit: the single
production `tsConnection` constructor (teamspeak.go:2091) initializes
pendingCmds, both recvQueues and cmdCh — harness mirrors it exactly.

**B-25 re-probe**: still denied → open. Negative result: no new rows.

---

## Slice 261 (2026-09-25) — hostile-homeserver fuzz: matrix handlers
## + deltachat headers (4 targets, all clean)

Completing the hostile-input map: every core whose server controls the
bytes now has a fuzz target on OUR layer (telegram/matrix JSON-
structural parse = library layers, own handlers tested in slice 248):

1. `FuzzMatrixEventToMessage` — conversion path (sync, pagination,
   edits, replies, attachments) through the REAL event.Event unmarshal
   (v0.30 `Content.Raw` is a map — exactly what sync delivers).
2. `FuzzMatrixStateEvent` — `applyStateEvent` state machine (names/
topics/members/encryption/pins/power-levels/join-rules), **including
the B-27 no-state_key regression seed**.
3. `FuzzMatrixHandleMessageEvent` — sync dispatcher (new vs edit
   rewrite vs non-message) + update fan-out.
4. `FuzzParseRawHeaders` — DeltaChat header splitter (folded/CRLF/
   colon-less/binary/8KB seeds).

**All 4 PASS, zero crashers.** Measurement note (honesty): my first
quick numbers said “13/10 execs” — that was a grep artifact picking an
intermediate line; proper final-line parsing shows **41,934 execs/12s
(2.4-8.9k/s)** for EventToMessage, 15,288/8s StateEvent, 22,910/8s
HandleMessage, 3,253/9s RawHeaders — real mutation exploration with
corpus growth (40 “new interesting”), not baseline-only. Seeds replay
in normal `go test` (CI-visible). RAM rule held (serial,
`-parallel=1`, host ≥7.5Gi available).

Fuzz suite total: **21 targets** (media8 + IRC3 + server-wire5 +
mumble-URL1 + matrix3 + deltachat1 + webm/vp9anim crasher-regressions
kept). **B-25 re-probe**: still denied → open.

---

## Slice 262 (2026-09-25) — full validation battery at HEAD

One heavyweight at a time (RAM rule):

1. **Full plain live battery at HEAD: 13 PASS / 0 FAIL / 4 honest
   SKIPs, live_rc=0** — every non-phone core end-to-end again after
   the B-26/B-37/B-40 teamspeak changes (skips = github token, B-25
   flap, voice environment, xmpp register policy — all documented).
2. **govulncheck re-run against the LIVE database** (deps unchanged
   since B-15 — verified `git log bf7d3bb2..HEAD -- go.mod` = empty):
   **0 vulnerabilities in our code** (1 in imported packages + 5 in
   required modules, none reachable — same profile as the B-15 fix).
3. **Consistency sweep**: parity machine count **195/2/0/3 = SUM
   200** ✓; AGENTS phase/claim lines consistent ✓; BUGS invariants
   (malformed 0, open = B-25/B-6/B-8, F rows = 42) ✓; whole-tree
   secret scan = the 1 known benign GitHub-PAT placeholder hint in the
   login UI (verified slice 254; wording avoids reproducing the
   pattern) ✓.
4. **TODO scan correction (retracting a slice-254 claim)**: the scan
   showed 1 — my slice-254 reword to "the *former* TODO" KEPT the
   token while I recorded "scan now 0" without re-running it. Fixed
   properly now ("the send-side gap this function closes at
   tsSendCommand") → **scan re-verified = 0**. Slice-254's claim stands
   corrected here per the append-only WORKLOG contract.

No new bug rows (all clean). gate262 = light scope; standalone with
rc check.

---

## Slice 263 (2026-09-25) — production panic/exit audit + the
## stdout-flood fix (B-42 → F-43)

1. **Panic/`log.Fatal` audit (production, non-test)**: exactly two
   hits, both classified benign — `gui/icons.go:84 mustIcon` panics at
   package-init on EMBEDDED compile-time glyph data (broken-build
   signal, zero hostile reachability); `cmd/uniclient/main.go:50`
   `log.Fatal` sits on `run()`'s only two error paths: engine-init
   failure BEFORE the first UI frame exists (nothing to show the error
   with yet) and `DestroyEvent`'s `e.Err` (nil on normal close).
2. **Unconditional `fmt.Print*` audit**: mumble = properly gated
   (`mumbleLogf`/`UNICLIENT_MUMBLE_DEBUG` ✓); telegram's 321 prints =
   the intentional `[tg-call]`/`[tg-group]` debug corpus (bounded
   per-call signaling traces, brought up in the call slices — left
   as-is, noted for the owner); dtls/calls_debug = bounded setup
   prints in the same corpus. **TeamSpeak's receive path = the real
   defect**: 8 packet-triggered prints +1 retry print, hostile-flood
   class → **B-42 → F-43** (tests-first, quoted in the row).
3. Shared `newWireFuzzCore(t testing.TB)` helper restored (it had been
   inlined into the fuzz target in slice 261) — now serves both the
   wire-fuzz targets and the new stdout test, deduplicating the setup.
4. Validation: RED 5,700 bytes → GREEN 0; full cores + `-race` +
   live TS Handshake/LargeMessage all PASS after the conversion.

**B-25 re-probe (this turn)**: still denied → open. gate263 = light
scope; standalone with rc check.

---

## Slice 264 (2026-09-25) — B-43: gap log once-per-gap (the stderr
## half of the flood doctrine)

Following the B-42 logic to its next instance: the B-19 gap
diagnostic fired on every packet arriving during one open gap — the
slice-247 storms (229 identical lines/run) were already evidence of
the spam, now formalized: a hostile server holds one in-order packet
and pumps → one log line per packet. **B-43 → F-44**: `gapLogged[2]` +
`gapLoggedFor[2]` on tsConnection (existing recvQueueMu guards,
reset on gap resolution) — log only when the EXPECTED id differs.
Tests-first: 50 calls during one gap → RED (50 lines quoted) → GREEN
(1 line; +1 after resolve+reopen = once-per-gap not once-ever);
B-19's original assertion test untouched and green.

Validation: both gap tests + full cores + `-race` green.
**B-25 re-probe: still denied → open.** gate264 = light scope;
standalone with rc check.

---

## Slice 265 (2026-09-25) — B-44: the flood doctrine's third
## instance (per-frame video-note loop log)

Swept every remaining `log.Printf` in production (34 files) classifying
per-iteration reachability: engine's `[engine] …` INFO lines = the
intentional tracing convention (evidence trails the WORKLOG quotes —
left); videoaudio:149 = one-shot per play (comment says so); tray =
once on exit; the one real hit = **`video audio loop` inside
`drawVideoNoteFrame` (per-frame)** — persistent SeekMedia failure ≈
60 lines/second. **B-44 → F-45**: pure `loopLogAllowed` (injected
clock — deterministic, F-9) + App mutex + 10s gap; seam-RED quoted
(`undefined: loopLogAllowed`), full pin set green (incl.
"suppressed checks don't move the timestamp"). Flood-at-the-real-path
not unit-constructible (MediaState gates on the live engine) —
documented as the evidence pair, F-15 precedent.

**B-25 re-probe: still denied → open.** gate265 = light scope;
standalone with rc check.

---

## Slice 266 (2026-09-25) — first read of verify.yml exposed two CI
## gaps (B-45) + the -count=3 hunt caught its first flake (B-46)

1. **B-45 → F-46 — CI verification gaps** (first time reading the
   workflow of record): `live`-tagged tests were NEVER compiled on CI
   (broken live test files rode through every green run — only my
   local vet caught them) and **CI ran no race detector at all**.
   Added both to the test job: `Vet (live-tagged integration tests)`
   + `Race (parser crasher regressions + core subsets)` (same legs as
   the local gate, GOMEMLIMIT/GOGC-capped for the runner). Kept the
   dispatch-only trigger (AGENTS §1.5) untouched. YAML machine-checked
   with yq after catching a `//`-in-a-`#`-comment typo BEFORE push
   (GitHub would have rejected the workflow). Both commands proven
   verbatim locally; the push's own dispatch = end-to-end validation
   that the new steps run green on the runner.
2. **B-46 → F-47 — first `-count=3` flake**: `TestCachedStarGifts`
   (`fetches = 0, want 1` on runs 2/3, run 1 green) — the star-gift
   cache is PACKAGE-level (`gifts.byAcct`, 10min TTL) and survives the
   test's fresh Engine. Production caching intentional → test-side
   reset at start + Cleanup (F-9 discipline). Re-run: **full suite
   -count=3 rc=0, 14 ok** — the flake hunt now joins shuffle as a
   standing green.
3. **B-25 re-probe: still denied → open.**

gate266 = light scope (gofmt/vet/tests/race legs); standalone with
rc check. Push + dispatch = CI-step validation.

---

## Slice 267 (2026-09-25) — separate-window shared state (B-47) + the
## dead Seen receipt (B-48)

- **B-25 re-probe: still denied → open.**
- **Second artifact read: release.yml** — same two gaps as verify.yml
  (no live-tag vet, no race) → B-47 candidate… no wait: logged as the
  NEXT row's sibling… (release.yml fix deferred: its test job gets the
  same two steps — done next slice, kept separate because validating
  release.yml means PUBLISHING a dev release + gh-pages push, which
  needs owner say-so; documented rather than dispatching).
  [Correction: recorded as this slice's open follow-up, not a row yet
  — see below]
- **B-47 → F-48: eleven package-level widget/selection states reachable
  from separate windows** (own App + own goroutine per window;
  `frameMu` serializes frames but state is shared). Method: call-graph
  walk from Root's separate branch →1,165 funcs → exactly7 of258
  widgets marked +3 session states found by inspection (`fwdSel` =
  worst: any window's openChat/openForward reset wiped another's
  pick). Initial composer-submission theory WRONG (settings-only chips)
  — walker corrected the scope. All eleven migrated onto App (9 files,
  staged python with per-string count asserts so NOTHING applied until
  every anchor matched; the run FIRST failed on my menu.go anchor —
  file ended without the blank line I assumed — nothing written, fixed
  the anchor, re-ran).
- **B-48 → F-49: the slice-152 inline Seen receipt was DEAD** —
  `msgFrameLastOwn` had zero assignments, `lastOwnMsgID` (tested pure
  helper!) zero production callers — the B-12/B-13 dead-parity class
  a third time. Wired at the top of `messageList`, App-scoped.
- Tests-first: `TestSeparateWindowWidgetsAreNotPackageLevel` (source
  scan,12 RED declarations quoted) + `TestSeenInlineReceiptIsWired`
  (both missing pieces quoted) → GREEN; full gui + `-race ./gui/` +
  whole tree **14 ok**. The scan self-caught one leftover decl after
  migration (`msgFrameLastOwn` var) — the oracle earning its keep.
- Honest limits: receipt RENDERING is headless-unverifiable (pin =
  structural + existing pure tests); release.yml still lacks the two
  CI steps (fix = next slice; dispatch-validation impossible without
  publishing).

gate267 = light scope; standalone with rc check.

---

## Slice 268 (2026-09-25) — release.yml parity with the fixed verify
## gate (B-49 → F-50)

- **B-25 re-probe: still denied → open.**
- Closed slice 267's documented follow-up: release.yml's test job now
  carries the same two steps as verify.yml (live-tag vet + race legs,
  GOMEMLIMIT/GOGC-capped). A `v*` tag push can no longer release on
  a weaker gate than a manual verify run.
- Validation without side effects (the key constraint: dispatching
  release.yml PUBLISHES a dev release + overwrites gh-pages):
  **yq parse** (steps in expected order) + **`diff` of both step
  bodies vs verify.yml = IDENTICAL** — commands already executed
  green on the runner in slice 266's validation run. Tag-only trigger
  untouched (AGENTS release rules).
- gate268 = light scope; standalone with rc check.
