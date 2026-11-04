# WORKLOG.md — the state file

Top: the **STATE block** — rewritten every session, the resume pointer for the next
agent. Then open items (severity order), then entries newest-first, terse (did /
evidence / next). The pre-2026-11-01 progress docs (BUGS.md, research/) were purged by
owner order — that history lives in git if ever needed.

## STATE

- front: session 359 — CI reconciliation + harness determinism fix
  (fix run 41798479929 SUCCESS incl. race step) + H-1 iters 4-5:
  ForTestNewMatrixCore retired (7 sites onto real
  NewMatrixCore+Authenticate via mxAuthSurface) and
  ForTestSetGroupPeers cut (cleanup-guard plumbing onto the real
  Close/leaveGroupCallInternal teardown), 62 defs left
- next: H-1 — the remaining groupPeers/Mu/Renew/Pc assertion uses
  (meshwire/teardown/rejoin/roommember/leave read peer state to
  verify behavior; project through GetGroupCall or wire-level
  evidence), then the TS internals + Telegram SetAuthed/SetCtx +
  GitHub cluster (scripted-server front: ts3j-style TS server /
  gotd tgtest)
- owner-waiting: the next direction; the GUI build order (design is law in AGENTS.md §6 — Elm loop,
  Telegram Desktop/Web/Android references, capability-projected, Gio)
- last-gate: local quick gate GREEN (iter 5: tests/cores 19.0s,
  engine 6.4s, bootstrap 1.0s; gofmt + comment-ban clean; RED
  vet-undefined seen); CI: fix run 41798479929 SUCCESS on 6e847895;
  iter-4 41801127829 in flight on 9b49eb0f; iter-5 dispatch pending

## Open items

