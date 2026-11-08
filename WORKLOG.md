# WORKLOG.md — the state file

Top: the **STATE block** — rewritten every session, the resume pointer for the next
agent. Then open items (severity order), then entries newest-first, terse (did /
evidence / next). The pre-2026-11-01 progress docs (BUGS.md, research/) were purged by
owner order — that history lives in git if ever needed.

## STATE

- front: session 394 — the jump-to-end corner button landed (pending CI):
  history/corner_button.go (DownShown law: scrollTop+480 < max, or first
  unread row at/below the fold — cornerButtonsDownShown 9122-9157;
  DownJumpTop = first-unread top clamped else max — downClick →
  UnreadMessagePosition; DownButtonGeometry/Hit = the 52x62 box at
  right+12, sliding from below the pane edge over 72dp — updatePositions
  interpolate; tokens from historyToDown* + measured PNGs); Elm ChatDownState
  rides chatViewportChanged (all Top mutations) + ChatLoaded reset +
  ChatTick 150ms linear slide; press/release: hit pins ChatPress.DownPress
  (before scrollbar + touch branches — touch on button = tap, no scroll
  start), release-inside jumps, drag cancels; window ticks+invalidates on
  ChatDownActive; painter: 42dp circle (PrimaryContainer) + 2dp-offset
  shadow + 19x10 stroke-3 round chevron (OnPrimaryContainer)
- next: dispatch + watch verify.yml for this commit; then the chat-front
  polish queue — composer attach/menu trees or the mentions/reactions
  corner-button stack (historyUnreadThingsSkip 4 + slide-from-right law),
  measured from the reference
- owner-waiting: NEEDS_OWNER — GH_TOKEN absent this sandbox (env recycled
  between sessions); e06ced00 is committed locally on top of origin/main
  5b978120 but NOT pushed, and verify.yml is not dispatched. Re-mention when
  the token is restored
- last-gate: quick GREEN (scoped: tests/gui + tests/ui + importers; windows
  vet = rung-7 OOM skip, gotd tg too big for this box); comment ban clean;
  16 new tests (11 gui + 5 ui) = 306 total, all green locally

## Open items

