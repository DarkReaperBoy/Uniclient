//go:build linux

package gui

// notify_linux_test.go — slice 141: REAL wire-level verification of the
// interactive notification path against a private dbus-daemon: a fake
// org.freedesktop.Notifications server receives Notify calls (with the
// action list, the per-chat replaces_id and the avatar icon URI), then
// emits org.freedesktop.Notifications.ActionInvoked and NotificationClosed
// signals back at the client — the exact desktop loop, hermetic (own bus,
// own socket). Skips when no dbus-daemon binary exists.

import (
	"sync"
	"testing"
	"time"

	"github.com/godbus/dbus/v5"
)

// fakeNotifyCall is one Notify the server saw.
type fakeNotifyCall struct {
	replaces  uint32
	icon      string
	summary   string
	body      string
	actions   []string
	entry     string // desktop-entry hint
	imagePath string // image-path hint (the avatar)
}

// fakeNotifyServer serves org.freedesktop.Notifications.Notify and can
// emit the spec's ActionInvoked / NotificationClosed signals.
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
	s.mu.Lock()
	s.seq++
	id := s.seq
	s.calls = append(s.calls, fakeNotifyCall{
		replaces: replaces, icon: icon, summary: summary, body: body,
		actions: actions, entry: entry, imagePath: imgPath,
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

// emitAction fires ActionInvoked(id, actionKey) from the server side.
func (s *fakeNotifyServer) emitAction(id uint32, actionKey string) error {
	return s.conn.Emit("/org/freedesktop/Notifications",
		"org.freedesktop.Notifications.ActionInvoked", id, actionKey)
}

// emitClosed fires NotificationClosed(id, reason).
func (s *fakeNotifyServer) emitClosed(id uint32, reason uint32) error {
	return s.conn.Emit("/org/freedesktop/Notifications",
		"org.freedesktop.Notifications.NotificationClosed", id, reason)
}

// resetNotifyGlobals re-arms the package-global session-bus dialer and
// the banner bookkeeping — each -count iteration (or test) gets a fresh
// private bus. The old demux goroutine exits when its conn closes.
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

// waitFor polls cond until true or the deadline (signal round-trips are
// asynchronous).
func waitFor(t *testing.T, what string, cond func() bool) {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		if cond() {
			return
		}
		time.Sleep(20 * time.Millisecond)
	}
	t.Fatalf("timed out waiting for %s", what)
}

func TestNotifyLiveActions(t *testing.T) {
	addr, cleanup := startPrivateBus(t)
	defer cleanup()
	t.Setenv("DBUS_SESSION_BUS_ADDRESS", addr)
	resetNotifyGlobals()

	// Fake notification server owning the well-known name.
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

	// 1. First banner for a chat: fresh (replaces 0), action list, icon.
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

	// 2. The server invokes the default action → the handler fires with
	// the action key.
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

	// 3. Second banner for the SAME chat replaces in place (tdesktop
	// behavior: banners don't stack per chat) and re-arms the handler.
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

	// 4. A DIFFERENT chat gets its own banner (no cross-replace).
	if err := notifyDesktop("Bob", "hi", "acc1/chat2", "",
		notifyDefaultActions, func(k string) { clicked <- k }); err != nil {
		t.Fatalf("notifyDesktop #3: %v", err)
	}
	waitFor(t, "third Notify call", func() bool { return len(srv.callsSnapshot()) >= 3 })
	if got := srv.callsSnapshot()[2].replaces; got != 0 {
		t.Fatalf("other chat's banner replaces_id = %d, want 0", got)
	}

	// 5. NotificationClosed cleans the bookkeeping: the next banner for
	// the chat is fresh again (replaces 0), and the closed id's handler
	// no longer fires.
	if err := srv.emitClosed(2, 3); err != nil { // reason 3 = replaced
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

	// 6. Demux safety: an ActionInvoked for an unknown id never panics
	// and never reaches a live handler.
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
		// id 4's handler must have fired by now.
		t.Fatal("id 4 handler never fired")
	}
}
