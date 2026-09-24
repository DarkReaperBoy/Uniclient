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

## Audit battery — 2026-09-24 (full sweep complete)

The whole tree was swept with an explicit tool battery before fix work
resumed; every open row below came out of it or from the code each
finding sent us to. Clean results count as "checked" for the areas
they cover:

- `staticcheck 2026.2.1 -checks=all -tags goolm` over all packages:
  326 findings, triaged BY HAND in source — bug-class codes
  (SA4004/SA4010/SA4006/SA9003/SA5008/SA1012/ST1018) each verified
  before logging; style codes (ST1003 naming, ST1000 package
  comments) are not bugs and are not logged.
- `go vet -tags goolm ./...` green; full `go test -race -count=1
  ./...` over ALL 16 packages: **0 failures, 0 data races**.
- TODO/FIXME/XXX/HACK markers in code: **0**. Defer-in-loop scan: 19
  hits, all opened and verified false positives (defer inside `go
  func` closures).
- Cross-builds vs AGENTS' platform table: windows/amd64 `CGO_ENABLED=0`
  OK (documented pure-Go), linux `CGO_ENABLED=0` fails exactly as the
  table documents ("Verified: CGO_ENABLED=0 fails"), android = gogio+
  NDK CI job already exists in verify.yml — no undocumented platform
  regression.
- `govulncheck` (inside `nix develop`, `GOFLAGS=-tags=goolm`; the
  module lives in `go/`, not the repo root): **1 reachable
  vulnerability → B-15**; additionally 1 vuln in required-but-uncalled
  modules and 5 in imported-but-uncalled packages — not reachable, no
  action owed.
- Coverage snapshot (context, not a bug row): cores 8.9%, utils 9.9%,
  gui 18.3%, engine 24.0%; pure-logic packages 71–87%. Repo has ZERO
  `func Fuzz` targets → folded into B-17's next step.
- Two findings had to outrun their tools and the tools were RE-CHECKED
  rather than trusted: the xmpp tag error was reproduced in a
  standalone program (B-11), and the two dead-UI parity rows were
  confirmed with `git log -S` showing the call sites were never wired
  (B-12, B-13) — parity rows corrected with the wrong claims kept
  visible, counts re-derived by the same machine parser.
- `research/*.md` limitation lists were reviewed; per AGENTS they are
  not authoritative, and nothing in them was promoted to a bug row
  without independent code evidence.

## Open (ordered by what a session should look at first)

