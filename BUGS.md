# BUGS.md — the open bug list and the fix log

This file is the standing work list from 2026-09-23 on (AGENTS §11
"Bug hunt / stability phase"). Feature work is done — AyuGram parity
closed at 195/200 PRESENT and release **v0.9.1** shipped — so sessions
work from the top of the OPEN list below, plus anything they find on
the way.

The contract (same as everything in AGENTS.md):

- Every fix lands with a **test first** that fails without it.
- Fixed entries move to the Fixed log with their slice/commit.
- Nothing is closed on assumption: the evidence column is what makes
  an entry real, and "measured wrong" corrections get edited in place.
- Finding a new bug while fixing another ⇒ add an open entry even if
  you also fix it right away.

## Open (ordered by what a session should look at first)

| # | Where | What | Evidence / how to see it | Next step |
|---|-------|------|--------------------------|-----------|
| B-4 | gui/h264player.go | Stream readers stay open while their cache entry lives (≤48 entries; closed on reset/replace/evict since slice 230). A player-STOP hook could close earlier. | bounded by `h264PlayerMax`, but fd count grows with every streamed clip played in a session | close-on-stop: leaving the viewer/chat resets entries for that view |
| B-5 | gui/h264player.go `startVideoNoteInline` | A permanently-unplayable note arriving via the `wantInline` completion consumes the marker but shows nothing until the next tap (which routes to the system player). Pre-existing UX. | `ensureH264Player`'s `p.failed` early-return has no onFail at that call site | pass an onFail → `openMedia` handoff, same as the viewer path |
| B-6 | cores/matrix.go:1252 | Matrix group calls (MSC3401) not implemented — honest `ErrNotSupported` today. | code | feature work; owner-visible scope |
| B-7 | engine/events.go `maybeAutoDownload` | Auto-download ignores `RequestDownload` errors — correct for the new `ErrStreamActive` (the stream is already saving), but any other error is silent. | call sites capture nothing | log unexpected errors once |
| B-8 | repo root + `cores/teamspeak.go` `tsQuickLZCompress` | No LICENSE file exists in the repo at all (owner decision pending), and the slice-231 QuickLZ send-side is a byte-port of quicklz.c, whose header says the commercial license "does not cover derived or ported versions created by third parties under GPL". | quicklz.c header (fetched 2026-09-23, RT-Thread mirror); `ls LICENSE*` → none; the reference C is NOT vendored (gcc-built vectors only, like ffmpeg for fixtures) | owner picks the project license and confirms the port stays; until then provenance is documented here — never vendor quicklz.c |

## Fixed — slice 233 (2026-09-24)

| # | Bug | Why it mattered | Test |
|---|-----|-----------------|------|
| F-11 (= B-3) | **Duplicate chunk fetches.** `ensureChunk`'s fetch ran outside the bookkeeping lock with no coalescing: every reader that missed an already-started fetch issued its OWN RPC. Now per-chunk single-flight: one claim per chunk (`fetching[c]` channel), waiters block and re-check the bitmap; a failed leader hands the chunk over so the next waiter retries SERIALLY (no error herd); success wakes only AFTER `have[c]` is set; the lock is still never held across the RPC (Close/completion must not wait on the network), and results are coalesced, never cached (an entry exists only while a fetch runs). | measured pre-patch — the row's evidence line quantified with a delayed fake source: 8 readers of one chunk = **8 RPCs**; 4 concurrent whole-file readers = **126 RPCs vs 32** and **1,032,192 B fetched for a 262,144 B file (3.9× the bytes, ~4× the network cost of the same playback)** | `TestMediaStreamSingleFlightPerChunk` (both subtests RED pre-patch: `RPCs = 8, want 1` and `calls = 126, want 32`) + every prior stream test still green (external contract unchanged) + `-race` on the whole stream suite |

Readahead (the other half of the old "next step") is an optimization,
not a bug — not implemented, not opened as an entry; the duplicate-RPC
gap this row described is closed.

## Fixed — slice 232 (2026-09-24)

