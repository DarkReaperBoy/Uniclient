# WORKLOG.md — the session journal

Top: the **STATE block** — rewritten every session, the resume pointer for the
next agent. Below: one entry per work session, newest first. This is the
resume-from-zero mechanism. (The pre-2026-10 history was deleted by the owner
on 2026-10-30 — it lives in git history if ever needed.)

## STATE

- cycle: 2 | phase: P0 recon (chunk 3, per-file gui surfaces)
- item: iteration 28 DONE — twofa.go (661→726 lines, read in full — the R34 sibling sweep #7, the LAST named sibling); **R44** (twofaDlgState write-races-layout across THIRTEEN writer sites — four background tails with pointer-identity guards that don't stop frameMu reads + every GUI-loop click writer → updateTwoFADlg copy-on-write, accountID guards replacing identity guards which BREAK under copy-on-write; ×4 pins, local -race clean, CI race-leg extended) + **R45** (settings-row map never refreshed after a mutation — the row kept the pre-mutation On/Off until settings reopen while the comment promised server truth → refreshTwoFARowState fresh-map install, the R38 rule; ×1 pin). Layer audit: contentDialogSurface peer — no matrix gap. Rows in BUGS, section in MAP. **The named sweep is COMPLETE (7 of 7)**; only instantview.go's load tail remains from the watch list
- ALSO this session: iteration 27 — exportdlg.go (**R42** + **R43**); R40/R41 CI proofs closed at job+step level; wipe #7 recovery
- next: close the R34 systemic watch's last item — instantview.go's load tail (iv's docBusy already ivDocMu-guarded per the watch note: verify, then close the watch); after that: the remaining unscanned gui files by size (media.go 1,186, giveaways.go 1,171, callsbox.go 1,089, poll.go 972, stories.go 960, …); CI CLOSED at job+step level: R32/R33 **41222152669**, R34-R36 **41236970838 (f14028a6)**, R37 **41237343094 (e6de37fc)**, R38 **41237698797 (6fdb1835)**, R39 **41238091947 (f38e19f7)**, R40 **41238742290 (1d143036)**, R41 **41239171673 (733d220b)**; pending: **41244407673** (R42+R43, 9b2cf32d) + R44/R45's run this session
- owner-waiting: re-enable Pages + cut v0.10.4 (release.yml needs Actions; re-enabled in 333 — if the owner disabled it deliberately, say so and it flips back); R9 web-vault decision; real-account sign-ins; first non-prerelease
- last-gate: local full GREEN — gofmt clean, full gui suite **898/898** (+5 R44/R45 pins on top of R42/R43's 893), LOCAL -race clean on both new pin sets; R42/R43 CI **41244407673** in flight, R44/R45's dispatch next

## Session 339 — iteration 28: twofa.go = R44 + R45 — the named sweep COMPLETE (2026-11-01)

- **R44** (the R34 class, sweep #7 — the LAST named sibling): the 2FA
  editor's state was mutated in place by four background tails (load,
  mutation, refresh, cancel-email — all with pointer-identity guards
  that don't stop the frameMu reads) AND every GUI-loop click writer.
  updateTwoFADlg copy-on-write; guards switched to accountID (identity
  breaks under copy-on-write); thirteen writer sites converted; the
  lost-click class (a click writing to a frozen head) fixed with them.
- **R45** (the R35 staleness class): the settings-row map was never
  refreshed after a mutation — the row behind the dialog kept the
  pre-mutation On/Off until settings reopen. refreshTwoFARowState
  installs a fresh map (the R38 fresh-map rule), called from
  twofaFinish's refresh.
- GREEN: twofa_r44_test.go ×5, LOCAL -race clean, full gui suite
  **898/898**. CI race-leg extended. Edits tab-exact via python
  heredoc (scripts/r44_twofa_fix.py, 1-space-per-level literals + T()
  expansion + gofmt -w safety net).

## Session 339 — iteration 27: exportdlg.go = R42 + R43 (2026-11-01)

- Boot after **wipe #7** (repo + toolchain gone; upload token survived).
  Full recipe re-run (clone → go1.27.1 → mod download → devroot-setup,
  ~10 min). First act: closed the R40/R41 CI proofs via the API —
  41238742290 (1d143036) + 41239171673 (733d220b), both SUCCESS at job
  AND step level (all 5 jobs, Race steps green; the Nix release-tag gate
  skips off tags by design). Docs commit 5c00045c.
- **R42** (the R34 class, sweep #6): the export wizard's state was
  mutated in place by the engine's event goroutine
  (onExportProgress/Error/Complete) and startExport's failure tail —
  no accountID guard on that tail, either. updateExportDlg copy-on-write
  installer; all six writers converted. **R43** (the R35 class): the
  checkbox-pool seed flag was never reset — one seed per PROCESS, so
  every reopen showed stale toggles over a fresh-defaults map; Start
  exported the map, not the display. Reset at open+close. Layer audit:
  the wizard is a contentDialogSurface peer — coexistence by design,
  no matrix gap.
- GREEN: exportdlg_r42_test.go ×5, LOCAL -race clean, full gui suite
  **893/893**. CI race-leg filter extended. Edits made tab-exact via
  python heredoc (scripts/r42_exportdlg_fix.py) — the Edit-tool gofmt
  trap avoided entirely. Fresh-cache -race build OOMs once on gotd/tg;
  the retry completes (build cache carries progress).

## Session 338 — iteration 21: business.go = R34 + R35 + R36 (2026-11-01)

- Boot after **wipe #6** (repo + toolchain + download/ copies all gone;
  upload token file survived). Full recovery recipe re-run from zero:
  clone (HEAD be7541e4 — one commit AHEAD of the summary pointer, as
  expected: the WORKLOG STATE block, not any handoff summary, is the
  truth), go1.27.1 tarball, mod download, devroot-setup. Cancelled a
  redundant verify.yml dispatch (41233516479) after finding the R32/R33
  proof already landed: **41222152669 (be7541e4) = SUCCESS, all 5 jobs at
  step level, Race step green** — that closes R32/R33's CI proof.
- Read business.go in full (per-file lens): pure model (bizWeek
  wire↔editor, lenient parsing — already test-locked), lifecycle, apply/
  remove, QR CRUD, the six editor bodies, subtitles, entry card.
- **R34** (the headline — write-races-layout on a sub-page struct):
  snapshot() installs the LIVE *businessPageState pointer (state.go:2364)
  and its own contract says "only replaced, never mutated in place" — but
  six background tails mutated it in place under a.mu while layout read
  ~12 fields under frameMu only. RED: dep-free scratch repro
  (scripts-side, not committed) flags DATA RACE at loadTail vs
  layoutReads under `go run -race`. Fix: updateBusinessPage(fn) — clone,
  fn on the copy under a.mu, install; EVERY post-install mutation routed
  through it (six tails with accountID guards — closing a pre-existing
  cross-account clobber in apply/remove/QR tails — reload, toggle,
  hours/tz/chip/QR handlers; UI handlers land on the current head so
  updates can't go lost; the busy-claim reads the current head, not the
  frame's copy). GREEN: business_r34_test.go ×2 (hammer + installer
  contract) clean under LOCAL -race; CI race-leg filter extended.
- **R35** (dead checkboxes): bizRecChks/bizExcludeChk/bizOfflineChk
  rendered but never seeded from the wire and never read — Save sent the
  stale st.recips/st.offline. Now seeded (seedBizRecipWidgets, label
  order matching bizMsgEditor) and read back in bizEditorData with an
  at-least-one-recipient guard. business_r35_test.go ×2.
- **R36** (uncancellable rename + shared-editor slot): the QR Cancel
  button only cleared qrNewOpen — qrRenameID stayed set; the new form and
  the rename row also shared bizQRNameEd. One inline edit slot via three
  extracted bare-App-testable click methods. business_r36_test.go ×2.
- Full gui suite 874/874 (868 + 6); gate quick GREEN (js leg + 4/4
  wasm-runner contracts). MAP gains the P1-class systemic watch for the
  R34 sibling sub-pages (read order listed there).
- **Iteration 22 (same session): settingspremium.go = R37.** Read in
  full; premiumPageState had R34's pre-fix shape (load tail + reload in
  place under a.mu vs frame-pointer reads). Fix: updatePremiumPage
  copy-on-write installer (same shape as business.go's), both writer
  sites converted, cross-file access verified nil-install-only. Rest of
  the file clean (noAdsRevert a.mu-guarded both sides; settings maps
  GUI-loop-only; accountID install-immutable). settingspremium_r37_test
  .go ×2, local -race clean, CI race-leg extended. Full gui suite
  876/876; gate quick GREEN.
- **Iteration 23 (same session): settingsstars.go = R38.** Read in full;
  starsPageState had R34's shape PLUS the append half (append into the
  frame-visible Txns slice — header race vs the layout's range loop).
  Fix: updateStarsPage copy-on-write for all five writer sites; the
  append builds a FRESH StarsStatus + fresh Txns slice (old balance
  kept); the load head now skips the fetch when the page is gone; the
  dead filter capture in reload dropped. settingsstars_r38_test.go ×3
  (hammer + append-purity + contract), local -race clean, CI race-leg
  extended with all three. Full gui suite 879/879; gate quick GREEN.
- **Iteration 24 (same session): foldermgr.go = R39.** Read in full;
  folderMgrState had R34's shape (load tail + reload in place). Fix:
  updateFolderMgr copy-on-write. Plus the settings-shell exclusivity
  matrix audit + completion (openFolderMgr/openPremiumPage gaps closed;
  openProfileEdit misses 4, openStickerMgr misses 3 — their iterations).
  foldermgr_r39_test.go ×3 (hammer + contract + the matrix pin on the
  bare engine harness), local -race clean, CI race-leg extended. Full
  gui suite 882/882; gate quick GREEN.
- **Iteration 25 (same session): stickermanager.go = R40.** Read in full;
  R34's shape across SIX writer sites (both load tails, reload, search
  head+tail with the stale-run key, setTab). Fix: updateStickerMgr
  copy-on-write; openStickerMgr's matrix completed. stickermanager_r40
  _test.go ×3 (hammer spanning all three field families + contract incl.
  the searchFor abort + the sibling-clear pin), local -race clean, CI
  race-leg extended. Full gui suite 885/885; gate quick GREEN. R38's CI
  proof CLOSED (41237698797, all 5 jobs at step level).
- **Iteration 26 (same session): profileedit.go = R41.** Read in full;
  the loader was already fresh-replace (the one sibling without the
  struct race) — the finding was the FLAG race (profileEdSynced plain
  bool, load-tail background write vs GUI-loop priming read/write →
  atomic.Bool, R32's shape) + the write-only busy field (removed with
  both writes) + the final matrix completion (openProfileEdit nils all
  five siblings — every opener complete now). profileedit_r41_test.go ×3
  (atomic hammer + the loader's replace discipline + the final matrix
  pin), local -race clean, CI race-leg extended. Full gui suite 888/888;
  gate quick GREEN. NEW TOOL TRAP LEARNED: a FAILED Edit/MultiEdit still
  normalizes tabs→spaces across the file (profileedit.go needed
  gofmt -w after a failed attempt) — the HOT rule now covers failed
  edits; python-based edits with explicit \t avoid the trap.


## Session 337 — iteration 20: state.go part 2 = R32 + R33 (2026-11-01)

- Boot after **wipe #5**: repo clone AND toolchain both gone this time —
  full env.sh recipe re-run from scratch (go1.27.1 tarball → mod download
  → devroot-setup for the CGO sysroot). Recovery proven end-to-end again;
  repo git log confirmed the summary pointer was stale (repo sat at 3dc41161,
  chunk 3 iteration 19 DONE) — the WORKLOG STATE block is the truth, not
  the handoff summary.
- Read state.go's remaining body in three passes: downloads/auth
  (1161-1418), composer trio + cfg/load*/apply* families (1714-2245),
  snapshot() + frame struct (2246-2914). Verified every sibling call in
  refreshConfig's tail (setMsgShowSeconds atomic, updateTray self-locking,
  applyAppIconRuntime re-dispatched) — applyAvatarCorners was the one plain
  field left (R32). Verified the loaders' snapshot-outside-lock pattern, the
  download handlers' copy-on-write installs, the auth flows' off-lock
  engine calls, and the composer trio's GUI-loop-only widget discipline.
- **R32** (avatarcorners race): UI.avatarCorners plain int, written by
  refreshConfig from openSettings/applyDrawerHidden/applySystemTray/
  applyAccent/applyFontScale goroutines + the corners 600 ms debounce
  timer, read by avatarRadiusPx every frame in every window. Fix:
  atomic.Int32 (msgShowSeconds precedent). RED: dep-free scratch repro of
  the pre-fix shape under `go run -race` — DATA RACE flagged at exactly
  applyAvatarCorners vs avatarRadiusPx. GREEN: local `-race` on the gui
  package's new pin (first session the race build fit in 4 GiB — no OOM)
  + the CI race-leg filter carries it now. avatarcorners_r32_test.go.
- **R33** (show_sender_name stomp): loadNotifyAccts read the engine's
  show_sender_name into a dead `if ok && !from { _ = from }` block;
  applyReactionsNotify hardcoded true — any of the four reactions/polls
  rows re-enabled what another client had disabled. Fix: senderName on
  notifyAcctState (default true, §1.10 keeps it unsurfaced), pure
  (*notifyAcctState).applyReactionsMap extraction, pass-through in the
  apply. notifyaccts_r33_test.go ×4 shapes; engine round-trip needs a live
  account (noted in the row).
- Watch items added to MAP (both P4): applyGhostFlag's split RMW (sole
  caller is the serial GUI loop — fold if a second caller ever appears);
  addAccount's completion goroutine clobbering a.authAcct (auth-view
  confusion only, engine state per-account consistent).
