# HOT.md — the urgent store (AGENTS.md §0.3, §6)

Read FIRST every session, right after the WORKLOG STATE block. Anything the next
session MUST know lands here the moment it is noticed; prune the moment it is stale.
This is not history — stale lines are lies.

- **P0 chunk 3, session 338 (2026-11-01)**: iterations 21-26 DONE —
  business.go (R34+R35+R36), settingspremium.go (**R37**), settingsstars
  .go (**R38**, incl. the append-into-frame-visible-slice half — siblings
  with paging MUST build fresh slices, not append), foldermgr.go (**R39**
  + the settings-shell exclusivity matrix), stickermanager.go (**R40** —
  six writer sites), profileedit.go (**R41** — flag race via atomic.Bool,
  write-only busy state removed, matrix COMPLETE for every opener). R34 =
  the systemic one: frame-carried sub-page structs mutated in place by
  background tails under a.mu vs layout reads under frameMu — five of
  six swept files install copies via their update<Page> helper
  (profileedit's loader was already fresh-replace). **Sibling sweep
  continues** (one iteration per file, order in MAP): exportdlg.go →
  twofa.go → instantview.go's load tail.
- **CI proofs**: CLOSED — R32/R33 **41222152669 (be7541e4)**, R34-R36
  **41236970838 (f14028a6)**, R37 **41237343094 (e6de37fc)**, R38
  **41237698797 (6fdb1835)**, R39 **41238091947 (f38e19f7)**: all
  SUCCESS at job AND step level (all 5 jobs each; Race steps green).
  Pending: **41238742290** (R40, 1d143036) + **41239171673** (R41,
  733d220b) — verify EACH at job+step level (the race leg carries
  R34×2 + R37×2 + R38×3 + R39×3 + R40×3 + R41×3 pins). Local -race on the gui
  package fits the box (proven 337/338 — use it before falling back to
  CI).
- **Wipe #6 (session 338 boot)**: repo + toolchain + download/ copies
  gone; the upload token file survived. Full recipe re-run from zero
  (clone → go1.27.1 tarball → mod download → devroot-setup), ~10 min.
  Confirmed again: the WORKLOG STATE block is the resume truth (HEAD was
  one commit AHEAD of the handoff summary). If a verify.yml dispatch is
  redundant (an earlier run for the same SHA already succeeded), cancel
  it — CI minutes are not free.
- **Edit-tool + gofmt trap (hit THREE times in 338 — and it bites on
  FAILED edits too: a MultiEdit whose old_str mismatched still left the
  file tab→space normalized, breaking gofmt with no obvious cause)**:
  every Edit/MultiEdit write normalizes tabs→spaces across the WHOLE
  .go file; `gofmt -w` restores them — but ONLY with devroot.env
  sourced (a fresh shell says "gofmt: command not found"). RULE: after
  ANY Edit ATTEMPT (successful OR failed) on .go files, run
  `. ../devroot.env && gofmt -w <file> && gofmt -l ./gui/` (from go/gui)
  and expect EMPTY output before gating/committing; if git diff --stat
  shows a whole-file rewrite, gofmt never ran. For surgical edits with
  exact whitespace, a python heredoc with explicit \t avoids the
  tool's normalization entirely.
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
