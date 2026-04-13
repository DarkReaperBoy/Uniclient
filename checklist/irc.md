## Phase 11: IRC — DONE (core), NOT ADDED list below

340 exported methods, ~5,700 lines. All 95 additional methods implemented (not yet tested). Pure Go IRC client (RFC 1459/2812 + IRCv3 + CTCP + DCC + services). No external deps.

### Core Interface (55/55)

- [x] Name
- [x] Capabilities
- [x] Authenticate (SASL PLAIN / NickServ / no-auth)
- [x] Logout
- [x] GetDialogs
- [x] CreateGroup (JOIN)
- [x] CreateChannel (JOIN + TOPIC)
- [x] CreateTopic — returns ErrNotSupported
- [x] GetFolders — returns ErrNotSupported
- [x] CreateFolder — returns ErrNotSupported
- [x] SendMessage (PRIVMSG)
- [x] GetMessages (local buffer)
- [x] EditMessage — returns ErrNotSupported
- [x] DeleteMessage — returns ErrNotSupported
- [x] ReplyToMessage (quote prefix)
- [x] ForwardMessage (fwd prefix)
- [x] ReactToMessage — returns ErrNotSupported
- [x] PinMessage (local persistence)
- [x] UnpinMessage (local persistence)
- [x] MarkAsRead (local)
- [x] GetReadState (local)
- [x] UploadFile — returns ErrNotSupported
- [x] DownloadFile — returns ErrNotSupported
- [x] SendImageBase64 — returns ErrNotSupported
- [x] StartCall — returns ErrNotSupported
- [x] JoinGroupCall — returns ErrNotSupported
- [x] EndCall — returns ErrNotSupported
- [x] SetCallMuted — returns ErrNotSupported
- [x] GetProfile (WHOIS, cached)
- [x] OnUpdate
- [x] Close (QUIT)
- [x] GetChatInfo
- [x] EditChatTitle — returns ErrNotSupported
- [x] EditChatDescription (TOPIC)
- [x] LeaveChat (PART)
- [x] GetInviteLink — returns ErrNotSupported
- [x] AddMembers (INVITE)
- [x] RemoveMember (KICK)
- [x] BanMember (MODE +b)
- [x] UnbanMember (MODE -b)
- [x] GetMembers (NAMES)
- [x] SetAdmin (MODE +o/-o)
- [x] GetContacts — returns ErrNotSupported
- [x] AddContact — returns ErrNotSupported
- [x] DeleteContact — returns ErrNotSupported
- [x] BlockUser (local persistence)
- [x] UnblockUser (local persistence)
- [x] GetBlockedUsers (local persistence)
- [x] SearchMessages (local buffer)
- [x] SearchGlobal (local channels/DMs)
- [x] SendTyping — no-op
- [x] CreatePoll — returns ErrNotSupported
- [x] VotePoll — returns ErrNotSupported
- [x] SendSticker — returns ErrNotSupported
- [x] GetSessions — returns ErrNotSupported
- [x] TerminateSession — returns ErrNotSupported

### Nick/Identity (8)

- [x] GetNick
- [x] ChangeNick
- [x] SetName
- [x] Away
- [x] GetAway
- [x] Oper
- [x] QuitMessage
- [x] SendRawCommand

### Channel Join/Part (7)

- [x] JoinKey
- [x] JoinMultiple
- [x] PartMessage
- [x] PartMultiple
- [x] LeaveAllChannels
- [x] Knock
- [x] SendPass

### Channel Info (2)

- [x] GetChannelTopic
- [x] RequestNames

### Channel Modes (10)

- [x] SetMode
- [x] SetChannelKey
- [x] SetChannelLimit
- [x] SetChannelModerated
- [x] SetChannelInviteOnly
- [x] SetChannelNoExternal
- [x] SetChannelSecret
- [x] SetChannelTopicLock
- [x] SetUserMode
- [x] GetUserMode

### Ban/Exception Lists (5)

- [x] GetBanList
- [x] BanMask
- [x] UnbanMask
- [x] GetExceptList
- [x] GetInviteExceptList

### Ban/Invite Exceptions (3)

- [x] SetBanExcept
- [x] SetInviteExcept
- [x] RequestInviteList (implicit in GetInviteExceptList)

### User Ops (3)

- [x] SetVoice
- [x] SetHalfop
- [x] KickWithReason

### Messaging (7)

- [x] SendNotice
- [x] SendAction
- [x] Wallops
- [x] SendStatusMsg
- [x] SendStatusNotice
- [x] CPrivmsg
- [x] CNotice

### CTCP (3)

- [x] SendCTCP
- [x] SendCTCPReply
- [x] GetCTCPClientInfo (implicit)

### DCC (6)

- [x] DCCSend
- [x] DCCChat
- [x] DCCResume
- [x] DCCAccept
- [x] GetDCCOffers
- [x] ClearDCCOffers

### IRCv3 TAGMSG (2)

- [x] SendTagMsg
- [x] SendTypingIndicator

### IRCv3 CHATHISTORY (5)

