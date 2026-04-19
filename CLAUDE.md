# CLAUDE.md

**MANDATORY — every rule in this file is a HARD requirement, not a suggestion.** Violating any rule here is equivalent to writing broken code. On every context reset, re-read this file FIRST and obey it completely. If you catch yourself about to break a rule, stop and correct course. No exceptions, no "just this once."

Operational guide for Claude Code. **Rules and build commands only** — no findings, quirks, or TODOs here.

## Ralph Unattended Mode

If your prompt starts with "You are running in unattended automation mode (ralph loop)", you are in ralph mode. The following overrides apply:

- **Reading list:** Follow the ralph prompt's steps — do NOT read SPEC.md, auth/auth.md, or research/ files upfront. Only read CLAUDE.md and the specific spec section cited by your checklist item.
- **No plan files:** The component plan file requirement (gui_component_plan_{name}.md) is waived. The checklist IS the plan.
- **No doc sync:** Do NOT update SPEC.md or research/ files. Only update checklist/gui.md (delete completed items).
- **No auto-continue:** After completing your one item, exit cleanly. Do NOT read todolist.md and keep working.
- **No agents:** Do NOT spawn parallel agents. Stay focused on one item.
- All other CLAUDE.md rules still apply fully.

## On Context Reset — Read These First

**STOP. Before doing ANYTHING, read these files in order. Do not skip any.**

1. This file (`CLAUDE.md`) — operational rules (YOU ARE HERE — read every rule)
2. `checklist/todolist.md` — what to do next, top-to-bottom order
3. `SPEC.md` — full architecture and feature spec
4. `auth/auth.md` — test credentials (bot token, chat IDs)
5. `research/` — protocol specs, API quirks, debug findings

**Auto-continue rule:** If the user does not give a specific task, read `checklist/todolist.md` and continue from the top uncompleted item. No asking, no confirming — just pick up and work.

## Architecture

**Go backend + Flutter frontend, connected by FFI.** Each platform is a single Go file (`telegram.go`, `bale.go`, etc.) implementing the `Core` interface from `go/cores/base.go` (63 methods). The FFI bridge (`go/bridge/bridge.go`) exports functions via `//export` with JSON in/out. Shared utils live in `go/utils/`. Dart/Flutter UI (`dart/`) not started yet. See `SPEC.md` for full architecture.

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

# Build Flutter app (requires nix develop)
scripts/build_flutter.sh      # → dart/build/linux/x64/debug/bundle/uniclient

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

## What To Do

All work is tracked in `checklist/todolist.md` — structured top-to-bottom. On context reset, read it and continue from the top uncompleted item. Remove items from `checklist/todolist.md` when done. NEVER ask the user what to do next — the answer is in `checklist/todolist.md`.

Steps 1–13 (cores, testing, protobuf bridge) are ALL DONE. Current work: Step 15 — Build GUI (delete old UI, rebuild from scratch). Final step after GUI: docstring every core.

**HARD RULE: Pure Go + Flutter ONLY — ZERO CGo, ZERO C/C++ dependencies.** No CGo anywhere — not in cores, not in utils, not in bridge, not in tests, not anywhere. No libvpx, no libolm, no native codecs, no C compilers needed. If it can't be done in pure Go or Flutter, find a different approach or skip it. The FFI bridge uses `dart:ffi` on the Dart side calling into a Go shared lib built with `go build -buildmode=c-shared` — that's Go's own toolchain, NOT CGo linking against external C libs. The tgcalls C++ test harness is a SEPARATE binary outside this repo (built independently in /tmp/), never compiled as part of `go build`. This project compiles with `go build` alone, no C compiler, no pkg-config, no system libraries.

**GitHub repo:** https://github.com/DarkReaperBoy/uniclient (HTTPS push, no SSH)

## Adding a New Platform ("add X social media")

When the user says "add X", follow these steps in order:

1. **Research & spec every method.** Find ALL official API/protocol commands and document them in `checklist/`. Read the RFCs, protocol specs, and find EVERY major library for the platform — catalog every method they expose. "Every method" means the FULL protocol surface, not just what maps to Core's 55 methods. Example: IRC has ~50+ commands (JOIN, PART, MODE, WHO, WHOIS, WHOWAS, AWAY, OPER, LIST, MONITOR, etc.) plus CTCP, DCC, IRCv3 extensions, NickServ/ChanServ — ALL of these must be implemented as exported methods on the core struct. The Core interface is the minimum; platform-specific methods go beyond it.
2. **Implement all methods 1:1 with original.** One file (`x.go`), same Core interface, same structure as existing cores. No invented protocols — match the original spec exactly. Every protocol command/feature becomes an exported method.
3. **Test ALL methods.** Find public server lists or create accounts yourself. Test every method one by one. Prune passing tests immediately and mark results in `checklist/` — never re-run a confirmed passing test.
4. **Calls (if supported).** Test against the official harness you can control and debug. Audio must flow perfectly bidirectional. Same rule: don't repeat passing tests, prune and mark the checklist.

