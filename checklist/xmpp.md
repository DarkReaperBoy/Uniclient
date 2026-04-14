# XMPP Checklist — 379 methods


## Core Interface
- [x] Capabilities
- [x] Close
- [x] Name
- [x] OnUpdate

## Authentication
- [x] Authenticate
- [x] ChangePassword
- [x] Logout
- [x] RegisterAccount
- [x] UnregisterAccount

## Authentication Extensions
- [x] Bind2
- [x] FASTReconnect
- [x] InitAuthPipelining
- [x] OAuthClientLogin
- [x] QuickstartTLS
- [x] SASL2Authenticate

## Connection
- [x] ConnectBOSH
- [x] ConnectDirectTLS
- [x] ConnectHappyEyeballs
- [x] ConnectWebSocket

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
- [x] RetractMessage
- [x] SendBitsOfBinary
- [x] SendContentTypedMessage
- [x] SendDirectedPresence
- [x] SendDisplayedMarker
- [x] SendFileURL
- [x] SendGroupchatMessage
- [x] SendHeadlineMessage
- [x] SendImageBase64
- [x] SendJSONMessage
- [x] SendLocation
- [x] SendMessage
- [x] SendMessageReference
- [x] SendNormalMessage
- [x] SendOOBURL
- [x] SendPing
- [x] SendQuickResponse
- [x] SendReaction
- [x] SendRealTimeText
- [x] SendReceipt
- [x] SendReceivedMarker
- [x] SendRichTextMessage
- [x] SendSIMS
- [x] SendSpoilerMessage
- [x] SendTrustMessage
- [x] SendTyping
- [x] SendWebXDC
- [x] UnpinAllMessages
- [x] UnpinMessage

## Chat States
- [x] SendChatStateActive
- [x] SendChatStateComposing
- [x] SendChatStateGone
- [x] SendChatStateInactive
- [x] SendChatStatePaused

## Media & Files
- [x] DownloadFile
- [x] UploadFile

## Calls
- [x] AcceptCall
- [x] DeclineCall
- [x] EndCall
- [x] ProposeCall
- [x] SendCallInvite
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
- [x] GetStickerPack
- [x] SendSticker
- [x] SendStickerXEP

## Forum Topics
- [x] CreateForum

## User Profile (PEP)
- [x] SetUserActivity
- [x] SetUserLocation
- [x] SetUserMood
- [x] SetUserNickname
- [x] SetUserTune

## Avatars
- [x] GetAvatarPEP
- [x] SetAvatarPEP
- [x] SetAvatarVCard

## Search
- [x] SearchChannels
- [x] SearchMessages
- [x] SearchUsersExtended
- [x] SearchUsersXMPP

## Presence
- [x] ProbePresence
- [x] SendPresenceAvailable
- [x] SendPresenceSubscribe
- [x] SendPresenceSubscribed
- [x] SendPresenceUnavailable
- [x] SendPresenceUnsubscribe
- [x] SendPresenceUnsubscribed
- [x] SetPresencePriority

## Roster
- [x] AddRosterItem
- [x] GetRoster
- [x] RemoveRosterItem
- [x] SetRosterItemGroups
- [x] SetRosterItemName

## MUC (Multi-User Chat)
- [x] BanFromMUC
- [x] ConfigureMUC
- [x] CreateInstantMUC
- [x] CreateMUCTokenInvite
- [x] DeclineMUCInvitation
- [x] DestroyMUC
- [x] DiscoverMUCService
- [x] EnableMUCAffiliationVersioning
- [x] EnableMUCPresenceVersioning
- [x] GetMUCActivityIndicator
- [x] GetMUCConfig
- [x] GetMUCInfo
- [x] GetMUCOccupants
- [x] GrantVoice
- [x] JoinMUC
- [x] KickFromMUC
- [x] LeaveMUC
- [x] ModerateMessage
- [x] MUCSelfPing
- [x] RequestMUCHistory
- [x] RequestMUCVoice
- [x] RevokeVoice
- [x] SendDirectMUCInvitation
- [x] SendMUCInvitation
- [x] SendMUCMediatedInvite
- [x] SetMUCAffiliation
- [x] SetMUCAvatar
- [x] SetMUCHat
- [x] SetMUCNick
- [x] SetMUCRole
- [x] SetMUCSlowMode
- [x] SetMUCSubject
- [x] SubscribeMUCMentions
- [x] UnbanFromMUC

