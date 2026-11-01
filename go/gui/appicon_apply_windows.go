//go:build windows

package gui

import (
	"image/color"
	"sync"

	"gioui.org/app"

	"golang.org/x/sys/windows"
)

const appIconRuntimeApply = true

const (
	wmSetIcon = 0x80
	iconSmall = 0
	iconBig   = 1
	iconBigPx = 48
	iconSmPx  = 32
)

var (
	user32DLL        = windows.NewLazySystemDLL("user32.dll")
	procSendMessageW = user32DLL.NewProc("SendMessageW")

	appIconMu          sync.Mutex
	appIconHwnd        uintptr
	appIconLastID      string
	appIconLastAccent  color.NRGBA
	appIconBigH        uintptr
	appIconSmallH      uintptr
	appIconBigBitmap   uintptr
	appIconSmallBitmap uintptr
)

func appiconSetWindow(ev app.ViewEvent, set appIconSet, accent color.NRGBA) {
	w32, ok := ev.(app.Win32ViewEvent)
	if !ok || w32.HWND == 0 {
		return
	}
	appIconMu.Lock()
	defer appIconMu.Unlock()
	appIconHwnd = w32.HWND
	applyWindowIconLocked(set, accent)
}

func applyAppIconRuntime(set appIconSet, accent color.NRGBA) {
	appIconMu.Lock()
	defer appIconMu.Unlock()
	applyWindowIconLocked(set, accent)
}

func applyWindowIconLocked(set appIconSet, accent color.NRGBA) {
	if appIconHwnd == 0 {
		return
	}
	if set.ID == appIconLastID && (set.ID != "default" || colorEq(appIconLastAccent, accent)) {
		return
	}
	appIconLastID = set.ID
	appIconLastAccent = accent

	tile := set.Tile
	if set.Tile == liveAccentTile {
		tile = accent
	}
	sized := appIconSet{ID: set.ID, Label: set.Label, Tile: tile, Mark: set.Mark}

	bigImg := renderAppIconRGBA(sized, iconBigPx)
	bigH, bigC, _ := rgbaToHICON(bigImg)
	smallImg := renderAppIconRGBA(sized, iconSmPx)
	smallH, smallC, _ := rgbaToHICON(smallImg)
	if bigH == 0 && smallH == 0 {
		return
	}

	procSendMessageW.Call(appIconHwnd, wmSetIcon, iconBig, bigH)
	procSendMessageW.Call(appIconHwnd, wmSetIcon, iconSmall, smallH)
	destroyAppIconPairLocked()
	appIconBigH, appIconSmallH = bigH, smallH
	appIconBigBitmap, appIconSmallBitmap = bigC, smallC
}

func destroyAppIconPairLocked() {
	if appIconBigH != 0 {
		procDestroyIcon.Call(appIconBigH)
		appIconBigH = 0
	}
	if appIconSmallH != 0 {
		procDestroyIcon.Call(appIconSmallH)
		appIconSmallH = 0
	}
	if appIconBigBitmap != 0 {
		procDeleteObject.Call(appIconBigBitmap)
		appIconBigBitmap = 0
	}
	if appIconSmallBitmap != 0 {
		procDeleteObject.Call(appIconSmallBitmap)
		appIconSmallBitmap = 0
	}
}

func stopAppIcon() {
	appIconMu.Lock()
	defer appIconMu.Unlock()
	destroyAppIconPairLocked()
}
