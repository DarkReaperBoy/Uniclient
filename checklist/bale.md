# Bale Checklist — 456 methods


## Core Interface
- [x] Capabilities
- [x] Close
- [x] Name
- [x] OnUpdate

## Authentication
- [x] Authenticate
- [x] ChangePhone
- [x] Logout

## Dialogs & Chats
- [x] ArchiveChat
- [x] EditChatDescription
- [x] EditChatTitle
- [x] GetChatInfo
- [x] GetDialogs
- [x] LeaveChat
- [x] MuteChat

## Messaging
- [x] DeleteMessage
- [x] EditMessage
- [x] ForwardMessage
- [x] GetMessages
- [x] GetReadState
- [x] MarkAsRead
- [x] MarkUnread
- [x] PinMessage
- [x] ReactToMessage
- [x] ReplyToMessage
- [x] SendAnimatedSticker
- [x] SendAnimation
- [x] SendBankMessage
- [x] SendChangePhoneVerificationCode
- [x] SendChatAction
- [x] SendContact
- [x] SendDeleteAccountVerificationCode
- [x] SendDocument
- [x] SendImageBase64
- [x] SendJsonMessage
- [x] SendLiveMessage
- [x] SendLocation
- [x] SendLongTextMessage
- [x] SendMediaGroup
- [x] SendMessage
- [x] SendMessageWithKeyboard
- [x] SendOrderMessage
- [x] SendPhoto
- [x] SendProtectedMessage
- [x] SendRamzOTP
- [x] SendScheduledMessage
- [x] SendSticker
- [x] SendTyping
- [x] SendVenue
- [x] UnpinAllMessages
- [x] UnpinMessage

## Media & Files
- [x] DownloadFile
- [x] GetFile
- [x] SendAudio
- [x] SendVideo
- [x] SendVideoNote
- [x] SendVoice
- [x] UploadFile

## Calls
- [x] AcceptCall
- [x] AnswerCallbackQuery
- [x] DeclineCall
- [x] DiscardCall
- [x] EndCall
- [x] GetCallLogs
- [x] GetOngoingCalls
- [x] ReceiveCall
- [x] SetCallMuted
- [x] StartCall

## Group Calls
- [x] GetGroupCall
- [x] JoinGroupCall

## Groups & Channels
- [x] CreateChannel
- [x] CreateGroup
- [x] CreateTopic

## Members & Admin
- [x] AddMembers
- [x] BanMember
- [x] GetInviteLink
- [x] GetMembers
- [x] RemoveMember
- [x] SetAdmin
- [x] UnbanMember

## Contacts & Users
- [x] AddContact
- [x] BlockUser
- [x] DeleteContact
- [x] GetBlockedUsers
- [x] GetContacts
- [x] GetProfile
- [x] SearchGlobal
- [x] UnblockUser

## Folders
- [x] CreateFolder
- [x] DeleteFolder
- [x] GetFolders

## Sessions
- [x] GetSessions
- [x] TerminateSession

## Polls
- [x] CreatePoll
- [x] VotePoll

## Stickers
- [x] AddStickerToSet
- [x] CreateNewStickerSet
- [x] DeleteStickerFromSet
- [x] GetStickerSet
- [x] UploadStickerFile

## Forum Topics
- [x] DeleteTopic
- [x] EditTopic

## Profile & Settings
- [x] GetFullUser

## Privacy
- [x] GetUserFullPrivacy
- [x] GetUserPrivacyStatus
- [x] SetUserPrivacyStatus

## Search
- [x] SearchLinks
- [x] SearchMembers
- [x] SearchMessages
- [x] SearchPeerMedia
- [x] SearchPeerMessages

## Chat Invites & Lists
- [x] CreateChatInviteLink
- [x] ExportChatInviteLink

