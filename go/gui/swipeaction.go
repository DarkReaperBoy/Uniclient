package gui

// Swipe quick actions (slice 158, tdesktop dialogs_quick_action /
// swipe_handler 1:1): a horizontal drag on a chat-list row slides the row
// and reveals a colored action strip behind it; releasing past the 50dp
// threshold fires the configured quick action. Mirrors tdesktop:
//
//   - gesture: direction lock when |dx|-|dy| > 1px; threshold 50dp (scaled);
//     ratio = dx/threshold clamped to [0, 1.5]; overswipe translation is
//     logarithmically damped; release at ratio >= 1 fires; the row snaps
//     back with a short ease-out animation.
//   - actions: one user-configurable action (Settings → Chat → Quick
//     actions): Mute / Pin / Read / Archive / Delete / Disabled (tdesktop
//     default: Disabled), each with a state-aware label
//     (Mute↔Unmute, Pin↔Unpin, Read↔Unread, Archive↔Unarchive).
//   - visuals: strip background = accent (windowBgActive) for most
//     actions, attention red for Delete, gray for Disabled; icon +
//     shrinking label (tdesktop SwipeActionFont 13→5 stepping); a reach
//     circle grows behind the icon once the threshold is crossed
//     (tdesktop animationReach affordance).
//   - swipe the OTHER way (finger left): swipe-back navigation — leaves
//     the archive view / the folder tab (tdesktop closes folders/forums
//     and shows the main menu).
//
// The overlay is pass-through (rows keep hover/clicks; the list keeps
// wheel scrolling) exactly like the message-list rubber-band (slice 84).

import (
	"image"
	"math"
	"time"

	"gioui.org/io/event"
	"gioui.org/io/pointer"
	"gioui.org/layout"
	"gioui.org/op"
	"gioui.org/op/clip"
	"gioui.org/op/paint"
	"gioui.org/unit"
	"gioui.org/widget"

	"image/color"

	"uniclient/engine"
)

// swipeActionThreshold is the drag distance that fully reveals the strip
// (tdesktop kThresholdWidth, 50px scaled).
const swipeActionThreshold = unit.Dp(50)

// swipeMaxRatio caps the tracked drag ratio (tdesktop kMaxRatio 1.5).
const swipeMaxRatio = float32(1.5)

// swipeOverswipeLogA/B shape the logarithmic damping curve past the
// threshold (tdesktop DampedOverswipe).
const (
	swipeOverswipeLogA = float32(16.0)
	swipeOverswipeLogB = float32(10.0)
)

// swipeBackDuration is the snap-back animation length (tdesktop
// slideWrapDuration ballpark).
const swipeBackDuration = 220 * time.Millisecond

// swipeDirLock decides the gesture axis from cumulative deltas: 1 while
// dragging right, -1 while dragging left, 0 = undecided/vertical.
// Pure — locked by tests.
func swipeDirLock(dx, dy float32) int {
	d := math.Abs(float64(dx)) - math.Abs(float64(dy))
	if d > 1 {
		if dx < 0 {
			return -1
		}
		return 1
	}
	return 0
}

// swipeRatio is the normalized drag progress in [0, 1.5]. Negative drags
// clamp at zero (dragging back cancels). Pure — locked by tests.
func swipeRatio(dx float32, thr float32) float32 {
	if thr <= 0 {
		return 0
	}
	r := dx / thr
	if r < 0 {
		return 0
	}
	if r > swipeMaxRatio {
		return swipeMaxRatio
	}
	return r
}

// swipeTranslation converts the ratio into the row's pixel shift: linear
// up to the threshold, then logarithmically damped overswipe (tdesktop
// DampedOverswipe: A·ln(1 + shift/B) — the row visibly resists past
// 100%). Pure — locked by tests.
func swipeTranslation(ratio float32, thr float32) float32 {
	if ratio <= 0 || thr <= 0 {
		return 0
	}
	linear := ratio
	if linear > 1 {
		linear = 1
	}
	shift := linear * thr
	if over := ratio - 1; over > 0 {
		overswipeShift := float64(over) * float64(thr)
		damped := float64(swipeOverswipeLogA) * math.Log(1+overswipeShift/float64(swipeOverswipeLogB))
		shift += float32(damped)
	}
	return shift
}

