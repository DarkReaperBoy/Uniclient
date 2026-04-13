# XMPP — Full Protocol Surface Checklist

**Last updated:** 2026-04-13 (Step 3)
**Current:** 322 methods, ~6,290 lines. Pure Go stdlib. SASL2/FAST, OMEMO, MUC, MIX, Jingle, MAM.
**Confirmed working:** 101 extended + 55 Core (all pass on yax.im Prosody, Step 2).
**Full surface:** RFC 6120/6121 + ~200 XEPs.
**Remaining:** ~120 XEPs listed below.

Only XEPs/features NOT yet implemented are listed.

---

## Connection & Authentication (10 XEPs)

- [ ] XEP-0368 — SRV Records for XMPP over TLS — Direct TLS via `xmpps-client` SRV (Compliance 2023)
- [ ] XEP-0474 — SASL SCRAM Downgrade Protection — Protect against mechanism downgrade
- [ ] XEP-0397 — Instant Stream Resumption — Resume streams instantly after disconnect
- [ ] XEP-0487 — Host Meta 2 — Improved alternative connection discovery
- [ ] XEP-0493 — OAuth Client Login — OAUTHBEARER SASL mechanism
- [ ] XEP-0494 — Client Access Management — Revoke per-client access
- [ ] XEP-0495 — Happy Eyeballs — Parallel A/AAAA for faster connections
- [ ] XEP-0509 — Initial Authentication Pipelining — Single-round-trip setup with SASL2
- [ ] XEP-0478 — Stream Limits Advertisement — Server advertises stanza size limits
- [ ] XEP-0305 — XMPP Quickstart — TLS session resumption + caps

## Messaging (12 XEPs)

- [ ] XEP-0424 — Message Retraction — Unsend messages (Compliance 2023)
- [ ] XEP-0393 — Message Styling — `*bold*`, `_italic_`, `` `code` ``, `~strike~` (Compliance 2023)
- [ ] XEP-0382 — Spoiler Messages — Hidden content with optional hint
- [ ] XEP-0422 — Message Fastening — Generic wrapper for fastening payloads
- [ ] XEP-0432 — Simple JSON Messaging — JSON payloads in messages
- [ ] XEP-0439 — Quick Response — Predefined response buttons
- [ ] XEP-0481 — Content Types in Messages — MIME content type (text/markdown, etc.)
- [ ] XEP-0301 — In-Band Real-Time Text — Character-by-character transmission
- [ ] XEP-0359 — Unique and Stable Stanza IDs — Server-assigned message IDs (Compliance 2023)
- [ ] XEP-0430 — Inbox — Server-side unread counts per conversation
- [ ] XEP-0431 — Full Text Search in MAM — Server-side full-text search
- [ ] XEP-0435 — Reminders — Schedule reminders for messages

## MUC Extensions (11 XEPs)

- [ ] XEP-0249 — Direct MUC Invitations — Simpler than mediated invites
- [ ] XEP-0317 — Hats — Visual roles/badges for occupants
- [ ] XEP-0433 — Extended Channel Search — Search MUC/MIX across domains (Compliance 2023)
- [ ] XEP-0436 — MUC Presence Versioning — Incremental presence updates
- [ ] XEP-0437 — Room Activity Indicators — Lightweight activity without full join
- [ ] XEP-0452 — MUC Mention Notifications — @mentions without joining
- [ ] XEP-0463 — MUC Affiliations Versioning — Incremental affiliation updates
- [ ] XEP-0486 — MUC Avatars — Room avatars
- [ ] XEP-0488 — MUC Token Invite — Generate/revoke invite tokens
- [ ] XEP-0500 — MUC Slow Mode — Rate-limit messages per user
- [ ] XEP-0502 — MUC Activity Indicator — Approximate messages-per-hour

## MIX Extensions (5 XEPs)

- [ ] XEP-0403 — MIX-PRESENCE — Presence sharing among MIX participants
- [ ] XEP-0404 — MIX-ANON — Hidden real JIDs, private messaging
- [ ] XEP-0405 — MIX-PAM — Server-side MIX channel list management
- [ ] XEP-0406 — MIX-ADMIN — MIX administration and configuration
- [ ] XEP-0407 — MIX-MISC — Avatar, nick registration, retraction, invitations

## Jingle / Calls (18 XEPs)

- [ ] XEP-0167 — Jingle RTP Sessions — Full codec params, SDP mapping
- [ ] XEP-0177 — Jingle Raw UDP Transport — Fallback when ICE unavailable
- [ ] XEP-0262 — ZRTP in Jingle — Voice encryption key agreement
- [ ] XEP-0266 — Codecs for Jingle Audio — Opus, Speex, G.711 guidance
- [ ] XEP-0272 — Multiparty Jingle (Muji) — Mesh multiparty calls
- [ ] XEP-0298 — Conference Info (Coin) — Conference state notifications
- [ ] XEP-0299 — Codecs for Jingle Video — VP8, H.264 guidance
- [ ] XEP-0320 — DTLS-SRTP in Jingle — DTLS fingerprint for SRTP
- [ ] XEP-0338 — Jingle Grouping Framework — SDP bundle for WebRTC interop
- [ ] XEP-0339 — Source-Specific Media Attributes — Per-source SSRC
- [ ] XEP-0343 — WebRTC DataChannels — DTLS/SCTP data channels
- [ ] XEP-0353 — Jingle Message Initiation (ringing) — Add ringing signal
- [ ] XEP-0358 — Publishing Available Jingle Sessions — Advertise joinable sessions
- [ ] XEP-0371 — Jingle ICE Transport (Trickle ICE) — Updated ICE transport
- [ ] XEP-0391 — Jingle Encrypted Transports (JET) — E2E-encrypt transport data
- [ ] XEP-0396 — JET-OMEMO — OMEMO encryption for Jingle file transfers
- [ ] XEP-0482 — Call Invites — Invite to calls via Jingle or URI
- [ ] XEP-0507 — Jingle Content Category — Distinguish webcam vs screen share

