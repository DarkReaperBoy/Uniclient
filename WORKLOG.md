# WORKLOG.md — the state file

Top: the **STATE block** — rewritten every session, the resume pointer for the next
agent. Then open items (severity order), then entries newest-first, terse (did /
evidence / next). The pre-2026-11-01 progress docs (BUGS.md, research/) were purged by
owner order — that history lives in git if ever needed.

## STATE

- front: session 401 — the field text-engine core landed
  (ui/text: Metrics/LineHeight/LineAscent/Elide/Layout/CursorAt;
  compose field: wrap width −2 caret reserve, content height,
  placeholder law margins 2,0,2,0 + shift −50 static + 100ms);
  Qt cursor-line law pinned from qtextengine.cpp 3758-3770
- next: the composer continues — cursor rect (height = lineH per
  FixedHeight block format) + selection model + field scroll
  (ensureCursorVisible), then the bar painter + Elm wiring
  (ChatComposeState riding resize/field msgs); schedule/save/cancel
  glyphs when their types get painted; real font metrics adapter
  when the gio shaper lands
- owner-waiting: none
- last-gate: quick GREEN (401 scope, both atomics); js/wasm compile
  ui/... GREEN; comment ban clean; 389 tests (228 ui + 153 gui +
  8 text) green locally; verify 42524452324 for 95ef00d9 in flight

## Open items

