# WORKLOG.md — the state file

Top: the **STATE block** — rewritten every session, the resume pointer for the next
agent. Then open items (severity order), then entries newest-first, terse (did /
evidence / next). The pre-2026-11-01 progress docs (BUGS.md, research/) were purged by
owner order — that history lives in git if ever needed.

## STATE

- front: session 404 (owner redirect 2026-11-09: "github actions does
  the building, never the sandbox") — build.yml live: per-push on
  main, no tests, parallel — web (js/wasm + CI-generated loader:
  progress/speed/ETA, version-keyed cache, sha256 integrity, offline
  SW, Telegram bridge -> orphan gh-pages + gz/br kit artifact) +
  android (gogio arm64 APK); release.yml re-ships the APK on tags;
  AGENTS §1.22 sandbox invisibility (owner order); Pages re-enabled
- next: the GUI front resumes — keyboard routing (window key.Event ->
  the compose msgs; Enter=send + Up/Down history when empty); then D-3
- owner-waiting: none
- last-gate: build run <ID> <RESULT> job+step; Pages
  https://darkreaperboy.github.io/Uniclient/ live; no Go change this
  slice (comment ban clean; verify 42584000646 stands for e6aa0bbd)

## Open items

| ID | where | what | evidence | next step |
|---|---|---|---|---|
| H-2 | verify/release yml | CLOSED 2026-11-09 (owner order): android + web legs returned as build.yml (per-push, no tests, parallel); only the Xvfb GUI + Puppeteer web-drive legs stay parked with the rebuilt GUI | AGENTS.md §8; build run <ID> | Xvfb/Puppeteer return when the GUI ships (§6.7) |
| H-3 | engine/cores API | 301+1 identifiers exported purely for the tests move (API noise: TsParseInit1, TsTrackRecvPID; audio's MicStop folded to micStop in session 368) | commit 27faa5a4, session 368 | fold into real APIs or de-export when tests are reworked during the GUI rebuild |
| D-1 | ui/history corner button | down-button unread-count badge (22dp, centered x, top 0 — jump_down_button.cpp paintEvent + historyToDownBadge*) + hover/over colors + ripple deferred: no unread counter in the chat Item model yet, no hover/ripple machinery in the skin yet; replyReturn branch of downClick + loadedAtBottom==false state return with reply-return jumps / below-history pagination | jump_down_button.cpp 33-52, corner_buttons.cpp 139-145 | badge returns with read-state counts; over/ripple with the skin's hover+ripple pass |
| D-2 | ui/history unread-things buttons | read-marking absent for mentions AND reactions: after a jump the button stays shown (reference hides it when the server marks the thing read — updateUnreadThingsVisibility is server-data-driven); mentionsClick's already-there voice/video media-read branch (5623) deferred — no media model; unread-count badges join D-1's class; poll-votes 4th stack slot returns with a poll model | history_view_corner_buttons.cpp 147-190, 288-345 | returns with engine unread-things events + the media pass |
| D-3 | build.yml web job | wasm size diet: the js/wasm build ships every core incl. the six raw-TCP backends that can never connect from a browser (§7 web truth) — build-tag exclusion at the engine factory projected <20 MB; also headroom under git's 100 MB file ceiling on gh-pages | v0.9.1 gh-pages uniclient.wasm = 88,659,256 B | one atomic with tests: bootstrap factory js variant + per-core js stubs |

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
  APK on tags), §11 (Pages rung done under this order).
- Local build artifacts: none existed — fresh sandbox boot (the prior
  conversation's local APK/web builds died with its sandbox; only
  .tools/go, the gate toolchain, remains). The /tmp/gobin gogio test
  install removed.
- Evidence: build run <ID> <RESULT>; gh-pages orphan; Pages URL; the
  artifacts. Recorded post-run.

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

## Session 402 atomic 4 — the word-ops for the mouse law + the mined gesture law (2026-11-09)

- Law (Qt qwidgettextcontrol.cpp + qtextcursor.cpp, fetched from
  qt/qtbase dev — the input_field itself has no mouse overrides):
  PRESS = hitTest FuzzyHit (= 401 XToColumn nearest) -> MoveAnchor
  (cursor set, selection cleared); Shift+press = KeepAnchor extend;
  press inside a selection may start a DnD drag (no DnD model —
  skip). DOUBLE-CLICK = setCursorPosition then select(WordUnderCursor)
  iff the line has text; WordUnderCursor = StartOfWord (MoveAnchor:
  block-end + space/sep before = stay; else peek +1 then a PreviousWord
  walk) + EndOfWord (KeepAnchor: classify the rune AT the position —
  separator run or word run; fails at doc end or '\n' -> empty
  selection; clicking ON a space selects the PRECEDING word) ;
  trippleClickTimer = doubleClickInterval; selectedWord stored.
  TRIPLE-CLICK (within startDragDistance of the stored point while
  the timer lives) = StartOfBlock + EndOfBlock KeepAnchor +
  NextCharacter KeepAnchor = the whole line INCLUDING its '\n'.
  DRAG (move with left held) = hitTest -> KeepAnchor extend (word-
  wise/block-wise extension only after a double/triple click — the
  plain drag is a straight anchor extension; autoscroll deferred).
  RELEASE = clears mousePressed (selection settles; clipboard
  selection deferred). Caret blink = styleHints cursorFlashTime/2,
  pauses while a selection exists unless the style hints say
  otherwise.
- Go: ui/text MoveStartOfWord / MoveEndOfWord (the two engine ops
  the app wiring needs next session — flat-model mapping: '\n' is a
  block boundary rune; Qt's block-relative len-1 = our doc end or
  the '\n' position). RED -> GREEN clean. 2 new tests, 419 total =
  230 ui + 170 gui + 19 text. quick GREEN; js/wasm ui/... GREEN;
  comment ban clean. Verifies: 42543314028 (913f6c68) SUCCESS
  job+step; 42544011545 (23b21e34) in flight; this atomic's verify
  dispatched on push.

## Session 402 atomic 3 — the compose bar render painter (2026-11-09)

- Law: historyComposeField (chat_helpers.style 1281-1300) — border 0,
  borderActive 0, borderRadius 0 -> InputField::paintFlatSurrounding
  (input_field.cpp 2846-2852): a FLAT textBg = historyComposeAreaBg =
  msgInBg rect, no border, no rounding. Icon placement: attach/smile
  on the centered 40x40 ripple canvas (2,3) + their padded cells
  (11,9)/(15,17); send at the pinned (10,11) + cell (2,2) — fillGlyph
  composes button+canvas+cell. Colors map Material: field bg
  SurfaceContainerHigh (the msgInBg convention), text/caret OnSurface,
  selection PrimaryContainer, placeholder OnSurfaceVariant with the
  fade alpha, send icon Primary (the accent), attach/smile
  OnSurfaceVariant.
- Go: render.PaintComposeBar — field bg fill, clip to the field rect,
  -Scroll translate: selection spans (span.Line*lineH rows), line
  labels (fontRegular FontBase — the shaper paints the line runes the
  model wrapped; the real metrics adapter reconciles when the gio
  shaper lands), caret rect (1xlineH OnSurface); placeholder label
  outside the translate (never scrolls) at X with opacity alpha; the
  glyph trio with zero-rect guards (hidden buttons never painted).
  Window integration: PaintComposeBar after PaintChatPane in the chat
  column; ChatComposePlaceholderActive joins the tick + invalidate
  conditions. Keyboard routing to the compose msgs = the next window
  slice (pointer-only today). Caret blink deferred (painter timing).
- The render package vets CGO_ENABLED=0 — op recording is pure; the
  smoke test paints shown/selected/hidden/zero panes without panic
  (the corner-button painter precedent: thin fills ride CI verify).
  1 new test, 417 total = 230 ui + 170 gui + 17 text. quick GREEN;
  windows vet GREEN; js/wasm ui/... GREEN; comment ban clean. Verify
  42542765446 (381a7f3e) SUCCESS job+step — all 3 jobs, every step.

## Session 402 atomic 2 — the placeholder fade law + the ComposePane projection (2026-11-09)

- Law: input_field startPlaceholderAnimation 2911-2927 — shifted =
  textLength > placeholderAfterSymbols (compose: 0 -> pure len>0);
  Animations::Simple linear (animations.h 62-67 default) over
  st.duration 100; paintPlaceholder 2951-2962: painted iff degree < 1
  (NOT textLen==0 — the settled law only picks the anim target),
  opacity 1-deg, left = interpolate(0, -shift, deg) — the mid-fade
  frames paint over non-empty text.
- Go: ChatComposeState gains Placeholder + the anim set (Shifted/
  Degree/From/To/Started/Anim); text-edit msgs carry Now (data-arrival
  clock, session-396 law); composePlaceholderCheck on every edit
  (transition-only, no restart mid-anim — degree holds between ticks,
  event-driven), composePlaceholderTick rides ChatTick; ComposePane()
  projection (Shown/Geometry/LineHeight/Scroll/Lines/Caret/Selection/
  Placeholder{Text elided, X, Baseline, Opacity}) + ChatPane.Compose
  riding View. Empty Placeholder = nothing painted (peer data arrives
  with the engine wiring — AGENTS 1.9).
- RED -> GREEN after 1 wiring bug of mine (used the settled law for
  the paint condition — reference paints on degree<1) + 1 test-side
  slip (wall-clock vs event-driven degree). 6 new gui tests, 416
  total = 230 ui + 169 gui + 17 text. quick GREEN; js/wasm ui/...
  GREEN; comment ban clean. Verify for 381a7f3e: 42542765446 in
  flight at push time.

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
