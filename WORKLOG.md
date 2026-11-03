# WORKLOG.md — the state file

Top: the **STATE block** — rewritten every session, the resume pointer for the next
agent. Then open items (severity order), then entries newest-first, terse (did /
evidence / next). The pre-2026-11-01 progress docs (BUGS.md, research/) were purged by
owner order — that history lives in git if ever needed.

## STATE

- front: session 356 — H-1 Matrix rooms+group-call state cluster (the
  big one) in progress; iterations 1-2 done (HandleMemberEvent exported;
  rooms family retired onto real ingestion), 79 defs left
- next: H-1 Matrix cluster iterations — group-call state seeding via
  real JoinGroupCall (SetGroupConfID/SetGroupRoomID/SetGroupSession/
  SetGroupRenew), members via HandleGroupMemberEvent (SetGroupMembers),
  reads via GetGroupCall (conf ID = cs.ID, participants) + wire puts +
  MatrixCall.State; then TS cluster, then construction family
  (ForTestNewMatrixCall/ForTestNewMatrixCore)
- owner-waiting: the next direction; the GUI build order (design is law in AGENTS.md §6 — Elm loop,
  Telegram Desktop/Web/Android references, capability-projected, Gio)
- last-gate: local quick gate GREEN (iteration 2: tests/cores 17.5s,
  engine 6.2s, bootstrap 0.9s; gofmt + comment-ban clean); CI:
  iteration-1 dispatch in flight, iteration-2 dispatch rides with its
  push

## Open items

| ID | where | what | evidence | next step |
|---|---|---|---|---|
| H-1 | cores testhooks*.go | ForTest* hooks are debt (§5.3): 79 left by def-count (session 356 iters 1-2: HandleMemberEvent exported + rooms family retired onto real ingestion; session 354: mumble/IRC/DeltaChat/XMPP state-mirror slices — 15 defs; session 353: injection, mumble-wire-codec, mumble-crypt families + 24-def orphan sweep); TelegramCore SetAuthed/SetCtx + TeamSpeakCore SetAuthed (6 sites) + GitHub SetUsername/NewGitHubCore await a scripted-server front | session 356 entry | Matrix state cluster in progress, then TS cluster, then construction family; the scripted front via ts3j-style TS server / gotd tgtest / GUI --script seam |
| H-2 | verify/release yml | android APK + web (gh-pages) + Xvfb GUI legs parked until the new GUI | AGENTS.md §6/§8 | re-add with the GUI build (owner order pending) |
| H-3 | engine/cores API | 302 identifiers exported purely for the tests move (API noise: TsParseInit1, ForTest-adjacent) | commit 27faa5a4 | fold into real APIs or de-export when tests are reworked during the GUI rebuild |

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

## Session 353 — H-1 cores front, family 1: the cross-core injection hooks (SetAuthed/SetCtx/Cancel/SaveSession) (2026-11-03)

- Boot: fresh sandbox — toolchain + caches wiped again; env.sh recovery
  recipe followed verbatim (go1.27.1, checksum-verified, TOOLCHAIN=
  ../toolchain per the file; core.fileMode false re-set; /tmp tarballs
  removed when the box filled). Baseline gate green before touching
  anything (tests/engine 6.5s, bootstrap 1.0s on the unmodified head).
- Family census corrected by def-count (rg 'func.*ForTest' testhooks*.go):
  37 defs in the family, NOT 39; 12 used sites in 7 files, 25 orphan defs.
  Design rating: mumble Close() retirement 9/10 (Close IS the persist+
  cancel+drain lifecycle — the test now proves the real teardown);
  matrix real-Authenticate journey 8/10 (whoami+keys+sync all real HTTP
  through mautrix; crypto init genuinely succeeds — 51 OTKs uploaded);
  telegram/TS trio DEFERRED 5/10 (no unit-level real path — needs scripted
  servers, a separate front; hooks kept, path named in H-1).
- RED first: all 34 doomed defs deleted → tool-proven compile failure ×6
  (matrix_test.go:429 ForTestSetAuthed; mumble_tofu_connect 132/133/159/160
  ForTestCancel; mumble_tofu_test 99 ForTestSaveSession).
