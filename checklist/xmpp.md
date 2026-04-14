# XMPP — Fresh Checklist

**Methods:** 379 exported | **Lines:** 7,848 | **File:** `go/cores/xmpp.go`
**Protocol:** XMPP (RFC 6120/6121 + 30+ XEPs, Jingle, OMEMO, MUC, MIX, PubSub)
**Last updated:** 2026-04-13

## Connection & Transport (11)
- [ ] Close
- [ ] ConnectBOSH
- [ ] ConnectDirectTLS
- [ ] ConnectHappyEyeballs
- [ ] ConnectWebSocket
- [ ] DiscoverAlternativeConnections
- [ ] DiscoverHostMeta2
- [ ] EnableStreamManagement
- [ ] GetStreamLimits
- [ ] InstantStreamResumption
- [ ] ResumeStream

## Authentication & Registration (12)
- [ ] Authenticate
- [ ] Bind2
- [ ] ChangePassword
- [ ] FASTReconnect
- [ ] InitAuthPipelining
- [ ] Logout
- [ ] NegotiateChannelBinding
- [ ] OAuthClientLogin
- [ ] PreAuthenticatedIBR
- [ ] QuickstartTLS
- [ ] RegisterAccount
- [ ] SASL2Authenticate
- [ ] SCRAMDowngradeProtect
- [ ] UnregisterAccount

## Session & Stream (8)
- [ ] GetSessions
- [ ] NegotiateSession
- [ ] RequestAck
- [ ] SendAck
- [ ] SetClientStateActive
- [ ] SetClientStateInactive
- [ ] TerminateSession
- [ ] Name

## Presence (11)
- [ ] ProbePresence
- [ ] SendDirectedPresence
- [ ] SendPresenceAvailable
- [ ] SendPresenceSubscribe
- [ ] SendPresenceSubscribed
- [ ] SendPresenceUnavailable
- [ ] SendPresenceUnsubscribe
- [ ] SendPresenceUnsubscribed
- [ ] SetPresencePriority
- [ ] SetReachability
- [ ] SetUserActivity

## Messaging — Core (14)
- [ ] DeleteMessage
- [ ] EditMessage
- [ ] ForwardMessage
- [ ] ForwardStanza
- [ ] ModerateMessage
- [ ] ReplyToMessage
- [ ] RetractMessage
- [ ] SendGroupchatMessage
- [ ] SendHeadlineMessage
- [ ] SendMessage
- [ ] SendNormalMessage
- [ ] SendRichTextMessage
- [ ] SendSpoilerMessage
- [ ] SendContentTypedMessage

## Messaging — Chat States (5)
- [ ] SendChatStateActive
- [ ] SendChatStateComposing
- [ ] SendChatStateGone
- [ ] SendChatStateInactive
- [ ] SendChatStatePaused

## Messaging — Markers & Receipts (7)
- [ ] MarkAsRead
- [ ] MarkUnread
- [ ] RequestReceipt
- [ ] SendDisplayedMarker
- [ ] SendReceivedMarker
- [ ] SendReceipt
- [ ] SyncDisplayedMessages

## Messaging — Reactions & References (5)
- [ ] ReactToMessage
- [ ] SendMessageReference
- [ ] SendQuickResponse
- [ ] SendReaction
- [ ] SendRealTimeText

## Messaging — Stickers & Media Messages (6)
- [ ] SendImageBase64
- [ ] SendLocation
- [ ] SendOOBURL
- [ ] SendSticker
- [ ] SendStickerXEP
- [ ] SendBitsOfBinary

## Messaging — Typing & Hints (4)
- [ ] SendTyping
- [ ] SetEncryptionHint
- [ ] SetFallbackIndication
- [ ] SetMessageHint

## Messaging — Advanced (10)
- [ ] AdvertiseNoReply
- [ ] FastenPayload
- [ ] PinMessage
- [ ] RequestBurnerJID
- [ ] RequestStanzaIDs
- [ ] SendJSONMessage
- [ ] SendWebXDC
- [ ] SetAMPRules
- [ ] UnpinAllMessages
- [ ] UnpinMessage

