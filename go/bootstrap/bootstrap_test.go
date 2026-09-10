package bootstrap

import (
	"encoding/json"
	"fmt"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"uniclient/cores"
	"uniclient/engine"
)

// ---------------------------------------------------------------------------
// Test-only fake core (AGENTS.md §1.10 bans fake platforms in the shipped
// product; test doubles are scaffolding, never registered in the factory the
// GUI uses). It implements just enough of cores.Core to drive the full
// engine pipeline: one chat, folders, an echo reply.
// ---------------------------------------------------------------------------

const fakePlatform = "fake-e2e"

type fakeCore struct {
	cores.StubCore
	mu       sync.Mutex
	handler  func(cores.Update)
	chats    []cores.Dialog
	messages map[string][]cores.Message
	ids      int
}

var _ cores.Core = (*fakeCore)(nil)

func newFakeCore() *fakeCore {
	return &fakeCore{
		messages: map[string][]cores.Message{},
		chats: []cores.Dialog{{
			ID:          "e2e-room",
			Type:        cores.ChatTypeGroup,
			Title:       "E2E Room",
			UnreadCount: 2,
			MemberCount: 3,
			Platform:    fakePlatform,
			Username:    "e2e-room",
		}},
	}
}

func (c *fakeCore) Name() string                        { return fakePlatform }
func (c *fakeCore) Authenticate(cores.AuthConfig) error { return nil }
func (c *fakeCore) Logout() error                       { return nil }
func (c *fakeCore) Close() error                        { return nil }

func (c *fakeCore) OnUpdate(h func(cores.Update)) {
	c.mu.Lock()
	c.handler = h
	c.mu.Unlock()
}

func (c *fakeCore) emit(u cores.Update) {
	c.mu.Lock()
	h := c.handler
	c.mu.Unlock()
	if h != nil {
		u.Platform = fakePlatform
		h(u)
	}
}

func (c *fakeCore) GetFolders() ([]cores.Folder, error) {
	return []cores.Folder{
		{ID: "f-all", Name: "All", IsChatList: true},
		{ID: "f-groups", Name: "Groups", Groups: true},
	}, nil
}

func (c *fakeCore) GetDialogs(cores.PaginationOpts) ([]cores.Dialog, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	return append([]cores.Dialog(nil), c.chats...), nil
}

func (c *fakeCore) GetChatInfo(chatID string) (*cores.Dialog, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	for i := range c.chats {
		if c.chats[i].ID == chatID {
			d := c.chats[i]
			return &d, nil
		}
	}
	return nil, cores.ErrNotFound
}

func (c *fakeCore) GetMessages(chatID string, opts cores.PaginationOpts) ([]cores.Message, error) {
	c.mu.Lock()
	msgs := append([]cores.Message(nil), c.messages[chatID]...)
	c.mu.Unlock()
	// Newest first, like the real cores.
	for i, j := 0, len(msgs)-1; i < j; i, j = i+1, j-1 {
		msgs[i], msgs[j] = msgs[j], msgs[i]
	}
	if opts.Limit > 0 && len(msgs) > opts.Limit {
		msgs = msgs[:opts.Limit]
	}
	return msgs, nil
}

func (c *fakeCore) SendMessage(chatID string, msg cores.OutgoingMessage) (*cores.Message, error) {
	m := c.store(chatID, "me", "You", msg.Text, true, cores.MessageStatusSent)
	go func() {
		time.Sleep(150 * time.Millisecond)
		c.store(chatID, "bot", "Echo Bot", "echo: "+msg.Text, false, cores.MessageStatusDelivered)
	}()
	return &m, nil
}

func (c *fakeCore) GetProfile(string) (*cores.User, error) {
	return &cores.User{ID: "me", DisplayName: "E2E Tester", Platform: fakePlatform}, nil
}

func (c *fakeCore) MarkAsRead(string, string) error { return nil }

func (c *fakeCore) store(chatID, senderID, senderName, text string, outgoing bool, status cores.MessageStatus) cores.Message {
	c.mu.Lock()
	c.ids++
	m := cores.Message{
		ID:         fmt.Sprintf("m%d", c.ids),
		ChatID:     chatID,
		SenderID:   senderID,
		SenderName: senderName,
		Text:       text,
		Timestamp:  time.Now(),
		Status:     status,
		IsOutgoing: outgoing,
		Platform:   fakePlatform,
	}
	c.messages[chatID] = append(c.messages[chatID], m)
	for i := range c.chats {
		if c.chats[i].ID == chatID {
			lm := m
			c.chats[i].LastMessage = &lm
			if !outgoing {
				c.chats[i].UnreadCount++
			}
		}
	}
	c.mu.Unlock()
	c.emit(cores.Update{Type: cores.UpdateNewMessage, ChatID: chatID, Message: &m})
	return m
}

