# SPEC.md — Unified Multi-Platform Messaging Client Specification

This is the stable project specification. For operational guidance (build commands, current state, rules), see [`CLAUDE.md`](CLAUDE.md).

---

You are building a fully functional, production-grade, cross-platform messaging client supporting Telegram, Bale, Rubika, Delta Chat, TeamSpeak 3, Matrix, Mumble, GitHub, and IRC. Every feature described below must be **completely implemented** — no placeholders, no `// TODO` stubs, no skeleton code, no deferred logic. Every listed detail is a hard requirement.

## Language Split

**Dart** owns the UI, navigation, app state, and widget tree. **Go** owns everything that touches the network, file system, crypto, or heavy computation. The two communicate over a thin FFI bridge — Go compiles to a C shared library (`.so`/`.dll`/`.dylib`), Dart calls it via `dart:ffi` + `package:ffigen`. On web, Go compiles to WASM and Dart calls it via `package:web`/JS interop.

The boundary rule is simple: if it blocks, streams, encrypts, decrypts, compresses, splits, hashes, dials a socket, or reads/writes disk — it's Go. If it paints pixels, animates, or manages widget state — it's Dart.

### Performance Non-Negotiables

- **60fps minimum** on all screens, 120fps where the display supports it. No jank, no dropped frames during scrolling, transitions, or media loading.
- **Lazy everything.** Chat list items, message bubbles, media thumbnails — all built on-demand via `ListView.builder` / `SliverList`. Never load 10,000 messages into memory at once.
- **Isolate-aware.** Heavy Dart-side work (JSON deserialization of large payloads, image decoding) runs on a Dart isolate, not the UI thread.
- **Go goroutines** handle all I/O concurrency. No blocking the bridge. No synchronous FFI calls that take >1ms — if it might be slow, it goes async via the event port.
- **Memory-conscious.** Evict cached images/media outside the visible scroll window. Use `ResizeImage` to decode at display resolution, not full resolution. Stream file uploads/downloads in chunks — never buffer a 2GB file in RAM.
- **Startup < 2 seconds** to first interactive frame (splash → chat list) on a mid-range phone.

### Cross-Platform as a First-Class Constraint

Every line of code, every dependency, every file path, every FFI call must work on **all five targets**: Linux, Windows, macOS, Android, Web. This is not an afterthought — it's a design constraint that applies from day one.

