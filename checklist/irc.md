# IRC — Fresh Checklist

**Methods:** 418 exported | **Lines:** 5,712 | **File:** `go/cores/irc.go`
**Protocol:** IRC (RFC 1459/2812, IRCv3, DCC, CTCP, Services)
**Last updated:** 2026-04-13

## Audit Changes (2026-04-13)

**Merged duplicates:**
- 18 `Extban*` methods → 1 `SetExtban(channel, modeChar, extbanType, value)` — all were one-liner MODE commands varying only by extban prefix and mode char
- 10 `ChanServ{Op,Deop,Voice,Devoice,Halfop,Dehalfop,Owner,Deowner,Protect,Deprotect}` → 1 `ChanServModeCmd(channel, nick, command)` — all identical pattern `PRIVMSG ChanServ :CMD #ch nick`
- 16 `Set{NoColors,NoCTCP,DelayedJoins,WordFilter,Censor,NoKnock,RequireRegistered,RequireRegisteredSpeak,NoNickChange,OperOnly,Permanent,NoKicks,StripColors,NoNotices,Auditorium,NoInvite,SSLOnly}` → 1 `SetChannelModeFlag(channel, mode, on)` — all were `chanMode(ch, X, on)` one-liners
- 9 `Set{BotMode,DeafMode,CallerID,HideOper,HideChannels,BlockUnregistered,BlockCTCP,WhoisNotify,RequireSSL}` → 1 `SetUserModeFlag(mode, on)` — all were `userMode(X, on)` one-liners
- Removed `SetBotModeIRCv3` — exact duplicate of `SetUserModeFlag('B', true)`
- `SendTyping` (Core interface) now delegates to `SendTypingIndicator` instead of being a no-op
- `MarkAsRead` (Core interface) now also calls `MarkRead` to sync server-side via IRCv3 MARKREAD

**NOT duplicates (kept both):**
- `SendTyping` (Core interface, error return) vs `SendTypingIndicator` (IRC-specific, supports on/off toggle) — different signatures and semantics
- `MarkAsRead` (Core interface, updates local state + server) vs `MarkRead` (IRC-specific, server MARKREAD only) — different levels of abstraction

**Stubs returning ErrNotSupported (Core interface compliance — IRC genuinely lacks these):**
- CreatePoll, VotePoll, SendSticker, GetSessions, TerminateSession
- MuteChat, ArchiveChat, MarkUnread, UnpinAllMessages
- AcceptCall, DeclineCall, SendLocation
- UploadFile, DownloadFile, SendImageBase64
- EditMessage, DeleteMessage, ReactToMessage
- AddContact, DeleteContact, GetContacts
- EditChatTitle (IRC channels are immutable names)
- GetInviteLink

**No dead unexported methods found** — all 56 unexported methods are called internally.

## Categories

### Connection & Authentication (18)
- [ ] Connect
- [ ] ConnectHTTPProxy
- [ ] ConnectSOCKS
- [ ] ConnectWebSocket
- [ ] Authenticate
- [ ] Register
- [ ] SendPass
- [ ] Logout
- [ ] Oper
- [ ] WebIRC
- [ ] Starttls
- [ ] STSAutoUpgrade
- [ ] STSRemember
- [ ] Resume
- [ ] BouncerBind
- [ ] BounceListNetworks
- [ ] CloseConnections
- [ ] QuitMessage

### Capabilities & Feature Negotiation (4)
- [ ] Capabilities
- [ ] RequestCAP
- [ ] RequestCAPList
- [ ] HasCapability

### SASL Authentication (3)
- [ ] SASLECDSAChallenge
- [ ] SASLExternal
- [ ] SASLScramSHA256

### Nick & Identity (9)
- [ ] ChangeNick
- [ ] GetNick
- [ ] GetProfile
- [ ] SetName
- [ ] Setname
- [ ] SetHost
- [ ] ChgHost
- [ ] ChgIdent
- [ ] ChgName

### User Modes & Status (7)
- [ ] Away
- [ ] PreAway
- [ ] GetAway
- [ ] GetUserMode
- [ ] SetUserMode
- [ ] SetUserModeFlag *(replaces 9 individual user mode methods)*
- [ ] Vhost
- [ ] Swhois

