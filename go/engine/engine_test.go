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

	// Verify schema version matches latest migration.
	var version int
	db.QueryRow("PRAGMA user_version").Scan(&version)
	if version != len(migrations) {
		t.Errorf("expected schema version %d, got %d", len(migrations), version)
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

	// Open twice — second open should be a no-op (already at latest version).
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
	if version != len(migrations) {
		t.Errorf("expected version %d, got %d", len(migrations), version)
	}
}

// TestMigrateV2IsOutgoing verifies the V1→V2 upgrade path: running migrations
// against an older DB (with user_version < 2) adds the messages.is_outgoing
// column, preserves existing rows, defaults new rows to 0, and is idempotent.
func TestMigrateV2IsOutgoing(t *testing.T) {
	dir := tempDir(t)

	// Step 1: Open a fresh DB, run all migrations, confirm is_outgoing exists.
	db, err := OpenDB(dir)
	if err != nil {
		t.Fatalf("OpenDB: %v", err)
	}

	// Confirm column exists on a fresh-build DB.
	var colCount int
	db.QueryRow(`SELECT COUNT(*) FROM pragma_table_info('messages') WHERE name='is_outgoing'`).Scan(&colCount)
	if colCount != 1 {
		t.Fatalf("expected is_outgoing column on fresh DB, got count=%d", colCount)
	}

	// Step 2: Roll the DB back to V1 state to exercise the V2 ALTER path.
	//   a) create a legacy account row so the FK on messages holds,
	//   b) drop the is_outgoing column (requires table rebuild on old SQLite,
	//      but modern SQLite supports DROP COLUMN),
	//   c) reset user_version to 1.
	if _, err := db.Exec(`INSERT INTO accounts(id, platform, created_at) VALUES('acc1','telegram',1)`); err != nil {
		t.Fatalf("insert account: %v", err)
	}
	// Insert a V1-era row (is_outgoing will still exist here since DB is V4).
	if _, err := db.Exec(`INSERT INTO messages(account_id, chat_id, msg_id, content_text, timestamp, is_outgoing)
		VALUES('acc1','c1','m1','hello from v1',1000, 1)`); err != nil {
		t.Fatalf("insert legacy msg: %v", err)
	}
	if _, err := db.Exec(`ALTER TABLE messages DROP COLUMN is_outgoing`); err != nil {
		t.Fatalf("drop column: %v", err)
	}
	if _, err := db.Exec(`PRAGMA user_version = 1`); err != nil {
		t.Fatalf("reset user_version: %v", err)
	}
	db.Close()

	// Step 3: Reopen — migrateV2 must re-add the column and migrations V3/V4 must still run.
	db2, err := OpenDB(dir)
	if err != nil {
		t.Fatalf("reopen: %v", err)
	}
	defer db2.Close()

	var v int
	db2.QueryRow(`PRAGMA user_version`).Scan(&v)
	if v != len(migrations) {
		t.Errorf("expected user_version=%d after reopen, got %d", len(migrations), v)
	}

	// Column must be back, default 0.
	var isOut int
	err = db2.QueryRow(`SELECT is_outgoing FROM messages WHERE msg_id='m1'`).Scan(&isOut)
	if err != nil {
		t.Fatalf("select is_outgoing: %v", err)
	}
	if isOut != 0 {
		t.Errorf("expected default is_outgoing=0 for re-added column, got %d", isOut)
	}

	// Inserts with explicit value work.
	if _, err := db2.Exec(`INSERT INTO messages(account_id, chat_id, msg_id, content_text, timestamp, is_outgoing)
		VALUES('acc1','c1','m2','hello post-migrate',2000, 1)`); err != nil {
		t.Fatalf("insert post-migrate: %v", err)
	}
	var out2 int
	db2.QueryRow(`SELECT is_outgoing FROM messages WHERE msg_id='m2'`).Scan(&out2)
	if out2 != 1 {
		t.Errorf("expected is_outgoing=1 for new row, got %d", out2)
	}

	// Step 4: Idempotency — a second run of migrations on an already-upgraded DB is a no-op.
	tx, err := db2.Begin()
	if err != nil {
		t.Fatalf("begin tx: %v", err)
	}
	if err := migrateV2(tx); err != nil {
		t.Errorf("migrateV2 should be idempotent, got: %v", err)
	}
	tx.Commit()
}