- [x] ChatHistoryLatest
- [x] ChatHistoryBefore
- [x] ChatHistoryAfter
- [x] ChatHistoryAround
- [x] ChatHistoryTargets

### IRCv3 MARKREAD/REDACT (2)

- [x] MarkRead
- [x] Redact

### IRCv3 REGISTER/VERIFY (2)

- [x] Register
- [x] Verify

### IRCv3 RENAME (implicit in channel ops)

### Queries (5)

- [x] Who
- [x] WhoX
- [x] RequestWhois
- [x] Whowas
- [x] Userhost
- [x] Ison

### Server Queries (12)

- [x] List
- [x] RequestMOTD
- [x] GetMOTD
- [x] RequestVersion
- [x] RequestTime
- [x] RequestAdmin
- [x] RequestInfo
- [x] RequestLusers
- [x] RequestStats
- [x] GetServerInfo
- [x] HasCapability
- [x] RequestUsers
- [x] Summon

### Server Topology (5)

- [x] RequestLinks
- [x] RequestTrace
- [x] RequestMap
- [x] RequestHelp
- [x] RequestRules

### Service Queries (2)

- [x] ServList
- [x] SQuery

### CAP (2)

- [x] GetEnabledCaps (via HasCapability/GetServerInfo)
- [x] RequestCAPList (implicit)

### MONITOR (6)

- [x] MonitorAdd
- [x] MonitorRemove
- [x] MonitorClear
- [x] MonitorList
- [x] MonitorStatus
- [x] GetMonitored

### WATCH (5)

- [x] WatchAdd
- [x] WatchRemove
- [x] WatchClear
- [x] WatchList
- [x] WatchStatus

### SILENCE/WEBIRC/KILL (3)

- [x] Silence
- [x] UserIP
- [x] Kill (implicit via Oper)

### NickServ (20)

- [x] NickServIdentify
- [x] NickServRegister
- [x] NickServGhost
- [x] NickServRelease
- [x] NickServInfo
- [x] NickServLogout
- [x] NickServSetPassword
- [x] NickServGroup
- [x] NickServUngroup
- [x] NickServAccess
- [x] NickServAjoin
- [x] NickServCert
- [x] NickServAlist
- [x] NickServAcc
- [x] NickServStatus
- [x] NickServDrop
- [x] NickServSet
- [x] NickServSendPass
- [x] NickServRecover
- [x] NickServUpdate

### ChanServ (39)

- [x] ChanServOp
- [x] ChanServDeop
- [x] ChanServVoice
- [x] ChanServDevoice
- [x] ChanServHalfop
- [x] ChanServDehalfop
- [x] ChanServRegister
- [x] ChanServDrop
- [x] ChanServInvite
- [x] ChanServAkick
- [x] ChanServInfo
- [x] ChanServFlags (implicit in ChanServAccess)
- [x] ChanServAccess
- [x] ChanServAop
- [x] ChanServSop
- [x] ChanServHop
- [x] ChanServVop
- [x] ChanServQop
- [x] ChanServBan
- [x] ChanServUnban
- [x] ChanServKick
- [x] ChanServTopic
- [x] ChanServUp
- [x] ChanServDown
- [x] ChanServSet
- [x] ChanServClear
- [x] ChanServEnforce
- [x] ChanServEntryMsg
- [x] ChanServSync
- [x] ChanServGetKey
- [x] ChanServStatus
- [x] ChanServList
- [x] ChanServClone
- [x] ChanServOwner
- [x] ChanServDeowner
- [x] ChanServProtect
- [x] ChanServDeprotect
- [x] ChanServIdentify
- [x] ChanServMode

### MemoServ (10)

- [x] MemoServSend
- [x] MemoServRead
- [x] MemoServList
- [x] MemoServDelete
- [x] MemoServRSend
- [x] MemoServCancel
- [x] MemoServCheck
- [x] MemoServInfo
- [x] MemoServIgnore
- [x] MemoServSet

### HostServ (4)

- [x] HostServOn
- [x] HostServOff
- [x] HostServRequest
- [x] HostServGroup

### BotServ (6)

- [x] BotServBotList
- [x] BotServAssign
- [x] BotServUnassign
- [x] BotServInfo
- [x] BotServSay
- [x] BotServAct

### Verified on 6 Networks

Libera.Chat, Rizon, OFTC, EFNet, UnderNet, QuakeNet — all pass.

---

### Extended Methods (95 — all implemented, not yet tested)

#### RFC Commands (6)

- [x] CONNECT — request server link (oper only)
- [x] DIE — shutdown server (oper only)
- [x] REHASH — reload server config (oper only)
- [x] RESTART — restart server (oper only)
- [x] SERVICE — register a service
- [x] NJOIN — server-to-server channel burst (server-only)

#### IRCv3 Extensions (5)

- [x] SETNAME — change realname without reconnect
- [x] ChatHistoryBetween — CHATHISTORY BETWEEN two timestamps/msgids
- [x] BATCH — start/end batch processing
- [x] RENAME — handle channel rename events
- [x] STARTTLS — upgrade plain connection to TLS

#### DCC Extended (9)

