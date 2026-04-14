# Telegram — Fresh Checklist

**Methods:** 771 exported | **Lines:** 15,326 | **File:** `go/cores/telegram.go`
**Protocol:** Telegram MTProto (gotd/td v0.143.0, 681/763 API methods wrapped — 82 excluded: payments/premium/SMS/test)
**Last updated:** 2026-04-13

## Categories

### Core Interface (3)
- [ ] Capabilities
- [ ] Name
- [ ] Close

### Authentication & Session — General (7)
- [ ] Authenticate
- [ ] AuthCodeRequested
- [ ] AuthPasswordRequested
- [ ] Logout
- [ ] ProvideAuthCode
- [ ] ProvideAuthPassword
- [ ] StartBot

### Authentication — auth.* (22)
- [ ] AuthAcceptLoginToken
- [ ] AuthBindTempAuthKey
- [ ] AuthCancelCode
- [ ] AuthCheckPaidAuth
- [ ] AuthCheckPassword
- [ ] AuthCheckRecoveryPassword
- [ ] AuthDropTempAuthKeys
- [ ] AuthExportAuthorization
- [ ] AuthExportLoginToken
- [ ] AuthFinishPasskeyLogin
- [ ] AuthImportAuthorization
- [ ] AuthImportBotAuthorization
- [ ] AuthImportLoginToken
- [ ] AuthImportWebTokenAuthorization
- [ ] AuthInitPasskeyLogin
- [ ] AuthRecoverPassword
- [ ] AuthReportMissingCode
- [ ] AuthRequestFirebaseSMS
- [ ] AuthRequestPasswordRecovery
- [ ] AuthResendCode
- [ ] AuthResetAuthorizations
- [ ] AuthResetLoginEmail
- [ ] AuthSendCode
- [ ] AuthSignIn
- [ ] AuthSignUp

### Account — Profile & Settings (25)
- [ ] AccountChangeAuthorizationSettings
- [ ] AccountChangePhone
- [ ] AccountCheckUsername
- [ ] AccountDeleteAccount
- [ ] AccountFinishTakeoutSession
- [ ] AccountGetContactSignUpNotification
- [ ] AccountGetContentSettings
- [ ] AccountGetNotifyExceptions
- [ ] AccountGetNotifySettings
- [ ] AccountGetTmpPassword
- [ ] AccountGetWebAuthorizations
- [ ] AccountInitTakeoutSession
- [ ] AccountInvalidateSignInCodes
- [ ] AccountRegisterDevice
- [ ] AccountReorderUsernames
- [ ] AccountReportPeer
- [ ] AccountReportProfilePhoto
- [ ] AccountResetNotifySettings
- [ ] AccountResetWebAuthorization
- [ ] AccountResetWebAuthorizations
- [ ] AccountSetAuthorizationTTL
- [ ] AccountSetContactSignUpNotification
- [ ] AccountSetContentSettings
- [ ] AccountSetMainProfileTab
- [ ] AccountToggleSponsoredMessages
- [ ] AccountToggleUsername
- [ ] AccountUnregisterDevice
- [ ] AccountUpdateDeviceLocked
- [ ] AccountUpdateNotifySettings
- [ ] AccountUpdatePersonalChannel

### Account — Password & Security (10)
- [ ] AccountCancelPasswordEmail
- [ ] AccountConfirmPasswordEmail
- [ ] AccountDeclinePasswordReset
- [ ] AccountGetPasswordSettings
- [ ] AccountResendPasswordEmail
- [ ] AccountResetPassword
- [ ] AccountUpdatePasswordSettings
- [ ] GetPassword
- [ ] GetActiveSessions
- [ ] TerminateSession

### Account — Passkeys (4)
- [ ] AccountDeletePasskey
- [ ] AccountGetPasskeys
- [ ] AccountInitPasskeyRegistration
- [ ] AccountRegisterPasskey

### Account — Phone Verification (6)
- [ ] AccountConfirmPhone
- [ ] AccountSendChangePhoneCode
- [ ] AccountSendConfirmPhoneCode
- [ ] AccountSendVerifyPhoneCode
- [ ] AccountVerifyPhone
- [ ] AccountSendVerifyEmailCode
- [ ] AccountVerifyEmail

### Account — Privacy & Status (5)
- [ ] GetGlobalPrivacy
- [ ] SetGlobalPrivacy
- [ ] GetPrivacy
- [ ] SetPrivacy
- [ ] UpdateStatus

