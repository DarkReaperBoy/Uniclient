# Delta Chat Core — API Reference

Pure Go Delta Chat client implementing chat-over-email via IMAP/SMTP with Autocrypt E2EE (OpenPGP). No CGo, no external dependencies. Works with any email provider — Gmail, Outlook, Fastmail, or chatmail servers.

**245 exported methods** across messaging, groups, contacts, calls, webxdc apps, location sharing, key management, multi-account, backup, and configuration.

## Table of Contents

- [Setup](#setup)
- [Types](#types)
- [Connection & Authentication](#connection--authentication)
- [Core Interface Methods](#core-interface-methods)
- [Chat Management](#chat-management)
- [Chat Properties](#chat-properties)
- [Chatlist Operations](#chatlist-operations)
- [Contact Management](#contact-management)
- [Contact Properties](#contact-properties)
- [Message Operations](#message-operations)
- [Message Properties](#message-properties)
- [Search](#search)
- [File Transfer & Media](#file-transfer--media)
- [Calls](#calls)
- [Stickers](#stickers)
- [Drafts & Polls](#drafts--polls)
- [Ephemeral Messages](#ephemeral-messages)
- [Webxdc Apps](#webxdc-apps)
- [Location Sharing](#location-sharing)
- [vCard Import/Export](#vcard-importexport)
- [HTML Messages](#html-messages)
- [Autocrypt & Keys](#autocrypt--keys)
- [Key Transfer](#key-transfer)
- [SecureJoin & QR Codes](#securejoin--qr-codes)
- [Backup & Export](#backup--export)
- [Configuration](#configuration)
- [Multi-Account](#multi-account)
- [Transports](#transports)
- [I/O & Network Control](#io--network-control)
- [Account Management](#account-management)
- [Provider Database](#provider-database)
- [Push Notifications](#push-notifications)
- [Device Messages](#device-messages)
- [Sessions](#sessions)
- [Read Receipts](#read-receipts)
- [OAuth2](#oauth2)
- [Connectivity & System Info](#connectivity--system-info)
- [Stock Strings](#stock-strings)
- [Event Handlers](#event-handlers)
- [Convenience Wrappers](#convenience-wrappers)

## Setup

```go
import "uniclient/cores"

dc := cores.NewDeltaChatCore("./sessions/deltachat.json")
```

**Capabilities:** `TEXT`, `CHANNELS`, `CALLS`, `REACTIONS`, `READ_RECEIPTS`, `BASE64_IMAGE`, `E2EE`, `TYPING`, `SEARCH`, `BLOCKING`, `LOCATION`, `FILE_TRANSFER`

## Types

### DeltaChatCore

The main core struct. Create with `NewDeltaChatCore(sessionPath)`. Manages IMAP/SMTP connections, Autocrypt key exchange, chat state, and WebRTC calls.

### DCLocationStream

```go
type DCLocationStream struct {
    ChatID   string
    Duration time.Duration
    StartAt  time.Time
    Cancel   context.CancelFunc
}
```

Tracks an active location-sharing session for a chat.

### DCWebxdcUpdate

```go
type DCWebxdcUpdate struct {
    Serial  int             `json:"serial"`
    Payload json.RawMessage `json:"payload"`
    Info    string          `json:"info,omitempty"`
    Sender  string          `json:"sender"`
    Time    int64           `json:"time"`
}
```

A single status update for a webxdc mini-app instance.

### DCTransport

```go
type DCTransport struct {
    ID       string `json:"id"`
    Email    string `json:"email"`
    Password string `json:"password"`
    IMAPHost string `json:"imap_host"`
    SMTPHost string `json:"smtp_host"`
}
```

Represents an additional email transport for multi-account support.

### DCLocation

```go
type DCLocation struct {
    Lat         float64 `json:"lat"`
    Lon         float64 `json:"lon"`
    Time        int64   `json:"time"`
    Sender      string  `json:"sender"`
    ChatID      string  `json:"chat_id"`
    Independent bool    `json:"independent"`
}
```

A stored location point. `Independent` distinguishes POI markers from streaming points.

### DeltaChatWebxdcInfo

```go
type DeltaChatWebxdcInfo struct {
    Name          string `json:"name"`
    Icon          string `json:"icon"`
    SourceCodeURL string `json:"source_code_url"`
    Summary       string `json:"summary"`
}
```

Metadata parsed from a `.xdc` ZIP manifest.

### DeltaChatStorageReport

```go
type DeltaChatStorageReport struct {
    SessionBytes  int64 `json:"session_bytes"`
    TotalBytes    int64 `json:"total_bytes"`
    MessagesCount int   `json:"messages_count"`
    ChatsCount    int   `json:"chats_count"`
    ContactsCount int   `json:"contacts_count"`
}
```

Breakdown of local storage usage.

### DeltaChatProviderInfo

```go
type DeltaChatProviderInfo struct {
    Status          int    `json:"status"`
    BeforeLoginHint string `json:"before_login_hint"`
    AfterLoginHint  string `json:"after_login_hint"`
    OverviewPage    string `json:"overview_page"`
    IMAPHost        string `json:"imap_host"`
    IMAPPort        int    `json:"imap_port"`
    SMTPHost        string `json:"smtp_host"`
    SMTPPort        int    `json:"smtp_port"`
}
```

Auto-config information for an email provider. Status: 1=OK, 2=broken, 3=preparation needed.

### DeltaChatQuotaInfo

```go
type DeltaChatQuotaInfo struct {
    Current int64 `json:"current"`
    Limit   int64 `json:"limit"`
}
```

IMAP mailbox quota usage (current bytes and limit).

---

## Connection & Authentication

### Name

```go
func (d *DeltaChatCore) Name() string
```

Returns `"deltachat"`.

### Capabilities

```go
func (d *DeltaChatCore) Capabilities() []string
```

Returns the list of supported capabilities.

### Authenticate

```go
func (d *DeltaChatCore) Authenticate(cfg AuthConfig) error
```

Connects to IMAP/SMTP using email credentials. Auto-discovers servers from the email domain via DNS SRV records. Generates an Ed25519/Curve25519 Autocrypt keypair. Starts dual IMAP IDLE connections for real-time delivery.

**AuthConfig fields:**
- `cfg.Phone` or `Extra["email"]` -- email address (required)
- `cfg.Password2F` or `Extra["password"]` -- email password (required)
- `Extra["display_name"]` -- display name (optional, defaults to email prefix)
- `Extra["imap_host"]` -- custom IMAP host:port (optional, auto-detected)
- `Extra["smtp_host"]` -- custom SMTP host:port (optional, auto-detected)
- `cfg.Mode` -- `AuthModeBot` for bot mode (no BCC self, auto-delete after processing)

```go
err := dc.Authenticate(cores.AuthConfig{
    Extra: map[string]string{
        "email":    "user@example.com",
        "password": "email_password",
    },
})
```

### Logout

```go
func (d *DeltaChatCore) Logout() error
```

Disconnects IMAP/SMTP, cancels background goroutines, removes session file. Sets authed=false.

### Close

```go
func (d *DeltaChatCore) Close() error
```

Full shutdown: closes all connections, cancels context, waits for goroutines, saves session.

### OnUpdate

```go
func (d *DeltaChatCore) OnUpdate(handler func(Update))
```

Registers a callback for unified updates (new messages, connectivity changes, etc.).

```go
dc.OnUpdate(func(u cores.Update) {
    if u.Message != nil {
        fmt.Printf("[%s] %s: %s\n", u.ChatID, u.Message.SenderName, u.Message.Text)
    }
})
```

### IsConfigured

```go
func (d *DeltaChatCore) IsConfigured() bool
```

Returns true if the account is authenticated and configured.

---

## Core Interface Methods

These implement the unified `Core` interface shared across all platforms.

### Messaging

#### SendMessage

```go
func (d *DeltaChatCore) SendMessage(chatID string, msg OutgoingMessage) (*Message, error)
```

Sends a message (email) to a chat. Encrypts with PGP/MIME if peer keys are available. For groups, sends to all members with Chat-Group-ID header.

```go
msg, err := dc.SendMessage("dm:friend@example.com", cores.OutgoingMessage{Text: "Hello!"})
```

#### GetMessages

```go
func (d *DeltaChatCore) GetMessages(chatID string, opts PaginationOpts) ([]Message, error)
```

Returns cached messages for a chat. Syncs from IMAP first. Supports `Offset` and `Limit` pagination.

#### EditMessage

```go
func (d *DeltaChatCore) EditMessage(chatID string, msgID string, text string) (*Message, error)
```

Edits a sent message by sending a replacement email with `Chat-Edit` header referencing the original Message-ID.

#### DeleteMessage

```go
func (d *DeltaChatCore) DeleteMessage(chatID string, msgID string) error
```

Deletes a message locally. If the message is on the IMAP server, marks it as deleted there too.

#### ReplyToMessage

```go
func (d *DeltaChatCore) ReplyToMessage(chatID string, replyToMsgID string, msg OutgoingMessage) (*Message, error)
```

Sends a reply email with `In-Reply-To` and `References` headers set to the original message ID.

#### ForwardMessage

```go
func (d *DeltaChatCore) ForwardMessage(fromChatID string, msgID string, toChatID string) (*Message, error)
```

Forwards a message to another chat by re-sending it with `X-Forwarded-Message-Id` header.

#### ReactToMessage

```go
func (d *DeltaChatCore) ReactToMessage(chatID string, msgID string, emoji string) error
```

Sends a reaction email with `Chat-Content: reaction` header. The emoji is the message body.

#### PinMessage

```go
func (d *DeltaChatCore) PinMessage(chatID string, msgID string) error
```

Pins a message in a chat (local state).

#### UnpinMessage

```go
func (d *DeltaChatCore) UnpinMessage(chatID string, msgID string) error
```

Unpins a message in a chat (local state).

#### UnpinAllMessages

```go
func (d *DeltaChatCore) UnpinAllMessages(chatID string) error
```

Removes all pins in a chat.

#### MarkAsRead

```go
func (d *DeltaChatCore) MarkAsRead(chatID string, upToMsgID string) error
```

Marks messages as read up to the given message ID. Sends MDN (read receipt) emails to senders.

#### GetReadState

```go
func (d *DeltaChatCore) GetReadState(chatID string) (*ReadState, error)
```

Returns the local read state for a chat.

#### SendTyping

```go
func (d *DeltaChatCore) SendTyping(chatID string) error
```

Sends a typing indicator (local-only notification, not sent over email).

#### ResendMessage

```go
func (d *DeltaChatCore) ResendMessage(chatID string, msgID string) (*Message, error)
```

Re-sends a failed message by re-submitting it via SMTP.

#### SendImageBase64

```go
func (d *DeltaChatCore) SendImageBase64(chatID string, b64 string, caption string) (*Message, error)
```

Sends a base64-encoded image as a MIME attachment. Decodes to PNG, attaches to email.

#### SendContact

```go
func (d *DeltaChatCore) SendContact(chatID string, contactEmail string) (*Message, error)
```

Sends a contact's vCard as an email attachment.

#### SendVideochatInvitation

```go
func (d *DeltaChatCore) SendVideochatInvitation(chatID string) (*Message, error)
```

Sends a videochat invitation message with a `Chat-Content: videochat-invitation` header.

#### SendHTML

```go
func (d *DeltaChatCore) SendHTML(chatID string, html string, plaintext string) (*Message, error)
```

Sends a multipart/alternative email with both HTML and plaintext parts. Encrypts with PGP/MIME when possible.

```go
msg, err := dc.SendHTML("dm:friend@example.com", "<b>Hello</b>", "Hello")
```

### Dialogs

#### GetDialogs

```go
func (d *DeltaChatCore) GetDialogs(opts PaginationOpts) ([]Dialog, error)
```

Returns all chats as dialogs. Syncs IMAP messages first to build the chat list.

#### GetChatInfo

```go
func (d *DeltaChatCore) GetChatInfo(chatID string) (*Dialog, error)
```

Returns detailed info for a specific chat.

### Groups & Channels

#### CreateGroup

```go
func (d *DeltaChatCore) CreateGroup(name string, members []string) (*Dialog, error)
```

Creates a group chat. Generates a unique Chat-Group-ID and sends a group creation email to all members with `Chat-Group-Name` header.

```go
dlg, err := dc.CreateGroup("Book Club", []string{"alice@example.com", "bob@example.com"})
```

#### CreateChannel

```go
func (d *DeltaChatCore) CreateChannel(name string, description string) (*Dialog, error)
```

Creates a broadcast list (one-way channel). Members receive messages but cannot reply to the group.

#### CreateTopic

```go
func (d *DeltaChatCore) CreateTopic(chatID string, name string) (*Dialog, error)
```

Creates a sub-group within an existing group (separate Chat-Group-ID thread).

### Members

#### AddMembers

```go
func (d *DeltaChatCore) AddMembers(chatID string, userIDs []string) error
```

Adds members to a group by sending a `Chat-Group-Member-Added` email to all members.

#### RemoveMember

```go
func (d *DeltaChatCore) RemoveMember(chatID string, userID string) error
```

Removes a member from a group by sending a `Chat-Group-Member-Removed` email.

#### BanMember

```go
func (d *DeltaChatCore) BanMember(chatID string, userID string) error
```

Removes a member and blocks their email from the group.

#### UnbanMember

```go
func (d *DeltaChatCore) UnbanMember(chatID string, userID string) error
```

Unblocks a previously banned member.

#### GetMembers

```go
func (d *DeltaChatCore) GetMembers(chatID string, opts PaginationOpts) ([]User, error)
```

Returns the member list for a group chat. Supports pagination.

#### SetAdmin

```go
func (d *DeltaChatCore) SetAdmin(chatID string, userID string, admin bool) error
```

Sets or removes admin status for a group member.

### Contacts & Blocking

#### GetContacts

```go
func (d *DeltaChatCore) GetContacts() ([]User, error)
```

Returns all known contacts from the Autocrypt peer state database.

#### AddContact

```go
func (d *DeltaChatCore) AddContact(phone string, firstName string, lastName string) error
```

Adds a contact by email address (the `phone` parameter holds the email).

#### DeleteContact

```go
func (d *DeltaChatCore) DeleteContact(userID string) error
```

Removes a contact from the peer state database.

#### BlockUser

```go
func (d *DeltaChatCore) BlockUser(userID string) error
```

Blocks a contact by email. Their messages will be ignored.

#### UnblockUser

```go
func (d *DeltaChatCore) UnblockUser(userID string) error
```

Unblocks a contact.

#### GetBlockedUsers

```go
func (d *DeltaChatCore) GetBlockedUsers() ([]User, error)
```

Returns all blocked contacts.

### Profiles

#### GetProfile

```go
func (d *DeltaChatCore) GetProfile(userID string) (*User, error)
```

Returns profile info for a contact by email address. Includes display name, email, last seen time, and Autocrypt state.

### Folders

#### GetFolders

```go
func (d *DeltaChatCore) GetFolders() ([]Folder, error)
```

Returns virtual folders (All, Unread, Groups, Channels, Archived).

#### CreateFolder

```go
func (d *DeltaChatCore) CreateFolder(name string, chatIDs []string) (*Folder, error)
```

Creates a virtual folder containing specific chats.

---

## Chat Management

### EditChatTitle

```go
func (d *DeltaChatCore) EditChatTitle(chatID string, title string) error
```

Changes a group chat title by sending a `Chat-Group-Name-Changed` email to all members.

### EditChatDescription

```go
func (d *DeltaChatCore) EditChatDescription(chatID string, description string) error
```

Changes a group chat description by sending a `Chat-Group-Description` email.

### LeaveChat

```go
func (d *DeltaChatCore) LeaveChat(chatID string) error
```

Leaves a group chat by sending a `Chat-Group-Member-Removed` email for yourself.

### GetInviteLink

```go
func (d *DeltaChatCore) GetInviteLink(chatID string) (string, error)
```

Returns a Delta Chat invite link (`https://i.delta.chat/#...`) containing the group fingerprint and address.

### SetChatImage

```go
func (d *DeltaChatCore) SetChatImage(chatID string, imageB64 string) error
```

Sets a group chat avatar by sending a `Chat-Group-Avatar` email with the image attached.

### RemoveChatImage

```go
func (d *DeltaChatCore) RemoveChatImage(chatID string) error
```

Removes the group chat avatar.

### SetChatVisibility

```go
func (d *DeltaChatCore) SetChatVisibility(chatID string, visibility int) error
```

Sets chat visibility. 0=Normal, 1=Archived, 2=Pinned.

### SetChatMuted

```go
func (d *DeltaChatCore) SetChatMuted(chatID string, duration int64) error
```

Mutes a chat. Duration in seconds: 0=forever, -1=unmute, positive=timed mute.

### SetChatProtected

```go
func (d *DeltaChatCore) SetChatProtected(chatID string, protected bool) error
```

Enables or disables verified encryption for a chat. When protected, all messages must be encrypted and from verified contacts.

### AcceptChat

```go
func (d *DeltaChatCore) AcceptChat(chatID string) error
```

Accepts a chat from the contact request list.

### BlockChat

```go
func (d *DeltaChatCore) BlockChat(chatID string) error
```

Blocks a chat and all its members.

### DeleteChat

```go
func (d *DeltaChatCore) DeleteChat(chatID string) error
```

Deletes a chat and all its cached messages.

### MarkNoticedChat

```go
func (d *DeltaChatCore) MarkNoticedChat(chatID string) error
```

Marks a chat as noticed (resets unread count).

### MarkFreshChat

```go
func (d *DeltaChatCore) MarkFreshChat(chatID string) error
```

Marks a chat as fresh (sets unread count to 1).

### SetAvatar

```go
func (d *DeltaChatCore) SetAvatar(imageB64 string) error
```

Sets the user's avatar image (stored for inclusion in outgoing emails via `Chat-User-Avatar` header).

### SetStatus

```go
func (d *DeltaChatCore) SetStatus(text string) error
```

Sets the user's bio/status text.

### GetStatus

```go
func (d *DeltaChatCore) GetStatus() string
```

Returns the user's bio/status text.

---

## Chat Properties

### GetChatMedia

```go
func (d *DeltaChatCore) GetChatMedia(chatID string, viewtype string) ([]*Message, error)
```

Returns all media messages in a chat filtered by MIME type prefix (e.g., `"image"`, `"video"`, `"audio"`). Pass empty string for all media.

### GetChatContacts

```go
func (d *DeltaChatCore) GetChatContacts(chatID string) ([]string, error)
```

Returns contact emails for a chat's current members.

### GetPastContacts

```go
func (d *DeltaChatCore) GetPastContacts(chatID string) ([]string, error)
```

Returns contacts who have left a group chat.

### GetChatIdByContactId

```go
func (d *DeltaChatCore) GetChatIdByContactId(email string) (string, error)
```

Looks up the 1:1 chat ID for a contact email.

### CreateChatByContactId

```go
func (d *DeltaChatCore) CreateChatByContactId(email string) (string, error)
```

Creates a 1:1 chat with a contact. Returns the chat ID (format: `dm:email@example.com`).

```go
chatID, err := dc.CreateChatByContactId("friend@example.com")
```

### CanSend

```go
func (d *DeltaChatCore) CanSend(chatID string) bool
```

Returns true if the user can send messages to this chat (chat exists and authenticated).

### GetChatColor

```go
func (d *DeltaChatCore) GetChatColor(chatID string) string
```

Returns a deterministic hex color for a chat (e.g., `"#a3f2c1"`).

### GetChatType

```go
func (d *DeltaChatCore) GetChatType(chatID string) string
```

Returns the chat type: `"single"`, `"group"`, `"mailinglist"`, or `"broadcast"`.

### IsChatContactRequest

```go
func (d *DeltaChatCore) IsChatContactRequest(chatID string) bool
```

Returns true if the chat is a pending contact request.

### IsChatDeviceTalk

```go
func (d *DeltaChatCore) IsChatDeviceTalk(chatID string) bool
```

Returns true if the chat is the device-messages chat.

### IsChatSelfTalk

```go
func (d *DeltaChatCore) IsChatSelfTalk(chatID string) bool
```

Returns true if the chat is Saved Messages (self-talk).

### IsChatUnpromoted

```go
func (d *DeltaChatCore) IsChatUnpromoted(chatID string) bool
```

Returns true if a group hasn't been announced to members yet.

### IsChatEncrypted

```go
func (d *DeltaChatCore) IsChatEncrypted(chatID string) bool
```

Returns true if encryption is enabled for the chat.

### GetRemainingMuteDuration

```go
func (d *DeltaChatCore) GetRemainingMuteDuration(chatID string) int64
```

Returns remaining mute duration in seconds (0 if not muted).

### GetMailingListAddr

```go
func (d *DeltaChatCore) GetMailingListAddr(chatID string) string
```

Returns the posting address for a mailing list chat.

### GetFreshMessageCount

```go
func (d *DeltaChatCore) GetFreshMessageCount(chatID string) int
```

Returns the unread message count for a chat.

---

## Chatlist Operations

### GetChatlistEntries

```go
func (d *DeltaChatCore) GetChatlistEntries(listFlags int, query string) ([]string, error)
```

Returns chat IDs matching optional query filter. Pass empty query for all chats.

### GetChatlistItemsByEntries

```go
func (d *DeltaChatCore) GetChatlistItemsByEntries(chatIDs []string) ([]map[string]interface{}, error)
```

Returns basic info (id, name, type) for a list of chat IDs.

### GetChatlistSummary

```go
func (d *DeltaChatCore) GetChatlistSummary(chatID string) (map[string]interface{}, error)
```

Returns a summary for a chat: name, unread count, last message text, and timestamp.

### GetBasicChatInfo

```go
func (d *DeltaChatCore) GetBasicChatInfo(chatID string) (map[string]interface{}, error)
```

Returns basic chat info: id, name, is_group, member_count.

### GetFullChatById

```go
func (d *DeltaChatCore) GetFullChatById(chatID string) (map[string]interface{}, error)
```

Returns full chat details: id, name, is_group, members, is_encrypted, is_muted, fresh_count.

---

## Contact Management

### AddContact

```go
func (d *DeltaChatCore) AddContact(phone string, firstName string, lastName string) error
```

Adds a contact by email address.

### DeleteContact

```go
func (d *DeltaChatCore) DeleteContact(userID string) error
```

Removes a contact from the peer state database.

### GetContacts

```go
func (d *DeltaChatCore) GetContacts() ([]User, error)
```

Returns all known contacts.

### BlockUser / UnblockUser

```go
func (d *DeltaChatCore) BlockUser(userID string) error
func (d *DeltaChatCore) UnblockUser(userID string) error
```

Blocks or unblocks a contact by email.

### GetBlockedUsers

```go
func (d *DeltaChatCore) GetBlockedUsers() ([]User, error)
```

Returns all blocked contacts.

### AddAddressBook

```go
func (d *DeltaChatCore) AddAddressBook(csv string) int
```

Imports contacts from a CSV string (alternating lines: Name, Email). Returns the number of contacts added.

```go
count := dc.AddAddressBook("Alice\nalice@example.com\nBob\nbob@example.com")
```

### ChangeContactName

```go
func (d *DeltaChatCore) ChangeContactName(email, newName string) error
```

Changes the display name for a contact.

### IsContactInChat

```go
func (d *DeltaChatCore) IsContactInChat(chatID, email string) bool
```

Returns true if a contact is a member of the specified chat.

---

## Contact Properties

### LookupContactByAddr

```go
func (d *DeltaChatCore) LookupContactByAddr(email string) (string, error)
```

Looks up a contact by email. Returns the canonical email if found.

### GetContactEncryptionInfo

```go
func (d *DeltaChatCore) GetContactEncryptionInfo(email string) (string, error)
```

Returns encryption info for a contact: key fingerprint or "no Autocrypt".

### IsContactVerified

```go
func (d *DeltaChatCore) IsContactVerified(email string) bool
```

Returns true if the contact has a verified Autocrypt key with mutual encryption preference.

### IsContactBot

```go
func (d *DeltaChatCore) IsContactBot(email string) bool
```

Always returns false (Delta Chat has no bot detection mechanism).

### IsContactKeyContact

```go
func (d *DeltaChatCore) IsContactKeyContact(email string) bool
```

Returns true if we have a public key for this contact.

### GetContactColor

```go
func (d *DeltaChatCore) GetContactColor(email string) string
```

Returns a deterministic hex color for a contact.

### GetContactAuthName

```go
func (d *DeltaChatCore) GetContactAuthName(email string) string
```

Returns the authenticated display name from the peer's Autocrypt header.

### GetContactLastSeen

```go
func (d *DeltaChatCore) GetContactLastSeen(email string) time.Time
```

Returns the last time a message was received from this contact.

### GetContactVerifierId

```go
func (d *DeltaChatCore) GetContactVerifierId(email string) string
```

Returns empty string (not tracked in this implementation).

### GetContactStatus

```go
func (d *DeltaChatCore) GetContactStatus(email string) string
```

Returns empty string (contact status not available over email).

### WasContactSeenRecently

```go
func (d *DeltaChatCore) WasContactSeenRecently(email string) bool
```

Returns true if a contact was seen within the last 7 days.

---

## Message Operations

### GetFreshMessages

```go
func (d *DeltaChatCore) GetFreshMessages() ([]Message, error)
```

Returns all unread messages across all chats, sorted chronologically.

### GetNextMessages

```go
func (d *DeltaChatCore) GetNextMessages(chatID string, lastSeenMsgID string) ([]*Message, error)
```

Returns messages after the given message ID. Pass empty string for all messages.

### WaitNextMessages

```go
func (d *DeltaChatCore) WaitNextMessages(chatID string, timeout time.Duration) ([]*Message, error)
```

Polls for new messages with a timeout. Returns when messages arrive or timeout expires.

### GetFirstUnreadMessage

```go
func (d *DeltaChatCore) GetFirstUnreadMessage(chatID string) (string, error)
```

Returns the message ID of the first unread message in a chat.

### DeleteMessagesForAll

```go
func (d *DeltaChatCore) DeleteMessagesForAll(chatID string, msgIDs []string) error
```

Deletes messages from all recipients by sending a `Chat-Content: delete-messages` email. Also deletes locally.

### ForwardMessagesToAccount

```go
func (d *DeltaChatCore) ForwardMessagesToAccount(msgIDs []string, targetEmail string) error
```

Forwards messages to a different email account by re-sending them to the target address.

### SaveMessages

```go
func (d *DeltaChatCore) SaveMessages(msgIDs []string) error
```

Saves messages to the Saved Messages chat.

### GetReactions

```go
func (d *DeltaChatCore) GetReactions(chatID string, msgID string) ([]Reaction, error)
```

Returns reactions on a message.

### DownloadFullMessage

```go
func (d *DeltaChatCore) DownloadFullMessage(chatID, msgID string) error
```

Downloads the full body of a partially-downloaded message from IMAP. Searches by Message-ID header and replaces the cached partial version.

### GetMessageHTML

```go
func (d *DeltaChatCore) GetMessageHTML(chatID, msgID string) (string, error)
```

Returns the original HTML version of a message. Falls back to wrapping plain text in HTML tags.

### GetEncryptionInfo

```go
func (d *DeltaChatCore) GetEncryptionInfo(chatID string) (string, error)
```

Returns encryption status for a chat, including protection status and per-member key info.

### GetConnectivity

```go
func (d *DeltaChatCore) GetConnectivity() (string, error)
```

Returns a human-readable connectivity status string.

---

## Message Properties

### GetMessageInfo

```go
func (d *DeltaChatCore) GetMessageInfo(chatID, msgID string) (map[string]string, error)
```

Returns metadata for a message: id, status, timestamp, sender, text.

### GetMessageSubject

```go
func (d *DeltaChatCore) GetMessageSubject(chatID, msgID string) string
```

Returns the email subject line of a message.

### SetMessageSubject

```go
func (d *DeltaChatCore) SetMessageSubject(msg *OutgoingMessage, subject string)
```

Sets a custom subject line on an outgoing message.

### GetMessageDownloadState

```go
func (d *DeltaChatCore) GetMessageDownloadState(chatID, msgID string) string
```

Returns the download state: `"done"` or partial state.

### GetMessageSortTimestamp

```go
func (d *DeltaChatCore) GetMessageSortTimestamp(chatID, msgID string) int64
```

Returns the sort timestamp in milliseconds.

### GetMessageError

```go
func (d *DeltaChatCore) GetMessageError(chatID, msgID string) string
```

Returns the error string for a failed message, or empty if no error.

### IsMessageBot

```go
func (d *DeltaChatCore) IsMessageBot(chatID, msgID string) bool
```

Returns true if the message was sent by a bot.

### IsMessageEdited

```go
func (d *DeltaChatCore) IsMessageEdited(chatID, msgID string) bool
```

Returns true if the message has been edited.

### IsMessageForwarded

```go
func (d *DeltaChatCore) IsMessageForwarded(chatID, msgID string) bool
```

Returns true if the message was forwarded.

### IsMessageInfo

```go
func (d *DeltaChatCore) IsMessageInfo(chatID, msgID string) bool
```

Returns true if the message is an informational system message.

### GetMessageInfoType

```go
func (d *DeltaChatCore) GetMessageInfoType(chatID, msgID string) string
```

Returns the info message type (e.g., member added, member removed).

### GetMessageParent

```go
func (d *DeltaChatCore) GetMessageParent(chatID, msgID string) string
```

Returns the parent message ID (In-Reply-To).

### GetOriginalMsgId

```go
func (d *DeltaChatCore) GetOriginalMsgId(chatID, msgID string) string
```

Returns the original message ID for a saved/forwarded message.

### GetSavedMsgId

```go
func (d *DeltaChatCore) GetSavedMsgId(chatID, msgID string) string
```

Returns the saved-copy message ID, if this message was saved.

### HasMessageHtml

```go
func (d *DeltaChatCore) HasMessageHtml(chatID, msgID string) bool
```

Returns true if the message has an HTML part.

### HasMessageLocation

```go
func (d *DeltaChatCore) HasMessageLocation(chatID, msgID string) bool
```

Returns true if the message has location data attached.

### HasDeviatingTimestamp

```go
func (d *DeltaChatCore) HasDeviatingTimestamp(chatID, msgID string) bool
```

Returns true if the message timestamp differs significantly from receive time.

### GetOverrideSenderName

```go
func (d *DeltaChatCore) GetOverrideSenderName(chatID, msgID string) string
```

Returns the override sender display name, if set.

### SetOverrideSenderName

```go
func (d *DeltaChatCore) SetOverrideSenderName(msg *OutgoingMessage, name string)
```

Sets a custom sender display name on an outgoing message.

### GetShowPadlock

```go
func (d *DeltaChatCore) GetShowPadlock(chatID, msgID string) bool
```

Returns true if a padlock icon should be shown (message was encrypted).

### MessageSaveFile

```go
func (d *DeltaChatCore) MessageSaveFile(chatID, msgID, destPath string) error
```

Saves a message's file attachment to a destination path.

### SetMessageDimensions

```go
func (d *DeltaChatCore) SetMessageDimensions(msg *OutgoingMessage, width, height int)
```

Sets image/video dimensions on an outgoing message.

### SetMessageDuration

```go
func (d *DeltaChatCore) SetMessageDuration(msg *OutgoingMessage, duration int)
```

Sets audio/video duration on an outgoing message.

### SetMessageLocation

```go
func (d *DeltaChatCore) SetMessageLocation(msg *OutgoingMessage, lat, lon float64)
```

Attaches location coordinates to an outgoing message.

### SetMessageHtml

```go
func (d *DeltaChatCore) SetMessageHtml(msg *OutgoingMessage, html string)
```

Sets HTML content on an outgoing message.

---

## Search

### SearchMessages

```go
func (d *DeltaChatCore) SearchMessages(chatID string, query string, opts PaginationOpts) ([]Message, error)
```

Searches messages in a specific chat by text substring.

### SearchGlobal

```go
func (d *DeltaChatCore) SearchGlobal(query string, opts PaginationOpts) ([]Dialog, error)
```

Searches all chats and contacts by name or email substring.

---

## File Transfer & Media

### UploadFile

```go
func (d *DeltaChatCore) UploadFile(chatID string, file FileUpload, progress func(sent, total int64)) (*Message, error)
```

Sends a file as a MIME attachment in an email. Supports progress callback.

```go
msg, err := dc.UploadFile("dm:friend@example.com", cores.FileUpload{
    Name:   "report.pdf",
    Reader: file,
    Size:   fileSize,
}, nil)
```

### DownloadFile

```go
func (d *DeltaChatCore) DownloadFile(fileRef FileRef, dest string, progress func(recv, total int64)) error
```

Downloads a file attachment to a local path. Supports progress callback.

---

## Calls

Delta Chat calls use WebRTC with SDP offer/answer exchanged via email.

### StartCall

```go
func (d *DeltaChatCore) StartCall(chatID string, video bool) (*CallSession, error)
```

Starts a 1:1 WebRTC call by sending an SDP offer email with `Chat-Content: webrtc-offer`. Only DM chats are supported.

```go
session, err := dc.StartCall("dm:friend@example.com", false)
```

### AcceptIncomingCall

```go
func (d *DeltaChatCore) AcceptIncomingCall(callID string, offerPayload string) (*CallSession, error)
```

Accepts an incoming call by creating a WebRTC peer connection and sending an SDP answer email.

### AcceptCall

```go
func (d *DeltaChatCore) AcceptCall(callID string) (*CallSession, error)
```

Convenience wrapper for `AcceptIncomingCall(callID, "")`.

### DeclineCall

```go
func (d *DeltaChatCore) DeclineCall(callID string) error
```

Declines a call. Delegates to `EndCall`.

### JoinGroupCall

```go
func (d *DeltaChatCore) JoinGroupCall(chatID string) (*CallSession, error)
```

Not supported (Delta Chat calls are 1:1 only). Returns `ErrNotSupported`.

### EndCall

```go
func (d *DeltaChatCore) EndCall(callID string) error
```

Ends an active call by closing the WebRTC peer connection and sending a `Chat-Content: webrtc-hangup` email.

### SetCallMuted

```go
func (d *DeltaChatCore) SetCallMuted(callID string, muted bool) error
```

Mutes or unmutes the audio track in an active call.

### GetCallInfo

```go
func (d *DeltaChatCore) GetCallInfo(callID string) (*CallSession, error)
```

Returns info about an active call session.

---

## Stickers

### GetStickerFolder

```go
func (d *DeltaChatCore) GetStickerFolder() (string, error)
```

Returns the path to the sticker storage directory, creating it if needed.

### GetStickers

```go
func (d *DeltaChatCore) GetStickers() (map[string][]string, error)
```

Returns available stickers as pack name to file paths. Loose stickers go in the `"default"` pack.

### SaveSticker

```go
func (d *DeltaChatCore) SaveSticker(chatID, msgID string) error
```

Saves an image attachment from a message to the sticker folder under the `"saved"` pack.

### SendSticker

```go
func (d *DeltaChatCore) SendSticker(chatID string, stickerID string) (*Message, error)
```

Sends a sticker image as a message attachment. The `stickerID` is a file path to the sticker image.

---

## Drafts & Polls

### SetDraft

```go
func (d *DeltaChatCore) SetDraft(chatID string, msg *OutgoingMessage) error
```

Saves a draft message for a chat.

### GetDraft

```go
func (d *DeltaChatCore) GetDraft(chatID string) (*OutgoingMessage, error)
```

Returns the saved draft for a chat.

### SendDraft

```go
func (d *DeltaChatCore) SendDraft(chatID string) (*Message, error)
```

Sends and removes the saved draft for a chat.

### RemoveDraft

```go
func (d *DeltaChatCore) RemoveDraft(chatID string)
```

Removes a draft without sending.

### CreatePoll

```go
func (d *DeltaChatCore) CreatePoll(chatID string, question string, options []string) (*Message, error)
```

Sends a poll as a formatted text message with numbered options.

### VotePoll

```go
func (d *DeltaChatCore) VotePoll(chatID string, msgID string, optionIndex int) error
```

Casts a vote on a poll by sending a reply message with the option text.

---

## Ephemeral Messages

### SetEphemeralTimer

```go
func (d *DeltaChatCore) SetEphemeralTimer(chatID string, seconds int) error
```

Sets the disappearing messages timer for a chat. Sends an `Ephemeral-Timer` header email to notify other members. 0 disables.

### GetEphemeralTimer

```go
func (d *DeltaChatCore) GetEphemeralTimer(chatID string) (int, error)
```

Returns the current ephemeral timer in seconds for a chat.

### EstimateAutoDeletionCount

```go
func (d *DeltaChatCore) EstimateAutoDeletionCount(chatID string, seconds int) (int, error)
```

Estimates how many messages would be deleted if the ephemeral timer were set to the given seconds.

---

## Webxdc Apps

Webxdc is Delta Chat's mini-app platform. Apps are distributed as `.xdc` ZIP files and communicate via status updates.

### SendWebxdcStatusUpdate

```go
func (d *DeltaChatCore) SendWebxdcStatusUpdate(chatID, msgID string, payload json.RawMessage, info string) error
```

Sends a status update for a webxdc app instance. Delivered to all chat members via email with `Chat-Content: webxdc-status-update`.

```go
err := dc.SendWebxdcStatusUpdate("grp:abc", msgID, json.RawMessage(`{"score": 100}`), "New high score!")
```

### GetWebxdcStatusUpdates

```go
func (d *DeltaChatCore) GetWebxdcStatusUpdates(msgID string, lastKnownSerial int) ([]DCWebxdcUpdate, error)
```

Returns status updates since the given serial number.

### GetWebxdcInfo

```go
func (d *DeltaChatCore) GetWebxdcInfo(chatID, msgID string) (*DeltaChatWebxdcInfo, error)
```

Parses the `manifest.toml` from a `.xdc` ZIP attachment to extract app metadata.

### GetWebxdcBlob

```go
func (d *DeltaChatCore) GetWebxdcBlob(chatID, msgID, blobName string) ([]byte, string, error)
```

Extracts a named file from a `.xdc` ZIP attachment. Returns file data, MIME type, and error.

### SetWebxdcIntegration

```go
func (d *DeltaChatCore) SetWebxdcIntegration(msgID string) error
```

Registers a webxdc app as the integration provider (e.g., maps integration).

### InitWebxdcIntegration

```go
func (d *DeltaChatCore) InitWebxdcIntegration(filter string) (string, error)
```

Returns the message ID of the configured integration webxdc, or error if none set.

### SendWebxdcRealtimeData

```go
func (d *DeltaChatCore) SendWebxdcRealtimeData(chatID, msgID string, data []byte) error
```

Sends real-time data for a webxdc app via email (non-P2P fallback). Data is base64-encoded.

### SendWebxdcRealtimeAdvertisement

```go
func (d *DeltaChatCore) SendWebxdcRealtimeAdvertisement(chatID, msgID string) error
```

Advertises P2P availability for a webxdc app by sending a notification email to chat members.

### LeaveWebxdcRealtime

```go
func (d *DeltaChatCore) LeaveWebxdcRealtime(chatID, msgID string) error
```

Leaves the real-time channel for a webxdc app by sending a `webxdc-realtime-leave` email.

---

## Location Sharing

### StartLocationStreaming

```go
func (d *DeltaChatCore) StartLocationStreaming(chatID string, seconds int) error
```

Starts streaming location to a chat for the specified duration. Sends periodic location emails.

### StopLocationStreaming

```go
func (d *DeltaChatCore) StopLocationStreaming(chatID string) error
```

Stops active location streaming for a chat.

### SendLocation

```go
func (d *DeltaChatCore) SendLocation(chatID string, lat float64, lon float64) (*Message, error)
```

Sends a single point-of-interest location message.

### GetLocations

```go
func (d *DeltaChatCore) GetLocations(chatID, contactEmail string, fromTime, toTime int64) ([]DCLocation, error)
```

Retrieves stored location history. Filter by chat, contact, and time range. Pass empty/0 to skip filters.

```go
locs, err := dc.GetLocations("grp:abc", "friend@example.com", 0, 0)
```

### IsLocationStreaming

```go
func (d *DeltaChatCore) IsLocationStreaming(chatID string) bool
```

Returns true if location streaming is active for a chat.

### IsSendingLocationsToChat

```go
func (d *DeltaChatCore) IsSendingLocationsToChat(chatID string) bool
```

Same as `IsLocationStreaming` -- returns true if actively sending locations to a chat.

### DeleteAllLocations

```go
func (d *DeltaChatCore) DeleteAllLocations()
```

Deletes all stored location history.

---

## vCard Import/Export

### ImportVCard

```go
func (d *DeltaChatCore) ImportVCard(vcard string) ([]User, error)
```

Parses a vCard string and adds contacts. Returns the imported contacts.

### MakeVCard

```go
func (d *DeltaChatCore) MakeVCard(emails []string) (string, error)
```

Generates a vCard 3.0 string for the given contact emails.

```go
vcard, err := dc.MakeVCard([]string{"alice@example.com", "bob@example.com"})
```

---

## HTML Messages

### SendHTML

```go
func (d *DeltaChatCore) SendHTML(chatID string, html string, plaintext string) (*Message, error)
```

Sends a multipart/alternative email with HTML and plaintext parts. Encrypts with PGP/MIME when peer keys are available.

### GetMessageHTML

```go
func (d *DeltaChatCore) GetMessageHTML(chatID, msgID string) (string, error)
```

Returns the HTML version of a received message. Falls back to wrapping plain text in basic HTML.

---

## Autocrypt & Keys

### GetEncryptionInfo

```go
func (d *DeltaChatCore) GetEncryptionInfo(chatID string) (string, error)
```

Returns a human-readable encryption status for a chat, including protection state and per-member key info.

### SetPeerPublicKey

```go
func (d *DeltaChatCore) SetPeerPublicKey(email string, pubKeyBytes []byte) error
```

Injects a peer's public key for testing or chatmail interop. Accepts both ASCII-armored and raw binary OpenPGP keys.

```go
keyData, _ := os.ReadFile("peer-public-key.asc")
err := dc.SetPeerPublicKey("friend@example.com", keyData)
```

### ExportSelfKeys

```go
func (d *DeltaChatCore) ExportSelfKeys(dir string) error
```

Exports PGP keys (public + private) as armored ASCII `.asc` files to the given directory.

### ImportSelfKeys

```go
func (d *DeltaChatCore) ImportSelfKeys(dir string) error
```

Imports PGP keys from armored ASCII files matching `*private-key*.asc` in the given directory.

### PreconfigureKeypair

```go
func (d *DeltaChatCore) PreconfigureKeypair(addr, publicKey, privateKey string) error
```

Sets up PGP keys without Autocrypt negotiation. Both keys should be ASCII-armored. If `addr` differs from the authenticated address, the public key is also stored as a peer key.

---

## Key Transfer

### InitiateKeyTransfer

```go
func (d *DeltaChatCore) InitiateKeyTransfer() (string, error)
```

Creates an Autocrypt Setup Message and sends it to self. Returns a 44-digit setup code (9 groups of 4 digits separated by dashes) that the receiving device needs to enter.

```go
setupCode, err := dc.InitiateKeyTransfer()
// setupCode looks like: "1234-5678-9012-3456-7890-1234-5678-9012-3456"
```

### ContinueKeyTransfer

```go
func (d *DeltaChatCore) ContinueKeyTransfer(msgID, setupCode string) error
```

Decrypts an Autocrypt Setup Message using the setup code and imports the private key. The `msgID` references the setup message received via email.

---

## SecureJoin & QR Codes

### CheckQR

```go
func (d *DeltaChatCore) CheckQR(qr string) (map[string]string, error)
```

Parses a Delta Chat QR code (`https://i.delta.chat/#...`) and returns the parsed fields (fingerprint, address, group ID, etc.).

### SecureJoin

```go
func (d *DeltaChatCore) SecureJoin(qrData string) (*Dialog, error)
```

Joins a verified group or verifies a contact via scanned QR code data. Sends Secure-Join protocol messages.

```go
dlg, err := dc.SecureJoin("https://i.delta.chat/#FINGERPRINT&a=friend@example.com&g=GroupName&x=groupid")
```

### GetSecureJoinQR

```go
func (d *DeltaChatCore) GetSecureJoinQR(chatID string) (string, error)
```

Generates an OPENPGP4FPR QR code data string for verifying your identity or inviting to a group.

### GetSecureJoinQRSvg

```go
func (d *DeltaChatCore) GetSecureJoinQRSvg(chatID string) (string, error)
```

Returns an SVG representation of the SecureJoin QR code.

### CreateQRSvg

```go
func (d *DeltaChatCore) CreateQRSvg(data string) string
```

Generates a minimal SVG QR code representation from arbitrary data.

### SetConfigFromQR

```go
func (d *DeltaChatCore) SetConfigFromQR(qrData string) error
```

Applies a DCLOGIN QR code (`DCLOGIN:user:pass@host`) to configuration.

---

## Backup & Export

### ExportBackup

```go
func (d *DeltaChatCore) ExportBackup(path string) error
```

Exports a backup of the session data to the specified file path.

### ImportBackup

```go
func (d *DeltaChatCore) ImportBackup(path string) error
```

Imports a backup from the specified file path and restores state.

### ProvideBackup

```go
func (d *DeltaChatCore) ProvideBackup() (string, error)
```

Returns the session file path (alias for `GetBackup`).

### GetBackup

```go
func (d *DeltaChatCore) GetBackup() (string, error)
```

Returns the session file path.

### GetBackupQR

```go
func (d *DeltaChatCore) GetBackupQR() (string, error)
```

Returns a `DCBACKUP:` QR code data string for the current session.

### GetBackupQRSvg

```go
func (d *DeltaChatCore) GetBackupQRSvg() (string, error)
```

Returns an SVG of the backup QR code.

### ReceiveBackup

```go
func (d *DeltaChatCore) ReceiveBackup(qrData string) error
```

Restores from a backup QR code. Currently returns an error (not fully implemented in pure Go client).

---

## Configuration

### SetConfig

```go
func (d *DeltaChatCore) SetConfig(key, value string)
```

Sets a configuration key-value pair.

### GetConfig

```go
func (d *DeltaChatCore) GetConfig(key string) string
```

Gets a configuration value by key.

### BatchSetConfig

```go
func (d *DeltaChatCore) BatchSetConfig(kv map[string]string)
```

Sets multiple configuration keys atomically.

### BatchGetConfig

```go
func (d *DeltaChatCore) BatchGetConfig(keys []string) map[string]string
```

Gets multiple configuration values at once.

### SetShowEmails

```go
func (d *DeltaChatCore) SetShowEmails(mode int) error
```

Controls display of non-Delta-Chat classical emails. 0=Off (only DC messages), 1=Accepted contacts, 2=All.

### SetDownloadLimit

```go
func (d *DeltaChatCore) SetDownloadLimit(limitBytes int64) error
```

Sets the maximum auto-download size in bytes. Messages larger than this are partially downloaded (headers + text only). 0=unlimited.

### SetCallFilter

```go
func (d *DeltaChatCore) SetCallFilter(mode int) error
```

Controls who can initiate calls. 0=Everybody, 1=Contacts only, 2=Nobody.

### CheckEmailValidity

```go
func (d *DeltaChatCore) CheckEmailValidity(email string) bool
```

Validates an email address format (contains `@` and `.`).

---

## Multi-Account

### AddAccount

```go
func (d *DeltaChatCore) AddAccount(addr, password string) (string, error)
```

Creates a new account in the account manager. Returns the account ID.

### RemoveAccount

```go
func (d *DeltaChatCore) RemoveAccount(accountID string) error
```

Removes an account by ID.

### SelectAccount

```go
func (d *DeltaChatCore) SelectAccount(accountID string) error
```

Switches the active account. Updates the email address and password used for IMAP/SMTP.

### GetAllAccountIds

```go
func (d *DeltaChatCore) GetAllAccountIds() []string
```

Returns all account IDs.

### StartIoForAllAccounts

```go
func (d *DeltaChatCore) StartIoForAllAccounts() error
```

Starts IMAP/SMTP I/O for all accounts. Delegates to `StartIo`.

### StopIoForAllAccounts

```go
func (d *DeltaChatCore) StopIoForAllAccounts() error
```

Stops I/O for all accounts. Delegates to `StopIo`.

### StartIo

```go
func (d *DeltaChatCore) StartIo() error
```

Explicitly starts IMAP/SMTP I/O. Returns error if not authenticated.

### StopIo

```go
func (d *DeltaChatCore) StopIo() error
```

Stops IMAP/SMTP I/O by cancelling the context.

---

## Transports

Transports provide multi-account email support within a single DeltaChatCore instance.

### AddTransport

```go
func (d *DeltaChatCore) AddTransport(email, password, imapHost, smtpHost string) (string, error)
```

Adds an additional email transport. Auto-discovers servers if hosts are empty. Verifies connectivity before adding. Returns the transport ID.

```go
id, err := dc.AddTransport("other@example.com", "pass", "", "")
```

### ListTransports

```go
func (d *DeltaChatCore) ListTransports() []*DCTransport
```

Returns all configured email transports.

### DeleteTransport

```go
func (d *DeltaChatCore) DeleteTransport(id string) error
```

Removes an email transport by ID.

---

## I/O & Network Control

### SyncNow

```go
func (d *DeltaChatCore) SyncNow() error
```

Forces an IMAP sync, fetching new messages from INBOX and DeltaChat folders.

### MaybeNetwork

```go
func (d *DeltaChatCore) MaybeNetwork()
```

Hints that network is available. Tests IDLE connections with NOOP and triggers reconnection if dead.

### StopOngoingProcess

```go
func (d *DeltaChatCore) StopOngoingProcess() error
```

Cancels any ongoing long-running operation.

### BackgroundFetch

```go
func (d *DeltaChatCore) BackgroundFetch() error
```

One-shot background fetch for new emails.

### StopBackgroundFetch

```go
func (d *DeltaChatCore) StopBackgroundFetch() error
```

Stops background fetch (no-op in current implementation).

---

## Account Management

### DeactivateAccount

```go
func (d *DeltaChatCore) DeactivateAccount() error
```

Requests account deletion from the email provider. For chatmail servers, sends a `Chat-Content: delete-request` email to self.

### ChangePassphrase

```go
func (d *DeltaChatCore) ChangePassphrase(oldPass, newPass string) error
```

Changes the IMAP/SMTP password. Verifies the new password works by test-connecting before updating.

### GetAccountFileSize

```go
func (d *DeltaChatCore) GetAccountFileSize() (int64, error)
```

Returns the size in bytes of the session file on disk.

### GetStorageUsageReport

```go
func (d *DeltaChatCore) GetStorageUsageReport() (*DeltaChatStorageReport, error)
```

Returns a breakdown of local storage usage: session size, message count, chat count, contact count, and sticker storage.

---

## Provider Database

### GetProviderInfo

```go
func (d *DeltaChatCore) GetProviderInfo(email string) (*DeltaChatProviderInfo, error)
```

Returns auto-config information for an email provider. Uses DNS SRV records for server discovery with fallback to well-known ports.

```go
info, err := dc.GetProviderInfo("user@gmail.com")
fmt.Printf("IMAP: %s:%d, SMTP: %s:%d\n", info.IMAPHost, info.IMAPPort, info.SMTPHost, info.SMTPPort)
```

---

## Push Notifications

### SetPushDeviceToken

```go
func (d *DeltaChatCore) SetPushDeviceToken(token string) error
```

Stores the push notification device token. Sets push state to `"Heartbeat"` when token is present.

### GetPushState

```go
func (d *DeltaChatCore) GetPushState() string
```

Returns the current push notification state: `"NotConfigured"`, `"Heartbeat"`, or `"Connected"`.

---

## Device Messages

### AddDeviceMessage

```go
func (d *DeltaChatCore) AddDeviceMessage(label, text string) error
```

Adds a local-only system message to the device-messages chat. These are never sent over email. The label ensures the same message is not shown twice.

```go
dc.AddDeviceMessage("welcome", "Welcome to Delta Chat!")
```

### WasDeviceMsgEverAdded

```go
func (d *DeltaChatCore) WasDeviceMsgEverAdded(label string) bool
```

Returns true if a device message with this label was already shown.

---

## Sessions

### GetSessions

```go
func (d *DeltaChatCore) GetSessions() ([]Session, error)
```

Returns the current session info.

### TerminateSession

```go
func (d *DeltaChatCore) TerminateSession(sessionID string) error
```

Terminates a session (logs out and removes session data).

---

## Read Receipts

### GetReadReceiptCount

```go
func (d *DeltaChatCore) GetReadReceiptCount(chatID, msgID string) int
```

Returns the number of read receipts for a message (0 or 1).

### GetReadReceipts

```go
func (d *DeltaChatCore) GetReadReceipts(chatID, msgID string) []string
```

Returns a list of email addresses that sent read receipts for this message.

---

## OAuth2

### GetOAuth2URL

```go
func (d *DeltaChatCore) GetOAuth2URL(addr, redirectURI string) (string, error)
```

Returns the OAuth2 authorization URL for supported providers (Gmail, Yandex). Returns error for unsupported providers.

---

## Connectivity & System Info

### GetConnectivity

```go
func (d *DeltaChatCore) GetConnectivity() (string, error)
```

Returns a human-readable connectivity status.

### GetConnectivityHtml

```go
func (d *DeltaChatCore) GetConnectivityHtml() string
```

Returns an HTML page showing connection status, IMAP host, and SMTP host.

### GetContextInfo

```go
func (d *DeltaChatCore) GetContextInfo() map[string]string
```

Returns context info: email address, display name, configured state, and PGP fingerprint.

### GetSystemInfo

```go
func (d *DeltaChatCore) GetSystemInfo() map[string]string
```

Returns system-level info: architecture, OS, and version string.

### GetBlobDir

```go
func (d *DeltaChatCore) GetBlobDir() string
```

Returns the blob directory path (adjacent to the session file).

### GetQuota

```go
func (d *DeltaChatCore) GetQuota() (*DeltaChatQuotaInfo, error)
```

Checks IMAP mailbox quota usage. Returns current message count and limit (limit requires QUOTA extension support).

---

## Stock Strings

### SetStockStrings

```go
func (d *DeltaChatCore) SetStockStrings(strings map[int]string)
```

Sets localized UI strings for system messages (e.g., "Member added", "Group created").

---

## Event Handlers

### OnUpdate

```go
func (d *DeltaChatCore) OnUpdate(handler func(Update))
```

Registers a callback for all events: new messages, message edits, connectivity changes, call events, etc. Multiple handlers can be registered.

---

## Convenience Wrappers

These methods delegate to other methods for API consistency.

### MuteChat

```go
func (d *DeltaChatCore) MuteChat(chatID string, muted bool) error
```

Mutes (forever) or unmutes a chat. Delegates to `SetChatMuted`.

### ArchiveChat

```go
func (d *DeltaChatCore) ArchiveChat(chatID string, archived bool) error
```

Archives or unarchives a chat. Delegates to `SetChatVisibility`.

### MarkUnread

```go
func (d *DeltaChatCore) MarkUnread(chatID string, unread bool) error
```

Marks a chat as unread or read. Delegates to `MarkFreshChat`/`MarkNoticedChat`.

### GetSimilarChats

```go
func (d *DeltaChatCore) GetSimilarChats(chatID string) ([]string, error)
```

Finds chats with similar member sets using Jaccard similarity (threshold > 0.5). Useful for merge/dedup suggestions.

### CreateBroadcastList

```go
func (d *DeltaChatCore) CreateBroadcastList(name string) (string, error)
```

Creates a broadcast channel. Delegates to `CreateChannel`.

---

## How It Works

Delta Chat treats email as a chat transport:
- **DM**: Direct email to a contact (chat ID: `dm:email@example.com`)
- **Group**: Email thread with multiple recipients using `Chat-Group-ID` headers (chat ID: `grp:GROUP_ID`)
- **Channels**: Broadcast lists / mailing lists
- **E2EE**: Autocrypt headers in emails carry public keys; messages encrypted with OpenPGP (PGP/MIME)
- **Calls**: WebRTC with SDP exchanged via email
- **Webxdc**: Mini-apps as `.xdc` ZIP files with status updates via email

No Delta Chat server needed -- works with Gmail, Outlook, Fastmail, or any IMAP/SMTP provider.

## Dependencies

- Standard library only (net, crypto, encoding)
- `emersion/go-imap/v2` + `emersion/go-message` for IMAP/MIME
- `ProtonMail/go-crypto` for OpenPGP
- `pion/webrtc` for calls
- No CGo required
