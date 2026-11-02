# WORKLOG.md — the state file

Top: the **STATE block** — rewritten every session, the resume pointer for the next
agent. Then open items (severity order), then entries newest-first, terse (did /
evidence / next). The pre-2026-11-01 progress docs (BUGS.md, research/) were purged by
owner order — that history lives in git if ever needed.

## STATE

- front: session 350 landed M-1 (owner ban, rule 19) in 3 code slices + 1 fix —
  (1) engine layer: earn/gifts/giveaways/premium_business/sponsored.go deleted,
  engine.go/cache_msgs.go/cache_users.go monetary methods + sponsoredCache/
  giftCache/LocalPremium fields pruned, utils/config.go LocalPremium dropped
  (1,680 lines, 5e64e5e); (2) cores files: telegram_business/earn/gifts/giveaways/
  sponsored.go + telegram_countries.go deleted, tests/business/earn/gifts/giveaways/
  sponsored/countries/stars/premium pruned, TestStoryReactionEmoticon rescued
  (d1d02e2); (3) telegram.go cascade-cut: ~50 zero-user monetary methods + types,
  base.go 15 orphan types, paidEnabled branch of SetChatReactionsMode removed at
  both layers (5db0adc); comment-law fix (ffd31b2). Engine hooks 34→29;
  then H-1 iteration 6 (93b0aa4): ForTestSetConfig + ForTestSetVault retired —
  antirecall/avatarcorners tests now build via New(db, vault, config) through
  newTestEngineWith (newTestEngine delegates nil/nil; 20+ call sites unchanged),
  zero semantic drift (DefaultConfig leaves Ayu*/MaxCacheSize
  constructor-neutral; proxy branch Mode=0 inert). Engine hooks 29→27
- next: remaining engine hook families by use-count — SetConfig/SetVault pair
  DONE (iter 6); next singles by user count: ForTestSetAntiRecall (1 user,
  antirecall_test.go — real path: UpdateConfigFromBridge with Ayu flags?),
  ForTestGranule (1 user, fuzz_ogg_test.go), ForTestComplete (1 user,
  mediastream_test.go); ForTestSetMedia ×3 / SetDownloadDir ×5 / SetMediaDir ×3
  need downloadDir/mediaDir on New or setters → real API decision; ForTestMu
  cluster after (receiver-qualified re-grep needed); then the next front
- owner-waiting: the next direction; the GUI build order (design is law in AGENTS.md §6 — Elm loop,
  Telegram Desktop/Web/Android references, capability-projected, Gio)
- last-gate: verify.yml **41447518193 = SUCCESS on 93b0aa4** (H-1 iteration 6) AND
  **41434129182 = SUCCESS on ffd31b2** (M-1 prune complete;
  dispatch 204 at ~11:05Z, completed success) AND **41424762770 = SUCCESS on
  8f595494** (session 348 authFlows fix); local quick gate GREEN after every slice
  (tests/cores ~14s, tests/engine ~5s, vet clean, gofmt clean, comment check clean)

## Open items

| ID | where | what | evidence | next step |
|---|---|---|---|---|
| H-1 | cores/engine testhooks*.go | ForTest* hooks are debt (§5.3): ~222 hooks left after session 346 (engine 41→36); session 348: engine 36→34; session 350 (M-1): engine 34→29 (gift/sponsored cache hooks died with their features) | session 350 entry | retire hooks as flows gain exported APIs; prune when a hook's last use dies |
| H-2 | verify/release yml | android APK + web (gh-pages) + Xvfb GUI legs parked until the new GUI | AGENTS.md §6/§8 | re-add with the GUI build (owner order pending) |
| H-3 | engine/cores API | 302 identifiers exported purely for the tests move (API noise: TsParseInit1, ForTest-adjacent) | commit 27faa5a4 | fold into real APIs or de-export when tests are reworked during the GUI rebuild |

## Session 350 — M-1 executed: monetary feature surfaces pruned engine-wide and core-wide (2026-11-02)

- Slice 1 (engine, 5e64e5e, 1,680 lines): engine/earn.go gifts.go giveaways.go
  premium_business.go sponsored.go deleted + tests/engine/{earn,gifts,giveaways,
  sponsored}_test.go; engine.go lost sponsoredMu/sponsoredCache fields,
  SetLocalPremium/localPremiumSnapshot/LocalPremiumFor, star-ref APIs,
  UpdateChannelEmojiStatus, UpdatePaidMessagesPrice, boosts APIs, gift-code
  options, GetGiveawayPeriodMax; cache_msgs.go lost star-gift fetch/pinned/send,
  UnlockPaidMedia, stars/broadcast revenue + withdrawal URLs; cache_users.go lost
  messages privacy/paid-messages config/stars-paid-post max/gift codes;
  utils/config.go LocalPremium dropped; testhooks.go gift/sponsored hooks deleted
  (engine 34→29). Zero non-test callers existed (grep evidence).
