# WORKLOG.md — the state file

Top: the **STATE block** — rewritten every session, the resume pointer for the next
agent. Then open items (severity order), then entries newest-first, terse (did /
evidence / next). The pre-2026-11-01 progress docs (BUGS.md, research/) were purged by
owner order — that history lives in git if ever needed.

## STATE

- front: session 361 — the scripted-server front OPENED: an
  in-process TS server speaking the real wire (init crypto with
  y/echo verification, license proof, clientek ECDH, real-key EAX
  command traffic both ways, scripted responder) drives the REAL
  Authenticate journey; first-contact defect fixed (initserver's
  virtualserver_name never reached setServerName on the wire path)
- next: H-1 — retire the TS internals cluster onto the scripted
  server: ForTestCmdCh/ExecCh/ExecMu/ExecWait (exec-harness
  backbone, 19+ sites), ForTestSetAuthed/SetMyClientID/SetTsConn/
  NewTeamSpeakCore/NewTsConnection family, the identity-race
  rewrite (358 research: 5/10 synthetic on both sides); then gotd
  tgtest for Telegram SetAuthed/SetCtx, then the GitHub cluster
- owner-waiting: the next direction; the GUI build order (design is law in AGENTS.md §6 — Elm loop,
  Telegram Desktop/Web/Android references, capability-projected, Gio)
- last-gate: local quick gate GREEN (session 361: tests/cores 25.8s,
  engine 6.3s, bootstrap 0.9s; gofmt + comment-ban clean — 272
  files); CI: session-361 dispatch 41837816519 (bac31816) in flight;
  session-360 iter-1 41825704688 + iter-2 41827255692 both SUCCESS

## Open items

| ID | where | what | evidence | next step |
|---|---|---|---|---|
| H-1 | cores testhooks*.go | ForTest* hooks are debt (§5.3): 52 left by def-count (session 361: scripted TS server built — the retirement vehicle for the TS cluster; session 360: group-call assertion family — 8 defs onto wire/update evidence, teardownGroupPeer = per-peer Ended updates, ForTestSetDeviceID → whoami identity; session 359 iters 4-5: ForTestNewMatrixCore → real NewMatrixCore+Authenticate via mxAuthSurface, ForTestSetGroupPeers → real Close teardown; session 358 iters 1-3: reads family → GetGroupCall projection, TS state-mirror family, ForTestNewMatrixCall → real ReconcileGroupMesh peers; session 357 iters 5-6: ForTestSetGroupMembers retired onto HandleGroupMemberEvent + audio pair onto real JoinGroupCall; session 356 iters 1-4: HandleMemberEvent + LiveDevices exported, rooms family + seededMeshCore retired onto real journeys; session 354: mumble/IRC/DeltaChat/XMPP state-mirror slices — 15 defs; session 353: injection, mumble-wire-codec, mumble-crypt families + 24-def orphan sweep); TelegramCore SetAuthed/SetCtx + TeamSpeakCore SetAuthed + TS internals (ForTestCmdCh = exec-harness backbone, 19+ sites) + GitHub SetUsername/NewGitHubCore retire onto the scripted fronts | session 361 entry | TS cluster retirement onto the scripted server (ForTestCmdCh family first), then gotd tgtest, then the remaining matrix Set*/constructor defs |
| H-2 | verify/release yml | android APK + web (gh-pages) + Xvfb GUI legs parked until the new GUI | AGENTS.md §6/§8 | re-add with the GUI build (owner order pending) |
| H-3 | engine/cores API | 302 identifiers exported purely for the tests move (API noise: TsParseInit1, ForTest-adjacent) | commit 27faa5a4 | fold into real APIs or de-export when tests are reworked during the GUI rebuild |

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

## Session 359 — H-1 iters 4-5 + CI reconciliation + harness determinism fix (2026-11-04)

- Harness determinism: exec-harness pumped buffered pre-queued
  responses instead of dropping them (CI 41790936340 race-step
  failure root cause); fix run 41798479929 SUCCESS incl. race.