// swipeFires reports whether releasing at this ratio triggers the action
// (tdesktop: ratio >= 1). Pure — locked by tests.
func swipeFires(ratio float32) bool { return ratio >= 1 }

// swipeBackCommand maps a leftward swipe to a navigation command:
// "archive" leaves the archived-chats view, "folder" clears the folder
// tab, "" does nothing (tdesktop swipe-back closes folders/forums/menu).
// Pure — locked by tests.
func swipeBackCommand(archiveView bool, folderOpen bool) string {
	switch {
	case archiveView:
		return "archive"
	case folderOpen:
		return "folder"
	}
	return ""
}

// swipeAct is the resolved, state-aware swipe action for one row.
type swipeAct struct {
	kind  string // "" when disabled; else "mute"|"pin"|"read"|"archive"|"delete"
	label string // rendered in the strip
	done  string // success toast
	icon  swipeIcon
	red   bool // delete → attention red strip
	gray  bool // disabled → gray strip
}

// swipeIcon adapts *widget.Icon to the iconDrawer interface used below.
type swipeIcon struct {
	w *widget.Icon
}

func (s swipeIcon) Layout(gtx layout.Context, col color.NRGBA) layout.Dimensions {
	if s.w == nil {
		return layout.Dimensions{}
	}
	return s.w.Layout(gtx, col)
}

// resolveSwipeAction maps the configured action onto one chat row's
// current state (tdesktop ResolveQuickDialogLabel). Pure — locked by tests.
func resolveSwipeAction(cfg string, c engine.ChatInfo, archiveView bool) swipeAct {
	switch cfg {
	case "mute":
		if c.IsMuted {
			return swipeAct{"mute", "Unmute", "Unmuted", swipeIcon{iconSocialNotif}, false, false}
		}
		return swipeAct{"mute", "Mute", "Muted", swipeIcon{iconSocialNotifOff}, false, false}
	case "pin":
		if c.IsPinned {
			return swipeAct{"pin", "Unpin", "Unpinned", swipeIcon{iconActionOfflinePin}, false, false}
		}
		return swipeAct{"pin", "Pin", "Pinned", swipeIcon{iconActionOfflinePin}, false, false}
	case "read":
		if c.UnreadCount > 0 || c.UnreadMark {
			return swipeAct{"read", "Mark as read", "Marked as read", swipeIcon{iconActionCheckCircle}, false, false}
		}
		return swipeAct{"read", "Mark as unread", "Marked as unread", swipeIcon{iconContentMarkUnread}, false, false}
	case "archive":
		if archiveView || c.IsArchived {
			return swipeAct{"archive", "Unarchive", "Unarchived", swipeIcon{iconMgrUnarchive}, false, false}
		}
		return swipeAct{"archive", "Archive", "Archived", swipeIcon{iconMgrArchive}, false, false}
	case "delete":
		return swipeAct{"delete", "Delete", "Deleted", swipeIcon{iconActionDelete}, true, false}
	}
	// Disabled / unknown / empty config (tdesktop default is Disabled).
	return swipeAct{"", "Disabled", "", swipeIcon{iconContentClear}, false, true}
}

// swipeLabelSize steps the strip label font down to fit the revealed
// width (tdesktop SwipeActionFont: 13px semibold shrinking to 5px min).
// Pure — locked by tests.
func swipeLabelSize(revealDp float32) int {
	for sp := 14; sp > 5; sp-- {
		// ~0.62dp average glyph advance at size sp.
		if revealDp >= float32(sp)*7 {
			return sp
		}
	}
	return 5
}

// ── gesture state (frame-loop only, like the rubber-band) ───────────────

