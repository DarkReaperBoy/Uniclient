# Telegram Development Notes

Things discovered during implementation that aren't obvious from docs. See also: `research/tgcalls_protocol.md` for the full call protocol spec.

## Bot Mode Limitations
<!-- Discovered 2026-04-05 -->

- Bots **cannot** use `messages.getHistory` or `messages.getDialogs` — returns `BOT_METHOD_INVALID`. These are user-mode only methods. Bots must use the Bot API equivalents or different MTProto methods.
- Bots also **cannot** use `messages.search` — same BOT_METHOD_INVALID.
- Bots **CAN** use `channels.getMessages` to fetch specific messages by ID in groups/channels. But this requires knowing the message IDs upfront (e.g., from updates). It's not a history browsing method.
- Privacy mode on/off makes NO difference — the MTProto method restrictions apply regardless.
- Bots CAN: send/edit/delete messages, reply, forward, upload files (as document/photo/video/audio), use inline keyboards, receive updates via the update dispatcher.
- Bots CAN delete messages in DMs, groups, and channels (requires admin + "Delete Messages" permission for groups/channels).

## Complete Bot Capabilities Tested
<!-- Discovered 2026-04-05 -->

Verified working via real integration tests (20/20 pass):
- Auth with real token / reject bad token
- Send text to DM, group, channel
- Edit messages
- Delete messages in DM, group, channel (channel uses `channels.deleteMessages`)
- Reply to messages (creates reply thread)
- Forward messages between chats
- Upload file as document (shows as downloadable file)
- Upload image as photo (shows inline preview, NOT as file) — use `message.UploadedPhoto()`
- Upload audio (shows audio player) — use `.Audio()`
- Send inline keyboard with callback buttons and URL buttons
- Receive real-time updates via dispatcher
- Logout and verify session invalidation
- NOT possible: getHistory, getDialogs, search (all BOT_METHOD_INVALID)

## Channel/Supergroup Access Hash
<!-- Discovered 2026-04-05 -->

- `InputPeerChannel` requires `AccessHash` in addition to `ChannelID`. Without it you get `CHANNEL_INVALID`.
- For bots: resolve via `channels.getChannels` with `InputChannel{ChannelID}` to get the access hash from the returned `Channel` object.
- Numeric channel IDs in the `-100xxxx` format: strip the `-100` prefix to get the raw `ChannelID`, then resolve the access hash.

## FLOOD_WAIT
<!-- Discovered 2026-04-05 -->

- Authenticating too many times in rapid succession triggers `FLOOD_WAIT` (we got 3385 seconds / ~56 minutes).
- **Mitigation**: use `telegram.FileSessionStorage` to persist sessions to disk. After first auth, subsequent runs reuse the session and don't trigger re-auth.
- In tests: share a single authenticated session across all test functions via `sync.Once`.

## gotd/td API Patterns
<!-- Discovered 2026-04-05 -->

- `tg.Message.FwdFrom` and `tg.Message.Reactions` are **value types**, not pointers. Use `msg.GetFwdFrom()` / `msg.GetReactions()` which return `(value, ok bool)`.
- `DialogFilter.Title` is `TextWithEntities`, not `string`. Access via `.Title.Text`.
- `MessagesCreateChat` returns `*MessagesInvitedUsers`, not `UpdatesClass`. The `Updates` are inside `.Updates` field.
- `ContactsResolveUsername` takes a `*ContactsResolveUsernameRequest` struct, not a bare string.
- `MessagesEditMessage.Message` field is `string`, not `*string`.
- Forum topics: use `MessagesCreateForumTopic` (not `ChannelsCreateForumTopic`).
- `ReactionCount.Chosen` doesn't exist — use `ChosenOrder > 0` to check if the user reacted.
- `sender.To()` takes `InputPeerClass`, not `PeerClass`. Must convert via `toInputPeer()`.
- `sender.Reply(id).Text()` and `sender.Text()` return `(UpdatesClass, error)`, not `(*Updates, error)`.

## Deleting Messages in Channels/Supergroups
<!-- Discovered 2026-04-05 -->

- `messages.deleteMessages` does NOT work for channels/supergroups — it silently succeeds but the message stays.
- Must use `channels.deleteMessages` with `InputChannel{ChannelID, AccessHash}` for any chat with `-100xxxx` ID format.
- Bot must be admin with "Delete Messages" permission in the group/channel.

## Sending Media with Inline Preview
<!-- Discovered 2026-04-05 -->

