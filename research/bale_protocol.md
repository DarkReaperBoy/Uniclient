# Bale Protocol Research

<!-- Last updated: 2026-04-06 -->

## Overview

Bale has **two distinct APIs**:
1. **Bot API** — Telegram Bot API clone over HTTP REST (`tapi.bale.ai`)
2. **User/Internal API** — gRPC-Web with Protobuf over WebSocket/HTTP (`next-ws.bale.ai`)

---

## Bot API

<!-- Discovered 2026-04-05, enriched 2026-04-06 with official docs -->

### Base URL

- API: `https://tapi.bale.ai/bot{token}/METHOD_NAME`
- File download: `https://tapi.bale.ai/file/bot{token}/{file_path}`
- Short URL: `https://ble.ir` (for deep links)
- Official docs: https://docs.bale.ai/ (Persian)
- Bot creation via `@BotFather` inside Bale (same flow as Telegram)

### Network / DNS Fallback

<!-- Discovered 2026-04-06 via HackerTarget host search + CNAME analysis -->

ArvanCloud CDN (NS: `k.ns.arvancdn.ir`) resolves **all** `*.bale.ai` to `2.189.68.110`.
This IP may be blocked on restricted/intranet networks. The origin server IPs (pre-CDN) are:

| Domain | Purpose | CDN IP | Origin IP | Source |
|--------|---------|--------|-----------|--------|
| `tapi.bale.ai` | Bot API | 2.189.68.110 | **2.189.68.126** | CNAME → `gateway.bh.bale.ai` |
| `next-ws.bale.ai` | User WebSocket | 2.189.68.110 | **2.189.68.126** | Same as `next.bale.ai` |
| `next-api.bale.ai` | User HTTP API | 2.189.68.110 | **2.189.68.118** | HackerTarget |
| `web.bale.ai` | Web client | 2.189.68.110 | **2.189.68.126** | HackerTarget |
| `api.bale.ai` | General API | 2.189.68.110 | **2.189.68.126** | HackerTarget |
| `bale.ai` | Main site | 2.189.68.110 | **2.189.68.126** | HackerTarget |
| `meet-gw.bale.ai` | Call gateway | 2.189.68.110 | **2.189.68.115** | DNS direct |
| `meet-gw3.bale.ai` | Call gateway 3 | 2.189.68.110 | **2.189.68.115** | DNS direct |
| `siloo.bale.ai` | File/media CDN | 2.189.68.110 | **2.189.68.94** | DNS direct |
| `mail.bale.ai` | Email (MX) | — | **185.88.153.138** | MX record |

All origin IPs are in AS48159 (TIC — Telecommunication Infrastructure Company, Tehran).
ArvanCloud is AS208006 — they only handle DNS, not reverse proxy, for Bale.

**Implementation**: `bale.go` uses a custom `DialContext` that tries DNS first, then
falls back to origin IPs automatically. See `baleFallbackIPs` and `newBaleHTTPClient()`.

### Key Facts

- **Near-identical to Telegram Bot API** — same method names, same JSON payloads, same update model.
- Confirmed by Go fork `GhiaC/bale-bot-api` (literally Telegram bot API with URL changed).
- Both GET and POST methods supported, case-insensitive method names.
- Four parameter encoding methods: URL query string, `application/x-www-form-urlencoded`, `application/json` (except file upload), `multipart/form-data` (for files).
- All requests must be UTF-8 encoded.
- Response: JSON with `ok` (bool), `result` (on success), `error_code` + `description` (on failure).
- Optional `parameters.retry_after` field for rate limit handling.

### File Size Limits

| Type | Upload Method | Max Size |
|------|--------------|----------|
| Photos via URL | HTTP URL | 5 MB |
| Photos via multipart | multipart/form-data | 10 MB |
| Other files via URL | HTTP URL | 20 MB |
| Other files via multipart | multipart/form-data | 50 MB |
| Bot download (getFile) | GET | 20 MB |

- File sending: 3 methods — `file_id` reuse (no limit), HTTP URL, multipart upload.
- Cannot change file type when resending via `file_id` (video stays video, photo stays photo).
- Thumbnails cannot be reused via `file_id`.
- Sending by URL requires correct MIME type. `sendDocument` via URL only works for GIF, PDF, ZIP.
- `sendVoice` via URL: must be `audio/ogg`, max 1 MB. Voice 1-20 MB sent as document.

### Webhook

- Supported ports: **443, 88** only.
- `setWebhook` — set URL for incoming updates via HTTPS POST.
- `deleteWebhook` — disable webhook, return to getUpdates.
- `getWebhookInfo` — check current webhook status.

### Update Storage

- Last 2000 messages stored for 24 hours on server until fetched.
- Updates delivered as JSON `Update` objects via getUpdates or webhook.
- Each Update has at most one of: `message`, `edited_message`, `callback_query`, `pre_checkout_query`.

### Available Methods (Bot API)

#### Core
- `getMe` — verify token, get bot info (returns `User`)
- `sendChatAction` — show typing indicator (typing, upload_photo, record_video, upload_video, record_voice, upload_voice, choose_sticker)

#### Messages
- `sendMessage` — send text (1-4096 chars), supports `reply_to_message_id` and `reply_markup`
- `forwardMessage` — forward any message type
- `copyMessage` — copy without forward header (returns `MessageId`)
- `editMessageText` — edit text content
- `editMessageCaption` — edit media caption
- `editMessageReplyMarkup` — edit inline keyboard only
- `deleteMessage` — delete within 48h, bot must be admin for others' messages

#### Media
- `sendPhoto` — photo (InputFile or file_id or URL), caption 0-4096 chars
- `sendAudio` — MP3/M4A, up to 50 MB, displayed in music player
- `sendDocument` — any file, up to 50 MB
- `sendVideo` — MPEG4 video, up to 50 MB
- `sendAnimation` — GIF/H.264 without audio, up to 50 MB
- `sendVoice` — voice message, up to 50 MB
- `sendMediaGroup` — album of photos/videos/docs/audio
- `sendLocation` — map point (lat/lon, optional horizontal_accuracy 0-1500m)
- `sendContact` — phone contact
- `sendSticker` — sticker (file_id)
- `getFile` — get file info + download path (valid 1 hour)

#### Chat Management
- `getChat` — full chat info (`ChatFullInfo`: id, type, title, photo, bio, description, invite_link, linked_chat_id)
- `getChatAdministrators` — list of `ChatMember` admins
- `getChatMembersCount` — integer member count
- `getChatMember` — single member info (bot must be admin)
- `banChatMember` — block user (bot must be admin)
- `unbanChatMember` — unblock user, optional `only_if_banned`
- `promoteChatMember` — promote/demote admin (can_change_info, can_post_messages, can_edit_messages, can_delete_messages, can_manage_video_chats, can_invite_users, can_restrict_members, can_promote_members, can_post_stories, can_pin_messages)
- `setChatTitle` — change title (not for private chats)
- `setChatDescription` — change description
- `setChatPhoto` — set new photo (multipart upload)
- `deleteChatPhoto` — remove photo
- `leaveChat` — bot leaves

