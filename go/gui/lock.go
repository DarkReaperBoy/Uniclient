package gui

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"image"
	"strconv"
	"time"

	"gioui.org/io/event"
	"gioui.org/io/key"
	"gioui.org/io/pointer"
	"gioui.org/layout"
	"gioui.org/op/clip"
	"gioui.org/op/paint"
	"gioui.org/unit"
	"gioui.org/widget/material"
)

type lockState struct {
	digits      int
	autolockMin int
	hash        string
	salt        string

	locked      bool
	input       string
	wrong       bool
	wrongCount  int
	frozenUntil time.Time
	lastActive  time.Time
}

const (
	maxLockWrong     = 5
	lockFreezeSecond = 30 * time.Second
)

func pinHashOf(salt, pin string) string {
	sum := sha256.Sum256([]byte(salt + pin))
	return hex.EncodeToString(sum[:])
}

func newLockSalt() string {
	b := make([]byte, 8)
	if _, err := rand.Read(b); err != nil {
		return strconv.FormatInt(time.Now().UnixNano(), 16)
	}
	return hex.EncodeToString(b)
}

func lockFromConfig(data map[string]interface{}) *lockState {
	if data == nil {
		return nil
	}
	if en, _ := data["enabled"].(bool); !en {
		return nil
	}
	st := &lockState{locked: true}
	switch v := data["digits"].(type) {
	case float64:
		st.digits = lockClampDigits(int(v))
	case int:
		st.digits = lockClampDigits(v)
	}
	if st.digits == 0 {
		st.digits = 4
	}
	switch v := data["autolock"].(type) {
	case float64:
		st.autolockMin = int(v)
	case int:
		st.autolockMin = v
	}
	if st.autolockMin < 0 {
		st.autolockMin = 0
	}
	st.salt, _ = data["salt"].(string)
	st.hash, _ = data["hash"].(string)
	if st.salt == "" || st.hash == "" {
		return nil
	}
	return st
}

func (st *lockState) toConfig() map[string]interface{} {
	return map[string]interface{}{
		"enabled":  true,
		"digits":   st.digits,
		"autolock": st.autolockMin,
		"salt":     st.salt,
		"hash":     st.hash,
	}
}

func lockClampDigits(n int) int {
	if n < 4 {
		return 4
	}
	if n > 6 {
		return 6
	}
	return n
}

func lockFrozen(st *lockState, now time.Time) bool {
	return st != nil && !st.frozenUntil.IsZero() && now.Before(st.frozenUntil)
}

func lockShouldAutolock(st *lockState, now time.Time) bool {
	return st != nil && !st.locked && st.autolockMin > 0 &&
		!st.lastActive.IsZero() &&
		now.Sub(st.lastActive) > time.Duration(st.autolockMin)*time.Minute
}

func lockFeedDigit(st *lockState, d byte) bool {
	if st == nil || len(st.input) >= st.digits {
		return false
	}
	if d < '0' || d > '9' {
		return false
	}
	if lockFrozen(st, time.Now()) {
		return false
	}
	st.input += string(d)
	return true
}

func lockTryAttempt(st *lockState, now time.Time) bool {
	if st == nil || len(st.input) != st.digits {
		return false
	}
	if pinHashOf(st.salt, st.input) == st.hash {
		st.locked = false
		st.input = ""
		st.wrong = false
		st.wrongCount = 0
		st.frozenUntil = time.Time{}
		st.lastActive = now
		return true
	}
	st.wrong = true
	st.input = ""
	st.wrongCount++
	if st.wrongCount >= maxLockWrong {
		st.wrongCount = 0
		st.frozenUntil = now.Add(lockFreezeSecond)
	}
	return false
}

func lockBackspace(st *lockState) {
	if st == nil || st.input == "" {
		return
	}
	st.input = st.input[:len(st.input)-1]
}

var (
	lockKeyTag      = new(struct{})
	lockActivityTag = new(struct{})
)

func (a *App) lockDots(gtx layout.Context, st *lockState) layout.Dimensions {
	return a.pinDots(gtx, st.digits, len(st.input), st.wrong)
}