### Account — Theme & Wallpaper (16)
- [ ] AccountCreateTheme
- [ ] AccountGetChatThemes
- [ ] AccountGetMultiWallPapers
- [ ] AccountGetTheme
- [ ] AccountGetThemes
- [ ] AccountGetUniqueGiftChatThemes
- [ ] AccountGetWallPaper
- [ ] AccountGetWallPapers
- [ ] AccountInstallTheme
- [ ] AccountInstallWallPaper
- [ ] AccountResetWallPapers
- [ ] AccountSaveTheme
- [ ] AccountSaveWallPaper
- [ ] AccountUpdateTheme
- [ ] AccountUploadTheme
- [ ] AccountUploadWallPaper

### Account — Emoji & Reactions (13)
- [ ] AccountClearRecentEmojiStatuses
- [ ] AccountGetChannelDefaultEmojiStatuses
- [ ] AccountGetChannelRestrictedStatusEmojis
- [ ] AccountGetCollectibleEmojiStatuses
- [ ] AccountGetDefaultBackgroundEmojis
- [ ] AccountGetDefaultEmojiStatuses
- [ ] AccountGetDefaultGroupPhotoEmojis
- [ ] AccountGetDefaultProfilePhotoEmojis
- [ ] AccountGetReactionsNotifySettings
- [ ] AccountGetRecentEmojiStatuses
- [ ] AccountSetReactionsNotifySettings
- [ ] AccountUpdateColor
- [ ] AccountUpdateEmojiStatus

### Account — Auto-Download & Auto-Save (5)
- [ ] AccountDeleteAutoSaveExceptions
- [ ] AccountGetAutoDownloadSettings
- [ ] AccountGetAutoSaveSettings
- [ ] AccountSaveAutoDownloadSettings
- [ ] AccountSaveAutoSaveSettings

### Account — Secure Values (Passport) (5)
- [ ] AccountAcceptAuthorization
- [ ] AccountGetAllSecureValues
- [ ] AccountGetAuthorizationForm
- [ ] AccountGetSecureValue
- [ ] AccountSaveSecureValue
- [ ] AccountDeleteSecureValue

### Account — Business (14)
- [ ] AccountCreateBusinessChatLink
- [ ] AccountDeleteBusinessChatLink
- [ ] AccountDisablePeerConnectedBot
- [ ] AccountEditBusinessChatLink
- [ ] AccountGetBotBusinessConnection
- [ ] AccountGetBusinessChatLinks
- [ ] AccountGetConnectedBots
- [ ] AccountResolveBusinessChatLink
- [ ] AccountToggleConnectedBotPaused
- [ ] AccountUpdateBusinessAwayMessage
- [ ] AccountUpdateBusinessGreetingMessage
- [ ] AccountUpdateBusinessIntro
- [ ] AccountUpdateBusinessLocation
- [ ] AccountUpdateBusinessWorkHours
- [ ] AccountUpdateConnectedBot

### Account — Paid Messages (2)
- [ ] AccountGetPaidMessagesRevenue
- [ ] AccountToggleNoPaidMessagesException

### Account — Ringtones & Music (4)
- [ ] AccountGetSavedMusicIDs
- [ ] AccountGetSavedRingtones
- [ ] AccountSaveMusic
- [ ] AccountSaveRingtone
- [ ] AccountUploadRingtone

### Profile (7)
- [ ] GetProfile
- [ ] UpdateProfile
- [ ] UpdateUsername
- [ ] UpdateBirthday
- [ ] DeleteProfilePhotos
- [ ] UploadProfilePhoto
- [ ] GetUserPhotos

### Profile Photos (2)
- [ ] PhotosUpdateProfilePhoto
- [ ] PhotosUploadContactProfilePhoto

### Contacts (17)
- [ ] AddContact
- [ ] DeleteContact
- [ ] DeleteContacts
- [ ] GetContactIDs
- [ ] GetContacts
- [ ] ImportContacts
- [ ] ResolvePhone
- [ ] ResolveUsername
- [ ] ContactsAcceptContact
- [ ] ContactsBlockFromReplies
- [ ] ContactsDeleteByPhones
- [ ] EditCloseFriends
- [ ] ContactsExportContactToken
- [ ] ContactsGetLocated
- [ ] ContactsGetSaved
- [ ] ContactsGetStatuses
- [ ] ContactsImportContactToken
- [ ] ContactsResetSaved
- [ ] ContactsResetTopPeerRating
- [ ] ContactsSetBlocked
- [ ] ContactsToggleTopPeers
- [ ] ContactsUpdateContactNote
- [ ] ContactsGetSponsoredPeers
- [ ] SearchContactsCount

