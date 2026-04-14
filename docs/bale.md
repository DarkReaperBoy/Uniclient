# Bale Core — API Reference

Pure Go client for [Bale Messenger](https://bale.ai), an Iranian messaging platform. Dual-mode: Bot API (Telegram-compatible HTTP endpoint at `tapi.bale.ai`) and User API (gRPC-Web/WebSocket with custom protobuf over `next-ws.bale.ai`). No CGo, no external dependencies beyond standard library and `nhooyr.io/websocket`.

**456 exported methods** across bot messaging, media, chat management, webhooks, stickers, payments, inline queries, user messaging, groups/channels, contacts, account management, calls (LiveKit WebRTC), polls, reactions, stories, folders, search, push notifications, scheduled tasks, feeds, bots/mini-apps, and more.

## Table of Contents

- [Setup](#setup)
- [Types](#types)
- [Connection & Authentication](#connection--authentication)
- [Core Interface Methods](#core-interface-methods)
- [Bot API -- Messages](#bot-api----messages)
- [Bot API -- Media](#bot-api----media)
- [Bot API -- Chat Management](#bot-api----chat-management)
- [Bot API -- Keyboard & Inline](#bot-api----keyboard--inline)
- [Bot API -- Webhooks](#bot-api----webhooks)
- [Bot API -- Sticker Sets](#bot-api----sticker-sets)
- [Bot API -- Bot Commands](#bot-api----bot-commands)
- [Bot API -- Miscellaneous](#bot-api----miscellaneous)
- [User API -- Raw Transport](#user-api----raw-transport)
- [User API -- Messages](#user-api----messages)
- [User API -- Groups & Channels](#user-api----groups--channels)
- [User API -- Contacts](#user-api----contacts)
- [User API -- Media & Files](#user-api----media--files)
- [User API -- Account & Profile](#user-api----account--profile)
- [User API -- Settings & Privacy](#user-api----settings--privacy)
- [User API -- Security & 2FA](#user-api----security--2fa)
- [User API -- Sessions](#user-api----sessions)
- [User API -- Presence & Online](#user-api----presence--online)
- [User API -- Dialogs](#user-api----dialogs)
- [User API -- Topics & Threads](#user-api----topics--threads)
- [User API -- Search](#user-api----search)
- [Polls](#polls)
- [Reactions](#reactions)
- [Upvotes](#upvotes)
- [Folders](#folders)
- [Calls](#calls)
- [User API -- Calls (Extended)](#user-api----calls-extended)
- [Stories](#stories)
- [GIFs & Stickers (User)](#gifs--stickers-user)
- [Bots & Mini-Apps (User)](#bots--mini-apps-user)
- [Push Notifications](#push-notifications)
- [Ramz (Financial Security)](#ramz-financial-security)
- [Reporting](#reporting)
- [Scheduled Tasks](#scheduled-tasks)
- [Message Streams](#message-streams)
- [Links & Previews](#links--previews)
- [Shared Media](#shared-media)
- [Feeds & Magazine](#feeds--magazine)
- [Recommendations](#recommendations)
- [Nasim File System](#nasim-file-system)
- [Organization](#organization)
- [AI & LLM](#ai--llm)
- [Miscellaneous User Methods](#miscellaneous-user-methods)
- [Extended Message Types](#extended-message-types)
- [Event Handlers](#event-handlers)
- [Unsupported Core Methods](#unsupported-core-methods)

## Setup

```go
import "uniclient/cores"

bale := cores.NewBaleCore("./sessions/bale.json")
```

**Capabilities:** `TEXT`, `CHANNELS`, `REACTIONS`, `POLLS`, `STICKERS`, `ADMIN`, `FOLDERS`, `TYPING`, `SEARCH`, `LOCATION`, `FILE_TRANSFER`

## Types

### BaleCore

```go
type BaleCore struct {
    // internal fields: auth state, HTTP client, WebSocket connection,
    // protobuf codec, group ID cache, LiveKit call state
}
```

The main client struct. Created via `NewBaleCore(sessionPath)`. Implements the `Core` interface.

### BaleChatInfo

```go
type BaleChatInfo struct {
    ID        int64  `json:"id"`
    Type      string `json:"type"`       // "private", "group", "supergroup", "channel"
    Title     string `json:"title,omitempty"`
    Username  string `json:"username,omitempty"`
    FirstName string `json:"first_name,omitempty"`
    LastName  string `json:"last_name,omitempty"`
}
```

Chat info from the bot API (`getChat`).

### BaleChatMember

```go
type BaleChatMember struct {
    User   BaleUserInfo `json:"user"`
    Status string       `json:"status"` // "creator", "administrator", "member", "restricted", "left", "kicked"
}
```

### BaleUserInfo

```go
type BaleUserInfo struct {
    ID        int64  `json:"id"`
    IsBot     bool   `json:"is_bot"`
    FirstName string `json:"first_name"`
    LastName  string `json:"last_name,omitempty"`
    Username  string `json:"username,omitempty"`
}
```

### BaleFileInfo

```go
type BaleFileInfo struct {
    FileID   string `json:"file_id"`
    FileSize int64  `json:"file_size"`
    FilePath string `json:"file_path"`
}
```

File info from the bot API (`getFile`).

### BaleWebhookInfo

```go
type BaleWebhookInfo struct {
    URL                  string `json:"url"`
    HasCustomCertificate bool   `json:"has_custom_certificate"`
    PendingUpdateCount   int    `json:"pending_update_count"`
}
```

### BaleStickerSet

```go
type BaleStickerSet struct {
    Name       string `json:"name"`
    Title      string `json:"title"`
    IsAnimated bool   `json:"is_animated"`
}
```

### BaleUserProfilePhotos

```go
type BaleUserProfilePhotos struct {
    TotalCount int `json:"total_count"`
}
```

---

## Connection & Authentication

### Name

```go
func (b *BaleCore) Name() string
```

Returns `"bale"`.

### GetUserID

```go
func (b *BaleCore) GetUserID() int64
```

Returns the authenticated user's numeric ID (user mode) or bot ID.

### Capabilities

```go
func (b *BaleCore) Capabilities() []string
```

Returns the list of supported feature flags.

### Authenticate

```go
func (b *BaleCore) Authenticate(cfg AuthConfig) error
```

Authenticates in bot or user mode based on `cfg` fields.

**Bot mode** — set `cfg.BotToken`:

```go
err := bale.Authenticate(cores.AuthConfig{
    BotToken: "123456:ABC-DEF",
})
```

Validates the token via `getMe` at `tapi.bale.ai`.

**User mode** — set `cfg.Phone`:

```go
err := bale.Authenticate(cores.AuthConfig{
    Phone: "+98xxxxxxxxxx",
})
```

Phone/code flow via gRPC-Web. Sends OTP via SMS, polls `auth/otp_code.txt` for the code. Supports 2FA via `cfg.Password2F`. Establishes a persistent WebSocket connection to `next-ws.bale.ai` after auth. Includes DNS fallback IP (`2.189.68.126`) for use outside Iran.

### Logout

```go
func (b *BaleCore) Logout() error
```

Disconnects and clears authentication state. In user mode, closes the WebSocket. Does not delete the session file.

### Close

```go
func (b *BaleCore) Close() error
```

Full shutdown: cancels polling/WebSocket, waits for goroutines, saves session, sets authed=false.

### OnUpdate

```go
func (b *BaleCore) OnUpdate(handler func(Update))
```

Registers a callback for real-time updates. In bot mode, updates come from HTTP long-polling. In user mode, updates arrive over WebSocket (new messages, edits, deletes, connectivity state).

```go
bale.OnUpdate(func(u cores.Update) {
    if u.Message != nil {
        fmt.Printf("[%s] %s: %s\n", u.ChatID, u.Message.SenderName, u.Message.Text)
    }
})
```

---

## Core Interface Methods

These implement the unified `Core` interface shared across all uniclient platforms.

### Messaging

#### SendMessage

```go
func (b *BaleCore) SendMessage(chatID string, msg OutgoingMessage) (*Message, error)
```

Sends a text message. In bot mode, calls `sendMessage`. In user mode, sends via WebSocket protobuf. Supports `msg.ReplyToID` for replies and `msg.ParseMode` for formatting.

```go
msg, err := bale.SendMessage("123456", cores.OutgoingMessage{Text: "Hello!"})
```

#### GetMessages

```go
func (b *BaleCore) GetMessages(chatID string, opts PaginationOpts) ([]Message, error)
```

Retrieves message history. In bot mode, uses `getUpdates` cache. In user mode, calls `LoadHistory` via gRPC.

#### EditMessage

```go
func (b *BaleCore) EditMessage(chatID string, msgID string, text string) (*Message, error)
```

Edits a message's text. Bot mode uses `editMessageText`; user mode uses `UpdateMessage`.

#### DeleteMessage

```go
func (b *BaleCore) DeleteMessage(chatID string, msgID string) error
```

Deletes a message. Bot mode uses `deleteMessage`; user mode uses `DeleteMessage` with RID+date.

#### ReplyToMessage

```go
func (b *BaleCore) ReplyToMessage(chatID string, replyToMsgID string, msg OutgoingMessage) (*Message, error)
```

Sends a reply to a specific message. Delegates to `SendMessage` with the reply-to ID set.

#### ForwardMessage

```go
func (b *BaleCore) ForwardMessage(fromChatID string, msgID string, toChatID string) (*Message, error)
```

Forwards a message between chats. Bot mode uses `forwardMessage`; user mode uses `ForwardMessages`.

#### ReactToMessage

```go
func (b *BaleCore) ReactToMessage(chatID string, msgID string, emoji string) error
```

Adds a reaction emoji to a message. Bot mode uses `setMessageReaction`; user mode uses `SetReaction`.

#### PinMessage

```go
func (b *BaleCore) PinMessage(chatID string, msgID string) error
```

Pins a message in a chat. Bot mode uses `pinChatMessage`; user mode uses `PinMessage`.

#### UnpinMessage

```go
func (b *BaleCore) UnpinMessage(chatID string, msgID string) error
```

Unpins a message. Bot mode uses `unpinChatMessage`; user mode uses `UnPinMessages`.

#### MarkAsRead

```go
func (b *BaleCore) MarkAsRead(chatID string, upToMsgID string) error
```

Marks messages as read up to the given message ID. User mode uses `MessageRead`.

#### GetReadState

```go
func (b *BaleCore) GetReadState(chatID string) (*ReadState, error)
```

Returns the read state for a chat (last read message ID and unread count).

#### SendImageBase64

```go
func (b *BaleCore) SendImageBase64(chatID string, b64 string, caption string) (*Message, error)
```

Sends a base64-encoded image. Decodes to bytes and sends via the appropriate media endpoint.

### File Transfer

#### UploadFile

```go
func (b *BaleCore) UploadFile(chatID string, file FileUpload, progress func(sent, total int64)) (*Message, error)
```

Uploads a file to a chat. Bot mode uses multipart upload to `sendDocument`. User mode uploads via `GetFileUploadURL` + PUT, then sends a document message. Supports progress callbacks.

```go
msg, err := bale.UploadFile("chat_id", cores.FileUpload{
    Path: "/path/to/file.pdf",
    Name: "report.pdf",
}, func(sent, total int64) {
    fmt.Printf("Upload: %d/%d bytes\n", sent, total)
})
```

#### DownloadFile

```go
func (b *BaleCore) DownloadFile(fileRef FileRef, dest string, progress func(recv, total int64)) error
```

Downloads a file to disk. Bot mode uses `getFile` + file path download. User mode uses `GetFileURL` with fileID and accessHash. Supports progress callbacks.

### Calls

#### StartCall

```go
func (b *BaleCore) StartCall(chatID string, video bool) (*CallSession, error)
```

Starts a 1:1 call via LiveKit WebRTC. User mode only. Calls `StartCall` on the Meet service, retrieves LiveKit room credentials, and connects to the SFU at `meet-em.ble.ir`.

**Note:** Geo-restricted to Iran. Untested outside Iran due to `meet-em.ble.ir` access restrictions.

#### JoinGroupCall

```go
func (b *BaleCore) JoinGroupCall(chatID string) (*CallSession, error)
```

Joins (or starts) a group call. Checks for ongoing calls first via `GetOngoingCalls`, then joins or creates a new group call. Connects to LiveKit SFU.

#### EndCall

```go
func (b *BaleCore) EndCall(callID string) error
```

Ends an active call. Disconnects from LiveKit room, unpublishes audio tracks, and sends `EndGroupCall`/`DiscardCall` signaling.

#### SetCallMuted

```go
func (b *BaleCore) SetCallMuted(callID string, muted bool) error
```

Mutes or unmutes the local audio track in a LiveKit call.

#### AcceptCall

```go
func (b *BaleCore) AcceptCall(callID string) (*CallSession, error)
```

Accepts an incoming call. Returns `ErrNotSupported` (incoming call acceptance requires push notification integration).

#### DeclineCall

```go
func (b *BaleCore) DeclineCall(callID string) error
```

Declines an incoming call by discarding it.

#### GetOngoingCalls

```go
func (b *BaleCore) GetOngoingCalls() (map[string]interface{}, error)
```

Returns currently active calls from the Meet service.

#### GetWssURL

```go
func (b *BaleCore) GetWssURL(callID string) (string, error)
```

Retrieves the LiveKit WebSocket URL for an active call by calling `GetCallDetails` and extracting the WSS endpoint.

#### GetGroupCall

```go
func (b *BaleCore) GetGroupCall(chatID string) (map[string]interface{}, error)
```

Returns information about an active group call in the specified chat.

#### GetCallLogs

```go
func (b *BaleCore) GetCallLogs(page, count int) (map[string]interface{}, error)
```

Retrieves paginated call history logs.

### Profile

#### GetProfile

```go
func (b *BaleCore) GetProfile(userID string) (*User, error)
```

Gets a user's profile. Bot mode uses `getChat`; user mode uses `LoadUsers` or `LoadFullUsers`.

### Dialogs & Chat Info

#### GetDialogs

```go
func (b *BaleCore) GetDialogs(opts PaginationOpts) ([]Dialog, error)
```

Returns the user's dialog list. Bot mode is limited (no native dialog list in Bot API). User mode calls `LoadDialogs` with pagination.

#### GetChatInfo

```go
func (b *BaleCore) GetChatInfo(chatID string) (*Dialog, error)
```

Returns detailed info for a chat. Bot mode uses `getChat`; user mode resolves peers and loads full group/user data.

#### EditChatTitle

```go
func (b *BaleCore) EditChatTitle(chatID string, title string) error
```

Changes a chat's title. Bot mode uses `setChatTitle`; user mode uses `EditGroupTitle`.

#### EditChatDescription

```go
func (b *BaleCore) EditChatDescription(chatID string, description string) error
```

Changes a chat's description/about text.

#### GetInviteLink

```go
func (b *BaleCore) GetInviteLink(chatID string) (string, error)
```

Gets the invite link for a chat. Bot mode uses `exportChatInviteLink`; user mode uses `GetGroupInviteURL`.

#### LeaveChat

```go
func (b *BaleCore) LeaveChat(chatID string) error
```

Leaves a group or channel. Calls `leaveChat` (bot) or `LeaveGroup` (user).

### Groups & Channels (Core)

#### CreateGroup

```go
func (b *BaleCore) CreateGroup(name string, members []string) (*Dialog, error)
```

Creates a new group. Bot mode uses `createNewGroup`; user mode uses `CreateGroup`.

#### CreateChannel

```go
func (b *BaleCore) CreateChannel(name string, description string) (*Dialog, error)
```

Creates a new channel with a title and description.

#### CreateTopic

```go
func (b *BaleCore) CreateTopic(chatID string, name string) (*Dialog, error)
```

Creates a topic/thread in a group (if the group supports topics).

### Members (Core)

#### AddMembers

```go
func (b *BaleCore) AddMembers(chatID string, userIDs []string) error
```

Adds members to a group/channel. Bot mode uses `inviteUser`; user mode uses `InviteUsers`.

#### RemoveMember

```go
func (b *BaleCore) RemoveMember(chatID string, userID string) error
```

Removes a member from a group/channel.

#### BanMember

```go
func (b *BaleCore) BanMember(chatID string, userID string) error
```

Bans a user from a chat (bot: `banChatMember`, user: `KickUser`).

#### UnbanMember

```go
func (b *BaleCore) UnbanMember(chatID string, userID string) error
```

Unbans a user (bot: `unbanChatMember`, user: `UnBanUser`).

#### GetMembers

```go
func (b *BaleCore) GetMembers(chatID string, opts PaginationOpts) ([]User, error)
```

Lists members of a group/channel with pagination.

#### SetAdmin

```go
func (b *BaleCore) SetAdmin(chatID string, userID string, admin bool) error
```

Promotes or demotes a user to/from admin.

### Contacts (Core)

#### GetContacts

```go
func (b *BaleCore) GetContacts() ([]User, error)
```

Returns the user's contact list. User mode uses `GetContacts`.

#### AddContact

```go
func (b *BaleCore) AddContact(phone string, firstName string, lastName string) error
```

Adds a contact by phone number.

#### DeleteContact

```go
func (b *BaleCore) DeleteContact(userID string) error
```

Removes a contact.

#### BlockUser

```go
func (b *BaleCore) BlockUser(userID string) error
```

Blocks a user.

#### UnblockUser

```go
func (b *BaleCore) UnblockUser(userID string) error
```

Unblocks a user.

#### GetBlockedUsers

```go
func (b *BaleCore) GetBlockedUsers() ([]User, error)
```

Returns the list of blocked users.

### Search (Core)

#### SearchMessages

```go
func (b *BaleCore) SearchMessages(chatID string, query string, opts PaginationOpts) ([]Message, error)
```

Searches messages within a specific chat.

#### SearchGlobal

```go
func (b *BaleCore) SearchGlobal(query string, opts PaginationOpts) ([]Dialog, error)
```

Searches across all chats for dialogs matching the query.

### Typing

#### SendTyping

```go
func (b *BaleCore) SendTyping(chatID string) error
```

Sends a typing indicator. Bot mode uses `sendChatAction` with action `"typing"`.

### Polls (Core)

#### CreatePoll

```go
func (b *BaleCore) CreatePoll(chatID string, question string, options []string) (*Message, error)
```

Creates a poll in a chat.

#### VotePoll

```go
func (b *BaleCore) VotePoll(chatID string, msgID string, optionIndex int) error
```

Votes on a poll option.

### Sessions (Core)

#### GetSessions

```go
func (b *BaleCore) GetSessions() ([]Session, error)
```

Returns the list of active authentication sessions. User mode calls `GetAuthSessions`.

#### TerminateSession

```go
func (b *BaleCore) TerminateSession(sessionID string) error
```

Terminates a specific authentication session.

### Folders (Core)

#### GetFolders

```go
func (b *BaleCore) GetFolders() ([]Folder, error)
```

Returns the user's dialog folders.

#### CreateFolder

```go
func (b *BaleCore) CreateFolder(name string, chatIDs []string) (*Folder, error)
```

Creates a new folder with the specified chats.

---

## Bot API -- Messages

### GetUpdates

```go
func (b *BaleCore) GetUpdates(offset int64, limit int, timeout int) ([]map[string]interface{}, error)
```

Long-polls for updates from the bot API. Returns raw update objects. Use `timeout` for long-polling duration in seconds.

```go
updates, err := bale.GetUpdates(0, 100, 30)
```

### CopyMessage

```go
func (b *BaleCore) CopyMessage(chatID string, fromChatID string, msgID int64) (int64, error)
```

Copies a message from one chat to another without the "Forwarded from" header. Returns the new message ID.

### EditMessageCaption

```go
func (b *BaleCore) EditMessageCaption(chatID string, msgID int64, caption string) error
```

Edits the caption of a media message.

### SendScheduledMessage

```go
func (b *BaleCore) SendScheduledMessage(chatID string, text string, scheduleDate int64) (map[string]interface{}, error)
```

Sends a message scheduled for a future time (Unix timestamp).

### SendProtectedMessage

```go
func (b *BaleCore) SendProtectedMessage(chatID string, text string) (map[string]interface{}, error)
```

Sends a message that cannot be forwarded or saved by recipients.

### SendLongTextMessage

```go
func (b *BaleCore) SendLongTextMessage(chatID string, text string) (map[string]interface{}, error)
```

Sends a long-form text message (exceeding normal character limits).

### UnpinAllMessages

```go
func (b *BaleCore) UnpinAllMessages(chatID string) error
```

Unpins all messages in a chat.

---

## Bot API -- Media

### SendPhoto

```go
func (b *BaleCore) SendPhoto(chatID string, photo string, caption string) (*Message, error)
```

Sends a photo. `photo` can be a file path or file_id.

```go
msg, err := bale.SendPhoto("123456", "/path/to/photo.jpg", "Nice view!")
```

### SendAudio

```go
func (b *BaleCore) SendAudio(chatID string, audio string, caption string, duration int) (*Message, error)
```

Sends an audio file with optional caption and duration metadata.

### SendDocument

```go
func (b *BaleCore) SendDocument(chatID string, document string, caption string) (*Message, error)
```

Sends a document/file. `document` can be a file path or file_id.

### SendVideo

```go
func (b *BaleCore) SendVideo(chatID string, video string, caption string, duration int) (*Message, error)
```

Sends a video file with optional caption and duration.

### SendAnimation

```go
func (b *BaleCore) SendAnimation(chatID string, animation string, caption string) (*Message, error)
```

Sends a GIF animation.

### SendVoice

```go
func (b *BaleCore) SendVoice(chatID string, voice string, caption string, duration int) (*Message, error)
```

Sends a voice message (OGG/Opus).

### SendVideoNote

```go
func (b *BaleCore) SendVideoNote(chatID string, videoNote string, duration int, length int) (*Message, error)
```

Sends a round video note (circular video message).

### SendMediaGroup

```go
func (b *BaleCore) SendMediaGroup(chatID string, media []map[string]interface{}) ([]map[string]interface{}, error)
```

Sends a group of photos/videos as an album. Each item in `media` should have `type`, `media`, and optional `caption` fields.

### SendLocation

```go
func (b *BaleCore) SendLocation(chatID string, lat float64, lon float64) (*Message, error)
```

Sends a location pin.

### SendContact

```go
func (b *BaleCore) SendContact(chatID string, phone string, firstName string, lastName string) (*Message, error)
```

Sends a contact card.

### SendVenue

```go
func (b *BaleCore) SendVenue(chatID string, lat, lon float64, title, address string) (*Message, error)
```

Sends a venue with geographic coordinates, title, and address.

### SendSticker

```go
func (b *BaleCore) SendSticker(chatID string, stickerFileID string) (*Message, error)
```

Sends a sticker by file_id.

### GetFile

```go
func (b *BaleCore) GetFile(fileID string) (BaleFileInfo, error)
```

Gets file info (path, size) for downloading. Use the returned `FilePath` with the base URL to construct a download URL.

### GetUserProfilePhotos

```go
func (b *BaleCore) GetUserProfilePhotos(userID int64, offset, limit int) (BaleUserProfilePhotos, error)
```

Gets a user's profile photos with pagination.

---

## Bot API -- Chat Management

### GetChat

```go
func (b *BaleCore) GetChat(chatID string) (BaleChatInfo, error)
```

Gets chat info (id, type, title, username) via bot API `getChat`.

### GetChatAdministrators

```go
func (b *BaleCore) GetChatAdministrators(chatID string) ([]BaleChatMember, error)
```

Returns the list of administrators in a chat.

### GetChatMembersCount

```go
func (b *BaleCore) GetChatMembersCount(chatID string) (int, error)
```

Returns the total number of members in a chat.

### GetChatMember

```go
func (b *BaleCore) GetChatMember(chatID string, userID int64) (BaleChatMember, error)
```

Gets info about a specific member (status, permissions).

### PromoteChatMember

```go
func (b *BaleCore) PromoteChatMember(chatID string, userID int64, perms map[string]bool) error
```

Promotes a user with specific admin permissions. Keys: `can_change_info`, `can_delete_messages`, `can_invite_users`, `can_restrict_members`, `can_pin_messages`, `can_promote_members`.

### RestrictChatMember

```go
func (b *BaleCore) RestrictChatMember(chatID string, userID int64, permissions map[string]bool) error
```

Restricts a user's permissions. Keys: `can_send_messages`, `can_send_media_messages`, `can_send_other_messages`, `can_add_web_page_previews`.

### SetChatPhoto

```go
func (b *BaleCore) SetChatPhoto(chatID string, photo io.Reader, fileName string) error
```

Sets a chat's photo via multipart upload.

### DeleteChatPhoto

```go
func (b *BaleCore) DeleteChatPhoto(chatID string) error
```

Removes the chat photo.

### CreateChatInviteLink

```go
func (b *BaleCore) CreateChatInviteLink(chatID string) (string, error)
```

Creates a new invite link for a chat. Returns the link URL.

### ExportChatInviteLink

```go
func (b *BaleCore) ExportChatInviteLink(chatID string) (string, error)
```

Exports the primary invite link for a chat.

### SendChatAction

```go
func (b *BaleCore) SendChatAction(chatID string, action string) error
```

Sends a chat action (e.g. `"typing"`, `"upload_photo"`, `"upload_document"`).

### InviteUser

```go
func (b *BaleCore) InviteUser(chatID string, userID int64) error
```

Invites a single user to a chat by user ID.

---

## Bot API -- Keyboard & Inline

### SendMessageWithKeyboard

```go
func (b *BaleCore) SendMessageWithKeyboard(chatID string, text string, keyboard [][]map[string]string) (*Message, error)
```

Sends a message with an inline keyboard. Each button map should have `"text"` and optionally `"callback_data"` or `"url"`.

```go
keyboard := [][]map[string]string{
    {{"text": "Button 1", "callback_data": "btn1"}, {"text": "Button 2", "url": "https://example.com"}},
}
msg, err := bale.SendMessageWithKeyboard("123456", "Choose:", keyboard)
```

### AnswerCallbackQuery

```go
func (b *BaleCore) AnswerCallbackQuery(callbackQueryID string, text string, showAlert bool) error
```

Answers a callback query from an inline button press. `showAlert` shows a popup instead of a toast.

### AnswerInlineQuery

```go
func (b *BaleCore) AnswerInlineQuery(inlineQueryID string, results []map[string]interface{}, cacheTime int) error
```

Answers an inline query with results. `cacheTime` is how long results are cached on the server (seconds).

### EditMessageReplyMarkup

```go
func (b *BaleCore) EditMessageReplyMarkup(chatID string, msgID int64, replyMarkup interface{}) error
```

Edits the reply markup (inline keyboard) of an existing message.

---

## Bot API -- Webhooks

### SetWebhook

```go
func (b *BaleCore) SetWebhook(url string, maxConnections int) error
```

Sets a webhook URL for receiving updates instead of long-polling.

### DeleteWebhook

```go
func (b *BaleCore) DeleteWebhook() error
```

Removes the webhook, switching back to `getUpdates` mode.

### GetWebhookInfo

```go
func (b *BaleCore) GetWebhookInfo() (BaleWebhookInfo, error)
```

Returns current webhook configuration (URL, pending update count).

---

## Bot API -- Sticker Sets

### GetStickerSet

```go
func (b *BaleCore) GetStickerSet(name string) (BaleStickerSet, error)
```

Gets a sticker set by its short name.

### UploadStickerFile

```go
func (b *BaleCore) UploadStickerFile(userID int64, sticker io.Reader, stickerFormat string) (map[string]interface{}, error)
```

Uploads a sticker file for later use in sticker set creation.

### CreateNewStickerSet

```go
func (b *BaleCore) CreateNewStickerSet(userID int64, name, title string, stickers []map[string]interface{}) error
```

Creates a new sticker set owned by the specified user.

### AddStickerToSet

```go
func (b *BaleCore) AddStickerToSet(userID int64, name string, sticker map[string]interface{}) error
```

Adds a sticker to an existing set.

### DeleteStickerFromSet

```go
func (b *BaleCore) DeleteStickerFromSet(sticker string) error
```

Removes a sticker from a set by its file_id.

---

## Bot API -- Bot Commands

### SetMyCommands

```go
func (b *BaleCore) SetMyCommands(commands []map[string]string) (map[string]interface{}, error)
```

Sets the bot's command menu. Each command: `{"command": "/start", "description": "Start the bot"}`.

### DeleteMyCommands

```go
func (b *BaleCore) DeleteMyCommands() (map[string]interface{}, error)
```

Removes all bot commands from the menu.

### GetMyCommands

```go
func (b *BaleCore) GetMyCommands() ([]map[string]string, error)
```

Returns the bot's current command list.

---

## Bot API -- Miscellaneous

### SendBankMessage

```go
func (b *BaleCore) SendBankMessage(chatID string, bankData map[string]interface{}) (map[string]interface{}, error)
```

Sends a bank/payment message (Bale-specific financial messaging).

### SendJsonMessage

```go
func (b *BaleCore) SendJsonMessage(chatID string, jsonData string) (map[string]interface{}, error)
```

Sends a raw JSON-formatted message.

### SendOrderMessage

```go
func (b *BaleCore) SendOrderMessage(chatID string, orderData map[string]interface{}) (map[string]interface{}, error)
```

Sends an order/invoice message.

### SendAnimatedSticker

```go
func (b *BaleCore) SendAnimatedSticker(chatID string, stickerData map[string]interface{}) (map[string]interface{}, error)
```

Sends an animated sticker (Lottie/TGS format).

### SendLiveMessage

```go
func (b *BaleCore) SendLiveMessage(chatID string, liveData map[string]interface{}) (map[string]interface{}, error)
```

Sends a live/streaming message.

### MuteChat

```go
func (b *BaleCore) MuteChat(chatID string, muted bool) error
```

Mutes or unmutes notifications for a chat.

### ArchiveChat

```go
func (b *BaleCore) ArchiveChat(chatID string, archived bool) error
```

Archives or unarchives a chat.

### MarkUnread

```go
func (b *BaleCore) MarkUnread(chatID string, unread bool) error
```

Marks a chat as unread or read.

### MarkAsUnread

```go
func (b *BaleCore) MarkAsUnread(chatID string) (map[string]interface{}, error)
```

Marks a chat as unread (user mode variant).

---

## User API -- Raw Transport

### UserHTTPPost

```go
func (b *BaleCore) UserHTTPPost(service, method string, payload map[string]interface{}) (map[string]interface{}, error)
```

Sends a raw gRPC-Web HTTP POST request. Used for auth requests before WebSocket is established.

### UserSendRaw

```go
func (b *BaleCore) UserSendRaw(service, method string, payload map[string]interface{}) (map[string]interface{}, error)
```

Sends a raw request over the WebSocket. Low-level access to any Bale gRPC service/method.

```go
resp, err := bale.UserSendRaw("bale.users.v1.Users", "LoadFullUsers", map[string]interface{}{
    "1": []interface{}{map[string]interface{}{"1": int64(12345), "2": int64(1)}},
})
```

### ResolveGroupID

```go
func (b *BaleCore) ResolveGroupID(peerID int64) (int64, error)
```

Resolves a peer ID to the internal group ID (needed for Groups service calls). Uses cached values when available.

### UploadRawPUT

```go
func (b *BaleCore) UploadRawPUT(url string, data []byte) error
```

Performs a raw HTTP PUT upload to a given URL (used for file uploads in user mode).

---

## User API -- Messages

### UserSendMessage

```go
func (b *BaleCore) UserSendMessage(chatID string, text string, replyToRID int64, replyToDate int64) (map[string]interface{}, error)
```

Sends a message in user mode. `chatID` format: `"peerID|peerType"`. Set `replyToRID` and `replyToDate` to non-zero for replies.

```go
resp, err := bale.UserSendMessage("12345|1", "Hello!", 0, 0)
```

### UserUpdateMessage

```go
func (b *BaleCore) UserUpdateMessage(chatID string, msgRID int64, dateMs int64, newText string) (map[string]interface{}, error)
```

Edits a message by its RID and date.

### UserDeleteMessage

```go
func (b *BaleCore) UserDeleteMessage(chatID string, rids []int64, dates []int64) (map[string]interface{}, error)
```

Deletes one or more messages by their RIDs and dates.

### UserForwardMessages

```go
func (b *BaleCore) UserForwardMessages(toChatID string, fromPeer map[string]interface{}, rids []int64, dates []int64) (map[string]interface{}, error)
```

Forwards messages from one peer to another. `fromPeer` is a protobuf Peer map `{1: type, 2: id}`.

### UserLoadHistory

```go
func (b *BaleCore) UserLoadHistory(chatID string, date int64, limit int, loadMode int) (map[string]interface{}, error)
```

Loads message history for a chat. `loadMode`: 0=backward, 1=forward, 2=both. `date` is the offset timestamp in milliseconds.

### UserMessageRead

```go
func (b *BaleCore) UserMessageRead(chatID string, date int64) (map[string]interface{}, error)
```

Marks messages as read up to the given timestamp.

### UserClearChat

```go
func (b *BaleCore) UserClearChat(chatID string) (map[string]interface{}, error)
```

Clears all messages in a chat (local side).

### UserDeleteChat

```go
func (b *BaleCore) UserDeleteChat(chatID string) (map[string]interface{}, error)
```

Deletes a chat entirely.

### UserSendMultiMediaMessage

```go
func (b *BaleCore) UserSendMultiMediaMessage(chatID string, mediaMessages []map[string]interface{}) (map[string]interface{}, error)
```

Sends multiple media items in a single grouped message (album).

### UserFetchProtectedMessage

```go
func (b *BaleCore) UserFetchProtectedMessage(chatID string, msgID string) (map[string]interface{}, error)
```

Fetches the content of a protected (non-forwardable) message.

### UserGetMessagesRepliesInfo

```go
func (b *BaleCore) UserGetMessagesRepliesInfo(chatID string, msgIDs []string) (map[string]interface{}, error)
```

Gets reply/thread info for multiple messages.

### UserGetDiscussionMessage

```go
func (b *BaleCore) UserGetDiscussionMessage(chatID string, msgID string) (map[string]interface{}, error)
```

Gets the discussion thread message linked to a channel post.

### UserGetMessageSeenList

```go
func (b *BaleCore) UserGetMessageSeenList(chatID string, msgID string) (map[string]interface{}, error)
```

Returns the list of users who have seen a specific message.

### UserMessageReceived

```go
func (b *BaleCore) UserMessageReceived(chatID string, dateMs int64) (map[string]interface{}, error)
```

Confirms message receipt up to the given date (delivery acknowledgment).

### UserMentionRead

```go
func (b *BaleCore) UserMentionRead(chatID string, msgID string) (map[string]interface{}, error)
```

Marks mention notifications as read for a specific message.

---

## User API -- Groups & Channels

### UserCreateGroup

```go
func (b *BaleCore) UserCreateGroup(title string, userIDs []int64) (map[string]interface{}, error)
```

Creates a new group with initial members.

### UserCreateGroupFull

```go
func (b *BaleCore) UserCreateGroupFull(title string, userIDs []int64, groupType int, username string, restriction int) (map[string]interface{}, error)
```

Creates a group with full configuration. `groupType`: 1=private, 2=public. `restriction`: access level for joining.

### UserEditGroupTitle

```go
func (b *BaleCore) UserEditGroupTitle(groupID int64, title string) (map[string]interface{}, error)
```

Changes a group's title.

### UserEditGroupAbout

```go
func (b *BaleCore) UserEditGroupAbout(groupID int64, about string) (map[string]interface{}, error)
```

Changes a group's description/about text.

### UserInviteUsers

```go
func (b *BaleCore) UserInviteUsers(groupID int64, userIDs []int64) (map[string]interface{}, error)
```

Invites multiple users to a group at once.

### UserInviteUser

```go
func (b *BaleCore) UserInviteUser(groupID int64, userID int64) (map[string]interface{}, error)
```

Invites a single user to a group.

### UserKickUser

```go
func (b *BaleCore) UserKickUser(groupID int64, userID int64) (map[string]interface{}, error)
```

Kicks a user from a group.

### UserMakeUserAdmin

```go
func (b *BaleCore) UserMakeUserAdmin(groupID int64, userID int64) (map[string]interface{}, error)
```

Promotes a user to admin.

### UserRemoveUserAdmin

```go
func (b *BaleCore) UserRemoveUserAdmin(groupID int64, userID int64) (map[string]interface{}, error)
```

Demotes an admin to regular member.

### UserSetMemberPermissions

```go
func (b *BaleCore) UserSetMemberPermissions(groupID int64, userID int64, perms map[string]interface{}) (map[string]interface{}, error)
```

Sets granular permissions for a specific member.

### UserSetGroupDefaultPermissions

```go
func (b *BaleCore) UserSetGroupDefaultPermissions(groupID int64, perms map[string]interface{}) (map[string]interface{}, error)
```

Sets default permissions for all members.

### UserGetMemberPermissions

```go
func (b *BaleCore) UserGetMemberPermissions(groupID int64, userID int64) (map[string]interface{}, error)
```

Gets the permissions for a specific member.

### UserGetFullGroup

```go
func (b *BaleCore) UserGetFullGroup(groupID int64) (map[string]interface{}, error)
```

Loads full group info (title, about, members count, settings, etc.).

### UserLoadMembers

```go
func (b *BaleCore) UserLoadMembers(groupID int64, limit int, next []byte) (map[string]interface{}, error)
```

Loads group members with cursor-based pagination. Pass `next` from previous response for next page.

### UserGetGroupMembersCount

```go
func (b *BaleCore) UserGetGroupMembersCount(groupID int64) (map[string]interface{}, error)
```

Returns the total member count for a group.

### UserGetGroupInviteURL

```go
func (b *BaleCore) UserGetGroupInviteURL(groupID int64) (map[string]interface{}, error)
```

Gets the group's invite link.

### UserRevokeInviteURL

```go
func (b *BaleCore) UserRevokeInviteURL(groupID int64) (map[string]interface{}, error)
```

Revokes the current invite link and generates a new one.

### UserJoinGroup

```go
func (b *BaleCore) UserJoinGroup(token string) (map[string]interface{}, error)
```

Joins a group using an invite token.

### UserJoinPublicGroup

```go
func (b *BaleCore) UserJoinPublicGroup(peerID int64, peerType int) (map[string]interface{}, error)
```

Joins a public group/channel by its peer ID.

### UserLeaveGroup

```go
func (b *BaleCore) UserLeaveGroup(groupID int64) (map[string]interface{}, error)
```

Leaves a group.

### UserGetBannedUsers

```go
func (b *BaleCore) UserGetBannedUsers(groupID int64) (map[string]interface{}, error)
```

Returns the list of banned users in a group.

### UserUnBanUser

```go
func (b *BaleCore) UserUnBanUser(groupID int64, userID int64) (map[string]interface{}, error)
```

Unbans a user from a group.

### UserSetRestriction

```go
func (b *BaleCore) UserSetRestriction(groupID int64, restriction int, username ...string) (map[string]interface{}, error)
```

Sets the group's join restriction (public/private). Optional `username` for public groups.

### UserTransferOwnership

```go
func (b *BaleCore) UserTransferOwnership(groupID int64, newOwnerID int64) (map[string]interface{}, error)
```

Transfers group ownership to another user.

### UserEditChannelNick

```go
func (b *BaleCore) UserEditChannelNick(groupID int64, nick string) (map[string]interface{}, error)
```

Sets or changes a channel's username/nick.

### UserGetGroupPreview

```go
func (b *BaleCore) UserGetGroupPreview(groupID int64) (map[string]interface{}, error)
```

Gets a preview of a group (for non-members).

### UserEditGroupAvatar

```go
func (b *BaleCore) UserEditGroupAvatar(groupID int64, fileID int64, accessHash int64) (map[string]interface{}, error)
```

Sets the group's avatar using a previously uploaded file.

### UserRemoveGroupAvatar

```go
func (b *BaleCore) UserRemoveGroupAvatar(groupID int64) (map[string]interface{}, error)
```

Removes the group's avatar.

### UserLoadFullGroups

```go
func (b *BaleCore) UserLoadFullGroups(groupIDs []int64) (map[string]interface{}, error)
```

Loads full info for multiple groups at once.

### UserGetMyGroups

```go
func (b *BaleCore) UserGetMyGroups() (map[string]interface{}, error)
```

Returns all groups/channels the user is a member of.

### UserLoadGroupAvatars

```go
func (b *BaleCore) UserLoadGroupAvatars(groupID int64) (map[string]interface{}, error)
```

Loads all avatar photos for a group.

### UserEditGroupDefaultCardNumber

```go
func (b *BaleCore) UserEditGroupDefaultCardNumber(groupID int64, cardNumber string) (map[string]interface{}, error)
```

Sets the default bank card number for a group (used for in-group payments).

### UserGetGroupDefaultCardNumber

```go
func (b *BaleCore) UserGetGroupDefaultCardNumber(groupID int64) (map[string]interface{}, error)
```

Gets the group's default bank card number.

### UserSetCanSeeMessages

```go
func (b *BaleCore) UserSetCanSeeMessages(groupID int64, canSee bool) (map[string]interface{}, error)
```

Configures whether new members can see message history before they joined.

### UserGetCanSeeMessages

```go
func (b *BaleCore) UserGetCanSeeMessages(groupID int64) (map[string]interface{}, error)
```

Gets the "can see messages" setting.

### UserFetchGroupAdmins

```go
func (b *BaleCore) UserFetchGroupAdmins(groupID int64) (map[string]interface{}, error)
```

Returns the list of admins for a group.

### UserLoadGroups

```go
func (b *BaleCore) UserLoadGroups(groupIDs []int64) (map[string]interface{}, error)
```

Loads basic info for multiple groups.

### UserSetAvailableReactions

```go
func (b *BaleCore) UserSetAvailableReactions(groupID int64, reactions []string) (map[string]interface{}, error)
```

Sets the allowed reaction emojis for a group.

### UserGetMutualGroups

```go
func (b *BaleCore) UserGetMutualGroups(userID int64) (map[string]interface{}, error)
```

Gets groups that are mutual between you and another user.

### UserSetDiscussionGroup

```go
func (b *BaleCore) UserSetDiscussionGroup(channelID int64, groupID int64) (map[string]interface{}, error)
```

Links a discussion group to a channel.

### UserRemoveDiscussionGroup

```go
func (b *BaleCore) UserRemoveDiscussionGroup(channelID int64) (map[string]interface{}, error)
```

Removes the discussion group link from a channel.

### UserAddDiscussionGroupAdmin

```go
func (b *BaleCore) UserAddDiscussionGroupAdmin(channelID int64, userID int64) (map[string]interface{}, error)
```

Adds an admin to the linked discussion group.

### UserSetCanSeeHistory

```go
func (b *BaleCore) UserSetCanSeeHistory(groupID int64, canSee bool) (map[string]interface{}, error)
```

Configures whether new members can see full history.

### UserGetGroupRecommendations

```go
func (b *BaleCore) UserGetGroupRecommendations(groupID int64) (map[string]interface{}, error)
```

Gets recommended channels/groups based on a group.

### UserSetMemberCustomTitle

```go
func (b *BaleCore) UserSetMemberCustomTitle(groupID int64, userID int64, title string) (map[string]interface{}, error)
```

Sets a custom title for an admin (e.g. "Founder", "Moderator").

---

## User API -- Contacts

### UserSearchContacts

```go
func (b *BaleCore) UserSearchContacts(query string) (map[string]interface{}, error)
```

Searches contacts by name or username.

### UserImportContacts

```go
func (b *BaleCore) UserImportContacts(contacts []map[string]interface{}) (map[string]interface{}, error)
```

Imports contacts from phone address book. Each contact map: `{1: phone, 2: name}`.

### UserAddContact

```go
func (b *BaleCore) UserAddContact(userID int64) (map[string]interface{}, error)
```

Adds a user to contacts by user ID.

### UserRemoveContact

```go
func (b *BaleCore) UserRemoveContact(userID int64) (map[string]interface{}, error)
```

Removes a user from contacts.

### UserGetContacts

```go
func (b *BaleCore) UserGetContacts() (map[string]interface{}, error)
```

Returns the full contact list.

### UserBlockUser

```go
func (b *BaleCore) UserBlockUser(userID int64) (map[string]interface{}, error)
```

Blocks a user (user mode).

### UserUnblockUser

```go
func (b *BaleCore) UserUnblockUser(userID int64) (map[string]interface{}, error)
```

Unblocks a user (user mode).

### UserLoadBlockedUsers

```go
func (b *BaleCore) UserLoadBlockedUsers() (map[string]interface{}, error)
```

Loads the list of blocked users (user mode).

### UserResetContacts

```go
func (b *BaleCore) UserResetContacts() (map[string]interface{}, error)
```

Deletes all contacts.

### UserGetContactsPresences

```go
func (b *BaleCore) UserGetContactsPresences() (map[string]interface{}, error)
```

Gets online/offline status for all contacts.

### UserGetOrganizationalContacts

```go
func (b *BaleCore) UserGetOrganizationalContacts() (map[string]interface{}, error)
```

Gets contacts from the user's organization (Bale corporate feature).

### UserGetAnonymousContactPage

```go
func (b *BaleCore) UserGetAnonymousContactPage() (map[string]interface{}, error)
```

Gets the anonymous contact page (for anonymous messaging feature).

---

## User API -- Media & Files

### UserGetFileUploadURL

```go
func (b *BaleCore) UserGetFileUploadURL(size int64, name string, mimeType string) (map[string]interface{}, error)
```

Gets a presigned URL for uploading a file. Returns the upload URL, file ID, and access hash.

### UserGetFileURL

```go
func (b *BaleCore) UserGetFileURL(fileID int64, accessHash int64) (map[string]interface{}, error)
```

Gets a download URL for a file by its ID and access hash.

---

## User API -- Account & Profile

### UserLoadUsers

```go
func (b *BaleCore) UserLoadUsers(userIDs []int64) (map[string]interface{}, error)
```

Loads basic info for multiple users.

### UserLoadFullUsers

```go
func (b *BaleCore) UserLoadFullUsers(userIDs []int64) (map[string]interface{}, error)
```

Loads full profiles for multiple users.

### UserEditName

```go
func (b *BaleCore) UserEditName(name string) (map[string]interface{}, error)
```

Changes the user's display name.

### UserEditNickName

```go
func (b *BaleCore) UserEditNickName(nick string) (map[string]interface{}, error)
```

Changes the user's nickname/username.

### UserCheckNickName

```go
func (b *BaleCore) UserCheckNickName(nick string) (map[string]interface{}, error)
```

Checks if a nickname is available.

### UserEditAbout

```go
func (b *BaleCore) UserEditAbout(about string) (map[string]interface{}, error)
```

Changes the user's bio/about text.

### UserEditLocalName

```go
func (b *BaleCore) UserEditLocalName(userID int64, localName string) (map[string]interface{}, error)
```

Sets a local display name for another user (only visible to you).

### EditSex

```go
func (b *BaleCore) EditSex(sex int) (map[string]interface{}, error)
```

Updates the user's gender in their profile.

### EditBirthDate

```go
func (b *BaleCore) EditBirthDate(birthDate string) (map[string]interface{}, error)
```

Updates the user's birth date.

### EditAvatarGRPC

```go
func (b *BaleCore) EditAvatarGRPC(fileID int64, accessHash int64) (map[string]interface{}, error)
```

Sets the user's avatar using a previously uploaded file.

### RemoveAvatar

```go
func (b *BaleCore) RemoveAvatar() (map[string]interface{}, error)
```

Removes the user's profile photo.

### EditMyTimeZone

```go
func (b *BaleCore) EditMyTimeZone(timezone string) (map[string]interface{}, error)
```

Sets the user's timezone (e.g. `"Asia/Tehran"`).

### EditMyPreferredLanguages

```go
func (b *BaleCore) EditMyPreferredLanguages(langs []string) (map[string]interface{}, error)
```

Sets preferred languages (e.g. `["fa", "en"]`).

### LoadAvatars

```go
func (b *BaleCore) LoadAvatars(userID int64) (map[string]interface{}, error)
```

Loads all avatar photos for a user.

### NotifyAboutDeviceInfo

```go
func (b *BaleCore) NotifyAboutDeviceInfo(deviceModel, osVersion, appVersion string) (map[string]interface{}, error)
```

Sends device info to the server (used for session management display).

### IsNameAllowed

```go
func (b *BaleCore) IsNameAllowed(name string) (map[string]interface{}, error)
```

Checks if a display name is allowed by Bale's naming policy.

### GetFullUser

```go
func (b *BaleCore) GetFullUser(userID int64) (map[string]interface{}, error)
```

Loads a single user's complete profile (full details, including about, photos, etc.).

### DeleteAccount

```go
func (b *BaleCore) DeleteAccount(reason string) (map[string]interface{}, error)
```

Requests account deletion.

### ChangePhone

```go
func (b *BaleCore) ChangePhone(newPhone string) (map[string]interface{}, error)
```

Initiates a phone number change.

### SendDeleteAccountVerificationCode

```go
func (b *BaleCore) SendDeleteAccountVerificationCode() (map[string]interface{}, error)
```

Sends a verification code for account deletion.

### SendChangePhoneVerificationCode

```go
func (b *BaleCore) SendChangePhoneVerificationCode(newPhone string) (map[string]interface{}, error)
```

Sends a verification code for phone number change.

### ChangePhoneNumber

```go
func (b *BaleCore) ChangePhoneNumber(newPhone string) (map[string]interface{}, error)
```

Alternative phone change method.

### ConfirmPhoneNumber

```go
func (b *BaleCore) ConfirmPhoneNumber(transactionHash, code string) (map[string]interface{}, error)
```

Confirms a phone number change with the verification code.

### UserSignOut

```go
func (b *BaleCore) UserSignOut() (map[string]interface{}, error)
```

Signs out the current user mode session.

### UserSignUp

```go
func (b *BaleCore) UserSignUp(transactionHash string, name string) (map[string]interface{}, error)
```

Completes new account registration with a display name (after phone verification).

### UserValidatePassword

```go
func (b *BaleCore) UserValidatePassword(transactionHash string, password string) (map[string]interface{}, error)
```

Validates a 2FA password during authentication.

---

## User API -- Settings & Privacy

### UserGetParameters

```go
func (b *BaleCore) UserGetParameters() (map[string]interface{}, error)
```

Gets all user parameters/settings.

### UserEditParameter

```go
func (b *BaleCore) UserEditParameter(key string, value string) (map[string]interface{}, error)
```

Edits a single user parameter.

### GetUserPrivacyStatus

```go
func (b *BaleCore) GetUserPrivacyStatus() (map[string]interface{}, error)
```

Gets the user's privacy settings (who can see online status, profile photo, etc.).

### SetUserPrivacyStatus

```go
func (b *BaleCore) SetUserPrivacyStatus(key string, value int) (map[string]interface{}, error)
```

Sets a specific privacy setting. Keys: online status, profile photo, phone number, etc.

### GetUserFullPrivacy

```go
func (b *BaleCore) GetUserFullPrivacy() (map[string]interface{}, error)
```

Gets all privacy settings at once.

---

## User API -- Security & 2FA

### EnableTwoFactorAuthentication

```go
func (b *BaleCore) EnableTwoFactorAuthentication(password string, hint string) (map[string]interface{}, error)
```

Enables 2FA with a password and hint.

### DisableTwoFactorAuthentication

```go
func (b *BaleCore) DisableTwoFactorAuthentication(password string) (map[string]interface{}, error)
```

Disables 2FA (requires current password).

### IsTwoFactorAuthenticationEnabled

```go
func (b *BaleCore) IsTwoFactorAuthenticationEnabled() (map[string]interface{}, error)
```

Checks if 2FA is enabled.

### VerifyEmail

```go
func (b *BaleCore) VerifyEmail(email string, code string) (map[string]interface{}, error)
```

Verifies an email address with a code.

### RecoverPassword

```go
func (b *BaleCore) RecoverPassword() (map[string]interface{}, error)
```

Initiates password recovery (sends recovery code to email).

### VerifyPasswordRecovery

```go
func (b *BaleCore) VerifyPasswordRecovery(code string) (map[string]interface{}, error)
```

Verifies a password recovery code.

### SetNewPassword

```go
func (b *BaleCore) SetNewPassword(transactionHash, newPassword, hint string) (map[string]interface{}, error)
```

Sets a new password after recovery.

---

## User API -- Sessions

### TerminateAllSessions

```go
func (b *BaleCore) TerminateAllSessions() (map[string]interface{}, error)
```

Terminates all other sessions except the current one.

### UserTerminateSession

```go
func (b *BaleCore) UserTerminateSession(sessionID int64) (map[string]interface{}, error)
```

Terminates a specific session by its numeric ID.

---

## User API -- Presence & Online

### UserSetOnline

```go
func (b *BaleCore) UserSetOnline(isOnline bool, duration int) (map[string]interface{}, error)
```

Sets online/offline status. `duration` is how long to remain online (seconds).

### UserTyping

```go
func (b *BaleCore) UserTyping(chatID string) (map[string]interface{}, error)
```

Sends a typing indicator to a chat.

### UserStopTyping

```go
func (b *BaleCore) UserStopTyping(chatID string) (map[string]interface{}, error)
```

Stops the typing indicator.

### UserGetGroupMembersPresences

```go
func (b *BaleCore) UserGetGroupMembersPresences(groupID int64) (map[string]interface{}, error)
```

Gets online status for all members of a group.

### UserGetGroupOnlineCount

```go
func (b *BaleCore) UserGetGroupOnlineCount(groupID int64) (map[string]interface{}, error)
```

Returns how many members are currently online in a group.

### UserGetUsersPresence

```go
func (b *BaleCore) UserGetUsersPresence(userIDs []int64) (map[string]interface{}, error)
```

Gets online/offline status for specific users.

### UserSubscribeToOnline

```go
func (b *BaleCore) UserSubscribeToOnline(userIDs []int64) (map[string]interface{}, error)
```

Subscribes to online status updates for specific users. You'll receive real-time notifications when they come online/go offline.

### UserSubscribeFromOnline

```go
func (b *BaleCore) UserSubscribeFromOnline(userIDs []int64) (map[string]interface{}, error)
```

Unsubscribes from online status updates.

### UserSubscribeToGroupOnline

```go
func (b *BaleCore) UserSubscribeToGroupOnline(groupID int64) (map[string]interface{}, error)
```

Subscribes to online count updates for a group.

### UserSubscribeFromGroupOnline

```go
func (b *BaleCore) UserSubscribeFromGroupOnline(groupID int64) (map[string]interface{}, error)
```

Unsubscribes from group online count updates.

---

## User API -- Dialogs

### UserLoadDialogs

```go
func (b *BaleCore) UserLoadDialogs(offsetDate int64, limit int) (map[string]interface{}, error)
```

Loads the dialog list with pagination. `offsetDate` in milliseconds.

### LoadDialogsFiltered

```go
func (b *BaleCore) LoadDialogsFiltered(offsetDate int64, limit int, folderID int64, archived bool, excludePinned bool) (map[string]interface{}, error)
```

Loads dialogs with folder/archive/pin filters.

### UserLoadDialogsFiltered

```go
func (b *BaleCore) UserLoadDialogsFiltered(filterType int, offset int64, limit int) (map[string]interface{}, error)
```

Loads dialogs filtered by type (user-mode variant).

### UserLoadFolderDialogs

```go
func (b *BaleCore) UserLoadFolderDialogs(folderID int64, offsetDate int64, limit int) (map[string]interface{}, error)
```

Loads dialogs within a specific folder.

### UserLoadGroupedDialogs

```go
func (b *BaleCore) UserLoadGroupedDialogs(offsetDate int64, limit int) (map[string]interface{}, error)
```

Loads dialogs grouped by category (contacts, groups, channels, bots).

### UserLoadPeerDialogs

```go
func (b *BaleCore) UserLoadPeerDialogs(peerIDs []string) (map[string]interface{}, error)
```

Loads dialog info for specific peers.

### UserLoadPeers

```go
func (b *BaleCore) UserLoadPeers(peerIDs []string) (map[string]interface{}, error)
```

Loads peer info (user/group basic data) for specific IDs.

### UserLoadPinnedDialogs

```go
func (b *BaleCore) UserLoadPinnedDialogs() (map[string]interface{}, error)
```

Loads all pinned dialogs.

### UserArchiveDialogs

```go
func (b *BaleCore) UserArchiveDialogs(chatIDs []string) (map[string]interface{}, error)
```

Archives multiple dialogs at once.

### UserUnArchiveDialogs

```go
func (b *BaleCore) UserUnArchiveDialogs(chatIDs []string) (map[string]interface{}, error)
```

Unarchives multiple dialogs.

### UserPinDialogs

```go
func (b *BaleCore) UserPinDialogs(chatIDs []string) (map[string]interface{}, error)
```

Pins multiple dialogs.

### UserUnpinDialogs

```go
func (b *BaleCore) UserUnpinDialogs(chatIDs []string) (map[string]interface{}, error)
```

Unpins multiple dialogs.

### UserReorderPinnedDialogs

```go
func (b *BaleCore) UserReorderPinnedDialogs(chatIDs []string) (map[string]interface{}, error)
```

Reorders the pinned dialogs list.

### UserMarkDialogsAsRead

```go
func (b *BaleCore) UserMarkDialogsAsRead(chatIDs []string) (map[string]interface{}, error)
```

Marks multiple dialogs as read.

### UserMarkAsUnread

```go
func (b *BaleCore) UserMarkAsUnread(chatID string, unread bool) (map[string]interface{}, error)
```

Marks a dialog as unread or read.

---

## User API -- Topics & Threads

### UserCreateThread

```go
func (b *BaleCore) UserCreateThread(chatID string, msgID string) (map[string]interface{}, error)
```

Creates a thread from a specific message.

### UserCreateTopic

```go
func (b *BaleCore) UserCreateTopic(chatID string, title string) (map[string]interface{}, error)
```

Creates a topic in a group that supports topics.

### UserGetTopics

```go
func (b *BaleCore) UserGetTopics(chatID string) (map[string]interface{}, error)
```

Gets all topics in a group.

### UserGetTopicByID

```go
func (b *BaleCore) UserGetTopicByID(chatID string, topicID int64) (map[string]interface{}, error)
```

Gets a specific topic by ID.

### EditTopic

```go
func (b *BaleCore) EditTopic(chatID string, topicID int64, title string) (map[string]interface{}, error)
```

Edits a topic's title.

### DeleteTopic

```go
func (b *BaleCore) DeleteTopic(chatID string, topicID int64) (map[string]interface{}, error)
```

Deletes a topic.

### UserLoadReplies

```go
func (b *BaleCore) UserLoadReplies(chatID string, msgID string, offsetDate int64, limit int) (map[string]interface{}, error)
```

Loads replies to a specific message (thread view).

### UserSubscribeToThreadUpdates

```go
func (b *BaleCore) UserSubscribeToThreadUpdates(chatID string, threadID int64) (map[string]interface{}, error)
```

Subscribes to real-time updates for a specific thread.

### UserUnsubscribeFromThreadUpdates

```go
func (b *BaleCore) UserUnsubscribeFromThreadUpdates(chatID string, threadID int64) (map[string]interface{}, error)
```

Unsubscribes from thread updates.

---

## User API -- Search

### SearchPeerMessages

```go
func (b *BaleCore) SearchPeerMessages(chatID string, query string, limit int) (map[string]interface{}, error)
```

Searches messages within a specific chat.

### SearchPeerMedia

```go
func (b *BaleCore) SearchPeerMedia(chatID string, mediaType int, limit int) (map[string]interface{}, error)
```

Searches for media files in a chat by type (photo, video, document, etc.).

### SearchMembers

```go
func (b *BaleCore) SearchMembers(chatID string, query string) (map[string]interface{}, error)
```

Searches group members by name or username.

### SearchLinks

```go
func (b *BaleCore) SearchLinks(chatID string, limit int) (map[string]interface{}, error)
```

Searches for URLs/links shared in a chat.

### GlobalChannelSearch

```go
func (b *BaleCore) GlobalChannelSearch(query string, limit int) (map[string]interface{}, error)
```

Searches for public channels globally.

### UserSearchMessages

```go
func (b *BaleCore) UserSearchMessages(query string, chatID string, limit int) (map[string]interface{}, error)
```

User mode message search (searches via Search service).

### UserSearchMessageMore

```go
func (b *BaleCore) UserSearchMessageMore(query string, chatID string, offset int64, limit int) (map[string]interface{}, error)
```

Continues a message search with offset pagination.

### UserSearchPeer

```go
func (b *BaleCore) UserSearchPeer(query string, limit int) (map[string]interface{}, error)
```

Searches for users and groups by name/username.

### UserSearchMediaService

```go
func (b *BaleCore) UserSearchMediaService(chatID string, mediaType int, limit int) (map[string]interface{}, error)
```

Searches media in a chat via the Search service.

### UserSearchMembersService

```go
func (b *BaleCore) UserSearchMembersService(chatID string, query string) (map[string]interface{}, error)
```

Searches group members via the Search service.

### UserSearchDialog

```go
func (b *BaleCore) UserSearchDialog(query string, limit int) (map[string]interface{}, error)
```

Searches dialogs by name/title.

### UserSearchContent

```go
func (b *BaleCore) UserSearchContent(query string, limit int) (map[string]interface{}, error)
```

Searches all content (messages, media, links) globally.

### UserUpdateSearchContentClick

```go
func (b *BaleCore) UserUpdateSearchContentClick(contentID string) (map[string]interface{}, error)
```

Reports a click on a search result (for search ranking).

---

## Polls

### UserCreatePoll

```go
func (b *BaleCore) UserCreatePoll(chatID string, question string, options []string, multipleChoice bool, anonymous bool) (map[string]interface{}, error)
```

Creates a poll with full options (multiple choice, anonymous voting).

### ClosePoll

```go
func (b *BaleCore) ClosePoll(chatID string, rid int64, date int64) (map[string]interface{}, error)
```

Closes an active poll (stops accepting votes).

### GetPollResults

```go
func (b *BaleCore) GetPollResults(chatID string, rid int64, date int64) (map[string]interface{}, error)
```

Gets the current results of a poll.

### GetFullPollResult

```go
func (b *BaleCore) GetFullPollResult(chatID string, rid int64, date int64, optionIndex int) (map[string]interface{}, error)
```

Gets detailed results for a specific poll option (who voted for it).

### UserClosePollService

```go
func (b *BaleCore) UserClosePollService(chatID string, msgID string) (map[string]interface{}, error)
```

Closes a poll via the Poll service.

### UserVotePollService

```go
func (b *BaleCore) UserVotePollService(chatID string, msgID string, optionIndices []int) (map[string]interface{}, error)
```

Votes on a poll via the Poll service. Supports multiple option indices for multi-choice polls.

### UserGetPollResultsService

```go
func (b *BaleCore) UserGetPollResultsService(chatID string, msgID string) (map[string]interface{}, error)
```

Gets poll results via the Poll service.

### UserGetFullPollResultService

```go
func (b *BaleCore) UserGetFullPollResultService(chatID string, msgID string, optionIndex int) (map[string]interface{}, error)
```

Gets detailed results for a poll option via the Poll service.

---

## Reactions

### UserSetReaction

```go
func (b *BaleCore) UserSetReaction(chatID string, rid int64, emoji string, date int64) (map[string]interface{}, error)
```

Adds a reaction to a message.

### UserRemoveReaction

```go
func (b *BaleCore) UserRemoveReaction(chatID string, rid int64, emoji string, date int64) (map[string]interface{}, error)
```

Removes a reaction from a message.

### UserGetReactions

```go
func (b *BaleCore) UserGetReactions(chatID string, rids []int64, dates []int64) (map[string]interface{}, error)
```

Gets reactions for multiple messages at once.

### UserGetReactionsList

```go
func (b *BaleCore) UserGetReactionsList(chatID string, rid int64, dateMs int64, emoji string) (map[string]interface{}, error)
```

Gets the list of users who reacted with a specific emoji.

### UserGetMessageViews

```go
func (b *BaleCore) UserGetMessageViews(chatID string, dates []int64, rids []int64) (map[string]interface{}, error)
```

Gets view counts for multiple messages (channel posts).

### UserEnableShowReactionFlag

```go
func (b *BaleCore) UserEnableShowReactionFlag(enabled bool) (map[string]interface{}, error)
```

Enables or disables showing your reactions to others.

### UserGetShowReactionFlag

```go
func (b *BaleCore) UserGetShowReactionFlag() (map[string]interface{}, error)
```

Gets the current "show reaction" flag.

### UserLoadReactions

```go
func (b *BaleCore) UserLoadReactions() (map[string]interface{}, error)
```

Loads all available reaction emojis.

### UserMessageReactionsRead

```go
func (b *BaleCore) UserMessageReactionsRead(chatID string, msgID string) (map[string]interface{}, error)
```

Marks reaction notifications as read.

---

## Upvotes

### UpvotePost

```go
func (b *BaleCore) UpvotePost(chatID string, rid int64, date int64) (map[string]interface{}, error)
```

Upvotes a channel post.

### RevokeUpvotedPost

```go
func (b *BaleCore) RevokeUpvotedPost(chatID string, rid int64, date int64) (map[string]interface{}, error)
```

Removes an upvote from a post.

### GetMessageUpvoters

```go
func (b *BaleCore) GetMessageUpvoters(chatID string, rid int64, date int64) (map[string]interface{}, error)
```

Gets the list of users who upvoted a post.

### UserGetMyUpvotes

```go
func (b *BaleCore) UserGetMyUpvotes(offset int64, limit int) (map[string]interface{}, error)
```

Gets posts you've upvoted, with pagination.

---

## Folders

### LoadFolders

```go
func (b *BaleCore) LoadFolders() (map[string]interface{}, error)
```

Loads all dialog folders (user mode).

### EditFolder

```go
func (b *BaleCore) EditFolder(folderID int64, title string) (map[string]interface{}, error)
```

Edits a folder's title.

### DeleteFolder

```go
func (b *BaleCore) DeleteFolder(folderID int64) (map[string]interface{}, error)
```

Deletes a folder.

### ReorderFolders

```go
func (b *BaleCore) ReorderFolders(folderIDs []int64) (map[string]interface{}, error)
```

Reorders folders by specifying the desired order of IDs.

### UserCreateFolder

```go
func (b *BaleCore) UserCreateFolder(title string, peerIDs []string) (map[string]interface{}, error)
```

Creates a new folder with specific peers (user mode).

### UserCreateReservedFolder

```go
func (b *BaleCore) UserCreateReservedFolder(title string) (map[string]interface{}, error)
```

Creates a reserved (system) folder.

---

## Calls

### ReceiveCall

```go
func (b *BaleCore) ReceiveCall(callID int64) (map[string]interface{}, error)
```

Receives/accepts an incoming call by call ID (signaling level).

### DiscardCall

```go
func (b *BaleCore) DiscardCall(callID int64) (map[string]interface{}, error)
```

Discards/rejects a call by call ID (signaling level).

---

## User API -- Calls (Extended)

### UserAcceptCallMeet

```go
func (b *BaleCore) UserAcceptCallMeet(callID int64) (map[string]interface{}, error)
```

Accepts a call via the Meet service.

### UserGetCallState

```go
func (b *BaleCore) UserGetCallState(callID int64) (map[string]interface{}, error)
```

Gets the current state of a call (ringing, connected, ended).

### UserDeleteCallLogs

```go
func (b *BaleCore) UserDeleteCallLogs(callIDs []int64) (map[string]interface{}, error)
```

Deletes call log entries.

### UserInviteToCall

```go
func (b *BaleCore) UserInviteToCall(callID int64, userIDs []int64) (map[string]interface{}, error)
```

Invites additional users to an ongoing call.

### UserAskToJoinCall

```go
func (b *BaleCore) UserAskToJoinCall(callID int64) (map[string]interface{}, error)
```

Requests to join an ongoing call (requires approval from call admin).

### UserAnswerCallJoinRequest

```go
func (b *BaleCore) UserAnswerCallJoinRequest(callID int64, userID int64, accept bool) (map[string]interface{}, error)
```

Accepts or rejects a join request for a call.

### UserSendCallReaction

```go
func (b *BaleCore) UserSendCallReaction(callID int64, reaction string) (map[string]interface{}, error)
```

Sends a reaction emoji during a call (e.g. clap, thumbs up).

### UserSubmitCallFeedback

```go
func (b *BaleCore) UserSubmitCallFeedback(callID int64, rating int, comment string) (map[string]interface{}, error)
```

Submits call quality feedback after a call ends.

### UserMuteCallParticipant

```go
func (b *BaleCore) UserMuteCallParticipant(callID int64, userID int64, muted bool) (map[string]interface{}, error)
```

Mutes or unmutes a participant in a group call (admin only).

### UserRemoveCallParticipant

```go
func (b *BaleCore) UserRemoveCallParticipant(callID int64, userID int64) (map[string]interface{}, error)
```

Removes a participant from a group call.

### UserStartRecording

```go
func (b *BaleCore) UserStartRecording(callID int64) (map[string]interface{}, error)
```

Starts recording a call.

### UserStopRecording

```go
func (b *BaleCore) UserStopRecording(callID int64) (map[string]interface{}, error)
```

Stops call recording.

### UserStartStream

```go
func (b *BaleCore) UserStartStream(callID int64) (map[string]interface{}, error)
```

Starts screen sharing/streaming in a call.

### UserDeleteStream

```go
func (b *BaleCore) UserDeleteStream(callID int64) (map[string]interface{}, error)
```

Stops screen sharing/streaming.

### UserUpdateCallLayout

```go
func (b *BaleCore) UserUpdateCallLayout(callID int64, layout int) (map[string]interface{}, error)
```

Changes the call display layout (grid, speaker, etc.).

### UserGenerateCallLink

```go
func (b *BaleCore) UserGenerateCallLink(callID int64) (map[string]interface{}, error)
```

Generates a shareable link for joining a call.

### UserGetCallLinkDetails

```go
func (b *BaleCore) UserGetCallLinkDetails(link string) (map[string]interface{}, error)
```

Gets details about a call from its link.

### UserSetCallLinkTitle

```go
func (b *BaleCore) UserSetCallLinkTitle(callID int64, title string) (map[string]interface{}, error)
```

Sets a title for a call link.

### UserSendCallFanoosEvent

```go
func (b *BaleCore) UserSendCallFanoosEvent(callID int64, eventName string) (map[string]interface{}, error)
```

Sends a Fanoos analytics event during a call.

### UserTakeCallAction

```go
func (b *BaleCore) UserTakeCallAction(callID int64, action int) (map[string]interface{}, error)
```

Takes a generic call action by action code.

---

## Stories

### UserAddStory

```go
func (b *BaleCore) UserAddStory(content map[string]interface{}) (map[string]interface{}, error)
```

Posts a story to your profile.

### UserAddChannelStory

```go
func (b *BaleCore) UserAddChannelStory(channelID int64, content map[string]interface{}) (map[string]interface{}, error)
```

Posts a story to a channel.

### UserAddBotStory

```go
func (b *BaleCore) UserAddBotStory(botID int64, content map[string]interface{}) (map[string]interface{}, error)
```

Posts a story for a bot.

### UserCanAddBotStory

```go
func (b *BaleCore) UserCanAddBotStory(botID int64) (map[string]interface{}, error)
```

Checks if the user can add stories for a specific bot.

### UserRemoveStory

```go
func (b *BaleCore) UserRemoveStory(storyID int64) (map[string]interface{}, error)
```

Deletes a story.

### UserGetStoryViewers

```go
func (b *BaleCore) UserGetStoryViewers(storyID int64, offset int64, limit int) (map[string]interface{}, error)
```

Gets the list of users who viewed a story.

### UserGetStoryViewersCount

```go
func (b *BaleCore) UserGetStoryViewersCount(storyID int64) (map[string]interface{}, error)
```

Gets the total number of viewers for a story.

### UserGetStories

```go
func (b *BaleCore) UserGetStories(peerID int64) (map[string]interface{}, error)
```

Gets all stories for a user.

### UserGetChannelStories

```go
func (b *BaleCore) UserGetChannelStories(channelID int64) (map[string]interface{}, error)
```

Gets all stories for a channel.

### UserGetBotStories

```go
func (b *BaleCore) UserGetBotStories(botID int64) (map[string]interface{}, error)
```

Gets all stories for a bot.

### UserReactToStory

```go
func (b *BaleCore) UserReactToStory(storyID int64, reaction string) (map[string]interface{}, error)
```

Reacts to a story with an emoji.

### UserGetStoryByID

```go
func (b *BaleCore) UserGetStoryByID(storyID int64) (map[string]interface{}, error)
```

Gets a specific story by its ID.

### UserGetStoryPrivacyConfig

```go
func (b *BaleCore) UserGetStoryPrivacyConfig() (map[string]interface{}, error)
```

Gets story privacy settings (who can see your stories).

### UserSetStoryPrivacyConfig

```go
func (b *BaleCore) UserSetStoryPrivacyConfig(config map[string]interface{}) (map[string]interface{}, error)
```

Sets story privacy settings.

### UserGetDefaultStoryBackgrounds

```go
func (b *BaleCore) UserGetDefaultStoryBackgrounds() (map[string]interface{}, error)
```

Gets available default backgrounds for text stories.

### UserGetMostPopularStories

```go
func (b *BaleCore) UserGetMostPopularStories() (map[string]interface{}, error)
```

Gets trending/popular stories.

### UserGetStoryWidgets

```go
func (b *BaleCore) UserGetStoryWidgets() (map[string]interface{}, error)
```

Gets available interactive widgets for stories (polls, links, etc.).

### UserGetUserStoryConfig

```go
func (b *BaleCore) UserGetUserStoryConfig() (map[string]interface{}, error)
```

Gets the user's story creation config (limits, features).

### UserSetUserStoryConfig

```go
func (b *BaleCore) UserSetUserStoryConfig(config map[string]interface{}) (map[string]interface{}, error)
```

Sets the user's story creation config.

### UserGetStoriesByList

```go
func (b *BaleCore) UserGetStoriesByList(storyIDs []int64) (map[string]interface{}, error)
```

Gets multiple stories by their IDs.

### UserGetStoryReactionEmojis

```go
func (b *BaleCore) UserGetStoryReactionEmojis() (map[string]interface{}, error)
```

Gets available emojis for story reactions.

### UserGetStoryTags

```go
func (b *BaleCore) UserGetStoryTags() (map[string]interface{}, error)
```

Gets available story tags.

### UserCheckStoryLinkValidity

```go
func (b *BaleCore) UserCheckStoryLinkValidity(link string) (map[string]interface{}, error)
```

Checks if a story link is valid and accessible.

---

## GIFs & Stickers (User)

### UserAddGif

```go
func (b *BaleCore) UserAddGif(fileID int64, accessHash int64) (map[string]interface{}, error)
```

Saves a GIF to the user's saved GIFs collection.

### UserRemoveGif

```go
func (b *BaleCore) UserRemoveGif(fileID int64) (map[string]interface{}, error)
```

Removes a GIF from saved GIFs.

### UserUseGif

```go
func (b *BaleCore) UserUseGif(fileID int64) (map[string]interface{}, error)
```

Records a GIF usage (for sorting by recently used).

### UserGetSavedGifs

```go
func (b *BaleCore) UserGetSavedGifs() (map[string]interface{}, error)
```

Gets all saved GIFs.

### UserAddStickerCollection

```go
func (b *BaleCore) UserAddStickerCollection(collectionID int64) (map[string]interface{}, error)
```

Adds a sticker collection to the user's library.

### UserRemoveStickerCollection

```go
func (b *BaleCore) UserRemoveStickerCollection(collectionID int64) (map[string]interface{}, error)
```

Removes a sticker collection.

### UserAddStickerPack

```go
func (b *BaleCore) UserAddStickerPack(packID int64) (map[string]interface{}, error)
```

Adds a sticker pack.

### UserRemoveStickerPack

```go
func (b *BaleCore) UserRemoveStickerPack(packID int64) (map[string]interface{}, error)
```

Removes a sticker pack.

### UserLoadOwnStickers

```go
func (b *BaleCore) UserLoadOwnStickers() (map[string]interface{}, error)
```

Loads all sticker packs/collections owned by the user.

### UserLoadStickerCollection

```go
func (b *BaleCore) UserLoadStickerCollection(collectionID int64) (map[string]interface{}, error)
```

Loads all stickers in a specific collection.

---

## Bots & Mini-Apps (User)

### UserSendInlineCallBackData

```go
func (b *BaleCore) UserSendInlineCallBackData(botID int64, queryID string, data string) (map[string]interface{}, error)
```

Sends callback data to a bot from an inline keyboard button.

### UserSendInlineCallback

```go
func (b *BaleCore) UserSendInlineCallback(botID int64, queryID string, data string) (map[string]interface{}, error)
```

Sends an inline callback to a bot.

### UserSendAuthenticatedInlineCallBackData

```go
func (b *BaleCore) UserSendAuthenticatedInlineCallBackData(botID int64, queryID string, data string) (map[string]interface{}, error)
```

Sends an authenticated callback (includes user identity verification).

### UserSendMiniAppData

```go
func (b *BaleCore) UserSendMiniAppData(botID int64, data string) (map[string]interface{}, error)
```

Sends data from a mini-app to its bot.

### UserGetBotWhiteList

```go
func (b *BaleCore) UserGetBotWhiteList() (map[string]interface{}, error)
```

Gets the bot whitelist (allowed bots).

### UserGetUserContext

```go
func (b *BaleCore) UserGetUserContext(botID int64) (map[string]interface{}, error)
```

Gets the user's context with a specific bot (session data).

### UserGetWebappHash

```go
func (b *BaleCore) UserGetWebappHash(botID int64) (map[string]interface{}, error)
```

Gets the webapp hash for bot authentication.

### UserGetBots

```go
func (b *BaleCore) UserGetBots() (map[string]interface{}, error)
```

Gets all bots the user interacts with.

### UserGetBotInfo

```go
func (b *BaleCore) UserGetBotInfo(botID int64) (map[string]interface{}, error)
```

Gets detailed info about a bot.

### UserGetInlineBotResults

```go
func (b *BaleCore) UserGetInlineBotResults(botID int64, query string, offset string) (map[string]interface{}, error)
```

Gets inline query results from a bot.

### UserGetBotGroupPermissions

```go
func (b *BaleCore) UserGetBotGroupPermissions(botID int64, groupID int64) (map[string]interface{}, error)
```

Gets a bot's permissions in a specific group.

### UserGetPaymentDetails

```go
func (b *BaleCore) UserGetPaymentDetails(paymentID string) (map[string]interface{}, error)
```

Gets details of a payment transaction.

### UserMakePayment

```go
func (b *BaleCore) UserMakePayment(paymentID string) (map[string]interface{}, error)
```

Executes a payment.

### UserInvokeCustomAction

```go
func (b *BaleCore) UserInvokeCustomAction(botID int64, action string, data string) (map[string]interface{}, error)
```

Invokes a custom bot action.

### GetMiniAppUrl

```go
func (b *BaleCore) GetMiniAppUrl(botID int64, shortName string) (map[string]interface{}, error)
```

Gets the URL for opening a mini-app (Appzar service).

### GetBotMenuButtons

```go
func (b *BaleCore) GetBotMenuButtons(botID int64) (map[string]interface{}, error)
```

Gets the menu buttons configured for a bot.

### InvokeCustomMethod

```go
func (b *BaleCore) InvokeCustomMethod(botID int64, method string, params string) (map[string]interface{}, error)
```

Invokes a custom method on a bot.

### UserGetMiniAppUrlAppzar

```go
func (b *BaleCore) UserGetMiniAppUrlAppzar(botID int64, shortName string) (map[string]interface{}, error)
```

Gets mini-app URL via the Appzar service.

### UserGetMenuButton

```go
func (b *BaleCore) UserGetMenuButton(botID int64) (map[string]interface{}, error)
```

Gets a bot's menu button (user mode).

### UserInvokeCustomMethodAppzar

```go
func (b *BaleCore) UserInvokeCustomMethodAppzar(botID int64, method string, params string) (map[string]interface{}, error)
```

Invokes a custom method via the Appzar service.

### UserSetMyCommands

```go
func (b *BaleCore) UserSetMyCommands(commands []map[string]interface{}) (map[string]interface{}, error)
```

Sets bot commands (user mode).

### UserDeleteMyCommands

```go
func (b *BaleCore) UserDeleteMyCommands() (map[string]interface{}, error)
```

Deletes bot commands (user mode).

### UserGetMyCommands

```go
func (b *BaleCore) UserGetMyCommands() (map[string]interface{}, error)
```

Gets bot commands (user mode).

---

## Push Notifications

### RegisterPush

```go
func (b *BaleCore) RegisterPush(token string, platform int) (map[string]interface{}, error)
```

Registers a push notification token.

### UnregisterPush

```go
func (b *BaleCore) UnregisterPush(token string) (map[string]interface{}, error)
```

Unregisters a push notification token.

### RegisterGooglePush

```go
func (b *BaleCore) RegisterGooglePush(token string) (map[string]interface{}, error)
```

Registers a Google FCM push token.

### UnregisterGooglePush

```go
func (b *BaleCore) UnregisterGooglePush(token string) (map[string]interface{}, error)
```

Unregisters a Google FCM push token.

### UnregisterAllPushCredentials

```go
func (b *BaleCore) UnregisterAllPushCredentials() (map[string]interface{}, error)
```

Removes all push notification registrations.

### PushSetConfig

```go
func (b *BaleCore) PushSetConfig(config map[string]interface{}) (map[string]interface{}, error)
```

Sets push notification configuration (which events trigger notifications).

### UserPushSetConfig

```go
func (b *BaleCore) UserPushSetConfig(config map[string]interface{}) (map[string]interface{}, error)
```

Sets push config (user mode variant).

---

## Ramz (Financial Security)

Bale's "Ramz" is a secondary password layer for financial operations.

### SetRamzPassword

```go
func (b *BaleCore) SetRamzPassword(password string) (map[string]interface{}, error)
```

Sets the Ramz financial password.

### DeleteRamzPassword

```go
func (b *BaleCore) DeleteRamzPassword(password string) (map[string]interface{}, error)
```

Deletes the Ramz password (requires current password).

### SendRamzOTP

```go
func (b *BaleCore) SendRamzOTP() (map[string]interface{}, error)
```

Sends a one-time code for Ramz password recovery.

### ForgetRamzPassword

```go
func (b *BaleCore) ForgetRamzPassword(otp string) (map[string]interface{}, error)
```

Resets the Ramz password using an OTP.

### ValidateRamzOTP

```go
func (b *BaleCore) ValidateRamzOTP(otp string) (map[string]interface{}, error)
```

Validates a Ramz OTP code.

### CheckRamzPasswordSet

```go
func (b *BaleCore) CheckRamzPasswordSet() (map[string]interface{}, error)
```

Checks if a Ramz password has been set.

### CheckRamzPassword

```go
func (b *BaleCore) CheckRamzPassword(password string) (map[string]interface{}, error)
```

Verifies a Ramz password.

---

## Reporting

### ReportInappropriateContent

```go
func (b *BaleCore) ReportInappropriateContent(chatID string, rid int64, reason string) (map[string]interface{}, error)
```

Reports a message for inappropriate content.

### ReportDismiss

```go
func (b *BaleCore) ReportDismiss(chatID string) (map[string]interface{}, error)
```

Dismisses the report prompt for a chat.

---

## Scheduled Tasks

### UserScheduleTask

```go
func (b *BaleCore) UserScheduleTask(chatID string, task map[string]interface{}) (map[string]interface{}, error)
```

Schedules a task (e.g. scheduled message, reminder).

### UserUnScheduleTask

```go
func (b *BaleCore) UserUnScheduleTask(taskID int64) (map[string]interface{}, error)
```

Cancels a scheduled task.

### UserListScheduledTasks

```go
func (b *BaleCore) UserListScheduledTasks(chatID string) (map[string]interface{}, error)
```

Lists all scheduled tasks for a chat.

### UserExecuteTaskNow

```go
func (b *BaleCore) UserExecuteTaskNow(taskID int64) (map[string]interface{}, error)
```

Immediately executes a scheduled task.

### UserReScheduleTask

```go
func (b *BaleCore) UserReScheduleTask(taskID int64, newDate int64) (map[string]interface{}, error)
```

Reschedules a task to a new time.

### UserPeersWithScheduleTask

```go
func (b *BaleCore) UserPeersWithScheduleTask() (map[string]interface{}, error)
```

Gets all peers that have scheduled tasks.

---

## Message Streams

### UserCancelMessageStream

```go
func (b *BaleCore) UserCancelMessageStream(streamID int64) (map[string]interface{}, error)
```

Cancels an active message stream.

### UserReceiveMessageStream

```go
func (b *BaleCore) UserReceiveMessageStream(streamID int64) (map[string]interface{}, error)
```

Receives data from a message stream (streaming responses, e.g. AI-generated text).

---

## Links & Previews

### UserGetLinkSummary

```go
func (b *BaleCore) UserGetLinkSummary(url string) (map[string]interface{}, error)
```

Gets a summary/preview for a URL.

### UserGetLinkPreview

```go
func (b *BaleCore) UserGetLinkPreview(url string) (map[string]interface{}, error)
```

Gets a rich link preview (title, description, image) for a URL.

### UserGetLinkStatus

```go
func (b *BaleCore) UserGetLinkStatus(link string) (map[string]interface{}, error)
```

Checks the status of a Bale invite/join link.

---

## Shared Media

### UserLoadSharedMedia

```go
func (b *BaleCore) UserLoadSharedMedia(chatID string, mediaType int, offset int64, limit int) (map[string]interface{}, error)
```

Loads shared media files in a chat (photos, videos, documents, links, audio).

### UserGetActiveSharedMedia

```go
func (b *BaleCore) UserGetActiveSharedMedia(chatID string) (map[string]interface{}, error)
```

Gets counts of active shared media by type for a chat.

---

## Feeds & Magazine

### UserLoadFeedMessages

```go
func (b *BaleCore) UserLoadFeedMessages(offset int64, limit int) (map[string]interface{}, error)
```

Loads the user's feed (aggregated channel posts).

### UserLoadInternalFeedMessages

```go
func (b *BaleCore) UserLoadInternalFeedMessages(offset int64, limit int) (map[string]interface{}, error)
```

Loads internal (Bale-curated) feed messages.

### UserLoadCategoryFeedMessages

```go
func (b *BaleCore) UserLoadCategoryFeedMessages(categoryID int64, offset int64, limit int) (map[string]interface{}, error)
```

Loads feed messages for a specific category.

### UserLoadMagazineCategories

```go
func (b *BaleCore) UserLoadMagazineCategories() (map[string]interface{}, error)
```

Gets available magazine/feed categories.

### UserGetSimilarPosts

```go
func (b *BaleCore) UserGetSimilarPosts(chatID string, msgID string) (map[string]interface{}, error)
```

Gets posts similar to a given one (content recommendation).

---

## Recommendations

### UserGetTopPeer

```go
func (b *BaleCore) UserGetTopPeer() (map[string]interface{}, error)
```

Gets the user's most-contacted peers.

### UserRemoveTopPeer

```go
func (b *BaleCore) UserRemoveTopPeer(peerID string) (map[string]interface{}, error)
```

Removes a peer from the top peers list.

### UserGetChannelRecommendations

```go
func (b *BaleCore) UserGetChannelRecommendations(channelID int64) (map[string]interface{}, error)
```

Gets recommended channels based on a channel.

### UserGetRelatedChannels

```go
func (b *BaleCore) UserGetRelatedChannels(channelID int64) (map[string]interface{}, error)
```

Gets channels related to a specific channel.

### UserGetGroupsRecommendation

```go
func (b *BaleCore) UserGetGroupsRecommendation() (map[string]interface{}, error)
```

Gets recommended groups.

### UserGetRelatedGroups

```go
func (b *BaleCore) UserGetRelatedGroups(groupID int64) (map[string]interface{}, error)
```

Gets groups related to a specific group.

---

## Nasim File System

Bale's cloud file storage backend (Nasim).

### UserGetNasimFileUrls

```go
func (b *BaleCore) UserGetNasimFileUrls(fileIDs []map[string]interface{}) (map[string]interface{}, error)
```

Gets download URLs for multiple Nasim files at once.

### UserGetNasimFileUploadResume

```go
func (b *BaleCore) UserGetNasimFileUploadResume(fileID int64) (map[string]interface{}, error)
```

Gets resume information for a partially uploaded file.

### UserFileUploadCancel

```go
func (b *BaleCore) UserFileUploadCancel(fileID int64) (map[string]interface{}, error)
```

Cancels an in-progress file upload.

### UserGetNasimFilePublicUrl

```go
func (b *BaleCore) UserGetNasimFilePublicUrl(fileID int64, accessHash int64) (map[string]interface{}, error)
```

Gets a public URL for a Nasim file (accessible without auth).

---

## Organization

### UserGetOrganizationInfo

```go
func (b *BaleCore) UserGetOrganizationInfo() (map[string]interface{}, error)
```

Gets the user's organization info (Bale corporate/enterprise feature).

---

## AI & LLM

### UserGetLLMAuthToken

```go
func (b *BaleCore) UserGetLLMAuthToken() (map[string]interface{}, error)
```

Gets an authentication token for Bale's LLM/AI services.

### GetTranscript

```go
func (b *BaleCore) GetTranscript(chatID string, rid int64, date int64) (map[string]interface{}, error)
```

Gets an AI-generated transcript of a voice message.

### UserAISendEvent

```go
func (b *BaleCore) UserAISendEvent(eventData map[string]interface{}) (map[string]interface{}, error)
```

Sends an event to Bale's AI service (Turing).

### UserAIGetTranscript

```go
func (b *BaleCore) UserAIGetTranscript(chatID string, msgID string) (map[string]interface{}, error)
```

Gets an AI transcript via the Turing service.

---

## Miscellaneous User Methods

### GetInAppUpdate

```go
func (b *BaleCore) GetInAppUpdate() (map[string]interface{}, error)
```

Checks for in-app updates.

### FanoosSend

```go
func (b *BaleCore) FanoosSend(eventName string, eventData map[string]string) (map[string]interface{}, error)
```

Sends an analytics event to Bale's Fanoos analytics service.

### UserSubscribeToUpdates

```go
func (b *BaleCore) UserSubscribeToUpdates() (map[string]interface{}, error)
```

Subscribes to real-time updates via the WebSocket.

### UserGetDifference

```go
func (b *BaleCore) UserGetDifference(seq int64) (map[string]interface{}, error)
```

Gets updates since a specific sequence number (for catching up after disconnect).

---

## Extended Message Types

These methods send specialized Bale-specific message formats in user mode.

### UserSendScheduledMessage

```go
func (b *BaleCore) UserSendScheduledMessage(chatID string, date int64, msg map[string]interface{}) (map[string]interface{}, error)
```

Sends a scheduled message (user mode). `date` is the Unix timestamp for delivery.

### UserSendProtectedMessage

```go
func (b *BaleCore) UserSendProtectedMessage(chatID string, msg map[string]interface{}) (map[string]interface{}, error)
```

Sends a protected (non-forwardable) message in user mode.

### UserSendLongTextMessage

```go
func (b *BaleCore) UserSendLongTextMessage(chatID string, text string) (map[string]interface{}, error)
```

Sends a long-form text message in user mode.

### UserSendBankMessage

```go
func (b *BaleCore) UserSendBankMessage(chatID string, bankMsg map[string]interface{}) (map[string]interface{}, error)
```

Sends a bank/payment message in user mode.

### UserSendJsonMessage

```go
func (b *BaleCore) UserSendJsonMessage(chatID string, jsonData string) (map[string]interface{}, error)
```

Sends a raw JSON message in user mode.

### UserSendOrderMessage

```go
func (b *BaleCore) UserSendOrderMessage(chatID string, order map[string]interface{}) (map[string]interface{}, error)
```

Sends an order/invoice message in user mode.

### UserSendAnimatedSticker

```go
func (b *BaleCore) UserSendAnimatedSticker(chatID string, stickerData map[string]interface{}) (map[string]interface{}, error)
```

Sends an animated sticker in user mode.

### UserSendLiveMessage

```go
func (b *BaleCore) UserSendLiveMessage(chatID string, liveData map[string]interface{}) (map[string]interface{}, error)
```

Sends a live/streaming message in user mode.

---

## User API -- Pins

### UserPinMessage

```go
func (b *BaleCore) UserPinMessage(chatID string, msgRID int64, date int64, mid int64) (map[string]interface{}, error)
```

Pins a message by RID and date.

### UserUnPinMessages

```go
func (b *BaleCore) UserUnPinMessages(chatID string, msgs []map[string]interface{}, all bool) (map[string]interface{}, error)
```

Unpins messages. Set `all=true` to unpin all, or provide specific messages.

### UserLoadPinnedMessages

```go
func (b *BaleCore) UserLoadPinnedMessages(chatID string) (map[string]interface{}, error)
```

Loads all pinned messages in a chat.

### UserGetPins

```go
func (b *BaleCore) UserGetPins(groupID int64, page int, limit int) (map[string]interface{}, error)
```

Gets pinned messages in a group with pagination.

### UserRemovePin

```go
func (b *BaleCore) UserRemovePin(groupID int64, msgRID int64, date int64) (map[string]interface{}, error)
```

Removes a specific pin.

### UserRemoveAllPins

```go
func (b *BaleCore) UserRemoveAllPins(groupID int64) (map[string]interface{}, error)
```

Removes all pins from a group.

---

## Event Handlers

### OnUpdate

```go
func (b *BaleCore) OnUpdate(handler func(Update))
```

Registers a handler for all update types. Multiple handlers can be registered. In bot mode, triggers from HTTP long-polling. In user mode, triggers from WebSocket updates.

**Update types received:**
- `UpdateNewMessage` — new message (field 55 in composed update)
- `UpdateEditMessage` — message edited (field 162)
- `UpdateDeleteMessage` — message deleted (field 46)
- `UpdateConnectivity` — connection state changes (`"connected"`, `"disconnected"`, `"reconnecting"`)

```go
bale.OnUpdate(func(u cores.Update) {
    switch u.Type {
    case cores.UpdateNewMessage:
        fmt.Printf("New: %s\n", u.Message.Text)
    case cores.UpdateEditMessage:
        fmt.Printf("Edit: %s\n", u.Message.Text)
    case cores.UpdateConnectivity:
        fmt.Printf("Connection: %s\n", u.ConnState)
    }
})
```

---

## Unsupported Core Methods

These `Core` interface methods are not applicable to Bale and return `ErrNotSupported`:

- `AcceptCall` — requires push notification infrastructure for incoming call detection
- `CreatePoll` (bot mode) — polls only partially supported in bot API

## Dependencies

- Standard library: `net/http`, `crypto/tls`, `encoding/json`, `encoding/binary`
- `nhooyr.io/websocket` — WebSocket client for user mode
- `github.com/livekit/server-sdk-go/v2` — LiveKit client for voice calls
- No CGo required

## Notes

- **Chat ID format (user mode):** `"peerID|peerType"` where peerType: 1=private, 2=group, 3=channel, 4=bot, 5=supergroup
- **Message ID format (user mode):** `"rid:dateMs"` — both values needed for edit/delete/pin operations
- **Timestamps:** All Bale user API timestamps are in **milliseconds** (not seconds)
- **DNS fallback:** If `tapi.bale.ai` or `next-ws.bale.ai` DNS is blocked (common outside Iran), the client falls back to IP `2.189.68.126`
- **Auto-reconnect:** WebSocket disconnects trigger exponential backoff reconnection (3s to 60s, up to 10 retries)
- **Calls (LiveKit):** Voice calls connect to `meet-em.ble.ir` via LiveKit SDK. Geo-restricted to Iran. Audio publishes a silent Opus track, then unmutes on connection
