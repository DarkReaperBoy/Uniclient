//go:build !windows && !linux

package gui

import (
	"image/color"

	"gioui.org/app"
)

func taskbarSetWindow(app.ViewEvent) {}

func updateTaskbarBadge(count int, accent color.NRGBA) {}

func stopTaskbar() {}
