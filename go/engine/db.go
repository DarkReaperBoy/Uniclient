// Package engine is the orchestration layer between the 10 platform cores and the Flutter UI.
// It manages SQLite caching, account lifecycle, auth flows, offline-first pending queue,
// media pipeline, and event dispatch. The UI is a dumb renderer; the engine is the brain.
package engine

import (
	"database/sql"
	"fmt"
	"os"
	"path/filepath"
)

// OpenDB opens (or creates) the SQLite cache database at dir/cache.db.
// WAL mode is enabled for concurrent read/write from multiple goroutines.
// If the database is corrupt, it is renamed to cache.db.corrupt and recreated.
func OpenDB(dir string) (*sql.DB, error) {
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return nil, fmt.Errorf("create db dir: %w", err)
	}

	path := filepath.Join(dir, "cache.db")

	db, err := openAndPragma(path)
	if err != nil {
		// File might be corrupt / not a database. Try recovery.
		db, err = recoverCorrupt(path)
		if err != nil {
			return nil, err
		}
	}

	// Integrity check — detect subtle corruption.
	if err := checkIntegrity(db); err != nil {
		db.Close()
		db, err = recoverCorrupt(path)
		if err != nil {
			return nil, err
		}
	}

	// Run migrations.
	if err := migrateDB(db); err != nil {
		db.Close()
		return nil, fmt.Errorf("migrate: %w", err)
	}

	return db, nil
}

var pragmas = []string{
	"PRAGMA journal_mode = WAL",
	"PRAGMA busy_timeout = 5000",
	"PRAGMA foreign_keys = ON",
	"PRAGMA synchronous = NORMAL",
	"PRAGMA cache_size = -8000", // 8MB cache
}

// openAndPragma opens the SQLite database and sets performance pragmas.
func openAndPragma(path string) (*sql.DB, error) {
	db, err := sql.Open("sqlite", path)
	if err != nil {
		return nil, fmt.Errorf("open database: %w", err)
	}
	for _, p := range pragmas {
		if _, err := db.Exec(p); err != nil {
			db.Close()
			return nil, fmt.Errorf("set pragma %q: %w", p, err)
		}
	}
	return db, nil
}

// recoverCorrupt renames the corrupt DB file and creates a fresh one.
func recoverCorrupt(path string) (*sql.DB, error) {
	corruptPath := path + ".corrupt"
	os.Rename(path, corruptPath)
	os.Rename(path+"-wal", corruptPath+"-wal")
	os.Rename(path+"-shm", corruptPath+"-shm")

	db, err := openAndPragma(path)
	if err != nil {
		return nil, fmt.Errorf("open fresh database: %w", err)
	}
	return db, nil
}

// checkIntegrity runs PRAGMA integrity_check and returns an error if the DB is corrupt.
func checkIntegrity(db *sql.DB) error {
	var result string
	if err := db.QueryRow("PRAGMA integrity_check").Scan(&result); err != nil {
		return fmt.Errorf("integrity check query: %w", err)
	}
	if result != "ok" {
		return fmt.Errorf("corruption detected: %s", result)
	}
	return nil
}

// --- Migrations ---

// Each migration function takes the DB from version N-1 to version N.
// Migrations run inside a transaction for atomicity.
var migrations = []func(*sql.Tx) error{
	migrateV1,
	migrateV2,
	migrateV3,
	migrateV4,
	migrateV5,
	migrateV6,
	migrateV7,
	migrateV8,
	migrateV9,
	migrateV10,
	migrateV11,
	migrateV12,
	migrateV13,
	migrateV14,
	migrateV15,
	migrateV16,
	migrateV17,
	migrateV18,
	migrateV19,
	migrateV20,
}

