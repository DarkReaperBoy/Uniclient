package engine

import (
	"os"
	"path/filepath"
	"testing"
	"time"

	"uniclient/cores"
	"uniclient/utils"
)

func tempDir(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	return dir
}

func TestOpenDB(t *testing.T) {
	dir := tempDir(t)
	db, err := OpenDB(dir)
	if err != nil {
		t.Fatalf("OpenDB: %v", err)
	}
	defer db.Close()

	// Verify WAL mode.
	var journalMode string
	db.QueryRow("PRAGMA journal_mode").Scan(&journalMode)
	if journalMode != "wal" {
		t.Errorf("expected WAL mode, got %q", journalMode)
	}

	// Verify schema version.
	var version int
	db.QueryRow("PRAGMA user_version").Scan(&version)
	if version != 1 {
		t.Errorf("expected schema version 1, got %d", version)
	}

	// Verify tables exist.
	tables := []string{"accounts", "chats", "messages", "pending", "users", "media"}
	for _, table := range tables {
		var name string
		err := db.QueryRow("SELECT name FROM sqlite_master WHERE type='table' AND name=?", table).Scan(&name)
		if err != nil {
			t.Errorf("table %q not found: %v", table, err)
		}
	}

	// Verify FTS5 table.
	var ftsName string
	db.QueryRow("SELECT name FROM sqlite_master WHERE type='table' AND name='messages_fts'").Scan(&ftsName)
	if ftsName != "messages_fts" {
		t.Error("FTS5 table messages_fts not found")
	}
}

func TestDBCorruptionRecovery(t *testing.T) {
	dir := tempDir(t)

	// Create a corrupt DB file.
	corruptPath := filepath.Join(dir, "cache.db")
	os.WriteFile(corruptPath, []byte("not a valid sqlite database"), 0644)

	db, err := OpenDB(dir)
	if err != nil {
		t.Fatalf("OpenDB with corrupt file should recover, got: %v", err)
	}
	defer db.Close()

	// Corrupt file should be renamed.
	if _, err := os.Stat(corruptPath + ".corrupt"); os.IsNotExist(err) {
		t.Error("corrupt file should be renamed to cache.db.corrupt")
	}
}

func TestDBMigrationIdempotent(t *testing.T) {
	dir := tempDir(t)

	// Open twice — second open should be a no-op (already at version 1).
	db1, err := OpenDB(dir)
	if err != nil {
		t.Fatalf("first open: %v", err)
	}
	db1.Close()

	db2, err := OpenDB(dir)
	if err != nil {
		t.Fatalf("second open: %v", err)
	}
	defer db2.Close()

	var version int
	db2.QueryRow("PRAGMA user_version").Scan(&version)
	if version != 1 {
		t.Errorf("expected version 1, got %d", version)
	}
}

func TestEngineInit(t *testing.T) {
	dir := tempDir(t)
	configDir := filepath.Join(dir, "config")
	cacheDir := filepath.Join(dir, "cache")
	downloadDir := filepath.Join(dir, "downloads")

	eng, err := Init(configDir, cacheDir, downloadDir, "test-password")
	if err != nil {
		t.Fatalf("Init: %v", err)
	}
	defer eng.Shutdown()

	// Verify vault was created.
	vaultPath := filepath.Join(configDir, "uniclient.vault")
	if _, err := os.Stat(vaultPath); os.IsNotExist(err) {
		t.Error("vault file should exist")
	}

	// Verify config was created.
	if eng.config == nil {
		t.Fatal("config should not be nil")
	}
	if eng.config.Theme != "dark" {
		t.Errorf("expected dark theme, got %q", eng.config.Theme)
	}

	// Verify DB is open.
	if eng.db == nil {
		t.Fatal("db should not be nil")
	}
}

