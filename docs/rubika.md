# Rubika Core

Client for [Rubika](https://rubika.ir), an Iranian messaging platform. Implements the proprietary WebSocket protocol with RSA/AES encryption.

## Setup

```go
import "uniclient/cores"

rub := cores.NewRubikaCore("./sessions/rubika.json")
```

## Authentication

```go
// Bot mode
err := rub.Authenticate(cores.AuthConfig{
    BotToken: "bot_token_here",
})

// User mode (phone + OTP)
err := rub.Authenticate(cores.AuthConfig{
    Phone: "+98xxxxxxxxxx",
})
```

Auth uses RSA encryption for key exchange, AES for message encryption, and a custom substitution cipher. DC (data center) endpoints are auto-discovered.

## Key Features

- 242 exported methods
- RSA + AES + SHA256 crypto pipeline
- WebSocket-based real-time messaging
- Multiple DC endpoint fallback (works when domains are blocked)
- Voice chat via Janus WebRTC server
- RTP audio handling
- Bot API support
- Channel/group management with admin controls
- Sticker management
- File upload with thumbnail generation

## Capabilities

`TEXT, CHANNELS, REACTIONS, POLLS, STICKERS, FOLDERS, ADMIN, SESSIONS, TYPING, LOCATION, FILE_TRANSFER`

## Example

```go
// Send a message
msg, err := rub.SendMessage("chat_guid", "Hello Rubika!")

// Get group info
info, err := rub.GetGroupInfo("group_guid")

// Get channel members
members, err := rub.GetChannelAllMembers("channel_guid")

// Upload a file
ref, err := rub.UploadFile("chat_guid", "/path/to/photo.jpg")

// Join a voice chat
err := rub.JoinGroupCall("group_guid")
```

## Network Resilience

Rubika core includes fallback DC endpoints for operation outside Iran where primary domains may be blocked. The core automatically cycles through available endpoints on connection failure.

## Dependencies

- Standard library only (net, crypto)
- No CGo required
