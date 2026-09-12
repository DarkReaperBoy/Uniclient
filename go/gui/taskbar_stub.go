//go:build !windows

package gui

// taskbar_stub.go — slice 153: platforms without a taskbar overlay API
// (Linux docks have no freedesktop standard — the Unity launcher badge
// stays a documented future; macOS is banned outright). All entry
// points are no-ops so call sites stay unconditional.

import (
	"image/color"

	"gioui.org/app"
)

// taskbarSetWindow is a no-op without the Windows taskbar.
func taskbarSetWindow(app.ViewEvent) {}

// updateTaskbarBadge is a no-op without the Windows taskbar.
func updateTaskbarBadge(count int, accent color.NRGBA) {}

// stopTaskbar is a no-op without the Windows taskbar.
func stopTaskbar() {}
