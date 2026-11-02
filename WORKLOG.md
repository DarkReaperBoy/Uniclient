# WORKLOG.md — the state file

Top: the **STATE block** — rewritten every session, the resume pointer for the next
agent. Then open items (severity order), then entries newest-first, terse (did /
evidence / next). The pre-2026-11-01 progress docs (BUGS.md, research/) were purged by
owner order — that history lives in git if ever needed.

## STATE

- front: session 353 — H-1 CORES FRONT: family 1 (injection hooks 37 defs
  → 3: mumble onto real Close(), matrix onto real Authenticate, 29 orphans
  cut) + family 2 (mumble wire codec: 35 Marshal/Unmarshal + PbEncoder
  wrappers → 0 via exported MumbleMarshal/MumbleUnmarshal pair — the
  MumbleVarintDecode pattern; CryptSetup test completed with real content
  assertions). Cores def-count 196→127.
- next: next cores hook families by census — mumble crypt hooks (obvious:
  exported MumbleCryptState.Init/Encrypt/Decrypt already exist — the
  ForTestMumbleCryptState family folds onto them), then the state-mirror
  family (ForTestRooms/Channels/Users/…), then construction family
  (ForTestNewTsConnection/ForTestNewTeamSpeakCore/…)
- owner-waiting: the next direction; the GUI build order (design is law in AGENTS.md §6 — Elm loop,
  Telegram Desktop/Web/Android references, capability-projected, Gio)
- last-gate: local quick gate GREEN on the working tree (tests/cores 15.5s
  7/7 ok, tests/engine 6.5s, tests/bootstrap 1.0s, js/wasm + runner green,
  gofmt + comment-ban clean, 271 files 0 dropped); -race = rung-7 (box too
  small — CI leg gates); verify.yml dispatched on this iteration's push
  (id in the session 353 entry once closed)

## Open items

| ID | where | what | evidence | next step |
|---|---|---|---|---|
| H-1 | cores testhooks*.go | ForTest* hooks are debt (§5.3): 127 left by def-count (session 353) — injection + mumble-wire-codec families done; TelegramCore SetAuthed/SetCtx + TeamSpeakCore SetAuthed (6 sites) still await a scripted-server front | session 353 entry | mumble crypt hooks next (fold onto the existing exported MumbleCryptState API); then state-mirror + construction families; the trio via ts3j-style TS server / gotd tgtest / GUI --script seam |
| H-2 | verify/release yml | android APK + web (gh-pages) + Xvfb GUI legs parked until the new GUI | AGENTS.md §6/§8 | re-add with the GUI build (owner order pending) |
| H-3 | engine/cores API | 302 identifiers exported purely for the tests move (API noise: TsParseInit1, ForTest-adjacent) | commit 27faa5a4 | fold into real APIs or de-export when tests are reworked during the GUI rebuild |
| Q-1 | cores/matrix.go initCrypto | mautrix client logger set at DBG with a console writer — every request logs to stderr in production (now visible: mxAuthedCore drives Authenticate) | session 353 run log | gate to WRN or env (UNICLIENT_MATRIX_DEBUG, mirroring mumble) — tiny, needs its own commit |

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

## Session 350 — M-1 executed: monetary feature surfaces pruned engine-wide and core-wide (2026-11-02)

- Three slices (5e64e5e engine 1,680 lines; d1d02e2 cores files; 5db0adc
  telegram.go cascade ~2,088 lines): earn/gifts/giveaways/premium_business/
  sponsored deleted at both layers + ~50 zero-user monetary methods, 15
  orphan base.go types, 13 test files; engine hooks 34→29. KEPT as data
  mirroring per rule 19 (is_premium/stars columns + Extra keys, gift
  conversion, timezoneOffsetNoLock, folder/link limits, Get/SetMessagesPrivacy).
- Same session, H-1 iteration 6 (93b0aa4): ForTestSetConfig + ForTestSetVault
  retired via the REAL constructor — newTestEngineWith(t, vault, config) →
  New(db, vault, config); engine hooks 29→27. Sandbox recycled mid-session
  (SDK + caches wiped) — env.sh recovery proven.
- Evidence: quick gate GREEN per slice (tests/cores 14.7s, tests/engine 5.3s,
  tests/bootstrap 1.0s); gate of record verify.yml 41434129182 = SUCCESS
  on ffd31b2.

## Session 349 — owner directive: rule 19 extended — no gifts, nothing monetary (2026-11-02)

- Owner order (intent, verbatim): "also ban premium, gift, and anything monetary."
- Atomic change: AGENTS.md §1 rule 19 retitled **"No premium, no gifts, nothing
  monetary, no bloat"** — explicit bans added: gifting, stars/credits/balance,
  payments, transfers, boosts, sponsored/monetized surfaces; remote flags
  (e.g. is_premium) may be mirrored as data for correctness, never built on or
  gated by as features.
- Evidence: rule 19 (lines 87–92 post-edit); repo grep for monetary surfaces →
  M-1 opened at top of open items (§0.4 owner-reported): engine earn/gifts/
  giveaways/premium_business/sponsored + cores telegram_business/earn/gifts/
  giveaways/sponsored (+ paidmedia, stars) + 13 test files.

## Session 348 — H-1 iteration 5: ForTestNewAuthFlow + ForTestCollected retired (2026-11-02)

