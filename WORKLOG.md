# WORKLOG.md — the state file

Top: the **STATE block** — rewritten every session, the resume pointer for the next
agent. Then open items (severity order), then entries newest-first, terse (did /
evidence / next). The pre-2026-11-01 progress docs (BUGS.md, research/) were purged by
owner order — that history lives in git if ever needed.

## STATE

- front: session 366 — the H-1 orphan sweeps: 16 defs cut
  (23→7) — the five STATE-listed targets (TS packet-state
  quartet, ForTestNewXMPPCore, ForTestSetUserID, pb/truncate
  helpers, ForTestNewRpcGuard) + 6 rewrite-orphaned TS hooks;
  TS quartet/XMPP/Matrix/RpcGuard families onto real wire
  journeys; github truncate wrapper inlined; RpcTimeout →
  public var; race pin: dead TestTruncate → TestRPCGuard|
  TestTSReceive
- next: H-1 — the final 7 defs to zero (TS identity trio
  ForTestTsSign/Omega/UID, ForTestTsTrackRecvPID cluster,
  ForTestNewTsIncomingCmd, ForTestMyClientID, groupPeer
  ForTestKey)
- owner-waiting: the next direction; the GUI build order (design is law in AGENTS.md §6 — Elm loop,
  Telegram Desktop/Web/Android references, capability-projected, Gio)
- last-gate: local full gate GREEN — focused family 11.9s, 2 ×
  count=10 zero fails, make test (cores 58.1s), vet, gofmt,
  strip check, js/wasm, census zero, defs 7; CI dispatch
  pending (session 366 open)

## Open items

| ID | where | what | evidence | next step |
|---|---|---|---|---|
| H-1 | cores testhooks*.go | ForTest* hooks are debt (§5.3): 7 left by def-count (session 366: orphan sweeps — 16 defs onto real wire journeys, testhooks_manual.go deleted; session 365: GitHub cluster — 2 defs onto the scripted GitHub API server via the api_base seam, 5 new wire journeys incl. first Authenticate/session-resume coverage; session 364: Telegram setter cluster — 4 defs onto the gotd tgtest scripted server; session 363: queuegap family — 5 defs onto S2C out-of-order/fragmented wire journeys; session 362: TS constructor/setter cluster — 11 defs onto the scripted server; session 361: exec-harness pump + proof injection — 7 defs; session 360: group-call assertion family — 8 defs; session 359: ForTestNewMatrixCore → real Authenticate via mxAuthSurface, ForTestSetGroupPeers → real Close teardown; session 358: reads family → GetGroupCall projection, TS state-mirror family, ForTestNewMatrixCall → real ReconcileGroupMesh; sessions 356-357: rooms/members/audio pairs onto real journeys; sessions 353-355: mumble/IRC/DeltaChat/XMPP slices + orphan sweeps); remaining: TS identity trio (ForTestTsSign/Omega/UID), ForTestTsTrackRecvPID cluster, ForTestNewTsIncomingCmd, ForTestMyClientID, groupPeer ForTestKey | session 366 entry | final sweeps to zero |
| H-2 | verify/release yml | android APK + web (gh-pages) + Xvfb GUI legs parked until the new GUI | AGENTS.md §6/§8 | re-add with the GUI build (owner order pending) |
| H-3 | engine/cores API | 302 identifiers exported purely for the tests move (API noise: TsParseInit1, ForTest-adjacent) | commit 27faa5a4 | fold into real APIs or de-export when tests are reworked during the GUI rebuild |

## Session 366 — H-1: orphan sweeps onto real journeys — 16 defs, testhooks_manual.go deleted (2026-11-05)

- Boot: session recycle landed mid-WIP — the sweep (hook
  deletions + test rewrites) was recovered intact from the
  uncommitted working tree; PAT re-verified (HTTP 200), env.sh
  recovery verbatim (go1.27.1), origin == 15c74a34 (365 closed
  green) — no cold baseline needed. Census-first recovery: every
  identifier the rewrites reference (PbEncode/PbDecode, NewXMPPCore,
  newTestVaultXMPP, mxAuthedCore, stickNext/authedCore/
  waitStuckEntered, PushAtGen/PushAtPID/NextPID/sendRaw) verified
  present before running anything.
