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
  CLOSED.** **41182590400** (4883033a) = **SUCCESS — native+race proof for
  R18+R19 landed.** **41184046305** (2e606d58, dispatched this session) =
  native proof for R20+R21 — READ ITS RESULT next session before trusting
  native green for those. **41184562534** (a8880414, also in flight) = the
  R22 proof. If a run ever sits `queued` with zero in-progress runs again,
  check `actions/permissions` FIRST, not runner starvation.
- **P0 chunk 3 in flight** (per-file gui surfaces): DONE so far — chat.go,
  sidebar.go, chatsearch.go, shortcuts.go, settings.go (331-332), mediaview.go
  + profile.go (333). MAP.md chunk table is the tracker; chunk 2 (state
  core) DONE; R14-R22 all FIXED. Session 333 alone produced R18-R22 (five:
  viewer-Share deadlock, cross-window viewer bookkeeping race, failed-send
  tick mapping + Resend wiring, runner flag-dropping, panel mute-pool fatal
  map race). Next iteration: login.go 547 / widgets.go 485 / contacts.go
  464 / emoji.go 446 / stickers.go 436 — or separate.go 359, small but
  central to the multi-window theme that keeps producing bugs.
- **Session 333 also produced R20 + R21** (same session, later turns): R20 =
  the outgoing-status tick mapping was shifted against the engine consts
  (a permanently failed send drew the DELIVERED double-check; RetryPending
  had no gui wiring) — fixed with statusTickKind + Resend action + failure
  toast; the old "failed send loses typed text" watch item is RESOLVED
  (premise was wrong: the text lives in the failed bubble via the pending
  queue — tdesktop's model). R21 = wasm-test-runner.sh dropped every
  go-test flag (two layers: shell didn't forward "$@" to node; driver set
  go.argv to just the binary path) — filtered evidence runs were silently
  full-suite; fixed + harness contract #4. TRUE filtered runs now work
  (-run/-v visible). NOTE for future evidence claims: any pre-R21
  "single-test" js-leg evidence in old WORKLOG entries was actually
  full-suite evidence.
- Toolchain recovery recipe: `scripts/env.sh` header steps 1-5 — proven
  through **wipe #3** (session 333: full re-download of go 1.27.0 + mod-cache
  refill 1.3G). VM wipes are routine — source it first thing. web-test
  node_modules + chrome were restored in session 332; NOT yet re-verified
  after wipe #3 (only needed for web-gate legs).
