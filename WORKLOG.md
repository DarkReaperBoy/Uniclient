# WORKLOG.md — the state file

Top: the **STATE block** — rewritten every session, the resume pointer for the next
agent. Then open items (severity order), then entries newest-first, terse (did /
evidence / next). The pre-2026-11-01 progress docs (BUGS.md, research/) were purged by
owner order — that history lives in git if ever needed.

## STATE

- front: session 352 — H-1 ENGINE SLICE COMPLETE: iteration 16 (media
  lifecycle self-contained; ForTestMedia/-Queue/-ExecuteDownload dead) +
  iteration 17 (VoiceVAD + httpImageCache hooks dead — voice journeys drive
  the real mic pipeline via audio.SetDeviceFactory + JoinGroupCall, LRU pinned
  through FetchHTTPImage hit-counting; NewHTTPImageCache de-exported) —
  engine/testhooks.go DELETED, engine hooks 0
- next: cores hooks (180 — census in the session 352 entry: MatrixCore 25,
  TsConnection 18, TeamSpeakCore 14, mumble wire msgs ~35, …; first candidate
  = the cross-core SetAuthed/SetCtx/Cancel/SaveSession injection family) —
  retire by family; H-3 export noise folds into those reworks
- owner-waiting: the next direction; the GUI build order (design is law in AGENTS.md §6 — Elm loop,
  Telegram Desktop/Web/Android references, capability-projected, Gio)
- last-gate: verify.yml **41491975538 = SUCCESS on 8911e54b** (iteration 17;
  all 3 jobs, every step incl. the CI race leg) AND **41489996615 = SUCCESS
  on b8cfe27d** (iteration 16) AND **41482286310 = SUCCESS on a5f6566a**
  (reconciled dead-session iters 13–15); local quick gate GREEN on every
  iteration this session (tests/engine 5.6–6.4s, bootstrap ~0.9s,
  vet/gofmt/comments clean, js/wasm + cmd ok, headless smoke rc=0)

## Open items

| ID | where | what | evidence | next step |
|---|---|---|---|---|
| H-1 | cores testhooks*.go | ForTest* hooks are debt (§5.3): 181 left (all cores — engine slice COMPLETE, 41→0 across sessions 346–352; engine/testhooks.go deleted in 352) | session 352 entry | receiver-qualified recon per core, then retire by family |
| H-2 | verify/release yml | android APK + web (gh-pages) + Xvfb GUI legs parked until the new GUI | AGENTS.md §6/§8 | re-add with the GUI build (owner order pending) |
| H-3 | engine/cores API | 302 identifiers exported purely for the tests move (API noise: TsParseInit1, ForTest-adjacent) | commit 27faa5a4 | fold into real APIs or de-export when tests are reworked during the GUI rebuild |

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

- 7a (22434bc): ForTestSetAntiRecall retired — the hook forced true/true/false
  onto the fields without the lock, but New+DefaultConfig already yields exactly
  that (constructor defaults, Ayu* nil); the test now pins real constructor
  defaults. 7b (8e9b289): SetAntiRecallSettings deleted — zero callers repo-wide,
  the persisted mutation path is UpdateConfigFromBridge (Ayu* flags).
- 8 (48280e2): ForTestGranule retired — oggPage granule/headerType/serial/seq had
  zero production consumers (packet reader uses payload+lacing only); the fuzz
  assertion contradicted the Ogg spec (high-bit granule positions are legal wire
  data, e.g. -1 = no-position). ReadOggPage de-exported to readOggPage (last
  external caller was the fuzz target); fuzz reworked onto the real read flow:
  FuzzOggPacketReader over NewOggPacketReader with a sticky-error pin and valid
  BuildOggPage seeds.
- 9 (35fcbb1): MediaStream completion hooks retired — complete() had zero
  production callers; ForTestComplete's assertion was redundant (onDone fires iff
  done flips, exactly once, TestMediaStreamDoneOnlyAfterLastChunk pins timing);
  ForTestDone was an orphan.
- 10 (c930373): BUG, red→green — UpdateConfigFromBridge{DownloadDir} updated only
  e.config.DownloadDir; the runtime e.downloadDir that savetodl.go reads never
  moved, so saves kept landing in the old directory. Red:
  TestBridgeDownloadDirChangeSteersSavePath failed "…/002, want
  …/004/nested/downloads"; fix sets e.downloadDir under the held e.mu and
  ensureDir's the new dir before locking. Dead SetDownloadDir (zero callers,
  bridge-era orphan) deleted; the 5 savetodl hook sites moved onto real paths
  (config construction via newSaveToDownloadsEngine + bridge changes).
