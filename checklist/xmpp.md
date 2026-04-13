## Phase 12: XMPP — DONE (core), gaps remain

178 exported methods, ~5,079 lines. ~125+ additional methods identified from RFCs/XEPs but not yet in core. Pure Go stdlib only. 32/32 tests pass against yax.im (Prosody).

### Core Interface (55/55)

- [x] Name
- [x] Capabilities
- [x] Authenticate (SCRAM-SHA-256 / SCRAM-SHA-1 / PLAIN)
- [x] Logout
- [x] GetDialogs
- [x] CreateGroup (MUC)
- [x] CreateChannel (MUC public)
- [x] CreateTopic
- [x] GetFolders
- [x] CreateFolder
- [x] SendMessage
- [x] GetMessages (local buffer + MAM)
- [x] EditMessage (XEP-0308 correction)
- [x] DeleteMessage
- [x] ReplyToMessage (XEP-0461)
- [x] ForwardMessage
- [x] ReactToMessage (XEP-0444)
- [x] PinMessage
- [x] UnpinMessage
- [x] MarkAsRead
- [x] GetReadState
- [x] UploadFile (XEP-0363 HTTP Upload)
- [x] DownloadFile
- [x] SendImageBase64
- [x] StartCall (Jingle XEP-0166)
- [x] JoinGroupCall — returns ErrNotSupported
- [x] EndCall
- [x] SetCallMuted — returns ErrNotSupported
- [x] GetProfile (vCard)
- [x] OnUpdate
- [x] Close
- [x] GetChatInfo
- [x] EditChatTitle
- [x] EditChatDescription
- [x] LeaveChat
- [x] GetInviteLink
- [x] AddMembers (MUC invite)
- [x] RemoveMember
- [x] BanMember
- [x] UnbanMember
- [x] GetMembers
- [x] SetAdmin
- [x] GetContacts (roster)
- [x] AddContact (roster add)
- [x] DeleteContact (roster remove)
- [x] BlockUser (XEP-0191)
- [x] UnblockUser
- [x] GetBlockedUsers
- [x] SearchMessages (local buffer)
- [x] SearchGlobal
- [x] SendTyping (XEP-0085 composing)
- [x] CreatePoll — returns ErrNotSupported
- [x] VotePoll — returns ErrNotSupported
- [x] SendSticker — returns ErrNotSupported
- [x] GetSessions
- [x] TerminateSession — returns ErrNotSupported

### Presence (14)

- [x] SendPresenceAvailable
- [x] SendPresenceUnavailable
- [x] SendPresenceAway
- [x] SendPresenceDND
- [x] SendPresenceXA
- [x] SendPresenceChat
- [x] SetPresenceStatus
- [x] SetPresencePriority
- [x] SendPresenceSubscribe
- [x] SendPresenceSubscribed
- [x] SendPresenceUnsubscribe
- [x] SendPresenceUnsubscribed
- [x] SendDirectedPresence
- [x] ProbePresence

### Roster (5)

- [x] GetRoster
- [x] AddRosterItem
- [x] RemoveRosterItem
- [x] SetRosterItemName
- [x] SetRosterItemGroups

### Chat States (5)

- [x] SendChatStateActive
- [x] SendChatStateComposing
- [x] SendChatStatePaused
- [x] SendChatStateInactive
- [x] SendChatStateGone

### Message Types (4)

- [x] SendChatMessage
- [x] SendGroupchatMessage
- [x] SendHeadlineMessage
- [x] SendNormalMessage

### Message Extensions (8)

- [x] CorrectMessage (XEP-0308)
- [x] RequestReceipt (XEP-0184)
- [x] SendReceipt
- [x] SendDisplayedMarker (XEP-0333)
- [x] SendReceivedMarker
- [x] SendOOBURL (XEP-0066)
- [x] SetMessageHint (XEP-0334)
- [x] SendReply (XEP-0461)
- [x] SendReaction (XEP-0444)
- [x] SendFileURL

### Carbons (2)

- [x] EnableCarbons (XEP-0280)
- [x] DisableCarbons

### MUC (22)

- [x] JoinMUC
- [x] LeaveMUC
- [x] SetMUCNick
- [x] GetMUCOccupants
- [x] GetMUCInfo
- [x] SetMUCSubject
- [x] SendMUCInvitation (XEP-0249)
- [x] SendMUCMediatedInvite (XEP-0045)
- [x] DeclineMUCInvitation
- [x] SetMUCRole
- [x] SetMUCAffiliation
- [x] KickFromMUC
- [x] BanFromMUC
- [x] UnbanFromMUC
- [x] GrantVoice
- [x] RevokeVoice
- [x] GetMUCConfig
- [x] ConfigureMUC
- [x] DestroyMUC
- [x] CreateInstantMUC
- [x] RequestMUCHistory
- [x] MUCSelfPing (XEP-0410)

### Service Discovery (7)

- [x] DiscoInfo (XEP-0030)
- [x] DiscoItems
- [x] QueryFeatures
- [x] QueryIdentity
- [x] DiscoverMUCService
- [x] DiscoverHTTPUploadService
- [x] DiscoverExternalServices (XEP-0215)