// ---------------------------------------------------------------------------
// Ban enforcement: no placeholder backends anywhere in the product path.
// ---------------------------------------------------------------------------

// TestStartAuthRejectsUnknownPlatforms: the engine must refuse to start auth
// for platforms the factory cannot construct — including the old "demo"
// backend, which is banned by AGENTS.md §1.10.
func TestStartAuthRejectsUnknownPlatforms(t *testing.T) {
	dir := t.TempDir()
	eng, err := Init(dir, filepath.Join(dir, "cache"), filepath.Join(dir, "downloads"), "testpw", nil)
	if err != nil {
		t.Fatalf("Init: %v", err)
	}
	defer eng.Shutdown()

	for _, platform := range []string{"demo", "no-such-backend"} {
		id, err := eng.AddAccount(platform, false)
		if err != nil {
			t.Fatalf("AddAccount(%s): %v", platform, err)
		}
		st, err := eng.StartAuth(id)
		if err == nil && st != nil && st.State != engine.AuthStateError {
			t.Errorf("platform %q must be rejected (got state=%+v, err=%v) — placeholder backends are banned (AGENTS.md §1.10)", platform, st, err)
		}
	}
}

// TestUnsupportedAccountsPurgedAtBoot: a saved account whose platform no
// longer exists (e.g. the banned demo) must be removed at startup, not left
// rotting in the account list as a dead error row.
func TestUnsupportedAccountsPurgedAtBoot(t *testing.T) {
	dir := t.TempDir()
	eng1, err := Init(dir, filepath.Join(dir, "cache"), filepath.Join(dir, "downloads"), "testpw", nil)
	if err != nil {
		t.Fatalf("Init: %v", err)
	}
	// Simulate a stale account left behind by a removed backend.
	if _, err := eng1.AddAccount("demo", false); err != nil {
		t.Fatalf("AddAccount(demo): %v", err)
	}
	eng1.Shutdown()

	eng2, err := Init(dir, filepath.Join(dir, "cache"), filepath.Join(dir, "downloads"), "testpw", nil)
	if err != nil {
		t.Fatalf("re-Init: %v", err)
	}
	defer eng2.Shutdown()

	for _, acc := range eng2.ListAccounts() {
		if acc.Platform == "demo" {
			t.Errorf("stale account %s (platform %q) survived boot — unsupported platforms must be purged at startup", acc.ID, acc.Platform)
		}
	}
}

// TestFactoryConstructsEverySupportedPlatform: every platform in
// SupportedPlatforms() must produce a working core and a real first auth
// step via the production factory.
func TestFactoryConstructsEverySupportedPlatform(t *testing.T) {
	dir := t.TempDir()
	eng, err := Init(dir, filepath.Join(dir, "cache"), filepath.Join(dir, "downloads"), "testpw", nil)
	if err != nil {
		t.Fatalf("Init: %v", err)
	}
	defer eng.Shutdown()

	for _, platform := range SupportedPlatforms() {
		id, err := eng.AddAccount(platform, false)
		if err != nil {
			t.Fatalf("AddAccount(%s): %v", platform, err)
		}
		st, err := eng.StartAuth(id)
		if err != nil {
			t.Errorf("platform %q: core construction failed: %v", platform, err)
			continue
		}
		if st == nil || st.State == engine.AuthStateError {
			t.Errorf("platform %q: no real auth flow (state=%+v)", platform, st)
		}
	}
}

// ---------------------------------------------------------------------------
// Engine end-to-end (regression net for the demo deletion): drives the exact
// saved-account boot path the GUI uses — add account, save credentials,
// connect, sync chats, send, receive events, read the cache, restart, and
// reconnect via ConnectAllAccounts (what happens at every real startup).
// Uses engine.Init directly with a test factory so the fake never leaks into
// the production bootstrap factory.
// ---------------------------------------------------------------------------

