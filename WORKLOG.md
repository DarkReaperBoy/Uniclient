# WORKLOG.md — the session journal

Top: the **STATE block** — rewritten every session, the resume pointer for the
next agent. Below: one entry per work session, newest first. This is the
resume-from-zero mechanism. (The pre-2026-10 history was deleted by the owner
on 2026-10-30 — it lives in git history if ever needed.)

## STATE

- cycle: 2 | phase: P0 recon (chunk 3, per-file gui surfaces)
- item: iteration 34 DONE — stories.go (960→1,034 lines, read in full — the unscanned queue by size #5); **R53** (storyViewerState frame-carried as a POINTER, every writer mutated it in place: the fetch tail, storyAdvance, storyReact's optimistic flip + background revert THROUGH the frame-shared items backing array, the react/reply strip toggles — plus the revert stomp: a failed old react overwriting a newer successful one; → updateStoryView copy-on-write installer + flipStoryReaction deep-item copy + extracted storyReactDone with a from-match guard) + **R54** (the fetch tail was identity-guarded only — a slow fetch for chat X landed stale data over a reopened X; → storyViewGen session key, open/close bump it) + **R55** (the story reply draft leaked across viewer sessions — cleared on close now; every close caller verified GUI-loop). stories_r53_test.go ×7, TRUE tool-proven RED (the snapshot-immutability pin fired the detector against the stage-1 in-place build). Rows in BUGS, section in MAP
- next: the unscanned gui files by size — location.go (941), savedsublists.go (883), topics.go (738), statsview.go (697), h264player.go (688), folders.go (688), sponsored.go (641), …; CI: R32-R52 ALL CLOSED at job+step level (runs in HOT); R53-R55 verify.yml dispatched this session — run ID in HOT/entry below
- owner-waiting: re-enable Pages + cut v0.10.4 (release.yml needs Actions; re-enabled in 333 — if the owner disabled it deliberately, say so and it flips back); R9 web-vault decision; real-account sign-ins; first non-prerelease
- last-gate: local full GREEN — gofmt clean, vet clean, full gui suite **925 PASS / 0 FAIL / 3 SKIP** (environmental; +7 story pins on top of 918), new pins clean under LOCAL -race **-count=20**; R49/R50 CI 41251708582 + R51/R52 CI 41252480112 verified SUCCESS at job+step level this session; R53-R55 CI in flight


## Session 341 — wipe #8 boot; CI closures; iteration 34: stories.go = R53 + R54 + R55 (2026-11-01)

- Boot after wipe #8 (repo + toolchain gone; upload token survived):
  clone → devroot-setup → mod refill (~10 min), proven recipe. The
  handoff summary was a WHOLE PHASE stale (claimed chunk 2 iteration 2;
  actual chunk 3 iteration 33) — the WORKLOG STATE block was the resume
  truth, a FOURTH confirmation (HOT updated).
- Verified the two in-flight CI runs at job AND step level: R49/R50
  **41251708582 (0319f118)** and R51/R52 **41252480112 (9d1d7269)** —
  all 5 jobs each, all steps success, Race green. No CI pending at
  iteration start.
- Iteration 34 — stories.go (the Stories surface, parity slice 104 +
  164/215): **R53** — storyViewerState is frame-carried as a POINTER and
  every writer mutated it in place: the fetch tail (loading/err/items
  under a.mu, which does not stop the lock-free layout reads through
  f.storyView), storyAdvance (cur), storyReact's optimistic flip and its
  background revert (the latter writing it.SentReaction through a
  pointer INTO the frame-shared items backing array — R34 + R38 in one
  shape), and the reactOpen/replyOn strip toggles (GUI-loop writes onto
  the frozen snapshot; one site even took a.mu uselessly). The revert
  also lacked a from-match guard: a failed older react stomped a newer
  successful one. **R54** — the fetch tail's guard was identity-only
  (chatID+accountID): a slow fetch for chat X could land stale data over
  a close+reopen of X, permanently (no refetch fires). **R55** — the
  reply draft (a.wid.storyReplyEd) survived closes: arming reply on any
  later story resurrected the old half-written text — a cross-conversation
  draft leak. Fixes: updateStoryView CoW installer (ALL writers
  converted), flipStoryReaction with deep item copy + from-match,
  storyViewGen session key (open/close bump; extracted storyFetchDone
  installs only while its gen is current), closeStoryViewer clears the
  editor (all callers verified GUI-loop), the strip's pointless
  `go openStoryViewer` dropped, the duplicated `own` check deduped into
  storyViewerOwn.
- Evidence: **TRUE RED** — stage 1 (extraction-only build, the original
  in-place tail body) made TestStoryViewerSnapshotImmutableUnderTails
  FAIL under LOCAL -race ("race detected during execution of test" +
  frozen head mutated: items=1 loading=false); stage 2 (CoW) clean.
  stories_r53_test.go ×7 (installer contract incl. 4-writer hammer,
  snapshot immutability, fetch-tail session guard, react flip contract
  incl. deep-copy + no-stomp, revert-tail guard, advance CoW + past-end
  close, reply-draft lifecycle) clean under -race -count=20. Full gui
  suite **925 PASS / 0 FAIL / 3 SKIP** (environmental); gofmt + vet
  clean. CI race-leg extended with the ×7 pins; verify.yml dispatched —
  run ID backfilled below/HOT.
- Doc hygiene: WORKLOG pruned to <300 lines (sessions 333-335 dropped —
  their bugs live in BUGS.md Fixed + git history).

## Session 340 — iterations 32-33: callsbox.go = R49 + R50; poll.go = R51 + R52; R46/R47/R48 CI closed (2026-11-01)

- Verified the pending CI at job AND step level: R46 **41245678978
  (d8b4ce01)** and R47/R48 **41246248716 (12165b24)** — all 5 jobs
  each SUCCESS, Race steps green.
- Iteration 32 — callsbox.go (the Calls box, tdesktop parity slice
  154): **R49** (load-tail append + in-place sort into the
  frame-shared backing array — armed by the delete shift's spare
  capacity → fresh-slice merge in applyCallsBoxPage;
  scripts/r49_red_proof.go prints the pre-fix array reuse) + **R50**
  (no session guard on the tail — cross-account/reopen/clear stomps,
  stale busy resets, the clear flow's parallel reload, and the
  failed-clear busy deadlock → callsBoxGen + applyCallsBoxPage guard
  + chained reload + callsBoxClearFailed). ×5 pins in
  callsbox_r49_test.go, local -race clean, suite 914 PASS / 0 FAIL /
  3 SKIP (environmental). CI race-leg extended (r49_ci_filter.py).
- Env note (also in HOT): Bash shells reset between tool calls —
  re-source `. ./devroot.env && unset GOROOT && export
  GOMODCACHE=/home/z/my-project/toolchain/mod
  GOCACHE=/home/z/my-project/toolchain/gocache GOFLAGS=-p=1
  GOMEMLIMIT=3GiB GOGC=20` in EVERY call; scripts/env.sh alone lacks
  PKG_CONFIG_PATH (gui CGO builds fail on xkbcommon/wayland).
- Iteration 33 — poll.go (the polls surface, AyuGram parity §4 + slice
  124): **R51** (five in-place writers on the frame-carried *pollDlgState
  incl. the background send tail + the unguarded reopen stomp →
  updatePollDlg CoW + pollDlgGen + pollSendDone) + **R52** (send
  goroutine read a.wid switch values → captured on the GUI loop; RED
  proven by temporarily reverting the capture — the detector FAILS the
  pin, restored it is clean). ×4 pins in poll_r51_test.go, local -race
  clean, suite 918 PASS / 0 FAIL / 3 SKIP (environmental). CI race-leg
  extended. Line-index python edits (scripts/r51_poll_fix.py) — deep
  layout nesting makes tab-exact anchors fragile.

## Session 339 — iterations 30-31: media.go CLEAN; giveaways.go = R47 + R48 (2026-11-01)

- Iteration 30 — media.go (1,186 lines): CLEAN (no frame-carried struct;
  mediaImgCache self-locked; mediaTickerOn a.mu both sides; P4 watch:
  per-bubble MediaState getters). Section in MAP.
- Iteration 31 — giveaways.go: **R47** (~17 writer sites incl. the
  UNLOCKED dateIdx clamp on the frozen frame pointer — the send-dead
  bug; create-tail guard strengthened) + **R48** (sync RPC on the GUI
  loop → goroutine). ×6 pins, LOCAL -race clean, suite 909/909.

## Session 339 — iteration 29: instantview.go = R46 — THE R34 WATCH CLOSED (2026-11-01)

- **R46** (the systemic watch's last entry): the IV reader's state was
  mutated in place by the open load tail and ivLandRelated (pointer-
  identity retirement doesn't stop the frameMu reads) plus the two
  GUI-loop heads (lost-click class). updateIV copy-on-write; staleness =
  openID + gen (identity breaks under copy-on-write; gen alone can't
  retire a reopen straggler); pushHistory builds fresh slices (R38).
  detailsOpen/slideIdx stay shared GUI-loop-only maps; docBusy keeps
  ivDocMu (re-verified). R26 pins updated to head-observation.
- GREEN: instantview_r46_test.go ×5, LOCAL -race clean, full gui suite
  **903/903**. CI race-leg extended. Python heredoc edits
  (scripts/r46_instantview_fix.py).

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
