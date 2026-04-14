# IRC Core — API Reference

Pure Go IRC client implementing RFC 1459/2812 plus IRCv3 extensions. Connects to any IRC network with TLS, SASL, CTCP, DCC, and full services/oper command coverage. No CGo, no external dependencies.

**418 exported methods** across core protocol, channel management, user operations, channel/user modes, extended bans, services (NickServ, ChanServ, MemoServ, HostServ, BotServ, OperServ, GroupServ, StatServ), oper commands, CTCP, DCC/XDCC, IRCv3 capabilities, MONITOR/WATCH, raw commands, reconnection, event handlers, and proxy/transport support.

## Table of Contents

- [Setup](#setup)
- [Types](#types)
- [Connection & Authentication](#connection--authentication)
- [Core Interface Methods](#core-interface-methods)
- [Channel Operations](#channel-operations)
- [Messaging & CTCP](#messaging--ctcp)
- [User Operations](#user-operations)
- [Channel Mode Flags](#channel-mode-flags)
- [User Mode Flags](#user-mode-flags)
- [Extended Bans](#extended-bans)
- [Ban Lists & Exceptions](#ban-lists--exceptions)
- [NickServ Commands](#nickserv-commands)
- [ChanServ Commands](#chanserv-commands)
- [MemoServ Commands](#memoserv-commands)
- [HostServ Commands](#hostserv-commands)
- [BotServ Commands](#botserv-commands)
- [OperServ Commands](#operserv-commands)
- [GroupServ Commands](#groupserv-commands)
- [StatServ Commands](#statserv-commands)
- [Oper Commands — RFC](#oper-commands--rfc)
- [Oper Commands — UnrealIRCd](#oper-commands--unrealircd)
- [Oper Commands — InspIRCd](#oper-commands--inspircd)
- [Oper Commands — Server Extensions](#oper-commands--server-extensions)
- [DCC & XDCC](#dcc--xdcc)
- [CTCP Extended](#ctcp-extended)
- [IRCv3 Capabilities & Extensions](#ircv3-capabilities--extensions)
- [CHATHISTORY](#chathistory)
- [Metadata](#metadata)
- [Batch & Multiline](#batch--multiline)
- [SASL Mechanisms](#sasl-mechanisms)
- [Server Commands](#server-commands)
- [MONITOR](#monitor)
- [WATCH](#watch)
- [Raw Commands](#raw-commands)
- [Reconnection](#reconnection)
- [Proxy & Transport](#proxy--transport)
- [Event Handlers](#event-handlers)
- [Formatting Helpers](#formatting-helpers)
- [Unsupported Core Methods](#unsupported-core-methods)

## Setup

```go
import "uniclient/cores"

irc := cores.NewIRCCore("./sessions/irc.json")
```

**Capabilities:** `TEXT`, `CHANNELS`, `ADMIN`, `SEARCH`, `BLOCKING`, `TYPING`

## Types

### IRCServerInfo

```go
type IRCServerInfo struct {
    Network     string            // NETWORK=
    ServerName  string            // from 004
    ServerVer   string            // from 004
    UserModes   string            // from 004
    ChanModes   string            // from 004
    CaseMapping string            // CASEMAPPING=
    ChanTypes   string            // CHANTYPES=
    Prefix      string            // PREFIX=
    MaxNickLen  int               // NICKLEN=
    MaxChanLen  int               // CHANNELLEN=
    MaxTopicLen int               // TOPICLEN=
    MaxTargets  int               // TARGMAX=
    MaxModes    int               // MODES=
    MaxChannels int               // CHANLIMIT=
    Raw         map[string]string // all raw ISUPPORT key=value pairs
}
```

Parsed from RPL_ISUPPORT (005) and RPL_MYINFO (004). Populated automatically after authentication.

### IRCListEntry

```go
type IRCListEntry struct {
    Channel string
    Users   int
    Topic   string
}
```

One entry from a LIST response.

### IRCWhoEntry

```go
type IRCWhoEntry struct {
    Channel  string
    User     string
    Host     string
    Server   string
    Nick     string
    Flags    string // H/G (here/gone), *, @, +
    Hopcount int
    Realname string
}
```

One entry from a WHO response.

### IRCWhowasEntry

```go
type IRCWhowasEntry struct {
    Nick     string
    User     string
    Host     string
    Realname string
}
```

One entry from a WHOWAS response.

### IRCBanEntry

```go
type IRCBanEntry struct {
    Mask  string
    SetBy string
    SetAt time.Time
}
```

One entry from a ban list, ban exception list, or invite exception list.

### IRCUserhostEntry

```go
type IRCUserhostEntry struct {
    Nick     string
    IsOper   bool
    IsAway   bool
    Hostname string
}
```

One USERHOST reply entry.

### IRCDCCOffer

```go
type IRCDCCOffer struct {
    Type     string // "SEND", "CHAT"
    Filename string
    IP       string
    Port     int
    Size     int64
    From     string
}
```

Represents an incoming DCC request. Retrieved via `GetDCCOffers()`.

### IRCCore

```go
type IRCCore struct {
    // unexported fields: connection, identity, state, channels, etc.
}
```

The main IRC client struct. Create with `NewIRCCore(sessionPath)`.

---

## Connection & Authentication

### Name

```go
func (c *IRCCore) Name() string
```

Returns `"irc"`.

### Capabilities

```go
func (c *IRCCore) Capabilities() []string
```

Returns `["TEXT", "CHANNELS", "ADMIN", "SEARCH", "BLOCKING", "TYPING"]`.

### Authenticate

```go
func (c *IRCCore) Authenticate(cfg AuthConfig) error
```

Connects to an IRC server over TLS (or plain text), performs NICK/USER registration, and optionally authenticates via SASL or NickServ.

**AuthConfig fields:**
- `Extra["server"]` -- server address as `host:port` (required)
- `Extra["nick"]` -- display nickname (required)
- `Extra["username"]` -- ident/username (optional, defaults to nick)
- `Extra["realname"]` -- real name field (optional)
- `Extra["pass"]` -- NickServ/SASL password (optional)
- `Extra["server_pass"]` -- connection password for PASS command (optional)
- `Extra["tls"]` -- `"true"` to force TLS, `"false"` to disable (default: auto based on port)
- `Extra["sasl"]` -- `"true"` to use SASL PLAIN instead of NickServ (optional)
- `Extra["channels"]` -- comma-separated channels to auto-join (optional)

```go
err := irc.Authenticate(cores.AuthConfig{
    Extra: map[string]string{
        "server":   "irc.libera.chat:6697",
        "nick":     "mybot",
        "pass":     "nickserv_password",
        "sasl":     "true",
        "channels": "#go-nuts,#test",
    },
})
```

### Logout

```go
func (c *IRCCore) Logout() error
```

Sends QUIT and disconnects. Disables auto-reconnect. Session file is preserved for future connections.

### Close

```go
func (c *IRCCore) Close() error
```

Full shutdown: sends QUIT, closes the TCP connection, waits for goroutines to finish, saves session, sets authed=false.

### OnUpdate

```go
func (c *IRCCore) OnUpdate(handler func(Update))
```

Registers a callback for unified updates (messages, joins, parts, quits, kicks, mode changes, topic changes, connectivity).

```go
irc.OnUpdate(func(u cores.Update) {
    if u.Message != nil {
        fmt.Printf("[%s] %s: %s\n", u.ChatID, u.Message.SenderName, u.Message.Text)
    }
})
```

---

## Core Interface Methods

These implement the unified `Core` interface shared across all uniclient platforms.

### Messaging

#### SendMessage

```go
func (c *IRCCore) SendMessage(chatID string, msg OutgoingMessage) (*Message, error)
```

Sends a PRIVMSG to a channel or user. `chatID` is a channel name (e.g. `#go-nuts`) or a nick for private messages.

```go
msg, err := irc.SendMessage("#go-nuts", cores.OutgoingMessage{Text: "Hello IRC!"})
msg, err := irc.SendMessage("alice", cores.OutgoingMessage{Text: "Private message"})
```

#### GetMessages

```go
func (c *IRCCore) GetMessages(chatID string, opts PaginationOpts) ([]Message, error)
```

Returns cached messages for a channel or user. Only messages received during this session are available (IRC has no server-side history in base protocol; see CHATHISTORY for IRCv3 servers).

#### EditMessage

```go
func (c *IRCCore) EditMessage(_ string, _ string, _ string) (*Message, error)
```

Not supported by IRC protocol. Returns `ErrNotSupported`.

#### DeleteMessage

```go
func (c *IRCCore) DeleteMessage(_ string, _ string) error
```

Not supported by IRC protocol. Returns `ErrNotSupported`.

#### ReplyToMessage

```go
func (c *IRCCore) ReplyToMessage(chatID string, replyToMsgID string, msg OutgoingMessage) (*Message, error)
```

Sends a PRIVMSG with the reply context prepended. IRC has no native reply threading, so this quotes the original message text as a prefix.

#### ForwardMessage

```go
func (c *IRCCore) ForwardMessage(fromChatID string, msgID string, toChatID string) (*Message, error)
```

Looks up the message by ID in the local cache and sends it as a PRIVMSG to the target channel/user with attribution.

#### ReactToMessage

```go
func (c *IRCCore) ReactToMessage(_ string, _ string, _ string) error
```

Not supported by base IRC. Returns `ErrNotSupported`. See `SendReactTag` for IRCv3 draft/react support.

#### PinMessage / UnpinMessage

```go
func (c *IRCCore) PinMessage(chatID string, msgID string) error
func (c *IRCCore) UnpinMessage(chatID string, msgID string) error
```

Simulated via channel topic. PinMessage sets the channel topic to the message text. UnpinMessage clears the topic.

#### MarkAsRead

```go
func (c *IRCCore) MarkAsRead(chatID string, upToMsgID string) error
```

Marks messages as read in the local cache. See also `MarkRead` for IRCv3 MARKREAD support.

#### GetReadState

```go
func (c *IRCCore) GetReadState(chatID string) (*ReadState, error)
```

Returns the local read state for a channel or user.

#### SendTyping

```go
func (c *IRCCore) SendTyping(chatID string) error
```

Sends a typing indicator via IRCv3 TAGMSG with `+typing=active` tag. Requires server support for `message-tags` and `draft/typing` capabilities.

### File Transfer

#### UploadFile / DownloadFile

```go
func (c *IRCCore) UploadFile(_ string, _ FileUpload, _ func(int64, int64)) (*Message, error)
func (c *IRCCore) DownloadFile(_ FileRef, _ string, _ func(int64, int64)) error
```

Not supported via the core interface. Returns `ErrNotSupported`. Use DCC methods for file transfer.

#### SendImageBase64

```go
func (c *IRCCore) SendImageBase64(_ string, _ string, _ string) (*Message, error)
```

Not supported. Returns `ErrNotSupported`.

### Calls

#### StartCall / JoinGroupCall / EndCall / SetCallMuted

```go
func (c *IRCCore) StartCall(_ string, _ bool) (*CallSession, error)
func (c *IRCCore) JoinGroupCall(_ string) (*CallSession, error)
func (c *IRCCore) EndCall(_ string) error
func (c *IRCCore) SetCallMuted(_ string, _ bool) error
```

Not supported. IRC has no voice call protocol. Returns `ErrNotSupported`.

#### AcceptCall / DeclineCall

```go
func (c *IRCCore) AcceptCall(callID string) (*CallSession, error)
func (c *IRCCore) DeclineCall(callID string) error
```

Not supported. Returns `ErrNotSupported`.

### Dialogs & Chat Info

#### GetDialogs

```go
func (c *IRCCore) GetDialogs(opts PaginationOpts) ([]Dialog, error)
```

Returns joined channels and active private message conversations as dialogs.

#### GetChatInfo

```go
func (c *IRCCore) GetChatInfo(chatID string) (*Dialog, error)
```

Returns info about a channel (name, topic, user count) or a user (nick, host, away status).

#### CreateGroup

```go
func (c *IRCCore) CreateGroup(name string, members []string) (*Dialog, error)
```

Creates a channel (JOIN) and invites the listed members.

#### CreateChannel

```go
func (c *IRCCore) CreateChannel(name string, description string) (*Dialog, error)
```

Joins or creates a channel and sets the topic to `description`.

#### CreateTopic

```go
func (c *IRCCore) CreateTopic(_ string, _ string) (*Dialog, error)
```

Not supported (IRC channels are not forum-style). Returns `ErrNotSupported`.

#### GetFolders / CreateFolder

```go
func (c *IRCCore) GetFolders() ([]Folder, error)
func (c *IRCCore) CreateFolder(_ string, _ []string) (*Folder, error)
```

Not supported. Returns `ErrNotSupported`.

#### EditChatTitle

```go
func (c *IRCCore) EditChatTitle(_ string, _ string) error
```

Not supported (IRC channels cannot be renamed via standard commands). Returns `ErrNotSupported`. See `RenameChannel` for IRCv3 draft support.

#### EditChatDescription

```go
func (c *IRCCore) EditChatDescription(chatID string, description string) error
```

Sets the channel topic via the TOPIC command.

#### LeaveChat

```go
func (c *IRCCore) LeaveChat(chatID string) error
```

Sends PART to leave a channel.

#### GetInviteLink

```go
func (c *IRCCore) GetInviteLink(_ string) (string, error)
```

Returns an `irc://` URL for the channel.

### Members

#### AddMembers

```go
func (c *IRCCore) AddMembers(chatID string, userIDs []string) error
```

Sends INVITE for each user to the channel.

#### RemoveMember

```go
func (c *IRCCore) RemoveMember(chatID string, userID string) error
```

Kicks the user from the channel.

#### BanMember

```go
func (c *IRCCore) BanMember(chatID string, userID string) error
```

Sets mode +b on the user's hostmask and kicks them.

#### UnbanMember

```go
func (c *IRCCore) UnbanMember(chatID string, userID string) error
```

Removes mode +b for the user's hostmask.

#### GetMembers

```go
func (c *IRCCore) GetMembers(chatID string, opts PaginationOpts) ([]User, error)
```

Returns the cached NAMES list for the channel as User objects with role info (op, voice, etc.).

#### SetAdmin

```go
func (c *IRCCore) SetAdmin(chatID string, userID string, admin bool) error
```

Grants or revokes channel operator status (+o / -o).

### Contacts

#### GetContacts / AddContact / DeleteContact

```go
func (c *IRCCore) GetContacts() ([]User, error)
func (c *IRCCore) AddContact(_ string, _ string, _ string) error
func (c *IRCCore) DeleteContact(_ string) error
```

Not supported. Returns `ErrNotSupported`.

### Blocking

#### BlockUser

```go
func (c *IRCCore) BlockUser(userID string) error
```

Adds user to the local block list. Messages from blocked users are suppressed.

#### UnblockUser

```go
func (c *IRCCore) UnblockUser(userID string) error
```

Removes user from the local block list.

#### GetBlockedUsers

```go
func (c *IRCCore) GetBlockedUsers() ([]User, error)
```

Returns the list of locally blocked users.

### Search

#### SearchMessages

```go
func (c *IRCCore) SearchMessages(chatID string, query string, opts PaginationOpts) ([]Message, error)
```

Searches the local message cache for messages matching the query string.

#### SearchGlobal

```go
func (c *IRCCore) SearchGlobal(query string, opts PaginationOpts) ([]Dialog, error)
```

Searches channels/users matching the query across the LIST and NAMES caches.

### Profile

#### GetProfile

```go
func (c *IRCCore) GetProfile(userID string) (*User, error)
```

Returns user information from cached WHOIS data or the NAMES list.

### Sessions

#### GetSessions / TerminateSession

```go
func (c *IRCCore) GetSessions() ([]Session, error)
func (c *IRCCore) TerminateSession(_ string) error
```

Not supported. IRC has no multi-session concept. Returns `ErrNotSupported`.

### Polls & Stickers

#### CreatePoll / VotePoll / SendSticker

```go
func (c *IRCCore) CreatePoll(_ string, _ string, _ []string) (*Message, error)
func (c *IRCCore) VotePoll(_ string, _ string, _ int) error
func (c *IRCCore) SendSticker(_ string, _ string) (*Message, error)
```

Not supported. Returns `ErrNotSupported`.

### Location

#### SendLocation

```go
func (c *IRCCore) SendLocation(chatID string, lat float64, lon float64) (*Message, error)
```

Not supported. Returns `ErrNotSupported`.

---

## Channel Operations

### JoinKey

```go
func (c *IRCCore) JoinKey(channel, key string)
```

Joins a channel with a key (password).

```go
irc.JoinKey("#secret", "channelpassword")
```

### JoinMultiple

```go
func (c *IRCCore) JoinMultiple(channels []string, keys []string)
```

Joins multiple channels in a single command. Keys correspond positionally to channels.

```go
irc.JoinMultiple([]string{"#a", "#b", "#c"}, []string{"key_a"})
```

### PartMessage

```go
func (c *IRCCore) PartMessage(channel, reason string)
```

Leaves a channel with an optional reason.

### PartMultiple

```go
func (c *IRCCore) PartMultiple(channels []string, reason string)
```

Leaves multiple channels in a single command.

### LeaveAllChannels

```go
func (c *IRCCore) LeaveAllChannels()
```

Sends `JOIN 0` to leave all channels (per RFC 2812).

### GetChannelTopic

```go
func (c *IRCCore) GetChannelTopic(channel string) (string, string, error)
```

Returns the cached topic text and who set it. Returns `ErrNotFound` if not in the channel.

### SetMode

```go
func (c *IRCCore) SetMode(target, modes string, params ...string)
```

Sets modes on a channel or user. General-purpose mode command.

```go
irc.SetMode("#channel", "+o", "alice")
irc.SetMode("#channel", "+ntk", "secretkey")
```

### Knock

```go
func (c *IRCCore) Knock(channel string)
```

Requests an invitation to an invite-only channel.

### RequestNames

```go
func (c *IRCCore) RequestNames(channel string)
```

Explicitly requests the NAMES list for a channel.

### SetVoice

```go
func (c *IRCCore) SetVoice(channel, nick string, voice bool)
```

Grants or revokes voice (+v / -v) on a user in a channel.

### SetHalfop

```go
func (c *IRCCore) SetHalfop(channel, nick string, halfop bool)
```

Grants or revokes halfop (+h / -h) on a user in a channel.

### KickWithReason

```go
func (c *IRCCore) KickWithReason(channel, nick, reason string)
```

Kicks a user from a channel with a reason.

### BanMask

```go
func (c *IRCCore) BanMask(channel, mask string)
```

Sets +b on a hostmask.

```go
irc.BanMask("#channel", "*!*@bad.host.com")
```

### UnbanMask

```go
func (c *IRCCore) UnbanMask(channel, mask string)
```

Removes +b from a hostmask.

### SetChannelKey

```go
func (c *IRCCore) SetChannelKey(channel, key string)
```

Sets or removes the channel key (+k / -k). Empty key removes it.

### SetChannelLimit

```go
func (c *IRCCore) SetChannelLimit(channel string, limit int)
```

Sets or removes the channel user limit (+l). Limit of 0 removes it.

### SetChannelModerated

```go
func (c *IRCCore) SetChannelModerated(channel string, moderated bool)
```

Sets or unsets moderated mode (+m / -m).

### SetChannelInviteOnly

```go
func (c *IRCCore) SetChannelInviteOnly(channel string, inviteOnly bool)
```

Sets or unsets invite-only mode (+i / -i).

### SetChannelNoExternal

```go
func (c *IRCCore) SetChannelNoExternal(channel string, noExternal bool)
```

Sets or unsets no-external-messages mode (+n / -n).

### SetChannelSecret

```go
func (c *IRCCore) SetChannelSecret(channel string, secret bool)
```

Sets or unsets secret mode (+s / -s).

### SetChannelTopicLock

```go
func (c *IRCCore) SetChannelTopicLock(channel string, locked bool)
```

Sets or unsets topic lock mode (+t / -t). When locked, only ops can change the topic.

### RequestInviteList

```go
func (c *IRCCore) RequestInviteList(channel string)
```

Requests the invite exception list (+I) for a channel.

### RenameChannel

```go
func (c *IRCCore) RenameChannel(oldName, newName, reason string)
```

Renames a channel (requires server support for IRCv3 `channel-rename` capability).

### Cycle

```go
func (c *IRCCore) Cycle(channel string)
```

Parts and immediately rejoins a channel (CYCLE command, non-RFC).

---

## Messaging & CTCP

### SendNotice

```go
func (c *IRCCore) SendNotice(target, text string)
```

Sends a NOTICE to a channel or user. Notices should not be auto-replied to.

### SendAction

```go
func (c *IRCCore) SendAction(target, text string)
```

Sends a CTCP ACTION (/me) to a target.

```go
irc.SendAction("#channel", "waves hello")
// Displays as: * mynick waves hello
```

### SendCTCP

```go
func (c *IRCCore) SendCTCP(target, command, params string)
```

Sends a CTCP request to a target. Used for VERSION, PING, TIME, etc.

```go
irc.SendCTCP("alice", "VERSION", "")
irc.SendCTCP("alice", "PING", "1234567890")
```

### SendCTCPReply

```go
func (c *IRCCore) SendCTCPReply(target, command, params string)
```

Sends a CTCP reply via NOTICE.

### Wallops

```go
func (c *IRCCore) Wallops(message string)
```

Sends a WALLOPS message (broadcast to users with +w mode).

### SendStatusMsg

```go
func (c *IRCCore) SendStatusMsg(prefix, channel, text string)
```

Sends a PRIVMSG only to users with a specific status prefix in a channel.

```go
irc.SendStatusMsg("@", "#channel", "ops-only message")
irc.SendStatusMsg("+", "#channel", "voiced and above")
```

### SendStatusNotice

```go
func (c *IRCCore) SendStatusNotice(prefix, channel, text string)
```

Sends a NOTICE only to users with a specific status prefix in a channel.

### CPrivmsg

```go
func (c *IRCCore) CPrivmsg(nick, channel, text string)
```

Sends a CPRIVMSG, bypassing channel flood limits (available to voiced/ops).

### CNotice

```go
func (c *IRCCore) CNotice(nick, channel, text string)
```

Sends a CNOTICE, bypassing channel flood limits (available to voiced/ops).

---

## User Operations

### GetNick

```go
func (c *IRCCore) GetNick() string
```

Returns the client's current nickname.

### ChangeNick

```go
func (c *IRCCore) ChangeNick(newNick string)
```

Changes the client's nickname.

### SetName

```go
func (c *IRCCore) SetName(realname string)
```

Changes the client's realname (requires IRCv3 SETNAME support).

### Away

```go
func (c *IRCCore) Away(message string)
```

Sets the away message. Empty string clears away status.

```go
irc.Away("Gone for lunch")
irc.Away("") // back
```

### GetAway

```go
func (c *IRCCore) GetAway() string
```

Returns the current away message (empty if not away).

### Oper

```go
func (c *IRCCore) Oper(name, password string)
```

Authenticates as an IRC operator (OPER command).

### QuitMessage

```go
func (c *IRCCore) QuitMessage(message string)
```

Disconnects with a custom quit message. Defaults to "Goodbye" if empty.

### Who

```go
func (c *IRCCore) Who(mask string) ([]IRCWhoEntry, error)
```

Sends a WHO query and waits for the response. Returns structured entries.

```go
entries, err := irc.Who("#channel")
for _, e := range entries {
    fmt.Printf("%s!%s@%s (%s)\n", e.Nick, e.User, e.Host, e.Flags)
}
```

### WhoX

```go
func (c *IRCCore) WhoX(mask, fields string)
```

Sends an extended WHO query with custom fields (WHOX).

```go
irc.WhoX("#channel", "nuhsra") // nick, user, host, server, realname, account
```

### RequestWhois

```go
func (c *IRCCore) RequestWhois(nick string)
```

Sends a WHOIS query. Results arrive via the update handler.

### Whowas

```go
func (c *IRCCore) Whowas(nick string, count int) ([]IRCWhowasEntry, error)
```

Queries historical info for a nick. Returns up to `count` entries.

### Userhost

```go
func (c *IRCCore) Userhost(nicks ...string) ([]IRCUserhostEntry, error)
```

Queries the user/host info for up to 5 nicks.

### Ison

```go
func (c *IRCCore) Ison(nicks ...string) ([]string, error)
```

Checks which of the given nicks are currently online. Returns the online nicks.

### UserIP

```go
func (c *IRCCore) UserIP(nicks ...string)
```

Queries the IP address of up to 5 users (non-RFC, supported by UnrealIRCd/InspIRCd).

### RequestUsers

```go
func (c *IRCCore) RequestUsers(target string)
```

Requests the list of users logged into the server host (USERS command).

### SetUserMode

```go
func (c *IRCCore) SetUserMode(modes string)
```

Sets user modes as a raw mode string.

```go
irc.SetUserMode("+iw")
```

### GetUserMode

```go
func (c *IRCCore) GetUserMode()
```

Requests the current user modes from the server.

### Silence

```go
func (c *IRCCore) Silence(mask string)
```

Manages the server-side ignore list (SILENCE command). Use `"+mask"` to add, `"-mask"` to remove, empty string to query.

### Accept

```go
func (c *IRCCore) Accept(args string)
```

Manages the ACCEPT list (caller-ID mode). Use `"+nick"` to add, `"-nick"` to remove, `"*"` to list.

### Vhost

```go
func (c *IRCCore) Vhost(username, password string)
```

Sets own virtual host (VHOST command, UnrealIRCd user command).

---

## Channel Mode Flags

### SetChannelModeFlag

```go
func (c *IRCCore) SetChannelModeFlag(channel string, mode byte, on bool)
```

Sets or unsets a simple boolean channel mode flag.

Common mode chars:
- `c` -- no colors
- `C` -- no CTCP
- `D` -- delayed joins
- `g` -- word filter (freeform)
- `G` -- censor (bad word filter)
- `K` -- no KNOCK
- `M` -- require registered to speak
- `N` -- no nick changes while in channel
- `O` -- oper-only channel
- `P` -- permanent channel
- `Q` -- no kicks
- `R` -- require registered to join
- `S` -- strip colors
- `T` -- no channel notices
- `u` -- auditorium mode
- `V` -- no INVITE
- `z` -- SSL/TLS only

```go
irc.SetChannelModeFlag("#channel", 'R', true)  // require registration to join
irc.SetChannelModeFlag("#channel", 'c', true)  // strip colors
```

### SetFloodProtection

```go
func (c *IRCCore) SetFloodProtection(channel string, params string)
```

Sets channel flood protection mode (+f). Params are server-specific.

```go
irc.SetFloodProtection("#channel", "[10j#R5,40m#M5,3n#N1]:15") // UnrealIRCd
```

### SetChannelHistory

```go
func (c *IRCCore) SetChannelHistory(channel string, lines int, seconds int)
```

Sets the channel history mode (+H lines:seconds). Shows recent history to joining users.

### SetJoinThrottle

```go
func (c *IRCCore) SetJoinThrottle(channel string, joins int, seconds int)
```

Sets the join throttle mode (+j joins:seconds). Limits how fast users can join.

### SetChannelRedirect

```go
func (c *IRCCore) SetChannelRedirect(channel, target string)
```

Sets the channel redirect mode (+L target). Users redirected here when the channel is full.

---

## User Mode Flags

### SetUserModeFlag

```go
func (c *IRCCore) SetUserModeFlag(mode byte, on bool)
```

Sets or unsets a user mode flag.

Common mode chars:
- `B` -- mark as bot
- `d` -- deaf (no channel messages)
- `g` -- caller-ID (only accept messages from ACCEPT list)
- `H` -- hide oper status
- `I` -- hide channel list in WHOIS
- `R` -- block messages from unregistered users
- `T` -- block CTCP
- `W` -- notify on WHOIS
- `Z` -- require SSL for private messages

```go
irc.SetUserModeFlag('B', true)  // mark as bot
irc.SetUserModeFlag('R', true)  // block unregistered
```

---

## Extended Bans

### SetExtban

```go
func (c *IRCCore) SetExtban(channel string, modeChar byte, extbanType, value string)
```

Sets an extended ban (or exception) on a channel.

- `modeChar` -- the mode letter: `'b'` for ban, `'e'` for exception, `'I'` for invite exception
- `extbanType` -- the extban prefix (server-specific)
- `value` -- the mask/account/pattern

```go
irc.SetExtban("#ch", 'b', "~q:", "nick!*@*")       // quiet ban
irc.SetExtban("#ch", 'b', "~a:", "accountname")     // account ban
irc.SetExtban("#ch", 'e', "~m:", "nick!*@*")        // message bypass exception
irc.SetExtban("#ch", 'b', "~t:300:", "nick!*@*")    // timed ban (300s)
irc.SetExtban("#ch", 'b', "~T:block:", "badword")   // text filter
irc.SetExtban("#ch", 'b', "~f:nick!*@*:", "#target") // forward ban
```

### ParseAccountExtban

```go
func (c *IRCCore) ParseAccountExtban(account string) string
```

Returns an extban string for account-based matching, using the server's configured extban prefix. Defaults to `$a:account` if the server doesn't advertise one.

---

## Ban Lists & Exceptions

### GetBanList

```go
func (c *IRCCore) GetBanList(channel string) ([]IRCBanEntry, error)
```

Requests and returns the ban list (+b) for a channel.

### SetBanExcept

```go
func (c *IRCCore) SetBanExcept(channel, mask string, add bool)
```

Adds or removes a ban exception (+e / -e).

### GetExceptList

```go
func (c *IRCCore) GetExceptList(channel string) ([]IRCBanEntry, error)
```

Requests and returns the ban exception list (+e) for a channel.

### SetInviteExcept

```go
func (c *IRCCore) SetInviteExcept(channel, mask string, add bool)
```

Adds or removes an invite exception (+I / -I).

### GetInviteExceptList

```go
func (c *IRCCore) GetInviteExceptList(channel string) ([]IRCBanEntry, error)
```

Requests and returns the invite exception list (+I) for a channel.

---

## NickServ Commands

### NickServIdentify

```go
func (c *IRCCore) NickServIdentify(password string)
```

Identifies to NickServ with the given password.

### NickServRegister

```go
func (c *IRCCore) NickServRegister(password, email string)
```

Registers the current nick with NickServ.

### NickServGhost

```go
func (c *IRCCore) NickServGhost(nick, password string)
```

Disconnects a ghost session using your nick.

### NickServRelease

```go
func (c *IRCCore) NickServRelease(nick, password string)
```

Releases a held nickname.

### NickServInfo

```go
func (c *IRCCore) NickServInfo(nick string)
```

Queries registration info for a nick.

### NickServLogout

```go
func (c *IRCCore) NickServLogout()
```

Logs out from NickServ without disconnecting.

### NickServSetPassword

```go
func (c *IRCCore) NickServSetPassword(newPassword string)
```

Changes the NickServ password.

### NickServGroup

```go
func (c *IRCCore) NickServGroup(target, password string)
```

Links the current nick to an existing account. Empty target groups to the primary nick.

### NickServUngroup

```go
func (c *IRCCore) NickServUngroup(nick string)
```

Unlinks a nick from the account group.

### NickServAccess

```go
func (c *IRCCore) NickServAccess(action, mask string)
```

Manages the authorized address list (ADD, DEL, LIST).

### NickServAjoin

```go
func (c *IRCCore) NickServAjoin(action, channel string)
```

Manages auto-join channels (ADD, DEL, LIST).

### NickServCert

```go
func (c *IRCCore) NickServCert(action, fingerprint string)
```

Manages client certificate fingerprints (ADD, DEL, LIST).

### NickServAlist

```go
func (c *IRCCore) NickServAlist()
```

Lists channels where you have access privileges.

### NickServAcc

```go
func (c *IRCCore) NickServAcc(nick string)
```

Checks authentication level of a user (0=not registered, 1=registered not identified, 2=recognized, 3=identified).

### NickServStatus

```go
func (c *IRCCore) NickServStatus(nick string)
```

Checks owner status of a nickname.

### NickServDrop

```go
func (c *IRCCore) NickServDrop(nick string)
```

Unregisters a nickname. Empty nick drops the current nick.

### NickServSet

```go
func (c *IRCCore) NickServSet(option, value string)
```

Configures a nick option (PASSWORD, ENFORCE, URL, EMAIL, NOMEMO, etc.).

### NickServSendPass

```go
func (c *IRCCore) NickServSendPass(nick string)
```

Requests a password recovery email.

### NickServRecover

```go
func (c *IRCCore) NickServRecover(nick, password string)
```

Disconnects someone using your registered nick.

### NickServUpdate

```go
func (c *IRCCore) NickServUpdate()
```

Refreshes status and checks for memos.

### NickServRegain

```go
func (c *IRCCore) NickServRegain(nick, password string)
```

Recovers and changes to a nick in one step.

### NickServGList

```go
func (c *IRCCore) NickServGList()
```

Lists nicks in the current nick group.

### NickServConfirm

```go
func (c *IRCCore) NickServConfirm(code string)
```

Completes email verification for registration.

### NickServSuspend (oper)

```go
func (c *IRCCore) NickServSuspend(nick, reason string)
```

Suspends a nick (oper only).

### NickServUnsuspend (oper)

```go
func (c *IRCCore) NickServUnsuspend(nick string)
```

Lifts a nick suspension (oper only).

### NickServForbid (oper)

```go
func (c *IRCCore) NickServForbid(nick, reason string)
```

Forbids a nick from being registered (oper only).

### NickServList (oper)

```go
func (c *IRCCore) NickServList(pattern string)
```

Searches registered nicks (oper only).

### NickServSaSet (oper)

```go
func (c *IRCCore) NickServSaSet(nick, option, value string)
```

Admin-sets a nick option for any user (oper only).

---

## ChanServ Commands

### ChanServModeCmd

```go
func (c *IRCCore) ChanServModeCmd(channel, nick, command string)
```

Sends a ChanServ mode command (OP, DEOP, VOICE, DEVOICE, etc.).

### ChanServRegister

```go
func (c *IRCCore) ChanServRegister(channel, password, description string)
```

Registers a channel with ChanServ.

### ChanServDrop

```go
func (c *IRCCore) ChanServDrop(channel string)
```

Drops a channel registration.

### ChanServInvite

```go
func (c *IRCCore) ChanServInvite(channel string)
```

Requests ChanServ to invite you to a channel.

### ChanServAkick

```go
func (c *IRCCore) ChanServAkick(channel, action, mask, reason string)
```

Manages the auto-kick list (ADD, DEL, LIST, CLEAR).

### ChanServInfo

```go
func (c *IRCCore) ChanServInfo(channel string)
```

Displays registration info for a channel.

### ChanServFlags

```go
func (c *IRCCore) ChanServFlags(channel, nick, flags string)
```

Manages user privilege flags. Without nick, lists all flags. Without flags, shows a user's flags.

```go
irc.ChanServFlags("#channel", "alice", "+vVoO") // set flags
irc.ChanServFlags("#channel", "", "")            // list all
```

### ChanServAccess

```go
func (c *IRCCore) ChanServAccess(channel, action, mask, level string)
```

Manages the channel access list (ADD, DEL, LIST, CLEAR).

### ChanServAop / ChanServSop / ChanServHop / ChanServVop / ChanServQop

```go
func (c *IRCCore) ChanServAop(channel, action, nick string)
func (c *IRCCore) ChanServSop(channel, action, nick string)
func (c *IRCCore) ChanServHop(channel, action, nick string)
func (c *IRCCore) ChanServVop(channel, action, nick string)
func (c *IRCCore) ChanServQop(channel, action, nick string)
```

Manage the Auto-Op, Super-Op, Half-Op, Voice, and channel owner lists respectively.

### ChanServBan / ChanServUnban

```go
func (c *IRCCore) ChanServBan(channel, nick string)
func (c *IRCCore) ChanServUnban(channel, nick string)
```

Bans/unbans a user via ChanServ.

### ChanServKick

```go
func (c *IRCCore) ChanServKick(channel, nick, reason string)
```

Kicks a user via ChanServ.

### ChanServTopic

```go
func (c *IRCCore) ChanServTopic(channel, topic string)
```

Sets the channel topic via ChanServ (bypasses +t restriction).

### ChanServAppendTopic

```go
func (c *IRCCore) ChanServAppendTopic(channel, text string)
```

Appends text to the existing channel topic.

### ChanServUp / ChanServDown

```go
func (c *IRCCore) ChanServUp(channel string)
func (c *IRCCore) ChanServDown(channel string)
```

Updates your own channel status to match your access level (UP) or removes your privileges (DOWN).

### ChanServSet

```go
func (c *IRCCore) ChanServSet(channel, option, value string)
```

Configures a channel option (KEEPTOPIC, TOPICLOCK, MLOCK, PRIVATE, RESTRICTED, SECURE, etc.).

### ChanServClear

```go
func (c *IRCCore) ChanServClear(channel, what string)
```

Clears a channel attribute (MODES, BANS, USERS, OPS, VOICES, etc.).

### ChanServEnforce

```go
func (c *IRCCore) ChanServEnforce(channel string)
```

Applies channel modes and access lists immediately.

### ChanServEntryMsg

```go
func (c *IRCCore) ChanServEntryMsg(channel, message string)
```

Sets the message shown when users join a channel.

### ChanServSync

```go
func (c *IRCCore) ChanServSync(channel string)
```

Synchronizes channel modes with the access list.

### ChanServGetKey

```go
func (c *IRCCore) ChanServGetKey(channel string)
```

Retrieves the channel key.

### ChanServStatus

```go
func (c *IRCCore) ChanServStatus(channel, nick string)
```

Shows a user's access level in a channel.

### ChanServList

```go
func (c *IRCCore) ChanServList(pattern string)
```

Searches registered channels. Empty pattern lists all.

### ChanServClone

```go
func (c *IRCCore) ChanServClone(source, target string)
```

Duplicates settings from one channel to another.

### ChanServIdentify

```go
func (c *IRCCore) ChanServIdentify(channel, password string)
```

Authenticates as channel founder.

### ChanServMode

```go
func (c *IRCCore) ChanServMode(channel, modes string)
```

Sets channel modes via ChanServ.

### ChanServLevels

```go
func (c *IRCCore) ChanServLevels(channel, action, level, value string)
```

Manages access level definitions for a channel (SET, DIS, LIST, RESET).

### ChanServLog

```go
func (c *IRCCore) ChanServLog(channel string)
```

Views the action log for a channel.

### ChanServCount

```go
func (c *IRCCore) ChanServCount(channel string)
```

Counts access list entries for a channel.

### ChanServSuspend / ChanServUnsuspend (oper)

```go
func (c *IRCCore) ChanServSuspend(channel, reason string)
func (c *IRCCore) ChanServUnsuspend(channel string)
```

Suspends/unsuspends a channel (oper only).

### ChanServForbid (oper)

```go
func (c *IRCCore) ChanServForbid(channel, reason string)
```

Forbids a channel from being registered (oper only).

---

## MemoServ Commands

### MemoServSend

```go
func (c *IRCCore) MemoServSend(target, text string)
```

Sends a memo to a user.

### MemoServRead

```go
func (c *IRCCore) MemoServRead(which string)
```

Reads a memo by number or range (e.g. "1", "2-5", "ALL", "NEW").

### MemoServList

```go
func (c *IRCCore) MemoServList()
```

Lists all memos.

### MemoServDelete

```go
func (c *IRCCore) MemoServDelete(which string)
```

Deletes a memo by number, range, or "ALL".

### MemoServRSend

```go
func (c *IRCCore) MemoServRSend(target, text string)
```

Sends a memo with read receipt.

### MemoServCancel

```go
func (c *IRCCore) MemoServCancel(target string)
```

Cancels the most recent unread memo to a target.

### MemoServCheck

```go
func (c *IRCCore) MemoServCheck(target string)
```

Checks if a memo was read by the target.

### MemoServInfo

```go
func (c *IRCCore) MemoServInfo(target string)
```

Displays memo account information. Empty target shows your own info.

### MemoServIgnore

```go
func (c *IRCCore) MemoServIgnore(action, nick string)
```

Manages memo sender ignore list (ADD, DEL, LIST).

### MemoServSet

```go
func (c *IRCCore) MemoServSet(option, value string)
```

Configures memo options (NOTIFY, LIMIT, etc.).

### MemoServSendGroup

```go
func (c *IRCCore) MemoServSendGroup(group, text string)
```

Sends a memo to a nick group.

### MemoServSendOps

```go
func (c *IRCCore) MemoServSendOps(channel, text string)
```

Sends a memo to channel operators.

### MemoServForward

```go
func (c *IRCCore) MemoServForward(memoID, target string)
```

Forwards a memo to another user.

### MemoServStaff (oper)

```go
func (c *IRCCore) MemoServStaff(text string)
```

Sends a memo to all staff (oper only).

---

## HostServ Commands

### HostServOn / HostServOff

```go
func (c *IRCCore) HostServOn()
func (c *IRCCore) HostServOff()
```

Activates or deactivates the assigned virtual host.

### HostServRequest

```go
func (c *IRCCore) HostServRequest(vhost string)
```

Submits a custom vhost for approval.

### HostServGroup

```go
func (c *IRCCore) HostServGroup()
```

Syncs vhost across grouped nicks.

### HostServList

```go
func (c *IRCCore) HostServList()
```

Lists own vhosts.

### HostServSet (oper)

```go
func (c *IRCCore) HostServSet(nick, vhost string)
```

Assigns a vhost to a nick (oper only).

### HostServSetAll (oper)

```go
func (c *IRCCore) HostServSetAll(nick, vhost string)
```

Assigns a vhost to a nick group (oper only).

### HostServDel / HostServDelAll (oper)

```go
func (c *IRCCore) HostServDel(nick string)
func (c *IRCCore) HostServDelAll(nick string)
```

Removes a vhost from a nick or a nick group (oper only).

### HostServActivate (oper)

```go
func (c *IRCCore) HostServActivate(nick string)
```

Approves a pending vhost request (oper only).

### HostServReject (oper)

```go
func (c *IRCCore) HostServReject(nick, reason string)
```

Rejects a pending vhost request (oper only).

### HostServWaiting (oper)

```go
func (c *IRCCore) HostServWaiting()
```

Lists pending vhost requests (oper only).

---

## BotServ Commands

### BotServBotList

```go
func (c *IRCCore) BotServBotList()
```

Lists available service bots.

### BotServAssign / BotServUnassign

```go
func (c *IRCCore) BotServAssign(channel, botNick string)
func (c *IRCCore) BotServUnassign(channel string)
```

Assigns or removes a bot from a channel.

### BotServInfo

```go
func (c *IRCCore) BotServInfo(target string)
```

Views bot or channel bot details.

### BotServSay / BotServAct

```go
func (c *IRCCore) BotServSay(channel, text string)
func (c *IRCCore) BotServAct(channel, text string)
```

Makes a bot send a message or action to a channel.

### BotServBotAdd / BotServBotDel / BotServBotChange (oper)

```go
func (c *IRCCore) BotServBotAdd(nick, ident, host, realname string)
func (c *IRCCore) BotServBotDel(nick string)
func (c *IRCCore) BotServBotChange(oldNick, newNick, ident, host, realname string)
```

Creates, deletes, or modifies bots (oper only).

### BotServBadwords

```go
func (c *IRCCore) BotServBadwords(channel, action, word string)
```

Manages the bad word filter list (ADD, DEL, LIST, CLEAR).

### BotServKickConfig

```go
func (c *IRCCore) BotServKickConfig(channel, option, value string)
```

Configures auto-kick triggers for a channel bot.

### BotServSet

```go
func (c *IRCCore) BotServSet(channel, option, value string)
```

Configures bot settings for a channel.

---

## OperServ Commands

All OperServ commands require IRC operator privileges.

### OperServAkill

```go
func (c *IRCCore) OperServAkill(action, mask, reason string)
```

Manages network-wide K-lines (ADD, DEL, LIST, CLEAR).

### OperServSqline

```go
func (c *IRCCore) OperServSqline(action, mask, reason string)
```

Manages nick/channel quarantines (ADD, DEL, LIST).

### OperServSnline

```go
func (c *IRCCore) OperServSnline(action, mask, reason string)
```

Manages realname bans (ADD, DEL, LIST).

### OperServSession

```go
func (c *IRCCore) OperServSession(action, host string)
```

Views/manages session limits.

### OperServNoop

```go
func (c *IRCCore) OperServNoop(server, action string)
```

Disables O-lines on a server.

### OperServJupe

```go
func (c *IRCCore) OperServJupe(server, reason string)
```

Fakes/quarantines a server.

### OperServGlobal

```go
func (c *IRCCore) OperServGlobal(message string)
```

Sends a global notice to all users.

### OperServDefcon

```go
func (c *IRCCore) OperServDefcon(level int)
```

Sets the network defense level (1-5).

### OperServStats

```go
func (c *IRCCore) OperServStats(what string)
```

Shows services statistics. Empty `what` shows general stats.

### OperServReload

```go
func (c *IRCCore) OperServReload(module string)
```

Reloads services configuration modules. Empty module reloads all.

### OperServShutdown / OperServRestart

```go
func (c *IRCCore) OperServShutdown()
func (c *IRCCore) OperServRestart()
```

Shuts down or restarts services.

---

## GroupServ Commands

Atheme GroupServ commands.

### GroupServInfo

```go
func (c *IRCCore) GroupServInfo(group string)
```

Shows info about a group.

### GroupServJoin / GroupServLeave

```go
func (c *IRCCore) GroupServJoin(group string)
func (c *IRCCore) GroupServLeave(group string)
```

Joins or leaves a group.

### GroupServFlags

```go
func (c *IRCCore) GroupServFlags(group, target, flags string)
```

Manages group flags.

---

## StatServ Commands

### StatServInfo

```go
func (c *IRCCore) StatServInfo()
```

Shows network statistics.

### StatServAkill

```go
func (c *IRCCore) StatServAkill()
```

Shows akill statistics.

---

## Oper Commands -- RFC

These require IRC operator privileges (obtained via `Oper()`).

### Kill

```go
func (c *IRCCore) Kill(nick, reason string)
```

Disconnects a user from the network.

### Connect

```go
func (c *IRCCore) Connect(target string, port int, remote string)
```

Requests the server to link to another server. If `remote` is provided, the command is forwarded to that server.

### Die

```go
func (c *IRCCore) Die()
```

Requests the server to shut down.

### Rehash

```go
func (c *IRCCore) Rehash()
```

Requests the server to reload its configuration.

### Restart

```go
func (c *IRCCore) Restart()
```

Requests the server to restart.

---

## Oper Commands -- UnrealIRCd

### GLine

```go
func (c *IRCCore) GLine(mask, duration, reason string)
```

Adds a network-wide ban (G-Line). Duration format: e.g. `"1h"`, `"7d"`, `"0"` for permanent.

### GZLine

```go
func (c *IRCCore) GZLine(ip, duration, reason string)
```

Adds a network-wide IP ban without ident lookup.

### ZLine

```go
func (c *IRCCore) ZLine(ip, duration, reason string)
```

Adds a server-local IP ban.

### KLine

```go
func (c *IRCCore) KLine(mask, duration, reason string)
```

Adds a server-local ban by user@host mask.

### Shun

```go
func (c *IRCCore) Shun(mask, duration, reason string)
```

Silences a user network-wide (they stay connected but cannot send messages).

### Eline

```go
func (c *IRCCore) Eline(mask, duration, reason string)
```

Adds or removes a ban exception (E-Line). Empty reason removes it.

### Tempshun

```go
func (c *IRCCore) Tempshun(nick, reason string)
```

Temporarily shuns a user (lasts until they disconnect).

### SpamfilterAdd / SpamfilterDel

```go
func (c *IRCCore) SpamfilterAdd(target, action, tkltime, reason, regex string)
func (c *IRCCore) SpamfilterDel(target, action, regex string)
```

Manages server spam filters. Target is where to match (channel/private/etc.), action is what to do on match.

### Rmtkl

```go
func (c *IRCCore) Rmtkl(tklType, pattern string)
```

Removes TKL (temporary K-line) entries matching a pattern.

### Jumpserver

```go
func (c *IRCCore) Jumpserver(addr, port, reason string)
```

Redirects all clients to another server.

### Tsctl

```go
func (c *IRCCore) Tsctl(subcmd string)
```

TS (timestamp) control command.

### Dccdeny / Undccdeny

```go
func (c *IRCCore) Dccdeny(filePattern, reason string)
func (c *IRCCore) Undccdeny(filePattern string)
```

Manages DCC deny rules.

### Dccallow

```go
func (c *IRCCore) Dccallow(args string)
```

Manages DCC allow list.

### Sdesc

```go
func (c *IRCCore) Sdesc(desc string)
```

Changes the server description.

### Mkpasswd

```go
func (c *IRCCore) Mkpasswd(hashType, password string)
```

Generates a password hash.

### Ircops

```go
func (c *IRCCore) Ircops()
```

Lists online IRC operators.

### CloseConnections

```go
func (c *IRCCore) CloseConnections()
```

Closes all unregistered connections.

### DnsInfo

```go
func (c *IRCCore) DnsInfo(args string)
```

Queries DNS cache info.

### Addmotd / Addomotd

```go
func (c *IRCCore) Addmotd(line string)
func (c *IRCCore) Addomotd(line string)
```

Appends a line to the MOTD or oper MOTD.

### Botmotd / Opermotd

```go
func (c *IRCCore) Botmotd()
func (c *IRCCore) Opermotd()
```

Displays the bot MOTD or oper MOTD.

### ShowCredits / ShowLicense / ShowStaff

```go
func (c *IRCCore) ShowCredits()
func (c *IRCCore) ShowLicense()
func (c *IRCCore) ShowStaff()
```

Displays server credits, license, or staff list.

### ModuleManage

```go
func (c *IRCCore) ModuleManage(action, moduleName string)
```

Manages server modules. Actions: `"list"`, `"load"`, `"unload"`.

### Qline / QlineDel

```go
func (c *IRCCore) Qline(nick, reason string)
func (c *IRCCore) QlineDel(nick string)
```

Quarantines/unquarantines a nickname.

---

## Oper Commands -- InspIRCd

### ForcePart

```go
func (c *IRCCore) ForcePart(nick, channel, reason string)
```

Forcibly removes a user from a channel (REMOVE command).

### Uninvite

```go
func (c *IRCCore) Uninvite(nick, channel string)
```

Revokes an invitation to a channel.

### Clearchan

```go
func (c *IRCCore) Clearchan(channel, action string)
```

Clears a channel attribute (USERS, OPS, VOICES, etc.).

### Cban / CbanDel

```go
func (c *IRCCore) Cban(channel, reason string)
func (c *IRCCore) CbanDel(channel string)
```

Bans/unbans a channel from being used.

### Rline / RlineDel

```go
func (c *IRCCore) Rline(regex, duration, reason string)
func (c *IRCCore) RlineDel(regex string)
```

Manages regex-based bans.

### Tline

```go
func (c *IRCCore) Tline(mask string)
```

Tests how many users match a ban mask.

### Clones

```go
func (c *IRCCore) Clones()
```

Lists users with multiple connections from the same host.

### Rconnect

```go
func (c *IRCCore) Rconnect(serverMask, remoteTarget string)
```

Requests a remote server to connect to another server.

### Rsquit

```go
func (c *IRCCore) Rsquit(serverMask, reason string)
```

Requests a remote server to disconnect from the network.

### Nicklock / Nickunlock

```go
func (c *IRCCore) Nicklock(nick, newNick string)
func (c *IRCCore) Nickunlock(nick string)
```

Locks or unlocks a user's nickname.

### Setidle

```go
func (c *IRCCore) Setidle(seconds int)
```

Sets your idle time.

### Swhois

```go
func (c *IRCCore) Swhois(nick, line string)
```

Adds a custom WHOIS line for a user.

### Ojoin

```go
func (c *IRCCore) Ojoin(channel string)
```

Joins a channel with oper override.

### Sakick

```go
func (c *IRCCore) Sakick(channel, nick, reason string)
```

Forces a kick with oper privileges.

### Saquit

```go
func (c *IRCCore) Saquit(nick, reason string)
```

Forces a user to quit with a given reason.

### Satopic

```go
func (c *IRCCore) Satopic(channel, topic string)
```

Forces a topic change with oper privileges.

### Rmode

```go
func (c *IRCCore) Rmode(mask, modes string)
```

Applies modes to channels matching a mask.

### FilterAdd / FilterDel

```go
func (c *IRCCore) FilterAdd(pattern string)
func (c *IRCCore) FilterDel(pattern string)
```

Manages server message filters.

### Alltime

```go
func (c *IRCCore) Alltime()
```

Shows the time on all linked servers.

### Check

```go
func (c *IRCCore) Check(target string)
```

Inspects user/channel details.

---

## Oper Commands -- Server Extensions

### SetHost

```go
func (c *IRCCore) SetHost(vhost string)
```

Sets own virtual host (oper only).

### ChgHost / ChgIdent / ChgName

```go
func (c *IRCCore) ChgHost(nick, newHost string)
func (c *IRCCore) ChgIdent(nick, newIdent string)
func (c *IRCCore) ChgName(nick, newName string)
```

Changes another user's hostname, ident, or realname (oper only).

### SaJoin / SaPart

```go
func (c *IRCCore) SaJoin(nick, channel string)
func (c *IRCCore) SaPart(nick, channel string)
```

Forces a user to join or part a channel (oper only).

### SaNick

```go
func (c *IRCCore) SaNick(oldNick, newNick string)
```

Forces a user to change nick (oper only).

### SaMode

```go
func (c *IRCCore) SaMode(target, modes string)
```

Forces a mode change on a channel or user (oper only).

### Globops

```go
func (c *IRCCore) Globops(message string)
```

Sends an oper-only global broadcast message.

---

## DCC & XDCC

### DCCSend

```go
func (c *IRCCore) DCCSend(nick, filename string, port int, size int64)
```

Sends a DCC SEND request to a user for file transfer.

### DCCChat

```go
func (c *IRCCore) DCCChat(nick string, port int)
```

Sends a DCC CHAT request to a user for direct messaging.

### DCCResume

```go
func (c *IRCCore) DCCResume(nick, filename string, port int, position int64)
```

Sends a DCC RESUME request to continue an interrupted file transfer.

### DCCAccept

```go
func (c *IRCCore) DCCAccept(nick, filename string, port int, position int64)
```

Accepts a DCC RESUME request from another user.

### DCCSecureSend

```go
func (c *IRCCore) DCCSecureSend(nick, filename string, port int, size int64)
```

Sends a DCC SSEND (TLS-encrypted file transfer) request.

### DCCSecureChat

```go
func (c *IRCCore) DCCSecureChat(nick string, port int)
```

Sends a DCC SCHAT (TLS-encrypted chat) request.

### DCCReverse

```go
func (c *IRCCore) DCCReverse(nick, filename string, size int64, token string)
```

Initiates a passive/reverse DCC transfer (port 0 for NAT traversal). The receiver connects back using the token.

### RDCC

```go
func (c *IRCCore) RDCC(nick string)
```

Initiates an advanced DCC Server handshake.

### GetDCCOffers

```go
func (c *IRCCore) GetDCCOffers() []IRCDCCOffer
```

Returns pending DCC offers received from other users.

### ClearDCCOffers

```go
func (c *IRCCore) ClearDCCOffers()
```

Clears all pending DCC offers.

### XDCCSend

```go
func (c *IRCCore) XDCCSend(botNick string, packNum int)
```

Requests a file from an XDCC bot.

```go
irc.XDCCSend("filebot", 42) // sends: XDCC SEND #42
```

### XDCCList

```go
func (c *IRCCore) XDCCList(botNick string)
```

Requests the pack list from an XDCC bot.

### XDCCBatch

```go
func (c *IRCCore) XDCCBatch(botNick string, packNums []int)
```

Requests multiple packs from an XDCC bot.

### XDCCCancel

```go
func (c *IRCCore) XDCCCancel(botNick string)
```

Cancels the current XDCC transfer.

### XDCCRemove

```go
func (c *IRCCore) XDCCRemove(botNick string, packNum int)
```

Removes a pack (bot owner only).

### XDCCInfo

```go
func (c *IRCCore) XDCCInfo(botNick string, packNum int)
```

Shows details about a specific pack.

### XDCCSearch

```go
func (c *IRCCore) XDCCSearch(botNick, query string)
```

Searches packs on an XDCC bot.

---

## CTCP Extended

### CTCPFinger

```go
func (c *IRCCore) CTCPFinger(target string)
```

Sends a CTCP FINGER query.

### CTCPSource

```go
func (c *IRCCore) CTCPSource(target string)
```

Sends a CTCP SOURCE query.

### CTCPUserinfo

```go
func (c *IRCCore) CTCPUserinfo(target string)
```

Sends a CTCP USERINFO query.

### CTCPErrMsg

```go
func (c *IRCCore) CTCPErrMsg(nick, query, message string)
```

Sends a CTCP ERRMSG reply.

### CTCPAvatar

```go
func (c *IRCCore) CTCPAvatar(nick, url string)
```

Sends a CTCP AVATAR reply with a URL.

### GetCTCPClientInfo

```go
func (c *IRCCore) GetCTCPClientInfo() string
```

Returns the list of CTCP commands this client supports: `"ACTION VERSION PING TIME CLIENTINFO FINGER USERINFO SOURCE DCC"`.

---

## IRCv3 Capabilities & Extensions

### HasCapability

```go
func (c *IRCCore) HasCapability(cap string) bool
```

Checks if a specific IRCv3 capability is enabled.

```go
if irc.HasCapability("message-tags") {
    irc.SendTypingIndicator("#channel", true)
}
```

### GetEnabledCaps

```go
func (c *IRCCore) GetEnabledCaps() []string
```

Returns the sorted list of currently enabled IRCv3 capabilities.

### RequestCAPList

```go
func (c *IRCCore) RequestCAPList()
```

Requests the list of currently enabled capabilities from the server (CAP LIST).

### RequestCAP

```go
func (c *IRCCore) RequestCAP(caps ...string)
```

Requests additional capabilities after registration (CAP REQ).

```go
irc.RequestCAP("message-tags", "draft/typing")
```

### RequestNoImplicitNames

```go
func (c *IRCCore) RequestNoImplicitNames()
```

Requests the `draft/no-implicit-names` capability (disables automatic NAMES on JOIN).

### RequestExtendedMonitor

```go
func (c *IRCCore) RequestExtendedMonitor()
```

Requests the `draft/extended-monitor` capability.

### RequestExtendedIsupport

```go
func (c *IRCCore) RequestExtendedIsupport()
```

Requests the `draft/extended-isupport` capability.

### SendTagMsg

```go
func (c *IRCCore) SendTagMsg(target string, tags map[string]string)
```

Sends a TAGMSG (message-tags only, no text content). Requires `message-tags` capability.

```go
irc.SendTagMsg("#channel", map[string]string{"+typing": "active"})
```

### SendTypingIndicator

```go
func (c *IRCCore) SendTypingIndicator(target string, typing bool)
```

Sends a typing indicator via TAGMSG. `true` = active, `false` = done.

### SendChannelContextTag

```go
func (c *IRCCore) SendChannelContextTag(target, channelCtx, tags string)
```

Sends a TAGMSG with a `+draft/channel-context` tag.

### SendReactTag

```go
func (c *IRCCore) SendReactTag(target, msgID, emoji string)
```

Sends a reaction via TAGMSG using `+draft/react` and `+draft/reply` tags.

```go
irc.SendReactTag("#channel", "msgid123", "thumbsup")
```

### Redact

```go
func (c *IRCCore) Redact(target, msgid, reason string)
```

Redacts/deletes a previously sent message by msgid (IRCv3 draft).

### Register / Verify

```go
func (c *IRCCore) Register(account, email, password string)
func (c *IRCCore) Verify(account, code string)
```

In-band account registration (IRCv3 `draft/account-registration`). Register creates the account; Verify confirms with a verification code.

### MarkRead

```go
func (c *IRCCore) MarkRead(target, msgid string)
```

Sets or queries the read marker for a target (IRCv3 draft). Empty msgid queries the current marker.

### Relaymsg

```go
func (c *IRCCore) Relaymsg(channel, nick, text string)
```

Sends a message as a relay (appears to come from a different nick). Requires `draft/relaymsg` capability.

### Starttls

```go
func (c *IRCCore) Starttls()
```

Requests TLS upgrade on a plain text connection (STARTTLS command).

### STSAutoUpgrade

```go
func (c *IRCCore) STSAutoUpgrade(domain string, port int) error
```

Stores an STS (Strict Transport Security) policy for automatic TLS upgrade.

### STSRemember

```go
func (c *IRCCore) STSRemember(domain string, port int, duration time.Duration)
```

Remembers an STS policy with a specific duration.

### ConnectWebSocket

```go
func (c *IRCCore) ConnectWebSocket(url string) error
```

Stores a WebSocket URL for IRC-over-WebSocket connections. Returns an error as external ws library is needed.

### GetNetworkIcon

```go
func (c *IRCCore) GetNetworkIcon() string
```

Returns the network icon URL if advertised by the server.

### FilehostUpload

```go
func (c *IRCCore) FilehostUpload(filename string)
```

Sends a FILEHOST UPLOAD command (IRCv3 draft file upload).

### Resume

```go
func (c *IRCCore) Resume(token string, timestamp time.Time)
```

Attempts to resume a disconnected session (IRCv3 `draft/resume`).

### WebPushRegister / WebPushUnregister

```go
func (c *IRCCore) WebPushRegister(endpoint, vapidKey, p256dh, auth string)
func (c *IRCCore) WebPushUnregister(endpoint string)
```

Registers/unregisters for web push notifications.

### BounceListNetworks / BouncerBind

```go
func (c *IRCCore) BounceListNetworks()
func (c *IRCCore) BouncerBind(networkID string)
```

Bouncer commands: lists available networks or binds to a specific one.

### WebIRC

```go
func (c *IRCCore) WebIRC(password, gateway, hostname, ip string)
```

Sends a WEBIRC command to report the real IP through a gateway. Must be sent before PASS/NICK/USER.

### SendPass

```go
func (c *IRCCore) SendPass(password string)
```

Sends a connection password (PASS command). Normally handled automatically by Authenticate; this is for manual/advanced use.

---

## CHATHISTORY

IRCv3 CHATHISTORY draft commands. Require server support for `draft/chathistory`.

### ChatHistoryLatest

```go
func (c *IRCCore) ChatHistoryLatest(target string, limit int)
```

Requests the latest N messages for a target.

### ChatHistoryBefore

```go
func (c *IRCCore) ChatHistoryBefore(target, reference string, limit int)
```

Requests messages before a given msgid or timestamp.

### ChatHistoryAfter

```go
func (c *IRCCore) ChatHistoryAfter(target, reference string, limit int)
```

Requests messages after a given msgid or timestamp.

### ChatHistoryAround

```go
func (c *IRCCore) ChatHistoryAround(target, reference string, limit int)
```

Requests messages around a given msgid or timestamp.

### ChatHistoryBetween

```go
func (c *IRCCore) ChatHistoryBetween(target, startRef, endRef string, limit int)
```

Fetches messages between two timestamps or message IDs.

### ChatHistoryTargets

```go
func (c *IRCCore) ChatHistoryTargets(fromTime, toTime string, limit int)
```

Requests a list of targets (channels/users) with recent messages in the given time range.

---

## Metadata

IRCv3 `draft/metadata` commands.

### MetadataGet

```go
func (c *IRCCore) MetadataGet(target, key string)
```

Gets a metadata value for a target.

### MetadataSet

```go
func (c *IRCCore) MetadataSet(target, key, value string)
```

Sets a metadata value for a target.

### MetadataList

```go
func (c *IRCCore) MetadataList(target string)
```

Lists all metadata for a target.

### MetadataSub / MetadataUnsub

```go
func (c *IRCCore) MetadataSub(target, key string)
func (c *IRCCore) MetadataUnsub(target, key string)
```

Subscribes or unsubscribes from metadata change notifications.

---

## Batch & Multiline

### BatchStart / BatchEnd

```go
func (c *IRCCore) BatchStart(refTag, batchType string, params ...string)
func (c *IRCCore) BatchEnd(refTag string)
```

Starts/ends a batch processing context (IRCv3 batch).

### SendClientBatch

```go
func (c *IRCCore) SendClientBatch(batchID, batchType, target string, start bool)
```

Starts or ends a client-to-server batch.

### SendMultiline

```go
func (c *IRCCore) SendMultiline(target string, lines []string)
```

Sends a multi-line message via batch (IRCv3 `draft/multiline`). Automatically generates batch IDs and uses `draft/multiline-concat` tags.

```go
irc.SendMultiline("#channel", []string{
    "First line",
    "Second line",
    "Third line",
})
```

---

## SASL Mechanisms

### SASLScramSHA256

```go
func (c *IRCCore) SASLScramSHA256(username, password string)
```

Starts SCRAM-SHA-256 authentication. The actual SCRAM exchange happens in the message handler.

### SASLExternal

```go
func (c *IRCCore) SASLExternal()
```

Starts EXTERNAL authentication (client certificate).

### SASLECDSAChallenge

```go
func (c *IRCCore) SASLECDSAChallenge(accountName string)
```

Starts ECDSA-NIST256P-CHALLENGE authentication.

---

## Server Commands

### GetServerInfo

```go
func (c *IRCCore) GetServerInfo() IRCServerInfo
```

Returns the cached server info parsed from ISUPPORT (005) and MYINFO (004).

### List

```go
func (c *IRCCore) List(filter string) ([]IRCListEntry, error)
```

Requests the channel list. Optional filter string (e.g. `">100"` for channels with 100+ users, server-dependent).

```go
channels, err := irc.List("")
for _, ch := range channels {
    fmt.Printf("%s (%d users): %s\n", ch.Channel, ch.Users, ch.Topic)
}
```

### RequestMOTD

```go
func (c *IRCCore) RequestMOTD()
```

Requests the Message of the Day from the server.

### GetMOTD

```go
func (c *IRCCore) GetMOTD() []string
```

Returns the cached MOTD lines.

### RequestVersion

```go
func (c *IRCCore) RequestVersion()
```

Requests the server version.

### RequestTime

```go
func (c *IRCCore) RequestTime()
```

Requests the server time.

### RequestAdmin

```go
func (c *IRCCore) RequestAdmin()
```

Requests server admin information.

### RequestInfo

```go
func (c *IRCCore) RequestInfo()
```

Requests server info.

### RequestLusers

```go
func (c *IRCCore) RequestLusers()
```

Requests user/server statistics (LUSERS).

### RequestStats

```go
func (c *IRCCore) RequestStats(query string)
```

Requests server statistics (STATS). Common queries: `"l"` (connections), `"u"` (uptime), `"o"` (O-lines).

### RequestLinks

```go
func (c *IRCCore) RequestLinks(mask string)
```

Requests the list of linked servers. Optional mask to filter.

### RequestTrace

```go
func (c *IRCCore) RequestTrace(target string)
```

Traces the route to a server or user.

### RequestMap

```go
func (c *IRCCore) RequestMap()
```

Requests a visual map of the server network (non-RFC, widely supported).

### RequestHelp

```go
func (c *IRCCore) RequestHelp(topic string)
```

Requests help on a topic from the server.

### RequestRules

```go
func (c *IRCCore) RequestRules()
```

Requests the server rules (non-RFC, widely supported).

---

## MONITOR

IRCv3 MONITOR commands for server-side online/offline notifications.

### MonitorAdd

```go
func (c *IRCCore) MonitorAdd(nicks ...string)
```

Adds nicks to the MONITOR list.

### MonitorRemove

```go
func (c *IRCCore) MonitorRemove(nicks ...string)
```

Removes nicks from the MONITOR list.

### MonitorClear

```go
func (c *IRCCore) MonitorClear()
```

Clears the entire MONITOR list.

### MonitorList

```go
func (c *IRCCore) MonitorList()
```

Requests the current MONITOR list from the server.

### MonitorStatus

```go
func (c *IRCCore) MonitorStatus()
```

Requests the online/offline status of all monitored nicks.

### GetMonitored

```go
func (c *IRCCore) GetMonitored() []string
```

Returns the locally cached list of monitored nicks.

---

## WATCH

Server-side friend list (non-RFC, supported by UnrealIRCd/InspIRCd).

### WatchAdd

```go
func (c *IRCCore) WatchAdd(nicks ...string)
```

Adds nicks to the WATCH list.

### WatchRemove

```go
func (c *IRCCore) WatchRemove(nicks ...string)
```

Removes nicks from the WATCH list.

### WatchClear

```go
func (c *IRCCore) WatchClear()
```

Clears the WATCH list.

### WatchList

```go
func (c *IRCCore) WatchList()
```

Lists the WATCH list.

### WatchStatus

```go
func (c *IRCCore) WatchStatus()
```

Requests the status of watched nicks.

---

## Raw Commands

### SendRawCommand

```go
func (c *IRCCore) SendRawCommand(line string)
```

Sends a raw IRC command. Use for anything not covered by a typed method.

```go
irc.SendRawCommand("PRIVMSG #channel :raw message")
irc.SendRawCommand("MODE #channel +o alice")
```

---

## Reconnection

The IRC core has built-in auto-reconnect with exponential backoff. Enabled by default with a maximum of 10 retries.

- On connection loss, the read loop detects EOF and triggers the reconnect loop
- Exponential backoff starts at 2 seconds, doubling each attempt
- On successful reconnect, the client automatically re-joins previously joined channels
- `Logout()` disables auto-reconnect
- A reconnect update is fired via the update handler on successful reconnection

---

## Proxy & Transport

### ConnectSOCKS

```go
func (c *IRCCore) ConnectSOCKS(proxyAddr, targetAddr string) error
```

Connects to an IRC server through a SOCKS5 proxy. Performs the SOCKS5 handshake (no-auth method only).

```go
err := irc.ConnectSOCKS("127.0.0.1:1080", "irc.libera.chat:6667")
```

### ConnectHTTPProxy

```go
func (c *IRCCore) ConnectHTTPProxy(proxyAddr, targetAddr string) error
```

Connects to an IRC server through an HTTP CONNECT proxy.

```go
err := irc.ConnectHTTPProxy("proxy.example.com:3128", "irc.libera.chat:6667")
```

---

## Event Handlers

### OnInviteNotify

```go
func (c *IRCCore) OnInviteNotify(handler func(inviter, channel, target string))
```

Registers a callback for INVITE notifications (requires IRCv3 `invite-notify` capability).

```go
irc.OnInviteNotify(func(inviter, channel, target string) {
    fmt.Printf("%s invited %s to %s\n", inviter, target, channel)
})
```

---

## Formatting Helpers

Package-level functions for IRC text formatting.

```go
func FormatBold(text string) string
func FormatItalic(text string) string
func FormatUnderline(text string) string
func FormatStrikethrough(text string) string
func FormatMonospace(text string) string
func FormatColor(text string, fg, bg int) string  // bg=-1 for fg only
func FormatHexColor(text, rrggbb string) string
func FormatReset() string
func StripFormatting(text string) string
func ParseColors(text string) []map[string]interface{}
```

```go
msg := cores.FormatBold("Hello") + " " + cores.FormatColor("world", 4, -1)
clean := cores.StripFormatting(msg)
```

Also: `ParseStandardReply` parses IRCv3 FAIL/WARN/NOTE structured responses and `ParsePROXYProtocol` parses HAProxy PROXY header lines.

---

## Unsupported Core Methods

These Core interface methods return `ErrNotSupported` because IRC does not have an equivalent concept:

| Method | Reason |
|--------|--------|
| `EditMessage` | IRC has no edit (see `Redact` for IRCv3 draft) |
| `DeleteMessage` | IRC has no delete (see `Redact`) |
| `ReactToMessage` | No native reaction (see `SendReactTag` for IRCv3 draft) |
| `UploadFile` / `DownloadFile` | Use DCC/XDCC instead |
| `SendImageBase64` | No native image support |
| `StartCall` / `JoinGroupCall` / `EndCall` / `SetCallMuted` | No voice calls |
| `AcceptCall` / `DeclineCall` | No voice calls |
| `CreateTopic` | IRC channels are not forum-style |
| `GetFolders` / `CreateFolder` | No folder concept |
| `GetContacts` / `AddContact` / `DeleteContact` | No contact list (see MONITOR/WATCH) |
| `GetSessions` / `TerminateSession` | No multi-session |
| `CreatePoll` / `VotePoll` | No native polls |
| `SendSticker` | No sticker support |
| `SendLocation` | No location sharing |
| `MuteChat` / `ArchiveChat` / `MarkUnread` | No chat management metadata |
| `UnpinAllMessages` | No pin concept beyond topic |
| `EditChatTitle` | Channels cannot be renamed in standard IRC (see `RenameChannel` for IRCv3 draft) |

## Dependencies

- Standard library only (`net`, `crypto/tls`, `encoding/base64`, `encoding/json`)
- No CGo required
