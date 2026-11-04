# WORKLOG.md — the state file

Top: the **STATE block** — rewritten every session, the resume pointer for the next
agent. Then open items (severity order), then entries newest-first, terse (did /
evidence / next). The pre-2026-11-01 progress docs (BUGS.md, research/) were purged by
owner order — that history lives in git if ever needed.

## STATE

- front: session 362 — the TS constructor/setter cluster retired onto
  the scripted server: 11 defs cut (45→34, largest single retirement),
  11 tests across 7 files now drive real Authenticate journeys with
  server-side evidence (voice packets decrypted+codec-asserted,
  command reassembly/decompression byte-exact, ping/pong on the wire,
  gen+1 decrypt fallback proven end-to-end); zero production changes
- next: H-1 — the queuegap family onto S2C fragmented sending
  (scripted server gains sendFragmented/out-of-order pushes), then
  gotd tgtest for Telegram SetAuthed/SetCtx, then the GitHub cluster
- owner-waiting: the next direction; the GUI build order (design is law in AGENTS.md §6 — Elm loop,
  Telegram Desktop/Web/Android references, capability-projected, Gio)
- last-gate: local quick gate GREEN (session 362: tests/cores 47.8s,
  engine 6.2s, bootstrap 0.9s; gofmt + comment-ban clean — 272
  files); local -race CI-subset shape GREEN 28.2s, 0 races; 10×
  count=5 zero fails; CI dispatch pending this push

## Open items

| ID | where | what | evidence | next step |
|---|---|---|---|---|
| H-1 | cores testhooks*.go | ForTest* hooks are debt (§5.3): 34 left by def-count (session 362: TS constructor/setter cluster — 11 defs onto the scripted server — ForTestNewTsConnection/NewTeamSpeakCore/SetAuthed(TS)/SetMyClientID/SetTsConn + orphaned getters ForTestClientID/ClientInfoMu/TsSendAck/TsSendCommand/TsSendPong/NewTsChannelInfo; voice receive + C2S reassembly/decompress + ping/pong + PushAtGen + SharedIV landed in the harness; session 361: exec-harness pump + proof injection — 7 defs; session 360: group-call assertion family — 8 defs; session 359: ForTestNewMatrixCore → real Authenticate via mxAuthSurface, ForTestSetGroupPeers → real Close teardown; session 358: reads family → GetGroupCall projection, TS state-mirror family, ForTestNewMatrixCall → real ReconcileGroupMesh; sessions 356-357: rooms/members/audio pairs onto real journeys; sessions 353-355: mumble/IRC/DeltaChat/XMPP slices + orphan sweeps); remaining: queuegap family (needs S2C fragmented sending), TelegramCore SetAuthed/SetCtx (gotd tgtest), GitHub SetUsername/NewGitHubCore | session 362 entry | queuegap onto server-side fragmented S2C sends, then gotd tgtest, then the GitHub cluster |
| H-2 | verify/release yml | android APK + web (gh-pages) + Xvfb GUI legs parked until the new GUI | AGENTS.md §6/§8 | re-add with the GUI build (owner order pending) |
| H-3 | engine/cores API | 302 identifiers exported purely for the tests move (API noise: TsParseInit1, ForTest-adjacent) | commit 27faa5a4 | fold into real APIs or de-export when tests are reworked during the GUI rebuild |

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

## Session 361 — H-1 scripted-server front opened: TS scripted server drives the REAL Authenticate journey (2026-11-04)

- Boot: full-wipe recycle (workspace, toolchain and caches all
  gone); env.sh recovery verbatim — go1.27.1 checksum-verified
  (63d339f0…), modcache 990M, cold baseline 7m15s GREEN before any
  edit (cores 23.5s, engine 6.4s, bootstrap 0.9s). Session-360 CI
  already green in STATE (iter-1 + iter-2 SUCCESS).
