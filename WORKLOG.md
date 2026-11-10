# WORKLOG.md — the state file

Top: the **STATE block** — rewritten every session, the resume pointer for the next
agent. Then open items (severity order), then entries newest-first, terse (did /
evidence / next). The pre-2026-11-01 progress docs (BUGS.md, research/) were purged by
owner order — that history lives in git if ever needed.

## STATE

- front: GUI rebuild (§6); D-3 (wasm size diet) CLOSED (session 414, two
  atomics): (1) the engine speaks capability interfaces + the shared
  cores/telegram_data.go schema — never a concrete core or a gotd type;
  (2) the six raw-TCP families tagged //go:build !js, bootstrap factory
  build-split (native full 9 / js github+matrix+bale with an honest
  "cannot connect from a browser" error), the account sweep rides the
  product list (no js deletions); gotd = 0 packages in the js link graph
  (go list -deps); wasm plain build 32,837,371 -> 26,714,844 B
  (-6,122,527 B, -18.6%) — the <20MB projection did not hold: the
  remaining bulk is the web trio's own deps (mautrix+goolm, bale
  gRPC-web, pion webrtc) + the rebuilt GUI (gio+fonts) — the honest floor
  for the current feature set. next front work: W-2 residuals — the
  search front (transliteration/username/"@"-mentions matching +
  search-results sections) and PaintComposeBar zero callers
- next: W-2 residuals (search front)
- owner-waiting: N-1 — install the uniclient-android APK artifact
  (build 42622715804) on a device and report (android GUI-default check)
- last-gate: session 414 — quick gate GREEN twice (atomics 1+2: scoped
  bootstrap/cores/engine + tests trio, tests/cores 59.1s, tests/engine
  6.7s; js legs: tests/webbuild under the wasm runner + audio
  regression), gofmt + comment ban clean (376 files), js/wasm full-tree
  build green; CI green on BOTH pushes: atomic 1 (16466373) Build #17 +
  Verify #413 (42848153096) + Pages #32; atomic 2 (cbec4ef7) Build #18
  (all 5 jobs) + Verify #414 (42851639961, all 3 jobs + steps) +
  Pages #33 — the live deployed wasm (CI shape, trimpath + -s -w) =
  26,194,302 B, serving at the Pages URL (was 17 gotd packages in the
  js graph; now zero)

## Open items