### Channel Operations (13)
- [ ] CreateChannel
- [ ] JoinKey
- [ ] JoinMultiple
- [ ] LeaveChat
- [ ] PartMessage
- [ ] PartMultiple
- [ ] LeaveAllChannels
- [ ] Cycle
- [ ] Knock
- [ ] RenameChannel
- [ ] List
- [ ] Ojoin
- [ ] Njoin

### Channel Modes (9)
- [ ] SetMode
- [ ] Rmode
- [ ] SetChannelModeFlag *(replaces 16 individual boolean channel mode methods)*
- [ ] SetChannelKey
- [ ] SetChannelLimit
- [ ] SetChannelModerated
- [ ] SetChannelNoExternal
- [ ] SetChannelSecret
- [ ] SetChannelTopicLock
- [ ] SetChannelInviteOnly
- [ ] SetChannelRedirect
- [ ] SetChannelHistory
- [ ] SetFloodProtection
- [ ] SetJoinThrottle

### Channel Topic (2)
- [ ] GetChannelTopic
- [ ] CreateTopic

### Channel Member Modes (3)
- [ ] SetVoice
- [ ] SetHalfop
- [ ] SetAdmin

### Channel Bans & Lists (9)
- [ ] BanMask
- [ ] UnbanMask
- [ ] GetBanList
- [ ] GetExceptList
- [ ] GetInviteExceptList
- [ ] RequestInviteList
- [ ] SetBanExcept
- [ ] SetInviteExcept
- [ ] SetExtban *(replaces 18 individual Extban* methods)*

### Content Filtering (4)
- [ ] FilterAdd
- [ ] FilterDel
- [ ] SpamfilterAdd
- [ ] SpamfilterDel

### Messaging (18)
- [ ] SendMessage
- [ ] SendNotice
- [ ] SendAction
- [ ] SendMultiline
- [ ] SendStatusMsg
- [ ] SendStatusNotice
- [ ] CPrivmsg
- [ ] CNotice
- [ ] SendRawCommand
- [ ] ReplyToMessage
- [ ] ForwardMessage
- [ ] EditMessage
- [ ] DeleteMessage
- [ ] Redact
- [ ] ReactToMessage
- [ ] SendReactTag
- [ ] SendTagMsg
- [ ] Relaymsg

### Typing & Read State (4)
- [ ] SendTyping
- [ ] SendTypingIndicator
- [ ] MarkAsRead
- [ ] MarkRead

### Message Pins (3)
- [ ] PinMessage
- [ ] UnpinMessage
- [ ] UnpinAllMessages

### IRCv3 Tags & Batches (5)
- [ ] SendChannelContextTag
- [ ] SendClientBatch
- [ ] BatchStart
- [ ] BatchEnd
- [ ] GetEnabledCaps

### Chat History (IRCv3 CHATHISTORY) (6)
- [ ] ChatHistoryAfter
- [ ] ChatHistoryAround
- [ ] ChatHistoryBefore
- [ ] ChatHistoryBetween
- [ ] ChatHistoryLatest
- [ ] ChatHistoryTargets

### CTCP (8)
- [ ] SendCTCP
- [ ] SendCTCPReply
- [ ] GetCTCPClientInfo
- [ ] CTCPAvatar
- [ ] CTCPErrMsg
- [ ] CTCPFinger
- [ ] CTCPSource
- [ ] CTCPUserinfo

### DCC (13)
- [ ] DCCSend
- [ ] DCCChat
- [ ] DCCAccept
- [ ] DCCResume
- [ ] DCCReverse
- [ ] DCCSecureSend
- [ ] DCCSecureChat
- [ ] Dccallow
- [ ] Dccdeny
- [ ] Undccdeny
- [ ] ClearDCCOffers
- [ ] GetDCCOffers
- [ ] RDCC

### XDCC (7)
- [ ] XDCCSend
- [ ] XDCCList
- [ ] XDCCSearch
- [ ] XDCCInfo
- [ ] XDCCBatch
- [ ] XDCCCancel
- [ ] XDCCRemove

### Files & Media (5)
- [ ] UploadFile
- [ ] DownloadFile
- [ ] FilehostUpload
- [ ] SendImageBase64
- [ ] SendSticker

### Monitor & Watch (12)
- [ ] GetMonitored
- [ ] MonitorAdd
- [ ] MonitorRemove
- [ ] MonitorList
- [ ] MonitorClear
- [ ] MonitorStatus
- [ ] WatchAdd
- [ ] WatchRemove
- [ ] WatchList
- [ ] WatchClear
- [ ] WatchStatus
- [ ] Ison

