# XMPP Core — API Reference

Pure Go XMPP client implementing RFC 6120 (Core) and RFC 6121 (IM) plus 30+ XEP extensions. Connects to any Jabber/XMPP server. No CGo, no external dependencies — stdlib only (net, crypto/tls, encoding/xml).

**379 exported methods** across connection, messaging, presence, roster, MUC, MIX, PubSub, service discovery, Jingle calls, file transfer, MAM, vCards, OMEMO, blocking, bookmarks, registration, ad-hoc commands, and more.

## Table of Contents

- [Setup](#setup)
- [Types](#types)
- [Connection & Authentication](#connection--authentication)
- [Core Interface — Dialogs & Chat Management](#core-interface--dialogs--chat-management)
- [Core Interface — Messaging](#core-interface--messaging)
- [Core Interface — Read State](#core-interface--read-state)
- [Core Interface — Files](#core-interface--files)
- [Core Interface — Calls](#core-interface--calls)
- [Core Interface — Profile](#core-interface--profile)
- [Core Interface — Members](#core-interface--members)
- [Core Interface — Contacts](#core-interface--contacts)
- [Core Interface — Blocking](#core-interface--blocking)
- [Core Interface — Search](#core-interface--search)
- [Core Interface — Typing & Polls & Stickers](#core-interface--typing--polls--stickers)
- [Core Interface — Sessions](#core-interface--sessions)
- [Core Interface — Events & Lifecycle](#core-interface--events--lifecycle)
- [Presence Management](#presence-management)
- [Roster (Contacts)](#roster-contacts)
- [Chat States (XEP-0085)](#chat-states-xep-0085)
- [Message Operations](#message-operations)
- [MUC — Multi-User Chat (XEP-0045)](#muc--multi-user-chat-xep-0045)
- [MIX — Modern MUC (XEP-0369)](#mix--modern-muc-xep-0369)
- [Service Discovery (XEP-0030)](#service-discovery-xep-0030)
- [PubSub (XEP-0060) & PEP (XEP-0163)](#pubsub-xep-0060--pep-xep-0163)
- [PubSub Extended](#pubsub-extended)
- [File Transfer — HTTP Upload (XEP-0363)](#file-transfer--http-upload-xep-0363)
- [File Transfer — In-Band Bytestreams (XEP-0047)](#file-transfer--in-band-bytestreams-xep-0047)
- [File Transfer — SOCKS5 Bytestreams (XEP-0065)](#file-transfer--socks5-bytestreams-xep-0065)
- [File Transfer — Stateless File Sharing (XEP-0447)](#file-transfer--stateless-file-sharing-xep-0447)
- [File Transfer — Encrypted & Media](#file-transfer--encrypted--media)
- [Bookmarks (XEP-0048 / XEP-0402)](#bookmarks-xep-0048--xep-0402)
- [MAM — Message Archive Management (XEP-0313)](#mam--message-archive-management-xep-0313)
- [vCards (XEP-0054 / XEP-0292)](#vcards-xep-0054--xep-0292)
- [OMEMO / Encryption (XEP-0384)](#omemo--encryption-xep-0384)
- [OpenPGP for XMPP (XEP-0373/0374)](#openpgp-for-xmpp-xep-03730374)
- [Stanza Content Encryption (XEP-0420)](#stanza-content-encryption-xep-0420)
- [Trust Messages (XEP-0434)](#trust-messages-xep-0434)
- [Explicit Message Encryption (XEP-0380)](#explicit-message-encryption-xep-0380)
- [User Blocking (XEP-0191)](#user-blocking-xep-0191)
- [Privacy Lists (XEP-0016)](#privacy-lists-xep-0016)
- [Ping / Last Activity / Entity Time](#ping--last-activity--entity-time)
- [Client State Indication (XEP-0352)](#client-state-indication-xep-0352)
- [Entity Capabilities](#entity-capabilities)
- [Stream Management (XEP-0198)](#stream-management-xep-0198)
- [Registration (XEP-0077)](#registration-xep-0077)
- [Ad-Hoc Commands (XEP-0050)](#ad-hoc-commands-xep-0050)
- [Data Forms (XEP-0004)](#data-forms-xep-0004)
- [Private XML Storage (XEP-0049)](#private-xml-storage-xep-0049)
- [Offline Messages (XEP-0013)](#offline-messages-xep-0013)
- [Push Notifications (XEP-0357)](#push-notifications-xep-0357)
- [Jingle — Calls (XEP-0166)](#jingle--calls-xep-0166)
- [Jingle Message Initiation (XEP-0353)](#jingle-message-initiation-xep-0353)
- [Jingle Extended Actions](#jingle-extended-actions)
- [Jingle File Transfer (XEP-0234)](#jingle-file-transfer-xep-0234)
- [Jingle RTP / Codecs / Media](#jingle-rtp--codecs--media)
- [Jingle Transport Variants](#jingle-transport-variants)
- [Jingle Encryption & Advanced](#jingle-encryption--advanced)
- [Alternative Connections (XEP-0156)](#alternative-connections-xep-0156)
- [SASL2 / Bind2 / FAST](#sasl2--bind2--fast)
- [Advanced Messaging Extensions](#advanced-messaging-extensions)
- [MUC Extensions](#muc-extensions)
- [User Profile & Social](#user-profile--social)
- [Notification & Sync](#notification--sync)
- [Server Interaction](#server-interaction)
- [Newer / Experimental](#newer--experimental)
- [Result Set Management (XEP-0059)](#result-set-management-xep-0059)
- [Miscellaneous Utilities](#miscellaneous-utilities)
- [Unsupported Core Methods](#unsupported-core-methods)

---

## Setup

```go
import "uniclient/cores"

xmpp := cores.NewXMPPCore("./sessions/xmpp.json")
```

**Capabilities:** `TEXT`, `CHANNELS`, `CALLS`, `REACTIONS`, `READ_RECEIPTS`, `TYPING`, `BLOCKING`, `SEARCH`, `PRESENCE`, `E2EE`, `FILE_TRANSFER`

**Chat IDs:**
- `"user@domain"` -- DM (bare JID)
- `"room@conference.domain"` -- MUC room (group)

---

## Types

### XMPPIQ

```go
type XMPPIQ struct {
    XMLName xml.Name         `xml:"iq"`
    Type    string           `xml:"type,attr"`
    ID      string           `xml:"id,attr,omitempty"`
    To      string           `xml:"to,attr,omitempty"`
    From    string           `xml:"from,attr,omitempty"`
    Lang    string           `xml:"xml:lang,attr,omitempty"`
    Inner   string           `xml:",innerxml"`
    Error   *XMPPStanzaError `xml:"error"`
}
```

Generic IQ stanza. Returned by many methods for raw protocol responses.

### XMPPStanzaError

```go
type XMPPStanzaError struct {
    Type  string `xml:"type,attr,omitempty"`
    Code  string `xml:"code,attr,omitempty"`
    Text  string `xml:"text,omitempty"`
    Inner string `xml:",innerxml"`
}
```

### xmppRosterItem

```go
type xmppRosterItem struct {
    JID          string   `xml:"jid,attr"`
    Name         string   `xml:"name,attr,omitempty"`
    Subscription string   `xml:"subscription,attr,omitempty"`
    Groups       []string `xml:"group"`
    Ask          string   `xml:"ask,attr,omitempty"`
}
```

Returned by `GetRoster()`.

### xmppBookmark

```go
type xmppBookmark struct {
    JID      string `json:"jid"`
    Name     string `json:"name,omitempty"`
    Nick     string `json:"nick,omitempty"`
    AutoJoin bool   `json:"autojoin,omitempty"`
}
```

Returned by `GetBookmarks()`.

### XMPPCore

```go
type XMPPCore struct { /* ... */ }
```

Main struct implementing the `Core` interface. Create with `NewXMPPCore(sessionPath)`.

### Constants

```go
const XMPPIQTimeout = 30 * time.Second
```

---

## Connection & Authentication

### Name

```go
func (c *XMPPCore) Name() string
```

Returns `"xmpp"`.

### Capabilities

```go
func (c *XMPPCore) Capabilities() []string
```

Returns all supported capability strings.

### Authenticate

```go
func (c *XMPPCore) Authenticate(cfg AuthConfig) error
```

Connects to an XMPP server, negotiates STARTTLS (or direct TLS), authenticates via SASL, binds a resource, and starts the read loop.

**AuthConfig.Extra keys:**
- `"jid"` -- bare JID, e.g. `"user@example.com"` (required)
- `"password"` -- account password (required)
- `"server"` -- `host:port` (default: derived from JID domain + `:5222`)
- `"resource"` -- XMPP resource (default: `"uniclient"`)
- `"tls"` -- `"starttls"` (default), `"direct"` (port 5223), or `"none"`
- `"mechanism"` -- `"plain"`, `"scram-sha-1"`, `"scram-sha-256"` (default: best available)
- `"muc_service"` -- MUC service domain (auto-discovered if empty)
- `"upload_service"` -- HTTP upload service JID (auto-discovered if empty)

```go
err := xmpp.Authenticate(cores.AuthConfig{
    Extra: map[string]string{
        "jid":      "alice@conversations.im",
        "password": "secret",
        "server":   "conversations.im:5222",
    },
})
```

### Logout

```go
func (c *XMPPCore) Logout() error
```

Sends unavailable presence, closes the XML stream, and saves the session. Does not delete session data.

### Close

```go
func (c *XMPPCore) Close() error
```

Full shutdown: closes the stream, waits for goroutines, saves session, sets authed=false.

---

## Core Interface -- Dialogs & Chat Management

### GetDialogs

```go
func (c *XMPPCore) GetDialogs(opts PaginationOpts) ([]Dialog, error)
```

Returns all roster contacts as DM dialogs and all joined MUC rooms as group dialogs. Supports `Offset` and `Limit` pagination.

### CreateGroup

```go
func (c *XMPPCore) CreateGroup(name string, members []string) (*Dialog, error)
```

Creates a MUC room, configures it as persistent, and invites the listed members.

```go
d, err := xmpp.CreateGroup("dev-team", []string{"bob@example.com", "carol@example.com"})
```

### CreateChannel

```go
func (c *XMPPCore) CreateChannel(name string, description string) (*Dialog, error)
```

Creates a MUC room (XMPP doesn't distinguish channels from groups). Sets description if provided.

### CreateTopic

```go
func (c *XMPPCore) CreateTopic(chatID string, name string) (*Dialog, error)
```

Not supported (XMPP has no forum topics). Returns `ErrNotSupported`.

### GetFolders

```go
func (c *XMPPCore) GetFolders() ([]Folder, error)
```

Returns bookmarked rooms as a single "Bookmarks" folder.

### CreateFolder

```go
func (c *XMPPCore) CreateFolder(name string, chatIDs []string) (*Folder, error)
```

Saves the given chat IDs as bookmarks.

### GetChatInfo

```go
func (c *XMPPCore) GetChatInfo(chatID string) (*Dialog, error)
```

Returns info for a chat. For MUC rooms, queries disco#info. For DMs, returns roster info.

### EditChatTitle

```go
func (c *XMPPCore) EditChatTitle(chatID string, title string) error
```

Sets the MUC room subject. Only works for rooms; returns `ErrNotSupported` for DMs.

### EditChatDescription

```go
func (c *XMPPCore) EditChatDescription(chatID string, description string) error
```

Configures the `muc#roomconfig_roomdesc` field. Only works for rooms.

### LeaveChat

```go
func (c *XMPPCore) LeaveChat(chatID string) error
```

Leaves a MUC room or removes a JID from the roster.

### GetInviteLink

```go
func (c *XMPPCore) GetInviteLink(chatID string) (string, error)
```

Returns an `xmpp:room@conference.example.com?join` URI.

---

## Core Interface -- Messaging

### SendMessage

```go
func (c *XMPPCore) SendMessage(chatID string, msg OutgoingMessage) (*Message, error)
```

Sends a text message. Automatically detects chat vs groupchat type. Includes delivery receipt request, active chat state, reply reference (if `msg.ReplyToID` is set), and MAM storage hint.

```go
msg, err := xmpp.SendMessage("alice@example.com", cores.OutgoingMessage{Text: "Hello!"})
```

### GetMessages

```go
func (c *XMPPCore) GetMessages(chatID string, opts PaginationOpts) ([]Message, error)
```

Tries MAM archive first (when offset/limit specified), falls back to local message buffer.

### EditMessage

```go
func (c *XMPPCore) EditMessage(chatID string, msgID string, text string) (*Message, error)
```

Sends a message correction (XEP-0308). The new message includes `<replace>` referencing the original.

### DeleteMessage

```go
func (c *XMPPCore) DeleteMessage(chatID string, msgID string) error
```

Removes the message from the local buffer. XMPP lacks a standard deletion command; use `RetractMessage()` for XEP-0424 retraction.

### ReplyToMessage

```go
func (c *XMPPCore) ReplyToMessage(chatID string, replyToMsgID string, msg OutgoingMessage) (*Message, error)
```

Sends a message with XEP-0461 reply reference.

### ForwardMessage

```go
func (c *XMPPCore) ForwardMessage(fromChatID string, msgID string, toChatID string) (*Message, error)
```

Finds the original message in the local buffer and sends it to the target chat with a `[Forwarded from ...]` prefix.

### ReactToMessage

```go
func (c *XMPPCore) ReactToMessage(chatID string, msgID string, emoji string) error
```

Sends a reaction via XEP-0444. Delegates to `SendReaction()`.

### PinMessage

```go
func (c *XMPPCore) PinMessage(chatID string, msgID string) error
```

Pins a message locally (XMPP has no server-side pin concept). Persisted in session.

### UnpinMessage

```go
func (c *XMPPCore) UnpinMessage(chatID string, msgID string) error
```

Removes a local pin.

---

## Core Interface -- Read State

### MarkAsRead

```go
func (c *XMPPCore) MarkAsRead(chatID string, upToMsgID string) error
```

Updates local read state and sends a XEP-0333 displayed marker.

### GetReadState

```go
func (c *XMPPCore) GetReadState(chatID string) (*ReadState, error)
```

Returns the local read state for a chat.

---

## Core Interface -- Files

### UploadFile

```go
func (c *XMPPCore) UploadFile(chatID string, file FileUpload, progress func(sent, total int64)) (*Message, error)
```

Uploads via XEP-0363 HTTP File Upload: requests a slot, uploads via HTTP PUT, then sends an OOB URL message.

```go
f, _ := os.Open("report.pdf")
msg, err := xmpp.UploadFile("room@conf.example.com", cores.FileUpload{
    Name:     "report.pdf",
    Size:     1024000,
    MimeType: "application/pdf",
    Reader:   f,
}, nil)
```

### DownloadFile

```go
func (c *XMPPCore) DownloadFile(fileRef FileRef, dest string, progress func(recv, total int64)) error
```

Downloads a file from its URL (from `FileRef.URL`) to a local path.

### SendImageBase64

```go
func (c *XMPPCore) SendImageBase64(chatID string, b64 string, caption string) (*Message, error)
```

Decodes a base64 image, uploads via HTTP Upload, and sends the URL. Falls back to a text message if upload service is unavailable.

---

## Core Interface -- Calls

### StartCall

```go
func (c *XMPPCore) StartCall(chatID string, video bool) (*CallSession, error)
```

Initiates a Jingle session (XEP-0166) with the target JID. Delegates to `InitiateJingle()`.

### JoinGroupCall

```go
func (c *XMPPCore) JoinGroupCall(chatID string) (*CallSession, error)
```

Not widely supported (Muji/XEP-0272). Returns `ErrNotSupported`.

### EndCall

```go
func (c *XMPPCore) EndCall(callID string) error
```

Terminates a Jingle session with reason "success".

### SetCallMuted

```go
func (c *XMPPCore) SetCallMuted(callID string, muted bool) error
```

Not supported. Returns `ErrNotSupported`.

---

## Core Interface -- Profile

### GetProfile

```go
func (c *XMPPCore) GetProfile(userID string) (*User, error)
```

Fetches vCard data for a JID. Falls back to roster info if vCard is unavailable. Pass `""` for own profile.

---

## Core Interface -- Members

### AddMembers

```go
func (c *XMPPCore) AddMembers(chatID string, userIDs []string) error
```

Sends MUC invitations to each user. Only works for MUC rooms.

### RemoveMember

```go
func (c *XMPPCore) RemoveMember(chatID string, userID string) error
```

Kicks a user from a MUC room (sets role to "none").

### BanMember

```go
func (c *XMPPCore) BanMember(chatID string, userID string) error
```

Sets the user's affiliation to "outcast" in a MUC room.

### UnbanMember

```go
func (c *XMPPCore) UnbanMember(chatID string, userID string) error
```

Sets the user's affiliation back to "none".

### GetMembers

```go
func (c *XMPPCore) GetMembers(chatID string, opts PaginationOpts) ([]User, error)
```

Returns MUC occupants for rooms, or both parties for DMs.

### SetAdmin

```go
func (c *XMPPCore) SetAdmin(chatID string, userID string, admin bool) error
```

Sets the user's affiliation to "admin" (or "member" to revoke) in a MUC room.

---

## Core Interface -- Contacts

### GetContacts

```go
func (c *XMPPCore) GetContacts() ([]User, error)
```

Returns all roster items (excluding `subscription="remove"`).

### AddContact

```go
func (c *XMPPCore) AddContact(phone string, firstName string, lastName string) error
```

Adds a JID to the roster (the `phone` parameter is used as the JID) and subscribes to their presence.

### DeleteContact

```go
func (c *XMPPCore) DeleteContact(userID string) error
```

Removes a JID from the roster.

---

## Core Interface -- Blocking

### BlockUser

```go
func (c *XMPPCore) BlockUser(userID string) error
```

Blocks a JID via XEP-0191. Delegates to `BlockJID()`.

### UnblockUser

```go
func (c *XMPPCore) UnblockUser(userID string) error
```

Unblocks a JID. Delegates to `UnblockJID()`.

### GetBlockedUsers

```go
func (c *XMPPCore) GetBlockedUsers() ([]User, error)
```

Returns the block list as User objects.

---

## Core Interface -- Search

### SearchMessages

```go
func (c *XMPPCore) SearchMessages(chatID string, query string, opts PaginationOpts) ([]Message, error)
```

Case-insensitive text search across the local message buffer. Pass `""` for chatID to search all chats.

### SearchGlobal

```go
func (c *XMPPCore) SearchGlobal(query string, opts PaginationOpts) ([]Dialog, error)
```

Searches roster contacts and MUC rooms by name/JID.

---

## Core Interface -- Typing & Polls & Stickers

### SendTyping

```go
func (c *XMPPCore) SendTyping(chatID string) error
```

Sends a XEP-0085 "composing" chat state. Delegates to `SendChatStateComposing()`.

### CreatePoll

```go
func (c *XMPPCore) CreatePoll(chatID string, question string, options []string) (*Message, error)
```

Not supported. Returns `ErrNotSupported`.

### VotePoll

```go
func (c *XMPPCore) VotePoll(chatID string, msgID string, optionIndex int) error
```

Not supported. Returns `ErrNotSupported`.

### SendSticker

```go
func (c *XMPPCore) SendSticker(chatID string, stickerID string) (*Message, error)
```

Not supported. Returns `ErrNotSupported`. See `SendStickerXEP()` for XEP-0449 stickers.

---

## Core Interface -- Sessions

### GetSessions

```go
func (c *XMPPCore) GetSessions() ([]Session, error)
```

Returns the current session (XMPP has no standard session listing).

### TerminateSession

```go
func (c *XMPPCore) TerminateSession(sessionID string) error
```

Not supported. Returns `ErrNotSupported`.

---

## Core Interface -- Events & Lifecycle

### OnUpdate

```go
func (c *XMPPCore) OnUpdate(handler func(Update))
```

Registers a callback for real-time updates (messages, presence changes, typing, invitations).

```go
xmpp.OnUpdate(func(u cores.Update) {
    if u.Message != nil {
        fmt.Printf("[%s] %s: %s\n", u.ChatID, u.Message.SenderName, u.Message.Text)
    }
})
```

---

## Presence Management

### SendPresenceAvailable

```go
func (c *XMPPCore) SendPresenceAvailable(show, status string) error
```

Broadcasts available presence. `show` can be `""`, `"chat"`, `"away"`, `"xa"`, or `"dnd"`. `status` is freeform text.

```go
xmpp.SendPresenceAvailable("chat", "Ready to talk")
```

### SendPresenceUnavailable

```go
func (c *XMPPCore) SendPresenceUnavailable(status string) error
```

Broadcasts unavailable presence with an optional status message.

### SetPresencePriority

```go
func (c *XMPPCore) SetPresencePriority(priority int) error
```

Sets the resource priority (affects which resource receives messages).

### SendPresenceSubscribe

```go
func (c *XMPPCore) SendPresenceSubscribe(jid string) error
```

Requests presence subscription from a JID. Part of the contact-adding flow.

### SendPresenceSubscribed

```go
func (c *XMPPCore) SendPresenceSubscribed(jid string) error
```

Approves a presence subscription request.

### SendPresenceUnsubscribe

```go
func (c *XMPPCore) SendPresenceUnsubscribe(jid string) error
```

Unsubscribes from a JID's presence.

### SendPresenceUnsubscribed

```go
func (c *XMPPCore) SendPresenceUnsubscribed(jid string) error
```

Denies or revokes a presence subscription.

### SendDirectedPresence

```go
func (c *XMPPCore) SendDirectedPresence(jid, show, status string) error
```

Sends presence directed to a specific JID (useful for MUC, privacy).

### ProbePresence

```go
func (c *XMPPCore) ProbePresence(jid string) error
```

Sends a presence probe to request a JID's current status.

---

## Roster (Contacts)

### GetRoster

```go
func (c *XMPPCore) GetRoster() ([]xmppRosterItem, error)
```

Returns the cached roster items.

### AddRosterItem

```go
func (c *XMPPCore) AddRosterItem(jid, name string, groups []string) error
```

Adds or updates a roster item and subscribes to the JID's presence.

```go
err := xmpp.AddRosterItem("bob@example.com", "Bob", []string{"Friends", "Work"})
```

### RemoveRosterItem

```go
func (c *XMPPCore) RemoveRosterItem(jid string) error
```

Removes a JID from the roster (sets `subscription='remove'`).

### SetRosterItemName

```go
func (c *XMPPCore) SetRosterItemName(jid, name string) error
```

Updates the display name for a roster item.

### SetRosterItemGroups

```go
func (c *XMPPCore) SetRosterItemGroups(jid string, groups []string) error
```

Sets the group membership for a roster item, preserving the existing name.

---

## Chat States (XEP-0085)

### SendChatStateActive

```go
func (c *XMPPCore) SendChatStateActive(chatID string) error
```

Sends "active" chat state (user is focused on the chat window).

### SendChatStateComposing

```go
func (c *XMPPCore) SendChatStateComposing(chatID string) error
```

Sends "composing" chat state (user is typing).

### SendChatStatePaused

```go
func (c *XMPPCore) SendChatStatePaused(chatID string) error
```

Sends "paused" chat state (user stopped typing).

### SendChatStateInactive

```go
func (c *XMPPCore) SendChatStateInactive(chatID string) error
```

Sends "inactive" chat state (user has not interacted recently).

### SendChatStateGone

```go
func (c *XMPPCore) SendChatStateGone(chatID string) error
```

Sends "gone" chat state (user has left the conversation).

---

## Message Operations

### SendGroupchatMessage

```go
func (c *XMPPCore) SendGroupchatMessage(to, body string) error
```

Sends a `type='groupchat'` message to a MUC room (no receipt request or chat state).

### SendHeadlineMessage

```go
func (c *XMPPCore) SendHeadlineMessage(to, body, subject string) error
```

Sends a `type='headline'` message (server announcements, alerts).

### SendNormalMessage

```go
func (c *XMPPCore) SendNormalMessage(to, body string) error
```

Sends a `type='normal'` message (one-off, not part of a conversation).

### RequestReceipt

```go
func (c *XMPPCore) RequestReceipt(to, msgID string) error
```

Sends a XEP-0184 delivery receipt request for a specific message.

### SendReceipt

```go
func (c *XMPPCore) SendReceipt(to, msgID string) error
```

Sends a XEP-0184 delivery receipt acknowledgment.

### EnableCarbons

```go
func (c *XMPPCore) EnableCarbons() error
```

Enables XEP-0280 message carbons so messages sent/received on other devices are forwarded here.

### DisableCarbons

```go
func (c *XMPPCore) DisableCarbons() error
```

Disables message carbons.

### SendDisplayedMarker

```go
func (c *XMPPCore) SendDisplayedMarker(to, msgID string) error
```

Sends a XEP-0333 "displayed" chat marker (read receipt).

### SendReceivedMarker

```go
func (c *XMPPCore) SendReceivedMarker(to, msgID string) error
```

Sends a XEP-0333 "received" chat marker.

### SendOOBURL

```go
func (c *XMPPCore) SendOOBURL(chatID, url, desc string) error
```

Sends a message with an XEP-0066 out-of-band URL (file link, image, etc.).

### SetMessageHint

```go
func (c *XMPPCore) SetMessageHint(chatID, msgID, hint string) error
```

Not supported (hints can only be set at send time). Returns `ErrNotSupported`.

### SendReaction

```go
func (c *XMPPCore) SendReaction(chatID, msgID string, emojis []string) error
```

Sends XEP-0444 message reactions. Supports multiple emojis.

```go
err := xmpp.SendReaction("alice@example.com", "msg_42", []string{"thumbsup", "heart"})
```

### RetractMessage

```go
func (c *XMPPCore) RetractMessage(to, msgID string) error
```

Sends a XEP-0424 message retraction with a fallback body for clients that don't support it.

### ModerateMessage

```go
func (c *XMPPCore) ModerateMessage(roomJID, stanzaID, reason string) error
```

Retracts another user's message in a MUC room (XEP-0425 message moderation). Requires moderator role.

### SendSpoilerMessage

```go
func (c *XMPPCore) SendSpoilerMessage(to, body, hint string) error
```

Sends a message with XEP-0382 spoiler markup. The `hint` is shown before revealing the hidden content.

### FastenPayload

```go
func (c *XMPPCore) FastenPayload(to, targetID, payload string) error
```

Attaches an XML payload to an existing message via XEP-0422 message fastening.

### SendJSONMessage

```go
func (c *XMPPCore) SendJSONMessage(to string, jsonPayload json.RawMessage) error
```

Sends a message with a XEP-0432 JSON payload element.

### SendQuickResponse

```go
func (c *XMPPCore) SendQuickResponse(to, body string, responses []string) error
```

Sends a message with XEP-0439 quick response buttons.

### SendContentTypedMessage

```go
func (c *XMPPCore) SendContentTypedMessage(to, body, contentType string) error
```

Sends a message annotated with a XEP-0481 MIME content type.

### SendRealTimeText

```go
func (c *XMPPCore) SendRealTimeText(to string, seq int, actions []map[string]string) error
```

Sends XEP-0301 real-time text events. Actions can include `"insert"`, `"erase"`, or `"wait"` keys.

### RequestStanzaIDs

```go
func (c *XMPPCore) RequestStanzaIDs() error
```

Requests XEP-0359 server-assigned stanza IDs.

### GetInbox

```go
func (c *XMPPCore) GetInbox() (*XMPPIQ, error)
```

Queries the XEP-0430 server-side inbox.

### SearchMAMFullText

```go
func (c *XMPPCore) SearchMAMFullText(query string) (*XMPPIQ, error)
```

Performs a XEP-0431 full-text search in MAM archives.

### SetReminder

```go
func (c *XMPPCore) SetReminder(to, text string, when time.Time) error
```

Schedules a XEP-0435 reminder message.

### SendMessageReference

```go
func (c *XMPPCore) SendMessageReference(toJID, text, refType, refURI string) error
```

Sends a message with a XEP-0372 reference to a URI or data.

### SendRichTextMessage

```go
func (c *XMPPCore) SendRichTextMessage(toJID, plainText, xhtmlBody string) error
```

Sends a message with XEP-0071 XHTML-IM rich text body alongside a plain text fallback.

### HandleOccupantId

```go
func (c *XMPPCore) HandleOccupantId(stanzaXML string) string
```

Extracts the XEP-0421 anonymous occupant-id from a MUC stanza.

### SyncDisplayedMessages

```go
func (c *XMPPCore) SyncDisplayedMessages(jid, stanzaID string) error
```

Publishes a XEP-0490 displayed marker to PEP for cross-device read sync.

### SetFallbackIndication

```go
func (c *XMPPCore) SetFallbackIndication(forNS string) string
```

Returns a XEP-0428 `<fallback>` XML element marking the body as a fallback for an unsupported extension.

### ForwardStanza

```go
func (c *XMPPCore) ForwardStanza(to, originalFrom, originalStanza string) error
```

Forwards a stanza using XEP-0297 standard encapsulation with a delay stamp.

### SendBitsOfBinary

```go
func (c *XMPPCore) SendBitsOfBinary(to string, data []byte, mimeType, cid string) error
```

Sends XEP-0231 inline binary data (small images, sounds) as base64 within a message.

---

## MUC -- Multi-User Chat (XEP-0045)

### JoinMUC

```go
func (c *XMPPCore) JoinMUC(roomJID, nick string) error
```

Joins a MUC room. Pass `""` for nick to use the local part of your JID. Requests up to 50 lines of history on join.

```go
err := xmpp.JoinMUC("room@conference.example.com", "alice")
```

### LeaveMUC

```go
func (c *XMPPCore) LeaveMUC(roomJID string) error
```

Sends unavailable presence to leave a MUC room.

### SetMUCNick

```go
func (c *XMPPCore) SetMUCNick(roomJID, nick string) error
```

Changes your nickname in a MUC room by sending a new presence.

### GetMUCOccupants

```go
func (c *XMPPCore) GetMUCOccupants(roomJID string) ([]User, error)
```

Returns all occupants of a joined MUC room from the local cache.

### GetMUCInfo

```go
func (c *XMPPCore) GetMUCInfo(roomJID string) (*Dialog, error)
```

Queries disco#info for a MUC room and returns name, member count, etc.

### SetMUCSubject

```go
func (c *XMPPCore) SetMUCSubject(roomJID, subject string) error
```

Sets the room subject/topic.

### SendMUCInvitation

```go
func (c *XMPPCore) SendMUCInvitation(roomJID, userJID, reason string) error
```

Sends a XEP-0249 direct MUC invitation.

### SendMUCMediatedInvite

```go
func (c *XMPPCore) SendMUCMediatedInvite(roomJID, userJID, reason string) error
```

Sends a XEP-0045 mediated MUC invitation (via the room).

### DeclineMUCInvitation

```go
func (c *XMPPCore) DeclineMUCInvitation(roomJID, inviterJID, reason string) error
```

Declines a MUC invitation.

### SetMUCRole

```go
func (c *XMPPCore) SetMUCRole(roomJID, nick, role string) error
```

Sets a participant's role (`"none"`, `"visitor"`, `"participant"`, `"moderator"`).

### SetMUCAffiliation

```go
func (c *XMPPCore) SetMUCAffiliation(roomJID, userJID, affiliation string) error
```

Sets a user's affiliation (`"none"`, `"member"`, `"admin"`, `"owner"`, `"outcast"`).

### KickFromMUC

```go
func (c *XMPPCore) KickFromMUC(roomJID, nick, reason string) error
```

Kicks a user by setting their role to "none".

### BanFromMUC

```go
func (c *XMPPCore) BanFromMUC(roomJID, userJID, reason string) error
```

Bans a user by setting their affiliation to "outcast".

### UnbanFromMUC

```go
func (c *XMPPCore) UnbanFromMUC(roomJID, userJID string) error
```

Unbans by setting affiliation to "none".

### GrantVoice

```go
func (c *XMPPCore) GrantVoice(roomJID, nick string) error
```

Promotes a visitor to participant (grants voice in moderated rooms).

### RevokeVoice

```go
func (c *XMPPCore) RevokeVoice(roomJID, nick string) error
```

Demotes a participant to visitor (revokes voice).

### GetMUCConfig

```go
func (c *XMPPCore) GetMUCConfig(roomJID string) (map[string]string, error)
```

Retrieves the room configuration form as key-value pairs.

### ConfigureMUC

```go
func (c *XMPPCore) ConfigureMUC(roomJID string, config map[string]string) error
```

Submits room configuration changes.

```go
err := xmpp.ConfigureMUC("room@conf.example.com", map[string]string{
    "muc#roomconfig_persistentroom": "1",
    "muc#roomconfig_membersonly":    "1",
})
```

### DestroyMUC

```go
func (c *XMPPCore) DestroyMUC(roomJID, reason string) error
```

Destroys a MUC room. Requires owner affiliation.

### CreateInstantMUC

```go
func (c *XMPPCore) CreateInstantMUC(roomJID, nick string) error
```

Joins a room and immediately accepts the default configuration (instant room creation).

### RequestMUCHistory

```go
func (c *XMPPCore) RequestMUCHistory(roomJID string, maxStanzas int) error
```

Re-sends a presence with a `<history maxstanzas='N'/>` element to request more history.

### MUCSelfPing

```go
func (c *XMPPCore) MUCSelfPing(roomJID string) error
```

Pings your own occupant JID in a room to verify you're still joined (XEP-0410).

### RequestMUCVoice

```go
func (c *XMPPCore) RequestMUCVoice(roomJID string) error
```

Requests participant role (voice) in a moderated room via a data form.

---

## MIX -- Modern MUC (XEP-0369)

### JoinMIXChannel

```go
func (c *XMPPCore) JoinMIXChannel(channelJID, nick string, subscriptions []string) error
```

Joins a MIX channel with specified node subscriptions (e.g. `"urn:xmpp:mix:nodes:messages"`).

### LeaveMIXChannel

```go
func (c *XMPPCore) LeaveMIXChannel(channelJID string) error
```

Leaves a MIX channel.

### SetMIXNick

```go
func (c *XMPPCore) SetMIXNick(channelJID, nick string) error
```

Changes your nickname on a MIX channel.

### UpdateMIXSubscriptions

```go
func (c *XMPPCore) UpdateMIXSubscriptions(channelJID string, subscribe, unsubscribe []string) error
```

Adds or removes node subscriptions on a MIX channel.

### CreateMIXChannel

```go
func (c *XMPPCore) CreateMIXChannel(serviceJID, channelName string) error
```

Creates a new MIX channel on the service.

### DestroyMIXChannel

```go
func (c *XMPPCore) DestroyMIXChannel(channelJID string) error
```

Destroys a MIX channel.

### MIXPresenceSubscribe

```go
func (c *XMPPCore) MIXPresenceSubscribe(channel string) error
```

Subscribes to presence updates on a MIX channel (XEP-0403).

### MIXSetAnonymity

```go
func (c *XMPPCore) MIXSetAnonymity(channel string, anonymous bool) error
```

Configures whether the MIX channel hides participant JIDs (XEP-0404).

### MIXPAMJoin

```go
func (c *XMPPCore) MIXPAMJoin(channel string) error
```

Joins a MIX channel via server-side PAM (XEP-0405), subscribing to messages, participants, and info nodes.

### MIXAdminSetConfig

```go
func (c *XMPPCore) MIXAdminSetConfig(channel string, fields map[string]string) error
```

Sets admin configuration on a MIX channel (XEP-0406).

### MIXMiscSetAvatar

```go
func (c *XMPPCore) MIXMiscSetAvatar(channel string, pngData []byte) error
```

Sets a MIX channel avatar (XEP-0407).

---

## Service Discovery (XEP-0030)

### DiscoInfo

```go
func (c *XMPPCore) DiscoInfo(target string) (*XMPPIQ, error)
```

Queries disco#info for a JID or server. Pass `""` for your server domain.

### DiscoItems

```go
func (c *XMPPCore) DiscoItems(target string) (*XMPPIQ, error)
```

Queries disco#items for sub-services and components.

### QueryFeatures

```go
func (c *XMPPCore) QueryFeatures(target string) ([]string, error)
```

Returns the feature list from disco#info as a string slice.

### QueryIdentity

```go
func (c *XMPPCore) QueryIdentity(target string) (category, typ, name string, err error)
```

Returns the identity (category, type, name) from disco#info.

### DiscoverMUCService

```go
func (c *XMPPCore) DiscoverMUCService() (string, error)
```

Auto-discovers the MUC (conference) service JID on the server.

### DiscoverHTTPUploadService

```go
func (c *XMPPCore) DiscoverHTTPUploadService() (string, int64, error)
```

Auto-discovers the HTTP Upload service JID and max file size.

### DiscoverExternalServices

```go
func (c *XMPPCore) DiscoverExternalServices() ([]map[string]string, error)
```

Queries XEP-0215 external services (TURN/STUN for calls). Returns service maps with `"host"`, `"port"`, `"type"`, `"transport"`, `"username"`, `"password"`.

### DiscoInfoExtended

```go
func (c *XMPPCore) DiscoInfoExtended(to, node string) (*XMPPIQ, error)
```

Queries disco#info with a specific node attribute (XEP-0128 extended info).

### EntityCaps2

```go
func (c *XMPPCore) EntityCaps2(hashAlgo string, features []string) string
```

Computes an XEP-0390 Entity Capabilities 2.0 hash string. Returns the base64-encoded hash.

### GetDOAP

```go
func (c *XMPPCore) GetDOAP(to string) (*XMPPIQ, error)
```

Queries XEP-0453 machine-readable capability descriptions.

---

## PubSub (XEP-0060) & PEP (XEP-0163)

### CreatePubSubNode

```go
func (c *XMPPCore) CreatePubSubNode(service, node string) error
```

Creates a PubSub node. Pass `""` for service to use the server domain.

### DeletePubSubNode

```go
func (c *XMPPCore) DeletePubSubNode(service, node string) error
```

Deletes a PubSub node.

### PublishPubSubItem

```go
func (c *XMPPCore) PublishPubSubItem(service, node, itemID, payload string) error
```

Publishes an item to a PubSub node. Pass `""` for service to publish to your own PEP.

### RetractPubSubItem

```go
func (c *XMPPCore) RetractPubSubItem(service, node, itemID string) error
```

Retracts (deletes) an item from a PubSub node.

### SubscribePubSub

```go
func (c *XMPPCore) SubscribePubSub(service, node string) error
```

Subscribes to a PubSub node.

### UnsubscribePubSub

```go
func (c *XMPPCore) UnsubscribePubSub(service, node string) error
```

Unsubscribes from a PubSub node.

### GetPubSubItems

```go
func (c *XMPPCore) GetPubSubItems(service, node string) (*XMPPIQ, error)
```

Retrieves all items from a PubSub node.

### GetPubSubSubscriptions

```go
func (c *XMPPCore) GetPubSubSubscriptions(service string) (*XMPPIQ, error)
```

Lists your subscriptions on a PubSub service.

### ConfigurePubSubNode

```go
func (c *XMPPCore) ConfigurePubSubNode(service, node string, config map[string]string) error
```

Configures a PubSub node via a data form.

### SetUserMood

```go
func (c *XMPPCore) SetUserMood(mood, text string) error
```

Publishes a PEP user mood (XEP-0107). Example moods: `"happy"`, `"angry"`, `"bored"`.

### SetUserActivity

```go
func (c *XMPPCore) SetUserActivity(activity, specific, text string) error
```

Publishes a PEP user activity (XEP-0108). e.g. `("relaxing", "partying", "Having a great time!")`.

### SetUserTune

```go
func (c *XMPPCore) SetUserTune(artist, title, source string, length int) error
```

Publishes currently playing music (XEP-0118).

### SetUserLocation

```go
func (c *XMPPCore) SetUserLocation(lat, lon float64, description string) error
```

Publishes geolocation (XEP-0080).

### SetAvatarPEP

```go
func (c *XMPPCore) SetAvatarPEP(imageData []byte, mimeType string) error
```

Publishes an avatar via XEP-0084 PEP: uploads data and metadata.

### GetAvatarPEP

```go
func (c *XMPPCore) GetAvatarPEP(jid string) ([]byte, error)
```

Retrieves a user's PEP avatar image data.

---

## PubSub Extended

### PurgeNode

```go
func (c *XMPPCore) PurgeNode(service, node string) error
```

Removes all items from a PubSub node.

### GetNodeAffiliations

```go
func (c *XMPPCore) GetNodeAffiliations(service, node string) (*XMPPIQ, error)
```

Lists affiliations on a PubSub node.

### SetNodeAffiliation

```go
func (c *XMPPCore) SetNodeAffiliation(service, node, jid, affiliation string) error
```

Sets a JID's affiliation on a PubSub node.

### GetNodeSubscribers

```go
func (c *XMPPCore) GetNodeSubscribers(service, node string) (*XMPPIQ, error)
```

Lists all subscribers to a PubSub node.

### PEPManageNode

```go
func (c *XMPPCore) PEPManageNode(node string, config map[string]string) error
```

Manages a PEP node's configuration (XEP-0163).

### PubSubPersistPublic

```go
func (c *XMPPCore) PubSubPersistPublic(node, itemID, payload string) error
```

Publishes with XEP-0222 best practices for public persistent data (open access, persist=true).

### PubSubPersistPrivate

```go
func (c *XMPPCore) PubSubPersistPrivate(node, itemID, payload string) error
```

Publishes with XEP-0223 best practices for private persistent data (whitelist access).

### PubSubCollectionNode

```go
func (c *XMPPCore) PubSubCollectionNode(node, childNode string) error
```

Creates a XEP-0248 collection node.

### PublishMicroblog

```go
func (c *XMPPCore) PublishMicroblog(content, author string) error
```

Publishes an Atom entry to the XEP-0277 microblog node.

### QueryPubSubMAM

```go
func (c *XMPPCore) QueryPubSubMAM(service, node string) (*XMPPIQ, error)
```

Queries MAM on a PubSub node archive (XEP-0442).

### SetPubSubCachingHints

```go
func (c *XMPPCore) SetPubSubCachingHints(node string, maxAge int) error
```

Sets XEP-0460 caching hints (item expiry in seconds) on a node.

### FilterPubSubByType

```go
func (c *XMPPCore) FilterPubSubByType(service, nodeType string) (*XMPPIQ, error)
```

Filters PubSub nodes by type (XEP-0462).

### SetPubSubPublicSubscriptions

```go
func (c *XMPPCore) SetPubSubPublicSubscriptions(node string, public bool) error
```

Sets whether subscriptions to a node are publicly visible (XEP-0465).

### PubSubAttachment

```go
func (c *XMPPCore) PubSubAttachment(targetNode, targetItem, attachmentPayload string) error
```

Adds a reaction or comment to a PubSub item (XEP-0470).

### PublishSocialFeed

```go
func (c *XMPPCore) PublishSocialFeed(content, contentType string) error
```

Publishes to a XEP-0472 social feed node.

### EncryptPubSubOX

```go
func (c *XMPPCore) EncryptPubSubOX(node, itemID, payload string) error
```

Publishes an OpenPGP-encrypted item to a PubSub node (XEP-0473).

### GetPubSubServerInfo

```go
func (c *XMPPCore) GetPubSubServerInfo(service string) (*XMPPIQ, error)
```

Queries XEP-0485 server information from a PubSub service.

### SetPubSubRelationship

```go
func (c *XMPPCore) SetPubSubRelationship(node, parentNode string) error
```

Sets a node's parent collection (XEP-0496).

### PubSubCompareAndPublish

```go
func (c *XMPPCore) PubSubCompareAndPublish(node, itemID, payload, prevID string) error
```

Performs an atomic compare-and-swap publish (XEP-0395).

---

## File Transfer -- HTTP Upload (XEP-0363)

### RequestHTTPUploadSlot

```go
func (c *XMPPCore) RequestHTTPUploadSlot(filename string, size int64, contentType string) (putURL, getURL string, err error)
```

Requests a PUT/GET URL pair from the HTTP Upload service.

### UploadFileHTTP

```go
func (c *XMPPCore) UploadFileHTTP(putURL string, data []byte, contentType string, progress func(sent, total int64)) error
```

Uploads file data to the PUT URL via HTTP.

### DownloadFileHTTP

```go
func (c *XMPPCore) DownloadFileHTTP(url, dest string, progress func(recv, total int64)) error
```

Downloads a file from a URL to a local path with progress reporting.

### SendFileURL

```go
func (c *XMPPCore) SendFileURL(chatID, url, caption string) (*Message, error)
```

Sends a message containing an OOB URL pointing to an uploaded file.

---

## File Transfer -- In-Band Bytestreams (XEP-0047)

### OpenIBBSession

```go
func (c *XMPPCore) OpenIBBSession(toJID, sid string, blockSize int) error
```

Opens an in-band bytestream session with a given block size.

### SendIBBData

```go
func (c *XMPPCore) SendIBBData(toJID, sid string, seq int, data []byte) error
```

Sends a chunk of data over an in-band bytestream.

### CloseIBBSession

```go
func (c *XMPPCore) CloseIBBSession(toJID, sid string) error
```

Closes an in-band bytestream session.

---

## File Transfer -- SOCKS5 Bytestreams (XEP-0065)

### InitiateS5B

```go
func (c *XMPPCore) InitiateS5B(toJID, sid string, streamHosts []map[string]string) error
```

Initiates a SOCKS5 proxy-mediated file transfer. Each stream host map should contain `"jid"`, `"host"`, `"port"`.

### ActivateS5B

```go
func (c *XMPPCore) ActivateS5B(proxyJID, sid, targetJID string) error
```

Activates the bytestream after the proxy connection is established.

---

## File Transfer -- Stateless File Sharing (XEP-0447)

### ShareFileMetadata

```go
func (c *XMPPCore) ShareFileMetadata(toJID, name, mediaType string, size int64, hash string) error
```

Sends file metadata (name, type, size, hash) for stateless file sharing.

### ShareFileSources

```go
func (c *XMPPCore) ShareFileSources(toJID string, urls []string) error
```

Sends file source URLs for stateless file sharing.

---

## File Transfer -- Encrypted & Media

### ShareEncryptedFile

```go
func (c *XMPPCore) ShareEncryptedFile(toJID, name, mediaType string, size int64, ivB64, keyB64, url string) error
```

Sends XEP-0448 AESGCM-encrypted file sharing metadata.

### EncryptMedia

```go
func (c *XMPPCore) EncryptMedia(plaintext []byte) ([]byte, string, string, error)
```

Encrypts bytes with a random AES-256-GCM key. Returns ciphertext, IV (base64), and key (base64). Used for XEP-0454 OMEMO media sharing.

### DecryptMedia

```go
func (c *XMPPCore) DecryptMedia(ciphertext []byte, ivB64, keyB64 string) ([]byte, error)
```

Decrypts AES-256-GCM encrypted media given base64-encoded IV and key.

### ShareFileMetadataElem

```go
func (c *XMPPCore) ShareFileMetadataElem(to, name, mimeType string, size int64, hashAlgo, hashValue string) error
```

Sends XEP-0446 standalone file metadata with hash.

### SendSIMS

```go
func (c *XMPPCore) SendSIMS(to, url, mimeType string, size int64, desc string) error
```

Sends XEP-0385 stateless inline media sharing.

### PubSubFileShare

```go
func (c *XMPPCore) PubSubFileShare(node, itemID, name, url string) error
```

Publishes a file share to a PubSub node (XEP-0498).

### DataFormsFileInput

```go
func (c *XMPPCore) DataFormsFileInput(to, formType, fieldVar, uploadURL string) error
```

Submits a file upload via data forms (XEP-0505).

### JingleContentThumbnail

```go
func (c *XMPPCore) JingleContentThumbnail(to, sid, thumbnailURI, mimeType string, width, height int) error
```

Adds a XEP-0264 thumbnail to a Jingle file offer.

---

## Bookmarks (XEP-0048 / XEP-0402)

### GetBookmarks

```go
func (c *XMPPCore) GetBookmarks() ([]xmppBookmark, error)
```

Returns all bookmarks, loading from PEP (XEP-0402) or private storage (XEP-0048) if needed.

### SetBookmark

```go
func (c *XMPPCore) SetBookmark(jid, name, nick string, autoJoin bool) error
```

Adds or updates a bookmark and saves to the server.

### RemoveBookmark

```go
func (c *XMPPCore) RemoveBookmark(jid string) error
```

Removes a bookmark.

### SetBookmarkAutoJoin

```go
func (c *XMPPCore) SetBookmarkAutoJoin(jid string, autoJoin bool) error
```

Toggles the auto-join flag on a bookmark.

### SetBookmarkPEP

```go
func (c *XMPPCore) SetBookmarkPEP(roomJID, name, nick string, autoJoin bool) error
```

Sets a bookmark as an individual PubSub item via XEP-0402 (PEP native bookmarks).

### RemoveBookmarkPEP

```go
func (c *XMPPCore) RemoveBookmarkPEP(roomJID string) error
```

Removes a PEP native bookmark.

### BookmarksConversion

```go
func (c *XMPPCore) BookmarksConversion() error
```

Requests XEP-0411 server-side bookmark conversion between old and new formats.

---

## MAM -- Message Archive Management (XEP-0313)

### QueryMAM

```go
func (c *XMPPCore) QueryMAM(jid string, limit int, after string) ([]Message, error)
```

Queries the MAM archive. Results are delivered via the read loop and returned from the local buffer.

```go
msgs, err := xmpp.QueryMAM("alice@example.com", 50, "")
```

### QueryMAMByJID

```go
func (c *XMPPCore) QueryMAMByJID(jid string, limit int) ([]Message, error)
```

Shorthand for `QueryMAM(jid, limit, "")`.

### QueryMAMByDateRange

```go
func (c *XMPPCore) QueryMAMByDateRange(jid string, start, end time.Time, limit int) ([]Message, error)
```

Queries MAM with date-range filtering.

### QueryMAMPage

```go
func (c *XMPPCore) QueryMAMPage(jid string, limit int, after string) ([]Message, error)
```

Pages through MAM results using an `after` cursor.

### GetMAMPreferences

```go
func (c *XMPPCore) GetMAMPreferences() (*XMPPIQ, error)
```

Retrieves MAM archive preferences.

### SetMAMPreferences

```go
func (c *XMPPCore) SetMAMPreferences(defaultPolicy string, alwaysJIDs, neverJIDs []string) error
```

Configures MAM preferences. `defaultPolicy` is `"always"`, `"never"`, or `"roster"`.

---

## vCards (XEP-0054 / XEP-0292)

### GetVCard

```go
func (c *XMPPCore) GetVCard(jid string) (map[string]string, error)
```

Retrieves a vCard (XEP-0054). Returns fields: `"FN"`, `"NICKNAME"`, `"EMAIL"`, `"URL"`, `"DESC"`, `"TEL"`, `"PHOTO_TYPE"`, `"PHOTO_BINVAL"`. Results are cached.

### SetVCard

```go
func (c *XMPPCore) SetVCard(fields map[string]string) error
```

Sets your vCard. Supported fields: `"FN"`, `"NICKNAME"`, `"EMAIL"`, `"URL"`, `"DESC"`.

### GetVCardField

```go
func (c *XMPPCore) GetVCardField(jid, field string) (string, error)
```

Gets a single vCard field by name.

### SetAvatarVCard

```go
func (c *XMPPCore) SetAvatarVCard(imageData []byte, mimeType string) error
```

Sets your avatar in the vCard and updates the local cache.

### GetVCard4

```go
func (c *XMPPCore) GetVCard4(jid string) (*XMPPIQ, error)
```

Retrieves a vCard4 (XEP-0292) from PubSub.

### SetVCard4

```go
func (c *XMPPCore) SetVCard4(vcardXML string) error
```

Publishes a vCard4 via PubSub.

### SetVCardAvatar

```go
func (c *XMPPCore) SetVCardAvatar(pngData []byte) error
```

Sets a vCard-based avatar (XEP-0153) and broadcasts the photo hash via presence.

---

## OMEMO / Encryption (XEP-0384)

### PublishOMEMODeviceList

```go
func (c *XMPPCore) PublishOMEMODeviceList(deviceIDs []int) error
```

Publishes your OMEMO device list via PEP.

### FetchOMEMODeviceList

```go
func (c *XMPPCore) FetchOMEMODeviceList(jid string) (*XMPPIQ, error)
```

Fetches a contact's OMEMO device list.

### PublishOMEMOBundle

```go
func (c *XMPPCore) PublishOMEMOBundle(deviceID int, bundleXML string) error
```

Publishes your OMEMO key bundle via PEP.

### FetchOMEMOBundle

```go
func (c *XMPPCore) FetchOMEMOBundle(jid string, deviceID int) (*XMPPIQ, error)
```

Fetches an OMEMO key bundle for a specific device.

### OMEMOEncrypt

```go
func (c *XMPPCore) OMEMOEncrypt(payload []byte, recipientKeys []map[string]string) (string, error)
```

Produces an OMEMO encrypted XML element. Each recipient key map needs `"rid"`, `"prekey"`, `"data"`.

### OMEMODecrypt

```go
func (c *XMPPCore) OMEMODecrypt(encryptedXML string, sessionKey []byte) ([]byte, error)
```

Extracts and decodes the base64 payload from an OMEMO encrypted element.

### OMEMOBuildSession

```go
func (c *XMPPCore) OMEMOBuildSession(jid string, deviceID int) error
```

Fetches the OMEMO bundle for a device to establish an encryption session.

### OMEMOAutoTrust

```go
func (c *XMPPCore) OMEMOAutoTrust(to string, deviceIDs []int) error
```

Sends a XEP-0450 automatic trust management message for OMEMO devices.

---

## OpenPGP for XMPP (XEP-0373/0374)

### PublishOXPublicKey

```go
func (c *XMPPCore) PublishOXPublicKey(fingerprint string, pubKeyB64 string) error
```

Publishes an OpenPGP public key via PEP.

### FetchOXPublicKey

```go
func (c *XMPPCore) FetchOXPublicKey(jid, fingerprint string) (*XMPPIQ, error)
```

Fetches a user's OpenPGP public key.

### OXEncrypt

```go
func (c *XMPPCore) OXEncrypt(payload string) string
```

Wraps a payload in an OX signcrypt element with timestamp and padding.

### OXDecrypt

```go
func (c *XMPPCore) OXDecrypt(signcryptXML string) (string, error)
```

Extracts the payload from an OX signcrypt element.

### OXSignEncrypt

```go
func (c *XMPPCore) OXSignEncrypt(toJID, payload, openpgpB64 string) error
```

Sends an OX sign+encrypt message (XEP-0374) with an EME hint.

---

## Stanza Content Encryption (XEP-0420)

### EncryptStanzaContent

```go
func (c *XMPPCore) EncryptStanzaContent(payload, rpad string) string
```

Wraps content in an SCE envelope with sender, timestamp, and random padding.

### DecryptStanzaContent

```go
func (c *XMPPCore) DecryptStanzaContent(envelopeXML string) (string, error)
```

Extracts the content from an SCE envelope.

---

## Trust Messages (XEP-0434)

### SendTrustMessage

```go
func (c *XMPPCore) SendTrustMessage(toJID, encryptionNS string, trustedKeys, distrustedKeys []string) error
```

Sends a trust message to communicate key trust/distrust decisions.

---

## Explicit Message Encryption (XEP-0380)

### SetEncryptionHint

```go
func (c *XMPPCore) SetEncryptionHint(namespace, name string) string
```

Returns an EME XML element indicating which encryption protocol is used (for inclusion in messages).

---

## User Blocking (XEP-0191)

### BlockJID

```go
func (c *XMPPCore) BlockJID(jid string) error
```

Blocks a JID server-side. Updates local blocked set.

### UnblockJID

```go
func (c *XMPPCore) UnblockJID(jid string) error
```

Unblocks a JID server-side.

### GetBlocklist

```go
func (c *XMPPCore) GetBlocklist() ([]string, error)
```

Retrieves the full block list from the server. Falls back to local state on error.

---

## Privacy Lists (XEP-0016)

### GetPrivacyLists

```go
func (c *XMPPCore) GetPrivacyLists() (*XMPPIQ, error)
```

Retrieves all privacy lists.

### SetActiveList

```go
func (c *XMPPCore) SetActiveList(name string) error
```

Sets the active privacy list for this session.

### SetDefaultList

```go
func (c *XMPPCore) SetDefaultList(name string) error
```

Sets the default privacy list (applies when no active list is set).

---

## Ping / Last Activity / Entity Time

### SendPing

```go
func (c *XMPPCore) SendPing(to string) error
```

Sends a XEP-0199 ping. Pass `""` to ping the server.

### GetSoftwareVersion

```go
func (c *XMPPCore) GetSoftwareVersion(jid string) (name, version, os string, err error)
```

Queries XEP-0092 software version of a JID.

### GetLastActivity

```go
func (c *XMPPCore) GetLastActivity(jid string) (int64, error)
```

Queries XEP-0012 last activity (idle seconds) for a JID.

### GetEntityTime

```go
func (c *XMPPCore) GetEntityTime(jid string) (utc, tzo string, err error)
```

Queries XEP-0202 entity time (UTC time and timezone offset).

### GetLastUserInteraction

```go
func (c *XMPPCore) GetLastUserInteraction(jid string) (*XMPPIQ, error)
```

Queries XEP-0319 last user interaction time.

---

## Client State Indication (XEP-0352)

### SetClientStateActive

```go
func (c *XMPPCore) SetClientStateActive() error
```

Tells the server the client is active (send all updates).

### SetClientStateInactive

```go
func (c *XMPPCore) SetClientStateInactive() error
```

Tells the server the client is inactive (server may throttle non-essential traffic).

---

## Entity Capabilities

### GetEntityCapabilities

```go
func (c *XMPPCore) GetEntityCapabilities(jid string) (string, error)
```

Returns the raw disco#info XML for a JID.

---

## Stream Management (XEP-0198)

### EnableStreamManagement

```go
func (c *XMPPCore) EnableStreamManagement() error
```

Enables stream management with resume support. Called automatically during post-auth setup if the server advertises SM.

### RequestAck

```go
func (c *XMPPCore) RequestAck() error
```

Sends an `<r/>` request asking the server to acknowledge received stanzas.

### SendAck

```go
func (c *XMPPCore) SendAck() error
```

Sends an `<a/>` acknowledgment of how many stanzas we have handled.

### ResumeStream

```go
func (c *XMPPCore) ResumeStream(prevID string, h int64) error
```

Attempts to resume a previous stream management session.

---

## Registration (XEP-0077)

### RegisterAccount

```go
func (c *XMPPCore) RegisterAccount(server, username, password string) error
```

Registers a new account via in-band registration.

### ChangePassword

```go
func (c *XMPPCore) ChangePassword(newPassword string) error
```

Changes the account password.

### UnregisterAccount

```go
func (c *XMPPCore) UnregisterAccount() error
```

Deletes the account from the server.

---

## Ad-Hoc Commands (XEP-0050)

### DiscoverCommands

```go
func (c *XMPPCore) DiscoverCommands(serviceJID string) (*XMPPIQ, error)
```

Lists available ad-hoc commands on a service.

### ExecuteCommand

```go
func (c *XMPPCore) ExecuteCommand(serviceJID, node, sessionID, action, formXML string) (*XMPPIQ, error)
```

Executes an ad-hoc command. Use `""` for action to default to "execute". Pass `""` for sessionID on the first step.

### CancelCommand

```go
func (c *XMPPCore) CancelCommand(serviceJID, node, sessionID string) error
```

Cancels an in-progress ad-hoc command session.

---

## Data Forms (XEP-0004)

### SubmitForm

```go
func (c *XMPPCore) SubmitForm(toJID, formXML string) error
```

Submits a data form.

### CancelForm

```go
func (c *XMPPCore) CancelForm(toJID, formXML string) error
```

Cancels a data form.

### ProcessFormResult

```go
func (c *XMPPCore) ProcessFormResult(formXML string) map[string]string
```

Parses a form result XML into key-value pairs.

---

## Private XML Storage (XEP-0049)

### StorePrivateXML

```go
func (c *XMPPCore) StorePrivateXML(innerXML string) error
```

Stores arbitrary XML in private server-side storage.

### RetrievePrivateXML

```go
func (c *XMPPCore) RetrievePrivateXML(namespace, element string) (*XMPPIQ, error)
```

Retrieves data from private XML storage by namespace and element name.

---

## Offline Messages (XEP-0013)

### GetOfflineMessageCount

```go
func (c *XMPPCore) GetOfflineMessageCount() (*XMPPIQ, error)
```

Returns the number of stored offline messages.

### GetOfflineMessageHeaders

```go
func (c *XMPPCore) GetOfflineMessageHeaders() (*XMPPIQ, error)
```

Returns headers of stored offline messages.

### RetrieveOfflineMessages

```go
func (c *XMPPCore) RetrieveOfflineMessages(nodeIDs []string) (*XMPPIQ, error)
```

Retrieves specific offline messages by node ID.

### RemoveOfflineMessages

```go
func (c *XMPPCore) RemoveOfflineMessages(nodeIDs []string) error
```

Removes specific offline messages from the server.

---

## Push Notifications (XEP-0357)

### EnablePushNotifications

```go
func (c *XMPPCore) EnablePushNotifications(pushServiceJID, node string, publishOptions map[string]string) error
```

Enables push notifications via an app server.

### DisablePushNotifications

```go
func (c *XMPPCore) DisablePushNotifications(pushServiceJID, node string) error
```

Disables push notifications.

---

## Jingle -- Calls (XEP-0166)

### InitiateJingle

```go
func (c *XMPPCore) InitiateJingle(to string, video bool) (*CallSession, error)
```

Initiates a Jingle audio or video call. Returns a `CallSession` with the session ID and state.

```go
session, err := xmpp.InitiateJingle("bob@example.com/phone", true)
```

### AcceptJingle

```go
func (c *XMPPCore) AcceptJingle(to, sid string) error
```

Accepts a Jingle session with matching codec parameters.

### RejectJingle

```go
func (c *XMPPCore) RejectJingle(to, sid string) error
```

Rejects a Jingle session (terminates with reason "decline").

### TerminateJingle

```go
func (c *XMPPCore) TerminateJingle(sid, reason string) error
```

Terminates a Jingle session. Reason can be `"success"`, `"decline"`, `"cancel"`, `"busy"`, etc.

### SendJingleTransportInfo

```go
func (c *XMPPCore) SendJingleTransportInfo(to, sid, candidate string) error
```

Sends ICE candidate information for an active Jingle session.

### GetTURNCredentials

```go
func (c *XMPPCore) GetTURNCredentials() ([]map[string]string, error)
```

Discovers TURN/STUN credentials via XEP-0215 external services.

---

## Jingle Message Initiation (XEP-0353)

### ProposeCall

```go
func (c *XMPPCore) ProposeCall(toJID, sessionID string, descriptions string) error
```

Sends a pre-Jingle call proposal via message.

### AcceptProposal

```go
func (c *XMPPCore) AcceptProposal(toJID, sessionID string) error
```

Accepts a call proposal.

### RejectProposal

```go
func (c *XMPPCore) RejectProposal(toJID, sessionID string) error
```

Rejects a call proposal.

### RetractProposal

```go
func (c *XMPPCore) RetractProposal(toJID, sessionID string) error
```

Retracts a previously sent call proposal.

### ProceedToJingle

```go
func (c *XMPPCore) ProceedToJingle(toJID, sessionID string) error
```

Accepts a call proposal and indicates readiness for full Jingle negotiation.

### JingleMessageRinging

```go
func (c *XMPPCore) JingleMessageRinging(to, sid string) error
```

Sends a ringing signal via Jingle Message Initiation.

### SendCallInvite

```go
func (c *XMPPCore) SendCallInvite(to, sid string, audio, video bool) error
```

Sends a XEP-0482 call invite with audio/video flags.

---

## Jingle Extended Actions

### JingleContentAdd

```go
func (c *XMPPCore) JingleContentAdd(toJID, sessionID, contentXML string) error
```

Adds content (e.g. video stream) to an active Jingle session.

### JingleContentAccept

```go
func (c *XMPPCore) JingleContentAccept(toJID, sessionID, contentXML string) error
```

Accepts added content.

### JingleContentReject

```go
func (c *XMPPCore) JingleContentReject(toJID, sessionID, name string) error
```

Rejects added content by name.

### JingleContentModify

```go
func (c *XMPPCore) JingleContentModify(toJID, sessionID, contentXML string) error
```

Modifies content parameters mid-session.

### JingleContentRemove

```go
func (c *XMPPCore) JingleContentRemove(toJID, sessionID, name string) error
```

Removes content from a session.

### JingleTransportReplace

```go
func (c *XMPPCore) JingleTransportReplace(toJID, sessionID, contentName, transportXML string) error
```

Proposes a fallback transport.

### JingleTransportAccept

```go
func (c *XMPPCore) JingleTransportAccept(toJID, sessionID, contentName, transportXML string) error
```

Accepts a transport replacement.

### JingleTransportReject

```go
func (c *XMPPCore) JingleTransportReject(toJID, sessionID string) error
```

Rejects a transport replacement.

### JingleContentCategory

```go
func (c *XMPPCore) JingleContentCategory(to, sid, name, category string) error
```

Sets a content category (XEP-0507) to distinguish webcam vs screenshare.

---

## Jingle File Transfer (XEP-0234)

### JingleFileOffer

```go
func (c *XMPPCore) JingleFileOffer(toJID, sessionID, name string, size int64, hash, desc string) error
```

Initiates a Jingle file transfer with file metadata.

### JingleFileRequest

```go
func (c *XMPPCore) JingleFileRequest(toJID, sessionID, name string, size int64) error
```

Requests a file via Jingle (shorthand for `JingleFileOffer` without hash/desc).

### JingleFileChecksum

```go
func (c *XMPPCore) JingleFileChecksum(toJID, sessionID, algo, hash string) error
```

Sends a file checksum after transfer completes.

### JingleFileReceived

```go
func (c *XMPPCore) JingleFileReceived(toJID, sessionID string) error
```

Acknowledges file receipt.

### JingleFileResume

```go
func (c *XMPPCore) JingleFileResume(toJID, sessionID string, offset int64) error
```

Sends a resume request with byte offset for interrupted transfers.

---

## Jingle RTP / Codecs / Media

### JingleRTPSession

```go
func (c *XMPPCore) JingleRTPSession(to, sid, media string, payloadTypes []map[string]string) error
```

Sends a full XEP-0167 RTP session description with payload types.

### NegotiateRTCPFeedback

```go
func (c *XMPPCore) NegotiateRTCPFeedback(toJID, sessionID, contentName string, fbTypes []string) error
```

Includes XEP-0293 RTCP feedback types in the RTP description.

### NegotiateRTPHeaderExtensions

```go
func (c *XMPPCore) NegotiateRTPHeaderExtensions(toJID, sessionID, contentName string, extensions []string) error
```

Includes XEP-0294 RTP header extensions in Jingle.

### JingleSourceSSRC

```go
func (c *XMPPCore) JingleSourceSSRC(to, sid string, ssrc uint32, params map[string]string) error
```

Sends XEP-0339 per-source SSRC attributes.

### JingleGrouping

```go
func (c *XMPPCore) JingleGrouping(to, sid string, contentNames []string) error
```

Sends XEP-0338 SDP BUNDLE grouping for multiple media streams.

### JingleConferenceInfo

```go
func (c *XMPPCore) JingleConferenceInfo(to, sid string, users []string) error
```

Sends XEP-0298 conference state notification with participant list.

### PublishJingleSession

```go
func (c *XMPPCore) PublishJingleSession(sid, description string) error
```

Advertises a joinable Jingle session via PubSub (XEP-0358).

### JingleMuji

```go
func (c *XMPPCore) JingleMuji(room, media string) error
```

Sends a XEP-0272 multiparty Jingle presence to a MUC room.

---

## Jingle Transport Variants

### JingleRawUDP

```go
func (c *XMPPCore) JingleRawUDP(to, sid, candidateIP string, candidatePort int) error
```

Sends XEP-0177 raw UDP transport candidate.

### JingleTrickleICE

```go
func (c *XMPPCore) JingleTrickleICE(to, sid string, candidate map[string]string) error
```

Sends XEP-0371 trickle ICE candidate. Candidate map should contain `"ufrag"`, `"pwd"`, `"foundation"`, `"ip"`, `"port"`, `"priority"`, `"protocol"`, `"type"`.

### JingleDTLSSRTP

```go
func (c *XMPPCore) JingleDTLSSRTP(to, sid, fingerprint, setup string) error
```

Sends XEP-0320 DTLS-SRTP fingerprint. `setup` is `"active"`, `"passive"`, or `"actpass"`.

### JingleDataChannels

```go
func (c *XMPPCore) JingleDataChannels(to, sid string, port int) error
```

Initiates XEP-0343 WebRTC DTLS/SCTP data channels.

---

## Jingle Encryption & Advanced

### JingleZRTP

```go
func (c *XMPPCore) JingleZRTP(to, sid, zrtpHash, hashVersion string) error
```

Sends XEP-0262 ZRTP key agreement hash.

### JingleEncryptedTransport

```go
func (c *XMPPCore) JingleEncryptedTransport(to, sid, cipher, keyB64 string) error
```

Sends XEP-0391 JET (Jingle Encrypted Transport) parameters.

### JingleJETOMEMO

```go
func (c *XMPPCore) JingleJETOMEMO(to, sid string, deviceID int, keyData []byte) error
```

Sends XEP-0396 OMEMO-encrypted key for Jingle file transfers.

---

## Alternative Connections (XEP-0156)

### DiscoverAlternativeConnections

```go
func (c *XMPPCore) DiscoverAlternativeConnections(domain string) (wsURL, boshURL string, err error)
```

Queries `/.well-known/host-meta` for WebSocket and BOSH endpoints.

### ConnectWebSocket

```go
func (c *XMPPCore) ConnectWebSocket(wsURL string) error
```

Establishes an XMPP connection over WebSocket (RFC 7395).

### ConnectBOSH

```go
func (c *XMPPCore) ConnectBOSH(boshURL, domain string) (string, error)
```

Establishes an XMPP-over-BOSH session via HTTP long-polling (XEP-0124/0206). Returns the session ID.

### ConnectDirectTLS

```go
func (c *XMPPCore) ConnectDirectTLS(domain string) error
```

Connects via XEP-0368 xmpps-client SRV record (direct TLS, no STARTTLS).

### DiscoverHostMeta2

```go
func (c *XMPPCore) DiscoverHostMeta2(domain string) (map[string]string, error)
```

Queries XEP-0487 JSON-based host-meta discovery.

### ConnectHappyEyeballs

```go
func (c *XMPPCore) ConnectHappyEyeballs(host string, port int) (net.Conn, error)
```

Connects using XEP-0495 parallel A/AAAA DNS lookups.

### InstantStreamResumption

```go
func (c *XMPPCore) InstantStreamResumption(token string) error
```

Sends a XEP-0397 ISR token for instant stream resumption.

### QuickstartTLS

```go
func (c *XMPPCore) QuickstartTLS(domain string) error
```

Sends XEP-0305 STARTTLS with quickstart hint.

---

## SASL2 / Bind2 / FAST

### SASL2Authenticate

```go
func (c *XMPPCore) SASL2Authenticate(mechanism, initialResponse string, inlineFeatures string) error
```

Performs XEP-0388 SASL2 inline authentication.

### Bind2

```go
func (c *XMPPCore) Bind2(tag string) error
```

Performs XEP-0386 inline resource binding.

### FASTReconnect

```go
func (c *XMPPCore) FASTReconnect(token, mechanism string) error
```

Performs XEP-0484 token-based fast reconnection.

### OAuthClientLogin

```go
func (c *XMPPCore) OAuthClientLogin(token string) error
```

Authenticates using XEP-0493 OAUTHBEARER SASL mechanism.

### InitAuthPipelining

```go
func (c *XMPPCore) InitAuthPipelining(mechanism, initialResponse string) error
```

Sends XEP-0509 pipelined auth+bind request.

### NegotiateChannelBinding

```go
func (c *XMPPCore) NegotiateChannelBinding(bindingType string) string
```

Returns XEP-0440 SCRAM channel-binding type XML for SASL negotiation.

### GetStreamLimits

```go
func (c *XMPPCore) GetStreamLimits() map[string]int
```

Returns XEP-0478 stream limits: `"max_bytes"` and `"idle_seconds"`.

---

## Advanced Messaging Extensions

### GetStickerPack

```go
func (c *XMPPCore) GetStickerPack(serviceJID, node string) (*XMPPIQ, error)
```

Retrieves a XEP-0449 sticker pack from PubSub.

### SendStickerXEP

```go
func (c *XMPPCore) SendStickerXEP(toJID, stickerPackNode, stickerHash, fallbackBody string) error
```

Sends a XEP-0449 sticker with a fallback body for clients without sticker support.

### SetAMPRules

```go
func (c *XMPPCore) SetAMPRules(rules []map[string]string) string
```

Returns an XEP-0079 AMP element for inclusion in messages. Each rule map needs `"condition"`, `"action"`, `"value"`.

### VerifyHTTPRequest

```go
func (c *XMPPCore) VerifyHTTPRequest(toJID, confirmID, method, url string) error
```

Responds to a XEP-0070 HTTP authentication request.

### SendWebXDC

```go
func (c *XMPPCore) SendWebXDC(to, name string, data []byte) error
```

Sends a XEP-0491 interactive HTML/JS widget as base64 data.

---

## MUC Extensions

### SendDirectMUCInvitation

```go
func (c *XMPPCore) SendDirectMUCInvitation(to, room, reason, password string) error
```

Sends a XEP-0249 direct MUC invitation with optional password.

### SetMUCHat

```go
func (c *XMPPCore) SetMUCHat(room, nick, hatURI, hatTitle string) error
```

Sets a XEP-0317 visual role badge (hat) on an occupant.

### SearchChannels

```go
func (c *XMPPCore) SearchChannels(query string) (*XMPPIQ, error)
```

Searches for channels via XEP-0433 extended channel search.

### EnableMUCPresenceVersioning

```go
func (c *XMPPCore) EnableMUCPresenceVersioning(room string) error
```

Enables XEP-0436 presence versioning for efficient occupant updates.

### SubscribeRoomActivity

```go
func (c *XMPPCore) SubscribeRoomActivity(room string) error
```

Subscribes to XEP-0437 room activity notifications without joining.

### SubscribeMUCMentions

```go
func (c *XMPPCore) SubscribeMUCMentions(room string) error
```

Subscribes to XEP-0452 mention notifications in a room.

### EnableMUCAffiliationVersioning

```go
func (c *XMPPCore) EnableMUCAffiliationVersioning(room string) error
```

Enables XEP-0463 affiliation versioning for efficient updates.

### SetMUCAvatar

```go
func (c *XMPPCore) SetMUCAvatar(room string, pngData []byte) error
```

Sets a room avatar via vCard-temp (XEP-0486).

### CreateMUCTokenInvite

```go
func (c *XMPPCore) CreateMUCTokenInvite(room string) (*XMPPIQ, error)
```

Generates a XEP-0488 token-based invitation link.

### SetMUCSlowMode

```go
func (c *XMPPCore) SetMUCSlowMode(room string, intervalSeconds int) error
```

Configures XEP-0500 slow mode (minimum interval between messages).

### GetMUCActivityIndicator

```go
func (c *XMPPCore) GetMUCActivityIndicator(room string) (*XMPPIQ, error)
```

Queries XEP-0502 room activity indicator.

---

## User Profile & Social

### SetUserNickname

```go
func (c *XMPPCore) SetUserNickname(nick string) error
```

Publishes a XEP-0172 PEP nickname.

### GetUserNickname

```go
func (c *XMPPCore) GetUserNickname(jid string) (*XMPPIQ, error)
```

Fetches a user's PEP nickname.

### AvatarConversion

```go
func (c *XMPPCore) AvatarConversion(to string) (*XMPPIQ, error)
```

Queries XEP-0398 server-side avatar format conversion hints.

### SetReachability

```go
func (c *XMPPCore) SetReachability(addresses []map[string]string) error
```

Publishes XEP-0152 reachability addresses. Each map needs `"uri"` and `"desc"`.

---

## Notification & Sync

### SetChatNotificationSettings

```go
func (c *XMPPCore) SetChatNotificationSettings(jid, level string) error
```

Sets per-chat notification level via XEP-0492. Level can be `"default"`, `"always"`, `"never"`, etc.

### SetServerNotificationFilter

```go
func (c *XMPPCore) SetServerNotificationFilter(rules map[string]bool) error
```

Configures XEP-0351 server-side notification filtering. Keys are event types, values are enable/disable.

---

## Server Interaction

### SearchUsersXMPP

```go
func (c *XMPPCore) SearchUsersXMPP(serviceJID, formXML string) (*XMPPIQ, error)
```

Queries a user directory via XEP-0055 Jabber Search with raw form XML.

### SearchUsersExtended

```go
func (c *XMPPCore) SearchUsersExtended(service string, fields map[string]string) (*XMPPIQ, error)
```

Searches a user directory using data form fields.

### HandleCAPTCHA

```go
func (c *XMPPCore) HandleCAPTCHA(to, challengeID, answer string) error
```

Responds to a XEP-0158 CAPTCHA challenge.

### EnableRosterVersioning

```go
func (c *XMPPCore) EnableRosterVersioning(ver string) (*XMPPIQ, error)
```

Requests a XEP-0237 versioned roster. Pass `""` for initial roster fetch.

### CreateInvitationURI

```go
func (c *XMPPCore) CreateInvitationURI() (*XMPPIQ, error)
```

Generates a XEP-0401 invitation URI.

### PreAuthenticatedIBR

```go
func (c *XMPPCore) PreAuthenticatedIBR(token string) error
```

Sends a XEP-0445 token-gated registration request.

### GetServiceOutageStatus

```go
func (c *XMPPCore) GetServiceOutageStatus(domain string) (*XMPPIQ, error)
```

Queries XEP-0455 server outage/maintenance status.

### GetDataPolicy

```go
func (c *XMPPCore) GetDataPolicy(domain string) (*XMPPIQ, error)
```

Queries XEP-0504 data retention policy.

### RevokeClientAccess

```go
func (c *XMPPCore) RevokeClientAccess(clientID string) error
```

Revokes per-client access via XEP-0494.

### ListClientAccess

```go
func (c *XMPPCore) ListClientAccess() (*XMPPIQ, error)
```

Lists authorized clients via XEP-0494.

---

## Newer / Experimental

### CreateServerSpace

```go
func (c *XMPPCore) CreateServerSpace(name string, channels []string) error
```

Creates a XEP-0503 server space (Discord-like channel category).

### CreateForum

```go
func (c *XMPPCore) CreateForum(service, name string) error
```

Creates a XEP-0508 threaded discussion forum.

### EncryptContactsMetadata

```go
func (c *XMPPCore) EncryptContactsMetadata(jid string, encryptedPayload []byte) error
```

Publishes XEP-0510 encrypted contacts metadata via PEP.

### GetLinkMetadata

```go
func (c *XMPPCore) GetLinkMetadata(url string) (*XMPPIQ, error)
```

Queries XEP-0511 rich link preview metadata.

### RequestOnlineMeeting

```go
func (c *XMPPCore) RequestOnlineMeeting(service, meetingType string) (*XMPPIQ, error)
```

Requests a XEP-0483 HTTP online meeting invite.

### RequestBurnerJID

```go
func (c *XMPPCore) RequestBurnerJID(service string) (*XMPPIQ, error)
```

Requests a XEP-0383 temporary anonymous JID.

---

## Result Set Management (XEP-0059)

### RSMQuery

```go
func (c *XMPPCore) RSMQuery(to, queryNS string, max int, after string) (*XMPPIQ, error)
```

Performs a paginated query with result set management.

---

## Miscellaneous Utilities

### NegotiateSession

```go
func (c *XMPPCore) NegotiateSession(to string, fields map[string]string) error
```

Sends a XEP-0155 stanza session negotiation request.

### ParseMessageStyling (package-level)

```go
func ParseMessageStyling(text string) []map[string]string
```

Parses XEP-0393 message styling directives (`*bold*`, `_italic_`, `` `code` ``, `~strike~`). Returns span info with style, text, start, and end positions.

### JingleAudioCodecs (package-level)

```go
func JingleAudioCodecs() []map[string]string
```

Returns XEP-0266 recommended audio codec list: Opus, Speex, PCMU, PCMA.

### JingleVideoCodecs (package-level)

```go
func JingleVideoCodecs() []map[string]string
```

Returns XEP-0299 recommended video codec list: VP8, H264.

### ConsistentColor (package-level)

```go
func ConsistentColor(jid string) (float64, float64, float64)
```

Generates a XEP-0392 consistent HSL color from a JID string.

### HashElement (package-level)

```go
func HashElement(algo string, data []byte) string
```

Returns a XEP-0300 standardized hash XML element. Supports `"sha-256"` and `"sha-1"`.

---

## Unsupported Core Methods

These Core interface methods return `ErrNotSupported`:

```go
func (c *XMPPCore) MuteChat(chatID string, muted bool) error
func (c *XMPPCore) ArchiveChat(chatID string, archived bool) error
func (c *XMPPCore) MarkUnread(chatID string, unread bool) error
func (c *XMPPCore) UnpinAllMessages(chatID string) error
func (c *XMPPCore) AcceptCall(callID string) (*CallSession, error)
func (c *XMPPCore) DeclineCall(callID string) error
func (c *XMPPCore) SendLocation(chatID string, lat float64, lon float64) (*Message, error)
```

---

## Dependencies

- Standard library only: `net`, `crypto/tls`, `encoding/xml`, `crypto/aes`, `crypto/sha256`, `net/http`
- No CGo required
