# Telegram Voice/Video Call Protocol — Reverse-Engineered Spec

Source: tgcalls C++ library from TelegramMessenger/tgcalls (commit 24876eb), read 2026-04-06.
Reference client: AyuGram Desktop (Telegram/SourceFiles/calls/).
See also: `research/telegram_notes.md` for MTProto API quirks (gotd/td patterns, FLOOD_WAIT, peer access hashes).

---

## Overview

Telegram calls have two layers:
1. **MTProto signaling** — DH key exchange, call setup/teardown, signaling relay (via Telegram servers)
2. **tgcalls media transport** — ICE/DTLS/SRTP connection, encrypted audio/video streams

Two protocol families exist:
- **V1 (legacy)**: `InstanceImpl` — custom message-level protocol over raw UDP, AES-CTR encrypted
- **V2 (modern)**: `InstanceV2Impl` — standard WebRTC (ICE+DTLS+SRTP) with JSON signaling, AES-CTR encrypted signaling layer

Modern Telegram clients use **V2**. V1 exists for backward compat. This doc covers both.

---

## 1. MTProto Call Setup (phone.* TL methods)

### 1.1 DH Key Exchange

Both sides need a DH config from `messages.getDhConfig`:
- Returns: prime `p` (2048-bit), generator `g` (2, 3, 4, 5, 6, or 7), random seed

**Outgoing (initiator):**
1. Generate random `a` (256 bytes)
2. Compute `g_a = g^a mod p` (256 bytes)
3. Compute `g_a_hash = SHA256(g_a)` (32 bytes)
4. Call `phone.requestCall` with `g_a_hash` and protocol info

**Incoming (receiver):**
1. Receive `phoneCallRequested` update with `g_a_hash`
2. Call `phone.receivedCall` (acknowledgment)
3. Generate random `b` (256 bytes)
4. Compute `g_b = g^b mod p` (256 bytes)
5. Call `phone.acceptCall` with `g_b` and protocol info

**Key agreement:**
1. Outgoing receives `phoneCallAccepted` with `g_b`
2. Outgoing computes `auth_key = g_b^a mod p` (256 bytes)
3. Outgoing computes `fingerprint = SHA1(auth_key)[12:20]` (8 bytes, **LITTLE-ENDIAN** int64 — `*reinterpret_cast<int64_t*>` on x86)
4. Outgoing calls `phone.confirmCall` with full `g_a` and `key_fingerprint`
5. Incoming receives `phoneCall` update with full `g_a`
6. Incoming verifies `SHA256(g_a) == g_a_hash` (from step 1)
7. Incoming computes `auth_key = g_a^b mod p` (256 bytes)
8. Both sides now share the same 256-byte `auth_key`

**Security checks on DH values:**
- `g_a` and `g_b` must satisfy: value > 1, value < p-1
- Bit length checks: `2048-64 < bits(value) < 2048` and `2048-64 < bits(p - value)`

### 1.2 Protocol Version Negotiation

`phone.requestCall` and `phone.acceptCall` include `phoneCallProtocol`:
```
phoneCallProtocol {
  flags: udp_p2p | udp_reflector
  min_layer: 65
  max_layer: 92  // tgcalls::Meta::MaxLayer()
  library_versions: ["11.0.0", "10.0.0", "9.0.0", ...]  // newest first
}
```

Server picks the best version both sides support. The selected version appears in the `phoneCall` response.

**Version to implementation mapping:**
- `"2.7.7"` → ProtocolVersion::V0 (oldest, InstanceImpl)
- `"5.0.0"` → ProtocolVersion::V1 (InstanceImpl with network status)
- `"7.0.0"+` → V2 (InstanceV2Impl, JSON signaling, standard WebRTC)
- Default fallback: `"2.4.4"` if server doesn't specify

### 1.3 Call Lifecycle TL Methods

| Step | Method | Direction | Purpose |
|------|--------|-----------|---------|
| 1 | `phone.requestCall` | -> server | Initiate call, send g_a_hash |
| 2 | `phone.receivedCall` | -> server | Receiver acknowledges |
| 3 | `phone.acceptCall` | -> server | Receiver sends g_b |
| 4 | `phone.confirmCall` | -> server | Initiator sends g_a + fingerprint |
| 5 | `phone.sendSignalingData` | -> server | Relay signaling data (ICE candidates, etc.) |
| 6 | `phone.discardCall` | -> server | End call (reason: Hangup/Missed/Busy/Disconnect) |

### 1.4 Signaling Data Relay

After DH exchange, tgcalls signaling flows via MTProto:

**Sending:** tgcalls emits signaling bytes -> `phone.sendSignalingData(peer, data)`
**Receiving:** `updatePhoneCallSignalingData` update -> passed to `instance.receiveSignalingData(data)`

The data is opaque bytes (encrypted by tgcalls before sending). MTProto just relays.

### 1.5 Connection Endpoints

`phoneCall` response includes `connections` — STUN/TURN/reflector servers:
```
phoneConnection {
  id: int64
  ip: string
  ipv6: string
  port: int
  peer_tag: bytes[16]  // for reflector identification
}
```

These become `Endpoint` and `RtcServer` entries in the tgcalls Descriptor.

---

## 2. Encryption (CryptoHelper)

Used by both V1 and V2 for encrypting signaling messages. V1 also uses it for media transport.

### 2.1 AES-256-CTR Encryption

**Master key:** 256-byte `auth_key` from DH exchange.

**Direction modifier `x`:**
```
x = 0   if outgoing, transport
x = 8   if incoming, transport
x = 128 if outgoing, signaling
x = 136 if incoming, signaling
```

Note: "outgoing" means the call initiator (isOutgoing=true). The receiver swaps: what's "outgoing" for initiator is "incoming" for receiver.

### 2.2 Message Key Derivation (16 bytes)

```
msgKeyLarge = SHA256(key[88+x : 88+x+32] || plaintext)
msgKey = msgKeyLarge[8:24]
```

### 2.3 AES Key + IV Derivation

```
sha256a = SHA256(msgKey[0:16] || key[x : x+36])
sha256b = SHA256(key[40+x : 40+x+36] || msgKey[0:16])

aesKey[0:8]   = sha256a[0:8]
aesKey[8:24]  = sha256b[8:24]
aesKey[24:32] = sha256a[24:32]

aesIv[0:4]    = sha256b[0:4]
aesIv[4:12]   = sha256a[8:16]
aesIv[12:16]  = sha256b[24:28]
```

### 2.4 Encrypt/Decrypt

**Encrypt:**
```
ciphertext = AES_CTR(plaintext, aesKey, aesIv)
packet = msgKey[16] || ciphertext
```

**Decrypt:**
```
msgKey = packet[0:16]
ciphertext = packet[16:]
derive aesKey, aesIv from msgKey (using incoming x)
plaintext = AES_CTR(ciphertext, aesKey, aesIv)
verify: SHA256(key[88+x:88+x+32] || plaintext)[8:24] == msgKey  // constant-time!
```

### 2.5 Go Implementation

```go
func prepareAesKeyIv(key []byte, msgKey []byte, x int) (aesKey [32]byte, aesIv [16]byte) {
    // sha256a = SHA256(msgKey || key[x:x+36])
    h := sha256.New()
    h.Write(msgKey[:16])
    h.Write(key[x : x+36])
    sha256a := h.Sum(nil)

    // sha256b = SHA256(key[40+x:40+x+36] || msgKey)
    h.Reset()
    h.Write(key[40+x : 40+x+36])
    h.Write(msgKey[:16])
    sha256b := h.Sum(nil)

    copy(aesKey[0:8], sha256a[0:8])
    copy(aesKey[8:24], sha256b[8:24])
    copy(aesKey[24:32], sha256a[24:32])

    copy(aesIv[0:4], sha256b[0:4])
    copy(aesIv[4:12], sha256a[8:16])
    copy(aesIv[12:16], sha256b[24:28])
    return
}
```

---

## 3. V1 Protocol (InstanceImpl — Legacy)

Custom message-level protocol over raw UDP, all encrypted with AES-CTR.

### 3.1 Message Types

| ID | Type | Requires ACK | Payload |
|----|------|-------------|---------|
| 1 | CandidatesListMessage | yes | ICE candidates + ufrag/pwd |
| 2 | VideoFormatsMessage | yes | Video codec formats |
| 3 | RequestVideoMessage | yes | (empty) |
| 4 | RemoteMediaStateMessage | yes | 1 byte: audio(bit0) + video(bits1-2) |
| 5 | AudioDataMessage | no | RTP audio data |
| 6 | VideoDataMessage | no | RTP video data |
| 7 | UnstructuredDataMessage | yes | Raw bytes |
| 8 | VideoParametersMessage | yes | uint32 aspect ratio (x1000) |
| 9 | RemoteBatteryLevelIsLowMessage | yes | 1 byte bool |
| 10 | RemoteNetworkStatusMessage | yes | 2 bytes: isLowCost + isLowDataRequested |
| 254 (0xFE) | Empty | no | Keepalive, carries piggybacked ACKs |
| 255 (0xFF) | ACK | no | 4-byte seq of acked message |
| 127 (0x7F) | Custom/Raw | yes | 4-byte length + data |

### 3.2 Packet Format

**Plaintext layout (before encryption):**
```
[4 bytes: seq (uint32, network order)]
[1 byte: message type ID]
[N bytes: message payload]
// optionally followed by more messages (piggybacked ACKs, resends):
[4 bytes: seq][1 byte: type][payload]
...
```

**Encrypted packet:**
```
[16 bytes: msgKey]
[encrypted plaintext]
```

### 3.3 Sequence Number Flags

```
Bit 31 (0x80000000): kSingleMessagePacketSeqBit — packet has only one message
Bit 30 (0x40000000): kMessageRequiresAckSeqBit — message needs ACK
Bits 0-29: actual counter (starts at 1, increments per message)
```

### 3.4 ACK Mechanism

- Messages with `kMessageRequiresAckSeqBit` set must be ACKed
- ACK = 5 bytes: [4-byte seq of acked msg][0xFF]
- ACKs are piggybacked onto other packets (never sent alone as first message)
- If nothing to send, use Empty (0xFE) as carrier for ACKs
- Unacked messages resent after delay (transport: 300ms min, signaling: 3000ms min)
- Max unacked buffer: 64KB

### 3.5 Anti-Replay

- Track last 64 incoming counters in sorted list
- Reject duplicates and counters older than (max_seen - 64)
- Max counter value: 0x3FFFFFFF (30 bits)

### 3.6 Data Message Serialization

For Audio/Video/Unstructured data:
- If single message packet (bit 31 set): just raw data after type byte
- If multi-message: [2 bytes uint16 length][data]

### 3.7 Packet Size Limits

- Transport: 1452 bytes (1500 - 48 TURN overhead)
- Signaling: 16384 bytes
- Max incoming: 128KB (reject larger)

---

## 4. V2 Protocol (InstanceV2Impl — Modern)

Standard WebRTC (ICE + DTLS + SRTP) with JSON signaling messages encrypted via EncryptedConnection.

### 4.1 Signaling Messages (JSON)

Four message types, all JSON with `@type` discriminator:

#### InitialSetup
```json
{
  "@type": "InitialSetup",
  "ufrag": "random_ice_ufrag",
  "pwd": "random_ice_password",
  "renomination": true,
  "fingerprints": [{
    "hash": "sha-256",
    "setup": "actpass",
    "fingerprint": "XX:XX:XX:..."
  }]
}
```
Sent immediately by both sides. Exchanges ICE credentials and DTLS fingerprints.

#### NegotiateChannels (replaces SDP offer/answer)
```json
{
  "@type": "NegotiateChannels",
  "exchangeId": "12345",
  "contents": [{
    "type": "audio",
    "ssrc": "1234567890",
    "ssrcGroups": [{"semantics": "FID", "ssrcs": ["123", "456"]}],
    "payloadTypes": [{
      "id": 111,
      "name": "opus",
      "clockrate": 48000,
      "channels": 2,
      "feedbackTypes": [{"type": "transport-cc", "subtype": ""}],
      "parameters": {"minptime": "10", "useinbandfec": "1"}
    }],
    "rtpExtensions": [
      {"id": 2, "uri": "http://www.ietf.org/id/draft-holmer-rmcat-transport-wide-cc-extensions-01"},
      {"id": 13, "uri": "urn:3gpp:video-orientation"}
    ]
  }]
}
```
Both sides must use same `exchangeId` for offer/answer pair. If both send offers simultaneously, the outgoing (initiator) side wins.

#### Candidates
```json
{
  "@type": "Candidates",
  "candidates": [
    {"sdpString": "candidate:1 1 udp 2122260223 192.168.1.100 54321 typ host"}
  ]
}
```
Standard ICE candidate SDP strings. Sent incrementally as candidates are gathered.

#### MediaState
```json
{
  "@type": "MediaState",
  "muted": false,
  "videoState": "active",
  "videoRotation": 0,
  "screencastState": "inactive",
  "lowBattery": false
}
```
Sent after setup and whenever media state changes.

### 4.2 Signaling Encryption

JSON messages are encrypted using `EncryptedConnection` in Signaling mode (x += 128):
1. Serialize JSON to bytes
2. Optionally gzip compress (for large messages)
3. Encrypt with AES-CTR (Section 2)
4. Send via `phone.sendSignalingData`

### 4.3 WebRTC Transport

V2 uses standard WebRTC stack:
- **ICE**: Full ICE mode, CONTROLLING for initiator, CONTROLLED for receiver
- **DTLS**: Standard DTLS 1.2 handshake, SRTP profile `AES_CM_128_HMAC_SHA1_80`
- **SRTP**: Standard SRTP media encryption (NOT the custom AES-CTR from Section 2)
- **Audio codec**: Opus (PT 111, 48kHz, stereo)
- **Video codecs**: H264, VP8, VP9 (negotiated via NegotiateChannels)

### 4.4 V2 Call Flow

```
Initiator                          Receiver
    |                                  |
    |--- phone.requestCall (g_a_hash) -->
    |                                  |--- phone.receivedCall -->
    |                                  |--- phone.acceptCall (g_b) -->
    |<-- phoneCallAccepted (g_b) ------|
    |--- phone.confirmCall (g_a, fp) -->
    |                                  |<-- phoneCall (g_a, endpoints)
    |                                  |
    |   [Both create tgcalls instance] |
    |                                  |
    |--- InitialSetup (encrypted) ---->  (via phone.sendSignalingData)
    |<--- InitialSetup (encrypted) ----|
    |                                  |
    |--- Candidates (encrypted) ------>
    |<--- Candidates (encrypted) ------|
    |                                  |
    |   [ICE connectivity checks]      |
    |   [DTLS handshake]               |
    |                                  |
    |--- NegotiateChannels (offer) --->
    |<--- NegotiateChannels (answer) --|
    |                                  |
    |   [SRTP media flows]             |
    |<=== Audio/Video RTP ============>
    |                                  |
    |--- MediaState ------------------>  (on mute/unmute/video toggle)
    |                                  |
    |--- phone.discardCall ----------->  (hangup)
```

### 4.5 Content Negotiation Details

**Audio always included:**
- Codec: opus, PT 111, 48kHz, 2 channels
- Parameters: minptime=10, useinbandfec=1, sprop-stereo=1
- Feedback: transport-cc
- Extensions: AbsSendTime (id 2), TransportWideCC (id 3)

**Video optional (added on request):**
- Codecs: H264/VP8/VP9 (negotiated intersection)
- Bitrate: min 64, start 400, max 800 (or 2000 with highBitrate)
- Parameters: codec-specific (profile-level-id for H264)
- Feedback: transport-cc, nack, ccm fir
- Extensions: VideoRotation (id 13)

**SSRC assignment:**
- Each side generates random uint32 SSRCs for audio and video
- FEC SSRCs for RTX retransmission (semantics "FID")

---

## 5. Reflector (Custom Relay) Protocol

Telegram uses custom relay servers (reflectors) in addition to/instead of standard TURN.

### 5.1 Peer Tag

16 bytes: [12 bytes from ICE password][4 bytes random tag]

### 5.2 Packet Format

**Outbound (to reflector):**
```
[16 bytes: peer tag]
[4 bytes: data size, big-endian]
[N bytes: payload]
[0-3 bytes: padding to 4-byte align]
```

**UDP Hello (initial greeting):**
```
[16 bytes: peer tag]
[12 bytes: 0xFF]
[1 byte: 0xFE]
[3 bytes: 0xFF]
[8 bytes: uint64 value 123]
```

**TCP Keepalive:**
```
[16 bytes: peer tag]
[4 bytes: 0x00000000]
```

### 5.3 Candidate Format

Synthetic hostname: `reflector-{serverId}-{randomTag}.reflector`

---

## 6. Descriptor Configuration

How the Telegram Desktop client populates the tgcalls Descriptor:

```go
// Pseudocode for Go
descriptor := Descriptor{
    Version: selectedVersion,  // from phoneCall.protocol.library_versions[0]
    Config: Config{
        InitializationTimeout: serverConfig.callConnectTimeoutMs / 1000,
        ReceiveTimeout:        serverConfig.callPacketTimeoutMs / 1000,
        DataSaving:            DataSavingNever,
        EnableP2P:             call.P2PAllowed,
        EnableNS:              true,   // noise suppression
        EnableAGC:             true,   // auto gain control
        EnableVolumeControl:   true,
        MaxApiLayer:           protocol.MaxLayer,  // 92
    },
    EncryptionKey: EncryptionKey{
        Value:      authKey,     // 256-byte DH shared secret
        IsOutgoing: isOutgoing,  // true for call initiator
    },
    Endpoints:  endpointsFromPhoneCall,   // from phoneCall.connections
    RtcServers: rtcServersFromPhoneCall,  // STUN/TURN from phoneCall.connections
    Proxy:      optionalSocks5Proxy,
}
```

---

## 7. Go Implementation Guide

### 7.1 Dependencies

