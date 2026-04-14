# Delta Chat Core

Chat-over-email client using IMAP/SMTP. Works with any email provider. End-to-end encrypted via Autocrypt (OpenPGP).

## Setup

```go
import "uniclient/cores"

dc := cores.NewDeltaChatCore("./sessions/deltachat.json")
```

## Authentication

```go
err := dc.Authenticate(cores.AuthConfig{
    Extra: map[string]string{
        "email":    "user@example.com",
        "password": "email_password",
    },
})
```

Auto-discovers IMAP/SMTP servers from the email domain. Supports custom server configuration via Extra fields (`imap_host`, `smtp_host`, `imap_port`, `smtp_port`).

## Key Features

- 245 exported methods
- Chat-over-email: messages are emails, chats are email threads
- Autocrypt E2EE (Ed25519/Curve25519 via OpenPGP)
- Dual IMAP IDLE connections for real-time delivery
- Webxdc support (mini-apps in chats)
- Device messages (local-only notifications)
- Location streaming
- PGP key import/export
- Multi-account support
- Chatmail server compatibility

## Capabilities

`TEXT, CHANNELS, CALLS, REACTIONS, READ_RECEIPTS, BASE64_IMAGE, E2EE, TYPING, SEARCH, BLOCKING, LOCATION, FILE_TRANSFER`

## Example

```go
// Send a message (sends an email)
msg, err := dc.SendMessage("friend@example.com", "Hello via email!")

// Get conversations
dialogs, err := dc.GetDialogs(20)

// Send a file attachment
ref, err := dc.UploadFile("friend@example.com", "/path/to/file.pdf")

// Create a group chat
err := dc.CreateGroup("Book Club")

// Get E2EE status
info, err := dc.GetVerificationInfo("friend@example.com")
```

## How It Works

Delta Chat treats email as a chat transport:
- **DM**: Direct email to a contact
- **Group**: Email thread with multiple recipients (using Chat-Group-ID headers)
- **Channels**: Mailing lists
- **E2EE**: Autocrypt headers in emails carry public keys; messages encrypted with OpenPGP

No Delta Chat server needed — works with Gmail, Outlook, Fastmail, or any IMAP/SMTP provider.

## Dependencies

- Standard library only (net, crypto)
- No CGo required
