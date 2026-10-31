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
  real overlay via input.Router; gate quick GREEN; **native proof = verify.yml
  41188229919 (ea3b12ac) — READ ITS RESULT before trusting native green
  for R23**).
  **frameMu discovery (load-bearing)**: Root() holds frameMu for the entire
  frame, so layout-only package state cannot data-race — residual bug shapes
  are semantic cross-window bleed (R14/R23) and outside-layout writes
  (R22-class maps). Chunk-3 ranking queue + this lens live in MAP; scanner
  is now **v3 (go/ast, exact)** at `/home/z/my-project/scripts/pkgvar_scan_v3`
  (v2's regex let menu.go struct fields leak in as false positives).
  Iteration 10 menu.go CLEAN (pools already per-App; 3 P3 notes in MAP).
  Next per the v3-reshuffled queue in MAP: **webpage.go (webPhotoDone/
  webPhotoFailed MAPS in link previews — R22 fatal class if download
  goroutines write them), then suggestionbar.go (suggStates map),
  cornerreply.go + cornerreaction.go, richtext.go, instantview.go
  (ivDocDone watch item), msgshot.go, translatebar.go + profilemusic.go**.
  Gio harness lessons in MAP: pointer.Drag is not queueable
  (Move-while-pressed synthesizes Drag), pane-coord boundaries make edge
  presses miss rows.
- Toolchain recovery recipe: `scripts/env.sh` header steps 1-5 — proven through
  **wipe #3** (session 333: full re-download of go 1.27.0 + mod-cache refill
  1.3G). VM wipes are routine — source it first thing. web-test node_modules +
  chrome were restored in session 332; NOT re-verified after wipe #3 (only
  needed for web-gate legs).
