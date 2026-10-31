# HOT.md — the urgent store (AGENTS.md §0.3, §6)

Read FIRST every session, right after the WORKLOG STATE block. Anything the next
session MUST know lands here the moment it is noticed; prune the moment it is stale.
This is not history — stale lines are lies.

- **P0 chunk 3, session 337 (2026-11-01)**: iteration 20 DONE — state.go
  part 2 finished the file. **R32**: UI.avatarCorners plain int written by
  refreshConfig from five goroutine contexts vs per-frame layout reads →
  atomic.Int32; RED = dep-free scratch repro under -race (DATA RACE at
  applyAvatarCorners vs avatarRadiusPx), GREEN = LOCAL -race clean on the
  new pin (avatarcorners_r32_test.go — first session the race build fit
  the 4 GiB box) + CI race-leg filter extended. **R33**:
  show_sender_name dead-load + hardcoded-true applyReactionsNotify
  stomped other clients' setting → senderName on notifyAcctState via pure
  applyReactionsMap (notifyaccts_r33_test.go). Rows in BUGS; part-2
  section + two P4 watch items in MAP (applyGhostFlag split RMW;
  addAccount authAcct clobber). Next: unscanned gui files; verify the CI
  run for the R32/R33 commit at job+step level once dispatched.
- **Wipe #5 (session 337 boot)**: BOTH repo and toolchain gone. Full
  env.sh recipe re-run from zero (clone → tarball → mod download →
  devroot-setup). Confirmed: **the WORKLOG STATE block is the resume
  truth, not any handoff summary** (summary said chunk 2 iteration 2;
  repo was at chunk 3 iteration 19). The upload token file was still
  there for the clone.
- **Proofs (session 335, all landed)**: R25 proof **41205692894
  (bf9ea2bf) = SUCCESS** and R27 proof **41206658703 (d029af30) =
  SUCCESS** — both verified at job AND step level (all 5 jobs each; the
  Race legs carry the extended gui pins: R18/R23/R24/R25 + the
  TestShotRenderPipelineIsSerialized R27 pin). R28/R29/R30 are pure
  gui-code + test changes covered by the same Test legs those runs
  execute — R30's dispatch goes out with its commit; check the run at
  job+step level. Local -race on gui still OOMs on gotd; CI is the race
  proof path.
- **Wipe #4 lessons (session 335 boot)**: only the repo clone was gone —
  /home/z/my-project/toolchain SURVIVED (go 1.27.0 + mod cache), but
  **scripts/ was wiped: scanner v3 (pkgvar_scan_v3) is GONE** — its queue
  is fully baked into MAP so it is not needed unless the scan must rerun
  (rebuild: go/ast walk of package vars; v2's regex let struct fields
  leak). **Two toolchains now exist**: env.sh's
  /home/z/my-project/toolchain (go1.27.0) vs devroot-setup's ~/.local/go
  (go1.27.1) — mixing them poisons GOCACHE with version-mismatch
  objects. Working combo after a wipe: `sh scripts/devroot-setup.sh && .
  ./devroot.env` + `export GOMODCACHE=/home/z/my-project/toolchain/mod
  GOCACHE=/home/z/my-project/toolchain/gocache` (reuse the survived mod
  cache; go test needs `-tags goolm`; env.sh's 1.27.0 URL is one patch
  behind — devroot-setup installs 1.27.1, standardize on it).
- **Edit-tool + gofmt trap (cost one gate cycle)**: every Edit/MultiEdit
  write normalizes tabs→spaces across the WHOLE .go file; `gofmt -w`
  restores them — but ONLY with devroot.env sourced (a fresh shell says
  "gofmt: command not found" and an `&&` chain hides it). RULE: after any
  Edit to .go files, run `. ../devroot.env && gofmt -w <file> && gofmt -l
  ./gui/` and expect EMPTY output before gating/committing; if git diff
  --stat shows a whole-file rewrite, gofmt never ran.
- R24 native+race proof **41189550503 (cf60ce4d) = SUCCESS, all 5 jobs at
  step level** — the gui pins (R18/R23/R24) are proven under -race on CI;
  the race-leg filter now also carries TestIVPhotoClaimGuarded (R25).
- Gio harness lessons in MAP: pointer.Drag is not queueable
  (Move-while-pressed synthesizes Drag), pane-coord boundaries make edge
  presses miss rows. Bare `&App{eng: &engine.Engine{}}` is a viable
  harness for engine-touching gui code (zero Engine errors fast on
  getAccount miss) — used by TestIVPhotoRetryAfterFailure.
- Toolchain recovery recipe: `scripts/env.sh` header steps 1-5 (proven
  through wipes #2/#3/#4). web-test node_modules + chrome NOT re-verified
  after wipe #4 (only needed for web-gate legs).
