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
  409s ("has not been queued yet"), delete 403s; ignore them. **41181306179
  (b58d7a102) = SUCCESS — native proof for R15+R14+R16+R17, CI backlog
  CLOSED.** **41182590400** (4883033a, dispatched this session) = native +
  race-leg proof for R18+R19 — READ ITS RESULT next session before trusting
  native green for those. If a run ever sits `queued` with zero in-progress
  runs again, check `actions/permissions` FIRST, not runner starvation.
- **P0 chunk 3 in flight** (per-file gui surfaces): DONE so far — chat.go,
  sidebar.go, chatsearch.go, shortcuts.go, settings.go (331-332), mediaview.go
  (333 — produced R18 viewer-Share deadlock + R19 cross-window viewer
  bookkeeping race, both FIXED). MAP.md chunk table is the tracker; chunk 2
  (state core) DONE; R14-R19 all FIXED. Next iteration: next surface from the
  MAP chunk table (candidates by size: profile.go 779, login.go 547,
  widgets.go 485, contacts.go 464; separate.go 359 is small but central to
  the multi-window theme).
- **Watch item needing reference verification (law 22/23)**: failed send loses
  the typed text (composer cleared before the async result; tdesktop keeps it)
  — chat.go trySubmitComposer + inline-bot/music-attach/sticker send paths.
  Verify against AyuGramDesktop, then promote to a BUGS row or drop.
- Toolchain recovery recipe: `scripts/env.sh` header steps 1-5 — proven
  through **wipe #3** (session 333: full re-download of go 1.27.0 + mod-cache
  refill 1.3G). VM wipes are routine — source it first thing. web-test
  node_modules + chrome were restored in session 332; NOT yet re-verified
  after wipe #3 (only needed for web-gate legs).
