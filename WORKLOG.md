# WORKLOG.md — the state file

Top: the **STATE block** — rewritten every session, the resume pointer for the next
agent. Then open items (severity order), then entries newest-first, terse (did /
evidence / next). The pre-2026-11-01 progress docs (BUGS.md, research/) were purged by
owner order — that history lives in git if ever needed.

## STATE

- front: session 369 — owner redirect encoded in law: GUI =
  AyuGram Desktop layout 1:1 (measured geometry table,
  §6.8) under a Material Design skin, zero jank (§6.9),
  scenario-complete testing; desktop master design, mobile
  adapts it, web = same WASM app; AGENTS.md line ceiling
  removed (owner: never verbose either)
- next: the GUI build order (owner); first GUI-rebuild move
  per §6.8: the AyuGram geometry-table front; H-3 fold and
  H-2 legs ride with the GUI rebuild
- owner-waiting: GUI build order; a live push token
  (session-369 commit is local-only — token 401)
- last-gate: docs-only session, no gate legs applicable;
  prior green: CI 42167382870 on 128fbbf5 (session 368)

## Open items

| ID | where | what | evidence | next step |
|---|---|---|---|---|
| T-1 | repo push | session-369 docs commit is local-only: owner token rejected (GitHub 401 Bad credentials), no GH_TOKEN in sandbox env | curl 401 this session | NEEDS_OWNER: fresh token out-of-band, then push |
| H-2 | verify/release yml | android APK + web (gh-pages) + Xvfb GUI legs parked until the new GUI | AGENTS.md §6/§8 | re-add with the GUI build (owner order pending) |
| H-3 | engine/cores API | 301+1 identifiers exported purely for the tests move (API noise: TsParseInit1, TsTrackRecvPID; audio's MicStop folded to micStop in session 368) | commit 27faa5a4, session 368 | fold into real APIs or de-export when tests are reworked during the GUI rebuild |

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
  Commit is LOCAL — push blocked (owner token 401 Bad
  credentials; no GH_TOKEN in env) → open item T-1,
  NEEDS_OWNER. Build order still owner-only (§11); H-2/H-3
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

## Session 365 — H-1: GitHub cluster onto the scripted GitHub API — 2 defs, api_base seam (GHE) (2026-11-05)

- 2 defs cut (25→23: ForTestSetUsername,
  ForTestNewGitHubCore) onto a new httptest GitHub API
  harness (mutex-guarded wire recorder, per-test handlers).
- Production seam: GitHubCore.apiBase + AuthConfig.Extra
  ["api_base"] — GitHub Enterprise support: all 8 hardcoded
  ghAPIBase sites route through it, graphqlURL() maps /api/v3
  GHE bases to the documented /api/graphql, persisted in
  ghSession for GHE resume; dotcom default unchanged.
- 5 new wire journeys — the GitHub Authenticate path's first
  real coverage: whoami headers pinned, profile-repo
  bootstrap 404→POST /user/repos exact body, session resume
  through a real vault, bad-token 401 terminal, 429
  Retry-After retried on the wire. CommentToMessage
  outgoing-ness + DownloadFile ceiling onto real journeys.
- Evidence: family GREEN (1.1s); count=10 ×2 zero fails;
  make test GREEN (cores 52.8s); census zero; go.mod
  unchanged. CI 42033866337 SUCCESS. Design 8/10.

## Session 364 — H-1: Telegram setter cluster onto the gotd tgtest scripted server — 4 defs (2026-11-05)

- 4 defs cut (29→25: ForTestMu/ForTestSetApi/
  ForTestSetAuthed/ForTestSetCtx) onto a real tgtest
  MTProto server (RSA-keyed exchange, real-key encrypted
  RPCs, scripted auth journey, upload.getFile scripting).
- Three harness battles (all harness bugs, not production):
  gotd's racing dial vs tgtest auto-detect (warm listener
  absorbing probe conns); test-DC wire truth (exchange
  validates DC+10000 while served config must say ThisDC=2
  — own config handler); stuck RPC blocking the read loop
  (async SendErr from a goroutine).
- Rewrites: freeze family — ForTestMu mutex probe became a
  second public API call (Logout) observed SERVER-SIDE while
  the first RPC is stuck; migrate family — FILE_MIGRATE as
  parsed Type+Argument, gotd's redirect proven server-side,
  byte-exact upload.getFile assertions.
- Production: TelegramConfig.PublicKeys — the only seam.
  CI race pin extended to the new family. go mod tidy (xxhash
  → indirect). vendorHash repinned (flake.yml 42025269748);
  CI 42025733121 SUCCESS. Design 8/10.

## Session 363 — H-1: queuegap family onto S2C out-of-order + fragmented wire sends — 5 defs (2026-11-04) — condensed

- 5 defs cut (34→29): the synthetic queue-surgery family;
  2 tests → 3 real journeys: gap-log ids (held-vs-delivered
  through the fill), B-43 once-per-gap with ordered-drain
  proof, first S2C fragment-reassembly coverage (plain/
  compressed/delayed-first-fragment). Harness: sendCmdPkt,
  NextPID/PushAtPID, FragmentsAtPID/SendS2CFragment;
  TSan-fixed log capture (mutex-guarded writer). Zero
  production defects. Family + full gate GREEN; census zero;
  CI 41895227385 SUCCESS. Design 9/10.

## Session 362 — H-1: TS constructor/setter cluster onto the scripted server — 11 defs (2026-11-04) — condensed

- 11 defs cut (45→34) incl. 6 hooks orphaned by the rewrites;
  11 tests / 7 files onto real journeys: identity-race pairs
  (paced floods, TSan the verifier), servername rename/
  fallback, sendcomp 6-case byte-exact, voice trio (decrypted
  codec+frame), move-race, fuzz core on the real chain, gen+1
  decrypt fallback end-to-end. Harness: C2S fragment
  reassembly + QuickLZ, voice receive, S2C ping/C2S pong,
  PushAtGen, SharedIV, paced knobs. Full suite + 2 × count=5
  zero fails; census zero. Design 9/10, zero production diff.
