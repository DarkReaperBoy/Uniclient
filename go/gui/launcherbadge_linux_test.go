//go:build linux

package gui

// Unity launcher-entry badge (slice 160): the Linux dock unread-count
// badge — tdesktop updateUnityCounter 1:1 (com.canonical.Unity.
// LauncherEntry Update signal on the session bus). Pure logic locked
// here; the dbus emission lives in launcherbadge_linux.go.

import (
	"image/color"
	"strconv"
	"sync"
	"testing"
	"time"

	"github.com/godbus/dbus/v5"
)

func TestDjb2Hash(t *testing.T) {
	// djb2 (xdg "string hash"): h = 5381; h = (h<<5)+h+c, uint32 wrap.
	// Known vector: djb2("uniclient") — computed once, pinned.
	cases := map[string]uint32{
		"":          5381,
		"a":         177670,
		"uniclient": djb2HashReference("uniclient"),
	}
	for s, want := range cases {
		if got := djb2Hash(s); got != want {
			t.Errorf("djb2Hash(%q) = %d, want %d", s, got, want)
		}
	}
}

func TestDjb2HashReferenceVector(t *testing.T) {
	// Independent reference: djb2("application") via a loop written
	// differently (add-then-shift) — must match the shift-then-add form
	// modulo 2^32 because (h<<5)+h == h*33.
	h := uint32(5381)
	for _, c := range "application" {
		h = h*33 + uint32(c)
		h = h * 1 // no-op to keep the loop shape distinct
	}
	if got := djb2Hash("application"); got != h {
		t.Errorf("djb2Hash(application) = %d, want %d", got, h)
	}
}

func TestLauncherEntryPath(t *testing.T) {
	p := launcherEntryPath("uniclient")
	want := dbus.ObjectPath("/com/canonical/unity/launcherentry/" + strconv.FormatUint(uint64(djb2HashReference("application://uniclient.desktop")), 10))
	if p != want {
		t.Errorf("launcherEntryPath = %q, want %q", p, want)
	}
	if len(p) > 255 {
		t.Errorf("object path too long: %d", len(p))
	}
}

func TestUnityBadgeProps(t *testing.T) {
	// Zero count: count 0, hidden.
	props := unityBadgeProps(0)
	if props["count"].Value() != int64(0) {
		t.Errorf("count = %v", props["count"].Value())
	}
	if props["count-visible"].Value() != false {
		t.Errorf("count-visible = %v", props["count-visible"].Value())
	}

	// Plain count.
	props = unityBadgeProps(42)
	if props["count"].Value() != int64(42) {
		t.Errorf("count = %v", props["count"].Value())
	}
	if props["count-visible"].Value() != true {
		t.Errorf("count-visible = %v", props["count-visible"].Value())
	}

	// tdesktop counterSlice: 9999 clamp.
	props = unityBadgeProps(123456)
	if props["count"].Value() != int64(9999) {
		t.Errorf("clamped count = %v", props["count"].Value())
	}
}

func TestLauncherAppID(t *testing.T) {
	if got := launcherAppID("uniclient"); got != "application://uniclient.desktop" {
		t.Errorf("launcherAppID = %q", got)
	}
}

// djb2HashReference is a slow but obviously-correct djb2 (used to pin
// the fast implementation against drift).
func djb2HashReference(s string) uint32 {
	h := uint32(5381)
	for _, c := range s {
		h = h*33 + uint32(c)
	}
	return h
}

// TestLauncherBadgeWire verifies the Update signal on a REAL private
// dbus-daemon (hermetic — own bus, own socket; skips without dbus-daemon):
// updateTaskbarBadge must emit com.canonical.Unity.LauncherEntry.Update
// on the djb2-derived object path with the app_id string and the
// count/count-visible property dict — the exact tdesktop wire form.
func TestLauncherBadgeWire(t *testing.T) {
	addr, cleanup := startPrivateBus(t)
	defer cleanup()
	t.Setenv("DBUS_SESSION_BUS_ADDRESS", addr)
	dbusOnce = sync.Once{}
	dbusConn = nil
	dbusErr = nil

	// Monitor side: subscribe to the Unity signal on the entry path.
	mconn, err := dbus.Dial(addr)
	if err != nil {
		t.Fatalf("monitor dial: %v", err)
	}
	defer mconn.Close()
	if err := mconn.Auth(nil); err != nil {
		t.Fatalf("monitor auth: %v", err)
	}
	if err := mconn.Hello(); err != nil {
		t.Fatalf("monitor hello: %v", err)
	}
	path := launcherEntryPath(launcherDesktopEntry)
	if err := mconn.AddMatchSignal(
		dbus.WithMatchObjectPath(path),
		dbus.WithMatchInterface(unityLauncherIface),
	); err != nil {
		t.Fatalf("match rule: %v", err)
	}
	signals := make(chan *dbus.Signal, 4)
	mconn.Signal(signals)

	// Emit with a count: must arrive with count 42, visible true.
	updateTaskbarBadge(42, color.NRGBA{})
	select {
	case sig := <-signals:
		if sig.Path != path {
			t.Fatalf("signal path = %v, want %v", sig.Path, path)
		}
		if sig.Name != unityLauncherIface+".Update" {
			t.Fatalf("signal name = %q", sig.Name)
		}
		if len(sig.Body) != 2 {
			t.Fatalf("signal body arity = %d", len(sig.Body))
		}
		appID, _ := sig.Body[0].(string)
		if appID != launcherAppID(launcherDesktopEntry) {
			t.Fatalf("app_id = %q", appID)
		}
		props, ok := sig.Body[1].(map[string]dbus.Variant)
		if !ok {
			t.Fatalf("props type = %T", sig.Body[1])
		}
		if props["count"].Value() != int64(42) {
			t.Fatalf("count = %v", props["count"].Value())
		}
		if props["count-visible"].Value() != true {
			t.Fatalf("count-visible = %v", props["count-visible"].Value())
		}
	case <-time.After(3 * time.Second):
		t.Fatal("no Update signal within 3s")
	}

	// Zero count clears the badge: visible false.
	updateTaskbarBadge(0, color.NRGBA{})
	select {
	case sig := <-signals:
		props, ok := sig.Body[1].(map[string]dbus.Variant)
		if !ok {
			t.Fatalf("props type = %T", sig.Body[1])
		}
		if props["count"].Value() != int64(0) {
			t.Fatalf("clear count = %v", props["count"].Value())
		}
		if props["count-visible"].Value() != false {
			t.Fatalf("clear count-visible = %v", props["count-visible"].Value())
		}
	case <-time.After(3 * time.Second):
		t.Fatal("no clearing Update signal within 3s")
	}
}
