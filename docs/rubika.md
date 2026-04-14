# Rubika Core — API Reference

Pure Go client for [Rubika](https://rubika.ir), an Iranian messaging platform. Implements the proprietary WebSocket protocol with RSA/AES encryption for user mode, and the HTTP bot API for bot mode. No CGo, no external dependencies.

**242 exported methods** across messaging, groups, channels, voice chats, contacts, stickers, folders, bot API, file transfers, and account management.

## Table of Contents

- [Setup](#setup)
- [Types](#types)
- [Connection & Authentication](#connection--authentication)
- [Core Interface — Messaging](#core-interface--messaging)
- [Core Interface — Dialogs & Chat Info](#core-interface--dialogs--chat-info)
- [Core Interface — Groups & Channels](#core-interface--groups--channels)
- [Core Interface — Members](#core-interface--members)
- [Core Interface — Contacts & Blocking](#core-interface--contacts--blocking)
- [Core Interface — Search](#core-interface--search)
- [Core Interface — Profiles](#core-interface--profiles)
- [Core Interface — Files](#core-interface--files)
- [Core Interface — Calls](#core-interface--calls)
- [Core Interface — Sessions](#core-interface--sessions)
- [Core Interface — Polls & Stickers](#core-interface--polls--stickers)
- [Core Interface — Folders](#core-interface--folders)
- [Typed Media Senders](#typed-media-senders)
- [Group Management](#group-management)
- [Channel Management](#channel-management)
- [User & Account](#user--account)
- [Voice Chats](#voice-chats)
- [Voice / Audio](#voice--audio)
- [Messages Extended](#messages-extended)
- [Stickers & GIFs](#stickers--gifs)
- [Misc & Admin](#misc--admin)
- [Bot API](#bot-api)
- [WebSocket Events](#websocket-events)
- [Unsupported Core Methods](#unsupported-core-methods)

## Setup

```go
import "uniclient/cores"

rub := cores.NewRubikaCore("./sessions/rubika.json")
```

**Capabilities:** `TEXT`, `CHANNELS`, `GROUPS`, `MEDIA`, `REACTIONS`, `CONTACTS`, `STICKERS`, `CALLS`, `SEARCH`, `FOLDERS`, `TYPING`

### Two Authentication Modes

**Bot mode** uses the Rubika HTTP bot API with a token. Suitable for automated bots.

**User mode** uses a WebSocket connection with RSA key exchange and AES-encrypted payloads. Supports the full protocol surface including voice chats, stickers, account management, and real-time events.

### Network Resilience

Rubika core includes fallback DC (data center) endpoint addresses for operation outside Iran where primary domains may be blocked. The core automatically cycles through available endpoints on connection failure. This includes both direct IP addresses and alternative subdomains.

---

## Types

### RubikaGroupInfo

```go
type RubikaGroupInfo struct {
    GroupGUID                string `json:"group_guid"`
    GroupTitle               string `json:"group_title"`
    CountMembers             int    `json:"count_members"`
    Description              string `json:"description"`
    SlowMode                 int    `json:"slow_mode"`
    ChatHistoryForNewMembers string `json:"chat_history_for_new_members"`
    EventMessages            bool   `json:"event_messages"`
    GroupType                string `json:"group_type"`
    Username                 string `json:"username"`
    AvatarThumbnail          string `json:"avatar_thumbnail"`
    GroupVoiceChatID         string `json:"group_voice_chat_id"`
}
```

### RubikaChannelInfo

```go
type RubikaChannelInfo struct {
    ChannelGUID        string `json:"channel_guid"`
    ChannelTitle       string `json:"channel_title"`
    CountMembers       int    `json:"count_members"`
    Description        string `json:"description"`
    Username           string `json:"username"`
    ChannelType        string `json:"channel_type"`
    AvatarThumbnail    string `json:"avatar_thumbnail"`
    IsVerified         bool   `json:"is_verified"`
    SignMessages       bool   `json:"sign_messages"`
    ChannelVoiceChatID string `json:"channel_voice_chat_id"`
}
```

### RubikaUserInfo

```go
type RubikaUserInfo struct {
    UserGUID        string `json:"user_guid"`
    FirstName       string `json:"first_name"`
    LastName        string `json:"last_name"`
    Username        string `json:"username"`
    Phone           string `json:"phone"`
    Bio             string `json:"bio"`
    AvatarThumbnail string `json:"avatar_thumbnail"`
    IsVerified      bool   `json:"is_verified"`
    IsDeleted       bool   `json:"is_deleted"`
    LastOnline      int64  `json:"last_online"`
    OnlineStatus    string `json:"online_time_status"`
}
```

### RubikaMember

```go
type RubikaMember struct {
    MemberGUID string `json:"member_guid"`
    FirstName  string `json:"first_name"`
    LastName   string `json:"last_name"`
    Username   string `json:"username"`
}
```

### RubikaMemberList

Paginated list of members. Use `HasContinue` and `NextStartID` for cursor-based pagination.

```go
type RubikaMemberList struct {
    Members     []RubikaMember `json:"in_chat_members"`
    HasContinue bool           `json:"has_continue"`
    NextStartID string         `json:"next_start_id"`
}
```

### RubikaAccessEntry

```go
type RubikaAccessEntry struct {
    Access string `json:"access"`
}
```

### RubikaAvatar

```go
type RubikaAvatar struct {
    AvatarID    string `json:"avatar_id"`
    MainFileID  string `json:"main_file_id"`
    ThumbFileID string `json:"thumb_file_id"`
}
```

### RubikaAvatarList

```go
type RubikaAvatarList struct {
    Avatars []RubikaAvatar `json:"avatars"`
}
```

### RubikaStickerSet

```go
type RubikaStickerSet struct {
    StickerSetID string `json:"sticker_set_id"`
    Title        string `json:"title"`
    Count        int    `json:"count"`
}
```

### RubikaPollStatus

```go
type RubikaPollStatus struct {
    State          string         `json:"state"`
    SelectionCount map[string]int `json:"selection_count"`
    TotalCount     int            `json:"total_count"`
}
```

### RubikaPollVoters

```go
type RubikaPollVoters struct {
    Voters      []RubikaMember `json:"voters"`
    HasContinue bool           `json:"has_continue"`
    NextStartID string         `json:"next_start_id"`
}
```

### RubikaReactionInfo

```go
type RubikaReactionInfo struct {
    Reactions []struct {
        Emoji string `json:"emoji"`
        Count int    `json:"count"`
    } `json:"reactions"`
}
```

### RubikaPrivacySettings

```go
type RubikaPrivacySettings struct {
    Settings map[string]string `json:"settings"`
}
```

### RubikaTwoStepInfo

```go
type RubikaTwoStepInfo struct {
    HasPassword  bool   `json:"has_password"`
    PasswordHint string `json:"password_hint"`
}
```

### RubikaFolderInfo

```go
type RubikaFolderInfo struct {
    FolderID           string   `json:"folder_id"`
    Name               string   `json:"name"`
    IncludeChatTypes   []string `json:"include_chat_types"`
    IncludeObjectGUIDs []string `json:"include_object_guids"`
    ExcludeTypes       []string `json:"exclude_chat_types"`
}
```

### RubikaSessionInfo

```go
type RubikaSessionInfo struct {
    SessionKey  string `json:"session_key"`
    DeviceModel string `json:"device_model"`
    Platform    string `json:"platform"`
    AppVersion  string `json:"app_version"`
    IP          string `json:"ip"`
    Country     string `json:"country"`
    IsCurrent   bool   `json:"is_current"`
}
```

### RubikaVoiceChatInfo

```go
type RubikaVoiceChatInfo struct {
    VoiceChatID string `json:"voice_chat_id"`
    SDPAnswer   string `json:"sdp_answer_data"`
}
```

### RubikaUploadInfo

```go
type RubikaUploadInfo struct {
    ID             string `json:"id"`
    UploadURL      string `json:"upload_url"`
    AccessHashSend string `json:"access_hash_send"`
    DCID           int    `json:"dc_id"`
}
```

### RubikaBotInfo

```go
type RubikaBotInfo struct {
    UserGUID  string `json:"user_guid"`
    FirstName string `json:"first_name"`
    LastName  string `json:"last_name"`
    Username  string `json:"username"`
    IsBot     bool   `json:"is_bot"`
}
```

### RubikaBotChatInfo

```go
type RubikaBotChatInfo struct {
    ChatGUID     string `json:"chat_guid"`
    Title        string `json:"title"`
    ChatType     string `json:"chat_type"`
    CountMembers int    `json:"count_members"`
}
```

### RubikaBotJoinStatus

```go
type RubikaBotJoinStatus struct {
    IsMember bool `json:"is_member"`
}
```

### RubikaLinkInfo

```go
type RubikaLinkInfo struct {
    JoinLink string `json:"join_link"`
}
```

### RubikaGroupEdit

Editable fields for group info updates. Omitted fields are not changed.

```go
type RubikaGroupEdit struct {
    Title       string `json:"title,omitempty"`
    Description string `json:"description,omitempty"`
    SlowMode    *int   `json:"slow_mode,omitempty"`
    ChatHistory string `json:"chat_history_for_new_members,omitempty"`
}
```

### RubikaChannelEdit

Editable fields for channel info updates.

```go
type RubikaChannelEdit struct {
    Title        string `json:"title,omitempty"`
    Description  string `json:"description,omitempty"`
    SignMessages *bool  `json:"sign_messages,omitempty"`
}
```

### RubikaKeypadRow

```go
type RubikaKeypadRow struct {
    Buttons []RubikaKeypadButton `json:"buttons"`
}
```

### RubikaKeypadButton

```go
type RubikaKeypadButton struct {
    ID          string `json:"id"`
    Type        string `json:"type"`         // "Simple", "TextInline", "RequestPhone", etc.
    ButtonText  string `json:"button_text"`
    ButtonURL   string `json:"button_url,omitempty"`
    ButtonQuery string `json:"button_query,omitempty"`
}
```

### RubikaBotSendOpts

Optional parameters for bot send methods.

```go
type RubikaBotSendOpts struct {
    ReplyToMessageID string            `json:"reply_to_message_id,omitempty"`
    InlineKeypad     []RubikaKeypadRow `json:"inline_keypad,omitempty"`
}
```

### RubikaFileInline

File metadata for upload/avatar operations.

```go
type RubikaFileInline struct {
    FileID        string `json:"file_id"`
    FileName      string `json:"file_name"`
    Mime          string `json:"mime"`
    Size          int64  `json:"size"`
    DCID          int    `json:"dc_id"`
    AccessHashRec string `json:"access_hash_rec"`
    ThumbInline   string `json:"thumb_inline,omitempty"`
    Width         int    `json:"width,omitempty"`
    Height        int    `json:"height,omitempty"`
}
```

### RubikaMessageShareInfo

```go
type RubikaMessageShareInfo struct {
    Link string `json:"link"`
}
```

### RubikaContactImportResult

```go
type RubikaContactImportResult struct {
    Users []RubikaUserInfo `json:"users"`
}
```

---

## Connection & Authentication

### Name

```go
func (r *RubikaCore) Name() string
```

Returns `"rubika"`.

### Capabilities

```go
func (r *RubikaCore) Capabilities() []string
```

Returns `["TEXT", "CHANNELS", "GROUPS", "MEDIA", "REACTIONS", "CONTACTS", "STICKERS", "CALLS", "SEARCH", "FOLDERS", "TYPING"]`.

### Authenticate

```go
func (r *RubikaCore) Authenticate(cfg AuthConfig) error
```

Authenticates in either bot or user mode. Bot mode requires a token; user mode initiates phone-based OTP flow over WebSocket with RSA key exchange and AES encryption.

**AuthConfig fields:**
- `BotToken` — bot API token (bot mode)
- `Phone` — phone number with country code (user mode, e.g. `+98xxxxxxxxxx`)

```go
// Bot mode
err := rub.Authenticate(cores.AuthConfig{
    BotToken: "bot_token_here",
})

// User mode — triggers OTP flow
err := rub.Authenticate(cores.AuthConfig{
    Phone: "+98xxxxxxxxxx",
})
```

### SendCode

```go
func (r *RubikaCore) SendCode(phone string, passKey string) (string, error)
```

Sends an OTP verification code to the given phone number. Returns a `phoneCodeHash` needed for `SignIn`. The `passKey` is the two-step verification password if enabled (pass empty string if not).

```go
hash, err := rub.SendCode("+98xxxxxxxxxx", "")
```

### SignIn

```go
func (r *RubikaCore) SignIn(phone string, otp string, phoneCodeHash string) error
```

Completes authentication using the OTP received via SMS and the code hash from `SendCode`. On success, establishes the encrypted session and starts the WebSocket listener.

```go
err := rub.SignIn("+98xxxxxxxxxx", "12345", phoneCodeHash)
```

### Logout

```go
func (r *RubikaCore) Logout() error
```

Logs out of the current session. Clears session data.

### Close

```go
func (r *RubikaCore) Close() error
```

Full shutdown: closes WebSocket connection, stops goroutines, saves session state.

### OnUpdate

```go
func (r *RubikaCore) OnUpdate(handler func(Update))
```

Registers a callback for unified updates (incoming messages, chat changes, connectivity events). Updates arrive over the WebSocket connection in user mode.

```go
rub.OnUpdate(func(u cores.Update) {
    if u.Message != nil {
        fmt.Printf("[%s] %s: %s\n", u.ChatID, u.Message.SenderName, u.Message.Text)
    }
})
```

### StartWebSocket

```go
func (r *RubikaCore) StartWebSocket() error
```

Manually starts the WebSocket connection for receiving real-time events. Called automatically during user-mode authentication, but can be restarted if the connection drops.

### RawAPI

```go
func (r *RubikaCore) RawAPI(method string, input map[string]interface{}) (map[string]interface{}, error)
```

Sends a raw API request with the given method name and parameters. Handles AES encryption/decryption automatically. Useful for calling Rubika API methods not yet wrapped.

```go
result, err := rub.RawAPI("getChatsUpdates", map[string]interface{}{
    "state": 12345,
})
```

### GetGUID

```go
func (r *RubikaCore) GetGUID() string
```

Returns the authenticated user's GUID (unique identifier in Rubika's system).

---

## Core Interface — Messaging

These implement the unified `Core` interface shared across all platforms.

### SendMessage

```go
func (r *RubikaCore) SendMessage(chatID string, msg OutgoingMessage) (*Message, error)
```

Sends a text message to a chat. The `chatID` is a Rubika GUID (user, group, or channel).

```go
msg, err := rub.SendMessage("g0BGxx...", cores.OutgoingMessage{Text: "Hello!"})
```

### GetMessages

```go
func (r *RubikaCore) GetMessages(chatID string, opts PaginationOpts) ([]Message, error)
```

Retrieves messages from a chat with pagination support.

```go
msgs, err := rub.GetMessages("g0BGxx...", cores.PaginationOpts{Limit: 20})
```

### EditMessage

```go
func (r *RubikaCore) EditMessage(chatID string, msgID string, text string) (*Message, error)
```

Edits an existing message's text content.

### DeleteMessage

```go
func (r *RubikaCore) DeleteMessage(chatID string, msgID string) error
```

Deletes a message by its ID.

### ReplyToMessage

```go
func (r *RubikaCore) ReplyToMessage(chatID string, replyToMsgID string, msg OutgoingMessage) (*Message, error)
```

Sends a message as a reply to an existing message.

### ForwardMessage

```go
func (r *RubikaCore) ForwardMessage(fromChatID string, msgID string, toChatID string) (*Message, error)
```

Forwards a message from one chat to another.

### ReactToMessage

```go
func (r *RubikaCore) ReactToMessage(chatID string, msgID string, emoji string) error
```

Adds an emoji reaction to a message.

```go
err := rub.ReactToMessage("g0BGxx...", "msg123", "❤️")
```

### PinMessage

```go
func (r *RubikaCore) PinMessage(chatID string, msgID string) error
```

Pins a message in a chat.

### UnpinMessage

```go
func (r *RubikaCore) UnpinMessage(chatID string, msgID string) error
```

Unpins a message in a chat.

### MarkAsRead

```go
func (r *RubikaCore) MarkAsRead(chatID string, upToMsgID string) error
```

Marks all messages up to the given message ID as read.

### GetReadState

```go
func (r *RubikaCore) GetReadState(chatID string) (*ReadState, error)
```

Returns the read state for a chat.

### SendImageBase64

```go
func (r *RubikaCore) SendImageBase64(chatID string, b64 string, caption string) (*Message, error)
```

Sends a base64-encoded image as a message with an optional caption.

### SendTyping

```go
func (r *RubikaCore) SendTyping(chatID string) error
```

Sends a typing indicator to the chat. Wraps `SendChatActivity` with the typing activity type.

---

## Core Interface — Dialogs & Chat Info

### GetDialogs

```go
func (r *RubikaCore) GetDialogs(opts PaginationOpts) ([]Dialog, error)
```

Returns a paginated list of the user's conversations (users, groups, channels).

```go
dialogs, err := rub.GetDialogs(cores.PaginationOpts{Limit: 50})
```

### GetChatInfo

```go
func (r *RubikaCore) GetChatInfo(chatID string) (*Dialog, error)
```

Returns detailed information about a chat. Automatically detects chat type (user/group/channel) from the GUID prefix and calls the appropriate API.

### EditChatTitle

```go
func (r *RubikaCore) EditChatTitle(chatID string, title string) error
```

Edits the title of a group or channel.

### EditChatDescription

```go
func (r *RubikaCore) EditChatDescription(chatID string, description string) error
```

Edits the description of a group or channel.

### LeaveChat

```go
func (r *RubikaCore) LeaveChat(chatID string) error
```

Leaves a group or channel. Detects chat type from the GUID prefix.

### GetInviteLink

```go
func (r *RubikaCore) GetInviteLink(chatID string) (string, error)
```

Returns the invite link for a group or channel.

---

## Core Interface — Groups & Channels

### CreateGroup

```go
func (r *RubikaCore) CreateGroup(name string, members []string) (*Dialog, error)
```

Creates a new group with the given name and initial member GUIDs.

```go
group, err := rub.CreateGroup("My Group", []string{"u0ABxx...", "u0CDxx..."})
```

### CreateChannel

```go
func (r *RubikaCore) CreateChannel(name string, description string) (*Dialog, error)
```

Creates a new channel with the given name and description.

### CreateTopic

```go
func (r *RubikaCore) CreateTopic(chatID string, name string) (*Dialog, error)
```

Not supported by Rubika. Returns `ErrNotSupported`.

---

## Core Interface — Members

### AddMembers

```go
func (r *RubikaCore) AddMembers(chatID string, userIDs []string) error
```

Adds members to a group or channel. Detects chat type from the GUID prefix.

### RemoveMember

```go
func (r *RubikaCore) RemoveMember(chatID string, userID string) error
```

Removes a member from a group or channel.

### BanMember

```go
func (r *RubikaCore) BanMember(chatID string, userID string) error
```

Bans a member from a group or channel.

### UnbanMember

```go
func (r *RubikaCore) UnbanMember(chatID string, userID string) error
```

Unbans a previously banned member.

### GetMembers

```go
func (r *RubikaCore) GetMembers(chatID string, opts PaginationOpts) ([]User, error)
```

Returns a paginated list of members in a group or channel.

### SetAdmin

```go
func (r *RubikaCore) SetAdmin(chatID string, userID string, admin bool) error
```

Promotes or demotes a member to/from admin in a group. When `admin` is true, grants default admin access; when false, removes admin role.

---

## Core Interface — Contacts & Blocking

### GetContacts

```go
func (r *RubikaCore) GetContacts() ([]User, error)
```

Returns the user's contact list.

### AddContact

```go
func (r *RubikaCore) AddContact(phone string, firstName string, lastName string) error
```

Adds a contact by phone number.

### DeleteContact

```go
func (r *RubikaCore) DeleteContact(userGUID string) error
```

Deletes a contact by their GUID.

### SetBlockUser

```go
func (r *RubikaCore) SetBlockUser(userGUID string, block bool) error
```

Blocks or unblocks a user. Set `block=true` to block, `block=false` to unblock. This is the underlying method used by `BlockUser` and `UnblockUser`.

### BlockUser

```go
func (r *RubikaCore) BlockUser(userID string) error
```

Blocks a user. Wraps `SetBlockUser` with `block=true`.

### UnblockUser

```go
func (r *RubikaCore) UnblockUser(userID string) error
```

Unblocks a user. Wraps `SetBlockUser` with `block=false`.

### GetBlockedUsers

```go
func (r *RubikaCore) GetBlockedUsers() ([]User, error)
```

Returns the list of blocked users.

---

## Core Interface — Search

### SearchMessages

```go
func (r *RubikaCore) SearchMessages(chatID string, query string, opts PaginationOpts) ([]Message, error)
```

Searches for messages within a specific chat.

```go
results, err := rub.SearchMessages("g0BGxx...", "hello", cores.PaginationOpts{Limit: 20})
```

### SearchGlobal

```go
func (r *RubikaCore) SearchGlobal(query string, opts PaginationOpts) ([]Dialog, error)
```

Searches globally across all chats for matching dialogs.

---

## Core Interface — Profiles

### GetProfile

```go
func (r *RubikaCore) GetProfile(userID string) (*User, error)
```

Returns the profile of a user by their GUID. Maps Rubika user info to the unified `User` type.

---

## Core Interface — Files

### UploadFile

```go
func (r *RubikaCore) UploadFile(chatID string, file FileUpload, progress func(sent, total int64)) (*Message, error)
```

Uploads a file and sends it as a message. Handles the full upload flow: requests an upload slot, uploads the file data to the Rubika file server, then sends the file reference as a message. Supports progress callbacks.

```go
msg, err := rub.UploadFile("g0BGxx...", cores.FileUpload{
    Path: "/path/to/document.pdf",
}, func(sent, total int64) {
    fmt.Printf("Upload: %d/%d bytes\n", sent, total)
})
```

### DownloadFile

```go
func (r *RubikaCore) DownloadFile(fileRef FileRef, dest string, progress func(recv, total int64)) error
```

Downloads a file from Rubika's file server to a local path. Supports progress callbacks.

---

## Core Interface — Calls

### StartCall

```go
func (r *RubikaCore) StartCall(chatID string, video bool) (*CallSession, error)
```

Starts a private call with a user. The `video` parameter is accepted but Rubika calls are audio-only via Janus WebRTC gateway.

### JoinGroupCall

```go
func (r *RubikaCore) JoinGroupCall(chatID string) (*CallSession, error)
```

Joins an active group voice chat. Establishes a WebRTC connection through Rubika's Janus gateway.

### EndCall

```go
func (r *RubikaCore) EndCall(callID string) error
```

Ends an active call or leaves a voice chat.

### SetCallMuted

```go
func (r *RubikaCore) SetCallMuted(callID string, muted bool) error
```

Mutes or unmutes the microphone in an active call.

---

## Core Interface — Sessions

### GetSessions

```go
func (r *RubikaCore) GetSessions() ([]Session, error)
```

Returns a list of all active sessions for the account, mapped to the unified `Session` type.

### TerminateSession

```go
func (r *RubikaCore) TerminateSession(sessionKey string) error
```

Terminates a specific session by its session key.

---

## Core Interface — Polls & Stickers

### CreatePoll

```go
func (r *RubikaCore) CreatePoll(chatID string, question string, options []string) (*Message, error)
```

Creates and sends a poll to a chat.

```go
msg, err := rub.CreatePoll("g0BGxx...", "Favorite color?", []string{"Red", "Blue", "Green"})
```

### VotePoll

```go
func (r *RubikaCore) VotePoll(chatID string, msgID string, optionIndex int) error
```

Votes on a poll option by index.

### SendSticker

```go
func (r *RubikaCore) SendSticker(chatID string, stickerID string) (*Message, error)
```

Sends a sticker to a chat by sticker ID.

### GetPollStatus

```go
func (r *RubikaCore) GetPollStatus(pollID string) (map[string]interface{}, error)
```

Returns the current status of a poll (vote counts, state).

### GetPollOptionVoters

```go
func (r *RubikaCore) GetPollOptionVoters(pollID string, selectionIndex int, startID string) (map[string]interface{}, error)
```

Returns the list of users who voted for a specific poll option. Supports pagination via `startID`.

---

## Core Interface — Folders

### GetFolders

```go
func (r *RubikaCore) GetFolders() ([]Folder, error)
```

Returns the user's chat folders, mapped to the unified `Folder` type.

### CreateFolder

```go
func (r *RubikaCore) CreateFolder(name string, chatIDs []string) (*Folder, error)
```

Creates a new folder with the given name and included chat GUIDs.

---

## Typed Media Senders

Convenience methods for sending specific media types. Each handles upload and message sending in one call.

### SendPhoto

```go
func (r *RubikaCore) SendPhoto(chatID string, data []byte, fileName string, caption string) (map[string]interface{}, error)
```

Uploads and sends a photo with optional caption.

```go
photo, _ := os.ReadFile("photo.jpg")
result, err := rub.SendPhoto("g0BGxx...", photo, "photo.jpg", "Check this out!")
```

### SendVideo

```go
func (r *RubikaCore) SendVideo(chatID string, data []byte, fileName string, caption string) (map[string]interface{}, error)
```

Uploads and sends a video with optional caption.

### SendGif

```go
func (r *RubikaCore) SendGif(chatID string, data []byte, fileName string, caption string) (map[string]interface{}, error)
```

Uploads and sends a GIF with optional caption.

### SendMusic

```go
func (r *RubikaCore) SendMusic(chatID string, data []byte, fileName string, caption string) (map[string]interface{}, error)
```

Uploads and sends a music file with optional caption.

### SendVoice

```go
func (r *RubikaCore) SendVoice(chatID string, data []byte, fileName string) (map[string]interface{}, error)
```

Uploads and sends a voice message. No caption parameter (voice messages don't support captions).

### SendDocument

```go
func (r *RubikaCore) SendDocument(chatID string, data []byte, fileName string, caption string) (map[string]interface{}, error)
```

Uploads and sends a document/file with optional caption.

### SendVideoMessage

```go
func (r *RubikaCore) SendVideoMessage(chatID string, data []byte, fileName string) (map[string]interface{}, error)
```

Uploads and sends a video message (round video). No caption support.

---

## Group Management

### GetGroupInfo

```go
func (r *RubikaCore) GetGroupInfo(groupGUID string) (RubikaGroupInfo, error)
```

Returns detailed information about a group.

```go
info, err := rub.GetGroupInfo("g0BGxx...")
fmt.Printf("Group: %s (%d members)\n", info.GroupTitle, info.CountMembers)
```

### GetGroupAllMembers

```go
func (r *RubikaCore) GetGroupAllMembers(groupGUID string) (RubikaMemberList, error)
```

Returns all members of a group with pagination info.

### SetGroupAdmin

```go
func (r *RubikaCore) SetGroupAdmin(groupGUID string, memberGUID string, accessList []string) error
```

Promotes a member to admin with specific access permissions.

```go
err := rub.SetGroupAdmin("g0BGxx...", "u0ABxx...", []string{
    "PinMessages", "DeleteGlobalAllMessages", "BanMember",
})
```

### RemoveGroupAdmin

```go
func (r *RubikaCore) RemoveGroupAdmin(groupGUID string, memberGUID string) error
```

Removes admin privileges from a group member.

### BanGroupMember

```go
func (r *RubikaCore) BanGroupMember(groupGUID string, memberGUID string, ban bool) error
```

Bans or unbans a member from a group. Set `ban=true` to ban, `ban=false` to unban.

### JoinGroup

```go
func (r *RubikaCore) JoinGroup(groupGUID string) error
```

Joins a group by its GUID.

### LeaveGroup

```go
func (r *RubikaCore) LeaveGroup(groupGUID string) error
```

Leaves a group.

### AddGroupMembers

```go
func (r *RubikaCore) AddGroupMembers(groupGUID string, memberGUIDs []string) error
```

Adds multiple members to a group by their GUIDs.

### EditGroupInfo

```go
func (r *RubikaCore) EditGroupInfo(groupGUID string, updates map[string]interface{}) error
```

Edits group properties. The `updates` map can include `"title"`, `"description"`, and other editable fields.

```go
err := rub.EditGroupInfo("g0BGxx...", map[string]interface{}{
    "title":       "New Group Name",
    "description": "Updated description",
})
```

### GetGroupLink

```go
func (r *RubikaCore) GetGroupLink(groupGUID string) (RubikaLinkInfo, error)
```

Returns the current invite link for a group.

### SetGroupLink

```go
func (r *RubikaCore) SetGroupLink(groupGUID string) (RubikaLinkInfo, error)
```

Regenerates and returns a new invite link for a group.

### GetNewGroupLink

```go
func (r *RubikaCore) GetNewGroupLink(groupGUID string) (RubikaLinkInfo, error)
```

Generates a new invite link for a group, revoking the old one.

### GetGroupAdminMembers

```go
func (r *RubikaCore) GetGroupAdminMembers(groupGUID string, startID string) (RubikaMemberList, error)
```

Returns a paginated list of admin members. Pass empty `startID` for the first page; use `NextStartID` from the result for subsequent pages.

### GetGroupAdminAccessList

```go
func (r *RubikaCore) GetGroupAdminAccessList(groupGUID string, memberGUID string) ([]string, error)
```

Returns the list of admin permissions for a specific member.

```go
perms, err := rub.GetGroupAdminAccessList("g0BGxx...", "u0ABxx...")
// perms: ["PinMessages", "DeleteGlobalAllMessages", "BanMember", ...]
```

### GetBannedGroupMembers

```go
func (r *RubikaCore) GetBannedGroupMembers(groupGUID string, startID string) (RubikaMemberList, error)
```

Returns a paginated list of banned members in a group.

### GetGroupDefaultAccess

```go
func (r *RubikaCore) GetGroupDefaultAccess(groupGUID string) ([]string, error)
```

Returns the default access permissions for regular (non-admin) group members.

### SetGroupDefaultAccess

```go
func (r *RubikaCore) SetGroupDefaultAccess(groupGUID string, accessList []string) error
```

Sets the default access permissions for regular group members.

```go
err := rub.SetGroupDefaultAccess("g0BGxx...", []string{
    "SendMessages", "AddMember",
})
```

### GetGroupMentionList

```go
func (r *RubikaCore) GetGroupMentionList(groupGUID string, searchText string) (map[string]interface{}, error)
```

Returns mentionable members in a group matching the search text. Used for @-mention autocomplete.

### GetGroupOnlineCount

```go
func (r *RubikaCore) GetGroupOnlineCount(groupGUID string) (int, error)
```

Returns the number of currently online members in a group.

### GetGroupMemberCount

```go
func (r *RubikaCore) GetGroupMemberCount(groupGUID string) (int, error)
```

Returns the total number of members in a group.

### RemoveGroup

```go
func (r *RubikaCore) RemoveGroup(groupGUID string) error
```

Permanently deletes a group. Requires owner privileges.

### DeleteNoAccessGroupChat

```go
func (r *RubikaCore) DeleteNoAccessGroupChat(groupGUID string) error
```

Deletes a group chat from the user's chat list when they no longer have access (e.g., after being removed).

### GroupPreviewByJoinLink

```go
func (r *RubikaCore) GroupPreviewByJoinLink(hashLink string) (map[string]interface{}, error)
```

Returns a preview of a group from its invite link hash without joining.

### EditGroupHistoryForNewMembers

```go
func (r *RubikaCore) EditGroupHistoryForNewMembers(groupGUID string, visible bool) error
```

Controls whether new members can see chat history from before they joined. Set `visible=true` to show history, `visible=false` to hide it.

### SetGroupEventMessages

```go
func (r *RubikaCore) SetGroupEventMessages(groupGUID string, enabled bool) error
```

Enables or disables event messages in a group (e.g., "X joined the group").

### SetGroupSlowModeTime

```go
func (r *RubikaCore) SetGroupSlowModeTime(groupGUID string, seconds int) error
```

Sets the slow mode interval in seconds. Set to 0 to disable slow mode.

### SetGroupReactions

```go
func (r *RubikaCore) SetGroupReactions(groupGUID string, reactionType string, selectedReactions []string) error
```

Configures which reactions are available in a group. The `reactionType` can be `"all"`, `"selected"`, or `"none"`. When using `"selected"`, provide the emoji list in `selectedReactions`.

```go
err := rub.SetGroupReactions("g0BGxx...", "selected", []string{"❤️", "👍", "😂"})
```

---

## Channel Management

### GetChannelInfo

```go
func (r *RubikaCore) GetChannelInfo(channelGUID string) (RubikaChannelInfo, error)
```

Returns detailed information about a channel.

```go
info, err := rub.GetChannelInfo("c0ABxx...")
fmt.Printf("Channel: %s (%d members)\n", info.ChannelTitle, info.CountMembers)
```

### GetChannelAllMembers

```go
func (r *RubikaCore) GetChannelAllMembers(channelGUID string) (RubikaMemberList, error)
```

Returns all members of a channel with pagination info.

### AddChannelMembers

```go
func (r *RubikaCore) AddChannelMembers(channelGUID string, memberGUIDs []string) error
```

Adds multiple members to a channel.

### BanChannelMember

```go
func (r *RubikaCore) BanChannelMember(channelGUID string, memberGUID string, ban bool) error
```

Bans or unbans a member from a channel.

### EditChannelInfo

```go
func (r *RubikaCore) EditChannelInfo(channelGUID string, updates map[string]interface{}) error
```

Edits channel properties. The `updates` map can include `"title"`, `"description"`, `"sign_messages"`.

### GetChannelLink

```go
func (r *RubikaCore) GetChannelLink(channelGUID string) (RubikaLinkInfo, error)
```

Returns the current invite link for a channel.

### SetChannelLink

```go
func (r *RubikaCore) SetChannelLink(channelGUID string) (RubikaLinkInfo, error)
```

Regenerates and returns a new invite link for a channel.

### GetChannelAdminMembers

```go
func (r *RubikaCore) GetChannelAdminMembers(channelGUID string, startID string) (RubikaMemberList, error)
```

Returns a paginated list of admin members in a channel.

### GetChannelAdminAccessList

```go
func (r *RubikaCore) GetChannelAdminAccessList(channelGUID string, memberGUID string) ([]string, error)
```

Returns the list of admin permissions for a specific channel member.

### GetBannedChannelMembers

```go
func (r *RubikaCore) GetBannedChannelMembers(channelGUID string, startID string) (RubikaMemberList, error)
```

Returns a paginated list of banned members in a channel.

### RemoveChannel

```go
func (r *RubikaCore) RemoveChannel(channelGUID string) error
```

Permanently deletes a channel. Requires owner privileges.

### ChannelPreviewByJoinLink

```go
func (r *RubikaCore) ChannelPreviewByJoinLink(hashLink string) (map[string]interface{}, error)
```

Returns a preview of a channel from its invite link hash without joining.

### JoinChannelAction

```go
func (r *RubikaCore) JoinChannelAction(channelGUID string, action string) error
```

Performs a join/leave action on a channel. The `action` parameter is `"Join"` or `"Leave"`.

### JoinChannelByLink

```go
func (r *RubikaCore) JoinChannelByLink(hashLink string) error
```

Joins a channel using an invite link hash.

### SeenChannelMessages

```go
func (r *RubikaCore) SeenChannelMessages(channelGUID string, minID string, maxID string) error
```

Marks a range of channel messages as seen, from `minID` to `maxID`.

### UpdateChannelUsername

```go
func (r *RubikaCore) UpdateChannelUsername(channelGUID string, username string) error
```

Sets or updates the public username for a channel.

### CheckChannelUsername

```go
func (r *RubikaCore) CheckChannelUsername(username string) (map[string]interface{}, error)
```

Checks if a channel username is available.

---

## User & Account

### GetUserInfo

```go
func (r *RubikaCore) GetUserInfo(userGUID string) (RubikaUserInfo, error)
```

Returns detailed user information by GUID.

```go
info, err := rub.GetUserInfo("u0ABxx...")
fmt.Printf("%s %s (@%s)\n", info.FirstName, info.LastName, info.Username)
```

### GetObjectByUsername

```go
func (r *RubikaCore) GetObjectByUsername(username string) (map[string]interface{}, error)
```

Resolves a username to an object (user, group, or channel). Returns the raw API response.

### UpdateProfile

```go
func (r *RubikaCore) UpdateProfile(firstName string, lastName string, bio string) error
```

Updates the authenticated user's profile information.

### UpdateUsername

```go
func (r *RubikaCore) UpdateUsername(username string) error
```

Sets or updates the authenticated user's username.

### CheckUserUsername

```go
func (r *RubikaCore) CheckUserUsername(username string) (map[string]interface{}, error)
```

Checks if a username is available for a user account.

### GetPrivacySetting

```go
func (r *RubikaCore) GetPrivacySetting() (RubikaPrivacySettings, error)
```

Returns the user's current privacy settings (who can see online status, profile photo, etc.).

### SetPrivacySetting

```go
func (r *RubikaCore) SetPrivacySetting(settingType string, value string) error
```

Updates a specific privacy setting.

```go
err := rub.SetPrivacySetting("online_status", "nobody")
```

### GetTwoPasscodeStatus

```go
func (r *RubikaCore) GetTwoPasscodeStatus() (RubikaTwoStepInfo, error)
```

Returns the current two-step verification status for the account.

### SetupTwoStepVerification

```go
func (r *RubikaCore) SetupTwoStepVerification(password string, hint string, recoveryEmail string) error
```

Enables two-step verification with a password, hint, and recovery email.

### TurnOffTwoStep

```go
func (r *RubikaCore) TurnOffTwoStep(password string) error
```

Disables two-step verification using the current password.

### LoginTwoStepForgetPassword

```go
func (r *RubikaCore) LoginTwoStepForgetPassword(phoneNumber string, phoneCodeHash string) (map[string]interface{}, error)
```

Initiates the password recovery flow when the two-step verification password is forgotten.

### LoginDisableTwoStep

```go
func (r *RubikaCore) LoginDisableTwoStep(phoneNumber string, phoneCodeHash string) (map[string]interface{}, error)
```

Disables two-step verification during login via the recovery flow.

### RequestDeleteAccount

```go
func (r *RubikaCore) RequestDeleteAccount() (map[string]interface{}, error)
```

Initiates an account deletion request. Returns confirmation data.

### TerminateOtherSessions

```go
func (r *RubikaCore) TerminateOtherSessions() error
```

Terminates all other active sessions except the current one.

---

## Voice Chats

Rubika supports voice chats in groups and channels via a Janus WebRTC gateway.

### CreateGroupVoiceChat

```go
func (r *RubikaCore) CreateGroupVoiceChat(groupGUID string) (map[string]interface{}, error)
```

Creates a new voice chat in a group. Returns voice chat info including the `voice_chat_id`.

### CreateChannelVoiceChat

```go
func (r *RubikaCore) CreateChannelVoiceChat(channelGUID string) (map[string]interface{}, error)
```

Creates a new voice chat in a channel.

### JoinVoiceChat

```go
func (r *RubikaCore) JoinVoiceChat(chatID string, voiceChatID string, sdpOffer string) (map[string]interface{}, error)
```

Joins a voice chat with an SDP offer for WebRTC negotiation. Returns the SDP answer.

```go
result, err := rub.JoinVoiceChat("g0BGxx...", "vc123", sdpOfferString)
```

### LeaveGroupVoiceChat

```go
func (r *RubikaCore) LeaveGroupVoiceChat(chatGUID string, voiceChatID string) error
```

Leaves a group voice chat.

### LeaveChannelVoiceChat

```go
func (r *RubikaCore) LeaveChannelVoiceChat(channelGUID string, voiceChatID string) error
```

Leaves a channel voice chat.

### DiscardGroupVoiceChat

```go
func (r *RubikaCore) DiscardGroupVoiceChat(chatGUID string, voiceChatID string) error
```

Ends/discards a group voice chat. Requires admin privileges.

### DiscardChannelVoiceChat

```go
func (r *RubikaCore) DiscardChannelVoiceChat(channelGUID string, voiceChatID string) error
```

Ends/discards a channel voice chat. Requires admin privileges.

### SetGroupVoiceChatSetting

```go
func (r *RubikaCore) SetGroupVoiceChatSetting(groupGUID string, voiceChatID string, settings map[string]interface{}) error
```

Updates voice chat settings for a group (e.g., title, who can speak).

### SetChannelVoiceChatSetting

```go
func (r *RubikaCore) SetChannelVoiceChatSetting(channelGUID string, voiceChatID string, settings map[string]interface{}) error
```

Updates voice chat settings for a channel.

### GetGroupVoiceChatUpdates

```go
func (r *RubikaCore) GetGroupVoiceChatUpdates(chatGUID string, voiceChatID string, state int64) (map[string]interface{}, error)
```

Gets voice chat state updates since the given state number. Used for polling voice chat participant changes.

### GetGroupVoiceChatParticipants

```go
func (r *RubikaCore) GetGroupVoiceChatParticipants(chatGUID string, voiceChatID string) (map[string]interface{}, error)
```

Returns the list of current voice chat participants.

### LoadMoreParticipants

```go
func (r *RubikaCore) LoadMoreParticipants(chatID string, voiceChatID string, startID string) (map[string]interface{}, error)
```

Loads additional voice chat participants for pagination.

### SetVoiceChatState

```go
func (r *RubikaCore) SetVoiceChatState(chatID string, voiceChatID string, state string) error
```

Sets the voice chat state (e.g., muted/unmuted) for the current user.

### SendGroupVoiceChatActivity

```go
func (r *RubikaCore) SendGroupVoiceChatActivity(groupGUID string, voiceChatID string, activity string) error
```

Sends an activity indicator in a voice chat (e.g., speaking, hand raised).

---

## Voice / Audio

### SendAudioOpus

```go
func (r *RubikaCore) SendAudioOpus(opusFrame []byte)
```

Sends a raw Opus audio frame to the active call's RTP stream.

### OnAudioReceived

```go
func (r *RubikaCore) OnAudioReceived(cb func(opusFrame []byte))
```

Registers a callback to receive incoming Opus audio frames from the active call.

```go
rub.OnAudioReceived(func(frame []byte) {
    // Process incoming audio
    player.Write(frame)
})
```

### GetCallStats

```go
func (r *RubikaCore) GetCallStats() (sent, recv int64)
```

Returns the number of RTP packets sent and received in the current call.

---

## Messages Extended

### GetMessagesByID

```go
func (r *RubikaCore) GetMessagesByID(chatID string, messageIDs []string) (map[string]interface{}, error)
```

Retrieves specific messages by their IDs.

### GetMessagesInterval

```go
func (r *RubikaCore) GetMessagesInterval(chatID string, middleMsgID string) (map[string]interface{}, error)
```

Returns messages around a specific message ID (context window).

### GetMessagesUpdates

```go
func (r *RubikaCore) GetMessagesUpdates(chatID string, state int64) (map[string]interface{}, error)
```

Returns message updates for a chat since the given state number. Used for syncing.

### GetChatsUpdates

```go
func (r *RubikaCore) GetChatsUpdates(state int64) (map[string]interface{}, error)
```

Returns chat list updates since the given state number. Used for syncing the dialog list.

### GetMessageReactions

```go
func (r *RubikaCore) GetMessageReactions(chatID string, msgID string) (map[string]interface{}, error)
```

Returns all reactions on a message.

### RemoveReaction

```go
func (r *RubikaCore) RemoveReaction(chatID string, msgID string, reactionID int) error
```

Removes a specific reaction from a message by reaction ID.

### GetMessageShareURL

```go
func (r *RubikaCore) GetMessageShareURL(chatID string, msgID string) (map[string]interface{}, error)
```

Returns a shareable URL for a message.

### AutoDeleteMessage

```go
func (r *RubikaCore) AutoDeleteMessage(chatID string, msgID string, seconds float64) error
```

Schedules a message for automatic deletion after the specified number of seconds.

### TranscribeVoice

```go
func (r *RubikaCore) TranscribeVoice(chatID string, msgID string) (map[string]interface{}, error)
```

Initiates voice message transcription. Returns a transcription ID.

### GetTranscription

```go
func (r *RubikaCore) GetTranscription(transcriptionID string) (map[string]interface{}, error)
```

Retrieves the result of a voice transcription by its ID.

### SeenChats

```go
func (r *RubikaCore) SeenChats(seenList map[string]string) error
```

Marks multiple chats as seen in bulk. The map keys are chat GUIDs and values are the last seen message IDs.

```go
err := rub.SeenChats(map[string]string{
    "g0BGxx...": "msg123",
    "u0ABxx...": "msg456",
})
```

### DeleteChatHistory

```go
func (r *RubikaCore) DeleteChatHistory(chatID string, lastMessageID string) error
```

Deletes all chat history up to the given message ID.

### DeleteUserChat

```go
func (r *RubikaCore) DeleteUserChat(userGUID string, lastDeletedMsgID string) error
```

Deletes a private chat with a user up to the given message ID.

### SendContact

```go
func (r *RubikaCore) SendContact(chatGUID string, firstName string, lastName string, phone string) (map[string]interface{}, error)
```

Sends a contact card as a message.

### SendLocation

```go
func (r *RubikaCore) SendLocation(chatID string, lat float64, lon float64) (*Message, error)
```

Sends a location message with latitude and longitude coordinates.

```go
msg, err := rub.SendLocation("g0BGxx...", 35.6892, 51.3890) // Tehran
```

---

## Stickers & GIFs

### GetMyStickers

```go
func (r *RubikaCore) GetMyStickers() (map[string]interface{}, error)
```

Returns the user's installed stickers.

### GetMyStickerSets

```go
func (r *RubikaCore) GetMyStickerSets() (map[string]interface{}, error)
```

Returns the user's installed sticker sets.

### GetMyGifSet

```go
func (r *RubikaCore) GetMyGifSet() (map[string]interface{}, error)
```

Returns the user's saved GIFs.

### SearchStickers

```go
func (r *RubikaCore) SearchStickers(searchText string, startID string) (map[string]interface{}, error)
```

Searches for sticker sets by text. Supports pagination via `startID`.

### GetStickerSetByID

```go
func (r *RubikaCore) GetStickerSetByID(stickerSetID string) (map[string]interface{}, error)
```

Returns a sticker set by its ID.

### GetStickersByEmoji

```go
func (r *RubikaCore) GetStickersByEmoji(emoji string) (map[string]interface{}, error)
```

Returns stickers associated with a specific emoji.

### GetStickersBySetIDs

```go
func (r *RubikaCore) GetStickersBySetIDs(stickerSetIDs []string) (map[string]interface{}, error)
```

Returns stickers from multiple sticker sets by their IDs.

### GetTrendStickerSets

```go
func (r *RubikaCore) GetTrendStickerSets() (map[string]interface{}, error)
```

Returns currently trending sticker sets.

### ActionOnStickerSet

```go
func (r *RubikaCore) ActionOnStickerSet(stickerSetID string, action string) error
```

Performs an action on a sticker set. Actions include `"Add"` (install) and `"Remove"` (uninstall).

### AddToMyGifSet

```go
func (r *RubikaCore) AddToMyGifSet(chatID string, msgID string) error
```

Saves a GIF from a message to the user's GIF collection.

### RemoveFromMyGifSet

```go
func (r *RubikaCore) RemoveFromMyGifSet(fileID string) error
```

Removes a GIF from the user's saved GIF collection by file ID.

---

## Misc & Admin

### SetSetting

```go
func (r *RubikaCore) SetSetting(settings map[string]interface{}) error
```

Updates application settings.

### GetSuggestedFolders

```go
func (r *RubikaCore) GetSuggestedFolders() (map[string]interface{}, error)
```

Returns server-suggested folder configurations.

### AddFolder

```go
func (r *RubikaCore) AddFolder(name string, includeObjectGUIDs []string) (RubikaFolderInfo, error)
```

Creates a new folder with specified chats. Returns the created folder info.

### DeleteFolder

```go
func (r *RubikaCore) DeleteFolder(folderID string) error
```

Deletes a folder by its ID.

### EditFolder

```go
func (r *RubikaCore) EditFolder(folderID string, name string, includedChatGUIDs []string, excludedTypes []string) (map[string]interface{}, error)
```

Edits a folder's name, included chats, and excluded chat types.

### GetAbsObjects

```go
func (r *RubikaCore) GetAbsObjects(guids []string) (map[string]interface{}, error)
```

Returns abbreviated object info for multiple GUIDs in a single request. Useful for batch-resolving user/group/channel names.

### GetLinkFromAppUrl

```go
func (r *RubikaCore) GetLinkFromAppUrl(appURL string) (map[string]interface{}, error)
```

Resolves a Rubika app URL (deep link) to its target.

### GetProfileLinkItems

```go
func (r *RubikaCore) GetProfileLinkItems(objectGUID ...string) (map[string]interface{}, error)
```

Returns profile link items for one or more objects.

### GetRelatedObjects

```go
func (r *RubikaCore) GetRelatedObjects(objectGUID string) (map[string]interface{}, error)
```

Returns objects related to the given GUID (e.g., common groups).

### UserIsAdmin

```go
func (r *RubikaCore) UserIsAdmin(chatID string) (map[string]interface{}, error)
```

Checks if the authenticated user is an admin in the given chat.

### ReportObject

```go
func (r *RubikaCore) ReportObject(chatID string, reportType int, description string) error
```

Reports a user, group, or channel. The `reportType` is a numeric code for the report reason.

### SendChatActivity

```go
func (r *RubikaCore) SendChatActivity(chatID string, activity string) error
```

Sends a chat activity indicator (e.g., `"Typing"`, `"Recording"`).

### SetActionChat

```go
func (r *RubikaCore) SetActionChat(chatID string, action string) error
```

Sets a chat action such as muting notifications or pinning the chat.

### ActionOnJoinRequest

```go
func (r *RubikaCore) ActionOnJoinRequest(chatID string, chatType string, userGUID string, action string) error
```

Approves or rejects a join request. The `action` is `"Accept"` or `"Reject"`. The `chatType` is `"Group"` or `"Channel"`.

### CreateJoinLink

```go
func (r *RubikaCore) CreateJoinLink(chatID string) (map[string]interface{}, error)
```

Creates a new join link for a chat.

### GetJoinLinks

```go
func (r *RubikaCore) GetJoinLinks(chatID string) (map[string]interface{}, error)
```

Returns all join links for a chat.

### GetJoinRequests

```go
func (r *RubikaCore) GetJoinRequests(chatID string) (map[string]interface{}, error)
```

Returns pending join requests for a chat.

### GetContactsUpdates

```go
func (r *RubikaCore) GetContactsUpdates(state int64) (map[string]interface{}, error)
```

Returns contact list updates since the given state number.

### ResetContacts

```go
func (r *RubikaCore) ResetContacts() error
```

Resets the server-side contact list.

### ImportContacts

```go
func (r *RubikaCore) ImportContacts(contacts []map[string]string) (map[string]interface{}, error)
```

Imports contacts in bulk. Each map should contain `"phone"`, `"first_name"`, and optionally `"last_name"`.

### SearchContacts

```go
func (r *RubikaCore) SearchContacts(query string) (map[string]interface{}, error)
```

Searches contacts by name or phone number.

### GetChatInfoByUsername

```go
func (r *RubikaCore) GetChatInfoByUsername(username string) (map[string]interface{}, error)
```

Returns chat info by resolving a username.

### SearchGlobalMessages

```go
func (r *RubikaCore) SearchGlobalMessages(text string, startID string, limit int) (map[string]interface{}, error)
```

Searches messages globally across all chats. Supports pagination via `startID` and result limiting.

### UploadAvatar

```go
func (r *RubikaCore) UploadAvatar(objectGUID string, fileInline map[string]interface{}) error
```

Sets the avatar for a user, group, or channel using a previously uploaded file reference.

### DeleteGroupAvatar

```go
func (r *RubikaCore) DeleteGroupAvatar(groupGUID string, avatarID string) error
```

Deletes a specific avatar from a group.

### GetAvatars

```go
func (r *RubikaCore) GetAvatars(objectGUID string) (RubikaAvatarList, error)
```

Returns all avatars for a user, group, or channel.

### DeleteAvatar

```go
func (r *RubikaCore) DeleteAvatar(objectGUID string, avatarID string) error
```

Deletes a specific avatar from any object type.

### AcceptRequestObjectOwning

```go
func (r *RubikaCore) AcceptRequestObjectOwning(objectGUID string) error
```

Accepts a request to transfer ownership of a group or channel.

### RejectRequestObjectOwning

```go
func (r *RubikaCore) RejectRequestObjectOwning(objectGUID string) error
```

Rejects a request to transfer ownership.

### RequestChangeObjectOwner

```go
func (r *RubikaCore) RequestChangeObjectOwner(objectGUID string, newOwnerGUID string) (map[string]interface{}, error)
```

Initiates an ownership transfer request for a group or channel to a new owner.

---

## Bot API

These methods use the Rubika HTTP bot API. Requires bot-mode authentication.

### BotGetMe

```go
func (r *RubikaCore) BotGetMe() (RubikaBotInfo, error)
```

Returns information about the bot itself.

```go
info, err := rub.BotGetMe()
fmt.Printf("Bot: @%s\n", info.Username)
```

### BotSendMessage

```go
func (r *RubikaCore) BotSendMessage(chatID string, text string, opts map[string]interface{}) (string, error)
```

Sends a text message via the bot API. Returns the message ID. The `opts` map can include `"reply_to_message_id"` and `"inline_keypad"`.

```go
msgID, err := rub.BotSendMessage("g0BGxx...", "Hello from bot!", nil)
```

### BotSendFile

```go
func (r *RubikaCore) BotSendFile(chatID string, fileID string, text string, opts map[string]interface{}) (string, error)
```

Sends a file by its file ID with optional text caption.

### BotSendPoll

```go
func (r *RubikaCore) BotSendPoll(chatID string, question string, options []string) (string, error)
```

Sends a poll via the bot API.

### BotSendLocation

```go
func (r *RubikaCore) BotSendLocation(chatID string, lat string, lon string, opts map[string]interface{}) (string, error)
```

Sends a location message via the bot API. Coordinates are passed as strings.

### BotSendContact

```go
func (r *RubikaCore) BotSendContact(chatID string, phone string, firstName string, lastName string, opts map[string]interface{}) (string, error)
```

Sends a contact card via the bot API.

### BotEditMessageText

```go
func (r *RubikaCore) BotEditMessageText(chatID string, msgID string, text string) error
```

Edits the text of a bot message.

### BotEditMessageKeypad

```go
func (r *RubikaCore) BotEditMessageKeypad(chatID string, msgID string, inlineKeypad map[string]interface{}) error
```

Edits the inline keypad (buttons) on a bot message.

### BotEditChatKeypad

```go
func (r *RubikaCore) BotEditChatKeypad(chatID string, chatKeypad map[string]interface{}, keypadType string) error
```

Sets or updates the persistent chat keypad (reply keyboard). The `keypadType` controls the keyboard behavior.

### BotDeleteMessage

```go
func (r *RubikaCore) BotDeleteMessage(chatID string, msgID string) error
```

Deletes a bot message.

### BotForwardMessage

```go
func (r *RubikaCore) BotForwardMessage(fromChatID string, msgID string, toChatID string) (string, error)
```

Forwards a message via the bot API. Returns the new message ID.

### BotGetChat

```go
func (r *RubikaCore) BotGetChat(chatID string) (RubikaBotChatInfo, error)
```

Returns chat info via the bot API.

### BotGetUpdates

```go
func (r *RubikaCore) BotGetUpdates(offsetID string, limit int) (map[string]interface{}, error)
```

Long-polls for bot updates. Pass an empty `offsetID` for the first call, then use the last received update ID for subsequent calls.

```go
updates, err := rub.BotGetUpdates("", 100)
```

### BotSetCommands

```go
func (r *RubikaCore) BotSetCommands(commands []map[string]string) error
```

Sets the bot's command list. Each map should have `"command"` and `"description"` keys.

```go
err := rub.BotSetCommands([]map[string]string{
    {"command": "start", "description": "Start the bot"},
    {"command": "help", "description": "Show help"},
})
```

### BotUpdateEndpoints

```go
func (r *RubikaCore) BotUpdateEndpoints(url string, endpointType string) error
```

Updates the bot's webhook or callback endpoint.

### BotRequestSendFile

```go
func (r *RubikaCore) BotRequestSendFile(fileType string) (string, error)
```

Requests a file upload slot from the bot API. Returns an upload URL.

### BotGetFile

```go
func (r *RubikaCore) BotGetFile(fileID string) (string, error)
```

Returns the download URL for a file by its ID.

### BotBanChatMember

```go
func (r *RubikaCore) BotBanChatMember(chatID string, userID string) error
```

Bans a member from a chat via the bot API.

### BotUnbanChatMember

```go
func (r *RubikaCore) BotUnbanChatMember(chatID string, userID string) error
```

Unbans a member from a chat via the bot API.

### BotUploadFile

```go
func (r *RubikaCore) BotUploadFile(fileType string, fileName string, data []byte) (string, error)
```

Uploads a file via the bot API. Requests an upload slot, uploads the data, and returns the file ID.

```go
data, _ := os.ReadFile("photo.jpg")
fileID, err := rub.BotUploadFile("Image", "photo.jpg", data)
```

### BotSendSticker

```go
func (r *RubikaCore) BotSendSticker(chatID string, fileID string, opts map[string]interface{}) (string, error)
```

Sends a sticker via the bot API.

### BotSendImage

```go
func (r *RubikaCore) BotSendImage(chatID string, fileID string, caption string, opts map[string]interface{}) (string, error)
```

Sends an image via the bot API with optional caption and inline keypad.

### BotSendDocument

```go
func (r *RubikaCore) BotSendDocument(chatID string, fileID string, caption string, opts map[string]interface{}) (string, error)
```

Sends a document via the bot API.

### BotSendVoice

```go
func (r *RubikaCore) BotSendVoice(chatID string, fileID string, opts map[string]interface{}) (string, error)
```

Sends a voice message via the bot API.

### BotSendVideo

```go
func (r *RubikaCore) BotSendVideo(chatID string, fileID string, caption string, opts map[string]interface{}) (string, error)
```

Sends a video via the bot API.

### BotSendGif

```go
func (r *RubikaCore) BotSendGif(chatID string, fileID string, caption string, opts map[string]interface{}) (string, error)
```

Sends a GIF via the bot API.

### BotSendMusic

```go
func (r *RubikaCore) BotSendMusic(chatID string, fileID string, caption string, opts map[string]interface{}) (string, error)
```

Sends a music file via the bot API.

### BotCheckJoin

```go
func (r *RubikaCore) BotCheckJoin(chatID string, userID string) (RubikaBotJoinStatus, error)
```

Checks if a user is a member of a chat. Useful for verifying mandatory channel joins.

```go
status, err := rub.BotCheckJoin("c0ABxx...", "u0CDxx...")
if status.IsMember {
    fmt.Println("User has joined")
}
```

### BotRemoveKeypad

```go
func (r *RubikaCore) BotRemoveKeypad(chatID string) error
```

Removes the persistent chat keypad (reply keyboard) for a chat.

### BotReplyMessage

```go
func (r *RubikaCore) BotReplyMessage(chatID string, text string, replyToMsgID string, opts map[string]interface{}) (string, error)
```

Sends a reply message via the bot API. Returns the message ID.

---

## WebSocket Events

These methods register handlers for specific WebSocket event types. User mode only.

### OnChatUpdates

```go
func (r *RubikaCore) OnChatUpdates(handler func(map[string]interface{}))
```

Registers a handler for chat update events (new messages, edits, deletes, etc.).

```go
rub.OnChatUpdates(func(update map[string]interface{}) {
    fmt.Printf("Chat update: %v\n", update)
})
```

### OnShowActivities

```go
func (r *RubikaCore) OnShowActivities(handler func(map[string]interface{}))
```

Registers a handler for activity events (typing indicators, recording indicators).

### OnShowNotifications

```go
func (r *RubikaCore) OnShowNotifications(handler func(map[string]interface{}))
```

Registers a handler for notification events.

### OnRemoveNotifications

```go
func (r *RubikaCore) OnRemoveNotifications(handler func(map[string]interface{}))
```

Registers a handler for notification removal events (e.g., when messages are read elsewhere).

---

## Unsupported Core Methods

These Core interface methods are not supported by the Rubika protocol and return `ErrNotSupported`.

### MuteChat

```go
func (r *RubikaCore) MuteChat(chatID string, muted bool) error
```

Not supported. Returns `ErrNotSupported`.

### ArchiveChat

```go
func (r *RubikaCore) ArchiveChat(chatID string, archived bool) error
```

Not supported. Returns `ErrNotSupported`.

### MarkUnread

```go
func (r *RubikaCore) MarkUnread(chatID string, unread bool) error
```

Not supported. Returns `ErrNotSupported`.

### UnpinAllMessages

```go
func (r *RubikaCore) UnpinAllMessages(chatID string) error
```

Not supported. Returns `ErrNotSupported`.

### AcceptCall

```go
func (r *RubikaCore) AcceptCall(callID string) (*CallSession, error)
```

Not supported. Returns `ErrNotSupported`.

### DeclineCall

```go
func (r *RubikaCore) DeclineCall(callID string) error
```

Not supported. Returns `ErrNotSupported`.

---

## Dependencies

- Standard library only (`net`, `crypto`, `encoding/json`, `net/http`)
- No CGo required
- Pure Go RSA/AES/SHA256 crypto pipeline
- WebSocket via standard library