- GREEN: mumble tofu tests Close() mid-connect (cancel→ctx.Done unblocks
  the ServerSync wait; probe conn closed; pins preserved — ResetEnv still
  re-pins); TestServerPinSurvivesCertSave now persists via Close()
  (saveSession under Session!=nil, assert through store.Load);
  mxAuthedCore: httptest homeserver — whoami (401 unless Bearer
  test-token), keys/query {"device_keys":{}}, keys/upload counts, sync
  held open on r.Context().Done; Authenticate(AuthModeBot) drives the
  real bot path; t.Cleanup LIFO closes core before server.
- Evidence: quick gate GREEN (tests/cores 15.5s, tests/engine 6.5s,
  tests/bootstrap 1.0s, utils/aacaud/voice ok, js/wasm audio leg green,
  wasm-runner contracts green); gofmt clean; strip_comments --check clean
  (271 files, 0 dropped); -race rung-7 (disk/RAM too small — CI gates).
  Cores def-count 196→162. Matrix DBG stderr logging noted as Q-1.
- verify.yml dispatched post-push (run id recorded at next boot).
- Iteration 2 (same session) — mumble wire codec family, 35 defs → 0:
  ForTestMarshal ×15 + ForTestUnmarshal ×18 (all thin delegates to
  unexported marshal/unmarshal on the message structs) + PbEncoder
  ForTestBytes/ForTestWriteBytes. Only 8 sites in mumble_proto_test.go
  actually used them (6 exported types); 27 wrappers were orphans. Real API
  added instead of per-type method exports (H-3 discipline): package-level
  `MumbleMarshal(msg interface{ marshal() []byte })` + `MumbleUnmarshal(data,
  msg interface{ unmarshal([]byte) error })` beside MumbleVarintEncode —
  one consistent codec seam for every message type. TestMumbleCryptSetup-
  RoundTrip was HALF-WRITTEN (dead `_ =` locals, hand-built PbEncoder wire,
  zero content assertions) — rewritten onto the real roundtrip with
  populated fields + bytes.Equal on Key/ClientNonce/ServerNonce + field-tag
  pin. Design rating 9/10.
- Iteration 2 evidence: RED = 10+ undefined ForTestMarshal/Unmarshal/
  WriteBytes compile failures pre-rewrite; GREEN = the 6 codec tests PASS,
  full tests/cores 15.9s, tests/engine 6.6s, tests/bootstrap 1.2s; gofmt +
  comment-ban clean (271 files, 0 dropped); quick gate GREEN. Cores
  def-count 162→127. NOTE: the edit tool writes space-indent — gofmt -w
  after EVERY edit, then re-diff to confirm only intended lines changed
  (bit me twice this session; gate self-heals but verify the diff).
- Iteration 3 (same session) — mumble crypt family, 6 defs → 0: the
  `type ForTestMumbleCryptState = mumbleCryptState` alias + ForTestInit/
  ForTestEncrypt/ForTestDecrypt + 2 orphans (mumbleCryptState ForTestKey/
  ForTestMu — zero users; ForTestMu/Key users are TelegramCore/groupPeer).
  All 25 test sites folded onto the ALREADY-EXPORTED MumbleCryptState
  wrapper (struct-embed + Init/Encrypt/Decrypt — the §5.2 real-API shape
  that a prior session built but never migrated onto). Mechanical sed
  migration; the 7 crypt tests (OCB2 roundtrip, OOO window, replay-512,
  tamper, official vectors, client/server directions, exported wrappers)
  all PASS unchanged in behavior.
- Iteration 3 evidence: RED = undefined ForTestMumbleCryptState ×5 (then
  the method sites); GREEN = crypt suite 7/7 PASS, tests/cores 15.5s,
  tests/engine 6.7s, tests/bootstrap 1.1s, quick gate GREEN, comment-ban
  clean. Cores def-count 162→121 cumulative this session.
- Gates of record: iteration 1 verify.yml 41518425922 = SUCCESS on 9ad04fd8
  (all jobs, step level). Iteration 2 dispatched (in flight at this edit);
  iteration 3 dispatches post-push.
