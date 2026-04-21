# UniClient — TODO

**FOCUS: Telegram GUI only.** Do NOT work on other cores (Bale, Rubika, Matrix, XMPP, IRC, Delta Chat, GitHub, Mumble, TeamSpeak) until the human explicitly says so.

Top-to-bottom execution order. Remove items when done.

## Step 1: Perfect the UI spec — ✅ COMPLETE (2026-04-19)

All per-section content gaps in `research/telegram_desktop_ui.md` have been filled. See `checklist/spec_gaps.md` for full completion notes. Every section §1-§57 now has source-cited pixel-level detail.

## Step 2: Build the complete GUI checklist — COMPLETE (2026-04-19, restructured 2026-04-20)

Original 5329-item monolithic `gui.md` has been split into 6 per-section files (~1096 consolidated items). Old file archived as `gui_old_monolithic.md`.

## Step 3: Implement everything on the checklists

**SPLIT CHECKLIST FILES** — work through these top to bottom. Each file lists which `.dart` files it touches in a header table. **Multiple ralphs CAN run in parallel on files that touch DIFFERENT .dart files.** Do NOT run two ralphs on files that share the same .dart file.

| Checklist file | Sections | Primary .dart files | Safe to parallelize with |
|---|---|---|---|
| `gui_layout_and_nav.md` | §1-§4 | `shell.dart`, `titlebar.dart`, `filter_column.dart`, `chat_list_panel.dart`, `chat_list_row.dart`, `hamburger_drawer.dart` | §14-§22, §23-§40, §41-§57 |
| `gui_messages.md` | §5-§7 | `message_bubble.dart`, `chat_view.dart` | §14-§22, §23-§40 (if not touching chat_view) |
| `gui_panels_and_overlays.md` | §8-§13 | `info_panel.dart`, `auth_screen.dart`, NEW: `emoji_panel.dart`, `call_screen.dart` | §14-§22, §23-§40, §41-§57 |
| `gui_settings_and_dialogs.md` | §14-§22 | `settings_screen.dart`, NEW: `media_viewer.dart`, `create_group_wizard.dart` | §1-§4, §8-§13, §23-§40, §41-§57 |
| `gui_features_23_40.md` | §23-§40 | NEW files: `contacts_screen.dart`, `calls_history.dart`, `passcode_screen.dart`, etc. | §1-§4, §8-§13, §14-§22, §41-§57 |
| `gui_features_41_57.md` | §41-§57 | NEW files: `formatting_menu.dart`, `drag_drop_overlay.dart`, `ghost_mode.dart`, etc. | §1-§4, §8-§13, §14-§22, §23-§40 |

**CRITICAL WARNINGS FOR RALPH:**
- §3 "Settings Sections" in the spec is a REFERENCE to what the Settings PAGE (§14) contains. Do NOT add settings rows to the hamburger drawer. Settings live in `settings_screen.dart`.
- Each checklist item references a spec section (e.g., "spec §5.2"). READ that full spec section before implementing — it has all the pixel dimensions, colors, and behavior details.
- For each item: implement it → build → self-test with `flutter_inspect.sh screenshot` + `flutter_interact.sh` → mark done.

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
