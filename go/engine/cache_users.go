package engine

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
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
	BotMenuText         string `json:"bot_menu_text,omitempty"`
	LastSeen            int64  `json:"last_seen,omitempty"`
	LastSeenKind        string `json:"last_seen_kind,omitempty"`
	HasPersonalPhoto    bool   `json:"has_personal_photo,omitempty"`
	BirthdayDay         int    `json:"birthday_day,omitempty"`
	BirthdayMonth       int    `json:"birthday_month,omitempty"`
	BirthdayYear        int    `json:"birthday_year,omitempty"`
	PersonalChannelID      string `json:"personal_channel_id,omitempty"`
	PersonalChannelName    string `json:"personal_channel_name,omitempty"`
	VoiceMessagesForbidden bool   `json:"voice_messages_forbidden,omitempty"`
	ContactRequirePremium  bool   `json:"contact_require_premium,omitempty"`
	NoForwardsMy           bool   `json:"no_forwards_my,omitempty"`
	NoForwardsPeer         bool   `json:"no_forwards_peer,omitempty"`
}

// UpsertUser inserts or updates a user profile in the cache.
func (e *Engine) UpsertUser(accountID string, u cores.User) error {
	now := time.Now().UnixMilli()
	var lastSeen sql.NullInt64
	if u.LastSeen != nil {
		lastSeen = sql.NullInt64{Int64: u.LastSeen.UnixMilli(), Valid: true}
	}

	_, err := e.db.Exec(
		`INSERT INTO users (account_id, user_id, display_name, username, phone, bio, is_bot, is_online, is_contact, is_blocked, bot_menu_text, last_seen, last_seen_kind, has_personal_photo, birthday_day, birthday_month, birthday_year, personal_channel_id, personal_channel_name, voice_messages_forbidden, contact_require_premium, updated_at)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
		 ON CONFLICT(account_id, user_id) DO UPDATE SET
		     display_name = excluded.display_name,
		     username = excluded.username,
		     phone = COALESCE(NULLIF(excluded.phone, ''), users.phone),
		     bio = COALESCE(NULLIF(excluded.bio, ''), users.bio),
		     is_bot = excluded.is_bot,
		     is_online = excluded.is_online,
		     is_contact = excluded.is_contact,
		     is_blocked = excluded.is_blocked,
		     bot_menu_text = COALESCE(NULLIF(excluded.bot_menu_text, ''), users.bot_menu_text),
		     last_seen = COALESCE(excluded.last_seen, users.last_seen),
		     last_seen_kind = COALESCE(NULLIF(excluded.last_seen_kind, ''), users.last_seen_kind),
		     has_personal_photo = excluded.has_personal_photo,
		     birthday_day = CASE WHEN excluded.birthday_day > 0 THEN excluded.birthday_day ELSE users.birthday_day END,
		     birthday_month = CASE WHEN excluded.birthday_month > 0 THEN excluded.birthday_month ELSE users.birthday_month END,
		     birthday_year = CASE WHEN excluded.birthday_year > 0 THEN excluded.birthday_year ELSE users.birthday_year END,
		     personal_channel_id = COALESCE(NULLIF(excluded.personal_channel_id, ''), users.personal_channel_id),
		     personal_channel_name = COALESCE(NULLIF(excluded.personal_channel_name, ''), users.personal_channel_name),
		     voice_messages_forbidden = excluded.voice_messages_forbidden,
		     contact_require_premium = excluded.contact_require_premium,
		     updated_at = excluded.updated_at`,
		accountID, u.ID, u.DisplayName, u.Username, u.Phone, u.Bio,
		boolToInt(u.IsBot), boolToInt(u.IsOnline), boolToInt(u.IsContact), boolToInt(u.IsBlocked), u.BotMenuText, lastSeen,
		u.LastSeenKind, boolToInt(u.HasPersonalPhoto),
		u.BirthdayDay, u.BirthdayMonth, u.BirthdayYear, u.PersonalChannelID, u.PersonalChannelName,
		boolToInt(u.VoiceMessagesForbidden), boolToInt(u.ContactRequirePremium), now)
	return err
}

