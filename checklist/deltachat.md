## Phase 5: Delta Chat — DONE (core complete, extras pending)

92 exported methods, ~4,859 lines. 132 method tests ALL PASS on real chatmail (2026-04-09).
~43 additional methods discovered in deltachat-core-rust C FFI + JSON-RPC — not yet implemented.

### Core Interface (55/55)

- [x] Name
- [x] Capabilities
- [x] Authenticate
- [x] Logout
- [x] GetDialogs
- [x] CreateGroup
- [x] CreateChannel
- [x] CreateTopic
- [x] GetFolders
- [x] CreateFolder
- [x] SendMessage
- [x] GetMessages
- [x] EditMessage
- [x] DeleteMessage
- [x] ReplyToMessage
- [x] ForwardMessage
- [x] ReactToMessage
- [x] PinMessage
- [x] UnpinMessage
- [x] MarkAsRead
- [x] GetReadState
- [x] UploadFile
- [x] DownloadFile
- [x] SendImageBase64
- [x] StartCall
- [x] JoinGroupCall
- [x] EndCall
- [x] SetCallMuted
- [x] GetProfile
- [x] OnUpdate
- [x] Close
- [x] GetChatInfo
- [x] EditChatTitle
- [x] EditChatDescription
- [x] LeaveChat
- [x] GetInviteLink
- [x] AddMembers
- [x] RemoveMember
- [x] BanMember
- [x] UnbanMember
- [x] GetMembers
- [x] SetAdmin
- [x] GetContacts
- [x] AddContact
- [x] DeleteContact
- [x] BlockUser
- [x] UnblockUser
- [x] GetBlockedUsers
- [x] SearchMessages
- [x] SearchGlobal
- [x] SendTyping
- [x] CreatePoll
- [x] VotePoll
- [x] SendSticker
- [x] GetSessions
- [x] TerminateSession

### DC-Specific Methods (49)

- [x] AcceptIncomingCall
- [x] GetCallInfo
- [x] SendVideochatInvitation
- [x] ResendMessage
- [x] GetFreshMessages
- [x] SaveMessages
- [x] GetReactions
- [x] SendHTML
- [x] SetDraft
- [x] GetDraft
- [x] SetChatImage
- [x] RemoveChatImage
- [x] SetChatVisibility
- [x] SetChatMuted
- [x] SetChatProtected
- [x] AcceptChat
- [x] BlockChat
- [x] SetEphemeralTimer
- [x] GetEphemeralTimer
- [x] GetEncryptionInfo
- [x] GetConnectivity
- [x] SyncNow
- [x] SendLocation
- [x] StartLocationStreaming
- [x] StopLocationStreaming
- [x] ExportBackup
- [x] ImportBackup
- [x] ImportVCard
- [x] MakeVCard
- [x] SendContact
- [x] SetPeerPublicKey
- [x] SetStatus
- [x] GetStatus
- [x] SetAvatar
- [x] CheckQR
- [x] SecureJoin

### Implementation Details

- [x] Bot mode (isBot flag, auto-delete processed messages)
- [x] Auth: IMAP TLS/STARTTLS/insecure + SMTP TLS/STARTTLS/plain
- [x] Chatmail auto-discovery (DNS SRV + domain fallback)
- [x] Ed25519/Cv25519 keypair generation (Autocrypt)
- [x] Autocrypt header on all outgoing messages
- [x] IMAP IDLE (3 connections: INBOX + DeltaChat + ops, 28-min restart)
- [x] PGP/MIME encryption/decryption (wrapPGPMIME/decryptPGPMIME)
- [x] Session persistence (JSON: keypair, peer states, chats, pins, folders)

### Verified Tests (132/132)

All tests pass — see previous session notes for full list.

### Multi-Instance (8/8 chatmail servers)

nine.testrun.org, mehl.cloud, mailchat.pl, chatmail.woodpeckersnest.space, chat.adminforge.de, tarpit.fun, chatmail.au, chatmail.email — all pass.

### Dependencies

`go-imap/v2`, `go-smtp`, `go-message`, `go-sasl`, `ProtonMail/go-crypto`, `pion/webrtc/v4` — all pure Go.

### Not Added in Core

Methods found in deltachat-core-rust (C FFI + JSON-RPC) not yet implemented in the Go core.

**Webxdc (entire subsystem):**
- [ ] SendWebxdcStatusUpdate
- [ ] GetWebxdcStatusUpdates
- [ ] GetWebxdcInfo
- [ ] GetWebxdcBlob
- [ ] SetWebxdcIntegration
- [ ] InitWebxdcIntegration
- [ ] SendWebxdcRealtimeData
- [ ] SendWebxdcRealtimeAdvertisement
- [ ] LeaveWebxdcRealtime

**Account Management:**
- [ ] DeactivateAccount / RequestDeleteAccount
- [ ] ChangePassphrase
- [ ] GetAccountFileSize
- [ ] GetStorageUsageReport

**Key Transfer (Autocrypt Setup Message):**
- [ ] InitiateKeyTransfer
- [ ] ContinueKeyTransfer

**Key Management:**
- [ ] ExportSelfKeys
- [ ] ImportSelfKeys
- [ ] PreconfigureKeypair

**Device Messages:**
- [ ] AddDeviceMessage
- [ ] WasDeviceMsgEverAdded

**Stickers (JSON-RPC):**
- [ ] GetStickerFolder
- [ ] GetStickers
- [ ] SaveSticker

**Advanced Chat:**
- [ ] CreateBroadcastList
- [ ] EstimateAutoDeletionCount
- [ ] GetSimilarChats
- [ ] DeleteMessagesForAll
- [ ] ForwardMessagesToAccount

**Provider (email auto-config):**
- [ ] GetProviderInfo

**Push:**
- [ ] SetPushDeviceToken
- [ ] GetPushState

**Transport (multi-account):**
- [ ] AddTransport
- [ ] ListTransports
- [ ] DeleteTransport

**Location (not added — §13):**
- [ ] GetLocations — retrieve stored location history
- [ ] IsLocationStreaming — check if currently streaming to a chat

**Download-on-Demand (not added — §20):**
- [ ] DownloadFullMessage — download full body for partially-downloaded messages

**Configuration (not added — §2/§10/§20):**
- [ ] SetShowEmails — control display of non-DC classical emails (Off/AcceptedContacts/All)
- [ ] SetDownloadLimit — set max auto-download size in bytes
- [ ] SetCallFilter — control who can call (Everybody/Contacts/Nobody)

**Quota (not added — §2):**
- [ ] GetQuota — check IMAP mailbox quota usage via GETQUOTAROOT

**HTML (not added — §3):**
- [ ] GetMessageHTML — get original HTML version of a received message

**Contact (not added — §19):**
- [ ] WasContactSeenRecently — check if a contact was seen recently

---
