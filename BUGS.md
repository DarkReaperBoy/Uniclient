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
| B-6 | cores/matrix.go:1252 | Matrix group calls (MSC3401) not implemented — honest `ErrNotSupported` today. | code | feature work; owner-visible scope |
| B-8 | repo root + `cores/teamspeak.go` `tsQuickLZCompress` | No LICENSE file exists in the repo at all (owner decision pending), and the slice-231 QuickLZ send-side is a byte-port of quicklz.c, whose header says the commercial license "does not cover derived or ported versions created by third parties under GPL". | quicklz.c header (fetched 2026-09-23, RT-Thread mirror); `ls LICENSE*` → none; the reference C is NOT vendored (gcc-built vectors only, like ffmpeg for fixtures) | owner picks the project license and confirms the port stays; until then provenance is documented here — never vendor quicklz.c |

## Fixed — slice 246 (2026-09-24)

| # | Bug | Why it mattered | Test |
|---|-----|-----------------|------|
| F-27 (= B-5) | **Inline play failure consumed the marker silently.** `startVideoNoteInline` passed NO onFail, so a permanently-unplayable note completing via the play-on-done marker showed nothing until the next tap; and `ensureH264Player`'s `p.path==path && p.failed` early-return swallowed onFail even when a caller DID pass one — the entry is known-bad and will never play, so the fallback had to run there too. Both fixed: the completion entry now hands off exactly like the viewer path (toast "Can't play this video in-app — opening system player" + `openMedia` → system player, §1.10 no dead bubble), and the failed-entry early-return notifies. | RED: `TestInlinePlayFailureHandsOffToSystemPlayer` (garbage .mp4 through the real setPlayOnDone → onDownloadComplete → parse-fail path with `openExternalAsync` stubbed) failed pre-patch with `opened=[] … (B-5)`; second part pins the already-failed early-return (onFail must still fire). **-race caught a data race in the first draft of this very test** (unsynchronized stub slice + flag vs the parse goroutine) — fixed with a mutex in the harness before landing; post-patch both tests + full gui suite + `-race` green |

## Fixed — slice 245 (2026-09-24)

