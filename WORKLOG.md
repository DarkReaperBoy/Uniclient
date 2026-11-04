# WORKLOG.md — the state file

Top: the **STATE block** — rewritten every session, the resume pointer for the next
agent. Then open items (severity order), then entries newest-first, terse (did /
evidence / next). The pre-2026-11-01 progress docs (BUGS.md, research/) were purged by
owner order — that history lives in git if ever needed.

## STATE

- front: session 363 — the queuegap family retired onto S2C
  out-of-order + fragmented wire journeys: 5 defs cut (34→29),
  2 tests → 3 incl. four S2C-fragment sub-journeys (the client's
  fragBuf reassembly + single-compressed receive paths covered for
  the first time), held-vs-delivered and ordered-drain asserted
  through ServerName with ack evidence; a latent harness race
  (unsynchronized log capture) found by TSan and fixed; zero
  production changes
- next: H-1 — gotd tgtest for TelegramCore SetAuthed/SetCtx
  (research done: public TelegramConfig.DialFunc is the seam —
  dcs.Plain resolver, zero new hooks; freeze family's 45 subtests
  must share a SessionStorage so each core re-authenticates from
  the saved session, else the family's runtime explodes; probe
  becomes a second public API call observed server-side while the
  first RPC is stuck — may also retire TelegramCore ForTestMu),
  then the GitHub cluster (SetUsername/NewGitHubCore)
- owner-waiting: the next direction; the GUI build order (design is law in AGENTS.md §6 — Elm loop,
  Telegram Desktop/Web/Android references, capability-projected, Gio)
- last-gate: CI 41895227385 SUCCESS at job AND step level (comment
  ban, gofmt, vet+live, test, RACE subset, headless smoke, windows,
  js/wasm, nix) on f80c667c; local full make test GREEN (cores
  53.1s, engine 6.0s, bootstrap 0.9s, utils 1.2s); local -race
  CI-subset shape GREEN 43s, 0 races; count=10 ×2 zero fails —
  session 363 closed green

## Open items

| ID | where | what | evidence | next step |
|---|---|---|---|---|
| H-1 | cores testhooks*.go | ForTest* hooks are debt (§5.3): 29 left by def-count (session 363: queuegap family — 5 defs onto S2C out-of-order/fragmented wire journeys, first coverage of the client's S2C fragment reassembly + single-compressed receive; session 362: TS constructor/setter cluster — 11 defs onto the scripted server; session 361: exec-harness pump + proof injection — 7 defs; session 360: group-call assertion family — 8 defs; session 359: ForTestNewMatrixCore → real Authenticate via mxAuthSurface, ForTestSetGroupPeers → real Close teardown; session 358: reads family → GetGroupCall projection, TS state-mirror family, ForTestNewMatrixCall → real ReconcileGroupMesh; sessions 356-357: rooms/members/audio pairs onto real journeys; sessions 353-355: mumble/IRC/DeltaChat/XMPP slices + orphan sweeps); remaining: TelegramCore SetAuthed/SetCtx (gotd tgtest), GitHub SetUsername/NewGitHubCore | session 363 entry | gotd tgtest for the Telegram pair, then the GitHub cluster |
| H-2 | verify/release yml | android APK + web (gh-pages) + Xvfb GUI legs parked until the new GUI | AGENTS.md §6/§8 | re-add with the GUI build (owner order pending) |
| H-3 | engine/cores API | 302 identifiers exported purely for the tests move (API noise: TsParseInit1, ForTest-adjacent) | commit 27faa5a4 | fold into real APIs or de-export when tests are reworked during the GUI rebuild |

## Session 363 — H-1: queuegap family onto S2C out-of-order + fragmented wire sends — 5 defs, first S2C fragment-reassembly coverage (2026-11-04)

- Boot: full-wipe recycle (workspace AND toolchain gone); PAT
  re-verified, fresh clone (remote URL kept token-free), env.sh
  recovery verbatim: go1.27.1 sha256 63d339f0… matches the record,
  modcache 990M, cold baseline 7m28s GREEN before any edit (cores
  48.0s, engine 6.0s, bootstrap 0.9s, utils 1.2s).
- RED: 5 defs deleted → vet `ForTestRecvQueue undefined` at the
  first queuegap site.
- Retired (5 defs, 34→29): ForTestRecvQueue, ForTestRecvQueueMu,
  ForTestTsProcessCommandQueue, ForTestNewTsDecryptedPkt
  (testhooks.go) + ForTestWithNextRecvID (testhooks_manual.go) —
  the whole synthetic queue-surgery family. ForTestPktState
  survives (the decrypt-level gen-retry test still owns it).
- Harness gains (scriptedserver_test.go): sendCmdPkt primitive
  (explicit pID, real-key EAX 0x30, cmdPID advanced past the pID —
  real-server retransmit semantics, pIDs never reused),
  NextPID/PushAtPID (out-of-order pushes), FragmentsAtPID /
  SendS2CFragment / PushFragmentedAtPID (S2C fragmented sends:
  FR on first+last, Compressed rides the first and only when
  QuickLZ actually shrank — mirror of the client's C2S scheme).
- Rewrites (2 tests → 3, all real Authenticate journeys, named to
  ride the CI -race pin): gap-log ids — pushes at base+4/base+2,
  exact line parsing (expected id + queued-id set), fill at base
  proves held-vs-delivered (name becomes the fill's, second line
  lists both held ids). B-43 once-per-gap — 8 paced out-of-order
  arrivals → ONE line; ordered-drain proof: pID base+2 hit the
  wire FIRST yet ServerName lands "B2" (delivery strictly in pID
  order); fill order engineered (base+1 first, settle, then base)
  so the drain is atomic; new gap re-logs, same-gap extra packet
  does not. S2C fragment reassembly — FIRST coverage of the
  client's fragBuf + single-compressed receive paths: plain
  3-fragment, compressed 16-byte-chunk fragments (flag pins:
  first C+F, middles bare, last F-only), single compressed packet,
  delayed-first-fragment reassembling through a queue gap.
- First-run flaws (mine, not production): (1) journey-transient
  gap lines — initserver/channellistfinished back-to-back
  datagrams processed by racing per-packet goroutines fire an
  innocent transient gap log; fixed by installing the capture
  AFTER the journey (Authenticate's drain loop guarantees full
  delivery at return). (2) TSan: reading the capture buffer raced
  the receive loop's log.Printf — the old tests serialized via
  recvQueueMu, which wire journeys can't hold; fixed with a
  mutex-guarded tsGapLog writer (the SharedIV-class harness-race
  pattern). Zero production defects found this round.
- Evidence: family GREEN; count=10 ZERO fails (×2, before and
  after the race fix); local -race CI-subset shape GREEN 43s,
  ZERO races; full make test GREEN (cores 53.1s, engine 6.0s,
  bootstrap 0.9s, utils 1.2s); gofmt clean; strip_comments
  --check clean (272 files, 0 dropped); census ZERO refs to all
  5 deleted names; defs 34→29.
- Design rating 9/10: assertions moved from queue-map surgery to
  public-API consequence (ServerName through held/ordered
  delivery) + server-side ack evidence; the S2C fragment paths go
  from zero coverage to four sub-journeys.

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
