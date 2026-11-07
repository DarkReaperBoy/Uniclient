# WORKLOG.md — the state file

Top: the **STATE block** — rewritten every session, the resume pointer for the next
agent. Then open items (severity order), then entries newest-first, terse (did /
evidence / next). The pre-2026-11-01 progress docs (BUGS.md, research/) were purged by
owner order — that history lives in git if ever needed.

## STATE

- front: session 380 — the GUI kit build (post-skeleton);
  the dialogs window-adapter input leg (wheel angle
  law, click hit-test, elastic bar drag/jump, touch
  drag+tap) landed as e30bbfad; verify 42362009163
  SUCCESS at job AND step level — 380 closed green
- next: kinetic touch (fling) + overscroll anim state
  (the deferred halves of the input leg); message-
  bubble kit; Material icon assets (chat-type/send-
  state/pinned/mention/poll/TTL glyphs) to un-defer
  icon paint
- owner-waiting: none
- last-gate: quick GREEN (69 ui + 30 gui = 99 PASS;
  windows-vet substitute for render/window/cmd);
  comment ban 291 clean; CI 42362009163 green
  (cross-builds incl. js/wasm, test/vet/race/smoke,
  nix)

## Open items

| ID | where | what | evidence | next step |
|---|---|---|---|---|
| H-2 | verify/release yml | android APK + web (gh-pages) + Xvfb GUI legs parked until the new GUI | AGENTS.md §6/§8 | re-add with the GUI build (owner order pending) |
| H-3 | engine/cores API | 301+1 identifiers exported purely for the tests move (API noise: TsParseInit1, TsTrackRecvPID; audio's MicStop folded to micStop in session 368) | commit 27faa5a4, session 368 | fold into real APIs or de-export when tests are reworked during the GUI rebuild |

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
  arms 1:1 finger follow (the crossing move applies
  too — prev-position updates every event); tap (never
  armed) selects at the release position; long-press
  right-click deferred (no context menu yet). Row
  hit-test = RowAt(y+Top, width); rowAtY
  (dialogs_list.cpp:252) lower_bound+confirm proved
  equivalent to the existing List.RowAt walk.
- Wiring: 6 messages (Wheel, TrackpadScrolled, Pressed,
  Dragged, Released, PressCanceled) + Model.DialogsTouch/
  DialogsBar states; mouse selects on press, touch on
  release-tap. All scrolls route through clamp +
  loadMoreCmd. PaintPane registers event.Op (Painter.Input)
  in the pane clip; window reads pointer.Filter events
  (open scroll ranges, grab on press, Metric px→dp).
  Windows = angle path (gio passes raw ±120 deltas =
  Qt angleDelta numerically); other backends = pixel
  path (gio converts notches itself: X11 10/notch,
  wayland 100, js ~100 — divergence from AyuGram 60
  noted, Windows exact). Window loop now paints
  PaintPane (was background-only).
- TDD: 2 spec bugs lost to the law — wheel-up −500
  from 692 is 192 in-range (case moved to ±2000);
  692×53/206 = 178.04 → 178 not 177.
- GREEN: 18 tests (7 ui + 11 gui), 99 total; gofmt,
  comment ban 291 clean, quick gate GREEN. Shipped
  e30bbfad; verify 42362009163 SUCCESS at job AND
  step level (3 jobs, 0 failures).

## Session 379 — the dialogs list Elm+render leg: viewport state, scroll laws, Pane snapshot, PaintPane (2026-11-07)

- Boot: workspace intact at 5a84a9ff (no recycle);
  baseline 72 PASS re-verified via quick gate before
  any edit.
- Laws mined: wheel apply = tryScrollTo(visibleFrom
  + delta) with delta = −pixels.y (elastic_scroll.cpp:
  946) — at rest willScrollTo reduces to clamp
  [0, content−view]; reload/resize clamp = QScrollBar
  range-change semantics; load-more fires on EVERY
  viewport-affecting msg while loadTill >= content
  (inner_widget 4712-4723); empty list satisfies it
  trivially → the initial page request; thumb chrome =
  st::defaultScrollArea: bar x deltax 3, w 4, radius
  2, color #00000053 (colors.palette:62).
- The pure snapshot: dialogs.Pane + List.Pane(v,
  width) — VisibleRows window, absolute RowYs walk,
  ScrollbarThumb reuse. Elm: Model.DialogsScroll;
  DialogsScrolled clamps+accumulates; Loaded/Resized
  clamp Top + set pane height; loadMoreCmd returns
  the no-op marker DialogsLoadMoreRequested.
- LAW CHANGE: TestUpdateRecordsResized pin updated —
  resize on an empty list now emits the initial load
  request; the skeleton-era pin lost to the loadTill
  law.
- render.PaintPane: viewport clip; per-row push/pop
  op.Offset(RowYs[i]−View.Top); RowSelected when
  First+i == Selected; thumb rrect at Width−10+3.
- TDD discipline: 5 spec cases fell to the law before
  GREEN (fixtures 6 rows = 372; −20 from 72 = 52
  pass-through; [first,last) windows; barWanted 30
  lifted to min 40; paneFixture Selected −1).
- GREEN: 9 tests, 81 total; gates clean; shipped
  239cdaf1, verify 42351344419 SUCCESS job+step.

## Session 378 — wipe #5 boot + the dialogs list scroll law: viewport, virtualization, reveal, thumb (2026-11-07)

- Boot: full-wipe #5 (repo/toolchain/ayu-ref gone;
  env sweep clean). Clone at 5e6ba094 = origin/main
  (the "ahead by 2" was a stale tracking ref from the
  one-time-URL push). env.sh recovery; ayu-ref
  re-acquired after the AyuGram6→AyuGramDesktop repo
  rename (v7.2.9 + lib_ui @ e3d0582); pins verified;
  baseline 60 PASS.
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
  thumb), Y = deltat+cutFrom. Elastic wheel = device-
  delta driven, no constant to mine; classic updateBar
  thumb law unpinned (dialogs never rides it).
