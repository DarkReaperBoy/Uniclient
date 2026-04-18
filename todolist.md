# UniClient — TODO

**FOCUS: Telegram GUI only.** Do NOT work on other cores (Bale, Rubika, Matrix, XMPP, IRC, Delta Chat, GitHub, Mumble, TeamSpeak) until the human explicitly says so.

Top-to-bottom execution order. Remove items when done.

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

### 2a. Telegram (reference implementation)
- Read `go/cores/telegram.go` — catalog every feature
- Chat list sidebar — folder tabs, search, pinned, archived, account switcher
- Message area — bubbles, replies, edits, forwards, reactions, read receipts
- Media — photos, videos, documents, voice/video messages, stickers, GIFs
- Info panel — member list, shared media, chat actions
- Topics — topic groups with per-topic message loading
- Calls — voice/video call UI
- Mobile-responsive — single-panel narrow, multi-panel wide

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