| ID | where | what | evidence | next step |
|---|---|---|---|---|
| H-2 | verify/release yml | android APK + web (gh-pages) + Xvfb GUI legs parked until the new GUI | AGENTS.md §6/§8 | re-add with the GUI build (owner order pending) |
| H-3 | engine/cores API | 301+1 identifiers exported purely for the tests move (API noise: TsParseInit1, TsTrackRecvPID; audio's MicStop folded to micStop in session 368) | commit 27faa5a4, session 368 | fold into real APIs or de-export when tests are reworked during the GUI rebuild |
| N-1 | repo push | e06ced00 (session 394) unpushed — no GH_TOKEN/SSH in this sandbox; push + dispatch verify.yml when auth returns | git log origin/main..HEAD | owner restores GH_TOKEN or runs: git push origin main |
| D-1 | ui/history corner button | down-button unread-count badge (22dp, centered x, top 0 — jump_down_button.cpp paintEvent + historyToDownBadge*) + hover/over colors + ripple deferred: no unread counter in the chat Item model yet, no hover/ripple machinery in the skin yet; replyReturn branch of downClick + loadedAtBottom==false state return with reply-return jumps / below-history pagination | jump_down_button.cpp 33-52, corner_buttons.cpp 139-145 | badge returns with read-state counts; over/ripple with the skin's hover+ripple pass |

## Session 394 — the jump-to-end corner button (2026-11-09)

- Law: history_view_corner_buttons.cpp (CornerButtons: updateVisibility
  animates on state change only, st::historyToDownDuration 150;
  updatePositions 357-474: column right edge, down button top =
  interpolate(0, 62+10, shown), moveToRight(12, parentH - top) — hidden
  sits fully below the pane edge; the widget 52x62 IS the hit area; wheel
  over the button forwards to the scroll viewport — single-pane pointer
  routing gives that by construction) + history_widget.cpp 9122-9157
  cornerButtonsDownShown (no list / first load → hidden; voice-lock →
  hidden; !loadedAtBottom || replyReturn → shown; scrollTop+480 <
  scrollTopMax → shown; first unread itemTop >= scrollTop+viewportH →
  shown; else hidden) + downClick 139-145 (Ctrl/plain without replyReturn →
  UnreadMessagePosition = first unread else bottom) + chat_helpers.style
  1179-1211 (position 12,10; TwoIconButton 52x62; rippleArea 42@(5,15) ==
  the solid circle in history_down_shadow.png measured 42@(5,5)+icon offset
  10; badge 22 semibold; shownAfter 480; duration 150) + measured
  history_down_arrow@2x.png (glyph bbox 19x10, center (26,28) in the 52
  canvas → (26,38) in button coords, ~3dp legs, round caps/joins — Gio
  strokes render round by default).
- Go mapping: our list is bottom-anchored (loadedAtBottom always true) and
  reply returns don't exist yet → those two show-branches return with their
  features (open item D-1); first-load gate = empty/unmeasured list
  (MaxOffset 0 / rowTop 0 → hidden by construction); unread = first
  UnreadBar row (the read boundary — Item.Unread is the per-message
  out-tick flag, wrong notion for this law).
- history/corner_button.go: DownShown / DownJumpTop (clamped) /
  DownButtonGeometry(paneW, paneH, progress) / DownButtonHit. Tokens:
  HistoryToDown* (12/10/52/62/42@(5,15)/19x10x3@(26,38)/480/150).
- Elm: ChatDownState{Shown,Anim,From,To,Started,Progress}; chatDownCheck
  rides chatViewportChanged (ALL Top mutations incl. measured-compensation,
  resize, bar-drag) + ChatLoaded resets then ChatMeasured re-evaluates;
  chatDownTick 150ms linear; ChatDownActive gates window tick+invalidate;
  pressChat: chatDownHitAt BEFORE scrollbar and touch branches — pins
  ChatPress{DownPress, Row:-1}, zeroes ChatBar/ChatTouch (touch on button =
  tap only, drag cancels, release-inside chatDownClick jumps + re-checks);
  View layers ChatPane.DownProgress.
- Painter: paintDownButton — shadow circle +2dp black 0x28, 42dp circle
  PrimaryContainer, chevron OnPrimaryContainer (Material FAB skin over the
  measured geometry); slides with progress, clipped by the pane.
- RED (compile) → 2 law-test expectation fixes (my own arithmetic: unread
  fold positions, duplicate-slice bug) + 1 model-setup fix (tests must set
  HasDialogs=false or the chat pane is ~500dp and press coords land on the
  scrollbar track) → GREEN. 16 new tests (11 gui journeys + 5 ui laws),
  306 total (190 ui + 116 gui). quick gate GREEN scoped (windows vet rung-7
  OOM skip — CI is the gate of record).

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

- Law: list_widget.cpp 4784-5060 mouseActionStart/Update/Finish +
  changeSelection 1843-1860 + config.h MaxSelectedItems 100 +
  bottom_info.cpp 207-212 (Date cursor zone) + Message/Service::pointState.
  Elm ChatPressState on press (bar-drag leaves Row -1; hidden-thumb strip
  presses fall through to the item); branch order: selection mode
  overSelected -> PrepareDrag else PrepareSelect, time zone -> PrepareDrag,
  body -> Selecting, margin -> PrepareSelect; drags degrade past 10px or a
  row change; finish Inverts in selection mode, else the release-point Date
  cursor selects (the margin-press + time-release quirk kept); touch tap
  synthesizes press+finish at the release point. history/interaction.go:
  Selection laws (cap 100, !service/!empty gate, copy-on-write), HitBox
  PointState, TimeRect. Measure emits per-row HitBoxes; the window gates
  mouse on chatPrimary (gio releases report remaining buttons — the
  chorded-release corner is a refinement candidate). RED 29 -> GREEN first
  run. 267 PASS. Detail: 80aff2a9 + git history.

## Session 390 — chat scrollbar bar-drag laws (2026-11-08)

- ElasticScrollBar (lib_ui elastic_scroll.cpp:116-406; chat.style 188-202,
  colors.palette 344-345): cut-clamp refreshGeometry, off-thumb press centers
  the thumb, drag scale + both pass-through quirks, 1:1 dead-zone reversal
  payback; Elm mouse-only bar drag + ChatPane Thumb/ThumbDragging. 238 PASS.
  Verify 42487726300 SUCCESS. Detail: 8d39d63e + git history.

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

- Boot: wipe #11. Clone at bcf2757 — 379-383
  closed green in lost sessions; baseline 159
  re-verified after env rebuild.
- Law source: history_view_service_message.cpp
  372-485 + chat_style.cpp 103-126 + call site
  780-798 (detail in git + service_bubble.go
  tests): radii 10/3/2 DERIVED from pad/font
  pins; CountServiceLineWidths minDelta-22
  neighbor raise + i-=2 rewalk + post-add;
  call-site add 9 iff clamped back > badge
  additional && < before; parts walk (richW
  +24, richH +3/-4/+4/-3 by sides, forceShrink
  on prevShrink+equal, shrink x+=2 w-=4, C++-
  trunc centering = Go native). RED 11 -> 2
  spec errors (law won). 170 PASS; e21f207;
  verify 42448242342 SUCCESS job+step.

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

- Wheel law (ui_utility.cpp:268-288 + elastic_scroll
  :926-945, pins in dialogs/window code + tests):
  angle→px = angle×lines/(2×3) qRound'd; per-axis
  Ctrl/Shift mult max(w|h,120)/120 TRUNCATED (y by
  scroll HEIGHT); cross-axis |px|>=|py| ignores;
  dy = −pixels.y; pixel path qRound through the same
  block. Bar: 10dp-strip hit test, off-thumb press
  = jump-to-middle, drag dy×scrollable/outsideBar.
  Touch: manhattan>=10 arms 1:1 (arm swallows the
  crossing delta — 381 corrected), tap selects at
  release. 6 Elm messages + Model states; PaintPane
  event.Op; window pointer.Filter + Metric px→dp.
  18 tests, 99 total; e30bbfad; verify 42362009163
  SUCCESS job+step.

## Session 379 — the dialogs list Elm+render leg: viewport state, scroll laws, Pane snapshot, PaintPane (2026-11-07)

- Wheel apply = tryScrollTo(from+delta), delta =
  −pixels.y, rest clamp [0, content−view]; load-more
  on every viewport msg while loadTill >= content
  (empty list = initial page request — resize pin
  updated accordingly). dialogs.Pane + List.Pane(v,
  width) snapshot; Elm Model.DialogsScroll + clamp
  on Loaded/Resized; render.PaintPane (viewport
  clip, per-row offset, thumb rrect). 5 spec cases
  fell to the law. 9 tests, 81 total; shipped
  239cdaf1, verify 42351344419 SUCCESS job+step.

## Session 378 — wipe #5 boot + the dialogs list scroll law: viewport, virtualization, reveal, thumb (2026-11-07)

- Discovery: dialogs list = Ui::ElasticScroll
  (not ScrollArea) — thumb law elastic_scroll.cpp:
  131-175. dialogs/scroll.go: Viewport, MaxOffset/
  Clamp, VisibleRows (1px-overlap lower_bound +
  walk), PreloadWindow 3 screens, ScrollToReveal,
  Thumb (skip 6, thickness 4, barMin min(40,avail/
  2), hide rules, ratio cut-clamp). 12 tests, 72
  total; e38052c2; verify 42347578779 SUCCESS.

## Session 377 — the dialogs row widget: pure layout + Elm state + gio render (2026-11-07)

- dialogs Entry+Layout (name-rect shrink date+5 ->
  chat icon+3 -> send state -20; badge stack
  right-anchored max-2; variants 62/72/80/96; online
  43/43 TTL 36/36); Elm selection clamp; render
  Painter (bg states, photo/userpic, presence dot,
  elided labels, counter pill); icon glyphs
  deferred. 11 ui + 1 gui; gates clean.

## Session 376 — wipe #4 boot: env rebuilt; Material theme system (M3 baseline + AMOLED) (2026-11-07)

- ui/material Scheme 36 roles Light/Dark/Amoled
  (Compose material3 v0_210); dialogs-row slice 5
  pins; TTL-pos test caught a real porting bug.

## Session 375 — the Gio skeleton: Elm core, window adapter, the measured pane law; the cgo-closure fight (2026-11-06)

- go/ui/app Elm core (zero Gio) + pane law
  (computeColumnLayout); window adapter; gioui
  Xlib cgo closure -> gate.sh windows-vet
  substitute; flake green 75944429.

## Session 374 — geometry-table slice 4 re-mined after a full-wipe recycle (2026-11-06)

- Re-derivation converged 23/23; pins in tokens.go
  + tests; CI 42187083372 SUCCESS; T-2 closed.
