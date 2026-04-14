# TeamSpeak — Fresh Checklist

**Methods:** 296 exported | **Lines:** 6,893 | **File:** `go/cores/teamspeak.go`
**Protocol:** TeamSpeak 3 (UDP client protocol, ServerQuery)
**Last updated:** 2026-04-13

## Audit Notes (2026-04-13)
- **No true duplicates found.** `ClientKick` (single, flexible reasonID) vs `RequestClientsKickFromChannel/Server` (batch, hardcoded) are complementary. `ClientMute/Unmute` (local, `clientmute` cmd) vs `RequestMuteClientsTemporary` (server-side, `clientedit client_output_muted`) are fundamentally different operations.
- **No dead unexported code.** All helper functions are called at least once.
- **SendTyping** implemented for DM chats (delegates to `clientchatcomposing`). Still returns ErrNotSupported for channel/server chats.
- **DecodeLegacyCodec** is a correct stub — Speex/CELT require native C decoders (CGo forbidden).
- **Correct ErrNotSupported stubs:** EditMessage, DeleteMessage, ForwardMessage, ReactToMessage, PinMessage, UnpinMessage, UnpinAllMessages, polls, stickers, location, contacts add/delete, read state, folders, topics, leave chat, call methods (TS3 uses channel-join model).
- Codec/whisper constants are defined but only used as exported API documentation for callers — intentionally kept.

## Categories

### Connection & Authentication (5)
- [ ] Authenticate
- [ ] Close
- [ ] Logout
- [ ] Name
- [ ] WhoAmI

### Server Management (27)
- [ ] GlobalMessage
- [ ] HostInfo
- [ ] InstanceEdit
- [ ] InstanceInfo
- [ ] ServerCreate
- [ ] ServerDelete
- [ ] ServerEdit
- [ ] ServerIdGetByPort
- [ ] ServerInfo
- [ ] ServerList
- [ ] ServerListExtended
- [ ] ServerProcessStop
- [ ] ServerRequestConnectionInfo
- [ ] ServerSnapshotCreate
- [ ] ServerSnapshotDeploy
- [ ] ServerSnapshotDeployKeepFiles
- [ ] ServerSnapshotPassword
- [ ] ServerStart
- [ ] ServerStop
- [ ] ServerTempPasswordAdd
- [ ] ServerTempPasswordDel
- [ ] ServerTempPasswordList
- [ ] ServerVersion
- [ ] VerifyServerPassword
- [ ] GetBandwidthStats
- [ ] GetConnectionInfo
- [ ] SetConnectionInfo

### Server Permissions (8)
- [ ] ServerAddPerm
- [ ] ServerDelPerm
- [ ] ServerPermList
- [ ] PermCommandsPermSID
- [ ] PermFind
- [ ] PermGet
- [ ] PermIDGetByName
- [ ] PermissionList

### Permission Management — Extended (3)
- [ ] PermissionListNew
- [ ] PermOverview
- [ ] PermReset

### Channel Management (13)
- [ ] CreateChannel
- [ ] CreateChannelFull
- [ ] DeleteChannel
- [ ] EditChannel
- [ ] FindChannel
- [ ] MoveChannel
- [ ] ChannelInfoRequest
- [ ] ChannelListExtended
- [ ] GetChannelDescription
- [ ] JoinChannel
- [ ] VerifyChannelPassword
- [ ] SubscribeChannel
- [ ] UnsubscribeChannel

### Channel Subscriptions (2)
- [ ] SubscribeAllChannels
- [ ] UnsubscribeAllChannels

### Channel Permissions (4)
- [ ] ChannelAddPerm
- [ ] ChannelDelPerm
- [ ] ChannelPermList
- [ ] SetChannel3DAttributes

### Channel Client Permissions (3)
- [ ] ChannelClientAddPerm
- [ ] ChannelClientDelPerm
- [ ] ChannelClientPermList

### Channel Groups (8)
- [ ] ChannelGroupAdd
- [ ] ChannelGroupAddPerm
- [ ] ChannelGroupClientList
- [ ] ChannelGroupCopy
- [ ] ChannelGroupDel
- [ ] ChannelGroupDelPerm
- [ ] ChannelGroupList
- [ ] ChannelGroupPermList

### Channel Group Extras (2)
- [ ] ChannelGroupRename
- [ ] ChannelGroupsByClientID

