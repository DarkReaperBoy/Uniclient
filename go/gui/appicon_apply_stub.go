//go:build (!linux && !windows) || android

package gui

import (
	"image/color"

	"gioui.org/app"
)

const appIconRuntimeApply = false

func appiconSetWindow(ev app.ViewEvent, set appIconSet, accent color.NRGBA) {}

func applyAppIconRuntime(set appIconSet, accent color.NRGBA) {}

func stopAppIcon() {}