## Message Archive Management (MAM) (8)
- [ ] GetMAMPreferences
- [ ] QueryMAM
- [ ] QueryMAMByDateRange
- [ ] QueryMAMByJID
- [ ] QueryMAMPage
- [ ] QueryPubSubMAM
- [ ] SearchMAMFullText
- [ ] SetMAMPreferences

## Roster & Contacts (12)
- [ ] AddContact
- [ ] DeleteContact
- [ ] GetBlockedUsers
- [ ] GetBlocklist
- [ ] GetContacts
- [ ] GetRoster
- [ ] RemoveRosterItem
- [ ] AddRosterItem
- [ ] SetRosterItemGroups
- [ ] SetRosterItemName
- [ ] ShareRosterItem
- [ ] EnableRosterVersioning

## Blocking (4)
- [ ] BlockJID
- [ ] BlockUser
- [ ] UnblockJID
- [ ] UnblockUser

## Profile & Identity (18)
- [ ] GetAvatarPEP
- [ ] GetProfile
- [ ] GetUserNickname
- [ ] GetVCard
- [ ] GetVCard4
- [ ] GetVCardField
- [ ] SetAvatarPEP
- [ ] SetAvatarVCard
- [ ] SetUserLocation
- [ ] SetUserMood
- [ ] SetUserNickname
- [ ] SetUserTune
- [ ] SetVCard
- [ ] SetVCard4
- [ ] SetVCardAvatar
- [ ] AvatarConversion
- [ ] GetDOAP
- [ ] GetSoftwareVersion

## MUC — Multi-User Chat (29)
- [ ] BanFromMUC
- [ ] ConfigureMUC
- [ ] CreateInstantMUC
- [ ] CreateMUCTokenInvite
- [ ] DeclineMUCInvitation
- [ ] DestroyMUC
- [ ] EnableMUCAffiliationVersioning
- [ ] EnableMUCPresenceVersioning
- [ ] GetMUCActivityIndicator
- [ ] GetMUCConfig
- [ ] GetMUCInfo
- [ ] GetMUCOccupants
- [ ] HandleOccupantId
- [ ] JoinMUC
- [ ] KickFromMUC
- [ ] LeaveMUC
- [ ] MUCSelfPing
- [ ] RequestMUCHistory
- [ ] RequestMUCVoice
- [ ] SendDirectMUCInvitation
- [ ] SendMUCInvitation
- [ ] SendMUCMediatedInvite
- [ ] SetMUCAffiliation
- [ ] SetMUCAvatar
- [ ] SetMUCHat
- [ ] SetMUCNick
- [ ] SetMUCRole
- [ ] SetMUCSlowMode
- [ ] SetMUCSubject
- [ ] SubscribeMUCMentions
- [ ] SubscribeRoomActivity
- [ ] UnbanFromMUC

## MUC — Voice (3)
- [ ] GrantVoice
- [ ] RevokeVoice
- [ ] BanMember

## MIX — Mediated Information eXchange (10)
- [ ] CreateMIXChannel
- [ ] DestroyMIXChannel
- [ ] JoinMIXChannel
- [ ] LeaveMIXChannel
- [ ] MIXAdminSetConfig
- [ ] MIXMiscSetAvatar
- [ ] MIXPAMJoin
- [ ] MIXPresenceSubscribe
- [ ] MIXSetAnonymity
- [ ] SetMIXNick
- [ ] UpdateMIXSubscriptions