## User API
- [x] UserAcceptCallMeet
- [x] UserAddBotStory
- [x] UserAddChannelStory
- [x] UserAddContact
- [x] UserAddDiscussionGroupAdmin
- [x] UserAddGif
- [x] UserAddStickerCollection
- [x] UserAddStickerPack
- [x] UserAddStory
- [x] UserAIGetTranscript
- [x] UserAISendEvent
- [x] UserAnswerCallJoinRequest
- [x] UserArchiveDialogs
- [x] UserAskToJoinCall
- [x] UserBlockUser
- [x] UserCanAddBotStory
- [x] UserCancelMessageStream
- [x] UserCheckNickName
- [x] UserCheckStoryLinkValidity
- [x] UserClearChat
- [x] UserClosePollService
- [x] UserCreateFolder
- [x] UserCreateGroup
- [x] UserCreateGroupFull
- [x] UserCreatePoll
- [x] UserCreateReservedFolder
- [x] UserCreateThread
- [x] UserCreateTopic
- [x] UserDeleteCallLogs
- [x] UserDeleteChat
- [x] UserDeleteMessage
- [x] UserDeleteMyCommands
- [x] UserDeleteStream
- [x] UserEditAbout
- [x] UserEditChannelNick
- [x] UserEditGroupAbout
- [x] UserEditGroupAvatar
- [x] UserEditGroupDefaultCardNumber
- [x] UserEditGroupTitle
- [x] UserEditLocalName
- [x] UserEditName
- [x] UserEditNickName
- [x] UserEditParameter
- [x] UserEnableShowReactionFlag
- [x] UserExecuteTaskNow
- [x] UserFetchGroupAdmins
- [x] UserFetchProtectedMessage
- [x] UserFileUploadCancel
- [x] UserForwardMessages
- [x] UserGenerateCallLink
- [x] UserGetActiveSharedMedia
- [x] UserGetAnonymousContactPage
- [x] UserGetBannedUsers
- [x] UserGetBotGroupPermissions
- [x] UserGetBotInfo
- [x] UserGetBots
- [x] UserGetBotStories
- [x] UserGetBotWhiteList
- [x] UserGetCallLinkDetails
- [x] UserGetCallState
- [x] UserGetCanSeeMessages
- [x] UserGetChannelRecommendations
- [x] UserGetChannelStories
- [x] UserGetContacts
- [x] UserGetContactsPresences
- [x] UserGetDefaultStoryBackgrounds
- [x] UserGetDifference
- [x] UserGetDiscussionMessage
- [x] UserGetFileUploadURL
- [x] UserGetFileURL
- [x] UserGetFullGroup
- [x] UserGetFullPollResultService
- [x] UserGetGroupDefaultCardNumber
- [x] UserGetGroupInviteURL
- [x] UserGetGroupMembersCount
- [x] UserGetGroupMembersPresences
- [x] UserGetGroupOnlineCount
- [x] UserGetGroupPreview
- [x] UserGetGroupRecommendations
- [x] UserGetGroupsRecommendation
- [x] UserGetInlineBotResults
- [x] UserGetLinkPreview
- [x] UserGetLinkStatus
- [x] UserGetLinkSummary
- [x] UserGetLLMAuthToken
- [x] UserGetMemberPermissions
- [x] UserGetMenuButton
- [x] UserGetMessageSeenList
- [x] UserGetMessagesRepliesInfo
- [x] UserGetMessageViews
- [x] UserGetMiniAppUrlAppzar
- [x] UserGetMostPopularStories
- [x] UserGetMutualGroups
- [x] UserGetMyCommands
- [x] UserGetMyGroups
- [x] UserGetMyUpvotes
- [x] UserGetNasimFilePublicUrl
- [x] UserGetNasimFileUploadResume
- [x] UserGetNasimFileUrls
- [x] UserGetOrganizationalContacts
- [x] UserGetOrganizationInfo
- [x] UserGetParameters
- [x] UserGetPaymentDetails
- [x] UserGetPins
- [x] UserGetPollResultsService
- [x] UserGetReactions
- [x] UserGetReactionsList
- [x] UserGetRelatedChannels
- [x] UserGetRelatedGroups
- [x] UserGetSavedGifs
- [x] UserGetShowReactionFlag
- [x] UserGetSimilarPosts
- [x] UserGetStories
- [x] UserGetStoriesByList
- [x] UserGetStoryByID
- [x] UserGetStoryPrivacyConfig
- [x] UserGetStoryReactionEmojis
- [x] UserGetStoryTags
- [x] UserGetStoryViewers
- [x] UserGetStoryViewersCount
- [x] UserGetStoryWidgets
- [x] UserGetTopicByID
- [x] UserGetTopics
- [x] UserGetTopPeer
- [x] UserGetUserContext
- [x] UserGetUsersPresence
- [x] UserGetUserStoryConfig
- [x] UserGetWebappHash
- [x] UserHTTPPost
- [x] UserImportContacts
- [x] UserInviteToCall
- [x] UserInviteUser
- [x] UserInviteUsers
- [x] UserInvokeCustomAction
- [x] UserInvokeCustomMethodAppzar
- [x] UserJoinGroup
- [x] UserJoinPublicGroup
- [x] UserKickUser
- [x] UserLeaveGroup
- [x] UserListScheduledTasks
- [x] UserLoadBlockedUsers
- [x] UserLoadCategoryFeedMessages
- [x] UserLoadDialogs
- [x] UserLoadDialogsFiltered
- [x] UserLoadFeedMessages
- [x] UserLoadFolderDialogs
- [x] UserLoadFullGroups
- [x] UserLoadFullUsers
- [x] UserLoadGroupAvatars
- [x] UserLoadGroupedDialogs
- [x] UserLoadGroups
- [x] UserLoadHistory
- [x] UserLoadInternalFeedMessages
- [x] UserLoadMagazineCategories
- [x] UserLoadMembers
- [x] UserLoadOwnStickers
- [x] UserLoadPeerDialogs
- [x] UserLoadPeers
- [x] UserLoadPinnedDialogs
- [x] UserLoadPinnedMessages
- [x] UserLoadReactions
- [x] UserLoadReplies
- [x] UserLoadSharedMedia
- [x] UserLoadStickerCollection
- [x] UserLoadUsers
- [x] UserMakePayment
- [x] UserMakeUserAdmin
- [x] UserMarkAsUnread
- [x] UserMarkDialogsAsRead
- [x] UserMentionRead
- [x] UserMessageReactionsRead
- [x] UserMessageRead
- [x] UserMessageReceived
- [x] UserMuteCallParticipant
- [x] UserPeersWithScheduleTask
- [x] UserPinDialogs
- [x] UserPinMessage
- [x] UserPushSetConfig
- [x] UserReactToStory
- [x] UserReceiveMessageStream
- [x] UserRemoveAllPins
- [x] UserRemoveCallParticipant
- [x] UserRemoveContact
- [x] UserRemoveDiscussionGroup
- [x] UserRemoveGif
- [x] UserRemoveGroupAvatar
- [x] UserRemovePin
- [x] UserRemoveReaction
- [x] UserRemoveStickerCollection
- [x] UserRemoveStickerPack
- [x] UserRemoveStory
- [x] UserRemoveTopPeer
- [x] UserRemoveUserAdmin
- [x] UserReorderPinnedDialogs
- [x] UserReScheduleTask
- [x] UserResetContacts
- [x] UserRevokeInviteURL
- [x] UserScheduleTask
- [x] UserSearchContacts
- [x] UserSearchContent
- [x] UserSearchDialog
- [x] UserSearchMediaService
- [x] UserSearchMembersService
- [x] UserSearchMessageMore
- [x] UserSearchMessages
- [x] UserSearchPeer
- [x] UserSendAnimatedSticker
- [x] UserSendAuthenticatedInlineCallBackData
- [x] UserSendBankMessage
- [x] UserSendCallFanoosEvent
- [x] UserSendCallReaction
- [x] UserSendInlineCallback
- [x] UserSendInlineCallBackData
- [x] UserSendJsonMessage
- [x] UserSendLiveMessage
- [x] UserSendLongTextMessage
- [x] UserSendMessage
- [x] UserSendMiniAppData
- [x] UserSendMultiMediaMessage
- [x] UserSendOrderMessage
- [x] UserSendProtectedMessage
- [x] UserSendRaw
- [x] UserSendScheduledMessage
- [x] UserSetAvailableReactions
- [x] UserSetCallLinkTitle
- [x] UserSetCanSeeHistory
- [x] UserSetCanSeeMessages
- [x] UserSetDiscussionGroup
- [x] UserSetGroupDefaultPermissions
- [x] UserSetMemberCustomTitle
- [x] UserSetMemberPermissions
- [x] UserSetMyCommands
- [x] UserSetOnline
- [x] UserSetReaction
- [x] UserSetRestriction
- [x] UserSetStoryPrivacyConfig
- [x] UserSetUserStoryConfig
- [x] UserSignOut
- [x] UserSignUp
- [x] UserStartRecording
- [x] UserStartStream
- [x] UserStopRecording
- [x] UserStopTyping
- [x] UserSubmitCallFeedback
- [x] UserSubscribeFromGroupOnline
- [x] UserSubscribeFromOnline
- [x] UserSubscribeToGroupOnline
- [x] UserSubscribeToOnline
- [x] UserSubscribeToThreadUpdates
- [x] UserSubscribeToUpdates
- [x] UserTakeCallAction
- [x] UserTerminateSession
- [x] UserTransferOwnership
- [x] UserTyping
- [x] UserUnArchiveDialogs
- [x] UserUnBanUser
- [x] UserUnblockUser
- [x] UserUnpinDialogs
- [x] UserUnPinMessages
- [x] UserUnScheduleTask
- [x] UserUnsubscribeFromThreadUpdates
- [x] UserUpdateCallLayout
- [x] UserUpdateMessage
- [x] UserUpdateSearchContentClick
- [x] UserUseGif
- [x] UserValidatePassword
- [x] UserVotePollService

