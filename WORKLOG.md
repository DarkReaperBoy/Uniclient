# WORKLOG.md — the state file

Top: the **STATE block** — rewritten every session, the resume pointer for the next
agent. Then open items (severity order), then entries newest-first, terse (did /
evidence / next). The pre-2026-11-01 progress docs (BUGS.md, research/) were purged by
owner order — that history lives in git if ever needed.

## STATE

- front: the GUI rebuild (§6) — next slice: keyboard routing (window
  key.Event -> the compose msgs; Enter=send + Up/Down history when empty)
- next: that slice, then D-3 (wasm diet); the token lives in .env (§0.2)
- owner-waiting: N-1 — install the uniclient-android APK artifact from
  build 42622715804 on a device and report (android GUI-default check)
- last-gate: CI build 42622715804 (9d437e10) SUCCESS job+step; Pages
  live-verified in chromium 1440x900 + 390x844 — HUD none, canvas 1,
  #FEF7FF, console clean, v9d437e1

## Open items

| ID | where | what | evidence | next step |
|---|---|---|---|---|
| N-1 | android APK | GUI-default on android is runtime-unverifiable in-sandbox (no emulator/device); expected: the empty Material surface, not a black zombie | session 405 (js sibling); js live-verified in 406; APK artifact on build 42622715804 | owner installs the uniclient-android APK artifact and reports |
| H-2 | verify/release yml | CLOSED 2026-11-09 (owner order): android + web legs returned as build.yml (per-push, no tests, parallel); only the Xvfb GUI + Puppeteer web-drive legs stay parked with the rebuilt GUI | AGENTS.md §8; build 42597570851 | Xvfb/Puppeteer return when the GUI ships (§6.7) |
| H-3 | engine/cores API | 301+1 identifiers exported purely for the tests move (API noise: TsParseInit1, TsTrackRecvPID; audio's MicStop folded to micStop in session 368) | commit 27faa5a4, session 368 | fold into real APIs or de-export when tests are reworked during the GUI rebuild |
| D-1 | ui/history corner button | down-button unread-count badge (22dp, centered x, top 0 — jump_down_button.cpp paintEvent + historyToDownBadge*) + hover/over colors + ripple deferred: no unread counter in the chat Item model yet, no hover/ripple machinery in the skin yet; replyReturn branch of downClick + loadedAtBottom==false state return with reply-return jumps / below-history pagination | jump_down_button.cpp 33-52, corner_buttons.cpp 139-145 | badge returns with read-state counts; over/ripple with the skin's hover+ripple pass |
| D-2 | ui/history unread-things buttons | read-marking absent for mentions AND reactions: after a jump the button stays shown (reference hides it when the server marks the thing read — updateUnreadThingsVisibility is server-data-driven); mentionsClick's already-there voice/video media-read branch (5623) deferred — no media model; unread-count badges join D-1's class; poll-votes 4th stack slot returns with a poll model | history_view_corner_buttons.cpp 147-190, 288-345 | returns with engine unread-things events + the media pass |
| D-3 | build.yml web job | wasm size diet: the js/wasm build ships every core incl. the six raw-TCP backends that can never connect from a browser (§7 web truth) — build-tag exclusion at the engine factory projected <20 MB; also headroom under git's 100 MB file ceiling on gh-pages | headless-host wasm = 31,153,413 B today (v0.9.1's old-GUI build was 88,659,256 B) | one atomic with tests: bootstrap factory js variant + per-core js stubs |

## Session 405 — the web stuck-boot fix: GUI default on no-argv platforms (2026-11-09)

- Owner report (chat): "the web page doesn't load, idk if it is only
  me or it is a bug." Reproduced in headless chromium (playwright
  1.57 / agent-browser) against the live Pages URL: shell + wasm +
  sha256 all serve (31,153,413 B, hash matches the pin), the engine
  boots ("uniclient engine ready (dir /uniclient)" mirrored into the
  HUD), then the headless host blocks on <-sig forever — js has no
  signals; canvasCount 0, boot HUD display:flex after 50 s. A bug,
  not the owner's connection.
