# HOT.md — the urgent store (AGENTS.md §0.3, §6)

Read FIRST every session, right after the WORKLOG STATE block. Anything the next
session MUST know lands here the moment it is noticed; prune the moment it is stale.
This is not history — stale lines are lies.

- **verify.yml run 41174703134 (R14 native proof) = FAILURE — do NOT trust
  the R14 "native dispatched" claim until re-run green.** The R14 fix's own
  test TestInSearchFromPanelIsPerWindow self-deadlocks: it holds a.mu and
  then calls snapshot() which locks a.mu again (chatsearch_test.go:24-25,
  state.go:2178). Worse: **wasm-test-runner.sh had a false-green hole** — a
  deadlocked js test drains node's event loop → node exits 0 with no verdict
  → runner's `RC==0 → exit 0` short-circuit declared GREEN (session 331's
  "gui suite 0.596s green" was FALSE; the suite silently truncated at this
  test). Both being fixed this session; native proof requires a fresh
  verify.yml run.
- **P0 chunk 3 in flight** (per-file gui surfaces): chat.go DONE (iteration 1).
  Next: sidebar.go (36KB, the chat-list journey). MAP.md chunk table is the
  tracker. Chunk 2 (state core) DONE; R14 (found there) is FIXED.
- **Watch item needing reference verification (law 22/23)**: failed send loses
  the typed text (composer cleared before the async result; tdesktop keeps it)
  — chat.go trySubmitComposer + inline-bot/music-attach/sticker send paths.
  Verify against AyuGramDesktop, then promote to a BUGS row or drop.
- Toolchain recovery recipe: `scripts/env.sh` (proven twice). VM wipes are
  routine — source it first thing. web-test node_modules + chrome restored
  this session.
