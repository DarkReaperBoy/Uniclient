# Mumble Checklist — 233 methods


## Core Interface
- [x] Capabilities
- [x] Close
- [x] Name
- [x] OnUpdate

## Authentication
- [x] Authenticate
- [x] Logout

## Connection
- [x] ConnectFromURL
- [x] Reconnect
- [x] SetAutoReconnect

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
- [x] SendSticker
- [x] SendTreeMessage
- [x] SendTyping
- [x] SendVersion
- [x] SendWelcomeMessage
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

## Voice & Audio
- [x] GetAudioStats
- [x] OnAudioStream
- [x] OnVoice
- [x] SendPositionalAudio
- [x] SendVoice
- [x] SendVoiceTCP
- [x] SendVoiceTerminator
- [x] ServerLoopback
- [x] SetAudioBitrate
- [x] SetAudioFrameSize
- [x] SetPreferredCodec
- [x] SetVoiceTarget

## Groups & Channels
- [x] CreateGroup
- [x] CreateTopic

## Channel Operations
- [x] CreateChannel
- [x] CreateTemporaryChannel
- [x] DeleteChannel
- [x] GetChannelDescription
- [x] GetChannelTree
- [x] LinkChannels
- [x] MoveChannel
- [x] MoveToChannel
- [x] RenameChannel
- [x] SetChannelMaxUsers
- [x] SetChannelPosition
- [x] UnlinkChannels

## Members & Admin
- [x] AddMembers
- [x] GetInviteLink
- [x] GetMembers
- [x] RemoveMember
- [x] SetAdmin
- [x] UnbanMember

## Contacts & Users
- [x] AddContact
- [x] BlockUser
- [x] DeleteContact
- [x] GetBlockedUsers
- [x] GetContacts
- [x] GetProfile
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

## Event Handlers
- [x] HandleCodecVersion
- [x] HandleContextActionModify
- [x] HandleReject
- [x] HandleSuggestConfig
- [x] HandleUserStats

## Bans
- [x] AddBan
- [x] BanMember
- [x] GetBanList
- [x] RemoveBan
- [x] SetBanList

## Ice Admin
- [x] ConnectAdmin
- [x] DisconnectAdmin
- [x] IceAddChannel
- [x] IceAddUserToGroup
- [x] IceEffectivePermissions
- [x] IceGetACL
- [x] IceGetAllConf
- [x] IceGetBans
- [x] IceGetCertificateList
- [x] IceGetChannels
- [x] IceGetChannelState
- [x] IceGetConf
- [x] IceGetListeningChannels
- [x] IceGetListeningUsers
- [x] IceGetLogLen
- [x] IceGetRegistration
- [x] IceGetState
- [x] IceGetTexture
- [x] IceGetTree
- [x] IceGetUserIds
- [x] IceGetUserNames
- [x] IceGetUsers
- [x] IceHasPermission
- [x] IceIsListening
- [x] IceKickUser
- [x] IceMetaCallbackStarted
- [x] IceMetaCallbackStopped
- [x] IceRegisterUser
- [x] IceRemoveChannel
- [x] IceRemoveUserFromGroup
- [x] IceSendMessage
- [x] IceSendMessageChannel
- [x] IceSendWelcomeMessage
- [x] IceServerCallbackChannelCreated
- [x] IceServerCallbackChannelRemoved
- [x] IceServerCallbackChannelStateChanged
- [x] IceServerCallbackUserConnected
- [x] IceServerCallbackUserDisconnected
- [x] IceServerCallbackUserStateChanged
- [x] IceServerCallbackUserTextMessage
- [x] IceServerDelete
- [x] IceServerID
- [x] IceServerIsRunning
- [x] IceServerStart
- [x] IceServerStop
- [x] IceSetACL
- [x] IceSetAuthenticator
- [x] IceSetBans
- [x] IceSetChannelState
- [x] IceSetState
- [x] IceSetSuperuserPassword
- [x] IceSetTexture
- [x] IceStartListening
- [x] IceStopListening
- [x] IceUnregisterUser
- [x] IceUpdateRegistration
- [x] IceVerifyPassword
- [x] OnIceContextAction

## Meta (Multi-Server)
- [x] MetaAddCallback
- [x] MetaGetAllServers
- [x] MetaGetBootedServers
- [x] MetaGetDefaultConf
- [x] MetaGetServer
- [x] MetaGetSlice
- [x] MetaGetSliceChecksums
- [x] MetaGetUptime
- [x] MetaGetVersion
- [x] MetaNewServer
- [x] MetaRemoveCallback

## Authenticator
- [x] AuthenticatorAuthenticate
- [x] AuthenticatorGetInfo
- [x] AuthenticatorIdToName
- [x] AuthenticatorIdToTexture
- [x] AuthenticatorNameToId
- [x] UpdatingAuthRegisterUser
- [x] UpdatingAuthSetInfo
- [x] UpdatingAuthSetTexture
- [x] UpdatingAuthUnregisterUser

## ACL & Permissions
- [x] FlushPermissions
- [x] GetACL
- [x] GetCachedPermissions
- [x] GetPermissions
- [x] HandlePermissionDenied
- [x] SetACL

## User Registration
- [x] GetRegisteredUsers
- [x] RegisterSelf
- [x] RegisterUser
- [x] UnregisterUser

## Channel Listeners
- [x] AddChannelListener
- [x] RemoveChannelListener
- [x] SetListenerVolume

## Plugins & Context Actions
- [x] AddContextCallback
- [x] RemoveContextCallback
- [x] SendPluginData
- [x] SetPluginContext
- [x] SetPluginIdentity
- [x] TriggerContextAction

## Certificates
- [x] GetCertificateHash
- [x] GetServerCertificate
- [x] LoadCertificate
- [x] UpdateCertificate

## Debug
- [x] DebugBuildLegacyVoicePacket
- [x] DebugBuildVoicePacket
- [x] DebugCodecVersion
- [x] DebugMySession
- [x] DebugServerVersion
- [x] DebugState
- [x] DebugUserFlags
- [x] DebugVoiceTunnelCount

## Queries & Info
- [x] GetPublicServers
- [x] GetServerConfig
- [x] GetServerLog
- [x] GetServerUptime
- [x] GetUserComment
- [x] GetUserStats
- [x] GetUserTexture

## Settings & Configuration
- [x] SetAccessTokens
- [x] SetComment
- [x] SetPrioritySpeaker
- [x] SetRecording
- [x] SetTemporaryAccessTokens
- [x] SetTexture

## Requests
- [x] RequestBlob
- [x] RequestNonceResync

## Event Handlers

## Other
- [x] MoveUser
- [x] QueryUsers
- [x] RedirectWhisperGroup
- [x] SelfDeaf
- [x] SelfMute
- [x] ServerDeaf
- [x] ServerMute
- [x] Suppress
