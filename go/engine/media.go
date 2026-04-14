package engine

import (
	"context"
	"database/sql"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"

	"uniclient/cores"
)

// downloadJob represents a queued media download.
type downloadJob struct {
	AccountID string
	ChatID    string
	MsgID     string
	Seq       int
	RemoteRef string
	FileName  string
	MimeType  string
	Priority  int // 0=highest (user tap), 1=visible, 2=prefetch, 3=auto-download
	cancelFn  context.CancelFunc
}

// MediaManager handles the download queue and LRU cache eviction.
type MediaManager struct {
	engine *Engine

	mu       sync.Mutex
	queue    []*downloadJob
	active   int
	maxConc  int // max concurrent downloads total
	wg       sync.WaitGroup
	notify   chan struct{} // signal to process queue
}

func newMediaManager(e *Engine) *MediaManager {
	mm := &MediaManager{
		engine:  e,
		maxConc: 10,
		notify:  make(chan struct{}, 1),
	}
	return mm
}

// Start begins the download worker loop.
func (mm *MediaManager) Start(ctx context.Context) {
	mm.wg.Add(1)
	go func() {
		defer mm.wg.Done()
		for {
			select {
			case <-ctx.Done():
				return
			case <-mm.notify:
				mm.processQueue()
			}
		}
	}()
}

// Stop waits for all active downloads to complete.
func (mm *MediaManager) Stop() {
	mm.wg.Wait()
}

// Enqueue adds a download job to the priority queue.
func (mm *MediaManager) Enqueue(job *downloadJob) {
	mm.mu.Lock()
	defer mm.mu.Unlock()

	// Insert sorted by priority (lower = higher priority).
	inserted := false
	for i, j := range mm.queue {
		if job.Priority < j.Priority {
			mm.queue = append(mm.queue[:i+1], mm.queue[i:]...)
			mm.queue[i] = job
			inserted = true
			break
		}
	}
	if !inserted {
		mm.queue = append(mm.queue, job)
	}

	// Signal worker.
	select {
	case mm.notify <- struct{}{}:
	default:
	}
}

// Cancel removes a download from the queue or cancels an active one.
func (mm *MediaManager) Cancel(accountID, chatID, msgID string, seq int) {
	mm.mu.Lock()
	defer mm.mu.Unlock()

	for i, j := range mm.queue {
		if j.AccountID == accountID && j.ChatID == chatID && j.MsgID == msgID && j.Seq == seq {
			if j.cancelFn != nil {
				j.cancelFn()
			}
			mm.queue = append(mm.queue[:i], mm.queue[i+1:]...)
			return
		}
	}
}

func (mm *MediaManager) processQueue() {
	for {
		mm.mu.Lock()
		if mm.active >= mm.maxConc || len(mm.queue) == 0 {
			mm.mu.Unlock()
			return
		}
		job := mm.queue[0]
		mm.queue = mm.queue[1:]
		mm.active++
		mm.mu.Unlock()

		mm.wg.Add(1)
		go func() {
			defer mm.wg.Done()
			mm.executeDownload(job)
			mm.mu.Lock()
			mm.active--
			mm.mu.Unlock()
			// Try next.
			select {
			case mm.notify <- struct{}{}:
			default:
			}
		}()
	}
}

func (mm *MediaManager) executeDownload(job *downloadJob) {
	e := mm.engine

	// Get core.
	acc, ok := e.getAccount(job.AccountID)
	if !ok || acc.Core == nil {
		return
	}

	// Determine local path.
	dir := filepath.Join(e.mediaDir, job.AccountID, "full")
	os.MkdirAll(dir, 0o755)

	ext := filepath.Ext(job.FileName)
	if ext == "" {
		ext = ".bin"
	}
	localPath := filepath.Join(dir, job.MsgID+"_"+fmt.Sprint(job.Seq)+ext)

	// Update state to downloading.
	e.db.Exec(
		"UPDATE media SET download_state = ? WHERE account_id = ? AND chat_id = ? AND msg_id = ? AND seq = ?",
		DownloadInProgress, job.AccountID, job.ChatID, job.MsgID, job.Seq)

	// Create file ref for download.
	ref := cores.FileRef{
		ID:       job.RemoteRef,
		Name:     job.FileName,
		MimeType: job.MimeType,
	}

	// Download with progress reporting.
	lastProgress := time.Now()
	err := acc.Core.DownloadFile(ref, localPath, func(recv, total int64) {
		if time.Since(lastProgress) < 100*time.Millisecond {
			return
		}
		lastProgress = time.Now()
		e.emitEvent(EventDownloadProgress, job.AccountID, DownloadProgressEvent{
			AccountID:  job.AccountID,
			ChatID:     job.ChatID,
			MsgID:      job.MsgID,
			Seq:        job.Seq,
			BytesRecv:  recv,
			BytesTotal: total,
		})
	})

	if err != nil {
		e.db.Exec(
			"UPDATE media SET download_state = ? WHERE account_id = ? AND chat_id = ? AND msg_id = ? AND seq = ?",
			DownloadFailed, job.AccountID, job.ChatID, job.MsgID, job.Seq)
		return
	}

	// Update media record.
	now := time.Now().UnixMilli()
	e.db.Exec(
		`UPDATE media SET local_path = ?, download_state = ?, last_accessed = ?
		 WHERE account_id = ? AND chat_id = ? AND msg_id = ? AND seq = ?`,
		localPath, DownloadComplete, now, job.AccountID, job.ChatID, job.MsgID, job.Seq)

	e.emitEvent(EventDownloadComplete, job.AccountID, DownloadCompleteEvent{
		AccountID: job.AccountID,
		ChatID:    job.ChatID,
		MsgID:     job.MsgID,
		Seq:       job.Seq,
		LocalPath: localPath,
	})

	// Check if eviction is needed.
	mm.maybeEvict()
}

