# HOT.md — the urgent store (AGENTS.md §0.3, §6)

Read FIRST every session, right after the WORKLOG STATE block. Anything the next
session MUST know lands here the moment it is noticed; prune the moment it is stale.
This is not history — stale lines are lies.

- **verify.yml queue is STARVED (GitHub side): three runs pending** — read the
  NEWEST first: **41179924424** (on 04b4a07f — native proof for R15+R14+R16+
  R17, the one that matters), then 41179413739 (c4f733b4, R15+R14+R16),
  41177906124 (51b3d240, R15+R14; superseded). None started >1h after
  dispatch with zero other runs in the repo — GitHub runner starvation;
  cancel-API returns 409 on pending dispatches, so they were left to run as
  duplicate proofs. History: 41174703134 (R14 alone) = FAILURE — the R14
  fix's own test self-deadlocked (held a.mu, then called snapshot() which
  locks a.mu again), and the local js leg had FALSE-GREENED it
  (**wasm-test-runner.sh accepted node exit 0 with no verdict** — a hung
  wasm drains node's event loop; the suite silently truncated). All FIXED
  this session (runner requires the binary's PASS line, regression harness
  scripts/test-wasm-runner.sh wired into the gates, test un-deadlocked,
  R16 Ctrl+Tab drain order, R17 About version lockstep).
- **P0 chunk 3 in flight** (per-file gui surfaces): DONE so far — chat.go,
  sidebar.go, chatsearch.go, shortcuts.go, settings.go (sessions 331-332;
  R16 and R17 came out of the last two). MAP.md chunk table is the tracker;
  chunk 2 (state core) DONE; R14-R17 all FIXED.
- **Watch item needing reference verification (law 22/23)**: failed send loses
  the typed text (composer cleared before the async result; tdesktop keeps it)
  — chat.go trySubmitComposer + inline-bot/music-attach/sticker send paths.
  Verify against AyuGramDesktop, then promote to a BUGS row or drop.
- Toolchain recovery recipe: `scripts/env.sh` (proven twice). VM wipes are
  routine — source it first thing. web-test node_modules + chrome restored
  this session.