#### Invite Links
- `createChatInviteLink` — create new invite link
- `revokeChatInviteLink` — revoke and regenerate
- `exportChatInviteLink` — export (create if none, revoke if exists)

#### Pins
- `pinChatMessage` — pin message (bot needs `can_pin_messages`)
- `unPinChatMessage` — unpin specific message
- `unpinAllChatMessages` — unpin all

#### Inline Keyboards & Callbacks
- `answerCallbackQuery` — respond to inline button press (0-200 chars text, optional `show_alert`)
  - **Quirk (since Khordad 1404/June 2025)**: if `callback_query_id` starts with `1`, user has old client without callback support — send regular message instead.
  - Must be called even without text to release button loading state.

#### Stickers
- `uploadStickerFile` — upload .WEBP/.PNG/.TGS/.WEBM sticker file
- `createNewStickerSet` — create set (1-50 stickers, name ends with `_by_<bot_username>`)
- `addStickerToSet` — add sticker (max: 200 emoji, 50 video, 120 regular)

#### Payments (Wallet-based)
- `sendInvoice` — send payment request (title 1-32 chars, description 1-255, prices in IRR)
- `createInvoiceLink` — create payment ID for mini-apps
- `answerPreCheckoutQuery` — approve/reject payment (must respond within 10s)
- `inquireTransaction` — query transaction status (pending/paid/failed/rejected)
- **Test token**: `WALLET-TEST-1111111111111111` (no real money transfer)
- **Provider token**: obtained from `@BotFather`
- Card-to-card payments removed — wallet only now.

#### Reviews
- `askReview` — request user review (since Aban 1404/Nov 2025, needs new client)
  - `user_id` + `delay_seconds`, server may suppress based on conditions
  - Not in standard Telegram bot libraries — direct HTTP call required

### Chat Types

- `private` — 1:1 DM
- `group` — group chat
- `channel` — broadcast channel

### Message Formatting (Markdown)

Bale uses Markdown for all messages:
- `*bold*` — requires spaces before/after the asterisks
- `_italic_` — requires spaces before/after underscores
- `[text](url)` — inline links
- `` ```[text]description``` `` — "instant view" / expandable descriptions

### Known Differences from Telegram Bot API

<!-- Discovered 2026-04-06 -->

1. Base URL: `tapi.bale.ai` not `api.telegram.org`
2. File download URL: `tapi.bale.ai/file/bot{token}/{file_path}`
3. Webhook ports: only **443 and 88** (Telegram supports 443, 80, 88, 8443)
4. MessageEntity types: only `mention` and `bot_command` (Telegram has many more)
5. Chat types: no `supergroup` type — only `private`, `group`, `channel`
6. No inline mode (`answerInlineQuery` not documented)
7. `answerCallbackQuery` — new feature, old clients (ID starts with `1`) don't support it
8. Wallet payments system instead of Telegram's Stripe-based payments
9. `askReview` and `inquireTransaction` are Bale-specific methods not in Telegram
10. `ChatMemberRestricted` — only in supergroups, granular send permissions
11. Markdown formatting requires spaces around bold/italic markers

---

## User/Internal API (gRPC-Web / Protobuf)

<!-- Discovered 2026-04-05 via aiobale, enriched 2026-04-06 via Balethon -->

### Endpoints

| Purpose | URL |
|---------|-----|
| WebSocket (real-time) | `wss://next-ws.bale.ai/ws/` |
| HTTP (single requests) | `https://next-ws.bale.ai` |
| File upload | Dynamic URL from `GetNasimFileUploadUrl` response |
| Web client origin | `https://web.bale.ai` |

### Protocol

- **gRPC-Web** with custom Protobuf serialization (not standard gRPC)
- Binary frames: 5-byte header `[compressed_flag(1)] + [length(4 big-endian)]` + payload
- Response includes `grpc-status` trailer that must be stripped before decoding
- Each request gets auto-incrementing `index` for response correlation
- Request ID (RID): random 16-digit number per message-level operation
- Timeout: 20 seconds default per request

### Session Metadata (sent with every request)

| Field | Value |
|-------|-------|
| `app_version` | `113466` (aiobale) / `86550` (Balethon) |
| `browser_type` | `1` |
| `browser_version` | `3471765337684194354` |
| `os_type` | `3` |
| `session_id` | Unix timestamp (milliseconds) |

### Token Detection (Balethon)

- Token length > 100 chars → WebSocket/UserBot mode
- Token length ≤ 100 chars → HTTP Bot API mode

### Authentication Flow

**Stage 1: StartPhoneAuth**
- Service: `bale.auth.v1.Auth`
- Request: `phone_number` (int), `app_id`, `app_key`, `device_hash`, `device_title`, `send_code_type`
- Response: `transaction_hash`, `is_registered`, `sent_code_type`, `code_expiration_date` (ms), `code_timeout` (s)
- Send code types: DEFAULT=1, SMS=3, CALL=4, EMAIL=5, MISSCALL=6, WHATSAPP=8, TELEGRAM=9, USSD=10

**Stage 2: ValidateCode**
- Service: `bale.auth.v1.Auth`
- Request: `transaction_hash`, `code` (OTP), `is_jwt: {"1": 1}`
- Response: JWT token on success, or error enum

**Stage 3: ValidatePassword (if needed)**
- Required when account has 2FA enabled

**Auth Error Codes:**
- 1=NUMBER_BANNED, 2=AUTH_LIMIT, 3=WRONG_CODE, 4=PASSWORD_NEEDED
- 5=SIGN_UP_NEEDED, 6=WRONG_PASSWORD, 7=RATE_LIMIT, 8=INVALID

### Services (56 Total — ~646 Methods)

<!-- Updated 2026-04-13 from web.bale.ai v4.17.0+151668 JS scrape -->
<!-- All services use gRPC-over-WebSocket except Auth which uses grpc-web HTTP -->

