# Bale — Fresh Checklist

**Methods:** 464 exported | **Lines:** 7,985 | **File:** `go/cores/bale.go`
**Protocol:** Bale (Bot API + User gRPC API, Iranian messenger)
**Last updated:** 2026-04-13

## Categories

### Core Interface (2)
- [ ] Capabilities
- [ ] Name

### Authentication & Session (26)
- [ ] Authenticate
- [ ] ChangePhone
- [ ] ChangePhoneNumber
- [ ] ConfirmPhoneNumber
- [ ] Close
- [ ] DeleteAccount
- [ ] DisableTwoFactorAuthentication
- [ ] EnableTwoFactorAuthentication
- [ ] GetAuthSessions
- [ ] GetSessions
- [ ] GetUserID
- [ ] GetUserIdToken
- [ ] IsTwoFactorAuthenticationEnabled
- [ ] Logout
- [ ] RecoverPassword
- [ ] SendChangePhoneVerificationCode
- [ ] SendDeleteAccountVerificationCode
- [ ] SetNewPassword
- [ ] TerminateAllSessions
- [ ] TerminateSession
- [ ] TerminateSessionReal
- [ ] UserSignOut
- [ ] UserSignUp
- [ ] UserTerminateSession
- [ ] UserValidatePassword
- [ ] VerifyPasswordRecovery

### Messaging — Send (30)
- [ ] CopyMessage
- [ ] ForwardMessage
- [ ] ReplyToMessage
- [ ] SendAnimation
- [ ] SendAnimatedSticker
- [ ] SendAudio
- [ ] SendContact
- [ ] SendDocument
- [ ] SendImageBase64
- [ ] SendInvoice
- [ ] SendJsonMessage
- [ ] SendLiveMessage
- [ ] SendLocation
- [ ] SendLongTextMessage
- [ ] SendMediaGroup
- [ ] SendMessage
- [ ] SendMessageWithKeyboard
- [ ] SendOrderMessage
- [ ] SendPhoto
- [ ] SendProtectedMessage
- [ ] SendScheduledMessage
- [ ] SendSticker
- [ ] SendVenue
- [ ] SendVideo
- [ ] SendVideoNote
- [ ] SendVoice
- [ ] UserForwardMessages
- [ ] UserSendMessage
- [ ] UserSendMultiMediaMessage
- [ ] UserSendRaw

### Messaging — Send (User-Specific) (11)
- [ ] SendBankMessage
- [ ] UserSendAnimatedSticker
- [ ] UserSendBankMessage
- [ ] UserSendJsonMessage
- [ ] UserSendLiveMessage
- [ ] UserSendLongTextMessage
- [ ] UserSendOrderMessage
- [ ] UserSendProtectedMessage
- [ ] UserSendScheduledMessage
- [ ] UserFetchProtectedMessage
- [ ] UserSendAuthenticatedInlineCallBackData

### Messaging — Edit & Delete (5)
- [ ] DeleteMessage
- [ ] EditMessage
- [ ] EditMessageCaption
- [ ] EditMessageReplyMarkup
- [ ] UserUpdateMessage

### Messaging — Delete (User) (2)
- [ ] UserClearChat
- [ ] UserDeleteMessage

### Messaging — Read State (8)
- [ ] GetReadState
- [ ] MarkAsRead
- [ ] MarkAsUnread
- [ ] MarkUnread
- [ ] UserMarkAsUnread
- [ ] UserMarkDialogsAsRead
- [ ] UserMentionRead
- [ ] UserMessageRead

### Messaging — Reactions (8)
- [ ] ReactToMessage
- [ ] UserEnableShowReactionFlag
- [ ] UserGetReactions
- [ ] UserGetReactionsList
- [ ] UserGetShowReactionFlag
- [ ] UserLoadReactions
- [ ] UserMessageReactionsRead
- [ ] UserSetAvailableReactions

### Messaging — Reactions (Single) (2)
- [ ] UserRemoveReaction
- [ ] UserSetReaction

