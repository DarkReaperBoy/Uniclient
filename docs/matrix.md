# Matrix Core

> **This core is a wrapper around [mautrix-go](https://github.com/mautrix/go) (v0.26.4+), not a from-scratch implementation.**
> mautrix-go already has comprehensive documentation — use it as the primary reference for any method not covered here:
> - Package docs: https://pkg.go.dev/maunium.net/go/mautrix
> - Source & guides: https://github.com/mautrix/go

MatrixCore exists to provide the **unified Core interface** so the GUI never needs to know which platform it is talking to. `SendMessage()`, `GetDialogs()`, `GetProfile()`, and the other 52 shared methods behave the same here as they do on Telegram, Bale, Rubika, and every other core. Beyond those 55 unified methods, MatrixCore exposes 185 platform-specific methods that are thin wrappers around mautrix-go — for those, the mautrix-go docs above are the authoritative reference.

**240 exported methods total** — 55 from the unified Core interface + 185 platform-specific methods covering CS API v1.13–v1.18, Spaces, Threads, MatrixRTC calls, E2EE (Olm/Megolm), and server admin.

## Setup

```go
import "uniclient/cores"

mx := cores.NewMatrixCore("./sessions/matrix.json")
```

The session file persists the access token so subsequent runs skip the login step entirely.

**Capabilities:** `TEXT`, `CHANNELS`, `CALLS`, `REACTIONS`, `READ_RECEIPTS`, `TYPING`, `POLLS`, `STICKERS`, `FOLDERS`, `ADMIN`, `BASE64_IMAGE`, `THREADS`, `PRESENCE`, `SPACES`, `E2EE`, `SEARCH`, `BLOCKING`, `FILE_TRANSFER`

## Authentication

### Password login

```go
err := mx.Authenticate(cores.AuthConfig{
    Extra: map[string]string{
        "homeserver": "https://matrix.org",
        "username":   "@user:matrix.org",
        "password":   "secret",
    },
})
```

### SSO login

Some homeservers (e.g. corporate deployments) disable password auth and require SSO. Pass `"sso": "true"` — the core returns a browser URL to open, then polls for the token:

```go
err := mx.Authenticate(cores.AuthConfig{
    Extra: map[string]string{
        "homeserver": "https://company.chat",
        "username":   "@user:company.chat",
        "sso":        "true",
    },
})
```

After first login the session file stores the access token. On the next run, call `Authenticate` with the same config and the token is reused automatically — no password prompt.

## Unified Interface — Key Examples

These are the same method signatures every other core uses. No Matrix-specific knowledge needed.

```go
// Send a text message
msg, err := mx.SendMessage("!roomid:matrix.org", "Hello from Matrix!")

// Fetch the inbox (rooms with recent activity)
dialogs, err := mx.GetDialogs(50)

// Get your own profile
profile, err := mx.GetProfile()

// Create a room (equivalent to a group/channel on other platforms)
roomID, err := mx.CreateGroup("Project Alpha")

// Reply to a message
reply, err := mx.ReplyToMessage("!roomid:matrix.org", "$eventid", "Sounds good!")

// Send a file
ref, err := mx.UploadFile("!roomid:matrix.org", "/path/to/report.pdf")

// Edit a message
err = mx.EditMessage("!roomid:matrix.org", "$eventid", "Corrected text")

// Delete a message (redacts the event)
err = mx.DeleteMessage("!roomid:matrix.org", "$eventid")

// React to a message
err = mx.ReactToMessage("!roomid:matrix.org", "$eventid", "👍")

// Get room members
members, err := mx.GetMembers("!roomid:matrix.org")

// Search messages
results, err := mx.SearchMessages("!roomid:matrix.org", "quarterly report")

// Block a user
err = mx.BlockUser("@spammer:matrix.org")
```

## E2EE

Requires the `-tags goolm` build tag for the pure Go Olm/Megolm implementation (no CGo):

```bash
go build -tags goolm ./cores/...
go test -tags goolm ./tests/... -run TestMatrix
```

E2EE is automatic for rooms that have encryption enabled — no extra calls needed. Key backup, cross-signing, SSSS, and SAS emoji verification are all handled internally by mautrix-go. The Core interface exposes `SetEncryption` to toggle encryption on a room you own:

```go
err := mx.SetEncryption("!roomid:matrix.org", true)
```

## Platform-Specific Methods

The 185 platform-specific methods (Spaces, Threads, MatrixRTC, room aliases, push rules, account data, admin APIs, etc.) are thin wrappers that call the equivalent mautrix-go function and return its result. Their signatures follow the same naming convention as the rest of the core but they are not part of the unified interface.

For full details on what each one does, refer to the mautrix-go package docs:
https://pkg.go.dev/maunium.net/go/mautrix

A few examples to show the pattern:

```go
// Create a Space (Matrix-specific — not in unified interface)
spaceID, err := mx.CreateSpace("Engineering", "eng-space", true)

// Add a room to a Space
err = mx.AddRoomToSpace("!spaceid:matrix.org", "!roomid:matrix.org")

// Send a threaded reply
reply, err := mx.SendThreadReply("!roomid:matrix.org", "$threadRootID", "In reply to the thread...")

// Set a room alias
err = mx.SetRoomAlias("!roomid:matrix.org", "#myalias:matrix.org")

// Fetch a user's account data key
data, err := mx.GetAccountData("m.push_rules")

// Kick a user with a reason
err = mx.KickUser("!roomid:matrix.org", "@user:matrix.org", "Violated room rules")
```

## Dependencies

- `maunium.net/go/mautrix` v0.26.4+ — Matrix SDK (the heavy lifting is all here)
- Build with `-tags goolm` for E2EE (pure Go, no CGo)
