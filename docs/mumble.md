# Mumble Core

Pure Go Mumble client implementing the binary TCP/UDP protocol. Includes Ice RPC admin interface for Murmur server management.

## Setup

```go
import "uniclient/cores"

mum := &cores.MumbleCore{}
```

## Authentication

```go
err := mum.Authenticate(cores.AuthConfig{
    Extra: map[string]string{
        "server":   "mumble.example.com:64738",
        "username": "GoBot",
        "password": "server_password", // optional
    },
})
```

Uses TLS certificate-based identity. Certificates are auto-generated and persisted. Server passwords are sent during handshake.

## Key Features

- 233 exported methods
- TCP control channel (protobuf messages)
- UDP voice channel with AES-OCB2 encryption
- CELT/Opus codec support
- Channel ACL/permissions management
- Full Ice RPC admin interface (pure Go ZeroC Ice wire protocol)
- User management, bans, registration
- Authenticator callbacks for external auth systems
- 3D audio positioning
- Server certificate management

## Capabilities

`TEXT, CHANNELS, VOICE, ADMIN, BLOCKING, SEARCH`

## Example

```go
// Send a text message
msg, err := mum.SendMessage("channel_id", "Hello Mumble!")

// Join a channel
err := mum.JoinChannel("channel_id")

// Create a channel
id, err := mum.CreateChannel("New Channel")

// List users in current channel
users, err := mum.GetMembers("channel_id")

// Ice RPC: get all registered users (admin)
users, err := mum.IceGetRegisteredUsers("")
```

## Ice RPC Admin

The core includes a pure Go implementation of the ZeroC Ice wire protocol for Murmur server administration:

```go
// Connect to Murmur's Ice interface
err := mum.IceConnect("localhost:6502")

// Get server uptime
uptime, err := mum.IceGetUptime()

// Ban a user
err := mum.IceKickUser(sessionID, "reason")

// Set server config
err := mum.IceSetConf("welcometext", "Welcome!")
```

## Dependencies

- Standard library only (net, crypto/tls)
- No CGo required
