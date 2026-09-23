# In-app video player — pure-Go decoder research (2026-09-11)

Verdict (updated 2026-09-23): **H.264 UNBLOCKED — see `h264_decoder.md`.**

govpx ships the VP9 side (slice 216); `liqmix/govid` covers H.264 and was
missed by BOTH earlier surveys (2026-09-11 and 2026-09-16) even though it
dates from 2026-03-14. It is verified bit-exact against ffmpeg on our own
fixtures in `go/h264vid`, so the "system-player handoff is the honest
ceiling" conclusion below is obsolete. The table is kept as the record of
why the other candidates were rejected.

Original verdict (superseded): **blocked, with rationale.** Telegram videos are H.264/AVC in MP4
(+ AAC audio); video stickers are VP9/WebM. The constitution (§1.1) bans
non-Go runtime deps and cgo outside Gio's Linux GPU shims, so the decoder
must be pure Go. Deep-research pass over the current ecosystem:

| Candidate | Finding | Verdict |
|---|---|---|
| Eyevinn/hi264 | Pure Go H.264 toolkit, pixel-perfect vs FFmpeg — but the decoder handles **IDR + P_Skip only** ("full P/B-frame decoding is out of scope"). Built for thumbnails/test-vector generation. | ❌ player |
| ugparu/gomedia (yapingcat fork) | Pure-Go mux/demux only; H.264 **decoding needs hardware/VAAPI cgo paths**, libfdk-aac bindings need C toolchain. | ❌ cgo |
| mike1808/h264decoder | Wraps ffmpeg via goav cgo bindings. | ❌ cgo |
| golang.org/x/image/vp8 | Real pure-Go VP8 decoder — but Telegram sends no VP8 video (webm stickers are VP9; x/image has no VP9). | ❌ codec mismatch |
| Edge264 (FOSDEM'25) | C library, not Go. | ❌ not Go |

Consequences (superseded by `h264_decoder.md` — in-app H.264 playback now
ships through `go/h264vid`):
- ~~The in-app video player stays **system-player handoff** (slice 86).~~
- The web (WASM) target could legitimately use the browser `<video>`
  element later (JS interop is allowed there — same pattern as WebAudio).

This decision recorded per §1.13/§1.14 (research → rate → plan): the
existing videoBubble (thumb + play badge + duration + handoff) was rated
7/10 for what was achievable within the constitution — that ceiling was
an ecosystem limit, not a design limit, and it has since expired.