- Root cause: the rebuilt main.go made headless the default mode and
  build.yml's web job built that default; v0.10.3's web build WAS the
  GUI (no flag at all — git show v0.10.3:go/cmd/uniclient/main.go).
  Fix: guiDefault = GOOS js or android — the no-argv platforms
  (browser tabs, gogio APKs) have no flags and no signals, a headless
  default there is a zombie surface; desktop keeps headless as its
  default (a real flag there, §1.3). 2-line diff, main.go only.
- Verification (§4): the fixed wasm built with the exact CI recipe
  (gate build, 31,153,413 B) served under the real CI shell on
  localhost: chromium 1440x900 AND 390x844 — HUD display:none,
  canvasCount 1, canvas pixel-sampled 254,247,255 = material Light
  Surface 0xFE,0xF7,0xFF, i.e. the honest zero-account InitialModel
  scene (no demo data, §1.9); console clean; the 390 re-boot also
  exercised the same-version Cache API path (zero-network boot).
  Android kept the same flip but stays runtime-unverified here -> N-1.
- Gates: gofmt clean, comment-ban clean, js/wasm full build green;
  linux-cgo build env-blocked (no libwayland-dev, no root) and the
  windows cross-build OOM'd on gotd tg (the known 4 GiB box limit) —
  both are CI legs (verify/release); build.yml's js job is the same
  recipe. Second atomic: the generated shell's pre-canvas status
  "Running — Uniclient engine host" -> "Running — Uniclient" (the
  GUI boots there now; one build.yml line).
- AGENTS §1.4 + §8 + build.yml header synced in-commit — the old
  "ships the headless engine host until the GUI lands" wording is
  the law that produced the stuck boot.
- Next: push (token waited), watch the CI build run + the Pages
  deploy, verify the live URL in chromium, then the GUI front:
  keyboard routing.

## Session 406 — the push: stuck-boot fix live, Pages verified (2026-11-09)

- Owner provided the GitHub token → stored in `.env` per owner order
  (gitignored `.env*`, never committed/printed/pushed). AGENTS §0.2 +
  scripts/git-askpass.sh (GIT_ASKPASS helper sourcing .env) committed
  BEFORE the push — owner order "update agents.md before you push",
  so future sessions never hunt for a token that is already there.
- Pushed 9d437e10 = session 405's four commits + the auth docs;
  fast-forward 5bf5b4e2..9d437e10, remote URL stayed token-free.
- CI build 42622715804 (9d437e10) SUCCESS at job AND step level: web
  job (wasm 31,153,413 B, shell VER 9d437e104379 sha aaa9fb15…, gz/br
  kit artifact, gh-pages orphan deploy ddb9dee9) + android job (gogio
  arm64 APK artifact).
- Live verification (§4, the owner's exact report path, agent-browser/
  playwright chromium): https://darkreaperboy.github.io/Uniclient/ at
  1440x900 AND 390x844 — HUD display:none, canvasCount 1, canvas
  pixel-sampled 254,247,255 = #FEF7FF material Light Surface (the
  zero-account InitialModel), status "Running — Uniclient" detail
  "v9d437e1 · 29.7 MB · downloaded", console + page errors clean.
  The stuck-boot report is closed end-to-end; the js leg of the fix is
  live-confirmed (android stays N-1, NEEDS_OWNER).
- Toolchain: sandbox had recycled again — Go 1.27.3 reinstalled per the
  env.sh recipe, module cache symlinked from the surviving ~/go/pkg
  (966 MB), go mod download green.
- Next: the GUI front — keyboard routing.

## Session 404 — the owner's CI builder: build.yml + the loader (2026-11-09)

- Owner redirect (chat): "i want github actions to do this, not to
  actually build it. delete local shit. add to agents.md that i have
  no access to your local sandbox… configure the whole thing." — the
  android/web targets are CI products, never sandbox hand-offs.
  Context: the owner dispatched Release today (run 42589237640,
  cancelled) and saw no android/web legs — they were parked in H-2
  pending exactly this order.