## MIX (Next-Gen MUC)
- [x] CreateMIXChannel
- [x] DestroyMIXChannel
- [x] JoinMIXChannel
- [x] LeaveMIXChannel
- [x] MIXAdminSetConfig
- [x] MIXMiscSetAvatar
- [x] MIXPAMJoin
- [x] MIXPresenceSubscribe
- [x] MIXSetAnonymity
- [x] SetMIXNick
- [x] UpdateMIXSubscriptions

## Jingle (Calls & File Transfer)
- [x] AcceptJingle
- [x] InitiateJingle
- [x] JingleConferenceInfo
- [x] JingleContentAccept
- [x] JingleContentAdd
- [x] JingleContentCategory
- [x] JingleContentModify
- [x] JingleContentReject
- [x] JingleContentRemove
- [x] JingleContentThumbnail
- [x] JingleDataChannels
- [x] JingleDTLSSRTP
- [x] JingleEncryptedTransport
- [x] JingleFileChecksum
- [x] JingleFileOffer
- [x] JingleFileReceived
- [x] JingleFileRequest
- [x] JingleFileResume
- [x] JingleGrouping
- [x] JingleJETOMEMO
- [x] JingleMessageRinging
- [x] JingleMuji
- [x] JingleRawUDP
- [x] JingleRTPSession
- [x] JingleSourceSSRC
- [x] JingleTransportAccept
- [x] JingleTransportReject
- [x] JingleTransportReplace
- [x] JingleTrickleICE
- [x] JingleZRTP
- [x] NegotiateChannelBinding
- [x] NegotiateRTCPFeedback
- [x] NegotiateRTPHeaderExtensions
- [x] NegotiateSession
- [x] RejectJingle
- [x] SendJingleTransportInfo
- [x] TerminateJingle

## OMEMO Encryption
- [x] FetchOMEMOBundle
- [x] FetchOMEMODeviceList
- [x] OMEMOAutoTrust
- [x] OMEMOBuildSession
- [x] OMEMODecrypt
- [x] OMEMOEncrypt
- [x] PublishOMEMOBundle
- [x] PublishOMEMODeviceList

## OpenPGP (OX)
- [x] EncryptPubSubOX
- [x] FetchOXPublicKey
- [x] OXDecrypt
- [x] OXEncrypt
- [x] OXSignEncrypt
- [x] PublishOXPublicKey

## PubSub
- [x] ConfigurePubSubNode
- [x] CreatePubSubNode
- [x] DeletePubSubNode
- [x] FilterPubSubByType
- [x] GetPubSubItems
- [x] GetPubSubServerInfo
- [x] GetPubSubSubscriptions
- [x] PublishJingleSession
- [x] PublishMicroblog
- [x] PublishPubSubItem
- [x] PublishSocialFeed
- [x] PubSubAttachment
- [x] PubSubCollectionNode
- [x] PubSubCompareAndPublish
- [x] PubSubFileShare
- [x] PubSubPersistPrivate
- [x] PubSubPersistPublic
- [x] PurgeNode
- [x] QueryPubSubMAM
- [x] RetractPubSubItem
- [x] SetPubSubCachingHints
- [x] SetPubSubPublicSubscriptions
- [x] SetPubSubRelationship
- [x] SubscribePubSub
- [x] UnsubscribePubSub

## Service Discovery
- [x] DiscoInfo
- [x] DiscoInfoExtended
- [x] DiscoItems
- [x] DiscoverAlternativeConnections
- [x] DiscoverCommands
- [x] DiscoverExternalServices
- [x] DiscoverHostMeta2
- [x] DiscoverHTTPUploadService
- [x] QueryFeatures
- [x] QueryIdentity

