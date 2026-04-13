## Phase 6: TeamSpeak 3 — DONE (core); missing methods listed below

172 exported methods, ~5,369 lines. Real TS3 UDP client protocol (port 9987).
Additional ~43 client-accessible and SQ commands identified but not yet in core.

### Core Interface (55/55)

- [x] Name
- [x] Capabilities
- [x] Authenticate
- [x] Logout
- [x] GetDialogs
- [x] CreateGroup
- [x] CreateChannel
- [x] CreateTopic — returns ErrNotSupported
- [x] GetFolders — returns ErrNotSupported
- [x] CreateFolder — returns ErrNotSupported
- [x] SendMessage
- [x] GetMessages
- [x] EditMessage — returns ErrNotSupported
- [x] DeleteMessage — returns ErrNotSupported
- [x] ReplyToMessage — alias to SendMessage (no reply concept)
- [x] ForwardMessage — returns ErrNotSupported
- [x] ReactToMessage — returns ErrNotSupported
- [x] PinMessage — returns ErrNotSupported
- [x] UnpinMessage — returns ErrNotSupported
- [x] MarkAsRead — returns ErrNotSupported
- [x] GetReadState — returns ErrNotSupported
- [x] UploadFile
- [x] DownloadFile
- [x] SendImageBase64 — returns ErrNotSupported
- [x] StartCall — returns ErrNotSupported (voice is always-on)
- [x] JoinGroupCall — returns ErrNotSupported
- [x] EndCall — returns ErrNotSupported
- [x] SetCallMuted — returns ErrNotSupported
- [x] GetProfile
- [x] OnUpdate
- [x] Close
- [x] GetChatInfo
- [x] EditChatTitle
- [x] EditChatDescription
- [x] LeaveChat
- [x] GetInviteLink
- [x] AddMembers
- [x] RemoveMember
- [x] BanMember
- [x] UnbanMember
- [x] GetMembers
- [x] SetAdmin
- [x] GetContacts
- [x] AddContact — returns ErrNotSupported
- [x] DeleteContact — returns ErrNotSupported
- [x] BlockUser
- [x] UnblockUser
- [x] GetBlockedUsers
- [x] SearchMessages
- [x] SearchGlobal
- [x] SendTyping — returns ErrNotSupported
- [x] CreatePoll — returns ErrNotSupported
- [x] VotePoll — returns ErrNotSupported
- [x] SendSticker — returns ErrNotSupported
- [x] GetSessions
- [x] TerminateSession

### Client Self-Update (clientupdate) (16)

- [x] ClientUpdate
- [x] SetNickname
- [x] SetInputMuted
- [x] SetOutputMuted
- [x] SetInputHardware
- [x] SetOutputHardware
- [x] SetChannelCommander
- [x] SetRecording
- [x] SetAway
- [x] SetDescription
- [x] SetAvatar
- [x] RequestTalkPower
- [x] CancelTalkPowerRequest
- [x] SetBadges
- [x] SetMetaData
- [x] SetPhoneticNickname

### Channel Management (12)

- [x] CreateChannelFull
- [x] EditChannel
- [x] DeleteChannel
- [x] MoveChannel
- [x] FindChannel
- [x] GetChannelDescription
- [x] SubscribeChannel
- [x] SubscribeAllChannels
- [x] UnsubscribeChannel
- [x] UnsubscribeAllChannels
- [x] JoinChannel
- [x] RawExec

### Channel Permissions (6)

- [x] ChannelAddPerm
- [x] ChannelDelPerm
- [x] ChannelPermList
- [x] ChannelClientAddPerm
- [x] ChannelClientDelPerm
- [x] ChannelClientPermList

### Server Groups (11)

- [x] ServerGroupAdd
- [x] ServerGroupDel
- [x] ServerGroupClientList
- [x] ServerGroupPermList
- [x] ServerGroupAddPerm
- [x] ServerGroupDelPerm
- [x] ServerGroupCopy
- [x] ServerGroupRename
- [x] ServerGroupsByClientID
- [x] ServerGroupAutoAddPerm
- [x] ServerGroupAutoDelPerm

### Channel Groups (10)

- [x] ChannelGroupList
- [x] ChannelGroupAdd
- [x] ChannelGroupDel
- [x] ChannelGroupClientList
- [x] ChannelGroupPermList
- [x] ChannelGroupAddPerm
- [x] ChannelGroupDelPerm
- [x] ChannelGroupCopy
- [x] ChannelGroupRename
- [x] SetClientChannelGroup

### Client Management (12)

- [x] ClientDBInfo
- [x] ClientDBEdit
- [x] ClientDBDelete
- [x] ClientDBFind
- [x] ClientFind
- [x] ClientGetDBIDFromUID
- [x] ClientGetIDs
- [x] ClientGetNameFromUID
- [x] ClientGetNameFromDBID
- [x] ClientGetUIDFromCLID
- [x] ClientEdit
- [x] ClientPoke
- [x] ClientChatClosed

