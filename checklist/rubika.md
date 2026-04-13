# Rubika — Fresh Checklist

**Methods:** 277 exported | **Lines:** 5,775 | **File:** `go/cores/rubika.go`
**Protocol:** Rubika (JSON-RPC over HTTPS, WebSocket, Iranian messenger)
**Last updated:** 2026-04-13

## Authentication & Session (10)
- [ ] Authenticate
- [ ] SendCode
- [ ] SignIn
- [ ] SetupTwoStepVerification
- [ ] TurnOffTwoStep
- [ ] LoginDisableTwoStep
- [ ] LoginTwoStepForgetPassword
- [ ] GetTwoPasscodeStatus
- [ ] Logout
- [ ] GetMySessions

## Core Interface (4)
- [ ] Capabilities
- [ ] Close
- [ ] GetGUID
- [ ] Name

## User Profile & Settings (10)
- [ ] GetProfile
- [ ] GetProfileLinkItems
- [ ] UpdateProfile
- [ ] UpdateUsername
- [ ] CheckUserUsername
- [ ] GetUserInfo
- [ ] SetSetting
- [ ] GetPrivacySetting
- [ ] SetPrivacySetting
- [ ] RegisterDevice

## Contacts (8)
- [ ] AddAddressBook
- [ ] AddContact
- [ ] DeleteContact
- [ ] GetContacts
- [ ] GetContactsUpdates
- [ ] ImportContacts
- [ ] ResetContacts
- [ ] SearchContacts

## Messaging — Send (16)
- [ ] SendMessage
- [ ] ReplyToMessage
- [ ] ForwardMessage
- [ ] SendPhoto
- [ ] SendVideo
- [ ] SendVideoMessage
- [ ] SendVoice
- [ ] SendAudioOpus
- [ ] SendMusic
- [ ] SendDocument
- [ ] SendGif
- [ ] SendSticker
- [ ] SendLocation
- [ ] SendContact
- [ ] SendImageBase64
- [ ] SendChatActivity

## Messaging — Edit, Delete & History (9)
- [ ] EditMessage
- [ ] DeleteMessage
- [ ] DeleteChatHistory
- [ ] DeleteUserChat
- [ ] DeleteNoAccessGroupChat
- [ ] AutoDeleteMessage
- [ ] GetMessages
- [ ] GetMessagesByID
- [ ] GetMessagesInterval

## Messaging — Read State & Reactions (8)
- [ ] MarkAsRead
- [ ] MarkUnread
- [ ] SeenChats
- [ ] GetReadState
- [ ] ReactToMessage
- [ ] RemoveReaction
- [ ] GetMessageReactions
- [ ] ClickMessageUrl

## Messaging — Pin & Search (6)
- [ ] PinMessage
- [ ] UnpinMessage
- [ ] UnpinAllMessages
- [ ] SearchMessages
- [ ] SearchChatMessages
- [ ] GetMessageShareURL

## Messaging — Activity & Typing (2)
- [ ] SendTyping
- [ ] OnShowActivities

## Files & Media (3)
- [ ] UploadFile
- [ ] DownloadFile
- [ ] GetTranscription

## Polls (4)
- [ ] CreatePoll
- [ ] VotePoll
- [ ] GetPollStatus
- [ ] GetPollOptionVoters

## Stickers & GIFs (11)
- [ ] ActionOnStickerSet
- [ ] GetMyStickers
- [ ] GetMyStickerSets
- [ ] GetStickersByEmoji
- [ ] GetStickersBySetIDs
- [ ] GetStickerSetByID
- [ ] GetTrendStickerSets
- [ ] SearchStickers
- [ ] GetMyGifSet
- [ ] AddToMyGifSet
- [ ] RemoveFromMyGifSet

## Chat Management (8)
- [ ] GetChatInfo
- [ ] GetChatInfoByUsername
- [ ] GetDialogs
- [ ] ArchiveChat
- [ ] MuteChat
- [ ] LeaveChat
- [ ] SetActionChat
- [ ] GetChatAds

## Group Management (22)
- [ ] CreateGroup
- [ ] RemoveGroup
- [ ] EditGroupInfo
- [ ] EditGroupHistoryForNewMembers
- [ ] GetGroupInfo
- [ ] GetGroupLink
- [ ] SetGroupLink
- [ ] GetNewGroupLink
- [ ] GetGroupAllMembers
- [ ] GetGroupAdminMembers
- [ ] GetGroupAdminAccessList
- [ ] GetGroupDefaultAccess
- [ ] SetGroupDefaultAccess
- [ ] GetGroupMemberCount
- [ ] GetGroupMentionList
- [ ] GetGroupOnlineCount
- [ ] SetGroupAdmin
- [ ] RemoveGroupAdmin
- [ ] SetGroupEventMessages
- [ ] SetGroupReactions
- [ ] SetGroupSlowModeTime
- [ ] DeleteGroupAvatar

## Group Membership (5)
- [ ] AddGroupMembers
- [ ] BanGroupMember
- [ ] GetBannedGroupMembers
- [ ] JoinGroup
- [ ] LeaveGroup

## Channel Management (12)
- [ ] CreateChannel
- [ ] RemoveChannel
- [ ] EditChannelInfo
- [ ] GetChannelInfo
- [ ] GetChannelLink
- [ ] SetChannelLink
- [ ] CheckChannelUsername
- [ ] UpdateChannelUsername
- [ ] GetChannelAllMembers
- [ ] GetChannelAdminMembers
- [ ] GetChannelAdminAccessList
- [ ] SeenChannelMessages

## Channel Membership (4)
- [ ] AddChannelMembers
- [ ] BanChannelMember
- [ ] GetBannedChannelMembers
- [ ] JoinChannelAction