- **Go side**: pure Go only (zero CGo anywhere — CGO_ENABLED=0). Build tags for platform-specific code. `os.UserConfigDir()` / `os.UserCacheDir()` for paths. Test with `GOOS=linux`, `GOOS=windows`, `GOOS=darwin`, `GOOS=android`, `GOOS=js GOARCH=wasm`.
- **Dart side**: only Flutter plugins with declared support for `linux`, `windows`, `macos`, `android`, `web` in their `pubspec.yaml`. If a plugin doesn't support a platform, wrap it with a no-op fallback — never crash.
- **File paths**: always use `path/filepath` (Go) or `path` (Dart) for joins. Never hardcode `/` or `\`. Never assume case sensitivity. Never assume home directory structure.
- **Web target**: no filesystem access — Go's `storage.go` routes to Dart-side IndexedDB via the bridge. No `dart:io` on web — conditionally import `dart:html` / `package:web`.
- **Android**: Dart passes scoped storage paths to Go at init. Go never guesses Android paths.

---

## Project Structure

```
uniclient/
├── flake.nix                 # Nix flake — entire dev/build environment
├── flake.lock
│
├── go/                       # All Go code — compiles to C shared lib + WASM
│   ├── go.mod
│   ├── go.sum
│   ├── bridge/
│   │   └── bridge.go         # Go exports (//export): the FFI surface Dart calls into
│   ├── cores/
│   │   ├── base.go           # Core interface + shared models (Message, Dialog, User, File, etc.)
│   │   ├── telegram.go       # Telegram core (gotd/td MTProto)
│   │   ├── bale.go           # Bale core (custom HTTP client)
│   │   ├── rubika.go         # Rubika core (custom WebSocket client)
│   │   ├── deltachat.go      # Delta Chat core (IMAP/SMTP, pure Go)
│   │   ├── teamspeak.go      # TeamSpeak 3 core (UDP client protocol)
│   │   ├── matrix.go         # Matrix core (mautrix-go SDK, E2EE, VoIP)
│   │   ├── mumble.go         # Mumble core (TLS TCP + OCB2 encrypted UDP)
│   │   ├── github.go        # GitHub core (REST API, issues-as-channels)
│   │   ├── irc.go           # IRC core (RFC 1459/2812 + IRCv3, pure Go)
│   │   └── xmpp.go         # XMPP core (RFC 6120/6121 + XEPs, pure Go)
│   ├── utils/
│   │   ├── encryption.go     # ECDH, AES-256-GCM, Argon2id, keystore, @@ prefix
│   │   ├── compression.go    # Zstd compress/decompress
│   │   ├── filesplit.go      # Auto-split & reassemble files by size limit
│   │   ├── msgsplit.go       # 4000-word message chunking & reassembly
│   │   ├── proxy.go          # HTTP/SOCKS5 proxy, DNS override, fallback
│   │   ├── storage.go        # Cross-platform paths (config, data, cache, downloads)
│   │   ├── config.go         # Settings load/save, per-account config
│   │   ├── vault.go          # Unified encrypted database (BBolt) — all credentials, keys, sessions
│   │   ├── markdown.go       # Markdown parse/render helpers (Go side processing)
│   │   └── base64img.go      # Base64 encode/decode image pipeline
│   └── tests/
│       └── *_test.go         # Integration tests (gitignored)
│
├── dart/                     # Flutter app — UI only
│   ├── pubspec.yaml
│   ├── lib/
│   │   ├── main.dart
│   │   ├── bridge/           # FFI/WASM bridge to Go
│   │   ├── models/           # Dart mirrors of Go's shared models
│   │   ├── state/            # App & chat state management
│   │   ├── screens/          # All screens (splash, login, chat_list, chat, settings, search)
│   │   └── widgets/          # Reusable widgets (message_bubble, chat_tile, lock_button, etc.)
│   ├── linux/ windows/ macos/ android/ web/
│
├── research/                     # Protocol specs, API quirks, research notes
├── auth/                     # Credentials & sessions (gitignored)
└── scripts/                  # build_go.sh, run.sh
```

---

## Nix Flake (`flake.nix`)

The flake provides **everything** — no Android Studio, no manual SDK installs. A single `nix develop` drops you into a shell with all tools ready.

### What the flake provides

- **Flutter SDK** (stable channel, pinned version)
- **Go** (1.22+)
- **Android SDK** (command-line tools only — `sdkmanager`, `adb`, platform-tools, build-tools, platform 34, NDK). No Android Studio. The flake sets `ANDROID_HOME`, `ANDROID_SDK_ROOT`, and accepts licenses automatically.
- **Linux desktop build deps**: `gtk3`, `pkg-config`, `cmake`, `ninja`, `clang`, `libepoxy`, standard Flutter Linux requirements.
- **Go build**: `go build -buildmode=c-shared` produces the shared lib using Go's own toolchain (no external C compiler needed at runtime).
- **Web toolchain**: Go WASM compiler support (standard in Go, no extra tools).
- **Development tools**: `go`, `dart`, `flutter`, `protoc` (if needed later), `jq`, `ripgrep`.

### Shell hooks

The `devShell` configures:
- `ANDROID_HOME` / `ANDROID_SDK_ROOT` pointing to the Nix-managed Android SDK.
- `CHROME_EXECUTABLE` for Flutter web dev (if Chromium is available).
- `CGO_ENABLED=0` — zero CGo, pure Go everywhere.
- `LD_LIBRARY_PATH` includes the Go output directory so Flutter can find the `.so` at runtime during development.
- A `build-go` alias that runs `scripts/build_go.sh` for the current platform.

### Build targets

| Target | Go output | Flutter command |
|---|---|---|
| Linux desktop | `libcores.so` (x86_64) | `flutter build linux` |
| Windows desktop | `cores.dll` (x86_64) | `flutter build windows` |
| macOS desktop | `libcores.dylib` (arm64/x86_64) | `flutter build macos` |
| Android | `libcores.so` (arm64-v8a, armeabi-v7a, x86_64 via NDK cross-compile) | `flutter build apk` / `flutter build appbundle` |
| Web | `cores.wasm` + `wasm_exec.js` | `flutter build web` |

The `scripts/build_go.sh` script detects the target platform (or accepts it as an argument) and runs the appropriate `go build` with the right `GOOS`, `GOARCH`, `CC`, and build mode (`-buildmode=c-shared` for native, WASM for web).

---

## FFI Bridge (`go/bridge/` ↔ `dart/lib/bridge/`)

### Go side (`bridge.go`)

Exports C functions via `//export` directives (Go's built-in c-shared buildmode). Every exported function:
- Takes and returns C types only (`*C.char`, `C.int`, `C.int64_t`, byte buffers with length).
- Is **non-blocking from the caller's perspective**: long-running operations (auth, send, download) are dispatched onto Go goroutines internally. Results are delivered back to Dart via a callback mechanism or a shared event channel.
- JSON-encodes complex return types (messages, dialogs, user profiles) as `*C.char` strings. Dart deserializes on its side.
- Errors are returned as JSON `{"error": "...", "code": "..."}` — never panics across the FFI boundary.
- **Before building the Flutter GUI**, replace JSON encoding with **Protocol Buffers**: define `.proto` files for all bridge request/response types, generate Go structs and Dart classes from the same source. This ensures both sides stay in sync — when the schema changes, `protoc` regenerates both languages and the compiler catches every mismatch at build time. No runtime surprises from shape drift.

### Dart side (`ffi_bridge.dart` / `wasm_bridge.dart`)

- `ffi_bridge.dart`: uses `dart:ffi` + `DynamicLibrary` to load the Go shared lib. Generated with `package:ffigen` from a C header that mirrors bridge.go's exports.
- `wasm_bridge.dart`: uses `dart:js_interop` to call the Go WASM module's exported functions.
- `bridge.dart`: conditional export — `ffi_bridge.dart` on native platforms, `wasm_bridge.dart` on web. The rest of the app imports only `bridge.dart` and never knows which backend is active.

### Event stream (Go → Dart)

Real-time updates (new messages, status changes, progress callbacks) flow from Go to Dart via a **port-based callback**:
- On native: Go calls a Dart `NativePort` (`Dart_PostCObject`) to push events. Dart listens via a `ReceivePort`.
- On web: Go WASM calls a JS callback registered at init, which Dart picks up via a `StreamController`.
- All events are JSON-encoded with a `type` discriminator field. Dart deserializes into the appropriate model.

---

## Core / Plugin Architecture (Go side)

Each messenger is a **core** — a Go struct that implements the `Core` interface defined in `cores/base.go`. The bridge layer discovers and initializes available cores at startup.

### Core Interface (`cores/base.go`)

