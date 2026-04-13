## Phase 3: Bale — DONE

Bot 17/17. User 68/68. 162 exported methods, ~4,778 lines. ~152 additional methods found in Balethon/aiobale/web client but not yet in core. Geo-restricted from abroad.

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

### Not Added in Core

Methods found in Balethon (bot SDK), aiobale (gRPC user API), and Bale web client JS but not yet implemented in `bale.go`.

**Bot API (not added):**
- [ ] GetUpdates (long-poll updates)
- [ ] SetWebhook
- [ ] DeleteWebhook
- [ ] GetWebhookInfo
- [ ] SendPhoto
- [ ] SendAudio
- [ ] SendDocument
- [ ] SendVideo
- [ ] SendAnimation
- [ ] SendVoice
- [ ] SendVideoNote
- [ ] SendMediaGroup
- [ ] SendVenue
- [ ] EditMessageReplyMarkup
- [ ] GetFile
- [ ] RestrictChatMember
- [ ] UploadStickerFile
- [ ] CreateNewStickerSet
- [ ] AddStickerToSet
- [ ] DeleteStickerFromSet
- [ ] CreateInvoiceLink
- [ ] AnswerShippingQuery
- [ ] GetUserProfilePhotos
- [ ] AnswerInlineQuery
- [ ] AskReview (Bale-specific)
- [ ] InviteUser (Bale-specific)
- [ ] InquireTransaction (Bale wallet)

**Auth Service (not added):**
- [ ] DeleteAccount
- [ ] ChangePhone
- [ ] SendDeleteAccountVerificationCode
- [ ] SendChangePhoneVerificationCode
- [ ] EnableTwoFactorAuthentication
- [ ] DisableTwoFactorAuthentication
- [ ] IsTwoFactorAuthenticationEnabled
- [ ] VerifyEmail
- [ ] RecoverPassword
- [ ] VerifyPasswordRecovery
- [ ] SetNewPassword
- [ ] GetUserIdToken
- [ ] GetTicket
- [ ] GetBajeBamTicket
- [ ] GetBaleTicket
- [ ] GetJWTToken
- [ ] TerminateAllSessions

**Users Service (not added):**
- [ ] EditSex
- [ ] EditBirthDate
- [ ] EditAvatar (gRPC)
- [ ] RemoveAvatar
- [ ] EditMyTimeZone
- [ ] EditMyPreferredLanguages
- [ ] LoadFullUsersSequentially
- [ ] LoadAvatars
- [ ] GetUsersDefaultCardNumber
- [ ] AddCard
- [ ] ChangeDefaultCardNumber
- [ ] RemoveDefaultCardNumber
- [ ] NotifyAboutDeviceInfo
- [ ] GetUserPrivacyStatus
- [ ] SetUserPrivacyStatus
- [ ] GetUserFullPrivacy
- [ ] IsNameAllowed
- [ ] ChangePhoneNumber
- [ ] ConfirmPhoneNumber

**Meet Service (not added):**
- [ ] ReceiveCall (accept incoming)
- [ ] DiscardCall

**GiftPacket Service (not added):**
- [ ] SendGiftPacketWithWallet
- [ ] OpenGiftPacket

**Magazine Service (not added):**
- [ ] UpvotePost
- [ ] RevokeUpvotedPost
- [ ] GetMessageUpvoters

**Kifpool Service (not added):**
- [ ] GetMyKifpools

**Push Service (not added):**
- [ ] RegisterPush
- [ ] UnregisterPush
- [ ] RegisterGooglePush
- [ ] UnregisterGooglePush
- [ ] UnregisterAllPushCredentials

**Ramz / App Lock (not added):**
- [ ] SetPassword
- [ ] DeletePassword
- [ ] SendOTP
- [ ] ForgetPassword
- [ ] ValidateOTP
- [ ] CheckPasswordSet
- [ ] CheckPassword

**Report Service (not added):**
- [ ] ReportInappropriateContent
- [ ] ReportDismiss

**Feedback (not added):**
- [ ] SendFeedBack

**Search (not added — web client JS):**
- [ ] SearchPeerMessages — search within a specific chat
- [ ] SearchPeerMedia — search media in a specific chat
- [ ] SearchMembers — search group members by name
- [ ] SearchLinks — search shared links in a chat
- [ ] GlobalChannelSearch — search public channels globally

**Topics (not added — bale.messaging.v2):**
- [ ] EditTopic
- [ ] DeleteTopic

**Folders (not added — bale.messaging.v2):**
- [ ] EditFolder
- [ ] DeleteFolder
- [ ] ReorderFolders

**Polls (not added — user-mode):**
- [ ] ClosePoll
- [ ] GetPollResults
- [ ] GetFullPollResult

**Mini Apps / Bots (not added):**
- [ ] GetMiniAppUrl
- [ ] GetBotMenuButtons
- [ ] InvokeCustomMethod

**AI / Transcription (not added):**
- [ ] GetTranscript — voice-to-text

**Configs (not added):**
- [ ] GetInAppUpdate — check for app updates

**Analytics (not added):**
- [ ] FanoosSend — analytics event (bale.fanoos.v1)


---