## File Sharing & Media (5 XEPs)

- [ ] XEP-0264 — Jingle Content Thumbnails — Thumbnails on file offers
- [ ] XEP-0385 — Stateless Inline Media Sharing (SIMS) — Inline media display
- [ ] XEP-0446 — File Metadata Element — Standalone file metadata
- [ ] XEP-0498 — PubSub File Sharing — File/directory sharing via PubSub
- [ ] XEP-0505 — Data Forms File Input — File upload in data forms

## PubSub Extensions (15 XEPs)

- [ ] XEP-0163 — Personal Eventing Protocol (PEP) — Explicit PEP node management
- [ ] XEP-0222 — Persistent Storage of Public Data — Best practices
- [ ] XEP-0223 — Persistent Storage of Private Data — Best practices
- [ ] XEP-0248 — PubSub Collection Nodes — Hierarchical node relationships
- [ ] XEP-0277 — Microblogging — Atom-based social feed via PubSub
- [ ] XEP-0442 — PubSub MAM — MAM queries on PubSub archives
- [ ] XEP-0460 — PubSub Caching Hints — Client-side caching hints
- [ ] XEP-0462 — PubSub Type Filtering — Filter disco#items by node type
- [ ] XEP-0465 — PubSub Public Subscriptions — Publicly visible subscriptions
- [ ] XEP-0470 — PubSub Attachments — Reactions/comments on PubSub items
- [ ] XEP-0472 — PubSub Social Feed — Generic social feed framework
- [ ] XEP-0473 — OpenPGP for PubSub — E2E-encrypt PubSub content
- [ ] XEP-0485 — PubSub Server Information — Discover server metadata
- [ ] XEP-0496 — PubSub Node Relationships — Parent/child relationships
- [ ] XEP-0395 — Atomically Compare-And-Publish — Atomic CAS on PubSub items

## Service Discovery (3 XEPs)

- [ ] XEP-0128 — Service Discovery Extensions — Extended info in disco#info
- [ ] XEP-0390 — Entity Capabilities 2.0 — Improved caps hashing (replaces XEP-0115)
- [ ] XEP-0453 — DOAP Usage — Machine-readable capability descriptions

## Encryption (1 XEP)

- [ ] XEP-0450 — Automatic Trust Management (ATM) — Auto-establish OMEMO trust

## User Profile & Social (4 XEPs)

- [ ] XEP-0392 — Consistent Color Generation — Colors from JIDs
- [ ] XEP-0398 — Avatar Conversion — Server-side XEP-0084 <-> XEP-0153
- [ ] XEP-0152 — Reachability Addresses — Phone/SIP URIs via PEP
- [ ] XEP-0153 — vCard-Based Avatars — Full presence-hash avatar protocol

## Notification & Sync (2 XEPs)

- [ ] XEP-0492 — Chat Notification Settings — Per-conversation notification prefs
- [ ] XEP-0351 — Server-Side Notification Filtering

## Server Interaction (10 XEPs)

- [ ] XEP-0055 — Jabber Search (extended) — Full data forms results
- [ ] XEP-0144 — Roster Item Exchange — Share/recommend roster items
- [ ] XEP-0158 — CAPTCHA Forms — Handle CAPTCHA during registration
- [ ] XEP-0227 — Portable Import/Export — Account data import/export
- [ ] XEP-0237 — Roster Versioning — Incremental roster sync
- [ ] XEP-0401 — Easy User Onboarding — Generate invitation URIs
- [ ] XEP-0445 — Pre-Authenticated IBR — Token-gated registration
- [ ] XEP-0455 — Service Outage Status — Server status monitoring
- [ ] XEP-0504 — Data Policy — Data retention/jurisdiction info
- [ ] XEP-0411 — Bookmarks Conversion — XEP-0049 <-> XEP-0402 server-side

## Newer/Experimental (10 XEPs)

- [ ] XEP-0491 — WebXDC — Interactive HTML/JS widgets in chat
- [ ] XEP-0503 — Server-side Spaces — Channel organization (Discord-like categories)
- [ ] XEP-0508 — Forums — Threaded discussions over PubSub
- [ ] XEP-0510 — E2E-Encrypted Contacts Metadata
- [ ] XEP-0511 — Link Metadata — Rich link previews
- [ ] XEP-0483 — HTTP Online Meetings — Request Jitsi/etc. URLs
- [ ] XEP-0383 — Burner JIDs — Temporary anonymous identifiers
- [ ] XEP-0332 — HTTP over XMPP Transport — Proxy HTTP over XMPP
- [ ] XEP-0297 — Stanza Forwarding — Standard stanza encapsulation
- [ ] XEP-0506 — No-reply JIDs — Advertise non-accepting JIDs

## Miscellaneous (5 XEPs)

- [ ] XEP-0059 — Result Set Management — Pagination for large results
- [ ] XEP-0155 — Stanza Session Negotiation — Pre-communication negotiation
- [ ] XEP-0231 — Bits of Binary — Inline small binary data
- [ ] XEP-0300 — Cryptographic Hash Functions — Standardized hash element
- [ ] XEP-0438 — Password Hashing — Best practices
