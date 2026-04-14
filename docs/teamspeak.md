# TeamSpeak Core -- API Reference

Pure Go TeamSpeak 3 client implementing the full UDP binary protocol with encrypted voice support. No CGo, no external dependencies.

**296 exported methods** across connection, messaging, channel management, client/user management, server groups, channel groups, permissions, bans, file transfer, voice, offline messages, complaints, tokens, server administration, notifications, 3D audio, audio devices, whisper, bookmarks, and ServerQuery commands.

## Table of Contents

- [Setup](#setup)
- [Types](#types)
- [Connection & Authentication](#connection--authentication)
- [Core Interface -- Messaging](#core-interface----messaging)
- [Core Interface -- Dialogs & Chat Info](#core-interface----dialogs--chat-info)
- [Core Interface -- Groups & Channels](#core-interface----groups--channels)
- [Core Interface -- Members](#core-interface----members)
- [Core Interface -- Contacts](#core-interface----contacts)
- [Core Interface -- Search](#core-interface----search)
- [Core Interface -- File Transfer](#core-interface----file-transfer)
- [Core Interface -- Profile & Sessions](#core-interface----profile--sessions)
- [Core Interface -- Real-time & Events](#core-interface----real-time--events)
- [Core Interface -- Typing & Misc](#core-interface----typing--misc)
- [Client Self-Update](#client-self-update)
- [Channel Management](#channel-management)
- [Channel Subscriptions](#channel-subscriptions)
- [Channel Permissions](#channel-permissions)
- [Client/User Management](#clientuser-management)
- [Client Lookup & Resolution](#client-lookup--resolution)
- [Client Operations (Bulk)](#client-operations-bulk)
- [Server Groups](#server-groups)
- [Channel Groups](#channel-groups)
- [Permissions](#permissions)
- [Server Permissions](#server-permissions)
- [Custom Properties](#custom-properties)
- [Ban Management](#ban-management)
- [Offline Messages](#offline-messages)
- [Complaints](#complaints)
- [Tokens & Privileges](#tokens--privileges)
- [Server Info & Configuration](#server-info--configuration)
- [Server Management (ServerQuery)](#server-management-serverquery)
- [Server Snapshots](#server-snapshots)
- [Temporary Passwords](#temporary-passwords)
- [File Transfer Management](#file-transfer-management)
- [File Transfer Init](#file-transfer-init)
- [Connection Stats & Bandwidth](#connection-stats--bandwidth)
- [Voice & Audio](#voice--audio)
- [3D Audio Positioning](#3d-audio-positioning)
- [Audio Device Management](#audio-device-management)
- [Audio Preprocessing & Playback Config](#audio-preprocessing--playback-config)
- [Wave File Playback](#wave-file-playback)
- [Custom Audio Devices](#custom-audio-devices)
- [Whisper List Management](#whisper-list-management)
- [Notifications & Subscriptions](#notifications--subscriptions)
- [Event Handlers](#event-handlers)
- [Extended List Flags](#extended-list-flags)
- [Logging](#logging)
- [Query Login Management](#query-login-management)
- [API Key Management](#api-key-management)
- [Password Verification](#password-verification)
- [Server Instance Management](#server-instance-management)
- [Bookmarks & Profiles](#bookmarks--profiles)
- [Plugin Commands](#plugin-commands)
- [Raw Command Execution](#raw-command-execution)
- [Unsupported Core Methods](#unsupported-core-methods)

## Setup

```go
import "uniclient/cores"

ts := cores.NewTeamSpeakCore("./sessions/teamspeak.json")
```

**Capabilities:** `TEXT`, `CHANNELS`, `VOICE`, `ADMIN`, `SESSIONS`, `TYPING`

## Types

### TeamSpeakCore

The main struct. Create via `NewTeamSpeakCore(sessionPath)`. Implements the `Core` interface. Thread-safe.

### VoicePacket

```go
type VoicePacket struct {
    SenderClientID int    // S2C only: who sent this voice
    Codec          byte   // 0=SpeexNB, 1=SpeexWB, 2=SpeexUWB, 3=CeltMono, 4=OpusVoice, 5=OpusMusic
    AudioData      []byte // encoded audio frame
    PacketCounter  uint16
    IsWhisper      bool
    ServerFlag     byte   // decoder session tracking (0 if not present)
    HasServerFlag  bool
}
```

Represents incoming or outgoing voice audio data. Codec 4 (OpusVoice) is the modern default.

### TsBandwidthSnapshot

```go
type TsBandwidthSnapshot struct {
    SentLastSecond  [3]int64  // [speech, keepalive, control] bytes/sec
    RecvLastSecond  [3]int64
    SentLastMinute  [3]int64  // bytes/sec average over 60s
    RecvLastMinute  [3]int64
    TotalSentPkts   [3]int64
    TotalSentBytes  [3]int64
    TotalRecvPkts   [3]int64
    TotalRecvBytes  [3]int64
    VoicePacketLoss float64   // 0.0-1.0 ratio
}
```

Point-in-time snapshot of bandwidth statistics. Array indices: 0=speech, 1=keepalive, 2=control.

---

## Connection & Authentication

### Name

```go
func (t *TeamSpeakCore) Name() string
```

Returns `"teamspeak"`.

### Capabilities

```go
func (t *TeamSpeakCore) Capabilities() []string
```

Returns `["TEXT", "CHANNELS", "VOICE", "ADMIN", "SESSIONS", "TYPING"]`.

### Authenticate

```go
func (t *TeamSpeakCore) Authenticate(cfg AuthConfig) error
```

Connects to a TS3 server via UDP. Performs ECDSA cryptographic handshake with Ed25519 license chain verification. Generates and persists a P-256 identity key.

**AuthConfig fields:**
- `Extra["server_address"]` -- server address as `host:port` (default: `localhost:9987`)
- `Extra["nickname"]` -- display name (default: `UniClient`)
- `Extra["password"]` -- server password (optional)

After connecting, automatically registers for server, channel, and text notifications.

```go
err := ts.Authenticate(cores.AuthConfig{
    Extra: map[string]string{
        "server_address": "ts3.example.com:9987",
        "nickname":       "GoBot",
    },
})
```

### Logout

```go
func (t *TeamSpeakCore) Logout() error
```

Disconnects from the server. Disables auto-reconnect before sending the disconnect command.

### Close

```go
func (t *TeamSpeakCore) Close() error
```

Full shutdown: saves session, cancels context, sends disconnect, closes UDP connection, waits for goroutines.

---

## Core Interface -- Messaging

### SendMessage

```go
func (t *TeamSpeakCore) SendMessage(chatID string, msg OutgoingMessage) (*Message, error)
```

Sends a text message. `chatID` format determines target mode:
- `ch:<id>` -- channel message (targetmode=2)
- `dm:<id>` -- private message to client ID (targetmode=1)
- `server` -- server-wide message (targetmode=3)

```go
msg, err := ts.SendMessage("ch:1", cores.OutgoingMessage{Text: "Hello channel!"})
msg, err := ts.SendMessage("dm:5", cores.OutgoingMessage{Text: "Private message"})
msg, err := ts.SendMessage("server", cores.OutgoingMessage{Text: "Server broadcast"})
```

### GetMessages

```go
func (t *TeamSpeakCore) GetMessages(chatID string, opts PaginationOpts) ([]Message, error)
```

Returns cached messages for a channel or user. TS3 has no server-side message history -- only messages received during this session are available. Supports `Limit` and `Offset` pagination.

### EditMessage

```go
func (t *TeamSpeakCore) EditMessage(chatID, msgID, text string) (*Message, error)
```

Not supported. Returns `ErrNotSupported`.

### DeleteMessage

```go
func (t *TeamSpeakCore) DeleteMessage(chatID, msgID string) error
```

Not supported. Returns `ErrNotSupported`.

### ReplyToMessage

```go
func (t *TeamSpeakCore) ReplyToMessage(chatID, replyToMsgID string, msg OutgoingMessage) (*Message, error)
```

TS3 has no reply threading. Sends a normal message to the chat instead.

### ForwardMessage

```go
func (t *TeamSpeakCore) ForwardMessage(fromChatID, msgID, toChatID string) (*Message, error)
```

Not supported. Returns `ErrNotSupported`.

### ReactToMessage

```go
func (t *TeamSpeakCore) ReactToMessage(chatID, msgID, emoji string) error
```

Not supported. Returns `ErrNotSupported`.

### PinMessage / UnpinMessage

```go
func (t *TeamSpeakCore) PinMessage(chatID, msgID string) error
func (t *TeamSpeakCore) UnpinMessage(chatID, msgID string) error
```

Not supported. Returns `ErrNotSupported`.

### MarkAsRead / GetReadState

```go
func (t *TeamSpeakCore) MarkAsRead(chatID, upToMsgID string) error
func (t *TeamSpeakCore) GetReadState(chatID string) (*ReadState, error)
```

Not supported. Returns `ErrNotSupported`.

### SendImageBase64

```go
func (t *TeamSpeakCore) SendImageBase64(chatID, b64, caption string) (*Message, error)
```

Not supported. Returns `ErrNotSupported`.

---

## Core Interface -- Dialogs & Chat Info

### GetDialogs

```go
func (t *TeamSpeakCore) GetDialogs(opts PaginationOpts) ([]Dialog, error)
```

Returns all channels as dialogs by executing `channellist`. Each channel becomes a `Dialog` with type `ChatTypeChannel` and ID `ch:<cid>`.

### GetChatInfo

```go
func (t *TeamSpeakCore) GetChatInfo(chatID string) (*Dialog, error)
```

Returns info for a specific chat. For `server` returns a static server chat dialog. For `dm:<id>` returns a DM dialog. For `ch:<id>` queries `channelinfo` for full channel details.

```go
info, err := ts.GetChatInfo("ch:5")
info, err := ts.GetChatInfo("server")
```

### EditChatTitle

```go
func (t *TeamSpeakCore) EditChatTitle(chatID, title string) error
```

Renames a channel. Only works for `ch:` chat IDs.

### EditChatDescription

```go
func (t *TeamSpeakCore) EditChatDescription(chatID, description string) error
```

Sets a channel's description. Only works for `ch:` chat IDs.

### LeaveChat

```go
func (t *TeamSpeakCore) LeaveChat(chatID string) error
```

Not supported. Returns `ErrNotSupported`. Use `JoinChannel` to move to a different channel.

### GetInviteLink

```go
func (t *TeamSpeakCore) GetInviteLink(chatID string) (string, error)
```

Generates a privilege key (token) for the channel that grants access when used.

```go
token, err := ts.GetInviteLink("ch:5")
```

---

## Core Interface -- Groups & Channels

### CreateGroup

```go
func (t *TeamSpeakCore) CreateGroup(name string, members []string) (*Dialog, error)
```

Creates a semi-permanent channel (TS3 has no "groups" -- maps to channel creation). Delegates to `CreateChannel`.

### CreateChannel

```go
func (t *TeamSpeakCore) CreateChannel(name string, description string) (*Dialog, error)
```

Creates a semi-permanent channel with an optional description. Returns a `Dialog` with ID `ch:<cid>`.

```go
dialog, err := ts.CreateChannel("Lobby", "A place to hang out")
```

### CreateTopic

```go
func (t *TeamSpeakCore) CreateTopic(name, description string) (*Dialog, error)
```

Not supported. Returns `ErrNotSupported`.

### GetFolders / CreateFolder

```go
func (t *TeamSpeakCore) GetFolders() ([]Folder, error)
func (t *TeamSpeakCore) CreateFolder(name string, ids []string) (*Folder, error)
```

Not supported. Returns `ErrNotSupported`.

---

## Core Interface -- Members

### AddMembers

```go
func (t *TeamSpeakCore) AddMembers(chatID string, userIDs []string) error
```

Moves clients into a channel. Each user ID is a client ID (clid). Only works for `ch:` chat IDs.

```go
err := ts.AddMembers("ch:5", []string{"3", "7"})
```

### RemoveMember

```go
func (t *TeamSpeakCore) RemoveMember(chatID, userID string) error
```

Kicks a client from the channel (reasonid=4).

### BanMember

```go
func (t *TeamSpeakCore) BanMember(chatID, userID string) error
```

Bans a client by their client ID.

### UnbanMember

```go
func (t *TeamSpeakCore) UnbanMember(chatID, userID string) error
```

Removes a ban by ban ID.

### GetMembers

```go
func (t *TeamSpeakCore) GetMembers(chatID string, opts PaginationOpts) ([]User, error)
```

Returns clients in a channel from the local cache. For `ch:` IDs, filters by channel. Supports pagination.

### SetAdmin

```go
func (t *TeamSpeakCore) SetAdmin(chatID, userID string, admin bool) error
```

Adds or removes a client from the "Server Admin" or "Admin" server group. `userID` is the client database ID.

---

## Core Interface -- Contacts

### GetContacts

```go
func (t *TeamSpeakCore) GetContacts() ([]User, error)
```

Returns all known clients from the server database via `clientdblist`.

### AddContact / DeleteContact

```go
func (t *TeamSpeakCore) AddContact(id, name, phone string) error
func (t *TeamSpeakCore) DeleteContact(id string) error
```

Not supported. Returns `ErrNotSupported`.

### BlockUser

```go
func (t *TeamSpeakCore) BlockUser(userID string) error
```

Bans the client. Delegates to `BanMember`.

### UnblockUser

```go
func (t *TeamSpeakCore) UnblockUser(userID string) error
```

Removes the ban. Delegates to `UnbanMember`.

### GetBlockedUsers

```go
func (t *TeamSpeakCore) GetBlockedUsers() ([]User, error)
```

Returns the server ban list as users. Gracefully handles empty ban list (error 1281).

---

## Core Interface -- Search

### SearchMessages

```go
func (t *TeamSpeakCore) SearchMessages(chatID, query string, opts PaginationOpts) ([]Message, error)
```

Searches cached messages by substring match (case-insensitive). Searches across all chats.

### SearchGlobal

```go
func (t *TeamSpeakCore) SearchGlobal(query string, opts PaginationOpts) ([]Dialog, error)
```

Searches channel names by substring match (case-insensitive) via `channellist`.

---

## Core Interface -- File Transfer

### UploadFile

```go
func (t *TeamSpeakCore) UploadFile(chatID string, file FileUpload, progress func(sent, total int64)) (*Message, error)
```

Uploads a file to a channel's file browser. Only works for `ch:` chat IDs. Initiates a file transfer via `ftinitupload`, connects to the FT port over TCP, sends the ftkey, then streams the file data.

```go
f, _ := os.Open("document.pdf")
msg, err := ts.UploadFile("ch:1", cores.FileUpload{
    Name:   "document.pdf",
    Size:   fileSize,
    Reader: f,
}, func(sent, total int64) {
    fmt.Printf("%.0f%%\n", float64(sent)/float64(total)*100)
})
```

### DownloadFile

```go
func (t *TeamSpeakCore) DownloadFile(fileRef FileRef, dest string, progress func(recv, total int64)) error
```

Downloads a file from the channel file browser. `fileRef.ID` must be formatted as `cid:<channel_id>:<file_path>`. Uses `ftinitdownload` to get transfer params, then streams via TCP.

---

## Core Interface -- Profile & Sessions

### GetProfile

```go
func (t *TeamSpeakCore) GetProfile(userID string) (*User, error)
```

Returns detailed info for a connected client via `clientinfo`. `userID` is the client ID (clid).

### GetSessions

```go
func (t *TeamSpeakCore) GetSessions() ([]Session, error)
```

Lists all connected clients as sessions via `clientlist -uid -times -info`. Each session includes device platform, client version, IP, and connection time.

### TerminateSession

```go
func (t *TeamSpeakCore) TerminateSession(sessionID string) error
```

Kicks a client from the server (reasonid=5). Cannot terminate your own session.

---

## Core Interface -- Real-time & Events

### OnUpdate

```go
func (t *TeamSpeakCore) OnUpdate(handler func(Update))
```

Registers a callback for unified updates (messages, user joins/parts, channel changes).

```go
ts.OnUpdate(func(u cores.Update) {
    if u.Message != nil {
        fmt.Printf("[%s] %s: %s\n", u.ChatID, u.Message.SenderName, u.Message.Text)
    }
})
```

---

## Core Interface -- Typing & Misc

### SendTyping

```go
func (t *TeamSpeakCore) SendTyping(chatID string) error
```

Sends a typing indicator via `clientchatcomposing`. Only supported for DM chat IDs (`dm:<clid>`).

### CreatePoll / VotePoll

```go
func (t *TeamSpeakCore) CreatePoll(chatID, question string, options []string) (*Message, error)
func (t *TeamSpeakCore) VotePoll(chatID, pollID string, option int) error
```

Not supported. Returns `ErrNotSupported`.

### SendSticker

```go
func (t *TeamSpeakCore) SendSticker(chatID, stickerID string) (*Message, error)
```

Not supported. Returns `ErrNotSupported`.

---

## Client Self-Update

These methods modify properties of the connected client via `clientupdate`.

### ClientUpdate

```go
func (t *TeamSpeakCore) ClientUpdate(params map[string]string) error
```

Generic client update with arbitrary key-value pairs.

```go
err := ts.ClientUpdate(map[string]string{
    "client_nickname": "NewName",
    "client_away":     "1",
})
```

### SetNickname

```go
func (t *TeamSpeakCore) SetNickname(nickname string) error
```

Changes the client's display name. Updates internal state.

### SetInputMuted

```go
func (t *TeamSpeakCore) SetInputMuted(muted bool) error
```

Mutes or unmutes microphone input.

### SetOutputMuted

```go
func (t *TeamSpeakCore) SetOutputMuted(muted bool) error
```

Mutes or unmutes audio output.

### SetInputHardware

```go
func (t *TeamSpeakCore) SetInputHardware(enabled bool) error
```

Sets whether input hardware (microphone) is available.

### SetOutputHardware

```go
func (t *TeamSpeakCore) SetOutputHardware(enabled bool) error
```

Sets whether output hardware (speakers) is available.

### SetChannelCommander

```go
func (t *TeamSpeakCore) SetChannelCommander(enabled bool) error
```

Toggles channel commander status (shows a special icon).

### SetRecording

```go
func (t *TeamSpeakCore) SetRecording(enabled bool) error
```

Sets the recording status flag (visible to other clients).

### SetAway

```go
func (t *TeamSpeakCore) SetAway(away bool, message string) error
```

Sets away status with an optional message.

```go
err := ts.SetAway(true, "Be right back")
```

### SetDescription

```go
func (t *TeamSpeakCore) SetDescription(description string) error
```

Sets the client's description text.

### SetAvatar

```go
func (t *TeamSpeakCore) SetAvatar(md5Hex string) error
```

Sets the client avatar flag (MD5 hash of the avatar file).

### RequestTalkPower

```go
func (t *TeamSpeakCore) RequestTalkPower(message string) error
```

Requests talk power in a moderated channel.

### CancelTalkPowerRequest

```go
func (t *TeamSpeakCore) CancelTalkPowerRequest() error
```

Cancels a pending talk power request.

### SetBadges

```go
func (t *TeamSpeakCore) SetBadges(badges string) error
```

Sets the client's badge string (overwrites format).

### SetMetaData

```go
func (t *TeamSpeakCore) SetMetaData(metadata string) error
```

Sets the client's metadata string (arbitrary data visible to plugins).

### SetPhoneticNickname

```go
func (t *TeamSpeakCore) SetPhoneticNickname(name string) error
```

Sets a phonetic pronunciation of the nickname for text-to-speech.

---

## Channel Management

### CreateChannelFull

```go
func (t *TeamSpeakCore) CreateChannelFull(name string, opts map[string]string) (int, error)
```

Creates a channel with full control over all properties. Returns the new channel ID.

```go
cid, err := ts.CreateChannelFull("VIP Room", map[string]string{
    "channel_flag_permanent":    "1",
    "channel_maxclients":        "10",
    "channel_password":          "secret",
    "channel_codec":             "4",  // Opus Voice
    "channel_codec_quality":     "10",
})
```

### EditChannel

```go
func (t *TeamSpeakCore) EditChannel(cid int, props map[string]string) error
```

Edits channel properties.

```go
err := ts.EditChannel(5, map[string]string{
    "channel_name":  "Renamed Channel",
    "channel_topic": "New topic",
})
```

### DeleteChannel

```go
func (t *TeamSpeakCore) DeleteChannel(cid int, force bool) error
```

Deletes a channel. If `force` is true, deletes even if clients are in it (moves them to default).

### MoveChannel

```go
func (t *TeamSpeakCore) MoveChannel(cid, newParent, order int) error
```

Moves a channel to a new parent with a sort order.

### FindChannel

```go
func (t *TeamSpeakCore) FindChannel(pattern string) ([]map[string]string, error)
```

Searches channels by name pattern via `channelfind`.

### GetChannelDescription

```go
func (t *TeamSpeakCore) GetChannelDescription(cid int) (string, error)
```

Returns the full description text for a channel via `channelgetdescription`.

### ChannelInfoRequest

```go
func (t *TeamSpeakCore) ChannelInfoRequest(cid int) (map[string]string, error)
```

Requests full channel info from the server via `channelinfo`.

### RequestInfoUpdate

```go
func (t *TeamSpeakCore) RequestInfoUpdate(infoType string, id int) error
```

Forces a refresh of server, channel, or client info. `infoType`: `"server"`, `"channel"`, `"client"`.

---

## Channel Subscriptions

### SubscribeChannel

```go
func (t *TeamSpeakCore) SubscribeChannel(cids ...int) error
```

Subscribes to one or more channels to receive their events and client lists.

### SubscribeAllChannels

```go
func (t *TeamSpeakCore) SubscribeAllChannels() error
```

Subscribes to all channels at once.

### UnsubscribeChannel

```go
func (t *TeamSpeakCore) UnsubscribeChannel(cids ...int) error
```

Unsubscribes from one or more channels.

### UnsubscribeAllChannels

```go
func (t *TeamSpeakCore) UnsubscribeAllChannels() error
```

Unsubscribes from all channels.

---

## Channel Permissions

### ChannelAddPerm

```go
func (t *TeamSpeakCore) ChannelAddPerm(cid int, permID int, permValue int) error
```

Adds a permission to a channel.

### ChannelDelPerm

```go
func (t *TeamSpeakCore) ChannelDelPerm(cid int, permID int) error
```

Removes a permission from a channel.

### ChannelPermList

```go
func (t *TeamSpeakCore) ChannelPermList(cid int) ([]map[string]string, error)
```

Lists all permissions on a channel.

### ChannelClientAddPerm

```go
func (t *TeamSpeakCore) ChannelClientAddPerm(cid, cldbid, permID, permValue int) error
```

Adds a client-specific permission on a channel.

### ChannelClientDelPerm

```go
func (t *TeamSpeakCore) ChannelClientDelPerm(cid, cldbid, permID int) error
```

Removes a client-specific permission from a channel.

### ChannelClientPermList

```go
func (t *TeamSpeakCore) ChannelClientPermList(cid, cldbid int) ([]map[string]string, error)
```

Lists client-specific permissions on a channel.

---

## Client/User Management

### ClientKick

```go
func (t *TeamSpeakCore) ClientKick(clid, reasonID int, message string) error
```

Kicks a client. `reasonID`: 4 = kick from channel, 5 = kick from server.

### ClientMute

```go
func (t *TeamSpeakCore) ClientMute(clid int) error
```

Locally mutes a client (suppresses their voice packets).

### ClientUnmute

```go
func (t *TeamSpeakCore) ClientUnmute(clid int) error
```

Removes the local mute from a client.

### ClientChatComposing

```go
func (t *TeamSpeakCore) ClientChatComposing(clid int) error
```

Sends a typing indicator to a specific client.

### ClientChatClosed

```go
func (t *TeamSpeakCore) ClientChatClosed(clid int) error
```

Notifies a client that you closed the chat window.

### ClientPoke

```go
func (t *TeamSpeakCore) ClientPoke(clid int, message string) error
```

Sends a poke notification to a client (appears as a popup).

```go
err := ts.ClientPoke(5, "Hey, join our channel!")
```

### ClientEdit

```go
func (t *TeamSpeakCore) ClientEdit(clid int, props map[string]string) error
```

Edits another client's properties (requires permissions).

### ClientVariable

```go
func (t *TeamSpeakCore) ClientVariable(clid int, varNames ...string) (map[string]string, error)
```

Gets specific client variables by name.

### ClientDBList

```go
func (t *TeamSpeakCore) ClientDBList(start, duration int) ([]map[string]string, error)
```

Lists client database entries with pagination.

### ClientDBInfo

```go
func (t *TeamSpeakCore) ClientDBInfo(cldbid int) (map[string]string, error)
```

Returns detailed info for a client database entry.

### ClientDBEdit

```go
func (t *TeamSpeakCore) ClientDBEdit(cldbid int, props map[string]string) error
```

Edits a client database entry.

### ClientDBDelete

```go
func (t *TeamSpeakCore) ClientDBDelete(cldbid int) error
```

Deletes a client database entry.

### JoinChannel

```go
func (t *TeamSpeakCore) JoinChannel(cid int, password string) error
```

Moves yourself to a channel. Password is optional (empty string for no password).

```go
err := ts.JoinChannel(5, "")
err := ts.JoinChannel(10, "channel_password")
```

### SetIsTalker

```go
func (t *TeamSpeakCore) SetIsTalker(clid int, isTalker bool) error
```

Grants or revokes talker status for a client in a moderated channel.

### RequestClientEditDescription

```go
func (t *TeamSpeakCore) RequestClientEditDescription(clid int, description string) error
```

Sets another client's description.

### GetAvatar

```go
func (t *TeamSpeakCore) GetAvatar(clid int) ([]byte, error)
```

Initiates a file transfer to download a client's avatar. Returns file transfer parameters.

---

## Client Lookup & Resolution

### ClientFind

```go
func (t *TeamSpeakCore) ClientFind(pattern string) ([]map[string]string, error)
```

Searches online clients by nickname pattern.

### ClientDBFind

```go
func (t *TeamSpeakCore) ClientDBFind(pattern string, isUID bool) ([]map[string]string, error)
```

Searches the client database by nickname or UID pattern.

### ClientGetDBIDFromUID

```go
func (t *TeamSpeakCore) ClientGetDBIDFromUID(cluid string) (int, error)
```

Resolves a unique identifier to a database ID.

### ClientGetIDs

```go
func (t *TeamSpeakCore) ClientGetIDs(cluid string) ([]map[string]string, error)
```

Returns all online sessions for a unique identifier.

### ClientGetNameFromUID

```go
func (t *TeamSpeakCore) ClientGetNameFromUID(cluid string) (string, error)
```

Resolves a unique identifier to a nickname.

### ClientGetNameFromDBID

```go
func (t *TeamSpeakCore) ClientGetNameFromDBID(cldbid int) (string, error)
```

Resolves a database ID to a nickname.

### ClientGetUIDFromCLID

```go
func (t *TeamSpeakCore) ClientGetUIDFromCLID(clid int) (string, error)
```

Resolves an online client ID to their unique identifier.

---

## Client Operations (Bulk)

### RequestClientsMove

```go
func (t *TeamSpeakCore) RequestClientsMove(clids []int, cid int, password string) error
```

Moves multiple clients to a channel at once.

### RequestClientsKickFromChannel

```go
func (t *TeamSpeakCore) RequestClientsKickFromChannel(clids []int, message string) error
```

Kicks multiple clients from their current channel.

### RequestClientsKickFromServer

```go
func (t *TeamSpeakCore) RequestClientsKickFromServer(clids []int, message string) error
```

Kicks multiple clients from the server.

### RequestMuteClientsTemporary

```go
func (t *TeamSpeakCore) RequestMuteClientsTemporary(clids []int) error
```

Temporarily mutes multiple clients.

### RequestUnmuteClientsTemporary

```go
func (t *TeamSpeakCore) RequestUnmuteClientsTemporary(clids []int) error
```

Unmutes multiple clients.

### ClientAddServerGroup

```go
func (t *TeamSpeakCore) ClientAddServerGroup(cldbid int, sgids []int) error
```

Adds multiple server groups to a client at once (3.9.0+).

### ClientDelServerGroup

```go
func (t *TeamSpeakCore) ClientDelServerGroup(cldbid int, sgids []int) error
```

Removes multiple server groups from a client at once (3.9.0+).

---

## Server Groups

### ServerGroupList

```go
func (t *TeamSpeakCore) ServerGroupList() ([]map[string]string, error)
```

Lists all server groups.

### ServerGroupAdd

```go
func (t *TeamSpeakCore) ServerGroupAdd(name string) (int, error)
```

Creates a new server group. Returns the group ID.

### ServerGroupDel

```go
func (t *TeamSpeakCore) ServerGroupDel(sgid int, force bool) error
```

Deletes a server group. If `force`, removes even if clients are assigned.

### ServerGroupRename

```go
func (t *TeamSpeakCore) ServerGroupRename(sgid int, name string) error
```

Renames a server group.

### ServerGroupCopy

```go
func (t *TeamSpeakCore) ServerGroupCopy(sourceSGID int, name string, targetType int) (int, error)
```

Copies a server group. Returns the new group ID.

### ServerGroupAddClient

```go
func (t *TeamSpeakCore) ServerGroupAddClient(sgid, cldbid int) error
```

Adds a client to a server group.

### ServerGroupDelClient

```go
func (t *TeamSpeakCore) ServerGroupDelClient(sgid, cldbid int) error
```

Removes a client from a server group.

### ServerGroupClientList

```go
func (t *TeamSpeakCore) ServerGroupClientList(sgid int) ([]map[string]string, error)
```

Lists all clients in a server group.

### ServerGroupPermList

```go
func (t *TeamSpeakCore) ServerGroupPermList(sgid int) ([]map[string]string, error)
```

Lists permissions assigned to a server group.

### ServerGroupAddPerm

```go
func (t *TeamSpeakCore) ServerGroupAddPerm(sgid, permID, permValue int) error
```

Adds a permission to a server group.

### ServerGroupDelPerm

```go
func (t *TeamSpeakCore) ServerGroupDelPerm(sgid, permID int) error
```

Removes a permission from a server group.

### ServerGroupsByClientID

```go
func (t *TeamSpeakCore) ServerGroupsByClientID(cldbid int) ([]map[string]string, error)
```

Lists all server groups a client belongs to.

### ServerGroupAutoAddPerm

```go
func (t *TeamSpeakCore) ServerGroupAutoAddPerm(sgtype int, permID, permValue int, permNegated, permSkip bool) error
```

Adds an auto-assigned permission for a server group type.

### ServerGroupAutoDelPerm

```go
func (t *TeamSpeakCore) ServerGroupAutoDelPerm(sgtype int, permID int) error
```

Removes an auto-assigned permission for a server group type.

---

## Channel Groups

### ChannelGroupList

```go
func (t *TeamSpeakCore) ChannelGroupList() ([]map[string]string, error)
```

Lists all channel groups.

### ChannelGroupAdd

```go
func (t *TeamSpeakCore) ChannelGroupAdd(name string) (int, error)
```

Creates a new channel group. Returns the group ID.

### ChannelGroupDel

```go
func (t *TeamSpeakCore) ChannelGroupDel(cgid int, force bool) error
```

Deletes a channel group.

### ChannelGroupRename

```go
func (t *TeamSpeakCore) ChannelGroupRename(cgid int, name string) error
```

Renames a channel group.

### ChannelGroupCopy

```go
func (t *TeamSpeakCore) ChannelGroupCopy(sourceCGID int, name string, targetType int) (int, error)
```

Copies a channel group. Returns the new group ID.

### ChannelGroupClientList

```go
func (t *TeamSpeakCore) ChannelGroupClientList(cgid, cid int) ([]map[string]string, error)
```

Lists clients in a channel group for a specific channel.

### ChannelGroupPermList

```go
func (t *TeamSpeakCore) ChannelGroupPermList(cgid int) ([]map[string]string, error)
```

Lists permissions for a channel group.

### ChannelGroupAddPerm

```go
func (t *TeamSpeakCore) ChannelGroupAddPerm(cgid, permID, permValue int) error
```

Adds a permission to a channel group.

### ChannelGroupDelPerm

```go
func (t *TeamSpeakCore) ChannelGroupDelPerm(cgid, permID int) error
```

Removes a permission from a channel group.

### SetClientChannelGroup

```go
func (t *TeamSpeakCore) SetClientChannelGroup(cgid, cid, cldbid int) error
```

Assigns a client to a channel group in a specific channel.

### ChannelGroupsByClientID

```go
func (t *TeamSpeakCore) ChannelGroupsByClientID(cldbid int) ([]map[string]string, error)
```

Lists channel groups assigned to a client across all channels.

---

## Permissions

### PermissionList

```go
func (t *TeamSpeakCore) PermissionList() ([]map[string]string, error)
```

Lists all available permissions on the server.

### PermissionListNew

```go
func (t *TeamSpeakCore) PermissionListNew() ([]map[string]string, error)
```

Lists permissions in the newer format (3.0.7+).

### PermFind

```go
func (t *TeamSpeakCore) PermFind(permID int) ([]map[string]string, error)
```

Finds where a permission is assigned (server groups, channel groups, etc.).

### PermGet

```go
func (t *TeamSpeakCore) PermGet(permID int) (map[string]string, error)
```

Gets the value of a specific permission.

### PermOverview

```go
func (t *TeamSpeakCore) PermOverview(cid, cldbid int) ([]map[string]string, error)
```

Returns a complete permission overview for a client in a channel.

### PermIDGetByName

```go
func (t *TeamSpeakCore) PermIDGetByName(permsid string) (int, error)
```

Resolves a permission string identifier to its numeric ID.

```go
permID, err := ts.PermIDGetByName("b_virtualserver_modify_name")
```

### PermReset

```go
func (t *TeamSpeakCore) PermReset() error
```

Resets all permissions to server defaults.

### PermCommandsPermSID

```go
func (t *TeamSpeakCore) PermCommandsPermSID(command string, permSID string, permValue int) error
```

Executes permission commands using string-based permission references instead of numeric IDs.

### ClientAddPerm

```go
func (t *TeamSpeakCore) ClientAddPerm(cldbid, permID, permValue int) error
```

Adds a permission to a specific client.

### ClientDelPerm

```go
func (t *TeamSpeakCore) ClientDelPerm(cldbid, permID int) error
```

Removes a permission from a client.

### ClientPermList

```go
func (t *TeamSpeakCore) ClientPermList(cldbid int) ([]map[string]string, error)
```

Lists all permissions assigned to a client.

---

## Server Permissions

### ServerAddPerm

```go
func (t *TeamSpeakCore) ServerAddPerm(permID, permValue int, permNegated, permSkip bool) error
```

Adds a server-level permission.

### ServerDelPerm

```go
func (t *TeamSpeakCore) ServerDelPerm(permID int) error
```

Removes a server-level permission.

### ServerPermList

```go
func (t *TeamSpeakCore) ServerPermList() ([]map[string]string, error)
```

Lists all server-level permissions.

---

## Custom Properties

### CustomInfo

```go
func (t *TeamSpeakCore) CustomInfo(cldbid int) ([]map[string]string, error)
```

Lists custom properties for a client.

### CustomSearch

```go
func (t *TeamSpeakCore) CustomSearch(ident, pattern string) ([]map[string]string, error)
```

Searches custom properties by identifier and value pattern.

### CustomSet

```go
func (t *TeamSpeakCore) CustomSet(cldbid int, ident, value string) error
```

Sets a custom property on a client.

### CustomDelete

```go
func (t *TeamSpeakCore) CustomDelete(cldbid int, ident string) error
```

Deletes a custom property from a client.

---

## Ban Management

### BanAdd

```go
func (t *TeamSpeakCore) BanAdd(ip, name, uid string, timeSeconds int, reason string) (int, error)
```

Creates a ban rule by IP, name, and/or UID. Returns the ban ID. All filter fields are optional but at least one must be set. `timeSeconds=0` means permanent.

```go
banID, err := ts.BanAdd("1.2.3.4", "", "", 3600, "Spamming")
banID, err := ts.BanAdd("", "", "abc123=", 0, "Permanent UID ban")
```

### BanClient

```go
func (t *TeamSpeakCore) BanClient(clid, timeSeconds int, reason string) (int, error)
```

Bans an online client directly by client ID. Returns the ban ID.

### BanClientDBID

```go
func (t *TeamSpeakCore) BanClientDBID(cldbid, timeSeconds int, reason string) (int, error)
```

Bans a client by their database ID.

### BanAddMyTSID

```go
func (t *TeamSpeakCore) BanAddMyTSID(mytsid string, timeSeconds int, reason string) (int, error)
```

Bans by myTeamSpeak ID (server 3.5.0+).

### BanDel

```go
func (t *TeamSpeakCore) BanDel(banID int) error
```

Deletes a specific ban rule by ID.

### BanDelAll

```go
func (t *TeamSpeakCore) BanDelAll() error
```

Deletes all ban rules.

### BanListPaginated

```go
func (t *TeamSpeakCore) BanListPaginated(start, duration int) ([]map[string]string, error)
```

Returns ban list with pagination (3.8.0+).

---

## Offline Messages

### MessageAdd

```go
func (t *TeamSpeakCore) MessageAdd(cluid, subject, message string) error
```

Sends an offline message to a client identified by their unique ID.

### MessageDel

```go
func (t *TeamSpeakCore) MessageDel(msgID int) error
```

Deletes an offline message.

### MessageGet

```go
func (t *TeamSpeakCore) MessageGet(msgID int) (map[string]string, error)
```

Retrieves an offline message by ID.

### MessageList

```go
func (t *TeamSpeakCore) MessageList() ([]map[string]string, error)
```

Lists all offline messages.

### MessageUpdateFlag

```go
func (t *TeamSpeakCore) MessageUpdateFlag(msgID int, read bool) error
```

Marks an offline message as read or unread.

---

## Complaints

### ComplainAdd

```go
func (t *TeamSpeakCore) ComplainAdd(tcldbid int, message string) error
```

Files a complaint about a client.

### ComplainDel

```go
func (t *TeamSpeakCore) ComplainDel(tcldbid, fcldbid int) error
```

Deletes a specific complaint (target + from client).

### ComplainDelAll

```go
func (t *TeamSpeakCore) ComplainDelAll(tcldbid int) error
```

Deletes all complaints about a client.

### ComplainList

```go
func (t *TeamSpeakCore) ComplainList(tcldbid int) ([]map[string]string, error)
```

Lists all complaints about a client.

---

## Tokens & Privileges

### PrivilegeKeyAdd

```go
func (t *TeamSpeakCore) PrivilegeKeyAdd(tokenType, tokenID1, tokenID2 int) (string, error)
```

Creates a privilege key (token). `tokenType`: 0 = server group, 1 = channel group. Returns the token string.

```go
token, err := ts.PrivilegeKeyAdd(0, serverGroupID, 0) // server group token
token, err := ts.PrivilegeKeyAdd(1, channelGroupID, channelID) // channel group token
```

### PrivilegeKeyDelete

```go
func (t *TeamSpeakCore) PrivilegeKeyDelete(token string) error
```

Deletes a privilege key.

### PrivilegeKeyList

```go
func (t *TeamSpeakCore) PrivilegeKeyList() ([]map[string]string, error)
```

Lists all privilege keys.

### PrivilegeKeyUse

```go
func (t *TeamSpeakCore) PrivilegeKeyUse(token string) error
```

Redeems a privilege key, applying its group assignment.

---

## Server Info & Configuration

### ServerInfo

```go
func (t *TeamSpeakCore) ServerInfo() (map[string]string, error)
```

Returns comprehensive server information (name, version, max clients, uptime, etc.).

### ServerEdit

```go
func (t *TeamSpeakCore) ServerEdit(props map[string]string) error
```

Edits virtual server properties.

```go
err := ts.ServerEdit(map[string]string{
    "virtualserver_name":       "My Server",
    "virtualserver_maxclients": "64",
})
```

### ServerVersion

```go
func (t *TeamSpeakCore) ServerVersion() (map[string]string, error)
```

Returns server version, platform, and build info.

### WhoAmI

```go
func (t *TeamSpeakCore) WhoAmI() (map[string]string, error)
```

Returns info about the current connection (client ID, channel, server ID, etc.).

### GetConnectionInfo

```go
func (t *TeamSpeakCore) GetConnectionInfo(clid int) (map[string]string, error)
```

Returns detailed connection statistics for a client.

### ServerRequestConnectionInfo

```go
func (t *TeamSpeakCore) ServerRequestConnectionInfo() (map[string]string, error)
```

Returns server-wide connection statistics.

### GlobalMessage

```go
func (t *TeamSpeakCore) GlobalMessage(message string) error
```

Broadcasts a text message to all virtual servers (ServerQuery only).

---

## Server Management (ServerQuery)

These commands require ServerQuery admin access.

### ServerList

```go
func (t *TeamSpeakCore) ServerList() ([]map[string]string, error)
```

Lists all virtual servers.

### ServerCreate

```go
func (t *TeamSpeakCore) ServerCreate(name string, props map[string]string) (map[string]string, error)
```

Creates a new virtual server. Returns server info including `sid` and `token`.

### ServerDelete

```go
func (t *TeamSpeakCore) ServerDelete(sid int) error
```

Deletes a virtual server.

### ServerStart

```go
func (t *TeamSpeakCore) ServerStart(sid int) error
```

Starts a stopped virtual server.

### ServerStop

```go
func (t *TeamSpeakCore) ServerStop(sid int) error
```

Stops a running virtual server.

### ServerIdGetByPort

```go
func (t *TeamSpeakCore) ServerIdGetByPort(port int) (int, error)
```

Looks up a virtual server's ID by its UDP port.

### ServerProcessStop

```go
func (t *TeamSpeakCore) ServerProcessStop() error
```

Shuts down the entire TS3 server process.

---

## Server Snapshots

### ServerSnapshotCreate

```go
func (t *TeamSpeakCore) ServerSnapshotCreate() (string, error)
```

Creates a snapshot of the virtual server configuration. Returns the snapshot data string.

### ServerSnapshotDeploy

```go
func (t *TeamSpeakCore) ServerSnapshotDeploy(snapshot string) error
```

Restores a server from a snapshot string.

### ServerSnapshotDeployKeepFiles

```go
func (t *TeamSpeakCore) ServerSnapshotDeployKeepFiles(snapshot string) error
```

Deploys a snapshot while keeping existing files (3.10.0+).

### ServerSnapshotPassword

```go
func (t *TeamSpeakCore) ServerSnapshotPassword(password string) (string, error)
```

Creates a password-protected snapshot (3.10.0+).

---

## Temporary Passwords

### ServerTempPasswordAdd

```go
func (t *TeamSpeakCore) ServerTempPasswordAdd(password string, description string, duration int, targetCID int) error
```

Creates a temporary server password that auto-moves users to a channel.

### ServerTempPasswordDel

```go
func (t *TeamSpeakCore) ServerTempPasswordDel(password string) error
```

Deletes a temporary server password.

### ServerTempPasswordList

```go
func (t *TeamSpeakCore) ServerTempPasswordList() ([]map[string]string, error)
```

Lists all temporary server passwords.

---

## File Transfer Management

### FTGetFileList

```go
func (t *TeamSpeakCore) FTGetFileList(cid int, path, channelPassword string) ([]map[string]string, error)
```

Lists files in a channel's file browser.

```go
files, err := ts.FTGetFileList(1, "/", "")
```

### FTGetFileInfo

```go
func (t *TeamSpeakCore) FTGetFileInfo(cid int, name, channelPassword string) (map[string]string, error)
```

Returns info about a specific file.

### FTDeleteFile

```go
func (t *TeamSpeakCore) FTDeleteFile(cid int, names []string, channelPassword string) error
```

Deletes one or more files from a channel.

### FTCreateDir

```go
func (t *TeamSpeakCore) FTCreateDir(cid int, dirname, channelPassword string) error
```

Creates a directory in a channel's file browser.

### FTRenameFile

```go
func (t *TeamSpeakCore) FTRenameFile(cid int, oldName, newName, channelPassword string, targetCID int, targetPassword string) error
```

Renames or moves a file. If `targetCID > 0`, moves the file to a different channel.

### FTStop

```go
func (t *TeamSpeakCore) FTStop(serverFTFID int, del bool) error
```

Stops a running file transfer. If `del`, deletes the incomplete file.

### FTList

```go
func (t *TeamSpeakCore) FTList() ([]map[string]string, error)
```

Lists all active file transfers.

---

## File Transfer Init

### FTInitUpload

```go
func (t *TeamSpeakCore) FTInitUpload(clientftfid, cid int, name string, cpw string, size int64, overwrite, resume bool) (map[string]string, error)
```

Initializes a file upload. Returns transfer parameters: `port`, `ftkey`, `seekpos`.

### FTInitDownload

```go
func (t *TeamSpeakCore) FTInitDownload(clientftfid, cid int, name string, cpw string, seekpos int64) (map[string]string, error)
```

Initializes a file download. Returns transfer parameters: `port`, `ftkey`, `size`.

---

## Connection Stats & Bandwidth

### SetConnectionInfo

```go
func (t *TeamSpeakCore) SetConnectionInfo() error
```

Reports local bandwidth statistics to the server. Sends per-category (speech/keepalive/control) sent/received byte counts, packet counts, and packet loss data.

### GetBandwidthStats

```go
func (t *TeamSpeakCore) GetBandwidthStats() TsBandwidthSnapshot
```

Returns current bandwidth statistics as a point-in-time snapshot. Tracks per-category (speech, keepalive, control) data with a 60-second rolling window.

---

## Voice & Audio

### OnVoice

```go
func (t *TeamSpeakCore) OnVoice(handler func(VoicePacket))
```

Registers a callback for incoming voice packets. Each `VoicePacket` contains the sender, codec type, raw encoded audio data, and whisper flag.

```go
ts.OnVoice(func(vp cores.VoicePacket) {
    fmt.Printf("Voice from client %d: codec=%d, %d bytes\n",
        vp.SenderClientID, vp.Codec, len(vp.AudioData))
})
```

### SendVoice

```go
func (t *TeamSpeakCore) SendVoice(codec byte, audioData []byte) error
```

Sends a voice packet to the current channel. Audio must be pre-encoded (Opus recommended). Packets are encrypted with EAX-AES and sent via UDP -- fire and forget, no ACK.

```go
err := ts.SendVoice(4, opusFrame) // codec 4 = Opus Voice
```

### SendVoiceWhisper

```go
func (t *TeamSpeakCore) SendVoiceWhisper(codec byte, audioData []byte, channelIDs []uint64, clientIDs []uint16) error
```

Sends a whisper voice packet to specific channels and/or clients.

```go
err := ts.SendVoiceWhisper(4, opusFrame, []uint64{1, 2}, []uint16{5})
```

### SendVoiceGroupWhisper

```go
func (t *TeamSpeakCore) SendVoiceGroupWhisper(codec byte, audioData []byte, whisperType, whisperTarget byte, targetID uint64) error
```

Sends a group whisper voice packet. Whisper types: 0=ServerGroup, 1=ChannelGroup, 2=ChannelCommander, 3=AllClients. Whisper targets: 0=AllChannels, 1=CurrentChannel, 2=ParentChannel, 3=AllParentChannels, 4=ChannelFamily, 5=CompleteChannelFamily, 6=Subchannels.

### DecodeLegacyCodec

```go
func (t *TeamSpeakCore) DecodeLegacyCodec(codecType int, data []byte) ([]int16, error)
```

Placeholder for decoding Speex/CELT audio from older clients. Returns an error since legacy codecs require native decoders. Modern TS3 uses Opus (codec 4/5).

### StartVoiceRecording

```go
func (t *TeamSpeakCore) StartVoiceRecording() error
```

Starts recording voice. Sets the recording flag.

### StopVoiceRecording

```go
func (t *TeamSpeakCore) StopVoiceRecording() error
```

Stops voice recording.

---

### DetectVoiceActivity (package-level)

```go
func DetectVoiceActivity(pcm []int16, threshold float64) bool
```

Energy-based voice activity detection. Returns true if the RMS energy of the PCM samples exceeds the threshold. Typical threshold: 300-500 for speech.

```go
if cores.DetectVoiceActivity(pcmSamples, 400) {
    // Voice detected, encode and send
}
```

---

## 3D Audio Positioning

### Set3DListenerAttributes

```go
func (t *TeamSpeakCore) Set3DListenerAttributes(position, forward, up [3]float32)
```

Sets the listener's position and orientation in 3D space for spatial audio rendering.

### SetChannel3DAttributes

```go
func (t *TeamSpeakCore) SetChannel3DAttributes(clid int, position [3]float32)
```

Positions a client's audio source in 3D space relative to the listener.

### Set3DWaveAttributes

```go
func (t *TeamSpeakCore) Set3DWaveAttributes(waveHandle int, position [3]float32)
```

Positions a wave file sound source in 3D space.

### System3DSettings

```go
func (t *TeamSpeakCore) System3DSettings(distanceFactor, rolloffScale float32)
```

Configures the global distance factor and rolloff scale for 3D audio attenuation.

---

## Audio Device Management

### GetPlaybackDeviceList

```go
func (t *TeamSpeakCore) GetPlaybackDeviceList() []map[string]string
```

Returns available playback devices. Currently returns a default device.

### GetCaptureDeviceList

```go
func (t *TeamSpeakCore) GetCaptureDeviceList() []map[string]string
```

Returns available capture devices. Currently returns a default device.

### GetPlaybackModeList

```go
func (t *TeamSpeakCore) GetPlaybackModeList() []string
```

Returns available playback modes. Returns `["default"]`.

### GetCaptureModeList

```go
func (t *TeamSpeakCore) GetCaptureModeList() []string
```

Returns available capture modes. Returns `["default"]`.

### OpenPlaybackDevice

```go
func (t *TeamSpeakCore) OpenPlaybackDevice(mode, deviceID string) error
```

Opens a playback device by mode and device ID.

### OpenCaptureDevice

```go
func (t *TeamSpeakCore) OpenCaptureDevice(mode, deviceID string) error
```

Opens a capture device by mode and device ID.

### ClosePlaybackDevice

```go
func (t *TeamSpeakCore) ClosePlaybackDevice() error
```

Closes the active playback device.

### CloseCaptureDevice

```go
func (t *TeamSpeakCore) CloseCaptureDevice() error
```

Closes the active capture device.

### ActivateCaptureDevice

```go
func (t *TeamSpeakCore) ActivateCaptureDevice() error
```

Activates audio capture on the opened capture device.

---

## Audio Preprocessing & Playback Config

### GetPreProcessorInfo

```go
func (t *TeamSpeakCore) GetPreProcessorInfo(key string) string
```

Returns a preprocessor info value (e.g., voice activity level).

### GetPreProcessorConfig

```go
func (t *TeamSpeakCore) GetPreProcessorConfig(key string) string
```

Returns a preprocessor config value. Same as `GetPreProcessorInfo`.

### SetPreProcessorConfig

```go
func (t *TeamSpeakCore) SetPreProcessorConfig(key, value string)
```

Sets a preprocessor config value (AGC, denoise, VAD settings).

### GetPlaybackConfig

```go
func (t *TeamSpeakCore) GetPlaybackConfig(key string) string
```

Returns a playback config value.

### SetPlaybackConfig

```go
func (t *TeamSpeakCore) SetPlaybackConfig(key, value string)
```

Sets a playback config value.

### SetClientVolumeModifier

```go
func (t *TeamSpeakCore) SetClientVolumeModifier(clid int, modifier float32)
```

Adjusts the volume level for a specific client's audio output.

---

## Wave File Playback

### PlayWaveFile

```go
func (t *TeamSpeakCore) PlayWaveFile(path string) error
```

Plays a local wave file through the audio pipeline.

### PlayWaveFileHandle

```go
func (t *TeamSpeakCore) PlayWaveFileHandle(path string, loop bool) (int, error)
```

Plays a wave file and returns a handle for pause/stop control. `loop` enables looping.

### PauseWaveFileHandle

```go
func (t *TeamSpeakCore) PauseWaveFileHandle(handle int, pause bool) error
```

Pauses or resumes wave file playback.

### CloseWaveFileHandle

```go
func (t *TeamSpeakCore) CloseWaveFileHandle(handle int) error
```

Stops and closes wave file playback.

---

## Custom Audio Devices

### RegisterCustomDevice

```go
func (t *TeamSpeakCore) RegisterCustomDevice(deviceID, deviceDisplayName string, capFrequency, capChannels, playFrequency, playChannels int) error
```

Registers a custom audio I/O device for programmatic audio input/output.

```go
err := ts.RegisterCustomDevice("mydevice", "My Custom Device", 48000, 1, 48000, 2)
```

### UnregisterCustomDevice

```go
func (t *TeamSpeakCore) UnregisterCustomDevice(deviceID string) error
```

Unregisters a custom audio device.

### ProcessCustomCaptureData

```go
func (t *TeamSpeakCore) ProcessCustomCaptureData(deviceID string, pcm []int16) error
```

Feeds raw PCM audio data as capture input to a custom device.

### AcquireCustomPlaybackData

```go
func (t *TeamSpeakCore) AcquireCustomPlaybackData(deviceID string, samples int) ([]int16, error)
```

Reads mixed playback output as PCM from a custom device.

---

## Whisper List Management

### SetWhisperList

```go
func (t *TeamSpeakCore) SetWhisperList(targetChannelIDs []int, targetClientIDs []int) error
```

Sets the persistent whisper list. All subsequent voice packets will be whispered to these targets.

### IsWhispering

```go
func (t *TeamSpeakCore) IsWhispering() bool
```

Returns true if a whisper list is active (has target channels or clients).

### IsReceivingWhisper

```go
func (t *TeamSpeakCore) IsReceivingWhisper(clid int) bool
```

Checks if receiving a whisper from a specific client.

---

## Notifications & Subscriptions

### ServerNotifyRegister

```go
func (t *TeamSpeakCore) ServerNotifyRegister(event string, cid int) error
```

Registers for server event notifications. Events: `"server"`, `"channel"`, `"textserver"`, `"textchannel"`, `"textprivate"`. `cid` is only used for channel events (0 for all).

```go
err := ts.ServerNotifyRegister("channel", 0)
err := ts.ServerNotifyRegister("textprivate", 0)
```

### ServerNotifyUnregister

```go
func (t *TeamSpeakCore) ServerNotifyUnregister() error
```

Unregisters from all server event notifications.

---

## Event Handlers

Fine-grained per-event callbacks. Each receives a `map[string]string` with the raw notification parameters.

### HandleServerEdited

```go
func (t *TeamSpeakCore) HandleServerEdited(handler func(map[string]string))
```

Fires when server properties are edited.

### HandleServerUpdated

```go
func (t *TeamSpeakCore) HandleServerUpdated(handler func(map[string]string))
```

Fires when server state updates.

### HandleChannelEdited

```go
func (t *TeamSpeakCore) HandleChannelEdited(handler func(map[string]string))
```

Fires when a channel is edited.

### HandleChannelCreated

```go
func (t *TeamSpeakCore) HandleChannelCreated(handler func(map[string]string))
```

Fires when a channel is created.

### HandleChannelDeleted

```go
func (t *TeamSpeakCore) HandleChannelDeleted(handler func(map[string]string))
```

Fires when a channel is deleted.

### HandleChannelMoved

```go
func (t *TeamSpeakCore) HandleChannelMoved(handler func(map[string]string))
```

Fires when a channel is moved.

### HandleChannelDescriptionChanged

```go
func (t *TeamSpeakCore) HandleChannelDescriptionChanged(handler func(map[string]string))
```

Fires when a channel description changes.

### HandleChannelPasswordChanged

```go
func (t *TeamSpeakCore) HandleChannelPasswordChanged(handler func(map[string]string))
```

Fires when a channel password changes.

### HandleClientUpdated

```go
func (t *TeamSpeakCore) HandleClientUpdated(handler func(map[string]string))
```

Fires when a client's properties update.

### HandleTokenUsed

```go
func (t *TeamSpeakCore) HandleTokenUsed(handler func(map[string]string))
```

Fires when a privilege key (token) is used.

### HandleTalkStatusChange

```go
func (t *TeamSpeakCore) HandleTalkStatusChange(handler func(map[string]string))
```

Fires when a client's talk status changes (start/stop talking).

### HandleConnectStatusChange

```go
func (t *TeamSpeakCore) HandleConnectStatusChange(handler func(map[string]string))
```

Fires on connection status changes.

### HandleCurrentServerConnectionChanged

```go
func (t *TeamSpeakCore) HandleCurrentServerConnectionChanged(handler func(map[string]string))
```

Fires when the current server connection changes.

---

## Extended List Flags

### ClientListExtended

```go
func (t *TeamSpeakCore) ClientListExtended(flags ...string) ([]map[string]string, error)
```

Returns client list with extended info flags. Supported: `-uid`, `-away`, `-voice`, `-times`, `-groups`, `-info`, `-icon`, `-country`, `-ip`, `-badges`.

```go
clients, err := ts.ClientListExtended("-uid", "-away", "-country")
```

### ChannelListExtended

```go
func (t *TeamSpeakCore) ChannelListExtended(flags ...string) ([]map[string]string, error)
```

Returns channel list with extended info flags. Supported: `-topic`, `-flags`, `-voice`, `-limits`, `-icon`, `-secondsempty`, `-banners`.

### ServerListExtended

```go
func (t *TeamSpeakCore) ServerListExtended(flags ...string) ([]map[string]string, error)
```

Returns server list with extended info flags. Supported: `-uid`, `-short`, `-all`, `-onlyoffline`.

---

## Logging

### LogView

```go
func (t *TeamSpeakCore) LogView(lines, reverse, instance int, beginPos uint64) ([]map[string]string, error)
```

Retrieves server log entries (ServerQuery only). `reverse=1` for newest-first, `instance=1` for instance log.

### LogAdd

```go
func (t *TeamSpeakCore) LogAdd(logLevel int, logMsg string) error
```

Adds a custom entry to the server log. Log levels: 1=ERROR, 2=WARNING, 3=DEBUG, 4=INFO.

---

## Query Login Management

### QueryLoginAdd

```go
func (t *TeamSpeakCore) QueryLoginAdd(name string, cldbid int) (map[string]string, error)
```

Creates a ServerQuery login (SQ 3.6.0+). Returns `client_login_name` and `client_login_password`.

### QueryLoginDel

```go
func (t *TeamSpeakCore) QueryLoginDel(cldbid int) error
```

Deletes a ServerQuery login.

### QueryLoginList

```go
func (t *TeamSpeakCore) QueryLoginList() ([]map[string]string, error)
```

Lists all ServerQuery logins.

---

## API Key Management

### ApiKeyAdd

```go
func (t *TeamSpeakCore) ApiKeyAdd(scope string, lifetime int, cldbid int) (map[string]string, error)
```

Creates a new API key (SQ 3.12.0+). `scope`: `"manage"`, `"write"`, `"read"`. `lifetime` in days (0=permanent).

### ApiKeyDel

```go
func (t *TeamSpeakCore) ApiKeyDel(id int) error
```

Deletes an API key.

### ApiKeyList

```go
func (t *TeamSpeakCore) ApiKeyList(cldbid int, start, duration int) ([]map[string]string, error)
```

Lists API keys with optional client filter and pagination.

---

## Password Verification

### VerifyServerPassword

```go
func (t *TeamSpeakCore) VerifyServerPassword(password string) error
```

Checks if a password matches the virtual server password.

### VerifyChannelPassword

```go
func (t *TeamSpeakCore) VerifyChannelPassword(cid int, password string) error
```

Checks if a password matches a channel password.

---

## Server Instance Management

### HostInfo

```go
func (t *TeamSpeakCore) HostInfo() (map[string]string, error)
```

Returns host information (uptime, timestamp, total virtual servers).

### InstanceInfo

```go
func (t *TeamSpeakCore) InstanceInfo() (map[string]string, error)
```

Returns instance configuration (DB revision, file transfer port, etc.).

### InstanceEdit

```go
func (t *TeamSpeakCore) InstanceEdit(props map[string]string) error
```

Modifies instance configuration properties.

### BindingList

```go
func (t *TeamSpeakCore) BindingList() ([]map[string]string, error)
```

Lists bound IP addresses on the server.

---

## Bookmarks & Profiles

### GetBookmarkList

```go
func (t *TeamSpeakCore) GetBookmarkList() []map[string]string
```

Returns saved server bookmarks (local storage).

### CreateBookmark

```go
func (t *TeamSpeakCore) CreateBookmark(name, address, nickname, password string, isDefault bool)
```

Creates a new server bookmark.

```go
ts.CreateBookmark("My Server", "ts3.example.com:9987", "GoBot", "", false)
```

### GetProfileList

```go
func (t *TeamSpeakCore) GetProfileList() []map[string]string
```

Lists audio/identity profiles. Returns a default profile.

---

## Plugin Commands

### SendPluginCommand

```go
func (t *TeamSpeakCore) SendPluginCommand(name, data string, targetMode int) error
```

Sends a plugin command. `targetMode`: 0=current channel, 1=server, 2=client, 3=subscription.

---

## Raw Command Execution

### RawExec

```go
func (t *TeamSpeakCore) RawExec(cmd string) ([]map[string]string, error)
```

Sends a raw TS3 command string and returns parsed key-value response rows. For advanced use when no wrapper method exists.

```go
rows, err := ts.RawExec("clientlist -uid -times")
for _, row := range rows {
    fmt.Println(row["clid"], row["client_nickname"])
}
```

---

## Unsupported Core Methods

These Core interface methods are not applicable to TeamSpeak and return `ErrNotSupported`:

### StartCall / JoinGroupCall / EndCall / SetCallMuted

```go
func (t *TeamSpeakCore) StartCall(chatID string, video bool) (*CallSession, error)
func (t *TeamSpeakCore) JoinGroupCall(chatID string) (*CallSession, error)
func (t *TeamSpeakCore) EndCall(callID string) error
func (t *TeamSpeakCore) SetCallMuted(callID string, muted bool) error
```

Not supported. TS3 voice is channel-based, not call-based. Use `JoinChannel` + `SendVoice` instead.

### AcceptCall / DeclineCall

```go
func (t *TeamSpeakCore) AcceptCall(callID string) (*CallSession, error)
func (t *TeamSpeakCore) DeclineCall(callID string) error
```

Not supported. No call signaling protocol.

### MuteChat / ArchiveChat / MarkUnread / UnpinAllMessages

```go
func (t *TeamSpeakCore) MuteChat(chatID string, muted bool) error
func (t *TeamSpeakCore) ArchiveChat(chatID string, archived bool) error
func (t *TeamSpeakCore) MarkUnread(chatID string, unread bool) error
func (t *TeamSpeakCore) UnpinAllMessages(chatID string) error
```

Not supported. TS3 has no chat mute, archiving, unread tracking, or message pinning.

### SendLocation

```go
func (t *TeamSpeakCore) SendLocation(chatID string, lat float64, lon float64) (*Message, error)
```

Not supported. No location sharing.

### Other Unsupported

| Method | Reason |
|--------|--------|
| `EditMessage` | TS3 has no message editing |
| `DeleteMessage` | TS3 has no message deletion |
| `ForwardMessage` | No message forwarding |
| `ReactToMessage` | No reactions |
| `PinMessage` / `UnpinMessage` | No message pinning |
| `MarkAsRead` / `GetReadState` | No server-side read state |
| `SendImageBase64` | No inline images |
| `CreateTopic` | No forum topics |
| `GetFolders` / `CreateFolder` | No folder concept |
| `LeaveChat` | Use `JoinChannel` instead |
| `AddContact` / `DeleteContact` | No contact list |
| `CreatePoll` / `VotePoll` | No polls |
| `SendSticker` | No stickers |
