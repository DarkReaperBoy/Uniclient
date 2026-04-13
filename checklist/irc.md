## Phase 11: IRC — DONE (core), NOT ADDED list below

245 exported methods, ~4,473 lines. ~104 more identified but not added. Pure Go IRC client (RFC 1459/2812 + IRCv3 + CTCP + DCC + services). No external deps.

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

### Not Added in Core

Methods found in the IRC protocol ecosystem (RFC 1459/2812, IRCv3, services, extensions) but not yet implemented. ~90 methods total.

#### RFC Commands (6)

- [ ] CONNECT — request server link (oper only)
- [ ] DIE — shutdown server (oper only)
- [ ] REHASH — reload server config (oper only)
- [ ] RESTART — restart server (oper only)
- [ ] SERVICE — register a service
- [ ] NJOIN — server-to-server channel burst (server-only)

#### IRCv3 Extensions (5)

- [ ] SETNAME — change realname without reconnect
- [ ] ChatHistoryBetween — CHATHISTORY BETWEEN two timestamps/msgids
- [ ] BATCH — start/end batch processing
- [ ] RENAME — handle channel rename events
- [ ] STARTTLS — upgrade plain connection to TLS

#### DCC Extended (9)

- [ ] DCCSecureSend — DCC SSEND (TLS file transfer)
- [ ] DCCSecureChat — DCC SCHAT (TLS chat)
- [ ] XDCCSend — XDCC SEND (request file from bot)
- [ ] XDCCList — XDCC LIST (list available packs)
- [ ] XDCCBatch — XDCC BATCH (request multiple packs)
- [ ] XDCCCancel — XDCC CANCEL (cancel transfer)
- [ ] XDCCRemove — XDCC REMOVE (remove pack — bot owner)
- [ ] XDCCInfo — XDCC INFO (pack details)
- [ ] XDCCSearch — XDCC SEARCH (search packs)

#### CTCP Extended (3)

- [ ] CTCPFinger — CTCP FINGER query/reply
- [ ] CTCPSource — CTCP SOURCE query/reply
- [ ] CTCPUserinfo — CTCP USERINFO query/reply

#### NickServ Extended (8)

- [ ] NickServRegain — recover + change nick in one step
- [ ] NickServGList — list nicks in group
- [ ] NickServConfirm — email verification
- [ ] NickServSuspend — suspend nick (oper only)
- [ ] NickServUnsuspend — unsuspend nick (oper only)
- [ ] NickServForbid — forbid nick registration (oper only)
- [ ] NickServList — search registered nicks (oper only)
- [ ] NickServSaSet — admin-set nick options (oper only)

#### ChanServ Extended (7)

- [ ] ChanServAppendTopic — append to channel topic
- [ ] ChanServLevels — manage access level definitions
- [ ] ChanServLog — view channel action log
- [ ] ChanServCount — count access list entries
- [ ] ChanServSuspend — suspend channel (oper only)
- [ ] ChanServUnsuspend — unsuspend channel (oper only)
- [ ] ChanServForbid — forbid channel registration (oper only)

#### MemoServ Extended (4)

- [ ] MemoServSendGroup — send memo to nick group
- [ ] MemoServSendOps — send memo to channel ops
- [ ] MemoServForward — forward memo to another user
- [ ] MemoServStaff — send memo to all staff (oper only)

#### HostServ Extended (8)

- [ ] HostServList — list own vhosts
- [ ] HostServSet — assign vhost to nick (oper only)
- [ ] HostServSetAll — assign vhost to nick group (oper only)
- [ ] HostServDel — remove vhost from nick (oper only)
- [ ] HostServDelAll — remove vhost from nick group (oper only)
- [ ] HostServActivate — approve vhost request (oper only)
- [ ] HostServReject — reject vhost request (oper only)
- [ ] HostServWaiting — list pending vhost requests (oper only)

#### BotServ Extended (5)

- [ ] BotServBotAdd — create a bot (oper only)
- [ ] BotServBotDel — delete a bot (oper only)
- [ ] BotServBotChange — modify bot nick/ident/host (oper only)
- [ ] BotServBadwords — manage bad word filter list
- [ ] BotServKickConfig — configure auto-kick triggers
- [ ] BotServSet — configure bot channel settings

#### OperServ (12) — all oper only

- [ ] OperServAkill — network-wide K-line (ban)
- [ ] OperServSqline — nick/channel quarantine
- [ ] OperServSnline — realname ban
- [ ] OperServSession — view/manage session limits
- [ ] OperServNoop — disable O-lines on a server
- [ ] OperServJupe — fake/quarantine a server
- [ ] OperServGlobal — send global notice to all users
- [ ] OperServDefcon — set network defense level
- [ ] OperServStats — services statistics
- [ ] OperServReload — reload services config
- [ ] OperServShutdown — shutdown services
- [ ] OperServRestart — restart services

#### Server Extensions (10)

- [ ] SETHOST — set own virtual host (oper only)
- [ ] CHGHOST — change another user's host (oper only)
- [ ] CHGIDENT — change another user's ident (oper only)
- [ ] CHGNAME — change another user's realname (oper only)
- [ ] SAJOIN — force a user to join a channel (oper only)
- [ ] SAPART — force a user to part a channel (oper only)
- [ ] SANICK — force a user to change nick (oper only)
- [ ] SAMODE — force a mode change on channel/user (oper only)
- [ ] GLOBOPS / CHATOPS / LOCOPS — oper-only broadcast messages
- [ ] VHOST — set own virtual host (user command, UnrealIRCd)

#### IRCv3 Draft Extensions (not added)

- [ ] BounceListNetworks / BouncerBind — IRCv3 draft/bouncer for multi-network bouncers
- [ ] Resume — IRCv3 draft/resume, reconnect without losing state
- [ ] WebPushRegister / WebPushUnregister — IRCv3 draft/webpush notifications

#### IRCd-Specific Oper Commands (not added)

- [ ] GLine / GZLine / ZLine — network-wide IP bans (UnrealIRCd/InspIRCd)
- [ ] Shun — silence a user network-wide (UnrealIRCd)
- [ ] KLine — server-local ban (distinct from AKILL)
- [ ] Check — inspect user/channel details (InspIRCd oper)

#### Services: GroupServ (not added — Atheme)

- [ ] GroupServInfo — info about a group
- [ ] GroupServJoin / GroupServLeave — join/leave a group
- [ ] GroupServFlags — manage group flags

#### Services: StatServ (not added)

- [ ] StatServInfo — network statistics
- [ ] StatServAkill — akill statistics