func TestAccountCRUD(t *testing.T) {
	dir := tempDir(t)
	eng, err := Init(
		filepath.Join(dir, "config"),
		filepath.Join(dir, "cache"),
		filepath.Join(dir, "downloads"),
		"test-pw")
	if err != nil {
		t.Fatalf("Init: %v", err)
	}
	defer eng.Shutdown()

	// Add account.
	id, err := eng.AddAccount("telegram")
	if err != nil {
		t.Fatalf("AddAccount: %v", err)
	}
	if id == "" {
		t.Fatal("account ID should not be empty")
	}
	if len(id) < 5 {
		t.Errorf("account ID too short: %q", id)
	}

	// List accounts.
	accounts := eng.ListAccounts()
	if len(accounts) != 1 {
		t.Fatalf("expected 1 account, got %d", len(accounts))
	}
	if accounts[0].Platform != "telegram" {
		t.Errorf("expected telegram, got %q", accounts[0].Platform)
	}

	// Save and load credentials.
	creds := cores.AuthConfig{Mode: cores.AuthModeBot, BotToken: "123:ABC"}
	if err := eng.SaveCredentials(id, creds); err != nil {
		t.Fatalf("SaveCredentials: %v", err)
	}
	loaded, err := eng.LoadCredentials(id)
	if err != nil {
		t.Fatalf("LoadCredentials: %v", err)
	}
	if loaded.BotToken != "123:ABC" {
		t.Errorf("expected 123:ABC, got %q", loaded.BotToken)
	}

	// Add second account.
	id2, err := eng.AddAccount("matrix")
	if err != nil {
		t.Fatalf("AddAccount 2: %v", err)
	}

	// Reorder.
	if err := eng.ReorderAccounts([]string{id2, id}); err != nil {
		t.Fatalf("ReorderAccounts: %v", err)
	}
	accounts = eng.ListAccounts()
	if accounts[0].ID != id2 {
		t.Errorf("after reorder, first should be %s, got %s", id2, accounts[0].ID)
	}

	// Remove.
	if err := eng.RemoveAccount(id); err != nil {
		t.Fatalf("RemoveAccount: %v", err)
	}
	accounts = eng.ListAccounts()
	if len(accounts) != 1 {
		t.Errorf("expected 1 account after removal, got %d", len(accounts))
	}
}

func TestChatListCRUD(t *testing.T) {
	dir := tempDir(t)
	eng, err := Init(
		filepath.Join(dir, "config"),
		filepath.Join(dir, "cache"),
		filepath.Join(dir, "downloads"),
		"pw")
	if err != nil {
		t.Fatalf("Init: %v", err)
	}
	defer eng.Shutdown()

	accID, _ := eng.AddAccount("telegram")

	// Upsert chats.
	now := time.Now()
	eng.UpsertChat(accID, cores.Dialog{
		ID: "chat1", Type: cores.ChatTypeDM, Title: "Alice",
		UnreadCount: 3,
		LastMessage: &cores.Message{ID: "m1", Text: "hello", Timestamp: now},
	})
	eng.UpsertChat(accID, cores.Dialog{
		ID: "chat2", Type: cores.ChatTypeGroup, Title: "Devs",
		IsPinned: true,
		LastMessage: &cores.Message{ID: "m2", Text: "update", Timestamp: now.Add(-time.Hour)},
	})

	// Get unified list.
	chats, err := eng.GetUnifiedChatList(50, 0)
	if err != nil {
		t.Fatalf("GetUnifiedChatList: %v", err)
	}
	if len(chats) != 2 {
		t.Fatalf("expected 2 chats, got %d", len(chats))
	}
	// Pinned first.
	if chats[0].Title != "Devs" {
		t.Errorf("pinned chat should be first, got %q", chats[0].Title)
	}

	// Draft.
	eng.SaveDraft(accID, "chat1", "draft text")
	chats, _ = eng.GetChatList(accID, false, 50, 0)
	found := false
	for _, c := range chats {
		if c.ChatID == "chat1" && c.DraftText == "draft text" {
			found = true
		}
	}
	if !found {
		t.Error("draft not saved")
	}

	// Archive.
	eng.ArchiveChat(accID, "chat2", true)
	chats, _ = eng.GetUnifiedChatList(50, 0)
	if len(chats) != 1 {
		t.Errorf("archived chat should be hidden, got %d chats", len(chats))
	}
}

func TestMessageCacheAndFTS(t *testing.T) {
	dir := tempDir(t)
	eng, err := Init(
		filepath.Join(dir, "config"),
		filepath.Join(dir, "cache"),
		filepath.Join(dir, "downloads"),
		"pw")
	if err != nil {
		t.Fatalf("Init: %v", err)
	}
	defer eng.Shutdown()

	accID, _ := eng.AddAccount("telegram")
	eng.UpsertChat(accID, cores.Dialog{ID: "chat1", Title: "Test"})

	now := time.Now()

	// Cache messages.
	for i := 0; i < 10; i++ {
		eng.cacheMessage(accID, "chat1", &cores.Message{
			ID:        "msg" + string(rune('a'+i)),
			SenderID:  "user1",
			Text:      "hello world message " + string(rune('a'+i)),
			Timestamp: now.Add(time.Duration(i) * time.Minute),
			Status:    cores.MessageStatusSent,
		})
	}

	// Get most recent.
	msgs, err := eng.GetMessages(accID, "chat1", 0, 5)
	if err != nil {
		t.Fatalf("GetMessages: %v", err)
	}
	if len(msgs) != 5 {
		t.Errorf("expected 5 messages, got %d", len(msgs))
	}
	// Should be in reverse chronological order.
	if msgs[0].Timestamp < msgs[1].Timestamp {
		t.Error("messages should be newest first")
	}

	// FTS5 search.
	results, err := eng.SearchMessages("hello", "", 50)
	if err != nil {
		t.Fatalf("SearchMessages: %v", err)
	}
	if len(results) != 10 {
		t.Errorf("expected 10 search results, got %d", len(results))
	}
}

