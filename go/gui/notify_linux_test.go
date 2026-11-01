//go:build linux

package gui

import (
	"sync"
	"testing"
	"time"

	"github.com/godbus/dbus/v5"
)

type fakeNotifyCall struct {
	replaces  uint32
	icon      string
	summary   string
	body      string
	actions   []string
	entry     string
	imagePath string
	suppress  bool
}

type fakeNotifyServer struct {
	mu    sync.Mutex
	seq   uint32
	calls []fakeNotifyCall
	conn  *dbus.Conn
}

func (s *fakeNotifyServer) Notify(appName string, replaces uint32, icon, summary, body string, actions []string, hints map[string]dbus.Variant, timeout int32) (uint32, *dbus.Error) {
	entry := ""
	if v, ok := hints["desktop-entry"]; ok {
		entry, _ = v.Value().(string)
	}
	imgPath := ""
	if v, ok := hints["image-path"]; ok {
		imgPath, _ = v.Value().(string)
	}
	suppress := false
	if v, ok := hints["suppress-sound"]; ok {
		suppress, _ = v.Value().(bool)
	}
	s.mu.Lock()
	s.seq++
	id := s.seq
	s.calls = append(s.calls, fakeNotifyCall{
		replaces: replaces, icon: icon, summary: summary, body: body,
		actions: actions, entry: entry, imagePath: imgPath, suppress: suppress,
	})
	s.mu.Unlock()
	return id, nil
}

func (s *fakeNotifyServer) callsSnapshot() []fakeNotifyCall {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := make([]fakeNotifyCall, len(s.calls))
	copy(out, s.calls)
	return out
}

func (s *fakeNotifyServer) emitAction(id uint32, actionKey string) error {
	return s.conn.Emit("/org/freedesktop/Notifications",
		"org.freedesktop.Notifications.ActionInvoked", id, actionKey)
}

func (s *fakeNotifyServer) emitClosed(id uint32, reason uint32) error {
	return s.conn.Emit("/org/freedesktop/Notifications",
		"org.freedesktop.Notifications.NotificationClosed", id, reason)
}

func resetNotifyGlobals() {
	dbusOnce = sync.Once{}
	dbusConn = nil
	dbusErr = nil
	notifications.subOnce = sync.Once{}
	notifications.subErr = nil
	notifications.mu.Lock()
	notifications.actions = map[uint32]func(string){}
	notifications.last = map[string]uint32{}
	notifications.mu.Unlock()
}

func TestNotifyLiveActions(t *testing.T) {
	addr, cleanup := startPrivateBus(t)
	defer cleanup()
	t.Setenv("DBUS_SESSION_BUS_ADDRESS", addr)
	resetNotifyGlobals()

	sconn, err := dbus.Dial(addr)
	if err != nil {
		t.Fatalf("server dial: %v", err)
	}
	defer sconn.Close()
	if err := sconn.Auth(nil); err != nil {
		t.Fatalf("server auth: %v", err)
	}
	if err := sconn.Hello(); err != nil {
		t.Fatalf("server hello: %v", err)
	}
	srv := &fakeNotifyServer{conn: sconn}
	if err := sconn.Export(srv, "/org/freedesktop/Notifications", "org.freedesktop.Notifications"); err != nil {
		t.Fatalf("export server: %v", err)
	}
	if reply, err := sconn.RequestName("org.freedesktop.Notifications", dbus.NameFlagDoNotQueue); err != nil || reply != dbus.RequestNameReplyPrimaryOwner {
		t.Fatalf("request name: %v reply=%d", err, reply)
	}

	clicked := make(chan string, 4)
	if err := notifyDesktop("Alice", "hello there", "acc1/chat1", "file:///avatars/alice.png",
		notifyDefaultActions, func(k string) { clicked <- k }); err != nil {
		t.Fatalf("notifyDesktop #1: %v", err)
	}
	waitFor(t, "first Notify call", func() bool { return len(srv.callsSnapshot()) >= 1 })
	c := srv.callsSnapshot()[0]
	if c.replaces != 0 {
		t.Fatalf("first banner replaces_id = %d, want 0", c.replaces)
	}
	if c.summary != "Alice" || c.body != "hello there" {
		t.Fatalf("banner = %q/%q", c.summary, c.body)
	}
	if len(c.actions) != 2 || c.actions[0] != "default" {
		t.Fatalf("actions = %v, want [default …]", c.actions)
	}
	if c.entry != "uniclient" {
		t.Fatalf("desktop-entry hint = %q, want uniclient", c.entry)
	}
	if c.imagePath != "file:///avatars/alice.png" {
		t.Fatalf("image-path hint = %q, want the avatar URI", c.imagePath)
	}
	if !c.suppress {
		t.Fatalf("suppress-sound hint = false, want true (the app chime is the sound)")
	}

	if err := srv.emitAction(1, "default"); err != nil {
		t.Fatalf("emitAction: %v", err)
	}
	select {
	case k := <-clicked:
		if k != "default" {
			t.Fatalf("action key = %q, want default", k)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("ActionInvoked never reached the handler")
	}

	if err := notifyDesktop("Alice", "second message", "acc1/chat1", "",
		notifyDefaultActions, func(k string) { clicked <- k }); err != nil {
		t.Fatalf("notifyDesktop #2: %v", err)
	}
	waitFor(t, "second Notify call", func() bool { return len(srv.callsSnapshot()) >= 2 })
	if got := srv.callsSnapshot()[1].replaces; got != 1 {
		t.Fatalf("second banner replaces_id = %d, want 1 (in-place update)", got)
	}
	if err := srv.emitAction(2, "default"); err != nil {
		t.Fatalf("emitAction #2: %v", err)
	}
	select {
	case <-clicked:
	case <-time.After(5 * time.Second):
		t.Fatal("replaced banner's action handler never fired")
	}

	if err := notifyDesktop("Bob", "hi", "acc1/chat2", "",
		notifyDefaultActions, func(k string) { clicked <- k }); err != nil {
		t.Fatalf("notifyDesktop #3: %v", err)
	}
	waitFor(t, "third Notify call", func() bool { return len(srv.callsSnapshot()) >= 3 })
	if got := srv.callsSnapshot()[2].replaces; got != 0 {
		t.Fatalf("other chat's banner replaces_id = %d, want 0", got)
	}

	if err := srv.emitClosed(2, 3); err != nil {
		t.Fatalf("emitClosed: %v", err)
	}
	waitFor(t, "closed banner cleanup", func() bool {
		notifications.mu.Lock()
		defer notifications.mu.Unlock()
		_, live := notifications.last["acc1/chat1"]
		return !live
	})
	if err := notifyDesktop("Alice", "after close", "acc1/chat1", "",
		notifyDefaultActions, func(k string) { clicked <- k }); err != nil {
		t.Fatalf("notifyDesktop #4: %v", err)
	}
	waitFor(t, "fourth Notify call", func() bool { return len(srv.callsSnapshot()) >= 4 })
	if got := srv.callsSnapshot()[3].replaces; got != 0 {
		t.Fatalf("post-close banner replaces_id = %d, want 0 (entry cleaned)", got)
	}

	if err := srv.emitAction(999, "default"); err != nil {
		t.Fatalf("emitAction unknown: %v", err)
	}
	if err := srv.emitAction(4, "default"); err != nil {
		t.Fatalf("emitAction #4: %v", err)
	}
	select {
	case k := <-clicked:
		if k == "" {
			t.Fatal("empty action key")
		}
	case <-time.After(300 * time.Millisecond):
		t.Fatal("id 4 handler never fired")
	}
}
