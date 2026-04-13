# Delta Chat Protocol Specification — Implementation Reference

Research compiled 2026-04-09 from Delta Chat core source (Rust), Autocrypt spec, SecureJoin spec, and chatmail spec.

---

## 1. Architecture Overview

Delta Chat is chat-over-email. It uses **standard IMAP/SMTP** with custom email headers to overlay instant-messaging semantics onto email. Every message is a valid RFC 5322 email. Non-DC clients see regular email; DC clients render them as chat bubbles.

**Key principle**: there is no central server. Any email account works. Real-time delivery uses IMAP IDLE. Encryption uses Autocrypt (OpenPGP over email headers).

### Transport Stack
- **Sending**: SMTP (port 587/STARTTLS or 465/TLS)
- **Receiving**: IMAP (port 993/TLS or 143/STARTTLS)
- **Real-time**: IMAP IDLE (RFC 2177) for push-like delivery
- **Encryption**: Autocrypt Level 1 (OpenPGP/MIME)
- **Verified contacts**: SecureJoin protocol (QR code + in-band handshake)

### User ID Scheme
- Every user is identified by their **email address** (canonicalized lowercase)
- No phone numbers, no internal numeric IDs
- Chat IDs: `dm:<email>` for DMs, `grp:<Chat-Group-ID>` for groups, `bc:<Chat-List-ID>` for broadcasts
- Message IDs: RFC 5322 `Message-ID` header (globally unique)

---

## 2. IMAP Strategy

### Folder Structure
DC uses two IMAP folders:
- `INBOX` — all incoming mail arrives here
- `DeltaChat` (or `INBOX/DeltaChat` with delimiter) — DC moves its messages here

On configure, DC tries to find/create a folder named `DeltaChat`. Fallback: `INBOX<delimiter>DeltaChat`. The delimiter is discovered via IMAP LIST.

### IMAP IDLE for Real-Time
DC opens **three IMAP connections** simultaneously and puts them into IDLE:
1. One on `INBOX` — catches new arrivals
2. One on `DeltaChat` — catches moved messages
3. One for other operations (SMTP send triggers, folder sync)

**IDLE is restarted every 28 minutes** to avoid server timeouts (RFC says servers may drop IDLE after 30 min).

When IDLE notifies of new mail:
1. Break IDLE
2. FETCH new message UIDs
3. FETCH headers + body
4. Parse DC headers, determine chat
5. If DC message: move from INBOX to `DeltaChat` folder
6. Resume IDLE

### Message Fetching
Use IMAP FETCH with:
- `ENVELOPE` — for From, To, Subject, Date, Message-ID, In-Reply-To
- `BODY.PEEK[HEADER.FIELDS (Chat-Version Autocrypt ...)]` — custom headers without marking as seen
- `BODY.PEEK[]` — full RFC 5322 message for parsing

### IMAP Configuration
```
ConfiguredInboxFolder = "INBOX"
ConfiguredMvboxFolder = "DeltaChat"  (or INBOX/DeltaChat)
```

### Classic Email Display (`ShowEmails` config)
Controls how non-DC (classical) emails are displayed:
- `Off` (0) — only show DC messages
- `AcceptedContacts` (1) — show classical emails from accepted contacts
- `All` (2, default) — show all emails

### Quota Checking (`IMAP GETQUOTAROOT`)
DC checks IMAP mailbox quota via the QUOTA extension. Warning thresholds:
- 80% — yellow warning
- 95% — red error
- 75% — all-clear hysteresis (stop warning)

---

## 3. Message Format (MIME Structure)

### Simple Text Message (Plaintext)
```
From: alice@example.org
To: bob@example.org
Subject: Chat: Hello there
Date: Wed, 09 Apr 2026 12:00:00 +0000
Message-ID: <Mr.abc123@example.org>
Chat-Version: 1.0
Chat-Disposition-Notification-To: alice@example.org
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

Hello there
```

### Encrypted Message (PGP/MIME)
```
From: alice@example.org
To: bob@example.org
Subject: Chat: Encrypted message
Date: Wed, 09 Apr 2026 12:00:00 +0000
Message-ID: <Mr.def456@example.org>
Chat-Version: 1.0
Autocrypt: addr=alice@example.org; prefer-encrypt=mutual; keydata=BASE64...
MIME-Version: 1.0
Content-Type: multipart/encrypted; protocol="application/pgp-encrypted"; boundary="BOUND"

--BOUND
Content-Type: application/pgp-encrypted
Content-Description: PGP/MIME version identification

Version: 1

--BOUND
Content-Type: application/octet-stream; name="encrypted.asc"

-----BEGIN PGP MESSAGE-----
... (encrypted payload containing the real headers + body) ...
-----END PGP MESSAGE-----
--BOUND--
```

The **encrypted inner payload** is a complete MIME message containing:
- The real `Subject` (outer subject is just "Chat: Encrypted message")
- All `Chat-*` headers (protected from server inspection)
- The actual message body (text/plain or multipart)
- `Autocrypt-Gossip` headers (for group key distribution)

### Message with Attachment
```
Content-Type: multipart/mixed; boundary="OUTER"

--OUTER
Content-Type: text/plain; charset=utf-8

Here is a file

--OUTER
Content-Type: application/pdf; name="document.pdf"
Content-Disposition: attachment; filename="document.pdf"
Content-Transfer-Encoding: base64

BASE64DATA...
--OUTER--
```

### Voice Message
Same as attachment, but with additional headers:
```
Chat-Voice-Message: 1
Chat-Duration: 5000
```
(Duration in milliseconds)

### Sticker Message
Image attachment with:
```
Chat-Content: sticker
```
Supported formats: `image/png`, `image/gif`, `image/webp`. Rendered at fixed size (200x200px). No sticker pack concept — stickers are individual images.

### HTML Message
DC can send HTML messages. The MIME contains both `text/plain` and `text/html` parts:
```
Content-Type: multipart/alternative; boundary="ALT"

--ALT
Content-Type: text/plain; charset=utf-8

Plain text version

--ALT
Content-Type: text/html; charset=utf-8

<html><body><p>HTML version</p></body></html>
--ALT--
```
On receive, DC strips HTML to plain text for display but preserves the original HTML (accessible via `get_html()`).

### Read Receipt (MDN)
```
Auto-Submitted: auto-replied
Content-Type: multipart/report; report-type=disposition-notification; boundary="SNIPP"

--SNIPP
Content-Type: text/plain; charset=utf-8

Read receipts do not guarantee sth. was read.

--SNIPP
Content-Type: message/disposition-notification

Original-Message-ID: <original-message-id@example.org>
Disposition: manual-action/MDN-sent-automatically; displayed

--SNIPP--
```

Combined MDNs (batch multiple read receipts):
```
Additional-Message-IDs: <id1@ex.org> <id2@ex.org>
```

### Reaction Message (RFC 9078 + XEP-0444 semantics)
```
In-Reply-To: <original-message-id@example.org>
Chat-Version: 1.0

Content-Type: text/plain; charset=utf-8
Content-Disposition: reaction

👍 🔥
```
- Body contains space-separated emoji
- Empty body = retract all reactions
- Each new reaction from a contact **replaces** all their previous reactions on that message
- Reaction messages are **hidden** (not shown as normal messages, only as badges on the original)

### vCard Message
Contact sharing via vCard attachment:
```
Content-Type: text/vcard; name="contact.vcf"
Content-Disposition: attachment; filename="contact.vcf"

BEGIN:VCARD
VERSION:3.0
FN:Bob Smith
EMAIL:bob@example.org
END:VCARD
```
Viewtype: `Vcard` (value 90). Recipients can import the shared contacts.

