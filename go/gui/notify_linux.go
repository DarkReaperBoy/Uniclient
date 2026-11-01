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

func dbusSession() (*dbus.Conn, error) {
	dbusOnce.Do(func() {
		dbusConn, dbusErr = dbus.ConnectSessionBus()
	})
	return dbusConn, dbusErr
}

type notifyBus struct {
	mu      sync.Mutex
	actions map[uint32]func(string)
	last    map[string]uint32

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
		conn.Signal(ch)
		go n.demux(ch)
	})
}

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

func (n *notifyBus) dispatch(id uint32, action string) {
	n.mu.Lock()
	fn := n.actions[id]
	n.mu.Unlock()
	if fn != nil {
		go fn(action)
	}
}

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
	hints["suppress-sound"] = dbus.MakeVariant(true)

	var id uint32
	call := obj.Call(dbusNotifyIface+".Notify", 0,
		"Uniclient",
		replaces,
		"",
		title,
		body,
		actions,
		hints,
		int32(6000),
	)
	if err := call.Store(&id); err != nil {
		return err
	}
	if id == 0 {
		return nil
	}

	notifications.mu.Lock()
	if key != "" {
		if old, ok := notifications.last[key]; ok && old != id {
			delete(notifications.actions, old)
		}
		notifications.last[key] = id
	}
	if onAction != nil {
		notifications.actions[id] = onAction
	}
	notifications.mu.Unlock()
	return nil
}
