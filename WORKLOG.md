# WORKLOG.md — the state file

Top: the **STATE block** — rewritten every session, the resume pointer for the next
agent. Then open items (severity order), then entries newest-first, terse (did /
evidence / next). The pre-2026-11-01 progress docs (BUGS.md, research/) were purged by
owner order — that history lives in git if ever needed.

## STATE

- front: session 389 — history entry
  composing landed as 3d78f116 (ComposeBars
  walks recountDisplayDateInBlocks with the
  previousDisplayedInBlocks Empty||Hidden
  skip, DateText-equality day anchors, prev
  hideDisplayDate forcing the badge, own-side
  Hidden/Empty/Sponsored/HideDisplayDate gates,
  and the DateText-presence gate so legacy
  zero-value items grow no ghost pills;
  DateBadge paint = PaintPreparedDate with both
  measured quirks kept — margin.left subtracted
  twice, padding.left added twice; UnreadBar
  35/4/24-pill-31 with the 15.5 double radius
  as float32 through an arc-built path;
  painter Measure composes the bars itself and
  List.Pane carries Bars for the visible
  window); verify 42476159326 SUCCESS at job
  AND step level — closed green
- next: chat scrollbar bar-drag laws + chat
  item interaction (tap/press = message leg);
  after that: chat preload/pagination at the
  top edge, then the floating scroll-date
  (scroll-tied stick-to-top + opacity, needs
  scroll-state plumbing from the 388 leg)
- owner-waiting: none
- last-gate: quick GREEN (168 ui + 56 gui = 224
  PASS; windows-vet substitute for render/window/
  cmd); comment ban clean; CI 42476159326
  success (3 jobs, all steps; release-tag step
  skipped by design on main)

## Open items

| ID | where | what | evidence | next step |
|---|---|---|---|---|
| H-2 | verify/release yml | android APK + web (gh-pages) + Xvfb GUI legs parked until the new GUI | AGENTS.md §6/§8 | re-add with the GUI build (owner order pending) |
| H-3 | engine/cores API | 301+1 identifiers exported purely for the tests move (API noise: TsParseInit1, TsTrackRecvPID; audio's MicStop folded to micStop in session 368) | commit 27faa5a4, session 368 | fold into real APIs or de-export when tests are reworked during the GUI rebuild |

## Session 389 — history entry composing: dates + unread dividers (2026-11-08)

- Boot: wipe #12 recovery. Clone at c8a9ec83
  (385-388 already closed — the carried summary
  was stale again; WORKLOG won). Baseline 213
  re-verified (158 ui + 55 gui).
- Composing law = Element::recountDisplayDateInBlocks
  + setDisplayDate (element.cpp:2684-2745):
  display iff !(own hideDisplayDate = Empty ||
  flag) && !(Hidden || Empty || Sponsored) &&
  (no prev displayed || prev.hideDisplayDate ||
  prev day != day); the previousDisplayed walk
  skips Empty||Hidden prevs (sponsored prevs
  stay valid anchors). Go model: DateText is
  the day key (C++ compares dateTime().date()
  — text equality is the model's day identity)
  and the DateText-presence gate is the one
  deviation: C++ derives text from item->date()
  unconditionally; zero-value legacy items
  must not grow ghost pills.
- Heights ride the existing Bars margin
  channel: DateBadge 32 (10+3+13+4+2, matches
  DateBadgeHeight), UnreadBar 35 = 32+3,
  marginTop 4 = lineWidth 1 + margin 3.
- Date paint law = PaintPreparedDate
  (service_message.cpp:155-194), both quirks
  kept verbatim: available w subtracts
  msgServiceMargin.left TWICE, bubble width
  adds msgServicePadding.left TWICE (equal to
  symmetric forms at 10/12 but carried as
  measured); pill textW+24 x 20 at
  (10 + (w-20-textW-24)/2, y+10), text +12/+3,
  corners r10, wide clamp min(w, 542). Painted
  by the LIST after items (list_widget.cpp:
  3381-3406, in-place dateY = itemtop; the
  floating stick-to-top date stays deferred,
  scroll-tied).
- Unread paint law = UnreadBar::paint
  (element.cpp:781-848, the Ayu pill rewrite;
  the old bar fill block is commented out):
  pill textW+24 x 31 at ((w-pillW)/2, aboveh+4)
  with radius 15.5 (double) carried as float32
  through an arc-built path (gio RRect is
  int-only), text centered on full w, textTop
  pillY+(31-fontH)/2; aboveh = date+thread
  heights per the draw translate (element.cpp:
  1785-1796 / service_message.cpp:705-716).
- Wiring: render.Measure composes bars itself
  (view-derived like C++ components; no app
  churn), List.Pane carries Bars for the
  visible window, paintService/paintMessage
  reconstruct ctx WITH bars. Date pill rides
  the 385 service roles; unread pill roles
  SurfaceContainerLowest/Primary (fcfbfa/538bb4).
- RED 11 (10 ui + 1 gui render) -> 1 spec error
  (item 6's anchor is the HideDisplayDate prev,
  which forces the badge — expectation fixed,
  law unchanged). GREEN 224 PASS (168 ui +
  56 gui). 3d78f116 -> verify 42476159326
  SUCCESS, 3 jobs, all steps reconciled.

## Session 388 — the chat-leg scroll input (2026-11-08)

- Pins: ElasticScroll Real/Real, setHandleTouch(false),
  lockWheelDirection + cross-axis consumeScrollAction
  (list_widget.cpp:2289 — horizontal strict |dx|>|dy|,
  NoScrollPhase non-horizontal short-circuit, text items
  never consume); touch arm manhattan>=10 swallows, manual
  1:1 via ChatWidget::listScrollTo (chat_section:4687 plain
  clamp + moved flag), NO chat-touch overscroll, fling 1px/ms
  deaccel stopping dead at edge (hasScrolled), Acceleration
  under finger 40ms; requestBottomContent (elastic_scroll.cpp:1098)
  delta>0 past bottom edge before clamp; FlingDelta qRound
  half-away (Qt6 QPoint semantics — the trunc pin was a Qt5-ism);
  acceleration sampling on manual blend prev/4+new*3/4;
  3 dialogs elm pins re-derived. Detail: d2d5ae81 + git history.

## Session 387 — the dialogs row painter leg (2026-11-08)

- Wipe #12 recovery; baseline 186 re-verified.
  Detail: git 60467393 + 70600653 (vendorHash
  rotation for the x/image/draw vendored package
  set) + this file's history; laws pinned in
  dialogs code + tests: ChatTypeIcon/BadgeIcon
  selection (bot 17/channel 15/forum 20 canvas
  widths; pinned cell = the 20px canvas, advance
  20+5); ink map (chat-type OnSurface, clock
  OnSurfaceVariant, ticks Primary theme-split,
  mention/reaction/poll Primary/Error/Tertiary,
  active OnPrimaryContainer); narrow icon badges
  = 19x19 empty pills (13x13 variant set NOT
  traced — refinement candidate); TTL badge =
  StackBlur r24 + WCAG darken x4/5 (uint8 wrap
  bug caught) + FormatTTLTiny thresholds +
  2-rune clamp; InfoWidth reserves the 24px
  ticks space. RED 10 -> GREEN 196; verify
  42461470926 SUCCESS job+step.

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