| ID | where | what | evidence | next step |
|---|---|---|---|---|
| H-2 | verify/release yml | android APK + web (gh-pages) + Xvfb GUI legs parked until the new GUI | AGENTS.md §6/§8 | re-add with the GUI build (owner order pending) |
| H-3 | engine/cores API | 301+1 identifiers exported purely for the tests move (API noise: TsParseInit1, TsTrackRecvPID; audio's MicStop folded to micStop in session 368) | commit 27faa5a4, session 368 | fold into real APIs or de-export when tests are reworked during the GUI rebuild |
| D-1 | ui/history corner button | down-button unread-count badge (22dp, centered x, top 0 — jump_down_button.cpp paintEvent + historyToDownBadge*) + hover/over colors + ripple deferred: no unread counter in the chat Item model yet, no hover/ripple machinery in the skin yet; replyReturn branch of downClick + loadedAtBottom==false state return with reply-return jumps / below-history pagination | jump_down_button.cpp 33-52, corner_buttons.cpp 139-145 | badge returns with read-state counts; over/ripple with the skin's hover+ripple pass |
| D-2 | ui/history unread-things buttons | read-marking absent for mentions AND reactions: after a jump the button stays shown (reference hides it when the server marks the thing read — updateUnreadThingsVisibility is server-data-driven); mentionsClick's already-there voice/video media-read branch (5623) deferred — no media model; unread-count badges join D-1's class; poll-votes 4th stack slot returns with a poll model | history_view_corner_buttons.cpp 147-190, 288-345 | returns with engine unread-things events + the media pass |

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
- 17 new tests this session (14 + 3), 389 total = 228 ui +
  153 gui + 8 text. quick GREEN both commits; js/wasm compile
  ui/... GREEN; comment ban clean. WORKLOG pruned (sessions ≤383
  cut; 346→~300 lines).

## Session 400 — the compose-bar glyph trio (2026-11-09)

- Boot: synced 67c078ce, token valid; dispatched verify
  42516135130 for 398/399 — SUCCESS job+step (closed the owed
  gate). Front: composer glyph assets.
- Law: chat/input_attach 40px canvas (historyAttach icon,
  chat_helpers.style 1307-1315), chat/input_send 24px
  (historySendIcon 1403), chat/input_smile_face 40px
  (historyAttachEmojiInner 1337-1345). IconButton paint law
  (buttons.cpp 648-693 + defaultIconButton iconPosition (-1,-1),
  widgets.style 1068): centered canvas ((44-40)/2,(46-40)/2) =
  (2,3) for attach/smile — same cell as the ripple; send at the
  pinned sendIconPosition (10,11). Trace per the 386 chat-family
  law: @3x source, blue>127, RETR_CCOMP + approxPolyDP 0.75@3x,
  1/3dp grid (no-op at /3); masks ceil-rounded to contain bounds.
  Glyphs: attach 18x21 single 50v self-band (open paperclip —
  no closed holes), area -93.89; send 20x19 single 20v, -166.61;
  smile 10x9 = 3 solids (13v mouth + two 8v eyes — the asset has
  NO enclosing circle, a minimalist face). PADDED-canvas Cell law
  (new family): Cell = real PNG canvas + rounded bbox origin
  (attach {40,40,11,9}, send {24,24,2,2}, smile {40,40,15,17});
  containment test; the 386 tight mask+point=canvas family law
  untouched. IoU vs @2x: 0.876 / 0.854 / 0.839 — below the
  386 thick-stroke band (0.886-0.957): 1dp-thin strokes make
  the reference's per-DPI hand-tuned drift dominate; eps 0.5
  tried, rejected (attach 0.833).
- Tooling: scripts/trace_compose_glyphs.py (sandbox scripts dir;
  not repo) — IoU metric fixed twice: rasterize at exact x3 with
  INTER_AREA /3 (margins + non-integer scale dropped 1px strokes
  below the 127 threshold) and normalize the trace's absolute
  coords before the x3 fill (clipping was silently halving it).
- Go: icons/data.go composeAttach/Send/SmileGlyph + Compose*
  Icons. RED -> GREEN after 2 of my own test bugs (ceil; inverted
  area windows). 3 tests, 372 total = 219 ui + 153 gui. quick
  GREEN; js/wasm GREEN; comment ban clean.

## Session 399 — the send-button type machine + shape laws (2026-11-09)

- Law: ui/controls/send_button.cpp — type set Send/Schedule/Slowmode/
  Save/Cancel/Record/Round/Stop/EditPrice; updateSize 676-683 (width
  44 — stars widening deferred, height 46, EditPrice (0,46)); ripple
  (2,3,40) every type — same cell as the attach ripple; paintStop
  296-308 (14x14 r3 centered, int-div); paintSlowmode 331-338 (text
  m:ss — minutes = s/60, s%60 padded 2, 0 -> empty, setState 91-97;
  rect marginsRemoved (0,0,10,0), chat_helpers.style 1013); tokens
  sendIconPosition (10,11), scheduleIconPosition (7,8), recordSize
  26, universalDuration 120 = SendStateChangeDurationMs. Go:
  send_button.go SendButtonType + Width/Height/Ripple/StopRect +
  SlowmodeDelayText/TextRect. RED -> GREEN clean. 6 tests, 369 total
  = 216 ui + 153 gui; quick GREEN; js/wasm GREEN; comment ban clean.

## Session 398 — the compose-bar geometry law (2026-11-09)

- Owner restored the token: pushed 5b978120..79d27335 (sessions
  394-397), dispatched verify 42513830501 — SUCCESS at job AND step
  level. N-1 closed.
- Law: moveFieldControls (history_widget.cpp 7587-7660) —
  buttonsBottom = paneH - 46; left run from historySendRight 2:
  attach (2, bb, 44x46), field left 2+44; field top = paneH -
  fieldH - historySendPadding 9; right run: send moveToRight(2),
  emoji toggle moveToRight(2+44) — 44x46 cells (historySendSize,
  chat_helpers.style 1405; every bar IconButton clones it).
  updateFieldSize (7696-7703): fieldWidth = W - attach - 2 - send -
  emoji — sendRight subtracted ONCE while both runs inset by 2: the
  field's right edge sits 2px under the emoji toggle; both paint
  historyComposeAreaBg = msgInBg (colors.palette 458) — benign,
  pinned as the reference's own quirk. fieldHeight (7402-7408):
  no-text chat = 46-18 = 28; else the InputField clamp
  (input_field.cpp 2817-2839): clamp(content, 36, widgetMax),
  setMaxHeight lowering the min when max < 36 (2720-2725).
  computeMaxFieldHeight (9097-9115) = min(224, paneH - reservedAbove
  - 18 - 49 - (49 if replyShown)) — reservedAbove = the top-bar/bars
  column our pane models in a later slice. Scroll partition
  (8660-8666): scrollH = paneH - (fieldH + 18) when canSend, else
  the list keeps the pane. AyuSettings defaults (ayu_settings.h
  668-672): attach/commands/emoji/autodelete buttons all shown.
- Go: ui/history/compose.go — ComposeBarHeight / ComposeFieldMaxHeight
  / ComposeFieldHeight / ComposeBarGeometry (ComposeButtons{Attach,
  Emoji}; hidden button = zero rect, never faked) /
  ComposeScrollHeight; tokens.HistoryReplyHeight 49 pinned
  (chat_helpers.style 1130 — the compose tokens were pinned in an
  earlier session; these are their first consumers).
- RED (undefined symbols) -> GREEN after 3 of MY OWN test-arithmetic
  errors fixed by computing with code (518->510; 184->224, 135->184,
  183 case added). 6 new tests, 363 total = 210 ui + 153 gui. quick
  gate GREEN; js/wasm compile of ui/history + ui/tokens GREEN;
  comment ban clean.

## Session 397 — the unread-reactions corner button (2026-11-09)

- Down-button family clone: slide-from-right 64px, shift =
  66*downP + 66*mentionsP, shown iff >=1 Item.UnreadReaction
  (data-driven), click = topmost unread reaction, routing
  reactions-first, 150ms; heart-ring glyph traced IoU 0.936 as
  icons.HistoryReaction. 19 tests, 357 total. Detail: 79d27335 +
  git history; verify 42513830501 SUCCESS.

## Session 396 — the unread-mentions corner button: the corner stack begins (2026-11-09)

- Law: history_view_corner_buttons.cpp updatePositions 390-404 (mentions
  right = interpolate(-52, 12, shown) — slides in FROM the right edge;
  top = parentH - 62 - 10 - interpolate(0, 62+skip, downShown) — rides
  the down button's ANIMATED progress; settled gap 4, never overlapping
  when settled) + updateVisibility 276-286 (150ms, on change only) +
  updateUnreadThingsVisibility 288-345 (shown = loadedCount > 0 &&
  unreadMayBeShown -> >=1 Item.UnreadMention, data-driven NOT
  scroll-driven) + mentionsClick 147-172 (showAt(minLoaded) = topmost
  row; media-read branch deferred, D-2) + delegate laws history_widget
  .cpp 9118-9165 + style 1242-1254 + historyUnreadThingsSkip 4.
- Glyph: history_unread_mention@2x traced (cv2 RETR_CCOMP +
  approxPolyDP 0.35dp, 1/3dp grid): @ bbox 19x19.33 center (26,36) in
  button coords; 2 contours (ring+curl 43v, hole 10v, opposite winding);
  raster-diff IoU 0.939; icons.HistoryMention Cell{36,46,(16,26)}; pinned
  in the three icon law tests.
- Clock law riding the same concern: ChatLoaded/ChatPrepended gain Now
  (data-arrival msgs carry their clock like press/scroll msgs) — the
  show slide starts at arrival; also fixes the down button's load-time
  clocking.
- Go: MentionsShown/MentionsJumpTop/MentionsButtonGeometry(w,h,progress,
  downProgress)/Hit; tokens HistoryUnreadThingsSkip; Item.UnreadMention;
  ChatPane.MentionsProgress; Elm ChatMentionsState + MentionsPress;
  chatMentionsCheck at ChatLoaded (hard reset — the switch law) +
  ChatPrepended ONLY; press routing mentions-before-down-before-
  scrollbar/touch; chatMentionsTick 150ms; painter paintMentionsButton
  (circle/shadow family + fillGlyph @). No read-marking yet (D-2).
- RED (compile, full surface) -> GREEN after the clock-law fix (4 test
  timing rewrites). 20 new tests (6 ui + 14 gui), 338 total (199 ui +
  139 gui; bookkeeping drift vs the 395 commit msg corrected). quick
  gate GREEN; render+window windows vet GREEN standalone; js/wasm
  compile GREEN; comment ban clean. Detail: 4a9dc14c + git.

## Session 395 — the dialogs to-up corner button (2026-11-09)

- Law: dialogs_widget.cpp 1685-1720 + 1256/2782 (shown iff Top > 240 AND
  Top < max; pane < 260 forces hidden instantly; slide up 64 from below
  the pane edge; click = scrollToDefault Top 0, instant today) +
  chat_helpers.style 1234-1240 + window.style 34/155. Go:
  dialogs/corner_button.go ToUpShown/Geometry/Hit + DialogsToUp* tokens;
  Elm DialogsToUpState rides every dialogs Top mutation site; painter
  chevron-up (flip+1px). 12 new tests (9 gui + 3 ui), 318 total
  (193 ui + 125 gui). quick gate GREEN. Detail: b1e268ec + git.

## Session 394 — the jump-to-end corner button (2026-11-09)

- Law: history_view_corner_buttons.cpp (updateVisibility animates on
  change only, 150; updatePositions 357-474: down top = interpolate(0,
  62+10, shown), moveToRight(12, parentH-top); the 52x62 widget IS the
  hit area) + history_widget.cpp 9122-9157 cornerButtonsDownShown
  (scrollTop+480 < max, or first unread at/below the fold) + downClick
  139-145 (UnreadMessagePosition = first unread else bottom) + style
  1179-1211 + measured history_down_arrow@2x (19x10, center (26,38) in
  button coords). Go: DownShown/DownJumpTop/Geometry/Hit +
  HistoryToDown* tokens; Elm ChatDownState rides chatViewportChanged
  (all Top mutations) + ChatLoaded reset; press pins DownPress before
  scrollbar/touch; painter Material FAB skin. loadedAtBottom/replyReturn
  branches return with those features (D-1). 16 new tests (11 gui +
  5 ui), 306 total (190 ui + 116 gui). quick gate GREEN. Detail:
  b5c4b9c9 + git.

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

## Session 389 — history entry composing: dates + unread dividers (2026-11-08)

- Composing law = Element::recountDisplayDateInBlocks + setDisplayDate
  (element.cpp:2684-2745); DateBadge/UnreadBar paint laws
  PaintPreparedDate (service_message.cpp:155-194, margin.left subtracted
  twice + padding.left added twice quirks) and UnreadBar::paint
  (element.cpp:781-848, pill textW+24 x 31 r15.5 float32 arc path);
  heights ride the Bars margin channel (32 / 35 = 32+3 / marginTop 4).
  Painter Measure composes bars; List.Pane carries Bars. RED 11 -> 1
  spec error fixed. 224 PASS. Detail: git 3d78f116 + this file's history.

## Session 388 — the chat-leg scroll input (2026-11-08)

- Pins: ElasticScroll Real/Real, setHandleTouch(false),
  lockWheelDirection + consumeScrollAction, touch arm
  manhattan>=10 swallows, manual 1:1 plain clamp, NO
  chat-touch overscroll, fling deaccel stops dead at
  edge, requestBottomContent before clamp, FlingDelta
  qRound half-away, acceleration manual blend.
  Detail: d2d5ae81 + git history.

## Session 386 — the Material icon asset library (2026-11-08)

- Canvas law (codegen_style parsed_file.cpp:967-969 + lib_ui MonoIcon): icon part point(x,y) = QMargins(x,y,0,0) — glyph at cell+(x,y), canvas = mask + point; SVG -WxH renders the FULL viewBox into WxH (chatlist 72 -> 18, scale 0.25); PNG coverage = blue channel (blue>127 at @3x, RDP eps 0.75@3x, /3 grid; crack-boundary walk; contour order = component scan then area-desc, holes wind opposite); SVG legs absolute M/L/C/Z flatten, 12 samples/cubic; IoU vs @2x 0.886-0.957; @3x is the trace source (per-DPI hand-tuned bboxes, pinned).
- 13 glyphs: bot 16x11@(1,3)->17x14, channel 12x11@(3,4)->15x15, forum 19x10@(1,4)->20x14, dialogs sending 11x11@(8,4)->19x15 / sent 12x10@(10,4)->22x14 / received 17x10@(5,4)->22x14, pinned 20x20, chatlist 18x18 x3 (mention/reaction/poll), history sending 11x11@(5,5)->16x16 / sent 13x11@(2,4)->15x15 / received 18x11@(2,4)->20x15.
- TTL timer (ttl_icon.cpp): pen 1.5 round, solid LEFT half-arc 90..270deg one annulus contour with round caps (bottom cap bulges +x, top -x), dotted right half 9 dots r0.75 pitch 3 anchored 3 o'clock (QPainterPath phase ASSUMED — refine vs a live render someday), text 9px semibold clamped 2 chars.
- Selection laws: history.SendStateIcon(out, sending, unread) = bottom_info.cpp 287-300; dialogs.SendStateIcon(state); BadgeReaction split from BadgeMention (mention wins when both). paintMessage feeds Out to TimeLabel + fillGlyphs the icon at iconX/iconY (Item gains Sending/Unread).
- RED 8 -> 2 spec errors fixed by measurement. GREEN 186. d8eedff -> verify 42454857199 SUCCESS (3 jobs, all steps). Detail: git d8eedff5 + this file's history.