#### Core Services (implemented)
| Service | gRPC Service Name | Methods |
|---------|------------------|---------|
| Auth (26) | `bale.auth.v1.Auth` | StartPhoneAuth, ValidateCode, ValidatePassword, SignUp, SignOut, LogOut, GetAuthSessions, TerminateSession, TerminateAllSessions, DeleteAccount, ChangePhone, SendDeleteAccountVerificationCode, SendChangePhoneVerificationCode, GetUserIdToken, GetTicket, GetBajeBamTicket, GetBaleTicket, GetJWTToken, EnableTwoFactorAuthentication, IsTwoFactorAuthenticationEnabled, VerifyEmail, RecoverPassword, VerifyPasswordRecovery, SetNewPassword, VerifyPassword, DisableTwoFactorAuthentication |
| Messaging (43) | `bale.messaging.v2.Messaging` | SendMessage, SendMultiMediaMessage, UpdateMessage, DeleteMessage, ForwardMessages, ClearChat, DeleteChat, LoadDialogs, LoadFolderDialogs, LoadGroupedDialogs, LoadPeerDialogs, LoadPeers, LoadHistory, LoadPinnedDialogs, LoadPinnedMessages, LoadReplies, LoadFolders, CreateFolder, EditFolder, DeleteFolder, ReorderFolders, CreateReservedFolder, ArchiveDialogs, UnArchiveDialogs, PinDialogs, UnpinDialogs, ReorderPinnedDialogs, PinMessage, UnPinMessages, MarkDialogsAsRead, MarkDialogsAsUnread, MentionRead, MessageRead, MessageReceived, FetchProtectedMessage, GetMessagesRepliesInfo, GetDiscussionMessage, CreateThread, CreateTopic, EditTopic, GetTopics, GetTopicByID, DeleteTopic |
| Users (38) | `bale.users.v1.Users` | EditName, EditNickName, CheckNickName, EditAbout, EditSex, EditBirthDate, EditAvatar, RemoveAvatar, EditMyTimeZone, EditMyPreferredLanguages, EditUserLocalName, LoadFullUsers, GetFullUser, GetUsersDefaultCardNumber, LoadFullUsersSequentially, LoadAvatars, AddCard, BlockUser, UnblockUser, LoadBlockedUsers, NotifyAboutDeviceInfo, ChangeDefaultCardNumber, RemoveDefaultCardNumber, ImportContacts, GetContacts, RemoveContact, AddContact, SearchContacts, LoadUsers, GetUserPrivacyStatus, SetUserPrivacyStatus, GetUserFullPrivacy, ResetContacts, IsNameAllowed, ChangePhoneNumber, ConfirmPhoneNumber |
| Groups (48) | `bale.groups.v1.Groups` | LoadFullGroups, GetFullGroup, LoadMembers, GetMyGroups, LoadGroupAvatars, CreateGroup, InviteUsers, EditGroupTitle, EditGroupDefaultCardNumber, GetGroupDefaultCardNumber, EditGroupAvatar, RemoveGroupAvatar, EditGroupAbout, EditChannelNick, InviteUser, LeaveGroup, KickUser, MakeUserAdmin, RemoveUserAdmin, TransferOwnership, GetGroupInviteURL, RevokeInviteURL, JoinGroup, JoinPublicGroup, PinMessage, RemovePin, RemoveSinglePin, GetPins, SetCanSeeMessages, GetCanSeeMessages, GetMemberPermissions, SetMemberPermissions, SetGroupDefaultPermissions, SetRestriction, FetchGroupAdmins, LoadGroups, GetGroupMembersCount, SetAvailableReactions, GetMutualGroups, SetDiscussionGroup, RemoveDiscussionGroup, AddDiscussionGroupAdmin, UnBanUser, GetBannedUsers, SetCanSeeHistory, GetGroupPreview, GetGroupRecommendations, SetMemberCustomTitle |
| Meet (30) | `bale.meet.v1.Meet` | StartCall, DiscardCall, AcceptCall, ReceiveCall, GetCallState, GetCallLogs, DeleteCallLogs, InviteToCall, AskToJoinCall, AnswerCallJoinRequest, SendCallReaction, SubmitCallFeedback, StartGroupCall, JoinGroupCall, LeaveGroupCall, GetGroupCall, GetOngoingCalls, MuteParticipant, RemoveParticipant, StartRecording, StopRecording, StartStream, DeleteStream, UpdateLayout, GenerateCallLink, GetCallLinkDetails, SetLinkTitle, GetWssURL, SendFanoosEvent, TakeCallAction |
| Presence (11) | `bale.presence.v1.Presence` | GetContactsPresences, GetGroupMembersPresences, GetGroupOnlineCount, GetUsersPresence, SetOnline, StopTyping, Typing, SubscribeToOnline, SubscribeFromOnline, SubscribeToGroupOnline, SubscribeFromGroupOnline |
| Abacus (9) | `bale.abacus.v1.Abacus` | EnableShowReactionFlag, GetShowReactionFlag, GetMessageReactionsList, GetMessagesReactions, GetMessagesViews, LoadReactions, MessageReactionsRead, MessageSetReaction, MessageRemoveReaction |
| Files (6) | `ai.bale.server.Files` | GetNasimFileUploadUrl, GetNasimFileUrls, GetNasimFileUrl, GetNasimFileUploadResume, FileUploadCancel, GetNasimFilePublicUrl |
| Configs (3) | `bale.v1.Configs` | GetParameters, EditParameter, GetInAppUpdate |
| Push (6) | `ai.bale.pushak.Push` | RegisterPush, UnregisterPush, RegisterGooglePush, UnregisterGooglePush, UnregisterAllPushCredentials, SetConfig |
| Ramz (7) | `bale.ramz.v1.Ramz` | SetPassword, DeletePassword, SendOTP, ForgetPassword, ValidateOTP, CheckPasswordSet, CheckPassword |
| Report (2) | `bale.report.v1.Report` | ReportInappropriateContent, ReportDismiss |
| Fanoos (1) | `bale.fanoos.v1.fanoos` | Send |
| Feedback (1) | `bale.feedback.v1.FeedBack` | SendFeedBack |
| GiftPacket (3) | `bale.giftpacket.v1.GiftPacket` | SendGiftPacketWithWallet, OpenGiftPacket, GetGiftPacketPaymentToken |
| Magazine (9) | `bale.magazine.v1.Magazine` | UpvotePost, RevokeUpvotedPost, GetMyUpvotes, GetMessageUpvoters, LoadFeedMessages, LoadInternalFeedMessages, LoadCategoryFeedMessages, LoadCategories, GetSimilarPosts |
| Kifpool (32) | `bale.kifpool.v1.Kifpool` | GetMyKifpools, UpgradeKifpool, CreateKifpool, GetChargePaymentToken, VerifyCashOutKifpool, CashOut, Invoice, Transfer, CheckChargePermission, Charge, VerifyPurchaseMessage, PurchaseMessage, PurchaseMessageWithCharge, GetKifpoolOwner, GetKifpoolPointBalance, GetKifpoolPointSummery, GetKifpoolPointDetails, GetKifpoolTransactionPoint, Purchase, PurchaseWithCharge, GetCryptoChargePaymentToken, CryptoTransfer, GetCryptoWallets, CryptoCashOut, CryptoInvoice, CryptoPurchase, CryptoRefund, GetCredit, PayForMessage |

