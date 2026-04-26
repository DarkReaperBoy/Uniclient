package engine

import (
	"database/sql"
	"fmt"
	"os"
	"time"

	"uniclient/cores"
)

// CachedUser is the user profile data returned to the UI from cache.
type CachedUser struct {
	AccountID   string `json:"account_id"`
	UserID      string `json:"user_id"`
	DisplayName string `json:"display_name,omitempty"`
	Username    string `json:"username,omitempty"`
	Phone       string `json:"phone,omitempty"`
	Bio         string `json:"bio,omitempty"`
	AvatarPath  string `json:"avatar_path,omitempty"`
	IsBot       bool   `json:"is_bot"`
	IsOnline    bool   `json:"is_online"`
	IsContact   bool   `json:"is_contact"`
	IsBlocked   bool   `json:"is_blocked"`
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
		`INSERT INTO users (account_id, user_id, display_name, username, phone, bio, is_bot, is_online, is_contact, is_blocked, last_seen, updated_at)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
		 ON CONFLICT(account_id, user_id) DO UPDATE SET
		     display_name = excluded.display_name,
		     username = excluded.username,
		     phone = COALESCE(NULLIF(excluded.phone, ''), users.phone),
		     bio = COALESCE(NULLIF(excluded.bio, ''), users.bio),
		     is_bot = excluded.is_bot,
		     is_online = excluded.is_online,
		     is_contact = excluded.is_contact,
		     is_blocked = excluded.is_blocked,
		     last_seen = COALESCE(excluded.last_seen, users.last_seen),
		     updated_at = excluded.updated_at`,
		accountID, u.ID, u.DisplayName, u.Username, u.Phone, u.Bio,
		boolToInt(u.IsBot), boolToInt(u.IsOnline), boolToInt(u.IsContact), boolToInt(u.IsBlocked), lastSeen, now)
	return err
}

// GetUser retrieves a cached user profile.
func (e *Engine) GetUser(accountID, userID string) (*CachedUser, error) {
	var u CachedUser
	var displayName, username, phone, bio, avatarPath sql.NullString
	var lastSeen sql.NullInt64
	var isBot, isOnline, isContact, isBlocked int

	err := e.db.QueryRow(
		`SELECT account_id, user_id, display_name, username, phone, bio, avatar_path,
		        is_bot, is_online, is_contact, is_blocked, last_seen
		 FROM users WHERE account_id = ? AND user_id = ?`,
		accountID, userID).Scan(
		&u.AccountID, &u.UserID, &displayName, &username, &phone, &bio, &avatarPath,
		&isBot, &isOnline, &isContact, &isBlocked, &lastSeen)
	if err != nil {
		return nil, err
	}

	u.DisplayName = displayName.String
	u.Username = username.String
	u.Phone = phone.String
	u.Bio = bio.String
	u.AvatarPath = avatarPath.String
	u.IsBot = isBot == 1
	u.IsOnline = isOnline == 1
	u.IsContact = isContact == 1
	u.IsBlocked = isBlocked == 1
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

type fullUserProvider interface {
	GetFullUser(userID string) (*cores.User, error)
}

// GetUserProfile returns a full user profile, fetching bio via GetFullUser if supported.
func (e *Engine) GetUserProfile(accountID, userID string) (*CachedUser, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return e.GetUser(accountID, userID)
	}

	if fup, ok := acc.Core.(fullUserProvider); ok {
		fullUser, err := fup.GetFullUser(userID)
		if err == nil {
			e.UpsertUser(accountID, *fullUser)
			return e.GetUser(accountID, userID)
		}
	}

	return e.GetOrFetchUser(accountID, userID)
}

type profilePhotoUploader interface {
	UploadProfilePhoto(pngData []byte) error
}

type fallbackPhotoManager interface {
	UploadFallbackPhoto(pngData []byte) error
	DeleteFallbackPhoto() error
	HasFallbackPhoto() (bool, error)
}

type selfBioGetter interface {
	GetSelfBio() (string, error)
}

func (e *Engine) GetSelfBio(accountID string) (string, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return "", fmt.Errorf("account %q not connected", accountID)
	}
	bg, ok := acc.Core.(selfBioGetter)
	if !ok {
		return "", fmt.Errorf("platform does not support self bio")
	}
	return bg.GetSelfBio()
}