## PubSub (22)
- [ ] ConfigurePubSubNode
- [ ] CreatePubSubNode
- [ ] DeletePubSubNode
- [ ] FilterPubSubByType
- [ ] GetPubSubItems
- [ ] GetPubSubServerInfo
- [ ] GetPubSubSubscriptions
- [ ] PEPManageNode
- [ ] PublishPubSubItem
- [ ] PubSubAttachment
- [ ] PubSubCollectionNode
- [ ] PubSubCompareAndPublish
- [ ] PubSubFileShare
- [ ] PubSubPersistPrivate
- [ ] PubSubPersistPublic
- [ ] PurgeNode
- [ ] RetractPubSubItem
- [ ] SetPubSubCachingHints
- [ ] SetPubSubPublicSubscriptions
- [ ] SetPubSubRelationship
- [ ] SubscribePubSub
- [ ] UnsubscribePubSub
- [ ] GetNodeAffiliations
- [ ] GetNodeSubscribers
- [ ] SetNodeAffiliation

## Jingle — Session Management (14)
- [ ] AcceptJingle
- [ ] InitiateJingle
- [ ] JingleContentAccept
- [ ] JingleContentAdd
- [ ] JingleContentCategory
- [ ] JingleContentModify
- [ ] JingleContentReject
- [ ] JingleContentRemove
- [ ] JingleContentThumbnail
- [ ] JingleGrouping
- [ ] PublishJingleSession
- [ ] RejectJingle
- [ ] SendJingleTransportInfo
- [ ] TerminateJingle

## Jingle — Transport (8)
- [ ] ActivateS5B
- [ ] InitiateS5B
- [ ] JingleRawUDP
- [ ] JingleTransportAccept
- [ ] JingleTransportReject
- [ ] JingleTransportReplace
- [ ] JingleTrickleICE
- [ ] JingleEncryptedTransport

## Jingle — RTP & Media (6)
- [ ] JingleDTLSSRTP
- [ ] JingleRTPSession
- [ ] JingleSourceSSRC
- [ ] JingleZRTP
- [ ] NegotiateRTCPFeedback
- [ ] NegotiateRTPHeaderExtensions

## Jingle — File Transfer (6)
- [ ] JingleFileChecksum
- [ ] JingleFileOffer
- [ ] JingleFileReceived
- [ ] JingleFileRequest
- [ ] JingleFileResume
- [ ] JingleJETOMEMO

## Jingle — Conferencing (3)
- [ ] JingleConferenceInfo
- [ ] JingleDataChannels
- [ ] JingleMuji

## Jingle — Message Initiation (2)
- [ ] JingleMessageRinging
- [ ] ProceedToJingle

## Calls (10)
- [ ] AcceptCall
- [ ] AcceptProposal
- [ ] DeclineCall
- [ ] EndCall
- [ ] JoinGroupCall
- [ ] ProposeCall
- [ ] RejectProposal
- [ ] RetractProposal
- [ ] SendCallInvite
- [ ] SetCallMuted
- [ ] StartCall

## OMEMO (8)
- [ ] FetchOMEMOBundle
- [ ] FetchOMEMODeviceList
- [ ] OMEMOAutoTrust
- [ ] OMEMOBuildSession
- [ ] OMEMODecrypt
- [ ] OMEMOEncrypt
- [ ] PublishOMEMOBundle
- [ ] PublishOMEMODeviceList

## OpenPGP for XMPP (OX) (5)
- [ ] EncryptPubSubOX
- [ ] FetchOXPublicKey
- [ ] OXDecrypt
- [ ] OXEncrypt
- [ ] OXSignEncrypt
- [ ] PublishOXPublicKey

## Encryption — General (4)
- [ ] DecryptMedia
- [ ] DecryptStanzaContent
- [ ] EncryptMedia
- [ ] EncryptStanzaContent
- [ ] EncryptContactsMetadata
- [ ] SendTrustMessage

## Service Discovery (9)
- [ ] Capabilities
- [ ] DiscoInfo
- [ ] DiscoInfoExtended
- [ ] DiscoItems
- [ ] DiscoverMUCService
- [ ] EntityCaps2
- [ ] GetEntityCapabilities
- [ ] QueryFeatures
- [ ] QueryIdentity