| # | Where | What | Evidence / how to see it | Next step |
|---|-------|------|--------------------------|-----------|
| B-12 | gui/paidmedia.go + parity row 153 | **Paid-media unlock UI was never wired.** `layoutPaidMediaWall`, `paidUnlockClickable`, `confirmUnlockPaidMedia` have zero callers (staticcheck U1000; paren-less refs also zero), and the only writer of `a.paidDlg` sits inside the uncalled `confirmUnlockPaidMedia` → chat.go:306's confirm gate can never open. `git log -S 'layoutPaidMediaWall('` = ONE commit (219eabee, slice 181) → the call site never existed; parity row 153 claimed the wall renders (the checker counted files, not call graphs). Row corrected to CORE-ONLY with the original claim kept visible. | staticcheck U1000 ×3 + paidDlg-writer analysis + zero external refs (incl. parsePaidMedia/paidWallVisible/paidStarsText) + git -S | wire bubble→wall→click→confirm (parse + engine UnlockPaidMedia exist) or make the downgrade permanent; test first either way |
| B-13 | gui/signupcard.go + parity row 44 | **Dedicated signup form never wired.** `layoutSignupCard`/`signupSubmit`/`signupPickPhoto`/`signupPhotoCircle`/`labeledEditor` have zero callers (staticcheck U1000; grep across gui incl. login.go = 0); `AuthStateSignUp` falls into `authInput`'s default branch (login.go:348) → ONE generic line: no first/last split, no photo circle — the pre-slice-193 bug (last names silently merged/lost) is live again. `git log -S 'layoutSignupCard('` = ONE commit (22f4176d, slice 193) → never wired. Row 44 corrected to PARTIAL with the original claim kept visible. | staticcheck U1000 + dispatch read (login.go authCard default case) + git -S | wire the card into the signup dispatch (or rebuild split fields in authInput) + a test asserting the signup step renders the dedicated form / emits `first\nlast`; row 44 back to PRESENT only with that test green |
| B-14 | gui/menu.go:586 | Reaction-"more" button label is double-encoded mojibake: literal bytes `C3 A2 C2 8B C2 AF` = Latin-1 re-encoding of "⋯" (U+22EF) — contains raw control char **U+008B** → the message actions-row button renders an invisible/garbage glyph. | staticcheck ST1018 + `od -c` of the source line | replace with "⋯"; test: label constant contains no control characters and equals the expected glyph (RED pre-patch) |
| B-15 | go.mod (`github.com/cloudflare/circl` v1.6.2) | **Reachable dependency vulnerability GO-2026-4550** — incorrect secp384r1 CombinedMult in circl; fixed in v1.6.3. | govulncheck: "Your code is affected by 1 vulnerability from 1 module", reachable traces through the deltachat/xmpp crypto paths | `go get github.com/cloudflare/circl@v1.6.3`, full gate, re-run govulncheck → 0 reachable |
| B-16 | cores/teamspeak.go:2552 | **Server name never stored or surfaced.** The `initserver` handler's store branch is empty (SA9003, comment says "Store server name etc"); `virtualserver_name` is read nowhere else in the repo (only other occurrence = the servercreate WRITE at 6652) and `ServerList()` has no callers → a TS server's name never reaches the UI, and a live rename is invisible. | staticcheck SA9003 + repo-wide grep (2 occurrences total) + ServerList zero callers | store the name on initserver (and from serverinfo rows), surface it where the server header renders; test: initserver fixture ⇒ stored |
| B-17 | go/webm/webm.go:397-403,550 + go/vp9anim/vp9anim.go:256 | Media parsers swallow read errors (`num, _ = q.readUint(...)`, `colorRange, _ = br.bit()`): truncated/hostile files produce garbage fields instead of a decode error (§1.10 fail-don't-fudge), and the repo has ZERO `func Fuzz` targets so nothing hunts those paths. | `_ =` scan (229 hits total; these are the parser-class ones, read in context) + `grep 'func Fuzz'` → 0 | propagate the errors in EBML/VP9 header reads; add fuzz targets for webm/vp9 parse that must not panic on random bytes |
| B-18 | repo-wide (staticcheck U1000 ×141) | Dead-code inventory — mostly benign duplicates (`stopWebmEmojiPlayer` duplicates the inline eviction stop at emojifile.go:113-118; `openTtlDialog` superseded by the wired `openTtlDialogNow`; `slowmodeSendBlocked` package var shadowed by the App field) but includes unreachable features: `maybeRateCall` (call rating never opens), `cornerReplyOverlay` (never wrapped around rows), plus B-12/B-13's trios. | staticcheck -checks=all, each headline claim re-checked by grep before writing this row | per-cluster triage in fix slices: wire or delete — never delete blindly |
| B-19 | cores/teamspeak.go:1932 | Discarded gap diagnostic: the out-of-order branch builds `keys` from `recvQueue` and drops it (SA4010 — empty line where the result should be used): dead allocation on every gap event, and the intended queued-packet-id logging never happens. | staticcheck SA4010 + code read | log the queued ids at debug level or delete the block; add a test if behavior is added |
| B-20 | gui/drawer_test.go:126 (+ gui/stickers_test.go:41) | Test assertions that CANNOT fail: `if _, ok := contactChat(chats, "acc2", "100"); !ok { /* empty */ }` asserts nothing — the account-scoping case is untested (production `contactChat` IS correctly scoped: contacts.go:140-147 compares AccountID, verified by read); the stickers "no recent" case reassigns `sel` and never checks it. | staticcheck SA4006+SA9003 on the tests + contactChat source read | write the real assertions (wrong-account lookup must NOT match a scoped query; mid-case `sel` checked) — test-only fixes, RED where an assertion is added |
| B-21 | engine/auth.go:420 (`finalizeAuth`) | Nil context passed to `syncAccount(nil, …)` (staticcheck SA1012). Safe today ONLY because syncAccount never touches ctx (verified: health.go:180-216 has no ctx use — the `ctx.Done()` nearby belongs to monitorConnection): one future `ctx.Done()`/RPC use turns first login into a panic. | staticcheck SA1012 + full syncAccount body read | pass `context.Background()` (behavior-identical) + document syncAccount's ctx contract |
| B-5 | gui/h264player.go `startVideoNoteInline` | A permanently-unplayable note arriving via the `wantInline` completion consumes the marker but shows nothing until the next tap (which routes to the system player). Pre-existing UX. | `ensureH264Player`'s `p.failed` early-return has no onFail at that call site | pass an onFail → `openMedia` handoff, same as the viewer path |
| B-6 | cores/matrix.go:1252 | Matrix group calls (MSC3401) not implemented — honest `ErrNotSupported` today. | code | feature work; owner-visible scope |
| B-7 | engine/events.go `maybeAutoDownload` | Auto-download ignores `RequestDownload` errors — correct for the new `ErrStreamActive` (the stream is already saving), but any other error is silent. | call sites capture nothing | log unexpected errors once |
| B-8 | repo root + `cores/teamspeak.go` `tsQuickLZCompress` | No LICENSE file exists in the repo at all (owner decision pending), and the slice-231 QuickLZ send-side is a byte-port of quicklz.c, whose header says the commercial license "does not cover derived or ported versions created by third parties under GPL". | quicklz.c header (fetched 2026-09-23, RT-Thread mirror); `ls LICENSE*` → none; the reference C is NOT vendored (gcc-built vectors only, like ffmpeg for fixtures) | owner picks the project license and confirms the port stays; until then provenance is documented here — never vendor quicklz.c |

## Fixed — slice 237 (2026-09-24)

| # | Bug | Why it mattered | Test |
|---|-----|-----------------|------|
| F-15 (= B-11) | **XMPP roster never loaded.** The `<ver>` field tag (`xml:"jabber:iq:roster query>ver,attr"`) is structurally invalid — encoding/xml rejects `,attr` on a chained path — so `xml.Unmarshal` errored on EVERY roster payload; `handleRosterPush` returned silently on that error and `requestRoster` ignored it outright → `c.roster` stayed empty forever: contacts never appeared, and roster-push removes were dropped with them. Fixed by extracting `xmppParseRoster` (correct XEP-0237 element tag) and using it at both sites, which now LOG failures instead of swallowing them — an invisible empty roster must never again masquerade as "no contacts". | RED: `TestXMPPParseRoster` failed to build pre-patch (seam undefined; the audit's standalone probe had already shown `err=xml: query>ver chain not valid with attr flag, items=0` on every input); green post-patch across items/ver/groups, the `subscription=remove` payload, and the malformed-XML error path; full cores suite + `-race` clean; staticcheck re-run shows SA5008 gone |

## Fixed — slice 236 (2026-09-24)

| # | Bug | Why it mattered | Test |
|---|-----|-----------------|------|
| F-14 (= B-10) | **Multi-chunk streams completed after chunk 0.** `finishFetchLocked`'s done-check looped `for _, ok := range s.have` but broke on the first `ok` — inspecting only slot 0 (staticcheck SA4004, loop unconditionally terminated; present since slice 228, `git log -S`). With `streamChunk = 512 KiB`, EVERY file bigger than one chunk (i.e. every video) set `done` when the first chunk landed → `onDone` ran the DB promotion `download_state=DownloadComplete` + emitted `EventDownloadComplete` while most of the sparse file was still unfetched holes → "complete" consumers could read zero-filled gaps (the §1.10 class), play-on-done fired on partial bytes, badges lied. Fixed: completion = EVERY slot present, evaluated under the stream lock; exactly-once kept by the existing `justDone` / `onDone = nil` handoff. | RED: `TestMediaStreamDoneOnlyAfterLastChunk` failed pre-patch with "onDone fired after chunk 0 of 3 (1) — stream promoted complete while 2/3 of the file is still holes"; green post-patch, full engine suite + `-race` over all stream tests clean, staticcheck SA4004 gone |

## Fixed — slice 234 (2026-09-24)

| # | Bug | Why it mattered | Test |
|---|-----|-----------------|------|
| F-12 (= B-4) | **Stream readers outlived their view.** Entries kept `src` open from first play until reset/replace/evict (≤48 entries) — leaving a chat or closing the viewer held fds (Android ≈1024 cap) for the rest of the session. Both view boundaries now release: `closeViewer` resets the viewed clip, and an actual chat change runs `leaveChatMediaReset` → `resetAll` (drop every entry, close every reader, return the ids so their audio can pause). Lock discipline kept: `resetAll` takes the cache lock itself; the openChat hook runs WITHOUT `a.mu` (`closeSrc` reaches the engine's file guard). | fds freed at the view boundary instead of at eviction; the next visit re-parses honestly (no stale verdicts) | `TestCloseViewerReleasesStreamSource` (behavioral RED pre-patch: "stream reader still open after its view closed"), `TestH264CacheResetAllReleasesEverything`, `TestLeaveChatReleasesStreamSources` + full gui suite + `-race` |
| F-13 (= B-9, found while fixing B-4) | **Orphan sound across a chat switch.** The loop's audio re-arms only from the draw path (its own comment: "a stopped video never restarts its sound") — but NOTHING paused the CURRENT track on chat change (zero `videoAudioPause` call sites in `openChat`/`closeViewer` pre-patch), so a note's audio kept playing out behind the next chat (§1.10, bounded by track length but real). Logged as its own entry rather than folded into F-12; both view-boundary seams now pause their own track — own-track-only via `videoAudioMine`, so leaving a chat can never pause someone else's music. | sound without a picture when the user has moved on | the two hooks run inside `TestCloseViewerReleasesStreamSource` / `TestLeaveChatReleasesStreamSources` (glue over the already-tested videoaudio logic; the nil-engine guard makes the call a no-op in unit tests — the audio half is review-evidenced, not overclaimed) |

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