## Key Rules

- **SPEC FIRST, CODE SECOND — mandatory for all UI work** — Before writing ANY widget or screen code, you MUST: (1) Read the FULL spec sections for that component (`research/telegram_desktop_ui.md`), not just headers — every subsection, dimension, and state. (2) Cross-reference all related spec sections (a sidebar involves §1 layout + §2 chat list + §3 hamburger + §18 folders). (3) For large components (new screens, multi-widget layouts), write a component breakdown plan in `research/gui_component_plan_{name}.md` listing every widget, its nesting, exact dimensions, and state needs — not required for small single-widget checklist items. This rule exists because we wasted an entire session building a completely wrong left panel by skipping the spec.
- **Research before implementing UI features** — If you check `research/telegram_desktop_ui.md` and don't find the UI feature you need to implement, you MUST research AyuGram Desktop source code (https://github.com/AyuGram/AyuGramDesktop) first and add your findings to the research file BEFORE writing any code. Never guess how a UI feature should work — find the real implementation.
- **Smoke-test the GUI before declaring done** — After ANY GUI-related work, you MUST build the app, launch it, and **interact with it like a normal user** to verify changes work. Passing unit tests is not enough — the actual app must work.
- **UI is the source of truth, not API calls** — A feature is NOT working unless the user can SEE it working in the UI. An API call succeeding behind the scenes means nothing if the display is broken. When verifying bugs or features: screenshot the rendered result and judge what the USER sees, not what the logs say. "Forward works" means a forwarded message renders with a "Forwarded from" header — not that the API returned 200. "Pinned bar works" means clicking it scrolls to the pinned message visually — not that GetPinnedMessages returned data. Always verify the VISUAL output, never just the data layer.

  ### GUI Automation Toolkit

  Three tools for controlling the running Flutter app without OS-level mouse/keyboard automation:

  #### 1. `scripts/flutter_inspect.sh` — See & inspect the UI
  Flutter debug apps expose a VM Service (WebSocket JSON-RPC). This script connects to it.
  ```bash
  # Build & launch
  nix develop --command bash -c "scripts/build_flutter.sh linux debug"
  cd dart/build/linux/x64/debug/bundle && nohup ./uniclient > /tmp/uniclient_log.txt 2>&1 &

  # Screenshot the rendered UI (works on Wayland, X11, headless — no display needed)
  scripts/flutter_inspect.sh screenshot /tmp/ss.png   # then: Read /tmp/ss.png

  # Inspect widget tree
  scripts/flutter_inspect.sh tree                      # full widget tree with inspector IDs
  scripts/flutter_inspect.sh find TextField            # find widgets by name
  scripts/flutter_inspect.sh text inspector-116        # read text content of a widget
  scripts/flutter_inspect.sh details inspector-68      # full properties of a widget
  ```
  **How it works:** Connects to the Dart VM Service URL (printed in app startup logs), calls `ext.flutter.inspector.*` extension methods over WebSocket. `screenshot` renders the widget tree to PNG server-side — no screen capture needed. Requires `websocat` (auto-fetched via nix).

  #### 2. `scripts/flutter_auth.sh` — Control auth flow
  Automates authentication by writing commands to `/tmp/uniclient_auth_cmd.json`, which the app's `AuthState` polls every second when auth needs input.
  ```bash
  scripts/flutter_auth.sh status                       # show auth state from logs
  scripts/flutter_auth.sh choose phone                 # pick auth method
  scripts/flutter_auth.sh submit "+1234567890"         # enter phone number
  scripts/flutter_auth.sh otp-wait                     # poll auth/otp_code.txt, auto-submit OTP
  scripts/flutter_auth.sh submit "my2fapassword"       # enter 2FA password
  scripts/flutter_auth.sh auto phone "+1234567890"     # full auto: choose→phone→OTP wait→2FA wait
  scripts/flutter_auth.sh cancel                       # cancel auth flow
  ```
  **How it works:** `AuthState` in `dart/lib/state/auth_state.dart` has a file-polling timer. When auth needs input (`choose`/`input`/`otp`/`2fa` states), it checks `/tmp/uniclient_auth_cmd.json` every second. File format: `{"action":"submit","value":"12345"}`. File is deleted after reading. Same OTP-file pattern as Go tests (`auth/otp_code.txt`).

  #### 3. `scripts/flutter_interact.sh` — Simulate user interaction
  Dispatches real pointer/gesture events into the running Flutter app via `/tmp/uniclient_debug_cmd.json`. The app's debug command handler in `main.dart` uses `GestureBinding.handlePointerEvent()` to inject taps, right-clicks, scrolls, etc.
  ```bash
  scripts/flutter_interact.sh tap 500 300           # left-click at (500, 300)
  scripts/flutter_interact.sh rightclick 500 300    # right-click (opens context menu)
  scripts/flutter_interact.sh longpress 500 300     # long-press (enters selection mode)
  scripts/flutter_interact.sh scroll 500 400 0 -200 # scroll down at (500, 400)
  scripts/flutter_interact.sh scroll 500 400 0 200  # scroll up
  scripts/flutter_interact.sh type "hello world"    # type into focused TextField
  scripts/flutter_interact.sh key enter             # send Enter key
  scripts/flutter_interact.sh open 5                # open chat at index 5
  scripts/flutter_interact.sh open -id "chatId123"  # open chat by ID
  scripts/flutter_interact.sh send "hello"          # send message in active chat
  scripts/flutter_interact.sh chats                 # list chats (JSON to stdout)
  scripts/flutter_interact.sh messages              # list current messages
  scripts/flutter_interact.sh state                 # get app state
  scripts/flutter_interact.sh accounts              # list accounts
  ```
  **How it works:** Writes JSON commands to `/tmp/uniclient_debug_cmd.json` which the app polls every 1s in debug mode. Gesture commands use `GestureBinding.instance.handlePointerEvent()` to dispatch real `PointerDownEvent`/`PointerUpEvent`/`PointerScrollEvent` at screen coordinates. Text input finds the focused `EditableTextState` and updates its value. Output commands write results to `/tmp/uniclient_debug_out.json`.

  **Testing workflow:** Screenshot → identify element coordinates → interact → screenshot → verify result. This is the PRIMARY way to self-test UI features. You own the entire verification pipeline — the user should not need to test anything.

  #### 4. App logs — Verify engine calls
  ```bash
  cat /tmp/uniclient_log.txt                           # full log
  grep "ENGINE:" /tmp/uniclient_log.txt                # FFI bridge calls
  grep "AUTH:" /tmp/uniclient_log.txt                  # auth flow
  grep "CHAT:" /tmp/uniclient_log.txt                  # chat state changes
  grep "EVENT:" /tmp/uniclient_log.txt                 # Go→Dart events
  ```

  #### Bringing the window to front (for OS-level screenshots with `spectacle`)
  On KDE Wayland, `xdotool` doesn't work. Use `kdotool` (KDE-specific):
  ```bash
  # Find window by PID
  APP_PID=$(pgrep -f "bundle/uniclient" | head -1)
  nix-shell -p kdotool --run "
    for uuid in \$(kdotool search --name ''); do
      pid=\$(kdotool getwindowpid \$uuid 2>/dev/null)
      [ \"\$pid\" = \"$APP_PID\" ] && kdotool windowactivate \$uuid && break
    done"
  spectacle -b -n -f -o /tmp/screenshot.png            # full-screen screenshot
  ```
  Note: `flutter_inspect.sh screenshot` is preferred — it captures the Flutter UI directly without needing window focus.

  #### Gotchas & low-level details
  - **websocat buffer:** Default 64KB — large widget trees get truncated. Screenshot responses usually fit.
  - **Inspector IDs** (`inspector-N`) change between app restarts. Use `flutter_inspect.sh tree` to find the right one, or `inspector-8` (typically app root).
  - **`evaluate` doesn't work:** Dart expression evaluation isn't available in custom builds (no JIT compilation service). That's why we use file-based IPC instead.
  - **HTTP vs WebSocket:** `getVM`/`getIsolate` work via HTTP GET, but `ext.flutter.inspector.*` extension methods require WebSocket.
  - **Isolate discovery:** `curl -s "http://127.0.0.1:PORT/TOKEN=/getVM" | jq '.result.isolates[] | select(.isSystemIsolate == false) | .id'`
  - **Raw JSON-RPC** (if scripts break and you need to debug manually):
    ```
    screenshot:  {"method":"ext.flutter.inspector.screenshot","params":{"isolateId":"isolates/XXX","id":"inspector-8","width":1280,"height":800,"margin":0,"maxPixelRatio":2.0,"debugPaint":false}}
    widget tree: {"method":"ext.flutter.inspector.getRootWidgetSummaryTree","params":{"isolateId":"isolates/XXX","objectGroup":"inspect"}}
    details:     {"method":"ext.flutter.inspector.getDetailsSubtree","params":{"isolateId":"isolates/XXX","arg":"inspector-116","subtreeDepth":10}}
    ```
    Send via: `echo '<json>' | websocat -n1 "ws://127.0.0.1:PORT/TOKEN=/ws"`

  ### Checklist: what to verify
  - Does the screen render correctly? (screenshot)
  - Do chats load after auth? (logs: `GetChatList`)
  - Do buttons produce expected engine calls? (logs: `ENGINE:`)
  - Does the auth flow complete? (logs: `AUTH:` → `ready`)
  - Are events delivered? (logs: `EVENT:`)
  - If something is broken, fix it before saying you're done.