// GetUser retrieves a cached user profile.
func (e *Engine) GetUser(accountID, userID string) (*CachedUser, error) {
	var u CachedUser
	var displayName, username, phone, bio, avatarPath, botMenuText sql.NullString
	var personalChannelID, personalChannelName sql.NullString
	var lastSeenKind sql.NullString
	var lastSeen sql.NullInt64
	var isBot, isOnline, isContact, isBlocked int
	var voiceForbidden, contactPremium, noForwardsMy, noForwardsPeer, hasPersonalPhoto int

	err := e.db.QueryRow(
		`SELECT account_id, user_id, display_name, username, phone, bio, avatar_path,
		        is_bot, is_online, is_contact, is_blocked, bot_menu_text, last_seen,
		        last_seen_kind, has_personal_photo,
		        birthday_day, birthday_month, birthday_year,
		        personal_channel_id, personal_channel_name,
		        voice_messages_forbidden, contact_require_premium,
		        no_forwards_my, no_forwards_peer
		 FROM users WHERE account_id = ? AND user_id = ?`,
		accountID, userID).Scan(
		&u.AccountID, &u.UserID, &displayName, &username, &phone, &bio, &avatarPath,
		&isBot, &isOnline, &isContact, &isBlocked, &botMenuText, &lastSeen,
		&lastSeenKind, &hasPersonalPhoto,
		&u.BirthdayDay, &u.BirthdayMonth, &u.BirthdayYear,
		&personalChannelID, &personalChannelName,
		&voiceForbidden, &contactPremium,
		&noForwardsMy, &noForwardsPeer)
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
	u.BotMenuText = botMenuText.String
	u.LastSeenKind = lastSeenKind.String
	u.HasPersonalPhoto = hasPersonalPhoto == 1
	u.PersonalChannelID = personalChannelID.String
	u.PersonalChannelName = personalChannelName.String
	u.VoiceMessagesForbidden = voiceForbidden == 1
	u.ContactRequirePremium = contactPremium == 1
	u.NoForwardsMy = noForwardsMy == 1
	u.NoForwardsPeer = noForwardsPeer == 1
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
	UserID       string `json:"user_id"`
	Username     string `json:"username,omitempty"`
	DisplayName  string `json:"display_name,omitempty"`
	AvatarB64    string `json:"avatar_b64,omitempty"`
	IsBot        bool   `json:"is_bot"`
	IsOnline     bool   `json:"is_online"`
	Role         string `json:"role"` // "owner", "admin", "member", "restricted", "banned"
	CustomRank   string `json:"custom_rank,omitempty"`
	PromotedBy   string `json:"promoted_by,omitempty"`
	PromotedByID string `json:"promoted_by_id,omitempty"`
	PromotedDate int64  `json:"promoted_date,omitempty"`
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

type ParticipantsByRoleResult struct {
	Members []MemberInfo `json:"members"`
	Total   int          `json:"total"`
}

func (e *Engine) GetChatMembersByRole(accountID, chatID, role, query string, limit, offset int) (*ParticipantsByRoleResult, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return nil, fmt.Errorf("account not connected: %s", accountID)
	}
	if limit <= 0 {
		limit = 200
	}

	type roleProvider interface {
		GetParticipantsByRole(chatID, role, query string, limit, offset int) ([]cores.User, map[int64]cores.ParticipantExtra, error)
	}
	rp, ok := acc.Core.(roleProvider)
	if !ok {
		members, err := e.GetChatMembers(accountID, chatID, limit, offset)
		if err != nil {
			return nil, err
		}
		return &ParticipantsByRoleResult{Members: members, Total: len(members)}, nil
	}

	users, extras, err := rp.GetParticipantsByRole(chatID, role, query, limit, offset)
	if err != nil {
		return nil, err
	}

	members := make([]MemberInfo, 0, len(users))
	for _, u := range users {
		e.UpsertUser(accountID, u)
		r := u.Role
		if r == "" {
			r = "member"
		}
		mi := MemberInfo{
			UserID:      u.ID,
			Username:    u.Username,
			DisplayName: u.DisplayName,
			AvatarB64:   u.AvatarB64,
			IsBot:       u.IsBot,
			IsOnline:    u.IsOnline,
			Role:        r,
		}
		uid, _ := strconv.ParseInt(u.ID, 10, 64)
		if ex, ok := extras[uid]; ok {
			mi.CustomRank = ex.CustomRank
			if ex.PromotedBy != 0 {
				mi.PromotedByID = strconv.FormatInt(ex.PromotedBy, 10)
				if cached, err := e.GetUser(accountID, mi.PromotedByID); err == nil && cached != nil {
					mi.PromotedBy = cached.DisplayName
				}
			}
			if ex.PromotedDate != 0 {
				mi.PromotedDate = int64(ex.PromotedDate)
			}
		}
		members = append(members, mi)
	}
	return &ParticipantsByRoleResult{Members: members, Total: len(members)}, nil
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
	AvatarB64   string `json:"avatar_b64,omitempty"`
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
			AvatarB64:   e.AvatarB64,
		})
	}
	return result, nil
}

