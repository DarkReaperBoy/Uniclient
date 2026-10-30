# BUGS.md — open bug list and fix log

One row per bug: what it is, why it matters, the fix + evidence. Tests
first — every row's fix landed with a red test turned green. New rows
number sequentially; the pre-2026-10 history (F-1..F-86) was deleted by
the owner on 2026-10-30 and lives in git history. Rows from the web
hardening pass carry the risk ID from
`research/web_hardening_2026-10.md` §3.

## Open (topmost first — the next session starts here)

| # | Where | What | Evidence / how to see it | Next step |
|---|-------|------|--------------------------|-----------|
| R5 | gh-pages shell (release.yml heredoc) | After the boot overlay hides, a later wasm panic/exit leaves a dead silent page — no crash surface, no retry. | research/web_hardening_2026-10.md §3 R5; pinned in the suite's KNOWN list. | Add a window error/unhandledrejection handler that re-shows the overlay + Retry; extend shell.spec. |
| R6 | gh-pages shell (release.yml heredoc) | MutationObserver accumulates across failed boots (self-heals at first canvas attach). | research/web_hardening_2026-10.md §3 R6. | Disconnect the previous observer at boot() start; prove via a monkeypatched MutationObserver counter in shell.spec. |
| R9 | web vault | Web vault is ciphertext-at-rest with a fixed default password (env/flags unreachable in a wasm argv) — no KDF secret on this target. | research/web_hardening_2026-10.md §3 R9; AGENTS.md §2 web persistence. | Owner decision: accept (product behavior) or spec a web passcode derivation path. Not silently changeable. |
| R10 | wrtc/js.go | GatheringCompletePromise(js) returns an immediately-closed channel — callers awaiting full ICE gathering send early answers on web. Callers are voice paths (media unsupported on web), matrix group-call signaling needs a check. | research/web_hardening_2026-10.md §3 R10. | Audit matrix_groupcall.go callers; if any signaling path awaits it on web, trickle candidates instead. |

*Nothing else open. Known cosmetic/doc lies are tracked as R7 (Phase 3).*

## Fixed

| # | What | Why it matters | Fix + evidence |
|---|------|----------------|----------------|
| F-87 (R1) | **Two tabs clobber the web vault — account/session data loss.** `utils/vault.go` flush() rewrote the ENTIRE vault from the instance's in-memory image; on js/wasm there is no single-instance lock (engine/lock_js.go no-ops) and every tab shares one localStorage vault. Tab A adds an account, tab B (booted earlier, stale image) saves → A's accounts/sessions/config keys are erased. Pre-fix, machine-verified: two tabs each pick Telegram; the decrypted vault (Argon2id t=3 m=64MiB p=4 + AES-256-GCM, params of utils/crypto.go, decoded in scripts/web-test/vault-crypto.mjs) held exactly ONE account after the second add. | Data-loss class, web-only. Any two open tabs + a save in the older tab silently destroys the newer tab's credentials/sessions. Native is immune (lock file). | Flush-time cross-instance merge: `mergeVaultData(ours, foreign)` (key-level union, ours wins) + platform hook `(*Vault).mergeForeignVaultData()` at the top of every flush — js (utils/vault_io_js.go) re-reads, decrypts and folds the persisted vault in before writing; native (utils/vault_io_file.go) no-ops (the lock file makes concurrent writers impossible; a merge there would mask a broken lock). RED-first both seams: unit TestMergeVaultDataAdoptsForeignKeys/TestMergeVaultDataEmptyAndNil (`undefined: mergeVaultData` before), puppeteer b6 flipped to expect 2 accounts (pre-fix binary: 1). GREEN: utils/engine/cores/gui/bootstrap ok natively, vet clean native+GOOS=js, wasm rebuilt, app tier 6/6. Known residual documented in code: simultaneous same-ms flushes can still interleave (Web Locks not awaitable from Go wasm); flushes are seconds apart in practice. |
