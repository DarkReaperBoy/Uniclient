# XMPP Protocol Implementation Reference

Pure Go implementation. stdlib only: `encoding/xml`, `crypto/tls`, `crypto/sha1`, `crypto/sha256`, `crypto/hmac`, `encoding/base64`, `net`, `bufio`.

## Core RFCs

- **RFC 6120** — XMPP Core: TCP binding, TLS, SASL, stream management, stanza routing
- **RFC 6121** — XMPP IM: roster, presence, messaging
- **RFC 7622** — XMPP Address Format (JID: localpart@domainpart/resourcepart)

## Connection Flow

1. TCP connect to `domain:5222` (or SRV lookup `_xmpp-client._tcp.domain`)
2. Send stream header: `<stream:stream to='domain' xmlns='jabber:client' xmlns:stream='http://etherx.jabber.org/streams' version='1.0'>`
3. Server responds with stream header + `<stream:features>`
4. **STARTTLS** (XEP-0170): `<starttls xmlns='urn:ietf:params:xml:ns:xmpp-tls'/>` → upgrade to TLS → restart stream
5. **SASL auth**: `<auth xmlns='urn:ietf:params:xml:ns:xmpp-sasl' mechanism='PLAIN'>base64(authzid\0authcid\0password)</auth>`
   - SCRAM-SHA-1: challenge-response (client-first → server-challenge → client-final → server-final)
   - SCRAM-SHA-256: same flow, SHA-256
6. Restart stream after SASL success
7. **Resource binding**: IQ set `<bind xmlns='urn:ietf:params:xml:ns:xmpp-bind'><resource>uniclient</resource></bind>`
8. Send initial presence: `<presence/>`
9. Request roster: IQ get `<query xmlns='jabber:iq:roster'/>`

## Stanza Types

All XMPP communication uses three stanza types:

### Message (`<message>`)
```xml
<message to='user@domain' type='chat' id='msg1'>
  <body>Hello</body>
  <thread>thread-id</thread>
  <subject>Subject</subject>
</message>
```
Types: `chat` (1:1), `groupchat` (MUC), `headline` (alerts), `normal` (email-like), `error`

### Presence (`<presence>`)
```xml
<presence>
  <show>away</show>        <!-- away, xa, dnd, chat -->
  <status>Be right back</status>
  <priority>5</priority>
</presence>
```
Types: (none)=available, `unavailable`, `subscribe`, `subscribed`, `unsubscribe`, `unsubscribed`, `probe`, `error`

### IQ (Info/Query) (`<iq>`)
```xml
<iq type='get' to='domain' id='disco1'>
  <query xmlns='http://jabber.org/protocol/disco#info'/>
</iq>
```
Types: `get`, `set`, `result`, `error`

## XML Stream Parsing

XMPP uses a single XML document per direction. The root `<stream:stream>` never closes until disconnect. Use `xml.NewDecoder` in streaming mode — read tokens one at a time, match StartElement for stanza begins, then `DecodeElement` for the full stanza body.

**Key quirk**: The stream header is an opening tag with no matching close. Standard xml.Decoder handles this if we read the initial StartElement separately and then loop on child elements.

## Key XEPs Implemented

### Messaging
- **XEP-0184** Message Delivery Receipts: `<request xmlns='urn:xmpp:receipts'/>` / `<received id='msg-id'/>`
- **XEP-0085** Chat State Notifications: `<composing/>`, `<active/>`, `<paused/>`, `<inactive/>`, `<gone/>` in xmlns `http://jabber.org/protocol/chatstates`
- **XEP-0308** Last Message Correction: `<replace id='original-id' xmlns='urn:xmpp:message-correct:0'/>`
- **XEP-0280** Message Carbons: IQ enable `urn:xmpp:carbons:2`
- **XEP-0333** Displayed Markers: `<displayed id='msg-id' xmlns='urn:xmpp:chat-markers:0'/>`
- **XEP-0334** Message Processing Hints: `<no-store/>`, `<no-copy/>`, `<store/>` in xmlns `urn:xmpp:hints`
- **XEP-0066** Out of Band Data: `<x xmlns='jabber:x:oob'><url>...</url></x>`
- **XEP-0372** References: message references (mentions, URIs)
- **XEP-0461** Message Replies: `<reply to='jid' id='msg-id' xmlns='urn:xmpp:reply:0'/>`
- **XEP-0444** Message Reactions: `<reactions id='msg-id' xmlns='urn:xmpp:reactions:0'><reaction>👍</reaction></reactions>`