### Messaging — Search (10)
- [ ] SearchGlobal
- [ ] SearchMessages
- [ ] UserSearchContent
- [ ] UserSearchDialog
- [ ] UserSearchMessageMore
- [ ] UserSearchMessages
- [ ] UserSearchPeer
- [ ] UserUpdateSearchContentClick
- [ ] SearchLinks
- [ ] UserGetLinkPreview

### Messaging — History & Fetch (7)
- [ ] GetMessages
- [ ] UserGetDifference
- [ ] UserLoadHistory
- [ ] UserLoadReplies
- [ ] UserGetDiscussionMessage
- [ ] UserGetMessagesRepliesInfo
- [ ] UserMessageReceived

### Messaging — Pins (6)
- [ ] PinMessage
- [ ] UnpinAllChatMessages
- [ ] UnpinAllMessages
- [ ] UnpinMessage
- [ ] UserGetPins
- [ ] UserLoadPinnedMessages

### Messaging — Pins (User) (4)
- [ ] UserPinMessage
- [ ] UserRemoveAllPins
- [ ] UserRemovePin
- [ ] UserUnPinMessages

### Messaging — Typing & Actions (3)
- [ ] SendChatAction
- [ ] SendTyping
- [ ] UserStopTyping

### Messaging — Typing (User) (1)
- [ ] UserTyping

### Messaging — Upvotes (4)
- [ ] GetMessageUpvoters
- [ ] RevokeUpvotedPost
- [ ] UpvotePost
- [ ] UserGetMyUpvotes

### Messaging — Views (1)
- [ ] UserGetMessageViews

### Messaging — Seen List (1)
- [ ] UserGetMessageSeenList

### Messaging — Streams (3)
- [ ] UserCancelMessageStream
- [ ] UserDeleteStream
- [ ] UserReceiveMessageStream

### Polls (8)
- [ ] ClosePoll
- [ ] CreatePoll
- [ ] GetFullPollResult
- [ ] GetPollResults
- [ ] VotePoll
- [ ] UserClosePollService
- [ ] UserCreatePoll
- [ ] UserVotePollService

### Polls (User-Specific) (2)
- [ ] UserGetFullPollResultService
- [ ] UserGetPollResultsService

### Inline & Callback (5)
- [ ] AnswerCallbackQuery
- [ ] AnswerInlineQuery
- [ ] UserGetInlineBotResults
- [ ] UserSendInlineCallback
- [ ] UserSendInlineCallBackData

### Chat & Group Management (14)
- [ ] CreateChannel
- [ ] CreateGroup
- [ ] GetChat
- [ ] GetChatInfo
- [ ] EditChatDescription
- [ ] EditChatTitle
- [ ] SetChatDescription
- [ ] SetChatTitle
- [ ] DeleteChatPhoto
- [ ] SetChatPhoto
- [ ] LeaveChat
- [ ] UserCreateGroup
- [ ] UserCreateGroupFull
- [ ] UserGetFullGroup

### Chat — Members (16)
- [ ] AddMembers
- [ ] BanChatMember
- [ ] BanMember
- [ ] GetChatAdministrators
- [ ] GetChatMember
- [ ] GetChatMembersCount
- [ ] GetMembers
- [ ] InviteUser
- [ ] PromoteChatMember
- [ ] RemoveMember
- [ ] RestrictChatMember
- [ ] SearchMembers
- [ ] SetAdmin
- [ ] UnbanChatMember
- [ ] UnbanMember
- [ ] UserLoadMembers

### Chat — Members (User) (12)
- [ ] UserFetchGroupAdmins
- [ ] UserGetBannedUsers
- [ ] UserGetGroupMembersCount
- [ ] UserGetGroupMembersPresences
- [ ] UserGetMemberPermissions
- [ ] UserInviteUser
- [ ] UserInviteUsers
- [ ] UserKickUser
- [ ] UserMakeUserAdmin
- [ ] UserRemoveUserAdmin
- [ ] UserSearchMembersService
- [ ] UserSetMemberPermissions

