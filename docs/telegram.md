# Telegram Core

Pure Go MTProto client via [gotd/td](https://github.com/gotd/td). Supports both bot and user mode with full API coverage.

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
err := tg.Authenticate(cores.AuthConfig{
    BotToken: "123456:ABC-DEF", // bot mode
    // OR
    Phone: "+1234567890",        // user mode — will prompt for OTP
})
```

**Bot mode:** Validates token via `auth.importBotAuthorization`.

**User mode:** Interactive flow — sends code to phone, reads OTP from `AuthConfig.OTPCode` or `auth/otp_code.txt` polling, handles 2FA password if set.

## Key Features

- 771 exported methods (full gotd/td API surface)
- WebRTC voice/video calls with codec injection
- Group calls via SFU (Selective Forwarding Unit)
- Peer access hash caching (essential for user mode)
- Session persistence with FLOOD_WAIT handling
- Scheduled messages, polls, stickers, reactions
- Full admin/moderation API
- File upload/download with progress

## Capabilities

`TEXT, CHANNELS, TOPICS, CALLS, GROUP_CALLS, REACTIONS, READ_RECEIPTS, TYPING, POLLS, STICKERS, FOLDERS, ADMIN, SESSIONS, BASE64_IMAGE, SCHEDULED, SEARCH, BLOCKING, FILE_TRANSFER`

## Example

```go
// Send a message
msg, err := tg.SendMessage("@channel_name", "Hello!")

// Get recent chats
dialogs, err := tg.GetDialogs(20)

// Download a file
ref, err := tg.DownloadFile("document_id", "/tmp/file.pdf")

// Search messages globally
msgs, err := tg.SearchMessagesGlobal("query", 50)
```

## Platform-Specific Methods

Beyond the 55 Core interface methods, TelegramCore exposes 716 additional methods wrapping the full Telegram API:

- `Account*` — account settings, privacy, sessions
- `Channels*` / `Messages*` — channel/message management
- `Contacts*` — contact list operations
- `Photos*` — profile photo management
- `Stickers*` — sticker set operations
- `Phone*` — call management
- Direct gotd/td method wrappers for the full MTProto surface

## Dependencies

- `github.com/gotd/td` — MTProto implementation
- No CGo required
