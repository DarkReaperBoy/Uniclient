# Rubika Protocol — Reverse-Engineered Specification

**Sources**: rubpy library (github.com/shayanheidari01/rubika) + official Rubika JS web client (m.rubika.ir/static/js/main.5a6e7f59.js)
**Last updated**: 2026-04-13

---

## 1. Overview

Rubika uses an HTTP-based API with AES-256-CBC encrypted payloads. Real-time updates come via WebSocket (WSS). There's a separate unencrypted Bot API at a different endpoint.

**Transport**: HTTP POST (API calls) + WSS (real-time updates)
**Encryption**: AES-256-CBC with static zero IV, PKCS7 padding, Base64-encoded
**Auth**: 32-char auth key, RSA-1024 for key exchange during sign-in

---

## 2. Data Center Discovery

<!-- Discovered 2026-04-05 -->

**Endpoint**: `GET https://getdcmess.iranlms.ir/`

**Response**:
```json
{
  "data": {
    "API": {
      "1": "https://api1.iranlms.ir/",
      "2": "https://api2.iranlms.ir/"
    },
    "socket": {
      "1": "wss://socket1.iranlms.ir",
      "2": "wss://socket2.iranlms.ir"
    },
    "default_api": "1",
    "default_apis": ["1", "2"],
    "default_socket": "1"
  }
}
```

- Multiple API endpoints available for failover
- `default_apis` defines priority order
- Socket URLs for WebSocket real-time connection
- On request failure, try next endpoint in priority list (exponential backoff: 1s base, 2^attempt)

---

## 3. Encryption

<!-- Discovered 2026-04-05 -->

### 3.1 Auth Key

32-character alphanumeric string. Generated randomly during first registration, or received encrypted via RSA during sign-in.

### 3.2 decode_auth — Auth → Wire Format

Applied to auth before sending in HTTP request `auth` field:

```
For lowercase char c: chr(((32 - (ord(c) - 97)) % 26) + 97)
For uppercase char c: chr(((29 - (ord(c) - 65)) % 26) + 65)  
For digit char c:     chr(((13 - (ord(c) - 48)) % 10) + 48)
Other chars: unchanged
```

This is a reversible substitution cipher.

### 3.3 passphrase — Auth → AES Key

Derives the 32-byte AES key from the 32-char auth string:

```
1. Split auth into 4 chunks of 8 chars: [c0, c1, c2, c3]
2. Rearrange: c2 + c0 + c3 + c1
3. For each char c in the rearranged string:
     if c is digit ('0'-'9'):
       new_char = chr(((ord(c) - ord('0') + 5) % 10) + ord('0'))
     else (lowercase letter):
       new_char = chr(((ord(c) - ord('a') + 9) % 26) + ord('a'))
```

<!-- Discovered 2026-04-05: rubpy only handles letters (+9 mod 26). The official JS web client
     also handles digits (+5 mod 10). Verified by comparing function `u` in main.5a6e7f59.js
     with rubpy's Crypto.passphrase(). Auth keys can contain digits! -->

Result is 32 chars — used as AES-256-CBC key (encoded to bytes as UTF-8).

### 3.4 AES-256-CBC Encrypt/Decrypt

- **Algorithm**: AES-256-CBC
- **IV**: 16 zero bytes (`\x00` * 16) — STATIC, always zeros
- **Padding**: PKCS7 (to AES block size = 16 bytes)
- **Encoding**: Base64 URL-safe

**Encrypt**: JSON → UTF-8 bytes → PKCS7 pad → AES-CBC encrypt → Base64 encode
**Decrypt**: Base64 decode → AES-CBC decrypt → PKCS7 unpad → UTF-8 → JSON parse

### 3.5 RSA Signature (API v6)

For authenticated requests (not tmp_session), the `data_enc` field is also signed:

- **Algorithm**: RSA PKCS#1 v1.5 with SHA-256
- **Key size**: 1024 bits (generated client-side during registration)
- **Format**: Base64-encoded signature in the `sign` field

### 3.6 RSA OAEP Decryption (Sign-In)

