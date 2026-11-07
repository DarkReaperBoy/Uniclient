# WORKLOG.md — the state file

Top: the **STATE block** — rewritten every session, the resume pointer for the next
agent. Then open items (severity order), then entries newest-first, terse (did /
evidence / next). The pre-2026-11-01 progress docs (BUGS.md, research/) were purged by
owner order — that history lives in git if ever needed.

## STATE

- front: session 378 — the GUI kit build (post-skeleton);
  boot after full-wipe #5 (repo, toolchain, ayu-ref
  all gone): fresh clone at 5e6ba094, go1.27.1 + modcache
  1.1G rebuilt per env.sh recipe, ayu-ref re-acquired
  (AyuGramDesktop v7.2.9 + lib_ui @ e3d0582), baseline
  60 PASS re-verified; the dialogs LIST scroll slice
  (viewport/virtualization/thumb law) landed locally,
  gates GREEN, uncommitted-to-pushed pending
- next: reconcile the list-scroll CI verdict after
  dispatch; then the Elm + gio render leg of the list
  widget (viewport wiring into Model.Dialogs, scroll
  messages, thumb paint); then message-bubble kit;
  Material icon assets to un-defer icon paint
- owner-waiting: none
- last-gate: quick GREEN (60 ui + 12 gui = 72 PASS;
  windows-vet substitute for render/window/cmd); comment
  ban 286 clean; CI 42338432935 green (pre-slice
  baseline; new dispatch pending)

## Open items

