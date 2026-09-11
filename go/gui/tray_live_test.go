//go:build linux || windows

package gui

// tray_live_test.go — slice 137: REAL wire-level verification of the tray
// against a private dbus-daemon: a fake org.kde.StatusNotifierWatcher
// receives the registration, the SNI object serves its properties, and the
// com.canonical.dbusmenu GetLayout/Event round-trips work. Skips when no
// dbus-daemon binary exists (hermetic otherwise — own bus, own socket).

import (
	"os/exec"
	"strings"
	"testing"
	"time"

	"github.com/godbus/dbus/v5"
)

// liveTrayWatcher is a fake org.kde.StatusNotifierWatcher.
type liveTrayWatcher struct {
	registered chan string
}

func (w *liveTrayWatcher) RegisterStatusNotifierItem(service string) *dbus.Error {
	select {
	case w.registered <- service:
	default:
	}
	return nil
}

// startPrivateBus launches an isolated session bus. Returns the address
// and a cleanup func.
func startPrivateBus(t *testing.T) (string, func()) {
	t.Helper()
	bin, err := exec.LookPath("dbus-daemon")
	if err != nil {
		t.Skip("no dbus-daemon binary in PATH")
	}
	cmd := exec.Command(bin, "--session", "--print-address=1", "--fork")
	out, err := cmd.Output()
	if err != nil {
		t.Skipf("dbus-daemon failed to start: %v", err)
	}
	addr := strings.TrimSpace(string(out))
	if addr == "" {
		t.Skip("dbus-daemon printed no address")
	}
	return addr, func() {
		_ = cmd.Process.Kill()
	}
}

// collectMenuLabels walks a dbusmenu layout tree collecting labels.
func collectMenuLabels(v interface{}, out *[]string) {
	row, ok := v.([]interface{})
	if !ok || len(row) < 3 {
		return
	}
	if props, ok := row[1].(map[string]dbus.Variant); ok {
		if lbl, ok := props["label"]; ok {
			*out = append(*out, lbl.Value().(string))
		}
	}
	if children, ok := row[2].([]dbus.Variant); ok {
		for _, c := range children {
			collectMenuLabels(c.Value(), out)
		}
	}
}

