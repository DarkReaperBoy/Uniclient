# HOT.md — the urgent store (AGENTS.md §0.3, §6)

Read FIRST every session, right after the WORKLOG STATE block. Anything the next
session MUST know lands here the moment it is noticed; prune the moment it is stale.
This is not history — stale lines are lies.

- **P0 chunk 3, session 335**: iterations 15-17 DONE (instantview,
  msgshot, translatebar, profilemusic — all read in full): **R25** (IV
  photo latch → in-flight claim), **R26** (related-fetch generation
  gate), **R27** (shot render pipeline: lazy face caches + shared
  opentype.Face scratch buffers raced on the save goroutine + palette
  read racing applyTheme → shotMu + GUI-loop capture), **R28**
  (transPickerOpen package bool → per-window App field, R14 class),
  **R29** (profile Music section was a dead button in separate windows —
  hidden there now). Rows in BUGS Fixed; sections + remaining notes in
  MAP. **v3 candidate queue EXHAUSTED** — next lens is the R29 systemic
  watch item (dead content-pane openers in separate windows), then the
  unscanned gui files.
- **Proofs all landed (session 335)**: R25 proof **41205692894
  (bf9ea2bf) = SUCCESS** and R27 proof **41206658703 (d029af30) =
  SUCCESS** — both verified at job AND step level (all 5 jobs each; the
  Race legs carry the extended gui pins: R18/R23/R24/R25 + the
  TestShotRenderPipelineIsSerialized R27 pin). R28/R29 landed after the
  dispatch but are pure gui-code + test changes covered by the same
  Test legs those runs execute — no dedicated proof pending. Local
  -race on gui still OOMs on gotd; CI is the race proof path.
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