| ID | where | what | evidence | next step |
|---|---|---|---|---|
| W-1 | ui/app InitialModel | CLOSED 2026-11-09 (session 408): the zero-account scene now paints the frame — dialogs column SurfaceContainerLow vs chat Surface, 54dp header band, the reference-measured search field (7,9,W-18,35 r18) with real focus/typing/backspace/blink; driven live at 1440x900 + 390x844 (pixel scan: pill exact, ring+caret+typed text verified). The residual — the engine-driven add-account affordance — moved to the new front item below | session 408 driven journey | done |
| W-2 | app/engine bridge | PART: msg_received row bump landed (session 413 — engine emits the full bumped row: handleNewMessage increments unread before the row-update emit, ONE chat_updated per incoming message with preview/date/unread/move; REAL-seam wire test pins HandleUpdate -> chat_updated bytes -> app rows for a non-open chat); payload unification landed (session 413 — JoinChannel/ClearHistory emit emitChatUpdate's full row; ONE chat_updated wire shape); chat_updated atomic landed (session 412 — full-payload chat_updated drives live row content: ONE snapshotRow mapping path, replace-or-insert into accountRows, engine list law sorted locally (pinned DESC, last_msg_time DESC), filter+identity-selection reapplied, snapshot-equivalence pinned); filter atomic landed (session 411 — typed search filters the rows: SearchWords/MatchesWords law in ui/dialogs/search.go, word-prefix + accent/case fold + AND, selection = row identity across filter cycles); feeds atomic landed (session 410); STILL OPEN: PaintComposeBar zero callers, msg-level unread bars need read-position, ChatPreloadTopRequested is a no-op, transliteration/username/"@"-mentions matching + the search-results sections ride the search front | session 413 wire tests | D-4 atomic 2 |
| N-1 | android APK | GUI-default on android is runtime-unverifiable in-sandbox (no emulator/device); expected: the empty Material surface, not a black zombie | session 405 (js sibling); js live-verified in 406; APK artifact on build 42622715804 | owner installs the uniclient-android APK artifact and reports |
| H-2 | verify/release yml | CLOSED 2026-11-09 (owner order): android + web legs returned as build.yml (per-push, no tests, parallel); only the Xvfb GUI + Puppeteer web-drive legs stay parked with the rebuilt GUI | AGENTS.md §8; build 42597570851 | Xvfb/Puppeteer return when the GUI ships (§6.7) |
| H-3 | engine/cores API | 301+1 identifiers exported purely for the tests move (API noise: TsParseInit1, TsTrackRecvPID; audio's MicStop folded to micStop in session 368) | commit 27faa5a4, session 368 | fold into real APIs or de-export when tests are reworked during the GUI rebuild |
| D-1 | ui/history corner button | down-button unread-count badge (22dp, centered x, top 0 — jump_down_button.cpp paintEvent + historyToDownBadge*) + hover/over colors + ripple deferred: no unread counter in the chat Item model yet, no hover/ripple machinery in the skin yet; replyReturn branch of downClick + loadedAtBottom==false state return with reply-return jumps / below-history pagination | jump_down_button.cpp 33-52, corner_buttons.cpp 139-145 | badge returns with read-state counts; over/ripple with the skin's hover+ripple pass |
| D-2 | ui/history unread-things buttons | read-marking absent for mentions AND reactions: after a jump the button stays shown (reference hides it when the server marks the thing read — updateUnreadThingsVisibility is server-data-driven); mentionsClick's already-there voice/video media-read branch (5623) deferred — no media model; unread-count badges join D-1's class; poll-votes 4th stack slot returns with a poll model | history_view_corner_buttons.cpp 147-190, 288-345 | returns with engine unread-things events + the media pass |
| D-3 | build.yml web job | CLOSED 2026-11-10 (session 414, two atomics — see the session entry for the evidence trail) | gotd = 0 packages in the js link graph; wasm plain build 32,837,371 -> 26,714,844 B (-6,122,527 B, -18.6%); <20MB projection did not hold — remaining bulk = web trio deps (mautrix+goolm, bale gRPC-web, pion webrtc) + the rebuilt GUI (gio+fonts) | done; CI web job ships the trimmed wasm from the atomic-2 push |
| D-4 | window keys | ATOMIC 2 LANDED (session 413): plain Enter/Return -> ChatComposeSubmitted -> composeSubmittedCmd (guards: open+port+CanSend+non-empty) clears the field and fires ChatPort.Send -> ChatComposeSendRequested{OK,Text}; failed sends restore the field (composeEdit — no data loss); Up/Down arrows = ChatScrolled step 20dp, PageUp/PageDown = 200dp (tokens ScrollKeyStep = WheelNotch/WheelScrollLines/WheelPixelToAngleDelta, ScrollKeyPageStep = 10x — the Qt qabstractslider defaults through the wheel law); CanSend lands on the open transition from the row type (channels read-only — honest default until the writability front carries admin rights); REAL-seam: appport.Send -> engine.SendMessage -> optimistic msg_received -> open-chat append (wire test). Residuals: Up-on-empty-field edit-last rides the messages/edit front (scrolls meanwhile), Ctrl+Up/Down reply-cycle rides the reply front, scroll keys need compose focus — the unfocused chat pane has no key routing yet (window front) | history_widget.cpp 9276-9349 (fetched 2026-11-09) + qabstractslider defaults | IME ranged EditEvents + SelectionCmd/SnippetCmd contract = the mobile/IME front; window-front key routing |

## Session 415 — the search front opens: username wire + reference matching (2026-11-11)

- Boot: sandbox recycled to zero — toolchain rebuilt per env.sh (go 1.27.1,
  module cache refilled), .env re-created from the owner token (gitignored,
  askpass push intact). Machine: cold build cache cost paid once (gotd's tg
  serial compile; vet leg re-key, documented §9 rung-7 shape — converges on
  re-run, cache carries progress).
- Atomic 1 (chat_updated carries the row's username): emitChatUpdate's SELECT
  omitted chats.username, so every row-replace event (read state, mute, pin,
  title, row bumps...) emitted username "" — a violation of the session-413
  unified full-row law and the seam the search front needs (a username-matched
  row would lose its handle on the first chat_updated). Fix: c.username into
  the SELECT + scan. Test red->green:
  TestChatRowWireCarriesUsername (SyncChats a dialog with Username "devcrew"
  -> REAL read-state HandleUpdate -> captured chat_snapshot AND chat_updated
  bytes both decode username=devcrew). Red seen first: 'chat_updated must
  carry the full row's username: got "", want devcrew' (the snapshot leg
  already passed — GetChatList always selected it).
- Gates: quick gate GREEN (scoped: bootstrap, engine, tests/bootstrap,
  tests/engine 6.3s, appport + window + cmd via windows vet), gofmt clean,
  comment ban clean (376 files).

## Session 414 — D-3 closed in two atomics: engine decoupling + the raw-TCP js exclusion (2026-11-10)

- Boot: sandbox recycled — toolchain + module cache survived under ../toolchain
  (env.sh re-sourced, go 1.27.1; build cache warm only under the CGO_ENABLED=1
  recipe — a CGO_ENABLED=0 run re-keys the whole cache and OOMs on gotd's tg;
  use the dev-test/gate recipe), .env intact (gitignored, askpass push intact).
  CI for session 413's pushes recorded: Build #15 (c5cd8751) + Build #16
  (ff00c1e2) green, Verify #412 (42838556241) all 3 jobs + steps green on
  ff00c1e2, Build #14 (2dc365c8) cancelled by build.yml's own
  cancel-in-progress concurrency policy (superseded mid-run — not a red
  gate), Pages builds serving.
- The law (D-3 precondition, rated: the concrete-assertion engine was <7/10
  against the §6.3/§7 capability law — replaced, not patched): the engine
  projects per-core features through interfaces and never references a
  concrete core or a core SDK type — otherwise no build-tag core exclusion
  can ever shrink the js link graph. Research (identifier-definition map,
  engine vs the six raw-TCP families): 19 concrete assertions
  (auth.go 12 telegram + 2 bale; cache_users.go 7), 21 engine-cache schema
  types defined inside the telegram family (all pure structs, gotd-free —
  regex-audited), exactly one gotd import in the whole engine
  (cache_users.go, the GetMapTile tg web-file request + LangPackGetLanguages
  tg return).
- Change: telegramLoginFlow (16 methods, the login machine) + baleSubmitter
  in engine/auth.go; peerBarController/phoneSharer/botPhotoSetter/
  notifyDelayGetter/langPackGetter/geoTileFetcher in engine/cache_users.go —
  house-pattern interfaces at their call sites; every assertion target
  swapped, zero behavior deltas (wrong-core paths return the same errors);
  the 26-method surface maps 1:1 onto the real signatures (extracted, not
  transcribed). cores/telegram_data.go NEW (untagged): JoinAsPeerInfo,
  AdminLogEvent, ChatPermissionFlags, DefaultBannedRights, ParticipantExtra,
  BotCommandEntry, InlineBotResults, ForumTopicIconInfo, ChannelUsernameInfo,
  PasskeyInfo, CloudPasswordState, PasswordResetResult, ChatNotifySettings,
  PeerColorEntry, CloudThemeInfo, ChatThemeInfo, WallpaperInfo,
  CallHistoryEntry (telegram.go) + DiceSticker, DiceStickersResult
  (telegram_dice.go) + ChannelStats (telegram_stats.go) + the two new seams
  GeoWebFileQuery and LangPackInfo. Telegram methods reshaped:
  UploadGetWebFile(*tg.UploadGetWebFileRequest) (*tg.UploadWebFile) ->
  GetGeoWebTile(GeoWebFileQuery) ([]byte, error) (the engine's clamp law
  stays engine-side; the tg request build moves core-side);
  LangpackGetLanguages -> []LangPackInfo (field-mapped). Engine's gotd
  import deleted.
- Tests: tests/engine/engine_decoupling_test.go NEW, seen RED first —
  TestEngineImportsNoCoreSDK (cache_users.go "github.com/gotd/td/tg") and
  TestEngineAssertsNoConcreteCore (auth.go:136 *cores.TelegramCore; the
  pinned roster covers all 10 concrete cores — a new core joins by
  extending the pin) — then GREEN. All existing suites green zero re-pins:
  tests/engine 6.9s, tests/bootstrap 1.0s, tests/cores 59.3s (telegram
  scripted-server legs through the reshaped seams included). Edits via
  byte-exact python patch (sessions 410-412 landmine) with count-verified
  anchors; gofmt fixed three authored-file nits (alignment, import blank,
  test-file tabs) — gofmt -l . clean.
- Gates: quick gate GREEN (scoped: bootstrap, cores, engine,
  tests/bootstrap, tests/cores, tests/engine; windows vet gio legs),
  comment ban clean (373 files), js/wasm build green (engine + cores +
  bootstrap + cmd).
- Atomic 2 (the exclusion): the six raw-TCP families tagged
  //go:build !js — telegram.go, telegram_dice/stats/stream/savedmusic/
  notify_sound/proximity, irc.go, xmpp.go, deltachat.go, teamspeak.go,
  mumble.go (dtls_native + calls_debug already carried it); the two
  now-dead js variants deleted (telegram_dtls_js.go 130 B,
  telegram_calls_debug_js.go 72 B — no-op siblings of !js files,
  dead everywhere after the family cut). Fallout fixed in-run: the
  shared telegram_data.go referenced InlineBotResult (telegram.go) +
  StatsValue/StatsGraphData (telegram_stats.go) — moved into the island
  (pure structs); cores/proxy.go was untagged and dragged 17 gotd
  packages through dcs/mtproxy — split: the shared ProxyConfig +
  active() stay untagged, the MTProxy machinery (resolver/dialFunc/
  httpConnectDialFunc/bufferedConn, sole caller telegram.go) moved to
  cores/telegram_proxy.go (!js). bootstrap split: factory_native.go
  (!js, the full 9-case switch + vaultSessionStorage + the gotd session
  import, byte-spliced from bootstrap.go) / factory_js.go (js,
  webPlatforms trio + honest default error "platform %q cannot connect
  from a browser"); bootstrap.go keeps the productPlatforms list — the
  account sweep rides it, so the js build NEVER deletes an account of a
  build-excluded platform (build exclusion is not deprecation; a raw-TCP
  account in the web-local vault starts with the honest factory error).
  SupportedPlatforms() is per-build: js = [github matrix bale] (order
  pinned). No per-core js stubs — dead code on js by construction;
  the factory error tells the truth instead.
- Tests (atomic 2) red->green, both seen RED first: tests/webbuild NEW —
  platforms_js_test.go (//go:build js; the trio pin under the wasm
  runner — run 1 printed got [telegram matrix irc xmpp github bale
  deltachat teamspeak mumble]) + family_tags_test.go (!js; source scan:
  every telegram*/irc/xmpp/deltachat/teamspeak/mumble file in cores
  except the telegram_data.go island must open with //go:build !js —
  run 1 printed "deltachat.go ... not excluded"; + the bootstrap
  factory_native/factory_js first-line pins + bootstrap.go gotd-free).
  All existing suites green zero re-pins: tests/cores 59.0s,
  tests/engine 7.0s, tests/bootstrap 1.1s, tests/webbuild, js legs:
  tests/webbuild + tests/audio (0.74s regression).
- Evidence (atomic 2): js link graph — GOOS=js go list -deps
  ./cmd/uniclient: gotd 0 packages (was 17 before the proxy split;
  mumble/xmpp/deltachat/teamspeak/irc SDKs 0); wasm plain-flag build
  (the WORKLOG precedent shape — session-412 numbers were plain-flag;
  CI's build.yml web job adds -trimpath -ldflags "-s -w" on runners
  with disk) = 26,714,844 B vs 32,837,371 B (session 412) =
  -6,122,527 B (-18.6%); the <20 MB projection from the open item did
  NOT hold — the honest remaining bulk is the web trio's own deps
  (mautrix+goolm 28 pkgs, bale gRPC-web, pion webrtc for group calls)
  + the rebuilt GUI (gioui 39 pkgs + gofonts) — the floor for the
  current feature set; 100 MB gh-pages ceiling headroom restored.
  dev-test.sh js leg + gate.sh quick js routing extended to
  tests/webbuild.
- Machine notes: /tmp+rootfs hit 99% full twice (the trimpath re-key
  recompiles everything; the windows cross attempt OOM'd gotd as
  documented §9 rung 7) — /tmp/go-build* pruned between legs; the
  plain-flag build rides the warm cache.
- Gates: quick gate GREEN (js leg now includes tests/webbuild: vet +
  wasm-runner run + the runner self-test), gofmt clean, comment ban
  clean (376 files), js/wasm full-tree build green, native pure build
  green, windows cmd cross-build blocked by the /tmp disk ceiling
  (rung 7 — CI verify cross-build is the gate).
- Next: W-2 residuals (search front: transliteration/username/
  "@"-mentions matching + search-results sections; PaintComposeBar
  zero callers).

## Session 413 — W-2 wire atomics + D-4 atomic 2: row bumps, ONE payload shape, window keys (2026-11-10)

- Boot: sandbox recycled to zero — toolchain rebuilt per env.sh (go 1.27.1,
  module cache refilled 1.1G), .env re-created from the owner token
  (gitignored, askpass push intact); CI for session 412's push recorded
  green: Build 42803562918 all five jobs + Verify 42803582751 all jobs+steps
  on ed008c69, Pages 42804202730 serving. (Doc fix in-run: the atomic-2
  commit accidentally shipped this entry duplicated — rebuilt single here.)
- Atomic 1 (msg_received row bump): handleNewMessage ran
  updateChatLastMessage (which emits chat_updated — the event the UI row
  path rides) BEFORE incrementUnread, so a bumped row's unread badge
  lagged by exactly one message; preview/date/move already worked
  (session 412 path). UI-side synthesis rated <7 (duplicates engine law:
  unread counters, group preview needs chat type the msg_received payload
  lacks) — replaced, not patched: engine reorder, ONE event carrying the
  full authoritative DB row. Test red->green:
  TestNewMessageWireBumpsNonOpenChatRow (snapshot seeds c1 unread 2 below
  newer c2; REAL HandleUpdate new message in non-open c1 -> captured
  chat_updated bytes -> app rows: unread 2->3, preview "alice: live wire",
  date vs the captured envelope ts, c1 moves to top, non-open chat grows
  no items). Red seen first: "the bumped row must carry the incremented
  unread, got 2, want 3".
- Atomic 2 (chat_updated payload unification): JoinChannel + ClearHistory
  were the last bare-map chat_updated emitters ({"account_id","chat_id"}) —
  shapes the UI decodes to an empty ChatID and drops. Both now call
  emitChatUpdate: the full row re-read from the DB, ONE wire shape for
  chat_updated; no-row still emits nothing (Scan-err early return). Test
  red->green: TestJoinChannelAndClearHistoryEmitFullRowChatUpdated (stub
  core with JoinChannel/DeleteChatHistory -> SyncChats seeds the row ->
  REAL JoinChannel/ClearHistory -> captured chat_updated decodes
  chat_id/title/unread/last_msg_text through the {chat} shape -> app rows
  survive both events). Red seen first: 'JoinChannel must emit the
  unified full-row payload, got: {"account_id":"a1","chat_id":"c1"}'.
  No other consumer pinned the legacy shape (grep-verified).
- Atomic 3 (D-4 atomic 2, window keys): ComposeKeyMsg maps plain
  Enter/Return -> ChatComposeSubmitted (Ctrl/Shift+Return keep the newline
  law), Up/Down/PageUp/PageDown -> ChatScrolled deltas through tokens
  ScrollKeyStep (=WheelNotchAngleDelta/WheelScrollLines/WheelPixelToAngleDelta
  = 20) and ScrollKeyPageStep (=10x = 200) — the customUpDown law: vertical
  arrows NEVER move the compose caret. Update: ChatComposeSubmitted ->
  composeSubmittedCmd guards (open + port + CanSend + non-empty) -> clears
  the field (composeEdit("",0)) -> Cmd fires ChatPort.Send ->
  ChatComposeSendRequested{OK,Text}; failure restores the field text (no
  data loss). ChatPort gains Send; appport delegates to engine.SendMessage;
  the optimistic message lands in the open chat through the REAL
  msg_received wire (wire test pins items +1, Out, Sending). CanSend
  wiring: openCmdAfterPress captures row.ChatType != ChatChannel ->
  openCanSend; ChatLoaded lands it on the open transition (broadcast
  channels read-only — the honest default until the writability front
  carries admin rights). Regression caught by the gate and fixed in-run:
  ChatLoaded initially set CanSend on EVERY replay, stomping unit-journey
  preconditions (compose_elm viewport/resize pins) — moved inside the
  openLoaded transition (CanSend changes on open, not on content reload).
- Tests red->green (atomic 3): compose_keys_test.go table +7 (submit,
  arrows, page steps) with the ignore list re-pinned (7 now-mapped keys
  leave it — the law changed, pins updated in-commit);
  compose_submit_test.go NEW (5: send+clear journey with a recording fake
  port, failure restores, guards (no open / read-only / portless /
  empty), CanSend-from-row-type open journey, scroll-key clamp table);
  app_chat_wire_test.go +1 REAL-seam (port.Send -> optimistic
  msg_received -> open-chat append). BLOCKED-env: the driven wasm page
  cannot reach the compose (zero accounts -> no open chat) — the seam is
  proven at the wire boundary instead, session-410 precedent.
- Gates: quick gate GREEN three times (scoped: engine, tests/engine 6.4s,
  tests/bootstrap, bootstrap; then tests/gui, tests/ui, ui/* — gio cgo
  legs via windows vet), gofmt clean, comment ban clean (371 files),
  js/wasm build green. tests/gui out of scope for the engine atomics by
  construction — the wire seam (raw JSON bytes) keeps ui/app engine-free.
- Next: D-3.

## Session 412 — W-2 the chat_updated atomic: live row content updates (2026-11-10)

- Boot: sandbox recycled — toolchain + module/build caches survived under
  ../toolchain (env.sh re-sourced, go 1.27.1), .env re-created from the
  owner token (gitignored, askpass push intact); no red gate — Build #12
  + Verify #410 green on e627f27a.
- The law: engine emits chat_updated with the full row (emitChatUpdate
  re-reads the chat after read-state/mute/pin/title/… changes) -> the UI
  row must update LIVE. applyChatUpdated: decode {chat}; guards —
  ChatID=="" drops (covers the bare-map payloads JoinChannel/
  DeleteChatHistory still emit — engine-side unification is its own
  atomic), account must already have a snapshot row-set (never fabricate
  a partial list; the snapshot always precedes); row built through the
  ONE snapshotRow path (zero drift snapshot vs update); replace-or-insert
  into a copied slice (copy-on-write storeAccountRows, shared with the
  snapshot path); sortDialogRows re-derives the engine's own list law
  locally (is_pinned DESC, last_msg_time DESC — cache_chats.go
  GetChatList ORDER BY; stable sort: equal-time ties keep wire order,
  message-less rows SortTime 0 bottom) so the post-update store == the
  fresh-snapshot store; Entry.SortTime added (dialogs.Entry) — the UI
  never trusts wire order; reprojectDialogRows re-applies the active
  filter + identity selection (selection follows a row that moves) +
  scroll clamp.
- Tests red->green: tests/gui/app_feeds_test.go +11 (in-place replace at
  a tie, move-by-list-law, pinned law both directions, insert for an
  unseen chat, drop without a snapshot, 7 dropped shapes incl. the legacy
  bare-map payload, selection follows the moved row, filter re-applies on
  a rename + clear restores, snapshot-equivalence invariant, badge fields
  map from the event + non-badge content survives); tests/engine/
  app_chat_wire_test.go +1 REAL-seam (real HandleUpdate read-state JSON
  -> real chat_updated bytes -> app rows: unread 5 -> 0 while mention/
  reaction/mark PERSIST — the real engine tracks them apart from read
  state — rest of the row intact). All existing suites green, zero
  re-pins.
- Edit-tool landmine (sessions 410/411 pattern) hit again: whole-file
  tab->space rewrite — caught by the gate gofmt check, restored canonical
  via gofmt -w (diff back to pure additions; subsequent edits verified
  with gofmt -l in the gate).
- Driven: BLOCKED-env for live rows (no backend in the sandbox — zero
  accounts on the driven path; seam proven at the engine boundary
  instead, session-410 precedent). js/wasm builds green: 32,837,371 B
  (+660,516 B vs session 411: the router case + sort law + tests).
- Gates: quick gate GREEN (native vet+test scoped — tests/engine 6.7s,
  tests/gui, tests/ui, ui/dialogs, ui/history; windows vet gio legs),
  gofmt + comment ban clean (370 files); gotd windows cross-build
  compile OOM = documented §9 rung-7 machine limit — CI verify dispatch
  is the gate; CI record lands next session.
- Next: msg_received row bump for non-open chats, engine chat_updated
  payload unification, D-4 atomic 2, D-3.