func (a *App) pinDots(gtx layout.Context, n, filled int, wrong bool) layout.Dimensions {
	const dotDp = 14
	gap := gtx.Dp(unit.Dp(10))
	dot := gtx.Dp(unit.Dp(dotDp))
	w := n*dot + (n-1)*gap
	h := dot
	x := 0
	for i := 0; i < n; i++ {
		c := a.ui.p.TextFaint
		if i < filled {
			c = a.ui.p.Text
			if wrong {
				c = a.ui.p.Error
			}
		}
		circ := clip.Ellipse{Min: image.Pt(x, 0), Max: image.Pt(x+dot, dot)}.Push(gtx.Ops)
		paint.Fill(gtx.Ops, c)
		circ.Pop()
		x += dot + gap
	}
	return layout.Dimensions{Size: image.Pt(w, h)}
}

func (a *App) pinGrid(gtx layout.Context, disabled bool, feed func(k string)) layout.Dimensions {
	growClickables(&a.wid.lockPadBtns, 11)

	const keyDp = 72
	const gapDp = 14
	keySz := gtx.Dp(unit.Dp(keyDp))
	gap := gtx.Dp(unit.Dp(gapDp))
	rowW := 3*keySz + 2*gap
	keys := []string{"1", "2", "3", "4", "5", "6", "7", "8", "9", "", "0", "⌫"}
	var rows []layout.FlexChild
	for r := 0; r < 4; r++ {
		rowKeys := keys[r*3 : r*3+3]
		rows = append(rows, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			gtx.Constraints.Min.X = rowW
			cells := make([]layout.FlexChild, 0, 3)
			for _, k := range rowKeys {
				cells = append(cells, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					if k == "" {
						return layout.Dimensions{Size: image.Pt(keySz, keySz)}
					}
					btn := &a.wid.lockPadBtns[lockPadIndex(k)]
					if btn.Clicked(gtx) && !disabled {
						feed(lockKeyOf(k))
					}
					bl := material.Button(a.ui.Theme, btn, k)
					bl.Background = a.ui.p.SurfaceHi
					bl.Color = a.ui.p.Text
					bl.CornerRadius = unit.Dp(keyDp / 2)
					bl.TextSize = unit.Sp(22)
					if disabled {
						bl.Background = a.ui.p.Surface
						bl.Color = a.ui.p.TextFaint
					}
					gtx.Constraints.Min = image.Pt(keySz, keySz)
					gtx.Constraints.Max = image.Pt(keySz, keySz)
					return bl.Layout(gtx)
				}))
			}
			return layout.Flex{Axis: layout.Horizontal, Spacing: layout.SpaceBetween}.Layout(gtx, cells...)
		}))
	}
	return layout.Flex{Axis: layout.Vertical, Spacing: layout.Spacing(gapDp)}.Layout(gtx, rows...)
}

func lockKeyOf(k string) string {
	if k == "⌫" {
		return "back"
	}
	return k
}

func lockFeedKey(st *lockState, k string) bool {
	if k == "back" {
		lockBackspace(st)
		return true
	}
	if len(k) == 1 {
		return lockFeedDigit(st, k[0])
	}
	return false
}

func (a *App) lockPad(gtx layout.Context, st *lockState, disabled bool, now time.Time) layout.Dimensions {
	for {
		ev, ok := gtx.Source.Event(key.Filter{})
		if !ok {
			break
		}
		if ke, is := ev.(key.Event); is && ke.State == key.Press {
			lockKeyInput(a, st, ke, now)
		}
	}
	return a.pinGrid(gtx, disabled, func(k string) {
		if lockFeedKey(st, k) {
			a.invalidate()
		}
	})
}

func lockPadIndex(k string) int {
	if k == "⌫" {
		return 10
	}
	if k == "" || len(k) != 1 || k[0] < '0' || k[0] > '9' {
		return -1
	}
	return int(k[0] - '0')
}

func lockKeyInput(a *App, st *lockState, ke key.Event, now time.Time) {
	if st == nil {
		return
	}
	switch ke.Name {
	case key.NameDeleteBackward:
		lockBackspace(st)
		a.invalidate()
	case key.NameEnter, key.NameReturn:
		if lockTryAttempt(st, now) {
			a.setToast("Unlocked")
			a.broadcastLockState(false)
		}
		a.invalidate()
	default:
		if len(ke.Name) == 1 && ke.Name[0] >= '0' && ke.Name[0] <= '9' {
			if lockFeedDigit(st, ke.Name[0]) {
				a.invalidate()
			}
		}
	}
}

