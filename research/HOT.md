# HOT.md — the urgent store (AGENTS.md §0.3, §6)

Read FIRST every session, right after the WORKLOG STATE block. Anything the next
session MUST know lands here the moment it is noticed; prune the moment it is stale.
This is not history — stale lines are lies.

- **verify.yml run 41177906124** (R15+R14 native proof, on 51b3d240) is
  in flight — READ ITS RESULT before trusting native green. History:
  41174703134 (R14 alone) = FAILURE — the R14 fix's own test
  TestInSearchFromPanelIsPerWindow self-deadlocked (held a.mu, then
  called snapshot() which locks a.mu again), and the local js leg had
  FALSE-GREENED it: **wasm-test-runner.sh accepted node exit 0 with no
  verdict** (a hung wasm drains node's event loop) — the suite silently
  truncated at that test. Both FIXED this session (runner now requires
  the binary's PASS line; regression harness scripts/test-wasm-runner.sh
  wired into the gates; test no longer holds the lock). R15 in BUGS.md.
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