#### New Services (not yet implemented)
| Service | gRPC Service Name | Methods |
|---------|------------------|---------|
| Poll (5) | `bale.poll.v1.Poll` | CreatePoll, ClosePoll, Vote, GetPollResults, GetFullPollResult |
| Search (11) | `bale.search.v1.Search` | SearchMessages, SearchMessageMore, SearchPeer, SearchMedia, SearchMembers, SearchMarket, SearchProduct, SearchMarketPopular, SearchDialog, SearchContent, UpdateSearchContentClick |
| Story (23) | `bale.story.v1.Story` | AddStory, AddChannelStory, AddBotStory, CanAddBotStory, RemoveStory, GetViewers, GetViewersCount, GetStories, GetChannelStories, GetBotStories, ReactToStory, GetStoryById, GetUserPrivacyConfig, SetUserPrivacyConfig, GetDefaultStoryBackgrounds, GetMostPopularStories, GetStoryWidgets, GetUserStoryConfig, SetUserStoryConfig, GetStoriesByList, GetStoryReactionEmojis, GetStoryTags, CheckLinkValidity |
| Advertisement (108) | `bale.advertisement.v1.Advertisement` | (see checklist/bale.md for full list) |
| Charnet (11) | `bale.charnet.v1.CharnetService` | GetInternetBundlePaymentToken, GetInternetBundleList, GetRecentInternetBundleOrders, DeleteRecentInternetBundleOrder, GetRecentChargeOrders, DeleteRecentChargeOrder, BuyCharge, BuyInternetBundle, GetTopUpChargePaymentToken, GetVoucherChargePaymentToken, GetAvailableCharges |
| Sap (16) | `bale.sap.v1.Sap` | EnrollNewCard, ReactivateApp, GetCardInfo, GetDestinationCardInfo, DeliverOtp, TransferMoneyByCard, GetCards, RemoveCard, AddNewCards, EditCardExpirationDate, SetDefaultCard, GetDefaultCard, RemoveDefaultCard, GetDestinationCards, AddDestinationCards, RemoveDestinationCards |
| Bank (19) | `bale.bank.v1.Bank` | BuyFastCharge, GetCardRemain, GetCardTransferToken, GetOrganizationPaymentToken, GetOTPToken, GetOTPTokenV2, GetPaymentToken, GetPayMoneyRequestToken, GetPayvandCard, GetPayvandCardList, GetPSProxyPaymentToken, GetPSProxyToken, GetRecentCharges, GetRemainToken, GetSadadPSPPaymentToken, GetTokenInvoice, GrantBankiAccess, GetPreferences, EditPreference |
| Wallet (13) | `bale.wallet.v1.Wallet` | ActivateWallet, CashOutFromWallet, GetMoneyRequestPaymentTokenByCard, GetMyWallets, GetPaymentTokenByCard, GetWalletChargeToken, GetWalletContracts, GetWalletInvoice, PayByWallet, PayMoneyRequestByWallet, VerifyCashOut, VerifyPeer, VerifyQRCode |
| Premium (7) | `bale.premium.v1.Premium` | CalculateDiscountedPrice, GetBadges, GetPackages, IsPremium, IsPremiumBatch, PurchasePackage, SetUserBadge |
| AI (2) | `bale.turing.v1.AI` | SendEvent, GetTranscript |
| MessageStream (2) | `bale.message_stream.v1.MessageStream` | CancelMessageStream, ReceiveMessageStream |
| Timche (5) | `bale.timche.v1.Timche` | AskBotReviewCallback, GetBotPage, GetHomePage, GetSectionPage, SubmitReview |
| Scheduler (6) | `bale.schedule.v1.Scheduler` | ScheduleTask, UnScheduleTask, ListTasks, ExecuteTaskNow, ReScheduleTask, PeersWithScheduleTask |
| TLDR (2) | `bale.tldr.v1.TLDR` | GetLinkSummary, GetLinkPreview |
| AnonymousContact (1) | `bale.anonymous_contact.v1.AnonymousContact` | GetUserAnonymousContactPage |
| MavizStream (4) | `bale.maviz.v1.MavizStream` | SubscribeToUpdates, GetDifference, SubscribeToThreadUpdates, UnsubscribeFromThreadUpdates |
| Arbaeen (19) | `bale.arbaeen.v1.Arbaeen` | LoadArbaeenHistory, GetValidArbaeenBanks, VerifyUserArbaeenAuthority, VerifyUserArbaeenExtraInfo, GetListOfArbaeenDeliveryStations, GetArbaeenCurrenciesList, GetArbaeenCurrencyPrice, GetArbaeenPaymentToken, GetListOfBoxOffice, GetListOfBranches, GetListOfStates, UserHasAccess, CashPaymentCallback, GetAdminStationList, SendOTP, VerifyOTP, GetSuggestedGroups, GetRate, StartBot |
| Evex (8) | `bale.evex.v1.Evex` | LoadEvexHistory, GetValidBanks, VerifyUserEvexAuthority, VerifyUserEvexExtraInfo, GetListOfEvexDeliveryStations, GetEvexCurrenciesList, GetEvexCurrencyPrice, GetEvexPaymentToken |
| Exchange (10) | `bale.exchange.v1.Exchange` | LoadExchangeHistory, GetUserIcmsInfo, VerifyUserExchangeAuthority, GetListOfDeliveryStations, GetCurrenciesList, GetCurrencyPrice, GetExchangePaymentToken, GetExchangeOrderInfo, GetInitialConfig, GetTravelCurrencyOrderInDetail |
| Sarrafi (9) | `bale.sarrafi.v1.Sarrafi` | AuthenticateUser, GetTickers, GetWallet, GetDepth, GetSession, CreateOrder, GetOrders, GetOrder, GetChargeToken |
| BankAccountPreferences (3) | `bale.BankAccountPreferences.v1.BankAccountPreferences` | ActivateYaraMessaging, EditPreference, GetPreferences |
| Bill (7) | `bale.bill.v1.Bill` | InquiryBill, PayBill, GetBillHistory, CreateSavedBill, GetSavedBills, RenameSavedBill, DeleteSavedBills |
| Falake (1) | `bale.falake.v1.Falake` | GetLinkStatus |
| Negah (1) | `bale.negah.v1.Negah` | GetMessageSeenList |
| LLMAuth (1) | `bale.llm_auth.v1.LLMAuthService` | GetAuthToken |
| MyBank (1) | `bale.my_bank.v1.MyBank` | GetMyBank |
| Appzar (3) | `bale.appzar.v1.Appzar` | GetMiniAppUrl, GetMenuButton, InvokeCustomMethod |
| TopPeer (2) | `bale.top_peer.v1.TopPeer` | GetTopPeer, RemovePeer |
| Organizations (2) | `bale.organizations.v1.Organizations` | GetUserOrganizationalContacts, GetUserOrganizationInfo |
| PFM (15) | `bale.pfm.v1.Pfm` | GetUserAccounts, LoadTransactions, AddTransactionTags, RemoveTransactionTags, GetTransactionTags, AddUserTags, RemoveUserTags, GetUserTags, FilterTaggedTransactions, AddDetailToTransaction, RemoveTransaction, SplitTransaction, LoadTransactionsByIDs, GetSubTransactions, ReviveTransaction |
| MicroBanki (3) | `bale.microbanki.v1.MicroBanki` | GetMoneyRequestDetails, GetMoneyRequestPaymentList, GetBamServiceToken |
| CrowdFunding (2) | `bale.crowdfunding.v1.CrowdFunding` | GetParticipants, GetTotalPaidAmount |
| Recommender (4) | `bale.recommender.v1.Recommender` | GetChannelRecommendations, GetRelatedChannels, GetGroupsRecommendation, GetRelatedGroups |
| Ghasedak (2) | `bale.ghasedak.v1.GhasedakService` | GetRoutesStates, GetDiff |
| SharedMedia (2) | `bale.shared_media.v1.SharedMediaService` | LoadMedia, GetActiveSharedMedia |
| Market (26) | `bale.market.v1.Market` | GetStores, GetCategoriesList, GetYaldaStores, CreateTag, GetTags, CreateMarketJoinRequest, GetMarketJoinRequests, GetCategoryMarkets, GetCategoryProducts, SetOnboardingData, GetOnboardingStatus, GetIndexedProducts, GetNumberOfSales, GetTopMarkets, SubmitMarketFeedback, AcceptMarketJoinRequest, RejectMarketJoinRequest, GetMarketsPendingJoinRequest, GetMarket, UpdateMarketInfo, SetMarketBanners, GetPendingCampaignMarkets, AcceptCampaignMarket, RejectCampaignMarket, SetPopularSearches, SetGenericDeepLinks |
| Ketf/Bots (24) | `bale.v1.Images` / `bale.ketf.v1.Ketf` | AddGif, RemoveGif, UseGif, GetSavedGifs, AddStickerCollection, RemoveStickerCollection, AddStickerPack, RemoveStickerPack, LoadOwnStickers, LoadStickerCollection, SendInlineCallBackData, SendInlineCallback, SendAuthenticatedInlineCallBackData, SendMiniAppData, GetBotWhiteList, GetUserContext, GetWebappHash, GetBots, GetBotInfo, GetInlineBotResults, GetBotGroupPermissions, GetPaymentDetails, MakePayment, InvokeCustomAction |

