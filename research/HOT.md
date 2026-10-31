# HOT.md — the urgent store (AGENTS.md §0.3, §6)

Read FIRST every session, right after the WORKLOG STATE block. Anything the next
session MUST know lands here the moment it is noticed; prune the moment it is stale.
This is not history — stale lines are lies.

- **VM wipe #2 (2026-10-31):** the WHOLE working tree + toolchain were erased; the
  repo was re-cloned from origin at 205816e9 and nothing else was lost — the push
  law worked. Toolchain rebuild recipe now lives IN the repo: `scripts/env.sh`
  header (Go 1.27.0 tarball → `$TOOLCHAIN/go`, `go mod download` in `go/`,
  `npm ci` + `npx puppeteer browsers install chrome` in `scripts/web-test/`).
- **verify.yml run 41152637658** (session 329 dispatched it as the native-gotd
  proof for the bootstrap comment-strip): result NOT yet read — read it before
  relying on native-leg green for the next Go commit.
- **P0 chunk 2 in flight:** gui/ state+mutex surfaces, one package per iteration;
  MAP.md so far covers chunk 1 (cmd/uniclient + bootstrap) only.
