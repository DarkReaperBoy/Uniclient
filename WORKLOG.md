# WORKLOG.md — the state file

Top: the **STATE block** — rewritten every session, the resume pointer for the next
agent. Then open items (severity order), then entries newest-first, terse (did /
evidence / next). The pre-2026-11-01 progress docs (BUGS.md, research/) were purged by
owner order — that history lives in git if ever needed.

## STATE

- front: session 390 — chat scrollbar
  bar-drag laws landed as
  8d39d63e (the chat column
  hosts a Ui::ElasticScroll
  whose bar is the separate
  ElasticScrollBar widget,
  not the old ScrollArea pair:
  historyScroll tokens 12/3
  + deltas 3, thumb colors
  517c417a/517c41bc; refresh
  -Geometry with the cut-clamp,
  off-thumb press centers the
  thumb, drags scale
  scrollable/outsideBar with
  both pass-through quirks,
  and the 1:1 dead-zone
  reversal payback carried
  verbatim incl. the live
  clamp bounds; Elm mouse-only
  bar drag, ChatPane carries
  Thumb + ThumbDragging,
  painter rrect w6 r3 with
  the over color while
  dragging); verify 42487726300
  SUCCESS at job AND step
  level — closed green
- next: chat item interaction
  (tap/press = message leg);
  after that: chat preload/
  pagination at the top edge,
  then the floating scroll-date
  (scroll-tied stick-to-top +
  opacity, needs scroll-state
  plumbing from the 388 leg)
- owner-waiting: none
- last-gate: quick GREEN (176 ui
  + 62 gui = 238 PASS;
  windows-vet substitute for
  render/window/cmd); comment
  ban clean; CI 42487726300
  success (3 jobs, all steps;
  release-tag step skipped by
  design on main)

## Open items

| ID | where | what | evidence | next step |
|---|---|---|---|---|
| H-2 | verify/release yml | android APK + web (gh-pages) + Xvfb GUI legs parked until the new GUI | AGENTS.md §6/§8 | re-add with the GUI build (owner order pending) |
| H-3 | engine/cores API | 301+1 identifiers exported purely for the tests move (API noise: TsParseInit1, TsTrackRecvPID; audio's MicStop folded to micStop in session 368) | commit 27faa5a4, session 368 | fold into real APIs or de-export when tests are reworked during the GUI rebuild |

## Session 390 — chat scrollbar bar-drag laws (2026-11-08)

- Boot: wipe #13 recovery. Clone at
  b2b02e5d (385-389 already closed
  — carried summary stale again;
  WORKLOG won). Baseline 224
  re-verified (168 ui + 56 gui).
- Law source: the chat scroll is a
  Ui::ElasticScroll (history_widget
  .cpp:291-293, st::historyScroll)
  whose bar is the separate
  ElasticScrollBar widget (lib_ui
  elastic_scroll.cpp:116-406), NOT
  the old ScrollArea/ScrollBar the
  dialogs leg mirrors. Tokens:
  width 12, round 3, deltas 3
  (chat.style:188-202); thumb
  colors 517c417a/517c41bc
  (colors.palette:344-345).
  refreshGeometry: skip 3, fullSkip
  6, thickness 6, minSize 18,
  barMin min(40, available/2),
  barWanted = available*viewH/
  contentH, hide when barWanted >=
  available, cut-clamp keeps >=
  thickness px per end. Off-thumb
  press centers the thumb (middle
  clamp, from = range*(middle-half
  -deltat)/(available-bar)); drags
  scale scrollable/outsideBar with
  both pass-through quirks; the
  DEAD ZONE: a drag into a clamped
  edge accumulates as potential,
  reversal pays it back 1:1 before
  the content scrolls (base::
  OppositeSigns, zero signless,
  lib_base algorithm.h:137); live
  clamp bounds min(vf,0)..vf+
  (fullSize-visibleTill) carried
  verbatim. Elm: mouse-only bar
  drag (touch stays with the
  ListWidget machine per
  setHandleTouch(false); the C++
  synthesized-mouse touch-on-bar
  nuance is a refinement
  candidate), ChatPane carries
  Thumb + ThumbDragging, painter
  rrect at width-9 w6 r3 with
  the over color while dragging.
  RED 14 -> GREEN first run
  (hand-derived expectations;
  dialogs-leg drag laws were the
  cross-check). 238 PASS (176 ui
  + 62 gui). 8d39d63e -> verify
  42487726300 SUCCESS, 3 jobs,
  all steps reconciled.

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

- Boot: wipe #10. Clone at 8b2ae432 (379-382
  closed green in lost sessions; baseline
  re-verified after env rebuild).
- Pins (laws live in ui/history + tests, detail
  in git): corner law message.cpp:6626-6651
  (attachedTop/Bottom small the wall-side
  corners, tail on layout-side bottom,
  Large=16/Small=6/Tail->0, removeMessageTail
  off by default Tail->Large); tail glyph 6x10
  right triangle; shadow strip 2px
  #748ea2@0x29 / #3ac346@0x1d; time label
  message.cpp:5479-5516 (send-state 24px,
  anchor (-17,-19)); chat mode wide >= 880;
  ChatPainter TD skip-block emulation + body
  wrap approximation documented for the text-
  engine slice; Material skin colors.
- 18 tests, 159 total; 4fdc467c -> verify
  42409023939 SUCCESS job+step.

## Session 382 — the history element geometry law: margins, bubble, service (2026-11-07)

- Boot: wipe #9. Clone at 874f707f (379-381
  closed green in lost sessions; baseline
  re-verified after env rebuild).
- Pins (full derivation in ui/history/element.go
  + its tests, sources cited in git): message
  top margin = attached?0:6 + BARS SURVIVE HIDDEN
  + servicePre-above + added; bottom 2 + below-
  servicePre (hidden 0). Service margins 10/2,
  servicePre unconditional, two-small-margins −20
  floor 25 quirk, Wide min(w,542). Skip block
  12+infoW−2 / fontH−5. textW = max(w,160)−22;
  optimal/limit/clamp chain per message.cpp
  1347/5648/5668/6680-6935. DateBadge 10+3+font+
  4+2; Ayu time badge w+14/h+4/additional w+13.
  Text engine deferred like icon paint (Text
  struct with HeightFor closure).
- RED 14 -> GREEN first run (2 slips caught at
  design). 141 total; 3a655338 -> verify
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