- Iteration 4 (same session) — orphan sweep, 24 defs → 0 users lost:
  ForTestMu on 14 non-Telegram receivers (only TelegramCore's is used —
  freeze test; the audio package's is a different file, untouched),
  DeltaChat/Telegram ForTestActiveCalls (Matrix's is the used one), Mumble+IRC
  ForTestSetChannels (TeamSpeak's used), Bale+GitHub ForTestSetUserID
  (Matrix's used), XMPP ForTestSetRooms, IRC ForTestSetUsername, Mumble
  ForTestMyChannelID — every cut verified by locating the name's actual use
  sites and their receivers. Method per session 351; evidence = the census
  greps in-session. Zero test edits; compile-green by construction.
- Iteration 4 evidence: quick gate GREEN (tests/cores 17.2s after a full
  cache-cold recompile, tests/engine 6.7s, tests/bootstrap 1.1s);
  comment-ban clean; def-count 122→98 (the earlier "121" had counted the
  now-dead type alias as a def — corrected).
- Machine incident mid-iteration: rootfs hit 100% (build temp); the
  transient PolarFS /tmp/my-project mount (which had held a previous
  session's toolchain) vanished mid-move — symlinks also policy-blocked;
  resolved via go clean -cache (4G) + one full recompile (~15 min, gotd
  compiled clean with -gcflags=all=-c=1). If the box fills again: clean
  the gocache, not the modcache.
- BUG FIX (red→green, the front working as intended): CI race legs on
  iterations 2+3 (41520169823 on f1fca6c9, 41520879579 on 3b99c679) FAILED
  with DATA RACE in TestMatrixGetDialogsSortsAndPaginates — the real-auth
  journey from iteration 1 exposed a PRE-EXISTING MatrixCore bug:
  startSync() wrote m.syncCtx/m.syncStop WITHOUT m.mu (matrix.go:3139)
  while Close() reads m.syncStop under the lock (1848) — a close-races-
  auth-start crash vector in production. Fix: m.mu around the assignment
  (+2 lines; all orderings then safe — Close-before-start yields a
  WithCancel on the cancelled parent → instant clean loop exit). Local
  scoped -race insensitive (scheduling window; CI is the reproducer);
  quick gate GREEN; CI re-dispatched = the verdict.
- Race-fix dispatches: verify.yml on 329cdb58 (iteration 4) = failure (the
  same pre-fix race, superseded); **the fix run 41526012096 on 5131fc1e =
  SUCCESS — all 3 jobs, every step green at step level, race leg included**.
  This is the gate of record for the whole session stack.

## Session 352 — boot reconciliation + H-1 iterations 16–17: media lifecycle self-contained; engine hook quarantine deleted (2026-11-02)

- Boot found head 4 commits past STATE (prior session died after push, before
  the WORKLOG rewrite): iter 12 (8a10ad24 — ForTestConfig retired, real
  MediaVolume getter), 13 (25b84cc1 — UseMediaDir construction option retired
  ForTestSetMedia/-SetMediaDir), 14 (7feea8c5 — ForTestOpenMediaStream onto the
  real OpenMediaStream), 15 (a5f6566a — seven orphan ForTestMu hooks deleted).
  Local gate re-run green on that head (tests/engine 5.59s, bootstrap 0.87s,
  vet/gofmt/comments clean); the missing gate-of-record dispatched: verify.yml
  41482286310 on a5f6566a.
- Iteration 16 — design flaw exposed while retiring ForTestMedia/
  ForTestQueue/ForTestExecuteDownload: UseMediaDir installed a manager WITHOUT
  starting it (Init had to remember Start(context.Background())), Stop() was
  dead code, the worker LEAKED past Shutdown into a closed db, and
  executeDownload raced e.mediaDir against a dir swap. Fix: Engine owns a
  lifecycle ctx (New creates it; Shutdown cancels + drains media with a 5s cap
  before db close); Start derives a child cancel (double-start guarded),
  Stop() = cancel + wg.Wait; UseMediaDir self-contained (stops the old manager
  outside e.mu, installs + starts the new one); executeDownload reads mediaDir
  under e.mu.RLock; e.media readers go through a locked mediaManager()
  (RequestDownload, CancelDownload, OpenMediaStream, MaybeAutoDownload).
- Tests rewritten black-box onto the real flow (event-driven waitUntil +
  evRecorder). The enqueue→stream→execute skip-race pinned deterministically
  by maxConc saturation: 10 gate-blocked fillers hold every slot, m1 queued
  11th, stream opens, gate releases → m1 must skip (started==10, state
  DownloadNone), then after Close + re-request started==11 exactly — a broken
  guard runs m1 during the stream and lands on 12. Harness fix riding along:
  newTestEngineWith pins db.SetMaxOpenConns(1) — the :memory: pool opened
  FRESH EMPTY dbs on the worker goroutines' first concurrent use ("no such
  table: media"), masked until now by the sync hooks.
- TRUE tool-proven RED pre-change (unmodified tree): 3 timeouts (download_failed
  event; download_complete after Close; 10 filler downloads started). GREEN
  post-change: tests/engine 6.3s + tests/bootstrap 0.9s (-count=1); vet/gofmt/
  comment-check clean; js/wasm + cmd builds ok; headless smoke engine-ready,
  vault+cache+downloads, SIGTERM rc=0 (drives the new Shutdown drain); -race =
  rung-7 gotd OOM skip (even -gcflags=all=-c=1) — the CI race leg gates it.
- Engine hooks 8→5, zero refs repo-wide. Remaining: VoiceVAD ×2 (voice front),
  httpImageCache ×3 (img front).
- Iteration 17 (engine slice complete): ForTestGate/ForTestNeedTerminator/
  ForTestStore/ForTestGet/ForTestLen deleted and engine/testhooks.go removed
  outright. Compile-seam RED first (undefined NewHTTPImageCache + ForTest*),
  then the rewrites: voice_test drives the REAL pipeline — fake mic device
  through the exported audio.SetDeviceFactory seam + journeyVoiceCore (full
  cores.VoiceCore; StubCore does not implement it — SetVoiceMuted was the
  missing method that silently skipped the runner); JoinGroupCall starts the
  runner; per-frame feed→count waits pin speech/hangover-exact/
  terminator-once/prolonged-silence-inert/cold-start, final exact counts are
  the deterministic catchers and the loud-frame catcher proves pipeline
  liveness (a dead pipeline cannot false-pass).
  TestHTTPImageCacheEvictionThroughFetch pins cap-256 eviction + LRU touch
  through real FetchHTTPImage roundtrips against a hit-counting server
  (unique server per test isolates the package-global cache). The
  store-on-existing-key branch keeps its defensive shape — reachable only
  through the inflight-delete→store race window, not deterministically
  testable via the real API; that coverage is consciously dropped with the
  hooks. NewHTTPImageCache de-exported (H-3 −1, internal-only caller).
- Iteration 17 evidence: scoped TestVoiceVAD*/TestHTTPImage*/TestFetchHTTPImage
  ok 0.60s; full tests/engine 6.4s + tests/bootstrap 0.9s; vet/gofmt/comment
  clean; js/wasm + cmd builds ok; -race = rung-7 gotd OOM skip (CI leg).
  Iteration 16 gate of record: verify.yml 41489996615 = SUCCESS on b8cfe27d.
- Cores hook census for the next front (180 total, testhooks.go +
  testhooks_manual.go): MatrixCore 25, TsConnection 18, TeamSpeakCore 14,
  MumbleCore 11 + ~35 mumble wire-message Marshal/Unmarshal pairs, IRCCore
  10, DeltaChat 9, XMPP 9, GitHub 7, Telegram 6, Bale 6, rest singles.
  Cross-cutting construction/auth family first candidate: ForTestSetAuthed
  ×10 + ForTestSetCtx ×10 + ForTestCancel ×11 + ForTestSaveSession ×8 across
  every core — same shape as the engine's retired injection hooks (systemic
  retirement via a real construction/dial-state path, not per-hook patches).
  verify.yml 41491975538 dispatched on 8911e54b (in flight at yield; next
  session's boot records the result).

## Session 351 — H-1 iterations 7–11: five engine hook retirements + a download-dir bug fixed red→green (2026-11-02)

- 7a/7b (22434bc, 8e9b289): ForTestSetAntiRecall retired onto real New+
  DefaultConfig defaults; dead SetAntiRecallSettings deleted (zero callers).
  8 (48280e2): ForTestGranule retired — zero production consumers, fuzz
  assertion contradicted the Ogg spec; ReadOggPage de-exported; fuzz reworked
  onto the real read flow. 9 (35fcbb1): MediaStream completion hooks retired
  (complete() had zero production callers). 10 (c930373): BUG red→green —
  UpdateConfigFromBridge{DownloadDir} never moved runtime e.downloadDir
  (saves landed in the old dir); fixed under e.mu + ensureDir; dead
  SetDownloadDir deleted; 5 savetodl sites onto real paths. 11 (1255350):
  three orphan hooks deleted.
- Evidence: quick gate GREEN per iteration; verify.yml 41454716589 on
  1255350. Engine hooks 27→19. Orphan-cut method: per-name user counts
  over go/tests/.
