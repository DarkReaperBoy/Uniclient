# WORKLOG.md — the state file

Top: the **STATE block** — rewritten every session, the resume pointer for the next
agent. Then open items (severity order), then entries newest-first, terse (did /
evidence / next). The pre-2026-11-01 progress docs (BUGS.md, research/) were purged by
owner order — that history lives in git if ever needed.

## STATE

- front: session 386 — the Material icon
  asset library landed as d8eedff (13 glyphs:
  chat-type bot/channel/forum, send-state
  sending/sent/received in both dialogs and
  history cells, badges pinned/mention/reaction/
  poll; @3x blue-channel crack-trace + chatlist
  SVG flatten; icon canvas law point(x,y) =
  margins(x,y,0,0) from codegen parsed_file.cpp;
  TTL timer law; selection laws; paintMessage
  now paints the history send-state glyph);
  verify 42454857199 SUCCESS at job AND step
  level — closed green
- next: dialogs row painter leg (RowLayout ->
  userpic/name/date/badges/glyph paint over the
  386 assets — ChatTypeIcon in-cell offsets,
  send-state cell at nameX+nameW, pinned right-
  aligned to its 20px canvas, badge glyph fills,
  TTL timer over the blurred userpic cutout);
  info-block width law: out messages reserve
  the 24px ticks space in the text skip
  (bottom_info.cpp:181-183); chat-leg scroll
  input (wheel/touch — dialogs kinetic laws
  apply) after that
- owner-waiting: none
- last-gate: quick GREEN (137 ui + 43 gui = 186
  PASS; windows-vet substitute for render/window/
  cmd); comment ban 310 clean; CI 42454857199
  success (3 jobs, all steps)

## Open items

| ID | where | what | evidence | next step |
|---|---|---|---|---|
| H-2 | verify/release yml | android APK + web (gh-pages) + Xvfb GUI legs parked until the new GUI | AGENTS.md §6/§8 | re-add with the GUI build (owner order pending) |
| H-3 | engine/cores API | 301+1 identifiers exported purely for the tests move (API noise: TsParseInit1, TsTrackRecvPID; audio's MicStop folded to micStop in session 368) | commit 27faa5a4, session 368 | fold into real APIs or de-export when tests are reworked during the GUI rebuild |

## Session 386 — the Material icon asset library (2026-11-08)

- VM survived again; repo booted at 8420312 ==
  origin (385 had closed green in a lost
  session); baseline 178 re-verified.
- Canvas law (codegen_style parsed_file.cpp:967-
  969 + lib_ui MonoIcon::paint/createCachedPixmap):
  icon part point(x,y) = QMargins(x,y,0,0) —
  glyph at cell+(x,y), canvas = mask+point;
  SVG -WxH modifier renders the FULL viewBox
  into W x H (mention/poll/reaction 72 -> 18,
  scale 0.25); PNG coverage = blue channel byte
  (colorizeImage offset 0, useAlpha false); @3x
  assets are per-DPI hand-tuned (bbox differs
  from 1x up to 0.67px — @3x is the trace
  source, bounds pinned to it).
- 13 glyphs: bot 16x11@(1,3)->17x14, channel
  12x11@(3,4)->15x15, forum 19x10@(1,4)->20x14,
  dialogs sending 11x11@(8,4)->19x15 / sent
  12x10@(10,4)->22x14 / received 17x10@(5,4)->
  22x14, pinned 20x20, chatlist 18x18 x3, history
  sending 11x11@(5,5)->16x16 / sent 13x11@(2,4)-
  >15x15 / received 18x11@(2,4)->20x15. PNG legs:
  crack-boundary walk on the @3x binary (blue>
  127), RDP eps 0.75@3x, /3 grid; contour order =
  component scan then area-desc (outer, holes,
  next); holes wind opposite automatically. SVG
  legs: absolute M/L/C/Z flatten, 12 samples per
  cubic. IoU vs @2x coverage 0.886-0.957.
- TTL timer (ttl_icon.cpp): pen 1.5 round, solid
  LEFT half-arc 90..270deg as one annulus
  contour with round caps (bottom cap bulges +x,
  top -x), dotted right half = 9 dots r0.75
  pitch 3 from the 3 o'clock anchor (QPainterPath
  ellipse stroke modeled as starting at angle 0 —
  PHASE ASSUMED, refine against a live render
  someday), text 9px semibold clamped 2 chars.
- Selection laws: history.SendStateIcon(out,
  sending, unread) = bottom_info.cpp 287-300
  (OutLayout gates; sending clock, unread single,
  else double); dialogs.SendStateIcon(state);
  BadgeReaction split from BadgeMention (mention
  wins when both, Ayu ternary). Painter wiring:
  paintMessage feeds item.Out to TimeLabel and
  fillGlyphs the icon at iconX/iconY (Item gains
  Sending/Unread).
