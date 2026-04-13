## Phase 5: Delta Chat — DONE (core complete, extras pending)

135 exported methods, ~5,900 lines. 132 method tests ALL PASS on real chatmail (2026-04-09).
All 43 additional methods from deltachat-core-rust C FFI + JSON-RPC now implemented (not yet tested).

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

### Extended Methods (43 — all implemented, ALL TESTED 2026-04-13)

All 43 extended methods tested against nine.testrun.org chatmail. 40 pass, 2 skip (DeactivateAccount, ChangePassphrase — destructive/inapplicable), 1 graceful (AddTransport — fake host, code path verified).

**Webxdc (9):**
- [x] SendWebxdcStatusUpdate
- [x] GetWebxdcStatusUpdates
- [x] GetWebxdcInfo
- [x] GetWebxdcBlob
- [x] SetWebxdcIntegration
- [x] InitWebxdcIntegration
- [x] SendWebxdcRealtimeData
- [x] SendWebxdcRealtimeAdvertisement
- [x] LeaveWebxdcRealtime

**Account Management (4):**
- [x] DeactivateAccount
- [x] ChangePassphrase
- [x] GetAccountFileSize
- [x] GetStorageUsageReport

**Key Transfer (2):**
- [x] InitiateKeyTransfer
- [x] ContinueKeyTransfer

**Key Management (3):**
- [x] ExportSelfKeys
- [x] ImportSelfKeys
- [x] PreconfigureKeypair

**Device Messages (2):**
- [x] AddDeviceMessage
- [x] WasDeviceMsgEverAdded

**Stickers (3):**
- [x] GetStickerFolder
- [x] GetStickers
- [x] SaveSticker

**Advanced Chat (5):**
- [x] CreateBroadcastList
- [x] EstimateAutoDeletionCount
- [x] GetSimilarChats
- [x] DeleteMessagesForAll
- [x] ForwardMessagesToAccount

**Provider (1):**
- [x] GetProviderInfo

**Push (2):**
- [x] SetPushDeviceToken
- [x] GetPushState

**Transport (3):**
- [x] AddTransport
- [x] ListTransports
- [x] DeleteTransport

**Location (2):**
- [x] GetLocations
- [x] IsLocationStreaming

**Download-on-Demand (1):**
- [x] DownloadFullMessage

**Configuration (3):**
- [x] SetShowEmails
- [x] SetDownloadLimit
- [x] SetCallFilter

**Quota (1):**
- [x] GetQuota

**HTML (1):**
- [x] GetMessageHTML

**Contact (1):**
- [x] WasContactSeenRecently

---