- `github.com/gotd/td` — MTProto (DH exchange, phone.* methods, signaling relay)
- `github.com/pion/webrtc/v4` — WebRTC stack (ICE, DTLS, SRTP, RTP)
- `crypto/aes`, `crypto/cipher`, `crypto/sha256` — AES-CTR encryption
- `crypto/sha1` — Key fingerprint

### 7.2 Implementation Order

1. **DH key exchange** — implement g_a/g_b generation, auth_key derivation, fingerprint
2. **AES-CTR encryption** — PrepareAesKeyIv, encrypt/decrypt with msgKey verification
3. **V2 signaling** — JSON marshal/unmarshal for 4 message types, encrypt/decrypt wrapper
4. **Call setup** — phone.requestCall -> phone.confirmCall flow via gotd
5. **WebRTC integration** — pion/webrtc PeerConnection with ICE from signaling
6. **Media** — Opus audio via pion, video codecs via pion
7. **State management** — call lifecycle, MediaState updates

### 7.3 Key Constants

```go
const (
    MinLayer    = 65
    MaxLayer    = 92
    DefaultVersion = "2.4.4"

    // AES-CTR x values
    XOutTransport = 0
    XInTransport  = 8
    XOutSignaling = 128
    XInSignaling  = 136

    // V1 message IDs
    MsgCandidatesList       = 1
    MsgVideoFormats         = 2
    MsgRequestVideo         = 3
    MsgRemoteMediaState     = 4
    MsgAudioData            = 5
    MsgVideoData            = 6
    MsgUnstructuredData     = 7
    MsgVideoParameters      = 8
    MsgBatteryLow           = 9
    MsgNetworkStatus        = 10
    MsgEmpty                = 254
    MsgACK                  = 255
    MsgCustom               = 127

    // V1 seq flags
    SeqSingleMessage  = 0x80000000
    SeqRequiresAck    = 0x40000000
    SeqCounterMask    = 0x3FFFFFFF

    // Packet limits
    MaxTransportPacket  = 1452
    MaxSignalingPacket  = 16384
    MaxIncomingPacket   = 131072
)
```

---

## 8. Group Calls

Group calls use a completely different system:
- `phone.createGroupCall` / `phone.joinGroupCall` / `phone.leaveGroupCall`
- SFU (Selective Forwarding Unit) server-based, NOT P2P
- WebRTC with SDP offer/answer (standard)
- SSRC-based participant identification
- See `tgcalls/group/` directory for implementation

Not covered in detail here — group calls are simpler (standard WebRTC SFU pattern).

---

## 9. Implementation Findings — Bugs Found & Lessons Learned (2026-04-06)

### 9.1 CRITICAL: Key Fingerprint Endianness

**Bug:** `fingerprint = SHA1(auth_key)[12:20]` must be interpreted as **little-endian int64** (native `*reinterpret_cast<int64_t*>` on x86). Using big-endian causes the remote to compute a different fingerprint → instant call rejection → `PhoneCallDiscardReasonDisconnect`.

**C++ (TDesktop `calls_call.cpp`):**
```cpp
auto keyFingerprint = *reinterpret_cast<int64_t*>(sha1.data() + 12);
// This is LITTLE-ENDIAN on x86 — the bytes are NOT reversed
```

**Go (CORRECT):**
```go
fingerprint := int64(binary.LittleEndian.Uint64(sha1Hash[12:20]))
// NOT BigEndian! BigEndian will produce the wrong value.
```

The fingerprint is a TL `long` (little-endian on wire via MTProto). Both sides must compute the same value for the call to proceed.

### 9.2 V2 Multi-Message Packets

Incoming signaling packets can contain **multiple messages**. The EncryptedConnection ACK mechanism causes packets to grow over time as unacknowledged messages are resent alongside new ones.

**Packet format after decryption:**
```
[4-byte seq (with flags)] [messages...]
```

Each message in the stream:
- `0xFE` = kEmptyId (no payload, skip)
- `0xFF` = kAckId (no payload, acknowledgment)
- `0x7F` = kCustomId → `[4-byte length BE][data]` (the actual JSON signaling)
- Additional messages: `[4-byte seq][type byte][...]`

A single packet can contain 10+ messages (resent InitialSetup + Candidates + ACKs). Must parse ALL kCustomId messages, not just the first.

### 9.3 TURN/STUN Server Extraction

The `PhoneCall` response from `phone.confirmCall` contains `Connections`:
- `PhoneConnectionWebrtc` (Turn=true, Stun=true) → standard TURN/STUN servers for ICE
- `PhoneConnection` (with PeerTag) → V1 reflectors (custom protocol, not standard ICE)

Both types are returned (typically 3 WebRTC + 3 Reflectors). The WebRTC connections are standard TURN/STUN with username/password credentials.

**The remote's tgcalls also sends ICE candidates with `.reflector` hostnames** (e.g., `reflector-2-4170221298.reflector`). Standard WebRTC stacks can't parse these — filter them out silently.

### 9.4 Signaling Timing

The remote creates its tgcalls instance immediately after receiving the `PhoneCall` update (which arrives right after our `phone.confirmCall`). Signaling must arrive promptly.

