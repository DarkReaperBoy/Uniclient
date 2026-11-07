# WORKLOG.md — the state file

Top: the **STATE block** — rewritten every session, the resume pointer for the next
agent. Then open items (severity order), then entries newest-first, terse (did /
evidence / next). The pre-2026-11-01 progress docs (BUGS.md, research/) were purged by
owner order — that history lives in git if ever needed.

## STATE

- front: session 379 — the GUI kit build (post-skeleton);
  the dialogs list Elm+render leg (viewport state,
  scroll msgs, clamp laws, load-more wiring, Pane
  snapshot, PaintPane with elastic thumb) landed as
  239cdaf1; verify 42351344419 SUCCESS at job AND
  step level — 379 closed green
- next: the window-adapter input leg (wheel/touch →
  DialogsScrolled, click hit-testing via List.RowAt
  + viewport offset, scrollbar drag); then message-
  bubble kit; Material icon assets (chat-type/send-
  state/pinned/mention/poll/TTL glyphs) to un-defer
  icon paint
- owner-waiting: none
- last-gate: quick GREEN (62 ui + 19 gui = 81 PASS;
  windows-vet substitute for render/window/cmd);
  comment ban 288 clean; CI 42351344419 green
  (cross-builds incl. js/wasm, test/vet/race/smoke,
  nix)

## Open items

