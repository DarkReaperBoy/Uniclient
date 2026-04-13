## Phase 7: Matrix — DONE (core complete, 60+ methods not yet in core)

103 exported methods, ~4,397 lines. SDK: maunium.net/go/mautrix.

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

### Not Added in Core

Methods/endpoints found in the official Matrix Client-Server API spec and mautrix-go SDK but not yet implemented.

#### VoIP (6)

- [ ] AcceptCallSelectAnswer (m.call.select_answer — glare handling)
- [ ] SendCallCandidates (m.call.candidates — trickle ICE)
- [ ] CallReplaces (m.call.replaces — call transfer)
- [ ] SDPStreamMetadataChanged (m.call.sdp_stream_metadata_changed)
- [ ] CallNotify (m.call.notify)
- [ ] GroupCallEncryptionKeys (m.call.encryption_keys — MatrixRTC)

#### Registration / Account (5)

- [ ] Register (create account)
- [ ] DeactivateAccount
- [ ] ChangePassword
- [ ] CheckUsernameAvailability
- [ ] RequestEmailToken / RequestMsisdnToken

#### 3PID Management (5)

- [ ] Get3PIDs
- [ ] Add3PID
- [ ] Bind3PID
- [ ] Delete3PID
- [ ] Unbind3PID

#### Push Notifications (6)

- [ ] GetPushers
- [ ] SetPusher
- [ ] GetPushRules
- [ ] SetPushRule / DeletePushRule
- [ ] EnablePushRule
- [ ] GetNotifications

#### Room State Events (4)

- [ ] SetPowerLevels (m.room.power_levels)
- [ ] SetGuestAccess (m.room.guest_access)
- [ ] SetServerACL (m.room.server_acl)
- [ ] GetRoomState (all state)

#### Room Aliases — Visibility (2)

- [ ] GetRoomVisibility
- [ ] SetRoomVisibility

#### Filters (2)

- [ ] CreateFilter
- [ ] GetFilter

#### Account Data (4)

- [ ] SetAccountData (global)
- [ ] GetAccountData (global)
- [ ] SetRoomAccountData
- [ ] GetRoomAccountData

#### To-Device (1)

- [ ] SendToDevice

#### Reporting (2)

- [ ] ReportRoom
- [ ] ReportUser

#### Third-Party Protocol (3)

- [ ] GetThirdPartyProtocols
- [ ] LookupThirdPartyLocation
- [ ] LookupThirdPartyUser

#### OpenID (1)

- [ ] RequestOpenIDToken

#### Cross-Signing (3)

- [ ] UploadCrossSigningKeys
- [ ] UploadSignatures
- [ ] GenerateCrossSigningKeys

#### SSSS / Secret Storage (2)

- [ ] SetSecretStorageKey
- [ ] GetSecretStorageKey

#### Admin (1)

- [ ] WhoisUser

#### Media (2)

- [ ] GetMediaConfig (max upload size)
- [ ] CreateMXCURI (async upload)

#### Rooms / State (not added — CS API)

- [ ] GetEvent(chatID, eventID) — `GET /rooms/{roomId}/event/{eventId}`
- [ ] GetEventContext(chatID, eventID) — `GET /rooms/{roomId}/context/{eventId}`
- [ ] ResolveAlias(alias) — `GET /directory/room/{alias}`

#### Auth / Login (not added)

- [ ] GetLoginFlows() — `GET /login` (list supported auth types)
- [ ] LogoutAll() — `POST /logout/all`

#### Media (not added)

- [ ] DownloadThumbnail(mxcURI, width, height) — server-side thumbnailing

#### Tags (not added)

- [ ] GetTags(chatID) — `GET /user/{userId}/rooms/{roomId}/tags` (read side of SetRoomTag)

#### Read Receipts (not added)

- [ ] SendPrivateReadReceipt(chatID, eventID) — `m.read.private` (v1.4+)
- [ ] SetReadMarkers(chatID, fullyRead, read) — atomic read marker update

#### Devices (not added)

- [ ] GetDeviceInfo(deviceID) — `GET /devices/{deviceId}`
- [ ] DeleteDevices(deviceIDs) — `POST /delete_devices` (bulk)

#### Server Discovery (not added)

- [ ] GetCapabilities() — `GET /capabilities` (room versions, features)
- [ ] GetVersions() — `GET /versions` (supported spec versions)

---
