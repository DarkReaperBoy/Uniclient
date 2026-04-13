## Phase 3: Bale — DONE (core complete, all extended methods implemented)

267 exported methods, ~5,813 lines. All extended methods implemented (not yet tested). Geo-restricted from abroad.

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

### Bot API Methods (17)

- [x] SendMessage (bot mode)
- [x] EditMessage (bot mode)
- [x] DeleteMessage (bot mode)
- [x] ForwardMessage (bot mode)
- [x] CopyMessage
- [x] SendLocation
- [x] SendContact
- [x] SendInvoice
- [x] GetStickerSet
- [x] AnswerCallbackQuery
- [x] AnswerPreCheckoutQuery
- [x] SendMessageWithKeyboard
- [x] EditMessageCaption
- [x] SendChatAction
- [x] GetChatAdministrators
- [x] GetChatMembersCount
- [x] GetChatMember

### Chat Management (extended)

- [x] GetChat
- [x] SetChatTitle
- [x] SetChatDescription
- [x] SetChatPhoto
- [x] DeleteChatPhoto
- [x] CreateChatInviteLink
- [x] ExportChatInviteLink
- [x] UnpinAllChatMessages
- [x] BanChatMember
- [x] UnbanChatMember
- [x] PromoteChatMember

### User-Mode API Methods (68)

- [x] UserHTTPPost
- [x] UserSendRaw
- [x] ResolveGroupID
- [x] UploadRawPUT
- [x] GetUserID
- [x] UserSendMessage
- [x] UserUpdateMessage
- [x] UserDeleteMessage
- [x] UserForwardMessages
- [x] UserLoadHistory
- [x] UserLoadDialogs
- [x] UserMessageRead
- [x] UserPinMessage
- [x] UserUnPinMessages
- [x] UserLoadPinnedMessages
- [x] UserClearChat
- [x] UserDeleteChat
- [x] UserLoadUsers
- [x] UserLoadFullUsers
- [x] UserEditName
- [x] UserEditNickName
- [x] UserCheckNickName
- [x] UserEditAbout
- [x] UserEditLocalName
- [x] UserBlockUser
- [x] UserUnblockUser
- [x] UserLoadBlockedUsers
- [x] UserSearchContacts
- [x] UserImportContacts
- [x] UserAddContact
- [x] UserRemoveContact
- [x] UserGetContacts
- [x] UserResetContacts
- [x] UserCreateGroup
- [x] UserCreateGroupFull
- [x] UserEditGroupTitle
- [x] UserEditGroupAbout
- [x] UserInviteUsers
- [x] UserKickUser
- [x] UserMakeUserAdmin
- [x] UserRemoveUserAdmin
- [x] UserSetMemberPermissions
- [x] UserSetGroupDefaultPermissions
- [x] UserGetMemberPermissions
- [x] UserGetFullGroup
- [x] UserLoadMembers
- [x] UserGetGroupMembersCount
- [x] UserGetGroupInviteURL
- [x] UserRevokeInviteURL
- [x] UserJoinGroup
- [x] UserJoinPublicGroup
- [x] UserLeaveGroup
- [x] UserGetBannedUsers
- [x] UserUnBanUser
- [x] UserSetRestriction
- [x] UserTransferOwnership
- [x] UserEditChannelNick
- [x] UserGetPins
- [x] UserRemovePin
- [x] UserRemoveAllPins
- [x] UserGetGroupPreview
- [x] UserEditGroupAvatar
- [x] UserRemoveGroupAvatar
- [x] UserGetFileUploadURL
- [x] UserGetFileURL
- [x] UserSetOnline
- [x] UserTyping
- [x] UserStopTyping
- [x] UserSetReaction
- [x] UserRemoveReaction
- [x] UserGetReactions
- [x] UserGetReactionsList
- [x] UserGetMessageViews
- [x] UserGetParameters
- [x] UserEditParameter
- [x] UserSignOut
- [x] UserValidatePassword
- [x] UserSignUp

### Call Methods

- [x] StartCall (LiveKit signaling)
- [x] JoinGroupCall (LiveKit)
- [x] EndCall (LiveKit disconnect)
- [x] SetCallMuted (LiveKit track mute)
- [x] GetOngoingCalls
- [x] GetWssURL
- [x] GetGroupCall
- [x] GetCallLogs

### Untested (geo-restricted)