- RED 8 tests -> 2 spec errors fixed by the
  measurement (my dot-x arithmetic 10.622 vs
  real 10.566; Icon struct not comparable ->
  zero-check helper). GREEN 186 PASS (137 ui +
  43 gui). d8eedff -> verify 42454857199 SUCCESS
  (3 jobs, all steps, release-tag step skipped
  by design on main).

## Session 385 — the complex bubble paint leg: op model + painter wiring (2026-11-08)

- VM survived the whole session (first since
  wipe #9); repo booted at 9c248ea == origin.
- Flare shape measured to the mask source:
  createInvertedCircleMask(2r) = filled square
  MINUS centered disc (style_core.cpp:164-178),
  quartered by PrepareInvertedCornerPixmaps
  (cached_round_corners.cpp:246-262); cut lands
  at the disc-center corner of each drawn
  quadrant — top-left flare cuts bottom-right,
  top-right cuts bottom-left, bottom-left cuts
  top-right, bottom-right cuts top-left; flare
  squares inv x inv at (x-inv,side-y)/(x+w,
  side-y), side-y = top or bottom-inv. Gio
  paths: MoveTo(neighbor1) ArcTo(cut corner as
  center, +-pi/2 by sweep) LineTo(opposite)
  Close; +pi/2 sweeps up->right->down->left
  (screen), the only -pi/2 is cut-bottom-right.
- Op model: per part ONE fill with side-rounded
  corners (10 where Rounded, 0 else) — Go-native
  equivalent of Ayu corner pixmaps + middle
  fill, identical coverage; then top flares
  (L,R), then bottom flares (L,R). No op
  overlaps (flares sit outside part rects).
- ServiceBubbleRadii(fontH): normal=(3+fontH+4)
  /2, inverted=fontH-normal, shrink=2*inv/3 —
  the 384 token consts are the fontH=13 case
  (invariant-tested). PartsFont walk generalizes
  heights+shrink to measured svcH (render leg
  measures real fonts; 13-delegation intact).
- Painter: shape() now collects per-line ends
  (lineEnds), shapeLineWidths clamps >=0; add
  decision on RAW widths (call site 784-788),
  CountServiceLineWidths normalizes, PartsFont
  at svcH; parts y translated by g.Top-
  marginTop (Ayu p.translate 790-799); badge
  anchors on RAW lineWidths.back() with lines
  count (818-836). ServicePill code path
  replaced — single line IS the degenerate parts
  walk (identical geometry; empty text now
  paints nothing, matching Ayu's zero-iteration
  loop). bubblePath refactored onto shared
  openCornersPath (tails unchanged).
- RED 8 tests -> 1 spec error (nil-vs-empty
  again; law won). GREEN 178 PASS (135 ui + 43
  gui). b91b7c9 -> verify 42451027930 success
  (3 jobs, all steps, job AND step reconciled).

## Session 384 — the multi-line service complex bubble law (2026-11-08)

- Boot: wipe #11. Clone at bcf2757 — 379-383
  closed green in lost sessions; baseline 159
  re-verified after env rebuild.
- Law source: history_view_service_message.cpp
  372-485 + chat_style.cpp 103-126 + call site
  780-798 (detail in git + service_bubble.go
  tests): radii 10/3/2 DERIVED from pad/font
  pins; CountServiceLineWidths minDelta-22
  neighbor raise + i-=2 rewalk + post-add;
  call-site add 9 iff clamped back > badge
  additional && < before; parts walk (richW
  +24, richH +3/-4/+4/-3 by sides, forceShrink
  on prevShrink+equal, shrink x+=2 w-=4, C++-
  trunc centering = Go native). RED 11 -> 2
  spec errors (law won). 170 PASS; e21f207;
  verify 42448242342 SUCCESS job+step.

## Session 383 — the message-bubble render leg: corner/tail/shadow laws, chat Elm + ChatPainter (2026-11-07)

- Boot: wipe #10. Clone at 8b2ae432 (379-382
  closed green in lost sessions; baseline
  re-verified after env rebuild).
- Pins (laws live in ui/history + tests, detail
  in git): corner law message.cpp:6626-6651
  (attachedTop/Bottom small the wall-side
  corners, tail on layout-side bottom,
  Large=16/Small=6/Tail->0, removeMessageTail
  off by default Tail->Large); tail glyph 6x10
  right triangle; shadow strip 2px
  #748ea2@0x29 / #3ac346@0x1d; time label
  message.cpp:5479-5516 (send-state 24px,
  anchor (-17,-19)); chat mode wide >= 880;
  ChatPainter TD skip-block emulation + body
  wrap approximation documented for the text-
  engine slice; Material skin colors.
- 18 tests, 159 total; 4fdc467c -> verify
  42409023939 SUCCESS job+step.

## Session 382 — the history element geometry law: margins, bubble, service (2026-11-07)

- Boot: wipe #9. Clone at 874f707f (379-381
  closed green in lost sessions; baseline
  re-verified after env rebuild).
