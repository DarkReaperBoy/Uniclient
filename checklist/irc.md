# IRC Checklist — 418 methods


## Core Interface
- [x] Capabilities
- [x] Close
- [x] Name
- [x] OnUpdate

## Authentication
- [x] Authenticate
- [x] Logout
- [x] Register

## Connection
- [x] WebIRC

## Dialogs & Chats
- [x] ArchiveChat
- [x] EditChatDescription
- [x] EditChatTitle
- [x] GetChatInfo
- [x] GetDialogs
- [x] LeaveChat
- [x] MuteChat

## Messaging
- [x] DeleteMessage
- [x] EditMessage
- [x] ForwardMessage
- [x] GetMessages
- [x] GetReadState
- [x] MarkAsRead
- [x] MarkUnread
- [x] PinMessage
- [x] ReactToMessage
- [x] ReplyToMessage
- [x] SendClientBatch
- [x] SendImageBase64
- [x] SendLocation
- [x] SendMessage
- [x] SendMultiline
- [x] SendSticker
- [x] UnpinAllMessages
- [x] UnpinMessage

## Messaging Extensions
- [x] SendAction
- [x] SendNotice
- [x] SendPass
- [x] SendRawCommand
- [x] SendReactTag
- [x] SendStatusMsg
- [x] SendStatusNotice
- [x] SendTagMsg
- [x] SendTyping
- [x] SendTypingIndicator

## Media & Files
- [x] DownloadFile
- [x] UploadFile

## Calls
- [x] AcceptCall
- [x] DeclineCall
- [x] EndCall
- [x] SetCallMuted
- [x] StartCall

## Group Calls
- [x] JoinGroupCall

## Groups & Channels
- [x] CreateGroup
- [x] CreateTopic

## Channel Operations
- [x] BanMask
- [x] BanMember
- [x] CreateChannel
- [x] GetBanList
- [x] GetChannelTopic
- [x] GetExceptList
- [x] GetInviteExceptList
- [x] KickWithReason
- [x] LeaveAllChannels
- [x] RenameChannel
- [x] SendChannelContextTag
- [x] SetBanExcept
- [x] SetChannelHistory
- [x] SetChannelInviteOnly
- [x] SetChannelKey
- [x] SetChannelLimit
- [x] SetChannelModeFlag
- [x] SetChannelModerated
- [x] SetChannelNoExternal
- [x] SetChannelRedirect
- [x] SetChannelSecret
- [x] SetChannelTopicLock
- [x] SetHalfop
- [x] SetInviteExcept
- [x] SetMode
- [x] SetUserMode
- [x] SetUserModeFlag
- [x] SetVoice
- [x] UnbanMask
- [x] UnbanMember

## Members & Admin
- [x] AddMembers
- [x] GetInviteLink
- [x] GetMembers
- [x] RemoveMember
- [x] SetAdmin

## Contacts & Users
- [x] AddContact
- [x] BlockUser
- [x] DeleteContact
- [x] GetBlockedUsers
- [x] GetContacts
- [x] GetProfile
- [x] SearchGlobal
- [x] UnblockUser

## User Queries
- [x] Ison
- [x] Userhost
- [x] UserIP
- [x] Who
- [x] Whowas
- [x] WhoX

## Folders
- [x] CreateFolder
- [x] GetFolders

## Sessions
- [x] GetSessions
- [x] TerminateSession

## Polls
- [x] CreatePoll
- [x] VotePoll

## Search
- [x] SearchMessages

## Chat History
- [x] ChatHistoryAfter
- [x] ChatHistoryAround
- [x] ChatHistoryBefore
- [x] ChatHistoryBetween
- [x] ChatHistoryLatest
- [x] ChatHistoryTargets

## NickServ
- [x] NickServAcc
- [x] NickServAccess
- [x] NickServAjoin
- [x] NickServAlist
- [x] NickServCert
- [x] NickServConfirm
- [x] NickServDrop
- [x] NickServForbid
- [x] NickServGhost
- [x] NickServGList
- [x] NickServGroup
- [x] NickServIdentify
- [x] NickServInfo
- [x] NickServList
- [x] NickServLogout
- [x] NickServRecover
- [x] NickServRegain
- [x] NickServRegister
- [x] NickServRelease
- [x] NickServSaSet
- [x] NickServSendPass
- [x] NickServSet
- [x] NickServSetPassword
- [x] NickServStatus
- [x] NickServSuspend
- [x] NickServUngroup
- [x] NickServUnsuspend
- [x] NickServUpdate