### Chat — Member Customization (3)
- [ ] UserSetMemberCustomTitle
- [ ] UserSetRestriction
- [ ] UserTransferOwnership

### Chat — Invite Links (5)
- [ ] CreateChatInviteLink
- [ ] ExportChatInviteLink
- [ ] GetInviteLink
- [ ] UserGetGroupInviteURL
- [ ] UserRevokeInviteURL

### Chat — Join & Leave (User) (3)
- [ ] UserJoinGroup
- [ ] UserJoinPublicGroup
- [ ] UserLeaveGroup

### Chat — Group Settings (User) (6)
- [ ] UserEditGroupAbout
- [ ] UserEditGroupAvatar
- [ ] UserEditGroupTitle
- [ ] UserRemoveGroupAvatar
- [ ] UserSetCanSeeHistory
- [ ] UserSetCanSeeMessages

### Chat — Group Permissions (User) (3)
- [ ] UserGetBotGroupPermissions
- [ ] UserGetCanSeeMessages
- [ ] UserSetGroupDefaultPermissions

### Chat — Group Info (User) (6)
- [ ] UserGetGroupOnlineCount
- [ ] UserGetGroupPreview
- [ ] UserGetMyGroups
- [ ] UserLoadFullGroups
- [ ] UserLoadGroups
- [ ] ResolveGroupID

### Chat — Discussion Groups (3)
- [ ] UserAddDiscussionGroupAdmin
- [ ] UserRemoveDiscussionGroup
- [ ] UserSetDiscussionGroup

### Chat — Recommendations (4)
- [ ] UserGetChannelRecommendations
- [ ] UserGetGroupRecommendations
- [ ] UserGetGroupsRecommendation
- [ ] UserGetRelatedChannels

### Chat — Recommendations (Groups) (1)
- [ ] UserGetRelatedGroups

### Chat — Mutual (1)
- [ ] UserGetMutualGroups

### Chat — Archive & Mute (5)
- [ ] ArchiveChat
- [ ] MuteChat
- [ ] UserArchiveDialogs
- [ ] UserUnArchiveDialogs
- [ ] UserDeleteChat

### Dialogs & Folders (17)
- [ ] CreateFolder
- [ ] CreateFolderReal
- [ ] DeleteFolder
- [ ] EditFolder
- [ ] GetDialogs
- [ ] GetFolders
- [ ] LoadDialogsFiltered
- [ ] LoadFolders
- [ ] ReorderFolders
- [ ] UserCreateFolder
- [ ] UserCreateReservedFolder
- [ ] UserLoadDialogs
- [ ] UserLoadDialogsFiltered
- [ ] UserLoadFolderDialogs
- [ ] UserLoadGroupedDialogs
- [ ] UserLoadPeerDialogs
- [ ] UserLoadPinnedDialogs

### Dialogs — Pin (3)
- [ ] UserPinDialogs
- [ ] UserReorderPinnedDialogs
- [ ] UserUnpinDialogs

### Topics & Threads (7)
- [ ] CreateTopic
- [ ] DeleteTopic
- [ ] EditTopic
- [ ] UserCreateTopic
- [ ] UserCreateThread
- [ ] UserGetTopicByID
- [ ] UserGetTopics

### Thread Subscriptions (2)
- [ ] UserSubscribeToThreadUpdates
- [ ] UserUnsubscribeFromThreadUpdates

### Contacts (11)
- [ ] AddContact
- [ ] DeleteContact
- [ ] GetContacts
- [ ] UserAddContact
- [ ] UserGetContacts
- [ ] UserGetContactsPresences
- [ ] UserGetOrganizationalContacts
- [ ] UserImportContacts
- [ ] UserRemoveContact
- [ ] UserResetContacts
- [ ] UserSearchContacts