### Users (6)
- [ ] GetFullUser
- [ ] BlockUser
- [ ] UnblockUser
- [ ] GetBlockedUsers
- [ ] UsersGetRequirementsToContact
- [ ] UsersSuggestBirthday
- [ ] UsersGetSavedMusic
- [ ] UsersGetSavedMusicByID
- [ ] UsersSetSecureValueErrors

### Messaging — Send & Edit (17)
- [ ] SendMessage
- [ ] SendMultiMedia
- [ ] SendImageBase64
- [ ] SendLocation
- [ ] SendSticker
- [ ] ReplyToMessage
- [ ] ForwardMessage
- [ ] EditMessage
- [ ] DeleteMessage
- [ ] SendInlineBotResult
- [ ] SendScheduled
- [ ] SendScheduledNow
- [ ] DeleteScheduledMessages
- [ ] GetScheduledMessages
- [ ] ExportMessageLink
- [ ] SendTyping
- [ ] SetTyping

### Messaging — Read & State (10)
- [ ] MarkAsRead
- [ ] MarkDialogUnread
- [ ] MarkUnread
- [ ] ReadMentions
- [ ] ReadReactions
- [ ] GetReadState
- [ ] GetMessageViews
- [ ] GetMessageReadParticipants
- [ ] GetOutboxReadDate
- [ ] ClearDraft
- [ ] SaveDraft

### Messaging — Search & Fetch (11)
- [ ] GetMessages
- [ ] SearchMessages
- [ ] SearchGlobal
- [ ] SearchMessagesGlobal
- [ ] GetSearchCalendar
- [ ] GetSearchCounters
- [ ] GetWebPagePreview
- [ ] TranslateText
- [ ] GetUnreadMentions
- [ ] GetUnreadReactions
- [ ] GetAllDrafts

### Messaging — Reactions & Polls (11)
- [ ] ReactToMessage
- [ ] GetReactionsList
- [ ] GetMessageReactionsList
- [ ] SetChatReactions
- [ ] SetDefaultReaction
- [ ] CreatePoll
- [ ] SendPoll
- [ ] VoteInPoll
- [ ] VotePoll
- [ ] GetPollResults
- [ ] GetPollVotes

### Messaging — Inline & Bot Interaction (3)
- [ ] GetInlineBotResults
- [ ] GetBotCallbackAnswer
- [ ] OnUpdate

