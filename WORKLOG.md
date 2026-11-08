# WORKLOG.md — the state file

Top: the **STATE block** — rewritten every session, the resume pointer for the next
agent. Then open items (severity order), then entries newest-first, terse (did /
evidence / next). The pre-2026-11-01 progress docs (BUGS.md, research/) were purged by
owner order — that history lives in git if ever needed.

## STATE

- front: sessions 398+399 — the composer front opened: the
  compose-bar geometry law (bar height, field-height machine,
  max-height cap, button-row layout with the 2px field/emoji
  underlap quirk pinned, scroll partition) + the send-button type
  machine (type set, 44x46 cells, ripple (2,3,40), stop 14x14 r3,
  slowmode m:ss text + margins)
- next: the composer continues — attach/send/emoji/schedule glyph
  assets (chat/input_attach@, historySendIcon, chat/input_schedule)
  via the measured-trace pipeline, then the bar painter + Elm wiring
  (ChatComposeState riding resize/field msgs); SendButton state
  crossfade (120ms) + record lottie geometry with the painter
- owner-waiting: none
- last-gate: quick GREEN (399 scope); js/wasm compile ui/... GREEN;
  comment ban clean; 369 tests (216 ui + 153 gui) green locally;
  verify 42513830501 SUCCESS job+step (394-397 scope; dispatch a
  fresh verify for 070b5188+8cda61db next session or on the next
  push)

## Open items

| ID | where | what | evidence | next step |
|---|---|---|---|---|
| H-2 | verify/release yml | android APK + web (gh-pages) + Xvfb GUI legs parked until the new GUI | AGENTS.md §6/§8 | re-add with the GUI build (owner order pending) |
| H-3 | engine/cores API | 301+1 identifiers exported purely for the tests move (API noise: TsParseInit1, TsTrackRecvPID; audio's MicStop folded to micStop in session 368) | commit 27faa5a4, session 368 | fold into real APIs or de-export when tests are reworked during the GUI rebuild |
| D-1 | ui/history corner button | down-button unread-count badge (22dp, centered x, top 0 — jump_down_button.cpp paintEvent + historyToDownBadge*) + hover/over colors + ripple deferred: no unread counter in the chat Item model yet, no hover/ripple machinery in the skin yet; replyReturn branch of downClick + loadedAtBottom==false state return with reply-return jumps / below-history pagination | jump_down_button.cpp 33-52, corner_buttons.cpp 139-145 | badge returns with read-state counts; over/ripple with the skin's hover+ripple pass |
| D-2 | ui/history unread-things buttons | read-marking absent for mentions AND reactions: after a jump the button stays shown (reference hides it when the server marks the thing read — updateUnreadThingsVisibility is server-data-driven); mentionsClick's already-there voice/video media-read branch (5623) deferred — no media model; unread-count badges join D-1's class; poll-votes 4th stack slot returns with a poll model | history_view_corner_buttons.cpp 147-190, 288-345 | returns with engine unread-things events + the media pass |

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

## Session 387 — the dialogs row painter leg (2026-11-08)

- Wipe #12 recovery. Detail: git 60467393 + 70600653
  (vendorHash rotation) + this file's history; icons/
  ink-map/TTL laws pinned in dialogs code + tests.
  RED 10 -> GREEN 196; verify 42461470926 SUCCESS.

## Session 386 — the Material icon asset library (2026-11-08)

- Canvas law (codegen_style parsed_file.cpp:967-969 + lib_ui MonoIcon): icon part point(x,y) = QMargins(x,y,0,0) — glyph at cell+(x,y), canvas = mask + point; SVG -WxH renders the FULL viewBox into WxH (chatlist 72 -> 18, scale 0.25); PNG coverage = blue channel (blue>127 at @3x, RDP eps 0.75@3x, /3 grid; crack-boundary walk; contour order = component scan then area-desc, holes wind opposite); SVG legs absolute M/L/C/Z flatten, 12 samples/cubic; IoU vs @2x 0.886-0.957; @3x is the trace source (per-DPI hand-tuned bboxes, pinned).
- 13 glyphs: bot 16x11@(1,3)->17x14, channel 12x11@(3,4)->15x15, forum 19x10@(1,4)->20x14, dialogs sending 11x11@(8,4)->19x15 / sent 12x10@(10,4)->22x14 / received 17x10@(5,4)->22x14, pinned 20x20, chatlist 18x18 x3 (mention/reaction/poll), history sending 11x11@(5,5)->16x16 / sent 13x11@(2,4)->15x15 / received 18x11@(2,4)->20x15.
- TTL timer (ttl_icon.cpp): pen 1.5 round, solid LEFT half-arc 90..270deg one annulus contour with round caps (bottom cap bulges +x, top -x), dotted right half 9 dots r0.75 pitch 3 anchored 3 o'clock (QPainterPath phase ASSUMED — refine vs a live render someday), text 9px semibold clamped 2 chars.
- Selection laws: history.SendStateIcon(out, sending, unread) = bottom_info.cpp 287-300; dialogs.SendStateIcon(state); BadgeReaction split from BadgeMention (mention wins when both). paintMessage feeds Out to TimeLabel + fillGlyphs the icon at iconX/iconY (Item gains Sending/Unread).
- RED 8 -> 2 spec errors fixed by measurement. GREEN 186. d8eedff -> verify 42454857199 SUCCESS (3 jobs, all steps). Detail: git d8eedff5 + this file's history.

## Session 385 — the complex bubble paint leg: op model + painter wiring (2026-11-08)

- Flare shape (style_core.cpp:164-178 + cached_round_corners.cpp:246-262): createInvertedCircleMask(2r) = filled square MINUS centered disc, quartered; cut lands at the disc-center corner of each drawn quadrant (top-left flare cuts bottom-right etc.); flare squares inv x inv at (x-inv, side-y)/(x+w, side-y), side-y = top or bottom-inv. Gio: MoveTo(neighbor1) ArcTo(cut corner, +-pi/2 by sweep) LineTo(opposite) Close; the only -pi/2 is cut-bottom-right.
- Op model: per part ONE fill with side-rounded corners (10 where Rounded, 0 else; Go-native corner-pixmap equivalent); then top flares (L,R), bottom flares (L,R); no op overlaps. ServiceBubbleRadii(fontH) = the 384 consts generalized (invariant-tested at 13). Painter: per-line shape ends >=0 clamped, add decision on RAW widths, PartsFont at measured svcH, parts y by g.Top-marginTop, badge on RAW lineWidths.back(); ServicePill = degenerate parts walk (identical geometry); bubblePath onto shared openCornersPath.
- RED 8 -> 1 spec error (nil-vs-empty; law won). GREEN 178. b91b7c9 -> verify 42451027930 success (3 jobs, job AND step reconciled). Detail: git b91b7c9a + this file's history.

## Session 384 — the multi-line service complex bubble law (2026-11-08)

- Boot: wipe #11, clone at bcf2757 (379-383 closed green in lost
  sessions; baseline 159 re-verified). Law: history_view_service_message
  .cpp 372-485 + chat_style.cpp 103-126 + call site 780-798 — radii
  10/3/2 derived; CountServiceLineWidths minDelta-22 raise + i-=2
  rewalk + post-add; rich part metrics +24/+3/-4/+4/-3, forceShrink,
  shrink x+=2 w-=4, C++-trunc centering. RED 11 -> 2 spec errors (law
  won). 170 PASS; e21f207; verify 42448242342 SUCCESS job+step.