### User Profile & Privacy (17)
- [ ] EditAvatarGRPC
- [ ] EditBirthDate
- [ ] EditMyPreferredLanguages
- [ ] EditMyTimeZone
- [ ] EditSex
- [ ] GetFullUser
- [ ] GetProfile
- [ ] GetUserFullPrivacy
- [ ] GetUserPrivacyStatus
- [ ] IsNameAllowed
- [ ] LoadAvatars
- [ ] LoadFullUsersSequentially
- [ ] RemoveAvatar
- [ ] SetUserPrivacyStatus
- [ ] UserEditAbout
- [ ] UserEditName
- [ ] UserEditNickName

### User Profile (User-Specific) (5)
- [ ] UserCheckNickName
- [ ] UserEditChannelNick
- [ ] UserEditLocalName
- [ ] UserEditParameter
- [ ] UserGetParameters

### User — Avatars (User) (1)
- [ ] UserLoadGroupAvatars

### User — Presence & Online (6)
- [ ] UserGetUsersPresence
- [ ] UserSetOnline
- [ ] UserSubscribeFromGroupOnline
- [ ] UserSubscribeFromOnline
- [ ] UserSubscribeToGroupOnline
- [ ] UserSubscribeToOnline

### User — Block (5)
- [ ] BlockUser
- [ ] UnblockUser
- [ ] UserBlockUser
- [ ] UserUnBanUser
- [ ] UserUnblockUser

### User — Blocked List (2)
- [ ] GetBlockedUsers
- [ ] UserLoadBlockedUsers

### User — Peers & Top Peers (3)
- [ ] UserLoadPeers
- [ ] UserGetTopPeer
- [ ] UserRemoveTopPeer

### User — Context (1)
- [ ] UserGetUserContext

### User — Anonymous (1)
- [ ] UserGetAnonymousContactPage

### User — Full Users (1)
- [ ] UserLoadFullUsers

### User — Users (1)
- [ ] UserLoadUsers

### Files & Media (7)
- [ ] DownloadFile
- [ ] GetFile
- [ ] UploadFile
- [ ] UploadRawPUT
- [ ] UserGetFileUploadURL
- [ ] UserGetFileURL
- [ ] UserFileUploadCancel

### Files — Shared Media (3)
- [ ] SearchPeerMedia
- [ ] SearchPeerMessages
- [ ] UserLoadSharedMedia

### Files — Active Shared Media (1)
- [ ] UserGetActiveSharedMedia

### Files — Search Media (1)
- [ ] UserSearchMediaService

### Files — Nasim (CDN) (3)
- [ ] UserGetNasimFilePublicUrl
- [ ] UserGetNasimFileUploadResume
- [ ] UserGetNasimFileUrls

### Stickers (10)
- [ ] AddStickerToSet
- [ ] CreateNewStickerSet
- [ ] DeleteStickerFromSet
- [ ] GetStickerSet
- [ ] UploadStickerFile
- [ ] UserAddStickerCollection
- [ ] UserAddStickerPack
- [ ] UserLoadOwnStickers
- [ ] UserLoadStickerCollection
- [ ] UserRemoveStickerCollection

### Stickers (User) (1)
- [ ] UserRemoveStickerPack

### GIFs (4)
- [ ] UserAddGif
- [ ] UserGetSavedGifs
- [ ] UserRemoveGif
- [ ] UserUseGif

### Stories (19)
- [ ] UserAddBotStory
- [ ] UserAddChannelStory
- [ ] UserAddStory
- [ ] UserCanAddBotStory
- [ ] UserCheckStoryLinkValidity
- [ ] UserGetBotStories
- [ ] UserGetChannelStories
- [ ] UserGetDefaultStoryBackgrounds
- [ ] UserGetMostPopularStories
- [ ] UserGetSimilarPosts
- [ ] UserGetStories
- [ ] UserGetStoriesByList
- [ ] UserGetStoryByID
- [ ] UserGetStoryPrivacyConfig
- [ ] UserGetStoryReactionEmojis
- [ ] UserGetStoryTags
- [ ] UserGetStoryViewers
- [ ] UserGetStoryViewersCount
- [ ] UserGetStoryWidgets

### Stories — Actions (3)
- [ ] UserReactToStory
- [ ] UserRemoveStory
- [ ] UserSetStoryPrivacyConfig

