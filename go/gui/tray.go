//go:build linux || windows

package gui

import (
	"image/color"
	"log"
	"sync"

	"gioui.org/io/system"

	"github.com/gogpu/systray"

	"uniclient/utils"
)

const traySupportedOn = true

type trayController struct {
	a    *App
	tray *systray.SystemTray

	mu   sync.Mutex
	snap traySnapshot

	miAccounts []*systray.MenuItem
	miGhost    *systray.MenuItem
	miStream   *systray.MenuItem

	iconCount  int
	iconAccent color.NRGBA
	iconSetID  string

	once sync.Once
}

func startTray(a *App) *trayController {
	c := &trayController{a: a}
	c.iconAccent = a.initialTrayAccent()
	c.tray = systray.New()
	c.tray.SetAppName("Uniclient")
	c.tray.SetTooltip("Uniclient")
	c.tray.OnClick(func() {
		c.showWindow()
	})
	{
		a.mu.Lock()
		set := effectiveAppIconSet(a.cfg)
		a.mu.Unlock()
		c.iconSetID = set.ID
		c.tray.SetIcon(renderTrayIconForSetPNG(128, set, c.iconAccent, 0))
	}
	c.buildMenu(traySnapshot{})
	go func() {
		if err := c.tray.Run(); err != nil {
			log.Printf("gui: tray loop: %v", err)
		}
	}()
	return c
}

func (a *App) initialTrayAccent() color.NRGBA {
	return a.ui.p.Accent
}

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

func (c *trayController) sync(snap traySnapshot, accent color.NRGBA, iconSetCfg cfgSnapshot) {
	c.mu.Lock()
	prev := c.snap
	c.snap = snap
	c.mu.Unlock()

	set := effectiveAppIconSet(iconSetCfg)
	if snap.TotalUnread != c.iconCount || accent != c.iconAccent || set.ID != c.iconSetID {
		c.iconCount = snap.TotalUnread
		c.iconAccent = accent
		c.iconSetID = set.ID
		c.tray.SetIcon(renderTrayIconForSetPNG(128, set, accent, snap.TotalUnread))
	}

	tooltip := "Uniclient"
	if snap.TotalUnread > 0 {
		tooltip = "Uniclient — " + trayCountLabel(snap.TotalUnread) + " unread"
	}
	c.tray.SetTooltip(tooltip)

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

func (c *trayController) showWindow() {
	if w := c.a.win; w != nil {
		w.Perform(system.ActionRaise)
	}
}

func (c *trayController) quitApp() {
	if w := c.a.win; w != nil {
		w.Perform(system.ActionClose)
	}
}

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

func (c *trayController) stop() {
	c.once.Do(func() {
		if c.tray != nil {
			c.tray.Remove()
		}
	})
}

func (a *App) updateTray() {
	a.mu.Lock()
	snap := traySnapshotFrom(a.accounts, a.chats, a.cfg)
	accent := a.accentNow
	cfg := a.cfg
	tr := a.tray
	a.mu.Unlock()
	updateTaskbarBadge(snap.TotalUnread, accent)
	if tr == nil {
		return
	}
	tr.sync(snap, accent, cfg)
}

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

func (a *App) stopTray() {
	a.mu.Lock()
	tr := a.tray
	a.tray = nil
	a.mu.Unlock()
	if tr != nil {
		tr.stop()
	}
}
