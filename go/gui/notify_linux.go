//go:build linux

package gui

import (
	"sync"

	"github.com/godbus/dbus/v5"
)

var (
	dbusOnce sync.Once
	dbusConn *dbus.Conn
	dbusErr  error
)

// dbusSession lazily dials the session bus (shared; GUI-lifetime).
func dbusSession() (*dbus.Conn, error) {
	dbusOnce.Do(func() {
		dbusConn, dbusErr = dbus.SessionBus()
	})
	return dbusConn, dbusErr
}

// notifyDesktop sends a Freedesktop notification banner
// (org.freedesktop.Notifications.Notify) — the Linux desktop layer of
// AyuGram's notification pipeline. Windows/wasm/android stub out.
func notifyDesktop(title, body string) error {
	conn, err := dbusSession()
	if err != nil {
		return err
	}
	obj := conn.Object("org.freedesktop.Notifications", "/org/freedesktop/Notifications")
	call := obj.Call("org.freedesktop.Notifications.Notify", 0,
		"Uniclient",
		uint32(0),
		"",    // app icon
		title, // summary
		body,  // body
		[]string{},
		map[string]dbus.Variant{},
		int32(6000), // expire ms
	)
	return call.Err
}
