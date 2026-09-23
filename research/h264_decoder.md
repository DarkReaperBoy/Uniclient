# Pure-Go H.264 decode — re-research 2026-09-23

**Verdict: UNBLOCKED.** The 2026-09-11 and 2026-09-16 passes both concluded
"no pure-Go full H.264 decoder exists". That conclusion was wrong — both
passes surveyed hi264 / go-openh264 / gomedia / cgo wrappers and never
surfaced `liqMix/govid` (created 2026-03-14, i.e. it existed during both
surveys).

## Candidate

`github.com/liqmix/govid` (MIT, pure Go, Go ≥ 1.25).

| package | contents | production deps |
|---|---|---|
| `h264` | from-scratch decoder: CAVLC+CABAC, I/P/B, High profile, 8×8 transform, DPB/MMCO, POC reorder buffer | stdlib + `govid` root (stdlib-only) |
| `mp4` | MP4 demux: stts/ctts presentation times, keyframe sync, SPS/PPS prepend | `Eyevinn/mp4ff` |

`gen2brain/mpeg` and `ebiten` appear only in bench/example/test files — they
are NOT pulled in by importing `h264`/`mp4`.

## Verification performed here (do not trust the README)

The govid README states "This repo is written by Claude", so every claim was
re-checked independently rather than taken on faith:

1. **Its own suite**: 86 pass, 21 skip. Every skip is a missing *local-only*
   fixture (`testdata/_capm3.264 not found`), not a broken code path.
2. **Its references are genuine ffmpeg output**: `ffmpeg -i test.mp4 -frames:v1
   -pix_fmt yuv420p -f rawvideo` reproduces the committed `test_frame0.yuv`
   **byte for byte** — so its "bit-exact vs ffmpeg" tests mean something.
3. **Our own fixtures, our own harness** (never shipped in govid): two MP4s
   encoded with ffmpeg at 128×96/30fps — one *Constrained Baseline, no
   B-frames* (the shape a Telegram round video uses), one *High + CABAC +
   2 B-frames* (worst case). Decoded through `mp4.NewDemuxer` +
   `h264.NewCodec()` and compared against `ffmpeg -pix_fmt yuv420p` raw
   output: **all 12 frames × 221,184 samples bit-exact on both**, SHA-256
   of the decoded planes equal to SHA-256 of the ffmpeg file:
   - `round_video`   `87104766def8a01e94c49604ec57a488192f2f425ec59dbb934c5b4b1e3c3588`
   - `high_bframes`  `5aab1a3a3945e7f33c6b3cfd6ca05e41260d84f3ef47603adbc7d739ffb51cbe`

Those two hashes are pinned by `go/h264vid` tests; a ffmpeg-gated test
re-derives them from the committed MP4 on any machine that has ffmpeg, so the
provenance never has to be taken on trust again.

## Rejected, with reasons (kept so the survey is not repeated)

| candidate | why not |
|---|---|
| Eyevinn/hi264 | IDR + P_Skip only — "full P/B-frame decoding is out of scope". Good for thumbnails, not playback. |
| mgvs/go-openh264 | intra-only ("P-slice / B-slice out of scope") — thumbnail decoder. |
| ugparu/gomedia forks | demux/mux only; H.264 decode paths are VAAPI/cgo. |
| mike1808/h264decoder | wraps ffmpeg through goav — cgo, banned by §1.1. |
| go-vp9 | VP9, wrong codec for Telegram video (which is H.264/MP4). |
| Edge264 | C library. |

## What this unlocks

Telegram sends video messages and round video notes as H.264/AVC (`avc1`) in
MP4, so the whole "blocked" family of parity rows becomes reachable:
row 143 (player bubble), 276 (playback controls), 231 (video bubbles),
281 (in-chat streaming) and 279 (PiP — the matrix's only MISSING row).

Recorded per §1.13 → §1.14 (research → rate → plan).
