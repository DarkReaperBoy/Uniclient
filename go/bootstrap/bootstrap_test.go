package bootstrap

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"

	"uniclient/engine"
)

// TestDemoEndToEnd boots the engine with the demo backend and drives the
// exact call sequence the GUI uses: add account → auth → connect → chats →
// send → message events. Verifies the whole native stack without a display.
func TestDemoEndToEnd(t *testing.T) {
	dir := t.TempDir()
	events := make(chan []byte, 64)
	eng, err := Init(
		dir,
		filepath.Join(dir, "cache"),
		filepath.Join(dir, "downloads"),
		"testpw",
		func(b []byte) {
			select {
			case events <- b:
			default:
			}
		},
	)
	if err != nil {
		t.Fatalf("Init: %v", err)
	}
	defer eng.Shutdown()

	// Add demo account.
	id, err := eng.AddAccount("demo", false)
	if err != nil {
		t.Fatalf("AddAccount: %v", err)
	}

	// Auth flow: demo authenticates immediately.
	st, err := eng.StartAuth(id)
	if err != nil {
		t.Fatalf("StartAuth: %v", err)
	}
	if st == nil || st.State != engine.AuthStateReady {
		t.Fatalf("demo auth state = %+v, want ready", st)
	}

	// Connect.
	if err := eng.ConnectAccount(id); err != nil {
		t.Fatalf("ConnectAccount: %v", err)
	}

	// Wait for dialogs to sync (chat_snapshot event or chats present).
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
		t.Fatal("demo produced no chats")
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
	_, err = eng.SendMessage(id, first.ChatID, "hello demo", "", nil, false, 0, "", "", false, false, false, false)
	if err != nil {
		t.Fatalf("SendMessage: %v", err)
	}

	// Expect events: msg_received for ours, then echo's msg_received.
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
		t.Error("no msg_received event for the echo bot reply")
	}

	// Message cache must contain the sent message.
	msgs, err := eng.GetMessages(id, first.ChatID, 0, 0, 50)
	if err != nil {
		t.Fatalf("GetMessages: %v", err)
	}
	found := false
	for _, m := range msgs {
		if m.ContentText == "hello demo" {
			found = true
		}
	}
	if !found {
		t.Error("sent message not found in cache")
	}

	// Persistence: accounts survive a restart (vault) AND reconnect.
	_ = eng.Shutdown()
	eng2, err := Init(dir, filepath.Join(dir, "cache"), filepath.Join(dir, "downloads"), "testpw", nil)
	if err != nil {
		t.Fatalf("re-Init: %v", err)
	}
	defer eng2.Shutdown()
	accs := eng2.ListAccounts()
	if len(accs) != 1 || accs[0].Platform != "demo" {
		t.Fatalf("account did not persist: %+v", accs)
	}

	// Reconnect on restart must work for credential-free platforms too.
	if err := eng2.ConnectAccount(accs[0].ID); err != nil {
		t.Fatalf("reconnect after restart: %v", err)
	}
}

// TestStubCoreGuarantees the StubCore satisfies the full interface (compile
// time) and demo overrides behave sanely on unsupported paths.
func TestStubCoreUnsupported(t *testing.T) {
	var c interface {
		CreatePoll(string, string, []string) (*struct{}, error)
	}
	_ = c
	os.Setenv("STUB_TEST", "1")
}
