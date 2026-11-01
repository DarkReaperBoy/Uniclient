//go:build linux && !android

package gui

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

var netWMIconSizes = []int{128, 64, 48, 32}

var (
	appIconXMu     sync.Mutex
	appIconXConn   *xgb.Conn
	appIconXAtom   xproto.Atom
	appIconXWindow xproto.Window
	appIconXLastID string
	appIconXFailed bool
)

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

func applyAppIconRuntime(set appIconSet, accent color.NRGBA) {
	appIconXMu.Lock()
	defer appIconXMu.Unlock()
	applyXWindowIconLocked(set, accent)
}

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
	err := xproto.ChangePropertyChecked(appIconXConn, xproto.PropModeReplace,
		appIconXWindow, appIconXAtom, xproto.AtomCardinal, 32,
		uint32(len(payload)), buf).Check()
	if err != nil {
		log.Printf("appicon: _NET_WM_ICON write failed: %v", err)
	}
}

var appIconXLastAccent color.NRGBA

func stopAppIcon() {
	appIconXMu.Lock()
	defer appIconXMu.Unlock()
	if appIconXConn != nil {
		appIconXConn.Close()
		appIconXConn = nil
	}
}