```go
type Core interface {
    // Identity
    Name() string                    // "telegram", "bale", "rubika"
    Capabilities() []string          // ["CALLS", "REACTIONS", "TOPICS", ...]

    // Auth
    Authenticate(cfg AuthConfig) error
    Logout() error                     // full logout: clear session from vault, disconnect, invalidate server-side token

    // Dialogs
    GetDialogs(opts PaginationOpts) ([]Dialog, error)
    CreateGroup(name string, members []string) (*Dialog, error)
    CreateChannel(name string, description string) (*Dialog, error)        // CHANNELS capability
    CreateTopic(chatID string, name string) (*Dialog, error)               // TOPICS capability
    GetFolders() ([]Folder, error)                                         // FOLDERS capability
    CreateFolder(name string, chatIDs []string) (*Folder, error)           // FOLDERS capability

    // Messages
    SendMessage(chatID string, msg OutgoingMessage) (*Message, error)
    GetMessages(chatID string, opts PaginationOpts) ([]Message, error)
    EditMessage(chatID string, msgID string, text string) (*Message, error)
    DeleteMessage(chatID string, msgID string) error
    ReplyToMessage(chatID string, replyToMsgID string, msg OutgoingMessage) (*Message, error)
    ForwardMessage(fromChatID string, msgID string, toChatID string) (*Message, error)
    ReactToMessage(chatID string, msgID string, emoji string) error           // REACTIONS capability
    PinMessage(chatID string, msgID string) error
    UnpinMessage(chatID string, msgID string) error

    // Read state
    MarkAsRead(chatID string, upToMsgID string) error    // marks messages as read up to this ID
    GetReadState(chatID string) (*ReadState, error)      // who has read up to where

    // Files
    UploadFile(chatID string, file FileUpload, progress func(sent, total int64)) (*Message, error)
    DownloadFile(fileRef FileRef, dest string, progress func(recv, total int64)) error

    // Media
    SendImageBase64(chatID string, b64 string, caption string) (*Message, error)  // optional, check Capabilities

    // Calls — 1:1 (CALLS capability)
    StartCall(chatID string, video bool) (*CallSession, error)
    AcceptCall(callID string) (*CallSession, error)
    EndCall(callID string) error
    DeclineCall(callID string) error                          // reject with "busy"
    SetCallMuted(callID string, muted bool) error
    SetCallVideo(callID string, enabled bool) error
    StartScreenShare(callID string) error
    StopScreenShare(callID string) error
    SendAudioFrame(callID string, opusData []byte) error
    SetOnAudioFrame(callID string, handler func([]byte))
    SendVideoFrame(callID string, vp8Data []byte) error      // raw VP8 bitstream
    SendVideoFrameYUV(callID string, yuv []byte, w, h int) error  // encode YUV420P → VP8
    SendScreenFrame(callID string, vp8Data []byte) error
    SendScreenFrameYUV(callID string, yuv []byte, w, h int) error
    SetOnVideoFrame(callID string, handler func([]byte))
    SetOnDecodedVideoFrame(callID string, handler func(yuv []byte, w, h int))
    SetOnDecodedScreenFrame(callID string, handler func(yuv []byte, w, h int))
    SetVideoEncoderFactory(factory func() VideoEncoder)
    SetVideoDecoderFactory(factory func() VideoDecoder)
    StartCallRecording(callID string, filePath string) error
    StopCallRecording(callID string) (int, error)             // returns frame count
    SetAudioFrameDuration(callID string, ms int) error        // 20 or 40
    SetEchoMode(callID string, enabled bool) error
    SendCallRating(callID string, rating int, comment string) error

    // Calls — Group (GROUP_CALLS capability)
    CreateGroupCall(chatID string, title string) (*CallSession, error)
    CreateScheduledGroupCall(chatID string, title string, scheduleDate int) (*CallSession, error)
    StartScheduledGroupCall(callID string) error
    JoinGroupCall(chatID string) (*CallSession, error)
    JoinGroupCallWithVideo(chatID string, video bool) (*CallSession, error)
    LeaveGroupCall(callID string) error
    GetGroupCall(chatID string) (*GroupCallInfo, error)
    SetGroupCallMuted(callID string, muted bool) error
    ToggleGroupCallVideo(callID string, enabled bool) error
    SetGroupCallParticipantVolume(callID string, userID string, volume int) error
    StartGroupCallScreenShare(callID string) error
    StopGroupCallScreenShare(callID string) error
    GetGroupCallStreamRtmpURL(chatID string, revoke bool) (url, key string, err error)
    GetGroupCallStreamChannels(callID string) ([]map[string]int64, error)

    // Profile
    GetProfile(userID string) (*User, error)

    // Real-time
    OnUpdate(handler func(Update))   // registers callback, runs in background goroutine
    Close() error
}
```

The `ReadState` model:
```go
type ReadState struct {
    MyLastRead    string            // message ID I've read up to
    PeerLastRead  map[string]string // userID → message ID they've read up to (DMs: just the peer)
}
```

The `CallSession` model:
```go
type CallSession struct {
    ID          string
    ChatID      string
    IsVideo     bool
    IsGroup     bool
    Participants []CallParticipant
    State       CallState          // Ringing, Active, Ended
}

type GroupCallInfo struct {
    ID              string
    Title           string
    ParticipantCount int
    Participants    []CallParticipant
}
```

The `VideoEncoder` / `VideoDecoder` interfaces (pure Go, injected from Flutter):
```go
type VideoEncoder interface {
    Encode(yuv420p []byte, width, height int) ([]byte, error) // → VP8 bitstream
    ForceKeyframe()
    Close()
}

type VideoDecoder interface {
    Decode(vp8Frame []byte) (yuv420p []byte, width, height int, err error)
    Close()
}
```

A built-in pure Go VP8 keyframe encoder (`go/utils/vp8enc.go`) serves as the default fallback
when no external factory is set. It produces valid RFC 6386 keyframes (14μs per frame, zero CGo)
but with empty image data — sufficient for RTP pipeline testing and PLI response. Production
quality VP8 will come from Flutter platform codecs injected via `SetVideoEncoderFactory`.

**Every core implements the exact same interface.** No core adds public methods outside this contract. Platform-specific features are guarded by `Capabilities()` — Dart checks `capabilities.contains("CALLS")` before showing call UI.

### Shared Models (`cores/base.go`)

All cores return the same Go structs: `Message`, `Dialog`, `User`, `File`, `Update`, `AuthConfig`, etc. Platform-specific API responses are mapped into these shared models inside each core. No platform-specific types leak past the core boundary.