## Fanoos Analytics
- [x] FanoosSend

## Push Notifications
- [x] PushSetConfig
- [x] RegisterGooglePush
- [x] RegisterPush
- [x] UnregisterAllPushCredentials
- [x] UnregisterGooglePush
- [x] UnregisterPush

## Upvotes
- [x] GetMessageUpvoters
- [x] RevokeUpvotedPost
- [x] UpvotePost

## Queries & Info
- [x] GetChat
- [x] GetChatAdministrators
- [x] GetChatMember
- [x] GetChatMembersCount
- [x] GetFullPollResult
- [x] GetInAppUpdate
- [x] GetMiniAppUrl
- [x] GetMyCommands
- [x] GetPollResults
- [x] GetTranscript
- [x] GetUpdates
- [x] GetUserID
- [x] GetUserProfilePhotos
- [x] GetWebhookInfo
- [x] GetWssURL

## Settings & Configuration
- [x] SetChatPhoto
- [x] SetMyCommands
- [x] SetNewPassword
- [x] SetRamzPassword
- [x] SetWebhook

## Deletion
- [x] DeleteAccount
- [x] DeleteChatPhoto
- [x] DeleteMyCommands
- [x] DeleteRamzPassword
- [x] DeleteWebhook
- [x] RemoveAvatar

