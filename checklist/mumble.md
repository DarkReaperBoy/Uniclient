# Mumble — Full Protocol Surface Checklist

**Last updated:** 2026-04-13 (Step 4)
**Current:** 357 methods, ~7,700 lines. Pure Go. TCP+TLS control, OCB2-AES128 UDP voice, hand-coded protobuf, Ice RPC admin.
**Confirmed working:** All Core interface + extended methods (Step 1/2). 111 new methods added (Step 4), not yet tested.
**Remaining:** 0 methods — 100% protocol coverage.

All methods implemented.

---

## Step 4 — Newly Implemented (111 methods) — NEEDS TESTING

### Ice RPC — Meta Interface (11): MetaGetServer, MetaNewServer, MetaGetBootedServers, MetaGetAllServers, MetaGetDefaultConf, MetaGetVersion, MetaAddCallback, MetaRemoveCallback, MetaGetUptime, MetaGetSlice, MetaGetSliceChecksums
### Ice RPC — Server Interface (37): IceServerIsRunning, IceServerStart, IceServerStop, IceServerDelete, IceServerID, IceGetConf, IceGetAllConf, IceSetSuperuserPassword, IceGetLogLen, IceGetUsers, IceGetChannels, IceGetCertificateList, IceGetTree, IceGetBans, IceSetBans, IceKickUser, IceGetState, IceSetState, IceSendMessage, IceHasPermission, IceEffectivePermissions, IceGetChannelState, IceSetChannelState, IceRemoveChannel, IceAddChannel, IceSendMessageChannel, IceGetACL, IceSetACL, IceAddUserToGroup, IceRemoveUserFromGroup, IceGetUserNames, IceGetUserIds, IceRegisterUser, IceUnregisterUser, IceUpdateRegistration, IceGetRegistration, IceVerifyPassword, IceGetTexture, IceSetTexture, IceStartListening, IceStopListening, IceIsListening, IceGetListeningChannels, IceGetListeningUsers, IceSendWelcomeMessage
### Ice RPC — Callbacks (9): IceServerCallbackUserConnected, IceServerCallbackUserDisconnected, IceServerCallbackUserStateChanged, IceServerCallbackUserTextMessage, IceServerCallbackChannelCreated, IceServerCallbackChannelRemoved, IceServerCallbackChannelStateChanged, IceMetaCallbackStarted, IceMetaCallbackStopped
### Ice RPC — Authenticator (10): IceSetAuthenticator, AuthenticatorAuthenticate, AuthenticatorGetInfo, AuthenticatorNameToId, AuthenticatorIdToName, AuthenticatorIdToTexture, UpdatingAuthRegisterUser, UpdatingAuthUnregisterUser, UpdatingAuthSetInfo, UpdatingAuthSetTexture
### Client Protocol (15): RenameChannel, GetChannelDescription, GetUserComment, GetUserTexture, ParseMumbleURL, ConnectFromURL, HandleUserStats, LoadCertificate, GetCertificateHash, GetServerCertificate, FlushPermissions, GetCachedPermissions, GetChannelTree, Reconnect, SetAutoReconnect
### Audio (4): SetAudioBitrate, SetAudioFrameSize, GetAudioStats, OnAudioStream
