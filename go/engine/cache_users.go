package engine

import (
	"database/sql"
	"fmt"
	"time"

	"uniclient/cores"
)

// CachedUser is the user profile data returned to the UI from cache.
type CachedUser struct {
	AccountID   string `json:"account_id"`
	UserID      string `json:"user_id"`
	DisplayName string `json:"display_name,omitempty"`
	Username    string `json:"username,omitempty"`
	AvatarPath  string `json:"avatar_path,omitempty"`
	IsBot       bool   `json:"is_bot"`
	IsOnline    bool   `json:"is_online"`
	LastSeen    int64  `json:"last_seen,omitempty"`
}

// UpsertUser inserts or updates a user profile in the cache.
func (e *Engine) UpsertUser(accountID string, u cores.User) error {
	now := time.Now().UnixMilli()
	var lastSeen sql.NullInt64
	if u.LastSeen != nil {
		lastSeen = sql.NullInt64{Int64: u.LastSeen.UnixMilli(), Valid: true}
	}

	_, err := e.db.Exec(
		`INSERT INTO users (account_id, user_id, display_name, username, is_bot, is_online, last_seen, updated_at)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?)
		 ON CONFLICT(account_id, user_id) DO UPDATE SET
		     display_name = excluded.display_name,
		     username = excluded.username,
		     is_bot = excluded.is_bot,
		     is_online = excluded.is_online,
		     last_seen = COALESCE(excluded.last_seen, users.last_seen),
		     updated_at = excluded.updated_at`,
		accountID, u.ID, u.DisplayName, u.Username,
		boolToInt(u.IsBot), boolToInt(u.IsOnline), lastSeen, now)
	return err
}

// GetUser retrieves a cached user profile.
func (e *Engine) GetUser(accountID, userID string) (*CachedUser, error) {
	var u CachedUser
	var displayName, username, avatarPath sql.NullString
	var lastSeen sql.NullInt64
	var isBot, isOnline int

	err := e.db.QueryRow(
		`SELECT account_id, user_id, display_name, username, avatar_path,
		        is_bot, is_online, last_seen
		 FROM users WHERE account_id = ? AND user_id = ?`,
		accountID, userID).Scan(
		&u.AccountID, &u.UserID, &displayName, &username, &avatarPath,
		&isBot, &isOnline, &lastSeen)
	if err != nil {
		return nil, err
	}

	u.DisplayName = displayName.String
	u.Username = username.String
	u.AvatarPath = avatarPath.String
	u.IsBot = isBot == 1
	u.IsOnline = isOnline == 1
	if lastSeen.Valid {
		u.LastSeen = lastSeen.Int64
	}
	return &u, nil
}

// GetOrFetchUser returns a cached user, fetching from core if not cached.
func (e *Engine) GetOrFetchUser(accountID, userID string) (*CachedUser, error) {
	u, err := e.GetUser(accountID, userID)
	if err == nil {
		return u, nil
	}

	// Not cached — try to fetch from core.
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, err
	}

	profile, fetchErr := acc.Core.GetProfile(userID)
	if fetchErr != nil {
		return nil, fetchErr
	}

	e.UpsertUser(accountID, *profile)
	return e.GetUser(accountID, userID)
}

// MemberInfo is the member data returned to the UI for a chat member list.
type MemberInfo struct {
	UserID      string `json:"user_id"`
	Username    string `json:"username,omitempty"`
	DisplayName string `json:"display_name,omitempty"`
	AvatarB64   string `json:"avatar_b64,omitempty"`
	IsBot       bool   `json:"is_bot"`
	IsOnline    bool   `json:"is_online"`
	Role        string `json:"role"` // "owner", "admin", "member", "restricted", "banned"
}

