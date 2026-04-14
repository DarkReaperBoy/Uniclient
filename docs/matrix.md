# Matrix Core

Client for the [Matrix](https://matrix.org) protocol via [mautrix-go](https://github.com/mautrix/go). Supports the full Client-Server API with E2EE.

## Setup

```go
import "uniclient/cores"

mx := cores.NewMatrixCore("./sessions/matrix.json")
```

## Authentication

```go
err := mx.Authenticate(cores.AuthConfig{
    Extra: map[string]string{
        "homeserver": "https://matrix.org",
        "username":   "@user:matrix.org",
        "password":   "secret",
    },
})
```

Supports password login and persisted access token reuse. SSO login flow available for servers that require it.

## Key Features

- 240 exported methods
- Full Client-Server API (v1.13–v1.18)
- E2EE via Olm/Megolm (pure Go with `-tags goolm`)
- Room state management and caching
- Spaces and threads support
- Key verification (SAS emoji)
- Media upload/download
- Push notification rules
- Room directory and search
- Admin/moderation tools
- Cross-signing and SSSS

## Capabilities

`TEXT, CHANNELS, CALLS, REACTIONS, READ_RECEIPTS, TYPING, POLLS, STICKERS, FOLDERS, ADMIN, BASE64_IMAGE, THREADS, PRESENCE, SPACES, E2EE, SEARCH, BLOCKING, FILE_TRANSFER`

## Example

```go
// Send a message
msg, err := mx.SendMessage("!roomid:matrix.org", "Hello Matrix!")

// Create a room
id, err := mx.CreateGroup("My Room")

// Get room members
members, err := mx.GetMembers("!roomid:matrix.org")

// Upload media
ref, err := mx.UploadFile("!roomid:matrix.org", "/path/to/image.png")

// Enable E2EE for a room
err := mx.SetEncryption("!roomid:matrix.org", true)
```

## E2EE

Requires the `-tags goolm` build tag for pure Go Olm/Megolm implementation:

```bash
go build -tags goolm ./cores/...
```

E2EE is automatic for rooms with encryption enabled. Key backup, cross-signing, and verification are supported.

## Dependencies

- `maunium.net/go/mautrix` — Matrix SDK
- Build with `-tags goolm` for E2EE (no CGo needed)
