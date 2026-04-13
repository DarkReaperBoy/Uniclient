# Mumble — Full Protocol Surface Checklist

**Last updated:** 2026-04-13 (Step 3)
**Current:** 246 methods, ~5,700 lines. Pure Go. TCP+TLS control, OCB2-AES128 UDP voice, hand-coded protobuf, Ice RPC admin.
**Confirmed working:** All Core interface + extended methods (Step 1/2).
**Remaining:** ~111 methods listed below.

Only methods NOT yet implemented are listed.

---

## Ice RPC — Meta Interface (11 methods)

Currently only Server servant is connected. The entire Meta interface for managing virtual servers is absent.

- [ ] MetaGetServer — `Meta.getServer(id)` — Get Server proxy by virtual server ID
- [ ] MetaNewServer — `Meta.newServer()` — Create a new virtual server instance
- [ ] MetaGetBootedServers — `Meta.getBootedServers()` — List all running virtual servers
- [ ] MetaGetAllServers — `Meta.getAllServers()` — List all defined virtual servers (running or stopped)
- [ ] MetaGetDefaultConf — `Meta.getDefaultConf()` — Get default server config map
- [ ] MetaGetVersion — `Meta.getVersion()` — Get Murmur daemon version
- [ ] MetaAddCallback — `Meta.addCallback(cb)` — Register MetaCallback for start/stop events
- [ ] MetaRemoveCallback — `Meta.removeCallback(cb)` — Unregister MetaCallback
- [ ] MetaGetUptime — `Meta.getUptime()` — Get daemon uptime (distinct from per-server)
- [ ] MetaGetSlice — `Meta.getSlice()` — Get full Slice definition string
- [ ] MetaGetSliceChecksums — `Meta.getSliceChecksums()` — Get Slice checksums

## Ice RPC — Server Interface (~37 methods)

7 of ~45 Server methods implemented. Missing:

- [ ] IceServerIsRunning — `Server.isRunning()` — Check if virtual server is running
- [ ] IceServerStart — `Server.start()` — Start (boot) virtual server
- [ ] IceServerStop — `Server.stop()` — Stop virtual server
- [ ] IceServerDelete — `Server.delete()` — Delete virtual server entirely
- [ ] IceServerID — `Server.id()` — Get numeric ID of virtual server
- [ ] IceGetConf — `Server.getConf(key)` — Get single config value
- [ ] IceGetAllConf — `Server.getAllConf()` — Get entire config map
- [ ] IceSetSuperuserPassword — `Server.setSuperuserPassword(pw)` — Set SuperUser password
- [ ] IceGetLogLen — `Server.getLogLen()` — Get total log entry count
- [ ] IceGetUsers — `Server.getUsers()` — Get map of all connected users (session -> User)
- [ ] IceGetChannels — `Server.getChannels()` — Get map of all channels (id -> Channel)
- [ ] IceGetCertificateList — `Server.getCertificateList(session)` — Get TLS cert chain for user
- [ ] IceGetTree — `Server.getTree()` — Get full channel tree (recursive Tree with users)
- [ ] IceGetBans — `Server.getBans()` — Get ban list via Ice (structured Ban objects)
- [ ] IceSetBans — `Server.setBans(bans)` — Replace ban list via Ice
- [ ] IceKickUser — `Server.kickUser(session, reason)` — Kick user via Ice
- [ ] IceGetState — `Server.getState(session)` — Get full User state struct via Ice
- [ ] IceSetState — `Server.setState(state)` — Modify user state via Ice
- [ ] IceSendMessage — `Server.sendMessage(session, text)` — Send text to user via Ice
- [ ] IceHasPermission — `Server.hasPermission(session, channelid, perm)` — Check permission
- [ ] IceEffectivePermissions — `Server.effectivePermissions(session, channelid)` — Get effective permission bitmask
- [ ] IceGetChannelState — `Server.getChannelState(channelid)` — Get Channel struct via Ice
- [ ] IceSetChannelState — `Server.setChannelState(state)` — Modify channel properties via Ice
- [ ] IceRemoveChannel — `Server.removeChannel(channelid)` — Remove channel via Ice
- [ ] IceAddChannel — `Server.addChannel(name, parent)` — Create channel via Ice
- [ ] IceSendMessageChannel — `Server.sendMessageChannel(channelid, tree, text)` — Send text to channel
- [ ] IceGetACL — `Server.getACL(channelid)` — Get ACL/groups for channel via Ice
- [ ] IceSetACL — `Server.setACL(channelid, acls, groups, inherit)` — Set ACL/groups via Ice
- [ ] IceAddUserToGroup — `Server.addUserToGroup(channelid, session, group)` — Add user to ACL group
- [ ] IceRemoveUserFromGroup — `Server.removeUserFromGroup(channelid, session, group)` — Remove from group
- [ ] IceGetUserNames — `Server.getUserNames(ids)` — Resolve user IDs to names
- [ ] IceGetUserIds — `Server.getUserIds(names)` — Resolve names to IDs
- [ ] IceRegisterUser — `Server.registerUser(info)` — Register new user via Ice
- [ ] IceUnregisterUser — `Server.unregisterUser(userid)` — Unregister user via Ice
- [ ] IceUpdateRegistration — `Server.updateRegistration(userid, info)` — Update registered user info
- [ ] IceGetRegistration — `Server.getRegistration(userid)` — Get registered user info
- [ ] IceVerifyPassword — `Server.verifyPassword(name, pw)` — Verify user password
- [ ] IceGetTexture — `Server.getTexture(userid)` — Get user avatar/texture via Ice
- [ ] IceSetTexture — `Server.setTexture(userid, tex)` — Set user avatar/texture via Ice
- [ ] IceStartListening — `Server.startListening(userid, channelid)` — Make user listen via Ice
- [ ] IceStopListening — `Server.stopListening(userid, channelid)` — Stop listening via Ice
- [ ] IceIsListening — `Server.isListening(userid, channelid)` — Check listening via Ice
- [ ] IceGetListeningChannels — `Server.getListeningChannels(userid)` — Get channels user listens to
- [ ] IceGetListeningUsers — `Server.getListeningUsers(channelid)` — Get users listening to channel
- [ ] IceSendWelcomeMessage — `Server.sendWelcomeMessage(receiverUserIDs)` — Send welcome to specific users

