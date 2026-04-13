# Matrix — Full Protocol Surface Checklist

**Last updated:** 2026-04-13 (Step 3)
**Current:** 218 methods, ~5,900 lines. SDK: mautrix-go. E2EE via goolm.
**Confirmed working:** 64 extended + 55 Core (all pass on local Dendrite, Step 2).
**Full API surface:** Matrix CS API v1.13-v1.18 + MSCs.
**Remaining:** ~90 methods listed below.

Only methods NOT yet implemented are listed.

---

## Authentication & Session (7 methods)

- [ ] RefreshToken — `POST /_matrix/client/v3/refresh` — Exchange refresh token for new access token
- [ ] GetLoginToken — `POST /_matrix/client/v1/login/get_token` — Generate token for QR code login
- [ ] CheckRegistrationToken — `GET /_matrix/client/v1/register/m.login.registration_token/validity`
- [ ] SSORedirect — `GET /_matrix/client/v3/login/sso/redirect` — Redirect to SSO provider
- [ ] SSORedirectIdP — `GET /_matrix/client/v3/login/sso/redirect/{idpId}` — Redirect to specific IdP
- [ ] GetAuthMetadata — `GET /_matrix/client/v1/auth_metadata` — OAuth 2.0 discovery (v1.15)
- [ ] DeviceAuthGrant — RFC 8628 device authorization grant flow (v1.18)

## Server Discovery (3 methods)

- [ ] GetClientWellKnown — `GET /.well-known/matrix/client` — Discover homeserver URLs
- [ ] GetSupportContacts — `GET /.well-known/matrix/support` — Admin contact info (v1.10)
- [ ] GetRTCTransports — `GET /_matrix/client/v1/rtc/transports` — Discover MatrixRTC backends

## Room Management (4 methods)

- [ ] GetRoomSummary — `GET /_matrix/client/v1/room_summary/{roomIdOrAlias}` — Rich room info without joining (v1.15)
- [ ] GetMutualRooms — `GET /_matrix/client/v1/user/mutual_rooms/{userId}` — Rooms shared with user
- [ ] TimestampToEvent — `GET /_matrix/client/v1/rooms/{roomId}/timestamp_to_event` — Jump to date
- [ ] InviteBy3PID — `POST /_matrix/client/v3/rooms/{roomId}/invite` (3PID variant) — Invite by email/phone

## Events & Messaging (6 methods)

- [ ] CreateDelayedEvent — `POST /_matrix/client/v1/delayed_events` — Schedule delayed events (v1.18)
- [ ] UpdateDelayedEvent — `PUT /_matrix/client/v1/delayed_events/{delayId}` — Update/cancel delayed event
- [ ] SendLocationMessage — `m.room.message` with `msgtype: m.location` — Share static location
- [ ] SendLiveLocation — `m.beacon_info` / `m.beacon` state events — Stream live location
- [ ] SendEmoteMessage — `m.room.message` with `msgtype: m.emote` — /me action messages
- [ ] EndPoll — `m.poll.end` event — End a poll and display results

## Extensible Profiles (4 methods, v1.16)

- [ ] GetProfileField — `GET /_matrix/client/v3/profile/{userId}/{field_key}` — Read custom field
- [ ] SetProfileField — `PUT /_matrix/client/v3/profile/{userId}/{field_key}` — Write custom field
- [ ] DeleteProfileField — `DELETE /_matrix/client/v3/profile/{userId}/{field_key}` — Remove field
- [ ] SetTimezone — `us.cloke.msc4175.tz` profile field — User timezone (v1.16)

## Admin & Moderation (5 methods, v1.14-v1.18)

- [ ] SuspendUser — `GET/PUT /_matrix/client/v1/admin/suspend/{userId}` — Get/set account suspension
- [ ] LockUser — `GET/PUT /_matrix/client/v1/admin/lock/{userId}` — Get/set account lock
- [ ] SetInviteBlocking — Account data toggle (MSC4380) — Block all incoming invites (v1.18)
- [ ] SetPolicyRule — `m.policy.rule.user/room/server` state events — Moderation ban lists
- [ ] RedactAllUserEvents — `POST /_matrix/client/v1/rooms/{roomId}/redact/{userId}` — Batch redact (unstable)

## Authenticated Media (7 methods, v1.11+)