## Bookmarks
- [x] BookmarksConversion
- [x] GetBookmarks
- [x] RemoveBookmark
- [x] RemoveBookmarkPEP
- [x] SetBookmark
- [x] SetBookmarkAutoJoin
- [x] SetBookmarkPEP

## VCard
- [x] GetVCard
- [x] GetVCard4
- [x] GetVCardField
- [x] SetVCard
- [x] SetVCard4
- [x] SetVCardAvatar

## Bytestreams (IBB/S5B)
- [x] ActivateS5B
- [x] CloseIBBSession
- [x] InitiateS5B
- [x] OpenIBBSession
- [x] SendIBBData

## Message Archive (MAM)
- [x] GetMAMPreferences
- [x] QueryMAM
- [x] QueryMAMByDateRange
- [x] QueryMAMByJID
- [x] QueryMAMPage
- [x] SearchMAMFullText
- [x] SetMAMPreferences

## Stream Management
- [x] EnableStreamManagement
- [x] InstantStreamResumption
- [x] RequestAck
- [x] ResumeStream
- [x] SendAck

## Ad-Hoc Commands
- [x] CancelCommand
- [x] ExecuteCommand

## Privacy Lists
- [x] GetPrivacyLists
- [x] SetActiveList
- [x] SetDefaultList

## Encryption
- [x] EncryptContactsMetadata
- [x] EncryptMedia
- [x] EncryptStanzaContent
- [x] SetEncryptionHint

## Event Handlers
- [x] HandleCAPTCHA
- [x] HandleOccupantId

## Queries & Info
- [x] GetBlocklist
- [x] GetDataPolicy
- [x] GetDOAP
- [x] GetEntityCapabilities
- [x] GetEntityTime
- [x] GetInbox
- [x] GetLastActivity
- [x] GetLastUserInteraction
- [x] GetLinkMetadata
- [x] GetNodeAffiliations
- [x] GetNodeSubscribers
- [x] GetOfflineMessageCount
- [x] GetOfflineMessageHeaders
- [x] GetServiceOutageStatus
- [x] GetSoftwareVersion
- [x] GetStreamLimits
- [x] GetTURNCredentials
- [x] GetUserNickname

## Settings & Configuration
- [x] SetAMPRules
- [x] SetChatNotificationSettings
- [x] SetClientStateActive
- [x] SetClientStateInactive
- [x] SetFallbackIndication
- [x] SetMessageHint
- [x] SetNodeAffiliation
- [x] SetReachability
- [x] SetReminder
- [x] SetServerNotificationFilter

## Deletion
- [x] RemoveOfflineMessages

## Creation
- [x] CreateInvitationURI
- [x] CreateServerSpace

## Listing
- [x] ListClientAccess

## Requests
- [x] RequestBurnerJID
- [x] RequestHTTPUploadSlot
- [x] RequestOnlineMeeting
- [x] RequestReceipt
- [x] RequestStanzaIDs

## Event Handlers

## Other
- [x] AcceptProposal
- [x] AvatarConversion
- [x] BlockJID
- [x] CancelForm
- [x] DataFormsFileInput
- [x] DecryptMedia
- [x] DecryptStanzaContent
- [x] DisableCarbons
- [x] DisablePushNotifications
- [x] DownloadFileHTTP
- [x] EnableCarbons
- [x] EnablePushNotifications
- [x] EnableRosterVersioning
- [x] EntityCaps2
- [x] FastenPayload
- [x] ForwardStanza
- [x] PEPManageNode
- [x] PreAuthenticatedIBR
- [x] ProceedToJingle
- [x] ProcessFormResult
- [x] RejectProposal
- [x] RetractProposal
- [x] RetrieveOfflineMessages
- [x] RetrievePrivateXML
- [x] RevokeClientAccess
- [x] RSMQuery
- [x] ShareEncryptedFile
- [x] ShareFileMetadata
- [x] ShareFileMetadataElem
- [x] ShareFileSources
- [x] StorePrivateXML
- [x] SubmitForm
- [x] SubscribeRoomActivity
- [x] SyncDisplayedMessages
- [x] UnblockJID
- [x] UploadFileHTTP
- [x] VerifyHTTPRequest
