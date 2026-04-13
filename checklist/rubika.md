## Phase 4: Rubika — DONE

230 exported methods, ~4,808 lines. 84 + 2 call + 3 two-user call = 89 tests ALL PASS.
All methods from rubpy/RubikaLib implemented including Rubino social media API.
WebRTC voice chat with bidirectional Opus audio verified (2-user, 635+ RTP packets each direction).

### Core Interface (55/55)

- [x] Name
- [x] Capabilities
- [x] Authenticate
- [x] Logout
- [x] GetDialogs
- [x] CreateGroup
- [x] CreateChannel
- [x] CreateTopic
- [x] GetFolders
- [x] CreateFolder
- [x] SendMessage
- [x] GetMessages
- [x] EditMessage
- [x] DeleteMessage
- [x] ReplyToMessage
- [x] ForwardMessage
- [x] ReactToMessage
- [x] PinMessage
- [x] UnpinMessage
- [x] MarkAsRead
- [x] GetReadState
- [x] UploadFile
- [x] DownloadFile
- [x] SendImageBase64
- [x] StartCall
- [x] JoinGroupCall
- [x] EndCall
- [x] SetCallMuted
- [x] GetProfile
- [x] OnUpdate
- [x] Close
- [x] GetChatInfo
- [x] EditChatTitle
- [x] EditChatDescription
- [x] LeaveChat
- [x] GetInviteLink
- [x] AddMembers
- [x] RemoveMember
- [x] BanMember
- [x] UnbanMember
- [x] GetMembers
- [x] SetAdmin
- [x] GetContacts
- [x] AddContact
- [x] DeleteContact
- [x] BlockUser
- [x] UnblockUser
- [x] GetBlockedUsers
- [x] SearchMessages
- [x] SearchGlobal
- [x] SendTyping
- [x] CreatePoll
- [x] VotePoll
- [x] SendSticker
- [x] GetSessions
- [x] TerminateSession

### Auth & Session

- [x] SendCode
- [x] SignIn
- [x] GetMySessions
- [x] TerminateOtherSessions
- [x] StartWebSocket
- [x] GetGUID
- [x] RawAPI

### Group Management

- [x] GetGroupInfo
- [x] AddGroupMembers
- [x] GetGroupAllMembers
- [x] SetGroupAdmin
- [x] BanGroupMember
- [x] EditGroupInfo
- [x] JoinGroup
- [x] LeaveGroup
- [x] RemoveGroup
- [x] DeleteNoAccessGroupChat
- [x] GetGroupLink
- [x] SetGroupLink
- [x] GetGroupAdminMembers
- [x] GetGroupAdminAccessList
- [x] GetBannedGroupMembers
- [x] GetGroupDefaultAccess
- [x] SetGroupDefaultAccess
- [x] GetGroupMentionList
- [x] GetGroupOnlineCount
- [x] GroupPreviewByJoinLink

### Channel Management

- [x] GetChannelInfo
- [x] AddChannelMembers
- [x] GetChannelAllMembers
- [x] BanChannelMember
- [x] EditChannelInfo
- [x] JoinChannelAction
- [x] RemoveChannel
- [x] GetChannelLink
- [x] SetChannelLink
- [x] GetChannelAdminMembers
- [x] GetChannelAdminAccessList
- [x] ChannelPreviewByJoinLink
- [x] JoinChannelByLink
- [x] SeenChannelMessages
- [x] UpdateChannelUsername
- [x] CheckChannelUsername

### Message Operations (extended)

- [x] GetMessagesByID
- [x] GetMessagesInterval
- [x] GetMessagesUpdates
- [x] AutoDeleteMessage
- [x] SendChatActivity
- [x] SetActionChat
- [x] GetMessageReactions
- [x] RemoveReaction

### Folder Management

- [x] DeleteFolder
- [x] GetSuggestedFolders

### File Operations

(covered by Core interface UploadFile/DownloadFile/SendImageBase64)

### Poll Operations

- [x] GetPollStatus
- [x] GetPollOptionVoters

### Sticker Operations

- [x] GetMyStickerSets
- [x] GetMyStickers
- [x] SearchStickers
- [x] GetStickerSetByID
- [x] GetStickersByEmoji
- [x] GetStickersBySetIDs
- [x] GetTrendStickerSets
- [x] ActionOnStickerSet

### GIF Operations

- [x] GetMyGifSet
- [x] AddToMyGifSet
- [x] RemoveFromMyGifSet

### User Profile & Contacts

- [x] UpdateProfile
- [x] UpdateUsername
- [x] CheckUserUsername
- [x] GetAvatars
- [x] DeleteAvatar
- [x] UploadAvatar
- [x] GetProfileLinkItems
- [x] AddAddressBook
- [x] GetContactsUpdates
- [x] ResetContacts
- [x] SetBlockUser
- [x] UserIsAdmin

### Search Operations

- [x] SearchGlobalObjects
- [x] SearchChatMessages

### Object & Link Operations

- [x] GetObjectByUsername
- [x] GetAbsObjects
- [x] GetLinkFromAppUrl
- [x] GetTime
- [x] GetMessageShareURL
- [x] GetRelatedObjects
- [x] GetChatsUpdates
- [x] DeleteChatHistory