type selfBirthdayGetter interface {
	GetSelfBirthday() (day, month, year int, err error)
}

func (e *Engine) GetSelfBirthday(accountID string) (day, month, year int, err error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return 0, 0, 0, fmt.Errorf("account %q not connected", accountID)
	}
	bg, ok := acc.Core.(selfBirthdayGetter)
	if !ok {
		return 0, 0, 0, fmt.Errorf("platform does not support birthday")
	}
	return bg.GetSelfBirthday()
}

type birthdayUpdater interface {
	UpdateBirthday(day, month, year int) error
}

func (e *Engine) UpdateBirthday(accountID string, day, month, year int) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not connected", accountID)
	}
	bu, ok := acc.Core.(birthdayUpdater)
	if !ok {
		return fmt.Errorf("platform does not support birthday update")
	}
	return bu.UpdateBirthday(day, month, year)
}

type bioUpdater interface {
	UpdateBio(bio string) error
}

func (e *Engine) UpdateBio(accountID, bio string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not connected", accountID)
	}
	bu, ok := acc.Core.(bioUpdater)
	if !ok {
		return fmt.Errorf("platform does not support bio update")
	}
	return bu.UpdateBio(bio)
}

func (e *Engine) UploadProfilePhoto(accountID, filePath string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not connected", accountID)
	}
	upl, ok := acc.Core.(profilePhotoUploader)
	if !ok {
		return fmt.Errorf("platform does not support profile photo upload")
	}
	data, err := os.ReadFile(filePath)
	if err != nil {
		return fmt.Errorf("read photo: %w", err)
	}
	return upl.UploadProfilePhoto(data)
}

func (e *Engine) UploadFallbackPhoto(accountID, filePath string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not connected", accountID)
	}
	fm, ok := acc.Core.(fallbackPhotoManager)
	if !ok {
		return fmt.Errorf("platform does not support fallback photo")
	}
	data, err := os.ReadFile(filePath)
	if err != nil {
		return fmt.Errorf("read photo: %w", err)
	}
	return fm.UploadFallbackPhoto(data)
}

func (e *Engine) DeleteFallbackPhoto(accountID string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not connected", accountID)
	}
	fm, ok := acc.Core.(fallbackPhotoManager)
	if !ok {
		return fmt.Errorf("platform does not support fallback photo")
	}
	return fm.DeleteFallbackPhoto()
}

