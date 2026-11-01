//go:build !linux && !windows

package gui

const traySupportedOn = false

func startTray(a *App) *trayController { return nil }

type trayController struct{}

func (c *trayController) stop() {}

func (a *App) updateTray() {}

func (a *App) startTrayIfNeeded() {}

func (a *App) stopTray() {}
