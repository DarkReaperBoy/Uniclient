# WORKLOG.md — the state file

Top: the **STATE block** — rewritten every session, the resume pointer for the next
agent. Then open items (severity order), then entries newest-first, terse (did /
evidence / next). The pre-2026-11-01 progress docs (BUGS.md, research/) were purged by
owner order — that history lives in git if ever needed.

## STATE

- front: GUI rebuild (§6); the W-1 chrome slice landed (session
  408 — the zero-account scene paints the frame); next front work:
  the search filter semantics, then the engine->UI bridge (the
  account-driven empty state), then D-4 atomic 2
- next: filter semantics, engine bridge, D-4 atomic 2, D-3; token in
  .env (§0.2)
- owner-waiting: N-1 — install the uniclient-android APK artifact
  (build 42622715804) on a device and report (android GUI-default check)
- last-gate: session 408 local — quick gate GREEN (native vet+test,
  windows vet), comment ban clean, js/wasm build 31,183,083 B driven
  under the real CI shell on localhost: 1440x900 + 390x844 panes/band/
  pill painted, click->ring+caret, typed "ab" + caret follows + blink
  ON/off at 500ms, geometry pixel-exact (pill 7..502 x 9..43); CI push
  run dispatched after the commit (record in next session)

## Open items

| ID | where | what | evidence | next step |
|---|---|---|---|---|
| W-1 | ui/app InitialModel | CLOSED 2026-11-09 (session 408): the zero-account scene now paints the frame — dialogs column SurfaceContainerLow vs chat Surface, 54dp header band, the reference-measured search field (7,9,W-18,35 r18) with real focus/typing/backspace/blink; driven live at 1440x900 + 390x844 (pixel scan: pill exact, ring+caret+typed text verified). The residual — the engine-driven add-account affordance — moved to the new front item below | session 408 driven journey | done |
| W-2 | app/engine bridge | the GUI runs window.Run() with ZERO engine wiring — no bootstrap.Init on the gui path, nothing ever sends DialogsLoaded/ChatLoaded (grep: test-only senders); the search field filters nothing yet; the honest account-driven empty state ("add an account") needs the pump: engine events -> Msgs, account list in Model, dialogs/chat feeds | session 408 recon (PaintComposeBar also has zero callers — the compose bar is painted by nobody) | the bridge atomic: gui path boots the engine, pump goroutine, Accounts in Model; then the search filter semantics atomic (rows exist -> filter pinned by tests) |
| N-1 | android APK | GUI-default on android is runtime-unverifiable in-sandbox (no emulator/device); expected: the empty Material surface, not a black zombie | session 405 (js sibling); js live-verified in 406; APK artifact on build 42622715804 | owner installs the uniclient-android APK artifact and reports |
| H-2 | verify/release yml | CLOSED 2026-11-09 (owner order): android + web legs returned as build.yml (per-push, no tests, parallel); only the Xvfb GUI + Puppeteer web-drive legs stay parked with the rebuilt GUI | AGENTS.md §8; build 42597570851 | Xvfb/Puppeteer return when the GUI ships (§6.7) |
| H-3 | engine/cores API | 301+1 identifiers exported purely for the tests move (API noise: TsParseInit1, TsTrackRecvPID; audio's MicStop folded to micStop in session 368) | commit 27faa5a4, session 368 | fold into real APIs or de-export when tests are reworked during the GUI rebuild |
| D-1 | ui/history corner button | down-button unread-count badge (22dp, centered x, top 0 — jump_down_button.cpp paintEvent + historyToDownBadge*) + hover/over colors + ripple deferred: no unread counter in the chat Item model yet, no hover/ripple machinery in the skin yet; replyReturn branch of downClick + loadedAtBottom==false state return with reply-return jumps / below-history pagination | jump_down_button.cpp 33-52, corner_buttons.cpp 139-145 | badge returns with read-state counts; over/ripple with the skin's hover+ripple pass |
| D-2 | ui/history unread-things buttons | read-marking absent for mentions AND reactions: after a jump the button stays shown (reference hides it when the server marks the thing read — updateUnreadThingsVisibility is server-data-driven); mentionsClick's already-there voice/video media-read branch (5623) deferred — no media model; unread-count badges join D-1's class; poll-votes 4th stack slot returns with a poll model | history_view_corner_buttons.cpp 147-190, 288-345 | returns with engine unread-things events + the media pass |
| D-3 | build.yml web job | wasm size diet: the js/wasm build ships every core incl. the six raw-TCP backends that can never connect from a browser (§7 web truth) — build-tag exclusion at the engine factory projected <20 MB; also headroom under git's 100 MB file ceiling on gh-pages | headless-host wasm = 31,162,944 B after the keyboard atomic (v0.9.1's old-GUI build was 88,659,256 B) | one atomic with tests: bootstrap factory js variant + per-core js stubs |
| D-4 | window keys — atomic 2 | Enter=submit (ShouldSubmit law: default Enter-mode = plain Enter/Return submits, Shift/Ctrl+Return newline — already mapped) -> ChatComposeSubmitted + send-request seam (ChatBottomRequested-pattern) + field clear; Up/Down/PageUp/PageDown = history scroll (never compose cursor moves — customUpDown law); Up on EMPTY field + canWrite + !edit + !reply -> edit last editable message, else scroll; Ctrl+Up/Down -> reply prev/next (reply front) | AyuGramDesktop dev history_widget.cpp 9276-9349 (fetched 2026-11-09): Down always _scroll->keyPressEvent; Up scrolls unless field empty && canWrite && !_editMsgId && !_replyTo, then lastEditableMessage() -> editMessage else scroll; PageUp/PageDown always scroll; Enter -> ShouldSubmit(sendSubmitWay, mods); Qt key scroll = SliderSingleStep/PageStep (qabstractscrollarea.cpp 1215-1220; qabstractslider.cpp 180: defaults singleStep 1 pageStep 10 — but our own wheel law 120-angle notch = 60px = WheelScrollLines 3 => singleStep = 20px = WheelNotchAngleDelta/WheelScrollLines/WheelPixelToAngleDelta); IME ranged EditEvents + SelectionCmd/SnippetCmd contract = the mobile/IME front | atomic 2: ChatComposeSubmitted + ChatComposeSendRequested + scroll keys with the 20px singleStep law; edit-last rides the messages/edit front |