// ContactInfo is the contact data returned to the UI for the contacts list.
type ContactInfo struct {
	UserID         string `json:"user_id"`
	Username       string `json:"username,omitempty"`
	DisplayName    string `json:"display_name,omitempty"`
	Phone          string `json:"phone,omitempty"`
	AvatarB64      string `json:"avatar_b64,omitempty"`
	IsBot          bool   `json:"is_bot"`
	IsOnline       bool   `json:"is_online"`
	StoryCount     int32  `json:"story_count,omitempty"`
	HasUnreadStory bool   `json:"has_unread_story,omitempty"`
	IsVerified     bool   `json:"is_verified,omitempty"`
	IsPremium      bool   `json:"is_premium,omitempty"`
	IsScam         bool   `json:"is_scam,omitempty"`
	IsFake         bool   `json:"is_fake,omitempty"`
	LastSeenKind   string `json:"last_seen_kind,omitempty"`
	LastSeenTs     int64  `json:"last_seen_ts,omitempty"`
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
		var lastSeenTs int64
		if u.LastSeen != nil {
			lastSeenTs = u.LastSeen.Unix()
		}
		contacts = append(contacts, ContactInfo{
			UserID:         u.ID,
			Username:       u.Username,
			DisplayName:    u.DisplayName,
			Phone:          u.Phone,
			AvatarB64:      u.AvatarB64,
			IsBot:          u.IsBot,
			IsOnline:       u.IsOnline,
			StoryCount:     int32(u.StoryCount),
			HasUnreadStory: u.HasUnreadStory,
			IsVerified:     u.IsVerified,
			IsPremium:      u.IsPremium,
			IsScam:         u.IsScam,
			IsFake:         u.IsFake,
			LastSeenKind:   u.LastSeenKind,
			LastSeenTs:     lastSeenTs,
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

// SetUserNoForwardsFlags sets the AyuNoForwards flags for a user (local preference).
func (e *Engine) SetUserNoForwardsFlags(accountID, userID string, myEnabled, peerEnabled bool) error {
	_, err := e.db.Exec(
		`UPDATE users SET no_forwards_my = ?, no_forwards_peer = ? WHERE account_id = ? AND user_id = ?`,
		boolToInt(myEnabled), boolToInt(peerEnabled), accountID, userID)
	return err
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

func (e *Engine) TransferChannelOwnership(accountID, chatID, userID, password string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}
	type transferable interface {
		TransferChannelOwnership(chatID, userID, password string) error
	}
	if t, ok := acc.Core.(transferable); ok {
		return t.TransferChannelOwnership(chatID, userID, password)
	}
	return fmt.Errorf("platform does not support TransferChannelOwnership")
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

func (e *Engine) UnbanMember(accountID, chatID, userID string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}
	type unbannable interface {
		UnbanMember(chatID, userID string) error
	}
	if u, ok := acc.Core.(unbannable); ok {
		return u.UnbanMember(chatID, userID)
	}
	return fmt.Errorf("platform does not support UnbanMember")
}

type AdminRights struct {
	ChangeInfo     bool
	DeleteMessages bool
	BanUsers       bool
	InviteUsers    bool
	PinMessages    bool
	ManageTopics   bool
	PostMessages   bool
	EditMessages   bool
	PostStories    bool
	EditStories    bool
	DeleteStories  bool
	ManageCall     bool
	ManageRanks    bool
	Anonymous      bool
	AddAdmins      bool
	ManageDirect   bool
}

func (e *Engine) PromoteAdminWithRights(accountID, chatID, userID string, rights *AdminRights, rank string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}
	type promotableWithRights interface {
		PromoteAdminWithRights(chatID, userID string, rights map[string]bool, rank string) error
	}
	if p, ok := acc.Core.(promotableWithRights); ok {
		m := map[string]bool{
			"change_info":     rights.ChangeInfo,
			"delete_messages": rights.DeleteMessages,
			"ban_users":       rights.BanUsers,
			"invite_users":    rights.InviteUsers,
			"pin_messages":    rights.PinMessages,
			"manage_topics":   rights.ManageTopics,
			"post_messages":   rights.PostMessages,
			"edit_messages":   rights.EditMessages,
			"post_stories":    rights.PostStories,
			"edit_stories":    rights.EditStories,
			"delete_stories":  rights.DeleteStories,
			"manage_call":     rights.ManageCall,
			"manage_ranks":    rights.ManageRanks,
			"anonymous":       rights.Anonymous,
			"add_admins":      rights.AddAdmins,
			"manage_direct":   rights.ManageDirect,
		}
		return p.PromoteAdminWithRights(chatID, userID, m, rank)
	}
	return fmt.Errorf("platform does not support PromoteAdminWithRights")
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

func (e *Engine) RestrictMemberWithRights(accountID, chatID, userID string, rights *DefaultBannedRights, untilDate int) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}
	type restrictable interface {
		RestrictMemberWithRights(chatID, userID string, rights *cores.DefaultBannedRights, untilDate int) error
	}
	if r, ok := acc.Core.(restrictable); ok {
		return r.RestrictMemberWithRights(chatID, userID, &cores.DefaultBannedRights{
			SendPlain:     rights.SendPlain,
			SendPhotos:    rights.SendPhotos,
			SendVideos:    rights.SendVideos,
			SendRoundvideos: rights.SendRoundvideos,
			SendAudios:    rights.SendAudios,
			SendVoices:    rights.SendVoices,
			SendDocs:      rights.SendDocs,
			SendStickers:  rights.SendStickers,
			EmbedLinks:    rights.EmbedLinks,
			SendPolls:     rights.SendPolls,
			InviteUsers:   rights.InviteUsers,
			ManageTopics:  rights.ManageTopics,
			PinMessages:   rights.PinMessages,
			EditRank:      rights.EditRank,
			ChangeInfo:    rights.ChangeInfo,
		}, untilDate)
	}
	return fmt.Errorf("platform does not support RestrictMemberWithRights")
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
func (e *Engine) AddContact(accountID, phone, firstName, lastName, note string) error {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return fmt.Errorf("account not connected: %s", accountID)
	}
	type noteAdder interface {
		AddContactWithNote(phone, firstName, lastName, note string) error
	}
	if note != "" {
		if na, ok := acc.Core.(noteAdder); ok {
			return na.AddContactWithNote(phone, firstName, lastName, note)
		}
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

type paymentInfoClearer interface {
	ClearPaymentInfo(clearCredentials, clearShipping bool) error
}

func (e *Engine) ClearPaymentInfo(accountID string, clearCredentials, clearShipping bool) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not connected", accountID)
	}
	c, ok := acc.Core.(paymentInfoClearer)
	if !ok {
		return fmt.Errorf("platform does not support clearing payment info")
	}
	return c.ClearPaymentInfo(clearCredentials, clearShipping)
}

type paymentFormGetter interface {
	GetPaymentForm(chatID, msgID string) (map[string]interface{}, error)
}

func (e *Engine) GetPaymentForm(accountID, chatID, msgID string) (map[string]interface{}, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account %q not connected", accountID)
	}
	g, ok := acc.Core.(paymentFormGetter)
	if !ok {
		return nil, fmt.Errorf("platform does not support payment forms")
	}
	return g.GetPaymentForm(chatID, msgID)
}

