# HOT.md — the urgent store (AGENTS.md §0.3, §6)

Read FIRST every session, right after the WORKLOG STATE block. Anything the next
session MUST know lands here the moment it is noticed; prune the moment it is stale.
This is not history — stale lines are lies.

- **P0 chunk 3, session 335**: iteration 15 instantview.go DONE, read in full —
  **R25 FIXED** (ivDocDone photo latch: marked-done-before-download + silent
  error = one transient failure permanently thumbnail/blank until restart;
  now an in-flight claim ivPhotoClaim/ivPhotoRelease spanning the whole
  download→read→decode→store chain; failure retries on the next natural
  frame, no invalidate → no spin) and **R26 FIXED** (ivOpenRelated's
  `!cur.loading` landing guard was a flag, not a generation —
  back-during-fetch + re-navigate rearmed it and a straggler fetch pushed
  an unopened page onto the back stack; ivState.gen + pointer identity +
  ivLandRelated). Native race proof for the R25 hammer: verify.yml
  **41205692894 (bf9ea2bf) dispatched, IN FLIGHT — read its result before
  trusting race green for the extended gui leg** (local -race OOMs on gotd
  as always). Queue after: **msgshot.go (shotFaceCache/shotSmallFaceCache),
  then translatebar.go + profilemusic.go** — sections + calibration in MAP.
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
