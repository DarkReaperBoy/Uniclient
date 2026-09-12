//go:build !linux && !windows

package gui

// appicon_apply_stub.go — slice 170: platforms without runtime window
// icons (js/wasm + Android). appIconPickerSupported is false there, so
// the picker never renders — honest absence (§1.10). The apply hooks
// stay no-ops for call-shape compatibility.

import (
	"image/color"

	"gioui.org/app"
)

const appIconRuntimeApply = false

func appiconSetWindow(ev app.ViewEvent, set appIconSet, accent color.NRGBA) {}

func applyAppIconRuntime(set appIconSet, accent color.NRGBA) {}

func stopAppIcon() {}
