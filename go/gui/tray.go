//go:build linux || windows

package gui

// tray.go — slice 137: the system tray (AyuGram/tdesktop parity).
//
// Linux speaks the freedesktop StatusNotifierItem + com.canonical.dbusmenu
// protocols (via github.com/gogpu/systray, pure Go on godbus — the same D-Bus
// stack the notification banners use); Windows rides Shell_NotifyIconW
// through x/sys/windows. The icon is rendered in-process (trayicon.go) and
// carries the unread counter badge; the menu mirrors AyuGram's tray:
// Show, per-account rows with unread counts, Ghost mode and Streamer mode
// toggles, and Quit. The web/Android builds have no system tray at all —
// the honest absence there is tray_stub.go.

import (
	"image/color"
	"log"
	"sync"

	"gioui.org/io/system"

	"github.com/gogpu/systray"

	"uniclient/utils"
)

// traySupportedOn reports whether this platform has a system tray at all
// (drives the settings toggle's visibility — no dead UI, §1.10).
const traySupportedOn = true

// trayController owns the platform tray icon + menu for the app lifetime.
type trayController struct {
	a    *App
	tray *systray.SystemTray

	mu   sync.Mutex
	snap traySnapshot

	// menu item handles for live updates
	miAccounts []*systray.MenuItem
	miGhost    *systray.MenuItem
	miStream   *systray.MenuItem

	// last rendered icon state (dedupes regeneration)
	iconCount  int
	iconAccent color.NRGBA

	once sync.Once
}

// startTray creates the tray for the app. Never nil: the library absorbs
// a missing tray service (registration retries when a watcher appears).
func startTray(a *App) *trayController {
	c := &trayController{a: a}
	c.iconAccent = a.initialTrayAccent()
	c.tray = systray.New()
	c.tray.SetAppName("Uniclient")
	c.tray.SetTooltip("Uniclient")
	c.tray.OnClick(func() { // hosts that send Activate despite ItemIsMenu
		c.showWindow()
	})
	c.tray.SetIcon(renderTrayIconPNG(128, c.iconAccent, 0))
	c.buildMenu(traySnapshot{})
	go func() {
		if err := c.tray.Run(); err != nil {
			log.Printf("gui: tray loop: %v", err)
		}
	}()
	return c
}

// initialTrayAccent snapshots the accent for the first icon (safe on the
// boot path — Start runs before the frame loop starts).
func (a *App) initialTrayAccent() color.NRGBA {
	return a.ui.p.Accent
}

// buildMenu constructs the tray menu for a snapshot (AyuGram layout).
func (c *trayController) buildMenu(snap traySnapshot) {
	m := systray.NewMenu()
	m.Add("Show UniClient", c.showWindow)
	m.AddSeparator()

	c.miAccounts = nil
	for i := range snap.Accounts {
		acc := snap.Accounts[i]
		c.miAccounts = append(c.miAccounts, m.Add(trayAccountLabel(acc.Name, acc.Unread), func() {
			c.switchAccount(acc.ID)
		}))
	}
	if len(snap.Accounts) > 0 {
		m.AddSeparator()
	}

	c.miGhost = m.AddCheckbox("Ghost mode", snap.Ghost, c.toggleGhost)
	c.miStream = m.AddCheckbox("Streamer mode", snap.Streamer, c.toggleStreamer)
	m.AddSeparator()
	m.Add("Quit UniClient", c.quitApp)

	c.mu.Lock()
	c.snap = snap
	c.mu.Unlock()
	c.tray.SetMenu(m)
}

// sync pushes a fresh snapshot: badge icon, tooltip, account labels,
// checkbox states. Cheap when nothing changed.
func (c *trayController) sync(snap traySnapshot, accent color.NRGBA) {
	c.mu.Lock()
	prev := c.snap
	c.snap = snap
	c.mu.Unlock()

	if snap.TotalUnread != c.iconCount || accent != c.iconAccent {
		c.iconCount = snap.TotalUnread
		c.iconAccent = accent
		c.tray.SetIcon(renderTrayIconPNG(128, accent, snap.TotalUnread))
	}

	tooltip := "Uniclient"
	if snap.TotalUnread > 0 {
		tooltip = "Uniclient — " + trayCountLabel(snap.TotalUnread) + " unread"
	}
	c.tray.SetTooltip(tooltip)

	// The account set changes rarely; relabel in place otherwise.
	if accountSetChanged(snap.Accounts, prev.Accounts) {
		c.buildMenu(snap)
		return
	}
	for i := range snap.Accounts {
		if i < len(c.miAccounts) && c.miAccounts[i] != nil {
			c.miAccounts[i].SetLabel(trayAccountLabel(snap.Accounts[i].Name, snap.Accounts[i].Unread))
		}
	}
	if c.miGhost != nil {
		c.miGhost.SetChecked(snap.Ghost)
	}
	if c.miStream != nil {
		c.miStream.SetChecked(snap.Streamer)
	}
}