Dart mirrors these models in `dart/lib/models/models.dart` (generated from the Go structs or manually kept in sync).

### Capabilities

| Capability | Description | Platforms |
|---|---|---|
| `CALLS` | 1:1 voice/video calls (audio frames, mute, recording) | All (implement if platform supports it) |
| `VIDEO_CALLS` | Camera video in calls (VP8 — pure Go encoder, pixel-accurate) | Telegram (3 versions: v13/v8/v4, bidirectional verified) |
| `SCREEN_SHARE` | Screen sharing in calls (separate track from video) | Telegram (V2Ref+V2Impl) |
| `CALL_RECORDING` | Client-side call recording (binary Opus file) | Telegram |
| `GROUP_CALLS` | Group voice/video calls via SFU (bidirectional video+audio, data channel subscription) | Telegram, Matrix |
| `CHANNELS` | Create/manage channels | All (implement if platform supports it) |
| `REACTIONS` | Message reactions | All (implement if platform supports it) |
| `READ_RECEIPTS` | Per-user read state (who read what) | All (implement if platform supports it) |
| `POLLS` | Create/vote on polls | All (implement if platform supports it) |
| `STICKERS` | Sticker packs | All (implement if platform supports it) |
| `TOPICS` | Forum-style topic threads in groups | **Telegram only** |
| `SCHEDULED` | Scheduled messages | All (implement if platform supports it) |
| `FOLDERS` | Chat folder/filter organization | All (implement if platform supports it) |
| `ADMIN` | Group/channel admin controls | All (implement if platform supports it) |
| `SESSIONS` | Active sessions management | All (implement if platform supports it) |
| `BASE64_IMAGE` | Send images as Base64 strings | All (optional) |

Features like replying, forwarding, pinning, editing, deleting, and marking as read are part of the **base `Core` interface** — not capabilities. Every core must implement them. If a platform doesn't support one, the core returns `ErrNotSupported` and the UI gracefully hides the option.

### Uniform API Contract

1. **Same name, same signature.** Every core method matches the `Core` interface exactly.
2. **Same data models.** All cores return the shared structs from `base.go`.
3. **Extensions behind capabilities.** Optional methods return `ErrNotSupported` if not supported.
4. **Same error semantics.** All cores return errors from a shared error set (`ErrAuth`, `ErrNetwork`, `ErrNotFound`, `ErrRateLimit`, etc.).
5. **Same concurrency contract.** All blocking operations are safe to call from any goroutine.

### Portability & Adding a New Core

Adding a new platform must be **trivially easy**:

1. Create `go/cores/discord.go` — implement the `Core` interface.
2. Register it in `go/bridge/bridge.go` — one line: `cores = append(cores, discord.New())`.
3. Done. The UI automatically discovers the new core.

**No Dart changes.** Every core is fully self-contained: no core imports from another core. The bridge's core registration is the only place that "knows" which cores exist.

---

## Utils: Swappable Feature Legos (Go side)

The `go/utils/` package contains **every cross-cutting feature** as an isolated, single-responsibility module:

- **No util imports from another util** unless there's a genuine data dependency.
- **No util imports from any core.** Utils are platform-agnostic.
- **Cores import from utils, never the reverse.**
- **Every util has its own `_test.go` file.**

### Module Responsibilities

