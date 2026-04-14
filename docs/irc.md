# IRC Core

Pure Go IRC client implementing RFC 2812 + IRCv3 extensions. Connects to any IRC network.

## Setup

```go
import "uniclient/cores"

irc := cores.NewIRCCore("./sessions/irc.json")
```

## Authentication

```go
err := irc.Authenticate(cores.AuthConfig{
    Extra: map[string]string{
        "server": "irc.libera.chat:6697",
        "nick":   "mybot",
        "pass":   "nickserv_password", // optional
    },
})
```

Supports NickServ identification and SASL PLAIN authentication. Auto-reconnect with configurable retry limits.

## Key Features

- 418 exported methods
- RFC 2812 full compliance
- IRCv3: CAP negotiation, SASL, labeled-responses, message-tags, CHATHISTORY, TAGMSG
- CTCP (ACTION, VERSION, PING, TIME, SOURCE)
- DCC file transfer
- Services: NickServ, ChanServ, MemoServ, OperServ
- Operator commands (KILL, KLINE, GLINE, etc.)
- Extended ban types, channel modes, user modes
- Auto-reconnect with exponential backoff

## Capabilities

`TEXT, CHANNELS, ADMIN, SEARCH, BLOCKING, TYPING`

## Example

```go
// Join a channel
err := irc.JoinChannel("#go-nuts")

// Send a message
msg, err := irc.SendMessage("#go-nuts", "Hello IRC!")

// Send a CTCP action (/me)
err := irc.CtcpAction("#go-nuts", "waves hello")

// Set channel topic
err := irc.SetChatTitle("#go-nuts", "New topic here")

// Send raw IRC command
err := irc.SendRawCommand("PRIVMSG #go-nuts :raw message")
```

## Dependencies

- Standard library only (net, crypto/tls)
- No CGo required