- 16 defs cut (23→7): the five STATE targets — TS packet-state
  quartet (ForTestWithRecvInit/WithLastRecvPID/WithRecvGenID/
  RecvGenID, testhooks_manual.go gone), ForTestNewXMPPCore,
  ForTestSetUserID, pb/truncate helpers (ForTestPbEncode/
  PbDecode/Truncate), ForTestNewRpcGuard — plus 6 orphans the
  rewrites obsoleted (ForTestPktState, ForTestTsConn,
  ForTestTsDecryptRecv, ForTestTsHandlePacket, ForTestKey ×2).
- Production (2 files, minimal): github.go's truncate() wrapper
  deleted — all 8 sites call utils.TruncateEllipsis directly;
  telegram.go RpcTimeout const→var (the established
  TsExecVoidTimeout public-knob pattern). PbEncode/PbDecode were
  ALREADY exported in bale.go — those hooks were redundant
  wrappers, pure deletion. Zero other production changes.
- Rewrites onto real journeys: TS quartet — generation climb
  (PushAtGen 1→2 observed as ServerName transitions), tampered
  MAC (new PushCorruptAtPID: MAC-bit-flipped packet dropped,
  next good command still lands), replay (same-pID resend
  absorbed, pID+1 lands), hostile-silence (50 garbage packets
  via srv.sendRaw, zero stdout, good command survives); XMPP —
  SASL flood + download-cap tests now ride a real Authenticate
  against the mini server (new floodSASL server knob, 10s cap
  asserted on the clock); Matrix — newTestMatrix = mxAuthedCore
  (real whoami @me:test, 17 sites), unauthed case → plain
  NewMatrixCore(nil); RpcGuard trio — real stuck
  UsersGetFullUser on the tgtest wire: bounded by RpcTimeout,
  caller deadline preserved (50ms beats the 60s default),
  default applied (250ms enforced) — hungInvoker deleted.
- CI race pin: TestTruncate entry dead (its file deleted,
  coverage lives in ./tests/utils) → replaced with
  TestRPCGuard|TestTSReceive (the new concurrency-heavy wire
  families).
- Evidence: focused family GREEN (11.9s); 2 × count=10 = 20
  consecutive runs ZERO fails; full make test GREEN (cores
  58.1s, engine 6.7s, bootstrap 1.0s, utils 1.5s); go vet ./...
  GREEN; gofmt tree clean; strip_comments --check clean (272
  files, 0 dropped); census ZERO refs to all 16 deleted names;
  defs 23→7; js/wasm compile check GREEN. Local -race and
  windows crossbuild OOM-skipped on the gotd compile (env.sh
  machine truth) — the CI race leg carries the new families in
  the pin.
- Design rating 9/10: three slices were pure deletion of
  redundant wrappers; every rewrite moved assertions from
  struct surgery to wire/server-side evidence; RpcTimeout-as-var
  rides an established pattern, not a new seam.

## Session 365 — H-1: GitHub cluster onto the scripted GitHub API — 2 defs, api_base seam (GHE) (2026-11-05)

- Boot: session recycle landed between turns; PAT re-verified
  (HTTP 200), env.sh recovery verbatim (go1.27.1, modcache 1.1G,
  gocache 2.9G), repo clean at 5d6f6960 (364 closed green) — no
  cold baseline needed, nothing committed since.
- RED: 2 defs deleted from testhooks.go (ForTestSetUsername,
  ForTestNewGitHubCore) → vet `ForTestNewGitHubCore undefined`.