### File Upload (User Mode)

1. Call `GetNasimFileUploadUrl` with: `expected_size`, `user_id`, `name`, `mime_type`, `chat`, `send_type`
2. Server returns `file_id`, `access_hash`, `upload_url` (presigned)
3. HTTP PUT to upload URL with file data
4. Reference file by `file_id` + `access_hash` in messages

### Real-Time Updates (User Mode)

WebSocket-based, 12 event types:
- `message` — new message
- `message_edited` — message edited
- `message_deleted` — message(s) deleted
- `message_sent` — outgoing message confirmation
- `chat_cleared` — chat emptied
- `chat_deleted` — chat removed
- `username_changed` / `about_changed` — profile updates
- `group_message_pinned` / `group_pin_removed` — pin events
- `user_blocked` / `user_unblocked` — block events

Ping keepalive: every 5 seconds.

### Peer Format

- User mode uses `Peer` structures with `type` and `id` fields
- Also supports `peer_id|peer_type` string format

### Warnings

- Internal API is sensitive to excessive gRPC calls
- Overuse may trigger rate limits or temporary bans
- Add delays between calls (1.5s minimum recommended)

---

## Open-Source References

### Bot Libraries

| Name | Language | GitHub | Status | Notes |
|---|---|---|---|---|
| **Balethon** | Python | Balethon/Balethon | Active (2025) | Most popular, async, bot + userbot via WebSocket |
| **python-bale-bot** | Python | python-bale-bot/python-bale-bot | Moderate | Async, good docs |
| **bale-bot-api** | Go | GhiaC/bale-bot-api | Inactive (2019) | Fork of go-telegram-bot-api — confirms API compat |
| **Bale-Bot-SDK** | PHP | ErfanVahabpour/Bale-Bot-SDK | Active (2025) | Laravel integration |

### User-Mode Libraries

| Name | Language | GitHub | Status | Notes |
|---|---|---|---|---|
| **aiobale** | Python | Enalite/aiobale | Active (2025) | **Only user-mode client** — full gRPC/Protobuf internals |

---

## Implementation Status in uniclient

### Bot Mode — IMPLEMENTED & TESTED 2026-04-06

17/17 methods verified against live API. Bot: `@agiskynetbot`.

Tested: auth, send/edit/delete/reply/forward/copy messages, pin/unpin (group), inline keyboards, stickers (multipart fix), location, contact, typing, getChat, profile, file upload+download (byte-identical), getUpdates long-poll, logout.

**Quirk**: Sticker file_ids contain colons which break JSON — must use `multipart/form-data` for `sendSticker`.

### User Mode — IMPLEMENTED & AUDITED 2026-04-06

195+ functions, 3600+ lines total. 82 RPC methods across 11 services.
All 28 Core-interface methods audited against aiobale source + live-tested with user verification.

**Infrastructure:**
- Custom protobuf wire format codec (varint, length-delimited, fixed64, fixed32)
- gRPC-Web framing (5-byte header: `[0x00][4-byte big-endian length]`, trailer stripping)
- WebSocket client (`coder/websocket`) with binary frames, auto-reconnect, 5s ping keepalive
- Request/response correlation via auto-incrementing index field
- DNS fallback with `DialTLSContext` (5s TCP+TLS probe, then fallback to origin IPs)

**Auth:**
- StartPhoneAuth: app_id=4, app_key=`C28D46DC4C3A7A26564BFCC48B929086A95C93C98E789A19847BEE8627DE4E7D` (from aiobale)
- StartPhoneAuth (field 9 = send_code_type, field 10 = options `{"0":1}` REQUIRED)
- ValidateCode (JWT wrapped in StringValue at field 4 → unwrap field 1)
- ValidatePassword (2FA), SignUp, SignOut