## ChanServ
- [x] ChanServAccess
- [x] ChanServAkick
- [x] ChanServAop
- [x] ChanServAppendTopic
- [x] ChanServBan
- [x] ChanServClear
- [x] ChanServClone
- [x] ChanServCount
- [x] ChanServDown
- [x] ChanServDrop
- [x] ChanServEnforce
- [x] ChanServEntryMsg
- [x] ChanServFlags
- [x] ChanServForbid
- [x] ChanServGetKey
- [x] ChanServHop
- [x] ChanServIdentify
- [x] ChanServInfo
- [x] ChanServInvite
- [x] ChanServKick
- [x] ChanServLevels
- [x] ChanServList
- [x] ChanServLog
- [x] ChanServMode
- [x] ChanServModeCmd
- [x] ChanServQop
- [x] ChanServRegister
- [x] ChanServSet
- [x] ChanServSop
- [x] ChanServStatus
- [x] ChanServSuspend
- [x] ChanServSync
- [x] ChanServTopic
- [x] ChanServUnban
- [x] ChanServUnsuspend
- [x] ChanServUp
- [x] ChanServVop

## MemoServ
- [x] MemoServCancel
- [x] MemoServCheck
- [x] MemoServDelete
- [x] MemoServForward
- [x] MemoServIgnore
- [x] MemoServInfo
- [x] MemoServList
- [x] MemoServRead
- [x] MemoServRSend
- [x] MemoServSend
- [x] MemoServSendGroup
- [x] MemoServSendOps
- [x] MemoServSet
- [x] MemoServStaff

## HostServ
- [x] HostServActivate
- [x] HostServDel
- [x] HostServDelAll
- [x] HostServGroup
- [x] HostServList
- [x] HostServOff
- [x] HostServOn
- [x] HostServReject
- [x] HostServRequest
- [x] HostServSet
- [x] HostServSetAll
- [x] HostServWaiting

## BotServ
- [x] BotServAct
- [x] BotServAssign
- [x] BotServBadwords
- [x] BotServBotAdd
- [x] BotServBotChange
- [x] BotServBotDel
- [x] BotServBotList
- [x] BotServInfo
- [x] BotServKickConfig
- [x] BotServSay
- [x] BotServSet
- [x] BotServUnassign

## OperServ
- [x] OperServAkill
- [x] OperServDefcon
- [x] OperServGlobal
- [x] OperServJupe
- [x] OperServNoop
- [x] OperServReload
- [x] OperServRestart
- [x] OperServSession
- [x] OperServShutdown
- [x] OperServSnline
- [x] OperServSqline
- [x] OperServStats

## DCC/XDCC
- [x] DCCAccept
- [x] DCCChat
- [x] DCCResume
- [x] DCCReverse
- [x] DCCSecureChat
- [x] DCCSecureSend
- [x] DCCSend
- [x] XDCCBatch
- [x] XDCCCancel
- [x] XDCCInfo
- [x] XDCCList
- [x] XDCCRemove
- [x] XDCCSearch
- [x] XDCCSend

## CTCP
- [x] CTCPAvatar
- [x] CTCPErrMsg
- [x] CTCPFinger
- [x] CTCPSource
- [x] CTCPUserinfo
- [x] SendCTCP
- [x] SendCTCPReply

## Monitoring
- [x] MonitorAdd
- [x] MonitorClear
- [x] MonitorList
- [x] MonitorRemove
- [x] MonitorStatus
- [x] WatchAdd
- [x] WatchClear
- [x] WatchList
- [x] WatchRemove
- [x] WatchStatus

## Capabilities (CAP)
- [x] GetEnabledCaps
- [x] RequestCAP
- [x] RequestCAPList