### MUC (XEP-0045)
- Join: `<presence to='room@conference.domain/nick'><x xmlns='http://jabber.org/protocol/muc'/></presence>`
- Leave: `<presence to='room@conference.domain/nick' type='unavailable'/>`
- Subject: `<message to='room@conference.domain' type='groupchat'><subject>New topic</subject></message>`
- Invite: `<message to='room@conference.domain'><x xmlns='http://jabber.org/protocol/muc#user'><invite to='user@domain'/></x></message>`
- Kick: IQ set `<query xmlns='http://jabber.org/protocol/muc#admin'><item nick='nick' role='none'><reason>...</reason></item></query>`
- Ban: IQ set affiliation=outcast
- Config: IQ get/set `http://jabber.org/protocol/muc#owner`
- Roles: none, visitor, participant, moderator
- Affiliations: none, member, admin, owner, outcast

### Service Discovery (XEP-0030)
- `disco#info`: IQ get `http://jabber.org/protocol/disco#info` → identities + features
- `disco#items`: IQ get `http://jabber.org/protocol/disco#items` → child items/services

### Roster (RFC 6121)
- Get: IQ get `jabber:iq:roster`
- Add/Update: IQ set with `<item jid='...' name='...'><group>Friends</group></item>`
- Remove: IQ set with `<item jid='...' subscription='remove'/>`
- Versioning (XEP-0237): `<query ver='stored-ver'/>` → server sends only changes

### File Transfer
- **XEP-0363** HTTP File Upload: IQ get `urn:xmpp:http:upload:0` → PUT url + GET url
- **XEP-0066** OOB: send URL in message

### PubSub (XEP-0060)
- Create node: IQ set `http://jabber.org/protocol/pubsub` `<create node='...'/>`
- Publish: `<publish node='...'><item id='...'><entry>...</entry></item></publish>`
- Subscribe: `<subscribe node='...' jid='...'/>`
- Retract: `<retract node='...'><item id='...'/></retract>`
- Get items: IQ get `<items node='...'/>`

### PEP (XEP-0163) — Personal Eventing Protocol
PEP is PubSub on the user's bare JID. Used for:
- **XEP-0084** User Avatar: node `urn:xmpp:avatar:data` + `urn:xmpp:avatar:metadata`
- **XEP-0107** User Mood: node `http://jabber.org/protocol/mood`
- **XEP-0108** User Activity: node `http://jabber.org/protocol/activity`
- **XEP-0118** User Tune: node `http://jabber.org/protocol/tune`
- **XEP-0080** User Geolocation: node `http://jabber.org/protocol/geoloc`

### Blocking (XEP-0191)
- Block: IQ set `urn:xmpp:blocking` `<block><item jid='...'/></block>`
- Unblock: `<unblock><item jid='...'/></unblock>`
- Get blocklist: IQ get `<blocklist/>`

### Bookmarks (XEP-0048 / XEP-0402)
- Store in private XML storage or PEP node `urn:xmpp:bookmarks:1`
- Conference bookmark: `<conference jid='room@conf' autojoin='true' name='Room'><nick>me</nick></conference>`

### MAM — Message Archive Management (XEP-0313)
- Query: IQ set `urn:xmpp:mam:2` with data form filter (jid, start, end)
- Results come as `<message>` with `<result>` wrapper containing `<forwarded>` stanza
- Pagination via RSM (XEP-0059): `<set xmlns='http://jabber.org/protocol/rsm'><max>50</max><after>item-id</after></set>`

### vCard (XEP-0054 / XEP-0292)
- Get: IQ get `vcard-temp` → `<vCard xmlns='vcard-temp'>`
- Set: IQ set with full vCard XML
- Fields: FN, N, NICKNAME, EMAIL, TEL, ADR, URL, PHOTO, etc.

### Stream Management (XEP-0198)
- Enable: `<enable xmlns='urn:xmpp:sm:3' resume='true'/>`
- Ack request: `<r xmlns='urn:xmpp:sm:3'/>`
- Ack response: `<a xmlns='urn:xmpp:sm:3' h='N'/>`
- Resume: reconnect, send `<resume xmlns='urn:xmpp:sm:3' h='N' previd='id'/>`

### Ping (XEP-0199)
- IQ get `urn:xmpp:ping` → IQ result (empty)

### Entity Capabilities (XEP-0115)
- Presence includes `<c xmlns='http://jabber.org/protocol/caps' hash='sha-1' node='...' ver='base64-hash'/>`
- Hash computed from sorted disco#info features + identities

