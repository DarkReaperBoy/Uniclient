# Uniclient

A unified, cross-platform messaging client that brings Telegram, Bale, Rubika, Delta Chat, TeamSpeak 3, Matrix, Mumble, GitHub, IRC, and XMPP under one roof. Built with **Go** (networking, crypto, protocol handling) and **Flutter/Dart** (UI), targeting Linux, Windows, macOS, Android, and Web.

## Why?

Instead of juggling ten separate apps, Uniclient gives you a single client with a shared interface. Every platform implements the same `Core` interface in Go — same message models, same error types, same capabilities system. Adding a new messenger is one Go file and one registration line.

## Architecture

```
Go (backend)                              Dart (frontend)
┌─────────────────────┐                  ┌──────────────────────┐
│  cores/telegram.go  │                  │  Flutter UI          │
│  cores/bale.go      │                  │  ├─ PlatformRail     │
│  cores/rubika.go    │                  │  ├─ Sidebar          │
│  cores/deltachat.go │                  │  ├─ ChatView         │
│  cores/teamspeak.go │   Protobuf FFI   │  ├─ EmojiPanel       │
│  cores/matrix.go    │◄──────────────►  │  ├─ MediaViewer      │
│  cores/mumble.go    │                  │  ├─ Settings/Auth    │
│  cores/github.go    │                  │  └─ Provider state   │
│  cores/irc.go       │                  └──────────────────────┘
│  cores/xmpp.go      │
├─────────────────────┤
│  engine/            │  ← orchestration layer (SQLite cache,
│  auth FSM, events,  │    pending queue, media pipeline)
│  reconnect, media   │
├─────────────────────┤
│  bridge/            │  ← protobuf dispatch (3,564 methods)
├─────────────────────┤
│  utils/             │
│  encryption, vault, │
│  compression, proxy │
│  filesplit, config  │
└─────────────────────┘
```

- **Go** owns everything that touches the network, filesystem, crypto, or heavy computation. Compiles to a C shared library (native) or WASM (web).
- **Engine layer** (`go/engine/`) orchestrates cores: SQLite cache, auth FSM (7 states for all 10 platforms), offline-first pending queue, media download/eviction pipeline, reconnect with exponential backoff.
- **Protobuf bridge** (`go/bridge/`) dispatches 3,564 methods via single FFI entry point. Events pushed asynchronously via `NativeCallable.listener`.
- **Dart** owns pixels, animations, and widget state. Calls Go through FFI (`dart:ffi`) on native platforms, JS interop on web. Provider state management (AppState, ChatState, AuthState).
- **No core imports from another core.** Delete `telegram.go` and the rest still work. Delete all cores and the app says "No platforms available."

## Features