## Ice RPC — Callbacks (9 methods)

- [ ] IceServerCallbackUserConnected — Notification when user connects
- [ ] IceServerCallbackUserDisconnected — Notification when user disconnects
- [ ] IceServerCallbackUserStateChanged — Notification when user state changes
- [ ] IceServerCallbackUserTextMessage — Notification when user sends text
- [ ] IceServerCallbackChannelCreated — Notification when channel created
- [ ] IceServerCallbackChannelRemoved — Notification when channel removed
- [ ] IceServerCallbackChannelStateChanged — Notification when channel state changes
- [ ] IceMetaCallbackStarted — Notification when virtual server starts
- [ ] IceMetaCallbackStopped — Notification when virtual server stops

## Ice RPC — Authenticator (10 methods)

Custom external authenticator support:

- [ ] IceSetAuthenticator — `Server.setAuthenticator(auth)` — Register custom authenticator
- [ ] AuthenticatorAuthenticate — Authenticate connecting user, return userid + groups
- [ ] AuthenticatorGetInfo — Get user info for registered user
- [ ] AuthenticatorNameToId — Resolve username to user ID
- [ ] AuthenticatorIdToName — Resolve user ID to username
- [ ] AuthenticatorIdToTexture — Get user texture by ID
- [ ] UpdatingAuthRegisterUser — Register user (server callback)
- [ ] UpdatingAuthUnregisterUser — Unregister user (server callback)
- [ ] UpdatingAuthSetInfo — Update user info (server callback)
- [ ] UpdatingAuthSetTexture — Update user texture (server callback)

## Client Protocol — Missing Features (~15 methods)

- [ ] RenameChannel — Send ChannelState with new name field
- [ ] GetChannelDescription — Convenience: auto-resolve hash via RequestBlob
- [ ] GetUserComment — Convenience: auto-resolve comment hash via RequestBlob
- [ ] GetUserTexture — Convenience: auto-resolve texture hash via RequestBlob
- [ ] ParseMumbleURL — Parse `mumble://` URL into components
- [ ] ConnectFromURL — Connect using mumble:// URL
- [ ] HandleUserStats — Callback for receiving UserStats responses
- [ ] LoadCertificate — Load TLS client certificate from PEM files
- [ ] GetCertificateHash — Get SHA1 hash of client certificate
- [ ] GetServerCertificate — Get server's TLS certificate for pinning
- [ ] FlushPermissions — Send PermissionQuery with flush=true
- [ ] GetCachedPermissions — Get locally cached permissions without round-trip
- [ ] GetChannelTree — Build full channel tree as structured object
- [ ] Reconnect — Reconnect with same credentials
- [ ] SetAutoReconnect — Auto-reconnect on disconnection with configurable delay

## Audio — Missing Features (4 methods)

- [ ] SetAudioBitrate — Configure Opus encoder bitrate
- [ ] SetAudioFrameSize — Configure audio frame duration (10/20/40/60ms)
- [ ] GetAudioStats — Get local audio statistics (packets sent/received/lost)
- [ ] OnAudioStream — Per-user audio stream callback