## Session 408 — full recon (owner order) + W-1 closed: the zero-account frame (2026-11-09)

- Owner redirect: "still broken, do full recon before continuing." Recon
  first, then the fix. Recon findings (all command-verified this session):
  local main == origin/main == a85ec25a, clean tree; PRs #1/#3 = old
  closed owner test/doc PRs (irrelevant); CI Build #8 (42647039235,
  dispatched on a85ec25a, unrecorded in STATE until now) all five jobs
  SUCCESS + Pages deploy e0e69862 green — the live URL serves VER
  a85ec25a, wasm 31,162,944 B; live drive (agent-browser, 1440x900 +
  390x844): boots clean (HUD none, canvas 1, console + page errors
  empty) but the viewport is STILL 100.00% one color #FEF7FF — the
  owner's "still broken" = W-1, confirmed with this session's own eyes.
  Code-level root cause mapped: window.go paints Background + two panes;
  dialogs PaintPane draws rows only; chat PaintChatPane early-returns
  at Count<=0; PaintComposeBar has ZERO callers (dead code — W-2);
  the gui path runs window.Run() with no engine wiring at all.
- W-1 atomic (the visible frame): tokens measured from the reference —
  dialogs.style dialogsFilter (heightMin 35, radius 18, textMargins
  12/8/30/5, borderActive 2), dialogsFilterPadding 7/7, dialogsFilterSkip
  4, the top bar 54 (info.style topBarHeight — already in the table),
  composition from dialogs_widget.cpp updateControlsGeometry 4642-4710:
  filterLeft = padX + menuW + padX (54 with the hamburger, 7 without —
  the hamburger is DEFERRED to the menu front: no working menu items
  exist, a dead button is banned §1.9), filterRight = skip + padX = 11,
  field top = (54-35)/2 = 9; placeholder = lng_dlg_filter "Search"
  (no leading icon in the reference field). New: ui/dialogs/header.go
  (HeaderView + HeaderLayout + HeaderFieldHit), Pane.Header, app/search.go
  (SearchState + DialogsHeaderPressed/SearchTyped/SearchBackspace/
  SearchFocusLost + focus/blur/blink — the same CursorFlashTimeMs/2
  law), search_keys.go (SearchEditMsg single-line, ranged IME edits nil
  until the IME front — the compose pin; SearchKeyMsg: Backspace only,
  arrows/copy deferred to the field-kit front), window.go routing
  (band press -> DialogsHeaderPressed in pane coords, list events
  shifted -54; routeSearchKeys mirrors routeComposeKeys incl.
  SoftKeyboardCmd; pressDialogs blurs the search — a list press is
  outside the field), painter: the dialogs column fills
  SurfaceContainerLow (M3 list-pane law; the chat column keeps Surface
  — the two-pane split), the band + pill (SurfaceContainerHighest,
  focused ring Primary 2dp) + placeholder OnSurfaceVariant + caret;
  Resized: DialogsScroll.Height = H-54 (the list is a separate
  scrollable below the fixed band, the reference's own structure).
- Tests: dialogs_header_elm_test.go NEW (11 tests: geometry at both
  pane shapes, scroll height, focus journey incl. list-press blur and
  band-press-leaves-list-untouched, typed/backspace, blink law, focus
  lost, zero-account scene pins the header, view projection, paint
  smoke). Deliberate behavior change — the 54dp band — re-pinned in the
  six dialogs test files (scroll clamp 72->126, viewport 300->246,
  load-more line 92->254, wheel accel 270->243 (areaH 246), track jump
  346->486, bar drag scale 33->41, rubber band 702/10/196->750/4/88,
  spring return 700/695/693/692->749/747/746/746, fling settle 692->746,
  to-up press Y 360->306, hidden-bar 4 rows->3) — every pin recomputed
  from the law, not copied: rubber band 44 leftover x2 /20 = 4.4 -> 4,
  spring 4xe^(-12.5t), wheel -60x246/120 = 123. tests/gui 197 (186+11).
- THE CARET BUG (found by the drive, fixed): fillRRect with radius 1 on
  a 2dp-wide rect paints NOTHING on gio/js (degenerate rounded-rect
  path); the ring (radius 20) and pill (18) painted fine, the caret was
  invisible at both blink phases — isolated by two debug builds
  (unconditional gate still invisible; radius 0 + W 8 painted 128px at
  the exact computed geometry 19,18). Fix: caret radius 0 (a 2dp
  hairline has no rounding). Painter law: hairline fills use radius 0.
- Driven journey (§4, the fixed build under the real CI shell on
  localhost, agent-browser): 1440x900 — pixel histogram 64.31%
  #FEF7FF + 34.37% #F7F2FA + 1.29% #E6E0E9 (the split) + #49454F
  (placeholder); pill bounds scanned 7..502 x 9..43 = the measured
  table exactly; click (100,27) -> focus ring 2dp #6750A4 + caret
  2x16 at (19,18); press a,b -> text painted, caret moved to x 34-35
  (follows the text); blink over 5 shots: ON off ON ON off (500ms
  law); 390x844 single-pane: pill + ring visible (95.73% container +
  3.72% pill). Console + page errors clean at both sizes.
- Gates: quick gate GREEN (native vet+test scoped, windows vet for the
  gio legs), gofmt clean, comment ban clean, js/wasm full build green
  31,183,083 B. Boot: sandbox had recycled to zero (Go 1.27.3
  reinstalled per env.sh, module cache refilled).
- Docs: README web paragraph now says what the page shows (frame +
  empty lists until the bridge lands); STATE records Build #8; W-1
  CLOSED, W-2 opened (the engine->UI bridge — the add-account
  affordance needs it; the search filter semantics ride it too).

## Session 407 — the md truth audit (owner order) + the whitescreen verdict (2026-11-09)

- Owner redirect: "make sure the md files are correct before you proceed
  to fix anything" — audit first, zero code changes; the question set
  (linux/windows builds, the whitescreen, CI parallelism, ayugram
  cloning, per-commit testing) answered from evidence below.
- Boot: the local clone sat STALE at 5bf5b4e2 — origin/main had moved to
  dc2385e0 (session 406: .gitignore anchor, the stuck-boot fix 4069813b,
  shell/README syncs, the .env auth law 9d437e10, the keyboard atomic
  90be7905). Pulled; both mds re-read at the tip. Working tree: 383
  mode-only flips (sandbox-restore artifact, 0 content diffs) —
  core.fileMode=false; nothing unpushed.
- Audit verdict — every checkable claim traced TRUE: test counts (ui 230
  / gui 186 / text 21, static grep); build 42629204319 SUCCESS (run
  page: head 90be790, 4m37s); release.yml ships linux amd64+arm64 +
  windows + android (TAG-gated; latest tag v0.10.3 — that is why recent
  runs show no linux/windows: per-push Build is web+android, §1.5);
  build jobs parallel (no needs chain); ui/tokens 487 lines (AyuGram =
  the FREE GPLv3 desktop repo; measurements only, zero code copy §6.8);
  AGENTS §1.4 == main.go:21 guiDefault; live Pages 200,
  WASM_BYTES == content-length == 31,162,944.
- Corrected in this commit: STATE's "Pages live on VER 90be790587cb"
  (true at its 13:58Z write) — a DISPATCHED Build #6 (14:54:20Z, manual,
  unrecorded) redeployed main@dc2385e0: live VER dc2385e08410, recorded
  now; AGENTS §1.5/§8 now state the paths filter (doc-only pushes skip);
  README's web paragraph says what the page looks like today; sessions
  405/406 reordered newest-first; session 402 pruned for the line cap.