## Editing
- [x] EditAvatarGRPC
- [x] EditBirthDate
- [x] EditFolder
- [x] EditMessageCaption
- [x] EditMessageReplyMarkup
- [x] EditMyPreferredLanguages
- [x] EditMyTimeZone
- [x] EditSex

## Read State
- [x] MarkAsUnread

## Other
- [x] AnswerInlineQuery
- [x] ChangePhoneNumber
- [x] CheckRamzPassword
- [x] CheckRamzPasswordSet
- [x] ClosePoll
- [x] ConfirmPhoneNumber
- [x] CopyMessage
- [x] DisableTwoFactorAuthentication
- [x] EnableTwoFactorAuthentication
- [x] ForgetRamzPassword
- [x] GlobalChannelSearch
- [x] InviteUser
- [x] InvokeCustomMethod
- [x] IsNameAllowed
- [x] IsTwoFactorAuthenticationEnabled
- [x] LoadAvatars
- [x] LoadDialogsFiltered
- [x] LoadFolders
- [x] NotifyAboutDeviceInfo
- [x] PromoteChatMember
- [x] RecoverPassword
- [x] ReorderFolders
- [x] ReportDismiss
- [x] ReportInappropriateContent
- [x] ResolveGroupID
- [x] RestrictChatMember
- [x] TerminateAllSessions
- [x] UploadRawPUT
- [x] ValidateRamzOTP
- [x] VerifyEmail
- [x] VerifyPasswordRecovery

## Bots
- [x] GetBotMenuButtons