- Production seam: GitHubCore.apiBase + AuthConfig.Extra
  ["api_base"] — GitHub Enterprise support, the gh-CLI GH_HOST /
  go-github BaseURL class: all 8 hardcoded ghAPIBase sites route
  through it (buildURL, apiDelete, apiMutate + cache
  invalidation, notifications poll, emails/social DELETEs,
  graphql); graphqlURL() maps a /api/v3 GHE base to the
  documented /api/graphql pairing, dotcom default unchanged;
  persisted in ghSession so resume works against GHE; explicit
  cfg beats the saved base. Zero other production changes.
- Harness (github_scriptedserver_test.go): httptest GitHub API —
  mutex-guarded wire recorder (method/path/query/bearer/Accept/
  API-version/body), per-test handlers, authed-core factory; the
  poll loop never ticks under the 10s notif interval and Close()
  reaps it.
- Rewrites: CommentToMessage — username from a REAL whoami
  (octocat via GET /user); own comment outgoing + peer comment
  (mona) not-outgoing, the negative case is NEW. Download
  ceiling — the client is the real makeHTTPClient product and
  the download request's bearer is asserted server-side.
- New wire journeys (first real coverage of the GitHub
  Authenticate path): whoami (Authorization/Accept/
  X-GitHub-Api-Version pinned, no bootstrap POST when the
  profile repo exists, GetProfile's username-driven
  /users/octocat request); profile-repo bootstrap (404 → POST
  /user/repos with the exact 4-field body asserted); session
  resume through a real vault (saved token on the wire ×2, no
  token in cfg, no re-bootstrap); bad-token 401 terminal
  (exactly 1 request, ErrAuth, core stays unauthed); 429 →
  Retry-After: 0 → retried on the wire (exactly 2 GET /user).
- Evidence: focused family GREEN (1.1s); 2 × count=10 = 20
  consecutive runs ZERO fails; full make test GREEN (cores 52.8s,
  engine 6.6s, bootstrap 1.0s, utils 1.5s); make vet + lint
  GREEN; quick gate GREEN via scripts/gate.sh; js/wasm compile
  check GREEN; census ZERO refs to both deleted names; defs
  25→23; gofmt clean; strip_comments --check clean (274 files);
  go.mod unchanged (stdlib only — no flake.yml repin needed).
  Local -race and windows crossbuild OOM-skipped on the gotd
  compile (env.sh machine truth) — the CI race leg carries
  TestGitHub in the pin.
- Design rating 8/10: assertions moved from field injection to
  server-side wire evidence; the api_base seam is a genuine
  product capability (GHE), not test scaffolding; the graphql
  derivation rides the documented /api/v3 ↔ /api/graphql
  pairing.

## Session 364 — H-1: Telegram setter cluster onto the gotd tgtest scripted server — 4 defs, server-side freeze probes (2026-11-05)

- Boot: session recycle landed mid-WIP — the scripted-server
  scaffolding was recovered from the uncommitted working tree;
  PAT re-verified, env.sh recovery verbatim (go1.27.1, modcache
  1.1G, gocache 1.1G), no cold baseline needed (nothing
  committed since 363's green). Machine note (354's, still
  biting): scripted edits land SPACE-indented and gofmt
  re-aligns struct fields — gofmt -w after EVERY edit and
  never string-match unformatted code.
- RED: 4 defs deleted from testhooks.go (ForTestMu,
  ForTestSetApi, ForTestSetAuthed, ForTestSetCtx) → vet
  `ForTestSetApi undefined` at the first site.
- Harness (telegram_scriptedserver_test.go): a real tgtest
  MTProto server — RSA-keyed exchange, real-key encrypted RPCs,
  UnpackInvoke dispatch, scripted auth journey (sendCode →
  signIn → authorized-key registry), upload.getFile scripting,
  stickNext/watchType/countOf for server-side evidence. Three
  first-contact battles, all harness bugs not production:
  (1) gotd's racing dial (all DC candidates dial in parallel;
  losers close before their codec marker) killed tgtest's
  auto-detect listener — fixed with a warm listener that peeks
  the first byte and absorbs byte-free probe conns; (2) test-DC
  wire truth: the exchange validates DC+10000 while the served
  config must say ThisDC=2 — the stock config service
  overwrites ThisDC with the server DC so the client's onSession
  gate never fired (60s hang) — replaced with an own config
  handler; (3) the stuck RPC blocked the server's read loop so
  the pipelined Logout probe was never read — the stuck handler
  now responds asynchronously (SendErr from a goroutine;
  transport conn sends are writeMux-serialized). UploadFile.Type
  required (storage.filePartial) — its absence killed 593 conns.