### Location Message (KML)
Locations are KML files attached to messages:
```
Content-Type: application/vnd.google-earth.kml+xml; name="message.kml"

<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <Placemark>
      <Timestamp><when>2026-04-09T12:00:00Z</when></Timestamp>
      <Point><coordinates>13.388860,52.517037,0</coordinates></Point>
    </Placemark>
  </Document>
</kml>
```
- Independent locations (POI): attached as `message.kml`
- Path locations (streaming): attached as `location.kml`
- Each placemark has coordinates (lon,lat), timestamp, optional accuracy and marker emoji

### Large File Split (Pre/Post Message)
For files exceeding the email size limit:
- **Pre-message**: sent first, contains text + metadata about the attachment
  - `Chat-Post-Message-Id: <rfc724_mid>` — references the post-message
  - `Chat-Post-Message-Metadata: <serialized metadata>` — file name, size, MIME type
- **Post-message**: sent second, contains the actual attachment
  - `Chat-Is-Post-Message` — unprotected header marking this as the attachment part
  - Receiver can skip fetching post-message body during initial sync

---

## 4. Complete Header Reference

### Required on ALL Outgoing Messages
| Header | Value | Notes |
|--------|-------|-------|
| `Chat-Version` | `1.0` | Identifies DC messages. MUST be in outer (unprotected) headers so IMAP can fetch without downloading body. |

### Message Identity & Threading
| Header | Value | Notes |
|--------|-------|-------|
| `Message-ID` | `<Gr.GRPID.RANDOM@domain>` for groups, `<Mr.RANDOM@domain>` for DMs | Group messages use `Gr.` prefix with group ID embedded |
| `In-Reply-To` | `<parent-message-id>` | Standard RFC 5322 threading |
| `References` | `<id1> <id2> ...` | Standard RFC 5322 reference chain |

### Group Management
| Header | Value | Notes |
|--------|-------|-------|
| `Chat-Group-ID` | `[0-9A-Za-z_-]+` | Unique group identifier |
| `Chat-Group-Name` | RFC 2047 encoded UTF-8 | Group display name |
| `Chat-Group-Name-Changed` | Old name | Present when group name changes |
| `Chat-Group-Name-Timestamp` | Unix timestamp | Conflict resolution for concurrent renames |
| `Chat-Group-Description` | Base64-encoded text | Group description |
| `Chat-Group-Description-Changed` | `""` | Present when description changes |
| `Chat-Group-Description-Timestamp` | Unix timestamp | Conflict resolution |
| `Chat-Group-Member-Added` | Email address | Member added to group |
| `Chat-Group-Member-Added-Fpr` | Fingerprint | PGP fingerprint of added member |
| `Chat-Group-Member-Removed` | Email address | Member removed from group |
| `Chat-Group-Member-Removed-Fpr` | Fingerprint | PGP fingerprint of removed member |
| `Chat-Group-Past-Members` | Email addresses | Past members (tombstones, kept 60 days) |
| `Chat-Group-Member-Timestamps` | Space-separated timestamps | Add timestamps for To members, then remove timestamps for past members |
| `Chat-Group-Member-Fpr` | Space-separated fingerprints | PGP fingerprints in same order as To + past members |

### Avatars / Profile Images
| Header | Value | Notes |
|--------|-------|-------|
| `Chat-Group-Avatar` | `base64:<data>` or `0` | Group avatar (base64 JPEG/PNG), `0` to remove |
| `Chat-User-Avatar` | `base64:<data>` or `0` | Sender's profile avatar, `0` to remove |

### Media / Content Type
| Header | Value | Notes |
|--------|-------|-------|
| `Chat-Voice-Message` | `1` | Marks audio attachment as voice message |
| `Chat-Duration` | Milliseconds (integer) | Duration of audio/video attachment |
| `Chat-Content` | See table below | System message type indicator |

### All `Chat-Content` Values
| Value | System Message Type | Notes |
|-------|---------------------|-------|
| `sticker` | Sticker | Marks message as a sticker |
| `call` | Call initiation | With `Chat-Webrtc-Room` |
| `call-accepted` | Call accepted (hidden) | With `Chat-Webrtc-Accepted` |
| `call-ended` | Call ended (hidden) | |
| `group-avatar-changed` | Group avatar changed | |
| `location-streaming-enabled` | Location streaming started | |
| `ephemeral-timer-changed` | Disappearing timer changed | |
| `protection-enabled` | Chat protection enabled | |
| `protection-disabled` | Chat protection disabled | |
| `webxdc-status-update` | webxdc state sync | JSON payload |

### Message Operations
| Header | Value | Notes |
|--------|-------|-------|
| `Chat-Edit` | `<original-message-id>` | This message edits the referenced message |
| `Chat-Delete` | `<message-id>` | This message deletes the referenced message(s) |

### Read Receipts
| Header | Value | Notes |
|--------|-------|-------|
| `Chat-Disposition-Notification-To` | Sender's email | Requests MDN. DC uses this instead of standard `Disposition-Notification-To`. |

### Ephemeral / Disappearing Messages
| Header | Value | Notes |
|--------|-------|-------|
| `Ephemeral-Timer` | Seconds (integer) | Disappearing message timer duration |

### Calls (WebRTC signaled via email)
| Header | Value | Notes |
|--------|-------|-------|
| `Chat-Webrtc-Room` | Room identifier / SDP offer | WebRTC call room |
| `Chat-Webrtc-Accepted` | SDP answer | Present when call accepted |
| `Chat-Webrtc-Has-Video-Initially` | Boolean | Whether call started with video |

### Broadcast Channels
| Header | Value | Notes |
|--------|-------|-------|
| `Chat-List-ID` | `Name <grpid>` | Broadcast channel identifier |
| `Chat-Broadcast-Secret` | Base64 shared secret | Symmetric encryption key for broadcast messages |

### Large Attachments
| Header | Value | Notes |
|--------|-------|-------|
| `Chat-Post-Message-Id` | `<rfc724_mid>` | In pre-message, references the post-message |
| `Chat-Post-Message-Metadata` | Serialized metadata | File name, size, MIME type |
| `Chat-Is-Post-Message` | Present | Marks a post-message (unprotected header) |

### Verified/Protected Chat
| Header | Value | Notes |
|--------|-------|-------|
| `Chat-Verified` | `1` | All messages MUST be encrypted, all members MUST be verified |

### Header Protection (RFC 9788)
| Header | Value | Notes |
|--------|-------|-------|
| `Hp-Outer` | Duplicated headers | Protects outer headers from MIME modification |

### Multi-Device Sync
| Header | Value | Notes |
|--------|-------|-------|
| `Auto-Submitted` | `auto-generated` | On sync messages to prevent auto-replies |

---

## 5. Autocrypt (E2EE)

### Overview
Autocrypt Level 1 distributes OpenPGP public keys via email headers. No key servers, no manual exchange. Keys travel with the messages themselves.

### Key Generation
Generate **Ed25519 + Cv25519** keypair:
- Primary key: Ed25519 (signing, certification)
- Subkey: Cv25519 (encryption)
- User ID: `<email@address>`

The keydata in the Autocrypt header must contain exactly 5 OpenPGP packets:
1. Signing-capable primary key (public)
2. User ID
3. Self-signature over User ID
4. Encryption-capable subkey (public)
5. Binding signature over subkey

### Autocrypt Header Format
```
Autocrypt: addr=alice@example.org; prefer-encrypt=mutual; keydata=BASE64KEYDATA
```

Attributes:
- `addr` (required): Sender email, must match From header
- `prefer-encrypt` (optional): Only value is `mutual`. Absent = `nopreference`
- `keydata` (required, must be LAST): Base64-encoded Transferable Public Key
- `_<name>` (non-critical): Underscore-prefixed attributes are ignored
- Unknown non-underscore attributes: entire header is INVALID