### User/Channel Queries (10)
- [ ] RequestWhois
- [ ] Who
- [ ] WhoX
- [ ] Whowas
- [ ] RequestNames
- [ ] RequestNoImplicitNames
- [ ] Userhost
- [ ] UserIP
- [ ] GetMembers
- [ ] GetContacts

### Server Queries & Info (18)
- [ ] GetServerInfo
- [ ] RequestAdmin
- [ ] RequestInfo
- [ ] RequestLinks
- [ ] RequestLusers
- [ ] RequestMap
- [ ] RequestMOTD
- [ ] RequestRules
- [ ] RequestStats
- [ ] RequestTime
- [ ] RequestTrace
- [ ] RequestUsers
- [ ] RequestVersion
- [ ] RequestHelp
- [ ] RequestExtendedIsupport
- [ ] RequestExtendedMonitor
- [ ] GetMOTD
- [ ] ShowCredits

### Dialogs & Chat Management (12)
- [ ] GetDialogs
- [ ] GetChatInfo
- [ ] GetMessages
- [ ] SearchMessages
- [ ] SearchGlobal
- [ ] GetReadState
- [ ] GetInviteLink
- [ ] ArchiveChat
- [ ] MuteChat
- [ ] CreateFolder
- [ ] GetFolders
- [ ] GetNetworkIcon

### Contacts & Blocks (6)
- [ ] AddContact
- [ ] DeleteContact
- [ ] BlockUser
- [ ] UnblockUser
- [ ] GetBlockedUsers
- [ ] Silence

### Group & Member Management (8)
- [ ] CreateGroup
- [ ] AddMembers
- [ ] RemoveMember
- [ ] BanMember
- [ ] UnbanMember
- [ ] KickWithReason
- [ ] ForcePart
- [ ] Uninvite

### Invites (2)
- [ ] OnInviteNotify
- [ ] Accept

### Polls (2)
- [ ] CreatePoll
- [ ] VotePoll

### Location (1)
- [ ] SendLocation

### Calls (7)
- [ ] StartCall
- [ ] AcceptCall
- [ ] DeclineCall
- [ ] EndCall
- [ ] JoinGroupCall
- [ ] SetCallMuted
- [ ] GetSessions

### NickServ (28)
- [ ] NickServIdentify
- [ ] NickServRegister
- [ ] NickServInfo
- [ ] NickServList
- [ ] NickServSet
- [ ] NickServSetPassword
- [ ] NickServSaSet
- [ ] NickServAcc
- [ ] NickServAccess
- [ ] NickServAjoin
- [ ] NickServAlist
- [ ] NickServCert
- [ ] NickServConfirm
- [ ] NickServDrop
- [ ] NickServForbid
- [ ] NickServGhost
- [ ] NickServGList
- [ ] NickServGroup
- [ ] NickServLogout
- [ ] NickServRecover
- [ ] NickServRegain
- [ ] NickServRelease
- [ ] NickServSendPass
- [ ] NickServStatus
- [ ] NickServSuspend
- [ ] NickServUngroup
- [ ] NickServUnsuspend
- [ ] NickServUpdate

### ChanServ (37)
- [ ] ChanServRegister
- [ ] ChanServInfo
- [ ] ChanServList
- [ ] ChanServSet
- [ ] ChanServDrop
- [ ] ChanServForbid
- [ ] ChanServSuspend
- [ ] ChanServUnsuspend
- [ ] ChanServAccess
- [ ] ChanServFlags
- [ ] ChanServLevels
- [ ] ChanServAkick
- [ ] ChanServBan
- [ ] ChanServUnban
- [ ] ChanServClear
- [ ] ChanServClone
- [ ] ChanServCount
- [ ] ChanServEnforce
- [ ] ChanServEntryMsg
- [ ] ChanServGetKey
- [ ] ChanServIdentify
- [ ] ChanServInvite
- [ ] ChanServKick
- [ ] ChanServLog
- [ ] ChanServMode
- [ ] ChanServSync
- [ ] ChanServTopic
- [ ] ChanServAppendTopic
- [ ] ChanServStatus
- [ ] ChanServUp
- [ ] ChanServDown
- [ ] ChanServModeCmd *(replaces Op/Deop/Voice/Devoice/Halfop/Dehalfop/Owner/Deowner/Protect/Deprotect)*
- [ ] ChanServHop
- [ ] ChanServAop
- [ ] ChanServSop
- [ ] ChanServVop
- [ ] ChanServQop