- 11 (1255350): three orphan hooks deleted — httpImgFlight.ForTestDone,
  httpImgFlight.ForTestSetDone, MediaStream.ForTestSetDone (zero test users).
- Evidence: quick gate GREEN after every iteration (latest: tests/bootstrap
  0.869s, tests/engine 5.574s, vet/gofmt/comment checks clean); targeted runs
  red→green for iteration 10; Ogg suite incl. TestOggRealOpusFile (ffmpeg
  differential) green after iteration 8. verify.yml 41454716589 dispatched on
  1255350 (204 accepted).
- Engine hooks 27→19. Orphan-hook scan method: per-name user counts over
  go/tests/ (rg -c), zero-count = cut.

## Session 350 — M-1 executed: monetary feature surfaces pruned engine-wide and core-wide (2026-11-02)

- Three slices (5e64e5e engine, 1,680 lines; d1d02e2 cores files; 5db0adc
  telegram.go cascade, ~2,088 lines): earn/gifts/giveaways/premium_business/
  sponsored deleted at both layers + ~50 zero-user monetary methods, 15
  orphan base.go types, 13 test files; utils/config.go LocalPremium dropped;
  SetChatReactionsMode paidEnabled branch removed at both layers; engine
  hooks 34→29. KEPT as data mirroring per rule 19: is_premium/stars columns
  + Extra keys, gift/paid-media message conversion, ServiceActionText gift
  branches, timezoneOffsetNoLock, folder/link limits, Get/SetMessagesPrivacy.
- Evidence: quick gate GREEN per slice (tests/cores 14.7s, tests/engine 5.3s,
  tests/bootstrap 1.0s, vet/gofmt/comments clean); gate of record verify.yml
  **41434129182 = SUCCESS on ffd31b2**.

### H-1 iteration 6: ForTestSetConfig + ForTestSetVault retired (same session)

- Atomic change (93b0aa4): the config/vault injection hooks (2 users each —
  antirecall_test.go, avatarcorners_test.go) replaced by the REAL constructor
  path: newTestEngineWith(t, vault, config) → New(db, vault, config);
  newTestEngine delegates with nil/nil so 20+ existing call sites unchanged.
  engine/testhooks.go: both setters deleted (engine hooks 29→27).
- Evidence: scoped quick gate vet clean; go test -tags goolm -count=1
  ./tests/engine/ ok 5.671s, ./tests/bootstrap/ ok 6.331s; gofmt clean;
  comment check clean. Sandbox recycled mid-iteration (Go SDK + caches wiped,
  file modes 100644→100755 — core.fileMode false set locally; content
  untouched); reinstalled Go 1.27.0, re-ran gate green. verify.yml dispatched
  post-push.
- Next: singles (ForTestSetAntiRecall 1, ForTestGranule 1, ForTestComplete 1),
  then the SetMedia/SetDownloadDir/SetMediaDir trio (needs downloadDir/
  mediaDir on the real path), then ForTestMu cluster.

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

## Session 346 — H-1 iter 3: New + AttachAccount + ReplaceAccountCore retire the account-injection hook cluster (2026-11-02)

- Atomic change (3 exported APIs, all production-shaped):
  - `New(db, vault, config) *Engine` — the engine's real assembly point: accounts map,
    avatar state, production defaults (saveDeleted/saveHistory true, maxCache 1<<30) + the
    whole config application (Ayu flags, maxCache, proxy, downloadDir override) moved in
    verbatim from Init's inline block; `Init` now acquires dirs/lock/vault/db and calls New
    (downloadDir precedence preserved: cfg wins, param fills). New-init accounts map makes
    `&Engine{}`-style nil maps impossible through the constructor.
  - `AttachAccount(id, platform, core) error` — the caller-owned account install: empty-id
    and duplicate-id errors, SortOrder = AddAccount's maxOrder+1 discipline, ConnConnected
    (the core is live), nil-map guarded. The runtime-cache install ConnectAccount performs
    at health.go:72-76, now an explicit embedding seam (bot-supervisor/future --script shape).
  - `ReplaceAccountCore(accountID, core) error` — the core hot-swap ConnectAccount
    (health.go:73) and DisconnectAccount (health.go:306) perform internally, exported: missing
    account errors; account stays registered. Serves the mid-test core-swap journeys
    (comments/restrict "unsupported core must error") that map-replacement used to provide.
