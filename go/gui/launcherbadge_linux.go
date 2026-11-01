//go:build linux

package gui

import (
	"image/color"
	"strconv"

	"github.com/godbus/dbus/v5"

	"gioui.org/app"
)

const unityLauncherIface = "com.canonical.Unity.LauncherEntry"

const launcherDesktopEntry = "uniclient"

func djb2Hash(s string) uint32 {
	h := uint32(5381)
	for i := 0; i < len(s); i++ {
		h = (h << 5) + h + uint32(s[i])
	}
	return h
}

func launcherAppID(desktopEntry string) string {
	return "application://" + desktopEntry + ".desktop"
}

func launcherEntryPath(desktopEntry string) dbus.ObjectPath {
	return dbus.ObjectPath("/com/canonical/unity/launcherentry/" +
		strconv.FormatUint(uint64(djb2Hash(launcherAppID(desktopEntry))), 10))
}

func unityBadgeProps(count int) map[string]dbus.Variant {
	if count > 9999 {
		count = 9999
	}
	if count < 0 {
		count = 0
	}
	return map[string]dbus.Variant{
		"count":         dbus.MakeVariant(int64(count)),
		"count-visible": dbus.MakeVariant(count > 0),
	}
}

func updateTaskbarBadge(count int, accent color.NRGBA) {
	conn, err := dbusSession()
	if err != nil {
		return
	}
	appID := launcherAppID(launcherDesktopEntry)
	path := launcherEntryPath(launcherDesktopEntry)
	_ = conn.Emit(path, unityLauncherIface+".Update", appID, unityBadgeProps(count))
}

func taskbarSetWindow(app.ViewEvent) {}

func stopTaskbar() {}