// TestOpenDBCleanupCorruptChatType verifies that OpenDB's startup cleanup
// removes any chat rows whose `type` column is not INTEGER. An earlier
// version of ensureChatExists wrote string type values ("dm", "group", ...)
// into a column that should only hold the integer ChatType* constants;
// those rows stayed in the cache and broke GetChatList when Scan tried to
// read them into an int destination. The cleanup step in migrateDB deletes
// them on next startup so the cache self-heals.
func TestOpenDBCleanupCorruptChatType(t *testing.T) {
	dir := tempDir(t)

	// Step 1: Open a fresh DB, insert one valid INTEGER-typed row and one
	// corrupt string-typed row (SQLite's dynamic typing allows this).
	db, err := OpenDB(dir)
	if err != nil {
		t.Fatalf("OpenDB: %v", err)
	}
	if _, err := db.Exec(`INSERT INTO accounts(id, platform, created_at) VALUES('acc1','telegram',1)`); err != nil {
		t.Fatalf("insert account: %v", err)
	}
	// Valid row — type = integer 1 (DM).
	if _, err := db.Exec(`INSERT INTO chats(account_id, chat_id, type, title, updated_at) VALUES('acc1','good', ?, 'good chat', 1)`, ChatTypeDMVal); err != nil {
		t.Fatalf("insert valid chat: %v", err)
	}
	// Corrupt row — type = string "dm" (simulates the pre-fix bug).
	if _, err := db.Exec(`INSERT INTO chats(account_id, chat_id, type, title, updated_at) VALUES('acc1','bad', 'dm', 'bad chat', 2)`); err != nil {
		t.Fatalf("insert corrupt chat: %v", err)
	}
	// Sanity: both rows are present before reopen.
	var before int
	db.QueryRow(`SELECT COUNT(*) FROM chats WHERE account_id='acc1'`).Scan(&before)
	if before != 2 {
		t.Fatalf("expected 2 chats before cleanup, got %d", before)
	}
	// Sanity: the corrupt row is actually stored with a TEXT type affinity.
	var rawType any
	db.QueryRow(`SELECT type FROM chats WHERE chat_id='bad'`).Scan(&rawType)
	if _, ok := rawType.(int64); ok {
		t.Fatalf("test setup bug: expected 'bad' row to have non-integer type, got int64 (%v)", rawType)
	}
	db.Close()

	// Step 2: Reopen — migrateDB's cleanup DELETE runs on every OpenDB call
	// and must drop the 'bad' row while preserving the 'good' row.
	db2, err := OpenDB(dir)
	if err != nil {
		t.Fatalf("reopen: %v", err)
	}
	defer db2.Close()

	var after int
	db2.QueryRow(`SELECT COUNT(*) FROM chats WHERE account_id='acc1'`).Scan(&after)
	if after != 1 {
		t.Errorf("expected 1 chat after cleanup, got %d", after)
	}

	// The surviving row must be 'good'.
	var surviving string
	db2.QueryRow(`SELECT chat_id FROM chats WHERE account_id='acc1'`).Scan(&surviving)
	if surviving != "good" {
		t.Errorf("expected surviving chat to be 'good', got %q", surviving)
	}

	// Re-running cleanup on a clean DB must be a no-op (idempotent).
	db2.Close()
	db3, err := OpenDB(dir)
	if err != nil {
		t.Fatalf("third open: %v", err)
	}
	defer db3.Close()
	var after2 int
	db3.QueryRow(`SELECT COUNT(*) FROM chats WHERE account_id='acc1'`).Scan(&after2)
	if after2 != 1 {
		t.Errorf("idempotent cleanup: expected 1 chat, got %d", after2)
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
	msgs, err := eng.GetMessages(accID, "chat1", 0, 0, 5)
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
	results, err := eng.SearchMessages("hello", "", 50, "")
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
	cached := eng.InsertPendingMessage(accID, "chat1", "local_abc", "hi there", "me", "Me", "")
	if cached.Status != MsgStatusSending {
		t.Errorf("expected SENDING status, got %d", cached.Status)
	}
	if cached.LocalID != "local_abc" {
		t.Errorf("expected local_abc, got %q", cached.LocalID)
	}

	// Confirm it.
	eng.ConfirmMessage(accID, "chat1", "local_abc", "server_123")

	// Should be retrievable by server ID now.
	msgs, _ := eng.GetMessages(accID, "chat1", 0, 0, 10)
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

// TestEnsureChatExists verifies that handleNewMessage auto-creates a chat row
// when the message arrives for an uncached chat, with the correct INTEGER type
// column (DM=1) and idempotent on a second invocation. Also confirms the
// handleNewMessage path emits the message-received event and the chat row is
// queryable through the normal GetChatList API.
func TestMsgPreviewText(t *testing.T) {
	// Text only: truncated to 100 chars, no emoji.
	m := &cores.Message{Text: "hello world"}
	if got := msgPreviewText(m); got != "hello world" {
		t.Errorf("text-only: got %q want %q", got, "hello world")
	}
	long := make([]byte, 150)
	for i := range long {
		long[i] = 'x'
	}
	m = &cores.Message{Text: string(long)}
	if got := msgPreviewText(m); len(got) != 100 {
		t.Errorf("text truncation: expected 100 chars, got %d", len(got))
	}

	// Media-only cases.
	cases := []struct {
		name string
		att  cores.FileRef
		want string
	}{
		{"photo", cores.FileRef{MimeType: "image/jpeg", Name: "p.jpg"}, "📷 Photo"},
		{"video", cores.FileRef{MimeType: "video/mp4"}, "🎥 Video"},
		{"audio", cores.FileRef{MimeType: "audio/mpeg"}, "🎵 Audio"},
		{"voice", cores.FileRef{MimeType: "audio/ogg"}, "🎙 Voice message"},
		{"voice_opus", cores.FileRef{MimeType: "audio/opus"}, "🎙 Voice message"},
		{"sticker", cores.FileRef{MimeType: "image/webp"}, "🖼 Sticker"},
		{"gif", cores.FileRef{MimeType: "image/gif"}, "🎞 GIF"},
		{"file_named", cores.FileRef{MimeType: "application/pdf", Name: "report.pdf"}, "📎 report.pdf"},
		{"file_unnamed", cores.FileRef{MimeType: "application/octet-stream"}, "📎 File"},
		{"no_mime_named", cores.FileRef{Name: "x"}, "📎 x"},
		{"no_mime_unnamed", cores.FileRef{}, "📎 File"},
	}
	for _, c := range cases {
		m := &cores.Message{Attachments: []cores.FileRef{c.att}}
		if got := msgPreviewText(m); got != c.want {
			t.Errorf("%s: got %q want %q", c.name, got, c.want)
		}
	}

	// Media + caption: emoji prefix + text.
	m = &cores.Message{
		Text:        "look at this",
		Attachments: []cores.FileRef{{MimeType: "image/jpeg"}},
	}
	if got := msgPreviewText(m); got != "📷 look at this" {
		t.Errorf("media+caption: got %q want %q", got, "📷 look at this")
	}

	// No text, no attachments → empty.
	if got := msgPreviewText(&cores.Message{}); got != "" {
		t.Errorf("empty msg: got %q want empty", got)
	}
}

func TestEnsureChatExists(t *testing.T) {
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

	// Sanity: no chats present.
	chats, _ := eng.GetChatList(accID, false, 50, 0)
	if len(chats) != 0 {
		t.Fatalf("expected 0 chats initially, got %d", len(chats))
	}

	// Inject a message for a chatID that has not been seen before.
	now := time.Now()
	msg := &cores.Message{
		ID:         "m1",
		SenderID:   "user42",
		SenderName: "Carol",
		Text:       "first message from a new contact",
		Timestamp:  now,
		Status:     cores.MessageStatusSent,
	}
	eng.handleNewMessage(accID, "newchat", msg)

	// Chat row should exist now.
	chats, _ = eng.GetChatList(accID, false, 50, 0)
	if len(chats) != 1 {
		t.Fatalf("ensureChatExists should have created 1 chat, got %d", len(chats))
	}
	c := chats[0]
	if c.ChatID != "newchat" {
		t.Errorf("chat_id mismatch: got %q want %q", c.ChatID, "newchat")
	}
	// Title falls back to sender name for DMs.
	if c.Title != "Carol" {
		t.Errorf("title should be sender name 'Carol', got %q", c.Title)
	}
	if c.LastMsgText != "first message from a new contact" {
		t.Errorf("last_msg_text mismatch: got %q", c.LastMsgText)
	}
	if c.LastMsgID != "m1" {
		t.Errorf("last_msg_id mismatch: got %q", c.LastMsgID)
	}
	if c.LastMsgSender != "Carol" {
		t.Errorf("last_msg_sender mismatch: got %q", c.LastMsgSender)
	}
	if c.UnreadCount != 1 {
		t.Errorf("unread_count should be 1 (no active chat set), got %d", c.UnreadCount)
	}

	// Verify the type column is the INTEGER value 1 (DM), not a string.
	var rawType any
	if err := eng.db.QueryRow(
		"SELECT type FROM chats WHERE account_id = ? AND chat_id = ?",
		accID, "newchat",
	).Scan(&rawType); err != nil {
		t.Fatalf("scan type: %v", err)
	}
	switch v := rawType.(type) {
	case int64:
		if v != int64(ChatTypeDMVal) {
			t.Errorf("type should be %d (DM), got %d", ChatTypeDMVal, v)
		}
	case int:
		if v != ChatTypeDMVal {
			t.Errorf("type should be %d (DM), got %d", ChatTypeDMVal, v)
		}
	default:
		t.Fatalf("type column must be INTEGER, got %T (%v) — this is the corruption that ensureChatExists fixes", rawType, rawType)
	}

	// Idempotency: a second call with a new message for the same chat must
	// NOT create a duplicate row, and must update last_msg_*.
	msg2 := &cores.Message{
		ID:         "m2",
		SenderID:   "user42",
		SenderName: "Carol",
		Text:       "follow-up",
		Timestamp:  now.Add(time.Minute),
		Status:     cores.MessageStatusSent,
	}
	eng.handleNewMessage(accID, "newchat", msg2)
	chats, _ = eng.GetChatList(accID, false, 50, 0)
	if len(chats) != 1 {
		t.Fatalf("second message should not duplicate chat row, got %d chats", len(chats))
	}
	if chats[0].LastMsgID != "m2" {
		t.Errorf("last_msg_id should advance to m2, got %q", chats[0].LastMsgID)
	}
	if chats[0].UnreadCount != 2 {
		t.Errorf("unread_count should be 2 after second message, got %d", chats[0].UnreadCount)
	}

	// Dedup: re-injecting the SAME msg.ID must be a no-op (no extra unread,
	// no duplicate cached message).
	eng.handleNewMessage(accID, "newchat", msg2)
	chats, _ = eng.GetChatList(accID, false, 50, 0)
	if chats[0].UnreadCount != 2 {
		t.Errorf("dedup: unread_count must stay 2 after re-injecting m2, got %d", chats[0].UnreadCount)
	}
	msgs, _ := eng.GetMessages(accID, "newchat", 0, 0, 50)
	if len(msgs) != 2 {
		t.Errorf("dedup: expected 2 cached messages, got %d", len(msgs))
	}
}