| # | Bug | Why it mattered | Test |
|---|-----|-----------------|------|
| F-26 (= B-18) | **Dead-code cluster triaged wire-or-delete.** 58 symbols removed across gui/engine/cores (staticcheck U1000 **128 → 70**). Two premises inside the original row were WRONG and are corrected here: (a) "call rating never opens" — it is LIVE: `onCallStateEvent` arms the dialog INLINE (callui.go) and app.go renders it; the flagged openers were superseded duplicates — the inline block was consolidated into `openRateCall` (behavior-identical) and `maybeRateCall` deleted; (b) `slowmodeSendBlocked`/`muteDlgCustomErr` deletion needed MORE than the declaration: every remaining reference was a pure WRITE (unused's read-based analysis was right) — write sites removed too; while doing so it surfaced that muteDlgCustomErr's validation hint (`Use a duration like…`) had NO display path ever — dead state from an unbuilt hint, part of this cluster not a separate bug. KEPT with evidence: `audio/opensl_layout.go` (U1000 is a linux-view artifact — `opensl_android.go:266+` consumes locatorType/pLocator/deviceType under the android tag) and the mumble + TeamSpeak protocol enum tables (reference tables, deliberate). Also deleted: abandoned overlay/tile/field leftovers (cornerReplyOverlay, closeInstantView superseded by locked inline closes, openTtlDialog duplicate of openTtlDialogNow, layoutOneTimeChip, stopWebmEmojiPlayer superseded by the inlined eviction stop, the telegram tgcalls-era SDP experiments, …). | Pure deletion has no RED possible (documented like F-22): the machine evidence is the COMPILER (every deletion survived `go vet -tags goolm ./...` rc=0 — a missed reference fails the build) + the full test suite (all 14 packages ok) + staticcheck recount 128→70 with no new findings + gofmt clean; the callrate consolidation is behavior-identical (same state fields, own lock) and review-pinned |

## Fixed — slice 244 (2026-09-24)

| # | Bug | Why it mattered | Test |
|---|-----|-----------------|------|
| F-25 (= B-17) | **Media parsers swallowed read errors + the repo had zero fuzz targets.** `parseTrackEntry` did `num, _ = q.readUint(...)`: a malformed TrackNumber/TrackType/DefaultDuration became a fabricated 0 that the track gate reads as "absent" — malformed input indistinguishable from a file with no video track (§1.10). Now those decision-critical fields return `ErrBadElement` (signature `(uint64, error)`, propagated through `parseTracks`), while two lenient paths were KEPT deliberately with the reasoning in-code: `parseBlockMore`'s add-id (optional alpha — malformed must degrade to "absent", never fabricated bytes) and the optional w/h `if ok` style (absence, not swallowed failure). vp9anim's `colorRange` bit-read was made explicit too (provably recovered by the next frame-size read, but the branch costs nothing). Fuzz targets added: `webm.FuzzParse` + `vp9anim.FuzzParse` with seeds from the builders and the committed official streams — contract: never panic, never (nil, nil). | RED: `TestMalformedTrackNumberIsAnErrorNotAnAbsentTrack` failed pre-patch (`err=webm: no VP9 video track` — malformed read as absent, want ErrBadElement); green post-patch; **750k+ fuzz execs across both targets (648,852 webm + 99,145 vp9anim + post-patch re-runs) crashed ZERO times**; full webm/vp9anim suites green; seed-corpus mode (what CI runs) is instant |

## Fixed — slice 243 (2026-09-24)

| # | Bug | Why it mattered | Test |
|---|-----|-----------------|------|
| F-21 (= B-19) | **Discarded gap diagnostic.** The out-of-order branch of `tsProcessCommandQueue` built `keys` from recvQueue and dropped the slice on an empty line (SA4010): a wasted allocation on every command-queue gap and the intended queued-packet logging never happened. Now logs `ts: waiting for command packet %d; queued out-of-order: %v` (still under the documented recvQueueMu contract; `log` import added — teamspeak.go previously only had fmt debug prints). | RED: `TestTSCommandQueueLogsGapWithQueuedIDs` (crafted pktState=5 with queued 7,9 through the real `tsProcessCommandQueue`) failed pre-patch with `gap log … got ""`; green post-patch (log names 5 and lists 7, 9) |
| F-22 (= B-20) | **Test assertions that could not fail.** `drawer_test`'s account-scoping branch had an EMPTY body (SA4006+SA9003 — the case proved nothing) and `stickers_test` reassigned `sel` in the no-recent case without checking it. Both now assert the real contract: acc2/100 must resolve to ITS OWN DM title, and an in-range selection survives `stickerTabs`. Production was CORRECT in both places (contactChat compares AccountID at contacts.go:140-147; stickerTabs keeps in-range sel at stickers.go:52-54 — both source-verified), so no RED exists for correct behavior — the assertions themselves are the fix and WILL fail if scoping or clamping regresses. | new assertions green against the verified-correct production code; the rows that flagged them were staticcheck SA4006/SA9003 on the test files |
| F-23 (= B-21) | **Nil-context landmine at first login.** `finalizeAuth` passed `syncAccount(nil, …)` (SA1012). Safe only while nothing dereferences ctx — one future `ctx.Done()`/RPC use turns first login into a panic. Now: `syncAccountContext` replaces nil with `context.Background()` at the boundary (the documented contract) AND the call site passes Background explicitly (defense in depth). | RED: `TestSyncAccountContextNeverNil` failed to build pre-patch (seam undefined); green post-patch pins nil→Background plus pass-through of a real ctx |
| F-24 (= B-7) | **Silent auto-download errors.** `maybeAutoDownload` discarded `RequestDownload`'s result: correct-for-ErrStreamActive (playback is already saving the bytes) but every other error — missing media row, uninitialized manager — vanished, so a broken pipeline was indistinguishable from "settings said no". Now logs `[engine] auto-download …: err` for everything except ErrStreamActive (RequestDownload never returns ErrStreamBusy — its return paths are not-found / stream-active / media-not-init / enqueue, so Active is the only benign exception; `errors`+`log` imports added to events.go). | RED: `TestAutoDownloadLogsUnexpectedRequestErrors` failed pre-patch (`… was silent; log = ""`), green post-patch; `TestAutoDownloadStaysQuietOnStreamActive` guards the benign exception (claims the stream via the real guard, asserts an empty log) |

## Fixed — slice 242 (2026-09-24)

| # | Bug | Why it mattered | Test |
|---|-----|-----------------|------|
| F-20 (= B-16) | **TeamSpeak server name never stored or surfaced.** The `initserver` handler's store branch was an empty `if` with a "Store server name etc" comment (SA9003), `virtualserver_name` was read nowhere else in the repo (2 occurrences total: this empty read + the servercreate WRITE), `ServerInfo()` had zero callers — and `GetDialogs` hardcoded `Title: "Server Chat"`. So a server's own name never reached the chat list and a live rename was invisible. Now: `initserver` stores it (`setServerName`, own mutex — GetDialogs reads it under `t.mu.RLock`, no lock-order inversion) and the server dialog's title uses it, falling back to the historical label when no name has arrived. The serverinfo-row store from the row's next step was NOT added: `ServerInfo()` has no production callers (grep-verified), so it would have been dead code — initserver is the standard TS3 carrier of the name. | RED: `TestTeamSpeakInitserverStoresAndSurfacesServerName` (uses only pre-existing API — `tsHandleServerCommand` + `GetDialogs`) failed pre-patch with `title = "Server Chat", want the virtualserver_name… (B-16)` for both the initial push and a rename push; `TestTeamSpeakServerDialogFallsBackWithoutName` guards the no-name fallback; green post-patch, full cores suite + `-race` clean |

## Fixed — slice 241 (2026-09-24)

| # | Bug | Why it mattered | Test |
|---|-----|-----------------|------|
| F-19 (= B-15) | **Reachable dependency vulnerability GO-2026-4550** — incorrect secp384r1 CombinedMult in `github.com/cloudflare/circl` (v1.6.2, pulled in via ProtonMail/go-crypto → openpgp used by the deltachat/xmpp crypto paths). Bumped to **v1.6.3** (the fixed release) with `go get` + `go mod tidy`; go.sum pins updated. | govulncheck IS the failing test here: pre-bump it reported "Your code is affected by 1 vulnerability from 1 module" with reachable traces; post-bump (same command, same flags: inside `nix develop`, `GOFLAGS=-tags=goolm`) it reports **"No vulnerabilities found. Your code is affected by 0 vulnerabilities."** + full gate green (vet/tests/race against the new dep) |

## Fixed — slice 240 (2026-09-24)

| # | Bug | Why it mattered | Test |
|---|-----|-----------------|------|
| F-18 (= B-14) | **Reaction-"more" button rendered mojibake with an invisible control char.** The literal was `C3 A2 C2 8B C2 AF` — a Latin-1 double-encode of "⋯" (U+22EF) that embeds raw U+008B, so the message actions-row button showed a garbage/invisible glyph (staticcheck ST1018). Fixed as `reactionMoreLabel = "⋯"` const; the package-wide source scan (decoding each .go and rejecting any rune in U+0080–U+009F) found exactly this ONE site repo-wide — and now guards against any future double-encode. | source-scan RED evidence: the slice-240 python scan reported `go/gui/menu.go 586 ['0x8b']` as the repo's only C1-control hit; `TestGUISourcesHaveNoControlCharLabels` compiles-RED pre-patch (const undefined) and becomes the behavioral regression guard after (scan must stay zero + const must equal "⋯") — green post-patch, octet 0x8B gone from the file |

## Fixed — slice 239 (2026-09-24)

| # | Bug | Why it mattered | Test |
|---|-----|-----------------|------|
| F-17 (= B-13) | **Dedicated signup form was never wired.** `authCard` had no `AuthStateSignUp` case (git -S: the call site never existed since slice 193), so signup fell into the default branch → the generic single-line `authInput`: no First/Last split, no photo circle, and the pre-193 bug (last names silently merged/lost, engine expecting `first\nlast`) stayed LIVE while parity row 44 claimed it fixed. Wired: `case engine.AuthStateSignUp: return a.layoutSignupCard(...)` in the dispatch. Parity row 44 restored to PRESENT on the strength of the test (miscount history kept visible in the row). | RED: `TestSignupStepRendersDedicatedCard` drives the REAL `authCard` through the input router and clicks the Create-account band — failed pre-patch with `toast=""` and the B-13 diagnosis (the assertion is the card's OWN validation wording, which the generic input can never say); green post-patch (toast = "Enter your first name"), full gui suite + `-race` clean |

## Fixed — slice 238 (2026-09-24)

| # | Bug | Why it mattered | Test |
|---|-----|-----------------|------|
| F-16 (= B-12) | **Paid-media star wall was never wired.** `layoutPaidMediaWall`, `paidUnlockClickable` and `confirmUnlockPaidMedia` had zero callers since slice 181 (`git log -S` = one commit), so locked paid posts showed no wall, no price, no Unlock button — parity row 153's whole chain was unreachable, and the confirm card's only state-writer sat inside the dead function. Wired through the bubble's media row via a new pure dispatch (`paidBubbleWall`: locked-only, §1.10), AND fixed a second defect found while wiring: `widgets.init()` never created `paidUnlockBtns`, so the FIRST wall render would have written a nil map and panicked. Parity row 153 restored to PRESENT on the strength of the new test (history of the miscount kept visible in the row). | RED: `TestPaidWallRendersInBubbleAndArmsConfirm` drives the REAL `messageRow` layout through the real input router and clicks the wall's Unlock button — failed pre-patch with "paid wall never armed the unlock confirm — the star wall is not wired into the bubble (B-12)"; green post-patch (confirm armed with stars=25 + right msgID), guard subtests prove unlocked/plain messages never arm it; full gui suite + `-race` clean |

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