func migrateDB(db *sql.DB) error {
	var version int
	db.QueryRow("PRAGMA user_version").Scan(&version)

	for i := version; i < len(migrations); i++ {
		tx, err := db.Begin()
		if err != nil {
			return fmt.Errorf("begin tx for v%d: %w", i+1, err)
		}
		if err := migrations[i](tx); err != nil {
			tx.Rollback()
			return fmt.Errorf("v%d: %w", i+1, err)
		}
		if _, err := tx.Exec(fmt.Sprintf("PRAGMA user_version = %d", i+1)); err != nil {
			tx.Rollback()
			return fmt.Errorf("set user_version %d: %w", i+1, err)
		}
		if err := tx.Commit(); err != nil {
			return fmt.Errorf("commit v%d: %w", i+1, err)
		}
	}

	// Cleanup: remove any chats with non-integer type values (bug fix).
	db.Exec("DELETE FROM chats WHERE typeof(type) != 'integer'")

	return nil
}

// migrateV1 creates the initial schema.
func migrateV1(tx *sql.Tx) error {
	stmts := []string{
		// Account registry
		`CREATE TABLE IF NOT EXISTS accounts (
			id           TEXT PRIMARY KEY,
			platform     TEXT NOT NULL,
			display_name TEXT,
			avatar_path  TEXT,
			vault_key    TEXT,
			sort_order   INTEGER NOT NULL DEFAULT 0,
			created_at   INTEGER NOT NULL
		)`,

		// Chat list
		`CREATE TABLE IF NOT EXISTS chats (
			account_id    TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
			chat_id       TEXT NOT NULL,
			type          INTEGER NOT NULL DEFAULT 0,
			title         TEXT NOT NULL DEFAULT '',
			avatar_path   TEXT,
			last_msg_id   TEXT,
			last_msg_text TEXT,
			last_msg_time INTEGER,
			last_msg_sender TEXT,
			last_msg_is_outgoing INTEGER NOT NULL DEFAULT 0,
			unread_count  INTEGER NOT NULL DEFAULT 0,
			is_muted      INTEGER NOT NULL DEFAULT 0,
			is_pinned     INTEGER NOT NULL DEFAULT 0,
			is_archived   INTEGER NOT NULL DEFAULT 0,
			draft_text    TEXT,
			member_count  INTEGER,
			parent_id     TEXT,
			capabilities  TEXT,
			is_verified   INTEGER NOT NULL DEFAULT 0,
			is_scam       INTEGER NOT NULL DEFAULT 0,
			is_fake       INTEGER NOT NULL DEFAULT 0,
			updated_at    INTEGER NOT NULL,
			PRIMARY KEY (account_id, chat_id)
		)`,
		`CREATE INDEX IF NOT EXISTS idx_chats_sort ON chats(is_archived, is_pinned DESC, last_msg_time DESC)`,
		`CREATE INDEX IF NOT EXISTS idx_chats_account ON chats(account_id)`,

		// Messages
		`CREATE TABLE IF NOT EXISTS messages (
			account_id    TEXT NOT NULL,
			chat_id       TEXT NOT NULL,
			msg_id        TEXT NOT NULL,
			local_id      TEXT,
			sender_id     TEXT,
			sender_name   TEXT,
			sender_rank   TEXT,
			content_raw   BLOB,
			content_rich  BLOB,
			content_text  TEXT,
			timestamp     INTEGER NOT NULL,
			edited_at     INTEGER,
			status        INTEGER NOT NULL DEFAULT 2,
			reply_to_id   TEXT,
			reply_preview TEXT,
			forward_from  TEXT,
			is_pinned     INTEGER NOT NULL DEFAULT 0,
			is_outgoing   INTEGER NOT NULL DEFAULT 0,
			has_media     INTEGER NOT NULL DEFAULT 0,
			PRIMARY KEY (account_id, chat_id, msg_id)
		)`,
		`CREATE INDEX IF NOT EXISTS idx_msgs_chat_time ON messages(account_id, chat_id, timestamp DESC)`,
		`CREATE INDEX IF NOT EXISTS idx_msgs_local ON messages(local_id) WHERE local_id IS NOT NULL`,

		// FTS5 full-text search
		`CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING fts5(
			content_text,
			content='messages',
			content_rowid='rowid',
			tokenize='unicode61'
		)`,

		// FTS5 sync triggers
		`CREATE TRIGGER IF NOT EXISTS messages_ai AFTER INSERT ON messages BEGIN
			INSERT INTO messages_fts(rowid, content_text) VALUES (new.rowid, new.content_text);
		END`,
		`CREATE TRIGGER IF NOT EXISTS messages_ad AFTER DELETE ON messages BEGIN
			INSERT INTO messages_fts(messages_fts, rowid, content_text) VALUES('delete', old.rowid, old.content_text);
		END`,
		`CREATE TRIGGER IF NOT EXISTS messages_au AFTER UPDATE ON messages BEGIN
			INSERT INTO messages_fts(messages_fts, rowid, content_text) VALUES('delete', old.rowid, old.content_text);
			INSERT INTO messages_fts(rowid, content_text) VALUES (new.rowid, new.content_text);
		END`,

		// Pending outbox
		`CREATE TABLE IF NOT EXISTS pending (
			id           INTEGER PRIMARY KEY AUTOINCREMENT,
			account_id   TEXT NOT NULL,
			chat_id      TEXT NOT NULL,
			local_id     TEXT NOT NULL UNIQUE,
			action       TEXT NOT NULL,
			payload      BLOB NOT NULL,
			status       INTEGER NOT NULL DEFAULT 0,
			retry_count  INTEGER NOT NULL DEFAULT 0,
			error_msg    TEXT,
			created_at   INTEGER NOT NULL,
			last_attempt INTEGER
		)`,
		`CREATE INDEX IF NOT EXISTS idx_pending_status ON pending(status, created_at)`,

		// User profiles
		`CREATE TABLE IF NOT EXISTS users (
			account_id    TEXT NOT NULL,
			user_id       TEXT NOT NULL,
			display_name  TEXT,
			username      TEXT,
			phone         TEXT,
			bio           TEXT,
			avatar_path   TEXT,
			is_bot        INTEGER NOT NULL DEFAULT 0,
			is_online     INTEGER NOT NULL DEFAULT 0,
			is_contact    INTEGER NOT NULL DEFAULT 0,
			is_blocked    INTEGER NOT NULL DEFAULT 0,
			last_seen     INTEGER,
			updated_at    INTEGER NOT NULL,
			PRIMARY KEY (account_id, user_id)
		)`,

		// Media references
		`CREATE TABLE IF NOT EXISTS media (
			account_id     TEXT NOT NULL,
			chat_id        TEXT NOT NULL,
			msg_id         TEXT NOT NULL,
			seq            INTEGER NOT NULL DEFAULT 0,
			media_type     INTEGER NOT NULL,
			remote_ref     TEXT,
			local_path     TEXT,
			thumb_path     TEXT,
			thumb_b64      TEXT,
			file_name      TEXT,
			mime_type      TEXT,
			file_size      INTEGER,
			duration_ms    INTEGER,
			width          INTEGER,
			height         INTEGER,
			download_state INTEGER NOT NULL DEFAULT 0,
			last_accessed  INTEGER,
			extra          TEXT,
			PRIMARY KEY (account_id, chat_id, msg_id, seq)
		)`,
		`CREATE INDEX IF NOT EXISTS idx_media_evict ON media(last_accessed) WHERE local_path IS NOT NULL`,
	}

	for _, s := range stmts {
		if _, err := tx.Exec(s); err != nil {
			return fmt.Errorf("exec %q: %w", s[:min(60, len(s))], err)
		}
	}
	return nil
}