**Size limit**: 10 KiB max.

**DC extension**: `_verified=1` attribute on `Autocrypt-Gossip` headers indicates sender has verified this key.

DC always sets `prefer-encrypt=mutual`.

### Peer State Management
For each contact (canonicalized email), track:
```
peer_state {
    addr:                 string     // canonicalized email
    last_seen:            timestamp  // most recent message from peer
    autocrypt_timestamp:  timestamp  // most recent Autocrypt header
    public_key:           []byte     // from most recent Autocrypt header
    prefer_encrypt:       enum       // nopreference | mutual
    gossip_timestamp:     timestamp  // most recent gossip header
    gossip_key:           []byte     // from most recent gossip header
}
```

**Update rules**:
1. Skip `multipart/report` messages
2. Skip messages with multiple From addresses
3. Only process if message date > `autocrypt_timestamp`
4. If message has Autocrypt header: update `public_key`, `prefer_encrypt`, `autocrypt_timestamp`
5. If message has NO Autocrypt header: only update `last_seen`

### Encryption Decision Algorithm

For each recipient:
1. No peer state exists → `disable`
2. No `public_key` AND no `gossip_key` → `disable`
3. Only `gossip_key` available → `discourage`
4. `autocrypt_timestamp` older than 35 days before `last_seen` → `discourage`
5. Otherwise → `available`

Upgrade to `encrypt`:
- Replying to an encrypted message, OR
- Both sender and all recipients have `prefer_encrypt=mutual`

For multiple recipients: any `disable` → overall `disable`; all `encrypt` → `encrypt`; any `discourage` → `discourage`; else `available`.

### Autocrypt-Gossip (Group Key Distribution)
In encrypted group messages, include gossip headers for each recipient:
```
Autocrypt-Gossip: addr=bob@example.org; keydata=BASE64...
Autocrypt-Gossip: addr=charlie@example.org; keydata=BASE64...
```

Rules:
- MUST be inside the encrypted payload (not outer headers)
- One header per recipient (matching To/Cc/Reply-To)
- `keydata` contains the key used to encrypt TO that recipient
- SHOULD NOT include `prefer-encrypt`
- Updates `gossip_key` and `gossip_timestamp` on the receiving side

### PGP/MIME Format
Encrypted messages use standard PGP/MIME (RFC 3156):
```
Content-Type: multipart/encrypted; protocol="application/pgp-encrypted"

Part 1: application/pgp-encrypted  →  "Version: 1\r\n"
Part 2: application/octet-stream   →  ASCII-armored PGP message
```

The PGP message is signed by the sender and encrypted to all recipients + self.

### Autocrypt Setup Message (Multi-Device Key Transfer)
Transfers the private key between devices. Encrypted with a passphrase displayed as 9×4 digits:
```
Autocrypt-Setup-Message: v1
Content-Type: multipart/mixed

Part 1: text/plain — instructions
Part 2: application/autocrypt-setup — encrypted private key (symmetric, passphrase-derived)
```
One-time manual process. The 44-digit passphrase is shown on the sending device, entered on the receiving device.

---

## 6. SecureJoin Protocol (Verified Contacts)

### Purpose
Establishes verified end-to-end encryption resistant to MITM attacks. Uses out-of-band QR code to verify key fingerprints.

### QR Code Format (v3)
**Setup Contact** (1:1 verification):
```
https://i.delta.chat/#<FINGERPRINT>&v=3&i=<INVITENUMBER>&s=<AUTH>&a=<ADDR>&n=<NAME>
```

**Join Group** (verified group invite):
```
https://i.delta.chat/#<FINGERPRINT>&v=3&x=<GRPID>&i=<INVITENUMBER>&s=<AUTH>&a=<ADDR>&n=<NAME>&g=<GROUPNAME>
```

**Join Broadcast**:
```
https://i.delta.chat/#<FINGERPRINT>&v=3&x=<GRPID>&j=<INVITENUMBER>&s=<AUTH>&a=<ADDR>&n=<NAME>&b=<BROADCASTNAME>
```

Parameters:
- `FINGERPRINT`: Hex-encoded PGP key fingerprint of inviter
- `INVITENUMBER`: Token to request inviter's key
- `AUTH`: Authentication token (one-time, expires ~7 days)
- `ADDR`: URL-encoded email address
- `NAME`: URL-encoded display name (max 25 chars, truncated with `_`)
- `GRPID`: Group/broadcast ID
- `v=3`: Protocol version

### Setup Contact Protocol Flow

**Alice** (inviter) generates QR code containing her fingerprint + tokens.

**Bob** (joiner) scans QR code, then:

**Case A — Bob already has Alice's key matching the fingerprint:**
1. Bob sends `vc-request-with-auth` (encrypted) containing AUTH + Secure-Join-Invitenumber
2. Alice verifies AUTH, marks Bob as verified
3. Alice sends `vc-contact-confirm` (encrypted)
4. Done.

**Case B — Bob doesn't have Alice's key yet:**
1. Bob sends `vc-request` containing INVITENUMBER (or `vc-request-pubkey` for v3)
2. Alice sends `vc-auth-required` (or `vc-pubkey` with her key for v3)
3. Bob receives Alice's key, verifies fingerprint matches QR code
4. Bob sends `vc-request-with-auth` (encrypted) with AUTH
5. Alice verifies AUTH, marks Bob as verified
6. Alice sends `vc-contact-confirm`
7. Done.

### SecureJoin Headers
| Header | Value | Notes |
|--------|-------|-------|
| `Secure-Join` | Step name | The handshake step |
| `Secure-Join-Invitenumber` | Token | Present in request messages |
| `Secure-Join-Auth` | Token | Present in auth messages |
| `Secure-Join-Fingerprint` | Hex fingerprint | Key fingerprint being verified |

### Handshake Steps
| Step | Direction | Description |
|------|-----------|-------------|
| `vc-request` | Bob → Alice | Request contact verification (legacy) |
| `vc-request-pubkey` | Bob → Alice | Request Alice's pubkey (v3, symmetric-encrypted) |
| `vc-pubkey` | Alice → Bob | Send pubkey (v3) |
| `vc-auth-required` | Alice → Bob | Ask Bob for AUTH (legacy) |
| `vg-auth-required` | Alice → Bob | Same for group join |
| `vc-request-with-auth` | Bob → Alice | Send AUTH for contact verification |
| `vg-request-with-auth` | Bob → Alice | Send AUTH for group join |
| `vc-contact-confirm` | Alice → Bob | Contact verified |
| `vg-member-added` | Alice → Bob | Member added to verified group |

All handshake messages are **hidden** (not shown in chat UI).

### Verified Group Join
Same as Setup Contact, but:
1. QR code contains group ID (`x=<GRPID>`)
2. Bob sends `vg-*` variants instead of `vc-*`
3. Alice adds Bob to group with `Chat-Group-Member-Added`
4. Group messages include `Autocrypt-Gossip` for all members

---

## 7. Group Management

### Creating a Group
1. Generate random Group ID: `[0-9A-Za-z_-]+`
2. Send first message to all members with:
   - `Chat-Group-ID: <grpid>`
   - `Chat-Group-Name: <name>`
   - Members in `To:` header

### Message-ID Format for Groups
```
Gr.<group-id>.<random-data>@<sender-domain>
```

### Adding a Member
```
Chat-Group-Member-Added: newmember@example.org
Chat-Group-Member-Added-Fpr: <fingerprint>
```
New member must be in `To:`. Include `Autocrypt-Gossip` for all members.