**Critical implementation notes (from deep review):**
- ALL timestamps in milliseconds (not seconds)
- Request ID is a simple counter (NOT random) — starts at 0, increments per request
- Message RID (temp ID) is random 16-digit number
- JWT token sent via `Cookie: access_token={JWT}` header on WebSocket connect
- Metadata must include both plain and `mt_`-prefixed versions of all fields
- Initial handshake after WS connect: `Request{field 3: {1:1, 2:1}}` (authorized+ready)
- LoadDialogs response field 3 may return single object OR list — must handle both
- Document name field (4) may come as nested dict or plain string — must handle both
- **Protobuf decode ambiguity**: wire type 2 (length-delimited) is shared between strings and embedded messages. Transaction hashes and other binary-looking strings get mis-decoded as nested messages. Fix: store raw bytes alongside decoded messages (`__raw_N` keys) and fall back to raw bytes in `pbGetString()`.
- **UpdateMessage**: peer + rid + message content; adding date field (4) may help; `UpdateMessageDenied` can occur if editing non-own messages or after time window
- **UnPinMessages**: field 2 is repeated OtherMessage `{1: dateMs, 2: msgRID}` (NOT a bool!), field 3 is all_messages flag
- **EditAbout**: payload must be wrapped in StringValue `{1: {1: text}}`, not plain string `{1: text}`
- **Peer types for DMs**: bots use peer type 1 (private), NOT type 4 (bot) — type 4 causes InvalidArgument
- **Recursive decode depth limit**: needed to prevent stack overflow on large payloads like GetParameters (huge config). Max depth = 8.
- **varint length sanity check**: payloads > 10MB should be rejected to prevent `makeslice: len out of range` panics
- SendMessage has no typed response — message ID arrives via ComposedUpdate (field 55)
- **LoadHistory loadMode**: 1=FORWARD (from oldest), 2=BACKWARD (from newest), 3=BOTH. Use mode=2 with `offset_date=time.Now().UnixMilli()` to get latest messages. Mode=1 with date=0 returns from the BEGINNING of history (NOT latest!).
- **Message IDs are `rid:dateMs:mid`**: Bale needs the rid (client random ID) AND date to identify messages. The `mid` (server sequential ID from SendMessage response field 1) is stored but rarely needed. Core interface stores IDs as `"rid:dateMs:mid"` string format, parsed by `parseMsgIDFull()`.
- **Core interface user-mode dispatch**: `SendMessage`, `GetMessages`, `ReactToMessage`, `MarkAsRead`, `CreateGroup` dispatch to user mode. `EditMessage`, `DeleteMessage`, `ForwardMessage`, `PinMessage`, `UnpinMessage` were FIXED to also dispatch (previously always used bot HTTP API even in user mode).
- **Reply requires date**: InfoMessage for reply_to needs `{1: Peer, 2: rid, 3: IntValue{1: dateMs}}`. Without field 3 (date), Bale defaults to first message in chat.
- **DeleteMessage requires all fields**: `{1: Peer, 2: [rids], 3: IntListValue{1: [dates]}, 4: IntValue{1: 0}}` — dates and just_me are REQUIRED per aiobale spec.

### SOLVED: Pin/Forward were broken due to peer type issue (2026-04-06)
- **Root cause (Forward)**: `parsePeerID("4695281546")` returned peer type 1 (private) for a group ID. Bale uses positive IDs for groups, unlike Telegram. Fix: pass group IDs as `"id|2"` format to specify peer type explicitly.
- **Root cause (Pin)**: TWO issues. (1) Was sending `mid` instead of `rid` as message_id. (2) Groups service uses an **internal group ID** different from the Peer ID. Peer ID 4695281546 is for Messaging; internal ID 400314250 (from GetFullGroup response field 1→1) is for Groups service (pin/kick/admin/etc). Server silently accepts the wrong ID without error. Fix: `resolveGroupInternalID()` fetches and caches the mapping via GetFullGroup.
- **Key discovery**: Bale has two Message types — `Message` (from updates, field 4=message_id) and `MessageData` (from LoadHistory, field 2=message_id). Both store the `rid`, not the `mid`. The `mid` is only the server's internal sequential counter.
- **Key discovery**: Bale has TWO ID systems for groups. Peer ID (used in `Peer{type,id}` for Messaging) differs from internal group ID (used in `ShortPeer{id}` for Groups service). Web client confirmed via DevTools WS frame capture.
- All confirmed working with user verification 2026-04-06.

### Full aiobale Audit Results (2026-04-06)

Every method in `bale.go` was compared field-by-field against the aiobale Python library source (`github.com/AmirhosseinRaworBale/aiobale`). All protobuf field numbers, service names, and method names verified.

**28/28 Core methods tested live + user verified:**

| # | Method | Service | Status |
|---|--------|---------|--------|
| 1 | SendMessage | Messaging | PASS (fixed: returns rid:dateMs:mid) |
| 2 | EditMessage (UpdateMessage) | Messaging | PASS (fixed: uses rid not mid) |
| 3 | DeleteMessage | Messaging | PASS |
| 4 | ReplyToMessage | Messaging | PASS |
| 5 | ForwardMessages | Messaging | PASS (fixed: peer type for groups) |
| 6 | GetMessages (LoadHistory) | Messaging | PASS |
| 7 | GetDialogs (LoadDialogs) | Messaging | PASS |
| 8 | MarkAsRead (MessageRead) | Messaging | PASS |
| 9 | PinMessage (group) | Groups | PASS (fixed: rid not mid) |
| 10 | UnpinMessage (UnPinMessages) | Messaging | PASS |
| 11 | ReactToMessage (MessageSetReaction) | Abacus | PASS |
| 12 | GetProfile (LoadFullUsers) | Users | PASS (fixed: user-mode dispatch) |
| 13 | EditName | Users | PASS |
| 14 | EditAbout | Users | PASS |
| 15 | SearchContacts | Users | PASS |
| 16 | GetContacts | Users | PASS |
| 17 | LoadBlockedUsers | Users | PASS |
| 18 | SetOnline | Presence | PASS |
| 19 | Typing | Presence | PASS |
| 20 | StopTyping | Presence | PASS |
| 21 | GetParameters | Configs | PASS |
| 22 | GetFullGroup | Groups | PASS |
| 23 | LoadMembers | Groups | PASS |
| 24 | GetGroupMembersCount | Groups | PASS |
| 25 | GetGroupInviteURL | Groups | PASS |
| 26 | GetFileUploadURL (GetNasimFileUploadUrl) | Files | PASS |
| 27 | GetMyKifpools | Kifpool | PASS (timeout expected for non-financial) |
| 28 | LoadPinnedMessages | Messaging | PASS |

**Protobuf field discrepancies found (non-critical — less-used methods):**

| Method | Issue | Severity |
|--------|-------|----------|
| EditParameter | Field 2 should be StringValue `{1: value}`, Go sends plain string | Low — works anyway |
| GetMessageReactionsList | Missing optional fields 5 (page) and 6 (limit) | Low — defaults work |
| GetMessagesViews | Extra field 3 (`true` for increment) not in aiobale | Low — server accepts |
| GetFileUploadUrl | Missing optional fields 6 (Chat) and 7 (SendType) | Low — optional |
| LoadMembers | Field 3 type: should be StringValue, Go sends []byte | Low — works for nil |
| MakeUserAdmin | Missing optional field 3 (admin_name as StringValue) | Low — optional |
| SendReport | Different payload structure vs aiobale | Medium — untested |
| SendGiftPacketWithWallet | Different payload structure vs aiobale | Medium — untested |
| OpenGiftPacket | Different payload structure vs aiobale | Medium — untested |
| UpvotePost | Field 1 should be InfoMessage, Go sends Peer | Medium — untested |
| RevokeUpvotedPost | Same as UpvotePost | Medium — untested |
| GetMessageUpvoters | Fields 1/2 wrong types vs aiobale | Medium — untested |