| ID | where | what | evidence | next step |
|---|---|---|---|---|
| H-2 | verify/release yml | android APK + web (gh-pages) + Xvfb GUI legs parked until the new GUI | AGENTS.md §6/§8 | re-add with the GUI build (owner order pending) |
| H-3 | engine/cores API | 301+1 identifiers exported purely for the tests move (API noise: TsParseInit1, TsTrackRecvPID; audio's MicStop folded to micStop in session 368) | commit 27faa5a4, session 368 | fold into real APIs or de-export when tests are reworked during the GUI rebuild |

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
- Next: commit + push + dispatch Verify, reconcile;
  then the Elm/gio leg wiring Viewport into Model.
  Dialogs (scroll messages, clamp on reload, thumb
  paint via render Painter).

## Session 377 — the dialogs row widget: pure layout + Elm state + gio render (2026-11-07)

- Boot: workspace intact (no recycle); dialogs-row CI
  42333376504 (Verify #375) reconciled SUCCESS on
  056710b2 — 376 closed green. Baseline 37 ui + 11 gui
  = 48 PASS re-verified before any edit.
- The row-core slice: go/ui/dialogs (pure) — Entry
  (name, preview, date, unread/mark/muted, mention/
  reaction/poll, pinned, online/TTL, chat type, send
  state, tagged/forum, photo) + Layout(e, width,
  Metrics) as the pinned-law geometry function: name
  rect shrink order date(+5) → chat icon(+iconW+3) →
  send state(−20); date right-aligned, baseline =
  nameTop+semiboldH−normalDescent; badge stack right-
  anchored (dot 24 / pill w+5 / pinned 23 at textTop)
  then mention/poll ungated wide, max-2 narrow (pill-
  cell 19); narrow = width<130 → height 62, badges
  under photo (anchor 56, top 35); variants plain/
  tagged/forum/taggedForum 62/72/80/96, textTops
  34/30/32/32, tagTops 52/77 (NEW pins — dialogs.
  style:114-129 taggedForumDialogRow), online (43,43)
  / TTL (36,36) photo-absolute (dialogs_layout.cpp:
  92-347, dialogs_row.cpp:422-446 ComputeSt/
  recountHeight). List: Height/RowAt hit-testing. Elm:
  Model.Dialogs + DialogsLoaded/DialogRowPressed,
  selection clamped on reload. Font metrics inject
  via Metrics — formulas pinned, values from the
  runtime font stack (same class as the slice-5
  baseline law).
- go/ui/dialogs/render (gio): Painter (gofont
  collection, NoSystemFonts) — measure → Layout →
  paint; bg states (selected SurfaceContainerHigh /
  active PrimaryContainer — skin call); photo (image
  affine-scaled, circle-clipped / EmptyUserpic: hash
  color over scheme accents + initials 18 = 46·13/33
  semibold centered, empty_userpic.cpp:307; luma-
  switched ink); online dot presenceGreen #4DC920
  (lib_ui colors.palette:198) + 3px bg stroke ring;
  elided name/preview labels, date at baseline,
  counter centered in pill; muted pill Surface-
  ContainerHighest. Icon glyphs (chat-type, send-
  state, pinned/mention/poll, TTL) + tag strip +
  forum topics + right button + swipe deferred to
  the icon-asset and decoration slices — layout
  already reserves their geometry. golang.org/x/
  image promoted indirect→direct (v0.26.0 unchanged).
- RED (undefined: Layout/Entry/Metrics + msgs) →
  GREEN 11 new ui tests + 1 gui (60 total); gofmt;
  comment ban 284 files 0; quick gate GREEN (windows-
  vet substitute for render/window/cmd).

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

- Boot: owner token → af2f4136 pushed, verify
  dispatched (42250138772 → SUCCESS — 374 closed
  green); slice-3 run 42187083372 SUCCESS confirmed
  (373 closed green).
- go/ui/app — the pure Elm core (Model/Msg/Update/
  Cmd, zero Gio imports): the pane law as measured
  from the reference's own computeColumnLayout
  (window_session_controller.cpp:2626-2722, method
  law §6.8): single < 640 (leftMin+mainMin, dialogs
  gate), triple only ≥ 932 AND third requested
  (default off), else double; dialogs width =
  SafeRound(body×5/14) [round-half-away-from-zero =
  Go math.Round — countDialogsWidthFromRatio:2688]
  clamped ≥ 260 with NO 540 max (upstream line
  commented out, :2690) then min body−380; third =
  clamp(0,[292,392]) → 292; three-column shrink =
  proportional-to-min-clamped (shrinkDialogsAndThird
  Columns:2701-2723); no-dialogs shape drops the
  left column entirely (boundary 672). View(Model)
  = pure Scene. SafeRound half-cases verified by
  consumers: 800→286, 932→333.
- go/ui/window — the Gio adapter: window sized from
  tokens (800×600 default, 380×480 min), FrameEvent
  px→dp via Metric.PxToDp → Resized msg, cmd
  goroutines feed back via a 64-slot queue +
  Invalidate (§6.1 law shape), Running=false →
  system.ActionClose, paint = View background.
  go/ui/material seed: SurfaceLight #FEF7FF (M3
  baseline light surface). cmd/uniclient gains -gui.
  go/tests/gui: 12 Msg-sequence tests (boot/purity/
  quit, pane boundaries 639/640/931/932/672,
  dialogs widths, shrink, no-dialogs, resize journey
  380→933→third→quit).
- gioui.org v0.10.3 (§1.7, only windowing dep):
  current gio has NO pure-Go Linux desktop path —
  X11 is Xlib cgo now. cgo surface swept from the
  source: pkg-config x11 xkbcommon xkbcommon-x11
  x11-xcb xcursor xfixes egl wayland-client
  wayland-cursor wayland-egl + vulkan headers
  (dlopen). Pipeline synced same-commit (code wins):
  AGENTS §7 truth rewritten; gate.sh partitions
  scoped packages by gio import (native legs for
  pure, windows-vet substitute + explicit SKIP for
  gio — no root on this VM, Linux-native rides CI);
  verify.yml/release.yml apt steps; flake.nix
  closure (mirrors gio's own dev-shell recipe +
  libxcb/libXrender for the .pc Requires chain).
- The closure took 4 flake runs (42257568354 →
  42259385966 → 42260395403 → SUCCESS 42261435344,
  vendorHash a0wRykh…, commit 75944429), each failure
  read from job logs, each fix pushed atomically.
  Design rating 9/10 — the pure-adapter split keeps
  the Elm core testable without a display; deduction:
  the cgo closure had to be discovered by CI
  iteration (no local nix on this VM to pre-check).
- Evidence: RED → GREEN 12/12 + 23/23; quick gate
  GREEN (windows vet of cmd+window); js/wasm +
  windows builds GREEN; comment ban 278 clean;
  gofmt clean; local full gate machine-blocked at
  the native gotd compile — verify 42262264512 in
  flight on 75944429 is the gate of record.

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
