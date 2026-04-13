# Delta Chat — Fresh Checklist

**Methods:** 245 exported | **Lines:** 7,613 | **File:** `go/cores/deltachat.go`
**Protocol:** Delta Chat (IMAP/SMTP, Autocrypt E2EE, chatmail)
**Last updated:** 2026-04-13

## Categories

### Core Lifecycle (7)
- [ ] Authenticate
- [ ] Close
- [ ] IsConfigured
- [ ] Logout
- [ ] Name
- [ ] Capabilities
- [ ] OnUpdate

### Account Management (7)
- [ ] AddAccount
- [ ] DeactivateAccount
- [ ] GetAllAccountIds
- [ ] GetAccountFileSize
- [ ] RemoveAccount
- [ ] SelectAccount
- [ ] GetContextInfo

### I/O & Connectivity (10)
- [ ] StartIo
- [ ] StartIoForAllAccounts
- [ ] StopIo
- [ ] StopIoForAllAccounts
- [ ] StopOngoingProcess
- [ ] MaybeNetwork
- [ ] SyncNow
- [ ] GetConnectivity
- [ ] GetConnectivityHtml
- [ ] BackgroundFetch
- [ ] StopBackgroundFetch

### Configuration (8)
- [ ] GetConfig
- [ ] SetConfig
- [ ] SetConfigFromQR
- [ ] BatchGetConfig
- [ ] BatchSetConfig
- [ ] SetStockStrings
- [ ] SetShowEmails
- [ ] SetDownloadLimit

### Profile & Status (4)
- [ ] GetProfile
- [ ] GetStatus
- [ ] SetStatus
- [ ] SetAvatar

### Contacts (20)
- [ ] AddContact
- [ ] AddAddressBook
- [ ] ChangeContactName
- [ ] DeleteContact
- [ ] GetContacts
- [ ] GetContactAuthName
- [ ] GetContactColor
- [ ] GetContactEncryptionInfo
- [ ] GetContactLastSeen
- [ ] GetContactStatus
- [ ] GetContactVerifierId
- [ ] GetPastContacts
- [ ] ImportVCard
- [ ] IsContactBot
- [ ] IsContactInChat
- [ ] IsContactKeyContact
- [ ] IsContactVerified
- [ ] LookupContactByAddr
- [ ] MakeVCard
- [ ] WasContactSeenRecently

### Chat Management (24)
- [ ] AcceptChat
- [ ] ArchiveChat
- [ ] BlockChat
- [ ] CreateBroadcastList
- [ ] CreateChannel
- [ ] CreateChatByContactId
- [ ] CreateGroup
- [ ] CreatePoll
- [ ] CreateTopic
- [ ] DeleteChat
- [ ] EditChatDescription
- [ ] EditChatTitle
- [ ] GetBasicChatInfo
- [ ] GetChatColor
- [ ] GetChatIdByContactId
- [ ] GetChatInfo
- [ ] GetChatType
- [ ] GetFullChatById
- [ ] GetSimilarChats
- [ ] IsChatContactRequest
- [ ] IsChatDeviceTalk
- [ ] IsChatSelfTalk
- [ ] IsChatUnpromoted
- [ ] LeaveChat

### Chat Visibility & Muting (5)
- [ ] GetRemainingMuteDuration
- [ ] MuteChat
- [ ] SetChatMuted
- [ ] SetChatVisibility
- [ ] MarkFreshChat

### Chat Images (2)
- [ ] RemoveChatImage
- [ ] SetChatImage

### Chat Encryption & Protection (3)
- [ ] GetEncryptionInfo
- [ ] IsChatEncrypted
- [ ] SetChatProtected

### Chat Lists (3)
- [ ] GetChatlistEntries
- [ ] GetChatlistItemsByEntries
- [ ] GetChatlistSummary

### Members & Groups (6)
- [ ] AddMembers
- [ ] GetChatContacts
- [ ] GetMembers
- [ ] RemoveMember
- [ ] SetAdmin
- [ ] GetMailingListAddr

### Banning (2)
- [ ] BanMember
- [ ] UnbanMember

### Blocking (2)
- [ ] BlockUser
- [ ] UnblockUser
- [ ] GetBlockedUsers

### Dialogs & Folders (3)
- [ ] GetDialogs
- [ ] GetFolders
- [ ] CreateFolder

### Messaging — Send (10)
- [ ] SendMessage
- [ ] SendHTML
- [ ] SendContact
- [ ] SendDraft
- [ ] SendImageBase64
- [ ] SendLocation
- [ ] SendSticker
- [ ] SendTyping
- [ ] SendVideochatInvitation
- [ ] ReplyToMessage

### Messaging — Edit & Forward (4)
- [ ] EditMessage
- [ ] ForwardMessage
- [ ] ForwardMessagesToAccount
- [ ] ResendMessage

### Messaging — Delete (2)
- [ ] DeleteMessage
- [ ] DeleteMessagesForAll