| # | Bug | Why it mattered | Test |
|---|-----|-----------------|------|
| F-10 (= B-2) | **Stale FILE_MIGRATE limitation — PREMISE CORRECTED.** There is no migration gap: gotd's invoker chain intercepts `FILE_MIGRATE`/`STATS_MIGRATE` and reruns the call on a sub-connection to the target DC (`telegram/client.go:280` `c.invoker = invokeDirect` → `invoke.go:70` → `sub_conns.go`), and every client we hold rides that chain (`t.api = tg.NewClient(rpcGuard{next: t.client})`); `DownloadFile` (downloader → same api) and the thumb path never had migration code either — they work BECAUSE gotd migrates. The old comment claimed errors "surface to the caller"; what actually surfaces is a REDIRECT failure, now wrapped with that context while the raw error stays `errors.Is`-visible for the engine's retryable-read classification. | a wrong limitation comment invites the next session to re-implement a gap that does not exist (the row's own "next step" said "mirror DownloadFile", which does not migrate either — the premise was wrong twice) | `TestReadFilePartWrapsRedirectFailureWithoutSwallowing` (RED pre-patch: raw `rpc error code 400: FILE_MIGRATE` with no context) + `TestReadFilePartReturnsBytesAndForwardsRange` (success-path guard: bytes + offset/limit/precise/location fidelity) |

Evidence chain walked line by line before deciding: `withAPI` →
`guardedClient() = tg.NewClient(rpcGuard{next: t.client})` →
`telegram.Client.Invoke` → `chainMiddlewares(invokeDirect)` →
FILE_MIGRATE branch → `invokeSub(dc)` → cached sub-connection.
gotd has no test of its own for that branch (grep), so the chain was
read directly from the pinned module (v0.161.0).

## Fixed — slice 231 (2026-09-23)

| # | Bug | Why it mattered | Test |
|---|-----|-----------------|------|
| F-8 (= B-1) | **QuickLZ send-side.** PREMISE CORRECTION first: the RX decompressor (`tsQuickLZDecompress`, fragmented AND non-fragmented) and TX fragmentation already existed — only the compress side was a TODO, so every command > 487 B went out as raw fragments while reference clients compress first. `tsQuickLZCompress` is a faithful port of official quicklz.c 1.5.0 level 1 in the TeamSpeak build configuration (streaming off, QLZ_PTR_64 — including the "stored position 0 reads empty" table quirk and the ratio give-up); `tsSendCommand` compresses first, ships one `0x40` packet when the stream fits, fragments the compressed stream when it does not, and falls back to raw fragmentation when give-up makes the stored form bigger than the input. | measured, not assumed: today's public server ACCEPTS raw multi-packet C2S (pre-fix live run — 615 B command → semantic permission reply = decoded end-to-end), so B-1 was an efficiency/compat gap, not an outage; but the wire cost was real: a 2600 B command went out as 6 packets instead of 1 | `TestTS3QuickLZCompressByteIdenticalToOfficial` (19 gcc-built golden vectors, byte-identical), `TestTS3QuickLZRoundTripOfficialStreams`, `TestTS3QuickLZCompressRejectsEmpty`, `TestTS3SendCommandCompressesLargeCommand` (4 subtests: 580 B→1 pkt, 2600 B→1 pkt, 1500 B noise→raw 4-fragment no-0x40, small→unchanged), `TestTS3SendCommandPacketIDsSequential`, live `TestTeamSpeakLiveLargeMessage` (pre + post fix) |

| F-9 | **Date-dependent tests found by the gate.** `TestHeaderLastSeenExact` / `TestSameCalendarDay` assumed "now minus 90 min / 1 h" is always the same calendar day — false between 00:00 and 01:30 local. The suite went RED at 00:03 while production was CORRECT (it rendered yesterday's date for a yesterday timestamp). Tests now anchor to noon of today's date: deterministic at every wall-clock time; only test code changed. | a red gate hides real regressions; the bug was in the test's wall-clock assumption, not the renderer | the failing runs themselves (repro in the 00:00–01:30 window pre-patch) + both tests green at any hour post-patch |

Session notes for honesty: guest text on ts.arcticblaze.net is now
permission-denied for big messages in both modes (permission drift
since the 2026-09-10 run), so peer delivery is no longer measurable
there — the live oracle is "semantic reply = decoded end-to-end",
delivery opportunistic; `TestTeamSpeakLiveRoundTrip` still passes (its
so-called echo is actually a third-party bot message — label corrected
to what it proves, S2C delivery). Caught on the first run: `same7` was
given an already-shifted position while it shifts internally (double
subtraction → panic `index -2`), one-line fix. Also known: the edit+
read/test-same-file pairing rule was violated twice more this slice.

## Fixed — slice 230 (2026-09-23)

Audit method: read the slice-228/229 streaming paths line by line looking
for wrong behaviour; every row below has a test that fails without the
fix.

| # | Bug | Why it mattered | Test |
|---|-----|-----------------|------|
| F-1 | **Stream/download write race.** `RequestDownload`/`executeDownload` never checked for an open stream, and `MediaManager.Cancel` cannot touch an already-dequeued job — `os.Create` (O_TRUNC) would truncate the sparse file under the playing picture. Auto-prefetch (`maybeAutoDownload`, scroll-in prefetch) makes the collision reachable with no user gesture. Now a per-file guard makes the writers mutually exclusive in BOTH directions (`ErrStreamActive` download-side, `ErrStreamBusy` stream-side) and duplicate jobs for one key skip. | broken playback; two writers on one path | `TestRequestDownloadRefusedWhileStreamOpen`, `TestOpenMediaStreamRefusedWhileDownloadActive`, `TestExecuteDownloadSkipsWhileStreamOpen`, `TestStreamGuardSurvivesDoubleClose` |
| F-2 | **Re-download of a completed file.** `RequestDownload` on a complete row re-`os.Create`d the finished file (truncate under readers) and enqueued needless network work; markers waiting on that row never fired. Now completes instantly with `download_complete` (no queue, no core call). | dead taps + file torn under readers | `TestRequestDownloadCompletesInstantlyWhenFileOnDisk` |
| F-3 | **fd leaks on the streamed-player path.** `ensureH264StreamPlayer` leaked its reader on every decline (already-playing re-open, parse in flight, invalid args); on parse failure the close lived only in caller closures; cache entries dropped readers on reset/replace without closing. Now ensure owns the reader on EVERY path and the cache closes `src` on reset/replace/evict. | fd table grows for the whole session (Android limit ≈1024) | `TestEnsureStreamPlayerClosesDeclinedReader`, `TestEnsureStreamPlayerClosesReaderOnParseFailure`, `TestStreamSourceClosesOnResetReplaceEviction` |
| F-4 | **Dead eviction path.** The h264 cache's size cap lived only in `get()`, which nothing calls for this cache — entries and producer goroutines grew without bound. Caps now enforced at every insert via a shared `evictLocked` (which also closes sources). | unbounded memory + goroutines | eviction subtest in `TestStreamSourceClosesOnResetReplaceEviction` |
| F-5 | **Transient failure pinned permanent.** Any `ParseSeek` error called `failParse`: one dead chunk fetch during parse marked the clip unplayable forever. New `h264vid.ErrDecodeFailed` + `IsPermanent` separate "verdict about the bytes" (pin) from "failed to read them" (retry). | §1.10 — a good clip dead-ended by one network blip | `TestParseSeekClassifiesDecodeStageFailure`, `TestParseSeekGarbageNotPermanent`, `TestIsPermanentClassifiesVerdicts` |
| F-6 | **Orphan sound / wrong join offset.** The completion-time audio join could start behind a viewer clip that had already played through (sound with a frozen last frame) and ignored loop phase. `streamJoinAt` wraps the offset with the picture and refuses ended clips. | fake playback (§1.10) + desync | `TestStreamJoinAt`, rewritten `TestStreamShouldJoinAudio` |
| F-7 | **Frozen frame with running sound.** A producer dying mid-play (fetch error) left the cache `playing` — static frame while the engine kept playing audio, taps did nothing. The draw path now heals: reset the entry + pause the audio; the next tap re-opens the source. | §1.10 stuck state | source-close tests + review (the draw call itself is gtx-bound, not unit-tested) |

Session notes kept for honesty: the test oracle itself was broken once
(`countCloser` was missing its `Close()` method, so every close
assertion silently passed on a no-op — the checker failed the checker),
and the "audio-only" fixture assumption was wrong (the aacaud fixtures
are full video files, measured with ffmpeg) — fixed by generating and
sha-pinning a real one: `h264vid/testdata/audio_only.mp4` =
`ade3487e…b6bb7`. Also investigated and dismissed: green run
`dd00b612` is the gh-pages workflow's own commit, not on `main`.