- Retired hooks (engine 41→37): ForTestNewEngine (constructor sites: hide/recentsearch/lread/
  mediaplayer_aac → New), ForTestSetAccounts (54 sites across 19 files → AttachAccount, error
  checked per call), ForTestAccounts (3 map-mutation sites → AttachAccount / the savedsublists
  attach-then-swap restructured to one honest attach), ForTestGetAccount (media_guard helper →
  GetAccountCore, the exported accessor that already existed). 4 test files dropped their now-
  unused engine dot-import (favreact/savedmessages/sponsored/stickermgr/stories).
- Platform labels made honest in the sweep: tg→telegram, irc→irc, a1→telegram (TG-flavored
  features), groupcall a1→teamspeak (talk power).
- TRUE tool-proven RED: tests/engine/attachaccount_test.go — `undefined: New` ×5 build failure
  (compile seam, the R47/R51 class) against the pre-change tree. GREEN post-change: 5 tests
  (New config+defaults contract; AttachAccount contract incl. dup/empty/coreless/caps;
  ListAccounts shape incl. ConnState; ReplaceAccountCore contract incl. nil replace;
  concurrent hammer — 8 writers + 4 readers + 16 same-id racers, exactly-one-wins) clean under
  LOCAL -race.
- Evidence: quick gate GREEN (scoped: bootstrap/cmd/engine/tests-bootstrap/tests-engine;
  native vet leg = rung-7 gotd OOM skip per gate.sh, native test both ok); FULL native suite
  7/7 ok (aacaud/audio/bootstrap/cores/engine/utils/voice, 16.2s cores); -race
  tests/engine 89.5s + tests/bootstrap 6.2s ok (-gcflags=all=-c=1); gofmt clean;
  strip_comments --check clean (293 files); js/wasm build ok; windows cross-build = rung-7
  gotd OOM skip (CI gates it); headless smoke: `uniclient -dir X -password p -events` →
  "engine ready", vault+cache+downloads created, timeout TERM → exit 0.
- CI dispatched: verify.yml **41394693974** on 5997a16b — CLOSED: SUCCESS, all 3 jobs (test&vet&
  gofmt&smoke / nix / windows+js-wasm), every step green at step level; the windows leg this box
  could not compile (rung-7 gotd OOM) proved green there. No behavior change to production paths
  (Init refactor is side-effect-order-preserving; only the New-defaults flip
  saveDeleted/saveHistory false→true on test-constructed engines — audited: no test exercises
  message_deleted/message_edited update handlers without setting flags explicitly; suite proves
  it).

### Iteration 4 — dbEngine harness retires ForTestDb (same session)

- Atomic change (test-side only, zero new engine API): `dbEngine{*Engine; db *sql.DB}` in
  hide_test.go — newTestEngine KEEPS the sql.DB it opens (the test owns the handle it already
  creates, migrates, and hands to New; taking it back through a hook was backwards). 46 sites
  (32 Exec seeds + 14 QueryRow assertions) → e.db.Exec/e.db.QueryRow; 6 local constructors and
  17 db-touching helpers retyped to *dbEngine; newGuardEngine's NewMediaManager arg →
  e.Engine; 4 files dropped now-unused engine dot-imports (earn/giveaways/pollresults/
  savedsublists).
- TRUE tool-proven RED: ForTestDb deleted FIRST — "e.ForTestDb undefined (type *engine.Engine
  has no field or method ForTestDb)" compile seam across the 46 sites; then the harness landed
  and the full suite went GREEN (5.8s).
- Evidence: quick gate GREEN (scoped engine+importers, native test ok; vet leg = rung-7 gotd
  OOM skip per gate.sh); FULL native suite 7/7 ok; -race tests/engine 89.9s + tests/bootstrap
  6.2s ok; gofmt + strip_comments --check clean; js/wasm build ok; headless smoke exit 0
  (engine ready, vault+cache+downloads, SIGTERM). CI gate of record: verify.yml
  **41396012222 = SUCCESS on d9e472df** — all 3 jobs, every step green at step level.