## Server Queries
- [x] GetAway
- [x] GetMOTD
- [x] GetNick
- [x] GetServerInfo
- [x] RequestAdmin
- [x] RequestHelp
- [x] RequestInfo
- [x] RequestLinks
- [x] RequestLusers
- [x] RequestMap
- [x] RequestMOTD
- [x] RequestRules
- [x] RequestStats
- [x] RequestTime
- [x] RequestTrace
- [x] RequestUsers
- [x] RequestVersion

## Batch
- [x] BatchEnd
- [x] BatchStart

## Queries & Info
- [x] GetCTCPClientInfo
- [x] GetDCCOffers
- [x] GetMonitored
- [x] GetNetworkIcon
- [x] GetUserMode

## Settings & Configuration
- [x] SetExtban
- [x] SetFloodProtection
- [x] SetHost
- [x] Setidle
- [x] SetJoinThrottle
- [x] SetName

## Listing
- [x] List

## Requests
- [x] RequestExtendedIsupport
- [x] RequestExtendedMonitor
- [x] RequestInviteList
- [x] RequestNames
- [x] RequestNoImplicitNames
- [x] RequestWhois

## Join & Leave
- [x] JoinKey
- [x] JoinMultiple

## Read State
- [x] MarkRead

## Other
- [x] Accept
- [x] Addmotd
- [x] Addomotd
- [x] Alltime
- [x] Away
- [x] BounceListNetworks
- [x] BouncerBind
- [x] Cban
- [x] CbanDel
- [x] ChangeNick
- [x] Check
- [x] ChgHost
- [x] ChgIdent
- [x] ChgName
- [x] Clearchan
- [x] ClearDCCOffers
- [x] Clones
- [x] CloseConnections
- [x] CNotice
- [x] Connect
- [x] ConnectHTTPProxy
- [x] ConnectSOCKS
- [x] ConnectWebSocket
- [x] CPrivmsg
- [x] Cycle
- [x] Dccallow
- [x] Dccdeny
- [x] Die
- [x] DnsInfo
- [x] Eline
- [x] FilehostUpload
- [x] FilterAdd
- [x] FilterDel
- [x] ForcePart
- [x] GLine
- [x] Globops
- [x] GroupServFlags
- [x] GroupServInfo
- [x] GroupServJoin
- [x] GroupServLeave
- [x] GZLine
- [x] HasCapability
- [x] Ircops
- [x] Jumpserver
- [x] Kill
- [x] KLine
- [x] Knock
- [x] MetadataGet
- [x] MetadataList
- [x] MetadataSet
- [x] MetadataSub
- [x] MetadataUnsub
- [x] Mkpasswd
- [x] ModuleManage
- [x] Nicklock
- [x] Nickunlock
- [x] Ojoin
- [x] OnInviteNotify
- [x] Oper
- [x] Opermotd
- [x] ParseAccountExtban
- [x] PartMessage
- [x] PartMultiple
- [x] Qline
- [x] QlineDel
- [x] QuitMessage
- [x] Rconnect
- [x] RDCC
- [x] Redact
- [x] Rehash
- [x] Relaymsg
- [x] Restart
- [x] Resume
- [x] Rline
- [x] RlineDel
- [x] Rmode
- [x] Rmtkl
- [x] Rsquit
- [x] SaJoin
- [x] Sakick
- [x] SaMode
- [x] SaNick
- [x] SaPart
- [x] Saquit
- [x] SASLECDSAChallenge
- [x] SASLExternal
- [x] SASLScramSHA256
- [x] Satopic
- [x] Sdesc
- [x] ShowCredits
- [x] ShowLicense
- [x] ShowStaff
- [x] Shun
- [x] Silence
- [x] SpamfilterAdd
- [x] SpamfilterDel
- [x] Starttls
- [x] StatServAkill
- [x] StatServInfo
- [x] STSAutoUpgrade
- [x] STSRemember
- [x] Swhois
- [x] Tempshun
- [x] Tline
- [x] Tsctl
- [x] Undccdeny
- [x] Uninvite
- [x] Verify
- [x] Vhost
- [x] Wallops
- [x] WebPushRegister
- [x] WebPushUnregister
- [x] ZLine

## Bots
- [x] Botmotd
