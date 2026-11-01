package engine

import (
	"encoding/json"
	"fmt"

	"uniclient/cores"
)

type ChatWallpaperUploader interface {
	UploadChatWallpaper(data []byte, mime string, blurred bool) (cores.WallpaperInfo, error)
}

type ChatWallpaperSetter interface {
	SetChatWallpaper(chatID string, wallpaper cores.WallpaperInfo, forBoth bool) error
	RevertChatWallpaper(chatID string) error
}

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