var swipeTag = new(struct{})

type swipeGesture struct {
	on         bool
	row        int // visible-row index under the press (-1 = none)
	dir        int // 1 right / -1 left once locked
	startX     float32
	startY     float32
	curX       float32
	ratio      float32
	anim       bool // snap-back animation running
	animT      time.Time
	animFrom   float32 // ratio at release
	thr        float32 // threshold in px this gesture
	backReveal float32 // leftward drag progress [0,1] (swipe-back hint)
}

var swipeG swipeGesture

// swipeRowVisual computes the current render state for a row index from
// the gesture: pixel shift, drag ratio, and whether this row is swiping.
func swipeRowVisual(row int, thr float32) (shift float32, ratio float32, active bool) {
	if swipeG.row != row || swipeG.row < 0 {
		return 0, 0, false
	}
	if swipeG.on {
		if swipeG.dir != 1 {
			return 0, 0, false
		}
		return swipeTranslation(swipeG.ratio, swipeG.thr), swipeG.ratio, true
	}
	if swipeG.anim {
		elapsed := time.Since(swipeG.animT)
		if elapsed >= swipeBackDuration {
			swipeG.anim = false
			return 0, 0, false
		}
		progress := float32(elapsed) / float32(swipeBackDuration)
		eased := 1 - (1-progress)*(1-progress) // ease-out quad
		r := swipeG.animFrom * (1 - eased)
		return swipeTranslation(r, swipeG.thr), r, true
	}
	return 0, 0, false
}

// swipeBackReveal reports the leftward-drag progress for the swipe-back
// hint arrow (0 when not dragging left).
func swipeBackReveal() float32 {
	if swipeG.on && swipeG.dir == -1 {
		return swipeG.backReveal
	}
	return 0
}

// processSidebarSwipe registers the pass-through swipe input over the
// chat list and drives the gesture. Called AFTER the list laid out (row
// bounds are current). size is the list area's size in pane space.
func (a *App) processSidebarSwipe(gtx layout.Context, f frame, size image.Point) {
	// Search-results mode has no chat rows to swipe.
	plainList := f.search == ""
	if plainList {
		defer pointer.PassOp{}.Push(gtx.Ops).Pop()
		stack := clip.Rect{Max: size}.Push(gtx.Ops)
		event.Op(gtx.Ops, swipeTag)
		stack.Pop()
	}

	for {
		ev, ok := gtx.Source.Event(pointer.Filter{
			Target: swipeTag,
			Kinds:  pointer.Press | pointer.Drag | pointer.Release | pointer.Cancel,
		})
		if !ok {
			break
		}
		e, is := ev.(pointer.Event)
		if !is || !plainList {
			continue
		}
		switch e.Kind {
		case pointer.Press:
			if e.Buttons != pointer.ButtonPrimary {
				continue
			}
			pos := e.Position.Round()
			swipeG.on = true
			swipeG.dir = 0
			swipeG.row = -1
			swipeG.startX = e.Position.X
			swipeG.startY = e.Position.Y
			swipeG.curX = e.Position.X
			swipeG.ratio = 0
			swipeG.backReveal = 0
			swipeG.thr = float32(gtx.Metric.Dp(swipeActionThreshold))
			for idx, r := range a.chatRowBounds {
				if pointInRect(pos, r) && idx >= 0 && idx < len(a.sbVisible) {
					swipeG.row = idx
					break
				}
			}
		case pointer.Drag:
			if !swipeG.on {
				continue
			}
			swipeG.curX = e.Position.X
			dx := swipeG.curX - swipeG.startX
			dy := e.Position.Y - swipeG.startY
			if swipeG.dir == 0 {
				swipeG.dir = swipeDirLock(dx, dy)
			}
			switch swipeG.dir {
			case 1:
				if swipeG.row >= 0 {
					swipeG.ratio = swipeRatio(dx, swipeG.thr)
				}
			case -1:
				reveal := -dx / swipeG.thr
				if reveal < 0 {
					reveal = 0
				}
				if reveal > 1 {
					reveal = 1
				}
				swipeG.backReveal = reveal
			}
			gtx.Execute(op.InvalidateCmd{})
		case pointer.Release, pointer.Cancel:
			if !swipeG.on {
				continue
			}
			if e.Kind == pointer.Release {
				if swipeG.dir == 1 && swipeG.row >= 0 && swipeFires(swipeG.ratio) {
					a.performSwipeAction(f, swipeG.row)
				} else if swipeG.dir == -1 && swipeBackReveal() >= 1 {
					if cmd := swipeBackCommand(f.archiveView, f.folder != 0); cmd != "" {
						a.runSwipeBack(cmd)
					}
				}
			}
			// Snap back: animate the strip closed, then clear.
			swipeG.anim = swipeG.dir == 1 && swipeG.row >= 0 && swipeG.ratio > 0.02
			swipeG.animT = time.Now()
			swipeG.animFrom = swipeG.ratio
			swipeG.on = false
			swipeG.ratio = 0
			gtx.Execute(op.InvalidateCmd{})
		}
	}

	if swipeG.anim && time.Since(swipeG.animT) >= swipeBackDuration {
		swipeG.anim = false
	}
	if swipeG.on || swipeG.anim {
		gtx.Execute(op.InvalidateCmd{})
	}
}

