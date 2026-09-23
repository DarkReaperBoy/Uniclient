# QR decoding (pure Go) — research for slice 227 / matrix row 306

Date: 2026-09-23. Question: **which pure-Go QR decoder should UniClient
ship** to close matrix row 306 ("Join via invite link / QR" — the gap was
"QR scan remains")?

Method follows the repo rule (§1.14): search live, then **measure — never
trust a README claim**. Every candidate library got to encode fixtures,
every other library decoded them, and only exact payload matches scored.

## Candidates (searched 2026-09-23)

| Library | License | Last push | Stars | Notes |
|---|---|---|---|---|
| `github.com/makiuchi-d/gozxing` | **MIT** (LICENSE file; GitHub's API says NOASSERTION — verified by reading the file) | 2025-07 | 672 | ZXing port; QR + other barcode formats; `golang.org/x/text` dep |
| `github.com/piglig/go-qr` | MIT | 2026-08 | 64 | encoder+decoder, zero deps, axis-aligned fast path + rotation/noise fallback |
| `github.com/netstar-labs/qr` | Apache-2.0 | 2026-07 | 0 | zero-dep; README states `DecodePNG` targets **clean, axis-aligned** images only — explicitly not camera photos |
| `github.com/snykk/qr-generator` | Apache-2.0 | 2026-09 | 1 | very new (v0.14.0); encoder+decoder with full image pipeline |
| `github.com/tuotoo/qrcode` | GPL-3.0 | 2022 | 331 | decoder-only, stale |
| `github.com/liyue201/goqr` | **LGPL-3.0** | 2020 | 88 | **archived**; decoder-only |

Copyleft flags matter here: the repo ships no LICENSE file, so GPL/LGPL
candidates were measured anyway but recorded as risky (same honesty rule
as the AAC research).

## The bench

`4 encoders × 6 decoders × 4 image variants × 6 payloads = 576 checks`.

- **Encoders** (independent of the decoder under test): piglig,
  netstar, snykk, gozxing — each renders the same 6 payloads
  (t.me `+hash`, `joinchat`, bare, long, numeric, UTF-8).
- **Variants**: base (module 8, quiet zone 4), rotated 90°
  (EXIF-orientation screenshots), JPEG q=40 round-trip (screenshot
  re-saved), JPEG + rotated.
- **Score**: exact payload match. Each decoder was also scored
  **excluding fixtures it encoded itself** (self-confirmation guard).

## Results

| Decoder | exact | wrong payload | failed | excl-own exact | rotation (4 variants avg) |
|---|---|---|---|---|---|
| **gozxing** | **96/96** | 0 | 0 | **72/72** | 24/24 every variant |
| snykk | 72/96 | 0 | 24 | 48/72 | 18/24 (fails on gozxing-encoded symbols) |
| netstar | 48/96 | 0 | 48 | 36/72 | 0 on both rotated variants (as its README admits) |
| goqr | 38/96 | **8** | 50 | 38/96 | ~9/24, and cannot read snykk output at all |
| piglig | 36/96 | 0 | 60 | 24/72 | 0 rotated |
| tuotoo | 36/96 | **4** | 56 | 36/96 | 0 rotated |

Two failure classes are not equivalent:

- **No-detect** (error) — the UI can say "no QR found".
- **Wrong payload** — the app would run `CheckChatInvite` on an attacker-
  shaped or truncated hash. **goqr returned 8 wrong payloads, tuotoo 4.**
  That alone disqualifies them for an invite flow.

## Decision

**`github.com/makiuchi-d/gozxing` v0.1.1 (MIT)** — the only candidate
with a perfect score *including* on foreign encoders, the only one that
handles rotation + JPEG artifacts on every input, and its wrong-payload
count is zero. The MIT LICENSE file was read directly (API reports
NOASSERTION). Pure Go; the `golang.org/x/text` dep is already in the
module graph.

Decoder configuration is pinned in `go/qrscan/qrscan.go`: `Decode` with
**nil hints** — the exact configuration the 96/96 was measured under.
Tuning it means re-running the bench.

## Fixtures (anti-self-confirmation)

`go/qrscan/testdata/` holds 8 PNGs **encoded by the three foreign
encoders** (piglig, netstar, snykk) with pinned SHA-256s in
`qrscan_test.go`, plus one no-QR negative:

| fixture | payload | variant |
|---|---|---|
| `invite_piglig.png` | `https://t.me/+QrSc4nBenchH4sh` | base |
| `invite_netstar.png` | `https://t.me/joinchat/AAAAAEhJT0luZml0ZQ` | base |
| `invite_snykk_utf8.png` | `https://t.me/+ключ🔑hash` | UTF-8 byte mode |
| `invite_piglig_rot90.png` | same as piglig | rotated 90° |
| `invite_netstar_jpeg40.png` | same as netstar | JPEG q=40 |
| `notinvite_piglig.png` | `https://example.com/not-an-invite` | negative: not an invite |
| `publiclink_netstar.png` | `https://t.me/someuser` | negative: public username, not an invite |
| `no_qr.png` | — | negative: image without a symbol |

So the decoder under test can never grade symbols it produced itself; the
only self-encoded test left is an explicit round-trip wiring check.

## Scope note (why file-based, not camera)

The matrix row is AyuGramDesktop parity: **desktop Telegram/AyuGram have
no camera QR scan** (no camera surface in a desktop GTK/Qt app), so the
shipped form is "pick a QR image file" — which is also what a desktop
user actually has (a screenshot, a downloaded image). The GUI exposes it
in the search field (the same surface that takes a pasted invite link),
decodes with `go/qrscan`, and reuses the existing
preview → confirm → `ImportChatInvite` flow. Camera capture would be a
mobile-only surface and is out of this row's scope.
