package gui

// Passcode editor dialog (slice 87): Privacy & Security → "Passcode
// lock". Set (new + confirm), change (verify current first), disable
// (verify + armed confirm), and the autolock picker (1/5/60 minutes,
// never) applied immediately through engine.UpdatePasscodeConfig. The
// step machine is GUI-loop state; engine persistence runs async with
// honest toasts. Locked by lock_test.go.

import (
	"image"
	"time"

	"gioui.org/io/event"
	"gioui.org/io/key"
	"gioui.org/layout"
	"gioui.org/op/clip"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"
)

// lock dialog steps.
const (
	lockDlgVerify  = 0 // existing passcode: verify before options
	lockDlgOptions = 1 // change / disable / autolock
	lockDlgNew     = 2 // enter the new passcode
	lockDlgConfirm = 3 // re-enter to confirm
)

// lockDlgState is the open passcode editor.
type lockDlgState struct {
	step         int
	digits       int // chosen length for a new passcode
	autolock     int // minutes, live-edited
	input        string
	first        string // candidate from lockDlgNew
	wrong        bool
	wrongCount   int
	frozen       time.Time
	hasLock      bool // passcode already configured
	disableArmed bool
}

var (
	lockDlgTag        = new(struct{})
	lockDlgCancelBtn  widget.Clickable
	lockDlgChangeBtn  widget.Clickable
	lockDlgDisableBtn widget.Clickable
	lockDlgBackBtn    widget.Clickable
	lockDlgDigitsBtns []widget.Clickable
	lockDlgLockBtns   []widget.Clickable // autolock options
)

// openLockDialog opens the passcode editor.
func (a *App) openLockDialog() {
	cur := a.liveLockState()
	dlg := &lockDlgState{hasLock: cur != nil, digits: 4, autolock: 1}
	if cur != nil {
		dlg.step = lockDlgVerify
		dlg.autolock = cur.autolockMin
	} else {
		dlg.step = lockDlgNew
	}
	a.mu.Lock()
	a.lockDlg = dlg
	a.mu.Unlock()
	a.invalidate()
}

// closeLockDialog dismisses the editor.
func (a *App) closeLockDialog() {
	a.mu.Lock()
	a.lockDlg = nil
	a.mu.Unlock()
	a.invalidate()
}

// liveLockState returns the live lock state (nil when unset).
func (a *App) liveLockState() *lockState {
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.lock
}

// lockDlgCaption is the step's prompt. Pure.
func lockDlgCaption(d *lockDlgState, now time.Time) (string, bool) {
	switch d.step {
	case lockDlgVerify:
		if lockDlgFrozen(d, now) {
			return "Too many attempts — wait", true
		}
		if d.wrong {
			return "Wrong passcode", true
		}
		return "Enter current passcode", false
	case lockDlgNew:
		return "Enter new passcode (" + itoa(d.digits) + " digits)", false
	case lockDlgConfirm:
		if d.wrong {
			return "Passcodes differ — re-enter", true
		}
		return "Confirm the new passcode", false
	}
	return "", false
}

// lockDlgFrozen: wrong-attempt cooldown inside the dialog.
func lockDlgFrozen(d *lockDlgState, now time.Time) bool {
	return !d.frozen.IsZero() && now.Before(d.frozen)
}

// lockDlgFeed advances the step machine with one pad key. Returns the
// resulting action ("", "verified", "saved:<pin>", "mismatch"). Pure-ish
// (mutates the dialog state only).
func lockDlgFeed(d *lockDlgState, cur *lockState, k string, now time.Time) string {
	if lockDlgFrozen(d, now) {
		return ""
	}
	if k == "back" {
		if d.input != "" {
			d.input = d.input[:len(d.input)-1]
			d.wrong = false
		}
		return ""
	}
	if len(k) != 1 || k[0] < '0' || k[0] > '9' {
		return ""
	}
	if d.step == lockDlgVerify {
		if len(d.input) >= cur.digits {
			return ""
		}
		d.input += k
		if len(d.input) == cur.digits {
			if pinHashOf(cur.salt, d.input) == cur.hash {
				d.input = ""
				d.wrong = false
				d.wrongCount = 0
				return "verified"
			}
			d.input = ""
			d.wrong = true
			d.wrongCount++
			if d.wrongCount >= maxLockWrong {
				d.wrongCount = 0
				d.frozen = now.Add(lockFreezeSecond)
			}
		}
		return ""
	}
	if d.step == lockDlgNew || d.step == lockDlgConfirm {
		if len(d.input) >= d.digits {
			return ""
		}
		d.input += k
		if len(d.input) == d.digits {
			if d.step == lockDlgNew {
				d.first = d.input
				d.input = ""
				d.step = lockDlgConfirm
				return ""
			}
			if d.input == d.first {
				pin := d.input
				d.input = ""
				d.wrong = false
				return "saved:" + pin
			}
			d.input = ""
			d.wrong = true
			d.step = lockDlgNew // re-enter from the start
		}
	}
	return ""
}

