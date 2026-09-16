package engine

// wallpaper.go — slice 218: per-chat custom wallpaper passthroughs. The
// upload (account.uploadWallPaper for_chat) and the set
// (messages.setChatWallPaper incl. for_both / revert) ride the core; the
// engine applies the wallpaper to the chat cache directly after a
// successful own set (the receiving side learns it from the
// messageActionSetChatWallPaper service row through the mirror in
// cache_chats.go). Document bytes download through the pre-existing
// DownloadWallpaperDocument.

import (
	"encoding/json"
	"fmt"

	"uniclient/cores"
)

// ChatWallpaperUploader uploads a custom wallpaper image for the
// per-chat flow (account.uploadWallPaper with for_chat).
type ChatWallpaperUploader interface {
	UploadChatWallpaper(data []byte, mime string, blurred bool) (cores.WallpaperInfo, error)
}

// ChatWallpaperSetter sets / reverts a chat wallpaper
// (messages.setChatWallPaper).
type ChatWallpaperSetter interface {
	SetChatWallpaper(chatID string, wallpaper cores.WallpaperInfo, forBoth bool) error
	RevertChatWallpaper(chatID string) error
}

// UploadChatWallpaper uploads an image (JPEG/PNG bytes) as a for-chat
// wallpaper, returning the reference to pass to SetChatWallpaper.
func (e *Engine) UploadChatWallpaper(accountID string, data []byte, mime string, blurred bool) (cores.WallpaperInfo, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return cores.WallpaperInfo{}, fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return cores.WallpaperInfo{}, fmt.Errorf("account not connected: %s", accountID)
	}
	uploader, ok := acc.Core.(ChatWallpaperUploader)
	if !ok {
		return cores.WallpaperInfo{}, fmt.Errorf("platform does not support wallpaper upload")
	}
	return uploader.UploadChatWallpaper(data, mime, blurred)
}

// SetChatWallpaper applies a wallpaper to a private chat and mirrors it
// onto the chat cache row (the GUI renders it immediately; the service
// row lands through the normal update pipeline on the other side).
func (e *Engine) SetChatWallpaper(accountID, chatID string, wallpaper cores.WallpaperInfo, forBoth bool) error {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return fmt.Errorf("account not connected: %s", accountID)
	}
	setter, ok := acc.Core.(ChatWallpaperSetter)
	if !ok {
		return fmt.Errorf("platform does not support chat wallpapers")
	}
	if err := setter.SetChatWallpaper(chatID, wallpaper, forBoth); err != nil {
		return err
	}
	if raw, jerr := json.Marshal(wallpaper); jerr == nil {
		e.db.Exec(
			`UPDATE chats SET wallpaper_json = ? WHERE account_id = ? AND chat_id = ?`,
			string(raw), accountID, chatID)
	}
	return nil
}

// RevertChatWallpaper restores our previous wallpaper in a private chat
// (the answer to an unwanted for-both wallpaper) and clears the mirror.
func (e *Engine) RevertChatWallpaper(accountID, chatID string) error {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return fmt.Errorf("account not connected: %s", accountID)
	}
	setter, ok := acc.Core.(ChatWallpaperSetter)
	if !ok {
		return fmt.Errorf("platform does not support chat wallpapers")
	}
	if err := setter.RevertChatWallpaper(chatID); err != nil {
		return err
	}
	e.db.Exec(
		`UPDATE chats SET wallpaper_json = '' WHERE account_id = ? AND chat_id = ?`,
		accountID, chatID)
	return nil
}
