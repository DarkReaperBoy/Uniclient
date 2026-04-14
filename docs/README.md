# Uniclient Core Libraries

Each messaging platform is implemented as a standalone Go package in `go/cores/`. You can import and use any core independently — no Flutter, no bridge, no dependencies on other cores.

## Quick Start

```go
import "uniclient/cores"

// Create a Telegram bot
tg := cores.NewTelegramCore(cores.TelegramConfig{
    BotToken: "123456:ABC-DEF",
})
if err := tg.Authenticate(cores.AuthConfig{BotToken: "123456:ABC-DEF"}); err != nil {
    log.Fatal(err)
}
msg, err := tg.SendMessage("@channel", "Hello from Go!")
```

## Available Cores

| Core | Platform | Methods | Auth | Docs |
|------|----------|---------|------|------|
| [Telegram](telegram.md) | Telegram (MTProto) | 771 | Bot token / Phone+OTP | Full MTProto via gotd/td |
| [GitHub](github.md) | GitHub | 282 | Personal Access Token | REST API, chat-via-issues |
| [Bale](bale.md) | Bale Messenger | 456 | Bot token / Phone+OTP | Bot API + User gRPC |
| [IRC](irc.md) | IRC Networks | 418 | NickServ / SASL | RFC 2812 + IRCv3 |
| [XMPP](xmpp.md) | XMPP/Jabber | 379 | JID + Password (SASL) | RFC 6120 + 30 XEPs |
| [TeamSpeak](teamspeak.md) | TeamSpeak 3 | 296 | Certificate Identity | UDP binary protocol |
| [DeltaChat](deltachat.md) | Delta Chat (Email) | 245 | Email + Password | IMAP/SMTP + Autocrypt |
| [Rubika](rubika.md) | Rubika | 242 | Bot token / Phone+OTP | WebSocket + RSA/AES |
| [Matrix](matrix.md) | Matrix | 240 | Access token / SSO | CS API via mautrix-go |
| [Mumble](mumble.md) | Mumble | 233 | TLS Certificate | Binary proto + UDP voice |

**Total: 4,048 exported methods across 10 cores.**

## Common Interface

All cores implement the `Core` interface from `go/cores/base.go` (55 methods). This means every core supports:

```go
type Core interface {
    Name() string
    Capabilities() []string
    Authenticate(cfg AuthConfig) error
    SendMessage(chatID, text string) (*OutgoingMessage, error)
    GetDialogs(limit int) ([]Dialog, error)
    GetMessages(chatID string, limit int) ([]Message, error)
    // ... 49 more methods
}
```

Platform-specific methods exist beyond the Core interface as additional exported methods on each core struct.

## Shared Types

All cores use the same shared types defined in `go/cores/base.go`:

- `Message` — chat message (ID, ChatID, SenderID, Text, Timestamp, Attachments, etc.)
- `Dialog` — conversation/chat (ID, Title, Type, LastMessage, UnreadCount, etc.)
- `User` — user profile (ID, Username, DisplayName, Avatar, IsOnline, etc.)
- `FileRef` — file reference (ID, Name, Size, MimeType, URL, etc.)
- `OutgoingMessage` — sent message confirmation (ID, Timestamp)
- `Update` — real-time event (Type, Message, User, ChatID, etc.)

## Build Requirements

- Go 1.26+ 
- No CGo, no C compiler needed
- `CGO_ENABLED=0 go build ./cores/...` works everywhere
- For Matrix E2EE: add `-tags goolm` build tag

## Session Persistence

All cores persist auth sessions to JSON files. Pass a session path to the constructor:

```go
core := cores.NewBaleCore("./sessions/bale.json")
```

After `Authenticate()`, the session is saved automatically. On restart, call `Authenticate()` again — it will load the saved session and skip the auth flow if the session is still valid.