// runSwipeBack executes a leftward-swipe navigation command.
func (a *App) runSwipeBack(cmd string) {
	switch cmd {
	case "archive":
		a.exitArchive() // same as Esc in the archived view (slice 67)
	case "folder":
		a.mu.Lock()
		a.folder = 0 // back to the All tab
		a.mu.Unlock()
		a.invalidate()
	}
}

// performSwipeAction runs the resolved action against the engine and
// toasts the outcome (tdesktop PerformQuickDialogAction).
func (a *App) performSwipeAction(f frame, row int) {
	if row < 0 || row >= len(a.sbVisible) {
		return
	}
	c := a.sbVisible[row]
	act := resolveSwipeAction(f.cfg.SwipeAction, c, f.archiveView)
	if act.kind == "" {
		return
	}
	acct, id := c.AccountID, c.ChatID
	go func() {
		var err error
		switch act.kind {
		case "mute":
			err = a.eng.MuteChat(acct, id, !c.IsMuted, 0)
		case "pin":
			err = a.eng.PinChat(acct, id, !c.IsPinned)
		case "read":
			if c.UnreadCount > 0 || c.UnreadMark {
				err = a.eng.MarkChatRead(acct, id, "")
			} else {
				err = a.eng.MarkChatUnread(acct, id)
			}
		case "archive":
			err = a.eng.ArchiveChat(acct, id, !(c.IsArchived || f.archiveView))
		case "delete":
			err = a.eng.DeleteChat(acct, id, false)
		}
		if err != nil {
			a.setToast("Swipe action: " + err.Error())
			return
		}
		a.setToast(act.done)
		a.refreshChats()
	}()
}