## Session 383 — the message-bubble render leg: corner/tail/shadow laws, chat Elm + ChatPainter (2026-11-07)

- 4fdc467c. Corner law message.cpp:6626-6651,
  tail glyph 6x10, shadow strips, time label
  message.cpp:5479-5516, wide >= 880, ChatPainter
  TD emulation (text engine deferred). Verify
  42409023939 SUCCESS job+step.

## Session 382 — the history element geometry law: margins, bubble, service (2026-11-07)

- 3a655338. Margins/bars/servicePre chain, two-
  small-margins floor quirk, skip block, textW
  clamp chain (message.cpp 1347/5648/5668/
  6680-6935), DateBadge/Ayu time badge — full
  derivation in ui/history/element.go. Verify
  42384001792 SUCCESS job+step.

## Session 381 — kinetic touch + overscroll anim: fling, rubber band, spring return (2026-11-07)

- Flick law (touchUpdateSpeed per-axis px/s),
  rubber-band overscroll (elastic_scroll.cpp,
  pins in dialogs kinetic code + tests),
  spring return anim; bar-drag overscroll
  range-clamp landed (deferred from 380).
  13 tests, 112 total; ac999d75; verify
  42372859307 SUCCESS job+step.

## Session 380 — the window-adapter input leg: wheel, hit-test, bar drag, touch (2026-11-07)

- Wheel law (ui_utility.cpp:268-288 + elastic_scroll:926-945, pins in the
  dialogs/window code + tests); bar hit/drag laws; touch manhattan>=10
  arming + tap-at-release; 6 Elm messages; window pointer.Filter + px->dp.
  18 tests, 99 total; e30bbfad; verify 42362009163 SUCCESS job+step.

## Session 379 — the dialogs list Elm+render leg: viewport state, scroll laws, Pane snapshot, PaintPane (2026-11-07)

- Wheel apply + clamps; load-more on every viewport msg while loadTill >=
  content (empty list = initial page request); dialogs.Pane snapshot +
  render.PaintPane. 9 tests, 81 total; 239cdaf1; verify 42351344419
  SUCCESS job+step.

## Session 378 — wipe #5 boot + the dialogs list scroll law: viewport, virtualization, reveal, thumb (2026-11-07)

- dialogs list = Ui::ElasticScroll (thumb law elastic_scroll.cpp:131-175);
  dialogs/scroll.go Viewport/VisibleRows/PreloadWindow/ScrollToReveal/
  Thumb. 12 tests, 72 total; e38052c2; verify 42347578779 SUCCESS.

## Session 377 — the dialogs row widget: pure layout + Elm state + gio render (2026-11-07)

- dialogs Entry+Layout (shrink chain, badge stack right-anchored max-2,
  variants 62/72/80/96, online 43/43 TTL 36/36); Elm selection clamp;
  render Painter (bg states, photo, presence, elided labels, counter
  pill). 11 ui + 1 gui; gates clean.

## Session 376 — wipe #4 boot: env rebuilt; Material theme system (M3 baseline + AMOLED) (2026-11-07)

- ui/material Scheme 36 roles Light/Dark/Amoled (Compose material3
  v0_210); dialogs-row slice 5 pins; TTL-pos test caught a real bug.

## Session 375 — the Gio skeleton: Elm core, window adapter, the measured pane law; the cgo-closure fight (2026-11-06)

- go/ui/app Elm core (zero Gio) + pane law
  (computeColumnLayout); window adapter; gioui
  Xlib cgo closure -> gate.sh windows-vet
  substitute; flake green 75944429.

## Session 374 — geometry-table slice 4 re-mined after a full-wipe recycle (2026-11-06)

- Re-derivation converged 23/23; pins in tokens.go
  + tests; CI 42187083372 SUCCESS; T-2 closed.
