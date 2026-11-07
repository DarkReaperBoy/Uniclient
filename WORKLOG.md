# WORKLOG.md — the state file

Top: the **STATE block** — rewritten every session, the resume pointer for the next
agent. Then open items (severity order), then entries newest-first, terse (did /
evidence / next). The pre-2026-11-01 progress docs (BUGS.md, research/) were purged by
owner order — that history lives in git if ever needed.

## STATE

- front: session 381 — the GUI kit build (post-
  skeleton); kinetic touch (fling) + overscroll anim
  state (the deferred halves of the input leg) landed
  as ac999d75; verify 42372859307 SUCCESS at job AND
  step level — 381 closed green
- next: message-bubble kit; Material icon assets
  (chat-type/send-state/pinned/mention/poll/TTL
  glyphs) to un-defer icon paint
- owner-waiting: none
- last-gate: quick GREEN (90 ui + 37 gui = 127 PASS;
  windows-vet substitute for render/window/cmd);
  comment ban 294 clean; CI 42372859307 green
  (cross-builds incl. js/wasm, test/vet/race/smoke,
  nix)

## Open items

| ID | where | what | evidence | next step |
|---|---|---|---|---|
| H-2 | verify/release yml | android APK + web (gh-pages) + Xvfb GUI legs parked until the new GUI | AGENTS.md §6/§8 | re-add with the GUI build (owner order pending) |
| H-3 | engine/cores API | 301+1 identifiers exported purely for the tests move (API noise: TsParseInit1, TsTrackRecvPID; audio's MicStop folded to micStop in session 368) | commit 27faa5a4, session 368 | fold into real APIs or de-export when tests are reworked during the GUI rebuild |

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

- Boot: workspace intact at 5a84a9ff; baseline 72
  PASS re-verified via quick gate before any edit.
- Laws mined: wheel apply = tryScrollTo(from+delta),
  delta = −pixels.y — at rest = clamp [0, content−
  view]; load-more fires on EVERY viewport-affecting
  msg while loadTill >= content (inner_widget
  4712-4723; empty list = the initial page request);
  thumb chrome = st::defaultScrollArea 3/4/2/
  #00000053.
- The pure snapshot: dialogs.Pane + List.Pane(v,
  width) — VisibleRows window, absolute RowYs walk,
  ScrollbarThumb reuse. Elm: Model.DialogsScroll;
  DialogsScrolled clamps; Loaded/Resized clamp Top;
  loadMoreCmd = DialogsLoadMoreRequested.
- LAW CHANGE: TestUpdateRecordsResized pin updated —
  resize on an empty list emits the initial load
  request (skeleton-era pin lost to the loadTill
  law). render.PaintPane: viewport clip, per-row
  op.Offset(RowYs[i]−View.Top), RowSelected, thumb
  rrect at Width−10+3.
- TDD: 5 spec cases fell to the law before GREEN.
  9 tests, 81 total; gates clean; shipped 239cdaf1,
  verify 42351344419 SUCCESS job+step.

## Session 378 — wipe #5 boot + the dialogs list scroll law: viewport, virtualization, reveal, thumb (2026-11-07)

- Boot: full-wipe #5. Clone at 5e6ba094 = origin/main
  (the "ahead by 2" was a stale tracking ref).
  ayu-ref re-acquired after the AyuGram6→
  AyuGramDesktop repo rename (v7.2.9 + lib_ui @
  e3d0582); pins verified; baseline 60 PASS.
- Discovery: the dialogs list runs Ui::ElasticScroll
  (dialogs_widget.h:373), not classic ScrollArea —
  thumb law = elastic_scroll.cpp:131-175
  (refreshGeometry); ComputeScrollTo byte-identical in
  both files — one reveal law.
- go/ui/dialogs/scroll.go: Viewport; MaxOffset =
  max(0, content−view); ClampOffset; VisibleRows →
  [first,last) via findByY lower_bound (last-pixel
  overlap) + paint walk; PreloadWindow/LoadMoreNeeded
  (3 screens, config.h:21); ScrollToReveal =
  ComputeScrollTo verbatim; Thumb + ScrollbarThumb —
  fullSkip 6, thickness 4, barMin min(40, available/2),
  barWanted >= available hides, barFrom ratio with
  cut-clamp to the inset range (overscroll shrinks the
  thumb), Y = deltat+cutFrom.
- RED 12 undefined → GREEN 12 (3 spec bugs lost to
  re-derivation first). 72 total; gates clean.
  Landed e38052c2; verify 42347578779 SUCCESS
  job+step — 378 closed green.

## Session 377 — the dialogs row widget: pure layout + Elm state + gio render (2026-11-07)

- Boot: workspace intact; dialogs-row CI 42333376504
  reconciled SUCCESS on 056710b2 — 376 green.
  Baseline 48 PASS re-verified.
- The row-core slice: go/ui/dialogs (pure) — Entry +
  Layout(e, width, Metrics) as the pinned-law geometry
  function: name-rect shrink order date(+5) -> chat
  icon(+iconW+3) -> send state (−20); date baseline =
  nameTop+semiboldH−descent; badge stack right-anchored,
  max-2 narrow; variants plain/tagged/forum/taggedForum
  62/72/80/96; online (43,43) / TTL (36,36); List
  Height/RowAt hit-testing. Elm: Model.Dialogs +
  DialogsLoaded/DialogRowPressed, selection clamped on
  reload. Metrics injected — formulas pinned, values
  from the runtime font stack.
- go/ui/dialogs/render (gio): Painter — measure ->
  Layout -> paint; bg states; photo (affine circle-
  clip / EmptyUserpic hash color + initials, luma
  ink); online dot presenceGreen #4DC920 + 3px bg
  ring; elided labels, counter in pill, muted pill.
  Icon glyphs + tag strip + forum topics deferred
  (geometry reserved).
- RED -> GREEN 11 new ui + 1 gui (60 total); gofmt;
  comment ban 284 0; quick gate GREEN.

## Session 376 — wipe #4 boot: env rebuilt; Material theme system (M3 baseline + AMOLED) (2026-11-07)

- Boot: owner token → VM wiped clean; fresh clone at
  0259ee3f, 375 closed green (42264110055 + release
  42267096271 SUCCESS). go1.27.1 + ayu-ref rebuilt
  per recipe; baseline 23/23 + 11/11 green.
- Theme system: ui/material Scheme (36 roles) + Kind
  + SchemeFor(Light/Dark/Amoled), pinned from
  Compose material3 v0_210: light Primary #6750A4 /
  Surface #FEF7FF, dark #D0BCFF / #141218; AMOLED =
  dark + pure-black chrome (luma pinned by test);
  fixed-role family deferred. RED → GREEN 8 / 31 ui.
- Dialogs-row geometry slice 5 (pins in tokens +
  tests): badge 12/h19/pad5/pill/textW+2p vs 19/r h/2
  /dot 8; "99+">999, "99999+">999999; date 13 skip 5
  baseline semibold−descent; name (68,10,w−78); chat
  skip 3 / send-state skip 20 / text min 150 / icons
  18; online 12ø stroke 3 dur 150; variants 72/80;
  width anim 120; narrow top 35 max-2. RED → GREEN 6
  / 37 ui — the TTL-pos test caught a real porting
  bug (stroke=0 used −half). Design 8/10.

## Session 375 — the Gio skeleton: Elm core, window adapter, the measured pane law; the cgo-closure fight (2026-11-06)

- Boot: af2f4136 pushed, 374 closed green (42250138772
  SUCCESS); slice-3 42187083372 SUCCESS (373 green).
- go/ui/app — the pure Elm core (zero Gio imports):
  pane law from computeColumnLayout (window_session_
  controller.cpp:2626-2722): single < 640, triple only
  >= 932 AND third requested, else double; dialogs =
  SafeRound(body·5/14) clamped >= 260, min body−380;
  third clamp [292,392]; three-column shrink
  proportional-to-min-clamped. go/ui/window — the
  adapter: 800x600/380x480, px→dp Resized, cmd queue
  + Invalidate, ActionClose; 12 Msg-sequence tests.
- gioui.org v0.10.3 Xlib cgo closure: gate.sh
  partitions gio packages (windows-vet substitute,
  Linux-native rides CI), verify/release apt steps,
  flake.nix closure (+libxcb/libXrender) — 4 flake
  runs to green (75944429). RED → GREEN 12/12 +
  23/23; local full gate machine-blocked (gotd OOM)
  — verify 42262264512 on 75944429 is the gate of
  record. Design 9/10.

## Session 374 — geometry-table slice 4 re-mined after a full-wipe recycle (2026-11-06)

- Boot: full-wipe recycle — unpushed slice 4 died with
  it; rebuilt from zero at 910d959f, baseline 15/15.
- Slice 4 mined (pins in tokens.go + tests): menu
  icons 24×24 pos 15/5 pad 54/8/17/8; title 24 /
  button 36×24 / semibold 12; top bar 54, buttons
  40/44/52, ripple 40 y 7; checkbox 22ø dur 120
  mark 14×10@4/7; ripple 650/200; scrollbar 10/2/
  20/40 insets 3 150/1000; toast 19/13/19/12+13+480
  +8+200/1000/160. VerticalCenterOffset = DERIVED
  (menu_action.cpp:131). RED → GREEN 23/23 converged
  with the lost session; CI 42186245433 +
  42187083372 SUCCESS; fresh owner token: af2f4136
  → verify 42250138772, T-2 closed.
