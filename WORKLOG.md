# WORKLOG.md — the state file

Top: the **STATE block** — rewritten every session, the resume pointer for the next
agent. Then open items (severity order), then entries newest-first, terse (did /
evidence / next). The pre-2026-11-01 progress docs (BUGS.md, research/) were purged by
owner order — that history lives in git if ever needed.

## STATE

- front: session 358 — H-1 Matrix reads family retired (iter 1:
  ForTestGroupConfID + ForTestGroupMembers → real GetGroupCall
  projection, 2 defs / 9 sites), 71 defs left
- next: H-1 — TS cluster (TeamSpeakCore ForTestChannels/ChannelsMu/
  ClientInfoMu + TsConnection hooks), then Matrix construction family
  (ForTestNewMatrixCall/ForTestNewMatrixCore), then Telegram SetAuthed/
  SetCtx cluster (scripted-server front)
- owner-waiting: the next direction; the GUI build order (design is law in AGENTS.md §6 — Elm loop,
  Telegram Desktop/Web/Android references, capability-projected, Gio)
- last-gate: local quick gate GREEN (iteration 1 redo: tests/cores 21.1s,
  engine 8.6s, bootstrap 1.5s, cold gocache; gofmt + comment-ban clean);
  CI: iteration-5/6 dispatches 41706457218 + 41707644864 = SUCCESS
  (session-357 stack closed green); iter-1 dispatch pending post-push

## Open items

| ID | where | what | evidence | next step |
|---|---|---|---|---|
| H-1 | cores testhooks*.go | ForTest* hooks are debt (§5.3): 71 left by def-count (session 358 iter 1: reads family ForTestGroupConfID/ForTestGroupMembers → GetGroupCall projection; session 357 iters 5-6: ForTestSetGroupMembers retired onto HandleGroupMemberEvent + audio pair onto real JoinGroupCall, conf/room/session setters + ForTestDeviceID getter cut; session 356 iters 1-4: HandleMemberEvent + LiveDevices exported, rooms family + seededMeshCore retired onto real journeys; session 354: mumble/IRC/DeltaChat/XMPP state-mirror slices — 15 defs; session 353: injection, mumble-wire-codec, mumble-crypt families + 24-def orphan sweep); TelegramCore SetAuthed/SetCtx + TeamSpeakCore SetAuthed (6 sites) + GitHub SetUsername/NewGitHubCore await a scripted-server front | session 358 entry | TS cluster next (TeamSpeakCore mirrors + TsConnection internals), then Matrix construction family, then the scripted front via ts3j-style TS server / gotd tgtest / GUI --script seam |
| H-2 | verify/release yml | android APK + web (gh-pages) + Xvfb GUI legs parked until the new GUI | AGENTS.md §6/§8 | re-add with the GUI build (owner order pending) |
| H-3 | engine/cores API | 302 identifiers exported purely for the tests move (API noise: TsParseInit1, ForTest-adjacent) | commit 27faa5a4 | fold into real APIs or de-export when tests are reworked during the GUI rebuild |

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
  clean (271 files, 0 dropped); census ZERO refs. Defs 73→71.
- Sandbox recycle mid-session (after the first GREEN, before commit):
  toolchain+caches+repo wiped; iteration re-applied from context via a
  deterministic python-replace script (exact-match asserts, tabs
  preserved — diff 55+/45- vs the edit-tool's 247+/237- whole-file
  rewrite) and re-gated GREEN before push. Lesson re-confirmed: commit
  the moment the gate is green — the sandbox owes nothing.

## Session 357 — H-1 Matrix group-call cluster: iterations 5-6, member-event seeding + the audio pair onto real journeys (2026-11-04)

- Boot: fresh sandbox — toolchain recovery per env.sh (go1.27.1
  checksum-verified via go.dev/dl?include=all — 1.27.1 is archived now,
  stable is 1.27.3; same 1.27.x line as go.mod); modcache refill
  990M/23s; cold baseline 7m06s GREEN before any edit (tests/cores
  17.2s, engine 6.2s, bootstrap 0.9s). CI reconciliation: iter-3
  41605557654 (ef733ab) + iter-4 41605805609 (8778e5a) = SUCCESS —
  the session-356 stack is fully closed green.
