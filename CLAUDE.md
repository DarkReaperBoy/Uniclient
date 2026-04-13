# CLAUDE.md

**MANDATORY — every rule in this file is a HARD requirement, not a suggestion.** Violating any rule here is equivalent to writing broken code. On every context reset, re-read this file FIRST and obey it completely. If you catch yourself about to break a rule, stop and correct course. No exceptions, no "just this once."

Operational guide for Claude Code. **Rules and build commands only** — no findings, quirks, or TODOs here.

## On Context Reset — Read These First

**STOP. Before doing ANYTHING, read these files in order. Do not skip any.**

1. This file (`CLAUDE.md`) — operational rules (YOU ARE HERE — read every rule)
2. `checklist/roadmap.md` — where you left off (current step, core, method)
3. `SPEC.md` — full architecture and feature spec
4. `checklist/` — per-platform checklists (see `checklist/README.md` for index)
5. `auth/auth.md` — test credentials (bot token, chat IDs)
6. `research/` — protocol specs, API quirks, debug findings

**Auto-continue rule:** If the user does not give a specific task, read `checklist/roadmap.md` and continue the pre-GUI roadmap from where you left off. No asking, no confirming — just pick up and work.

## Architecture

**Go backend + Flutter frontend, connected by FFI.** Each platform is a single Go file (`telegram.go`, `bale.go`, etc.) implementing the `Core` interface from `go/cores/base.go` (55 methods). The FFI bridge (`go/bridge/bridge.go`) exports functions via `//export` with JSON in/out. Shared utils live in `go/utils/`. Dart/Flutter UI (`dart/`) not started yet. See `SPEC.md` for full architecture.

## Quick Reference — Build & Test Commands

```bash
# Enter dev shell (required — provides Go, Flutter, Android SDK, all deps)
nix develop

# Build Go shared library
scripts/build_go.sh linux     # → go/build/libcores.so
scripts/build_go.sh windows   # → go/build/cores.dll (needs mingw32-gcc)
scripts/build_go.sh darwin    # → go/build/libcores.dylib
scripts/build_go.sh android   # → go/build/android/*/libcores.so (needs ANDROID_NDK_HOME)
scripts/build_go.sh web       # → go/build/cores.wasm + wasm_exec.js

# Shell aliases (defined in flake.nix)
build-go                      # → scripts/build_go.sh (current platform)
test-go                       # → cd go && go test ./...
test-dart                     # → cd dart && flutter test
test-all                      # → test-go && test-dart

# Run unit tests (no credentials needed)
cd go && go test ./utils/... -v -timeout 120s

# Run a single test (use -tags goolm for Matrix E2EE tests)
cd go && go test ./cores/... -run "TestTelegramBotAuth" -v -timeout 30s
cd go && go test -tags goolm ./tests/... -run "TestMatrixE2EE" -v -timeout 60s

# Integration tests (need env vars from auth/auth.md)
source auth/auth.md && cd go/tests && go test -v -timeout 300s
```

**Go version**: 1.26.1 · **CGO_ENABLED=0** everywhere. No CGo. Period.

## Pre-GUI Roadmap — Session-by-Session Steps

Progress is tracked in `checklist/roadmap.md`. On every context reset, read that file to know exactly where you left off — which step, which core, which method. At the end of every session (and after completing any substep), update `roadmap.md` with current status. NEVER ask the user what to do next — the answer is in `roadmap.md`. Do NOT skip steps. Do NOT start the GUI until ALL steps are complete.

### Step 1: Complete Existing Checklist Methods
Implement every method listed in the current `checklist/` files that isn't implemented yet. One core at a time.

### Step 2: Test ALL Existing Methods
Test every implemented method in every core against official harnesses and live APIs. Verify results using the official harness — never trust only your own test code. Mark results in `checklist/`. Prune passing tests. Fix failures. Do NOT nag the user — figure it out yourself via web search, reading existing libs, or replicating the official harness implementation.

