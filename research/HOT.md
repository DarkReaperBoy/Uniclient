# HOT.md — the urgent store (AGENTS.md §0.3, §6)

Read FIRST every session, right after the WORKLOG STATE block. Anything the next
session MUST know lands here the moment it is noticed; prune the moment it is stale.
This is not history — stale lines are lies.

- **P0 chunk 3, session 338 (2026-11-01)**: iterations 21-25 DONE —
  business.go (R34+R35+R36), settingspremium.go (**R37**), settingsstars
  .go (**R38**, incl. the append-into-frame-visible-slice half — siblings
  with paging MUST build fresh slices, not append), foldermgr.go (**R39**
  + the settings-shell exclusivity matrix), stickermanager.go (**R40** —
  six writer sites; only openProfileEdit still misses 4 siblings). R34 =
  the systemic one: frame-carried sub-page structs mutated in place by
  background tails under a.mu vs layout reads under frameMu — all five
  files now install copies via their update<Page> helper. **Sibling sweep
  continues** (one iteration per file, order in MAP): profileedit.go →
  exportdlg.go → twofa.go → instantview.go's load tail.
- **CI proofs**: CLOSED — R32/R33 **41222152669 (be7541e4)**, R34-R36
  **41236970838 (f14028a6)**, R37 **41237343094 (e6de37fc)**, R38
  **41237698797 (6fdb1835)**: all SUCCESS at job AND step level (all 5
  jobs each; Race steps green). Pending: **41238091947** (R39, f38e19f7)
  + the R40 dispatch — verify at job+step level (the race leg carries
  R34×2 + R37×2 + R38×3 + R39×3 + R40×3 pins). Local -race on the gui
  package fits the box (proven 337/338 — use it before falling back to
  CI).
- **Wipe #6 (session 338 boot)**: repo + toolchain + download/ copies
  gone; the upload token file survived. Full recipe re-run from zero
  (clone → go1.27.1 tarball → mod download → devroot-setup), ~10 min.
  Confirmed again: the WORKLOG STATE block is the resume truth (HEAD was
  one commit AHEAD of the handoff summary). If a verify.yml dispatch is
  redundant (an earlier run for the same SHA already succeeded), cancel
  it — CI minutes are not free.
- **Edit-tool + gofmt trap (hit AGAIN in 338 — cost one gate cycle)**:
  every Edit/MultiEdit write normalizes tabs→spaces across the WHOLE
  .go file; `gofmt -w` restores them — but ONLY with devroot.env
  sourced. RULE: after any Edit to .go files, run
  `. ../devroot.env && gofmt -w <file> && gofmt -l ./gui/` (from go/gui)
  and expect EMPTY output before gating/committing.
- Gio harness lessons in MAP: pointer.Drag is not queueable
  (Move-while-pressed synthesizes Drag), pane-coord boundaries make edge
  presses miss rows. Bare `&App{eng: &engine.Engine{}}` is a viable
  harness for engine-touching gui code (zero Engine errors fast on
  getAccount miss) — and a bare `&App{}` works for pure-state methods
  (updateBusinessPage & friends; a.invalidate is nil-win-guarded).
- Toolchain recovery recipe: `scripts/env.sh` header steps 1-5 (proven
  through wipes #2/#3/#5/#6). Working combo after a wipe:
  `sh scripts/devroot-setup.sh && . ./devroot.env` + `export
  GOMODCACHE=/home/z/my-project/toolchain/mod
  GOCACHE=/home/z/my-project/toolchain/gocache` (go test needs `-tags
  goolm`; the gui race build fits the 4GiB box with -gcflags=all=-c=1).
  web-test node_modules + chrome NOT re-verified after wipe #6 (only
  needed for web-gate legs).
