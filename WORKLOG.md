# WORKLOG.md — the state file

Top: the **STATE block** — rewritten every session, the resume pointer for the next
agent. Then open items (severity order), then entries newest-first, terse (did /
evidence / next). The pre-2026-11-01 progress docs (BUGS.md, research/) were purged by
owner order — that history lives in git if ever needed.

## STATE

- front: session 367 — H-1 cores retirement COMPLETE:
  testhooks.go deleted, 7 defs cut (7→0 in cores; whole-tree
  census keeps audio's js-only ForTestMu — 1 def left);
  identity trio onto wire evidence (EKProofValid + WhoAmI
  sha1-of-omega cross-derivation), myClientID via self-echo
  suppression + clid-7 positive control, wrap-bump pinned by
  the InitialCmdPID high-counter boot + gen-skipping first
  post-wrap pID, TsNewIncomingCmd constructor at both
  production wire sites, TsTrackRecvPID exported
- next: H-1 audio tail (audio/testhooks_audio.go ForTestMu, js/wasm leg) or the next front per owner; H-3 fold at GUI rebuild
- owner-waiting: the next direction; the GUI build order (design is law in AGENTS.md §6 — Elm loop,
  Telegram Desktop/Web/Android references, capability-projected, Gio)
- last-gate: CI 42075019094 SUCCESS at job AND step level
  (comment ban, gofmt, vet+live, test, race with the
  TestTS3*/TestHandshake* families in the pin, headless
  smoke, windows, js/wasm, nix; version==tag correctly
  skipped) on db994451; local full gate GREEN before
  dispatch — session 367 closed green

## Open items

| ID | where | what | evidence | next step |
|---|---|---|---|---|
| H-1 | cores testhooks*.go | ForTest* hooks are debt (§5.3): cores at ZERO (session 367 deleted testhooks.go — the final 7: groupPeer key pure-deletion, TsNewIncomingCmd constructor, self-echo myClientID journey, identity trio onto EKProofValid + WhoAmI cross-derivation, TsTrackRecvPID export + InitialCmdPID wrap journey; sessions 358-366 cut the other 61). Whole-tree remainder: audio/testhooks_audio.go ForTestMu (js/wasm-only mutex hook, §5.3 lock-and-mutate class) | session 367 entry | retire the audio tail with the WebDevice failure-injection API |
| H-2 | verify/release yml | android APK + web (gh-pages) + Xvfb GUI legs parked until the new GUI | AGENTS.md §6/§8 | re-add with the GUI build (owner order pending) |
| H-3 | engine/cores API | 302+1 identifiers exported purely for the tests move (API noise: TsParseInit1, TsTrackRecvPID) | commit 27faa5a4, session 367 | fold into real APIs or de-export when tests are reworked during the GUI rebuild |

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

## Session 361 — H-1 scripted-server front opened: TS scripted server drives the REAL Authenticate journey (2026-11-04) — condensed

- The front: an in-process scripted TS server speaking the
  REAL wire — init0-4 with server-side y/echo verification,
  license proof, clientek ECDH to a known sharedIV, real-key
  EAX both directions with gen tracking + ±1 fallback, S2C
  acks, scriptable responder.
- REAL DEFECTS FOUND+FIXED on first contact: the handshake's
  initserver branch never dispatched to TsHandleServerCommand
  (B-16 only reachable synthetically) — one-line fix, RED
  seen live; TsExecProof's proof path returned before the
  command terminator (straggler error-ok cross-talk, B-35
  family); tsConn access race (dedicated tsConnMu). CI runs
  41790936340 + 41801710239 + 41846284509 SUCCESS.

## Session 360 — H-1: group-call assertion family retired onto wire + update evidence (2026-11-04) — condensed

- 8 defs cut (61→53) + the unused wrtc import; 5 files / 17
  tests onto wire evidence; iteration 2 deleted
  ForTestSetDeviceID (DEV2 identity from its own homeserver's
  whoami). Probes became assertions: real pion ICE
  candidates on the wire DURING sendGroupOffer's gather
  wait; the renewal loop publishes membership PUTs at the
  knob rate and goes silent 4×interval after EndCall.
  Production: teardownGroupPeer wired into every group-peer
  teardown path. CI 41801127829 + 41801860069 SUCCESS.
  Design 9/10.
