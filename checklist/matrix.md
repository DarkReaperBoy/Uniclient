# Matrix Checklist — 240 methods


## Core Interface
- [x] Capabilities
- [x] Close
- [x] Name
- [x] OnUpdate

## Authentication
- [x] Authenticate
- [x] ChangePassword
- [x] DeactivateAccount
- [x] Logout
- [x] Register

## Authentication Extensions
- [x] CheckRegistrationToken
- [x] DeviceAuthGrant
- [x] GetAuthMetadata
- [x] GetLoginFlows
- [x] GetLoginToken
- [x] RefreshToken
- [x] SSORedirect
- [x] SSORedirectIdP

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
- [x] SendEmoteMessage
- [x] SendImageBase64
- [x] SendLocation
- [x] SendLocationMessage
- [x] SendMessage
- [x] SendPrivateReadReceipt
- [x] SendSecretRequest
- [x] SendSecretSend
- [x] SendSticker
- [x] SendToDevice
- [x] SendTyping
- [x] UnpinAllMessages
- [x] UnpinMessage

## Media & Files
- [x] DownloadFile
- [x] UploadFile

## Calls
- [x] AcceptCall
- [x] AcceptCallSelectAnswer
- [x] CallNotify
- [x] CallReplaces
- [x] DeclineCall
- [x] EndCall
- [x] RejectCall
- [x] SendCallAssertedIdentity
- [x] SendCallCandidates
- [x] SendCallNegotiate
- [x] SetCallAudioSink
- [x] SetCallAudioSource
- [x] SetCallMuted
- [x] StartCall

## Group Calls
- [x] GroupCallEncryptionKeys
- [x] JoinGroupCall
- [x] SendGroupCallEncryptionKeys

## Groups & Channels
- [x] CreateChannel
- [x] CreateGroup
- [x] CreateTopic

## Members & Admin
- [x] AddMembers
- [x] BanMember
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
- [x] SearchUsers

## Event Handlers
- [x] HandleUserLimitExceeded

## Spaces
- [x] AddSpaceChild
- [x] GetSpaceChildren
- [x] RemoveSpaceChild

## Threads
- [x] GetThreadReplies
- [x] GetThreads

## Push Rules & Notifications
- [x] DeletePushRule
- [x] EnablePushRule
- [x] GetPushers
- [x] GetPushRuleActions
- [x] GetPushRuleEnabled
- [x] GetPushRules
- [x] SetPusher
- [x] SetPushRule
- [x] SetPushRuleActions

## Cross-Signing & Secrets
- [x] DeleteDehydratedDevice
- [x] GenerateCrossSigningKeys
- [x] GetDehydratedDevice
- [x] GetDehydratedDeviceEvents
- [x] GetSecretStorageKey
- [x] SetDehydratedDevice
- [x] SetSecretStorageKey
- [x] UploadCrossSigningKeys

## Third-Party Identity
- [x] Add3PID
- [x] Bind3PID
- [x] Delete3PID
- [x] Delete3PIDByAddress
- [x] Get3PIDs
- [x] GetThirdPartyInvites
- [x] GetThirdPartyProtocols
- [x] InviteBy3PID
- [x] LookupThirdPartyLocation
- [x] LookupThirdPartyUser
- [x] Unbind3PID

## Sync
- [x] SlidingSync
- [x] SyncStateAfter

## RTC & Location
- [x] DeclineRTCSession
- [x] GetRTCTransports
- [x] SendLiveLocation
- [x] SendRTCNotification
- [x] SetRTCMemberState

## Queries & Info
- [x] GetAccountData
- [x] GetCapabilities
- [x] GetClientWellKnown
- [x] GetDeviceInfo
- [x] GetDirectChats
- [x] GetEncryptionInfo
- [x] GetEvent
- [x] GetEventContext
- [x] GetFilter
- [x] GetForgetOnLeave
- [x] GetFullyReadMarker
- [x] GetIgnoredUsers
- [x] GetKeyBackupInfo
- [x] GetKeyChanges
- [x] GetMediaConfig
- [x] GetMediaConfigAuth
- [x] GetMutualRooms
- [x] GetNonCrossSignedExclusion
- [x] GetNotifications
- [x] GetPresence
- [x] GetProfileField
- [x] GetProfileFieldsCap
- [x] GetPublicRooms
- [x] GetRecentEmoji
- [x] GetRoomAccountData
- [x] GetRoomAliases
- [x] GetRoomCreationEvent
- [x] GetRoomState
- [x] GetRoomSummary
- [x] GetRoomTombstone
- [x] GetRoomVisibility
- [x] GetSupportContacts
- [x] GetTags
- [x] GetTurnServer
- [x] GetURLPreview
- [x] GetURLPreviewAuth
- [x] GetVersions

## Settings & Configuration
- [x] SetAccountData
- [x] SetAvatar
- [x] SetCanonicalAlias
- [x] SetDeviceName
- [x] SetDirectChat
- [x] SetDisplayName
- [x] SetGuestAccess
- [x] SetHistoryVisibility
- [x] SetInviteBlocking
- [x] SetJoinRules
- [x] SetPolicyRule
- [x] SetPowerLevels
- [x] SetPresence
- [x] SetProfileField
- [x] SetReadMarkers
- [x] SetRoomAccountData
- [x] SetRoomAlias
- [x] SetRoomAvatar
- [x] SetRoomTag
- [x] SetRoomVisibility
- [x] SetServerACL
- [x] SetTimezone

## Deletion
- [x] DeleteDevices
- [x] DeleteProfileField
- [x] DeleteRoomAlias
- [x] RemoveRoomTag

## Creation
- [x] CreateDelayedEvent
- [x] CreateFilter
- [x] CreateKeyBackup
- [x] CreateMXCURI

## Requests
- [x] RequestEmailToken
- [x] RequestMsisdnToken
- [x] RequestOpenIDToken

## Join & Leave
- [x] JoinRoom
- [x] JoinRoomByAlias

## Event Handlers

## Other
- [x] AcceptSASVerification
- [x] CancelVerification
- [x] CheckUsernameAvailability
- [x] ConfirmSASEmojis
- [x] DownloadMediaAuth
- [x] DownloadMediaAuthFilename
- [x] DownloadThumbnail
- [x] DownloadThumbnailAuth
- [x] EnableEncryption
- [x] EndPoll
- [x] ExportKeys
- [x] ForgetRoom
- [x] ImportKeys
- [x] KnockRoom
- [x] LockUser
- [x] LogoutAll
- [x] RedactAllUserEvents
- [x] ReportEvent
- [x] ReportRoom
- [x] ReportUser
- [x] ResolveAlias
- [x] RestoreKeyBackup
- [x] SDPStreamMetadataChanged
- [x] StartQRVerification
- [x] StartSASVerification
- [x] SuspendUser
- [x] TimestampToEvent
- [x] UpdateDelayedEvent
- [x] UpgradeRoom
- [x] UploadMediaAsync
- [x] UploadSignatures
- [x] ValidateEmailForAccount
- [x] ValidatePhoneForAccount
- [x] VerifyDevice
- [x] WhoisUser