### Messages — Extended API (133)
- [ ] MessagesAcceptEncryption
- [ ] MessagesAcceptURLAuth
- [ ] MessagesAddPollAnswer
- [ ] MessagesAppendTodoList
- [ ] MessagesCheckHistoryImport
- [ ] MessagesCheckHistoryImportPeer
- [ ] MessagesCheckQuickReplyShortcut
- [ ] MessagesCheckURLAuthMatchCode
- [ ] MessagesClearAllDrafts
- [ ] MessagesClearRecentReactions
- [ ] MessagesClearRecentStickers
- [ ] MessagesClickSponsoredMessage
- [ ] MessagesComposeMessageWithAI
- [ ] MessagesDeclineURLAuth
- [ ] MessagesDeleteChat
- [ ] MessagesDeleteFactCheck
- [ ] MessagesDeletePhoneCallHistory
- [ ] MessagesDeletePollAnswer
- [ ] MessagesDeleteQuickReplyMessages
- [ ] MessagesDeleteQuickReplyShortcut
- [ ] MessagesDeleteRevokedExportedChatInvites
- [ ] MessagesDeleteSavedHistory
- [ ] MessagesDiscardEncryption
- [ ] MessagesEditChatAbout
- [ ] MessagesEditChatAdmin
- [ ] MessagesEditChatCreator
- [ ] MessagesEditChatParticipantRank
- [ ] MessagesEditChatPhoto
- [ ] MessagesEditChatTitle
- [ ] MessagesEditFactCheck
- [ ] MessagesEditInlineBotMessage
- [ ] MessagesEditQuickReplyShortcut
- [ ] MessagesGetAdminsWithInvites
- [ ] MessagesGetArchivedStickers
- [ ] MessagesGetAttachedStickers
- [ ] MessagesGetAttachMenuBot
- [ ] MessagesGetAttachMenuBots
- [ ] MessagesGetAvailableEffects
- [ ] MessagesGetAvailableReactions
- [ ] MessagesGetBotApp
- [ ] MessagesGetChats
- [ ] MessagesGetCustomEmojiDocuments
- [ ] MessagesGetDefaultTagReactions
- [ ] MessagesGetDiscussionMessage
- [ ] MessagesGetDocumentByHash
- [ ] MessagesGetEmojiGameInfo
- [ ] MessagesGetEmojiGroups
- [ ] MessagesGetEmojiKeywords
- [ ] MessagesGetEmojiKeywordsDifference
- [ ] MessagesGetEmojiKeywordsLanguages
- [ ] MessagesGetEmojiProfilePhotoGroups
- [ ] MessagesGetEmojiStatusGroups
- [ ] MessagesGetEmojiStickerGroups
- [ ] MessagesGetEmojiStickers
- [ ] MessagesGetEmojiURL
- [ ] MessagesGetExportedChatInvite
- [ ] MessagesGetExportedChatInvites
- [ ] MessagesGetExtendedMedia
- [ ] MessagesGetFactCheck
- [ ] MessagesGetFeaturedEmojiStickers
- [ ] MessagesGetForumTopicsByID
- [ ] MessagesGetFutureChatCreatorAfterLeave
- [ ] MessagesGetGameHighScores
- [ ] MessagesGetInlineGameHighScores
- [ ] MessagesGetMaskStickers
- [ ] MessagesGetMessageEditData
- [ ] MessagesGetMessages
- [ ] MessagesGetMessagesReactions
- [ ] MessagesGetMyStickers
- [ ] MessagesGetOldFeaturedStickers
- [ ] MessagesGetPaidReactionPrivacy
- [ ] MessagesGetPeerDialogs
- [ ] MessagesGetPinnedSavedDialogs
- [ ] MessagesGetPreparedInlineMessage
- [ ] MessagesGetQuickReplies
- [ ] MessagesGetQuickReplyMessages
- [ ] MessagesGetRecentLocations
- [ ] MessagesGetRecentReactions
- [ ] MessagesGetReplies
- [ ] MessagesGetSavedDialogs
- [ ] MessagesGetSavedDialogsByID
- [ ] MessagesGetSavedGifs
- [ ] MessagesGetSavedHistory
- [ ] MessagesGetSavedReactionTags
- [ ] MessagesGetScheduledMessages
- [ ] MessagesGetSearchResultsPositions
- [ ] MessagesGetSplitRanges
- [ ] MessagesGetSponsoredMessages
- [ ] MessagesGetStickers
- [ ] MessagesGetTopReactions
- [ ] MessagesGetUnreadPollVotes
- [ ] MessagesGetWebPage
- [ ] MessagesHideAllChatJoinRequests
- [ ] MessagesHidePeerSettingsBar
- [ ] MessagesInitHistoryImport
- [ ] MessagesInstallStickerSet
- [ ] MessagesProlongWebView
- [ ] MessagesRateTranscribedAudio
- [ ] MessagesReadDiscussion
- [ ] MessagesReadEncryptedHistory
- [ ] MessagesReadFeaturedStickers
- [ ] MessagesReadMessageContents
- [ ] MessagesReadPollVotes
- [ ] MessagesReadSavedHistory
- [ ] MessagesReceivedMessages
- [ ] MessagesReceivedQueue
- [ ] MessagesReorderPinnedSavedDialogs
- [ ] MessagesReorderQuickReplies
- [ ] MessagesReorderStickerSets
- [ ] MessagesReport
- [ ] MessagesReportEncryptedSpam
- [ ] MessagesReportMessagesDelivery
- [ ] MessagesReportMusicListen
- [ ] MessagesReportReaction
- [ ] MessagesReportReadMetrics
- [ ] MessagesReportSpam
- [ ] MessagesReportSponsoredMessage
- [ ] MessagesRequestAppWebView
- [ ] MessagesRequestEncryption
- [ ] MessagesRequestMainWebView
- [ ] MessagesRequestSimpleWebView
- [ ] MessagesRequestURLAuth
- [ ] MessagesRequestWebView
- [ ] MessagesSaveDefaultSendAs
- [ ] MessagesSaveGif
- [ ] MessagesSavePreparedInlineMessage
- [ ] MessagesSaveRecentSticker
- [ ] MessagesSearchCustomEmoji
- [ ] MessagesSearchEmojiStickerSets
- [ ] MessagesSearchSentMedia
- [ ] MessagesSearchStickers
- [ ] MessagesSendBotRequestedPeer
- [ ] MessagesSendEncrypted
- [ ] MessagesSendEncryptedFile
- [ ] MessagesSendEncryptedService
- [ ] MessagesSendPaidReaction
- [ ] MessagesSendQuickReplyMessages
- [ ] MessagesSendScreenshotNotification
- [ ] MessagesSendWebViewData
- [ ] MessagesSendWebViewResultMessage
- [ ] MessagesSetBotCallbackAnswer
- [ ] MessagesSetBotPrecheckoutResults
- [ ] MessagesSetBotShippingResults
- [ ] MessagesSetDefaultHistoryTTL
- [ ] MessagesSetEncryptedTyping
- [ ] MessagesSetGameScore
- [ ] MessagesSetInlineBotResults
- [ ] MessagesSetInlineGameScore
- [ ] MessagesStartHistoryImport
- [ ] MessagesSummarizeText
- [ ] MessagesToggleBotInAttachMenu
- [ ] MessagesToggleDialogFilterTags
- [ ] MessagesTogglePaidReactionPrivacy
- [ ] MessagesTogglePeerTranslations
- [ ] MessagesToggleSavedDialogPin
- [ ] MessagesToggleStickerSets
- [ ] MessagesToggleSuggestedPostApproval
- [ ] MessagesToggleTodoCompleted
- [ ] MessagesTranscribeAudio
- [ ] MessagesUninstallStickerSet
- [ ] MessagesUpdateSavedReactionTag
- [ ] MessagesUploadEncryptedFile
- [ ] MessagesUploadImportedMedia
- [ ] MessagesUploadMedia
- [ ] MessagesViewSponsoredMessage

