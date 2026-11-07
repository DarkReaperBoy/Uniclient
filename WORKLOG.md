# WORKLOG.md — the state file

Top: the **STATE block** — rewritten every session, the resume pointer for the next
agent. Then open items (severity order), then entries newest-first, terse (did /
evidence / next). The pre-2026-11-01 progress docs (BUGS.md, research/) were purged by
owner order — that history lives in git if ever needed.

## STATE

- front: session 376 — boot after full-wipe recycle
  #4 (env rebuilt: clone at 0259ee3f, go1.27.1, ayu-ref
  v7.2.9 + lib_ui e3d0582); TWO GUI slices landed:
  Material theme system (SchemeFor Light/Dark/Amoled,
  36 M3-baseline roles from Compose v0_210 tokens,
  WCAG ≥4.5) + dialogs-row internals (badge pill law,
  counter format, online-badge pos law, tagged/forum
  variants)
- next: the dialogs row widget — gio painting + Elm
  dialogs state on the pinned table; then the
  message-bubble kit
- owner-waiting: none
- last-gate: quick GREEN ×2 (37 ui + 11 gui = 48 PASS;
  windows-vet substitute for cmd+window); comment ban
  280 clean; verify 42332427263 in flight on 2cf8f9ff
  (theme slice) — second dispatch rides the dialogs
  push; reconcile both at boot

## Open items