- Sending everything as `UploadedDocument` makes it show as a downloadable file in Telegram — no preview, no inline player.
- **Photos**: use `message.UploadedPhoto(upload)` → shows as inline image with preview.
- **Video**: use `message.UploadedDocument(upload).MIME("video/mp4").Video()` → shows with video player.
- **Audio**: use `message.UploadedDocument(upload).MIME("audio/...").Audio()` → shows with audio player.
- **Voice**: use `.Voice()` instead of `.Audio()` for voice messages (shows waveform).
- Detection should be based on MIME type prefix: `image/*` → photo, `video/*` → video, `audio/*` → audio.

## Bot Admin Operations — Full Matrix
<!-- Discovered 2026-04-05 -->

- `ChannelsEditBanned` works for kick/ban/restrict. Bot needs "Ban Users" admin right.
- `ChannelsInviteToChannel` = BOT_METHOD_INVALID. Bots cannot re-invite users. User must rejoin manually.
- `ChannelsEditAdmin` (promote/demote) requires bot to have "Add New Admins" admin right specifically. Without it: CHAT_ADMIN_REQUIRED.
- Promote target must be a group member (not kicked). Promoting a non-member: USER_NOT_MUTUAL_CONTACT.
- `ChannelsEditTitle` and `MessagesEditChatAbout` work for setting group title/about.
- `MessagesEditChatDefaultBannedRights` works — can set default permissions for all members (e.g., disable stickers/gifs).

Admin features that are BOT_METHOD_INVALID (user-mode only):
- `ChannelsToggleSlowMode` — set slow mode
- `ChannelsGetAdminLog` — view admin action log
- `ChannelsDeleteParticipantHistory` — delete all messages from a user
- `ChannelsToggleAntiSpam` — toggle Telegram's anti-spam
- `ChannelsToggleSignatures` — toggle post signatures in channels

## Bot Update Reception
<!-- Discovered 2026-04-05 -->

- Bots receive updates via the `tg.UpdateDispatcher.OnNewMessage` handler.
- `FromID` field in received messages may be `nil` on MTProto bot updates — the message content is still correct.
- Commands (messages starting with `/`) are received as normal messages. Bot must parse them.
- Callback queries arrive via `OnBotCallbackQuery` handler. Answer with `MessagesSetBotCallbackAnswer`.
- `msg.Out` flag distinguishes bot's own outgoing messages from incoming user messages.

## User Mode — API Quirks
<!-- Discovered 2026-04-05 -->

### Peer Access Hashes (CRITICAL)
- In user mode, ALL peers require access hashes (unlike bot mode where some work without).
- Must maintain a cache of `userID→accessHash` and `channelID→accessHash`.
- Cache populated from: `MessagesGetDialogs`, `ContactsResolveUsername`, `ContactsGetContacts`, `ChannelsGetParticipants`, `ChannelsGetFullChannel`, and all results that include `Users`/`Chats` arrays.
- Without access hash: `PEER_ID_INVALID` for users, `CHANNEL_INVALID` for channels.
- File access hashes also needed for downloads: `fileID→(accessHash, fileReference)`.

### Channel vs Chat Methods
- Supergroups (IDs starting with `-100`) use `channels.*` methods (readHistory, deleteMessages, etc.)
- Regular groups (negative IDs without `-100` prefix) use `messages.*` methods.
- `MessagesReadHistory` → `PEER_ID_INVALID` on supergroups. Must use `ChannelsReadHistory`.
- `ChannelsToggleSlowMode`, `ChannelsGetAdminLog`, `ChannelsToggleSignatures` — work only on supergroups/channels.

### Interactive Auth Flow
- User mode auth is multi-step: Phone → OTP → optional 2FA.
- gotd/td's `auth.IfNecessary` calls `Code()` and `Password()` callbacks.
- Channel-based approach works: `Code()` blocks on a channel, caller sends OTP via `ProvideAuthCode()`.
- `AUTH_RESTART` error means the session is corrupted from failed auth. Delete session file and retry.
- Session file MUST be persisted (FileSessionStorage). Without it, every reconnect triggers new OTP → FLOOD_WAIT.
- Interactive auth timeout must be long (5+ minutes) to allow human OTP entry.

### FLOOD_WAIT Patterns
- `ChannelsEditTitle`, `MessagesSetChatAvailableReactions`, `MessagesSetChatTheme` — very aggressive rate limits (~800s FLOOD_WAIT after 2-3 calls).
- `ChannelsCreateChannel` — 5-6s FLOOD_WAIT between creations.
- `MessagesSetHistoryTTL` — same aggressive rate limit after toggling.
- Session reuse (FileSessionStorage) is essential to avoid auth FLOOD_WAIT.

