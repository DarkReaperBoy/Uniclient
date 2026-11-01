package gui

import (
	"image"
	"runtime"
	"sync"
	"sync/atomic"

	"gioui.org/app"
	"gioui.org/io/system"
	"gioui.org/layout"
	"gioui.org/op"
	"gioui.org/unit"

	"uniclient/engine"
)

func separateWindowSupported(goos string) bool {
	switch goos {
	case "linux", "windows":
		return true
	default:
		return false
	}
}

func separateWindowTitle(title string) string {
	if title == "" {
		return "Uniclient"
	}
	return title
}

func shouldDeselectMainForSeparate(sel *chatKey, k chatKey) bool {
	return sel != nil && *sel == k
}

func (a *App) isSeparate() bool {
	return a.separate != nil
}

func mainOnlySurfaceShown(a *App) bool {
	return !a.isSeparate()
}

type sepWindow struct {
	app *App
	key chatKey
}

var (
	sepMu   sync.Mutex
	sepWins = map[chatKey]*sepWindow{}
	sepWG   sync.WaitGroup
	mainRef *App
)

func (a *App) openSeparateWindow(k chatKey, title string) {
	if !separateWindowSupported(runtime.GOOS) {
		return
	}
	sepMu.Lock()
	if old, ok := sepWins[k]; ok && old.app != a {
		old.app.win.Perform(system.ActionClose)
		delete(sepWins, k)
	}
	sepMu.Unlock()
	a.deselectIfShowing(k)
	a.queueDeselectElsewhere(k)

	eng := a.eng
	sepWG.Add(1)
	go func() {
		defer sepWG.Done()
		runSeparateWindow(eng, k, title)
	}()
}

func (a *App) deselectIfShowing(k chatKey) {
	a.mu.Lock()
	if !shouldDeselectMainForSeparate(a.selected, k) {
		a.mu.Unlock()
		return
	}
	a.selected = nil
	a.msgFor = nil
	a.uiGen++
	a.mu.Unlock()
	if a.isSeparate() {
		a.sepUnregister()
		a.win.Option(app.Title(separateWindowTitle("")))
	}
}

func runSeparateWindow(eng *engine.Engine, k chatKey, title string) {
	w := new(app.Window)
	w.Option(
		app.Title(separateWindowTitle(title)),
		app.Size(unit.Dp(560), unit.Dp(680)),
		app.MinSize(unit.Dp(360), unit.Dp(480)),
	)
	a := New(w, eng)
	a.separate = &k

	sepMu.Lock()
	sepWins[k] = &sepWindow{app: a, key: k}
	sepMu.Unlock()

	a.Start()
	defer a.Shutdown()

	var ops op.Ops
	for {
		e := w.Event()
		a.ListenEvents(e)
		switch e := e.(type) {
		case app.DestroyEvent:
			a.sepUnregister()
			a.sepSub.Unsubscribe()
			return
		case app.FrameEvent:
			gtx := app.NewContext(&ops, e)
			a.Root(gtx)
			e.Frame(&ops)
		}
	}
}

func (a *App) sepMoveRegistry(oldK, newK chatKey) {
	sepMu.Lock()
	defer sepMu.Unlock()
	if sw, ok := sepWins[oldK]; ok && sw.app == a {
		delete(sepWins, oldK)
	}
	if other, ok := sepWins[newK]; ok && other.app != a {
		other.app.queueDeselectLocked(newK)
	}
	sepWins[newK] = &sepWindow{app: a, key: newK}
}

func (a *App) sepUnregister() {
	sepMu.Lock()
	defer sepMu.Unlock()
	a.mu.Lock()
	k := a.separate
	a.mu.Unlock()
	if k == nil {
		return
	}
	if sw, ok := sepWins[*k]; ok && sw.app == a {
		delete(sepWins, *k)
	}
}

