//go:build linux

package gui

// launcherbadge_linux.go — slice 160: the Linux dock unread-count badge,
// tdesktop updateUnityCounter 1:1. The com.canonical.Unity.LauncherEntry
// protocol (understood by Ubuntu Dock / Dash-to-Dock, KDE Plasma taskbar,
// and anything libunity-compatible): emit the Update signal on
// /com/canonical/unity/launcherentry/<djb2(app_id)> carrying the count +
// count-visible properties. Pure Go — godbus on the session bus, no
// libunity link.
//
// tdesktop reference (platform/linux/main_window_linux.cpp):
//   - launcherUrl = "application://" + desktopFileName + ".desktop"
//   - object path = "/com/canonical/unity/launcherentry/" + djb2(launcherUrl)
//   - signal: com.canonical.Unity.LauncherEntry.Update(s app_id, a{sv} props)
//   - props: count = int64(min(unread, 9999)), count-visible = count > 0

import (
	"image/color"
	"strconv"

	"github.com/godbus/dbus/v5"

	"gioui.org/app"
)

// unityLauncherIface is the LauncherEntry D-Bus interface; its Update
// signal is the whole protocol.
const unityLauncherIface = "com.canonical.Unity.LauncherEntry"

// launcherDesktopEntry is the app's desktop-file basename (matches the
// notifications desktop-entry hint in notify_linux.go).
const launcherDesktopEntry = "uniclient"

// djb2Hash is the xdg string hash tdesktop uses for the entry id:
// h = 5381; h = (h<<5) + h + c, wrapping uint32. Pure — locked by tests.
func djb2Hash(s string) uint32 {
	h := uint32(5381)
	for i := 0; i < len(s); i++ {
		h = (h << 5) + h + uint32(s[i])
	}
	return h
}

// launcherAppID builds the launcher URL from a desktop-file basename.
// Pure — locked by tests.
func launcherAppID(desktopEntry string) string {
	return "application://" + desktopEntry + ".desktop"
}

// launcherEntryPath computes the object path for one desktop entry.
// Pure — locked by tests. (strconv, not the gui itoa helper — that one is
// the unread-badge 999+ label formatter.)
func launcherEntryPath(desktopEntry string) dbus.ObjectPath {
	return dbus.ObjectPath("/com/canonical/unity/launcherentry/" +
		strconv.FormatUint(uint64(djb2Hash(launcherAppID(desktopEntry))), 10))
}

// unityBadgeProps builds the Update signal's property dict (tdesktop
// counterSlice: 9999 clamp; visible only with a count). Pure — locked
// by tests.
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

// updateTaskbarBadge applies the unread count to the dock/taskbar icon
// (the same entry point the Windows ITaskbarList3 overlay uses, slice
// 153). Fire-and-forget: a dock that doesn't implement the protocol
// ignores the signal; emission failures are silent (the badge is
// best-effort polish, never a functional path).
func updateTaskbarBadge(count int, accent color.NRGBA) {
	conn, err := dbusSession()
	if err != nil {
		return
	}
	appID := launcherAppID(launcherDesktopEntry)
	path := launcherEntryPath(launcherDesktopEntry)
	_ = conn.Emit(path, unityLauncherIface+".Update", appID, unityBadgeProps(count))
}

// taskbarSetWindow is a no-op on Linux (the launcher-entry protocol is
// window-independent — no X11 handle needed).
func taskbarSetWindow(app.ViewEvent) {}

// stopTaskbar is a no-op on Linux: the dock drops the entry when the
// session-bus connection closes; a zero-count Update clears it before
// that anyway.
func stopTaskbar() {}