- Iter 4: ForTestNewMatrixCore deleted → 7 sites onto real
  NewMatrixCore(nil) + Authenticate via the shared mxAuthSurface
  wrapper (per-site whoami identity, keys endpoints, sync parked on
  the request context). Migration-found defect: download tests'
  `defer hs.Close` ran before core cleanup → the real-auth sync
  goroutine retried against a dead server (hostile 180.01s → 0.03s;
  fixed to t.Cleanup ordering).
- Iter 5: ForTestSetGroupPeers cut — the 4 hook-based cleanup blocks
  replaced by the REAL Close path (leaveGroupCallInternal: groupMu +
  renew cancel + cleanupCall per peer with pc.Close); the prevRenew
  reads kept as assertions (retired in session 360 by wire-silence).
  Evidence: quick gate GREEN (19.0s/6.4s/1.0s); 62 defs after iter 5.
- CI: iter-4 41801127829 + iter-5 41801860069 both SUCCESS at job and
  step level (reconciled at session-360 boot).

## Session 358 — H-1 reads family: ForTestGroupConfID/ForTestGroupMembers retired onto GetGroupCall (2026-11-04)

- Boot: fresh sandbox — go1.27.1 checksum-verified, modcache 990M/21s,
  cold baseline 7m05s GREEN before any edit (cores 17.8s, engine 6.3s,
  bootstrap 0.9s). CI reconciliation: iter-5 41706457218 + iter-6
  41707644864 = SUCCESS — session-357 fully closed green.
- Iteration 1: the reads family — ForTestGroupConfID +
  ForTestGroupMembers deleted (2 defs, 9 sites), every assertion onto
  the public GetGroupCall projection (CallSession.ID == conf;
  Participants == the member-content/live-device/room-join filter).
  member_test (was a bare &MatrixCore{} + map peek) now drives the full
  journey: seededMeshCore + wire member events + GetGroupCall
  participants — the spoof-dropped/honest-stored security property
  asserted through the real read path. teardown family: assertCallTornDown
  gains "call still observable through GetGroupCall" (after Logout/Close
  the core is un-authed: GetGroupCall = ErrAuth — the honest no-call for
  a dead core; renewal+peers+CallStateEnded complete the proof, all
  cleared atomically with conf in leaveGroupCallInternal). The
  TestLeaveChatWhileInCallTearsDown inline GetGroupCall duplicate
  dropped (helper covers it). renew joinedConf polls GetGroupCall
  (cs.ID) instead of the raw field. rejoin sites onto sess.ID.
  Design 9/10.
- RED: defs deleted → vet `core.ForTestGroupConfID undefined (type
  *cores.MatrixCore has no field or method ForTestGroupConfID)`.
  GREEN: quick gate over the import closure (cores 21.1s, engine 8.6s,
  bootstrap 1.5s — cold gocache); gofmt clean; strip_comments --check
  clean (271 files, 0 dropped); census ZERO refs. Defs 74→72 (the
  73/71 figures logged at the time were off by one; re-derived at
  iter 2 from a per-file HEAD census).
- Sandbox recycle mid-session (after the first GREEN, before commit):
  iteration re-applied from context via a deterministic python-replace
  script (exact-match asserts, tabs preserved) and re-gated GREEN
  before push. Lesson re-confirmed: commit the moment the gate is
  green — the sandbox owes nothing.
