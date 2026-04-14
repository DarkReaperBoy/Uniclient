# TeamSpeak Checklist — 296 methods


## Core Interface
- [x] Capabilities
- [x] Close
- [x] Name
- [x] OnUpdate

## Authentication
- [x] Authenticate
- [x] Logout

## Dialogs & Chats
- [x] ArchiveChat
- [x] EditChatDescription
- [x] EditChatTitle
- [x] GetChatInfo
- [x] GetDialogs
- [x] LeaveChat
- [x] MuteChat

## Messaging
- [x] DeleteMessage
- [x] EditMessage
- [x] ForwardMessage
- [x] GetMessages
- [x] GetReadState
- [x] MarkAsRead
- [x] MarkUnread
- [x] PinMessage
- [x] ReactToMessage
- [x] ReplyToMessage
- [x] SendImageBase64
- [x] SendLocation
- [x] SendMessage
- [x] SendPluginCommand
- [x] SendSticker
- [x] SendTyping
- [x] UnpinAllMessages
- [x] UnpinMessage

## Media & Files
- [x] DownloadFile
- [x] UploadFile

## Calls
- [x] AcceptCall
- [x] DeclineCall
- [x] EndCall
- [x] SetCallMuted
- [x] StartCall

## Group Calls
- [x] JoinGroupCall

## Voice
- [x] IsReceivingWhisper
- [x] IsWhispering
- [x] OnVoice
- [x] SendVoice
- [x] SendVoiceGroupWhisper
- [x] SendVoiceWhisper
- [x] SetWhisperList
- [x] StartVoiceRecording
- [x] StopVoiceRecording

## Audio System
- [x] AcquireCustomPlaybackData
- [x] ActivateCaptureDevice
- [x] CloseCaptureDevice
- [x] ClosePlaybackDevice
- [x] CloseWaveFileHandle
- [x] CustomDelete
- [x] CustomInfo
- [x] CustomSearch
- [x] CustomSet
- [x] GetCaptureDeviceList
- [x] GetCaptureModeList
- [x] GetPlaybackConfig
- [x] GetPlaybackDeviceList
- [x] GetPlaybackModeList
- [x] GetPreProcessorConfig
- [x] GetPreProcessorInfo
- [x] OpenCaptureDevice
- [x] OpenPlaybackDevice
- [x] PauseWaveFileHandle
- [x] PlayWaveFile
- [x] PlayWaveFileHandle
- [x] ProcessCustomCaptureData
- [x] RegisterCustomDevice
- [x] Set3DListenerAttributes
- [x] Set3DWaveAttributes
- [x] SetChannel3DAttributes
- [x] SetClientVolumeModifier
- [x] SetPlaybackConfig
- [x] SetPreProcessorConfig
- [x] System3DSettings
- [x] UnregisterCustomDevice

## Groups & Channels
- [x] CreateChannel
- [x] CreateGroup
- [x] CreateTopic
- [x] DeleteChannel
- [x] JoinChannel

## Channel Operations
- [x] ChannelAddPerm
- [x] ChannelClientAddPerm
- [x] ChannelClientDelPerm
- [x] ChannelClientPermList
- [x] ChannelDelPerm
- [x] ChannelInfoRequest
- [x] ChannelListExtended
- [x] ChannelPermList

## Members & Admin
- [x] AddMembers
- [x] GetInviteLink
- [x] GetMembers
- [x] RemoveMember
- [x] SetAdmin

## Contacts & Users
- [x] AddContact
- [x] BlockUser
- [x] DeleteContact
- [x] GetBlockedUsers
- [x] GetContacts
- [x] SearchGlobal
- [x] UnblockUser

## Folders
- [x] CreateFolder
- [x] GetFolders

## Sessions
- [x] GetSessions
- [x] TerminateSession

## Polls
- [x] CreatePoll
- [x] VotePoll

## Search
- [x] SearchMessages

## Offline Messages
- [x] MessageAdd
- [x] MessageDel
- [x] MessageGet
- [x] MessageList
- [x] MessageUpdateFlag

## Event Handlers
- [x] HandleChannelCreated
- [x] HandleChannelDeleted
- [x] HandleChannelDescriptionChanged
- [x] HandleChannelEdited
- [x] HandleChannelMoved
- [x] HandleChannelPasswordChanged
- [x] HandleClientUpdated
- [x] HandleConnectStatusChange
- [x] HandleCurrentServerConnectionChanged
- [x] HandleServerEdited
- [x] HandleServerUpdated
- [x] HandleTalkStatusChange
- [x] HandleTokenUsed

## Server/Channel Groups
- [x] ChannelGroupAdd
- [x] ChannelGroupAddPerm
- [x] ChannelGroupClientList
- [x] ChannelGroupCopy
- [x] ChannelGroupDel
- [x] ChannelGroupDelPerm
- [x] ChannelGroupList
- [x] ChannelGroupPermList
- [x] ChannelGroupRename
- [x] ChannelGroupsByClientID
- [x] ServerGroupAdd
- [x] ServerGroupAddClient
- [x] ServerGroupAddPerm
- [x] ServerGroupAutoAddPerm
- [x] ServerGroupAutoDelPerm
- [x] ServerGroupClientList
- [x] ServerGroupCopy
- [x] ServerGroupDel
- [x] ServerGroupDelClient
- [x] ServerGroupDelPerm
- [x] ServerGroupList
- [x] ServerGroupPermList
- [x] ServerGroupRename
- [x] ServerGroupsByClientID