### Server Groups (14)
- [ ] ServerGroupAdd
- [ ] ServerGroupAddClient
- [ ] ServerGroupAddPerm
- [ ] ServerGroupAutoAddPerm
- [ ] ServerGroupAutoDelPerm
- [ ] ServerGroupClientList
- [ ] ServerGroupCopy
- [ ] ServerGroupDel
- [ ] ServerGroupDelClient
- [ ] ServerGroupDelPerm
- [ ] ServerGroupList
- [ ] ServerGroupPermList
- [ ] ServerGroupRename
- [ ] ServerGroupsByClientID

### Client Management (20)
- [ ] ClientAddPerm
- [ ] ClientDBDelete
- [ ] ClientDBEdit
- [ ] ClientDBFind
- [ ] ClientDBInfo
- [ ] ClientDBList
- [ ] ClientDelPerm
- [ ] ClientEdit
- [ ] ClientFind
- [ ] ClientGetDBIDFromUID
- [ ] ClientGetIDs
- [ ] ClientGetNameFromDBID
- [ ] ClientGetNameFromUID
- [ ] ClientGetUIDFromCLID
- [ ] ClientListExtended
- [ ] ClientPermList
- [ ] ClientUpdate
- [ ] ClientVariable
- [ ] ClientAddServerGroup
- [ ] ClientDelServerGroup

### Client Actions (10)
- [ ] ClientKick
- [ ] ClientMute
- [ ] ClientPoke
- [ ] ClientUnmute
- [ ] ClientChatClosed
- [ ] ClientChatComposing
- [ ] RequestClientEditDescription
- [ ] RequestClientsKickFromChannel
- [ ] RequestClientsKickFromServer
- [ ] RequestClientsMove

### Client Settings (10)
- [ ] SetAvatar
- [ ] SetAway
- [ ] SetBadges
- [ ] SetChannelCommander
- [ ] SetClientChannelGroup
- [ ] SetClientVolumeModifier
- [ ] SetDescription
- [ ] SetMetaData
- [ ] SetNickname
- [ ] SetPhoneticNickname

### Muting & Talk Power (6)
- [ ] RequestMuteClientsTemporary
- [ ] RequestUnmuteClientsTemporary
- [ ] RequestTalkPower
- [ ] CancelTalkPowerRequest
- [ ] SetIsTalker
- [ ] SetRecording

### Ban Management (7)
- [ ] BanAdd
- [ ] BanAddMyTSID
- [ ] BanClient
- [ ] BanClientDBID
- [ ] BanDel
- [ ] BanDelAll
- [ ] BanListPaginated

### Complain System (4)
- [ ] ComplainAdd
- [ ] ComplainDel
- [ ] ComplainDelAll
- [ ] ComplainList

### Privilege Keys (Tokens) (4)
- [ ] PrivilegeKeyAdd
- [ ] PrivilegeKeyDelete
- [ ] PrivilegeKeyList
- [ ] PrivilegeKeyUse

### Offline Messages (5)
- [ ] MessageAdd
- [ ] MessageDel
- [ ] MessageGet
- [ ] MessageList
- [ ] MessageUpdateFlag

### Logging (2)
- [ ] LogAdd
- [ ] LogView

### Custom Properties (4)
- [ ] CustomDelete
- [ ] CustomInfo
- [ ] CustomSearch
- [ ] CustomSet

### Server Notifications (2)
- [ ] ServerNotifyRegister
- [ ] ServerNotifyUnregister

### Query Login Management (3)
- [ ] QueryLoginAdd
- [ ] QueryLoginDel
- [ ] QueryLoginList

### API Key Management (3)
- [ ] ApiKeyAdd
- [ ] ApiKeyDel
- [ ] ApiKeyList

### File Transfer (10)
- [ ] DownloadFile
- [ ] UploadFile
- [ ] FTCreateDir
- [ ] FTDeleteFile
- [ ] FTGetFileInfo
- [ ] FTGetFileList
- [ ] FTInitDownload
- [ ] FTInitUpload
- [ ] FTList
- [ ] FTRenameFile

### File Transfer Control (1)
- [ ] FTStop

### Voice & Audio — Capture (5)
- [ ] ActivateCaptureDevice
- [ ] CloseCaptureDevice
- [ ] OpenCaptureDevice
- [ ] GetCaptureDeviceList
- [ ] GetCaptureModeList

### Voice & Audio — Playback (6)
- [ ] ClosePlaybackDevice
- [ ] OpenPlaybackDevice
- [ ] GetPlaybackConfig
- [ ] GetPlaybackDeviceList
- [ ] GetPlaybackModeList
- [ ] SetPlaybackConfig

### Voice & Audio — Wave Files (4)
- [ ] CloseWaveFileHandle
- [ ] PauseWaveFileHandle
- [ ] PlayWaveFile
- [ ] PlayWaveFileHandle

