# Video decode status re-verification (2026-09-16)

Re-ran the pure-Go video decode research (previous pass: 2026-09-11, verdict
"blocked"). Primary sources: GitHub API (repos/releases/commits), the Go
module proxy, pkg.go.dev, local shallow clones of the candidates for API +
LOC inspection.

## Findings

### H.264/AVC (round videos) — UNBLOCKED 2026-09-23 (was "STILL BLOCKED")
Re-researched after both earlier passes failed to surface `liqMix/govid`
(a from-scratch pure-Go H.264 decoder with I/P/B + CABAC, present since
2026-03-14). Verified bit-exact vs ffmpeg on our own fixtures — see
`h264_decoder.md` and `go/h264vid`. Survey of the candidates both earlier
passes DID find, kept for the record:
- **Eyevinn/hi264** — releases v0.9.0 (2026-02-17), v0.10.0 (2026-05-08);
  README: "The decoder handles IDR plus P_Skip frames; full P/B-frame
  decoding is out of scope." Encoder/SEI-side work only.
- **mgvs/go-openh264** (2026-06, v0.1.2) — pure-Go High-profile intra,
  but "P-slice / B-slice (inter prediction) — out of scope" (thumbnail).
- gomedia dormant since 2024; the rest are cgo.
→ In-app H.264 playback ships through `go/h264vid` (was: system-player
handoff, slice 86).

### VP9 (video stickers + video emoji) — UNBLOCKED
Two new pure-Go VP9 decoders, both appeared May–June 2026:

| | mgvs/go-vp9 v0.2.0 | thesyncim/govpx (unreleased) |
|---|---|---|
| Size | 18k LOC, 76 files | 437k LOC, 1727 files (libvpx port) |
| Release | tagged v0.2.0 on proxy | pseudo-version only |
| Verification | bit-exact vs libvpx on real streams: key+inter, multi-tile 1272×720, 90-frame alt-ref/compound superframes, 10/12-bit profile 2 | full official VP9 conformance corpus in CI, byte-for-byte vs libvpx 1.16 |
| Profile 0 (8-bit 4:2:0 — what Telegram stickers use) | fully verified | fully verified |
| Threading | single | row-MT + threaded loop filter |
| License | BSD-2 | BSD-3 (+libvpx patent notice) |
| Author | single, LLM-assisted, 0★ | single, 0★ |

**Choice: mgvs/go-vp9 v0.2.0.** Tagged (stable pin), 18k LOC (auditable),
bit-exact on exactly the feature set Telegram sticker streams exercise
(Profile 0 key+inter+alt-ref superframes). govpx's conformance corpus is
stronger evidence but 437k LOC from one author with no tag is a bigger blast
radius; revisit if it tags a release. Risk mitigation: our own end-to-end
test pins demux→decode→RGBA against a real VP9 WebM vector committed as
testdata, and a decode-through test over every frame.

Supporting facts:
- `frame.Parse` (exported) gives Profile/ColorSpace/ColorRange/BitDepth —
  lets the player reject profile 2/3 10/12-bit before decode and pick the
  right YUV→RGB matrix (BT.601 studio default; sRGB full-range when
  signaled; VP9 CS_UNKNOWN treated as BT.601 — the historical web default).
- `decoder.New().DecodeFrame(payload) (*refbuf.Frame, error)` — Frame is
  planar 4:2:0 with 96px replicated borders + strides; sequential decode
  required (inter frames reference prior frames); loops restart at frame 0.
- WebM demux: ebml-go v0.19.2 is pure Go but writer-centric; the reader
  (Unmarshal into tagged structs) is workable yet awkward for our scoped
  need (one VP9 video track, ≤ a few seconds, no streaming). A focused
  in-repo EBML reader (~400 lines: varints, element walk, Tracks, Cluster,
  SimpleBlock/Block with all three lacing modes, TimecodeScale) keeps the
  new-dependency surface at exactly one (the decoder) and is fully
  unit-testable with hand-built fixtures.

### Other
- x/image still has no vp9 (v0.46.0, 2026-09-08). Pion: packetizers only,
  no decoder. No pure-Go HW-decode-via-syscall projects (D3D11VA/VAAPI).
- Gray-zone escape hatches (ffmpeg.wasm on wazero, purego dlopen of
  libav*) all violate the 100% Go constitution — rejected.

## Slice 216 plan (rating + architecture)

Rating of existing surface: **tgsPlayer pattern 9/10** (per-message player
cache with async one-time parse + frame clock + tap replay + power-saving
static frame + wholesale-pruned cache — exactly the right shape). Extend,
never replace. The video-sticker path (stickerKindWebm) and emoji
classifyEmojiArt "unsupported" slot are the seams.

Plan:
1. `go/webm/` — minimal pure-Go EBML/WebM reader (tests first, hand-built
   fixtures): varint edge cases, element tree walk, VP9 video-track
   discovery (codec V_VP9, dimensions, DefaultDuration), Cluster
   Timecode+SimpleBlock/Block frame extraction incl. all three lacing modes,
   TimecodeScale→ns math, graceful unknown-size handling.
2. `go/vp9anim/` — pure decode+player library (no gio): Parse (demux +
   profile/color validation, frame timeline), Player with a background
   sequential producer (global decode semaphore, idle slot release),
   YUV→RGBA (colorimetry from frame.Parse header), bounded frame ring,
   FrameAt(elapsed) pure timeline math (unit-tested), loop restart.
3. gui wiring: stickerKindWebm renders through the player (clock pattern
   identical to tgs); emojifile.go gains emojiArtVideo for video/webm
   documents (shared per-document player, inline box 1.35×font); reaction
   pills inherit via the same artwork cache.
4. Acceptance: real VP9 WebM testdata vector pinned end-to-end (frame
   count, dims, duration, first-frame RGBA checksum) + decode-through-all
   test; CI verify dispatch; parity rows 146/147 updated.
