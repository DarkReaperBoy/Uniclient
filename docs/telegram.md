# Telegram Core

> **This core is a wrapper around [gotd/td](https://github.com/gotd/td) (v0.143.0+), not a from-scratch MTProto implementation.** gotd/td already has comprehensive documentation — see [pkg.go.dev/github.com/gotd/td](https://pkg.go.dev/github.com/gotd/td) and the [GitHub repo](https://github.com/gotd/td). This doc explains the wrapper layer only.

## Why a Wrapper?

The unified `Core` interface lets the GUI call `SendMessage()`, `GetDialogs()`, `DownloadFile()`, etc. on every platform without knowing which backend it's talking to. `TelegramCore` satisfies that interface using gotd/td under the hood, so Telegram behaves identically to Bale, Rubika, Matrix, and every other core from the GUI's perspective.

**771 exported methods total:**
- 55 from the unified `Core` interface (shared signature with every other core)
- 716 platform-specific methods that are thin wrappers over gotd/td's full MTProto API surface

For the 716 platform-specific methods, the gotd/td documentation is the authoritative reference — they map 1:1 to gotd/td calls.

## Setup

```go
import "uniclient/cores"

// Bot mode
tg := cores.NewTelegramCore(cores.TelegramConfig{
    BotToken: "123456:ABC-DEF",
})

// User mode (interactive phone/OTP flow)
tg := cores.NewTelegramCore(cores.TelegramConfig{
    AppID:   12345,
    AppHash: "abcdef1234567890",
    Phone:   "+1234567890",
})
```

## Authentication

```go
// Bot mode — validates token via auth.importBotAuthorization
err := tg.Authenticate(cores.AuthConfig{
    BotToken: "123456:ABC-DEF",
})

// User mode — sends code to phone, reads OTP, handles 2FA if set
err := tg.Authenticate(cores.AuthConfig{
    Phone:   "+1234567890",
    OTPCode: "12345", // or leave empty to poll auth/otp_code.txt
})
```

**Bot mode:** Token validated via `auth.importBotAuthorization`. No phone or App ID needed — use a token from [@BotFather](https://t.me/BotFather).

**User mode:** Full interactive flow. Sends the login code to the phone number, reads the OTP from `AuthConfig.OTPCode` (or polls `auth/otp_code.txt` if empty), and handles a 2FA password prompt if the account has one set. Requires an App ID + App Hash from [my.telegram.org](https://my.telegram.org).

## Core Interface Methods

These 55 methods are identical in signature and behavior to every other core. The GUI uses only these.

```go
// Messaging
msg, err := tg.SendMessage("@channel_name", "Hello!")
msg, err := tg.SendMessage("-1001234567890", "Hello group!")

// Dialogs / chats
dialogs, err := tg.GetDialogs(20)

// File transfer
ref, err := tg.DownloadFile("document_id", "/tmp/file.pdf")
err = tg.UploadFile("/tmp/photo.jpg", "-1001234567890")

// Search
msgs, err := tg.SearchMessagesGlobal("query", 50)

// Blocking
err = tg.BlockUser("user_id")
```

**Capabilities:** `TEXT`, `CHANNELS`, `TOPICS`, `CALLS`, `GROUP_CALLS`, `REACTIONS`, `READ_RECEIPTS`, `TYPING`, `POLLS`, `STICKERS`, `FOLDERS`, `ADMIN`, `SESSIONS`, `BASE64_IMAGE`, `SCHEDULED`, `SEARCH`, `BLOCKING`, `FILE_TRANSFER`

## Platform-Specific Methods

The remaining 716 methods expose the full gotd/td API surface. They are grouped by TL namespace:

- `Account*` — account settings, privacy, sessions
- `Auth*` — authorization flows, QR login, password reset
- `Channels*` — channel and supergroup management
- `Contacts*` — contact list, import, resolve, block list
- `Messages*` — full message API (reactions, polls, scheduled, pinning, etc.)
- `Photos*` — profile photo management
- `Stickers*` — sticker set operations
- `Phone*` — call management (voice and video, group calls via SFU)
- `Users*` — user info, full user fetch
- `Help*` — server config, terms of service, app updates
- `Langpack*` — localization strings
- `Folders*` — chat folder management
- `Stats*` — channel and group statistics

**For these methods, refer to [pkg.go.dev/github.com/gotd/td](https://pkg.go.dev/github.com/gotd/td) for parameter types and behavior.** Each method here is a direct pass-through with minimal adaptation (error unwrapping, access hash injection from cache).

## Notable Behaviors

**Access hash caching.** Telegram's MTProto API requires an `access_hash` for every peer (user, channel, bot). `TelegramCore` caches these automatically from dialog fetches, contact resolution, and incoming updates — you never need to supply them manually.

**FLOOD_WAIT handling.** Rate limit errors (`FLOOD_WAIT_X`) are surfaced as typed errors so the GUI can back off gracefully. The session layer does not auto-retry — that's left to the caller.

**Session persistence.** Sessions are stored in `auth/telegram_session.json` (gitignored). Reuse the same session file across runs to avoid repeated OTP flows.

**No CGo.** gotd/td is pure Go. This core compiles with `go build` alone — no C compiler, no system libraries.

## Dependencies

- [`github.com/gotd/td`](https://github.com/gotd/td) — MTProto implementation (the real engine)
- No CGo required
