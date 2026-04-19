# UniClient — TODO

**FOCUS: Telegram GUI only.** Do NOT work on other cores (Bale, Rubika, Matrix, XMPP, IRC, Delta Chat, GitHub, Mumble, TeamSpeak) until the human explicitly says so.

Top-to-bottom execution order. Remove items when done.

## Step 1: Perfect the UI spec (IN PROGRESS — see `checklist/spec_gaps.md`)

Full end-to-end audit of `research/telegram_desktop_ui.md` complete. Structural work done:
- ✅ Sections §41/§42/§43 reordered to file order; §45/§46 swapped.
- ✅ §37 heading HTML entities normalized.
- ✅ §50 Streamer Mode & Read Toggles (AyuGram) added (was missing entirely).
- ✅ §56 Appendix A — Resolved Style Constants added.
- ✅ §57 Appendix B — Dark Theme Color Palette added.

Remaining: fill per-section content gaps documented in `checklist/spec_gaps.md`. Next session should pick one group, spawn 3+ parallel research agents against AyuGram Desktop source, and fill the cited gaps. Commit each section separately.

Progress so far (see `spec_gaps.md` for strike-throughs + per-section completion notes):
- ✅ §1-§13 core UI group complete (2026-04-18/19)
- ✅ §32 story composer + §34 conference-call-create box (2026-04-19)
- ✅ §54 AyuGram Filters semantics + Shadow Ban flow (2026-04-19)
- ✅ §14-§19 Settings group complete (2026-04-19)
- ✅ §20-§22 Media Viewer / Create Group/Channel / Forum Topics (2026-04-19)
- ✅ §23-§26 Scheduled / Keyboard Shortcuts / Theming / Admin Tools (2026-04-19) — §20-§26 batch complete

Next-session priority (pick one, dispatch 3 parallel agents):
1. **§27-§34** — Passcode, 2FA, Chat Export, Bots, Saved Messages, §32/§33/§34 remainder (story composer already done — only gaps left in §32; §33 contacts + §34 calls).
2. **§35-§49** — States/Popups/Misc — many small sections, good for a fast cleanup batch.
3. **§52/§53** — remaining AyuGram extensions (saveForBots gating, deletedMark/editedMark, Repeat Message hint, etc.)

Batch recipe (proven): read current section bounds via grep, dispatch 3 parallel Opus agents each scoped to one section's line range, split the combined diff with `/tmp/split_patch*.py` approach, commit each section separately, push once at the end.

## Step 2: Build the complete GUI checklist (session after Step 1)

Using the perfected `research/telegram_desktop_ui.md`, build a full implementation checklist in `checklist/gui.md`. Rules:
- Every UI feature gets a checklist entry
- Each entry cites the relevant `telegram_desktop_ui.md` section (e.g. "see §4.2") — do NOT copy-paste spec content
- If a feature is already implemented, verify it matches the spec exactly (is it canon?)
- If a feature is not implemented, it goes on the list as TODO
- The checklist must be COMPLETE — every single UI element, interaction, and state from the spec

## Step 3: Implement everything on the checklist

Work through `checklist/gui.md` top to bottom. For each item:
- If not implemented → implement it
- If implemented but not canon → fix it to match spec exactly
- Self-test with automated pipeline before marking done

## 2. Chat Mode — AyuGram-style UI (Telegram first)

Study AyuGram Desktop (https://github.com/AyuGram/AyuGramDesktop). Build new UI from scratch matching Telegram Desktop 1:1. Mobile-responsive. **READ THE ENTIRE CORE FILE before implementing UI for each platform.**

**IMPORTANT: No separate "AyuGram Preferences" section.** All AyuGram-specific settings get folded into standard UniClient settings categories:
- Ghost Mode (§51: 5 core toggles + 3 extras, per-account, lock mechanism) → **Privacy** settings
- Anti-Recall / Message History (§52) → **Privacy** settings
- Forward enhancements (§53) → **Chat** settings
- Appearance customization (§54: avatar corners, bubble radius, wide multiplier, tail, MD3 switches, quotes) → **Appearance** settings
- Context menu & field button toggles (§54.7-54.9) → **Chat** settings
- Drawer/sidebar toggles (§54.8) → **Layout** settings

Every component smoke-tested: build, launch, `flutter_inspect.sh screenshot`, verify engine logs. Not done until visually confirmed working.

### 2b. Per-platform adaptation (after Telegram)
- Bale — read `go/cores/bale.go`, adapt for Bale features
- Rubika — read `go/cores/rubika.go`, adapt
- Matrix — read `go/cores/matrix.go`, adapt (E2EE indicators, threads, spaces)
- XMPP — read `go/cores/xmpp.go`, adapt (MUC, presence, OMEMO)
- IRC — read `go/cores/irc.go`, adapt (channel modes, NickServ, topic)
- Delta Chat — read `go/cores/deltachat.go`, adapt (email-based, contacts)
- GitHub — read `go/cores/github.go`, adapt (issues, PRs, discussions)

### Rules
- Features a platform doesn't support → button doesn't exist
- Platform-specific features → show only for that platform
- Every screen/widget screenshot-verified before marking done

## 3. Voice Mode (Mumble, TeamSpeak)

Completely different layout for voice platforms. Read `go/cores/mumble.go` and `go/cores/teamspeak.go` fully first.

- Channel tree — hierarchical channel list with user counts
- User list per channel — speaking/muted/deafened indicators
- Voice activity indicators — visual feedback when talking
- Join/disconnect controls — click channel to join, disconnect button
- Self controls — mute, deafen, push-to-talk toggle
- Per-user volume adjustment — volume sliders per person
- Channel text chat — visible when joined to a voice channel
- Server info — name, ping, codec, connected users count
- Mode switching — clicking voice account → voice mode, chat account → chat mode

## 4. Distribution & Polish

- Application icon in taskbar — .desktop file + icon theme wired into build
- Distribution packaging — Flatpak, AppImage, AUR, .deb, .rpm
- Accessibility — semantic labels, screen reader support, focus management

## 5. Docstring Every Core

Final step. Add Go docstrings to every exported method in every core. Documentation lives in the code.

## Architecture Reference

- **Go backend** → `libcores.so` via `dart:ffi`
- **Protobuf FFI bridge**: 3,564 methods, async via `Isolate.run`
- **Engine**: SQLite cache (rebuildable from vault), auth FSM, pending queue, media pipeline, reconnect
- **Vault**: AES-256-GCM — single source of truth for accounts, credentials, sessions, config
- **Provider state**: `AppState`, `ChatState`, `AuthState`
- **Single-instance**: GApplication D-Bus + flock
- **Display**: Wayland-only (GDK_BACKEND=wayland forced)

## GUI Automation Toolkit

- **`scripts/flutter_inspect.sh`** — screenshot, widget tree, text extraction via Flutter VM Service
- **`scripts/flutter_auth.sh`** — CLI auth control via file-polling (`/tmp/uniclient_auth_cmd.json`)