// paintSwipeStrip paints the revealed action strip for a sliding row:
// colored background, reach circle, icon, and the shrinking label. The
// strip occupies [0, w) of the row; the body slides right over it.
func (a *App) paintSwipeStrip(gtx layout.Context, act swipeAct, w int, rowH int, ratio float32) {
	if w < 2 {
		return
	}
	bg := a.ui.p.Accent
	if act.red {
		bg = rgb(0xD32F2F) // tdesktop attentionButtonFg
	} else if act.gray {
		bg = a.ui.p.TextFaint
	}
	rect := clip.Rect{Max: image.Pt(w, rowH)}
	stack := rect.Push(gtx.Ops)
	paint.FillShape(gtx.Ops, bg, rect.Op())

	// Reach circle (tdesktop animationReach): grows once the threshold
	// is crossed — the "armed" affordance.
	if ratio >= 1 {
		grow := ratio - 1
		if grow > 0.5 {
			grow = 0.5
		}
		r := int(float32(rowH) * (0.22 + 0.3*grow))
		if r > 0 {
			cx, cy := w/2, rowH/2
			circle := clip.UniformRRect(image.Rectangle{
				Min: image.Pt(cx-r, cy-r),
				Max: image.Pt(cx+r, cy+r),
			}, r)
			cstack := circle.Push(gtx.Ops)
			paint.Fill(gtx.Ops, withAlpha(rgb(0xFFFFFF), 0x28))
			cstack.Pop()
		}
	}
	stack.Pop()

	// Icon + label stacked at the strip's center.
	cs := gtx.Constraints
	gtx.Constraints = layout.Constraints{Max: image.Pt(w, rowH)}
	defer func() { gtx.Constraints = cs }()
	layout.Stack{Alignment: layout.Center}.Layout(gtx,
		layout.Stacked(func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Vertical, Alignment: layout.Middle}.Layout(gtx,
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					if act.icon.w == nil {
						return layout.Dimensions{}
					}
					sz := gtx.Dp(unit.Dp(20))
					if act.gray {
						sz = gtx.Dp(unit.Dp(24))
					}
					return layoutIconPx(gtx, act.icon, rgb(0xFFFFFF), sz)
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					if act.label == "" {
						return layout.Dimensions{}
					}
					sp := swipeLabelSize(float32(w) - 6)
					lbl := a.ui.Label(unit.Sp(sp), act.label)
					lbl.Color = rgb(0xFFFFFF)
					return lbl.Layout(gtx)
				}),
			)
		}),
	)
}

// swipeRowShift renders the swiped row: the strip behind plus the body
// shifted right by the current translation. Returns the body's dims.
func (a *App) swipeRowShift(gtx layout.Context, f frame, c engine.ChatInfo, rowIdx int, body func(gtx layout.Context) layout.Dimensions) layout.Dimensions {
	shift, ratio, active := swipeRowVisual(rowIdx, float32(gtx.Metric.Dp(swipeActionThreshold)))
	if !active || shift < 1 {
		// Swipe-back hint arrow during a leftward drag.
		if reveal := swipeBackReveal(); reveal > 0.1 {
			rowH := gtx.Constraints.Max.Y
			rowW := gtx.Constraints.Min.X
			if rowW <= 0 {
				rowW = gtx.Constraints.Max.X
			}
			a.paintSwipeBackHint(gtx, int(float32(48)*reveal), rowH)
		}
		return body(gtx)
	}
	act := resolveSwipeAction(f.cfg.SwipeAction, c, f.archiveView)
	rowH := gtx.Constraints.Max.Y
	rowW := gtx.Constraints.Max.X
	w := int(shift)
	if w > rowW {
		w = rowW
	}
	a.paintSwipeStrip(gtx, act, w, rowH, ratio)
	defer op.Offset(image.Pt(int(shift), 0)).Push(gtx.Ops).Pop()
	return body(gtx)
}

// paintSwipeBackHint draws the back-arrow affordance at the row's left
// edge while dragging leftward (tdesktop swipe-back icon).
func (a *App) paintSwipeBackHint(gtx layout.Context, w, rowH int) {
	if w < 4 || iconNavigationBack == nil {
		return
	}
	// Faded panel + arrow anchored at the left edge.
	rect := clip.Rect{Max: image.Pt(w, rowH)}
	stack := rect.Push(gtx.Ops)
	paint.FillShape(gtx.Ops, withAlpha(a.ui.p.SurfaceHi, byte(0x30+0x60*min(1, float32(w)/48))), rect.Op())
	stack.Pop()
	sz := gtx.Dp(unit.Dp(18))
	if sz > w {
		sz = w
	}
	macro := op.Record(gtx.Ops)
	layoutIconPx(gtx, swipeIcon{iconNavigationBack}, a.ui.p.TextDim, sz)
	op.Defer(gtx.Ops, macro.Stop())
}