- Iteration 2: TS state-mirror family — 7 defs deleted
  (TeamSpeakCore ForTestChannels/ChannelsMu/MyChannelID/MyTalkPower/
  SetChannels + TsChannelInfo ForTestTalkPower/TalkPowerKnown),
  tsRefreshChannelTalkPower exported as TsRefreshChannelTalkPower
  (JoinChannel's real refresh path; sibling of TsExec/
  TsHandleServerCommand); ForTestNewTeamSpeakCore now mirrors real
  construction (msgBuffer/eventHandlers/channels/clientInfo maps —
  same nil-map class session 356 fixed on Matrix). 4 tests onto real
  journeys through the exec harness: talk-power capture asserted via
  GetGroupCall meta transitions (unknown→blocked→ok) over real
  channellist + channelinfo ingestion; the clid-mismatch security
  case (another client's power must NOT be captured); the concurrent
  move/read race now proves the move handler is live via
  self-in-participants through GetGroupCall. Census: ZERO refs.
  Design 9/10.
- RED (iter 2, reproduced surgically after a context-loss recycle:
  hooks-only patch on HEAD → vet `m.ForTestMyTalkPower undefined (type
  *cores.TeamSpeakCore has no field or method ForTestMyTalkPower)`);
  GREEN: quick gate over the import closure (cores 19.1s, engine 6.8s,
  bootstrap 1.0s); gofmt clean; strip_comments --check clean (271
  files, 0 dropped). Defs 72→65 (HEAD count re-derived: the old 71/73
  figures were off by one; all defs live in the 3 quarantine files,
  census method: rg '^func (\([^)]*\) )?ForTest' over testhooks*).
- TS-internals research (for the scripted-server front): myClientID's
  only production write is the initserver branch of the handshake
  (NOT reachable via TsHandleServerCommand); the identity-race tests
  are synthetic on BOTH sides (5/10); their honest rewrite needs the
  scripted TS server driving real Authenticate. ForTestCmdCh (19
  sites) is the exec-harness backbone — same front. All TS internals
  + constructors park as one cluster behind it. (Front landed in
  session 361.)
- Iteration 3: ForTestNewMatrixCall deleted (1 def, 4 sites) — every
  peer-call seeding now goes through the REAL ReconcileGroupMesh
  journey (the production MatrixCall constructor: pc + audioTrack +
  cancel, registered in groupPeers; the same path
  TestGroupReconcileSendsConfTaggedOffer already drove):
  seedCallState reconciles and reads the bob peer back through
  ForTestGroupPeers (groupPeers mirror family — separate slice);
  leave_test gains the prevRenew-wrap (delegate to the real cancel —
  the no-hang pattern) instead of replace-only; the departed-peer
  test now grows the peer via reconcile, then expires it via the
  member event + auto-reconcile; the ICE-candidates test sends
  conf-tagged candidates from the REAL peer call. Design 9/10.
- RED (iter 3): def deleted → vet `undefined: ForTestNewMatrixCall`
  (leave_test.go:22). GREEN: quick gate over the import closure
  (cores 20.6s, engine 6.7s, bootstrap 1.1s); gofmt clean;
  strip_comments --check clean (271 files, 0 dropped); census ZERO
  refs. Defs 65→64.

## Session 357 — H-1 Matrix group-call: iterations 5-6 (2026-11-04)

- Iter 5: ForTestSetGroupMembers retired (4 sites) onto the REAL
  HandleGroupMemberEvent syncer path (wire member events, sender==
  state_key; pre-join seeding order keeps harness state byte-identical;
  departed-peer overwrite rides the handler's auto-reconcile).
- Iter 6: audio pair onto the real JoinGroupCall —
  ForTestSetGroupConfID/SetGroupRoomID/SetGroupSession cut; join ADOPTS
  conf from server m.call state (asserted via sess.ID), real membership
  publish + renewal; orphaned ForTestDeviceID getter cut. Defs 78→74.
- CI: iter-5 41706457218 + iter-6 41707644864 = SUCCESS.

## Session 356 — H-1 Matrix rooms+group-call state cluster (2026-11-03)

- Iter 1: handleMemberEvent exported as HandleMemberEvent. Iter 2:
  rooms family cut (ForTestRooms/SetRooms/RoomsMu, 6 sites) onto real
  GetChatInfo/fetchRoomState + the real /sync loop; exposed AND fixed:
  ForTestNewMatrixCore nil-map defect + the harness never served POST
  /user/{id}/filter. Iter 3: seededMeshCore onto the REAL JoinGroupCall
  (conf adopted from server m.call state; seedCallState WRAPS the real
  renewal cancel — the replace-hang on Close, 57s timeout evidence).
  Iter 4: liveDevices exported as LiveDevices. CI 41602626598 SUCCESS
  on ade20b8. Defs 83→78.

## Session 355 — Q-1 matrix logger quietness (2026-11-03) — condensed

- zerolog console writer hit STDOUT at DBG (corrupting the headless
  -events stream, leaking one-time keys); fixed in initCrypto: WRN
  default + stderr, DBG via UNICLIENT_MATRIX_DEBUG. Two journey tests
  pin it (quiet-by-default + opt-in) via stdout/stderr capture.
  Quick gate GREEN; CI 41591878823 SUCCESS.

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