- Pins (full derivation in ui/history/element.go
  + its tests, sources cited in git): message
  top margin = attached?0:6 + BARS SURVIVE HIDDEN
  + servicePre-above + added; bottom 2 + below-
  servicePre (hidden 0). Service margins 10/2,
  servicePre unconditional, two-small-margins −20
  floor 25 quirk, Wide min(w,542). Skip block
  12+infoW−2 / fontH−5. textW = max(w,160)−22;
  optimal/limit/clamp chain per message.cpp
  1347/5648/5668/6680-6935. DateBadge 10+3+font+
  4+2; Ayu time badge w+14/h+4/additional w+13.
  Text engine deferred like icon paint (Text
  struct with HeightFor closure).
- RED 14 -> GREEN first run (2 slips caught at
  design). 141 total; 3a655338 -> verify
  42384001792 SUCCESS job+step.

## Session 381 — kinetic touch + overscroll anim: fling, rubber band, spring return (2026-11-07)

- Flick law (touchUpdateSpeed per-axis px/s),
  rubber-band overscroll (elastic_scroll.cpp,
  pins in dialogs kinetic code + tests),
  spring return anim; bar-drag overscroll
  range-clamp landed (deferred from 380).
  13 tests, 112 total; ac999d75; verify
  42372859307 SUCCESS job+step.

## Session 380 — the window-adapter input leg: wheel, hit-test, bar drag, touch (2026-11-07)

- Wheel law (ui_utility.cpp:268-288 + elastic_scroll
  :926-945, pins in dialogs/window code + tests):
  angle→px = angle×lines/(2×3) qRound'd; per-axis
  Ctrl/Shift mult max(w|h,120)/120 TRUNCATED (y by
  scroll HEIGHT); cross-axis |px|>=|py| ignores;
  dy = −pixels.y; pixel path qRound through the same
  block. Bar: 10dp-strip hit test, off-thumb press
  = jump-to-middle, drag dy×scrollable/outsideBar.
  Touch: manhattan>=10 arms 1:1 (arm swallows the
  crossing delta — 381 corrected), tap selects at
  release. 6 Elm messages + Model states; PaintPane
  event.Op; window pointer.Filter + Metric px→dp.
  18 tests, 99 total; e30bbfad; verify 42362009163
  SUCCESS job+step.

## Session 379 — the dialogs list Elm+render leg: viewport state, scroll laws, Pane snapshot, PaintPane (2026-11-07)

- Wheel apply = tryScrollTo(from+delta), delta =
  −pixels.y, rest clamp [0, content−view]; load-more
  on every viewport msg while loadTill >= content
  (empty list = initial page request — resize pin
  updated accordingly). dialogs.Pane + List.Pane(v,
  width) snapshot; Elm Model.DialogsScroll + clamp
  on Loaded/Resized; render.PaintPane (viewport
  clip, per-row offset, thumb rrect). 5 spec cases
  fell to the law. 9 tests, 81 total; shipped
  239cdaf1, verify 42351344419 SUCCESS job+step.

## Session 378 — wipe #5 boot + the dialogs list scroll law: viewport, virtualization, reveal, thumb (2026-11-07)

- Discovery: dialogs list = Ui::ElasticScroll
  (not ScrollArea) — thumb law elastic_scroll.cpp:
  131-175. dialogs/scroll.go: Viewport, MaxOffset/
  Clamp, VisibleRows (1px-overlap lower_bound +
  walk), PreloadWindow 3 screens, ScrollToReveal,
  Thumb (skip 6, thickness 4, barMin min(40,avail/
  2), hide rules, ratio cut-clamp). 12 tests, 72
  total; e38052c2; verify 42347578779 SUCCESS.

## Session 377 — the dialogs row widget: pure layout + Elm state + gio render (2026-11-07)

- dialogs Entry+Layout (name-rect shrink date+5 ->
  chat icon+3 -> send state -20; badge stack
  right-anchored max-2; variants 62/72/80/96; online
  43/43 TTL 36/36); Elm selection clamp; render
  Painter (bg states, photo/userpic, presence dot,
  elided labels, counter pill); icon glyphs
  deferred. 11 ui + 1 gui; gates clean.

## Session 376 — wipe #4 boot: env rebuilt; Material theme system (M3 baseline + AMOLED) (2026-11-07)

- ui/material Scheme 36 roles Light/Dark/Amoled
  (Compose material3 v0_210); dialogs-row slice 5
  pins; TTL-pos test caught a real porting bug.

## Session 375 — the Gio skeleton: Elm core, window adapter, the measured pane law; the cgo-closure fight (2026-11-06)

- go/ui/app Elm core (zero Gio) + pane law
  (computeColumnLayout); window adapter; gioui
  Xlib cgo closure -> gate.sh windows-vet
  substitute; flake green 75944429.

## Session 374 — geometry-table slice 4 re-mined after a full-wipe recycle (2026-11-06)

- Re-derivation converged 23/23; pins in tokens.go
  + tests; CI 42187083372 SUCCESS; T-2 closed.
