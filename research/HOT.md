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
- **P0 chunk 3 iteration 8 DONE (session 334)**: separate.go (359 ln) read in
  full — **VERDICT CLEAN**, the multi-window core is the best-defended file in
  gui (registry sepMu-guarded, uniform sepMu→a.mu order verified at openChat
  1400-1426, hop discipline holds, lock-bus subscribe-before-boot-decision is
  airtight, reopen guard unreachable from separate Apps). MAP has the full
  write-up. **Chunk-3 ranking queue now in MAP** (pkg-var scan v2 +
  separateChatView-reachability rule): next = rubberband.go (message-list
  selection gesture = chat surface = multi-window), then menu.go, richtext.go,
  instantview.go, msgshot.go, cornerreply.go, profilemusic.go. Scanner lives at
  `scripts/pkgvar_write_scan.py` (v2 — v1 missed grouped var blocks; business.go's
  whole widget pool was invisible). ivDocDone one-shot-on-failure watch item is
  in MAP (instantview iteration confirms before any R-number).
- Toolchain recovery recipe: `scripts/env.sh` header steps 1-5 — proven through
  **wipe #3** (session 333: full re-download of go 1.27.0 + mod-cache refill
  1.3G). VM wipes are routine — source it first thing. web-test node_modules +
  chrome were restored in session 332; NOT re-verified after wipe #3 (only
  needed for web-gate legs).
