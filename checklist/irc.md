# IRC — Full Protocol Surface Checklist

**Last updated:** 2026-04-13 (Step 3)
**Current:** 399 methods, ~5,700 lines. RFC 1459/2812 + IRCv3 + CTCP + DCC + services. Pure Go.
**Confirmed working:** 95 extended + 55 Core (all pass on Libera.Chat, Step 2).
**Remaining:** ~130 items listed below.

Only features NOT yet implemented are listed.

---

## IRCd Oper Commands — UnrealIRCd (~23 commands)

- [ ] Tempshun — Temporarily shun a user connection
- [ ] Spamfilter — Add/remove regex spam filters with configurable actions
- [ ] Rmtkl — Mass-remove TKLs by pattern
- [ ] Jumpserver — Redirect all users to another server
- [ ] Tsctl — Manage server time synchronization
- [ ] Dccdeny — Blacklist file patterns from DCC
- [ ] Undccdeny — Remove DCCDENY entry
- [ ] Dccallow — Manage per-user DCC allow list
- [ ] Sdesc — Change server description on the fly
- [ ] Mkpasswd — Generate hashed passwords for config
- [ ] Ircops — Show online IRC operators
- [ ] Cycle — Leave and rejoin channel atomically
- [ ] CloseConnections — Terminate all pending unregistered connections
- [ ] DnsInfo — View DNS resolver cache
- [ ] Eline — Create/manage ban exceptions (E-lines)
- [ ] Addmotd — Append lines to server MOTD
- [ ] Addomotd — Append lines to oper MOTD
- [ ] Botmotd — View bot-specific MOTD
- [ ] Opermotd — View oper-specific MOTD
- [ ] ShowCredits — Display server credits
- [ ] ShowLicense — Display software license
- [ ] ShowStaff — Display staff file
- [ ] ModuleManage — List/load/unload server modules

## IRCd Oper Commands — InspIRCd (~23 commands)

- [ ] ForcePart — Force-part user from channel (REMOVE/FPART)
- [ ] Uninvite — Revoke pending INVITE
- [ ] Clearchan — Mass-punish all channel members
- [ ] Cban — Prevent channel patterns from being created
- [ ] Rline — Ban users matching regex on connect
- [ ] Tline — Test how many users match a mask
- [ ] Clones — Detect users from same IP
- [ ] Lockserv — Lock server, prevent new connections
- [ ] Unlockserv — Unlock server
- [ ] Rconnect — Force remote server to connect to another
- [ ] Rsquit — Force remote server to disconnect
- [ ] Nicklock — Force and lock a user's nick
- [ ] Nickunlock — Remove nick lock
- [ ] Setidle — Set own idle time
- [ ] Swhois — Set custom WHOIS line for user
- [ ] Ojoin — Join channel with oper prefix
- [ ] Sakick — Force-kick user from channel
- [ ] Saquit — Force user to QUIT
- [ ] Satopic — Force-set channel topic
- [ ] Rmode — Apply mode to all matching channels
- [ ] Filter — Add/remove message content filters
- [ ] Alltime — Display time on all servers
- [ ] Qline — Quarantine nick pattern

## IRCv3 Extensions (~19 specs)

- [ ] Metadata — Key-value metadata for users/channels (GET/SET/LIST/SUB/UNSUB)
- [ ] Relaymsg — Relay bridged messages with spoofed nicks
- [ ] StandardReplies — Handle FAIL/WARN/NOTE structured responses
- [ ] STS — Strict Transport Security auto-upgrade to TLS
- [ ] WebSocketTransport — Connect via ws:// / wss://
- [ ] NoImplicitNames — Disable automatic NAMES after JOIN
- [ ] ExtendedMonitor — Track away/account/chghost in MONITOR
- [ ] AccountExtban — ISUPPORT for constructing account-based EXTBANs
- [ ] BotMode — User mode + tag for marking bots
- [ ] InviteNotify — Notify ops when someone is INVITEd
- [ ] ChannelContext — Client-only tag for DM channel context
- [ ] ReactTag — Client-only tag for emoji reactions
- [ ] ClientBatch — Client-to-server batch support
- [ ] Multiline — Multi-line messages via batch
- [ ] PreAway — Send AWAY during registration
- [ ] ExtendedIsupport — Fetch ISUPPORT before registration
- [ ] NetworkIcon — ISUPPORT for network icon URL
- [ ] Filehost — Server-side file upload endpoint

## SASL Mechanisms (3)

- [ ] SASLScramSHA256 — SCRAM-SHA-256 challenge-response auth
- [ ] SASLExternal — Auth via TLS client certificate (CertFP)
- [ ] SASLECDSAChallenge — ECDSA public/private key auth

