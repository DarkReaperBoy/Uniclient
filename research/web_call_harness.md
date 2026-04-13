# Telegram Web v4.0.0 Call Protocol — Harness & Implementation Notes

Source: telegram-tt (web.telegram.org/a), tested 2026-04-10.
Harness: `go/tests/tt-harness/harness.js` (Node.js, GramJS + werift).

---

## 1. Protocol Overview

Telegram Web (telegram-tt, Telegram Web K) uses version `4.0.0` (or `4.0.1`). This is a distinct
signaling format from the Desktop/mobile `V2Impl` (8.0.0-13.0.0) and `V2Reference` (10.0.0-11.0.0).

Key differences from Desktop (V2Impl/V2Reference):
- **No NegotiateChannels** — media codecs are inline in `InitialSetup` (audio/video/screencast objects)
- **No SCTP data channel signaling** — uses standard WebRTC SCTP negotiation
- **V1 encryption framing** — simple `[4-byte LE seq][JSON]` then AES-256-CTR, not the V2 multi-message format
- **Always includes video + screencast** — even for audio-only calls, InitialSetup has all 3 media sections
- **Standard SDP offer/answer** — both sides convert between SDP ↔ InitialSetup JSON

### Version Negotiation

Web client advertises `libraryVersions: ['4.0.0']` in `PhoneCallProtocol`. When both sides support it,
the server negotiates `4.0.0`. Our Go client includes `4.0.0` in its version list and detects it via
`isWebVersion()`.

---

## 2. Signaling Format

### 2.1 InitialSetup

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

### 2.2 Candidates

ICE candidates sent individually as they're gathered:

```json
{
  "@type": "Candidates",
  "candidates": [{"sdpString": "candidate:... typ host generation 0 ufrag e975"}]
}
```

### 2.3 MediaState

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

---

## 3. Signaling Encryption

Uses AES-256-CTR with MTProto-style key derivation from the DH auth key.

### 3.1 Encrypt

1. Prepend 4-byte LE sequence number to JSON payload
2. Pad to 4-byte boundary with `0x20`
3. Compute `x = isOutgoing ? 128 : 136`
4. `msgKey = SHA256(authKey[88+x : 88+x+32] || plaintext)[8:24]`
5. Derive `key` (32 bytes) and `iv` (16 bytes) from `msgKey` + `authKey[x:]`
6. AES-256-CTR encrypt plaintext
7. Output: `msgKey (16 bytes) || ciphertext`

### 3.2 Decrypt

Same process with swapped `x` direction:
- Decrypt: `x = isOutgoing ? 136 : 128` (opposite of encrypt)
- Verify `msgKey` after decryption
- Skip 4-byte seq, strip trailing `0x20` padding, parse JSON

This is the **V1 framing** format — one message per packet, simple seq+JSON.
Desktop V2Impl uses a different framing (multi-message with ACKs embedded).

---

## 4. SDP ↔ InitialSetup Conversion

### 4.1 SDP → InitialSetup (`extractWebInitialSetupFromSDP`)

Go side: parses pion's SDP offer/answer into the JSON format above.
- Extracts ICE ufrag/pwd, DTLS fingerprint
- Parses audio/video m-lines for SSRCs, payload types, RTP extensions
- Generates dummy video + screencast sections (required by telegram-tt)
- **Critical**: PayloadTypes and RTPExtensions must be non-nil (empty slice `[]`, not `null`)
  — Go nil slice serializes to JSON `null`, which crashes telegram-tt's `.map()` calls

### 4.2 InitialSetup → SDP (`buildSyntheticSDPFromWebSetup`)

Go side: builds a synthetic SDP from received InitialSetup JSON.
- Creates audio m-line with all payload types from InitialSetup
- Creates video + screencast m-lines
- Adds SCTP data channel m-line (mid=3)
- Sets `a=setup:active` or `a=setup:passive` based on remote's `setup` field
- **Critical**: codec names are case-insensitive per RFC 3551 — use `strings.EqualFold` for matching

---

## 5. Connection Flow

### 5.1 Outgoing Call (Go → Web Harness)

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

### 5.2 Incoming Call (Web Harness → Go)

Same flow but roles reversed: harness sends `requestCall`, Go receives `PhoneCallRequested`
via `OnUpdate`, calls `AcceptCall`, waits for `PhoneCall` update with connections.

### 5.3 DTLS Role

- Caller (`isOutgoing=true`): sends `setup: actpass`, expects `setup: active` from callee
- Callee (`isOutgoing=false`): receives `setup: actpass`, responds with `setup: active`
- Go side: pion handles DTLS role automatically from SDP

### 5.4 Reoffer (Incoming Only)

When Go is the callee (incoming call), after DTLS completes, it does a reoffer:
1. Wait for `PeerConnection.connected` state
2. Create new offer with updated transceiver directions
3. Set local description, send new InitialSetup
This ensures the audio sender is properly bound after the incoming track arrives.

---

## 6. Harness Architecture

### 6.1 Stack

- **GramJS** (`telegram` npm): MTProto client for call setup/teardown signaling
- **werift** (`werift` npm v0.22.9): pure TypeScript WebRTC for Node.js (no native deps)
- **crypto** (Node.js built-in): AES-256-CTR encryption, SHA256, DH math

### 6.2 Components

- `PhoneCallCrypto` — signaling encryption/decryption (V1 framing)
- `DHState` — DH key exchange (BigInt math for g^a mod p, fingerprint SHA1)
- `parseSdpToInitialSetup()` — converts werift's SDP to InitialSetup JSON
- `buildSdpFromInitialSetup()` — converts received InitialSetup to SDP for werift
- `CallHarness` — call state machine (DH → WebRTC → audio I/O)