// lockDlgDigitsChanged resets entry state when the length picker moves.
func lockDlgDigitsChanged(d *lockDlgState, n int) {
	if d.digits == n {
		return
	}
	d.digits = n
	d.input = ""
	d.first = ""
	d.wrong = false
}

// applyNewPasscode persists the new passcode and arms the live lock.
func (a *App) applyNewPasscode(pin string, digits, autolockMin int) {
	st := &lockState{
		digits:      digits,
		autolockMin: autolockMin,
		salt:        newLockSalt(),
		locked:      false,
		lastActive:  time.Now(),
	}
	st.hash = pinHashOf(st.salt, pin)
	cfg := st.toConfig()
	go func() {
		if err := a.eng.SetPasscode(cfg); err != nil {
			a.setToast("Passcode: " + err.Error())
			return
		}
		a.mu.Lock()
		a.lock = st
		a.lockDlg = nil
		a.mu.Unlock()
		a.setToast("Passcode enabled")
		a.invalidate()
	}()
}

// disablePasscode removes the vault record and disarms the live lock.
func (a *App) disablePasscode() {
	go func() {
		if err := a.eng.ClearPasscode(); err != nil {
			a.setToast("Passcode: " + err.Error())
			return
		}
		a.mu.Lock()
		a.lock = nil
		a.lockDlg = nil
		a.mu.Unlock()
		a.setToast("Passcode disabled")
		a.invalidate()
	}()
}

// applyAutolock persists the autolock choice for the existing passcode.
func (a *App) applyAutolock(minutes int) {
	go func() {
		if err := a.eng.UpdatePasscodeConfig(map[string]interface{}{"autolock": minutes}); err != nil {
			a.setToast("Auto-lock: " + err.Error())
			return
		}
		a.mu.Lock()
		if a.lock != nil {
			a.lock.autolockMin = minutes
		}
		a.mu.Unlock()
		min := "never"
		if minutes > 0 {
			min = "after " + itoa(minutes) + " min"
		}
		a.setToast("Auto-lock " + min)
		a.invalidate()
	}()
}

// layoutLockDialog renders the passcode editor (content-pane replacement,
// like the other settings dialogs).
func (a *App) layoutLockDialog(gtx layout.Context, f frame) layout.Dimensions {
	d := f.lockDlg
	now := f.now
	if d.step == lockDlgVerify && !a.liveLockState().hasHash() {
		// No armed passcode behind a verify step — start over.
		d.step = lockDlgNew
	}

	// Esc closes; key events feed the pad.
	{
		stack := clip.Rect{Max: image.Pt(gtx.Constraints.Max.X, gtx.Constraints.Max.Y)}.Push(gtx.Ops)
		event.Op(gtx.Ops, lockDlgTag)
		stack.Pop()
	}
	for {
		ev, ok := gtx.Source.Event(key.Filter{})
		if !ok {
			break
		}
		if ke, is := ev.(key.Event); is && ke.State == key.Press {
			name := string(ke.Name)
			switch name {
			case string(key.NameEscape):
				a.closeLockDialog()
			case string(key.NameDeleteBackward):
				if act := lockDlgFeed(d, a.liveLockState(), "back", now); act != "" {
					a.lockDlgAction(act)
				}
			default:
				if len(name) == 1 && name[0] >= '0' && name[0] <= '9' {
					if act := lockDlgFeed(d, a.liveLockState(), name, now); act != "" {
						a.lockDlgAction(act)
					}
				}
			}
		}
	}
	if lockDlgCancelBtn.Clicked(gtx) {
		a.closeLockDialog()
	}

	frozen := lockDlgFrozen(d, now)
	return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		gtx.Constraints.Max.X = gtx.Dp(unit.Dp(360))
		gtx.Constraints.Max.Y = gtx.Dp(unit.Dp(560))
		return roundedFill(gtx, a.ui.p.Surface, 16, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(20)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Vertical, Alignment: layout.Middle}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return a.ui.H3("Passcode Lock").Layout(gtx)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							caption, err := lockDlgCaption(d, now)
							lbl := a.ui.Dim(unit.Sp(12), caption)
							if err {
								lbl.Color = a.ui.p.Error
							}
							return lbl.Layout(gtx)
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if d.step == lockDlgOptions {
							return layout.Dimensions{}
						}
						// Dots mirror the entry for pad steps.
						cur := a.liveLockState()
						n := d.digits
						if d.step == lockDlgVerify && cur != nil {
							n = cur.digits
						}
						return a.pinDots(gtx, n, len(d.input), d.wrong)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						// Digit-length picker (new/confirm steps).
						if d.step != lockDlgNew && d.step != lockDlgConfirm {
							return layout.Dimensions{}
						}
						return a.lockDlgDigitsRow(gtx, d)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if d.step == lockDlgOptions {
							return a.lockDlgOptionsBody(gtx, f, d)
						}
						return layout.Inset{Top: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return a.pinGrid(gtx, frozen, func(k string) {
								if act := lockDlgFeed(d, a.liveLockState(), k, now); act != "" {
									a.lockDlgAction(act)
								}
							})
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						bl := material.Button(a.ui.Theme, &lockDlgCancelBtn, "Close")
						bl.Background = a.ui.p.SurfaceHi
						bl.Color = a.ui.p.Text
						bl.CornerRadius = 10
						return layout.Inset{Top: unit.Dp(12)}.Layout(gtx, bl.Layout)
					}),
				)
			})
		})
	})
}

