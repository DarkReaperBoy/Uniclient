# WORKLOG.md — the state file

Top: the **STATE block** — rewritten every session, the resume pointer for the next
agent. Then open items (severity order), then entries newest-first, terse (did /
evidence / next). The pre-2026-11-01 progress docs (BUGS.md, research/) were purged by
owner order — that history lives in git if ever needed.

## STATE

- front: session 382 — the GUI kit build (post-
  skeleton); the history element geometry law landed
  as 3a655338 (message/service margins, bubble
  geometry+height, service law, skip block, Ayu
  service-time badge); verify 42384001792 in flight
  — reconcile at boot
- next: message-bubble render leg (Elm Messages
  model + render Painter via the geometry law);
  Material icon assets (chat-type/send-state/pinned/
  mention/poll/TTL glyphs) to un-defer icon paint
- owner-waiting: none
- last-gate: quick GREEN (104 ui + 37 gui = 141 PASS;
  windows-vet substitute for render/window/cmd);
  comment ban 296 clean; CI 42384001792 pending

## Open items

| ID | where | what | evidence | next step |
|---|---|---|---|---|
| H-2 | verify/release yml | android APK + web (gh-pages) + Xvfb GUI legs parked until the new GUI | AGENTS.md §6/§8 | re-add with the GUI build (owner order pending) |
| H-3 | engine/cores API | 301+1 identifiers exported purely for the tests move (API noise: TsParseInit1, TsTrackRecvPID; audio's MicStop folded to micStop in session 368) | commit 27faa5a4, session 368 | fold into real APIs or de-export when tests are reworked during the GUI rebuild |

## Session 382 — the history element geometry law: margins, bubble, service (2026-11-07)

- Boot: wipe #9 (only skills/download/upload; .env
  sweep clean). Clone at 874f707f — 379-381 had
  closed green in lost sessions (Elm+render leg,
  input leg, kinetic+overscroll; 127 baseline re-
  verified after toolchain/modcache/ayu-ref rebuild).
- Surface: element.cpp (skip block 1631-1650,
  textualMaxWidth 2940, DateBadge 857), message.cpp
  (margins 1708-1759, countGeometry 6557-6628,
  resizeContentGetHeight 6680-6935, bubbleTextWidth
  5668, monospaceMaxWidth 5648, optimal 1347),
  service_message.cpp (margins 667-696, geometry 540,
  height 565-640, ComputeServiceTimeMetrics ~500),
  chat.style (msgMinWidth 160, msgDateSpace 12,
  msgDateDelta 2/5), ayu_styles.style (time badge
  11px semibold pads 7/2 gap 8 inset 3).
- go/ui/history/element.go: message top margin =
  attached?0:6 + bars + servicePre-above + added —
  BARS SURVIVE HIDDEN (only the msg margin is
  conditioned); bottom = 2 + below-servicePre,
  hidden 0. Service: 10/2, servicePre UNCONDITIONAL
  (no below check), bottom pays even hidden.
  DateBadge 10+3+font+4+2. Skip block 12+infoW−2 /
  fontH−5. textW = max(w,160)−22; limit unlimited?
  0x3FFFFFF : max(430, mono). Geometry: left 16
  (rightLayout wideSkip; narrow 16) + photoSkip 40,
  rightAction −w−(40−31); clamps maxWidth → limit →
  shrunk max(realWidth+22, nonTextMax); out shift /
  centered halves; Wide centered max((430+80−w)/2,0).
  Height: ==maxWidth keeps OPTIMAL minHeight else
  heightFor(textW)+8+8; +fromName font; +needInfo
  bottomInfo−dateFont; + margins. Service height:
  TWO-SMALL-MARGINS quirk (−2×10), floor 25, nwidth
  max(cw−24,0), fits→minHeight else heightFor, empty
  text = marginTop−10; Wide min(w,542). Ayu time
  badge: w+14, h+4, additional max(w+13,0), skip
  max(badgeH, serviceFontH).
- Text engine deferred like icon paint: Text{MaxWidth,
  MinHeight, HeightFor(w)→(height, realWidth)};
  tests inject synthetic layouts.
- TDD: RED 14 undefined → GREEN 14 first run (2
  expectation slips caught at design time). 141
  total; gates clean. Shipped 3a655338; verify
  42384001792 SUCCESS at job AND step level — 382
  closed green.

## Session 381 — kinetic touch + overscroll anim: fling, rubber band, spring return (2026-11-07)

- Boot: wipes #7 AND #8 in one session (the second
  mid-work, before any edit landed). Recovery
  recipe re-proven twice; the full elastic_scroll
  measurement set survived in-context. Baseline 99
  PASS (full tree 9 pkgs green under GOMEMLIMIT).