| ID | where | what | evidence | next step |
|---|---|---|---|---|
| H-2 | verify/release yml | android APK + web (gh-pages) + Xvfb GUI legs parked until the new GUI | AGENTS.md §6/§8 | re-add with the GUI build (owner order pending) |
| H-3 | engine/cores API | 301+1 identifiers exported purely for the tests move (API noise: TsParseInit1, TsTrackRecvPID; audio's MicStop folded to micStop in session 368) | commit 27faa5a4, session 368 | fold into real APIs or de-export when tests are reworked during the GUI rebuild |

## Session 376 — wipe #4 boot: env rebuilt; Material theme system (M3 baseline + AMOLED) (2026-11-07)

- Boot: owner token → VM wiped clean (repo, toolchain,
  ayu-ref gone; sweep found zero credential traces —
  §0.2 held). Fresh clone at 0259ee3f; 375 closed
  green confirmed (verify 42264110055 + release
  42267096271 SUCCESS via API). go1.27.1 rebuilt from
  the env.sh recipe (modcache 1.1G); ayu-ref
  re-acquired (v7.2.9 tarball + lib_ui @ e3d0582,
  AyuGram fork). Baseline 23/23 + 11/11 green before
  any edit.
- The theme-system slice: ui/material seed → Scheme
  (36 roles) + Kind + SchemeFor(Light/Dark/Amoled),
  values pinned from Compose material3 tokens v0_210
  (ColorLight/ColorDarkTokens → PaletteTokens,
  Apache-2.0): light Primary #6750A4 / Surface #FEF7FF
  (matches the 375 seed — provenance now the full
  table), dark Primary #D0BCFF / Surface #141218.
  AMOLED = dark + pure-black chrome (Background/
  Surface/SurfaceDim/ContainerLowest → #000000),
  elevated containers keep dark lift (luma hierarchy
  pinned by test). Fixed-role family (M3 Expressive)
  deferred. app.View → SchemeFor(Light).Surface;
  SurfaceLight removed, elm gui pin updated same
  commit (same hex).
- RED (undefined: Kind/Light/Dark/Amoled/SchemeFor) →
  GREEN 8 tests / 31 ui total: light+dark anchors,
  AMOLED derivation, WCAG contrast ≥4.5 across 12
  pairs × 3 kinds, SurfaceTint==Primary, opaque,
  distinct, dark surface luma hierarchy. gofmt +
  comment ban (279 files) + quick gate GREEN
  (windows-vet substitute for cmd+window).
- The dialogs-row slice (geometry-table slice 5):
  unread badge — font 12 bold, height 19, padding 5,
  pill width max(textW+2p, 19), radius height/2,
  mark-dot 8 centered in a 19 cell (dialogs.style:
  78-80,636; unread_badge_paint.cpp:97-191); counter
  law narrow → "99+" >999 w/ mention, "99999+"
  >999999 (unread_counter_format.cpp:10-27); date —
  font 13 (=base), skip 5, baseline = semibold height
  − normal descent, name rect (68,10,w−78,semibold),
  name = semiboldFont = fsize 13 (lib_ui
  basic.style:55); chat-type skip 3, send-state skip
  20, text min 150 (fits min pane 68+150+10 ≤ 260),
  state icons 18, right-button gate = column min
  (dialogs.style:217,384,401; layout:114-124); online
  badge — 12ø stroke 3 dur 150, call 16, TTL 20, pos
  law ported from AyuUserpic::OnlineBadgePosition
  (ayu_userpic.cpp:81-99; round default — kMax-
  AvatarCorners 23 = lib_ui default, ayu_ui_settings
  .h:11) → (33,33) on the 46px photo, TTL (26,26)
  flush; row variants — tagged 72h/30/52, forum
  80h/32/8/14/21; width anim 120 (=universalDuration);
  narrow badge top 35 (pad+photo−19, bottom-aligned
  to photo); PaintBadges stack order + 5px spacing
  law, narrow max-2-badges gate (layout:165-314).
- RED (undefined: FontDialogsUnread + more) → GREEN
  6 tests / 37 ui total; the TTL-pos test caught a
  real porting bug (stroke=0 branch used −half not
  −badgeSize) — fixed, law now exact. Three
  vet-suspect compound conditions split (373 class).
  Gui suite recount: 11 tests (375 logged 12).
  gofmt + comment ban (280 files) + quick gate GREEN.
- Design 8/10: data-pinned with provenance and
  invariant tests; minus one — the M3 source is
  Compose's token table (m3.material.io shows
  swatches, no hex), the #FEF7FF cross-check ties
  them.

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
- The closure took 4 flake runs: vulkan headers
  (42257568354) → X11/Xlib.h inside vulkan.h
  (42259385966) → xcb.pc (42260395403) → SUCCESS
  (42261435344, vendorHash a0wRykh…, commit
  75944429). Each failure read from the job logs,
  each fix pushed atomically.
- Evidence: RED (package uniclient/ui/app not in
  std) → GREEN 12/12 + 23/23 tokens; quick gate
  GREEN (partitioned, windows vet of cmd+window
  completed); js/wasm ./... build GREEN; windows
  build GREEN (30.8MB); comment ban 278 files
  clean; gofmt clean. Local full gate machine-
  blocked at the native gotd compile (env.sh
  truth) — verify 42262264512 in flight on
  75944429 is the gate of record.
- Design rating 9/10: the pure-adapter split keeps
  the Elm core testable without a display; the one
  deduction — the cgo closure had to be discovered
  by CI iteration, a local nix/pkg-config pre-check
  would have caught it (no nix on this VM).

## Session 374 — geometry-table slice 4 re-mined after a full-wipe recycle: icons, window chrome, top bar, checkbox, ripple, scrollbar, toast (2026-11-06)

- Boot: full-wipe recycle (repo, toolchain AND ayu-ref
  lost) — the previous session's finished slice 4 was
  unpushed (token already dead) and died with it: rebuilt
  from zero per §3. Fresh clone at 910d959f, go1.27.1
  from the env.sh recipe, reference re-acquired (AyuGram
  v7.2.9 tarball + lib_ui @ e3d0582, full SHA
  e3d058223aea0b68938a07a7d436d67aaf2b1b30, AyuGram
  fork). Baseline 15/15 re-verified before any edit.
- Slice 4 mined: menu icons — sprite audit 582 files,
  base 24×24 (+@2x/@3x); menuWithIcons icon pos 15/5, pad
  54/8/17/8 (widgets.style:1699-1703). Window chrome —
  title height 24, button 36×24 sprite-filling, title
  font semibold 12 (widgets.style:1571-1595). Top bar —
  height 54, buttons 40/44/52, ripple 40 (y 7), icons
  32×32, title 24/17 max 20 semibold 14; dialogs buttons
  40 / calendar 32×35 / search-from 29 (info.style:137-
  256,905-959; dialogs.style:284-309). Checkbox — check
  22ø border 2 dur 120 (=universalDuration, basic.style:
  135) ripple pad 8, mark 14×10 at 4/7, margin 8, text
  10/2, check 8/8, disabled 0.5 (widgets.style:839-900);
  text-skip law from checkbox.cpp:750: 8+22+10=40. Ripple
  show 650 / hide 200 (widgets.style:703-707). Scrollbar
  — width 10, radius 2, min height 20, thumb min 40,
  insets 3/3/3, duration 150, hiding 1000, scrollBarMin
  40 (widgets.style:807-828). Toast — padding 19/13/19/
  12, margin 13, maxWidth 480, radius 8, fadeIn 200,
  fadeOut 1000, slide 160 (widgets.style:1552-1564).
- VerticalCenterOffset(container, content) added as a
  DERIVED helper — the reference's centering law
  (menu_action.cpp:131 top = (height-glyph)/2), proven
  by consumers: topBarSearch icon (4,11), dialogs menu
  icon (4,4), top-bar ripple y 7, back button 12, menu
  arrow 2.
- RED (undefined: MenuIconSize + 40 more identifiers) →
  GREEN 23/23 — same count as the lost session, the
  re-derivation converged. gofmt, comment ban (274
  files), vet clean (one tautology suspect-or split
  into two checks, session-373 class).
- CI: 42186245433 (slice 2, 5380141b) SUCCESS
  re-confirmed from the run page (13 min, all three
  jobs). 42187083372 (slice 3, eb014073, Verify #370)
  completed SUCCESS (2026-11-06T08:30Z) — session 373
  closed green. Push unblocked next session by a fresh
  owner token (§0.2 transient use): af2f4136 on main,
  verify.yml dispatched → run 42250138772; T-2 closed.

## Session 373 — geometry-table slice 3: boxes, menus, toggles, settings rows (2026-11-06)

- Slice 3 mined from v7.2.9: boxes (lib_ui layers.style
  38-125) — width 320 / wide 364, pad 24/14/24/8, radius 6,
  title font 16 semibold at 24/13 in a 48px bar (label max
  24), additional skip 9, row pad 24/0/24/0, top margin 8,
  max list 492, little/medium skips 10/20, buttons 34h
  (textTop 7, pad 6/10/10/10, font 14 semibold), checkbox
  text x 12; popup menus (lib_ui widgets.style defaultMenu/
  PopupMenu) — item pad 17/8/17/7, right skip 6, width clamp
  156-300, radius 6, scroll pad 8, anim 150/show 200; toggle
  (defaultToggle) — diameter 14, border 2, shift -2, dur
  150; settings rows — default 22/10/22/8 (text 20, toggle
  skip 22), chat-flavor 60/10/22/10 iconLeft 20, profile
  79/10/8/8 iconLeft 22 toggleSkip 20; row heights added as
  DERIVED helpers: MenuItemHeightFor(font)=font+15 → 28 at
  base 13; MainMenuRowHeight()=13+11+9=33.
- RED (undefined: BoxWidth) → GREEN 15/15; gofmt, comment
  ban, vet clean (another suspect-or split). Slice-2 CI
  still in flight at commit time — reconcile at next boot.

## Session 372 — geometry-table slice 2: the chat view (bubbles, radius system, composer) pinned (2026-11-06)

- Boot: workspace survived (no recycle); CI 42183334673
  reconciled SUCCESS on d49f0c2b — 371 closed green.
- Slice 2 mined from v7.2.9 (styles + consuming code, per
  the session-371 method law): bubbles — msgPadding
  11/8/11/8, msgMargin 16/6/56/2 (right reserves date+
  ticks), attached-top 0, photo 33 skip 40, msgMaxWidth 430,
  wide-mode formula max+2·skip+2·marginLeft = 542 (element.
  cpp:810-820); radius system — bubbleRadiusSmall 6
  (=roundRadiusLarge), large 16, slider max 16, AyuGram
  default 16 → both at max (chat_style_radius.cpp,
  ayu_settings.h:641), thumb radii 4/12; service — padding
  12/3/12/4, margin 10/10/10/2; fonts — name/service/date
  13 (semibold/semibold/regular); history list — bottom pad
  8, unread bar 32+3, photo-bubble min 200; composer —
  field 36→72 (rich 224, fade 6, anim 100ms), send/attach
  44×46, sendRight 2, pad 2/9/2/9, rest height 9+36+9=54
  (chat_helpers.style:1281-1310,1626-1648, compose
  controls cpp:5794-5810).
- RED (undefined: MsgMarginLeft) → GREEN 11/11; gofmt,
  comment ban, vet clean (one vet-suspect compound test
  condition split into two checks). No production code
  outside tokens; no AGENTS.md drift.

## Session 371 — owner-challenge audit: slice-1 breakpoints were assumptions — fixed onto the measured algorithm (2026-11-06)

- Owner challenged the 1:1 method ("would the style know the
  window inside a window?") → re-audit against the reference's
  LAYOUT CODE, not just styles. Confirmed the in-window model:
  MainMenu is a Ui::LayerWidget (window_main_menu.h:49); boxes
  (Ui::show) and PopupMenu context menus are layers too — styles
  mined/scheduled for all of them. But the audit caught a REAL
  defect: TwoPaneMinDp=600/ThreePaneMinDp=1000 were assumption
  leftovers from the pre-redirect §6 — never measurements.
- The reference computes boundaries (window_session_controller.
  cpp:2626-2676 computeColumnLayout): one-column when body <
  leftMin+mainMin (640); three-column only ≥ left+main+third
  (932) AND a third section requested (default OFF; window
  auto-extends when it can); dialogs = body×ratio clamped
  [260, body−380], default ratio 5/14 (core_settings.h:1083,
  non-MacStore path :1786); third default 0 → clamps to 292.
- Fix: TwoPaneMinDp/ThreePaneMinDp deleted; LayoutOneColumn-
  MaxWidth (640) + LayoutThreeColumnMinWidth (932) pinned as
  DERIVED consts (formula IS the pin); DialogsWidthRatioDefault
  =5/14, ThirdColumnWidthDefault=0. Test rewritten to pin the
  derivation + values; RED (undefined: LayoutThreeColumnMinWidth)
  then GREEN 7/7; gofmt/comment-ban/vet clean. AGENTS.md §6.4
  rewritten onto the measured semantics.
- Method law for the front: every slice mines styles AND the
  code that consumes them; derived constants stay derivations.
