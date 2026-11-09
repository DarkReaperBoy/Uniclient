# WORKLOG.md — the state file

Top: the **STATE block** — rewritten every session, the resume pointer for the next
agent. Then open items (severity order), then entries newest-first, terse (did /
evidence / next). The pre-2026-11-01 progress docs (BUGS.md, research/) were purged by
owner order — that history lives in git if ever needed.

## STATE

- front: session 402 — the compose Elm wiring landed (ChatComposeState
  riding Resized + key/insert/cursor/scroll msgs on the 401 text
  engine; the viewport bottom-pin law; CanSend=false = hidden bar)
- next: the compose bar render painter (gio leg rides CI) — field
  bg/caret/placeholder (100ms fade riding ChatTick) + the 400 glyph
  trio onto ComposeGeometry; then field mouse gestures (click
  position, double-click word, drag select — input_field mouse law);
  Enter=send + Up/Down history when empty (customUpDown +
  history_widget); send-button type crossfade 120ms; real font
  metrics adapter when the gio shaper lands
- owner-waiting: none
- last-gate: quick GREEN (402 both atomics); js/wasm compile ui/...
  GREEN; comment ban clean; 416 tests (230 ui + 169 gui + 17 text)
  green locally; verify 42542765446 (381a7f3e) in flight at last
  push; this atomic's verify dispatched on push

## Open items