- The front (the STATE next-pointer from 358's research): an
  in-process scripted TS server in go/tests/cores/
  teamspeak_scriptedserver_test.go speaking the REAL wire —
  init0/1/2/3/4 (server verifies the client's y == x^(2^level) mod n
  AND the random echoes), license proof (P256 omega, DER ECDSA over
  a 1-byte license so TsDeriveLicenseKey lands on the custom root),
  clientek ECDH (root = s·G with known s; sharedIV =
  SHA512(s·ekPub) ⊕ alpha‖beta — same value the client derives),
  real-key EAX command traffic both directions (0x30/0x31, gen
  tracking mirrored from tsTrackRecvPID incl. ±1 fallback), S2C
  acks, and a scriptable responder (SetResponder / Push /
  WaitCommand) for arbitrary journeys. S2C's 11-byte header (no cID)
  vs C2S's 13-byte mirrored exactly.
- Journey test (TestTeamSpeakScriptedServerAuthenticateJourney,
  named to ride the CI -race subset): real NewTeamSpeakCore + real
  Authenticate (vault-backed session store) → GREEN 0.68s,
  deterministic at -count=10 (6.7s). Asserts public API +
  server-side evidence: ServerName, GetDialogs ch:7 Lobby from the
  real channellist, TsExec round-trip over the encrypted wire,
  clientinit nickname on the server side, init2 echo valid, init4
  y valid, clientek identity proof valid (server verifies the
  client's P256 signature over ekPub‖beta with the omega from
  clientinitiv), client acks ≥1.
- REAL DEFECT FOUND+FIXED on first contact — the front's whole
  point: the handshake's initserver branch consumed the command
  without dispatching to TsHandleServerCommand, so
  virtualserver_name NEVER reached setServerName on the real wire
  path (the B-16 fix was only reachable synthetically; ServerName()
  stays "" after a real connect). Fix: t.TsHandleServerCommand(cmd)
  in the branch — one line, idempotent handler. RED seen live
  (ServerName = "" failure), GREEN after.
- Evidence: focused TS family GREEN (6.5s); quick gate GREEN (cores
  25.8s, engine 6.3s, bootstrap 0.9s); gofmt clean;
  strip_comments --check clean (272 files, 0 dropped). Def count
  unchanged at 52 — this iteration is the retirement vehicle; the
  TS internals hooks (ForTestCmdCh 19+ sites, the exec-harness
  pump, constructors, SetAuthed/SetMyClientID/SetTsConn,
  identity-race) start retiring onto it next iteration.
- Design rating 9/10: every server-side check (echo / y / proof)
  independently verifies OUR client's wire behavior; the responder
  surface turns every future TS test into a real journey.
- Iteration 2 (same session) — the exec-harness pump + proof
  injection RETIRED onto the scripted server: 7 defs deleted
  (ForTestCmdCh/ExecCh/ExecMu/ExecWait — the pump; ForTestFireProof/
  TakeProofs — proof injection; ForTestNewTsWant → NewTsWant
  exported constructor, the shape production already uses),
  newExecHarness + tsResp deleted. 18 tests rewritten across 7 files
  onto real journeys: exec silent/data/error, split-terminator,
  data-timeout (new pin), concurrent execs (B-35 on the real wire),
  TsExecVerified read-back family, servergroupclientlist read-back,
  talk-power capture (foreign clid security case via ordered pushes),
  join-refresh, proof channel/wrong-clid/wrong-name/stale-drain
  (observable sync: the stale notifyclientmoved must move self into
  ch:9 before the exec — the proof provably landed)/fields/mismatch.
  The pump's determinism regression test (CI 41790936340) retired
  WITH the pump — its subject was the synthetic injection ordering;
  the real-wire successors pin the same collection semantics
  (delayed terminator + quiet-timeout). TestTakeProofsDrainsStaleProof
  (unit pin) folded into the stale-drain journey.
- RED: defs deleted → vet `tc.ForTestCmdCh undefined (type
  *cores.TsConnection …)`.
- FLAKE HUNT → SECOND PRODUCTION DEFECT: -count=5 flaked ~1/3 runs
  (TestJoinChannelRefreshesTalkPower: talk_power never left unknown).
  Root cause: TsExecProof's proof path returned the instant a
  matching proof fired, abandoning the command's trailing terminator
  — the NEXT exec consumed the straggler error-ok as ITS response
  (empty-result cross-talk, B-35 family; triggerable against real
  servers whenever a notify push beats the error line — exactly what
  a real server does on clientmove). Deterministic RED pin:
  TestTSExecProofWaitsForTerminator (straggler 80ms, own response
  250ms → rows=[] proven live). Fix: a matching proof records its
  fields and the exec keeps collecting until the terminator or the
  500ms quiet window (finish() closure); the deadline path now also
  returns proof-only rows. After the fix: 3 × count=5 = 15
  consecutive full-family runs ZERO fails.
- Evidence: quick gate GREEN (cores 37.8s, engine 6.2s, bootstrap
  0.9s); gofmt clean; comment-ban clean; census ZERO refs to all 7
  deleted names + newExecHarness + tsResp. Defs 52→45.
- CI iter-2 41842704637 FAILED at the Race step → THIRD PRODUCTION
  DEFECT (pre-existing, only reachable once tests really run
  tsCommandLoop + Logout together): tsCommandLoop's `tc := t.tsConn`
  was an unsynchronized read racing Logout's `t.tsConn = nil` under
  t.mu (race report: Logout write vs tsCommandLoop read). The field
  has a whole class of such accesses (7 notify-case reads in
  TsHandleServerCommand reached from untracked exec-notify goroutines,
  tsSendVoicePacket, the reconnect teardown, Close, tsSaveSession).
  Fix: dedicated tsConnMu sync.RWMutex + tsConnGet/tsConnSet helpers;
  EVERY t.tsConn access in the file now flows through them (sweep
  script, exact-match asserts; mutex held only around the field
  access — mutex law clean; no lock inversion: tsConnMu never wraps
  t.mu). Post-fix: full family GREEN 19.1s, count=3 GREEN 54.7s,
  quick gate GREEN (37.2s/6.2s/0.9s), comment-ban clean.

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

## Session 354 — H-1 mumble/IRC/DeltaChat/XMPP state-mirror slices (2026-11-03) — condensed

- Boot: fresh sandbox — env.sh recovery verbatim (go1.27.1
  checksum-verified; modcache ~990M).
- Mumble slice, 5 defs → 0, onto production paths: ForTestNewMumbleCore
  → &MumbleCore{} + exported StoreServerPin; ForTestConnect → real
  Authenticate (proving mumbleGenerateCert on the wire);
  ForTestServerPins → store.Load + exact-fingerprint equality;
  ForTestSetTlsCert → real LoadCertificate from TempDir PEMs;
  ForTestChannels cut (orphan). RED: vet undefined. GREEN: full suites
  14.5s/6.0s/0.8s; gofmt + comment-ban clean; 98→93 defs. verify.yml
  41548671934 SUCCESS on 3a0e6362.
- IRC orphans 3 defs cut (receiver-verified zero users); DeltaChat
  peer-key cluster 4 defs → real GetContactEncryptionInfo; XMPP room
  orphans 2 defs; ForTestFeatures made load-bearing (registerPreAuth
  fails fast without IBR; mini XMPP server gained advertiseIBR +
  jabber:iq:register). 93→83 defs; verify.yml 41550641190 SUCCESS.
- Machine note: the MultiEdit tool rewrites whole files with SPACE
  indent — gofmt -w after EVERY edit + git diff -U0 review is routine
  (bit 353+354). vet on tests/cores compiles the whole test graph —
  first cold run ~7min after wipes.