- RED 12 undefined → GREEN 12 (3 spec bugs lost to
  re-derivation first: visible-walk till 233 includes
  row at 214; short-track top-0 thumb (3,27); the
  "partially below" reveal case was fully visible —
  law no-ops). 72 total; gates clean. Landed e38052c2
  (WORKLOG trimmed to 283); verify 42347578779
  SUCCESS job+step — 378 closed green.
- Next: the Elm/gio leg wiring Viewport into Model.
  Dialogs (scroll messages, clamp on reload, thumb
  paint via render Painter).

## Session 377 — the dialogs row widget: pure layout + Elm state + gio render (2026-11-07)

- Boot: workspace intact; dialogs-row CI 42333376504
  reconciled SUCCESS on 056710b2 — 376 green.
  Baseline 48 PASS re-verified.
- The row-core slice: go/ui/dialogs (pure) — Entry +
  Layout(e, width, Metrics) as the pinned-law geometry
  function (all pins live in row.go + tests; exact
  reference lines in git history): name-rect shrink
  order date(+5) -> chat icon(+iconW+3) -> send state
  (-20); date baseline = nameTop+semiboldH-descent;
  badge stack right-anchored, max-2 narrow; variants
  plain/tagged/forum/taggedForum 62/72/80/96; online
  (43,43) / TTL (36,36); List Height/RowAt
  hit-testing. Elm: Model.Dialogs + DialogsLoaded/
  DialogRowPressed, selection clamped on reload.
  Metrics injected — formulas pinned, values from the
  runtime font stack.
- go/ui/dialogs/render (gio): Painter — measure ->
  Layout -> paint; bg states (selected/active);
  photo (affine circle-clip / EmptyUserpic hash color
  + initials, empty_userpic.cpp:307, luma ink);
  online dot presenceGreen #4DC920 + 3px bg ring
  (colors.palette:198); elided labels, date at
  baseline, counter in pill, muted pill. Icon glyphs +
  tag strip + forum topics deferred (geometry
  reserved). x/image promoted indirect->direct.
- RED -> GREEN 11 new ui + 1 gui (60 total); gofmt;
  comment ban 284 0; quick gate GREEN.

## Session 376 — wipe #4 boot: env rebuilt; Material theme system (M3 baseline + AMOLED) (2026-11-07)

- Boot: owner token → VM wiped clean; fresh clone at
  0259ee3f, 375 closed green (42264110055 + release
  42267096271 SUCCESS). go1.27.1 + ayu-ref rebuilt
  per recipe; baseline 23/23 + 11/11 green.
- The theme-system slice: ui/material seed → Scheme
  (36 roles) + Kind + SchemeFor(Light/Dark/Amoled),
  values pinned from Compose material3 tokens v0_210
  (Apache-2.0): light Primary #6750A4 / Surface
  #FEF7FF, dark Primary #D0BCFF / Surface #141218.
  AMOLED = dark + pure-black chrome, elevated
  containers keep dark lift (luma pinned by test).
  Fixed-role family (M3 Expressive) deferred.
  app.View → SchemeFor(Light).Surface.
