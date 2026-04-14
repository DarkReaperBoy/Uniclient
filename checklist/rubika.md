# Rubika Checklist — 273 methods


## Core Interface
- [x] Capabilities
- [x] Close
- [x] Name
- [x] OnUpdate

## Authentication
- [x] Authenticate
- [x] Logout
- [x] SendCode
- [x] SignIn

## Dialogs & Chats
- [x] ArchiveChat
- [x] EditChatDescription
- [x] EditChatTitle
- [x] GetChatInfo
- [x] GetDialogs
- [x] LeaveChat
- [x] MuteChat

## Messaging
- [x] DeleteChatHistory
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
- [x] SendAudioOpus
- [x] SendChatActivity
- [x] SendContact
- [x] SendDocument
- [x] SendGif
- [x] SendGroupVoiceChatActivity
- [x] SendImageBase64
- [x] SendLocation
- [x] SendMessage
- [x] SendMusic
- [x] SendPhoto
- [x] SendSticker
- [x] SendTyping
- [x] SendVideoMessage
- [x] UnpinAllMessages
- [x] UnpinMessage

## Media & Files
- [x] DownloadFile
- [x] SendVideo
- [x] SendVoice
- [x] UploadFile

## Calls
- [x] AcceptCall
- [x] DeclineCall
- [x] EndCall
- [x] GetCallStats
- [x] SetCallMuted
- [x] StartCall

## Group Calls
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
- [x] ActionOnStickerSet
- [x] GetMyStickers
- [x] GetMyStickerSets
- [x] GetStickersByEmoji
- [x] GetStickersBySetIDs
- [x] GetStickerSetByID
- [x] GetTrendStickerSets
- [x] SearchStickers

## Profile & Settings
- [x] UpdateProfile
- [x] UpdateUsername

## Privacy
- [x] GetPrivacySetting
- [x] SetPrivacySetting

## Search
- [x] SearchContacts
- [x] SearchGlobalMessages
- [x] SearchMessages

## Rubino (Social)
- [x] RubinoAddComment
- [x] RubinoAddPicture
- [x] RubinoAddPost
- [x] RubinoAddPostViewCount
- [x] RubinoAddVideo
- [x] RubinoBookmarkPost
- [x] RubinoCreatePage
- [x] RubinoGetBlockedProfiles
- [x] RubinoGetBookmarkedPosts
- [x] RubinoGetComments
- [x] RubinoGetExplorePosts
- [x] RubinoGetMyArchiveStories
- [x] RubinoGetMyProfileInfo
- [x] RubinoGetPostByShareLink
- [x] RubinoGetProfileFollowers
- [x] RubinoGetProfileFollowings
- [x] RubinoGetProfileHighlights
- [x] RubinoGetProfileInfo
- [x] RubinoGetProfileList
- [x] RubinoGetProfilePosts
- [x] RubinoGetProfilesStories
- [x] RubinoGetRecentFollowingPosts
- [x] RubinoIsExistUsername
- [x] RubinoLikePostAction
- [x] RubinoRemovePage
- [x] RubinoRemoveRecord
- [x] RubinoRequestFollow
- [x] RubinoRequestUploadFile
- [x] RubinoSetBlockProfile
- [x] RubinoUpdateProfile
- [x] RubinoUploadFile

## Bot API
- [x] BotBanChatMember
- [x] BotCheckJoin
- [x] BotDeleteMessage
- [x] BotEditChatKeypad
- [x] BotEditMessageKeypad
- [x] BotEditMessageText
- [x] BotForwardMessage
- [x] BotGetChat
- [x] BotGetFile
- [x] BotGetMe
- [x] BotGetUpdates
- [x] BotRemoveKeypad
- [x] BotReplyMessage
- [x] BotRequestSendFile
- [x] BotSendContact
- [x] BotSendDocument
- [x] BotSendFile
- [x] BotSendGif
- [x] BotSendImage
- [x] BotSendLocation
- [x] BotSendMessage
- [x] BotSendMusic
- [x] BotSendPoll
- [x] BotSendSticker
- [x] BotSendVideo
- [x] BotSendVoice
- [x] BotSetCommands
- [x] BotUnbanChatMember
- [x] BotUpdateEndpoints
- [x] BotUploadFile

## Event Handlers
- [x] OnChatUpdates
- [x] OnRemoveNotifications
- [x] OnShowActivities
- [x] OnShowNotifications

