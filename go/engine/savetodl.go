package engine

import (
	"database/sql"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
)

var ErrMediaNotDownloaded = errors.New("media not downloaded yet")

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
	dest := UniqueDownloadPath(dir, name)
	if err := copyFile(localPath.String, dest); err != nil {
		return "", err
	}
	return dest, nil
}

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

func UniqueDownloadPath(dir, name string) string {
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