func (e *Engine) HasFallbackPhoto(accountID string) (bool, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return false, fmt.Errorf("account %q not connected", accountID)
	}
	fm, ok := acc.Core.(fallbackPhotoManager)
	if !ok {
		return false, nil
	}
	return fm.HasFallbackPhoto()
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
		role := u.Role
		if role == "" {
			role = "member"
		}
		members = append(members, MemberInfo{
			UserID:      u.ID,
			Username:    u.Username,
			DisplayName: u.DisplayName,
			AvatarB64:   u.AvatarB64,
			IsBot:       u.IsBot,
			IsOnline:    u.IsOnline,
			Role:        role,
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

// SimilarChannelInfo is the data returned to the UI for similar channels.
type SimilarChannelInfo struct {
	ChatID      string `json:"chat_id"`
	Title       string `json:"title"`
	AvatarB64   string `json:"avatar_b64,omitempty"`
	MemberCount int    `json:"member_count,omitempty"`
}

// GetSimilarChannels returns channels similar to the given channel.
func (e *Engine) GetSimilarChannels(accountID, chatID string) ([]SimilarChannelInfo, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return nil, fmt.Errorf("account not connected: %s", accountID)
	}
	type similarProvider interface {
		GetSimilarChannels(chatID string) ([]cores.Dialog, error)
	}
	sp, ok := acc.Core.(similarProvider)
	if !ok {
		return nil, fmt.Errorf("platform does not support similar channels")
	}
	dialogs, err := sp.GetSimilarChannels(chatID)
	if err != nil {
		return nil, err
	}
	result := make([]SimilarChannelInfo, 0, len(dialogs))
	for _, d := range dialogs {
		result = append(result, SimilarChannelInfo{
			ChatID:      d.ID,
			Title:       d.Title,
			AvatarB64:   d.AvatarB64,
			MemberCount: d.MemberCount,
		})
	}
	return result, nil
}

// BotCommandInfo is a bot command returned to the UI for autocomplete.
type BotCommandInfo struct {
	Command     string `json:"command"`
	Description string `json:"description"`
	BotID       string `json:"bot_id"`
	BotName     string `json:"bot_name"`
	BotUsername string `json:"bot_username"`
}

// GetChatBotCommands returns bot commands available in a chat.
func (e *Engine) GetChatBotCommands(accountID, chatID string) ([]BotCommandInfo, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return nil, fmt.Errorf("account not connected: %s", accountID)
	}
	type botCommandProvider interface {
		GetChatBotCommands(chatID string) ([]cores.BotCommandEntry, error)
	}
	bp, ok := acc.Core.(botCommandProvider)
	if !ok {
		return nil, nil
	}
	entries, err := bp.GetChatBotCommands(chatID)
	if err != nil {
		return nil, err
	}
	result := make([]BotCommandInfo, 0, len(entries))
	for _, e := range entries {
		result = append(result, BotCommandInfo{
			Command:     e.Command,
			Description: e.Description,
			BotID:       e.BotID,
			BotName:     e.BotName,
			BotUsername: e.BotUsername,
		})
	}
	return result, nil
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
		`INSERT INTO users (account_id, user_id, display_name, username, is_bot, is_online, is_contact, is_blocked, last_seen, updated_at)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
		 ON CONFLICT(account_id, user_id) DO UPDATE SET
		     display_name = excluded.display_name,
		     username = excluded.username,
		     is_bot = excluded.is_bot,
		     is_online = excluded.is_online,
		     is_contact = excluded.is_contact,
		     is_blocked = excluded.is_blocked,
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
			boolToInt(u.IsBot), boolToInt(u.IsOnline), boolToInt(u.IsContact), boolToInt(u.IsBlocked), lastSeen, now)
	}
	return tx.Commit()
}

// BlockUser blocks a user via the core and updates local DB.
func (e *Engine) BlockUser(accountID, userID string) error {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return fmt.Errorf("account not connected: %s", accountID)
	}
	if err := acc.Core.BlockUser(userID); err != nil {
		return err
	}
	e.db.Exec("UPDATE users SET is_blocked = 1 WHERE account_id = ? AND user_id = ?", accountID, userID)
	e.emitChatUpdate(accountID, userID)
	return nil
}

// UnblockUser unblocks a user via the core and updates local DB.
func (e *Engine) UnblockUser(accountID, userID string) error {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return fmt.Errorf("account not connected: %s", accountID)
	}
	if err := acc.Core.UnblockUser(userID); err != nil {
		return err
	}
	e.db.Exec("UPDATE users SET is_blocked = 0 WHERE account_id = ? AND user_id = ?", accountID, userID)
	e.emitChatUpdate(accountID, userID)
	return nil
}

func (e *Engine) BanMember(accountID, chatID, userID string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}
	return acc.Core.BanMember(chatID, userID)
}

func (e *Engine) RemoveMember(accountID, chatID, userID string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}
	return acc.Core.RemoveMember(chatID, userID)
}

func (e *Engine) DemoteAdmin(accountID, chatID, userID string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}
	type demotable interface {
		DemoteAdmin(chatID, userID string) error
	}
	if d, ok := acc.Core.(demotable); ok {
		return d.DemoteAdmin(chatID, userID)
	}
	return fmt.Errorf("platform does not support DemoteAdmin")
}

func (e *Engine) PromoteAdmin(accountID, chatID, userID string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}
	type promotable interface {
		PromoteToAdmin(chatID, userID string) error
	}
	if p, ok := acc.Core.(promotable); ok {
		return p.PromoteToAdmin(chatID, userID)
	}
	return fmt.Errorf("platform does not support PromoteAdmin")
}

func (e *Engine) RestrictMember(accountID, chatID, userID string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}
	type restrictable interface {
		RestrictMember(chatID, userID string) error
	}
	if r, ok := acc.Core.(restrictable); ok {
		return r.RestrictMember(chatID, userID)
	}
	return fmt.Errorf("platform does not support RestrictMember")
}

// ReportSpam reports a chat as spam via the core and blocks the sender.
func (e *Engine) ReportSpam(accountID, chatID string) error {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return fmt.Errorf("account not connected: %s", accountID)
	}
	_ = acc.Core.BlockUser(chatID)
	e.db.Exec("UPDATE users SET is_blocked = 1 WHERE account_id = ? AND user_id = ?", accountID, chatID)
	e.emitChatUpdate(accountID, chatID)
	return nil
}

// GetLinkedChatId returns the linked discussion group ID for a channel.
func (e *Engine) GetLinkedChatId(accountID, chatID string) (string, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return "", fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return "", fmt.Errorf("account not connected: %s", accountID)
	}
	d, err := acc.Core.GetChatInfo(chatID)
	if err != nil {
		return "", err
	}
	return d.LinkedChatId, nil
}

// AddContact adds a contact via the core and updates local DB.
func (e *Engine) AddContact(accountID, phone, firstName, lastName string) error {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return fmt.Errorf("account not connected: %s", accountID)
	}
	return acc.Core.AddContact(phone, firstName, lastName)
}

func (e *Engine) DeleteContact(accountID, userID string) error {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return fmt.Errorf("account not connected: %s", accountID)
	}
	if err := acc.Core.DeleteContact(userID); err != nil {
		return err
	}
	e.db.Exec("UPDATE users SET is_contact = 0 WHERE account_id = ? AND user_id = ?", accountID, userID)
	e.emitChatUpdate(accountID, userID)
	return nil
}

// GetPeerColors fetches the extended peer color palette (help.peerColors) from the core.
// Returns up to 64 color entries. Only works for Telegram accounts.
func (e *Engine) GetPeerColors(accountID string) ([]cores.PeerColorEntry, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return nil, fmt.Errorf("account not connected: %s", accountID)
	}
	type peerColorFetcher interface {
		GetPeerColorPalette() ([]cores.PeerColorEntry, error)
	}
	fetcher, ok := acc.Core.(peerColorFetcher)
	if !ok {
		return nil, nil // not a Telegram account, no peer colors
	}
	return fetcher.GetPeerColorPalette()
}

type selfColorChannelGetter interface {
	GetSelfColorAndChannel() (colorID int, personalChannelName string, err error)
}

func (e *Engine) GetSelfColorAndChannel(accountID string) (int, string, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return -1, "", fmt.Errorf("account %q not connected", accountID)
	}
	g, ok := acc.Core.(selfColorChannelGetter)
	if !ok {
		return -1, "", fmt.Errorf("platform does not support color/channel info")
	}
	return g.GetSelfColorAndChannel()
}

type nameColorUpdater interface {
	UpdateNameColor(colorID int) error
}

func (e *Engine) UpdateNameColor(accountID string, colorID int) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not connected", accountID)
	}
	u, ok := acc.Core.(nameColorUpdater)
	if !ok {
		return fmt.Errorf("platform does not support name color update")
	}
	return u.UpdateNameColor(colorID)
}

type contentSettingsGetter interface {
	GetContentSettings() (sensitiveEnabled bool, sensitiveCanChange bool, err error)
}

type contentSettingsSetter interface {
	SetContentSettings(sensitiveEnabled bool) error
}

func (e *Engine) GetContentSettings(accountID string) (bool, bool, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return false, false, fmt.Errorf("account %q not connected", accountID)
	}
	g, ok := acc.Core.(contentSettingsGetter)
	if !ok {
		return false, false, fmt.Errorf("platform does not support content settings")
	}
	return g.GetContentSettings()
}

func (e *Engine) SetContentSettings(accountID string, sensitiveEnabled bool) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not connected", accountID)
	}
	s, ok := acc.Core.(contentSettingsSetter)
	if !ok {
		return fmt.Errorf("platform does not support content settings")
	}
	return s.SetContentSettings(sensitiveEnabled)
}

type archiveSettingsGetter interface {
	GetArchiveSettings() (archiveAndMute bool, keepArchivedUnmuted bool, keepArchivedFolders bool, err error)
}

type archiveSettingsSetter interface {
	SetArchiveSettings(archiveAndMute, keepArchivedUnmuted, keepArchivedFolders bool) error
}

func (e *Engine) GetArchiveSettings(accountID string) (bool, bool, bool, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return false, false, false, fmt.Errorf("account %q not connected", accountID)
	}
	g, ok := acc.Core.(archiveSettingsGetter)
	if !ok {
		return false, false, false, fmt.Errorf("platform does not support archive settings")
	}
	return g.GetArchiveSettings()
}

func (e *Engine) SetArchiveSettings(accountID string, archiveAndMute, keepArchivedUnmuted, keepArchivedFolders bool) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not connected", accountID)
	}
	s, ok := acc.Core.(archiveSettingsSetter)
	if !ok {
		return fmt.Errorf("platform does not support archive settings")
	}
	return s.SetArchiveSettings(archiveAndMute, keepArchivedUnmuted, keepArchivedFolders)
}

type hideReadMarksGetter interface {
	GetHideReadMarks() (bool, error)
}

type hideReadMarksSetter interface {
	SetHideReadMarks(hide bool) error
}

func (e *Engine) GetHideReadMarks(accountID string) (bool, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return false, fmt.Errorf("account %q not connected", accountID)
	}
	g, ok := acc.Core.(hideReadMarksGetter)
	if !ok {
		return false, fmt.Errorf("platform does not support hide read marks")
	}
	return g.GetHideReadMarks()
}

func (e *Engine) SetHideReadMarks(accountID string, hide bool) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not connected", accountID)
	}
	s, ok := acc.Core.(hideReadMarksSetter)
	if !ok {
		return fmt.Errorf("platform does not support hide read marks")
	}
	return s.SetHideReadMarks(hide)
}

type messagesPrivacyGetter interface {
	GetMessagesPrivacy() (option string, chargeStars int64, err error)
}

type messagesPrivacySetter interface {
	SetMessagesPrivacy(option string, chargeStars int64) error
}

type paidMessagesConfigGetter interface {
	GetPaidMessagesConfig() (maxStars int64, commissionPermille int32, withdrawRate float64, err error)
}

func (e *Engine) GetMessagesPrivacy(accountID string) (string, int64, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return "", 0, fmt.Errorf("account %q not connected", accountID)
	}
	g, ok := acc.Core.(messagesPrivacyGetter)
	if !ok {
		return "", 0, fmt.Errorf("platform does not support messages privacy")
	}
	return g.GetMessagesPrivacy()
}

func (e *Engine) SetMessagesPrivacy(accountID, option string, chargeStars int64) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not connected", accountID)
	}
	s, ok := acc.Core.(messagesPrivacySetter)
	if !ok {
		return fmt.Errorf("platform does not support messages privacy")
	}
	return s.SetMessagesPrivacy(option, chargeStars)
}

func (e *Engine) GetPaidMessagesConfig(accountID string) (int64, int32, float64, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return 0, 0, 0, fmt.Errorf("account %q not connected", accountID)
	}
	g, ok := acc.Core.(paidMessagesConfigGetter)
	if !ok {
		return 10000, 150, 0.013, nil
	}
	return g.GetPaidMessagesConfig()
}

type cloudThemesFetcher interface {
	GetCloudThemes() ([]cores.CloudThemeInfo, error)
}

func (e *Engine) GetCloudThemes(accountID string) ([]cores.CloudThemeInfo, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return nil, fmt.Errorf("account not connected: %s", accountID)
	}
	f, ok := acc.Core.(cloudThemesFetcher)
	if !ok {
		return nil, nil
	}
	return f.GetCloudThemes()
}

func (e *Engine) GetWebPagePreview(accountID, url string) (*cores.WebPagePreviewResult, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return nil, fmt.Errorf("account not connected: %s", accountID)
	}
	type webPageFetcher interface {
		GetWebPagePreviewFull(url string) (*cores.WebPagePreviewResult, error)
	}
	fetcher, ok := acc.Core.(webPageFetcher)
	if !ok {
		return nil, nil
	}
	return fetcher.GetWebPagePreviewFull(url)
}

// SendAsPeerInfo describes a peer the user can send messages as.
type SendAsPeerInfo struct {
	PeerID      string `json:"peer_id"`
	DisplayName string `json:"display_name"`
	AvatarPath  string `json:"avatar_path,omitempty"`
	IsChannel   bool   `json:"is_channel"`
}

// GetSendAs returns the list of peers the user can send as in a given chat.
func (e *Engine) GetSendAs(accountID, chatID string) ([]SendAsPeerInfo, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return nil, fmt.Errorf("account not connected: %s", accountID)
	}
	type sendAsFetcher interface {
		GetSendAs(chatID string) ([]string, error)
	}
	fetcher, ok := acc.Core.(sendAsFetcher)
	if !ok {
		return nil, nil
	}
	ids, err := fetcher.GetSendAs(chatID)
	if err != nil {
		return nil, err
	}
	var result []SendAsPeerInfo
	for _, id := range ids {
		info := SendAsPeerInfo{PeerID: id}
		if u, err := e.GetUser(accountID, id); err == nil && u != nil {
			info.DisplayName = u.DisplayName
			info.AvatarPath = u.AvatarPath
		} else {
			var title, avatarPath sql.NullString
			e.db.QueryRow(
				"SELECT title, avatar_path FROM chats WHERE account_id = ? AND chat_id = ?",
				accountID, id).Scan(&title, &avatarPath)
			info.DisplayName = title.String
			info.AvatarPath = avatarPath.String
			info.IsChannel = true
		}
		result = append(result, info)
	}
	return result, nil
}

// SaveDefaultSendAs sets the default send-as peer for a channel.
func (e *Engine) SaveDefaultSendAs(accountID, chatID, peerID string) error {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return fmt.Errorf("account not connected: %s", accountID)
	}
	type sendAsSaver interface {
		SaveDefaultSendAs(chatID, peerID string) error
	}
	saver, ok := acc.Core.(sendAsSaver)
	if !ok {
		return fmt.Errorf("platform does not support send-as")
	}
	return saver.SaveDefaultSendAs(chatID, peerID)
}

type cloudPasswordStateProvider interface {
	GetCloudPasswordState() (cores.CloudPasswordState, error)
}

type cloudPasswordChecker interface {
	CheckCloudPassword(password string) error
}

type cloudPasswordSetter interface {
	SetCloudPassword(currentPassword, newPassword, hint, email string) error
}

type cloudPasswordRemover interface {
	RemoveCloudPassword(password string) error
}

func (e *Engine) GetCloudPasswordState(accountID string) (cores.CloudPasswordState, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return cores.CloudPasswordState{}, fmt.Errorf("account not found")
	}
	p, ok := acc.Core.(cloudPasswordStateProvider)
	if !ok {
		return cores.CloudPasswordState{}, fmt.Errorf("platform does not support cloud password")
	}
	return p.GetCloudPasswordState()
}

func (e *Engine) CheckCloudPassword(accountID, password string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account not found")
	}
	p, ok := acc.Core.(cloudPasswordChecker)
	if !ok {
		return fmt.Errorf("platform does not support cloud password")
	}
	return p.CheckCloudPassword(password)
}

func (e *Engine) SetCloudPassword(accountID, currentPassword, newPassword, hint, email string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account not found")
	}
	p, ok := acc.Core.(cloudPasswordSetter)
	if !ok {
		return fmt.Errorf("platform does not support cloud password")
	}
	return p.SetCloudPassword(currentPassword, newPassword, hint, email)
}

func (e *Engine) RemoveCloudPassword(accountID, password string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account not found")
	}
	p, ok := acc.Core.(cloudPasswordRemover)
	if !ok {
		return fmt.Errorf("platform does not support cloud password")
	}
	return p.RemoveCloudPassword(password)
}

type passkeyListProvider interface {
	GetPasskeyList() ([]cores.PasskeyInfo, error)
}

func (e *Engine) GetPasskeyList(accountID string) ([]cores.PasskeyInfo, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account not found")
	}
	p, ok := acc.Core.(passkeyListProvider)
	if !ok {
		return nil, fmt.Errorf("platform does not support passkeys")
	}
	return p.GetPasskeyList()
}

func (e *Engine) GetBlockedUsers(accountID string) ([]cores.User, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account not found")
	}
	return acc.Core.GetBlockedUsers()
}

func (e *Engine) GetSessions(accountID string) ([]cores.Session, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account not found")
	}
	return acc.Core.GetSessions()
}