### Messaging — Read State (5)
- [ ] GetReadReceipts
- [ ] GetReadReceiptCount
- [ ] GetReadState
- [ ] MarkAsRead
- [ ] MarkUnread
- [ ] MarkNoticedChat

### Messaging — Retrieve (13)
- [ ] GetMessages
- [ ] GetNextMessages
- [ ] WaitNextMessages
- [ ] GetChatMedia
- [ ] GetFirstUnreadMessage
- [ ] GetFreshMessageCount
- [ ] GetFreshMessages
- [ ] GetMessageHTML
- [ ] GetMessageInfo
- [ ] GetMessageInfoType
- [ ] GetMessageParent
- [ ] GetMessageSortTimestamp
- [ ] GetMessageSubject

### Messaging — State & Metadata (10)
- [ ] CanSend
- [ ] GetMessageDownloadState
- [ ] GetMessageError
- [ ] GetOriginalMsgId
- [ ] GetOverrideSenderName
- [ ] GetSavedMsgId
- [ ] GetShowPadlock
- [ ] HasDeviatingTimestamp
- [ ] HasMessageHtml
- [ ] HasMessageLocation
- [ ] IsMessageBot
- [ ] IsMessageEdited
- [ ] IsMessageForwarded
- [ ] IsMessageInfo

### Messaging — Compose & Draft (5)
- [ ] GetDraft
- [ ] RemoveDraft
- [ ] SetDraft
- [ ] SetMessageDimensions
- [ ] SetMessageDuration
- [ ] SetMessageHtml
- [ ] SetMessageLocation
- [ ] SetMessageSubject
- [ ] SetOverrideSenderName

### Messaging — Pin (3)
- [ ] PinMessage
- [ ] UnpinMessage
- [ ] UnpinAllMessages

### Messaging — Download & Files (4)
- [ ] DownloadFile
- [ ] DownloadFullMessage
- [ ] MessageSaveFile
- [ ] UploadFile

### Messaging — Save (1)
- [ ] SaveMessages

### Reactions (1)
- [ ] ReactToMessage
- [ ] GetReactions

### Polls (1)
- [ ] VotePoll

### Stickers (3)
- [ ] GetStickerFolder
- [ ] GetStickers
- [ ] SaveSticker

### Search (2)
- [ ] SearchGlobal
- [ ] SearchMessages

### Ephemeral / Auto-Delete (2)
- [ ] GetEphemeralTimer
- [ ] SetEphemeralTimer
- [ ] EstimateAutoDeletionCount

### Invite Links & QR (7)
- [ ] CheckQR
- [ ] CreateQRSvg
- [ ] GetBackupQR
- [ ] GetBackupQRSvg
- [ ] GetChatSecureJoinQRCodeSvg
- [ ] GetInviteLink
- [ ] GetSecureJoinQR
- [ ] GetSecureJoinQRSvg
- [ ] SecureJoin

### Backup (3)
- [ ] ExportBackup
- [ ] GetBackup
- [ ] ImportBackup
- [ ] ProvideBackup
- [ ] ReceiveBackup

### Key Management (5)
- [ ] ChangePassphrase
- [ ] ContinueKeyTransfer
- [ ] ExportSelfKeys
- [ ] ImportSelfKeys
- [ ] InitiateKeyTransfer
- [ ] PreconfigureKeypair
- [ ] SetPeerPublicKey

### Calls (8)
- [ ] AcceptCall
- [ ] AcceptIncomingCall
- [ ] DeclineCall
- [ ] EndCall
- [ ] GetCallInfo
- [ ] JoinGroupCall
- [ ] SetCallFilter
- [ ] SetCallMuted
- [ ] StartCall

### Location Streaming (5)
- [ ] DeleteAllLocations
- [ ] GetLocations
- [ ] IsLocationStreaming
- [ ] IsSendingLocationsToChat
- [ ] StartLocationStreaming
- [ ] StopLocationStreaming

### Webxdc (6)
- [ ] GetWebxdcBlob
- [ ] GetWebxdcInfo
- [ ] GetWebxdcStatusUpdates
- [ ] InitWebxdcIntegration
- [ ] LeaveWebxdcRealtime
- [ ] SendWebxdcRealtimeAdvertisement
- [ ] SendWebxdcRealtimeData
- [ ] SendWebxdcStatusUpdate
- [ ] SetWebxdcIntegration

### Push Notifications (2)
- [ ] GetPushState
- [ ] SetPushDeviceToken

### Transports (3)
- [ ] AddTransport
- [ ] DeleteTransport
- [ ] ListTransports

### Provider & OAuth (2)
- [ ] GetProviderInfo
- [ ] GetOAuth2URL

### Email Validation (1)
- [ ] CheckEmailValidity

### Storage & System (4)
- [ ] GetBlobDir
- [ ] GetQuota
- [ ] GetStorageUsageReport
- [ ] GetSystemInfo

### Sessions (2)
- [ ] GetSessions
- [ ] TerminateSession

### Device Messages (2)
- [ ] AddDeviceMessage
- [ ] WasDeviceMsgEverAdded
