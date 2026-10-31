# HOT.md — the urgent store (AGENTS.md §0.3, §6)

Read FIRST every session, right after the WORKLOG STATE block. Anything the next
session MUST know lands here the moment it is noticed; prune the moment it is stale.
This is not history — stale lines are lies.

- **verify.yml run 41179413739** (on c4f733b4 — native proof for R15+R14+R16
  together) dispatched this session; pending. The earlier dispatch
  41177906124 (51b3d240, R15+R14 only) sat QUEUED ~50min with zero other
  runs — GitHub runner starvation; superseded by the newer dispatch, cancel
  it if it ever goes in_progress. History: 41174703134 (R14 alone) =
  FAILURE — the R14 fix's own test self-deadlocked (held a.mu, then called
  snapshot() which locks a.mu again), and the local js leg had FALSE-GREENED
  it: **wasm-test-runner.sh accepted node exit 0 with no verdict** (a hung
  wasm drains node's event loop) — the suite silently truncated at that
  test. Both FIXED this session (runner now requires the binary's PASS
  line; regression harness scripts/test-wasm-runner.sh wired into the
  gates; test no longer holds the lock). R15, R16 in BUGS.md.
- **P0 chunk 3 in flight** (per-file gui surfaces): DONE so far — chat.go,
  sidebar.go, chatsearch.go, shortcuts.go (sessions 331-332; R16 came out
  of the shortcuts iteration). MAP.md chunk table is the tracker; chunk 2
  (state core) DONE, R14/R15/R16 all FIXED.
- **Watch item needing reference verification (law 22/23)**: failed send loses
  the typed text (composer cleared before the async result; tdesktop keeps it)
  — chat.go trySubmitComposer + inline-bot/music-attach/sticker send paths.
  Verify against AyuGramDesktop, then promote to a BUGS row or drop.
- Toolchain recovery recipe: `scripts/env.sh` (proven twice). VM wipes are
  routine — source it first thing. web-test node_modules + chrome restored
  this session.
