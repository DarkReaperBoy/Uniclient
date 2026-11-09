# WORKLOG.md — the state file

Top: the **STATE block** — rewritten every session, the resume pointer for the next
agent. Then open items (severity order), then entries newest-first, terse (did /
evidence / next). The pre-2026-11-01 progress docs (BUGS.md, research/) were purged by
owner order — that history lives in git if ever needed.

## STATE

- front: session 402 — the compose front is wired end-to-end:
  ChatComposeState (Elm msgs on the 401 engine, viewport bottom-pin,
  placeholder 100ms fade, ComposePane projection) + the render
  painter + the window leg + the word-ops for the mouse law
- next: the field mouse gestures (the FULL law is mined in the
  atomic-4 entry below — press FuzzyHit MoveAnchor / shift-extend,
  double-click WordUnderCursor via MoveStartOfWord+MoveEndOfWord
  with the stay/peek laws, triple-click whole-line-including-newline
  via the doubleClickInterval timer, drag KeepAnchor extend, caret
  blink flashTime/2) -> ChatComposePressed/DoubleClicked/Dragged/
  Released msgs + Focused state riding them; then keyboard routing
  (window key.Event -> the compose msgs, pure fn mapping like
  WheelDelta; focus gates it); Enter=send + Up/Down history when
  empty (customUpDown + history_widget); send-button type crossfade
  120ms; real font metrics adapter when the gio shaper lands
- owner-waiting: none
- last-gate: quick GREEN (402 all four atomics); js/wasm compile
  ui/... GREEN; comment ban clean; 419 tests (230 ui + 170 gui + 19
  text) green locally; verifies 42542765446 (381a7f3e) and
  42543314028 (913f6c68) SUCCESS job+step; 42544011545 (23b21e34)
  in flight; 23277542's verify = 42544938478 (boot checks both at
  job+step level); session 401 pruned to hold the line cap

## Open items

| ID | where | what | evidence | next step |
|---|---|---|---|---|
| H-2 | verify/release yml | android APK + web (gh-pages) + Xvfb GUI legs parked until the new GUI | AGENTS.md §6/§8 | re-add with the GUI build (owner order pending) |
| H-3 | engine/cores API | 301+1 identifiers exported purely for the tests move (API noise: TsParseInit1, TsTrackRecvPID; audio's MicStop folded to micStop in session 368) | commit 27faa5a4, session 368 | fold into real APIs or de-export when tests are reworked during the GUI rebuild |
| D-1 | ui/history corner button | down-button unread-count badge (22dp, centered x, top 0 — jump_down_button.cpp paintEvent + historyToDownBadge*) + hover/over colors + ripple deferred: no unread counter in the chat Item model yet, no hover/ripple machinery in the skin yet; replyReturn branch of downClick + loadedAtBottom==false state return with reply-return jumps / below-history pagination | jump_down_button.cpp 33-52, corner_buttons.cpp 139-145 | badge returns with read-state counts; over/ripple with the skin's hover+ripple pass |
| D-2 | ui/history unread-things buttons | read-marking absent for mentions AND reactions: after a jump the button stays shown (reference hides it when the server marks the thing read — updateUnreadThingsVisibility is server-data-driven); mentionsClick's already-there voice/video media-read branch (5623) deferred — no media model; unread-count badges join D-1's class; poll-votes 4th stack slot returns with a poll model | history_view_corner_buttons.cpp 147-190, 288-345 | returns with engine unread-things events + the media pass |

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


## Session 393 — the floating scroll-date (2026-11-08)

- ScrollDateAnchor + List.ScrollDateAt (stick/pack-bottom-clamp/inPlace per
  history_inner_widget.cpp 1182-1236 + PaintPreparedDate) + Elm ChatDateState
  (every Top mutation; upward anchor-change 800ms, day-crossing 3000ms latch,
  else hide-now; 200ms fade) + painter at stick position with fade alpha.
  290 PASS. Verify 42499644234 SUCCESS (f27c1bbb). Detail: f27c1bbb + git.

## Session 392 — chat top-edge preload/pagination (2026-11-08)

- PreloadTopNeeded (Top < 2*Height, kPreloadIfLessThanScreens 2) fired from
  every scroll-class surface; ChatPrepended stores viewport top, ChatMeasured
  compensates by summed prepended heights (same content rows stay put);
  MoreAbove = loadedAtTop projection. Deferred: good-for-around anchor scan +
  bottom edge (need row IDs). 280 PASS. Verify 42496692212 SUCCESS.
  Detail: 6ba120d5 + git history.

## Session 391 — chat item interaction: tap/press over the message leg (2026-11-08)

- ChatPressState action machine (prepare-select/prepare-drag/selecting/
  dragging; time-label hit toggles selection-add) + HitBox PointStateOf /
  TimeHit laws per the reference gesture split. 258 PASS. Verify success.
  Detail: git history.

## Session 390 — chat scrollbar bar-drag laws (2026-11-08)

- ElasticScrollBar (lib_ui elastic_scroll.cpp:116-406; chat.style 188-202):
  cut-clamp refreshGeometry, off-thumb press centers the thumb, drag scale +
  pass-through quirks, dead-zone reversal payback; Elm bar drag + ChatPane
  Thumb. 238 PASS. Verify 42487726300 SUCCESS. Detail: 8d39d63e + git.

## Session 386 — the Material icon asset library (2026-11-08)

- Canvas law (codegen_style parsed_file.cpp:967-969 + lib_ui MonoIcon): icon part point(x,y) = QMargins(x,y,0,0) — glyph at cell+(x,y), canvas = mask + point; SVG -WxH renders the FULL viewBox into WxH (chatlist 72 -> 18, scale 0.25); PNG coverage = blue channel (blue>127 at @3x, RDP eps 0.75@3x, /3 grid; crack-boundary walk; contour order = component scan then area-desc, holes wind opposite); SVG legs absolute M/L/C/Z flatten, 12 samples/cubic; IoU vs @2x 0.886-0.957; @3x is the trace source (per-DPI hand-tuned bboxes, pinned).
- 13 glyphs: bot 16x11@(1,3)->17x14, channel 12x11@(3,4)->15x15, forum 19x10@(1,4)->20x14, dialogs sending 11x11@(8,4)->19x15 / sent 12x10@(10,4)->22x14 / received 17x10@(5,4)->22x14, pinned 20x20, chatlist 18x18 x3 (mention/reaction/poll), history sending 11x11@(5,5)->16x16 / sent 13x11@(2,4)->15x15 / received 18x11@(2,4)->20x15.
- TTL timer (ttl_icon.cpp): pen 1.5 round, solid LEFT half-arc 90..270deg one annulus contour with round caps (bottom cap bulges +x, top -x), dotted right half 9 dots r0.75 pitch 3 anchored 3 o'clock (QPainterPath phase ASSUMED — refine vs a live render someday), text 9px semibold clamped 2 chars.
- Selection laws: history.SendStateIcon(out, sending, unread) = bottom_info.cpp 287-300; dialogs.SendStateIcon(state); BadgeReaction split from BadgeMention (mention wins when both). paintMessage feeds Out to TimeLabel + fillGlyphs the icon at iconX/iconY (Item gains Sending/Unread).
- RED 8 -> 2 spec errors fixed by measurement. GREEN 186. d8eedff -> verify 42454857199 SUCCESS (3 jobs, all steps). Detail: git d8eedff5 + this file's history.
