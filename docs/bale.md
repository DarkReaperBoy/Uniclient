# Bale Core

Client for [Bale Messenger](https://bale.ai), an Iranian messaging platform. Supports both Bot API (Telegram-compatible) and User API (gRPC-Web/WebSocket).

## Setup

```go
import "uniclient/cores"

bale := cores.NewBaleCore("./sessions/bale.json")
```

## Authentication

```go
// Bot mode
err := bale.Authenticate(cores.AuthConfig{
    BotToken: "123456:ABC-DEF",
})

// User mode (phone + OTP)
err := bale.Authenticate(cores.AuthConfig{
    Phone: "+98xxxxxxxxxx",
})
```

**Bot mode:** Token validated via `getMe` endpoint at `tapi.bale.ai`.

**User mode:** Phone/code flow via gRPC-Web protocol. Includes fallback IP (2.189.68.126) for when DNS is blocked outside Iran.

## Key Features

- 456 exported methods
- Dual-mode: Bot API (HTTP) + User API (gRPC-Web/WebSocket)
- Telegram Bot API-compatible endpoint
- LiveKit WebRTC voice integration
- HTTP long-polling for bot updates
- WebSocket for user real-time events
- CDN bypass with fallback IPs

## Capabilities

`TEXT, CHANNELS, REACTIONS, POLLS, STICKERS, ADMIN, FOLDERS, TYPING, SEARCH, LOCATION, FILE_TRANSFER`

## Example

```go
// Send a message
msg, err := bale.SendMessage("chat_id", "Hello from Bale!")

// Send a photo
msg, err := bale.SendPhoto("chat_id", "/path/to/photo.jpg", "Caption")

// Get chat info
info, err := bale.GetChatInfo("chat_id")

// User API: get contacts
contacts, err := bale.UserGetContacts()
```

## Dependencies

- Standard library only (net/http, crypto/tls)
- No CGo required