type paymentFormSender interface {
	SendPaymentForm(chatID, msgID string, formData map[string]interface{}) error
}

func (e *Engine) SendPaymentForm(accountID, chatID, msgID string, formData map[string]interface{}) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not connected", accountID)
	}
	s, ok := acc.Core.(paymentFormSender)
	if !ok {
		return fmt.Errorf("platform does not support payment forms")
	}
	return s.SendPaymentForm(chatID, msgID, formData)
}

type paymentReceiptGetter interface {
	GetPaymentReceipt(chatID, msgID string) (map[string]interface{}, error)
}

func (e *Engine) GetPaymentReceipt(accountID, chatID, msgID string) (map[string]interface{}, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account %q not connected", accountID)
	}
	g, ok := acc.Core.(paymentReceiptGetter)
	if !ok {
		return nil, fmt.Errorf("platform does not support payment receipts")
	}
	return g.GetPaymentReceipt(chatID, msgID)
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

type confcallSizeLimitGetter interface {
	GetConfcallSizeLimit() (int, error)
}

func (e *Engine) GetConfcallSizeLimit(accountID string) (int, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return 200, fmt.Errorf("account %q not connected", accountID)
	}
	g, ok := acc.Core.(confcallSizeLimitGetter)
	if !ok {
		return 200, nil
	}
	return g.GetConfcallSizeLimit()
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

