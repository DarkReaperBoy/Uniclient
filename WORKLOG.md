# WORKLOG.md — the session journal

Top: the **STATE block** — rewritten every session, the resume pointer for the
next agent. Below: one entry per work session, newest first. This is the
resume-from-zero mechanism. (The pre-2026-10 history was deleted by the owner
on 2026-10-30 — it lives in git history if ever needed.)

## STATE

- cycle: 2 | phase: P0 recon (chunk 3, per-file gui surfaces)
- item: iterations 8-15 DONE (separate/menu/webpage/cornerreply/cornerreaction/richtext CLEAN; suggestionbar R24, rubberband R23, instantview R25+R26 FIXED — photo-latch retry + related-fetch generation gate, rows in BUGS Fixed); R24 native+race proof 41189550503 = SUCCESS all 5 legs; scanner v3 queue in MAP (survived only as MAP content — the script itself was wiped, see HOT)
- next: read verify.yml 41205692894 (bf9ea2bf — R25 hammer's native+race proof, IN FLIGHT), then chunk 3 iteration 16 = msgshot.go (shotFaceCache/shotSmallFaceCache), then translatebar.go + profilemusic.go
- owner-waiting: re-enable Pages + cut v0.10.4 (release.yml needs Actions; re-enabled in 333 — if the owner disabled it deliberately, say so and it flips back); R9 web-vault decision; real-account sign-ins; first non-prerelease
- last-gate: quick GREEN ×2 (4/4 runner contracts, js leg, full gui suite incl. R25/R26 tests); gofmt trap rule in HOT — always gofmt -w with devroot.env after Edit-tool writes

## Session 335 — wipe #4 boot, instantview.go: R25 + R26 (2026-10-31)

- Boot: repo clone gone (wipe #4) — re-cloned via one-shot token header;
  toolchain/mod-cache dir SURVIVED; devroot-setup + devroot.env rebuilt the
  sysroot; cold gui build under -p=1 needed two passes; env.sh recipe URL
  realigned to go1.27.1 (one patch behind devroot-setup — two toolchains
  sharing one GOCACHE poison it; doc fix in-repo). Scanner v3 script was
  outside the repo and is gone — its queue lives on in MAP.
- **R24 proof closed**: 41189550503 (cf60ce4d) = SUCCESS at job AND step
  level (all 5 jobs; race leg with the R18/R23/R24 gui pins green).
- **Iteration 15: instantview.go (1,738 lines, read in full) — R25 + R26
  fixed, rest CLEAN** (section in MAP):
  - R25 (the carried watch item, CONFIRMED): ivDocDone latched IV photos
    on first failure — marked done before the download, silent error
    returns, no clear-path; one network blip = permanent thumbnail or
    full-size blank box until restart. Now an in-flight claim
    (ivPhotoClaim/ivPhotoRelease, ivDocMu) held across the whole
    download→read→decode→store chain (decodeImageAsync inlined — a
    two-goroutine split would release mid-decode and re-download);
    success memoized by mediaImgs, failure retries on the next natural
    frame WITHOUT invalidating (an instantly-failing fetch cannot spin).
    RED: TestIVPhotoClaimLifecycle (compile seam) + TestIVPhotoClaimGuarded
    (2000× hammer both sides) + TestIVPhotoRetryAfterFailure driving the
    REAL wiring via bare App + zero Engine (getAccount miss errors fast —
    new harness pattern, noted in HOT). cbc32ef0.
  - R26 (found by derivation during the read): ivOpenRelated's landing
    guard `!cur.loading` is a flag, not a generation — back-during-fetch
    + re-navigate rearms it and the straggler fetch pushes an unopened
    page onto the back stack. ivState.gen (a.mu) bumped by navigate/back;
    openInstantView switched to pointer identity; landing extracted to
    ivLandRelated (stale = replaced OR gen-mismatch → dropped whole).
    RED: TestIVLandRelatedStaleGeneration + TestIVBackBumpsGeneration.
    f2fb580c.
  - Cross-window lens closed: iv| MsgIDs collide across windows, but
    frameMu is PACKAGE-level (app.go:25) so linkTags stays serialized —
    richtext's verdict holds via frameMu, not key-uniqueness.
  - Gate quick GREEN twice; gofmt trap found and documented (Edit tool
    writes spaces; gofmt -w needs devroot.env or it silently no-ops via
    && chain) — cost one gate cycle, rule in HOT.
- verify.yml race-leg filter extended with TestIVPhotoClaimGuarded
  (bf9ea2bf) and **41205692894 dispatched — READ ITS RESULT next session**;
  local -race on gui still OOMs on gotd (machine truth unchanged).
- Queue: msgshot.go next, then translatebar.go + profilemusic.go.

## Session 334 — CI proofs closed, separate.go clean, ranking queue (2026-10-31)

- STATE queued both verify reads: **41184046305 (2e606d58) R20+R21 native
  proof = SUCCESS, 41184562534 (a8880414) R22 proof = SUCCESS** — verified at
  job AND step level (all 5 jobs green; the Nix gate's 7/8 steps is the
  tag-only version check, correctly skipped on main pushes — not an anomaly).
  CI backlog closed; HOT pruned to the durable lesson only (check
  `actions/permissions` first when runs sit queued).
- **Iteration 8: separate.go (359 lines, read in full) — VERDICT CLEAN.** The
  multi-window core that kept producing the R14/R18/R19/R22 bug family is the
  best-defended file in gui:
  - Registry (sepWins/mainRef) fully sepMu-guarded; lock order uniformly
    sepMu→a.mu — openChat VERIFIED to release a.mu before the retarget
    (state.go:1400-1426). No inversion exists.
  - Hop discipline verified field-by-field: every cross-goroutine access of
    a.selected/a.msgFor/a.lock is under a.mu (onMessageEvent, onDownload*
    lock at entry, onUserStatus, refreshMessages, loadHdrPresence,
    topicScopeFor); the unlocked reads at separate.go:235/245 are same-loop
    (all writers GUI-loop on the owning App — traced every one).
  - Reopen guard: openSeparateWindow's `old.app != a` skip-close can never
    see same-App — only callers are sidebar.go:567 + chatmenu.go:256, and the
    chat menu mounts only on sidebar rows (sidebar.go:145, fired from
    a.sbVisible at chatmenu.go:198); separate windows render no sidebar.
  - Lock-bus boot race closed BY ORDER: Start subscribes (state.go:684)
    before the boot decision reads lockEngaged (720-729) — a broadcast in
    the gap lands as a hop and lockEngaged still boots the window locked.
- **Iteration 9 + R23: rubberband.go (136 lines, read in full).** Top of the
  new ranking queue. The rubber-band gesture state (rubberOn/rubberStart/
  rubberCur) was package-level while the overlay renders in BOTH window
  branches (messageList ← layoutChatView ← layoutMain/separateChatView) and
  f.selOn is per-App: window B's frame while not selecting KILLED window A's
  mid-drag gesture (selOn early-exit); both selecting → B painted A's
  phantom rect. No data race only because frameMu serializes Root() frames
  — semantic bleed remained. Fix = R19 pattern: state moved to App fields
  (frame-loop-only group, provenance comment), rubberTag stays package-level
  (immutable). RED compile-seam → TestRubberBandGestureIsPerWindow drives
  the REAL overlay via input.Router with live pointer events across two
  App instances (press → other-window frames → drag tracks pane coords →
  release selects exactly the hit rows). Full gui suite green (js leg);
  gate quick GREEN (4/4 runner contracts). Native proof → verify.yml
  dispatch this session. Two Gio harness lessons recorded in MAP:
  pointer.Drag is not a queueable kind (Move-while-pressed synthesizes
  Drag delivery); pane-coord boundaries make edge-adjacent presses miss.
- **Iteration 10: menu.go (936 lines, read in full) — VERDICT CLEAN.** All
  menu button pools already per-App on a.wid (growClickables; line 61's
  `var ()` is the vestigial empty block from that migration). openMenu's
  four async lookups all follow engine-call-outside-lock + guarded locked
  write (stale results discarded); menuActionsFor's 40+ actions all
  copy-capture + goroutine + toast; R18's caller unlocked; R20's Resend
  present; pane routing all per-App GUI-loop state. Three P3 polish notes
  in MAP: misnamed …Locked() helpers that TAKE the lock (deadlock trap if
  the convention is followed against them), a.fwdSel unlocked-vs-locked
  sibling inconsistency (all accessors GUI-loop — no race), and the
  forward goroutine reading frozen widget state from inside `go`.
- **Scanner v3 (go/ast, exact)** — `/home/z/my-project/scripts/pkgvar_scan_v3/`.
  Regex failed twice (v1 missed grouped var blocks; v2's `var ()` open-
  never-closed let struct fields leak in — menu.go's label/run were false
  positives). v3 uses go/parser + AssignStmt LHS root-unwrapping. Queue +
  the frameMu lens (layout-only package state cannot race; residual shapes
  = R23 semantic bleed / R22 outside-layout map writes) live in MAP.
- **Iteration 11: webpage.go (296 lines, read in full) — VERDICT CLEAN.**
  The exact-map scan's top suspect was defended: webPhotoDone/Failed and
  linkPreview are all mutex-guarded on every access; pools per-App with a
  512-cap; fail-pin is documented intent. Two P4 notes in MAP:
  webPhotoFailed is dead state (shadowed by done at its only read), and
  parseWebPage re-parses ContentRaw every frame (measure before touching).
- **Iteration 12 + R24: suggestionbar.go (301 lines, read in full).**
  #2 on the v3 queue, and the read found the missing guard: suggStates/
  suggFetching/suggDismissed were package maps with NO mutex while the
  fetch goroutine (delete from suggFetching + write suggStates on
  completion) raced the GUI loop's EVERY-FRAME reads (ensureSuggestionState
  runs per frame from the sidebar bar). Fatal concurrent-map class, ONE
  window + one slow fetch, reachable at every boot + hourly TTL refresh;
  frameMu irrelevant (goroutine is not a frame). R22's crash class but
  easier to hit. Fixed with six suggMu-guarded helpers (immutable-after-
  build publish; inner dismissed maps GUI-loop-only, documented). RED
  compile-seam: TestSuggestionMapsAreGuarded (all six helpers undefined
  pre-fix) hammers both sides through the helpers; deterministic-safe on
  js, and **the verify.yml race leg was extended to run the gui
  concurrency pins under -race** (filtered: R18/R23/R24 tests; the js leg
  has no race detector, native CI is the proof). Full gui suite green;
  gate quick GREEN (4/4 contracts). P4 noted: dead method
  suggestionState.dismiss (zero callers); suggBar/CloseBtn package
  clickables are sidebar-only (P3 fold-in family).
- **Iteration 14: richtext.go (444 lines, read in full) — VERDICT CLEAN.**
  linkTags is a package map with no mutex but ALL access is layout-only
  (flowRich) — frameMu serializes; and MsgID keys never collide across
  windows (one window per chat — the hover argument). P4: unbounded map +
  per-frame delete/rebuild churn (512-cap fold-in when touched). P3:
  a.spoilerRevealed unlocked (GUI-loop-only, fwdSel family).
- **Iteration 13: cornerreply.go (147) + cornerreaction.go (285), read in
  full — BOTH CLEAN.** cornerreply's package hover state is semantically
  correct shared (one cursor → one window's events at a time; Leave clears
  the slot; different chats never collide on MsgID; hoverMu belt-and-
  suspenders). cornerreaction's fav maps are favMu-guarded on every access
  with the fetch goroutine publishing via the locked setter. P4: favAttempted
  fail-pin (no retry this session; comment overpromises). Scanner
  calibration: both v3-flagged files were already defended — the remaining
  chat-surface queue skews guarded.
- **ivDocDone watch item** (instantview.go:1096-1110, verified by complete
  grep — 3 usage sites total, no clear-path anywhere): one-shot mark happens
  BEFORE the download and the error path returns silently → a transient
  DownloadIVPhoto failure permanently pins that photo to its thumbnail until
  restart; map also unbounded. Carried in MAP; the instantview iteration
  confirms real-world reachability before any R-number.
- Docs+code session: R23 (rubberband gesture state → App fields) and R24
  (suggestion maps → suggMu-guarded helpers + CI gui race leg) landed;
  iterations 8/10/11 mapped clean; BUGS/MAP/HOT/WORKLOG updated. Full gui
  suite green under the js leg; gate quick GREEN on both fixes. Pushed per
  §1.14; native + race proofs dispatched to verify.yml.

## Session 333 — wipe #3, CI zombie dispatches, R18+R19 (2026-10-31)

- Opened on a fully-wiped VM (wipe #3): tree + toolchain + mod cache gone.
  Recovery per the env.sh header, ~5 min: clone (origin at b58d7a10), curl
  go 1.27.0, `go mod download` (1.3G). Zero progress loss — the §1.14
  recipe proven a third time; HOT.md updated.
- STATE queued "read the starved verify runs": all three still `queued` with
  ZERO in-progress runs and no self-hosted runners. Not starvation —
  `actions/permissions` returned **enabled:false**: Actions was disabled at
  the repo level sometime after the 07:16 dispatch. Decision (logged here,
  no confirmation per the standing directive): re-enabled via API — the
  workflow is dispatch-only and free on a public repo, the queued runs are
  needed for §9.7 native proofs, and a disabled Actions also blocks the
  OWNER's own queued item (release.yml for v0.10.4). One PUT, reversible.
- The three old dispatches turned out to be **zombie runs**: accepted while
  Actions was disabled, never enqueued; cancel 409s ("has not been queued
  yet"), delete 403s. Permanent queue litter — documented, ignored. Fresh
  dispatch on re-enable: **41181306179 = SUCCESS on b58d7a102** — the
  native proof for R15+R14+R16+R17, CI backlog CLOSED.
- Main work: **chunk 3 iteration 6 — mediaview.go mapped** (1,041 lines,
  read in full; MAP.md entry). Two bugs fell out, both fixed same session:
  - **R18 — the viewer Share button DEADLOCKED the window**: viewerShare
    held a.mu across openForward, which locks a.mu itself (select.go:159) —
    same-goroutine double-Lock, non-reentrant mutex, the R14/CI-41174703134
    shape but on a live user path (reachable in every window; the other two
    openForward callers were already correct). Fix: openForward outside the
    lock. RED-first with a WATCHDOG (TestViewerShareCompletes, goroutine +
    5 s deadline) so the failing shape fails fast instead of hanging the
    runner — the R15 lesson applied. RED confirmed at runtime (5.01 s), then
    GREEN with behavior assertions.
  - **R19 — viewer box/scaled bookkeeping was package-level** (mvBoxW/H,
    mvScaledW/H): layoutMediaView renders in BOTH Root branches, so two
    windows with viewers open race on the four vars and one window's pan
    clamp reads the other's box (B-47 class; the gesture fields were already
    per-App — the box bookkeeping never got converted). Fix: App fields +
    clamp methods. Compile-seam RED test
    (TestViewerBoxBookkeepingIsPerWindow), GREEN after.
- Verification: full gui suite green through the fixed runner; audio leg
  green; gate quick GREEN (runner self-test 3/3 contracts inside the gate);
  fresh verify.yml dispatched on the fix commit — **41182590400** (4883033a)
  = native + race-leg proof for R18/R19, read next session.
- Same session, later turns — the law-22/23 watch item ("failed send loses
  the typed text") was RESOLVED, and its resolution produced two more bugs:
  - Premise WRONG: eng.SendMessage is the queued path (engine/pending.go) —
    the text lives on in a visible pending message; on permanent failure
    FailMessage marks it MsgStatusFailed. tdesktop's model exactly.
  - **R20 — the tick mapping had drifted from the status consts**: Sending(1)
    drew a check, the read accent landed on Delivered(3), and Failed(5) fell
    to the default branch = the DELIVERED double-check — a lost message
    looked delivered, and RetryPending had NO gui wiring. Fixed: pure
    statusTickKind mapping (TestStatusTickKind, compile-seam RED) + new
    alertMark glyph + Resend menu action (TestActionsFor subtests, RED) +
    a failure toast on EventMsgStatus/MsgStatusFailed.
  - **R21 — wasm-test-runner.sh dropped every go-test flag** (found hunting
    verbose evidence: a "single-test" run took the same ~1.6s as the full
    suite): the shell passed only the binary to node, and the driver set
    go.argv to just that. Filtered evidence runs were silently full-suite.
    Fixed both layers + harness contract #4 (flagfwd fixture, RED on the
    old runner). TRUE filtered runs now visibly faster with per-test PASS
    lines — evidence precision restored to the sole verdict source.
- Same session, final stretch — **chunk 3 iteration 7 — profile.go mapped**
  (780 lines, read in full; MAP.md entry). DM profile / member list /
  shared-media tabs surface; engine calls outside locks throughout;
  streamer masking honored. Produced **R22**: panelSwitches/panelSynced
  were PACKAGE maps while the info panel renders in EVERY window (both
  Root branches) — two open panels = two GUI goroutines in one Go map =
  FATAL runtime panic (worse failure mode than R14/R19's race). Fixed:
  pool moved to a.wid (panelSwitch method, lazy-init), compile-seam RED
  test pins per-window pool + one-shot bookkeeping. Also verified + filed
  a P3 watch item: the panel's mute toggle NEVER re-syncs after its
  one-shot (no path clears panelSynced — even panel reopen doesn't), so a
  mute changed from the sidebar stays stale on the panel indefinitely;
  fix shape noted in MAP (clear the key on openPanel).
- Process note: the sandbox editing tool space-indented whole files on two
  edits (raw diff 8.5k lines); caught via `git diff --stat` vs
  `--ignore-all-space`, normalized with `gofmt -w` before commit. Final
  commit diff is semantic-only (144 insertions).

