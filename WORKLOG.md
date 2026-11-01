# WORKLOG.md — the state file

Top: the **STATE block** — rewritten every session, the resume pointer for the next
agent. Then open items (severity order), then entries newest-first, terse (did /
evidence / next). The pre-2026-11-01 progress docs (BUGS.md, research/) were purged by
owner order — that history lives in git if ever needed.

## STATE

- front: 2026-11-01 owner redirect #2 FULLY EXECUTED + CI-GATED — GUI removed, tests in go/tests/, AGENTS.md v4.1 (commits bcead437, 27faa5a4, f80f9b2d + flake pin a05066c8)
- next: standby for the owner's next instruction; treat it as the new front and execute it completely (never ask, never wait)
- owner-waiting: the next direction; the GUI build order (design is law in AGENTS.md §6 — Elm loop, Telegram Desktop/Web/Android references, capability-projected, Gio)
- last-gate: CI verify **41317140352 = SUCCESS on a05066c8** — all 3 jobs, all steps (comment-ban, gofmt, vet, vet-live, test, race tests/cores subset, headless smoke, nix build + nix run smoke, windows exe, js/wasm check); flake.yml 41316797193 pinned the new vendorHash first

## Open items

| ID | where | what | evidence | next step |
|---|---|---|---|---|
| H-1 | cores/engine testhooks*.go | ForTest* hooks are debt (§5.3): ~260 hooks exist because the suites were white-box | AGENTS.md §5.3 (2026-11-01) | retire hooks as flows gain exported APIs; prune when a hook's last use dies |
| H-2 | verify/release yml | android APK + web (gh-pages) + Xvfb GUI legs parked until the new GUI | AGENTS.md §6/§8 | re-add with the GUI build (owner order pending) |
| H-3 | engine/cores API | 302 identifiers exported purely for the tests move (API noise: TsParseInit1, ForTest-adjacent) | commit 27faa5a4 | fold into real APIs or de-export when tests are reworked during the GUI rebuild |

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
