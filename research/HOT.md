# HOT.md — the urgent store (AGENTS.md §0.3, §6)

Read FIRST every session, right after the WORKLOG STATE block. Anything the next
session MUST know lands here the moment it is noticed; prune the moment it is stale.
This is not history — stale lines are lies.

- **P0 chunk 3, sessions 338-340**: iterations 21-32 DONE — business.go
  (R34+R35+R36), settingspremium.go (**R37**), settingsstars.go
  (**R38**, incl. the append-into-frame-visible-slice half — siblings
  with paging MUST build fresh slices, not append), foldermgr.go
  (**R39** + the settings-shell exclusivity matrix), stickermanager.go
  (**R40** — six writer sites), profileedit.go (**R41** — flag race via
  atomic.Bool, write-only busy state removed, matrix COMPLETE for every
  opener), exportdlg.go (**R42** + **R43** — the engine-event writers +
  start-tail via updateExportDlg; the never-reset checkbox seed flag;
  contentDialogSurface peer, NO matrix gap), twofa.go (**R44** + **R45**
  — THIRTEEN writer sites via updateTwoFADlg incl. GUI-loop clicks;
  accountID guards REPLACE pointer-identity guards, which break under
  copy-on-write; the settings-row map refresh via the R38 fresh-map
  rule), instantview.go (**R46** — updateIV + openID/gen staleness keys,
  fresh-slice pushHistory, docBusy's ivDocMu claim re-verified).
  **THE R34 SYSTEMIC WATCH IS CLOSED — every frame-carried gui surface
  is now copy-on-write; the per-file lens works the unscanned queue by
  size: media.go 1,186 DONE CLEAN (iteration 30), giveaways.go 1,171
  DONE (**R47** + **R48**, iteration 31 — incl. the unlocked dateIdx
  clamp / send-dead bug), callsbox.go 1,089 DONE (**R49** + **R50**,
  iteration 32 — the load tail appended into the frame-shared backing
  array + had NO session guard; callsBoxGen key + fresh-slice merge),
  poll.go 972 DONE (**R51** + **R52**, iteration 33 — five in-place
  writers on the frame-carried *pollDlgState incl. the background send
  tail + the send goroutine reading a.wid switches; updatePollDlg CoW +
  pollDlgGen; TRUE -race RED proven for R52), stories.go 960 next.** Tab-exact python-heredoc edits dodge the
  Edit-tool gofmt trap.
- **CI proofs**: ALL CLOSED — R32/R33 **41222152669 (be7541e4)**, R34-R36
  **41236970838 (f14028a6)**, R37 **41237343094 (e6de37fc)**, R38
  **41237698797 (6fdb1835)**, R39 **41238091947 (f38e19f7)**, R40
  **41238742290 (1d143036)**, R41 **41239171673 (733d220b)**: all
  SUCCESS at job AND step level (all 5 jobs each; Race steps green;
  the only non-success step anywhere is the Nix "flake.nix version
  must match the release tag" gate, `skipped` by design off release
  tags). CLOSED: R42/R43 **41244407673 (9b2cf32d)**, R44/R45
  **41245057374 (1476115a)**, R46 **41245678978 (d8b4ce01)** and
  R47/R48 **41246248716 (12165b24)** — all 5 jobs success at step
  level, Race green (the race leg now carries R34×2 + R37×2 + R38×3 +
  R39×3 + R40×3 + R41×3 + R42/R43×5 + R44/R45×5 + R46×5 + R47/R48×6 +
  R49/R50×5 + R51/R52×4 pins). Pending: **41251708582** (R49/R50,
  0319f118) in flight + the R51/R52 dispatch after the next push — verify
  EACH at job AND step level. Local -race on the gui
  package fits the box (proven 337/338/339 — use it before falling
  back to CI).
- **Fresh-cache -race build OOM (session 339)**: after a wipe, the gui
  race build (`-race -gcflags=all=-c=1`) gets killed once on gotd/td/tg
  — RETRY the same command; the build cache carries progress and the
  second attempt completes. Don't lower GOMEMLIMIT or split the leg.
- **Wipe #7 (session 339 boot)**: repo + toolchain + download/ copies
  gone again (same shape as wipe #6); the upload token file survived.
  Full recipe re-run from zero (clone → go1.27.1 tarball → mod
  download), ~10 min. Confirmed a THIRD time: the WORKLOG STATE block
  is the resume truth (HEAD was
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
- Bash shells reset between tool calls (session 340): source the env
  in EVERY call — `. ./devroot.env && unset GOROOT && export
  GOMODCACHE=/home/z/my-project/toolchain/mod
  GOCACHE=/home/z/my-project/toolchain/gocache GOFLAGS=-p=1
  GOMEMLIMIT=3GiB GOGC=20`, then work from go/. scripts/env.sh alone
  sets GOROOT/PATH but NOT PKG_CONFIG_PATH — gui (CGO) builds then
  fail on xkbcommon/wayland-client; and once devroot's go is on PATH,
  GOROOT must be unset (two go trees sharing one GOCACHE poison it).
- Toolchain recovery recipe: `scripts/env.sh` header steps 1-5 (proven
  through wipes #2/#3/#5/#6). Working combo after a wipe:
  `sh scripts/devroot-setup.sh && . ./devroot.env` + `export
  GOMODCACHE=/home/z/my-project/toolchain/mod
  GOCACHE=/home/z/my-project/toolchain/gocache` (go test needs `-tags
  goolm`; the gui race build fits the 4GiB box with -gcflags=all=-c=1).
  web-test node_modules + chrome NOT re-verified after wipe #6 (only
  needed for web-gate legs).
