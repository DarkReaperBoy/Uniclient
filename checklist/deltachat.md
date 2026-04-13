# Delta Chat — Full Protocol Surface Checklist

**Last updated:** 2026-04-13 (Steps 4-6)
**Current:** 283 methods, ~7,500 lines. IMAP/SMTP + Autocrypt + chat-over-email.
**Confirmed working:** 43 extended + 55 Core (all pass on nine.testrun.org, Step 2). 105 new methods added (Step 4), not yet tested.
**Steps 5-6:** Auth guards, unified dispatch, capability constants, 7 new Core methods.
**Remaining:** 0 methods — 100% protocol coverage.

All methods implemented.

---

## Step 4 — Newly Implemented (105 methods) — NEEDS TESTING

### Configuration & Context (10): SetConfig, GetConfig, BatchSetConfig, BatchGetConfig, SetConfigFromQR, IsConfigured, GetContextInfo, GetSystemInfo, GetBlobDir, CheckEmailValidity
### Multi-Account (7): AddAccount, RemoveAccount, SelectAccount, GetAllAccountIds, StartIoForAllAccounts, StopIoForAllAccounts, StartIo/StopIo
### Chat Properties (17): GetChatMedia, GetChatContacts, GetPastContacts, GetChatIdByContactId, CreateChatByContactId, CanSend, GetChatColor, GetChatType, IsChatContactRequest, IsChatDeviceTalk, IsChatSelfTalk, IsChatUnpromoted, IsChatEncrypted, GetRemainingMuteDuration, GetMailingListAddr, DeleteChat, MarkNoticedChat/MarkFreshChat
### Message Properties (30): GetMessageInfo, GetFreshMessageCount, GetNextMessages, WaitNextMessages, GetFirstUnreadMessage, SendDraft, RemoveDraft, GetMessageSubject/SetMessageSubject, GetMessageDownloadState, GetMessageSortTimestamp, GetMessageError, IsMessageBot, IsMessageEdited, IsMessageForwarded, IsMessageInfo, GetMessageInfoType, GetMessageParent, GetOriginalMsgId, GetSavedMsgId, HasMessageHtml, HasMessageLocation, HasDeviatingTimestamp, GetOverrideSenderName/SetOverrideSenderName, GetShowPadlock, MessageSaveFile, SetMessageDimensions, SetMessageDuration, SetMessageLocation, SetMessageHtml
### Contact Properties (13): LookupContactByAddr, GetContactEncryptionInfo, IsContactVerified, IsContactBot, IsContactKeyContact, GetContactColor, GetContactAuthName, GetContactLastSeen, GetContactVerifierId, GetContactStatus, ChangeContactName, AddAddressBook, IsContactInChat
### QR Code (4): GetSecureJoinQR, GetSecureJoinQRSvg, GetChatSecureJoinQRCodeSvg, CreateQRSvg
### Backup (5): ProvideBackup, GetBackupQR, GetBackupQRSvg, ReceiveBackup, GetBackup
### Chatlist (5): GetChatlistEntries, GetChatlistItemsByEntries, GetChatlistSummary, GetBasicChatInfo, GetFullChatById
### I/O (4): MaybeNetwork, StopOngoingProcess, BackgroundFetch, StopBackgroundFetch
### OAuth2 (1): GetOAuth2URL
### Read Receipts (2): GetReadReceiptCount, GetReadReceipts
### Connectivity (1): GetConnectivityHtml
### Stock Strings (1): SetStockStrings
### Location Extras (2): DeleteAllLocations, IsSendingLocationsToChat