- [ ] DownloadMediaAuth — `GET /_matrix/client/v1/media/download/{serverName}/{mediaId}` — Authenticated download
- [ ] DownloadMediaAuthFilename — `GET /_matrix/client/v1/media/download/{serverName}/{mediaId}/{fileName}`
- [ ] DownloadThumbnailAuth — `GET /_matrix/client/v1/media/thumbnail/{serverName}/{mediaId}`
- [ ] GetMediaConfigAuth — `GET /_matrix/client/v1/media/config` — Authenticated media config
- [ ] GetURLPreviewAuth — `GET /_matrix/client/v1/media/preview_url` — Authenticated URL preview
- [ ] CreateMXCURI — `POST /_matrix/media/v1/create` — Async upload: create MXC URI first
- [ ] UploadMediaAsync — `PUT /_matrix/media/v3/upload/{serverName}/{mediaId}` — Upload to pre-created MXC

## Sync Improvements (2 methods)

- [ ] SlidingSync — `POST /_matrix/client/unstable/org.matrix.msc3575/sync` — Simplified Sliding Sync
- [ ] SyncStateAfter — `/sync` with `use_state_after` param — State after timeline gap (v1.16)

## MatrixRTC / Group Calls (6 methods)

- [ ] SetRTCMemberState — `org.matrix.msc4143.rtc.member` state event — Declare RTC participation
- [ ] SendRTCNotification — `org.matrix.msc4075.rtc.notification` — Notify about incoming RTC session
- [ ] DeclineRTCSession — `org.matrix.msc4310.rtc.decline` — Decline incoming RTC session
- [ ] SendCallAssertedIdentity — `m.call.asserted_identity` — Assert call participant identity
- [ ] SendCallNegotiate — `m.call.negotiate` — Mid-call SDP renegotiation
- [ ] SendGroupCallEncryptionKeys — Group call E2EE key distribution

## E2EE & Key Management (8 methods)

- [ ] GetKeyChanges — `GET /_matrix/client/v3/keys/changes` — Users with changed device keys
- [ ] SetDehydratedDevice — `PUT /_matrix/client/unstable/org.matrix.msc3814/dehydrated_device`
- [ ] GetDehydratedDevice — `GET /_matrix/client/unstable/org.matrix.msc3814/dehydrated_device`
- [ ] DeleteDehydratedDevice — `DELETE /_matrix/client/unstable/org.matrix.msc3814/dehydrated_device`
- [ ] GetDehydratedDeviceEvents — Retrieve to-device events for dehydrated device
- [ ] SendSecretRequest — `m.secret.request` to-device event
- [ ] SendSecretSend — `m.secret.send` to-device event
- [ ] StartQRVerification — `m.key.verification.start` with `m.reciprocate.v1` — QR code verification

## Push Rules Extended (3 methods)

- [ ] GetPushRuleActions — `GET /_matrix/client/v3/pushrules/global/{kind}/{ruleId}/actions`
- [ ] SetPushRuleActions — `PUT /_matrix/client/v3/pushrules/global/{kind}/{ruleId}/actions`
- [ ] GetPushRuleEnabled — `GET /_matrix/client/v3/pushrules/global/{kind}/{ruleId}/enabled`

## Room State Events (4 methods)

- [ ] GetRoomCreationEvent — Parse `m.room.create` state event (creator, version, predecessor)
- [ ] GetRoomTombstone — Parse `m.room.tombstone` (replacement room after upgrade)
- [ ] GetThirdPartyInvites — Parse `m.room.third_party_invite` state events
- [ ] SetCanonicalAlias — `m.room.canonical_alias` — Set primary alias and alt_aliases

## Identity Server (3 methods)

- [ ] ValidateEmailForAccount — `POST /_matrix/client/v3/account/3pid/email/requestToken`
- [ ] ValidatePhoneForAccount — `POST /_matrix/client/v3/account/3pid/msisdn/requestToken`
- [ ] Delete3PIDByAddress — Alternative DELETE for removing 3PIDs

## Capabilities (4 methods, v1.16-v1.18)

- [ ] GetForgetOnLeave — `m.forget_forced_upon_leave` capability
- [ ] GetProfileFieldsCap — `m.profile_fields` capability — Supported profile fields
- [ ] HandleUserLimitExceeded — `M_USER_LIMIT_EXCEEDED` error code (v1.18)
- [ ] GetNonCrossSignedExclusion — Recommendation MSC4153 (v1.18)

## Account Data Events (3 methods)

- [ ] GetRecentEmoji — `m.recent_emoji` account data (v1.18)
- [ ] GetIgnoredUsers — `m.ignored_user_list` — Full ignore list access
- [ ] GetFullyReadMarker — `m.fully_read` room account data