### HTTP Upload (3)

- [x] RequestHTTPUploadSlot (XEP-0363)
- [x] UploadFileHTTP
- [x] DownloadFileHTTP

### PubSub (9)

- [x] CreatePubSubNode (XEP-0060)
- [x] DeletePubSubNode
- [x] PublishPubSubItem
- [x] RetractPubSubItem
- [x] SubscribePubSub
- [x] UnsubscribePubSub
- [x] GetPubSubItems
- [x] GetPubSubSubscriptions
- [x] ConfigurePubSubNode

### PEP (6)

- [x] SetUserMood (XEP-0107)
- [x] SetUserActivity (XEP-0108)
- [x] SetUserTune (XEP-0118)
- [x] SetUserLocation (XEP-0080)
- [x] SetAvatarPEP (XEP-0084)
- [x] GetAvatarPEP

### vCard (4)

- [x] GetVCard (XEP-0054)
- [x] SetVCard
- [x] GetVCardField
- [x] SetAvatarVCard (XEP-0153)

### Blocking (3)

- [x] BlockJID (XEP-0191)
- [x] UnblockJID
- [x] GetBlocklist

### Bookmarks (4)

- [x] GetBookmarks (XEP-0048)
- [x] SetBookmark
- [x] RemoveBookmark
- [x] SetBookmarkAutoJoin

### MAM (4)

- [x] QueryMAM (XEP-0313)
- [x] QueryMAMByJID
- [x] QueryMAMByDateRange
- [x] QueryMAMPage

### Registration (3)

- [x] RegisterAccount (XEP-0077)
- [x] ChangePassword
- [x] UnregisterAccount

### Stream Management (4)

- [x] EnableStreamManagement (XEP-0198)
- [x] RequestAck
- [x] SendAck
- [x] ResumeStream

### IQ Queries (4)

- [x] SendPing (XEP-0199)
- [x] GetSoftwareVersion (XEP-0092)
- [x] GetLastActivity (XEP-0012)
- [x] GetEntityTime (XEP-0202)

### Client State (2)

- [x] SetClientStateActive (XEP-0352)
- [x] SetClientStateInactive

### Entity Capabilities (1)

- [x] GetEntityCapabilities (XEP-0115)

### Jingle / Calls (5)

- [x] InitiateJingle (XEP-0166)
- [x] AcceptJingle
- [x] RejectJingle
- [x] TerminateJingle
- [x] SendJingleTransportInfo

### TURN (1)

- [x] GetTURNCredentials (XEP-0215)

### Verified on yax.im (Prosody) — 32/32 tests pass

---

### Not Added in Core

Methods found in the XMPP protocol ecosystem (RFCs + XEPs) but not yet implemented.

#### Message Moderation (XEP-0425)

