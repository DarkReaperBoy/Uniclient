# ntgcalls Test Harness — Findings (2026-04-07)

> **OBSOLETE (2026-04-11):** ntgcalls CGo bridge is no longer used. Replaced by the external C++
> tgcalls harness (`/tmp/tgcalls_build/libtgcalls_native.so`) which supports all 9 protocol versions
> and is NOT linked into Go (lives outside the repo, called via build-tagged CGo test files only).
> CGo is banned project-wide per the zero-CGo rule. This document is preserved for historical
> reference — the debugging methodology and protocol findings are still valuable.
> See: `checklist/telegram.md` (Sessions 5-14), `research/tgcalls_protocol.md` (§15-17).

## Setup
- User1 (our pion code) calls User2 (real tgcalls via ntgcalls 2.1.0)
- Both use gotd/td for MTProto signaling
- ntgcalls linked as prebuilt .so (111MB, includes Google's libwebrtc)
- Hybrid signaling bridge: pion→ntgcalls via MTProto, ntgcalls→pion direct in-process

## What Works
1. **ntgcalls loads and initializes** — version 2.1.0, supports protocol versions [8.0.0, 9.0.0]
2. **DH key exchange** — auth_key passed via `ntg_skip_exchange`, verified fingerprint match
3. **Signaling encryption/decryption** — bidirectional, V2 format, ntgcalls decrypts our messages correctly
4. **ICE connection** — host candidates connect in ~800ms-1.8s on same machine
5. **DTLS handshake completes on ntgcalls side** — "DTLS handshake complete", SRTP activated with AES_CM_128_HMAC_SHA1_80
6. **NegotiateChannels exchange** — both sides exchange and answer codec offers

## What Doesn't Work Yet
1. **Pion DTLS doesn't start** — PeerConnectionState=connected but DTLS transport never starts handshake
   - No pion DTLS logs even at Info level
   - `dtls=unknown` in transport stats permanently
   - `outRTP=0, inRTP=0` — SRTP silently drops all WriteRTP calls
   - ntgcalls' DTLS completes but pion's doesn't — one-sided handshake?

2. **NegotiateChannels echo causes ntgcalls crash** — FIXED by only echoing opus audio codec instead of full codec list

3. **Signaling bridge latency** — MTProto relay adds 5-10 seconds; solved with direct in-process bridge for ntgcalls→pion direction

## Key Bugs Found & Fixed
1. `buildRemoteSDP` only had 1 m-line (audio) but offer has 3 → added all 3 m-lines
2. NegotiateChannels answer echoed full codec list (4KB+) → trimmed to opus-only
3. DTLS `a=setup` role: confirmed correct after analysis (pion inverts remote role in `role()`)
4. **Silence sender yield bug (2026-04-07)** — `onAudioFrame` (incoming audio callback) was treated as signal to stop sending silence. When test set `onAudioFrame` to receive audio, silence sender yielded and sent ZERO packets. Fixed: silence sender always runs.
5. **NegotiateChannels SSRC mismatch (2026-04-07)** — Answer echoed remote SSRC instead of our own. Fixed: uses `call.audioSSRC`.
6. **`call.audioSSRC` not synced with SDP (2026-04-07)** — Randomly generated `call.audioSSRC` wasn't updated to match pion's actual SDP SSRC. Caused SSRC mismatch between signaling and RTP. Fixed: `call.audioSSRC = sdpSSRC` after offer creation.

## DTLS Status (Updated 2026-04-07)

DTLS actually works! The "DTLS never starts" diagnosis was wrong — DTLS completes in ~200ms after ICE connects. The `dtls=unknown` in stats was because `TransportStats` isn't populated by pion. Direct `OnStateChange` callback confirms: new→connecting→connected.

## pion↔pion Two-User Test: PASS (2026-04-07)

After fixing bugs 4-6: **1027 bidirectional audio frames** confirmed. TestTwoUserCallAudio passes.

## RTP Demux Issue (affects ntgcalls AND Desktop)

Both ntgcalls and Desktop cannot demux our RTP packets despite SRTP working:
- ntgcalls: `rtp_transport.cc:230: Failed to demux RTP packet: PT=111 SSRC=X`
- Desktop: no incoming audio, no OnTrack, despite completed signaling + DTLS

**Root cause: pion↔tgcalls architectural mismatch.** See `docs/tgcalls_protocol.md` §9.15.

tgcalls' libwebrtc uses MID RTP header extension for BUNDLE demux. Pion doesn't negotiate MID
because our synthetic SDP doesn't include it. Without MID, libwebrtc falls back to SSRC matching
but doesn't register SSRCs from NegotiateChannels into its demuxer. This is a fundamental issue
with the synthetic SDP approach — not solvable without reimplementing tgcalls' internal session setup.

**Previous decision was to switch to ntgcalls native.** But V2Reference breakthrough (§9.15) made this unnecessary — pure Go/pion works with version 10.0.0.

## V2Reference Update (2026-04-07)

**RTP demux issue is SOLVED** by using InstanceV2ReferenceImpl (version 10.0.0) which uses standard WebRTC SDP offer/answer. No synthetic SDP needed. pion↔pion works perfectly with 200+ bidirectional RTP frames.

**ntgcalls 2.1.0 is incompatible with V2Reference:**
- ntgcalls only supports versions [8.0.0, 9.0.0] (InstanceV2Impl)
- Server requires 10.0.0 in version list → always negotiates 10.0.0
- ntgcalls receives our SDP offer but can't parse it (InstanceV2Impl expects InitialSetup+NegotiateChannels)
- Dual-mode signaling was attempted (detect negotiated version, branch to V2Impl or V2Reference) but reverted because server won't negotiate 9.0.0 without 10.0.0 in the list
- `CALL_PROTOCOL_COMPAT_LAYER_INVALID` (error 406) returned when version list doesn't include 10.0.0+

**ntgcalls bridge was tested historically** — CGo bindings loaded ntgcalls 2.1.0, CreateP2P/SkipExchange/ConnectP2P all functioned. Build tag `ntgcalls` isolated the CGo dependency. **NOTE (2026-04-11): CGo is now banned project-wide (CGO_ENABLED=0). The ntgcalls bridge is obsolete — replaced by the external C++ tgcalls harness (built in /tmp/, not part of `go build`).**

## Real tgcalls Bidirectional Audio — WORKING (2026-04-08)

**Test**: `TestPionVsRealTgcalls` (build tag `real_tgcalls`)  
**Result**: 98 incoming audio frames (440Hz sine from real tgcalls C++ → pion, opus-encoded RTP)

### Root cause: WebRTC transceiver matching bug

When real tgcalls (callee, `isOutgoing=false`) receives pion's SDP offer via `SetRemoteDescription`:
1. The PeerConnection creates a NEW `recvonly` transceiver for the offer's audio m-line (mid=0)
2. The existing `sendrecv` transceiver (added in constructor) remains unmatched (no mid)
3. The answer gets `a=recvonly` for mid=0 → no `AudioSendStream` → no outgoing audio

The Unified Plan matching algorithm SHOULD reuse the existing transceiver, but doesn't. This appears to be a webrtc bug (or an edge case in how tgcalls creates transceivers before receiving the offer).

### Fix (in InstanceV2ReferenceImpl.cpp)

After `SetRemoteDescription(offer)` completes, before creating the answer:
```cpp
// Find auto-created recvonly transceiver and upgrade to sendrecv
for (auto& t : transceivers) {
    if (t->media_type() == AUDIO && t->direction() == kRecvOnly && t->mid()) {
        if (_outgoingAudioTrack && !_outgoingAudioTransceiver->mid()) {
            t->sender()->SetTrack(_outgoingAudioTrack.get());
            t->SetDirectionWithError(kSendRecv);
            break;
        }
    }
}
```

### Other fixes in this session

1. **Signaling buffer race**: Set interceptor BEFORE call accept to buffer SCTP packets. Flush to real tgcalls after creation.
2. **ADM async creation**: `Meta::Create` returns before `start()` runs (async on media thread). `ForceStartRecording` must retry until ADM is available.
3. **RecordingIsAvailable**: `AudioDeviceModuleDefault::RecordingIsAvailable` doesn't set the output bool. Fixed in `LoggingADMWrapper`.

## V2 Signaling ACK Issue

Desktop keeps resending all signaling (InitialSetup, Candidates, NegotiateChannels) because we
never send ACKs. The V2 ACK format embeds `[counter][0xFF]` entries in outgoing packets.
Attempted implementation broke V2 framing (byte order wrong). Reverted.

When switching to ntgcalls, this becomes moot — ntgcalls handles V2 signaling internally.

### Files Created/Modified
- `go/tests/ntgcalls_bridge.go` — CGo bindings for ntgcalls (NtgInstance, PollSignaling, etc.)
- `go/tests/ntgcalls_harness_test.go` — Test: TestNtgCallsLoad, TestPionVsNtgcalls
- `go/cores/telegram.go` — Added test helpers:
  - `TestSetSignalingInInterceptor/OutInterceptor` — intercept raw signaling
  - `TestSendRawSignaling` — send raw encrypted signaling via MTProto
  - `TestAcceptCallRaw` — accept call with skipWebRTC (DH only)
  - `TestGetCallInfo` — get auth key + connections
  - `TestHandleSignalingData` — inject signaling directly
  - `tgCall.skipWebRTC/connections/protocol/dhDone` — new fields for test harness
- `docs/ntgcalls_test_findings.md` — this file

### How to Run
```bash
cd go/tests
GCC_LIB="/nix/store/ab3753m6i7isgvzphlar0a8xb84gl96i-gcc-15.2.0-lib/lib"
LD_LIBRARY_PATH="/tmp/ntgcalls/lib:$GCC_LIB:/nix/store/2kdz3m7ic8w226pcvkz1dlg169v91p6a-zlib-1.3.2/lib" \
CGO_ENABLED=1 go test -v -run TestPionVsNtgcalls -timeout 90s
```
ntgcalls .so is at `/tmp/ntgcalls/lib/libntgcalls.so`, header at `/tmp/ntgcalls/include/ntgcalls.h`.
Downloaded from: `https://github.com/pytgcalls/ntgcalls/releases/download/v2.1.0/ntgcalls.linux-x86_64-shared_libs.zip`