// --- Chat type constants (stored as integers in DB) ---

const (
	ChatTypeUnspec  = 0
	ChatTypeDMVal   = 1
	ChatTypeGroupVal = 2
	ChatTypeChanVal = 3
	ChatTypeTopicVal = 4
)

// --- Message status constants ---

const (
	MsgStatusSending   = 1
	MsgStatusSent      = 2
	MsgStatusDelivered = 3
	MsgStatusRead      = 4
	MsgStatusFailed    = 5
)

// --- Pending status constants ---

const (
	PendingQueued  = 0
	PendingSending = 1
	PendingFailed  = 2
)

// --- Download state constants ---

const (
	DownloadNone        = 0
	DownloadInProgress  = 1
	DownloadComplete    = 2
	DownloadFailed      = 3
)

// --- Media type constants ---

const (
	MediaImage     = 1
	MediaVideo     = 2
	MediaAudio     = 3
	MediaVoice     = 4
	MediaVideoNote = 5
	MediaSticker   = 6
	MediaGIF       = 7
	MediaFile      = 8
	MediaPoll      = 9
	MediaLocation  = 10
	MediaContact   = 11
)

func columnExists(tx *sql.Tx, table, column string) bool {
	var count int
	tx.QueryRow(`SELECT COUNT(*) FROM pragma_table_info(?) WHERE name = ?`, table, column).Scan(&count)
	return count > 0
}

