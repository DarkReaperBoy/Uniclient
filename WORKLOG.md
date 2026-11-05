# WORKLOG.md — the state file

Top: the **STATE block** — rewritten every session, the resume pointer for the next
agent. Then open items (severity order), then entries newest-first, terse (did /
evidence / next). The pre-2026-11-01 progress docs (BUGS.md, research/) were purged by
owner order — that history lives in git if ever needed.

## STATE

- front: session 364 — the Telegram setter cluster retired onto
  the gotd tgtest scripted server: 4 defs cut (29→25: ForTestMu/
  SetApi/SetAuthed/SetCtx), freeze + migrate families onto real
  Authenticate journeys with server-side stuck-RPC probes; one
  real seam added (TelegramConfig.PublicKeys); three harness
  battles won (warm listener vs gotd's racing dials, DC+10000
  exchange vs ThisDC=2 config, async stuck response vs the
  blocked server read loop); zero production changes beyond
  the seam
- next: H-1 — the GitHub cluster (ForTestSetUsername/
  ForTestNewGitHubCore onto a scripted HTTPS GitHub API)
- owner-waiting: the next direction; the GUI build order (design is law in AGENTS.md §6 — Elm loop,
  Telegram Desktop/Web/Android references, capability-projected, Gio)
- last-gate: CI 42025733121 SUCCESS at job AND step level
  (comment ban, gofmt, vet+live, test, RACE subset incl. the new
  telegram family, headless smoke, windows, js/wasm, nix) on
  2450d2c9 — after flake.yml 42025269748 pinned the vendorHash
  (first dispatch 42023904650 failed on the stale go-modules
  hash, the known §8 flow after dependency changes); local full
  make test GREEN (cores 51.4s); family count=10 ×2 zero fails
  — session 364 closed green

## Open items