- Iteration 5: ForTestSetGroupMembers deleted (defs 78→77); all 4 user
  sites seeded through the REAL syncer-path handler — the same method
  matrix.go routes m.call.member state events to: seededMeshCore + the
  departed-peer overwrite (meshwire), seedJoinedPair +
  TestMatrixGetGroupCall (audio). Harness fireGroupMemberEvent:
  json.Marshal(MatrixCallMemberContent) → event.Content.VeryRaw →
  HandleGroupMemberEvent — full wire roundtrip, sender==state_key
  included. Seeding order pre-join/pre-conf: the handler's
  auto-ReconcileGroupMesh hits its own groupConfID=="" guard, so
  harness state stays byte-identical to the hook era (no seeding-time
  offers/peers — JoinGroupCall census-read in full first: adopt-conf,
  publish, renewal, never reconciles); the departed-peer overwrite now
  rides the handler's auto-reconcile — the real expired-device
  teardown journey.
- RED: def deleted → vet `c.ForTestSetGroupMembers undefined (type
  *cores.MatrixCore has no field or method ForTestSetGroupMembers)`.
  GREEN: tests/cores 17.9s PASS; quick gate GREEN over the import
  closure (cores+engine+bootstrap+cmd + 3 test suites: 17.8s/6.1s/
  0.9s); gofmt clean; strip_comments --check clean (271 files, 0
  dropped). ForTestGroupMembers (getter) survives on 2 member_test
  assertion sites — reads family, later slice. Design 9/10.
- Iteration 6: audio pair onto the real JoinGroupCall journey —
  ForTestSetGroupConfID/SetGroupRoomID/SetGroupSession deleted (3 defs,
  5 sites): seedJoinedPair + TestMatrixGetGroupCall now join for real
  (srv.setCallConf → join ADOPTS the conf from server m.call state,
  asserted via sess.ID; real session id from matrixNewSessionID; real
  publishGroupMembership PUT + renewal goroutine; member events still
  pre-join). ForTestDeviceID getter orphaned by the retirement (its
  last user was the session-pin line) — cut, grep census: def-only,
  zero users repo-wide. Defs 77→73.
- RED (iter 6): defs deleted → vet `c.ForTestSetGroupConfID undefined
  (type *cores.MatrixCore has no field or method ...)`. GREEN: quick
  gate GREEN over the import closure (cores 17.2s, engine 6.1s,
  bootstrap 0.9s); gofmt + comment-ban clean (271 files, 0 dropped).
- Pruned sessions 351-353 (git retains them) to hold §10's <300-line
  budget; the space-indent edit-tool lesson re-verified (gofmt -l
  caught all 3 edited files pre -w; diff -U0 reviewed, only intended
  lines changed).

## Session 356 — H-1 Matrix rooms+group-call state cluster: iteration 1 (2026-11-03)

- Boot: fresh sandbox — full toolchain recovery per env.sh (go1.27.1
  checksum-verified against go.dev/dl JSON; modcache refill 21s-equivalent;
  cold baseline 7m07s). Baseline green before any edit (tests/cores
  16.7s, engine 6.2s, bootstrap 0.9s). CI 41591878823 = SUCCESS on
  ae89c979 — session-355 Q-1 gate of record closed.
- Cluster census: 24 Matrix defs across rooms (ForTestRooms/SetRooms/
  RoomsMu), group-call state (Set/Get GroupConfID/GroupRoomID/
  GroupSession/GroupRenew/GroupMembers/GroupPeers, GroupMu, ActiveCalls,
  CallsMu, Set/Get DeviceID/UserID), method hooks (HandleMemberEvent,
  LiveDevices), construction (NewMatrixCall/NewMatrixCore, deferred
  family). Real read APIs found: GetGroupCall returns cs.ID == confID +
  participants (the groupMembers+rooms+liveDevices projection);
  MatrixCall.State exported (cleanupCall sets CallStateEnded);
  Authenticate starts the real sync loop → served /sync responses
  populate rooms through processJoinedRoom; fetchRoomState via
  GetChatInfo seeds rooms from real state GETs; JoinGroupCall is the
  real write path for the whole group state family.
