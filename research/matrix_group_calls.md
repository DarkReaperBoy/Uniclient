# Matrix group calls (BUGS B-6) — research for the owner decision

Status: **not implemented** — `MatrixCore.JoinGroupCall` returns honest
`ErrNotSupported` (`go/cores/matrix.go:1241`). Nothing below is built;
this file exists so the owner's go/no-go is an informed choice.
Per AGENTS: research files are inputs, not authoritative — every claim
here carries its source, and implementation must re-verify.

Date: 2026-09-25. Sources: primary MSC/spec pages + local code greps
(this session), URLs listed at the bottom.

## What "group calls" means on Matrix today (primary sources)

1. **MSC3401 signalling core**
   - The initiator sends an **`m.call` state event** into the room
     (timeline placeholder: call happening, duration, termination).
   - Each participant declares membership with an **`m.call.member`
     state event whose state_key is their Matrix ID** (nobody else can
     edit it). Content = `m.calls[]`, one item, with:
     `m.call_id`, `m.foci[]` (SFU/focus hints), `m.devices[]` — each
     device: `device_id` (to-device target), `session_id` (stale-
     session resolution, regenerated per app load), `expires_ts`
     (POSIX ms; must be renewed while connected; expired devices are
     ignored), `feeds[]` (`purpose` = `m.usermedia`/`m.screenshare`,
     stream/track ids, `settings` incl. `m.maxbr`).
   - **Call setup messages are the familiar `m.call.*` events but sent
     over to-device (Olm-encrypted)**, extended with `conf_id`,
     `dest_session_id`, `seq` (to-device order is not guaranteed;
     `seq` starts at 0 and increments). `m.call.invite` additionally
     carries `device_id` + `sender_session_id` (+ `m.intent` for
     early ringing).
   - SFU-specific signalling was **split out of MSC3401 into MSC3898**
     (the MSC's own note).
2. **The production ecosystem moved on to MatrixRTC**
   - Element Call runs on **MatrixRTC (MSC4143)** with a **LiveKit SFU
     backend (MSC4195)**; transports are discovered via the CS-API
     endpoint `GET /_matrix/client/unstable/org.matrix.msc4143/rtc/transports`;
     participants propose their discovered focus in
     `org.matrix.msc3401.call.member` (`foci_preferred` decides the
     backend for the call); the MatrixRTC Authorization Service hands
     out the **LiveKit SFU WebSocket URL + access JWT**.
   - "Native P2P Group Calling MSC3401" (full-mesh) and "Group Calling
     Using SFU Backend for Scaling" are both presented as live options
     in Element's 2025 matrix.org conference slides; pluggable RTC
     transports: `full_mesh` (MSC3401) and `livekit` (MSC4195).
   - **matrix-js-sdk ships `src/webrtc/groupCall.ts`** — the reference
     client implementation of the full-mesh/`m.calls` membership model
     (participant expiry loop, device/session validation).
3. **mautrix-go (our pinned v0.30.0): ZERO group-call code.** Verified
   by grep over the module cache this session: no `MSC3401`,
   `m.call.member`, `GroupCall`, no call/voip/experimental package.
   Everything would be OUR code (the1:1 stack in `cores/matrix.go` is
   already ours on top of `uniclient/wrtc`).

## What we already have (local, verified)

- **1:1 calls fully wired** in `cores/matrix.go`: StartCall/ AcceptCall/
  RejectCall/ EndCall, `m.call.invite`/`answer`/`candidates`/`hangup`
  over `SendMessageEvent`, ICE plumbing, `handleIncomingAudio`/
  `sendAudio` loops, `createPeerConnection` on our `uniclient/wrtc`
  (pion fork), mute/camera stubs where unsupported.
- **Generic group-call plumbing already exists**: engine
  `GetGroupCall(account, chat) → GroupCallInfo` (Meta-driven), GUI
  call bar + callsbox consume it today for TeamSpeak/Mumble — Matrix
  returning a real `CallSession` would light most of that UI up.
- **E2EE capability exists**: mautrix crypto (olm/megolm) is in use for
  encrypted rooms, so Olm to-device call signalling is feasible.
- Existing tests: gui label/stamp/subtitle tests for calls; the new
  matrix unit suite (slice 248) shows the pattern for scripted-event
  tests of this core.

## The gap (what building B-6 actually costs)

**Tier 1 — MSC3401 full-mesh group call (no external server):**
- `m.call` + `m.call.member` state machine (device/session/expires_ts
  renewal loop), Olm to-device `m.call.*` with `conf_id`/
  `dest_session_id`/`seq`, mesh SDP fan-out (N×(N−1) peer connections
  via our wrtc), audio mixing through the existing `voice` package,
  join/leave/expiry handling, GUI wiring to the existing GroupCallInfo.
- **Interop**: only with other MSC3401 full-mesh clients (matrix-js-sdk
  reference); Element's modern default is Element Call/MatrixRTC, so
  Tier1 calls would NOT show up in Element without their legacy path.
- **Testable without infra**: scripted-event unit tests + a live test
  with 2–3 accounts on one homeserver. Accounts = the blocker
  (matrix.org needs email; alternatives: self-hosted Conduit/Synapse —
  Conduit is a single Go-free… no: single Rust binary — or an existing
  open-registration server).

**Tier 2 — SFU via MatrixRTC/Element Call (LiveKit):**
- Everything in Tier1's signalling surface PLUS transport discovery
  endpoint, foci/`foci_preferred` handling, MatrixRTC Auth (JWT) flow,
  LiveKit WebSocket media, slot/sticky-event extensions as needed —
- PLUS **infrastructure**: a LiveKit SFU deployment (livekit server is
  Go, but it is still a service to run + a MatrixRTC auth service),
  and Element Call's widget for the other participants' side.
- **Effectively untestable in the current environment** (no docker on
  this host, no SFU, two-sided widget stack).

**Status quo**: honest `ErrNotSupported` (the row's original
assessment stands — no user-facing dead UI, the call buttons for Matrix
report the gap properly).

## Decision points for the owner

1. **Tier1, Tier2, or status quo?** Tier1 = weeks of slices + live
   testing needs multi-account homeserver provisioning; Tier2 = Tier1
   + external infra + Element-Call interop story (the only variant
   Element users would actually hear); status quo = zero cost, gap is
   honest today.
2. If Tier1+: provision test accounts (email-based or self-hosted
   homeserver) — same class as the other live-test blockers.
3. If Element interop matters → Tier2 makes Tier1 alone insufficient.

## Sources

- MSC3401 proposal (github.com/matrix-org/matrix-doc,
  proposals/3401-group-voip.md) — membership/to-device mechanics quoted
  above.
- matrix-js-sdk `src/webrtc/groupCall.ts` — reference membership loop.
- element-hq/element-call README — MatrixRTC (MSC4143) + LiveKit
  (MSC4195), transports endpoint, `foci_preferred`, JWT from the
  MatrixRTC Authorization Service.
- 2025.matrix.org slides "Element Call — The Matrix Conference" —
  full_mesh vs LiveKit transports, MSC4196/4075 context.
- Local: `go/cores/matrix.go` (1:1 stack + ErrNotSupported site),
  module-cache grep of mautrix v0.30.0, engine/gui group-call plumbing.
