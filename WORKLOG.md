# WORKLOG.md — the state file

Top: the **STATE block** — rewritten every session, the resume pointer for the next
agent. Then open items (severity order), then entries newest-first, terse (did /
evidence / next). The pre-2026-11-01 progress docs (BUGS.md, research/) were purged by
owner order — that history lives in git if ever needed.

## STATE

- front: session 391 — chat item
  interaction landed as
  80aff2a9 (the message-leg
  mouse machine: press records
  the over-state — row via
  strictFindItemByY, PointState
  from the HitBox geometry,
  Date cursor from the TimeRect;
  branch order: in selection
  mode overSelected ->
  PrepareDrag else PrepareSelect,
  time zone -> PrepareDrag,
  body -> Selecting, margin ->
  PrepareSelect; drags degrade
  PrepareDrag->Dragging and
  PrepareSelect->Selecting past
  10px or a row change; finish
  inverts in selection mode,
  else the release-point Date
  cursor selects; touch tap
  synthesizes press+finish;
  ChangeSelection with the
  100-item cap and the
  !service/!empty gate,
  copy-on-write; Measure emits
  per-row HitBoxes; the window
  filters non-primary mouse
  presses/releases via the
  chatPrimary flag); verify
  42493085300 SUCCESS at job
  AND step level — closed
  green
- next: chat preload/pagination
  at the top edge; after that
  the floating scroll-date
  (scroll-tied stick-to-top +
  opacity, needs scroll-state
  plumbing from the 388 leg)
- owner-waiting: none
- last-gate: quick GREEN (185 ui
  + 82 gui = 267 PASS;
  windows-vet substitute for
  render/window/cmd); comment
  ban clean; CI 42493085300
  success (3 jobs, all steps;
  release-tag step skipped by
  design on main)

## Open items

| ID | where | what | evidence | next step |
|---|---|---|---|---|
| H-2 | verify/release yml | android APK + web (gh-pages) + Xvfb GUI legs parked until the new GUI | AGENTS.md §6/§8 | re-add with the GUI build (owner order pending) |
| H-3 | engine/cores API | 301+1 identifiers exported purely for the tests move (API noise: TsParseInit1, TsTrackRecvPID; audio's MicStop folded to micStop in session 368) | commit 27faa5a4, session 368 | fold into real APIs or de-export when tests are reworked during the GUI rebuild |

## Session 391 — chat item interaction: tap/press over the message leg (2026-11-08)

- Law source: history_view_list_widget.cpp
  4784-5060 (mouseActionStart/
  Update/Finish) + changeSelection
  1843-1860 + canBeSelected +
  config.h MaxSelectedItems 100 +
  bottom_info.cpp 207-212 (the
  Date cursor zone) + Message/
  Service::pointState.
- Elm: ChatPressState {Row, X, Y,
  Inside, Time, Action} on mouse
  press (bar-drag presses leave
  Row -1; hidden-thumb strip
  presses fall through to the
  item — the Qt hidden bar passes
  clicks); action branch order:
  selection mode overSelected ->
  PrepareDrag else PrepareSelect;
  time zone -> PrepareDrag; body
  -> Selecting (bare tap = net
  no-op); margin -> PrepareSelect.
  Drags degrade (10px or a row
  change). Finish: Invert in
  selection mode; else the
  release-point Date cursor
  Selects the pressed row (the
  margin-press + time-release
  quirk kept). Touch tap
  synthesizes press+finish at the
  release point. ChatLoaded
  clears the selection (rows have
  no stable FullMsgIds yet).
- history/interaction.go:
  Selection laws (Invert/Select/
  Deselect, cap 100, !service/
  !empty gate, copy-on-write),
  HitBox (Item + Time geometry,
  PointStateOf width<1 or hidden
  -> Outside), TimeRect (the
  withTicksWidth zone on the
  TimeLabel insets),
  Geometry.Contains.
- Measure returns per-row
  HitBoxes (content-coord tops);
  the window gates mouse
  press/release on chatPrimary
  (gio Release events report the
  REMAINING buttons; the
  chorded left-hold + right-
  release corner = refinement
  candidate, Qt e->button() is
  not in gio).
- RED 29 -> GREEN first run.
  267 PASS (185 ui + 82 gui).
  80aff2a9 -> verify 42493085300
  SUCCESS, 3 jobs, all steps
  reconciled.

## Session 390 — chat scrollbar bar-drag laws (2026-11-08)

- 8d39d63e. The chat column's
  ElasticScrollBar (lib_ui
  elastic_scroll.cpp:116-406;
  tokens chat.style:188-202,
  colors.palette:344-345):
  refreshGeometry with the
  cut-clamp, off-thumb press
  centers the thumb, drags scale
  scrollable/outsideBar with both
  pass-through quirks, 1:1
  dead-zone reversal payback
  (base::OppositeSigns, zero
  signless); Elm mouse-only bar
  drag, ChatPane Thumb +
  ThumbDragging. 238 PASS.
  Verify 42487726300 SUCCESS.

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
