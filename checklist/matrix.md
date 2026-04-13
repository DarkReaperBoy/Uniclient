# Matrix — Fresh Checklist

**Methods:** 240 exported | **Lines:** 6,409 | **File:** `go/cores/matrix.go`
**Protocol:** Matrix (CS API v1.13-v1.18, E2EE via goolm, mautrix-go SDK)
**Last updated:** 2026-04-13

## Categories

### Authentication & Registration (14)
- [ ] Authenticate
- [ ] Register
- [ ] Logout
- [ ] LogoutAll
- [ ] ChangePassword
- [ ] DeactivateAccount
- [ ] CheckUsernameAvailability
- [ ] CheckRegistrationToken
- [ ] GetLoginFlows
- [ ] GetLoginToken
- [ ] RefreshToken
- [ ] SSORedirect
- [ ] SSORedirectIdP
- [ ] DeviceAuthGrant

### Server Discovery & Capabilities (7)
- [ ] GetVersions
- [ ] GetCapabilities
- [ ] Capabilities
- [ ] GetClientWellKnown
- [ ] GetSupportContacts
- [ ] GetAuthMetadata
- [ ] GetMediaConfig

### Profile & User Settings (12)
- [ ] GetProfile
- [ ] SetDisplayName
- [ ] SetAvatar
- [ ] GetProfileField
- [ ] SetProfileField
- [ ] DeleteProfileField
- [ ] GetProfileFieldsCap
- [ ] SetTimezone
- [ ] SetPresence
- [ ] GetPresence
- [ ] GetIgnoredUsers
- [ ] GetRecentEmoji

### Messaging (13)
- [ ] SendMessage
- [ ] EditMessage
- [ ] DeleteMessage
- [ ] ReplyToMessage
- [ ] ForwardMessage
- [ ] ReactToMessage
- [ ] SendEmoteMessage
- [ ] SendLocationMessage
- [ ] SendLiveLocation
- [ ] SendLocation
- [ ] GetMessages
- [ ] GetEvent
- [ ] GetEventContext

### Polls (3)
- [ ] CreatePoll
- [ ] VotePoll
- [ ] EndPoll

### Stickers (1)
- [ ] SendSticker

### Media & Files (12)
- [ ] UploadFile
- [ ] DownloadFile
- [ ] SendImageBase64
- [ ] DownloadThumbnail
- [ ] GetURLPreview
- [ ] GetURLPreviewAuth
- [ ] CreateMXCURI
- [ ] GetMediaConfigAuth
- [ ] DownloadMediaAuth
- [ ] DownloadMediaAuthFilename
- [ ] DownloadThumbnailAuth
- [ ] UploadMediaAsync

### Read Receipts & Markers (6)
- [ ] MarkAsRead
- [ ] MarkUnread
- [ ] GetReadState
- [ ] SendPrivateReadReceipt
- [ ] SetReadMarkers
- [ ] GetFullyReadMarker

### Typing Indicators (1)
- [ ] SendTyping

### Pinning (3)
- [ ] PinMessage
- [ ] UnpinMessage
- [ ] UnpinAllMessages

### Room Management (18)
- [ ] CreateGroup
- [ ] CreateChannel
- [ ] CreateTopic
- [ ] GetChatInfo
- [ ] EditChatTitle
- [ ] EditChatDescription
- [ ] GetInviteLink
- [ ] LeaveChat
- [ ] JoinRoom
- [ ] JoinRoomByAlias
- [ ] KnockRoom
- [ ] ForgetRoom
- [ ] UpgradeRoom
- [ ] ArchiveChat
- [ ] MuteChat
- [ ] GetDialogs
- [ ] GetDirectChats
- [ ] SetDirectChat

### Room State & Configuration (12)
- [ ] GetRoomState
- [ ] GetRoomVisibility
- [ ] SetRoomVisibility
- [ ] SetRoomAvatar
- [ ] SetJoinRules
- [ ] SetHistoryVisibility
- [ ] SetGuestAccess
- [ ] SetCanonicalAlias
- [ ] GetRoomAliases
- [ ] SetRoomAlias
- [ ] DeleteRoomAlias
- [ ] ResolveAlias

### Room Metadata (4)
- [ ] GetRoomCreationEvent
- [ ] GetRoomTombstone
- [ ] GetRoomSummary
- [ ] GetForgetOnLeave

### Members & Permissions (8)
- [ ] GetMembers
- [ ] AddMembers
- [ ] RemoveMember
- [ ] BanMember
- [ ] UnbanMember
- [ ] SetAdmin
- [ ] SetPowerLevels
- [ ] InviteBy3PID

### Contacts & Blocking (6)
- [ ] GetContacts
- [ ] AddContact
- [ ] DeleteContact
- [ ] BlockUser
- [ ] UnblockUser
- [ ] GetBlockedUsers

### Folders & Tags (5)
- [ ] GetFolders
- [ ] CreateFolder
- [ ] SetRoomTag
- [ ] RemoveRoomTag
- [ ] GetTags

