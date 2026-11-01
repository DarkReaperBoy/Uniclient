package engine

import (
	"fmt"
	"log"
	"os"
	"path/filepath"
	"sync"
)

type avatarDownloader interface {
	DownloadChatAvatar(chatID, destPath string) error
}

type avatarState struct {
	mu      sync.Mutex
	pending map[string]map[string]bool
}

func newAvatarState() *avatarState {
	return &avatarState{
		pending: make(map[string]map[string]bool),
	}
}

func (e *Engine) markAvatarAvailable(accountID, chatID string) {
	e.avatars.mu.Lock()
	defer e.avatars.mu.Unlock()

	if e.avatars.pending[accountID] == nil {
		e.avatars.pending[accountID] = make(map[string]bool)
	}
	e.avatars.pending[accountID][chatID] = true
}

func (e *Engine) DownloadPendingAvatars(accountID string) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return
	}

	dl, ok := acc.Core.(avatarDownloader)
	if !ok {
		return
	}

	e.avatars.mu.Lock()
	chatIDs := make([]string, 0, len(e.avatars.pending[accountID]))
	for chatID := range e.avatars.pending[accountID] {
		chatIDs = append(chatIDs, chatID)
	}
	delete(e.avatars.pending, accountID)
	e.avatars.mu.Unlock()

	if len(chatIDs) == 0 {
		return
	}

	avatarDir := filepath.Join(e.mediaDir, safePathSegment(accountID), "avatars")
	os.MkdirAll(avatarDir, 0o755)

	var toDownload []string
	for _, chatID := range chatIDs {
		destPath := filepath.Join(avatarDir, chatID+".jpg")
		if _, err := os.Stat(destPath); err != nil {
			toDownload = append(toDownload, chatID)
		} else {
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
	avatarDir := filepath.Join(e.mediaDir, safePathSegment(accountID), "avatars")
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

func (e *Engine) GetUserAvatarThumb(accountID, userID string) (string, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return "", fmt.Errorf("account not found or not connected: %s", accountID)
	}
	thumber, ok := acc.Core.(interface {
		GetUserAvatarThumb(userID string) (string, error)
	})
	if !ok {
		return "", fmt.Errorf("platform does not support avatar thumbnails")
	}
	return thumber.GetUserAvatarThumb(userID)
}

func (e *Engine) updateAvatarPath(accountID, chatID, localPath string) {
	_, err := e.db.Exec(
		`UPDATE chats SET avatar_path = ? WHERE account_id = ? AND chat_id = ?`,
		localPath, accountID, chatID)
	if err != nil {
		return
	}
	e.emitChatUpdate(accountID, chatID)
}