### Chats & Groups (22)
- [ ] CreateGroup
- [ ] AddChatUser
- [ ] DeleteChatUser
- [ ] AddMembers
- [ ] RemoveMember
- [ ] GetChatInfo
- [ ] EditChatTitle
- [ ] EditChatDescription
- [ ] GetFullChat
- [ ] GetFullChatParticipantsCount
- [ ] MigrateChat
- [ ] LeaveChat
- [ ] MuteChat
- [ ] ArchiveChat
- [ ] SetChatTheme
- [ ] SetChatWallpaper
- [ ] DeleteChatHistory
- [ ] DeleteHistory
- [ ] SetHistoryTTL
- [ ] GetDefaultHistoryTTL
- [ ] SetSlowMode
- [ ] GetOnlineCount

### Chat Invites (8)
- [ ] CheckChatInvite
- [ ] ImportChatInvite
- [ ] ExportChatInvite
- [ ] EditChatInvite
- [ ] DeleteChatInvite
- [ ] GetInviteLink
- [ ] GetInviteImporters
- [ ] HideChatJoinRequest

### Channels & Supergroups (30)
- [ ] CreateChannel
- [ ] RawCreateChannel
- [ ] DeleteChannel
- [ ] JoinChannel
- [ ] LeaveChannel
- [ ] InviteToChannel
- [ ] EditChannelTitle
- [ ] EditChannelPhoto
- [ ] UpdateChannelColor
- [ ] UpdateChannelUsername
- [ ] GetFullChannel
- [ ] ChannelsCheckSearchPostsFlood
- [ ] ChannelsCheckUsername
- [ ] ChannelsConvertToGigagroup
- [ ] ChannelsDeactivateAllUsernames
- [ ] ChannelsDeleteHistory
- [ ] ChannelsDeleteParticipantHistory
- [ ] ChannelsEditLocation
- [ ] ChannelsGetAdminedPublicChannels
- [ ] ChannelsGetChannelRecommendations
- [ ] ChannelsGetGroupsForDiscussion
- [ ] ChannelsGetInactiveChannels
- [ ] ChannelsGetLeftChannels
- [ ] ChannelsGetMessageAuthor
- [ ] ChannelsGetMessages
- [ ] ChannelsReadMessageContents
- [ ] ChannelsReorderUsernames
- [ ] ChannelsReportAntiSpamFalsePositive
- [ ] ChannelsReportSpam
- [ ] ChannelsRestrictSponsoredMessages
- [ ] ChannelsSearchPosts
- [ ] ChannelsSetBoostsToUnblockRestrictions
- [ ] ChannelsSetDiscussionGroup
- [ ] ChannelsSetEmojiStickers
- [ ] ChannelsSetMainProfileTab
- [ ] ChannelsSetStickers
- [ ] ChannelsToggleUsername
- [ ] ChannelsUpdateEmojiStatus
- [ ] ChannelsUpdatePaidMessagesPrice