type wallpapersFetcher interface {
	GetWallpapers() ([]cores.WallpaperInfo, error)
}

func (e *Engine) GetWallpapers(accountID string) ([]cores.WallpaperInfo, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return nil, fmt.Errorf("account not connected: %s", accountID)
	}
	f, ok := acc.Core.(wallpapersFetcher)
	if !ok {
		return nil, nil
	}
	return f.GetWallpapers()
}

type cloudThemeDeleter interface {
	DeleteCloudTheme(themeID int64) error
}

func (e *Engine) DeleteCloudTheme(accountID string, themeID int64) error {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return fmt.Errorf("account not connected: %s", accountID)
	}
	d, ok := acc.Core.(cloudThemeDeleter)
	if !ok {
		return fmt.Errorf("core does not support cloud theme deletion")
	}
	return d.DeleteCloudTheme(themeID)
}

type chatThemesFetcher interface {
	GetChatThemesList() ([]cores.ChatThemeInfo, error)
}

func (e *Engine) GetChatThemes(accountID string) ([]cores.ChatThemeInfo, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return nil, fmt.Errorf("account not connected: %s", accountID)
	}
	f, ok := acc.Core.(chatThemesFetcher)
	if !ok {
		return nil, nil
	}
	return f.GetChatThemesList()
}

type chatThemeSetter interface {
	SetChatTheme(chatID string, emoticon string) error
}

func (e *Engine) SetChatTheme(accountID, chatID, emoticon string) error {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return fmt.Errorf("account not connected: %s", accountID)
	}
	f, ok := acc.Core.(chatThemeSetter)
	if !ok {
		return fmt.Errorf("platform does not support chat themes")
	}
	return f.SetChatTheme(chatID, emoticon)
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

func (e *Engine) GetInstantViewPage(accountID, url string) ([]byte, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return nil, fmt.Errorf("account not connected: %s", accountID)
	}
	type ivFetcher interface {
		GetInstantViewPage(url string) ([]byte, error)
	}
	fetcher, ok := acc.Core.(ivFetcher)
	if !ok {
		return nil, fmt.Errorf("instant view not supported for this account type")
	}
	return fetcher.GetInstantViewPage(url)
}

