# AAC decoder research (verified 2026-09-23)

**Verdict: there IS a working pure-Go AAC decoder — `github.com/tphakala/go-aac`,
verified here byte-identical to ffmpeg on 4/4 fixtures.** Our earlier claim
("no pure-Go AAC decoder exists", written in slices 220–221) was **wrong**, and
it was wrong for the same reason `research/h264_decoder.md` was wrong about
H.264: it was inherited, never re-run.

Follows the house rule: *research files go stale or hallucinate; verify twice.*

## Why the claim was made, and why it was false

The claim was never tested — it was carried forward as plausible ("codecs need C")
and used to justify omitting the viewer volume slider (§1.10). Searching current
sources produced **four** pure-Go AAC decoders:

| module | license | deps | status |
|---|---|---|---|
| `github.com/tphakala/go-aac` | LGPL-2.1 | `tphakala/simd` (Go asm, no cgo) | **verified correct here** |
| `github.com/arabian9ts/aac-go` | Apache-2.0 | none | **measured WRONG on stereo content** |
| `github.com/skrashevich/go-aac` | LGPL-3.0 | none | not measured (port of AAC.js) |
| `github.com/llehouerou/go-aac` | GPL-2.0 | — | not measured |

## How each was measured (the gate)

Fixtures generated locally with the installed ffmpeg, then decoded by the Go
library and by ffmpeg's **fixed-point AAC decoder**, compared by SHA-256:

```
ffmpeg -f lavfi -i sine=... -c:a aac -b:a 128k -ar 48000 -ac 2 -f adts out.aac
ffmpeg -c:a aac_fixed -i out.aac -c:a pcm_s16le -f s16le ref.raw   # oracle
<go decoder> out.aac -> out.raw ; sha256sum ref.raw out.raw
```

`aac_fixed` must be given **before `-i`** (it is a decoder, not an encoder);
placing it after `-i` fails with `Unknown encoder 'aac_fixed'` — the first
attempt did exactly that and produced no reference at all.

### `tphakala/go-aac` — 4/4 byte-identical

| fixture | content | result |
|---|---|---|
| `stereo48` | 440+660 Hz tone, AAC-LC 128k, 48 kHz stereo | **IDENTICAL** `aa084cd1…` |
| `mono44` | 300 Hz, 96k, 44.1 kHz mono | **IDENTICAL** `6eeb5bc5…` |
| `noise48` | pink noise, 192k, 48 kHz stereo | **IDENTICAL** `5edfe040…` |
| `tg_like` | Telegram-shaped MP4 (H.264 baseline + AAC-LC 96k mono) | **IDENTICAL** `8256cc5e…` |

`196608 / (48000·2·2) = 1.024 s` etc. — sample counts include AAC's 1024-sample
priming, which a decoder must not drop.

Why it matches: it is a function-by-function port of FFmpeg's own fixed-point
decoder, pinned to FFmpeg commit `d09d5afc3aebede25d2d245ee23b75a47ea17c3a`,
with its own differential gates against a pinned FFmpeg build (see its
`PROVENANCE.md`, and that it self-declares LGPL-2.1-or-later *because* of that
derivation — the license and the correctness are the same fact). Its `pcm`
tests pass locally (`ok github.com/tphakala/go-aac/pcm`).

### `arabian9ts/aac-go` — **rejected on measurement**, not on reputation

Permissively licensed (Apache-2.0), zero dependencies, genuinely pure Go, and
correct frame counts — but it is a from-scratch implementation, so:

| fixture | peak | max error | SNR | samples off by >64 LSB |
|---|---|---|---|---|
| `mono44` | 7456 | 5 | **74.4 dB** | 0.00% |
| `tg_like` | 5010 | 10 | **74.3 dB** | 0.00% |
| `stereo48` | 5131 | 30 | **65.4 dB** | 0.00% |
| `noise48` | 18768 | **5802** | **17.3 dB** | **88.0%** |

Mono tone content is fine; **pink-noise stereo at 192k decodes at 17 dB SNR** —
i.e. corrupted, audible, not a rounding artefact (88% of samples are wrong by
more than 64 LSB). A codec that is correct on some inputs and broken on others
is the worst possible failure mode for us: it would ship as "audio works" and
break on real Telegram voice/video content. **Not usable.**

This is also why "it builds and its tests pass" is not evidence: aac-go's own
35 test functions pass.

## What it does NOT cover

- **HE-AAC (SBR/PS)**: explicitly out of scope in both libraries. Telegram
  video/video-note audio is AAC-LC 48 kHz (and 44.1 kHz), so this is the common
  case; HE-AAC content falls back to the system player.
- **960-sample frames, channel configs above stereo**, xHE-AAC, LATM.
- MP4 gives **raw access units + an `AudioSpecificConfig`**, not ADTS.
  `go-aac` handles this via `aacpcm.WithRawStream(asc)`; `aac-go` has no ASC
  path at all (ADTS only), which is a second reason it does not fit.

## License note (for the owner, not a technical blocker)

The repository has **no LICENSE file**, so there is no declared project license
to conflict with. `go-aac` is **L LGPL-2.1-or-later** (it is a derivative of
LGPL FFmpeg and can never be permissive). Using it means: it stays a separate
Go module referenced in `go.mod` (its source is one `go mod download` away, and
the repo ships source), so LGPL §6's relinking/replacement guarantee is
satisfied by module boundary + `replace`. The alternative — a permissive
decoder — was measured and found incorrect, so this is a correctness-driven
choice, not a licensing preference.

## Bottom line

- `go-aac` **decodes AAC-LC correctly in pure Go**, verified the same way we
  verified `govid` for H.264.
- Row 276's volume was never blocked by a missing decoder; it is blocked by the
  **work** (MP4 audio-track demux + A/V sync against the video clock + a volume
  path in the audio backend).