- The whitescreen verdict ("idk if it is me"): NOT the owner. Live drive
  (agent-browser, the real URL, 1440x900 + 390x844): boots — canvas 1,
  HUD display:none, "Running — Uniclient", VER dc2385e08410, sha pin
  match, console clean — but the viewport is 100.0% ONE color #FEF7FF
  (pixel scan) at BOTH sizes: the zero-account InitialModel paints
  background only. Working as built; indistinguishable from broken =
  W-1 (degraded UX). The prior stuck-boot (headless default blocking on
  js signals) was real — fixed 4069813b, verified then.
- Gap admitted + closed: 90be7905 (user-facing) landed without a §4
  browser drive; this drive closes it — boots clean, the flat surface
  is the residual finding (W-1).
- Second atomic (owner question, mds already green): build.yml gains
  linux (amd64+arm64 matrix — the release.yml cgo recipe verbatim,
  Gio client libs) + windows (pure-Go cross) jobs — five parallel
  runs, no needs-chain; per-push artifacts now cover every platform.
  The "why no linux+windows" answer: they were always tag-gated in
  release.yml (latest tag v0.10.3 = the last shipped set); the §1.5
  per-push Build was web+android only until now. README artifacts
  sentence updated in-commit.

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
- Atomic 2 of the session (keyboard routing, slice 1 — the compose
  field takes keyboard input): ui/window routeComposeKeys — gio focus
  mirroring (Model Focused&&CanSend <-> key.FocusCmd on the chat input
  tag + SoftKeyboardCmd on transitions, the touch platforms' keyboard),
  key.FocusFilter EditEvents -> app.ComposeEditMsg (empty-range text ->
  ChatComposeTyped; ranged IME edits nil until the IME front),
  key.Filter{Focus: tag, Optional: Shift|Ctrl} key.Events ->
  app.ComposeKeyMsg (State Press only, Alt/Super dropped): arrows /
  Home/End / Ctrl-word / Shift-select / Backspace/Delete / Ctrl+A /
  Shift+Return and Ctrl+Return -> newline (tdesktop Enter-mode default);
  plain Return + Up/Down/PageUp/PageDown/Escape/Tab intentionally unmapped
  (chat-surface keys — D-4 atomic 2). ChatComposeFocusLost on gio
  FocusEvent loss: Focused+CursorOn drop, text/cursor survive, re-press
  refocuses. Laws verified in source this session: gio xkb DispatchKey
  (xkb_unix.go 199-212: printable + no Ctrl/Alt/Super -> EditEvent,
  letters' key.Event Names upper-cased = shortcuts only), gio filter
  matching (io/input/key.go 264-277: undeclared modifiers never match —
  hence Optional: Shift|Ctrl), js backend (os_js.go 570-594: Return
  preventDefault -> no EditEvent newline, key.Event only). 4 new tests
  (mapping table + ignores + edit + focus-lost journey): tests/gui 186,
  UI trio 437 = 230 ui + 186 gui + 21 text.
- Next: D-4 atomic 2 (Enter submit + history scroll keys), then D-3.

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