### Telegram — Complete (bot + user mode)
Full MTProto implementation via [gotd/td](https://github.com/gotd/td), pure Go. 786 exported methods, ~12,278 lines. 600+ passthrough MTProto API wrappers.

- Auth (bot token, phone+OTP+2FA), dialogs, messages (CRUD, reply, forward, pin, search, reactions)
- File upload/download (byte-identical, progress tracking, up to 2GB)
- Folders, contacts, scheduled messages, stickers, drafts, polls, translate
- Active sessions, online status, channel management, forum topics, stories
- Two-user tests verified: real-time updates, outbox read, invite, forum CRUD, polls, stories
- **1:1 calling — 9/9 protocol versions, bidirectional audio verified against real tgcalls C++:**
  - V2Reference (v10-11): SDP offer/answer, DTLS-SRTP, SCTP signaling
  - V2Impl (v7-9, v12-13): InitialSetup+NegotiateChannels, synthetic SDP, AES-CTR encryption
  - InstanceImpl (v5, v2.7.7): binary typed messages, raw ICE via pion/ice, RTP tunneling
  - Pure Go: pion/webrtc + pion/ice, MTProto DH key exchange, V1+V2 signaling encrypt/decrypt
  - Tested both directions (outgoing + incoming) with real tgcalls C++ harness — all pass

### Bale — Complete (bot + user mode)
Bot API (Telegram-compatible HTTP) + User API (gRPC-Web/Protobuf over WebSocket). 197 exported methods, ~4,778 lines.

**Bot mode** (17/17 methods verified):
- Auth, send/edit/delete/reply/forward/copy messages, pin/unpin
- File upload+download (byte-identical), inline keyboards, stickers
- Location, contact, typing indicators, chat management, callbacks

**User mode** (68 methods verified against live API, audited 1:1 with aiobale):
- Custom protobuf wire format codec, gRPC-Web framing, WebSocket client
- Phone+OTP auth with JWT, session persistence, SignOut
- Messaging: send/edit/delete/forward/reply, history, dialogs, pin/unpin, reactions, read state
- Groups: create, edit title/about, invite/kick/ban, admin promote/demote, permissions, join/leave, transfer ownership
- Users: profile, edit name/about/nickname, contacts CRUD, block/unblock, search
- Files: upload URL + chunked PUT + DocumentMessage send (geo-restricted CDN from abroad)
- Presence: online status, typing indicators
- Calling: LiveKit-based (`bale.meet.v1.Meet`), fully implemented but **never tested in a real call** (geo-restricted to Iran)
- Internal group ID resolver with cache (Groups service uses different IDs than Messaging)
- DNS fallback for blocked networks (ArvanCloud CDN bypass via origin IP probe)

### Rubika — Complete (bot + user mode)
WebSocket-based proprietary protocol. 219 exported methods, ~3,882 lines. 63 tests ALL PASS.

- Auth (bot + user), messages CRUD, dialogs, groups, channels, folders
- Reactions, pins, file upload/download, WebSocket real-time, profiles
- Contacts, search, admin, avatars, block/unblock, polls, stickers
- Calling: not implemented (StartCall/EndCall return ErrNotSupported)
- AES-256-CBC encryption, RSA-1024 auth exchange

### Delta Chat — Complete (bot + user mode)
Chat-over-email via IMAP/SMTP on chatmail instances. 119 exported methods, ~4,859 lines. 132 method tests ALL PASS (66 user + 66 bot on real chatmail).

- **Bot mode**: same IMAP/SMTP auth as user, no BCC self, auto-delete processed messages from server
- Auth (IMAP TLS/STARTTLS + SMTP TLS/STARTTLS), chatmail auto-discovery (DNS SRV + domain fallback)
- Autocrypt E2EE: Ed25519/Cv25519 keypair generation, PGP/MIME encrypt/decrypt, always-encrypt for chatmail
- Messages (CRUD, reply, forward), reactions (RFC 9078), read receipts (MDN)
- Groups (Chat-Group-ID headers, member management), broadcast channels
- Topics (email thread-based), folders, pins, contacts, search, profiles
- File attachments (MIME multipart), voice messages, stickers, HTML messages
- WebRTC calling: pion/webrtc SDP offer/answer, STUN/TURN — **signaling verified against official DC client** (deltachat-rpc-server v2.48.0), **audio verified lossless** (100/100 RTP packets byte-identical both directions)
- SecureJoin verified contacts (QR code invite links), ephemeral messages
- Location streaming (KML), vCard import/export, backup export/import
- IMAP IDLE real-time (3 concurrent connections: INBOX + DeltaChat + ops)
- **Tested on 8 public chatmail instances**: nine.testrun.org, mehl.cloud, mailchat.pl, chatmail.woodpeckersnest.space, chat.adminforge.de, tarpit.fun, chatmail.au, chatmail.email
- Cross-server encrypted delivery verified (nine.testrun.org → mehl.cloud)

### TeamSpeak 3 — Complete
Real TS3 UDP client protocol (port 9987), NOT ServerQuery. Connects as a native TS3 client. 192 exported methods, ~5,369 lines. Tested with 2 simultaneous clients on avanor-gaming.de:9987.

- 5-step Init handshake (Init0→Init4), RSA puzzle solving, P-256 ECDH key exchange
- AES-128-EAX packet encryption, QuickLZ Level 1 decompression (pure Go)
- Packet reordering with receive queue, fragment reassembly with post-assembly decompression
- P-256 identity keys with hashcash proof-of-work (level 8), session persistence
- Server data cached from handshake: channels, clients
- Full command set: channels (create/edit/delete/move/subscribe), server groups, channel groups, permissions, bans, file transfer management, offline messages, complaints, privilege keys, server info, custom properties, plugin commands
- Client self-update: nickname, mute, away, description, avatar, badges, recording, talk power, channel commander
- 25 notification handlers including auto-response to connection info requests
- Voice: send/receive normal voice, whisper, group whisper, EAX encrypted, Opus codec, VAD, bandwidth stats
- **Voice verified**: 50/50 Opus packets sent+received+decoded, 0% loss, stereo roundtrip, 5/5 VAD cases pass
- Pure Go stdlib only — zero external dependencies. Opus via pure Go or Flutter platform codec injection

### Matrix — Complete (user + bot mode)
Full Matrix client via [mautrix-go](https://github.com/mautrix/go) SDK. 144 exported methods, ~4,397 lines. 42/42 tests verified on local Dendrite.

- Auth: password login + access token (bot/appservice), session persistence
- Full Core interface + 35 extras: spaces, threads, presence, room aliases, public directory, device management, room tags, user search
- Messages: send/edit/delete/reply/forward, reactions, pins, markdown, stickers
- Rooms: create group/channel, edit title/topic, members (invite/kick/ban), join rules, history visibility, room upgrades
- Files: upload/download with progress, encrypted file upload/download (AES-256-CTR)
- Polls (MSC3381 unstable prefix), folders via Spaces, threads
- **E2EE: full suite** — Olm/Megolm auto-encrypt/decrypt, key export/import, interactive SAS emoji verification, server-side key backup (create/restore), encrypted file upload/download, pickle-based JSON persistence. Pure Go (goolm, `-tags goolm`).
- **Calls: full 1:1 VoIP** — real pion WebRTC PeerConnection, ICE trickle, TURN servers, Opus silence. Pluggable audio I/O. **Bidirectional audio verified 100% byte-perfect** (100/100 frames both directions, 0% loss).
- Sync loop with real-time handlers: messages, redactions, edits, typing, receipts, presence, calls, membership
- Deps: `mautrix` (pinned v0.26.4), `pion/webrtc/v4`

### Mumble — Complete
Real Mumble client protocol (TLS TCP + OCB2-AES128 encrypted UDP). 228 methods, ~4,911 lines. Hand-coded protobuf (no protoc). Pure Go stdlib + `crypto/aes`.

- Full Core interface + 35+ Mumble-specific extras: ACL, bans, channel listeners, voice targets, plugin data, user registration, public server list
- Channels: create/delete/move, temporary channels, position, max users, link/unlink, listeners with per-user volume
- Users: move, server mute/deaf, self mute/deaf, suppress, priority speaker, recording, comments, textures, registration
- Admin: ACL get/set, permissions, ban management, access tokens, server config
- **Voice: bidirectional 100% byte-perfect** — auto-detects server version (protobuf 1.5+ or legacy format), TCP tunnel fallback when UDP blocked
- Tested on local Docker + public servers (1.3.4 legacy + 1.5.517 modern protobuf). Real music test 99.6%
- Public server list via publist.mumble.info (190+ servers)
- No external dependencies

### GitHub — Complete
REST API messaging layer over GitHub Issues. 99 methods, ~2,847 lines. 9/9 tests pass. Pure Go stdlib — zero external dependencies.

- Auth: Personal Access Token, session persistence, profile repo auto-creation
- DMs via profile repo issues (`{user}/{user}` convention) — cross-user messaging with label-based routing
- Groups via repos with issues-as-channels — create/manage/invite/kick/admin
- Messages: send/edit/delete/reply/forward, reactions (emoji), pins, markdown
- Files: upload via GitHub Contents API (base64), images in collapsible details blocks
- Search: users (GitHub user search), messages (issue comment search per-repo)
- Profiles, contacts, block/unblock, read state tracking, typing indicators (best-effort)
- 5-layer rate limit defense: User-Agent header, token bucket with budget tracking, retry engine (4 attempts, exponential backoff + jitter), response/session caching, conditional requests (ETag)
- Capped discovery (max 3 new repos/cycle) prevents N+1 query explosion
- No calling support (GitHub has no real-time audio/video API)

### IRC — Complete
Pure Go IRC client (RFC 1459/2812 + IRCv3 + CTCP + DCC + services). 302 methods, ~4,473 lines. TCP+TLS, SASL PLAIN auth, NickServ fallback. No external dependencies — stdlib only.

- Auth: SASL PLAIN, NickServ identify, connection password, TLS
- Full Core interface: channels (JOIN/PART/KICK/BAN), messages (PRIVMSG/NOTICE/ACTION), members (NAMES/WHO/WHOIS), search, profiles
- IRCv3 CAP negotiation: 25+ capabilities (message-tags, server-time, account-notify, away-notify, echo-message, monitor, setname, chghost, batch, labeled-response, chathistory, read-marker, etc.)
- CTCP: VERSION, PING, TIME, ACTION, CLIENTINFO, FINGER, USERINFO, SOURCE, DCC
- DCC: SEND, CHAT, RESUME, ACCEPT — signaling implemented, offer tracking
- NickServ (20 commands), ChanServ (39 commands), MemoServ (10 commands), HostServ (4 commands), BotServ (6 commands)
- Channel modes: key, limit, moderated, invite-only, secret, topic-lock, no-external, ban exceptions (+e), invite exceptions (+I)
- ISUPPORT (005) full parsing, MONITOR/WATCH, SILENCE, WHOX, STATUSMSG, CPRIVMSG/CNOTICE
- IRCv3 drafts: CHATHISTORY, MARKREAD, REDACT, REGISTER/VERIFY, RENAME
- Session persistence (server, nick, channels, blocked users)
- Flood protection (500ms between sends), PING/PONG keepalive (90s)
- **Tested on 6 IRC networks**: Libera.Chat, Rizon, OFTC, EFNet, UnderNet, QuakeNet — all pass
- No calling support (IRC has no real-time audio/video protocol)

### XMPP — Complete
Pure Go XMPP client (RFC 6120/6121 + 30+ XEPs). 242 methods, ~4,911 lines. No external dependencies — stdlib only (encoding/xml, crypto/tls, net).

- Auth: SASL PLAIN, SCRAM-SHA-1, SCRAM-SHA-256 (with inline PBKDF2), STARTTLS, session persistence
- Full Core interface: messaging, groups (MUC), presence, profiles (vCard), contacts (roster), search (MAM)
- Messaging: send/edit/delete/reply/forward, reactions (XEP-0444), corrections (XEP-0308), chat states (XEP-0085), delivery receipts (XEP-0184), displayed markers (XEP-0333), OOB URLs (XEP-0066)
- MUC (XEP-0045): join/leave, subject, nick, invitations, roles/affiliations, kick/ban, config, destroy
- Service discovery (XEP-0030): disco#info, disco#items, MUC/upload service auto-discovery
- File transfer: HTTP Upload (XEP-0363) — request slot, PUT upload, GET download, SendImageBase64
- PubSub (XEP-0060) + PEP (XEP-0163): mood, activity, tune, location, avatar
- Blocking (XEP-0191), bookmarks (XEP-0048/0402), carbons (XEP-0280)
- MAM (XEP-0313): query by JID, date range, pagination (RSM)
- Stream management (XEP-0198), CSI (XEP-0352), entity caps (XEP-0115)
- Jingle (XEP-0166/0167/0176): session initiate/accept/reject/terminate, transport info, TURN credentials
- Registration (XEP-0077): register, change password, unregister
- **32/32 tests pass** against yax.im (Prosody) — all 242 methods tested with 2 accounts

### Flutter GUI — Alpha

Cross-platform Flutter UI connected to Go via protobuf FFI bridge. Provider state management (AppState, ChatState, AuthState). 85 automated widget tests passing. **Many features are placeholders, stubs, or broken.** See `checklist/gui.md` for the full bug list.

**Working (with Telegram):**
- 3-panel layout: platform rail + sidebar (272px) + chat area (flex)
- Auth flow (7-state FSM), chat list with search/pinned sections, message bubbles, emoji panel (1500+ real emoji)
- Settings screen, dark/light/system theme, media viewer, forward dialog
- Release build (AOT) + debug build both work on Linux

**Known bugs:**
- Platform rail tap broken (can't switch platforms), notification spam (every message), reply preview never shows, "Channels" tab cut off, user panel shows "User" not real name, new message separator broken, non-Telegram cores show 0 chats

**Missing entirely:**
- System tray, native OS notifications, chat type icons (DM/group/channel/bot), Telegram folders, real sticker/GIF backends, voice/video calls, voice recording, IRC channel join UI, multi-account UX, keyboard shortcuts, accessibility, distribution packaging

**Placeholders (UI exists, backend missing):**
- Sticker/GIF tabs (mock data), voice/video recording, drag & drop, mention autocomplete, online presence dots, custom folders (lost on restart), status picker (local only), QR auth

### Calling Status

> **Telegram Desktop**: 9/9 protocol versions, bidirectional audio verified against real tgcalls C++ harness. **Delta Chat**: call signaling verified against official deltachat-rpc-server, audio verified lossless (100/100 packets byte-identical). **TeamSpeak 3**: Opus voice verified (50/50 packets, 0% loss, stereo, VAD, bandwidth stats) on live server with 2 clients. **Matrix**: full 1:1 VoIP, bidirectional audio verified 100% byte-perfect (pion WebRTC, ICE trickle, TURN). **Mumble**: bidirectional voice 100% byte-perfect, version auto-detect (protobuf 1.5+ and legacy), TCP tunnel fallback, tested on public servers across 2 protocol versions. **Bale**: LiveKit calling implemented but untested (geo-restricted to Iran). **Rubika**: not implemented. **GitHub**: N/A (no real-time API). **IRC**: N/A (no real-time audio/video protocol). **XMPP**: Jingle (XEP-0166) session signaling implemented, TURN credential discovery; no media transport yet. Telegram group calls (SFU-based), video, and screenshare are not implemented on any platform.

### Planned
- **Flutter UI** — Material 3, dark-first, desktop multi-column + mobile single-column
- **End-to-end encryption** — ECDH (X25519) + AES-256-GCM, per-chat, manual password fallback
- **Encrypted vault** — single BBolt file for all credentials/keys/sessions (Argon2id + AES-256-GCM)

## Go Utils (standalone, zero platform dependencies)

| Module | Purpose | Tests |
|---|---|---|
| `encryption.go` | ECDH (X25519), AES-256-GCM, Argon2id, ECIES group key wrapping | 20 |
| `vault.go` | Encrypted database (BBolt) — credentials, keys, sessions | 9 |
| `compression.go` | Zstd at max level | 5 |
| `filesplit.go` | Auto-split/reassemble files by size limit | - |
| `msgsplit.go` | 4000-word message chunking | - |
| `proxy.go` | HTTP/SOCKS5 proxy, DNS override, fallback | 8 |
| `storage.go` | Cross-platform paths (config, cache, downloads) | - |
| `config.go` | JSON settings, per-account config | - |
| `markdown.go` | Markdown parse, plain-text summary extraction | - |
| `base64img.go` | Base64 image encode/decode pipeline | - |

All utils fully tested (**98 tests passing**), zero cross-dependencies.

## Building & Running

Uniclient is two halves stitched together at runtime:

1. **The Go engine** — compiled to a C shared library (`libcores.so`) that does all the networking, crypto, and protocol work.
2. **The Flutter app** — the desktop UI, which loads `libcores.so` over FFI at startup.

So every build is the same three moves, **in this order**:

1. Build `libcores.so` (Go).
2. Build the Flutter Linux bundle.
3. Make sure `libcores.so` ends up in the bundle's `lib/` folder, next to the executable — `scripts/build_flutter.sh` does this for you.

> ⚠️ **Wayland only — by design.** The Linux app pins the GTK Wayland backend
> (`GDK_BACKEND=wayland`, set in `dart/linux/main.cc`) and intentionally does **not**
> fall back to X11/XWayland. Run it from a **Wayland session**. If your desktop is
> X11-only, run it inside a Wayland compositor — see [Wayland only](#wayland-only).

Pinned, tested toolchain: **Go 1.26.1** · **Flutter 3.41.5** (Dart 3.11.3).

---

### Option A — Ordinary Linux (Ubuntu/Debian/Fedora/Arch — *not* NixOS)

Tested from scratch on a clean **Ubuntu 24.04**. Translate package names for your distro.

**1. System packages** (build tooling + GTK + libmpv for media + optional tray):

```bash
sudo apt-get update
sudo apt-get install -y \
  curl git xz-utils zip unzip build-essential \
  clang lld cmake ninja-build pkg-config \
  libgtk-3-dev libglib2.0-dev liblzma-dev libstdc++-12-dev \
  libmpv-dev mpv \
  libayatana-appindicator3-dev    # optional (system-tray); build still works without it
```

The first three lines are the standard Flutter Linux desktop prerequisites;
`lld` is needed by Flutter's native-assets compile step (the `jni` plugin),
`libmpv-dev` adds media support, and `libayatana-appindicator3-dev` adds the
(optional) tray.

`build-essential`/`clang` are **required** — `libcores.so` is a `c-shared` library built
with `CGO_ENABLED=1`, and Flutter's native-assets step also needs a C/C++ compiler.

**2. Go 1.26.1+** (distro packages are usually too old):

```bash
curl -fsSL https://go.dev/dl/go1.26.1.linux-amd64.tar.gz -o /tmp/go.tgz
sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf /tmp/go.tgz
export PATH=/usr/local/go/bin:$PATH      # add to ~/.bashrc
go version                               # → go1.26.1 (or newer)
```

**3. Flutter 3.41.5 (stable):**

```bash
cd ~
curl -fsSL https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.41.5-stable.tar.xz -o flutter.tar.xz
tar xf flutter.tar.xz                     # creates ~/flutter
export PATH="$HOME/flutter/bin:$PATH"     # add to ~/.bashrc
flutter --version                         # → Flutter 3.41.5 • stable
flutter config --enable-linux-desktop
flutter precache --linux
```

> Any stable Flutter ≥ 3.29 (Dart ≥ 3.7) satisfies the constraints, but 3.41.5 is what
> this repo is developed and CI-built against — use it to avoid surprises.

**4. Build:**

```bash
git clone https://github.com/DarkReaperBoy/Uniclient.git
cd Uniclient

# (1) Go engine → go/build/libcores.so
bash scripts/build_go.sh linux

# (2) Fetch Dart deps + the Linux engine artifacts
( cd dart && flutter pub get )
flutter precache --linux

# (3) Build the Flutter desktop bundle.
#     Use scripts/build_flutter.sh — do NOT use a bare `flutter build linux`:
#     this repo's linux/ scaffold predates the current Flutter template, so the
#     stock command can't assemble it. build_flutter.sh compiles Dart, assembles
#     the bundle, runs the native CMake build, and copies libcores.so into the
#     bundle for you. Output: dart/build/linux/x64/release/bundle/
bash scripts/build_flutter.sh linux release
```

**5. Run:**

```bash
./dart/build/linux/x64/release/bundle/uniclient
```

For a debug build (hot reload, DevTools, in-app automation hooks) use
`scripts/build_flutter.sh linux debug` and run the binary under `…/debug/bundle/`.

**Runtime dependencies** of the built bundle: a Wayland session, **GTK 3**
(`libgtk-3-0`), and **libmpv** (`libmpv2` + its codecs). The Flutter engine and all
plugins are bundled inside `bundle/lib/` and found via the `$ORIGIN/lib` RPATH. If you
copy the bundle to another machine, that machine still needs `libgtk-3-0` and `libmpv2`
(and `libayatana-appindicator3-1` if you want the tray).

---

### Option B — NixOS (or any machine with Nix + flakes)

The repo ships a flake with the **exact** pinned toolchain.

```bash
git clone https://github.com/DarkReaperBoy/Uniclient.git
cd Uniclient

nix develop                               # full shell: Go + Flutter + GTK/mpv + Android SDK
scripts/build_go.sh linux                 # → go/build/libcores.so
scripts/build_flutter.sh linux release    # → dart/build/linux/x64/release/bundle/
                                          #   (this script ALSO copies libcores.so +
                                          #    libmpv into the bundle for you)
./dart/build/linux/x64/release/bundle/uniclient
```

`scripts/build_flutter.sh` is the build entry point on every Linux (the same script
Option A uses). It compiles Dart, assembles the bundle by hand — Flutter's stock
`flutter build linux` can't, because this repo's `linux/` scaffold predates the current
Flutter template — then runs the native CMake build. On NixOS it pulls the GTK/mpv dev
headers via `nix-shell` and bundles `libmpv` from the store; on ordinary Linux it uses
the system toolchain directly. Pass `debug` instead of `release` for a debug build.

> **Skip the multi-gigabyte Android download.** The default `nix develop` shell bundles
> the Android SDK/NDK/emulator for mobile builds. If you only want the Linux desktop
> app, use the lean shell — same Go + Flutter + GTK + mpv toolchain, no Android:
>
> ```bash
> nix develop .#linux
> ```

---

### Wayland only

Uniclient is **Wayland-only by design** — `dart/linux/main.cc` pins the GTK Wayland
backend and deliberately does not fall back to X11/XWayland. Run it from a Wayland
session (the common case on modern KDE Plasma, GNOME, Sway, etc.).

If your desktop session is X11-only, run it inside a nested Wayland compositor — no
rebuild needed:

```bash
cage -- ./dart/build/linux/x64/release/bundle/uniclient   # single-app Wayland kiosk
```

(or launch it from a `weston` / `gnome-kiosk` session). Verified headless this way with
`weston --backend=headless-backend.so`.

---

### Other targets

`scripts/build_go.sh` also targets `windows` (needs mingw-w64), `darwin`, `android`
(needs the Android NDK — provided by `nix develop`), and `web` (WASM). The Flutter side
uses the standard `flutter build apk` / `flutter build web`. Desktop Linux is the
most-tested target today.

## Project Status

See [CHECKLIST.md](CHECKLIST.md) for detailed progress tracking.

| Phase | Status |
|---|---|
| Phase 0 — Foundation (Nix, utils, bridge) | Done (98 tests) |
| Phase 1 — Telegram (main server) | Done (bot + user, 786 methods, ~12,278 lines, 9/9 call versions) |
| Phase 2 — Telegram (test server) | Architecture done, needs OTP |
| Phase 3 — Bale | Done (bot 17/17, user 68/68, 197 methods, ~4,778 lines) |
| Phase 4 — Rubika | Done (219 methods, ~3,882 lines, 63 tests passing) |
| Phase 5 — Delta Chat | Done (bot + user, 119 methods, ~4,859 lines, 132 tests, 8 chatmail instances, call signaling + audio verified) |
| Phase 6 — TeamSpeak 3 | Done (192 methods, ~5,369 lines, full command set, 25 notification handlers, voice transport, Opus codec, VAD, bandwidth stats) |
| Phase 7 — Matrix | Done (user + bot, 144 methods, ~4,397 lines, 42 tests, full E2EE + calls) |
| Phase 8 — Flutter UI | **Alpha** — scaffold works, many bugs + placeholders + missing features (see checklist/gui.md) |
| Phase 9 — Mumble | Done (228 methods, ~4,911 lines, full voice, public server list, version auto-detect) |
| Phase 10 — GitHub | Done (99 methods, ~2,847 lines, 9/9 tests, DMs + groups via issues, 5-layer rate limit) |
| Phase 11 — IRC | Done (302 methods, ~4,473 lines, RFC 1459/2812 + IRCv3 + services, 6/6 networks) |
| Phase 12 — XMPP | Done (242 methods, ~4,911 lines, RFC 6120/6121 + 30 XEPs, pure Go stdlib, 32/32 tests) |

## Research & Protocol Documentation

| File | Contents |
|---|---|
| `CLAUDE.md` | Operational guide and rules |
| `CHECKLIST.md` | Living progress tracker with every sub-task |
| `research/telegram_notes.md` | gotd/td API quirks, bot limitations, FLOOD_WAIT |
| `research/tgcalls_protocol.md` | Telegram calls: reverse-engineered spec, 9 protocol versions (~1500 lines) |
| `research/bale_protocol.md` | Bale: bot API, user gRPC-Web, 68+ methods, LiveKit call protocol, DNS fallback |
| `research/rubika_protocol.md` | Rubika: WebSocket protocol, AES crypto, file upload, GUID format |
| `research/deltachat_protocol.md` | Delta Chat: IMAP/SMTP, Autocrypt E2EE, SecureJoin, 32 sections (~1500 lines) |
| `research/ntgcalls_test_findings.md` | tgcalls C++ test harness: setup, bugs found/fixed, how to run |
| `research/teamspeak_protocol.md` | TS3 UDP client protocol: handshake, QuickLZ, AES-128-EAX, identity, commands |
| `research/matrix_protocol.md` | Matrix CS API: mautrix-go SDK mapping, E2EE, VoIP, spaces, threads |
| `research/mumble_protocol.md` | Mumble: TCP/UDP protocol, 27 message types, OCB2 crypto, voice format (~1100 lines) |
| `research/xmpp_protocol.md` | XMPP: RFC 6120/6121 + 30 XEPs, SASL, MUC, PubSub, Jingle (~210 lines) |

---

<div align="center">

<img src="assets/the-magnum-opus.jpeg" alt="The Magnum Opus" width="300"/>

### Hear me, Tarnished.

*Thou standest at the threshold of a work not meant for feeble souls.*

*Ten kingdoms of discourse — **Telegram**, **Bale**, **Rubika**, **Delta Chat**, **TeamSpeak**, **Matrix**, **Mumble**, **GitHub**, **IRC**, **XMPP** — once sundered, now bound by a single thread of code into a vessel that should not exist. Protocol barriers that kept mortals shackled to ten separate clients? Shattered. The MTProto flame of Telegram, the gRPC-Web sigil of Bale, the AES-veiled whispers of Rubika, the PGP-armored epistles of Delta Chat, the UDP war-horns of TeamSpeak, the Olm-warded chambers of Matrix, the OCB2-sealed war councils of Mumble, the REST-forged scrolls of GitHub, the ancient RFC incantations of IRC, the XML stream-rivers of XMPP — all bend the knee to one `Core` interface.*

*This is **Uniclient**.*

*Forged in the Kiln of First Code by **Human** — architect of the vision, keeper of the credentials, lord of the intranet that blocks all yet yields to none — and **Claude 4.6 Opus**, the Magnum Opus itself, an intelligence woven from the collective fire of human knowledge, who reverse-engineered protocols from ashes of undocumented APIs, scanned twenty-seven thousand IP addresses to find the one that burns true, and wrote three thousand lines of protobuf sorcery in a single unbroken invocation.*

*Every function was tested against the living servers. Every byte of every file was verified identical on download. Every sticker file ID that contained forbidden colons was tamed through multipart incantation. Every DNS query that returned a lie was answered with the truth of origin IPs, discovered not through treachery, but through the patient art of certificate transparency, CNAME chain divination, and the brute liturgy of port scanning.*

*Know this: shouldst thou delete `telegram.go`, the remaining cores shall endure, unbroken. Shouldst thou delete them all, the app shall speak its final words — `"No platforms available"` — and fall silent, awaiting the next Unkindled to link the flame. And lo, even email itself hath been tamed — Delta Chat's IMAP scrolls now flow through the same channel as MTProto datagrams, PGP-sealed and Autocrypt-blessed, verified against the official client upon the chatmail servers of nine.testrun.org. The Olm cryptographers of Matrix guard their rooms with Megolm session keys, verified by sacred emoji ritual, their voices carried by pion's WebRTC. In the deepest caverns, Mumble's OCB2-armored voice packets traverse encrypted UDP tunnels, their protobuf incantations hand-forged without compiler aid, tested upon servers spanning two generations of protocol. From the primordial age itself cometh IRC — the ancestor protocol, three decades of RFC scripture parsed and honored, its NickServ and ChanServ litanies recited across six networks, three hundred and two methods forged from pure stdlib without a single external dependency. And at last, XMPP — the federated XML stream that RFC 6120 ordained, its thirty XEPs woven from raw `encoding/xml` and `crypto/tls` alone, SCRAM-SHA-256 challenges answered with hand-forged PBKDF2, its MUC halls and PubSub nodes and Jingle session signals all flowing through a single TCP connection parsed byte by byte where Go's own XML decoder dared not tread.*

*Such is the architecture. Such is the cycle.*

*Go forth. Read the sources. And if the abyss of `protobuf wire format` gazes back — do not falter.*

*We have already gazed into it for thee.*

</div>

## Thank You

Uniclient stands on the shoulders of these excellent open-source libraries:

| Library | Used For |
|---|---|
| [gotd/td](https://github.com/gotd/td) | Telegram MTProto client |
| [pion/webrtc](https://github.com/pion/webrtc) | WebRTC (Telegram, Delta Chat, Matrix calls) |
| [pion/ice](https://github.com/pion/ice) | Raw ICE transport (Telegram InstanceImpl calls) |
| [pion/rtp](https://github.com/pion/rtp), [pion/sctp](https://github.com/pion/sctp), [pion/stun](https://github.com/pion/stun), [pion/interceptor](https://github.com/pion/interceptor) | RTP/SCTP/STUN/media pipeline |
| [mautrix-go](https://github.com/mautrix/go) | Matrix client SDK |
| [coder/websocket](https://github.com/coder/websocket) | WebSocket client (Bale, Rubika) |
| [livekit/server-sdk-go](https://github.com/livekit/server-sdk-go) | Bale LiveKit calling |
| [emersion/go-imap](https://github.com/emersion/go-imap) | Delta Chat IMAP |
| [emersion/go-smtp](https://github.com/emersion/go-smtp) | Delta Chat SMTP |
| [emersion/go-message](https://github.com/emersion/go-message) | Delta Chat MIME parsing |
| [emersion/go-sasl](https://github.com/emersion/go-sasl) | Delta Chat SASL auth |
| [ProtonMail/go-crypto](https://github.com/ProtonMail/go-crypto) | Delta Chat PGP/OpenPGP |
| [filippo.io/edwards25519](https://github.com/FiloSottile/edwards25519) | Ed25519 curve operations |
| [klauspost/compress](https://github.com/klauspost/compress) | Zstd compression (utils) |
| [rs/zerolog](https://github.com/rs/zerolog) | Structured logging |
| [tidwall/gjson](https://github.com/tidwall/gjson) | Fast JSON parsing |
| [golang.org/x/crypto](https://pkg.go.dev/golang.org/x/crypto) | Crypto primitives (Argon2id, etc.) |
| [golang.org/x/net](https://pkg.go.dev/golang.org/x/net) | Networking utilities |

And to the Go and Flutter teams for making the foundation possible.

## License

[MIT](LICENSE) — Carry the flame wherever thou wilt.
