# Bale — Full Protocol Surface Checklist

**Last updated:** 2026-04-13 (Step 3)
**Current:** 304 methods, ~5,813 lines. Bot API (tapi.bale.ai) + User API (gRPC-Web/WebSocket).
**Confirmed working:** 105 extended + 55 Core (all pass, Step 2).
**Remaining:** ~25 methods listed below.

Only methods NOT yet implemented are listed. Bot API coverage is 100% of official docs.bale.ai.

---

## Bot API — Confirmed Missing (3 methods)

These are confirmed working via PHP SDK (Bale-Bot-SDK):

- [ ] SetMyCommands — Set bot command list
- [ ] DeleteMyCommands — Delete bot command list
- [ ] GetMyCommands — Get current bot commands

## User API — Stubs to Implement (4 methods)

These methods exist as stubs returning nil/empty — need real gRPC implementation:

- [ ] GetAuthSessions — `bale.auth.v1.Auth/GetAuthSessions` — Real session list (current returns `[]Session{}`)
- [ ] TerminateSessionReal — `bale.auth.v1.Auth/TerminateSession` — Real single session termination (current is stub)
- [ ] LoadFoldersReal — `bale.users.v1.Users/LoadFolders` — Real folder loading (current returns nil)
- [ ] CreateFolderReal — `bale.users.v1.Users/CreateFolder` — Real folder creation (current returns nil)

## User API — Missing Methods (3 methods)

- [ ] GetFullUser — `bale.users.v1.Users/GetFullUser` — Load single full user profile (distinct from batch LoadFullUsers)
- [ ] LoadDialogsFiltered — `bale.messaging.v2.Messaging/LoadDialogs` with folder/archive/mute filters
- [ ] PushSetConfig — `ai.bale.pushak.Push/SetConfig` — Configure push notification settings

## Chat Management — Missing Features (5 methods)

- [ ] MarkAsUnread — Set dialog `markedAsUnread` field
- [ ] MuteChat — Set dialog `isMute` field
- [ ] UnmuteChat — Clear dialog `isMute` field
- [ ] ArchiveChat — Archive a chat
- [ ] UnarchiveChat — Unarchive a chat

## Message Features — Missing (5 methods)

- [ ] SendScheduledMessage — Schedule message for future delivery
- [ ] SendThreadReply — Reply to a thread/comment chain (`replyToTopId`)
- [ ] SendProtectedMessage — Self-destructing/view-once messages (MessageContent field 27)
- [ ] SendMediaAlbum — User-mode media album grouping (`groupedId` field 14)
- [ ] SendLongTextMessage — Messages exceeding normal text limit (field 30)

## Exotic Content Types — Low Priority (5 methods)

- [ ] SendBankMessage — Banking/payment content
- [ ] SendJsonMessage — JSON payload messages
- [ ] SendOrderMessage — Order-related content
- [ ] SendAnimatedSticker — TGS/Lottie animated stickers (user-mode)
- [ ] SendLiveMessage — Live stream content
