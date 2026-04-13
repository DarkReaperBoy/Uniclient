## Phase 7: Matrix — DONE (core complete, 60+ methods not yet in core)

167 exported methods, ~5,900 lines. SDK: maunium.net/go/mautrix.
All 64 additional methods implemented (not yet tested).

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
- [x] UploadFile (including encrypted file upload via AES-256-CTR)
- [x] DownloadFile (including encrypted file download)
- [x] SendImageBase64
- [x] StartCall
- [x] JoinGroupCall — returns ErrNotSupported (MSC3401, deferred)
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
- [x] AddContact — returns ErrNotSupported (Matrix uses @user:server)
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

### Calls (8)

- [x] StartCall (pion PeerConnection + SDP offer + m.call.invite)
- [x] AcceptCall (SDP answer + m.call.answer)
- [x] RejectCall (m.call.reject)
- [x] EndCall (m.call.hangup)
- [x] SetCallMuted (pion track control)
- [x] SetCallAudioSource (pluggable audio input)
- [x] SetCallAudioSink (pluggable audio output)
- [ ] Mid-call renegotiation (m.call.negotiate) — **NOT ADDED IN CORE** (deferred)

### E2EE (11)

- [x] EnableEncryption
- [x] GetEncryptionInfo
- [x] ExportKeys
- [x] ImportKeys
- [x] VerifyDevice
- [x] StartSASVerification
- [x] AcceptSASVerification
- [x] ConfirmSASEmojis
- [x] CancelVerification
- [x] CreateKeyBackup
- [x] RestoreKeyBackup
- [x] GetKeyBackupInfo

### Profile & Presence (4)

- [x] GetPresence
- [x] SetPresence
- [x] SetDisplayName
- [x] SetAvatar

### Room Management (10)

- [x] GetRoomAliases
- [x] SetRoomAlias
- [x] DeleteRoomAlias
- [x] GetPublicRooms
- [x] JoinRoom
- [x] JoinRoomByAlias
- [x] KnockRoom
- [x] ForgetRoom
- [x] SetRoomAvatar
- [x] UpgradeRoom

### Room Settings (4)

- [x] SetJoinRules
- [x] SetHistoryVisibility
- [x] SetRoomTag
- [x] RemoveRoomTag

### Search (1)

- [x] SearchUsers

### Direct Chats (2)

- [x] GetDirectChats
- [x] SetDirectChat

### Threads (2)

- [x] GetThreads
- [x] GetThreadReplies

### Spaces (3)

- [x] GetSpaceChildren
- [x] AddSpaceChild
- [x] RemoveSpaceChild

### Moderation (2)

- [x] MarkUnread
- [x] ReportEvent

### Device Management (1)

- [x] SetDeviceName

### Server Info (2)

- [x] GetURLPreview
- [x] GetTurnServer

### Auto-reconnect

- [x] startSync retry loop with 5s backoff

### Verified Tests

Auth, E2EE (init, send/receive, key export/import, SAS verification, key backup, persistence), dialogs, rooms, messages, calls (two-user, audio pipe, interop), contacts, polls, stickers, sessions, spaces, tags, presence, display name, mark unread, search users — all pass.

### Dependencies

`maunium.net/go/mautrix`, `pion/webrtc/v4` — all pure Go (with goolm build tag).

### Extended Methods (64 — all implemented, not yet tested)

#### VoIP (6)

- [x] AcceptCallSelectAnswer (m.call.select_answer — glare handling)
- [x] SendCallCandidates (m.call.candidates — trickle ICE)
- [x] CallReplaces (m.call.replaces — call transfer)
- [x] SDPStreamMetadataChanged (m.call.sdp_stream_metadata_changed)
- [x] CallNotify (m.call.notify)
- [x] GroupCallEncryptionKeys (m.call.encryption_keys — MatrixRTC)

#### Registration / Account (6)

- [x] Register (create account)
- [x] DeactivateAccount
- [x] ChangePassword
- [x] CheckUsernameAvailability
- [x] RequestEmailToken
- [x] RequestMsisdnToken

#### 3PID Management (5)

- [x] Get3PIDs
- [x] Add3PID
- [x] Bind3PID
- [x] Delete3PID
- [x] Unbind3PID

#### Push Notifications (7)

- [x] GetPushers
- [x] SetPusher
- [x] GetPushRules
- [x] SetPushRule
- [x] DeletePushRule
- [x] EnablePushRule
- [x] GetNotifications

#### Room State Events (4)

- [x] SetPowerLevels
- [x] SetGuestAccess
- [x] SetServerACL
- [x] GetRoomState

#### Room Visibility (2)

- [x] GetRoomVisibility
- [x] SetRoomVisibility

#### Filters (2)

- [x] CreateFilter
- [x] GetFilter

#### Account Data (4)

- [x] SetAccountData
- [x] GetAccountData
- [x] SetRoomAccountData
- [x] GetRoomAccountData

#### To-Device (1)

- [x] SendToDevice

#### Reporting (2)

- [x] ReportRoom
- [x] ReportUser

#### Third-Party Protocol (3)

- [x] GetThirdPartyProtocols
- [x] LookupThirdPartyLocation
- [x] LookupThirdPartyUser

#### OpenID (1)

- [x] RequestOpenIDToken

#### Cross-Signing (3)

- [x] UploadCrossSigningKeys
- [x] UploadSignatures
- [x] GenerateCrossSigningKeys

#### SSSS / Secret Storage (2)

- [x] SetSecretStorageKey
- [x] GetSecretStorageKey

#### Admin (1)

- [x] WhoisUser

#### Media (3)

- [x] GetMediaConfig
- [x] CreateMXCURI
- [x] DownloadThumbnail

#### Rooms / State (3)

- [x] GetEvent
- [x] GetEventContext
- [x] ResolveAlias

#### Auth / Login (2)

- [x] GetLoginFlows
- [x] LogoutAll

#### Tags (1)

- [x] GetTags

#### Read Receipts (2)

- [x] SendPrivateReadReceipt
- [x] SetReadMarkers

#### Devices (2)

- [x] GetDeviceInfo
- [x] DeleteDevices

#### Server Discovery (2)

- [x] GetCapabilities
- [x] GetVersions

---