### Platform-Specific Errors
- `DISCUSSION_CHAT_REQUIRED` — ToggleJoinToSend needs a linked discussion group.
- `PARTICIPANTS_TOO_FEW` — ToggleParticipantsHidden needs larger group (100+ members).
- `CHANNEL_REQUIRED` — ChannelsUpdateColor needs a broadcast channel, not a supergroup.
- `CHANNEL_FORUM_MISSING` — CreateForumTopic needs forum mode enabled first (ChannelsToggleForum).
- `INVITE_REVOKED_MISSING` — Can't delete the primary invite link.
- `USER_IS_BOT` — Bots can't send messages to other bots via MTProto.
- `FILTER_NOT_SUPPORTED` — SearchResultsCalendar doesn't accept InputMessagesFilterEmpty.

### Folder Name Limit
- Telegram limits dialog filter/folder names to 12 characters.
- Exceeding this returns `MESSAGE_TOO_LONG` (misleading error).

### User Mode Features Confirmed Working (182 methods implemented)
- Full message CRUD, reactions, pins, read state, typing, online count
- All media types: photo, video, audio, voice, document, sticker (upload + download)
- Polls: send, vote, get results
- Translate text, web page preview, search (in-chat + global + counters)
- Scheduled messages: send, list, delete, send now
- Drafts: save, clear, get all
- Chat invites: export, check, edit, get importers
- Channel/group: create, join, leave, get full info, participants, admin log
- Admin: promote/demote, restrict, slow mode, anti-spam, pre-history, banned rights
- Contacts: get, search, block/unblock, resolve username/phone, birthdays, close friends
- Profile: get full, update bio, status, photos, privacy, global privacy, account TTL, 2FA status
- Folders: get, create, delete, suggested
- Stickers: get set, send, fave/unfave, recent, featured, search
- Bot interaction: start bot, inline results, callback answer
- System: app config, DC config (19 DCs), nearest DC (4), countries (235), call config
- Stories: get all, get peer
- Updates: get difference (sync)
- Calls: request/discard 1:1 (voice+video), create/join/leave/discard/get group call, mute participant

## Telegram Call Protocol

See `research/tgcalls_protocol.md` for the full call protocol spec (signaling, encryption, V1/V2 formats, ICE, DTLS, group calls, all 10 protocol versions tested).

Key gotd/td-specific notes not in the protocol spec:

- `phone.requestCall` with a bot UserID returns `USER_ID_INVALID` — cannot call bots
- gotd/td's `FileStorage.Save` failing silently kills the MTProto engine — always verify session path resolves from `go test`'s working directory

## SMS Code Delivery & Device Spoofing
<!-- Discovered 2026-04-05 -->

Investigated spoofing as Android client (api_id 6) to force SMS code delivery instead of in-app.

### Findings
- `auth.sendCode` returns `AuthSentCodeTypeApp` (in-app) by default
- `auth.resendCode` can convert to `AuthSentCodeTypeSMS` on test DC
- On **production**, official mobile api_ids (6=Android, 8=iOS, 21724=TGX) trigger `RECAPTCHA_CHECK_signup__<sitekey>` error from new sessions
- The reCAPTCHA site key is bound to `my.telegram.org:443` domain and is actually for Firebase/SafetyNet attestation on real Android devices — cannot be solved from a Go client
- Third-party api_ids (94575=Nicegram, 2496=Webogram, 2040=TDesktop) don't trigger reCAPTCHA but also don't offer SMS fallback (`SEND_CODE_UNAVAILABLE` on resendCode, `NextType: null`)
- `CodeSettings.Token` field is for iOS Firebase push token, not reCAPTCHA

### Conclusion
SMS delivery spoofing is not viable from unofficial clients. Use normal auth (TDesktop api_id 2040), accept in-app code delivery.

## GetProfile("me")
<!-- Discovered 2026-04-05 -->

`GetProfile("me")` must use `InputUserSelf{}` instead of parsing "me" as int64 (which gives user ID 0). Fixed to check for "me"/"self" strings.

## Reactions Require Premium
<!-- Discovered 2026-04-05 -->

`MessagesSendReaction` in DMs returns `PREMIUM_ACCOUNT_REQUIRED` (error 403) on non-premium accounts. Works in groups where the group admin has enabled reactions. Gracefully handle by checking the error string.

## Call Testing Results

All call testing details (protocol versions, harness results, session findings) are in `research/tgcalls_protocol.md` §15–§20. Summary: 10 protocol versions tested, 59/59 tests pass (v2.7.7 through v13.0.0).