// GetChatMembers fetches members for a chat from the connected core.
func (e *Engine) GetChatMembers(accountID, chatID string, limit, offset int) ([]MemberInfo, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return nil, fmt.Errorf("account not connected: %s", accountID)
	}

	if limit <= 0 {
		limit = 50
	}

	users, err := acc.Core.GetMembers(chatID, cores.PaginationOpts{
		Limit:  limit,
		Offset: fmt.Sprintf("%d", offset),
	})
	if err != nil {
		return nil, err
	}

	// Cache users and convert to MemberInfo.
	members := make([]MemberInfo, 0, len(users))
	for _, u := range users {
		e.UpsertUser(accountID, u)
		members = append(members, MemberInfo{
			UserID:      u.ID,
			Username:    u.Username,
			DisplayName: u.DisplayName,
			AvatarB64:   u.AvatarB64,
			IsBot:       u.IsBot,
			IsOnline:    u.IsOnline,
			Role:        "member", // default; cores can set this via Platform field
		})
	}
	return members, nil
}

// GetOnlineCount returns the number of online members in a chat.
// Delegates to the platform core if it supports the operation.
func (e *Engine) GetOnlineCount(accountID, chatID string) (int, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return 0, fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return 0, fmt.Errorf("account not connected: %s", accountID)
	}
	type onlineCounter interface {
		GetOnlineCount(chatID string) (int, error)
	}
	if oc, ok := acc.Core.(onlineCounter); ok {
		return oc.GetOnlineCount(chatID)
	}
	return 0, nil
}

// ContactInfo is the contact data returned to the UI for the contacts list.
type ContactInfo struct {
	UserID      string `json:"user_id"`
	Username    string `json:"username,omitempty"`
	DisplayName string `json:"display_name,omitempty"`
	Phone       string `json:"phone,omitempty"`
	AvatarB64   string `json:"avatar_b64,omitempty"`
	IsBot       bool   `json:"is_bot"`
	IsOnline    bool   `json:"is_online"`
}

// GetContacts fetches the contact list from the connected core.
func (e *Engine) GetContacts(accountID string) ([]ContactInfo, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return nil, fmt.Errorf("account not connected: %s", accountID)
	}

	users, err := acc.Core.GetContacts()
	if err != nil {
		return nil, err
	}

	contacts := make([]ContactInfo, 0, len(users))
	for _, u := range users {
		e.UpsertUser(accountID, u)
		contacts = append(contacts, ContactInfo{
			UserID:      u.ID,
			Username:    u.Username,
			DisplayName: u.DisplayName,
			Phone:       u.Phone,
			AvatarB64:   u.AvatarB64,
			IsBot:       u.IsBot,
			IsOnline:    u.IsOnline,
		})
	}
	return contacts, nil
}

// BulkUpsertUsers inserts/updates multiple user profiles in a single transaction.
func (e *Engine) BulkUpsertUsers(accountID string, users []cores.User) error {
	tx, err := e.db.Begin()
	if err != nil {
		return err
	}

	stmt, err := tx.Prepare(
		`INSERT INTO users (account_id, user_id, display_name, username, is_bot, is_online, last_seen, updated_at)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?)
		 ON CONFLICT(account_id, user_id) DO UPDATE SET
		     display_name = excluded.display_name,
		     username = excluded.username,
		     is_bot = excluded.is_bot,
		     is_online = excluded.is_online,
		     last_seen = COALESCE(excluded.last_seen, users.last_seen),
		     updated_at = excluded.updated_at`)
	if err != nil {
		tx.Rollback()
		return err
	}
	defer stmt.Close()

	now := time.Now().UnixMilli()
	for _, u := range users {
		var lastSeen sql.NullInt64
		if u.LastSeen != nil {
			lastSeen = sql.NullInt64{Int64: u.LastSeen.UnixMilli(), Valid: true}
		}
		stmt.Exec(accountID, u.ID, u.DisplayName, u.Username,
			boolToInt(u.IsBot), boolToInt(u.IsOnline), lastSeen, now)
	}
	return tx.Commit()
}
