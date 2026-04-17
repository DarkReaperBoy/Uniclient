# UniClient — TODO

Top-to-bottom execution order. Remove items when done.

## 0a. Docs audit — merge/update/remove/add

Scan ALL `.md` files across the repo: `research/`, `checklist/`, `CLAUDE.md`, `SPEC.md`, `todolist.md`. For each file:
- **Merge** duplicated info (e.g. same protocol notes in two places)
- **Update** stale/outdated content with current state
- **Remove** dead info (completed items still listed, wrong assumptions, obsolete notes)
- **Add** anything missing that was learned but never written down
- **Resolve contradictions** between files

Every doc should **cross-reference** related files (e.g. `telegram_notes.md` links to `tgcalls_protocol.md` where calls are relevant, `gui.md` links to `telegram_desktop_ui.md` sections, `CLAUDE.md` harness table links to research files). When you use a doc in a future session and find it lacking, **update it right then** — don't defer. Docs are living tools, not archives.

While auditing, reduce line count: delete fluff and duplicated wording, but **never delete research findings, rules, or instructions** — just say them more concisely.

Do this BEFORE any feature work. Clean docs = clean sessions.

## 0b. Finish Telegram Desktop UI Spec (`research/telegram_desktop_ui.md`)

Sections 1-49 written (12,251 lines). The remaining sections need to be researched from scratch by sending agents to study the AyuGram Desktop source code (https://github.com/AyuGram/AyuGramDesktop) and appending results to `research/telegram_desktop_ui.md`. Do 3 agents at a time, wait for results, append, repeat.

**Settings screens — ALL DONE:**
- ~~General/My Account settings~~ → §14
- ~~Notifications settings~~ → §15
- ~~Privacy & Security settings~~ → §16
- ~~Data & Storage / Advanced settings~~ → §17
- ~~Folders settings~~ → §18
- ~~Active Sessions / Devices screen~~ → §19
- ~~Power Saving settings~~ → §19
- ~~Language settings~~ → §19
- ~~Chat Settings screen~~ → covered in §14.6 + §54.12
- ~~AyuGram-specific extra settings~~ → §54 (full settings hierarchy)

**Feature screens:**
- ~~Media viewer/lightbox~~ → §20
- ~~Create group/channel wizard flow~~ → §21
- ~~Forum Topics UI~~ → §22
- ~~Scheduled messages UI~~ → §23
- ~~Keyboard shortcuts (full list)~~ → §24
- ~~Theming/color system~~ → §25
- ~~Admin tools~~ → §26
- ~~Passcode lock screen~~ → §27
- ~~2FA setup wizard~~ → §28
- ~~Chat export dialog~~ → §29
- ~~Bot interactions~~ → §30
- ~~Saved messages (sublists, tags)~~ → §31
- ~~Stories UI~~ → §32
- ~~Contacts screen~~ → §33
- ~~Calls history screen~~ → §34
- ~~Empty/error/loading states~~ → §35
- ~~Common dialog/modal patterns~~ → §36
- ~~Desktop notifications~~ → §37
- ~~User profile popup~~ → §38
- ~~Photo/avatar cropping dialog~~ → §39

**Interactions & micro-UI:**
- ~~Send files dialog~~ → §40
- ~~Message formatting toolbar~~ → §41
- ~~Reactions detail popup~~ → §42
- ~~Read receipts detail~~ → §43
- ~~Spoiler animation~~ → §44
- ~~Custom emoji rendering~~ → §45
- ~~Link preview in compose~~ → §46
- ~~Restricted permissions UI~~ → §47
- ~~Drag-and-drop file overlay~~ → §48
- ~~Scroll behaviors~~ → §49
- ~~Instant View~~ — skipped (just a web page loader, not relevant)

**AyuGram-specific features (each needs its own agent):**
- ~~Ghost Mode UI (8 toggles, per-account locks, tray integration)~~ → §51
- ~~Anti-Recall / Message History (deleted message display, edit history viewer, translucent styling)~~ → §52
- ~~Message Filters~~ — skipped (not relevant)
- ~~Streamer Mode~~ — skipped (not relevant)
- ~~Message Shot~~ — skipped (not relevant)
- ~~Forward enhancements~~ → §53
- ~~Ad/clutter removal~~ — skipped (UniClient has no ads)
- ~~AyuGram UI customization~~ → §54

**~~Analytics~~ → §55:**
- ~~Channel/group statistics (follower growth, views, shares, top hours, language pie chart, interactions graph)~~
- ~~Post/message statistics (individual post reach and interactions)~~
- ~~Group stats (member count, message count, top posters/admins/inviters)~~
- ~~Graph rendering (line charts, bar charts, pie charts, time range selector)~~

Skip premium/money/payments/stars/boosts/gifts — no monetary features, not relevant to UniClient.

## ~~1. Delete Old UI~~ DONE

~~Delete `dart/lib/screens/` and `dart/lib/widgets/`. Keep bridge/, state/, models/, proto/, utils/, theme/.~~

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
