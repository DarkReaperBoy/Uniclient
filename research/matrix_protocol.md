# Matrix Protocol — Implementation Reference

<!-- Last updated: 2026-04-10 -->

## Overview

Matrix is an open, federated messaging protocol. Unlike Telegram/Bale/Rubika (proprietary, reverse-engineered), Matrix has a complete public spec at [spec.matrix.org](https://spec.matrix.org/v1.13/client-server-api/).

**SDK**: `maunium.net/go/mautrix` (v0.26.x) — mature Go client with full CS API coverage, E2EE (Olm/Megolm), sync, state store, crypto store, event types.

**Transport**: HTTP/JSON REST (Client-Server API v1.13). Long-poll `/sync` for real-time.

**Auth modes**: Password login (user mode), access token (bot mode / application service).

**E2EE**: Olm (1:1 key exchange) + Megolm (group sessions). Cross-signing, key backup (SSSS), device verification. We use `OlmMachine` directly with `MemoryStore` (pickle-based JSON persistence) — no `cryptohelper`, no SQL. Pure Go via goolm (`-tags goolm`).

---

## Architecture Decisions

1. **Use mautrix-go directly** — no raw HTTP. The SDK wraps every CS API endpoint with typed Go methods. E2EE uses `OlmMachine` + `MemoryStore` directly (no `cryptohelper`, no SQL).

2. **Session persistence** — Three files per account: `matrix_session.json` (homeserver, token, device ID, pickle key), `matrix_session_crypto.json` (Olm/Megolm sessions pickled + devices/keys as JSON), `matrix_session_state.json` (room encryption state, members). All pure Go, no SQLite.

3. **Real-time** — `DefaultSyncer` dispatches events by type. We register handlers for message, state, ephemeral (typing/receipts/presence), and call events. Each handler converts to our `Update` type and calls `OnUpdate`.

4. **Calls** — 1:1 VoIP uses Matrix call signaling events (`m.call.invite/answer/candidates/hangup`) + pion WebRTC (same as Delta Chat). Group calls (MSC3401/MatrixRTC) are unstable — defer to later.

5. **Spaces = Folders** — Matrix Spaces map to our `Folder` type. `m.space.child` state events define membership. `Hierarchy` API for traversal.

6. **Threads** — `m.thread` relation type. Use `GetRelations` to fetch thread replies. Map to `CreateTopic`/topics in our Core interface.

---

## API Endpoint Reference

### Authentication

| SDK Method | Endpoint | Notes |
|-----------|----------|-------|
| `Login` | `POST /login` | Password or token. Returns access_token + device_id |
| `Logout` | `POST /logout` | Invalidate access token |
| `LogoutAll` | `POST /logout/all` | Invalidate all tokens |
| `Whoami` | `GET /account/whoami` | Get user ID + device ID |
| `GetLoginFlows` | `GET /login` | List supported auth types |

### Sync

| SDK Method | Endpoint | Notes |
|-----------|----------|-------|
| `SyncWithContext` | `GET /sync` | Long-poll. Returns timeline, state, ephemeral, to-device, account data |
| `StopSync` | — | Stops the sync loop |
| `CreateFilter` | `POST /user/{userId}/filter` | Create filter for selective sync |

### Rooms

| SDK Method | Endpoint | Notes |
|-----------|----------|-------|
| `CreateRoom` | `POST /createRoom` | Presets: private_chat, public_chat, trusted_private_chat |
| `JoinRoom` | `POST /join/{roomIdOrAlias}` | Join by ID, alias, or invite |
| `JoinRoomByID` | `POST /rooms/{roomId}/join` | Direct join by ID |
| `LeaveRoom` | `POST /rooms/{roomId}/leave` | Leave room |
| `ForgetRoom` | `POST /rooms/{roomId}/forget` | Remove from room list after leaving |
| `KnockRoom` | `POST /knock/{roomIdOrAlias}` | Request to join |
| `JoinedRooms` | `GET /joined_rooms` | List joined room IDs |
| `PublicRooms` | `POST /publicRooms` | Search public room directory |
| `Hierarchy` | `GET /rooms/{roomId}/hierarchy` | Space child rooms (recursive) |

### Room State

| SDK Method | Endpoint | Notes |
|-----------|----------|-------|
| `State` | `GET /rooms/{roomId}/state` | All current state |
| `StateEvent` | `GET /rooms/{roomId}/state/{type}/{key}` | Specific state event |
| `SendStateEvent` | `PUT /rooms/{roomId}/state/{type}/{key}` | Set state |

**Key state events**: `m.room.name`, `m.room.topic`, `m.room.avatar`, `m.room.power_levels`, `m.room.join_rules`, `m.room.history_visibility`, `m.room.encryption`, `m.room.pinned_events`, `m.room.canonical_alias`, `m.room.tombstone`, `m.space.child`, `m.space.parent`.

### Messages

| SDK Method | Endpoint | Notes |
|-----------|----------|-------|
| `SendMessageEvent` | `PUT /rooms/{roomId}/send/{type}/{txnId}` | Send any message event (idempotent) |
| `SendText` | — | Convenience: sends `m.text` |
| `SendNotice` | — | Convenience: sends `m.notice` |
| `SendReaction` | — | Sends `m.reaction` with `m.annotation` relation |
| `Messages` | `GET /rooms/{roomId}/messages` | Paginate history (dir=b/f) |
| `GetEvent` | `GET /rooms/{roomId}/event/{eventId}` | Single event by ID |
| `Context` | `GET /rooms/{roomId}/context/{eventId}` | Event with surrounding context |
| `RedactEvent` | `PUT /rooms/{roomId}/redact/{eventId}/{txnId}` | Delete/redact event |
| `GetRelations` | `GET /rooms/{roomId}/relations/{eventId}` | Reactions, threads, edits |

**Message types** (`m.room.message` msgtype): `m.text`, `m.emote`, `m.notice`, `m.image`, `m.file`, `m.audio`, `m.video`, `m.location`.

**Editing**: Send `m.room.message` with `m.new_content` + `m.relates_to: {rel_type: "m.replace", event_id: "..."}`.

**Reactions**: Send `m.reaction` with `m.relates_to: {rel_type: "m.annotation", event_id: "...", key: "emoji"}`.

**Threads**: Send with `m.relates_to: {rel_type: "m.thread", event_id: "root_id"}`.

### Members

| SDK Method | Endpoint | Notes |
|-----------|----------|-------|
| `InviteUser` | `POST /rooms/{roomId}/invite` | Invite user |
| `KickUser` | `POST /rooms/{roomId}/kick` | Kick (set membership=leave) |
| `BanUser` | `POST /rooms/{roomId}/ban` | Ban user |
| `UnbanUser` | `POST /rooms/{roomId}/unban` | Unban user |
| `Members` | `GET /rooms/{roomId}/members` | All members with filter |
| `JoinedMembers` | `GET /rooms/{roomId}/joined_members` | Joined members (name+avatar) |

### Read Receipts & Typing

| SDK Method | Endpoint | Notes |
|-----------|----------|-------|
| `MarkRead` | `POST /rooms/{roomId}/receipt/m.read/{eventId}` | Send read receipt |
| `SendReceipt` | `POST /rooms/{roomId}/receipt/{type}/{eventId}` | m.read, m.read.private, m.fully_read |
| `SetReadMarkers` | `POST /rooms/{roomId}/read_markers` | Set fully-read + read position |
| `UserTyping` | `PUT /rooms/{roomId}/typing/{userId}` | Typing indicator (true/false + timeout) |

### Profile & Presence

| SDK Method | Endpoint | Notes |
|-----------|----------|-------|
| `GetProfile` | `GET /profile/{userId}` | Display name + avatar |
| `SetDisplayName` | `PUT /profile/{userId}/displayname` | Set display name |
| `GetAvatarURL` | `GET /profile/{userId}/avatar_url` | Get avatar mxc:// URI |
| `SetAvatarURL` | `PUT /profile/{userId}/avatar_url` | Set avatar |
| `GetPresence` | `GET /presence/{userId}/status` | Online/offline/unavailable |
| `SetPresence` | `PUT /presence/{userId}/status` | Set presence + status message |

### Media

| SDK Method | Endpoint | Notes |
|-----------|----------|-------|
| `UploadMedia` | `POST /media/upload` | Upload, returns mxc:// URI |
| `UploadBytes` | — | Convenience: bytes + content type |
| `Download` | `GET /media/download/{server}/{mediaId}` | Download media |
| `DownloadBytes` | — | Convenience: returns []byte |
| `DownloadThumbnail` | `GET /media/thumbnail/{server}/{mediaId}` | Thumbnail (crop/scale) |
| `GetURLPreview` | `GET /media/preview_url` | URL preview (og:* meta) |
| `GetMediaConfig` | `GET /media/config` | Upload size limit |

### Account Data & Tags

| SDK Method | Endpoint | Notes |
|-----------|----------|-------|
| `GetAccountData` | `GET /user/{userId}/account_data/{type}` | Global account data |
| `SetAccountData` | `PUT /user/{userId}/account_data/{type}` | Set global |
| `GetRoomAccountData` | `GET /user/{userId}/rooms/{roomId}/account_data/{type}` | Per-room |
| `SetRoomAccountData` | `PUT /user/{userId}/rooms/{roomId}/account_data/{type}` | Set per-room |
| `AddTag` | `PUT /user/{userId}/rooms/{roomId}/tags/{tag}` | Tag room (m.favourite, m.lowpriority) |
| `RemoveTag` | `DELETE /user/{userId}/rooms/{roomId}/tags/{tag}` | Remove tag |
| `GetTags` | `GET /user/{userId}/rooms/{roomId}/tags` | Get room tags |

### Devices & Sessions

| SDK Method | Endpoint | Notes |
|-----------|----------|-------|
| `GetDevicesInfo` | `GET /devices` | List all devices |
| `GetDeviceInfo` | `GET /devices/{deviceId}` | Single device info |
| `SetDeviceInfo` | `PUT /devices/{deviceId}` | Update display name |
| `DeleteDevice` | `DELETE /devices/{deviceId}` | Delete device (UIA) |
| `DeleteDevices` | `POST /delete_devices` | Bulk delete (UIA) |

### E2EE Keys

| SDK Method | Endpoint | Notes |
|-----------|----------|-------|
| `UploadKeys` | `POST /keys/upload` | Device + one-time keys |
| `QueryKeys` | `POST /keys/query` | Query device keys for users |
| `ClaimKeys` | `POST /keys/claim` | Claim OTKs for Olm sessions |
| `GetKeyChanges` | `GET /keys/changes` | Changed devices since token |
| `UploadCrossSigningKeys` | `POST /keys/device_signing/upload` | Cross-signing keys (UIA) |
| `UploadSignatures` | `POST /keys/signatures/upload` | Sign devices/users |

**Key backup**: `CreateKeyBackupVersion`, `GetKeyBackupVersion`, `PutKeysInBackup`, `GetKeyBackup`, `DeleteKeyBackup` (14 methods total for SSSS).

### Search

| SDK Method | Endpoint | Notes |
|-----------|----------|-------|
| `Search` | `POST /search` | Search room events (text, sender, room) |
| `SearchUserDirectory` | `POST /user_directory/search` | Search users by name/ID |

### VoIP Calls (1:1)

No REST endpoints — signaling via room events:

| Event Type | Purpose |
|-----------|---------|
| `m.call.invite` | SDP offer, call_id, version, party_id, lifetime |
| `m.call.candidates` | ICE candidates array |
| `m.call.answer` | SDP answer |
| `m.call.hangup` | End call (reason: user_hangup, ice_timeout, etc.) |
| `m.call.reject` | Reject incoming |
| `m.call.select_answer` | Multi-device answer selection |
| `m.call.negotiate` | Mid-call renegotiation (SDP) |

| SDK Method | Endpoint | Notes |
|-----------|----------|-------|
| `TurnServer` | `GET /voip/turnServer` | Get TURN credentials (time-limited) |

### Room Aliases

| SDK Method | Endpoint | Notes |
|-----------|----------|-------|
| `CreateAlias` | `PUT /directory/room/{alias}` | Create alias |
| `DeleteAlias` | `DELETE /directory/room/{alias}` | Delete alias |
| `ResolveAlias` | `GET /directory/room/{alias}` | Resolve to room ID |
| `GetAliases` | `GET /rooms/{roomId}/aliases` | List all aliases |

### Ignoring Users

No dedicated endpoint — set via account data type `m.ignored_user_list`.

### Reporting

| SDK Method | Endpoint | Notes |
|-----------|----------|-------|
| `ReportEvent` | `POST /rooms/{roomId}/report/{eventId}` | Report content |
| `ReportRoom` | `POST /rooms/{roomId}/report` | Report room |

### Room Upgrades

| SDK Method | Endpoint | Notes |
|-----------|----------|-------|
| `UpgradeRoom` | `POST /rooms/{roomId}/upgrade` | Upgrade room version |

---

## Mapping to Core Interface

| Core Method | Matrix Implementation |
|------------|----------------------|
| `Name()` | `"matrix"` |
| `Capabilities()` | All except phone-based contacts |
| `Authenticate(cfg)` | `Login` (password) or set access token directly |
| `Logout()` | `Logout` |
| `GetDialogs(opts)` | Sync rooms from `/sync` response, cache locally |
| `CreateGroup(name, members)` | `CreateRoom` preset=private_chat + invite members |
| `CreateChannel(name, desc)` | `CreateRoom` preset=public_chat + set topic |
| `CreateTopic(chatID, name)` | Send message with `m.thread` relation (thread root) |
| `GetFolders()` | List Spaces (rooms with `m.space.child` state) |
| `CreateFolder(name, chatIDs)` | Create Space room + add `m.space.child` for each |
| `SendMessage(chatID, msg)` | `SendMessageEvent` (m.room.message, m.text) |
| `GetMessages(chatID, opts)` | `Messages` (paginate with dir=b) |
| `EditMessage(chatID, msgID, text)` | Send with `m.replace` relation + `m.new_content` |
| `DeleteMessage(chatID, msgID)` | `RedactEvent` |
| `ReplyToMessage(...)` | Send with `m.in_reply_to` in `m.relates_to` |
| `ForwardMessage(...)` | Re-send content with attribution (no native forward) |
| `ReactToMessage(...)` | `SendReaction` (m.annotation) |
| `PinMessage(chatID, msgID)` | Update `m.room.pinned_events` state (append event ID) |
| `UnpinMessage(chatID, msgID)` | Update `m.room.pinned_events` state (remove event ID) |
| `MarkAsRead(chatID, upToMsgID)` | `MarkRead` |
| `GetReadState(chatID)` | Read receipts from sync (per-user) |
| `UploadFile(chatID, file, progress)` | `UploadMedia` → send as m.file/m.image/m.audio/m.video |
| `DownloadFile(fileRef, dest, progress)` | `Download` (mxc:// URI) |
| `SendImageBase64(chatID, b64, caption)` | Decode → `UploadMedia` → send as m.image |
| `StartCall(chatID, video)` | Send `m.call.invite` + pion WebRTC |
| `JoinGroupCall(chatID)` | MSC3401 state events (unstable, defer) |
| `EndCall(callID)` | Send `m.call.hangup` |
| `SetCallMuted(callID, muted)` | Local pion track enable/disable |
| `GetProfile(userID)` | `GetProfile` |
| `OnUpdate(handler)` | Syncer event callbacks → convert to Update |
| `Close()` | `StopSync` + cleanup |
| `GetChatInfo(chatID)` | Room state (name, topic, avatar, member count) |
| `EditChatTitle(chatID, title)` | `SendStateEvent` m.room.name |
| `EditChatDescription(chatID, desc)` | `SendStateEvent` m.room.topic |
| `LeaveChat(chatID)` | `LeaveRoom` |
| `GetInviteLink(chatID)` | Room alias or `matrix.to` link |
| `AddMembers(chatID, userIDs)` | `InviteUser` for each |
| `RemoveMember(chatID, userID)` | `KickUser` |
| `BanMember(chatID, userID)` | `BanUser` |
| `UnbanMember(chatID, userID)` | `UnbanUser` |
| `GetMembers(chatID, opts)` | `Members` or `JoinedMembers` |
| `SetAdmin(chatID, userID, admin)` | Update `m.room.power_levels` (set user level) |
| `GetContacts()` | DM rooms from `m.direct` account data |
| `AddContact(phone, ...)` | `ErrNotSupported` (Matrix uses usernames, not phones) |
| `DeleteContact(userID)` | Remove from `m.direct` account data |
| `BlockUser(userID)` | Add to `m.ignored_user_list` account data |
| `UnblockUser(userID)` | Remove from `m.ignored_user_list` |
| `GetBlockedUsers()` | Read `m.ignored_user_list` |
| `SearchMessages(chatID, query, opts)` | `/search` with room filter |
| `SearchGlobal(query, opts)` | `/search` without room filter |
| `SendTyping(chatID)` | `UserTyping` |
| `CreatePoll(chatID, ...)` | `m.poll.start` event (MSC3381, unstable prefix) |
| `VotePoll(chatID, msgID, opt)` | `m.poll.response` event |
| `SendSticker(chatID, stickerID)` | `m.sticker` message type |
| `GetSessions()` | `GetDevicesInfo` |
| `TerminateSession(sessionID)` | `DeleteDevice` |

---

## Extra Methods (beyond Core interface)

These are Matrix-specific features worth exposing:

| Method | Purpose |
|--------|---------|
| `GetPresence(userID)` | Online/offline/unavailable + status message |
| `SetPresence(status, msg)` | Set own presence |
| `SetDisplayName(name)` | Update display name |
| `SetAvatar(mxcURI)` | Update avatar |
| `GetRoomAliases(chatID)` | List room aliases |
| `SetRoomAlias(chatID, alias)` | Create alias |
| `DeleteRoomAlias(alias)` | Delete alias |
| `GetPublicRooms(query, limit)` | Search public room directory |
| `JoinRoomByAlias(alias)` | Join via alias (e.g. #room:matrix.org) |
| `KnockRoom(chatID, reason)` | Request to join restricted room |
| `ForgetRoom(chatID)` | Remove from room list after leaving |
| `SetRoomAvatar(chatID, mxcURI)` | Set room avatar |
| `SetJoinRules(chatID, rule)` | public/invite/knock/restricted |
| `SetHistoryVisibility(chatID, vis)` | invited/joined/shared/world_readable |
| `EnableEncryption(chatID)` | Set m.room.encryption state |
| `GetEncryptionInfo(chatID)` | Check if room is encrypted, algorithm |
| `UpgradeRoom(chatID, version)` | Upgrade room version |
| `GetSpaceChildren(chatID)` | Space hierarchy traversal |
| `AddSpaceChild(spaceID, childID)` | Add room to space |
| `RemoveSpaceChild(spaceID, childID)` | Remove room from space |
| `GetThreads(chatID)` | List threads in room |
| `GetThreadReplies(chatID, threadRootID)` | Get thread reply chain |
| `SetRoomTag(chatID, tag)` | m.favourite, m.lowpriority, custom |
| `RemoveRoomTag(chatID, tag)` | Remove tag |
| `GetURLPreview(url)` | og:* metadata |
| `GetTurnServer()` | TURN credentials for calls |
| `VerifyDevice(userID, deviceID)` | Cross-signing verification |
| `GetDevices()` | List all devices (detailed) |
| `SetDeviceName(deviceID, name)` | Update device display name |
| `ExportKeys(passphrase)` | Export E2EE keys |
| `ImportKeys(data, passphrase)` | Import E2EE keys |
| `MarkUnread(chatID, unread)` | m.marked_unread room account data |
| `ReportEvent(chatID, eventID, reason)` | Report content |
| `SearchUsers(query, limit)` | User directory search |
| `GetDirectChats()` | DM room mappings from m.direct |
| `SetDirectChat(userID, roomID)` | Mark room as DM |

---

## E2EE Implementation Notes

Using `cryptohelper.NewCryptoHelper`:
1. Create SQLite DB at `auth/matrix_crypto.db`
2. Call `cryptoHelper.Init(ctx)` — handles key upload, cross-signing bootstrap, sync processing
3. For sending: `cryptoHelper.Encrypt(ctx, roomID, evtType, content)` → encrypted content
4. For receiving: decrypt happens in sync handler via `cryptoHelper.HandleEncrypted`
5. `cryptoHelper.Close()` on shutdown

Key backup via SSSS — `cryptoHelper` handles this if configured.

---

## Session Format

`auth/matrix_session.json`:
```json
{
  "homeserver": "https://matrix.org",
  "user_id": "@user:matrix.org",
  "access_token": "...",
  "device_id": "ABCDEF",
  "next_batch": "s123456_789"  // sync token
}
```

SQLite databases (managed by mautrix):
- `auth/matrix_state.db` — room state, member cache
- `auth/matrix_crypto.db` — Olm/Megolm sessions, device keys, cross-signing

---

## Dependencies

| Package | Purpose |
|---------|---------|
| `maunium.net/go/mautrix` | Matrix CS API client |
| `maunium.net/go/mautrix/crypto` | Olm/Megolm E2EE |
| `maunium.net/go/mautrix/crypto/cryptohelper` | Simplified E2EE setup |
| `maunium.net/go/mautrix/event` | Event types + content structs |
| `maunium.net/go/mautrix/id` | ID types (UserID, RoomID, etc.) |
| `github.com/pion/webrtc/v4` | WebRTC for voice/video calls |

All pure Go. No CGo dependencies.

---

## Known Limitations / Quirks

1. **Group calls (MSC3401)** — not in stable spec. Element Call uses it with unstable prefixes. Defer implementation.
2. **Polls (MSC3381)** — widely deployed but uses unstable event type prefix (`org.matrix.msc3381.v2.poll.start`). Implement with unstable prefix.
3. **Sliding sync** — not in stable spec. Use traditional `/sync` long-poll.
4. **AddContact by phone** — Matrix uses `@user:server` IDs, not phone numbers. Phone lookup requires identity server (privacy concerns). Return `ErrNotSupported`.
5. **Forward message** — no native "forward" in Matrix. Re-send content with sender attribution in body.
6. **Sticker packs** — no standardized sticker pack format. `m.sticker` events exist but pack management varies by client.
7. **Presence** — some homeservers disable presence for performance (Synapse does by default on large instances). May return errors.
8. **Rate limits** — homeservers enforce rate limits. mautrix handles retry with `M_LIMIT_EXCEEDED` errors (includes `retry_after_ms`).
9. **Room versions** — currently v1-v11. Default is v10-v11 on modern servers. Affects event auth rules.
10. **Media auth** — v1.11+ requires authenticated media endpoints. mautrix handles this transparently.