| ID | where | what | evidence | next step |
|---|---|---|---|---|
| H-1 | cores testhooks*.go | ForTest* hooks are debt (§5.3): 62 left by def-count (session 359 iters 4-5: ForTestNewMatrixCore → real NewMatrixCore+Authenticate via mxAuthSurface, ForTestSetGroupPeers → real Close teardown; session 358 iters 1-3: reads family → GetGroupCall projection, TS state-mirror family — 7 defs, ForTestNewMatrixCall → real ReconcileGroupMesh peers; session 357 iters 5-6: ForTestSetGroupMembers retired onto HandleGroupMemberEvent + audio pair onto real JoinGroupCall; session 356 iters 1-4: HandleMemberEvent + LiveDevices exported, rooms family + seededMeshCore retired onto real journeys; session 354: mumble/IRC/DeltaChat/XMPP state-mirror slices — 15 defs; session 353: injection, mumble-wire-codec, mumble-crypt families + 24-def orphan sweep); TelegramCore SetAuthed/SetCtx + TeamSpeakCore SetAuthed + TS internals (myClientID's sole write site = initserver handshake) + GitHub SetUsername/NewGitHubCore await a scripted-server front | session 358 entry | ForTestNewMatrixCore next, then the scripted front via ts3j-style TS server / gotd tgtest / GUI --script seam |
| H-2 | verify/release yml | android APK + web (gh-pages) + Xvfb GUI legs parked until the new GUI | AGENTS.md §6/§8 | re-add with the GUI build (owner order pending) |
| H-3 | engine/cores API | 302 identifiers exported purely for the tests move (API noise: TsParseInit1, ForTest-adjacent) | commit 27faa5a4 | fold into real APIs or de-export when tests are reworked during the GUI rebuild |

## Session 359 — H-1 iter 5: cleanup-guard plumbing retired onto real Close teardown (2026-11-04)

- RED: deleted ForTestSetGroupPeers from cores/testhooks.go → vet:
  "core.ForTestSetGroupPeers undefined" at
  matrix_groupcall_meshwire_test.go:145 (its sole use was teardown).
- Change: removed the 4 hook-based cleanup blocks (newMeshTestCore
  peer/renew/pc teardown; join/renew/rejoin renew-cancel guards).
  Covered by the REAL path since iter 4: every harness registers
  core.Close() → leaveGroupCallInternal takes groupMu, cancels
  groupRenew, cleanupCall per peer (cancel + pc.Close + Ended), then
  clears state. The leave/teardown prevRenew reads stay — they are
  ASSERTIONS (renewal identity no-hang pattern), not cleanup.
- Evidence: cores suite ok 22.1s; quick gate GREEN (tests/cores
  19.0s, engine 6.4s, bootstrap 1.0s); gofmt + comment-ban clean;
  census tree-wide = 62 defs.

## Session 359 — H-1 iter 4: ForTestNewMatrixCore retired onto real construction (2026-11-04)

- CI reconciliation: harness-fix dispatch 41798479929 SUCCESS on
  6e847895 (race step green — closes the iter-2 41790936340 FAILURE).
- RED: deleted ForTestNewMatrixCore from cores/testhooks.go (+ its
  now-unused mautrix import) → vet: "undefined: ForTestNewMatrixCore"
  at matrix_download_test.go:32.
- Migration (7 sites): newMeshTestCore (meshwire), renewTestCore
  (renew), newGroupTestCore (join), newCreateRoomTestCore (pl),
  download ×2 — all now NewMatrixCore(nil) + real
  Authenticate(AuthModeBot, tok, homeserver). Identity comes from the
  server: new shared mxAuthSurface(user, device, next) wrapper
  (matrix_test.go, mirrors the proven mxHarnessServer surface:
  POST */filter → f1, whoami → per-site user+device, keys/query →
  empty, keys/upload → empty counts, GET /sync → hang on
  r.Context().Done() so the syncer parks silently until Close).
  deviceID stays load-bearing (PartyID self-detection throughout the
  call code) so each server's whoami returns its DEV1.
- Defect found by migration: download tests used `defer hs.Close()`,
  which runs BEFORE t.Cleanup(core.Close) — the real-auth sync
  goroutine then retried against a dead server (hostile test
  180.01s). Fixed to t.Cleanup(hs.Close) registered before the core
  cleanup → 0.03s/0.01s. Scratch-probed the auth journey first:
  Authenticate itself 12ms; the stall was pure cleanup ordering.
- Evidence: full matrix family run ok 1.947s (download/mesh/join/pl/
  renew/reconcile/auth-journey/event/message); quick gate GREEN
  (tests/cores 18.3s, engine 6.6s, bootstrap 1.1s); gofmt + comment
  ban clean; ForTestNewMatrixCore zero refs tree-wide; census
  `rg -o '^func (\([^)]*\) )?ForTest\w+' go/ --glob '*.go'` = 63.
- Next: dispatch CI, then the groupPeers/renewal/mu hook cluster
  (mesh harness cleanups still lean on ForTestGroupMu/GroupPeers/
  SetGroupPeers/GroupRenew/Pc).

## Session 359 — CI reconciliation + exec-harness determinism fix (2026-11-04)

- Boot: token 401 with `token` prefix, works as `Bearer` (use Bearer).
  Reconciled: iter-2 run 41790936340 FAILURE — job 126443899068 step 9
  "Race (core subsets)": `TestGetGroupCallReportsTalkPowerBlocked:
  insufficient power Meta = "unknown", want blocked` (0.00s — no
  timeout, so not the 2s deadline: a row was dropped, not late);
  iter-3 41792038420 SUCCESS 8m47s on 1fc3924e (superset code) →
  latent harness race, not a product regression.
- Root cause: newExecHarness pump consumed cmdCh continuously and
  DROPPED cmds arriving while execWait=false. Tests queue responses
  BEFORE the exec call (talkpower_test does; older tests hide the race
  behind 30ms sleep-goroutines). Under -race on a slow CI runner the
  pump outruns the exec: data row dropped, error row forwarded first
  → empty rows → tsParseNeededTalkPower known=false → "unknown".
  Production tsCommandLoop never sees this window (a real server
  cannot respond before the request) — harness-only defect.
- Fix (tests/cores/teamspeak_exec_test.go, +59): pump buffers cmds
  received while unwaited and flushes them in order into the current
  execCh when a waiter exists (200µs ticker + flush-before-forward
  on the receive path; in-order via pending slice, non-blocking
  sends against the 64-buffer execCh).
- RED first: TestTSExecDeliversResponsesQueuedBeforeTheCall — row1 +
  16 fillers + late row + terminator; the 17th send proves (FIFO
  capacity arithmetic) row1 was consumed while unwaited → seen FAIL
  2.00s "no response to command within 2s (response lost)".
- First pump attempt (poll-until-waited) FAILED count=20 itself:
  `Meta = "blocked", want ok` — pre-committed receive fired into a
  dead execCh between execs. Buffer+flush design then passed count=20
  ×22 harness-family tests (exec/execseq/verified/talkpower/proof)
  138.9s GREEN.
- Race proof: local -race BLOCKED-env — gotd tg race-instrumented
  compile OOM-killed (4G RAM, even GOGC=10 GOMEMLIMIT=3GiB, 3.3G
  free); race leg = CI dispatch step 9 (unchanged product code since
  iter-3's green race run; only test files changed).
- Gate: quick GREEN (tests/cores 19.6s), gofmt clean, comment-ban
  clean (271 files). Next: dispatch verify.yml, then H-1
  ForTestNewMatrixCore.

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
  toolchain+caches+repo wiped; iteration re-applied from context via a
  deterministic python-replace script (exact-match asserts, tabs
  preserved — diff 55+/45- vs the edit-tool's 247+/237- whole-file
  rewrite) and re-gated GREEN before push. Lesson re-confirmed: commit
  the moment the gate is green — the sandbox owes nothing.
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
- TS-internals research (for the scripted-server front, next
  session): the ONLY production write to myClientID is the initserver
  branch inside Authenticate's handshake loop (teamspeak.go ~2200,
  reading tc.cmdCh directly — NOT reachable via TsHandleServerCommand);
  real reads live in the notifyclientupdated handler under clientInfoMu
  (~2390). The identity-race tests are currently synthetic on BOTH
  sides (5/10 — they prove the mutex works, not that production uses
  it); their honest rewrite needs the scripted TS server driving real
  Authenticate. ForTestCmdCh (19 sites) is the exec-harness backbone —
  same front. All TS internals + constructors therefore park as one
  cluster behind it.
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

- Iter 1: ForTestHandleMemberEvent retired — handleMemberEvent exported
  as HandleMemberEvent (sibling of the syncer's exported handlers).
- Iter 2: rooms family cut (ForTestRooms/SetRooms/RoomsMu, 6 sites)
  onto real GetChatInfo/fetchRoomState + the real /sync loop; exposed
  AND fixed: ForTestNewMatrixCore nil-map defect + the harness never
  served POST /user/{id}/filter (mautrix creates a filter before the
  first /sync — request-probe evidence x1/x0 → x1).
- Iter 3: seededMeshCore onto the REAL JoinGroupCall — conf adopted
  from server m.call state, real publishGroupMembership + renewal;
  seedCallState WRAPS the real renewal cancel (the replace-hang on
  Close, 57s test-timeout evidence).
- Iter 4: liveDevices exported as LiveDevices (member-content
  semantics). CI 41602626598 SUCCESS on ade20b8. Defs 83→78.

## Session 355 — Q-1 matrix logger quietness (2026-11-03) — condensed

- zerolog console writer hit STDOUT at DBG (corrupting the headless
  -events stream, leaking one-time keys); fixed in initCrypto: WRN
  default + stderr, DBG via UNICLIENT_MATRIX_DEBUG. Two journey tests
  pin it (quiet-by-default + opt-in) via stdout/stderr capture.
  Quick gate GREEN; CI 41591878823 SUCCESS.

## Session 354 — H-1 mumble/IRC/DeltaChat/XMPP state-mirror slices (2026-11-03)

- Boot: fresh sandbox — env.sh recovery followed verbatim (go1.27.1
  checksum-verified; modcache ~990M; cache-warm go build 5m29s).
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