func (e *Engine) DownloadIVPhoto(accountID string, photoID int64, extra string) ([]byte, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return nil, fmt.Errorf("account not connected: %s", accountID)
	}
	type ivPhotoDownloader interface {
		DownloadIVPhoto(photoID int64, extra string) (string, error)
	}
	dl, ok := acc.Core.(ivPhotoDownloader)
	if !ok {
		return nil, fmt.Errorf("IV photo download not supported for this account type")
	}
	path, err := dl.DownloadIVPhoto(photoID, extra)
	if err != nil { return nil, err }
	return json.Marshal(map[string]string{"path": path})
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

type cloudPasswordEmailConfirmer interface {
	AccountConfirmPasswordEmail(code string) (bool, error)
}

type cloudPasswordEmailResender interface {
	AccountResendPasswordEmail() (bool, error)
}

type cloudPasswordEmailCanceller interface {
	AccountCancelPasswordEmail() (bool, error)
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

func (e *Engine) ConfirmPasswordEmail(accountID, code string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account not found")
	}
	p, ok := acc.Core.(cloudPasswordEmailConfirmer)
	if !ok {
		return fmt.Errorf("platform does not support email confirmation")
	}
	_, err := p.AccountConfirmPasswordEmail(code)
	return err
}

func (e *Engine) ResendPasswordEmail(accountID string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account not found")
	}
	p, ok := acc.Core.(cloudPasswordEmailResender)
	if !ok {
		return fmt.Errorf("platform does not support email resend")
	}
	_, err := p.AccountResendPasswordEmail()
	return err
}

func (e *Engine) CancelPasswordEmail(accountID string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account not found")
	}
	p, ok := acc.Core.(cloudPasswordEmailCanceller)
	if !ok {
		return fmt.Errorf("platform does not support email cancellation")
	}
	_, err := p.AccountCancelPasswordEmail()
	return err
}

type passwordRecoveryRequester interface {
	RequestPasswordRecovery() (string, error)
}

type passwordResetter interface {
	ResetPassword() (cores.PasswordResetResult, error)
}

type passwordResetCanceller interface {
	CancelResetPassword() error
}

func (e *Engine) RequestPasswordRecovery(accountID string) (string, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return "", fmt.Errorf("account not found")
	}
	p, ok := acc.Core.(passwordRecoveryRequester)
	if !ok {
		return "", fmt.Errorf("platform does not support password recovery")
	}
	return p.RequestPasswordRecovery()
}

func (e *Engine) ResetPassword(accountID string) (cores.PasswordResetResult, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return cores.PasswordResetResult{}, fmt.Errorf("account not found")
	}
	p, ok := acc.Core.(passwordResetter)
	if !ok {
		return cores.PasswordResetResult{}, fmt.Errorf("platform does not support password reset")
	}
	return p.ResetPassword()
}

func (e *Engine) CancelResetPassword(accountID string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account not found")
	}
	p, ok := acc.Core.(passwordResetCanceller)
	if !ok {
		return fmt.Errorf("platform does not support cancel reset")
	}
	return p.CancelResetPassword()
}

type cloudPasswordEmailSetter interface {
	SetCloudPasswordEmail(currentPassword, email string) error
}

type recoveryPasswordChecker interface {
	CheckRecoveryPassword(code string) error
}

type recoveryPasswordWithCode interface {
	RecoverPasswordWithCode(code, newPassword, hint string) error
}

func (e *Engine) SetCloudPasswordEmail(accountID, currentPassword, email string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account not found")
	}
	p, ok := acc.Core.(cloudPasswordEmailSetter)
	if !ok {
		return fmt.Errorf("platform does not support email-only password update")
	}
	return p.SetCloudPasswordEmail(currentPassword, email)
}

func (e *Engine) CheckRecoveryPassword(accountID, code string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account not found")
	}
	p, ok := acc.Core.(recoveryPasswordChecker)
	if !ok {
		return fmt.Errorf("platform does not support recovery password check")
	}
	return p.CheckRecoveryPassword(code)
}