| ID | where | what | evidence | next step |
|---|---|---|---|---|
| H-2 | verify/release yml | android APK + web (gh-pages) + Xvfb GUI legs parked until the new GUI | AGENTS.md §6/§8 | re-add with the GUI build (owner order pending) |
| H-3 | engine/cores API | 301+1 identifiers exported purely for the tests move (API noise: TsParseInit1, TsTrackRecvPID; audio's MicStop folded to micStop in session 368) | commit 27faa5a4, session 368 | fold into real APIs or de-export when tests are reworked during the GUI rebuild |
| D-1 | ui/history corner button | down-button unread-count badge (22dp, centered x, top 0 — jump_down_button.cpp paintEvent + historyToDownBadge*) + hover/over colors + ripple deferred: no unread counter in the chat Item model yet, no hover/ripple machinery in the skin yet; replyReturn branch of downClick + loadedAtBottom==false state return with reply-return jumps / below-history pagination | jump_down_button.cpp 33-52, corner_buttons.cpp 139-145 | badge returns with read-state counts; over/ripple with the skin's hover+ripple pass |
| D-2 | ui/history unread-things buttons | read-marking absent for mentions AND reactions: after a jump the button stays shown (reference hides it when the server marks the thing read — updateUnreadThingsVisibility is server-data-driven); mentionsClick's already-there voice/video media-read branch (5623) deferred — no media model; unread-count badges join D-1's class; poll-votes 4th stack slot returns with a poll model | history_view_corner_buttons.cpp 147-190, 288-345 | returns with engine unread-things events + the media pass |

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


## Session 401 — the field text-engine core: metrics, wrap, cursor, placeholder (2026-11-09)

- Boot: sandbox recycled to zero — repo re-cloned at ff787639, Go
  1.27.1 + module cache rebuilt, ayu-ref re-fetched (AyuGramDesktop
  dev, sparse: SourceFiles/{history,ui,chat_helpers,data} + lib_ui
  @e3d05822 + lib_base @de35c7ab). No owed verify (400 closed by
  42517439919).
- Law: chat_helpers.style 1281-1300 historyComposeField (textMargins
  0,0,0,0 overriding defaultInputField's (0,28,0,4) at widgets.style
  1037; placeholderMargins 2,0,2,0; placeholderShift −50;
  placeholderScale 0 → static branch; placeholderFont normalFont;
  duration 100) + basic.style 84-91 defaultTextStyle lineHeight 0.
  input_field.cpp: documentMargin zeroed (1965); contentHeight =
  ceil(doc height) + v-margins, clamped (2821-2842 — feeds 398's
  ComposeFieldHeight); root-frame right margin = cursorWidth+1 = 2
  caret reserve so the caret never clips after the longest line
  (updateRootFrameFormat); BlockLineHeight = lh>0 ? max(lh,fontH) :
  fontH (1148-1152); QTextEditLineAscent = clamp(fixed·4/5 −
  max(fleading,0), 0, fixed) (1154-1163). Placeholder: shown iff
  textLen==0 (startPlaceholderAnimation; history_widget never
  force-hides), right-elided to fieldW−margins (style::font::elided
  = QFontMetrics::elidedText), x = margins.l +
  interpolate(0,−shift,hiddenDeg), baseline = margins.top + ascent,
  opacity 1−deg, 100ms; interpolate = SafeRound = std::round
  half-away (animation_value.h 106-108, lib_base algorithm.cpp 15).
  Wrap = QTextEdit default WrapAtWordBoundaryOrAnywhere
  (qtextedit.cpp): word boundary preferred, mid-word only when the
  word alone exceeds the full width, ≥1 rune per line, spaces glue
  to their line. Cursor line law = Qt lineNumberForTextPosition
  (qtextengine.cpp 3758-3770): first line with from+len+
  trailingSpaces > pos, end-of-text → last line — the boundary
  position after a soft-wrap's trailing space belongs to the NEXT
  line; hard '\n' positions stay on the previous line's end.
- Go: ui/text (Metrics{Height,Leading,Advance}, LineHeight,
  LineAscent, Elide, Layout→Document/Line{Start,Runes,Width},
  CursorAt{Line,Column,X}, Height) + ui/history/compose_field.go
  (WrapWidth −ComposeCaretReserve, Document, ContentHeight,
  placeholder Shown/MaxWidth/Text/X/Baseline/Opacity) + 11 tokens.
  RED (pkg missing) → GREEN; 3 of my own spec bugs caught before
  green (elide dropped the ellipsis; mid-word lineStart accumulator;
  final chunk force-emitted — must stay open for following words) +
  1 test-side off-by-one (offset after trailing space — Qt source
  proved the ENGINE right, test fixed).
- Atomic 2 (95ef00d9 + this): the selection + caret-rect law.
  Qt source: getSelectionBounds (qtextengine.cpp 4135-4160) +
  addSelectedRegionsToPath (qtextlayout.cpp 944-981) — selection
  rects span each line's [from, from+length) with lineEnd EXCLUDING
  trailingSpaces: soft-wrapped lines strip their trailing spaces
  from the highlight, hard-'\n' and last lines keep them; caret
  rect = (cursorX, line·lineH, cursorWidth 1, lineH) — lineH from
  the FixedHeight block format (PrepareBlockFormat setLineHeight).
  Go: ui/text Selection{Anchor,Position}/Range/Empty +
  Document.SelectionSpans→[]Span{Line,From,To} (soft/hard/last-line
  trailing law) + history ComposeCursorRect + token
  ComposeCursorWidth 1. RED → GREEN clean.
- Atomic 3 (this): the field scroll law. Qt source:
  QWidgetTextControl::ensureCursorVisible (qwidgettextcontrol.cpp
  3286-3292) = rectForPosition(cursor).adjusted(−5,0,+5,0) →
  visibilityRequest → QTextEditPrivate::ensureVisible (qtextedit.cpp
  332-363): if rect.y < vOffset → vOffset = rect.y; elif rect.y +
  rect.h > vOffset + viewH → vOffset = rect.y + rect.h − viewH;
  clamped to [0, docH − viewH] — minimal reveal, never centers; the
  −5/+5 pad is horizontal-only (compose never hscrolls, word wrap
  on). Go: ComposeFieldScrollOffset(current, content, view,
  cursorY, cursorH). RED → GREEN clean, 1 test.
- Atomic 5 (this): the editing op set. Qt law: insertText
  (qtextcursor.cpp 1385+) — selection deleted and replaced,
  cursor lands AFTER the inserted text; backspace/delete via
  removeSelectedText when a selection exists, else remove the
  char before/after; word variants remove [MoveWordLeft(p), p)
  / [p, MoveWordRight(p)); '\n' inserts are block separators
  (flat: the rune itself); no-ops at doc edges. Go: ui/text
  InsertAt/DeleteBackward/DeleteForward/DeleteWordBackward/
  DeleteWordForward → (newText, newCursor), clamp+range helpers
  shared. RED → GREEN after 1 test-side selection-slip of mine
  ([4,9) = "two.t" not the whole tail — engine right). Qt source:
  QTextCursorPrivate::movePosition (qtextcursor.cpp 305-640) —
  Left/Right = ∓1 with selection collapse to min/max (MoveAnchor);
  StartOfLine = line start; EndOfLine = Start + visible length,
  trailing spaces excluded on soft wraps, kept on hard/last lines;
  Start/End = 0 / doc end. Word hops = QTextLayout::
  next/previousCursorPosition SkipWords (qtextlayout.cpp 652-716) +
  QTextDocumentPrivate block crossing (qtextdocument_p.cpp
  1341-1366): three rune classes — whitespace, separator set
  (atWordSeparator qtextengine.cpp 3053-3089: .,?!@#$:;-<>[]()={}
  /+%&^*'\"`~|\ — underscore is a WORD char), word; NextWord =
  skip class run + spaces, stops at the '\n' position (a second
  hop crosses); entry at '\n' crosses +1; PrevWord = skip spaces
  back + class run back; entry at line start returns the previous
  line's end. Up/Down = line ∓1 with goal-x (verticalMovementX):
  setX() = current cursor x after horizontal moves, persists
  across vertical hops (setVerticalMovementX doc + movePosition
  tail `if (adjustX) setX()`); landing x = QTextLine::xToCursor
  (qtextlayout.cpp 3107-3260) = NEAREST boundary, ties to the
  earlier column, x≤0 → col 0; no move at doc top/bottom (op
  fails, goal still set). Go: ui/text/movement.go MoveLeft/
  MoveRight/Start/End/StartOfLine/EndOfLine/WordLeft/WordRight/
  XToColumn/MoveVertical + lineOf/visibleEnd refactor shared with
  CursorAt/SelectionSpans. RED → GREEN after 1 of my own
  test-arithmetic errors (deep-up goal: offset 7 = col 2 x16,
  not col 3 — engine was right).
- 26 new tests this session (14+3+1+5+3), 398 total = 229 ui +
  153 gui + 16 text. quick GREEN all commits; js/wasm compile
  ui/... GREEN; comment ban clean. Verifies: 42524452324 /
  42524984339 / 42525180686 all SUCCESS job+step; 42526186953
  in flight. WORKLOG pruned (sessions ≤383 cut; 346→~300 lines).

## Session 400 — the compose-bar glyph trio (2026-11-09)

- ac0521d6. Attach/send/smile PNG-traced per the 386
  chat-family law; padded-canvas Cell law (real canvas +
  rounded bbox origin, containment test); IconButton
  centered canvas (2,3) / send at pinned (10,11); IoU
  0.876/0.854/0.839 (thin strokes). 3 tests, 372 total.
  Verify 42517439919 SUCCESS job+step. Detail: git
  ac0521d6 + this file's history.
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