| ID | where | what | evidence | next step |
|---|---|---|---|---|
| H-1 | cores testhooks*.go | ForTest* hooks are debt (§5.3): 25 left by def-count (session 364: Telegram setter cluster — 4 defs onto the gotd tgtest scripted server, freeze/migrate probes now server-side; session 363: queuegap family — 5 defs onto S2C out-of-order/fragmented wire journeys, first coverage of the client's S2C fragment reassembly + single-compressed receive; session 362: TS constructor/setter cluster — 11 defs onto the scripted server; session 361: exec-harness pump + proof injection — 7 defs; session 360: group-call assertion family — 8 defs; session 359: ForTestNewMatrixCore → real Authenticate via mxAuthSurface, ForTestSetGroupPeers → real Close teardown; session 358: reads family → GetGroupCall projection, TS state-mirror family, ForTestNewMatrixCall → real ReconcileGroupMesh; sessions 356-357: rooms/members/audio pairs onto real journeys; sessions 353-355: mumble/IRC/DeltaChat/XMPP slices + orphan sweeps); remaining: GitHub SetUsername/NewGitHubCore | session 364 entry | the GitHub cluster, then orphan sweeps to zero |
| H-2 | verify/release yml | android APK + web (gh-pages) + Xvfb GUI legs parked until the new GUI | AGENTS.md §6/§8 | re-add with the GUI build (owner order pending) |
| H-3 | engine/cores API | 302 identifiers exported purely for the tests move (API noise: TsParseInit1, ForTest-adjacent) | commit 27faa5a4 | fold into real APIs or de-export when tests are reworked during the GUI rebuild |

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

## Session 362 — H-1: TS constructor/setter cluster onto the scripted server — 11 defs, zero production changes (2026-11-04)

- Boot: full-wipe recycle (workspace AND toolchain gone); PAT
  re-verified (admin/push), fresh clone (remote URL kept token-free —
  credential-helper push instead), env.sh recovery verbatim: go1.27.1
  sha256 63d339f0… matches the 361 record, modcache 990M/1m26s, cold
  baseline 7m25s GREEN before any edit (cores 37.3s, engine 6.2s,
  bootstrap 0.9s, utils 1.3s).
- RED: 11 defs deleted from testhooks.go → vet `ForTestSetTsConn
  undefined` at the first site.
- Retired (11 defs, 45→34): ForTestNewTsConnection,
  ForTestNewTeamSpeakCore, ForTestSetAuthed(TeamSpeakCore),
  ForTestSetMyClientID, ForTestSetTsConn + the six hooks the rewrites
  orphaned: ForTestClientID, ForTestClientInfoMu,
  ForTestTsSendAck/TsSendCommand/TsSendPong, ForTestNewTsChannelInfo.
  ForTestTsConn + ForTestMyClientID survive with real users (the IV
  reuse + the write-landed assertion).
- Harness (scriptedserver_test.go): C2S fragment reassembly (first+
  last carry 0x10, compressed flag rides the first) + QuickLZ
  decompress + per-packet (pID, raw type byte) evidence; voice-packet
  receive (decrypt, count, last payload); S2C ping + C2S pong count
  (tsSendPong's first coverage); PushAtGen (S2C command under an
  arbitrary generation); SharedIV() + handleClientek's sharedIV writes
  moved under wireMu (latent harness race); OmitServerName +
  FloodCommands (paced 1ms/20) knobs; the harness chain TB-ified so
  the fuzz core rides the journey.
- Rewrites (11 tests / 7 files): identity-race pair — clientID via a
  paced 120-command flood during the handshake (the reader's per-packet
  acks read clientID HB-unordered against the initserver Store; TSan is
  the verifier) + 100 pings→pongs; myClientID via 100 SendMessage
  hammers (public clientInfoMu read) concurrent with the handshake
  write, write-landed asserted == 42. servername pair — real journey +
  rename through a real-wire initserver push (TsEscape'd), fallback via
  OmitServerName. sendcomp (6 cases) — SendMessage public path with
  server-side evidence: byte-exact decoded line, single-compressed vs
  raw-fragmented flags, sequential fragment pIDs. voice trio —
  server-side voice receive (codec byte 4 + opus frame asserted inside
  the decrypted payload — stronger than the old un-decryptable UDP
  peek). move-race — 2000 paced wire pushes vs a GetGroupCall hammer.
  fuzz core — real journey (the notifyconnectioninforequest skip
  removed: the harness now serves it). proto gen-retry unit test reuses
  the REAL handshake IV via srv.SharedIV() (zero new hooks) + NEW
  TestTS3DecryptGenRetryOnWire pins the gen+1 fallback end-to-end.
- First-run flaws (mine, not production): unescaped spaces in pushed
  initserver values (TsParseCommand correctly drops them — values ride
  \s); evidence recorded the masked high nibble instead of raw[12];
  unpaced 2000-push bursts overwhelmed the per-packet-goroutine receive
  chain (`go tsHandlePacket` per packet — out-of-order processing is a
  DESIGN property, the recvQueue reorders) → 2.7s stalls + B-43
  gap-log spam. Fixed by pacing + right-sizing the flood to 120 (TSan
  needs HB-unordered pairs, not volume). tsTrackRecvPID verified
  genMu-synchronized — no production defect found this round.
- Evidence: focused family GREEN; full suite GREEN (cores 47.8s,
  engine 6.2s, bootstrap 0.9s, utils 1.2s); 2 × count=5 = 10
  consecutive runs ZERO fails; local -race CI-subset shape GREEN
  28.2s, 0 races; quick gate GREEN via scripts/gate.sh; gofmt clean;
  strip_comments --check clean (272 files, 0 dropped); census ZERO
  refs to all 11 deleted names; defs 45→34.
- Design rating 9/10: every assertion moved to server-side decrypted
  evidence; zero new hooks; zero production diff.

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

## Session 360 — H-1: group-call assertion family retired onto wire + update evidence (2026-11-04)

- Boot: fresh sandbox — env.sh recovery; the toolchain go survived but
  toolchain/mod + toolchain/gocache were wiped; the previous session's
  gomodcache (990M) + gocache (3.6G) survived at my-project level, so
  GOMODCACHE/GOCACHE were re-pointed there (cache-warm builds ~2s).
  CI reconciliation: iter-4 41801127829 + iter-5 41801860069 both
  SUCCESS at job AND step level (race steps green) — session 359
  fully closed.
- Probes before design (scratch test, deleted after): real pion ICE
  gathering in the mesh harness puts conf-tagged m.call.candidates on
  the wire DURING sendGroupOffer's GatheringCompletePromise wait
  (host + srflx observed, 0.05s); at MatrixRenewInterval=120ms the
  renewal loop publishes membership PUTs ~8/s and goes fully silent
  after EndCall (4×interval window, 0.94s probe). Both probe outcomes
  became the new assertions.
- RED: 8 defs deleted from cores/testhooks.go (ForTestGroupPeers,
  ForTestGroupMu, ForTestGroupRenew, ForTestSetGroupRenew,
  ForTestCallsMu, ForTestActiveCalls, ForTestPc ×2 — tgCall's Pc was
  a zero-use orphan) + the now-unused wrtc import → vet
  `core.ForTestGroupMu undefined (type *cores.MatrixCore …)`.
- Production change (real observability, not test scaffolding):
  teardownGroupPeer(call) = cleanupCall + UpdateCallState(Ended)
  with Participants carrying the dropped peer's user — wired into
  every real group-peer teardown path: dropGroupPeer, reconcile's
  toClose sweep, joinGroupCall's stale-conf sweep,
  leaveGroupCallInternal's peer loop. A call UI needs exactly this
  signal to drop participants as their media paths die.
- Test rewrites (5 files; 17 GroupPeers reads, 33 GroupMu wraps, the
  renew spy, the 1:1 leak peek, the pc peek): peer+pc existence →
  pc-generated SDP markers on the wire invite (v=0/m=audio/
  a:fingerprint — an SDP cannot exist without the pc); candidates →
  REAL gathering-driven conf-tagged events; 1:1 leak →
  AcceptCall("conf_x") must stay ErrNotFound (public path); foreign
  conf → zero call traffic + a non-interference journey (correct-conf
  invite still gets answered — a foreign-conf peer would have
  occupied the peerKey and blocked it); departed peer → per-peer
  Ended update + re-add re-invite (the SECOND invite proves the map
  emptied; sendGroupOffer short-circuits on an open peer); renew spy
  → consequence-level wire proof (liveness precondition ≥3 membership
  PUTs at the shortened public MatrixRenewInterval knob, then
  4×interval silence after the empty-membership leave); "kept" cases
  → renewal STILL publishing + no Ended update + GetGroupCall alive.
  seededMeshCore shortens the interval (join-time capture; renew_test
  already used the same public knob at 20ms).
- Evidence: full matrix group-call family GREEN (17 rewritten tests +
  untouched neighbors, 7.0s focused run); quick gate GREEN via
  scripts/gate.sh (tests/cores 25.3s, engine 6.7s, bootstrap 1.3s;
  gofmt tree clean; strip_comments --check clean — 271 files, 0
  dropped); census ZERO refs to all 7 deleted names; defs 61→53
  (testhooks* def lines), 50 distinct names tree-wide. Local -race
  OOM-skipped on the gotd tg compile (env.sh machine truth) — the CI
  race leg is the verdict.
- Design rating 9/10: the update channel is UI-load-bearing; every
  wire proof is stronger than the state peek it replaces (the spy
  proved a func was called; silence proves the publishing stopped).
- Iteration 2 (same session) — ForTestSetDeviceID deleted (1 def, 1
  site): seedJoinedPair's second core now gets its DEV2 identity from
  its own homeserver's whoami (newMeshHomeserverAs(user, device)
  wrapper; newMeshHomeserver keeps the alice/DEV1 default) instead of
  a field injection — the mxAuthSurface pattern generalized. RED: vet
  `b.ForTestSetDeviceID undefined`. GREEN: mesh audio loopback family
  + full quick gate (cores 25.3s, engine 6.6s, bootstrap 1.0s);
  census zero. 52 defs.