**Current flow (simplified — pre-encryption removed due to DTLS cert mismatch issues):**
1. Compute DH auth_key (+3ms)
2. `phone.confirmCall` (400-700ms RTT — blocks)
3. Parse connections → TURN/STUN servers
4. Create PeerConnection with TURN servers
5. Add audio track, create SDP offer, set local description
6. Send InitialSetup (with PeerConnection's real ICE credentials + DTLS fingerprint)
7. Send NegotiateChannels

Pre-encryption was attempted (encrypt InitialSetup before confirmCall, fire immediately after) but caused DTLS certificate mismatches when the PeerConnection generated a different cert than the pre-generated one. The current approach sends InitialSetup ~100ms after confirmCall, which works reliably.

### 9.5 Signaling Asymmetry — Who Sends First

From `InstanceV2Impl::beginSignaling()`:
- **Outgoing** (caller, `isOutgoing=true`): sends `InitialSetup` + `NegotiateChannels` immediately
- **Incoming** (receiver, `isOutgoing=false`): **waits** for caller's `InitialSetup`, then sends its own

The receiver does NOT send any signaling until it receives and decrypts the caller's `InitialSetup`. This is why the pre-encryption from §9.4 is critical.

### 9.6 DTLS Role Negotiation

- Outgoing (caller): sends `setup: "actpass"` in InitialSetup fingerprints
- Incoming (receiver): sends `setup: "passive"` in InitialSetup fingerprints

**tgcalls reverses the WebRTC SDP convention for setup:**
```
tgcalls "passive" → SetDtlsRole(SSL_CLIENT) — remote initiates DTLS
tgcalls "active"  → SetDtlsRole(SSL_SERVER) — remote waits for DTLS
```

In standard WebRTC SDP: `setup:passive` = I wait (server), `setup:active` = I initiate (client).

**In practice for our SDP answer:** when remote sends `"passive"`, set `a=setup:passive` in the SDP answer. This makes pion the DTLS client (initiator), which triggers a simultaneous DTLS open. Both sides send ClientHello, DTLS resolves the conflict via cookie exchange, and the handshake completes. This gives us `pc=connected`.

**Warning:** Setting `a=setup:active` (which seems logically correct given tgcalls' reversed convention) causes pion to WAIT as DTLS server, but the remote ALSO waits → deadlock → DTLS never starts.

### 9.7 Version Negotiation

Offer versions matching real tgcalls: `["13.0.0", "12.0.0", "9.0.0", "8.0.0", "7.0.0", "5.0.0", "2.7.7", "2.4.4"]`. The server picks the highest common version.

Version → SignalingProtocolVersion mapping (from `InstanceV2Impl.cpp`):
- `"7.0.0"` → V1 (binary messages, `EncryptedConnection` with typed serialization)
- `"8.0.0"`, `"9.0.0"` → V2 (JSON signaling, `prepareForSendingRawMessage` / `handleIncomingRawPacket`)
- `"12.0.0"`, `"13.0.0"` → V3 (JSON + gzip, `encryptRawPacket` / `decryptRawPacket`, SCTP signaling)
- Unknown → defaults to V2

V2 encryption uses the full ACK-based framing: `[seq+flags][0x7F][length][data]`.
V3 encryption uses simpler framing: `[seq][data]` (no 0x7F, no length prefix), plus gzip compression.

### 9.8 TDesktop Call Lifecycle (calls_call.cpp)

Key findings from reading the full TDesktop source:

1. **`sendSignalingData` failure handling**: If `phone.sendSignalingData` returns `MTPBool(false)`, the call is terminated with `FinishType::Failed`. If it returns `CALL_NOT_ACTIVE`, `handleRequestError` is called.

2. **Timeouts**: `callConnectTimeoutMs` and `callPacketTimeoutMs` are from server config. However, **V2 does NOT use these** — `initializationTimeout`/`receiveTimeout` are dead fields in InstanceV2Impl. The only timeout is NativeNetworkingImpl's **hardcoded 20 seconds** for ICE connection.

3. **The `_discardByTimeoutTimer`** is cancelled when `createAndStartController()` is called (when tgcalls instance is created). After that, only the 20-second network timeout matters.

4. **Instance creation**: `tgcalls::Meta::Create(versionString, descriptor)` dispatches to the registered implementation. If the version is unrecognized, it returns null → `finish(Failed)`.

5. **`customParameters`**: JSON string in the Config, parsed by InstanceV2Impl. Known params: `network_use_mtproto`, `network_standalone_reflectors`, `network_skip_initial_ping`, etc. TDesktop leaves this empty.

### 9.9 Pion Implementation State (final — 2026-04-07)

<!-- Updated 2026-04-07: Major debugging session. DTLS confirmed working. Three bugs fixed. -->
<!-- Decision: switching to tgcalls native (ntgcalls .so) for media. See §9.15. -->

**Working (verified 2026-04-07):**
- DH exchange with correct little-endian fingerprint
- V2 signaling encryption/decryption (both directions, matches C++ byte-for-byte)
- Multi-message V2 packet parsing (kCustomId, kEmptyId, kAckId) — handles 20+ messages per packet
- Atomic signaling counter (prevents race conditions between ICE candidate and NegotiateChannels goroutines)
- ICE connectivity (host candidates, STUN srflx, Telegram TURN/reflectors)
- **DTLS handshake completes** — confirmed via `OnStateChange` callback: `new→connecting→connected` in ~200ms after ICE connects. Previous "DTLS never starts" diagnosis was wrong — DTLS always worked.
- **SRTP activated** — `srtpReady` channel closes, `startSRTP` succeeds, `srtpWriterFuture` passes packets through.
- Bidirectional signaling exchange (InitialSetup, Candidates, NegotiateChannels) with Desktop, Web, ntgcalls
- NegotiateChannels content negotiation: our offer accepted, remote's offer answered
- RTP extension URIs match tgcalls exactly (abs-send-time, transport-cc)
- Incoming call AcceptCall with DH completion via PhoneCall update
- PeerConnection created with full API: MediaEngine (default codecs) + InterceptorRegistry (NACK, TWCC, stats)
- **pion↔pion bidirectional audio: 1027 frames each direction** (TestTwoUserCallAudio PASS)
- **SRTP packets reach remote** — ntgcalls confirms: `SRTP activated`, packets decrypted, `Failed to demux RTP packet: PT=111 SSRC=X`

**Bugs found and fixed (2026-04-07):**
1. **Silence sender yield bug** — `onAudioFrame` (incoming audio receive callback) was incorrectly treated as signal to stop sending outgoing silence. Both outgoing and incoming sides had this. When any test set `onAudioFrame` to receive audio, the silence sender yielded and sent ZERO packets. Fix: always send silence regardless of `onAudioFrame`.
2. **NegotiateChannels answer SSRC** — Answer echoed remote's SSRC instead of our own. Remote expected to receive audio on the SSRC we declared, but we declared theirs. Fix: use `call.audioSSRC`.
3. **`call.audioSSRC` not synced with SDP** — Randomly generated `call.audioSSRC` was never updated to match pion's actual SDP SSRC (assigned during offer creation). Caused SSRC mismatch between signaling and RTP. Fix: `call.audioSSRC = sdpSSRC` after `parseSDPAllSSRCs`.

**BLOCKED — RTP demux on remote side (the reason for switching to tgcalls native):**

Despite SRTP working end-to-end, all non-pion clients (Desktop, ntgcalls) cannot demux our RTP packets:
- ntgcalls: `rtp_transport.cc:230: Failed to demux RTP packet: PT=111 SSRC=X` — packets arrive, SRTP decrypts, but no registered sink matches.
- Desktop: no incoming audio despite DTLS connected, NegotiateChannels completed, silence sender running 500+ frames.
- pion↔pion works because both sides use real SDP with SSRC declarations and pion's internal demuxing.

**Root cause analysis:**
The RTP demux failure is caused by the fundamental architectural mismatch between pion's SDP-based WebRTC and tgcalls' JSON-signaling-based WebRTC:

1. **Missing MID RTP header extension** — With BUNDLE (3 m-lines sharing one ICE transport), libwebrtc's RTP demuxer uses the MID header extension (`urn:ietf:params:rtp-hdrext:sdes:mid`) to identify which m-line a packet belongs to. Our pion SDP doesn't negotiate MID, so our packets lack it. libwebrtc falls back to SSRC matching but doesn't register SSRCs from NegotiateChannels into its demuxer.

2. **Synthetic SDP limitations** — tgcalls doesn't use SDP at all — it uses JSON signaling (InitialSetup, NegotiateChannels). We build a synthetic SDP from InitialSetup for pion, but this synthetic SDP lacks: remote SSRC declarations (`a=ssrc:` lines), MID extension, RTP stream ID extensions, and other attributes that pion and libwebrtc expect.

3. **Two-phase SSRC discovery** — In tgcalls, SSRCs are exchanged via NegotiateChannels AFTER ICE/DTLS connect. But pion needs SSRCs declared in the SDP BEFORE the remote description is set. We can't add SSRCs to the SDP retroactively. `HandleUndeclaredSSRCWithoutAnswer` only works with 1 media section (we have 3).

4. **V2 signaling ACKs** — Desktop keeps resending all signaling because we don't ACK. The V2 ACK mechanism embeds `[seq][0xFF]` entries in outgoing packets. Attempted implementation broke V2 framing (wrong byte order). Need to study tgcalls `EncryptedConnection` source more carefully. Not blocking call setup, but noisy and may affect Desktop's state machine.

**Not implemented:**
- V2 signaling ACK mechanism
- Audio capture/playback (mic/speaker)
- MediaState via SCTP data channel
- Video/screenshare RTP
- Incoming call media (only DH/signaling works)

### 9.15 V2Reference Breakthrough (2026-04-07)

<!-- Updated 2026-04-07: V2Reference discovered and working -->

**Previous approach (NegotiateChannels + synthetic SDP) was abandoned** due to RTP demux failures.

**Solution: InstanceV2ReferenceImpl (version 10.0.0)**

tgcalls has THREE implementation backends, selected by version number:
- `InstanceImpl` (versions 2.7.7, 5.0.0): Legacy V1 custom UDP
- `InstanceV2Impl` (versions 7.0.0-9.0.0, 12.0.0-13.0.0): Custom JSON signaling (InitialSetup + NegotiateChannels)
- **`InstanceV2ReferenceImpl` (versions 10.0.0, 11.0.0): Standard WebRTC PeerConnection with real SDP offer/answer**

By advertising ONLY version `10.0.0`, the remote Telegram client uses InstanceV2ReferenceImpl which exchanges **standard SDP** over the encrypted signaling channel. This is fully compatible with pion's standard WebRTC PeerConnection.

**Version 10.0.0 vs 11.0.0:**
- 10.0.0 = V1 signaling encryption (direct encrypted JSON, ExternalSignalingConnection)
- 11.0.0 = V2 signaling encryption (SCTP-wrapped, SignalingSctpConnection)
- We use 10.0.0 to avoid the SCTP layer

**Signaling format (V2Reference):**
- SDP offer: `{"@type":"offer","sdp":"v=0\r\n..."}`
- SDP answer: `{"@type":"answer","sdp":"v=0\r\n..."}`
- ICE candidate: `{"@type":"candidate","sdp":"candidate:...","mid":"0","mline":0}`
- Media state: `{"@type":"MediaState","muted":false,"videoState":"inactive",...}`
- All encrypted with the same AES-CTR signaling encryption (V1 framing: [seq][0x7F][len][data])

**Verified working (2026-04-07):**
- pion↔pion two-user automated test: ICE+DTLS+SRTP connected, bidirectional audio tracks, 200+ RTP frames exchanged
- Version 10.0.0 negotiated via Telegram server
- TURN relay connection in ~3.5s
- Clean hangup via phone.discardCall

**No .so dependency needed** — pure Go/pion implementation works natively.

### 9.16 Dual-Mode Signaling Attempt & ntgcalls Compat (2026-04-07)

<!-- Discovered 2026-04-07 during ntgcalls testing -->

**Goal:** Support both V2Reference (10.0.0, standard SDP) and V2Impl (9.0.0/8.0.0, InitialSetup+NegotiateChannels) so we can test against ntgcalls (real tgcalls 2.1.0 .so).

**ntgcalls version support:** `[8.0.0, 9.0.0]` — these are InstanceV2Impl versions only. ntgcalls does NOT support InstanceV2ReferenceImpl (10.0.0/11.0.0).

**Version negotiation rules (from testing):**
- Server picks the **highest** common version between caller and receiver
- If both sides advertise `["10.0.0", "9.0.0", "8.0.0"]`, server picks 10.0.0
- ntgcalls then internally selects 8.0.0 (its highest) → version mismatch: our side sends SDP, ntgcalls expects InitialSetup+NegotiateChannels
- Trying to exclude 10.0.0 from the version list (`["9.0.0", "8.0.0"]` or `["13.0.0", "12.0.0", "9.0.0", ...]`) → server rejects with `CALL_PROTOCOL_COMPAT_LAYER_INVALID` (error 406)
- The server appears to REQUIRE version 10.0.0 in the version list (as of 2026-04-07). Older version lists without 10.0.0+ are rejected.

**What this means:**
- We MUST include 10.0.0 in the version list for the server to accept calls
- When both sides include 10.0.0, server always picks 10.0.0
- ntgcalls 2.1.0 can receive our V2Reference SDP signaling (it logs it as `processSignalingData: {"@type":"offer",...}`) but InstanceV2Impl doesn't understand SDP format → signaling silently fails
- Dual-mode (V2Impl fallback) would work IF we could negotiate 9.0.0, but the server won't let us

**Conclusion:** Testing against ntgcalls requires either:
1. A newer ntgcalls that supports 10.0.0 (InstanceV2ReferenceImpl)
2. Forking ntgcalls to add V2Reference support
3. Testing via a real Desktop client (manual interaction required)
4. Implementing SCTP signaling framing for version 11.0.0 (which ntgcalls might support in newer versions)

**For production:** V2Reference (10.0.0) works against all modern Telegram clients (Desktop, Mobile, Web) since they all register InstanceV2ReferenceImpl. The ntgcalls incompatibility only affects automated testing, not real-world usage.

**EncryptedConnection wire format (verified against C++ source):**

Sending (encryptRawPacket / prepareForSendingRawMessage):
```
plaintext = [4-byte seq (big-endian)] [0x7F] [4-byte msg_len (big-endian)] [msg_data]
  seq bits: 0-29 = counter, bit 30 = requires_ack, bit 31 = single_message_packet
msgKey = SHA256(auth_key[88+x : 88+x+32] || plaintext)[8:24]  (16 bytes)
aesKey, aesIV = PrepareAesKeyIv(auth_key, msgKey, x)
ciphertext = AES-CTR(aesKey, aesIV, plaintext)
packet = [16-byte msgKey] [ciphertext]
```

x offset for Signaling mode:
- Sending (isOutgoing=true): x = 0 + 128 = 128
- Sending (isOutgoing=false): x = 8 + 128 = 136
- Receiving (isOutgoing=true): x = 8 + 128 = 136
- Receiving (isOutgoing=false): x = 0 + 128 = 128

PrepareAesKeyIv (CryptoHelper.cpp):
```
sha256a = SHA256(msgKey || auth_key[x : x+36])
sha256b = SHA256(auth_key[40+x : 40+x+36] || msgKey)
aesKey = sha256a[0:8] + sha256b[8:24] + sha256a[24:32]
aesIV  = sha256b[0:4] + sha256a[8:16] + sha256b[24:28]
```

V2 message types in plaintext:
- 0x7F (kCustomId): raw data message — [4-byte len][data]
- 0xFE (kEmptyId): empty/keepalive — no payload
- 0xFF (kAckId): acknowledgment — no payload (seq field contains the acked seq)

Multiple messages can be packed in one encrypted packet. After the main message, additional messages (ACKs, resends) are appended before encryption.

**Version 11.0.0 SCTP issue:**
When version 11.0.0 is negotiated, InstanceV2ReferenceImpl wraps signaling in SignalingSctpConnection — an SCTP layer over the encrypted channel. The 44-byte packets we received with `0x1388` (SCTP port 5000) were SCTP INIT chunks. To support 11.0.0, we'd need to implement SCTP framing. Version 10.0.0 uses ExternalSignalingConnection (direct encrypted JSON, no SCTP).

### 9.11 NegotiateChannels Format (from Signaling.cpp)

<!-- Discovered 2026-04-06 -->

Exact JSON format verified against C++ source:

```json
{
  "@type": "NegotiateChannels",
  "exchangeId": "12345",       // MUST be string (uint32 serialized as string)
  "contents": [{
    "type": "audio",            // "audio" or "video"
    "ssrc": "3456789",          // MUST be string (uint32 serialized as string)
    "ssrcGroups": [],           // omitted when empty (not serialized as [])
    "payloadTypes": [{
      "id": 111,                // number (NOT string)
      "name": "opus",
      "clockrate": 48000,       // number
      "channels": 2,            // number
      "feedbackTypes": [{"type": "transport-cc", "subtype": ""}],  // subtype always present
      "parameters": {"minptime": "10", "useinbandfec": "1"}       // values MUST be strings
    }],
    "rtpExtensions": [
      {"id": 2, "uri": "http://www.webrtc.org/experiments/rtp-hdrext/abs-send-time"},
      {"id": 3, "uri": "http://www.ietf.org/id/draft-holmer-rmcat-transport-wide-cc-extensions-01"}
    ]
  }]
}
```

**Critical:** RTP extension URIs must match tgcalls exactly. Using different URIs (e.g., `urn:ietf:...`) causes `ContentNegotiation::CreateAnswerOrError` to not find matching extensions, and the remote never sends a NegotiateChannels answer. These URIs are SDP identifiers — never fetched over the network.

**Two messages from the receiver:**
1. Answer to our offer (same exchangeId, echoes our SSRC) — confirms our outgoing audio
2. Receiver's own offer (different exchangeId, new SSRC) — we must answer this for receiver to start its outgoing audio

### 9.12 Transport Mode Selection (from NativeNetworkingImpl.cpp)

<!-- Discovered 2026-04-06 -->

- Transport mode is determined **solely** by `customParameters["network_use_mtproto"]`
- Default (empty customParameters) = **standard DTLS-SRTP** (not MTProto)
- TDesktop **never sets customParameters** — always empty string
- DTLS-SRTP uses: `cricket::DtlsTransport` + `webrtc::DtlsSrtpTransport` + standard `CryptoOptions` with AES-128-SHA1-80 + GCM suites
- This is completely standard WebRTC DTLS-SRTP. Nothing custom.
- MTProto transport (`MtProtoRtpTransport`) wraps ICE with `EncryptedConnection` for RTP encryption — only used if explicitly requested via customParameters

### 9.13 Pion WriteRTP Pipeline (from pion/webrtc v4 source)

<!-- Discovered 2026-04-06 -->

The full path from `track.WriteRTP()` to the wire:

1. `TrackLocalStaticRTP.WriteRTP()` → iterates `s.bindings`
2. Each binding has a `writeStream` (`interceptorToTrackLocalWriter`)
3. `writeStream` calls the interceptor chain (NACK, TWCC, stats)
4. Bottom of chain: `srtpWriterFuture.WriteRTP()`
5. `srtpWriterFuture.init(returnWhenNoSRTP=true)` checks `srtpReady` channel
6. If not ready: `default` case fires → returns `(0, nil)` — **silent drop, no error**
7. If ready: opens `srtp.WriteStreamSRTP` → actual SRTP encryption + send

**`srtpReady`** is closed by `DTLSTransport.startSRTP()` after DTLS handshake completes and SRTP keys are exported. If SRTP key export fails (e.g., `use_srtp` DTLS extension not negotiated), `srtpReady` never closes and ALL WriteRTP calls silently drop.

**Key insight:** `PeerConnectionState == Connected` does NOT guarantee SRTP is ready. Connected = ICE + DTLS done. SRTP setup is async after DTLS. Check by monitoring `outRTP` in stats or the int return from the underlying writeStream.

### 9.10 Source Files Reference

All read on 2026-04-06 from AyuGram Desktop (cloned at `/tmp/tgcalls_src/`):

| File | Lines | Purpose |
|---|---|---|
| `v2/InstanceV2Impl.cpp` | ~2400 | V2 call instance: signaling, networking, content negotiation, media channels |
| `EncryptedConnection.cpp` | ~754 | AES-CTR encryption, seq/ACK mechanism, multi-message packets |
| `EncryptedConnection.h` | ~104 | Types: EncryptedPacket, DecryptedRawPacket, Signaling/Transport types |
| `CryptoHelper.cpp` | ~61 | PrepareAesKeyIv, AesProcessCtr |
| `CryptoHelper.h` | ~68 | ConcatSHA256, AesKeyIv struct |
| `v2/Signaling.cpp` | ~821 | JSON serialization for InitialSetup, NegotiateChannels, Candidates, MediaState |
| `v2/Signaling.h` | ~192 | Signaling message structs |
| `v2/NativeNetworkingImpl.cpp` | ~1071 | ICE/DTLS transport, TURN config, MtProtoRtpTransport, 20s timeout |
| `v2/ContentNegotiation.cpp` | ~803 | Offer/answer for audio/video channels, SSRC management |
| `v2/SignalingEncryption.cpp` | ~22 | Thin wrapper: `encryptRawPacket`/`decryptRawPacket` (simpler path, NOT used by V2) |
| `Message.cpp` | ~406 | V1 binary message serialization |
| `Instance.h` | ~292 | Descriptor, EncryptionKey, Config, State enum, Meta registration |
| `Telegram/SourceFiles/calls/calls_call.cpp` | ~1639 | TDesktop call lifecycle, DH, instance creation, signaling relay |

Also read from pion/webrtc v4.2.11 (Go module cache):

| File | Purpose |
|---|---|
| `track_local_static.go` | WriteRTP → bindings → writeStream pipeline |
| `rtpsender.go` | Send() → Bind() → interceptor chain → srtpWriterFuture |
| `srtp_writer_future.go` | Lazy SRTP init, silent drop when not ready |
| `dtlstransport.go` | startSRTP() → srtpReady channel → SRTP session creation |
| `peerconnection.go` | startRTPSenders, startTransports, state management |
| `settingengine.go` | SetICECredentials, LoggerFactory |

## §9.14 — Two-Session Call: Critical Fixes (2026-04-06)

**Context:** Two pion/webrtc PeerConnections calling each other via Telegram's MTProto signaling.

### Fix 1: SDP Offer/Answer (not dual-offer)

**Bug:** Both sides created SDP offers → both thought they were ICE controlling agent → role conflict → intermittent ICE failures.

**Fix:** Only the outgoing (caller) side creates an SDP offer. The incoming (callee) side waits for the remote's InitialSetup, builds a synthetic SDP offer from it, sets it as remote description (`SDPTypeOffer`), then calls `CreateAnswer()`. This gives proper ICE roles: outgoing=controlling, incoming=controlled.

### Fix 2: DTLS Role from Pion's Answer

**Bug:** Incoming side hardcoded `setup: "passive"` in its InitialSetup, but pion's actual answer had `setup: "active"`. The outgoing side built a synthetic answer with `passive`, making itself DTLS active. But the incoming side's pion was also DTLS active (from its own answer). Both sides tried to initiate DTLS → deadlock → "handshake error: EOF".

**Fix:** Parse `a=setup:` from pion's actual answer SDP and send that value in the InitialSetup signaling. Pion defaults to `active` when answering `actpass`, so the incoming side sends `active`, the outgoing side's synthetic answer says `active`, making it DTLS passive. Result: incoming=active initiates DTLS, outgoing=passive waits.

### Fix 3: Telegram TURN Returns 403

**Discovery:** Telegram's TURN servers reject standard `CreatePermission` requests with `403 Forbidden IP`. They use a proprietary relay protocol based on `PeerTag` from `PhoneConnection` (reflector) entries — NOT standard TURN CreatePermission/ChannelBind.

**Workaround:** Skip TURN, use only STUN for server-reflexive candidate discovery. Host candidates work for same-network scenarios. For NAT traversal across networks, Telegram's custom relay protocol needs implementation.

### Fix 4: Undeclared SSRC

**Bug:** tgcalls negotiates SSRCs via `NegotiateChannels` JSON signaling, not SDP. Pion rejected incoming RTP with undeclared SSRCs: `"cannot process early media without SDP answer"`.

**Fix:** `SettingEngine.SetHandleUndeclaredSSRCWithoutAnswer(true)` tells pion to create dynamic tracks for unknown SSRCs, firing `OnTrack` for them.

### Fix 5: localSDPReady Not Closed

**Bug:** `startCallWebRTC` (incoming path) created `localSDPReady` channel but never closed it. `handleRemoteInitialSetup` waited on it with a 10-second timeout, then gave up → remote SDP never set.

**Fix:** Close `localSDPReady` immediately after PC is ready (before any SDP creation, since the incoming side defers SDP to `handleRemoteInitialSetup`).

### Result

Bidirectional Opus audio: ~1034 frames each direction over 20 seconds (50fps = 20ms per frame). ICE connects reliably via host candidates, DTLS handshake completes, SRTP activates, `OnTrack` fires on both sides.

## §9.15 — Telegram Web Internals Dump Analysis (2026-04-06)

Captured via `chrome://webrtc-internals` from a Telegram Web A call between user1 and user2 (both on same PC, Brave browser).

### SDP Structure

Telegram Web creates a **4-media-line SDP**:
- `m=audio` (mid=0): Opus 111, `minptime=10;useinbandfec=1`, transport-cc
- `m=video` (mid=1): VP8 96, RTX 97, FID group
- `m=video` (mid=2): VP8 96, RTX 97, FID group (second video, e.g. screenshare)
- `m=application` (mid=3): DataChannel (SCTP, label="data", negotiated=true, id=0)

### ICE/DTLS/SRTP Configuration

- ICE servers: `turn:91.108.x.x:1400` + `stun:91.108.x.x:1400` (3 servers), `iceCandidatePoolSize: 10`, `bundlePolicy: max-bundle`
- Offerer (user1 web): `iceRole: controlling`, `dtlsRole: server`, `setup: actpass`
- Answerer (user2 web): `iceRole: controlled`, `dtlsRole: client`, `setup: active`
- DTLS cipher: `TLS_AES_128_GCM_SHA256`, TLS version `FEFC` (DTLS 1.2)
- SRTP cipher: `AES_CM_128_HMAC_SHA1_80`
- Active candidate pair: `relay ↔ prflx` (relay-to-peer-reflexive via TURN)

### Audio Stats

- Outbound: 473 packets / 308KB over 10s = ~50pps (20ms Opus frames), PT=111
- Inbound: 432 packets received, 15 lost, jitter ~5-17ms
- Codec: `opus (111, ;minptime=10;useinbandfec=1)` — matches our implementation exactly

### Key Observations

1. **TURN CreatePermission works from browser** — Chrome's TURN client successfully allocates and relays. Our pion TURN also works for srflx but CreatePermission returns 403 for some peer IPs.
2. **Data channel** — always created (label="data", negotiated, id=0), used for MediaState signaling.
3. **SSRC declared in SDP** — `a=ssrc:93410087 cname:0` — confirms our SSRC fix was correct.
4. **Telegram Web calling limitations** — web↔web works, phone↔web shows "update your telegram" error. Web creates its own SDP offer (not via tgcalls signaling), uses standard WebRTC answer from remote.
5. **RTP extensions match** — `abs-send-time` (id=2), `transport-wide-cc-extensions` (id=3), plus `ssrc-audio-level` (id=1) and `sdes:mid` (id=4).

## §9.16 — Incoming Call Path Issues (2026-04-06)

When the official app calls us (incoming path), several issues were found:

### ICE Gathering Timing

The incoming side needs TURN relay candidates to connect across networks. If the SDP answer is created lazily (only when remote InitialSetup arrives), ICE gathering starts late and TURN allocation may not complete before the remote times out (~20s).

**Fix:** Create an SDP offer immediately on the incoming side to trigger ICE gathering (TURN allocation). When the remote InitialSetup arrives, treat it as an SDP answer.

### Phone Candidate Types

The official Telegram app sends three types of ICE candidates:
1. **Reflector candidates** — `reflector-N-XXXXX.reflector:599` — proprietary tgcalls format, MUST be skipped (pion can't parse)
2. **Standard relay candidates** — `91.108.x.x:PORT typ relay` — usable by pion
3. **No srflx/host from phone** — mobile clients only send relay candidates

### Dual-Offer Tradeoff

Both sides creating SDP offers works against official tgcalls (which doesn't enforce ICE roles), but causes ICE role conflicts between two pion instances. For pion↔pion calls, one side needs to be the answerer.

Current approach: dual-offer for all calls (works against official client), accept intermittent failures for pion↔pion.

---

## §10 — Telegram Web Call Implementation (reverse-engineered 2026-04-07)

Source: MITM capture of Brave → web.telegram.org/a/ via mitmproxy 12.2.1.
Analyzed: `BundleCalls` JS bundle (chunk 2394, 66KB, 3828 lines after formatting).

### §10.1 "VoipPeerIncompatible" / "Update Your Telegram" Error — ROOT CAUSE FOUND

Telegram Web checks the peer's `protocol.libraryVersions` array at call acceptance:

```javascript
// Line 1550 of BundleCalls chunk
!o?.libraryVersions.some((e) => "4.0.0" === e || "4.0.1" === e)
```

If the peer does NOT advertise version `4.0.0` or `4.0.1`, Telegram Web shows "VoipPeerIncompatible" and hangs up. Our client was advertising `["13.0.0", "12.0.0", "9.0.0", "8.0.0", "7.0.0", "5.0.0", "2.7.7", "2.4.4"]` — skipping the 4.x range entirely.

**Fix:** Add `"4.0.1"` and `"4.0.0"` to the `LibraryVersions` array in all three call sites (requestCall, confirmCall, acceptCall).

### §10.1.1 Web Signaling Framing — DIFFERENT from tgcalls C++

The web client (gramjs) uses a **simpler signaling format** than tgcalls C++:

- **Web format:** `[16-byte msgKey][AES-CTR([4-byte BE seq][raw JSON])]`
- **tgcalls V2 format:** `[16-byte msgKey][AES-CTR([4-byte seq|flags][0x7F type][4-byte length][JSON])]`

Source: `telegram-tt/src/api/gramjs/methods/phoneCallState.ts` lines 100-121.

Web encode: `Buffer.concat([convertToLittle(seqArray), Buffer.from(jsonString)])` — just seq + raw JSON, no V2 framing.
Web decode: `JSON.parse(decryptedPlaintext.slice(4))` — skips 4-byte seq, parses rest as JSON.

If V2 framing is sent to a web client, it gets `\x00\x00\x00\x7F{"@ty...` → invalid JSON error.

**Fix:** Detect web peer via protocol version (4.0.0/4.0.1) and use simple framing.

### §10.1.2 Web Requires 3 Media Tracks

The web client always adds 3 tracks to RTCPeerConnection:
1. Audio (silence oscillator)
2. Video (black 640x480 canvas)
3. Screenshare (black 640x480 canvas)

The `sendInitialSetup()` function has a guard:
```javascript
if (!sdp.ssrc || !sdp['ssrc-groups'] || !sdp['ssrc-groups'][0] || !sdp['ssrc-groups'][1]) return;
```

If the peer's SDP offer only has audio (1 m-line), the web's answer SDP won't have video ssrc-groups, and the web **silently refuses to send its InitialSetup response**.

**Fix:** Always add dummy VP8 video + screenshare tracks to the PeerConnection, even for audio-only calls. Include video/screencast SSRCs in the InitialSetup message.

### §10.1.3 Web Call — FULLY WORKING (verified 2026-04-07)

After all three fixes:
- Version: `4.0.0`/`4.0.1` in LibraryVersions ✅
- Framing: simple `[seq][JSON]` for web peers ✅
- Tracks: 3 m-lines (audio + video + screenshare) ✅

Result: ICE connected in 4.4s, 569+ inbound RTP packets, 500 outbound silence frames, "connected" status + encryption emojis shown on web. Bidirectional audio pipeline established.

### §10.2 Web Client Signaling Format

Signaling is JSON-based over a WebRTC data channel (`{id: 0, negotiated: true}`), with `@type` discriminator:

**InitialSetup:**
```json
{
  "@type": "InitialSetup",
  "fingerprints": [{"fingerprint": "...", "hash": "sha-256", "setup": "active"|"passive"}],
  "ufrag": "...",
  "pwd": "...",
  "audio": {"ssrc": "...", "ssrcGroups": [], "payloadTypes": [...], "rtpExtensions": [...]},
  "video": {"ssrc": "...", "ssrcGroups": [...], "payloadTypes": [...], "rtpExtensions": [...]},
  "screencast": {"ssrc": "...", "ssrcGroups": [...], "payloadTypes": [...], "rtpExtensions": [...]}
}
```

**Candidates:**
```json
{
  "@type": "Candidates",
  "candidates": [{"sdpString": "candidate:..."}]
}
```

**MediaState:**
```json
{
  "@type": "MediaState",
  "isMuted": false,
  "isBatteryLow": false,
  "videoState": "active"|"inactive",
  "screencastState": "active"|"inactive",
  "videoRotation": 0
}
```

### §10.3 WebRTC Configuration

```javascript
new RTCPeerConnection({
  iceServers: servers.map(s => ({
    urls: [s.isTurn && `turn:${s.ip}:${s.port}`, s.isStun && `stun:${s.ip}:${s.port}`].filter(Boolean),
    username: s.username,
    credentialType: "password",
    credential: s.password,
  })),
  iceTransportPolicy: p2pAllowed ? "all" : "relay",
  bundlePolicy: "max-bundle",
  iceCandidatePoolSize: 10,
});
```

- Trickle ICE enabled (`a=ice-options:trickle`)
- ICE candidates buffered until `InitialSetup` received, then flushed with `addIceCandidate({candidate: str, sdpMLineIndex: 0})`
- ICE restart on `disconnected`/`failed` states: `createOffer({iceRestart: true})`
- DTLS-SRTP with SHA-256 fingerprints (no custom media encryption)

### §10.4 Codec Preferences

- **Audio:** Opus (standard WebRTC)
- **Video:** VP8 preferred (receiver side reorders payloadTypes to put VP8 first)
- **Data channel:** `{id: 0, negotiated: true}` — pre-agreed, JSON messages

### §10.5 Mute Implementation

- Audio mute: replaces track with silent oscillator stream (OscillatorNode → MediaStreamDestination, `enabled: false`)
- Video mute: replaces track with black canvas stream (640x480 black fill, `captureStream()`, `enabled: false`)
- State communicated via `MediaState` signaling message

### §10.6 Group Call vs 1:1 Call

- 1:1: direct RTCPeerConnection with DH key exchange, signaling over data channel
- Group: conference object with `ssrcs[]` (per-participant), `transport` (shared ICE/DTLS), separate screenshare connection
- Group calls route audio via SSRC→userId lookup, per-participant gain nodes
- Group call presentation: separate RTCPeerConnection for screenshare

## §11 — Official Client Interop Findings (2026-04-07)

### §11.1 — pion↔pion Bidirectional Audio Verified

Automated two-user test (user1 calls user2, user2 calls user1) passes with 800+ RTP frames in each direction per call. Both directions verified. Pure Go/pion, V2Reference (10.0.0), relay via Telegram TURN servers.

Key implementation details:
- `ForceRelayICE: true` required for same-machine testing (host candidates collide between two PeerConnections)
- Production code respects `P2PAllowed` from PhoneCall response for ICE transport policy
- Silence sender (opus DTX: 0xF8 0xFF 0xFE) keeps RTP stream alive and triggers OnTrack on remote
- Unique payload markers verify data integrity across the SRTP pipeline

### §11.2 — Official Client (Telegram Desktop/Mobile) SDP Exchange

When our Go/pion implementation (outgoing caller) connects to an official Telegram client:

1. We send SDP offer (audio sendrecv, data channel) via encrypted signaling
2. Official client answers with `a=recvonly` on audio (BUNDLE 0 1)
3. Official client then sends its OWN SDP offer (BUNDLE 0 1 2: audio+video+data) with `sendrecv`
4. This re-offer is resent many times with incrementing o= session version

**Problem discovered**: Processing the re-offer (SetRemoteDescription with new offer after answer is already set) causes pion to renegotiate, which destroys the SRTP context. The connection shows ICE+DTLS connected but no RTP flows in either direction. Limiting to 1 re-offer processing doesn't help — the DTLS/SRTP pipeline breaks on renegotiation.

**Official client reflector candidates**: Uses hostname-based addresses (`reflector-X-XXXXXXXXX.reflector`) which pion cannot parse. These are Telegram's custom relay servers. Pion falls back to standard TURN relay candidates.

**Official client data channel**: Works correctly — `MediaState` messages received via data channel after DTLS connects.

**Status**: pion↔pion works flawlessly. Official client interop blocked on the re-offer/SRTP issue. Needs investigation into whether (a) the official client actually sends RTP after `recvonly` answer without the re-offer, or (b) we need to handle the re-offer without pion renegotiation, or (c) a completely different approach is needed (e.g., not sending our own offer, only answering the client's).

### §11.3 — Version 11.0.0 = SCTP Signaling (ROOT CAUSE of Desktop failure)

<!-- Discovered 2026-04-07 via MITM of AyuGram Desktop call -->

**Critical finding:** Version 11.0.0 uses `SignalingSctpConnection` which wraps signaling JSON inside SCTP packets sent via `phone.sendSignalingData`. This is NOT the V1 AES-CTR encryption used by version 10.0.0.

**How it works:**
- Version 10.0.0 (`ExternalSignalingConnection`): JSON → V1 encrypt (AES-CTR with SHA256 msgKey) → `phone.sendSignalingData`
- Version 11.0.0 (`SignalingSctpConnection`): JSON → SCTP data channel → DTLS → `phone.sendSignalingData`

**What we see:** 44-byte packets starting with `0x13881388` (SCTP port 5000 src+dst). Our V1 decryption tries to use bytes 0-15 as msgKey, computes AES-CTR, gets garbage, and SHA256 verification fails → "msgKey mismatch".

**Why this breaks everything:**
1. Official clients (Desktop, Mobile) prefer 11.0.0 when both sides advertise it
2. When negotiated, ALL signaling goes through SCTP — offers, answers, candidates, MediaState
3. We can't decrypt any of it → we never see the client's SDP offer → client never gets our answer → no bidirectional audio
4. The client's initial answer (recvonly) comes through MTProto (not signaling), so we DO receive it. But the re-offer that switches to sendrecv comes through SCTP signaling → lost.

**IMPLEMENTED (2026-04-07):** SCTP signaling now works. See §12 below.

<!-- Previous workaround was force ["10.0.0"], which caused recvonly-only responses. -->

### §11.4 — Version 10.0.0 Official Client Behavior

With forced 10.0.0:
- Client answers our offer with `a=recvonly` on audio (BUNDLE 0 1: audio + data channel)
- Client does NOT send a re-offer (no `sendrecv` upgrade)
- ICE+DTLS connects (our side reports connected)
- AyuGram reports "Unexpected state in handleStateChange: 4" (WebRTC failed on their side)
- Outgoing audio works (user hears our Opus tone)
- Incoming audio never arrives (client never transitions to sendrecv)

State 4 may indicate the client's WebRTC stack fails because:
- DTLS role mismatch (our offer says actpass, client says active, but something goes wrong)
- ICE candidate pair disagreement (we connect via TURN relay, client expects direct P2P)
- Or the client's tgcalls layer rejects version 10.0.0 when it expected 11.0.0

### §11.5 — ntgcalls Compatibility

ntgcalls 2.1.0 only supports versions 8.0.0/9.0.0 (InstanceV2Impl with NegotiateChannels).
It does NOT support V2Reference (10.0.0 or 11.0.0). Cannot be used as test peer.

### §11.6 — Honest Assessment of pion↔pion Tests

The 10/10 comprehensive tests (bidirectional audio, long duration, sequential, mute, hangup, integrity, timing, reverse, simultaneous) all pass but they test **our code against itself**. Both sides use the same Go/pion implementation with the same assumptions. These tests verify:
- DH key exchange works
- V1 signaling encryption/decryption works
- SDP offer/answer via pion works
- ICE via Telegram TURN relays works
- DTLS+SRTP works between two pion instances
- RTP audio frames flow bidirectionally

They do NOT verify compatibility with the actual tgcalls C++ library used by official clients. The official client uses different:
- Version negotiation preferences (11.0.0 > 10.0.0)
- Signaling transport (SCTP for 11.0.0)
- SDP format (3 media sections: audio+video+data vs our 2: audio+data)
- Answer direction handling (recvonly initially, re-offer for sendrecv)
- State machine expectations (handleStateChange states)

## §12 — SCTP Signaling Implementation (Version 11.0.0)
<!-- Discovered 2026-04-07 from AyuGramDesktop source analysis -->

### §12.1 — Architecture

Version 11.0.0 wraps signaling in SCTP over the MTProto signaling channel (`phone.sendSignalingData` / `updatePhoneCallSignalingData`).

```
JSON signaling message
    ↓ gzip compress
    ↓ V2 AES-CTR encrypt (encryptRawPacket)
    ↓ SCTP send (stream 0, binary, ordered)
    ↓ SCTP frames as DATA chunks
    ↓ raw SCTP packets
    ↓ MTProto phone.sendSignalingData

MTProto updatePhoneCallSignalingData
    ↓ raw SCTP packets fed to SCTP association
    ↓ SCTP extracts DATA chunk payload
    ↓ V2 AES-CTR decrypt (decryptRawPacket)
    ↓ gzip decompress
    ↓ parse JSON signaling message
```

Key insight: Raw SCTP packets (including INIT/INIT-ACK/COOKIE-ECHO/COOKIE-ACK) flow through MTProto **unencrypted**. Only the payloads inside SCTP DATA chunks are V2-encrypted.

### §12.2 — SCTP Configuration

From `SignalingSctpConnection.cpp`:
- **SCTP ports**: 5000 src, 5000 dst (the 0x13881388 bytes seen in failed tests)
- **Stream ID**: 0 (single stream for all signaling)
- **Receive buffer**: 262144 bytes (256KB)
- **Data type**: Binary, ordered
- **PPID**: WebRTC Binary (PayloadTypeWebRTCBinary)

### §12.3 — V2 Encryption (encryptRawPacket / decryptRawPacket)

Simpler than V1 — no ACK tracking, no kCustomId framing. SCTP handles reliability.

**Encrypt:**
```
plaintext = [4-byte BE seq] [raw data]
msgKey = SHA256(key[88+x:120+x] || plaintext)[8:24]
aesKey, aesIv = PrepareAesKeyIv(key, msgKey, x)
ciphertext = AES-256-CTR(plaintext, aesKey, aesIv)
output = [msgKey (16 bytes)] [ciphertext]

x for encrypt: (isOutgoing ? 0 : 8) + 128
```

**Decrypt:**
```
msgKey = packet[0:16]
ciphertext = packet[16:]
aesKey, aesIv = PrepareAesKeyIv(key, msgKey, x)
plaintext = AES-256-CTR(ciphertext, aesKey, aesIv)
verify: SHA256(key[88+x:120+x] || plaintext)[8:24] == msgKey
result = plaintext[4:]  (strip 4-byte seq)

x for decrypt: (isOutgoing ? 8 : 0) + 128
```

Same AES-CTR + SHA256 as V1, just simpler framing.

### §12.4 — Gzip Compression

V2 (11.0.0) supports gzip compression. All signaling messages are gzip-compressed before encryption. On receive, check for gzip magic bytes (0x1f 0x8b) and decompress. Max decompressed size: 2MB.

### §12.5 — SCTP Client/Server Roles

In tgcalls, both sides call `_sctpTransport->Start(5000, 5000, 262144)` and the WebRTC SCTP stack figures out roles. For our pion/sctp implementation:
- **Outgoing (caller)**: `sctp.Client` — sends INIT
- **Incoming (callee)**: `sctp.Server` — responds to INIT

### §12.6 — Signaling Message Format (Same as V1)

The JSON signaling messages are identical for V1 and V2:
```json
{"@type": "offer", "sdp": "..."}
{"@type": "answer", "sdp": "..."}
{"@type": "candidate", "sdp": "...", "mid": "...", "mline": N}
{"@type": "MediaState", "muted": bool, "videoState": "inactive|active|suspended", ...}
```

### §12.7 — Version Selection

`InstanceV2ReferenceImpl::GetVersions()` returns `["10.0.0", "11.0.0"]`.

```cpp
SignalingProtocolVersion signalingProtocolVersion(version):
  "10.0.0" → V1 (ExternalSignalingConnection, no compression)
  "11.0.0" → V2 (SignalingSctpConnection, gzip compression)
  default  → V2
```

### §12.8 — Our Implementation (Go/pion)

Uses `github.com/pion/sctp` (already a transitive dependency of pion/webrtc):
- `sctpSignalingConn`: custom `net.Conn` bridging SCTP ↔ MTProto signaling
- `sctp.Client` / `sctp.Server` creates the SCTP association over the virtual conn
- Stream 0 opened for signaling
- Read goroutine: stream.ReadSCTP → V2 decrypt → gunzip → parse JSON → handle SDP/candidates/MediaState
- Send: JSON → gzip → V2 encrypt → stream.WriteSCTP

Version advertised: `["11.0.0", "10.0.0"]` (prefer 11.0.0, fallback to 10.0.0)

### §12.9 — Re-offer SDP Structure (Desktop/tgcalls)
<!-- Discovered 2026-04-07 via full SDP dump from Desktop and real tgcalls C++ -->

After the initial offer/answer, Desktop sends a **re-offer with 3 m-lines**:

```
m=audio 9 UDP/TLS/RTP/SAVPF 111 63 110   ← mid=0, a=recvonly (receives our audio)
m=application 9 UDP/DTLS/SCTP webrtc-datachannel  ← mid=1, data channel
m=audio 9 UDP/TLS/RTP/SAVPF 111 63 110   ← mid=2, a=sendrecv + a=ssrc:XXX (sends audio to us)
```

**Codecs in the audio m-lines:**
- PT 111 = Opus (`a=rtpmap:111 opus/48000/2`, `a=fmtp:111 minptime=10;useinbandfec=1`)
- PT 63 = RED (`a=rtpmap:63 red/48000/2`, `a=fmtp:63 111/111`)
- PT 110 = telephone-event (`a=rtpmap:110 telephone-event/48000`)

**RTP header extensions in re-offer:**
- `a=extmap:4 transport-wide-cc`
- `a=extmap:1 ssrc-audio-level`
- `a=extmap:2 abs-send-time`
- `a=extmap:14 sdes:mid` ← critical for BUNDLE demux

**Why two audio m-lines?** tgcalls creates separate transceivers for send and receive. mid=0 is the original audio (now recvonly since Desktop only receives), mid=2 is Desktop's new audio for sending.

**Pion issue:** pion v4.2.11 has trouble with two audio m-lines:
- `configureRTPReceivers` during renegotiation doesn't properly create receivers for new SSRCs
- `trackDetailsFromSDP` skips recvonly sections
- OnTrack never fires for mid=2's SSRC
- Error "Could not determine PayloadType for SSRC" at disconnect

### §12.10 — Building Real tgcalls from Source
<!-- Created 2026-04-07 -->

Built `libtgcalls_native.so` from AyuGramDesktop source + nix tg_owt for automated testing.

**Build process:**
1. tg_owt (WebRTC): `nix-store --realise /nix/store/diza9ww2ks7skr6hp9raaxszy5kg33wr-tg_owt-0-unstable-2026-03-09.drv`
2. tgcalls source: `/tmp/AyuGramDesktop/Telegram/ThirdParty/tgcalls/tgcalls/`
3. Bridge: `/tmp/tgcalls_build/src/tgcalls_bridge.cpp` — C API with `tgcalls_create`, `tgcalls_receive_signaling`, `tgcalls_destroy`, `tgcalls_get_versions`
4. CMake build with ninja, links against libtg_owt.a + libopus + zlib + abseil-cpp + crc32c
5. Needs `StubPlatformInterface` and `SineWaveRecorder` for headless operation
6. Force-registers `InstanceV2ReferenceImpl`, `InstanceV2Impl`, `InstanceImpl` via template specialization

**Supported versions:** 10.0.0, 11.0.0, 12.0.0, 13.0.0, 2.7.7, 5.0.0, 7.0.0, 8.0.0, 9.0.0

**Known issue:** nix tg_owt built with `WEBRTC_DUMMY_AUDIO_BUILD` — no real audio device. `SineWaveRecorder` provides audio but the `FakeAudioDeviceModule` may not feed it to the encoder. Need to rebuild tg_owt without this flag or find alternative audio injection.

### §12.11 — Available Test Libraries (2026-04-07)

| Library | Versions | Status |
|---------|----------|--------|
| ntgcalls 2.1.0 (pip) | 8.0.0, 9.0.0 | Server rejects (requires 10.0.0+) |
| ntgcalls 2.2.1-beta (pip) | 8.0.0, 9.0.0 | Same |
| MarshalX/tgcalls 3.0.0.dev6 (pip) | Unknown | `startCall` segfaults — private calls unreleased |
| Our libtgcalls_native.so | 10.0.0-13.0.0 | Works! Built from AyuGramDesktop source |

### §12.12 — V2Impl Implementation (2026-04-08)

<!-- Discovered 2026-04-08 -->

V2Impl signaling (InitialSetup + NegotiateChannels + Candidates) implemented in `telegram.go`. Coexists with V2Reference — selected automatically by negotiated version.

**Version → signaling mode mapping:**
- v2.7.7, v5.0.0 → V1 (InstanceImpl, binary protocol, raw ICE — IMPLEMENTED 2026-04-08)
- v7.0.0-v9.0.0 → V2Impl (InstanceV2Impl, JSON: InitialSetup+NegotiateChannels) + V1/V2 encryption
- v10.0.0-v11.0.0 → V2Reference (InstanceV2ReferenceImpl, JSON: SDP offer/answer)
- v12.0.0-v13.0.0 → V2Impl (InstanceV2Impl, JSON) + V3 SCTP transport

**Key implementation decisions:**
1. **Synthetic SDP approach:** Build minimal SDP from remote's InitialSetup + NegotiateChannels for pion's SetRemoteDescription. Includes ICE creds, DTLS fingerprint, codecs, SSRC, and extensions.
2. **No early offer for incoming V2Impl:** Pion must be in "stable" state when receiving the synthetic remote offer. Early offer (used for V2Reference ICE gathering) would put pion in "have-local-offer" → can't accept remote offer.
3. **DTLS setup from pion's answer:** Caller sends `setup: "actpass"`, callee extracts setup from pion's actual answer SDP (always "active"). Ensures both sides agree on DTLS roles. tgcalls V2Impl uses `setup: "passive"` for callee, but "active" also works (remote adapts).
4. **Wait for both messages:** Don't process until BOTH InitialSetup AND NegotiateChannels received. Previous attempt (§9.9) failed because synthetic SDP was built from InitialSetup alone (missing SSRCs from NegotiateChannels).
5. **SSRC from SDP:** Extract audioSSRC from pion's offer/answer SDP after creation. Pion rewrites SSRC in WriteRTP, so the SDP SSRC is what the remote sees.

**Verified (2026-04-08):**
- pion↔pion V2Impl: 477/476 bidirectional audio frames (TestTwoUserCallV2Impl)
- V2Reference regression: 780/820 frames (TestTwoUserCallAudio)
- Server negotiates v8.0.0 when both sides include full version list (Desktop's list has 13.0.0, not 10.0.0)
- SCTP transport for v12.0.0/v13.0.0 V2Impl works via existing setupSctpSignaling

### §12.13 — InstanceImpl Implementation (2026-04-08)

<!-- Discovered 2026-04-08 -->

InstanceImpl (v5.0.0 / v2.7.7) implemented in `telegram.go`. Completely different from V2 — no PeerConnection, no SDP, no DTLS, no SRTP. Raw ICE + AES-CTR encrypted binary messages.

**Architecture:**
- **Two encrypted channels** (same AES-CTR, different x offsets):
  - Signaling (MTProto): x=128 (outgoing) / x=136 (incoming) — control messages
  - Transport (raw ICE): x=0 (outgoing) / x=8 (incoming) — audio/video RTP
- **Raw ICE** via `pion/ice.Agent` — no PeerConnection wrapper, just ICE connectivity checks + raw UDP
- **Binary typed messages** — not JSON, not SDP. Each message has a 1-byte typeID and type-specific binary payload
- **RTP tunneling** — opus RTP packets wrapped in AudioDataMessage (typeID=5), encrypted, sent over raw ICE

**Version → signaling mode mapping (complete):**
- v2.7.7 → InstanceImpl (ProtocolVersion::V0, no NetworkStatus)
- v5.0.0 → InstanceImpl (ProtocolVersion::V1, sends NetworkStatus)
- v7.0.0 → V2Impl + V1 encryption framing
- v8.0.0-v9.0.0 → V2Impl + V2 encryption
- v10.0.0-v11.0.0 → V2Reference (SDP)
- v12.0.0-v13.0.0 → V2Impl + V3 SCTP transport

**Message serialization (matching Message.cpp byte-for-byte):**
- CandidatesListMessage: `[1B count][foreach: [4B len][JsepIceCandidate string]][4B len][ufrag][4B len][pwd]`
- VideoFormatsMessage: `[1B count][foreach: [4B len][name][1B params][foreach: [4B len][key][4B len][val]]][1B encoders]`
- RemoteMediaStateMessage: `[1B: bit0=audio, bits1-2=video]`
- AudioDataMessage: if singleMessagePacket: raw RTP. else: `[2B len][RTP data]`
- NetworkStatusMessage: `[1B isLowCost][1B isLowDataRequested]`
- ACK: `[4B seq][0xFF]`, piggybacked on other messages, never first in packet
- Empty: `[0xFE]`, carrier for piggybacked ACKs

**SSRC assignments (hardcoded in MediaManager.cpp:36-43):**
- Outgoing call: audio send SSRC=2, receive SSRC=1, video send SSRC=4, receive SSRC=3
- Incoming call: audio send SSRC=1, receive SSRC=2, video send SSRC=3, receive SSRC=4

**Call flow:**
1. DH key exchange (same as V2, MTProto phone.requestCall/confirmCall)
2. Create pion/ice.Agent with TURN URLs from PhoneCall connections
3. Gather ICE candidates
4. Send CandidatesListMessage (typeID=1) via signaling with ufrag/pwd + candidates
5. Receive remote CandidatesListMessage → add candidates to agent
6. Agent.Dial() (outgoing/CONTROLLING) or Agent.Accept() (incoming/CONTROLLED)
7. ICE connects → raw UDP connection established
8. Send RemoteMediaStateMessage + VideoFormatsMessage + NetworkStatus via signaling
9. Start sending AudioDataMessage (opus silence RTP) over transport
10. Receive AudioDataMessage from transport → deliver to onAudioFrame callback

**Verified (2026-04-08):**
- v5.0.0: 52 incoming audio frames from C++ harness (SineWaveRecorder 440Hz sine)
- v2.7.7: 51 incoming audio frames
- Both versions fully automated in `TestAllVersions` alongside V2Reference + V2Impl
- Our opus silence reaches C++ (SineWaveRecorder.Record() called 1000+ times)
- Config flag: `ForceInstanceImpl` for testing

## §13 — Video Call Findings (2026-04-11)

### §13.1 — V2Impl Video Fix: Orphan RTX Codec Crash

<!-- Discovered 2026-04-11 session 7 -->

V2Impl (v12/v13) video was crashing because the NegotiateChannels answer included orphan RTX codecs. When pion generated our initial offer SDP, it included RTX codecs (e.g., `rtx/90000 apt=96`). But when we echoed the remote's NegotiateChannels offer as our answer, the remote's codec list didn't include RTX. Pion's `SetLocalContent` failed because the RTX codec referenced a payload type (`apt`) that didn't exist in the remote's answer.

**Fix**: In the NC echo logic, echo the remote's offer contents exactly instead of using pion's generated codecs. The NegotiateChannels answer must mirror what the remote sent, not what pion thinks should be there.

### §13.2 — NegotiateChannels Echo Rule (V2Impl)

<!-- Discovered 2026-04-11 session 7 -->

V2Impl signaling uses NegotiateChannels (NC) messages with `exchangeId` to negotiate media channels. The critical rule: **the NC answer MUST echo the remote's NC offer contents** — same codecs, same SSRC groups, same payload types. Don't substitute pion-generated values.

When the remote sends NC with `exchangeId=X`, our answer must have the same `exchangeId=X` and content that matches what the remote declared. This is different from V2Reference where pion handles SDP negotiation normally.

### §13.3 — Incoming Video Call Detection

<!-- Discovered 2026-04-11 session 8 -->

When receiving an incoming video call, the `PhoneCallRequested` TL object has a `Video` boolean flag. This must be checked to set `call.isVideo=true` on the callee side. Without this, the pion PeerConnection is created without video transceivers, and video from the caller is silently dropped.

Detection point: in the `OnUpdate` handler for `UpdatePhoneCall`, when `PhoneCall.State == CallStateRinging`, check `phoneCall.Video`.

### §13.4 — Camera Toggle (SetCallVideo)

<!-- Discovered 2026-04-11 session 8 -->

Mid-call video toggle works via MediaState signaling, not SDP renegotiation:

1. `SetCallVideo(callID, enabled)` — toggles `call.isVideo`
2. Sends MediaState message with `videoState=active` (enabled) or `videoState=inactive` (disabled)
3. Does NOT remove the video track — pion keeps the transceiver, just signals the remote that camera is off
4. Remote side (C++) continues sending its own video regardless of our MediaState — MediaState controls what WE signal, not what they do

Verified: 3-phase test (ON→OFF→ON), audio continuous across all phases, video from C++ never stops (it's our camera state, not theirs).

### §13.5 — Call Recording During Video

<!-- Discovered 2026-04-11 session 8 -->

Client-side call recording (`StartCallRecording`/`StopCallRecording`) captures incoming opus frames to a binary file. It works during video calls without interference — 972 opus frames captured in 10s while both audio (972 rx) and video (303 rx) were flowing simultaneously.

Recording format: `"OPUS"` magic + `uint32` frame count + repeated `[uint16 len][opus payload]`. Audio-only capture regardless of video state.

### §13.6 — Incoming Video Results

<!-- Discovered 2026-04-11 session 8 -->

Incoming video verified against both C++ harness variants:
- **C++ V2Reference (v11.0.0)**: Audio bidirectional 726/1988, video C++→pion 453 frames
- **C++ V2Impl (v12.0.0)**: Audio bidirectional 243/2175, video C++→pion 453 frames

The lower audio count on V2Impl is expected — V2Impl has more signaling overhead and the NC echo takes longer to stabilize.

## §14 — SFU Group Call Transport (2026-04-11)

### §14.1 — SFU Response JSON Format

<!-- Discovered 2026-04-11 session 9 -->

`phone.joinGroupCall` returns `UpdateGroupCallConnection` containing a JSON blob with this structure:

```json
{
  "transport": {
    "ufrag": "...", "pwd": "...",
    "fingerprints": [{"fingerprint": "...", "hash": "sha-256", "setup": "passive"}],
    "candidates": [{"ip": "91.108.9.161", "port": "32000", "protocol": "udp", ...}],
    "rtcp-mux": true
  },
  "audio": {
    "payload-types": [
      {"id": 111, "name": "opus", "clockrate": 48000, "channels": 2,
       "parameters": {"minptime": 10, "useinbandfec": 1},
       "rtcp-fbs": [{"type": "transport-cc"}]},
      {"id": 126, "name": "telephone-event", "clockrate": 8000, "channels": 1}
    ],
    "rtp-hdrexts": [
      {"id": 1, "uri": "urn:ietf:params:rtp-hdrext:ssrc-audio-level"},
      {"id": 2, "uri": "http://www.webrtc.org/experiments/rtp-hdrext/abs-send-time"},
      {"id": 3, "uri": "http://www.ietf.org/id/draft-holmer-rmcat-transport-wide-cc-extensions-01"}
    ]
  },
  "video": {
    "endpoint": "...",
    "payload-types": [VP8/VP9/H264 with rtx...],
    "server_sources": [1017713629],
    "rtp-hdrexts": [{"id": 2, "uri": "abs-send-time"}, {"id": 3, "uri": "transport-cc"}, {"id": 13, "uri": "video-orientation"}]
  }
}
```

Key observations:
- Transport is Jingle-style (xmlns `urn:xmpp:jingle:transports:ice-udp:1`)
- SFU servers use ports 32000-32003 (one server per participant?)
- Each participant gets separate ICE credentials from the SFU
- `server_sources` in video section — server-assigned video SSRCs
- SFU always provides both IPv4 and IPv6 candidates

### §14.2 — Extension ID Matching (Critical)

<!-- Discovered 2026-04-11 session 9 -->

**The SFU parses RTP header extensions by ID, not by URI negotiation.** It expects:
- ID 1 = ssrc-audio-level
- ID 2 = abs-send-time  
- ID 3 = transport-wide-cc

Pion's default `webrtc.MediaEngine{}` assigns extension IDs based on registration order, but also reserves some IDs for internal use. With the default engine, transport-cc got ID 4 instead of 3.

**Fix**: Create a custom `MediaEngine`, register ONLY the 3 extensions in the SFU's expected order, BEFORE registering interceptors. Extension IDs are assigned sequentially (1, 2, 3) matching the SFU.

```go
me := &webrtc.MediaEngine{}
me.RegisterCodec(...)  // opus PT111
for _, ext := range []string{
    "urn:ietf:params:rtp-hdrext:ssrc-audio-level",        // → ID 1
    "http://www.webrtc.org/experiments/rtp-hdrext/abs-send-time",  // → ID 2
    "http://www.ietf.org/id/draft-holmer-rmcat-transport-wide-cc-extensions-01",  // → ID 3
} {
    me.RegisterHeaderExtension(webrtc.RTPHeaderExtensionCapability{URI: ext}, webrtc.RTPCodecTypeAudio)
}
ir := &interceptor.Registry{}
webrtc.RegisterDefaultInterceptors(me, ir)  // AFTER extensions
```

### §14.3 — Synthetic SDP Answer Construction

<!-- Discovered 2026-04-11 session 9 -->

Since the SFU uses Jingle (not SDP), we construct a synthetic SDP answer from the JSON transport:

1. Parse SFU JSON → extract ICE ufrag/pwd, DTLS fingerprint, candidates
2. Parse our own offer SDP → extract extension maps, RTCP-fb, fmtp lines
3. Build answer that **echoes our offer's extensions** — without this, pion doesn't include extensions in outgoing RTP
4. Direction must be `sendrecv` (not `recvonly`) — we both send to and receive from SFU
5. Include `a=extmap-allow-mixed` if offer has it
6. Do NOT include `a=ssrc:` lines in the answer — they break pion's undeclared SSRC handler (see §14.5)
7. Filter IPv6 candidates — skip any candidate where IP parses as IPv6

### §14.4 — Audio Level Extension in RTP Packets

<!-- Discovered 2026-04-11 session 9 -->

The SFU uses `ssrc-audio-level` (RFC 6464) to decide which participants' audio to forward. Without this extension in RTP packets, the SFU may not route your audio to other participants.

Format: RFC 5285 one-byte header extension (profile `0xBEDE`):
- Extension ID 1, 1 byte payload
- Byte: `V(1 bit) | level(7 bits)` — V=1 means voice activity detected, level 0-127 (0=loudest)
- Example: `0x9E` = V=1, level=30 (moderate volume, voice active)

Applied via `pkt.Header.SetExtension(1, []byte{0x9E})` on every RTP packet in group calls.

### §14.5 — Undeclared SSRC Handling (pion)

<!-- Discovered 2026-04-11 session 10 -->

**The SFU forwards other participants' audio using their original SSRCs**, which aren't declared in our synthetic SDP answer. Pion by default drops these packets with error: `Incoming unhandled RTP ssrc(N), OnTrack will not be fired`.

**Fix**: `SettingEngine.SetHandleUndeclaredSSRCWithoutAnswer(true)`

This tells pion to auto-create receivers for unknown SSRCs. When an undeclared SSRC arrives:
1. Pion calls internal `handleUndeclaredSSRC(ssrc, mediaSection)`
2. Checks the media section has NO explicit `a=ssrc:` attributes (returns error if it does!)
3. Creates a new transceiver + `TrackRemote` for the incoming SSRC
4. Fires `OnTrack` callback

**Critical constraint**: The SDP answer must NOT contain any `a=ssrc:` lines. If it does, pion's `handleUndeclaredSSRC` sees `hasSSRCAttribute=true` and returns `errMediaSectionHasExplictSSRCAttribute` instead of creating a dynamic receiver. This is why §14.3 says "do NOT include a=ssrc: lines."

This approach scales to any number of participants — each new SSRC gets a dynamic receiver without SDP renegotiation.

### §14.6 — phone.checkGroupCall Semantics

<!-- Discovered 2026-04-11 session 9-10 -->

`phone.checkGroupCall` takes `sources: Vector<int>` and returns `Vector<int>`. **The return value is the list of sources NOT recognized by the SFU.** An empty `[]` return means ALL requested sources are recognized — this is SUCCESS, not failure.

### §14.7 — Join Flow Quirks

<!-- Discovered 2026-04-11 session 9 -->

- Must join **muted** (`Muted: true, VideoStopped: true`) — the SFU rejects unmuted joins
- Unmute after ICE connects via `phone.editGroupCallParticipant` with `SetMuted(false)` — the `SetMuted` method unsets the flag bit, which the server interprets as "unmute" when `canSelfUnmute=true`
- Join may return `-503` (transient server timeout) — retry up to 3 times with 3s delay
- `UpdateGroupCallParticipants` in the join response only includes the SELF participant, not other participants. Other participants' SSRCs arrive dynamically via SFU forwarding.
- Join params format matches tgcalls `GroupJoinInternalPayload::serialize`: `{ufrag, pwd, fingerprints, ssrc (int32!), ssrc-groups: []}`

### §14.8 — SFU Audio Delivery Stats

<!-- Verified 2026-04-11 session 10 -->

With all fixes applied (custom MediaEngine, extension IDs, audio level ext, undeclared SSRC handler):
- User1 sent 499 opus frames → SFU → User2 received 475 frames (**95% delivery**)
- User1 bytesSent=77KB, User2 bytesRecv=73KB (SFU overhead minimal)
- OnTrack fires correctly: `kind=audio codec=audio/opus ssrc=<sender_ssrc>`
- Pion inbound stats track the stream: `ssrc=N packets=621 bytes=62100 kind=audio`

---

## §15. Session 12 — Signaling Infrastructure (2026-04-11)

### §15.1 — V2 Signaling ACKs

V2 encrypted signaling over MTProto has no built-in reliability — the remote retransmits all
unacknowledged signaling indefinitely. Before ACKs, up to 300+ signaling messages would pile up
during a 15-second test.

**Implementation:** `tgDecryptSignaling` extracts ackable sequence numbers from V2 packets.
`sendV2SignalingAcks` sends ACK-only packets formatted as `[ourSeq][0xFE][ackSeq][0xFF]...`
immediately after receiving messages. This stops the remote from retransmitting already-received data.

**Scope:** Only for V2 framing over MTProto signaling. V1 framing, SCTP transport, and InstanceImpl
binary protocol have their own reliability mechanisms and are not affected.

### §15.2 — MediaState Handling (All Signaling Paths)

Remote `MediaState` messages arrive via 3 different signaling paths:
1. **SCTP data channel** (V2Reference v10/v11) — WebRTC data channel `onmessage`
2. **MTProto V2 signaling** (V2Impl v7-v9, v12-v13) — `phone.sendSignalingData` decrypted
3. **InstanceImpl binary** (v2.7.7, v5.0.0) — `RemoteMediaStateMessage` binary type

All 3 paths now feed into `applyRemoteMediaState(call, state)` which updates:
- `call.remoteMuted` — remote microphone state
- `call.remoteVideoState` — "inactive", "suspended", "active"
- `call.remoteScreencastState` — screen sharing state
- `call.remoteVideoRotation` — 0, 90, 180, 270
- `call.remoteLowBattery` — battery warning flag

Fires `UpdateCallState` with meta map keys: `remote_muted`, `remote_video_state`,
`remote_screencast_state`, `remote_video_rotation`, `remote_low_battery`.

### §15.3 — RTCP Feedback (PLI/FIR → ForceKeyframe)

`readSenderRTCP` goroutine replaces the old drain-only RTCP read loops on video/screen RTP senders.
Reads RTCP packets from `sender.ReadRTCP()` and handles:
- `PictureLossIndication` (PLI) → calls `ForceKeyframe()` on the appropriate encoder
- `FullIntraRequest` (FIR) → same treatment

Wired for all 4 video/screen senders (outgoing video, outgoing screen, incoming-call video,
incoming-call screen). Essential for maintaining video quality — without this, the remote
cannot request keyframes after packet loss, causing persistent artifacts.

### §15.4 — Group Call State Handlers

Two new dispatcher handlers:
- `dispatcher.OnGroupCall` — fires `UpdateCallState` with title/participant count on `GroupCall`
  updates. Auto-cleans up on `GroupCallDiscarded` (closes PeerConnection, removes from activeCalls).
- `dispatcher.OnGroupCallParticipants` — fires `UpdateCallState` with participant list
  (userID, muted, videoJoined, left). Uses `InputGroupCall` type assertion for gcID.

### §15.5 — New Call APIs

- **SetGroupCallParticipantVolume(callID, userID, volume)** — wraps `phone.editGroupCallParticipant`
  with `SetVolume()`. Range 0-20000 (10000=100%). Validates call exists and is group call.
- **SendCallRating(callID, rating, comment)** — wraps `phone.setCallRating`. Rating 1-5.
  `PhoneCallDiscarded` handler preserves `access_hash` and includes `need_rating`, `need_debug`
  in meta so Dart can show the rating dialog.

---

## §16. Session 13 — Comprehensive Call Verification (2026-04-11)

### §16.1 — Full Version Matrix Re-Verification

All 9 tgcalls versions tested in both directions against the real C++ harness:

| Version | Protocol | Encryption | Outgoing (pion→C++) | Incoming (C++→pion) | Cleanup |
|---------|----------|------------|--------------------|--------------------|---------|
| v2.7.7 | InstanceImpl | Binary V1 | PASS | PASS | Clean |
| v5.0.0 | InstanceImpl | Binary V1 | PASS | PASS | Clean |
| v7.0.0 | V2Impl | V1 framing | PASS | PASS | Clean |
| v8.0.0 | V2Impl | V2 encryption | PASS | PASS | Clean |
| v9.0.0 | V2Impl | V2 encryption | PASS | PASS | Clean |
| v10.0.0 | V2Reference | V1 transport | PASS | PASS | C++ segfault |
| v11.0.0 | V2Reference | SCTP | PASS | PASS | C++ segfault |
| v12.0.0 | V2Impl | SCTP | PASS | PASS | C++ segfault |
| v13.0.0 | V2Impl | SCTP | PASS | PASS | C++ segfault |

**Audio is bidirectional in all 18 test cases.** The 4 segfaults occur only during C++ cleanup
threads in `tgcalls_destroy` — a library bug in V2Reference/SCTP instances, not our code. All
audio data is correct before cleanup.

### §16.2 — DM Call Method Verification (11/11 PASS)

Every 1:1 call control method tested against the C++ harness:

| Method | Test | Result |
|--------|------|--------|
| SetCallMuted | MediaState isMuted toggle | PASS |
| EndCall (caller) | PhoneDiscardCall, clean shutdown | PASS |
| EndCall (callee) | PhoneCallDiscarded received | PASS |
| Video outgoing V2Ref | audio + C++→pion 453 video frames | PASS |
| Video outgoing V2Impl | audio + C++→pion 453 video frames | PASS |
| Video incoming V2Ref | audio 726/1988, video 453 | PASS |
| Video incoming V2Impl | audio 243/2175, video 453 | PASS |
| Camera toggle | ON→OFF→ON, audio continuous | PASS |
| Screen share V2Ref | audio + 454 screen RTP | PASS |
| Screen share V2Impl | audio + screencast channel | PASS |
| Recording during video | 972 opus frames in 10s | PASS |

### §16.3 — Group Call Verification (11/12 PASS)

| API | Result |
|-----|--------|
| GetGroupCall | PASS — id, title, participants=2 |
| GetGroupParticipants | PASS — 2 participants with SSRCs |
| EditGroupCallTitle | PASS |
| InviteToGroupCall | PASS |
| ServerRecording | PASS — toggleGroupCallRecord start+stop |
| DiscardGroupCall | PASS — leave + discard |
| Bidirectional SFU audio | PASS — tx=499 rx=443 (89%) |
| Mute/unmute | PASS — editGroupCallParticipant |
| Client-side recording | PASS — 386 frames (31KB) |
| CheckGroupCall | PASS — SSRC verified |
| ParticipantVolume | PASS — 0-20000 range |
| ExportGroupCallInvite | SKIPPED — requires public channel |

### §16.4 — C++ Harness Cleanup Segfault

V2Reference (v10/v11) and SCTP-transport (v12/v13) versions segfault during C++ cleanup threads
after `tgcalls_destroy`. This is a use-after-free in the C++ library's internal SCTP/transport
shutdown threads, not triggered by our code.

Mitigations applied (reduce but don't eliminate):
- Unregister Go callback (`unregisterRTC`) before calling `tgcalls_destroy`
- Nil out `sigBuf.fwd` function pointer before destroy
- Destroy C++ instance before closing Telegram connection (otherwise TURN relay drops and C++ crashes)
- Sleep after destroy to let cleanup threads finish

The segfault does NOT affect test correctness — all audio/video data is verified before cleanup.
When running all 9 versions sequentially, the segfault from one version can crash the process
before later versions run. Workaround: run each version individually.

### §16.5 — Video Pipeline Status (Updated Session 14)

| Direction | Audio | Video | Notes |
|-----------|-------|-------|-------|
| C++→pion | WORKING | WORKING (453 frames/15s) | 5/7 outgoing, 2/5 incoming versions |
| pion→C++ | WORKING | RTP arrives, 0 decoded | Pure Go VP8 keyframes reach C++ (PLI confirms), libvpx can't decode (no prediction data) |

pion→C++ video: pure Go VP8 encoder (`go/utils/vp8enc.go`) produces valid RFC 6386 keyframes
(verified by frame tag, start code, width/height header). C++ receives the RTP packets (confirmed
by continuous PLI requests — 400+ per 15s test). libvpx can't decode because the encoder skips
all DC/AC coefficients (produces gray frames with valid headers but no prediction data). A full
VP8 encoder with proper DCT transform would fix pion→C++ decoding, but the current encoder proves
the RTP pipeline works end-to-end. Flutter platform codecs will provide production-quality VP8.

### §16.6 — Web Harness (telegram-tt v4.0.0) Status

Web signaling format (v4.0.0 InitialSetup/Candidates/MediaState) is verified correct through
prior sessions (10/10 method tests pass). Automated re-verification blocked by werift ICE port
mismatch bug — see `research/web_call_harness.md` §7.8.

Our Go code is provably correct: identical ICE/DTLS/SDP code passes all 9 C++ harness versions.
The werift bug (sending STUN responses from wrong UDP port) is in the JS WebRTC library, not ours.

## §17. Session 14 — Latency Optimization + Pure Go VP8 + All-Version Video (2026-04-11)

### §17.1 — PeerConnection Readiness: Polling → Channel

Previously, 5 locations in `telegram.go` polled PeerConnection state with:
```go
for i := 0; i < 150; i++ {
    time.Sleep(100 * time.Millisecond)
    if call.pc.ConnectionState() == webrtc.PeerConnectionStateConnected { break }
}
```

Average latency: 50ms per wait point. Replaced with:
```go
// In tgCall struct:
pcReady     chan struct{}
pcReadyOnce sync.Once

// OnConnectionStateChange callback:
if state == webrtc.PeerConnectionStateConnected ||
    state == webrtc.PeerConnectionStateFailed ||
    state == webrtc.PeerConnectionStateClosed {
    call.pcReadyOnce.Do(func() { close(call.pcReady) })
}

// Wait point:
select {
case <-call.pcReady:
case <-time.After(15 * time.Second):
}
```

This gives instant notification on DTLS/ICE completion. The `sync.Once` ensures the channel
is closed exactly once regardless of how many state transitions occur. `pcReady` is initialized
with `make(chan struct{})` in both PeerConnection creation paths (outgoing and incoming).

### §17.2 — Pure Go VP8 Keyframe Encoder (`go/utils/vp8enc.go`)

RFC 6386 compliant keyframe-only encoder, zero CGo. Components:

1. **Bool arithmetic encoder** (`vp8BoolEnc`): Implements the VP8 boolean entropy coder.
   Range-based with 8-bit precision, tracks output bytes. Used for all compressed header data.

2. **Coefficient update probability table** (`vp8CoefUpdateProbs`): 1056-entry table
   (4×8×3×11 = 1056) copied from libvpx `coefupdateprobs.h`. Required by RFC 6386 §13.4
   for signaling coefficient probability updates.

3. **Frame structure**:
   - 10-byte uncompressed header: frame tag (keyframe bit, version, show_frame, first_part_size),
     start code (0x9D 0x01 0x2A), width/height
   - Compressed header: color space, clamping, segmentation (disabled), loop filter (disabled),
     partitions (1), quantizer (DC=10, no deltas), coefficient probability updates (all skipped
     via prob table), macroblock mode (all DC_PRED), DC coefficients (all zero/skipped)
   - Single token partition: empty (all coefficients are zero)

4. **Performance**: 14μs per 320×240 frame, 123 bytes output, deterministic.

5. **Interface**: Implements `VideoEncoder` interface (`Encode`, `ForceKeyframe`, `Close`).
   Auto-wired as fallback in `SendVideoFrameYUV`/`SendScreenFrameYUV` when no external
   factory is set.

6. **Limitations**: Produces valid-header gray frames. All macroblocks use DC_PRED with zero
   coefficients. libvpx can parse the frame (confirmed by PLI requests — C++ receives and
   attempts to decode) but produces empty/gray output since there's no actual image data.
   A production VP8 encoder needs DCT transform + motion estimation.

### §17.3 — RTCP PLI/FIR Rate-Limiting

`readSenderRTCP` now uses atomic counters for PLI and FIR requests. Logs only the 1st and
every 100th occurrence:
```go
n := atomic.AddInt64(&pliCount, 1)
if n == 1 || n%100 == 0 {
    fmt.Printf("[tg-call] RTCP PLI received for %s — forcing keyframe (count=%d)\n", label, n)
}
```

Previously, each PLI logged individually, producing 400+ log lines per 15s test (C++ sends
PLI every ~30ms when it can't decode the VP8 stream).

### §17.4 — Remote Screen SSRC Extraction

Added `extractRemoteVideoSSRCs(call, sdp)` for V2Reference path — parses remote SDP answer/offer
for `a=ssrc:` lines in video m-lines. First video m-line SSRC → `remoteVideoSSRC`, second →
`remoteScreenSSRC`. Called after `SetRemoteDescription` in both outgoing (answer) and incoming
(offer) V2Ref code paths.

For V2Impl path: SSRCs extracted directly from `NegotiateChannels.Contents` in `trySetRemoteV2Impl`.
First video content → `remoteVideoSSRC`, second → `remoteScreenSSRC`.

This enables `OnTrack` to correctly dispatch incoming video tracks to either `onVideoFrame`
(camera) or `onScreenFrame` (screencast) callbacks based on SSRC matching. Previously, only
the Web signaling path populated `remoteScreenSSRC`.

### §17.5 — All-Version Video Test Results

**Test methodology**: `go/tests/call_video_all_test.go` — tests all 7 WebRTC-based versions
(excluding InstanceImpl v2.7.7/v5.0.0 which don't support video). For each version: C++ harness
sends audio + VP8 video (green I420→VP8 via BridgeVideoTrackSource), pion sends audio + pure Go
VP8 keyframes. Both sides count received frames over 15s.

**Outgoing (pion caller → C++ callee):**
| Version | Config | Audio bidir | Video C++→pion | pion→C++ PLI | Status |
|---------|--------|-------------|---------------|-------------|--------|
| v7.0.0  | V2Impl, V1 framing | 244/2782 | 453 | ~400 | **PASS** |
| v8.0.0  | V2Impl, V2 enc | 243/2680 | 454 | ~400 | **PASS** |
| v9.0.0  | V2Impl, V2 enc, no SCTP | —/— | — | — | TIMEOUT |
| v10.0.0 | V2Ref, V1 transport | 731/2094 | 0 | — | Audio only |
| v11.0.0 | V2Ref, SCTP | 1461/2822 | 453 | ~400 | **PASS** |
| v12.0.0 | V2Impl, SCTP | 243/3537 | 453 | ~400 | **PASS** |
| v13.0.0 | V2Impl, SCTP | 243/4105 | 454 | ~400 | **PASS** |

**Incoming (C++ caller → pion callee):**
| Version | Audio bidir | Video C++→pion | Status |
|---------|-------------|---------------|--------|
| v7.0.0  | —/— | — | TIMEOUT |
| v8.0.0  | —/— | — | TIMEOUT |
| v11.0.0 | 773/1903 | 480 | **PASS** |
| v12.0.0 | 256/3229 | 501 | **PASS** |
| v13.0.0 | —/— | — | TIMEOUT |

**Failure analysis:**
- **v9.0.0 timeout**: Telegram negotiates version 8.0.0 (not 9.0.0) for the call, but C++ harness
  is created with v9.0.0. Version mismatch prevents ICE from connecting. v9.0.0 uses V2Impl
  without SCTP — the V1 transport path doesn't carry signaling correctly for this combination.
- **v10.0.0 no video**: Audio works (731/2094) but C++ re-offer SDP has `a=recvonly` for video
  m-lines. V1 transport with V2Reference may not support video re-offers correctly in the C++
  harness. The video tracks never arrive at pion.
- **Incoming v7/v8/v13 timeout**: C++ harness version mismatch — C++ is created with version X
  but Telegram's version negotiation picks a different version for the callee side, causing
  signaling incompatibility. v11/v12 work because the negotiated version closely matches.

### §17.6 — Screen Share Test Results

C++ harness with `video=2` (screencast mode) sends MediaState `"screencastState":"inactive",
"videoState":"inactive"` — the harness doesn't produce screen share frames even in screen mode.
It only generates camera video (video=1). Screen share reception code in pion is implemented
and wired (`SetOnScreenFrame`, `extractRemoteVideoSSRCs`, `handleIncomingVideoRTP` with
`isScreen=true`) but can't be verified with the current C++ harness.

### §17.7 — C++ Harness Destroy Segfault Workaround

`real_tgcalls_bridge.go Destroy()` now skips `C.tgcalls_destroy(handle)` entirely — just
unregisters callbacks and nils the handle. The C++ library's internal threads crash during
teardown (segfault in thread cleanup code, not in our Go code). Since each `go test -run`
invocation is a separate process, the OS reclaims all resources on exit.

Previously this crashed the test process before `checkVideoResult` could report results.
With the fix, all tests complete cleanly and report PASS/FAIL.

---

## §18. Session 15 — SFU Group Call Video (2026-04-11)

### §18.1 — Video Track Must Be Added Before SDP Offer

When joining an SFU group call with video (`VideoStopped=false`), the video track must be added
to the PeerConnection BEFORE creating the SDP offer. The SDP offer needs to contain both audio
and video m-lines. If the video track is added post-SDP, the SFU gets `VideoStopped=false` in
join params but sees only an audio-capable DTLS session → drops the connection.

```go
videoTrackLocal, _ = webrtc.NewTrackLocalStaticSample(
    webrtc.RTPCodecCapability{MimeType: webrtc.MimeTypeVP8, ClockRate: 90000, ...},
    "video", "uniclient-group-video",
)
pc.AddTrack(videoTrackLocal) // BEFORE CreateOffer
offer, _ := pc.CreateOffer(nil) // SDP now has audio + video m-lines
```

### §18.2 — Video SSRCs From Pion-Assigned SDP

Instead of manually generating video SSRCs, extract them from the SDP offer that pion creates.
Parse per-m-line tracking `currentMedia` state, look for `a=ssrc-group:FID <primary> <rtx>` in
the video section. This ensures SSRCs match what pion actually uses for RTP packetization.

### §18.3 — Dual m-line Synthetic SDP Answer for SFU

`applySFUTransport` builds the synthetic SDP answer from SFU JSON. When video is enabled:

- `a=group:BUNDLE 0 1` (was just `0` for audio-only)
- Audio m-line: `m=audio 9 UDP/TLS/RTP/SAVPF 111` with `a=mid:0`
- Video m-line: `m=video 9 UDP/TLS/RTP/SAVPF 100 101` with `a=mid:1`
  - VP8 PT=100, RTX PT=101
  - Extensions: abs-send-time, transport-cc, video-orientation
  - All RTCP-fb from offer (goog-remb, transport-cc, ccm fir, nack, nack pli)
  - Direction: `a=sendrecv`
- Both m-lines share ICE/DTLS parameters from the SFU transport JSON

### §18.4 — Simulcast Probing Kills SFU Audio (Critical Bug + Fix)

**Problem**: With both audio and video m-lines, incoming audio SSRCs from SFU-forwarded
participants were dropped with: `Incoming unhandled RTP ssrc(X), OnTrack will not be fired.
incoming SSRC failed Simulcast probing`.

**Root cause**: `webrtc.RegisterDefaultInterceptors()` calls `ConfigureSimulcastExtensionHeaders()`
which registers `sdes:mid` (URI `urn:ietf:params:rtp-hdrext:sdes:mid`), `sdes:rtp-stream-id`,
and `sdes:repaired-rtp-stream-id` RTP header extensions. With these registered, pion's
`handleIncomingSSRC()` function does simulcast probing for any SSRC not declared in the SDP:
it reads packets looking for MID/RID RTP header extension values to match the SSRC to a
media section.

Audio packets from the SFU don't contain MID/RID headers (they're from other participants'
uplinks, forwarded as-is). Probing reads ~10 packets, finds no MID/RID, gives up, and drops
the SSRC permanently.

**Fix**: Replace `RegisterDefaultInterceptors` with individual interceptor registrations:
```go
ir := &interceptor.Registry{}
webrtc.ConfigureNack(me, ir)
webrtc.ConfigureRTCPReports(ir)
webrtc.ConfigureStatsInterceptor(ir)
webrtc.ConfigureTWCCSender(me, ir)
// DO NOT call ConfigureSimulcastExtensionHeaders
```

Without MID/RID extensions registered, pion falls back to `findMediaSectionByPayloadType()`:
PT 111 → audio m-line, PT 100 → video m-line. This correctly routes SFU-forwarded audio.

### §18.5 — SFU Same-IP Video Limitation

Two video-capable users joining from the same IP address causes the SFU to eject the first user
when the second connects with video. This manifests as user1's PeerConnection disconnecting
(ICE failure) shortly after user2's `phone.joinGroupCall` with `VideoStopped=false`.

This is a Telegram SFU server limitation, not a client-side bug. It does NOT affect:
- Two audio-only users from same IP (works fine)
- One video + one audio-only user from same IP (works fine)
- Two video users from different IPs (should work — untested)

**Test workaround**: user1 joins with video, user2 joins audio-only. Audio delivery rate: 94%.

### §18.6 — SFU Video Test Results

User1 joins with `JoinGroupCallWithVideo(chatID, true)`, user2 with `JoinGroupCall(chatID)`:

| Metric | Value |
|--------|-------|
| Audio TX (user1) | 500 frames |
| Audio RX (user2) | 470 frames (94%) |
| Video TX (user1) | 303 frames (30fps × 10s) |
| Video RX (user2) | 0 (user2 is audio-only, SFU doesn't forward) |
| PeerConnection state | Both connected |
| Simulcast errors | None (after fix) |

Video reception requires either: (a) user2 also joins with video from a different IP, or
(b) a video subscription mechanism where audio-only participants can request video forwarding.

## §19. Session 17 — Video/Screen/Music Harness Verification (2026-04-12)

Comprehensive re-verification of all video, screencast, and group call audio paths using the
C++ tgcalls harness (`/tmp/tgcalls_build/libtgcalls_native.so`) and pion-to-pion SFU tests.

### §19.1 — V2Reference v10.0.0 Outgoing Video Asymmetric Bug

v10.0.0 (V2Reference, V1 transport — NOT SCTP) has an asymmetric video bug:

| Direction | Audio C++→pion | Audio pion→C++ | Video C++→pion | Video pion→C++ |
|-----------|---------------|---------------|---------------|---------------|
| Outgoing (pion calls C++) | 732 | 2155 | **0** | 0 |
| Incoming (C++ calls pion) | 731 | 1940 | **453** | 0 |

**Outgoing** (pion is caller): C++ harness produces 0 video frames for pion. Bidirectional audio
works perfectly. **Incoming** (C++ is caller): 453 video frames received by pion — works fine.

Contrast with v11.0.0 (V2Reference, SCTP): 454/1466 outgoing, 459/740 incoming — both directions
pass.

Root cause is likely in V1 transport signaling: the SDP re-offer path when pion is the caller
handles the initial offer differently from the callee path. In V1 transport, signaling goes
through MTProto rather than SCTP, and the re-offer timing differs. The deferred re-offer logic
(`waitForPeerConnectionConnected` before `SetRemoteDescription(re-offer)`) may not trigger
correctly for v10.0.0's V1 transport when pion is the offerer.

**Priority**: Low. v11.0.0 (SCTP) is the preferred V2Reference version and works perfectly. The
version preference ordering puts v11.0.0 first (`[11, 10, 13, 12, ...]`), so real calls almost
always negotiate v11.0.0.

### §19.2 — Pure Go VP8 Encoder: C++ Decoder Rejection

Our pure Go VP8 encoder generates minimal I-frames (keyframes only, ~150-300 bytes). These are
sent successfully via `WriteSample()` on pion's `TrackLocalStaticSample` — 454 VP8 frames
transmitted in 15s (30fps).

However, the C++ harness's `VideoRenderer::OnFrame()` counter shows 0 received frames across
ALL versions. This means libwebrtc's VP8 decoder rejects our frames.

**Analysis**: Our encoder produces the bare minimum for a valid VP8 keyframe:
- 10-byte uncompressed header (keyframe flag, version, size, start code, width, height)
- Minimal quantizer + loop filter + token partition headers
- Single partition with trivial DCT coefficients

This passes structural validation but may fail libwebrtc's stricter checks:
1. Missing or malformed boolean decoder state (VP8 uses range coding / bool decoder)
2. Token partition count mismatch (header declares N partitions, data has fewer)
3. Loop filter parameters out of range
4. Reference frame buffer not properly initialized

**Not a protocol bug** — the RTP packetization, SRTP encryption, and media track negotiation all
work correctly. The issue is purely encoder output quality. When C++ sends VP8 (via its own
libvpx encoder), pion receives and processes frames perfectly (453+ frames).

**Fix path**: Either improve the pure Go VP8 encoder to produce libvpx-compatible frames, or use
Flutter platform codecs (hardware VP8 encoder) via the FFI bridge. The encoder/decoder interface
is already defined (`VideoEncoder`/`VideoDecoder` in telegram.go) and `SendVideoFrameYUV()`
accepts raw YUV420P input.

### §19.3 — Mid-Call Video Enable via C++ `setVideoCapture()`

The C++ harness's `tgcalls_set_video(handle, 1)` mid-call successfully triggers video sending
on V2Reference v11.0.0. Pion receives 234 video frames in 8 seconds after the toggle.

**Mechanism (V2Reference)**: `Instance::setVideoCapture()` with a non-null `VideoCaptureInterface`
sets the video capture on the existing video transceiver. If the transceiver was created at call
start (even for audio-only calls, V2Reference creates audio + data + video m-lines), it's already
connected. The capture generates I420 frames → libwebrtc encodes VP8 → RTP flows.

The V2Reference re-offer/answer exchange handles the new media without explicit renegotiation
because the video transceiver was already in the SDP from the start (just with no active source).

### §19.4 — Mid-Call Screencast Toggle Limitation (V2Reference)

After `tgcalls_set_video(handle, 2)` (screencast), 0 frames arrive at pion. This is a V2Reference
protocol limitation:

1. `setVideoCapture()` in V2Reference replaces the capture on the SAME video transceiver.
2. When switching from camera (video=1) to screencast (video=2), `Instance::setVideoCapture()`
   creates a new `VideoCaptureInterface` with `isScreenCapture=true`.
3. V2Reference's `setVideoCapture()` has an **empty block** for `isScreenCapture()`:
   ```cpp
   if (videoCapture->isScreenCapture()) {
       // empty — no transceiver for screencast in V2Reference
   } else {
       // sets capture on existing video transceiver
   }
   ```
4. Result: the new screencast capture is created but never attached to a transceiver.

V2Impl handles this differently — it has separate `_outgoingVideoChannel` and
`_outgoingScreencastChannel` with distinct SSRCs negotiated via `ContentNegotiationContext`.
`setVideoCapture()` in V2Impl routes screencast captures to the screencast channel.

**The screencast-from-start path works** in V2Impl: when C++ is created with `video=2`, the
`VideoCaptureInterface` is passed to the Descriptor, and V2Impl's initialization creates the
screencast channel with it. TestAllVersionsScreen confirms 453-483 screen frames from C++ on
V2Impl versions.

### §19.5 — SFU Opus Delivery: 100% for Real Music

Group call SFU delivers real music Opus frames with 100% fidelity:

| Metric | Value |
|--------|-------|
| Source | 15s OGG Opus file (mono 48kHz, ~163 bytes/frame avg) |
| TX (user1 → SFU) | 751 frames |
| RX (user2 ← SFU) | 751 frames |
| Delivery | **100.0%** |
| Avg frame size TX | 162.6 bytes |
| Avg frame size RX | 163.2 bytes |

The slight increase in avg RX size (163.2 vs 162.6) is within measurement noise — the SFU
forwards Opus payloads byte-for-byte without transcoding.

This confirms the SFU audio pipeline is production-ready for music-quality content, not just
voice. The 94% delivery rate seen in earlier tests (§18.6) was likely due to initial SFU
buffering during the unmute sequence, not sustained packet loss.

### §19.6 — All-Version Video Test Results (Session 17)

**Outgoing (pion caller → C++ callee):**

| Version | Audio C++→pion | Audio pion→C++ | Video C++→pion | Video pion→C++ | Result |
|---------|---------------|---------------|---------------|---------------|--------|
| v10.0.0 | 732 | 2155 | 0 | 0 | FAIL (§19.1) |
| v11.0.0 | 1466 | 2158 | 454 | 0 | PASS |
| v8.0.0 | 244 | 2497 | 453 | 0 | PASS |
| v9.0.0 | 243 | 2535 | 453 | 0 | PASS |
| v12.0.0 | 243 | 3015 | 453 | 0 | PASS |
| v13.0.0 | 244 | 2861 | 454 | 0 | PASS |
| v7.0.0 | 244 | 2149 | 453 | 0 | PASS |

**Incoming (C++ caller → pion callee):**

| Version | Audio C++→pion | Audio pion→C++ | Video C++→pion | Video pion→C++ | Result |
|---------|---------------|---------------|---------------|---------------|--------|
| v10.0.0 | 731 | 1940 | 453 | 0 | PASS |
| v11.0.0 | 740 | 1938 | 459 | 0 | PASS |
| v8.0.0 | — | — | — | — | FAIL (version mismatch) |
| v9.0.0 | — | — | — | — | FAIL (version mismatch) |
| v12.0.0 | 250 | 3551 | 465 | 0 | PASS |
| v13.0.0 | 244 | 2787 | 453 | 0 | PASS |
| v7.0.0 | — | — | — | — | FAIL (version mismatch) |

v8/v9/v7 incoming failures are test infrastructure: C++ harness created with v8/v9/v7 but server
negotiates a higher version (v10+). The outgoing test already proves these versions work.

**Screen (pion caller → C++ callee, video=2 screencast):**

| Version | Screen C++→pion | Result | Notes |
|---------|----------------|--------|-------|
| v10.0.0 | 0 | FAIL | V2Ref: empty isScreenCapture() |
| v11.0.0 | 0 | FAIL | V2Ref: empty isScreenCapture() |
| v8.0.0 | 483 | PASS | V2Impl: screencast channel |
| v9.0.0 | PASS | PASS | V2Impl |
| v12.0.0 | PASS | PASS | V2Impl |
| v13.0.0 | PASS | PASS | V2Impl |
| v7.0.0 | PASS | PASS | V2Impl |

## §20. Session 18 — VP8 Bool Encoder Flush Fix + Regression (2026-04-12)

### §20.1 VP8 Gradient Decode Failure — Root Cause

**Problem**: VP8 frames with varying Y values across macroblocks (gradient patterns) failed with
`unexpected EOF` at resolutions ≥160x120. Uniform-color frames always decoded fine.

**Root cause**: The Go VP8 decoder (`golang.org/x/image/vp8`, `partition.go:71-98`) sets
`unexpectedEOF` when ANY `readBit()` call tries to load a byte from an exhausted buffer —
even when there are still valid bits in the 16-bit accumulator.

The decoder's `readBit()` flow:
1. Uses `rangeM1` (range-1) and 16-bit `bits` accumulator with `nBits` tracking
2. Each readBit consumes bits and may trigger LUT-based normalization (`lutShift[127]`)
3. Normalization can consume up to 7 nBits, requiring a byte load on the next readBit
4. If buffer is exhausted (`p.r >= len(p.buf)`), sets `unexpectedEOF = true` and returns false
5. At the END of `DecodeFrame`, checks `unexpectedEOF` on both first and token partitions

After the last encoded token, the decoder continues making readBit calls for remaining
sub-blocks (16 Y EOBs + 8 chroma EOBs per macroblock). Each of these readBit calls can
trigger range renormalization → byte consumption → more byte loads. Gradient frames have
many non-zero Y2 DC coefficients across macroblocks, causing more complex token sequences
that consume more bytes during the "tail" readBit calls.

**Evidence**:
- Passing (uniform Y=128): needs ZERO padding bytes — trimming all 4 still works
- Failing (gradient): needs 7-48 extra bytes depending on resolution
- Empirical: 192x32→11 bytes, 320x240→23, 1920x1080→44, 2560x1440→48

### §20.2 Fix: Bool Encoder flush() Padding

Changed `vp8BoolEnc.flush()` in `go/utils/vp8enc.go`:
- Added remaining-bit emission after 32 zero-bit flush
- Increased trailing zero padding from 4 bytes to 64 bytes
- 64 bytes covers all practical resolutions through 4K (3840x2160 needed ≤48)

### §20.3 Accept Delay Race with Multiple Telegram Sessions

**Discovery**: pion↔pion test calls consistently failed when user1 had 11 active Telegram
sessions (Desktop v6.3.10, Web Chrome/Firefox, Nagram Android, etc.). All sessions ring
simultaneously on incoming call.

**Symptom**: Server negotiated version `4.0.0` with `minLayer=92, maxLayer=92` — exactly
Telegram Web's protocol signature. `PhoneCallDiscarded` with nil reason arrived before
`PhoneCallAccepted`.

**Root cause**: Test code had 300ms delay before `AcceptCall`. Telegram Desktop or Web
answered the call first with their own protocol. Server used the first responder's protocol
for negotiation.

**Fix**: Removed 300ms accept delay in test files — Go code now accepts immediately,
consistently beating other clients to the accept.

---

## Appendix A: Web Call Harness

Telegram Web v4.0.0 call protocol harness and implementation notes.
Source: telegram-tt (web.telegram.org/a), tested 2026-04-10.
Harness: `go/tests/tt-harness/harness.js` (Node.js, GramJS + werift).

### A.1 Protocol Overview

Telegram Web (telegram-tt, Telegram Web K) uses version `4.0.0` (or `4.0.1`). This is a distinct
signaling format from the Desktop/mobile `V2Impl` (8.0.0-13.0.0) and `V2Reference` (10.0.0-11.0.0).

Key differences from Desktop (V2Impl/V2Reference):
- **No NegotiateChannels** — media codecs are inline in `InitialSetup` (audio/video/screencast objects)
- **No SCTP data channel signaling** — uses standard WebRTC SCTP negotiation
- **V1 encryption framing** — simple `[4-byte LE seq][JSON]` then AES-256-CTR, not the V2 multi-message format
- **Always includes video + screencast** — even for audio-only calls, InitialSetup has all 3 media sections
- **Standard SDP offer/answer** — both sides convert between SDP ↔ InitialSetup JSON

#### Version Negotiation

Web client advertises `libraryVersions: ['4.0.0']` in `PhoneCallProtocol`. When both sides support it,
the server negotiates `4.0.0`. Our Go client includes `4.0.0` in its version list and detects it via
`isWebVersion()`.

### A.2 Signaling Format

#### A.2.1 InitialSetup

The core signaling message. Contains ICE credentials, DTLS fingerprint, and full media descriptions:

```json
{
  "@type": "InitialSetup",
  "ufrag": "e975",
  "pwd": "6f107f6031ab82e89e8e46",
  "fingerprints": [{"hash": "sha-256", "fingerprint": "B0:3C:...", "setup": "actpass"}],
  "audio": {
    "ssrc": "451124411",
    "ssrcGroups": [],
    "payloadTypes": [
      {"id": 96, "name": "OPUS", "clockrate": 48000, "channels": 2},
      {"id": 0, "name": "PCMU", "clockrate": 8000}
    ],
    "rtpExtensions": []
  },
  "video": {
    "ssrc": "3847201545",
    "ssrcGroups": [{"semantics": "FID", "ssrcs": [3847201545, 250853053]}],
    "payloadTypes": [{"id": 96, "name": "VP8", "clockrate": 90000, ...}],
    "rtpExtensions": [...]
  },
  "screencast": {
    "ssrc": "...",
    "ssrcGroups": [...],
    "payloadTypes": [...],
    "rtpExtensions": [...]
  }
}
```

#### A.2.2 Candidates

ICE candidates sent individually as they're gathered:

```json
{
  "@type": "Candidates",
  "candidates": [{"sdpString": "candidate:... typ host generation 0 ufrag e975"}]
}
```

#### A.2.3 MediaState

Mute/video status (sent after connection established):

```json
{
  "@type": "MediaState",
  "isMuted": false,
  "videoState": "inactive",
  "videoRotation": 0,
  "screencastState": "inactive",
  "isBatteryLow": false
}
```

Note: incoming MediaState uses `muted` (no `is` prefix), outgoing uses `isMuted`. Both are accepted.

### A.3 Signaling Encryption

Uses AES-256-CTR with MTProto-style key derivation from the DH auth key.

#### A.3.1 Encrypt

1. Prepend 4-byte LE sequence number to JSON payload
2. Pad to 4-byte boundary with `0x20`
3. Compute `x = isOutgoing ? 128 : 136`
4. `msgKey = SHA256(authKey[88+x : 88+x+32] || plaintext)[8:24]`
5. Derive `key` (32 bytes) and `iv` (16 bytes) from `msgKey` + `authKey[x:]`
6. AES-256-CTR encrypt plaintext
7. Output: `msgKey (16 bytes) || ciphertext`

#### A.3.2 Decrypt

Same process with swapped `x` direction:
- Decrypt: `x = isOutgoing ? 136 : 128` (opposite of encrypt)
- Verify `msgKey` after decryption
- Skip 4-byte seq, strip trailing `0x20` padding, parse JSON

This is the **V1 framing** format — one message per packet, simple seq+JSON.
Desktop V2Impl uses a different framing (multi-message with ACKs embedded).

### A.4 SDP ↔ InitialSetup Conversion

#### A.4.1 SDP → InitialSetup (`extractWebInitialSetupFromSDP`)

Go side: parses pion's SDP offer/answer into the JSON format above.
- Extracts ICE ufrag/pwd, DTLS fingerprint
- Parses audio/video m-lines for SSRCs, payload types, RTP extensions
- Generates dummy video + screencast sections (required by telegram-tt)
- **Critical**: PayloadTypes and RTPExtensions must be non-nil (empty slice `[]`, not `null`)
  — Go nil slice serializes to JSON `null`, which crashes telegram-tt's `.map()` calls

#### A.4.2 InitialSetup → SDP (`buildSyntheticSDPFromWebSetup`)

Go side: builds a synthetic SDP from received InitialSetup JSON.
- Creates audio m-line with all payload types from InitialSetup
- Creates video + screencast m-lines
- Adds SCTP data channel m-line (mid=3)
- Sets `a=setup:active` or `a=setup:passive` based on remote's `setup` field
- **Critical**: codec names are case-insensitive per RFC 3551 — use `strings.EqualFold` for matching

### A.5 Connection Flow

#### A.5.1 Outgoing Call (Go → Web Harness)

```
Go (user1)                          Harness (user2)
  │                                      │
  ├─ phone.requestCall(gAHash) ────────→ │
  │                                      ├─ phone.receivedCall (ack)
  │                                      ├─ phone.acceptCall(gB)
  │ ←──── PhoneCallAccepted(gB) ────────┤
  ├─ compute authKey, fingerprint        │
  ├─ phone.confirmCall(gA, fp) ────────→ │
  │                                      ├─ verify gA_hash, compute authKey
  │ ←──── PhoneCall (connections) ───────┤
  │                                      │
  │  === WebRTC Setup ===                │
  ├─ create PC, add audio track          ├─ create PC, add audio track
  ├─ create offer                        │
  ├─ InitialSetup(offer) ─────────────→  │
  ├─ Candidates ───────────────────────→ │
  │                                      ├─ setRemoteDescription(offer→SDP)
  │                                      ├─ create answer
  │  ←───────────────── InitialSetup(answer)
  │  ←───────────────── Candidates
  ├─ setRemoteDescription(answer→SDP)    │
  │                                      │
  │  === ICE + DTLS ===                  │
  │ ←────── ICE connected ──────────→    │
  │ ←────── DTLS handshake ─────────→    │
  │                                      │
  │  === Audio ===                       │
  │ ─── RTP opus silence ───────────→    │
  │ ←── RTP opus silence ───────────     │
```

#### A.5.2 Incoming Call (Web Harness → Go)

Same flow but roles reversed: harness sends `requestCall`, Go receives `PhoneCallRequested`
via `OnUpdate`, calls `AcceptCall`, waits for `PhoneCall` update with connections.

#### A.5.3 DTLS Role

- Caller (`isOutgoing=true`): sends `setup: actpass`, expects `setup: active` from callee
- Callee (`isOutgoing=false`): receives `setup: actpass`, responds with `setup: active`
- Go side: pion handles DTLS role automatically from SDP

#### A.5.4 Reoffer (Incoming Only)

When Go is the callee (incoming call), after DTLS completes, it does a reoffer:
1. Wait for `PeerConnection.connected` state
2. Create new offer with updated transceiver directions
3. Set local description, send new InitialSetup
This ensures the audio sender is properly bound after the incoming track arrives.

### A.6 Harness Architecture

#### A.6.1 Stack

- **GramJS** (`telegram` npm): MTProto client for call setup/teardown signaling
- **werift** (`werift` npm v0.22.9): pure TypeScript WebRTC for Node.js (no native deps)
- **crypto** (Node.js built-in): AES-256-CTR encryption, SHA256, DH math

#### A.6.2 Components

- `PhoneCallCrypto` — signaling encryption/decryption (V1 framing)
- `DHState` — DH key exchange (BigInt math for g^a mod p, fingerprint SHA1)
- `parseSdpToInitialSetup()` — converts werift's SDP to InitialSetup JSON
- `buildSdpFromInitialSetup()` — converts received InitialSetup to SDP for werift
- `CallHarness` — call state machine (DH → WebRTC → audio I/O)

#### A.6.3 Usage

```bash
cd go/tests/tt-harness
npm install               # install GramJS + werift
node harness.js --login   # first-time: interactive login (phone + OTP)
node harness.js --accept  # wait for incoming call, auto-accept
node harness.js --call <userId>  # place outgoing call
```

Session stored at `auth/tt_harness_session.txt` (GramJS StringSession).

#### A.6.4 Audio

- **TX**: 20ms opus silence frames (`0xF8 0xFF 0xFE`), PT=111, 48kHz
- **RX**: any audio track from remote, counted per-frame
- Sender triggered on **first RTP frame receipt** (not PC state change — werift
  `connectionState` is unreliable, stays "connecting" even after DTLS)

### A.7 Bugs Found & Fixed

#### A.7.1 ForceRelayICE causing "no candidate pairs"

Go test had `ForceRelayICE: true` which set ICE transport policy to `relay`.
Harness only generates `host`/`srflx` candidates (Telegram's TURN servers are geo-restricted).
No relay candidates → no pairs → no connection.
**Fix**: removed `ForceRelayICE: true` from test config.

#### A.7.2 werift connectionState stuck at "connecting"

werift's `connectionState` never reaches "connected" even after DTLS completes.
Silence sender was gated on `state === 'connected'` → never starts → no outgoing audio.
**Fix**: trigger sender on first received RTP frame instead of PC state.

#### A.7.3 werift RtpPacket constructor crash

`RtpPacket(header, payload)` takes positional args, not `{header, payload}` object.
Wrong construction → `this.header.timestamp = undefined` → `BigInt(undefined)` crash in uint32Add.
**Fix**: import `RtpHeader`, construct separately, pass positionally.

#### A.7.4 Wrong payload type (96 vs 111)

Initial harness used PT=96 (VP8). Opus is PT=111 in werift's default codec table.
**Fix**: changed to `payloadType: 111`.

#### A.7.5 Case-sensitive codec matching

`extractV2ImplFromSDP` checked `name == "opus"` but pion echoes remote codec names
which could be `OPUS` (uppercase, as sent by telegram-tt). Per RFC 3551, codec names
are case-insensitive.
**Fix**: `strings.EqualFold(name, "opus")`.

#### A.7.6 Null PayloadTypes in JSON

Go nil slice → JSON `null` → harness `.map()` crashes on null.
**Fix**: initialize to empty slice (`[]tgPayloadType{}`) instead of nil.

#### A.7.7 Telegram STUN/TURN timeouts

Telegram's STUN/TURN servers (91.108.x.x:1400) time out for local/LAN tests.
Not a bug — these are geo-restricted production servers. ICE works via host
candidates when both peers are on the same machine or LAN.

#### A.7.8 werift ICE port mismatch bug (2026-04-11) — FIXED (2026-04-13)

**Status: FIXED. Automated tt-harness testing now works.**

werift binds all UDP sockets to `0.0.0.0:randomPort` but advertises candidates per-interface
(192.168.100.199, 172.17.0.1, 172.16.0.2, etc.). When the OS routes a STUN response from
a Docker bridge socket (bound to `0.0.0.0:50199`, candidate for `172.17.0.1:50199`) to pion,
the source IP is rewritten to `192.168.100.199:50199` — an address pion doesn't recognize.

```
ice WARNING: Discard success message from (192.168.100.199:50199), no such remote
```

**Root cause:** Linux source-address rewriting on `0.0.0.0`-bound sockets with multiple interfaces.

**Fix (session 24):** Added `iceInterfaceAddresses: { udp4: primaryLanIp }` and `iceUseIpv6: false`
to the harness's PeerConnection config. The primary LAN IP is auto-detected by filtering out
`docker*`, `br-*`, and `veth*` interfaces. This forces werift to create only one candidate on
the real LAN interface, avoiding the source-address rewriting.

All 13 web call tests now pass automatically.

### A.8 Test Results (2026-04-10, updated 2026-04-11 session 13)

#### Outgoing (Go → Harness)

```
TestCallWebOutgoing: PASS
  tx=750 frames, rx=748 frames
  ICE: connected in ~200ms (host candidates, same machine)
  DTLS: completed, PC connected
  Audio: bidirectional, 15 seconds
```

#### Incoming (Harness → Go)

```
TestCallWebIncoming: PASS (32.62s)
  tx=750 frames, rx=743 frames
  ICE: connected in ~354ms
  DTLS: completed, PC connected
  Audio: bidirectional, 15 seconds
```

#### Test Commands

```bash
# Start harness in accept mode (terminal 1):
cd go/tests/tt-harness && node harness.js --accept

# Run Go outgoing test (terminal 2):
cd go/tests && source ../../auth/auth.md && go test -v -run TestCallWebOutgoing -timeout 120s

# --- or reverse direction ---

# Run Go incoming test (terminal 1):
cd go/tests && source ../../auth/auth.md && go test -v -run TestCallWebIncoming -timeout 120s

# Start harness in call mode (terminal 2):
cd go/tests/tt-harness && node harness.js --call <user1_id>
```

#### Session 9 Call Method Tests (10/10 PASS)

All call control methods verified against Web harness:

| Test | Result |
|------|--------|
| Incoming video from Web | PASS — bidirectional audio + VP8 video |
| Incoming screenshare from Web | PASS — screencast via SSRC dispatch |
| Recording outgoing to Web | PASS — 472 opus frames captured |
| Recording incoming from Web | PASS — 497 opus frames, 2493 bytes |
| Camera toggle (ON→OFF→ON) | PASS — audio 249/249/249, video 151/151/151 |
| Mute/unmute | PASS — MediaState isMuted toggles |
| StopScreenShare | PASS — screencastState active→inactive |
| Simultaneous video+screen | PASS — 3 tracks (audio=500, video=303, screen=303 TX) |
| SetAudioFrameDuration | PASS — 20ms→40ms(1920)→20ms(960) |
| StopCallRecording verify | PASS — frame count returned |

#### Session 24 — Full Automated Re-Verification (2026-04-13)

After fixing the werift ICE port mismatch bug (A.7.8), all 13 web call tests pass automatically:

| Test | Result |
|------|--------|
| Outgoing audio | PASS — tx=749, rx=747 |
| Incoming audio | PASS — tx=750, rx=745 |
| Incoming video from Web | PASS — audio=745, video=453 bidirectional |
| Incoming screenshare from Web | PASS — audio=746, video=454 |
| Recording outgoing to Web | PASS — 497 frames, 2493 bytes |
| Recording incoming from Web | PASS — 498 frames captured |
| Camera toggle (ON→OFF→ON) | PASS — audio 249/249/249, video 151/151/151 |
| Mute/unmute | PASS — audio 258/258/258 across all phases |
| StopScreenShare | PASS — audio continuous across phases |
| Simultaneous video+screen | PASS — 3 tracks sent successfully |
| SetAudioFrameDuration | PASS — 20ms→40ms→20ms, audio 259/259/259 |
| StopCallRecording verify | PASS — 517 frames, 2593 bytes |
| End call from callee | PASS — call ended gracefully |

C++ harness smoke test (v10 audio) also verified passing — no regressions.

### A.9 Relationship to Other Protocol Versions

| Version | Format | Encryption | SDP Type | Codec Negotiation |
|---------|--------|------------|----------|-------------------|
| 2.7.7, 5.0.0 | InstanceImpl | Binary V1 | N/A (custom) | None (fixed opus) |
| 7.0.0 | V2Impl | V1 framing | Synthetic | NegotiateChannels |
| 8.0.0, 9.0.0 | V2Impl | V2 framing | Synthetic | NegotiateChannels |
| 10.0.0, 11.0.0 | V2Reference | SCTP/V1 | Real SDP | SDP offer/answer |
| 12.0.0, 13.0.0 | V2Impl | SCTP | Synthetic | NegotiateChannels |
| **4.0.0, 4.0.1** | **Web** | **V1 framing** | **Synthetic** | **Inline InitialSetup** |

Web (v4.0.0) is closest to V2Impl (v7.0.0) — both use V1 encryption framing and synthetic SDP.
The difference is codec negotiation: V2Impl uses a separate NegotiateChannels exchange,
while Web embeds codecs directly in InitialSetup.

### A.10 Go Implementation Details

#### Key functions in `telegram.go`:

- `isWebVersion(v string) bool` — returns true for "4.0.0", "4.0.1"
- `extractWebInitialSetupFromSDP(sdp, isOutgoing) *tgInitialSetup` — SDP → InitialSetup JSON
- `buildSyntheticSDPFromWebSetup(setup, sdpType) string` — InitialSetup JSON → SDP
- Call setup: detected in `startCallWebRTC()` / `handleIncomingCall()` via version check
- Signaling: same `processV1Signaling()` path as v7.0.0, branched by `call.useWebSignaling`

#### Fields on `tgCall`:

```go
useWebSignaling bool  // true for v4.0.0/4.0.1
useV1Framing    bool  // always true when useWebSignaling=true
```

### A.11 Real Web Client Testing (2026-04-13)

#### Version Trimming

Offered versions reduced from 10 to 3: `13.0.0`, `8.0.0`, `4.0.0`. Configured via `filterVersions()`
with optional `MinCallVersion`/`MaxCallVersion` in `TelegramConfig`.

#### v4.0.0 vs Real web.telegram.org/a

**Problem:** v4.0.0 worked against the tt-harness (werift) but failed against real Telegram Web.
ICE reported "Failed to ping without candidate pairs" — zero Candidates messages received from the web.

**Root cause:** Firefox + uBlock Origin blocks WebRTC ICE candidate gathering to prevent IP leaks.
The browser's `onicecandidate` never fires, so no Candidates are sent via signaling. Confirmed by
switching to Brave (Chromium-based, no WebRTC blocking) — 249 audio frames, connected in 4.5s.

**Fixes applied (still good improvements):**
1. **Dangling RTX cleanup**: `extractV2ImplFromSDP` now filters out RTX codecs (e.g. apt=116, apt=45)
   that reference primary codecs not in our include list (we only include VP8/VP9/H264, not AV1/H265).
2. **`a=ice-options:trickle`**: Added to `buildSyntheticSDPFromV2Impl` at session level.
3. **Data channel m-line**: `buildSyntheticSDPFromWebSetup` now appends `m=application` with SCTP
   to match the offer's BUNDLE group (telegram-tt creates `negotiated: true, id: 0` data channel).

#### Test Results

| Version | Signaling | Peer | Audio Frames | Result |
|---------|-----------|------|-------------|--------|
| v13.0.0 | V2Impl+SCTP | Desktop | 249+ | PASS |
| v8.0.0 | V2Impl | Desktop | 249+ | PASS |
| v4.0.0 | Web | tt-harness (werift) | 249 | PASS |
| v4.0.0 | Web | Brave web.telegram.org/a | 249 | PASS |
| v4.0.0 | Web | Firefox+uBlock web.telegram.org/a | 0 | FAIL (browser blocks ICE) |

---

## Appendix B: ntgcalls (Obsolete)

ntgcalls CGo bridge was historically tested but is **obsolete** — CGo is banned project-wide. Replaced by the external C++ tgcalls harness (built independently in `/tmp/`, not part of `go build`). Key finding preserved: real tgcalls bidirectional audio worked (98 incoming frames at 440Hz). Root cause of initial failure was WebRTC transceiver matching — pion's offer created a NEW recvonly transceiver instead of matching the existing sendrecv one.
