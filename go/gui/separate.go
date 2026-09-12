package gui

// separate.go — slice 168: multi-window chats (tdesktop SeparateType::Chat).
//
// A separate window renders ONE chat (header, messages, composer) with the
// full interactive surface; it never shows the sidebar, drawer, settings or
// the voice tab. Entry points, tdesktop parity:
//   - chat-row context menu "Open in separate window" (Filler::addNewWindow)
//   - Ctrl+click on a chat row (Window::activateWindow + IsCtrlPressed)
//
// Model notes:
//   - One window per chat (tdesktop ensureSeparateWindowFor). Gio has no
//     raise/focus API, so "focus the existing window" approximates as
//     close-and-reopen (the fresh window maps on top).
//   - One window per chat INCLUDING the main window: the chat's interactive
//     surface (a.wid) may only render in one window at a time, so a takeover
//     deselects the chat wherever else it was open — routed through
//     pendingDeselect hops so each App mutates only on its own GUI loop.
//   - Frames serialize on frameMu: both windows' Root() calls take it, so
//     residual package-level state (lottie players, art caches) stays safe.
//   - The local passcode lock is process-wide: a lock bus broadcasts
//     lock/unlock + activity keepalives between windows (each App applies
//     hops on its own loop).

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

// separateWindowSupported reports whether this platform can host additional
// native windows. Gio exposes exactly one window on js/wasm and Android;
// macOS/iOS are banned outright (§1.2).
func separateWindowSupported(goos string) bool {
	switch goos {
	case "linux", "windows":
		return true
	default:
		return false
	}
}

// separateWindowTitle titles a separate window after its chat (tdesktop:
// the peer title). Empty titles fall back to the app name.
func separateWindowTitle(title string) string {
	if title == "" {
		return "Uniclient"
	}
	return title
}

// shouldDeselectMainForSeparate is the one-window-per-chat decision for the
// MAIN window's selection. Pure.
func shouldDeselectMainForSeparate(sel *chatKey, k chatKey) bool {
	return sel != nil && *sel == k
}

// isSeparate reports whether this App renders a separate chat window.
func (a *App) isSeparate() bool {
	return a.separate != nil
}

// ── separate-window registry ──────────────────────────────────────────────

// sepWindow tracks one live separate window.
type sepWindow struct {
	app *App
	key chatKey // the chat it currently renders
}

var (
	sepMu   sync.Mutex
	sepWins = map[chatKey]*sepWindow{} // chatKey → live separate window
	sepWG   sync.WaitGroup
	mainRef *App // the main window's App (nil until Start)
)

// openSeparateWindow spawns (or reopens) the separate window for k. Safe to
// call from any GUI loop; the window itself runs its own loop goroutine.
func (a *App) openSeparateWindow(k chatKey, title string) {
	if !separateWindowSupported(runtime.GOOS) {
		return
	}
	// Reopen semantics: an existing window for k closes (it unregisters from
	// its own loop) and a fresh one maps on top.
	sepMu.Lock()
	if old, ok := sepWins[k]; ok && old.app != a {
		old.app.win.Perform(system.ActionClose)
		delete(sepWins, k)
	}
	sepMu.Unlock()
	// One window per chat, INCLUDING this one: if the caller currently shows
	// k, its chat surface gives the chat up (runs on the caller's own loop).
	a.deselectIfShowing(k)
	// ...and every OTHER window currently showing k deselects too.
	a.queueDeselectElsewhere(k)

	eng := a.eng
	sepWG.Add(1)
	go func() {
		defer sepWG.Done()
		runSeparateWindow(eng, k, title)
	}()
}

// deselectIfShowing clears this window's chat selection when it is showing k
// (the takeover side of the one-window-per-chat invariant). Runs on this
// App's own GUI loop — the same mutation consumeCrossWindowHops applies for
// hops arriving from other windows.
func (a *App) deselectIfShowing(k chatKey) {
	a.mu.Lock()
	if !shouldDeselectMainForSeparate(a.selected, k) {
		a.mu.Unlock()
		return
	}
	a.selected = nil
	a.msgFor = nil
	a.mu.Unlock()
	if a.isSeparate() {
		a.sepUnregister()
		a.win.Option(app.Title(separateWindowTitle("")))
	}
}

// runSeparateWindow drives one separate window's event loop (the Gio
// multi-window pattern: one goroutine per window, app.Main() on the main
// thread stays in charge).
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

// sepMoveRegistry re-keys this window's registry entry after an in-window
// chat switch, taking k over from any other window that held it.
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

// sepUnregister removes this window's registry entry (DestroyEvent path).
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

// queueDeselectElsewhere asks every OTHER window currently showing k to
// deselect it (cross-window hop: each App applies pendingDeselect on its own
// GUI loop — App state is only ever mutated by its own loop).
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

// queueDeselectLocked queues the deselect hop on this App. Callers hold sepMu.
func (a *App) queueDeselectLocked(k chatKey) {
	a.mu.Lock()
	a.pendingDeselect = &k
	a.mu.Unlock()
	a.invalidate()
}

// consumeCrossWindowHops applies cross-window requests on THIS App's GUI
// loop (called from Root before the snapshot): a deselect from a takeover,
// and the shared passcode lock state.
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

// CloseSeparateWindowsAndWait closes every separate window and waits for
// their loops to exit — the main window's exit path (closing the main
// window quits the app; engine teardown must not race live frames).
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

// ── lock bus: process-wide passcode state ─────────────────────────────────

var (
	lockBusMu   sync.Mutex
	lockBusSeq  int
	lockBusSubs = map[int]func(locked bool, activity bool){}
	lockEngaged atomic.Bool // current shared lock state (for boot decisions)
)

// lockBroadcastShare subscribes to lock-state changes; the returned func
// unsubscribes. Callbacks run on the broadcaster's loop; they must only
// queue hops (never mutate another App directly).
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

// lockBroadcastAll notifies every window: locked flips the shared state;
// activity is a keepalive touch (any window's input resets every window's
// autolock idle timer, tdesktop semantics).
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

// layoutSeparateEmpty is the honest empty surface of a separate window
// after a takeover (its chat opened elsewhere): no dead chrome, §1.10.
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

// separateChatView renders the separate window's chat surface (the shared
// chat renderer; narrow drives the phone layout at very small widths).
func (a *App) separateChatView(gtx layout.Context, f frame) layout.Dimensions {
	narrow := gtx.Constraints.Max.X < gtx.Dp(unit.Dp(420))
	if f.selected == nil {
		return a.layoutSeparateEmpty(gtx)
	}
	return a.layoutChatView(gtx, f, narrow)
}

// sepTakeoverCursor keeps the registry's chat key in sync (unused marker for
// future lint; the registry moves in openChat via sepMoveRegistry).
var _ = image.Point{}