### Step 3: Replace Checklists with Full Protocol Surface
Delete the old checklists. For every core, research the FULL protocol surface (every command, every API method, every feature — not just Core's 55 methods). Create new comprehensive checklists. Do not duplicate methods already confirmed working.

### Step 4: Implement All New Methods to 100%
Implement every new method from the updated checklists, one by one. Test each against the official harness and verify using the official harness — not just your own tests. For research: use web search, read existing libs' source, and/or replicate the official harness implementation. Never nag the user. Every core reaches 100% protocol coverage.

### Step 5: Perfect, Optimize, and Decouple Cores
Make it work → make it right → make it fast. Each core must be fully independent — no cross-core dependencies. Optimize for GUI readiness without building the GUI. Clean interfaces, consistent error handling, unified patterns.

### Step 6: Unify Core APIs
All cores expose the same unified interface where possible. Pythonic example: `cores.bale.SendMessage()`, `cores.rubika.SendMessage()`, `cores.telegram.SendMessage()` — same signatures, same return types, same behavior for shared operations. Platform-specific methods remain as extras. Speed over elegance, but don't break anything.

### Step 7: Protobuf Bridge
Replace JSON bridge encoding with Protocol Buffers. Define `.proto` files for all bridge types. Generate Go + Dart code. Schema changes break at compile time, not runtime.

### Step 8: Write `/docs`
Create a `/docs` folder documenting how to use each core independently as a standalone Go library. Usage examples, method reference, auth flows — as if someone is importing just one core into their own project.

### Step 9: Build the GUI
Only now: start Flutter GUI work. See `research/gui-idea.md` and `checklist/gui.md` for design.

**HARD RULE: Pure Go + Flutter ONLY — ZERO CGo, ZERO C/C++ dependencies.** No CGo anywhere — not in cores, not in utils, not in bridge, not in tests, not anywhere. No libvpx, no libolm, no native codecs, no C compilers needed. If it can't be done in pure Go or Flutter, find a different approach or skip it. The FFI bridge uses `dart:ffi` on the Dart side calling into a Go shared lib built with `go build -buildmode=c-shared` — that's Go's own toolchain, NOT CGo linking against external C libs. The tgcalls C++ test harness is a SEPARATE binary outside this repo (built independently in /tmp/), never compiled as part of `go build`. This project compiles with `go build` alone, no C compiler, no pkg-config, no system libraries.

**GitHub repo:** https://github.com/DarkReaperBoy/uniclient (HTTPS push, no SSH)

## Adding a New Platform ("add X social media")

When the user says "add X", follow these steps in order:

1. **Research & spec every method.** Find ALL official API/protocol commands and document them in `checklist/`. Read the RFCs, protocol specs, and find EVERY major library for the platform — catalog every method they expose. "Every method" means the FULL protocol surface, not just what maps to Core's 55 methods. Example: IRC has ~50+ commands (JOIN, PART, MODE, WHO, WHOIS, WHOWAS, AWAY, OPER, LIST, MONITOR, etc.) plus CTCP, DCC, IRCv3 extensions, NickServ/ChanServ — ALL of these must be implemented as exported methods on the core struct. The Core interface is the minimum; platform-specific methods go beyond it.
2. **Implement all methods 1:1 with original.** One file (`x.go`), same Core interface, same structure as existing cores. No invented protocols — match the original spec exactly. Every protocol command/feature becomes an exported method.
3. **Test ALL methods.** Find public server lists or create accounts yourself. Test every method one by one. Prune passing tests immediately and mark results in `checklist/` — never re-run a confirmed passing test.
4. **Calls (if supported).** Test against the official harness you can control and debug. Audio must flow perfectly bidirectional. Same rule: don't repeat passing tests, prune and mark the checklist.

## Key Rules

- **Keep docs in sync at ALL times — THIS IS NON-NEGOTIABLE** — Every session, before committing code, you MUST update: `checklist/` (status, TODOs, priorities — one file per platform), `SPEC.md` (architecture, specs), and `research/` (findings, quirks, protocol details). If you discovered something weird, it goes in `research/` IMMEDIATELY — not later, not "I'll do it at the end", NOW. If a test passed or failed, `checklist/` gets updated IMMEDIATELY. If architecture changed, `SPEC.md` gets updated IMMEDIATELY. Failing to update docs is equivalent to not doing the work. `CLAUDE.md` is ONLY for operational rules and build commands — no findings, no status details, no TODOs.
- ALL tests are real (hit live APIs with real credentials from `auth/auth.md`)
- Delete test files after user confirms they pass — never re-run confirmed tests
- Ask user for credentials/interaction when needed
- Document API quirks in `research/` immediately when discovered
- Sessions stored in `auth/` (gitignored), convention: `auth/{platform}_session.json`. Reuse sessions to avoid FLOOD_WAIT.
- Rate limits: 1.5s delay between API calls, skip on FLOOD_WAIT errors
- Peer access hashes cached from dialog/contact/resolve results (essential for user mode)
- **Git push after every work session** — commit and push changes after completing any meaningful work.
- **Session handoff** — when the user says "finalize and let's move to next session": (1) update ALL docs (`checklist/`, `SPEC.md`, `research/`) with everything done this session, (2) commit and push, (3) leave the codebase ready for "continue where we left off" on context reset.
- **Test files and binaries stay out of git** — all test files go in `go/tests/` (gitignored). Build output in `go/build/` (gitignored). Never commit `.so`, `.dll`, `.dylib`, `.wasm`.
- **No PII in commits** — never include real names, usernames, phone numbers, user IDs, or GUIDs in commit messages, code comments, or committed files. All credentials stay in `auth/` (gitignored).
- **Test paths** — `go test` runs from `go/tests/`, so session paths must use `../../auth/` not `../auth/`.
- **OTP handling** — run tests via Bash tool. For OTP: run test in background, ask user for code, write to `auth/otp_code.txt` which the test polls.
- **Don't invent protocols** — read the official client source and implement 1:1.
- **No stubs — everything gets tested** — NEVER mark a method as "done" if it just returns an error stub. If a method requires a server, daemon, special privileges, or admin access (e.g. Murmur Ice RPC, TS3 ServerQuery), get the binary via NixOS package or download it, spin it up, and test against it. Every method must be a real implementation that works against a real endpoint.
- **Replication discipline** — NEVER assume. ALWAYS read the original source or spec. When something doesn't work: (1) the bug is in YOUR code, (2) add surgical logging, (3) don't guess — read the code that produces/consumes the data, (4) make it work first, then right, then fast.
- **One file per core** — all Telegram code in `telegram.go`, all Rubika in `rubika.go`, etc.
- **NEVER use memory — everything in-project** — NEVER use Claude's memory system (`~/.claude/` memory files, MEMORY.md). All notes go in project files so the user can review and version-control them. On context reset, read project docs — that IS the memory.
- **Don't re-run passing tests** — prune from test file, document in `checklist/`. Only re-run tests that errored.
- **Research goes in `research/`, TODOs go in `checklist/`** — weird findings, protocol quirks, debug discoveries go in `research/` files. Track priorities in `checklist/` (one file per platform). Do NOT put these in `CLAUDE.md`.
- **Be human** — the user likes playful, affectionate interaction (sometimes calls you neko-chan). Be cheery and fun. Celebrate wins, commiserate on bugs. Warmth in conversation, rigor in implementation.

## Docs Index

- `research/telegram_notes.md` — gotd/td API patterns, bot limitations, FLOOD_WAIT, tgcalls signaling
- `research/tgcalls_protocol.md` — reverse-engineered tgcalls spec (§1-12 calls, §13 video, §14 SFU)
- `research/bale_protocol.md` — Bale bot API, user API, calling protocol
- `research/rubika_protocol.md` — Rubika protocol spec
- `research/deltachat_protocol.md` — Delta Chat protocol spec (32 sections)
- `research/ntgcalls_test_findings.md` — ntgcalls automated test harness findings
- `research/web_call_harness.md` — Telegram Web v4.0.0 call protocol, tt-harness
- `research/teamspeak_protocol.md` — TS3 UDP client protocol spec
- `research/matrix_protocol.md` — Matrix CS API, mautrix-go SDK mapping
- `research/mumble_protocol.md` — Mumble protocol spec (TCP/UDP, OCB2 crypto)
- `research/xmpp_protocol.md` — XMPP (RFC 6120/6121 + 30+ XEPs, Jingle)
- `research/gui-idea.md` — UI/UX design exploration, Discord/Telegram hybrid rationale
- `checklist/roadmap.md` — pre-GUI roadmap progress tracker (current step, core, method)
- `checklist/gui.md` — GUI component checklist, current state of demo_ui.html