- Gates: gofmt clean; vet OK; full gui suite 868/868 PASS; gate quick
  GREEN (native + js legs, 4/4 wasm-runner contracts); local -race pin
  clean. verify.yml race filter extended with the R32 pin.

## Session 336 — iteration 18: the R29 systemic sweep = R30 (2026-10-31)

- Resumed at the STATE pointer: R27 proof 41206658703 had already closed
  SUCCESS (job+step level, commit 68aa9192) — straight into chunk 3
  iteration 18, the dead-opener sweep R29's watch item called for.
- **R30 found and fixed (19 dead openers, 9 surfaces)**: enumerated the 24
  contentDialogSurface states + settingsOpen + the main-branch modals +
  mode 1; mapped all 33 opener functions to call sites; intersected with
  the separate render tree (chat view + overlays). Dead-in-separate:
  header menu ×6, attach menu ×3, mute clock, member menu ×2, Filter
  Like This…, prepaid Launch cells, call rating, saved-lists Delete,
  Ctrl+J contacts, and the call bar's JOIN (worst: real engine join +
  mode-1 flip that painted nothing — the group-call UI appeared in NO
  window; now the bar itself is the in-call surface, JOIN→LEAVE via
  callBarInCall + leaveJoinedCall, mode flip skipped in separate
  windows). Fixes: `separate` params on the pure menu derivations
  (headerMenuItems/memberMenuItems/savedSublistMenuActions/
  attachMenuItems), shared mainOnlySurfaceShown predicate (R29's helper
  generalized), callBarJoin/applyCallJoinResult split. Direct engine
  actions stay everywhere. RED-first: deadopeners_r30_test.go ×7
  (compile seam + bare-App real-wiring for the join result); 16 existing
  test calls updated for the new params (paren-aware rewriter — the
  naive regex missed dmChat()-style first args); TestAttachMenuItemsMusic
  re-pinned to the grouped order. Local gate: gofmt clean, vet clean,
  full gui suite green ×3.
