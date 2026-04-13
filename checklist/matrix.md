# Matrix — Full Protocol Surface Checklist

**Last updated:** 2026-04-13 (Step 4)
**Current:** 308 methods, ~7,100 lines. SDK: mautrix-go. E2EE via goolm.
**Confirmed working:** 64 extended + 55 Core (all pass on local Dendrite, Step 2). 90 new methods added (Step 4), not yet tested.
**Remaining:** 0 methods — 100% protocol coverage (CS API v1.13-v1.18 + MSCs).

All methods implemented.

---

## Step 4 — Newly Implemented (90 methods) — NEEDS TESTING

### Auth & Session (7): RefreshToken, GetLoginToken, CheckRegistrationToken, SSORedirect, SSORedirectIdP, GetAuthMetadata, DeviceAuthGrant
### Server Discovery (3): GetClientWellKnown, GetSupportContacts, GetRTCTransports
### Room Management (4): GetRoomSummary, GetMutualRooms, TimestampToEvent, InviteBy3PID
### Events & Messaging (6): CreateDelayedEvent, UpdateDelayedEvent, SendLocationMessage, SendLiveLocation, SendEmoteMessage, EndPoll
### Extensible Profiles (4): GetProfileField, SetProfileField, DeleteProfileField, SetTimezone
### Admin & Moderation (5): SuspendUser, LockUser, SetInviteBlocking, SetPolicyRule, RedactAllUserEvents
### Authenticated Media (6): DownloadMediaAuth, DownloadMediaAuthFilename, DownloadThumbnailAuth, GetMediaConfigAuth, GetURLPreviewAuth, UploadMediaAsync (CreateMXCURI already existed)
### Sync (2): SlidingSync, SyncStateAfter
### MatrixRTC (6): SetRTCMemberState, SendRTCNotification, DeclineRTCSession, SendCallAssertedIdentity, SendCallNegotiate, SendGroupCallEncryptionKeys
### E2EE & Keys (8): GetKeyChanges, SetDehydratedDevice, GetDehydratedDevice, DeleteDehydratedDevice, GetDehydratedDeviceEvents, SendSecretRequest, SendSecretSend, StartQRVerification
### Push Rules (3): GetPushRuleActions, SetPushRuleActions, GetPushRuleEnabled
### Room State (4): GetRoomCreationEvent, GetRoomTombstone, GetThirdPartyInvites, SetCanonicalAlias
### Identity Server (3): ValidateEmailForAccount, ValidatePhoneForAccount, Delete3PIDByAddress
### Capabilities (4): GetForgetOnLeave, GetProfileFieldsCap, HandleUserLimitExceeded, GetNonCrossSignedExclusion
### Account Data (3): GetRecentEmoji, GetIgnoredUsers, GetFullyReadMarker
