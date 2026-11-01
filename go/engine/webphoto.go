package engine

import (
	"encoding/json"
	"fmt"
	"time"
)

type webPagePhoto struct {
	PhotoID  string
	Extra    string
	ThumbB64 string
	Width    int
	Height   int
}

func parseWebPagePhoto(raw []byte) (webPagePhoto, bool) {
	if len(raw) == 0 {
		return webPagePhoto{}, false
	}
	var env struct {
		Extra struct {
			ThumbB64 string  `json:"wp_thumb_b64"`
			PhotoID  string  `json:"wp_photo_id"`
			PhotoExt string  `json:"wp_photo_extra"`
			W        float64 `json:"wp_photo_w"`
			H        float64 `json:"wp_photo_h"`
		} `json:"extra"`
	}
	if err := json.Unmarshal(raw, &env); err != nil {
		return webPagePhoto{}, false
	}
	if env.Extra.PhotoID == "" || env.Extra.PhotoExt == "" {
		return webPagePhoto{}, false
	}
	return webPagePhoto{
		PhotoID:  env.Extra.PhotoID,
		Extra:    env.Extra.PhotoExt,
		ThumbB64: env.Extra.ThumbB64,
		Width:    int(env.Extra.W),
		Height:   int(env.Extra.H),
	}, true
}

func webPagePhotoFileName(photoID string) string {
	return "webpage_" + photoID + ".jpg"
}

func (e *Engine) EnsureWebPagePhoto(accountID, chatID, msgID string) error {
	var raw []byte
	if err := e.db.QueryRow(
		"SELECT content_raw FROM messages WHERE account_id = ? AND chat_id = ? AND msg_id = ?",
		accountID, chatID, msgID).Scan(&raw); err != nil {
		return fmt.Errorf("message %s not found: %w", msgID, err)
	}
	ph, ok := parseWebPagePhoto(raw)
	if !ok {
		return fmt.Errorf("message %s has no webpage photo", msgID)
	}

	var curRef string
	var curState int
	err := e.db.QueryRow(
		"SELECT remote_ref, download_state FROM media WHERE account_id = ? AND chat_id = ? AND msg_id = ? AND seq = 0",
		accountID, chatID, msgID).Scan(&curRef, &curState)
	if err == nil && curRef == ph.PhotoID && curState != DownloadFailed {
		return nil
	}

	if _, err := e.db.Exec(
		`INSERT OR REPLACE INTO media
                 (account_id, chat_id, msg_id, seq, media_type, remote_ref, thumb_b64,
                  file_name, mime_type, file_size, width, height, duration_ms,
                  download_state, last_accessed, extra)
                 VALUES (?, ?, ?, 0, ?, ?, ?, ?, ?, 0, ?, ?, 0, ?, ?, ?)`,
		accountID, chatID, msgID, MediaImage, ph.PhotoID, ph.ThumbB64,
		webPagePhotoFileName(ph.PhotoID), "image/jpeg",
		ph.Width, ph.Height,
		DownloadNone, time.Now().UnixMilli(), ph.Extra); err != nil {
		return fmt.Errorf("insert webpage photo row: %w", err)
	}

	if _, err := e.db.Exec(
		"UPDATE messages SET has_media = 1 WHERE account_id = ? AND chat_id = ? AND msg_id = ?",
		accountID, chatID, msgID); err != nil {
		return fmt.Errorf("flag has_media: %w", err)
	}

	return e.RequestDownload(accountID, chatID, msgID, 0, 2)
}