// lockDlgAction dispatches the step machine's outcomes.
func (a *App) lockDlgAction(act string) {
	switch {
	case act == "verified":
		a.mu.Lock()
		if a.lockDlg != nil {
			a.lockDlg.step = lockDlgOptions
			a.lockDlg.disableArmed = false
		}
		a.mu.Unlock()
	case len(act) > 6 && act[:6] == "saved:":
		a.applyNewPasscode(act[6:], a.lockDlgDigits(), a.lockDlgAutolock())
	}
	a.invalidate()
}

// lockDlgDigits/lockDlgAutolock read the dialog under the mutex.
func (a *App) lockDlgDigits() int {
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.lockDlg == nil {
		return 4
	}
	return a.lockDlg.digits
}

func (a *App) lockDlgAutolock() int {
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.lockDlg == nil {
		return 1
	}
	return a.lockDlg.autolock
}

// lockDlgDigitsRow: 4/5/6 segmented picker.
func (a *App) lockDlgDigitsRow(gtx layout.Context, d *lockDlgState) layout.Dimensions {
	opts := []int{4, 5, 6}
	growClickables(&lockDlgDigitsBtns, len(opts))
	cells := make([]layout.FlexChild, 0, len(opts))
	for i, n := range opts {
		n := n
		btn := &lockDlgDigitsBtns[i]
		if btn.Clicked(gtx) {
			lockDlgDigitsChanged(d, n)
			a.invalidate()
		}
		cells = append(cells, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return segmentChip(gtx, a, btn, itoa(n), d.digits == n)
		}))
	}
	return layout.Inset{Top: unit.Dp(8), Bottom: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle, Spacing: layout.SpaceBetween}.Layout(gtx,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return a.ui.Dim(unit.Sp(12), "Digits").Layout(gtx)
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal, Spacing: layout.Spacing(4)}.Layout(gtx, cells...)
			}),
		)
	})
}

func (a *App) lockDlgAutolockRow(gtx layout.Context, d *lockDlgState) layout.Dimensions {
	opts := []int{1, 5, 60, 0}
	growClickables(&lockDlgLockBtns, len(opts))
	cells := make([]layout.FlexChild, 0, len(opts))
	for i, m := range opts {
		m := m
		btn := &lockDlgLockBtns[i]
		if btn.Clicked(gtx) {
			d.autolock = m
			a.applyAutolock(m)
		}
		label := autolockLabel(m)
		cells = append(cells, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return segmentChip(gtx, a, btn, label, d.autolock == m)
		}))
	}
	return layout.Flex{Axis: layout.Horizontal, Spacing: layout.Spacing(6)}.Layout(gtx,
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.ui.Dim(unit.Sp(12), "Auto-lock").Layout(gtx)
		}),
		layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Horizontal, Spacing: layout.Spacing(4)}.Layout(gtx, cells...)
		}),
	)
}

// autolockLabel renders an autolock choice. Pure.
func autolockLabel(minutes int) string {
	switch minutes {
	case 0:
		return "Never"
	case 60:
		return "1 h"
	default:
		return itoa(minutes) + " min"
	}
}

func (a *App) lockDlgOptionsBody(gtx layout.Context, f frame, d *lockDlgState) layout.Dimensions {
	if lockDlgChangeBtn.Clicked(gtx) {
		a.mu.Lock()
		if a.lockDlg != nil {
			a.lockDlg.step = lockDlgNew
			a.lockDlg.input = ""
			a.lockDlg.first = ""
			a.lockDlg.wrong = false
		}
		a.mu.Unlock()
	}
	if lockDlgDisableBtn.Clicked(gtx) {
		if !d.disableArmed {
			d.disableArmed = true
		} else {
			a.disablePasscode()
		}
	}
	return layout.Flex{Axis: layout.Vertical, Alignment: layout.Middle}.Layout(gtx,
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(6), Bottom: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return a.lockDlgAutolockRow(gtx, d)
			})
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			bl := material.Button(a.ui.Theme, &lockDlgChangeBtn, "Change passcode")
			bl.Background = a.ui.p.Accent
			bl.CornerRadius = 10
			return bl.Layout(gtx)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			lbl := "Disable passcode"
			if d.disableArmed {
				lbl = "Tap again to disable"
			}
			bl := material.Button(a.ui.Theme, &lockDlgDisableBtn, lbl)
			bl.Background = a.ui.p.SurfaceHi
			bl.Color = a.ui.p.Error
			bl.CornerRadius = 10
			return layout.Inset{Top: unit.Dp(8)}.Layout(gtx, bl.Layout)
		}),
	)
}

// hasHash guards the verify step against an incomplete vault record.
func (st *lockState) hasHash() bool {
	return st != nil && st.salt != "" && st.hash != ""
}
