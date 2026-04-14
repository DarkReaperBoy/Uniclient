# TeamSpeak Core

Pure Go TeamSpeak 3 client implementing the UDP binary protocol. Connects to any TS3 server.

## Setup

```go
import "uniclient/cores"

ts := cores.NewTeamSpeakCore("./sessions/teamspeak.json")
```

## Authentication

```go
err := ts.Authenticate(cores.AuthConfig{
    Extra: map[string]string{
        "server":   "ts3.example.com:9987",
        "nickname": "GoBot",
        "password": "server_password", // optional
    },
})
```

Uses certificate-based identity with Ed25519 license chain verification. Identity keys are auto-generated and persisted.

## Key Features

- 296 exported methods
- Pure UDP binary protocol implementation
- Voice codec negotiation (Opus, CELT)
- ECDSA cryptographic handshake
- Channel/user management with full ACL permissions
- 3D audio positioning
- ServerQuery admin interface
- File browser and transfer
- Identity persistence across sessions
- Packet retransmission with sequence tracking

## Capabilities

`TEXT, CHANNELS, VOICE, ADMIN, SESSIONS, TYPING`

## Example

```go
// Send a channel message
msg, err := ts.SendMessage("channel_id", "Hello TeamSpeak!")

// Move to a channel
err := ts.JoinChannel("channel_id")

// Get server info
info, err := ts.GetChatInfo("server")

// List channels
dialogs, err := ts.GetDialogs(100)

// Set nickname
err := ts.SetDisplayName("NewNickname")
```

## Dependencies

- Standard library only (net, crypto)
- No CGo required
