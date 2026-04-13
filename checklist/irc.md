# IRC — Fresh Checklist

**Methods:** 469 exported | **Lines:** 5,797 | **File:** `go/cores/irc.go`
**Protocol:** IRC (RFC 1459/2812, IRCv3, DCC, CTCP, Services)
**Last updated:** 2026-04-13

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

### User Modes & Status (14)
- [ ] Away
- [ ] PreAway
- [ ] GetAway
- [ ] GetUserMode
- [ ] SetUserMode
- [ ] SetCallerID
- [ ] SetDeafMode
- [ ] SetHideChannels
- [ ] SetHideOper
- [ ] SetBotMode
- [ ] SetBotModeIRCv3
- [ ] SetWhoisNotify
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

### Channel Modes (28)
- [ ] SetMode
- [ ] Rmode
- [ ] SetChannelKey
- [ ] SetChannelLimit
- [ ] SetChannelModerated
- [ ] SetChannelNoExternal
- [ ] SetChannelSecret
- [ ] SetChannelTopicLock
- [ ] SetChannelInviteOnly
- [ ] SetChannelRedirect
- [ ] SetChannelHistory
- [ ] SetAuditorium
- [ ] SetDelayedJoins
- [ ] SetFloodProtection
- [ ] SetJoinThrottle
- [ ] SetNoColors
- [ ] SetNoCTCP
- [ ] SetNoInvite
- [ ] SetNoKicks
- [ ] SetNoKnock
- [ ] SetNoNickChange
- [ ] SetNoNotices
- [ ] SetOperOnly
- [ ] SetPermanent
- [ ] SetRequireRegistered
- [ ] SetRequireRegisteredSpeak
- [ ] SetRequireSSL
- [ ] SetSSLOnly

### Channel Topic (2)
- [ ] GetChannelTopic
- [ ] CreateTopic

### Channel Member Modes (7)
- [ ] SetVoice
- [ ] SetHalfop
- [ ] SetAdmin
- [ ] SetBanExcept
- [ ] SetInviteExcept
- [ ] SetBlockCTCP
- [ ] SetBlockUnregistered

### Channel Bans & Lists (7)
- [ ] BanMask
- [ ] UnbanMask
- [ ] GetBanList
- [ ] GetExceptList
- [ ] GetInviteExceptList
- [ ] RequestInviteList
- [ ] SetCensor

### Extended Bans (18)
- [ ] ExtbanAccount
- [ ] ExtbanASN
- [ ] ExtbanCertFP
- [ ] ExtbanChannel
- [ ] ExtbanCountry
- [ ] ExtbanFlood
- [ ] ExtbanForward
- [ ] ExtbanInherit
- [ ] ExtbanJoin
- [ ] ExtbanMsgbypass
- [ ] ExtbanNickchange
- [ ] ExtbanOperclass
- [ ] ExtbanPartmsg
- [ ] ExtbanQuiet
- [ ] ExtbanRealname
- [ ] ExtbanSecurityGroup
- [ ] ExtbanText
- [ ] ExtbanTimed

### Content Filtering (6)
- [ ] SetStripColors
- [ ] SetWordFilter
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

### Typing & Read State (5)
- [ ] SendTyping
- [ ] SendTypingIndicator
- [ ] MarkAsRead
- [ ] MarkRead
- [ ] MarkUnread

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

### ChanServ (46)
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
- [ ] ChanServOp
- [ ] ChanServDeop
- [ ] ChanServHalfop
- [ ] ChanServDehalfop
- [ ] ChanServVoice
- [ ] ChanServDevoice
- [ ] ChanServOwner
- [ ] ChanServDeowner
- [ ] ChanServProtect
- [ ] ChanServDeprotect
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

**Total: 478 methods across all categories.**