// migrateV2 adds is_outgoing column to messages table.
func migrateV2(tx *sql.Tx) error {
	if columnExists(tx, "messages", "is_outgoing") {
		return nil
	}
	_, err := tx.Exec(`ALTER TABLE messages ADD COLUMN is_outgoing INTEGER NOT NULL DEFAULT 0`)
	return err
}

// migrateV3 adds last_msg_is_outgoing column to chats table.
func migrateV3(tx *sql.Tx) error {
	if columnExists(tx, "chats", "last_msg_is_outgoing") {
		return nil
	}
	_, err := tx.Exec(`ALTER TABLE chats ADD COLUMN last_msg_is_outgoing INTEGER NOT NULL DEFAULT 0`)
	return err
}

// migrateV4 adds extra column to media table (stores access hash + file reference for downloads).
func migrateV4(tx *sql.Tx) error {
	if columnExists(tx, "media", "extra") {
		return nil
	}
	_, err := tx.Exec(`ALTER TABLE media ADD COLUMN extra TEXT`)
	return err
}

// migrateV5 adds verified/scam/fake columns to chats table.
func migrateV5(tx *sql.Tx) error {
	for _, col := range []string{"is_verified", "is_scam", "is_fake"} {
		if columnExists(tx, "chats", col) {
			continue
		}
		if _, err := tx.Exec(`ALTER TABLE chats ADD COLUMN ` + col + ` INTEGER NOT NULL DEFAULT 0`); err != nil {
			return err
		}
	}
	return nil
}

// migrateV6 adds last_msg_media_type and last_msg_thumb_b64 columns to chats table.
func migrateV6(tx *sql.Tx) error {
	if !columnExists(tx, "chats", "last_msg_media_type") {
		if _, err := tx.Exec(`ALTER TABLE chats ADD COLUMN last_msg_media_type INTEGER NOT NULL DEFAULT 0`); err != nil {
			return err
		}
	}
	if !columnExists(tx, "chats", "last_msg_thumb_b64") {
		if _, err := tx.Exec(`ALTER TABLE chats ADD COLUMN last_msg_thumb_b64 TEXT`); err != nil {
			return err
		}
	}
	return nil
}

// migrateV7 adds unread_mark column to chats table.
func migrateV7(tx *sql.Tx) error {
	if columnExists(tx, "chats", "unread_mark") {
		return nil
	}
	_, err := tx.Exec(`ALTER TABLE chats ADD COLUMN unread_mark INTEGER NOT NULL DEFAULT 0`)
	return err
}

// migrateV8 adds unread_mention_count and unread_reaction_count columns to chats table.
func migrateV8(tx *sql.Tx) error {
	if !columnExists(tx, "chats", "unread_mention_count") {
		if _, err := tx.Exec(`ALTER TABLE chats ADD COLUMN unread_mention_count INTEGER NOT NULL DEFAULT 0`); err != nil {
			return err
		}
	}
	if !columnExists(tx, "chats", "unread_reaction_count") {
		if _, err := tx.Exec(`ALTER TABLE chats ADD COLUMN unread_reaction_count INTEGER NOT NULL DEFAULT 0`); err != nil {
			return err
		}
	}
	return nil
}

// migrateV9 adds last_msg_status column to chats table (send state: 0=none, 1=pending, 2=sent, 3=read).
func migrateV9(tx *sql.Tx) error {
	if columnExists(tx, "chats", "last_msg_status") {
		return nil
	}
	_, err := tx.Exec(`ALTER TABLE chats ADD COLUMN last_msg_status INTEGER NOT NULL DEFAULT 0`)
	return err
}