### Channel & Group Admin (15)
- [ ] PromoteAdmin
- [ ] DemoteAdmin
- [ ] SetAdmin
- [ ] BanMember
- [ ] UnbanMember
- [ ] RestrictUser
- [ ] SetGroupPermissions
- [ ] GetAdminLog
- [ ] GetMembers
- [ ] GetParticipants
- [ ] GetParticipantInfo
- [ ] ToggleAntiSpam
- [ ] ToggleJoinRequest
- [ ] ToggleJoinToSend
- [ ] ToggleNoForwards
- [ ] ToggleParticipantsHidden
- [ ] TogglePreHistoryHidden
- [ ] ToggleSignatures

### Forum Topics (9)
- [ ] CreateForumTopic
- [ ] CreateTopic
- [ ] EditForumTopic
- [ ] GetForumTopics
- [ ] PinForumTopic
- [ ] DeleteTopicHistory
- [ ] ReorderPinnedForumTopics
- [ ] ToggleForum
- [ ] ToggleViewForumAsMessages

### Dialogs & Folders (12)
- [ ] GetDialogs
- [ ] GetDialogUnreadMarksCount
- [ ] GetPinnedDialogs
- [ ] PinDialog
- [ ] UnpinDialog
- [ ] ReorderPinnedDialogs
- [ ] CreateFolder
- [ ] DeleteFolder
- [ ] GetFolders
- [ ] ReorderDialogFilters
- [ ] GetSuggestedFoldersCount
- [ ] GetDifferenceCheck

### Chat Lists (Folders v2) (7)
- [ ] ChatlistsCheckChatlistInvite
- [ ] ChatlistsEditExportedInvite
- [ ] ChatlistsGetChatlistUpdates
- [ ] ChatlistsGetLeaveChatlistSuggestions
- [ ] ChatlistsHideChatlistUpdates
- [ ] ChatlistsJoinChatlistUpdates
- [ ] ChatlistsLeaveChatlist
- [ ] DeleteChatlistInvite
- [ ] ExportChatlistInvite
- [ ] GetChatlistInvites
- [ ] JoinChatlistInvite

### Pin Messages (4)
- [ ] PinMessage
- [ ] UnpinMessage
- [ ] UnpinAllMessages
- [ ] GetCommonChats

### Stickers (20)
- [ ] FaveSticker
- [ ] GetAllStickerSets
- [ ] GetFavedStickers
- [ ] GetFeaturedStickersCount
- [ ] GetRecentStickersCount
- [ ] GetStickerSet
- [ ] SearchStickerSetsCount
- [ ] StickersAddStickerToSet
- [ ] StickersChangeSticker
- [ ] StickersChangeStickerPosition
- [ ] StickersCheckShortName
- [ ] StickersCreateStickerSet
- [ ] StickersDeleteStickerSet
- [ ] StickersRemoveStickerFromSet
- [ ] StickersRenameStickerSet
- [ ] StickersReplaceSticker
- [ ] StickersSetStickerSetThumb
- [ ] StickersSuggestShortName

### Stories (30)
- [ ] SendStory
- [ ] SendStoryWithPhoto
- [ ] DeleteStories
- [ ] ReactToStory
- [ ] GetAllStories
- [ ] GetPeerStories
- [ ] GetPinnedStories
- [ ] GetStoryViews
- [ ] StoriesActivateStealthMode
- [ ] StoriesCanSendStory
- [ ] StoriesCreateAlbum
- [ ] StoriesDeleteAlbum
- [ ] StoriesEditStory
- [ ] StoriesExportStoryLink
- [ ] StoriesGetAlbums
- [ ] StoriesGetAlbumStories
- [ ] StoriesGetAllReadPeerStories
- [ ] StoriesGetChatsToSend
- [ ] StoriesGetPeerMaxIDs
- [ ] StoriesGetStoriesArchive
- [ ] StoriesGetStoriesByID
- [ ] StoriesGetStoryReactionsList
- [ ] StoriesGetStoryViewsList
- [ ] StoriesIncrementStoryViews
- [ ] StoriesReadStories
- [ ] StoriesReorderAlbums
- [ ] StoriesReport
- [ ] StoriesSearchPosts
- [ ] StoriesStartLive
- [ ] StoriesToggleAllStoriesHidden
- [ ] StoriesTogglePeerStoriesHidden
- [ ] StoriesTogglePinned
- [ ] StoriesTogglePinnedToTop
- [ ] StoriesUpdateAlbum

