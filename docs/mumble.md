# Mumble Core — API Reference

Pure Go Mumble client implementing the full binary TCP/UDP protocol (v1.2–1.5). Includes a pure Go ZeroC Ice wire protocol client for Murmur server administration. No CGo, no external dependencies.

**233 exported methods** across client protocol, voice, channel management, ACL/permissions, bans, user registration, Ice RPC admin, authenticator callbacks, and debug utilities.

## Table of Contents

- [Setup](#setup)
- [Types](#types)
- [Connection & Authentication](#connection--authentication)
- [Core Interface Methods](#core-interface-methods)
- [Channel Management](#channel-management)
- [User Management](#user-management)
- [Voice & Audio](#voice--audio)
- [ACL & Permissions](#acl--permissions)
- [Bans](#bans)
- [Registration & Identity](#registration--identity)
- [Server Info & Config](#server-info--config)
- [Plugin System](#plugin-system)
- [Channel Listeners & Links](#channel-listeners--links)
- [Voice Targeting (Whisper)](#voice-targeting-whisper)
- [Certificates & Crypto](#certificates--crypto)
- [Reconnection](#reconnection)
- [Public Server List](#public-server-list)
- [Event Handlers](#event-handlers)
- [Ice RPC Admin — Connection](#ice-rpc-admin--connection)
- [Ice RPC Admin — Meta (Multi-Server)](#ice-rpc-admin--meta-multi-server)
- [Ice RPC Admin — Server Management](#ice-rpc-admin--server-management)
- [Ice RPC Admin — Users](#ice-rpc-admin--users)
- [Ice RPC Admin — Channels](#ice-rpc-admin--channels)
- [Ice RPC Admin — ACL & Permissions](#ice-rpc-admin--acl--permissions)
- [Ice RPC Admin — Listeners](#ice-rpc-admin--listeners)
- [Ice RPC Admin — Bans](#ice-rpc-admin--bans)
- [Ice RPC Admin — Callbacks](#ice-rpc-admin--callbacks)
- [Ice RPC Admin — Authenticator](#ice-rpc-admin--authenticator)
- [Debug Utilities](#debug-utilities)
- [Unsupported Core Methods](#unsupported-core-methods)

## Setup

```go
import "uniclient/cores"

mum := &cores.MumbleCore{}
```

**Capabilities:** `TEXT`, `CHANNELS`, `VOICE`, `ADMIN`, `BLOCKING`, `SEARCH`

## Types

### MumbleServerConfig

```go
type MumbleServerConfig struct {
    MaxBandwidth       uint32
    WelcomeText        string
    AllowHTML          bool
    MessageLength      uint32
    ImageMessageLength uint32
    MaxUsers           uint32
    RecordingAllowed   bool
}
```

### MumbleACLMsg

```go
type MumbleACLMsg struct {
    ChannelID   uint32
    InheritACLs bool
    Groups      []MumbleACLGroup
    ACLs        []MumbleACLEntry
    Query       bool
}
```

### MumbleACLGroup

```go
type MumbleACLGroup struct {
    Name             string
    Inherited        bool
    Inherit          bool
    Inheritable      bool
    Add              []uint32  // user IDs to add
    Remove           []uint32  // user IDs to remove
    InheritedMembers []uint32
}
```

### MumbleACLEntry

```go
type MumbleACLEntry struct {
    ApplyHere bool
    ApplySubs bool
    Inherited bool
    UserID    uint32
    Group     string
    Grant     uint32  // permission bitmask to grant
    Deny      uint32  // permission bitmask to deny
    HasUserID bool
}
```

### MumbleBanEntry

```go
type MumbleBanEntry struct {
    Address  []byte  // IP address (IPv4 or IPv4-mapped-IPv6)
    Mask     uint32  // CIDR mask
    Name     string
    Hash     string  // certificate hash
    Reason   string
    Start    string  // RFC3339 timestamp
    Duration uint32  // seconds, 0 = permanent
}
```

### MumbleVoiceTargetEntry

```go
type MumbleVoiceTargetEntry struct {
    Sessions   []uint32  // target specific users
    ChannelID  uint32    // target a channel
    Group      string    // target a group within the channel
    Links      bool      // include linked channels
    Children   bool      // include child channels
    HasChannel bool      // set true when targeting a channel
}
```

### MumbleVoicePacket

```go
type MumbleVoicePacket struct {
    SenderSession uint32
    Codec         int     // codec identifier
    AudioData     []byte  // Opus frame data
    SequenceNum   int64
    Target        int     // 0=normal, 1-30=whisper target, 31=loopback
    IsTerminator  bool
    PositionX     float32 // 3D audio position
    PositionY     float32
    PositionZ     float32
}
```

### MumblePublicServer

```go
type MumblePublicServer struct {
    Name          string
    IP            string
    Port          int
    Country       string
    CountryCode   string
    ContinentCode string
    Region        string
    URL           string
    CA            int
}
```

### MumbleCryptState

Exported wrapper for the internal OCB2 encryption state. Used for voice channel encryption.

### Event Types

```go
type MumbleRejectEvent struct {
    Type   uint32  // rejection type code
    Reason string
}

type MumblePermissionDeniedEvent struct {
    Permission uint32
    ChannelID  uint32
    Session    uint32
    Reason     string
    Type       uint32
    Name       string
}

type MumbleSuggestConfigEvent struct {
    VersionV1  uint32
    VersionV2  uint64
    Positional bool
    PushToTalk bool
}

type MumbleContextActionEvent struct {
    Action    string
    Text      string
    Context   uint32  // bitmask: Server=1, Channel=2, User=4
    Operation uint32  // 0=Add, 1=Remove
}

type MumbleCodecVersionEvent struct {
    Alpha       int32
    Beta        int32
    PreferAlpha bool
    Opus        bool
}
```

### MumbleAuthenticator

```go
type MumbleAuthenticator struct {
    Authenticate   func(name, pw, certHash string, certStrong bool) (userID int, groups []string, err error)
    GetInfo        func(userID int) (map[int]string, error)
    NameToId       func(name string) (int, error)
    IdToName       func(userID int) (string, error)
    IdToTexture    func(userID int) ([]byte, error)
    RegisterUser   func(info map[int]string) (int, error)
    UnregisterUser func(userID int) error
    SetInfo        func(userID int, info map[int]string) error
    SetTexture     func(userID int, texture []byte) error
}
```

---

## Connection & Authentication

### Name

```go
func (c *MumbleCore) Name() string
```

Returns `"mumble"`.

### Capabilities

```go
func (c *MumbleCore) Capabilities() []string
```

Returns `["TEXT", "CHANNELS", "VOICE", "ADMIN", "BLOCKING", "SEARCH"]`.

### Authenticate

```go
func (c *MumbleCore) Authenticate(cfg AuthConfig) error
```

Connects to a Mumble server over TLS. Generates and persists a TLS client certificate for identity.

**AuthConfig fields:**
- `Extra["server"]` — server address as `host:port` (required)
- `Extra["username"]` — display name (required, falls back to `cfg.Phone`)
- `Extra["password"]` — server password (optional, falls back to `cfg.Password2F`)
- `Extra["tokens"]` — comma-separated access tokens (optional)
- `Extra["session_path"]` — certificate session file path (default: `auth/mumble_session.json`)
- `cfg.Mode` — `AuthModeBot` or `AuthModeUser`

```go
err := mum.Authenticate(cores.AuthConfig{
    Extra: map[string]string{
        "server":   "mumble.example.com:64738",
        "username": "GoBot",
        "password": "server_password",
        "tokens":   "token1,token2",
    },
})
```

### ConnectFromURL

```go
func (c *MumbleCore) ConnectFromURL(mumbleURL string) error
```

Parses a `mumble://` URL and authenticates. Extracts host, port, username, and password from the URL.

```go
err := mum.ConnectFromURL("mumble://user:pass@server.example.com:64738/channel")
```

### Logout

```go
func (c *MumbleCore) Logout() error
```

Disconnects from the server and closes the TLS connection. Does not delete session data.

### Close

```go
func (c *MumbleCore) Close() error
```

Full shutdown: closes TCP and UDP connections, waits for goroutines, saves session, sets authed=false.

### OnUpdate

```go
func (c *MumbleCore) OnUpdate(handler func(Update))
```

Registers a callback for unified updates (messages, user joins/parts, channel changes, connectivity).

```go
mum.OnUpdate(func(u cores.Update) {
    if u.Message != nil {
        fmt.Printf("[%s] %s: %s\n", u.ChatID, u.Message.SenderName, u.Message.Text)
    }
})
```

---

## Core Interface Methods

These implement the unified `Core` interface shared across all platforms.

### Messaging

#### SendMessage

```go
func (c *MumbleCore) SendMessage(chatID string, msg OutgoingMessage) (*Message, error)
```

Sends a text message. `chatID` can be a channel ID (prefixed with `c` or plain number for channels) or a user session ID (prefixed with `u`).

```go
msg, err := mum.SendMessage("c0", cores.OutgoingMessage{Text: "Hello root channel!"})
msg, err := mum.SendMessage("u5", cores.OutgoingMessage{Text: "Private message to session 5"})
```

#### GetMessages

```go
func (c *MumbleCore) GetMessages(chatID string, opts PaginationOpts) ([]Message, error)
```

Returns cached messages for a channel or user. Mumble doesn't have server-side message history — only messages received during this session are available.

#### EditMessage / DeleteMessage

```go
func (c *MumbleCore) EditMessage(chatID, msgID, text string) (*Message, error)
func (c *MumbleCore) DeleteMessage(chatID, msgID string) error
```

Not supported by Mumble protocol. Returns `ErrNotSupported`.

#### ReplyToMessage

```go
func (c *MumbleCore) ReplyToMessage(chatID, replyToMsgID string, msg OutgoingMessage) (*Message, error)
```

Not supported. Returns `ErrNotSupported`.

#### ForwardMessage

```go
func (c *MumbleCore) ForwardMessage(fromChatID, msgID, toChatID string) (*Message, error)
```

Not supported. Returns `ErrNotSupported`.

#### ReactToMessage

```go
func (c *MumbleCore) ReactToMessage(chatID, msgID, emoji string) error
```

Not supported. Returns `ErrNotSupported`.

#### PinMessage / UnpinMessage

```go
func (c *MumbleCore) PinMessage(chatID, msgID string) error
func (c *MumbleCore) UnpinMessage(chatID, msgID string) error
```

Not supported. Returns `ErrNotSupported`.

#### MarkAsRead

```go
func (c *MumbleCore) MarkAsRead(chatID, upToMsgID string) error
```

Marks messages as read in the local cache.

#### GetReadState

```go
func (c *MumbleCore) GetReadState(chatID string) (*ReadState, error)
```

Returns the local read state for a channel/user.

#### SendImageBase64

```go
func (c *MumbleCore) SendImageBase64(chatID, b64, caption string) (*Message, error)
```

Sends a base64-encoded image as an HTML `<img>` tag embedded in a text message (requires AllowHTML on server).

#### SendTyping

```go
func (c *MumbleCore) SendTyping(chatID string) error
```

Not supported. Returns `ErrNotSupported`.

### File Transfer

#### UploadFile / DownloadFile

```go
func (c *MumbleCore) UploadFile(chatID string, file FileUpload, progress func(sent, total int64)) (*Message, error)
func (c *MumbleCore) DownloadFile(fileRef FileRef, dest string, progress func(recv, total int64)) error
```

Not supported. Returns `ErrNotSupported`.

### Dialogs & Chat Info

#### GetDialogs

```go
func (c *MumbleCore) GetDialogs(opts PaginationOpts) ([]Dialog, error)
```

Returns a list of all channels and connected users as dialogs. Channels are returned with their hierarchy intact.

#### GetChatInfo

```go
func (c *MumbleCore) GetChatInfo(chatID string) (*Dialog, error)
```

Returns info for a specific channel or user.

#### EditChatTitle

```go
func (c *MumbleCore) EditChatTitle(chatID, title string) error
```

Renames a channel. Requires `Write` permission on the channel.

#### EditChatDescription

```go
func (c *MumbleCore) EditChatDescription(chatID, description string) error
```

Sets a channel's description. Requires `Write` permission.

#### LeaveChat

```go
func (c *MumbleCore) LeaveChat(chatID string) error
```

Moves you out of the specified channel to the root channel.

#### GetInviteLink

```go
func (c *MumbleCore) GetInviteLink(chatID string) (string, error)
```

Not supported. Returns `ErrNotSupported`.

### Groups & Channels (Core Interface)

#### CreateGroup

```go
func (c *MumbleCore) CreateGroup(name string, members []string) (*Dialog, error)
```

Creates a new permanent channel (Mumble has no "groups" — maps to channel creation).

#### CreateChannel

```go
func (c *MumbleCore) CreateChannel(name string, description string) (*Dialog, error)
```

Creates a new permanent channel with a description. Waits for the server's ChannelState response to return the new channel ID.

```go
dialog, err := mum.CreateChannel("Lobby", "A place to hang out")
fmt.Println(dialog.ID) // channel ID
```

#### CreateTopic

```go
func (c *MumbleCore) CreateTopic(chatID string, name string) (*Dialog, error)
```

Creates a sub-channel under `chatID`.

### Members

#### AddMembers

```go
func (c *MumbleCore) AddMembers(chatID string, userIDs []string) error
```

Moves users into a channel by session ID.

#### RemoveMember

```go
func (c *MumbleCore) RemoveMember(chatID, userID string) error
```

Kicks a user from the server with reason "Removed".

#### BanMember

```go
func (c *MumbleCore) BanMember(chatID, userID string) error
```

Bans a user by their certificate hash and kicks them.

#### UnbanMember

```go
func (c *MumbleCore) UnbanMember(chatID, userID string) error
```

Removes a ban matching the user's certificate hash.

#### GetMembers

```go
func (c *MumbleCore) GetMembers(chatID string, opts PaginationOpts) ([]User, error)
```

Returns users in a channel. Supports `Offset` and `Limit` pagination.

#### SetAdmin

```go
func (c *MumbleCore) SetAdmin(chatID, userID string, admin bool) error
```

Not directly supported (Mumble uses ACLs). Returns `ErrNotSupported`.

### Contacts & Blocking

#### GetContacts

```go
func (c *MumbleCore) GetContacts() ([]User, error)
```

Returns all connected users on the server.

#### AddContact / DeleteContact

```go
func (c *MumbleCore) AddContact(phone, firstName, lastName string) error
func (c *MumbleCore) DeleteContact(userID string) error
```

Not supported. Returns `ErrNotSupported`.

#### BlockUser

```go
func (c *MumbleCore) BlockUser(userID string) error
```

Server-deafens the user (prevents them from hearing or speaking). Requires admin permissions.

#### UnblockUser

```go
func (c *MumbleCore) UnblockUser(userID string) error
```

Removes server-deafen from the user.

#### GetBlockedUsers

```go
func (c *MumbleCore) GetBlockedUsers() ([]User, error)
```

Returns all server-deafened users.

### Profiles

#### GetProfile

```go
func (c *MumbleCore) GetProfile(userID string) (*User, error)
```

Returns profile info for a user by session ID. Includes name, channel, mute/deaf state, comment, and hash.

### Search

#### SearchMessages

```go
func (c *MumbleCore) SearchMessages(chatID, query string, opts PaginationOpts) ([]Message, error)
```

Searches cached messages for a channel/user by substring match.

#### SearchGlobal

```go
func (c *MumbleCore) SearchGlobal(query string, opts PaginationOpts) ([]Dialog, error)
```

Searches all channels and users by name.

### Sessions

#### GetSessions

```go
func (c *MumbleCore) GetSessions() ([]Session, error)
```

Returns all connected user sessions on the server.

#### TerminateSession

```go
func (c *MumbleCore) TerminateSession(sessionID string) error
```

Kicks a user by session ID.

### Calls

#### StartCall

```go
func (c *MumbleCore) StartCall(chatID string, video bool) (*CallSession, error)
```

"Starts a call" by joining a channel (Mumble is always voice). Returns a `CallSession` with the channel as the call ID. Video is not supported.

#### JoinGroupCall

```go
func (c *MumbleCore) JoinGroupCall(chatID string) (*CallSession, error)
```

Joins a channel for voice. Same as `StartCall`.

#### EndCall

```go
func (c *MumbleCore) EndCall(callID string) error
```

Self-deafens and self-mutes (leaves the voice session without disconnecting).

#### SetCallMuted

```go
func (c *MumbleCore) SetCallMuted(callID string, muted bool) error
```

Self-mutes or unmutes.

### Polls & Stickers

#### CreatePoll / VotePoll / SendSticker

```go
func (c *MumbleCore) CreatePoll(chatID, question string, options []string) (*Message, error)
func (c *MumbleCore) VotePoll(chatID, msgID string, optionIndex int) error
func (c *MumbleCore) SendSticker(chatID, stickerID string) (*Message, error)
```

Not supported. Return `ErrNotSupported`.

### Folders

#### GetFolders / CreateFolder

```go
func (c *MumbleCore) GetFolders() ([]Folder, error)
func (c *MumbleCore) CreateFolder(name string, chatIDs []string) (*Folder, error)
```

Not supported. Return `ErrNotSupported`.

---

## Channel Management

### MoveToChannel

```go
func (c *MumbleCore) MoveToChannel(channelID uint32) error
```

Moves yourself to a channel.

```go
err := mum.MoveToChannel(5) // move to channel ID 5
```

### MoveUser

```go
func (c *MumbleCore) MoveUser(session, channelID uint32) error
```

Moves another user to a channel. Requires `Move` permission.

### CreateTemporaryChannel

```go
func (c *MumbleCore) CreateTemporaryChannel(name string, parent uint32) error
```

Creates a temporary channel under a parent. Temporary channels are deleted when the last user leaves.

### DeleteChannel

```go
func (c *MumbleCore) DeleteChannel(channelID uint32) error
```

Permanently deletes a channel. Requires admin permissions.

### RenameChannel

```go
func (c *MumbleCore) RenameChannel(channelID uint32, newName string) error
```

Renames a channel.

### SetChannelMaxUsers

```go
func (c *MumbleCore) SetChannelMaxUsers(channelID, maxUsers uint32) error
```

Sets the maximum number of users for a channel.

### SetChannelPosition

```go
func (c *MumbleCore) SetChannelPosition(channelID uint32, position int32) error
```

Sets the display position of a channel in the tree.

### MoveChannel

```go
func (c *MumbleCore) MoveChannel(channelID, newParent uint32) error
```

Moves a channel under a new parent.

### GetChannelDescription

```go
func (c *MumbleCore) GetChannelDescription(channelID uint32) (string, error)
```

Returns the description of a channel. If not cached, requests the blob from the server and waits for it.

### GetChannelTree

```go
func (c *MumbleCore) GetChannelTree() map[string]interface{}
```

Returns the full channel tree as a nested map structure with `id`, `name`, `parent`, `description`, `position`, `max_users`, and `children` fields.

```go
tree := mum.GetChannelTree()
// tree["name"] = "Root"
// tree["children"] = []{...}
```

### SendTreeMessage

```go
func (c *MumbleCore) SendTreeMessage(channelID uint32, message string) error
```

Sends a text message to a channel and all its sub-channels.

---

## User Management

### ServerMute

```go
func (c *MumbleCore) ServerMute(session uint32, muted bool) error
```

Server-mutes or unmutes a user. Requires admin permissions.

### ServerDeaf

```go
func (c *MumbleCore) ServerDeaf(session uint32, deafed bool) error
```

Server-deafens or undeafens a user.

### SelfMute

```go
func (c *MumbleCore) SelfMute(muted bool) error
```

Mutes or unmutes yourself.

### SelfDeaf

```go
func (c *MumbleCore) SelfDeaf(deafed bool) error
```

Deafens or undeafens yourself.

### Suppress

```go
func (c *MumbleCore) Suppress(session uint32, suppressed bool) error
```

Suppresses or unsuppresses a user's voice transmission.

### SetComment

```go
func (c *MumbleCore) SetComment(comment string) error
```

Sets your user comment (visible to others).

### SetTexture

```go
func (c *MumbleCore) SetTexture(imageData []byte) error
```

Sets your user avatar/texture (PNG or JPEG image data).

### SetPrioritySpeaker

```go
func (c *MumbleCore) SetPrioritySpeaker(session uint32, enabled bool) error
```

Grants or revokes priority speaker status. Priority speakers are not attenuated by other speakers.

### SetRecording

```go
func (c *MumbleCore) SetRecording(recording bool) error
```

Notifies the server that you are recording. All users in the channel will see a recording indicator.

### GetUserComment

```go
func (c *MumbleCore) GetUserComment(session uint32) (string, error)
```

Returns a user's comment. Requests the blob from the server if not cached.

### GetUserTexture

```go
func (c *MumbleCore) GetUserTexture(session uint32) ([]byte, error)
```

Returns a user's avatar/texture data. Requests the blob from the server if not cached.

---

## Voice & Audio

### SendVoice

```go
func (c *MumbleCore) SendVoice(opusData []byte, target int) error
```

Sends an Opus-encoded voice frame over UDP. `target` is 0 for normal speech, 1–30 for whisper targets (see [Voice Targeting](#voice-targeting-whisper)), or 31 for server loopback.

```go
// Send an Opus frame to the current channel
err := mum.SendVoice(opusFrame, 0)
```

### SendVoiceTCP

```go
func (c *MumbleCore) SendVoiceTCP(opusData []byte, target int) error
```

Same as `SendVoice` but tunnels through TCP. Use this when UDP is unavailable or blocked.

### SendVoiceTerminator

```go
func (c *MumbleCore) SendVoiceTerminator() error
```

Sends a voice terminator packet to signal end of speech. Other clients use this to reset their audio decoders.

### SendPositionalAudio

```go
func (c *MumbleCore) SendPositionalAudio(opusData []byte, target int, x, y, z float32) error
```

Sends an Opus frame with 3D positional audio data. Used by games to spatialize voice based on player location.

```go
err := mum.SendPositionalAudio(opusFrame, 0, 10.5, 0.0, -3.2)
```

### ServerLoopback

```go
func (c *MumbleCore) ServerLoopback(opusData []byte) error
```

Sends voice data to yourself via the server (target 31). Useful for testing audio quality.

### OnVoice

```go
func (c *MumbleCore) OnVoice(handler func(MumbleVoicePacket))
```

Registers a callback for incoming voice packets. Called for every Opus frame received from any user.

```go
mum.OnVoice(func(pkt cores.MumbleVoicePacket) {
    fmt.Printf("Audio from session %d: %d bytes, seq=%d\n",
        pkt.SenderSession, len(pkt.AudioData), pkt.SequenceNum)
})
```

### OnAudioStream

```go
func (c *MumbleCore) OnAudioStream(handler func(session uint32, pcm []int16, codec string))
```

Registers a callback for decoded audio streams. Provides PCM samples after Opus decoding.

### SetAudioBitrate

```go
func (c *MumbleCore) SetAudioBitrate(bitrate int)
```

Sets the Opus encoder bitrate in bits/second. Default varies by server config.

### SetAudioFrameSize

```go
func (c *MumbleCore) SetAudioFrameSize(ms int)
```

Sets the Opus frame size in milliseconds (10, 20, 40, or 60).

### GetAudioStats

```go
func (c *MumbleCore) GetAudioStats() map[string]interface{}
```

Returns audio statistics: `udp_sent`, `udp_recv`, `tcp_voice_sent`, `tcp_voice_recv`, `sequence_num`, `voice_target`.

### SetPreferredCodec

```go
func (c *MumbleCore) SetPreferredCodec(opus bool)
```

Sets whether to prefer Opus (true) or CELT (false) for codec negotiation.

---

## ACL & Permissions

### GetACL

```go
func (c *MumbleCore) GetACL(channelID uint32) (*MumbleACLMsg, error)
```

Queries the ACL for a channel. Returns the full ACL including inherited groups and rules.

```go
acl, err := mum.GetACL(0) // root channel
for _, group := range acl.Groups {
    fmt.Printf("Group %s: inherit=%v\n", group.Name, group.Inherit)
}
for _, entry := range acl.ACLs {
    fmt.Printf("ACL: group=%s grant=%d deny=%d\n", entry.Group, entry.Grant, entry.Deny)
}
```

### SetACL

```go
func (c *MumbleCore) SetACL(channelID uint32, groups []MumbleACLGroup, acls []MumbleACLEntry, inheritACLs bool) error
```

Sets the full ACL for a channel. Replaces all non-inherited groups and ACL entries.

```go
err := mum.SetACL(5, []cores.MumbleACLGroup{
    {Name: "moderators", Inherit: true, Inheritable: true, Add: []uint32{1001}},
}, []cores.MumbleACLEntry{
    {ApplyHere: true, ApplySubs: true, Group: "moderators", Grant: 0x10}, // Speak
}, true)
```

### GetPermissions

```go
func (c *MumbleCore) GetPermissions(channelID uint32) (uint32, error)
```

Queries your effective permissions for a channel. Returns a permission bitmask.

### FlushPermissions

```go
func (c *MumbleCore) FlushPermissions(channelID uint32) error
```

Flushes cached permissions for a channel and re-queries from the server.

### GetCachedPermissions

```go
func (c *MumbleCore) GetCachedPermissions(channelID uint32) uint32
```

Returns locally cached permissions for a channel without a server round-trip.

---

## Bans

### GetBanList

```go
func (c *MumbleCore) GetBanList() ([]MumbleBanEntry, error)
```

Returns the server's ban list. Requires admin permissions.

### SetBanList

```go
func (c *MumbleCore) SetBanList(bans []MumbleBanEntry) error
```

Replaces the entire server ban list.

### AddBan

```go
func (c *MumbleCore) AddBan(address []byte, mask uint32, name, hash, reason string, duration uint32) error
```

Adds a ban to the server. `address` is the IP (normalizes IPv4 to IPv4-mapped-IPv6). `duration` is in seconds (0 = permanent).

```go
ip := net.ParseIP("192.168.1.100")
err := mum.AddBan(ip, 32, "spammer", "", "Spamming", 3600) // 1 hour ban
```

### RemoveBan

```go
func (c *MumbleCore) RemoveBan(address []byte, mask uint32) error
```

Removes a ban matching the address and mask.

---

## Registration & Identity

### RegisterSelf

```go
func (c *MumbleCore) RegisterSelf() error
```

Registers your username with the server using your certificate. After registration, the name is reserved for your certificate.

### RegisterUser

```go
func (c *MumbleCore) RegisterUser(session uint32) error
```

Registers another user by their session ID. Requires admin permissions.

### GetRegisteredUsers

```go
func (c *MumbleCore) GetRegisteredUsers() error
```

Requests the server to send the list of registered users. Results arrive via the update handler.

### UnregisterUser

```go
func (c *MumbleCore) UnregisterUser(userID uint32) error
```

Removes a user's registration.

### QueryUsers

```go
func (c *MumbleCore) QueryUsers(ids []uint32, names []string) error
```

Queries the mapping between user IDs and names. Results arrive via the update handler.

---

## Server Info & Config

### GetServerConfig

```go
func (c *MumbleCore) GetServerConfig() MumbleServerConfig
```

Returns the cached server configuration received during handshake.

```go
cfg := mum.GetServerConfig()
fmt.Printf("Max bandwidth: %d, Max users: %d\n", cfg.MaxBandwidth, cfg.MaxUsers)
```

### SendVersion

```go
func (c *MumbleCore) SendVersion() error
```

Sends a version message to the server. Normally sent automatically during handshake.

---

## Plugin System

### SetPluginContext

```go
func (c *MumbleCore) SetPluginContext(ctx []byte) error
```

Sets the plugin context data. Used by positional audio plugins to identify the game/context.

### SetPluginIdentity

```go
func (c *MumbleCore) SetPluginIdentity(identity string) error
```

Sets the plugin identity string. Used by positional audio plugins to identify the player.

### SendPluginData

```go
func (c *MumbleCore) SendPluginData(receivers []uint32, dataID string, data []byte) error
```

Sends arbitrary plugin data to specific users.

```go
err := mum.SendPluginData([]uint32{5, 6}, "game_pos", positionBytes)
```

### TriggerContextAction

```go
func (c *MumbleCore) TriggerContextAction(action string, session, channelID uint32) error
```

Triggers a registered context action on a user or channel.

### AddContextCallback

```go
func (c *MumbleCore) AddContextCallback(action, text string, ctx uint32) error
```

Registers a context action. `ctx` is a bitmask: Server=1, Channel=2, User=4.

```go
err := mum.AddContextCallback("kick_vote", "Vote to Kick", 4) // user context
```

### RemoveContextCallback

```go
func (c *MumbleCore) RemoveContextCallback(action string) error
```

Removes a registered context action.

---

## Channel Listeners & Links

### LinkChannels

```go
func (c *MumbleCore) LinkChannels(channelID uint32, linkIDs []uint32) error
```

Links channels together. Linked channels share voice — users in any linked channel hear each other.

### UnlinkChannels

```go
func (c *MumbleCore) UnlinkChannels(channelID uint32, unlinkIDs []uint32) error
```

Unlinks channels.

### AddChannelListener

```go
func (c *MumbleCore) AddChannelListener(channelIDs []uint32) error
```

Starts listening to channels without joining them. You hear voice from those channels.

### RemoveChannelListener

```go
func (c *MumbleCore) RemoveChannelListener(channelIDs []uint32) error
```

Stops listening to channels.

### SetListenerVolume

```go
func (c *MumbleCore) SetListenerVolume(channelID uint32, volume float32) error
```

Sets the volume adjustment for a listened channel. 1.0 = normal, 0.0 = muted.

---

## Voice Targeting (Whisper)

### SetVoiceTarget

```go
func (c *MumbleCore) SetVoiceTarget(id uint32, targets []MumbleVoiceTargetEntry) error
```

Configures a voice target for whisper. Target IDs 1–30 can be used with `SendVoice`.

```go
// Whisper to specific users
err := mum.SetVoiceTarget(1, []cores.MumbleVoiceTargetEntry{
    {Sessions: []uint32{5, 6, 7}},
})
mum.SendVoice(opusFrame, 1) // whisper using target 1

// Whisper to a channel and its children
err := mum.SetVoiceTarget(2, []cores.MumbleVoiceTargetEntry{
    {ChannelID: 3, HasChannel: true, Children: true, Links: true},
})
```

---

## Certificates & Crypto

### LoadCertificate

```go
func (c *MumbleCore) LoadCertificate(certFile, keyFile string) error
```

Loads a TLS client certificate from PEM files. Must be called before `Authenticate`.

```go
err := mum.LoadCertificate("my_cert.pem", "my_key.pem")
```

### GetCertificateHash

```go
func (c *MumbleCore) GetCertificateHash() string
```

Returns the SHA-256 hash of your client certificate.

### GetServerCertificate

```go
func (c *MumbleCore) GetServerCertificate() (*x509.Certificate, error)
```

Returns the server's TLS certificate.

### RequestNonceResync

```go
func (c *MumbleCore) RequestNonceResync() error
```

Requests a nonce resync for the UDP encryption. Use this if voice packets are failing to decrypt.

### RequestBlob

```go
func (c *MumbleCore) RequestBlob(textures, comments, descriptions []uint32) error
```

Requests blob data (textures, comments, descriptions) for users/channels by ID. Results arrive asynchronously.

### SetAccessTokens

```go
func (c *MumbleCore) SetAccessTokens(tokens []string) error
```

Sets access tokens for the current session. Tokens grant access to restricted channels.

### SetTemporaryAccessTokens

```go
func (c *MumbleCore) SetTemporaryAccessTokens(tokens []string) error
```

Same as `SetAccessTokens` — sends token list to the server.

---

## Reconnection

### Reconnect

```go
func (c *MumbleCore) Reconnect() error
```

Manually reconnects to the server using the last connection parameters.

### SetAutoReconnect

```go
func (c *MumbleCore) SetAutoReconnect(enabled bool, delay time.Duration)
```

Enables or disables automatic reconnection with the specified delay between attempts.

```go
mum.SetAutoReconnect(true, 5*time.Second)
```

---

## Public Server List

### GetPublicServers

```go
func (c *MumbleCore) GetPublicServers() ([]MumblePublicServer, error)
```

Fetches the Mumble public server list from `publist.mumble.info`. Does not require an active connection.

```go
servers, err := mum.GetPublicServers()
for _, s := range servers {
    fmt.Printf("%s (%s:%d) - %s\n", s.Name, s.IP, s.Port, s.Country)
}
```

---

## Event Handlers

### HandleReject

```go
func (c *MumbleCore) HandleReject(handler func(MumbleRejectEvent))
```

Fires when the server rejects the connection (wrong password, banned, server full, etc.).

### HandlePermissionDenied

```go
func (c *MumbleCore) HandlePermissionDenied(handler func(MumblePermissionDeniedEvent))
```

Fires when an operation is denied due to insufficient permissions.

### HandleSuggestConfig

```go
func (c *MumbleCore) HandleSuggestConfig(handler func(MumbleSuggestConfigEvent))
```

Fires when the server suggests client configuration (e.g., enable positional audio, use push-to-talk).

### HandleCodecVersion

```go
func (c *MumbleCore) HandleCodecVersion(handler func(MumbleCodecVersionEvent))
```

Fires when the server negotiates codec versions.

### HandleContextActionModify

```go
func (c *MumbleCore) HandleContextActionModify(handler func(MumbleContextActionEvent))
```

Fires when a context action is added or removed by another client/plugin.

### HandleUserStats

```go
func (c *MumbleCore) HandleUserStats(handler func(session uint32, stats map[string]interface{}))
```

Fires when user statistics are received (in response to `GetUserStats`).

### GetUserStats

```go
func (c *MumbleCore) GetUserStats(session uint32) error
```

Requests detailed statistics for a user. Results arrive via `HandleUserStats`.

---

## Ice RPC Admin — Connection

The Ice RPC interface lets you administrate a Murmur server remotely using the ZeroC Ice protocol. This is a pure Go implementation — no Ice libraries or CGo needed.

### ConnectAdmin

```go
func (c *MumbleCore) ConnectAdmin(addr, secret string, serverID int) error
```

Connects to Murmur's Ice interface.

- `addr` — Ice endpoint address (e.g., `"localhost:6502"`)
- `secret` — Ice secret (from murmur.ini `icesecretwrite`)
- `serverID` — virtual server ID (usually 1)

```go
err := mum.ConnectAdmin("localhost:6502", "my_ice_secret", 1)
```

### DisconnectAdmin

```go
func (c *MumbleCore) DisconnectAdmin()
```

Closes the Ice RPC connection.

### OnIceContextAction

```go
func (c *MumbleCore) OnIceContextAction(handler func(action string, session uint32, channelID int32))
```

Registers a callback for Ice context action events.

---

## Ice RPC Admin — Meta (Multi-Server)

Meta operations manage virtual servers on the Murmur instance.

### MetaGetServer

```go
func (c *MumbleCore) MetaGetServer(serverID int) (string, error)
```

Gets the proxy identity string for a virtual server.

### MetaNewServer

```go
func (c *MumbleCore) MetaNewServer() (int, error)
```

Creates a new virtual server. Returns the new server ID.

### MetaGetBootedServers

```go
func (c *MumbleCore) MetaGetBootedServers() ([]int, error)
```

Returns IDs of all running virtual servers.

### MetaGetAllServers

```go
func (c *MumbleCore) MetaGetAllServers() ([]int, error)
```

Returns IDs of all virtual servers (running or stopped).

### MetaGetDefaultConf

```go
func (c *MumbleCore) MetaGetDefaultConf() (map[string]string, error)
```

Returns the default configuration for new virtual servers.

### MetaGetVersion

```go
func (c *MumbleCore) MetaGetVersion() (string, error)
```

Returns the Murmur server version string.

### MetaAddCallback

```go
func (c *MumbleCore) MetaAddCallback(handler func(serverID int, started bool)) error
```

Registers a callback for virtual server start/stop events.

### MetaRemoveCallback

```go
func (c *MumbleCore) MetaRemoveCallback()
```

Removes the meta callback.

### MetaGetUptime

```go
func (c *MumbleCore) MetaGetUptime() (time.Duration, error)
```

Returns the uptime of the Murmur instance.

### MetaGetSlice

```go
func (c *MumbleCore) MetaGetSlice() (string, error)
```

Returns the compiled Slice definition from the server.

### MetaGetSliceChecksums

```go
func (c *MumbleCore) MetaGetSliceChecksums() (map[string]string, error)
```

Returns checksums for the Slice definitions.

---

## Ice RPC Admin — Server Management

### IceServerIsRunning

```go
func (c *MumbleCore) IceServerIsRunning() (bool, error)
```

Checks if the virtual server is running.

### IceServerStart / IceServerStop

```go
func (c *MumbleCore) IceServerStart() error
func (c *MumbleCore) IceServerStop() error
```

Starts or stops the virtual server.

### IceServerDelete

```go
func (c *MumbleCore) IceServerDelete() error
```

Permanently deletes the virtual server.

### IceServerID

```go
func (c *MumbleCore) IceServerID() (int, error)
```

Returns the virtual server's ID.

### IceGetConf

```go
func (c *MumbleCore) IceGetConf(key string) (string, error)
```

Gets a server configuration value by key.

```go
welcome, err := mum.IceGetConf("welcometext")
```

### IceGetAllConf

```go
func (c *MumbleCore) IceGetAllConf() (map[string]string, error)
```

Returns all server configuration key-value pairs.

### IceSetSuperuserPassword

```go
func (c *MumbleCore) IceSetSuperuserPassword(pw string) error
```

Sets the SuperUser password for the virtual server.

### IceGetLogLen

```go
func (c *MumbleCore) IceGetLogLen() (int, error)
```

Returns the number of log entries.

### GetServerLog

```go
func (c *MumbleCore) GetServerLog() ([]string, error)
```

Returns the server log entries.

### GetServerUptime

```go
func (c *MumbleCore) GetServerUptime() (time.Duration, error)
```

Returns the virtual server's uptime.

### UpdateCertificate

```go
func (c *MumbleCore) UpdateCertificate(certPEM, keyPEM string) error
```

Updates the server's TLS certificate via Ice.

### SendWelcomeMessage

```go
func (c *MumbleCore) SendWelcomeMessage(text string) error
```

Sends the server's welcome message to all connected users.

### RedirectWhisperGroup

```go
func (c *MumbleCore) RedirectWhisperGroup(source, target string) error
```

Redirects whispers from one group to another.

---

## Ice RPC Admin — Users

### IceGetUsers

```go
func (c *MumbleCore) IceGetUsers() (map[int]map[string]string, error)
```

Returns all connected users with their properties (session → property map).

### IceGetState

```go
func (c *MumbleCore) IceGetState(session int) (map[string]string, error)
```

Returns the state of a specific user session.

### IceSetState

```go
func (c *MumbleCore) IceSetState(session int, fields map[string]string) error
```

Sets fields on a user's state (e.g., move to channel, mute, deaf).

### IceKickUser

```go
func (c *MumbleCore) IceKickUser(session int, reason string) error
```

Kicks a user from the server with a reason.

```go
err := mum.IceKickUser(5, "Disruptive behavior")
```

### IceSendMessage

```go
func (c *MumbleCore) IceSendMessage(session int, text string) error
```

Sends a text message to a user via Ice.

### IceHasPermission

```go
func (c *MumbleCore) IceHasPermission(session, channelID int, perm int) (bool, error)
```

Checks if a user has a specific permission in a channel.

### IceEffectivePermissions

```go
func (c *MumbleCore) IceEffectivePermissions(session, channelID int) (int, error)
```

Returns the effective permission bitmask for a user in a channel.

### IceGetCertificateList

```go
func (c *MumbleCore) IceGetCertificateList(session int) ([][]byte, error)
```

Returns the DER-encoded certificates for a user session.

### IceGetUserNames

```go
func (c *MumbleCore) IceGetUserNames(ids []int) (map[int]string, error)
```

Maps registered user IDs to names.

### IceGetUserIds

```go
func (c *MumbleCore) IceGetUserIds(names []string) (map[string]int, error)
```

Maps usernames to registered user IDs.

### IceRegisterUser

```go
func (c *MumbleCore) IceRegisterUser(info map[int]string) (int, error)
```

Registers a new user. `info` maps field IDs to values (0=name, 1=email, 2=comment, 3=hash, 4=password, 5=last_active).

```go
id, err := mum.IceRegisterUser(map[int]string{
    0: "NewUser",
    4: "password123",
})
```

### IceUnregisterUser

```go
func (c *MumbleCore) IceUnregisterUser(userID int) error
```

Unregisters a user by ID.

### IceUpdateRegistration

```go
func (c *MumbleCore) IceUpdateRegistration(userID int, info map[int]string) error
```

Updates a registered user's info fields.

### IceGetRegistration

```go
func (c *MumbleCore) IceGetRegistration(userID int) (map[int]string, error)
```

Returns a registered user's info fields.

### IceVerifyPassword

```go
func (c *MumbleCore) IceVerifyPassword(name, pw string) (int, error)
```

Verifies a username/password combination. Returns the user ID if valid, -1 if not.

### IceGetTexture

```go
func (c *MumbleCore) IceGetTexture(userID int) ([]byte, error)
```

Returns a registered user's texture (avatar) via Ice.

### IceSetTexture

```go
func (c *MumbleCore) IceSetTexture(userID int, texture []byte) error
```

Sets a registered user's texture via Ice.

### IceSendWelcomeMessage

```go
func (c *MumbleCore) IceSendWelcomeMessage(userIDs []int) error
```

Sends the welcome message to specific users via Ice.

---

## Ice RPC Admin — Channels

### IceGetChannels

```go
func (c *MumbleCore) IceGetChannels() (map[int]map[string]string, error)
```

Returns all channels with their properties (channel ID → property map).

### IceGetChannelState

```go
func (c *MumbleCore) IceGetChannelState(channelID int) (map[string]string, error)
```

Returns the state of a specific channel.

### IceSetChannelState

```go
func (c *MumbleCore) IceSetChannelState(channelID int, fields map[string]string) error
```

Sets fields on a channel's state.

### IceRemoveChannel

```go
func (c *MumbleCore) IceRemoveChannel(channelID int) error
```

Removes a channel via Ice.

### IceAddChannel

```go
func (c *MumbleCore) IceAddChannel(name string, parent int) (int, error)
```

Creates a channel via Ice. Returns the new channel ID.

```go
id, err := mum.IceAddChannel("New Room", 0) // under root
```

### IceSendMessageChannel

```go
func (c *MumbleCore) IceSendMessageChannel(channelID int, tree bool, text string) error
```

Sends a text message to a channel via Ice. If `tree` is true, the message is sent to the channel and all sub-channels.

### IceGetTree

```go
func (c *MumbleCore) IceGetTree() (map[string]interface{}, error)
```

Returns the full channel tree via Ice.

---

## Ice RPC Admin — ACL & Permissions

### IceGetACL

```go
func (c *MumbleCore) IceGetACL(channelID int) (map[string]interface{}, error)
```

Returns the ACL for a channel via Ice.

### IceSetACL

```go
func (c *MumbleCore) IceSetACL(channelID int, aclData []byte, inherit bool) error
```

Sets the ACL for a channel via Ice. `aclData` is the serialized ACL.

### IceAddUserToGroup

```go
func (c *MumbleCore) IceAddUserToGroup(channelID, session int, group string) error
```

Adds a user to a group in a channel's ACL.

### IceRemoveUserFromGroup

```go
func (c *MumbleCore) IceRemoveUserFromGroup(channelID, session int, group string) error
```

Removes a user from a group in a channel's ACL.

---

## Ice RPC Admin — Listeners

### IceStartListening

```go
func (c *MumbleCore) IceStartListening(session, channelID int) error
```

Makes a user start listening to a channel via Ice.

### IceStopListening

```go
func (c *MumbleCore) IceStopListening(session, channelID int) error
```

Stops a user from listening to a channel.

### IceIsListening

```go
func (c *MumbleCore) IceIsListening(session, channelID int) (bool, error)
```

Checks if a user is listening to a channel.

### IceGetListeningChannels

```go
func (c *MumbleCore) IceGetListeningChannels(session int) ([]int, error)
```

Returns the channels a user is listening to.

### IceGetListeningUsers

```go
func (c *MumbleCore) IceGetListeningUsers(channelID int) ([]int, error)
```

Returns the users listening to a channel.

---

## Ice RPC Admin — Bans

### IceGetBans

```go
func (c *MumbleCore) IceGetBans() ([]map[string]string, error)
```

Returns the ban list via Ice.

### IceSetBans

```go
func (c *MumbleCore) IceSetBans(bans []map[string]string) error
```

Replaces the ban list via Ice.

---

## Ice RPC Admin — Callbacks

### IceServerCallbackUserConnected

```go
func (c *MumbleCore) IceServerCallbackUserConnected(handler func(state map[string]string))
```

Fires when a user connects to the server.

### IceServerCallbackUserDisconnected

```go
func (c *MumbleCore) IceServerCallbackUserDisconnected(handler func(state map[string]string))
```

Fires when a user disconnects.

### IceServerCallbackUserStateChanged

```go
func (c *MumbleCore) IceServerCallbackUserStateChanged(handler func(state map[string]string))
```

Fires when a user's state changes (channel move, mute, deaf, etc.).

### IceServerCallbackUserTextMessage

```go
func (c *MumbleCore) IceServerCallbackUserTextMessage(handler func(state map[string]string))
```

Fires when a user sends a text message.

### IceServerCallbackChannelCreated

```go
func (c *MumbleCore) IceServerCallbackChannelCreated(handler func(state map[string]string))
```

Fires when a channel is created.

### IceServerCallbackChannelRemoved

```go
func (c *MumbleCore) IceServerCallbackChannelRemoved(handler func(state map[string]string))
```

Fires when a channel is deleted.

### IceServerCallbackChannelStateChanged

```go
func (c *MumbleCore) IceServerCallbackChannelStateChanged(handler func(state map[string]string))
```

Fires when a channel's state changes.

### IceMetaCallbackStarted

```go
func (c *MumbleCore) IceMetaCallbackStarted(handler func(serverID int))
```

Fires when a virtual server starts.

### IceMetaCallbackStopped

```go
func (c *MumbleCore) IceMetaCallbackStopped(handler func(serverID int))
```

Fires when a virtual server stops.

---

## Ice RPC Admin — Authenticator

The authenticator system lets you implement custom authentication for Murmur. When set, Murmur will call your functions to validate users instead of its built-in database.

### IceSetAuthenticator

```go
func (c *MumbleCore) IceSetAuthenticator(auth *MumbleAuthenticator)
```

Registers a custom authenticator.

```go
mum.IceSetAuthenticator(&cores.MumbleAuthenticator{
    Authenticate: func(name, pw, certHash string, certStrong bool) (int, []string, error) {
        if name == "admin" && pw == "secret" {
            return 1, []string{"admin", "moderator"}, nil
        }
        return -1, nil, fmt.Errorf("auth failed")
    },
    GetInfo: func(userID int) (map[int]string, error) {
        return map[int]string{0: "admin"}, nil
    },
    // ... implement other callbacks as needed
})
```

### AuthenticatorAuthenticate

```go
func (c *MumbleCore) AuthenticatorAuthenticate(name, pw, certHash string, certStrong bool) (int, []string, error)
```

Dispatches to the registered authenticator's Authenticate function.

### AuthenticatorGetInfo

```go
func (c *MumbleCore) AuthenticatorGetInfo(userID int) (map[int]string, error)
```

Dispatches to GetInfo.

### AuthenticatorNameToId

```go
func (c *MumbleCore) AuthenticatorNameToId(name string) (int, error)
```

Dispatches to NameToId.

### AuthenticatorIdToName

```go
func (c *MumbleCore) AuthenticatorIdToName(userID int) (string, error)
```

Dispatches to IdToName.

### AuthenticatorIdToTexture

```go
func (c *MumbleCore) AuthenticatorIdToTexture(userID int) ([]byte, error)
```

Dispatches to IdToTexture.

### UpdatingAuthRegisterUser

```go
func (c *MumbleCore) UpdatingAuthRegisterUser(info map[int]string) (int, error)
```

Dispatches to RegisterUser.

### UpdatingAuthUnregisterUser

```go
func (c *MumbleCore) UpdatingAuthUnregisterUser(userID int) error
```

Dispatches to UnregisterUser.

### UpdatingAuthSetInfo

```go
func (c *MumbleCore) UpdatingAuthSetInfo(userID int, info map[int]string) error
```

Dispatches to SetInfo.

### UpdatingAuthSetTexture

```go
func (c *MumbleCore) UpdatingAuthSetTexture(userID int, texture []byte) error
```

Dispatches to SetTexture.

---

## Debug Utilities

### DebugBuildVoicePacket

```go
func (c *MumbleCore) DebugBuildVoicePacket(opusData []byte, target int, seq int64) []byte
```

Builds a raw voice packet without sending it. Useful for testing encoders.

### DebugBuildLegacyVoicePacket

```go
func (c *MumbleCore) DebugBuildLegacyVoicePacket(opusData []byte, target int, seq int64) []byte
```

Builds a legacy (pre-1.5) voice packet format.

### DebugVoiceTunnelCount

```go
func (c *MumbleCore) DebugVoiceTunnelCount() uint32
```

Returns the number of voice packets tunneled through TCP.

### DebugCodecVersion

```go
func (c *MumbleCore) DebugCodecVersion() (alpha, beta int32, preferAlpha, opus bool)
```

Returns the negotiated codec versions.

### DebugUserFlags

```go
func (c *MumbleCore) DebugUserFlags(session uint32) string
```

Returns a string describing a user's flags (mute, deaf, suppress, etc.).

### DebugServerVersion

```go
func (c *MumbleCore) DebugServerVersion() (v1 uint32, v2 uint64, release string, protobuf bool)
```

Returns the server's version info.

### DebugMySession

```go
func (c *MumbleCore) DebugMySession() uint32
```

Returns your session ID.

### DebugState

```go
func (c *MumbleCore) DebugState() (cryptReady, udpReady bool, udpSent, udpRecv, tcpSent, tcpRecv uint32)
```

Returns connection state: crypto readiness, UDP readiness, and packet counters.

---

## Unsupported Core Methods

These Core interface methods return `ErrNotSupported` because Mumble doesn't have equivalent features:

| Method | Reason |
|--------|--------|
| `MuteChat` | No chat-level mute in Mumble |
| `ArchiveChat` | No chat archiving |
| `MarkUnread` | No unread markers |
| `UnpinAllMessages` | No message pinning |
| `AcceptCall` | Mumble is always-on voice, no call accept/decline |
| `DeclineCall` | Same as above |
| `SendLocation` | No location sharing |

---

## Dependencies

- Standard library only (`net`, `crypto/tls`, `crypto/x509`, `encoding/xml`, `net/http`)
- No CGo required
- Pure Go protobuf encoding/decoding (hand-written, no protoc)
- Pure Go ZeroC Ice wire protocol implementation
- Pure Go AES-OCB2 voice encryption
