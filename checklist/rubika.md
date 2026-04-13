# Rubika — Full Protocol Surface Checklist

**Last updated:** 2026-04-13 (Step 4)
**Current:** 315 methods, ~5,500 lines. REST/WebSocket API + Bot API + Rubino social layer.
**Confirmed working:** 89 tests ALL PASS (including WebRTC voice chat, Step 1/2). 45 new methods added (Step 4), not yet tested.
**Remaining:** 0 methods — 100% protocol coverage.

All methods implemented. User API, Bot API, Rubino social, and WebSocket events fully covered.

---

## Step 4 — Newly Implemented (45 methods) — NEEDS TESTING

### Auth / Device (2)
- [x] RegisterDevice — Register device with Rubika
- [x] LoginDisableTwoStep — Bypass 2FA when password forgotten

### Messages (2)
- [x] SearchGlobalMessages — Search messages across all chats
- [x] ClickMessageUrl — Track URL click within a message

### Chat Management (3)
- [x] GetChatAds — Retrieve advertisement messages
- [x] SetPrivacySetting — Set individual privacy settings
- [x] GetChatInfoByUsername — Resolve chat by username

### Settings / Folders (1)
- [x] EditFolder — Edit existing folder properties

### Users (1)
- [x] GetUserInfo — Get detailed user info by GUID

### Groups (4)
- [x] RemoveGroupAdmin — Remove admin status
- [x] DeleteGroupAvatar — Delete group avatar
- [x] GetNewGroupLink — Reset and generate new invite link
- [x] GetGroupMemberCount — Lightweight member count

### Contacts (2)
- [x] ImportContacts — Bulk import from address book
- [x] SearchContacts — Search contact list

### Typed Media Senders (7)
- [x] SendPhoto — Upload + send photo (Image type)
- [x] SendVideo — Upload + send video (Video type)
- [x] SendGif — Upload + send GIF (Gif type)
- [x] SendMusic — Upload + send audio (Music type)
- [x] SendVoice — Upload + send voice (Voice type)
- [x] SendDocument — Upload + send document (File type)
- [x] SendVideoMessage — Upload + send video note (VideoMessage type)

### Rubino (6)
- [x] RubinoGetProfilePosts — Get posts from specific profile
- [x] RubinoRemovePage — Delete a Rubino page
- [x] RubinoBookmarkPost — Bookmark/unbookmark a post
- [x] RubinoUploadFile — File upload with chunking
- [x] RubinoAddPicture — Upload + addPost with picture type
- [x] RubinoAddVideo — Upload + addPost with video type

### Bot API (10)
- [x] BotSendSticker — Send sticker via bot API
- [x] BotSendImage — Send image via bot API
- [x] BotSendDocument — Send document via bot API
- [x] BotSendVoice — Send voice via bot API
- [x] BotSendVideo — Send video via bot API
- [x] BotSendGif — Send GIF via bot API
- [x] BotSendMusic — Send music via bot API
- [x] BotCheckJoin — Check if user joined channel/group
- [x] BotRemoveKeypad — Remove chat keypad
- [x] BotReplyMessage — Reply to specific message

### WebSocket Events (4)
- [x] OnChatUpdates — Handler for chat list changes
- [x] OnShowActivities — Handler for typing/recording activity
- [x] OnShowNotifications — Handler for notification events
- [x] OnRemoveNotifications — Handler for notification dismissal
