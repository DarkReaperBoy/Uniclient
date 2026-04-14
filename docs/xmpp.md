# XMPP Core

Pure Go XMPP client implementing RFC 6120/6121 plus 30+ XEP extensions. Connects to any Jabber/XMPP server.

## Setup

```go
import "uniclient/cores"

xmpp := cores.NewXMPPCore("./sessions/xmpp.json")
```

## Authentication

```go
err := xmpp.Authenticate(cores.AuthConfig{
    Extra: map[string]string{
        "jid":      "user@example.com",
        "password": "secret",
    },
})
```

Supports SASL mechanisms: PLAIN, SCRAM-SHA-1, SCRAM-SHA-256. STARTTLS or direct TLS with resource binding.

## Key Features

- 379 exported methods
- RFC 6120 (Core) + RFC 6121 (IM) full implementation
- 30+ XEP extensions including:
  - XEP-0045: Multi-User Chat (MUC)
  - XEP-0084: User Avatar
  - XEP-0163: PEP (Personal Eventing Protocol)
  - XEP-0184: Message Delivery Receipts
  - XEP-0280: Message Carbons
  - XEP-0313: Message Archive Management (MAM)
  - XEP-0363: HTTP File Upload
  - XEP-0384: OMEMO (E2EE placeholder)
- Jingle call signaling
- PubSub/PEP for presence and activity
- Service discovery (XEP-0030)
- In-band registration (XEP-0077)

## Capabilities

`TEXT, CHANNELS, CALLS, REACTIONS, READ_RECEIPTS, TYPING, BLOCKING, SEARCH, PRESENCE, E2EE, FILE_TRANSFER`

## Example

```go
// Send a message
msg, err := xmpp.SendMessage("friend@example.com", "Hello XMPP!")

// Join a MUC room
err := xmpp.JoinChannel("room@conference.example.com")

// Set presence
err := xmpp.SetPresence("chat", "Available")

// Get roster (contact list)
roster, err := xmpp.GetRoster()

// Upload a file via HTTP Upload
ref, err := xmpp.UploadFile("room@conf.example.com", "/path/to/file.pdf")
```

## Dependencies

- Standard library only (net, crypto/tls, encoding/xml)
- No CGo required