| Module | Does | Does NOT |
|---|---|---|
| `encryption.go` | ECDH (X25519), AES-256-GCM encrypt/decrypt, Argon2id manual password, keystore load/save, `@@` prefix handling | Know about any platform, touch the network |
| `compression.go` | Zstd compress/decompress at max level | Know what the data is or where it's going |
| `filesplit.go` | Split `io.Reader` into N-byte chunks, reassemble from ordered parts, name parts (`*.part01`), validate integrity | Know platform upload limits (caller passes the limit) |
| `msgsplit.go` | Split text at 4000-word boundary, reassemble consecutive chunks | Know about encryption or compression |
| `proxy.go` | Create configured HTTP/SOCKS5 dialers, DNS override map, fallback logic, custom `http.Transport` | Know which platform is using it |
| `storage.go` | Resolve platform-correct paths for config, data, cache, downloads, sessions, keystore | Hardcode any OS-specific path |
| `config.go` | Load/save JSON settings, per-account config, merge defaults, validate | Know what the settings mean semantically |
| `vault.go` | Unified encrypted database (BBolt) — store/retrieve credentials, keys, sessions, settings. Encrypt at rest with Argon2id-derived key. Export/import. | Know what the data means semantically. Touch the network |
| `markdown.go` | Parse Markdown text, validate, extract plain-text summary (for chat list previews) | Render anything (rendering is Dart's job) |
| `base64img.go` | Encode image bytes → Base64, decode Base64 → image bytes, validate format | Know which messenger it's being sent through |

---

## Cross-Platform Architecture

### Cross-Platform File Locations (`utils/storage.go`)

| Data | Linux | Windows | macOS | Android | Web |
|---|---|---|---|---|---|
| Vault | `~/.config/uniclient/uniclient.vault` | `%APPDATA%\uniclient\uniclient.vault` | `~/Library/Application Support/uniclient/uniclient.vault` | App internal storage | IndexedDB |
| Downloads | `$XDG_DOWNLOAD_DIR/uniclient/` | `%USERPROFILE%\Downloads\uniclient\` | `~/Downloads/uniclient/` | Shared storage / Downloads | Browser download API |
| Cache | `~/.cache/uniclient/` | `%LOCALAPPDATA%\uniclient\cache\` | `~/Library/Caches/uniclient/` | App cache dir | Cache API |

### Cross-Platform Rules

- **Every Go dependency must cross-compile** to all targets or be wrapped with build-tag-gated alternatives.
- **Zero CGo anywhere** — CGO_ENABLED=0. Pure Go only, no C compiler needed.
- **No native subprocess calls** (no shelling out to `ffmpeg`, `gpg`, etc.).
- **No OS-specific imports at package level.** Use build tags where absolutely necessary.
- **Dart side**: use only Flutter plugins that support all targets.

### Cross-Platform Media Playback (Dart side)

**Video:** `media_kit` + `media_kit_video` (libmpv on desktop, platform player on mobile, HTML5 on web). Features: play, pause, seek, volume, fullscreen, speed (1x/1.5x/2x). Inline in message bubble + fullscreen. Round videos in `ClipOval`.

**Audio / Voice Messages:** `media_kit` for playback. Waveform visualization for voice messages. Background audio continues when navigating away. On mobile, use `audio_service` for lock screen controls.

**Thumbnails (generated in Go):** Pure-Go image libraries (`disintegration/imaging`) for blurred thumbnails stored as Base64 in message metadata.

---

## Research Approach

When learning a library or API, **clone the repo locally and read the source**. Do not rely on slow web searches.

1. `git clone` the repo to `/tmp/<name>` (shallow clone with `--depth 1` for speed).
2. Read `README.md`, `examples/`, and relevant source files directly.
3. Store findings in `research/` or inline comments.
4. Web search is only acceptable for finding a specific URL or link — never for broad research.

---

## Documentation Rules

### `research/` — Development Notes

**Every odd/unexpected thing you discover during development goes into `research/`.**

General rules:
- Update during research, not after.
- Include raw request/response examples (sanitized).
- Date entries with `<!-- Discovered YYYY-MM-DD -->` comments.
- Append-friendly — add new sections, don't reorganize unless wrong.

### `/auth/auth.md` — Test Credentials

All test credentials live in `/auth/auth.md` (gitignored). Format: `export VAR="value"`.

### `/auth/` — Session Files

All session files in `/auth/` (gitignored). Avoids re-authenticating on every test run.

---

## Build Order

Implement strictly in this order. Each step has a test gate. Track progress in `CHECKLIST.md`.

### Phase 0: Foundation
1. `flake.nix` — dev shell
2. `go/utils/` — all utility modules with tests
3. `go/bridge/bridge.go` — FFI skeleton

### Phase 1: Telegram (Main Server)
4. Telegram bot mode — auth, send/receive, files, inline/callback queries
5. Telegram user mode — full feature set

### Phase 2: Telegram (Test Server)
6. Bot mode against test DC
7. User mode against test DC

### Phase 3: Bale
8. Bot mode — auth, send/receive, files, keyboards
9. User mode — full feature set (calling geo-restricted from abroad)

### Phase 4: Rubika
10. Bot mode — auth, send/receive, files
11. User mode — full feature set

### Phase 5: Delta Chat
12. User mode — IMAP/SMTP, Autocrypt E2EE, SecureJoin

### Phase 6: TeamSpeak 3
13. UDP client protocol — voice, channels, commands

### Phase 7: Matrix
14. User + bot mode — mautrix-go SDK, E2EE (Olm/Megolm), 1:1 VoIP calls

### Phase 8: UI
15. Flutter UI — all screens via bridge

### Phase 9: Mumble
16. Real Mumble client protocol — TLS TCP + OCB2 encrypted UDP voice

### Phase 10: GitHub
17. REST API messaging layer — issues-as-channels, DMs via profile repos

### Phase 11: IRC
18. Pure Go IRC client — RFC 1459/2812 + IRCv3 + CTCP + DCC + NickServ/ChanServ/MemoServ/HostServ/BotServ

---

## Networking: Proxy & DNS Override (`utils/proxy.go`)

- Support **HTTP proxy** and **SOCKS5 proxy**, configurable per-account or globally.
- Support **manual IP override per domain**, bypassing DNS. Useful in censored environments.
- If manual IP fails, **automatically fall back to standard DNS**.
- All connections route through configured proxy/IP.
- Implementation: custom `net.Dialer` with DNS override map + proxy + fallback.

---

## Core: `telegram.go`

Built using **`gotd/td`** — a pure-Go MTProto implementation.

### Bot Mode
- Auth with bot token, send/receive messages, files, inline/callback queries.

### User Mode
- Phone+OTP+2FA auth, full dialogs, message CRUD, reactions, read receipts, media, profiles, real-time updates, groups, channels, topics, folders, calls, scheduled messages, drafts, contacts, sessions, admin controls, bot interaction, logout.

### Server Selection
- **Main server** (default) and **Test server** (`149.154.167.40:443` / DC 2 test). Separate sessions.

### API ID / API Hash Selection

| Client Name | API ID | API Hash |
|---|---|---|
| Telegram Desktop (TDesktop) | 2040 | b18441a1ff607e10a989891a5462e627 |
| Telegram Android | 6 | eb06d4abfb49dc3eeb1aeb98ae0f581e |
| Public Android Beta | 4 | 014b35b6184100b085b0d0572f9b5103 |
| Public Static Final | 5 | 1c5c96d5edd401b1ed40db3fb5633e2d |
| Public iOS Beta | 8 | 7245de8e747a0d6fbe11f7cc14fcc0bb |
| Nicegram / Telegram iOS | 94575 | a3406de8d171bb422bb6ddf3bbd800e2 |
| Webogram | 2496 | 8da85b0d5bfe62527e5b244c209159c3 |
| TGX for Android | 21724 | 3e0cb5efcd52300aec5994fdfc5bdc16 |
| TG-React | 414121 | db09ccfc2a65e1b14a937be15bdb5d4b |
| Custom | (user input) | (user input) |

### Universal Feature Principle

**Every Telegram Desktop feature that has a logical equivalent on other platforms must be implemented there too.** "If supported" means: implement it if the platform's API exposes the capability. Only mark unsupported if the platform genuinely doesn't offer it.

---

## Core: `bale.go`

Bale uses an HTTP-based API similar to Telegram's Bot API + gRPC-Web/Protobuf over WebSocket for user mode. Implement directly using Go's `net/http` and WebSocket.

**Calling note**: Bale's call feature (LiveKit-based) may be geo-restricted to Iran. Implement fully, mark tests as skippable.

---

## Core: `rubika.go`

Rubika uses a proprietary encrypted HTTP API + WebSocket for real-time. Protocol reverse-engineered from `rubpy` Python client.

---

## Core: `deltachat.go`

Pure Go IMAP/SMTP implementation. Both bot and user mode. Autocrypt E2EE (OpenPGP Level 1), SecureJoin, groups, broadcasts, reactions (RFC 9078), WebRTC calls via email signaling.

---

## Core: `teamspeak.go`

Real TS3 UDP client protocol (not ServerQuery TCP). P-256 identity keys, AES-128-EAX encryption, QuickLZ decompression, Opus voice (pure Go codec or Flutter platform codec).

---

## Core: `matrix.go`

Built using **`mautrix-go`** (maunium.net/go/mautrix) — a pure-Go Matrix client SDK. User + bot (access token) mode. Full E2EE via goolm (pure-Go Olm/Megolm, `-tags goolm`). 1:1 VoIP calls via pion/webrtc. Extras: spaces, threads, presence, room aliases, public directory, device management, tags, user search.

**E2EE note**: mautrix pinned at v0.26.4. E2EE uses OlmMachine + MemoryStore internals. Do NOT upgrade without running all Matrix tests.

---

## Core: `mumble.go`

Real Mumble client protocol — TLS TCP for control + OCB2-AES128 encrypted UDP for voice. Hand-coded protobuf (no protoc dependency). Auto-detects server version (protobuf 1.5+ or legacy voice format). TCP tunnel fallback when UDP blocked. Extras: ACL, bans, channel listeners, voice targets, plugin data, user registration, public server list.

---

## Core: `github.go`

REST API only (no GraphQL). DMs via profile repo issues (`{user}/{user}`), groups via repos with issues-as-channels. 5-layer rate limit defense: User-Agent header, token bucket rate limiter with budget tracking, doAPI retry engine (4 attempts, exponential backoff + jitter), response/session caching, conditional requests (ETag). Capped discovery (max 3 new repos/cycle) prevents N+1 queries. No external deps (stdlib only).

---

## Core: `irc.go`

Pure Go IRC client — RFC 1459/2812 message parsing, IRCv3 CAP negotiation (25+ capabilities), SASL PLAIN auth, NickServ fallback. TCP+TLS. 302 methods, ~4,473 lines. Full Core interface + 247 IRC-specific methods: channel modes, ban management, CTCP, DCC signaling, MONITOR/WATCH, services (NickServ 20, ChanServ 39, MemoServ 10, HostServ 4, BotServ 6), IRCv3 drafts (CHATHISTORY, MARKREAD, REDACT, REGISTER/VERIFY, RENAME). ISUPPORT (005) full parsing. Flood protection, PING/PONG keepalive, nick collision handling. No external deps (stdlib only).

---

## Research Documentation (`research/`)

Protocol research for each underdocumented platform must contain:
- Base URLs and endpoints
- Authentication flows (step-by-step with sanitized examples)
- Message formats and schemas
- File upload/download mechanisms
- Real-time update mechanisms
- Rate limits, quirks, gotchas
- Sources (which client code, which capture session)

---

## Encryption Layer (`utils/encryption.go`)

All encryption is at the application layer in Go. Platform servers see only opaque ciphertext.

### Encryption Indicator
Every encrypted message is prefixed with `@@` before Base64-encoded ciphertext. Absent `@@` = plaintext. Present but decrypt fails = broken lock icon + raw ciphertext.

### Compression Before Encryption
Compress with **Zstd** at max level before encrypting. Decompress after decrypting.

### Message Length Splitting
If >4000 words, split at word boundaries. Each chunk independently compressed, encrypted, `@@`-prefixed, sent separately.

### Per-Chat Encryption Modes (Lock Button)

| Mode | How It Works |
|---|---|
| **Off** | Plaintext. No `@@` prefix. Default for new chats. |
| **ECDH (Automatic)** | X25519 key exchange, zero-knowledge. Recommended. |
| **Manual Password** | Passphrase → Argon2id → AES-256-GCM key. Opt-in fallback. |

### DM Encryption: ECDH + AES-256-GCM
- Long-term X25519 keypair in local keystore.
- Ephemeral X25519 keypair per DM conversation.
- Key exchange via special handshake message (JSON with public key).
- ECDH → HKDF-SHA256 → 256-bit AES-GCM session key.
- Every message: AES-256-GCM with fresh random 96-bit nonce prepended to ciphertext.

### DM Encryption: Manual Password Mode
- Passphrase → Argon2id (64 MB, 3 iterations, parallelism 4, salt: SHA-256 of user IDs + conversation ID) → 256-bit AES-GCM key.
- Password never stored, never transmitted.

### Group Encryption: AES-256-GCM with Shared Group Key
- Group key generated by creator, distributed via ECIES wrapping per member.
- Member removed → new group key, rewrap for remaining members.

### Unified Encrypted Vault (`utils/vault.go`)
- Single encrypted file: `uniclient.vault` (BBolt).
- Contains: all keys, credentials, sessions, settings, drafts.
- Master key: Argon2id (64 MB, 3 iterations, parallelism 4) from vault password.
- BBolt buckets: `accounts/`, `keys/`, `config/`, `drafts/`.
- Export/import supported with optional re-encryption.

### Encryption UI Controls (Dart side)
- **Lock button**: open lock (off), green locked (ECDH), orange locked with key (manual password).
- **Per-message override**: right-click/long-press send → "Send as Plaintext" / "Send Encrypted".
- **Status indicators**: green lock = encrypted, gray = plaintext, red broken lock = decrypt failed.
- **Settings**: key fingerprints, regenerate, change vault password, export/import.

---

## UI/UX: Flutter (Dart)

Built with **Flutter** + **Material 3**. Platform-adaptive: multi-column on desktop/web, single-column on mobile.

### Visual Design: Dark-First

Dark mode is default. True black (`#000000`) OLED backgrounds, `#0D0D0D` cards, `#1A1A1A` elevated surfaces. Electric indigo primary, teal secondary, soft amber warnings. Light mode available as toggle.

### Screens

1. **Splash** — vault password prompt, loading indicator
2. **Login** — platform selector, mode toggle (user/bot), API client dropdown (Telegram), server selector
3. **Account Switcher** — sidebar (desktop) / drawer (mobile), grouped by platform
4. **Chat List** — Discord-inspired 3-column (server rail + chat list + chat view) on desktop, single column on mobile. Topic hierarchy for Telegram forum supergroups.
5. **Chat / Conversation** — message bubbles with markdown rendering, media (download-to-view, play in-app), read receipts (single/double/blue checks), encryption indicators, reply/forward/react, infinite scroll, file upload/download with progress
6. **File Upload/Download** — encrypted file transfer toggle, platform-specific auto-splitting (Bale 19.5MB, Telegram 2GB user/50MB bot)
7. **Message Search** — full-text within chat, highlighted excerpts
8. **Settings** — theme, proxy, encryption, accounts, about
9. **System Tray & Notifications** — desktop tray, cross-platform notifications
10. **Call Screen** — 1:1 (fullscreen overlay, mute/speaker/video/end) and group (participant grid, speaking indicator)
11. **Telegram-Specific** — contacts, saved messages, archived, folders, sessions, group/channel info

### Media Handling in Chat

- **Images**: blurred thumbnail → download → inline render → tap for fullscreen `InteractiveViewer` with pinch-to-zoom
- **Videos**: poster frame → download with progress → inline `media_kit` playback → fullscreen
- **GIFs**: auto-download, auto-play inline muted and looping
- **Audio/Music**: download → in-app `media_kit` player with seek bar, metadata, speed toggle
- **Voice messages**: auto-download, waveform visualization, speed toggle
- **Round videos**: `ClipOval` frame, inline playback
- **Stickers**: 200×200 logical pixels, animated via Lottie
- **Files**: filename + size + download → open with system viewer
- **Replies**: quoted block with original sender + first line, tap to scroll to original
- **Reactions**: emoji chips with counts below bubble
- **Markdown**: bold, italic, strikethrough, inline code, code blocks with syntax highlighting, links, blockquotes, lists, headings

---

## Test Infrastructure

### Philosophy
- **ALL tests are real** — hit live APIs with real credentials.
- **Every feature tested against real API before marked done** — user must confirm.
- **Credentials via environment variables** — never hardcode.
- **Delete test files after confirmation** — don't keep old passing tests.
- **Test each feature exactly once.**
- **Table-driven tests in Go, golden tests for Dart widgets.**
- **Utils tests are self-contained** (no external credentials needed).

### Workflow
1. Implement the feature
2. Write real test (live API)
3. Ask user for credentials
4. Run test
5. Ask user to verify on device
6. User confirms → mark done in CHECKLIST.md

### Go Tests
- Core tests: auth, messages, dialogs, files, read state, calls, real-time — all against live APIs
- Util tests: encryption, compression, filesplit, msgsplit, proxy, vault, markdown, storage, config, base64img

### Dart Tests
- Widget tests for every screen and reusable widget
- Golden snapshot tests for key screens (dark + light)
- Bridge mock tests for serialization/deserialization
- State management tests for account switching, encryption mode, theme

---

## Dependencies

### Go (`go.mod`)

| Package | Purpose |
|---|---|
| `github.com/gotd/td` | Telegram MTProto |
| `golang.org/x/crypto` | X25519, Argon2id, HKDF, AES-GCM |
| `github.com/klauspost/compress` | Zstd compression |
| `golang.org/x/net` | SOCKS5 proxy dialer |
| `nhooyr.io/websocket` | WebSocket (Rubika) |
| `go.etcd.io/bbolt` | Encrypted vault storage |
| `github.com/disintegration/imaging` | Thumbnail generation |
| `coder/websocket` | Bale WebSocket |
| `livekit/server-sdk-go/v2` | Bale calls (LiveKit) |
| `go-imap/v2`, `go-smtp`, `go-message` | Delta Chat IMAP/SMTP |
| `ProtonMail/go-crypto` | Delta Chat Autocrypt |
| `pion/webrtc/v4`, `pion/ice/v4` | Telegram/Delta Chat/Matrix calls |
| `maunium.net/go/mautrix` | Matrix client SDK (pinned v0.26.4) |

Zero CGo dependencies anywhere — CGO_ENABLED=0 across the entire project.

### Dart (`pubspec.yaml`)

| Package | Purpose |
|---|---|
| `media_kit` + `media_kit_video` | Video/audio playback |
| `flutter_markdown` | Markdown rendering |
| `flutter_highlight` | Syntax highlighting |
| `system_tray` | Desktop system tray |
| `flutter_local_notifications` | Notifications |
| `path_provider` | Platform directories |

---

## Implemented Platforms (Beyond Core)

| Platform | Protocol | Status |
|---|---|---|
| **Telegram** | MTProto (gotd/td) | **DONE.** 786 methods, ~14k lines. Bot+user mode. 1:1 calls: trimmed to 3 versions (v13.0.0 SCTP, v8.0.0 V2Impl, v4.0.0 Web) — all verified bidirectional audio. Pure Go VP8 encoder (zero CGo). Group calls: SFU bidirectional video+audio working (data channel ReceiverVideoConstraints subscription). Diff-IP verified (local + Singapore proxy). |
| **Bale** | HTTP + gRPC-Web | **DONE.** Bot 17/17, user 68/68. Calling implemented (LiveKit). |
| **Rubika** | HTTP + WSS | **DONE.** ~219 methods, 63/63 tests. |
| **Delta Chat** | IMAP/SMTP | **DONE.** ~119 methods, 132/132 tests. PGP/MIME E2EE. |
| **TeamSpeak** | Custom UDP | **DONE.** ~192 methods. Bidirectional audio verified on real servers. |
| **Matrix** | HTTP/JSON (mautrix-go) | **DONE.** 109 methods. Full E2EE (Olm/Megolm), calls, real-time sync. |
| **Mumble** | TLS TCP + OCB2 UDP | **DONE.** 228 methods, ~4.9k lines. Real Mumble protocol. |
| **IRC** | TCP/TLS | **DONE.** 302 methods, ~4.5k lines. RFC 1459/2812 + IRCv3. Tested on 6 networks. |
| **XMPP** | TCP/TLS, XML streams | **DONE.** 242 methods, 32/32 tests. RFC 6120/6121 + 30 XEPs. |
| **GitHub** | REST API | **DONE.** Issues-as-channels, 5-layer rate limit defense. |

## Future Platforms (Planned)

| Platform | Protocol | Approach |
|---|---|---|
| **Discord** | — | **NEVER add.** ToS bans unofficial clients, they actively detect and ban. |

Same pattern: implement `Core` in one Go file, register in bridge.go, add icon/color to Dart.

---

## Independence Guarantee

Every core and every util must **exist and function in complete isolation**:
- Delete any core → app starts without it, others work fine.
- Delete any util → cores that don't need it still work.
- Delete all cores → "No messaging platforms available."
- Any util dropped into a different Go project compiles and works.

---

## Phase 7.5 — Core Finalization (pre-UI hardening)

**Goal:** Every core is production-ready, uniformly structured, fully tested, docstring'd, and documented as a framework API before starting Flutter.

### Step 1 — Auth modes audit

Review every core's authentication and operating modes. Make sure no mode or functionality is left behind:
- **Telegram**: bot mode, user mode, test DC mode (`UseTestDC: true`)
- **Bale**: bot mode (HTTP API), user mode (gRPC-Web/WebSocket)
- **Rubika**: bot mode, user mode
- **Delta Chat**: bot mode, user mode (same IMAP/SMTP, different behavior)
- **TeamSpeak**: identity-based auth (no separate modes, but server password / privilege keys)
- **Matrix**: user mode (password login), bot mode (access token / appservice)
- **Mumble**: registered user, unregistered guest, certificate-based auth
- **GitHub**: PAT-based (single mode, but scopes vary)
- **IRC**: SASL PLAIN, NickServ identify, connection password, or no-auth (guest)

For each core, verify that every auth mode works end-to-end, session persistence survives restarts, and mode-specific features are accessible.

### Step 2 — Audit every core against the Core interface

Revisit each of the 9 cores (telegram, bale, rubika, deltachat, teamspeak, matrix, mumble, github, irc) and check every method in `base.go`'s `Core` interface. For each core:
- List methods that are missing, stubbed, or have incomplete implementations
- Check error handling: clear errors for the UI, not raw API messages
- Check input validation: bad chat IDs, empty strings, too-long text
- Check that `ErrNotSupported` is returned (not panic/nil) for unsupported features
- Verify consistent chat ID format conventions across cores
- Look for platform-specific extra methods that should be exposed or unified

### Step 3 — Uniform structure

Every core must follow the same layout pattern so they read identically:
1. Constants & types
2. Constructor (`NewXCore`)
3. Auth (Authenticate, Logout)
4. Dialogs (GetDialogs, CreateGroup, CreateChannel, CreateTopic, GetFolders, CreateFolder)
5. Messages (Send, Get, Edit, Delete, Reply, Forward, React, Pin, Unpin)
6. Read state (MarkAsRead, GetReadState)
7. Files (Upload, Download, SendImageBase64)
8. Calls (Start, Join, End, Mute)
9. Profile (GetProfile)
10. Real-time (OnUpdate, Close)
11. Chat management (GetChatInfo, EditTitle, EditDescription, Leave, InviteLink)
12. Members (Add, Remove, Ban, Unban, Get, SetAdmin)
13. Contacts (Get, Add, Delete, Block, Unblock, GetBlocked)
14. Search (Messages, Global)
15. Misc (Typing, Polls, Stickers, Sessions)
16. Internal helpers

The function mapping must be identical: `cores.NewBaleCore(session).SendMessage(chatID, msg)` works the same as `cores.NewTelegramCore(session).SendMessage(chatID, msg)`. Same params, same return types, same error patterns.

### Step 4 — Full integration tests for every core

Run comprehensive tests for each core covering every implemented method. Document pass/fail in CHECKLIST.md. Tests that already passed and were confirmed don't need re-running — only test untested or changed methods.

### Step 5 — Docstrings and comments

Before writing external docs, docstring the entire codebase:
- Every exported function, type, and constant gets a Go doc comment
- Complex internal logic gets inline comments explaining *why*, not *what*
- Each core file gets a package-level doc block summarizing what it implements
- `base.go` interface methods get doc comments explaining expected behavior, params, and error conventions
- This is the foundation — external docs reference these docstrings

### Step 6 — Create `docs/` as framework API documentation

Create a new `docs/` directory (the old `docs/` is now `research/`) with per-core API guides written for a developer using the cores as a library:
- `docs/README.md` — overview, quick start, how cores work
- `docs/telegram.md` — every method, params, return values, error cases, examples
- `docs/bale.md`, `docs/rubika.md`, `docs/deltachat.md`, `docs/teamspeak.md`, `docs/matrix.md`, `docs/mumble.md`, `docs/github.md`, `docs/irc.md`
- `docs/errors.md` — all error types, when each is returned, how UI should handle
- `docs/chat-ids.md` — chat ID format conventions per platform

These docs target a Flutter developer (or any consumer) who has never seen the Go code.

