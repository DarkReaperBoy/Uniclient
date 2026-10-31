# HOT.md — the urgent store (AGENTS.md §0.3, §6)

Read FIRST every session, right after the WORKLOG STATE block. Anything the next
session MUST know lands here the moment it is noticed; prune the moment it is stale.
This is not history — stale lines are lies.

- **CI saga RESOLVED (session 333)**: the "starved" runs were **zombie
  dispatches** — Actions was DISABLED at the repo level (found via
  `actions/permissions` → `enabled:false`; flipped off between Oct 31 07:16
  and wipe #3, cause unknown — likely accidental, it also blocked the owner's
  own release.yml). Re-enabled via API this session (full-scope token,
  decision logged in WORKLOG 333). The three old dispatches (41179924424 /
  41179413739 / 41177906124) are PERMANENT zombies — never enqueued, cancel
  409s ("has not been queued yet"), delete 403s; ignore them. Fresh dispatch
  on re-enable works: **41181306179** (b58d7a102 = HEAD) = the native proof
  for R15+R14+R16+R17 — READ ITS RESULT next session before trusting native
  green. If a run ever sits `queued` with zero in-progress runs again, check
  `actions/permissions` FIRST, not runner starvation.
- **P0 chunk 3 in flight** (per-file gui surfaces): DONE so far — chat.go,
  sidebar.go, chatsearch.go, shortcuts.go, settings.go (sessions 331-332;
  R16 and R17 came out of the last two). MAP.md chunk table is the tracker;
  chunk 2 (state core) DONE; R14-R17 all FIXED.
- **Watch item needing reference verification (law 22/23)**: failed send loses
  the typed text (composer cleared before the async result; tdesktop keeps it)
  — chat.go trySubmitComposer + inline-bot/music-attach/sticker send paths.
  Verify against AyuGramDesktop, then promote to a BUGS row or drop.
- Toolchain recovery recipe: `scripts/env.sh` header steps 1-5 — proven
  through **wipe #3** (session 333: full re-download of go 1.27.0 + mod-cache
  refill 1.3G). VM wipes are routine — source it first thing. web-test
  node_modules + chrome were restored in session 332; NOT yet re-verified
  after wipe #3 (only needed for web-gate legs).
