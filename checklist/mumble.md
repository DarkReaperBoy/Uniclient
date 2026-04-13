## Phase 9: Mumble — DONE (core); missing protocol methods below

133 exported methods, ~5,200 lines. Real Mumble client protocol. TLS+protobuf TCP + OCB2-AES128 UDP voice. Hand-coded protobuf (no protoc). Pure Go. 15 client protocol methods added; 7 Ice RPC admin methods still need real implementation via Murmur Ice endpoint.

### Core Interface (55/55)

- [x] Name
- [x] Capabilities
- [x] Authenticate
- [x] Logout
- [x] GetDialogs
- [x] CreateGroup — alias to CreateChannel
- [x] CreateChannel
- [x] CreateTopic — returns ErrNotSupported
- [x] GetFolders — returns ErrNotSupported
- [x] CreateFolder — returns ErrNotSupported
- [x] SendMessage
- [x] GetMessages
- [x] EditMessage — returns ErrNotSupported
- [x] DeleteMessage — returns ErrNotSupported
- [x] ReplyToMessage
- [x] ForwardMessage
- [x] ReactToMessage — returns ErrNotSupported
- [x] PinMessage — returns ErrNotSupported
- [x] UnpinMessage — returns ErrNotSupported
- [x] MarkAsRead — returns ErrNotSupported
- [x] GetReadState — returns ErrNotSupported
- [x] UploadFile — returns ErrNotSupported
- [x] DownloadFile — returns ErrNotSupported
- [x] SendImageBase64
- [x] StartCall — returns ErrNotSupported (voice is always-on)
- [x] JoinGroupCall — returns ErrNotSupported
- [x] EndCall — returns ErrNotSupported
- [x] SetCallMuted — returns ErrNotSupported
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
- [x] AddContact — returns ErrNotSupported
- [x] DeleteContact — returns ErrNotSupported
- [x] BlockUser
- [x] UnblockUser
- [x] GetBlockedUsers
- [x] SearchMessages
- [x] SearchGlobal
- [x] SendTyping — returns ErrNotSupported
- [x] CreatePoll — returns ErrNotSupported
- [x] VotePoll — returns ErrNotSupported
- [x] SendSticker — returns ErrNotSupported
- [x] GetSessions
- [x] TerminateSession

### Voice (5)

- [x] SendVoice (UDP encrypted)
- [x] SendVoiceTCP (TCP tunnel fallback)
- [x] SendVoiceTerminator
- [x] SendVoiceWhisper
- [x] OnVoice

### Channel Management (10)

- [x] CreateTemporaryChannel
- [x] DeleteChannel
- [x] MoveChannel
- [x] SetChannelPosition
- [x] SetChannelMaxUsers
- [x] LinkChannels
- [x] UnlinkChannels
- [x] AddChannelListener
- [x] RemoveChannelListener
- [x] SetListenerVolume

### User Control (9)

- [x] MoveToChannel
- [x] MoveUser
- [x] ServerMute
- [x] ServerDeaf
- [x] SelfMute
- [x] SelfDeaf
- [x] Suppress
- [x] SetComment
- [x] SetTexture

### Messaging (1 extra)

- [x] SendTreeMessage

### Registration (4)

- [x] RegisterSelf
- [x] RegisterUser
- [x] GetRegisteredUsers
- [x] UnregisterUser

### Admin (9)

- [x] GetACL
- [x] SetACL
- [x] GetPermissions
- [x] GetBanList
- [x] SetBanList
- [x] AddBan
- [x] SetPrioritySpeaker
- [x] SetRecording
- [x] SetAccessTokens

### Query/Utility (6)

- [x] QueryUsers
- [x] RequestBlob
- [x] GetUserStats
- [x] SendPluginData
- [x] TriggerContextAction
- [x] RequestNonceResync

### Voice Target (1)

- [x] SetVoiceTarget

### Server Config (1)

- [x] GetServerConfig

### Server Discovery (2)

- [x] MumbleServerPing (standalone)
- [x] GetPublicServers

### Debug Methods (8)

- [x] DebugBuildVoicePacket
- [x] DebugBuildLegacyVoicePacket
- [x] DebugVoiceTunnelCount
- [x] DebugCodecVersion
- [x] DebugUserFlags
- [x] DebugServerVersion
- [x] DebugMySession
- [x] DebugState

### Crypto (MumbleCryptState) (3)

- [x] Init
- [x] Encrypt
- [x] Decrypt

### Standalone Functions (2)

- [x] OCB2Encrypt
- [x] OCB2Decrypt

### Verified Audio

- OCB2-AES128 roundtrip, loopback, two-client bidirectional 100% byte-perfect
- Public servers: contraclan (legacy 1.3.4) + voice.xts-clan.de (modern 1.5.517)
- Version auto-detect, TCP tunnel fallback

### Additional Protocol Methods (all implemented)

#### User State (3)

- [x] SetPluginContext — set UserState.plugin_context (positional audio plugin coordination)
- [x] SetPluginIdentity — set UserState.plugin_identity (plugin identity string)
- [x] SetTemporaryAccessTokens — set UserState.temporary_access_tokens

#### Voice (2)

- [x] SendPositionalAudio — voice packet with X,Y,Z float32 positional coordinates (protobuf + legacy)
- [x] ServerLoopback — send voice with target=31 for server echo test

#### Context Actions (2)

- [x] HandleContextActionModify — callback for server-defined context action add/remove notifications
- [x] TriggerContextActionChannel — context action targeting a channel

#### Ban Management (1)

- [x] RemoveBan — remove a single ban entry by address+mask

#### Connection (4)

- [x] SendVersion — explicit version announcement (Version message)
- [x] HandleReject — callback for connection rejection (Reject message with reason/type)
- [x] HandlePermissionDenied — callback for permission denial events (PermissionDenied message)
- [x] HandleSuggestConfig — callback for server configuration suggestions (SuggestConfig message)

#### Codec (2)

- [x] HandleCodecVersion — callback for server codec negotiation (CodecVersion message)
- [x] SetPreferredCodec — set Opus vs CELT preference for next connection

#### Admin Ice RPC (7 — need Murmur Ice RPC implementation)

- [ ] GetServerLog — retrieve server log entries (Ice RPC)
- [ ] GetServerUptime — query server uptime (Ice RPC)
- [ ] UpdateCertificate — update server TLS certificate (Ice RPC)
- [ ] SendWelcomeMessage — set/update server welcome message (Ice RPC)
- [ ] RedirectWhisperGroup — redirect a whisper group (Ice RPC)
- [ ] AddContextCallback — register server-side context action callback (Ice RPC)
- [ ] RemoveContextCallback — unregister server-side context action callback (Ice RPC)

#### DNS / Discovery (1)

- [x] MumbleResolveSRV — DNS SRV record lookup for `_mumble._tcp.<hostname>`

---
