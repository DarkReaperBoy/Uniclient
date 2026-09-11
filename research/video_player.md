# In-app video player — pure-Go decoder research (2026-09-11)

Verdict: **blocked, with rationale.** Telegram videos are H.264/AVC in MP4
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

Consequences:
- The in-app video player stays **system-player handoff** (slice 86) on
  Linux/Windows — this is the honest ceiling per §1.10, not a regression.
- The web (WASM) target could legitimately use the browser `<video>`
  element later (JS interop is allowed there — same pattern as WebAudio);
  capability-gate it behind GOOS=js if ever built.
- Revisit when a complete pure-Go H.264/VP9 decoder lands upstream
  (hi264 growing P-frame support would be the likeliest path).

This decision recorded per §1.13/§1.14 (research → rate → plan): the
existing videoBubble (thumb + play badge + duration + handoff) is rated
7/10 for what is achievable within the constitution — kept, not replaced.