### Removing a Member
```
Chat-Group-Member-Removed: oldmember@example.org
Chat-Group-Member-Removed-Fpr: <fingerprint>
```
Removed member still receives this message (added to SMTP recipients even if not in `To:`).

### Renaming a Group
```
Chat-Group-Name: New Name
Chat-Group-Name-Changed: Old Name
Chat-Group-Name-Timestamp: 1712678400
```

### Group Description
```
Chat-Group-Description: <base64-encoded description>
Chat-Group-Description-Changed:
Chat-Group-Description-Timestamp: 1712678400
```

### Group Avatar
```
Chat-Group-Avatar: base64:<BASE64-ENCODED-JPEG-OR-PNG>
```
`Chat-Group-Avatar: 0` to remove.

### Member List Construction
DC constructs the member list ONLY from:
1. The `To:` header of the **first group message** received
2. Subsequent `Chat-Group-Member-Added` / `Chat-Group-Member-Removed` headers

Does NOT rebuild from `To:` of every message (prevents corruption from standard email clients that may CC extra people).

### Timestamps for Conflict Resolution
`Chat-Group-Member-Timestamps` contains space-separated timestamps for each member. Past member tombstones kept 60 days.

---

## 8. Broadcast Channels

DC has full broadcast/channel support:
- **OutBroadcast** (sender's view): writable, shows member list
- **InBroadcast** (recipient's view): read-only, cannot reply

### Protocol
- `Chat-List-ID: <channel_name> <grpid>` — identifies the channel
- Messages **symmetrically encrypted** using `Chat-Broadcast-Secret` (264-bit random key, base64url, 43 chars) — one encrypted copy for all recipients rather than N copies
- `To:` field set to `"hidden-recipients": ;` (empty group address) — recipients are hidden from each other
- Member add/remove: individual messages sent only to affected member (asymmetric encryption for those)
- When a member is added, the broadcast secret is sent encrypted to their public key

### Creating a Channel
1. Generate group ID and broadcast secret
2. Store secret locally
3. Send invitation messages to members with the secret (encrypted per-recipient)
4. Send broadcast messages with `Chat-List-ID` + symmetric encryption

---

## 9. Profiles and Avatars

### User Avatar
Sent as `Chat-User-Avatar` in the **encrypted (inner) headers**. Not sent with every message — DC sends it on first message to a new contact and periodically.
```
Chat-User-Avatar: base64:<BASE64-ENCODED-JPEG-OR-PNG>
```
Remove: `Chat-User-Avatar: 0`

### Display Name
From standard `From:` header:
```
From: "Alice Smith" <alice@example.org>
```
Override with `Sender:` header:
```
From: "Override Name" <alice@example.org>
Sender: "Real Config Name" <alice@example.org>
```

### Status / Bio
`Config::Selfstatus` — user-set status text. Appears in profile and can be sent in message footers. Stored locally from received messages for contacts.

---

## 10. Calls (WebRTC via Email Signaling)

<!-- Discovered 2026-04-09 from DC core source -->

DC supports **1:1 voice and video calls**. No group calls. Media uses WebRTC; signaling uses hidden email messages.

### Call Flow
1. **Caller** sends hidden message with:
   - `Chat-Content: call`
   - `Chat-Webrtc-Room: <room-id-or-sdp-offer>`
   - `Chat-Webrtc-Has-Video-Initially: <bool>` (if video)
2. **Callee** receives via IMAP IDLE, shows incoming call UI
3. **Callee accepts** → sends hidden message with:
   - `Chat-Content: call-accepted`
   - `Chat-Webrtc-Accepted: <sdp-answer>`
4. Both sides establish WebRTC connection via STUN/TURN
5. **Call ends** → hidden message with `Chat-Content: call-ended`

### ICE Server Discovery
- **Chatmail servers**: provide TURN credentials via IMAP METADATA command. Format: `hostname:port:timestamp:password` (timestamp = username AND expiration)
- **Fallback STUN**: `nine.testrun.org:3478`
- **Fallback TURN**: `turn.delta.chat:3478` with credentials `public/o4tR7yG4rG2slhXqRUf9zgmHz`

### Call States
| State | Description |
|-------|-------------|
| Alerting | Ringing |
| Active | In progress |
| Completed(duration) | Ended normally |
| Missed | 120-second ringing timeout reached |
| Declined | Callee rejected |
| Canceled | Caller hung up before answer |

### Call Filtering (`WhoCanCallMe` config)
- `Everybody` (0) — anyone can call
- `Contacts` (1, default) — only known contacts
- `Nobody` (2) — calls disabled

### Limitations
- **1:1 only** — no group calls (`Chattype::Single` required)
- **Email latency** — signaling via email means 0.2-30s+ delay before call connects. Works best with chatmail servers optimized for fast IMAP IDLE.
- Our implementation: use pion/webrtc for the media path, email signaling via the IMAP/SMTP core.

---

## 11. Reactions (RFC 9078)

<!-- Discovered 2026-04-09 -->

DC natively supports emoji reactions per RFC 9078 with XEP-0444 update semantics.

### Protocol
- Sent as regular MIME email with `Content-Disposition: reaction` on the `text/plain` part
- Body: space-separated emoji strings (e.g., `"👍 🔥"`)
- `In-Reply-To: <original-message-id>` identifies the target message
- **Hidden**: reaction messages don't appear as normal messages, only as badges
- Empty body = **retract** all reactions from this sender
- Each new reaction **replaces** all previous reactions from that contact (XEP-0444)
- Multiple emoji per reaction supported, sorted and deduplicated

---

## 12. Ephemeral (Disappearing) Messages

### Protocol
- `Ephemeral-Timer: <seconds>` header on outgoing messages
- Timer values: 0 (off), 1, 10, 30, 60, 300, 3600, 86400, 604800, custom
- When set, all new messages in the chat get this header
- Timer change announced via `Chat-Content: ephemeral-timer-changed` system message
- Messages auto-deleted locally after the timer expires (from time of reading)

---

## 13. Location Streaming

<!-- Discovered 2026-04-09 -->

Users can share live GPS location to a chat for a configurable duration.

### Protocol
- **Start streaming**: system message with `Chat-Content: location-streaming-enabled`
- **Location updates**: KML files attached to messages
  - `message.kml` — independent locations (POI)
  - `location.kml` — continuous path locations
- **KML format**: standard OGC KML with `<Placemark>` elements containing:
  - `<coordinates>lon,lat,0</coordinates>`
  - `<Timestamp><when>ISO8601</when></Timestamp>`
  - Optional accuracy and marker emoji

### API
- `send_locations_to_chat(chat_id, seconds)` — start streaming (0 = stop)
- `is_sending_locations_to_chat(chat_id)` — check if streaming
- `set_location(lat, lon)` — attach POI to a message
- `get_locations()` — retrieve stored locations

---

## 14. Chat Visibility (Pin / Archive / Normal)

Local-only feature, synced across devices via multi-device sync.

### Three States
| Visibility | Value | Description |
|-----------|-------|-------------|
| Normal | 0 | Default |
| Archived | 1 | Hidden from main list, accessible via "Archived" section |
| Pinned | 2 | Pinned to top of chat list |

### Sync
Synchronized via `SyncAction::SetVisibility` in multi-device sync messages.

---

## 15. Chat Muting

Local setting, synced across devices.

### Three Modes
| Mode | Description |
|------|-------------|
| NotMuted | Normal — all notifications |
| Forever | Permanently muted |
| Until(timestamp) | Muted until specific time |

### Sync
Synchronized via `SyncAction::SetMuted`.

---

## 16. Drafts

Local per-chat message drafts, persisted in the local database.

### API
- `set_draft(chat_id, msg)` — save draft
- `get_draft(chat_id)` — load draft

Synced across devices via `SyncData::SaveMessage`.

---

## 17. Verified/Protected Chats

A chat can be "protected" — all messages MUST be encrypted and all members MUST be verified via SecureJoin.

### Protocol
- `Chat-Verified: 1` header on messages in protected chats
- `Chat-Content: protection-enabled` system message when enabled
- `Chat-Content: protection-disabled` system message when disabled
- If verification breaks (key change without re-verification), chat reverts to unprotected

---

## 18. Self-Chat (Saved Messages)

Chat with yourself (`ContactId::SELF`). Used for notes, saving messages, and as a sync channel.

- `save_msgs(msg_ids)` — copies messages from any chat to self-chat
- Regular `SendMessage` to self-chat works like notes
- Multi-device sync messages travel through self-chat (BCC self)

---

## 19. Contact Management

### Operations
| Operation | Protocol | Notes |
|-----------|----------|-------|
| Add contact | Local (store email + name) | Triggers Autocrypt exchange on first message |
| Block contact | Local + sync | `SyncAction::AlterChat` with block flag |
| Unblock contact | Local + sync | Same |
| Import address book | Local | Bulk import name+email pairs |
| Import vCard | Parse `.vcf` file | Extract contacts from vCard format |
| Export vCard | Generate `.vcf` | Create vCard for sharing |
| Delete contact | Local + sync | Remove from contacts list |

### "Recently seen" heuristic
`Contact::was_seen_recently()` — checks if a message was received from the contact within a recent window. Not the same as "online status" (email has no presence concept).

---

## 20. Download-on-Demand (Partial Download)

Large messages can be partially downloaded — headers + text only, no attachments. User can then download the full message later.

### Config
`DownloadLimit` — max size (bytes) of auto-downloaded messages. 0 = unlimited.

### Download States
| State | Description |
|-------|-------------|
| Done | Fully downloaded |
| Available | Partial, full download available |
| InProgress | Currently downloading |
| Failure | Download failed |
| Undecipherable | Downloaded but can't decrypt |

### API
- `download_full(msg_id)` — download the full message
- Uses pre/post message split headers for large files

---

## 21. Multi-Device Sync

Synchronizes actions across multiple devices logged into the same email account.

### Mechanism
- Uses BCC-self messages with JSON payloads
- Marked with `Auto-Submitted: auto-generated` to prevent auto-replies
- System message type: `MultiDeviceSync` (value 20)

### Synced Actions
| Action | What it syncs |
|--------|---------------|
| `AlterChat` | Block/unblock, accept, visibility, mute, rename, description, contacts, delete |
| `Config` | Display name, MDN setting, mvbox_move, show_emails, avatar, status |
| `AddQrToken` / `DeleteQrToken` | SecureJoin tokens |
| `SaveMessage` | Save message to self-chat |
| `DeleteMessages` | Delete messages |
| `Transports` | Add/remove email transports |

---

## 22. Backup Import/Export

### Modes
| Mode | Description |
|------|-------------|
| `ExportSelfKeys` | Export PGP keys only |
| `ImportSelfKeys` | Import PGP keys only |
| `ExportBackup` | Full backup (tar archive, optionally encrypted) |
| `ImportBackup` | Restore from backup |

### Device-to-Device Transfer
QR-code-based `DCBACKUP` scheme using iroh-net (P2P, QUIC-based) for direct transfer between devices without a server.

---

## 23. webxdc Apps

Mini-apps (`.xdc` ZIP files containing HTML+JS) shared as message attachments.

### Protocol
- `.xdc` file attached as regular MIME attachment
- State updates synced via DC messages with `Chat-Content: webxdc-status-update` and JSON body
- webxdc JS API: `window.webxdc.sendUpdate()` / `window.webxdc.setUpdateListener()`

### Peer Channels (iroh-net)
Real-time P2P communication for webxdc apps:
- `Iroh-Node-Addr` header — node's relay address
- `Iroh-Gossip-Topic` header — 32-byte topic ID
- Uses iroh gossip protocol (QUIC-based, ephemeral keys)

**Note**: webxdc is how DC implements polls (via a poll app), collaborative editing, and other interactive features. It's a mini-app runtime, not individual protocol features.

---

## 24. File Attachments

Standard MIME attachments. Nothing DC-specific.

### File Size Limits
Most email providers limit to 25-50 MB. DC recommends **~18 MB** after Base64 overhead (base64 inflates by ~33%).

### Encrypted Attachments
When the message is PGP/MIME encrypted, the entire MIME structure including attachments is inside the encrypted payload. Server sees only `application/octet-stream; name="encrypted.asc"`.

---

## 25. Go Library APIs

### `github.com/emersion/go-imap/v2` (IMAP)

```go
import "github.com/emersion/go-imap/v2/imapclient"

// TLS connection
client, err := imapclient.DialTLS("imap.example.org:993", &imapclient.Options{
    UnilateralDataHandler: &imapclient.UnilateralDataHandler{
        Expunge: func(seqNum uint32) { /* handle expunge */ },
        Mailbox: func(data *imap.MailboxData) { /* handle mailbox updates */ },
    },
})

// Auth
err = client.Login("user@example.org", "password").Wait()

// Or SASL auth (XOAUTH2)
err = client.Authenticate(saslClient).Wait()

// Select mailbox
mbox, err := client.Select("INBOX", nil).Wait()

// Fetch messages
seqSet := imap.SeqSet{}
seqSet.AddRange(1, mbox.NumMessages)
fetchCmd := client.Fetch(seqSet, &imap.FetchOptions{
    Envelope: true,
    Flags:    true,
    BodySection: []*imap.FetchItemBodySection{
        {Specifier: imap.PartSpecifierHeader},
        {Specifier: imap.PartSpecifierText},
    },
})
defer fetchCmd.Close()
for {
    msg := fetchCmd.Next()
    if msg == nil { break }
    // msg.Envelope.From, .To, .Subject, .MessageID, .InReplyTo
}

// IDLE
idleCmd, err := client.Idle()
// Blocks — server sends updates via UnilateralDataHandler
// Stop: idleCmd.Close(), then idleCmd.Wait()

// Search for DC messages
criteria := &imap.SearchCriteria{
    Header: []imap.SearchCriteriaHeaderField{
        {Key: "Chat-Version", Value: "1.0"},
    },
}
searchCmd := client.Search(criteria, nil)
results, err := searchCmd.Wait()

// Store flags (mark as read)
storeCmd := client.Store(seqSet, &imap.StoreFlags{
    Op:    imap.StoreFlagsAdd,
    Flags: []imap.Flag{imap.FlagSeen},
}, nil)

// Move messages
moveCmd := client.Move(seqSet, "DeltaChat")
err = moveCmd.Wait()

// Create folder
err = client.Create("DeltaChat", nil).Wait()
```

### `github.com/emersion/go-smtp` (SMTP)

```go
import "github.com/emersion/go-smtp"

// STARTTLS
client, err := smtp.DialStartTLS("smtp.example.org:587", tlsConfig)

// Auth
auth := sasl.NewPlainClient("", "user@example.org", "password")
err = client.Auth(auth)

// Send
err = client.SendMail("sender@example.org", []string{"recipient@example.org"}, messageReader)

// Or step-by-step:
err = client.Mail("sender@example.org", nil)
err = client.Rcpt("recipient@example.org", nil)
wc, err := client.Data()
wc.Write(messageBytes)
wc.Close()
client.Quit()
```

### `github.com/emersion/go-message` (MIME)

```go
import "github.com/emersion/go-message/mail"

// Writing a message
var buf bytes.Buffer
var h mail.Header
h.SetDate(time.Now())
h.SetAddressList("From", []*mail.Address{{Name: "Alice", Address: "alice@example.org"}})
h.SetAddressList("To", []*mail.Address{{Name: "Bob", Address: "bob@example.org"}})
h.SetSubject("Chat: Hello")
h.Set("Chat-Version", "1.0")
h.Set("Message-ID", "<Mr.abc123@example.org>")

w, _ := mail.CreateWriter(&buf, h)

// Text part
var ih mail.InlineHeader
ih.Set("Content-Type", "text/plain; charset=utf-8")
pw, _ := w.CreateInline()
tw, _ := pw.CreatePart(ih)
tw.Write([]byte("Hello world"))
tw.Close()
pw.Close()

// Attachment
var ah mail.AttachmentHeader
ah.Set("Content-Type", "application/pdf")
ah.SetFilename("doc.pdf")
aw, _ := w.CreateAttachment(ah)
io.Copy(aw, fileReader)
aw.Close()

w.Close()
// buf.Bytes() is the complete RFC 5322 message

// Reading a message
mr := mail.NewReader(entity)
for {
    part, err := mr.NextPart()
    if err == io.EOF { break }
    switch h := part.Header.(type) {
    case *mail.InlineHeader:
        ct, _, _ := h.ContentType()
        body, _ := io.ReadAll(part.Body)
    case *mail.AttachmentHeader:
        filename, _ := h.Filename()
        io.Copy(destFile, part.Body)
    }
}
```

### `github.com/ProtonMail/go-crypto/openpgp` (OpenPGP)

```go
import (
    "github.com/ProtonMail/go-crypto/openpgp"
    "github.com/ProtonMail/go-crypto/openpgp/packet"
    "github.com/ProtonMail/go-crypto/openpgp/armor"
)

// Key generation (Ed25519/Cv25519 for Autocrypt)
config := &packet.Config{
    Algorithm: packet.PubKeyAlgoEdDSA,  // Ed25519 primary, Cv25519 subkey auto
}
entity, err := openpgp.NewEntity("", "", "alice@example.org", config)

// Serialize public key for Autocrypt header
var buf bytes.Buffer
entity.Serialize(&buf)
keydata := base64.StdEncoding.EncodeToString(buf.Bytes())
// → Autocrypt: addr=alice@example.org; prefer-encrypt=mutual; keydata=<keydata>

// Encrypt & sign (PGP/MIME)
recipients := []*openpgp.Entity{bobEntity, aliceEntity} // encrypt to self too
var cipherBuf bytes.Buffer
plainWriter, err := openpgp.Encrypt(&cipherBuf, recipients, aliceEntity, nil, nil)
plainWriter.Write(mimePayload)
plainWriter.Close()

// Armor
var armoredBuf bytes.Buffer
armorWriter, _ := armor.Encode(&armoredBuf, "PGP MESSAGE", nil)
armoredBuf.Write(cipherBuf.Bytes())
armorWriter.Close()

// Decrypt
keyring := openpgp.EntityList{myEntity}
md, err := openpgp.ReadMessage(armoredReader, keyring, nil, nil)
plaintext, _ := io.ReadAll(md.UnverifiedBody)
// After reading: check md.SignatureError

// Read keys from Autocrypt header
keydata, _ := base64.StdEncoding.DecodeString(autocryptKeydata)
entities, err := openpgp.ReadKeyRing(bytes.NewReader(keydata))
peerKey := entities[0]
```

### `github.com/emersion/go-sasl` (SASL)

```go
import "github.com/emersion/go-sasl"

// PLAIN auth
client := sasl.NewPlainClient("", "user@example.org", "password")

// XOAUTH2 (Gmail, etc.)
client := sasl.NewXoauth2Client("user@example.org", "access_token")
```

---

## 26. Server Auto-Discovery

Users shouldn't need to type IMAP/SMTP hosts manually. DC discovers servers via:

1. **Mozilla Autoconfig**: `https://autoconfig.example.org/mail/config-v1.1.xml` or `https://autoconfig.thunderbird.net/v1.1/example.org`
2. **SRV records**: `_imaps._tcp.example.org`, `_submission._tcp.example.org`
3. **Well-known**: `https://example.org/.well-known/autoconfig/mail/config-v1.1.xml`
4. **Hardcoded fallbacks**: common providers (Gmail, Outlook, Yahoo, etc.)

### Chatmail Servers
Specialized email servers optimized for Delta Chat:
- Fast IMAP IDLE (sub-second notification)
- No quotas or rate limits
- Automatic account creation
- TURN credentials via IMAP METADATA
- Recommended for best experience

---

## 27. Core Interface Mapping — Complete

Every method in the `Core` interface maps to a Delta Chat operation. **Nothing returns ErrNotSupported except where email fundamentally cannot support the concept.**

### Identity & Auth

| Method | Implementation | Notes |
|--------|---------------|-------|
| `Name()` | `"deltachat"` | |
| `Capabilities()` | See capabilities table below | |
| `Authenticate(cfg)` | IMAP DialTLS + Login, SMTP DialStartTLS + Auth, generate Ed25519/Cv25519 keypair if first time, create DeltaChat folder, start 3x IDLE goroutines. `cfg.Extra`: `imap_host`, `imap_port`, `smtp_host`, `smtp_port`. Bot mode returns ErrNotSupported. `cfg.Phone` is actually the email address. `cfg.Password2F` is the email password. | Auto-discover servers if host not provided |
| `Logout()` | Close IMAP+SMTP connections, clear session from vault. No server-side invalidation (email has no logout). | |

### Dialogs

| Method | Implementation | Notes |
|--------|---------------|-------|
| `GetDialogs(opts)` | Scan DeltaChat IMAP folder, build chat list from `Chat-Group-ID` (groups) and From/To (DMs). Cache locally. Unread = messages without `\Seen` flag. | First sync is slow — cache message index |
| `CreateGroup(name, members)` | Generate random group ID, compose MIME with `Chat-Group-ID` + `Chat-Group-Name`, send to all members via SMTP | |
| `CreateChannel(name, desc)` | Create broadcast channel: generate group ID + broadcast secret (264-bit), send encrypted invitations to members. Uses `Chat-List-ID` + symmetric encryption. | Maps to DC's OutBroadcast |
| `CreateTopic(chatID, name)` | Create an email thread within a group by sending a message with a specific `Subject` and `In-Reply-To` chain. Topic = email thread. | Not perfect parity but functional |
| `GetFolders()` | Return local chat categories: Pinned, Archived, Normal. Not IMAP folders — local organization. | |
| `CreateFolder(name, chatIDs)` | Create local chat folder stored in vault. Group arbitrary chats together. | Local-only, synced via multi-device |

### Messages

| Method | Implementation | Notes |
|--------|---------------|-------|
| `SendMessage(chatID, msg)` | Build RFC 5322 MIME with `Chat-Version: 1.0`, `Chat-Disposition-Notification-To`, `Autocrypt:` header. If peer state says encrypt → PGP/MIME. Send via SMTP. BCC self. | |
| `GetMessages(chatID, opts)` | IMAP FETCH from DeltaChat folder filtered by group ID / sender. Parse MIME, decrypt if PGP/MIME. Paginate via UID ranges. | Cache parsed messages locally |
| `EditMessage(chatID, msgID, text)` | Send new message with `Chat-Edit: <original-message-id>` header. | Replaces original in recipient's UI |
| `DeleteMessage(chatID, msgID)` | Send message with `Chat-Delete: <message-id>`. Locally: IMAP STORE `\Deleted` + EXPUNGE. | |
| `ReplyToMessage(chatID, replyToMsgID, msg)` | Standard `In-Reply-To: <parent-id>` + `References:` chain. | Both DC and regular email understand this |
| `ForwardMessage(from, msgID, to)` | Fetch original, recompose with `Forwarded:` indicator, send to target chat. | |
| `ReactToMessage(chatID, msgID, emoji)` | Send RFC 9078 reaction: `Content-Disposition: reaction`, body = emoji, `In-Reply-To: <target-msg-id>`. | Native DC protocol |
| `PinMessage(chatID, msgID)` | Store pin state locally in vault. Announce via system message in chat. | Local + sync |
| `UnpinMessage(chatID, msgID)` | Remove pin state locally. | |

### Read State

| Method | Implementation | Notes |
|--------|---------------|-------|
| `MarkAsRead(chatID, upToMsgID)` | IMAP STORE `\Seen` flag. If message had `Chat-Disposition-Notification-To`, send MDN back. | |
| `GetReadState(chatID)` | `MyLastRead` from IMAP `\Seen` flags. `PeerLastRead` from received MDNs (`Original-Message-ID`). | |

### Files

| Method | Implementation | Notes |
|--------|---------------|-------|
| `UploadFile(chatID, file, progress)` | Attach as MIME part. Progress from SMTP write. ~18 MB limit. Voice messages: add `Chat-Voice-Message: 1` + `Chat-Duration`. | Auto-split via pre/post message if needed |
| `DownloadFile(fileRef, dest, progress)` | IMAP FETCH attachment body section. Decode Base64. Progress from read bytes. | Or download full message for partial downloads |
| `SendImageBase64(chatID, b64, caption)` | Decode Base64 → attach as image MIME part with caption. | |

### Calls

| Method | Implementation | Notes |
|--------|---------------|-------|
| `StartCall(chatID, video)` | Send hidden message: `Chat-Content: call`, `Chat-Webrtc-Room: <room/sdp>`, optional `Chat-Webrtc-Has-Video-Initially`. Create pion/webrtc PeerConnection, generate SDP offer. | 1:1 only. Email signaling latency. |
| `JoinGroupCall(chatID)` | Return ErrNotSupported | DC has no group calls |
| `EndCall(callID)` | Send hidden `Chat-Content: call-ended`. Close WebRTC connection. | |
| `SetCallMuted(callID, muted)` | Local mute/unmute on the pion/webrtc audio track. No protocol-level signaling needed. | |

### Profile

| Method | Implementation | Notes |
|--------|---------------|-------|
| `GetProfile(userID)` | Look up email address in contacts. Display name from cached `From:` headers. Avatar from cached `Chat-User-Avatar`. Status from cached profile. No online status. | |

### Real-time

| Method | Implementation | Notes |
|--------|---------------|-------|
| `OnUpdate(handler)` | Three IMAP IDLE goroutines (INBOX + DeltaChat + ops). On notification → break IDLE → FETCH new → parse → fire callback → resume. 28-min restart. Reconnect with exponential backoff. | |
| `Close()` | Close all IMAP connections, SMTP connection, stop goroutines. | |

### Chat Management

| Method | Implementation | Notes |
|--------|---------------|-------|
| `GetChatInfo(chatID)` | Return cached Dialog with members, name, avatar, description. | |
| `EditChatTitle(chatID, title)` | Send message with `Chat-Group-Name: <new>` + `Chat-Group-Name-Changed: <old>` + timestamp. | Groups/channels only |
| `EditChatDescription(chatID, desc)` | Send message with `Chat-Group-Description: <base64>` + `Chat-Group-Description-Changed` + timestamp. | |
| `LeaveChat(chatID)` | Send `Chat-Group-Member-Removed: <self-email>`. Stop syncing that chat. | |
| `GetInviteLink(chatID)` | Generate SecureJoin QR code URL: `https://i.delta.chat/#<FINGERPRINT>&v=3&x=<GRPID>&i=<INVITE>&s=<AUTH>&a=<ADDR>&n=<NAME>&g=<GROUPNAME>`. | Returns string URL |

### Member Management

| Method | Implementation | Notes |
|--------|---------------|-------|
| `AddMembers(chatID, userIDs)` | Send message with `Chat-Group-Member-Added: <email>` + `Autocrypt-Gossip` for all members. | userIDs are email addresses |
| `RemoveMember(chatID, userID)` | Send message with `Chat-Group-Member-Removed: <email>`. | |
| `BanMember(chatID, userID)` | Remove + add to local blocklist for this chat. | No server-side ban concept |
| `UnbanMember(chatID, userID)` | Remove from local chat blocklist. | |
| `GetMembers(chatID, opts)` | Return cached member list built from first message + add/remove headers. | |
| `SetAdmin(chatID, userID, admin)` | Store admin role locally. DC groups are flat (no admin hierarchy in protocol), but we can enforce locally. | Local-only |

### Contacts

| Method | Implementation | Notes |
|--------|---------------|-------|
| `GetContacts()` | Return all email addresses we've exchanged DC messages with. | |
| `AddContact(phone, first, last)` | `phone` is actually email. Store locally. Send initial hello to trigger Autocrypt. | |
| `DeleteContact(userID)` | Remove from local contacts. | |
| `BlockUser(userID)` | Add to blocklist. Silently ignore messages from address. Sync across devices. | |
| `UnblockUser(userID)` | Remove from blocklist. | |
| `GetBlockedUsers()` | Return local blocklist. | |

### Search

| Method | Implementation | Notes |
|--------|---------------|-------|
| `SearchMessages(chatID, query, opts)` | SQL LIKE on local message cache (all fetched messages stored locally). | Fast, no IMAP SEARCH needed |
| `SearchGlobal(query, opts)` | Same SQL search across all chats. Limit 1000 results. | |

### Typing

| Method | Implementation | Notes |
|--------|---------------|-------|
| `SendTyping(chatID)` | No-op (return nil, not error). Email has no typing concept. Silently ignore rather than error. | |

### Polls

| Method | Implementation | Notes |
|--------|---------------|-------|
| `CreatePoll(chatID, question, options)` | Send a structured text message with formatted poll (question + numbered options). Voters reply with option number. Parse replies to tally votes. | Convention-based, not native DC protocol. Simple but works. |
| `VotePoll(chatID, msgID, optionIndex)` | Send reply to poll message with the option number. | |

### Stickers

| Method | Implementation | Notes |
|--------|---------------|-------|
| `SendSticker(chatID, stickerID)` | Send image attachment with `Chat-Content: sticker` header. `stickerID` is a local file path or cached sticker reference. | Native DC protocol |

### Sessions

| Method | Implementation | Notes |
|--------|---------------|-------|
| `GetSessions()` | Return a single "current session" entry with our IMAP connection info. Email doesn't expose other sessions. | Truthful — shows what we know |
| `TerminateSession(sessionID)` | Change email password (if supported by provider API) or return ErrNotSupported. | Best-effort |

### Capabilities Table

| Capability | Supported | Notes |
|-----------|-----------|-------|
| `CALLS` | Yes | 1:1 only, WebRTC + email signaling. Latency depends on provider. |
| `GROUP_CALLS` | No | DC has no group calls |
| `CHANNELS` | Yes | Broadcast channels via `Chat-List-ID` |
| `REACTIONS` | Yes | RFC 9078 native |
| `READ_RECEIPTS` | Yes | MDN-based |
| `POLLS` | Yes | Convention-based (structured text + reply voting) |
| `STICKERS` | Yes | `Chat-Content: sticker` native |
| `TOPICS` | Yes | Email threading within groups |
| `SCHEDULED` | No | Email has no scheduled send (provider-dependent) |
| `FOLDERS` | Yes | Local chat organization |
| `ADMIN` | Yes | Local admin roles (DC groups are flat) |
| `SESSIONS` | Yes | Limited — current session only |
| `BASE64_IMAGE` | Yes | Decode + attach as MIME |

---

## 28. Internal Architecture

```go
type DeltaChatCore struct {
    // Connections (3 IMAP + 1 SMTP)
    imapOps       *imapclient.Client   // main operations (fetch, store, move)
    idleInbox     *imapclient.Client   // IDLE on INBOX
    idleDC        *imapclient.Client   // IDLE on DeltaChat folder
    smtpClient    *smtp.Client

    // Crypto (Autocrypt)
    myEntity      *openpgp.Entity      // our Ed25519/Cv25519 keypair
    peerStates    map[string]*PeerState // email → Autocrypt peer state

    // Chat state
    chats         map[string]*ChatState // chatID → members, name, avatar, pins, etc.
    messages      map[string][]*Message // chatID → cached messages (sorted by date)
    drafts        map[string]*OutgoingMessage // chatID → draft
    blocked       map[string]bool       // email → blocked
    folders       map[string]*Folder    // local folders

    // Identity
    myAddr        string               // our email address
    myName        string               // our display name
    myStatus      string               // bio/status text

    // Config
    imapHost      string
    smtpHost      string
    showEmails    int                   // 0=off, 1=accepted, 2=all
    downloadLimit int64                 // bytes, 0=unlimited

    // Active calls
    activeCalls   map[string]*callState // callID → WebRTC state

    // Concurrency
    mu            sync.RWMutex
    updateHandler func(Update)
    done          chan struct{}
}

type PeerState struct {
    Addr               string
    LastSeen           time.Time
    AutocryptTimestamp time.Time
    PublicKey          *openpgp.Entity
    PreferEncrypt      string // "mutual" or ""
    GossipTimestamp    time.Time
    GossipKey          *openpgp.Entity
}

type ChatState struct {
    ID          string
    Type        ChatType  // dm, group, channel (broadcast)
    Title       string
    Description string
    Members     []string  // email addresses
    PastMembers []string  // removed members (tombstones, 60 days)
    AvatarB64   string
    GroupID     string    // Chat-Group-ID or Chat-List-ID
    IsProtected bool      // Chat-Verified
    Visibility  int       // 0=normal, 1=archived, 2=pinned
    MuteUntil   *time.Time // nil=not muted
    Pins        map[string]bool // msgID → pinned
    EphemeralTimer int    // seconds, 0=off
    BroadcastSecret []byte // for channels only
}
```

### Chat ID Scheme
- DMs: `dm:<canonicalized-email>` (e.g., `dm:bob@example.org`)
- Groups: `grp:<Chat-Group-ID>` (e.g., `grp:a1b2c3d4`)
- Broadcasts: `bc:<Chat-List-ID>` (e.g., `bc:x9y8z7`)
- Self-chat: `dm:<own-email>` (saved messages)

### Message ID
RFC 5322 `Message-ID` header value. Globally unique, cross-device consistent.
- DM format: `<Mr.RANDOM@domain>`
- Group format: `<Gr.GRPID.RANDOM@domain>`

---

## 29. Dependencies

All pure Go, no CGo. Cross-platform (linux, windows, darwin, android, js/wasm).

```
github.com/emersion/go-imap/v2       // IMAP4rev2 client
github.com/emersion/go-smtp          // ESMTP client
github.com/emersion/go-message       // RFC 5322 MIME read/write
github.com/emersion/go-sasl          // SASL auth (PLAIN, XOAUTH2)
github.com/ProtonMail/go-crypto      // OpenPGP (Autocrypt E2EE)
```

---

## 30. Differences from Other Cores

| Aspect | Telegram/Bale/Rubika | Delta Chat |
|--------|---------------------|------------|
| Transport | Proprietary protocol / WebSocket | Standard IMAP + SMTP |
| Server | Platform-specific | Any email server |
| Real-time | Persistent connection | IMAP IDLE (3 connections) |
| Encryption | Platform E2EE | Autocrypt (OpenPGP/PGP-MIME) |
| Groups | Server-managed | Email headers + conventions |
| Channels | Server-managed | Broadcast lists (symmetric encryption) |
| User ID | Phone / internal ID | Email address |
| Session | Auth token / MTProto | IMAP + SMTP credentials |
| File limits | 2GB / 50MB / 19.5MB | ~18 MB (provider-dependent) |
| Calls | Platform VoIP | WebRTC + email signaling (latency-dependent) |
| Bot mode | Bot token API | N/A (bots = regular email accounts) |
| Reactions | Platform-specific | RFC 9078 (Content-Disposition: reaction) |
| Stickers | Platform sticker packs | `Chat-Content: sticker` on image |
| Online status | Yes | No (email has no presence) |
| Typing indicator | Yes | No (email has no concept) |
| Message ordering | Server-guaranteed | NOT guaranteed — sort by Date + Message-ID |
| Polling | Native | Convention-based (structured text) |

---

## 31. Caveats and Gotchas

1. **IMAP IDLE reliability varies wildly** across providers. Some have 30-minute timeouts, some disconnect silently. Must implement reconnection with exponential backoff.

2. **Email delivery latency** is 0.2s-30s+ depending on provider. Chatmail servers are sub-second. This affects call setup time significantly.

3. **Autocrypt key gossip** is the only way group members learn each other's keys. If a member joins without gossip, they can't decrypt messages from unknown members.

4. **Message ordering** is NOT guaranteed in email. Messages may arrive out of order. Sort by `Date` header with `Message-ID` as tiebreaker.

5. **Quota/rate limits** vary by provider. Gmail: ~500 messages/day free. Some providers reject rapid-fire messages.

6. **Base64 overhead**: email attachments are Base64-encoded, inflating size by ~33%. 50 MB limit → ~37.5 MB usable.

7. **BCC self**: DC BCCs itself on sent messages for IMAP. Some providers don't support this well — use IMAP APPEND as fallback.

8. **Multiple devices**: Autocrypt Setup Message transfers keys. One-time manual process with 44-digit passphrase.

9. **No online status**. No typing indicators. Email has no presence concept.

10. **Chat-Version placement**: MUST be in outer (unprotected) headers for IMAP fetch. Other `Chat-*` headers go in inner (encrypted) part.

11. **DeltaChat folder**: DC moves messages from INBOX → DeltaChat for coexistence with regular email clients.

12. **First sync is expensive**: must scan ALL message headers to build chat list. Cache locally, only fetch new UIDs on reconnect.

13. **Group membership drift**: member list built from first message + add/remove headers. Missing a message can cause drift. Careful IMAP sync is critical.

14. **Provider compatibility**: not all IMAP servers support IDLE, QUOTA, METADATA. Degrade gracefully.

15. **Self-chat BCC**: multi-device sync uses BCC-self messages. Requires `BccSelf` enabled.

---

## 32. Estimated Implementation Size

Based on other cores (Bale: 4092 lines, Rubika: 3484 lines), Delta Chat will likely be **4000-5000 lines**:
- IMAP/SMTP connection management: ~500 lines
- MIME message construction/parsing: ~800 lines
- Autocrypt (keygen, peer state, encrypt/decrypt, gossip): ~600 lines
- Group management (headers, member tracking, conflict resolution): ~400 lines
- Broadcast channels: ~300 lines
- Reactions (RFC 9078): ~150 lines
- Calls (WebRTC signaling): ~400 lines
- All Core interface methods: ~800 lines
- IDLE loop, reconnection, sync: ~500 lines
- Local cache, search, folders: ~300 lines
- Server auto-discovery: ~200 lines
