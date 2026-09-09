package engine

// Save-to-Downloads (slice 99, matrix row 158): the engine-facing half of
// AyuGram's "save file / save GIF / save sound" — copies a message's
// downloaded media file into the user's downloads directory with a
// collision-safe name. The GUI drives it from the media viewer and the
// message context menu; undownloaded media reports the honest
// ErrMediaNotDownloaded sentinel so the caller can start a download and
// retry on completion.

import (
	"database/sql"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
)

// ErrMediaNotDownloaded: the message's media has no local file yet — the
// caller should RequestDownload and retry once EventDownloadComplete
// fires.
var ErrMediaNotDownloaded = errors.New("media not downloaded yet")

// SaveMessageMediaToDownloads copies the message's seq-N media file into
// the downloads directory and returns the destination path. The name
// prefers the stored file name (sanitized), falling back to the cache
// file's base name; an existing file of the same name is never
// overwritten ("photo (1).jpg", …).
func (e *Engine) SaveMessageMediaToDownloads(accountID, chatID, msgID string, seq int) (string, error) {
	if seq < 0 {
		seq = 0
	}
	var localPath, fileName sql.NullString
	err := e.db.QueryRow(
		`SELECT local_path, file_name FROM media
                 WHERE account_id = ? AND chat_id = ? AND msg_id = ? AND seq = ?`,
		accountID, chatID, msgID, seq,
	).Scan(&localPath, &fileName)
	if errors.Is(err, sql.ErrNoRows) {
		return "", fmt.Errorf("no media for message %s", msgID)
	}
	if err != nil {
		return "", err
	}
	if !localPath.Valid || localPath.String == "" {
		return "", ErrMediaNotDownloaded
	}

	e.mu.RLock()
	dir := e.downloadDir
	e.mu.RUnlock()
	if dir == "" {
		return "", fmt.Errorf("no downloads directory configured")
	}

	name := sanitizeDownloadName(fileName.String, localPath.String)
	dest := uniqueDownloadPath(dir, name)
	if err := copyFile(localPath.String, dest); err != nil {
		return "", err
	}
	return dest, nil
}

// sanitizeDownloadName picks the saved file name: the stored name when
// usable, else the cache path's base. Path separators in a stored name
// never escape the downloads dir (both separators stripped, then the
// base taken again).
func sanitizeDownloadName(stored, cachePath string) string {
	name := strings.TrimSpace(stored)
	if name != "" {
		name = strings.ReplaceAll(name, "\\", "/")
		name = strings.Trim(name, "/")
		name = filepath.Base(name)
	}
	if name == "" || name == "." || name == ".." {
		name = filepath.Base(cachePath)
	}
	if name == "" || name == "." || name == ".." {
		name = "file"
	}
	return name
}

// uniqueDownloadPath: dir/name, or dir/"name (N).ext" when a file already
// sits there — the first free slot, never an overwrite.
func uniqueDownloadPath(dir, name string) string {
	ext := filepath.Ext(name)
	stem := strings.TrimSuffix(name, ext)
	candidate := filepath.Join(dir, name)
	for i := 1; ; i++ {
		if _, err := os.Stat(candidate); errors.Is(err, os.ErrNotExist) {
			return candidate
		}
		candidate = filepath.Join(dir, fmt.Sprintf("%s (%d)%s", stem, i, ext))
	}
}

// copyFile streams src to dst (large media never fully buffered).
func copyFile(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	out, err := os.Create(dst)
	if err != nil {
		return err
	}
	defer out.Close()
	if _, err := io.Copy(out, in); err != nil {
		return err
	}
	return out.Sync()
}
