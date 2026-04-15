# Engine Architecture — Pre-GUI Foundation

<!-- Written 2026-04-14, before Step 15 (Build GUI) -->

The engine is the orchestration layer between the 10 platform cores and the Flutter UI. Without it, the UI must manage 10 core lifecycles, implement caching, handle offline, coordinate events, and drive auth flows — all in Dart. With it, Dart is a dumb renderer.

This document is the implementation spec for `go/engine/`. Every decision here was validated against how Telegram (TDLib) and Google (Gmail/Messages) build their clients, adapted for our 10-platform, pure-Go, cross-platform constraints.

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Engine Components](#2-engine-components)
3. [SQLite Data Layer](#3-sqlite-data-layer)
4. [Event System](#4-event-system)
5. [Auth State Machine](#5-auth-state-machine)
6. [Content Normalization](#6-content-normalization)
7. [Pending Queue (Offline-First)](#7-pending-queue-offline-first)
8. [Media Pipeline](#8-media-pipeline)
9. [Startup Sequence](#9-startup-sequence)
10. [Dart State Layer](#10-dart-state-layer)
11. [Platform-Specific Concerns](#11-platform-specific-concerns)
12. [Call Subsystem](#12-call-subsystem)
13. [Configuration](#13-configuration)
14. [Testing Strategy](#14-testing-strategy)
15. [Error Recovery & Resilience](#15-error-recovery--resilience)
16. [Upload Pipeline](#16-upload-pipeline)
17. [Connection Health](#17-connection-health)
18. [Notifications](#18-notifications)
19. [Edge Cases & First Impressions](#19-edge-cases--first-impressions)
20. [Build Plan](#20-build-plan)

---

## 1. Architecture Overview

### The Three Layers

```
╔════════════════════════════════════════════════════════════╗
║  FLUTTER UI (Dart)                                        ║
║  Screens, widgets, animations, themes                     ║
║  State mirror (Riverpod 3) — read-only snapshot of engine ║
║  Bridge (dart:ffi / WASM interop)                         ║
╠══════════════════ FFI boundary ═══════════════════════════╣
║  BRIDGE (go/bridge/)                                      ║
║  FFI exports, protobuf serialize/deserialize              ║
║  Routes engine methods + raw core dispatch                ║
╠═══════════════════════════════════════════════════════════╣
║  ENGINE (go/engine/)                    ◄── NEW           ║
║  Account lifecycle, auth FSM, SQLite cache,               ║
║  event normalization, pending queue, media cache,         ║
║  content normalization, search (FTS5)                     ║
╠═══════════════════════════════════════════════════════════╣
║  CORES (go/cores/)                                        ║
║  10 platform clients — raw protocol, no state management  ║
╠═══════════════════════════════════════════════════════════╣
║  UTILS (go/utils/)                                        ║
║  vault, storage, proxy, config, encryption, etc.          ║
╚════════════════════════════════════════════════════════════╝
```

### Data Flow

```
USER ACTION:   UI → Riverpod → bridge.call() → Engine → Core → Network
RESPONSE:      Network → Core → Engine (cache + normalize) → PushEvent → Dart → UI

REAL-TIME:     Network → Core.OnUpdate → Engine.handleUpdate
               → write SQLite → normalize → dedup → PushEvent → Dart → UI

OFFLINE SEND:  UI → bridge.call(SendMessage) → Engine
               → write to pending table (status=queued)
               → insert into messages (status=SENDING)
               → PushEvent(NewMessage with clock icon)
               → background: core.SendMessage()
               → on success: update messages (status=SENT) + delete pending + PushEvent
               → on failure: update pending (status=failed) + PushEvent(retry icon)
```

### Bridge Routing

The bridge dispatches based on `core_id`:

- `core_id = "__engine"` → engine methods (account management, chat list, search, settings)
- `core_id = "tg_a1b2c3"` (any account ID) → raw core dispatch via existing `dispatch_gen.go`

This preserves all 3,564 existing core methods unchanged. The engine is just another dispatch target.

---

## 2. Engine Components

```
go/engine/
    engine.go        — Engine struct, Init/Shutdown, top-level orchestrator
    accounts.go      — Account CRUD, core lifecycle (connect/disconnect/reconnect)
    auth.go          — Generic auth state machine for all 10 platforms
    db.go            — SQLite open, schema, migrations, WAL mode
    cache_chats.go   — Chat list CRUD, sync, diff against network
    cache_msgs.go    — Message insert/query/paginate, FTS5 indexing
    cache_users.go   — User profile cache
    events.go        — Typed BridgeEvent definitions, normalization, dedup, dispatch
    pending.go       — Outbox queue: persist before send, retry on restart
    content.go       — 10 platform formats → RichContent proto conversion
    media.go         — Download queue (priority-based), LRU eviction, thumbnail mgmt
    search.go        — Cross-account FTS5 search, result ranking
```

### Engine Struct

```go
type Engine struct {
    mu       sync.RWMutex
    db       *sql.DB           // single SQLite database (WAL mode)
    vault    *utils.Vault      // encrypted credential store
    config   *utils.AppConfig  // app settings
    accounts map[string]*Account  // accountID → live account
    eventCB  func([]byte)      // serialized BridgeEvent → Dart

    mediaDir string            // media cache root
    maxCache int64             // max media cache size in bytes

    activeChat struct {        // notification suppression
        accountID string
        chatID    string
    }
}

type Account struct {
    ID         string
    Platform   string          // "telegram", "matrix", etc.
    Core       cores.Core      // live core instance
    AuthState  AuthState       // current auth flow state
    ConnState  ConnState       // connected/connecting/disconnected
    SortOrder  int
}
```

### Engine Methods (exposed via bridge)

Account management:
- `ListAccounts() → []AccountInfo`
- `AddAccount(platform string) → accountID` (starts auth flow)
- `RemoveAccount(accountID string)`
- `ReorderAccounts(order []string)`
- `SubmitAuthInput(accountID, input string)` (advance auth state machine)
- `CancelAuth(accountID string)`

Chat list:
- `GetChatList(accountID string, archived bool, limit, offset int) → []ChatInfo` (from SQLite)
- `GetUnifiedChatList(limit, offset int) → []ChatInfo` (all accounts, sorted by time)
- `SaveDraft(accountID, chatID, text string)`

Messages:
- `GetMessages(accountID, chatID string, beforeMsgID string, limit int) → []CachedMessage` (cache, falls back to network)
- `SendMessage(accountID, chatID string, content RichContent) → localID` (goes through pending queue)
- `SetActiveChat(accountID, chatID string)` (suppress notifications)
- `ClearActiveChat()`

Search:
- `SearchMessages(query string, accountID string, limit int) → []SearchResult` (FTS5, cross-account if accountID empty)

Media:
- `RequestDownload(accountID string, mediaRef MediaRef, priority int) → downloadID`
- `CancelDownload(downloadID string)`
- `GetCacheSize() → int64`
- `ClearCache(accountID string)` (empty = clear all)

Settings:
- `GetConfig() → AppConfig`
- `UpdateConfig(changes AppConfig)`

All other operations (edit message, ban member, create group, etc.) go through raw core dispatch — the existing bridge handles them directly.

---

## 3. SQLite Data Layer

### Database: `modernc.org/sqlite`

Pure Go, no CGo. Works with `CGO_ENABLED=0`. Supports Linux, Windows, macOS, Android. FTS5 and WAL mode included.

**Does NOT compile to `GOOS=js GOARCH=wasm`.** Web target uses a different strategy (see [Section 11](#11-platform-specific-concerns)).

### One Database, Not Ten

The unified chat list (ALL chats from ALL accounts sorted by time) is the primary view. This query must be fast and simple:

```sql
SELECT * FROM chats
WHERE archived = 0
ORDER BY pinned DESC, last_msg_time DESC
LIMIT 50 OFFSET ?
```

With one DB, this is a single indexed query. With 10 DBs, it requires opening 10 connections, running 10 queries, and merge-sorting in memory.

Write contention from 10 goroutines is handled by WAL mode (readers never block, writers queue briefly) and batched writes (accumulate 50-100ms of updates, write in one transaction).

Account deletion = `DELETE FROM * WHERE account_id = ?` + `VACUUM`. Rare operation, acceptable cost.

### Location

```
~/.config/uniclient/             (Linux, via os.UserConfigDir)
%APPDATA%\uniclient\             (Windows)
~/Library/Application Support/uniclient/  (macOS)
<app-internal>/                  (Android, path passed from Dart)

Contents:
    uniclient.vault              # encrypted credentials (Argon2id + AES-256-GCM)
    config.json                  # app settings (theme, language, proxy)
    cache.db                     # SQLite database (WAL mode)
    media/
        <account_id>/
            thumb/               # thumbnails (never evicted)
            full/                # full-size media (LRU evicted)
    downloads/                   # user-initiated saves (never evicted)
```

### Schema

```sql
PRAGMA journal_mode = WAL;
PRAGMA busy_timeout = 5000;
PRAGMA foreign_keys = ON;
PRAGMA user_version = 1;  -- schema version for migrations

-- ═══════════════════════════════════════════════
-- Account registry
-- ═══════════════════════════════════════════════
CREATE TABLE accounts (
    id           TEXT PRIMARY KEY,  -- "tg_a1b2c3d4" (platform prefix + 8 random hex)
    platform     TEXT NOT NULL,     -- "telegram", "matrix", etc.
    display_name TEXT,              -- "@nako" or "nako@matrix.org"
    avatar_path  TEXT,              -- local path to cached avatar
    vault_key    TEXT,              -- key in vault "accounts" bucket for credentials
    sort_order   INTEGER NOT NULL DEFAULT 0,
    created_at   INTEGER NOT NULL   -- unix ms
);

-- ═══════════════════════════════════════════════
-- Chat list (the main view)
-- ═══════════════════════════════════════════════
CREATE TABLE chats (
    account_id    TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    chat_id       TEXT NOT NULL,
    type          INTEGER NOT NULL DEFAULT 0,  -- 0=unspec, 1=dm, 2=group, 3=channel, 4=topic
    title         TEXT NOT NULL DEFAULT '',
    avatar_path   TEXT,
    last_msg_id   TEXT,
    last_msg_text TEXT,              -- preview (first 100 chars, plain text)
    last_msg_time INTEGER,           -- unix ms, for sorting
    last_msg_sender TEXT,
    unread_count  INTEGER NOT NULL DEFAULT 0,
    is_muted      INTEGER NOT NULL DEFAULT 0,
    is_pinned     INTEGER NOT NULL DEFAULT 0,
    is_archived   INTEGER NOT NULL DEFAULT 0,
    draft_text    TEXT,              -- unsent message text
    member_count  INTEGER,
    parent_id     TEXT,              -- for topics: parent group chat_id
    capabilities  TEXT,              -- JSON array of capability strings for this chat
    updated_at    INTEGER NOT NULL,
    PRIMARY KEY (account_id, chat_id)
);
CREATE INDEX idx_chats_sort ON chats(is_archived, is_pinned DESC, last_msg_time DESC);
CREATE INDEX idx_chats_account ON chats(account_id);

-- ═══════════════════════════════════════════════
-- Messages
-- ═══════════════════════════════════════════════
CREATE TABLE messages (
    account_id    TEXT NOT NULL,
    chat_id       TEXT NOT NULL,
    msg_id        TEXT NOT NULL,
    local_id      TEXT,              -- for pending messages before server confirms
    sender_id     TEXT,
    sender_name   TEXT,
    content_raw   BLOB,              -- original platform format (for round-trip editing)
    content_rich  BLOB,              -- serialized RichContent proto (for UI rendering)
    content_text  TEXT,              -- plain text extract (for FTS5 + chat preview)
    timestamp     INTEGER NOT NULL,  -- unix ms
    edited_at     INTEGER,
    status        INTEGER NOT NULL DEFAULT 2,  -- 1=sending, 2=sent, 3=delivered, 4=read, 5=failed
    reply_to_id   TEXT,
    reply_preview TEXT,
    forward_from  TEXT,
    is_pinned     INTEGER NOT NULL DEFAULT 0,
    has_media     INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (account_id, chat_id, msg_id)
);
CREATE INDEX idx_msgs_chat_time ON messages(account_id, chat_id, timestamp DESC);
CREATE INDEX idx_msgs_local ON messages(local_id) WHERE local_id IS NOT NULL;

-- FTS5 full-text search across ALL messages
CREATE VIRTUAL TABLE messages_fts USING fts5(
    content_text,
    content='messages',
    content_rowid='rowid',
    tokenize='unicode61'
);

-- Triggers to keep FTS5 in sync
CREATE TRIGGER messages_ai AFTER INSERT ON messages BEGIN
    INSERT INTO messages_fts(rowid, content_text) VALUES (new.rowid, new.content_text);
END;
CREATE TRIGGER messages_ad AFTER DELETE ON messages BEGIN
    INSERT INTO messages_fts(messages_fts, rowid, content_text) VALUES('delete', old.rowid, old.content_text);
END;
CREATE TRIGGER messages_au AFTER UPDATE ON messages BEGIN
    INSERT INTO messages_fts(messages_fts, rowid, content_text) VALUES('delete', old.rowid, old.content_text);
    INSERT INTO messages_fts(rowid, content_text) VALUES (new.rowid, new.content_text);
END;

-- ═══════════════════════════════════════════════
-- Pending outbox (survives crashes)
-- ═══════════════════════════════════════════════
CREATE TABLE pending (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    account_id   TEXT NOT NULL,
    chat_id      TEXT NOT NULL,
    local_id     TEXT NOT NULL UNIQUE,  -- temporary ID shown in UI before server confirms
    action       TEXT NOT NULL,          -- "send", "edit", "delete", "react", "forward"
    payload      BLOB NOT NULL,         -- serialized request proto
    status       INTEGER NOT NULL DEFAULT 0,  -- 0=queued, 1=sending, 2=failed
    retry_count  INTEGER NOT NULL DEFAULT 0,
    error_msg    TEXT,
    created_at   INTEGER NOT NULL,
    last_attempt INTEGER
);
CREATE INDEX idx_pending_status ON pending(status, created_at);

-- ═══════════════════════════════════════════════
-- User profiles (cache)
-- ═══════════════════════════════════════════════
CREATE TABLE users (
    account_id    TEXT NOT NULL,
    user_id       TEXT NOT NULL,
    display_name  TEXT,
    username      TEXT,
    avatar_path   TEXT,
    is_bot        INTEGER NOT NULL DEFAULT 0,
    is_online     INTEGER NOT NULL DEFAULT 0,
    last_seen     INTEGER,
    updated_at    INTEGER NOT NULL,
    PRIMARY KEY (account_id, user_id)
);

-- ═══════════════════════════════════════════════
-- Media references
-- ═══════════════════════════════════════════════
CREATE TABLE media (
    account_id    TEXT NOT NULL,
    chat_id       TEXT NOT NULL,
    msg_id        TEXT NOT NULL,
    seq           INTEGER NOT NULL DEFAULT 0,  -- for messages with multiple attachments
    media_type    INTEGER NOT NULL,  -- 1=image, 2=video, 3=audio, 4=voice, 5=video_note,
                                     -- 6=sticker, 7=gif, 8=file
    remote_ref    TEXT,              -- platform file ID for downloading
    local_path    TEXT,              -- null if not downloaded
    thumb_path    TEXT,              -- thumbnail (always downloaded if available)
    thumb_b64     TEXT,              -- inline base64 thumbnail for instant display
    file_name     TEXT,
    mime_type     TEXT,
    file_size     INTEGER,
    duration_ms   INTEGER,           -- for audio/video
    width         INTEGER,           -- for image/video
    height        INTEGER,
    download_state INTEGER NOT NULL DEFAULT 0,  -- 0=none, 1=downloading, 2=downloaded, 3=failed
    last_accessed INTEGER,           -- for LRU eviction
    PRIMARY KEY (account_id, chat_id, msg_id, seq)
);
CREATE INDEX idx_media_evict ON media(last_accessed) WHERE local_path IS NOT NULL;
```

### Cache Tiers

Not all messages are cached forever. Tiers:

| Tier | What | Retention | Eviction |
|------|------|-----------|----------|
| **Hot** | Last 200 messages per chat | Always kept | Never evicted while chat exists |
| **Warm** | Older messages in recently opened chats | 7 days since last chat access | Pruned on engine startup |
| **Cold** | Messages not in cache | Never cached | Fetched from network on scroll-back |

Media tiers:

| Tier | What | Retention |
|------|------|-----------|
| **Thumbnails** | Small previews (thumb_path, thumb_b64) | Permanent (tiny) |
| **Full media** | Downloaded images/videos/files (local_path) | LRU eviction at configurable max (default 1GB) |
| **User downloads** | Files saved via "Save to Downloads" | Never evicted (user's file, in downloads dir) |

### Migrations

```go
var migrations = []func(*sql.DB) error{
    migrateV1,  // initial schema above
    // migrateV2, migrateV3, ... added as schema evolves
}

func migrateDB(db *sql.DB) error {
    var version int
    db.QueryRow("PRAGMA user_version").Scan(&version)
    for i := version; i < len(migrations); i++ {
        if err := migrations[i](db); err != nil {
            return fmt.Errorf("migration v%d: %w", i+1, err)
        }
        db.Exec(fmt.Sprintf("PRAGMA user_version = %d", i+1))
    }
    return nil
}
```

---

## 4. Event System

### Event Types

The engine pushes typed events to Dart via the existing `PushEvent` mechanism. The `BridgeEvent` proto is extended with engine-level events:

```protobuf
message EngineEvent {
  string account_id = 1;
  int64 timestamp_ms = 2;

  oneof event {
    // Account lifecycle
    AuthStateChanged auth_state = 10;
    ConnectionStateChanged conn_state = 11;
    AccountListChanged account_list = 12;

    // Chat list
    ChatListSnapshot chat_snapshot = 20;     // full list (startup, or after major sync)
    ChatUpdated chat_updated = 21;           // single chat metadata changed
    ChatRemoved chat_removed = 22;

    // Messages
    MessageReceived msg_received = 30;
    MessageEdited msg_edited = 31;
    MessageDeleted msg_deleted = 32;
    MessageStatusChanged msg_status = 33;    // pending→sent, sent→delivered, etc.

    // Presence
    TypingIndicator typing = 40;
    UserStatusChanged user_status = 41;

    // Media
    DownloadProgress download_progress = 50;
    DownloadComplete download_complete = 51;

    // Calls
    IncomingCall incoming_call = 60;
    CallStateChanged call_state = 61;
  }
}
```

### Event Flow

```
Core pushes Update via OnUpdate handler
    ↓
engine.handleUpdate(accountID, update)
    ↓
1. Deduplicate: if msg_id already in DB with same content → skip
2. Normalize content: platform format → RichContent proto
3. Cache: write/update SQLite (messages, chats, users)
4. Update chat list: bump last_msg_time, increment unread_count
5. Suppress: if (accountID, chatID) == activeChat → skip notification event
6. Dispatch: serialize EngineEvent → PushEvent → Dart
```

### Deduplication

Events are idempotent. The engine checks:
- `NewMessage`: does `(account_id, chat_id, msg_id)` exist in messages table? If yes, skip.
- `EditMessage`: does the content differ from cached version? If same, skip.
- `DeleteMessage`: is the message already marked deleted? If yes, skip.
- `Typing`: is there already a recent typing event for this user+chat in the last 5s? If yes, skip.

### Event Batching

For initial sync (e.g., Matrix /sync returns 500 messages at once), events are batched:
- Accumulate for 100ms
- Write all to SQLite in one transaction
- Push one `ChatListSnapshot` instead of 500 individual `ChatUpdated` events
- Dart rebuilds once, not 500 times

---

## 5. Auth State Machine

### Problem

10 platforms have 10 different auth flows. Without abstraction, Flutter needs 10 different auth screens.

### Solution

The engine drives auth as a generic state machine. The UI renders ONE adaptive screen.

### States

```protobuf
message AuthState {
  string account_id = 1;
  string platform = 2;

  oneof state {
    AuthChoose choose = 10;      // "Pick how you want to log in"
    AuthInput input = 11;        // "Type something in"
    AuthOTP otp = 12;            // "Enter the verification code"
    Auth2FA two_factor = 13;     // "Enter your 2FA password"
    AuthQR qr = 14;              // "Scan this QR code"
    AuthReady ready = 15;        // "Logged in successfully"
    AuthError error = 16;        // "Something went wrong"
  }
}

message AuthChoose {
  repeated string option_ids = 1;    // ["phone", "bot_token", "qr_code"]
  repeated string option_labels = 2; // ["Phone Number", "Bot Token", "QR Code"]
}

message AuthInput {
  string field_type = 1;  // "phone", "email", "text", "url", "password", "token"
  string label = 2;       // "Phone Number"
  string hint = 3;        // "+1234567890"
  string error = 4;       // "Invalid phone number" (if previous attempt failed)
}

message AuthOTP {
  int32 code_length = 1;      // 5 or 6
  string sent_to = 2;         // "Telegram app" or "SMS to +***89"
  int32 timeout_seconds = 3;  // countdown before resend allowed
  bool can_resend = 4;
}

message Auth2FA {
  string hint = 1;         // "cat***"
  bool has_recovery = 2;   // show "Forgot password?" link
}

message AuthQR {
  bytes qr_data = 1;       // raw bytes for QR code rendering
  int32 expires_in = 2;    // seconds until QR expires
}

message AuthReady {
  string display_name = 1; // "@nako"
  string avatar_b64 = 2;   // base64 thumbnail
}

message AuthError {
  string message = 1;      // "Wrong password"
  bool recoverable = 2;    // true = show retry, false = start over
}
```

### Platform Mapping

| Platform | Auth Flow |
|----------|-----------|
| Telegram | choose(phone/bot_token/qr) → input(phone) → otp → [2fa] → ready |
| Matrix | input(homeserver URL) → input(username) → input(password) → ready |
| IRC | input(server:port) → input(nickname) → [input(NickServ password)] → ready |
| XMPP | input(JID) → input(password) → ready |
| GitHub | input(PAT token) → ready |
| Bale | choose(phone/bot_token) → input(phone) → otp → ready |
| Rubika | input(phone) → otp → ready |
| Delta Chat | input(email) → input(IMAP password) → ready |
| TeamSpeak | input(server:port) → input(nickname) → [input(server password)] → ready |
| Mumble | input(server:port) → input(username) → [input(password)] → ready |

### Implementation

Each platform has an `authDriver` that translates between the generic state machine and the platform-specific `core.Authenticate()`:

```go
type authDriver interface {
    // InitialState returns the first auth state for this platform.
    InitialState() *AuthState

    // Advance processes user input and returns the next state.
    // May call core.Authenticate() internally when enough info is collected.
    Advance(current *AuthState, userInput string) (*AuthState, error)
}
```

The engine:
1. Calls `driver.InitialState()` when `AddAccount(platform)` is called
2. Pushes `AuthStateChanged` event to Dart
3. Dart renders the appropriate UI (text field, OTP input, QR code, etc.)
4. User submits input → Dart calls `SubmitAuthInput(accountID, input)`
5. Engine calls `driver.Advance(current, input)`
6. Driver builds up the `AuthConfig` incrementally and calls `core.Authenticate()` when ready
7. If auth succeeds → pushes `AuthReady`, saves credentials to vault, starts core connections
8. If auth fails → pushes `AuthError`, user retries or cancels

### Credential Persistence

On successful auth:
1. Engine saves credentials to vault: `vault.Put("accounts", accountID, credentialBlob)`
2. Engine inserts account into SQLite: `INSERT INTO accounts (...)`
3. On next app launch, engine reads accounts from SQLite, loads credentials from vault, calls `core.Authenticate()` with saved credentials (session resume, not full re-auth)

---

## 6. Content Normalization

### Problem

10 platforms format message content in 10 different ways. The Flutter UI needs one format to render.

| Platform | Native Format |
|----------|--------------|
| Telegram | Plain text + entity offsets (bold at byte 5-12, mention at 20-25) |
| Matrix | HTML body + plain text fallback |
| IRC | mIRC codes (^B bold, ^I italic, ^U underline, \x03 color) |
| XMPP | XHTML-IM or plain text |
| GitHub | Markdown |
| Delta Chat | MIME email (plain or HTML) |
| TeamSpeak | BBCode-ish |
| Mumble | HTML subset |
| Rubika | Custom JSON entities |
| Bale | Telegram-compatible entities |

### Solution: RichContent Proto

```protobuf
message RichContent {
  repeated RichBlock blocks = 1;
}

message RichBlock {
  oneof block {
    RichParagraph paragraph = 1;
    RichCodeBlock code_block = 2;
    RichQuote blockquote = 3;
  }
}

message RichParagraph {
  repeated RichSpan spans = 1;
}

message RichSpan {
  string text = 1;
  uint32 format_flags = 2;  // bitmask: BOLD=1, ITALIC=2, STRIKETHROUGH=4, CODE=8,
                             //          UNDERLINE=16, SPOILER=32
  string url = 3;            // non-empty if this span is a hyperlink
  string mention_user_id = 4;  // non-empty if this span mentions a user
  string mention_name = 5;     // display name for the mention
}

message RichCodeBlock {
  string code = 1;
  string language = 2;  // "go", "python", "" for no highlighting
}

message RichQuote {
  repeated RichParagraph paragraphs = 1;
}
```

### Storage: Dual Format

Each message stores both raw and normalized content:

- `content_raw` (BLOB): Original platform format. Used when editing a message (send platform-native format back to the server, not a re-serialization of our normalized form).
- `content_rich` (BLOB): Serialized `RichContent` proto. Used by Flutter for rendering.
- `content_text` (TEXT): Plain text extraction. Used for FTS5 search and chat list preview.

### Conversion

Each platform has a converter function in `go/engine/content.go`:

```go
func normalizeTelegram(text string, entities []tg.MessageEntity) *RichContent { ... }
func normalizeMatrixHTML(htmlBody string) *RichContent { ... }
func normalizeIRC(raw string) *RichContent { ... }
func normalizeMarkdown(md string) *RichContent { ... }
// etc.
```

These are called at message ingestion time (when a message arrives from the network or is loaded from the core). The normalized form is cached in SQLite. The conversion happens once per message, not on every render.

---

## 7. Pending Queue (Offline-First)

### Problem

User hits send, then loses WiFi. What happens to the message?

### Solution

Every outbound mutation goes through the pending queue. The message appears instantly in the UI (optimistic), then confirms or fails asynchronously.

### Flow

```
1. User taps send
2. Engine generates local_id = "local_" + random hex
3. Engine writes to `pending` table:
     local_id, action="send", payload=serialized msg, status=queued
4. Engine writes to `messages` table:
     local_id, msg_id=local_id, status=SENDING
5. Engine pushes MessageReceived event → UI shows message with ⏳
6. Engine calls core.SendMessage() in background goroutine
7a. SUCCESS:
     - Update messages: msg_id=server_id, status=SENT
     - Delete from pending
     - Push MessageStatusChanged → UI shows ✓
7b. FAILURE (network):
     - Update pending: status=failed, error_msg, retry_count++
     - Update messages: status=FAILED
     - Push MessageStatusChanged → UI shows ⚠ with retry
7c. APP CRASH/RESTART:
     - Engine.Init() scans pending table for status=queued or status=sending
     - Retries all (they were in-flight when crash happened)
     - status=failed items wait for user to tap retry
```

### Retry Policy

- Retry immediately on first failure
- Then: 2s, 5s, 15s, 30s delays (exponential backoff, capped at 30s)
- After 5 failures: mark as permanently failed, wait for user action
- Network errors: retry when connection state changes to "connected"

### Actions Supported

The pending queue handles not just sends but all outbound mutations:

| Action | What |
|--------|------|
| `send` | SendMessage, ReplyToMessage |
| `edit` | EditMessage |
| `delete` | DeleteMessage |
| `react` | ReactToMessage |
| `forward` | ForwardMessage |

---

## 8. Media Pipeline

### Download Queue

Downloads are priority-ordered:

| Priority | When | Example |
|----------|------|---------|
| 0 (highest) | User tapped download explicitly | Tapped a file attachment |
| 1 | Currently visible on screen | Image in viewport (auto-download) |
| 2 | Near viewport (prefetch) | Images ±20 messages from scroll position |
| 3 (lowest) | Background auto-download | Auto-download policy (WiFi only, etc.) |

Concurrency: max 3 simultaneous downloads per account, max 10 total.

### Download Flow

```
1. Engine receives message with media attachment
2. If thumb_b64 available from core → store in media table (instant display)
3. Check auto-download policy:
   - If allowed → enqueue at priority 3
   - If not → leave download_state=none, user taps to download
4. When download starts:
   - Update media: download_state=downloading
   - Push DownloadProgress events (every 100ms or 5% progress, whichever is less frequent)
5. When complete:
   - Write file to media/<account_id>/full/<hash>.<ext>
   - Update media: local_path=..., download_state=downloaded, last_accessed=now
   - Push DownloadComplete event
6. UI renders local file
```

### LRU Eviction

When total media cache exceeds `maxCacheSize` (configurable, default 1GB):

```go
func (e *Engine) evictMedia() error {
    // Never evict thumbnails (thumb_path) — they're tiny and always needed
    // Never evict files in the downloads/ dir — those are user-saved
    // Evict from media/*/full/ only, oldest last_accessed first
    rows, _ := e.db.Query(`
        SELECT account_id, chat_id, msg_id, seq, local_path, file_size
        FROM media
        WHERE local_path IS NOT NULL AND download_state = 2
        ORDER BY last_accessed ASC
    `)
    // Delete files until cache is under limit
    // Update media: local_path=null, download_state=none
}
```

Eviction runs:
- On engine startup
- After every completed download
- When `ClearCache()` is called

### Media Metadata in Messages (added session 16)

When `GetMessages` returns cached messages, `populateMediaMetadata()` joins the `media` table to attach media info for messages with `has_media=true`. This avoids a separate API call for every message with media.

Proto fields added to `EngineCachedMessage` (tags 18-27):
- `media_type` (int32): 0=none, 1=image, 2=video, 3=audio, 4=voice, 5=videonote, 6=sticker, 7=gif, 8=file
- `media_file_name`, `media_mime_type` (string)
- `media_file_size` (int64, bytes)
- `media_thumb_b64` (string, base64-encoded thumbnail for instant display)
- `media_local_path` (string, local file path if download_state==done)
- `media_width`, `media_height` (int32, for images/video)
- `media_duration` (int32, seconds for audio/video)
- `media_download_state` (int32): 0=none, 1=queued, 2=downloading, 3=done, 4=failed

Dart-side `CachedMessage` model exposes convenience getters: `isImage`, `isVideo`, `isAudio`, `isVoice`, `isSticker`, `isGif`, `isFile`, `isMediaDownloaded`, `mediaSizeLabel`.

The UI renders:
- Images/GIFs/stickers: inline with `Image.file` (downloaded) or base64 thumbnail (not yet downloaded) + download button
- Video: thumbnail + play icon + duration
- Audio/voice: play icon + duration + waveform placeholder
- Files: file icon + name + size + download button

### Thumbnail Generation

If the platform provides a thumbnail (Telegram's `photoStripped`, Matrix's `info.thumbnail_url`), use it.

If not, and the file is an image: generate a thumbnail using pure-Go image libraries (`disintegration/imaging`). Store as a small JPEG in `media/<account_id>/thumb/<hash>.jpg` and as base64 in the `thumb_b64` column.

---

## 9. Startup Sequence

```
T+0ms     Flutter renders splash screen
          Dart calls engine.Init(configDir, cacheDir, downloadDir)

T+30ms    Engine opens vault (user enters password if first launch)
          Engine opens/creates SQLite database, runs migrations

T+50ms    Engine reads accounts table → pushes AccountListChanged
          Dart renders platform rail with account icons

T+80ms    Engine reads chats table:
            SELECT ... FROM chats WHERE archived=0
            ORDER BY pinned DESC, last_msg_time DESC
            LIMIT 100
          Pushes ChatListSnapshot → Dart renders full chat list

          USER SEES THEIR CHATS. App feels instant.

T+100ms   Engine starts connecting accounts (parallel goroutines)
          For each account:
            1. Load credentials from vault
            2. Push ConnectionStateChanged(connecting) → orange dot on rail icon
            3. core.Authenticate(savedCredentials) — session resume
            4. If auth fails → Push AuthStateChanged(error) → UI shows re-login prompt
            5. If auth OK → Push ConnectionStateChanged(connected) → green dot

T+200ms+  As each core connects:
            1. Register OnUpdate handler
            2. Fetch fresh chat list from network: core.GetDialogs()
            3. Diff against cached chats
            4. Write new/changed chats to SQLite
            5. Push ChatUpdated events for changed items
            6. UI updates reactively

T+2000ms  All accounts connected. UI fully live.

ONGOING   Real-time events flow: core → engine → cache → event → UI
```

### Key Principle

The UI is interactive at T+80ms. Everything after that is background sync. The user never sees a loading spinner for data they've seen before. If the app was last used 5 minutes ago, the cached data is probably still accurate. If it was last used 3 days ago, it's stale but still better than a blank screen.

### Scan Pending Queue

During startup, after opening the DB:
```go
rows, _ := e.db.Query("SELECT * FROM pending WHERE status IN (0, 1)")
// status 0 = queued (never attempted)
// status 1 = sending (was in-flight when app died)
for rows.Next() {
    // Re-enqueue for retry
}
```

---

## 10. Dart State Layer

### Pattern: Riverpod 3 StreamProvider

The Go engine is the source of truth. Dart maintains a read-only mirror, updated by events from the bridge. Widgets rebuild reactively when their specific data changes.

```
Bridge event stream (Stream<Uint8List>)
    ↓ decode protobuf
Event dispatcher (fans out by event type)
    ├─→ AccountListProvider    (list of connected accounts)
    ├─→ ConnectionStateProvider (per-account connection status)
    ├─→ ChatListProvider       (unified chat list)
    ├─→ ActiveChatProvider     (messages for currently open chat)
    ├─→ TypingProvider         (who's typing where)
    ├─→ DownloadProvider       (active download progress)
    └─→ CallProvider           (active call state)

UI-only state (not from engine):
    ├─→ ScrollPositionProvider (per-chat scroll offset)
    ├─→ SelectionProvider      (multi-select mode, selected messages)
    ├─→ PanelProvider          (which right panel is open)
    ├─→ ThemeProvider          (current theme, accent color)
    └─→ InputProvider          (reply bar, edit bar, formatting toolbar)
```

### ChatListProvider Example

```dart
class ChatListNotifier extends Notifier<List<ChatInfo>> {
  @override
  List<ChatInfo> build() => [];  // empty on init, populated by engine events

  void handleSnapshot(ChatListSnapshot snapshot) {
    state = snapshot.chats;
  }

  void handleUpdate(ChatUpdated update) {
    state = [
      for (final chat in state)
        if (chat.chatId == update.chatId && chat.accountId == update.accountId)
          update.chat  // replace
        else
          chat,
    ]..sort((a, b) {
      // pinned first, then by time
      if (a.isPinned != b.isPinned) return b.isPinned ? 1 : -1;
      return b.lastMsgTime.compareTo(a.lastMsgTime);
    });
  }

  void handleRemoved(ChatRemoved removed) {
    state = state.where((c) =>
      !(c.chatId == removed.chatId && c.accountId == removed.accountId)
    ).toList();
  }
}
```

### ActiveChatProvider Example

When user opens a chat:
1. Dart calls `engine.SetActiveChat(accountID, chatID)` (notification suppression)
2. Dart calls `engine.GetMessages(accountID, chatID, limit: 50)` → gets cached messages instantly
3. Dart listens for `MessageReceived`, `MessageEdited`, `MessageDeleted` events filtered to this chat
4. On scroll-back: calls `engine.GetMessages(accountID, chatID, before: oldestMsgID, limit: 50)` for older pages

### Key Rule

**Dart never calls core methods directly for data that the engine caches.** For chat list, messages, user profiles — always go through the engine. For operations that aren't cached (create group, ban member, etc.) — Dart calls through the existing raw core dispatch.

---

## 11. Platform-Specific Concerns

### Web (GOOS=js GOARCH=wasm)

`modernc.org/sqlite` does NOT compile to WASM. The `modernc.org/libc` package requires OS-level syscalls unavailable in the browser sandbox.

**Strategy for web:**

The engine defines a `CacheBackend` interface:

```go
type CacheBackend interface {
    Open(configDir string) error
    Close() error

    // Chat list
    GetChats(accountID string, archived bool, limit, offset int) ([]ChatRow, error)
    UpsertChat(row ChatRow) error
    // ... etc for all cache operations

    // Messages
    GetMessages(accountID, chatID string, before int64, limit int) ([]MessageRow, error)
    InsertMessage(row MessageRow) error
    // ... etc

    // Search
    SearchFTS(query string, accountID string, limit int) ([]SearchHit, error)
}
```

Native targets: `SQLiteCacheBackend` implements this with `modernc.org/sqlite`.

Web target options (to be decided when web is built):

1. **In-memory only**: No persistence on web. Engine holds state in Go maps within the WASM module. On page reload, refetch from network. Simple, works, but loses chat history on refresh.

2. **Dart-side IndexedDB bridge**: The WASM engine calls back to Dart (via JS interop) for storage operations. Dart uses `idb_shim` or similar to persist to IndexedDB. More complex but survives page reloads.

3. **sql.js via JS interop**: Use the Emscripten-compiled SQLite (sql.js) from Go WASM via `js.Global()` calls. Same SQL schema, different backend. Most compatible but adds another WASM module.

For V1: **build native targets first (Linux, Windows, macOS, Android)**. Web can launch with option 1 (in-memory only) and be upgraded to option 2 later. The `CacheBackend` interface ensures no code changes are needed in the engine — just swap the backend.

### Android

- Dart passes scoped storage paths to `engine.Init()` at startup
- Go never guesses Android paths — always uses what Dart provides
- Foreground service keeps the engine alive in background (otherwise Android kills the process and connections drop)
- `OverrideConfigDir` / `OverrideCacheDir` in `utils/storage.go` are set from Dart-provided paths

### Desktop (Linux, Windows, macOS)

- Standard filesystem access via `os.UserConfigDir()` / `os.UserCacheDir()`
- System tray integration (Dart-side via `system_tray` plugin)
- Multiple windows: V2 feature. V1 = single window, single active chat.

### RTL Support

Rubika is an Iranian platform. A significant portion of the user base reads right-to-left (Farsi). Flutter handles RTL natively via `Directionality`, but:

- Text that mixes RTL and LTR (Farsi user quoting English code) needs `TextDirection.auto` per paragraph
- Chat bubble alignment should flip in RTL mode (sent = left, received = right)
- Platform rail position stays on the left (like Discord, regardless of language)
- Build RTL support from day 1 — retrofitting is painful

---

## 12. Call Subsystem

Voice/video calls are a specialized subsystem that sits alongside the engine, not inside it.

### Why Separate

The engine handles text state (messages, chats, cache) via request/response + events over the protobuf bridge. Calls need **real-time media streams** — audio samples at 48kHz (50 packets/second) and video frames at 30fps. The protobuf bridge is too slow for this.

### Architecture

```
Flutter (Dart)
├── Audio capture (microphone → raw PCM via flutter plugin)
├── Audio playback (raw PCM → speaker via flutter plugin)
├── Video capture (camera → frames via flutter plugin)
├── Video display (Texture widget, GPU-side)
│
│   ── FFI (direct pointer, not protobuf) ──
│
Go Engine
├── Call signaling (via core: StartCall, AcceptCall, EndCall)
├── Call state events (via standard PushEvent)
│
Go Core
├── Codec: Opus encode/decode (audio), VP8 (video) — pure Go
├── Network: send/receive media packets (platform-specific)
├── RTP/SRTP/DTLS (via pion/webrtc where applicable)
```

### Audio Path

```
Mic → Dart plugin → FFI shared buffer → Go Opus encode → Network
Network → Go Opus decode → FFI shared buffer → Dart plugin → Speaker
```

The FFI shared buffer is a ring buffer allocated by Go, pointer passed to Dart. Dart writes/reads PCM samples directly — no serialization, no copying through protobuf.

Audio frame = 20ms at 48kHz = 960 samples = 1920 bytes. 50 FFI reads/writes per second. Trivial overhead.

### Video Path

```
Camera → Dart plugin → FFI texture → Go VP8 encode → Network
Network → Go VP8 decode → Flutter Texture widget → Screen
```

Go writes decoded RGBA frames to a Flutter `Texture` (backed by platform-native texture). Flutter renders it with zero-copy on the GPU side.

### Call Lifecycle (from engine perspective)

1. User taps call button → Dart calls `engine.StartCall(accountID, chatID, video)`
2. Engine delegates to `core.StartCall()` → returns `CallSession` with signaling info
3. Engine pushes `CallStateChanged(ringing)` event
4. Dart shows call UI, starts audio/video capture
5. Core establishes media channel → Engine pushes `CallStateChanged(active)`
6. Media flows directly between Dart (device I/O) and Go (codec + network) via FFI buffers
7. User taps end → Dart calls `engine.EndCall(accountID, callID)`
8. Engine calls `core.EndCall()` → pushes `CallStateChanged(ended)`
9. Dart stops capture, hides call UI

---

## 13. Configuration

### Expanded AppConfig

The current `AppConfig` needs expansion for the GUI:

```go
type AppConfig struct {
    // Display
    Theme       string `json:"theme"`        // "dark", "light", "system"
    AccentColor string `json:"accent_color"`  // hex color, e.g. "#4f6ef7"
    FontScale   float64 `json:"font_scale"`   // 0.8 = small, 1.0 = normal, 1.2 = large
    Language    string `json:"language"`      // "en", "fa", "ru", etc.

    // Downloads
    DownloadDir string `json:"download_dir"`
    MaxCacheSize int64 `json:"max_cache_size"` // bytes, 0 = unlimited, default 1GB

    // Auto-download
    AutoDownload AutoDownloadConfig `json:"auto_download"`

    // Network
    ProxyConfig  ProxyConfig       `json:"proxy_config"`
    DNSOverrides map[string]string `json:"dns_overrides"`
    DNSFallback  bool              `json:"dns_fallback"`

    // Privacy
    SendReadReceipts  bool `json:"send_read_receipts"`   // default true
    SendTyping        bool `json:"send_typing"`          // default true

    // Notifications
    NotifyDMs         bool `json:"notify_dms"`           // default true
    NotifyGroups      bool `json:"notify_groups"`        // default true
    NotifyMentionsOnly bool `json:"notify_mentions_only"` // default false
}

type AutoDownloadConfig struct {
    PhotosWiFi   bool  `json:"photos_wifi"`    // default true
    PhotosMobile bool  `json:"photos_mobile"`  // default true
    VideosWiFi   bool  `json:"videos_wifi"`    // default true
    VideosMobile bool  `json:"videos_mobile"`  // default false
    FilesWiFi    bool  `json:"files_wifi"`     // default false
    FilesMobile  bool  `json:"files_mobile"`   // default false
    MaxVideoSize int64 `json:"max_video_size"` // bytes, default 10MB
    MaxFileSize  int64 `json:"max_file_size"`  // bytes, default 5MB
}
```

### Per-Account Config

Some settings are per-account (stored in vault alongside credentials):

```go
type AccountConfig struct {
    ProxyOverride *ProxyConfig `json:"proxy_override"` // nil = use global proxy
    AutoConnect   bool         `json:"auto_connect"`   // connect on app startup
    NotifyEnabled bool         `json:"notify_enabled"` // per-account notification toggle
}
```

---

## 14. Testing Strategy

### Principle

Every layer has automated tests. No manual-only verification. The test suite must catch regressions before the user sees them.

### Layer 1: Engine Unit Tests (Go)

Each engine component has its own `_test.go`. These run against a real SQLite DB (in-memory or temp file) but use **mock cores** — no network, no credentials.

```go
// Mock core that implements cores.Core with canned responses
type mockCore struct {
    name        string
    dialogs     []cores.Dialog
    messages    map[string][]cores.Message  // chatID → messages
    sendErr     error                        // inject failures
    authErr     error
    updates     chan cores.Update            // inject fake updates
}
```

**What to test per component:**

| Component | Test Cases |
|-----------|-----------|
| `db.go` | Schema creation, migration v1→v2, WAL mode enabled, concurrent read/write (10 goroutines), corrupt DB detection + recovery |
| `accounts.go` | Add/remove/list accounts, vault credential round-trip, duplicate account rejection, account deletion cascades (chats/messages cleaned up) |
| `auth.go` | Every platform's auth flow end-to-end with mock core (10 tests), error recovery (wrong password → retry), cancel mid-flow, session resume from vault |
| `cache_chats.go` | Insert/update/query chats, unified sort (pinned first, then by time), archive/mute/draft persistence, diff sync (network returns changed chats → only changed ones update) |
| `cache_msgs.go` | Insert/query/paginate messages, FTS5 search accuracy (partial match, unicode, CJK, Farsi), duplicate message rejection, local_id → server_id replacement |
| `pending.go` | Queue → send → confirm flow, queue → fail → retry flow, crash recovery (restart engine, pending items retried), max retry limit, backoff timing |
| `content.go` | Normalize each of 10 platform formats → RichContent, round-trip fidelity (raw → normalize → render matches original intent), edge cases (empty message, only emoji, 10k chars, mixed RTL/LTR) |
| `media.go` | Download queue priority ordering, LRU eviction (insert 2GB, verify oldest evicted first, thumbnails survive), concurrent download limit, cancel mid-download |
| `events.go` | Deduplication (same msg_id twice → one event), batching (500 messages → one snapshot), notification suppression (active chat skipped), event ordering |
| `search.go` | Cross-account FTS5, ranking (recent first), empty query, special chars, result count limit |

**Run command:** `cd go && go test ./engine/... -v -timeout 120s -count 1`

These tests are **fast** (no network, in-memory DB) and run on every commit.

### Layer 2: Engine Integration Tests (Go)

These test the engine against **real cores with real credentials** (like the existing Step 1-12 tests). They verify the engine correctly wraps each core.

One test per platform:
1. Engine.Init() → AddAccount(platform) → drive auth flow → verify AuthReady
2. Verify chat list syncs from network → cached in SQLite → survives restart
3. Send message through pending queue → verify message appears in chat on the other side
4. Receive message → verify it arrives in cache + event pushed
5. Download media → verify file on disk → evict → verify file gone, thumb survives

**Run command:** `source auth/auth.md && cd go/tests && go test -run TestEngine -v -timeout 300s`

These are slow (network) and run manually, not on every commit.

### Layer 3: Bridge Tests (Go + Dart)

Test the FFI boundary:

**Go side:** `bridge_test.go` — serialize a request, call `bridge.Call()`, verify response deserializes correctly. Test engine routing (`__engine` core_id) separately from core routing.

**Dart side:** `bridge_test.dart` — load the shared library, call `bridge.call()` with known request bytes, verify response bytes decode correctly. Test event stream delivery.

### Layer 4: Flutter Widget Tests (Dart)

Every screen and reusable widget has widget tests with a **mock bridge** that returns canned protobuf responses. No Go, no FFI, no network.

```dart
class MockBridge implements Bridge {
  final Map<String, Uint8List> _responses = {};  // method → canned response
  final StreamController<Uint8List> _events = StreamController.broadcast();

  void stubResponse(String method, GeneratedMessage response) { ... }
  void pushEvent(EngineEvent event) { ... }

  @override
  Uint8List call(Uint8List request) { ... }

  @override
  Stream<Uint8List> get events => _events.stream;
}
```

**What to test per screen:**

| Screen | Test Cases |
|--------|-----------|
| Splash | Vault password entry, wrong password error, loading state |
| Auth | All 7 auth state types render correctly, input validation, error display, cancel flow |
| Platform rail | Account icons, connection status dots (green/orange/red), unread badges, reorder |
| Chat list | Empty state ("No chats yet"), populated list sorts correctly, unread count, muted dimmed, typing indicator, search filter, context menu actions |
| Chat view | Message bubbles (sent/received), timestamps, reply quotes, reactions, edit indicator, media placeholders, scroll-to-bottom button, date separators, unread separator |
| Input area | Text entry, send button, reply bar, edit mode bar, markdown toolbar, mention autocomplete, emoji panel toggle, channel read-only notice |
| Settings | Theme toggle, accent color picker, proxy config, cache size display + clear button, auto-download toggles |
| Search | Query input, results list with highlighted matches, cross-account results, empty results |
| Call screen | Incoming call banner, active call overlay, mute/video/end buttons, participant list, connection quality |

**Run command:** `cd dart && flutter test`

### Layer 5: Golden Screenshot Tests (Dart)

For visual regression detection. Capture screenshots of every screen in both themes (dark + light) and compare against golden files.

```dart
testWidgets('chat list dark theme', (tester) async {
  await tester.pumpWidget(buildApp(theme: 'dark', mockData: sampleChatList));
  await expectLater(
    find.byType(ChatListScreen),
    matchesGoldenFile('goldens/chat_list_dark.png'),
  );
});
```

Generate goldens for:
- Every screen (10 screens × 2 themes = 20 goldens)
- Every chat type (DM, group, topic group, channel = 4 goldens)
- RTL layout (key screens in Farsi = 4 goldens)
- Edge cases: empty state, error state, loading state (6 goldens)

**Run command:** `cd dart && flutter test --update-goldens` (to regenerate)

### Layer 6: Performance Benchmarks (Go)

Prevent perf regressions in hot paths:

```go
func BenchmarkChatListQuery(b *testing.B) {
    // Pre-fill DB with 10,000 chats across 10 accounts
    for i := 0; i < b.N; i++ {
        engine.GetUnifiedChatList(50, 0)
    }
}

func BenchmarkMessageInsert(b *testing.B) {
    // Insert messages one at a time (simulates real-time update)
}

func BenchmarkFTS5Search(b *testing.B) {
    // Pre-fill 100k messages, search
}

func BenchmarkContentNormalize(b *testing.B) {
    // Normalize a complex Telegram message with 20 entities
}
```

Benchmark targets:
- `GetUnifiedChatList(50, 0)` with 10k chats: < 5ms
- Single message insert + FTS5 index: < 1ms
- FTS5 search across 100k messages: < 50ms
- Content normalization: < 100us per message

### CI Pipeline

```yaml
# .github/workflows/test.yml
on: [push, pull_request]

jobs:
  go-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/setup-go@v5
        with: { go-version: '1.26' }
      - run: cd go && go test ./engine/... ./utils/... ./bridge/... -v -timeout 120s
      - run: cd go && go test -bench=. ./engine/... -benchtime=3s

  dart-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: subosito/flutter-action@v2
      - run: cd dart && flutter test
      - run: cd dart && flutter test --update-goldens  # verify goldens match
```

Integration tests (with real credentials) run manually, not in CI.

---

## 15. Error Recovery & Resilience

### Core Isolation: One Crash Doesn't Kill the App

Each core runs in its own goroutine. If a core panics, the engine catches it and keeps the other 9 running.

```go
func (e *Engine) runCore(acc *Account) {
    defer func() {
        if r := recover(); r != nil {
            log.Printf("core %s panicked: %v", acc.ID, r)
            e.setConnState(acc.ID, ConnStateDisconnected)
            e.pushEvent(ConnectionStateChanged{
                AccountID: acc.ID,
                State:     "error",
                Error:     fmt.Sprintf("internal error: %v", r),
            })
            // Schedule reconnect after 30s
            time.AfterFunc(30*time.Second, func() {
                e.reconnectAccount(acc.ID)
            })
        }
    }()
    // ... run core connection
}
```

The UI shows a red dot on the crashed platform's rail icon + an error banner. Other platforms continue working normally.

### SQLite Corruption Recovery

SQLite is very resilient (WAL journal, atomic commits), but corruption can happen (disk failure, power loss at exactly the wrong moment).

Detection:
```go
func (e *Engine) checkDBIntegrity() error {
    var result string
    e.db.QueryRow("PRAGMA integrity_check").Scan(&result)
    if result != "ok" {
        return fmt.Errorf("database corruption detected: %s", result)
    }
    return nil
}
```

Recovery:
1. Run `PRAGMA integrity_check` on engine startup
2. If corrupt: rename `cache.db` to `cache.db.corrupt`, log the issue
3. Create a fresh `cache.db` with empty schema
4. On next network sync, caches rebuild naturally from network data
5. Message history older than the most recent sync window is lost — but credentials (in vault) and accounts (rebuilt from vault) survive

The vault is a separate file, so credential corruption is independent. Vault corruption is more serious (requires re-entering all credentials). The vault format is simple (one JSON blob encrypted, no pages/blocks to corrupt partially), so partial corruption is unlikely — it's all-or-nothing.

### Disk Full

```go
func (e *Engine) checkDiskSpace() error {
    // Check available space in config dir
    var stat syscall.Statfs_t
    syscall.Statfs(e.configDir, &stat)
    available := stat.Bavail * uint64(stat.Bsize)
    if available < 50*1024*1024 {  // < 50MB
        return ErrDiskLow
    }
    return nil
}
```

When disk is low:
1. Stop all media downloads
2. Run aggressive media eviction
3. Push a system event to UI: "Low disk space — media downloads paused"
4. Continue text messaging (SQLite inserts are tiny)
5. If critically low (< 10MB): push warning, refuse non-essential writes

### Flaky Network (Not Off, Just Bad)

Worse than offline — packets arrive sometimes, connections half-open, timeouts everywhere.

Strategy:
- Each core already handles reconnection. The engine adds monitoring:
- If a core disconnects and reconnects more than 3 times in 60 seconds → mark as "unstable"
- Unstable cores: increase reconnect delay (30s → 60s → 120s), push ConnectionStateChanged("unstable") → UI shows yellow dot
- When stable for 5 minutes: reset to normal reconnect behavior

### Vault Password Forgotten

No recovery — the vault is encrypted with Argon2id, there's no backdoor.

What happens:
1. App starts → splash screen → password prompt
2. User enters wrong password → "Wrong password" error
3. After 5 wrong attempts: show "Reset vault?" option
4. Reset vault = delete `uniclient.vault`, delete `cache.db`, start fresh
5. All credentials lost, all cache lost. User re-adds all accounts.

This is by design — if there were a backdoor, the encryption would be meaningless.

### Out-of-Memory (Android)

Android can kill background apps when memory is low. The engine handles this by:
- Pending queue persists to SQLite (survives kill)
- Foreground service notification tells Android "this is important, don't kill me" (reduces likelihood)
- If killed anyway: on next launch, engine scans pending table + reconnects

### Graceful Shutdown

```go
func (e *Engine) Shutdown() error {
    // 1. Stop accepting new operations
    e.mu.Lock()
    e.shuttingDown = true
    e.mu.Unlock()

    // 2. Flush pending writes to SQLite
    // (batched writes that haven't been committed yet)

    // 3. Save vault (if dirty)
    e.vault.Save()

    // 4. Close all cores (parallel, with 5s timeout)
    var wg sync.WaitGroup
    for _, acc := range e.accounts {
        wg.Add(1)
        go func(a *Account) {
            defer wg.Done()
            ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
            defer cancel()
            a.Core.Close()
        }(acc)
    }
    wg.Wait()

    // 5. Close SQLite
    e.db.Close()
    return nil
}
```

Dart calls `engine.Shutdown()` in `AppLifecycleState.detached` (or equivalent platform lifecycle).

---

## 16. Upload Pipeline

### Flow

```
1. User picks file (Dart file picker → gets path)
2. Dart calls engine.SendFile(accountID, chatID, filePath, caption)
3. Engine checks:
   a. File exists and is readable
   b. File size vs platform limit (Telegram: 2GB user/50MB bot, Bale: 19.5MB, etc.)
   c. If too large → split using utils/filesplit.go → queue each part
4. Engine creates pending entry:
   local_id, action="upload", payload includes file path
5. Engine inserts message with status=SENDING + media with download_state=uploading
6. Engine pushes MessageReceived → UI shows message with progress bar
7. Engine calls core.UploadFile() with progress callback:
   - Progress callback → push DownloadProgress events (reused for uploads too)
   - Every 100ms or 5%, whichever is less frequent
8. On success:
   - Update message: status=SENT, update media refs
   - Delete pending entry
   - Push MessageStatusChanged
9. On failure:
   - Update pending: status=failed
   - Push MessageStatusChanged → UI shows retry button
```

### Platform Size Limits

| Platform | Max File Size | Split Strategy |
|----------|--------------|----------------|
| Telegram (user) | 2 GB | No split needed (huge limit) |
| Telegram (bot) | 50 MB | Split at 49 MB |
| Bale | 19.5 MB | Split at 19 MB |
| Rubika | 200 MB | Split at 199 MB |
| Matrix | Server-dependent (usually 50-100 MB) | Query server limit, split accordingly |
| Delta Chat | ~25 MB (email attachment limit) | Split at 24 MB |
| XMPP | HTTP Upload, server-dependent | Query max, split accordingly |
| GitHub | 25 MB (API limit) | Split at 24 MB |
| TeamSpeak | N/A (no file transfer in Core) | ErrNotSupported |
| Mumble | N/A | ErrNotSupported |
| IRC | DCC (direct peer-to-peer) | No limit, no split |

Split files get reassembled by the recipient's uniclient instance automatically (via `utils/filesplit.go` naming convention: `file.zip.part01`, `.part02`, etc.).

### Upload Resume

If the app dies mid-upload:
- Pending table has the file path and action="upload"
- On restart, engine checks if file still exists at that path
- If yes: re-upload from the beginning (most platforms don't support partial upload resume)
- If no (temp file was cleaned up): mark as permanently failed

### Compression Before Upload

If the user has encryption enabled for the chat:
1. Read file
2. Compress with Zstd (`utils/compression.go`)
3. Encrypt with chat key (`utils/encryption.go`)
4. Upload compressed+encrypted blob
5. Recipient reverses: decrypt → decompress

Without encryption: upload raw file (platforms do their own compression).

---

## 17. Connection Health

### Per-Account Connection Lifecycle

```
States:
    disconnected → connecting → connected → disconnected (cycle)
                                         → unstable → disconnected
                                         → auth_required (session expired)

Transitions:
    disconnected → connecting:  engine.Init() or manual reconnect
    connecting → connected:     core.Authenticate() succeeds + OnUpdate registered
    connected → disconnected:   network error, server close, core error
    connected → unstable:       3+ reconnects in 60 seconds
    connected → auth_required:  core returns ErrAuth or ErrSessionExpired
    unstable → connected:       stable for 5 minutes (no disconnects)
    auth_required → connecting: user re-enters credentials via auth FSM
```

### Reconnection Strategy

```go
type reconnectState struct {
    attempts    int
    lastAttempt time.Time
    backoff     time.Duration
}

func (r *reconnectState) nextDelay() time.Duration {
    delays := []time.Duration{0, 2*time.Second, 5*time.Second, 15*time.Second, 30*time.Second, 60*time.Second}
    idx := r.attempts
    if idx >= len(delays) {
        idx = len(delays) - 1
    }
    base := delays[idx]
    // Add jitter: ±25%
    jitter := time.Duration(rand.Int63n(int64(base) / 2)) - base/4
    return base + jitter
}
```

- First reconnect: immediate (0s)
- Then: 2s, 5s, 15s, 30s, 60s (capped)
- Jitter prevents thundering herd if multiple accounts disconnect simultaneously
- Reset attempt counter on successful connection lasting > 60 seconds

### Staggered Initial Connection

On startup, don't connect all 10 accounts at once. Stagger by 100ms:

```go
for i, acc := range e.accounts {
    time.AfterFunc(time.Duration(i)*100*time.Millisecond, func() {
        e.connectAccount(acc.ID)
    })
}
```

This prevents:
- CPU spike on startup (10 TLS handshakes at once)
- Network congestion (10 simultaneous auth flows)
- Battery drain spike on mobile

### Heartbeat Monitoring

Each core has its own keepalive mechanism (Telegram: PING, IRC: PING/PONG, XMPP: whitespace keepalive, etc.). The engine doesn't duplicate this but monitors it:

```go
func (e *Engine) monitorConnection(acc *Account) {
    ticker := time.NewTicker(30 * time.Second)
    for range ticker.C {
        if acc.ConnState == ConnStateConnected {
            // Check if we've received any event from this core in the last 60s
            if time.Since(acc.lastEventTime) > 60*time.Second {
                // No events in 60s — might be a zombie connection
                // Send a lightweight probe (e.g., GetDialogs with limit=1)
                if _, err := acc.Core.GetDialogs(cores.PaginationOpts{Limit: 1}); err != nil {
                    e.handleDisconnect(acc.ID, err)
                }
            }
        }
    }
}
```

---

## 18. Notifications

### Desktop (Linux, Windows, macOS)

- Use `flutter_local_notifications` plugin
- Engine pushes `Notification` event when a message arrives for a non-active chat
- Dart creates system notification with:
  - Title: sender name (or chat name for groups)
  - Body: message preview (plain text, max 100 chars)
  - Icon: cached avatar (or platform icon if no avatar)
  - Click action: open the relevant chat
- Group notifications by chat (multiple messages in same chat → update existing notification, don't stack)
- System tray icon shows total unread badge count

### Android

Same as desktop but additionally:
- Foreground service notification: persistent "Uniclient is running" notification (required by Android to keep the service alive)
- Message notifications: high-priority, heads-up display
- Notification channels: one per platform (so user can control per-platform notification settings in Android settings)
- Reply from notification (Android direct reply API) → sends through pending queue

### Notification Suppression Rules

```
DO NOT notify if:
  - (accountID, chatID) == activeChat (user is looking at this chat)
  - Chat is muted
  - Account notification is disabled (per-account toggle)
  - Global notification category is disabled (e.g., NotifyGroups=false and it's a group)
  - NotifyMentionsOnly=true and the message doesn't mention the user
  - The message was sent by the user themselves (from another device)

DO notify if:
  - All above checks pass
  - Message is a DM (unless muted)
  - Message mentions the user (regardless of other settings)
  - Incoming call (always notify, even if chat is muted)
```

### Badge Count

Total unread count across all accounts, shown on:
- Desktop: system tray icon badge
- Android: app icon badge (via `flutter_local_notifications`)
- Sidebar: per-platform unread count on rail icons, per-chat unread count on chat list items

Updated whenever `ChatUpdated` event changes `unread_count`. Dart sums all non-muted chat unread counts.

---

## 19. Edge Cases & First Impressions

### First-Run Experience (Zero Accounts)

When the app launches for the first time:
1. Splash screen → prompt to create vault password (or skip for no encryption)
2. Main screen renders with empty platform rail + empty chat list
3. Center of screen shows: "Welcome to Uniclient" + large "Add Account" button + list of supported platforms with icons
4. Tapping a platform starts the auth state machine flow
5. On successful auth: platform icon appears on rail, chat list populates from network
6. On second account: same flow, new icon on rail, chats merge into unified list

The zero-state must feel intentional, not broken. No "Error: no accounts" messages.

### Forward Across Platforms

User forwards a Telegram message to a Matrix chat:
1. UI calls `engine.ForwardCrossAccount(fromAccount, fromChat, msgID, toAccount, toChat)`
2. Engine reads the original message from cache (or fetches from source core)
3. Engine converts content: RichContent is already normalized, so it's platform-agnostic
4. Engine sends via destination core: `destCore.SendMessage(toChat, convertedMsg)`
5. For media: engine downloads from source platform, then uploads to destination platform
6. Attribution: prepend "Forwarded from [sender] via [platform]:" to message text

Limitations: platform-specific content (Telegram stickers, Matrix reactions) may not translate perfectly. Stickers become image files. Reactions become text.

### Edit Message Round-Trip

1. User taps edit on a message
2. Dart calls `engine.GetMessageRaw(accountID, chatID, msgID)` → returns `content_raw` from SQLite
3. Engine converts raw content back to editable text:
   - Telegram entities → markdown-ish text (bold markers, etc.)
   - Matrix HTML → plain text (or rendered in markdown input)
   - IRC/XMPP → plain text
4. Dart pre-fills input field with editable text
5. User edits and hits save
6. Dart calls `engine.EditMessage(accountID, chatID, msgID, newText)`
7. Engine converts edited text back to platform-native format
8. Engine sends via core.EditMessage() + updates cache

### Rapid Concurrent Sends

User types and sends 10 messages in 2 seconds:
- Each gets a unique `local_id` and goes through the pending queue independently
- All 10 appear in the UI immediately with ⏳ status
- Engine sends them sequentially (ordered by `created_at` in pending table) to preserve order
- Each confirms independently (✓)
- If one fails, the others still send — failed one shows ⚠

The pending queue processes one send per chat at a time (to preserve ordering) but different chats can send concurrently.

### Large Chat List (10,000 Chats)

If a user has many accounts with many chats:
- SQLite query with index is fast (< 5ms for 10k rows with LIMIT 50)
- Flutter `ListView.builder` only builds visible items (50-70 widgets, not 10k)
- Chat list pagination: load 100 initially, load more on scroll
- Search uses FTS5 (fast even on 10k+ chats by title)

### Emoji & Sticker Normalization

Each platform has different emoji/sticker support:
- **Emoji**: Unicode is universal. All platforms render system emoji. No normalization needed.
- **Custom emoji** (Telegram premium): stored as reference in `Extra`. Rendered as image if available, fallback to 🔲 placeholder with tooltip.
- **Stickers**: each platform has its own format. Engine downloads sticker media like any other file. Flutter renders:
  - Static stickers: as images
  - Animated stickers (Telegram TGS): as Lottie animations (Flutter has `lottie` package)
  - Video stickers (Telegram webm): as looping video via media_kit
  - Other platform stickers: as static images

### Link Previews

Generation is **Go-side** (not Dart):
1. When engine processes an outgoing/incoming message containing URLs
2. Engine extracts URLs from RichContent spans (any span with non-empty `url` field)
3. Engine fetches URL metadata (title, description, image) via HTTP GET + HTML parsing
4. Engine stores preview data in message `Extra` field
5. Flutter renders preview card below the message bubble

Caching: link previews are stored in the message's `Extra` field in SQLite. Fetched once, cached forever.

Rate limiting: max 3 concurrent preview fetches, 1s delay between fetches, skip URLs from known non-previewable domains (e.g., private IPs, localhost).

### Duplicate Account Prevention

Can the user add the same Telegram account twice?
- After successful auth, engine checks: is there already an account with the same (platform, user_id)?
- If yes: reject with error "This account is already connected"
- The check uses the user ID returned by the core after auth, not the phone number (phone can change)

### Message Ordering Guarantees

Messages can arrive out of order (especially on reconnect/sync). The UI must display them in timestamp order regardless of arrival order.

- SQLite stores messages with `timestamp` (server timestamp when available, send time when not)
- Query always uses `ORDER BY timestamp DESC`
- When a message arrives with a timestamp older than existing messages: it's inserted at the correct position in the DB. UI re-reads from DB for the affected chat.

### Accessibility

- Every interactive widget has a `Semantics` label
- Screen reader announces: message sender, text, time, status (sent/delivered/read)
- Focus traversal: Tab through chat list → messages → input. Escape goes back.
- High contrast: respect `MediaQuery.highContrast` → increase border widths, use fully opaque colors
- Font scaling: respect system font size via `MediaQuery.textScaleFactor`. All layout uses relative sizes, not fixed pixel values.
- Reduced motion: respect `MediaQuery.disableAnimations` → skip transitions, use instant state changes

### Keyboard Shortcuts (Desktop)

| Shortcut | Action |
|----------|--------|
| Ctrl+K | Search (focus search input) |
| Ctrl+N | New message (open compose) |
| Escape | Close panel / deselect / go back |
| Up/Down | Navigate chat list |
| Enter | Open selected chat / send message |
| Ctrl+Enter | New line in message (when Enter sends) |
| Ctrl+E | Toggle emoji panel |
| Ctrl+Shift+M | Mute current chat |
| Alt+Up/Down | Switch between chats |
| Ctrl+1-9 | Switch to platform 1-9 on rail |

---

## 20. Build Plan

### Phase A: Engine Foundation

Build `go/engine/` with core functionality. No Flutter yet.

```
1. db.go           — SQLite open, schema, migrations, WAL mode
2. engine.go       — Engine struct, Init/Shutdown, graceful shutdown
3. accounts.go     — Account CRUD, credential storage in vault
4. auth.go         — Auth state machine, all 10 platform drivers
5. cache_chats.go  — Chat list cache (write from network, read from DB)
6. cache_msgs.go   — Message cache, pagination, FTS5
7. cache_users.go  — User profile cache
8. events.go       — Event normalization, dedup, batching, dispatch
9. pending.go      — Outbox queue, retry logic, crash recovery
10. content.go     — Content normalization (10 formats → RichContent)
11. media.go       — Download queue, upload pipeline, LRU eviction
12. search.go      — FTS5 cross-account search
13. health.go      — Connection monitoring, reconnection, stagger
```

**Test gate:** Full engine unit test suite passes (all components, mock cores). Benchmark targets met. Restart-persistence verified.

### Phase B: Bridge Integration

Wire the engine into the existing protobuf bridge.

```
1. Define engine.proto (AuthState, RichContent, EngineEvent, all request/response types)
2. Update bridge.go to route "__engine" core_id to engine methods
3. Add panic recovery wrapper around all bridge dispatches
4. Regenerate Dart protobuf classes
5. Update dart/lib/bridge/bridge.dart to handle EngineEvent stream
6. Write MockBridge for Dart-side testing
```

**Test gate:** Bridge round-trip tests pass. Dart MockBridge works for widget testing.

### Phase C: Flutter UI

Build the GUI. The engine handles everything, Dart is boring:

```
1. App shell          — MaterialApp, theme, Riverpod scope, bridge init
2. Splash screen      — Vault password prompt, loading state, error state
3. Zero-state         — Welcome screen with "Add Account" when no accounts
4. Auth flow          — Generic auth screen (renders any AuthState)
5. Platform rail      — Account icons, status dots, badges, reorder, context menu
6. Chat list          — Unified list, folders, search, context menu, empty state
7. Chat view          — Message list, bubbles, media, replies, reactions, scroll-to-bottom
8. Input area         — Text, send, reply bar, edit mode, markdown toolbar, emoji panel
9. Settings           — Theme, accent, proxy, cache, notifications, privacy, about
10. Search            — Global FTS5 search, result list with highlights
11. Media viewer      — Full-screen image/video, pinch zoom, share, save
12. Call UI            — Incoming banner, active call overlay, controls
13. Notifications     — System notifications, badge counts, reply-from-notification
14. Keyboard shortcuts — Desktop shortcuts (Ctrl+K, Escape, etc.)
15. RTL support       — Farsi layout pass, mixed-direction text
16. Accessibility     — Semantics, focus traversal, screen reader labels
```

**Test gate:** Widget tests pass for all screens. Golden tests match for dark/light/RTL. No jank in profile mode (60fps verified).

### Phase D: Integration Testing

Before first daily use:

```
1. Engine integration tests — every platform auth + send/receive through engine
2. Full-stack smoke test — Launch app → add Telegram account → send message → receive reply
3. Offline test — enable airplane mode → send message → restore → verify delivery
4. Crash recovery test — kill app mid-send → relaunch → verify pending retried
5. Multi-account test — 3+ accounts across different platforms → unified chat list correct
6. Performance test — 10k chats, 1k messages in one chat → scrolling smooth
7. Memory test — run for 1 hour with active connections → memory stable (no leaks)
```

### Phase E: Dogfooding

Start using the app daily. Fix every annoyance. This is where the last 10% of quality comes from. Track issues in `checklist/gui_bugs.md`.

---

## Design Decisions Summary

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Local database | `modernc.org/sqlite` (pure Go) | Queryable (vs BBolt), FTS5, WAL mode, no CGo. Same choice as TDLib (SQLite). |
| One DB vs many | One DB, `account_id` column | Unified chat list query is the critical path. One query vs merge-sorting 10. |
| Credentials | Vault (Argon2id + AES-256-GCM file) | Already exists, battle-tested, encrypted at rest. |
| Message cache | SQLite (content_raw + content_rich + content_text) | Dual format: raw for editing, normalized for rendering, plain for search. |
| State management (Dart) | Riverpod 3 StreamProvider | Proven for event-stream-driven state. StreamNotifier for read+write. |
| Auth UI | Generic state machine | 1 Flutter screen handles all 10 platforms. Zero platform-specific auth UI. |
| Content format | RichContent proto (blocks + spans) | Type-safe, extensible, renders identically in Flutter. Not Markdown (no spoiler/mention support), not HTML (XSS risk). |
| Offline reliability | Pending queue (SQLite-backed) | Messages survive crashes. Optimistic UI. Retry on reconnect. |
| Media cache | LRU eviction, priority download queue | Configurable max size. Thumbnails permanent, full media evicted. |
| Web target | Deferred. CacheBackend interface for future swap. | modernc.org/sqlite doesn't compile to WASM. Build native first, web V2. |
| Engine location | `go/engine/` (separate package) | Separation of concerns. Bridge = plumbing, engine = brain, cores = protocol. |
