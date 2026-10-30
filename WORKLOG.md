# WORKLOG.md — the session journal

Top: the **STATE block** — rewritten every session, the resume pointer for the
next agent. Below: one entry per work session, newest first. This is the
resume-from-zero mechanism. (The pre-2026-10 history was deleted by the owner
on 2026-10-30 — it lives in git history if ever needed.)

## STATE

- cycle: 2 | phase: P0 (chunked recon of never-mapped surfaces; the web surface closed in cycle 1)
- item: BUGS.md R10 — matrix_groupcall GatheringCompletePromise callers on web
- next: R10 audit → P0 chunk 1 (cmd/uniclient + bootstrap → research/MAP.md)
- owner-waiting: re-enable Pages + cut v0.10.4; R9 web-vault password decision; real-account sign-ins (xmpp/bale/deltachat, mic/speaker, Android device); first non-prerelease
- last-gate: green @ 01dd3f9 (session 324 P7: dev-test + 15 shell + 6 app E2E + YAML)

## Session 325 — constitution v3 (2026-10-31)

Owner directive: one perfect AGENTS.md — endless "continue" loop, least words,
no context blowups, history out of the constitution. Merged the live file with
the three draft constitutions (owner paste) and the four failure-mode fixes
(chunked P0, execution mandate, comment carve-outs, blessed test triad).

- AGENTS.md rebuilt: new §0 boot/mandate, §3 atomic loop (3-strike, evidence
  rule, never-weaken-tests), §4 endless hardening cycle (gates, cycle+1→P2),
  §9 ladder + gate.sh plan; law items 16-20 added (severity, comments, deps,
  untestable, judgment). Section numbers §1.x/§2/§7/§8/§9 preserved — the 29
  code-comment cross-references stay true, zero code edits needed.
- WORKLOG: STATE block added at the top (this block).
- BUGS.md: stale open rows R5/R6 pruned (both were fixed in cycle 1 as
  F-91/F-92; the Fixed rows carry the evidence). Open: R9 (owner decision),
  R10.
- Repo visibility: private → public again (owner instruction — free-tier web
  testing). Pages serving remains disabled (owner action 2026-10-30; gh-pages
  branch intact); the E2E --live tier skips until re-enabled.
- Evidence: verified against a fresh clone (workflows, scripts/web-test,
  dev-test.sh, Makefile, BUGS/WORKLOG/research cross-refs); docs-only change.
- Next: R10, then P0 chunk 1.

## Session 324 — web hardening pass (2026-10-30/31, complete)

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

**Phase 2 (correctness, red-first, one bug per iteration):** all six
web findings fixed — F-87 two-tab vault clobber (merge-before-flush),
F-88 getUserMedia failure-path leak (per-attempt ownership), F-89 mic
rate read off the wrong object + no resample (AudioBuffer + streaming
resample; the read was a first-real-callback panic), F-90 web picker
offered TCP-impossible backends (js shows github/matrix/bale only),
F-91 no crash surface after canvas attach (window error/rejection →
overlay+Retry), F-92 observer accumulation (one tracked bootObs).
R10 audited: not a bug (trickle contract, comment corrected).
- **Phase 3:** comment/doc lies fixed (vault storage key, phantom
  IndexedDB host layer, XMPP "mellium" picker copy); dead-code deletion
  of vaultPathExists REVERTED by the suite — VaultExists→engine.Init
  uses it (usage analysis must catch wrappers).
- **Phase 4 (measured):** shell boot steady heap 88→3 MB (module bytes
  released post-instantiate — they were pinned for the app lifetime),
  download peak 170→133 MB (in-place assembly); instantiateStreaming
  REJECTED with numbers (compile is only ~200 ms). Harness:
  scripts/web-test/measure-boot.mjs.
- **Phase 5:** #status live region + noscript fallback (s15);
  below-fold-Bale resolved-by-design (scrollable List).
- **Phase 6:** secret sweep clean, zero DOM sinks (canvas = no HTML
  injection surface), scheme-allowlisted link opening; R9 (web vault
  fixed default password) needs an OWNER decision — held open.
- **Phase 7:** full battery green (gofmt/vet/vet-live/14-pkg suite/
  race legs/dev-test/15-shell/6-app/YAML). PRODUCTION: GitHub Pages
  serving is currently DISABLED on the repo (owner action ~22:00 UTC,
  gh-pages branch intact, Pages API 404) — the live tier skips with
  that reason; re-enabling + cutting v0.10.4 left to the owner.

Next (owner): re-enable Pages and cut v0.10.4 to ship the hardening;
decide R9 (web vault password); the standing owner-only rungs (live
sign-ins, first non-prerelease). Next (agent): continue from BUGS.md
open rows; the puppeteer suite now guards every web-touching change.
