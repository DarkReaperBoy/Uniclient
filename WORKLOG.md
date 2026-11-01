# WORKLOG.md — the state file

Top: the **STATE block** — rewritten every session, the resume pointer for the next
agent. Then open items (severity order), then entries newest-first, terse (did /
evidence / next). The pre-2026-11-01 progress docs (BUGS.md, research/) were purged by
owner order — that history lives in git if ever needed.

## STATE

- front: 2026-11-01 owner reset EXECUTED (comment purge + docs purge + AGENTS.md v4.0) — **awaiting the owner's new direction**
- next: standby for owner instruction; treat it as the new front and execute it completely (never ask, never wait)
- owner-waiting: the new direction itself; the GUI-removal order (GUI deprecated 2026-11-01, removal NOT yet ordered)
- last-gate: CI verify **41289289707 = SUCCESS** on 0a604c30 — all 5 jobs + all steps green (test/vet/race incl. the comment-ban check, nix, cross-builds, android, gui-smoke)

## Open items

(none — the 2026-11-01 purge reset the list; the closed F-/R- record is in git history)

## Session 342 — owner redirect: comment ban + docs purge + AGENTS.md v4.0 (2026-11-01)

- Owner verdict: the GUI is not 1:1 to Ayugram Desktop; direction changes entirely.
  Executed exactly what was ordered "for now":
- **Comment purge (commit 5ca51964, pushed):** new `scripts/strip_comments.py` —
  byte-level lexical state machine (string/rune/raw-string/comment aware; preserves
  `//go:build`, `//go:embed`, `//go:generate`, legacy `// +build`, `//line`, cgo
  preambles, Example `// Output:` pins; hard-fails any file that does not lex). Run
  over the tree: **718 Go files walked, 714 stripped, 32,115 comments dropped, 0 lex
  failures**; `go/third_party/anet` excluded (upstream nested module). gofmt -w after
  (3,372 lines realigned where comment removal merged alignment groups); `gofmt -l .`
  empty across go/ = parse-verified; `--check` clean. `git diff --shortstat`: 714
  files, 3,372 insertions(+) / 34,416 deletions(-). 61 `//go:build` + 1 `//go:embed`
  directive lines verified intact post-strip (64 raw matches = 61 ours + 3 in the
  excluded anet module).
- **Docs purge (commit 0a604c30):** deleted BUGS.md + all of research/ (23 files, ~12.9k
  lines: MAP, HOT, ayugram_parity, web_hardening_2026-10, protocol/engine notes).
  Durable web truths (capability table, persistence model, F-87 merge) merged into
  AGENTS.md §5; the rest is history in git. Dead doc-manipulation scripts removed
  (bugs_r30_row.py, bugs_r31_row.py, bugs_r31_fixed.py, r340_worklog.py — nothing
  references them). Stale doc references fixed: web-test spec headers + README,
  verify.yml/release.yml comments, AGENTS § refs in env.sh/gate.sh/dev-test.sh.
- **AGENTS.md v4.0 (commit 0a604c30):** ONE rethought constitution — was v3.4 (316 lines)
  + research/web_hardening_2026-10.md (394); now 287 lines, ceiling ~300. New law §2: no comments
  in code, ever (script + CI `--check` enforced; only compiler directives survive).
  §4: the agent tests like a human — real-interface journeys (Puppeteer/Xvfb/terminal)
  with evidence in the WORKLOG entry; a green unit suite is never "it works" (the
  owner's loop concern, made first-class). GUI deprecation + AyuGram-mandate
  revocation recorded up top. The P0-P7 cycle/MAP/BUGS/HOT apparatus is gone;
  WORKLOG.md is the single state file (open items = the former BUGS role). verify.yml
  gains the comment-ban gate step.
- Carried-over owner facts (record only, not open items): R9 web-vault default
  password decision was pending; v0.10.4 release + Pages re-enable were owner-in-flight
  (Session 341 STATE); CI runs 41282402414 + 41282912766 (R53-R57 verify) are
  superseded by this session's dispatch as gate of record.
- Evidence: strip dry-run + run outputs (counts above); gofmt -l empty; pushes
  `a46b52e9..5ca51964` + `5ca51964..0a604c30`; **verify.yml 41289289707 on 0a604c30 =
  SUCCESS** — all 5 jobs (test/vet/race incl. comment-ban gate, nix, cross-builds,
  android, gui-smoke) and all steps green, verified via the runs API.