| ID | where | what | evidence | next step |
|---|---|---|---|---|
| H-2 | verify/release yml | android APK + web (gh-pages) + Xvfb GUI legs parked until the new GUI | AGENTS.md §6/§8 | re-add with the GUI build (owner order pending) |
| H-3 | engine/cores API | 301+1 identifiers exported purely for the tests move (API noise: TsParseInit1, TsTrackRecvPID; audio's MicStop folded to micStop in session 368) | commit 27faa5a4, session 368 | fold into real APIs or de-export when tests are reworked during the GUI rebuild |

## Session 379 — the dialogs list Elm+render leg: viewport state, scroll laws, Pane snapshot, PaintPane (2026-11-07)

- Boot: workspace intact at 5a84a9ff (no recycle);
  baseline 72 PASS re-verified via quick gate before
  any edit.
- Laws mined: wheel apply = tryScrollTo(visibleFrom
  + delta) with delta = −pixels.y (elastic_scroll.cpp:
  946) — at rest willScrollTo reduces to clamp
  [0, content−view] (the gesture-relative min/max
  bounds only matter mid-rubber-band; adapter anim
  state, not core); reload/resize clamp = QScrollBar
  range-change semantics (value clamps when max
  shrinks); load-more fires on EVERY viewport-
  affecting msg while loadTill >= content (no
  transition guard — engine dedups, inner_widget
  4712-4723); empty list satisfies it trivially →
  the initial page request; thumb chrome =
  st::defaultScrollArea (ElasticScroll ctor default,
  elastic_scroll.h:112): bar x deltax 3, w 4, radius
  2, color scrollBarBg #00000053 (colors.palette:62).
- The pure snapshot: dialogs.Pane{Width, View, First,
  Rows, RowYs, Selected, Thumb} + List.Pane(v, width)
  — VisibleRows window, absolute RowYs cumulative
  walk, ScrollbarThumb reuse. Elm: Model.DialogsScroll
  Viewport; DialogsScrolled{DeltaY} clamps+
  accumulates; DialogsLoaded/Resized clamp Top
  (QScrollBar law) + set pane height; loadMoreCmd on
  scrolled/resized/loaded returning the no-op marker
  DialogsLoadMoreRequested (adapter observation point;
  no chain — Update no-ops it, verified).
- LAW CHANGE: TestUpdateRecordsResized pin updated —
  resize on an empty list now emits the initial load
  request; the skeleton-era "resize emits no cmd"
  predates the loadTill law and lost to it.
- render.PaintPane: viewport clip; per-row explicit
  push/pop op.Offset(RowYs[i]−View.Top) (defer-in-loop
  would accumulate offsets across rows — caught at
  design); RowSelected when First+i == Selected;
  thumb rrect at Width−10+3. Scene.Dialogs = the pane
  (zeroed when !HasDialogs).
- TDD discipline: 5 of my spec cases fell to the law
  before GREEN — 4 plain rows = 248 < 300 view (no
  scroll range; fixtures went to 6 rows = 372);
  −20 from 72 = 52 in-range pass-through (not 0);
  pane windows are [first,last) so top {0,100} shows
  rows 0..1 only (row 2 top 134 >= till) and narrow
  {62,124} rows 1..2 (row 3 top 186 not < 186);
  thumb track = view height → barWanted 30 lifted to
  min 40; paneFixture needed Selected −1 (zero value
  0 = row-0-selected). Implementation matched the
  pinned laws every time — all five were spec bugs.
- GREEN: 9 new tests (2 ui + 7 gui), 81 total. gofmt,
  comment ban 288 clean, quick gate GREEN (windows-vet
  substitute compiled the gio render leg).
- Next: the window-adapter input leg (wheel/touch ->
  DialogsScrolled, click hit-testing via RowAt +
  viewport offset, scrollbar drag).

## Session 378 — wipe #5 boot + the dialogs list scroll law: viewport, virtualization, reveal, thumb (2026-11-07)

- Boot: full-wipe #5 — repo, toolchain AND ayu-ref gone
  (only skills/download/upload survived; .env holds no
  credentials, sweep clean). Fresh clone at 5e6ba094
  (= origin/main, push had already landed; the "ahead
  by 2" in the dead workspace was a stale tracking ref
  from the one-time-URL push pattern). go1.27.1 rebuilt
  from the env.sh recipe (modcache 1.1G); ayu-ref
  re-acquired: AyuGramDesktop v7.2.9 tarball (github
  rename — AyuGram6 probe 404s; real repo
  AyuGram/AyuGramDesktop, found via web search) +
  lib_ui @ e3d0582 tarball. Version sanity: dialogs.style
  taggedForumDialogRow 96/77 matches the slice-5 pins.
  Baseline re-verified before any edit: quick gate
  HEAD~2 GREEN, 60 PASS.
- The discovery that reframes the slice: the dialogs
  list runs on Ui::ElasticScroll (dialogs_widget.h:373),
  NOT the classic ScrollArea — the governing thumb law
  is elastic_scroll.cpp:131-175 (refreshGeometry), not
  scroll_area.cpp updateBar. ComputeScrollTo is
  byte-identical in both files (elastic_scroll.cpp:21-52
  == scroll_area.cpp:23-53) — one reveal law.
- The scroll slice: go/ui/dialogs/scroll.go — Viewport
  {Top, Height}; MaxOffset = max(0, content−view)
  (scrollTopMax scroll_area.cpp:653 + QScrollBar
  range semantics); ClampOffset; VisibleRows(v, width)
  → [first,last) — findByY lower_bound "top+height−1 >=
  viewportTop" (dialogs_list.cpp) + the paint walk
  "break when top >= viewportBottom" (inner_widget
  3749-3752): a row counts as visible when its LAST
  pixel overlaps — 1px overlap pinned by test;
  PreloadWindow = [top, top + 4 viewports) and
  LoadMoreNeeded = top + 3·viewH >= contentH
  (inner_widget 4705-4723, 5654-5655; PreloadScreens
  = 3 token, config.h:21 — the same "3 screens"
  constant history_widget uses); ScrollToReveal(top,
  bottom, current, viewH, max) — ComputeScrollTo
  verbatim: clamp top, exact mode (bottom < 0 →
  top-align), no-op when item inside view, bottom-
  align toTill−viewH capped at item top; Thumb{Y,H,
  Hidden} + ScrollbarThumb(v, width, trackH) — the
  elastic law: fullSkip 6 (deltat+deltab), thickness
  4 (width−2·deltax), hide when content<=0 || view<=0
  || track < 14; available = track−6; barMin =
  min(scrollBarMin 40, available/2); bar = max(barMin,
  floor(available·view/content)); hide when barWanted
  >= available; barFrom = (available−bar)·top/scrollable
  cut-clamped to [0, available−thickness] / [thickness,
  available] (overscroll shrinks the thumb into the
  insets — pinned); Y = deltat + cutFrom. Wheel law
  NOT pinned: elastic wheel is device-delta driven
  (ScrollDeltaF), no constant to mine. Classic updateBar
  thumb law (scroll_area.cpp:145-190, clamps to style
  minHeight 20) left unpinned — dialogs list never
  rides it.
- RED: 12 tests in go/tests/ui/dialogs_list_
  scroll_test.go failed undefined (MaxOffset/Clamp-
  Offset/VisibleRows/PreloadWindow/LoadMoreNeeded/
  ScrollToReveal/ScrollbarThumb/PreloadScreens). Two
  spec bugs caught by re-derivation before GREEN:
  visible-walk case {top 133, viewH 100} spans rows
  1..4 (till 233 includes row 3 at top 214), and the
  short-track thumb at top 0 is (3, 27) not (30, 27);
  one more during GREEN: "partially below" reveal case
  was actually fully-visible (item [160,250) in view
  [160,260)) — the law correctly no-ops; fixed the case
  to current 100 → bottom-align 150. GREEN: 12 new, 72
  total PASS. gofmt, comment ban 286 clean, quick gate
  GREEN (windows-vet substitute for cmd/render/window).
  Landed as e38052c2 (WORKLOG trimmed to 283 lines —
  sessions 374-376 compressed, pins live in code);
  pushed, verify 42347578779 dispatched and reconciled
  SUCCESS at job AND step level (nix + test/vet/race/
  smoke + windows/js-wasm cross-builds) — 378 closed
  green.
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