// migrateV10 adds is_contact and is_blocked columns to users table.
func migrateV10(tx *sql.Tx) error {
	for _, col := range []string{"is_contact", "is_blocked"} {
		if !columnExists(tx, "users", col) {
			if _, err := tx.Exec(`ALTER TABLE users ADD COLUMN ` + col + ` INTEGER NOT NULL DEFAULT 0`); err != nil {
				return err
			}
		}
	}
	return nil
}

// migrateV11 adds sender_rank column to messages table for admin/creator badges.
func migrateV11(tx *sql.Tx) error {
	if columnExists(tx, "messages", "sender_rank") {
		return nil
	}
	_, err := tx.Exec(`ALTER TABLE messages ADD COLUMN sender_rank TEXT`)
	return err
}

// migrateV12 adds sender_color_id column to messages table for extended peer name colors.
// Default -1 means "use senderId % 7 fallback" (distinguishes from actual color_id=0).
func migrateV12(tx *sql.Tx) error {
	if columnExists(tx, "messages", "sender_color_id") {
		return nil
	}
	_, err := tx.Exec(`ALTER TABLE messages ADD COLUMN sender_color_id INTEGER NOT NULL DEFAULT -1`)
	return err
}

func migrateV13(tx *sql.Tx) error {
	if columnExists(tx, "messages", "is_service") {
		return nil
	}
	_, err := tx.Exec(`ALTER TABLE messages ADD COLUMN is_service INTEGER NOT NULL DEFAULT 0`)
	return err
}

func migrateV14(tx *sql.Tx) error {
	if columnExists(tx, "messages", "grouped_id") {
		return nil
	}
	_, err := tx.Exec(`ALTER TABLE messages ADD COLUMN grouped_id TEXT`)
	return err
}

func migrateV15(tx *sql.Tx) error {
	if !columnExists(tx, "chats", "slowmode_seconds") {
		if _, err := tx.Exec(`ALTER TABLE chats ADD COLUMN slowmode_seconds INTEGER NOT NULL DEFAULT 0`); err != nil {
			return err
		}
	}
	if !columnExists(tx, "chats", "slowmode_next_send_date") {
		if _, err := tx.Exec(`ALTER TABLE chats ADD COLUMN slowmode_next_send_date INTEGER NOT NULL DEFAULT 0`); err != nil {
			return err
		}
	}
	return nil
}

func migrateV16(tx *sql.Tx) error {
	if columnExists(tx, "chats", "stars_to_send") {
		return nil
	}
	_, err := tx.Exec(`ALTER TABLE chats ADD COLUMN stars_to_send INTEGER NOT NULL DEFAULT 0`)
	return err
}

func migrateV17(tx *sql.Tx) error {
	if columnExists(tx, "chats", "ttl_period") {
		return nil
	}
	_, err := tx.Exec(`ALTER TABLE chats ADD COLUMN ttl_period INTEGER NOT NULL DEFAULT 0`)
	return err
}

func migrateV18(tx *sql.Tx) error {
	if columnExists(tx, "chats", "emoji_status_id") {
		return nil
	}
	_, err := tx.Exec(`ALTER TABLE chats ADD COLUMN emoji_status_id TEXT`)
	return err
}

func migrateV19(tx *sql.Tx) error {
	if !columnExists(tx, "users", "phone") {
		if _, err := tx.Exec(`ALTER TABLE users ADD COLUMN phone TEXT`); err != nil {
			return err
		}
	}
	if !columnExists(tx, "users", "bio") {
		if _, err := tx.Exec(`ALTER TABLE users ADD COLUMN bio TEXT`); err != nil {
			return err
		}
	}
	return nil
}

func migrateV20(tx *sql.Tx) error {
	if !columnExists(tx, "chats", "story_count") {
		if _, err := tx.Exec(`ALTER TABLE chats ADD COLUMN story_count INTEGER NOT NULL DEFAULT 0`); err != nil {
			return err
		}
	}
	if !columnExists(tx, "chats", "has_unread_story") {
		if _, err := tx.Exec(`ALTER TABLE chats ADD COLUMN has_unread_story INTEGER NOT NULL DEFAULT 0`); err != nil {
			return err
		}
	}
	return nil
}