### Phone Calls — Private (13)
- [ ] AcceptCall
- [ ] DeclineCall
- [ ] StartCall
- [ ] EndCall
- [ ] GetCallConfig
- [ ] SendCallRating
- [ ] SendAudioFrame
- [ ] SendVideoFrame
- [ ] SendVideoFrameYUV
- [ ] SendScreenFrame
- [ ] SendScreenFrameYUV
- [ ] SetAudioFrameDuration
- [ ] SetCallMuted
- [ ] SetCallVideo

### Phone Calls — Callbacks & Codecs (7)
- [ ] SetOnAudioFrame
- [ ] SetOnDecodedScreenFrame
- [ ] SetOnDecodedVideoFrame
- [ ] SetOnScreenFrame
- [ ] SetOnVideoFrame
- [ ] SetVideoDecoderFactory
- [ ] SetVideoEncoderFactory

### Phone Calls — Call Recording & Screen Share (6)
- [ ] StartCallRecording
- [ ] StopCallRecording
- [ ] StartScreenShare
- [ ] StopScreenShare
- [ ] StartGroupCallScreenShare
- [ ] StopGroupCallScreenShare
- [ ] SetEchoMode

### Phone — Group Calls (30)
- [ ] CreateGroupCall
- [ ] CreateScheduledGroupCall
- [ ] StartScheduledGroupCall
- [ ] JoinGroupCall
- [ ] JoinGroupCallWithVideo
- [ ] LeaveGroupCall
- [ ] ToggleGroupCallVideo
- [ ] SetGroupCallMuted
- [ ] SetGroupCallParticipantVolume
- [ ] GetGroupCall
- [ ] GetGroupCallStreamChannels
- [ ] GetGroupCallStreamRtmpURL
- [ ] PhoneCheckGroupCall
- [ ] PhoneCreateConferenceCall
- [ ] PhoneCreateGroupCall
- [ ] PhoneDeclineConferenceCallInvite
- [ ] PhoneDeleteConferenceCallParticipants
- [ ] PhoneDeleteGroupCallMessages
- [ ] PhoneDeleteGroupCallParticipantMessages
- [ ] PhoneDiscardGroupCall
- [ ] PhoneEditGroupCallParticipant
- [ ] PhoneEditGroupCallTitle
- [ ] PhoneExportGroupCallInvite
- [ ] PhoneGetGroupCall
- [ ] PhoneGetGroupCallChainBlocks
- [ ] PhoneGetGroupCallJoinAs
- [ ] PhoneGetGroupCallStars
- [ ] PhoneGetGroupCallStreamChannels
- [ ] PhoneGetGroupCallStreamRtmpURL
- [ ] PhoneGetGroupParticipants
- [ ] PhoneInviteConferenceCallParticipant
- [ ] PhoneInviteToGroupCall
- [ ] PhoneJoinGroupCall
- [ ] PhoneJoinGroupCallPresentation
- [ ] PhoneLeaveGroupCall
- [ ] PhoneLeaveGroupCallPresentation
- [ ] PhoneReceivedCall
- [ ] PhoneSaveCallDebug
- [ ] PhoneSaveCallLog
- [ ] PhoneSaveDefaultGroupCallJoinAs
- [ ] PhoneSaveDefaultSendAs
- [ ] PhoneSendConferenceCallBroadcast
- [ ] PhoneSendGroupCallEncryptedMessage
- [ ] PhoneSendGroupCallMessage
- [ ] PhoneSetCallRating
- [ ] PhoneStartScheduledGroupCall
- [ ] PhoneToggleGroupCallRecord
- [ ] PhoneToggleGroupCallSettings
- [ ] PhoneToggleGroupCallStartSubscription