- [?] File upload/download (siloo.bale.ai unreachable)
- [?] EditGroupAvatar / RemoveGroupAvatar
- [?] Calling (LiveKit at meet-em.ble.ir) — implemented, cannot test from outside Iran

### Extended Methods (105 — all implemented, not yet tested)

#### Bot API (27)

- [x] GetUpdates (long-poll updates)
- [x] SetWebhook
- [x] DeleteWebhook
- [x] GetWebhookInfo
- [x] SendPhoto
- [x] SendAudio
- [x] SendDocument
- [x] SendVideo
- [x] SendAnimation
- [x] SendVoice
- [x] SendVideoNote
- [x] SendMediaGroup
- [x] SendVenue
- [x] EditMessageReplyMarkup
- [x] GetFile
- [x] RestrictChatMember
- [x] UploadStickerFile
- [x] CreateNewStickerSet
- [x] AddStickerToSet
- [x] DeleteStickerFromSet
- [x] CreateInvoiceLink
- [x] AnswerShippingQuery
- [x] GetUserProfilePhotos
- [x] AnswerInlineQuery
- [x] AskReview (Bale-specific)
- [x] InviteUser (Bale-specific)
- [x] InquireTransaction (Bale wallet)

#### Auth Service (17)

- [x] DeleteAccount
- [x] ChangePhone
- [x] SendDeleteAccountVerificationCode
- [x] SendChangePhoneVerificationCode
- [x] EnableTwoFactorAuthentication
- [x] DisableTwoFactorAuthentication
- [x] IsTwoFactorAuthenticationEnabled
- [x] VerifyEmail
- [x] RecoverPassword
- [x] VerifyPasswordRecovery
- [x] SetNewPassword
- [x] GetUserIdToken
- [x] GetTicket
- [x] GetBajeBamTicket
- [x] GetBaleTicket
- [x] GetJWTToken
- [x] TerminateAllSessions

#### Users Service (19)

- [x] EditSex
- [x] EditBirthDate
- [x] EditAvatarGRPC
- [x] RemoveAvatar
- [x] EditMyTimeZone
- [x] EditMyPreferredLanguages
- [x] LoadFullUsersSequentially
- [x] LoadAvatars
- [x] GetUsersDefaultCardNumber
- [x] AddCard
- [x] ChangeDefaultCardNumber
- [x] RemoveDefaultCardNumber
- [x] NotifyAboutDeviceInfo
- [x] GetUserPrivacyStatus
- [x] SetUserPrivacyStatus
- [x] GetUserFullPrivacy
- [x] IsNameAllowed
- [x] ChangePhoneNumber
- [x] ConfirmPhoneNumber

#### Meet Service (2)

- [x] ReceiveCall
- [x] DiscardCall

#### GiftPacket Service (2)

- [x] SendGiftPacketWithWallet
- [x] OpenGiftPacket

#### Magazine Service (3)

- [x] UpvotePost
- [x] RevokeUpvotedPost
- [x] GetMessageUpvoters

#### Kifpool Service (1)

- [x] GetMyKifpools

#### Push Service (5)

- [x] RegisterPush
- [x] UnregisterPush
- [x] RegisterGooglePush
- [x] UnregisterGooglePush
- [x] UnregisterAllPushCredentials

#### Ramz / App Lock (7)

- [x] SetRamzPassword
- [x] DeleteRamzPassword
- [x] SendRamzOTP
- [x] ForgetRamzPassword
- [x] ValidateRamzOTP
- [x] CheckRamzPasswordSet
- [x] CheckRamzPassword

#### Report Service (2)

- [x] ReportInappropriateContent
- [x] ReportDismiss

#### Feedback (1)

- [x] SendFeedBack

#### Search (5)

- [x] SearchPeerMessages
- [x] SearchPeerMedia
- [x] SearchMembers
- [x] SearchLinks
- [x] GlobalChannelSearch

#### Topics (2)

- [x] EditTopic
- [x] DeleteTopic

#### Folders (3)

- [x] EditFolder
- [x] DeleteFolder
- [x] ReorderFolders

#### Polls (3)

- [x] ClosePoll
- [x] GetPollResults
- [x] GetFullPollResult

#### Mini Apps / Bots (3)

- [x] GetMiniAppUrl
- [x] GetBotMenuButtons
- [x] InvokeCustomMethod

#### AI / Transcription (1)

- [x] GetTranscript

#### Configs (1)

- [x] GetInAppUpdate

#### Analytics (1)

- [x] FanoosSend

---
