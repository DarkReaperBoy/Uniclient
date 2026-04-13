# Bale — Full Protocol Surface Checklist

**Last updated:** 2026-04-13 (Steps 4-6)
**Current:** 368 methods, ~6,200 lines. Bot API (tapi.bale.ai) + User API (gRPC-Web/WebSocket).
**Confirmed working:** 105 extended + 55 Core (all pass, Step 2). 23 new methods added (Step 4), not yet tested.
**Steps 5-6:** Auth guards, unified dispatch, capability constants, 7 new Core methods.
**Remaining:** 0 methods — 100% protocol coverage.

All methods implemented. Bot API coverage is 100% of official docs.bale.ai. User API covers all known gRPC services.

---

## Step 4 — Newly Implemented (23 methods) — NEEDS TESTING

### Bot API Commands (3)
- [x] SetMyCommands — Set bot command list
- [x] DeleteMyCommands — Delete bot command list
- [x] GetMyCommands — Get current bot commands

### Auth Sessions (2, user mode)
- [x] GetAuthSessions — `bale.auth.v1.Auth/GetAuthSessions` — Real session list (Core GetSessions() now delegates here)
- [x] TerminateSessionReal — `bale.auth.v1.Auth/TerminateSession` — Real termination (Core TerminateSession() now delegates here)

### Folders (2, user mode)
- [x] LoadFolders — `bale.messaging.v2.Messaging/LoadFolders` — Load dialog folders
- [x] CreateFolderReal — `bale.messaging.v2.Messaging/CreateFolder` — Real folder creation (Core CreateFolder() now delegates here)

### Users (1, user mode)
- [x] GetFullUser — `bale.users.v1.Users/GetFullUser` — Single user profile

### Dialogs (1, user mode)
- [x] LoadDialogsFiltered — `bale.messaging.v2.Messaging/LoadDialogs` with folder/archive/mute filters

### Push Config (1, user mode)
- [x] PushSetConfig — `ai.bale.pushak.Push/SetConfig` — Push notification settings

### Chat Management (5, user mode)
- [x] MarkAsUnread — `bale.messaging.v2.Messaging/MarkDialogAsUnread`
- [x] MuteChat — `bale.messaging.v2.Messaging/MuteDialog` (mute=true)
- [x] UnmuteChat — `bale.messaging.v2.Messaging/MuteDialog` (mute=false)
- [x] ArchiveChat — `bale.messaging.v2.Messaging/ArchiveDialog`
- [x] UnarchiveChat — `bale.messaging.v2.Messaging/UnarchiveDialog`

### Message Features (3, user mode)
- [x] SendScheduledMessage — Messaging/SendMessage with schedule_date field 7
- [x] SendProtectedMessage — MessageContent field 27 (ProtectedMessage)
- [x] SendLongTextMessage — MessageContent field 30 (LongTextMessage)

### Exotic Content Types (5, user mode)
- [x] SendBankMessage — MessageContent field 1 (BankMessage)
- [x] SendJsonMessage — MessageContent field 7 (JsonMessage)
- [x] SendOrderMessage — MessageContent field 9 (OrderMessage)
- [x] SendAnimatedSticker — MessageContent field 24 (AnimatedStickerMessage)
- [x] SendLiveMessage — MessageContent field 26 (LiveMessage)