### Stories — Config (1)
- [ ] UserSetUserStoryConfig

### Stories — User Config (1)
- [ ] UserGetUserStoryConfig

### Calls — Bot API (5)
- [ ] AcceptCall
- [ ] DeclineCall
- [ ] DiscardCall
- [ ] EndCall
- [ ] StartCall

### Calls — State & Logs (4)
- [ ] GetCallLogs
- [ ] GetGroupCall
- [ ] GetOngoingCalls
- [ ] ReceiveCall

### Calls — Mute & Layout (3)
- [ ] SetCallMuted
- [ ] UserMuteCallParticipant
- [ ] UserUpdateCallLayout

### Calls — User Actions (9)
- [ ] UserAskToJoinCall
- [ ] UserAnswerCallJoinRequest
- [ ] UserDeleteCallLogs
- [ ] UserGenerateCallLink
- [ ] UserGetCallLinkDetails
- [ ] UserGetCallState
- [ ] UserInviteToCall
- [ ] UserRemoveCallParticipant
- [ ] UserTakeCallAction

### Calls — Links (1)
- [ ] UserSetCallLinkTitle

### Calls — Recording & Streaming (4)
- [ ] UserStartRecording
- [ ] UserStartStream
- [ ] UserStopRecording
- [ ] JoinGroupCall

### Calls — Reactions & Feedback (3)
- [ ] UserSendCallReaction
- [ ] UserSubmitCallFeedback
- [ ] UserAcceptCallMeet

### Calls — Fanoos (1)
- [ ] UserSendCallFanoosEvent

### Bots (9)
- [ ] DeleteMyCommands
- [ ] GetBotMenuButtons
- [ ] GetMyCommands
- [ ] InvokeCustomMethod
- [ ] SetMyCommands
- [ ] UserDeleteMyCommands
- [ ] UserGetBotInfo
- [ ] UserGetBots
- [ ] UserGetMyCommands

### Bots — Menu & Whitelist (2)
- [ ] UserGetMenuButton
- [ ] UserGetBotWhiteList

### Bots — User Commands (1)
- [ ] UserSetMyCommands

### Bots — Custom Actions (1)
- [ ] UserInvokeCustomAction

### Mini Apps & Webapps (4)
- [ ] GetMiniAppUrl
- [ ] UserGetMiniAppUrlAppzar
- [ ] UserSendMiniAppData
- [ ] UserGetWebappHash

### Webhooks (3)
- [ ] DeleteWebhook
- [ ] GetWebhookInfo
- [ ] SetWebhook

### Updates & Sync (4)
- [ ] GetUpdates
- [ ] OnUpdate
- [ ] UserSubscribeToUpdates
- [ ] GetUserProfilePhotos

### Payments & Commerce (7)
- [ ] AnswerPreCheckoutQuery
- [ ] AnswerShippingQuery
- [ ] CreateInvoiceLink
- [ ] UserCalculateDiscountedPrice
- [ ] UserGetPaymentDetails
- [ ] UserMakePayment
- [ ] InquireTransaction

### Banking & Ramz (10)
- [ ] AddCard
- [ ] ChangeDefaultCardNumber
- [ ] CheckRamzPassword
- [ ] CheckRamzPasswordSet
- [ ] DeleteRamzPassword
- [ ] ForgetRamzPassword
- [ ] GetUsersDefaultCardNumber
- [ ] RemoveDefaultCardNumber
- [ ] SendRamzOTP
- [ ] SetRamzPassword

### Banking (User) (2)
- [ ] ValidateRamzOTP
- [ ] UserEditGroupDefaultCardNumber

### Banking — Group Card (1)
- [ ] UserGetGroupDefaultCardNumber

### Push Notifications (6)
- [ ] PushSetConfig
- [ ] RegisterGooglePush
- [ ] RegisterPush
- [ ] UnregisterAllPushCredentials
- [ ] UnregisterGooglePush
- [ ] UnregisterPush