## DCC Extensions (2)

- [ ] DCCReverse — Passive/reverse DCC for NAT traversal (port 0 signal)
- [ ] RDCC — Advanced handshake for DCC Server mode

## Extended Bans — Helpers (18 types)

- [ ] ExtbanTimed — `~t` timed bans (auto-expire)
- [ ] ExtbanQuiet — `~q` prevent speaking, not joining
- [ ] ExtbanNickchange — `~n` prevent nick changes
- [ ] ExtbanJoin — `~j` prevent joining
- [ ] ExtbanForward — `~f` forward to another channel
- [ ] ExtbanMsgbypass — `~m` exempt from message restrictions
- [ ] ExtbanFlood — `~F` exempt from flood protection
- [ ] ExtbanAccount — `~a` match by services account
- [ ] ExtbanASN — `~A` match by Autonomous System Number
- [ ] ExtbanChannel — `~c` match by channel membership
- [ ] ExtbanCountry — `~C` match by country (GeoIP)
- [ ] ExtbanSecurityGroup — `~G` match by security group
- [ ] ExtbanOperclass — `~O` match by oper class
- [ ] ExtbanRealname — `~r` match by realname
- [ ] ExtbanCertFP — `~S` match by TLS certificate fingerprint
- [ ] ExtbanInherit — `~i` inherit bans from another channel
- [ ] ExtbanText — `~T` channel-specific text filter
- [ ] ExtbanPartmsg — `~p` hide part/quit messages

## Channel Modes — Typed Methods (~20)

- [ ] SetNoColors — `+c` strip formatting
- [ ] SetNoCTCP — `+C` block CTCP except ACTION
- [ ] SetDelayedJoins — `+D` users invisible until they speak
- [ ] SetFloodProtection — `+f/+F` configurable flood thresholds
- [ ] SetWordFilter — `+g` per-channel word filter
- [ ] SetCensor — `+G` strip bad words
- [ ] SetChannelHistory — `+H` show last N messages on join
- [ ] SetJoinThrottle — `+j/+J` limit joins per time period
- [ ] SetNoKnock — `+K` disable KNOCK
- [ ] SetChannelRedirect — `+L` overflow to another channel
- [ ] SetRequireRegistered — `+M` require registered nick to speak / `+R` to join
- [ ] SetNoNickChange — `+N` no nick changes in channel
- [ ] SetOperOnly — `+O` oper-only channel
- [ ] SetPermanent — `+P` persist with no users
- [ ] SetNoKicks — `+Q` no kicks
- [ ] SetStripColors — `+S` strip color codes
- [ ] SetNoNotices — `+T` no channel NOTICEs
- [ ] SetAuditorium — `+u` only ops visible in NAMES
- [ ] SetNoInvite — `+V` disable INVITE
- [ ] SetSSLOnly — `+z` TLS-only channel

## User Modes — Typed Methods (~10)

- [ ] SetBotMode — `+B` mark as bot
- [ ] SetDeafMode — `+d/+D` don't receive channel messages
- [ ] SetCallerID — `+g` block all unless ACCEPTed
- [ ] SetHideOper — `+H` hide oper from WHOIS
- [ ] SetHideChannels — `+I` hide channels from WHOIS
- [ ] SetBlockUnregistered — `+R` block messages from unregistered
- [ ] SetBlockCTCP — `+T` block CTCP from non-accepted
- [ ] SetWhoisNotify — `+W` alert when someone WHOISes you
- [ ] SetRequireSSL — `+Z` require TLS for messages

## ACCEPT Command (1)

- [ ] Accept — Manage caller-ID accept list (+nick, -nick, * list)

## IRC Formatting Helpers (4)

- [ ] FormatBold / FormatItalic / FormatUnderline / FormatStrikethrough / FormatMonospace / FormatColor / FormatReset — Text formatting code helpers
- [ ] StripFormatting — Remove all formatting codes from text
- [ ] ParseColors — Parse mIRC color codes to structured data
- [ ] FormatHexColor — Set color via 0x04 RRGGBB hex

## Connection/Transport (5)

- [ ] ConnectWebSocket — Connect via ws:// or wss://
- [ ] ConnectSOCKS — Connect through SOCKS4/SOCKS5 proxy
- [ ] ConnectHTTPProxy — Connect through HTTP CONNECT tunnel
- [ ] ParsePROXYProtocol — Parse HAProxy PROXY headers
- [ ] STSAutoUpgrade — Remember and enforce TLS-only policy

## CTCP Types (2)

- [ ] CTCPErrMsg — Error reply to unknown CTCP query
- [ ] CTCPAvatar — User avatar URL (non-standard)
