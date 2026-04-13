# Delta Chat — Full Protocol Surface Checklist

**Last updated:** 2026-04-13 (Step 3)
**Current:** 164 methods, ~5,900 lines. IMAP/SMTP + Autocrypt + chat-over-email.
**Confirmed working:** 43 extended + 55 Core (all pass on nine.testrun.org, Step 2).
**Full API surface:** deltachat-core-rust C FFI + JSON-RPC API.
**Remaining:** ~105 methods listed below.

Only methods NOT yet implemented are listed.

---

## Configuration & Context (10 methods)

- [ ] SetConfig — Generic config setter (90+ config keys)
- [ ] GetConfig — Generic config getter
- [ ] BatchSetConfig — Set multiple config keys atomically
- [ ] BatchGetConfig — Get multiple config values
- [ ] SetConfigFromQR — Apply DCLOGIN QR code to config
- [ ] IsConfigured — Check if account is fully configured
- [ ] GetContextInfo — Get context info string (version, DB path, fingerprint, etc.)
- [ ] GetSystemInfo — System-level info (version, arch, OS)
- [ ] GetBlobDir — Get blob directory path
- [ ] CheckEmailValidity — Validate email address format

## Multi-Account Management (7 methods)

- [ ] AddAccount — Create new account in account manager
- [ ] RemoveAccount — Remove account from manager
- [ ] SelectAccount — Switch active account
- [ ] GetAllAccountIds — List all account IDs
- [ ] StartIoForAllAccounts — Start IMAP/SMTP for all accounts
- [ ] StopIoForAllAccounts — Stop I/O for all accounts
- [ ] StartIo / StopIo — Explicit I/O start/stop for current account

## Chat Queries and Properties (17 methods)

- [ ] GetChatMedia — Get all media messages by viewtype
- [ ] GetChatContacts — Get contact IDs for a chat
- [ ] GetPastContacts — Get contacts who left a group
- [ ] GetChatIdByContactId — Look up 1:1 chat ID by contact
- [ ] CreateChatByContactId — Create 1:1 chat by internal contact ID
- [ ] CanSend — Check if user can send to chat
- [ ] GetChatColor — Get color assigned to chat
- [ ] GetChatType — Get type (single/group/broadcast/mailing list)
- [ ] IsChatContactRequest — Check if pending contact request
- [ ] IsChatDeviceTalk — Check if device-messages chat
- [ ] IsChatSelfTalk — Check if Saved Messages chat
- [ ] IsChatUnpromoted — Check if group not yet sent to members
- [ ] IsChatEncrypted — Check if encryption enabled
- [ ] GetRemainingMuteDuration — Get remaining mute seconds
- [ ] GetMailingListAddr — Get posting address for mailing list
- [ ] DeleteChat — Delete entire chat
- [ ] MarkNoticedChat / MarkFreshChat — Mark as noticed/fresh (unread)

## Message Properties (30 methods)

- [ ] GetMessageInfo — Detailed info (delivery status, timestamps, errors)
- [ ] GetFreshMessageCount — Count unread messages in chat
- [ ] GetNextMessages / WaitNextMessages — Pull-based message retrieval (bots)
- [ ] GetFirstUnreadMessage — First unread message ID in chat
- [ ] SendDraft — Send currently set draft
- [ ] RemoveDraft — Clear draft from chat
- [ ] GetMessageSubject / SetMessageSubject — Email Subject field
- [ ] GetMessageDownloadState — Check partial download state
- [ ] GetMessageSortTimestamp — Get sorting timestamp
- [ ] GetMessageError — Get error text if send failed
- [ ] IsMessageBot — Check if sent by bot
- [ ] IsMessageEdited — Check if edited
- [ ] IsMessageForwarded — Check if forwarded
- [ ] IsMessageInfo — Check if system/info message
- [ ] GetMessageInfoType — Type of info message (added/removed/timer/etc.)
- [ ] GetMessageParent — Parent message in thread
- [ ] GetOriginalMsgId / GetSavedMsgId — Original/saved message ID
- [ ] HasMessageHtml — Check for HTML version
- [ ] HasMessageLocation — Check for attached location
- [ ] HasDeviatingTimestamp — Check timestamp deviation
- [ ] GetOverrideSenderName / SetOverrideSenderName — Override display name
- [ ] GetShowPadlock — Check encryption padlock display
- [ ] MessageSaveFile — Export message file to disk path
- [ ] SetMessageDimensions — Set width/height on image/video
- [ ] SetMessageDuration — Set duration on audio/video
- [ ] SetMessageLocation — Attach location to outgoing message
- [ ] SetMessageHtml — Set HTML body on outgoing message

## Contact Properties (13 methods)

- [ ] LookupContactByAddr — Find contact by email address
- [ ] GetContactEncryptionInfo — Encryption info for contact
- [ ] IsContactVerified — Check if SecureJoin verified
- [ ] IsContactBot — Check if bot
- [ ] IsContactKeyContact — Check Autocrypt key confirmed
- [ ] GetContactColor — Color assigned to contact
- [ ] GetContactAuthName — Autocrypt-authenticated name
- [ ] GetContactLastSeen — Last seen timestamp
- [ ] GetContactVerifierId — ID of verifying contact
- [ ] GetContactStatus — Status text
- [ ] ChangeContactName — Rename contact locally
- [ ] AddAddressBook — Bulk-import from address book (CSV)
- [ ] IsContactInChat — Check if contact is in a specific chat

## QR Code Operations (4 methods)

- [ ] GetSecureJoinQR — Generate SecureJoin QR data string
- [ ] GetSecureJoinQRSvg — Generate SecureJoin QR as SVG
- [ ] GetChatSecureJoinQRCodeSvg — Chat-specific SecureJoin QR SVG
- [ ] CreateQRSvg — Generate generic QR code SVG

## Backup Transfer (5 methods)

- [ ] ProvideBackup — Start providing backup for second device
- [ ] GetBackupQR — Get QR data for backup session
- [ ] GetBackupQRSvg — Get QR as SVG for backup
- [ ] ReceiveBackup — Receive backup from another device
- [ ] GetBackup — Download backup from provider

## Chatlist Operations (5 methods)

- [ ] GetChatlistEntries — Filtered/sorted chat list (archived, no-specials, etc.)
- [ ] GetChatlistItemsByEntries — Chat list items with summaries
- [ ] GetChatlistSummary — Last message preview, timestamp, unread count
- [ ] GetBasicChatInfo — Lightweight chat info (name, image, type)
- [ ] GetFullChatById — Full chat snapshot with all properties

## I/O and Network Control (4 methods)

- [ ] MaybeNetwork — Hint network available, trigger reconnect
- [ ] StopOngoingProcess — Cancel ongoing operation (configure, IMEX, SecureJoin)
- [ ] BackgroundFetch — One-shot background fetch (mobile push)
- [ ] StopBackgroundFetch — Stop background fetch

## OAuth2 (1 method)

- [ ] GetOAuth2URL — Get OAuth2 authorization URL for Gmail/Yandex

## Read Receipts (2 methods)

- [ ] GetReadReceiptCount — Count of read receipts for message
- [ ] GetReadReceipts — List of contacts who sent read receipts

## Connectivity HTML (1 method)

- [ ] GetConnectivityHtml — Detailed connectivity status as HTML

## Stock Strings (1 method)

- [ ] SetStockStrings — Override default English system message strings with localized versions

## Location Extras (2 methods)

- [ ] DeleteAllLocations — Delete all stored locations
- [ ] IsSendingLocationsToChat — Check if streaming active for specific chat