- Slice 2a (cores files, d1d02e2): telegram_business/earn/gifts/giveaways/
  sponsored.go deleted (Data*/Build* helpers were file-local); telegram_countries.go
  orphaned + deleted; 5 test files died, TestStoryReactionEmoticon rescued to
  telegram_story_test.go; freeze test table: 5 monetary entries excised.
- Slice 2b (telegram.go cascade, 5db0adc, ~2,088 lines): fixpoint scan cut every
  monetary decl with zero surviving users (~50 methods: stars balance/status/
  txns/revenue/withdrawals, broadcast revenue, premium status/promo/plans, gift
  settings/codes, boosts, sponsored wrappers, star-ref, paid messages/reactions/
  auth, UnlockPaidMedia, business/quick-reply/emoji-status raw wrappers) + 15
  orphan base.go types; SetChatReactionsMode paidEnabled branch removed at both
  layers; telegram_premium/stars/countries tests deleted.
- KEPT per rule wording (data mirroring, not features): is_premium/stars_to_send/
  stars_per_message columns + Extra keys, received gift/paid-media message
  conversion (telegram_gift_test.go, telegram_paidmedia_test.go),
  ServiceActionText gift branches, timezoneOffsetNoLock (business-hours
  rendering), folder/link limits, Get/SetMessagesPrivacy.
- Evidence: quick gate GREEN after every slice (latest: tests/bootstrap 1.049s,
  tests/cores 14.679s, tests/engine 5.312s, vet clean, gofmt clean); comment
  check clean (2 stray comments in the rescued test stripped, ffd31b2); gate of
  record verify.yml **41434129182 = SUCCESS on ffd31b2**.
- Next: re-grep hook users (M-1 invalidated recon) → ForTestMu family by
  use-count; ForTestSet* next.

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
- Next: M-1 pruning in atomic steps (feature files + their tests die together;
  ForTestMu cluster shrinks as sponsored ×2 / gifts ×2 users die with M-1).

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

## Session 345 — H-1: audio device factory retires the MediaPlayer + VoiceRecorder hook clusters (2026-11-02)

- Atomic change: `audio.SetDeviceFactory(func() (Device, error))` — the exact SetCoreFactory
  shape the codebase already blesses (mutex-guarded; nil restores platform truth;
  Available() true while installed; factory errors surface from Open() unchanged). The
  three engine call sites (mediaplayer/voicerec/voice) untouched — the seam sits at the
  package front door, so ALL three flows can now be driven with real devices.
- Retired: engine/testhooks.go loses MediaPlayer ForTestMu/Pcm/Gain/Sess/SetSess/SetPos/
  SetPlaying/SetPaused/Fill + AuthFlow.ForTestMu (zero uses anywhere — dead since the
  tests move; grep-verified before deletion). mediaplayer{,_mp3,_aac}_test.go now drive
  the REAL path: PlayMedia → audio.Open() → pullDevice (fake Device capturing the real
  fill callback) → manual pulls. detachDevice/rewindMediaForTest (state force-set
  through hooks) deleted.
- Pins strengthened while converting: seek-after-completion now pins BOTH real
  behaviors (device present → resumes at 0.3·dur; deterministic headless via error
  factory → stays !Playing — the §1.10 pin, previously machine-dependent on absent
  pulse); TestMediaPlayerNoDeviceIsHonest deterministic; stored-signal immutability
  pinned behaviorally (pull@1 == full after 0.5/0/0.1-gain pulls) instead of reading
  p.pcm through a hook.
- TRUE tool-proven RED: tests/audio/devicefactory_test.go — 6× "undefined:
  SetDeviceFactory" build failure (compile seam, the R47/R51 class); GREEN post-change:
  3/3 factory tests. Full evidence: quick gate GREEN (scoped audio/bootstrap/cmd/engine/
  tests/{audio,bootstrap,engine}; native vet+test + js/wasm legs); gofmt clean;
  strip_comments --check clean (292 files); windows + js/wasm builds ok; -race
  tests/audio 1.0s + FULL tests/engine 90.2s ok (-gcflags=all=-c=1 — gotd's tg
  race-compile OOM-kills on this 4GiB box without it; env.sh's documented rung-7
  degradation); headless smoke: engine ready, vault+dirs created, SIGTERM → exit 0.