- Rewrites: freeze family — the old ForTestMu write-lock probe
  becomes a second public API call (Logout) observed SERVER-SIDE
  (auth.logOut watcher) while the first RPC is stuck; per-case
  first-RPC pins taken from the real wire (3 table entries
  corrected by the failures themselves: channels.getChannels
  resolve-first ×2, auth.recoverPassword). Migrate family —
  ReadFilePart onto the real journey: FILE_MIGRATE_2 surfaces
  as parsed Type FILE_MIGRATE + Argument 2, gotd's redirect
  really runs (auth.exportAuthorization ×1 server-side) and
  retries on the same-DC sub-conn; byte-exact payload +
  offset/limit/precise/document-location asserted from the
  server-side request.
- Production change: TelegramConfig.PublicKeys + core field —
  the only seam (gotd must trust the scripted server's key);
  DialFunc was already public. Zero other production changes.
- CI race pin extended: TestChatOpenHotPaths|TestLogoutDoesNotHold|
  TestReadPathRPCs|TestReadFilePart ride the -race leg (local
  -race still OOM-skipped on the gotd compile — env.sh truth).
- Evidence: focused family GREEN; count=10 ×2 = 20 consecutive
  runs ZERO fails; full make test GREEN (cores 51.4s, engine
  6.5s, bootstrap 1.2s, utils 1.5s); gofmt clean;
  strip_comments --check clean (273 files, 0 dropped); census
  ZERO refs to all 4 deleted names; defs 29→25; go mod tidy
  (xxhash demoted to indirect — zero direct importers, stale
  direct since before; testify + nhooyr websocket ride along as
  tgtest's indirect deps). CI: first dispatch failed on the
  stale nix vendorHash (go.mod changed deps — the known §8
  flow); flake.yml 42025269748 pinned it; re-dispatch
  42025733121 SUCCESS at job AND step level — race leg green
  with the new family in the pin.
- Design rating 8/10: assertions moved from mutex surgery to
  server-side wire evidence; the DC+10000/read-loop/racing-dial
  discoveries are real protocol knowledge now pinned by the
  harness; PublicKeys is a genuine API need, not a test hook.

## Session 363 — H-1: queuegap family onto S2C out-of-order + fragmented wire sends — 5 defs, first S2C fragment-reassembly coverage (2026-11-04) — condensed

- Boot: full-wipe recycle; PAT re-verified, fresh clone, env.sh
  recovery verbatim; cold baseline 7m28s GREEN (cores 48.0s).
- Retired (5 defs, 34→29): ForTestRecvQueue/RecvQueueMu/
  TsProcessCommandQueue/NewTsDecryptedPkt + ForTestWithNextRecvID
  — the whole synthetic queue-surgery family; RED via vet.
- Harness: sendCmdPkt (explicit pID, real-key EAX, retransmit
  semantics), NextPID/PushAtPID, FragmentsAtPID/SendS2CFragment/
  PushFragmentedAtPID (S2C fragmented sends — FR on first+last,
  Compressed rides the first, mirroring the C2S scheme).
- Rewrites (2 tests → 3, real journeys on the CI -race pin):
  gap-log ids (held-vs-delivered through the fill), B-43
  once-per-gap with ordered-drain proof (base+2 wired first,
  delivered last), S2C fragment reassembly — FIRST coverage of
  fragBuf + single-compressed receive (plain/compressed/
  delayed-first-fragment sub-journeys).
- Flaws (mine): journey-transient gap lines (capture installed
  after the journey); TSan race on log capture (mutex-guarded
  writer). Zero production defects.
- Evidence: family GREEN; count=10 ×2 zero fails; local -race
  CI-subset GREEN 43s 0 races; full make test GREEN; census
  zero; CI 41895227385 SUCCESS at job AND step level.
- Design rating 9/10: public-API consequence + server-side ack
  evidence replaces queue-map surgery.

## Session 362 — H-1: TS constructor/setter cluster onto the scripted server — 11 defs (2026-11-04) — condensed

- 11 defs cut (45→34) incl. 6 hooks orphaned by the rewrites; 11
  tests / 7 files onto real journeys: identity-race pairs (paced
  floods, TSan the verifier), servername rename/fallback,
  sendcomp 6-case byte-exact, voice trio (decrypted codec+frame),
  move-race, fuzz core on the real chain, gen+1 decrypt fallback
  end-to-end. Harness: C2S fragment reassembly + QuickLZ, voice
  receive, S2C ping/C2S pong, PushAtGen, SharedIV, paced knobs.
  My flaws (not production): unescaped \s values, masked-nibble
  evidence, unpaced 2000-push bursts. Full suite + 2 × count=5
  zero fails; census zero. Design 9/10, zero production diff.

## Session 361 — H-1 scripted-server front opened: TS scripted server drives the REAL Authenticate journey (2026-11-04) — condensed

- Boot: full-wipe recycle; env.sh recovery verbatim (go1.27.1
  checksum-verified, modcache 990M), cold baseline 7m15s GREEN.
- The front: an in-process scripted TS server speaking the REAL
  wire — init0/1/2/3/4 with server-side y/echo verification,
  license proof, clientek ECDH to a known sharedIV, real-key EAX
  both directions with gen tracking + ±1 fallback, S2C acks, and a
  scriptable responder (SetResponder/Push/WaitCommand).
- REAL DEFECT FOUND+FIXED on first contact: the handshake's
  initserver branch never dispatched to TsHandleServerCommand, so
  virtualserver_name never reached setServerName on the real wire
  (B-16 only reachable synthetically). One-line fix, RED seen
  live. verify.yml legs 41790936340 + 41801710239 SUCCESS.
- Iteration 2: exec-harness pump + proof injection retired (7
  defs, 18 tests onto real journeys) and a SECOND production
  defect fixed — TsExecProof's proof path returned before the
  command terminator, so a straggler error-ok cross-talked into
  the next exec's result (B-35 family, triggerable on real
  servers when a notify push beats the error line). tsConn access
  race also fixed (dedicated tsConnMu, iter 3 CI 41846284509
  SUCCESS).

## Session 360 — H-1: group-call assertion family retired onto wire + update evidence (2026-11-04) — condensed

- 8 defs cut (61→53) + the unused wrtc import; 5 files / 17 tests
  onto wire evidence; iteration 2 deleted ForTestSetDeviceID (52
  defs, DEV2 identity from its own homeserver's whoami).
- Probes became assertions: real pion ICE gathering puts
  conf-tagged candidates on the wire DURING sendGroupOffer's
  GatheringCompletePromise wait; the renewal loop publishes
  membership PUTs at the MatrixRenewInterval knob rate and goes
  silent 4×interval after EndCall.
- Production (real observability): teardownGroupPeer = cleanupCall
  + UpdateCallState(Ended) with the dropped peer's user — wired
  into every group-peer teardown path (dropGroupPeer, reconcile
  toClose, joinGroupCall stale-conf, leaveGroupCallInternal).
- Proof patterns: pc existence → SDP markers on the invite; renew
  spy → ≥3 membership PUTs then silence; departed peer → per-peer
  Ended + re-add re-invite; foreign conf → zero traffic +
  non-interference journey.
- Evidence: family + full quick gate GREEN (cores 25.3s); census
  zero; local -race OOM-skipped (CI verdict); iter-4/5 CI runs
  41801127829 + 41801860069 SUCCESS. Design 9/10.