func (e *Engine) RecoverPasswordWithCode(accountID, code, newPassword, hint string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account not found")
	}
	p, ok := acc.Core.(recoveryPasswordWithCode)
	if !ok {
		return fmt.Errorf("platform does not support password recovery with code")
	}
	return p.RecoverPasswordWithCode(code, newPassword, hint)
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

type blockedUsersPager interface {
	GetBlockedUsersPaged(offset, limit int) ([]cores.User, int, error)
}

func (e *Engine) GetBlockedUsersPaged(accountID string, offset, limit int) ([]cores.User, int, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, 0, fmt.Errorf("account not found")
	}
	if pager, ok := acc.Core.(blockedUsersPager); ok {
		return pager.GetBlockedUsersPaged(offset, limit)
	}
	all, err := acc.Core.GetBlockedUsers()
	if err != nil {
		return nil, 0, err
	}
	total := len(all)
	if offset >= total {
		return nil, total, nil
	}
	end := offset + limit
	if end > total {
		end = total
	}
	return all[offset:end], total, nil
}

func (e *Engine) GetSessions(accountID string) ([]cores.Session, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account not found")
	}
	return acc.Core.GetSessions()
}

func (e *Engine) TerminateSession(accountID, sessionID string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account not found")
	}
	return acc.Core.TerminateSession(sessionID)
}

func (e *Engine) TerminateAllOtherSessions(accountID string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account not found")
	}
	sessions, err := acc.Core.GetSessions()
	if err != nil {
		return err
	}
	for _, s := range sessions {
		if !s.IsCurrent {
			if err := acc.Core.TerminateSession(s.ID); err != nil {
				return err
			}
		}
	}
	return nil
}

type sessionAutoTerminateGetter interface {
	GetSessionAutoTerminateDays() (int, error)
}

type sessionAutoTerminateSetter interface {
	SetSessionAutoTerminateDays(days int) error
}

func (e *Engine) GetSessionAutoTerminateDays(accountID string) (int, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return 0, fmt.Errorf("account not found")
	}
	g, ok := acc.Core.(sessionAutoTerminateGetter)
	if !ok {
		return 0, fmt.Errorf("not supported")
	}
	return g.GetSessionAutoTerminateDays()
}

func (e *Engine) SetSessionAutoTerminateDays(accountID string, days int) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account not found")
	}
	s, ok := acc.Core.(sessionAutoTerminateSetter)
	if !ok {
		return fmt.Errorf("not supported")
	}
	return s.SetSessionAutoTerminateDays(days)
}

type LanguageInfo struct {
	LangCode   string `json:"lang_code"`
	Name       string `json:"name"`
	NativeName string `json:"native_name"`
	Official   bool   `json:"official"`
	Rtl        bool   `json:"rtl"`
	Beta       bool   `json:"beta"`
}

func (e *Engine) GetLanguages(accountID string) ([]LanguageInfo, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account not found")
	}
	if tc, ok := acc.Core.(*cores.TelegramCore); ok {
		langs, err := tc.LangpackGetLanguages("tdesktop")
		if err != nil {
			return nil, err
		}
		result := make([]LanguageInfo, 0, len(langs))
		for _, l := range langs {
			result = append(result, LanguageInfo{
				LangCode:   l.LangCode,
				Name:       l.Name,
				NativeName: l.NativeName,
				Official:   l.Official,
				Rtl:        l.Rtl,
				Beta:       l.Beta,
			})
		}
		return result, nil
	}
	return nil, fmt.Errorf("not supported")
}

func (e *Engine) SaveLanguagePrefs(accountID string, data json.RawMessage) error {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return fmt.Errorf("account %q not found", accountID)
	}
	dir := filepath.Join(e.configDir, "accounts", acc.ID)
	os.MkdirAll(dir, 0o755)
	return os.WriteFile(filepath.Join(dir, "language_prefs.json"), data, 0o644)
}