- H-1 ledger: engine hooks 64 → 54 (~250 → ~240 across packages). Next: VoiceRecorder
  mic cluster through the same factory.

### Iteration 2 — VoiceRecorder mic cluster retired (same session)

- voicerec_test.go now drives the REAL mic journey: StartVoiceRecording → micDevice
  (fake Device whose StartMic hands the recorder a test-fed channel) → the real micLoop
  goroutine → StopVoiceRecording → the written OGG read back and decoded. The
  startRecorderNoDevice half-initialized-recorder helper (enc/started/done force-set
  through hooks) is gone.
- New/stronger pins: sub-minimum captures are DROPPED (Stop on a 0.6s capture → path "",
  seconds ~0.6, no error — never pinned before, the old test wrote the OGG directly
  instead); NoMicIsHonest deterministic (error factory — was a no-op on pulse machines);
  level meter pinned through VoiceRecording().Level with an EMA decay leg (tone → >0.1,
  then silence → ≤0.05, deadline-polled — monotone so deterministic both ways); cancel
  idles the recorder; round-trip decode + 440Hz magnitude kept, now from the real output
  file. Silence-keeps-level-0 leg is window-polled (heuristic; the decay leg covers the
  math deterministically) — stated honestly.
- Retired: VoiceRecorder ForTestMu/Granule/Done/Packets/Level/Sess/SetSess/SetEnc/
  SetStarted/SetDone/SetPackets/FeedFrame (12) + voiceRunner ForTestSetEnc (zero uses
  anywhere) — engine hooks 54 → 41. The dead write-only micCh field removed from
  voicerec.go (white-box-era leftover).
- Evidence: converted tests 5/5 green; -race full tests/engine 89.8s green (the new
  micLoop concurrency included); windows + js/wasm builds ok; smoke exit 0; gofmt +
  strip_comments --check clean (292 files). No behavior change to production code
  (only the dead field removal) — refactor iteration, RED n/a per the session-343
  migration precedent.
- Gate of record (both iterations): verify.yml **41336426885 = SUCCESS on 3aa4cdda**
  and **41337215090 = SUCCESS on 912e7c06** — 3/3 jobs each (test&vet&gofmt&smoke /
  nix flake gate / windows+js-wasm), every step inspected green at step level. Session
  345 closed.

## Session 344 — owner redirect #3: product-surface laws into AGENTS.md §1 (2026-11-01)

- Owner order (intent, kept short as asked): nothing from premium/paid or any useless
  feature/look ever; support all phone + desktop + web with least dependency/size/
  hardware resource/latency; refactor clunky code as you go; unit tests over every
  user scenario PLUS the agent itself using the app and navigating it with any tool it
  can; "clean code rules" (deliberately unspecified); senior-dev intuition + common
  sense; production code; nothing less than SOTA perfection.
- **Added §1.19-21 (this commit):** 19 no-premium/no-bloat product surface; 20 lean on
  every axis for phone/desktop/web (deps/size/resources/latency as hard budgets); 21
  production code + clean code rules + refactor-as-you-go + senior-dev intuition with
  the SOTA bar. Ceiling 320→330, updated in all 3 places it is stated (line 29, §10,
  §11).
- Deliberately NOT duplicated (already law, verified before writing): phone+desktop+
  web targets = §1.2-1.4; size-based responsive UI = §6.4 (3/2/1-pane dp breakpoints,
  answering the owner's "maybe size based?"); agent plays the app through its real
  interface with whatever tool fits (Xvfb+xdotool, Puppeteer, event stream) = §4.1-5;
  scenario-complete unit tests = §4.7; small release binaries = §1.6.
- Docs-only change — no ladder tier touched (§9/§11); pre-push invariants checked
  locally: no secrets/token anywhere in the tree, WORKLOG < 300 lines, AGENTS ≤ ~330.
- Gate of record: verify.yml dispatch **41323001269 = SUCCESS on d4b4476f** — 3/3 jobs
  (test&vet&gofmt&smoke / nix flake gate / windows+js-wasm cross-builds), every step
  inspected green at step level. Session 344 closed.

## Session 343 — owner redirect #2: GUI removal + tests to /tests + AGENTS.md v4.1 (2026-11-01)

- Owner order: "remove the whole gui, we do from scratch with telegram desktop and or
  telegram web and or telegram android being the inspiration for gui for every core.
  think of the best implementation with gio, rethinking it. move tests to /tests.
  update agents.md." Executed completely; sandbox had been wiped (toolchain reinstalled
  from env.sh recipe, mod cache refilled).
