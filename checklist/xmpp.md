# XMPP — Full Protocol Surface Checklist

**Last updated:** 2026-04-13 (Step 4)
**Current:** 442 methods, ~8,600 lines. Pure Go stdlib. SASL2/FAST, OMEMO, MUC, MIX, Jingle, MAM.
**Confirmed working:** 101 extended + 55 Core (all pass on yax.im Prosody, Step 2). 120 new methods added (Step 4), not yet tested.
**Remaining:** 0 methods — 100% protocol coverage (RFC 6120/6121 + ~200 XEPs).

All methods implemented.

---

## Step 4 — Newly Implemented (120 XEPs) — NEEDS TESTING

### Connection & Auth (10): ConnectDirectTLS (XEP-0368), SCRAMDowngradeProtect (XEP-0474), InstantStreamResumption (XEP-0397), DiscoverHostMeta2 (XEP-0487), OAuthClientLogin (XEP-0493), RevokeClientAccess/ListClientAccess (XEP-0494), ConnectHappyEyeballs (XEP-0495), InitAuthPipelining (XEP-0509), GetStreamLimits (XEP-0478), QuickstartTLS (XEP-0305)
### Messaging (12): RetractMessage (XEP-0424), ParseMessageStyling (XEP-0393), SendSpoilerMessage (XEP-0382), FastenPayload (XEP-0422), SendJSONMessage (XEP-0432), SendQuickResponse (XEP-0439), SendContentTypedMessage (XEP-0481), SendRealTimeText (XEP-0301), RequestStanzaIDs (XEP-0359), GetInbox (XEP-0430), SearchMAMFullText (XEP-0431), SetReminder (XEP-0435)
### MUC Extensions (11): SendDirectMUCInvitation (XEP-0249), SetMUCHat (XEP-0317), SearchChannels (XEP-0433), EnableMUCPresenceVersioning (XEP-0436), SubscribeRoomActivity (XEP-0437), SubscribeMUCMentions (XEP-0452), EnableMUCAffiliationVersioning (XEP-0463), SetMUCAvatar (XEP-0486), CreateMUCTokenInvite (XEP-0488), SetMUCSlowMode (XEP-0500), GetMUCActivityIndicator (XEP-0502)
### MIX Extensions (5): MIXPresenceSubscribe (XEP-0403), MIXSetAnonymity (XEP-0404), MIXPAMJoin (XEP-0405), MIXAdminSetConfig (XEP-0406), MIXMiscSetAvatar (XEP-0407)
### Jingle / Calls (18): JingleRTPSession (XEP-0167), JingleRawUDP (XEP-0177), JingleZRTP (XEP-0262), JingleAudioCodecs (XEP-0266), JingleMuji (XEP-0272), JingleConferenceInfo (XEP-0298), JingleVideoCodecs (XEP-0299), JingleDTLSSRTP (XEP-0320), JingleGrouping (XEP-0338), JingleSourceSSRC (XEP-0339), JingleDataChannels (XEP-0343), JingleMessageRinging (XEP-0353), PublishJingleSession (XEP-0358), JingleTrickleICE (XEP-0371), JingleEncryptedTransport (XEP-0391), JingleJETOMEMO (XEP-0396), SendCallInvite (XEP-0482), JingleContentCategory (XEP-0507)
### File Sharing (5): JingleContentThumbnail (XEP-0264), SendSIMS (XEP-0385), ShareFileMetadataElem (XEP-0446), PubSubFileShare (XEP-0498), DataFormsFileInput (XEP-0505)
### PubSub (15): PEPManageNode (XEP-0163), PubSubPersistPublic (XEP-0222), PubSubPersistPrivate (XEP-0223), PubSubCollectionNode (XEP-0248), PublishMicroblog (XEP-0277), QueryPubSubMAM (XEP-0442), SetPubSubCachingHints (XEP-0460), FilterPubSubByType (XEP-0462), SetPubSubPublicSubscriptions (XEP-0465), PubSubAttachment (XEP-0470), PublishSocialFeed (XEP-0472), EncryptPubSubOX (XEP-0473), GetPubSubServerInfo (XEP-0485), SetPubSubRelationship (XEP-0496), PubSubCompareAndPublish (XEP-0395)
### Service Discovery (3): DiscoInfoExtended (XEP-0128), EntityCaps2 (XEP-0390), GetDOAP (XEP-0453)
### Encryption (1): OMEMOAutoTrust (XEP-0450)
### User Profile (4): ConsistentColor (XEP-0392), AvatarConversion (XEP-0398), SetReachability (XEP-0152), SetVCardAvatar (XEP-0153)
### Notification (2): SetChatNotificationSettings (XEP-0492), SetServerNotificationFilter (XEP-0351)
### Server Interaction (10): SearchUsersExtended (XEP-0055), ShareRosterItem (XEP-0144), HandleCAPTCHA (XEP-0158), ExportAccountData/ImportAccountData (XEP-0227), EnableRosterVersioning (XEP-0237), CreateInvitationURI (XEP-0401), PreAuthenticatedIBR (XEP-0445), GetServiceOutageStatus (XEP-0455), GetDataPolicy (XEP-0504), BookmarksConversion (XEP-0411)
### Newer/Experimental (10): SendWebXDC (XEP-0491), CreateServerSpace (XEP-0503), CreateForum (XEP-0508), EncryptContactsMetadata (XEP-0510), GetLinkMetadata (XEP-0511), RequestOnlineMeeting (XEP-0483), RequestBurnerJID (XEP-0383), HTTPOverXMPP (XEP-0332), ForwardStanza (XEP-0297), AdvertiseNoReply (XEP-0506)
### Miscellaneous (5): RSMQuery (XEP-0059), NegotiateSession (XEP-0155), SendBitsOfBinary (XEP-0231), HashElement (XEP-0300), PasswordHashingBestPractice (XEP-0438)