func (a *App) queueDeselectElsewhere(k chatKey) {
	sepMu.Lock()
	defer sepMu.Unlock()
	if mainRef != nil && mainRef != a {
		mainRef.queueDeselectLocked(k)
	}
	for key, sw := range sepWins {
		if key == k && sw.app != a {
			sw.app.queueDeselectLocked(k)
		}
	}
}

func (a *App) queueDeselectLocked(k chatKey) {
	a.mu.Lock()
	a.pendingDeselect = &k
	a.mu.Unlock()
	a.invalidate()
}

func (a *App) consumeCrossWindowHops() {
	a.mu.Lock()
	desel := a.pendingDeselect
	a.pendingDeselect = nil
	lock := a.pendingLock
	a.pendingLock = nil
	a.mu.Unlock()

	if desel != nil && a.selected != nil && *a.selected == *desel {
		a.mu.Lock()
		a.selected = nil
		a.msgFor = nil
		a.uiGen++
		a.mu.Unlock()
		if a.isSeparate() {
			a.sepUnregister()
			a.win.Option(app.Title(separateWindowTitle("")))
		}
	}
	if lock != nil && a.lock != nil {
		if *lock && !a.lock.locked {
			a.lock.locked = true
			a.lock.input = ""
		} else if !*lock && a.lock.locked {
			a.lock.locked = false
			a.lock.wrong = false
			a.lock.wrongCount = 0
		}
	}
}

func CloseSeparateWindowsAndWait() {
	sepMu.Lock()
	wins := make([]*sepWindow, 0, len(sepWins))
	for _, sw := range sepWins {
		wins = append(wins, sw)
	}
	sepMu.Unlock()
	for _, sw := range wins {
		sw.app.win.Perform(system.ActionClose)
	}
	sepWG.Wait()
}

var (
	lockBusMu   sync.Mutex
	lockBusSeq  int
	lockBusSubs = map[int]func(locked bool, activity bool){}
	lockEngaged atomic.Bool
)

func lockBroadcastShare(f func(locked, activity bool)) func() {
	lockBusMu.Lock()
	defer lockBusMu.Unlock()
	lockBusSeq++
	id := lockBusSeq
	lockBusSubs[id] = f
	return func() {
		lockBusMu.Lock()
		defer lockBusMu.Unlock()
		delete(lockBusSubs, id)
	}
}

func lockBroadcastAll(locked, activity bool) {
	if activity {
		lockBusMu.Lock()
		subs := make([]func(bool, bool), 0, len(lockBusSubs))
		for _, f := range lockBusSubs {
			subs = append(subs, f)
		}
		lockBusMu.Unlock()
		for _, f := range subs {
			f(false, true)
		}
		return
	}
	lockEngaged.Store(locked)
	lockBusMu.Lock()
	subs := make([]func(bool, bool), 0, len(lockBusSubs))
	for _, f := range lockBusSubs {
		subs = append(subs, f)
	}
	lockBusMu.Unlock()
	for _, f := range subs {
		f(locked, false)
	}
}

func (a *App) layoutSeparateEmpty(gtx layout.Context) layout.Dimensions {
	return centerLayout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Axis: layout.Vertical, Alignment: layout.Middle}.Layout(gtx,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return insetAll(gtx, unit.Dp(0), unit.Dp(0), unit.Dp(12), unit.Dp(0), func(gtx layout.Context) layout.Dimensions {
					lbl := a.ui.H2("Nothing open here")
					lbl.Color = a.ui.p.TextFaint
					return lbl.Layout(gtx)
				})
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				lbl := a.ui.Dim(unit.Sp(14), "This chat opened in another window. Pick a chat in the main window.")
				lbl.Color = a.ui.p.TextFaint
				return lbl.Layout(gtx)
			}),
		)
	})
}

func (a *App) separateChatView(gtx layout.Context, f frame) layout.Dimensions {
	narrow := gtx.Constraints.Max.X < gtx.Dp(unit.Dp(420))
	if f.selected == nil {
		return a.layoutSeparateEmpty(gtx)
	}
	return a.layoutChatView(gtx, f, narrow)
}

var _ = image.Point{}