## File Transfer (9)
- [ ] CloseIBBSession
- [ ] DownloadFile
- [ ] DownloadFileHTTP
- [ ] OpenIBBSession
- [ ] SendIBBData
- [ ] ShareEncryptedFile
- [ ] ShareFileMetadata
- [ ] ShareFileMetadataElem
- [ ] ShareFileSources

## HTTP Upload (4)
- [ ] DiscoverHTTPUploadService
- [ ] RequestHTTPUploadSlot
- [ ] UploadFile
- [ ] UploadFileHTTP

## HTTP Over XMPP (2)
- [ ] HTTPOverXMPP
- [ ] VerifyHTTPRequest

## Ad-Hoc Commands (4)
- [ ] CancelCommand
- [ ] DiscoverCommands
- [ ] ExecuteCommand
- [ ] ListClientAccess
- [ ] RevokeClientAccess

## Data Forms (4)
- [ ] CancelForm
- [ ] DataFormsFileInput
- [ ] ProcessFormResult
- [ ] SubmitForm

## Bookmarks (6)
- [ ] BookmarksConversion
- [ ] GetBookmarks
- [ ] RemoveBookmark
- [ ] RemoveBookmarkPEP
- [ ] SetBookmark
- [ ] SetBookmarkAutoJoin
- [ ] SetBookmarkPEP

## Chat Management (9)
- [ ] ArchiveChat
- [ ] EditChatDescription
- [ ] EditChatTitle
- [ ] GetChatInfo
- [ ] GetDialogs
- [ ] GetInbox
- [ ] LeaveChat
- [ ] MuteChat
- [ ] SetChatNotificationSettings

## Group & Channel Management (9)
- [ ] AddMembers
- [ ] CreateChannel
- [ ] CreateGroup
- [ ] CreateServerSpace
- [ ] GetInviteLink
- [ ] GetMembers
- [ ] RemoveMember
- [ ] SearchChannels
- [ ] SetAdmin
- [ ] UnbanMember

## Forum & Topics (2)
- [ ] CreateForum
- [ ] CreateTopic

## Polls (2)
- [ ] CreatePoll
- [ ] VotePoll

## Search (3)
- [ ] SearchGlobal
- [ ] SearchMessages
- [ ] SearchUsersExtended
- [ ] SearchUsersXMPP

## File URL Sharing (2)
- [ ] SendFileURL
- [ ] SendSIMS

## Push Notifications (2)
- [ ] DisablePushNotifications
- [ ] EnablePushNotifications

## Carbons (2)
- [ ] DisableCarbons
- [ ] EnableCarbons

## Privacy Lists (3)
- [ ] GetPrivacyLists
- [ ] SetActiveList
- [ ] SetDefaultList

## Private XML Storage (2)
- [ ] RetrievePrivateXML
- [ ] StorePrivateXML

## Offline Messages (3)
- [ ] GetOfflineMessageCount
- [ ] GetOfflineMessageHeaders
- [ ] RemoveOfflineMessages
- [ ] RetrieveOfflineMessages

## External Services (3)
- [ ] DiscoverExternalServices
- [ ] GetTURNCredentials
- [ ] RequestOnlineMeeting

## Microblogging & Social (2)
- [ ] PublishMicroblog
- [ ] PublishSocialFeed

## Account Management (3)
- [ ] ExportAccountData
- [ ] ImportAccountData
- [ ] HandleCAPTCHA

## Miscellaneous (12)
- [ ] CreateFolder
- [ ] CreateInvitationURI
- [ ] GetDataPolicy
- [ ] GetEntityTime
- [ ] GetFolders
- [ ] GetLastActivity
- [ ] GetLastUserInteraction
- [ ] GetLinkMetadata
- [ ] GetReadState
- [ ] GetServiceOutageStatus
- [ ] GetStickerPack
- [ ] OnUpdate
- [ ] RSMQuery
- [ ] SendPing
- [ ] SetReminder
- [ ] SetServerNotificationFilter

## Core Interface (1)
- [ ] GetMessages
