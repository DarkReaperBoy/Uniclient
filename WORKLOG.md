# WORKLOG.md — the state file

Top: the **STATE block** — rewritten every session, the resume pointer for the next
agent. Then open items (severity order), then entries newest-first, terse (did /
evidence / next). The pre-2026-11-01 progress docs (BUGS.md, research/) were purged by
owner order — that history lives in git if ever needed.

## STATE

- front: session 387 — the dialogs row
  painter leg landed as 60467393 (ChatTypeIcon/
  BadgeIcon selection laws feeding
  Metrics.ChatTypeIconW from the asset canvases;
  glyphs painted at layout cells with in-cell
  offsets; pinned badge right-aligned to its
  20px canvas; Material ink mapping from
  colors.palette + night theme; narrow icon
  badges as empty-text unread pills with
  centered glyphs; TTL corner badge over the
  blurred userpic cutout — StackBlur exact port
  radius 24, WCAG contrast darken x4/5,
  FormatTTLTiny thresholds + 2-rune clamp,
  timer per the 386 spec; info-block width law:
  history.InfoWidth reserves the 24px ticks
  space for out-or-sending, skip + TimeLabel
  derive from it); first CI run failed the Nix
  go-modules FOD (new vendored package
  x/image/draw), vendorHash rotated in 70600653;
  verify 42461470926 SUCCESS at job AND step
  level — closed green
- next: chat-leg scroll input (wheel/touch —
  the dialogs kinetic laws apply; chat pane
  rides on ui/dialogs kinetic.go + scroll.go
  laws); after that: history entry composing
  (dates/divider service messages over the 384/
  385 service bubble machinery)
- owner-waiting: none
- last-gate: quick GREEN (153 ui + 43 gui = 196
  PASS; windows-vet substitute for render/window/
  cmd); comment ban clean; CI 42461470926
  success (3 jobs, all steps; release-tag step
  skipped by design on main)

## Open items