func TestPendingMessage(t *testing.T) {
	dir := tempDir(t)
	eng, err := Init(
		filepath.Join(dir, "config"),
		filepath.Join(dir, "cache"),
		filepath.Join(dir, "downloads"),
		"pw")
	if err != nil {
		t.Fatalf("Init: %v", err)
	}
	defer eng.Shutdown()

	accID, _ := eng.AddAccount("telegram")
	eng.UpsertChat(accID, cores.Dialog{ID: "chat1", Title: "Test"})

	// Insert pending message.
	cached := eng.InsertPendingMessage(accID, "chat1", "local_abc", "hi there", "me", "Me")
	if cached.Status != MsgStatusSending {
		t.Errorf("expected SENDING status, got %d", cached.Status)
	}
	if cached.LocalID != "local_abc" {
		t.Errorf("expected local_abc, got %q", cached.LocalID)
	}

	// Confirm it.
	eng.ConfirmMessage(accID, "chat1", "local_abc", "server_123")

	// Should be retrievable by server ID now.
	msgs, _ := eng.GetMessages(accID, "chat1", 0, 10)
	if len(msgs) != 1 {
		t.Fatalf("expected 1 message, got %d", len(msgs))
	}
	if msgs[0].MsgID != "server_123" {
		t.Errorf("expected server_123, got %q", msgs[0].MsgID)
	}
	if msgs[0].Status != MsgStatusSent {
		t.Errorf("expected SENT status, got %d", msgs[0].Status)
	}
}

func TestUserCache(t *testing.T) {
	dir := tempDir(t)
	eng, err := Init(
		filepath.Join(dir, "config"),
		filepath.Join(dir, "cache"),
		filepath.Join(dir, "downloads"),
		"pw")
	if err != nil {
		t.Fatalf("Init: %v", err)
	}
	defer eng.Shutdown()

	accID, _ := eng.AddAccount("telegram")

	// Upsert user.
	err = eng.UpsertUser(accID, cores.User{
		ID: "u1", DisplayName: "Alice", Username: "alice", IsOnline: true,
	})
	if err != nil {
		t.Fatalf("UpsertUser: %v", err)
	}

	// Get user.
	u, err := eng.GetUser(accID, "u1")
	if err != nil {
		t.Fatalf("GetUser: %v", err)
	}
	if u.DisplayName != "Alice" {
		t.Errorf("expected Alice, got %q", u.DisplayName)
	}
	if !u.IsOnline {
		t.Error("expected online")
	}

	// Bulk upsert.
	users := []cores.User{
		{ID: "u2", DisplayName: "Bob"},
		{ID: "u3", DisplayName: "Charlie"},
	}
	if err := eng.BulkUpsertUsers(accID, users); err != nil {
		t.Fatalf("BulkUpsertUsers: %v", err)
	}
	u2, _ := eng.GetUser(accID, "u2")
	if u2.DisplayName != "Bob" {
		t.Errorf("expected Bob, got %q", u2.DisplayName)
	}
}

func TestEngineShutdown(t *testing.T) {
	dir := tempDir(t)
	eng, err := Init(
		filepath.Join(dir, "config"),
		filepath.Join(dir, "cache"),
		filepath.Join(dir, "downloads"),
		"pw")
	if err != nil {
		t.Fatalf("Init: %v", err)
	}

	// Shutdown should not panic.
	if err := eng.Shutdown(); err != nil {
		t.Fatalf("Shutdown: %v", err)
	}
}