- **GUI removal (commit bcead437, pushed):** go/gui (402 files) + the gui-only media
  cluster (lottie/h264vid/vp9anim/webm/vcodec/qrscan — importers were all gui) +
  scripts/web-test + web.sh + devroot-setup.sh + r49-r56 stage scripts deleted;
  go/audio lost its two gio hooks (view_android.go, mic-permission import) — the tree
  is now gio-free, go.mod drops gioui/systray/dbus/xgb/gozxing/govid/govpx/shiny;
  cmd/uniclient rewritten as the headless engine host (-dir/-password/-events, SIGTERM
  clean shutdown). §4 real-interface evidence: boots, vault+dirs created, "engine
  ready" logged, `timeout --preserve-status -s TERM` exit 0. CI: verify.yml gains the
  headless smoke, loses Gio headers/webm/vp9anim/gui race legs/android/gui-smoke;
  cross-builds = windows + js/wasm compile check; release.yml drops android+web jobs;
  flake.nix pure-Go (no gio buildInputs, no cgo); Makefile/gate.sh/dev-test.sh/build.sh/
  env.sh trimmed to the headless shape.
- **Tests move (commit 27faa5a4, pushed):** 163 _test.go files → go/tests/{cores,engine,
  utils,audio,voice,bootstrap,aacaud} as `package tests` + dot-import; live tests stay
  at tests/ root. The suites were deep white-box, so: 302 identifiers exported by
  rename (engine 72, cores 230; audio's platform layer wholesale: Device interface,
  OpenDevice, Pulse/Winmm/WebDevice + methods, OpenSL ABI consts/structs, JNI vtable,
  BQRing; utils WriteVaultBytes/MergeVaultData/DeriveVaultKey; aacaud CheckASC; voice
  via existing Sources()); fields/methods/ctors quarantined as ForTest* hooks in
  testhooks*.go (engine 64, cores 189+6 manual, audio js-tagged); mutex/array getters
  return pointers; map-of-value state uses With* copy hooks; source-scan pins updated
  (lockorder glob, api_body_cap/privatedir/pathsafe/gzip_drain/matrix_renew/xmpp_styling/
  download_integrity needles + ../../ paths); map-literal fixtures rebuilt as
  constructor calls; two tests that pinned the deleted gui tree were updated
  (TestDimensionBombWiringGone removed; api_body_cap audit list lost ../gui).
  Migration machinery (error-position-driven, git-original-rebuilding) in
  /home/z/my-project/scripts/{pass1_renames,pass2_hooks,pass3_gen_hooks,pass4_edits,
  migrate_edits,migrate_hooks,fix_arity,fix_zeros}.py — workspace-only, not in the repo.
- **AGENTS.md v4.1 (this commit):** one file, still law+reference. NEW §5 (tests live
  in go/tests/, black-box, ForTest hooks are debt with retirement rule) and NEW §6
  (the rebuilt GUI design law: Elm loop with one owner goroutine and pure
  update/view, single event pump with coalescing, capabilities project the UI,
  layout = pure function of Model+size with 3/2/1-pane breakpoints and a typed route
  stack, Telegram-flavored Material tokens + widget kit, perf laws, --script action
  channel for agent-driven testing). Direction block records the removal + the
  Telegram references; AyuGram mandate revoked forever; §7 arch tree, §8 CI, §9 ladder
  updated to the headless/tests shape; ceiling raised 300→320 (two new law sections).
- Gate evidence (all local, this session): `go test -tags goolm -count=1 ./...` =
  7/7 ok (aacaud 0.28s, audio 0.002s, bootstrap 0.86s, cores 15.8s, engine 5.6s,
  utils 1.4s, voice 0.07s); `go vet -tags goolm ./...` green; `go vet -tags goolm,live
  ./tests/` green; gofmt -l empty; strip_comments --check clean (315 files); `-race
  ./tests/cores/` pinned subset ok 8.05s; GOOS=js wasm-runner ./tests/audio/ ok 0.33s;
  windows + js builds of ./... ok. Toolchain note: disk filled once (stale /tmp
  go-build dirs from killed compiles) — cleaned, 2.3G free.
- Carried owner facts (record only): R9 web-vault default-password decision was
  pending; v0.10.4 release + Pages re-enable were owner-in-flight (Session 341); CI
  runs 41282402414/41282912766/41289289707 superseded by this session's dispatch.