- build.yml (new; push main + v* + dispatch; parallel; ZERO tests —
  §1.5): web job = the proven v0.10.3 wasm recipe (GOOS=js
  GOARCH=wasm, -trimpath -s -w, -p 1 GOMEMLIMIT=900MiB) + a
  CI-generated shell (main stays JS/HTML-free, §1.1): index.html
  loader — streamed download w/ %, MB, live speed (1.5 s sliding
  window) + ETA; version-keyed Cache API (same version = zero
  network, works offline); sha256 integrity pinned at build time
  (mismatch -> purge + one cache-busted reload); stale-version sweep;
  sw.js (network-first shell, wasm passthrough — offline boot);
  Telegram bridge (UA-gated lazy telegram-web-app.js:
  ready/expand/themeParams -> CSS vars — the telegram-loadable page
  the owner asked for); console mirror into the boot HUD; canvas
  MutationObserver overlay drop (v0.10.3 lineage) -> orphan gh-pages
  force-push (main + tag refs only); web-kit artifact w/ gzip -9 +
  brotli -q 11 siblings (gzip_static/brotli_static self-hosting).
  android job = the proven v0.10.3 gogio recipe verbatim
  (gogio@v0.10.0, NDK 27.0.12077973, build-tools 35.0.0, android-34,
  arm64, minsdk 24) -> uniclient-android artifact. gogio@v0.10.3
  install verified locally before writing the job.
- release.yml: android leg re-added — tag releases ship uniclient.apk
  again (v0.10.3 parity). README APK/web paragraph updated. AGENTS:
  §1.4 (gh-pages deploy returned, shell CI-generated), §1.5 (the CI
  split), §1.22 (sandbox invisibility — owner order), §8 (build.yml +
  APK on tags), §11 (Pages verified serving).
- The android leg found parked-leg rot immediately (its whole
  purpose): two android-only audio files the session-368 export
  sweep missed — no local gate compiles //go:build android (purego's
  android backend needs cgo/NDK). 4e612bd6 jni_android.go (15
  undefined JNIEnv*/JniVersion16 ordinals; run 42595087192) +
  bcb7dee0 opensl_android.go (openslDevice methods exported to
  satisfy audio.Device + OutputMix/DeviceType/DeviceID literals;
  run 42596604329) — both git diff -w = pure renames; gofmt,
  comment ban, linux build, tests/audio green locally each time.
- Wasm truth: 31,153,413 B — the old 88,659,256 figure was v0.9.1's
  full-old-GUI build; the headless host is 31.2 MB (D-3's diet still
  applies). APK artifact 12.1 MB; web kit 19.9 MB (gzip -9 + brotli
  -q 11 siblings for gzip_static/brotli_static self-hosting).
- Local build artifacts: none existed — fresh sandbox boot (the prior
  conversation's local APK/web builds died with its sandbox; only
  .tools/go, the gate toolchain, remains). The /tmp/gobin gogio test
  install removed.
- Evidence: build 42597570851 (bcb7dee0) SUCCESS job+step — both
  jobs, every step; verify 42596637204 (531c134f) SUCCESS job+step
  (all 3 jobs); gh-pages orphan "Web build for main (bcb7dee0…)";
  https://darkreaperboy.github.io/Uniclient/ serving VER bcb7dee06da9
  with WASM_BYTES = 31,153,413 matching the served bytes (31,153,413
  B, HTTP 200); artifacts uniclient-android 12.1 MB + uniclient-web
  19.9 MB on the run.

## Session 403 — the field mouse gestures: the app wiring (2026-11-09)

- Boot: the sandbox recycled to zero again (second wipe today — the
  402 checkout and .tools gone; nothing pushed was lost: repo
  re-cloned from origin, Go 1.27.3 + module cache rebuilt). Boot
  verifies first: 42544011545 (23b21e34) + 42544938478 (23277542)
  both SUCCESS job+step (all 3 jobs, every step).