### Registration (XEP-0077)
- IQ get `jabber:iq:register` → required fields
- IQ set with username/password

### Software Version (XEP-0092)
- IQ get `jabber:iq:version` → name, version, os

### Last Activity (XEP-0012)
- IQ get `jabber:iq:last` → seconds since last activity

### Entity Time (XEP-0202)
- IQ get `urn:xmpp:time` → utc + tzo

### Client State Indication (XEP-0352)
- `<active xmlns='urn:xmpp:csi:0'/>` / `<inactive xmlns='urn:xmpp:csi:0'/>`

### Jingle (XEP-0166) — Voice/Video Calls
- Session initiate: IQ set `urn:xmpp:jingle:1` action=`session-initiate`
- Content: `<content creator='initiator' name='voice'>`
  - Description: `<description xmlns='urn:xmpp:jingle:apps:rtp:1' media='audio'>`
  - Transport: `<transport xmlns='urn:xmpp:jingle:transports:ice-udp:1'>`
- Session accept: action=`session-accept`
- Transport info: action=`transport-info` (ICE candidates)
- Session terminate: action=`session-terminate`
- **XEP-0167** RTP Sessions: codec negotiation (Opus, VP8, H.264)
- **XEP-0176** ICE-UDP Transport: ICE candidates, STUN/TURN
- **XEP-0215** External Service Discovery: STUN/TURN server credentials

### OMEMO (XEP-0384) — E2EE
- Device list published via PEP node `eu.siacs.conversations.axolotl.devicelist`
- Key bundles at `eu.siacs.conversations.axolotl.bundles:DEVICE_ID`
- Double Ratchet (Signal Protocol) for session encryption
- Note: Full OMEMO requires libsignal-protocol-go or similar — stub for now

## SASL Mechanisms

### PLAIN
`base64("\0" + username + "\0" + password)`

### SCRAM-SHA-1 / SCRAM-SHA-256
1. Client sends: `n,,n=username,r=client-nonce`
2. Server sends: `r=client-nonce+server-nonce,s=salt-base64,i=iterations`
3. Client computes: SaltedPassword = Hi(password, salt, iterations)
   - ClientKey = HMAC(SaltedPassword, "Client Key")
   - StoredKey = H(ClientKey)
   - AuthMessage = client-first-bare + "," + server-first + "," + client-final-without-proof
   - ClientSignature = HMAC(StoredKey, AuthMessage)
   - ClientProof = ClientKey XOR ClientSignature
4. Client sends: `c=biws,r=combined-nonce,p=proof-base64`
5. Server verifies and sends: `v=server-signature-base64`

## JID Format
- Bare JID: `localpart@domainpart` (e.g., `user@example.com`)
- Full JID: `localpart@domainpart/resourcepart` (e.g., `user@example.com/uniclient`)
- Domain JID: `domainpart` (e.g., `conference.example.com`)

## Public Test Servers
- yax.im (Prosody) — used for all extended method testing. Supports XEP-0077 in-band registration (STARTTLS required first). Account: `uctest1776076689@yax.im`.
- conversations.im (registration open)
- jabber.de
- jabber.ccc.de
- xmpp.jp
- Sure.im
- 404.city

## Testing Findings (2026-04-13)

- **XEP-0077 In-Band Registration on yax.im**: requires STARTTLS upgrade before registration IQ. Server advertises `<register xmlns='http://jabber.org/features/iq-register'/>` in TLS features. Registration uses GET to discover fields, then SET with username/password. Server responds with self-closing `<iq type='result' id='...'/>` (no `</iq>` closing tag).
- **IQ timeout pattern**: Many XEPs not supported by yax.im (Prosody) cause 30s IQ timeouts instead of quick error responses. This makes test suites slow (~460s for 101 methods). Server-unsupported features: privacy lists (XEP-0016), flexible offline (XEP-0013), Jabber Search (XEP-0055), private XML (XEP-0049).
- **IBB/S5B self-JID deadlock**: Sending IQs to self (e.g., OpenIBBSession to own JID) creates a deadlock — the server relays the IQ back as an incoming stanza, but the client's readLoop doesn't auto-respond, so sendIQSync hangs forever. Use a non-existent JID for testing.
- **BOSH/WebSocket**: yax.im advertises alternative connections via XRD (`/.well-known/host-meta`). BOSH at `https://xmpp.yaxim.org/http-bind`. WebSocket URL format differs from expected.
- **OMEMO/OX crypto**: Encrypt/decrypt roundtrips work locally without server involvement. PEP publish for device lists and bundles succeeds on yax.im.
