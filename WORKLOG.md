# WORKLOG.md — the state file

Top: the **STATE block** — rewritten every session, the resume pointer for the next
agent. Then open items (severity order), then entries newest-first, terse (did /
evidence / next). The pre-2026-11-01 progress docs (BUGS.md, research/) were purged by
owner order — that history lives in git if ever needed.

## STATE

- front: session 396 — the unread-mentions corner button landed (the
  corner stack begins): shown iff ≥1 Item.UnreadMention (data-driven —
  rechecked at ChatLoaded [hard reset first] + ChatPrepended ONLY, never
  on scroll); slides in from the right edge over 64px while riding the
  down button's progress (shift 66*downP, 4px gap at full stack, provably
  never overlapping); 150ms; click jumps to the topmost unread mention
  (clamped, -1 = no-op); press routing mentions-before-down-before-
  scrollbar/touch; ChatLoaded/ChatPrepended now carry Now (data-arrival
  clock law — also fixes the down button's load-time clocking); traced @
  glyph (IoU 0.939 vs the reference raster) as icons.HistoryMention
- next: the reactions corner button (same law; shift gains the mentions
  term interpolate(0, 62+4, mentionsP); Item.UnreadReaction + glyph trace)
  or the composer attach/menu trees; push N-1 when the token returns
- owner-waiting: NEEDS_OWNER — GH_TOKEN still absent this sandbox; sessions
  394+395+396 sit committed locally on top of origin/main 5b978120,
  unpushed, verify.yml undispatched. Re-mention when the token is restored
- last-gate: quick GREEN (396 scope); render+window windows vet GREEN
  standalone (batched rung-7 OOM skip is cmd/uniclient's gotd, not these);
  js/wasm compile of ui/... GREEN; comment ban clean; 338 tests
  (199 ui + 139 gui) green locally incl. race

## Open items

| ID | where | what | evidence | next step |
|---|---|---|---|---|
| H-2 | verify/release yml | android APK + web (gh-pages) + Xvfb GUI legs parked until the new GUI | AGENTS.md §6/§8 | re-add with the GUI build (owner order pending) |
| H-3 | engine/cores API | 301+1 identifiers exported purely for the tests move (API noise: TsParseInit1, TsTrackRecvPID; audio's MicStop folded to micStop in session 368) | commit 27faa5a4, session 368 | fold into real APIs or de-export when tests are reworked during the GUI rebuild |
| N-1 | repo push | sessions 394+395+396 committed locally, unpushed — no GH_TOKEN/SSH in this sandbox; push + dispatch verify.yml when auth returns | git log origin/main..HEAD | owner restores GH_TOKEN or runs: git push origin main |
| D-1 | ui/history corner button | down-button unread-count badge (22dp, centered x, top 0 — jump_down_button.cpp paintEvent + historyToDownBadge*) + hover/over colors + ripple deferred: no unread counter in the chat Item model yet, no hover/ripple machinery in the skin yet; replyReturn branch of downClick + loadedAtBottom==false state return with reply-return jumps / below-history pagination | jump_down_button.cpp 33-52, corner_buttons.cpp 139-145 | badge returns with read-state counts; over/ripple with the skin's hover+ripple pass |
| D-2 | ui/history mentions button | mention read-marking absent: after the jump the button stays shown (reference hides it when the server marks the mention read — updateUnreadThingsVisibility is server-data-driven); mentionsClick's already-there voice/video media-read branch (5623) deferred — no media model; unread-count badge joins D-1's class | history_view_corner_buttons.cpp 147-172, 288-345 | returns with engine mention-read events + the media pass |

## Session 396 — the unread-mentions corner button: the corner stack begins (2026-11-09)

- Law: history_view_corner_buttons.cpp updatePositions 390-404 (mentions:
  right = interpolate(-52, 12, shown) — slides in FROM the right edge;
  top = parentH - 62 - 10 - interpolate(0, 62+skip, downShown) — rides
  the down button's ANIMATED progress; gap = 4*downP ≥ 0, provably never
  overlapping) + updateVisibility 276-286 (150ms, animates on change
  only) + updateUnreadThingsVisibility 288-345 (shown = loadedCount > 0
  && unreadMayBeShown; mapped to ≥1 Item.UnreadMention — data-driven,
  NOT scroll-driven) + mentionsClick 147-172 (showAt(minLoaded) = oldest
  = our topmost row; the already-there voice/video read-marking branch
  deferred with the media model) + delegate laws history_widget.cpp
  9118-9165 (ignore = show-anim [none]; unreadMayBeShown = !firstLoad &&
  !voiceBar [both n/a]; has(type) = true) + chat_helpers.style 1242-1254
  (historyUnreadMentions = TwoIconButton(historyToDown) clone, @ glyph)
  + historyUnreadThingsSkip 4.
- Glyph: history_unread_mention@2x measured — 52 canvas, @ bbox 19x19.33
  center (26,26)@1x → button (26,36) via iconPosition (0,10); traced
  with cv2 (RETR_CCOMP + approxPolyDP 0.35dp, 1/3dp grid): 2 contours
  (ring+curl 43v, counter-hole 10v, opposite winding −152.1/+41.0),
  raster-diff vs the source mask IoU 0.939 (599↔603 px). icons
  .HistoryMention Cell{W36,H46,(16,26)} — family law mask+point=canvas;
  pinned in TestIconCells/GlyphBounds/GlyphContoursOrientedForHoles.
- Clock law riding the same concern: ChatLoaded/ChatPrepended gain Now
  (data-arrival msgs carry their clock like press/scroll msgs already
  do) — the show slide starts at arrival, and the down button's
  load-time show is clocked right too.
- Go: history/corner_button.go MentionsShown / MentionsJumpTop (topmost
  unread-mention row top clamped, -1 = no-op) / MentionsButtonGeometry(
  w, h, progress, downProgress) / MentionsButtonHit; tokens
  HistoryUnreadThingsSkip; Item gains UnreadMention; ChatPane gains
  MentionsProgress. Elm: ChatMentionsState + ChatPress.MentionsPress;
  chatMentionsCheck at ChatLoaded (hard reset first — the switch law,
  same as ChatDown) + ChatPrepended ONLY; press routing hits mentions
  BEFORE down (column z-order: children stack up, later = above) and
  both before scrollbar/touch (tap-only touch, drag cancels,
  release-inside jumps + re-checks); chatMentionsTick 150ms linear in
  ChatTick; window ticks/invalidates on ChatMentionsActive; View layers
  pane.MentionsProgress. Painter: paintMentionsButton — the down-button
  circle/shadow family + fillGlyph @, after paintDownButton, pane-
  clipped, early-out when Left >= paneW.
- No read-marking in the model yet: the button stays shown after the
  jump (the reference hides it when the server marks the mention read) —
  open item D-2.
- RED (compile, full surface) → GREEN after the clock-law fix (4 test
  timing rewrites). 20 new tests (6 ui laws + 14 gui journeys), 338
  total (199 ui + 139 gui — STATE bookkeeping drift vs the 395 commit
  message corrected: 193+125 was the truth). quick gate GREEN; render+
  window windows vet GREEN standalone; js/wasm compile of ui/... GREEN;
  comment ban clean.

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