- Fling law (FlickCharm lineage, elastic_scroll.cpp:
  112-820): touchUpdateSpeed — px/s = diff·(1000/
  elapsed) with INTEGER multiplier (1000/7 = 142);
  3dp/s finger accuracy per axis; Manual blend prev/4
  + new·3/4 clamp 2500, INITIAL SAMPLE RAW UNCLAMPED;
  Auto re-touch blend old+new/4 clamp 4000 — the
  compat condition always passes with zero x-speed,
  only an x-straddle kills it (quirk pinned). Timer
  15ms: delta = speed·elapsed/1000 trunc, linear
  1dp/ms decay, speed null → Manual + ScrollEnd.
  Acceleration protocol: press during Auto → state
  Acceleration (no scroll, speed blends), 40ms
  stillness → Manual+End+reset, release re-flings
  WITHOUT TouchTime reset (long first delta is the
  law); arm event swallows the crossing delta
  (touchUpdateSpeed at arm sets prev = pos) —
  TestDialogsTouchDragScrolls re-pinned 10→0/30→20.
- Overscroll law (884-1096 + 1119-1169 + 1436-1505):
  pipeline = trackWheelVelocity (momentum-gap
  velocity preserved; Begin zeroes) → ignoreMomentum
  (same-direction momentum consumed during bounce,
  opposite cancels spring) → Chromium reconcile (1:1
  unwind toward content before scrolling) →
  willScrollTo widen [min(from,0), max(from,max)] →
  touch ×2 → 10dp pending minimum → accumulated band
  stretch = round(acc/20) ↔ acc = round(20·stretch)
  (plain Real/Real defaults 0, dialogs_widget.cpp:
  500; SafeRound = std::round half-away, lib_base
  algorithm.cpp:15) → position = max+s / negative s
  / clamp. Classic wheel = phase-None branch (948-
  961): NEVER overscrolls; stretch ≠ 0 → Return only.
  Spring (588-647): x(t) = (X0+V0·0.31·t)·e^(−12.5t)
  capped 1000ms, V0 = tracked velocity fresh ≤100ms
  clamp 6000, peak = 1/decay − X0/push, finish on
  sign-cross or zero-after-peak; collapsing() dead
  for plain defaults (defaults ≠ 0 = stories feature).
- Port: dialogs/kinetic.go pure laws + Overscroll
  state machine; Model.DialogsOverscroll + TouchDrag
  extended (State/Speed/PrevValid/Waiting/
  AccelerationTime/TouchTime); messages carry Now
  (window stamps UnixMilli at delivery — synthesized
  events use delivery time, AyuGram's timestamp-0
  fallback); DialogsTick frame-driven, Invalidate
  while KineticActive; spring skipped at progress 0
  (animation callbacks fire next frame); same-frame
  fling ticks elapsed-guarded. Touch-on-bar routes
  to the LIST not the bar (Qt touch propagates past
  the non-accepting bar) — bar grabs are mouse-only.
- Not ported (measured, deferred): bar-drag
  overscroll (_dragOverscrollAccumulated — separate
  accumulation, no spring even in AyuGram, rare
  path); trackpad phased momentum (gio exposes no
  scroll phases); pull sides + Virtual overscroll
  types (stories strip); long-press right-click;
  requestBottomContent sync retry (async loadMoreCmd
  instead).
- TDD: 3 spec bugs lost to the law (blend arithmetic
  425 not 225 — divided the wrong term; Begin-cancel
  setup self-contradiction; the slice-380 arm-delta
  belief above). GREEN: 28 tests (21 ui + 7 gui),
  127 total; gofmt, comment ban 294, quick gate
  GREEN. Shipped ac999d75; verify 42372859307
  SUCCESS at job and step level (3 jobs; flake
  tag-check skipped as on every non-release push).

## Session 380 — the window-adapter input leg: wheel, hit-test, bar drag, touch (2026-11-07)

- Boot: wipe #6 (repo/toolchain/ayu-ref gone;
  skills/download/upload survived, .env sweep clean).
  Clone landed at 26f6fccd — 379 had already closed
  green in the lost session. env.sh recovery, pins
  verified (taggedForumDialogRow 96/77), baseline 81
  PASS before any edit.
- Wheel law (ui_utility.cpp:268-288 + elastic_scroll
  :926-945): angle→px = angle×lines/(2×3), qRound on
  the float (toPoint = half away from zero); Ctrl/Shift
  multiply is PER-AXIS max(width|height,120)/120,
  TRUNCATED (QPoint double-ctor narrowing) — y scales
  by scroll HEIGHT, not width; cross-axis |px| >= |py|
  ignores (x carries the width mult, y the height mult,
  so acceleration can flip the verdict; dialogs sets
  no direction lock → the check is unconditional);
  dy = −pixels.y. Pixel path (trackpad + synthesized
  touch): qRound(px) through the same block, modifiers
  cleared for synthesized touch only.
- Bar laws (elastic_scroll.cpp:321-388): overBar =
  strip-local x in [deltax, deltax+thickness) AND y in
  [thumb.Y, thumb.Y+H) — the 10dp strip is wider than
  the 4dp thumb, so track-edge clicks jump; off-thumb
  press = jump-to-middle: middle = clamp(y, deltat+
  half, deltat+available+half−bar), from = scrollable×
  (middle−half−deltat)/(available−bar); drag = scaleToBar
  dy×scrollable/outsideBar, 1:1 when scrollable <=
  outsideBar; range clamp reduces to ClampOffset when
  not overscrolled (overscroll accumulation needs anim
  state — deferred with the fling).