### Voice Chat Operations

- [x] CreateGroupVoiceChat
- [x] CreateChannelVoiceChat
- [x] LeaveGroupVoiceChat
- [x] DiscardGroupVoiceChat
- [x] LeaveChannelVoiceChat
- [x] DiscardChannelVoiceChat
- [x] LoadMoreParticipants
- [x] SetGroupVoiceChatSetting
- [x] SetChannelVoiceChatSetting
- [x] GetGroupVoiceChatUpdates
- [x] GetGroupVoiceChatParticipants
- [x] JoinVoiceChat
- [x] SetVoiceChatState
- [x] SendGroupVoiceChatActivity

### WebRTC Call Integration (Core interface)

- [x] StartCall — creates voice chat + joins with pion/webrtc, Opus audio, Janus AudioBridge
- [x] JoinGroupCall — discovers active VC + joins with WebRTC
- [x] EndCall — leaves + discards + closes PeerConnection
- [x] SetCallMuted — toggles mute flag
- [x] Heartbeat loop (sendGroupVoiceChatActivity every 1s)
- [x] Updates polling loop (getGroupVoiceChatUpdates every 3s)
- [x] Silence sender (Opus silence frames every 20ms)

### Voice Transcription

- [x] TranscribeVoice
- [x] GetTranscription

### Join Requests & Links

- [x] ActionOnJoinRequest
- [x] CreateJoinLink
- [x] GetJoinLinks
- [x] GetJoinRequests

### User Account & Security

- [x] DeleteUserChat
- [x] GetPrivacySetting
- [x] GetTwoPasscodeStatus
- [x] SetupTwoStepVerification
- [x] SetSetting
- [x] ReportObject

### Bot API Methods (20)

- [x] BotGetMe
- [x] BotSendMessage
- [x] BotSendFile
- [x] BotSendPoll
- [x] BotSendLocation
- [x] BotSendContact
- [x] BotEditMessageText
- [x] BotEditMessageKeypad
- [x] BotEditChatKeypad
- [x] BotDeleteMessage
- [x] BotForwardMessage
- [x] BotGetChat
- [x] BotGetUpdates
- [x] BotSetCommands
- [x] BotUpdateEndpoints
- [x] BotRequestSendFile
- [x] BotGetFile
- [x] BotBanChatMember
- [x] BotUnbanChatMember
- [x] BotUploadFile

### Additional Methods (from rubpy/RubikaLib)

#### Group Management

- [x] EditGroupHistoryForNewMembers — toggle history visibility for new members
- [x] SetGroupEventMessages — configure join/leave event messages
- [x] SetGroupSlowModeTime — set slow mode interval
- [x] SetGroupReactions — configure allowed reactions for group

#### Channel Management

- [x] GetBannedChannelMembers — list banned channel members

#### Ownership Transfer

- [x] RequestChangeObjectOwner — initiate ownership transfer for group/channel
- [x] AcceptRequestObjectOwning — accept incoming ownership transfer
- [x] RejectRequestObjectOwning — reject incoming ownership transfer

#### Account

- [x] TurnOffTwoStep — disable two-step verification
- [x] RequestDeleteAccount — request account deletion
- [x] AddFolder — add folder (CreateFolder now delegates to this)
- [x] LoginTwoStepForgetPassword — 2FA password reset/recovery flow

#### Messaging

- [x] SendContact — send a contact card
- [x] SendLocation — send a location message
- [x] SeenChats — mark multiple chats as seen (batch version of MarkAsRead)

#### Rubino Social Media API (25 methods)

Rubika's built-in social media platform (separate from messaging). All prefixed with `Rubino` in Go.

- [x] RubinoGetMyProfileInfo — get own Rubino profile
- [x] RubinoGetProfileList — list Rubino profiles
- [x] RubinoGetProfileInfo — get another user's Rubino profile
- [x] RubinoCreatePage — create a Rubino page
- [x] RubinoUpdateProfile — update Rubino profile
- [x] RubinoIsExistUsername — check Rubino username availability
- [x] RubinoGetPostByShareLink — fetch post by share link
- [x] RubinoAddComment — comment on a Rubino post
- [x] RubinoLikePostAction — like/unlike a post
- [x] RubinoAddPostViewCount — increment post view count
- [x] RubinoGetComments — get comments on a post
- [x] RubinoGetRecentFollowingPosts — timeline of followed profiles' posts
- [x] RubinoGetProfilesStories — get stories from profiles
- [x] RubinoRequestUploadFile — request file upload for Rubino
- [x] RubinoGetProfileHighlights — get profile story highlights
- [x] RubinoGetBookmarkedPosts — get bookmarked posts
- [x] RubinoGetExplorePosts — get explore/discover feed
- [x] RubinoGetBlockedProfiles — list blocked Rubino profiles
- [x] RubinoGetProfileFollowers — get profile followers list
- [x] RubinoGetProfileFollowings — get profile followings list
- [x] RubinoSetBlockProfile — block/unblock a Rubino profile
- [x] RubinoGetMyArchiveStories — get own archived stories
- [x] RubinoRemoveRecord — delete a Rubino record/post
- [x] RubinoAddPost — create a new Rubino post
- [x] RubinoRequestFollow — follow/unfollow a Rubino profile

---