## Unified Member Operations (7)
- [ ] AddMembers
- [ ] RemoveMember
- [ ] BanMember
- [ ] UnbanMember
- [ ] GetMembers
- [ ] SetAdmin
- [ ] UserIsAdmin

## Join Links & Requests (8)
- [ ] CreateJoinLink
- [ ] GetJoinLinks
- [ ] GetJoinRequests
- [ ] ActionOnJoinRequest
- [ ] JoinChannelByLink
- [ ] ChannelPreviewByJoinLink
- [ ] GroupPreviewByJoinLink
- [ ] GetInviteLink

## Chat Description & Title (2)
- [ ] EditChatDescription
- [ ] EditChatTitle

## Folders (6)
- [ ] AddFolder
- [ ] CreateFolder
- [ ] EditFolder
- [ ] DeleteFolder
- [ ] GetFolders
- [ ] GetSuggestedFolders

## Avatars (3)
- [ ] UploadAvatar
- [ ] DeleteAvatar
- [ ] GetAvatars

## Blocking (4)
- [ ] BlockUser
- [ ] UnblockUser
- [ ] SetBlockUser
- [ ] GetBlockedUsers

## Session Management (3)
- [ ] GetSessions
- [ ] TerminateSession
- [ ] TerminateOtherSessions

## Updates & WebSocket (7)
- [ ] StartWebSocket
- [ ] OnUpdate
- [ ] OnChatUpdates
- [ ] OnShowNotifications
- [ ] OnRemoveNotifications
- [ ] GetChatsUpdates
- [ ] GetMessagesUpdates

## Search — Global (3)
- [ ] SearchGlobal
- [ ] SearchGlobalMessages
- [ ] SearchGlobalObjects

## Object / Username Lookup (5)
- [ ] GetObjectByUsername
- [ ] GetLinkFromAppUrl
- [ ] GetAbsObjects
- [ ] GetRelatedObjects
- [ ] ReportObject

## Ownership Transfer (3)
- [ ] RequestChangeObjectOwner
- [ ] AcceptRequestObjectOwning
- [ ] RejectRequestObjectOwning

## Account Deletion (1)
- [ ] RequestDeleteAccount

## Topics (1)
- [ ] CreateTopic

## Transcription (1)
- [ ] TranscribeVoice

## Time (1)
- [ ] GetTime

## Raw API (1)
- [ ] RawAPI

## Voice Chat — Group (8)
- [ ] CreateGroupVoiceChat
- [ ] DiscardGroupVoiceChat
- [ ] JoinVoiceChat
- [ ] LeaveGroupVoiceChat
- [ ] SetGroupVoiceChatSetting
- [ ] GetGroupVoiceChatParticipants
- [ ] GetGroupVoiceChatUpdates
- [ ] SendGroupVoiceChatActivity

## Voice Chat — Channel (4)
- [ ] CreateChannelVoiceChat
- [ ] DiscardChannelVoiceChat
- [ ] LeaveChannelVoiceChat
- [ ] SetChannelVoiceChatSetting

## Voice Chat — Unified (3)
- [ ] JoinGroupCall
- [ ] SetVoiceChatState
- [ ] LoadMoreParticipants

## Calls (7)
- [ ] StartCall
- [ ] AcceptCall
- [ ] DeclineCall
- [ ] EndCall
- [ ] SetCallMuted
- [ ] GetCallStats
- [ ] OnAudioReceived

## Bot API (30)
- [ ] BotUpdateEndpoints
- [ ] BotGetMe
- [ ] BotGetUpdates
- [ ] BotGetChat
- [ ] BotCheckJoin
- [ ] BotSendMessage
- [ ] BotReplyMessage
- [ ] BotForwardMessage
- [ ] BotEditMessageText
- [ ] BotDeleteMessage
- [ ] BotSendFile
- [ ] BotRequestSendFile
- [ ] BotUploadFile
- [ ] BotGetFile
- [ ] BotSendImage
- [ ] BotSendVideo
- [ ] BotSendGif
- [ ] BotSendDocument
- [ ] BotSendMusic
- [ ] BotSendVoice
- [ ] BotSendSticker
- [ ] BotSendPoll
- [ ] BotSendLocation
- [ ] BotSendContact
- [ ] BotEditChatKeypad
- [ ] BotEditMessageKeypad
- [ ] BotRemoveKeypad
- [ ] BotSetCommands
- [ ] BotBanChatMember
- [ ] BotUnbanChatMember

## Rubino (Social Platform) (31)
- [ ] RubinoAddComment
- [ ] RubinoAddPicture
- [ ] RubinoAddPost
- [ ] RubinoAddPostViewCount
- [ ] RubinoAddVideo
- [ ] RubinoBookmarkPost
- [ ] RubinoCreatePage
- [ ] RubinoGetBlockedProfiles
- [ ] RubinoGetBookmarkedPosts
- [ ] RubinoGetComments
- [ ] RubinoGetExplorePosts
- [ ] RubinoGetMyArchiveStories
- [ ] RubinoGetMyProfileInfo
- [ ] RubinoGetPostByShareLink
- [ ] RubinoGetProfileFollowers
- [ ] RubinoGetProfileFollowings
- [ ] RubinoGetProfileHighlights
- [ ] RubinoGetProfileInfo
- [ ] RubinoGetProfileList
- [ ] RubinoGetProfilePosts
- [ ] RubinoGetProfilesStories
- [ ] RubinoGetRecentFollowingPosts
- [ ] RubinoIsExistUsername
- [ ] RubinoLikePostAction
- [ ] RubinoRemovePage
- [ ] RubinoRemoveRecord
- [ ] RubinoRequestFollow
- [ ] RubinoRequestUploadFile
- [ ] RubinoSetBlockProfile
- [ ] RubinoUpdateProfile
- [ ] RubinoUploadFile