- RED → GREEN 8 tests / 31 ui total: light+dark
  anchors, AMOLED derivation, WCAG ≥4.5 across 12
  pairs × 3 kinds, opaque, distinct, luma hierarchy.
- The dialogs-row slice (geometry-table slice 5;
  all pins live in tokens + tests — exact source
  lines in git history): badge font 12 h19 pad5
  pill max(textW+2p,19) radius h/2 mark-dot 8;
  counter "99+" >999 / "99999+" >999999; date font
  13 skip 5 baseline semibold−descent; name rect
  (68,10,w−78,semibold); chat-type skip 3 send-state
  skip 20 text min 150 state icons 18; online badge
  12ø stroke 3 dur 150 pos (33,33)/TTL (26,26);
  variants tagged 72/30/52 forum 80/32; width anim
  120; narrow badge top 35, max-2-badges gate.
- RED → GREEN 6 tests / 37 ui total; the TTL-pos
  test caught a real porting bug (stroke=0 branch
  used −half not −badgeSize). Gui suite recount: 11
  (375 logged 12). Three vet-suspect splits.
- Design 8/10: data-pinned with provenance; minus —
  M3 source is Compose's token table, the #FEF7FF
  cross-check ties them.

## Session 375 — the Gio skeleton: Elm core, window adapter, the measured pane law; the cgo-closure fight (2026-11-06)

- Boot: af2f4136 pushed, 374 closed green (42250138772
  SUCCESS); slice-3 42187083372 SUCCESS (373 green).
- go/ui/app — the pure Elm core (Model/Msg/Update/Cmd,
  zero Gio imports): pane law measured from
  computeColumnLayout (window_session_controller.cpp:
  2626-2722): single < 640, triple only >= 932 AND
  third requested, else double; dialogs = SafeRound(
  body*5/14) clamped >= 260, no 540 max, min body-380;
  third clamp(0,[292,392]); three-column shrink
  proportional-to-min-clamped; no-dialogs drops left
  (boundary 672). View(Model) = pure Scene.
- go/ui/window — the Gio adapter: 800x600 default /
  380x480 min, px->dp Resized msg, cmd goroutines via
  64-slot queue + Invalidate, Running=false ->
  ActionClose. material seed #FEF7FF; cmd/uniclient
  -gui; 12 Msg-sequence tests (boundaries 639/640/
  931/932/672, widths, shrink, resize journey).
- gioui.org v0.10.3: gio's Linux desktop path is Xlib
  cgo (pkg-config x11 xkbcommon x11-xcb xcursor
  xfixes egl wayland* + vulkan dlopen). Pipeline
  synced same-commit: AGENTS §7 truth, gate.sh
  partitions gio packages (windows-vet substitute,
  Linux-native rides CI), verify/release apt steps,
  flake.nix closure (+libxcb/libXrender for the .pc
  Requires chain). Closure took 4 flake runs
  (42257568354 -> 42261435344 SUCCESS, 75944429).
- Evidence: RED -> GREEN 12/12 + 23/23; quick gate
  GREEN; js/wasm + windows builds GREEN; local full
  gate machine-blocked (gotd OOM) — verify 42262264512
  on 75944429 is the gate of record. Design 9/10.

## Session 374 — geometry-table slice 4 re-mined after a full-wipe recycle (2026-11-06)

- Boot: full-wipe recycle — unpushed slice 4 died with
  it (token already dead); rebuilt from zero per §3 at
  910d959f, go1.27.1 + ayu-ref (v7.2.9 + lib_ui
  e3d0582) re-acquired, baseline 15/15 re-verified.
- Slice 4 mined (all pins live in tokens.go + tests):
  menu icons 24×24 pos 15/5 pad 54/8/17/8; window
  chrome title 24 / button 36×24 / semibold 12; top
  bar 54, buttons 40/44/52, ripple 40 y 7; checkbox
  22ø dur 120 ripple-pad 8 mark 14×10@4/7; ripple
  650/200; scrollbar 10/2/20/40, insets 3/3/3, 150/
  1000; toast 19/13/19/12 + 13 + 480 + 8 + 200/1000/
  160 (widgets.style, info.style, dialogs.style,
  basic.style — exact lines in git history).
- VerticalCenterOffset added as DERIVED helper
  (menu_action.cpp:131 centering law).
- RED → GREEN 23/23 converged with the lost session;
  CI 42186245433 + 42187083372 SUCCESS (372/373
  closed green); fresh owner token unblocked push:
  af2f4136 → verify 42250138772, T-2 closed.