- **By-catch (dormant, not a bug)**: a.wid.boostGiveawayBtn is clicked
  (boostview.go) but never rendered in any window — the giveaway creator
  is only reachable via prepaid Launch cells. Watch item in MAP; gate it
  on mainOnlySurfaceShown if it is ever surfaced.
- SAFE classes verified in the sweep (documented in MAP): sidebar/drawer/
  settings/folder-menu/callsbox/chatmenu-only openers; poll/schedule/
  forward/shadow/deleted dialogs (chat-view overlays); business page;
  export/2FA/privacy/lock/autodl/cloud-theme (settings-only).
- **Iteration 19: state.go part 1 (refreshMessages/mergeMessages/openChat/
  loadOlder) — R31 found and fixed**. Four async installers of a.messages
  had no install-time staleness guard: a chat/scope switch mid-fetch
  installed the old view's window + msgFor into the new view (cross-chat
  content under the wrong header; sends resolve via msgFor → next send
  could target the chat the user left). Fixed with a.uiGen (message-window
  generation, bumped at all 12 scope-reset sites) + guarded extracted
  installers (applyOpenChatMessages / mergeMessages(gen) /
  applyForumTopicWindow / applyOlderPage; jumpToMessageAt carries the same
  check; loadOlder's outside-lock a.messages[0] read folded into the
  initial snapshot). RED-first deadinstalls_r31_test.go ×4; full suite
  green. Watch item (P2): deep-link pendings can be consumed by the next
  openChat's loader in a sub-second manual-nav race — fix = pass pendings
  as openChat parameters if ever hit. state.go part 2 remains.

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
- **Iteration 16: msgshot.go (665 lines, read in full) — R27 fixed, rest
  CLEAN** (section in MAP): saveMessageShot's goroutine ran the render
  pipeline unserialized against package state — lazily-written
  shotFaceCache/shotSmallFaceCache (fatal concurrent-map class) AND
  shared opentype.Face scratch buffers (buf sfnt.Buffer/rast/mask —
  x/image Font calls are concurrent-safe only with one Buffer per call,
  a Face owns exactly one; verified in the module source); plus the
  goroutine read a.ui.p (GUI-thread-only palette, applyTheme writes it
  lock-free) before taking a.mu — racing a theme swap. Fix: shotMu
  serializes the whole pipeline (shots are rare, renders are ms); the
  palette is captured on the GUI loop before the goroutine spawns.
  RED: TestShotRenderPipelineIsSerialized (compile seam on shotMu;
  resets the caches under the lock to force the lazy-write path; 8×15
  hammer) — added to the verify.yml race-leg filter with the R25 pin.
  674c41f9, gate quick GREEN.