func (e *Engine) LoadLanguagePrefs(accountID string) (json.RawMessage, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return nil, fmt.Errorf("account %q not found", accountID)
	}
	path := filepath.Join(e.configDir, "accounts", acc.ID, "language_prefs.json")
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return json.RawMessage("{}"), nil
		}
		return nil, err
	}
	return json.RawMessage(data), nil
}

type connectedBotsGetter interface {
	GetConnectedBots() ([]map[string]interface{}, error)
}

func (e *Engine) GetConnectedBots(accountID string) ([]map[string]interface{}, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account %q not connected", accountID)
	}
	g, ok := acc.Core.(connectedBotsGetter)
	if !ok {
		return nil, fmt.Errorf("platform does not support connected bots")
	}
	return g.GetConnectedBots()
}

type connectedBotPauser interface {
	ToggleConnectedBotPaused(chatID string, paused bool) error
}

func (e *Engine) ToggleConnectedBotPaused(accountID, chatID string, paused bool) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not connected", accountID)
	}
	p, ok := acc.Core.(connectedBotPauser)
	if !ok {
		return fmt.Errorf("platform does not support connected bot pausing")
	}
	return p.ToggleConnectedBotPaused(chatID, paused)
}

type connectedBotDisabler interface {
	DisablePeerConnectedBot(chatID string) error
}

type publicLinksLimitsGetter interface {
	GetPublicLinksLimits() (int, int, error)
}

func (e *Engine) GetPublicLinksLimits(accountID string) (int, int, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return 10, 20, fmt.Errorf("account %q not connected", accountID)
	}
	g, ok := acc.Core.(publicLinksLimitsGetter)
	if !ok {
		return 10, 20, nil
	}
	return g.GetPublicLinksLimits()
}

type forumTopicIconsFetcher interface {
	GetForumTopicDefaultIcons() ([]cores.ForumTopicIconInfo, error)
}

func (e *Engine) GetForumTopicDefaultIcons(accountID string) ([]cores.ForumTopicIconInfo, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account %q not connected", accountID)
	}
	f, ok := acc.Core.(forumTopicIconsFetcher)
	if !ok {
		return nil, fmt.Errorf("platform does not support forum topic icons")
	}
	return f.GetForumTopicDefaultIcons()
}

type channelUsernamesGetter interface {
	GetChannelUsernames(chatID string) ([]cores.ChannelUsernameInfo, error)
}

func (e *Engine) GetChannelUsernames(accountID, chatID string) ([]cores.ChannelUsernameInfo, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account %q not connected", accountID)
	}
	g, ok := acc.Core.(channelUsernamesGetter)
	if !ok {
		return nil, fmt.Errorf("platform does not support channel usernames")
	}
	return g.GetChannelUsernames(chatID)
}

type channelUsernameToggler interface {
	ToggleChannelUsername(chatID, username string, active bool) (bool, error)
}

func (e *Engine) ToggleChannelUsername(accountID, chatID, username string, active bool) (bool, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return false, fmt.Errorf("account %q not connected", accountID)
	}
	t, ok := acc.Core.(channelUsernameToggler)
	if !ok {
		return false, fmt.Errorf("platform does not support toggling usernames")
	}
	return t.ToggleChannelUsername(chatID, username, active)
}

type channelUsernamesReorderer interface {
	ReorderChannelUsernames(chatID string, order []string) (bool, error)
}

func (e *Engine) ReorderChannelUsernames(accountID, chatID string, order []string) (bool, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return false, fmt.Errorf("account %q not connected", accountID)
	}
	r, ok := acc.Core.(channelUsernamesReorderer)
	if !ok {
		return false, fmt.Errorf("platform does not support reordering usernames")
	}
	return r.ReorderChannelUsernames(chatID, order)
}

func (e *Engine) DisablePeerConnectedBot(accountID, chatID string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not connected", accountID)
	}
	d, ok := acc.Core.(connectedBotDisabler)
	if !ok {
		return fmt.Errorf("platform does not support disabling connected bots")
	}
	return d.DisablePeerConnectedBot(chatID)
}
