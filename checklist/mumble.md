# Mumble — Fresh Checklist

**Methods:** 233 exported | **Lines:** 7,846 | **File:** `go/cores/mumble.go`
**Protocol:** Mumble (TCP control + UDP voice, Protobuf messages, OCB2-AES crypto)
**Last updated:** 2026-04-13

## Categories

### Core Interface — Lifecycle & Identity (6)
- Name
- Capabilities
- Authenticate
- Close
- Logout
- OnUpdate

### Core Interface — Dialogs & Organization (6)
- GetDialogs
- CreateGroup
- CreateChannel
- CreateTopic
- GetFolders
- CreateFolder

### Core Interface — Messaging (12)
- SendMessage
- GetMessages
- EditMessage
- DeleteMessage
- ReplyToMessage
- ForwardMessage
- ReactToMessage
- PinMessage
- UnpinMessage
- MarkAsRead
- GetReadState
- SendTyping

### Core Interface — Files & Media (4)
- UploadFile
- DownloadFile
- SendImageBase64
- SendSticker

### Core Interface — Calls (4)
- StartCall
- JoinGroupCall
- EndCall
- SetCallMuted

### Core Interface — User & Profile (1)
- GetProfile

### Core Interface — Chat Management (5)
- GetChatInfo
- EditChatTitle
- EditChatDescription
- LeaveChat
- GetInviteLink

### Core Interface — Members & Moderation (6)
- AddMembers
- RemoveMember
- BanMember
- UnbanMember
- GetMembers
- SetAdmin

### Core Interface — Contacts & Blocking (6)
- GetContacts
- AddContact
- DeleteContact
- BlockUser
- UnblockUser
- GetBlockedUsers

### Core Interface — Search (2)
- SearchMessages
- SearchGlobal

### Core Interface — Polls (2)
- CreatePoll
- VotePoll

### Core Interface — Sessions & Misc (6)
- GetSessions
- TerminateSession
- MuteChat
- ArchiveChat
- MarkUnread
- UnpinAllMessages

### Core Interface — Location (1)
- SendLocation

### Client Protocol — Connection & Auth (5)
- ConnectFromURL
- Reconnect
- SetAutoReconnect
- LoadCertificate
- UpdateCertificate

### Client Protocol — Channel Operations (11)
- CreateTemporaryChannel
- DeleteChannel
- RenameChannel
- MoveChannel
- SetChannelMaxUsers
- SetChannelPosition
- GetChannelDescription
- GetChannelTree
- LinkChannels
- UnlinkChannels
- FlushPermissions

### Client Protocol — User Operations (8)
- MoveToChannel
- MoveUser
- RegisterSelf
- RegisterUser
- UnregisterUser
- QueryUsers
- GetRegisteredUsers
- SetComment

### Client Protocol — Server Interaction (8)
- SendVersion
- RequestBlob
- RequestNonceResync
- GetPublicServers
- SendPluginData
- SetPluginContext
- SetPluginIdentity
- SendWelcomeMessage

### Client Protocol — Permissions & ACL (5)
- GetACL
- SetACL
- GetPermissions
- GetCachedPermissions
- SetAccessTokens

### Client Protocol — Ban Management (4)
- GetBanList
- SetBanList
- AddBan
- RemoveBan

### Client Protocol — User State Modifiers (7)
- SelfMute
- SelfDeaf
- ServerMute
- ServerDeaf
- Suppress
- SetPrioritySpeaker
- SetRecording

### Client Protocol — Texture & Certificates (3)
- SetTexture
- GetUserTexture
- GetCertificateHash

### Client Protocol — Listeners (4)
- AddChannelListener
- RemoveChannelListener
- SetListenerVolume
- SetTemporaryAccessTokens

### Client Protocol — Context Actions (3)
- AddContextCallback
- RemoveContextCallback
- TriggerContextAction

### Client Protocol — Whisper & Targets (2)
- RedirectWhisperGroup
- SetVoiceTarget

