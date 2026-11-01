package gui

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

const swipeActionThreshold = unit.Dp(50)

const swipeMaxRatio = float32(1.5)

const (
	swipeOverswipeLogA = float32(16.0)
	swipeOverswipeLogB = float32(10.0)
)

const swipeBackDuration = 220 * time.Millisecond

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

func swipeFires(ratio float32) bool { return ratio >= 1 }

func swipeBackCommand(archiveView bool, folderOpen bool) string {
	switch {
	case archiveView:
		return "archive"
	case folderOpen:
		return "folder"
	}
	return ""
}

type swipeAct struct {
	kind  string
	label string
	done  string
	icon  swipeIcon
	red   bool
	gray  bool
}

type swipeIcon struct {
	w *widget.Icon
}

func (s swipeIcon) Layout(gtx layout.Context, col color.NRGBA) layout.Dimensions {
	if s.w == nil {
		return layout.Dimensions{}
	}
	return s.w.Layout(gtx, col)
}

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
	return swipeAct{"", "Disabled", "", swipeIcon{iconContentClear}, false, true}
}

func swipeLabelSize(revealDp float32) int {
	for sp := 14; sp > 5; sp-- {
		if revealDp >= float32(sp)*7 {
			return sp
		}
	}
	return 5
}

var swipeTag = new(struct{})

type swipeGesture struct {
	on         bool
	row        int
	dir        int
	startX     float32
	startY     float32
	curX       float32
	ratio      float32
	anim       bool
	animT      time.Time
	animFrom   float32
	thr        float32
	backReveal float32
}

var swipeG swipeGesture

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
		eased := 1 - (1-progress)*(1-progress)
		r := swipeG.animFrom * (1 - eased)
		return swipeTranslation(r, swipeG.thr), r, true
	}
	return 0, 0, false
}

func swipeBackReveal() float32 {
	if swipeG.on && swipeG.dir == -1 {
		return swipeG.backReveal
	}
	return 0
}

func (a *App) processSidebarSwipe(gtx layout.Context, f frame, size image.Point) {
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

func (a *App) runSwipeBack(cmd string) {
	switch cmd {
	case "archive":
		a.exitArchive()
	case "folder":
		a.mu.Lock()
		a.folder = 0
		a.mu.Unlock()
		a.invalidate()
	}
}

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

func (a *App) paintSwipeStrip(gtx layout.Context, act swipeAct, w int, rowH int, ratio float32) {
	if w < 2 {
		return
	}
	bg := a.ui.p.Accent
	if act.red {
		bg = rgb(0xD32F2F)
	} else if act.gray {
		bg = a.ui.p.TextFaint
	}
	rect := clip.Rect{Max: image.Pt(w, rowH)}
	stack := rect.Push(gtx.Ops)
	paint.FillShape(gtx.Ops, bg, rect.Op())

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

func (a *App) swipeRowShift(gtx layout.Context, f frame, c engine.ChatInfo, rowIdx int, body func(gtx layout.Context) layout.Dimensions) layout.Dimensions {
	shift, ratio, active := swipeRowVisual(rowIdx, float32(gtx.Metric.Dp(swipeActionThreshold)))
	if !active || shift < 1 {
		if reveal := swipeBackReveal(); reveal > 0.1 {
			rowH := gtx.Constraints.Max.Y
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

func (a *App) paintSwipeBackHint(gtx layout.Context, w, rowH int) {
	if w < 4 || iconNavigationBack == nil {
		return
	}
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
