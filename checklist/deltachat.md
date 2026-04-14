# Delta Chat Checklist — 245 methods


## Core Interface
- [x] Capabilities
- [x] Close
- [x] Name
- [x] OnUpdate

## Authentication
- [x] Authenticate
- [x] DeactivateAccount
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
- [x] SendContact
- [x] SendDraft
- [x] SendHTML
- [x] SendImageBase64
- [x] SendLocation
- [x] SendMessage
- [x] SendSticker
- [x] SendTyping
- [x] SendVideochatInvitation
- [x] UnpinAllMessages
- [x] UnpinMessage

## Media & Files
- [x] DownloadFile
- [x] DownloadFullMessage
- [x] MessageSaveFile
- [x] UploadFile

## Calls
- [x] AcceptCall
- [x] AcceptIncomingCall
- [x] DeclineCall
- [x] EndCall
- [x] GetCallInfo
- [x] SetCallFilter
- [x] SetCallMuted
- [x] StartCall

## Group Calls
- [x] JoinGroupCall

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

## Stickers
- [x] GetStickerFolder
- [x] GetStickers
- [x] SaveSticker

## Drafts
- [x] GetDraft
- [x] RemoveDraft
- [x] SetDraft

## Search
- [x] SearchMessages

## Chat Invites & Lists
- [x] GetChatlistEntries
- [x] GetChatlistItemsByEntries
- [x] GetChatlistSummary

## Webxdc
- [x] GetWebxdcBlob
- [x] GetWebxdcInfo
- [x] GetWebxdcStatusUpdates
- [x] InitWebxdcIntegration
- [x] LeaveWebxdcRealtime
- [x] SendWebxdcRealtimeAdvertisement
- [x] SendWebxdcRealtimeData
- [x] SendWebxdcStatusUpdate
- [x] SetWebxdcIntegration

## Multi-Transport
- [x] AddTransport
- [x] DeleteTransport
- [x] ListTransports

## State Queries
- [x] IsChatContactRequest
- [x] IsChatDeviceTalk
- [x] IsChatEncrypted
- [x] IsChatSelfTalk
- [x] IsChatUnpromoted
- [x] IsConfigured
- [x] IsContactBot
- [x] IsContactInChat
- [x] IsContactKeyContact
- [x] IsContactVerified
- [x] IsLocationStreaming
- [x] IsMessageBot
- [x] IsMessageEdited
- [x] IsMessageForwarded
- [x] IsMessageInfo
- [x] IsSendingLocationsToChat

## Backup & Key Transfer
- [x] ContinueKeyTransfer
- [x] ExportBackup
- [x] ExportSelfKeys
- [x] GetBackup
- [x] GetBackupQR
- [x] GetBackupQRSvg
- [x] ImportBackup
- [x] InitiateKeyTransfer
- [x] ProvideBackup
- [x] ReceiveBackup

## Queries & Info
- [x] GetAccountFileSize
- [x] GetAllAccountIds
- [x] GetBasicChatInfo
- [x] GetBlobDir
- [x] GetChatColor
- [x] GetChatContacts
- [x] GetChatIdByContactId
- [x] GetChatMedia
- [x] GetChatType
- [x] GetConfig
- [x] GetConnectivity
- [x] GetConnectivityHtml
- [x] GetContactAuthName
- [x] GetContactColor
- [x] GetContactEncryptionInfo
- [x] GetContactLastSeen
- [x] GetContactStatus
- [x] GetContactVerifierId
- [x] GetContextInfo
- [x] GetEncryptionInfo
- [x] GetEphemeralTimer
- [x] GetFirstUnreadMessage
- [x] GetFreshMessageCount
- [x] GetFreshMessages
- [x] GetFullChatById
- [x] GetLocations
- [x] GetMailingListAddr
- [x] GetMessageDownloadState
- [x] GetMessageError
- [x] GetMessageHTML
- [x] GetMessageInfo
- [x] GetMessageInfoType
- [x] GetMessageParent
- [x] GetMessageSortTimestamp
- [x] GetMessageSubject
- [x] GetNextMessages
- [x] GetOAuth2URL
- [x] GetOriginalMsgId
- [x] GetOverrideSenderName
- [x] GetPastContacts
- [x] GetProviderInfo
- [x] GetPushState
- [x] GetQuota
- [x] GetReactions
- [x] GetReadReceiptCount
- [x] GetReadReceipts
- [x] GetRemainingMuteDuration
- [x] GetSavedMsgId
- [x] GetSecureJoinQR
- [x] GetSecureJoinQRSvg
- [x] GetShowPadlock
- [x] GetSimilarChats
- [x] GetStatus
- [x] GetStorageUsageReport
- [x] GetSystemInfo

## Settings & Configuration
- [x] SetAvatar
- [x] SetChatImage
- [x] SetChatMuted
- [x] SetChatProtected
- [x] SetChatVisibility
- [x] SetConfig
- [x] SetConfigFromQR
- [x] SetDownloadLimit
- [x] SetEphemeralTimer
- [x] SetMessageDimensions
- [x] SetMessageDuration
- [x] SetMessageHtml
- [x] SetMessageLocation
- [x] SetMessageSubject
- [x] SetOverrideSenderName
- [x] SetPeerPublicKey
- [x] SetPushDeviceToken
- [x] SetShowEmails
- [x] SetStatus
- [x] SetStockStrings

## Deletion
- [x] DeleteAllLocations
- [x] DeleteChat
- [x] DeleteMessagesForAll
- [x] RemoveAccount
- [x] RemoveChatImage

## Creation
- [x] CreateBroadcastList
- [x] CreateChatByContactId
- [x] CreateQRSvg

## Read State
- [x] MarkFreshChat
- [x] MarkNoticedChat

## Other
- [x] AcceptChat
- [x] AddAccount
- [x] AddAddressBook
- [x] AddDeviceMessage
- [x] BackgroundFetch
- [x] BatchGetConfig
- [x] BatchSetConfig
- [x] BlockChat
- [x] CanSend
- [x] ChangeContactName
- [x] ChangePassphrase
- [x] CheckEmailValidity
- [x] CheckQR
- [x] EstimateAutoDeletionCount
- [x] ForwardMessagesToAccount
- [x] HasDeviatingTimestamp
- [x] HasMessageHtml
- [x] HasMessageLocation
- [x] ImportSelfKeys
- [x] ImportVCard
- [x] LookupContactByAddr
- [x] MakeVCard
- [x] MaybeNetwork
- [x] PreconfigureKeypair
- [x] ResendMessage
- [x] SaveMessages
- [x] SecureJoin
- [x] SelectAccount
- [x] StartIo
- [x] StartIoForAllAccounts
- [x] StartLocationStreaming
- [x] StopBackgroundFetch
- [x] StopIo
- [x] StopIoForAllAccounts
- [x] StopLocationStreaming
- [x] StopOngoingProcess
- [x] SyncNow
- [x] WaitNextMessages
- [x] WasContactSeenRecently
- [x] WasDeviceMsgEverAdded
