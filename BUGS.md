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
| B-1 | cores/teamspeak.go:1410 | QuickLZ compression never implemented — packets go out uncompressed (TODO since the rewrite). | code TODO; unknown whether current servers accept our uncompressed packets and at what size limit | research pass: protocol docs and/or a public/test TeamSpeak server, verify acceptance, then implement QuickLZ |
| B-2 | cores/telegram_stream.go:62 | `ReadFilePart` surfaces FILE_MIGRATE (cross-DC) errors like the existing thumb path — no DC migration/retry. | comment admits it; a file stored on another DC fails the stream and falls back to download-then-play | mirror what `DownloadFile`/thumb do for DC migration, or implement the upload.getFile downgrade flow |
| B-3 | engine/mediastream.go `ensureChunk` | Fetches run outside the lock, so two concurrent readers can fetch the same chunk (duplicate RPC). v1 documents the trade. | code comment; a multi-reader test can drive `fakePartSource.stats()` past `ceil(size/chunk)` | per-chunk single-flight + optional readahead; the external contract must not change |
| B-4 | gui/h264player.go | Stream readers stay open while their cache entry lives (≤48 entries; closed on reset/replace/evict since slice 230). A player-STOP hook could close earlier. | bounded by `h264PlayerMax`, but fd count grows with every streamed clip played in a session | close-on-stop: leaving the viewer/chat resets entries for that view |
| B-5 | gui/h264player.go `startVideoNoteInline` | A permanently-unplayable note arriving via the `wantInline` completion consumes the marker but shows nothing until the next tap (which routes to the system player). Pre-existing UX. | `ensureH264Player`'s `p.failed` early-return has no onFail at that call site | pass an onFail → `openMedia` handoff, same as the viewer path |
| B-6 | cores/matrix.go:1252 | Matrix group calls (MSC3401) not implemented — honest `ErrNotSupported` today. | code | feature work; owner-visible scope |
| B-7 | engine/events.go `maybeAutoDownload` | Auto-download ignores `RequestDownload` errors — correct for the new `ErrStreamActive` (the stream is already saving), but any other error is silent. | call sites capture nothing | log unexpected errors once |

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