- Law (qwidgettextcontrol.cpp, qt/qtbase dev, re-fetched raw — the
  402 atomic-4 mined law confirmed and completed): PRESS = hitTest
  FuzzyHit (= XToColumn nearest, line clamped) -> MoveAnchor;
  setPosition with mode != KeepAnchor clears selectedWord/
  selectedBlock (qtextcursor.cpp 546-548); Shift+press = blockwise/
  wordwise extend if armed else KeepAnchor; press inside a selection
  might start DnD (no DnD model — skipped, pinned). DOUBLE =
  setCursorPosition then select(WordUnderCursor) iff the wrap line
  has runes; the dblclick sets NO mousePressed; arms trippleClick-
  Timer (400) + point. Window-platform synthesis pin (mine): second
  press within MouseDoubleClickInterval 400 (QPlatformTheme default)
  AND manhattan < startDragDistance 10 — QApplication's synthesis is
  platform-level; 10 is the reference's own triple idiom. TRIPLE =
  press while the timer lives within 10px manhattan, checked BEFORE
  the hit test, on the CURRENT CURSOR's block: StartOfBlock +
  EndOfBlock KA + NextCharacter KA = the block INCLUDING its '\n'
  (NextCharacter fails at doc end); stores selectedBlock; stops the
  timer. DRAG = blockwise if armed, wordwise if armed, else straight
  KeepAnchor extend (mouseMoveEvent 1707-1719; wordSelectionEnabled
  false — the ctor default, never enabled by the reference); NO
  ensureCursorVisible on drag (autoscroll deferred, source
  1721-1723). extendWordwise = inside-word restore, StartOfWord/
  EndOfWord no-op bails (movePosition fails iff the position does
  not move — qtextcursor.cpp 305-640), same-wrap-line guard, the
  mouseX-in-[wordStartX,wordEndX] gate, the #39164 keep-the-word
  anchor law, the nearest-end-by-X pick; extendBlockwise = inside
  restore, down = EndOfBlock+NextCharacter, up = StartOfBlock.
  RELEASE clears mousePressed only (clipboard paths deferred).
  Blink = cursorFlashTime 1000 (QPlatformTheme default) / 2 = 500ms
  toggle; while selected cursorOn &= SH_BlinkCursorWhenTextSelected
  (QStyle default 0) — hides at the NEXT toggle, not instantly;
  focus-in lights + restarts (setCursorVisible ->
  updateCursorBlinking 691-714). setPosition always setX()
  (qtextcursor.cpp 1563) -> every mouse op sets GoalX (the clicked
  column becomes the vertical-move goal).