| ID | where | what | evidence | next step |
|---|---|---|---|---|
| H-2 | verify/release yml | android APK + web (gh-pages) + Xvfb GUI legs parked until the new GUI | AGENTS.md §6/§8 | re-add with the GUI build (owner order pending) |
| H-3 | engine/cores API | 301+1 identifiers exported purely for the tests move (API noise: TsParseInit1, TsTrackRecvPID; audio's MicStop folded to micStop in session 368) | commit 27faa5a4, session 368 | fold into real APIs or de-export when tests are reworked during the GUI rebuild |

## Session 387 — the dialogs row painter leg (2026-11-08)

- VM wiped a 12th time; full recovery per
  scripts/env.sh (clone f1c181db == origin —
  the carried summary was STALE, 385 AND 386
  had closed green in lost sessions; WORKLOG
  arbitrated as always). Baseline re-verified:
  186 PASS (143 ui + 43 gui; total is the
  authority, the 386 last-gate split 137/43
  counted differently).
- Selection laws (dialogs_layout.cpp:612-617 +
  dialogs.style + PaintBadges):
  dialogs.ChatTypeIcon(t) -> DialogsBot/
  Channel/Forum (zero Icon for plain),
  dialogs.BadgeIcon(kind) -> Pinned/Mention/
  Reaction/Poll. Painter feeds
  Metrics.ChatTypeIconW = icon.Cell.W (bot 17 /
  channel 15 / forum 20) so the name advances by
  the true canvas + skip 3; glyphs paint at
  layout cells via fillGlyph cell offsets.
- Pinned law fix (dialogs_layout.cpp:245-248):
  right - icon.width() at textTop — the cell is
  the 20px pinned canvas (was the 18px icon
  size); advance 20+5.
- Ink mapping (colors.palette + night theme):
  chat-type OnSurface (dialogsChatIconFg =
  dialogsNameFg), sending clock OnSurfaceVariant
  (#c1c1c1 / #647d96), ticks Primary (day green
  #5dc452 / night blue #72bcfd — theme-split
  accent), pinned OnSurfaceVariant
  (dialogsUnreadBgMuted), wide mention Primary
  (#40a7e3), reaction Error (#e05356), poll
  Tertiary (#997be1); active rows repaint every
  glyph OnPrimaryContainer (dialogsNameFgActive).
- Narrow icon badges (unread_badge_paint.cpp):
  empty-text PaintUnreadBadge = 19x19 circle
  pill, bg by sizeId (mention dialogsUnreadBg ->
  Primary, reaction dialogsDraftFg -> Error,
  poll dialogsPollIconFg -> Tertiary), glyph
  centered paintInCenter with on-ink. The 13x13
  badge-variant glyph set is NOT traced (386
  delivered one 18x18 set) — refinement
  candidate, noted here.
- TTL badge (dialogs_row.cpp:182-236): StackBlur
  = exact port of lib_ui image_prepare.cpp:679
  (radius 24, guard w<=r returns source);
  TTLBackdrop = crop of the blurred userpic,
  average color vs white via the WCAG
  CountContrast port (color_contrast.cpp), below
  4.5:1 darkens x4/5 in wide ints; source =
  photo-size NRGBA, row bg flattened under the
  circle-masked userpic (GenerateUserpicImage
  law: paintCircle over transparent, flattened
  over background); draw = ellipse clip +
  affine; timer in the 2px-inset inner rect
  (dialogsTTLBadgeInnerMargins), 386 arc/dots
  spec, FormatTTLTiny (format_values.cpp:482-495:
  h<=9h, d<=6d, w<=3w, m<=11m, round-y<=366d,
  {count}h/d/w/m/y — threshold crossings land on
  "0d"-style units, 11m clamps to "11") +
  TimerClamp 2 runes; premium white ink.
- Info-block width law (bottom_info.cpp:181-183,
  704-707): history.InfoWidth(dateW, hasTicks)
  adds HistorySendStateSpace 24 for out-or-
  sending; paintMessage derives skipW from it
  and passes hasTicks to TimeLabel.
- RED 10 tests -> 1 real bug caught (uint8
  c*4/5 WRAPS: 255*4=252 -> 50; widen to int —
  exactly what the discipline is for) + test
  name/dot-import churn. GREEN 196 PASS (153 ui
  + 43 gui). Headless smoke: 5 row variants x
  3 states painted without panics.
- 60467393 -> verify 42460502962 FAILED the Nix
  job only (go-modules FOD hash mismatch: the
  new x/image/draw IMPORT grew the go mod vendor
  package set; module x/image v0.26.0 itself
  unchanged). vendorHash rotated to the reported
  sha256-alPAl... in 70600653 -> verify
  42461470926 SUCCESS, 3 jobs, all steps
  reconciled (Nix lockless run + nix build both
  green).

## Session 386 — the Material icon asset library (2026-11-08)

- Canvas law (codegen_style parsed_file.cpp:967-969 + lib_ui MonoIcon): icon part point(x,y) = QMargins(x,y,0,0) — glyph at cell+(x,y), canvas = mask + point; SVG -WxH renders the FULL viewBox into WxH (chatlist 72 -> 18, scale 0.25); PNG coverage = blue channel (blue>127 at @3x, RDP eps 0.75@3x, /3 grid; crack-boundary walk; contour order = component scan then area-desc, holes wind opposite); SVG legs absolute M/L/C/Z flatten, 12 samples/cubic; IoU vs @2x 0.886-0.957; @3x is the trace source (per-DPI hand-tuned bboxes, pinned).
- 13 glyphs: bot 16x11@(1,3)->17x14, channel 12x11@(3,4)->15x15, forum 19x10@(1,4)->20x14, dialogs sending 11x11@(8,4)->19x15 / sent 12x10@(10,4)->22x14 / received 17x10@(5,4)->22x14, pinned 20x20, chatlist 18x18 x3 (mention/reaction/poll), history sending 11x11@(5,5)->16x16 / sent 13x11@(2,4)->15x15 / received 18x11@(2,4)->20x15.
- TTL timer (ttl_icon.cpp): pen 1.5 round, solid LEFT half-arc 90..270deg one annulus contour with round caps (bottom cap bulges +x, top -x), dotted right half 9 dots r0.75 pitch 3 anchored 3 o'clock (QPainterPath phase ASSUMED — refine vs a live render someday), text 9px semibold clamped 2 chars.
- Selection laws: history.SendStateIcon(out, sending, unread) = bottom_info.cpp 287-300; dialogs.SendStateIcon(state); BadgeReaction split from BadgeMention (mention wins when both). paintMessage feeds Out to TimeLabel + fillGlyphs the icon at iconX/iconY (Item gains Sending/Unread).
- RED 8 -> 2 spec errors fixed by measurement. GREEN 186. d8eedff -> verify 42454857199 SUCCESS (3 jobs, all steps). Detail: git d8eedff5 + this file's history.

## Session 385 — the complex bubble paint leg: op model + painter wiring (2026-11-08)

- Flare shape (style_core.cpp:164-178 + cached_round_corners.cpp:246-262): createInvertedCircleMask(2r) = filled square MINUS centered disc, quartered; cut lands at the disc-center corner of each drawn quadrant (top-left flare cuts bottom-right etc.); flare squares inv x inv at (x-inv, side-y)/(x+w, side-y), side-y = top or bottom-inv. Gio: MoveTo(neighbor1) ArcTo(cut corner, +-pi/2 by sweep) LineTo(opposite) Close; the only -pi/2 is cut-bottom-right.
- Op model: per part ONE fill with side-rounded corners (10 where Rounded, 0 else; Go-native corner-pixmap equivalent); then top flares (L,R), bottom flares (L,R); no op overlaps. ServiceBubbleRadii(fontH) = the 384 consts generalized (invariant-tested at 13). Painter: per-line shape ends >=0 clamped, add decision on RAW widths, PartsFont at measured svcH, parts y by g.Top-marginTop, badge on RAW lineWidths.back(); ServicePill = degenerate parts walk (identical geometry); bubblePath onto shared openCornersPath.
- RED 8 -> 1 spec error (nil-vs-empty; law won). GREEN 178. b91b7c9 -> verify 42451027930 success (3 jobs, job AND step reconciled). Detail: git b91b7c9a + this file's history.

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