func TestEngineVaultPersistence(t *testing.T) {
	dir := tempDir(t)
	configDir := filepath.Join(dir, "config")
	cacheDir := filepath.Join(dir, "cache")
	dlDir := filepath.Join(dir, "dl")

	// Create engine, add account with credentials.
	eng, err := Init(configDir, cacheDir, dlDir, "mypass")
	if err != nil {
		t.Fatalf("Init 1: %v", err)
	}
	accID, _ := eng.AddAccount("github")
	eng.SaveCredentials(accID, cores.AuthConfig{Mode: cores.AuthModeBot, BotToken: "ghp_secret"})
	eng.Shutdown()

	// Reopen — account and credentials should survive.
	eng2, err := Init(configDir, cacheDir, dlDir, "mypass")
	if err != nil {
		t.Fatalf("Init 2: %v", err)
	}
	defer eng2.Shutdown()

	accounts := eng2.ListAccounts()
	if len(accounts) != 1 {
		t.Fatalf("expected 1 account after restart, got %d", len(accounts))
	}
	if accounts[0].Platform != "github" {
		t.Errorf("expected github, got %q", accounts[0].Platform)
	}

	creds, err := eng2.LoadCredentials(accounts[0].ID)
	if err != nil {
		t.Fatalf("LoadCredentials after restart: %v", err)
	}
	if creds.BotToken != "ghp_secret" {
		t.Errorf("expected ghp_secret, got %q", creds.BotToken)
	}
}

func TestEventCallbackFires(t *testing.T) {
	dir := tempDir(t)
	eng, err := Init(
		filepath.Join(dir, "config"),
		filepath.Join(dir, "cache"),
		filepath.Join(dir, "downloads"),
		"pw")
	if err != nil {
		t.Fatalf("Init: %v", err)
	}
	defer eng.Shutdown()

	var received []byte
	eng.SetEventCallback(func(data []byte) {
		received = data
	})

	eng.emitEvent(EventAccountList, "", "test")

	if received == nil {
		t.Error("event callback should have fired")
	}
}

func TestActiveChat(t *testing.T) {
	dir := tempDir(t)
	eng, err := Init(
		filepath.Join(dir, "config"),
		filepath.Join(dir, "cache"),
		filepath.Join(dir, "downloads"),
		"pw")
	if err != nil {
		t.Fatalf("Init: %v", err)
	}
	defer eng.Shutdown()

	eng.SetActiveChat("acc1", "chat1")
	if !eng.isActiveChat("acc1", "chat1") {
		t.Error("should be active chat")
	}
	if eng.isActiveChat("acc1", "chat2") {
		t.Error("should not be active chat")
	}

	eng.ClearActiveChat()
	if eng.isActiveChat("acc1", "chat1") {
		t.Error("should not be active after clear")
	}
}

func TestWrongVaultPassword(t *testing.T) {
	dir := tempDir(t)
	configDir := filepath.Join(dir, "config")
	cacheDir := filepath.Join(dir, "cache")
	dlDir := filepath.Join(dir, "dl")

	// Create with password.
	eng, err := Init(configDir, cacheDir, dlDir, "correct")
	if err != nil {
		t.Fatalf("Init: %v", err)
	}
	eng.Shutdown()

	// Open with wrong password.
	_, err = Init(configDir, cacheDir, dlDir, "wrong")
	if err == nil {
		t.Fatal("should fail with wrong password")
	}
	if err.Error() != "open vault: wrong vault password" {
		t.Logf("error: %v (acceptable)", err)
	}
}

func TestConcurrentChatListAccess(t *testing.T) {
	dir := tempDir(t)
	eng, err := Init(
		filepath.Join(dir, "config"),
		filepath.Join(dir, "cache"),
		filepath.Join(dir, "downloads"),
		"pw")
	if err != nil {
		t.Fatalf("Init: %v", err)
	}
	defer eng.Shutdown()

	accID, _ := eng.AddAccount("telegram")

	// Concurrent writes and reads.
	done := make(chan bool, 20)
	for i := 0; i < 10; i++ {
		go func(i int) {
			eng.UpsertChat(accID, cores.Dialog{
				ID:    "chat" + string(rune('a'+i)),
				Title: "Chat " + string(rune('a'+i)),
				LastMessage: &cores.Message{
					ID: "m", Text: "hi", Timestamp: time.Now(),
				},
			})
			done <- true
		}(i)
	}
	for i := 0; i < 10; i++ {
		go func() {
			eng.GetUnifiedChatList(50, 0)
			done <- true
		}()
	}
	for i := 0; i < 20; i++ {
		<-done
	}
}

// Dummy test for vault import — just make sure utils is accessible.
func TestUtilsAccessible(t *testing.T) {
	if utils.DefaultConfig().Theme != "dark" {
		t.Error("utils.DefaultConfig should have dark theme")
	}
}
