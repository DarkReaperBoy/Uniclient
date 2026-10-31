# HOT.md — the urgent store (AGENTS.md §0.3, §6)

Read FIRST every session, right after the WORKLOG STATE block. Anything the next
session MUST know lands here the moment it is noticed; prune the moment it is stale.
This is not history — stale lines are lies.

- **R14 is BUGS.md topmost** (race class): package-level `inSearchFromPanel` in
  gui/chatsearch.go — cross-window unsynchronized access; fix = per-App field,
  red test = two App instances toggling independently. Caught in P0 recon
  (session 331); fix belongs to P2.
- **P0 chunk 2 DONE** (gui state core); chunk 3 = remaining ~88 gui files, one
  surface per iteration (MAP.md chunk table is the tracker).
- Toolchain recovery recipe: `scripts/env.sh` (BASH_SOURCE-fixed, proven).
  VM wipes are routine — source it first thing; `. scripts/env.sh` from repo root.