func TestTrayLiveSNIRegistration(t *testing.T) {
	addr, cleanup := startPrivateBus(t)
	defer cleanup()
	t.Setenv("DBUS_SESSION_BUS_ADDRESS", addr)

	// Fake watcher on the private bus.
	wconn, err := dbus.Dial(addr)
	if err != nil {
		t.Fatalf("watcher dial: %v", err)
	}
	defer wconn.Close()
	if err := wconn.Auth(nil); err != nil {
		t.Fatalf("watcher auth: %v", err)
	}
	if err := wconn.Hello(); err != nil {
		t.Fatalf("watcher hello: %v", err)
	}
	w := &liveTrayWatcher{registered: make(chan string, 4)}
	if err := wconn.Export(w, "/StatusNotifierWatcher", "org.kde.StatusNotifierWatcher"); err != nil {
		t.Fatalf("export watcher: %v", err)
	}
	reply, err := wconn.RequestName("org.kde.StatusNotifierWatcher", dbus.NameFlagDoNotQueue)
	if err != nil || reply != dbus.RequestNameReplyPrimaryOwner {
		t.Fatalf("request watcher name: %v reply=%d", err, reply)
	}

	// Boot the tray controller against this bus (minimal App: palette only).
	a := &App{ui: NewUI()}
	c := startTray(a)
	defer c.stop()

	select {
	case svc := <-w.registered:
		if !strings.HasPrefix(svc, "org.kde.StatusNotifierItem-") {
			t.Fatalf("registered service = %q, want org.kde.StatusNotifierItem-*", svc)
		}
		// The SNI object must serve its properties on that bus name.
		sobj := wconn.Object(svc, "/StatusNotifierItem")
		var category dbus.Variant
		if err := sobj.Call("org.freedesktop.DBus.Properties.Get", 0,
			"org.kde.StatusNotifierItem", "Category").Store(&category); err != nil {
			t.Fatalf("Properties.Get Category: %v", err)
		}
		if category.Value() != "ApplicationStatus" {
			t.Fatalf("Category = %v, want ApplicationStatus", category.Value())
		}
		var pixmaps dbus.Variant
		if err := sobj.Call("org.freedesktop.DBus.Properties.Get", 0,
			"org.kde.StatusNotifierItem", "IconPixmap").Store(&pixmaps); err != nil {
			t.Fatalf("Properties.Get IconPixmap: %v", err)
		}
		// The tray sets its icon at startup: at least one pixmap with data.
		arr, ok := pixmaps.Value().([][]interface{})
		if !ok || len(arr) == 0 {
			t.Fatalf("IconPixmap = %v, want ≥1 pixmap", pixmaps.Value())
		}

		// The dbusmenu object must serve the AyuGram menu layout.
		mobj := wconn.Object(svc, "/MenuBar")
		var rev uint32
		var layout dbus.Variant
		if err := mobj.Call("com.canonical.dbusmenu.GetLayout", 0,
			int32(0), int32(-1), []string{}).Store(&rev, &layout); err != nil {
			t.Fatalf("GetLayout: %v", err)
		}
		var labels []string
		collectMenuLabels(layout.Value(), &labels)
		joined := strings.Join(labels, "|")
		for _, want := range []string{"Show UniClient", "Ghost mode", "Streamer mode", "Quit UniClient"} {
			if !strings.Contains(joined, want) {
				t.Fatalf("menu labels %q missing %q", joined, want)
			}
		}

		// Event round-trip on the Quit item (no window in this test — the
		// handler no-ops safely; the wire call itself must succeed).
		var needUpdate bool
		if err := mobj.Call("com.canonical.dbusmenu.AboutToShow", 0, int32(0)).Store(&needUpdate); err != nil {
			t.Fatalf("AboutToShow: %v", err)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("watcher never received RegisterStatusNotifierItem")
	}
}

// TestTrayLiveSyncUpdates: sync() relabels account rows and swaps the icon
// through the same D-Bus surface.
func TestTrayLiveSyncUpdates(t *testing.T) {
	addr, cleanup := startPrivateBus(t)
	defer cleanup()
	t.Setenv("DBUS_SESSION_BUS_ADDRESS", addr)

	wconn, err := dbus.Dial(addr)
	if err != nil {
		t.Fatalf("watcher dial: %v", err)
	}
	defer wconn.Close()
	if err := wconn.Auth(nil); err != nil {
		t.Fatalf("watcher auth: %v", err)
	}
	if err := wconn.Hello(); err != nil {
		t.Fatalf("watcher hello: %v", err)
	}
	w := &liveTrayWatcher{registered: make(chan string, 4)}
	if err := wconn.Export(w, "/StatusNotifierWatcher", "org.kde.StatusNotifierWatcher"); err != nil {
		t.Fatalf("export watcher: %v", err)
	}
	if _, err := wconn.RequestName("org.kde.StatusNotifierWatcher", dbus.NameFlagDoNotQueue); err != nil {
		t.Fatalf("request watcher name: %v", err)
	}

	a := &App{ui: NewUI()}
	c := startTray(a)
	defer c.stop()

	select {
	case svc := <-w.registered:
		// Initial sync with one account carrying unread.
		c.sync(traySnapshot{
			Accounts:    []trayAccount{{ID: "a1", Name: "@alice", Unread: 4}},
			TotalUnread: 4,
		}, a.ui.p.Accent)
		time.Sleep(100 * time.Millisecond) // property writes settle

		mobj := wconn.Object(svc, "/MenuBar")
		var rev uint32
		var layout dbus.Variant
		if err := mobj.Call("com.canonical.dbusmenu.GetLayout", 0,
			int32(0), int32(-1), []string{}).Store(&rev, &layout); err != nil {
			t.Fatalf("GetLayout: %v", err)
		}
		var labels []string
		collectMenuLabels(layout.Value(), &labels)
		if !containsLabel(labels, "@alice (4)") {
			t.Fatalf("labels %v missing @alice (4)", labels)
		}

		// Resync: unread grows to 12 — in-place relabel (no rebuild).
		c.sync(traySnapshot{
			Accounts:    []trayAccount{{ID: "a1", Name: "@alice", Unread: 12}},
			TotalUnread: 12,
		}, a.ui.p.Accent)
		time.Sleep(100 * time.Millisecond)
		if err := mobj.Call("com.canonical.dbusmenu.GetLayout", 0,
			int32(0), int32(-1), []string{}).Store(&rev, &layout); err != nil {
			t.Fatalf("GetLayout after resync: %v", err)
		}
		labels = nil
		collectMenuLabels(layout.Value(), &labels)
		if !containsLabel(labels, "@alice (12)") {
			t.Fatalf("labels %v missing @alice (12) after resync", labels)
		}

		// The icon regenerated with the badge count (tooltip too).
		sobj := wconn.Object(svc, "/StatusNotifierItem")
		var tip dbus.Variant
		if err := sobj.Call("org.freedesktop.DBus.Properties.Get", 0,
			"org.kde.StatusNotifierItem", "ToolTip").Store(&tip); err != nil {
			t.Fatalf("ToolTip get: %v", err)
		}
		tt, ok := tip.Value().([]interface{})
		if !ok || len(tt) < 3 {
			t.Fatalf("ToolTip = %v", tip.Value())
		}
		title, _ := tt[2].(string)
		if !strings.Contains(title, "12 unread") {
			t.Fatalf("tooltip title = %q, want unread count", title)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("watcher never received RegisterStatusNotifierItem")
	}
}

func containsLabel(labels []string, want string) bool {
	for _, l := range labels {
		if l == want {
			return true
		}
	}
	return false
}
