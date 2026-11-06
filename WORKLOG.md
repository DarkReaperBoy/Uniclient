# WORKLOG.md — the state file

Top: the **STATE block** — rewritten every session, the resume pointer for the next
agent. Then open items (severity order), then entries newest-first, terse (did /
evidence / next). The pre-2026-11-01 progress docs (BUGS.md, research/) were purged by
owner order — that history lives in git if ever needed.

## STATE

- front: session 373 — geometry-table slice 3 pinned: boxes
  (dialogs), popup menus, toggles, settings rows — derived
  row-height helpers added; 15 invariant tests green
- next: table slice 4 — icons/dimensions audit (menu icon
  sizes, button icon boxes) + scrollbars/toasts if any; then
  the Gio skeleton (dep bump → full gate + CI)
- owner-waiting: none new (GUI build ordered 2026-11-06)
- last-gate: local legs green (15/15, gofmt, comment ban,
  vet); CI 42186245433 on 5380141b (slice 2) still running
  at session open; slice-3 dispatch recorded below

## Open items

| ID | where | what | evidence | next step |
|---|---|---|---|---|
| H-2 | verify/release yml | android APK + web (gh-pages) + Xvfb GUI legs parked until the new GUI | AGENTS.md §6/§8 | re-add with the GUI build (owner order pending) |
| H-3 | engine/cores API | 301+1 identifiers exported purely for the tests move (API noise: TsParseInit1, TsTrackRecvPID; audio's MicStop folded to micStop in session 368) | commit 27faa5a4, session 368 | fold into real APIs or de-export when tests are reworked during the GUI rebuild |

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

## Session 370 — GUI front opened: geometry-table slice 1 pinned from AyuGram v7.2.9 (2026-11-06)

- Boot: full-wipe recycle #3 — fresh clone at 223a89ac
  (369 closed green), toolchain rebuilt verbatim from the
  env.sh recipe (go1.27.1); no modcache refill needed
  (stdlib-only slice); gotd legs ride CI as ever.
- Reference acquisition: AyuGramDesktop v7.2.9 source
  tarball (GPLv3; measurements only, zero code copying,
  §6.8) + the pinned lib_ui submodule @ e3d0582 for the
  font tokens; kept OUTSIDE the repo (ayu-ref, untracked).
- Slice 1 pinned into go/ui/tokens (new package): window
  min/default/big-default (380×480 / 800×600 / 1024×768,
  window.style:13-17); pane columns (left 260–540, main
  ≥380, third 292–392, adaptiveChatWide 880, :34-39);
  dialogs row (62h, pad 10/8/10/8, photo 46, name/text
  x68 y10/y34, search block 38, dialogs.style:91-101,471);
  main-menu drawer (width 274, cover 134, userpic 48@24,20,
  name 26/84, status 26/103, skip 6, footer ≥80, button
  pad 61/11/20/9 icon 21 toggle 19, window.style:108-126 +
  window_main_menu.style:10-50); type scale (fsize 13,
  box 14, emoji 18, lib_ui basic.style:53-58); breakpoints
  (600/1000dp, §6.4 law).
- Drawer tree pinned: exact default entries + order +
  icons + labels (lang.strings) incl. the AyuGram toggles
  (SRead "Read on Server", Ghost Mode) with defaults from
  ayu_settings.h:675-691 (LRead/Streamer OFF, rest ON);
  bots = dynamic list slot (menu_main_menu_helpers.cpp).
- RED→GREEN: tests/ui/tokens_test.go first (compile fail:
  package not in std — RED seen), then the package; 7/7
  PASS. gofmt + comment ban + vet clean. AGENTS.md §7 tree
  gains the ui/ line (same commit, §10). No CI-dispatch
  blockers; dispatch id lands in the state commit.

## Session 369 — owner redirect: GUI design law rewritten (2026-11-06)

- Owner redirect (recorded, then executed): the rebuilt GUI
  targets **AyuGram Desktop's layout, 1:1** — window sizes,
  menus and their contents, spacing — under a **Material
  Design skin** (not AyuGram's pixel look), with **none of
  the reference's jank** and **every scenario tested**;
  desktop is the master design, mobile adapts it (Telegram
  Android explicitly rejected as a reference), web is the
  same WASM app (no separate web look), **no paid anything**
  (tools/assets/fonts free-open only). AGENTS.md line
  ceiling removed — the file must stay non-verbose instead.
- AGENTS.md: Direction + §6 rewritten — the 2026-11-01
  Telegram-references mandate (incl. "never AyuGram") is
  superseded; §6 gains the measured-1:1 mapping method
  (§6.8: geometry table as a pinned Go tokens file, golden
  overlay diffs, zero code copying — the GPLv3 C++/Qt
  reference contributes measurements only) and the cons-ban
  (§6.9); jank budget made hard law in §6.6 (60fps,
  one-frame input-to-paint, wrong-behavior severity);
  scenario completeness in §6.7; ceilings struck from
  §10/§11. README design-reference line synced.
- Docs-only change: no Go touched, no gate legs applicable.
  Push initially blocked (owner's first token 401 Bad
  credentials — dead, confirmed by the owner) → T-1 opened;
  owner supplied a fresh token out-of-band → 898d390c pushed
  (fast-forward onto 8863a8e9), T-1 resolved here. Token
  used transiently in the push URL only, never stored
  (§0.2). Build order still owner-only (§11); H-2/H-3
  unchanged, they ride with the GUI rebuild.

## Session 368 — H-1 audio tail: settle-race fix, then the ForTestMu retirement (2026-11-06)

- Boot: full-wipe recycle — fresh clone at 146cb147 (367
  closed green), toolchain rebuilt verbatim (go1.27.1,
  modcache 992M), wasm-runner contracts green.
- REAL DEFECT found by the retirement probe (js/wasm,
  wrong-behavior class): StopMic before getUserMedia settles
  → the cleanup goroutine Releases setup/failed while the
  settle microtask is still pending → "call to released
  function" console.error per attempt. Verified against
  go1.27.1 syscall/js source: released-func invocation is a
  console error, NOT a panic (func.go handleEvent);
  Release-while-running is explicitly legal (func.go:71) —
  the tail shape is sound. A real-browser journey: toggle
  the mic off before the permission prompt resolves.
- Fix (+9/-3, one file): promise.then(setup, failed).then(tail)
  — the settle-scoped trio (setup/failed/tail, tail
  self-releases) dies at settle; the cleanup goroutine keeps
  only fn (capture-scoped, after node teardown). A
  late-settling promise now cleans up instead of erroring.
- jsFakes gains a console.error sniffer (ConsoleErrors) —
  the misfire is otherwise silent under the runner; the
  shim passes through to the real console and restores on
  release.
- NEW TestStopMicBeforeSettleCleansUp: start → stop before
  settle → sleep (the yield that fires the microtask) →
  arm oracle (second StartMic must succeed — "mic already
  running" is the armed-state probe through the public API)
  → stop → settle → assert ZERO console errors. RED seen
  live (2 errors), GREEN after the fix.
- Evidence: focused RED then GREEN; full audio leg GREEN
  (0.72s); count=10 GREEN (6.3s); js vet OK; gofmt clean;
  strip clean; runner contracts green.
- Retirement (1 def → 0, WHOLE TREE ZERO):
  testhooks_audio.go deleted; MicStop de-exported to
  micStop (folded — exported in 27faa5a4 for the tests
  move; H-3 count 302+1 → 301+1); both webaudio tests
  dropped the *WebDevice type assertion (the Device
  interface carries every method they use). The
  armed-state assertions ride the public API: the R2
  leak pin moved into the second-StartMic oracle
  ("mic already running" = attempt still armed), the
  stop-disarm pin into TestStopMicBeforeSettleCleansUp.
- Census: ZERO ForTest in production packages — the only
  remaining matches are test-LOCAL helpers named *ForTest
  in tests/engine (never hooks); no testhooks* files left
  anywhere. The §5.3 lock-and-mutate hook class is
  extinct. H-1 CLOSED.
- Evidence (retirement): RED (vet: ForTestMu undefined)
  then GREEN; full audio leg GREEN ×2 (0.72s) + count=10
  (6.3s); js vet OK; js whole-module compile OK; native
  audio vet + native tests/audio OK; gofmt clean; strip
  clean. The quick-gate native importer-closure leg is
  cold-cache gotd-slow on this box (env.sh truth) — CI
  verify.yml dispatch is the gate of record.
- Design rating 9/10: the last hook died by pure deletion
  + oracle re-placement onto the public API; the
  retirement probe found and fixed a real wrong-behavior
  defect first — the pin strengthened, not weakened.
- CI: 42167382870 SUCCESS at job AND step level — race
  leg green, headless smoke green, js/wasm compile green
  — session 368 closed green.
