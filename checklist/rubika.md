# Rubika — Full Protocol Surface Checklist

**Last updated:** 2026-04-13 (Step 3)
**Current:** 270 methods, ~4,808 lines. REST/WebSocket API + Bot API + Rubino social layer.
**Confirmed working:** 89 tests ALL PASS (including WebRTC voice chat, Step 1/2).
**Remaining:** ~45 methods listed below.

Only methods NOT yet implemented are listed.

---

## User API — Auth / Device (2 methods)

- [ ] RegisterDevice — Register device with Rubika (token, lang_code, app_version, device_model, device_hash)
- [ ] LoginDisableTwoStep — Bypass 2FA when password forgotten (phone + phone_code_hash)

## User API — Messages (2 methods)

- [ ] SearchGlobalMessages — Search messages across all chats (distinct from per-chat SearchChatMessages)
- [ ] ClickMessageUrl — Track/report URL click within a message (link analytics)

## User API — Chat Management (3 methods)

- [ ] GetChatAds — Retrieve advertisement messages in chats
- [ ] SetPrivacySetting — Set individual privacy settings (granular control)
- [ ] GetChatInfoByUsername — Resolve chat by username and return full info

## User API — Settings / Folders (1 method)

- [ ] EditFolder — Edit existing folder properties (name, included chats, excluded types)

## User API — Users (1 method)

- [ ] GetUserInfo — Get detailed user info by user_guid (raw API method)

## User API — Groups (4 methods)

- [ ] RemoveGroupAdmin — Explicitly remove admin status (separate from SetGroupAdmin access list)
- [ ] DeleteGroupAvatar — Delete group avatar specifically
- [ ] GetNewGroupLink — Reset and generate new group invite link
- [ ] GetGroupMemberCount — Lightweight member count (without fetching all members)

## User API — Contacts (2 methods)

- [ ] ImportContacts — Bulk import contacts from phone address book
- [ ] SearchContacts — Search within user's contact list by name/phone

## User API — Typed Media Senders (7 methods)

High-level helpers that handle requestSendFile + upload + sendMessage in one call:

- [ ] SendPhoto — Dedicated photo sending (Image type)
- [ ] SendVideo — Dedicated video sending (Video type)
- [ ] SendGif — Dedicated GIF sending (Gif type)
- [ ] SendMusic — Dedicated audio/music sending (Music type)
- [ ] SendVoice — Dedicated voice message sending (Voice type)
- [ ] SendDocument — Dedicated document sending (File type, no thumbnail)
- [ ] SendVideoMessage — Dedicated video note/round video (VideoMessage type)

## Rubino — Missing Methods (6 methods)

- [ ] RubinoGetProfilePosts — Get posts from a specific profile
- [ ] RubinoRemovePage — Delete a Rubino page entirely
- [ ] RubinoBookmarkPost — Bookmark/unbookmark a post
- [ ] RubinoUploadFile — High-level file upload with chunking and progress
- [ ] RubinoAddPicture — Convenience: upload + addPost with picture type
- [ ] RubinoAddVideo — Convenience: upload + addPost with video type

## Bot API — Missing Methods (10 methods)

- [ ] BotSendSticker — Send sticker via bot API
- [ ] BotSendImage — Send image via bot API (distinct from generic BotSendFile)
- [ ] BotSendDocument — Send document via bot API
- [ ] BotSendVoice — Send voice message via bot API
- [ ] BotSendVideo — Send video via bot API
- [ ] BotSendGif — Send GIF via bot API
- [ ] BotSendMusic — Send audio/music via bot API
- [ ] BotCheckJoin — Check if user joined a channel/group (forced-join verification)
- [ ] BotRemoveKeypad — Remove chat keypad from conversation
- [ ] BotReplyMessage — Reply to specific message (with reply_to_message_id)

## WebSocket Events — Missing Handlers (4 event types)

- [ ] OnChatUpdates — Separate handler for chat list changes
- [ ] OnShowActivities — Handler for typing/recording activity
- [ ] OnShowNotifications — Handler for notification events
- [ ] OnRemoveNotifications — Handler for notification dismissal
