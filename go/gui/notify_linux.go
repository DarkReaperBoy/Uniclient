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
// ConnectSessionBus (not SessionBus): godbus's SessionBus caches a
// process-wide shared conn we could never re-arm — a private fresh dial
// keeps this package's lifecycle its own (Dial+Auth+Hello included).
func dbusSession() (*dbus.Conn, error) {
	dbusOnce.Do(func() {
		dbusConn, dbusErr = dbus.ConnectSessionBus()
	})
	return dbusConn, dbusErr
}

// notifyBus is the interactive-banner bookkeeping: which live banner id
// belongs to which chat (in-place replacement — tdesktop banners never
// stack per chat) and which id carries which click handler. The
// org.freedesktop.Notifications ActionInvoked / NotificationClosed
// signals drive it.
type notifyBus struct {
	mu      sync.Mutex
	actions map[uint32]func(string) // banner id → click handler
	last    map[string]uint32       // chat key → live banner id

	subOnce sync.Once
	subErr  error
}

var notifications = &notifyBus{
	actions: map[uint32]func(string){},
	last:    map[string]uint32{},
}

const (
	dbusNotifyIface  = "org.freedesktop.Notifications"
	dbusNotifyPath   = dbus.ObjectPath("/org/freedesktop/Notifications")
	sigActionInvoked = dbusNotifyIface + ".ActionInvoked"
	sigNotifyClosed  = dbusNotifyIface + ".NotificationClosed"
)

// subscribe installs the signal match rules and starts the demux loop
// exactly once per connection.
func (n *notifyBus) subscribe(conn *dbus.Conn) {
	n.subOnce.Do(func() {
		if err := conn.AddMatchSignal(
			dbus.WithMatchObjectPath("/org/freedesktop/Notifications"),
			dbus.WithMatchInterface(dbusNotifyIface),
			dbus.WithMatchSender(dbusNotifyIface),
		); err != nil {
			n.subErr = err
			return
		}
		ch := make(chan *dbus.Signal, 32)
		conn.Signal(ch) // godbus closes ch when the conn closes
		go n.demux(ch)
	})
}

// demux routes notification signals to their handlers. Runs for the
// connection's lifetime; unknown ids and malformed bodies are dropped.
func (n *notifyBus) demux(ch <-chan *dbus.Signal) {
	for sig := range ch {
		if len(sig.Body) < 2 {
			continue
		}
		switch sig.Name {
		case sigActionInvoked:
			if id, ok := sig.Body[0].(uint32); ok {
				if key, ok := sig.Body[1].(string); ok {
					n.dispatch(id, key)
				}
			}
		case sigNotifyClosed:
			if id, ok := sig.Body[0].(uint32); ok {
				n.closed(id)
			}
		}
	}
}

// dispatch runs a banner's click handler off the demux goroutine —
// handlers raise windows and poke the GUI loop, never dbus internals.
func (n *notifyBus) dispatch(id uint32, action string) {
	n.mu.Lock()
	fn := n.actions[id]
	n.mu.Unlock()
	if fn != nil {
		go fn(action)
	}
}

// closed drops a gone banner's bookkeeping (any close reason — expired,
// dismissed, replaced: the entry is dead either way).
func (n *notifyBus) closed(id uint32) {
	n.mu.Lock()
	defer n.mu.Unlock()
	delete(n.actions, id)
	for k, v := range n.last {
		if v == id {
			delete(n.last, k)
		}
	}
}

// notifyDesktop sends a Freedesktop notification banner — the Linux
// desktop layer of AyuGram's notification pipeline. key identifies the
// chat for in-place replacement (a second banner for the same chat
// updates the live one instead of stacking; empty = always fresh).
// actions is the freedesktop (key,label) pair list; onAction (may be
// nil) runs on a background goroutine when the banner's action fires.
// Windows/wasm/android stub out (notify_other.go).
func notifyDesktop(title, body, key, icon string, actions []string, onAction func(string)) error {
	conn, err := dbusSession()
	if err != nil {
		return err
	}
	notifications.subscribe(conn)

	notifications.mu.Lock()
	replaces := notifications.last[key]
	notifications.mu.Unlock()

	obj := conn.Object(dbusNotifyIface, dbusNotifyPath)
	hints := map[string]dbus.Variant{}
	if icon != "" {
		hints["image-path"] = dbus.MakeVariant(icon)
	}
	hints["desktop-entry"] = dbus.MakeVariant("uniclient")

	var id uint32
	call := obj.Call(dbusNotifyIface+".Notify", 0,
		"Uniclient",
		replaces,
		"", // app icon (themed name): the avatar rides the image-path hint
		title,
		body,
		actions,
		hints,
		int32(6000), // expire ms
	)
	if err := call.Store(&id); err != nil {
		return err
	}
	if id == 0 {
		return nil // server declined the banner
	}

	notifications.mu.Lock()
	if key != "" {
		if old, ok := notifications.last[key]; ok && old != id {
			delete(notifications.actions, old) // replaced banner is gone
		}
		notifications.last[key] = id
	}
	if onAction != nil {
		notifications.actions[id] = onAction
	}
	notifications.mu.Unlock()
	return nil
}
