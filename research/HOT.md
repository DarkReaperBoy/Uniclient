# HOT.md — the urgent store (AGENTS.md §0.3, §6)

Read FIRST every session, right after the WORKLOG STATE block. Anything the next
session MUST know lands here the moment it is noticed; prune the moment it is stale.
This is not history — stale lines are lies.

- **CI backlog FULLY CLOSED (session 334)**: 41184046305 (2e606d58, R20+R21
  native proof) = SUCCESS, and 41184562534 (a8880414, R22 proof) = SUCCESS —
  both verified at job AND step level this session (all 5 jobs green; the Nix
  gate's 7/8 is the tag-only version check, correctly skipped on main pushes).
  Durable lesson kept: if a run ever sits `queued` with zero in-progress runs,
  check `actions/permissions` FIRST (repo-level disable) — not runner
  starvation. The three 411779-411799 zombie dispatches are permanent, ignore.
- **P0 chunk 3, session 334**: iterations 8+9 DONE — separate.go (multi-window
  core, **VERDICT CLEAN**, full invariant audit in MAP) and rubberband.go
  (**R23 FIXED**: package-level gesture state vs per-App selOn — other
  window's frame killed in-flight rubber-band drags or painted phantom
  rects; moved to App fields; TestRubberBandGestureIsPerWindow drives the
  real overlay via input.Router; gate quick GREEN; native proof 41188229919 = **SUCCESS** at job level, all 5 legs).
  **frameMu discovery (load-bearing)**: Root() holds frameMu for the entire
  frame, so layout-only package state cannot data-race — residual bug shapes
  are semantic cross-window bleed (R14/R23) and outside-layout writes
  (R22-class maps). Chunk-3 ranking queue + this lens live in MAP; scanner
  is now **v3 (go/ast, exact)** at `/home/z/my-project/scripts/pkgvar_scan_v3`
  (v2's regex let menu.go struct fields leak in as false positives).
  Iteration 10 menu.go CLEAN (pools already per-App; 3 P3 notes in MAP).
  Iteration 11 webpage.go CLEAN (maps mutex-guarded; 2 P4 notes). Iteration
  12 suggestionbar.go → **R24 FIXED**: suggStates/suggFetching/suggDismissed
  had NO mutex — the fetch goroutine raced the GUI loop's every-frame reads
  (fatal concurrent-map class, reachable at every boot; goroutine ≠ frame
  so frameMu irrelevant). Six suggMu-guarded helpers; compile-seam RED test
  hammers both sides; **verify.yml race leg extended to the gui concurrency
  pins (R18/R23/R24) — js has no race detector, native CI is the proof;
  R23 proof 41188229919 = SUCCESS all 5 legs; R24 proof = 41189550503
  (cf60ce4d) in flight — READ ITS RESULT before trusting race green for
  the new gui leg**. Next per the queue
  in MAP: **richtext.go, then instantview.go (ivDocDone watch item),
  msgshot.go, translatebar.go + profilemusic.go** (cornerreply +
  cornerreaction DONE this session — both clean; cornerreply's shared
  hover is cursor-correct by construction, cornerreaction fully
  favMu-guarded; calibration: remaining queue skews guarded).
  Gio harness lessons in MAP: pointer.Drag is not queueable
  (Move-while-pressed synthesizes Drag), pane-coord boundaries make edge
  presses miss rows.
- Toolchain recovery recipe: `scripts/env.sh` header steps 1-5 — proven through
  **wipe #3** (session 333: full re-download of go 1.27.0 + mod-cache refill
  1.3G). VM wipes are routine — source it first thing. web-test node_modules +
  chrome were restored in session 332; NOT re-verified after wipe #3 (only
  needed for web-gate legs).