### 6.3 Usage

```bash
cd go/tests/tt-harness
npm install               # install GramJS + werift
node harness.js --login   # first-time: interactive login (phone + OTP)
node harness.js --accept  # wait for incoming call, auto-accept
node harness.js --call <userId>  # place outgoing call
```

Session stored at `auth/tt_harness_session.txt` (GramJS StringSession).

### 6.4 Audio

- **TX**: 20ms opus silence frames (`0xF8 0xFF 0xFE`), PT=111, 48kHz
- **RX**: any audio track from remote, counted per-frame
- Sender triggered on **first RTP frame receipt** (not PC state change — werift
  `connectionState` is unreliable, stays "connecting" even after DTLS)

---

## 7. Bugs Found & Fixed

### 7.1 ForceRelayICE causing "no candidate pairs"

Go test had `ForceRelayICE: true` which set ICE transport policy to `relay`.
Harness only generates `host`/`srflx` candidates (Telegram's TURN servers are geo-restricted).
No relay candidates → no pairs → no connection.
**Fix**: removed `ForceRelayICE: true` from test config.

### 7.2 werift connectionState stuck at "connecting"

werift's `connectionState` never reaches "connected" even after DTLS completes.
Silence sender was gated on `state === 'connected'` → never starts → no outgoing audio.
**Fix**: trigger sender on first received RTP frame instead of PC state.

### 7.3 werift RtpPacket constructor crash

`RtpPacket(header, payload)` takes positional args, not `{header, payload}` object.
Wrong construction → `this.header.timestamp = undefined` → `BigInt(undefined)` crash in uint32Add.
**Fix**: import `RtpHeader`, construct separately, pass positionally.

### 7.4 Wrong payload type (96 vs 111)

Initial harness used PT=96 (VP8). Opus is PT=111 in werift's default codec table.
**Fix**: changed to `payloadType: 111`.

### 7.5 Case-sensitive codec matching

`extractV2ImplFromSDP` checked `name == "opus"` but pion echoes remote codec names
which could be `OPUS` (uppercase, as sent by telegram-tt). Per RFC 3551, codec names
are case-insensitive.
**Fix**: `strings.EqualFold(name, "opus")`.

### 7.6 Null PayloadTypes in JSON

Go nil slice → JSON `null` → harness `.map()` crashes on null.
**Fix**: initialize to empty slice (`[]tgPayloadType{}`) instead of nil.

### 7.7 Telegram STUN/TURN timeouts

Telegram's STUN/TURN servers (91.108.x.x:1400) time out for local/LAN tests.
Not a bug — these are geo-restricted production servers. ICE works via host
candidates when both peers are on the same machine or LAN.

### 7.8 werift ICE port mismatch bug (2026-04-11) — FIXED (2026-04-13)

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

---

## 8. Test Results (2026-04-10, updated 2026-04-11 session 13)

### Outgoing (Go → Harness)

```
TestCallWebOutgoing: PASS
  tx=750 frames, rx=748 frames
  ICE: connected in ~200ms (host candidates, same machine)
  DTLS: completed, PC connected
  Audio: bidirectional, 15 seconds
```

### Incoming (Harness → Go)

```
TestCallWebIncoming: PASS (32.62s)
  tx=750 frames, rx=743 frames
  ICE: connected in ~354ms
  DTLS: completed, PC connected
  Audio: bidirectional, 15 seconds
```

### Test Commands

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

### Session 9 Call Method Tests (10/10 PASS)

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

### Session 24 — Full Automated Re-Verification (2026-04-13)

After fixing the werift ICE port mismatch bug (§7.8), all 13 web call tests pass automatically:

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

---

## 9. Relationship to Other Protocol Versions

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

---

## 10. Go Implementation Details

### Key functions in `telegram.go`:

- `isWebVersion(v string) bool` — returns true for "4.0.0", "4.0.1"
- `extractWebInitialSetupFromSDP(sdp, isOutgoing) *tgInitialSetup` — SDP → InitialSetup JSON
- `buildSyntheticSDPFromWebSetup(setup, sdpType) string` — InitialSetup JSON → SDP
- Call setup: detected in `startCallWebRTC()` / `handleIncomingCall()` via version check
- Signaling: same `processV1Signaling()` path as v7.0.0, branched by `call.useWebSignaling`

### Fields on `tgCall`:

```go
useWebSignaling bool  // true for v4.0.0/4.0.1
useV1Framing    bool  // always true when useWebSignaling=true
```

---

## 11. Real Web Client Testing (2026-04-13)

### Version Trimming

Offered versions reduced from 10 to 3: `13.0.0`, `8.0.0`, `4.0.0`. Configured via `filterVersions()`
with optional `MinCallVersion`/`MaxCallVersion` in `TelegramConfig`.

### v4.0.0 vs Real web.telegram.org/a

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

### Test Results

| Version | Signaling | Peer | Audio Frames | Result |
|---------|-----------|------|-------------|--------|
| v13.0.0 | V2Impl+SCTP | Desktop | 249+ | PASS |
| v8.0.0 | V2Impl | Desktop | 249+ | PASS |
| v4.0.0 | Web | tt-harness (werift) | 249 | PASS |
| v4.0.0 | Web | Brave web.telegram.org/a | 249 | PASS |
| v4.0.0 | Web | Firefox+uBlock web.telegram.org/a | 0 | FAIL (browser blocks ICE) |
