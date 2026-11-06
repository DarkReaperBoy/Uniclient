# WORKLOG.md — the state file

Top: the **STATE block** — rewritten every session, the resume pointer for the next
agent. Then open items (severity order), then entries newest-first, terse (did /
evidence / next). The pre-2026-11-01 progress docs (BUGS.md, research/) were purged by
owner order — that history lives in git if ever needed.

## STATE

- front: session 371 — slice-1 breakpoints corrected onto
  the measured layout algorithm (640/932 derived, ratio
  5/14) after the owner challenge audit; tokens now pin
  derivations, not magic numbers
- next: table slice 2 — history/compose styles (bubbles,
  composer) from chat.style/chat_style.style/history_view;
  then slice 3 (settings/boxes/menus); then the Gio
  skeleton (dep bump → full gate + CI)
- owner-waiting: none new (GUI build ordered 2026-11-06)
- last-gate: CI 42181695686 SUCCESS on 1e9d03ea (slice 1,
  job and step level); 42183334673 dispatched on d49f0c2b
  (the fix) — reconcile at boot

## Open items

| ID | where | what | evidence | next step |
|---|---|---|---|---|
| H-2 | verify/release yml | android APK + web (gh-pages) + Xvfb GUI legs parked until the new GUI | AGENTS.md §6/§8 | re-add with the GUI build (owner order pending) |
| H-3 | engine/cores API | 301+1 identifiers exported purely for the tests move (API noise: TsParseInit1, TsTrackRecvPID; audio's MicStop folded to micStop in session 368) | commit 27faa5a4, session 368 | fold into real APIs or de-export when tests are reworked during the GUI rebuild |

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

## Session 367 — H-1: the cores final sweep — testhooks.go deleted, 7 defs cut (2026-11-06)

- Boot: full-wipe recycle — the whole sandbox (repo +
  toolchain) gone; fresh clone at b5337add (366 closed
  green), PAT re-verified (HTTP 200), env.sh recovery
  verbatim (go1.27.1, modcache 992M), the clone-token
  scrubbed from the remote URL (AGENTS.md §0.2).
- 7 defs cut (7→0 in cores): groupPeer ForTestKey — pure
  deletion, the key was always GroupPeerKey(UserID, Device)
  over exported fields; ForTestNewTsIncomingCmd —
  TsNewIncomingCmd constructor now used by BOTH production
  wire sites (receive loop + handshake) and the fuzz
  harness; ForTestMyClientID — replaced by the self-echo
  journey: server pushes notifytextmessage invokerid=42
  (our clid) → suppressed, invokerid=7 → surfaces
  (positive control), observed via OnUpdate — the race test
  keeps its 100-SendMessage hammer; identity trio —
  sign+omega already wire-pinned (EKProofValid, asserted in
  the journey test since 361), UID pinned by
  cross-derivation: WhoAmI (responder omits
  client_unique_identifier) must report base64(sha1(omega))
  with omega the SERVER-OBSERVED clientinitiv value (new
  harness ClientOmega()); the two unit tests deleted;
  ForTestTsTrackRecvPID — exported as TsTrackRecvPID (the
  TsParseInit1 helper class, H-3 census), the 3 scenario
  unit tests stay: dup idempotence, jitter/straggler
  no-bump semantics are masked by the ±1 decrypt fallback —
  not journey-observable.
- NEW wire journey TestTS3WrapClimbOnWire: the wrap-bump is
  only wire-provable through a generation SKIP (a same-gen
  or +1 packet self-heals via fallback+adoption), so the
  harness gains InitialCmdPID — the scripted server boots
  its command counter at 0xFFFD (a real server mid-life
  after 65k commands), channellistfinished lands at 0xFFFF,
  the client's nextRecvID wraps to 0x0000 naturally; the
  first post-wrap pID arrives gen-skipped (gen 2): it
  decrypts ONLY if the tracker proactively bumped to gen 1
  (then the alt-2 fallback lands; a stuck-at-0 tracker tries
  0 and 1 → drop). PushAtPIDGen(pID, gen) added (sendCmdPkt
  was gen-0 only).
- Discovery: command S2C packets decrypt AT ARRIVAL (the
  tracker runs then) but deliver IN pID ORDER (the queuegap
  queue) — arbitrary-pID pushes get held; the voice slot
  bypasses tsDecryptRecv entirely (reads recvGenID
  directly, no per-pID tracking).
- Production (1 file, +8/-4): TsNewIncomingCmd constructor;
  tsTrackRecvPID → TsTrackRecvPID (2 call sites). Zero
  other production changes; go.mod unchanged.
- Evidence: focused family GREEN (12.0s); 2 × count=10 = 20
  consecutive runs ZERO fails (118.5s + 118.6s); full make
  test GREEN (cores 59.1s, engine 6.1s, bootstrap 0.9s,
  utils 1.3s); vet + gofmt tree clean; strip check clean
  (271 files, 0 dropped); census ZERO ForTest in cores
  (whole tree: audio's js-only ForTestMu remains, logged in
  H-1); js/wasm compile GREEN. Local -race/windows
  OOM-skipped (env.sh truth) — the CI race pin carries
  TestTS3*|TestHandshake* (the new tests auto-in by prefix).
- Design rating 9/10: five slices pure-deletion or
  constructor-promotion onto established patterns; every
  replaced assertion moved to wire/server-side evidence;
  the wrap journey pins previously unpinned protocol
  semantics through a realistic high-counter boot instead of
  state surgery.
- CI: 42075019094 SUCCESS at job AND step level — race leg
  green with the new TestTS3IdentityProofAndUIDOnWire/
  TestTS3WrapClimbOnWire/TestHandshake* in the pin —
  session 367 closed green.

## Session 366 — H-1: orphan sweeps onto real journeys — 16 defs, testhooks_manual.go deleted (2026-11-05)

- Boot: session recycle landed mid-WIP — the sweep recovered
  intact from the uncommitted working tree; PAT re-verified,
  env.sh verbatim (go1.27.1), origin == 15c74a34 (365
  green). Census-first recovery: every identifier the
  rewrites reference verified present before running.
- 16 defs cut (23→7): the five STATE targets — TS
  packet-state quartet (testhooks_manual.go gone),
  ForTestNewXMPPCore, ForTestSetUserID, pb/truncate
  helpers, ForTestNewRpcGuard — plus 6 rewrite-orphaned TS
  hooks (ForTestPktState/TsConn/TsDecryptRecv/
  TsHandlePacket/ForTestKey ×2).
- Rewrites onto real journeys: TS quartet — gen climb
  (PushAtGen 1→2 as ServerName transitions), tampered MAC
  (new PushCorruptAtPID: dropped, next good command lands),
  replay (same-pID absorbed), hostile silence (50 garbage
  packets, zero stdout); XMPP SASL-flood + download-cap on
  a real Authenticate (new floodSASL knob, 10s cap on the
  clock); Matrix newTestMatrix = mxAuthedCore (17 sites);
  RpcGuard trio on a real stuck UsersGetFullUser — bounded
  by RpcTimeout, caller deadline preserved, default applied.
- Production (2 files, minimal): github.go truncate()
  wrapper inlined to utils.TruncateEllipsis (8 sites);
  telegram.go RpcTimeout const→var (the established
  public-knob pattern). PbEncode/PbDecode were already
  exported — pure deletion. CI race pin: dead TestTruncate →
  TestRPCGuard|TestTSReceive.
- Evidence: family GREEN (11.9s); 2 × count=10 zero fails;
  make test GREEN (cores 58.1s); vet/gofmt/strip clean;
  census zero; defs 23→7; wasm GREEN. CI 42062309084
  SUCCESS at job AND step level — session closed green.