### Client Protocol — Message Handlers (6)
- HandleCodecVersion
- HandleContextActionModify
- HandlePermissionDenied
- HandleReject
- HandleSuggestConfig
- HandleUserStats

### Client Protocol — User Stats & Info (3)
- GetUserStats
- GetUserComment
- GetServerConfig

### Client Protocol — Call Flow (2)
- AcceptCall
- DeclineCall

### Client Protocol — Tree Messages (1)
- SendTreeMessage

### Audio / Voice (12)
- SendVoice
- SendVoiceTCP
- SendPositionalAudio
- SendVoiceTerminator
- OnVoice
- OnAudioStream
- SetAudioBitrate
- SetAudioFrameSize
- SetPreferredCodec
- GetAudioStats
- ServerLoopback
- GetServerCertificate

### Ice Admin RPC — Server Management (10)
- ConnectAdmin
- DisconnectAdmin
- IceServerID
- IceServerIsRunning
- IceServerStart
- IceServerStop
- IceServerDelete
- IceIsListening
- IceStartListening
- IceStopListening

### Ice Admin RPC — User Management (9)
- IceGetUsers
- IceGetUserIds
- IceGetUserNames
- IceGetRegistration
- IceRegisterUser
- IceUnregisterUser
- IceUpdateRegistration
- IceKickUser
- IceVerifyPassword

### Ice Admin RPC — Channel Management (5)
- IceGetChannels
- IceGetChannelState
- IceSetChannelState
- IceAddChannel
- IceRemoveChannel

### Ice Admin RPC — State & Config (5)
- IceGetState
- IceSetState
- IceGetConf
- IceGetAllConf
- IceSetSuperuserPassword

### Ice Admin RPC — ACL & Permissions (4)
- IceGetACL
- IceSetACL
- IceEffectivePermissions
- IceHasPermission

### Ice Admin RPC — Bans & Log (3)
- IceGetBans
- IceSetBans
- IceGetLogLen

### Ice Admin RPC — Groups & Listeners (4)
- IceAddUserToGroup
- IceRemoveUserFromGroup
- IceGetListeningChannels
- IceGetListeningUsers

### Ice Admin RPC — Messaging (3)
- IceSendMessage
- IceSendMessageChannel
- IceSendWelcomeMessage

### Ice Admin RPC — Textures & Certificates (3)
- IceGetTexture
- IceSetTexture
- IceGetCertificateList

### Ice Admin RPC — Tree (1)
- IceGetTree

### Ice Admin RPC — Callbacks (11)
- IceMetaCallbackStarted
- IceMetaCallbackStopped
- IceServerCallbackChannelCreated
- IceServerCallbackChannelRemoved
- IceServerCallbackChannelStateChanged
- IceServerCallbackUserConnected
- IceServerCallbackUserDisconnected
- IceServerCallbackUserStateChanged
- IceServerCallbackUserTextMessage
- IceSetAuthenticator
- OnIceContextAction

### Ice Admin RPC — Authenticator (5)
- AuthenticatorAuthenticate
- AuthenticatorGetInfo
- AuthenticatorIdToName
- AuthenticatorIdToTexture
- AuthenticatorNameToId

### Ice Admin RPC — Updating Authenticator (4)
- UpdatingAuthRegisterUser
- UpdatingAuthSetInfo
- UpdatingAuthSetTexture
- UpdatingAuthUnregisterUser

### Ice Admin RPC — Meta (11)
- MetaAddCallback
- MetaRemoveCallback
- MetaGetAllServers
- MetaGetBootedServers
- MetaGetDefaultConf
- MetaGetServer
- MetaGetSlice
- MetaGetSliceChecksums
- MetaGetUptime
- MetaGetVersion
- MetaNewServer

### Ice Admin RPC — Server Info (2)
- GetServerUptime
- GetServerLog

### Debug (8)
- DebugBuildLegacyVoicePacket
- DebugBuildVoicePacket
- DebugCodecVersion
- DebugMySession
- DebugServerVersion
- DebugState
- DebugUserFlags
- DebugVoiceTunnelCount