### Spaces (3)
- [ ] GetSpaceChildren
- [ ] AddSpaceChild
- [ ] RemoveSpaceChild

### Threads (2)
- [ ] GetThreads
- [ ] GetThreadReplies

### Search (3)
- [ ] SearchMessages
- [ ] SearchGlobal
- [ ] SearchUsers

### Public Rooms (2)
- [ ] GetPublicRooms
- [ ] GetMutualRooms

### 1:1 Calls (VoIP) (12)
- [ ] StartCall
- [ ] AcceptCall
- [ ] RejectCall
- [ ] DeclineCall
- [ ] EndCall
- [ ] SetCallMuted
- [ ] SetCallAudioSource
- [ ] SetCallAudioSink
- [ ] AcceptCallSelectAnswer
- [ ] SendCallCandidates
- [ ] SendCallNegotiate
- [ ] SendCallAssertedIdentity

### Call Signaling (3)
- [ ] CallReplaces
- [ ] SDPStreamMetadataChanged
- [ ] CallNotify

### Group Calls & RTC (7)
- [ ] JoinGroupCall
- [ ] GroupCallEncryptionKeys
- [ ] SendGroupCallEncryptionKeys
- [ ] GetRTCTransports
- [ ] SetRTCMemberState
- [ ] SendRTCNotification
- [ ] DeclineRTCSession

### E2EE & Key Management (10)
- [ ] ExportKeys
- [ ] ImportKeys
- [ ] EnableEncryption
- [ ] GetEncryptionInfo
- [ ] CreateKeyBackup
- [ ] RestoreKeyBackup
- [ ] GetKeyBackupInfo
- [ ] GetKeyChanges
- [ ] SetSecretStorageKey
- [ ] GetSecretStorageKey

### Cross-Signing & Verification (8)
- [ ] VerifyDevice
- [ ] StartSASVerification
- [ ] AcceptSASVerification
- [ ] ConfirmSASEmojis
- [ ] CancelVerification
- [ ] StartQRVerification
- [ ] GenerateCrossSigningKeys
- [ ] UploadCrossSigningKeys

### Signatures (1)
- [ ] UploadSignatures

### Secret Sharing (2)
- [ ] SendSecretRequest
- [ ] SendSecretSend

### Dehydrated Devices (4)
- [ ] SetDehydratedDevice
- [ ] GetDehydratedDevice
- [ ] DeleteDehydratedDevice
- [ ] GetDehydratedDeviceEvents

### Device Management (5)
- [ ] GetSessions
- [ ] TerminateSession
- [ ] GetDeviceInfo
- [ ] SetDeviceName
- [ ] DeleteDevices

### Push Notifications (10)
- [ ] GetPushers
- [ ] SetPusher
- [ ] GetPushRules
- [ ] SetPushRule
- [ ] DeletePushRule
- [ ] EnablePushRule
- [ ] GetPushRuleActions
- [ ] SetPushRuleActions
- [ ] GetPushRuleEnabled
- [ ] GetNotifications

### Third-Party Identifiers (10)
- [ ] Get3PIDs
- [ ] Add3PID
- [ ] Bind3PID
- [ ] Delete3PID
- [ ] Delete3PIDByAddress
- [ ] Unbind3PID
- [ ] RequestEmailToken
- [ ] RequestMsisdnToken
- [ ] ValidateEmailForAccount
- [ ] ValidatePhoneForAccount

### Third-Party Protocols (3)
- [ ] GetThirdPartyProtocols
- [ ] LookupThirdPartyLocation
- [ ] LookupThirdPartyUser

### Third-Party Invites (1)
- [ ] GetThirdPartyInvites

### Account Data (4)
- [ ] SetAccountData
- [ ] GetAccountData
- [ ] SetRoomAccountData
- [ ] GetRoomAccountData

### Filters (2)
- [ ] CreateFilter
- [ ] GetFilter

### Delayed Events (2)
- [ ] CreateDelayedEvent
- [ ] UpdateDelayedEvent

### Sync (2)
- [ ] SlidingSync
- [ ] SyncStateAfter

### To-Device Messaging (1)
- [ ] SendToDevice

### Moderation & Reporting (5)
- [ ] ReportEvent
- [ ] ReportRoom
- [ ] ReportUser
- [ ] RedactAllUserEvents
- [ ] SetPolicyRule

### Server Administration (4)
- [ ] WhoisUser
- [ ] SuspendUser
- [ ] LockUser
- [ ] HandleUserLimitExceeded

### Privacy & Safety (2)
- [ ] SetInviteBlocking
- [ ] GetNonCrossSignedExclusion

### Room ACL (1)
- [ ] SetServerACL

### TURN Server (1)
- [ ] GetTurnServer

### Tokens & Identity (2)
- [ ] RequestOpenIDToken
- [ ] TimestampToEvent

### Lifecycle (3)
- [ ] Name
- [ ] OnUpdate
- [ ] Close
