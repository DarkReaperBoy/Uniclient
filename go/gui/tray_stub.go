//go:build !linux && !windows

package gui

// tray_stub.go — slice 137: platforms with no system tray (web/Android).
// startTray stays nil: every tray surface (settings toggle included) is
// gated on traySupportedOn so nothing dead renders (§1.10).

// traySupportedOn reports whether this platform has a system tray.
const traySupportedOn = false

// startTray never starts a tray here.
func startTray(a *App) *trayController { return nil }

// trayController is a nil-able placeholder on tray-less platforms.
type trayController struct{}

func (c *trayController) stop() {}

// updateTray is a no-op without a tray.
func (a *App) updateTray() {}

// startTrayIfNeeded is a no-op without a tray.
func (a *App) startTrayIfNeeded() {}

// stopTray is a no-op without a tray.
func (a *App) stopTray() {}