- Touch: manhattan(pos−start) >= startDragDistance 10
  arms 1:1 finger follow; tap (never armed) selects
  at the release position; long-press right-click
  deferred (no context menu yet). Row hit-test =
  RowAt(y+Top, width). NOTE: 380 shipped the arm
  event as scrolling (10px applied) — 381 re-measured
  and corrected: the arm swallows the crossing delta.
- Wiring: 6 messages (Wheel, TrackpadScrolled, Pressed,
  Dragged, Released, PressCanceled) + Model.DialogsTouch/
  DialogsBar states; mouse selects on press, touch on
  release-tap. PaintPane registers event.Op (Painter.
  Input) in the pane clip; window reads pointer.Filter
  events (grab on press, Metric px→dp). Windows =
  angle path (gio ±120 = Qt angleDelta numerically);
  other backends = pixel path (gio converts notches
  itself: X11 10/notch, wayland 100, js ~100 —
  divergence from AyuGram 60 noted, Windows exact).
  Window loop now paints PaintPane (was background-
  only). Bar-drag overscroll range-clamp deferred
  (needs anim state — landed in 381).
- TDD: 2 spec bugs lost to the law — wheel-up −500
  from 692 is 192 in-range (case moved to ±2000);
  692×53/206 = 178.04 → 178 not 177.
- GREEN: 18 tests (7 ui + 11 gui), 99 total; gofmt,
  comment ban 291 clean, quick gate GREEN. Shipped
  e30bbfad; verify 42362009163 SUCCESS at job AND
  step level (3 jobs, 0 failures).

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

- Boot: full-wipe #5. Clone at 5e6ba094 = origin/main
  (the "ahead by 2" was a stale tracking ref).
  ayu-ref re-acquired after the AyuGram6→
  AyuGramDesktop repo rename (v7.2.9 + lib_ui @
  e3d0582); pins verified; baseline 60 PASS.
- Discovery: the dialogs list runs Ui::ElasticScroll
  (dialogs_widget.h:373), not classic ScrollArea —
  thumb law = elastic_scroll.cpp:131-175;
  ComputeScrollTo byte-identical in both files.
- go/ui/dialogs/scroll.go: Viewport; MaxOffset /
  ClampOffset; VisibleRows (lower_bound last-pixel
  overlap + paint walk); PreloadWindow 3 screens;
  ScrollToReveal; Thumb (fullSkip 6, thickness 4,
  barMin min(40, available/2), hide rules, ratio
  with cut-clamp — overscroll shrinks the thumb).
  12 tests (3 spec bugs lost to re-derivation), 72
  total; landed e38052c2; verify 42347578779
  SUCCESS job+step.

## Session 377 — the dialogs row widget: pure layout + Elm state + gio render (2026-11-07)

- go/ui/dialogs (pure): Entry + Layout(e, width,
  Metrics) — name-rect shrink order date(+5) → chat
  icon(+iconW+3) → send state(−20); badge stack
  right-anchored, max-2 narrow; variants 62/72/80/96;
  online (43,43) / TTL (36,36); List RowAt. Elm
  Model.Dialogs + selection clamp on reload.
  render Painter: bg states, photo/EmptyUserpic,
  presenceGreen dot, elided labels, counter pill;
  icon glyphs + tags deferred. 11 ui + 1 gui (60
  total); gates clean.

## Session 376 — wipe #4 boot: env rebuilt; Material theme system (M3 baseline + AMOLED) (2026-11-07)

- ui/material Scheme (36 roles, Light/Dark/Amoled)
  from Compose material3 v0_210; RED → GREEN 8/31.
  Dialogs-row geometry slice 5 pins (badge pill,
  counter format, online-badge pos law, tagged/forum
  variants) in tokens + tests — 6/37; the TTL-pos
  test caught a real porting bug. 376 green.

## Session 375 — the Gio skeleton: Elm core, window adapter, the measured pane law; the cgo-closure fight (2026-11-06)

- go/ui/app Elm core (zero Gio): pane law from
  computeColumnLayout (window_session_controller.cpp:
  2626-2722); go/ui/window adapter + 12 Msg tests.
  gioui.org v0.10.3 Xlib cgo closure: gate.sh gio
  partition (windows-vet substitute), apt/nix sets —
  4 flake runs to green (75944429). 12/12 + 23/23;
  verify 42262264512 → 42264110055 gate of record.

## Session 374 — geometry-table slice 4 re-mined after a full-wipe recycle (2026-11-06)

- Full-wipe recycle killed the unpushed first
  attempt; re-derivation converged (23/23) — pins
  live in tokens.go + tests: menu icons 24×24 15/5
  54/8/17/8; title/button/top-bar/checkbox/ripple/
  scrollbar/toast tables; VerticalCenterOffset =
  menu_action.cpp:131. CI 42187083372 SUCCESS;
  verify 42250138772 on af2f4136 — T-2 closed.
