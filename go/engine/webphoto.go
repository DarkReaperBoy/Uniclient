package engine

// webphoto.go — slice 130: full-resolution thumbs for link-preview cards.
// The telegram core exports the webpage photo's download coordinates in
// the message Extra (wp_photo_id / wp_photo_extra); this file turns them
// into a standard media row on demand so the normal download pipeline
// fetches the real image — the exact EnsureDiceSticker pattern (dice.go),
// applied to messages whose media is a MessageMediaWebPage.
//
// Why a media row and not a bespoke fetch: the pipeline already gives us
// priority scheduling, progress state, retry, the cache-dir layout and the
// ClearCache-by-tag accounting. The GUI's link-preview card then reads
// MediaLocalPath like any photo bubble.

import (
	"encoding/json"
	"fmt"
	"time"
)

// jsonUnmarshal is a tiny alias keeping the parser's dependency obvious.
var jsonUnmarshal = json.Unmarshal

// webPagePhoto is the parsed download coordinate set of a message's
// webpage photo.
type webPagePhoto struct {
	PhotoID  string
	Extra    string
	ThumbB64 string
	Width    int
	Height   int
}

// parseWebPagePhoto extracts the webpage photo coordinates from a cached
// message's raw JSON. ok=false when the message has no usable photo (no
// webpage, no photo, or no download extra). Pure — unit-tested.
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

// webPagePhotoFileName is the stable download file name for a page photo.
func webPagePhotoFileName(photoID string) string {
	return "webpage_" + photoID + ".jpg"
}

// EnsureWebPagePhoto resolves a link-preview message's photo into a media
// row and prefetches it (priority 2, the avatar/dice tier). Idempotent: a
// row already pointing at the photo is left alone unless its download
// failed (which re-arms). Messages without webpage photo coordinates
// return an error the GUI treats as "nothing to do".
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

	// Already resolved (in flight or complete)? A failed row re-arms.
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

	// populateMediaMetadata gates on has_media — the card's local thumb
	// only surfaces when the flag is set.
	if _, err := e.db.Exec(
		"UPDATE messages SET has_media = 1 WHERE account_id = ? AND chat_id = ? AND msg_id = ?",
		accountID, chatID, msgID); err != nil {
		return fmt.Errorf("flag has_media: %w", err)
	}

	return e.RequestDownload(accountID, chatID, msgID, 0, 2)
}
