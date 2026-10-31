# HOT.md — the urgent store (AGENTS.md §0.3, §6)

Read FIRST every session, right after the WORKLOG STATE block. Anything the next
session MUST know lands here the moment it is noticed; prune the moment it is stale.
This is not history — stale lines are lies.

- **verify.yml run 41174703134** (R14 fix 497a4528's native proof) was
  still in_progress at this session's last check — READ ITS RESULT before
  trusting native green for the next Go change. (Session 329's equivalent run
  41152637658 came back SUCCESS.)
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