During sign-in, server returns auth key encrypted with client's RSA public key:
- **Algorithm**: RSA OAEP (PKCS#1 OAEP)
- **Decrypted result**: 32-char auth key string

---

## 4. API Request/Response Format

<!-- Discovered 2026-04-05 -->

### 4.1 User API (api_version: "6")

**Authenticated request**:
```json
{
  "api_version": "6",
  "auth": "<decode_auth(auth_key)>",
  "data_enc": "<AES_encrypted_payload>",
  "sign": "<RSA_signature_of_data_enc>"
}
```

**Temporary session request** (during auth flow):
```json
{
  "api_version": "6",
  "tmp_session": "<temp_auth>",
  "data_enc": "<AES_encrypted_payload>"
}
```

**Payload structure (before encryption)**:
```json
{
  "client": {
    "app_name": "Main",
    "app_version": "2.4.6",
    "platform": "PWA",
    "package": "m.rubika.ir",
    "lang_code": "fa"
  },
  "method": "methodName",
  "input": { ... }
}
```

**Response**:
```json
{
  "data_enc": "<AES_encrypted_response>"
}
```

**Decrypted response**:
```json
{
  "status": "OK",
  "status_det": "OK",
  "data": { ... }
}
```

### 4.2 HTTP Headers

**PWA (Web) mode**:
```
origin: https://m.rubika.ir
referer: https://m.rubika.ir/
content-type: application/json
connection: keep-alive
user-agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/102.0.0.0 Safari/537.36
```

**Android mode**:
```
content-type: application/json
connection: keep-alive
user-agent: okhttp/3.12.1
```
(No origin/referer headers for Android)

### 4.3 Platform Configs

| Field | PWA | Android |
|-------|-----|---------|
| app_name | Main | Main |
| app_version | 2.4.6 | 3.8.2 |
| platform | PWA | Android |
| package | m.rubika.ir | app.rbmain.a |

---

## 5. Authentication Flow

<!-- Discovered 2026-04-05 -->

### Step 1: Generate temporary auth + key

If no stored session, generate:
- `auth` = 32 random lowercase chars
- `key` = passphrase(auth)

### Step 2: registerDevice

```
Method: registerDevice
Uses: tmp_session (temporary auth)
Input:
{
  "token": "",
  "lang_code": "fa",
  "token_type": "Firebase",
  "app_version": "PW_2.4.6",        // or "MA_3.8.2" for Android
  "system_version": "Windows 10",    // parsed from user-agent
  "device_model": "Chrome 102",      // parsed from user-agent
  "device_hash": "2<digits_from_ua>" // "2" + all digits from user-agent string
}
```

### Step 3: sendCode

```
Method: sendCode
Uses: tmp_session
Input:
{
  "phone_number": "989123456789",
  "send_type": "SMS",          // or "Internal"
  "pass_key": null             // optional, for 2FA
}
Response:
{
  "status": "OK",              // or "SendPassKey" if 2FA needed
  "phone_code_hash": "..."
}
```

Phone format: strip leading 0, prepend country code (98 for Iran).

If `status == "SendPassKey"`, prompt user for password, re-call sendCode with `pass_key`.

### Step 4: Generate RSA keypair

```
1. Generate 1024-bit RSA keypair
2. Export public key as DER bytes
3. Base64-encode the public key bytes  
4. Apply decode_auth() transformation to the base64 string
5. Send transformed public key in signIn
```

### Step 5: signIn

```
Method: signIn
Uses: tmp_session
Input:
{
  "phone_code": "123456",
  "phone_number": "989123456789",
  "phone_code_hash": "<from_sendCode>",
  "public_key": "<decoded_auth_transformed_base64_public_key>"
}
Response (status == "OK"):
{
  "auth": "<RSA_OAEP_encrypted_auth_key>",
  "user": {
    "user_guid": "u0...",
    "phone": "989123456789",
    ...
  }
}
```

### Step 6: Decrypt and store

```
1. RSA OAEP decrypt response.auth using private key → 32-char auth string
2. key = passphrase(auth)
3. decode_auth_val = decode_auth(auth)
4. Store: auth, guid, user_agent, phone, private_key to session
5. Call registerDevice again with proper device_model
```

### Session Storage

Persisted fields:
- `phone_number`: string
- `auth`: 32-char auth key
- `guid`: user GUID (e.g., "u0ABC123...")
- `user_agent`: browser user-agent string
- `private_key`: RSA private key (PEM)

---

## 6. API Methods — Messages

<!-- Discovered 2026-04-05 -->

### sendMessage
```json
{
  "object_guid": "<recipient_guid>",
  "text": "Hello",
  "rnd": 123456,
  "reply_to_message_id": "<optional>",
  "metadata": [
    {"type": "bold", "start": 0, "length": 5}
  ]
}
```
With file: add `file_inline` object (see File Upload section).

### editMessage
```json
{
  "object_guid": "<guid>",
  "message_id": "<msg_id>",
  "text": "Edited text"
}
```

### deleteMessages
```json
{
  "object_guid": "<guid>",
  "message_ids": ["<id1>", "<id2>"],
  "type": "Global"       // or "Local"
}
```

### forwardMessages
```json
{
  "from_object_guid": "<source_guid>",
  "to_object_guid": "<dest_guid>",
  "message_ids": ["<id1>"],
  "rnd": 123456
}
```

### getMessages
```json
{
  "object_guid": "<guid>",
  "sort": "FromMax",      // or "FromMin"
  "max_id": "<msg_id>",
  "limit": "20"
}
```

### setPinMessage
```json
{
  "object_guid": "<guid>",
  "message_id": "<msg_id>",
  "action": "Pin"         // or "Unpin"
}
```

### actionOnMessageReaction
```json
{
  "object_guid": "<guid>",
  "message_id": "<msg_id>",
  "action": "Add",        // or "Remove"
  "reaction_id": 1
}
```

### createPoll
```json
{
  "object_guid": "<guid>",
  "question": "Poll question",
  "options": ["Option A", "Option B", "Option C"],
  "type": "Regular",       // or "Quiz"
  "is_anonymous": true,
  "allows_multiple_answers": true,
  "rnd": 123456
}
```

---

## 7. API Methods — Chats & Dialogs

<!-- Discovered 2026-04-05 -->

### getChats
```json
{
  "start_id": null         // pagination cursor, null for first page
}
```

### getChatsUpdates
```json
{
  "state": 1712300000      // unix timestamp, typically now - 150
}
```

### seenChats
```json
{
  "seen_list": {
    "<chat_guid>": "<last_seen_msg_id>",
    "<chat_guid2>": "<msg_id2>"
  }
}
```

### searchChatMessages
<!-- method discovered but input TBD -->

---

## 8. API Methods — Groups

<!-- Discovered 2026-04-05 -->

### addGroup
```json
{
  "title": "Group Name",
  "member_guids": ["<user_guid1>", "<user_guid2>"],
  "description": "Optional description"
}
```

### getGroupInfo
```json
{"group_guid": "<guid>"}
```

### editGroupInfo
<!-- method exists, input TBD -->

### setGroupAdmin
<!-- method exists for admin management -->

### getGroupAllMembers
<!-- method exists for member listing -->

### getGroupOnlineCount
<!-- method exists -->

### joinGroup / leaveGroup
<!-- method exists -->

### banGroupMember / getGroupAdminMembers
<!-- methods exist -->

---

## 9. API Methods — Channels

<!-- Discovered 2026-04-05 -->

### addChannel
```json
{
  "title": "Channel Name",
  "description": "Optional description",
  "member_guids": ["<guid1>"]
}
```

### getChannelInfo
```json
{"channel_guid": "<guid>"}
```

### joinChannelAction / joinChannelByLink
<!-- methods exist -->

### addChannelMembers / banChannelMember
<!-- methods exist -->

### editChannelInfo / getChannelAllMembers
<!-- methods exist -->

### seenChannelMessages
<!-- method exists -->

---

## 10. API Methods — Users & Profile

<!-- Discovered 2026-04-05 -->

### getUserInfo
```json
{}                         // empty = get self
// or
{"user_guid": "<guid>"}   // get other user
```

### updateProfile
<!-- method exists in settings -->

### updateUsername / checkUserUsername
<!-- methods exist -->

---

## 11. API Methods — Settings

<!-- Discovered 2026-04-05 -->

### getFolders
```json
{"last_state": 1712300000}
```

### getMySessions
<!-- method exists -->

### terminateSession / terminateOtherSessions
<!-- methods exist -->

### getBlockedUsers
<!-- method exists -->

### getPrivacySetting / setSetting
<!-- methods exist -->

### getTwoPasscodeStatus / setupTwoStepVerification
<!-- methods exist -->

---

## 12. API Methods — Stickers

<!-- Discovered 2026-04-05 -->

### getMyStickerSets / getStickerSetById / getStickersBySetIds
### getStickersByEmoji / searchStickers / getTrendStickerSets
### actionOnStickerSet
<!-- All methods exist in rubpy source -->

---

## 13. API Methods — Misc

### getObjectByUsername
```json
{"username": "username"}
```
Resolves username to user/group/channel info.

### searchGlobalObjects
<!-- Global search method -->

### getAbsObjects
```json
{"objects_guids": ["<guid1>", "<guid2>"]}
```
Batch resolve GUIDs to their info.

### getTime
<!-- Server time -->

### getLinkFromAppUrl
<!-- Resolve app URLs -->

---

## 14. File Upload

<!-- Discovered 2026-04-05 -->

### Step 1: requestSendFile
```json
{
  "file_name": "photo.jpg",
  "size": 1048576,
  "mime": "jpg"            // file extension, not full MIME type
}
Response:
{
  "id": "<file_id>",
  "dc_id": 2,
  "upload_url": "https://upload2.iranlms.ir/UploadFile.ashx",
  "access_hash_send": "<hash>"
}
```

### Step 2: Upload Chunks

```
POST <upload_url>
Headers:
  auth: <raw_auth_key>        (NOT decode_auth!)
  file-id: <file_id>
  total-part: <total_chunks>
  part-number: <1-based_index>
  chunk-size: <bytes_in_chunk>
  access-hash-send: <hash>
Body: <raw_chunk_bytes>

Response:
{
  "status": "OK",
  "status_det": "OK",
  "data": {
    "access_hash_rec": "<hash_for_download>"  // only in last chunk
  }
}
```

- **Default chunk size**: 1 MB (1048576 bytes)
- **Part numbers**: 1-based
- If response status is `"ERROR_TRY_AGAIN"`, call requestSendFile again and restart from part 1

### Step 3: Send message with file_inline

```json
{
  "object_guid": "<guid>",
  "text": "caption",
  "file_inline": {
    "file_id": "<file_id>",
    "dc_id": 2,
    "size": 1048576,
    "type": "Image",         // Image | Video | File | Music | Voice | Gif
    "mime": "jpg",
    "access_hash_rec": "<hash>",
    "width": 800,
    "height": 600,
    "time": 0,               // duration in ms for video/audio
    "is_spoil": false,
    "is_round": false,        // true for video messages
    "music_performer": "",
    "thumb_inline": "<base64_thumbnail>"
  },
  "rnd": 123456
}
```

---

## 15. File Download

<!-- Discovered 2026-04-05 -->

```
POST https://messenger<dc_id>.iranlms.ir/GetFile.ashx
Headers:
  auth: <raw_auth_key>
  access-hash-rec: <hash>
  file-id: <file_id>
  user-agent: <user_agent>
  start-index: <byte_offset>        // 0-based
  last-index: <end_byte_offset>     // inclusive
Response: raw bytes
```

- **Default chunk size**: 128 KB (131072 bytes)
- Range is inclusive both ends
- Can parallelize chunk downloads

---

## 16. WebSocket — Real-Time Updates

<!-- Discovered 2026-04-05 -->

### Connection

Connect to WSS URL from DC discovery response.

### Handshake

Send immediately after connecting:
```json
{
  "method": "handShake",
  "auth": "<raw_auth_key>",
  "api_version": "6",
  "data": ""
}
```

### Keepalive

Send empty JSON `{}` every 10 seconds.
Also poll `getChatsUpdates` every 10 seconds for redundancy.

### Incoming Updates

```json
{
  "data_enc": "<AES_encrypted_update>"
}
```

Decrypt with passphrase-derived key. Decrypted structure:

```json
{
  "user_guid": "<current_user_guid>",
  "message": [
    {
      "message_id": "...",
      "object_guid": "...",
      "author_guid": "...",
      "time": 1712300000,
      "text": "Hello",
      ...
    }
  ],
  "chat": [
    {
      "object_guid": "...",
      "last_message_id": "...",
      "unread_count": 3,
      ...
    }
  ]
}
```

Update types (key names in decrypted JSON):
- `message` — new/edited messages
- `chat` — chat list changes
- `chat_update` — chat info changes
- `user` — user info changes
- `reaction` — message reactions

Each key maps to a list of update objects.

### Auto-Reconnect

On disconnect/timeout, wait 3 seconds and reconnect. Re-send handshake.

---

## 17. Bot API

<!-- Discovered 2026-04-05 -->

Completely separate from user API. **No encryption**.

### Base URL

```
https://botapi.rubika.ir/v3/<bot_token>/
```

### Request Format

```
POST https://botapi.rubika.ir/v3/<token>/<method>
Content-Type: application/json
Body: <raw_json_input>
```

### Official Methods (from rubika.ir/botapi)

<!-- Discovered 2026-04-05 from official documentation at rubika.ir/botapi/methods -->

| Method | Description | Key Params |
|--------|-------------|------------|
| `getMe` | Bot info (name, username, id, avatar) | — |
| `sendMessage` | Send text with optional keypads | `chat_id`, `text`, `chat_keypad`, `inline_keypad`, `reply_to_message_id`, `chat_keypad_type` |
| `sendFile` | Send uploaded file | `chat_id`, `file_id`, `text` |
| `sendPoll` | Send poll | `chat_id`, `question`, `options` |
| `sendLocation` | Send coordinates | `chat_id`, `latitude`, `longitude` |
| `sendContact` | Send contact card | `chat_id`, `phone_number`, `first_name`, `last_name` |
| `editMessageText` | Edit message text | `chat_id`, `message_id`, `text` |
| `editMessageKeypad` | Edit inline keypad | `chat_id`, `message_id`, `inline_keypad` |
| `editChatKeypad` | Update/remove chat keyboard | `chat_id`, `chat_keypad`, `chat_keypad_type` ("New"/"Remove") |
| `deleteMessage` | Delete a message | `chat_id`, `message_id` |
| `forwardMessage` | Forward message | `from_chat_id`, `message_id`, `to_chat_id` |
| `getChat` | Get chat info | `chat_id` |
| `getUpdates` | Poll for updates | `offset_id`, `limit` |
| `setCommands` | Set bot commands | `bot_commands` (list of `{command, description}`) |
| `updateBotEndpoints` | Set webhook URL | `url`, `type` ("ReceiveUpdate"/"ReceiveInlineMessage"/etc.) |
| `requestSendFile` | Get upload URL | `type` ("File"/"Image"/"Voice"/"Video"/"Music"/"Gif") |
| `getFile` | Get download URL | `file_id` → returns `download_url` |
| `banChatMember` | Ban user from group/channel | `chat_id`, `user_id` |
| `unbanChatMember` | Unban user | `chat_id`, `user_id` |

### Update Types (webhook/polling)

- `NewMessage` — new message received
- `UpdatedMessage` — message edited
- `RemovedMessage` — message deleted
- `StartedBot` — user started the bot
- `StoppedBot` — user stopped the bot

### Button Types

`Simple`, `Selection`, `Calendar`, `NumberPicker`, `StringPicker`, `Location`, `Camera`, `Gallery`, `File`, `Audio`, `Textbox`, `Link`, `AskMyPhoneNumber`, `AskMyLocation`, `Barcode`

### Endpoint Types (webhook)

`ReceiveUpdate`, `ReceiveInlineMessage`, `ReceiveQuery`, `GetSelectionItem`, `SearchSelectionItems`

### Constraints

- Bots only see mentions and `/` commands unless "receive all messages" enabled in @BotFather
- Max 10 admin bots per group/channel
- Manual admin addition only (no link invites)
- Bots can't detect edits/deletions from other bots
- `inline_keypad` and `chat_keypad` are **DM-only** — INVALID_INPUT in groups/channels
- `sendContact` is **DM-only** — INVALID_INPUT in groups
- Group `chat_id` from `getUpdates` uses `g0{hash}` (different hash from web URL)
- Bot DM `chat_id` uses composite format `b0{userHash}{botHash}`

---

## 18. Error Codes

<!-- Discovered 2026-04-05 -->

| status | status_det | Meaning |
|--------|-----------|---------|
| OK | OK | Success |
| ERROR | CodeIsUsed | Verification code already used |
| ERROR | TooRequests | Rate limited |
| ERROR | InvalidAuth | Auth token invalid |
| ERROR | NotRegistered | User not registered / session invalid |
| ERROR | CodeIsExpired | Verification code expired |
| ERROR | ServerError | Internal server error |
| ERROR | InvalidInput | Input validation failed |
| ERROR | Undeliverable | Message cannot be delivered |
| ERROR | InvalidMethod | Method not found |

---

## 19. GUID Format

<!-- Discovered 2026-04-05 -->

All entities use GUIDs as identifiers:
- Users: `u0XXXXXXXX...` (starts with `u0`)
- Groups: `g0XXXXXXXX...` (starts with `g0`)
- Channels: `c0XXXXXXXX...` (starts with `c0`)
- Bots: `b0XXXXXXXX...` (starts with `b0`)

The GUID prefix indicates entity type.

---

## 20. Text Formatting Metadata

<!-- Discovered 2026-04-05 -->

```json
{
  "metadata": [
    {"type": "bold", "start": 0, "length": 5},
    {"type": "italic", "start": 6, "length": 4},
    {"type": "mono", "start": 11, "length": 3},
    {"type": "underline", "start": 15, "length": 4},
    {"type": "strikethrough", "start": 20, "length": 3},
    {"type": "link", "start": 24, "length": 4, "link": "https://example.com"}
  ]
}
```

Types: `bold`, `italic`, `mono`, `underline`, `strikethrough`, `link`

---

## 21. Implementation Notes for Go

1. **AES key must be 32 bytes** — the passphrase function produces 32 chars (lowercase ASCII + digits), UTF-8 encoding gives 32 bytes.

2. **Static IV** — all zeros, never changes. This is a known weakness but it's how Rubika works.

3. **RSA 1024-bit** — weak by modern standards but required by the protocol.

4. **decode_auth is a substitution cipher** — must be applied to auth before sending in HTTP `auth` field. The raw auth is used for file upload/download headers and WebSocket handshake.

5. **File upload uses raw auth** (not decode_auth) in the `auth` header.

6. **requestSendFile mime** — uses file extension string (e.g., "jpg"), not full MIME type (e.g., not "image/jpeg").

7. **Message IDs are strings** — not integers.

8. **rnd field** — random integer 1 to 1,000,000, required for sendMessage/forwardMessages/createPoll.

9. **Phone number format** — strip leading 0, prepend country code (98 for Iran). E.g., 09134556255 → 989134556255.

10. **Retry with endpoint failover** — on HTTP failure, try next API endpoint from priority list before giving up.

11. **Base64 encoding** — use standard Base64 (not URL-safe). The official JS client uses CryptoJS which outputs standard Base64. rubpy uses `base64.urlsafe_b64decode` but this is incorrect per the JS client.

12. **App version** — current official PWA version is `2.5.4` (rubpy uses `2.4.6` which is outdated).

13. **DC response has 3 sections**: `API` (53 endpoints), `socket` (20 WSS endpoints), `storage` (800+ file storage endpoints). Use `storage` URLs for file download instead of hardcoded patterns.

14. **Auth methods skip signing** — sendCode, signIn, registerDevice, loginTwoStepForgetPassword, loginDisableTwoStep all use `disableSign: true` in the JS client. Only authenticated (post-login) requests include the RSA signature.

15. **Passphrase handles digits** — the official JS client applies `+5 mod 10` for digits in the passphrase derivation, not just `+9 mod 26` for letters. rubpy only handles letters (bug in rubpy).

16. **Multiple API versions**: `0` (BASE/SERVICE), `1` (HOME/VOD/WALLET), `2` (MESSENGER_V2), `4` (DC), `5` (MESSENGER — used for setPublicKey), `6` (MESSENGER_V6 — used for most messenger methods). Use `6` for all messenger operations.

---

## 22. Group Voice Chat / Calling

<!-- Discovered 2026-04-05 from rubpy voice_chat_player.py -->

Rubika uses **standard WebRTC** for group voice chats. Much simpler than Telegram's custom protocol.

### Flow

1. **Create voice chat**: `createGroupVoiceChat({chat_guid})` → returns `voice_chat_id`
2. **Create WebRTC offer**: Generate local `RTCPeerConnection`, add audio track, create SDP offer
3. **Join**: `joinGroupVoiceChat({chat_guid, voice_chat_id, sdp_offer_data, self_object_guid})` → returns `sdp_answer_data`
4. **Set remote SDP**: Set the answer on the PeerConnection → WebRTC connects
5. **Background loops**:
   - `sendGroupVoiceChatActivity(group_guid, voice_chat_id)` every **1 second** (speaking indicator)
   - `getGroupVoiceChatUpdates(group_guid, voice_chat_id, state)` every **10 seconds** (heartbeat/participants)
6. **State**: `setVoiceChatState(chat_guid, voice_chat_id, state)` after joining
7. **Leave**: `leaveGroupVoiceChat(group_guid, voice_chat_id)`
8. **End**: `discardChannelVoiceChat(channel_guid, voice_chat_id)` for channels

### API Methods

| Method | Input | Description |
|--------|-------|-------------|
| `createGroupVoiceChat` | `{chat_guid}` | Start voice chat, get voice_chat_id |
| `createChannelVoiceChat` | `{channel_guid}` | Start in channel |
| `joinGroupVoiceChat` | `{chat_guid, voice_chat_id, sdp_offer_data, self_object_guid}` | Join with SDP offer, get SDP answer |
| `joinChannelVoiceChat` | Same as above | Join channel voice chat |
| `leaveGroupVoiceChat` | `{group_guid, voice_chat_id}` | Leave |
| `discardChannelVoiceChat` | `{channel_guid, voice_chat_id}` | End channel voice chat |
| `setVoiceChatState` | `{chat_guid, voice_chat_id, state}` | Set state |
| `setGroupVoiceChatSetting` | `{group_guid, voice_chat_id, ...settings}` | Update settings |
| `setChannelVoiceChatSetting` | `{channel_guid, voice_chat_id, ...settings}` | Update settings |
| `getGroupVoiceChatUpdates` | `{group_guid, voice_chat_id, state}` | Get participants/updates |
| `sendGroupVoiceChatActivity` | `{group_guid, voice_chat_id}` | Speaking indicator |

### API Methods (verified 2026-04-12)

All use `chat_guid` (NOT `group_guid`) in the real web client:

| Method | Input | Description |
|--------|-------|-------------|
| `createGroupVoiceChat` | `{chat_guid}` | Start voice chat, returns `voice_chat_id` in `group_voice_chat_update` |
| `joinGroupVoiceChat` | `{chat_guid, voice_chat_id, sdp_offer_data, self_object_guid}` | Join with SDP offer, get SDP answer |
| `getGroupVoiceChatParticipants` | `{chat_guid, voice_chat_id}` | Get current participants |
| `getGroupVoiceChatUpdates` | `{chat_guid, voice_chat_id, state}` | Poll for participant/state updates |
| `sendGroupVoiceChatActivity` | `{group_guid, voice_chat_id, activity}` | Speaking heartbeat (1s interval) |
| `leaveGroupVoiceChat` | `{chat_guid, voice_chat_id}` | Leave (participant) |
| `discardGroupVoiceChat` | `{chat_guid, voice_chat_id}` | End call (creator/admin) |

### Server: Janus AudioBridge

The SDP answer reveals the server is **Janus WebRTC Gateway** (AudioBridge plugin):
- `s=AudioBridge 31225443` in SDP answer
- Standard Opus/48000/2 audio with `ssrc-audio-level` extension
- ICE candidates with both private (`10.x`) and public (`86.107.x`) IPs
- DTLS fingerprint `sha-256` with `setup:active`

### createGroupVoiceChat Response Formats <!-- Discovered 2026-04-12 -->

The `voice_chat_id` can appear in multiple locations depending on whether a VC already exists:

```
# New VC created:
{"group_voice_chat_update": {"voice_chat_id": "..."}}
# or:
{"chat_update": {"chat": {"group_voice_chat_id": "..."}}}

# VC already exists:
{"exist_group_voice_chat": {"voice_chat_id": "..."}}
```

Must check all three paths. The `getGroupInfo` response sometimes includes `group_voice_chat_id` in the `group` object, but this is **unreliable** — often absent even when a VC is active.

### joinGroupVoiceChat Response

Returns SDP answer in `sdp_answer_data` (string). On success, the `data` key may be null/missing — the answer is at the top level of the decrypted response. The response also sometimes returns the full decrypted payload without a `data` wrapper.

### ~~Janus Session Timeout~~ — FIXED <!-- Discovered 2026-04-13, fixed 2026-04-13 -->

**Previously**: WebRTC disconnected after ~60-63 seconds consistently. **Root cause**: `getGroupVoiceChatUpdates` `state` parameter was passed as empty string `""` instead of integer `0`. The API requires `state` as an integer (epoch-based). With empty string, the server's Janus session wasn't being refreshed, causing the 60s timeout.

**Fix**: Pass `state: 0` (int64) initially. Track the returned state from `timestamp` field in response (string containing epoch integer, e.g. `"1776038960"`). The state advances with each successful poll. With correct integer state, connections survive indefinitely (tested 3+ minutes).

**Note**: `getGroupVoiceChatUpdates` (polled every 15s) is the **sole** Janus session keepalive. `sendGroupVoiceChatActivity` is only a speaking indicator (4s debounce) and is NOT a keepalive.

### DTLS Connection Intermittency

WebRTC DTLS handshake succeeds only ~25% of attempts. Retry up to 10 times with 3-second delays. Failure mode: ICE connects but WebRTC state goes `connecting → disconnected → closed` without reaching `connected`.

### Implementation Notes

- Uses `pion/webrtc/v4` in Go (pure Go, no CGo)
- SDP offer/answer is standard WebRTC format (no custom encryption layer)
- Audio codec: Opus 48kHz stereo with `minptime=10;useinbandfec=1`
- No Telegram-style DH key exchange or E2E encryption — standard WebRTC DTLS/SRTP
- Voice chat ID is obtained from `createGroupVoiceChat` response (check 3 paths — see above)
- Background loops: heartbeat every 1s, updates poll every 10s, Opus keepalive every 20ms
- `setVoiceChatState` must be called after WebRTC connects (state `"1"`)
- RTCP must be drained from the receiver track (goroutine reading `receiver.ReadRTCP()`) or pion stalls
- Client config uses `app_version: "4.4.27"`, `platform: "Web"`, `package: "web.rubika.ir"` in real captures

---

## Quirks & Gotchas <!-- Discovered 2026-04-06 -->

### Encryption
- AES-256-CBC with **zero IV** (all zeros) — not AES-GCM. The `data_enc` field in every request/response uses this.
- RSA-1024 for `sign` field — weak by modern standards but required.
- `decode_auth` cipher for initial key derivation — custom, not a standard KDF.

### GUID parameter naming inconsistency
Different methods use different parameter names for the same chat identifier:
- `chat_guid` — voice chat join, create
- `group_guid` — group-specific methods (leave, settings, activity)
- `channel_guid` — channel-specific methods
- `object_guid` — generic methods (report, admin check, transcribe)
- `self_object_guid` — your own GUID, required in `joinGroupVoiceChat`

Getting the wrong param name = silent failure or cryptic error.

### DC failover
- Multiple messenger DCs: `messengerg2cXXX` (e.g., 458, 715, 168, 490).
- Client must retry on different DCs on 502 errors or 20s timeout.
- Service discovery via `getdcmess.iranlms.ir` (getDCs) and `servicesbase.iranlms.ir` (getBaseInfo).

### WebSocket
- Endpoint: `wss://nsocketXX.iranlms.ir:80/` (WSS on port 80, not 443).
- Must send `handShake` method with auth token after connecting.
- Heartbeat: send empty `{}` every ~30 seconds.

### Voice chat
- State values are `"Playing"` / `"Paused"` — NOT "unmuted"/"muted".
- `sendGroupVoiceChatActivity` heartbeat every ~1 second with activity `"Speaking"`.
- `getGroupVoiceChatUpdates` polled every ~10 seconds with a `state` timestamp.
- Creating a VC when one exists returns `exist_group_voice_chat` with existing ID.
- `loadMoreParticipantsApi` has trailing `Api` suffix unlike all other methods.
- Janus re-encodes ALL input as SILK Wideband (TOC `0x48`), even if input was CELT Fullband.
- Silence frames from Janus: `4806e379c12458` (7B) and `4806e37227dc0640` (8B), repeat constantly.
- Non-silence frames: 26-63 bytes, all unique, decode to real PCM via pion/opus pure Go.
- DataChannel rejected by Janus: `m=application 0 ... a=inactive` in SDP answer.
- Rate limit: ~15 voice chat creates before WebRTC connections start failing. Need 60-90s cooldown.
- Web client uses `RTCPeerConnection(null)` — no ICE servers. Janus provides server candidates in SDP answer.
- **~~Janus session timeout~~** — FIXED. Root cause: `state` param was string instead of int. With `state: 0` (int64), connection lives indefinitely.
- **DTLS intermittent**: only ~25% of WebRTC connection attempts succeed. ICE connects, DTLS fails silently.
- **`getGroupInfo` unreliable for VC discovery** — `group_voice_chat_id` often missing from response even when a VC is active. Use `createGroupVoiceChat` (returns existing VC) or pass VC ID explicitly.
- **`voice_chat_id` appears in 3 different response paths** — `exist_group_voice_chat.voice_chat_id`, `group_voice_chat_update.voice_chat_id`, `chat_update.chat.group_voice_chat_id`. Must check all three.
- **RTCP drain required** — must read RTCP from `receiver.ReadRTCP()` in a goroutine or pion/webrtc stalls.
- **`setVoiceChatState` required** — must call with `state: "1"` after WebRTC connects, otherwise Janus may not forward audio.
- **Intermittent HTTP 502** from API — affects heartbeats, auth, VC creation. All API calls need retry logic.

### API version
- `api_version` "6" for messenger API, "4"/"5" for service discovery, "0" for Rubino social media API.

### Error handling
- Some errors return HTTP 200 with error in decrypted payload — always check `status` != `"OK"`.

### Rubino Social Media API <!-- Discovered 2026-04-12 -->
- **Completely different transport**: plaintext JSON, no AES encryption, no RSA signature.
- **Auth**: sends raw `auth` token (NOT `decode_auth`).
- **Request format**: `{api_version: "0", auth: "<raw>", client: {...}, method: "...", data: {...}}`
- **Payload key**: `data` (plaintext), NOT `data_enc` (encrypted).
- **Endpoint**: `https://rubino{N}.iranlms.ir/` — multiple DCs, some return 502.
- **Headers**: must use `Content-Type: application/json` and `Origin: https://rubino.ir` (NOT `text/plain` or `web.rubika.ir`).
- **Pagination**: uses `sort: "FromMax"` + `equal: false` (NOT `start_id`). Some methods use `max_id` for cursor.
- **Profile ID pattern**: many methods need both `profile_id` (viewer/self) and `target_profile_id` (the profile being queried).
- **getProfileFollowers** handles both followers and followings — distinguished by `f_type: "Follower"` vs `"Following"`.
- **Contact/Location messages** (user API): use `message_contact` and `location` top-level keys in `sendMessage`, NOT `file_inline`.
- **editGroupInfo**: `chat_history_for_new_members` requires `updated_parameters` array containing the key name.

---

## Sources

- rubpy library: https://github.com/shayanheidari01/rubika (cloned to /tmp/rubika, read 2026-04-05)
- Key files analyzed: `network.py`, `crypto/crypto.py`, `methods/advanced/build.py`, `methods/utilities/start.py`, `methods/auth/`, `methods/messages/`, `methods/channels/`, `methods/groups/`, `bot/bot.py`
- Rubika web client HAR captures analyzed (2026-04-06) — confirmed voice chat flow, DC failover patterns, WebSocket heartbeats
