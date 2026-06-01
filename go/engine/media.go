package engine

import (
	"context"
	"database/sql"
	"fmt"
	"os"
	"path/filepath"
	"strings"
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
	Extra     string // platform-specific metadata (e.g., Telegram access hash + file reference)
	Priority  int    // 0=highest (user tap), 1=visible, 2=prefetch, 3=auto-download
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
		Extra:    job.Extra,
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
	var remoteRef, fileName, mimeType, extra sql.NullString
	err := e.db.QueryRow(
		"SELECT remote_ref, file_name, mime_type, extra FROM media WHERE account_id = ? AND chat_id = ? AND msg_id = ? AND seq = ?",
		accountID, chatID, msgID, seq).Scan(&remoteRef, &fileName, &mimeType, &extra)
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
		Extra:     extra.String,
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

// mediaTypesForTag maps a Local Storage UI cache-tag index to the engine media
// type ids it represents. Tag indices match the Dart Local Storage box rows:
// 0=Images, 1=Stickers, 2=Voice messages, 3=Video messages, 4=Animations,
// 5=Media cache (everything else / big files). Mirrors AyuGram's per-tag cache
// buckets (kImageCacheTag/kStickerCacheTag/… in data/data_cloud_file / cache tags).
func mediaTypesForTag(tag int) []int {
	switch tag {
	case 0:
		return []int{MediaImage}
	case 1:
		return []int{MediaSticker}
	case 2:
		return []int{MediaVoice}
	case 3:
		return []int{MediaVideoNote}
	case 4:
		return []int{MediaGIF}
	case 5:
		return []int{MediaVideo, MediaAudio, MediaFile}
	default:
		return nil
	}
}

// ClearCacheByTag deletes only the cached media files belonging to a single
// Local Storage tag, leaving the rest of the cache intact. This mirrors
// AyuGram's LocalStorageBox::clearByTag (boxes/local_storage_box.cpp:379-389),
// where clicking "Clear" on one row surgically wipes that tag's entries only —
// as opposed to ClearCache which nukes everything. If accountID is non-empty the
// clear is scoped to that account.
func (e *Engine) ClearCacheByTag(accountID string, tag int) error {
	types := mediaTypesForTag(tag)
	if len(types) == 0 {
		return nil
	}

	placeholders := make([]string, len(types))
	args := make([]interface{}, 0, len(types)+1)
	for i, t := range types {
		placeholders[i] = "?"
		args = append(args, t)
	}
	inClause := strings.Join(placeholders, ",")

	selectQ := "SELECT local_path FROM media WHERE local_path IS NOT NULL AND media_type IN (" + inClause + ")"
	updateQ := "UPDATE media SET local_path = NULL, download_state = 0 WHERE media_type IN (" + inClause + ")"
	if accountID != "" {
		selectQ += " AND account_id = ?"
		updateQ += " AND account_id = ?"
		args = append(args, accountID)
	}

	rows, err := e.db.Query(selectQ, args...)
	if err != nil {
		return err
	}
	var paths []string
	for rows.Next() {
		var path string
		rows.Scan(&path)
		paths = append(paths, path)
	}
	rows.Close()

	for _, path := range paths {
		os.Remove(path)
	}
	e.db.Exec(updateQ, args...)
	return nil
}

// maybeEvict enforces all cache limits after a download completes: the
// time-retention window, the per-media ("big files") size cap, and the total
// cache size cap. Mirrors AyuGram's two-database (cache + cacheBig) model with
// independent size limits plus a totalTimeLimit.
func (mm *MediaManager) maybeEvict() {
	mm.evictExpired()
	mm.evictBigMedia()
	mm.evictTotal()
}

// mediaVictim identifies one cached file targeted for eviction.
type mediaVictim struct {
	accID, chatID, msgID, localPath string
	seq                             int
	fileSize                        int64
}

// isThumb reports whether a local path lives in the account's thumbnail dir,
// which is never evicted.
func (e *Engine) isThumb(accID, localPath string) bool {
	return filepath.Dir(localPath) == filepath.Join(e.mediaDir, accID, "thumb")
}

// dropVictim removes the file and clears its DB pointer.
func (e *Engine) dropVictim(v mediaVictim) {
	os.Remove(v.localPath)
	e.db.Exec(
		"UPDATE media SET local_path = NULL, download_state = 0 WHERE account_id = ? AND chat_id = ? AND msg_id = ? AND seq = ?",
		v.accID, v.chatID, v.msgID, v.seq)
}

// bigMediaTypes are the large-file media types accounted against the separate
// "media cache size limit" (AyuGram's cacheBig database): videos, documents,
// music, voice, round videos, and animations.
var bigMediaTypes = []int{MediaVideo, MediaFile, MediaAudio, MediaVoice, MediaVideoNote, MediaGIF}

// evictExpired drops cached media not accessed within the retention window
// (localStorageTimeDays). 0 days == keep forever. Mirrors AyuGram's
// totalTimeLimit eviction.
func (mm *MediaManager) evictExpired() {
	e := mm.engine
	days := e.localStorageTimeDays
	if days <= 0 {
		return
	}
	cutoff := time.Now().Add(-time.Duration(days) * 24 * time.Hour).UnixMilli()
	rows, err := e.db.Query(
		`SELECT account_id, chat_id, msg_id, seq, local_path
		 FROM media
		 WHERE local_path IS NOT NULL AND download_state = ? AND last_accessed < ?`,
		DownloadComplete, cutoff)
	if err != nil {
		return
	}
	var victims []mediaVictim
	for rows.Next() {
		var v mediaVictim
		rows.Scan(&v.accID, &v.chatID, &v.msgID, &v.seq, &v.localPath)
		victims = append(victims, v)
	}
	rows.Close()

	for _, v := range victims {
		if e.isThumb(v.accID, v.localPath) {
			continue
		}
		e.dropVictim(v)
	}
}

// evictBigMedia enforces the independent "media cache" size cap
// (localStorageMediaMB) over large files only, evicting oldest-accessed first.
func (mm *MediaManager) evictBigMedia() {
	e := mm.engine
	if e.localStorageMediaMB <= 0 {
		return
	}
	limit := int64(e.localStorageMediaMB) * 1024 * 1024

	placeholders := make([]string, len(bigMediaTypes))
	typeArgs := make([]interface{}, len(bigMediaTypes))
	for i, t := range bigMediaTypes {
		placeholders[i] = "?"
		typeArgs[i] = t
	}
	inClause := strings.Join(placeholders, ",")

	var size sql.NullInt64
	e.db.QueryRow(
		"SELECT COALESCE(SUM(file_size),0) FROM media WHERE download_state = ? AND local_path IS NOT NULL AND media_type IN ("+inClause+")",
		append([]interface{}{DownloadComplete}, typeArgs...)...).Scan(&size)
	if size.Int64 <= limit {
		return
	}

	rows, err := e.db.Query(
		"SELECT account_id, chat_id, msg_id, seq, local_path, file_size FROM media WHERE local_path IS NOT NULL AND download_state = ? AND media_type IN ("+inClause+") ORDER BY last_accessed ASC",
		append([]interface{}{DownloadComplete}, typeArgs...)...)
	if err != nil {
		return
	}
	var victims []mediaVictim
	for rows.Next() {
		var v mediaVictim
		rows.Scan(&v.accID, &v.chatID, &v.msgID, &v.seq, &v.localPath, &v.fileSize)
		victims = append(victims, v)
	}
	rows.Close()

	cur := size.Int64
	for _, v := range victims {
		if cur <= limit {
			break
		}
		if e.isThumb(v.accID, v.localPath) {
			continue
		}
		e.dropVictim(v)
		cur -= v.fileSize
	}
}

// evictTotal enforces the overall cache size cap (maxCache / total limit),
// evicting oldest-accessed files of any type first.
func (mm *MediaManager) evictTotal() {
	e := mm.engine
	if e.maxCache <= 0 {
		return
	}
	size, _ := e.GetCacheSize()
	if size <= e.maxCache {
		return
	}

	rows, err := e.db.Query(
		`SELECT account_id, chat_id, msg_id, seq, local_path, file_size
		 FROM media
		 WHERE local_path IS NOT NULL AND download_state = ?
		 ORDER BY last_accessed ASC`,
		DownloadComplete)
	if err != nil {
		return
	}
	var victims []mediaVictim
	for rows.Next() {
		var v mediaVictim
		rows.Scan(&v.accID, &v.chatID, &v.msgID, &v.seq, &v.localPath, &v.fileSize)
		victims = append(victims, v)
	}
	rows.Close()

	for _, v := range victims {
		if size <= e.maxCache {
			break
		}
		if e.isThumb(v.accID, v.localPath) {
			continue
		}
		e.dropVictim(v)
		size -= v.fileSize
	}
}