### Bots API (36)
- [ ] BotsAddPreviewMedia
- [ ] BotsAllowSendMessage
- [ ] BotsAnswerWebhookJSONQuery
- [ ] BotsCanSendMessage
- [ ] BotsCheckDownloadFileParams
- [ ] BotsCheckUsername
- [ ] BotsCreateBot
- [ ] BotsDeletePreviewMedia
- [ ] BotsEditPreviewMedia
- [ ] BotsExportBotToken
- [ ] BotsGetAdminedBots
- [ ] BotsGetBotCommands
- [ ] BotsGetBotInfo
- [ ] BotsGetBotMenuButton
- [ ] BotsGetBotRecommendations
- [ ] BotsGetPopularAppBots
- [ ] BotsGetPreviewInfo
- [ ] BotsGetPreviewMedias
- [ ] BotsGetRequestedWebViewButton
- [ ] BotsInvokeWebViewCustomMethod
- [ ] BotsReorderPreviewMedias
- [ ] BotsReorderUsernames
- [ ] BotsRequestWebViewButton
- [ ] BotsResetBotCommands
- [ ] BotsSendCustomRequest
- [ ] BotsSetBotBroadcastDefaultAdminRights
- [ ] BotsSetBotCommands
- [ ] BotsSetBotGroupDefaultAdminRights
- [ ] BotsSetBotInfo
- [ ] BotsSetBotMenuButton
- [ ] BotsSetCustomVerification
- [ ] BotsToggleUserEmojiStatusPermission
- [ ] BotsToggleUsername
- [ ] BotsUpdateStarRefProgram
- [ ] BotsUpdateUserEmojiStatus

### File Upload & Download (12)
- [ ] DownloadFile
- [ ] UploadFile
- [ ] UploadGetCDNFile
- [ ] UploadGetCDNFileHashes
- [ ] UploadGetFile
- [ ] UploadGetFileHashes
- [ ] UploadGetWebFile
- [ ] UploadReuploadCDNFile
- [ ] UploadSaveBigFilePart
- [ ] UploadSaveFilePart

### Stats & Analytics (6)
- [ ] GetBroadcastStats
- [ ] GetMegagroupStats
- [ ] StatsGetMessagePublicForwards
- [ ] StatsGetMessageStats
- [ ] StatsGetStoryPublicForwards
- [ ] StatsGetStoryStats
- [ ] StatsLoadAsyncGraph

### Localization (langpack) (5)
- [ ] LangpackGetDifference
- [ ] LangpackGetLangPack
- [ ] LangpackGetLanguage
- [ ] LangpackGetLanguages
- [ ] LangpackGetStrings

### Help & Config (21)
- [ ] GetAppConfig
- [ ] GetAppConfigCheck
- [ ] GetConfig
- [ ] GetConfigDCCount
- [ ] GetCountriesList
- [ ] GetNearestDC
- [ ] GetSendAs
- [ ] GetSessions
- [ ] GetTopPeersCount
- [ ] GetBirthdaysCount
- [ ] GetAccountTTL
- [ ] SetAccountTTL
- [ ] GetPeerSettingsCheck
- [ ] GetChannelDifference
- [ ] HelpAcceptTermsOfService
- [ ] HelpDismissSuggestion
- [ ] HelpEditUserInfo
- [ ] HelpGetAppUpdate
- [ ] HelpGetCDNConfig
- [ ] HelpGetDeepLinkInfo
- [ ] HelpGetInviteText
- [ ] HelpGetPassportConfig
- [ ] HelpGetPeerColors
- [ ] HelpGetPeerProfileColors
- [ ] HelpGetPremiumPromo
- [ ] HelpGetPromoData
- [ ] HelpGetRecentMeURLs
- [ ] HelpGetSupport
- [ ] HelpGetSupportName
- [ ] HelpGetTermsOfServiceUpdate
- [ ] HelpGetTimezonesList
- [ ] HelpGetUserInfo
- [ ] HelpHidePromoData
- [ ] HelpSaveAppLog
- [ ] HelpSetBotUpdatesStatus

### Autotranslation (1)
- [ ] ToggleAutotranslation

### JSON Invoke (1)
- [ ] InvokeJSON

### Test / Debug Helpers (13)
- [ ] TestAcceptCallRaw
- [ ] TestGetCallAudioSSRC
- [ ] TestGetCallInfo
- [ ] TestGetCallPCState
- [ ] TestGetCallStats
- [ ] TestGetGroupCallAccessHash
- [ ] TestGetSenderSSRCs
- [ ] TestHandleSignalingData
- [ ] TestSendRawSignaling
- [ ] TestSetSignalingInInterceptor
- [ ] TestSetSignalingOutInterceptor
- [ ] TestStartCallRaw