The "Medium" items are gift/upvote/report methods that haven't been live-tested. The payload structures differ significantly from aiobale and may need rewriting if those features are needed.

**Key architectural findings:**

1. **rid is king**: Bale identifies messages by the client-generated random ID (`rid`), not the server's sequential `mid`. The `mid` from SendMessage response field 1 is just a counter — never use it for edit/delete/pin/forward/react.

2. **Positive group IDs**: Unlike Telegram (negative = group), Bale uses positive IDs for all peer types. Must pass explicit peer type via `"id|2"` format or look up from dialog cache. `parsePeerID()` can only guess private (positive) vs group (negative).

3. **Two Message types in protobuf**:
   - `Message` (from updates/send response): `{1: Chat, 2: sender_id, 3: date, 4: message_id}`
   - `MessageData` (from LoadHistory): `{1: sender_id, 2: message_id, 3: date, 4: content}`
   - Both `message_id` fields contain the `rid`. Different field positions!

4. **SendMessage response format**: `{1: mid (server counter), 2: date (millis)}`. Our `rid` is NOT echoed back — we stash it via `__rid` key in the response map.

---

## Web Client Scrape (web.bale.ai v4.16.0+150936, 2026-04-06)

### Platform App Credentials
| Platform | app_id | api_key |
|----------|--------|---------|
| iOS | 2 | `D5E18686B5C7FA2EA2EC64BDE0A0EC6CD5E18686B5C7FA2EA2EC64BDE0A0EC6C` |
| Web | 4 | `C28D46DC4C3A7A26564BFCC48B929086A95C93C98E789A19847BEE8627DE4E7D` |

### WebSocket Framing (from JS source)
```
ClientFrame: {1: Request, 2: Ping, 3: HandshakeRequest}
ServerFrame: {1: Response, 2: Update, 3: TerminateSession, 4: Pong, 5: HandshakeResponse}
Request: {1: serviceName, 2: method, 3: payload, 4: metadata, 5: index}
Response: {1: error{1:code, 2:message, 3:details}, 2: response, 3: index}
HandshakeRequest: {1: mkprotoVersion(=1), 2: apiVersion}
```

*(Auth, Users, Configs, Push, Ramz, Report, Fanoos, FeedBack service method lists are in the Services table above — not duplicated here.)*

### MessageContent: 31 oneof types (from JS protobuf)
| Field | Type | Description |
|-------|------|-------------|
| 1 | BankMessage | Banking/payment |
| 2 | BinaryMessage | Binary data |
| 3 | DeletedMessage | Deleted placeholder |
| 4 | DocumentMessage | Files/media (photo/video/voice/audio/gif) |
| 5 | EmptyMessage | Empty/forwarded stub |
| 7 | JsonMessage | JSON payload |
| 8 | NasimEncryptedMessage | Server-side encrypted |
| 9 | OrderMessage | Order |
| 10 | PurchaseMessage | Purchase |
| 11 | ServiceMessage | System/service notifications (26 sub-types) |
| 12 | StickerMessage | Sticker |
| 13 | TemplateMessage | Bot template with inline keyboard |
| 14 | TemplateMessageResponse | Bot template response |
| 15 | TextMessage | Plain text |
| 16 | UnsupportedMessage | Unsupported |
| 17 | GiftPacketMessage | Gift packet |
| 18 | PremiumMessage | Premium |
| 19 | NewPremiumMessage | New premium |
| 20 | BoughtPremiumMessage | Bought premium |
| 21 | AdvertisementMessage | Ad |
| 23 | CrowdFundingMessage | Crowdfunding |
| 24 | AnimatedStickerMessage | Animated sticker |
| 25 | BannedMessage | Banned content |
| 26 | LiveMessage | Live stream |
| 27 | ProtectedMessage | Protected/disappearing |
| 28 | GoldGiftPacketMessage | Gold gift |
| 29 | PollMessage | Poll |
| 30 | LongTextMessage | Long text (>limit) |
| 31 | StreamedMessage | Streamed/chunked |

### HistoryMessage (full protobuf)
```
1=senderUid, 2=rid, 3=date(ms), 4=MessageContent, 5=state(MESSAGESTATE),
6=repeated Reaction, 7=MessageAttribute, 8=QuotedMessage,
9=Int64Value(seq), 10=OtherMessage(prev), 11=OtherMessage(next),
12=Int64Value(editedAt), 13=Int32Value(editorUserId),
14=Int64Value(groupedId), 15=BoolValue(hasComment),
16=RepliesInfo(replies), 17=Int64Value(replyToTopId)
```

### Dialog (full protobuf)
```
1=OutPeer, 2=unreadCount, 3=sortDate, 4=senderUid, 5=rid, 6=date,
7=MessageContent, 8=state, 9=Int64Value(firstUnreadDate), 10=attributes,
13=Struct(exInfo), 14=isMessageForwarded, 15=repeated UnreadMention,
16=repeated UnreadReaction, 17=markedAsUnread, 18=isMute
```

### Enums (key ones)
```
PeerType: 0=UNKNOWN, 1=PRIVATE, 2=GROUP, 3=CHANNEL, 4=BOT, 5=SUPERGROUP, 6=THREAD
GroupType: 0=GROUP, 1=CHANNEL, 2=SUPER_GROUP
MessageState: 0=SENT, 1=RECEIVED, 2=READ
```

### ServiceMessage: 26 sub-types
Fields 1-26 of ServiceMessageExt, including: BecameOrphaned, ChangedAbout,
ChangedAvatar, ChangedNick, ChangedTitle, ChangedTopic, ChatArchived, ChatRestored,
ContactRegistered, GroupCreated, PhoneCall, PhoneMissed, UserInvited, UserJoined,
UserKicked, UserLeft, GiftPacketOpened, GiftPacketOpenedCompact, NewUserWelcome,
GroupCallStarted, GroupCallEnded, CallRecordStateChanged, MiniAppDataSent,
AnonymousContact, PassportDataSent, TopicCreated

### PhoneCall message (server-relay VOIP)
```
1=id, 2=createDate, 3=startDate, 4=duration, 5=callerUid, 6=callerPhone,
7=switchIp, 8=switchPort, 9=tempVoipToken, 10=calleePhone, 11=discardReason
```

### New features discovered in web client
- **Topics**: CreateTopic, EditTopic, DeleteTopic (PEERTYPE_THREAD=6)
- **Folders**: LoadFolders, CreateFolder, EditFolder, DeleteFolder, ReorderFolders
- **Polls**: CreatePoll, Vote, ClosePoll, GetPollResults, GetFullPollResult
- **Stories**: StoryReference in QuotedMessage
- **Mini Apps**: GetMiniAppUrl, GetBotMenuButtons, InvokeCustomMethod
- **AI**: GetTranscript (voice→text)
- **Privacy**: GetUserPrivacyStatus, SetUserPrivacyStatus, GetUserFullPrivacy
- **2FA**: Full enable/disable/recover/verify flow
- **Sessions**: GetAuthSessions, TerminateSession, TerminateAllSessions
- **Search**: SearchPeerMessages, SearchPeerMedia, SearchMembers, SearchLinks, GlobalChannelSearch
- **App Lock**: bale.ramz.v1.Ramz service (7 methods)
- **Push**: ai.bale.pushak.Push service (6 methods)
- **Analytics**: bale.fanoos.v1.fanoos/Send
- **Feedback**: bale.feedback.v1.FeedBack/SendFeedBack