### MemoServ (14)
- [ ] MemoServSend
- [ ] MemoServSendGroup
- [ ] MemoServSendOps
- [ ] MemoServRead
- [ ] MemoServList
- [ ] MemoServDelete
- [ ] MemoServCancel
- [ ] MemoServCheck
- [ ] MemoServForward
- [ ] MemoServIgnore
- [ ] MemoServInfo
- [ ] MemoServSet
- [ ] MemoServStaff
- [ ] MemoServRSend

### HostServ (12)
- [ ] HostServActivate
- [ ] HostServDel
- [ ] HostServDelAll
- [ ] HostServGroup
- [ ] HostServList
- [ ] HostServOff
- [ ] HostServOn
- [ ] HostServReject
- [ ] HostServRequest
- [ ] HostServSet
- [ ] HostServSetAll
- [ ] HostServWaiting

### BotServ (12)
- [ ] BotServAct
- [ ] BotServAssign
- [ ] BotServBadwords
- [ ] BotServBotAdd
- [ ] BotServBotChange
- [ ] BotServBotDel
- [ ] BotServBotList
- [ ] BotServInfo
- [ ] BotServKickConfig
- [ ] BotServSay
- [ ] BotServSet
- [ ] BotServUnassign

### GroupServ (4)
- [ ] GroupServFlags
- [ ] GroupServInfo
- [ ] GroupServJoin
- [ ] GroupServLeave

### OperServ (12)
- [ ] OperServAkill
- [ ] OperServDefcon
- [ ] OperServGlobal
- [ ] OperServJupe
- [ ] OperServNoop
- [ ] OperServReload
- [ ] OperServRestart
- [ ] OperServSession
- [ ] OperServShutdown
- [ ] OperServSnline
- [ ] OperServSqline
- [ ] OperServStats

### StatServ (2)
- [ ] StatServAkill
- [ ] StatServInfo

### Metadata (IRCv3) (5)
- [ ] MetadataGet
- [ ] MetadataList
- [ ] MetadataSet
- [ ] MetadataSub
- [ ] MetadataUnsub

### Web Push (IRCv3) (2)
- [ ] WebPushRegister
- [ ] WebPushUnregister

### ExtBan Parsing (1)
- [ ] ParseAccountExtban

### Server Administration & Oper Commands (40)
- [ ] Die
- [ ] Restart
- [ ] Rehash
- [ ] Kill
- [ ] Wallops
- [ ] Globops
- [ ] Jumpserver
- [ ] Rconnect
- [ ] Rsquit
- [ ] SaJoin
- [ ] SaPart
- [ ] SaMode
- [ ] SaNick
- [ ] Sakick
- [ ] Saquit
- [ ] Satopic
- [ ] Close
- [ ] Lockserv
- [ ] Unlockserv
- [ ] Clearchan
- [ ] Clones
- [ ] Check
- [ ] Ircops
- [ ] Nicklock
- [ ] Nickunlock
- [ ] Setidle
- [ ] Sdesc
- [ ] Mkpasswd
- [ ] ModuleManage
- [ ] Tline
- [ ] Tsctl
- [ ] Alltime
- [ ] DnsInfo
- [ ] ShowLicense
- [ ] ShowStaff
- [ ] Summon
- [ ] Service
- [ ] ServList
- [ ] SQuery
- [ ] Rmtkl

### Server Bans & Exemptions (17)
- [ ] KLine
- [ ] GLine
- [ ] ZLine
- [ ] GZLine
- [ ] Qline
- [ ] QlineDel
- [ ] Eline
- [ ] Rline
- [ ] RlineDel
- [ ] Shun
- [ ] Tempshun
- [ ] Cban
- [ ] CbanDel
- [ ] Addmotd
- [ ] Addomotd
- [ ] Botmotd
- [ ] Opermotd

### Chat Description & Title (2)
- [ ] EditChatTitle
- [ ] EditChatDescription

### Session & Callback (4)
- [ ] Name
- [ ] OnUpdate
- [ ] Verify
- [ ] TerminateSession

---

**Total: 418 exported methods across all categories.**