## Queries & Info
- [x] GetAbsObjects
- [x] GetAvatars
- [x] GetBannedChannelMembers
- [x] GetBannedGroupMembers
- [x] GetChannelAdminAccessList
- [x] GetChannelAdminMembers
- [x] GetChannelAllMembers
- [x] GetChannelInfo
- [x] GetChannelLink
- [x] GetChatInfoByUsername
- [x] GetChatsUpdates
- [x] GetContactsUpdates
- [x] GetGroupAdminAccessList
- [x] GetGroupAdminMembers
- [x] GetGroupAllMembers
- [x] GetGroupDefaultAccess
- [x] GetGroupInfo
- [x] GetGroupLink
- [x] GetGroupMemberCount
- [x] GetGroupMentionList
- [x] GetGroupOnlineCount
- [x] GetGroupVoiceChatParticipants
- [x] GetGroupVoiceChatUpdates
- [x] GetGUID
- [x] GetJoinLinks
- [x] GetJoinRequests
- [x] GetLinkFromAppUrl
- [x] GetMessageReactions
- [x] GetMessagesByID
- [x] GetMessageShareURL
- [x] GetMessagesInterval
- [x] GetMessagesUpdates
- [x] GetMyGifSet
- [x] GetNewGroupLink
- [x] GetObjectByUsername
- [x] GetPollOptionVoters
- [x] GetPollStatus
- [x] GetProfileLinkItems
- [x] GetRelatedObjects
- [x] GetSuggestedFolders
- [x] GetTranscription
- [x] GetTwoPasscodeStatus
- [x] GetUserInfo

## Settings & Configuration
- [x] SetActionChat
- [x] SetBlockUser
- [x] SetChannelLink
- [x] SetChannelVoiceChatSetting
- [x] SetGroupAdmin
- [x] SetGroupDefaultAccess
- [x] SetGroupEventMessages
- [x] SetGroupLink
- [x] SetGroupReactions
- [x] SetGroupSlowModeTime
- [x] SetGroupVoiceChatSetting
- [x] SetSetting
- [x] SetupTwoStepVerification
- [x] SetVoiceChatState

## Deletion
- [x] DeleteAvatar
- [x] DeleteGroupAvatar
- [x] DeleteNoAccessGroupChat
- [x] DeleteUserChat
- [x] RemoveChannel
- [x] RemoveFromMyGifSet
- [x] RemoveGroup
- [x] RemoveGroupAdmin
- [x] RemoveReaction

## Creation
- [x] CreateChannelVoiceChat
- [x] CreateGroupVoiceChat
- [x] CreateJoinLink

## Editing
- [x] EditChannelInfo
- [x] EditFolder
- [x] EditGroupHistoryForNewMembers
- [x] EditGroupInfo

## Requests
- [x] RequestChangeObjectOwner
- [x] RequestDeleteAccount

## Join & Leave
- [x] JoinChannelAction
- [x] JoinChannelByLink
- [x] JoinGroup
- [x] JoinVoiceChat
- [x] LeaveChannelVoiceChat
- [x] LeaveGroup
- [x] LeaveGroupVoiceChat

## Event Handlers

## Other
- [x] AcceptRequestObjectOwning
- [x] ActionOnJoinRequest
- [x] AddChannelMembers
- [x] AddFolder
- [x] AddGroupMembers
- [x] AddToMyGifSet
- [x] AutoDeleteMessage
- [x] BanChannelMember
- [x] BanGroupMember
- [x] ChannelPreviewByJoinLink
- [x] CheckChannelUsername
- [x] CheckUserUsername
- [x] DiscardChannelVoiceChat
- [x] DiscardGroupVoiceChat
- [x] GroupPreviewByJoinLink
- [x] ImportContacts
- [x] LoadMoreParticipants
- [x] LoginDisableTwoStep
- [x] LoginTwoStepForgetPassword
- [x] OnAudioReceived
- [x] RawAPI
- [x] RejectRequestObjectOwning
- [x] ReportObject
- [x] ResetContacts
- [x] SeenChannelMessages
- [x] SeenChats
- [x] StartWebSocket
- [x] TerminateOtherSessions
- [x] TranscribeVoice
- [x] TurnOffTwoStep
- [x] UpdateChannelUsername
- [x] UploadAvatar
- [x] UserIsAdmin