## File Transfer
- [x] FTCreateDir
- [x] FTDeleteFile
- [x] FTGetFileInfo
- [x] FTGetFileList
- [x] FTInitDownload
- [x] FTInitUpload
- [x] FTList
- [x] FTRenameFile
- [x] FTStop

## Privilege Keys
- [x] PrivilegeKeyAdd
- [x] PrivilegeKeyDelete
- [x] PrivilegeKeyList
- [x] PrivilegeKeyUse

## Complaints
- [x] ComplainAdd
- [x] ComplainDel
- [x] ComplainDelAll
- [x] ComplainList

## Offline Messages

## Bans
- [x] BanAdd
- [x] BanAddMyTSID
- [x] BanClient
- [x] BanClientDBID
- [x] BanDel
- [x] BanDelAll
- [x] BanListPaginated
- [x] BanMember
- [x] UnbanMember

## API Keys
- [x] ApiKeyAdd
- [x] ApiKeyDel
- [x] ApiKeyList

## Query Logins
- [x] QueryLoginAdd
- [x] QueryLoginDel
- [x] QueryLoginList

## Server Management
- [x] ServerAddPerm
- [x] ServerCreate
- [x] ServerDelete
- [x] ServerDelPerm
- [x] ServerEdit
- [x] ServerIdGetByPort
- [x] ServerInfo
- [x] ServerList
- [x] ServerListExtended
- [x] ServerNotifyRegister
- [x] ServerNotifyUnregister
- [x] ServerPermList
- [x] ServerProcessStop
- [x] ServerRequestConnectionInfo
- [x] ServerSnapshotCreate
- [x] ServerSnapshotDeploy
- [x] ServerSnapshotDeployKeepFiles
- [x] ServerSnapshotPassword
- [x] ServerStart
- [x] ServerStop
- [x] ServerTempPasswordAdd
- [x] ServerTempPasswordDel
- [x] ServerTempPasswordList
- [x] ServerVersion

## Client Operations
- [x] ClientAddPerm
- [x] ClientAddServerGroup
- [x] ClientChatClosed
- [x] ClientChatComposing
- [x] ClientDBDelete
- [x] ClientDBEdit
- [x] ClientDBFind
- [x] ClientDBInfo
- [x] ClientDBList
- [x] ClientDelPerm
- [x] ClientDelServerGroup
- [x] ClientEdit
- [x] ClientFind
- [x] ClientGetDBIDFromUID
- [x] ClientGetIDs
- [x] ClientGetNameFromDBID
- [x] ClientGetNameFromUID
- [x] ClientGetUIDFromCLID
- [x] ClientKick
- [x] ClientListExtended
- [x] ClientMute
- [x] ClientPermList
- [x] ClientPoke
- [x] ClientUnmute
- [x] ClientUpdate
- [x] ClientVariable

## Permissions
- [x] PermCommandsPermSID
- [x] PermFind
- [x] PermGet
- [x] PermIDGetByName
- [x] PermissionList
- [x] PermissionListNew
- [x] PermOverview
- [x] PermReset

## Bookmarks & Profiles
- [x] CreateBookmark
- [x] GetBookmarkList
- [x] GetProfile
- [x] GetProfileList

## Queries & Info
- [x] GetAvatar
- [x] GetBandwidthStats
- [x] GetChannelDescription
- [x] GetConnectionInfo

## Settings & Configuration
- [x] SetAvatar
- [x] SetAway
- [x] SetBadges
- [x] SetChannelCommander
- [x] SetClientChannelGroup
- [x] SetConnectionInfo
- [x] SetDescription
- [x] SetInputHardware
- [x] SetInputMuted
- [x] SetIsTalker
- [x] SetMetaData
- [x] SetNickname
- [x] SetOutputHardware
- [x] SetOutputMuted
- [x] SetPhoneticNickname
- [x] SetRecording

## Creation
- [x] CreateChannelFull

## Editing
- [x] EditChannel

## Requests
- [x] RequestClientEditDescription
- [x] RequestClientsKickFromChannel
- [x] RequestClientsKickFromServer
- [x] RequestClientsMove
- [x] RequestInfoUpdate
- [x] RequestMuteClientsTemporary
- [x] RequestTalkPower
- [x] RequestUnmuteClientsTemporary

## Event Handlers

## Other
- [x] BindingList
- [x] CancelTalkPowerRequest
- [x] DecodeLegacyCodec
- [x] FindChannel
- [x] GlobalMessage
- [x] HostInfo
- [x] InstanceEdit
- [x] InstanceInfo
- [x] LogAdd
- [x] LogView
- [x] MoveChannel
- [x] RawExec
- [x] SubscribeAllChannels
- [x] SubscribeChannel
- [x] UnsubscribeAllChannels
- [x] UnsubscribeChannel
- [x] VerifyChannelPassword
- [x] VerifyServerPassword
- [x] WhoAmI