// accountSetChanged reports whether the account rows differ by ID/name.
func accountSetChanged(a, b []trayAccount) bool {
	if len(a) != len(b) {
		return true
	}
	for i := range a {
		if a[i].ID != b[i].ID || a[i].Name != b[i].Name {
			return true
		}
	}
	return false
}

// showWindow raises the main window (tray "Show", tdesktop behavior).
func (c *trayController) showWindow() {
	if w := c.a.win; w != nil {
		w.Perform(system.ActionRaise)
	}
}

// quitApp closes the main window; the normal shutdown path (DestroyEvent)
// stops the engine and exits.
func (c *trayController) quitApp() {
	if w := c.a.win; w != nil {
		w.Perform(system.ActionClose)
	}
}

// switchAccount scopes the sidebar to one account (same path as the
// drawer account rows).
func (c *trayController) switchAccount(accountID string) {
	a := c.a
	a.mu.Lock()
	if a.acctFilter == accountID {
		a.acctFilter = ""
	} else {
		a.acctFilter = accountID
	}
	a.folder = 0
	scope := a.acctFilter
	a.mu.Unlock()
	a.refreshFolders(scope)
	a.invalidate()
}

// toggleGhost flips the AyuGram master ghost profile (the same eight
// flags as the drawer toggle).
func (c *trayController) toggleGhost() {
	c.mu.Lock()
	on := !c.snap.Ghost
	c.snap.Ghost = on
	if c.miGhost != nil {
		c.miGhost.SetChecked(on)
	}
	c.mu.Unlock()
	c.a.setGhostAll(on)
}

// toggleStreamer flips streamer mode (same call as the drawer toggle).
func (c *trayController) toggleStreamer() {
	c.mu.Lock()
	on := !c.snap.Streamer
	c.snap.Streamer = on
	if c.miStream != nil {
		c.miStream.SetChecked(on)
	}
	c.mu.Unlock()
	c.a.applyStreamer(on)
}

// stop removes the tray icon and releases D-Bus resources (idempotent).
func (c *trayController) stop() {
	c.once.Do(func() {
		if c.tray != nil {
			c.tray.Remove()
		}
	})
}

// updateTray is the App-side hook: project state + push to the tray.
// Called from the refresh paths (accounts/chats/config changes).
func (a *App) updateTray() {
	a.mu.Lock()
	snap := traySnapshotFrom(a.accounts, a.chats, a.cfg)
	accent := a.accentNow
	tr := a.tray
	a.mu.Unlock()
	// Windows taskbar overlay badge (slice 153): the same unread total
	// rides the taskbar button; independent of the tray icon so it works
	// with the tray turned off too.
	updateTaskbarBadge(snap.TotalUnread, accent)
	if tr == nil {
		return
	}
	tr.sync(snap, accent)
}

// startTrayIfNeeded boots the tray when the config enables it.
func (a *App) startTrayIfNeeded() {
	a.mu.Lock()
	already := a.tray != nil
	accent := a.accentNow
	a.mu.Unlock()
	if already {
		return
	}
	cfg := a.eng.GetConfig()
	if cfg == nil || !utils.EffectiveSystemTray(*cfg) {
		return
	}
	a.mu.Lock()
	a.tray = startTray(a)
	a.mu.Unlock()
	a.updateTray()
	_ = accent
}

// stopTray shuts the tray down (config toggle off or app exit).
func (a *App) stopTray() {
	a.mu.Lock()
	tr := a.tray
	a.tray = nil
	a.mu.Unlock()
	if tr != nil {
		tr.stop()
	}
	// the taskbar overlay is independent of the tray icon — it keeps
	// running until app Shutdown (slice 153)
}