- Go: ui/app/compose.go — ChatComposeState gains Focused/CursorOn/
  NextBlinkAt/MousePressed/Grab/LastClick{Set,At,X,Y}/TrippleClick-
  {Deadline,X,Y}/WordSel{Active,Anchor,Cursor}/BlockSel{...}; msgs
  ChatComposePressed{X,Y,Shift,Now}/Dragged/Released; composePressed
  (focus-transition-gated blink restart; triple/double/plain+shift
  branches; the last-click chain), composeDragged, composeReleased,
  composeBlinkTick, ChatComposeBlinkActive; composeFieldHitAt +
  composeHitTest; composeExtendBlockwise/Wordwise. ui/text:
  MoveStartOfBlock/MoveEndOfBlock (the '\n' boundary scans).
  tokens: MouseDoubleClickIntervalMs 400 + CursorFlashTimeMs 1000
  (Qt defaults; the distance gate reuses TouchDragStartDistance 10 —
  one Qt constant, one token). Routing: pressChat hits the field
  FIRST (mouse AND touch — a field touch never starts list
  scrolling), non-field presses break the double-click chain
  (QApplication's per-widget synthesis law); dragChat/releaseChat
  route on Grab; ChatPressCanceled clears Grab + MousePressed + the
  chain. ChatPressed gains Shift (window: e.Modifiers&key.ModShift).
  Projection: ComposePaneView.CaretOn; the painter gates the caret
  fill; the window tick + invalidate join ChatComposeBlinkActive.
- RED -> GREEN after 6 test-side slips of mine (an out-of-contract
  drag msg, the 400/500/600 sequence was double/triple/double,
  800->900 was itself a double, the list-press placement between the
  pair, a double-toggle blink check, the instant-hide assumption) —
  the engine was right every time; each fix re-traced against the
  source before touching the test.
- 14 new tests (12 gui + 2 text), 433 total = 230 ui + 182 gui + 21
  text. quick GREEN; js/wasm compile ui/... GREEN; comment ban
  clean; gotd legs OOM on this 4GiB box (§9 rung 7 — CI verify is
  the gate).

## Session 402 — the compose Elm wiring: ChatComposeState (2026-11-09)

- Boot: sandbox recycled to zero again — repo re-cloned at b6cfb704,
  Go 1.27.1 + module cache rebuilt, ayu-ref re-fetched (the sparse
  patterns targeted SourceFiles/ at the repo root but this tree nests
  under Telegram/ — disabled sparse, checked out, inited lib_ui
  e3d05822 + lib_base de35c7ab). No owed verify (401 closed by
  42526363086 SUCCESS job+step).
- Law: history_widget updateControlsGeometry -> updateFieldSize ->
  moveFieldControls chain (resize re-wraps, field width law = 398);
  fieldResized chain: _field->heightChanges -> moveFieldControls +
  updateHistoryGeometry — typing resizes the bar AND the scroll area;
  updateHistoryGeometry 8652-8700: scrollH = paneH - (fieldHeight +
  2*sendPadding) when canSend/editing, else the list keeps the pane;
  bottom-pin law: wasAtBottom = Top >= scrollTopMax -> newScrollTop =
  countAutomaticScrollTop = ScrollMax (bottom; 8533-8551 — no unread
  model yet), else keep Top clamped. input_field keyPressEventInner
  4482: nav keys fall to QTextEdit default = the 401 engine ops;
  ensureCursorVisible after every non-modifier key; Enter ->
  _submits.fire (later slice); customUpDown: Up/Down/PageUp/PageDown
  ignored by the field (history_widget intercepts when empty — later
  slice). Qt movePosition MoveAnchor: Right with a selection collapses
  to max WITHOUT stepping (Left to min) — pinned.
- Go: ui/app/compose.go — ChatComposeState{CanSend, Text, Cursor,
  Anchor, Scroll, GoalX, HasGoalX, Metrics} on the Model; msgs
  ChatComposeTyped / Backspace{Word} / Delete{Word} / CursorKey{Dir,
  Select} (10 dirs: left/right/up/down/home/end/doc-home/doc-end/
  word-left/right) / SelectAll; edits = engine InsertAt/Delete* with
  selection replacement; cursor keys = engine moves with goal-x law
  (horizontal+doc moves set the goal, vertical hops consume+persist,
  edits clear it — my call, avoids stale-goal jumps); ensureCursorVisible
  (ComposeFieldScrollOffset minimal reveal) rides every cursor change;
  composeViewportSync (wasAtBottom bottom-pin) wired into Resized +
  every compose msg; ComposeFieldHeight / ComposeGeometry projections.
  CanSend=false = the bar is hidden: msgs no-op, viewport keeps the
  pane (AGENTS §1.9 — capabilities arrive with the engine wiring; the
  field never fakes). history.ComposeFieldWidth extracted (the bar
  geometry refactored onto it — one law). ui/text nil-Advance guard
  (advance() = zero-width) — a zero Metrics can never panic.
- RED -> GREEN after 6 of MY OWN test-side slips (selection indices
  twice, word-delete space arithmetic, the MoveAnchor no-step law,
  mid-cursor insert scroll expectation, at-bottom max 454 not 546) —
  the engine was right every time; pins now match the reference.
- 12 new tests (10 gui + 1 text + 1 ui), 410 total = 230 ui + 163 gui
  + 17 text. quick gate GREEN; js/wasm compile ui/... GREEN; comment
  ban clean. Verify <PENDING>.
