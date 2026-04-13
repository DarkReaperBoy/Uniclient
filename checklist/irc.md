# IRC — Full Protocol Surface Checklist

**Last updated:** 2026-04-13 (Step 4)
**Current:** 529 methods, ~7,300 lines. RFC 1459/2812 + IRCv3 + CTCP + DCC + services. Pure Go.
**Confirmed working:** 95 extended + 55 Core (all pass on Libera.Chat, Step 2). 130 new methods added (Step 4), not yet tested.
**Remaining:** 0 methods — 100% protocol coverage.

All methods implemented.

---

## Step 4 — Newly Implemented (~130 methods) — NEEDS TESTING

### UnrealIRCd Oper (23): Tempshun, SpamfilterAdd/Del, Rmtkl, Jumpserver, Tsctl, Dccdeny, Undccdeny, Dccallow, Sdesc, Mkpasswd, Ircops, Cycle, CloseConnections, DnsInfo, Eline, Addmotd, Addomotd, Botmotd, Opermotd, ShowCredits, ShowLicense, ShowStaff, ModuleManage
### InspIRCd Oper (23): ForcePart, Uninvite, Clearchan, Cban/CbanDel, Rline/RlineDel, Tline, Clones, Lockserv, Unlockserv, Rconnect, Rsquit, Nicklock, Nickunlock, Setidle, Swhois, Ojoin, Sakick, Saquit, Satopic, Rmode, FilterAdd/FilterDel, Alltime, Qline/QlineDel
### IRCv3 Extensions (19): MetadataGet/Set/List/Sub/Unsub, Relaymsg, ParseStandardReply, STSAutoUpgrade, ConnectWebSocket, RequestNoImplicitNames, RequestExtendedMonitor, ParseAccountExtban, SetBotModeIRCv3, OnInviteNotify, SendChannelContextTag, SendReactTag, SendClientBatch, SendMultiline, PreAway, RequestExtendedIsupport, GetNetworkIcon, FilehostUpload
### SASL (3): SASLScramSHA256, SASLExternal, SASLECDSAChallenge
### DCC Extensions (2): DCCReverse, RDCC
### Extended Bans (18): ExtbanTimed, ExtbanQuiet, ExtbanNickchange, ExtbanJoin, ExtbanForward, ExtbanMsgbypass, ExtbanFlood, ExtbanAccount, ExtbanASN, ExtbanChannel, ExtbanCountry, ExtbanSecurityGroup, ExtbanOperclass, ExtbanRealname, ExtbanCertFP, ExtbanInherit, ExtbanText, ExtbanPartmsg
### Channel Modes (20): SetNoColors, SetNoCTCP, SetDelayedJoins, SetFloodProtection, SetWordFilter, SetCensor, SetChannelHistory, SetJoinThrottle, SetNoKnock, SetChannelRedirect, SetRequireRegistered, SetRequireRegisteredSpeak, SetNoNickChange, SetOperOnly, SetPermanent, SetNoKicks, SetStripColors, SetNoNotices, SetAuditorium, SetNoInvite, SetSSLOnly
### User Modes (9): SetBotMode, SetDeafMode, SetCallerID, SetHideOper, SetHideChannels, SetBlockUnregistered, SetBlockCTCP, SetWhoisNotify, SetRequireSSL
### ACCEPT (1): Accept
### Formatting (4 groups): FormatBold/Italic/Underline/Strikethrough/Monospace/Color/Reset, StripFormatting, ParseColors, FormatHexColor
### Connection (5): ConnectWebSocket, ConnectSOCKS, ConnectHTTPProxy, ParsePROXYProtocol, STSRemember
### CTCP (2): CTCPErrMsg, CTCPAvatar