### Voice & Audio — Preprocessor (3)
- [ ] GetPreProcessorConfig
- [ ] GetPreProcessorInfo
- [ ] SetPreProcessorConfig

### Voice & Audio — Input/Output (4)
- [ ] SetInputHardware
- [ ] SetInputMuted
- [ ] SetOutputHardware
- [ ] SetOutputMuted

### Voice & Audio — 3D Sound (2)
- [ ] Set3DListenerAttributes
- [ ] Set3DWaveAttributes

### Voice & Audio — 3D System (1)
- [ ] System3DSettings

### Voice & Audio — Custom Devices (3)
- [ ] AcquireCustomPlaybackData
- [ ] ProcessCustomCaptureData
- [ ] RegisterCustomDevice

### Voice & Audio — Custom Device Cleanup (1)
- [ ] UnregisterCustomDevice

### Voice & Audio — Whisper (4)
- [ ] IsReceivingWhisper
- [ ] IsWhispering
- [ ] SendVoiceGroupWhisper
- [ ] SendVoiceWhisper

### Voice & Audio — Whisper List (1)
- [ ] SetWhisperList

### Voice & Audio — Recording & Codec (4)
- [ ] StartVoiceRecording
- [ ] StopVoiceRecording
- [ ] DecodeLegacyCodec
- [ ] SendVoice

### Voice & Audio — Callbacks (2)
- [ ] OnVoice
- [ ] HandleTalkStatusChange

### Calls (6)
- [ ] AcceptCall
- [ ] DeclineCall
- [ ] EndCall
- [ ] JoinGroupCall
- [ ] StartCall
- [ ] SetCallMuted

### Messaging (11)
- [ ] SendMessage
- [ ] EditMessage
- [ ] DeleteMessage
- [ ] ForwardMessage
- [ ] ReplyToMessage
- [ ] ReactToMessage
- [ ] PinMessage
- [ ] UnpinMessage
- [ ] UnpinAllMessages
- [ ] SendImageBase64
- [ ] SendSticker

### Messaging — Extras (3)
- [ ] SendLocation
- [ ] SendTyping (implemented for DMs, ErrNotSupported for channel/server)
- [ ] SendPluginCommand

### Chat Management (9)
- [ ] ArchiveChat
- [ ] EditChatDescription
- [ ] EditChatTitle
- [ ] GetChatInfo
- [ ] GetReadState
- [ ] LeaveChat
- [ ] MarkAsRead
- [ ] MarkUnread
- [ ] MuteChat

### Contacts & Users (6)
- [ ] AddContact
- [ ] DeleteContact
- [ ] GetContacts
- [ ] BlockUser
- [ ] UnblockUser
- [ ] GetBlockedUsers

### Groups & Members (6)
- [ ] AddMembers
- [ ] BanMember
- [ ] CreateGroup
- [ ] GetMembers
- [ ] RemoveMember
- [ ] UnbanMember

### Group Extras (3)
- [ ] SetAdmin
- [ ] GetInviteLink
- [ ] GetDialogs

### Folders & Topics (3)
- [ ] CreateFolder
- [ ] GetFolders
- [ ] CreateTopic

### Polls (2)
- [ ] CreatePoll
- [ ] VotePoll

### Profile & Bookmarks (4)
- [ ] GetProfile
- [ ] GetProfileList
- [ ] CreateBookmark
- [ ] GetBookmarkList

### Search (2)
- [ ] SearchGlobal
- [ ] SearchMessages

### Messages — Fetching (1)
- [ ] GetMessages

### Sessions (2)
- [ ] GetSessions
- [ ] TerminateSession

### Avatars (1)
- [ ] GetAvatar

### Binding & Info (2)
- [ ] BindingList
- [ ] Capabilities

### Raw Execution (1)
- [ ] RawExec

### Request & Info Updates (2)
- [ ] OnUpdate
- [ ] RequestInfoUpdate

### Event Handlers (10)
- [ ] HandleChannelCreated
- [ ] HandleChannelDeleted
- [ ] HandleChannelDescriptionChanged
- [ ] HandleChannelEdited
- [ ] HandleChannelMoved
- [ ] HandleChannelPasswordChanged
- [ ] HandleClientUpdated
- [ ] HandleConnectStatusChange
- [ ] HandleCurrentServerConnectionChanged
- [ ] HandleServerEdited

### Event Handlers — Extras (2)
- [ ] HandleServerUpdated
- [ ] HandleTokenUsed
