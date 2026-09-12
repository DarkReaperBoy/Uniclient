//go:build linux

package gui

// appicon_apply_linux.go — slice 170: runtime window-icon application
// on X11 (the Linux leg of AyuGram's applyIcon — Qt sets the window
// icon; our equivalent is the freedesktop _NET_WM_ICON property).
// Pure Go via github.com/jezek/xgb (already in the module graph through
// the tray's systray dep): one lazy extra X connection used only for
// property writes, so gio's cgo backend stays untouched.

import (
	"encoding/binary"
	"image/color"
	"log"
	"sync"

	"gioui.org/app"

	"github.com/jezek/xgb"
	"github.com/jezek/xgb/xproto"
)

const appIconRuntimeApply = true

// netWMIconSizes: every size is appended into one property value (the
// WM picks the best fit) — the tdesktop/Qt behavior. Capped at 128px:
// a single ChangeProperty request must stay under the core protocol's
// 16-bit length field (262,140 bytes; 128+64+48+32 → ~95 KB, while a
// 256px icon alone would overflow it — live-verified under Xvfb, which
// answered BadLength before the cap).
var netWMIconSizes = []int{128, 64, 48, 32}

var (
	appIconXMu     sync.Mutex
	appIconXConn   *xgb.Conn
	appIconXAtom   xproto.Atom
	appIconXWindow xproto.Window
	appIconXLastID string
	appIconXFailed bool // display unreachable: stay silently icon-default
)

// appiconSetWindow captures the X11 window from the gio ViewEvent and
// applies the configured icon set (called from ListenEvents; main
// window only — separate windows keep the default icon).
func appiconSetWindow(ev app.ViewEvent, set appIconSet, accent color.NRGBA) {
	x11, ok := ev.(app.X11ViewEvent)
	if !ok || x11.Window == 0 {
		return
	}
	appIconXMu.Lock()
	defer appIconXMu.Unlock()
	appIconXWindow = xproto.Window(x11.Window)
	if !initXIconConnLocked() {
		return
	}
	applyXWindowIconLocked(set, accent)
}

// applyAppIconRuntime re-applies the icon when the configured set (or
// the default set's accent) changed.
func applyAppIconRuntime(set appIconSet, accent color.NRGBA) {
	appIconXMu.Lock()
	defer appIconXMu.Unlock()
	applyXWindowIconLocked(set, accent)
}

// initXIconConnLocked lazily dials the display + interns the
// _NET_WM_ICON atom. Failures are permanent-but-silent: a headless or
// remote session simply keeps the WM default icon (§1.10 honesty — no
// error surface for a cosmetic property).
func initXIconConnLocked() bool {
	if appIconXFailed {
		return false
	}
	if appIconXConn != nil {
		return true
	}
	conn, err := xgb.NewConn()
	if err != nil {
		appIconXFailed = true
		return false
	}
	reply, err := xproto.InternAtom(conn, false,
		uint16(len("_NET_WM_ICON")), "_NET_WM_ICON").Reply()
	if err != nil {
		conn.Close()
		appIconXFailed = true
		return false
	}
	appIconXConn = conn
	appIconXAtom = reply.Atom
	return true
}

// applyXWindowIconLocked composes the multi-size ARGB payload and
// replaces the property.
func applyXWindowIconLocked(set appIconSet, accent color.NRGBA) {
	if appIconXConn == nil || appIconXWindow == 0 {
		return
	}
	tile := set.Tile
	if set.Tile == liveAccentTile {
		tile = accent
	}
	sized := appIconSet{ID: set.ID, Label: set.Label, Tile: tile, Mark: set.Mark}
	if sized.ID == appIconXLastID && (sized.ID != "default" || colorEq(appIconXLastAccent, accent)) {
		return
	}
	appIconXLastID = sized.ID
	appIconXLastAccent = accent

	var payload []uint32
	for _, px := range netWMIconSizes {
		payload = append(payload, netWMIconData(sized, px)...)
	}
	buf := make([]byte, len(payload)*4)
	for i, v := range payload {
		binary.LittleEndian.PutUint32(buf[i*4:], v)
	}
	// CARDINAL = atom 6 (xproto.AtomCardinal).
	err := xproto.ChangePropertyChecked(appIconXConn, xproto.PropModeReplace,
		appIconXWindow, appIconXAtom, xproto.AtomCardinal, 32,
		uint32(len(payload)), buf).Check()
	if err != nil {
		log.Printf("appicon: _NET_WM_ICON write failed: %v", err)
	}
}

var appIconXLastAccent color.NRGBA

// stopAppIcon closes the helper connection (app shutdown).
func stopAppIcon() {
	appIconXMu.Lock()
	defer appIconXMu.Unlock()
	if appIconXConn != nil {
		appIconXConn.Close()
		appIconXConn = nil
	}
}