func TestEngineEndToEnd(t *testing.T) {
	dir := t.TempDir()
	events := make(chan []byte, 64)

	eng, err := engine.Init(dir, filepath.Join(dir, "cache"), filepath.Join(dir, "downloads"), "testpw")
	if err != nil {
		t.Fatalf("engine.Init: %v", err)
	}
	defer eng.Shutdown()
	eng.SetEventCallback(func(b []byte) {
		select {
		case events <- b:
		default:
		}
	})
	engine.SetCoreFactory(func(platform, accountID string) (cores.Core, error) {
		if platform == fakePlatform {
			return newFakeCore(), nil
		}
		return nil, fmt.Errorf("unknown platform: %s", platform)
	})

	// Add account + save credentials (the saved-account path — accounts
	// restored from the vault at boot never run StartAuth).
	id, err := eng.AddAccount(fakePlatform, false)
	if err != nil {
		t.Fatalf("AddAccount: %v", err)
	}
	if err := eng.SaveCredentials(id, cores.AuthConfig{}); err != nil {
		t.Fatalf("SaveCredentials: %v", err)
	}

	// Connect — same call the GUI/boot makes.
	if err := eng.ConnectAccount(id); err != nil {
		t.Fatalf("ConnectAccount: %v", err)
	}

	// Chats must sync into the engine cache.
	deadline := time.Now().Add(5 * time.Second)
	var chats []engine.ChatInfo
	for time.Now().Before(deadline) {
		chats, err = eng.GetChatList(id, false, 100, 0)
		if err != nil {
			t.Fatalf("GetChatList: %v", err)
		}
		if len(chats) > 0 {
			break
		}
		time.Sleep(100 * time.Millisecond)
	}
	if len(chats) == 0 {
		t.Fatal("fake core produced no chats")
	}

	// Folders must exist (GUI folder tabs rely on the core's GetFolders).
	core := eng.GetAccountCore(id)
	if core == nil {
		t.Fatal("account core is nil after connect")
	}
	folders, err := core.GetFolders()
	if err != nil || len(folders) == 0 {
		t.Fatalf("GetFolders: %v (%d folders)", err, len(folders))
	}

	// Send a message into the first chat and expect the echo.
	first := chats[0]
	_, err = eng.SendMessage(id, first.ChatID, "hello e2e", "", nil, false, 0, "", "", false, false, false, false, false)
	if err != nil {
		t.Fatalf("SendMessage: %v", err)
	}

	sawSend, sawEcho := false, false
	for time.Now().Before(time.Now().Add(5*time.Second)) && !(sawSend && sawEcho) {
		select {
		case raw := <-events:
			var env struct {
				Type string          `json:"type"`
				Data json.RawMessage `json:"data"`
			}
			if json.Unmarshal(raw, &env) != nil {
				continue
			}
			if env.Type == engine.EventMsgReceived {
				var m engine.MsgReceivedEvent
				if json.Unmarshal(env.Data, &m) == nil {
					if m.Message.IsOutgoing {
						sawSend = true
					} else {
						sawEcho = true
					}
				}
			}
		case <-time.After(100 * time.Millisecond):
		}
	}
	if !sawSend {
		t.Error("no msg_received event for the outgoing message")
	}
	if !sawEcho {
		t.Error("no msg_received event for the echo reply")
	}

	// Message cache must contain the sent message.
	msgs, err := eng.GetMessages(id, first.ChatID, 0, 0, 50)
	if err != nil {
		t.Fatalf("GetMessages: %v", err)
	}
	found := false
	for _, m := range msgs {
		if m.ContentText == "hello e2e" {
			found = true
		}
	}
	if !found {
		t.Error("sent message not found in cache")
	}

	// Restart: account persists in the vault and reconnects via the
	// real boot path (ConnectAllAccounts — what App.Start() calls).
	_ = eng.Shutdown()
	eng2, err := engine.Init(dir, filepath.Join(dir, "cache"), filepath.Join(dir, "downloads"), "testpw")
	if err != nil {
		t.Fatalf("re-Init: %v", err)
	}
	defer eng2.Shutdown()
	engine.SetCoreFactory(func(platform, accountID string) (cores.Core, error) {
		if platform == fakePlatform {
			return newFakeCore(), nil
		}
		return nil, fmt.Errorf("unknown platform: %s", platform)
	})

	accs := eng2.ListAccounts()
	if len(accs) != 1 || accs[0].Platform != fakePlatform {
		t.Fatalf("account did not persist: %+v", accs)
	}

	eng2.ConnectAllAccounts()

	deadline = time.Now().Add(5 * time.Second)
	var chats2 []engine.ChatInfo
	for time.Now().Before(deadline) {
		chats2, err = eng2.GetChatList(accs[0].ID, false, 100, 0)
		if err != nil {
			t.Fatalf("GetChatList(restart): %v", err)
		}
		if len(chats2) > 0 {
			break
		}
		time.Sleep(100 * time.Millisecond)
	}
	if len(chats2) == 0 {
		t.Error("chats did not re-sync after restart")
	}
}
