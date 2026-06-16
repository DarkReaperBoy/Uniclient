package engine

import (
	"fmt"
	"log"
	"os"
	"path/filepath"
	"sync"
)

// avatarDownloader is implemented by cores that support downloading chat/user profile photos.
type avatarDownloader interface {
	DownloadChatAvatar(chatID, destPath string) error
}

// avatarState tracks which chats have photos available but not yet downloaded.
type avatarState struct {
	mu       sync.Mutex
	pending  map[string]map[string]bool // accountID → set of chatIDs needing download
}

func newAvatarState() *avatarState {
	return &avatarState{
		pending: make(map[string]map[string]bool),
	}
}

// markAvatarAvailable records that a chat has a photo that may need downloading.
func (e *Engine) markAvatarAvailable(accountID, chatID string) {
	e.avatars.mu.Lock()
	defer e.avatars.mu.Unlock()

	if e.avatars.pending[accountID] == nil {
		e.avatars.pending[accountID] = make(map[string]bool)
	}
	e.avatars.pending[accountID][chatID] = true
}

// DownloadPendingAvatars downloads profile photos for chats that have photos
// available but no local file yet. Called after SyncChats completes.
func (e *Engine) DownloadPendingAvatars(accountID string) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return
	}

	dl, ok := acc.Core.(avatarDownloader)
	if !ok {
		return
	}

	// Collect chats needing avatars.
	e.avatars.mu.Lock()
	chatIDs := make([]string, 0, len(e.avatars.pending[accountID]))
	for chatID := range e.avatars.pending[accountID] {
		chatIDs = append(chatIDs, chatID)
	}
	// Clear pending — we'll process them now.
	delete(e.avatars.pending, accountID)
	e.avatars.mu.Unlock()

	if len(chatIDs) == 0 {
		return
	}

	// Check which ones already have avatars on disk.
	avatarDir := filepath.Join(e.mediaDir, accountID, "avatars")
	os.MkdirAll(avatarDir, 0o755)

	var toDownload []string
	for _, chatID := range chatIDs {
		destPath := filepath.Join(avatarDir, chatID+".jpg")
		if _, err := os.Stat(destPath); err != nil {
			// File doesn't exist — needs download.
			toDownload = append(toDownload, chatID)
		} else {
			// File exists — just make sure DB has the path.
			e.updateAvatarPath(accountID, chatID, destPath)
		}
	}

	if len(toDownload) == 0 {
		return
	}

	log.Printf("[engine] downloading %d avatars for %s", len(toDownload), accountID)

	for _, chatID := range toDownload {
		destPath := filepath.Join(avatarDir, chatID+".jpg")
		if err := dl.DownloadChatAvatar(chatID, destPath); err != nil {
			// Non-fatal — some chats may not have downloadable photos.
			continue
		}
		e.updateAvatarPath(accountID, chatID, destPath)
	}
}

func (e *Engine) DownloadSingleAvatar(accountID, chatID string) (string, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return "", fmt.Errorf("account not found or not connected: %s", accountID)
	}
	dl, ok := acc.Core.(avatarDownloader)
	if !ok {
		return "", fmt.Errorf("platform does not support avatar download")
	}
	avatarDir := filepath.Join(e.mediaDir, accountID, "avatars")
	os.MkdirAll(avatarDir, 0o755)
	destPath := filepath.Join(avatarDir, chatID+".jpg")
	if _, err := os.Stat(destPath); err == nil {
		return destPath, nil
	}
	if err := dl.DownloadChatAvatar(chatID, destPath); err != nil {
		return "", err
	}
	return destPath, nil
}

// GetUserAvatarThumb returns a single user's small base64 avatar thumbnail, used
// for lazy per-sender avatar loading in group/channel message lists (replaces the
// bulk member-avatar fetch). Empty string when the user has no photo.
func (e *Engine) GetUserAvatarThumb(accountID, userID, chatID, msgID string) (string, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return "", fmt.Errorf("account not found or not connected: %s", accountID)
	}
	thumber, ok := acc.Core.(interface {
		GetUserAvatarThumb(userID, chatID, msgID string) (string, error)
	})
	if !ok {
		return "", fmt.Errorf("platform does not support avatar thumbnails")
	}
	return thumber.GetUserAvatarThumb(userID, chatID, msgID)
}

// updateAvatarPath sets the avatar_path for a chat and emits an update event.
func (e *Engine) updateAvatarPath(accountID, chatID, localPath string) {
	_, err := e.db.Exec(
		`UPDATE chats SET avatar_path = ? WHERE account_id = ? AND chat_id = ?`,
		localPath, accountID, chatID)
	if err != nil {
		return
	}
	e.emitChatUpdate(accountID, chatID)
}
