# WORKLOG.md — the session journal

One entry per work session, newest first. This is the resume-from-zero
mechanism: the last entry tells the next agent what happened and what is
next. (The pre-2026-10 history was deleted by the owner on 2026-10-30 —
it lives in git history if ever needed.)

## Session 324 — web hardening pass (2026-10-30/31, in progress)

Owner instruction: run the phased production-hardening prompt **against
the web target**; free choice of test interface ("do whatever you want
for test interface"); **use puppeteer**; reset/update AGENTS.md (the
owner then deleted AGENTS/WORKLOG/BUGS mid-session — this file and the
fresh AGENTS.md/BUGS.md are the reset). Full phase log lives in
`research/web_hardening_2026-10.md`.

- **Phase 0 (recon, read-only):** web-surface map, platform truth table
  (only github/matrix/bale can connect from a browser), 8 critical
  journeys, 10 risk zones (R1 two-tab vault clobber … R10) — written to
  the research doc. Measured: wasm = 88.5 MB, ~20 MB gz transfer on
  gh-pages.
- **Phase 1 (safety net):** puppeteer suite under `scripts/web-test/`
  (12 shell tests on the EXACT bytes CI ships, extracted from release.yml;
  6 real-app tests incl. vault decryption for exact account counts).
  Also repaired the standing gates: aacaud ffmpeg pins per-major-version
  (local ffmpeg 7 false-failed the provenance check), gui js/wasm test
  leg (was `undefined: waitFor` — broken since stream_guards_test.go
  landed, invisible to CI), js skips for filesystem-reading tests.
  Everything green; pushed (e7cb54a6..bb799595 window).
- **Phase 2 (correctness, one bug per iteration, red-first):**
  - F-87 (R1, data loss): two tabs clobbered the web vault — fixed with
    flush-time cross-instance merge (js hook re-reads+merges the
    persisted vault; native no-op behind the lock file). Unit tests +
    b6 E2E flipped red→green.
  - R2/R3 (audio/webaudio_js mic failure-path leaks, unused micRate),
    R4 (web picker offers TCP-impossible backends), R5 (no post-boot
    crash surface in the shell), R6 (observer accumulation) — queued.

Next: finish Phase 2 fixes, then Phases 3-7 (prune/refactor → perf
baseline+measure → UI/UX polish → security → full verification incl. the
live deployed-site tier), one final WORKLOG update + changelog by phase.