// RequestDownload queues a download for a media attachment.
func (e *Engine) RequestDownload(accountID, chatID, msgID string, seq, priority int) error {
	var remoteRef, fileName, mimeType sql.NullString
	err := e.db.QueryRow(
		"SELECT remote_ref, file_name, mime_type FROM media WHERE account_id = ? AND chat_id = ? AND msg_id = ? AND seq = ?",
		accountID, chatID, msgID, seq).Scan(&remoteRef, &fileName, &mimeType)
	if err != nil {
		return fmt.Errorf("media ref not found: %w", err)
	}

	if e.media == nil {
		return fmt.Errorf("media manager not initialized")
	}

	e.media.Enqueue(&downloadJob{
		AccountID: accountID,
		ChatID:    chatID,
		MsgID:     msgID,
		Seq:       seq,
		RemoteRef: remoteRef.String,
		FileName:  fileName.String,
		MimeType:  mimeType.String,
		Priority:  priority,
	})
	return nil
}

// CancelDownload cancels a pending or active download.
func (e *Engine) CancelDownload(accountID, chatID, msgID string, seq int) {
	if e.media != nil {
		e.media.Cancel(accountID, chatID, msgID, seq)
	}
}

// GetCacheSize returns the total size of downloaded media files.
func (e *Engine) GetCacheSize() (int64, error) {
	var total sql.NullInt64
	err := e.db.QueryRow(
		"SELECT COALESCE(SUM(file_size), 0) FROM media WHERE download_state = ?",
		DownloadComplete).Scan(&total)
	if err != nil {
		return 0, err
	}
	return total.Int64, nil
}

// ClearCache deletes all downloaded media. If accountID is non-empty, only for that account.
func (e *Engine) ClearCache(accountID string) error {
	var rows *sql.Rows
	var err error
	if accountID != "" {
		rows, err = e.db.Query(
			"SELECT local_path FROM media WHERE account_id = ? AND local_path IS NOT NULL",
			accountID)
	} else {
		rows, err = e.db.Query(
			"SELECT local_path FROM media WHERE local_path IS NOT NULL")
	}
	if err != nil {
		return err
	}
	defer rows.Close()

	for rows.Next() {
		var path string
		rows.Scan(&path)
		os.Remove(path)
	}

	if accountID != "" {
		e.db.Exec("UPDATE media SET local_path = NULL, download_state = 0 WHERE account_id = ?", accountID)
	} else {
		e.db.Exec("UPDATE media SET local_path = NULL, download_state = 0")
	}
	return nil
}

// maybeEvict runs LRU eviction if cache exceeds max size.
func (mm *MediaManager) maybeEvict() {
	e := mm.engine
	if e.maxCache <= 0 {
		return
	}

	size, _ := e.GetCacheSize()
	if size <= e.maxCache {
		return
	}

	// Evict oldest-accessed files until under limit.
	rows, err := e.db.Query(
		`SELECT account_id, chat_id, msg_id, seq, local_path, file_size
		 FROM media
		 WHERE local_path IS NOT NULL AND download_state = ?
		 ORDER BY last_accessed ASC`,
		DownloadComplete)
	if err != nil {
		return
	}
	defer rows.Close()

	for rows.Next() && size > e.maxCache {
		var accID, chatID, msgID, localPath string
		var seq int
		var fileSize int64
		rows.Scan(&accID, &chatID, &msgID, &seq, &localPath, &fileSize)

		// Never evict thumbnails.
		if filepath.Dir(localPath) == filepath.Join(e.mediaDir, accID, "thumb") {
			continue
		}

		os.Remove(localPath)
		e.db.Exec(
			"UPDATE media SET local_path = NULL, download_state = 0 WHERE account_id = ? AND chat_id = ? AND msg_id = ? AND seq = ?",
			accID, chatID, msgID, seq)
		size -= fileSize
	}
}