- [x] DCCSecureSend — DCC SSEND (TLS file transfer)
- [x] DCCSecureChat — DCC SCHAT (TLS chat)
- [x] XDCCSend — XDCC SEND (request file from bot)
- [x] XDCCList — XDCC LIST (list available packs)
- [x] XDCCBatch — XDCC BATCH (request multiple packs)
- [x] XDCCCancel — XDCC CANCEL (cancel transfer)
- [x] XDCCRemove — XDCC REMOVE (remove pack — bot owner)
- [x] XDCCInfo — XDCC INFO (pack details)
- [x] XDCCSearch — XDCC SEARCH (search packs)

#### CTCP Extended (3)

- [x] CTCPFinger — CTCP FINGER query/reply
- [x] CTCPSource — CTCP SOURCE query/reply
- [x] CTCPUserinfo — CTCP USERINFO query/reply

#### NickServ Extended (8)

- [x] NickServRegain — recover + change nick in one step
- [x] NickServGList — list nicks in group
- [x] NickServConfirm — email verification
- [x] NickServSuspend — suspend nick (oper only)
- [x] NickServUnsuspend — unsuspend nick (oper only)
- [x] NickServForbid — forbid nick registration (oper only)
- [x] NickServList — search registered nicks (oper only)
- [x] NickServSaSet — admin-set nick options (oper only)

#### ChanServ Extended (7)

- [x] ChanServAppendTopic — append to channel topic
- [x] ChanServLevels — manage access level definitions
- [x] ChanServLog — view channel action log
- [x] ChanServCount — count access list entries
- [x] ChanServSuspend — suspend channel (oper only)
- [x] ChanServUnsuspend — unsuspend channel (oper only)
- [x] ChanServForbid — forbid channel registration (oper only)

#### MemoServ Extended (4)

- [x] MemoServSendGroup — send memo to nick group
- [x] MemoServSendOps — send memo to channel ops
- [x] MemoServForward — forward memo to another user
- [x] MemoServStaff — send memo to all staff (oper only)

#### HostServ Extended (8)

- [x] HostServList — list own vhosts
- [x] HostServSet — assign vhost to nick (oper only)
- [x] HostServSetAll — assign vhost to nick group (oper only)
- [x] HostServDel — remove vhost from nick (oper only)
- [x] HostServDelAll — remove vhost from nick group (oper only)
- [x] HostServActivate — approve vhost request (oper only)
- [x] HostServReject — reject vhost request (oper only)
- [x] HostServWaiting — list pending vhost requests (oper only)

#### BotServ Extended (5)

- [x] BotServBotAdd — create a bot (oper only)
- [x] BotServBotDel — delete a bot (oper only)
- [x] BotServBotChange — modify bot nick/ident/host (oper only)
- [x] BotServBadwords — manage bad word filter list
- [x] BotServKickConfig — configure auto-kick triggers
- [x] BotServSet — configure bot channel settings

#### OperServ (12) — all oper only

- [x] OperServAkill — network-wide K-line (ban)
- [x] OperServSqline — nick/channel quarantine
- [x] OperServSnline — realname ban
- [x] OperServSession — view/manage session limits
- [x] OperServNoop — disable O-lines on a server
- [x] OperServJupe — fake/quarantine a server
- [x] OperServGlobal — send global notice to all users
- [x] OperServDefcon — set network defense level
- [x] OperServStats — services statistics
- [x] OperServReload — reload services config
- [x] OperServShutdown — shutdown services
- [x] OperServRestart — restart services

#### Server Extensions (10)

- [x] SETHOST — set own virtual host (oper only)
- [x] CHGHOST — change another user's host (oper only)
- [x] CHGIDENT — change another user's ident (oper only)
- [x] CHGNAME — change another user's realname (oper only)
- [x] SAJOIN — force a user to join a channel (oper only)
- [x] SAPART — force a user to part a channel (oper only)
- [x] SANICK — force a user to change nick (oper only)
- [x] SAMODE — force a mode change on channel/user (oper only)
- [x] GLOBOPS / CHATOPS / LOCOPS — oper-only broadcast messages
- [x] VHOST — set own virtual host (user command, UnrealIRCd)

#### IRCv3 Draft Extensions (3)

- [x] BounceListNetworks / BouncerBind — IRCv3 draft/bouncer for multi-network bouncers
- [x] Resume — IRCv3 draft/resume, reconnect without losing state
- [x] WebPushRegister / WebPushUnregister — IRCv3 draft/webpush notifications

#### IRCd-Specific Oper Commands (4)

- [x] GLine / GZLine / ZLine — network-wide IP bans (UnrealIRCd/InspIRCd)
- [x] Shun — silence a user network-wide (UnrealIRCd)
- [x] KLine — server-local ban (distinct from AKILL)
- [x] Check — inspect user/channel details (InspIRCd oper)

#### Services: GroupServ (3 — Atheme)

- [x] GroupServInfo — info about a group
- [x] GroupServJoin / GroupServLeave — join/leave a group
- [x] GroupServFlags — manage group flags

#### Services: StatServ (2)

- [x] StatServInfo — network statistics
- [x] StatServAkill — akill statistics