### Client Permissions (3)

- [x] ClientAddPerm
- [x] ClientDelPerm
- [x] ClientPermList

### Ban Management (2 extra)

- [x] BanAdd
- [x] BanDelAll

### Offline Messages (5)

- [x] MessageAdd
- [x] MessageDel
- [x] MessageGet
- [x] MessageList
- [x] MessageUpdateFlag

### Complaints (4)

- [x] ComplainAdd
- [x] ComplainDel
- [x] ComplainDelAll
- [x] ComplainList

### Privilege Keys (4)

- [x] PrivilegeKeyAdd
- [x] PrivilegeKeyDelete
- [x] PrivilegeKeyList
- [x] PrivilegeKeyUse

### Server Info & Config (7)

- [x] ServerInfo
- [x] ServerEdit
- [x] ServerVersion
- [x] WhoAmI
- [x] GetConnectionInfo
- [x] ServerRequestConnectionInfo
- [x] SetConnectionInfo

### Permission System (6)

- [x] PermissionList
- [x] PermFind
- [x] PermGet
- [x] PermOverview
- [x] PermIDGetByName
- [x] PermReset

### Custom Properties (4)

- [x] CustomInfo
- [x] CustomSearch
- [x] CustomSet
- [x] CustomDelete

### Plugin Commands (1)

- [x] SendPluginCommand

### File Transfer (7)

- [x] FTGetFileList
- [x] FTGetFileInfo
- [x] FTDeleteFile
- [x] FTCreateDir
- [x] FTRenameFile
- [x] FTStop
- [x] FTList

### Voice (5)

- [x] OnVoice
- [x] SendVoice
- [x] SendVoiceWhisper
- [x] SendVoiceGroupWhisper
- [x] GetBandwidthStats

### Verified Tests

- Live 2-client voice: 50 opus packets 0% loss, bidirectional byte-perfect
- Multi-server: 3/4 connectable servers pass voice 100%
- FLAC playback, voice recording, simultaneous stress test — all pass

### Not Added in Core

#### Client Management

- [ ] ClientKick — kick from channel or server (distinct from RemoveMember)
- [ ] ClientMute — local mute (ClientQuery)
- [ ] ClientUnmute — local unmute (ClientQuery)
- [ ] ClientChatComposing — typing indicator
- [ ] ClientDBList — list all known clients in server DB
- [ ] ClientVariable — get a specific client variable

#### Ban Management

- [ ] BanClient — ban an online client directly (by clid)
- [ ] BanDel — delete a specific ban rule by ID

#### Server Management (SQ-only)

- [ ] ServerList — list virtual servers
- [ ] ServerCreate — create a virtual server
- [ ] ServerDelete — delete a virtual server
- [ ] ServerStart — start a virtual server
- [ ] ServerStop — stop a virtual server
- [ ] ServerSnapshotCreate — create server snapshot
- [ ] ServerSnapshotDeploy — deploy/restore server snapshot
- [ ] ServerTempPasswordAdd — add a temporary server password
- [ ] ServerTempPasswordDel — delete a temporary server password
- [ ] ServerTempPasswordList — list temporary server passwords

#### File Transfer

- [ ] FTInitUpload — initialize a file upload transfer
- [ ] FTInitDownload — initialize a file download transfer

#### Event Registration

- [ ] ServerNotifyRegister — register for server event notifications
- [ ] ServerNotifyUnregister — unregister from server event notifications

#### Logging (SQ-only)

- [ ] LogView — view server log entries
- [ ] LogAdd — add a custom entry to the server log

#### Query Login Management (SQ 3.6.0+)

- [ ] QueryLoginAdd — create a ServerQuery login
- [ ] QueryLoginDel — delete a ServerQuery login
- [ ] QueryLoginList — list ServerQuery logins

#### API Key Management (SQ 3.12.0+)

- [ ] ApiKeyAdd — create an API key
- [ ] ApiKeyDel — delete an API key
- [ ] ApiKeyList — list API keys

#### Server Permissions

- [ ] ServerAddPerm — add server-level permissions
- [ ] ServerDelPerm — remove server-level permissions
- [ ] ServerPermList — list server-level permissions

#### Global Message (SQ-only)

- [ ] GlobalMessage — broadcast message to all virtual servers (gm)

#### Exported Wrappers Needed (used internally but not exposed)

- [ ] ServerGroupList() — `servergrouplist`: list all server groups
- [ ] ServerGroupAddClient(sgid, cldbid) — `servergroupaddclient`
- [ ] ServerGroupDelClient(sgid, cldbid) — `servergroupdelclient`
- [ ] ChannelGroupsByClientID(cldbid) — `channelgroupsbyclientid`: list channel groups for a client

---