### Push (User) (1)
- [ ] UserPushSetConfig

### Device & App (3)
- [ ] GetInAppUpdate
- [ ] NotifyAboutDeviceInfo
- [ ] UserExecuteTaskNow

### Tickets & Tokens (5)
- [ ] GetBajeBamTicket
- [ ] GetBaleTicket
- [ ] GetJWTToken
- [ ] GetTicket
- [ ] GetWssURL

### Email (1)
- [ ] VerifyEmail

### Feedback & Reports (4)
- [ ] AskReview
- [ ] ReportDismiss
- [ ] ReportInappropriateContent
- [ ] SendFeedBack

### Fanoos (1)
- [ ] FanoosSend

### Channel Search (1)
- [ ] GlobalChannelSearch

### Link Status (2)
- [ ] UserGetLinkStatus
- [ ] UserGetLinkSummary

### Premium (5)
- [ ] UserGetPremiumBadges
- [ ] UserGetPremiumPackages
- [ ] UserIsPremium
- [ ] UserIsPremiumBatch
- [ ] UserPurchasePremiumPackage

### Premium — Badge (1)
- [ ] UserSetPremiumBadge

### Organization (1)
- [ ] UserGetOrganizationInfo

### Marketplace (21)
- [ ] UserMarketAcceptCampaignMarket
- [ ] UserMarketAcceptJoinRequest
- [ ] UserMarketCreateJoinRequest
- [ ] UserMarketCreateTag
- [ ] UserMarketGetCategoriesList
- [ ] UserMarketGetCategoryMarkets
- [ ] UserMarketGetCategoryProducts
- [ ] UserMarketGetIndexedProducts
- [ ] UserMarketGetJoinRequests
- [ ] UserMarketGetMarket
- [ ] UserMarketGetNumberOfSales
- [ ] UserMarketGetOnboardingStatus
- [ ] UserMarketGetPendingCampaignMarkets
- [ ] UserMarketGetPendingJoinRequests
- [ ] UserMarketGetStores
- [ ] UserMarketGetTags
- [ ] UserMarketGetTopMarkets
- [ ] UserMarketGetYaldaStores
- [ ] UserMarketRejectCampaignMarket
- [ ] UserMarketRejectJoinRequest
- [ ] UserMarketSetBanners

### Marketplace — Config (4)
- [ ] UserMarketSetGenericDeepLinks
- [ ] UserMarketSetOnboardingData
- [ ] UserMarketSetPopularSearches
- [ ] UserMarketSubmitFeedback

### Marketplace — Update & Search (3)
- [ ] UserMarketUpdateInfo
- [ ] UserSearchMarket
- [ ] UserSearchMarketPopular

### Marketplace — Products (1)
- [ ] UserSearchProduct

### Timche (5)
- [ ] UserTimcheAskBotReviewCallback
- [ ] UserTimcheGetBotPage
- [ ] UserTimcheGetHomePage
- [ ] UserTimcheGetSectionPage
- [ ] UserTimcheSubmitReview

### Ghasedak (Feed) (2)
- [ ] UserGhasedakGetDiff
- [ ] UserGhasedakGetRoutesStates

### Feed & Magazine (3)
- [ ] UserLoadCategoryFeedMessages
- [ ] UserLoadFeedMessages
- [ ] UserLoadInternalFeedMessages

### Magazine (1)
- [ ] UserLoadMagazineCategories

### AI & Transcription (4)
- [ ] GetTranscript
- [ ] GetTranscript
- [ ] UserAIGetTranscript
- [ ] UserAISendEvent

### LLM Auth (1)
- [ ] UserGetLLMAuthToken

### Scheduled Tasks (5)
- [ ] UserListScheduledTasks
- [ ] UserPeersWithScheduleTask
- [ ] UserReScheduleTask
- [ ] UserScheduleTask
- [ ] UserUnScheduleTask

### HTTP & Network (1)
- [ ] UserHTTPPost

### Appzar (1)
- [ ] UserInvokeCustomMethodAppzar