## Harnesses — What To Use For What

**RULE: Research is a living document, not a write-once artifact.** Every session, if research is outdated, vague, incomplete, or untested — go to the OFFICIAL source, study it, and update/add/remove/optimize the research file. The goal: next session, you spoonfeed yourself. Don't re-discover what you already learned.

### UI Implementation & Testing

| Task | Source of truth | Research file | How to verify |
|------|----------------|---------------|---------------|
| **Design any UI widget/screen** | [AyuGram Desktop](https://github.com/AyuGram/AyuGramDesktop) — match 1:1 | `research/telegram_desktop_ui.md` | Read spec section first. If missing/vague, send agent to AyuGram source, ADD findings to research, THEN implement. |
| **Test UI renders correctly** | Flutter debug tools (built in-repo) | See CLAUDE.md § GUI Automation Toolkit | Build → launch → `flutter_inspect.sh screenshot` → `flutter_interact.sh` (tap/scroll/findtext/taptext) → screenshot → verify. |
| **Test UI interaction flows** | `scripts/flutter_interact.sh` | `checklist/gui.md` | `taptext "Button"` to click by label. `findtext "X"` to locate elements. `rightclick x y` for context menus. `scroll` for pagination. `alltext` to dump screen. Always screenshot before AND after. |
| **Test auth flow** | `scripts/flutter_auth.sh` | See CLAUDE.md § GUI Automation Toolkit | `flutter_auth.sh auto phone "+..."` → monitor `AUTH:` logs → verify `ready` state. |

### Telegram Backend

| Task | Harness | Auth | Research file |
|------|---------|------|---------------|
| **Test Telegram API methods** | [gotd/td](https://github.com/gotd/td) | Two sessions in `auth/` | `research/telegram_notes.md` |
| **Test Telegram desktop/web calls** | [TelegramMessenger/tgcalls](https://github.com/TelegramMessenger/tgcalls) (v8 + v13) | Two sessions in `auth/` for OTP | `research/tgcalls_protocol.md` |
| **Test Telegram web calls** | [AyuGram/AyuGramDesktop](https://github.com/AyuGram/AyuGramDesktop) web call flow | Same auth | `research/tgcalls_web_protocol.md` (split from tgcalls — web-specific WebRTC flow) |

### Bale

| Task | Harness | Auth | Research file |
|------|---------|------|---------------|
| **Test Bale API methods** | [Enalite/aiobale](https://github.com/Enalite/aiobale) | Sessions in `auth/` | `research/bale_protocol.md` |
| **Find unpublished Bale user API** | Scrape official Bale web client source | — | `research/bale_protocol.md` |
| **Test Bale calls** | Same as above + Bale web client | — | `research/bale_protocol.md` |

### Rubika

| Task | Harness | Auth | Research file |
|------|---------|------|---------------|
| **Test Rubika API methods** | [shayanheidari01/rubika](https://github.com/shayanheidari01/rubika) | Sessions in `auth/` | `research/rubika_protocol.md` |
| **Find unpublished Rubika user API** | Scrape official Rubika web client source | — | `research/rubika_protocol.md` |
| **Test Rubika calls** | Same as above | — | `research/rubika_protocol.md` |

### Other Cores

| Core | Harness | Research file | Notes |
|------|---------|---------------|-------|
| **Matrix** | [mautrix-go](https://github.com/mautrix/go) | `research/matrix_protocol.md` | CS API, E2EE via goolm |
| **XMPP** | [mellium.im/xmpp](https://pkg.go.dev/mellium.im/xmpp) | `research/xmpp_protocol.md` | RFC 6120/6121 + XEPs |
| **IRC** | Direct socket (RFC 2812) | `research/irc_protocol.md` | Test against libera.chat/OFTC |
| **Delta Chat** | [deltachat-core-rust](https://github.com/deltachat/deltachat-core-rust) (reference) | `research/deltachat_protocol.md` | IMAP/SMTP, Autocrypt |
| **Mumble** | Spin up Murmur via NixOS | `research/mumble_protocol.md` | TCP+UDP, OCB2-AES128 |
| **TeamSpeak** | Spin up TS3 server via NixOS | `research/teamspeak_protocol.md` | UDP client protocol |
| **GitHub** | GitHub REST/GraphQL API directly | — | Standard OAuth |

When adding a NEW core not listed here: research the official client libraries, find the best Go library or protocol spec, add a row to this table, and create the research file BEFORE writing any code.

- **Build in batches, self-verify, then continue** — Implement a cluster of related features, build, and fully verify them yourself using the automated testing pipeline (screenshots, gesture dispatch, logs). Fix any bugs found before moving on. Log bugs in `checklist/gui.md`. Don't ask "what should I do next" — fix bugs first, then continue from `checklist/todolist.md`. The user does NOT need to verify anything — that's your job.
- **Self-test BEFORE handing to user — MANDATORY, FULLY AUTOMATED** — After implementing a batch, you MUST build, launch, and thoroughly test every feature yourself. You have ZERO excuse to skip testing — everything is automated:
  - **Screenshots:** `flutter_inspect.sh screenshot` — visually verify against AyuGram Desktop spec
  - **Interaction:** `flutter_interact.sh` — tap, right-click, scroll, type, taptext, findtext
  - **Auth/OTP:** Use existing sessions in `auth/`. For OTP, read the code from connected accounts via the engine
  - **Visual judgment:** YOU compare screenshots against spec/AyuGram source — don't defer to the user
  - **Bug testing:** YOU test every flow end-to-end before ticking the checklist — the user should never find a bug you could have caught
  - **Credentials:** Use existing accounts in `auth/` or create new ones yourself
  
  The user should NEVER be the first person to discover something is broken. If you can't verify it, don't mark it done.
- **Log every bug found in checklists** — Any bug or issue discovered during testing, auditing, or smoke-testing MUST be added to the relevant checklist file in `checklist/` immediately. Don't just fix it silently — document it so there's a paper trail. If it's a GUI bug, add it to `checklist/gui.md`. If it's a core/engine bug, add it to the relevant platform checklist.
- **Keep docs in sync at ALL times — THIS IS NON-NEGOTIABLE** — Every session, before committing code, you MUST update: `checklist/` (status, TODOs, priorities — one file per platform), `SPEC.md` (architecture, specs), and `research/` (findings, quirks, protocol details). If you discovered something weird, it goes in `research/` IMMEDIATELY — not later, not "I'll do it at the end", NOW. If a test passed or failed, `checklist/` gets updated IMMEDIATELY. If architecture changed, `SPEC.md` gets updated IMMEDIATELY. Failing to update docs is equivalent to not doing the work. `CLAUDE.md` is ONLY for operational rules and build commands — no findings, no status details, no TODOs.
- ALL tests are real (hit live APIs with real credentials from `auth/auth.md`)
- Delete test files after verifying they pass — never re-run confirmed tests
- Use existing credentials from `auth/`. Create new accounts yourself if needed.
- Document API quirks in `research/` immediately when discovered
- Sessions stored in `auth/` (gitignored), convention: `auth/{platform}_session.json`. Reuse sessions to avoid FLOOD_WAIT.
- Rate limits: 1.5s delay between API calls, skip on FLOOD_WAIT errors
- Peer access hashes cached from dialog/contact/resolve results (essential for user mode)
- **Git push after every work session** — commit and push changes after completing any meaningful work.
- **Session handoff** — when the user says "finalize and let's move to next session": (1) update ALL docs (`checklist/`, `SPEC.md`, `research/`) with everything done this session, (2) commit and push, (3) leave the codebase ready for "continue where we left off" on context reset.
- **Test files and binaries stay out of git** — all test files go in `go/tests/` (gitignored). Build output in `go/build/` (gitignored). Never commit `.so`, `.dll`, `.dylib`, `.wasm`.
- **No PII in commits** — never include real names, usernames, phone numbers, user IDs, or GUIDs in commit messages, code comments, or committed files. All credentials stay in `auth/` (gitignored).
- **Test paths** — `go test` runs from `go/tests/`, so session paths must use `../../auth/` not `../auth/`.
- **OTP handling** — run tests via Bash tool. For OTP: use existing connected accounts to read the code via the engine, or read from `auth/otp_code.txt`.
- **Don't invent protocols** — read the official client source and implement 1:1.
- **No duplicate methods** — Before implementing a method from the checklist, ALWAYS check existing code first. Grep the core file for similar function names and read any matches. A "missing" method may already be implemented under a different name or covered by existing logic. Compare what the checklist says vs what the code already does. Only implement if the functionality genuinely doesn't exist yet. If a checklist item is already covered, remove it from the checklist instead of adding duplicate code.
- **ZERO placeholders — HARD BAN** — NEVER write placeholder code, stub UI, mock data, "coming soon" snackbars, hardcoded fake content, or any feature that appears to work but doesn't. If a feature isn't implemented, the UI element for it must NOT exist. No fake buttons, no mock sticker packs, no static waveforms, no "TODO" features. Every visible UI element must be fully functional end-to-end. Violating this rule is equivalent to shipping broken code.
- **No stubs — everything gets tested** — NEVER mark a method as "done" if it just returns an error stub. If a method requires a server, daemon, special privileges, or admin access (e.g. Murmur Ice RPC, TS3 ServerQuery), get the binary via NixOS package or download it, spin it up, and test against it. Every method must be a real implementation that works against a real endpoint.
- **Parallelize with agents** — For research, spec writing, and any task that splits into independent chunks: spawn multiple agents in parallel (3+ at a time). Don't serialize work that can run concurrently. One agent per source file / spec section / protocol feature. Wait for results, merge, repeat.
- **Replication discipline** — NEVER assume. ALWAYS read the original source or spec. When something doesn't work: (1) the bug is in YOUR code, (2) add surgical logging, (3) don't guess — read the code that produces/consumes the data, (4) make it work first, then right, then fast.
- **One file per core** — all Telegram code in `telegram.go`, all Rubika in `rubika.go`, etc.
- **NEVER use memory — everything in-project** — NEVER use Claude's memory system (`~/.claude/` memory files, MEMORY.md). All notes go in project files so the user can review and version-control them. On context reset, read project docs — that IS the memory.
- **Don't re-run passing tests** — prune from test file, document in `checklist/`. Only re-run tests that errored.
- **Research goes in `research/`, TODOs go in `checklist/`** — weird findings, protocol quirks, debug discoveries go in `research/` files. Track priorities in `checklist/` (one file per platform). Do NOT put these in `CLAUDE.md`.
- **Be human** — the user likes playful, affectionate interaction (sometimes calls you neko-chan). Be cheery and fun. Celebrate wins, commiserate on bugs. Warmth in conversation, rigor in implementation.

## Docs Index

- `research/telegram_notes.md` — gotd/td API patterns, bot limitations, FLOOD_WAIT, tgcalls signaling
- `research/tgcalls_protocol.md` — reverse-engineered tgcalls spec (§1-12 calls, §13 video, §14 SFU) + web call harness & ntgcalls appendices
- `research/bale_protocol.md` — Bale bot API, user API, calling protocol
- `research/rubika_protocol.md` — Rubika protocol spec
- `research/deltachat_protocol.md` — Delta Chat protocol spec (32 sections)
- `research/teamspeak_protocol.md` — TS3 UDP client protocol spec
- `research/matrix_protocol.md` — Matrix CS API, mautrix-go SDK mapping
- `research/mumble_protocol.md` — Mumble protocol spec (TCP/UDP, OCB2 crypto)
- `research/ice_protocol.md` — ZeroC Ice wire protocol for Murmur admin (encap format, identities, tested methods)
- `research/xmpp_protocol.md` — XMPP (RFC 6120/6121 + 30+ XEPs, Jingle)
- `research/engine_architecture.md` — Engine layer spec: SQLite cache, auth FSM, events, pending queue, media pipeline, content normalization
- `research/telegram_desktop_ui.md` — Complete Telegram Desktop UI spec (22 sections: §1-13 core UI, §14 general/account settings, §15 notifications, §16 privacy/security, §17 data/storage/advanced, §18 folders, §19 sessions/power/language, §20 media viewer, §21 create group/channel, §22 forum topics)