- [ ] ModerateMessage (retract another user's message in MUC)

#### Jingle Message Initiation (XEP-0353)

- [ ] ProposeCall (pre-Jingle call proposal via message)
- [ ] AcceptProposal
- [ ] RejectProposal
- [ ] RetractProposal
- [ ] ProceedToJingle

#### Jingle Extended (XEP-0166 additions)

- [ ] JingleContentAdd (add content mid-session)
- [ ] JingleContentAccept
- [ ] JingleContentReject
- [ ] JingleContentModify
- [ ] JingleContentRemove
- [ ] JingleTransportReplace (fallback transport)
- [ ] JingleTransportAccept
- [ ] JingleTransportReject

#### Jingle File Transfer (XEP-0234)

- [ ] JingleFileOffer
- [ ] JingleFileRequest
- [ ] JingleFileChecksum
- [ ] JingleFileReceived
- [ ] JingleFileResume

#### Jingle RTP Quality (XEP-0293 / XEP-0294)

- [ ] NegotiateRTCPFeedback
- [ ] NegotiateRTPHeaderExtensions

#### OMEMO Encryption (XEP-0384)

- [ ] PublishOMEMODeviceList
- [ ] FetchOMEMODeviceList
- [ ] PublishOMEMOBundle
- [ ] FetchOMEMOBundle
- [ ] OMEMOEncrypt
- [ ] OMEMODecrypt
- [ ] OMEMOBuildSession

#### MIX (XEP-0369, experimental)

- [ ] JoinMIXChannel
- [ ] LeaveMIXChannel
- [ ] SetMIXNick
- [ ] UpdateMIXSubscriptions
- [ ] CreateMIXChannel
- [ ] DestroyMIXChannel

#### Push Notifications (XEP-0357)

- [ ] EnablePushNotifications
- [ ] DisablePushNotifications

#### Ad-Hoc Commands (XEP-0050)

- [ ] DiscoverCommands
- [ ] ExecuteCommand
- [ ] CancelCommand

#### Privacy Lists (XEP-0016, deprecated)

- [ ] GetPrivacyLists
- [ ] SetActiveList
- [ ] SetDefaultList

#### Flexible Offline Messages (XEP-0013)

- [ ] GetOfflineMessageCount
- [ ] GetOfflineMessageHeaders
- [ ] RetrieveOfflineMessages
- [ ] RemoveOfflineMessages

#### Stanza Content Encryption (XEP-0420)

- [ ] EncryptStanzaContent
- [ ] DecryptStanzaContent

#### SASL2 / Bind2 / FAST (XEP-0388 / XEP-0386 / XEP-0484)

- [ ] SASL2Authenticate (inline SASL)
- [ ] Bind2 (inline resource binding)
- [ ] FASTReconnect (token-based fast reconnect)

#### Data Forms (XEP-0004)

- [ ] SubmitForm
- [ ] CancelForm
- [ ] ProcessFormResult

#### Private XML Storage (XEP-0049)

- [ ] StorePrivateXML
- [ ] RetrievePrivateXML

#### PEP Native Bookmarks (XEP-0402)

- [ ] SetBookmarkPEP (individual PubSub items)
- [ ] RemoveBookmarkPEP

#### Stateless File Sharing (XEP-0447)

- [ ] ShareFileMetadata
- [ ] ShareFileSources

#### vCard4 (XEP-0292)

- [ ] GetVCard4
- [ ] SetVCard4

#### HTTP Authentication (XEP-0070)

- [ ] VerifyHTTPRequest

#### Message References (XEP-0372)

- [ ] SendMessageReference

#### XHTML-IM (XEP-0071)

- [ ] SendRichTextMessage

#### Anonymous Occupant IDs (XEP-0421)

- [ ] HandleOccupantId

#### MAM Preferences (XEP-0313 / XEP-0441, not added)

- [ ] GetMAMPreferences — retrieve archive preferences (always/never/roster)
- [ ] SetMAMPreferences — configure which JIDs are archived

#### PubSub Extended (XEP-0060, not added)

- [ ] PurgeNode — remove all items from a node
- [ ] GetNodeAffiliations — list affiliations on a node
- [ ] SetNodeAffiliation — set affiliation for a JID on a node
- [ ] GetNodeSubscribers — list all subscribers to a node

#### Jabber Search (XEP-0055, not added)

- [ ] SearchUsers — query a user directory (data form search)

#### In-Band Bytestreams (XEP-0047, not added)

- [ ] OpenIBBSession — open in-band bytestream (fallback file transfer)
- [ ] SendIBBData — send data chunk over IBB
- [ ] CloseIBBSession

#### SOCKS5 Bytestreams (XEP-0065, not added)

- [ ] InitiateS5B — initiate SOCKS5 proxy-mediated file transfer
- [ ] ActivateS5B — activate the bytestream after proxy connection

#### MUC Voice Request (XEP-0045, not added)

- [ ] RequestMUCVoice — request voice (participant role) in moderated room

#### User Nickname (XEP-0172, not added)

- [ ] SetUserNickname — publish PEP nickname
- [ ] GetUserNickname

#### OpenPGP for XMPP (XEP-0373/0374, not added)

- [ ] PublishOXPublicKey — publish OpenPGP public key via PEP
- [ ] FetchOXPublicKey
- [ ] OXEncrypt / OXDecrypt
- [ ] OXSignEncrypt — sign + encrypt (XEP-0374 OX-IM)

#### Explicit Message Encryption (XEP-0380, not added)

- [ ] SetEncryptionHint — add EME element indicating encryption protocol

#### Last User Interaction (XEP-0319, not added)

- [ ] GetLastUserInteraction — get idle time for a contact

#### Advanced Message Processing (XEP-0079, not added)

- [ ] SetAMPRules — per-message delivery conditions (expire, deliver, match-resource)

#### Stickers (XEP-0449, not added)

- [ ] GetStickerPack — retrieve sticker pack from PubSub
- [ ] SendStickerXEP — send per XEP-0449

#### Encryption for File Sharing (XEP-0448, not added)

- [ ] ShareEncryptedFile — AESGCM-encrypted file sharing with XEP-0447 metadata

#### OMEMO Media Sharing (XEP-0454, not added)

- [ ] EncryptMedia / DecryptMedia

#### Trust Messages (XEP-0434, not added)

- [ ] SendTrustMessage — communicate key trust/distrust for OMEMO

#### Message Displayed Synchronization (XEP-0490, not added)

- [ ] SyncDisplayedMessages — synchronize read markers across devices

#### Fallback Indication (XEP-0428, not added)

- [ ] SetFallbackIndication — mark body as fallback for unsupported extensions

#### SASL Channel-Binding (XEP-0440, not added)

- [ ] NegotiateChannelBinding — advertise/negotiate SCRAM channel-binding type

#### Alternative Connections (XEP-0156, not added)

- [ ] DiscoverAlternativeConnections — HTTP well-known / DNS TXT for WebSocket/BOSH

#### WebSocket Transport (RFC 7395, not added)

- [ ] ConnectWebSocket — XMPP over WebSocket

#### BOSH Transport (XEP-0124/0206, not added)

- [ ] ConnectBOSH — XMPP-over-BOSH session (long-polling HTTP fallback)