### Call Protocol — `bale.meet.v1.Meet` (captured via mitmproxy 2026-04-07, enriched 2026-04-08 from Python reference)

**Service**: `bale.meet.v1.Meet` (NOT in aiobale, discovered via MITM)

**Bale uses LiveKit for calls** — StartGroupCall/JoinGroupCall returns a LiveKit JWT + WebSocket URL.

#### Peer format
`{1: type, 2: id}` — type 1=private, type 2=group.

#### Methods:

| Method | Request | Response |
|--------|---------|----------|
| `StartGroupCall` | `{1: Peer{1:2, 2:group_id}}` | `{1: {1:call_id, 2:room, 3:token, 4:{1:url}}}` |
| `JoinGroupCall` | `{1: call_id}` | Same as StartGroupCall |
| `LeaveGroupCall` | `{1: call_id, 2: reason(0)}` | - |
| `GetWssURL` | `{1: call_id}` | `{1: url}` |
| `GetOngoingCalls` | `{}` | `{1: {10: {1: call_id}, ...}}` |
| `GetCallLogs` | `{1: page, 2: count}` | Call history |
| `StartCall` | `{1: OutPeer{1:1, 2:peer_id}, 2:rid}` | Needs access_hash (unreliable) |
| `ReceiveCall` | `{1: call_id}` | Accept incoming call |
| `DiscardCall` | `{1: call_id, 2: reason}` | End private call |
| `GetGroupCall` | `{1: Peer{1:2, 2:group_id}}` | Check if group call is active |

**GetOngoingCalls response parsing**: call_id is in field `1.10.1` (not top-level — `1.2` is group peer, not call_id).

<!-- Discovered 2026-04-08 -->
**StartGroupCall request**: does NOT need a randomID (field 2). Just `{1: Peer}` suffices.

**Response nesting**: response data may be wrapped under field "1" — `{1: {1: call_id, 2: room, 3: token, 4: {1: url}}}`. Check both flat and nested.

- JWT contains: `{video: {canPublish, canPublishData, canSubscribe, room, roomAdmin, roomJoin}, sub: "userID", iss: "APIVLFKgSeHLgRb", metadata: {user_id, auth_sid}}`

#### LiveKit Integration:
- **Server**: `wss://meet-em.ble.ir` (Iran-only, geo-restricted)
- **Validate**: `GET https://meet-em.ble.ir/rtc/validate?access_token=...` (preflight)
- **WebSocket**: `wss://meet-em.ble.ir/rtc?access_token=TOKEN&auto_subscribe=1&sdk=js&version=2.15.2&protocol=16&adaptive_stream=1`
- **TURN**: `turns:meet-turn.ble.ir:443?transport=tcp`
- **STUN**: `stun:2.189.68.115:443`, `stun:stun.l.google.com:19302`
- **SDP**: Negotiates `webrtc-datachannel` (SCTP), `max-message-size: 65535`
- **Server version**: LiveKit 1.9.11
- **Codecs**: VP8, VP9, H264, AV1, opus
- JWT issuer: `APIVLFKgSeHLgRb` (LiveKit API key)
- Room UUID assigned by server
- Supports: publish audio/video, subscribe, screen share, data channels

<!-- Discovered 2026-04-08 -->
**Silent audio track requirement**: A silent audio track (48kHz mono, DTX enabled) must be published for the SFU to treat the connection as a real call participant (triggers `connection_quality_changed` events, full bandwidth allocation).

<!-- Discovered 2026-04-08 -->
**Fingerprint disguise**: LiveKit Python SDK sends `sdk=python&os=NixOS` in the URL. Bale's server expects `sdk=js&version=2.15.2` with browser User-Agent and `Origin: https://web.bale.ai`. A WebSocket proxy or URL rewrite may be needed if using non-browser SDKs.

#### Call Enums (from web client JS):
```
CALLMODE: PRIVATE, GROUP, MULTIPEER, CHANNEL_LIVE, UNKNOWN
CALLTYPE: INTERNAL, SIP, SIP_AND_INTERNAL, UNKNOWN
CALLEVENTTYPE: RECORD_COUNTDOWN, UNKNOWN
STATSTYPE: VOICEIN, VOICEOUT, VIDEOIN, VIDEOOUT, SCREENVIN, SCREENVOUT, SCREENAIN, SCREENAOUT
```

#### EndCall flow:
1. Try `LeaveGroupCall({1: call_id, 2: 0})` first (works for group calls)
2. Fallback to `DiscardCall({1: call_id, 2: 1})` for private 1:1 calls

#### LiveKit token expiry:
Tokens expire after ~6 hours. Restart call to refresh.

#### Implementation Status: DONE (UNTESTED — geo-restricted)

<!-- Updated 2026-04-08 -->
Fully implemented in `bale.go` using `github.com/livekit/server-sdk-go/v2` (pure Go, uses pion/webrtc).

**Group call flow** (implemented in `JoinGroupCall`):
1. `GetOngoingCalls` → extract call_id from field `1.10.1`
2. If found: `JoinGroupCall({1: call_id})` → get LiveKit credentials
3. If not found: `StartGroupCall({1: Peer})` → creates new call, returns LiveKit credentials
4. `GetWssURL({1: call_id})` as fallback if response lacks ws_url
5. `ConnectToRoomWithToken(url, jwt)` via livekit SDK → WebRTC connection
6. Publish silent opus audio track (48kHz mono) → SFU treats us as real participant
7. Auto-subscribe to all remote tracks (audio read+discard for now; bridge playback in Phase 5)

**1:1 call flow** (implemented in `StartCall`):
1. `StartCall({1: OutPeer{1:1, 2:peer_id}, 2: rid})` → get LiveKit credentials
2. Same LiveKit connection steps as group call (steps 4-7 above)
3. Note: may need `access_hash` which is unreliable — group calls are more reliable

**End call**: LiveKit `room.Disconnect()` → `LeaveGroupCall` (group) or `DiscardCall` (1:1)
**Mute**: `audioPub.SetMuted(bool)` on the LiveKit track publication

### Puppet Platforms (multi-messenger support)
```
PUPPET_BALE, PUPPET_IGAP, PUPPET_GAP, PUPPET_EITTA, PUPPET_RUBIKA, PUPPET_SPLUS, PUPPET_M7, PUPPET_M8, PUPPET_UNKNOWN
```
Bale has built-in bridge/puppet support for other Iranian messengers.