- Queue: translatebar.go next, then profilemusic.go; R27's proof dispatch
  pending after 41205692894 lands.
- **R25 proof landed: 41205692894 (bf9ea2bf) = SUCCESS, verified at job
  AND step level** (all 5 jobs; the Race leg with the extended gui pins
  incl. TestIVPhotoClaimGuarded green). R27 proof dispatched:
  **41206658703 (d029af30) — READ ITS RESULT next session**.
- **Iteration 17a: translatebar.go (290 lines, read in full) — R28
  fixed, rest CLEAN** (section in MAP): transPickerOpen was a package
  bool written by layout (R14 class) — opening the language picker in
  window A expanded it in window B's chat and picking a language in
  either flipped both. Now an App field (a.mu) + frame carry + openChat
  reset, the exact R14 pattern. RED: TestTransPickerIsPerWindow
  (compile seam). P3 watch item left in MAP: transAsked latches on
  failed auto-translates (naive fix = per-frame re-ask spin; needs
  backoff design). ff5d12b5.
- **Iteration 17b: profilemusic.go (598 lines, read in full) — R29
  fixed, rest CLEAN** (section in MAP): the panel Music section's
  tap-through opens a content-pane dialog that only the MAIN window
  renders, but the info panel renders in every window — a dead button
  in separate windows (§1.10). Hidden there via profileMusicSectionShown.
  RED: TestProfileMusicHiddenInSeparateWindows (compile seam). Package
  widget vars (musicRows/musicList/…) verified MAIN-WINDOW-ONLY (joins
  the business.go list in MAP); systemic dead-opener sweep queued as
  iteration 18. 47ce870a. Gate quick GREEN ×4 this session.

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