func (a *App) layoutLockScreen(gtx layout.Context, f frame) layout.Dimensions {
	st := f.lock
	now := f.now

	{
		stack := clip.Rect{Max: image.Pt(gtx.Constraints.Max.X, gtx.Constraints.Max.Y)}.Push(gtx.Ops)
		event.Op(gtx.Ops, lockKeyTag)
		stack.Pop()
	}
	for {
		ev, ok := gtx.Source.Event(pointer.Filter{Target: lockKeyTag, Kinds: pointer.Press})
		if !ok {
			break
		}
		_ = ev
	}

	frozen := lockFrozen(st, now)
	if !frozen && len(st.input) == st.digits {
		if lockTryAttempt(st, now) {
			a.setToast("Unlocked")
			a.broadcastLockState(false)
			a.invalidate()
			return layout.Dimensions{Size: gtx.Constraints.Max}
		}
		a.invalidate()
	}

	return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		gtx.Constraints.Max.X = gtx.Dp(unit.Dp(340))
		return roundedFill(gtx, a.ui.p.Surface, 16, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(24)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Vertical, Alignment: layout.Middle}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						gtx.Constraints.Min.X = gtx.Dp(unit.Dp(36))
						return iconActionLock.Layout(gtx, a.ui.p.Accent)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.H3("Uniclient is locked")
							return lbl.Layout(gtx)
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						caption := "Enter passcode"
						col := a.ui.p.TextDim
						switch {
						case frozen:
							sec := int(time.Until(st.frozenUntil).Round(time.Second).Seconds()) + 1
							caption = "Too many attempts — wait " + itoa(sec) + "s"
							col = a.ui.p.Error
						case st.wrong:
							caption = "Wrong passcode"
							col = a.ui.p.Error
						}
						return layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Dim(unit.Sp(12), caption)
							lbl.Color = col
							return lbl.Layout(gtx)
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return a.lockDots(gtx, st)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(16)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return a.lockPad(gtx, st, frozen, now)
						})
					}),
				)
			})
		})
	})
}

func (a *App) lockActivityLayer(gtx layout.Context, f frame) {
	if f.lock == nil || f.lock.locked {
		return
	}
	defer pointer.PassOp{}.Push(gtx.Ops).Pop()
	{
		stack := clip.Rect{Max: image.Pt(gtx.Constraints.Max.X, gtx.Constraints.Max.Y)}.Push(gtx.Ops)
		event.Op(gtx.Ops, lockActivityTag)
		stack.Pop()
	}
	active := false
	for {
		ev, ok := gtx.Source.Event(pointer.Filter{
			Target: lockActivityTag,
			Kinds:  pointer.Press | pointer.Release | pointer.Scroll | pointer.Drag,
		})
		if !ok {
			break
		}
		if _, is := ev.(pointer.Event); is {
			active = true
		}
	}
	for {
		ev, ok := gtx.Source.Event(key.Filter{})
		if !ok {
			break
		}
		if _, is := ev.(key.Event); is {
			active = true
		}
	}
	if active {
		f.lock.lastActive = time.Now()
		lockBroadcastAll(false, true)
	}
}

func (a *App) lockTick(f frame) {
	if lockShouldAutolock(f.lock, f.now) {
		f.lock.locked = true
		f.lock.input = ""
		f.lock.wrong = false
		a.broadcastLockState(true)
		a.invalidate()
	}
}

func (a *App) broadcastLockState(locked bool) {
	if a.lock == nil {
		return
	}
	lockBroadcastAll(locked, false)
}

func (a *App) onLockBroadcast(locked, activity bool) {
	if activity {
		a.mu.Lock()
		if a.lock != nil && !a.lock.locked {
			a.lock.lastActive = time.Now()
		}
		a.mu.Unlock()
		return
	}
	v := locked
	a.mu.Lock()
	a.pendingLock = &v
	a.mu.Unlock()
	a.invalidate()
}