- Iteration 1: ForTestHandleMemberEvent retired — handleMemberEvent
  exported as HandleMemberEvent (sibling-consistent with
  HandleMessageEvent/HandleGroupMemberEvent/HandleCallInvite, the
  syncer's exported handlers); syncer callback updated; 5 test users
  onto the real method; orphaned event import cleaned. Design 9/10.
- RED: vet `core.HandleMemberEvent undefined (type *cores.MatrixCore
  has no field or method HandleMemberEvent, but does have unexported
  method handleMemberEvent)`. GREEN: affected tests PASS; full quick
  gate GREEN (cores 16.9s, engine 6.1s, bootstrap 0.8s); gofmt clean;
  strip_comments --check clean (271 files, 0 dropped). Defs 83→82.
- Iteration 2: rooms family retired — ForTestRooms/SetRooms/RoomsMu
  deleted (3 defs, 6 user sites). Real paths: mxStateServer (journey
  base + rooms-state GET) seeded via GetChatInfo (fetchRoomState →
  ApplyStateEvent) for EventToMessage/PinnedEvents/membership tests;
  mxSyncServer (first /sync response, then long-poll hang) through the
  REAL sync loop for the GetDialogs timeline/LastEvent test (poll
  until 3 dialogs); meshServer.setRoomState + GetChatInfo for the
  roommember tests. Two defects exposed AND fixed: (1)
  ForTestNewMatrixCore built cores with nil rooms/directChats/
  activeCalls maps — real paths panicked (fetchRoomState
  assignment-to-nil-map); the hook now mirrors NewMatrixCore's map
  init. (2) the harness never served POST /user/{id}/filter —
  mautrix SyncWithContext creates a filter BEFORE the first /sync and
  the sync loop aborted on 404, so the hanging /sync handler was
  never reached (request-probe evidence: filter POST x1, GET /sync
  x0 before fix; x1 after). Q-1 logger quietness still holds under
  real sync traffic.
- RED (iter 2): defs deleted → vet undefined ForTestRoomsMu
  (+ grep census: 6 sites). GREEN: 6 rewritten tests PASS; full quick
  gate GREEN (cores 17.5s, engine 6.2s, bootstrap 0.9s); gofmt clean;
  comment-ban clean. Defs 82→79. Race note: sync goroutine now live
  in every mxAuthedCore test — all m.rooms access mutex-guarded; CI
  race leg is the verdict.
- Iteration 3: seededMeshCore (the shared harness behind 11 mesh
  tests) onto the REAL JoinGroupCall journey — meshServer serves the
  m.call state GET (setCallConf) so the join ADOPTS conf_x from
  server state (asserted via sess.ID), real publishGroupMembership
  PUT on the wire, real runGroupRenewal goroutine; the Set* trio
  (conf/room/session) is gone from the mesh path. Rejoin test now
  drives a real server-side conf CHANGE between joins (setCallConf
  "conf_new") — the actual rejoin-a-new-call scenario. seedCallState
  now WRAPS the real renewal cancel (flag + delegate) instead of
  replacing it — the old replace hung Close() forever once a real
  renewal goroutine existed (wg.Wait blocked; test timeout evidence
  at TestCloseWhileInCallTearsDown, 57s). ForTestSetGroupConfID/
  RoomID/Session defs survive on the audio pair (next iteration).
- GREEN (iter 3): mesh/teardown/rejoin/roommember sets PASS; full
  quick gate GREEN (cores 18.6s, engine 6.5s, bootstrap 0.9s);
  gofmt clean; comment-ban clean. No production change (pure test
  harness retirement). Defs stay 79. CI 41602626598 = SUCCESS on
  ade20b8 (iteration-2 gate of record).
- Iteration 4: ForTestLiveDevices retired — liveDevices exported as
  LiveDevices on MatrixCallMemberCall (member-content semantics,
  sibling of the exported MatrixNextRenewalAt/GroupPeersToConnect/
  GroupPeerKey family); 2 production callers updated. RED: vet
  `call.LiveDevices undefined ... unexported method liveDevices`.
  GREEN: full quick gate (cores 17.0s, engine 6.3s, bootstrap 0.9s);
  gofmt + comment-ban clean. Defs 79→78.

## Session 355 — boot reconciliation + Q-1 closed: matrix logger WRN/stderr with journey-pinned opt-in (2026-11-03)

- Boot: fresh sandbox — toolchain + gocache survived, mod cache wiped
  AND root-claimed (recycler artifact): old mod dir moved aside, fresh
  mod2 download 21s. Rootfs hit 99% twice: stale /home/z/repos (4G,
  deleted) was the real pig; PolarFS /tmp/my-project is too slow for
  caches (0.5–5.5MB/s small-file) but fine as TMPDIR (build temp).
  Session env: GOMODCACHE=toolchain/mod2, TMPDIR=/tmp/my-project/
  buildtmp (scripts/ucenv.sh outside the repo). Baseline green before
  any edit (cores 22.8s, engine 22.1s, bootstrap 25.6s). CI
  41550641190 = SUCCESS on b396c08a — session-354 slices 2–5 closed.
- Q-1 root cause worse than logged: zerolog.NewConsoleWriter() writes
  to os.STDOUT (not stderr) at DBG, dumping full request bodies incl.
  one-time-key material — the headless -events protocol stream gets
  corrupted by any authed matrix account. Probe evidence: test binary
  run directly showed " DBG Request completed … req_body=…" on stdout;
  go test hides passing-binary stdout, which is why the noise was
  invisible in earlier runs.
- Fix (7 lines, matrix.go initCrypto): level WarnLevel default,
  DebugLevel when UNICLIENT_MATRIX_DEBUG is set (read per-call so
  t.Setenv can pin it); console writer moved to os.Stderr. Mirrors
  mumble's UNICLIENT_MUMBLE_DEBUG shape.
- RED→GREEN: TestMatrixAuthJourneyQuietByDefault (no DBG/TRC on either
  standard stream through the real bot-token Authenticate journey,
  captured via os.Stdout/os.Stderr pipe swap + drain) and
  TestMatrixAuthJourneyDebugOptIn (opt-in DBG present on stderr,
  never on stdout) both FAILed on the unmodified tree with the
  captured noise as the failure message; both PASS after the fix.
  Harness: mxJourneyServer extracted from mxAuthedCore (behavior
  identical), mxRunCaptured/mxAuthJourneyCaptured reuse it; Close()
  waits m.wg so the capture is deterministic (no post-restore writes).
- Evidence: quick gate GREEN (tests/cores 24.9s, engine 22.7s,
  bootstrap 21.2s, vet scoped set incl. cmd/bootstrap/engine); gofmt
  clean; strip_comments --check clean (271 files, 0 dropped).
  verify.yml dispatched post-push (id at next boot).

## Session 354 — H-1 cores front, mumble state-mirror family: the last 5 mumble hooks retired onto real APIs (2026-11-03)

- Boot: fresh sandbox again — toolchain + caches wiped; env.sh recovery
  followed verbatim (go1.27.1, checksum-verified; modcache ~990M;
  cache-warm go build 5m29s). Census re-verified per-receiver: 98 defs /
  87 names, ZERO orphans by name — but MumbleCore.ForTestChannels is an
  orphan BY RECEIVER (name-level uses are all TeamSpeakCore's).
- Slice: mumble state mirrors, 5 defs → 0, all onto production paths —
  ForTestNewMumbleCore → &MumbleCore{} + exported StoreServerPin (the
  reset test gets a real Session store); ForTestConnect → real
  Authenticate(AuthConfig{Mode: AuthModeUser, Extra:{server,username}})
  — the engine entry, now also proving mumbleGenerateCert on the wire;
  ForTestServerPins → store.Load(&MumbleSessionData) + exact-fingerprint
  equality (stronger than the old not-wrong/not-empty in-memory read) +
  CertPEM persisted assertion; ForTestSetTlsCert → real LoadCertificate
  from PEM files written to TempDir; ForTestChannels cut (orphan).
  Design rating 9/10.
- RED: 5 defs deleted → tool-proven `undefined: ForTestNewMumbleCore`
  (vet, tests/cores) + one now-unused crypto/tls import cleaned.
- GREEN: all rewritten tests PASS (refuse-before-send 0-byte proof,
  proceed-on-match, reset-repins with persisted fp, pin-survives-cert-
  save through LoadCertificate); full tests/cores 14.5s, tests/engine
  6.0s, tests/bootstrap 0.8s; gofmt clean; strip_comments --check clean
  (271 files, 0 dropped); def-count 98→93. Race analysis: pin/cert
  writes happen-before the probe-read observation that gates every
  Close() — CI race leg is the verdict (rung 7).
- verify.yml 41548671934 = SUCCESS on 3a0e6362 (mumble slice gate of
  record; all jobs/step-level).
- Iteration 2 (same session) — IRC orphans, 3 defs cut: IRCCore
  ForTestChannels/ForTestChannelsMu/ForTestConnect — receiver-verified
  zero users (ForTestChannels* uses are TeamSpeakCore's; mumble's
  ForTestConnect uses died in iteration 1). Compile-green by
  construction; census greps in-session are the evidence; full suites
  green (14.8s/6.2s/0.8s).
- Iteration 3 (same session) — DeltaChat peer-key cluster, 4 defs → 0:
  ForTestPeerKeysMu/ForTestPeerStates/ForTestEntity retired onto real
  GetContactEncryptionInfo with EXACT-fingerprint equality (same power
  as the old byte-equality: different stored key ⇒ different
  fingerprint ⇒ mismatch; unparsed ⇒ "(unparsed)" string ⇒ mismatch);
  ForTestCallsMu (DeltaChat def) cut — its 2 users are MatrixCore's.
  RED: undefined ForTestPeerKeysMu (vet). GREEN: both rewritten tests
  PASS; full gate 14.3s/6.0s/0.9s; 86 defs.
- Iteration 4 (same session) — XMPP room orphans, 2 defs cut
  (ForTestRooms/ForTestRoomsMu on XMPPCore — all uses are MatrixCore's).
- Iteration 5 (same session) — XMPP ForTestFeatures retired by making
  the dead `advertised := c.features.IBR != nil; _ = advertised` read
  LOAD-BEARING: registerPreAuth now fails fast ("server does not
  advertise in-band registration") instead of sending a doomed stanza
  — honest behavior + a real consumer for the parsed feature. Mini
  XMPP server gained advertiseIBR mode + jabber:iq:register IQ
  handling (get → empty query; set → recorded creds + echoed query —
  ParseIBRResponse requires nsRegister in the result). Two behavioral
  journeys replace the parsing pin: register+auth end-to-end with
  exact registered-credential assertion, and refused-when-not-
  advertised. Design rating 8/10 (fail-fast = honest error class).
  RED: undefined ForTestFeatures. GREEN: all XMPP tests + engine auth
  journeys PASS; full gate 18.2s/6.1s/0.85s; 83 defs.
- verify.yml 41550641190 dispatched on b396c08a (covers iterations
  2–5; result lands at next boot).
- Machine note: the MultiEdit tool rewrites whole files with SPACE
  indent — gofmt -w after EVERY edit + git diff -U0 review is now
  routine (bit session 353 too). vet on tests/cores compiles the whole
  test graph — first cold run ~7min, budget for it after wipes.

