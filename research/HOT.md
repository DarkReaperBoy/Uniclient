# HOT.md — the urgent store (AGENTS.md §0.3, §6)

Read FIRST every session, right after the WORKLOG STATE block. Anything the next
session MUST know lands here the moment it is noticed; prune the moment it is stale.
This is not history — stale lines are lies.

- **P0 chunk 3, session 335**: iterations 15 (instantview.go) and 16
  (msgshot.go) DONE, both read in full — **R25** (IV photo latch →
  in-flight claim), **R26** (related-fetch generation gate), **R27**
  (shot render pipeline: lazily-written face caches + SHARED opentype.Face
  scratch buffers raced on the save goroutine, plus the palette read
  racing applyTheme → shotMu + GUI-loop palette capture). Rows in BUGS
  Fixed, sections in MAP. Native race proof: verify.yml **41205692894
  (bf9ea2bf, carries the R25 pin) IN FLIGHT at last check — read its
  result; it does NOT carry the R27 pin** (filter extended after
  dispatch) → **dispatch a fresh verify.yml for 674c41f9 (R27) once it
  finishes** (local -race on gui still OOMs on gotd). Queue after:
  **translatebar.go (transPickerOpen), then profilemusic.go (musicList)**
  — calibration note in MAP: v3 flags keep paying out, assume nothing.
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