- Atomic change: tests/engine/auth_xmpp_test.go rewritten onto the REAL auth path — a test
  core factory (SetCoreFactory, exported registration seam bootstrap uses in production)
  feeds a real XMPPCore + real SessionStore from a test vault; the engine comes from
  New(nil,nil,nil) + AttachAccount("xmpp-…", "xmpp", nil); the journeys drive StartAuth →
  SubmitAuthInput and assert the same transitions black-box via returned AuthStates:
  initial JID input → password → register offer (label pinned) → dial failure surfaces
  as a RECOVERABLE ERROR STATE (the engine contract — SubmitAuthInput never returns the
  dial error), both for "y" (register) and "" (straight-login retry). AdvanceXMPP white-box
  tests and the ForTestCollected map assertions died with the hooks. engine/testhooks.go:
  both hooks deleted (engine 36→34), orphaned cores import dropped. TestParseYesNo +
  TestBuildAuthConfigXMPPRegister kept (exported pure functions, no hooks).
- Evidence: gofmt clean; go vet -tags goolm EXIT 0 (engine, tests/engine, bootstrap,
  cmd/uniclient, tests/bootstrap); go test -p 1 -tags goolm -count=1 ./tests/engine/ ok
  5.144s (4/4 auth tests PASS), ./tests/bootstrap/ ok 0.863s; strip_comments.py --check
  clean (go files=293, dropped=0). Gate of record: verify.yml dispatched post-push (id
  below when closed).
- Next: authFlows package-global → per-Engine (isolation test red→green, touches
  engine/auth.go + engine/cache_users.go); then remaining hook families by use-count.

### authFlows scoped per-Engine (same session, second atomic change)

- Failing test first: TestAuthFlowsArePerEngine (tests/engine/authflows_test.go) — two
  Engines via newAuthEngine, same accountID "acct", e2.CancelAuth kills e1's flow →
  SEEN RED: `e1 lost its auth flow after e2 cancelled its own: no auth flow for "acct"`.
- Fix: authFlows + authFlowsMu moved into Engine (engine.go struct + New literal); all
  readers rewritten to e.authFlows/e.authFlowsMu (auth.go: StartAuth, SubmitAuthInput,
  onQRTokenUpdate, CancelAuth, GoBackAuth, SwitchAuthMethod, finalizeAuth; cache_users.go:
  GetLanguages, GetLangStrings auth-flow core fallback); dead package-level CurrentAuthState
  deleted (zero users repo-wide — grep evidence in-session).
- Evidence: TestAuthFlowsArePerEngine PASS + both XMPP journeys PASS; full
  ./tests/engine/ ok 5.350s; ./tests/bootstrap/ ok 0.842s; vet EXIT 0; gofmt clean;
  -race clean on the auth tests; strip_comments.py --check clean (294 files, 0 dropped).
- Next: remaining engine hook families by use-count (ForTestMu / ForTestSet*).

## Session 347 — owner redirect: AGENTS.md §3 push law hardened — git is the checkpoint (2026-11-02)

- Owner order (out-of-band, this session): keep rapidly pushing git — the sandbox dies at
  any moment and every unpushed change is then redone from zero; git is the checkpoint.
- Atomic change (docs only): AGENTS.md §3 bullet replaced — "Push the moment it's green —
  every few turns at minimum" → "**Git is the checkpoint — push relentlessly**" (push each
  atomic change the moment its gate is green, never batched, never "later"; re-push after
  every WORKLOG/STATE rewrite). Law-only file preserved; 331→333 lines (owner-ordered
  addition, noted here per the ≤~330 ceiling).
- Evidence: this commit, pushed immediately per the new law itself.
- Next: H-1 iteration 5 — retire ForTestNewAuthFlow by rewriting auth_xmpp_test.go onto
  StartAuth/SubmitAuthInput; recon quotes in-session (auth.go: authFlows is a package-global
  map — cross-Engine flow leakage is the follow-up atomic fix).

## Session 346 — H-1 iters 3–4: account-injection cluster + ForTestDb retired (2026-11-02)

- Iter 3 (3 exported production-shaped APIs): `New(db, vault, config)` —
  the engine's real assembly point (Init refactored to call it,
  side-effect-order preserving; nil-map construction impossible now);
  `AttachAccount(id, platform, core)` — the caller-owned install
  (ConnectAccount's runtime-cache step, exported as the bot-supervisor/
  --script seam); `ReplaceAccountCore(accountID, core)` — the hot-swap
  ConnectAccount/DisconnectAccount perform internally. Retired (engine
  41→37): ForTestNewEngine, ForTestSetAccounts (54 sites → AttachAccount),
  ForTestAccounts, ForTestGetAccount (→ GetAccountCore). Platform labels
  made honest (tg→telegram, a1→telegram/teamspeak). TRUE RED: `undefined:
  New` ×5 pre-change; concurrent-hammer (8 writers + 16 same-id racers,
  exactly-one-wins) clean under LOCAL -race.
- Iter 4 (test-side only): `dbEngine{*Engine; db}` harness — newTestEngine
  KEEPS the sql.DB it itself creates; 46 ForTestDb sites → e.db.Exec/
  QueryRow; 6 constructors + 17 helpers retyped (engine →36).
- Evidence: full native suite 7/7 ok; -race tests/engine 89.5s ok; js/wasm
  + windows cross-build ok (windows = CI-gated OOM skip locally); headless
  smoke exit 0 (engine ready, SIGTERM). verify.yml 41394693974 = SUCCESS
  on 5997a16b, 41396012222 = SUCCESS on d9e472df (all 3 jobs, step-level).
